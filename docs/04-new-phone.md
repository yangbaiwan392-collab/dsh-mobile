# 新手机开箱：从零到"手机上跑 DSH"

> 目标：一部全新的 Android 手机（13+），**只需要 3 个 APK + 1 次点击**。
> 前提：手机与（可选的）PC 在同一个 Wi-Fi。

## 一、装三个 APK（都在 `phone/` 目录里，已核对过官方 sha256）

| 顺序 | 文件 | 说明 |
|---|---|---|
| 1 | `termux-app_v0.118.3+github-debug_arm64-v8a.apk` | Termux 本体（官方 GitHub 发布版；arm64 机型用它） |
| 2 | `termux-api-app_v0.53.0+github.debug.apk` | Termux:API —— 唤醒锁 / 剪贴板要用 |
| 3 | `dsh-mobile-<版本>-debug.apk` | 本 app |

装法任选：
- **手机浏览器/文件管理器**：把这几个 APK 拷进手机（MTP 或直接从 PC 局域网传），逐个点安装，允许"安装未知应用"。
- **adb**（若已开 USB 调试或无线调试）：`adb install -r dsh-mobile-<版本>-debug.apk`。
  `adb install` **不会自动授予** Termux 的运行时权限，所以首次点「启动手机上的 DSH」时
  app 会弹一次授权（同意即可）；也可以 `adb shell pm grant app.dsh.mobile com.termux.permission.RUN_COMMAND`。

> APK 是**调试签名**（工程自带密钥，同一把，所以以后升级可以直接覆盖安装）。
> 要在应用商店/公开分发，用 `docs/03-build.md` 里的 release 签名说明另出一版。

## 二、打开 app，点一次「启动手机上的 DSH」

菜单 →「启动手机上的 DSH」。这一下会**自动**做完：

1. 把手机侧脚本（`setup-dsh.sh` / `start-dsh.sh` / `tunnel-to-pc.sh` / `fix-android-runtime.sh`）
   从 APK 的 assets 写进 Termux 的 `~/dsh-android/`（无需任何手工拷贝）；
2. 装 Node（`nodejs-lts`）、`curl`、`openssh`、`termux-api`；
3. 装 DSH（走国内镜像 + `overrides` 绕开上游坏发布）；
4. 装 `python clang make` 并**在手机上现编** `node-pty`；
5. 装 **wasm 版 sharp**（免编译）；
6. 跑 `fix-android-runtime.sh`：现编 `flock` 原生模块 + 把会话持久化的 `link()` 换成 `rename()`
   （Android 禁硬链接）；
7. 拿唤醒锁、启动 `dsh web`，并把带 token 的入口地址交给 app（走剪贴板，绕开"后台不能启动页面"的限制）。

首次会跑几分钟（第 4、6 步要编译）；**过程要留在 Termux 的通知在前台**，别让系统把 Termux 杀掉。

## 三、让它别再被系统回收（强烈建议）

```powershell
adb shell dumpsys deviceidle whitelist +com.termux
```
没有 adb 的话：系统设置 → 应用 → Termux → 电池 → 选「不限制」。

**但这还不够** —— 2026-09-25 在 moto XT2611-1 / Android 16 上实测出两件事，都得处理：

### ① 唤醒锁（启动脚本已自动带）

不加锁时 Termux 只是**普通后台应用**："清理后台 / 划掉最近任务"会把它强停，DSH 的 node 子进程跟着死。
系统日志里那条证据非常直白：

```
ApplicationExitInfo: reason=10 (USER REQUESTED) subreason=21 (FORCE STOP)
                     description=stop com.termux due to RemoveTaskMemoryClean
```

`termux/start-dsh.sh` 现在会先跑 `termux-wake-lock`：Termux 变成**前台服务**（常驻一条通知），
清后台杀不掉（`dumpsys power` 里能看到 `'termux:service-wakelock' … LONG`）。解除用 `termux-wake-unlock`。

### ② ROM 会拦"别的应用启动 Termux"，而且拦了也不报错

现象：app 里点「启动手机上的 DSH」，**请求被系统悄悄丢掉**（`startService` 不抛异常、无返回值，
所以 app 侧改成**实测 `127.0.0.1:3080` 有没有人在听**来判定成败，见 `core/TermuxStartReport`）。系统日志：

```
MotoBatteryCareService: isBatteryCareAllowedSelfStart restricted com.termux by mode
PackageManager: filterSelfStart: callingUid=app.dsh.mobile → target=com.termux
ActivityManager: Unable to start service Intent { act=com.termux.RUN_COMMAND … }: not found
DeviceGuard: [AutoRunServices] onSelfStartRestricted → com.termux, fromPkg=app.dsh.mobile
```

