<?php
/**
 * SmartPonic receive_data.php
 *
 * Primary telemetry ingestion endpoint.
 * Receives encrypted sensor data forwarded by the HQ gateway.
 *
 * Headers:
 *   X-API-Key:     Shared API key
 *   X-Timestamp:   Unix timestamp
 *   X-Signature:   SHA256(timestamp + body + secret)
 *
 * Body (JSON):
 *   {
 *     "hardware_id": "16-char hex",
 *     "rssi": -45,
 *     "snr": 10.5,
 *     "event_type": "telemetry",
 *     "sensors": [{ "pin": 4, "sensor": "Temperature", "value": "28.5" }, ...]
 *   }
 */

require_once __DIR__ . '/db.php';
require_once __DIR__ . '/security_config.php';

// ──────────────────────────────────────────────
// 1. Validate HTTP method
// ──────────────────────────────────────────────
if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['error' => 'Method not allowed']);
    exit;
}

// ──────────────────────────────────────────────
// 2. Validate headers
// ──────────────────────────────────────────────
$apiKey     = $_SERVER['HTTP_X_API_KEY']     ?? '';
$timestamp  = $_SERVER['HTTP_X_TIMESTAMP']   ?? '';
$signature  = $_SERVER['HTTP_X_SIGNATURE']   ?? '';

// API key check
if ($apiKey !== SMARTPONIC_API_KEY) {
    http_response_code(401);
    echo json_encode(['error' => 'Invalid API key']);
    exit;
}

// Timestamp check
// Accept both Unix timestamps AND millis() values from ESP32.
// millis() values (< 1700000000) skip the real-time window check
// since ESP32 has no RTC. Signature still validates either way.
if (!is_numeric($timestamp)) {
    http_response_code(400);
    echo json_encode(['error' => 'Invalid timestamp']);
    exit;
}

$ts  = (int)$timestamp;
if ($ts > 1700000000) {
    // Real Unix timestamp — enforce time window
    $now = time();
    if (abs($now - $ts) > SMARTPONIC_REQUEST_MAX_AGE) {
        http_response_code(401);
        echo json_encode(['error' => 'Timestamp out of window']);
        exit;
    }
}
// millis()-style timestamps are accepted without window check

// ──────────────────────────────────────────────
// 3. Read and verify body
// ──────────────────────────────────────────────
$rawBody = file_get_contents('php://input');
if ($rawBody === false || $rawBody === '') {
    http_response_code(400);
    echo json_encode(['error' => 'Empty request body']);
    exit;
}

// Verify signature: SHA256(timestamp + body + secret)
$expectedSig = hash('sha256', $timestamp . $rawBody . SMARTPONIC_HMAC_SECRET);
if (!hash_equals($expectedSig, $signature)) {
    http_response_code(401);
    echo json_encode(['error' => 'Invalid signature']);
    exit;
}

// ──────────────────────────────────────────────
// 4. Parse JSON body
// ──────────────────────────────────────────────
$data = json_decode($rawBody, true);
if ($data === null) {
    http_response_code(400);
    echo json_encode(['error' => 'Invalid JSON']);
    exit;
}

$hardwareId = $data['hardware_id'] ?? '';
$rssi       = isset($data['rssi'])       ? (int)$data['rssi']        : null;
$snr        = isset($data['snr'])        ? (float)$data['snr']       : null;
$eventType  = $data['event_type']        ?? 'telemetry';
$sensors    = $data['sensors']           ?? [];

// Priority/report_mode from binary payload (0=low/normal, 1=medium/abnormal, 2=high/critical)
$priorityIdx   = isset($data['priority'])    ? (int)$data['priority']    : 0;
$reportModeIdx = isset($data['report_mode']) ? (int)$data['report_mode'] : 0;
$priorityMap   = [0 => 'LOW', 1 => 'MEDIUM', 2 => 'HIGH'];
$reportModeMap = [0 => 'NORMAL', 1 => 'ABNORMAL', 2 => 'CRITICAL'];
$priorityStr   = $priorityMap[$priorityIdx]   ?? 'LOW';
$reportModeStr = $reportModeMap[$reportModeIdx] ?? 'NORMAL';

// Validate hardware_id (16-char uppercase hex)
if (!preg_match('/^[0-9A-F]{16}$/', $hardwareId)) {
    http_response_code(400);
    echo json_encode(['error' => 'Invalid hardware_id format']);
    exit;
}

