# 文档索引

| 文档 | 什么时候读 |
|---|---|
| [../README.md](../README.md) | **先读这个**：这是什么、两种模式、快速开始、项目结构、验证状态、FAQ |
| [01-termux-local.md](01-termux-local.md) | 模式 A：在手机 Termux 里跑 DSH。含"装哪个 Termux"、"怎么把脚本放进去"、脚本验证到什么程度 |
| [02-remote-pc.md](02-remote-pc.md) | 模式 B：手机连 PC 上的 DSH。含硬约束实测、SSH 隧道 vs 免管理员代理、cookie/端口注意 |
| [03-build.md](03-build.md) | 构建、安装、**真机事故排查**（闪退 / 签名错误各一例，含日志抓法） |
| [04-new-phone.md](04-new-phone.md) | 新手机开箱：从零到"手机上跑 DSH"（装 APK → 启动 → 防回收 → 沙箱自检） |
| [05-anywhere-tailscale.md](05-anywhere-tailscale.md) | **离开局域网也能用**：Tailscale 组网 + `tailscale serve` + 凭据签发；含重启清单与过期重发 |
| [../SECURITY.md](../SECURITY.md) | 部署前必读，尤其是模式 B 的 B2 代理代价与 B3 组网边界 |
| [../CONTRIBUTING.md](../CONTRIBUTING.md) | 想改代码：环境、构建、测试、代码纪律、PR 检查单 |
| [../CHANGELOG.md](../CHANGELOG.md) | 版本历史（★ 标记的是真机踩出来的坑） |

## 图片

`images/` 放仓库用的图。当前有：

- `icon-round.png` / `icon-small.png` —— 应用图标（圆形遮罩模拟 / 48dp 观感），由 `tools/icon-preview.py` 生成。

**待补**：真机界面截图（模式 A 的入口列表、WebView 里的 DSH 界面、崩溃日志弹窗）。
本项目在开发机上没有模拟器，截图来自真机 —— 欢迎提 PR 补充，或把截图发到 issue 里。
