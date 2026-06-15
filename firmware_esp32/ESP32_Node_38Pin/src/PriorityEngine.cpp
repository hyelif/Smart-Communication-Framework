#include "PriorityEngine.h"
#include "SmartPacket.h"

PriorityEngine::PriorityEngine()
    : _priority(SmartPacket::PRIORITY_LOW)
    , _reportMode(SmartPacket::REPORT_MODE_NORMAL)
    , _intervalMs(SmartPacket::INTERVAL_NORMAL_MS)
    , _criticalPending(false)
{
}

void PriorityEngine::evaluate(const std::vector<SensorReading>& readings) {
    uint8_t maxPriority = SmartPacket::PRIORITY_LOW;

    for (const auto& r : readings) {
        uint8_t p = classifySensor(r.sensorName, r.rawValue);
        if (p > maxPriority) maxPriority = p;
    }

    _priority = maxPriority;
    updateMode(maxPriority);
}

uint8_t PriorityEngine::classifySensor(const String& name, const String& value) {
    float v = value.toFloat();
    bool isNan = (value == "nan");
    bool isErr = (value == "-127.0");

    if (name == "Temperature") {
        if (isNan) return SmartPacket::PRIORITY_HIGH;
        if (v < 18.0 || v > 35.0) return SmartPacket::PRIORITY_HIGH;
        if (v < 22.0 || v > 32.0) return SmartPacket::PRIORITY_MEDIUM;
        return SmartPacket::PRIORITY_LOW;
    }

    if (name == "Humidity") {
        if (isNan) return SmartPacket::PRIORITY_HIGH;
        if (v < 30.0 || v > 90.0) return SmartPacket::PRIORITY_HIGH;
        if (v < 40.0 || v > 80.0) return SmartPacket::PRIORITY_MEDIUM;
        return SmartPacket::PRIORITY_LOW;
    }

    if (name == "WaterTemp") {
        if (isErr) return SmartPacket::PRIORITY_HIGH;
        if (v < 15.0 || v > 32.0) return SmartPacket::PRIORITY_HIGH;
        if (v < 20.0 || v > 30.0) return SmartPacket::PRIORITY_MEDIUM;
        return SmartPacket::PRIORITY_LOW;
    }

    if (name == "pH") {
        if (v < 5.5 || v > 8.5) return SmartPacket::PRIORITY_HIGH;
        if (v < 6.0 || v > 8.0) return SmartPacket::PRIORITY_MEDIUM;
        return SmartPacket::PRIORITY_LOW;
    }

    if (name == "TDS") {
        if (v > 1200.0) return SmartPacket::PRIORITY_HIGH;
        if (v > 800.0)  return SmartPacket::PRIORITY_MEDIUM;
        return SmartPacket::PRIORITY_LOW;
    }

    if (name == "Turbidity") {
        if (v > 1000.0) return SmartPacket::PRIORITY_HIGH;
        if (v > 300.0)  return SmartPacket::PRIORITY_MEDIUM;
        return SmartPacket::PRIORITY_LOW;
    }

    if (name == "Rain") {
        if (v > 0.5) return SmartPacket::PRIORITY_MEDIUM; // rain detected
        return SmartPacket::PRIORITY_LOW;
    }

    return SmartPacket::PRIORITY_LOW;
}

void PriorityEngine::updateMode(uint8_t prio) {
    switch (prio) {
        case SmartPacket::PRIORITY_HIGH:
            _reportMode = SmartPacket::REPORT_MODE_CRITICAL;
            _intervalMs = SmartPacket::INTERVAL_CRITICAL_MS;
            _criticalPending = true;
            break;
        case SmartPacket::PRIORITY_MEDIUM:
            _reportMode = SmartPacket::REPORT_MODE_ABNORMAL;
            _intervalMs = SmartPacket::INTERVAL_ABNORMAL_MS;
            break;
        default:
            _reportMode = SmartPacket::REPORT_MODE_NORMAL;
            _intervalMs = SmartPacket::INTERVAL_NORMAL_MS;
            break;
    }
}
