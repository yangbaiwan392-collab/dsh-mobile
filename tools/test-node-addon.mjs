// 探测：某个 .node 原生模块能不能在 Android/Bionic 上加载（不能只看有没有文件）。
// 用法： node test-node-addon.mjs <候选路径>...
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
for (const candidate of process.argv.slice(2)) {
  try {
    const mod = require(candidate);
    console.log('LOAD OK  ', candidate, 'exports=' + Object.keys(mod).join(','));
  } catch (error) {
    const code = error && error.code ? error.code : '';
    const message = error && error.message ? error.message.split('\n')[0] : String(error);
    console.log('LOAD FAIL', candidate, '->', code, message);
  }
}
console.log('platform=' + process.platform + '-' + process.arch);
