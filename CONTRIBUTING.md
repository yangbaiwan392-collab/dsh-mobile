# 贡献指南

感谢你有兴趣改进 **dsh-mobile**。这个项目的目标很窄：**把 DSH 的 Web GUI 在 Android 上用顺手**。
所有改动都应该服务这个目标 —— 想加终端模拟器、内置模型、后台服务之类的东西，先开 issue 讨论。

## 环境

| 需要 | 版本 / 说明 |
|---|---|
| Windows | 10/11（构建脚本是 PowerShell；Linux/macOS 可以用 `android/gradlew` 手动跑，见下） |
| JDK | 17（`tools/install-toolchain.ps1` 会装 Microsoft OpenJDK 17） |
| Android SDK | platform-tools + build-tools 34.0.0 + platforms;android-35 |
| Gradle | 8.11.1（工具链脚本自带） |
| bash（可选） | `tools/test-termux-scripts.sh` 需要 Git for Windows 自带的 bash |

一条命令准备齐（默认装到 `E:\Android`，可用 `$env:DSH_ANDROID_TOOLCHAIN` 改）：

```powershell
powershell -File tools\fetch-toolchain.ps1
powershell -File tools\install-toolchain.ps1
```

## 构建与测试

```powershell
powershell -File tools\build-apk.ps1 -Task testDebugUnitTest   # 只跑单测
powershell -File tools\build-apk.ps1                           # 出 debug APK → dist\
```

`build-apk.ps1` 会**依次**做三件事，任何一步失败都不会继续：

1. `tools/check-contracts.ps1` —— 跨工件契约（Termux 脚本 ↔ Android 工程 ↔ 文档）；
2. `tools/test-termux-scripts.sh` —— 用桩命令真跑手机脚本；
3. Gradle 构建，最后打印 APK 的 **SHA-256 与签名指纹**。

### 不用 PowerShell 的等价做法

```bash
# 手动构建（自己保证 JAVA_HOME / ANDROID_HOME 指向你装的工具链）
cd android
JAVA_HOME=/path/to/jdk17 ANDROID_HOME=/path/to/Sdk ./gradlew testDebugUnitTest assembleDebug
# 注意：仓库里没有 gradlew（Windows 脚本直接调用本地 Gradle）。需要的话先跑一次
# `gradle wrapper --gradle-version 8.11.1` 生成，再提交 wrapper 文件。
```

## 代码纪律（评审会照这个看）

1. **逻辑必须在 `core/` 的纯 Kotlin 里**，不依赖 Android —— 这样才能用 JVM 单测验证行为，不需要模拟器。
   UI（`ui/`）与适配器（`web/`、`platform/`）只做搬运，不含判断。
2. **一个文件一个职责，目标 < 150 行**；超了先拆分再写。
3. **单一事实源**：依赖版本只在 `android/gradle/libs.versions.toml`；工具链路径只在 `tools/toolchain-env.ps1`；
   模式 B 的命令/风险文案只在 `core/TunnelGuidance.kt`。
4. **不引入不需要的依赖**：目前只有 4 个 AndroidX + Material。加 DI 框架 / Retrofit / RxJava 这类改动需要先讨论。
5. **token、URL、密钥不进源码**：入口存 DataStore/文件，密钥用 `tools/make-debug-keystore.ps1` 生成（且被 gitignore）。
6. **新增用户可见行为时**：同步更新 `docs/` 与 `CHANGELOG.md`；跨工件的字符串（组件名、extra 键、脚本路径）
   请交给 `check-contracts.ps1` 而不是靠人眼。

## 提交信息

用 [Conventional Commits](https://www.conventionalcommits.org/) 风格，中文/英文均可：

```
fix(web): 401 后只在有 token 时自动重试一次
feat(ui): 入口列表支持拖拽排序
docs(termux): 补充 F-Droid 下载慢时的替代方案
test(core): 补 Endpoint 对 IPv6 字面量的用例
```

## Pull Request 检查单

- [ ] `tools/build-apk.ps1` 全绿（契约检查 / 脚本测试 / 单测 / 构建）
- [ ] 新行为有对应的 `core/` 单测，或说明为什么无法单测
- [ ] 涉及真机的改动，在 PR 描述里写清**机型 + Android 版本 + 实测结果**（本项目对"只在真机上才能发现"的问题有切肤之痛）
- [ ] 文档与 `CHANGELOG.md` 已更新
- [ ] 没有提交 `dist/`、`phone/`、`android/signing/debug.keystore`、`local.properties`、`tools/usb-driver/`

## 报告问题

- **功能异常 / 崩溃**：请附 app 内的崩溃日志（弹窗里的「复制日志」）或 `adb logcat -b crash -d` 的输出。
- **安全问题**：不要开公开 issue，见 [SECURITY.md](../SECURITY.md)。
