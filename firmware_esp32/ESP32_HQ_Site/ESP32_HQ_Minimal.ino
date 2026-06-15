// ESP32_HQ_Minimal.ino - Pure LoRa receiver for SmartPonic Node 38Pin
// No WiFi, no HTTP, no extra features - just receive + reply

#include <Arduino.h>
#include <SPI.h>
#include <LoRa.h>
#include <vector>
#include <mbedtls/aes.h>

// ================= SmartPacket constants (inlined) =================
namespace SmartPacket {
constexpr uint32_t MAGIC = 0x31504653UL;
constexpr uint8_t VERSION = 0x01;
constexpr size_t HEADER_SIZE = 23;
constexpr size_t NONCE_SIZE = 16;
constexpr size_t CRC_SIZE = 4;
constexpr size_t MAX_PACKET_BYTES = 255;

constexpr uint8_t BIN_READING_SIZE = 4;
constexpr uint8_t BIN_HEADER_SIZE = 1;
constexpr uint8_t BIN_MAX_READINGS = 24;
constexpr uint16_t BIN_VALUE_NAN = 0x7FFF;
constexpr uint16_t BIN_VALUE_ERROR = 0x7FFE;

enum SensorType : uint8_t {
  SENSOR_TEMPERATURE = 0, SENSOR_HUMIDITY = 1, SENSOR_WATER_TEMP = 2,
  SENSOR_PH = 3, SENSOR_TDS = 4, SENSOR_TURBIDITY = 5, SENSOR_RAIN = 6
};

struct __attribute__((packed)) Header {
  uint32_t magic;
  uint8_t version;
  uint8_t hardwareId[16];
  uint16_t payloadLength;
};

inline uint32_t crc32(const uint8_t* data, size_t len) {
  uint32_t crc = 0xFFFFFFFF;
  for (size_t i = 0; i < len; i++) {
    crc ^= data[i];
    for (int b = 0; b < 8; b++) crc = (crc >> 1) ^ (0xEDB88320 & -(crc & 1));
  }
  return ~crc;
}

inline void fillNonce(uint8_t nonce[16]) {
  memset(nonce, 0, 16);
  uint32_t now = millis();
  memcpy(nonce + 4, &now, 4);
  uint32_t r1 = esp_random(), r2 = esp_random(), r3 = esp_random();
  memcpy(nonce + 8, &r1, 4);
  memcpy(nonce + 12, &r2, 4);
  nonce[0] ^= (r3 & 0xFF); nonce[1] ^= ((r3 >> 8) & 0xFF);
  nonce[2] ^= ((r3 >> 16) & 0xFF); nonce[3] ^= ((r3 >> 24) & 0xFF);
}

inline String getFieldValue(const String& data, const String& key) {
  String prefix = key + "=";
  int start = 0;
  while (true) {
    int amp = data.indexOf('&', start);
    int end = (amp < 0) ? data.length() : amp;
    String seg = data.substring(start, end);
    if (seg.startsWith(prefix)) return seg.substring(prefix.length());
    if (amp < 0) break;
    start = amp + 1;
  }
  return "";
}

inline bool isValidHardwareId(const String& hwId) {
  if (hwId.length() != 16) return false;
  for (int i = 0; i < 16; i++) {
    char c = hwId.charAt(i);
    if (!((c >= '0' && c <= '9') || (c >= 'A' && c <= 'F'))) return false;
  }
  return true;
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
  return len > 0 && data[0] <= BIN_MAX_READINGS;
}
} // namespace SmartPacket

// ================= LoRa Pins (ESP32-S2 Mini) =================
#define LORA_SCK   7
#define LORA_MISO  8
#define LORA_MOSI  9
#define LORA_SS    6
#define LORA_RST   5
#define LORA_DIO0  -1
#define LORA_BAND  433E6

#define AES_KEY  "SmartPonic123456"
#define AUTH_KEY "AQUA77"

uint32_t gPacketCount = 0;

void aesCtr(const uint8_t* input, size_t len, const uint8_t key[16], const uint8_t nonce[16], uint8_t* output) {
  uint8_t counter[16]; memcpy(counter, nonce, 16);
  size_t ncOff = 0; uint8_t streamBlock[16] = {0};
  mbedtls_aes_context aes;
  mbedtls_aes_init(&aes);
  mbedtls_aes_setkey_enc(&aes, key, 128);
  mbedtls_aes_crypt_ctr(&aes, len, &ncOff, counter, streamBlock, input, output);
  mbedtls_aes_free(&aes);
}

void sendReply(const String& hardwareId, const String& cmd) {
  String payload = "auth=" + String(AUTH_KEY) + "&cmd=" + cmd + "&hardware_id=" + hardwareId;
  uint8_t key[16]; memcpy(key, AES_KEY, 16);
  uint8_t nonce[16]; SmartPacket::fillNonce(nonce);
  std::vector<uint8_t> encrypted(payload.length());
  aesCtr((const uint8_t*)payload.c_str(), payload.length(), key, nonce, encrypted.data());

  SmartPacket::Header hdr;
  memset(&hdr, 0, sizeof(hdr));
  hdr.magic = SmartPacket::MAGIC;
  hdr.version = SmartPacket::VERSION;
  memcpy(hdr.hardwareId, hardwareId.c_str(), 16);
  hdr.payloadLength = (uint16_t)encrypted.size();

  std::vector<uint8_t> packet;
  packet.resize(23 + 16 + encrypted.size() + 4);
  size_t offset = 0;
  memcpy(packet.data() + offset, &hdr, 23); offset += 23;
  memcpy(packet.data() + offset, nonce, 16); offset += 16;
  memcpy(packet.data() + offset, encrypted.data(), encrypted.size()); offset += encrypted.size();
  uint32_t crc = SmartPacket::crc32(packet.data(), offset);
  memcpy(packet.data() + offset, &crc, 4);

  LoRa.beginPacket();
  LoRa.write(packet.data(), packet.size());
  LoRa.endPacket();
  delay(20);
  LoRa.receive();
  Serial.print("  TX: "); Serial.print(packet.size()); Serial.print("B  "); Serial.println(cmd);
}

