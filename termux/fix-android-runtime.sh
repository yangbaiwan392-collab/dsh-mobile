#!/data/data/com.termux/files/usr/bin/bash
# Android 上**必须**做的两处运行时修复。都不是配置问题，而是 Android 与 Node 生态的交界：
#
#  1) flock：@deepseek-ai/node-addon-system 只认 linux/darwin，也没有 android 预编译包 ——
#     但官方把 C 源码（src/flock.c，含 NAPI_MODULE_INIT）一起发布了，所以可以**现编**。
#     不修的症状：开会话时 "本轮运行失败：flock is not supported on android-arm64"。
#  2) 硬链接：应用数据目录**禁止 link(2)**（SELinux 直接 Permission denied，`ln` 实测失败），
#     而 DSH 的会话持久化用 fs.link() 做原子落地 —— 同盘 rename() 同样原子且被允许。
#     不修的症状：EACCES: permission denied, link '…session.v3.jsonl.zstd.<hash>.c.tmp' -> '…'
#
# 幂等：已经修好的会跳过。用法： bash fix-android-runtime.sh
set -euo pipefail

PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
export PATH="$PREFIX/bin:$PATH"
# 注意：`adb shell run-as com.termux` 会把 HOME 设成 /data/user/0/com.termux（应用数据根），
# 而不是 Termux 自己的家目录 —— 所以这里**必须显式**定死，不能用 ${HOME:-...}（踩过）。
export HOME="/data/data/com.termux/files/home"
INSTALL_DIR="$HOME/dsh-install"
NODE="$(command -v node || echo "$PREFIX/bin/node")"
GYP="$PREFIX/lib/node_modules/npm/node_modules/node-gyp/bin/node-gyp.js"
ADDON_DIR="$INSTALL_DIR/node_modules/@deepseek-ai/node-addon-system"
PKG_DIR="$INSTALL_DIR/node_modules/@deepseek-ai/node-addon-system-android-arm64"
PERSIST="$INSTALL_DIR/node_modules/@deepseek-ai/dsh-session-persistence-jsonl/lib/index.js"
BUILD_DIR="$HOME/node-addon-build"

echo "==> [1/2] flock（android-arm64 原生模块）"

if [ -f "$PKG_DIR/bin/system.node" ] && grep -q "platform !== 'android'" "$ADDON_DIR/lib/flock.js" 2>/dev/null; then
  echo "    已经修好，跳过"
else
  command -v clang >/dev/null 2>&1 || { echo "!! 缺 clang：先 pkg install -y python clang make"; exit 1; }
  command -v python3 >/dev/null 2>&1 || { echo "!! 缺 python3：先 pkg install -y python clang make"; exit 1; }

  mkdir -p "$BUILD_DIR/src"
  if [ ! -f "$BUILD_DIR/src/flock.c" ]; then
    cp "$ADDON_DIR/src/flock.c" "$BUILD_DIR/src/flock.c"
  fi
  # binding.gyp 只编 flock.c —— main.c 是那个 landlock-run 独立 CLI（有自己的 main()）
  cat > "$BUILD_DIR/binding.gyp" <<'GYP_EOF'
{
  "targets": [
    {
      "target_name": "system",
      "sources": ["src/flock.c"],
      "defines": ["_GNU_SOURCE=1"],
      "cflags": ["-O2", "-fPIC"]
    }
  ]
}
GYP_EOF

  echo "    编译（node-gyp + clang）…"
  ( cd "$BUILD_DIR" && "$NODE" "$GYP" rebuild --python="$PREFIX/bin/python3" >/dev/null 2>&1 ) || {
    echo "!! 编译失败，重跑一次看细节："
    ( cd "$BUILD_DIR" && "$NODE" "$GYP" rebuild --python="$PREFIX/bin/python3" 2>&1 | tail -20 )
    exit 1
  }

  mkdir -p "$PKG_DIR/bin"
  cp "$BUILD_DIR/build/Release/system.node" "$PKG_DIR/bin/system.node"
  cat > "$PKG_DIR/package.json" <<'PKG_EOF'
{
  "name": "@deepseek-ai/node-addon-system-android-arm64",
  "version": "0.1.2",
  "description": "Locally built for Android/Termux (aarch64) from the sources shipped in @deepseek-ai/node-addon-system.",
  "license": "BSD-3-Clause",
  "os": ["android"],
  "cpu": ["arm64"]
}
PKG_EOF

  # 放行 android（原本 if (platform !== 'linux' && platform !== 'darwin') throw）
  "$NODE" -e '
    const fs = require("fs");
    const file = process.argv[1];
    const from = "platform !== \x27linux\x27 && platform !== \x27darwin\x27";
    const to = "platform !== \x27linux\x27 && platform !== \x27darwin\x27 && platform !== \x27android\x27";
    const source = fs.readFileSync(file, "utf8");
    if (source.includes(to)) { console.log("    flock.js 已经是放行 android 的形态"); process.exit(0); }
    if (!source.includes(from)) { console.log("!! flock.js 里找不到平台判定，上游可能改过，请人工看一眼"); process.exit(1); }
    fs.writeFileSync(file, source.replace(from, to));
    console.log("    已放行 android：" + file);
  ' "$ADDON_DIR/lib/flock.js"

  echo "    编译产物：$(ls -l "$PKG_DIR/bin/system.node" | awk '{print $5}') 字节"
fi

echo "==> [2/2] 硬链接 → 同盘 rename（会话持久化）"

if grep -q "await rename(tmp, finalPath)" "$PERSIST" 2>/dev/null; then
  echo "    已经修好，跳过"
else
  "$NODE" -e '
    const fs = require("fs");
    const file = process.argv[1];
    let source = fs.readFileSync(file, "utf8");
    const steps = [
      ["import 里补上 rename", "{ link, lstat, mkdir,", "{ link, rename, lstat, mkdir,"],
      ["发布暂存文件：link -> rename", "internals.fs.link(staged, currentPath)", "internals.fs.rename(staged, currentPath)"],
      ["发布日志版本文件：link -> rename", "await link(tmp, finalPath);", "await rename(tmp, finalPath);"],
    ];
    for (const [label, from, to] of steps) {
      if (source.includes(from)) { source = source.replace(from, to); console.log("    " + label); }
      else if (!source.includes(to)) { console.log("!! 找不到模式：" + label + "（上游可能改过）"); process.exit(1); }
    }
    fs.writeFileSync(file, source);
  ' "$PERSIST"
fi

echo "==> 自检：flock 真的能用吗"
cat > "$INSTALL_DIR/selfcheck-flock.mjs" <<'JS_EOF'
import { closeSync, openSync, writeFileSync } from 'node:fs';
import { tryLockExclusive } from '@deepseek-ai/node-addon-system/flock';
const path = process.argv[2];
writeFileSync(path, '');
const first = openSync(path, 'r+');
await tryLockExclusive(first);
const second = openSync(path, 'r+');
try {
  await tryLockExclusive(second);
  console.log('!! 第二次加锁竟然成功：flock 语义没生效');
  process.exitCode = 1;
} catch {
  console.log('flock 可用 ✓（第一次成功，第二次被 EAGAIN 拒绝）');
}
closeSync(first);
closeSync(second);
JS_EOF

( cd "$INSTALL_DIR" && "$NODE" selfcheck-flock.mjs "$HOME/.flock-selfcheck" ) || exit 1
rm -f "$HOME/.flock-selfcheck"

echo "==> Android 运行时修复完成（flock 已编好、硬链接已绕开）"
