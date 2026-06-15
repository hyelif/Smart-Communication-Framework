#include <Arduino.h>
#include <SPI.h>
#include <LoRa.h>
#include <WiFi.h>
#include <HTTPClient.h>
#include <Preferences.h>
#include <FS.h>
#include <SPIFFS.h>
#include <vector>
#include <mbedtls/aes.h>
#include <mbedtls/sha256.h>
#include <ArduinoJson.h>

#include "SmartPacket.h"

// ================= CONFIG =================
// WiFi
const char* WIFI_SSID  = "Kimie";
const char* WIFI_PASS  = "00008888";

// API endpoints
const char* API_URL       = "http://172.20.10.3/smartponic/receive_data.php";
const char* CONTROL_URL   = "http://172.20.10.3/smartponic/control_queue.php";

// Default keys
#define DEFAULT_AES_KEY    "SmartPonic123456"
#define DEFAULT_API_KEY    "smartponic-hq-key"
#define DEFAULT_HMAC_SECRET "smartponic-hq-signature-secret"
#define DEFAULT_AUTH_KEY   "AQUA77"

// LoRa pins (ESP32-S2 Mini)
#define LORA_SCK   7
#define LORA_MISO  9
#define LORA_MOSI  11
#define LORA_SS    12
#define LORA_RST   5
#define LORA_DIO0  -1
#define LORA_BAND  433E6

// Timing
constexpr unsigned long WIFI_RETRY_MS      = 10000UL;
constexpr unsigned long NOISE_PRINT_MS     = 10000UL;
constexpr unsigned long HTTP_RETRY_MS      = 30000UL;
constexpr unsigned long CONTROL_POLL_MS    = 4000UL;

// Queue
const char* PENDING_QUEUE_PATH = "/pending_http_queue.ndjson";

// ================= GLOBALS =================
String gAesKey     = DEFAULT_AES_KEY;
String gApiKey     = DEFAULT_API_KEY;
String gHmacSecret = DEFAULT_HMAC_SECRET;
String gAuthKey    = DEFAULT_AUTH_KEY;
String gHardwareId;

bool gWifiConnected = false;
unsigned long gWifiRetryMs = 0;
unsigned long gLastNoisePrintMs = 0;
uint32_t gPacketRxCount = 0;
int gLastRssi = 0;
float gLastSnr = 0.0f;

// Sequence deduplication
uint32_t gLastSeq = 0;

// HTTP retry queue
unsigned long gLastHttpRetryMs = 0;

// Control queue polling
unsigned long gLastControlPollMs = 0;

// Multi-node tracking
std::vector<String> gKnownHardwareIds;

// Track recently sent relay command IDs to avoid duplicates
std::vector<uint32_t> gSentRelayCmdIds;
constexpr size_t MAX_SENT_RELAY_CACHE = 20;

// ================= FORWARD DECLARATIONS =================
void queueFailedJson(const String& jsonBody);
void handleSerialCommand(const String& input);

// ================= AES-CTR =================
void aesCtr(const uint8_t* input, size_t len, const uint8_t key[16],
            const uint8_t nonce[16], uint8_t* output) {
    uint8_t counter[16];
    memcpy(counter, nonce, 16);
    size_t ncOff = 0;
    uint8_t stream[16] = {0};
    mbedtls_aes_context aes;
    mbedtls_aes_init(&aes);
    mbedtls_aes_setkey_enc(&aes, key, 128);
    mbedtls_aes_crypt_ctr(&aes, len, &ncOff, counter, stream, input, output);
    mbedtls_aes_free(&aes);
}

// ================= SIGNATURE (plain SHA256, matching PHP backend) =================
// PHP uses: hash('sha256', timestamp . body . secret)
String buildSignature(const String& ts, const String& body) {
    String input = ts + body + gHmacSecret;
    unsigned char hash[32];
    mbedtls_sha256_context ctx;
    mbedtls_sha256_init(&ctx);
    mbedtls_sha256_starts(&ctx, 0);
    mbedtls_sha256_update(&ctx, (const unsigned char*)input.c_str(), input.length());
    mbedtls_sha256_finish(&ctx, hash);
    mbedtls_sha256_free(&ctx);

    String sig;
    for (int i = 0; i < 32; i++) {
        if (hash[i] < 0x10) sig += "0";
        sig += String(hash[i], HEX);
    }
    return sig;
}

