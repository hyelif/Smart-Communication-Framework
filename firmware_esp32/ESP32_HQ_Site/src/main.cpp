#include <Arduino.h>
#include <SPI.h>
#include <LoRa.h>
#include <WiFi.h>
#include <HTTPClient.h>
#include <ArduinoJson.h>
#include <time.h>
#include <vector>
#include <FS.h>
#include <SD.h>
#include <SPIFFS.h>
#include <mbedtls/aes.h>
#include <mbedtls/md.h>
#include "SmartPacket.h"

// ================= CONFIGURATION =================
// WiFi Settings - CHANGE THESE
const char* wifi_ssid = "YOUR_WIFI_SSID";
const char* wifi_password = "YOUR_WIFI_PASSWORD";

// PHP API URL - CHANGE THIS to your XAMPP IP
const char* api_url = "http://192.168.1.100/smartponic/receive_data.php";

// Encryption Key (must match Node)
const char* key = "SmartPonic123456";
const char* api_key = "smartponic-hq-key";
const char* api_hmac_secret = "smartponic-hq-signature-secret";
const char* pendingQueuePath = "/pending_http_queue.ndjson";
constexpr unsigned long HTTP_RETRY_INTERVAL_MS = 30000UL;

// ADD THIS: optional SD-backed buffering. Keep disabled until SD CS pin is known.
constexpr int SD_CS_PIN = -1;
bool sdBufferAvailable = false;
bool spiffsBufferAvailable = false;

// LoRa Pins (ESP32-S2 Mini)
#define LORA_SCK   7
#define LORA_MISO  8
#define LORA_MOSI  9
#define LORA_SS    6
#define LORA_RST   5
#define LORA_DIO0  -1
#define LORA_SYNC_WORD 0xB4

// Sequence tracking for data integrity
uint32_t lastSeq = 0;
unsigned long lastRetryMs = 0;

String bytesToHex(const std::vector<unsigned char>& bytes);
void syncClock();
bool sendJsonToAPI(const String& jsonBody, bool queueOnFailure);
void queueFailedJson(const String& jsonBody);
void retryQueuedHttpIfNeeded();
bool decryptStructuredPacket(const std::vector<unsigned char>& input, SmartPacket::Header& header, String& payload);
String decryptLegacyHex(const String& hexText);
String getFieldValue(const String& data, const String& key);
String buildRequestSignature(const String& timestamp, const String& body);
bool looksLikeValidPayload(const String& payload);
fs::FS* getQueueStorage();

bool looksLikeValidPayload(const String& payload) {
  return payload.indexOf("auth=AQUA77&") != -1 &&
         payload.indexOf("&node=") != -1 &&
         payload.indexOf("&seq=") != -1;
}

fs::FS* getQueueStorage() {
  if (sdBufferAvailable) {
    return &SD;
  }
  if (spiffsBufferAvailable) {
    return &SPIFFS;
  }
  return nullptr;
}

String bytesToHex(const std::vector<unsigned char>& bytes) {
  String hex;
  for (size_t i = 0; i < bytes.size(); i++) {
    if (bytes[i] < 0x10) {
      hex += "0";
    }
    hex += String(bytes[i], HEX);
  }
  return hex;
}

String buildRequestSignature(const String& timestamp, const String& body) {
  const String payloadToSign = timestamp + "\n" + body;
  unsigned char hmacOutput[32];
  mbedtls_md_context_t ctx;
  mbedtls_md_init(&ctx);
  const mbedtls_md_info_t* info = mbedtls_md_info_from_type(MBEDTLS_MD_SHA256);

  if (info == nullptr || mbedtls_md_setup(&ctx, info, 1) != 0) {
    mbedtls_md_free(&ctx);
    return "";
  }

  mbedtls_md_hmac_starts(&ctx, (const unsigned char*) api_hmac_secret, strlen(api_hmac_secret));
  mbedtls_md_hmac_update(&ctx, (const unsigned char*) payloadToSign.c_str(), payloadToSign.length());
  mbedtls_md_hmac_finish(&ctx, hmacOutput);
  mbedtls_md_free(&ctx);

  std::vector<unsigned char> hmacBytes(hmacOutput, hmacOutput + sizeof(hmacOutput));
  return bytesToHex(hmacBytes);
}

