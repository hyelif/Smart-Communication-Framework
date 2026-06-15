#include "NFCConfigReader.h"
#include <mbedtls/aes.h>
#include <ArduinoJson.h>
#include <Preferences.h>

NFCConfigReader::NFCConfigReader()
    : _nfc(0xFF, 0xFF), _initialized(false) {
}

bool NFCConfigReader::begin() {
    Serial.println("[NFC] Initializing PN532 over I2C...");

    // Wait for PN532 power to stabilize
    delay(NFC_POWER_STABILIZE_MS);

    // Internal pull-up on SCL to help I2C state-switch (SDA has external 3.3kΩ)
    pinMode(NFC_I2C_SCL, INPUT_PULLUP);
    delay(10);

    Wire.begin(NFC_I2C_SDA, NFC_I2C_SCL);
    delay(200);

    for (int attempt = 0; attempt < 2; attempt++) {
        if (attempt > 0) {
            Serial.print("[NFC] Retry attempt ");
            Serial.println(attempt + 1);
            delay(500);
        }

        _nfc.begin();

        uint32_t versiondata = _nfc.getFirmwareVersion();
        if (versiondata) {
            Serial.print("[NFC] Found PN532 (FW v");
            Serial.print((versiondata >> 16) & 0xFF, HEX);
            Serial.print(".");
            Serial.print((versiondata >> 8) & 0xFF, HEX);
            Serial.println(")");

            _nfc.setPassiveActivationRetries(0xFF);
            _nfc.SAMConfig();

            _initialized = true;
            Serial.println("[NFC] PN532 ready");
            return true;
        }
    }

    _lastError = "PN532 not detected - check wiring (SDA=21, SCL=22)";
    Serial.print("[NFC] ERROR: ");
    Serial.println(_lastError);
    _initialized = false;
    return false;
}

void NFCConfigReader::reinitAfterSleep() {
    // Re-enable internal pull-up on SCL (lost during light sleep)
    pinMode(NFC_I2C_SCL, INPUT_PULLUP);
    delay(10);
    // I2C bus is already re-init'd in main.cpp; just re-apply SAMConfig
    _nfc.SAMConfig();
    Serial.println("[NFC] Re-init after sleep");
}

bool NFCConfigReader::quickCardCheck() {
    if (!_initialized) return false;

    // Use minimal retry for quick polling — avoids 3s delays on each empty check
    uint8_t uid[7] = {0};
    uint8_t uidLen = 0;

    if (_nfc.readPassiveTargetID(PN532_MIFARE_ISO14443A, uid, &uidLen, 10)) {
        Serial.print("[NFC] Quick check: target UID ");
        for (uint8_t i = 0; i < uidLen; i++) {
            Serial.print(uid[i], HEX);
        }
        Serial.println();
        return true;
    }

    return false;
}

bool NFCConfigReader::isCardPresent() {
    return quickCardCheck();
}

bool NFCConfigReader::waitForCard(uint32_t timeoutMs) {
    unsigned long start = millis();
    while (millis() - start < timeoutMs) {
        if (quickCardCheck()) {
            return true;
        }
        delay(50);  // Shorter delay between checks
    }
    return false;
}

