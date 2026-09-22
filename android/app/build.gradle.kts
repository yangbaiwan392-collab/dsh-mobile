import org.gradle.api.tasks.PathSensitivity
import org.gradle.api.tasks.testing.Test

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
}

// ManifestContractTest 在**运行时**读清单与构建脚本做契约检查；
// 不把这两个文件声明成输入，改了清单 Gradle 会认为测试 up-to-date 而跳过 —— 守卫静默失效。
// （这不是理论问题：v0.1.0 的闪退就是这么从守卫底下溜过去的。）
tasks.withType<Test>().configureEach {
    inputs.file("src/main/AndroidManifest.xml").withPathSensitivity(PathSensitivity.RELATIVE)
    inputs.file("build.gradle.kts").withPathSensitivity(PathSensitivity.RELATIVE)
}

android {
    namespace = "app.dsh.mobile"
    // platform-35 已在本机 SDK 里就位；build-tools 固定 34.0.0（镜像上只有 r34）
    compileSdk = 35
    buildToolsVersion = "34.0.0"

    defaultConfig {
        applicationId = "app.dsh.mobile"
        // 用户手机是 Android 13+：把下限抬到 33，省掉一半兼容分支（少分支 = 少屎山）
        minSdk = 33
        targetSdk = 35
        versionCode = 3
        versionName = "0.1.3"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    // 签名密钥固定进工程（tools\make-debug-keystore.ps1 生成）：
    // AGP 默认那把 ~/.android/debug.keystore 的生效时间 = 构建那一刻，手机时钟稍早就会被
    // 判为"证书尚未生效"→ 安装报签名错误；而且它在仓库外，被重建一次所有升级都会签名不一致。
    signingConfigs {
        getByName("debug") {
            storeFile = rootProject.file("signing/debug.keystore")
            storePassword = "android"
            keyAlias = "androiddebugkey"
            keyPassword = "android"
        }
    }

    buildTypes {
        debug {
            signingConfig = signingConfigs.getByName("debug")
        }
        release {
            isMinifyEnabled = false
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }

    testOptions {
        unitTests.isReturnDefaultValues = true
    }
}

dependencies {
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.appcompat)
    implementation(libs.androidx.recyclerview)
    implementation(libs.material)

    testImplementation(libs.junit)
    testImplementation(libs.json.test)
}
