#ifndef SMARTPACKET_H
#define SMARTPACKET_H

#include <Arduino.h>
#include <stdint.h>
#include <string.h>
#include <assert.h>

namespace SmartPacket {

// ================= Firmware Version =================
// Update these on each release. GIT_HASH is set by build system or left as "unknown".
constexpr const char* FIRMWARE_VERSION_STR   = "1.0.0";
constexpr const char* FIRMWARE_GIT_HASH      = "@GIT_HASH@";
constexpr uint16_t    FIRMWARE_VERSION_MAJOR = 1;
constexpr uint16_t    FIRMWARE_VERSION_MINOR = 0;
constexpr uint16_t    FIRMWARE_VERSION_PATCH = 0;

// ================= Core Packet Constants =================
constexpr uint32_t MAGIC           = 0x31504653UL;  // "SPF1"
constexpr uint8_t  VERSION         = 0x01;
constexpr size_t   HEADER_SIZE     = 23;             // 4 + 1 + 16 + 2
constexpr size_t   NONCE_SIZE      = 16;
constexpr size_t   CRC_SIZE        = 4;
constexpr size_t   MAX_PACKET_BYTES = 255;
constexpr size_t   MAX_HARDWARE_ID_SIZE = 16;        // 16-char hex
constexpr size_t   MAX_AUTH_KEY_SIZE   = 32;         // max auth key bytes
constexpr size_t   AES_KEY_SIZE       = 16;          // 16-byte AES-128 key
constexpr size_t   HMAC_KEY_SIZE      = 16;

// Derived minimum full-packet length for validation (magic + version + hwId + payloadLen + nonce + crc + 1)
constexpr size_t   MIN_PACKET_LEN = HEADER_SIZE + NONCE_SIZE + CRC_SIZE + 1;

// ================= Sampling / Intervals =================
constexpr unsigned long SAMPLE_INTERVAL_MS       = 90000UL;  // 90s default
constexpr unsigned long INTERVAL_NORMAL_MS       = 900000UL; // 15 min
constexpr unsigned long INTERVAL_ABNORMAL_MS     = 300000UL; // 5 min
constexpr unsigned long INTERVAL_CRITICAL_MS     = 60000UL;  // 1 min
constexpr unsigned long INTERVAL_IMMEDIATE_MS    = 1000UL;   // immediate dispatch

// Minimum interval between DHT22 reads (datasheet: 2s)
constexpr unsigned long DHT_MIN_INTERVAL_MS      = 2000UL;

// ================= Priority Levels =================
constexpr uint8_t PRIORITY_LOW    = 0;
constexpr uint8_t PRIORITY_MEDIUM = 1;
constexpr uint8_t PRIORITY_HIGH   = 2;

// ================= Report Modes =================
constexpr uint8_t REPORT_MODE_NORMAL   = 0;
constexpr uint8_t REPORT_MODE_ABNORMAL = 1;
constexpr uint8_t REPORT_MODE_CRITICAL = 2;

// ================= Binary Payload Format =================
enum SensorType : uint8_t {
    SENSOR_TEMPERATURE = 0,
    SENSOR_HUMIDITY    = 1,
    SENSOR_WATER_TEMP  = 2,
    SENSOR_PH          = 3,
    SENSOR_TDS         = 4,
    SENSOR_TURBIDITY   = 5,
    SENSOR_RAIN        = 6,
    SENSOR_NONE        = 7   // sentinel for unrecognized / missing
};

// How many sensor types we actually classify
constexpr uint8_t SENSOR_TYPE_COUNT = 7;

constexpr uint16_t BIN_VALUE_NAN    = 0x7FFF;
constexpr uint16_t BIN_VALUE_ERROR  = 0x7FFE;
constexpr uint8_t  BIN_READING_SIZE = 4;       // pin + type + value(2B)
constexpr uint8_t  BIN_HEADER_SIZE  = 3;       // count(1) + priority(1) + report_mode(1)
constexpr uint8_t  BIN_MAX_READINGS = 24;

// ================= Node Registration / State Machine =================
// Commands sent inside encrypted registration payloads
constexpr const char* CMD_HELLO      = "hello";
constexpr const char* CMD_APPROVE    = "approve";
constexpr const char* CMD_REJECT     = "reject";
constexpr const char* CMD_REFRESH    = "refresh";

// Node states
enum NodeState : uint8_t {
    NODE_UNREGISTERED = 0,
    NODE_HELLO_SENT   = 1,
    NODE_APPROVED     = 2,
    NODE_CONNECTED    = 3,
    NODE_RECONNECTING = 4
};

// ACK tracking: milliseconds after which a node is considered disconnected
constexpr unsigned long ACK_LOSS_TIMEOUT_MS  = 1800000UL;  // 30 min without ACK -> reconnect
constexpr unsigned long ACK_LOSS_RETRY_MS    = 30000UL;     // retry hello every 30s during reconnect

// ================= Store-and-Forward Retry Queue =================
constexpr uint8_t  MAX_RETRY_QUEUE      = 12;    // max buffered packets per thesis Ch4
constexpr size_t   MAX_PACKET_STORE_SIZE = MAX_PACKET_BYTES;  // per-entry size in queue

// ================= ADR (Adaptive Data Rate) =================
// RSSI thresholds for dynamic SF selection
constexpr int ADR_RSSI_EXCELLENT   = -80;    // SF7
constexpr int ADR_RSSI_GOOD        = -90;    // SF8
constexpr int ADR_RSSI_FAIR        = -100;   // SF9
constexpr int ADR_RSSI_POOR        = -110;   // SF10
constexpr int ADR_INVALID_RSSI     = -999;

// SF values used by LoRa library
constexpr uint8_t ADR_SF7  = 7;
constexpr uint8_t ADR_SF8  = 8;
constexpr uint8_t ADR_SF9  = 9;
constexpr uint8_t ADR_SF10 = 10;

// ADR evaluation interval: re-evaluate SF every N received ACKs
constexpr uint8_t ADR_EVAL_AFTER_ACKS = 5;

// ================= CAD (Channel Activity Detection) =================
constexpr uint8_t  CAD_ATTEMPTS_MAX     = 5;      // max CAD attempts before force-send
constexpr uint8_t  CAD_SYMBOL_TIME_MS   = 32;     // approx LoRa symbol time at SF9 (ms)
constexpr uint16_t CAD_BACKOFF_MIN_MS   = 50;     // minimum random backoff
constexpr uint16_t CAD_BACKOFF_MAX_MS   = 500;    // maximum random backoff

// ================= Relay Commands & ACK Tracking =================
constexpr size_t   RELAY_ID_SIZE      = 16;     // max relay hardware ID string length
constexpr uint8_t  RELAY_CMD_ON       = 1;
constexpr uint8_t  RELAY_CMD_OFF      = 0;
constexpr uint8_t  RELAY_CMD_STATUS   = 2;      // request status report
constexpr uint8_t  RELAY_STATUS_ON    = 1;
constexpr uint8_t  RELAY_STATUS_OFF   = 0;
constexpr uint8_t  RELAY_STATUS_ERROR = 0xFF;   // relay not found / fault

// Track relay command execution
struct RelayAckPayload {
    uint8_t  relayIndex;
    uint8_t  command;
    uint8_t  executed;
    uint16_t sequenceNumber;
};

// ================= Watchdog Timer =================
constexpr unsigned long WATCHDOG_TIMEOUT_MS     = 10000UL;   // 10s task watchdog
constexpr unsigned long WATCHDOG_HTTP_TIMEOUT_MS = 15000UL;  // 15s for HTTP operations
constexpr unsigned long WATCHDOG_SENSOR_TIMEOUT_MS = 5000UL; // 5s for sensor reads

// ================= Deep Sleep / Power Saving =================
constexpr unsigned long DEEP_SLEEP_MIN_US       = 1000000UL;       // 1s minimum
constexpr unsigned long DEEP_SLEEP_DEFAULT_US   = 900000000UL;     // 15 min default (900s)
constexpr uint8_t       LIGHT_SLEEP_ENABLED     = 1;
constexpr uint8_t       DEEP_SLEEP_ENABLED      = 2;

// GPIO wake-up pins for deep sleep
constexpr uint8_t  DEEP_SLEEP_WAKEUP_PIN        = 4;      // default wake pin
constexpr uint8_t  DEEP_SLEEP_WAKEUP_LEVEL      = 1;      // HIGH level wakes

// ================= OTA Firmware Update =================
constexpr uint16_t OTA_PORT                  = 3232;
constexpr size_t   OTA_UPDATE_CHUNK_SIZE     = 1024;
constexpr unsigned long OTA_TIMEOUT_MS       = 60000UL;   // 60s max OTA session
constexpr const char* OTA_PARTITION_LABEL     = "app0";
constexpr const char* OTA_HOSTNAME_PREFIX     = "SmartPonic-";

// ================= Serial CLI Commands =================
constexpr const char* CLI_HELP       = "HELP";
constexpr const char* CLI_SETKEYS    = "SETKEYS";
constexpr const char* CLI_STATUS     = "STATUS";
constexpr const char* CLI_ADD        = "ADD";
constexpr const char* CLI_REMOVE     = "REMOVE";
constexpr const char* CLI_LIST       = "LIST";
constexpr const char* CLI_CALIBRATE  = "CALIBRATE";
constexpr const char* CLI_SLEEP      = "SLEEP";
constexpr const char* CLI_REBOOT     = "REBOOT";
constexpr const char* CLI_RESET      = "RESET";
constexpr const char* CLI_VERSION    = "VERSION";

// ================= NFC Provisioning =================
constexpr const char* NFC_AID        = "F0.SMARTPONIC";
constexpr uint8_t     NFC_AID_BYTES[] = { 0xF0, 0x53, 0x4D, 0x41, 0x52, 0x54, 0x50, 0x4F, 0x4E, 0x49, 0x43 };
constexpr uint8_t     NFC_AID_LEN    = sizeof(NFC_AID_BYTES);
constexpr size_t      NFC_PAGE_SIZE  = 4;        // NTAG215 page size
constexpr size_t      NFC_TLV_OFFSET = 4;        // NDEF TLV starts after first 4 pages (capability container)
constexpr uint8_t     NFC_TLV_NDEF   = 0x03;     // NDEF message TLV tag
constexpr uint8_t     NFC_TLV_TERM   = 0xFE;     // TLV terminator

// AES-CTR provisioning nonce prefix for NFC
constexpr const char* NFC_PROVISIONING_PREFIX = "NFCv1";

// ================= Endianness Helpers =================
// Explicit conversion for multi-byte fields (magic, payloadLength, CRC32)
// These always produce little-endian wire format, matching ESP32 native but
// portable to big-endian platforms.

inline uint16_t htons_u16(uint16_t val) {
#if __BYTE_ORDER__ == __ORDER_BIG_ENDIAN__
    return val;
#else
    return __builtin_bswap16(val);
#endif
}

inline uint16_t ntohs_u16(uint16_t val) {
    return htons_u16(val);  // symmetric
}

inline uint32_t htonl_u32(uint32_t val) {
#if __BYTE_ORDER__ == __ORDER_BIG_ENDIAN__
    return val;
#else
    return __builtin_bswap32(val);
#endif
}

inline uint32_t ntohl_u32(uint32_t val) {
    return htonl_u32(val);  // symmetric
}

// ================= CRC32 =================
inline uint32_t crc32(const uint8_t* data, size_t len) {
    uint32_t crc = 0xFFFFFFFF;
    for (size_t i = 0; i < len; i++) {
        crc ^= data[i];
        for (int b = 0; b < 8; b++) {
            crc = (crc >> 1) ^ (0xEDB88320 & -(crc & 1));
        }
    }
    return ~crc;
}

// ================= Binary Payload Header =================
// Wire format of a binary payload header (written before the reading array):
//   uint8_t count;        // number of readings
//   uint8_t priority;     // PRIORITY_LOW / MEDIUM / HIGH
//   uint8_t report_mode;  // REPORT_MODE_NORMAL / ABNORMAL / CRITICAL

#pragma pack(push, 1)
struct Header {
    uint32_t magic;          // 0x31504653 (little-endian)
    uint8_t  version;        // 0x01
    uint8_t  hardwareId[MAX_HARDWARE_ID_SIZE]; // 16-char uppercase hex hardware ID
    uint16_t payloadLength;  // encrypted payload size (little-endian)
};
#pragma pack(pop)

// Compile-time check: Header must be exactly HEADER_SIZE bytes with no padding
static_assert(sizeof(Header) == 23, "SmartPacket::Header size mismatch (expected 23 bytes)");

// ================= Nonce Construction =================
/**
 * Fill a 16-byte nonce for AES-CTR.
 *
 * Structure:
 *   bytes 0-3:   esp_random() full entropy (4 bytes) -- XOR of 4 independent random calls
 *   bytes 4-7:   boot-unique counter from a persisted or mixed source
 *                 (millis() low + boot-time esp_random() seed)
 *   bytes 8-11:  esp_random()
 *   bytes 12-15: esp_random()
 *
 * This avoids the previous issue where bytes 8-15 only used 2 random values (r1/r2)
 * for 8 bytes, wasting entropy.
 *
 * It also mitigates the boot-reuse collision: by XOR'ing millis() with a bootSeed
 * derived from two independent esp_random() calls, the same millis() value across
 * reboots produces a different nonce.
 */
inline void fillNonce(uint8_t nonce[NONCE_SIZE]) {
    // Seed generation: combine two random values into a boot-specific base
    uint32_t bootSeed = esp_random() ^ esp_random();
    uint32_t nowMs    = millis();

    // Bytes 0-3: full entropy from 4 independent random calls
    uint32_t r0 = esp_random();
    uint32_t r1 = esp_random();
    uint32_t r2 = esp_random();
    uint32_t r3 = esp_random();
    // Mix all four into the first 4 bytes
    uint32_t entropyBlock = r0 ^ r1 ^ r2 ^ (r3 << 1);
    memcpy(nonce, &entropyBlock, 4);

    // Bytes 4-7: boot-unique counter; XOR millis() with the boot seed so same
    // millis() across reboots produces a different nonce.
    uint32_t counterBlock = nowMs ^ bootSeed;
    memcpy(nonce + 4, &counterBlock, 4);

    // Bytes 8-11: fresh random
    uint32_t r4 = esp_random();
    memcpy(nonce + 8, &r4, 4);

    // Bytes 12-15: fresh random
    uint32_t r5 = esp_random();
    memcpy(nonce + 12, &r5, 4);
}

// ================= Sensor Type Utilities =================
inline SensorType sensorNameToType(const String& name) {
    if (name == "Temperature") return SENSOR_TEMPERATURE;
    if (name == "Humidity")    return SENSOR_HUMIDITY;
    if (name == "WaterTemp")   return SENSOR_WATER_TEMP;
    if (name == "pH")          return SENSOR_PH;
    if (name == "TDS")         return SENSOR_TDS;
    if (name == "Turbidity")   return SENSOR_TURBIDITY;
    if (name == "Rain")        return SENSOR_RAIN;
    // Return NONE for unrecognized names instead of silently mapping to TEMPERATURE,
    // so callers can detect configuration errors.
    return SENSOR_NONE;
}

inline const char* sensorTypeToName(SensorType type) {
    switch (type) {
        case SENSOR_TEMPERATURE: return "Temperature";
        case SENSOR_HUMIDITY:    return "Humidity";
        case SENSOR_WATER_TEMP:  return "WaterTemp";
        case SENSOR_PH:          return "pH";
        case SENSOR_TDS:         return "TDS";
        case SENSOR_TURBIDITY:   return "Turbidity";
        case SENSOR_RAIN:        return "Rain";
        default:                 return "Unknown";
    }
}

inline bool isBinaryFormat(const uint8_t* data, size_t len) {
    if (len == 0) return false;
    return data[0] <= BIN_MAX_READINGS;
}

inline String priorityLabel(uint8_t priority) {
    switch (priority) {
        case PRIORITY_HIGH:   return "HIGH";
        case PRIORITY_MEDIUM: return "MEDIUM";
        default:              return "LOW";
    }
}

inline String reportModeLabel(uint8_t reportMode) {
    switch (reportMode) {
        case REPORT_MODE_CRITICAL: return "CRITICAL";
        case REPORT_MODE_ABNORMAL: return "ABNORMAL";
        default:                   return "NORMAL";
    }
}

// ================= Field Extraction =================
inline String getFieldValue(const String& data, const String& key) {
    String prefix = key + "=";
    int start = 0;
    while (true) {
        int amp = data.indexOf('&', start);
        int end = (amp < 0) ? data.length() : amp;
        String seg = data.substring(start, end);
        if (seg.startsWith(prefix)) {
            return seg.substring(prefix.length());
        }
        if (amp < 0) break;
        start = amp + 1;
    }
    return "";
}

// ================= Hardware ID Utilities =================
inline String formatHardwareId(uint64_t efuseMac) {
    char buf[17];
    snprintf(buf, sizeof(buf), "%016llX", efuseMac);
    return String(buf);
}

/**
 * Validate a hardware ID string.
 * Accepts both uppercase (A-F) and lowercase (a-f) hex characters.
 */
inline bool isValidHardwareId(const String& hwId) {
    if (hwId.length() != MAX_HARDWARE_ID_SIZE) return false;
    for (int i = 0; i < MAX_HARDWARE_ID_SIZE; i++) {
        char c = hwId.charAt(i);
        bool isDigit      = (c >= '0' && c <= '9');
        bool isUpperHex   = (c >= 'A' && c <= 'F');
        bool isLowerHex   = (c >= 'a' && c <= 'f');
        if (!(isDigit || isUpperHex || isLowerHex)) return false;
    }
    return true;
}

// ================= Pin Safety =================
inline bool isSafePin(int pin) {
    switch (pin) {
        case 4:  case 12: case 13: case 15: case 16: case 17:
        case 21: case 22: case 25: case 26: case 27:
        case 32: case 33: case 34: case 35: case 36: case 39:
            return true;
        default:
            return false;
    }
}

// ================= Interval Selection =================
/**
 * Return the appropriate sampling interval for a given report mode.
 */
inline unsigned long intervalForReportMode(uint8_t reportMode) {
    switch (reportMode) {
        case REPORT_MODE_CRITICAL: return INTERVAL_CRITICAL_MS;
        case REPORT_MODE_ABNORMAL: return INTERVAL_ABNORMAL_MS;
        default:                   return INTERVAL_NORMAL_MS;
    }
}

// ================= ADR Helper =================
/**
 * Select the best spreading factor based on RSSI.
 * Returns SF7 through SF10.
 */
inline uint8_t selectSfFromRssi(int rssi) {
    if (rssi >= ADR_RSSI_EXCELLENT) return ADR_SF7;
    if (rssi >= ADR_RSSI_GOOD)      return ADR_SF8;
    if (rssi >= ADR_RSSI_FAIR)      return ADR_SF9;
    if (rssi >= ADR_RSSI_POOR)      return ADR_SF10;
    return ADR_SF10;  // fallback: slowest but most robust
}

// ================= CAD Helper =================
/**
 * Return a random backoff delay in milliseconds within [min, max].
 */
inline unsigned long cadBackoffMs() {
    return CAD_BACKOFF_MIN_MS + (esp_random() % (CAD_BACKOFF_MAX_MS - CAD_BACKOFF_MIN_MS + 1));
}

// ================= AES Key Validation =================
/**
 * Validate and pad (or truncate) a key string to exactly AES_KEY_SIZE bytes.
 * Returns false if the key is empty or contains non-printable characters.
 * On success, writes the key (null-padded if shorter than AES_KEY_SIZE) into out.
 */
inline bool normalizeAesKey(const String& key, uint8_t out[AES_KEY_SIZE]) {
    memset(out, 0, AES_KEY_SIZE);
    size_t len = key.length();
    if (len == 0) return false;
    size_t copyLen = (len < AES_KEY_SIZE) ? len : AES_KEY_SIZE;
    for (size_t i = 0; i < copyLen; i++) {
        char c = key.charAt(i);
        if (c < 32 || c > 126) return false;  // non-printable
        out[i] = (uint8_t)c;
    }
    return true;
}

} // namespace SmartPacket

#endif // SMARTPACKET_H