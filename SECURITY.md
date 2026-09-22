# 安全说明

## 这个 app 会碰什么

- **不收集任何数据**，没有分析/遥测/账号体系。
- 唯一的网络访问是**你配置的 DSH 实例**（以及该实例页面自身加载的资源）。
- 不读取你的文件系统权限（文件上传走系统文件选择器 SAF，下载走 `DownloadManager`）。
- 入口地址与 token 存在 app 私有目录（`files/profiles.json`），token 明文存储但不出 app 沙箱。

## 模式 A（手机本地）为什么不引入新风险

DSH 跑在手机自己的 Termux 里，只监听 `127.0.0.1`；app 也在这台设备上访问它。
这正是 DSH 设计时的信任模型（loopback + 进程级 token 换 cookie），**没有跨设备、没有明文出机**。

## 模式 B 的两种转发方式：**B2 有真实代价，请读完再用**

DSH 只监听 `127.0.0.1`（这是它刻意的安全选择：`--host 0.0.0.0` 会被服务端拒绝，理由是
"would expose remote code execution to the network"）。要让手机连上就必须有转发者：

### B1 · SSH 隧道（推荐）

```bash
# 手机 Termux 里：
bash tunnel-to-pc.sh <PC 的 IP> <PC 用户名>
# 等价于：ssh -N -L 3080:127.0.0.1:3080 <user>@<PC_IP>
```
- phone→PC 这一段**加密**；
- 在 DSH 看来请求就是本机访问：信任栅栏、cookie 绑定、`SameSite=Strict` 全部自然满足；
- **不绕过**任何设计意图。
- 前提：PC 上要有一个 SSH 服务器（Windows 可启用自带的 OpenSSH 服务器）。

### B2 · 回环改写代理（`tools/loopback-proxy.mjs`，无需管理员）

它把手机发来的请求的 `Host` / `Origin` / `sec-fetch-site` **改写成 loopback** 再转给 DSH。
实测可行（`tools/verify-mode-b.ps1` 端到端通过），但请明确接受三条：

1. **明文 HTTP**：DSH 的会话 cookie **不带 `Secure`**（官方只跑 loopback HTTP），
   同一局域网内的被动嗅探可导致**身份被完整冒用**；
2. **有意绕过** DSH 的 browser-trust 栅栏 —— 那个栅栏本意就是阻止非 loopback 访问；
   DSH 能执行 shell，作者对"暴露到网络"的警告是认真的；
3. 因此：**只在完全可信的家庭局域网使用，绝不放到公网/公司网/公共 Wi-Fi**。

想要"能远程访问又不要这些代价"，正确做法是 B1，或在 PC 上自己架一个带 TLS 与认证的反向代理并
在 DSH 侧用 `--trusted-host` 显式声明该 authority（本项目不内置这种配置）。

## 其它注意

- app 声明了 `android:usesCleartextTraffic="true"`：**必需**，因为 DSH 官方只跑 loopback HTTP。
  如果你的部署全程 HTTPS，可以改成 `false` 收紧。
- 调试签名：`tools/make-debug-keystore.ps1` 生成的密钥口令是公开的（`android` / `androiddebugkey`），
  **不要用它签名要分发的正式版本**。
- 发布正式版请自备 release keystore，并把口令放在 CI 的 secret 里，不要提交进仓库。

## 报告漏洞

请通过 issue 里的私密渠道，或直接邮件联系维护者（在 GitHub 个人资料里）。
请在报告里写明：影响范围（模式 A/B）、复现步骤、你的部署形态（隧道 or 代理、是否 TLS）。
**不要在公开 issue 里贴 token、cookie 或内网地址。**
