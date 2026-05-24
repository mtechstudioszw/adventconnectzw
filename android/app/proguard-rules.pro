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

# OkHttp / Conscrypt — pulled in transitively by Supabase and
# firebase_messaging. Without these you get "platform" warnings.
-dontwarn org.conscrypt.**
-dontwarn org.bouncycastle.**
-dontwarn org.openjsse.**
