package app.dsh.mobile.core

/**
 * "收到一个入口"该怎么并进现有列表 —— 三条判断，放这里是为了能单测（UI 只负责搬运）。
 *
 * 来历（都是真机上想清楚的）：
 *  · DSH 每次启动都会换 token，所以"同一台机器同一个端口"的入口会**反复**被交过来；
 *  · 但用户可能给入口改过名（「家里电脑」），自动收下**不能**把名字重置成「远程 192.168.0.105」；
 *  · token 没变的重复投递**不该**有任何动作（Termux 每次启动都会写一遍剪贴板）。
 */
object ProfileIntake {

    /**
     * @return 需要写入的档案；`null` = 与现有内容一致，什么都不用做。
     */
    fun merge(existing: List<Profile>, endpoint: Endpoint): Profile? {
        val same = existing.firstOrNull { it.endpoint.sameAuthority(endpoint) }
            ?: return Profile.create(endpoint.suggestedName(), endpoint)
        if (same.endpoint.token == endpoint.token) return null
        // 同 authority：换掉 endpoint（token/地址），**保留 id 与用户起的名字**
        return same.copy(endpoint = endpoint)
    }
}