bool NFCConfigReader::readConfig(String& configJson, String& authKey) {
    if (!_initialized) {
        _lastError = "PN532 not initialized";
        return false;
    }

    Serial.println("[NFC] Reading config...");

    // Try HCE (direct phone tap) first
    String encryptedStr;
    if (readHceFromPhone(encryptedStr)) {
        Serial.println("[NFC] HCE read successful");
    } else {
        Serial.println("[NFC] HCE failed, trying physical tag...");
        // Fall back to physical NTAG215
        if (!readPhysicalTag(encryptedStr)) {
            _lastError = "Both HCE and physical tag read failed";
            Serial.print("[NFC] ERROR: ");
            Serial.println(_lastError);
            return false;
        }
        Serial.println("[NFC] Physical tag read successful");
    }

    // Convert hex string to byte buffer
    std::vector<uint8_t> encrypted;
    for (size_t i = 0; i < encryptedStr.length(); i += 2) {
        char hi = encryptedStr[i];
        char lo = encryptedStr[i + 1];
        uint8_t byte = 0;
        if (hi >= '0' && hi <= '9') byte |= (hi - '0') << 4;
        else if (hi >= 'A' && hi <= 'F') byte |= (hi - 'A' + 10) << 4;
        else if (hi >= 'a' && hi <= 'f') byte |= (hi - 'a' + 10) << 4;
        if (lo >= '0' && lo <= '9') byte |= (lo - '0');
        else if (lo >= 'A' && lo <= 'F') byte |= (lo - 'A' + 10);
        else if (lo >= 'a' && lo <= 'f') byte |= (lo - 'a' + 10);
        encrypted.push_back(byte);
    }

    if (encrypted.size() < 17) {  // At least 16-byte IV + 1 byte ciphertext
        _lastError = "Encrypted payload too short";
        Serial.print("[NFC] ERROR: ");
        Serial.println(_lastError);
        return false;
    }

    // Get AES key from Preferences
    Preferences prefs;
    prefs.begin("secrets", true);
    String aesKey = prefs.getString("aes_key", "SmartPonic123456");
    prefs.end();

    // Decrypt
    String plaintext = decryptPayload(encrypted, aesKey);
    if (plaintext.length() == 0) {
        _lastError = "Decryption failed";
        Serial.print("[NFC] ERROR: ");
        Serial.println(_lastError);
        return false;
    }

    Serial.print("[NFC] Decrypted config: ");
    Serial.println(plaintext);

    // Parse JSON
    JsonDocument doc;
    DeserializationError error = deserializeJson(doc, plaintext);
    if (error) {
        _lastError = "JSON parse failed: ";
        _lastError += error.c_str();
        Serial.print("[NFC] ERROR: ");
        Serial.println(_lastError);
        return false;
    }

    // Extract config JSON
    if (!doc["config"].isNull()) {
        serializeJson(doc["config"], configJson);
    } else {
        configJson = plaintext;
    }

    // Extract auth key if present
    JsonObject keysObj = doc["keys"];
    if (!keysObj.isNull() && keysObj["auth"].is<const char*>()) {
        authKey = keysObj["auth"].as<String>();
    }

    Serial.println("[NFC] Config parsed successfully");
    return true;
}

bool NFCConfigReader::writeConfig(const String& configJson) {
    // Write config to Preferences
    Preferences prefs;
    prefs.begin("config", false);
    prefs.putString("nfc_config", configJson);
    prefs.end();

    Serial.println("[NFC] Config written to Preferences");
    return true;
}

// ================= HCE (Direct Phone Tap) =================

