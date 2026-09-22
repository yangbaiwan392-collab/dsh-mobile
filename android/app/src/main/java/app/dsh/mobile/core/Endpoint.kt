package app.dsh.mobile.core

/**
 * 一个 DSH 入口（值对象）。只经 [Endpoint.parse] 构造，构造后不可变。
 *
 * 它吃掉的全部复杂度（调用者不用知道）：
 *  · 用户粘贴的可能是**整行启动输出**（`dsh web: http://127.0.0.1:3080/?token=… (LAN: …)`），
 *    也可能是裸 URL、带不带尾斜杠、带不带 token、http 还是 https；
 *  · DSH 的契约是 **token 只允许用于根 URL 交换**（之后靠 cookie），所以 token 要从 URL 里**摘出来**单独存；
 *  · baseUrl 必须规范化成 `scheme://host[:port]`，因为 cookie 绑定 hostname+port，多一个斜杠就换一个身份。
 */
data class Endpoint private constructor(
    val scheme: String,
    val host: String,
    val port: Int,
    val token: String?,
) {
    /** `http://host:port` —— 无尾斜杠、无 query。cookie 身份就绑在这个字符串上。 */
    val baseUrl: String
        get() = if (port == defaultPort(scheme)) "$scheme://$host" else "$scheme://$host:$port"

    /** 列表里显示的名字：去掉 scheme，保留端口。 */
    val displayName: String get() = baseUrl.substringAfter("://")

    /** 首次加载用：带 token 的根 URL（DSH 只在这里接受 token）。 */
    fun authorizeUrl(): String =
        if (token.isNullOrBlank()) "$baseUrl/" else "$baseUrl/?token=$token"

    /** 交换完成后浏览器应该停在的干净地址。 */
    fun cleanUrl(): String = "$baseUrl/"

    /** 同一台机器同一端口才算同一个入口（token 变了不算换入口）。 */
    fun sameAuthority(other: Endpoint): Boolean = baseUrl == other.baseUrl

    companion object {
        private const val PRINTED_PREFIX = "dsh web:"
        private const val LAN_MARKER = "(LAN:"

        private fun defaultPort(scheme: String) = if (scheme == "https") 443 else 80

        /**
         * 解析用户能提供的任何形态。失败时给出**能照着改**的中文原因。
         */
        fun parse(raw: String): Result<Endpoint> {
            val text = normalizeInput(raw)
            if (text.isEmpty()) return Result.failure(IllegalArgumentException("请粘贴 DSH 的入口地址"))

            val withScheme = if (text.startsWith("http://") || text.startsWith("https://")) text else "http://$text"
            val uri = try {
                java.net.URI(withScheme)
            } catch (e: Exception) {
                return Result.failure(IllegalArgumentException("地址格式不对：$text"))
            }
            val scheme = uri.scheme?.lowercase()
            if (scheme != "http" && scheme != "https") {
                return Result.failure(IllegalArgumentException("只支持 http/https，收到：$scheme"))
            }
            val host = uri.host
            if (host.isNullOrBlank()) {
                return Result.failure(IllegalArgumentException("地址里没有主机名：$text"))
            }
            val port = if (uri.port > 0) uri.port else defaultPort(scheme)
            return Result.success(Endpoint(scheme, host, port, tokenFrom(uri.rawQuery)))
        }

        /** 摘掉启动输出里的前缀与 LAN 尾巴，只留第一个 URL。 */
        private fun normalizeInput(raw: String): String =
            raw.trim()
                .removePrefix(PRINTED_PREFIX)
                .trim()
                .substringBefore(LAN_MARKER)
                .trim()
                .trim('"', '\'', '<', '>')

        /** `token=abc&x=1` → `abc`；没有就是 null。 */
        private fun tokenFrom(rawQuery: String?): String? =
            rawQuery
                ?.split('&')
                ?.firstOrNull { it.startsWith("token=") }
                ?.substringAfter("token=")
                ?.takeIf { it.isNotBlank() }
    }
}
