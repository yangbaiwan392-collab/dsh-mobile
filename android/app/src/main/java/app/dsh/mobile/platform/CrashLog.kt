package app.dsh.mobile.platform

import android.content.Context
import java.io.File
import java.io.PrintWriter
import java.io.StringWriter
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * 崩溃落盘。**为什么需要**：这是台真机 app，第一版就因为清单里漏了
 * `android:name=".DshApp"` 而启动即闪退，而那时手机上没有任何地方能看到原因
 * （图标正常、没有任何提示）。有了它，下次崩溃在 app 里就能看到，不必连电脑抓 logcat。
 *
 * 接口三个方法；写入位置、格式、大小限制都在里面。
 */
object CrashLog {

    private const val RELATIVE_PATH = "crash/last.txt"
    private const val MAX_CHARS = 16_000

    /** 在 Application.onCreate 里调用 —— 必须早于任何 Activity，否则捕不到启动期崩溃。 */
    fun install(context: Context) {
        val appContext = context.applicationContext
        val previous = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, error ->
            runCatching { write(appContext, thread.name, error) }
            previous?.uncaughtException(thread, error)
        }
    }

    /** 最近一次崩溃全文；没有就是 null。 */
    fun last(context: Context): String? =
        file(context).takeIf { it.exists() }?.readText(Charsets.UTF_8)?.takeIf { it.isNotBlank() }

    fun clear(context: Context) {
        runCatching { file(context).delete() }
    }

    private fun file(context: Context) = File(context.filesDir, RELATIVE_PATH)

    private fun write(context: Context, threadName: String, error: Throwable) {
        val stack = StringWriter().also { error.printStackTrace(PrintWriter(it)) }.toString()
        val stamp = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US).format(Date())
        val text = buildString {
            appendLine("时间：$stamp")
            appendLine("线程：$threadName")
            appendLine("异常：${error.javaClass.name}")
            appendLine("信息：${error.message}")
            appendLine()
            append(stack)
        }
        val target = file(context)
        target.parentFile?.mkdirs()
        target.writeText(text.take(MAX_CHARS), Charsets.UTF_8)
    }
}
