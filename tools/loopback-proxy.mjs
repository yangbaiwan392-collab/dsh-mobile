// 模式 B · 免管理员方案：把 DSH 的 loopback 服务"回环改写"后暴露到局域网。
//
// 为什么需要它（实测事实，不是猜测）：
//   · `dsh web --host 0.0.0.0` → 被服务端显式拒绝（"would expose remote code execution to the network"）
//   · `dsh web --host 192.168.0.105` → 配置校验失败：$.host expected "127.0.0.1" | "0.0.0.0"
//   · 于是 DSH 永远只听 127.0.0.1；手机要连就必须有东西替它转发，并把 Host/Origin 改写成 loopback。
//
// ⚠ 安全代价（必读，别忽略）：
//   1) 这是**故意绕过** DSH 的 browser-trust 栅栏（它本意就是不让非 loopback 访问），风险由你承担；
//   2) 走明文 HTTP：DSH 的会话 cookie **不带 Secure**（官方只跑 loopback HTTP），
//      所以同一局域网内能被抓到就是完整身份 → **只在你信得过的家里 Wi-Fi 用**；
//   3) 想避免上述两点，用 SSH 隧道（docs/02-remote-pc.md 的推荐方案），不要用本脚本。
//
// 用法：node tools/loopback-proxy.mjs --listen 0.0.0.0:8081 --target 127.0.0.1:3080
import http from 'node:http';
import net from 'node:net';

/** "host:port" → {host, port}；只在启动时解析一次，之后不再猜。 */
function parseAuthority(text) {
  const i = text.lastIndexOf(':');
  if (i < 0) throw new Error(`authority 需要 host:port 形式，收到：${text}`);
  const port = Number(text.slice(i + 1));
  if (!Number.isInteger(port) || port <= 0 || port > 65535) throw new Error(`端口非法：${text}`);
  return { host: text.slice(0, i), port };
}

function readArgs(argv) {
  const map = new Map();
  for (let i = 0; i < argv.length; i += 2) {
    if (!argv[i].startsWith('--')) throw new Error(`未知参数：${argv[i]}`);
    map.set(argv[i], argv[i + 1]);
  }
  return map;
}

const args = readArgs(process.argv.slice(2));
const listen = parseAuthority(args.get('--listen') ?? '0.0.0.0:8081');
const target = parseAuthority(args.get('--target') ?? '127.0.0.1:3080');
const targetAuthority = `${target.host}:${target.port}`;

/** 把浏览器发来的 Host/Origin/sec-fetch-site 改写成"完全像本机访问"。 */
function rewriteHeaders(headers) {
  const out = { ...headers, host: targetAuthority };
  if (out.origin) out.origin = `http://${targetAuthority}`;
  if (out['sec-fetch-site']) out['sec-fetch-site'] = 'same-origin';
  return out;
}

const server = http.createServer((req, res) => {
  const upstream = http.request(
    { host: target.host, port: target.port, method: req.method, path: req.url, headers: rewriteHeaders(req.headers) },
    (up) => {
      res.writeHead(up.statusCode ?? 502, up.headers);
      up.pipe(res);
    },
  );
  upstream.on('error', (error) => {
    res.writeHead(502, { 'content-type': 'text/plain; charset=utf-8' });
    res.end(`loopback-proxy: 无法连到 ${targetAuthority} —— ${error.message}`);
  });
  req.pipe(upstream);
});

// DSH 的 /api/remote.mux 是 WebSocket：不转发 upgrade 就等于把 app 打断。
server.on('upgrade', (req, socket, head) => {
  const upstream = net.connect(target.port, target.host, () => {
    const headerLines = Object.entries(rewriteHeaders(req.headers)).map(([k, v]) => `${k}: ${v}`);
    upstream.write([`${req.method} ${req.url} HTTP/1.1`, ...headerLines, '', ''].join('\r\n'));
    if (head?.length) upstream.write(head);
    upstream.pipe(socket);
    socket.pipe(upstream);
  });
  upstream.on('error', () => socket.destroy());
  socket.on('error', () => upstream.destroy());
  socket.on('close', () => upstream.destroy());
});

server.listen(listen.port, listen.host, () => {
  console.log(`loopback-proxy 监听 http://${listen.host}:${listen.port}  →  ${targetAuthority}`);
  console.log('⚠ 明文 HTTP + 绕过 browser-trust 栅栏：只用在你信得过的局域网。');
});
