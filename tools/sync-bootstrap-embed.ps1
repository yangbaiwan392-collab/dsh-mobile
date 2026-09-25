# sync-bootstrap-embed.ps1 — 把 termux/start-dsh.sh 的内容同步进 termux/phone-bootstrap.sh 的内嵌段
#
# 为什么需要它：phone-bootstrap.sh 是"贴进 Termux 就能跑"的自包含脚本，不能 source 外部文件，
# 所以它必须内嵌一份 start-dsh.sh。历史上这两份是**各自手改**的，结果真的漂了：
# 内嵌那份少了 DSH_OLLAMA_KEY、也没有唤醒锁，而文件头却写着"拿唤醒锁并启动"（自相矛盾）。
# 现在改成：**内嵌段 = start-dsh.sh 的逐字副本**，只能由本脚本生成，不许手改。
#
# 用法：
#   powershell -File tools/sync-bootstrap-embed.ps1          # 同步（写回）
#   powershell -File tools/sync-bootstrap-embed.ps1 -Check   # 只核对，不一致就 exit 1（构建时用）
#
# tools/check-contracts.ps1 会调用 -Check 模式，所以漂了会直接让构建红。

[CmdletBinding()]
param(
  [switch]$Check
)

$ErrorActionPreference = 'Stop'
$enc = New-Object System.Text.UTF8Encoding($false)
$root = Split-Path -Parent $PSScriptRoot
$canonicalPath = Join-Path $root 'termux\start-dsh.sh'
$bootPath = Join-Path $root 'termux\phone-bootstrap.sh'

$canonical = [System.IO.File]::ReadAllText($canonicalPath, $enc).TrimEnd("`r", "`n")
$raw = [System.IO.File]::ReadAllText($bootPath, $enc)
$nl = if ($raw.Contains("`r`n")) { "`r`n" } else { "`n" }
$lines = [System.Collections.Generic.List[string]]::new()
$lines.AddRange([string[]]($raw -split "`r?`n"))

$startIdx = -1
$endIdx = -1
for ($i = 0; $i -lt $lines.Count; $i++) {
  if ($startIdx -lt 0 -and $lines[$i].TrimStart().StartsWith('cat > ') -and
      $lines[$i].Contains('start-dsh.sh') -and $lines[$i].Contains('<<')) {
    $startIdx = $i
    continue
  }
  if ($startIdx -ge 0 -and $lines[$i].TrimEnd() -eq 'SH') { $endIdx = $i; break }
}
if ($startIdx -lt 0 -or $endIdx -lt 0) { throw "在 $bootPath 里找不到 start-dsh.sh 的内嵌段（cat > … <<'SH' … SH）" }

# 只替换**包裹行之间的内容**：cat 行与 SH 终止行原样保留。
# 踩过的坑：早先的版本重建了边界行，结果把 cat 行弄丢、canonical 内容被摊平进 bootstrap
# （python: 见 CHANGELOG 2026-09-25 的那次失误），所以这里刻意不做任何边界行重建。
$embedded = ($lines[($startIdx + 1)..($endIdx - 1)] -join "`n").TrimEnd("`r", "`n")
$same = ($embedded -ceq $canonical)

if ($Check) {
  if ($same) {
    Write-Host '  内嵌副本与 termux/start-dsh.sh 一致 ✓'
    exit 0
  }
  Write-Host '  ✗ 内嵌副本与 termux/start-dsh.sh 不一致：' -ForegroundColor Red
  Write-Host ('    内嵌 {0} 字符 / 真身 {1} 字符' -f $embedded.Length, $canonical.Length)
  Write-Host '    跑一次 tools/sync-bootstrap-embed.ps1 即可同步（别手改内嵌段）'
  exit 1
}

if ($same) {
  Write-Host '已经一致，无需改动。'
  exit 0
}

$new = [System.Collections.Generic.List[string]]::new()
for ($i = 0; $i -le $startIdx; $i++) { $new.Add($lines[$i]) }
foreach ($l in ($canonical -split "`r?`n")) { $new.Add($l) }
for ($i = $endIdx; $i -lt $lines.Count; $i++) { $new.Add($lines[$i]) }

[System.IO.File]::WriteAllText($bootPath, ($new -join $nl) + $nl, $enc)
Write-Host ('已同步：内嵌段 {0} 行 → {1} 行' -f ($endIdx - $startIdx - 1), (($canonical -split "`n").Count))
