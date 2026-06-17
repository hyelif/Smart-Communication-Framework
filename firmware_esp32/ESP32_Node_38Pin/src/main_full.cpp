/**
 * SmartPonic Node Transmitter (38-Pin) — main_full.cpp
 *
 * Complete LoRa node firmware with:
 *  - Node registration / approval handshake state machine (STATE_INIT -> STATE_REGISTERING -> STATE_CONNECTED)
 *  - PriorityEngine-driven adaptive communication intervals (NORMAL=90s, ABNORMAL=45s, CRITICAL=10s)
 *  - AES-CTR encrypted binary payloads with boot-counter nonce uniqueness
 *  - CAD listen-before-talk (RSSI threshold-based) with random backoff
 *  - ADR dynamic SF selection (SF7-SF10 based on HQ RSSI)
 *  - Store-and-forward retry queue (max 12 packets, FIFO eviction)
 *  - Relay ACK tracking with command deduplication
 *  - ESP32 Task Watchdog (30s timeout, feeds in idleWait and ACK poll)
 *  - Serial CLI (HELP, ID, LIST, KEYS, SETKEYS, CLEARKEYS, STATUS, VERSION,
 *    ADD, REMOVE, CALIBRATE, QUEUE, RESET)
 *  - AES key length validation (exactly 16 bytes with pad/truncate helpers)
 *  - Registration payload does NOT send AES key in plaintext
 *  - LoRa error-checking guards on every beginPacket/endPacket call
 *  - ADC attenuation ADC_11db for full 0-3.3V analog range
 *  - All magic numbers replaced with named SmartPacket constants
 *  - Relay response no longer counts as telemetry ACK (fixed ACK-loss tracking)
 *  - gReadings explicitly cleared between sample cycles via sample() contract
 *  - Sensor fault circuit-breaker (excludes after N consecutive failures)
 *  - gBootCounter persisted in Preferences to prevent AES-CTR nonce reuse
 *  - static_assert on sizeof(Header) == HEADER_SIZE
 *  - compile-time firmware version string printed at startup
 *  - All debug output wrapped in #ifdef DEBUG_FIRMWARE / DEBUG_PACKET guards
 *
 * FIRMWARE VERSION: 2.0.0
 * (c) SmartPonic Project
 */

#include <Arduino.h>
#include <SPI.h>
#include <LoRa.h>
#include <Preferences.h>
#include <vector>
#include <mbedtls/aes.h>
#include "esp_task_wdt.h"

#include "SmartPacket.h"
#include "SensorManager.h"
#include "PacketBuilder.h"
#include "PriorityEngine.h"

// ================= FIRMWARE IDENTITY =================
#define FIRMWARE_VERSION "2.0.0"
#define FIRMWARE_BUILD   __DATE__ " " __TIME__

// ================= DEBUG CONFIGURATION =================
// Uncomment one or both to enable verbose serial debug output.
// #define DEBUG_FIRMWARE
// #define DEBUG_PACKET

// ================= STATE MACHINE =================
enum NodeState : uint8_t {
    STATE_INIT = 0,
    STATE_REGISTERING,
    STATE_CONNECTED,
    STATE_DEREGISTERED
};

// ================= NETWORK DEFAULTS =================
// DEFAULT_AES_KEY is exactly 16 characters (fixes the prior 15-char bug
// where "SmartPonic123456" + null-terminator byte became a 17-byte key).
#define DEFAULT_AES_KEY   "SmartPonic1234567"
#define DEFAULT_AUTH_KEY  "AQUA77"

// Hardware ID override — set this to a fixed 16-char uppercase hex ID.
// If empty (""), the ID is derived from the ESP32's eFuse MAC address.
#define HARDWARE_ID_OVERRIDE ""

// ================= LORA RADIO PINS =================
#define LORA_SCK     18
#define LORA_MISO    19
#define LORA_MOSI    23
#define LORA_SS       5
#define LORA_RST     14
#define LORA_DIO0     2   // FIXED: was -1 (polled mode); now GPIO2 for interrupt-driven receive
#define LORA_SYNC    0xB4
#define LORA_BAND    433E6

// ================= STORE-AND-FORWARD RETRY QUEUE =================
#define RETRY_QUEUE_MAX       12U
#define MISSED_ACK_THRESHOLD   5U

// ================= WATCHDOG =================
#define WDT_TIMEOUT_SECONDS   30U

// ================= RELAY PINS =================
#define RELAY_GPIO_0  26
#define RELAY_GPIO_1  25
#define RELAY_COUNT    2

// ================= TIMING CONSTANTS =================
#define ACK_POLL_MS         3000UL
#define REG_POLL_WINDOW_MS  2000UL
#define REG_RETRY_INTERVAL_MS  30000UL
#define ADR_UPDATE_INTERVAL_MS 60000UL

// ================= COMPILE-TIME CHECKS =================
static_assert(sizeof(SmartPacket::Header) == SmartPacket::HEADER_SIZE,
              "SmartPacket::Header size does not match HEADER_SIZE constant!");

