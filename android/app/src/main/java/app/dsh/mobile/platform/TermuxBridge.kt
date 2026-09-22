package app.dsh.mobile.platform

import android.content.Context
import android.content.Intent

/**
 * 模式 A 的"帮我在手机上把 DSH 起起来"。
 *
 * 接口只有两个方法；Termux 的 intent 细节（extras 名字、service 类名、需要
 * allow-external-apps）全部关在里面。失败时给出**用户能照做**的原因。
 */
class TermuxBridge(private val context: Context) {

    fun isTermuxInstalled(): Boolean = try {
        context.packageManager.getPackageInfo(TERMUX_PACKAGE, 0)
        true
    } catch (_: Exception) {
        false
    }

    /**
     * 触发 Termux 跑 `termux/start-dsh.sh`。
     * 脚本跑完会用 `am start -e dsh_url …` 把入口地址回传给本 app（见 termux/start-dsh.sh）。
     */
    fun startLocalDsh(scriptPath: String = DEFAULT_SCRIPT_PATH): Result<Unit> {
        if (!isTermuxInstalled()) {
            return Result.failure(IllegalStateException("没检测到 Termux。请先装 F-Droid 版 Termux（Play 版已废弃）。"))
        }
        val intent = Intent("com.termux.RUN_COMMAND").apply {
            setClassName(TERMUX_PACKAGE, "$TERMUX_PACKAGE.app.RunCommandService")
            putExtra("com.termux.RUN_COMMAND_PATH", TERMUX_BASH)
            putExtra("com.termux.RUN_COMMAND_ARGUMENTS", arrayOf(scriptPath))
            putExtra("com.termux.RUN_COMMAND_WORKDIR", TERMUX_HOME)
            putExtra("com.termux.RUN_COMMAND_BACKGROUND", true)
        }
        return try {
            context.startService(intent)
            Result.success(Unit)
        } catch (e: Exception) {
            Result.failure(IllegalStateException("Termux 拒绝执行：请在 Termux 里确认 ~/.termux/termux.properties 打开了 allow-external-apps=true"))
        }
    }

    /** 判据文案也放这里，UI 直接显示，避免两处不一致。 */
    fun manualSteps(): List<String> = listOf(
        "装 F-Droid 版 Termux",
        "把 termux/ 两个脚本放到 $TERMUX_SCRIPT_DIR",
        "Termux 里跑： bash $DEFAULT_SCRIPT_PATH",
        "复制它打印的入口地址，回到本 app「添加入口」",
    )

    companion object {
        const val TERMUX_PACKAGE = "com.termux"
        private const val TERMUX_HOME = "/data/data/com.termux/files/home"
        private const val TERMUX_BASH = "/data/data/com.termux/files/usr/bin/bash"
        const val TERMUX_SCRIPT_DIR = "$TERMUX_HOME/dsh-android"
        const val DEFAULT_SCRIPT_PATH = "$TERMUX_SCRIPT_DIR/start-dsh.sh"
    }
}
