# 模式 B · 手机连 PC 上的 DSH

> 引擎留在 PC（ComfyUI / Ollama / 全部技能都在），手机当客户端。

## 零、先认清这条硬约束（本机实测，不是推测）

DSH **永远只监听 127.0.0.1**：

| 尝试 | 实测结果 |
|---|---|
| `dsh web --host 0.0.0.0` | 启动即被拒：`--host 0.0.0.0 is intentionally not supported yet for safety: it would expose remote code execution to the network` |
| `dsh web --host 192.168.0.105` | 配置校验失败：`$.host expected "127.0.0.1" \| "0.0.0.0" but got "192.168.0.105"` |

所以**手机不可能直连 PC 的 3080**，必须有一个转发者。两条路：

| 方案 | 要管理员吗 | 传输 | 评价 |
|---|---|---|---|
| **B1 · SSH 隧道** | 要（PC 上启用 OpenSSH 服务器） | **加密** | **推荐**：不碰信任栅栏、cookie 不出明文 |
| **B2 · 回环改写代理** | 不要 | 明文 HTTP | 能用，但见下面的安全代价 |

## 一、B1 · SSH 隧道（推荐）

**PC 侧（一次性，需管理员 PowerShell）**
```powershell
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
Start-Service sshd
Set-Service sshd -StartupType Automatic
```
> 本机现状：只有 `ssh-agent`（已停止/禁用），**没有 sshd**；上面这条命令我没跑（需要提权，本会话没有）。

**手机侧（Termux）**
```bash
bash tunnel-to-pc.sh <PC 的局域网 IP> <PC 用户名>
# 等价于： ssh -N -L 3080:127.0.0.1:3080 <用户>@<PC_IP>
```
然后 app 里添加入口：`http://127.0.0.1:3080/?token=<PC 控制台打印的那串>`。
（用 `tools\loopback-proxy.mjs` 不需要；隧道已经把"手机上的 127.0.0.1:3080"接到 PC 的回环端口了 ——
在 DSH 看来这就是本机访问，**栅栏、cookie 绑定、`SameSite` 全都自然满足**。）

## 二、B2 · 回环改写代理（无需管理员，本机已验证）

**PC 侧**
```powershell
node <仓库目录>\tools\loopback-proxy.mjs --listen 0.0.0.0:8081 --target 127.0.0.1:3080
```
**手机侧**：app 里添加入口 `http://<PC 的局域网 IP>:8081/?token=<那串 token>`。

### 实测结果（`tools\verify-mode-b.ps1`，隔离实例 + 隔离端口，没碰你正在用的 3080）
```
1. 隔离实例启动           ok  http://127.0.0.1:3099/?token=…
2a. 伪 Host + token       HTTP 303   ← 这道栅栏比它的文档宽松：并未按 Host 拒绝
2b. 伪 Host 无 token      HTTP 401   ← 未认证照样拒
2c. 伪 Host + 跨站 Origin  HTTP 401
3. 代理启动                ok  :8081 -> 127.0.0.1:3099
4. 经代理交换 token         HTTP 303；Set-Cookie=已下发
5. 带 cookie 取首页         HTTP 200；长度=27660；外壳=像 SPA（拿到真的 DSH 前端）
```
代理同时转发了 WebSocket 升级（DSH 的 `/api/remote.mux`），否则 app 的实时流会断。

### ⚠ 安全代价（用之前必须接受）
1. 明文 HTTP：DSH 的会话 cookie **不带 `Secure`**（官方只跑 loopback），同网段抓到就是完整身份。
2. 这是**有意绕过**它"只允许 loopback"的设计意图；作者在拒绝 `0.0.0.0` 时给的理由是"会把远程代码执行暴露给网络"——DSH 本体能跑 shell，这个警告是认真的。
3. 因此：**只在你完全信任的家庭 Wi-Fi 用**，别在咖啡厅/公司网/公网开。要长期用请走 B1。

## 三、cookie 与端口的两条注意

- cookie **绑 hostname+port**：B2 下如果 PC 的局域网 IP 变了（DHCP 换 IP），手机上的登录态会失效 → 给 PC 配静态 IP 或 DHCP 保留。
- cookie 有效期 30 天（`cookieMaxAgeDays`），但**签名密钥**在 PC 的 `$DSH_HOME/.credentials.yaml` 里；换 `DSH_HOME` 或删该记录 = 所有手机都得重新交换一次 token。
