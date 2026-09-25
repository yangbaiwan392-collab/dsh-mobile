#!/usr/bin/env bash
# 用桩命令在本机**真跑** termux/ 下的脚本，验证：
#   ① 语法能过；
#   ② 从 dsh 的真实输出里正确摘出带 token 的 URL（不吃 "(LAN: …)" 尾巴）；
#   ③ 递给 app 的组件名/extra 键与 Android 侧一致（最易写错、且在手机上会静默失败的一环）；
#   ④ "服务已在跑"时走复用分支、不重启；
#   ⑤ 自包含引导能自己写出 start-dsh.sh 并跑通；
#   ⑥ curl 因"包升级了一半"而崩时，预检会拦住并给出修复命令。
#
# 为什么需要：本机没有 Termux、也没有已注册的 WSL 发行版，手机是第一次真跑；
# 这个脚本把"能不能跑通"提前到本机，用 Git for Windows 自带的 bash 执行。
#
# 用法： "C:\Program Files\Git\bin\bash.exe" tools/test-termux-scripts.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
START_SH="$ROOT/termux/start-dsh.sh"
SETUP_SH="$ROOT/termux/setup-dsh.sh"
BOOT_SH="$ROOT/termux/phone-bootstrap.sh"
TMP="$(mktemp -d)"
STUB="$TMP/bin"
mkdir -p "$STUB" "$TMP/home"
export HOME="$TMP/home"

pass=0
fail=0
check() { # check <描述> <期望> <实际>
  if [ "$2" = "$3" ]; then
    printf '  ok   %s\n' "$1"; pass=$((pass + 1))
  else
    printf '  FAIL %s\n       期望: %s\n       实际: %s\n' "$1" "$2" "$3"; fail=$((fail + 1))
  fi
}

# ---------- 公共桩 ----------
# dsh：按 DSH 真实格式打印一行（带 LAN 尾巴，用来验证摘取逻辑不被尾巴干扰）
cat > "$STUB/dsh" <<'EOF'
#!/usr/bin/env bash
echo "dsh web: http://127.0.0.1:3099/?token=TESTTOKEN123 (LAN: http://192.168.0.105:3099/?token=TESTTOKEN123)"
EOF
cat > "$STUB/am" <<EOF
#!/usr/bin/env bash
echo "\$@" >> "$TMP/am.calls"
EOF
cat > "$STUB/termux-clipboard-set" <<EOF
#!/usr/bin/env bash
cat > "$TMP/clipboard.txt"
EOF
cat > "$STUB/termux-wake-lock" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat > "$STUB/nohup" <<'EOF'
#!/usr/bin/env bash
exec "$@"
EOF
cat > "$STUB/sleep" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat > "$STUB/pkg" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat > "$STUB/node" <<'EOF'
#!/usr/bin/env bash
# 模拟 node：被用来跑 dsh 的 bin.js 时，打印 DSH 真实格式的那一行；否则打印版本号
case "$*" in
  *bin.js*) echo "dsh web: http://127.0.0.1:3099/?token=TESTTOKEN123 (LAN: http://192.168.0.105:3099/?token=TESTTOKEN123)" ;;
  *) echo v22.0.0 ;;
esac
exit 0
EOF
# 脚本现在优先用 node + bin.js（避开 shebang 与 HMR flag 问题），所以桩环境里要有这个文件
mkdir -p "$TMP/home/dsh-install/node_modules/@deepseek-ai/dsh/lib"
: > "$TMP/home/dsh-install/node_modules/@deepseek-ai/dsh/lib/bin.js"
cat > "$STUB/npm" <<'EOF'
#!/usr/bin/env bash
# 模拟 npm：config 打印 registry；rebuild 会**生成** node-pty 的编译产物
# （脚本里有"产物不存在就 rebuild、还不在就退出"的检查，桩必须能配合它）
if [ "$1" = "config" ]; then echo "https://registry.npmmirror.com"; exit 0; fi
if [ "$1" = "rebuild" ]; then
  mkdir -p "$HOME/dsh-install/node_modules/node-pty/build/Release"
  : > "$HOME/dsh-install/node_modules/node-pty/build/Release/pty.node"
fi
exit 0
EOF

# curl 桩：**必须同时支持 `--version`（预检会调它）**与"服务是否在跑"的探测。
# $1 为 up/down 控制探测结果；写成 make_curl up 或 make_curl down。
make_curl() {
  local mode="$1"
  local probe_exit=7
  [ "$mode" = "up" ] && probe_exit=0
  cat > "$STUB/curl" <<EOF
#!/usr/bin/env bash
case "\$1" in
  --version) echo "curl 8.22.0"; exit 0 ;;
  *) exit $probe_exit ;;
