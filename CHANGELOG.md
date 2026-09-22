# 变更记录

本项目遵循 [语义化版本](https://semver.org/lang/zh-CN/)；`0.x` 期间接口与 UI 仍可能变动。
带 ★ 的条目是**真机踩出来的**问题 —— 记在这里是为了让下一个人少走一遍。

## [Unreleased]

### 已验证（真机里程碑）
- **Android/Termux 上 DSH 的原生依赖可以编出来**：`node-pty` 无 `android-arm64` 预编译，
  在 moto g54（Android 13 / aarch64）上用 `pkg install -y python clang make` +
  `npm rebuild node-pty @deepseek-ai/dsh-subprocess-local --foreground-scripts` **编译成功**
  （`gyp info ok`，产物 `build/Release/pty.node` **65032 字节**）；
  `@deepseek-ai/dsh-subprocess-local` 的 `ensure-spawn-helper` postinstall 也正常执行。
- ★ 期间发现 **npm 11.19+ 的安装脚本审批闸门**：未批准的包其 install/postinstall **不执行**，
  且 npm 的 `up to date` 快路径**不会补跑**已装包的脚本 —— 所以必须"检查产物"而不是"相信 exit code"。
  现在两个脚本都显式检查 `pty.node` 并在缺失时 rebuild。

### 新增
- `termux/phone-bootstrap.sh`：**自包含引导**（贴进 Termux 即可跑，不需要 `/sdcard` 授权、不需要 MTP 传文件），
  它会自己写出 `~/dsh-android/start-dsh.sh`，因此 app 里的「启动 DSH」按钮随后仍可用。

### 修复
- ★ **`node-pty` 在手机上编译失败导致 DSH 装不上**：node-pty 只提供 `darwin/linux/win32` 预编译，
  **没有 `android-arm64`**，于是退回 node-gyp 本地编译；而 Termux 默认没有 Python/编译器，
  报 `gyp ERR! find Python ... Could not find any Python installation to use`。
  又因为 `dsh-subprocess-local` 在**模块顶层**就 `import * as nodePty from "node-pty"`（饿加载），
  **跳过编译（`--ignore-scripts`）会让插件树起不来**，不能走这条路。
  → 两个脚本现在会在装 DSH 前主动 `pkg install -y python clang make`。
- ★ **`npm i -g @deepseek-ai/dsh` 必定 ETARGET**（上游发布坏了）：`dsh-client-ui-sidebar` 有乱序发布的
  `0.1.5-rc.3`，配套的 `dsh-client-ui-sidebar-documentpreview` 无 rc.3，而 `^0.1.5-rc.3` 按 semver 只匹配
  0.1.5 系列 → 无解。改为装进 `~/dsh-install` 项目并用 `overrides` 钉住已知可用的 `0.1.5-rc.2` 组合，
  再 `npm link` 暴露命令；本机实测该组合 584 个包解析通过。新增 `tools/probe-dsh-versions.ps1` 可复现探测。
- ★ **Termux "升级了一半"导致 curl 崩溃**：`pkg install` 升级了 `curl`/`libcurl` 但 `openssl` 未同步
  （apt 提示 `N not upgraded`）→ `CANNOT LINK EXECUTABLE "curl": cannot locate symbol "SSL_set_quic_tls_early_data_enabled"`，
  连锁使镜像自检与 `nodejs` 安装全部失败。两个脚本现在都有**预检**：检测到 curl 不可用就停下并打印
  `apt update && apt full-upgrade -y`，不再继续。
- `tools/test-termux-scripts.sh` 扩到 **4 个用例 / 19 项**：新增"自包含引导"与"curl 崩溃预检"回归；
  并修正 curl 桩必须支持 `--version`（预检会调用它）。

## [0.1.2] — 2026-09-22

### 修复
- ★ **安装报「签名错误」**：AGP 自动生成的调试证书**生效时间 = 构建那一刻**，
  手机时钟稍早即被判"证书尚未生效"。改用**工程自带**的调试密钥
  （`tools/make-debug-keystore.ps1`，生效时间 2020-01-01 起、有效期 30 年），
  并在 `app/build.gradle.kts` 里显式绑定。
- ★ **Termux 脚本回传组件名写错**：`am start -n app.dsh.mobile/.MainActivity` 少写 `.ui`，
  且后面带 `|| true` → 在手机上"看起来正常、app 收不到地址"。改为 `.ui.MainActivity`，
  并新增 `tools/check-contracts.ps1` 把这类跨工件漂移变成可执行断言。

### 新增
- **应用图标**：原创朱红小鲸鱼 + 墨印圈（**不是** DeepSeek 商标的复刻）；
  `tools/icon-preview.py` 做自适应图标**安全区自检**（首版尾鳍被圆形遮罩切掉、一颗水花 r=29.8 超界，都是它抓的）。
- **崩溃可查**：`platform/CrashLog.kt` 全局落盘，下次打开弹窗显示 + 一键复制。
- **构建可信度**：`tools/build-apk.ps1` 每次出包打印 **APK SHA-256 + 签名证书指纹**；
  并把契约检查与脚本测试前置为构建闸门。
- `tools/toolchain-env.ps1`：工具链位置的唯一事实源（可用 `$env:DSH_ANDROID_TOOLCHAIN` 覆盖），
  `gradle.properties` 不再写死 `org.gradle.java.home`。
- 开源骨架：`LICENSE`(MIT) / `.gitignore` / `CONTRIBUTING.md` / `SECURITY.md` / 本文件 / `docs/` 索引。

### 变更
- **模式 B 的实测结论**：`--host 0.0.0.0` 被服务端拒绝、`--host <LAN IP>` 配置校验失败
  → 手机无法直连，必须有转发者；代理链路已端到端实测。

## [0.1.1] — 2026-09-22

### 修复
- ★ **打开即闪退**：清单 `<application>` 漏写 `android:name=".DshApp"`，
  导致每个 Activity 里的 `(application as DshApp)` 抛
  `ClassCastException: android.app.Application cannot be cast to app.dsh.mobile.DshApp`。
  编译器 / lint / 单测全绿，**只有真机能暴露**。
- 新增 `ManifestContractTest`（4 项）：Application 必须挂上、每个 `.XxxActivity` 必须能找到源码类、
  `namespace` 必须等于 `applicationId`、三个 Activity 必须在清单里。
  并修掉"改了清单 Gradle 会跳过单测"导致的**守卫静默失效**（`inputs.file(...)`）。

## [0.1.0] — 2026-09-22

### 新增
- 首个可用版本：入口列表 / 添加与编辑（粘贴整行自动识别）/ 全屏 WebView（cookie、外链、上传、下载、重认证）/
  Termux 联动（RUN_COMMAND + `am start` 回传）。
- `core/` 纯逻辑：`Endpoint`、`TokenExchange`、`Profile`、`ProfileStore`（文件 + 内存两个适配器）、`TunnelGuidance`。
- `termux/`：`setup-dsh.sh`、`start-dsh.sh`、`tunnel-to-pc.sh`。
- `tools/`：工具链下载/安装、构建入口、模式 B 代理与端到端验证、Termux 脚本桩测试。
- `docs/`：模式 A / 模式 B / 构建与排障三份说明书。
- 构建链：全程国内镜像（腾讯 AndroidSDK、腾讯 Gradle、aka.ms JDK），实测 5–8 MB/s。
