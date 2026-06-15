<?php
/**
 * SmartPonic Dashboard Data API
 *
 * Serves all dashboard data as JSON for the frontend.
 *
 * Query params:
 *   node_id  - (int) Node ID to focus on (default: first node)
 *   range    - (str) Time range: 1h, 6h, 24h, 7d, 30d (default: 24h)
 *
 * Response: JSON with nodes, summary, analytics, profiles, alerts,
 *           communication_health, signal_history, sensor_history.
 */

require_once __DIR__ . "/db.php";

header("Content-Type: application/json; charset=utf-8");
header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Methods: GET, OPTIONS");
header("Access-Control-Allow-Headers: Content-Type");

if ($_SERVER["REQUEST_METHOD"] === "OPTIONS") {
    http_response_code(204);
    exit;
}

if ($_SERVER["REQUEST_METHOD"] !== "GET") {
    http_response_code(405);
    echo json_encode(["error" => "Method not allowed"]);
    exit;
}

// ── Parse inputs ──────────────────────────────────────────────────────────
$nodeId   = isset($_GET["node_id"]) ? (int)$_GET["node_id"] : 0;
$range    = $_GET["range"] ?? "24h";

$allowedRanges = ["1h","6h","24h","7d","30d"];
if (!in_array($range, $allowedRanges, true)) {
    $range = "24h";
}

$rangeMap = [
    "1h"  => "1 HOUR",
    "6h"  => "6 HOUR",
    "24h" => "24 HOUR",
    "7d"  => "7 DAY",
    "30d" => "30 DAY",
];
$rangeSql = $rangeMap[$range];

$tz = date_default_timezone_get() ?: "Asia/Kuala_Lumpur";
$now = date("Y-m-d H:i:s");
$rangeStart = date("Y-m-d H:i:s", strtotime("-{$rangeSql}"));

