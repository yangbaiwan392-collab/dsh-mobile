#!/data/data/com.termux/files/usr/bin/bash
# 模式 A · 在手机自己上跑 DSH（loopback，完全符合 DSH 的信任模型）
#
# 用法（Termux 里）：  bash setup-dsh.sh
# 之后每次启动：        bash start-dsh.sh
#
# 为什么绑定 loopback 就够：DSH 的 browser-trust 栅栏只接受 127.0.0.1 或显式白名单，
# 而 `--host 0.0.0.0` 会被服务端显式拒绝（实测："would expose remote code execution"）。
# 手机自己跑 + 本机浏览器/壳子访问，正好落在它设计的路径上。
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"

# ---------- 预检：Termux 的滚动仓库很容易处于"升级了一半"的状态 ----------
# 真实案例（2026-09-22 真机）：安装时升级了 curl/libcurl 8.12→8.22，但 openssl 没跟着升
# （apt 提示 "72 not upgraded"），于是 curl 报：
#   CANNOT LINK EXECUTABLE "curl": cannot locate symbol "SSL_set_quic_tls_early_data_enabled"
# 这种情况下 pkg 的镜像自检、nodejs 安装都会连锁失败 —— 必须先整体升级，而不是继续装。
if ! curl --version >/dev/null 2>&1; then
  echo "!! curl 无法运行：Termux 的包很可能升级了一半（例如新 libcurl 配旧 openssl）。"
  echo "   请先执行："
  echo "       apt update && apt full-upgrade -y"
  echo "   跑完用 'curl --version' 确认正常，再重新执行本脚本。"
  exit 1
fi

echo "==> 更新包索引"
pkg update -y >/dev/null

echo "==> 安装依赖（curl / openssh / termux-api）"
pkg install -y curl openssh termux-api

# Node 包名在不同 Termux 版本里可能是 nodejs-lts 或 nodejs —— 装不上就回退，别让整条链断在这
echo "==> 安装 Node"
if ! pkg install -y nodejs-lts; then
  echo "    nodejs-lts 装不上，改用 nodejs"
  pkg install -y nodejs
fi
command -v node >/dev/null 2>&1 || { echo "!! Node 没装上，先解决 Termux 的网络/镜像问题"; exit 1; }
echo "    node $(node -v) / npm $(npm -v)"

# npm 走国内镜像：手机上的 VPN 往往不稳，直连 registry.npmjs.org 很容易卡死在这一步。
# 想改回官方源： npm config set registry https://registry.npmjs.org
echo "==> 配置 npm 镜像（registry.npmmirror.com）"
npm config set registry https://registry.npmmirror.com
echo "    当前 registry: $(npm config get registry)"

echo "==> 安装 DSH（这一步最慢，几分钟正常）"
# node-pty 只提供 darwin/linux/win32 预编译，**没有 android-arm64** → 必须在手机上现编。
# 而 dsh-subprocess-local 在模块顶层就 import node-pty（饿加载），编译不出来 DSH 就起不来，
# 所以这里先把编译工具链装好（否则 node-gyp 会报一大段 "Could not find any Python"）。
if ! command -v python3 >/dev/null 2>&1 || ! command -v clang >/dev/null 2>&1; then
  echo "==> 安装编译工具链（python / clang / make，给 node-pty 用）"
  pkg install -y python clang make
fi
# ⚠ 不要用 `npm i -g @deepseek-ai/dsh`：上游当前发布树是坏的 ——
#   dsh-client-ui-sidebar 有一个乱序发布的 0.1.5-rc.3，而配套的
#   dsh-client-ui-sidebar-documentpreview 没有 rc.3（只有 rc.1/rc.2，然后跳到 alpha）；
#   `^0.1.5-rc.3` 按 semver 只匹配 0.1.5 系列 → 无解 → npm ETARGET，全新安装必失败。
# 做法：装进项目目录，用 overrides 把相关子包钉到已知可用的 rc.2 组合，再 npm link 暴露 dsh 命令。
# 实测：该组合 584 个包全部解析成功（见 tools/probe-dsh-versions.ps1）。
INSTALL_DIR="$HOME/dsh-install"
mkdir -p "$INSTALL_DIR"
# allowScripts：npm 11.19+ 默认**不执行**未批准的安装脚本（node-pty 的编译、dsh-subprocess-local
# 的 ensure-spawn-helper 都在其中，被跳过就等于没装好）。策略可以直接写在 package.json 里。
cat > "$INSTALL_DIR/package.json" <<'JSON'
{
  "name": "dsh-install",
  "private": true,
  "dependencies": { "@deepseek-ai/dsh": "0.1.5-rc.2" },
  "overrides": {
    "@deepseek-ai/dsh-client-ui-sidebar": "0.1.5-rc.2",
    "@deepseek-ai/dsh-client-ui-sidebar-documentpreview": "0.1.5-rc.2",
    "@deepseek-ai/dsh-web-app": "0.1.5-rc.2",
    "@deepseek-ai/dsh-client-ui-chat": "0.1.5-rc.2"
  },
  "allowScripts": {
    "node-pty": true,
    "@deepseek-ai/dsh-subprocess-local": true,
    "koffi": true,
    "protobufjs": true
  }
}
JSON
( cd "$INSTALL_DIR" && npm install --no-audit --no-fund )

