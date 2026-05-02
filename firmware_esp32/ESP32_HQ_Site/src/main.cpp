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
#include <Preferences.h>
#include <mbedtls/aes.h>
#include <mbedtls/md.h>
#include "SmartPacket.h"

// ================= CONFIGURATION =================
// WiFi Settings - CHANGE THESE
const char* wifi_ssid = "YOUR_WIFI_SSID";
const char* wifi_password = "YOUR_WIFI_PASSWORD";

// PHP API URL - CHANGE THIS to your XAMPP IP
const char* api_url = "http://192.168.1.100/smartponic/receive_data.php";
const char* control_url = "http://192.168.1.100/smartponic/control_queue.php";

// NOTE: AES key, API key, and HMAC secret are now stored in flash Preferences
// Use serial commands to set them: SETKEYS,AES=xxx,API=yyy,HMAC=zzz
// Or use web UI / Flutter app to update

// Default fallback keys (used if flash storage is empty)
const char* DEFAULT_AES_KEY = "SmartPonic123456";
const char* DEFAULT_API_KEY = "smartponic-hq-key";
const char* DEFAULT_HMAC_SECRET = "smartponic-hq-signature-secret";

// Runtime key storage (loaded from flash at startup)
String runtimeAesKey = "SmartPonic123456";
String runtimeApiKey = "smartponic-hq-key";
String runtimeHmacSecret = "smartponic-hq-signature-secret";

// Preferences keys for secure storage
const char* prefsNamespace = "hq_secrets";
const char* aesKeyPrefKey = "aes_key";
const char* apiKeyPrefKey = "api_key";
const char* hmacSecretPrefKey = "hmac_secret";

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
unsigned long lastControlPollMs = 0;
constexpr unsigned long CONTROL_POLL_INTERVAL_MS = 4000UL;

// Track all node IDs seen via LoRa so relay polling covers every node
std::vector<int> knownNodeIds;

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
bool postJson(const char* url, const String& jsonBody, String& responseOut);
std::vector<unsigned char> encryptCtrPayload(const String& plainText, const uint8_t nonce[SmartPacket::NONCE_SIZE]);
std::vector<unsigned char> buildStructuredPacket(const String& plainText, uint8_t nodeId, uint8_t priority, uint8_t reportMode, uint32_t sequence);
bool sendBinaryPacket(const std::vector<unsigned char>& packetBytes);
void pollControlQueueIfNeeded();
void sendRelayCommandToNode(int nodeId, int relayId, const String& action, uint32_t commandId);
void handleControlAckIfPresent(const String& payload, int nodeId);

// Secure key storage functions
void loadSecureKeys();
bool saveAesKey(const String& value);
bool saveApiKey(const String& value);
bool saveHmacSecret(const String& value);
bool clearSecureKeys();
void handleHqSerialCommand(String input);

// Runtime auth key used for LoRa payload validation (must match Node's runtimeAuthKey)
String getRuntimeAuthKey() {
  // For backward compatibility, this returns the auth key portion
  // In a multi-node scenario, this could be looked up per-node
  return "AQUA77";
}

