<?php
/**
 * SmartPonic control_queue.php
 *
 * Relay command queue management.
 * HQ polls this endpoint to get pending relay commands for registered nodes.
 *
 * Actions:
 *   get_pending  - Returns pending/approved commands for a node
 *   mark_sent    - Marks a command as sent (after LoRa TX)
 *   ack          - Acknowledges command execution (after node ACK)
 *
 * Headers (same as receive_data):
 *   X-API-Key, X-Timestamp, X-Signature
 */

require_once __DIR__ . '/db.php';
require_once __DIR__ . '/security_config.php';

// ──────────────────────────────────────────────
// 1. Validate method
// ──────────────────────────────────────────────
if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['error' => 'Method not allowed']);
    exit;
}

// ──────────────────────────────────────────────
// 2. Authenticate request
// ──────────────────────────────────────────────
$apiKey    = $_SERVER['HTTP_X_API_KEY']   ?? '';
$timestamp = $_SERVER['HTTP_X_TIMESTAMP'] ?? '';
$signature = $_SERVER['HTTP_X_SIGNATURE'] ?? '';

if ($apiKey !== SMARTPONIC_API_KEY) {
    http_response_code(401);
    echo json_encode(['error' => 'Invalid API key']);
    exit;
}

if (!is_numeric($timestamp)) {
    http_response_code(400);
    echo json_encode(['error' => 'Invalid timestamp']);
    exit;
}

$now = time();
if (abs($now - (int)$timestamp) > SMARTPONIC_REQUEST_MAX_AGE) {
    http_response_code(401);
    echo json_encode(['error' => 'Timestamp out of window']);
    exit;
}

$rawBody = file_get_contents('php://input');
if ($rawBody === false || $rawBody === '') {
    http_response_code(400);
    echo json_encode(['error' => 'Empty request body']);
    exit;
}

$expectedSig = hash('sha256', $timestamp . $rawBody . SMARTPONIC_HMAC_SECRET);
if (!hash_equals($expectedSig, $signature)) {
    http_response_code(401);
    echo json_encode(['error' => 'Invalid signature']);
    exit;
}

// ──────────────────────────────────────────────
// 3. Parse request
// ──────────────────────────────────────────────
$data = json_decode($rawBody, true);
if ($data === null || !isset($data['action'])) {
    http_response_code(400);
    echo json_encode(['error' => 'Invalid JSON or missing action']);
    exit;
}

$action = $data['action'];

try {
    $db = getDb();

    switch ($action) {

        // ──────────────────────────────────────────
        case 'get_pending':
            $hwId   = $data['hardware_id'] ?? '';
            $limit  = isset($data['limit']) ? (int)$data['limit'] : 5;
            $filter = $data['status_filter'] ?? 'approved';

            if (!preg_match('/^[0-9A-F]{16}$/', $hwId)) {
                http_response_code(400);
                echo json_encode(['error' => 'Invalid hardware_id']);
                break;
            }

            if ($limit < 1) $limit = 1;
            if ($limit > 20) $limit = 20;

            $stmt = $db->prepare(
                'SELECT id, relay_id, action
                 FROM relay_commands
                 WHERE hardware_id = ? AND status = ?
                 ORDER BY created_at ASC
                 LIMIT ?'
            );
            $stmt->execute([$hwId, $filter, $limit]);
            $rows = $stmt->fetchAll();

            echo json_encode(['pending' => $rows]);
            break;

        // ──────────────────────────────────────────
        case 'mark_sent':
            $cmdId = $data['command_id'] ?? 0;

            if ($cmdId <= 0) {
                http_response_code(400);
                echo json_encode(['error' => 'Invalid command_id']);
                break;
            }

            $stmt = $db->prepare(
                'UPDATE relay_commands SET status = ? WHERE id = ? AND status IN (?, ?)'
            );
            $stmt->execute(['sent', $cmdId, 'pending', 'approved']);

            if ($stmt->rowCount() > 0) {
                echo json_encode(['status' => 'ok']);
            } else {
                echo json_encode(['status' => 'not_found']);
            }
            break;

        // ──────────────────────────────────────────
        case 'ack':
            $cmdId  = $data['command_id'] ?? 0;
            $status = $data['status'] ?? 'done';
            $msg    = $data['message'] ?? '';

            if ($cmdId <= 0) {
                http_response_code(400);
                echo json_encode(['error' => 'Invalid command_id']);
                break;
            }

            if (!in_array($status, ['done', 'failed'], true)) {
                $status = 'done';
            }

            $stmt = $db->prepare(
                'UPDATE relay_commands SET status = ?, result_message = ? WHERE id = ?'
            );
            $stmt->execute([$status, $msg, $cmdId]);

            echo json_encode(['status' => 'ok']);
            break;

        // ──────────────────────────────────────────
        default:
            http_response_code(400);
            echo json_encode(['error' => 'Unknown action']);
            break;
    }

} catch (PDOException $e) {
    http_response_code(500);
    echo json_encode(['error' => 'Database error']);
    error_log('SmartPonic control_queue DB error: ' . $e->getMessage());
} catch (Throwable $e) {
    http_response_code(500);
    echo json_encode(['error' => 'Internal server error']);
    error_log('SmartPonic control_queue error: ' . $e->getMessage());
}
