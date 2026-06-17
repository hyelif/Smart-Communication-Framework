<?php
/**
 * SmartPonic — MySQL → Turso Data Migration Script
 *
 * Reads all historical data from XAMPP MySQL and writes it to Turso
 * via TursoService, preserving original IDs and timestamps.
 *
 * Usage: php database/migrate_data_to_turso.php [--dry-run]
 *   --dry-run  Show what would be migrated without writing
 */

require __DIR__ . '/../dashboard/vendor/autoload.php';

$dotenv = Dotenv\Dotenv::createImmutable(__DIR__ . '/../dashboard');
$dotenv->load();

// ─── MySQL Connection ──────────────────────────────────────────

try {
    $mysql = new PDO(
        'mysql:host=127.0.0.1;port=3306;dbname=smartponic;charset=utf8mb4',
        'root',
        '',
        [
            PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
        ]
    );
    echo "✓ MySQL connected (smartponic)\n";
} catch (PDOException $e) {
    die("✗ MySQL connection failed: " . $e->getMessage() . "\n");
}

// ─── Turso Connection ──────────────────────────────────────────

$baseUrl   = rtrim($_ENV['TURSO_DATABASE_URL'] ?? '', '/');
$authToken = $_ENV['TURSO_AUTH_TOKEN'] ?? '';

if (str_starts_with($baseUrl, 'libsql://')) {
    $baseUrl = 'https://' . substr($baseUrl, 9);
}

if (!$authToken) {
    die("✗ TURSO_AUTH_TOKEN not set in .env\n");
}

echo "✓ Turso connected: $baseUrl\n";

// ─── CLI options ───────────────────────────────────────────────

$dryRun = in_array('--dry-run', $argv ?? [], true);
if ($dryRun) echo "⚠ DRY-RUN MODE — no data will be written\n\n";

/**
 * Execute a SQL statement on Turso via the HTTP pipeline API.
 */
function tursoExec(string $sql, array $params = []): array
{
    global $baseUrl, $authToken;

    $args = [];
    foreach ($params as $p) {
        if (is_null($p)) {
            $args[] = ['type' => 'null', 'value' => null];
        } else {
            $args[] = ['type' => 'text', 'value' => (string)$p];
        }
    }

    $payload = json_encode([
        'requests' => [
            [
                'type' => 'execute',
                'stmt' => ['sql' => $sql, 'args' => $args],
            ],
            ['type' => 'close'],
        ],
    ]);

    $ch = curl_init($baseUrl . '/v2/pipeline');
    curl_setopt_array($ch, [
        CURLOPT_POST           => true,
        CURLOPT_HTTPHEADER     => [
            'Content-Type: application/json',
            'Authorization: Bearer ' . $authToken,
        ],
        CURLOPT_POSTFIELDS     => $payload,
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_TIMEOUT        => 30,
    ]);

    $response = curl_exec($ch);
    $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);

    if ($httpCode !== 200) {
        throw new RuntimeException("Turso HTTP $httpCode: " . substr($response, 0, 300));
    }

    $json = json_decode($response, true);
    $results = $json['results'] ?? [];
    foreach ($results as $result) {
        if (isset($result['error'])) {
            $msg = $result['error']['message'] ?? json_encode($result['error']);
            throw new RuntimeException("Turso SQL error: $msg");
        }
    }

    // Return response for queries
    foreach ($results as $result) {
        if (isset($result['response']['result'])) {
            return $result['response']['result'];
        }
    }

    return [];
}

/**
 * Count rows currently in a Turso table.
 */
function tursoCount(string $table): int
{
    $res = tursoExec("SELECT COUNT(*) as cnt FROM {$table}");
    return (int)($res['rows'][0][0]['value'] ?? 0);
}

/**
 * Truncate a Turso table (delete all rows and reset auto-increment).
 */
function tursoTruncate(string $table): void
{
    tursoExec("DELETE FROM {$table}");
    // SQLite auto-increment reset
    tursoExec("DELETE FROM sqlite_sequence WHERE name = ?", [$table]);
}

// ─── Migration ─────────────────────────────────────────────────

echo "\n=== Starting Migration ===\n\n";

$tables = [
    'sensor_profiles',
    'nodes',
    'sensor_readings',
    'sensor_data',
    'invalid_sensor_data',
    'relay_commands',
    'alerts',
    'pending_approvals',
    'dashboard_settings',
    'communication_health',
    'telegram_bot_state',
    'telegram_alert_state',
];

