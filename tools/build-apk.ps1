# 构建 APK 的唯一入口（本机工具链固定在 E:，不在 PATH 里，所以必须经这个脚本）。
#
# 用法：
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\build-apk.ps1              # 等价于 assembleDebug
#   powershell ... -File tools\build-apk.ps1 -Task testDebugUnitTest                     # 只跑单测
#   powershell ... -File tools\build-apk.ps1 -Task assembleRelease                       # 需要签名配置
[CmdletBinding()]
param(
    [string]$Task = 'assembleDebug',
    [switch]$Clean
)

$ErrorActionPreference = 'Stop'

# 先跑跨工件契约检查（Termux 脚本的组件名/extra 键/文档路径 与 app 是否一致）——
# 这类不一致编译器和单测都看不到，但会在手机上静默失败。
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'check-contracts.ps1')
if ($LASTEXITCODE -ne 0) { throw '跨工件契约检查未通过，先修好再构建' }

# Termux 脚本的行为验证（用桩命令真跑；需要 Git for Windows 自带的 bash）。
# 本机没有 Termux 也没有已注册的 WSL 发行版，所以这是"手机之前"唯一能真跑它的地方。
$gitBash = 'C:\Program Files\Git\bin\bash.exe'
if (Test-Path $gitBash) {
    & $gitBash (Join-Path $PSScriptRoot 'test-termux-scripts.sh')
    if ($LASTEXITCODE -ne 0) { throw 'Termux 脚本测试未通过，先修好再构建' }
} else {
    Write-Host '[warn] 找不到 Git 自带 bash，跳过 Termux 脚本测试' -ForegroundColor Yellow
}

. "$PSScriptRoot\toolchain-env.ps1"     # 工具链位置只在 toolchain-env.ps1 里定义
$ProjectDir  = Join-Path (Split-Path -Parent $PSScriptRoot) 'android'

foreach ($p in @($Jdk, $Sdk, $Gradle, $ProjectDir)) {
    if (-not (Test-Path $p)) { throw "缺东西：$p（先跑 tools\fetch-toolchain.ps1 和 tools\install-toolchain.ps1）" }
}

# 签名密钥固定进工程；缺失就生成（幂等）
$keystore = Join-Path $ProjectDir 'signing\debug.keystore'
if (-not (Test-Path $keystore)) {
    Write-Host "==> 缺少调试密钥，先生成" -ForegroundColor Yellow
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'make-debug-keystore.ps1')
    if (-not (Test-Path $keystore)) { throw "密钥生成失败：$keystore" }
}

$env:JAVA_HOME = $Jdk
$env:ANDROID_HOME = $Sdk
$env:ANDROID_SDK_ROOT = $Sdk

$tasks = if ($Clean) { @('clean', $Task) } else { @($Task) }
$gradleArgs = @('-p', $ProjectDir, '--no-daemon', '--console=plain') + $tasks
Write-Host ("==> gradle {0}（JAVA_HOME={1}）" -f ($tasks -join ' '), $Jdk) -ForegroundColor Cyan
Write-Host ("    完整参数：{0}" -f ($gradleArgs -join ' ')) -ForegroundColor DarkGray

& $Gradle @gradleArgs
if ($LASTEXITCODE -ne 0) { throw "gradle 失败（exit $LASTEXITCODE）" }

# 出 APK 的任务顺手报产物路径与大小，并复制一份到 dist/（build/ 会被 clean 清掉，dist/ 不会）
if ($Task -like 'assemble*' -and -not $Clean) {
    $apks = Get-ChildItem "$ProjectDir\app\build\outputs\apk" -Recurse -Filter *.apk -ErrorAction SilentlyContinue
    if ($apks) {
        $dist = Join-Path (Split-Path -Parent $PSScriptRoot) 'dist'
        New-Item -ItemType Directory -Force -Path $dist | Out-Null
        $version = (Select-String -Path "$ProjectDir\app\build.gradle.kts" -Pattern 'versionName\s*=\s*"([^"]+)"').Matches.Groups[1].Value
        Write-Host "`n==> 产物：" -ForegroundColor Green
        foreach ($apk in $apks) {
            $kind = if ($apk.Name -match 'release') { 'release' } else { 'debug' }
            $target = Join-Path $dist ("dsh-mobile-$version-$kind.apk")
            Copy-Item $apk.FullName $target -Force
            # 先把大小算进变量再用 -f：把表达式直接塞进 -f 的参数列表会被 PowerShell 解析歪
            $sizeMb = [math]::Round((Get-Item $target).Length / 1MB, 2)
            $sha = (Get-FileHash $target -Algorithm SHA256).Hash
            Write-Host ("    {0}  ({1} MB)" -f $target, $sizeMb)
            Write-Host ("      SHA-256 : {0}" -f $sha)
            # 打印签名身份：以后"签名错误"这类问题能立刻对账，不用猜
            $certs = & "$Sdk\build-tools\34.0.0\apksigner.bat" verify --print-certs $target 2>&1 |
                Select-String -Pattern 'certificate SHA-256 digest' | Select-Object -First 1
            if ($certs) { Write-Host ("      签名证书 : {0}" -f ($certs.Line -replace '^.*digest:\s*', '')) }
        }
    }
}
