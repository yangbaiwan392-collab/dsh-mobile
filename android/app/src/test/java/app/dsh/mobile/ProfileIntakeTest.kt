package app.dsh.mobile

import app.dsh.mobile.core.Endpoint
import app.dsh.mobile.core.Profile
import app.dsh.mobile.core.ProfileIntake
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ProfileIntakeTest {

    private fun endpoint(raw: String) = Endpoint.parse(raw).getOrThrow()

    @Test
    fun `没有同 authority 的条目时按规则起名并新建`() {
        val merged = ProfileIntake.merge(emptyList(), endpoint("http://192.168.0.105:8081/?token=a"))
        assertNotNull(merged)
        assertEquals("远程 192.168.0.105", merged!!.name)
    }

    @Test
    fun `token 没变的重复投递什么都不做`() {
        val e = endpoint("http://127.0.0.1:3080/?token=same")
        val existing = listOf(Profile.create("手机本地", e))
        assertNull(ProfileIntake.merge(existing, e))
    }

    @Test
    fun `DSH 换了 token 时保留用户起的名字与 id，只换 token`() {
        val old = Profile.create("家里电脑", endpoint("http://192.168.0.105:8081/?token=old"))
        val merged = ProfileIntake.merge(listOf(old), endpoint("http://192.168.0.105:8081/?token=new"))
        assertNotNull(merged)
        assertEquals("家里电脑", merged!!.name)
        assertEquals(old.id, merged.id)
        assertEquals("new", merged.endpoint.token)
        assertEquals("http://192.168.0.105:8081", merged.endpoint.baseUrl)
    }

    @Test
    fun `不同端口的同一主机算不同入口`() {
        val existing = listOf(Profile.create("A", endpoint("http://192.168.0.105:8081/?token=x")))
        val merged = ProfileIntake.merge(existing, endpoint("http://192.168.0.105:9999/?token=x"))
        assertNotNull(merged)
        assertTrue(merged!!.id != existing[0].id)
    }
}
