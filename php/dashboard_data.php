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
    ensureSensorReadingsColumns($pdo);

    $settings = getDashboardSettings($pdo);
    if (isset($settings['default_range']) && isset($rangeMap[$settings['default_range']]) && !isset($_GET['range'])) {
        $range = $settings['default_range'];
        $rangeStart = date('Y-m-d H:i:s', strtotime($rangeMap[$range]));
    }

    $nodesStmt = $pdo->query("
        SELECT id, name, location
        FROM nodes
        ORDER BY id ASC
    ");
    $nodes = $nodesStmt->fetchAll();

    $nodeIds = array_map(static fn($row) => (int) $row['id'], $nodes);
    $nodeId = $requestedNode === 'all'
        ? ($nodeIds[0] ?? 1)
        : max(1, (int) $requestedNode);

    $nodeStmt = $pdo->prepare("
        SELECT id, name, location
        FROM nodes
        WHERE id = :node_id
        LIMIT 1
    ");
    $nodeStmt->execute([':node_id' => $nodeId]);
    $node = $nodeStmt->fetch() ?: ['id' => $nodeId, 'name' => 'Node ' . $nodeId, 'location' => 'Unknown'];

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

    foreach ($sensorConfig as $sensorKey => $sensor) {
        $configured = false;
        if ($latestReading) {
            $configuredStmt = $pdo->prepare("
                SELECT 1
                FROM {$sensor['table']}
                WHERE node_id = :node_id AND reading_id = :reading_id
                LIMIT 1
            ");
            $configuredStmt->execute([
                ':node_id' => $nodeId,
                ':reading_id' => $latestReading['id']
            ]);
            $configured = (bool) $configuredStmt->fetchColumn();
        }

        $latestStmt = $pdo->prepare("
            SELECT id, pin_number, value, created_at
            FROM {$sensor['table']}
            WHERE node_id = :node_id
            ORDER BY created_at DESC, id DESC
            LIMIT 1
        ");
        $latestStmt->execute([':node_id' => $nodeId]);
        $latest = $latestStmt->fetch() ?: null;

        $historyStmt = $pdo->prepare("
            SELECT id, pin_number, value, created_at
            FROM {$sensor['table']}
            WHERE node_id = :node_id
              AND created_at >= :range_start
            ORDER BY created_at DESC, id DESC
            LIMIT {$historyLimit}
        ");
        $historyStmt->execute([
            ':node_id' => $nodeId,
            ':range_start' => $rangeStart
        ]);
        $rows = array_reverse($historyStmt->fetchAll());

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
            'history' => $history
        ];
    }

    $nodeStatus = classifyNodeStatus($latestReading['created_at'] ?? null);
    $signal = signalQuality(
        $latestReading ? (int) $latestReading['rssi'] : null,
        $latestReading ? (float) $latestReading['snr'] : null
    );

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

    $sensorAnalytics = [];
    foreach ($sensorConfig as $sensorKey => $sensor) {
        $statsStmt = $pdo->prepare("
            SELECT MIN(CAST(value AS DECIMAL(12,4))) AS min_value,
                   MAX(CAST(value AS DECIMAL(12,4))) AS max_value,
                   AVG(CAST(value AS DECIMAL(12,4))) AS avg_value
            FROM {$sensor['table']}
            WHERE node_id = :node_id
              AND value REGEXP '^-?[0-9]+(\\.[0-9]+)?$'
              AND created_at >= :range_start
        ");
        $statsStmt->execute([
            ':node_id' => $nodeId,
            ':range_start' => $rangeStart,
        ]);
        $stats = $statsStmt->fetch() ?: null;
        $sensorAnalytics[$sensorKey] = [
            'min' => $stats && $stats['min_value'] !== null ? round((float) $stats['min_value'], 2) : null,
            'max' => $stats && $stats['max_value'] !== null ? round((float) $stats['max_value'], 2) : null,
            'avg' => $stats && $stats['avg_value'] !== null ? round((float) $stats['avg_value'], 2) : null,
        ];
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
        ],
        'configured_sensors' => $configuredSensors,
        'profiles' => $profiles,
        'alerts' => $alerts,
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
        'recent_activity' => $recentActivity
    ]);
} catch (Exception $e) {
    http_response_code(500);
    echo json_encode(['error' => 'Failed to load dashboard data: ' . $e->getMessage()]);
}
