package app.dsh.mobile

import app.dsh.mobile.core.ClipboardIntake
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 剪贴板通道的判据：**宁可什么都不做，也不能把用户剪贴板里的无关内容当成入口。**
 * 这条通道存在的原因见 ClipboardIntake 的注释（Android 拦后台应用启动 Activity）。
 */
class ClipboardIntakeTest {

    @Test
    fun `认得出 DSH 打印的整行入口`() {
        val line = "dsh web: http://127.0.0.1:3080/?token=abc123 (LAN: http://192.168.0.104:3080/?token=abc123)"
        val payload = ClipboardIntake.classify(line)
        assertTrue(payload is ClipboardIntake.Payload.EndpointLine)
        assertEquals(line, (payload as ClipboardIntake.Payload.EndpointLine).raw)
    }

    @Test
    fun `认得出裸的带 token 地址`() {
        assertTrue(ClipboardIntake.classify("http://192.168.0.105:8081/?token=xyz") is ClipboardIntake.Payload.EndpointLine)
    }

    @Test
    fun `认得出自检报告`() {
        val report = ClipboardIntake.DIAG_HEADER + "\n时间：2026-09-22 23:20\n[1] 家目录：/data/..."
        val payload = ClipboardIntake.classify(report)
        assertTrue(payload is ClipboardIntake.Payload.Diag)
    }

    @Test
    fun `剪贴板里的无关内容一律不认`() {
        assertNull(ClipboardIntake.classify(null))
        assertNull(ClipboardIntake.classify(""))
        assertNull(ClipboardIntake.classify("   "))
        assertNull(ClipboardIntake.classify("今天下午三点开会"))
        assertNull(ClipboardIntake.classify("https://example.com/some/page"))
        assertNull(ClipboardIntake.classify("http://nas.local/"))          // 不是 IP、没 token、非 loopback
        assertNull(ClipboardIntake.classify("token=abc"))                  // 有 token 但没有 URL
    }
}
