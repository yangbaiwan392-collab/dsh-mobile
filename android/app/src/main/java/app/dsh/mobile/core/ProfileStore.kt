package app.dsh.mobile.core

import org.json.JSONArray
import org.json.JSONObject

/**
 * 入口档案的持久化。**接口很小，实现承担全部复杂度**（原子写、损坏回退、字段缺失容忍）。
 *
 * 两个适配器（文件 / 内存）→ 这是**真 seam**，不是假想的：单测用内存实现跑逻辑，
 * 文件实现自己也有测试（临时目录 + 损坏文件回退）。
 */
interface ProfileStore {
    fun load(): List<Profile>

    /** 同 authority 覆盖，否则追加。返回写入后的完整列表（结果，不是副作用）。 */
    fun upsert(profile: Profile): List<Profile>

    fun remove(id: String): List<Profile>
}

/** 内存实现：单测用，也是"清单为空"的默认回退。 */
class InMemoryProfileStore(initial: List<Profile> = emptyList()) : ProfileStore {
    private var items: List<Profile> = initial

    override fun load(): List<Profile> = items

    override fun upsert(profile: Profile): List<Profile> {
        items = items.filterNot { it.matchesEndpoint(profile.endpoint) || it.id == profile.id } + profile
        return items
    }

    override fun remove(id: String): List<Profile> {
        items = items.filterNot { it.id == id }
        return items
    }
}

/**
 * 文件实现：一个 JSON 数组。写入走 **临时文件 + rename**（断电/被杀不会留半个文件）；
 * 读失败（损坏、被手改坏）**返回空表而不是崩** —— 档案丢了可以重建，app 起不来不行。
 */
class FileProfileStore(private val file: java.io.File) : ProfileStore {

    override fun load(): List<Profile> {
        if (!file.exists()) return emptyList()
        return try {
            decode(file.readText(Charsets.UTF_8))
        } catch (e: Exception) {
            quarantine()
            emptyList()
        }
    }

    override fun upsert(profile: Profile): List<Profile> {
        val next = InMemoryProfileStore(load()).upsert(profile)
        persist(next)
        return next
    }

    override fun remove(id: String): List<Profile> {
        val next = InMemoryProfileStore(load()).remove(id)
        persist(next)
        return next
    }

    private fun persist(items: List<Profile>) {
        file.parentFile?.mkdirs()
        val tmp = java.io.File(file.parentFile, file.name + ".tmp")
        tmp.writeText(encode(items), Charsets.UTF_8)
        if (!tmp.renameTo(file)) {           // 同目录 rename 在 Android 上也是原子的
            file.writeText(encode(items), Charsets.UTF_8)
            tmp.delete()
        }
    }

    /** 把坏文件挪到 .bad，留证据但不挡住启动。 */
    private fun quarantine() {
        try {
            file.renameTo(java.io.File(file.parentFile, file.name + ".bad"))
        } catch (_: Exception) {
        }
    }

    companion object {
        fun encode(items: List<Profile>): String {
            val array = JSONArray()
            items.forEach { p ->
                array.put(
                    JSONObject()
                        .put("id", p.id)
                        .put("name", p.name)
                        .put("url", p.endpoint.baseUrl)
                        .put("token", p.endpoint.token ?: JSONObject.NULL),
                )
            }
            return array.toString(2)
        }

        fun decode(text: String): List<Profile> {
            val array = JSONArray(text)
            val out = ArrayList<Profile>(array.length())
            for (i in 0 until array.length()) {
                val obj = array.optJSONObject(i) ?: continue
                val url = obj.optString("url")
                if (url.isBlank()) continue      // 不用 ifBlank { continue }：inline lambda 里的 continue 是实验特性
                val token = if (obj.isNull("token")) null else obj.optString("token").ifBlank { null }
                val parsed = Endpoint.parse(if (token == null) url else "$url/?token=$token").getOrNull() ?: continue
                val name = obj.optString("name").ifBlank { parsed.displayName }
                val id = obj.optString("id").ifBlank { java.util.UUID.randomUUID().toString() }
                out += Profile(id, name, parsed)
            }
            return out
        }
    }
}
