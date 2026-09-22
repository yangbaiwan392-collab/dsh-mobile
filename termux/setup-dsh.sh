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
npm i -g @deepseek-ai/dsh
command -v dsh >/dev/null 2>&1 || { echo "!! dsh 没装上：看上面的 npm 报错"; exit 1; }
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
