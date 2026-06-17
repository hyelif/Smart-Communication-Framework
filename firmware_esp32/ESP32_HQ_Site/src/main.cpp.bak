#include <Arduino.h>
#include <SPI.h>
#include <LoRa.h>
#include <WiFi.h>
#include <HTTPClient.h>
#include <Preferences.h>
#include <vector>
#include <mbedtls/aes.h>
#include <mbedtls/sha256.h>

#include "SmartPacket.h"

// ================= CONFIG =================
const char* WIFI_SSID  = "Kimie";
const char* WIFI_PASS  = "00008888";
const char* API_URL    = "http://172.20.10.3/smartponic/receive_data.php";

#define LORA_SCK   7
#define LORA_MISO  9
#define LORA_MOSI  11
#define LORA_SS    12
#define LORA_RST   5
#define LORA_DIO0  -1
#define LORA_BAND  433E6

#define DEFAULT_AES_KEY    "SmartPonic123456"
#define DEFAULT_API_KEY    "smartponic-hq-key"
#define DEFAULT_HMAC_SECRET "smartponic-hq-signature-secret"
#define DEFAULT_AUTH_KEY   "AQUA77"

// ================= GLOBALS =================
String gAesKey     = DEFAULT_AES_KEY;
String gApiKey     = DEFAULT_API_KEY;
String gHmacSecret = DEFAULT_HMAC_SECRET;
String gAuthKey    = DEFAULT_AUTH_KEY;
String gHardwareId;  // last heard node

bool gWifiConnected = false;
unsigned long gWifiRetryMs = 0;
unsigned long gLastNoisePrintMs = 0;
uint32_t gPacketRxCount = 0;
int gLastRssi = 0;
float gLastSnr = 0.0f;

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

// ================= SIGNATURE =================
String buildSignature(const String& ts, const String& body) {
    String input = ts + body + gHmacSecret;
    mbedtls_sha256_context ctx;
    mbedtls_sha256_init(&ctx);
    mbedtls_sha256_starts(&ctx, 0);
    mbedtls_sha256_update(&ctx, (const uint8_t*)input.c_str(), input.length());
    uint8_t hash[32];
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
    return (code >= 200 && code < 300);
}

// ================= FORWARD TELEMETRY =================
bool forwardTelemetry(const String& hwId, const String& sensorsJson) {
    String json = "{";
    json += "\"hardware_id\":\"" + hwId + "\",";
    json += "\"rssi\":" + String(gLastRssi) + ",";
    json += "\"snr\":" + String(gLastSnr, 1) + ",";
    json += "\"event_type\":\"telemetry\",";
    json += "\"sensors\":" + sensorsJson + "}";

    String resp;
    bool ok = httpPost(String(API_URL), json, resp);
    if (ok) {
        Serial.print("[HTTP] OK: ");
        Serial.println(resp);
    } else {
        Serial.println("[HTTP] FAIL");
    }
    return ok;
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
String parseBinaryPayload(const std::vector<uint8_t>& data) {
    if (data.size() < SmartPacket::BIN_HEADER_SIZE) return "[]";
    uint8_t count = data[0];
    if (count > SmartPacket::BIN_MAX_READINGS) return "[]";

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

// ================= SETUP =================
void setup() {
    Serial.begin(115200);
    delay(2000);

    Serial.println("\n=============================================");
    Serial.println("  SmartPonic HQ Gateway");
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
        if (now - gWifiRetryMs > 10000) { gWifiRetryMs = now; WiFi.reconnect(); }
    }

    // --- LoRa RX ---
    int packetSize = LoRa.parsePacket();
    if (packetSize <= 0) {
        // Print noise floor every 10s so we know the radio is alive
        if (now - gLastNoisePrintMs > 10000) {
            gLastNoisePrintMs = now;
            Serial.print("[RX] noise floor: ");
            Serial.print(LoRa.rssi());
            Serial.println(" dBm (no packet)");
        }
        delay(5);
        return;
    }

    uint8_t buf[SmartPacket::MAX_PACKET_BYTES];
    int len = 0;
    while (LoRa.available() && len < SmartPacket::MAX_PACKET_BYTES) {
        buf[len++] = LoRa.read();
    }
    LoRa.receive();

    gLastRssi = LoRa.packetRssi();
    gLastSnr  = LoRa.packetSnr();

    // --- Validate ---
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

    // --- Decrypt ---
    uint8_t key[16]; memcpy(key, gAesKey.c_str(), 16);
    std::vector<uint8_t> plain(payloadLen);
    aesCtr(buf + SmartPacket::HEADER_SIZE + SmartPacket::NONCE_SIZE, payloadLen, key,
           buf + SmartPacket::HEADER_SIZE, plain.data());

    gPacketRxCount++;

    Serial.println("\n═══════════════════════════════════════");
    Serial.print("  RX #"); Serial.print(gPacketRxCount);
    Serial.print("  HW: "); Serial.print(hardwareId);
    Serial.print("  RSSI:"); Serial.print(gLastRssi);
    Serial.print("  SNR:"); Serial.println(gLastSnr);

    // --- Detect format ---
    if (SmartPacket::isBinaryFormat(plain.data(), plain.size())) {
        // Binary telemetry
        Serial.println("  Type: BINARY TELEMETRY");
        String sensorsJson = parseBinaryPayload(plain);
        Serial.println("───────────────────────────────────────");
        sendReply(hardwareId, "ack");

        // Forward to PHP
        forwardTelemetry(hardwareId, sensorsJson);
    } else {
        // Text (registration)
        String text;
        for (size_t i = 0; i < plain.size(); i++) {
            if (plain[i] == 0) break;
            text += (char)plain[i];
        }
        text.trim();
        Serial.print("  Type: TEXT  Payload: "); Serial.println(text);

        String cmd = SmartPacket::getFieldValue(text, "cmd");
        if (cmd == "hello") {
            Serial.println("  >>> REGISTRATION - Sending approval");
            Serial.println("───────────────────────────────────────");
            sendReply(hardwareId, "approve");
        } else {
            Serial.println("  Unknown cmd");
            Serial.println("───────────────────────────────────────");
        }
    }
}