// 根构建脚本只声明插件，具体配置在 :app 里。
plugins {
    alias(libs.plugins.android.application) apply false
    alias(libs.plugins.kotlin.android) apply false
}
