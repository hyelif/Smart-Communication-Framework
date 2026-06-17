#include <Arduino.h>
#include <SPI.h>
#include <LoRa.h>
#include <Preferences.h>
#include <vector>
#include <mbedtls/aes.h>

#include "SmartPacket.h"
#include "SensorManager.h"
#include "PacketBuilder.h"
#include "PriorityEngine.h"
// ================= STATE MACHINE =================
enum NodeState {
    STATE_REGISTERING,
    STATE_CONNECTED
};

// ================= DEFAULTS =================
#define DEFAULT_AES_KEY   "SmartPonic123456"
#define DEFAULT_AUTH_KEY  "AQUA77"

// Hardware ID override — set this to a fixed 16-char uppercase hex ID.
// If empty (""), the ID is derived from the ESP32's eFuse MAC address.
#define HARDWARE_ID_OVERRIDE ""

#define LORA_SCK     18
#define LORA_MISO    19
#define LORA_MOSI    23
#define LORA_SS       5
#define LORA_RST     14
#define LORA_DIO0    -1
#define LORA_SYNC    0xB4
#define LORA_BAND    433E6

// ================= GLOBALS =================
String gHardwareId;
String gAesKey;
String gAuthKey;

Preferences gPrefs;
SensorManager gSensorMgr;
PacketBuilder gPacketBuilder;
PriorityEngine gPriorityEngine;

std::vector<SensorReading> gReadings;
std::vector<uint8_t> gPacketBuf;
std::vector<uint8_t> gBinaryPayload;

unsigned long gLastSampleMs = 0;
unsigned long gBootMs = 0;
uint32_t gPacketCount = 0;
NodeState gNodeState = STATE_REGISTERING;
unsigned long gLastRegMs = 0;
constexpr unsigned long REG_INTERVAL_MS = 30000UL;
uint32_t gRegAttempt = 0;
unsigned long gLastHqSeenMs = 0;
uint32_t gMissedAckCount = 0;

// ADR (Adaptive Data Rate) state
int gBestHqRssi = SmartPacket::ADR_INVALID_RSSI;
int gCurrentSf = 9;
unsigned long gLastAdrUpdateMs = 0;
constexpr unsigned long ADR_UPDATE_INTERVAL_MS = 60000UL;

// Relay deduplication — skip already-processed commands
uint32_t gLastRelayCmdId = 0;

// ================= KEY STORAGE =================
static void loadKeys() {
    Serial.println("[KEY] Loading from Preferences namespace 'secrets'...");
    gPrefs.begin("secrets", false);
    gAesKey   = gPrefs.getString("aes_key", DEFAULT_AES_KEY);
    gAuthKey  = gPrefs.getString("auth_key", DEFAULT_AUTH_KEY);
    gPrefs.end();

    if (gAesKey.length() != 16) {
        gAesKey = DEFAULT_AES_KEY;
        Serial.println("[KEY] AES key invalid/missing, using default");
    }
    if (gAuthKey.length() == 0) {
        gAuthKey = DEFAULT_AUTH_KEY;
        Serial.println("[KEY] AUTH key missing, using default");
    }

    Serial.print("[KEY] AES: ");
    Serial.println(gAesKey);
    Serial.print("[KEY] AUTH: ");
    Serial.println(gAuthKey);
}

static void saveAesKey(const String& v) {
    if (v.length() != 16) {
        Serial.println("[KEY] ERROR: AES key must be exactly 16 characters");
        return;
    }
    gPrefs.begin("secrets", false);
    gPrefs.putString("aes_key", v);
    gPrefs.end();
    gAesKey = v;
    Serial.print("[KEY] AES key saved: ");
    Serial.println(v);
}

static void saveAuthKey(const String& v) {
    if (v.length() == 0) {
        Serial.println("[KEY] ERROR: Auth key cannot be empty");
        return;
    }
    gPrefs.begin("secrets", false);
    gPrefs.putString("auth_key", v);
    gPrefs.end();
    gAuthKey = v;
    Serial.print("[KEY] AUTH key saved: ");
    Serial.println(v);
}

static void clearKeys() {
    gPrefs.begin("secrets", false);
    gPrefs.remove("aes_key");
    gPrefs.remove("auth_key");
    gPrefs.end();
    gAesKey = DEFAULT_AES_KEY;
    gAuthKey = DEFAULT_AUTH_KEY;
    Serial.println("[KEY] Keys reset to defaults");
}