void syncClock() {
  configTime(8 * 3600, 0, "pool.ntp.org", "time.nist.gov", "time.google.com");

  time_t now = time(nullptr);
  int attempts = 0;
  while (now < 1700000000 && attempts < 10) {
    delay(300);
    now = time(nullptr);
    attempts++;
  }

  if (now >= 1700000000) {
    Serial.println("Clock synchronized for signed API requests.");
  } else {
    Serial.println("Clock sync pending. Signed requests may be rejected until time is available.");
  }
}

// ================= WIFI CONNECTION =================
void connectWiFi() {
  Serial.println("\nConnecting to WiFi...");
  WiFi.begin(wifi_ssid, wifi_password);

  int attempts = 0;
  while (WiFi.status() != WL_CONNECTED && attempts < 30) {
    delay(500);
    Serial.print(".");
    attempts++;
  }

  if (WiFi.status() == WL_CONNECTED) {
    Serial.println("\nWiFi Connected!");
    Serial.print("IP: ");
    Serial.println(WiFi.localIP());
    syncClock();
  } else {
    Serial.println("\nWiFi Failed!");
  }
}

// ================= SEND DATA TO PHP API =================
String getFieldValue(const String& data, const String& key) {
  int start = 0;
  const String prefix = key + "=";
  while (true) {
    int amp = data.indexOf('&', start);
    if (amp == -1) amp = data.length();

    String segment = data.substring(start, amp);
    if (segment.startsWith(prefix)) {
      return segment.substring(prefix.length());
    }

    if (amp >= data.length()) break;
    start = amp + 1;
  }

  return "";
}

void queueFailedJson(const String& jsonBody) {
  fs::FS* storage = getQueueStorage();
  if (storage == nullptr) {
    Serial.println("No local queue storage available.");
    return;
  }

  File file = storage->open(pendingQueuePath, FILE_APPEND);
  if (!file) {
    Serial.println("Failed to open retry queue file.");
    return;
  }
  file.println(jsonBody);
  file.close();
}

bool sendJsonToAPI(const String& jsonBody, bool queueOnFailure) {
  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("WiFi not connected, HTTP send postponed.");
    if (queueOnFailure) {
      queueFailedJson(jsonBody);
    }
    return false;
  }

  HTTPClient http;
  http.begin(api_url);
  http.addHeader("Content-Type", "application/json");

  String requestTimestamp = String((unsigned long) time(nullptr));
  String requestSignature = buildRequestSignature(requestTimestamp, jsonBody);
  http.addHeader("X-API-Key", api_key);
  http.addHeader("X-Timestamp", requestTimestamp);
  http.addHeader("X-Signature", requestSignature);

  int httpCode = http.POST(jsonBody);
  String response = http.getString();

  Serial.print("HTTP Response code: ");
  Serial.println(httpCode);
  Serial.println("Response: " + response);

  http.end();

  if (httpCode >= 200 && httpCode < 300) {
    return true;
  }

  if (queueOnFailure) {
    queueFailedJson(jsonBody);
  }
  return false;
}

void retryQueuedHttpIfNeeded() {
  if (millis() - lastRetryMs < HTTP_RETRY_INTERVAL_MS) {
    return;
  }
  lastRetryMs = millis();

  fs::FS* storage = getQueueStorage();
  if (storage == nullptr || !storage->exists(pendingQueuePath)) {
    return;
  }

  File file = storage->open(pendingQueuePath, FILE_READ);
  if (!file) {
    return;
  }

  std::vector<String> remaining;
  bool retriedOne = false;
  while (file.available()) {
    String line = file.readStringUntil('\n');
    line.trim();
    if (line.isEmpty()) continue;

    if (!retriedOne) {
      retriedOne = true;
      if (!sendJsonToAPI(line, false)) {
        remaining.push_back(line);
      } else {
        Serial.println("Queued HTTP payload forwarded successfully.");
      }
    } else {
      remaining.push_back(line);
    }
  }
  file.close();

  file = storage->open(pendingQueuePath, FILE_WRITE);
  if (!file) {
    return;
  }
  for (size_t i = 0; i < remaining.size(); i++) {
    file.println(remaining[i]);
  }
  file.close();
}

