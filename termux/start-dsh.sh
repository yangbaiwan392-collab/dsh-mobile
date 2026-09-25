#!/data/data/com.termux/files/usr/bin/bash
# 启动（或复用）手机本地的 DSH Web，并把带 token 的 URL 交给你 / 交给 app。
#
# 用法：bash start-dsh.sh [端口，默认 3080]
# 判据：退出码 0 且最后一行是 APP_URL=<...>
set -euo pipefail

PORT="${1:-${DSH_PORT:-3080}}"
LOG="$HOME/.dsh-web.log"
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
# DSH 的 provider 配置要求 apiKeyEnv 指向的环境变量**存在**（Ollama 本身不校验值）。
# 这里给"远程 Ollama"那类 provider 一个占位值，见 docs/02 第五节。
export DSH_OLLAMA_KEY="${DSH_OLLAMA_KEY:-ollama}"
# 本 app 的组件名（与 AndroidManifest 里的 .ui.MainActivity 对应；tools/check-contracts.ps1 会核对这行）
APP_COMPONENT='app.dsh.mobile/.ui.MainActivity'

# Termux 靠 termux-exec 把 shebang（#!/usr/bin/env node）重写成 $PREFIX/bin/node；
# 从非 Termux 环境（例如 adb run-as、或某些服务上下文）调用本脚本时它没被带上，
# 于是 `dsh` 会报 "/usr/bin/env: bad interpreter" —— 这里补上，让脚本从任何调用方都能跑。
if [ -z "${LD_PRELOAD:-}" ] && [ -f "$PREFIX/lib/libtermux-exec.so" ]; then
  export LD_PRELOAD="$PREFIX/lib/libtermux-exec.so"
fi

# 拿一把唤醒锁 —— 这是"用一会儿 DSH 就没了"的根治手段（moto XT2611-1 / Android 16 实测）：
#   系统日志实证：ApplicationExitInfo 里 com.termux 的退出原因是
#     reason=10 (USER REQUESTED) subreason=21 (FORCE STOP)
#     description=stop com.termux due to RemoveTaskMemoryClean
#   即"清理后台/划掉最近任务"时 Termux 作为普通后台应用被强停，node 子进程跟着死。
#   termux-wake-lock 会让 Termux 变成**前台服务**（常驻一条通知），清后台杀不掉它。
#   幂等：重复调用只是重新确认；没装 termux-tools（没有这个命令）时静默跳过。
#   解除：`termux-wake-unlock`，或结束 Termux 进程。
if command -v termux-wake-lock >/dev/null 2>&1; then
  if termux-wake-lock 2>/dev/null; then
    echo "==> 已取得唤醒锁（Termux 转为前台服务，清后台不会再杀掉 DSH）"
  fi
fi

# 解析 dsh 命令。三条理由决定了这里不走 `dsh` 这个 shim：
#   1) 上游坏依赖（0.1.5-rc.3）让 `npm link <包名>` 必定失败（它会回 registry 重新解析），所以用 .bin 路径；
#   2) dsh 的 shebang 是 `#!/usr/bin/env node`，**Android 上没有 /usr/bin/env** ——
#      只有 Termux 的 termux-exec 在场时才会被重写（见上面的 LD_PRELOAD 兜底）；
#   3) DSH 的 web profile 带 HMR 插件，它要求 node 以 **--expose-internals** 启动，
#      否则报 "--expose-internals is required for HMR service"（真机实测）。
# 因此直接用 node 调 bin.js，并把 flag 带上。
NODE_BIN="$(command -v node || echo "$PREFIX/bin/node")"
DSH_JS="$HOME/dsh-install/node_modules/@deepseek-ai/dsh/lib/bin.js"
if [ -f "$DSH_JS" ]; then
  DSH_CMD=("$NODE_BIN" --expose-internals "$DSH_JS")
elif command -v dsh >/dev/null 2>&1; then
  DSH_CMD=(dsh)
else
  echo "!! 找不到 dsh。先按 docs/01-termux-local.md 在 ~/dsh-install 里装好。"
  exit 1
fi

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
  nohup "${DSH_CMD[@]}" web --port "$PORT" --no-open >>"$LOG" 2>&1 &
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
