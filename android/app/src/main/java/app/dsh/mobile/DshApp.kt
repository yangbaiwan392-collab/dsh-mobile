package app.dsh.mobile

import android.app.Application
import app.dsh.mobile.core.FileProfileStore
import app.dsh.mobile.core.ProfileStore
import app.dsh.mobile.platform.CrashLog
import java.io.File

/**
 * Application 是 Android 里唯一合理的"进程级单例"位置。
 * 只做两件启动期的事：装崩溃记录、提供入口档案存储。**不放业务逻辑**。
 *
 * ⚠ 这个类必须由清单里的 `android:name=".DshApp"` 挂上 ——
 *   漏掉它会让每个 Activity 里的 `(application as DshApp)` 抛 ClassCastException（v0.1.0 就是这么闪退的），
 *   所以有 ManifestContractTest 看着这件事。
 */
class DshApp : Application() {

    val profileStore: ProfileStore by lazy {
        FileProfileStore(File(filesDir, "profiles.json"))
    }

    override fun onCreate() {
        super.onCreate()
        CrashLog.install(this)
    }
}
