plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.playvibemusic.vibe"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    signingConfigs {
        create("release") {
            val ksPath = System.getenv("CM_KEYSTORE_PATH")
            if (ksPath != null) {
                storeFile     = file(ksPath)
                storePassword = System.getenv("CM_KEYSTORE_PASSWORD") ?: ""
                keyAlias      = System.getenv("CM_KEY_ALIAS")         ?: ""
                keyPassword   = System.getenv("CM_KEY_PASSWORD")      ?: ""
            }
        }
    }

    defaultConfig {
        applicationId = "com.playvibemusic.vibe"
        minSdk        = flutter.minSdkVersion
        targetSdk     = flutter.targetSdkVersion
        versionCode   = flutter.versionCode
        versionName   = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = if (System.getenv("CM_KEYSTORE_PATH") != null)
                signingConfigs.getByName("release")
            else
                signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
