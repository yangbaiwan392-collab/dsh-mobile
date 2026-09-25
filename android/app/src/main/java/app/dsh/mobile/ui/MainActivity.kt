package app.dsh.mobile.ui

import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.view.Menu
import android.view.MenuItem
import android.view.View
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import app.dsh.mobile.DshApp
import app.dsh.mobile.R
import app.dsh.mobile.core.Endpoint
import app.dsh.mobile.core.Profile
import app.dsh.mobile.core.TermuxCommand
import app.dsh.mobile.core.TermuxStartOutcome
import app.dsh.mobile.core.TermuxStartReport
import app.dsh.mobile.core.TunnelGuidance
import app.dsh.mobile.platform.CrashLog
import app.dsh.mobile.platform.LocalDshProbe
import app.dsh.mobile.platform.TermuxBridge
import com.google.android.material.appbar.MaterialToolbar
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import com.google.android.material.floatingactionbutton.FloatingActionButton

/** 入口列表页：显示 / 打开 / 长按管理 / 接收 Termux 回传的地址。所有判断都在 core 里。 */
class MainActivity : AppCompatActivity() {

    private val store by lazy { (application as DshApp).profileStore }
    private lateinit var adapter: ProfileAdapter
    private lateinit var empty: View

    /** 同一份自检报告只弹一次。**要持久化**：剪贴板会一直留着它，否则每次冷启动都弹一遍。 */
    private var lastDiagShown: String?
        get() = prefs.getString(KEY_LAST_DIAG, null)
        set(value) = prefs.edit().putString(KEY_LAST_DIAG, value).apply()

    private val prefs by lazy { getSharedPreferences("dsh-mobile", MODE_PRIVATE) }

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
        // 空状态里那两个按钮一旦有了入口就看不见了 —— 真机验证时发现的缺口，所以同时在工具栏菜单里给一份
        setSupportActionBar(findViewById<MaterialToolbar>(R.id.toolbar))