bool NFCConfigReader::readHceFromPhone(String& configJson) {
    Serial.println("[NFC] Waiting for HCE device...");

    uint8_t uid[7] = {0};
    uint8_t uidLen = 0;

    // Wait for ISO14443A target
    if (!_nfc.readPassiveTargetID(PN532_MIFARE_ISO14443A, uid, &uidLen, 2000)) {
        _lastError = "No ISO14443A target detected";
        return false;
    }

    Serial.print("[NFC] HCE target detected, UID: ");
    for (uint8_t i = 0; i < uidLen; i++) {
        Serial.print(uid[i], HEX);
    }
    Serial.println();

    delay(100);

    // Step 1: SELECT AID
    // Command: 00 A4 04 00 0B [AID: 11 bytes] 00
    uint8_t selectAid[] = {
        0x00, 0xA4, 0x04, 0x00, 0x0B,
        0xF0, 0x53, 0x4D, 0x41, 0x52, 0x54, 0x50, 0x4F, 0x4E, 0x49, 0x43,
        0x00
    };
    uint8_t selectResp[32] = {0};
    uint8_t selectRespLen = sizeof(selectResp);

    if (!_nfc.inDataExchange(selectAid, sizeof(selectAid), selectResp, &selectRespLen)) {
        _lastError = "SELECT AID exchange failed";
        return false;
    }

    // Check response: should end with 0x90 0x00
    if (selectRespLen < 2 || selectResp[selectRespLen - 2] != 0x90 || selectResp[selectRespLen - 1] != 0x00) {
        _lastError = "SELECT AID rejected by phone";
        Serial.print("[NFC] SELECT AID response: ");
        for (uint16_t i = 0; i < selectRespLen; i++) {
            Serial.print(selectResp[i], HEX);
            Serial.print(" ");
        }
        Serial.println();
        return false;
    }
    Serial.println("[NFC] SELECT AID OK");

    delay(50);

    // Step 2: GET LENGTH
    // Command: 00 CA 00 00 04
    uint8_t getLenCmd[] = {0x00, 0xCA, 0x00, 0x00, 0x04};
    uint8_t getLenResp[32] = {0};
    uint8_t getLenRespLen = sizeof(getLenResp);

    if (!_nfc.inDataExchange(getLenCmd, sizeof(getLenCmd), getLenResp, &getLenRespLen)) {
        _lastError = "GET LENGTH exchange failed";
        return false;
    }

    if (getLenRespLen < 6 || getLenResp[getLenRespLen - 2] != 0x90 || getLenResp[getLenRespLen - 1] != 0x00) {
        _lastError = "GET LENGTH failed";
        return false;
    }

    // First 4 bytes are big-endian payload length
    uint32_t payloadLen = ((uint32_t)getLenResp[0] << 24) |
                          ((uint32_t)getLenResp[1] << 16) |
                          ((uint32_t)getLenResp[2] << 8) |
                          (uint32_t)getLenResp[3];

    if (payloadLen == 0 || payloadLen > NFC_MAX_PAYLOAD_SIZE) {
        _lastError = "Invalid payload length: ";
        _lastError += String(payloadLen);
        return false;
    }

    Serial.print("[NFC] Payload length: ");
    Serial.println(payloadLen);

    delay(50);

    // Step 3: READ BINARY (chunked)
    std::vector<uint8_t> fullPayload;
    fullPayload.reserve(payloadLen);

    uint16_t offset = 0;
    while (offset < payloadLen) {
        uint8_t chunkSize = (payloadLen - offset < MAX_CHUNK_SIZE) ? (payloadLen - offset) : MAX_CHUNK_SIZE;

        uint8_t readCmd[] = {
            0x00, 0xB0,
            (uint8_t)((offset >> 8) & 0xFF),  // offset hi
            (uint8_t)(offset & 0xFF),          // offset lo
            chunkSize
        };
        uint8_t readResp[64] = {0};
        uint8_t readRespLen = sizeof(readResp);

        if (!_nfc.inDataExchange(readCmd, sizeof(readCmd), readResp, &readRespLen)) {
            _lastError = "READ BINARY exchange failed at offset ";
            _lastError += String(offset);
            return false;
        }

        if (readRespLen < 2 || readResp[readRespLen - 2] != 0x90 || readResp[readRespLen - 1] != 0x00) {
            _lastError = "READ BINARY failed at offset ";
            _lastError += String(offset);
            return false;
        }

        // Copy data (exclude status bytes)
        uint16_t dataLen = readRespLen - 2;
        for (uint16_t i = 0; i < dataLen; i++) {
            fullPayload.push_back(readResp[i]);
        }

        offset += dataLen;
        delay(20);
    }

    if (fullPayload.size() != payloadLen) {
        _lastError = "Payload size mismatch: got ";
        _lastError += String(fullPayload.size());
        _lastError += " expected ";
        _lastError += String(payloadLen);
        return false;
    }

    // Convert binary payload to hex string for return
    configJson = "";
    for (size_t i = 0; i < fullPayload.size(); i++) {
        char buf[3];
        snprintf(buf, sizeof(buf), "%02X", fullPayload[i]);
        configJson += buf;
    }

    Serial.print("[NFC] HCE payload received: ");
    Serial.print(fullPayload.size());
    Serial.println(" bytes");
    return true;
}

uint8_t NFCConfigReader::handleHceCommand(const uint8_t* apdu, uint8_t apduLen,
                                            uint8_t* response, uint8_t& responseLen) {
    // This is used when ESP32 is in card emulation mode (not reader mode).
    // For our use case, ESP32 is always the reader, so this is a stub.
    // Returns SW = 0x6D 0x00 (INS not supported)
    response[0] = 0x6D;
    response[1] = 0x00;
    responseLen = 2;
    return 2;
}

// ================= Physical NTAG215 Tag Read =================

