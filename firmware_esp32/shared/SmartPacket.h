#pragma once

#include <Arduino.h>
#include <stdint.h>
#include <vector>

namespace SmartPacket {

constexpr uint32_t MAGIC = 0x31504653UL;  // "SPF1"
constexpr uint8_t VERSION = 1;
constexpr size_t NONCE_SIZE = 16;

enum Priority : uint8_t {
  PRIORITY_LOW = 0,
  PRIORITY_MEDIUM = 1,
  PRIORITY_HIGH = 2,
};

enum ReportMode : uint8_t {
  REPORT_MODE_NORMAL = 0,
  REPORT_MODE_ABNORMAL = 1,
  REPORT_MODE_CRITICAL = 2,
};

#pragma pack(push, 1)
struct Header {
  uint32_t magic;
  uint8_t version;
  uint8_t nodeId;
  uint8_t priority;
  uint8_t reportMode;
  uint16_t payloadLength;
  uint32_t sequence;
};
#pragma pack(pop)

inline uint32_t crc32(const uint8_t* data, size_t length) {
  uint32_t crc = 0xFFFFFFFFUL;
  for (size_t i = 0; i < length; ++i) {
    crc ^= data[i];
    for (uint8_t bit = 0; bit < 8; ++bit) {
      const uint32_t mask = -(crc & 1U);
      crc = (crc >> 1U) ^ (0xEDB88320UL & mask);
    }
  }
  return ~crc;
}

inline String priorityLabel(uint8_t priority) {
  switch (priority) {
    case PRIORITY_HIGH:
      return "HIGH";
    case PRIORITY_MEDIUM:
      return "MEDIUM";
    default:
      return "LOW";
  }
}

inline String reportModeLabel(uint8_t reportMode) {
  switch (reportMode) {
    case REPORT_MODE_CRITICAL:
      return "CRITICAL";
    case REPORT_MODE_ABNORMAL:
      return "ABNORMAL";
    default:
      return "NORMAL";
  }
}

}  // namespace SmartPacket
