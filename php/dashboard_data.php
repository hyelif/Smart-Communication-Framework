<?php

header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type');
header('Cache-Control: no-store, no-cache, must-revalidate, max-age=0');
header('Pragma: no-cache');
header('Expires: 0');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}

if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
    http_response_code(405);
    echo json_encode(['error' => 'Method not allowed']);
    exit;
}

require_once 'db.php';
require_once 'dashboard_store.php';
require_once 'data_policy.php';

date_default_timezone_set('Asia/Kuala_Lumpur');

$requestedNode = isset($_GET['node_id']) ? trim((string) $_GET['node_id']) : '1';
$historyLimit = isset($_GET['limit']) ? max(6, min(96, (int) $_GET['limit'])) : 24;
$range = isset($_GET['range']) ? trim((string) $_GET['range']) : '24h';

$rangeMap = [
    '1h' => '-1 hour',
    '6h' => '-6 hours',
    '24h' => '-24 hours',
    '7d' => '-7 days',
    '30d' => '-30 days',
];

if (!isset($rangeMap[$range])) {
    $range = '24h';
}

$rangeStart = date('Y-m-d H:i:s', strtotime($rangeMap[$range]));
$sensorConfig = sensorDefinitions();

function normalizeValue(?string $rawValue, string $sensorKey): array
{
    if ($rawValue === null) {
        return ['raw' => null, 'numeric' => null, 'display' => '--'];
    }

    $trimmed = trim($rawValue);
    if ($trimmed === '') {
        return ['raw' => $rawValue, 'numeric' => null, 'display' => '--'];
    }

    if (($sensorKey === 'temperature' || $sensorKey === 'humidity') && strtolower($trimmed) === 'nan') {
        return ['raw' => $rawValue, 'numeric' => null, 'display' => 'Sensor error'];
    }

    if ($sensorKey === 'waterTemp' && is_numeric($trimmed) && (float) $trimmed === -127.0) {
        return ['raw' => $rawValue, 'numeric' => null, 'display' => 'Sensor error'];
    }

    if ($sensorKey === 'rain') {
        $numeric = is_numeric($trimmed) ? (float) $trimmed : null;
        $display = $numeric === null ? $trimmed : ((int) $numeric === 1 ? 'Wet' : 'Dry');
        return ['raw' => $rawValue, 'numeric' => $numeric, 'display' => $display];
    }

    if (!is_numeric($trimmed)) {
        return ['raw' => $rawValue, 'numeric' => null, 'display' => $trimmed];
    }

    $numeric = round((float) $trimmed, 2);
    return [
        'raw' => $rawValue,
        'numeric' => $numeric,
        'display' => rtrim(rtrim(number_format($numeric, 2, '.', ''), '0'), '.')
    ];
}

function classifyNodeStatus(?string $latestAt): array
{
    if (!$latestAt) {
        return ['state' => 'offline', 'label' => 'Offline', 'minutes_since' => null];
    }

    $seconds = time() - strtotime($latestAt);
    $minutes = (int) floor($seconds / 60);

    if ($seconds <= 300) {
        return ['state' => 'online', 'label' => 'Online', 'minutes_since' => $minutes];
    }

    if ($seconds <= 900) {
        return ['state' => 'delayed', 'label' => 'Delayed', 'minutes_since' => $minutes];
    }

    if ($seconds <= 3600) {
        return ['state' => 'stale', 'label' => 'Stale', 'minutes_since' => $minutes];
    }

    return ['state' => 'offline', 'label' => 'Offline', 'minutes_since' => $minutes];
}

function signalQuality(?int $rssi, ?float $snr): array
{
    if ($rssi === null && $snr === null) {
        return ['label' => 'Unknown', 'state' => 'unknown'];
    }

    if ($rssi !== null && $rssi >= -90 && $snr !== null && $snr >= 7) {
        return ['label' => 'Strong', 'state' => 'good'];
    }

    if ($rssi !== null && $rssi >= -105 && $snr !== null && $snr >= 3) {
        return ['label' => 'Fair', 'state' => 'warn'];
    }

    return ['label' => 'Weak', 'state' => 'critical'];
}

