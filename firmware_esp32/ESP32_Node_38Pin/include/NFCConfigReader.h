#ifndef NFC_CONFIG_READER_H
#define NFC_CONFIG_READER_H

#include <Arduino.h>
#include <Wire.h>
#include <Adafruit_PN532.h>
#include <vector>

// PN532 I2C Pin Configuration — ONLY SDA/SCL are used
#define NFC_I2C_SDA 21
#define NFC_I2C_SCL 22
#define NFC_POWER_STABILIZE_MS 1000

// NFC Configuration Constants
#define NFC_READ_TIMEOUT_MS 5000UL
#define NFC_MAX_PAYLOAD_SIZE 512

// HCE Constants
#define HCE_AID "F0534D415254504F4E4943"
#define INS_GET_LENGTH 0xCA
#define INS_READ_BINARY 0xB0
#define MAX_CHUNK_SIZE 48

class NFCConfigReader {
public:
    NFCConfigReader();
    bool begin();
    bool isCardPresent();
    bool waitForCard(uint32_t timeoutMs = NFC_READ_TIMEOUT_MS);
    bool quickCardCheck();
    bool readConfig(String& configJson, String& authKey);
    bool writeConfig(const String& configJson);
    String getLastError() const { return _lastError; }
    bool isReady() const { return _initialized; }
    void reinitAfterSleep();

private:
    Adafruit_PN532 _nfc;
    bool _initialized;
    String _lastError;

    bool readHceFromPhone(String& configJson);
    uint8_t handleHceCommand(const uint8_t* apdu, uint8_t apduLen,
                              uint8_t* response, uint8_t& responseLen);
    String decryptPayload(const std::vector<uint8_t>& encrypted, const String& aesKey);
    bool readPhysicalTag(String& configJson);
    void setLed(bool on);
    void flashLed(int count, int durationMs);
};

#endif