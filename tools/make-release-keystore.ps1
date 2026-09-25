# make-release-keystore.ps1 — 生成**正式分发**用的签名密钥（一次性；生成后请备份到安全的地方）
#
# 为什么需要它：仓库里的 `signing/debug.keystore` 是**调试**密钥，口令是公开的
# （`android`/`androiddebugkey`，见 SECURITY.md），任何拿到源码的人都能拿它签一个"看起来是同一个 app"的包。
# 调试密钥只适合自己装、不适合分发。正式分发要用你自己的密钥。
#
# ⚠️ 三条铁律（都写在这里，因为违反它们的代价是不可逆的）：
#   1. **keystore 文件 + 口令丢了 = 你再也无法给已安装的用户升级**（Android 只认同一把密钥的升级包）。
#      生成后请立刻把它和 `android/keystore.properties` 备份到**仓库之外**（密码管理器 / 离线介质）。
#   2. 两者都**不要提交**：本脚本会写进 `.gitignore` 已覆盖的位置（`android/signing/release.keystore`
#      与 `android/keystore.properties`）。
#   3. 本脚本**默认拒绝覆盖**已有 keystore —— 覆盖等于毁掉升级路径。真要重做请显式 `-Force` 并明白后果。
#
# 用法：
#   powershell -File tools/make-release-keystore.ps1                 # 生成（随机强口令）
#   powershell -File tools/make-release-keystore.ps1 -Alias mykey    # 指定别名（默认 dsh-mobile）
#
# 之后：
#   powershell -File tools/build-apk.ps1 -Task assembleRelease       # 出正式签名 APK（dist/ 下会有 release 包）
#   详见 RELEASING.md

[CmdletBinding()]
param(
    [string]$Alias = 'dsh-mobile',
    [string]$Dname = 'CN=DSH Mobile, OU=Release, O=DSH Mobile, L=, ST=, C=CN',
    [int]$ValidityDays = 10950,          # 30 年：Android 的惯例是"签名要活过 app 的寿命"
    [string]$Password,                    # 不给就随机生成 32 位
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$signingDir = Join-Path $root 'android\signing'
$keystore = Join-Path $signingDir 'release.keystore'
$propsFile = Join-Path $root 'android\keystore.properties'

. "$PSScriptRoot\toolchain-env.ps1"
$keytool = Join-Path $Jdk 'bin\keytool.exe'
if (-not (Test-Path $keytool)) { throw "找不到 keytool：$keytool（先跑 tools\install-toolchain.ps1）" }

if ((Test-Path $keystore) -and -not $Force) {
    throw @"
已存在正式密钥：$keystore
本脚本默认不覆盖 —— **覆盖它等于让所有已安装的旧版本无法升级**。
确实要重做（例如密钥已泄漏）：先备份现有文件，再带 -Force 重跑。
"@
}

if (-not $Password) {
    # 32 位随机口令（去掉容易看错的字符）；只写进 keystore.properties，不打印到控制台之外的地方
    $alphabet = 'abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789'
    $Password = -join (1..32 | ForEach-Object { $alphabet[(Get-Random -Maximum $alphabet.Length)] })
}

New-Item -ItemType Directory -Force -Path $signingDir | Out-Null

Write-Host '==> 生成正式签名密钥' -ForegroundColor Cyan
& $keytool -genkeypair -v `
    -keystore $keystore `
    -alias $Alias `
    -keyalg RSA -keysize 4096 `
    -validity $ValidityDays `
    -storepass $Password -keypass $Password `
    -dname $Dname 2>&1 | Select-Object -Last 3

if (-not (Test-Path $keystore)) { throw "密钥生成失败：$keystore" }

# 写 keystore.properties（gradle 读它；被 gitignore）
$props = @(
    "# 正式签名配置 —— 由 tools/make-release-keystore.ps1 生成",
    "# ⚠️ 本文件含口令，**不要提交**（.gitignore 已覆盖）；丢了就无法给已安装用户升级，请与 keystore 一起备份到仓库之外。",
    "storeFile=signing/release.keystore",
    "storePassword=$Password",
    "keyAlias=$Alias",
    "keyPassword=$Password"
) -join "`n"
[System.IO.File]::WriteAllText($propsFile, $props + "`n", (New-Object System.Text.UTF8Encoding($false)))

Write-Host ''
Write-Host '==> 证书指纹（发版说明里可以贴上，方便别人核对）' -ForegroundColor Cyan
& $keytool -list -v -keystore $keystore -storepass $Password -alias $Alias 2>&1 |
    Select-String -Pattern 'SHA256:|SHA1:|Valid from' | ForEach-Object { "  $($_.Line.Trim())" }

Write-Host ''
Write-Host '==> 下一步（很重要，别跳过）' -ForegroundColor Yellow
Write-Host "  1. **立刻备份**这两个文件到仓库之外（密码管理器 / 离线介质）："
Write-Host "       $keystore"
Write-Host "       $propsFile"
Write-Host '     丢了 = 你再也无法给已安装的用户发升级包。'
Write-Host '  2. 确认它们没被 git 跟踪：git status --short 里不该出现这两个文件。'
Write-Host '  3. 出正式包：powershell -File tools/build-apk.ps1 -Task assembleRelease'
Write-Host '     产物会是 release 签名（不再是 debug），可以分发了。'
