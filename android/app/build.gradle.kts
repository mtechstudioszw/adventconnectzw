import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // Apply Firebase / Google services to consume android/app/google-services.json.
    id("com.google.gms.google-services")
    id("com.google.firebase.crashlytics")
}

// Release signing + AdMob app ID come from android/key.properties at
// build time. If the file is missing (typical local dev), we sign
// the release build with the debug key and use Google's sample AdMob
// app ID so `flutter run --release` still works.
//
// See android/key.properties.example for the expected keys.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

val admobAppId: String = (keystoreProperties["admobAndroidAppId"] as String?)
    ?: "ca-app-pub-3940256099942544~3347511713"

android {
    namespace = "io.supabase.adventconnectzw.advent_connect_zw"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Required by flutter_local_notifications for Android API level
        // backports (java.time, etc).
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "io.supabase.adventconnectzw.advent_connect_zw"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // Injected into AndroidManifest.xml via ${admobAppId}.
        manifestPlaceholders["admobAppId"] = admobAppId
    }

    signingConfigs {
        // Pin the debug keystore to a copy in the repo so CI builds
        // produce APKs with the SAME SHA-1 as local builds. This is the
        // SHA-1 registered with Google Cloud for OAuth — without this,
        // every GitHub Actions APK would have a fresh random SHA-1
        // (because the runner has no ~/.android/debug.keystore) and
        // Google Sign-In would fail with DEVELOPER_ERROR (code 10).
        // The debug keystore is NOT secret — passwords are the well-
        // known Android defaults ("android" / "androiddebugkey").
        getByName("debug") {
            storeFile = file("debug.keystore")
            storePassword = "android"
            keyAlias = "androiddebugkey"
            keyPassword = "android"
        }
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                // Falls back to the debug key so dev builds still work.
                // Play Store will reject an upload signed this way — the
                // release script enforces that key.properties exists.
                signingConfigs.getByName("debug")
            }
            // R8 code shrinking + resource shrinking. Cuts APK size
            // by ~30-50%. Keep rules for Flutter, Firebase, Supabase,
            // and UCrop live in android/app/proguard-rules.pro.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Provides Java 8+ APIs (java.time, etc) on older Android versions.
    // Required because flutter_local_notifications uses these APIs.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