**即使让 Termux 起来了，系统也会在十几秒后以 `due to AutoRun` 再停它一次** ——
哪怕它已经是前台服务（`importance=125 FOREGROUND_SERVICE`）。所以别和它硬碰，走下面任一条：

1. **让 Termux 常驻**：它活着，app 的按钮和入口就一直好用（唤醒锁保证它活着）。
2. **打开一次 Termux 就够了**：`start-dsh.sh` 会往 `~/.bashrc` 装一个钩子
   （"若 3080 没在听，就后台跑一次 start-dsh.sh"），于是**用户自己点开 Termux 就能把 DSH 拉起来**
   —— 这条路不受自启动策略限制，因为它不是"被别的应用拉起"。
   app 里"打不开这个入口"的提示会直接给「打开 Termux」按钮，点了之后系统会弹
   **「DSH 手机端 想要打开 Termux / 打开 · 仅限这一次 · 取消」**（摩托的 `MotoConfirmAppStartActivity`），
   点「打开」，回到 app 会自动重试并加载成功。

> **国行 Moto 的名称差异与边界**（都实测过）：
> - 「关于手机」里连点 7 次的那个，国行叫「**系统标识**」（原生/国际版叫"版本号"）；
> - 「开发者选项」可能在 设置 → 系统 或 设置 → 其他设置 下；
> - 没有 Play 商店的国行机型也能跑 Termux 与 DSH（Termux 不依赖 Google 服务）；
> - 那个**自启动/关联启动管理界面没有导出**：`com.motorola.deviceguard/.autoRun.activity.AutoRunMainActivity`
>   用 adb 打不开（`you do not have permission to access it`），电池页与应用信息页里也没有入口
>   —— 所以这条只能用户在设置里找，agent 帮不上。

## 四、验证"这部手机能不能让 agent 跑 shell 命令"

菜单 →「环境自检」，看最后三条：

```
[11] 内核：…
[12] Landlock：可用 / 不可用
[13] 结论：可以用 workspace-write 跑命令 ／ 只能把沙箱模式设为 danger-full-access
```

### 先把概念分清：**终端能跑 ≠ agent 能跑**

- 你在手机上装过的"虚拟 Linux"（**Termux**、或 Termux 里的 `proot-distro` / Andronix / UserLAnd）
  是**给人类用的终端** —— 你自己敲 `ls`，没有任何东西拦你，那是**你**在跑。
- DSH 要让 **agent** 跑命令时，会先把 agent 关进一个**沙箱**再执行 —— 这是设计上的安全默认：
  拿不到沙箱后端，它**拒绝执行**（宁可不做，也不无约束地跑）。

### DSH 在 Linux 上的沙箱后端是一条链

源码（`@deepseek-ai/dsh-sandbox-local`）里的顺序是 **`["bwrap", "landlock"]`**：

| 后端 | 要求 | Android 上的实际情况 |
|---|---|---|
| `bwrap`（bubblewrap） | 非特权**用户命名空间**（`unshare -U`） | Android 一般不允许（Termux 因此才改用 `proot` 这种 ptrace 方案）→ 多半不可用 |
| `landlock` | 内核 **≥ 5.13** 且启用了该 LSM；用 `@deepseek-ai/node-addon-system-<平台>/bin/landlock-run --probe` **功能探测** | 手机内核常见 5.10（本机实测 `Linux 5.10.218-android…`，`/sys/kernel/security/landlock` 不存在）→ 不可用 |

`termux/fix-android-runtime.sh` 会**把 `landlock-run` 也编好**（源码在同一个包里，`src/main.c`），
所以：**内核支持 Landlock 的手机，装上就是可用状态**；内核不支持时它会明确告诉你"只能 danger-full-access"。

### 结论怎么用

- 内核 ≥ 5.13 且有 Landlock → 直接可用，agent 在 `workspace-write` 等模式下就能跑命令（最安全）；
- 否则只有两条路：把沙箱模式放宽到 **`danger-full-access`**（**只建议在专用设备上**），
  或者接受"手机上不跑需要 shell 的任务"（界面、对话、文件读写都不受影响）。

## 五、（可选）让手机连 PC 上的 DSH

见 `docs/02-remote-pc.md`。要点：DSH 只监听 `127.0.0.1`，所以必须有转发者
（SSH 隧道最干净；或 `tools/loopback-proxy.mjs` 免管理员但有明文代价）。

**离开自己的网段也要用？** 见 [`05-anywhere-tailscale.md`](05-anywhere-tailscale.md)：
用 Tailscale 组网 + `tailscale serve` 挂真证书 HTTPS 入口，模型通路走组网 IP 直连 `8083`。
该文档同时给出**重启电脑后的照做清单**（Ollama 与 8083 代理都不自启）与**凭据过期后的重发命令**。
