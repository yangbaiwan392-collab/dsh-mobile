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
# ⚠ 这段与 termux/start-dsh.sh 是同一份逻辑的两处副本（本脚本要自包含）。
#   tools/test-termux-scripts.sh 会分别跑这两份，保证行为一致。
cat > "$SCRIPT_DIR/start-dsh.sh" <<'SH'
#!/data/data/com.termux/files/usr/bin/bash
# 启动（或复用）手机本地 DSH Web，并把带 token 的 URL 交给 app。
set -euo pipefail
PORT="${1:-${DSH_PORT:-3080}}"
LOG="$HOME/.dsh-web.log"
APP_COMPONENT='app.dsh.mobile/.ui.MainActivity'
DSH_BIN=""
if command -v dsh >/dev/null 2>&1; then DSH_BIN="dsh"
elif [ -x "$HOME/dsh-install/node_modules/.bin/dsh" ]; then DSH_BIN="$HOME/dsh-install/node_modules/.bin/dsh"
else echo "!! 找不到 dsh 命令，先按 docs/01-termux-local.md 安装"; exit 1; fi
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
  nohup "$DSH_BIN" web --port "$PORT" --no-open >>"$LOG" 2>&1 &
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
