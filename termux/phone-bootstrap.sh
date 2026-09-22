#!/usr/bin/env bash
# 手机端**自包含引导**（贴进 Termux 就能跑，不依赖 /sdcard 权限、不需要 MTP 拷文件）。
#
# 为什么存在：`termux-setup-storage` 的授权对话框很容易被错过，导致 ~/storage/downloads 不存在、
# cp 报 "No such file or directory"。本脚本自己写出 ~/dsh-android/start-dsh.sh，
# 因此 app 里的「启动手机上的 DSH」按钮（按这个路径调用）随后也能用。
#
# 用法：把本文件内容整段粘进 Termux（或 bash phone-bootstrap.sh）
set -euo pipefail

SCRIPT_DIR="$HOME/dsh-android"
mkdir -p "$SCRIPT_DIR"

# ---------- 写出 start-dsh.sh（与 termux/start-dsh.sh 行为一致的精简版） ----------
cat > "$SCRIPT_DIR/start-dsh.sh" <<'SH'
#!/data/data/com.termux/files/usr/bin/bash
# 启动（或复用）手机本地 DSH Web，并把带 token 的 URL 交给 app。
# 判据：退出码 0 且最后一行是 APP_URL=<...>
set -euo pipefail
PORT="${1:-${DSH_PORT:-3080}}"
LOG="$HOME/.dsh-web.log"
APP_COMPONENT='app.dsh.mobile/.ui.MainActivity'
url_from_log() {
  [ -f "$LOG" ] || return 1
  local line
  line="$(grep -m1 'dsh web: ' "$LOG" 2>/dev/null || true)"
  [ -n "$line" ] || return 1
  printf '%s' "$line" | sed -E 's/^.*dsh web: (http[^ ]+).*$/\1/'
}
if curl -s -o /dev/null "http://127.0.0.1:$PORT/" 2>/dev/null; then
  echo "==> 端口 $PORT 上已有服务在跑，直接复用"
else
  echo "==> 启动 dsh web --port $PORT（日志 $LOG）"
  : > "$LOG"
  nohup dsh web --port "$PORT" --no-open >>"$LOG" 2>&1 &
fi
URL=""
for _ in $(seq 1 60); do
  URL="$(url_from_log || true)"
  [ -n "$URL" ] && break
  sleep 2
done
if [ -z "$URL" ]; then echo "!! 120 秒内没等到 URL，日志尾部："; tail -n 20 "$LOG"; exit 1; fi
echo "==> 入口 URL："
echo "$URL"
if command -v termux-clipboard-set >/dev/null 2>&1; then printf '%s' "$URL" | termux-clipboard-set || true; fi
if command -v am >/dev/null 2>&1; then
  if am start -n "$APP_COMPONENT" -e dsh_url "$URL" >/dev/null 2>&1; then
    echo "    （已把入口地址递给 DSH 手机端）"
  else
    echo "    （没能自动递给 app —— 把上面的 URL 手粘进 app 的「添加入口」即可）"
  fi
fi
echo "APP_URL=$URL"
SH
chmod +x "$SCRIPT_DIR/start-dsh.sh"

# ---------- 装依赖 ----------
echo "==> 更新包索引"
pkg update -y >/dev/null
echo "==> 安装 curl / openssh / termux-api"
pkg install -y curl openssh termux-api
echo "==> 安装 Node"
if ! pkg install -y nodejs-lts; then pkg install -y nodejs; fi
command -v node >/dev/null 2>&1 || { echo "!! Node 没装上"; exit 1; }
echo "    node $(node -v) / npm $(npm -v)"

# ---------- 装 DSH（走国内镜像：手机 VPN 常不稳） ----------
npm config set registry https://registry.npmmirror.com >/dev/null
echo "==> 安装 DSH（最慢的一步，几分钟正常；registry=$(npm config get registry)）"
npm i -g @deepseek-ai/dsh
command -v dsh >/dev/null 2>&1 || { echo "!! dsh 没装上：看上面的 npm 报错"; exit 1; }

# ---------- 唤醒锁 ----------
if command -v termux-wake-lock >/dev/null 2>&1; then
  termux-wake-lock || true
  echo "==> 已获取唤醒锁（termux-wake-unlock 释放）"
fi

echo "==> 启动本地 DSH Web"
exec bash "$SCRIPT_DIR/start-dsh.sh"