// ================= HARDWARE ID =================
static String getHardwareId() {
    if (strlen(HARDWARE_ID_OVERRIDE) == 16) {
        Serial.print("[HW] Using override: ");
        Serial.println(HARDWARE_ID_OVERRIDE);
        return String(HARDWARE_ID_OVERRIDE);
    }
    uint64_t mac = ESP.getEfuseMac();
    String id = SmartPacket::formatHardwareId(mac);
    Serial.print("[HW] ESP.getEfuseMac() = 0x");
    Serial.print((uint32_t)(mac >> 32), HEX);
    Serial.println((uint32_t)(mac & 0xFFFFFFFF), HEX);
    Serial.print("[HW] Hardware ID: ");
    Serial.println(id);
    return id;
}

// ================= CONFIGURE RADIO =================
static void configureRadio() {
    Serial.println("[RADIO] Configuring LoRa parameters...");
    LoRa.setSyncWord(LORA_SYNC);
    Serial.print("[RADIO] SyncWord=0x");
    Serial.println(LORA_SYNC, HEX);

    LoRa.setSpreadingFactor(9);
    Serial.println("[RADIO] SpreadingFactor=9");

    LoRa.setSignalBandwidth(125E3);
    Serial.println("[RADIO] Bandwidth=125kHz");

    LoRa.setCodingRate4(5);
    Serial.println("[RADIO] CodingRate=4/5");

    LoRa.setPreambleLength(12);
    Serial.println("[RADIO] Preamble=12");

    LoRa.enableCrc();
    Serial.println("[RADIO] CRC enabled");

    LoRa.setTxPower(20);
    Serial.println("[RADIO] TX Power=20dBm");

    Serial.println("[RADIO] Configuration complete");
}

// ================= SENSOR CONFIG =================
static void setupDefaultSensors() {
    Serial.println("[SETUP] Configuring default sensors...");
    Serial.println("[SETUP] Pin mapping:");
    Serial.println("[SETUP]   GPIO 17 -> DHT22     (Air Temp/Humidity)");
    Serial.println("[SETUP]   GPIO 27 -> WaterTemp (DS18B20)");
    Serial.println("[SETUP]   GPIO 32 -> pH        (Analog)");
    Serial.println("[SETUP]   GPIO 33 -> TDS       (Analog)");
    Serial.println("[SETUP]   GPIO 35 -> Turbidity (Analog)");
    Serial.println("[SETUP]   GPIO 16 -> Rain      (Digital, 1=sunny/0=rain)");

    gSensorMgr.addSensor(15, "AI", "DHT22",     "Air Temperature/Humidity");
    gSensorMgr.addSensor(27, "AI", "WaterTemp", "Water Temperature (DS18B20)");
    gSensorMgr.addSensor(32, "AI", "pH",         "pH Level");
    gSensorMgr.addSensor(33, "AI", "TDS",        "Total Dissolved Solids");
    gSensorMgr.addSensor(35, "AI", "Turbidity",  "Water Turbidity");
    gSensorMgr.addSensor(16, "DI", "Rain",       "Rain Detector");

    Serial.print("[SETUP] Initializing sensors...");
    gSensorMgr.init();
    Serial.println(" OK");
}

// ================= BINARY PAYLOAD BUILDER =================
static void buildBinaryPayload(const std::vector<SensorReading>& readings,
                                std::vector<uint8_t>& outPayload,
                                uint8_t priority = SmartPacket::PRIORITY_LOW,
                                uint8_t reportMode = SmartPacket::REPORT_MODE_NORMAL) {
    outPayload.clear();
    size_t maxReadings = readings.size();
    if (maxReadings > SmartPacket::BIN_MAX_READINGS) maxReadings = SmartPacket::BIN_MAX_READINGS;

    outPayload.reserve(SmartPacket::BIN_HEADER_SIZE + maxReadings * SmartPacket::BIN_READING_SIZE);
    outPayload.push_back((uint8_t)maxReadings);
    outPayload.push_back(priority);
    outPayload.push_back(reportMode);

    for (size_t i = 0; i < maxReadings; i++) {
        const auto& r = readings[i];
        outPayload.push_back((uint8_t)r.pin);
        outPayload.push_back((uint8_t)SmartPacket::sensorNameToType(r.sensorName));

        int16_t scaled;
        if (r.rawValue == "nan" || r.rawValue == "NaN") {
            scaled = SmartPacket::BIN_VALUE_NAN;
        } else if (r.rawValue == "-127.0") {
            scaled = SmartPacket::BIN_VALUE_ERROR;
        } else {
            float val = r.rawValue.toFloat();
            scaled = (int16_t)(roundf(val * 10.0f));
        }
        outPayload.push_back((uint8_t)(scaled & 0xFF));
        outPayload.push_back((uint8_t)((scaled >> 8) & 0xFF));
    }

    Serial.print("[BIN] Binary payload: ");
    Serial.print((int)outPayload.size());
    Serial.print(" bytes for ");
    Serial.print((int)maxReadings);
    Serial.println(" readings");
}

