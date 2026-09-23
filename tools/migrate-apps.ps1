# 把旧手机上**用户安装的 app**（含 X / YouTube / ChatGPT / Telegram / VPN 这类）整包搬到新手机。
#
# 为什么需要：换机工具（含 Google 的"复制应用"）**不会**可靠地搬侧载/非 Play 应用的 APK，
# 而这些 app 恰恰要"先挂 VPN 才能下载"—— 从自己手机上拉包最省事，也避免装到不对劲的版本。
#
# 注意：**只搬安装包，不搬数据与登录态**（那是 app 自己的安全设计，谁也绕不过）；
# 新机上仍需登录一次（配合密码管理器就很快）。
#
# 用法：
#   # 先看看旧机上都有什么（不改动任何东西）
#   powershell -File tools\migrate-apps.ps1 -From 192.168.0.104:46393 -To 192.168.0.11:46393 -ListOnly
#   # 只搬指定的几个
#   powershell -File tools\migrate-apps.ps1 -From <旧> -To <新> -Only com.instagram.android,org.telegram.messenger,com.openai.chatgpt
#   # 全搬（用户安装的全部）
#   powershell -File tools\migrate-apps.ps1 -From <旧> -To <新>
#
# 前置：两台手机都开无线调试；`adb devices` 里能看到两个串号（`-From`/`-To` 就是串号）。
# 旧机上只会做三件**只读**操作：列包、查路径、拉文件。
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$From,
    [Parameter(Mandatory = $true)][string]$To,
    [string[]]$Only = @(),
    [switch]$ListOnly,
    [string]$OutDir = "$env:TEMP\dsh-app-migration"
)

$ErrorActionPreference = 'Continue'
. "$PSScriptRoot\toolchain-env.ps1"
$adb = Join-Path $PlatformTools 'adb.exe'

# 说明：这里刻意用最朴素的 `& $adb … 2>&1` 调用。
# 试过用 Start-Process + 重定向做超时包装，结果**反而会挂住**：adb 会常驻一个 daemon，
# 它继承了重定向的文件句柄，父进程永远等不到管道关闭（今天实测踩到）。
# 朴素调用在本会话所有 adb 脚本里都没挂过；**唯一会卡的情形是串号 offline/不可达** ——
# 所以：先 adb connect 两台手机，再跑本脚本；真卡住了 Ctrl+C，`adb kill-server` 重来。

function AdbTo { & $adb -s $To @args }

"=== 设备检查 ==="
& $adb start-server 2>&1 | Out-Null
# ⚠ 对**数组**用 -notmatch 返回的是"不匹配的元素"，不能当布尔用 —— 所以 join 成字符串再判
$devices = (& $adb devices -l) -join "`n"
foreach ($serial in @($From, $To)) {
    if ($devices -notmatch [regex]::Escape($serial) + '\s+device') {
        throw ("设备不在线：{0}。先执行 adb connect {0}（端口见手机无线调试页），再跑本脚本。" -f $serial)
    }
}
$modelFrom = (& $adb -s $From shell getprop ro.product.model).Trim()
$modelTo = (& $adb -s $To shell getprop ro.product.model).Trim()
Write-Host ("    旧机 {0}（{1}） → 新机 {2}（{3}）" -f $From, $modelFrom, $To, $modelTo) -ForegroundColor Green

"`n=== 旧机上用户安装的 app ==="
$lines = (& $adb -s $From shell pm list packages -3 -f) -split "`r?`n" | Where-Object { $_ }
$apps = foreach ($line in $lines) {
    $m = [regex]::Match($line, '^package:(?<path>[^=]+)=(?<pkg>\S+)$')
    if ($m.Success) { [pscustomobject]@{ Package = $m.Groups['pkg'].Value; BasePath = $m.Groups['path'].Value } }
}
if ($Only.Count -gt 0) { $apps = $apps | Where-Object { $Only -contains $_.Package } }
Write-Host ("    共 {0} 个" -f @($apps).Count)
@($apps) | ForEach-Object { Write-Host ("      {0}" -f $_.Package) }
if ($ListOnly) { Write-Host "`n（-ListOnly：到此为止，什么都没改）" -ForegroundColor DarkGray; return }
if (@($apps).Count -eq 0) { Write-Host "没有匹配的包，结束" -ForegroundColor Yellow; return }

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$ok = @(); $fail = @()
foreach ($app in $apps) {
    $pkg = $app.Package
    # 一个包可能有多个 split（base + config.*），必须一起装 —— 用 pm path 列全
    $paths = (AdbFrom shell "pm path $pkg") -split "`r?`n" |
        ForEach-Object { $_ -replace '^package:', '' } | Where-Object { $_ }
    if (@($paths).Count -eq 0) { $fail += "$pkg（拿不到路径）"; continue }

    $dir = Join-Path $OutDir $pkg
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $localFiles = @()
    $pullOk = $true
    foreach ($remote in $paths) {
        $name = Split-Path $remote -Leaf
        $local = Join-Path $dir $name
        & $adb -s $From pull $remote $local 2>&1 | Out-Null
        if (Test-Path $local) { $localFiles += $local } else { $pullOk = $false }
    }
    if (-not $pullOk -or $localFiles.Count -eq 0) { $fail += "$pkg（拉取失败）"; continue }

    $res = (AdbTo install-multiple -r @localFiles) 2>&1 | Select-Object -Last 1
    if ($res -match 'Success') { $ok += $pkg } else { $fail += "$pkg（安装：$res）" }
    Write-Host ("    {0,-42} {1}" -f $pkg, $(if ($res -match 'Success') { '✓' } else { '✗' }))
}

"`n=== 结果 ==="
Write-Host ("    成功 {0} 个，失败 {1} 个" -f $ok.Count, $fail.Count) -ForegroundColor Green
if ($fail.Count) { Write-Host "    失败明细："; $fail | ForEach-Object { Write-Host ("      - {0}" -f $_) -ForegroundColor Yellow }
    Write-Host "    （有些包如银行类会拒绝侧载；它们用 Play 装即可）" -ForegroundColor DarkGray }
Write-Host ("`n    安装包已缓存到：{0}（可删）" -f $OutDir) -ForegroundColor DarkGray
Write-Host "    下一步：在新机上逐个登录。建议先把 VPN 装好并导入配置，再登录其余 app。" -ForegroundColor Cyan
