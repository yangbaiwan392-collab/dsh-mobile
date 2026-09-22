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

echo "==> 安装依赖（Node / curl / openssh / termux-api）"
pkg update -y >/dev/null
pkg install -y nodejs-lts curl openssh termux-api

echo "==> 安装 DSH"
npm i -g @deepseek-ai/dsh

# 唤醒锁：Android 13 后台限制很严，没有它 Termux 进程会被冻结
if command -v termux-wake-lock >/dev/null 2>&1; then
  termux-wake-lock || true
  echo "==> 已获取唤醒锁（用 termux-wake-unlock 释放）"
fi

echo "==> 启动本地 DSH Web"
exec bash "$HERE/start-dsh.sh"
