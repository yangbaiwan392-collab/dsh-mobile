package app.dsh.mobile.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 自动命名的回归：同一份列表里，手机本地与远程入口**不能再同名**。
 * 这是真机上发现的（两条都叫「手机本地」，用户分不清）。
 */
class EndpointNamingTest {

    private fun name(raw: String): String {
        val endpoint = Endpoint.parse(raw).getOrThrow()
        return endpoint.suggestedName()
    }

    @Test
    fun `本地回环的三种写法都叫手机本地`() {
        assertEquals(Endpoint.LOCAL_NAME, name("http://127.0.0.1:3080/?token=abc"))
        assertEquals(Endpoint.LOCAL_NAME, name("http://localhost:3080"))
        assertEquals(Endpoint.LOCAL_NAME, name("127.0.0.1:3080"))
        assertEquals(Endpoint.LOCAL_NAME, name("http://[::1]:3080"))
    }

    @Test
    fun `远程入口带上主机名，绝不与本地同名`() {
        val lan = name("http://192.168.0.105:8081/?token=abc")
        assertEquals("${Endpoint.REMOTE_PREFIX} 192.168.0.105", lan)

        val hostname = name("https://nas.local")
        assertEquals("${Endpoint.REMOTE_PREFIX} nas.local", hostname)

        assertFalse(lan == Endpoint.LOCAL_NAME)
        assertFalse(hostname == Endpoint.LOCAL_NAME)
    }

    @Test
    fun `两条不同入口的名字必须不同（这就是当初的 bug）`() {
        val local = name("http://127.0.0.1:3080")
        val remote = name("http://192.168.0.105:8081")
        assertTrue(local != remote)
    }

    @Test
    fun `isLoopback 只看主机，不看端口或 token`() {
        assertTrue(Endpoint.parse("http://127.0.0.1:9/?token=x").getOrThrow().isLoopback)
        assertFalse(Endpoint.parse("http://192.168.1.2:3080").getOrThrow().isLoopback)
    }
}