// ================= HTTP POST =================
bool httpPost(const String& url, const String& json, String& resp) {
    if (WiFi.status() != WL_CONNECTED) return false;

    String ts = String(millis());
    String sig = buildSignature(ts, json);

    HTTPClient http;
    http.begin(url);
    http.setTimeout(5000);
    http.addHeader("Content-Type", "application/json");
    http.addHeader("X-API-Key", gApiKey);
    http.addHeader("X-Timestamp", ts);
    http.addHeader("X-Signature", sig);

    int code = http.POST(json);
    resp = http.getString();
    http.end();
    Serial.print("[HTTP] POST "); Serial.print(url);
    Serial.print(" -> "); Serial.println(code);
    return (code >= 200 && code < 300);
}

// ================= FORWARD TELEMETRY =================
bool forwardTelemetry(const String& hwId, const String& sensorsJson,
                      uint8_t priority = 0, uint8_t reportMode = 0) {
    String json = "{";
    json += "\"hardware_id\":\"" + hwId + "\",";
    json += "\"rssi\":" + String(gLastRssi) + ",";
    json += "\"snr\":" + String(gLastSnr, 1) + ",";
    json += "\"priority\":" + String(priority) + ",";
    json += "\"report_mode\":" + String(reportMode) + ",";
    json += "\"event_type\":\"telemetry\",";
    json += "\"sensors\":" + sensorsJson + "}";

    String resp;
    bool ok = httpPost(String(API_URL), json, resp);
    if (ok) {
        Serial.print("[HTTP] OK: ");
        Serial.println(resp);
    } else {
        Serial.println("[HTTP] FAIL - queueing for retry");
        queueFailedJson(json);
    }
    return ok;
}

// ================= OFFLINE QUEUE (SPIFFS) =================
void initStorage() {
    if (!SPIFFS.begin(true)) {
        Serial.println("[QUEUE] SPIFFS init FAILED");
    } else {
        Serial.println("[QUEUE] SPIFFS ready");
    }
}

void queueFailedJson(const String& jsonBody) {
    if (!SPIFFS.begin(false)) return;
    File f = SPIFFS.open(PENDING_QUEUE_PATH, FILE_APPEND);
    if (!f) {
        Serial.println("[QUEUE] Failed to open queue file");
        return;
    }
    f.println(jsonBody);
    f.close();
    Serial.println("[QUEUE] Queued for retry");
}

void retryQueuedHttpIfNeeded() {
    if (millis() - gLastHttpRetryMs < HTTP_RETRY_MS) return;
    gLastHttpRetryMs = millis();
    if (WiFi.status() != WL_CONNECTED) return;
    if (!SPIFFS.begin(false)) return;
    if (!SPIFFS.exists(PENDING_QUEUE_PATH)) return;

    File f = SPIFFS.open(PENDING_QUEUE_PATH, FILE_READ);
    if (!f) return;

    // Read all lines into memory, retry first one
    std::vector<String> lines;
    while (f.available()) {
        String line = f.readStringUntil('\n');
        line.trim();
        if (line.length() > 0) {
            lines.push_back(line);
        }
    }
    f.close();

    if (lines.empty()) {
        SPIFFS.remove(PENDING_QUEUE_PATH);
        return;
    }

    // Build a minimal JSON that receive_data.php will accept
    // Re-wrap the original JSON with proper headers
    String first = lines[0];
    String resp;
    bool ok = httpPost(String(API_URL), first, resp);

    if (ok) {
        Serial.print("[QUEUE] Retry success: ");
        Serial.println(resp);
        lines.erase(lines.begin());
    } else {
        Serial.println("[QUEUE] Retry failed, keeping in queue");
        // Keep the first entry for next retry cycle
    }

    // Rewrite remaining lines
    if (lines.empty()) {
        SPIFFS.remove(PENDING_QUEUE_PATH);
    } else {
        File w = SPIFFS.open(PENDING_QUEUE_PATH, FILE_WRITE);
        if (w) {
            for (const auto& l : lines) {
                w.println(l);
            }
            w.close();
        }
    }
}