try {
    $db = getDb();

    // ── Nodes ─────────────────────────────────────────────────────────
    $nodes = $db->query(
        "SELECT id, hardware_id, name, location,
                UNIX_TIMESTAMP(first_seen) as first_seen_ts,
                UNIX_TIMESTAMP(last_seen)  as last_seen_ts
         FROM nodes ORDER BY id ASC"
    )->fetchAll();

    $nodeList = [];
    foreach ($nodes as $n) {
        $nodeList[] = [
            "id"          => (int)$n["id"],
            "hardware_id" => $n["hardware_id"],
            "name"        => $n["name"] ?: ("Node " . substr($n["hardware_id"] ?? "??", 0, 6)),
            "location"    => $n["location"] ?? "",
            "latitude"    => null,
            "longitude"   => null,
        ];
    }

    // Auto-select node if not specified
    if ($nodeId <= 0 && !empty($nodeList)) {
        $nodeId = $nodeList[0]["id"];
    }

    $currentNode = null;
    foreach ($nodeList as $n) {
        if ($n["id"] === $nodeId) {
            $currentNode = $n;
            break;
        }
    }
    if (!$currentNode && !empty($nodeList)) {
        $currentNode = $nodeList[0];
        $nodeId = $currentNode["id"];
    }

    $hwId = $currentNode["hardware_id"] ?? "";

    // ── Summary ───────────────────────────────────────────────────────
    $summary = [
        "latest_reading_id"     => null,
        "latest_reading_at"     => null,
        "rssi"                  => null,
        "snr"                   => null,
        "priority_level"        => "NORMAL",
        "report_mode"           => "NORMAL",
        "sequence_number"       => null,
        "latitude"              => null,
        "longitude"             => null,
        "distance_m"            => null,
        "active_sensor_count"   => 0,
        "configured_sensor_count" => 0,
        "node_status"           => ["state" => "offline", "label" => "Offline", "minutes_since" => null],
        "signal_quality"        => ["label" => "Unknown", "state" => "unknown"],
    ];

    if ($hwId) {
        $stmt = $db->prepare(
            "SELECT id, rssi, snr, created_at
             FROM sensor_readings
             WHERE hardware_id = ?
             ORDER BY id DESC LIMIT 1"
        );
        $stmt->execute([$hwId]);
        $lastReading = $stmt->fetch();

        if ($lastReading) {
            $lastTs = strtotime($lastReading["created_at"]);
            $minutesSince = (int)((time() - $lastTs) / 60);

            $signalLabel = "Unknown";
            $signalState = "unknown";
            $rssi = (int)$lastReading["rssi"];
            if ($rssi > -70)      { $signalLabel = "Excellent"; $signalState = "excellent"; }
            elseif ($rssi > -85)  { $signalLabel = "Good";      $signalState = "good"; }
            elseif ($rssi > -100) { $signalLabel = "Fair";      $signalState = "warn"; }
            else                  { $signalLabel = "Poor";      $signalState = "bad"; }

            $nodeState = ($minutesSince <= 5) ? "online" : "offline";
            $nodeLabel = ($minutesSince <= 5) ? "Online" : "Offline";

            // Count active sensors in latest reading
            $stmt2 = $db->prepare(
                "SELECT COUNT(DISTINCT sensor) as cnt FROM sensor_data WHERE reading_id = ?"
            );
            $stmt2->execute([(int)$lastReading["id"]]);
            $activeCnt = (int)$stmt2->fetch()["cnt"];

            $summary = [
                "latest_reading_id"     => (int)$lastReading["id"],
                "latest_reading_at"     => $lastReading["created_at"],
                "rssi"                  => $rssi,
                "snr"                   => (float)$lastReading["snr"],
                "priority_level"        => "HIGH",
                "report_mode"           => "CRITICAL",
                "sequence_number"       => null,
                "latitude"              => null,
                "longitude"             => null,
                "distance_m"            => null,
                "active_sensor_count"   => $activeCnt,
                "configured_sensor_count" => 7,
                "node_status" => [
                    "state"        => $nodeState,
                    "label"        => $nodeLabel,
                    "minutes_since"=> $nodeState === "online" ? 0 : $minutesSince,
                ],
                "signal_quality" => [
                    "label" => $signalLabel,
                    "state" => $signalState,
                ],
            ];
        }
    }

    // ── Analytics ─────────────────────────────────────────────────────
    $analytics = [
        "critical_event_count" => 0,
        "priority_counts"      => ["LOW" => 0, "MEDIUM" => 0, "HIGH" => 0],
        "priority_percentages" => ["LOW" => 0, "MEDIUM" => 0, "HIGH" => 0],
        "sensor_stats"         => [],
        "signal_stats"         => ["min_rssi" => null, "max_rssi" => null, "avg_rssi" => null,
                                   "min_snr" => null, "max_snr" => null, "avg_snr" => null,
                                   "packet_count" => 0],
    ];

    $sensorKeys = ["temperature","humidity","waterTemp","ph","tds","turbidity","rain"];

    if ($hwId) {
        // Signal stats
        $stmt = $db->prepare(
            "SELECT COUNT(*) as cnt, MIN(rssi) as min_r, MAX(rssi) as max_r,
                    AVG(rssi) as avg_r, MIN(snr) as min_s, MAX(snr) as max_s,
                    AVG(snr) as avg_s
             FROM sensor_readings
             WHERE hardware_id = ? AND created_at >= ?"
        );
        $stmt->execute([$hwId, $rangeStart]);
        $sigStats = $stmt->fetch();
        if ($sigStats && $sigStats["cnt"] > 0) {
            $analytics["signal_stats"] = [
                "min_rssi"     => (int)$sigStats["min_r"],
                "max_rssi"     => (int)$sigStats["max_r"],
                "avg_rssi"     => round((float)$sigStats["avg_r"], 1),
                "min_snr"      => round((float)$sigStats["min_s"], 1),
                "max_snr"      => round((float)$sigStats["max_s"], 1),
                "avg_snr"      => round((float)$sigStats["avg_s"], 1),
                "packet_count" => (int)$sigStats["cnt"],
            ];
            $analytics["critical_event_count"] = (int)$sigStats["cnt"];
            $analytics["priority_counts"]["HIGH"] = (int)$sigStats["cnt"];
            $analytics["priority_percentages"]["HIGH"] = 100;
        }

        // Per-sensor stats: we query sensor_data joined to sensor_readings
        foreach ($sensorKeys as $sk) {
            $sensorLabel = match($sk) {
                "temperature" => "Temperature",
                "humidity"    => "Humidity",
                "waterTemp"   => "WaterTemp",
                "ph"          => "pH",
                "tds"         => "TDS",
                "turbidity"   => "Turbidity",
                "rain"        => "Rain",
                default       => $sk,
            };

            $stmt = $db->prepare(
                "SELECT MIN(CAST(sd.value AS DECIMAL(10,2))) as vmin,
                        MAX(CAST(sd.value AS DECIMAL(10,2))) as vmax,
                        AVG(CAST(sd.value AS DECIMAL(10,2))) as vavg
                 FROM sensor_data sd
                 JOIN sensor_readings sr ON sd.reading_id = sr.id
                 WHERE sr.hardware_id = ? AND sd.sensor = ? AND sr.created_at >= ?
                   AND sd.value REGEXP '^-?[0-9]+(\\.[0-9]+)?$'"
            );
            $stmt->execute([$hwId, $sensorLabel, $rangeStart]);
            $row = $stmt->fetch();
            $analytics["sensor_stats"][$sk] = [
                "min" => $row && $row["vmin"] !== null ? round((float)$row["vmin"], 2) : null,
                "max" => $row && $row["vmax"] !== null ? round((float)$row["vmax"], 2) : null,
                "avg" => $row && $row["vavg"] !== null ? round((float)$row["vavg"], 2) : null,
            ];
        }
    }

    // ── Profiles ──────────────────────────────────────────────────────
    $profiles = getSensorProfiles($db);

    // ── Configured sensors ────────────────────────────────────────────
    $configuredSensors = [];
    if ($hwId) {
        $stmt = $db->prepare(
            "SELECT DISTINCT sensor FROM sensor_data sd
             JOIN sensor_readings sr ON sd.reading_id = sr.id
             WHERE sr.hardware_id = ? AND sr.created_at >= ?
             ORDER BY sensor"
        );
        $stmt->execute([$hwId, $rangeStart]);
        while ($row = $stmt->fetch()) {
            $sn = $row["sensor"];
            $key = match(strtolower($sn)) {
                "temperature" => "temperature",
                "humidity"    => "humidity",
                "watertemp"   => "waterTemp",
                "ph"          => "ph",
                "tds"         => "tds",
                "turbidity"   => "turbidity",
                "rain"        => "rain",
                default       => strtolower($sn),
            };
            $configuredSensors[] = $key;
        }
    }

    // ── Alerts ────────────────────────────────────────────────────────
    $alerts = [];
    $alertHistory = [];

    if ($hwId) {
        // Active alerts
        $stmt = $db->prepare(
            "SELECT sensor_key, severity, message, created_at
             FROM alerts
             WHERE hardware_id = ? AND status = 'active'
             ORDER BY created_at DESC"
        );
        $stmt->execute([$hwId]);
        while ($row = $stmt->fetch()) {
            $p = $profiles[$row["sensor_key"]] ?? null;
            $alerts[] = [
                "sensor_key" => $row["sensor_key"],
                "label"      => $p["label"] ?? $row["sensor_key"],
                "severity"   => $row["severity"],
                "message"    => $row["message"],
                "created_at" => $row["created_at"],
                "accent"     => $p["accent"] ?? "#9ecaff",
            ];
        }

        // Alert history (resolved)
        $stmt = $db->prepare(
            "SELECT sensor_key, severity, message, status, created_at, updated_at
             FROM alerts
             WHERE hardware_id = ? AND status IN ('acknowledged','resolved')
             ORDER BY updated_at DESC LIMIT 20"
        );
        $stmt->execute([$hwId]);
        while ($row = $stmt->fetch()) {
            $p = $profiles[$row["sensor_key"]] ?? null;
            $alertHistory[] = [
                "sensor_key" => $row["sensor_key"],
                "label"      => $p["label"] ?? $row["sensor_key"],
                "severity"   => $row["severity"],
                "message"    => $row["message"],
                "status"     => $row["status"],
                "created_at" => $row["created_at"],
                "updated_at" => $row["updated_at"],
                "accent"     => $p["accent"] ?? "#9ecaff",
            ];
        }
    }

    // Generate threshold-based alerts if no alerts table entries exist
    if (empty($alerts) && $hwId && !empty($summary["latest_reading_id"])) {
        $stmt = $db->prepare(
            "SELECT sd.sensor, sd.value
             FROM sensor_data sd
             WHERE sd.reading_id = ?"
        );
        $stmt->execute([$summary["latest_reading_id"]]);
        while ($row = $stmt->fetch()) {
            $sensorName = $row["sensor"];
            $value = $row["value"];
            if (!is_numeric($value)) continue;

            $sensorKey = match(strtolower($sensorName)) {
                "temperature" => "temperature",
                "humidity"    => "humidity",
                "watertemp"   => "waterTemp",
                "ph"          => "ph",
                "tds"         => "tds",
                "turbidity"   => "turbidity",
                default       => null,
            };
            if (!$sensorKey || !isset($profiles[$sensorKey])) continue;

            $p = $profiles[$sensorKey];
            $val = (float)$value;

            if ($p["threshold_min"] !== null && $val < $p["threshold_min"]) {
                $alerts[] = [
                    "sensor_key" => $sensorKey,
                    "label"      => $p["label"],
                    "severity"   => "warning",
                    "message"    => "{$p["label"]} is low at {$val} {$p["unit"]}",
                    "created_at" => $summary["latest_reading_at"],
                    "accent"     => $p["accent"],
                ];
            } elseif ($p["threshold_max"] !== null && $val > $p["threshold_max"]) {
                $alerts[] = [
                    "sensor_key" => $sensorKey,
                    "label"      => $p["label"],
                    "severity"   => "warning",
                    "message"    => "{$p["label"]} is high at {$val} {$p["unit"]}",
                    "created_at" => $summary["latest_reading_at"],
                    "accent"     => $p["accent"],
                ];
            }
        }
    }

    // ── Communication health ──────────────────────────────────────────
    $commHealth = [
        "delivery_rate"     => 100.0,
        "total_expected"    => 0,
        "total_received"    => 0,
        "sequence_gaps"     => 0,
        "freshness_seconds" => 0,
    ];

    if ($hwId) {
        $stmt = $db->prepare(
            "SELECT delivery_rate, total_expected, total_received,
                    sequence_gaps, freshness_seconds
             FROM communication_health WHERE hardware_id = ?"
        );
        $stmt->execute([$hwId]);
        $ch = $stmt->fetch();
        if ($ch) {
            $commHealth = [
                "delivery_rate"     => round((float)$ch["delivery_rate"], 1),
                "total_expected"    => (int)$ch["total_expected"],
                "total_received"    => (int)$ch["total_received"],
                "sequence_gaps"     => (int)$ch["sequence_gaps"],
                "freshness_seconds" => (int)$ch["freshness_seconds"],
            ];
        } else {
            // Compute from readings
            $stmt = $db->prepare(
                "SELECT COUNT(*) as cnt FROM sensor_readings WHERE hardware_id = ? AND created_at >= ?"
            );
            $stmt->execute([$hwId, $rangeStart]);
            $row = $stmt->fetch();
            $commHealth["total_received"] = (int)$row["cnt"];
            $commHealth["total_expected"] = (int)$row["cnt"]; // approximate

            if ($summary["latest_reading_at"]) {
                $commHealth["freshness_seconds"] = max(0, time() - strtotime($summary["latest_reading_at"]));
            }
        }
    }

    // ── Signal history ────────────────────────────────────────────────
    $signalHistory = [];
    if ($hwId) {
        $stmt = $db->prepare(
            "SELECT id, rssi, snr, created_at
             FROM sensor_readings
             WHERE hardware_id = ? AND created_at >= ?
             ORDER BY id DESC LIMIT 100"
        );
        $stmt->execute([$hwId, $rangeStart]);
        while ($row = $stmt->fetch()) {
            $signalHistory[] = [
                "id"              => (int)$row["id"],
                "rssi"            => (int)$row["rssi"],
                "snr"             => round((float)$row["snr"], 2),
                "priority_level"  => "HIGH",
                "report_mode"     => "CRITICAL",
                "sequence_number" => null,
                "latitude"        => null,
                "longitude"       => null,
                "distance_m"      => null,
                "created_at"      => $row["created_at"],
            ];
        }
    }

    // ── Sensor history ────────────────────────────────────────────────
    $sensorHistory = [];
    if ($hwId) {
        $stmt = $db->prepare(
            "SELECT sd.sensor, sd.pin, sd.value, sr.created_at
             FROM sensor_data sd
             JOIN sensor_readings sr ON sd.reading_id = sr.id
             WHERE sr.hardware_id = ? AND sr.created_at >= ?
             ORDER BY sr.id DESC LIMIT 200"
        );
        $stmt->execute([$hwId, $rangeStart]);
        while ($row = $stmt->fetch()) {
            $sn = $row["sensor"];
            $table = match(strtolower($sn)) {
                "temperature" => "temperature_data",
                "humidity"    => "humidity_data",
                "watertemp"   => "water_temp_data",
                "ph"          => "ph_data",
                "tds"         => "tds_data",
                "turbidity"   => "turbidity_data",
                "rain"        => "rain_data",
                default       => "sensor_data",
            };
            $sensorHistory[] = [
                "sensor"     => $sn,
                "table"      => $table,
                "pin"        => (int)$row["pin"],
                "value"      => $row["value"],
                "created_at" => $row["created_at"],
            ];
        }
    }

    // ── Dashboard settings ────────────────────────────────────────────
    $settings = [
        "retention_policy"   => "keep_forever",
        "export_format"      => "excel",
        "default_range"      => "24h",
        "alert_notifications" => "dashboard_only",
    ];
    $stmt = $db->query("SELECT setting_key, setting_value FROM dashboard_settings");
    while ($row = $stmt->fetch()) {
        $settings[$row["setting_key"]] = $row["setting_value"];
    }

    // ── Assemble response ─────────────────────────────────────────────
    $response = [
        "status"         => "success",
        "generated_at"   => $now,
        "timezone"       => $tz,
        "selected_range" => $range,
        "range_start"    => $rangeStart,
        "retention_policy"=> $settings["retention_policy"] ?? "keep_forever",
        "settings"       => $settings,
        "nodes"          => $nodeList,
        "node"           => $currentNode,
        "summary"        => $summary,
        "analytics"      => $analytics,
        "configured_sensors" => $configuredSensors,
        "profiles"       => $profiles,
        "alerts"         => $alerts,
        "alert_history"  => $alertHistory,
        "communication_health" => $commHealth,
        "signal_history" => $signalHistory,
        "sensor_history" => $sensorHistory,
    ];

    echo json_encode($response, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES);

} catch (PDOException $e) {
    http_response_code(500);
    echo json_encode(["status" => "error", "message" => "Database error"]);
    error_log("dashboard_data.php DB error: " . $e->getMessage());
} catch (Throwable $e) {
    http_response_code(500);
    echo json_encode(["status" => "error", "message" => "Internal server error"]);
    error_log("dashboard_data.php error: " . $e->getMessage());
}

