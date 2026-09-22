#!/data/data/com.termux/files/usr/bin/bash
# 模式 B · 在手机 Termux 里开一条 SSH 隧道，把 PC 的 loopback DSH 端口搬到手机上。
#
# 为什么是"隧道"而不是直连：DSH 只监听 127.0.0.1，且拒绝 0.0.0.0 / 具体网卡 IP（见 docs/02-remote-pc.md）。
# SSH 的本地转发让"手机上的 127.0.0.1:3080"接到 PC 的 127.0.0.1:3080 ——
# 在 DSH 看来就是本机访问，信任栅栏、cookie 绑定、SameSite 全部自然满足，而且这一段是加密的。
#
# 用法：bash tunnel-to-pc.sh <PC 局域网 IP> <PC 用户名> [端口，默认 3080]
set -euo pipefail

PC_IP="${1:?用法: bash tunnel-to-pc.sh <PC 局域网 IP> <PC 用户名> [端口]}"
PC_USER="${2:?缺少 PC 用户名}"
PORT="${3:-3080}"

echo "==> 隧道：手机 127.0.0.1:$PORT  ->  $PC_USER@$PC_IP 的 127.0.0.1:$PORT"
echo "    保持这个 Termux 会话（Ctrl-C 断开）；另开一个会话跑别的。"
echo
echo "    app 里添加入口："
echo "      http://127.0.0.1:$PORT/?token=<PC 上 dsh web 打印的那串>"
echo "    （PC 侧拿 token：看 PC 控制台里 'dsh web: http://127.0.0.1:$PORT/?token=…' 那一行）"
echo
echo "    提示：PC 需要先启用 OpenSSH 服务器（管理员 PowerShell）："
echo "      Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0; Start-Service sshd"
echo

exec ssh -N \
  -o ExitOnForwardFailure=yes \
  -o ServerAliveInterval=30 \
  -o ServerAliveCountMax=3 \
  -L "127.0.0.1:$PORT:127.0.0.1:$PORT" \
  "$PC_USER@$PC_IP"
