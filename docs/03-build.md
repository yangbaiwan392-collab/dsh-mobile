# 构建与安装

## 一、构建（本机，一条命令）

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\build-apk.ps1
# 只跑单测：
powershell ... -File tools\build-apk.ps1 -Task testDebugUnitTest
# 清一遍再出包：
powershell ... -File tools\build-apk.ps1 -Clean
```

产物会复制到 **`dist\dsh-mobile-<版本>-debug.apk`**（`build\` 会被 clean 清掉，`dist\` 不会）。

## 二、工具链（已在本机装好；换机器照这两步）

```powershell
powershell -File tools\fetch-toolchain.ps1     # 从腾讯/aka.ms 镜像下载（~578 MB，5–8 MB/s）
powershell -File tools\install-toolchain.ps1   # 展开 + 逐项验证（幂等）
```

路径的**单一事实源**（换机器只改这两处）：

| 事实 | 文件 |
|---|---|
| SDK 位置 | `android\local.properties` 的 `sdk.dir` |
| JDK 位置 | `android\gradle.properties` 的 `org.gradle.java.home` |
| 依赖仓库 | `android\settings.gradle.kts`（阿里云镜像优先，官方兜底） |
| 依赖版本 | `android\gradle\libs.versions.toml` |

## 三、装到手机

```powershell
# 手机开「开发者选项 → USB 调试」，插上后：
E:\Android\Sdk\platform-tools\adb.exe install -r <仓库目录>\dist\dsh-mobile-0.1.2-debug.apk
# 或者：把 dist 里的 apk 传到手机（微信/网盘/U 盘都行），在手机上点它安装
#   （debug 签名，需要允许「安装未知来源应用」）
# ⚠ 只有 0.1.2 这一次需要先卸载：因为签名密钥从 AGP 默认那把换成了工程自带那把。
#   之后升级都可以 -r 原地覆盖。
E:\Android\Sdk\platform-tools\adb.exe uninstall app.dsh.mobile     # 仅本次需要
```

## 四、装完该看到什么（自验清单）

| 步骤 | 期望 |
|---|---|
| 打开 app | 标题「DSH 手机端」，空状态写着两种用法 |
| 点「怎么连 PC？」 | 弹出 SSH 隧道命令 + 代理命令 + 四条风险说明 |
| 点右下 + → 粘贴入口地址 | 一边输一边校验；粘贴 `dsh web: http://…?token=… (LAN: …)` 整行也能识别 |
| 点「保存」后回到列表 | 卡片显示 `<host:port> · 已存 token` |
| 点卡片 | 进全屏 WebView 并加载 DSH 界面（token 会被自动交换掉） |
| 长按卡片 | 编辑 / 删除 |
| 右上角菜单（在 WebView 页） | 「重新认证（清 cookie 再交换 token）」「复制入口地址」 |
| 在 Termux 里跑 `start-dsh.sh` | Termux 输出 `APP_URL=…`，并自动把这个地址递给 app |

## 六、排查真机事故（两个真实案例）

### 案例 1：一开就闪退（v0.1.0）

### 那一版为什么一开就闪退

清单的 `<application>` 漏了 `android:name=".DshApp"` → 运行时用的是系统默认 `Application`，
而三个 Activity 里都有 `(application as DshApp)`，于是启动瞬间抛：

```
java.lang.ClassCastException: android.app.Application cannot be cast to app.dsh.mobile.DshApp
    at app.dsh.mobile.ui.MainActivity.onCreate(MainActivity.kt:…)
```

**为什么构建、lint、单测全绿却没抓到**：它们都不看"清单里挂的是哪个 Application"。
这是一类**只有真机能暴露**的静态错误 —— 已经补了守卫，见下面。

### 现在怎么看日志（三种，按方便程度排）

**① app 自己显示（v0.1.1 起，不用电脑）**
崩溃后重新打开 app，会弹「上次启动崩溃了」的对话框，里面有完整堆栈，按钮：
- **复制日志** → 粘给我即可（微信/任意地方）
- **清除** → 不再弹

**② adb（USB，最详细）**
```powershell
E:\Android\Sdk\platform-tools\adb.exe devices                  # 手机需先开「USB 调试」
E:\Android\Sdk\platform-tools\adb.exe logcat -c                # 清空旧日志
# 然后在手机上点开 app；崩了之后：
E:\Android\Sdk\platform-tools\adb.exe logcat -b crash -d       # 只看崩溃缓冲
E:\Android\Sdk\platform-tools\adb.exe logcat AndroidRuntime:E *:S   # 只看异常栈
```

**③ adb 无线调试（Android 11+，不用数据线）**
设置 → 开发者选项 → **无线调试** → 使用配对码配对设备（记下 IP、配对端口、配对码）：
```powershell
E:\Android\Sdk\platform-tools\adb.exe pair 192.168.x.x:配对端口     # 输入配对码
E:\Android\Sdk\platform-tools\adb.exe connect 192.168.x.x:连接端口  # 端口与配对端口不同
E:\Android\Sdk\platform-tools\adb.exe logcat -b crash -d
```

> 注意：v0.1.0 那次崩溃**手机上没有任何日志可查** —— 因为崩溃发生在自定义 Application 生效之前，
> 落盘机制还没来得及装上。`adb logcat` 能看到，但前提是当时连着线。

### 防复发：清单契约测试

`app/src/test/java/app/dsh/mobile/ManifestContractTest.kt` 会在单测里检查：

1. `<application>` 必须写 `android:name=".DshApp"`；
2. 每个 `android:name=".X"` 都能在源码里找到对应类（顺手治住 Activity 类名打错）；
3. `namespace` 与 `applicationId` 一致（否则相对类名解析到别的包）；
4. 三个 Activity 都在清单里。

