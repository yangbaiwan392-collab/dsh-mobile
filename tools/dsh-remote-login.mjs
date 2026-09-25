#!/usr/bin/env node
/**
 * dsh-remote-login.mjs — 给「手机 / 另一台设备」发一张 DSH Web 的 30 天登录 cookie。
 *
 * 为什么需要它
 * ------------
 * `dsh web` 的浏览器凭据有两层（见 @deepseek-ai/dsh-client-connection 的 browser-auth）：
 *
 *   1. 启动时打印的 `?token=<本次进程随机>` —— 它只是一次性的「兑换入口」，
 *      进程一重启就作废，且无法从运行中的进程里读出来；
 *   2. 真正长期生效的是它兑换出来的 cookie：`dsh-auth-<hash(authority)>`，
 *      内容是用 ~/.dsh 里一条**持久化**的 32 字节签名密钥做的 HMAC-SHA256。
 *
 * 密钥是持久的 → 谁拿到本机的 ~/.dsh，谁就能签出任意 authority 的 cookie。
 * 本工具就是把这件事做成一条命令：签一张给指定 authority 的 cookie，
 * 并通过一个「一次性入口页」把它种进目标设备的浏览器。
 *
 * 为什么要那个入口页
 * ------------------
 * cookie 是按 **主机名** 绑定的（同主机不同端口共享）。手机浏览器要拿到的 cookie
 * 必须属于 `<主机名>.<你的 tailnet>.ts.net`，所以承载 `Set-Cookie` 的页面也必须从
 * 这个主机名提供 —— 于是：本脚本监听 127.0.0.1，由
 * `tailscale serve --https=<另一个端口>` 把它挂到同一个组网主机名上；
 * 手机访问 `https://<主机名>.<你的 tailnet>.ts.net:<port>/__login?c=<一次性口令>`，
 * 拿到 cookie 后 303 跳到 GUI。cookie 与端口无关，所以 443 上的 GUI 立刻可用。
 *
 * 安全边界
 * --------
 *   - 只监听 127.0.0.1，永远不直接对外；能被手机访问纯粹是因为 tailscale serve
 *     把它挂在组网内（公网不可达）。
 *   - 入口页要求一次性口令（随机 16 字节），且默认 10 分钟自动关闭；
 *     口令写在 URL 里，不落日志。
 *   - cookie 有效期默认 30 天，与 `dsh web` 自己发的完全一致；
 *     想立刻作废所有浏览器会话：删掉 ~/.dsh/.credentials.yaml 里
 *     `client-connection/browser-session` 那条记录（PC 上的窗口也要重新登录）。
 *
 * 用法
 * ----
 *   node dsh-remote-login.mjs --authority <主机名>.<你的 tailnet>.ts.net --print-cookie
 *   node dsh-remote-login.mjs --authority 127.0.0.1:3080            # 自检：打印指纹，不打印 cookie
 *   node dsh-remote-login.mjs --authority <主机名>.<你的 tailnet>.ts.net \
 *        --port 3088 --url-file .remote-login-url --ttl-minutes 10  # 起一次性入口页
 */
import { createHash, createHmac, randomBytes, timingSafeEqual } from 'node:crypto';
import { readFileSync, writeFileSync } from 'node:fs';
import { createServer } from 'node:http';
import os from 'node:os';
import path from 'node:path';

const CREDENTIALS = path.join(os.homedir(), '.dsh', '.credentials.yaml');
const RECORD_KEY = 'client-connection/browser-session';
const DAY_MILLISECONDS = 86_400_000;
const SECRET_BYTES = 32;

function fail(message) {
  console.error(`dsh-remote-login: ${message}`);
  process.exit(1);
}