bool looksLikeValidPayload(const String& payload) {
  return payload.indexOf("auth=" + getRuntimeAuthKey() + "&") != -1 &&
         (payload.indexOf("&hardware_id=") != -1 || payload.indexOf("&node=") != -1) &&
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

// ================= SECURE KEY STORAGE =================
// Keys stored in ESP32 flash via Preferences namespace "hq_secrets"

void loadSecureKeys() {
  Preferences prefs;
  prefs.begin(prefsNamespace, true);
  runtimeAesKey = prefs.getString(aesKeyPrefKey, "");
  runtimeApiKey = prefs.getString(apiKeyPrefKey, "");
  runtimeHmacSecret = prefs.getString(hmacSecretPrefKey, "");
  prefs.end();

  if (runtimeAesKey.length() == 0) {
    runtimeAesKey = DEFAULT_AES_KEY;
    Serial.println("WARNING: Using default AES key - set custom key with SETKEYS command");
  }
  if (runtimeApiKey.length() == 0) {
    runtimeApiKey = DEFAULT_API_KEY;
    Serial.println("WARNING: Using default API key - set custom key with SETKEYS command");
  }
  if (runtimeHmacSecret.length() == 0) {
    runtimeHmacSecret = DEFAULT_HMAC_SECRET;
    Serial.println("WARNING: Using default HMAC secret - set custom key with SETKEYS command");
  }

  Serial.println("Secure keys loaded from flash storage");
  Serial.print("AES key configured: ");
  Serial.println(runtimeAesKey.length() > 0 ? "YES" : "NO");
  Serial.print("API key configured: ");
  Serial.println(runtimeApiKey.length() > 0 ? "YES" : "NO");
  Serial.print("HMAC secret configured: ");
  Serial.println(runtimeHmacSecret.length() > 0 ? "YES" : "NO");
}

bool saveAesKey(const String& value) {
  if (value.length() != 16) {
    Serial.println("ERROR: AES key must be exactly 16 characters");
    return false;
  }
  Preferences prefs;
  prefs.begin(prefsNamespace, false);
  prefs.putString(aesKeyPrefKey, value);
  prefs.end();
  runtimeAesKey = value;
  Serial.println("AES key saved to flash storage");
  return true;
}

bool saveApiKey(const String& value) {
  if (value.length() == 0 || value.length() > 128) {
    Serial.println("ERROR: API key must be 1-128 characters");
    return false;
  }
  Preferences prefs;
  prefs.begin(prefsNamespace, false);
  prefs.putString(apiKeyPrefKey, value);
  prefs.end();
  runtimeApiKey = value;
  Serial.println("API key saved to flash storage");
  return true;
}

bool saveHmacSecret(const String& value) {
  if (value.length() == 0 || value.length() > 128) {
    Serial.println("ERROR: HMAC secret must be 1-128 characters");
    return false;
  }
  Preferences prefs;
  prefs.begin(prefsNamespace, false);
  prefs.putString(hmacSecretPrefKey, value);
  prefs.end();
  runtimeHmacSecret = value;
  Serial.println("HMAC secret saved to flash storage");
  return true;
}

bool clearSecureKeys() {
  Preferences prefs;
  prefs.begin(prefsNamespace, false);
  prefs.remove(aesKeyPrefKey);
  prefs.remove(apiKeyPrefKey);
  prefs.remove(hmacSecretPrefKey);
  prefs.end();
  runtimeAesKey = DEFAULT_AES_KEY;
  runtimeApiKey = DEFAULT_API_KEY;
  runtimeHmacSecret = DEFAULT_HMAC_SECRET;
  Serial.println("Secure keys cleared - using defaults");
  return true;
}

void handleHqSerialCommand(String input) {
  if (input.length() == 0) return;

  Serial.println("\n>>> HQ Command: " + input);
  String command = input;
  command.toUpperCase();

  if (command == "HELP" || command == "?") {
    Serial.println("=== HQ AVAILABLE COMMANDS ===");
    Serial.println("HELP           - Show this help");
    Serial.println("SHOWKEYS       - Show current keys");
    Serial.println("SETKEYS,AES=xxx,API=yyy,HMAC=zzz - Set keys");
    Serial.println("CLEARKEYS      - Reset keys to defaults");
    Serial.println("WIFISTATUS     - Show WiFi connection status");
    Serial.println("QUEUE          - Show pending HTTP retry queue");
    Serial.println("");
    Serial.println("Example: SETKEYS,AES=SmartPonic123456,API=myapikey,HMAC=mysecret");
    return;
  }

  if (command == "SHOWKEYS") {
    Serial.println("=== SECURE KEYS ===");
    Serial.println("AES key: " + runtimeAesKey);
    Serial.println("API key: " + runtimeApiKey);
    Serial.println("HMAC secret: " + runtimeHmacSecret);
    return;
  }

  if (command == "CLEARKEYS") {
    clearSecureKeys();
    return;
  }

  if (command.startsWith("SETKEYS,")) {
    String args = input.substring(8);
    bool aesSet = false;
    bool apiSet = false;
    bool hmacSet = false;

    int aesPos = args.indexOf("AES=");
    int apiPos = args.indexOf("API=");
    int hmacPos = args.indexOf("HMAC=");

    if (aesPos >= 0) {
      int aesEnd = args.indexOf(",", aesPos);
      if (aesEnd < 0) aesEnd = args.length();
      String aesKey = args.substring(aesPos + 4, aesEnd);
      aesKey.trim();
      if (saveAesKey(aesKey)) aesSet = true;
    }

    if (apiPos >= 0) {
      int apiEnd = args.indexOf(",", apiPos);
      if (apiEnd < 0) apiEnd = args.length();
      String apiKey = args.substring(apiPos + 4, apiEnd);
      apiKey.trim();
      if (saveApiKey(apiKey)) apiSet = true;
    }

    if (hmacPos >= 0) {
      int hmacEnd = args.indexOf(",", hmacPos);
      if (hmacEnd < 0) hmacEnd = args.length();
      String hmacKey = args.substring(hmacPos + 5, hmacEnd);
      hmacKey.trim();
      if (saveHmacSecret(hmacKey)) hmacSet = true;
    }

    if (!aesSet && !apiSet && !hmacSet) {
      Serial.println("ERROR: Invalid format. Use: SETKEYS,AES=xxx,API=yyy,HMAC=zzz");
    } else {
      Serial.println("Keys updated:");
      if (aesSet) Serial.println("  AES: " + runtimeAesKey);
      if (apiSet) Serial.println("  API: " + runtimeApiKey);
      if (hmacSet) Serial.println("  HMAC: [configured]");
    }
    return;
  }

  if (command == "WIFISTATUS") {
    Serial.println("=== WIFI STATUS ===");
    Serial.println("Connected: " + String(WiFi.status() == WL_CONNECTED ? "YES" : "NO"));
    if (WiFi.status() == WL_CONNECTED) {
      Serial.println("IP: " + WiFi.localIP().toString());
      Serial.println("RSSI: " + String(WiFi.RSSI()) + " dBm");
    }
    return;
  }

  if (command == "QUEUE") {
    Serial.println("=== PENDING HTTP QUEUE ===");
    fs::FS* storage = getQueueStorage();
    if (storage == nullptr || !storage->exists(pendingQueuePath)) {
      Serial.println("(empty or no storage)");
      return;
    }
    File file = storage->open(pendingQueuePath, FILE_READ);
    if (!file) {
      Serial.println("(cannot open file)");
      return;
    }
    int count = 0;
    while (file.available()) {
      String line = file.readStringUntil('\n');
      line.trim();
      if (line.length() > 0) {
        count++;
        Serial.println("  " + String(count) + ": " + line.substring(0, min((unsigned int) 80, line.length())) + "...");
      }
    }
    file.close();
    Serial.println("Total: " + String(count) + " queued items");
    return;
  }

  Serial.println("Unknown command. Type HELP for available commands.");
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

  mbedtls_md_hmac_starts(&ctx, (const unsigned char*) runtimeHmacSecret.c_str(), runtimeHmacSecret.length());
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
  http.addHeader("X-API-Key", runtimeApiKey.c_str());
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

bool postJson(const char* url, const String& jsonBody, String& responseOut) {
  responseOut = "";
  if (WiFi.status() != WL_CONNECTED) {
    return false;
  }

  HTTPClient http;
  http.begin(url);
  http.addHeader("Content-Type", "application/json");

  String requestTimestamp = String((unsigned long) time(nullptr));
  String requestSignature = buildRequestSignature(requestTimestamp, jsonBody);
  http.addHeader("X-API-Key", runtimeApiKey.c_str());
  http.addHeader("X-Timestamp", requestTimestamp);
  http.addHeader("X-Signature", requestSignature);

  int httpCode = http.POST(jsonBody);
  responseOut = http.getString();
  http.end();
  return httpCode >= 200 && httpCode < 300;
}

std::vector<unsigned char> encryptCtrPayload(const String& plainText, const uint8_t nonce[SmartPacket::NONCE_SIZE]) {
  std::vector<unsigned char> output(plainText.length(), 0);
  std::vector<unsigned char> nonceCounter(SmartPacket::NONCE_SIZE, 0);
  memcpy(nonceCounter.data(), nonce, SmartPacket::NONCE_SIZE);
  size_t ncOffset = 0;
  unsigned char streamBlock[16] = {0};

  mbedtls_aes_context aes;
  mbedtls_aes_init(&aes);
  mbedtls_aes_setkey_enc(&aes, reinterpret_cast<const unsigned char *>(runtimeAesKey.c_str()), 128);
  mbedtls_aes_crypt_ctr(
      &aes,
      plainText.length(),
      &ncOffset,
      nonceCounter.data(),
      streamBlock,
      reinterpret_cast<const unsigned char *>(plainText.c_str()),
      output.data());
  mbedtls_aes_free(&aes);
  return output;
}

static void fillNonce(uint8_t nonce[SmartPacket::NONCE_SIZE], uint32_t sequence, uint8_t nodeId) {
  memset(nonce, 0, SmartPacket::NONCE_SIZE);
  uint32_t now = millis();
  uint32_t randomValue = esp_random();
  uint32_t node = nodeId;
  memcpy(nonce, &sequence, sizeof(sequence));
  memcpy(nonce + 4, &now, sizeof(now));
  memcpy(nonce + 8, &randomValue, sizeof(randomValue));
  memcpy(nonce + 12, &node, sizeof(node));
}

std::vector<unsigned char> buildStructuredPacket(const String& plainText, uint8_t nodeId, uint8_t priority, uint8_t reportMode, uint32_t sequence) {
  uint8_t nonce[SmartPacket::NONCE_SIZE];
  fillNonce(nonce, sequence, nodeId);
  std::vector<unsigned char> encryptedPayload = encryptCtrPayload(plainText, nonce);

  SmartPacket::Header header;
  header.magic = SmartPacket::MAGIC;
  header.version = SmartPacket::VERSION;
  header.nodeId = nodeId;
  header.priority = priority;
  header.reportMode = reportMode;
  header.payloadLength = (uint16_t) encryptedPayload.size();
  header.sequence = sequence;

  size_t bodyLength = sizeof(SmartPacket::Header) + SmartPacket::NONCE_SIZE + encryptedPayload.size();
  std::vector<unsigned char> packet(bodyLength + sizeof(uint32_t), 0);
  size_t offset = 0;

  memcpy(packet.data() + offset, &header, sizeof(header));
  offset += sizeof(header);
  memcpy(packet.data() + offset, nonce, SmartPacket::NONCE_SIZE);
  offset += SmartPacket::NONCE_SIZE;
  memcpy(packet.data() + offset, encryptedPayload.data(), encryptedPayload.size());
  offset += encryptedPayload.size();

  uint32_t checksum = SmartPacket::crc32((const uint8_t*) packet.data(), offset);
  memcpy(packet.data() + offset, &checksum, sizeof(checksum));
  return packet;
}

bool sendBinaryPacket(const std::vector<unsigned char>& packetBytes) {
  LoRa.beginPacket();
  size_t written = LoRa.write(packetBytes.data(), packetBytes.size());
  int result = LoRa.endPacket();
  LoRa.receive();
  return written == packetBytes.size() && result == 1;
}

void sendRelayCommandToNode(int nodeId, int relayId, const String& action, uint32_t commandId) {
  uint32_t seq = (uint32_t) millis();
  int state = (action == "ON") ? 1 : 0;
  String payload = "auth=AQUA77";
  payload += "&cmd=relay";
  payload += "&node=" + String(nodeId);
  payload += "&seq=" + String(seq);
  payload += "&command_id=" + String(commandId);
  payload += "&relay=" + String(relayId);
  payload += "&state=" + String(state);

  std::vector<unsigned char> packet = buildStructuredPacket(payload, (uint8_t) nodeId, SmartPacket::PRIORITY_HIGH, SmartPacket::REPORT_MODE_ABNORMAL, seq);
  bool ok = sendBinaryPacket(packet);
  Serial.print("Relay cmd send ");
  Serial.print(ok ? "OK" : "FAIL");
  Serial.print(" cmd_id=");
  Serial.println(commandId);

  if (ok) {
    String response;
    postJson(control_url, "{\"action\":\"mark_sent\",\"command_id\":" + String(commandId) + "}", response);
  }
}

void handleControlAckIfPresent(const String& payload, int nodeId) {
  if (getFieldValue(payload, "ack") != "relay") {
    return;
  }

  uint32_t commandId = (uint32_t) getFieldValue(payload, "command_id").toInt();
  String status = getFieldValue(payload, "status");
  String msg = getFieldValue(payload, "msg");
  status.toLowerCase();
  if (status != "done") {
    status = "failed";
  }

  String response;
  String body = "{\"action\":\"ack\",\"command_id\":" + String(commandId) +
                ",\"status\":\"" + status + "\"" +
                ",\"message\":\"node " + String(nodeId) + " " + msg + "\"}";
  postJson(control_url, body, response);
  Serial.print("Control ACK forwarded. cmd_id=");
  Serial.println(commandId);
}

void registerKnownNode(int nodeId) {
  if (nodeId <= 0) return;
  for (size_t i = 0; i < knownNodeIds.size(); i++) {
    if (knownNodeIds[i] == nodeId) return;
  }
  knownNodeIds.push_back(nodeId);
}

void pollControlQueueIfNeeded() {
  if (millis() - lastControlPollMs < CONTROL_POLL_INTERVAL_MS) {
    return;
  }
  lastControlPollMs = millis();

  if (WiFi.status() != WL_CONNECTED) {
    return;
  }

  // Always include node 1 as a baseline
  registerKnownNode(1);

  for (size_t ni = 0; ni < knownNodeIds.size(); ni++) {
    int pollNodeId = knownNodeIds[ni];
    String response;
    String body = "{\"action\":\"get_pending\",\"node_id\":" + String(pollNodeId) + ",\"limit\":2,\"mark_sent\":false}";
    if (!postJson(control_url, body, response)) {
      continue;
    }

    DynamicJsonDocument doc(1536);
    DeserializationError err = deserializeJson(doc, response);
    if (err) {
      continue;
    }
    if (!doc.containsKey("pending") || !doc["pending"].is<JsonArray>()) {
      continue;
    }

    JsonArray pending = doc["pending"].as<JsonArray>();
    for (JsonObject cmd : pending) {
      uint32_t commandId = (uint32_t) (cmd["id"] | 0);
      int nodeId = cmd["node_id"] | pollNodeId;
      int relayId = cmd["relay_id"] | 0;
      String action = cmd["action"] | "OFF";
      action.toUpperCase();
      if (commandId > 0) {
        sendRelayCommandToNode(nodeId, relayId, action, commandId);
      }
    }
  }
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
  String hardwareId = getFieldValue(sensorData, "hardware_id");
  if (hardwareId.length() == 0) {
    Serial.println("Packet has no hardware_id. Dropping.");
    return;
  }

  bool isLocationUpdate = getFieldValue(sensorData, "meta") == "location";

  if (isLocationUpdate) {
    String lat = getFieldValue(sensorData, "lat");
    String lon = getFieldValue(sensorData, "lon");
    String dist = getFieldValue(sensorData, "distance");
    if (lat.length() == 0 || lon.length() == 0) {
      Serial.println("Location update missing lat/lon. Dropping.");
      return;
    }
    String jsonBody = "{\"hardware_id\":\"" + hardwareId + "\"" +
                     ",\"rssi\":" + String(rssi) +
                     ",\"snr\":" + String(snr) +
                     ",\"priority\":\"" + SmartPacket::priorityLabel(priority) + "\"" +
                     ",\"report_mode\":\"" + SmartPacket::reportModeLabel(reportMode) + "\"" +
                     ",\"sequence\":" + String(sequence) +
                     ",\"event_type\":\"location_update\"" +
                     ",\"latitude\":" + lat +
                     ",\"longitude\":" + lon +
                     ",\"distance\":" + (dist.length() > 0 ? dist : "0") +
                     ",\"sensors\":[]}";
    sendJsonToAPI(jsonBody, true);
    return;
  }

  String jsonBody = "{\"hardware_id\":\"" + hardwareId + "\"" +
                    ",\"rssi\":" + String(rssi) +
                    ",\"snr\":" + String(snr) +
                    ",\"priority\":\"" + SmartPacket::priorityLabel(priority) + "\"" +
                    ",\"report_mode\":\"" + SmartPacket::reportModeLabel(reportMode) + "\"" +
                    ",\"sequence\":" + String(sequence) +
                    ",\"event_type\":\"telemetry\"" +
                    ",\"sensors\":[";

  bool firstSensor = true;
  int start = 0;
  while (true) {
    int amp = sensorData.indexOf('&', start);
    if (amp == -1) amp = sensorData.length();

    String segment = sensorData.substring(start, amp);
    bool metadataSegment = segment.startsWith("node=") ||
                           segment.startsWith("seq=") ||
                           segment.startsWith("auth=") ||
                           segment.startsWith("hardware_id=") ||
                           segment.startsWith("packet_part=") ||
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
  mbedtls_aes_setkey_enc(&aes, (const unsigned char*) runtimeAesKey.c_str(), 128);
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
  mbedtls_aes_setkey_dec(&aes, (const unsigned char*) runtimeAesKey.c_str(), 128);

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
  LoRa.receive();

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

  // Load secure keys from flash storage
  loadSecureKeys();

  Serial.println("System Ready!");
}

void loop() {
  retryQueuedHttpIfNeeded();
  pollControlQueueIfNeeded();

  // Handle serial commands for key management
  if (Serial.available()) {
    String input = Serial.readStringUntil('\n');
    input.trim();
    handleHqSerialCommand(input);
  }

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
    String hardwareId = getFieldValue(decryptedData, "hardware_id");
    if (hardwareId.length() > 0) {
      Serial.println("Node hardware ID: " + hardwareId);
    }

    if (!looksLikeValidPayload(decryptedData)) {
      Serial.println("Invalid payload signature. Packet ignored.");
      delay(10);
      return;
    }

    if (getFieldValue(decryptedData, "ack") == "relay") {
      handleControlAckIfPresent(decryptedData, nodeId);
      delay(10);
      return;
    }

    if (getFieldValue(decryptedData, "cmd") != "") {
      Serial.println("Control command packet received. Not forwarding to telemetry API.");
      delay(10);
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

      registerKnownNode(nodeId);

      // Send to PHP API
      sendToAPI(nodeId, rssi, snr, decryptedData, priority, reportMode, sequence);
    }
  }

  delay(10);
}