function ensureSensorReadingsColumns(PDO $pdo): void
{
    $requiredColumns = [
        'priority_level' => "ALTER TABLE sensor_readings ADD COLUMN priority_level VARCHAR(20) NULL AFTER snr",
        'report_mode' => "ALTER TABLE sensor_readings ADD COLUMN report_mode VARCHAR(20) NULL AFTER priority_level",
        'sequence_number' => "ALTER TABLE sensor_readings ADD COLUMN sequence_number INT NULL AFTER report_mode",
        'latitude' => "ALTER TABLE sensor_readings ADD COLUMN latitude DECIMAL(10,6) NULL AFTER sequence_number",
        'longitude' => "ALTER TABLE sensor_readings ADD COLUMN longitude DECIMAL(10,6) NULL AFTER latitude",
        'distance_m' => "ALTER TABLE sensor_readings ADD COLUMN distance_m DECIMAL(10,2) NULL AFTER longitude",
    ];

    $columnStmt = $pdo->query("SHOW COLUMNS FROM sensor_readings");
    $existingColumns = [];
    foreach ($columnStmt->fetchAll() as $column) {
        $existingColumns[$column['Field']] = true;
    }

    foreach ($requiredColumns as $columnName => $sql) {
        if (!isset($existingColumns[$columnName])) {
            $pdo->exec($sql);
        }
    }
}

