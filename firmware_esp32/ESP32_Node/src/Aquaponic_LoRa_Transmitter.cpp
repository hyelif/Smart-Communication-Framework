#include <Arduino.h>
#include <SPI.h>
#include <LoRa.h>
#include <WiFi.h>
#include <WebServer.h>
#include <ArduinoJson.h>
#include <Preferences.h>
#include <vector>
#include <cmath>
#include <DHT.h>
#include <OneWire.h>
#include <DallasTemperature.h>
#include <mbedtls/aes.h>
#include "SmartPacket.h"

// ================= FORWARD DECLARATIONS =================
float readPH(int raw);
float readTDS(int raw);
String readTurbidity(int raw);
String canonicalSensorName(String sensor);
void handleSerialCommand(String input);

// ================= SETTINGS =================
const char *key = "SmartPonic123456";
const char *ssid = "AQUA_NODE";
const char *password = "12345678";

WebServer server(80);
Preferences prefs;
bool loraReady = false;
uint32_t packetSeq = 0;  // Sequence counter for data integrity
const char *nodeKeyHeader = "X-Node-Key";
const char *configNamespace = "cfg";
const char *configJsonPrefKey = "json";
const char *nodeSecurityPrefKey = "node_key";

// ADD THIS: smart communication timing profile
constexpr unsigned long SAMPLE_INTERVAL_MS = 5000UL;
constexpr unsigned long REPORT_INTERVAL_NORMAL_MS = 15UL * 60UL * 1000UL;
constexpr unsigned long REPORT_INTERVAL_ABNORMAL_MS = 5UL * 60UL * 1000UL;
constexpr unsigned long REPORT_INTERVAL_CRITICAL_MS = 60UL * 1000UL;
constexpr unsigned long RETRY_INTERVAL_MS = 30000UL;
constexpr size_t MAX_PENDING_PACKETS = 12;

// LoRa Pins
#define LORA_SCK 18
#define LORA_MISO 19
#define LORA_MOSI 23
#define LORA_SS 5
#define LORA_RST 14
#define LORA_DIO0 -1
#define LORA_SYNC_WORD 0xB4
const String SECRET_KEY = "AQUA77";

struct GPIOConfig {
  int pin;
  String type;
  String sensor;
  String label;
};

// ADD THIS: node-side metadata provided by the app / range testing workflow
struct NodeRuntimeSettings {
  uint8_t nodeId = 1;
  float latitude = 0.0f;
  float longitude = 0.0f;
  float distanceMeters = 0.0f;
};

// ADD THIS: cache sampled values every 5 seconds
struct SensorSegment {
  String segment;
  String sensorName;
  String rawValue;
  int pin;
};

// ADD THIS: FIFO retry queue item for failed LoRa packets
struct PendingPacket {
  std::vector<uint8_t> bytes;
  uint8_t priority;
  uint8_t reportMode;
  uint32_t sequence;
  unsigned long queuedAtMs;
};

std::vector<GPIOConfig> configList;
std::vector<SensorSegment> latestSegments;
std::vector<PendingPacket> pendingPackets;
NodeRuntimeSettings runtimeSettings;
#define MAX_SENSORS 15

// Sensor Pointers
DHT *dhtSensors[MAX_SENSORS];
OneWire *oneWireSensors[MAX_SENSORS];
DallasTemperature *tempSensors[MAX_SENSORS];

unsigned long lastSampleMs = 0;
unsigned long lastReportMs = 0;
unsigned long lastRetryMs = 0;
bool criticalDispatchPending = false;
bool metadataSyncPending = false;
uint8_t currentPriority = SmartPacket::PRIORITY_LOW;
uint8_t currentReportMode = SmartPacket::REPORT_MODE_NORMAL;
unsigned long currentReportIntervalMs = REPORT_INTERVAL_NORMAL_MS;

const int safePins[] = {
    4,  13, 16, 17, 21, 22, 25, 26,
    27, 32, 33, 34, 35, 36, 39,
};

bool isSafePin(int pin) {
  for (size_t i = 0; i < sizeof(safePins) / sizeof(safePins[0]); i++) {
    if (safePins[i] == pin) {
      return true;
    }
  }
  return false;
}

String boardName() {
#if defined(CONFIG_IDF_TARGET_ESP32S3)
  return "ESP32-S3 Dev Module";
#elif defined(CONFIG_IDF_TARGET_ESP32S2)
  return "ESP32-S2 Dev Module";
#elif defined(CONFIG_IDF_TARGET_ESP32C3)
  return "ESP32-C3 Dev Module";
#elif defined(CONFIG_IDF_TARGET_ESP32)
  return "ESP32 Dev Module";
#else
  return "ESP32";
#endif
}

void addCommonHeaders() {
  server.sendHeader("Access-Control-Allow-Origin", "*");
  server.sendHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
  server.sendHeader("Access-Control-Allow-Headers", "Content-Type, X-Node-Key");
  server.sendHeader("Cache-Control", "no-store");
}

String loadNodeSecurityKey() {
  prefs.begin(configNamespace, true);
  String value = prefs.getString(nodeSecurityPrefKey, "");
  prefs.end();
  return value;
}

