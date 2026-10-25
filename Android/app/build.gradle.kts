plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.veylo.player"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.veylo.player"
        minSdk = 21
        targetSdk = 34
        versionCode = 8
        versionName = "0.3.5"
        // Phones and TV boxes (most boxes are 32-bit ARM).
        ndk { abiFilters += listOf("armeabi-v7a", "arm64-v8a") }
    }

    // One fixed key (made by the workflow, kept in the Actions cache — never in this repo), so
    // every new APK installs over the previous one. Local builds fall back to the debug key.
    val keystore = System.getenv("VEYLO_KEYSTORE")?.let { file(it) }?.takeIf { it.exists() }
    signingConfigs {
        if (keystore != null) {
            create("veylo") {
                storeFile = keystore
                storePassword = "veylo-android"
                keyAlias = "veylo"
                keyPassword = "veylo-android"
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            signingConfig = if (keystore != null) signingConfigs.getByName("veylo") else signingConfigs.getByName("debug")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
    buildFeatures { compose = true; buildConfig = true }
    composeOptions { kotlinCompilerExtensionVersion = "1.5.14" }
    packaging { resources { excludes += "/META-INF/{AL2.0,LGPL2.1}" } }
}

dependencies {
    implementation(platform("androidx.compose:compose-bom:2024.06.00"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.foundation:foundation")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-core")
    implementation("androidx.activity:activity-compose:1.9.0")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.2")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1")
    implementation("io.coil-kt:coil-compose:2.6.0")
    // Same engine as the iPhone app (MobileVLCKit): VLC.
    implementation("org.videolan.android:libvlc-all:3.5.1")
}