// ================= RELAY CONTROL DOWNLINK =================
void sendRelayCommand(const String& hwId, int relayId, int state, uint32_t commandId) {
    String payload = "auth=" + gAuthKey + "&cmd=relay";
    payload += "&relay=" + String(relayId);
    payload += "&state=" + String(state);
    payload += "&command_id=" + String(commandId);

    uint8_t key[16]; memcpy(key, gAesKey.c_str(), 16);
    uint8_t nonce[SmartPacket::NONCE_SIZE];
    SmartPacket::fillNonce(nonce);

    std::vector<uint8_t> enc(payload.length());
    aesCtr((const uint8_t*)payload.c_str(), payload.length(), key, nonce, enc.data());

    SmartPacket::Header hdr;
    memset(&hdr, 0, sizeof(hdr));
    hdr.magic = SmartPacket::MAGIC;
    hdr.version = SmartPacket::VERSION;
    memcpy(hdr.hardwareId, hwId.c_str(), 16);
    hdr.payloadLength = (uint16_t)enc.size();

    std::vector<uint8_t> pkt;
    pkt.resize(SmartPacket::HEADER_SIZE + SmartPacket::NONCE_SIZE + enc.size() + SmartPacket::CRC_SIZE);
    size_t off = 0;
    memcpy(pkt.data() + off, &hdr, SmartPacket::HEADER_SIZE); off += SmartPacket::HEADER_SIZE;
    memcpy(pkt.data() + off, nonce, SmartPacket::NONCE_SIZE); off += SmartPacket::NONCE_SIZE;
    memcpy(pkt.data() + off, enc.data(), enc.size()); off += enc.size();
    uint32_t crc = SmartPacket::crc32(pkt.data(), off);
    memcpy(pkt.data() + off, &crc, SmartPacket::CRC_SIZE);

    LoRa.beginPacket();
    LoRa.write(pkt.data(), pkt.size());
    LoRa.endPacket();
    delay(20);
    LoRa.receive();
    Serial.print("  TX relay: cmd_id="); Serial.println(commandId);

    // Mark as sent in PHP
    String body = "{\"action\":\"mark_sent\",\"command_id\":" + String(commandId) + "}";
    String resp;
    httpPost(String(CONTROL_URL), body, resp);

    // Add to local sent cache to prevent re-sending
    if (gSentRelayCmdIds.size() >= MAX_SENT_RELAY_CACHE) {
        gSentRelayCmdIds.erase(gSentRelayCmdIds.begin());
    }
    gSentRelayCmdIds.push_back(commandId);
}

// ================= CONTROL QUEUE POLLING =================
void registerKnownNode(const String& hwId) {
    for (size_t i = 0; i < gKnownHardwareIds.size(); i++) {
        if (gKnownHardwareIds[i] == hwId) return;
    }
    gKnownHardwareIds.push_back(hwId);
    Serial.print("[CTRL] Registered node: ");
    Serial.println(hwId);
}

static void pollControlQueue() {
    if (millis() - gLastControlPollMs < CONTROL_POLL_MS) return;
    gLastControlPollMs = millis();
    if (WiFi.status() != WL_CONNECTED) return;

    // Ensure last-heard hardware ID is in the known list
    if (gHardwareId.length() == 16) {
        registerKnownNode(gHardwareId);
    }

    for (size_t ni = 0; ni < gKnownHardwareIds.size(); ni++) {
        String hwId = gKnownHardwareIds[ni];

        String body = "{\"action\":\"get_pending\",\"hardware_id\":\"" + hwId + "\",\"limit\":2}";
        String resp;
        if (!httpPost(String(CONTROL_URL), body, resp)) continue;

        JsonDocument doc;
        DeserializationError err = deserializeJson(doc, resp);
        if (err) continue;
        if (!doc["pending"].is<JsonArray>()) continue;

        JsonArray pending = doc["pending"].as<JsonArray>();
        // Send only ONE command per poll cycle to avoid LoRa collisions
        bool sentOne = false;
        for (JsonObject cmd : pending) {
            if (sentOne) break;
            uint32_t commandId = (uint32_t)(cmd["id"] | 0);
            // Skip already-sent commands
            bool alreadySent = false;
            for (size_t si = 0; si < gSentRelayCmdIds.size(); si++) {
                if (gSentRelayCmdIds[si] == commandId) { alreadySent = true; break; }
            }
            if (alreadySent) continue;

            int relayId = cmd["relay_id"] | 0;
            String action = cmd["action"] | "OFF";
            action.toUpperCase();
            int state = (action == "ON") ? 1 : 0;
            if (commandId > 0) {
                sendRelayCommand(hwId, relayId, state, commandId);
                sentOne = true;  // Only one command per 4s cycle to avoid LoRa collisions
            }
        }
    }
}

