#!/data/data/com.termux/files/usr/bin/bash
# 修 Termux 的"升级了一半"状态 + 把卡住的 dpkg 收尾（真机实测两处都会踩）：
#
#  1) pkg 装了 curl 却没同步 openssl → curl 崩（CANNOT LINK EXECUTABLE ... SSL_set_quic_tls_early_data_enabled），
#     连锁让 nodejs-lts / node 都装不上；
#  2) apt 遇到 openssl.cnf 这类 conffile 会**停下来等输入**（*** openssl.cnf (Y/I/N/O/D/Z) ?），
#     在无人值守的安装流程里就是永久卡死 —— 必须 DEBIAN_FRONTEND=noninteractive + --force-confnew。
#
# 用法： bash repair-termux.sh   （输出追加到 ~/dsh-android-install.log）
set -u

# run-as 下 HOME 会变成 /data/user/0/com.termux —— 必须显式定死（踩过）
export HOME=/data/data/com.termux/files/home
export PATH=/data/data/com.termux/files/usr/bin:$PATH
export DEBIAN_FRONTEND=noninteractive
LOG="$HOME/dsh-android-install.log"

log() { echo "$@" >> "$LOG"; }
APT_OPTS=(-y -o Dpkg::Options::=--force-confnew -o Dpkg::Options::=--force-confdef)

log ""
log "=== $(date '+%F %T') 修复 Termux 包树（非交互）==="
log "升级前 curl：$(curl --version 2>&1 | head -1)"

# 1) 先把可能卡住的 apt/dpkg 收掉（卡在提示符上时，进程会一直挂着）
if pgrep -x apt >/dev/null 2>&1 || pgrep -x dpkg >/dev/null 2>&1; then
  log "检测到卡住的 apt/dpkg，先终止"
  pkill -x apt >/dev/null 2>&1 || true
  pkill -x dpkg >/dev/null 2>&1 || true
  sleep 2
fi
# 2) 把上次中断的事务收尾（非交互；openssl.cnf 一律取新版本）
dpkg --configure -a >> "$LOG" 2>&1 || log "（dpkg --configure -a 有报错，继续）"

apt update >> "$LOG" 2>&1 || log "!! apt update 失败"
apt "${APT_OPTS[@]}" full-upgrade >> "$LOG" 2>&1 || log "!! full-upgrade 有报错（见上）"
dpkg --configure -a >> "$LOG" 2>&1 || true

log "升级后 curl：$(curl --version 2>&1 | head -1)"
log "=== $(date '+%F %T') 修复结束 ==="
