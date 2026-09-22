package app.dsh.mobile.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class TokenExchangeTest {

    private val withToken = Endpoint.parse("http://127.0.0.1:3080/?token=t0k").getOrThrow()
    private val withoutToken = Endpoint.parse("http://127.0.0.1:3080/").getOrThrow()

    @Test
    fun `first load uses the token when we have one`() {
        assertEquals("http://127.0.0.1:3080/?token=t0k", TokenExchange.initialUrl(withToken))
        assertEquals("http://127.0.0.1:3080/", TokenExchange.initialUrl(withoutToken))
    }

    @Test
    fun `settled means we are on the clean path without a token in the query`() {
        assertTrue(TokenExchange.isSettled("http://127.0.0.1:3080/", withToken))
        assertTrue(TokenExchange.isSettled("http://127.0.0.1:3080/#/session/1", withToken))
        assertFalse(TokenExchange.isSettled("http://127.0.0.1:3080/?token=t0k", withToken))
        assertFalse(TokenExchange.isSettled("http://127.0.0.1:3080/?token=t0k#/x", withToken))
        assertFalse(TokenExchange.isSettled("http://other:3080/", withToken))
    }

    @Test
    fun `only 401 and 403 count as reauth`() {
        assertTrue(TokenExchange.needsReauth(401))
        assertTrue(TokenExchange.needsReauth(403))
        assertFalse(TokenExchange.needsReauth(200))
        assertFalse(TokenExchange.needsReauth(404))
        assertFalse(TokenExchange.needsReauth(500))
    }

    @Test
    fun `retry with token is only possible when a token is stored`() {
        assertTrue(TokenExchange.canRetryWithToken(withToken))
        assertFalse(TokenExchange.canRetryWithToken(withoutToken))
    }
}
