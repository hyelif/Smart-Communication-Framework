<?php

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
    echo 'Method not allowed';
    exit;
}

require_once 'db.php';
require_once 'dashboard_store.php';

date_default_timezone_set('Asia/Kuala_Lumpur');

$requestedNode = isset($_GET['node_id']) ? trim((string) $_GET['node_id']) : '1';
$limit = isset($_GET['limit']) ? max(10, min(5000, (int) $_GET['limit'])) : 500;
$exportAll = isset($_GET['all']) && $_GET['all'] === '1';
$dateFrom = isset($_GET['date_from']) && $_GET['date_from'] !== '' ? trim((string) $_GET['date_from']) . ' 00:00:00' : null;
$dateTo = isset($_GET['date_to']) && $_GET['date_to'] !== '' ? trim((string) $_GET['date_to']) . ' 23:59:59' : null;
$requestedTypes = isset($_GET['sensor_types']) ? array_filter(array_map('trim', explode(',', (string) $_GET['sensor_types']))) : [];

$sensorConfig = sensorDefinitions();

try {
    $requestedKeys = [];
    foreach ($requestedTypes as $type) {
        foreach ($sensorConfig as $key => $meta) {
            if (strcasecmp($type, $key) === 0 || strcasecmp($type, $meta['label']) === 0) {
                $requestedKeys[] = $key;
            }
        }
    }

    if (!$requestedKeys) {
        $requestedKeys = array_keys($sensorConfig);
    }

    $unionParts = [];
    $params = [];
    $index = 0;

    foreach ($requestedKeys as $sensorKey) {
        $meta = $sensorConfig[$sensorKey];
        $nodeFilter = '';
        $fromFilter = '';
        $toFilter = '';
        $nodeParam = ':node_id_' . $index;
        $fromParam = ':date_from_' . $index;
        $toParam = ':date_to_' . $index;

        if ($requestedNode !== 'all') {
            $nodeFilter = " AND d.node_id = {$nodeParam}";
            $params[$nodeParam] = max(1, (int) $requestedNode);
        }

        if ($dateFrom !== null) {
            $fromFilter = " AND d.created_at >= {$fromParam}";
            $params[$fromParam] = $dateFrom;
        }

        if ($dateTo !== null) {
            $toFilter = " AND d.created_at <= {$toParam}";
            $params[$toParam] = $dateTo;
        }

        $unionParts[] = "
            SELECT sr.id AS reading_id,
                   sr.node_id,
                   sr.rssi,
                   sr.snr,
                   d.pin_number,
                   '{$meta['label']}' AS sensor_type,
                   d.value,
                   d.created_at
            FROM {$meta['table']} d
            INNER JOIN sensor_readings sr ON sr.id = d.reading_id
            WHERE 1 = 1{$nodeFilter}{$fromFilter}{$toFilter}
        ";
        $index++;
    }

    $sql = implode(' UNION ALL ', $unionParts) . "
        ORDER BY created_at DESC, reading_id DESC
    ";

    if (!$exportAll) {
        $sql .= " LIMIT {$limit}";
    }

    $stmt = $pdo->prepare($sql);
    $stmt->execute($params);
    $rows = $stmt->fetchAll();

    $filename = sprintf(
        'smartponic_export_%s.csv',
        date('Ymd_His')
    );

    header('Content-Type: text/csv; charset=utf-8');
    header('Content-Disposition: attachment; filename="' . $filename . '"');

    $output = fopen('php://output', 'w');
    fwrite($output, "\xEF\xBB\xBF");

    fputcsv($output, [
        'reading_id',
        'node_id',
        'sensor_type',
        'pin_number',
        'value',
        'rssi',
        'snr',
        'created_at'
    ]);

    foreach ($rows as $row) {
        fputcsv($output, [
            $row['reading_id'],
            $row['node_id'],
            $row['sensor_type'],
            $row['pin_number'],
            $row['value'],
            $row['rssi'],
            $row['snr'],
            $row['created_at'],
        ]);
    }

    fclose($output);
} catch (Exception $e) {
    http_response_code(500);
    header('Content-Type: text/plain; charset=utf-8');
    echo 'Export failed: ' . $e->getMessage();
}
