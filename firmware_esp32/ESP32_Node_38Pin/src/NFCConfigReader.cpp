#include "NFCConfigReader.h"
#include <mbedtls/aes.h>
#include <Preferences.h>
#include <algorithm>

// Preferences namespace for NFC state
const char* nfcNamespace = "nfc_cfg";
const char* nfcLastConfigPrefKey = "last_cfg";
const char* nfcLastReadPrefKey = "last_read";

// AES key for NFC payload decryption (same as LoRa payload)
// Loaded from Preferences "secrets" namespace at runtime
static String getNfcAesKey() {
    Preferences prefs;
    prefs.begin("secrets", true);
    String key = prefs.getString("aes_key", "SmartPonic123456");
    prefs.end();
    return key.length() == 16 ? key : "SmartPonic123456";
}

NFCConfigReader::NFCConfigReader()
    : _nfc(NFC_IRQ, NFC_RESET, &Wire)
    , _initialized(false)
{
}

bool NFCConfigReader::begin() {
    if (_initialized) {
        return true;
    }

    Serial.println("[NFC] Initializing PN532...");

    Wire.begin(NFC_I2C_SDA, NFC_I2C_SCL);

    // Initialize PN532 over I2C
    _nfc.begin();

    // Check PN532 version
    uint32_t versiondata = _nfc.getFirmwareVersion();
    if (versiondata == 0) {
        _lastError = "PN532 not found - check wiring";
        Serial.println("[NFC] ERROR: " + _lastError);
        return false;
    }

    Serial.print("[NFC] PN532 found: v0.");
    Serial.print((versiondata >> 24) & 0xFF, HEX);
    Serial.print(".");
    Serial.print((versiondata >> 16) & 0xFF, HEX);
    Serial.println();

    // Set max retries
    _nfc.setPassiveActivationRetries(0xFF);

    // Configure SAM (Secure Access Module)
    if (!_nfc.SAMConfig()) {
        _lastError = "PN532 SAMConfig failed";
        Serial.println("[NFC] ERROR: " + _lastError);
        return false;
    }

    // Initialize LED pin
    pinMode(NFC_LED_PIN, OUTPUT);
    digitalWrite(NFC_LED_PIN, LOW);

    _initialized = true;
    Serial.println("[NFC] PN532 initialized successfully");
    return true;
}

bool NFCConfigReader::isCardPresent() {
    if (!_initialized) {
        return false;
    }

    uint8_t success;
    uint8_t uid[32];
    uint8_t uidLength;

    success = _nfc.readPassiveTargetID(PN532_MIFARE_ISO14443A, uid, &uidLength);

    if (success) {
        Serial.print("[NFC] Card detected: UID length ");
        Serial.println(uidLength);
        return true;
    }

    return false;
}

bool NFCConfigReader::waitForCard(uint32_t timeoutMs) {
    if (!_initialized) {
        _lastError = "PN532 not initialized";
        return false;
    }

    Serial.println("[NFC] Waiting for NFC card...");
    setLed(true);  // LED on while waiting

    unsigned long startMs = millis();
    bool cardDetected = false;

    while (millis() - startMs < timeoutMs) {
        if (isCardPresent()) {
            cardDetected = true;
            break;
        }
        delay(100);
    }

    setLed(false);

    if (!cardDetected) {
        _lastError = "No card detected within timeout";
        Serial.println("[NFC] TIMEOUT: " + _lastError);
        return false;
    }

    // Card detected, now read config
    String configJson, authKey;
    return readConfig(configJson, authKey);
}