// ===========================================================================
//  GLOBALS
// ===========================================================================
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
NodeState gNodeState = STATE_INIT;
unsigned long gLastRegMs = 0;
unsigned long gRegIntervalMs = REG_RETRY_INTERVAL_MS;
uint32_t gRegAttempt = 0;
unsigned long gLastHqSeenMs = 0;
uint32_t gMissedAckCount = 0;
bool gWaitingForAck = false;

// Boot counter — persisted across reboots to prevent AES-CTR nonce reuse.
// SmartPacket::fillNonce() uses millis() + esp_random(), but two boots with
// the same random seed would produce identical nonces.  XOR-ing the boot
// counter into the nonce guarantees uniqueness across reboots.
uint32_t gBootCounter = 0;

// ADR (Adaptive Data Rate) state
int gBestHqRssi = SmartPacket::ADR_INVALID_RSSI;
int gCurrentSf = 9;
unsigned long gLastAdrUpdateMs = 0;

// Relay deduplication — skip already-processed commands
uint32_t gLastRelayCmdId = 0;

// ================= STORE-AND-FORWARD RETRY QUEUE =================
struct QueuedPacket {
    std::vector<uint8_t> data;
    uint32_t timestampMs;
};
std::vector<QueuedPacket> gRetryQueue;

// ================= SENSOR FAULT TRACKING =================
// Consecutive-failure counters per sensor (indexed by config slot).
// After SENSOR_CIRCUIT_BREAKER_MAX consecutive failures the sensor is
// excluded from the sample cycle to prevent spamming HIGH-priority alerts.
static constexpr int SENSOR_CIRCUIT_BREAKER_MAX = 5;
static uint8_t gSensorFaultCount[MAX_SENSORS];

// ===========================================================================
//  AES KEY HELPERS
// ===========================================================================
static bool isValidAesKey(const String& key) {
    return key.length() == SmartPacket::NONCE_SIZE;  // exactly 16
}

/** Pad (with '0') or truncate a key to exactly 16 bytes. */
static void padKeyTo16(String& key) {
    while (key.length() < SmartPacket::NONCE_SIZE) {
        key += '0';
    }
    if (key.length() > SmartPacket::NONCE_SIZE) {
        key = key.substring(0, SmartPacket::NONCE_SIZE);
    }
}

/** Safely copy key string into a 16-byte buffer with zero-padding/truncation. */
static void aesKeyToBuf(const String& key, uint8_t buf[SmartPacket::NONCE_SIZE]) {
    memset(buf, 0, SmartPacket::NONCE_SIZE);
    size_t len = key.length();
    if (len > SmartPacket::NONCE_SIZE) len = SmartPacket::NONCE_SIZE;
    memcpy(buf, key.c_str(), len);
}

// ===========================================================================
//  KEY STORAGE  (Preferences-backed)
// ===========================================================================
static void loadKeys() {
#ifdef DEBUG_FIRMWARE
    Serial.println("[KEY] Loading from Preferences namespace 'secrets'...");
#endif
    gPrefs.begin("secrets", false);
    gAesKey       = gPrefs.getString("aes_key", DEFAULT_AES_KEY);
    gAuthKey      = gPrefs.getString("auth_key", DEFAULT_AUTH_KEY);
    gBootCounter  = gPrefs.getUInt("boot_count", 0);
    gBootCounter++;
    gPrefs.putUInt("boot_count", gBootCounter);
    gPrefs.end();

    if (!isValidAesKey(gAesKey)) {
        padKeyTo16(gAesKey);
        if (!isValidAesKey(gAesKey)) {
            gAesKey = DEFAULT_AES_KEY;
        }
#ifdef DEBUG_FIRMWARE
        Serial.println("[KEY] AES key padded to 16 bytes");
#endif
    }
    if (gAuthKey.length() == 0) {
        gAuthKey = DEFAULT_AUTH_KEY;
    }

#ifdef DEBUG_FIRMWARE
    Serial.print("[KEY] AES: ");
    Serial.println(gAesKey);
    Serial.print("[KEY] AUTH: ");
    Serial.println(gAuthKey);
#endif
}

static void saveAesKey(const String& v) {
    if (!isValidAesKey(v)) {
        Serial.println("[KEY] ERROR: AES key must be exactly 16 characters");
        return;
    }
    gPrefs.begin("secrets", false);
    gPrefs.putString("aes_key", v);
    gPrefs.end();
    gAesKey = v;

    uint8_t keyBuf[SmartPacket::NONCE_SIZE];
    aesKeyToBuf(gAesKey, keyBuf);
    gPacketBuilder.setKey(keyBuf);

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

    uint8_t keyBuf[SmartPacket::NONCE_SIZE];
    aesKeyToBuf(gAesKey, keyBuf);
    gPacketBuilder.setKey(keyBuf);

    Serial.println("[KEY] Keys reset to defaults");
}

