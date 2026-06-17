// SmartPonic HQ Gateway - Full firmware
// Board: LOLIN S2 Mini | Port: COM16 | Flash: 4MB
#include <SPI.h>
#include <LoRa.h>
#include <WiFi.h>
#include <HTTPClient.h>
#include <Preferences.h>
#include <vector>
#include <mbedtls/aes.h>
#include <mbedtls/sha256.h>
#include <time.h>

// ================= SmartPacket =================
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
  uint32_t magic; uint8_t version; uint8_t hardwareId[16]; uint16_t payloadLength;
};
uint32_t crc32(const uint8_t* d, size_t l) {
  uint32_t c = 0xFFFFFFFF; for (size_t i = 0; i < l; i++) { c ^= d[i]; for (int b = 0; b < 8; b++) c = (c >> 1) ^ (0xEDB88320 & -(c & 1)); } return ~c;
}
void fillNonce(uint8_t n[16]) {
  memset(n, 0, 16); uint32_t now = millis(); memcpy(n + 4, &now, 4);
  uint32_t r1 = esp_random(), r2 = esp_random(), r3 = esp_random();
  memcpy(n + 8, &r1, 4); memcpy(n + 12, &r2, 4);
  n[0] ^= (r3 & 0xFF); n[1] ^= ((r3 >> 8) & 0xFF); n[2] ^= ((r3 >> 16) & 0xFF); n[3] ^= ((r3 >> 24) & 0xFF);
}
String getFieldValue(const String& d, const String& k) {
  String p = k + "="; int s = 0;
  while (true) { int a = d.indexOf('&', s); int e = (a < 0) ? d.length() : a;
    String seg = d.substring(s, e); if (seg.startsWith(p)) return seg.substring(p.length());
    if (a < 0) break; s = a + 1; } return "";
}
bool isValidHardwareId(const String& h) {
  if (h.length() != 16) return false; for (int i = 0; i < 16; i++) { char c = h.charAt(i);
    if (!((c >= '0' && c <= '9') || (c >= 'A' && c <= 'F'))) return false; } return true;
}
const char* sensorTypeToName(SensorType t) {
  switch (t) { case 0: return "Temperature"; case 1: return "Humidity"; case 2: return "WaterTemp";
    case 3: return "pH"; case 4: return "TDS"; case 5: return "Turbidity"; case 6: return "Rain";
    default: return "Unknown"; }
}
bool isBinaryFormat(const uint8_t* d, size_t l) { return l > 0 && d[0] <= BIN_MAX_READINGS; }
}

// ================= GLOBALS =================
const char* WIFI_SSID = "Kimie";
const char* WIFI_PASS = "00008888";
const char* API_URL   = "https://smartponic-dashboard.onrender.com/api/receive-data";

String gAesKey = "SmartPonic123456";
String gApiKey = "smartponic-hq-key";
String gHmacSecret = "smartponic-hq-signature-secret";
String gAuthKey = "AQUA77";

bool gWifiConnected = false;
bool gClockSynced = false;
unsigned long gWifiRetryMs = 0;
uint32_t gPacketRxCount = 0;
int gLastRssi = 0;
float gLastSnr = 0;

void aesCtr(const uint8_t* in, size_t len, const uint8_t key[16], const uint8_t nonce[16], uint8_t* out) {
  uint8_t ctr[16]; memcpy(ctr, nonce, 16); size_t off = 0; uint8_t sb[16] = {0};
  mbedtls_aes_context aes; mbedtls_aes_init(&aes);
  mbedtls_aes_setkey_enc(&aes, key, 128);
  mbedtls_aes_crypt_ctr(&aes, len, &off, ctr, sb, in, out);
  mbedtls_aes_free(&aes);
}

String sign(const String& ts, const String& body) {
  String in = ts + body + gHmacSecret;
  mbedtls_sha256_context ctx; mbedtls_sha256_init(&ctx);
  mbedtls_sha256_starts(&ctx, 0);
  mbedtls_sha256_update(&ctx, (const uint8_t*)in.c_str(), in.length());
  uint8_t h[32]; mbedtls_sha256_finish(&ctx, h); mbedtls_sha256_free(&ctx);
  String s; for (int i = 0; i < 32; i++) { if (h[i] < 0x10) s += "0"; s += String(h[i], HEX); }
  return s;
}

