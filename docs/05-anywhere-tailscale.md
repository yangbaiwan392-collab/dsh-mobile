# 05 · 离开局域网也能用（Tailscale 组网）

> **本文里的 `<...>` 都是占位符**（`<你的 tailnet>`、`<主机名>`、`<PC 的组网 IP>` …），请替换成你自己的值。
> 文中所有数字都是实测值，括号里标了测法；命令可直接照抄，只需先替换占位符。
>
> 建置日期 **2026-09-25**，全部结论均为当天实测，不是推测。
> 适用机型：moto XT2611-1 / Android 16（tailnet 里叫 `<手机节点名>`）。
> PC：Windows 11，tailnet 节点 `<主机名>`。

## 一、要解决的是什么

手机上的 DSH 本身跑在 Termux 里，**它不需要网**；出网段就废掉的是它的**脑子**——
模型指向家里 PC 的 `<PC 的局域网 IP>:8083`。所以问题不是"DSH 不能离线"，而是"模型通路只在局域网里"。

顺带把第二件事也做了：在外面用手机浏览器打开 **PC 上这个完整 GUI**（含全部技能、工作流、工作区）。

## 二、拓扑

```
手机（4G/5G/别人家 Wi-Fi）                     家里 PC
┌───────────────────────────┐                ┌─────────────────────────────────────┐
│ Tailscale 应用  <手机的组网 IP>│◄── 组网直连 ──►│ Tailscale  <PC 的组网 IP>            │
│                            │   (打洞失败时   │   ├─ 127.0.0.1:3080  DSH Web GUI   │
│ ①Termux 里的 DSH ──────────┼── 走 DERP 中继) │   │    └ tailscale serve --https=443│
│    └ 模型 baseURL ─────────┼───────────────►│   │       = https://<主机名>.       │
│                            │  http://<PC 的组网 IP>:8083/v1 │  <你的 tailnet>.ts.net/  │
│ ②Chrome ───────────────────┼───────────────►│   └─ 0.0.0.0:8083  回环代理        │
│    = https://<主机名>.      │                │        └─► 127.0.0.1:11434 Ollama  │
│      <你的 tailnet>.ts.net/    │                └─────────────────────────────────────┘
└───────────────────────────┘
```

- **两个地址各管一件事**：手机的 DSH 用 `<PC 的组网 IP>:8083`（IP 直连，避开 MagicDNS 依赖）；
  浏览器用 `https://<主机名>.<你的 tailnet>.ts.net/`（要真证书，所以必须走域名）。
- 在家时 Tailscale 会自动选**局域网直连**，不绕外网，所以这一个地址在家在外通用，**不需要维护两套配置**。

## 三、PC 侧做了什么

| 项 | 内容 |
|---|---|
| Tailscale 客户端 | `winget install Tailscale.Tailscale`（1.102.4），服务自启；**本机原本就已登录过该账号**，无需重新注册 |
| 组网身份 | 节点名 `<主机名>`、IP `<PC 的组网 IP>`、网域 `<你的 tailnet>.ts.net`、账号 `<你的 Tailscale 账号>`，密钥 2027-03-24 到期 |
| HTTPS 证书 | 管理后台 **DNS → HTTPS Certificates → Enable**（不开会报 `your Tailscale account does not support getting TLS certs`）；MagicDNS 本来就开着 |
| 反向代理 | `tailscale serve --bg --https=443 http://127.0.0.1:3080` → **仅组网内可达**（无 Funnel，公网扫不到）。配置由 tailscaled 持久保存，重启不丢 |
| 启动参数 | `<启动器目录>\start-dsh-web.ps1` 的 `$ExtraArgs` 加了 `--trusted-host <主机名>.<你的 tailnet>.ts.net`。**DSH 默认只信任回环地址**，不加这条 `/api` 会被浏览器信任栅栏挡成 403（页面能开但全是死的）。备份 `start-dsh-web.ps1.bak-20260925` |
| 一键重启 | `<启动器目录>\restart-dsh-web.cmd`（双击即杀旧进程+重新拉起，用于让启动参数变更生效） |
| 模型通路 | `<仓库目录>\tools\start-pc-model-services.ps1`（幂等）：拉起 Ollama(11434) 与回环代理(8083→11434) |
| 凭据签发 | `<仓库目录>\tools\dsh-remote-login.mjs`（见第六节） |

