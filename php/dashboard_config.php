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

date_default_timezone_set('Asia/Kuala_Lumpur');

$nodeId = isset($_GET['node_id']) ? (int) $_GET['node_id'] : 1;

try {
    $snapshot = exportConfigSnapshot($pdo, $nodeId);
    $filename = sprintf('smartponic_node_%d_config_%s.json', $nodeId, date('Ymd_His'));

    header('Content-Disposition: attachment; filename="' . $filename . '"');
    echo json_encode($snapshot, JSON_PRETTY_PRINT);
} catch (Exception $e) {
    http_response_code(500);
    echo json_encode(['error' => 'Failed to export config snapshot: ' . $e->getMessage()]);
}