// ── Helpers ───────────────────────────────────────────────────────────────

function getSensorProfiles(PDO $db): array {
    $defaults = [
        "temperature" => ["sensor_key" => "temperature", "label" => "Temperature", "unit" => "C",
            "family" => "DHT22", "accent" => "#fce442", "threshold_min" => 22, "threshold_max" => 34,
            "calibration_a" => 1, "calibration_b" => 0, "calibration_c" => 0,
            "calibration_labels" => ["Scale","Offset","Reserve"]],
        "humidity"    => ["sensor_key" => "humidity",    "label" => "Humidity",    "unit" => "%",
            "family" => "DHT22", "accent" => "#00fbfb", "threshold_min" => 45, "threshold_max" => 85,
            "calibration_a" => 1, "calibration_b" => 0, "calibration_c" => 0,
            "calibration_labels" => ["Scale","Offset","Reserve"]],
        "waterTemp"   => ["sensor_key" => "waterTemp",   "label" => "Water Temp",  "unit" => "C",
            "family" => "Water Temperature", "accent" => "#1e95f2", "threshold_min" => 20, "threshold_max" => 30,
            "calibration_a" => 1, "calibration_b" => 0, "calibration_c" => 0,
            "calibration_labels" => ["Scale","Offset","Reserve"]],
        "ph"          => ["sensor_key" => "ph",          "label" => "pH",           "unit" => "pH",
            "family" => "Water Quality", "accent" => "#9ecaff", "threshold_min" => 5.8, "threshold_max" => 7.2,
            "calibration_a" => 1, "calibration_b" => 0, "calibration_c" => 0,
            "calibration_labels" => ["Slope","Offset","Reserve"]],
        "tds"         => ["sensor_key" => "tds",         "label" => "TDS",          "unit" => "ppm",
            "family" => "Water Quality", "accent" => "#5cf2b5", "threshold_min" => 300, "threshold_max" => 1200,
            "calibration_a" => 1, "calibration_b" => 0, "calibration_c" => 0,
            "calibration_labels" => ["Multiplier","Offset","Reserve"]],
        "turbidity"   => ["sensor_key" => "turbidity",   "label" => "Turbidity",    "unit" => "NTU",
            "family" => "Water Quality", "accent" => "#ffa94d", "threshold_min" => 0, "threshold_max" => 120,
            "calibration_a" => 1, "calibration_b" => 0, "calibration_c" => 0,
            "calibration_labels" => ["Scale","Offset","Clear Ref"]],
        "rain"        => ["sensor_key" => "rain",        "label" => "Rain",         "unit" => "state",
            "family" => "Environment", "accent" => "#ff7aa2", "threshold_min" => null, "threshold_max" => null,
            "calibration_a" => 1, "calibration_b" => 0, "calibration_c" => 0,
            "calibration_labels" => ["Scale","Offset","Reserve"]],
    ];

    // Load from DB if sensor_profiles table exists
    try {
        $stmt = $db->query("SELECT * FROM sensor_profiles");
        while ($row = $stmt->fetch()) {
            $key = $row["sensor_key"];
            $defaults[$key] = [
                "sensor_key" => $key,
                "label"      => $row["label"],
                "unit"       => $row["unit"],
                "family"     => $row["family"] ?? "",
                "accent"     => $row["accent"] ?? "#9ecaff",
                "threshold_min" => $row["threshold_min"] !== null ? (float)$row["threshold_min"] : null,
                "threshold_max" => $row["threshold_max"] !== null ? (float)$row["threshold_max"] : null,
                "calibration_a" => (float)$row["calibration_a"],
                "calibration_b" => (float)$row["calibration_b"],
                "calibration_c" => (float)$row["calibration_c"],
                "calibration_labels" => [
                    $row["cal_label_a"] ?? "Scale",
                    $row["cal_label_b"] ?? "Offset",
                    $row["cal_label_c"] ?? "Reserve",
                ],
                "updated_at" => $row["updated_at"],
            ];
        }
    } catch (PDOException $e) {
        // Table may not exist yet; use defaults
    }

    return $defaults;
}
