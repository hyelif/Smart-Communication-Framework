#include "PacketBuilder.h"
#include "SmartPacket.h"

PacketBuilder::PacketBuilder()
    : _keySet(false)
{
    memset(_key, 0, 16);
}

PacketBuilder::~PacketBuilder() {
    memset(_key, 0, 16);
    _keySet = false;
}

void PacketBuilder::setKey(const uint8_t key[16]) {
    memcpy(_key, key, 16);
    _keySet = true;
    Serial.print("[PACKET] AES key set: ");
    for (int i = 0; i < 16; i++) {
        if (_key[i] < 0x10) Serial.print("0");
        Serial.print(_key[i], HEX);
    }
    Serial.println();
}

void PacketBuilder::build(const String& payload, const uint8_t hardwareId[16],
                           std::vector<uint8_t>& outPacket)
{
    build((const uint8_t*)payload.c_str(), payload.length(), hardwareId, outPacket);

    Serial.print("[PACKET] text plaintext (");
    Serial.print(payload.length());
    Serial.print(" bytes): ");
    Serial.println(payload);
}

void PacketBuilder::build(const uint8_t* data, size_t len, const uint8_t hardwareId[16],
                           std::vector<uint8_t>& outPacket)
{
    outPacket.clear();
    if (!_keySet) {
        Serial.println("[PACKET] ERROR: AES key not set, cannot build packet");
        return;
    }

    // 1. generate nonce
    uint8_t nonce[SmartPacket::NONCE_SIZE];
    SmartPacket::fillNonce(nonce);

    // 2. encrypt payload
    std::vector<uint8_t> encrypted;
    encrypt(data, len, nonce, encrypted);

    // 3. build header with hardware_id
    SmartPacket::Header hdr;
    memset(&hdr, 0, sizeof(hdr));
    hdr.magic        = SmartPacket::MAGIC;
    hdr.version      = SmartPacket::VERSION;
    memcpy(hdr.hardwareId, hardwareId, 16);
    hdr.payloadLength = (uint16_t)encrypted.size();

    // 4. assemble: header + nonce + encrypted + crc32
    outPacket.resize(SmartPacket::HEADER_SIZE + SmartPacket::NONCE_SIZE +
                     encrypted.size() + SmartPacket::CRC_SIZE);

    size_t offset = 0;
    memcpy(outPacket.data() + offset, &hdr, SmartPacket::HEADER_SIZE);
    offset += SmartPacket::HEADER_SIZE;

    memcpy(outPacket.data() + offset, nonce, SmartPacket::NONCE_SIZE);
    offset += SmartPacket::NONCE_SIZE;

    memcpy(outPacket.data() + offset, encrypted.data(), encrypted.size());
    offset += encrypted.size();

    uint32_t crc = SmartPacket::crc32(outPacket.data(), offset);
    memcpy(outPacket.data() + offset, &crc, SmartPacket::CRC_SIZE);

    Serial.print("[PACKET] final packet (");
    Serial.print(outPacket.size());
    Serial.print(" bytes): ");
    for (size_t i = 0; i < outPacket.size() && i < 24; i++) {
        if (outPacket[i] < 0x10) Serial.print("0");
        Serial.print(outPacket[i], HEX);
        Serial.print(" ");
    }
    if (outPacket.size() > 24) Serial.print("...");
    Serial.print(" | CRC32=0x");
    Serial.print(crc, HEX);
    Serial.println();
}

void PacketBuilder::encrypt(const uint8_t* plain, size_t len, const uint8_t nonce[16],
                             std::vector<uint8_t>& outEncrypted)
{
    outEncrypted.resize(len);

    uint8_t counter[SmartPacket::NONCE_SIZE];
    memcpy(counter, nonce, SmartPacket::NONCE_SIZE);
    size_t ncOff = 0;
    uint8_t streamBlock[16] = {0};

    mbedtls_aes_context aes;
    mbedtls_aes_init(&aes);
    mbedtls_aes_setkey_enc(&aes, _key, 128);
    mbedtls_aes_crypt_ctr(&aes, len, &ncOff, counter, streamBlock,
                          plain, outEncrypted.data());
    mbedtls_aes_free(&aes);
}
