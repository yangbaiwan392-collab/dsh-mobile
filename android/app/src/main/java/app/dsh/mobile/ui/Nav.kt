package app.dsh.mobile.ui

import android.content.Context
import android.content.Intent

/**
 * 页面之间的**契约**集中在这里：extras 的键名与工厂方法只有一处。
 * 这样就没有"某个 Activity 里手写字符串键、另一个里写错一个字母"的经典事故。
 */
object Nav {
    const val EXTRA_PROFILE_ID = "profile_id"
    const val EXTRA_DSH_URL = "dsh_url"
    const val EXTRA_DIAG = "dsh_diag"

    fun openWeb(context: Context, profileId: String): Intent =
        Intent(context, WebActivity::class.java).putExtra(EXTRA_PROFILE_ID, profileId)

    fun newProfile(context: Context): Intent =
        Intent(context, EditProfileActivity::class.java)

    fun editProfile(context: Context, profileId: String): Intent =
        Intent(context, EditProfileActivity::class.java).putExtra(EXTRA_PROFILE_ID, profileId)

    /** Termux 侧 `am start -e dsh_url <url>` 落下来的入口地址。 */
    fun endpointFrom(intent: Intent?): String? =
        intent?.getStringExtra(EXTRA_DSH_URL)?.takeIf { it.isNotBlank() }

    /** Termux 侧 `am start -e dsh_diag <report>` 回传的环境自检报告。 */
    fun diagFrom(intent: Intent?): String? =
        intent?.getStringExtra(EXTRA_DIAG)?.takeIf { it.isNotBlank() }
}
