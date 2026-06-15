#ifndef SENSORMANAGER_H
#define SENSORMANAGER_H

#include <Arduino.h>
#include <vector>

#include <DHT.h>
#include <OneWire.h>
#include <DallasTemperature.h>

#define MAX_SENSORS 24

struct SensorReading {
    int pin;           // GPIO pin number
    String sensorName; // canonical name
    String rawValue;   // string representation
    String segment;    // "pin=sensorName=rawValue"
};

struct GpioConfig {
    int pin;
    String type;   // "AI" / "DI" / "DO"
    String sensor; // "DHT22" / "WaterTemp" / "pH" / "TDS" / "Turbidity" / "Rain"
    String label;
};

class SensorManager {
public:
    SensorManager();
    ~SensorManager();

    bool addSensor(int pin, const String& type, const String& sensor, const String& label);
    void clearSensors();
    bool init();
    void sample(std::vector<SensorReading>& output);

    int count() const { return _count; }
    const GpioConfig& getConfig(int index) const { return _configs[index]; }
    bool isInitialized() const { return _initialized; }

private:
    GpioConfig _configs[MAX_SENSORS];
    int _count;
    bool _initialized;

    DHT* _dhtInstances[MAX_SENSORS];
    OneWire* _oneWireInstances[MAX_SENSORS];
    DallasTemperature* _dtInstances[MAX_SENSORS];

    void readDht22(int idx, const GpioConfig& cfg, std::vector<SensorReading>& output);
    void readWaterTemp(int idx, const GpioConfig& cfg, std::vector<SensorReading>& output);
    void readAnalogSensor(const GpioConfig& cfg, std::vector<SensorReading>& output);
    void readRain(const GpioConfig& cfg, std::vector<SensorReading>& output);
};

#endif // SENSORMANAGER_H