void saveNodeSecurityKey(const String &value) {
  prefs.begin(configNamespace, false);
  prefs.putString(nodeSecurityPrefKey, value);
  prefs.end();
}

String readRequestSecurityKey() {
  String requestKey;

  if (server.hasHeader(nodeKeyHeader)) {
    requestKey = server.header(nodeKeyHeader);
  }

  if (requestKey.isEmpty() && server.hasArg("key")) {
    requestKey = server.arg("key");
  }

  requestKey.trim();
  return requestKey;
}

bool requireAuthorizedNodeKey(bool allowBootstrap) {
  String requestKey = readRequestSecurityKey();
  String nodeKey = loadNodeSecurityKey();

  if (requestKey.isEmpty()) {
    addCommonHeaders();
    server.send(
        401,
        "application/json",
        "{\"status\":\"missing_key\",\"message\":\"Security key required\"}");
    return false;
  }

  if (nodeKey.isEmpty()) {
    if (allowBootstrap) {
      return true;
    }

    addCommonHeaders();
    server.send(
        403,
        "application/json",
        "{\"status\":\"key_not_configured\",\"message\":\"Set a key with a deploy request first\"}");
    return false;
  }

  if (requestKey != nodeKey) {
    addCommonHeaders();
    server.send(
        403,
        "application/json",
        "{\"status\":\"invalid_key\",\"message\":\"Security key mismatch\"}");
    return false;
  }

  return true;
}

// ADD THIS: sensor/communication prioritization helpers
uint8_t escalatePriority(uint8_t current, uint8_t candidate) {
  return candidate > current ? candidate : current;
}

uint8_t classifySensorPriority(const String &sensorName, const String &rawValue) {
  String trimmed = rawValue;
  trimmed.trim();

  if ((sensorName == "Temperature" || sensorName == "Humidity") && trimmed.equalsIgnoreCase("nan")) {
    return SmartPacket::PRIORITY_HIGH;
  }

  if (sensorName == "WaterTemp" && trimmed.toFloat() == -127.0f) {
    return SmartPacket::PRIORITY_HIGH;
  }

  if (!trimmed.equalsIgnoreCase("nan")) {
    const float value = trimmed.toFloat();

    if (sensorName == "Temperature") {
      if (value < 18.0f || value > 35.0f) return SmartPacket::PRIORITY_HIGH;
      if (value < 22.0f || value > 32.0f) return SmartPacket::PRIORITY_MEDIUM;
    } else if (sensorName == "Humidity") {
      if (value < 30.0f || value > 90.0f) return SmartPacket::PRIORITY_HIGH;
      if (value < 40.0f || value > 80.0f) return SmartPacket::PRIORITY_MEDIUM;
    } else if (sensorName == "WaterTemp") {
      if (value < 15.0f || value > 32.0f) return SmartPacket::PRIORITY_HIGH;
      if (value < 20.0f || value > 30.0f) return SmartPacket::PRIORITY_MEDIUM;
    } else if (sensorName == "pH") {
      if (value < 5.5f || value > 8.5f) return SmartPacket::PRIORITY_HIGH;
      if (value < 6.0f || value > 8.0f) return SmartPacket::PRIORITY_MEDIUM;
    } else if (sensorName == "TDS") {
      if (value > 1200.0f) return SmartPacket::PRIORITY_HIGH;
      if (value > 800.0f) return SmartPacket::PRIORITY_MEDIUM;
    } else if (sensorName == "Turbidity") {
      if (value > 1000.0f) return SmartPacket::PRIORITY_HIGH;
      if (value > 300.0f) return SmartPacket::PRIORITY_MEDIUM;
    } else if (sensorName == "Rain") {
      if ((int) value == 1) return SmartPacket::PRIORITY_MEDIUM;
    }
  }

  return SmartPacket::PRIORITY_LOW;
}

void updateReportMode(uint8_t priority) {
  currentPriority = priority;

  if (priority == SmartPacket::PRIORITY_HIGH) {
    currentReportMode = SmartPacket::REPORT_MODE_CRITICAL;
    currentReportIntervalMs = REPORT_INTERVAL_CRITICAL_MS;
    criticalDispatchPending = true;
  } else if (priority == SmartPacket::PRIORITY_MEDIUM) {
    currentReportMode = SmartPacket::REPORT_MODE_ABNORMAL;
    currentReportIntervalMs = REPORT_INTERVAL_ABNORMAL_MS;
  } else {
    currentReportMode = SmartPacket::REPORT_MODE_NORMAL;
    currentReportIntervalMs = REPORT_INTERVAL_NORMAL_MS;
  }
}

String canonicalSensorName(String sensor) {
  sensor.trim();
  String normalized = sensor;
  normalized.toUpperCase();

  if (normalized == "DHT22") return "DHT22";
  if (normalized == "WATERTEMP") return "WaterTemp";
  if (normalized == "PH") return "pH";
  if (normalized == "TDS") return "TDS";
  if (normalized == "TURBIDITY") return "Turbidity";
  if (normalized == "RAIN") return "Rain";

  return sensor;
}