// ================= CHANNEL ACTIVITY DETECTION =================
static bool isChannelClear() {
    LoRa.receive();
    delay(2);
    int rssi = LoRa.rssi();
    return rssi < -95;
}

static bool waitForClearChannel() {
    const int maxAttempts = 5;
    for (int i = 0; i < maxAttempts; i++) {
        if (isChannelClear()) return true;
        delay(random(20, 100));
    }
    Serial.println("[CAD] Channel busy after 5 attempts, transmitting anyway");
    return false;
}

// ================= ADAPTIVE DATA RATE =================
static void updateAdr() {
    if (gBestHqRssi <= SmartPacket::ADR_INVALID_RSSI) return;

    int newSf;
    if (gBestHqRssi > SmartPacket::ADR_RSSI_SF7) {
        newSf = 7;
    } else if (gBestHqRssi > SmartPacket::ADR_RSSI_SF8) {
        newSf = 8;
    } else if (gBestHqRssi > SmartPacket::ADR_RSSI_SF9) {
        newSf = 9;
    } else {
        newSf = 10;
    }

    if (newSf != gCurrentSf) {
        gCurrentSf = newSf;
        // NOTE: ADR calculation kept for diagnostics. SF switching disabled
        // because HQ receiver is fixed at SF9. Both radios must use the same SF.
        // LoRa.setSpreadingFactor(gCurrentSf);
        Serial.print("[ADR] RSSI=");
        Serial.print(gBestHqRssi);
        Serial.print(" -> SF");
        Serial.print(gCurrentSf);
        Serial.println(" (NOT applied — HQ locked at SF9)");
    }
}

// ================= REGISTRATION =================
static String buildRegistrationPayload() {
    return "auth=" + gAuthKey + "&aes_key=" + gAesKey + "&cmd=hello";
}