// ================= HANDLE CONTROL ACK =================
void handleControlAck(const String& plaintext) {
    if (SmartPacket::getFieldValue(plaintext, "ack") != "relay") return;

    uint32_t commandId = (uint32_t)SmartPacket::getFieldValue(plaintext, "command_id").toInt();
    String status = SmartPacket::getFieldValue(plaintext, "status");
    String msg = SmartPacket::getFieldValue(plaintext, "msg");
    if (status != "done") status = "failed";

    String body = "{\"action\":\"ack\",\"command_id\":" + String(commandId) +
                  ",\"status\":\"" + status + "\",\"message\":\"" + msg + "\"}";
    String resp;
    httpPost(String(CONTROL_URL), body, resp);
    Serial.print("[CTRL] ACK forwarded cmd_id="); Serial.println(commandId);
}

// ================= SEND REPLY =================
void sendReply(const String& hwId, const String& cmd) {
    String payload = "auth=" + gAuthKey + "&cmd=" + cmd + "&hardware_id=" + hwId;
    uint8_t key[16]; memcpy(key, gAesKey.c_str(), 16);
    uint8_t nonce[SmartPacket::NONCE_SIZE];
    SmartPacket::fillNonce(nonce);

    std::vector<uint8_t> enc(payload.length());
    aesCtr((const uint8_t*)payload.c_str(), payload.length(), key, nonce, enc.data());

    SmartPacket::Header hdr;
    memset(&hdr, 0, sizeof(hdr));
    hdr.magic = SmartPacket::MAGIC;
    hdr.version = SmartPacket::VERSION;
    memcpy(hdr.hardwareId, hwId.c_str(), 16);
    hdr.payloadLength = (uint16_t)enc.size();

    std::vector<uint8_t> pkt;
    pkt.resize(SmartPacket::HEADER_SIZE + SmartPacket::NONCE_SIZE + enc.size() + SmartPacket::CRC_SIZE);
    size_t off = 0;
    memcpy(pkt.data() + off, &hdr, SmartPacket::HEADER_SIZE); off += SmartPacket::HEADER_SIZE;
    memcpy(pkt.data() + off, nonce, SmartPacket::NONCE_SIZE); off += SmartPacket::NONCE_SIZE;
    memcpy(pkt.data() + off, enc.data(), enc.size()); off += enc.size();
    uint32_t crc = SmartPacket::crc32(pkt.data(), off);
    memcpy(pkt.data() + off, &crc, SmartPacket::CRC_SIZE);

    LoRa.beginPacket();
    LoRa.write(pkt.data(), pkt.size());
    LoRa.endPacket();
    delay(20);
    LoRa.receive();
    Serial.print("  TX: "); Serial.print(pkt.size()); Serial.print("B  ");
    Serial.println(cmd);
}

// ================= PARSE BINARY =================
String parseBinaryPayload(const std::vector<uint8_t>& data,
                          uint8_t& outPriority, uint8_t& outReportMode) {
    if (data.size() < SmartPacket::BIN_HEADER_SIZE) return "[]";
    uint8_t count = data[0];
    if (count > SmartPacket::BIN_MAX_READINGS) return "[]";

    outPriority   = data[1];
    outReportMode = data[2];

    String json = "[";
    size_t pos = SmartPacket::BIN_HEADER_SIZE;
    bool first = true;

    for (uint8_t i = 0; i < count && pos + SmartPacket::BIN_READING_SIZE <= data.size(); i++) {
        uint8_t pin = data[pos];
        uint8_t typeId = data[pos + 1];
        int16_t scaled = (int16_t)(data[pos + 2] | ((uint16_t)data[pos + 3] << 8));
        pos += SmartPacket::BIN_READING_SIZE;

        String val;
        if (scaled == SmartPacket::BIN_VALUE_NAN) val = "nan";
        else if (scaled == SmartPacket::BIN_VALUE_ERROR) val = "-127.0";
        else { char b[16]; float v = scaled / 10.0f; snprintf(b, sizeof(b), "%.1f", v); val = b; }

        const char* name = SmartPacket::sensorTypeToName((SmartPacket::SensorType)typeId);

        if (!first) json += ",";
        json += "{\"pin\":" + String(pin) + ",\"sensor\":\"" + String(name)
              + "\",\"value\":\"" + val + "\"}";
        first = false;

        Serial.print("  "); Serial.print(name); Serial.print("="); Serial.println(val);
    }
    json += "]";
    return json;
}

