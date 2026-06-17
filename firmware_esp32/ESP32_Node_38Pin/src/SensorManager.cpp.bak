#include "SensorManager.h"
#include "SmartPacket.h"

SensorManager::SensorManager()
    : _count(0)
    , _initialized(false)
{
    memset(_dhtInstances, 0, sizeof(_dhtInstances));
    memset(_oneWireInstances, 0, sizeof(_oneWireInstances));
    memset(_dtInstances, 0, sizeof(_dtInstances));
}

SensorManager::~SensorManager() {
    clearSensors();
}

bool SensorManager::addSensor(int pin, const String& type, const String& sensor, const String& label) {
    if (_count >= MAX_SENSORS) {
        Serial.println("[SENSOR] FAIL: max sensors reached");
        return false;
    }
    if (!SmartPacket::isSafePin(pin)) {
        Serial.print("[SENSOR] FAIL: pin ");
        Serial.print(pin);
        Serial.println(" is not in safe pin whitelist");
        return false;
    }

    for (int i = 0; i < _count; i++) {
        if (_configs[i].pin == pin) {
            Serial.print("[SENSOR] FAIL: duplicate pin ");
            Serial.println(pin);
            return false;
        }
    }

    _configs[_count].pin   = pin;
    _configs[_count].type  = type;
    _configs[_count].sensor = sensor;
    _configs[_count].label = label;
    _count++;

    Serial.print("[SENSOR] added [");
    Serial.print(_count - 1);
    Serial.print("] pin=");
    Serial.print(pin);
    Serial.print(" type=");
    Serial.print(type);
    Serial.print(" sensor=");
    Serial.print(sensor);
    Serial.print(" label=");
    Serial.println(label);
    return true;
}

void SensorManager::clearSensors() {
    for (int i = 0; i < MAX_SENSORS; i++) {
        if (_dhtInstances[i]) { delete _dhtInstances[i]; _dhtInstances[i] = nullptr; }
        if (_oneWireInstances[i]) { delete _oneWireInstances[i]; _oneWireInstances[i] = nullptr; }
        if (_dtInstances[i]) { delete _dtInstances[i]; _dtInstances[i] = nullptr; }
    }
    _count = 0;
    _initialized = false;
    Serial.println("[SENSOR] all sensors cleared");
}

bool SensorManager::init() {
    Serial.println("[SENSOR] initializing...");
    for (int i = 0; i < _count; i++) {
        const auto& cfg = _configs[i];
        if (cfg.sensor == "DHT22") {
            Serial.print("[SENSOR] init DHT22 on pin ");
            Serial.println(cfg.pin);
            _dhtInstances[i] = new DHT(cfg.pin, DHT22);
            _dhtInstances[i]->begin();
        } else if (cfg.sensor == "WaterTemp") {
            Serial.print("[SENSOR] init DS18B20 on pin ");
            Serial.println(cfg.pin);
            _oneWireInstances[i] = new OneWire(cfg.pin);
            _dtInstances[i] = new DallasTemperature(_oneWireInstances[i]);
            _dtInstances[i]->begin();
        } else if (cfg.sensor == "Rain") {
            Serial.print("[SENSOR] init Rain on pin ");
            Serial.print(cfg.pin);
            Serial.println(" (digital input with pull-up)");
            pinMode(cfg.pin, INPUT_PULLUP);
        } else {
            Serial.print("[SENSOR] init ");
            Serial.print(cfg.sensor);
            Serial.print(" on pin ");
            Serial.print(cfg.pin);
            Serial.println(" (analog/digital, no HW init needed)");
        }
    }
    _initialized = true;
    Serial.println("[SENSOR] init complete");
    return true;
}

void SensorManager::sample(std::vector<SensorReading>& output) {
    output.clear();
    if (!_initialized) {
        Serial.println("[SENSOR] WARN: sampling skipped, not initialized");
        return;
    }

    for (int i = 0; i < _count; i++) {
        const auto& cfg = _configs[i];
        if (cfg.sensor == "DHT22") {
            readDht22(i, cfg, output);
        } else if (cfg.sensor == "WaterTemp") {
            readWaterTemp(i, cfg, output);
        } else if (cfg.sensor == "Rain") {
            readRain(cfg, output);
        } else {
            readAnalogSensor(cfg, output);
        }
    }
}