static bool checkLoRaResponse() {
    int packetSize = LoRa.parsePacket();
    if (packetSize <= 0) return false;

    uint8_t buf[SmartPacket::MAX_PACKET_BYTES];
    int len = 0;
    while (LoRa.available() && len < SmartPacket::MAX_PACKET_BYTES) {
        buf[len++] = LoRa.read();
    }
    LoRa.receive();

    if (len < 44) return false;

    uint32_t magic;
    memcpy(&magic, buf, 4);
    if (magic != SmartPacket::MAGIC) return false;
    if (buf[4] != SmartPacket::VERSION) return false;

    char hwId[17] = {0};
    memcpy(hwId, buf + 5, 16);
    if (gHardwareId != String(hwId)) return false;

    uint16_t payloadLen = buf[21] | ((uint16_t)buf[22] << 8);
    size_t expected = SmartPacket::HEADER_SIZE + SmartPacket::NONCE_SIZE + payloadLen + SmartPacket::CRC_SIZE;
    if ((size_t)len != expected) return false;

    uint32_t calcCrc = SmartPacket::crc32(buf, len - SmartPacket::CRC_SIZE);
    uint32_t recvCrc;
    memcpy(&recvCrc, buf + len - SmartPacket::CRC_SIZE, SmartPacket::CRC_SIZE);
    if (calcCrc != recvCrc) return false;

    const uint8_t* nonce = buf + SmartPacket::HEADER_SIZE;
    const uint8_t* ciphertext = buf + SmartPacket::HEADER_SIZE + SmartPacket::NONCE_SIZE;

    uint8_t keyBuf[16];
    memcpy(keyBuf, gAesKey.c_str(), 16);

    uint8_t counter[SmartPacket::NONCE_SIZE];
    memcpy(counter, nonce, SmartPacket::NONCE_SIZE);
    size_t ncOff = 0;
    uint8_t streamBlock[16] = {0};

    std::vector<uint8_t> plain(payloadLen);
    mbedtls_aes_context aes;
    mbedtls_aes_init(&aes);
    mbedtls_aes_setkey_enc(&aes, keyBuf, 128);
    mbedtls_aes_crypt_ctr(&aes, payloadLen, &ncOff, counter, streamBlock, ciphertext, plain.data());
    mbedtls_aes_free(&aes);

    String plaintext;
    for (size_t i = 0; i < payloadLen; i++) {
        if (plain[i] == 0) break;
        plaintext += (char)plain[i];
    }
    plaintext.trim();

    if (plaintext.length() == 0) return false;

    gLastHqSeenMs = millis();

    int hqRssi = LoRa.packetRssi();
    if (hqRssi > gBestHqRssi) {
        gBestHqRssi = hqRssi;
        Serial.print("[ADR] New best HQ RSSI: ");
        Serial.println(gBestHqRssi);
    }

    String cmd = SmartPacket::getFieldValue(plaintext, "cmd");

    // Handle relay command from HQ
    if (cmd == "relay") {
        String relayAuth = SmartPacket::getFieldValue(plaintext, "auth");
        if (relayAuth == gAuthKey) {
            int relayId = SmartPacket::getFieldValue(plaintext, "relay").toInt();
            int state = SmartPacket::getFieldValue(plaintext, "state").toInt();
            uint32_t commandId = (uint32_t)SmartPacket::getFieldValue(plaintext, "command_id").toInt();

            // Skip if we already processed this command
            if (commandId == gLastRelayCmdId) {
                return false;
            }
            gLastRelayCmdId = commandId;

            Serial.print("[RELAY] cmd_id="); Serial.print(commandId);
            Serial.print(" relay="); Serial.print(relayId);
            Serial.print(" state="); Serial.println(state);

            int relayPins[] = {26, 25};
            if (relayId >= 0 && relayId < 2) {
                int pin = relayPins[relayId];
                pinMode(pin, OUTPUT);
                digitalWrite(pin, state ? HIGH : LOW);
                Serial.print("[RELAY] GPIO"); Serial.print(pin);
                Serial.print(" -> "); Serial.println(state ? "ON" : "OFF");

                // Build ACK payload in a separate buffer so we don't corrupt gPacketBuf
                std::vector<uint8_t> ackBuf;
                String ackPayload = "auth=" + gAuthKey + "&ack=relay";
                ackPayload += "&command_id=" + String(commandId);
                ackPayload += "&status=done&relay=" + String(relayId);
                ackPayload += "&state=" + String(state) + "&msg=ok";

                uint8_t hwIdBytes[16];
                memcpy(hwIdBytes, gHardwareId.c_str(), 16);
                gPacketBuilder.build(ackPayload, hwIdBytes, ackBuf);

                waitForClearChannel();
                LoRa.beginPacket();
                LoRa.write(ackBuf.data(), ackBuf.size());
                LoRa.endPacket();
                delay(20);
                LoRa.receive();
                Serial.print("[RELAY] ACK sent, cmd_id="); Serial.println(commandId);
            }
        }
        return true;  // Updates gLastHqSeenMs — prevents false "HQ lost" fallbacks
    }

    return (cmd == "approve" || cmd == "ack");
}

// ================= IDLE WAIT =================
void serialCommand(const String& input);
static void idleWait(unsigned long ms) {
    unsigned long start = millis();
    while (millis() - start < ms) {
        if (Serial.available()) {
            String line = Serial.readStringUntil('\n');
            line.trim();
            if (line.length() > 0) serialCommand(line);
        }
        checkLoRaResponse();
        delay(5);
    }
}

