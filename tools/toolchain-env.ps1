# Android 工具链位置的**唯一事实源**（其它脚本都 dot-source 本文件）。
#
# 换机器：设一个环境变量即可，别去改各个脚本：
#   $env:DSH_ANDROID_TOOLCHAIN = 'D:\Android'
# 默认 E:\Android（本项目作者机器上的位置）。
#
# 目录约定（tools/install-toolchain.ps1 会按这个布局展开）：
#   <root>\jdk17                     Microsoft OpenJDK 17
#   <root>\Sdk\platform-tools        adb
#   <root>\Sdk\build-tools\34.0.0    aapt2 / apksigner
#   <root>\Sdk\platforms\android-35  compileSdk 35
#   <root>\Sdk\cmdline-tools\latest  sdkmanager
#   <root>\gradle-8.11.1             Gradle
#   <root>\_dl                       下载缓存（zip）

$AndroidRoot = if ($env:DSH_ANDROID_TOOLCHAIN) { $env:DSH_ANDROID_TOOLCHAIN } else { 'E:\Android' }
$Jdk         = Join-Path $AndroidRoot 'jdk17'
$Sdk         = Join-Path $AndroidRoot 'Sdk'
$GradleHome  = Join-Path $AndroidRoot 'gradle-8.11.1'
$Gradle      = Join-Path $GradleHome 'bin\gradle.bat'
$Downloads   = Join-Path $AndroidRoot '_dl'
$BuildTools  = Join-Path $Sdk 'build-tools\34.0.0'
$PlatformTools = Join-Path $Sdk 'platform-tools'
