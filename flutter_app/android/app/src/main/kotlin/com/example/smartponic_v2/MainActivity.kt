package com.example.smartponic_v2

import android.content.pm.PackageManager
import android.util.Base64
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "smartponic/hce")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isSupported" -> result.success(
                        packageManager.hasSystemFeature(PackageManager.FEATURE_NFC_HOST_CARD_EMULATION)
                    )
                    "setPayload" -> {
                        val payload = call.argument<ByteArray>("payload")
                        val ttlSeconds = call.argument<Int>("ttlSeconds") ?: 120
                        if (payload == null || payload.isEmpty()) {
                            result.error("empty_payload", "No NFC payload was provided.", null)
                            return@setMethodCallHandler
                        }
                        getSharedPreferences(HceStore.PREFS_NAME, MODE_PRIVATE)
                            .edit()
                            .putString(
                                HceStore.KEY_PAYLOAD_BASE64,
                                Base64.encodeToString(payload, Base64.NO_WRAP)
                            )
                            .putLong(
                                HceStore.KEY_ACTIVE_UNTIL_MS,
                                System.currentTimeMillis() + ttlSeconds * 1000L
                            )
                            .apply()
                        result.success(true)
                    }
                    "clearPayload" -> {
                        getSharedPreferences(HceStore.PREFS_NAME, MODE_PRIVATE)
                            .edit()
                            .remove(HceStore.KEY_PAYLOAD_BASE64)
                            .remove(HceStore.KEY_ACTIVE_UNTIL_MS)
                            .apply()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
