<?php
/**
 * receive_data.php
 * API endpoint to receive sensor data from HQ Site
 *
 * HQ Site sends HTTP POST request with JSON data:
 * {
 *   "node_id": 1,
 *   "rssi": -45,
 *   "snr": 10.5,
 *   "sensors": [
 *     {"pin": 32, "sensor": "pH", "value": "2048"},
 *     {"pin": 33, "sensor": "TDS", "value": "1500"},
 *     ...
 *   ]
 * }
 */

require_once 'security_config.php';

header('Content-Type: application/json');
if (isset($_SERVER['HTTP_ORIGIN']) && in_array($_SERVER['HTTP_ORIGIN'], SMARTPONIC_ALLOWED_ORIGINS, true)) {
    header('Access-Control-Allow-Origin: ' . $_SERVER['HTTP_ORIGIN']);
}
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, X-API-Key, X-Timestamp, X-Signature');

// Handle preflight requests
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}

// Only accept POST requests
if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['error' => 'Method not allowed']);
    exit;
}

require_once 'db.php';
require_once 'data_policy.php';

function respondWithJsonError(int $statusCode, string $message): void
{
    http_response_code($statusCode);
    echo json_encode(['error' => $message]);
    exit;
}

function getRequiredHeader(string $headerName): string
{
    $serverKey = 'HTTP_' . strtoupper(str_replace('-', '_', $headerName));
    $value = $_SERVER[$serverKey] ?? '';
    return is_string($value) ? trim($value) : '';
}

function verifySignedRequest(string $rawJson): void
{
    $apiKey = getRequiredHeader('X-API-Key');
    $timestamp = getRequiredHeader('X-Timestamp');
    $signature = getRequiredHeader('X-Signature');

    if ($apiKey === '' || $timestamp === '' || $signature === '') {
        respondWithJsonError(401, 'Missing security headers');
    }

    if (!hash_equals(SMARTPONIC_API_KEY, $apiKey)) {
        respondWithJsonError(403, 'Invalid API key');
    }

    if (!ctype_digit($timestamp)) {
        respondWithJsonError(400, 'Invalid request timestamp');
    }

    if (abs(time() - (int) $timestamp) > SMARTPONIC_REQUEST_MAX_AGE_SECONDS) {
        respondWithJsonError(408, 'Request timestamp expired');
    }

    $expectedSignature = hash_hmac('sha256', $timestamp . "\n" . $rawJson, SMARTPONIC_HMAC_SECRET);
    if (!hash_equals($expectedSignature, strtolower($signature))) {
        respondWithJsonError(403, 'Invalid request signature');
    }
}

if (isset($_SERVER['HTTP_ORIGIN']) && !in_array($_SERVER['HTTP_ORIGIN'], SMARTPONIC_ALLOWED_ORIGINS, true)) {
    respondWithJsonError(403, 'Origin not allowed');
}

// Get JSON input
$json = file_get_contents('php://input');
verifySignedRequest($json);
$data = json_decode($json, true);

// Validate input
if (!is_array($data) || !isset($data['node_id']) || !isset($data['sensors'])) {
    respondWithJsonError(400, 'Invalid data format');
}

if (!is_int($data['node_id']) && !(is_string($data['node_id']) && ctype_digit($data['node_id']))) {
    respondWithJsonError(400, 'Invalid node ID');
}

if ((int) $data['node_id'] <= 0) {
    respondWithJsonError(400, 'Node ID must be positive');
}

$eventType = isset($data['event_type']) && is_string($data['event_type']) ? strtolower(trim($data['event_type'])) : 'telemetry';
if (!in_array($eventType, ['telemetry', 'location_update'], true)) {
    $eventType = 'telemetry';
}

if (!is_array($data['sensors'])) {
    respondWithJsonError(400, 'Invalid sensor list');
}

if ($eventType === 'telemetry' && count($data['sensors']) === 0) {
    respondWithJsonError(400, 'No sensor data provided');
}

if (count($data['sensors']) > 32) {
    respondWithJsonError(400, 'Too many sensors in one request');
}

$priorityLevel = isset($data['priority']) && is_string($data['priority']) ? strtoupper(trim($data['priority'])) : 'LOW';
if (!in_array($priorityLevel, ['LOW', 'MEDIUM', 'HIGH'], true)) {
    $priorityLevel = 'LOW';
}