# npm 的 "up to date" 快路径会**跳过**已装包的 install 脚本 —— 所以显式确认 node-pty 的
# 编译产物在不在，不在就 rebuild（这一步是"验证而不是假设"：dsh --version 不加载 node-pty，
# 看不出来；但 dsh-subprocess-local 顶层 import 它，缺了 DSH 起不来）。
PTY_NODE="$INSTALL_DIR/node_modules/node-pty/build/Release/pty.node"
if [ ! -f "$PTY_NODE" ]; then
  echo "==> node-pty 编译产物不在（可能被 up-to-date 快路径跳过），显式重编"
  ( cd "$INSTALL_DIR" && npm rebuild node-pty @deepseek-ai/dsh-subprocess-local --foreground-scripts )
fi
[ -f "$PTY_NODE" ] || { echo "!! node-pty 仍未编出：把上面的编译错误发出来"; exit 1; }
echo "    node-pty 编译产物 ✓"

# sharp 同样没有 android-arm64 预编译，而且需要 libvips；官方给的免编译出路是 wasm 版。
# dsh-attachment-local 依赖它，缺了整棵插件树起不来（真机实测报
# "Could not load the sharp module using the android-arm64 runtime"）。
echo "==> 安装 wasm 版 sharp（@img/sharp-wasm32，免编译）"
( cd "$INSTALL_DIR" && npm install --no-audit --no-fund @img/sharp-wasm32@0.35.4 )
if ( cd "$INSTALL_DIR" && node -e 'require("sharp")' >/dev/null 2>&1 ); then
  echo "    sharp ✓"
else
  echo "!! sharp 仍不可用（把上面的 npm 输出发出来）"; exit 1
fi

# Android 上还必须修两处运行时（都不是配置问题）：
#   · flock：node-addon-system 没有 android 预编译 → 用随包的 C 源码现编 + 放行 android
#   · 硬链接：应用数据目录禁止 link(2) → 会话持久化改用同盘 rename
# 不修就会在开会话时报 "本轮运行失败：flock is not supported on android-arm64"
# 或 "EACCES ... link '…session.v3.jsonl.zstd.<hash>.c.tmp'"（都是真机实测）。
if [ -f "$HERE/fix-android-runtime.sh" ]; then
  echo "==> Android 运行时修复（flock / 硬链接）"
  bash "$HERE/fix-android-runtime.sh"
fi
npm link @deepseek-ai/dsh >/dev/null 2>&1 || true
if ! command -v dsh >/dev/null 2>&1; then
  echo "    （npm link 未生效，改用 PATH 方式）"
  export PATH="$INSTALL_DIR/node_modules/.bin:$PATH"
  if ! grep -q 'dsh-install/node_modules/.bin' "$HOME/.bashrc" 2>/dev/null; then
    echo 'export PATH="$HOME/dsh-install/node_modules/.bin:$PATH"' >> "$HOME/.bashrc"
    echo "    已写入 ~/.bashrc（新开终端自动生效）"
  fi
fi
command -v dsh >/dev/null 2>&1 || { echo "!! dsh 仍不可用：把上面的 npm 报错发出来"; exit 1; }
echo "    dsh $(dsh --version 2>/dev/null || echo '(已安装)')"

# 唤醒锁：Android 13 后台限制很严，没有它 Termux 进程会被冻结
if command -v termux-wake-lock >/dev/null 2>&1; then
  termux-wake-lock || true
  echo "==> 已获取唤醒锁（用 termux-wake-unlock 释放）"
else
  echo "    （没找到 termux-wake-lock：Termux:API 没装或没授权，后台可能被系统冻结）"
fi

echo "==> 启动本地 DSH Web"
exec bash "$HERE/start-dsh.sh"
