package app.dsh.mobile.web

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.webkit.CookieManager
import android.webkit.DownloadListener
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import app.dsh.mobile.core.Endpoint
import app.dsh.mobile.core.TokenExchange

/**
 * DSH 专用 WebView 的**全部**复杂度都关在这里：cookie、外链、下载、上传、重新认证。
 *
 * 接口只有三个方法 —— 调用者（Activity）不需要知道 CookieManager、DownloadManager、
 * onShowFileChooser 这类东西的存在。
 */
class DshWebView(
    private val activity: Activity,
    private val webView: WebView,
    private val fileChooser: FileChooserHost,
    private val onReauth: (status: Int) -> Unit,
    private val onProgress: (Int) -> Unit = {},
) {
    /** 需要外部配合的两件事（由 Activity 实现，因为要 startActivityForResult 语义）。 */
    interface FileChooserHost {
        fun openFileChooser(acceptTypes: Array<String>?, onPicked: (Array<Uri>?) -> Unit)
        fun download(url: String, userAgent: String?, mimeType: String?, contentDisposition: String?)
    }

    private var endpoint: Endpoint? = null
    private var triedToken = false

    fun load(target: Endpoint) {
        endpoint = target
        triedToken = false
        configure()
        webView.loadUrl(TokenExchange.initialUrl(target))
    }

    /** 令牌可能过期：清 cookie 后用存着的 token 再交换一次；没有 token 就交给上层提示。 */
    fun reauth() {
        val target = endpoint ?: return
        CookieManager.getInstance().removeAllCookies(null)
        CookieManager.getInstance().flush()
        triedToken = false
        webView.loadUrl(TokenExchange.initialUrl(target))
    }

    fun reload() = webView.reload()

    /** 返回键：优先在网页里后退。 */
    fun handleBack(): Boolean {
        if (!webView.canGoBack()) return false
        webView.goBack()
        return true
    }

    private fun configure() {
        CookieManager.getInstance().setAcceptCookie(true)
        CookieManager.getInstance().setAcceptThirdPartyCookies(webView, false)
        webView.settings.apply {
            javaScriptEnabled = true                 // DSH 前端是 SPA，必须开
            domStorageEnabled = true                 // 前端用 localStorage 存主题/布局
            databaseEnabled = true
            loadsImagesAutomatically = true
            useWideViewPort = true
            loadWithOverviewMode = true
            mediaPlaybackRequiresUserGesture = false
            mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW   // 只用 http，不需要混合内容
            userAgentString = "$userAgentString DshMobile/0.1"
        }
        webView.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                val url = request.url.toString()
                val target = endpoint
                if (target != null && url.startsWith(target.baseUrl)) return false
                // 外链一律交给系统浏览器，别把壳子做成浏览器
                return try {
                    activity.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
                    true
                } catch (_: Exception) {
                    false
                }
            }

            override fun onReceivedHttpError(view: WebView, request: WebResourceRequest, errorResponse: android.webkit.WebResourceResponse) {
                val status = errorResponse.statusCode
                if (!TokenExchange.needsReauth(status)) return
                if (!triedToken && target(endpoint)) {
                    triedToken = true
                    reauth()
                } else {
                    onReauth(status)
                }
            }
        }
        webView.webChromeClient = object : WebChromeClient() {
            override fun onProgressChanged(view: WebView, newProgress: Int) = onProgress(newProgress)

            override fun onShowFileChooser(
                view: WebView,
                filePathCallback: android.webkit.ValueCallback<Array<Uri>>,
                params: FileChooserParams,
            ): Boolean {
                fileChooser.openFileChooser(params.acceptTypes) { picked -> filePathCallback.onReceiveValue(picked) }
                return true
            }
        }
        webView.setDownloadListener(
            DownloadListener { url, userAgent, contentDisposition, mimeType, _ ->
                fileChooser.download(url, userAgent, mimeType, contentDisposition)
            },
        )
    }

    private fun target(endpoint: Endpoint?): Boolean = endpoint != null
}
