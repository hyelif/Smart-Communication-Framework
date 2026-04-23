<?php

header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type');
header('Cache-Control: no-store, no-cache, must-revalidate, max-age=0');
header('Pragma: no-cache');
header('Expires: 0');

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
require_once 'dashboard_store.php';
require_once 'data_policy.php';

date_default_timezone_set('Asia/Kuala_Lumpur');

$payload = json_decode(file_get_contents('php://input'), true);
if (!is_array($payload)) {
    http_response_code(400);
    echo json_encode(['error' => 'Invalid JSON payload']);
    exit;
}

$action = isset($payload['action']) ? trim((string) $payload['action']) : '';
$nodeId = isset($payload['node_id']) ? (int) $payload['node_id'] : 1;

try {
    if ($action === 'save_settings') {
        $settings = is_array($payload['settings'] ?? null) ? $payload['settings'] : [];
        if (isset($settings['retention_policy']) && !array_key_exists($settings['retention_policy'], allowedRetentionPolicies())) {
            throw new InvalidArgumentException('Unsupported retention policy');
        }

        $saved = saveDashboardSettings($pdo, $settings);
        echo json_encode([
            'status' => 'success',
            'message' => 'Dashboard settings saved',
            'settings' => $saved,
        ]);
        exit;
    }

    if ($action === 'save_profiles') {
        $profiles = is_array($payload['profiles'] ?? null) ? $payload['profiles'] : [];
        $saved = saveSensorProfiles($pdo, $nodeId, $profiles);
        echo json_encode([
            'status' => 'success',
            'message' => 'Sensor profiles saved',
            'profiles' => $saved,
        ]);
        exit;
    }

    if ($action === 'import_snapshot') {
        $snapshot = is_array($payload['snapshot'] ?? null) ? $payload['snapshot'] : [];
        $imported = importConfigSnapshot($pdo, $nodeId, $snapshot);
        echo json_encode([
            'status' => 'success',
            'message' => 'Configuration snapshot imported',
            'snapshot' => $imported,
        ]);
        exit;
    }

    if ($action === 'acknowledge_alert') {
        $sensorKey = isset($payload['sensor_key']) ? trim((string) $payload['sensor_key']) : '';
        if ($sensorKey === '') {
            throw new InvalidArgumentException('sensor_key is required');
        }
        $result = acknowledgeAlert($pdo, $nodeId, $sensorKey);
        echo json_encode([
            'status' => 'success',
            'message' => 'Alert acknowledged',
            'affected' => $result['affected'],
        ]);
        exit;
    }

    if ($action === 'resolve_alert') {
        $sensorKey = isset($payload['sensor_key']) ? trim((string) $payload['sensor_key']) : '';
        if ($sensorKey === '') {
            throw new InvalidArgumentException('sensor_key is required');
        }
        $result = resolveAlert($pdo, $nodeId, $sensorKey);
        echo json_encode([
            'status' => 'success',
            'message' => 'Alert resolved',
            'affected' => $result['affected'],
        ]);
        exit;
    }

    if ($action === 'get_alerts') {
        $alerts = getActiveAlerts($pdo, $nodeId);
        echo json_encode([
            'status' => 'success',
            'alerts' => $alerts,
        ]);
        exit;
    }

    if ($action === 'get_profiles') {
        $profiles = getSensorProfiles($pdo, $nodeId);
        echo json_encode([
            'status' => 'success',
            'profiles' => $profiles,
        ]);
        exit;
    }

    if ($action === 'sync_profiles') {
        $profiles = is_array($payload['profiles'] ?? null) ? $payload['profiles'] : [];
        $saved = saveSensorProfiles($pdo, $nodeId, $profiles);
        echo json_encode([
            'status' => 'success',
            'message' => 'Profiles synced',
            'profiles' => $saved,
        ]);
        exit;
    }

    if ($action === 'save_node_location') {
        $latitude = isset($payload['latitude']) ? (float) $payload['latitude'] : null;
        $longitude = isset($payload['longitude']) ? (float) $payload['longitude'] : null;
        $distance = isset($payload['distance']) ? (float) $payload['distance'] : null;
        $saved = saveNodeLocation($pdo, $nodeId, $latitude, $longitude, $distance);
        echo json_encode([
            'status' => 'success',
            'message' => 'Node location saved',
            'node' => $saved,
        ]);
        exit;
    }

    throw new InvalidArgumentException('Unsupported action');
} catch (Exception $e) {
    http_response_code(500);
    echo json_encode(['error' => 'Failed to process dashboard action: ' . $e->getMessage()]);
}