void SensorManager::readDht22(int idx, const GpioConfig& cfg, std::vector<SensorReading>& output) {
    if (!_dhtInstances[idx]) {
        Serial.print("[SENSOR] DHT22 null on pin ");
        Serial.println(cfg.pin);
        return;
    }

    float t = _dhtInstances[idx]->readTemperature();
    float h = _dhtInstances[idx]->readHumidity();

    SensorReading tr;
    tr.pin = cfg.pin;
    tr.sensorName = "Temperature";

    if (isnan(t)) {
        tr.rawValue = "nan";
        Serial.print("[SENSOR] DHT22 pin=");
        Serial.print(cfg.pin);
        Serial.println(" Temperature: nan (READ ERROR!)");
    } else {
        tr.rawValue = String(t, 1);
        Serial.print("[SENSOR] DHT22 pin=");
        Serial.print(cfg.pin);
        Serial.print(" Temperature: ");
        Serial.print(t, 1);
        Serial.println(" °C");
    }
    tr.segment = String(cfg.pin) + "=Temperature=" + tr.rawValue;
    output.push_back(tr);

    SensorReading hr;
    hr.pin = cfg.pin;
    hr.sensorName = "Humidity";

    if (isnan(h)) {
        hr.rawValue = "nan";
        Serial.print("[SENSOR] DHT22 pin=");
        Serial.print(cfg.pin);
        Serial.println(" Humidity: nan (READ ERROR!)");
    } else {
        hr.rawValue = String(h, 1);
        Serial.print("[SENSOR] DHT22 pin=");
        Serial.print(cfg.pin);
        Serial.print(" Humidity: ");
        Serial.print(h, 1);
        Serial.println(" %");
    }
    hr.segment = String(cfg.pin) + "=Humidity=" + hr.rawValue;
    output.push_back(hr);
}

void SensorManager::readWaterTemp(int idx, const GpioConfig& cfg, std::vector<SensorReading>& output) {
    if (!_dtInstances[idx]) {
        Serial.print("[SENSOR] DS18B20 null on pin ");
        Serial.println(cfg.pin);
        return;
    }

    _dtInstances[idx]->requestTemperatures();
    float t = _dtInstances[idx]->getTempCByIndex(0);

    SensorReading sr;
    sr.pin = cfg.pin;
    sr.sensorName = "WaterTemp";

    if (t == -127.00 || t == DEVICE_DISCONNECTED_C) {
        sr.rawValue = "-127.0";
        Serial.print("[SENSOR] DS18B20 pin=");
        Serial.print(cfg.pin);
        Serial.println(" WaterTemp: -127.0 (DISCONNECTED!)");
    } else {
        sr.rawValue = String(t, 1);
        Serial.print("[SENSOR] DS18B20 pin=");
        Serial.print(cfg.pin);
        Serial.print(" WaterTemp: ");
        Serial.print(t, 1);
        Serial.println(" °C");
    }
    sr.segment = String(cfg.pin) + "=WaterTemp=" + sr.rawValue;
    output.push_back(sr);
}

void SensorManager::readAnalogSensor(const GpioConfig& cfg, std::vector<SensorReading>& output) {
    int raw = analogRead(cfg.pin);
    float value = 0.0;

    if (cfg.sensor == "pH") {
        value = ((raw - 1500.0) / 250.0) + 7.0;
        if (value < 0.0) value = 0.0;
        if (value > 14.0) value = 14.0;
        Serial.print("[SENSOR] pH pin=");
        Serial.print(cfg.pin);
        Serial.print(" raw=");
        Serial.print(raw);
        Serial.print(" pH=");
        Serial.println(value, 1);
    } else if (cfg.sensor == "TDS") {
        value = (raw / 4095.0) * 2000.0 * 0.5;
        Serial.print("[SENSOR] TDS pin=");
        Serial.print(cfg.pin);
        Serial.print(" raw=");
        Serial.print(raw);
        Serial.print(" TDS=");
        Serial.print(value, 1);
        Serial.println(" ppm");
    } else if (cfg.sensor == "Turbidity") {
        // Invert: higher raw = clearer water, lower raw = cloudier
        value = ((4095.0 - raw) / 4095.0) * 3000.0;
        Serial.print("[SENSOR] Turbidity pin=");
        Serial.print(cfg.pin);
        Serial.print(" raw=");
        Serial.print(raw);
        Serial.print(" NTU=");
        Serial.println(value, 1);
    } else {
        value = raw;
        Serial.print("[SENSOR] Analog pin=");
        Serial.print(cfg.pin);
        Serial.print(" type=");
        Serial.print(cfg.sensor);
        Serial.print(" raw=");
        Serial.println(raw);
    }

    SensorReading sr;
    sr.pin = cfg.pin;
    sr.sensorName = cfg.sensor;
    sr.rawValue = String(value, 1);
    sr.segment = String(cfg.pin) + "=" + cfg.sensor + "=" + sr.rawValue;
    output.push_back(sr);
}

void SensorManager::readRain(const GpioConfig& cfg, std::vector<SensorReading>& output) {
    int val = digitalRead(cfg.pin);

    SensorReading sr;
    sr.pin = cfg.pin;
    sr.sensorName = "Rain";
    // Most rain sensor modules: DO=LOW when wet (rain), DO=HIGH when dry (sunny)
    sr.rawValue = val == HIGH ? "1" : "0";
    sr.segment = String(cfg.pin) + "=Rain=" + sr.rawValue;

    Serial.print("[SENSOR] Rain pin=");
    Serial.print(cfg.pin);
    Serial.print(" digital=");
    Serial.print(val);
    Serial.print(" status=");
    Serial.println(val == HIGH ? "1 (sunny)" : "0 (rain)");
    output.push_back(sr);
}
