package app.dsh.mobile.ui

import android.app.DownloadManager
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.net.Uri
import android.os.Bundle
import android.view.Menu
import android.view.MenuItem
import android.view.View
import android.webkit.WebView
import android.widget.ProgressBar
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import app.dsh.mobile.DshApp
import app.dsh.mobile.R
import app.dsh.mobile.core.Endpoint
import app.dsh.mobile.core.TermuxStartReport
import app.dsh.mobile.platform.TermuxBridge
import app.dsh.mobile.web.DshWebView
import com.google.android.material.appbar.MaterialToolbar
import com.google.android.material.dialog.MaterialAlertDialogBuilder

/**
 * 壳子的主屏：一个全屏 WebView。**只有装配代码** —— WebView 的复杂度在 [DshWebView]，
 * URL/token 的语义在 core，这里只把它们接起来。
 */
class WebActivity : AppCompatActivity(), DshWebView.FileChooserHost {

    private lateinit var shell: DshWebView
    private lateinit var webView: WebView
    private lateinit var progress: ProgressBar
    private var pendingFileCallback: ((Array<Uri>?) -> Unit)? = null
    private var endpoint: Endpoint? = null

    /**
     * 上次主文档加载失败了（连不上）。
     *
     * 用来做「去打开 Termux → 回到本页自动重试一次」：用户点完「打开 Termux」这个对话框就关了，
     * 回来时如果什么都不做，他手里就只剩一屏 err_connection_refused（真机走一遍才发现）。
     * 只在**确实失败过**时才自动重试，成功后不再打扰（成功路径由 onResume 清掉它）。
     */
    private var loadFailed = false

    private val pickFiles = registerForActivityResult(ActivityResultContracts.OpenMultipleDocuments()) { uris ->
        pendingFileCallback?.invoke(uris?.takeIf { it.isNotEmpty() }?.toTypedArray())
        pendingFileCallback = null
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_web)

        progress = findViewById(R.id.progress)
        webView = findViewById(R.id.webview)

        val profile = intent.getStringExtra(Nav.EXTRA_PROFILE_ID)?.let { id ->
            (application as DshApp).profileStore.load().firstOrNull { it.id == id }
        }
        if (profile == null) {
            toast(getString(R.string.toast_profile_missing))
            finish()
            return
        }
        endpoint = profile.endpoint

        findViewById<MaterialToolbar>(R.id.toolbar).apply {
            title = profile.name
            subtitle = profile.endpoint.displayName
            setNavigationOnClickListener { finish() }
        }
        // 不设 ActionBar 的话 onCreateOptionsMenu 永远不会被调用（菜单会静默消失）
        setSupportActionBar(findViewById<MaterialToolbar>(R.id.toolbar))

        shell = DshWebView(
            activity = this,
            webView = webView,
            fileChooser = this,
            onReauth = { status -> toast(getString(R.string.toast_reauth_failed, status)) },
            onProgress = { value ->
                progress.progress = value
                progress.visibility = if (value in 1..99) View.VISIBLE else View.GONE
            },
            onLoadFailed = { failed ->
                loadFailed = true
                showLoadFailed(failed)
            },
        )
        shell.load(profile.endpoint)
    }

    /**
     * 主文档连不上 —— 别把 WebView 自带那屏 `net::ERR_CONNECTION_REFUSED` 丢给用户。
     *
     * 本机入口的下一步是确定的：打开 Termux 就会把 DSH 拉起来（~/.bashrc 里的钩子），
     * 而且这条路不受"自启动策略"限制（用户自己启动 ≠ 被别的应用拉起）。
     * 远程入口则给隧道/PC 的排查方向（文案在 core/TermuxStartReport 里，有单测）。
     */
    private fun showLoadFailed(target: Endpoint) {
        val builder = MaterialAlertDialogBuilder(this)
            .setTitle(R.string.web_load_failed_title)
            .setMessage(TermuxStartReport.loadFailedMessage(target, null))
            .setPositiveButton(R.string.action_retry) { _, _ -> shell.reload() }
            .setNegativeButton(android.R.string.cancel, null)
        if (target.isLoopback) {
            builder.setNeutralButton(R.string.action_open_termux) { _, _ ->
                if (TermuxBridge(this).openTermux()) {
                    toast(getString(R.string.toast_termux_opening))
                } else {
                    toast(getString(R.string.toast_open_termux_failed))
                }
            }
        }
        builder.show()
    }

    override fun onCreateOptionsMenu(menu: Menu): Boolean {
        menu.add(0, MENU_REAUTH, 0, R.string.action_reauth)
        menu.add(0, MENU_COPY, 1, R.string.action_copy_url)
        return true
    }

    override fun onOptionsItemSelected(item: MenuItem): Boolean = when (item.itemId) {
        android.R.id.home -> {
            finish(); true
        }
        MENU_REAUTH -> {
            shell.reauth(); true
        }
        MENU_COPY -> {
            val clip = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
            clip.setPrimaryClip(ClipData.newPlainText("dsh", endpoint?.baseUrl.orEmpty()))
            toast(getString(R.string.toast_url_copied))
            true
        }
        else -> super.onOptionsItemSelected(item)
    }

    @Deprecated("Deprecated in Java")
    override fun onBackPressed() {
        if (!shell.handleBack()) super.onBackPressed()
    }

    override fun onResume() {
        super.onResume()
        webView.onResume()
        // 回到本页：上次连不上就自动重试一次（典型场景：用户刚按提示去打开了 Termux）
        if (loadFailed) {
            loadFailed = false
            shell.reload()
        }
    }

    override fun onPause() {
        webView.onPause()
        super.onPause()
    }

    // ---- DshWebView.FileChooserHost：需要 Activity 能力的两件事 ----

    override fun openFileChooser(acceptTypes: Array<String>?, onPicked: (Array<Uri>?) -> Unit) {
        pendingFileCallback = onPicked
        // 注意：filter 返回 List，直接跟 arrayOf(...) 用 ?: 会退化成 Any
        val accepted = acceptTypes.orEmpty().filter { it.isNotBlank() }.toTypedArray()
        pickFiles.launch(if (accepted.isNotEmpty()) accepted else arrayOf("*/*"))
    }

    override fun download(url: String, userAgent: String?, mimeType: String?, contentDisposition: String?) {
        try {
            val request = DownloadManager.Request(Uri.parse(url)).apply {
                setMimeType(mimeType)
                setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
                setDestinationInExternalPublicDir(android.os.Environment.DIRECTORY_DOWNLOADS, android.webkit.URLUtil.guessFileName(url, contentDisposition, mimeType))
                if (userAgent != null) addRequestHeader("User-Agent", userAgent)
                // cookie 必须带上，否则 DSH 的文件下载会 401
                android.webkit.CookieManager.getInstance().getCookie(url)?.let { addRequestHeader("Cookie", it) }
            }
            (getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager).enqueue(request)
            toast(getString(R.string.toast_download_started))
        } catch (e: Exception) {
            toast(getString(R.string.toast_download_failed, e.message ?: ""))
        }
    }

    private fun toast(text: String) = Toast.makeText(this, text, Toast.LENGTH_LONG).show()

    private companion object {
        const val MENU_REAUTH = 1
        const val MENU_COPY = 2
    }
}