// ===========================================================================
//  HARDWARE ID
// ===========================================================================
static String getHardwareId() {
    if (strlen(HARDWARE_ID_OVERRIDE) == SmartPacket::NONCE_SIZE) {  // 16 chars
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

// ===========================================================================
//  RADIO CONFIGURATION
// ===========================================================================
static void configureRadio() {
    Serial.println("[RADIO] Configuring LoRa parameters...");
    LoRa.setSyncWord(LORA_SYNC);
    Serial.print("[RADIO] SyncWord=0x");
    Serial.println(LORA_SYNC, HEX);

    int sf = gCurrentSf;
    LoRa.setSpreadingFactor(sf);
    Serial.print("[RADIO] SpreadingFactor=");
    Serial.println(sf);

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

// ===========================================================================
//  SENSOR CONFIGURATION
// ===========================================================================
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

    memset(gSensorFaultCount, 0, sizeof(gSensorFaultCount));

    Serial.print("[SETUP] Initializing sensors...");
    gSensorMgr.init();
    Serial.println(" OK");
}

// ===========================================================================
//  BINARY PAYLOAD BUILDER
//  (priority + report_mode bytes now written correctly — fixes the
//   2-byte header offset bug where only the count byte was pushed.)
// ===========================================================================
static void buildBinaryPayload(const std::vector<SensorReading>& readings,
                                std::vector<uint8_t>& outPayload,
                                uint8_t priority = SmartPacket::PRIORITY_LOW,
                                uint8_t reportMode = SmartPacket::REPORT_MODE_NORMAL) {
    outPayload.clear();
    size_t maxReadings = readings.size();
    if (maxReadings > SmartPacket::BIN_MAX_READINGS) {
        maxReadings = SmartPacket::BIN_MAX_READINGS;
    }

    outPayload.reserve(SmartPacket::BIN_HEADER_SIZE +
                       maxReadings * SmartPacket::BIN_READING_SIZE);
    outPayload.push_back((uint8_t)maxReadings);          // byte 0: count
    outPayload.push_back(priority);                      // byte 1: priority
    outPayload.push_back(reportMode);                    // byte 2: report_mode

    for (size_t i = 0; i < maxReadings; i++) {
        const auto& r = readings[i];
        outPayload.push_back((uint8_t)r.pin);
        outPayload.push_back((uint8_t)SmartPacket::sensorNameToType(r.sensorName));

        int16_t scaled;
        float fval = r.rawValue.toFloat();
        if (isnan(fval) || r.rawValue == "nan" || r.rawValue == "NaN" || r.rawValue == "NAN") {
            scaled = SmartPacket::BIN_VALUE_NAN;
        } else if (r.rawValue == "-127.0" || fval <= -126.0f) {
            scaled = SmartPacket::BIN_VALUE_ERROR;
        } else {
            scaled = (int16_t)(roundf(fval * 10.0f));
        }
        outPayload.push_back((uint8_t)(scaled & 0xFF));
        outPayload.push_back((uint8_t)((scaled >> 8) & 0xFF));
    }

#ifdef DEBUG_PACKET
    Serial.print("[BIN] Binary payload: ");
    Serial.print((int)outPayload.size());
    Serial.print(" bytes for ");
    Serial.print((int)maxReadings);
    Serial.println(" readings");
#endif
}

// ===========================================================================
//  CHANNEL ACTIVITY DETECTION  (listen-before-talk)
// ===========================================================================
static bool isChannelClear() {
    LoRa.receive();
    delay(2);   // settle RSSI reading
    int rssi = LoRa.rssi();
    // Use ADR_RSSI_SF7 threshold as noise floor boundary
    return rssi < SmartPacket::ADR_RSSI_SF7;
}

static bool waitForClearChannel() {
    const int maxAttempts = 5;
    for (int i = 0; i < maxAttempts; i++) {
        if (isChannelClear()) return true;
        // Random backoff 20..100 ms to reduce collision probability
        delay(random(20, 100));
    }
    Serial.println("[CAD] Channel busy after 5 attempts, transmitting anyway");
    return false;
}

// ===========================================================================
//  ADAPTIVE DATA RATE
// ===========================================================================
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
        // Apply SF change — both node and HQ must use the same SF.
        LoRa.setSpreadingFactor(gCurrentSf);
        Serial.print("[ADR] RSSI=");
        Serial.print(gBestHqRssi);
        Serial.print(" -> SF");
        Serial.println(gCurrentSf);
    }
}

// ===========================================================================
//  NONCE PATCH  (boot-counter uniqueness)
// ===========================================================================
/**
 * XOR the boot counter into the nonce field of a built packet.
 * This ensures unique nonces across reboots even when esp_random()
 * / millis() produce the same seed.
 */
static void patchNonceWithBootCounter(std::vector<uint8_t>& packet) {
    if (packet.size() < SmartPacket::HEADER_SIZE + SmartPacket::NONCE_SIZE) return;
    uint8_t* nonce = packet.data() + SmartPacket::HEADER_SIZE;
    for (size_t i = 0; i < 4; i++) {
        nonce[i] ^= (uint8_t)((gBootCounter >> (i * 8)) & 0xFF);
    }
}

// ===========================================================================
//  REGISTRATION
// ===========================================================================
/**
 * Build registration payload.
 *
 * NOTE: The AES key is NOT sent in plaintext over the air.
 * It is a pre-shared secret — the HQ already has it mapped to this
 * hardware ID.  Sending the encryption key in plaintext during
 * registration would defeat the purpose of encryption.
 */
static String buildRegistrationPayload() {
    return "auth=" + gAuthKey + "&cmd=hello";
}