// ================= PACKET PROCESSING =================
void processPacket(int packetSize) {
    uint8_t buf[SmartPacket::MAX_PACKET_BYTES];
    int len = 0;
    while (LoRa.available() && len < SmartPacket::MAX_PACKET_BYTES) {
        buf[len++] = LoRa.read();
    }
    LoRa.receive();

    gLastRssi = LoRa.packetRssi();
    gLastSnr  = LoRa.packetSnr();

    if (len < 44) { Serial.println("[RX] Too short"); return; }

    uint32_t magic; memcpy(&magic, buf, 4);
    if (magic != SmartPacket::MAGIC) { Serial.println("[RX] Bad magic"); return; }
    if (buf[4] != SmartPacket::VERSION) { Serial.println("[RX] Bad version"); return; }

    char hwId[17] = {0}; memcpy(hwId, buf + 5, 16);
    String hardwareId = String(hwId);
    if (!SmartPacket::isValidHardwareId(hardwareId)) { Serial.println("[RX] Invalid HW ID"); return; }
    gHardwareId = hardwareId;

    uint16_t payloadLen = buf[21] | ((uint16_t)buf[22] << 8);
    size_t expected = SmartPacket::HEADER_SIZE + SmartPacket::NONCE_SIZE + payloadLen + SmartPacket::CRC_SIZE;
    if ((size_t)len != expected) { Serial.println("[RX] Size mismatch"); return; }

    uint32_t calcCrc = SmartPacket::crc32(buf, len - SmartPacket::CRC_SIZE);
    uint32_t recvCrc; memcpy(&recvCrc, buf + len - SmartPacket::CRC_SIZE, SmartPacket::CRC_SIZE);
    if (calcCrc != recvCrc) { Serial.println("[RX] CRC fail"); return; }

    uint8_t key[16]; memcpy(key, gAesKey.c_str(), 16);
    std::vector<uint8_t> plain(payloadLen);
    aesCtr(buf + SmartPacket::HEADER_SIZE + SmartPacket::NONCE_SIZE, payloadLen, key,
           buf + SmartPacket::HEADER_SIZE, plain.data());

    gPacketRxCount++;
    registerKnownNode(hardwareId);

    Serial.println("\n═══════════════════════════════════════");
    Serial.print("  RX #"); Serial.print(gPacketRxCount);
    Serial.print("  HW: "); Serial.print(hardwareId);
    Serial.print("  RSSI:"); Serial.print(gLastRssi);
    Serial.print("  SNR:"); Serial.println(gLastSnr);

    if (SmartPacket::isBinaryFormat(plain.data(), plain.size())) {
        uint8_t rxPriority = 0, rxReportMode = 0;
        String sensorsJson = parseBinaryPayload(plain, rxPriority, rxReportMode);
        Serial.print("  Type: BINARY  Prio=");
        Serial.print(SmartPacket::priorityLabel(rxPriority));
        Serial.print("  Mode=");
        Serial.println(SmartPacket::reportModeLabel(rxReportMode));
        Serial.println("───────────────────────────────────────");
        sendReply(hardwareId, "ack");
        forwardTelemetry(hardwareId, sensorsJson, rxPriority, rxReportMode);
    } else {
        String text;
        for (size_t i = 0; i < plain.size(); i++) {
            if (plain[i] == 0) break;
            text += (char)plain[i];
        }
        text.trim();
        Serial.print("  Type: TEXT  Payload: "); Serial.println(text);

        handleControlAck(text);

        String cmd = SmartPacket::getFieldValue(text, "cmd");
        if (cmd == "hello") {
            Serial.println("  >>> REGISTRATION - Sending approval");
            Serial.println("───────────────────────────────────────");
            sendReply(hardwareId, "approve");
        } else if (cmd != "relay") {
            Serial.println("  Unknown cmd");
            Serial.println("───────────────────────────────────────");
        }
    }
}

