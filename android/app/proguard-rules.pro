# Flutter's embedding uses reflection for plugin registration and for the
# deferred-components / split-install hooks. R8 cannot see those references, so
# keep them explicitly.
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**

# Play Core is referenced by Flutter's deferred-components support but is not a
# dependency of this app, which ships as a single module.
-dontwarn com.google.android.play.core.**
