// 解开 DSH 的会话日志（多帧 zstd）。
//
// 为什么需要专门写：DSH 的会话日志是**多帧** zstd —— 直接 zstdDecompressSync 只解第一帧，
// 剩下的会被忽略（看起来"只有一条记录"）。必须按 magic 0x28B52FFD 切帧逐帧解。
//
// 用法：
//   node tools/decode-session-log.mjs <文件.zstd>
//   或先 base64 取回：  ... | node tools/decode-session-log.mjs --base64
import { readFileSync } from 'node:fs';
import { zstdDecompressSync } from 'node:zlib';

const MAGIC = Buffer.from([0x28, 0xb5, 0x2f, 0xfd]);

function splitFrames(buffer) {
  const offsets = [];
  let index = buffer.indexOf(MAGIC, 0);
  while (index !== -1) {
    offsets.push(index);
    index = buffer.indexOf(MAGIC, index + MAGIC.length);
  }
  return offsets.map((start, i) => buffer.subarray(start, i + 1 < offsets.length ? offsets[i + 1] : buffer.length));
}

const args = process.argv.slice(2);
const asBase64 = args.includes('--base64');
const file = args.find((a) => !a.startsWith('--'));
if (!file) {
  console.error('用法： node tools/decode-session-log.mjs <文件.zstd> [--base64]');
  process.exit(2);
}

const raw = asBase64
  ? Buffer.from(readFileSync(file, 'utf8').replace(/\s+/g, ''), 'base64')
  : readFileSync(file);

const frames = splitFrames(raw);
console.log(`文件 ${raw.length} 字节，识别出 ${frames.length} 个 zstd 帧`);
let rows = 0;
frames.forEach((frame, i) => {
  let text;
  try {
    text = zstdDecompressSync(frame).toString('utf8');
  } catch (error) {
    console.log(`  帧 ${i + 1}（${frame.length} 字节）解压失败：${error.code || error.message}`);
    return;
  }
  for (const line of text.split('\n')) {
    if (!line.trim()) continue;
    rows += 1;
    let shown = line;
    try {
      const parsed = JSON.parse(line);
      shown = (parsed.type || parsed.kind || parsed.role || 'row') + ' | ' + JSON.stringify(parsed);
    } catch {
      /* 不是 JSON 就原样显示 */
    }
    console.log('  ' + shown.slice(0, 400));
  }
});
console.log(`共 ${rows} 行记录`);
