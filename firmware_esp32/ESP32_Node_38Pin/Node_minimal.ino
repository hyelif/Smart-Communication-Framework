// Node_minimal.ino - Sends a simple "hello" packet every 5 seconds
// Upload to ESP32 Dev Module via Arduino IDE (Tools > Board > ESP32 Arduino > ESP32 Dev Module)

#include <SPI.h>
#include <LoRa.h>

#define LORA_SCK  18
#define LORA_MISO 19
#define LORA_MOSI 23
#define LORA_SS   5
#define LORA_RST  14
#define LORA_DIO0 -1
#define LORA_BAND 433E6

unsigned long lastTx = 0;

void setup() {
  Serial.begin(115200);
  delay(1000);

  Serial.println("\n========== NODE MINIMAL ==========");

  SPI.begin(LORA_SCK, LORA_MISO, LORA_MOSI, LORA_SS);
  LoRa.setPins(LORA_SS, LORA_RST, LORA_DIO0);

  if (!LoRa.begin(LORA_BAND)) {
    Serial.println("LoRa INIT FAILED!");
    return;
  }
  Serial.println("LoRa INIT OK");

  LoRa.setSyncWord(0xB4);
  LoRa.setSpreadingFactor(9);
  LoRa.setSignalBandwidth(125E3);
  LoRa.setCodingRate4(5);
  LoRa.setPreambleLength(12);
  LoRa.enableCrc();
  LoRa.setTxPower(20);

  Serial.println("Ready, sending every 5s");
  Serial.println("========== READY ==========");
}

void loop() {
  unsigned long now = millis();
  if (now - lastTx < 5000) {
    delay(10);
    return;
  }
  lastTx = now;

  const char* msg = "SmartPonic HELLO from Node 38Pin!";
  int msgLen = strlen(msg);

  Serial.print("\n[TX] Sending: ");
  Serial.println(msg);

  LoRa.beginPacket();
  LoRa.write((const uint8_t*)msg, msgLen);
  LoRa.endPacket();
  LoRa.receive();

  Serial.print("[TX] Done (");
  Serial.print(msgLen);
  Serial.println(" bytes)");
}