bool NFCConfigReader::readConfig(String& configJson, String& authKey) {
    if (!_initialized) {
        _lastError = "PN532 not initialized";
        return false;
    }

    Serial.println("[NFC] Reading NFC tag...");
    flashLed(2, 100);  // Double flash

    if (readDirectHceConfig(configJson)) {
        authKey = "AQUA77";
        flashLed(5, 50);
        return true;
    }

    uint8_t data[NFC_MAX_PAYLOAD_SIZE];
    uint16_t dataLen = 0;

    uint8_t uid[32];
    uint8_t uidLength;

    if (!_nfc.readPassiveTargetID(PN532_MIFARE_ISO14443A, uid, &uidLength)) {
        _lastError = "Failed to read card UID";
        return false;
    }

    Serial.print("[NFC] Card UID: ");
    for (uint8_t i = 0; i < uidLength; i++) {
        Serial.print(uid[i] < 0x10 ? "0" : "");
        Serial.print(uid[i], HEX);
        Serial.print(" ");
    }
    Serial.println();

    // NTAG215 has 135 pages (0-135), 4 bytes per page
    // Pages 0-3 are manufacturer data
    // User data: pages 4-135 = 132 pages = 528 bytes total
    uint8_t page = 4;  // Start at page 4
    uint8_t bytesPerRead = 4;
    uint16_t offset = 0;

    while (offset < NFC_MAX_PAYLOAD_SIZE - bytesPerRead) {
        uint8_t pageData[4];

        if (!_nfc.ntag2xx_ReadPage(page, pageData)) {
            if (offset > 0) {
                dataLen = offset;
                break;
            }
            _lastError = "Failed to read page " + String(page);
            Serial.println("[NFC] ERROR: " + _lastError);
            return false;
        }

        memcpy(data + offset, pageData, bytesPerRead);
        offset += bytesPerRead;
        page++;

        if (page > 135) {
            dataLen = offset;
            break;
        }
    }

    if (dataLen == 0 && offset > 0) {
        dataLen = offset;
    }

    if (dataLen < 16) {
        _lastError = "Payload too small";
        Serial.println("[NFC] ERROR: " + _lastError);
        return false;
    }

    Serial.print("[NFC] Read ");
    Serial.print(dataLen);
    Serial.println(" bytes from NFC tag");

    // Parse NDEF record to extract encrypted payload
    std::vector<uint8_t> encryptedPayload;
    if (!parseNdefRecord(data, dataLen, encryptedPayload)) {
        _lastError = "Failed to parse NDEF record";
        Serial.println("[NFC] ERROR: " + _lastError);
        return false;
    }

    if (encryptedPayload.empty()) {
        // Try raw payload (no NDEF wrapper)
        encryptedPayload.assign(data, data + dataLen);
    }

    // Decrypt payload
    String aesKey = getNfcAesKey();
    configJson = decryptPayload(encryptedPayload, aesKey);

    if (configJson.isEmpty()) {
        _lastError = "Decryption failed";
        Serial.println("[NFC] ERROR: " + _lastError);
        return false;
    }

    Serial.println("[NFC] Config decrypted successfully");
    Serial.println("[NFC] Config JSON: " + configJson);

    // Auth key is embedded in the JSON payload under "keys.auth"
    // or use default "AQUA77"
    authKey = "AQUA77";  // Default, will be overridden by JSON parsing in main code

    flashLed(5, 50);  // Success: 5 quick flashes
    return true;
}

bool NFCConfigReader::writeConfig(const String& configJson) {
    if (!_initialized) {
        _lastError = "PN532 not initialized";
        return false;
    }

    Serial.println("[NFC] Writing config to NFC tag...");

    // Wait for card
    if (!waitForCard(10000)) {
        return false;
    }

    // For writing, we need to encrypt the payload first
    // This is a placeholder - full implementation would:
    // 1. Encrypt configJson with AES key
    // 2. Wrap in NDEF record
    // 3. Write to NTAG215 pages 4-39 using ntag2xx_WritePage

    _lastError = "Write not fully implemented yet";
    Serial.println("[NFC] WARNING: " + _lastError);
    return false;
}

bool NFCConfigReader::readDirectHceConfig(String& configJson) {
    Serial.println("[NFC] Trying direct Android HCE/APDU config...");

    if (!_nfc.inListPassiveTarget()) {
        _lastError = "No ISO14443 target for direct HCE";
        return false;
    }

    const uint8_t selectSmartPonicAid[] = {
        0x00, 0xA4, 0x04, 0x00, 0x0B,
        0xF0, 0x53, 0x4D, 0x41, 0x52, 0x54, 0x50, 0x4F, 0x4E, 0x49, 0x43,
        0x00
    };
    uint8_t response[64];
    uint8_t responseLen = sizeof(response);

    if (!exchangeApdu(selectSmartPonicAid, sizeof(selectSmartPonicAid), response, responseLen) ||
        !isSuccessStatus(response, responseLen)) {
        _lastError = "SmartPonic HCE AID not selected";
        return false;
    }

    const uint8_t getLengthApdu[] = {0x00, 0xCA, 0x00, 0x00, 0x04};
    responseLen = sizeof(response);
    if (!exchangeApdu(getLengthApdu, sizeof(getLengthApdu), response, responseLen) ||
        !isSuccessStatus(response, responseLen) || responseLen < 6) {
        _lastError = "Failed to read HCE payload length";
        return false;
    }

    uint32_t payloadLen = ((uint32_t)response[0] << 24) |
                          ((uint32_t)response[1] << 16) |
                          ((uint32_t)response[2] << 8) |
                          (uint32_t)response[3];
    if (payloadLen < 16 || payloadLen > NFC_MAX_HCE_PAYLOAD_SIZE) {
        _lastError = "Invalid HCE payload length " + String(payloadLen);
        Serial.println("[NFC] ERROR: " + _lastError);
        return false;
    }

    std::vector<uint8_t> encryptedPayload;
    encryptedPayload.reserve(payloadLen);

    uint32_t offset = 0;
    while (offset < payloadLen) {
        uint8_t chunkLen = (uint8_t)std::min<uint32_t>(48, payloadLen - offset);
        uint8_t readApdu[] = {
            0x00,
            0xB0,
            (uint8_t)((offset >> 8) & 0xFF),
            (uint8_t)(offset & 0xFF),
            chunkLen
        };

        responseLen = sizeof(response);
        if (!exchangeApdu(readApdu, sizeof(readApdu), response, responseLen) ||
            !isSuccessStatus(response, responseLen) || responseLen < 2) {
            _lastError = "Failed to read HCE payload chunk";
            Serial.println("[NFC] ERROR: " + _lastError);
            return false;
        }

        uint8_t dataLen = responseLen - 2;
        encryptedPayload.insert(encryptedPayload.end(), response, response + dataLen);
        offset += dataLen;
    }

    if (encryptedPayload.size() != payloadLen) {
        _lastError = "Incomplete HCE payload";
        return false;
    }

    String aesKey = getNfcAesKey();
    configJson = decryptPayload(encryptedPayload, aesKey);
    if (configJson.isEmpty()) {
        _lastError = "HCE payload decryption failed";
        Serial.println("[NFC] ERROR: " + _lastError);
        return false;
    }

    Serial.println("[NFC] Direct HCE config decrypted successfully");
    Serial.println("[NFC] Config JSON: " + configJson);
    return true;
}