// ================= SETUP =================
void setup() {
    Serial.begin(115200);
    delay(1000);

    Serial.println();
    Serial.println("====================================================");
    Serial.println("  SmartPonic Node Transmitter (38-Pin)");
    Serial.println("  Pure LoRa Link v1.0");
    Serial.println("====================================================");

    gBootMs = millis();

    gHardwareId = getHardwareId();
    loadKeys();
    setupDefaultSensors();

    uint8_t keyBuf[16];
    memcpy(keyBuf, gAesKey.c_str(), 16);
    gPacketBuilder.setKey(keyBuf);

    gReadings.reserve(MAX_SENSORS * 2);
    gPacketBuf.reserve(255);
    gBinaryPayload.reserve(128);

    // LoRa init
    Serial.println("[RADIO] Initializing LoRa on 433MHz...");
    Serial.print("[RADIO] SPI pins: SCK=");
    Serial.print(LORA_SCK);
    Serial.print(" MISO=");
    Serial.print(LORA_MISO);
    Serial.print(" MOSI=");
    Serial.print(LORA_MOSI);
    Serial.print(" SS=");
    Serial.println(LORA_SS);
    Serial.print("[RADIO] LoRa pins: SS=");
    Serial.print(LORA_SS);
    Serial.print(" RST=");
    Serial.print(LORA_RST);
    Serial.print(" DIO0=");
    Serial.println(LORA_DIO0);

    SPI.begin(LORA_SCK, LORA_MISO, LORA_MOSI, LORA_SS);
    LoRa.setPins(LORA_SS, LORA_RST, LORA_DIO0);

    if (!LoRa.begin(LORA_BAND)) {
        Serial.println("[RADIO] ERROR: LoRa.begin() FAILED!");
        Serial.println("[RADIO] Check wiring, frequency, and module power");
    } else {
        Serial.println("[RADIO] LoRa.begin() SUCCESS");
        configureRadio();
    }

    // Initial sample
    Serial.println("[SETUP] Taking initial sensor sample...");
    gSensorMgr.sample(gReadings);
    gLastSampleMs = millis();

    LoRa.receive();

    Serial.println("====================================================");
    Serial.println("  System READY");
    Serial.print("  Hardware ID: ");
    Serial.println(gHardwareId);
    Serial.print("  Sensors: ");
    Serial.println(gSensorMgr.count());
    Serial.print("  Sample interval: ");
    Serial.print(SmartPacket::SAMPLE_INTERVAL_MS / 1000);
    Serial.println("s");
    Serial.println("  Type HELP for commands");
    Serial.println("====================================================");
    Serial.println();
}

