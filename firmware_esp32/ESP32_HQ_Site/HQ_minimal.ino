// HQ_minimal.ino - Pure LoRa receiver, dumps everything to Serial
// Upload to LOLIN S2 Mini via Arduino IDE
// Board: Tools > Board > ESP32 Arduino > LOLIN S2 Mini
// Port: COM16

#include <SPI.h>
#include <LoRa.h>

// ================= PIN MAP (LOLIN S2 Mini - DEFAULT SPI) =================
// GPIO 7  -> SCK  (SPI clock)
// GPIO 9  -> MISO (SPI master-in-slave-out)
// GPIO 11 -> MOSI (SPI master-out-slave-in)
// GPIO 12 -> SS   (LoRa chip select / NSS)
// GPIO 5  -> RST  (LoRa reset)
// 3.3V    -> VCC
// GND     -> GND
// ========================================================================

#define LORA_SCK  7
#define LORA_MISO 9
#define LORA_MOSI 11
#define LORA_SS   12
#define LORA_RST  5
#define LORA_DIO0 -1
#define LORA_BAND 433E6

void setup() {
  Serial.begin(115200);
  delay(2000);

  Serial.println("\n========== HQ MINIMAL ==========");
  Serial.println("S2 Mini DEFAULT SPI pins:");
  Serial.println("  SCK  = GPIO 7");
  Serial.println("  MISO = GPIO 9");
  Serial.println("  MOSI = GPIO 11");
  Serial.println("  SS   = GPIO 12");
  Serial.println("  RST  = GPIO 5");

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
  LoRa.receive();

  Serial.println("Listening on 433MHz SF9");
  Serial.println("========== READY ==========");
}

void loop() {
  int packetSize = LoRa.parsePacket();
  if (packetSize == 0) {
    delay(5);
    return;
  }

  uint8_t buf[256];
  int len = 0;
  while (LoRa.available() && len < 256) {
    buf[len++] = LoRa.read();
  }
  LoRa.receive();

  Serial.print("\n[RX] ");
  Serial.print(len);
  Serial.print(" bytes  RSSI=");
  Serial.print(LoRa.packetRssi());
  Serial.print("  SNR=");
  Serial.println(LoRa.packetSnr());

  Serial.print("  HEX: ");
  for (int i = 0; i < len && i < 64; i++) {
    if (buf[i] < 0x10) Serial.print("0");
    Serial.print(buf[i], HEX);
    Serial.print(" ");
  }
  if (len > 64) Serial.print("...");
  Serial.println();

  Serial.print("  ASCII: ");
  for (int i = 0; i < len && i < 128; i++) {
    if (buf[i] >= 32 && buf[i] < 127) Serial.print((char)buf[i]);
    else Serial.print(".");
  }
  Serial.println();
}