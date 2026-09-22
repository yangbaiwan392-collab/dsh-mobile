package app.dsh.mobile.core

/**
 * token → cookie 交换的**决策**部分（纯逻辑，好测）。
 *
 * DSH 的契约（读 dsh-client-connection 源码得到）：
 *  · 只有 `GET /` 接受 `?token=`，交换成功后写一个绑 hostname+port 的签名 cookie，并 302 到干净的 `/`；
 *  · cookie 缺失/过期/authority 不符 → 401；
 *  · 静态资源是公开的，所以"能取到 JS"不代表"已登录"。
 *
 * 这一层只回答三个问题，WebView 那边照做即可。
 */
object TokenExchange {

    /** 第一次该加载哪个 URL（有 token 就带，没 token 就赌已有 cookie）。 */
    fun initialUrl(endpoint: Endpoint): String =
        if (endpoint.token.isNullOrBlank()) endpoint.cleanUrl() else endpoint.authorizeUrl()

    /** 是否已经落到"干净地址"（说明交换完成、或者本来就不需要交换）。 */
    fun isSettled(currentUrl: String, endpoint: Endpoint): Boolean {
        val clean = endpoint.cleanUrl()
        if (!currentUrl.startsWith(clean)) return false
        return !currentUrl.substring(clean.length).contains("token=")
    }

    /** 服务端要求重新认证 —— 401/403 都算（403 是 browser-trust 栅栏，换 token 或换地址才对）。 */
    fun needsReauth(httpStatus: Int): Boolean = httpStatus == 401 || httpStatus == 403

    /** 重新认证时要不要重新用一次 token（token 还在就再试一次，否则只能提示用户）。 */
    fun canRetryWithToken(endpoint: Endpoint): Boolean = !endpoint.token.isNullOrBlank()
}
