package app.dsh.mobile.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class TunnelGuidanceTest {

    @Test
    fun `ssh tunnel command forwards the same loopback port on both ends`() {
        val cmd = TunnelGuidance.sshTunnelCommand("192.168.0.105", "yangy", 3080)
        assertTrue(cmd.contains("-L 127.0.0.1:3080:127.0.0.1:3080"))
        assertTrue(cmd.endsWith("yangy@192.168.0.105"))
    }

    @Test
    fun `proxy command matches the shipped script's flags`() {
        val cmd = TunnelGuidance.proxyCommand(8081, 3080)
        assertEquals(true, cmd.contains("loopback-proxy.mjs"))
        assertTrue(cmd.contains("--listen 0.0.0.0:8081"))
        assertTrue(cmd.contains("--target 127.0.0.1:3080"))
    }

    @Test
    fun `termux tunnel command delegates to the shipped script`() {
        assertTrue(TunnelGuidance.termuxTunnelCommand("10.0.0.2", "me", 3080).startsWith("bash tunnel-to-pc.sh 10.0.0.2 me 3080"))
    }

    @Test
    fun `risk notes always mention the plaintext cookie problem`() {
        val notes = TunnelGuidance.riskNotes()
        assertTrue(notes.isNotEmpty())
        assertTrue(notes.any { it.contains("Secure") })
        assertTrue(notes.any { it.contains("127.0.0.1") })
    }
}
