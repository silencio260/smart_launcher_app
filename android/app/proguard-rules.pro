# Flutter / R8 keep rules for the release (minified) build.

# Flutter embedding & engine.
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.util.** { *; }

# Flutter references Play Core (deferred components / split installs) which we
# do not bundle. Without these the shrinker fails on missing classes.
-dontwarn com.google.android.play.core.**
-keep class com.google.android.play.core.** { *; }

# Firebase / Crashlytics: keep model classes and line numbers for readable
# stack traces.
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**
-keepattributes SourceFile,LineNumberTable
-keep public class * extends java.lang.Exception

# Keep annotations and generic signatures used via reflection.
-keepattributes *Annotation*,Signature,InnerClasses,EnclosingMethod
