# 跨文件契约检查：把"只有真机才能发现"的跨工件不一致，提前变成一条能跑的红/绿。
#
# 来历：termux/start-dsh.sh 里 `am start -n app.dsh.mobile/.MainActivity` 写错了组件名
# （真实类在 app.dsh.mobile.ui.MainActivity），而它后面带 `|| true`，所以在手机上会**静默失败**——
# 脚本说"已递给 app"，app 却什么都没收到。这类错误编译器和单测都看不到，只能靠契约检查。
#
# 用法：powershell -NoProfile -ExecutionPolicy Bypass -File tools\check-contracts.ps1
# 退出码：0 = 全部一致；1 = 有不一致（打印具体哪一条）
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$fail = New-Object System.Collections.Generic.List[string]

function Read-Text($relative) { Get-Content (Join-Path $root $relative) -Raw }

# ---- 事实来源：namespace / applicationId / MainActivity / extra 键 ----
$appGradle  = Read-Text 'android/app/build.gradle.kts'
$manifest   = Read-Text 'android/app/src/main/AndroidManifest.xml'
$navKt      = Read-Text 'android/app/src/main/java/app/dsh/mobile/ui/Nav.kt'
$termuxBridge = Read-Text 'android/app/src/main/java/app/dsh/mobile/platform/TermuxBridge.kt'
$startSh    = Read-Text 'termux/start-dsh.sh'
$doc01      = Read-Text 'docs/01-termux-local.md'

$namespace   = [regex]::Match($appGradle, 'namespace\s*=\s*"([^"]+)"').Groups[1].Value
$mainActivity = [regex]::Match($manifest, 'android:name="(\.ui\.MainActivity)"').Groups[1].Value
$extraKey    = [regex]::Match($navKt, 'EXTRA_DSH_URL\s*=\s*"([^"]+)"').Groups[1].Value
$scriptDir   = [regex]::Match($termuxBridge, 'TERMUX_SCRIPT_DIR\s*=\s*"([^"]+)"').Groups[1].Value
$scriptPath  = [regex]::Match($termuxBridge, 'DEFAULT_SCRIPT_PATH\s*=\s*"([^"]+)"').Groups[1].Value

if (-not $namespace)    { $fail.Add('build.gradle.kts 里读不到 namespace') }
if (-not $mainActivity) { $fail.Add('AndroidManifest.xml 里读不到 .ui.MainActivity') }
if (-not $extraKey)     { $fail.Add('Nav.kt 里读不到 EXTRA_DSH_URL') }

# 期望的组件名：<applicationId>/<相对类名> -> app.dsh.mobile/.ui.MainActivity
$expectedComponent = "$namespace/$mainActivity"

# ---- 契约 1：termux 脚本递给 app 的组件名必须与清单一致 ----
$actualComponent = [regex]::Match($startSh, "APP_COMPONENT='([^']+)'").Groups[1].Value
if (-not $actualComponent) {
    $fail.Add("termux/start-dsh.sh 里找不到 APP_COMPONENT='...'")
} elseif ($actualComponent -ne $expectedComponent) {
    $fail.Add("组件名不一致：脚本=$actualComponent 期望=$expectedComponent")
}

# ---- 契约 2：脚本用的 extra 键必须与 app 读的键一致 ----
$scriptExtra = [regex]::Match($startSh, '-e\s+(\w+)\s+"\$URL"').Groups[1].Value
if (-not $scriptExtra) {
    $fail.Add('termux/start-dsh.sh 里找不到 `-e <key> "$URL"`')
} elseif ($scriptExtra -ne $extraKey) {
    $fail.Add("extra 键不一致：脚本=$scriptExtra app=$extraKey")
}

# ---- 契约 3：文档写的脚本路径必须与 app 里调用的一致 ----
# TermuxBridge 里的路径是**两层 Kotlin 字符串插值**：
#   TERMUX_SCRIPT_DIR  = "$TERMUX_HOME/dsh-android"
#   DEFAULT_SCRIPT_PATH = "$TERMUX_SCRIPT_DIR/start-dsh.sh"
# 直接拿字面量比会永远失败 —— 所以按依赖顺序逐层展开，再把家目录还原成 `~` 形式。
$termuxHome = [regex]::Match($termuxBridge, 'TERMUX_HOME\s*=\s*"([^"]+)"').Groups[1].Value
$resolvedScriptDir = $scriptDir
if ($termuxHome -and $scriptDir -like "`$TERMUX_HOME*") {
    $resolvedScriptDir = $scriptDir -replace '^\$TERMUX_HOME', $termuxHome
}
$resolvedScriptPath = $scriptPath
if ($resolvedScriptDir -and $scriptPath -like "`$TERMUX_SCRIPT_DIR*") {
    $resolvedScriptPath = $scriptPath -replace '^\$TERMUX_SCRIPT_DIR', $resolvedScriptDir
}
$docForm = $resolvedScriptPath -replace '^/data/data/com\.termux/files/home', '~'
if ($docForm -and $doc01 -notmatch [regex]::Escape($docForm)) {
    $fail.Add("docs/01-termux-local.md 里没提到 app 实际调用的脚本路径：$docForm")
}

