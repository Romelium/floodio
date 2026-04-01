# FLUTTER BLUE PLUS
-keep class com.lib.flutter_blue_plus.* { *; }

# BACKGROUND SERVICE
-keep class id.flutter.flutter_background_service.** { *; }

# DRIFT / SQLITE
-dontwarn org.sqlite.**
-dontwarn net.sqlcipher.**

# PLAY CORE / DEFERRED COMPONENTS (Fixes R8 missing class errors)
-dontwarn com.google.android.play.core.**
-dontwarn io.flutter.embedding.engine.deferredcomponents.**
