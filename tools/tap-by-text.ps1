# 按屏幕上的文字找到控件并点它（比手算坐标可靠得多）。
#
# 用法：
#   powershell -File tools\tap-by-text.ps1 -Text "环境自检"              # 点它
#   powershell -File tools\tap-by-text.ps1 -Text "环境自检" -NoTap      # 只找位置
#   powershell -File tools\tap-by-text.ps1 -Key 82                     # 打开溢出菜单（MENU 键）
#
# 为何不用固定坐标：真机上横竖屏、菜单展开、字体大小都会让坐标变，而 uiautomator 的
# bounds 是布局算出来的真值。
[CmdletBinding()]
param(
    [string]$Text,
    [int]$Key,
    [string]$Ip,
    [string]$Port,
    [string]$Remote = '/sdcard/_ui_dump.xml',
    [switch]$NoTap
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\toolchain-env.ps1"
$adb = Join-Path $PlatformTools 'adb.exe'

# 设备解析：给了 -Ip/-Port 就用它；没给就**自动用唯一在线的那台**。
# （以前这里写死过一台手机的地址，换机后白跑一次 —— 别再写死。）
if ($Ip) {
    & $adb connect "$Ip`:$Port" 2>&1 | Out-Null
    $serial = "$Ip`:$Port"
} else {
    $online = (& $adb devices) | Where-Object { $_ -match '\sdevice$' } | ForEach-Object { ($_ -split '\s+')[0] }
    $online = @($online)
    if ($online.Count -eq 0) { throw '没有在线设备：先 adb connect <ip>:<port>，或用 -Ip/-Port 指定' }
    if ($online.Count -gt 1) { throw ("有 $($online.Count) 台在线设备：$($online -join ', ') —— 请用 -Ip/-Port 指定") }
    $serial = $online[0]
}
Write-Host ("设备：{0}" -f $serial) -ForegroundColor DarkGray
$devices = (& $adb devices) -join "`n"
if ($devices -notmatch "$([regex]::Escape($serial))\s+device") { throw "设备未连接：$serial" }
function Adb { & $adb -s $serial @args }
$stamp = (Get-Date -Format HH:mm:ss)
Write-Host ("开始：{0}" -f $stamp) -ForegroundColor DarkGray

if ($Key -gt 0) {
    Write-Host ("按键 event {0}" -f $Key)
    Adb shell "input keyevent $Key" | Out-Null
    Start-Sleep -Milliseconds 800
    if (-not $Text) { return }
}

if (-not $Text) { throw '要么给 -Text，要么给 -Key' }

$local = Join-Path $env:TEMP 'ui_dump.xml'
# 先删掉远端与本地旧文件：uiautomator dump 在"界面没静止"时会失败，但**旧文件还在**，
# 于是脚本会拿着上一屏的坐标去点 —— 比报错危险得多（踩过）。
& $adb shell "rm -f $Remote" 2>&1 | Out-Null
Remove-Item $local -ErrorAction SilentlyContinue
$dumpOut = & $adb shell "uiautomator dump $Remote" 2>&1
if ($dumpOut -notmatch 'dumped to') {
    Write-Host "dump 失败：$dumpOut" -ForegroundColor Red
    exit 2
}
& $adb pull $Remote $local 2>&1 | Out-Null
if (-not (Test-Path $local)) { Write-Host '本地没拿到 dump' -ForegroundColor Red; exit 2 }
$xml = [xml](Get-Content $local -Raw)

$nodes = $xml.SelectNodes('//node')
# 优先精确匹配，再退化到包含匹配。
# 来历：点「允许」时，对话框正文「要允许…吗？」也含"允许"，子串匹配会点到正文上。
$hit = $nodes | Where-Object { $_.text -eq $Text -or $_.'content-desc' -eq $Text } | Select-Object -First 1
if (-not $hit) {
    $hit = $nodes | Where-Object { $_.text -like "*$Text*" -or $_.'content-desc' -like "*$Text*" } | Select-Object -First 1
    if ($hit) { Write-Host ("（没有精确匹配，退化到包含匹配：{0}）" -f $hit.text) -ForegroundColor Yellow }
}
if (-not $hit) {
    Write-Host ("没找到含「{0}」的控件。当前屏幕上的文字有：" -f $Text) -ForegroundColor Yellow
    $xml.SelectNodes('//node') | Where-Object { $_.text } | ForEach-Object { "   · " + $_.text } | Select-Object -First 25
    exit 1
}

$b = $hit.bounds
$m = [regex]::Match($b, '\[(\d+),(\d+)\]\[(\d+),(\d+)\]')
if (-not $m.Success) { throw "解析 bounds 失败：$b" }
$x = [int](([int]$m.Groups[1].Value + [int]$m.Groups[3].Value) / 2)
$y = [int](([int]$m.Groups[2].Value + [int]$m.Groups[4].Value) / 2)
Write-Host ("找到「{0}」 bounds={1} → 点 ({2},{3})" -f $hit.text, $b, $x, $y) -ForegroundColor Green
if (-not $NoTap) {
    & $adb shell "input tap $x $y" | Out-Null
    Write-Host '已点击'
}
