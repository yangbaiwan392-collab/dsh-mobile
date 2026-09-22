package app.dsh.mobile.core

/**
 * 模式 B 的"怎么连 PC"知识集中在这里（纯逻辑）。
 *
 * 为什么不塞进 UI：这些命令与风险说明是**会变的领域知识**（DSH 的绑定限制、cookie 语义），
 * 放一处才能一起改、一起测；UI 只负责显示。
 */
object TunnelGuidance {

    /** 推荐方案：SSH 本地转发（加密、不绕信任栅栏）。 */
    fun sshTunnelCommand(pcHost: String, pcUser: String, port: Int): String =
        "ssh -N -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 " +
            "-L 127.0.0.1:$port:127.0.0.1:$port $pcUser@$pcHost"

    /** 免管理员方案：PC 上跑本仓库的回环改写代理。 */
    fun proxyCommand(proxyPort: Int, dshPort: Int): String =
        "node tools/loopback-proxy.mjs --listen 0.0.0.0:$proxyPort --target 127.0.0.1:$dshPort"

    /** 手机端（Termux）开隧道。 */
    fun termuxTunnelCommand(pcHost: String, pcUser: String, port: Int): String =
        "bash tunnel-to-pc.sh $pcHost $pcUser $port"

    /** PC 上启用 OpenSSH 服务器（需管理员，一次性）。 */
    fun enableSshServerCommand(): String =
        "Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0; Start-Service sshd"

    /** 必须让用户看到的代价（原文写在 docs/02-remote-pc.md）。 */
    fun riskNotes(): List<String> = listOf(
        "DSH 只监听 127.0.0.1，禁止 0.0.0.0 —— 局域网直连在它设计上就是不可能的。",
        "免管理员代理走明文 HTTP，而 DSH 的会话 cookie 不带 Secure：同网段抓到就是完整身份。",
        "用代理等于绕过它\"只允许 loopback\"的意图；DSH 能执行 shell，作者明确警告过这个风险。",
        "建议：家里 Wi-Fi 才用代理；长期使用请走 SSH 隧道。",
    )
}
