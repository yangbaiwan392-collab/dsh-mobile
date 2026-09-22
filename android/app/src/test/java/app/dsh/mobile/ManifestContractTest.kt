package app.dsh.mobile

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * 清单契约测试：把**只有真机能暴露的静态错误**挪到单测里。
 *
 * 来历：v0.1.0 在手机上启动即闪退，原因是 `<application>` 漏了 `android:name=".DshApp"`，
 * 于是每个 Activity 里的 `(application as DshApp)` 抛 ClassCastException。
 * 构建、lint、单元测试全绿 —— 因为它们都不看这件事。
 */
class ManifestContractTest {

    // Gradle 跑单测时的工作目录就是模块目录（app/）
    private val moduleDir = File(".").absoluteFile
    private val manifest = File(moduleDir, "src/main/AndroidManifest.xml").readText(Charsets.UTF_8)
    private val namespace = Regex("""namespace\s*=\s*"([^"]+)"""")
        .find(File(moduleDir, "build.gradle.kts").readText(Charsets.UTF_8))
        ?.groupValues?.get(1)
        ?: error("build.gradle.kts 里找不到 namespace")

    @Test
    fun `application node names our Application class`() {
        val applicationTag = Regex("<application[^>]*>", RegexOption.DOT_MATCHES_ALL).find(manifest)?.value
            ?: error("清单里没有 <application>")
        assertTrue(
            "清单的 <application> 必须写 android:name=\".DshApp\"，否则 (application as DshApp) 会在启动时抛 ClassCastException",
            applicationTag.contains("android:name=\".DshApp\""),
        )
    }

    @Test
    fun `run-command permission and termux visibility are declared`() {
        // 缺权限声明 → 真机上 `Permission Denial: Accessing service
        // com.termux/.app.RunCommandService … requires com.termux.permission.RUN_COMMAND`（踩过）。
        // 缺 <queries> → Android 11+ 看不见 Termux，装机检测恒为 false。
        assertTrue(
            "必须声明 Termux 的 RUN_COMMAND 权限，否则「启动手机上的 DSH」会被系统拒绝",
            manifest.contains("com.termux.permission.RUN_COMMAND"),
        )
        assertTrue(
            "必须在 <queries> 里声明 com.termux，否则检测不到 Termux 是否安装",
            Regex("<queries>.*?<package\\s+android:name=\"com\\.termux\"", RegexOption.DOT_MATCHES_ALL).containsMatchIn(manifest),
        )
    }

    @Test
    fun `every relative android name maps to a real source file`() {
        val names = Regex("""android:name="\.([A-Za-z0-9_.]+)"""").findAll(manifest).map { it.groupValues[1] }
        val missing = names.filterNot { relative ->
            val path = relative.replace('.', '/')
            File(moduleDir, "src/main/java/${namespace.replace('.', '/')}/$path.kt").exists() ||
                File(moduleDir, "src/main/java/${namespace.replace('.', '/')}/$path.java").exists()
        }.toList()
        assertEquals("这些 android:name 在源码里找不到对应类：$missing", emptyList<String>(), missing)
    }

    @Test
    fun `the namespace matches the applicationId so relative names resolve`() {
        val applicationId = Regex("""applicationId\s*=\s*"([^"]+)"""")
            .find(File(moduleDir, "build.gradle.kts").readText(Charsets.UTF_8))?.groupValues?.get(1)
        assertEquals("namespace 与 applicationId 必须一致，否则清单里的相对类名会解析到别的包", applicationId, namespace)
    }

    @Test
    fun `declared screens exist`() {
        val screens = listOf(".ui.MainActivity", ".ui.EditProfileActivity", ".ui.WebActivity")
        screens.forEach { assertTrue("清单里少了 $it", manifest.contains("android:name=\"$it\"")) }
    }
}