并且 `app/build.gradle.kts` 里把清单与构建脚本**声明成 test task 的输入**：

```kotlin
tasks.withType<Test>().configureEach {
    inputs.file("src/main/AndroidManifest.xml").withPathSensitivity(PathSensitivity.RELATIVE)
    inputs.file("build.gradle.kts").withPathSensitivity(PathSensitivity.RELATIVE)
}
```

不加这两行，改完清单 Gradle 会认为测试 up-to-date 而跳过 —— 守卫会**静默失效**（实测：改坏清单仍然 BUILD SUCCESSFUL）。
加完之后实测：清单坏 → `ManifestContractTest > application node names our Application class FAILED`；恢复 → 全绿。

### 案例 2：安装报「签名错误」（v0.1.1 → v0.1.2）

**现象**：手机上装 v0.1.1 时直接报签名错误，连装都装不上。

**排查过程（都是实测数据，不是猜）**：

1. 先怀疑"两次构建换密钥" → 对两个 APK 打印证书指纹：**完全相同**
   （都是 `6a93d37957d8741680b8c756d7d3c182cf1cf80fe50ea7eced1e9ddb38ccb49e`）→ 排除。
2. 再查签名方案：`apksigner verify --verbose` → **v2 scheme: true**（minSdk 33 只需 v2）→ 排除。
3. 查密钥本身 → **真凶**：
   ```
   创建日期: 2026年9月22日
   生效时间: Tue Sep 22 16:06:57 CST 2026, 失效时间: Thu Sep 14 16:06:57 CST 2056
   ```
   AGP 自动生成的调试证书，**生效时间 = 构建那一刻**。只要手机时钟比它早
   （差几分钟、或时区偏移），系统就认为"证书尚未生效" → 报**签名错误**。
   而且这把密钥在 `~/.android/debug.keystore`（仓库之外），被重建一次，
   以后**每次升级都会签名不一致**。

**修法（治根，不是"重装试试"）**：

- 用 `tools/make-debug-keystore.ps1` 生成**工程自带**的调试密钥：
  **生效时间 2020-01-01、有效期 30 年**（时钟偏差不可能咬到），随仓库走、换机器也一致。
- `app/build.gradle.kts` 里显式绑定：
  ```kotlin
  signingConfigs { getByName("debug") { storeFile = rootProject.file("signing/debug.keystore") /* … */ } }
  buildTypes { debug { signingConfig = signingConfigs.getByName("debug") } }
  ```
- `tools/build-apk.ps1` 每次出包都打印 **APK 的 SHA-256 + 签名证书指纹** —— 以后这类问题直接对账，不用猜。

**这次换密钥的代价**：手机上已装的那份用的是旧密钥，所以**必须先卸载再装**：
```powershell
E:\Android\Sdk\platform-tools\adb.exe uninstall app.dsh.mobile
E:\Android\Sdk\platform-tools\adb.exe install <仓库目录>\dist\dsh-mobile-0.1.2-debug.apk
```
之后密钥固定，升级可以原地覆盖安装（`adb install -r`），不会再要求卸载。

**如果还报签名错误，按这三条查**：

1. 手机时钟：设置 → 系统 → 日期与时间 → 打开「自动设置」；
2. 传输损坏：核对文件大小与 SHA-256（构建脚本会打印）；
3. 拿到准确错误码：`adb install` 输出里的 `INSTALL_FAILED_*`（图形界面安装器只给一句模糊的中文）。

## 七、这一版**已验证 / 未验证**（别混）

**已验证（本机，可复现）**

- 工具链：`java 17.0.20.1` / `aapt2 2.19` / `adb 1.0.41` / `gradle 8.11.1` / `sdkmanager 12.0`
- 纯逻辑与契约单测：**25 个全过**（Endpoint 7 / ProfileStore 6 / TokenExchange 4 / TunnelGuidance 4 / ManifestContract 4）
- 构建：`assembleDebug` BUILD SUCCESSFUL
- APK 元数据（v0.1.2，产物内清单实测）：包名 `app.dsh.mobile`、versionCode 2、versionName 0.1.2、**minSdk 33 / targetSdk 35**、`launchable-activity = app.dsh.mobile.ui.MainActivity`、`<application android:name="app.dsh.mobile.DshApp">`、权限 INTERNET + POST_NOTIFICATIONS + `com.termux.permission.RUN_COMMAND`
- APK 签名：**工程自带调试密钥**（`android/signing/debug.keystore`，生效 2020-01-01 起 / 30 年），证书 SHA-256 `c0964b04d7b1c33be2dbb83bb08c3b6bcfdb9142ff09ffa209a74505a0e556e3`；签名方案 **v2 = true**
- 产物指纹：`dist\dsh-mobile-0.1.2-debug.apk` 11.15 MB，SHA-256 `5AA2C7B36994BC6B6AB9E33A0472F20DFC240F488F04EF993300028ADFE09871`
- 图标几何：`tools\icon-preview.py` 安全区自检全过（内容 r≤29.3，上限 33），并生成三档预览
- 模式 B 链路：`tools\verify-mode-b.ps1` 端到端通过（见 `docs\02-remote-pc.md`）

**未验证（需要你的手机 / 需要你点几下）**

- **v0.1.1 在真机上能否正常启动**（v0.1.0 的闪退根因已定位并修掉、且加了守卫，但我没有设备能复跑一遍）
- Termux 侧的 `setup-dsh.sh` / 唤醒锁 / `am start` 回传（同上，只能在手机上跑）
- 真机上 WebView 里的 DSH 界面表现（软键盘、横竖屏、文件上传下载）
- release 签名（当前只有 debug 签名；要发布得自己生成 keystore）