try {
    ensureDashboardTables($pdo);

    $settings = getDashboardSettings($pdo);
    if (isset($settings['default_range']) && isset($rangeMap[$settings['default_range']]) && !isset($_GET['range'])) {
        $range = $settings['default_range'];
        $rangeStart = date('Y-m-d H:i:s', strtotime($rangeMap[$range]));
    }

    $nodesStmt = $pdo->query("
        SELECT id, name, location, hardware_id, latitude, longitude
        FROM nodes
        ORDER BY id ASC
    ");
    $nodes = $nodesStmt->fetchAll();

    $nodeIds = array_map(static fn($row) => (int) $row['id'], $nodes);
    $nodeId = $requestedNode === 'all'
        ? ($nodeIds[0] ?? 1)
        : max(1, (int) $requestedNode);

    $nodeStmt = $pdo->prepare("
        SELECT id, name, location, hardware_id, latitude, longitude
        FROM nodes
        WHERE id = :node_id
        LIMIT 1
    ");
    $nodeStmt->execute([':node_id' => $nodeId]);
    $node = $nodeStmt->fetch() ?: ['id' => $nodeId, 'name' => 'Node ' . $nodeId, 'location' => 'Unknown', 'hardware_id' => null, 'latitude' => null, 'longitude' => null, 'distance_m' => null];

    $profiles = getSensorProfiles($pdo, $nodeId);

    $summaryStmt = $pdo->prepare("
        SELECT id, rssi, snr, priority_level, report_mode, sequence_number, latitude, longitude, distance_m, created_at
        FROM sensor_readings
        WHERE node_id = :node_id
        ORDER BY created_at DESC, id DESC
        LIMIT 1
    ");
    $summaryStmt->execute([':node_id' => $nodeId]);
    $latestReading = $summaryStmt->fetch() ?: null;

    $signalStmt = $pdo->prepare("
        SELECT id, rssi, snr, priority_level, report_mode, sequence_number, latitude, longitude, distance_m, created_at
        FROM sensor_readings
        WHERE node_id = :node_id
          AND created_at >= :range_start
        ORDER BY created_at DESC, id DESC
        LIMIT 24
    ");
    $signalStmt->execute([
        ':node_id' => $nodeId,
        ':range_start' => $rangeStart,
    ]);
    $signalHistory = array_reverse($signalStmt->fetchAll());

    $historySql = [];
    $activityParams = [];
    $activityIndex = 0;
    foreach ($sensorConfig as $sensor) {
        $nodeParam = ':node_id_' . $activityIndex;
        $rangeParam = ':range_start_' . $activityIndex;
        $historySql[] = "
            SELECT '{$sensor['label']}' AS sensor_label,
                   '{$sensor['table']}' AS source_table,
                   pin_number,
                   value,
                   created_at
            FROM {$sensor['table']}
            WHERE node_id = {$nodeParam}
              AND created_at >= {$rangeParam}
        ";
        $activityParams[$nodeParam] = $nodeId;
        $activityParams[$rangeParam] = $rangeStart;
        $activityIndex++;
    }

    $activityStmt = $pdo->prepare(implode(' UNION ALL ', $historySql) . '
        ORDER BY created_at DESC
        LIMIT 60');
    $activityStmt->execute($activityParams);

    $recentActivity = [];
    foreach ($activityStmt->fetchAll() as $row) {
        $recentActivity[] = [
            'sensor' => $row['sensor_label'],
            'table' => $row['source_table'],
            'pin' => (int) $row['pin_number'],
            'value' => $row['value'],
            'created_at' => $row['created_at']
        ];
    }

    $sensors = [];
    $activeSensorCount = 0;
    $configuredSensorCount = 0;
    $configuredSensors = [];
    $alerts = [];

    // --- Batch 1: configured check (one row per sensor present in the latest reading) ---
    $configuredSet = [];
    if ($latestReading) {
        $cfgParts = [];
        $cfgParams = [];
        $ci = 0;
        foreach ($sensorConfig as $sensorKey => $sensor) {
            $cfgParts[] = "(SELECT '{$sensorKey}' AS sk FROM {$sensor['table']} WHERE node_id = :cfgn_{$ci} AND reading_id = :cfgr_{$ci} LIMIT 1)";
            $cfgParams[":cfgn_{$ci}"] = $nodeId;
            $cfgParams[":cfgr_{$ci}"] = (int) $latestReading['id'];
            $ci++;
        }
        $cfgStmt = $pdo->prepare(implode(' UNION ALL ', $cfgParts));
        $cfgStmt->execute($cfgParams);
        foreach ($cfgStmt->fetchAll(PDO::FETCH_COLUMN) as $sk) {
            $configuredSet[$sk] = true;
        }
    }

    // --- Batch 2: latest value per sensor (ranked subquery avoids per-table MAX join) ---
    $latestParts = [];
    $latestParams = [];
    $li = 0;
    foreach ($sensorConfig as $sensorKey => $sensor) {
        $latestParts[] = "(SELECT '{$sensorKey}' AS sk, id, pin_number, value, created_at FROM {$sensor['table']} WHERE node_id = :ltn_{$li} ORDER BY created_at DESC, id DESC LIMIT 1)";
        $latestParams[":ltn_{$li}"] = $nodeId;
        $li++;
    }
    $latestStmt = $pdo->prepare(implode(' UNION ALL ', $latestParts));
    $latestStmt->execute($latestParams);
    $latestBySensor = [];
    foreach ($latestStmt->fetchAll() as $row) {
        $latestBySensor[$row['sk']] = $row;
    }

    // --- Batch 3: history per sensor within range ---
    $histParts = [];
    $histParams = [];
    $hi = 0;
    foreach ($sensorConfig as $sensorKey => $sensor) {
        $histParts[] = "(SELECT '{$sensorKey}' AS sk, id, pin_number, value, created_at FROM {$sensor['table']} WHERE node_id = :htn_{$hi} AND created_at >= :htr_{$hi} ORDER BY created_at DESC, id DESC LIMIT {$historyLimit})";
        $histParams[":htn_{$hi}"] = $nodeId;
        $histParams[":htr_{$hi}"] = $rangeStart;
        $hi++;
    }
    $histStmt = $pdo->prepare(implode(' UNION ALL ', $histParts));
    $histStmt->execute($histParams);
    $histBySensor = [];
    foreach ($histStmt->fetchAll() as $row) {
        $histBySensor[$row['sk']][] = $row;
    }

    foreach ($sensorConfig as $sensorKey => $sensor) {
        $configured = isset($configuredSet[$sensorKey]);
        $latest = $latestBySensor[$sensorKey] ?? null;
        $rows = array_reverse($histBySensor[$sensorKey] ?? []);

        $history = [];
        foreach ($rows as $row) {
            $normalized = normalizeValue($row['value'], $sensorKey);
            $history[] = [
                'id' => (int) $row['id'],
                'pin' => (int) $row['pin_number'],
                'raw' => $row['value'],
                'numeric' => $normalized['numeric'],
                'display' => $normalized['display'],
                'created_at' => $row['created_at']
            ];
        }

        $latestPayload = null;
        if ($latest) {
            $normalizedLatest = normalizeValue($latest['value'], $sensorKey);
            $latestPayload = [
                'id' => (int) $latest['id'],
                'pin' => (int) $latest['pin_number'],
                'raw' => $latest['value'],
                'numeric' => $normalizedLatest['numeric'],
                'display' => $normalizedLatest['display'],
                'created_at' => $latest['created_at']
            ];
            $activeSensorCount++;
        }

        if ($configured) {
            $configuredSensorCount++;
            $configuredSensors[] = $sensorKey;
        }

        $profile = $profiles[$sensorKey];
        $status = 'ok';
        if ($latestPayload && $latestPayload['numeric'] !== null) {
            if ($profile['threshold_min'] !== null && $latestPayload['numeric'] < $profile['threshold_min']) {
                $status = 'low';
            } elseif ($profile['threshold_max'] !== null && $latestPayload['numeric'] > $profile['threshold_max']) {
                $status = 'high';
            }
        }

        if ($latestPayload && strtolower(trim((string) ($latestPayload['raw'] ?? ''))) === 'nan' && ($sensorKey === 'temperature' || $sensorKey === 'humidity')) {
            $status = 'critical';
        }

        if ($latestPayload && $sensorKey === 'waterTemp' && is_numeric(trim((string) ($latestPayload['raw'] ?? ''))) && (float) trim((string) $latestPayload['raw']) === -127.0) {
            $status = 'critical';
        }

        if ($status !== 'ok') {
            $message = $sensor['label'] . ' is ' . $status . ' at ' . $latestPayload['display'] . ($sensor['unit'] !== 'state' ? ' ' . $sensor['unit'] : '');
            $severity = 'warning';

            if ($status === 'critical' && ($sensorKey === 'temperature' || $sensorKey === 'humidity')) {
                $message = 'Check DHT sensor';
                $severity = 'critical';
            }

            if ($status === 'critical' && $sensorKey === 'waterTemp') {
                $message = 'Check DS18B20 sensor';
                $severity = 'critical';
            }

            $alerts[] = [
                'sensor_key' => $sensorKey,
                'label' => $sensor['label'],
                'severity' => $severity,
                'message' => $message,
                'created_at' => $latestPayload['created_at'] ?? $latestReading['created_at'] ?? null,
                'accent' => $sensor['accent'],
            ];
        }

        $sensors[$sensorKey] = [
            'key' => $sensorKey,
            'label' => $sensor['label'],
            'family' => $sensor['family'],
            'table' => $sensor['table'],
            'unit' => $sensor['unit'],
            'accent' => $sensor['accent'],
            'icon' => $sensor['icon'],
            'configured' => $configured,
            'status' => $status,
            'latest' => $latestPayload,
            'history' => $history,
            'threshold_min' => $profile['threshold_min'],
            'threshold_max' => $profile['threshold_max'],
            'calibration' => [
                'a' => $profile['calibration_a'],
                'b' => $profile['calibration_b'],
                'c' => $profile['calibration_c'],
            ],
        ];
    }

    $nodeStatus = classifyNodeStatus($latestReading['created_at'] ?? null);
    $signal = signalQuality(
        $latestReading ? (int) $latestReading['rssi'] : null,
        $latestReading ? (float) $latestReading['snr'] : null
    );

    // Load persisted alert records from DB
    $persistedAlertsStmt = $pdo->prepare("
        SELECT sensor_key, status, acknowledged_at, resolved_at
        FROM alerts
        WHERE node_id = :node_id
          AND status IN ('active', 'acknowledged', 'resolved')
        ORDER BY created_at DESC
    ");
    $persistedAlertsStmt->execute([':node_id' => $nodeId]);
    $persistedAlertsMap = [];
    foreach ($persistedAlertsStmt->fetchAll() as $row) {
        $persistedAlertsMap[$row['sensor_key']] = [
            'status' => $row['status'],
            'acknowledged_at' => $row['acknowledged_at'],
            'resolved_at' => $row['resolved_at'],
        ];
    }

    // Merge persisted state into live alerts
    foreach ($alerts as &$alert) {
        if (isset($persistedAlertsMap[$alert['sensor_key']])) {
            $alert['db_status'] = $persistedAlertsMap[$alert['sensor_key']]['status'];
            $alert['acknowledged_at'] = $persistedAlertsMap[$alert['sensor_key']]['acknowledged_at'];
            $alert['resolved_at'] = $persistedAlertsMap[$alert['sensor_key']]['resolved_at'];
        }
    }
    unset($alert);

    if ($nodeStatus['state'] !== 'online') {
        $alerts[] = [
            'sensor_key' => 'node',
            'label' => 'Node status',
            'severity' => $nodeStatus['state'] === 'offline' ? 'critical' : 'warning',
            'message' => $nodeStatus['label'] . ': no fresh packet within the target freshness window.',
            'created_at' => $latestReading['created_at'] ?? null,
            'accent' => $nodeStatus['state'] === 'offline' ? '#ff8f9d' : '#ffa94d',
        ];
    }

    $priorityAnalyticsStmt = $pdo->prepare("
        SELECT priority_level, COUNT(*) AS total
        FROM sensor_readings
        WHERE node_id = :node_id
          AND created_at >= :range_start
        GROUP BY priority_level
    ");
    $priorityAnalyticsStmt->execute([
        ':node_id' => $nodeId,
        ':range_start' => $rangeStart,
    ]);
    $priorityCounts = [
        'LOW' => 0,
        'MEDIUM' => 0,
        'HIGH' => 0,
    ];
    $priorityTotal = 0;
    foreach ($priorityAnalyticsStmt->fetchAll() as $row) {
        $level = strtoupper((string) $row['priority_level']);
        if (isset($priorityCounts[$level])) {
            $priorityCounts[$level] = (int) $row['total'];
            $priorityTotal += (int) $row['total'];
        }
    }

    // RSSI / SNR trend analytics
    $signalAnalyticsStmt = $pdo->prepare("
        SELECT
            MIN(rssi) AS min_rssi,
            MAX(rssi) AS max_rssi,
            AVG(rssi) AS avg_rssi,
            MIN(snr) AS min_snr,
            MAX(snr) AS max_snr,
            AVG(snr) AS avg_snr,
            COUNT(*) AS packet_count
        FROM sensor_readings
        WHERE node_id = :node_id
          AND created_at >= :range_start
          AND rssi IS NOT NULL
    ");
    $signalAnalyticsStmt->execute([
        ':node_id' => $nodeId,
        ':range_start' => $rangeStart,
    ]);
    $signalStats = $signalAnalyticsStmt->fetch() ?: null;
    $signalAnalytics = [
        'min_rssi'  => $signalStats && $signalStats['min_rssi']  !== null ? (int)   $signalStats['min_rssi']  : null,
        'max_rssi'  => $signalStats && $signalStats['max_rssi']  !== null ? (int)   $signalStats['max_rssi']  : null,
        'avg_rssi'  => $signalStats && $signalStats['avg_rssi']  !== null ? round((float) $signalStats['avg_rssi'], 1) : null,
        'min_snr'   => $signalStats && $signalStats['min_snr']   !== null ? round((float) $signalStats['min_snr'], 1) : null,
        'max_snr'   => $signalStats && $signalStats['max_snr']   !== null ? round((float) $signalStats['max_snr'], 1) : null,
        'avg_snr'   => $signalStats && $signalStats['avg_snr']   !== null ? round((float) $signalStats['avg_snr'], 1) : null,
        'packet_count' => $signalStats ? (int) $signalStats['packet_count'] : 0,
    ];

    // --- Batch 4: analytics (MIN/MAX/AVG) for all sensors in one query ---
    $sensorAnalytics = [];
    $anParts = [];
    $anParams = [];
    $ai = 0;
    foreach ($sensorConfig as $sensorKey => $sensor) {
        $anParts[] = "(SELECT '{$sensorKey}' AS sk, MIN(CAST(value AS DECIMAL(12,4))) AS min_v, MAX(CAST(value AS DECIMAL(12,4))) AS max_v, AVG(CAST(value AS DECIMAL(12,4))) AS avg_v FROM {$sensor['table']} WHERE node_id = :ann_{$ai} AND value REGEXP '^-?[0-9]+(\\.[0-9]+)?$' AND created_at >= :anr_{$ai})";
        $anParams[":ann_{$ai}"] = $nodeId;
        $anParams[":anr_{$ai}"] = $rangeStart;
        $ai++;
    }
    $anStmt = $pdo->prepare(implode(' UNION ALL ', $anParts));
    $anStmt->execute($anParams);
    foreach ($anStmt->fetchAll() as $row) {
        $sensorAnalytics[$row['sk']] = [
            'min' => $row['min_v'] !== null ? round((float) $row['min_v'], 2) : null,
            'max' => $row['max_v'] !== null ? round((float) $row['max_v'], 2) : null,
            'avg' => $row['avg_v'] !== null ? round((float) $row['avg_v'], 2) : null,
        ];
    }
    foreach ($sensorConfig as $sensorKey => $_) {
        if (!isset($sensorAnalytics[$sensorKey])) {
            $sensorAnalytics[$sensorKey] = ['min' => null, 'max' => null, 'avg' => null];
        }
    }

    echo json_encode([
        'status' => 'success',
        'generated_at' => date('Y-m-d H:i:s'),
        'timezone' => date_default_timezone_get(),
        'selected_range' => $range,
        'range_start' => $rangeStart,
        'retention_policy' => getDataRetentionPolicy($pdo),
        'settings' => $settings,
        'nodes' => $nodes,
        'node' => $node,
        'summary' => [
            'latest_reading_id' => $latestReading ? (int) $latestReading['id'] : null,
            'latest_reading_at' => $latestReading['created_at'] ?? null,
            'rssi' => $latestReading ? (int) $latestReading['rssi'] : null,
            'snr' => $latestReading ? (float) $latestReading['snr'] : null,
            'priority_level' => $latestReading['priority_level'] ?? 'LOW',
            'report_mode' => $latestReading['report_mode'] ?? 'NORMAL',
            'sequence_number' => $latestReading['sequence_number'] === null ? null : (int) $latestReading['sequence_number'],
            'latitude' => $latestReading['latitude'] === null ? null : (float) $latestReading['latitude'],
            'longitude' => $latestReading['longitude'] === null ? null : (float) $latestReading['longitude'],
            'distance_m' => $latestReading['distance_m'] === null ? null : (float) $latestReading['distance_m'],
            'active_sensor_count' => $activeSensorCount,
            'configured_sensor_count' => $configuredSensorCount,
            'node_status' => $nodeStatus,
            'signal_quality' => $signal,
        ],
        'analytics' => [
            'critical_event_count' => $priorityCounts['HIGH'],
            'priority_counts' => $priorityCounts,
            'priority_percentages' => [
                'LOW' => $priorityTotal > 0 ? round(($priorityCounts['LOW'] / $priorityTotal) * 100, 2) : 0,
                'MEDIUM' => $priorityTotal > 0 ? round(($priorityCounts['MEDIUM'] / $priorityTotal) * 100, 2) : 0,
                'HIGH' => $priorityTotal > 0 ? round(($priorityCounts['HIGH'] / $priorityTotal) * 100, 2) : 0,
            ],
            'sensor_stats' => $sensorAnalytics,
            'signal_stats' => $signalAnalytics,
        ],
        'configured_sensors' => $configuredSensors,
        'profiles' => $profiles,
        'alerts' => $alerts,
        'alert_history' => getActiveAlerts($pdo, $nodeId),
        'communication_health' => computeCommunicationHealth($pdo, $nodeId, $rangeStart),
        'signal_history' => array_map(static function ($row) {
            return [
                'id' => (int) $row['id'],
                'rssi' => $row['rssi'] === null ? null : (int) $row['rssi'],
                'snr' => $row['snr'] === null ? null : (float) $row['snr'],
                'priority_level' => $row['priority_level'] ?? 'LOW',
                'report_mode' => $row['report_mode'] ?? 'NORMAL',
                'sequence_number' => $row['sequence_number'] === null ? null : (int) $row['sequence_number'],
                'latitude' => $row['latitude'] === null ? null : (float) $row['latitude'],
                'longitude' => $row['longitude'] === null ? null : (float) $row['longitude'],
                'distance_m' => $row['distance_m'] === null ? null : (float) $row['distance_m'],
                'created_at' => $row['created_at'],
            ];
        }, $signalHistory),
        'sensors' => $sensors,
        'recent_activity' => $recentActivity,
        'signal_stats' => $signalAnalytics,
    ]);
} catch (Exception $e) {
    http_response_code(500);
    echo json_encode(['error' => 'Failed to load dashboard data: ' . $e->getMessage()]);
}
