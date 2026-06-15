const fs = require('fs');
const path = require('path');

const file = path.join(__dirname, 'app/Http/Controllers/DashboardController.php');
let content = fs.readFileSync(file, 'utf8');

// Fix 1: activeSensors - pass node_id and hardware_id for adaptive card display
const oldActiveSensorsReturn = `return [
                "key"    => $key,
                "sensor" => $row->sensor,
                "pin"    => $row->pin,
                "value"  => $value,
                "status" => $status,
                "unit"   => $profile["unit"] ?? "",
                "label"  => $profile["label"] ?? $key,
                "icon"   => $profile["icon"] ?? "\u2753",
                "color"  => $profile["color"] ?? "#888888",
                "badge"  => [
                    "text"  => strtoupper($status),
                    "class" => $status === "normal" ? "bg-emerald-400/10 text-emerald-400"
                        : ($status === "low" ? "bg-blue-400/10 text-blue-400" : "bg-red-400/10 text-red-400"),
                ],
            ];`;
const newActiveSensorsReturn = `return [
                "key"    => $key,
                "sensor" => $row->sensor,
                "pin"    => $row->pin,
                "value"  => $value,
                "status" => $status,
                "unit"   => $profile["unit"] ?? "",
                "label"  => $profile["label"] ?? $key,
                "icon"   => $profile["icon"] ?? "\u2753",
                "color"  => $profile["color"] ?? "#888888",
                "badge"  => [
                    "text"  => strtoupper($status),
                    "class" => $status === "normal" ? "bg-emerald-400/10 text-emerald-400"
                        : ($status === "low" ? "bg-blue-400/10 text-blue-400" : "bg-red-400/10 text-red-400"),
                ],
                "node_id"     => $latest->node_id ?? $latest->hardware_id ?? null,
                "hardware_id" => $latest->hardware_id ?? null,
            ];`;
content = content.replace(oldActiveSensorsReturn, newActiveSensorsReturn);

// Fix 2: systemSummary - fix CRITICAL event reporting for non-numeric values
const oldCriticalEvent = `$criticalEvents[] = [
                    "time"   => date("H:i", strtotime($row->created_at)),
                    "sensor" => $row->sensor,
                    "value"  => $value,
                ];`;
const newCriticalEvent = `$criticalEvents[] = [
                    "time"   => date("H:i", strtotime($row->created_at)),
                    "sensor" => $row->sensor,
                    "value"  => is_numeric($value) ? round($value, 2) : $row->value,
                ];`;
content = content.replace(oldCriticalEvent, newCriticalEvent);

// Fix 3: poll endpoint - also pass nodes so the frontend can display which node owns each sensor
const oldPollResult = `$result = [
            "sensor_readings"   => $this->latestReading($profiles),
            "active_sensors"   => $this->activeSensors($profiles),
            "telegram_bot_state"=> $this->sanitizeResult(DB::table("telegram_bot_state")->orderBy("state_key")->get()),
            "active_alerts"    => $this->getAlerts(),
            "signal_stats"     => $this->getSignalStats($range),
            "comm_health"      => $this->getCommHealth(),
            "profiles"         => $profiles,
        ];`;
const newPollResult = `$result = [
            "sensor_readings"   => $this->latestReading($profiles),
            "active_sensors"    => $this->activeSensors($profiles),
            "nodes"             => $this->sanitizeResult(DB::table("nodes")->orderBy("id")->get()),
            "telegram_bot_state"=> $this->sanitizeResult(DB::table("telegram_bot_state")->orderBy("state_key")->get()),
            "active_alerts"     => $this->getAlerts(),
            "signal_stats"      => $this->getSignalStats($range),
            "comm_health"      => $this->getCommHealth(),
            "profiles"          => $profiles,
        ];`;
content = content.replace(oldPollResult, newPollResult);

fs.writeFileSync(file, content, 'utf8');
console.log('DashboardController.php patched successfully');