// ================= CONFIG LOGIC =================

void applyConfig(JsonArray arr) {
  for (int i = 0; i < MAX_SENSORS; i++) {
    if (dhtSensors[i]) {
      delete dhtSensors[i];
      dhtSensors[i] = nullptr;
    }
    if (tempSensors[i]) {
      delete tempSensors[i];
      tempSensors[i] = nullptr;
      delete oneWireSensors[i];
      oneWireSensors[i] = nullptr;
    } else if (oneWireSensors[i]) {
      delete oneWireSensors[i];
      oneWireSensors[i] = nullptr;
    }
  }

  configList.clear();
  int idx = 0;

  for (JsonObject obj : arr) {
    if (idx >= MAX_SENSORS) {
      break;
    }

    int pin = obj["pin"] | -1;
    String sensor = canonicalSensorName(obj["sensor"] | "");
    String type = obj["type"] | "";
    String label = obj["label"] | "";
    label.trim();

    if (!isSafePin(pin)) {
      continue;
    }

    bool duplicate = false;
    for (size_t existingIndex = 0; existingIndex < configList.size(); existingIndex++) {
      if (configList[existingIndex].pin == pin && configList[existingIndex].sensor == sensor) {
        duplicate = true;
        break;
      }
    }
    if (duplicate) {
      continue;
    }

    configList.push_back({pin, type, sensor, label});

    if (sensor == "DHT22") {
      dhtSensors[idx] = new DHT(pin, DHT22);
      dhtSensors[idx]->begin();
    } else if (sensor == "WaterTemp") {
      oneWireSensors[idx] = new OneWire(pin);
      tempSensors[idx] = new DallasTemperature(oneWireSensors[idx]);
      tempSensors[idx]->begin();
    }

    if (type == "DO") {
      pinMode(pin, OUTPUT);
    } else {
      pinMode(pin, INPUT);
    }

    Serial.print("Configured GPIO ");
    Serial.print(pin);
    Serial.print(" as ");
    if (!label.isEmpty()) {
      Serial.print(label);
      Serial.print(" ");
    }
    Serial.print(sensor);
    Serial.print(" [");
    Serial.print(type);
    Serial.println("]");

    idx++;
  }
}

void loadRuntimeSettingsFromDocument(JsonDocument &doc) {
  runtimeSettings.nodeId = (uint8_t) max(1, (int) ((int) (doc["nodeId"] | runtimeSettings.nodeId)));
  runtimeSettings.latitude = doc["latitude"] | runtimeSettings.latitude;
  runtimeSettings.longitude = doc["longitude"] | runtimeSettings.longitude;
  runtimeSettings.distanceMeters = doc["distance"] | runtimeSettings.distanceMeters;
}

void handleRoot() {
  Serial.println("HTTP GET /");
  addCommonHeaders();

  String html =
      "<!doctype html><html><head><meta name='viewport' "
      "content='width=device-width,initial-scale=1'>"
      "<title>SmartPonic Node</title>"
      "<style>"
      "body{font-family:Arial,sans-serif;background:#f5f8f5;color:#17312a;"
      "padding:24px;line-height:1.5;}"
      ".card{max-width:560px;background:#ffffff;border-radius:20px;"
      "padding:20px;box-shadow:0 14px 30px rgba(23,49,42,0.10);}"
      "code{background:#eef4ef;padding:2px 6px;border-radius:8px;}"
      "a{color:#0d7a49;text-decoration:none;font-weight:600;}"
      "h1{margin:0 0 10px;font-size:28px;}"
      "p{margin:8px 0;}"
      "ul{padding-left:18px;}"
      "</style></head><body><div class='card'>"
      "<h1>SmartPonic Node</h1>"
      "<p>Wi-Fi AP is running and the local web server is alive.</p>"
      "<p><strong>SSID:</strong> <code>" +
      String(ssid) +
      "</code></p>"
      "<p><strong>IP:</strong> <code>" +
      WiFi.softAPIP().toString() +
      "</code></p>"
      "<p><strong>Locked:</strong> <code>" +
      String(loadNodeSecurityKey().isEmpty() ? "no" : "yes") +
      "</code></p>"
      "<p><strong>Node ID:</strong> <code>" +
      String(runtimeSettings.nodeId) +
      "</code></p>"
      "<p><strong>Distance:</strong> <code>" +
      String(runtimeSettings.distanceMeters, 1) +
      " m</code></p>"
      "<p><strong>Clients:</strong> <code>" +
      String(WiFi.softAPgetStationNum()) +
      "</code></p>"
      "<ul>"
      "<li><a href='/health'>/health</a> for quick JSON status</li>"
      "<li><a href='/config'>/config</a> for saved config JSON</li>"
      "</ul>"
      "</div></body></html>";

  server.send(200, "text/html", html);
}

