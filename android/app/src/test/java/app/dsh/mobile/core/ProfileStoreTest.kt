package app.dsh.mobile.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class ProfileStoreTest {

    @get:Rule
    val tmp = TemporaryFolder()

    private fun ep(url: String, token: String? = null) =
        Endpoint.parse(if (token == null) url else "$url/?token=$token").getOrThrow()

    @Test
    fun `upsert replaces the same authority instead of duplicating it`() {
        val store = InMemoryProfileStore()
        store.upsert(Profile("a", "本机", ep("http://127.0.0.1:3080", "t1")))
        val after = store.upsert(Profile("b", "本机新 token", ep("http://127.0.0.1:3080", "t2")))
        assertEquals(1, after.size)
        assertEquals("t2", after.single().endpoint.token)
    }

    @Test
    fun `different authorities coexist and remove works by id`() {
        val store = InMemoryProfileStore()
        store.upsert(Profile("a", "本地", ep("http://127.0.0.1:3080")))
        val two = store.upsert(Profile("b", "家里 PC", ep("http://192.168.0.105:8081")))
        assertEquals(2, two.size)
        assertEquals(1, store.remove("a").size)
    }

    @Test
    fun `file store round-trips through disk`() {
        val file = tmp.newFile("profiles.json")
        val store = FileProfileStore(file)
        store.upsert(Profile("a", "本机", ep("http://127.0.0.1:3080", "tok")))
        store.upsert(Profile("b", "PC", ep("http://192.168.0.105:8081", null)))

        val reloaded = FileProfileStore(file).load()
        assertEquals(2, reloaded.size)
        assertEquals("tok", reloaded.first { it.name == "本机" }.endpoint.token)
        assertEquals("http://192.168.0.105:8081", reloaded.first { it.name == "PC" }.endpoint.baseUrl)
    }

    @Test
    fun `a corrupt file is quarantined and reported as empty instead of crashing startup`() {
        val file = tmp.newFile("profiles.json")
        file.writeText("{ this is not json")
        val store = FileProfileStore(file)

        assertEquals(emptyList<Profile>(), store.load())
        assertTrue(java.io.File(file.parentFile, file.name + ".bad").exists())
    }

    @Test
    fun `decoding tolerates missing id name and token`() {
        val decoded = FileProfileStore.decode("""[{"url":"http://127.0.0.1:3080"}]""")
        assertEquals(1, decoded.size)
        assertEquals("127.0.0.1:3080", decoded.single().name)
        assertTrue(decoded.single().id.isNotBlank())
    }

    @Test
    fun `decoding skips entries without a usable url`() {
        assertEquals(0, FileProfileStore.decode("""[{"id":"x"},{"url":""},{"url":"not a url"}]""").size)
    }
}