bool postJson(const String& url, const String& json, String& resp) {
  if (WiFi.status() != WL_CONNECTED) return false;
  time_t t = time(nullptr); String ts = (t > 1700000000) ? String((unsigned long)t) : String(millis());
  HTTPClient http; http.begin(url); http.setTimeout(5000);
  http.addHeader("Content-Type", "application/json");
  http.addHeader("X-API-Key", gApiKey); http.addHeader("X-Timestamp", ts);
  http.addHeader("X-Signature", sign(ts, json));
  int code = http.POST(json); resp = http.getString(); http.end();
  return (code >= 200 && code < 300);
}

void sendReply(const String& hwId, const String& cmd) {
  String payload = "auth=" + gAuthKey + "&cmd=" + cmd + "&hardware_id=" + hwId;
  uint8_t key[16]; memcpy(key, gAesKey.c_str(), 16);
  uint8_t nonce[16]; SmartPacket::fillNonce(nonce);
  std::vector<uint8_t> enc(payload.length());
  aesCtr((const uint8_t*)payload.c_str(), payload.length(), key, nonce, enc.data());
  SmartPacket::Header hdr; memset(&hdr, 0, sizeof(hdr));
  hdr.magic = SmartPacket::MAGIC; hdr.version = SmartPacket::VERSION;
  memcpy(hdr.hardwareId, hwId.c_str(), 16);
  hdr.payloadLength = (uint16_t)enc.size();
  std::vector<uint8_t> pkt;
  pkt.resize(23 + 16 + enc.size() + 4);
  size_t o = 0; memcpy(pkt.data()+o, &hdr, 23); o+=23;
  memcpy(pkt.data()+o, nonce, 16); o+=16;
  memcpy(pkt.data()+o, enc.data(), enc.size()); o+=enc.size();
  uint32_t crc = SmartPacket::crc32(pkt.data(), o);
  memcpy(pkt.data()+o, &crc, 4);
  LoRa.beginPacket(); LoRa.write(pkt.data(), pkt.size()); LoRa.endPacket();
  delay(20); LoRa.receive();
  Serial.print("  TX: "); Serial.print(pkt.size()); Serial.print("B  "); Serial.println(cmd);
}

String parseBinary(const std::vector<uint8_t>& data) {
  if (data.size() < 1) return "[]";
  uint8_t count = data[0]; String j = "[";
  size_t pos = 1; bool first = true;
  for (uint8_t i = 0; i < count && pos+4 <= data.size(); i++) {
    uint8_t pin = data[pos], typeId = data[pos+1];
    int16_t scaled = (int16_t)(data[pos+2] | ((uint16_t)data[pos+3] << 8)); pos += 4;
    String v; if (scaled == 0x7FFF) v = "nan"; else if (scaled == 0x7FFE) v = "-127.0";
    else { char b[16]; snprintf(b, 16, "%.1f", scaled/10.0f); v = b; }
    if (!first) j += ",";
    j += "{\"pin\":" + String(pin) + ",\"sensor\":\"" + String(SmartPacket::sensorTypeToName((SmartPacket::SensorType)typeId)) + "\",\"value\":\"" + v + "\"}";
    first = false; Serial.print("  "); Serial.print(SmartPacket::sensorTypeToName((SmartPacket::SensorType)typeId)); Serial.print("="); Serial.println(v);
  }
  j += "]"; return j;
}

