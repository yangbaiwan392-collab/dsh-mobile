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

一条命令准备齐（工具链位置按 `$env:DSH_ANDROID_TOOLCHAIN` → `E:\Android` →
`%LOCALAPPDATA%\dsh-android-toolchain` 的顺序找，见 `tools/toolchain-env.ps1`）：

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

仓库自带 **Gradle Wrapper**（`gradle-wrapper.properties` 钉死 8.11.1），只要有 JDK 17 + Android SDK：

```bash
cd android
JAVA_HOME=/path/to/jdk17 ANDROID_HOME=/path/to/Sdk ./gradlew testDebugUnitTest
JAVA_HOME=/path/to/jdk17 ANDROID_HOME=/path/to/Sdk ./gradlew assembleDebug
```

Windows / IDE 同理用 `android\gradlew.bat`；`tools/build-apk.ps1` 也会**优先用 wrapper**（与 CI 同一条路）。

> ⚠ **直接跑 `gradlew` 之前，先跑一次 `powershell -File tools\make-debug-keystore.ps1`**：
> 调试签名密钥（`android/signing/debug.keystore`）**不在仓库里**（它是密钥，被 gitignore），
> 而 `debug` 构建类型指定了它 —— 少了这一步，签名任务会红在
> `Keystore file '…/signing/debug.keystore' not found`。`build-apk.ps1` 会自动补这一步，
> 直接调 Gradle 的路径（CI、IDE、其它平台）则要自己跑一次（生成后一直复用，不必每次跑）。
> 单元测试不需要密钥，所以 `testDebugUnitTest` 在干净克隆里能直接跑通。
> 另外：**每台机器各自生成的这把密钥都不一样**（随机），所以"自己构建的 APK"与"发布页下载的 APK"
> 之间**不能互相覆盖升级**（签名不同，得先卸载）—— 自己构建的产物用于验证，发布版用于安装。

> 国内首次拉 distribution（约 130 MB，来自 `services.gradle.org`）可能很慢：
> 可临时把 `android/gradle/wrapper/gradle-wrapper.properties` 的 `distributionUrl` 换成镜像
> （如 `https://mirrors.cloud.tencent.com/gradle/gradle-8.11.1-bin.zip`）。这类镜像会变，先用浏览器确认能下。
> **别把换过镜像的 properties 提交上来** —— 官方地址对国际贡献者更稳。

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
7. **`.ps1` 文件必须存成「UTF-8 带 BOM」**（脚本里全是中文；PowerShell 5.1 读无 BOM 的脚本会用系统
   ANSI 代码页，在 ACP 不是 UTF-8 的机器上中文全变乱码）。有些编辑器/工具链会**悄悄把 BOM 去掉**，
   所以改完 `.ps1` 后跑一次 `tools/check-contracts.ps1` —— 契约 8 就是专门抓这个的。

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

### 欢迎直接挑错（作者主动邀请）

这个项目第一次开源，**作者最想要的不是 star，而是"你这里写错了"**：

- **一句话就够**：「`web/DshWebView.kt` 的 cookie 处理不对，应该用 CookieManager 的 X」——
  不必写成完整报告，也不必先复现。
- **最想要的五类意见**：① 安全 ② Android 平台正确性 ③ Termux 集成的正确姿势 ④ Kotlin 结构与命名 ⑤ 构建与测试。
  完整说明在 README 的「先说不足（作者自陈）」一节。
- **不必客气**：觉得某段像新手写的就直说。作者不会辩解 —— 只会改，或者把"为什么不得不这样"补进文档。
- **会被记名致谢**（写进 `CHANGELOG.md`，除非你说不要）。
- 提之前可以先扫一眼 README 里那张"已知不足"表，能省你时间；**表里没写的，才是作者最想知道的**。
