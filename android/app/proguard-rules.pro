# FLUTTER & PLUGINS CORE
-keep class io.flutter.embedding.engine.plugins.FlutterPlugin { *; }
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class com.example.floodio.MainActivity { *; }

# PROTOBUF
-keep class com.google.protobuf.** { *; }
-keep class * extends com.google.protobuf.GeneratedMessageV3 { *; }
-keep class * extends com.google.protobuf.MessageOrBuilder { *; }
-keep enum * extends com.google.protobuf.Internal$EnumLite { *; }

# GSON & NOTIFICATIONS
-keep class com.google.gson.** { *; }
-keep class com.dexterous.flutterlocalnotifications.** { *; }
-keepattributes Signature, *Annotation*, EnclosingMethod
# Keep the model classes used by the notification plugin
-keep class com.dexterous.flutterlocalnotifications.models.** { *; }

# P2P & BLUETOOTH
-keep class com.lib.flutter_blue_plus.* { *; }
-keep class android.net.wifi.p2p.** { *; }
-keep class android.bluetooth.** { *; }
# Keep the P2P connection plugin's native handlers
-keep class com.example.flutter_p2p_connection.** { *; }

# BACKGROUND SERVICE
# Ensures the background isolate and its entry point are never removed
-keep class id.flutter.flutter_background_service.** { *; }

# DRIFT / SQLITE
-keep class org.sqlite.** { *; }
-keep class net.sqlcipher.** { *; }
-dontwarn org.sqlite.**
-dontwarn net.sqlcipher.**