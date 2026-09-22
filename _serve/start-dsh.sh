#!/data/data/com.termux/files/usr/bin/bash
# 启动（或复用）手机本地的 DSH Web，并把带 token 的 URL 交给你 / 交给 app。
#
# 用法：bash start-dsh.sh [端口，默认 3080]
# 判据：退出码 0 且最后一行是 APP_URL=<...>
set -euo pipefail

PORT="${1:-${DSH_PORT:-3080}}"
LOG="$HOME/.dsh-web.log"
# 本 app 的组件名（与 AndroidManifest 里的 .ui.MainActivity 对应；tools/check-contracts.ps1 会核对这行）
APP_COMPONENT='app.dsh.mobile/.ui.MainActivity'

url_from_log() {
  [ -f "$LOG" ] || return 1
  # DSH 自己打印的那行： dsh web: http://127.0.0.1:<port>/?token=<...>   （可能带 " (LAN: ...)" 后缀）
  local line
  line="$(grep -m1 'dsh web: ' "$LOG" 2>/dev/null || true)"
  [ -n "$line" ] || return 1
  printf '%s' "$line" | sed -E 's/^.*dsh web: (http[^ ]+).*$/\1/'
}

# 服务已在跑？那就不重启（避免把正在用的会话踢掉）
if curl -s -o /dev/null "http://127.0.0.1:$PORT/" 2>/dev/null; then
  echo "==> 端口 $PORT 上已有服务在跑，直接复用"
  URL="$(url_from_log || true)"
  if [ -z "${URL:-}" ]; then
    echo "    （日志里没找到 token URL：token 只在启动时打印一次；要换新的就重启服务）"
    echo "    重启： pkill -f 'dsh web' && bash $0 $PORT"
    exit 0
  fi
else
  echo "==> 启动 dsh web --port $PORT（后台，日志 $LOG）"
  : > "$LOG"
  nohup dsh web --port "$PORT" --no-open >>"$LOG" 2>&1 &
  URL=""
  for _ in $(seq 1 60); do
    URL="$(url_from_log || true)"
    [ -n "$URL" ] && break
    sleep 2
  done
  if [ -z "$URL" ]; then
    echo "!! 120 秒内没等到 URL，日志尾部："
    tail -n 20 "$LOG"
    exit 1
  fi
fi

echo "==> 入口 URL："
echo "$URL"

# 顺手塞进剪贴板（装了 termux-api 才有），方便粘进 app
if command -v termux-clipboard-set >/dev/null 2>&1; then
  printf '%s' "$URL" | termux-clipboard-set || true
  echo "    （已复制到剪贴板）"
fi

# 若装了本 app，直接把 URL 作为参数递过去，省掉手粘
if command -v am >/dev/null 2>&1; then
  if am start -n "$APP_COMPONENT" -e dsh_url "$URL" >/dev/null 2>&1; then
    echo "    （已把入口地址递给 DSH 手机端）"
  else
    echo "    （没能自动递给 app —— 可能还没装；把上面的 URL 手粘进 app 的「添加入口」即可）"
  fi
fi

echo "APP_URL=$URL"