bool NFCConfigReader::readPhysicalTag(String& configJson) {
    Serial.println("[NFC] Reading physical NTAG215 tag...");

    uint8_t uid[7] = {0};
    uint8_t uidLen = 0;

    // Wait for tag
    if (!_nfc.readPassiveTargetID(PN532_MIFARE_ISO14443A, uid, &uidLen, 2000)) {
        _lastError = "No tag detected";
        return false;
    }

    Serial.print("[NFC] Tag UID: ");
    for (uint8_t i = 0; i < uidLen; i++) {
        Serial.print(uid[i], HEX);
    }
    Serial.println();

    // Read NDEF message from tag
    // NTAG215 has 135 pages of 4 bytes each
    // NDEF data starts at page 4
    uint8_t pageData[4] = {0};
    std::vector<uint8_t> ndefData;
    ndefData.reserve(540);

    // Read pages 4 through 135 (max NTAG215 pages)
    for (uint8_t page = 4; page <= 135; page++) {
        if (!_nfc.ntag2xx_ReadPage(page, pageData)) {
            Serial.print("[NFC] Read page ");
            Serial.print(page);
            Serial.println(" failed");
            break;
        }

        for (int i = 0; i < 4; i++) {
            ndefData.push_back(pageData[i]);
        }

        // Check for NDEF terminator (0xFE in first byte of a page)
        // or end of NDEF data
        if (pageData[0] == 0xFE) break;

        delay(5);
    }

    if (ndefData.size() < 10) {
        _lastError = "Tag data too short";
        return false;
    }

    // Parse NDEF record
    // NDEF format: [TNF(1B)] [Type Len(1B)] [Payload Len(4B, BE)] [Type] [Payload]
    size_t pos = 0;

    // Skip NDEF header bytes
    // First byte: TNF + MB/ME/CF/SR/IL flags
    uint8_t tnf_byte = ndefData[pos++];

    // Check if MB (Message Begin) and ME (Message End) are set
    bool isMB = (tnf_byte & 0x80) != 0;
    bool isME = (tnf_byte & 0x40) != 0;

    (void)isMB;
    (void)isME;

    // Type length
    if (pos >= ndefData.size()) {
        _lastError = "NDEF header truncated (type len)";
        return false;
    }
    uint8_t typeLen = ndefData[pos++];

    // Payload length (3 bytes for long NDEF, or 1 byte for short)
    uint32_t payloadLen = 0;

    // Check SR (Short Record) flag
    if (tnf_byte & 0x10) {
        // Short record: payload length is 1 byte
        if (pos >= ndefData.size()) {
            _lastError = "NDEF header truncated (short payload len)";
            return false;
        }
        payloadLen = ndefData[pos++];
    } else {
        // Long record: payload length is 4 bytes
        if (pos + 4 > ndefData.size()) {
            _lastError = "NDEF header truncated (long payload len)";
            return false;
        }
        payloadLen = ((uint32_t)ndefData[pos] << 24) |
                     ((uint32_t)ndefData[pos + 1] << 16) |
                     ((uint32_t)ndefData[pos + 2] << 8) |
                     (uint32_t)ndefData[pos + 3];
        pos += 4;
    }

    // Skip type field
    pos += typeLen;

    // Check IL (ID Length) flag
    if (tnf_byte & 0x08) {
        if (pos >= ndefData.size()) {
            _lastError = "NDEF header truncated (id len)";
            return false;
        }
        uint8_t idLen = ndefData[pos++];
        pos += idLen;
    }

    // Extract payload
    if (pos + payloadLen > ndefData.size()) {
        _lastError = "NDEF payload truncated";
        return false;
    }

    // Convert payload to hex string
    configJson = "";
    for (uint32_t i = 0; i < payloadLen; i++) {
        char buf[3];
        snprintf(buf, sizeof(buf), "%02X", ndefData[pos + i]);
        configJson += buf;
    }

    Serial.print("[NFC] Tag payload: ");
    Serial.print(payloadLen);
    Serial.println(" bytes");
    return true;
}

// ================= AES-CTR Decryption =================

String NFCConfigReader::decryptPayload(const std::vector<uint8_t>& encrypted, const String& aesKey) {
    if (encrypted.size() < 17) {
        _lastError = "Encrypted data too short";
        return "";
    }

    // First 16 bytes = IV/nonce
    const uint8_t* iv = encrypted.data();
    size_t ciphertextLen = encrypted.size() - 16;
    const uint8_t* ciphertext = encrypted.data() + 16;

    // Prepare key
    uint8_t keyBuf[16] = {0};
    size_t keyLen = aesKey.length();
    if (keyLen > 16) keyLen = 16;
    memcpy(keyBuf, aesKey.c_str(), keyLen);

    // Prepare output buffer
    std::vector<uint8_t> plaintext(ciphertextLen + 1, 0);

    // AES-CTR decrypt using mbedtls
    mbedtls_aes_context aes;
    mbedtls_aes_init(&aes);
    mbedtls_aes_setkey_enc(&aes, keyBuf, 128);

    uint8_t counter[16];
    memcpy(counter, iv, 16);
    size_t ncOff = 0;
    uint8_t streamBlock[16] = {0};

    int ret = mbedtls_aes_crypt_ctr(&aes, ciphertextLen, &ncOff,
                                     counter, streamBlock,
                                     ciphertext, plaintext.data());
    mbedtls_aes_free(&aes);

    if (ret != 0) {
        _lastError = "AES-CTR decryption failed";
        return "";
    }

    // Null-terminate and convert to String
    plaintext[ciphertextLen] = 0;
    String result = String((const char*)plaintext.data());

    if (result.length() == 0) {
        _lastError = "Decrypted payload is empty";
        return "";
    }

    return result;
}
