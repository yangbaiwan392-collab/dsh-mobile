# 一条命令完成"无线调试配对 + 连接"：不用你在手机上找端口（那个随机高位端口很难读）。
#
# 关键事实：Android 的**配对端口只在「使用配对码配对设备」对话框打开期间监听**，
# 关掉对话框端口就没了。所以运行本脚本时，请让那个对话框保持打开。
#
# 用法：
#   powershell -File tools\pair-phone.ps1 -Ip 192.168.0.104 -Code 123456
#   （可选）-SkipScan 已知端口时直接指定 -Ports 46393,13318
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Ip,
    [Parameter(Mandatory = $true)][string]$Code,
    [int[]]$Ports,
    [switch]$SkipScan
)

$ErrorActionPreference = 'Continue'
. "$PSScriptRoot\toolchain-env.ps1"
$adb = Join-Path $PlatformTools 'adb.exe'
if (-not (Test-Path $adb)) { throw "找不到 adb：$adb（先跑 tools\install-toolchain.ps1）" }

function Get-OpenPorts {
    $json = & node (Join-Path $PSScriptRoot 'scan-adb-ports.mjs') $Ip 1024 65535 --json 2>&1 | Select-Object -Last 1
    try { return (ConvertFrom-Json $json).open } catch { throw "扫描失败：$json" }
}

if (-not $Ports -or $Ports.Count -eq 0) {
    if ($SkipScan) { throw '指定了 -SkipScan 就必须给 -Ports' }
    Write-Host "==> 扫描 $Ip 的开放端口（约 2.5 分钟；期间请保持配对对话框打开）" -ForegroundColor Cyan
    $Ports = Get-OpenPorts
    Write-Host ("    开放端口：{0}" -f ($Ports -join ', '))
}
if (-not $Ports -or $Ports.Count -eq 0) { throw '没扫到任何开放端口：确认无线调试已打开、手机与电脑同一 Wi-Fi' }

& $adb start-server 2>&1 | Out-Null

$paired = $null
foreach ($port in $Ports) {
    Write-Host ("==> 试配对 {0}:{1}" -f $Ip, $port) -ForegroundColor Cyan
    $out = & $adb pair "$Ip`:$port" $Code 2>&1
    $text = ($out | Out-String).Trim()
    Write-Host ("    " + ($text -replace "`r?`n", ' | '))
    if ($text -match 'Successfully paired') { $paired = $port; break }
}

if (-not $paired) {
    Write-Host "`n配对没成功。常见原因：" -ForegroundColor Red
    Write-Host "  · 配对对话框已关闭（端口随之消失）—— 重新打开再跑本脚本"
    Write-Host "  · 配对码输错 / 已过期 —— 对话框里的码会变，用最新的"
    Write-Host "  · 手机与电脑不在同一网段，或路由器开了 AP 隔离"
    exit 1
}

Write-Host "`n==> 配对成功（端口 $paired），尝试连接" -ForegroundColor Green
foreach ($port in $Ports) {
    $out = & $adb connect "$Ip`:$port" 2>&1
    Write-Host ("    " + (($out | Out-String).Trim() -replace "`r?`n", ' | '))
}

Write-Host "`n==> 设备列表" -ForegroundColor Cyan
& $adb devices -l
