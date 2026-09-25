package app.dsh.mobile.core

/**
 * 「启动手机上的 DSH」这件事的**结论**。
 *
 * 为什么必须有这么一层：真机上 app **谎报过成功**。摩托罗拉（XT2611-1 / Android 16）的
 * DeviceGuard 会把 `com.termux/.app.RunCommandService` 的启动请求**直接丢掉**
 * （系统日志：`filterSelfStart … Unable to start service … not found`、
 * `stop com.termux due to AutoRun`），而 `Context.startService()` 对"被丢掉"和"成功"
 * 一视同仁：既不抛异常、也没有返回值。于是唯一可靠的判据是
 * **本地端口有没有真的在监听**，而不是"intent 发出去了没有"。
 *
 * 这一层是纯逻辑（不碰 Android API），所以能单测；UI 只负责把结论翻成文字与按钮。
 */
enum class TermuxStartOutcome {
    /** 端口探到了：这次真成了。 */
    READY,

    /** 请求发出去了，但等到超时也没人监听：多半被系统的自启动/关联启动限制拦住了。 */
    NOT_STARTED,

    /** 请求根本没发出去：没装 Termux、缺运行命令权限、或 startService 抛了异常。 */
    REQUEST_FAILED,
}

object TermuxStartReport {

    /**
     * 判定。顺序有意义：请求都没发出去就谈不上"起来了"；
     * 只有"请求发出去了"才轮到端口说话。
     */
    fun classify(requestSent: Boolean, portReachable: Boolean): TermuxStartOutcome = when {
        !requestSent -> TermuxStartOutcome.REQUEST_FAILED
        portReachable -> TermuxStartOutcome.READY
        else -> TermuxStartOutcome.NOT_STARTED
    }

    /**
     * 要不要给「打开 Termux」这个手动兜底按钮。
     *
     * 要的原因：系统的限制拦的是"**从停止状态**被别的应用拉起"，用户手动点开 Termux 不受影响；
     * 开过一次之后 Termux 已是前台服务（脚本里有 termux-wake-lock），再点启动按钮就顺了。
     * 成功时不显示，避免把"还能这么干"当成正常步骤。
     */
    fun offersOpenTermux(outcome: TermuxStartOutcome): Boolean = outcome != TermuxStartOutcome.READY

    fun readyMessage(port: Int): String =
        "本机 DSH 已就绪：127.0.0.1:$port\n\n" +
            "入口地址（带 token）随后由 Termux 回传，会自动并进「手机本地」这条入口。"

    /**
     * 没起来时**必须说实话 + 给下一步**：以前这里显示的是"已让 Termux 启动本地 DSH"，
     * 用户照着等，白等一场（真机踩过）。
     */
    fun notStartedMessage(port: Int, waitedSeconds: Int): String = buildString {
        appendLine("等了 $waitedSeconds 秒，127.0.0.1:$port 仍然没有服务在监听 ——")
        appendLine("启动请求确实发出去了，但 Termux 没跑起来（或者刚起来就被系统杀掉了）。")
        appendLine()
        appendLine("最常见原因：系统的「自启动 / 关联启动」限制把 Termux 拦住了。")
        appendLine("摩托的 DeviceGuard、小米/华为的「自启动管理」都有这类开关，系统日志里会出现")
        appendLine("filterSelfStart、stop com.termux due to AutoRun 这类字样。")
        appendLine()
        appendLine("两种解法（任选）：")
        appendLine("· 去设置里把 Termux 与本 app 的「自启动」**和**「关联启动」都设为允许 —— 只开一个仍可能被拦；")
        appendLine("· 或者点下面的「打开 Termux」手动开一次，再回来点「启动手机上的 DSH」（手动开不受该限制）。")
    }

    /** 连请求都没送出去时，把真实原因说出来（UI 会接上 bridge.manualSteps()）。 */
    fun requestFailedMessage(detail: String?): String =
        "启动请求没能发出去：\n" + (detail ?: "（没有更多信息）")

    /**
     * 打开一个入口却连不上时的说明。
     *
     * 为什么本机与远程要分开说：**本机入口的下一步只有一个**（打开 Termux 就会自动拉起 ——
     * 系统允许用户自己启动 Termux，只是不让别的应用把停止状态的 Termux 拉起来），
     * 而远程入口是隧道/PC 那边的事，让用户去开 Termux 只会误伤。
     * 这条文案对应的正是用户看到的那屏 net::ERR_CONNECTION_REFUSED。
     */
    fun loadFailedMessage(endpoint: Endpoint, detail: String?): String = buildString {
        appendLine("连不上 ${endpoint.displayName}。")
        if (!detail.isNullOrBlank()) {
            appendLine("（$detail）")
        }
        appendLine()
        if (endpoint.isLoopback) {
            appendLine("这是手机本地入口，也就是说 Termux 里的 DSH 现在没在跑。")
            appendLine("最常见的原因：系统把 Termux 停掉了（清后台，或者「被别的应用拉起」被自启动策略拦下）。")
            appendLine()
            appendLine("点下面的「打开 Termux」就行 —— 打开 Termux 时会自动把 DSH 拉起来（约十几秒），")
            appendLine("之后回来点「重试」即可。这条路不受自启动策略限制：它不是「被别的应用拉起」。")
        } else {
            appendLine("这是远程入口：请确认 PC 上的 DSH 在跑、隧道/代理还开着、地址没变（IP 会随网络变）。")
            appendLine("细节见「怎么连 PC？」里的说明。")
        }
    }
}
