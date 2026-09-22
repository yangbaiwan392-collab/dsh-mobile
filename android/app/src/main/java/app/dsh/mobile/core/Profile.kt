package app.dsh.mobile.core

/**
 * 只有数据、没有行为的入口档案。token 单独存（它跟 URL 的生命周期不一样：
 * URL 是长期身份，token 每次 dsh 重启都会换）。
 */
data class Profile(
    val id: String,
    val name: String,
    val endpoint: Endpoint,
) {
    /** 存盘/回读的稳定性判据：同一 authority 视为同一个入口。 */
    fun matchesEndpoint(other: Endpoint): Boolean = endpoint.sameAuthority(other)

    companion object {
        fun create(name: String, endpoint: Endpoint): Profile =
            Profile(id = java.util.UUID.randomUUID().toString(), name = name.ifBlank { endpoint.displayName }, endpoint = endpoint)
    }
}