void parseBinary(const std::vector<uint8_t>& data) {
  uint8_t count = data[0];
  Serial.print("[BIN] "); Serial.print(count); Serial.println(" readings:");
  size_t pos = 1;
  for (uint8_t i = 0; i < count && pos + 4 <= data.size(); i++) {
    uint8_t pin = data[pos];
    uint8_t typeId = data[pos + 1];
    int16_t scaled = (int16_t)(data[pos + 2] | ((uint16_t)data[pos + 3] << 8));
    pos += 4;
    const char* name = SmartPacket::sensorTypeToName((SmartPacket::SensorType)typeId);
    String val;
    if (scaled == 0x7FFF) val = "nan";
    else if (scaled == 0x7FFE) val = "-127.0";
    else { char b[16]; float v = scaled / 10.0f; snprintf(b, sizeof(b), "%.1f", v); val = b; }
    Serial.print("  pin="); Serial.print(pin); Serial.print(" "); Serial.print(name); Serial.print("="); Serial.println(val);
  }
}

void setup() {
  Serial.begin(115200);
  delay(1000);

  Serial.println("\n================================");
  Serial.println("  SmartPonic HQ Minimal");
  Serial.println("================================");

  SPI.begin(LORA_SCK, LORA_MISO, LORA_MOSI, LORA_SS);
  LoRa.setPins(LORA_SS, LORA_RST, LORA_DIO0);

  if (!LoRa.begin(LORA_BAND)) {
    Serial.println("[LORA] FAILED!");
    return;
  }
  Serial.println("[LORA] OK");

  LoRa.setSyncWord(0xB4);
  LoRa.setSpreadingFactor(9);
  LoRa.setSignalBandwidth(125E3);
  LoRa.setCodingRate4(5);
  LoRa.setPreambleLength(12);
  LoRa.enableCrc();
  LoRa.setTxPower(20);
  LoRa.receive();

  Serial.println("[LORA] Ready");
  Serial.println("================================");
}

void loop() {
  int packetSize = LoRa.parsePacket();
  if (packetSize <= 0) { delay(5); return; }

  uint8_t buf[255];
  int len = 0;
  while (LoRa.available() && len < 255) buf[len++] = LoRa.read();
  LoRa.receive();

  if (len < 44) { Serial.print("[RX] Too short: "); Serial.println(len); return; }

  uint32_t magic; memcpy(&magic, buf, 4);
  if (magic != 0x31504653UL) { Serial.println("[RX] Bad magic"); return; }
  if (buf[4] != 0x01) { Serial.println("[RX] Bad version"); return; }

  char hwId[17] = {0}; memcpy(hwId, buf + 5, 16);
  String hardwareId = String(hwId);
  if (!SmartPacket::isValidHardwareId(hardwareId)) { Serial.println("[RX] Invalid HW ID"); return; }

  uint16_t payloadLen = buf[21] | ((uint16_t)buf[22] << 8);
  if ((size_t)len != 23 + 16 + payloadLen + 4) {
    Serial.print("[RX] Size mismatch"); return;
  }

  uint32_t calcCrc = SmartPacket::crc32(buf, len - 4);
  uint32_t recvCrc; memcpy(&recvCrc, buf + len - 4, 4);
  if (calcCrc != recvCrc) { Serial.println("[RX] CRC fail"); return; }

  uint8_t key[16]; memcpy(key, AES_KEY, 16);
  std::vector<uint8_t> plain(payloadLen);
  aesCtr(buf + 23 + 16, payloadLen, key, buf + 23, plain.data());

  gPacketCount++;
  Serial.println("\n═══════════════════════════════════");
  Serial.print("  RX #"); Serial.print(gPacketCount);
  Serial.print("  HW: "); Serial.print(hardwareId);
  Serial.print("  RSSI:"); Serial.print(LoRa.packetRssi());
  Serial.print("  SNR:"); Serial.println(LoRa.packetSnr());

  if (SmartPacket::isBinaryFormat(plain.data(), plain.size())) {
    Serial.print("  BINARY "); Serial.print(plain.size()); Serial.println(" bytes");
    parseBinary(plain);
    Serial.println("───────────────────────────────────");
    sendReply(hardwareId, "ack");
  } else {
    String text;
    for (size_t i = 0; i < plain.size(); i++) { if (plain[i] == 0) break; text += (char)plain[i]; }
    text.trim();
    Serial.print("  TEXT: "); Serial.println(text);
    String cmd = SmartPacket::getFieldValue(text, "cmd");
    if (cmd == "hello") {
      Serial.println("  >>> REGISTRATION");
      Serial.println("───────────────────────────────────");
      sendReply(hardwareId, "approve");
    } else {
      Serial.println("  Unknown");
      Serial.println("───────────────────────────────────");
    }
  }
}