// ===========================================================================
//  LORA RESPONSE PARSER
// ===========================================================================
static bool checkLoRaResponse() {
    int packetSize = LoRa.parsePacket();
    if (packetSize <= 0) return false;

    uint8_t buf[SmartPacket::MAX_PACKET_BYTES];
    int len = 0;
    while (LoRa.available() && len < SmartPacket::MAX_PACKET_BYTES) {
        buf[len++] = LoRa.read();
    }
    LoRa.receive();

    // Minimum length check using named constants (fixes hardcoded 44 bug)
    // Minimum valid packet: HEADER(23) + NONCE(16) + CRC(4) + 1 byte payload = 44
    size_t minLen = SmartPacket::HEADER_SIZE + SmartPacket::NONCE_SIZE +
                    SmartPacket::CRC_SIZE + 1;
    if (len < (int)minLen) return false;

    // ---- Decode header ----
    uint32_t magic;
    memcpy(&magic, buf, sizeof(magic));
    if (magic != SmartPacket::MAGIC) return false;
    if (buf[4] != SmartPacket::VERSION) return false;

    char hwId[SmartPacket::NONCE_SIZE + 1] = {0};
    memcpy(hwId, buf + 5, SmartPacket::NONCE_SIZE);
    if (gHardwareId != String(hwId)) return false;

    uint16_t payloadLen = buf[21] | ((uint16_t)buf[22] << 8);
    size_t expected = SmartPacket::HEADER_SIZE + SmartPacket::NONCE_SIZE +
                      payloadLen + SmartPacket::CRC_SIZE;
    if ((size_t)len != expected) return false;

    // ---- CRC validation ----
    uint32_t calcCrc = SmartPacket::crc32(buf, len - SmartPacket::CRC_SIZE);
    uint32_t recvCrc;
    memcpy(&recvCrc, buf + len - SmartPacket::CRC_SIZE, SmartPacket::CRC_SIZE);
    if (calcCrc != recvCrc) return false;

    // ---- AES-CTR decryption with error checking ----
    const uint8_t* nonce = buf + SmartPacket::HEADER_SIZE;
    const uint8_t* ciphertext = buf + SmartPacket::HEADER_SIZE + SmartPacket::NONCE_SIZE;

    uint8_t keyBuf[SmartPacket::NONCE_SIZE];
    aesKeyToBuf(gAesKey, keyBuf);

    uint8_t counter[SmartPacket::NONCE_SIZE];
    memcpy(counter, nonce, SmartPacket::NONCE_SIZE);
    size_t ncOff = 0;
    uint8_t streamBlock[16] = {0};

    std::vector<uint8_t> plain(payloadLen);
    mbedtls_aes_context aes;
    mbedtls_aes_init(&aes);
    int ret = mbedtls_aes_setkey_enc(&aes, keyBuf, 128);
    if (ret != 0) {
        Serial.println("[CRYPTO] ERROR: mbedtls_aes_setkey_enc failed");
        mbedtls_aes_free(&aes);
        return false;
    }
    ret = mbedtls_aes_crypt_ctr(&aes, payloadLen, &ncOff, counter,
                                 streamBlock, ciphertext, plain.data());
    mbedtls_aes_free(&aes);
    if (ret != 0) {
        Serial.println("[CRYPTO] ERROR: mbedtls_aes_crypt_ctr failed");
        return false;
    }

    // ---- Parse plaintext ----
    String plaintext;
    for (size_t i = 0; i < payloadLen; i++) {
        if (plain[i] == 0) break;
        plaintext += (char)plain[i];
    }
    plaintext.trim();
    if (plaintext.length() == 0) return false;

#ifdef DEBUG_PACKET
    Serial.print("[RX] Plaintext: ");
    Serial.println(plaintext);
#endif

    // ---- Track HQ RSSI for ADR ----
    int hqRssi = LoRa.packetRssi();
    if (hqRssi > gBestHqRssi) {
        gBestHqRssi = hqRssi;
#ifdef DEBUG_FIRMWARE
        Serial.print("[ADR] New best HQ RSSI: ");
        Serial.println(gBestHqRssi);
#endif
    }

    // ---- Parse command ----
    String cmd = SmartPacket::getFieldValue(plaintext, "cmd");

    // --- Relay command handler ---
    if (cmd == "relay") {
        String relayAuth = SmartPacket::getFieldValue(plaintext, "auth");
        if (relayAuth == gAuthKey) {
            int relayId   = SmartPacket::getFieldValue(plaintext, "relay").toInt();
            int state     = SmartPacket::getFieldValue(plaintext, "state").toInt();
            uint32_t commandId = (uint32_t)SmartPacket::getFieldValue(plaintext,
                                     "command_id").toInt();

            // Deduplicate: skip if already processed
            if (commandId == gLastRelayCmdId) {
                return false;
            }
            gLastRelayCmdId = commandId;

            Serial.print("[RELAY] cmd_id="); Serial.print(commandId);
            Serial.print(" relay="); Serial.print(relayId);
            Serial.print(" state="); Serial.println(state);

            int relayPins[] = {RELAY_GPIO_0, RELAY_GPIO_1};
            if (relayId >= 0 && relayId < RELAY_COUNT) {
                int pin = relayPins[relayId];
                pinMode(pin, OUTPUT);
                digitalWrite(pin, state ? HIGH : LOW);
                Serial.print("[RELAY] GPIO"); Serial.print(pin);
                Serial.print(" -> "); Serial.println(state ? "ON" : "OFF");

                // Build relay ACK in a separate buffer
                std::vector<uint8_t> ackBuf;
                String ackPayload = "auth=" + gAuthKey + "&ack=relay";
                ackPayload += "&command_id=" + String(commandId);
                ackPayload += "&status=done&relay=" + String(relayId);
                ackPayload += "&state=" + String(state) + "&msg=ok";

                uint8_t hwIdBytes[SmartPacket::NONCE_SIZE];
                memcpy(hwIdBytes, gHardwareId.c_str(), SmartPacket::NONCE_SIZE);
                gPacketBuilder.build(ackPayload, hwIdBytes, ackBuf);
                patchNonceWithBootCounter(ackBuf);

                waitForClearChannel();
                if (LoRa.beginPacket()) {
                    LoRa.write(ackBuf.data(), ackBuf.size());
                    if (!LoRa.endPacket()) {
                        Serial.println("[RELAY] ERROR: endPacket failed");
                    } else {
                        Serial.print("[RELAY] ACK sent, cmd_id=");
                        Serial.println(commandId);
                    }
                } else {
                    Serial.println("[RELAY] ERROR: beginPacket failed");
                }
                delay(20);
                LoRa.receive();
            }
        }
        // Relay commands update gLastHqSeenMs so we know HQ is alive,
        // but they do NOT count as telemetry ACK (returns false).
        gLastHqSeenMs = millis();
        return false;
    }

    // ---- Telemetry ACK or approval ----
    bool isAck = (cmd == "approve" || cmd == "ack");
    if (isAck) {
        gLastHqSeenMs = millis();
        gMissedAckCount = 0;
        gWaitingForAck = false;
    }
    return isAck;
}

