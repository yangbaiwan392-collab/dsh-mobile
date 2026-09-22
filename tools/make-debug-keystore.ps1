# 生成/复用**工程自带**的调试签名密钥（唯一入口）。
#
# 为什么要自己生成、而不用 ~/.android/debug.keystore：
#   AGP 自动生成的那把，生效时间 = 构建那一刻。只要手机时钟比它早（哪怕差几分钟/时区偏移），
#   Android 就认为"证书尚未生效"，安装时报**签名错误**（本次真机踩到）。
#   而且它在仓库之外，被重建一次，以后所有升级都会报签名不一致。
#
# 本脚本生成的这把：生效时间从 2020-01-01 起、有效期 30 年 —— 不可能被时钟偏差咬到，
# 并且随仓库走，换机器/重装系统后签名依旧一致。
#
# 用法：powershell -File tools\make-debug-keystore.ps1 [-Force]
[CmdletBinding()]
param([switch]$Force)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\toolchain-env.ps1"     # 工具链位置只在 toolchain-env.ps1 里定义
$Keytool  = Join-Path $Jdk 'bin\keytool.exe'
$Keystore = Join-Path (Split-Path -Parent $PSScriptRoot) 'android\signing\debug.keystore'

if (-not (Test-Path $Keytool)) { throw "缺 keytool：$Keytool（先跑 tools\install-toolchain.ps1）" }
if ((Test-Path $Keystore) -and -not $Force) {
    Write-Host "[skip] 密钥已存在：$Keystore（要重建加 -Force，注意：重建会让已装的版本必须卸载后才能装）" -ForegroundColor DarkGray
    exit 0
}

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Keystore) | Out-Null
if (Test-Path $Keystore) { Remove-Item $Keystore -Force }

& $Keytool -genkeypair -v `
    -keystore $Keystore `
    -alias androiddebugkey `
    -storepass android -keypass android `
    -dname "CN=DSH Mobile Debug, O=DSH Android, C=CN" `
    -keyalg RSA -keysize 2048 -validity 10950 `
    -startdate "2020/01/01 00:00:00"
if ($LASTEXITCODE -ne 0) { throw "keytool 生成失败（exit $LASTEXITCODE）" }

Write-Host "`n已生成：$Keystore" -ForegroundColor Green
& $Keytool -list -v -keystore $Keystore -storepass android -alias androiddebugkey 2>&1 |
    Select-String -Pattern "生效时间|失效时间|SHA256" | ForEach-Object { Write-Host ("  " + $_.Line.Trim()) }

# keytool 把提示写到 stderr，PowerShell 会把它当错误记录 —— 这里明确表示成功
exit 0
