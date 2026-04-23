<?php

function sensorDefinitions(): array
{
    return [
        'temperature' => [
            'label' => 'Temperature',
            'table' => 'temperature_data',
            'unit' => 'C',
            'family' => 'DHT22',
            'accent' => '#fce442',
            'icon' => 'thermostat',
            'threshold_min' => 22,
            'threshold_max' => 34,
            'calibration_a' => 1,
            'calibration_b' => 0,
            'calibration_c' => 0,
            'calibration_labels' => ['Scale', 'Offset', 'Reserve'],
        ],
        'humidity' => [
            'label' => 'Humidity',
            'table' => 'humidity_data',
            'unit' => '%',
            'family' => 'DHT22',
            'accent' => '#00fbfb',
            'icon' => 'droplets',
            'threshold_min' => 45,
            'threshold_max' => 85,
            'calibration_a' => 1,
            'calibration_b' => 0,
            'calibration_c' => 0,
            'calibration_labels' => ['Scale', 'Offset', 'Reserve'],
        ],
        'waterTemp' => [
            'label' => 'Water Temp',
            'table' => 'water_temp_data',
            'unit' => 'C',
            'family' => 'Water Temperature',
            'accent' => '#1e95f2',
            'icon' => 'waves',
            'threshold_min' => 20,
            'threshold_max' => 30,
            'calibration_a' => 1,
            'calibration_b' => 0,
            'calibration_c' => 0,
            'calibration_labels' => ['Scale', 'Offset', 'Reserve'],
        ],
        'ph' => [
            'label' => 'pH',
            'table' => 'ph_data',
            'unit' => 'pH',
            'family' => 'Water Quality',
            'accent' => '#9ecaff',
            'icon' => 'flask',
            'threshold_min' => 5.8,
            'threshold_max' => 7.2,
            'calibration_a' => 1,
            'calibration_b' => 0,
            'calibration_c' => 0,
            'calibration_labels' => ['Slope', 'Offset', 'Reserve'],
        ],
        'tds' => [
            'label' => 'TDS',
            'table' => 'tds_data',
            'unit' => 'ppm',
            'family' => 'Water Quality',
            'accent' => '#5cf2b5',
            'icon' => 'sparkles',
            'threshold_min' => 300,
            'threshold_max' => 1200,
            'calibration_a' => 1,
            'calibration_b' => 0,
            'calibration_c' => 0,
            'calibration_labels' => ['Multiplier', 'Offset', 'Reserve'],
        ],
        'turbidity' => [
            'label' => 'Turbidity',
            'table' => 'turbidity_data',
            'unit' => 'NTU',
            'family' => 'Water Quality',
            'accent' => '#ffa94d',
            'icon' => 'cloudy',
            'threshold_min' => 0,
            'threshold_max' => 120,
            'calibration_a' => 1,
            'calibration_b' => 0,
            'calibration_c' => 0,
            'calibration_labels' => ['Scale', 'Offset', 'Clear Ref'],
        ],
        'rain' => [
            'label' => 'Rain',
            'table' => 'rain_data',
            'unit' => 'state',
            'family' => 'Environment',
            'accent' => '#ff7aa2',
            'icon' => 'rain',
            'threshold_min' => null,
            'threshold_max' => null,
            'calibration_a' => 1,
            'calibration_b' => 0,
            'calibration_c' => 0,
            'calibration_labels' => ['Scale', 'Offset', 'Reserve'],
        ],
    ];
}

