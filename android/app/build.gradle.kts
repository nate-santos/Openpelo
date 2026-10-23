import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use(keystoreProperties::load)
}
val releaseKeystoreConfigured = listOf(
    "keyAlias",
    "keyPassword",
    "storeFile",
    "storePassword",
).all(keystoreProperties::containsKey)

android {
    namespace = "com.doudar.openpelo"
    // Target the latest stable Android release: Android 17 (API 37).
    // Flutter 3.44's flutter.compileSdkVersion / flutter.targetSdkVersion
    // default to API 36, and AGP must be >= 9.1 to compile against API 37
    // (see settings.gradle.kts and the Gradle wrapper), so pin both levels
    // explicitly here instead of inheriting the Flutter defaults.
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.doudar.openpelo"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        // Android 17 (API 37) -- see the note on compileSdk above.
        targetSdk = 37
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (releaseKeystoreConfigured) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            // Produce an unsigned artifact unless key.properties configures a
            // dedicated release key. Never publish a build signed with debug keys.
            signingConfig = signingConfigs.findByName("release")
        }
    }
}

flutter {
    source = "../.."
}
