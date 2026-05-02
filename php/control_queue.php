<?php
// control_queue.php
// HQ->PHP command queue endpoint (signed). HQ polls pending relay commands and posts acknowledgements.

require_once 'security_config.php';

header('Content-Type: application/json');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, X-API-Key, X-Timestamp, X-Signature');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit;
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['error' => 'Method not allowed']);
    exit;
}

require_once 'db.php';
require_once 'control_lib.php';

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

$raw = file_get_contents('php://input');
verifySignedRequest($raw);
$payload = json_decode($raw, true);
if (!is_array($payload)) {
    respondWithJsonError(400, 'Invalid JSON payload');
}

$action = isset($payload['action']) ? strtolower(trim((string) $payload['action'])) : '';
if ($action === '') {
    respondWithJsonError(400, 'action is required');
}

try {
    if ($action === 'get_pending') {
        $nodeId = isset($payload['node_id']) ? (int) $payload['node_id'] : 0;
        if ($nodeId <= 0) {
            throw new InvalidArgumentException('node_id is required');
        }

        $limit = isset($payload['limit']) ? (int) $payload['limit'] : 3;
        $markSent = isset($payload['mark_sent']) ? (bool) $payload['mark_sent'] : true;

        $pending = fetchPendingRelayCommands($pdo, $nodeId, $limit);
        if ($markSent) {
            foreach ($pending as $cmd) {
                markRelayCommandSent($pdo, (int) $cmd['id']);
            }
        }

        echo json_encode([
            'status' => 'success',
            'node_id' => $nodeId,
            'pending' => $pending,
        ]);
        exit;
    }

    if ($action === 'ack') {
        $commandId = isset($payload['command_id']) ? (int) $payload['command_id'] : 0;
        $status = isset($payload['status']) ? strtolower(trim((string) $payload['status'])) : '';
        $message = isset($payload['message']) ? trim((string) $payload['message']) : null;

        if ($commandId <= 0) {
            throw new InvalidArgumentException('command_id is required');
        }
        if (!in_array($status, ['done', 'failed'], true)) {
            throw new InvalidArgumentException('status must be done|failed');
        }

        $ok = markRelayCommandDone($pdo, $commandId, $status, $message);
        echo json_encode([
            'status' => 'success',
            'updated' => $ok,
            'command_id' => $commandId,
        ]);
        exit;
    }

    if ($action === 'mark_sent') {
        $commandId = isset($payload['command_id']) ? (int) $payload['command_id'] : 0;
        if ($commandId <= 0) {
            throw new InvalidArgumentException('command_id is required');
        }

        $ok = markRelayCommandSent($pdo, $commandId);
        echo json_encode([
            'status' => 'success',
            'updated' => $ok,
            'command_id' => $commandId,
        ]);
        exit;
    }

    respondWithJsonError(400, 'Unsupported action');
} catch (Exception $e) {
    respondWithJsonError(500, 'Failed to process control action: ' . $e->getMessage());
}