foreach ($tables as $table) {
    echo "─── {$table} ───\n";

    // 1. Count rows in MySQL
    $mysqlCount = (int) $mysql->query("SELECT COUNT(*) as cnt FROM {$table}")->fetch()['cnt'];
    echo "  MySQL: {$mysqlCount} rows\n";

    if ($mysqlCount === 0) {
        echo "  → Skipped (empty)\n\n";
        continue;
    }

    // 2. Count existing rows in Turso
    $tursoBefore = tursoCount($table);
    echo "  Turso (before): {$tursoBefore} rows\n";

    if ($dryRun) {
        echo "  → Would migrate {$mysqlCount} rows (DRY RUN)\n\n";
        continue;
    }

    // 3. Truncate existing data in Turso (to avoid duplicates)
    if ($tursoBefore > 0) {
        echo "  Truncating existing data...\n";
        tursoTruncate($table);
    }

    // 4. Fetch all rows from MySQL
    $rows = $mysql->query("SELECT * FROM {$table}")->fetchAll();

    // 5. Insert into Turso
    $inserted = 0;
    $errors   = 0;

    foreach ($rows as $row) {
        // Convert column names to match Turso schema
        $tursoRow = remapColumns($table, $row);

        try {
            insertIntoTurso($table, $tursoRow);
            $inserted++;
        } catch (\Exception $e) {
            echo "  ✗ Error on row: " . ($row['id'] ?? '?') . " — " . $e->getMessage() . "\n";
            $errors++;
        }

        // Progress indicator
        if ($inserted % 100 === 0) {
            echo "  ... {$inserted}/{$mysqlCount}\n";
        }
    }

    $tursoAfter = tursoCount($table);
    echo "  ✓ Inserted: {$inserted}, Errors: {$errors}\n";
    echo "  Turso (after): {$tursoAfter} rows\n\n";
}

echo "=== Migration Complete ===\n";

// ─── Verify ────────────────────────────────────────────────────

echo "\n=== Verification ===\n\n";

$verifyTables = ['nodes', 'sensor_readings', 'sensor_data'];
foreach ($verifyTables as $table) {
    $mysqlCnt  = (int) $mysql->query("SELECT COUNT(*) as cnt FROM {$table}")->fetch()['cnt'];
    $tursoCnt  = tursoCount($table);
    $match     = $mysqlCnt === $tursoCnt ? '✓' : '✗';
    echo "  {$match} {$table}: MySQL={$mysqlCnt} Turso={$tursoCnt}\n";
}

echo "\nDone!\n";

// ═══════════════════════════════════════════════════════════════
//  COLUMN MAPPING HELPERS
// ═══════════════════════════════════════════════════════════════

/**
 * Remap MySQL column names to Turso schema names where they differ.
 */
