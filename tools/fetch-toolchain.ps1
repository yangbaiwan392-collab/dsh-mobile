# 拉 Android 工具链（全部走国内镜像；本机 storage.googleapis.com 只有 ~80 KB/s，别直连）
#
# 这是**唯一**存放工具链 URL 的地方 —— 换版本只改这个文件。
# 只负责"下载 + 校验是个能打开的 zip"，不负责展开布局（那是 install-toolchain.ps1 的事）。
#
# 用法：powershell -NoProfile -ExecutionPolicy Bypass -File tools\fetch-toolchain.ps1
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem

. "$PSScriptRoot\toolchain-env.ps1"     # 工具链位置只在 toolchain-env.ps1 里定义
$Dl = $Downloads
New-Item -ItemType Directory -Force -Path $Dl | Out-Null

$MirrorAndroid = 'https://mirrors.cloud.tencent.com/AndroidSDK/'
$MirrorGradle  = 'https://mirrors.cloud.tencent.com/gradle/'

$Packages = @(
    @{ Name = 'commandlinetools'; Url = $MirrorAndroid + 'commandlinetools-win-11076708_latest.zip'; Out = "$Dl\cmdline-tools.zip" }
    @{ Name = 'platform-tools';   Url = $MirrorAndroid + 'platform-tools_r34.0.5-windows.zip';        Out = "$Dl\platform-tools.zip" }
    @{ Name = 'build-tools-34';   Url = $MirrorAndroid + 'build-tools_r34-windows.zip';              Out = "$Dl\build-tools-34.zip" }
    @{ Name = 'platform-35';      Url = $MirrorAndroid + 'platform-35_r02.zip';                       Out = "$Dl\platform-35.zip" }
    @{ Name = 'gradle-8.11.1';    Url = $MirrorGradle  + 'gradle-8.11.1-bin.zip';                     Out = "$Dl\gradle-8.11.1-bin.zip" }
    @{ Name = 'jdk-17';           Url = 'https://aka.ms/download-jdk/microsoft-jdk-17-windows-x64.zip'; Out = "$Dl\jdk17.zip" }
)

# 真校验：能当 zip 打开，且至少有一个条目。不做"猜字节数"这种假校验。
function Test-Zip([string]$path) {
    if (-not (Test-Path $path)) { return $false }
    try {
        $zip = [IO.Compression.ZipFile]::OpenRead($path)
        try { return ($zip.Entries.Count -gt 0) } finally { $zip.Dispose() }
    } catch { return $false }
}

foreach ($pkg in $Packages) {
    if (Test-Zip $pkg.Out) {
        Write-Host ("[skip] {0} 已下载且 zip 可读（{1:N1} MB）" -f $pkg.Name, ((Get-Item $pkg.Out).Length / 1MB)) -ForegroundColor DarkGray
        continue
    }
    Write-Host ("[下载] {0}" -f $pkg.Name) -ForegroundColor Cyan
    & curl.exe -L --fail --retry 3 --retry-delay 2 -C - -sS -o $pkg.Out $pkg.Url
    if ($LASTEXITCODE -ne 0) { throw "下载失败：$($pkg.Name)  $($pkg.Url)" }
    if (-not (Test-Zip $pkg.Out)) { throw "下载后不是可读 zip：$($pkg.Out)" }
    Write-Host ("       ok  {0:N1} MB" -f ((Get-Item $pkg.Out).Length / 1MB)) -ForegroundColor Green
}

Write-Host "`n全部就位：$Dl" -ForegroundColor Green
