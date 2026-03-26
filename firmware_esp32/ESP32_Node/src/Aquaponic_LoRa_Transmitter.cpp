#include <Arduino.h>
#include <SPI.h>
#include <LoRa.h>
#include <WiFi.h>
#include <WebServer.h>
#include <ArduinoJson.h>
#include <Preferences.h>
#include <vector>
#include <DHT.h>
#include <OneWire.h>
#include <DallasTemperature.h>
#include <mbedtls/aes.h>

// ================= SETTINGS =================
const char *key = "SmartPonic123456"; // Changed to const to fix ISO warning
const char* ssid = "AQUA_NODE";
const char* password = "12345678";

WebServer server(80);
Preferences prefs;

// LoRa Pins
#define LORA_SCK    18
#define LORA_MISO   19
#define LORA_MOSI   23
#define LORA_SS      5
#define LORA_RST    14
#define LORA_DIO0   -1
#define LORA_SYNC_WORD 0xB4
const String SECRET_KEY = "AQUA77";

struct GPIOConfig {
  int pin;
  String type;
  String sensor;
};

std::vector<GPIOConfig> configList;
#define MAX_SENSORS 10

// Sensor Pointers
DHT* dhtSensors[MAX_SENSORS];
OneWire* oneWireSensors[MAX_SENSORS];
DallasTemperature* tempSensors[MAX_SENSORS];

const int safePins[] = {25, 26, 27, 32, 33, 34, 35};

bool isSafePin(int pin) {
  for (int i = 0; i < 7; i++) if (safePins[i] == pin) return true;
  return false;
}

// ================= CONFIG LOGIC =================

void applyConfig(JsonArray arr) {
  for (int i = 0; i < MAX_SENSORS; i++) {
    if (dhtSensors[i]) { delete dhtSensors[i]; dhtSensors[i] = nullptr; }
    if (tempSensors[i]) { delete tempSensors[i]; tempSensors[i] = nullptr; }
    if (oneWireSensors[i]) { delete oneWireSensors[i]; oneWireSensors[i] = nullptr; }
  }

  configList.clear();
  int idx = 0;

  for (JsonObject obj : arr) {
    if (idx >= MAX_SENSORS) break;

    int pin = obj["pin"];
    String sensor = obj["sensor"];
    String type = obj["type"];

    if (!isSafePin(pin)) continue;

    configList.push_back({pin, type, sensor});

    if (sensor == "DHT22") {
      dhtSensors[idx] = new DHT(pin, DHT22);
      dhtSensors[idx]->begin();
    } else if (sensor == "WaterTemp") {
      oneWireSensors[idx] = new OneWire(pin);
      tempSensors[idx] = new DallasTemperature(oneWireSensors[idx]);
      tempSensors[idx]->begin();
    }

    if (type == "DO") pinMode(pin, OUTPUT);
    else pinMode(pin, INPUT);

    idx++;
  }
}

void handleGetConfig() {
  prefs.begin("cfg", true);
  String json = prefs.getString("json", "{\"config\":[]}");
  prefs.end();
  server.send(200, "application/json", json);
}

void handlePostConfig() {
  if (server.hasArg("plain") == false) {
    server.send(400, "application/json", "{\"status\":\"no body\"}");
    return;
  }

  String body = server.arg("plain");
  Serial.println("📥 Received New Config from App:");
  Serial.println(body); 

  DynamicJsonDocument doc(4096);
  DeserializationError error = deserializeJson(doc, body);

  if (error) {
    Serial.print("❌ JSON Parse Failed: ");
    Serial.println(error.f_str());
    server.send(400, "application/json", "{\"status\":\"parse error\"}");
    return;
  }

  if (doc.containsKey("config")) {
    JsonArray arr = doc["config"];
    applyConfig(arr);

    prefs.begin("cfg", false);
    prefs.putString("json", body);
    prefs.end();

    Serial.println("✅ Config Applied and Saved to Flash!");
    server.send(200, "application/json", "{\"status\":\"ok\"}");
  } else {
    server.send(400, "application/json", "{\"status\":\"missing config key\"}");
  }
} // <--- Brackets fixed here to prevent "Expected a declaration"

// ================= LORA & ENCRYPTION =================

String buildPayload() {
  String payload = "auth=" + SECRET_KEY + "&"; 
  for (size_t i = 0; i < configList.size(); i++) {
    auto c = configList[i];
    String prefix = String(c.pin) + "=" + c.sensor;

    if (c.sensor == "DHT22" && dhtSensors[i]) {
      payload += prefix + "_T=" + String(dhtSensors[i]->readTemperature(), 1) + "&";
      payload += prefix + "_H=" + String(dhtSensors[i]->readHumidity(), 1) + "&";
    } else if (c.sensor == "WaterTemp" && tempSensors[i]) {
      tempSensors[i]->requestTemperatures();
      payload += prefix + "=" + String(tempSensors[i]->getTempCByIndex(0), 1) + "&";
    } else if (c.sensor == "pH" || c.sensor == "TDS" || c.sensor == "Turbidity") {
      payload += prefix + "=" + String(analogRead(c.pin)) + "&";
    }
  }
  payload += "node=1";
  return payload;
}

String encrypt(String plainText) {
  int paddedLen = ((plainText.length() / 16) + 1) * 16;
  unsigned char input[paddedLen];
  unsigned char output[paddedLen];
  memset(input, 0, paddedLen);
  memcpy(input, plainText.c_str(), plainText.length());

  mbedtls_aes_context aes;
  mbedtls_aes_init(&aes);
  mbedtls_aes_setkey_enc(&aes, (const unsigned char*) key, 128);
  for (int i = 0; i < paddedLen; i += 16) {
    mbedtls_aes_crypt_ecb(&aes, MBEDTLS_AES_ENCRYPT, input + i, output + i);
  }
  mbedtls_aes_free(&aes);

  String hexStr = "";
  for (int i = 0; i < paddedLen; i++) {
    if (output[i] < 0x10) hexStr += "0";
    hexStr += String(output[i], HEX);
  }
  return hexStr;
}

void setup() {
  Serial.begin(115200);
  
  for(int i=0; i<MAX_SENSORS; i++) {
    dhtSensors[i] = nullptr; oneWireSensors[i] = nullptr; tempSensors[i] = nullptr;
  }

  WiFi.softAP(ssid, password);
  
  prefs.begin("cfg", true);
  String savedJson = prefs.getString("json", "");
  prefs.end();
  
  if (savedJson != "") {
    DynamicJsonDocument doc(4096);
    deserializeJson(doc, savedJson);
    if(doc.containsKey("config")) {
        applyConfig(doc["config"]);
    }
  }

  server.on("/config", HTTP_POST, handlePostConfig);
  server.on("/config", HTTP_GET, handleGetConfig); 
  server.begin();

  SPI.begin(LORA_SCK, LORA_MISO, LORA_MOSI, LORA_SS);
  LoRa.setPins(LORA_SS, LORA_RST, LORA_DIO0);
  if (LoRa.begin(433E6)) {
    LoRa.setSyncWord(LORA_SYNC_WORD);
    Serial.println("✅ System Ready");
  }
}

void loop() {
  server.handleClient();
  
  static unsigned long lastSend = 0;
  if (millis() - lastSend > 15000) {
    String raw = buildPayload();
    String secure = encrypt(raw);
    
    LoRa.beginPacket();
    LoRa.print(secure);
    LoRa.endPacket();

    Serial.print("Raw: "); Serial.println(raw);
    Serial.print("Encrypted HEX: "); Serial.println(secure);
    
    lastSend = millis();
  }
}