$reportMode = isset($data['report_mode']) && is_string($data['report_mode']) ? strtoupper(trim($data['report_mode'])) : 'NORMAL';
if (!in_array($reportMode, ['NORMAL', 'ABNORMAL', 'CRITICAL'], true)) {
    $reportMode = 'NORMAL';
}

$sequenceNumber = null;
if (isset($data['sequence']) && (is_int($data['sequence']) || (is_string($data['sequence']) && ctype_digit($data['sequence'])))) {
    $sequenceNumber = (int) $data['sequence'];
}

$latitude = isset($data['latitude']) && is_numeric($data['latitude']) ? (float) $data['latitude'] : null;
$longitude = isset($data['longitude']) && is_numeric($data['longitude']) ? (float) $data['longitude'] : null;
$distanceMeters = isset($data['distance']) && is_numeric($data['distance']) ? (float) $data['distance'] : null;

function ensureInvalidSensorTable(PDO $pdo): void
{
    $pdo->exec("
        CREATE TABLE IF NOT EXISTS invalid_sensor_data (
            id INT AUTO_INCREMENT PRIMARY KEY,
            node_id INT NOT NULL,
            reading_id INT NULL,
            sensor_name VARCHAR(100) NOT NULL,
            pin_number INT NOT NULL,
            raw_value VARCHAR(100) NOT NULL,
            reason VARCHAR(255) NOT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            INDEX idx_invalid_node_created (node_id, created_at)
        )
    ");
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

function classifyInvalidSensorValue(string $sensorKey, string $rawValue): ?string
{
    $trimmed = trim($rawValue);
    $lower = strtolower($trimmed);

    if (($sensorKey === 'temperature' || $sensorKey === 'humidity') && $lower === 'nan') {
        return 'Check DHT sensor';
    }

    if ($sensorKey === 'watertemp' && is_numeric($trimmed) && (float) $trimmed === -127.0) {
        return 'Check DS18B20 sensor';
    }

    if ($sensorKey === 'humidity' && is_numeric($trimmed)) {
        $value = (float) $trimmed;
        if ($value < 0 || $value > 100) {
            return 'Humidity out of valid range';
        }
    }

    if ($sensorKey === 'ph' && is_numeric($trimmed)) {
        $value = (float) $trimmed;
        if ($value < 0 || $value > 14) {
            return 'pH out of valid range';
        }
    }

    return null;
}

try {
    $sensorTableMap = [
        'temperature' => 'temperature_data',
        'humidity' => 'humidity_data',
        'watertemp' => 'water_temp_data',
        'ph' => 'ph_data',
        'tds' => 'tds_data',
        'turbidity' => 'turbidity_data',
        'rain' => 'rain_data'
    ];

    ensureInvalidSensorTable($pdo);
    ensureSensorReadingsColumns($pdo);

    if ($eventType === 'location_update') {
        $locationParts = [];
        if ($latitude !== null && $longitude !== null) {
            $locationParts[] = 'Lat ' . number_format($latitude, 6, '.', '');
            $locationParts[] = 'Lon ' . number_format($longitude, 6, '.', '');
        }
        if ($distanceMeters !== null) {
            $locationParts[] = 'Distance ' . number_format($distanceMeters, 1, '.', '') . ' m';
        }

        $locationSummary = implode(' | ', $locationParts);
        if ($locationSummary !== '') {
            $nodeUpdateStmt = $pdo->prepare("
                INSERT INTO nodes (id, name, location)
                VALUES (:node_id, :name, :location)
                ON DUPLICATE KEY UPDATE location = VALUES(location)
            ");
            $nodeUpdateStmt->execute([
                ':node_id' => (int) $data['node_id'],
                ':name' => 'Node ' . (int) $data['node_id'],
                ':location' => $locationSummary,
            ]);
        }

        echo json_encode([
            'status' => 'success',
            'message' => 'Location metadata updated successfully',
            'event_type' => 'location_update',
            'node_id' => (int) $data['node_id'],
            'latitude' => $latitude,
            'longitude' => $longitude,
            'distance' => $distanceMeters,
        ]);
        exit;
    }

    // Begin transaction
    $pdo->beginTransaction();
    $insertedTables = [];
    $sensorRouting = [];
    $skippedSensors = [];

    // Insert main reading record
    $stmt = $pdo->prepare("
        INSERT INTO sensor_readings (node_id, rssi, snr, priority_level, report_mode, sequence_number, latitude, longitude, distance_m)
        VALUES (:node_id, :rssi, :snr, :priority_level, :report_mode, :sequence_number, :latitude, :longitude, :distance_m)
    ");
    $stmt->execute([
        ':node_id' => $data['node_id'],
        ':rssi' => $data['rssi'] ?? null,
        ':snr' => $data['snr'] ?? null,
        ':priority_level' => $priorityLevel,
        ':report_mode' => $reportMode,
        ':sequence_number' => $sequenceNumber,
        ':latitude' => $latitude,
        ':longitude' => $longitude,
        ':distance_m' => $distanceMeters
    ]);

    $reading_id = $pdo->lastInsertId();

    // Prepare one insert per sensor table so values go into separate tables.
    $sensorStatements = [];

    foreach (array_unique(array_values($sensorTableMap)) as $tableName) {
        $sensorStatements[$tableName] = $pdo->prepare("
            INSERT INTO {$tableName} (reading_id, node_id, pin_number, value)
            VALUES (:reading_id, :node_id, :pin_number, :value)
        ");
    }

    $invalidSensorStmt = $pdo->prepare("
        INSERT INTO invalid_sensor_data (node_id, reading_id, sensor_name, pin_number, raw_value, reason)
        VALUES (:node_id, :reading_id, :sensor_name, :pin_number, :raw_value, :reason)
    ");

    foreach ($data['sensors'] as $sensor) {
        if (!is_array($sensor) || !isset($sensor['sensor'], $sensor['pin'], $sensor['value'])) {
            throw new InvalidArgumentException('Invalid sensor payload');
        }

        if (!is_int($sensor['pin']) && !(is_string($sensor['pin']) && ctype_digit($sensor['pin']))) {
            throw new InvalidArgumentException('Invalid sensor pin value');
        }

        if (!is_string($sensor['sensor']) || trim($sensor['sensor']) === '') {
            throw new InvalidArgumentException('Invalid sensor name');
        }

        $sensorKey = preg_replace('/[^a-z0-9]+/', '', strtolower(trim((string) $sensor['sensor'])));
        $params = [
            ':reading_id' => $reading_id,
            ':node_id' => $data['node_id'],
            ':pin_number' => (int) $sensor['pin'],
            ':value' => (string) $sensor['value']
        ];

        if (!isset($sensorTableMap[$sensorKey])) {
            throw new InvalidArgumentException('Unsupported sensor type: ' . $sensor['sensor']);
        }

        $invalidReason = classifyInvalidSensorValue($sensorKey, (string) $sensor['value']);
        if ($invalidReason !== null) {
            $invalidSensorStmt->execute([
                ':node_id' => $data['node_id'],
                ':reading_id' => $reading_id,
                ':sensor_name' => $sensor['sensor'],
                ':pin_number' => $sensor['pin'],
                ':raw_value' => $sensor['value'],
                ':reason' => $invalidReason
            ]);
            $skippedSensors[] = [
                'sensor' => $sensor['sensor'],
                'pin' => $sensor['pin'],
                'reason' => $invalidReason
            ];
            continue;
        }

        $targetTable = $sensorTableMap[$sensorKey];
        $sensorStatements[$targetTable]->execute($params);
        $insertedTables[] = $targetTable;
        $sensorRouting[] = [
            'sensor' => $sensor['sensor'],
            'pin' => $sensor['pin'],
            'table' => $targetTable
        ];
    }

    // Commit transaction
    $pdo->commit();

    $retentionDeleted = 0;
    try {
        $retentionDeleted = applyDataRetentionPolicy($pdo);
    } catch (Exception $retentionException) {
        $retentionDeleted = 0;
    }

    echo json_encode([
        'status' => 'success',
        'message' => 'Data stored successfully',
        'reading_id' => $reading_id,
        'priority' => $priorityLevel,
        'report_mode' => $reportMode,
        'inserted_tables' => $insertedTables,
        'sensor_routing' => $sensorRouting,
        'skipped_sensors' => $skippedSensors,
        'retention_deleted' => $retentionDeleted
    ]);

} catch (Exception $e) {
    if ($pdo->inTransaction()) {
        $pdo->rollBack();
    }
    http_response_code(500);
    echo json_encode(['error' => 'Failed to store data']);
}