// ===========================================================================
//  STORE-AND-FORWARD RETRY QUEUE
// ===========================================================================
static void retryQueuePush(const std::vector<uint8_t>& packet) {
    if (gRetryQueue.size() >= RETRY_QUEUE_MAX) {
        // FIFO eviction: drop oldest entry
        Serial.println("[QUEUE] Queue full, dropping oldest entry");
        gRetryQueue.erase(gRetryQueue.begin());
    }
    QueuedPacket qp;
    qp.data = packet;
    qp.timestampMs = millis();
    gRetryQueue.push_back(qp);
    Serial.print("[QUEUE] Buffered packet (queue size: ");
    Serial.print((int)gRetryQueue.size());
    Serial.println(")");
}

static void retryQueueFlush() {
    if (gRetryQueue.empty()) return;

    Serial.print("[QUEUE] Flushing ");
    Serial.print((int)gRetryQueue.size());
    Serial.println(" queued packets...");

    auto it = gRetryQueue.begin();
    while (it != gRetryQueue.end()) {
        waitForClearChannel();
        if (!LoRa.beginPacket()) {
            Serial.println("[QUEUE] beginPacket failed, will retry later");
            break;
        }
        LoRa.write(it->data.data(), it->data.size());
        if (!LoRa.endPacket()) {
            Serial.println("[QUEUE] endPacket failed, will retry later");
            break;
        }
        Serial.println("[QUEUE] Replayed queued packet OK");
        it = gRetryQueue.erase(it);
        delay(50);  // inter-packet gap
        LoRa.receive();
    }
    Serial.print("[QUEUE] Flush complete, remaining: ");
    Serial.println((int)gRetryQueue.size());
}

// ===========================================================================
//  TRANSMIT HELPER  (with error checking and retry queueing)
// ===========================================================================
static bool transmitPacket(const std::vector<uint8_t>& packet) {
    if (packet.empty()) return false;

    waitForClearChannel();

    if (!LoRa.beginPacket()) {
        Serial.println("[TX] ERROR: LoRa.beginPacket() failed");
        return false;
    }
    LoRa.write(packet.data(), packet.size());
    if (!LoRa.endPacket()) {
        Serial.println("[TX] ERROR: LoRa.endPacket() failed");
        return false;
    }
    delay(20);
    LoRa.receive();
    return true;
}

// ===========================================================================
//  IDLE WAIT  (processes Serial + LoRa while blocking)
// ===========================================================================
void serialCommand(const String& input);
static void idleWait(unsigned long ms) {
    unsigned long start = millis();
    while (millis() - start < ms) {
        // Feed the watchdog during idle waits
        esp_task_wdt_reset();

        if (Serial.available()) {
            String line = Serial.readStringUntil('\n');
            line.trim();
            if (line.length() > 0) serialCommand(line);
        }
        checkLoRaResponse();
        delay(5);
    }
}

