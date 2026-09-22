#!/data/data/com.termux/files/usr/bin/bash
# 手机端**自包含引导**（不依赖 /sdcard 权限）。
#
# ⚠ 不要把这个文件"整段复制粘贴"进 Termux —— 它内部有两个 heredoc，
#   多行粘贴在 Termux 里会被截断（真机踩过：cat 写出 0 字节文件 → npm EJSONPARSE）。
#   正确用法二选一：
#     · 用 MTP 把它当**文件**拷进手机，再 `bash ~/storage/downloads/phone-bootstrap.sh`
#     · 或不要用它，改为按 README FAQ 里的**单行命令**手工装（那行是单行，粘贴安全）
#
# 它做四件事：写出 ~/dsh-android/start-dsh.sh（因此 app 的「启动手机上的 DSH」按钮可用）
# → 装依赖 → 装 DSH（含绕开上游坏发布的 overrides 配方）→ 拿唤醒锁并启动。
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
# 预检：Termux 滚动仓库常处于"升级了一半"的状态（新 libcurl + 旧 openssl 会让 curl 崩：
# CANNOT LINK EXECUTABLE ... SSL_set_quic_tls_early_data_enabled），届时 pkg/npm 会连锁失败。
if ! curl --version >/dev/null 2>&1; then
  echo "!! curl 无法运行：请先执行  apt update && apt full-upgrade -y  再重跑本脚本。"
  exit 1
fi
echo "==> 更新包索引"
pkg update -y >/dev/null
echo "==> 安装 curl / openssh / termux-api"
pkg install -y curl openssh termux-api
echo "==> 安装 Node"
if ! pkg install -y nodejs-lts; then pkg install -y nodejs; fi
command -v node >/dev/null 2>&1 || { echo "!! Node 没装上"; exit 1; }
echo "    node $(node -v) / npm $(npm -v)"

# ---------- 装 DSH（走国内镜像 + 绕开上游坏发布） ----------
npm config set registry https://registry.npmmirror.com >/dev/null
echo "==> 安装 DSH（最慢的一步，几分钟正常；registry=$(npm config get registry)）"
# 上游 0.1.5-rc.3 那个发布坏了：sidebar 发了 rc.3，配套的 documentpreview 没发，
# 而 ^0.1.5-rc.3 按 semver 只匹配 0.1.5 系列 → 全新安装必 ETARGET。
# 用 overrides 钉到已知可用的 rc.2 组合（本机实测 584 个包解析通过）。
INSTALL_DIR="$HOME/dsh-install"
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
  }
}
JSON
( cd "$INSTALL_DIR" && npm install --no-audit --no-fund )
npm link @deepseek-ai/dsh >/dev/null 2>&1 || true
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
