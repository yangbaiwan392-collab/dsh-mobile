# 把仓库里的脚本无损推到手机 Termux（避开三个真实的坑）：
#   1) PowerShell → adb 的传参会把单引号吃掉（重定向就跑到 shell 用户下 → Permission denied）
#      → 不用引号，改用 `run-as ... tee <path>`，重定向交给 tee；
#   2) PowerShell 管道默认按 ASCII/带 BOM 编码 → 中文被破坏、脚本首行多出 BOM
#      → 显式设 $OutputEncoding 为 UTF-8 无 BOM；
#   3) /sdcard 那条路受 Android 存储权限限制 → 直接写进 Termux 家目录。
#
# 用法：powershell -File tools\push-to-phone.ps1 [-Ip 192.168.0.104] [-Port 46393] [-File <本地文件>...]
[CmdletBinding()]
param(
    [string]$Ip = '192.168.0.104',
    [string]$Port = '46393',
    [string[]]$File = @(),
    [string]$RemoteDir = '/data/data/com.termux/files/home/dsh-android'
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\toolchain-env.ps1"
$adb = Join-Path $PlatformTools 'adb.exe'
$repo = Split-Path -Parent $PSScriptRoot

if ($File.Count -eq 0) {
    $File = @(
        (Join-Path $repo 'termux\start-dsh.sh'),
        (Join-Path $repo 'termux\setup-dsh.sh'),
        (Join-Path $repo 'termux\tunnel-to-pc.sh')
    )
}

& $adb connect "$Ip`:$Port" 2>&1 | Out-Null
# ⚠ 必须 join 成单个字符串：PowerShell 里对**数组**用 -notmatch 返回的是"不匹配的元素"，
#   直接当布尔用几乎恒为真（踩过）。
$devices = (& $adb devices) -join "`n"
if ($devices -notmatch "$([regex]::Escape($Ip))`:$Port\s+device") {
    throw "设备未连接：$Ip`:$Port（先 tools\pair-phone.ps1 配对；无线调试重启后端口会变）"
}

& $adb shell "run-as com.termux mkdir -p $RemoteDir" 2>&1 | Out-Null
$OutputEncoding = New-Object System.Text.UTF8Encoding $false   # 无 BOM 的 UTF-8

foreach ($path in $File) {
    if (-not (Test-Path $path)) { throw "找不到本地文件：$path" }
    $name = Split-Path -Leaf $path
    $text = Get-Content $path -Raw -Encoding UTF8
    $expected = ([Text.Encoding]::UTF8.GetBytes($text)).Length
    $text | & $adb shell "run-as com.termux tee $RemoteDir/$name" | Out-Null
    $size = (& $adb shell "run-as com.termux wc -c < $RemoteDir/$name") -join ''
    $sizeInt = [int]($size.Trim())
    $ok = ($sizeInt -eq $expected)
    Write-Host ("  {0,-18} 本地 {1} 字节 → 手机 {2} 字节  {3}" -f $name, $expected, $sizeInt, $(if ($ok) { '✓' } else { '✗ 不一致' }))
    if (-not $ok) { throw "传输不一致：$name" }
}
Write-Host "`n完成。手机目录：$RemoteDir" -ForegroundColor Green