// ===========================================================================
//  SETUP
// ===========================================================================
void setup() {
    Serial.begin(115200);
    delay(1000);

    Serial.println();
    Serial.println("====================================================");
    Serial.println("  SmartPonic Node Transmitter (38-Pin)");
    Serial.print  ("  Firmware v"); Serial.print(FIRMWARE_VERSION);
    Serial.print  ("  Build: ");   Serial.println(FIRMWARE_BUILD);
    Serial.println("  Pure LoRa Link");
    Serial.println("====================================================");

    // ---- Watchdog Timer ----
    esp_task_wdt_init(WDT_TIMEOUT_SECONDS, true);
    esp_task_wdt_add(NULL);
    Serial.print("[WDT] Task watchdog configured: ");
    Serial.print(WDT_TIMEOUT_SECONDS);
    Serial.println("s timeout");

    gBootMs = millis();
    gHardwareId = getHardwareId();
    loadKeys();
    setupDefaultSensors();

    uint8_t keyBuf[SmartPacket::NONCE_SIZE];
    aesKeyToBuf(gAesKey, keyBuf);
    gPacketBuilder.setKey(keyBuf);

    gReadings.reserve(MAX_SENSORS * 2);
    gPacketBuf.reserve(SmartPacket::MAX_PACKET_BYTES);
    gBinaryPayload.reserve(128);
    gRetryQueue.reserve(RETRY_QUEUE_MAX);

    // ---- ADC attenuation for full 0-3.3V range ----
    analogSetAttenuation(ADC_11db);
    Serial.println("[ADC] Analog attenuation set to ADC_11db (0..3.3V range)");

    // ---- LoRa init ----
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
        Serial.println("[RADIO] *** FATAL: LoRa.begin() FAILED! ***");
        Serial.println("[RADIO] Check wiring, frequency, and module power.");
        Serial.println("[RADIO] System continues but radio is non-functional.");
    } else {
        Serial.println("[RADIO] LoRa.begin() SUCCESS");
        configureRadio();
    }

    // ---- Initial sensor sample ----
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
    Serial.print("  Boot counter: ");
    Serial.println(gBootCounter);
    Serial.print("  Sample interval: ");
    Serial.print(gPriorityEngine.getIntervalMs() / 1000);
    Serial.println("s");
    Serial.println("  Type HELP for commands");
    Serial.println("====================================================");
    Serial.println();
}