# ---- 契约 4：APK 里要带的脚本清单 ↔ 仓库 termux 目录里真实存在的文件 ----
# app 现在会把这些脚本**从 APK assets 现场写进 Termux**，所以"名单里有、文件不存在"
# 会变成用户手机上的一次失败安装 —— 必须在构建前就拦住。
$termuxCmd = Read-Text 'android/app/src/main/java/app/dsh/mobile/core/TermuxCommand.kt'
$scriptFilesBlock = [regex]::Match($termuxBridge, 'SCRIPT_FILES\s*=\s*listOf\(([^)]*)\)').Groups[1].Value
$declared = [regex]::Matches($scriptFilesBlock, '"([^"]+)"') | ForEach-Object { $_.Groups[1].Value }
if ($declared.Count -eq 0) { $fail.Add('TermuxBridge.SCRIPT_FILES 里读不到脚本名单') }
foreach ($name in $declared) {
    if (-not (Test-Path (Join-Path $root "termux/$name"))) {
        $fail.Add("TermuxBridge 声明要带进 APK 的脚本不存在：termux/$name")
    }
}

# ---- 契约 5：脚本目录常量两处必须一致（否则 app 写进去、脚本找不到）----
$coreScriptDir = [regex]::Match($termuxCmd, 'SCRIPT_DIR\s*=\s*"([^"]+)"').Groups[1].Value
if (-not $coreScriptDir) { $fail.Add('TermuxCommand.kt 里读不到 SCRIPT_DIR') }
elseif ($coreScriptDir -ne '\$HOME/dsh-android') {
    # 用 $HOME 而不是 ~：bash 不在双引号里展开 ~（生成的重定向带引号），真机踩过"目录空"的坑
    $fail.Add("TermuxCommand.SCRIPT_DIR=$coreScriptDir，期望 `$HOME/dsh-android")
}
if ($docForm -and -not $docForm.StartsWith('~/dsh-android')) {
    $fail.Add("app 调用的脚本路径 $docForm 不在 ~/dsh-android 之下")
}

# ---- 契约 6：自检回传的 extra 键 ↔ app 读的那个键 ----
$diagExtra = [regex]::Match($navKt, 'EXTRA_DIAG\s*=\s*"([^"]+)"').Groups[1].Value
if (-not $diagExtra) { $fail.Add('Nav.kt 里读不到 EXTRA_DIAG') }
elseif ($termuxCmd -notmatch "-e\s+$([regex]::Escape($diagExtra))") {
    $fail.Add("自检脚本没按 $diagExtra 回传报告（app 读的就是这个键）")
}

# ---- 输出 ----
Write-Host "契约检查（跨 Android 工程 / Termux 脚本 / 文档）" -ForegroundColor Cyan
Write-Host ("  namespace        = {0}" -f $namespace)
Write-Host ("  MainActivity     = {0}" -f $mainActivity)
Write-Host ("  期望组件名        = {0}" -f $expectedComponent)
Write-Host ("  脚本组件名        = {0}" -f $actualComponent)
Write-Host ("  extra 键          = app:{0}  script:{1}" -f $extraKey, $scriptExtra)
Write-Host ("  脚本默认路径      = {0}  →  {1}" -f $scriptPath, $resolvedScriptPath)
Write-Host ("  带进 APK 的脚本   = {0}" -f ($declared -join ', '))
Write-Host ("  自检回传键        = {0}" -f $diagExtra)

if ($fail.Count -gt 0) {
    Write-Host "`n不一致：" -ForegroundColor Red
    $fail | ForEach-Object { Write-Host ("  ✗ {0}" -f $_) -ForegroundColor Red }
    throw "$($fail.Count) 条契约不一致"
}
Write-Host "`n全部一致 ✓" -ForegroundColor Green