void setup() {
  Serial.begin(115200); delay(2000);
  Serial.println("\n======= SMARTPONIC HQ =======");

  Preferences p; p.begin("hq_secrets", true);
  gAesKey = p.getString("aes_key", gAesKey); gApiKey = p.getString("api_key", gApiKey);
  gHmacSecret = p.getString("hmac", gHmacSecret); gAuthKey = p.getString("auth_key", gAuthKey); p.end();

  Serial.println("[WIFI] Connecting...");
  WiFi.mode(WIFI_STA); WiFi.begin(WIFI_SSID, WIFI_PASS);

  Serial.println("[LORA] Init...");
  SPI.begin(7, 9, 11, 12); LoRa.setPins(12, 5, -1);
  if (!LoRa.begin(433E6)) { Serial.println("[LORA] FAIL!"); return; }
  LoRa.setSyncWord(0xB4); LoRa.setSpreadingFactor(9);
  LoRa.setSignalBandwidth(125E3); LoRa.setCodingRate4(5);
  LoRa.setPreambleLength(12); LoRa.enableCrc(); LoRa.setTxPower(20);
  LoRa.receive();
  Serial.println("[LORA] Ready on 433MHz SF9");
}

void loop() {
  unsigned long now = millis();
  if (WiFi.status() == WL_CONNECTED) {
    if (!gWifiConnected) { gWifiConnected = true; Serial.print("[WIFI] "); Serial.println(WiFi.localIP());
      configTime(28800, 0, "pool.ntp.org"); delay(1000);
      if (time(nullptr) > 1700000000) { gClockSynced = true; Serial.println("[NTP] OK"); } }
  } else { if (gWifiConnected) { gWifiConnected = false; gClockSynced = false; }
    if (now - gWifiRetryMs > 10000) { gWifiRetryMs = now; WiFi.reconnect(); } }

  int pktSz = LoRa.parsePacket(); if (pktSz <= 0) { delay(5); return; }
  uint8_t buf[255]; int len = 0;
  while (LoRa.available() && len < 255) buf[len++] = LoRa.read();
  LoRa.receive();
  gLastRssi = LoRa.packetRssi(); gLastSnr = LoRa.packetSnr();

  if (len < 44) return;
  uint32_t magic; memcpy(&magic, buf, 4);
  if (magic != 0x31504653UL) return; if (buf[4] != 0x01) return;
  char hwId[17] = {0}; memcpy(hwId, buf+5, 16); String hardwareId = String(hwId);
  if (!SmartPacket::isValidHardwareId(hardwareId)) return;
  uint16_t plen = buf[21] | ((uint16_t)buf[22] << 8);
  if ((size_t)len != 23+16+plen+4) return;
  uint32_t cc = SmartPacket::crc32(buf, len-4); uint32_t rc; memcpy(&rc, buf+len-4, 4);
  if (cc != rc) return;
  uint8_t key[16]; memcpy(key, gAesKey.c_str(), 16);
  std::vector<uint8_t> plain(plen);
  aesCtr(buf+23+16, plen, key, buf+23, plain.data());
  gPacketRxCount++;
  Serial.println("\n=== RX #" + String(gPacketRxCount) + " HW:" + hardwareId + " RSSI:" + String(gLastRssi) + " SNR:" + String(gLastSnr));
  if (SmartPacket::isBinaryFormat(plain.data(), plain.size())) {
    Serial.println("  BINARY TELEMETRY");
    String sj = parseBinary(plain);
    sendReply(hardwareId, "ack");
    if (gWifiConnected) {
      String j = "{\"hardware_id\":\"" + hardwareId + "\",\"rssi\":" + String(gLastRssi) + ",\"snr\":" + String(gLastSnr,1) + ",\"event_type\":\"telemetry\",\"sensors\":" + sj + "}";
      String r; bool ok = postJson(String(API_URL), j, r);
      Serial.print("[HTTP] "); Serial.println(ok ? "OK: "+r : "FAIL");
    } else Serial.println("[HTTP] No WiFi - skip");
  } else {
    String txt;
    for (size_t i = 0; i < plain.size(); i++) { if (plain[i] == 0) break; txt += (char)plain[i]; }
    txt.trim(); Serial.print("  TEXT: "); Serial.println(txt);
    String cmd = SmartPacket::getFieldValue(txt, "cmd");
    if (cmd == "hello") { Serial.println("  >>> REGISTRATION"); sendReply(hardwareId, "approve"); }
    else sendReply(hardwareId, "ack");
  }
}