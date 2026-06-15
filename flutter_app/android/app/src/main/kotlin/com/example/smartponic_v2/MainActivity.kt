package com.example.smartponic_v2

import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageManager
import android.nfc.NdefMessage
import android.nfc.NfcAdapter
import android.nfc.Tag
import android.os.Build
import android.util.Base64
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var nfcAdapter: NfcAdapter? = null

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleNfcIntent(intent)
    }

    private fun handleNfcIntent(intent: Intent?) {
        if (intent == null) return
        val action = intent.action ?: return
        val engine = flutterEngine ?: return

        if (action == NfcAdapter.ACTION_NDEF_DISCOVERED ||
            action == NfcAdapter.ACTION_TAG_DISCOVERED ||
            action == NfcAdapter.ACTION_TECH_DISCOVERED) {

            val rawMessages = intent.getParcelableArrayExtra(NfcAdapter.EXTRA_NDEF_MESSAGES)
            var ndefRecords = mutableListOf<Map<String, Any>>()

            if (rawMessages != null) {
                val messages = rawMessages.mapNotNull { it as? NdefMessage }
                val channel = MethodChannel(
                    engine.dartExecutor.binaryMessenger,
                    "smartponic/nfc_dispatch"
                )

                for (msg in messages) {
                    for (record in msg.records) {
                        ndefRecords.add(
                            mapOf(
                                "tnf" to record.tnf.toInt(),
                                "type" to Base64.encodeToString(record.type, Base64.NO_WRAP),
                                "payload" to Base64.encodeToString(record.payload, Base64.NO_WRAP)
                            )
                        )
                    }
                }

                if (ndefRecords.isNotEmpty()) {
                    channel.invokeMethod("onNfcDiscovered", mapOf("records" to ndefRecords))
                }
            }

            if (ndefRecords.isEmpty()) {
                val tag = intent.getParcelableExtra<Tag>(NfcAdapter.EXTRA_TAG)
                if (tag != null) {
                    val channel = MethodChannel(
                        engine.dartExecutor.binaryMessenger,
                        "smartponic/nfc_dispatch"
                    )
                    val tagTechs = tag.techList.toList()
                    channel.invokeMethod("onNfcDiscovered", mapOf(
                        "isTag" to true,
                        "techs" to tagTechs
                    ))
                }
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        nfcAdapter = NfcAdapter.getDefaultAdapter(this)

        // HCE method channel for payload storage
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "smartponic/hce")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isSupported" -> {
                        val isHceSupported = try {
                            packageManager.hasSystemFeature(
                                PackageManager.FEATURE_NFC_HOST_CARD_EMULATION
                            )
                        } catch (e: Exception) {
                            false
                        }
                        result.success(isHceSupported)
                    }
                    "isNfcEnabled" -> {
                        result.success(nfcAdapter?.isEnabled ?: false)
                    }
                    "setPayload" -> {
                        val payloadAny = call.argument<Any>("payload")
                        val payload: ByteArray = when (payloadAny) {
                            is ByteArray -> payloadAny
                            is List<*> -> {
                                try {
                                    ByteArray(payloadAny.size) { i ->
                                        (payloadAny[i] as Number).toByte()
                                    }
                                } catch (e: Exception) {
                                    result.error("payload_error", "Invalid payload: ", null)
                                    return@setMethodCallHandler
                                }
                            }
                            else -> {
                                result.error(
                                    "payload_error",
                                    "Invalid type: ",
                                    null
                                )
                                return@setMethodCallHandler
                            }
                        }
                        val ttlSeconds = call.argument<Int>("ttlSeconds") ?: 120

                        if (payload.isEmpty()) {
                            result.error("empty_payload", "No NFC payload provided.", null)
                            return@setMethodCallHandler
                        }

                        getSharedPreferences(HceStore.PREFS_NAME, MODE_PRIVATE)
                            .edit()
                            .putString(HceStore.KEY_PAYLOAD_BASE64, Base64.encodeToString(payload, Base64.NO_WRAP))
                            .putLong(HceStore.KEY_ACTIVE_UNTIL_MS, System.currentTimeMillis() + ttlSeconds * 1000L)
                            .apply()

                        // Start foreground service to keep HCE alive
                        val serviceIntent = Intent(this, NfcForegroundService::class.java)
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(serviceIntent)
                        } else {
                            startService(serviceIntent)
                        }
                        result.success(true)
                    }
                    "clearPayload" -> {
                        getSharedPreferences(HceStore.PREFS_NAME, MODE_PRIVATE)
                            .edit()
                            .remove(HceStore.KEY_PAYLOAD_BASE64)
                            .remove(HceStore.KEY_ACTIVE_UNTIL_MS)
                            .apply()

                        // Stop foreground service
                        val serviceIntent = Intent(this, NfcForegroundService::class.java)
                        stopService(serviceIntent)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