// ================= SETUP =================
void setup() {
    Serial.begin(115200);
    delay(2000);

    Serial.println("\n=============================================");
    Serial.println("  SmartPonic HQ Gateway (Full)");
    Serial.println("=============================================");

    // Keys
    Preferences p;
    p.begin("hq_secrets", false);
    gAesKey     = p.getString("aes_key", DEFAULT_AES_KEY);
    gApiKey     = p.getString("api_key", DEFAULT_API_KEY);
    gHmacSecret = p.getString("hmac", DEFAULT_HMAC_SECRET);
    gAuthKey    = p.getString("auth_key", DEFAULT_AUTH_KEY);
    p.end();
    Serial.print("[KEY] AES="); Serial.println(gAesKey);
    Serial.print("[KEY] AUTH="); Serial.println(gAuthKey);

    // SPIFFS for offline queue
    initStorage();

    // WiFi
    Serial.print("[WIFI] Connecting to "); Serial.println(WIFI_SSID);
    WiFi.mode(WIFI_STA);
    WiFi.begin(WIFI_SSID, WIFI_PASS);

    // LoRa
    Serial.println("[LORA] Initializing...");
    SPI.begin(LORA_SCK, LORA_MISO, LORA_MOSI, LORA_SS);
    LoRa.setPins(LORA_SS, LORA_RST, LORA_DIO0);

    if (!LoRa.begin(LORA_BAND)) {
        Serial.println("[LORA] FAILED!");
    } else {
        Serial.println("[LORA] OK");
        LoRa.setSyncWord(0xB4);
        LoRa.setSpreadingFactor(9);
        LoRa.setSignalBandwidth(125E3);
        LoRa.setCodingRate4(5);
        LoRa.setPreambleLength(12);
        LoRa.enableCrc();
        LoRa.setTxPower(20);
        LoRa.receive();
        Serial.println("[LORA] Ready on 433MHz SF9");
    }

    Serial.println("=============================================");
}

// ================= LOOP =================
void loop() {
    unsigned long now = millis();

    // --- WiFi ---
    if (WiFi.status() == WL_CONNECTED) {
        if (!gWifiConnected) {
            gWifiConnected = true;
            Serial.print("[WIFI] IP: "); Serial.println(WiFi.localIP());
        }
    } else {
        if (gWifiConnected) { gWifiConnected = false; }
        if (now - gWifiRetryMs > WIFI_RETRY_MS) { gWifiRetryMs = now; WiFi.reconnect(); }
    }

    // --- LoRa RX (ALWAYS before blocking HTTP to avoid missing packets) ---
    int packetSize = LoRa.parsePacket();
    if (packetSize > 0) {
        processPacket(packetSize);
    } else {
        if (now - gLastNoisePrintMs > NOISE_PRINT_MS) {
            gLastNoisePrintMs = now;
            Serial.print("[RX] noise floor: ");
            Serial.print(LoRa.rssi());
            Serial.println(" dBm (no packet)");
        }
        delay(5);
    }

    // --- Non-critical HTTP housekeeping (after LoRa, may block) ---
    retryQueuedHttpIfNeeded();
    pollControlQueue();

    // --- Serial CLI ---
    if (Serial.available()) {
        String line = Serial.readStringUntil('\n');
        line.trim();
        if (line.length() > 0) {
            handleSerialCommand(line);
        }
    }
}