        handleIncomingEndpoint(intent)
        Nav.diagFrom(intent)?.let(::showDiagnostics)
        showLastCrashIfAny()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIncomingEndpoint(intent)
        Nav.diagFrom(intent)?.let(::showDiagnostics)
    }

    /** 工具栏菜单：与空状态里那两个按钮等价，保证任何时候都能用。 */
    override fun onCreateOptionsMenu(menu: Menu): Boolean {
        menu.add(0, MENU_START_LOCAL, 0, R.string.action_start_local)
        menu.add(0, MENU_DIAGNOSTICS, 1, R.string.action_diagnostics)
        menu.add(0, MENU_CONNECT_GUIDE, 2, R.string.action_how_to_connect)
        return true
    }

    override fun onOptionsItemSelected(item: MenuItem): Boolean = when (item.itemId) {
        MENU_START_LOCAL -> {
            startLocalDsh(); true
        }
        MENU_DIAGNOSTICS -> {
            runDiagnostics(); true
        }
        MENU_CONNECT_GUIDE -> {
            showConnectGuide(); true
        }
        else -> super.onOptionsItemSelected(item)
    }

    override fun onResume() {
        super.onResume()
        refresh()
    }

    /**
     * 剪贴板要在**拿到窗口焦点之后**读：Android 10+ 拒绝非焦点应用读剪贴板，
     * 冷启动时 onResume 早于焦点，会读到 null（真机踩过：token 更新没生效）。
     */
    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) maybeHandleClipboard()
    }

    /**
     * 剪贴板通道：Termux 侧写进去的入口/自检报告在这里被认出来。
     * 判据（认不出就什么都不做）在 core/ClipboardIntake，UI 只负责搬运。
     */
    private fun maybeHandleClipboard() {
        val clip = getSystemService(Context.CLIPBOARD_SERVICE) as android.content.ClipboardManager
        val text = clip.primaryClip?.getItemAt(0)?.coerceToText(this)?.toString()
        val payload = app.dsh.mobile.core.ClipboardIntake.classify(text)
        // 一行日志：剪贴板通道出问题时（读到 null / 认不出）能一眼看出来，不用猜
        android.util.Log.d(
            "dsh-clipboard",
            "read=${text?.length ?: -1} classified=${payload?.javaClass?.simpleName ?: "none"}",
        )
        when (payload) {
            is app.dsh.mobile.core.ClipboardIntake.Payload.EndpointLine -> {
                val endpoint = Endpoint.parse(payload.raw).getOrNull() ?: return
                // 并进列表的规则（含"token 换了但保留用户起的名字"）在 core/ProfileIntake
                val merged = app.dsh.mobile.core.ProfileIntake.merge(store.load(), endpoint) ?: return
                store.upsert(merged)
                refresh()
                toast(getString(R.string.toast_endpoint_added, endpoint.displayName))
            }
            is app.dsh.mobile.core.ClipboardIntake.Payload.Diag -> {
                if (payload.report == lastDiagShown) return
                lastDiagShown = payload.report
                showDiagnostics(payload.report)
            }
            null -> Unit
        }
    }

    /** Termux 侧 `am start -e dsh_url <url>` 会走到这里：解析成功就直接存成入口。 */
    private fun handleIncomingEndpoint(intent: Intent?) {
        val raw = Nav.endpointFrom(intent) ?: return
        Endpoint.parse(raw)
            .onSuccess { endpoint ->
                // 名字按"是手机本地还是远程"自动区分，避免两条入口同名（真机踩过）；
                // token 变化时保留用户改过的名字（规则在 core/ProfileIntake）
                app.dsh.mobile.core.ProfileIntake.merge(store.load(), endpoint)?.let { store.upsert(it) }
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

    /**
     * 一次点击的完整动作：请求 Termux 启动 → **实测端口** → 按实测结果说话。
     *
     * 这里的三段是被真机教出来的（摩托 XT2611-1 / Android 16）：
     *   ① `startService` 不抛异常 ≠ 请求送达 —— DeviceGuard 会把 intent 直接丢掉，
     *      所以以前那句"已让 Termux 启动本地 DSH"是**谎报**；
     *   ② 唯一可靠判据是 `127.0.0.1:<port>` 有没有人在听（见 core/TermuxStartReport）；
     *   ③ 探活是网络 IO，必须离开主线程；同时用 UI 线程轮询剪贴板接收 Termux 回传的地址。
     */
    private fun startLocalDsh() {
        val bridge = TermuxBridge(this)
        // 缺 Termux 的执行权限时先申请一次（它是 Termux 定义的运行时权限，
        // adb 装的包不会自动拿到 —— 真机的 Permission Denial 就是这么来的）
        if (bridge.isTermuxInstalled() && !bridge.hasRunCommandPermission()) {
            requestPermissions(arrayOf(TermuxBridge.RUN_COMMAND_PERMISSION), REQ_RUN_COMMAND)
            return
        }
        val result = bridge.installAndStart()
        if (result.isFailure) {
            showStartResult(
                TermuxStartReport.requestFailedMessage(result.exceptionOrNull()?.message) +
                    "\n\n" + bridge.manualSteps().joinToString("\n") { s -> "· $s" },
                TermuxStartOutcome.REQUEST_FAILED,
                bridge,
            )
            return
        }

        val pending = MaterialAlertDialogBuilder(this)
            .setTitle(R.string.action_start_local)
            .setMessage(getString(R.string.start_local_pending))
            .setCancelable(false)
            .setNegativeButton(android.R.string.cancel, null)
            .create()
        pending.show()

        Thread {
            val elapsed = LocalDshProbe.awaitReachable(port = TermuxCommand.LOCAL_PORT) {
                // 顺手收 Termux 回传的地址（后台启动 Activity 会被系统拦，剪贴板是可靠通道）
                window.decorView.post { maybeHandleClipboard() }
            }
            runOnUiThread {
                if (isFinishing || isDestroyed) return@runOnUiThread
                pending.dismiss()
                val outcome = TermuxStartReport.classify(requestSent = true, portReachable = elapsed != null)
                val message = if (outcome == TermuxStartOutcome.READY) {
                    maybeHandleClipboard()
                    TermuxStartReport.readyMessage(TermuxCommand.LOCAL_PORT)
                } else {
                    TermuxStartReport.notStartedMessage(
                        TermuxCommand.LOCAL_PORT,
                        ((elapsed ?: AWAIT_LOCAL_DSH_MS) / 1000).toInt(),
                    )
                }
                showStartResult(message, outcome, bridge)
            }
        }.start()
    }

    /** 把结论摊给用户：成功就一句，失败必须同时给出「打开 Termux」这条手动出路。 */
    private fun showStartResult(message: String, outcome: TermuxStartOutcome, bridge: TermuxBridge) {
        val builder = MaterialAlertDialogBuilder(this)
            .setTitle(R.string.action_start_local)
            .setMessage(message)
            .setPositiveButton(android.R.string.ok, null)
        if (TermuxStartReport.offersOpenTermux(outcome)) {
            builder.setNeutralButton(R.string.action_open_termux) { _, _ ->
                if (!bridge.openTermux()) toast(getString(R.string.toast_open_termux_failed))
            }
        }
        builder.show()
    }

    /** 权限申请回来后：拿到了就接着启动，没拿到就把话说清楚。 */
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != REQ_RUN_COMMAND) return
        if (grantResults.isNotEmpty() && grantResults[0] == android.content.pm.PackageManager.PERMISSION_GRANTED) {
            startLocalDsh()
        } else {
            toast(getString(R.string.toast_run_command_denied))
        }
    }

    /** 环境自检：结果由 Termux 写进剪贴板（见 maybeHandleClipboard），这里点完主动轮询几次。 */
    private fun runDiagnostics() {
        TermuxBridge(this).runDiagnostics().onFailure {
            toast(it.message ?: "自检没能启动")
            return
        }
        // 脚本要跑几秒；用户此刻还停在本页，不会触发 onResume，所以自己轮询
        repeat(6) { i ->
            window.decorView.postDelayed({ maybeHandleClipboard() }, 1500L * (i + 1))
        }
    }

    /** Termux 回传的自检报告：可复制，方便贴给别人看。 */
    private fun showDiagnostics(report: String) {
        MaterialAlertDialogBuilder(this)
            .setTitle(R.string.action_diagnostics)
            .setMessage(report)
            .setPositiveButton(R.string.crash_copy) { _, _ ->
                val clip = getSystemService(Context.CLIPBOARD_SERVICE) as android.content.ClipboardManager
                clip.setPrimaryClip(android.content.ClipData.newPlainText("dsh-diag", report))
                toast(getString(R.string.crash_copied))
            }
            .setNegativeButton(android.R.string.ok, null)
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

    private companion object {
        const val MENU_START_LOCAL = 1
        const val MENU_CONNECT_GUIDE = 2
        const val MENU_DIAGNOSTICS = 3
        const val REQ_RUN_COMMAND = 1001
        const val KEY_LAST_DIAG = "last_diag_report"

        /** 等本地 DSH 起来的总预算，与 ui 里那句提示文案保持一致（已装好的通常十几秒）。 */
        const val AWAIT_LOCAL_DSH_MS = 90_000L
    }
}
