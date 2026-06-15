#ifndef PACKETBUILDER_H
#define PACKETBUILDER_H

#include <Arduino.h>
#include <vector>
#include <mbedtls/aes.h>

class PacketBuilder {
public:
    PacketBuilder();
    ~PacketBuilder();

    void setKey(const uint8_t key[16]);
    bool isKeySet() const { return _keySet; }

    void build(const String& payload, const uint8_t hardwareId[16],
               std::vector<uint8_t>& outPacket);

    // Binary payload: encrypts raw bytes directly (no text conversion)
    void build(const uint8_t* data, size_t len, const uint8_t hardwareId[16],
               std::vector<uint8_t>& outPacket);

private:
    bool _keySet;
    uint8_t _key[16];

    void encrypt(const uint8_t* plain, size_t len, const uint8_t nonce[16],
                 std::vector<uint8_t>& outEncrypted);
};

#endif // PACKETBUILDER_H