// Validate sensors array
if (!is_array($sensors) || count($sensors) === 0) {
    http_response_code(400);
    echo json_encode(['error' => 'Missing or empty sensors array']);
    exit;
}

if (count($sensors) > 32) {
    http_response_code(400);
    echo json_encode(['error' => 'Too many sensors (max 32)']);
    exit;
}

// ──────────────────────────────────────────────
// 5. Process
// ──────────────────────────────────────────────
try {
    $db = getDb();

    // Auto-register node if new
    $stmt = $db->prepare('INSERT IGNORE INTO nodes (hardware_id) VALUES (?)');
    $stmt->execute([$hardwareId]);

    // Update last_seen
    $stmt = $db->prepare('UPDATE nodes SET last_seen = NOW() WHERE hardware_id = ?');
    $stmt->execute([$hardwareId]);

    // Insert sensor_readings record
    $stmt = $db->prepare(
        'INSERT INTO sensor_readings (hardware_id, rssi, snr, event_type, priority, report_mode) VALUES (?, ?, ?, ?, ?, ?)'
    );
    $stmt->execute([$hardwareId, $rssi, $snr, $eventType, $priorityStr, $reportModeStr]);
    $readingId = (int)$db->lastInsertId();

    // Prepare statements for sensor_data and invalid_sensor_data
    $stmtSensor = $db->prepare(
        'INSERT INTO sensor_data (reading_id, pin, sensor, value) VALUES (?, ?, ?, ?)'
    );
    $stmtInvalid = $db->prepare(
        'INSERT INTO invalid_sensor_data (hardware_id, pin, sensor, value, reason) VALUES (?, ?, ?, ?, ?)'
    );

    $validCount   = 0;
    $invalidCount = 0;

    foreach ($sensors as $s) {
        $pin    = (int)($s['pin']    ?? 0);
        $sensor =      $s['sensor']  ?? '';
        $value  =      $s['value']   ?? '';

        if ($pin === 0 || $sensor === '' || $value === '') {
            continue; // skip malformed entries silently
        }

        // Check for invalid sensor values
        $reason = checkInvalidSensor($sensor, $value);

        if ($reason !== null) {
            $stmtInvalid->execute([$hardwareId, $pin, $sensor, $value, $reason]);
            $invalidCount++;
        }

        // Always store the reading (even invalid ones for diagnostics)
        $stmtSensor->execute([$readingId, $pin, $sensor, $value]);
        $validCount++;
    }

    // ──────────────────────────────────────────────
    // 6. Success response
    // ──────────────────────────────────────────────
    http_response_code(200);
    echo json_encode([
        'status'    => 'ok',
        'reading_id'=> $readingId,
        'sensors'   => $validCount,
        'invalid'   => $invalidCount,
    ]);

} catch (PDOException $e) {
    http_response_code(500);
    echo json_encode(['error' => 'Database error']);
    error_log('SmartPonic receive_data DB error: ' . $e->getMessage());
} catch (Throwable $e) {
    http_response_code(500);
    echo json_encode(['error' => 'Internal server error']);
    error_log('SmartPonic receive_data error: ' . $e->getMessage());
}

// ──────────────────────────────────────────────
// Helper: detect invalid sensor readings
// ──────────────────────────────────────────────
function checkInvalidSensor(string $sensor, string $value): ?string {
    $lower = strtolower(trim($value));

    // DHT22 returning NaN
    if ($lower === 'nan' || $lower === 'nan') {
        return 'Check DHT sensor (NaN)';
    }

    // DS18B20 error value
    if ($lower === '-127' || $lower === '-127.00' || $lower === '-127.0') {
        return 'Check DS18B20 sensor (open/error)';
    }

    // Only validate numeric values further
    if (!is_numeric($value)) {
        return null; // non-numeric but not known-error, pass through
    }

    $val = (float)$value;

    // Humidity range check
    if ($sensor === 'Humidity' && ($val < 0 || $val > 100)) {
        return 'Humidity out of valid range (0-100%)';
    }

    // pH range check
    if ($sensor === 'pH' && ($val < 0 || $val > 14)) {
        return 'pH out of valid range (0-14)';
    }

    return null;
}