// ================= LOOP =================
void loop() {
    unsigned long now = millis();

    if (gNodeState == STATE_REGISTERING) {
        if (checkLoRaResponse()) {
            gNodeState = STATE_CONNECTED;
            gLastSampleMs = millis();
            gLastHqSeenMs = millis();
            Serial.println();
            Serial.println("═══════════════════════════════════════════");
            Serial.println("  HANDSHAKE COMPLETE - Starting telemetry");
            Serial.println("═══════════════════════════════════════════");
            Serial.println();
        }

        if (gNodeState == STATE_REGISTERING && now - gLastRegMs >= REG_INTERVAL_MS) {
            gLastRegMs = now;
            gRegAttempt++;

            String regPayload = buildRegistrationPayload();
            uint8_t hwIdBytes[16];
            memcpy(hwIdBytes, gHardwareId.c_str(), 16);
            gPacketBuilder.build(regPayload, hwIdBytes, gPacketBuf);

            Serial.println();
            Serial.println("═══════════════════════════════════════════");
            Serial.println("  REGISTERING");
            Serial.println("═══════════════════════════════════════════");
            Serial.print("  HW: "); Serial.println(gHardwareId);
            Serial.print("  TX: "); Serial.print(gPacketBuf.size()); Serial.println("B  awaiting approval...");
            Serial.println("───────────────────────────────────────────");

            waitForClearChannel();

            LoRa.beginPacket();
            LoRa.write(gPacketBuf.data(), gPacketBuf.size());
            LoRa.endPacket();
            delay(20);
            LoRa.receive();

            // Poll for response briefly (2s window to catch HQ approval)
            unsigned long pollDeadline = millis() + 2000;
            while (millis() < pollDeadline) {
                if (checkLoRaResponse()) {
                    gNodeState = STATE_CONNECTED;
                    gLastSampleMs = millis();
                    gLastHqSeenMs = millis();
                    Serial.println();
                    Serial.println("═══════════════════════════════════════════");
                    Serial.println("  HANDSHAKE COMPLETE - Starting telemetry");
                    Serial.println("═══════════════════════════════════════════");
                    Serial.println();
                    break;
                }
                delay(10);
            }
        }

        if (gNodeState == STATE_REGISTERING) {
            unsigned long elapsed = millis() - gLastRegMs;
            if (elapsed < REG_INTERVAL_MS) {
                idleWait(REG_INTERVAL_MS - elapsed);
            }
        }
    }

    if (gNodeState == STATE_CONNECTED) {
        checkLoRaResponse();

        if (now - gLastSampleMs >= gPriorityEngine.getIntervalMs()) {
            gLastSampleMs = now;

            if (now - gLastAdrUpdateMs >= ADR_UPDATE_INTERVAL_MS) {
                gLastAdrUpdateMs = now;
                updateAdr();
            }

            gSensorMgr.sample(gReadings);

            // Classify priority across all readings
            gPriorityEngine.evaluate(gReadings);
            uint8_t currentPrio = gPriorityEngine.getPriority();
            uint8_t currentMode = gPriorityEngine.getReportMode();

            buildBinaryPayload(gReadings, gBinaryPayload, currentPrio, currentMode);

            uint8_t hwIdBytes[16];
            memcpy(hwIdBytes, gHardwareId.c_str(), 16);
            gPacketBuilder.build(gBinaryPayload.data(), gBinaryPayload.size(),
                                  hwIdBytes, gPacketBuf);

            Serial.println();
            Serial.println("═══════════════════════════════════════════");
            Serial.print("  SAMPLE #"); Serial.print(gPacketCount + 1);
            Serial.print("  Prio="); Serial.print(SmartPacket::priorityLabel(currentPrio));
            Serial.print("  Mode="); Serial.print(SmartPacket::reportModeLabel(currentMode));
            Serial.print("  (+"); Serial.print(gPriorityEngine.getIntervalMs() / 1000); Serial.println("s)");
            Serial.print("  SF"); Serial.print(gCurrentSf);
            Serial.print("  BestRSSI="); Serial.print(gBestHqRssi);
            Serial.println("dBm");
            Serial.println("═══════════════════════════════════════════");
            Serial.print("  ");
            for (const auto& r : gReadings) {
                Serial.print(r.segment); Serial.print("  ");
            }
            Serial.println();
            Serial.println("───────────────────────────────────────────");
            Serial.print("  TX: "); Serial.print(gPacketBuf.size()); Serial.println("B (binary)");
            Serial.println("───────────────────────────────────────────");

            waitForClearChannel();

            LoRa.beginPacket();
            LoRa.write(gPacketBuf.data(), gPacketBuf.size());
            LoRa.endPacket();
            delay(20);
            LoRa.receive();

            gPacketCount++;

            // Wait for ACK from HQ (up to 3s after TX)
            unsigned long ackDeadline = millis() + 3000;
            unsigned long hqBefore = gLastHqSeenMs;
            while (millis() < ackDeadline) {
                if (checkLoRaResponse()) {
                    gMissedAckCount = 0;
                    break;
                }
                delay(5);
            }
            if (gLastHqSeenMs <= hqBefore) {
                gMissedAckCount++;
                Serial.print("  ACK missed ("); Serial.print(gMissedAckCount); Serial.println("/5)");
                if (gMissedAckCount >= 5) {
                    gNodeState = STATE_REGISTERING;
                    gLastRegMs = 0;
                    gRegAttempt = 0;
                    Serial.println("  HQ LOST - Falling back to registration");
                }
            }
        }

        if (gNodeState == STATE_CONNECTED) {
            unsigned long elapsed = millis() - gLastSampleMs;
            unsigned long interval = gPriorityEngine.getIntervalMs();
            if (elapsed < interval) {
                idleWait(interval - elapsed);
            }
        }
    }

    // Serial CLI
    if (Serial.available()) {
        String line = Serial.readStringUntil('\n');
        line.trim();
        if (line.length() > 0) {
            serialCommand(line);
        }
    }
}

