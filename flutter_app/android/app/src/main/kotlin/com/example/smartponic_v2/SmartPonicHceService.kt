package com.example.smartponic_v2

import android.nfc.cardemulation.HostApduService
import android.os.Bundle
import android.util.Base64

class SmartPonicHceService : HostApduService() {
    override fun processCommandApdu(commandApdu: ByteArray?, extras: Bundle?): ByteArray {
        if (commandApdu == null || commandApdu.isEmpty()) return statusWrongLength()

        if (isSelectAid(commandApdu)) {
            return if (payload().isNotEmpty()) STATUS_OK else STATUS_CONDITIONS_NOT_SATISFIED
        }

        return when (commandApdu.getOrNull(1)?.toInt()?.and(0xFF)) {
            INS_GET_LENGTH -> lengthResponse()
            INS_READ_BINARY -> chunkResponse(commandApdu)
            else -> STATUS_INS_NOT_SUPPORTED
        }
    }

    override fun onDeactivated(reason: Int) = Unit

    private fun lengthResponse(): ByteArray {
        val payload = payload()
        if (payload.isEmpty()) return STATUS_CONDITIONS_NOT_SATISFIED
        val length = payload.size
        return byteArrayOf(
            ((length ushr 24) and 0xFF).toByte(),
            ((length ushr 16) and 0xFF).toByte(),
            ((length ushr 8) and 0xFF).toByte(),
            (length and 0xFF).toByte(),
            STATUS_OK[0],
            STATUS_OK[1],
        )
    }

    private fun chunkResponse(commandApdu: ByteArray): ByteArray {
        val payload = payload()
        if (payload.isEmpty()) return STATUS_CONDITIONS_NOT_SATISFIED
        if (commandApdu.size < 5) return statusWrongLength()

        val offset = (commandApdu[2].toInt().and(0xFF) shl 8) or commandApdu[3].toInt().and(0xFF)
        val requested = commandApdu[4].toInt().and(0xFF).let { if (it == 0) MAX_CHUNK_SIZE else it }
        if (offset >= payload.size) return STATUS_WRONG_P1P2

        val chunkSize = minOf(requested, MAX_CHUNK_SIZE, payload.size - offset)
        val response = ByteArray(chunkSize + STATUS_OK.size)
        System.arraycopy(payload, offset, response, 0, chunkSize)
        response[chunkSize] = STATUS_OK[0]
        response[chunkSize + 1] = STATUS_OK[1]
        return response
    }

    private fun payload(): ByteArray {
        val prefs = getSharedPreferences(HceStore.PREFS_NAME, MODE_PRIVATE)
        val activeUntil = prefs.getLong(HceStore.KEY_ACTIVE_UNTIL_MS, 0L)
        if (activeUntil > 0L && System.currentTimeMillis() > activeUntil) return ByteArray(0)

        val encoded = prefs.getString(HceStore.KEY_PAYLOAD_BASE64, null) ?: return ByteArray(0)
        return try {
            Base64.decode(encoded, Base64.NO_WRAP)
        } catch (_: IllegalArgumentException) {
            ByteArray(0)
        }
    }

    private fun isSelectAid(apdu: ByteArray): Boolean {
        if (apdu.size < 5) return false
        if (apdu[0] != 0x00.toByte() || apdu[1] != 0xA4.toByte() || apdu[2] != 0x04.toByte()) {
            return false
        }
        val length = apdu[4].toInt().and(0xFF)
        if (apdu.size < 5 + length) return false
        val aid = apdu.copyOfRange(5, 5 + length)
        return aid.contentEquals(SMARTPONIC_AID)
    }

    private fun statusWrongLength() = STATUS_WRONG_LENGTH

    companion object {
        private val SMARTPONIC_AID = byteArrayOf(
            0xF0.toByte(),
            0x53,
            0x4D,
            0x41,
            0x52,
            0x54,
            0x50,
            0x4F,
            0x4E,
            0x49,
            0x43,
        )
        private const val INS_GET_LENGTH = 0xCA
        private const val INS_READ_BINARY = 0xB0
        private const val MAX_CHUNK_SIZE = 48
        private val STATUS_OK = byteArrayOf(0x90.toByte(), 0x00)
        private val STATUS_CONDITIONS_NOT_SATISFIED = byteArrayOf(0x69.toByte(), 0x85.toByte())
        private val STATUS_INS_NOT_SUPPORTED = byteArrayOf(0x6D.toByte(), 0x00)
        private val STATUS_WRONG_LENGTH = byteArrayOf(0x67.toByte(), 0x00)
        private val STATUS_WRONG_P1P2 = byteArrayOf(0x6B.toByte(), 0x00)
    }
}

object HceStore {
    const val PREFS_NAME = "smartponic_hce"
    const val KEY_PAYLOAD_BASE64 = "payload_base64"
    const val KEY_ACTIVE_UNTIL_MS = "active_until_ms"
}
