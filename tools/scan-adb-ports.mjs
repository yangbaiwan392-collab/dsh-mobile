// 扫出手机无线调试的端口（配对端口与连接端口都是随机高位端口，手机上不好找）。
//
// 用法：node tools/scan-adb-ports.mjs 192.168.0.104 [起始端口] [结束端口]
// 默认扫 30000-49999（Android adb 无线调试的常见区间），外加 5555 与 1023。
//
// 只做 TCP connect 探测，不发任何数据 —— 不会触发认证，也不改手机状态。
import net from 'node:net';

const host = process.argv[2];
const from = Number(process.argv[3] ?? 30000);
const to = Number(process.argv[4] ?? 49999);
if (!host) {
  console.error('用法：node tools/scan-adb-ports.mjs <ip> [起始端口] [结束端口]');
  process.exit(2);
}

const TIMEOUT_MS = 900;
const CONCURRENCY = 400;

function probe(port) {
  return new Promise((resolve) => {
    const socket = net.connect({ host, port });
    const done = (open) => {
      socket.removeAllListeners();
      socket.destroy();
      resolve(open ? port : null);
    };
    socket.setTimeout(TIMEOUT_MS);
    socket.once('connect', () => done(true));
    socket.once('timeout', () => done(false));
    socket.once('error', () => done(false));
  });
}

const ports = [5555, 1023];
for (let p = from; p <= to; p += 1) ports.push(p);

const open = [];
let index = 0;
let scanned = 0;
const started = Date.now();

async function worker() {
  while (index < ports.length) {
    const port = ports[index];
    index += 1;
    const found = await probe(port);
    scanned += 1;
    if (found) {
      open.push(found);
      console.log(`  开放端口：${host}:${found}`);
    }
  }
}

const workers = Array.from({ length: CONCURRENCY }, worker);
await Promise.all(workers);

const seconds = ((Date.now() - started) / 1000).toFixed(1);
const asJson = process.argv.includes('--json');
if (asJson) {
  console.log(JSON.stringify({ host, open: open.sort((a, b) => a - b), scanned, seconds: Number(seconds) }));
} else {
  console.log(`\n扫了 ${scanned} 个端口，用时 ${seconds}s`);
  if (open.length === 0) {
    console.log('没有发现开放端口 —— 可能：无线调试没打开 / 手机不在同一网段 / 路由器开了 AP 隔离 / 代码不在扫描区间内');
  } else {
    console.log('开放端口：' + open.join(', '));
    console.log('下一步：adb pair ' + host + ':<配对端口> <6位配对码>，然后 adb connect ' + host + ':<连接端口>');
  }
}