// ================= SERIAL CLI =================
void serialCommand(const String& input) {
    String upper = input;
    upper.toUpperCase();

    if (upper == "HELP" || upper == "?") {
        Serial.println("====================================================");
        Serial.println("SmartPonic Node CLI Commands:");
        Serial.println("====================================================");
        Serial.println("  HELP / ?         - Show this help");
        Serial.println("  ID               - Show hardware ID");
        Serial.println("  LIST             - List all sensor configurations");
        Serial.println("  KEYS / SHOWKEYS  - Show AES and AUTH keys");
        Serial.println("  SETKEYS,AES=xx,AUTH=yy  - Update encryption keys");
        Serial.println("  CLEARKEYS        - Reset keys to factory defaults");
        Serial.println("  STATUS           - Show system status & uptime");
        Serial.println("  ADD,pin,type,sensor,label - Add sensor dynamically");
        Serial.println("====================================================");
        return;
    }

    if (upper == "ID") {
        Serial.print("Hardware ID: ");
        Serial.println(gHardwareId);
        return;
    }

    if (upper == "STATUS") {
        unsigned long ms = millis();
        Serial.println("=== System Status ===");
        Serial.print("Uptime: ");
        Serial.print(ms / 1000);
        Serial.println(" seconds");
        Serial.print("Heap free: ");
        Serial.print(ESP.getFreeHeap());
        Serial.println(" bytes");
        Serial.print("Hardware ID: ");
        Serial.println(gHardwareId);
        Serial.print("Sensors configured: ");
        Serial.println(gSensorMgr.count());
        Serial.print("Last sample: ");
        Serial.print(ms - gLastSampleMs);
        Serial.println("ms ago");
        Serial.print("Packets sent: ");
        Serial.println(gPacketCount);
        Serial.print("AES key length: ");
        Serial.print(gAesKey.length());
        Serial.println(" chars");
        Serial.print("AUTH key length: ");
        Serial.print(gAuthKey.length());
        Serial.println(" chars");
        return;
    }

    if (upper == "LIST") {
        Serial.print("Sensor count: ");
        Serial.println(gSensorMgr.count());
        Serial.println("Idx | Pin | Type | Sensor | Label");
        Serial.println("----+-----+------+--------+-----------------------------");
        for (int i = 0; i < gSensorMgr.count(); i++) {
            auto& c = gSensorMgr.getConfig(i);
            Serial.print("  ");
            Serial.print(i);
            Serial.print(" | ");
            Serial.print(c.pin);
            if (c.pin < 10) Serial.print(" ");
            Serial.print(" | ");
            Serial.print(c.type);
            Serial.print(" | ");
            Serial.print(c.sensor);
            Serial.print(" | ");
            Serial.println(c.label);
        }
        return;
    }

    if (upper == "KEYS" || upper == "SHOWKEYS") {
        Serial.println("=== Current Keys ===");
        Serial.print("AES:  '");
        Serial.print(gAesKey);
        Serial.println("'");
        Serial.print("AUTH: '");
        Serial.print(gAuthKey);
        Serial.println("'");
        Serial.print("AES length: ");
        Serial.print(gAesKey.length());
        Serial.println(" (must be 16)");
        return;
    }

    if (upper == "CLEARKEYS") {
        clearKeys();
        return;
    }

    if (upper.startsWith("SETKEYS,")) {
        String args = input.substring(8);
        int aesPos = args.indexOf("AES=");
        if (aesPos >= 0) {
            int start = aesPos + 4;
            int end = args.indexOf(',', start);
            if (end < 0) end = args.length();
            saveAesKey(args.substring(start, end));
        }
        int authPos = args.indexOf("AUTH=");
        if (authPos >= 0) {
            int start = authPos + 5;
            int end = args.indexOf(',', start);
            if (end < 0) end = args.length();
            saveAuthKey(args.substring(start, end));
        }

        uint8_t keyBuf[16];
        memcpy(keyBuf, gAesKey.c_str(), 16);
        gPacketBuilder.setKey(keyBuf);
        return;
    }

    if (upper.startsWith("ADD,")) {
        int c1 = input.indexOf(',', 4);
        if (c1 < 0) return;
        int c2 = input.indexOf(',', c1 + 1);
        if (c2 < 0) return;
        int c3 = input.indexOf(',', c2 + 1);
        if (c3 < 0) return;

        int pin = input.substring(4, c1).toInt();
        String type   = input.substring(c1 + 1, c2);
        String sensor = input.substring(c2 + 1, c3);
        String label  = input.substring(c3 + 1);
        type.trim(); sensor.trim(); label.trim();

        if (gSensorMgr.addSensor(pin, type, sensor, label)) {
            Serial.println("[CLI] Sensor added successfully");
        } else {
            Serial.println("[CLI] ERROR: Add failed (invalid pin or duplicate)");
        }
        return;
    }

    Serial.print("[CLI] Unknown command: ");
    Serial.println(input);
    Serial.println("Type HELP for available commands");
}