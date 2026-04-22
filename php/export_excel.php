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

function xmlEscape(string $value): string
{
    return htmlspecialchars($value, ENT_QUOTES | ENT_XML1, 'UTF-8');
}

function xmlCell(string $type, string $value): string
{
    return '<Cell><Data ss:Type="' . $type . '">' . xmlEscape($value) . '</Data></Cell>';
}

function xmlWorksheet(string $sheetName, array $rows): string
{
    $xml = '<Worksheet ss:Name="' . xmlEscape($sheetName) . '"><Table>';
    $headers = ['reading_id', 'node_id', 'pin_number', 'value', 'rssi', 'snr', 'created_at'];

    $xml .= '<Row>';
    foreach ($headers as $header) {
        $xml .= xmlCell('String', $header);
    }
    $xml .= '</Row>';

    foreach ($rows as $row) {
        $xml .= '<Row>';
        $xml .= xmlCell('Number', (string) $row['reading_id']);
        $xml .= xmlCell('Number', (string) $row['node_id']);
        $xml .= xmlCell('Number', (string) $row['pin_number']);
        $xml .= xmlCell('String', (string) $row['value']);
        $xml .= xmlCell('String', $row['rssi'] === null ? '' : (string) $row['rssi']);
        $xml .= xmlCell('String', $row['snr'] === null ? '' : (string) $row['snr']);
        $xml .= xmlCell('String', (string) $row['created_at']);
        $xml .= '</Row>';
    }

    if (!$rows) {
        $xml .= '<Row>' . xmlCell('String', 'No data') . '</Row>';
    }

    $xml .= '</Table></Worksheet>';
    return $xml;
}

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

    $sheets = [];

    foreach ($requestedKeys as $sensorKey) {
        $meta = $sensorConfig[$sensorKey];
        $sql = "
            SELECT sr.id AS reading_id,
                   sr.node_id,
                   sr.rssi,
                   sr.snr,
                   d.pin_number,
                   d.value,
                   d.created_at
            FROM {$meta['table']} d
            INNER JOIN sensor_readings sr ON sr.id = d.reading_id
            WHERE 1 = 1
        ";
        $params = [];

        if ($requestedNode !== 'all') {
            $sql .= " AND d.node_id = :node_id";
            $params[':node_id'] = max(1, (int) $requestedNode);
        }

        if ($dateFrom !== null) {
            $sql .= " AND d.created_at >= :date_from";
            $params[':date_from'] = $dateFrom;
        }

        if ($dateTo !== null) {
            $sql .= " AND d.created_at <= :date_to";
            $params[':date_to'] = $dateTo;
        }

        $sql .= " ORDER BY d.created_at DESC, d.id DESC";

        if (!$exportAll) {
            $sql .= " LIMIT {$limit}";
        }

        $stmt = $pdo->prepare($sql);
        $stmt->execute($params);
        $sheets[$meta['label']] = $stmt->fetchAll();
    }

    $filename = sprintf('smartponic_export_%s.xls', date('Ymd_His'));

    header('Content-Type: application/vnd.ms-excel; charset=utf-8');
    header('Content-Disposition: attachment; filename="' . $filename . '"');

    echo '<?xml version="1.0"?>';
    echo '<?mso-application progid="Excel.Sheet"?>';
    echo '<Workbook xmlns="urn:schemas-microsoft-com:office:spreadsheet" ';
    echo 'xmlns:o="urn:schemas-microsoft-com:office:office" ';
    echo 'xmlns:x="urn:schemas-microsoft-com:office:excel" ';
    echo 'xmlns:ss="urn:schemas-microsoft-com:office:spreadsheet">';
    echo '<Styles><Style ss:ID="Header"><Font ss:Bold="1"/></Style></Styles>';

    foreach ($sheets as $sheetName => $rows) {
        echo xmlWorksheet($sheetName, $rows);
    }

    echo '</Workbook>';
} catch (Exception $e) {
    http_response_code(500);
    header('Content-Type: text/plain; charset=utf-8');
    echo 'Export failed: ' . $e->getMessage();
}