function parseArgs(argv) {
  const out = {
    authority: null,
    port: 3088,
    // 对外 URL 用的端口：本脚本只监听 127.0.0.1:<port>，真正暴露给手机的是
    // `tailscale serve --https=<publicPort>` 那一条，两者通常不同，必须分开给。
    publicPort: null,
    publicHost: null,
    urlFile: null,
    ttlMinutes: 10,
    days: 30,
    mode: 'serve',
  };
  for (let i = 0; i < argv.length; i += 1) {
    const key = argv[i];
    const next = () => {
      const value = argv[i + 1];
      if (value === undefined) fail(`${key} 缺少取值`);
      i += 1;
      return value;
    };
    switch (key) {
      case '--authority': out.authority = next(); break;
      case '--port': out.port = Number(next()); break;
      case '--public-port': out.publicPort = Number(next()); break;
      case '--public-host': out.publicHost = next(); break;
      case '--url-file': out.urlFile = next(); break;
      case '--ttl-minutes': out.ttlMinutes = Number(next()); break;
      case '--days': out.days = Number(next()); break;
      case '--print-cookie': out.mode = 'print-cookie'; break;
      case '--check': out.mode = 'check'; break;
      case '--serve': out.mode = 'serve'; break;
      default: fail(`未知参数 ${key}`);
    }
  }
  if (out.authority === null) fail('必须给 --authority（例如 <主机名>.<你的 tailnet>.ts.net 或 127.0.0.1:3080）');
  if (!Number.isInteger(out.port) || out.port <= 0 || out.port > 65535) fail('--port 必须是 1..65535 的整数');
  if (!Number.isInteger(out.days) || out.days <= 0) fail('--days 必须是正整数');
  return out;
}

/** base64url（与 dsh 内部 encodeBase64Url 完全一致：无填充、+→-、/→_）。 */
function base64Url(value) {
  return Buffer.from(value).toString('base64').replaceAll('+', '-').replaceAll('/', '_').replace(/=+$/u, '');
}

/**
 * 从 ~/.dsh/.credentials.yaml 里取出持久签名密钥。
 * 只做定点提取（不引入 YAML 依赖），并校验长度必须是 32 字节 —— 与 dsh 的
 * canonicalSecret() 同一条约束，格式不符就报错而不是硬用。
 */
function loadSecret() {
  let text;
  try {
    text = readFileSync(CREDENTIALS, 'utf8');
  } catch (error) {
    fail(`读不到 ${CREDENTIALS}：${error.message}（先跑一次 dsh web，让它把密钥种下来）`);
  }
  const lines = text.split(/\r?\n/u);
  const start = lines.findIndex((line) => line.trimEnd() === `  ${RECORD_KEY}:`);
  if (start === -1) fail(`${CREDENTIALS} 里没有 ${RECORD_KEY} 记录（先跑一次 dsh web）`);
  for (let i = start + 1; i < lines.length; i += 1) {
    if (/^\S/u.test(lines[i]) && lines[i].trim() !== '') break;
    const match = /^\s+secret:\s*(\S+)\s*$/u.exec(lines[i]);
    if (match === null) continue;
    const secret = Buffer.from(match[1].replaceAll('-', '+').replaceAll('_', '/'), 'base64');
    if (secret.byteLength !== SECRET_BYTES) fail(`签名密钥长度不对（${secret.byteLength} 字节，应为 ${SECRET_BYTES}）`);
    return secret;
  }
  fail(`${RECORD_KEY} 记录里没有 secret 字段`);
}

function cookieName(authority) {
  return `dsh-auth-${base64Url(createHash('sha256').update(authority).digest())}`;
}

/** 与 dsh 的 encodeCookie() 同构：v1.<payload>.<hmac>，HMAC 覆盖 payload 的 base64url 文本。 */
function encodeCookie(payload, secret) {
  const body = base64Url(Buffer.from(JSON.stringify(payload), 'utf8'));
  return `v1.${body}.${base64Url(createHmac('sha256', secret).update(body).digest())}`;
}

/**
 * 同一张凭据，两种 SameSite：
 *
 *  - `Strict` 与 dsh 自己发的 cookie 一致。PC 上的启动器每次都用「带 token 的地址」
 *    重新种 cookie，那条路径是同站跳转，Strict 照发不误 —— 所以 PC 从来不会碰到问题。
 *  - 但手机不一样：实测（Android Chrome + CDP 抓包）从**外部 intent / 书签**发起的顶层
 *    导航，Chrome 判定 initiator 为跨站，`SameSite=Strict` 的 cookie **根本不会被带上**，
 *    于是每次点开都看到 "dsh web authentication required"。`Lax` 正是为「顶层 GET 导航」
 *    放行的档位，所以发给手机时用 Lax。
 *
 * 安全性：Lax 只对顶层 GET 生效，而 dsh 的危险操作都走 /api 的 POST / WebSocket，
 * 且 Host/Origin 信任栅栏会挡掉跨站来源；再加上这个入口本身只在组网内可达。
 */
const COOKIE_SAME_SITE_FOR_BROWSER = 'Lax';