bool NFCConfigReader::exchangeApdu(const uint8_t* command, uint8_t commandLen,
                                   uint8_t* response, uint8_t& responseLen) {
    uint8_t responseCapacity = responseLen;
    responseLen = responseCapacity;
    return _nfc.inDataExchange((uint8_t*)command, commandLen, response, &responseLen);
}

bool NFCConfigReader::isSuccessStatus(const uint8_t* response, uint8_t responseLen) {
    return responseLen >= 2 &&
           response[responseLen - 2] == 0x90 &&
           response[responseLen - 1] == 0x00;
}

String NFCConfigReader::decryptPayload(const std::vector<uint8_t>& encrypted, const String& aesKey) {
    // AES-128-CTR decryption
    // Payload format: [IV (16 bytes)] + [Ciphertext]

    if (encrypted.size() < 16) {
        Serial.println("[NFC] Payload too short for AES decryption");
        return "";
    }

    // Extract IV from first 16 bytes
    uint8_t iv[16];
    memcpy(iv, encrypted.data(), 16);

    // Ciphertext starts after IV
    size_t ciphertextLen = encrypted.size() - 16;
    uint8_t* ciphertext = (uint8_t*)encrypted.data() + 16;

    // Allocate output buffer
    uint8_t* plaintext = new uint8_t[ciphertextLen + 1];
    memset(plaintext, 0, ciphertextLen + 1);

    // Initialize AES context
    mbedtls_aes_context aes;
    mbedtls_aes_init(&aes);

    // Set key (AES-128)
    String keyStr = aesKey;
    unsigned char key[16];
    memcpy(key, keyStr.c_str(), 16);

    if (mbedtls_aes_setkey_enc(&aes, key, 128) != 0) {
        mbedtls_aes_free(&aes);
        delete[] plaintext;
        Serial.println("[NFC] AES key setup failed");
        return "";
    }

    // CTR mode decryption (same as encryption for CTR)
    uint8_t counter[16];
    memcpy(counter, iv, 16);

    size_t nc_off = 0;
    uint8_t stream_block[16];

    if (mbedtls_aes_crypt_ctr(&aes, ciphertextLen, &nc_off, counter, stream_block, ciphertext, plaintext) != 0) {
        mbedtls_aes_free(&aes);
        delete[] plaintext;
        Serial.println("[NFC] AES CTR decryption failed");
        return "";
    }

    mbedtls_aes_free(&aes);

    String result = String((char*)plaintext);
    delete[] plaintext;

    return result;
}

bool NFCConfigReader::parseNdefRecord(const uint8_t* data, uint16_t len, std::vector<uint8_t>& payload) {
    // Simple NDEF parser for SmartPonic format
    // NDEF Record structure:
    // [Header (1 byte)] [Type Length (1 byte)] [Payload Length (4 bytes)] [Type] [Payload]

    if (len < 6) {
        return false;
    }

    uint8_t header = data[0];
    uint8_t typeLen = data[1];

    // Payload length is 4 bytes (big endian for NDEF)
    uint32_t payloadLen = ((uint32_t)data[2] << 24) | ((uint32_t)data[3] << 16) |
                          ((uint32_t)data[4] << 8) | data[5];

    if (payloadLen == 0 || payloadLen > len - 6 - typeLen) {
        return false;
    }

    // Skip type field
    uint16_t payloadOffset = 2 + 4 + typeLen;

    // Extract payload
    payload.assign(data + payloadOffset, data + payloadOffset + payloadLen);

    Serial.print("[NFC] NDEF payload extracted: ");
    Serial.print(payload.size());
    Serial.println(" bytes");

    return true;
}

void NFCConfigReader::setLed(bool on) {
    digitalWrite(NFC_LED_PIN, on ? HIGH : LOW);
}

void NFCConfigReader::flashLed(int count, int durationMs) {
    for (int i = 0; i < count; i++) {
        setLed(true);
        delay(durationMs);
        setLed(false);
        if (i < count - 1) {
            delay(durationMs);
        }
    }
}