防火墙**不需要改**：安装包自带 `Tailscale-In`（Domain, Private）入站放行规则，而 Tailscale 网卡正是 Private 类别。

## 四、手机侧做了什么

1. Play 商店装 **Tailscale**，登录同一个 Google 账号，授权 VPN。
2. `~/.dsh/settings.yaml` 的 `ollama-pc.baseURL`：`http://<PC 的局域网 IP>:8083/v1` → **`http://<PC 的组网 IP>:8083/v1`**
   （备份 `~/.dsh/settings.yaml.bak-20260925`；改法见第七节的 adb 命令）。
3. 浏览器拿到 30 天登录 cookie，书签存 `https://<主机名>.<你的 tailnet>.ts.net/`。

## 五、实测数字（2026-09-25）

| 检查 | 结果 |
|---|---|
| `tailscale ping` PC→手机 | `via <手机的局域网 IP>:50982 in 35ms`（**直连**，非中继） |
| 手机 → 模型接口 | `curl http://<PC 的组网 IP>:8083/v1/models` → **HTTP 200 / 18.7 ms**，5 个模型 |
| GUI 无 cookie | `401` |
| GUI 带正确 cookie | `200`（28546 字节首页） |
| `/api/remote.mux` 加 `--trusted-host` 前 | `403`（栅栏拒绝） |
| 同上，重启后 | `404`（栅栏已放行，404 只是该路径不接受普通 GET） |
| 兜底中继延迟（PC 侧测得） | 香港 DERP 294 ms / 东京 272 ms；控制面 222 ms、登录页 173 ms |

## 六、登录凭据是怎么回事（**下次要重发时看这里**）

DSH 的浏览器鉴权有两层：

1. **启动时打印的 `?token=<每进程随机>`** —— 一次性"兑换入口"，进程重启即失效，且**无法从运行中的进程里读出来**（在内存 WeakMap 里）。
2. **真正长期生效的 cookie** —— `dsh-auth-<base64url(sha256(authority))>`，
   值是 `v1.<base64url(payload)>.<base64url(HMAC-SHA256(secret, body))>`，
   而 `secret` 是 **32 字节、持久化在 `~/.dsh/.credentials.yaml`** 的
   `client-connection/browser-session` 记录里。

**密钥是持久的** → 所以不必重启、不必去控制台抄 token，**直接用本机密钥签一张**即可。
`tools/dsh-remote-login.mjs` 就是干这个的：

```powershell
# 自检（只打印指纹，不打印 cookie 值）
node <仓库目录>\tools\dsh-remote-login.mjs --authority <主机名>.<你的 tailnet>.ts.net --check

# 给手机发放：先挂一个临时入口页，再让手机访问它
tailscale serve --bg --https=8443 http://127.0.0.1:3088
node <仓库目录>\tools\dsh-remote-login.mjs --authority <主机名>.<你的 tailnet>.ts.net `
     --port 3088 --public-port 8443 --url-file <仓库目录>\tools\.login-url --ttl-minutes 20
