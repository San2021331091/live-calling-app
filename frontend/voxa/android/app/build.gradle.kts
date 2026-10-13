plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Allow local builds before Firebase is configured. FCM stays unavailable until
// this project's google-services.json is supplied and the app is rebuilt.
if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
}

android {
    namespace = "com.example.voxa"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
        // DISABLE treating warnings as errors
        allWarningsAsErrors = false
    }

    defaultConfig {
        applicationId = "com.example.voxa"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    // Optional: apply to all Kotlin compile tasks (extra safety)
    tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
        kotlinOptions {
            allWarningsAsErrors = false
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Match the Media3 version used by video_player_android.
    implementation("androidx.media3:media3-transformer:1.9.2")
    implementation("androidx.media3:media3-effect:1.9.2")
}
