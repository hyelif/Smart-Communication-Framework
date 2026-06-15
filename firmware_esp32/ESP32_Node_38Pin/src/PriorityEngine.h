#ifndef PRIORITYENGINE_H
#define PRIORITYENGINE_H

#include <Arduino.h>
#include <vector>
#include "SensorManager.h"

class PriorityEngine {
public:
    PriorityEngine();

    void evaluate(const std::vector<SensorReading>& readings);

    uint8_t getPriority()   const { return _priority; }
    uint8_t getReportMode() const { return _reportMode; }
    unsigned long getIntervalMs() const { return _intervalMs; }
    bool isCriticalPending() const { return _criticalPending; }
    void clearCriticalFlag() { _criticalPending = false; }

private:
    uint8_t _priority;
    uint8_t _reportMode;
    unsigned long _intervalMs;
    bool _criticalPending;

    uint8_t classifySensor(const String& name, const String& value);
    void updateMode(uint8_t prio);
};

#endif // PRIORITYENGINE_H
