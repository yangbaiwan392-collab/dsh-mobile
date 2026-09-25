package app.dsh.mobile

import app.dsh.mobile.core.Endpoint
import app.dsh.mobile.core.TermuxStartOutcome
import app.dsh.mobile.core.TermuxStartReport
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 「启动手机上的 DSH」的结论判定。
 *
 * 这组用例锁的是那次真机事故：app 报"已让 Termux 启动"，而 DSH 根本没起来
 * （摩托 DeviceGuard 把 RUN_COMMAND 的 service 启动丢掉了，`startService` 不抛异常）。
 * 所以**端口没探到就必须是 NOT_STARTED**，不能被"请求发出去了"糊弄过去。
 */
class TermuxStartReportTest {

    @Test
    fun `请求发出且端口探到 = 就绪`() {
        assertEquals(
            TermuxStartOutcome.READY,
            TermuxStartReport.classify(requestSent = true, portReachable = true),
        )
    }

    @Test
    fun `请求发出但端口没探到 = 没起来（这是那次谎报成功的场景）`() {
        assertEquals(
            TermuxStartOutcome.NOT_STARTED,
            TermuxStartReport.classify(requestSent = true, portReachable = false),
        )
    }

    @Test
    fun `请求都没发出去 = 请求失败，且优先于端口判定`() {
        assertEquals(
            TermuxStartOutcome.REQUEST_FAILED,
            TermuxStartReport.classify(requestSent = false, portReachable = false),
        )
        // 极端情况：端口恰好有别人在听，也不能算成"我们启动成功了"
        assertEquals(
            TermuxStartOutcome.REQUEST_FAILED,
            TermuxStartReport.classify(requestSent = false, portReachable = true),
        )
    }

    @Test
    fun `只有成功时不给手动兜底按钮`() {
        assertFalse(TermuxStartReport.offersOpenTermux(TermuxStartOutcome.READY))
        assertTrue(TermuxStartReport.offersOpenTermux(TermuxStartOutcome.NOT_STARTED))
        assertTrue(TermuxStartReport.offersOpenTermux(TermuxStartOutcome.REQUEST_FAILED))
    }

    @Test
    fun `没起来的文案要说清原因与下一步，且带上端口和等待时长`() {
        val text = TermuxStartReport.notStartedMessage(port = 3080, waitedSeconds = 90)
        assertTrue("必须点明端口", text.contains("127.0.0.1:3080"))
        assertTrue("必须点明等了多久", text.contains("90 秒"))
        assertTrue("必须提到系统的自启动/关联启动限制", text.contains("自启动") && text.contains("关联启动"))
        assertTrue("必须给出「打开 Termux」这条出路", text.contains("打开 Termux"))
        assertTrue("要给出日志里能验证的判据", text.contains("filterSelfStart"))
    }

    @Test
    fun `请求失败的文案要把真实原因带上`() {
        assertTrue(TermuxStartReport.requestFailedMessage("boom").contains("boom"))
        assertTrue(TermuxStartReport.requestFailedMessage(null).contains("没有更多信息"))
    }

    @Test
    fun `就绪文案给出可点的地址`() {
        assertTrue(TermuxStartReport.readyMessage(3080).contains("127.0.0.1:3080"))
    }

    @Test
    fun `本机入口连不上：给出「打开 Termux」这条出路`() {
        val local = Endpoint.parse("http://127.0.0.1:3080/?token=abc").getOrThrow()
        val text = TermuxStartReport.loadFailedMessage(local, null)
        assertTrue("要点明是手机本地入口", text.contains("手机本地"))
        assertTrue("要指向 Termux", text.contains("打开 Termux"))
        assertTrue("要解释为什么这条路不受限制", text.contains("被别的应用拉起"))
        assertTrue("要带上显示用地址", text.contains(local.displayName))
    }

    @Test
    fun `远程入口连不上：不该让用户去开 Termux，而是指向 PC 侧排查`() {
        val remote = Endpoint.parse("http://192.168.0.102:3080/?token=abc").getOrThrow()
        val text = TermuxStartReport.loadFailedMessage(remote, "WebView 报错")
        assertTrue("要带上真实报错", text.contains("WebView 报错"))
        assertTrue("要指向 PC", text.contains("PC"))
        assertTrue("要提到隧道/代理", text.contains("隧道"))
        assertFalse("远程入口别教用户开 Termux", text.contains("打开 Termux"))
    }
}
