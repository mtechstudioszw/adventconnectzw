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

// Release signing comes from android/key.properties at build time.
// If the file is missing (typical local dev), we sign the release
// build with the debug key so `flutter run --release` still works
// for development. AAB uploads to Play require a real upload key.
//
// See android/key.properties.example for the expected keys.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "io.supabase.adventconnectzw.advent_connect_zw"
    compileSdk = flutter.compileSdkVersion
    // Pin NDK r27+ — its toolchain links native (.so) libraries with a 16 KB
    // max page size by default, which is required for Android 15's 16 KB memory
    // pages (Google Play "16 KB page sizes" requirement). Flutter's default NDK
    // can be older, so set it explicitly.
    // 28.2.13676358, raised from 27.0.12077973 on 9 Aug 2026.
    //
    // The `jni` package (pulled in transitively by the PDF renderer) requires
    // 28.2.13676358, and Gradle said so on every build:
    //
    //   Your project is configured with Android NDK 27.0.12077973, but the
    //   following plugin(s) depend on a different Android NDK version:
    //   - jni requires Android NDK 28.2.13676358
    //   Fix this issue by using the highest Android NDK version (they are
    //   backward compatible).
    //
    // It is printed as a warning, which is why it survived several releases,
    // but it was costing real time: the release job installed NDK 27 *and*
    // CMake 3.22.1 from scratch inside the `bundleRelease` task, over a
    // gigabyte of download before compilation, on a runner with no Gradle
    // cache. Two NDKs is twice that.
    //
    // NDKs are backward compatible, so taking the highest is the documented
    // fix rather than a workaround.
    ndkVersion = "28.2.13676358"

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
        // Floor minSdk at 24 (Android 7.0): the Appodeal SDK needs 23 and
        // webview_flutter 4.14 (embedded YouTube live chat) needs 24.
        minSdk = maxOf(24, flutter.minSdkVersion)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
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

    // Android 15+ devices use 16 KB memory pages, which Google Play now
    // requires apps to support. AGP 8.5.1+ aligns native (.so) libraries to
    // 16 KB when JNI libs are packaged uncompressed (non-legacy) — which is
    // the default at our AGP version. We pin it explicitly so the requirement
    // can't silently regress and Play stops rejecting updates.
    packaging {
        jniLibs {
            useLegacyPackaging = false
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

    // ----- Appodeal mediated networks ---------------------------------
    //
    // The Appodeal core SDK and the IAB (MRAID) renderer come from the
    // stack_appodeal_flutter plugin's own build.gradle, so they are NOT
    // repeated here. Everything below is a MEDIATED NETWORK, added one at
    // a time, and each one costs APK size — do not paste the full list
    // from Appodeal's README.
    //
    // UPDATED 23 Aug 2026. The 17 Aug note below is kept because it explains
    // how we got here, but it is no longer the situation:
    //
    //   > Only these are usable today (founder's dashboard, 17 Aug 2026):
    //   > BidMachine, Backfill, Ad Server Campaigns. Every other network
    //   > reports "does not pass all restrictions" and unlocks only once the
    //   > app has live store traffic.
    //
    // The app now HAS live store traffic (34 installs / 59 active users in
    // the week to 23 Aug) and Mediation Setup -> Ad Networks shows an
    // "Appodeal account" already attached to ten networks. They were never
    // able to serve, because a network needs BOTH halves: enabled in the
    // dashboard AND its adapter compiled in here. Only BidMachine had the
    // second half, so the production waterfall was one bidder deep:
    // 6.29K requests, 2.7% fill, $0.0000 eCPM — the 63 impressions that did
    // land were unpaid Backfill/Ad Server house inventory.
    //
    // Each line below is a network the dashboard already holds an account
    // for, so none of them needs per-network signup. Versions were read from
    // the Appodeal artifactory on 23 Aug 2026 and are the current releases
    // against core SDK 4.2.0; the scheme is <network-sdk-version>.<build>,
    // which is why they do NOT look like Appodeal version numbers.
    // Regenerate with Appodeal's Dependencies Wizard:
    //   https://docs.appodeal.com/android/advanced/configure-mediated-networks
    //
    // DELIBERATELY NOT ADDED, though the dashboard has accounts for them —
    // each costs APK size and would buy nothing on this app's traffic:
    //   * VK Ads (my_target)  — "does not pass all restrictions" + CIS-only.
    //   * Amazon Ads          — "has to be connected manually", thin outside US.
    //   * DT Exchange         — "does not pass all restrictions".
    //   * Inmobi              — "not connected to Appodeal default account yet".
    //   * ironSource          — "does not pass all restrictions".
    //   * Meta / Yandex       — "has to be connected manually", no account.
    //
    // Those statuses are quoted from Apps -> Advent Connect ZW -> Ad Units on
    // 23 Aug 2026. An adapter for a network the dashboard will not serve is
    // pure APK weight at zero fill, so the list below is exactly the set that
    // page reports as ready. Recheck it when adding: ironSource and DT
    // Exchange are restriction-gated and should unlock as traffic grows, and
    // Inmobi needs one click to attach the Appodeal default account.
    //
    // NEVER add an AdMob adapter. The AdMob ACCOUNT (not just the app) is
    // disapproved and under appeal; serving through it is the one thing
    // that must not happen. AdsService also calls disableNetwork("admob")
    // as a second line of defence. If that ever changes, the AdMob App ID
    // meta-data has to go back into AndroidManifest.xml at the same time —
    // play-services-ads crashes on launch without it.
    implementation("com.appodeal.ads.sdk.adapters:bidmachine:3.7.1.0")
    implementation("com.appodeal.ads.sdk.adapters:applovin:13.6.4.0")
    implementation("com.appodeal.ads.sdk.adapters:unity_ads:4.17.0.0")
    implementation("com.appodeal.ads.sdk.adapters:vungle:7.7.7.0")
    implementation("com.appodeal.ads.sdk.adapters:mintegral:17.1.71.0")
    implementation("com.appodeal.ads.sdk.adapters:bigo_ads:6.0.0.0")
}
