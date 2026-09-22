#!/usr/bin/env bash
# 用桩命令在本机**真跑** termux/start-dsh.sh，验证它：
#   ① 语法能过；② 能从 dsh 的输出里正确摘出带 token 的 URL；
#   ③ 递给 app 的组件名/extra 键与 Android 侧一致（这是最容易写错、且在手机上会静默失败的一环）。
#
# 为什么需要：本机没有 Termux、也没有已注册的 WSL 发行版，手机是第一次真跑；
# 这个脚本把"能不能跑通"提前到本机，用 Git for Windows 自带的 bash 执行。
#
# 用法： "C:\Program Files\Git\bin\bash.exe" tools/test-termux-scripts.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
START_SH="$ROOT/termux/start-dsh.sh"
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

# ---------- 桩命令 ----------
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
cat > "$STUB/nohup" <<'EOF'
#!/usr/bin/env bash
exec "$@"
EOF
cat > "$STUB/sleep" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$STUB"/*
export PATH="$STUB:$PATH"
unset NOHUP 2>/dev/null || true

# ---------- 语法检查 ----------
echo "语法检查（bash -n）："
for f in "$ROOT"/termux/*.sh; do
  if bash -n "$f"; then printf '  ok   %s\n' "$(basename "$f")"; pass=$((pass + 1));
  else printf '  FAIL %s 语法错误\n' "$(basename "$f")"; fail=$((fail + 1)); fi
done

# ---------- 用例 1：服务没在跑 → 启动分支 ----------
echo
echo "用例 1：服务未运行（curl 桩返回非零）→ 应启动并摘出 URL"
cat > "$STUB/curl" <<'EOF'
#!/usr/bin/env bash
exit 7
EOF
chmod +x "$STUB/curl"
OUT="$(bash "$START_SH" 3099 2>&1)"
check "退出码 0" "0" "$?"
check "摘出的 URL（不吃 LAN 尾巴）" "APP_URL=http://127.0.0.1:3099/?token=TESTTOKEN123" "$(printf '%s' "$OUT" | tail -n 1)"
check "递给了 app 正确组件" "start -n app.dsh.mobile/.ui.MainActivity -e dsh_url http://127.0.0.1:3099/?token=TESTTOKEN123" "$(cat "$TMP/am.calls" 2>/dev/null | tr -d '\r')"
check "URL 也进了剪贴板" "http://127.0.0.1:3099/?token=TESTTOKEN123" "$(cat "$TMP/clipboard.txt" 2>/dev/null | tr -d '\r')"

# ---------- 用例 2：服务已在跑 → 复用分支 ----------
echo
echo "用例 2：服务已在运行（curl 桩返回 0）→ 应复用日志里的 URL，不重启"
cat > "$STUB/curl" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$STUB/curl"
rm -f "$TMP/am.calls"
OUT2="$(bash "$START_SH" 3099 2>&1)"
check "退出码 0" "0" "$?"
check "提示复用" "1" "$(printf '%s' "$OUT2" | grep -c '已有服务在跑')"
check "仍然给出 APP_URL" "APP_URL=http://127.0.0.1:3099/?token=TESTTOKEN123" "$(printf '%s' "$OUT2" | tail -n 1)"

# ---------- 用例 3：自包含引导（无需存储权限）能自己写出 start-dsh.sh 并跑通 ----------
echo
echo "用例 3：phone-bootstrap.sh 自包含引导（不依赖 /sdcard 授权）"
cat > "$STUB/pkg" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat > "$STUB/npm" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "config" ]; then echo "https://registry.npmmirror.com"; fi
exit 0
EOF
cat > "$STUB/node" <<'EOF'
#!/usr/bin/env bash
echo v22.0.0
EOF
cat > "$STUB/dsh" <<'EOF'
#!/usr/bin/env bash
echo "dsh web: http://127.0.0.1:3099/?token=BOOTTOKEN (LAN: http://192.168.0.105:3099/?token=BOOTTOKEN)"
EOF
cat > "$STUB/termux-wake-lock" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$STUB"/*
# 清掉上一用例留下的日志与"服务已在跑"状态，让它真正走"启动"分支
rm -rf "$TMP/home/dsh-android" "$TMP/am.calls" "$TMP/home/.dsh-web.log"
cat > "$STUB/curl" <<'EOF'
#!/usr/bin/env bash
exit 7
EOF
chmod +x "$STUB/curl"
OUT3="$(bash "$ROOT/termux/phone-bootstrap.sh" 2>&1)"
check "退出码 0" "0" "$?"
check "自己写出了 start-dsh.sh" "yes" "$([ -f "$TMP/home/dsh-android/start-dsh.sh" ] && echo yes || echo no)"
check "写出的脚本语法正确" "0" "$(bash -n "$TMP/home/dsh-android/start-dsh.sh"; echo $?)"
check "引导过程拿到 APP_URL" "APP_URL=http://127.0.0.1:3099/?token=BOOTTOKEN" "$(printf '%s' "$OUT3" | tail -n 1)"
check "引导过程也把地址递给了 app" "start -n app.dsh.mobile/.ui.MainActivity -e dsh_url http://127.0.0.1:3099/?token=BOOTTOKEN" "$(cat "$TMP/am.calls" 2>/dev/null | tr -d '\r')"

# ---------- 汇总 ----------
echo
echo "通过 $pass 项，失败 $fail 项"
rm -rf "$TMP"
[ "$fail" -eq 0 ]