// ================= SERIAL CLI =================
void handleSerialCommand(const String& input) {
    String upper = input;
    upper.toUpperCase();

    if (upper == "HELP") {
        Serial.println("=== HQ CLI ===");
        Serial.println("HELP                  - This help");
        Serial.println("STATUS                - Show status");
        Serial.println("SHOWKEYS              - Show all keys");
        Serial.println("SETKEYS,AES=xx,API=yy,HMAC=zzz,AUTH=ww - Set keys");
        Serial.println("CLEARKEYS             - Reset keys to defaults");
        Serial.println("WIFISTATUS            - Show WiFi status");
        Serial.println("QUEUE                 - Show queued HTTP count");
        Serial.println("NODES                 - List known nodes");
        return;
    }

    if (upper == "STATUS") {
        unsigned long ms = millis();
        Serial.println("=== HQ Status ===");
        Serial.print("Uptime: "); Serial.print(ms / 1000); Serial.println("s");
        Serial.print("Heap: "); Serial.print(ESP.getFreeHeap() / 1024); Serial.println(" KB");
        Serial.print("Packets RX: "); Serial.println(gPacketRxCount);
        Serial.print("Last RSSI: "); Serial.println(gLastRssi);
        Serial.print("Last SNR: "); Serial.println(gLastSnr);
        Serial.print("Known nodes: "); Serial.println(gKnownHardwareIds.size());
        Serial.print("WiFi: "); Serial.println(WiFi.status() == WL_CONNECTED ? "connected" : "disconnected");
        return;
    }

    if (upper == "SHOWKEYS") {
        Serial.println("=== Keys ===");
        Serial.print("AES: "); Serial.println(gAesKey);
        Serial.print("API: "); Serial.println(gApiKey);
        Serial.print("HMAC: "); Serial.println(gHmacSecret);
        Serial.print("AUTH: "); Serial.println(gAuthKey);
        return;
    }

    if (upper.startsWith("SETKEYS,")) {
        String args = input.substring(8);
        Preferences p;
        p.begin("hq_secrets", false);
        int aesPos = args.indexOf("AES=");
        if (aesPos >= 0) {
            int end = args.indexOf(',', aesPos);
            if (end < 0) end = args.length();
            String v = args.substring(aesPos + 4, end);
            v.trim();
            if (v.length() == 16) {
                p.putString("aes_key", v);
                gAesKey = v;
                Serial.println("AES key saved");
            }
        }
        int apiPos = args.indexOf("API=");
        if (apiPos >= 0) {
            int end = args.indexOf(',', apiPos);
            if (end < 0) end = args.length();
            String v = args.substring(apiPos + 4, end);
            v.trim();
            if (v.length() > 0) {
                p.putString("api_key", v);
                gApiKey = v;
                Serial.println("API key saved");
            }
        }
        int hmacPos = args.indexOf("HMAC=");
        if (hmacPos >= 0) {
            int end = args.indexOf(',', hmacPos);
            if (end < 0) end = args.length();
            String v = args.substring(hmacPos + 5, end);
            v.trim();
            if (v.length() > 0) {
                p.putString("hmac", v);
                gHmacSecret = v;
                Serial.println("HMAC secret saved");
            }
        }
        int authPos = args.indexOf("AUTH=");
        if (authPos >= 0) {
            int end = args.indexOf(',', authPos);
            if (end < 0) end = args.length();
            String v = args.substring(authPos + 5, end);
            v.trim();
            if (v.length() > 0) {
                p.putString("auth_key", v);
                gAuthKey = v;
                Serial.println("AUTH key saved");
            }
        }
        p.end();
        return;
    }

    if (upper == "CLEARKEYS") {
        Preferences p;
        p.begin("hq_secrets", false);
        p.remove("aes_key");
        p.remove("api_key");
        p.remove("hmac");
        p.remove("auth_key");
        p.end();
        gAesKey = DEFAULT_AES_KEY;
        gApiKey = DEFAULT_API_KEY;
        gHmacSecret = DEFAULT_HMAC_SECRET;
        gAuthKey = DEFAULT_AUTH_KEY;
        Serial.println("Keys reset to defaults");
        return;
    }

    if (upper == "WIFISTATUS") {
        Serial.print("WiFi: ");
        Serial.println(WiFi.status() == WL_CONNECTED ? "connected" : "disconnected");
        if (WiFi.status() == WL_CONNECTED) {
            Serial.print("IP: "); Serial.println(WiFi.localIP());
            Serial.print("RSSI: "); Serial.println(WiFi.RSSI());
        }
        return;
    }

    if (upper == "QUEUE") {
        if (!SPIFFS.begin(false) || !SPIFFS.exists(PENDING_QUEUE_PATH)) {
            Serial.println("Queue: empty");
            return;
        }
        File f = SPIFFS.open(PENDING_QUEUE_PATH, FILE_READ);
        int count = 0;
        while (f.available()) {
            if (f.readStringUntil('\n').length() > 0) count++;
        }
        f.close();
        Serial.print("Queue: "); Serial.print(count); Serial.println(" pending");
        return;
    }

    if (upper == "NODES") {
        Serial.print("Known nodes ("); Serial.print(gKnownHardwareIds.size()); Serial.println("):");
        for (size_t i = 0; i < gKnownHardwareIds.size(); i++) {
            Serial.print("  "); Serial.println(gKnownHardwareIds[i]);
        }
        return;
    }

    Serial.print("Unknown: "); Serial.println(input);
    Serial.println("Type HELP for commands");
}