esac
EOF
  chmod +x "$STUB/curl"
}
chmod +x "$STUB"/*
export PATH="$STUB:$PATH"

# ---------- 语法检查 ----------
echo "语法检查（bash -n）："
for f in "$ROOT"/termux/*.sh; do
  if bash -n "$f"; then printf '  ok   %s\n' "$(basename "$f")"; pass=$((pass + 1));
  else printf '  FAIL %s 语法错误\n' "$(basename "$f")"; fail=$((fail + 1)); fi
done

# ---------- 用例 1：服务没在跑 → 启动分支 ----------
echo
echo "用例 1：服务未运行 → 应启动并摘出 URL"
make_curl down
rm -f "$TMP/am.calls" "$TMP/clipboard.txt" "$TMP/home/.dsh-web.log"
OUT="$(bash "$START_SH" 3099 2>&1)"
check "退出码 0" "0" "$?"
check "摘出的 URL（不吃 LAN 尾巴）" "APP_URL=http://127.0.0.1:3099/?token=TESTTOKEN123" "$(printf '%s' "$OUT" | tail -n 1)"
check "递给了 app 正确组件" "start -n app.dsh.mobile/.ui.MainActivity -e dsh_url http://127.0.0.1:3099/?token=TESTTOKEN123" "$(cat "$TMP/am.calls" 2>/dev/null | tr -d '\r')"
check "URL 也进了剪贴板" "http://127.0.0.1:3099/?token=TESTTOKEN123" "$(cat "$TMP/clipboard.txt" 2>/dev/null | tr -d '\r')"

# ---------- 用例 2：服务已在跑 → 复用分支 ----------
echo
echo "用例 2：服务已在运行 → 应复用日志里的 URL，不重启"
make_curl up
rm -f "$TMP/am.calls"
OUT2="$(bash "$START_SH" 3099 2>&1)"
check "退出码 0" "0" "$?"
check "提示复用" "1" "$(printf '%s' "$OUT2" | grep -c '已有服务在跑')"
check "仍然给出 APP_URL" "APP_URL=http://127.0.0.1:3099/?token=TESTTOKEN123" "$(printf '%s' "$OUT2" | tail -n 1)"

# ---------- 用例 3：自包含引导能自己写出 start-dsh.sh 并跑通 ----------
echo
echo "用例 3：phone-bootstrap.sh 自包含引导（不依赖 /sdcard 授权）"
make_curl down
rm -rf "$TMP/home/dsh-android" "$TMP/am.calls" "$TMP/home/.dsh-web.log"
OUT3="$(bash "$BOOT_SH" 2>&1)"
check "退出码 0" "0" "$?"
check "自己写出了 start-dsh.sh" "yes" "$([ -f "$TMP/home/dsh-android/start-dsh.sh" ] && echo yes || echo no)"
check "写出的脚本语法正确" "0" "$(bash -n "$TMP/home/dsh-android/start-dsh.sh" 2>/dev/null; echo $?)"
check "引导过程拿到 APP_URL" "APP_URL=http://127.0.0.1:3099/?token=TESTTOKEN123" "$(printf '%s' "$OUT3" | tail -n 1)"
check "引导过程也把地址递给了 app" "start -n app.dsh.mobile/.ui.MainActivity -e dsh_url http://127.0.0.1:3099/?token=TESTTOKEN123" "$(cat "$TMP/am.calls" 2>/dev/null | tr -d '\r')"
check "node-pty 编译产物被补上" "yes" "$([ -f "$TMP/home/dsh-install/node_modules/node-pty/build/Release/pty.node" ] && echo yes || echo no)"

# ---------- 用例 4：curl 崩了（Termux 升级了一半）→ 预检必须拦住并给修复命令 ----------
echo
echo "用例 4：curl 崩溃（新 libcurl 配旧 openssl）→ 预检应拦住并提示 apt full-upgrade"
cat > "$STUB/curl" <<'EOF'
#!/usr/bin/env bash
echo "CANNOT LINK EXECUTABLE \"curl\": cannot locate symbol \"SSL_set_quic_tls_early_data_enabled\"" >&2
exit 127
EOF
chmod +x "$STUB/curl"
set +e
OUT4="$(bash "$SETUP_SH" 2>&1)"
CODE4=$?
set -e
check "非零退出（拦住）" "1" "$CODE4"
# 断言"提示里有一条 apt 的 full-upgrade 指令"，但**不锁具体 flag**：
# setup-dsh.sh 现在打印的是 `apt update && apt -y full-upgrade`（带 -y 才能在无人值守时用），
# 以前这里写死 'apt full-upgrade' 就对不上了 —— 测试该盯的是"有没有这条指令"，不是它的写法。
check "提示了确切的修复命令" "1" "$(printf '%s' "$OUT4" | grep -cE 'apt .*full-upgrade')"
check "没有继续往下装依赖" "0" "$(printf '%s' "$OUT4" | grep -c '安装依赖')"

# ---------- 汇总 ----------
echo
echo "通过 $pass 项，失败 $fail 项"
echo "（配方单一事实源：tools/verify-install-recipe.sh 会打印并验证手机上要粘的那一行）"
rm -rf "$TMP"
[ "$fail" -eq 0 ]