void sendToAPI(int nodeId, int rssi, float snr, String sensorData, uint8_t priority, uint8_t reportMode, uint32_t sequence) {
  bool isLocationUpdate = getFieldValue(sensorData, "meta") == "location";
  String jsonBody = "{\"node_id\":" + String(nodeId) +
                    ",\"rssi\":" + String(rssi) +
                    ",\"snr\":" + String(snr) +
                    ",\"priority\":\"" + SmartPacket::priorityLabel(priority) + "\"" +
                    ",\"report_mode\":\"" + SmartPacket::reportModeLabel(reportMode) + "\"" +
                    ",\"sequence\":" + String(sequence) +
                    ",\"event_type\":\"" + String(isLocationUpdate ? "location_update" : "telemetry") + "\"" +
                    ",\"sensors\":[";

  if (isLocationUpdate) {
    jsonBody = "{\"node_id\":" + String(nodeId) +
               ",\"rssi\":" + String(rssi) +
               ",\"snr\":" + String(snr) +
               ",\"priority\":\"" + SmartPacket::priorityLabel(priority) + "\"" +
               ",\"report_mode\":\"" + SmartPacket::reportModeLabel(reportMode) + "\"" +
               ",\"sequence\":" + String(sequence) +
               ",\"event_type\":\"location_update\"" +
               ",\"latitude\":" + getFieldValue(sensorData, "lat") +
               ",\"longitude\":" + getFieldValue(sensorData, "lon") +
               ",\"distance\":" + getFieldValue(sensorData, "distance") +
               ",\"sensors\":[]}";
    sendJsonToAPI(jsonBody, true);
    return;
  }

  bool firstSensor = true;
  int start = 0;
  while (true) {
    int amp = sensorData.indexOf('&', start);
    if (amp == -1) amp = sensorData.length();

    String segment = sensorData.substring(start, amp);
    bool metadataSegment = segment.startsWith("node=") ||
                           segment.startsWith("seq=") ||
                           segment.startsWith("auth=") ||
                           segment.startsWith("priority=") ||
                           segment.startsWith("mode=") ||
                           segment.startsWith("lat=") ||
                           segment.startsWith("lon=") ||
                           segment.startsWith("distance=") ||
                           segment.startsWith("sample_ms=") ||
                           segment.startsWith("report_ms=");

    if (segment.length() > 0 && !metadataSegment) {
      int firstEq = segment.indexOf('=');
      int lastEq = segment.lastIndexOf('=');

      if (firstEq != -1 && firstEq != lastEq) {
        String pin = segment.substring(0, firstEq);
        String sensor = segment.substring(firstEq + 1, lastEq);
        String val = segment.substring(lastEq + 1);

        if (!firstSensor) {
          jsonBody += ",";
        }
        jsonBody += "{\"pin\":" + pin + ",\"sensor\":\"" + sensor + "\",\"value\":\"" + val + "\"}";
        firstSensor = false;
      }
    }

    if (amp >= sensorData.length()) break;
    start = amp + 1;
  }

  jsonBody += "]}";
  sendJsonToAPI(jsonBody, true);
}

// ================= DATA PARSING =================
int parseNodeId(String data) {
  int start = 0;
  while (true) {
    int amp = data.indexOf('&', start);
    if (amp == -1) amp = data.length();

    String segment = data.substring(start, amp);
    if (segment.startsWith("node=")) {
      return segment.substring(5).toInt();
    }

    if (amp >= data.length()) break;
    start = amp + 1;
  }
  return 1;
}

int parseSeq(String data) {
  int start = 0;
  while (true) {
    int amp = data.indexOf('&', start);
    if (amp == -1) amp = data.length();

    String segment = data.substring(start, amp);
    if (segment.startsWith("seq=")) {
      return segment.substring(4).toInt();
    }

    if (amp >= data.length()) break;
    start = amp + 1;
  }
  return 0;
}

