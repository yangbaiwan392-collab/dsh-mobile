package app.dsh.mobile.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class EndpointTest {

    /** 用户最可能的操作：整行粘过来（DSH 启动时打印的那行，带 LAN 尾巴）。 */
    @Test
    fun `parses the whole printed dsh line`() {
        val raw = "dsh web: http://127.0.0.1:3080/?token=abc123 (LAN: http://192.168.0.105:3080/?token=abc123)"
        val ep = Endpoint.parse(raw).getOrThrow()
        assertEquals("http://127.0.0.1:3080", ep.baseUrl)
        assertEquals("abc123", ep.token)
        assertEquals("http://127.0.0.1:3080/?token=abc123", ep.authorizeUrl())
    }

    @Test
    fun `bare host port defaults to http`() {
        val ep = Endpoint.parse("192.168.0.105:8081").getOrThrow()
        assertEquals("http://192.168.0.105:8081", ep.baseUrl)
        assertNull(ep.token)
    }

    @Test
    fun `trailing slashes and empty query normalize to one identity`() {
        val a = Endpoint.parse("http://127.0.0.1:3080/").getOrThrow()
        val b = Endpoint.parse("http://127.0.0.1:3080").getOrThrow()
        val c = Endpoint.parse("http://127.0.0.1:3080/?token=x").getOrThrow()
        assertEquals(a.baseUrl, b.baseUrl)
        assertEquals(a.baseUrl, c.baseUrl)
        assertTrue(a.sameAuthority(c))
        assertEquals("http://127.0.0.1:3080/", a.cleanUrl())
    }

    @Test
    fun `default ports are omitted from baseUrl but https is preserved`() {
        assertEquals("https://dsh.example.com", Endpoint.parse("https://dsh.example.com:443/").getOrThrow().baseUrl)
        assertEquals("http://dsh.example.com:8080", Endpoint.parse("http://dsh.example.com:8080").getOrThrow().baseUrl)
    }

    @Test
    fun `displayName drops the scheme`() {
        assertEquals("127.0.0.1:3080", Endpoint.parse("http://127.0.0.1:3080").getOrThrow().displayName)
    }

    @Test
    fun `rejects empty and hostless input with an actionable message`() {
        assertTrue(Endpoint.parse("   ").exceptionOrNull() is IllegalArgumentException)
        assertTrue(Endpoint.parse("http:///nohost").isFailure)
    }

    @Test
    fun `token is optional and never leaks into baseUrl`() {
        val ep = Endpoint.parse("http://127.0.0.1:3080/?foo=1").getOrThrow()
        assertNull(ep.token)
        assertEquals("http://127.0.0.1:3080/", ep.authorizeUrl())
    }
}
