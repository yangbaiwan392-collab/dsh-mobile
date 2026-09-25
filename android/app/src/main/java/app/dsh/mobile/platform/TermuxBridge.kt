package app.dsh.mobile.platform

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import app.dsh.mobile.core.TermuxCommand

/**
 * 模式 A 的"帮我在手机上把 DSH 起起来"。
 *
 * 接口很小；Termux 的 intent 细节（extras 名字、service 类名、allow-external-apps）
 * 与"脚本内容怎么送过去"全部关在里面。失败时给出**用户能照做**的原因。
 *
 * 脚本不再需要用户手动拷进手机：它们**在 APK 的 assets 里**（构建时从仓库 termux/ 同步），
 * app 现场用带引号的 heredoc 写进 Termux 家目录再执行 —— 一次点击，零文件搬运。
 */
class TermuxBridge(private val context: Context) {

    fun isTermuxInstalled(): Boolean = try {
        context.packageManager.getPackageInfo(TERMUX_PACKAGE, 0)
        true
    } catch (_: Exception) {
        false
    }

    /**
     * Termux 的 `com.termux.permission.RUN_COMMAND` 是**由 Termux 定义的运行时权限**，
     * 必须被授予才能启动它的 RunCommandService。真机上踩到过：
     *   `Permission Denial: Accessing service com.termux/.app.RunCommandService … requires com.termux.permission.RUN_COMMAND`
     * 用 `adb install`（不带 -g）装的包不会自动拿到它 —— 用户手动装时系统会弹授权框。
     * 所以这里要能**查**，UI 据此决定"先申请一次"还是直接调。
     */
    fun hasRunCommandPermission(): Boolean =
        context.checkSelfPermission(RUN_COMMAND_PERMISSION) == PackageManager.PERMISSION_GRANTED

    /** 一次点击的完整动作：写脚本 → 缺 DSH 就装、有就直接启动。幂等，可反复点。 */
    fun installAndStart(): Result<Unit> = runBash(
        TermuxCommand.installAndStart(SCRIPT_FILES.associateWith { readAsset(it) })
    )

    /** 环境自检：跑完会把报告用 `am start -e dsh_diag …` 回传给本 app（见 MainActivity）。 */
    fun runDiagnostics(): Result<Unit> = runBash(
        TermuxCommand.diagnostics(context.packageName, DIAG_ACTIVITY)
    )

    /**
     * 打开 Termux 的界面 —— 系统自启动限制的**手动兜底**。
     *
     * 摩托的 DeviceGuard 拦的是"Termux 从停止状态被别的应用拉起"；**用户手动点开是另一条路**，
     * 而且 Termux 一旦在前台跑起来，它导出的 RUN_COMMAND 服务就能被正常调用（真机实证）。
     * `TermuxActivity` 是 Termux 的启动器 Activity（带 LAUNCHER 过滤器 → 必然导出），
     * 所以这里不需要额外权限，失败只可能是 Termux 被卸载/被禁用。
     */
    fun openTermux(): Boolean = try {
        context.startActivity(
            Intent().apply {
                setClassName(TERMUX_PACKAGE, "$TERMUX_PACKAGE.app.TermuxActivity")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
        )
        true
    } catch (_: Exception) {
        false
    }

    /** 兼容旧路径：只启动、不写脚本（用户已按 docs/01 自己放过脚本时仍可用）。 */
    fun startLocalDsh(scriptPath: String = DEFAULT_SCRIPT_PATH): Result<Unit> =
        runBash(null, arrayOf(scriptPath))

    /**
     * @param body 非空时以 `bash -c <body>` 执行（脚本内容作为**一个参数**传入，
     *   Termux 直接交给 exec，不再经 shell 解析，所以正文里的引号/换行都安全）。
     * @param args 直接作为 bash 的参数列表执行。
     */
    private fun runBash(body: String?, args: Array<String>? = null): Result<Unit> {
        if (!isTermuxInstalled()) {
            return Result.failure(
                IllegalStateException("没检测到 Termux。请先装 F-Droid 版 Termux（Play 版已废弃）。")
            )
        }
        if (!hasRunCommandPermission()) {
            return Result.failure(
                IllegalStateException(
                    "缺少 Termux 的执行权限（com.termux.permission.RUN_COMMAND）。" +
                        "本 app 这就去申请一次；若系统没弹框，把它卸掉重装一次即可（手动安装时系统会列出来让你同意）。"
                )
            )
        }
        val arguments = if (body != null) arrayOf("-c", body) else args ?: arrayOf()
        val intent = Intent(ACTION_RUN_COMMAND).apply {
            setClassName(TERMUX_PACKAGE, "$TERMUX_PACKAGE.app.RunCommandService")
            putExtra("com.termux.RUN_COMMAND_PATH", TERMUX_BASH)
            putExtra("com.termux.RUN_COMMAND_ARGUMENTS", arguments)
            putExtra("com.termux.RUN_COMMAND_WORKDIR", TERMUX_HOME)
            putExtra("com.termux.RUN_COMMAND_BACKGROUND", true)
            putExtra("com.termux.RUN_COMMAND_COMMAND_LABEL", "DSH 手机端")
        }
        return try {
            context.startService(intent)
            Result.success(Unit)
        } catch (e: Exception) {
            // 把真实异常类型带出来：上次就是"甩锅给 allow-external-apps"而真因是权限，白绕一轮
            Result.failure(
                IllegalStateException(
                    "Termux 没接住请求：${e.javaClass.simpleName}: ${e.message}\n" +
                        "常见原因：① 缺 com.termux.permission.RUN_COMMAND（重装本 app 时同意即可）" +
                        " ② Termux 的 allow-external-apps=true 没开"
                )
            )
        }
    }

    private fun readAsset(name: String): String =
        context.assets.open("termux/$name").bufferedReader().use { it.readText() }

    /** 判据文案也放这里，UI 直接显示，避免两处不一致。 */
    fun manualSteps(): List<String> = listOf(
        "装 F-Droid 版 Termux + Termux:API",
        "打开 Termux 的 allow-external-apps=true（或直接点本页的「启动手机上的 DSH」由 app 代劳）",
        "首次安装需要几分钟（Node / 编译 node-pty / wasm 版 sharp）",
        "跑完 Termux 会把入口地址回传，本 app 自动建档「手机本地」",
    )

    companion object {
        const val TERMUX_PACKAGE = "com.termux"
        const val RUN_COMMAND_PERMISSION = "com.termux.permission.RUN_COMMAND"
        private const val ACTION_RUN_COMMAND = "com.termux.RUN_COMMAND"
        private const val DIAG_ACTIVITY = "app.dsh.mobile.ui.MainActivity"
        private const val TERMUX_HOME = "/data/data/com.termux/files/home"
        private const val TERMUX_BASH = "/data/data/com.termux/files/usr/bin/bash"
        const val TERMUX_SCRIPT_DIR = "$TERMUX_HOME/dsh-android"
        const val DEFAULT_SCRIPT_PATH = "$TERMUX_SCRIPT_DIR/start-dsh.sh"

        /** 这些文件必须都在 APK assets 的 termux/ 下（构建脚本会检查 APK 里是否真的有）。 */
        val SCRIPT_FILES = listOf(
            "setup-dsh.sh",
            "start-dsh.sh",
            "tunnel-to-pc.sh",
            "fix-android-runtime.sh",
            "repair-termux.sh",
        )
    }
}
