package com.example.floodio

import android.bluetooth.BluetoothManager
import android.content.Context
import android.net.wifi.WifiManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private val APK_CHANNEL = "com.example.floodio/apk"
    private val SYSTEM_CHANNEL = "com.example.floodio/system"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, APK_CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "getApkPath") {
                val apkPath = applicationInfo.sourceDir
                result.success(apkPath)
            } else {
                result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SYSTEM_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "setBluetoothName" -> {
                    val name = call.argument<String>("name")
                    val bluetoothManager = getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
                    val adapter = bluetoothManager.adapter
                    if (adapter != null && name != null) {
                        try {
                            @Suppress("MissingPermission")
                            val success = adapter.setName(name)
                            result.success(success)
                        } catch (e: SecurityException) {
                            result.success(false)
                        }
                    } else {
                        result.success(false)
                    }
                }
                "getBluetoothName" -> {
                    val bluetoothManager = getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
                    val adapter = bluetoothManager.adapter
                    if (adapter != null) {
                        try {
                            @Suppress("MissingPermission")
                            result.success(adapter.name)
                        } catch (e: SecurityException) {
                            result.success(null)
                        }
                    } else {
                        result.success(null)
                    }
                }
                "toggleWifi" -> {
                    val enable = call.argument<Boolean>("enable") ?: true
                    val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                    try {
                        @Suppress("DEPRECATION")
                        val success = wifiManager.setWifiEnabled(enable)
                        result.success(success)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
