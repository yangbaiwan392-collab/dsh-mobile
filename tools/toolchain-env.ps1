# Android 工具链位置的**唯一事实源**（其它脚本都 dot-source 本文件）。
#
# 怎么找 root（从上往下第一个"成立"的赢）：
#   1) $env:DSH_ANDROID_TOOLCHAIN   显式指定（换机器首选这个，别去改脚本）
#   2) E:\Android                   作者机器上的历史默认（换机器别依赖它）
#   3) %LOCALAPPDATA%\dsh-android-toolchain   其它机器上的默认安装位置
#      （放仓库外、不需要管理员权限；tools/install-toolchain.ps1 会按下面的布局装到这里）
#
# JDK / SDK 另外看一眼"环境里已经配好的那份"：<root> 布局里有就用它；布局里没有、但
# $env:JAVA_HOME / $env:ANDROID_HOME 指向可用工具链，就用环境里那份 —— CI runner 正是这种
# （JAVA_HOME/ANDROID_HOME 由 setup-java / setup-android 设好，而整个 runner 上没有 E: 盘）。
#
# ★ 拼路径一律用字符串插值，**不要用 Join-Path**：pwsh 7 的 Join-Path 会校验盘符是否存在
#   （Windows PowerShell 5.1 不会），于是在没有 E: 盘的机器上它直接崩：
#   `Join-Path: Cannot find drive. A drive with the name 'E' does not exist.`
#   —— 本项目第一次跑 CI 就是死在这上面（本地有 E: 盘，永远看不出来）。
#
# 目录约定（tools/install-toolchain.ps1 按这个布局展开）：
#   <root>\jdk17                     Microsoft OpenJDK 17
#   <root>\Sdk\platform-tools        adb
#   <root>\Sdk\build-tools\34.0.0    aapt2 / apksigner
#   <root>\Sdk\platforms\android-35  compileSdk 35
#   <root>\Sdk\cmdline-tools\latest  sdkmanager
#   <root>\gradle-8.11.1             Gradle
#   <root>\_dl                       下载缓存（zip）

$RepoRoot    = Split-Path -Parent $PSScriptRoot
$AndroidRoot = if ($env:DSH_ANDROID_TOOLCHAIN) { $env:DSH_ANDROID_TOOLCHAIN }
               elseif (Test-Path -LiteralPath 'E:\Android') { 'E:\Android' }
               elseif ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'dsh-android-toolchain' }
               else { Join-Path $RepoRoot '.toolchain' }
$AndroidRoot = $AndroidRoot.TrimEnd('\', '/')

$Jdk = if (Test-Path -LiteralPath "$AndroidRoot\jdk17") { "$AndroidRoot\jdk17" }
       elseif ($env:JAVA_HOME) { $env:JAVA_HOME.TrimEnd('\', '/') }
       else { "$AndroidRoot\jdk17" }

$Sdk = if (Test-Path -LiteralPath "$AndroidRoot\Sdk") { "$AndroidRoot\Sdk" }
       elseif ($env:ANDROID_HOME) { $env:ANDROID_HOME.TrimEnd('\', '/') }
       elseif ($env:ANDROID_SDK_ROOT) { $env:ANDROID_SDK_ROOT.TrimEnd('\', '/') }
       else { "$AndroidRoot\Sdk" }

$GradleHome    = "$AndroidRoot\gradle-8.11.1"
$Gradle        = "$GradleHome\bin\gradle.bat"
$Downloads     = "$AndroidRoot\_dl"
$BuildTools    = "$Sdk\build-tools\34.0.0"
$PlatformTools = "$Sdk\platform-tools"
