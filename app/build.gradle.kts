plugins {
    id("com.android.application")
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

configurations.all {
    resolutionStrategy {
        // AGP 9's built-in Kotlin compiler ships as 2.2.x. Last attempt at
        // built-in Kotlin (v0.4.7) failed because some dependency pulled in
        // kotlin-stdlib 2.4.10 transitively and Gradle's normal "highest
        // wins" resolution picked that over what we declared — the compiler
        // then couldn't read its own metadata format. force() overrides
        // that resolution instead of just adding another candidate version.
        force("org.jetbrains.kotlin:kotlin-stdlib:2.2.10")
    }
}

dependencies {
    implementation("org.mozilla.geckoview:geckoview:154.0.20260814215756")
    implementation("androidx.core:core-ktx:1.16.0")
    implementation("androidx.appcompat:appcompat:1.7.1")
    implementation("com.google.android.material:material:1.13.0")
    implementation("androidx.constraintlayout:constraintlayout:2.2.1")
    implementation("androidx.recyclerview:recyclerview:1.4.0")
}