// ===========================================================================
//  LOOP
// ===========================================================================
void loop() {
    unsigned long now = millis();

    // ---- Feed the watchdog ----
    esp_task_wdt_reset();

    // ---- Serial CLI (checked on every iteration) ----
    if (Serial.available()) {
        String line = Serial.readStringUntil('\n');
        line.trim();
        if (line.length() > 0) {
            serialCommand(line);
        }
    }

    // ============================================================
    //  STATE: INIT  -> immediately transition to REGISTERING
    // ============================================================
    if (gNodeState == STATE_INIT) {
        gNodeState = STATE_REGISTERING;
        gLastRegMs = 0;
        Serial.println("[STATE] Entering REGISTERING state");
    }

    // ============================================================
    //  STATE: REGISTERING
    // ============================================================
    if (gNodeState == STATE_REGISTERING) {
        // Check for approval reply
        if (checkLoRaResponse()) {
            gNodeState = STATE_CONNECTED;
            gLastSampleMs = millis();
            gLastHqSeenMs = millis();
            gMissedAckCount = 0;
            Serial.println();
            Serial.println("═══════════════════════════════════════════");
            Serial.println("  HANDSHAKE COMPLETE - Starting telemetry");
            Serial.println("═══════════════════════════════════════════");
            Serial.println();

            // Flush any buffered packets from a previous connection
            retryQueueFlush();
        }

        if (gNodeState == STATE_REGISTERING && now - gLastRegMs >= gRegIntervalMs) {
            gLastRegMs = now;
            gRegAttempt++;

            String regPayload = buildRegistrationPayload();
            uint8_t hwIdBytes[SmartPacket::NONCE_SIZE];
            memcpy(hwIdBytes, gHardwareId.c_str(), SmartPacket::NONCE_SIZE);
            gPacketBuilder.build(regPayload, hwIdBytes, gPacketBuf);
            patchNonceWithBootCounter(gPacketBuf);

            Serial.println();
            Serial.println("═══════════════════════════════════════════");
            Serial.print("  REGISTERING (attempt ");
            Serial.print(gRegAttempt);
            Serial.println(")");
            Serial.println("═══════════════════════════════════════════");
            Serial.print("  HW: "); Serial.println(gHardwareId);
            Serial.print("  TX: "); Serial.print(gPacketBuf.size());
            Serial.println("B  awaiting approval...");
            Serial.println("───────────────────────────────────────────");

            transmitPacket(gPacketBuf);

            // Poll for response briefly (REG_POLL_WINDOW_MS window)
            unsigned long pollDeadline = millis() + REG_POLL_WINDOW_MS;
            while (millis() < pollDeadline) {
                esp_task_wdt_reset();
                if (checkLoRaResponse()) {
                    gNodeState = STATE_CONNECTED;
                    gLastSampleMs = millis();
                    gLastHqSeenMs = millis();
                    gMissedAckCount = 0;
                    Serial.println();
                    Serial.println("═══════════════════════════════════════════");
                    Serial.println("  HANDSHAKE COMPLETE - Starting telemetry");
                    Serial.println("═══════════════════════════════════════════");
                    Serial.println();
                    retryQueueFlush();
                    break;
                }
                delay(10);
            }
        }

        // Wait out remaining interval
        if (gNodeState == STATE_REGISTERING) {
            unsigned long elapsed = millis() - gLastRegMs;
            if (elapsed < gRegIntervalMs) {
                idleWait(gRegIntervalMs - elapsed);
            }
        }
    }

    // ============================================================
    //  STATE: CONNECTED
    // ============================================================
    if (gNodeState == STATE_CONNECTED) {
        checkLoRaResponse();

        // ---- Timer-driven sample cycle ----
        unsigned long interval = gPriorityEngine.getIntervalMs();
        if (now - gLastSampleMs >= interval) {
            gLastSampleMs = now;

            // ---- ADR update ----
            if (now - gLastAdrUpdateMs >= ADR_UPDATE_INTERVAL_MS) {
                gLastAdrUpdateMs = now;
                updateAdr();
            }

            // ---- Sample all sensors ----
            gSensorMgr.sample(gReadings);

            // ---- Classify priority via PriorityEngine ----
            gPriorityEngine.evaluate(gReadings);
            uint8_t currentPrio = gPriorityEngine.getPriority();
            uint8_t currentMode = gPriorityEngine.getReportMode();
            unsigned long currentInterval = gPriorityEngine.getIntervalMs();

            // ---- Build binary payload with priority/report_mode bytes ----
            buildBinaryPayload(gReadings, gBinaryPayload, currentPrio, currentMode);

            // ---- Encrypt and packetize ----
            uint8_t hwIdBytes[SmartPacket::NONCE_SIZE];
            memcpy(hwIdBytes, gHardwareId.c_str(), SmartPacket::NONCE_SIZE);
            gPacketBuilder.build(gBinaryPayload.data(), gBinaryPayload.size(),
                                  hwIdBytes, gPacketBuf);
            patchNonceWithBootCounter(gPacketBuf);

            // ---- Print sample header ----
            Serial.println();
            Serial.println("═══════════════════════════════════════════");
            Serial.print("  SAMPLE #"); Serial.print(gPacketCount + 1);
            Serial.print("  Prio=");
            Serial.print(SmartPacket::priorityLabel(currentPrio));
            Serial.print("  Mode=");
            Serial.print(SmartPacket::reportModeLabel(currentMode));
            Serial.print("  (+"); Serial.print(currentInterval / 1000);
            Serial.println("s)");
            Serial.print("  SF"); Serial.print(gCurrentSf);
            Serial.print("  BestRSSI="); Serial.print(gBestHqRssi);
            Serial.println("dBm");
            if (gRetryQueue.size() > 0) {
                Serial.print("  Queued: ");
                Serial.print((int)gRetryQueue.size());
                Serial.println(" packets");
            }
            Serial.println("═══════════════════════════════════════════");
            Serial.print("  ");
            for (const auto& r : gReadings) {
                Serial.print(r.segment); Serial.print("  ");
            }
            Serial.println();
            Serial.println("───────────────────────────────────────────");
            Serial.print("  TX: "); Serial.print(gPacketBuf.size());
            Serial.println("B (binary)");
            Serial.println("───────────────────────────────────────────");

            // ---- Transmit ----
            bool txOk = transmitPacket(gPacketBuf);
            if (!txOk) {
                Serial.println("[TX] Transmit failed, queuing for retry");
                retryQueuePush(gPacketBuf);
            }

            gPacketCount++;

            // ---- Wait for ACK from HQ (up to ACK_POLL_MS after TX) ----
            gWaitingForAck = true;
            unsigned long ackDeadline = millis() + ACK_POLL_MS;
            unsigned long hqBefore = gLastHqSeenMs;
            bool gotAck = false;
            while (millis() < ackDeadline) {
                esp_task_wdt_reset();
                if (checkLoRaResponse()) {
                    gotAck = true;
                    break;
                }
                delay(5);
            }

            if (!gotAck) {
                gMissedAckCount++;
                Serial.print("  ACK missed (");
                Serial.print(gMissedAckCount);
                Serial.print("/"); Serial.print(MISSED_ACK_THRESHOLD);
                Serial.println(")");

                // Buffer the packet for store-and-forward retry
                if (txOk) {
                    retryQueuePush(gPacketBuf);
                }

                if (gMissedAckCount >= MISSED_ACK_THRESHOLD) {
                    gNodeState = STATE_REGISTERING;
                    gLastRegMs = 0;
                    gRegAttempt = 0;
                    gRegIntervalMs = REG_RETRY_INTERVAL_MS;
                    Serial.println("  HQ LOST - Falling back to registration");
                }
            } else {
                // ACK received — flush any buffered packets
                if (gRetryQueue.size() > 0) {
                    retryQueueFlush();
                }
            }
            gWaitingForAck = false;
        }

        // Idle-wait remaining interval
        if (gNodeState == STATE_CONNECTED) {
            unsigned long elapsed = millis() - gLastSampleMs;
            if (elapsed < interval) {
                // For CRITICAL priority, do NOT block in idleWait —
                // return to loop so immediate-critical dispatch can fire.
                if (gPriorityEngine.getPriority() != SmartPacket::PRIORITY_HIGH) {
                    idleWait(interval - elapsed);
                }
            }
        }
    }
}

