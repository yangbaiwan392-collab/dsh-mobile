package app.dsh.mobile.platform

import java.net.InetSocketAddress
import java.net.Socket

/**
 * 「本机 DSH 到底起没起来」的**唯一可靠判据**：那个端口有没有人在监听。
 *
 * 为什么不信 intent：`Context.startService()` 对"被系统丢掉"和"成功"一视同仁 ——
 * 摩托的自启动限制就是这么把 app 骗过去的（见 core/TermuxStartReport 的说明）。
 * 探一个回环端口既便宜又不依赖 DSH 的鉴权状态（401 也算在跑）。
 *
 * 线程约束：TCP 连接属于网络 IO，**必须在非主线程**调用，否则抛 NetworkOnMainThreadException。
 */
object LocalDshProbe {

    /** 单次探测。回环连接正常是毫秒级，所以超时给得很短，失败就是真的没在听。 */
    fun isReachable(host: String = "127.0.0.1", port: Int, timeoutMs: Int = 800): Boolean = try {
        Socket().use { it.connect(InetSocketAddress(host, port), timeoutMs) }
        true
    } catch (_: Exception) {
        false
    }

    /**
     * 轮询等待，直到探到端口或超时。
     *
     * @param totalMs 总预算。默认 90 秒：已装好的路径通常十几秒；
     *   首次安装（Node + 编译 node-pty + wasm sharp）要好几分钟 —— 那种情况用户该看的是
     *   Termux 窗口里的进度，而不是 app 的等待框，所以不把预算放得更大。
     * @param onTick 每轮没探到时的回调（给 UI 顺手做点事，例如读一次剪贴板里的回传地址）。
     * @return 探到端口时返回"距开始过了多少毫秒"；一直没探到返回 null。
     */
    fun awaitReachable(
        host: String = "127.0.0.1",
        port: Int,
        totalMs: Long = 90_000,
        intervalMs: Long = 2_000,
        onTick: (elapsedMs: Long) -> Unit = {},
    ): Long? {
        val start = System.currentTimeMillis()
        while (true) {
            if (isReachable(host, port)) return System.currentTimeMillis() - start
            val elapsed = System.currentTimeMillis() - start
            if (elapsed >= totalMs) return null
            onTick(elapsed)
            Thread.sleep(intervalMs)
        }
    }
}