void handleHealth() {
  Serial.println("HTTP GET /health");
  addCommonHeaders();

  const uint32_t freeHeapKb = ESP.getFreeHeap() / 1024;
  const uint32_t uptimeSec = millis() / 1000;
  String body = "{\"status\":\"ok\",\"ssid\":\"" + String(ssid) +
                "\",\"ip\":\"" + WiFi.softAPIP().toString() +
                "\",\"board\":\"" + boardName() +
                "\",\"chipModel\":\"" + String(ESP.getChipModel()) +
                "\",\"chipRevision\":" + String(ESP.getChipRevision()) +
                ",\"heapKb\":" + String(freeHeapKb) +
                ",\"uptimeSec\":" + String(uptimeSec) +
                ",\"locked\":" +
                String(loadNodeSecurityKey().isEmpty() ? "false" : "true") +
                ",\"clients\":" + String(WiFi.softAPgetStationNum()) +
                ",\"configCount\":" + String(configList.size()) +
                ",\"maxConfig\":" + String(MAX_SENSORS) +
                ",\"nodeId\":" + String(runtimeSettings.nodeId) +
                ",\"latitude\":" + String(runtimeSettings.latitude, 6) +
                ",\"longitude\":" + String(runtimeSettings.longitude, 6) +
                ",\"distance\":" + String(runtimeSettings.distanceMeters, 1) +
                ",\"priority\":\"" + SmartPacket::priorityLabel(currentPriority) + "\"" +
                ",\"reportMode\":\"" + SmartPacket::reportModeLabel(currentReportMode) + "\"" +
                ",\"pendingQueue\":" + String(pendingPackets.size()) + "}";

  server.send(200, "application/json", body);
}

void handleOptions() {
  Serial.println("HTTP OPTIONS /config");
  addCommonHeaders();
  server.send(200, "text/plain", "");
}

void handleGetConfig() {
  Serial.println("HTTP GET /config");
  if (!requireAuthorizedNodeKey(false)) {
    return;
  }

  prefs.begin(configNamespace, true);
  String json = prefs.getString(configJsonPrefKey, "{\"config\":[]}");
  prefs.end();

  addCommonHeaders();
  server.send(200, "application/json", json);
}

void handlePostConfig() {
  Serial.println("HTTP POST /config");
  if (!requireAuthorizedNodeKey(true)) {
    return;
  }

  addCommonHeaders();

  if (!server.hasArg("plain")) {
    server.send(400, "application/json", "{\"status\":\"no body\"}");
    return;
  }

  String body = server.arg("plain");
  Serial.println("Received new config from app:");
  Serial.println(body);

  DynamicJsonDocument doc(4096);
  DeserializationError error = deserializeJson(doc, body);

  if (error) {
    Serial.print("JSON parse failed: ");
    Serial.println(error.f_str());
    server.send(400, "application/json", "{\"status\":\"parse error\"}");
    return;
  }

  if (!doc.containsKey("config")) {
    server.send(400, "application/json", "{\"status\":\"missing config key\"}");
    return;
  }

  loadRuntimeSettingsFromDocument(doc);
  JsonArray arr = doc["config"];
  applyConfig(arr);
  metadataSyncPending = true;

  prefs.begin(configNamespace, false);
  prefs.putString(configJsonPrefKey, body);
  prefs.end();

  String nodeKey = loadNodeSecurityKey();
  if (nodeKey.isEmpty()) {
    saveNodeSecurityKey(readRequestSecurityKey());
    Serial.println("Security key saved to node.");
  }

  Serial.println("Config applied and saved to flash.");
  server.send(200, "application/json", "{\"status\":\"ok\"}");
}

void handleNotFound() {
  Serial.print("HTTP 404: ");
  Serial.println(server.uri());
  addCommonHeaders();
  server.send(
      404,
      "application/json",
      "{\"status\":\"not found\",\"hint\":\"use /, /health or /config\"}");
}

// ================= LORA & SMART COMMUNICATION =================

void appendSegment(std::vector<SensorSegment> &segments, int pin, const String &sensorName, const String &rawValue) {
  SensorSegment segment;
  segment.pin = pin;
  segment.sensorName = sensorName;
  segment.rawValue = rawValue;
  segment.segment = String(pin) + "=" + sensorName + "=" + rawValue;
  segments.push_back(segment);
}

