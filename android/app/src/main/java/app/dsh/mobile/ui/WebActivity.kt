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
import app.dsh.mobile.web.DshWebView
import com.google.android.material.appbar.MaterialToolbar

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
        )
        shell.load(profile.endpoint)
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
