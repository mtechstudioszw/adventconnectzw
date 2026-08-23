# Flutter / Dart — keeps the Flutter engine entry points and plugin
# registrant from being stripped. Flutter's Gradle plugin auto-merges
# its own rules too, but these are belt-and-braces.
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Firebase — most rules ship inside the firebase-* AARs, but
# Crashlytics needs explicit keep for line numbers in stack traces.
-keepattributes SourceFile,LineNumberTable
-keep public class * extends java.lang.Exception

# Supabase Flutter / kotlinx.serialization — these libs use
# reflection to deserialize PostgREST JSON responses. Without these
# rules release builds throw SerializationException at runtime.
-keep,includedescriptorclasses class io.supabase.** { *; }
-keepclassmembers class kotlinx.serialization.** { *; }
-keepclasseswithmembers class * {
    @kotlinx.serialization.Serializable <fields>;
}
-keep,includedescriptorclasses class kotlinx.serialization.json.** { *; }

# image_cropper (UCrop) — registered in AndroidManifest, would
# otherwise be stripped because it's not referenced from Kotlin.
-keep class com.yalantis.ucrop.** { *; }
-keep interface com.yalantis.ucrop.** { *; }

# Play Core (Flutter deferred components / dynamic feature support).
# Safe to keep even if unused; if stripped, Flutter logs a warning.
-keep class com.google.android.play.core.** { *; }
-dontwarn com.google.android.play.core.**

# Appodeal + mediated networks. The SDK resolves every network adapter by
# CLASS NAME at runtime (com.appodeal.ads.adapters.<network>.*), so R8 sees
# no reference to any of them and shrinks the entire waterfall out of the
# release build. The failure is silent and looks exactly like "no fill":
# init succeeds, requests go out, nothing ever comes back. Debug builds have
# minify off, which is half of why ads only ever appeared there.
#
# The core SDK ships consumer rules in its AAR, but the mediated adapters
# are added per-network in app/build.gradle.kts and are the part that gets
# stripped, so keep the adapter packages explicitly.
-keep class com.appodeal.ads.** { *; }
-keep interface com.appodeal.ads.** { *; }
-keep class com.explorestack.** { *; }
-keep interface com.explorestack.** { *; }
-keep class io.bidmachine.** { *; }
-keep interface io.bidmachine.** { *; }
-dontwarn com.appodeal.ads.**
-dontwarn com.explorestack.**
-dontwarn io.bidmachine.**

# The mediated network SDKs pulled in by the adapters in build.gradle.kts.
# Each ships its own consumer rules, so these are -dontwarn only: adding
# seven adapters at once surfaces a lot of cross-references to classes that
# other adapters would have provided, and R8 treats those as build-breaking
# warnings rather than shrinking decisions. Keeps are deliberately NOT added
# here — the AARs' own rules are more precise than a blanket -keep, and
# blanket keeps on seven ad SDKs would undo most of the size win that
# minification exists for.
-dontwarn com.applovin.**
-dontwarn com.unity3d.**
-dontwarn com.vungle.**
-dontwarn com.mbridge.**
-dontwarn sg.bigo.**
-dontwarn com.inmobi.**
-dontwarn com.ironsource.**
-dontwarn com.unity.**

# OkHttp / Conscrypt — pulled in transitively by Supabase and
# firebase_messaging. Without these you get "platform" warnings.
-dontwarn org.conscrypt.**
-dontwarn org.bouncycastle.**
-dontwarn org.openjsse.**
