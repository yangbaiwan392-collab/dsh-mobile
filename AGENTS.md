# AGENTS.md —— 在这个仓库里干活的规则

> 这份文件是**给 agent 看的**（人也可以读）：在这个仓库里干活时的约定。
> 为什么要有：本项目最贵的 bug 都是**"改动看着合理、但在真机上悄悄坏掉"**，而 CI 抓不到那类问题
> （没有模拟器、没有仪器测试，界面回归全靠人眼）。所以这里写的是**流程上的硬规矩**，不是建议。

## 0. 三条硬规矩

1. **bug：先说清现象，再动代码；改完必须交代"验证到哪一步"。**
   比如"本地契约检查全绿 + 真机装了一次"就说这两句，**没真机验证过的部分要明说"未真机验证"**，
   不要用语气把没验的东西说成验过了 —— 作者对这一点极其在意。
2. **新功能：先讨论，不先写代码。** 提方案时给 **2–4 个选项 + 各自代价**（维护成本 / 真机验证成本 /
   是否引入常驻或自动行为），由维护者拍板。本项目目标很窄（把 DSH 的 Web GUI 在 Android 上用顺手），
   **"能做"不等于"该做"**。
3. **不加自动 / 常驻 / 定时行为**：自启、看门狗、后台轮询、空闲清理、计划任务……一律先问。
   历史教训：先前有过"agent 顺手加了自动行为被要求撤回"的记录。

## 1. 开工顺序（省时间，别重新摸索）

1. `README.md` 的「先说不足」+「已知限制 / 路线图」—— 那里写着**已经承认的缺口**，别当新发现上报。
2. `CONTRIBUTING.md` —— 代码纪律（`core/` 纯逻辑 + 单测、单一事实源、一个文件一件事、< 150 行）。
3. `CHANGELOG.md` 最近两版 —— 很多坑已经写在里面（带 ★ 的是真机踩出来的），别重踩。
4. 按需读 `docs/`：`01-termux-local.md`（模式 A）/ `03-build.md`（构建与装包）/ `04-new-phone.md`（换机）/
   `05-anywhere-tailscale.md`（出网段远程访问）。

## 2. 改完必须做的事

- 跑 `tools/check-contracts.ps1`（8 条跨工件契约）与 `tools/test-termux-scripts.sh`（22 项）；
  一把过用 `tools/build-apk.ps1`（契约 → 脚本测试 → Gradle → 打印 APK SHA-256 与签名指纹）。
- **跨工件的字符串**（组件名 / extra 键 / 脚本路径 / 端口 / 版本号）改了就**加进契约检查**，别靠人眼对齐。
- 文件编码：`.ps1` 必须 **UTF-8 带 BOM**（PowerShell 5.1 读无 BOM 脚本用系统 ANSI 代码页 → 中文乱码；
  契约 8 会拦）；`.sh` 必须 LF（`.gitattributes` 管着）。
- 用户可见行为变了 → 同步改 `docs/` 与 `CHANGELOG.md`。
- 收尾把结论写进本机笔记：`E:\harness2\notes\android-dsh-app.md`（细节）、`lessons.md`（教训）、
  `INDEX.md`（入口）。**agent 没有跨会话记忆 —— 没写下来的，下次就是零。**

## 3. 凭据与用户环境（红线）

- **不打印 key / token / 入口 URL**。自检报告里的 token 已打码（有单测锁着），别在别处又打印回来；
  截图前先自己看一眼。
- 不进仓库：`android/signing/debug.keystore`、`android/signing/release.keystore`、`android/keystore.properties`、
  `dist/`、`phone/`。
- **别去动维护者正在用的东西**：3080 上的 `dsh web`（agent 自己往往就坐在上面）、Ollama、ComfyUI。
  真要重启/改配置，先说一声、并说明回退办法。

## 4. 提交与发布

- Conventional Commits（中文可以）：`fix(web): …` / `feat(ui): …` / `docs(termux): …`。
  **一个提交一件事**；别把纯格式化与逻辑改动混在一起（评审和回退都靠这个）。
- 发布按 `RELEASING.md`：打 tag → 传 APK → 在说明里写 **SHA-256** 与"debug 签名、不可正式分发"这类前提。
- 版本号两处一起改：`android/app/build.gradle.kts` 的 `versionCode`/`versionName` + `CHANGELOG.md`。
