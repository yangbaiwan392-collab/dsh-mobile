#!/data/data/com.termux/files/usr/bin/bash
# 手机端**自包含引导**（不依赖 /sdcard 权限）。
#
# ⚠ 不要把这个文件"整段复制粘贴"进 Termux —— 它内部有 heredoc，
#   多行粘贴在 Termux 里会被截断（真机踩过：cat 写出 0 字节文件 → npm EJSONPARSE）。
#   正确用法：用 MTP 把它当**文件**拷进手机，再 `bash ~/storage/downloads/phone-bootstrap.sh`
#
# 它做五件事：写出 ~/dsh-android/start-dsh.sh（因此 app 的「启动手机上的 DSH」按钮可用）
# → 装依赖（含 node-pty 编译工具链）→ 装 DSH（绕开上游坏发布 + 放行安装脚本）
# → 把 dsh 命令暴露出来 → 拿唤醒锁并启动。
set -euo pipefail

SCRIPT_DIR="$HOME/dsh-android"
INSTALL_DIR="$HOME/dsh-install"
mkdir -p "$SCRIPT_DIR"

# ---------- 预检：Termux 滚动仓库常处于"升级了一半"的状态 ----------
if ! curl --version >/dev/null 2>&1; then
  echo "!! curl 无法运行：请先执行  apt update && apt full-upgrade -y  再重跑本脚本。"
  exit 1
fi

# ---------- 写出 start-dsh.sh ----------
# ⚠ 下面内嵌的是 termux/start-dsh.sh 的**逐字副本**（本脚本要自包含，不能 source 外部文件）。
#   别再手改这一段：要改就改 termux/start-dsh.sh，然后跑 tools/sync-bootstrap-embed.ps1 灌回来。
#   tools/check-contracts.ps1 会逐字核对两者一致，漂了就红。
#   （历史上这两份是各自手改的，真的漂过：内嵌那份少了 DSH_OLLAMA_KEY、也没有唤醒锁。）
cat > "$SCRIPT_DIR/start-dsh.sh" <<'SH'
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

# 装一个「打开 Termux 就顺手把 DSH 拉起来」的钩子。
#
# 为什么需要它：系统会拦"从停止状态被别的应用拉起"—— 摩托的 DeviceGuard 实测就是这样，
# 而且连"Termux 已经是前台服务（importance=FOREGROUND_SERVICE）"时都照样以 AutoRun 为由强停：
#     ApplicationExitInfo: description=stop com.termux due to AutoRun
# 但**用户自己点开 Termux 不受这个限制**，所以把启动动作挂到 Termux 的交互 shell 上：
# 只要用户打开一次 Termux，DSH 就自己起来 —— app 里那个按钮被拦时就不再是死路。
#
# 幂等：~/.bashrc 里用哨兵注释标记，装过就不再追加，也不动用户已有的其它内容。
# 只在交互 shell（有 PS1）里生效，所以 RUN_COMMAND 的 `bash -c` 不会触发它、不会递归。
ensure_bashrc_hook() {
  local rc="$HOME/.bashrc"
  local begin='# >>> dsh-android 自动启动 >>>'
  local end='# <<< dsh-android 自动启动 <<<'
  if grep -qF "$begin" "$rc" 2>/dev/null; then
    return 0
  fi
  if {
    printf '\n%s\n' "$begin"
    printf '%s\n' '# 由 start-dsh.sh 安装：打开 Termux 时若本地 DSH 没在跑，就后台拉起（幂等、失败静默）。'
    printf '%s\n' 'if [ -n "${PS1:-}" ] && [ -x "$HOME/dsh-android/start-dsh.sh" ]; then'
    printf '%s\n' '  if ! curl -s -o /dev/null -m 2 "http://127.0.0.1:3080/" 2>/dev/null; then'
    printf '%s\n' '    ( bash "$HOME/dsh-android/start-dsh.sh" >/dev/null 2>&1 & )'
    printf '%s\n' '  fi'
    printf '%s\n' 'fi'
    printf '%s\n' "$end"
  } >> "$rc" 2>/dev/null; then
    echo "==> 已装好 ~/.bashrc 钩子：下次打开 Termux 会自动检查并拉起 DSH"
  fi
}
ensure_bashrc_hook

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

# node-pty 无 android-arm64 预编译，且被顶层饿加载 → 必须先有编译工具链
if ! command -v python3 >/dev/null 2>&1 || ! command -v clang >/dev/null 2>&1; then
  echo "==> 安装编译工具链（python / clang / make）"
  pkg install -y python clang make
fi

# ---------- 装 DSH ----------
npm config set registry https://registry.npmmirror.com >/dev/null
echo "==> 安装 DSH（最慢的一步；registry=$(npm config get registry)）"
mkdir -p "$INSTALL_DIR"
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
# up-to-date 快路径会跳过 install 脚本 → 显式确认 node-pty 的编译产物
PTY_NODE="$INSTALL_DIR/node_modules/node-pty/build/Release/pty.node"
if [ ! -f "$PTY_NODE" ]; then
  echo "==> node-pty 编译产物不在，显式重编"
  ( cd "$INSTALL_DIR" && npm rebuild node-pty @deepseek-ai/dsh-subprocess-local --foreground-scripts )
fi
[ -f "$PTY_NODE" ] || { echo "!! node-pty 仍未编出：把上面的编译错误发出来"; exit 1; }
# sharp 也没有 android-arm64 预编译 → 用官方推荐的 wasm 版（免编译）
echo "==> 安装 wasm 版 sharp（@img/sharp-wasm32）"
( cd "$INSTALL_DIR" && npm install --no-audit --no-fund @img/sharp-wasm32@0.35.4 ) || true
( cd "$INSTALL_DIR" && node -e 'require("sharp")' >/dev/null 2>&1 ) || { echo "!! sharp 不可用"; exit 1; }
command -v dsh >/dev/null 2>&1 || {
  # 不用 npm link <包名>：它会回 registry 重新解析，必然再撞上游坏依赖
  ln -sf "$INSTALL_DIR/node_modules/.bin/dsh" "$PREFIX/bin/dsh" 2>/dev/null || true
  hash -r 2>/dev/null || true
}
if ! command -v dsh >/dev/null 2>&1; then
  export PATH="$INSTALL_DIR/node_modules/.bin:$PATH"
  grep -q 'dsh-install/node_modules/.bin' "$HOME/.bashrc" 2>/dev/null || \
    echo 'export PATH="$HOME/dsh-install/node_modules/.bin:$PATH"' >> "$HOME/.bashrc"
fi
command -v dsh >/dev/null 2>&1 || { echo "!! dsh 没装上：看上面的 npm 报错"; exit 1; }

# ---------- 唤醒锁 ----------
if command -v termux-wake-lock >/dev/null 2>&1; then
  termux-wake-lock || true
  echo "==> 已获取唤醒锁（termux-wake-unlock 释放）"
fi

echo "==> 启动本地 DSH Web"
exec bash "$SCRIPT_DIR/start-dsh.sh"