adb connect <手机的局域网 IP>:<无线调试端口>          # 端口用 tools\scan-adb-ports.mjs 扫
adb shell am start -a android.intent.action.VIEW -d "$(Get-Content <仓库目录>\tools\.login-url -Raw)"
tailscale serve --https=8443 off                  # 发完立刻撤掉入口
```

**为什么必须走"入口页"而不是直接给 url：** cookie 按**主机名**绑定（同主机不同端口共享），
手机要拿到的必须是 `<主机名>.<你的 tailnet>.ts.net` 这个主机的 cookie，所以承载 `Set-Cookie`
的页面也必须从这个主机名提供 → 用 `tailscale serve --https=<另一个端口>` 把本机的一个小
HTTP 服务挂到同一主机名上；cookie 与端口无关，所以 443 上的 GUI 立刻可用。
入口页有**一次性口令**、只监听 127.0.0.1、默认限时自动退出。

**⚠ 两个踩过的坑（别再踩）：**
- **`SameSite=Strict` 在手机上不管用**：实测（Android Chrome + CDP 抓包）**从外部 intent / 书签发起的
  顶层导航，Strict cookie 根本不会被带上**，于是每次点开都是 `dsh web authentication required`。
  PC 上没这问题，因为启动器每次都用带 token 的地址同站重种 cookie。所以**发给手机时用 `Lax`**
  （脚本里 `COOKIE_SAME_SITE_FOR_BROWSER`），只对顶层 GET 生效，`/api` 的 POST/WS 仍受信任栅栏保护。
- **对外 URL 的端口必须单独给**：脚本自己监听 3088，但手机走的是 serve 的 8443，
  所以有 `--public-port` 这个参数；不给就会得到一条打不开的链接。

**作废所有浏览器会话**：删掉 `~/.dsh/.credentials.yaml` 里 `client-connection/browser-session` 那条记录
（PC 上的窗口也要重新登录一次）。

## 七、重启电脑之后（照这个清单走）

| 组件 | 会自己回来吗 | 备注 |
|---|---|---|
| Tailscale 服务 + serve 配置 | ✅ 会 | tailscaled 自启，serve 配置持久 |
| dsh web（带 `--trusted-host`） | ✅ 会 | 用户平时那个启动方式即可 |
| **回环代理 (8083)** | ✅ 会 | **2026-09-25 用户拍板加了自启**：启动文件夹里 `DSH模型代理.lnk` → `tools/autostart-proxy.vbs` → `start-pc-model-services.ps1 -ProxyOnly`（**只起代理，完全不碰 Ollama**）。要停就在任务管理器→启动应用里禁用它，或结束监听 8083 的 node 进程 |
| **Ollama (11434)** | ❌ **不会** | 启动文件夹里的 `Ollama.lnk` **处于禁用状态**（`AGENTS.md` §5 说它有自启，与实况不符）。用户明确要求**保持手动**——它一被请求就把十几 GB 塞进显存，会跟出图抢卡 |
| 手机上的 Tailscale | ✅ 会 | 只要没被翻墙 VPN 挤掉 |

所以重启后**只需要处理 Ollama**（代理已经自己在了）：

```powershell
powershell -ExecutionPolicy Bypass -File <仓库目录>\tools\start-pc-model-services.ps1
```

它最后会**在组网 IP 上实测并打印模型个数**——看到 `<PC 的组网 IP> → 5 个模型` 才算真好了。
（只想确认代理还活着：加 `-ProxyOnly` 跑一次，它会跳过 Ollama。）

## 八、已知限制（用户须知）

1. **Android 同一时刻只允许一个 VPN 服务** → Tailscale 与翻墙 VPN **只能二选一**，得手动切。
2. Tailscale 的登录页/控制面在国内**直连可达**（实测 173 / 222 ms），所以日常**不需要挂着翻墙**用 Tailscale；
   但它的账号登录走 Google OAuth，那一步需要翻墙——**只需在 PC 的浏览器里做一次**（见第九节）。
3. 手机 DSH 要连模型，前提是**手机的 Tailscale 处于连接状态**。
4. 出门在外若打洞失败会退化到中继（香港/东京，约 300 ms），能对话、不适合密集交互。
5. 手机上的 cookie **30 天过期**（本次到 2026-10-25），到期按第六节重发一次。
6. 设备在组网里叫 `<手机节点名>`（取的是 Android 设备名），可在后台 Machine settings 改名。

## 九、手机上 Google OAuth 打不开时怎么办（本次实际用到的招）

Tailscale Android **不支持 auth key**（上游仍未实现：tailscale/tailscale#8497、#20774），只能走浏览器登录。
而 `login.tailscale.com/a/<短码>` 这种**设备授权地址本来就是为无头设备设计的——在任何一台浏览器上打开都能完成授权**。
所以：手机上点 Sign in 拿到那串 `/a/xxxx` → 在 **PC 的浏览器**里打开并用 `<你的 Tailscale 账号>` 确认 →
手机上的 Tailscale 几十秒后自己就连上了，**手机全程不需要访问 Google**（授权地址约 10 分钟内有效）。

## 十、相关文件

```
<启动器目录>\start-dsh-web.ps1              # 已加 --trusted-host（备份 .bak-20260925）
<启动器目录>\restart-dsh-web.cmd / .ps1     # 一键重启 dsh web
<仓库目录>\tools\dsh-remote-login.mjs      # 签发/发放浏览器登录凭据
<仓库目录>\tools\start-pc-model-services.ps1 # 幂等拉起 Ollama + 8083 代理
<仓库目录>\tools\loopback-proxy.mjs        # 8083 → 11434 的实际转发者
<仓库目录>\tools\scan-adb-ports.mjs        # 扫无线调试端口（mDNS 在本机不可用）
```