function ensureDashboardTables(PDO $pdo): void
{
    $pdo->exec("
        CREATE TABLE IF NOT EXISTS dashboard_settings (
            setting_key VARCHAR(100) PRIMARY KEY,
            setting_value TEXT NOT NULL,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
        )
    ");

    $pdo->exec("
        CREATE TABLE IF NOT EXISTS sensor_profiles (
            id INT AUTO_INCREMENT PRIMARY KEY,
            node_id INT NOT NULL,
            sensor_key VARCHAR(50) NOT NULL,
            threshold_min DECIMAL(12,4) NULL,
            threshold_max DECIMAL(12,4) NULL,
            calibration_a DECIMAL(12,4) NOT NULL DEFAULT 1.0000,
            calibration_b DECIMAL(12,4) NOT NULL DEFAULT 0.0000,
            calibration_c DECIMAL(12,4) NOT NULL DEFAULT 0.0000,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            UNIQUE KEY uniq_node_sensor (node_id, sensor_key),
            INDEX idx_sensor_profiles_node (node_id),
            CONSTRAINT fk_sensor_profiles_node FOREIGN KEY (node_id) REFERENCES nodes(id) ON DELETE CASCADE
        )
    ");
}

function getDashboardSettings(PDO $pdo): array
{
    ensureDashboardTables($pdo);

    $defaults = [
        'retention_policy' => 'keep_forever',
        'export_format' => 'excel',
        'default_range' => '24h',
        'alert_notifications' => 'dashboard_only',
    ];

    $stmt = $pdo->query("
        SELECT setting_key, setting_value
        FROM dashboard_settings
    ");

    $settings = $defaults;
    foreach ($stmt->fetchAll() as $row) {
        $settings[$row['setting_key']] = $row['setting_value'];
    }

    return $settings;
}

function saveDashboardSettings(PDO $pdo, array $settings): array
{
    ensureDashboardTables($pdo);

    $allowed = ['retention_policy', 'export_format', 'default_range', 'alert_notifications'];
    $stmt = $pdo->prepare("
        INSERT INTO dashboard_settings (setting_key, setting_value)
        VALUES (:setting_key, :setting_value)
        ON DUPLICATE KEY UPDATE setting_value = VALUES(setting_value)
    ");

    foreach ($settings as $key => $value) {
        if (!in_array($key, $allowed, true)) {
            continue;
        }

        $stmt->execute([
            ':setting_key' => $key,
            ':setting_value' => (string) $value,
        ]);
    }

    return getDashboardSettings($pdo);
}

function getSensorProfiles(PDO $pdo, int $nodeId): array
{
    ensureDashboardTables($pdo);

    $definitions = sensorDefinitions();
    $stmt = $pdo->prepare("
        SELECT sensor_key, threshold_min, threshold_max, calibration_a, calibration_b, calibration_c, updated_at
        FROM sensor_profiles
        WHERE node_id = :node_id
    ");
    $stmt->execute([':node_id' => $nodeId]);

    $stored = [];
    foreach ($stmt->fetchAll() as $row) {
        $stored[$row['sensor_key']] = $row;
    }

    $profiles = [];
    foreach ($definitions as $sensorKey => $meta) {
        $row = $stored[$sensorKey] ?? null;
        $profiles[$sensorKey] = [
            'sensor_key' => $sensorKey,
            'label' => $meta['label'],
            'unit' => $meta['unit'],
            'family' => $meta['family'],
            'accent' => $meta['accent'],
            'threshold_min' => $row ? nullableFloat($row['threshold_min']) : $meta['threshold_min'],
            'threshold_max' => $row ? nullableFloat($row['threshold_max']) : $meta['threshold_max'],
            'calibration_a' => $row ? (float) $row['calibration_a'] : (float) $meta['calibration_a'],
            'calibration_b' => $row ? (float) $row['calibration_b'] : (float) $meta['calibration_b'],
            'calibration_c' => $row ? (float) $row['calibration_c'] : (float) $meta['calibration_c'],
            'calibration_labels' => $meta['calibration_labels'],
            'updated_at' => $row['updated_at'] ?? null,
        ];
    }

    return $profiles;
}

function saveSensorProfiles(PDO $pdo, int $nodeId, array $profiles): array
{
    ensureDashboardTables($pdo);

    $definitions = sensorDefinitions();
    $stmt = $pdo->prepare("
        INSERT INTO sensor_profiles (
            node_id, sensor_key, threshold_min, threshold_max, calibration_a, calibration_b, calibration_c
        ) VALUES (
            :node_id, :sensor_key, :threshold_min, :threshold_max, :calibration_a, :calibration_b, :calibration_c
        )
        ON DUPLICATE KEY UPDATE
            threshold_min = VALUES(threshold_min),
            threshold_max = VALUES(threshold_max),
            calibration_a = VALUES(calibration_a),
            calibration_b = VALUES(calibration_b),
            calibration_c = VALUES(calibration_c)
    ");

    foreach ($profiles as $sensorKey => $profile) {
        if (!isset($definitions[$sensorKey])) {
            continue;
        }

        $stmt->execute([
            ':node_id' => $nodeId,
            ':sensor_key' => $sensorKey,
            ':threshold_min' => normalizeNullableNumber($profile['threshold_min'] ?? null),
            ':threshold_max' => normalizeNullableNumber($profile['threshold_max'] ?? null),
            ':calibration_a' => normalizeNumber($profile['calibration_a'] ?? $definitions[$sensorKey]['calibration_a']),
            ':calibration_b' => normalizeNumber($profile['calibration_b'] ?? $definitions[$sensorKey]['calibration_b']),
            ':calibration_c' => normalizeNumber($profile['calibration_c'] ?? $definitions[$sensorKey]['calibration_c']),
        ]);
    }

    return getSensorProfiles($pdo, $nodeId);
}

function exportConfigSnapshot(PDO $pdo, int $nodeId): array
{
    return [
        'exported_at' => date('Y-m-d H:i:s'),
        'node_id' => $nodeId,
        'settings' => getDashboardSettings($pdo),
        'profiles' => getSensorProfiles($pdo, $nodeId),
    ];
}

function importConfigSnapshot(PDO $pdo, int $nodeId, array $snapshot): array
{
    if (isset($snapshot['settings']) && is_array($snapshot['settings'])) {
        saveDashboardSettings($pdo, $snapshot['settings']);
    }

    if (isset($snapshot['profiles']) && is_array($snapshot['profiles'])) {
        saveSensorProfiles($pdo, $nodeId, $snapshot['profiles']);
    }

    return exportConfigSnapshot($pdo, $nodeId);
}

function saveNodeLocation(PDO $pdo, int $nodeId, ?float $latitude, ?float $longitude, ?float $distance): array
{
    $stmt = $pdo->prepare("
        UPDATE nodes
        SET latitude = :latitude,
            longitude = :longitude,
            distance_m = :distance,
            updated_at = CURRENT_TIMESTAMP
        WHERE id = :node_id
    ");
    $stmt->execute([
        ':node_id' => $nodeId,
        ':latitude' => $latitude,
        ':longitude' => $longitude,
        ':distance' => $distance,
    ]);

    $fetchStmt = $pdo->prepare("SELECT id, name, location, latitude, longitude, distance_m FROM nodes WHERE id = :node_id");
    $fetchStmt->execute([':node_id' => $nodeId]);
    return $fetchStmt->fetch() ?: ['id' => $nodeId];
}

function normalizeNumber($value): float
{
    return (float) (is_numeric($value) ? $value : 0);
}

function normalizeNullableNumber($value): ?float
{
    if ($value === '' || $value === null) {
        return null;
    }

    return is_numeric($value) ? (float) $value : null;
}

function nullableFloat($value): ?float
{
    return $value === null ? null : (float) $value;
}

function ensureAlertsTable(PDO $pdo): void
{
    $pdo->exec("
        CREATE TABLE IF NOT EXISTS alerts (
            id INT AUTO_INCREMENT PRIMARY KEY,
            node_id INT NOT NULL,
            sensor_key VARCHAR(50) NOT NULL,
            label VARCHAR(100) NOT NULL,
            message TEXT NOT NULL,
            severity VARCHAR(20) NOT NULL DEFAULT 'warning',
            status VARCHAR(20) NOT NULL DEFAULT 'active',
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            acknowledged_at TIMESTAMP NULL,
            resolved_at TIMESTAMP NULL,
            INDEX idx_alerts_node_created (node_id, created_at),
            INDEX idx_alerts_status (status)
        )
    ");
}

function getActiveAlerts(PDO $pdo, int $nodeId): array
{
    ensureAlertsTable($pdo);
    $stmt = $pdo->prepare("
        SELECT id, sensor_key, label, message, severity, status,
               created_at, acknowledged_at, resolved_at
        FROM alerts
        WHERE node_id = :node_id
        ORDER BY
            CASE status
                WHEN 'active'   THEN 1
                WHEN 'acknowledged' THEN 2
                WHEN 'resolved'    THEN 3
            END,
            severity DESC,
            created_at DESC
    ");
    $stmt->execute([':node_id' => $nodeId]);
    return $stmt->fetchAll();
}

function acknowledgeAlert(PDO $pdo, int $nodeId, string $sensorKey): array
{
    ensureAlertsTable($pdo);
    $stmt = $pdo->prepare("
        UPDATE alerts
        SET status = 'acknowledged', acknowledged_at = CURRENT_TIMESTAMP
        WHERE node_id = :node_id
          AND sensor_key = :sensor_key
          AND status = 'active'
        ORDER BY created_at DESC
        LIMIT 1
    ");
    $stmt->execute([
        ':node_id' => $nodeId,
        ':sensor_key' => $sensorKey,
    ]);
    return ['affected' => $stmt->rowCount()];
}

function resolveAlert(PDO $pdo, int $nodeId, string $sensorKey): array
{
    ensureAlertsTable($pdo);
    $stmt = $pdo->prepare("
        UPDATE alerts
        SET status = 'resolved', resolved_at = CURRENT_TIMESTAMP
        WHERE node_id = :node_id
          AND sensor_key = :sensor_key
          AND status IN ('active', 'acknowledged')
        ORDER BY created_at DESC
        LIMIT 1
    ");
    $stmt->execute([
        ':node_id' => $nodeId,
        ':sensor_key' => $sensorKey,
    ]);
    return ['affected' => $stmt->rowCount()];
}

function syncAlertsFromReadings(PDO $pdo, int $nodeId, array $alerts, array $profiles): int
{
    ensureAlertsTable($pdo);

    $insertStmt = $pdo->prepare("
        INSERT INTO alerts (node_id, sensor_key, label, message, severity)
        VALUES (:node_id, :sensor_key, :label, :message, :severity)
    ");

    $count = 0;
    foreach ($alerts as $alert) {
        // Only insert critical / warning that isn't already active
        if ($alert['severity'] === 'critical' || $alert['severity'] === 'warning') {
            $check = $pdo->prepare("
                SELECT 1 FROM alerts
                WHERE node_id = :node_id
                  AND sensor_key = :sensor_key
                  AND status IN ('active', 'acknowledged')
                LIMIT 1
            ");
            $check->execute([
                ':node_id' => $nodeId,
                ':sensor_key' => $alert['sensor_key'],
            ]);
            if (!$check->fetchColumn()) {
                $insertStmt->execute([
                    ':node_id' => $nodeId,
                    ':sensor_key' => $alert['sensor_key'],
                    ':label' => $alert['label'],
                    ':message' => $alert['message'],
                    ':severity' => $alert['severity'],
                ]);
                $count++;
            }
        }
    }
    return $count;
}

function ensureCommunicationHealthTable(PDO $pdo): void
{
    $pdo->exec("
        CREATE TABLE IF NOT EXISTS communication_health (
            id INT AUTO_INCREMENT PRIMARY KEY,
            node_id INT NOT NULL,
            metric_key VARCHAR(50) NOT NULL,
            metric_value VARCHAR(255) NOT NULL,
            recorded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            INDEX idx_comm_health_node_recorded (node_id, recorded_at)
        )
    ");
}

function getCommunicationHealth(PDO $pdo, int $nodeId): array
{
    ensureCommunicationHealthTable($pdo);
    $stmt = $pdo->prepare("
        SELECT metric_key, metric_value, recorded_at
        FROM communication_health
        WHERE node_id = :node_id
        ORDER BY recorded_at DESC
        LIMIT 50
    ");
    $stmt->execute([':node_id' => $nodeId]);
    return $stmt->fetchAll();
}

function computeCommunicationHealth(PDO $pdo, int $nodeId, string $rangeStart): array
{
    $health = [
        'delivery_rate' => null,
        'total_expected' => 0,
        'total_received' => 0,
        'sequence_gaps' => 0,
        'freshness_seconds' => null,
    ];

    $rangeEnd = time();
    $rangeSeconds = $rangeEnd - strtotime($rangeStart);

    $receivedStmt = $pdo->prepare("
        SELECT COUNT(*) AS total,
               MIN(created_at) AS first_at,
               MAX(created_at) AS last_at,
               MIN(sequence_number) AS min_seq,
               MAX(sequence_number) AS max_seq
        FROM sensor_readings
        WHERE node_id = :node_id
          AND created_at >= :range_start
    ");
    $receivedStmt->execute([
        ':node_id' => $nodeId,
        ':range_start' => $rangeStart,
    ]);
    $received = $receivedStmt->fetch();

    $totalReceived = (int) ($received['total'] ?? 0);
    $health['total_received'] = $totalReceived;

    $criticalStmt = $pdo->prepare("
        SELECT COUNT(*) FROM sensor_readings
        WHERE node_id = :node_id
          AND created_at >= :range_start
          AND priority_level = 'HIGH'
    ");
    $criticalStmt->execute([
        ':node_id' => $nodeId,
        ':range_start' => $rangeStart,
    ]);
    $criticalCount = (int) $criticalStmt->fetchColumn();

    $totalExpected = $criticalCount + max(1, (int) ceil(($rangeSeconds - ($criticalCount * 60)) / 900));
    $health['total_expected'] = $totalExpected;

    if ($totalExpected > 0) {
        $health['delivery_rate'] = round(($totalReceived / $totalExpected) * 100, 1);
    }

    if ($received['min_seq'] !== null && $received['max_seq'] !== null) {
        $expectedSeqCount = (int) $received['max_seq'] - (int) $received['min_seq'] + 1;
        $actualSeqCount = (int) $received['total'];
        $health['sequence_gaps'] = max(0, $expectedSeqCount - $actualSeqCount);
    }

    if ($received['last_at'] !== null) {
        $health['freshness_seconds'] = (int) (time() - strtotime($received['last_at']));
    }

    return $health;
}