void sampleSensors() {
  std::vector<SensorSegment> sampledSegments;
  uint8_t highestPriority = SmartPacket::PRIORITY_LOW;

  for (size_t i = 0; i < configList.size(); i++) {
    auto c = configList[i];

    if (c.sensor == "DHT22" && dhtSensors[i]) {
      float temp = dhtSensors[i]->readTemperature();
      float humidity = dhtSensors[i]->readHumidity();
      String tempValue = isnan(temp) ? "nan" : String(temp, 1);
      String humidityValue = isnan(humidity) ? "nan" : String(humidity, 1);

      appendSegment(sampledSegments, c.pin, "Temperature", tempValue);
      appendSegment(sampledSegments, c.pin, "Humidity", humidityValue);
      highestPriority = escalatePriority(highestPriority, classifySensorPriority("Temperature", tempValue));
      highestPriority = escalatePriority(highestPriority, classifySensorPriority("Humidity", humidityValue));
    } else if (c.sensor == "WaterTemp" && tempSensors[i]) {
      tempSensors[i]->requestTemperatures();
      String value = String(tempSensors[i]->getTempCByIndex(0), 1);
      appendSegment(sampledSegments, c.pin, "WaterTemp", value);
      highestPriority = escalatePriority(highestPriority, classifySensorPriority("WaterTemp", value));
    } else if (c.sensor == "pH") {
      String value = String(readPH(analogRead(c.pin)), 2);
      appendSegment(sampledSegments, c.pin, "pH", value);
      highestPriority = escalatePriority(highestPriority, classifySensorPriority("pH", value));
    } else if (c.sensor == "TDS") {
      String value = String(readTDS(analogRead(c.pin)), 2);
      appendSegment(sampledSegments, c.pin, "TDS", value);
      highestPriority = escalatePriority(highestPriority, classifySensorPriority("TDS", value));
    } else if (c.sensor == "Turbidity") {
      String value = readTurbidity(analogRead(c.pin));
      appendSegment(sampledSegments, c.pin, "Turbidity", value);
      highestPriority = escalatePriority(highestPriority, classifySensorPriority("Turbidity", value));
    } else if (c.sensor == "Rain") {
      String value = String(digitalRead(c.pin));
      appendSegment(sampledSegments, c.pin, "Rain", value);
      highestPriority = escalatePriority(highestPriority, classifySensorPriority("Rain", value));
    }
  }

  latestSegments = sampledSegments;
  updateReportMode(highestPriority);
}

String buildPlainPayload(uint32_t sequence, uint8_t priority, uint8_t reportMode) {
  String payload = "auth=" + SECRET_KEY + "&";

  for (size_t i = 0; i < latestSegments.size(); i++) {
    payload += latestSegments[i].segment + "&";
  }

  payload += "node=" + String(runtimeSettings.nodeId);
  payload += "&seq=" + String(sequence);
  payload += "&priority=" + SmartPacket::priorityLabel(priority);
  payload += "&mode=" + SmartPacket::reportModeLabel(reportMode);
  payload += "&sample_ms=" + String(SAMPLE_INTERVAL_MS);
  payload += "&report_ms=" + String(currentReportIntervalMs);
  return payload;
}

String buildLocationSyncPayload(uint32_t sequence) {
  String payload = "auth=" + SECRET_KEY;
  payload += "&meta=location";
  payload += "&node=" + String(runtimeSettings.nodeId);
  payload += "&seq=" + String(sequence);
  payload += "&lat=" + String(runtimeSettings.latitude, 6);
  payload += "&lon=" + String(runtimeSettings.longitude, 6);
  payload += "&distance=" + String(runtimeSettings.distanceMeters, 1);
  return payload;
}

void fillNonce(uint8_t nonce[SmartPacket::NONCE_SIZE], uint32_t sequence) {
  memset(nonce, 0, SmartPacket::NONCE_SIZE);
  uint32_t now = millis();
  uint32_t randomValue = esp_random();
  uint32_t nodeId = runtimeSettings.nodeId;
  memcpy(nonce, &sequence, sizeof(sequence));
  memcpy(nonce + 4, &now, sizeof(now));
  memcpy(nonce + 8, &randomValue, sizeof(randomValue));
  memcpy(nonce + 12, &nodeId, sizeof(nodeId));
}