void parseData(String data) {
  Serial.println("\n--- Decrypted & Mapped Data ---");

  int start = 0;
  while (true) {
    int amp = data.indexOf('&', start);
    if (amp == -1) amp = data.length();

    String segment = data.substring(start, amp);
    if (segment.length() > 0) {

      int firstEq = segment.indexOf('=');
      int lastEq = segment.lastIndexOf('=');

      if (firstEq != -1 && firstEq != lastEq) {
        String pin = segment.substring(0, firstEq);
        String sensor = segment.substring(firstEq + 1, lastEq);
        String val = segment.substring(lastEq + 1);

        Serial.print("Pin: " + pin);
        Serial.print(" | Sensor: " + sensor);
        Serial.println(" | Value: " + val);
      } else if (firstEq != -1) {
        Serial.println("ID: " + segment);
      }
    }

    if (amp >= data.length()) break;
    start = amp + 1;
  }
}

// ================= DECRYPTION =================
bool decryptStructuredPacket(const std::vector<unsigned char>& input, SmartPacket::Header& header, String& payload) {
  const size_t minimumLength = sizeof(SmartPacket::Header) + SmartPacket::NONCE_SIZE + sizeof(uint32_t);
  if (input.size() < minimumLength) {
    return false;
  }

  memcpy(&header, input.data(), sizeof(SmartPacket::Header));
  if (header.magic != SmartPacket::MAGIC || header.version != SmartPacket::VERSION) {
    return false;
  }

  const size_t expectedLength = sizeof(SmartPacket::Header) + SmartPacket::NONCE_SIZE + header.payloadLength + sizeof(uint32_t);
  if (input.size() != expectedLength) {
    Serial.println("Structured packet size mismatch.");
    return false;
  }

  uint32_t receivedChecksum = 0;
  memcpy(&receivedChecksum, input.data() + input.size() - sizeof(uint32_t), sizeof(uint32_t));
  uint32_t calculatedChecksum = SmartPacket::crc32(input.data(), input.size() - sizeof(uint32_t));
  if (receivedChecksum != calculatedChecksum) {
    Serial.println("Structured packet checksum failed.");
    return false;
  }

  const uint8_t* nonce = input.data() + sizeof(SmartPacket::Header);
  const unsigned char* encryptedPayload = input.data() + sizeof(SmartPacket::Header) + SmartPacket::NONCE_SIZE;
  std::vector<unsigned char> decrypted(header.payloadLength, 0);
  std::vector<unsigned char> nonceCounter(SmartPacket::NONCE_SIZE, 0);
  memcpy(nonceCounter.data(), nonce, SmartPacket::NONCE_SIZE);

  size_t ncOffset = 0;
  unsigned char streamBlock[16] = {0};
  mbedtls_aes_context aes;
  mbedtls_aes_init(&aes);
  mbedtls_aes_setkey_enc(&aes, (const unsigned char*) key, 128);
  mbedtls_aes_crypt_ctr(
      &aes,
      header.payloadLength,
      &ncOffset,
      nonceCounter.data(),
      streamBlock,
      encryptedPayload,
      decrypted.data());
  mbedtls_aes_free(&aes);

  decrypted.push_back('\0');
  payload = String((char*)decrypted.data());
  return true;
}

String decryptLegacyHex(const String& hexText) {
  int len = hexText.length() / 2;
  std::vector<unsigned char> input(len, 0);
  std::vector<unsigned char> output(len + 1, 0);

  for (int i = 0; i < len; i++) {
    input[i] = (unsigned char) strtol(hexText.substring(i * 2, i * 2 + 2).c_str(), NULL, 16);
  }

  mbedtls_aes_context aes;
  mbedtls_aes_init(&aes);
  mbedtls_aes_setkey_dec(&aes, (const unsigned char*) key, 128);

  for (int i = 0; i < len; i += 16) {
    mbedtls_aes_crypt_ecb(&aes, MBEDTLS_AES_DECRYPT, input.data() + i, output.data() + i);
  }

  mbedtls_aes_free(&aes);

  int paddedLen = len;
  while (paddedLen > 0 && output[paddedLen - 1] == 0) {
    paddedLen--;
  }

  output[paddedLen] = '\0';
  return String((char*)output.data());
}

