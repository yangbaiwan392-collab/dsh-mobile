package app.dsh.mobile.ui

import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.view.View
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import app.dsh.mobile.DshApp
import app.dsh.mobile.R
import app.dsh.mobile.core.Endpoint
import app.dsh.mobile.core.Profile
import app.dsh.mobile.core.TunnelGuidance
import app.dsh.mobile.platform.CrashLog
import app.dsh.mobile.platform.TermuxBridge
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import com.google.android.material.floatingactionbutton.FloatingActionButton

/** 入口列表页：显示 / 打开 / 长按管理 / 接收 Termux 回传的地址。所有判断都在 core 里。 */
class MainActivity : AppCompatActivity() {

    private val store by lazy { (application as DshApp).profileStore }
    private lateinit var adapter: ProfileAdapter
    private lateinit var empty: View

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        empty = findViewById(R.id.empty)
        adapter = ProfileAdapter(
            onClick = { startActivity(Nav.openWeb(this, it.id)) },
            onLongClick = { showActions(it) },
        )
        findViewById<RecyclerView>(R.id.list).apply {
            layoutManager = LinearLayoutManager(this@MainActivity)
            adapter = this@MainActivity.adapter
        }
        findViewById<FloatingActionButton>(R.id.add).setOnClickListener { startActivity(Nav.newProfile(this)) }
        findViewById<View>(R.id.start_local).setOnClickListener { startLocalDsh() }
        findViewById<View>(R.id.how_to_connect).setOnClickListener { showConnectGuide() }

        handleIncomingEndpoint(intent)
        showLastCrashIfAny()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIncomingEndpoint(intent)
    }

    override fun onResume() {
        super.onResume()
        refresh()
    }

    /** Termux 侧 `am start -e dsh_url <url>` 会走到这里：解析成功就直接存成入口。 */
    private fun handleIncomingEndpoint(intent: Intent?) {
        val raw = Nav.endpointFrom(intent) ?: return
        Endpoint.parse(raw)
            .onSuccess { endpoint ->
                store.upsert(Profile.create(getString(R.string.default_profile_name), endpoint))
                toast(getString(R.string.toast_endpoint_added, endpoint.displayName))
            }
            .onFailure { toast(getString(R.string.toast_endpoint_invalid, it.message ?: "")) }
    }

    private fun refresh() {
        val items = store.load()
        adapter.submitList(items)
        empty.visibility = if (items.isEmpty()) View.VISIBLE else View.GONE
    }

    /**
     * 上次崩过就摊开给用户看 —— 手机上不用连电脑也能拿到原因。
     * 复制按钮是为了让用户能把日志发给我；清除按钮避免它每次都弹。
     */
    private fun showLastCrashIfAny() {
        val log = CrashLog.last(this) ?: return
        MaterialAlertDialogBuilder(this)
            .setTitle(R.string.crash_title)
            .setMessage(log.take(4000))
            .setPositiveButton(R.string.crash_copy) { _, _ ->
                val clip = getSystemService(Context.CLIPBOARD_SERVICE) as android.content.ClipboardManager
                clip.setPrimaryClip(android.content.ClipData.newPlainText("dsh-crash", log))
                toast(getString(R.string.crash_copied))
            }
            .setNegativeButton(R.string.crash_clear) { _, _ -> CrashLog.clear(this) }
            .setNeutralButton(android.R.string.cancel, null)
            .show()
    }

    private fun showActions(profile: Profile) {
        MaterialAlertDialogBuilder(this)
            .setTitle(profile.name)
            .setItems(arrayOf(getString(R.string.action_edit), getString(R.string.action_delete))) { _, which ->
                when (which) {
                    0 -> startActivity(Nav.editProfile(this, profile.id))
                    else -> {
                        store.remove(profile.id)
                        refresh()
                    }
                }
            }
            .show()
    }

    private fun startLocalDsh() {
        val bridge = TermuxBridge(this)
        val message = bridge.startLocalDsh()
            .fold(
                onSuccess = { getString(R.string.toast_termux_launched) },
                onFailure = { error ->
                    // 失败时别只说"失败"：把手动步骤列出来
                    (error.message ?: "") + "\n\n" + bridge.manualSteps().joinToString("\n") { "· $it" }
                },
            )
        MaterialAlertDialogBuilder(this)
            .setTitle(R.string.action_start_local)
            .setMessage(message)
            .setPositiveButton(android.R.string.ok, null)
            .show()
    }

    private fun showConnectGuide() {
        val body = buildString {
            appendLine(getString(R.string.guide_remote_intro))
            appendLine()
            appendLine("SSH 隧道（推荐）：")
            appendLine(TunnelGuidance.sshTunnelCommand("<PC 的 IP>", "<PC 用户名>", 3080))
            appendLine()
            appendLine("免管理员代理（明文，仅家里 Wi-Fi）：")
            appendLine(TunnelGuidance.proxyCommand(8081, 3080))
            appendLine()
            TunnelGuidance.riskNotes().forEach { appendLine("· $it") }
        }
        MaterialAlertDialogBuilder(this)
            .setTitle(R.string.guide_remote_title)
            .setMessage(body)
            .setPositiveButton(android.R.string.ok, null)
            .show()
    }

    private fun toast(text: String) = Toast.makeText(this, text, Toast.LENGTH_LONG).show()
}
