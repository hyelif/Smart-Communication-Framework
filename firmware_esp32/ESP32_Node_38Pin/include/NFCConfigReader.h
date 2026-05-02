#ifndef NFC_CONFIG_READER_H
#define NFC_CONFIG_READER_H

#include <Arduino.h>
#include <Wire.h>
#include <Adafruit_PN532.h>
#include <vector>
#include <String>

// PN532 I2C Pin Configuration
#define NFC_I2C_SDA 21
#define NFC_I2C_SCL 22
#define NFC_IRQ 27      // PN532 IRQ pin (avoid LoRa MOSI on GPIO23)
#define NFC_RESET -1    // Not connected by default

// NFC LED Indicator
#define NFC_LED_PIN 2   // Built-in LED on most ESP32 dev boards

// NFC Configuration Constants
#define NFC_READ_TIMEOUT_MS 5000UL
#define NFC_DEFAULT_CHECK_INTERVAL_MS 2000UL
#define NFC_MAX_PAYLOAD_SIZE 512  // NTAG215 has 504 bytes user memory
#define NFC_MAX_HCE_PAYLOAD_SIZE 2048  // Direct Android HCE has no tag-memory cap

// NDEF Record Type for SmartPonic Config
#define SMARTPONIC_NDEF_TNF 0x02  // MIME media type
#define SMARTPONIC_NDEF_TYPE "application/x-smartponic"
#define SMARTPONIC_NDEF_TYPE_LEN 24

class NFCConfigReader {
public:
    NFCConfigReader();

    // Initialize PN532 hardware
    bool begin();

    // Check if NFC card/tag is present
    bool isCardPresent();

    // Wait for card and read config payload
    // Returns true if config was successfully read and decrypted
    bool waitForCard(uint32_t timeoutMs = NFC_READ_TIMEOUT_MS);

    // Read config from detected card
    // Returns true if payload was successfully read and decrypted
    bool readConfig(String& configJson, String& authKey);

    // Write config to card (for testing/debugging)
    bool writeConfig(const String& configJson);

    // Get last error message
    String getLastError() const { return _lastError; }

    // Check if PN532 is initialized and ready
    bool isReady() const { return _initialized; }

private:
    Adafruit_PN532 _nfc;
    bool _initialized;
    String _lastError;

    // Decrypt NFC payload (AES-128-CTR)
    String decryptPayload(const std::vector<uint8_t>& encrypted, const String& aesKey);

    // Parse NDEF record from NFC tag
    bool parseNdefRecord(const uint8_t* data, uint16_t len, std::vector<uint8_t>& payload);

    // Read encrypted payload from an Android phone using Host Card Emulation.
    bool readDirectHceConfig(String& configJson);

    // Exchange an APDU with the currently selected NFC target.
    bool exchangeApdu(const uint8_t* command, uint8_t commandLen,
                      uint8_t* response, uint8_t& responseLen);

    bool isSuccessStatus(const uint8_t* response, uint8_t responseLen);

    // Set LED indicator
    void setLed(bool on);

    // Flash LED for status indication
    void flashLed(int count, int durationMs);
};

#endif // NFC_CONFIG_READER_H
