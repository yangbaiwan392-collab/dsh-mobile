package app.dsh.mobile.core

/**
 * 从**剪贴板**里认出 Termux 交给我们的东西。
 *
 * 为什么需要这条通道：Android 10+ 禁止**后台应用启动别的应用的 Activity** ——
 * 真机上实测 `ActivityTaskManager: Background activity launch blocked! [callingPackage: com.termux]`，
 * 于是 termux 脚本里的 `am start -e dsh_url/dsh_diag …` 会被系统拦掉（Termux 在前台时才成功）。
 * 而**写剪贴板不受此限制**，前台应用**读**剪贴板也只要自己的窗口有焦点 —— 所以：
 *   Termux（写）→ 剪贴板 → 本 app（读）
 * 这条路不依赖任何后台启动特权，且脚本早就在写入口地址了（Termux:API 的 termux-clipboard-set）。
 */
object ClipboardIntake {

    /** 自检报告的开头（Termux 侧生成，见 TermuxCommand.diagnostics）——用它把报告与普通文本区分开。 */
    const val DIAG_HEADER = "DSH 手机端 · 环境自检"

    sealed interface Payload {
        /** DSH 打印的入口（整行也行，只要里面有带 token 的 URL）。 */
        data class EndpointLine(val raw: String) : Payload

        /** 环境自检报告。 */
        data class Diag(val report: String) : Payload
    }

    /** 认不出来就返回 null（避免把用户剪贴板里的无关内容当成入口）。 */
    fun classify(text: String?): Payload? {
        val trimmed = text?.trim().orEmpty()
        if (trimmed.isEmpty()) return null
        if (trimmed.startsWith(DIAG_HEADER)) return Payload.Diag(trimmed)
        if (!trimmed.contains("http")) return null
        // 必须真的能解析成入口，且看起来"是给我们的"：
        // 要么带 token（DSH 启动输出就是这个形态），要么指向本机/内网 IP。
        val endpoint = Endpoint.parse(trimmed).getOrNull() ?: return null
        val looksOurs = trimmed.contains("token=") || endpoint.isLoopback || IPV4.containsMatchIn(endpoint.host)
        return if (looksOurs) Payload.EndpointLine(trimmed) else null
    }

    private val IPV4 = Regex("""^\d{1,3}(\.\d{1,3}){3}$""")
}
