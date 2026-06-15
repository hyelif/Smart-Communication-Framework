#ifndef SMARTPACKET_H
#define SMARTPACKET_H

#include <Arduino.h>
#include <stdint.h>
#include <string.h>

namespace SmartPacket {

// Constants
constexpr uint32_t MAGIC           = 0x31504653UL;  // "SPF1"
constexpr uint8_t  VERSION         = 0x01;
constexpr size_t   HEADER_SIZE     = 23;  // 4 + 1 + 16 + 2
constexpr size_t   NONCE_SIZE      = 16;
constexpr size_t   CRC_SIZE        = 4;
constexpr size_t   MAX_PACKET_BYTES = 255;

// Sampling interval
constexpr unsigned long SAMPLE_INTERVAL_MS = 90000UL;

// Priority levels
constexpr uint8_t PRIORITY_LOW    = 0;
constexpr uint8_t PRIORITY_MEDIUM = 1;
constexpr uint8_t PRIORITY_HIGH   = 2;

// Report modes
constexpr uint8_t REPORT_MODE_NORMAL   = 0;
constexpr uint8_t REPORT_MODE_ABNORMAL = 1;
constexpr uint8_t REPORT_MODE_CRITICAL = 2;

// Dynamic intervals
constexpr unsigned long INTERVAL_NORMAL_MS   = 90000UL;
constexpr unsigned long INTERVAL_ABNORMAL_MS = 45000UL;
constexpr unsigned long INTERVAL_CRITICAL_MS = 10000UL;

// ================= Binary Payload Format =================
enum SensorType : uint8_t {
    SENSOR_TEMPERATURE = 0,
    SENSOR_HUMIDITY    = 1,
    SENSOR_WATER_TEMP  = 2,
    SENSOR_PH          = 3,
    SENSOR_TDS         = 4,
    SENSOR_TURBIDITY   = 5,
    SENSOR_RAIN        = 6
};

constexpr uint16_t BIN_VALUE_NAN    = 0x7FFF;
constexpr uint16_t BIN_VALUE_ERROR  = 0x7FFE;
constexpr uint8_t  BIN_READING_SIZE = 4;       // pin + type + value(2B)
constexpr uint8_t  BIN_HEADER_SIZE  = 3;       // count(1) + priority(1) + report_mode(1)
constexpr uint8_t  BIN_MAX_READINGS = 24;

// ADR Constants
constexpr int ADR_RSSI_SF7  = -100;
constexpr int ADR_RSSI_SF8  = -110;
constexpr int ADR_RSSI_SF9  = -120;
constexpr int ADR_INVALID_RSSI = -999;

inline SensorType sensorNameToType(const String& name) {
    if (name == "Temperature") return SENSOR_TEMPERATURE;
    if (name == "Humidity")    return SENSOR_HUMIDITY;
    if (name == "WaterTemp")   return SENSOR_WATER_TEMP;
    if (name == "pH")          return SENSOR_PH;
    if (name == "TDS")         return SENSOR_TDS;
    if (name == "Turbidity")   return SENSOR_TURBIDITY;
    if (name == "Rain")        return SENSOR_RAIN;
    return SENSOR_TEMPERATURE;
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
        case PRIORITY_HIGH: return "HIGH";
        case PRIORITY_MEDIUM: return "MEDIUM";
        default: return "LOW";
    }
}

inline String reportModeLabel(uint8_t reportMode) {
    switch (reportMode) {
        case REPORT_MODE_CRITICAL: return "CRITICAL";
        case REPORT_MODE_ABNORMAL: return "ABNORMAL";
        default: return "NORMAL";
    }
}

#pragma pack(push, 1)
struct Header {
    uint32_t magic;          // 0x31504653
    uint8_t  version;        // 0x01
    uint8_t  hardwareId[16]; // 16-char uppercase hex hardware ID
    uint16_t payloadLength;  // encrypted payload size (little-endian)
};
#pragma pack(pop)

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

inline void fillNonce(uint8_t nonce[16]) {
    memset(nonce, 0, 16);
    uint32_t now = millis();
    memcpy(nonce + 4, &now, 4);
    uint32_t r1 = esp_random();
    uint32_t r2 = esp_random();
    uint32_t r3 = esp_random();
    memcpy(nonce + 8, &r1, 4);
    memcpy(nonce + 12, &r2, 4);
    nonce[0] ^= (uint8_t)(r3 & 0xFF);
    nonce[1] ^= (uint8_t)((r3 >> 8) & 0xFF);
    nonce[2] ^= (uint8_t)((r3 >> 16) & 0xFF);
    nonce[3] ^= (uint8_t)((r3 >> 24) & 0xFF);
}

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

inline String formatHardwareId(uint64_t efuseMac) {
    char buf[17];
    snprintf(buf, sizeof(buf), "%016llX", efuseMac);
    return String(buf);
}

inline bool isValidHardwareId(const String& hwId) {
    if (hwId.length() != 16) return false;
    for (int i = 0; i < 16; i++) {
        char c = hwId.charAt(i);
        if (!((c >= '0' && c <= '9') || (c >= 'A' && c <= 'F'))) return false;
    }
    return true;
}

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

} // namespace SmartPacket

#endif // SMARTPACKET_H