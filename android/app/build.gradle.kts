plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
}
android {
    namespace = "com.tasknotes.app"
    compileSdk = 36
    buildToolsVersion = "36.0.0"
    defaultConfig {
        applicationId = "com.tasknotes.app"
        minSdk = 26
        targetSdk = 36
        versionCode = 1
        versionName = file("../../VERSION").readText().trim()
    }
    signingConfigs { getByName("debug") { storeFile = layout.buildDirectory.file("signing/debug.keystore").get().asFile } }
    compileOptions { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17 }
    kotlinOptions { jvmTarget = "17" }
    buildFeatures { compose = true }
}
dependencyLocking { lockAllConfigurations(); lockMode.set(LockMode.STRICT) }
dependencies {
    implementation(libs.activity.compose)
    implementation(platform(libs.compose.bom))
    implementation(libs.compose.ui)
    implementation(libs.compose.material3)
    testImplementation(libs.junit)
    testImplementation(libs.json)
}
