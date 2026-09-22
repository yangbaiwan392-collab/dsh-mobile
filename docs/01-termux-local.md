# 模式 A · 在手机自己上跑 DSH（Termux）

> 引擎跑在手机里，绑定 **127.0.0.1**。这是 DSH 设计的路径（loopback + 本机 token），没有跨机、没有明文外泄。
> 代价：**没有 ComfyUI / 本地大模型**，模型要走云端 API key。

## 一、装（手机上，一次性）

### 装哪个 Termux（F-Droid 里搜 "termux" 会出现一堆，只装这两个）

| 装 | 名字 | 包名 | 为什么 |
|---|---|---|---|
| ✅ | **Termux**（`>_` 图标的那个主程序，摘要里带 "Terminal emulator with packages"） | `com.termux` | 终端本体 |
| ✅ | **Termux:API** | `com.termux.api` | 脚本要用 `termux-wake-lock`（防后台冻结）与 `termux-clipboard-set`（把入口地址塞剪贴板） |
| ❌ | Termux:Float / :Widget / :Tasker / :Styling / :Boot / :GUI | | 都是插件，本流程用不到 |
| ❌ | Termux Hub | | 第三方、F-Droid 标了"反特征" |
| ❌ | Google Play 版 Termux | | 已废弃，别用 |

### 把脚本放进去

最省事：PC 上打开「此电脑」→ **moto g54** → `Internal shared storage` → `Download`，
把 `<仓库目录>\phone\` 里的三个 `.sh` 拖进去（该文件夹还附了 APK 与说明，一次拷完）。

然后在 Termux 里执行：

```bash
termux-setup-storage                                   # 授权访问 Download（首次会弹窗）
mkdir -p ~/dsh-android
cp ~/storage/downloads/{setup-dsh.sh,start-dsh.sh,tunnel-to-pc.sh} ~/dsh-android/
bash ~/dsh-android/setup-dsh.sh
```

> ⚠ app 里的「启动手机上的 DSH」按钮就是按 **`~/dsh-android/start-dsh.sh`** 这个路径调用脚本的
> （`TermuxBridge.DEFAULT_SCRIPT_PATH`），所以目录名别改 —— `tools/check-contracts.ps1` 会核对这条一致性。

### 脚本在本机验到什么程度（手机之前能做的都做了）本机没有 Termux，也**没有已注册的 WSL 发行版**（`wsl -l -v` 原话：没有已安装的分发版），
所以用 **Git for Windows 自带的 bash 5.2** 做了这些（`tools/test-termux-scripts.sh`，10 项全过）：

- 三个脚本 `bash -n` 语法检查；
- 用桩命令真跑 `start-dsh.sh`：从 dsh 的真实输出格式里**摘出带 token 的 URL（不吃 `(LAN: …)` 尾巴）**；
- 递给 app 的组件名与 extra 键**实测为** `-n app.dsh.mobile/.ui.MainActivity -e dsh_url <url>`；
- 服务已在跑时走"复用"分支、不重启。

> 这套测试在真机上跑之前就抓到了一个会让链路**静默失败**的 bug：脚本里曾写成 `.MainActivity`
> （少了 `.ui`），而它后面带着 `|| true`，在手机上会"看起来一切正常、app 却没收到地址"。
> 现在 `tools/build-apk.ps1` 每次构建都会先跑跨工件契约检查 + 这个脚本测试。

### npm 装 DSH 必失败？那是上游发布坏了（已内置绕法）

真机症状：

```
npm error code ETARGET
npm error notarget No matching version found for
  @deepseek-ai/dsh-client-ui-sidebar-documentpreview@^0.1.5-rc.3
```

成因（在 npmjs 与 npmmirror 上逐版本核对过）：
`@deepseek-ai/dsh-client-ui-sidebar` 有一个**乱序发布的 `0.1.5-rc.3`**，而配套的
`dsh-client-ui-sidebar-documentpreview` **没有 rc.3**（只有 rc.1/rc.2，然后跳到 `0.1.6-alpha.*`）。
`^0.1.5-rc.3` 按 semver **只匹配 0.1.5 系列**（预发布版本不会跨 patch 匹配），因此无解 ——
**任何全新安装都会失败**，与你的网络/镜像无关。

脚本现在的做法：**不用 `npm i -g`**，而是装进 `~/dsh-install` 项目目录，用 `overrides`
把相关子包钉到**已知可用的 `0.1.5-rc.2` 组合**，再 `npm link @deepseek-ai/dsh` 暴露命令。
该组合在本机用 `--dry-run` 实测 **584 个包全部解析通过**（`tools/probe-dsh-versions.ps1` 可复现）。

手工等价命令见 README 的 FAQ；上游修好后本绕法无需移除（钉版本本身无害）。

## 二、用

- 启动输出里那一行长这样（这是 DSH 自己打印的，脚本只是把它抓出来）：
  ```
  dsh web: http://127.0.0.1:3080/?token=xxxxxxxx
  ```
- 把整条 URL 粘进 app 的"添加入口"里保存；或直接点 Termux 输出里的链接用手机浏览器打开。
- **token 每次启动都会变，但换到的 cookie 有 30 天有效期** —— 所以只要 dsh 一直用同一个 `DSH_HOME`、端口不变，粘一次能用很久。
- 想每次开机自动起：Termux 里 `pkg install termux-services`，或把 `start-dsh.sh` 加进 `~/.bashrc`。
- 想省电就 `termux-wake-unlock`（服务会停）。

## 三、判据（自己验，别信我说）

| 检查 | 命令 | 期望 |
|---|---|---|
| 服务在听 | `curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:3080/` | `401`（没 cookie 就该被拒，说明服务活着） |
| token URL 在日志里 | `grep -m1 'dsh web: ' ~/.dsh-web.log` | 一行带 `?token=` 的 URL |
| 唤醒锁生效 | Termux 通知栏出现 "wake lock held" | 屏幕关掉后服务不被冻结 |

## 四、已知限制（Android 13+）

- 后台冻结很凶：没有唤醒锁，切走几分钟进程就被挂起 → 脚本默认拿锁。
- Termux 里没有 `pwsh`，所以 DSH 的 `pwsh` 系列工具用不了；`bash` 工具可用。
- 手机上没有 ComfyUI / Ollama，凡是要它们的技能都会失败（skill 里会报本地能力缺失）。
- 存储：Termux 的家目录在 app 私有区；要看手机公共目录里的文件得先 `termux-setup-storage`。
