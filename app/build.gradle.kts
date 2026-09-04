plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.nexus.browser"
    compileSdk = 37

    defaultConfig {
        applicationId = "com.nexus.browser"
        minSdk = 26
        targetSdk = 37
        versionCode = 4
        versionName = "0.4.0"

        ndk {
            abiFilters += listOf("arm64-v8a", "armeabi-v7a", "x86_64")
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
        }
        debug {
            isDebuggable = true
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlin {
        jvmToolchain(17)
    }

    buildFeatures {
        viewBinding = true
    }
}

dependencies {
    // Explizit gepinnt, damit keine transitive Abhängigkeit (z.B. GeckoView)
    // eine neuere stdlib reinzieht, die der Kotlin-Compiler nicht mehr lesen kann.
    implementation("org.jetbrains.kotlin:kotlin-stdlib:2.2.10")
    implementation("org.mozilla.geckoview:geckoview:154.0.20260814215756")
    implementation("androidx.core:core-ktx:1.16.0")
    implementation("androidx.appcompat:appcompat:1.7.1")
    implementation("com.google.android.material:material:1.13.0")
    implementation("androidx.constraintlayout:constraintlayout:2.2.1")
    implementation("androidx.recyclerview:recyclerview:1.4.0")
}
