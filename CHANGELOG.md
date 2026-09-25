# 变更记录

本项目遵循 [语义化版本](https://semver.org/lang/zh-CN/)；`0.x` 期间接口与 UI 仍可能变动。
带 ★ 的条目是**真机踩出来的**问题 —— 记在这里是为了让下一个人少走一遍。

## [Unreleased]

### 新增
- **`AGENTS.md`：在这个仓库里干活的规矩**（写给 AI agent，人照着做同样省事）。
  三条硬规矩 —— **bug 先说清现象再改、改完交代"验证到哪一步"**（没真机验证的必须明说）；
  **新功能先讨论**，提方案时给 2–4 个选项与各自代价，由维护者拍板；**不加自动/常驻/定时行为**（先问）。
  另含开工顺序（先说不足 → 代码纪律 → 变更记录 → docs）、改完必做（契约 8 条 + 脚本测试 22 项 + 编码规矩）、
  红线（不打印 key/token、不动维护者正在用的 3080/Ollama/ComfyUI）与提交/发布约定。
  `CONTRIBUTING.md` 与 README 都加了指针；README 的「已知限制 / 路线图」也写明**每条都还没做、做之前先讨论**。

**已知待办（不影响使用，写在这里免得忘）**
- CI 里用的 actions 版本偏旧：`actions/checkout@v4` / `actions/setup-java@v4` / `actions/upload-artifact@v4` /
  `gradle/actions/setup-gradle@v4` / `android-actions/setup-android@v3` 已被 GitHub 标记 **Node 20 弃用**（当前仍能跑，只是每次多几条警告）。
  上游最新分别是 **v7 / v6 / v7 / v6 / v4** —— 升级要**逐个读各自的 breaking changes 再动**，别一次性盲升。
- 界面回归仍然靠人眼（没有模拟器/仪器测试）；`x86_64` 设备支持与更低的 `minSdk` 都未做，见 README「先说不足」。

## [0.1.8] — 2026-09-25

> 这一版的两大主题：**修掉"app 打不开"的真因**，以及**补齐工程件并首次开源**。

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
- **CI**（`.github/workflows/ci.yml`）：每次 push / PR 跑 契约检查 + Termux 脚本桩测试 + 单测 + 出包，
  并把 debug APK 作为构建产物上传。**只覆盖"不需要真机"的部分** —— 界面回归仍然靠人眼（见 README「先说不足」）。
- **Gradle Wrapper**（`gradle-wrapper.properties` 钉 8.11.1）：`tools/build-apk.ps1` 与 CI 都**优先用 wrapper**，
  于是别人 clone 后只要有 JDK 17 + Android SDK 就能构建，不必装特定版本 Gradle。
- **正式签名**：`tools/make-release-keystore.ps1`（默认**拒绝覆盖**已有密钥 —— 覆盖等于毁掉升级路径）
  + `RELEASING.md`（含"密钥丢了就再也无法给已装用户升级"这类不可逆代价）+ `build.gradle.kts` 的 release 分支：
  有 `android/keystore.properties` 就用正式密钥，没有则**退回 debug 签名并在构建日志里说明"不可分发"**（contributor 仍能跑 `assembleRelease`）。
- **issue 模板**：🐞「报告问题」/ 🔍「指出我写错了」（后者一句话 + 可选行号即可，正对 README 里那个邀请）
  + `config.yml`（安全类问题指向 `SECURITY.md`，不开公开 issue）。
- `termux/phone-bootstrap.sh`：**自包含引导**（贴进 Termux 即可跑，不需要 `/sdcard` 授权、不需要 MTP 传文件），
  它会自己写出 `~/dsh-android/start-dsh.sh`，因此 app 里的「启动 DSH」按钮随后仍可用。
- 手机本地 DSH 的端口有了**单一真源** `TermuxCommand.LOCAL_PORT`：启动脚本默认值、自检里的探活地址、
  app 侧"起来了没有"的探针三处共用，改一处即可。
- **`~/.bashrc` 钩子（由 start-dsh.sh 自动安装）**：打开 Termux 时若 3080 没在听，就后台跑一次 start-dsh.sh。
  这是给"系统拦别的应用启动 Termux"准备的**不受限入口** —— 用户自己点开 Termux 不属于"被别的应用拉起"。
  幂等（哨兵注释标记）、只在交互 shell 生效（不会与 RUN_COMMAND 的 `bash -c` 递归）。
- **WebView 连不上时给下一步**：主文档加载失败不再是 WebView 自带那屏 `net::ERR_CONNECTION_REFUSED`，
  而是弹「打不开这个入口」：本机入口给「打开 Termux」（点了会触发系统确认框，同意后钩子自动拉起 DSH）
  +「重试」；远程入口则指向 PC 侧排查（隧道/代理/地址变了）。判定与文案在纯逻辑 `core/TermuxStartReport`
  （有单测），只对**主文档**失败弹窗（子资源失败不打扰）。
- 从 Termux 切回本页会**自动重试一次**（只在确实失败过时），否则用户按提示去开完 Termux 回来，
  手里只剩一屏错误页而没有「重试」可点（真机走一遍才发现）。
- `tools/sync-bootstrap-embed.ps1`：把 `termux/start-dsh.sh` **逐字**灌进 `phone-bootstrap.sh` 的内嵌段，
  支持 `-Check` 只核对；`tools/check-contracts.ps1` 新增**契约 7** 调用它，漂了就红。

### 修复
- ★ **「启动手机上的 DSH」会谎报成功**（moto XT2611-1 / Android 16 实测）：摩托的 DeviceGuard 把
  `com.termux/.app.RunCommandService` 的启动请求**直接丢掉**（系统日志
  `filterSelfStart … Unable to start service … not found`、`stop com.termux due to AutoRun`），
  而 `Context.startService()` 对"被丢掉"和"成功"一视同仁 —— 既不抛异常也没有返回值，
  于是 app 弹出"已让 Termux 启动本地 DSH"，用户白等一场。
  → 判据改成**实测端口**：请求发出后轮询 `127.0.0.1:3080` 最多 90 秒（`platform/LocalDshProbe`，
  判定与文案在纯逻辑 `core/TermuxStartReport`，有单测 `TermuxStartReportTest`），探到才算成功；
  没探到就照实说明"请求发出去了但没人监听"，并给出两种解法。UI 同时新增**「打开 Termux」**按钮：
  系统限制拦的是"从停止状态被别的应用拉起"，用户手动开一次不受影响（开过一次后就顺了）。
- ★ **DSH 会随 Termux 被系统清理一起消失**：系统 `ApplicationExitInfo` 记录
  `reason=10 (USER REQUESTED) subreason=21 (FORCE STOP)`、
  `description=stop com.termux due to RemoveTaskMemoryClean` —— "清理后台 / 划掉最近任务"时
  Termux 作为**普通后台应用**被强停，node 子进程跟着死；表现是 app 打开本地入口报"无法连接"
  （**app 与脚本其实都没问题**，是本地服务没了）。
  → `termux/start-dsh.sh` 现在先 `termux-wake-lock`：Termux 转为**前台服务**（常驻一条通知），
  清后台不再能杀掉它。
- ★ **契约 7 在 CI 上假红**（本地全过、push 两次全红）：它是**另起一个 `powershell` 子进程**跑
  `sync-bootstrap-embed.ps1 -Check`，用 `$LASTEXITCODE` 判成败，而子进程的输出被 `$syncOut = … 2>&1`
  接走后**从不打印** —— 于是报告里只剩一句"内嵌的 start-dsh.sh 与真身不一致"，
  既说不出差在哪、也指错了方向（真身与内嵌副本其实一模一样）。
  → 改为**同进程**调用：判定逻辑仍只有一份，失败原因（含两边字符数）直接进报告；
  顺带新增**契约 8：仓库里的 `.ps1` 必须带 UTF-8 BOM**（PowerShell 5.1 读无 BOM 脚本用系统 ANSI 代码页，
  本机 ACP=utf-8 一直没露馅，换台机器中文就成乱码 —— 契约 8 上线当次就抓到了被编辑器去掉 BOM 的那个文件）；
  内嵌副本与真身的比对也**先归一 CRLF 再比**（契约要的是内容一致，不是字节一致）。
- ★ **CI 出不了包：干净克隆里没有调试签名密钥**（第一次 CI 跑到出包那步才暴露）：
  `android/signing/debug.keystore` 是密钥、**故意不进仓库**，而 `debug` 构建类型指定了它，
  于是 `validateSigningDebug` 红在 `Keystore file '…/debug.keystore' not found`。
  → CI 增加"生成调试签名密钥"步骤（`tools/make-debug-keystore.ps1`，幂等）；
  `CONTRIBUTING.md` 写明"直接跑 `gradlew`（或 IDE）前先跑一次这个脚本"；
  `tools/build-apk.ps1` 里补生成密钥的那句改成**同进程**调用（同契约 7 的理由：别再引入另一个 PowerShell 版本）。
  顺带两处让日志说人话：CI 给 Gradle **客户端** JVM 设 `-Dsun.stdout.encoding=UTF-8`
  （`org.gradle.jvmargs` 只管 daemon，runner 的控制台代码页把中文提示写成了 `???`）；
  `make-debug-keystore.ps1` 打印 keytool 信息时不再只匹配中文（英文 JDK 是 `Valid from`，只匹配中文等于什么都不打）。
- ★ **工具链脚本只会认作者机器上的 `E:\Android`**（CI 的第二个红：契约检查过了、单测过了，
  卡在"生成调试密钥"）：`tools/toolchain-env.ps1` 里写死 `E:\Android`，而 runner 上**没有 E: 盘**；
  更隐蔽的是 **pwsh 7 的 `Join-Path` 会校验盘符存在**（Windows PowerShell 5.1 不会），
  于是它直接崩在 `Cannot find drive. A drive with the name 'E' does not exist` —— 本机永远复现不了。
  → root 改成按优先级解析（`$env:DSH_ANDROID_TOOLCHAIN` → `E:\Android`（存在时）→
  `%LOCALAPPDATA%\dsh-android-toolchain`），JDK/SDK 在布局里没有时**直接用机器上已配好的**
  `JAVA_HOME` / `ANDROID_HOME`（CI runner 正是这种）；拼路径不再用 `Join-Path`；
  `tools/install-toolchain.ps1` 里两处写死的 `'E:\Android'` 改成 `$AndroidRoot`（否则换机器装不上）。
- `tools/test-termux-scripts.sh`：curl 预检那条不再写死 `apt full-upgrade`（实现是 `apt -y full-upgrade`，
  测试与实现不同步导致长期红），改为只断言"存在一条 apt 的 full-upgrade 指令"；现 **4 个用例 / 22 项全过**。
- ★ **自检报告会把入口地址的 token 原样打出来**：`[10] 日志里的入口地址` 直接 `grep` 了 `.dsh-web.log`，
  于是 `?token=…` 完整出现在报告里 —— 而这份报告天然是要被截图、被贴进 issue 的（作者本人就这么干过，
  把 token 截进了公开截图）。→ 现在只保留 `host:port`，token 一律替换成 `<已隐藏>`；
  替换用 `sed -E 's/(token=)[^ )]+/\1<已隐藏>/g'`，**`g` 是必须的**（日志行可能带 `(LAN: …)` 尾巴，里面还有同一个 token）；
  新增单测 `TermuxCommandTest.自检报告里的入口地址必须给 token 打码` 锁住这个行为
  （含"Kotlin 里写成 `\\1` 而不是 `\\\\1`"的反向断言 —— 后者会让 sed 打印字面量 `\1`，等于没打码）。
  同时把 README 里那张自检截图重做了打码。
- ★ **`phone-bootstrap.sh` 内嵌的 start-dsh.sh 与真身漂移**：两份各自手改，内嵌那份少了 `DSH_OLLAMA_KEY`、
  也没有唤醒锁，而文件头却写着"拿唤醒锁并启动"。现在内嵌段 = 真身的**逐字副本**，只能由
  `tools/sync-bootstrap-embed.ps1` 生成，并由契约 7 核对（自包含的需求仍在，所以不能删掉副本，但可以不让它漂）。
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

## [0.1.5] — 2026-09-23

**这一版解决的是"能打开界面但一开会话就失败"**：Android 上有两处**运行时**硬障碍，都不是配置问题。

### 新增
- `termux/fix-android-runtime.sh`：把下面两处修复做成**幂等、可复现**的一步，已接进一键流程
  （app 每次点「启动手机上的 DSH」都会跑一遍）。**真机自愈验证**：删掉修好的产物 → 装新 APK →
  点一次按钮 → 70 秒后原生模块自动重建、平台判定重新放行。

### 修复（真机实测，附症状原文）
- ★ **`flock is not supported on android-arm64`**：`@deepseek-ai/node-addon-system` 只认 linux/darwin，
  且**没有 android 预编译包**（官方预编译的 glibc/musl 版在 Bionic 上都装不上：`libc.so.6 not found` /
  `__errno_location` 缺失）。→ 但**随包发布了 C 源码**（`src/flock.c` 里就有 `NAPI_MODULE_INIT()`），
  于是在手机上用 node-gyp + clang **现编** `system.node`，装成
  `@deepseek-ai/node-addon-system-android-arm64`，并把平台判定放行 android。
  已验证语义正确：第一次加锁成功、第二个 fd 被 `EAGAIN` 拒绝。
- ★ **`EACCES: permission denied, link '…session.v3.jsonl.zstd.<hash>.c.tmp' -> '…'`**：
  **Android 应用数据目录禁止硬链接**（SELinux，实测 `ln` 直接 Permission denied），
  而 DSH 的会话持久化用 `fs.link()` 做原子落地 → 每个会话都建不起来。
  → 改成**同盘 `rename()`**（同样原子、且被允许；两处调用后面的 `rm(tmp)` 已有容错）。
  验证：会话日志 `session.v3.jsonl.zstd`（336 字节）正常落地，解开后能看到
  `{"type":"session",…}` / `permission/preset` / `sandbox/mode` / `approval/policy` 四行。

### 工具
- `tools/decode-session-log.mjs`：解开 DSH 的**多帧** zstd 会话日志（直接 `zstdDecompressSync`
  只解第一帧，会误以为"只有一条记录"）。
- `tools/tap-by-text.ps1`：优先精确匹配、dump 前清旧文件（`uiautomator dump` 失败时会拿到上一屏坐标）。
- `tools/pair-phone.ps1` / `tools/scan-adb-ports.mjs` / `tools/push-to-phone.ps1`：无线 adb 的配对、
  端口扫描与**无损**推送（PowerShell 管道会加 BOM，改用 base64 + `tail -c +4`）。

## [0.1.4] — 2026-09-22

### 新增
- **一键装/启（模式 A）**：手机侧脚本打包进 APK 的 assets（构建时从 `termux/` 同步），
  由 app 经 Termux 的 `RUN_COMMAND` 现场写进 `~/dsh-android/` 再执行。
  用户不再需要 MTP 拷文件、不再需要手敲命令 —— 真机验证脚本与仓库**逐字节一致**（sha256 比对）。
- **环境自检**：菜单项，逐环检查（脚本/allow-external-apps/node/dsh/node-pty 产物/wasm sharp/进程/端口/入口地址），
  结果回传到 app 内显示、可复制。
- **剪贴板通道**：见下方修复。
- 自动命名：本机 → 「手机本地」，远程 → 「远程 <主机>」（原先一律叫「手机本地」，两条入口同名）。
- 工具：`tools/tap-by-text.ps1`（按文字精确点击，优先精确匹配）、`tools/inspect-apk-layout.py`（APK 体积异常定位）。

### 修复
- ★ **Android 拦后台应用启动页面**：`ActivityTaskManager: Background activity launch blocked!
  [callingPackage: com.termux …]` —— Termux 在后台时脚本里的 `am start -e dsh_url/dsh_diag` 会被系统丢弃。
  → 入口地址与自检报告**同时写进剪贴板**（写入不受限、前台 app 可读），app 在 `onResume` 与点击后短轮询时收下；
  `am start` 保留作为"Termux 恰好在前台"时的快路径。判据在 `core/ClipboardIntake.kt`（认不出就什么都不做）。
- ★ **`Permission Denial: Accessing service com.termux/.app.RunCommandService … requires
  com.termux.permission.RUN_COMMAND`**：权限声明了但 `adb install` 不授予 → app 现在会**当场申请**并给出准确提示
  （原先的错误提示甩锅给 allow-external-apps）；`ManifestContractTest` 增加声明守卫。
- ★ **`cat > "~/dsh-android/x.sh"` 写不出文件**（真机表现为"目录建好了、文件是空的"）：
  **bash 不在双引号里展开 `~`** → 生成的命令改用 `$HOME`，并加回归测试（断言不出现 `"~/`）。
- 单测 **25 → 39** 项（新增命名、Termux 命令生成、剪贴板判据、权限声明守卫）。

## [0.1.3] — 2026-09-22

### 新增
- 工具栏菜单：把「启动手机上的 DSH」与「怎么连 PC？」从**空状态**里解放出来 ——
  真机测试时发现"一旦有了入口，空状态隐藏，这两个按钮就再也找不到了"。
- **真机截图入仓**（`docs/images/phone-*.png`，moto g54 / Android 15 实拍）。

### 已验证（模式 A 端到端，真机）
Termux 装好 DSH → `start-dsh.sh` 启动并打印 token URL → 脚本经 `am start -e dsh_url` 交给 app →
app 自动建档「手机本地」→ 点开在 WebView 里渲染出完整 DSH 界面。

### 修复
- ★ **`--expose-internals is required for HMR service`**：DSH 的 web profile 带 HMR 插件，
  要求 node 以此 flag 启动；且 `dsh` 的 shebang 是 `#!/usr/bin/env node`，而 **Android 没有 `/usr/bin/env`**
  （只有 termux-exec 在场时才被重写）→ 启动脚本改为 `node --expose-internals <dsh>/lib/bin.js`。
- ★ **`Could not load the "sharp" module using the android-arm64 runtime`**：sharp 无 android-arm64 预编译
  且需 libvips → 按官方指引安装 wasm 版 `@img/sharp-wasm32@0.35.4`（免编译），两个脚本都已内置并验证。
- 脚本内置 `LD_PRELOAD=libtermux-exec.so` 兜底，使脚本从 Termux 之外的调用方（adb / 服务上下文）也能跑。

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
