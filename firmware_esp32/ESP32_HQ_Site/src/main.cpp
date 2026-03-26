#include <Arduino.h>
#include <SPI.h>
#include <LoRa.h>
#include <mbedtls/aes.h>

char *key = "SmartPonic123456"; // Must match Node key

// ===== ESP32-S2 MINI =====
#define LORA_SCK   7
#define LORA_MISO  8
#define LORA_MOSI  9
#define LORA_SS    6
#define LORA_RST   5
#define LORA_DIO0  -1
#define LORA_SYNC_WORD 0xB4
const String SECRET_KEY = "AQUA77";

void parseData(String data) {
  Serial.println("\n--- Decrypted & Mapped Data ---");

  int start = 0;
  while (true) {
    int amp = data.indexOf('&', start);
    if (amp == -1) amp = data.length();
    
    String segment = data.substring(start, amp);
    if (segment.length() > 0) {
      
      // Find the first and last '=' in the segment (e.g., 32=pH=7.2)
      int firstEq = segment.indexOf('=');
      int lastEq = segment.lastIndexOf('=');

      if (firstEq != -1 && firstEq != lastEq) {
        String pin = segment.substring(0, firstEq);
        String sensor = segment.substring(firstEq + 1, lastEq);
        String val = segment.substring(lastEq + 1);

        Serial.print("Pin: " + pin);
        Serial.print(" | Sensor: " + sensor);
        Serial.println(" | Value: " + val);
      } else if (firstEq != -1) {
        // Handle the "node=1" part which only has one '='
        Serial.println("🆔 " + segment);
      }
    }

    if (amp >= data.length()) break;
    start = amp + 1;
  }
}

void setup() {
  Serial.begin(115200);
  delay(2000);

  pinMode(LORA_RST, OUTPUT);
  digitalWrite(LORA_RST, LOW);
  delay(10);
  digitalWrite(LORA_RST, HIGH);

  SPI.begin(LORA_SCK, LORA_MISO, LORA_MOSI, LORA_SS);
  LoRa.setPins(LORA_SS, LORA_RST, LORA_DIO0);

  if (!LoRa.begin(433E6)) {
    Serial.println("❌ LoRa failed");
    while (1);
  }

  LoRa.setSyncWord(LORA_SYNC_WORD); // Only listens to 0xB4
  Serial.println("✅ SECURE HQ READY");
}

String decrypt(String hexText) {
  int len = hexText.length() / 2;
  unsigned char input[len];
  unsigned char output[len];

  // Convert Hex string back to bytes
  for (int i = 0; i < len; i++) {
    input[i] = (unsigned char) strtol(hexText.substring(i*2, i*2+2).c_str(), NULL, 16);
  }

  mbedtls_aes_context aes;
  mbedtls_aes_init(&aes);
  mbedtls_aes_setkey_dec(&aes, (const unsigned char*) key, 128);

  for (int i = 0; i < len; i += 16) {
    mbedtls_aes_crypt_ecb(&aes, MBEDTLS_AES_DECRYPT, input + i, output + i);
  }

  mbedtls_aes_free(&aes);
  return String((char*)output);
}

// ===== UPDATED LOOP WITH SECURITY CHECK =====
void loop() {
  int packetSize = LoRa.parsePacket();
  if (packetSize) {
    int rssi = LoRa.packetRssi();
    float snr = LoRa.packetSnr();

    String received = "";
    while (LoRa.available()) { received += (char)LoRa.read(); }

    String decryptedData = decrypt(received);
    
    Serial.println("🔒 Encrypted: " + received);
    Serial.println("🔓 Decrypted: " + decryptedData);
    Serial.println("&rssi =" + String(rssi) + " &snr =" + String(snr));

    parseData(decryptedData); // Now parse the clean data
  }
}