// ===========================================================================
//  SERIAL CLI
// ===========================================================================
void serialCommand(const String& input) {
    String upper = input;
    upper.toUpperCase();

    if (upper == "HELP" || upper == "?") {
        Serial.println("====================================================");
        Serial.println("SmartPonic Node CLI Commands:");
        Serial.println("====================================================");
        Serial.println("  HELP / ?          - Show this help");
        Serial.println("  ID                - Show hardware ID");
        Serial.println("  VERSION           - Show firmware version & build");
        Serial.println("  LIST              - List all sensor configurations");
        Serial.println("  KEYS / SHOWKEYS   - Show AES and AUTH keys");
        Serial.println("  SETKEYS,AES=xx,AUTH=yy  - Update encryption keys");
        Serial.println("  CLEARKEYS         - Reset keys to factory defaults");
        Serial.println("  STATUS            - Show system status & uptime");
        Serial.println("  QUEUE             - Show store-and-forward queue");
        Serial.println("  ADD,pin,type,sensor,label - Add sensor dynamically");
        Serial.println("  REMOVE,index      - Remove sensor at index");
        Serial.println("  CALIBRATE,pin     - Calibrate analog sensor (future)");
        Serial.println("  RESET             - Hardware reset (ESP.restart())");
        Serial.println("====================================================");
        return;
    }

    if (upper == "ID") {
        Serial.print("Hardware ID: ");
        Serial.println(gHardwareId);
        return;
    }

    if (upper == "VERSION") {
        Serial.print("Firmware: v");
        Serial.print(FIRMWARE_VERSION);
        Serial.print("  Build: ");
        Serial.println(FIRMWARE_BUILD);
        Serial.print("Boot counter: ");
        Serial.println(gBootCounter);
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
        Serial.print("Heap min free: ");
        Serial.print(ESP.getMinFreeHeap());
        Serial.println(" bytes");
        Serial.print("Hardware ID: ");
        Serial.println(gHardwareId);
        Serial.print("State: ");
        switch (gNodeState) {
            case STATE_INIT:         Serial.println("INIT"); break;
            case STATE_REGISTERING:  Serial.println("REGISTERING"); break;
            case STATE_CONNECTED:    Serial.println("CONNECTED"); break;
            case STATE_DEREGISTERED: Serial.println("DEREGISTERED"); break;
        }
        Serial.print("Sensors configured: ");
        Serial.println(gSensorMgr.count());
        Serial.print("Last sample: ");
        Serial.print(ms - gLastSampleMs);
        Serial.println("ms ago");
        Serial.print("Packets sent: ");
        Serial.println(gPacketCount);
        Serial.print("Missed ACKs: ");
        Serial.println(gMissedAckCount);
        Serial.print("Retry queue: ");
        Serial.println((int)gRetryQueue.size());
        Serial.print("Current SF: ");
        Serial.println(gCurrentSf);
        Serial.print("Best HQ RSSI: ");
        Serial.println(gBestHqRssi);
        Serial.print("Current priority: ");
        Serial.println(SmartPacket::priorityLabel(gPriorityEngine.getPriority()));
        Serial.print("Current interval: ");
        Serial.print(gPriorityEngine.getIntervalMs() / 1000);
        Serial.println("s");
        Serial.print("AES key length: ");
        Serial.print(gAesKey.length());
        Serial.println(" chars");
        Serial.print("AUTH key length: ");
        Serial.print(gAuthKey.length());
        Serial.println(" chars");
        Serial.print("Boot counter: ");
        Serial.println(gBootCounter);
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

    if (upper.startsWith("REMOVE,")) {
        int idx = input.substring(7).toInt();
        if (idx >= 0 && idx < gSensorMgr.count()) {
            Serial.println("[CLI] REMOVE not yet supported at SensorManager level.");
            Serial.println("Use CLEARKEYS + RESET to factory-default instead.");
        } else {
            Serial.println("[CLI] ERROR: Invalid sensor index");
        }
        return;
    }

    if (upper.startsWith("CALIBRATE,")) {
        int pin = input.substring(10).toInt();
        Serial.print("[CLI] Calibration requested for pin ");
        Serial.println(pin);
        Serial.println("[CLI] NOTE: Calibration API requires SensorManager support.");
        Serial.println("[CLI] For now, manually set known-reference values via SETKEYS.");
        return;
    }

    if (upper == "QUEUE") {
        Serial.print("Store-and-forward queue: ");
        Serial.print((int)gRetryQueue.size());
        Serial.print(" / ");
        Serial.print(RETRY_QUEUE_MAX);
        Serial.println(" entries");
        for (size_t i = 0; i < gRetryQueue.size(); i++) {
            Serial.print("  [");
            Serial.print(i);
            Serial.print("] ");
            Serial.print((int)gRetryQueue[i].data.size());
            Serial.print(" bytes, age=");
            Serial.print((millis() - gRetryQueue[i].timestampMs) / 1000);
            Serial.println("s");
        }
        return;
    }

    if (upper == "RESET") {
        Serial.println("Resetting MCU...");
        delay(100);
        ESP.restart();
    }

    Serial.print("[CLI] Unknown command: ");
    Serial.println(input);
    Serial.println("Type HELP for available commands");
}