function remapColumns(string $table, array $row): array
{
    switch ($table) {
        case 'sensor_profiles':
            // MySQL: sensor_name, display_name, color, ...
            // Turso: sensor_key, label, accent, ...
            return [
                'sensor_key'      => $row['sensor_name'] ?? $row['sensor_key'] ?? '',
                'label'           => $row['display_name'] ?? $row['label'] ?? '',
                'unit'            => $row['unit'] ?? '',
                'family'          => $row['family'] ?? '',
                'accent'          => $row['color'] ?? $row['accent'] ?? '#9ecaff',
                'threshold_min'   => $row['threshold_min'] ?? null,
                'threshold_max'   => $row['threshold_max'] ?? null,
                'calibration_a'   => $row['calibration_a'] ?? 1.0,
                'calibration_b'   => $row['calibration_b'] ?? 0.0,
                'calibration_c'   => $row['calibration_c'] ?? 0.0,
                'cal_label_a'     => $row['cal_label_a'] ?? 'Scale',
                'cal_label_b'     => $row['cal_label_b'] ?? 'Offset',
                'cal_label_c'     => $row['cal_label_c'] ?? 'Reserve',
                'updated_at'      => $row['updated_at'] ?? date('Y-m-d H:i:s'),
            ];

        case 'nodes':
            return [
                'hardware_id' => $row['hardware_id'],
                'name'        => $row['name'] ?? null,
                'location'    => $row['location'] ?? null,
                'first_seen'  => $row['first_seen'] ?? null,
                'last_seen'   => $row['last_seen'] ?? null,
            ];

        case 'sensor_readings':
            return [
                'hardware_id' => $row['hardware_id'],
                'rssi'        => $row['rssi'] ?? null,
                'snr'         => $row['snr'] ?? null,
                'event_type'  => $row['event_type'] ?? 'telemetry',
                'priority'    => $row['priority'] ?? 'LOW',
                'report_mode' => $row['report_mode'] ?? 'NORMAL',
                'created_at'  => $row['created_at'] ?? null,
            ];

        case 'sensor_data':
            return [
                'reading_id' => $row['reading_id'],
                'pin'        => $row['pin'] ?? 0,
                'sensor'     => $row['sensor'],
                'value'      => $row['value'],
                'created_at' => $row['created_at'] ?? null,
            ];

        case 'invalid_sensor_data':
            return [
                'hardware_id' => $row['hardware_id'],
                'pin'         => $row['pin'],
                'sensor'      => $row['sensor'],
                'value'       => $row['value'],
                'reason'      => $row['reason'] ?? null,
                'created_at'  => $row['created_at'] ?? null,
            ];

        case 'relay_commands':
            return [
                'hardware_id' => $row['hardware_id'],
                'relay_id'    => $row['relay_id'],
                'action'      => $row['action'] ?? 'OFF',
                'status'      => $row['status'] ?? 'pending',
                'created_at'  => $row['created_at'] ?? null,
                'updated_at'  => $row['updated_at'] ?? null,
            ];

        case 'alerts':
            return [
                'hardware_id' => $row['hardware_id'],
                'sensor_key'  => $row['sensor_key'] ?? $row['sensor'] ?? '',
                'severity'    => $row['severity'] ?? 'warning',
                'message'     => $row['message'] ?? '',
                'status'      => $row['status'] ?? 'active',
                'created_at'  => $row['created_at'] ?? null,
                'updated_at'  => $row['updated_at'] ?? null,
            ];

        case 'pending_approvals':
            return [
                'command_id'   => $row['command_id'] ?? 0,
                'hardware_id'  => $row['hardware_id'],
                'relay_id'     => $row['relay_id'],
                'action'       => $row['action'],
                'trigger_value' => $row['trigger_value'] ?? null,
                'status'       => $row['status'] ?? 'pending',
                'chat_id'      => $row['chat_id'] ?? null,
                'created_at'   => $row['created_at'] ?? null,
                'expires_at'   => $row['expires_at'] ?? null,
            ];

        case 'dashboard_settings':
            return [
                'setting_key'   => $row['setting_key'],
                'setting_value' => $row['setting_value'],
                'updated_at'    => $row['updated_at'] ?? null,
            ];

        case 'communication_health':
            return [
                'hardware_id'       => $row['hardware_id'],
                'delivery_rate'     => $row['delivery_rate'] ?? 100.0,
                'total_expected'    => $row['total_expected'] ?? 0,
                'total_received'    => $row['total_received'] ?? 0,
                'sequence_gaps'     => $row['sequence_gaps'] ?? 0,
                'freshness_seconds' => $row['freshness_seconds'] ?? 0,
                'last_rssi'         => $row['last_rssi'] ?? null,
                'last_snr'          => $row['last_snr'] ?? null,
                'updated_at'        => $row['updated_at'] ?? null,
            ];

        case 'telegram_bot_state':
            return [
                'state_key'   => $row['state_key'],
                'state_value' => $row['state_value'],
                'updated_at'  => $row['updated_at'] ?? null,
            ];

        case 'telegram_alert_state':
            return [
                'state_key'    => $row['state_key'],
                'last_sent_at' => $row['last_sent_at'] ?? null,
                'updated_at'   => $row['updated_at'] ?? null,
            ];

        default:
            return $row;
    }
}

/**
 * Build and execute an INSERT statement for a Turso table.
 * Uses explicit columns so the order doesn't matter.
 */
function insertIntoTurso(string $table, array $data): void
{
    if (empty($data)) return;

    $columns = array_keys($data);
    $placeholders = implode(',', array_fill(0, count($columns), '?'));
    $colList = implode(',', $columns);

    $sql = "INSERT INTO {$table} ({$colList}) VALUES ({$placeholders})";
    $values = array_values($data);

    tursoExec($sql, $values);
}