function mint(authority, secret, days, sameSite = COOKIE_SAME_SITE_FOR_BROWSER) {
  const issuedAt = Date.now();
  const expiresAt = issuedAt + days * DAY_MILLISECONDS;
  const value = encodeCookie({ version: 1, authority, issuedAt, expiresAt }, secret);
  const maxAge = Math.floor((days * DAY_MILLISECONDS) / 1000);
  const cookie = `${cookieName(authority)}=${value}; Max-Age=${String(maxAge)}; Path=/; `
    + `Expires=${new Date(expiresAt).toUTCString()}; HttpOnly; SameSite=${sameSite}`;
  return { cookie, value, issuedAt, expiresAt };
}

function fingerprint(secret) {
  return createHash('sha256').update(secret).digest('hex').slice(0, 16);
}

const args = parseArgs(process.argv.slice(2));
const secret = loadSecret();

if (args.mode === 'check') {
  const { cookie, expiresAt } = mint(args.authority, secret, args.days);
  console.log(`authority      = ${args.authority}`);
  console.log(`cookie name    = ${cookieName(args.authority)}`);
  console.log(`secret fp      = ${fingerprint(secret)}（密钥本身不外显）`);
  console.log(`cookie 长度    = ${cookie.length}`);
  console.log(`过期           = ${new Date(expiresAt).toISOString()}`);
  process.exit(0);
}

if (args.mode === 'print-cookie') {
  // 只打印 `name=value`，供 curl / Invoke-WebRequest 直接塞进 Cookie 头；不含属性。
  const { cookie } = mint(args.authority, secret, args.days);
  process.stdout.write(cookie.split(';')[0]);
  process.exit(0);
}

// ---- serve：一次性入口页 --------------------------------------------------
const code = base64Url(randomBytes(16));
const target = `https://${args.authority}/`;
let used = false;

const server = createServer((req, res) => {
  const url = new URL(req.url ?? '/', 'http://placeholder.invalid');
  if (url.pathname === '/__health') {
    res.writeHead(200, { 'content-type': 'text/plain; charset=utf-8', 'cache-control': 'no-store' });
    res.end(`ok used=${String(used)}\n`);
    return;
  }
  if (url.pathname !== '/__login') {
    res.writeHead(404, { 'content-type': 'text/plain; charset=utf-8' });
    res.end('dsh-remote-login: 这里只有 /__login（一次性登录入口）\n');
    return;
  }
  const given = Buffer.from(url.searchParams.get('c') ?? '', 'utf8');
  const expected = Buffer.from(code, 'utf8');
  const matches = given.byteLength === expected.byteLength && timingSafeEqual(given, expected);
  if (!matches) {
    res.writeHead(401, { 'content-type': 'text/plain; charset=utf-8', 'cache-control': 'no-store' });
    res.end('dsh-remote-login: 口令不对\n');
    return;
  }
  const { cookie } = mint(args.authority, secret, args.days);
  used = true;
  console.log(`[${new Date().toISOString()}] 已把 cookie 发给 ${req.socket.remoteAddress ?? '?'}`);
  res.writeHead(303, {
    'cache-control': 'no-store',
    'referrer-policy': 'no-referrer',
    location: target,
    'set-cookie': cookie,
  });
  res.end();
});

server.listen(args.port, '127.0.0.1', () => {
  // 对外地址由 --public-host/--public-port 决定（tailscale serve 映射后的那一个），
  // 缺省时才退回本机监听地址。443 是 https 默认端口，写进 URL 反而多余。
  const host = args.publicHost ?? args.authority;
  const port = args.publicPort ?? args.port;
  const portPart = port === 443 ? '' : `:${String(port)}`;
  const loginUrl = `https://${host}${portPart}/__login?c=${code}`;
  if (args.urlFile !== null) {
    writeFileSync(args.urlFile, loginUrl, 'utf8');
    console.log(`dsh-remote-login: 入口页已就绪，URL 写入 ${args.urlFile}（含一次性口令，不打印）`);
  } else {
    console.log(`dsh-remote-login: 入口页已就绪：${loginUrl}`);
  }
  console.log(`dsh-remote-login: 监听 127.0.0.1:${String(args.port)}（对外 https://${host}${portPart}），${String(args.ttlMinutes)} 分钟后自动退出`);
});

const timer = setTimeout(() => {
  console.log('dsh-remote-login: 到期，关闭');
  server.close(() => { process.exit(0); });
}, args.ttlMinutes * 60_000);
timer.unref?.();

for (const signal of ['SIGINT', 'SIGTERM']) {
  process.on(signal, () => {
    server.close(() => { process.exit(0); });
  });
}
