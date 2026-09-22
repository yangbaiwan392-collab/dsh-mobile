// 真功能测试：不是"能加载"，而是"真的能锁、且第二个 fd 会被拒"。
// 放在 ~/dsh-install 里运行，好让 '@deepseek-ai/node-addon-system/flock' 能被解析。
import { closeSync, openSync, writeFileSync } from 'node:fs';
import { tryLockExclusive } from '@deepseek-ai/node-addon-system/flock';

const path = process.argv[2];
writeFileSync(path, '');

const first = openSync(path, 'r+');
await tryLockExclusive(first);
console.log('第一次加锁：成功 ✓');

const second = openSync(path, 'r+');
try {
  await tryLockExclusive(second);
  console.log('第二次加锁：意外成功 ✗（flock 语义没生效）');
  process.exitCode = 1;
} catch (error) {
  console.log('第二次加锁：被拒（' + (error && error.code) + '）✓ 这正是 flock 该有的行为');
}

closeSync(first);
closeSync(second);
console.log('flock 在 ' + process.platform + '-' + process.arch + ' 上可用 ✓');
