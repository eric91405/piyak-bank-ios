plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}
android {
    namespace = "com.minseo.piyakbank.wear"
    compileSdk = 36
    defaultConfig {
        applicationId = "com.minseo.piyakbank"
        minSdk = 30
        targetSdk = 35
        versionCode = 1000001
        versionName = "1.0.0"
    }
    signingConfigs {
        create("upload") {
            val keyPath = providers.environmentVariable("PIYAK_KEYSTORE").orNull
            if (keyPath != null) {
                storeFile = file(keyPath)
                storePassword = providers.environmentVariable("PIYAK_STORE_PASSWORD").orNull
                keyAlias = providers.environmentVariable("PIYAK_KEY_ALIAS").orNull
                keyPassword = providers.environmentVariable("PIYAK_KEY_PASSWORD").orNull
            }
        }
    }
    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"))
            if (providers.environmentVariable("PIYAK_KEYSTORE").isPresent) signingConfig = signingConfigs.getByName("upload")
        }
    }
    compileOptions { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17 }
    kotlinOptions { jvmTarget = "17" }
    buildFeatures { compose = true }
    sourceSets.getByName("main") {
        java.srcDir("../app/src/main/java/com/minseo/piyakbank/scene")
        assets.srcDir("../app/src/main/assets")
    }
    lint { abortOnError = true; checkReleaseBuilds = true }
}
dependencies {
    implementation(platform("androidx.compose:compose-bom:2025.10.01"))
    implementation("androidx.activity:activity-compose:1.11.0")
    implementation("androidx.fragment:fragment:1.8.9")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.9.4")
    implementation("com.google.android.gms:play-services-wearable:19.0.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-play-services:1.10.2")
    testImplementation("junit:junit:4.13.2")
}