// ================= SETUP & LOOP =================
void setup() {
  Serial.begin(115200);
  delay(2000);

  // Initialize LoRa
  pinMode(LORA_RST, OUTPUT);
  digitalWrite(LORA_RST, LOW);
  delay(10);
  digitalWrite(LORA_RST, HIGH);

  SPI.begin(LORA_SCK, LORA_MISO, LORA_MOSI, LORA_SS);
  LoRa.setPins(LORA_SS, LORA_RST, LORA_DIO0);

  if (!LoRa.begin(433E6)) {
    Serial.println("LoRa failed");
    while (1);
  }

  LoRa.setSyncWord(LORA_SYNC_WORD);
  Serial.println("LoRa HQ READY");

  if (SD_CS_PIN >= 0) {
    pinMode(SD_CS_PIN, OUTPUT);
    digitalWrite(SD_CS_PIN, HIGH);
    sdBufferAvailable = SD.begin(SD_CS_PIN, SPI);
    Serial.println(sdBufferAvailable ? "SD queue storage ready." : "SD init failed, falling back if SPIFFS is available.");
  }

  spiffsBufferAvailable = SPIFFS.begin(true);
  if (!spiffsBufferAvailable && !sdBufferAvailable) {
    Serial.println("No queue storage available. HTTP retry queue disabled.");
  } else if (spiffsBufferAvailable && !sdBufferAvailable) {
    Serial.println("SPIFFS queue storage ready.");
  }

  // Connect to WiFi
  connectWiFi();

  Serial.println("System Ready!");
}

void loop() {
  retryQueuedHttpIfNeeded();

  int packetSize = LoRa.parsePacket();
  if (packetSize) {
    int rssi = LoRa.packetRssi();
    float snr = LoRa.packetSnr();
    std::vector<unsigned char> received(packetSize, 0);
    LoRa.readBytes(received.data(), packetSize);

    SmartPacket::Header structuredHeader = {};
    String decryptedData = "";
    bool isStructured = false;
    uint8_t priority = SmartPacket::PRIORITY_LOW;
    uint8_t reportMode = SmartPacket::REPORT_MODE_NORMAL;
    uint32_t sequence = 0;
    int nodeId = 1;

    if (decryptStructuredPacket(received, structuredHeader, decryptedData)) {
      isStructured = true;
      priority = structuredHeader.priority;
      reportMode = structuredHeader.reportMode;
      sequence = structuredHeader.sequence;
      nodeId = structuredHeader.nodeId;
    } else {
      String legacyHex = "";
      for (size_t i = 0; i < received.size(); i++) {
        legacyHex += (char) received[i];
      }
      decryptedData = decryptLegacyHex(legacyHex);
      sequence = parseSeq(decryptedData);
      nodeId = parseNodeId(decryptedData);
    }

    Serial.println("\n========== NEW PACKET ==========");
    Serial.print("Transport: ");
    Serial.println(isStructured ? "structured-binary" : "legacy-hex");
    Serial.print("Packet bytes: ");
    Serial.println(packetSize);
    Serial.print("Priority: ");
    Serial.println(SmartPacket::priorityLabel(priority));
    Serial.print("Report mode: ");
    Serial.println(SmartPacket::reportModeLabel(reportMode));
    Serial.println("RSSI: " + String(rssi) + " | SNR: " + String(snr));
    Serial.println("Decrypted payload length: " + String(decryptedData.length()));

    if (!looksLikeValidPayload(decryptedData)) {
      Serial.println("Invalid payload signature. Packet ignored.");
      return;
    }

    // Parse and display
    parseData(decryptedData);

    // Sequence validation for data integrity
    if (sequence <= lastSeq) {
      Serial.println("Duplicate/Reject - seq: " + String(sequence) + " <= lastSeq: " + String(lastSeq));
    } else {
      lastSeq = sequence;
      Serial.println("Valid seq: " + String(sequence));

      // Send to PHP API
      sendToAPI(nodeId, rssi, snr, decryptedData, priority, reportMode, sequence);
    }
  }

  delay(10);
}
