# 把 _dl 里下好的 zip 展开成可用的 SDK / JDK / Gradle 布局，并逐项验证。
#
# 只负责"布局 + 验证"，不负责下载（那是 fetch-toolchain.ps1 的事）。
# 幂等：已展开的目录会跳过。
#
# 用法：powershell -NoProfile -ExecutionPolicy Bypass -File tools\install-toolchain.ps1
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem

. "$PSScriptRoot\toolchain-env.ps1"     # 工具链位置只在 toolchain-env.ps1 里定义
$Dl       = $Downloads
$JavaHome = $Jdk

# 展开一个 zip，返回它唯一的顶层目录（Android 官方 zip 都是单顶层目录）
function Expand-SingleRoot([string]$zipPath, [string]$destParent) {
    $tmp = Join-Path $destParent ('.tmp-' + [IO.Path]::GetFileNameWithoutExtension($zipPath))
    if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $tmp, $destParent | Out-Null
    [IO.Compression.ZipFile]::ExtractToDirectory($zipPath, $tmp)
    $roots = @(Get-ChildItem $tmp -Directory)
    if ($roots.Count -ne 1) { throw "zip 顶层不是单一目录：$zipPath（$($roots.Count) 个）" }
    return @{ Tmp = $tmp; Root = $roots[0].Name }
}

function Place([string]$zipPath, [string]$destParent, [string]$destName) {
    $dest = Join-Path $destParent $destName
    if (Test-Path $dest) { Write-Host "[skip] 已在位 $dest" -ForegroundColor DarkGray; return $dest }
    $r = Expand-SingleRoot $zipPath $destParent
    Move-Item (Join-Path $r.Tmp $r.Root) $dest
    Remove-Item $r.Tmp -Recurse -Force
    Write-Host "[展开] $dest" -ForegroundColor Cyan
    return $dest
}

# 外部程序（java/adb/gradle）常把版本写到 stderr；$ErrorActionPreference='Stop' 会把
# 2>&1 的重定向当成终止错误。所有外部探针都走这个函数（临时降级 + 经 cmd 捕获两路输出）。
function Invoke-Probe([string]$exe, [string[]]$cmdArgs) {
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        if (-not (Test-Path $exe)) { return $null }
        $line = & cmd.exe /c "`"$exe`" $($cmdArgs -join ' ') 2>&1" | Select-Object -First 2
        return (($line | Where-Object { $_ -and $_.ToString().Trim() -ne '' }) -join ' | ')
    } finally { $ErrorActionPreference = $prev }
}

New-Item -ItemType Directory -Force -Path $Sdk, "$Sdk\licenses" | Out-Null

# --- JDK ---
# 必须用 $AndroidRoot（toolchain-env.ps1 解析出来的根），**不要写死 E:\Android** ——
# 换机器/CI 上没有 E: 盘，写死就等于装不上（同一类问题在 CI 上已经红过一次）。
Place "$Dl\jdk17.zip" $AndroidRoot 'jdk17' | Out-Null
$env:JAVA_HOME = $JavaHome
$env:PATH = "$JavaHome\bin;$env:PATH"
Write-Host ("  java: {0}" -f (Invoke-Probe "$JavaHome\bin\java.exe" @('-version'))) -ForegroundColor Green

# --- SDK 组件 ---
Place "$Dl\platform-tools.zip" $Sdk 'platform-tools' | Out-Null
Place "$Dl\build-tools-34.zip" "$Sdk\build-tools" '34.0.0' | Out-Null
Place "$Dl\platform-35.zip" "$Sdk\platforms" 'android-35' | Out-Null
Place "$Dl\cmdline-tools.zip" "$Sdk\cmdline-tools" 'latest' | Out-Null

# cmdline-tools 的 zip 顶层是 cmdline-tools/，上一行会得到 cmdline-tools/latest/{bin,lib,...}？不一定 —— 统一兜一层
$probe = "$Sdk\cmdline-tools\latest\bin\sdkmanager.bat"
if (-not (Test-Path $probe) -and (Test-Path "$Sdk\cmdline-tools\latest\cmdline-tools\bin\sdkmanager.bat")) {
    $inner = "$Sdk\cmdline-tools\latest\cmdline-tools"
    Get-ChildItem $inner | Move-Item -Destination "$Sdk\cmdline-tools\latest"
    Remove-Item $inner -Force
}

# --- Gradle ---
Place "$Dl\gradle-8.11.1-bin.zip" $AndroidRoot 'gradle-8.11.1' | Out-Null

# --- SDK 许可（AGP 会检查 licenses 目录；这是 SDK 官方许可文本的哈希） ---
$licenseFile = "$Sdk\licenses\android-sdk-license"
if (-not (Test-Path $licenseFile)) {
    @(
        '24333f8a63b6825ea9c5514f83c2829b004d1fee'
        'd56f5187479451eabf01fb78af6dfcb131a6481e'
        '8933bad161af4178b1185d1a37fbf41ea5269c55'
    ) | Set-Content -Encoding ascii $licenseFile
    Write-Host "[写入] $licenseFile" -ForegroundColor Cyan
}

# --- 验证（每一条都要有输出，不做"应该没问题"） ---
Write-Host "`n=== 验证 ===" -ForegroundColor Yellow
$checks = @(
    @{ Name = 'java';       Path = "$JavaHome\bin\java.exe";                          Args = @('-version') }
    @{ Name = 'aapt2';      Path = "$Sdk\build-tools\34.0.0\aapt2.exe";               Args = @('version') }
    @{ Name = 'adb';        Path = "$Sdk\platform-tools\adb.exe";                     Args = @('version') }
    @{ Name = 'gradle';     Path = "$Gradle\bin\gradle.bat";                          Args = @('-v') }
    @{ Name = 'sdkmanager'; Path = "$Sdk\cmdline-tools\latest\bin\sdkmanager.bat";    Args = @('--version') }
)
$failed = @()
foreach ($c in $checks) {
    $out = Invoke-Probe $c.Path $c.Args
    if ($null -eq $out) { Write-Host ("  [{0}] 缺失：{1}" -f $c.Name, $c.Path) -ForegroundColor Red; $failed += $c.Name; continue }
    Write-Host ("  [{0}] {1}" -f $c.Name, $out) -ForegroundColor Green
}
if ($failed.Count -gt 0) { throw "以下组件未就绪：$($failed -join ', ')" }
Write-Host "`nSDK=$Sdk  JAVA_HOME=$JavaHome  GRADLE=$Gradle" -ForegroundColor Green