std::vector<uint8_t> encryptCtrPayload(const String &plainText, const uint8_t nonce[SmartPacket::NONCE_SIZE]) {
  std::vector<uint8_t> output(plainText.length(), 0);
  std::vector<uint8_t> nonceCounter(SmartPacket::NONCE_SIZE, 0);
  memcpy(nonceCounter.data(), nonce, SmartPacket::NONCE_SIZE);

  size_t ncOffset = 0;
  unsigned char streamBlock[16] = {0};

  mbedtls_aes_context aes;
  mbedtls_aes_init(&aes);
  mbedtls_aes_setkey_enc(&aes, reinterpret_cast<const unsigned char *>(key), 128);
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

std::vector<uint8_t> buildStructuredPacket(const String &plainText, uint8_t priority, uint8_t reportMode, uint32_t sequence) {
  uint8_t nonce[SmartPacket::NONCE_SIZE];
  fillNonce(nonce, sequence);
  std::vector<uint8_t> encryptedPayload = encryptCtrPayload(plainText, nonce);

  SmartPacket::Header header;
  header.magic = SmartPacket::MAGIC;
  header.version = SmartPacket::VERSION;
  header.nodeId = runtimeSettings.nodeId;
  header.priority = priority;
  header.reportMode = reportMode;
  header.payloadLength = (uint16_t) encryptedPayload.size();
  header.sequence = sequence;

  size_t bodyLength = sizeof(SmartPacket::Header) + SmartPacket::NONCE_SIZE + encryptedPayload.size();
  std::vector<uint8_t> packet(bodyLength + sizeof(uint32_t), 0);
  size_t offset = 0;

  memcpy(packet.data() + offset, &header, sizeof(header));
  offset += sizeof(header);
  memcpy(packet.data() + offset, nonce, SmartPacket::NONCE_SIZE);
  offset += SmartPacket::NONCE_SIZE;
  memcpy(packet.data() + offset, encryptedPayload.data(), encryptedPayload.size());
  offset += encryptedPayload.size();

  uint32_t checksum = SmartPacket::crc32(packet.data(), offset);
  memcpy(packet.data() + offset, &checksum, sizeof(checksum));
  return packet;
}

bool sendBinaryPacket(const std::vector<uint8_t> &packetBytes) {
  if (!loraReady) {
    return false;
  }

  LoRa.beginPacket();
  size_t written = LoRa.write(packetBytes.data(), packetBytes.size());
  int result = LoRa.endPacket();
  return written == packetBytes.size() && result == 1;
}

void enqueuePendingPacket(const std::vector<uint8_t> &packetBytes, uint8_t priority, uint8_t reportMode, uint32_t sequence) {
  if (pendingPackets.size() >= MAX_PENDING_PACKETS) {
    pendingPackets.erase(pendingPackets.begin());
  }

  PendingPacket packet{packetBytes, priority, reportMode, sequence, millis()};
  if (priority == SmartPacket::PRIORITY_HIGH) {
    pendingPackets.insert(pendingPackets.begin(), packet);
  } else {
    pendingPackets.push_back(packet);
  }
}

void retryPendingPacketsIfNeeded() {
  if (pendingPackets.empty() || millis() - lastRetryMs < RETRY_INTERVAL_MS) {
    return;
  }

  lastRetryMs = millis();
  PendingPacket packet = pendingPackets.front();
  if (sendBinaryPacket(packet.bytes)) {
    Serial.print("Retried queued packet successfully. Seq=");
    Serial.println(packet.sequence);
    pendingPackets.erase(pendingPackets.begin());
  } else {
    Serial.print("Queued packet retry failed. Seq=");
    Serial.println(packet.sequence);
  }
}

void sendCurrentTelemetry(bool forceImmediate) {
  if (latestSegments.empty()) {
    return;
  }

  bool intervalElapsed = (millis() - lastReportMs) >= currentReportIntervalMs;
  if (!forceImmediate && !intervalElapsed) {
    return;
  }

  uint32_t sequence = packetSeq++;
  String plainText = buildPlainPayload(sequence, currentPriority, currentReportMode);
  std::vector<uint8_t> packetBytes = buildStructuredPacket(plainText, currentPriority, currentReportMode, sequence);

  if (sendBinaryPacket(packetBytes)) {
    lastReportMs = millis();
    criticalDispatchPending = false;
    Serial.println("\n========== LORA PACKET ==========");
    Serial.print("Sequence: ");
    Serial.println(sequence);
    Serial.print("Priority: ");
    Serial.println(SmartPacket::priorityLabel(currentPriority));
    Serial.print("Report mode: ");
    Serial.println(SmartPacket::reportModeLabel(currentReportMode));
    Serial.print("Payload length: ");
    Serial.println(plainText.length());
    Serial.print("Packet length: ");
    Serial.println(packetBytes.size());
    Serial.println("Packet sent securely.");
    Serial.println("=================================\n");
  } else {
    Serial.println("LoRa send failed. Queueing packet.");
    enqueuePendingPacket(packetBytes, currentPriority, currentReportMode, sequence);
  }
}

void sendLocationSyncIfNeeded() {
  if (!metadataSyncPending) {
    return;
  }

  uint32_t sequence = packetSeq++;
  String payload = buildLocationSyncPayload(sequence);
  std::vector<uint8_t> packetBytes = buildStructuredPacket(
      payload,
      SmartPacket::PRIORITY_LOW,
      SmartPacket::REPORT_MODE_NORMAL,
      sequence);

  if (sendBinaryPacket(packetBytes)) {
    metadataSyncPending = false;
    Serial.println("Location sync packet sent after config update.");
  } else {
    enqueuePendingPacket(packetBytes, SmartPacket::PRIORITY_LOW, SmartPacket::REPORT_MODE_NORMAL, sequence);
    Serial.println("Location sync packet queued for retry.");
  }
}

// ================= SENSOR CALIBRATION FUNCTIONS =================
// These are default calibration values - adjust based on your sensor

// pH Sensor Calibration
// Default: Neutral pH7 = 1500 raw, Acid pH4 = 1000 raw, Alkaline pH10 = 2000 raw
// Formula: pH = ((raw - neutralRaw) / slope) + 7
float readPH(int raw) {
  // ESP32 ADC: 0-4095, typically pH7 reads around half (2048)
  // Calibration values - adjust these for your sensor!
  const float neutralRaw = 1500.0;  // Raw value at pH 7
  const float slope = 250.0;       // Raw change per pH unit

  float ph = ((raw - neutralRaw) / slope) + 7.0;

  // Clamp to valid range
  if (ph < 0) ph = 0;
  if (ph > 14) ph = 14;

  return ph;
}

// TDS Sensor Calibration
// Default: 0 raw = 0 PPM, 4095 raw = ~2000 PPM
// Formula: PPM = (raw / 4095.0) * 2000 * multiplier
float readTDS(int raw) {
  // Typical conversion: 1 unit ADC ~ 0.5 PPM
  // For 0-4095 ADC range mapping to 0-2000 PPM
  const float multiplier = 0.5;

  float tds = (raw / 4095.0) * 2000.0 * multiplier;

  return tds;
}

// Turbidity Sensor
// Returns NTU value and status text
String readTurbidity(int raw) {
  // ESP32: 0 = clear (high voltage), 4095 = murky (low voltage)
  // Map raw ADC to NTU (Nephelometric Turbidity Units)
  // Typical: 0 ADC = ~0 NTU (clear), 4095 ADC = ~3000 NTU (very murky)

  const float maxNTU = 3000.0;
  float ntu = ((float)raw / 4095.0) * maxNTU;

  // Return formatted string: "123.5" or use the helper below
  // For app compatibility, we'll return just the NTU value as string
  // The app can then display as "Clear" if < 10, "Murky" if > 100, etc.
  return String(ntu, 1);
}

// Alternative: Get turbidity status string
String getTurbidityStatus(int raw) {
  float ntu = ((float)raw / 4095.0) * 3000.0;

  if (ntu < 10) return "Clear";
  else if (ntu < 50) return "Slightly Cloudy";
  else if (ntu < 100) return "Cloudy";
  else if (ntu < 500) return "Murky";
  else return "Very Murky";
}

void setup() {
  Serial.begin(115200);
  delay(1000);
  Serial.println();
  Serial.println("BOOT OK");
  Serial.println("Starting SmartPonic node...");

  for (int i = 0; i < MAX_SENSORS; i++) {
    dhtSensors[i] = nullptr;
    oneWireSensors[i] = nullptr;
    tempSensors[i] = nullptr;
  }
  Serial.println("Sensor slots initialized");

  IPAddress localIp(192, 168, 4, 1);
  IPAddress gateway(192, 168, 4, 1);
  IPAddress subnet(255, 255, 255, 0);
  const char *headerKeys[] = {nodeKeyHeader};

  WiFi.mode(WIFI_AP);
  if (!WiFi.softAPConfig(localIp, gateway, subnet)) {
    Serial.println("AP IP config failed");
  }

  bool apReady = WiFi.softAP(ssid, password);
  Serial.print("Access Point status: ");
  Serial.println(apReady ? "ready" : "failed");
  Serial.print("Access Point SSID: ");
  Serial.println(ssid);
  Serial.print("Access Point IP: ");
  Serial.println(WiFi.softAPIP());

  prefs.begin(configNamespace, true);
  String savedJson = prefs.getString(configJsonPrefKey, "");
  prefs.end();
  Serial.print("Saved config bytes: ");
  Serial.println(savedJson.length());
  Serial.print("Node security key configured: ");
  Serial.println(loadNodeSecurityKey().isEmpty() ? "no" : "yes");

  if (savedJson != "") {
    DynamicJsonDocument doc(4096);
    DeserializationError error = deserializeJson(doc, savedJson);
    if (error) {
      Serial.print("Saved config parse failed: ");
      Serial.println(error.f_str());
    } else if (doc.containsKey("config")) {
      loadRuntimeSettingsFromDocument(doc);
      applyConfig(doc["config"]);
      Serial.println("Saved config applied");
    }
  }

  server.on("/", HTTP_GET, handleRoot);
  server.on("/health", HTTP_GET, handleHealth);
  server.collectHeaders(headerKeys, 1);
  server.on("/config", HTTP_OPTIONS, handleOptions);
  server.on("/config", HTTP_POST, handlePostConfig);
  server.on("/config", HTTP_GET, handleGetConfig);
  server.onNotFound(handleNotFound);
  server.begin();
  Serial.println("HTTP config server started");
  Serial.println("Open http://192.168.4.1/ in your browser");

  SPI.begin(LORA_SCK, LORA_MISO, LORA_MOSI, LORA_SS);
  LoRa.setPins(LORA_SS, LORA_RST, LORA_DIO0);
  loraReady = LoRa.begin(433E6);
  if (loraReady) {
    LoRa.setSyncWord(LORA_SYNC_WORD);
    Serial.println("System Ready");
  } else {
    Serial.println("LoRa init failed");
  }

  // ADD THIS: start with an immediate sample so the first report has fresh data
  sampleSensors();
}

void loop() {
  server.handleClient();

  if (millis() - lastSampleMs >= SAMPLE_INTERVAL_MS) {
    lastSampleMs = millis();
    sampleSensors();
  }

  if (currentPriority == SmartPacket::PRIORITY_HIGH && criticalDispatchPending) {
    sendCurrentTelemetry(true);
  } else {
    sendCurrentTelemetry(false);
  }

  sendLocationSyncIfNeeded();
  retryPendingPacketsIfNeeded();

  // Handle serial commands for configuration
  if (Serial.available()) {
    String input = Serial.readStringUntil('\n');
    input.trim();
    handleSerialCommand(input);
  }
}

// ================= SERIAL CONFIG COMMANDS =================
void handleSerialCommand(String input) {
  if (input.length() == 0) return;

  Serial.println("\n>>> Command: " + input);
  String command = input;
  command.toUpperCase();

  if (command == "HELP") {
    Serial.println("=== AVAILABLE COMMANDS ===");
    Serial.println("HELP           - Show this help");
    Serial.println("LIST           - Show current sensor config");
    Serial.println("CLEAR          - Clear all sensor config");
    Serial.println("ADD,pin,type,sensor,label - Add sensor");
    Serial.println("META,nodeId,lat,lon,distance - Update node metadata");
    Serial.println("");
    Serial.println("Examples:");
    Serial.println("ADD,4,AI,DHT22,TempSensor");
    Serial.println("ADD,21,AI,WaterTemp,WaterTemp");
    Serial.println("ADD,34,AI,pH,pHSensor");
    Serial.println("ADD,35,AI,TDS,TDSensor");
    Serial.println("ADD,36,AI,Turbidity,TurbSensor");
    Serial.println("ADD,39,DI,Rain,RainSensor");
    Serial.println("");
    Serial.println("type: AI=Input (sensors), DI=Digital Input");
    Serial.println("sensor: DHT22, WaterTemp, pH, TDS, Turbidity, Rain");
    return;
  }

  if (command == "LIST") {
    Serial.println("=== CURRENT CONFIG ===");
    Serial.println("Count: " + String(configList.size()));
    for (size_t i = 0; i < configList.size(); i++) {
      auto c = configList[i];
      Serial.println("  " + String(i+1) + ". Pin:" + String(c.pin) +
                     " Type:" + c.type +
                     " Sensor:" + c.sensor +
                     " Label:" + c.label);
    }
    Serial.println("Node ID: " + String(runtimeSettings.nodeId));
    Serial.println("Latitude: " + String(runtimeSettings.latitude, 6));
    Serial.println("Longitude: " + String(runtimeSettings.longitude, 6));
    Serial.println("Distance(m): " + String(runtimeSettings.distanceMeters, 1));
    Serial.println("Pending queue: " + String(pendingPackets.size()));
    return;
  }

  if (command == "CLEAR") {
    configList.clear();
    latestSegments.clear();
    Serial.println("Config cleared!");
    return;
  }

  if (command.startsWith("META,")) {
    String parts[4];
    int partIdx = 0;
    int start = 5;
    for (int i = 5; i <= input.length(); i++) {
      if (i == input.length() || input[i] == ',') {
        parts[partIdx] = input.substring(start, i);
        start = i + 1;
        partIdx++;
        if (partIdx >= 4) break;
      }
    }

    if (partIdx < 4) {
      Serial.println("ERROR: Invalid format. Use: META,nodeId,lat,lon,distance");
      return;
    }

    runtimeSettings.nodeId = (uint8_t) max(1, (int) parts[0].toInt());
    runtimeSettings.latitude = parts[1].toFloat();
    runtimeSettings.longitude = parts[2].toFloat();
    runtimeSettings.distanceMeters = parts[3].toFloat();
    Serial.println("Node metadata updated.");
    return;
  }

  if (command.startsWith("ADD,")) {
    // Format: ADD,pin,type,sensor,label
    String parts[4];
    int partIdx = 0;
    int start = 4;
    for (int i = 4; i <= input.length(); i++) {
      if (input[i] == ',' || i == input.length()) {
        parts[partIdx] = input.substring(start, i);
        start = i + 1;
        partIdx++;
        if (partIdx >= 4) break;
      }
    }

    if (partIdx < 3) {
      Serial.println("ERROR: Invalid format. Use: ADD,pin,type,sensor,label");
      return;
    }

    int pin = parts[0].toInt();
    String type = parts[1];
    type.toUpperCase();
    String sensor = canonicalSensorName(parts[2]);
    String label = parts[3];

    if (configList.size() >= MAX_SENSORS) {
      Serial.println("ERROR: Maximum sensor limit reached!");
      return;
    }

    if (!isSafePin(pin)) {
      Serial.println("ERROR: Pin " + String(pin) + " is not safe to use!");
      Serial.println("Safe pins: 4,13,16,17,21,22,25,26,27,32,33,34,35,36,39");
      return;
    }

    for (size_t i = 0; i < configList.size(); i++) {
      if (configList[i].pin == pin && configList[i].sensor == sensor) {
        Serial.println("ERROR: Duplicate sensor config detected!");
        return;
      }
    }

    configList.push_back({pin, type, sensor, label});

    // Initialize sensor if needed
    int idx = configList.size() - 1;
    if (sensor == "DHT22") {
      dhtSensors[idx] = new DHT(pin, DHT22);
      dhtSensors[idx]->begin();
    } else if (sensor == "WaterTemp") {
      oneWireSensors[idx] = new OneWire(pin);
      tempSensors[idx] = new DallasTemperature(oneWireSensors[idx]);
      tempSensors[idx]->begin();
    }

    if (type == "DO") {
      pinMode(pin, OUTPUT);
    } else {
      pinMode(pin, INPUT);
    }

    Serial.println("Sensor added: Pin " + String(pin) + " as " + sensor);
    return;
  }

  Serial.println("Unknown command. Type HELP for available commands.");
}
