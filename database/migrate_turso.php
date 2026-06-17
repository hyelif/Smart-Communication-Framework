<?php
/**
 * SmartPonic — Turso Schema Migration Script
 *
 * Runs the schema SQL against Turso via the HTTP API.
 * Handles multi-statement triggers with BEGIN...END blocks.
 *
 * Usage: php database/migrate_turso.php
 */

require __DIR__ . '/../dashboard/vendor/autoload.php';

$dotenv = Dotenv\Dotenv::createImmutable(__DIR__ . '/../dashboard');
$dotenv->load();

$baseUrl   = rtrim($_ENV['TURSO_DATABASE_URL'] ?? '', '/');
$authToken = $_ENV['TURSO_AUTH_TOKEN'] ?? '';

if (str_starts_with($baseUrl, 'libsql://')) {
    $baseUrl = 'https://' . substr($baseUrl, 9);
}

if (!$authToken) {
    die("Error: TURSO_AUTH_TOKEN not set in .env\n");
}

echo "Connecting to: $baseUrl\n";

/**
 * Send a single SQL statement to Turso.
 */
function executeSql(string $sql, string $baseUrl, string $authToken): void
{
    $url = $baseUrl . '/v2/pipeline';

    $payload = json_encode([
        'requests' => [
            [
                'type' => 'execute',
                'stmt' => [
                    'sql' => $sql,
                    'args' => [],
                ],
            ],
            ['type' => 'close'],
        ],
    ]);

    $ch = curl_init($url);
    curl_setopt_array($ch, [
        CURLOPT_POST => true,
        CURLOPT_HTTPHEADER => [
            'Content-Type: application/json',
            'Authorization: Bearer ' . $authToken,
        ],
        CURLOPT_POSTFIELDS => $payload,
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_TIMEOUT => 30,
    ]);

    $response = curl_exec($ch);
    $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);

    if ($httpCode !== 200) {
        echo "  HTTP $httpCode: " . substr($response, 0, 200) . "\n";
        echo "  SQL: " . substr(str_replace("\n", " ", $sql), 0, 100) . "\n";
        throw new RuntimeException("HTTP $httpCode");
    }

    $json = json_decode($response, true);
    $results = $json['results'] ?? [];
    foreach ($results as $result) {
        if (isset($result['error'])) {
            $msg = $result['error']['message'] ?? json_encode($result['error']);
            echo "  SQL Error: $msg\n";
            echo "  SQL: " . substr(str_replace("\n", " ", $sql), 0, 100) . "\n";
            throw new RuntimeException($msg);
        }
    }
}

/**
 * Split SQL into individual statements, respecting BEGIN...END blocks.
 */
function splitSql(string $sql): array
{
    // Remove PHP tag if present
    $sql = preg_replace('/^<\?php\s*/i', '', $sql);

    $statements = [];
    $current = '';
    $len = strlen($sql);
    $depth = 0;
    $inSingleQuote = false;
    $inDoubleQuote = false;
    $inLineComment = false;
    $inBlockComment = false;

    for ($i = 0; $i < $len; $i++) {
        $ch = $sql[$i];
        $next = $i + 1 < $len ? $sql[$i + 1] : '';

        // Line comments
        if (!$inBlockComment && !$inSingleQuote && !$inDoubleQuote && $ch === '-' && $next === '-') {
            $inLineComment = true;
            $current .= $ch;
            continue;
        }
        if ($inLineComment) {
            $current .= $ch;
            if ($ch === "\n") $inLineComment = false;
            continue;
        }

        // Block comments
        if (!$inLineComment && !$inSingleQuote && !$inDoubleQuote && $ch === '/' && $next === '*') {
            $inBlockComment = true;
            $current .= '/*';
            $i++;
            continue;
        }
        if ($inBlockComment && $ch === '*' && $next === '/') {
            $inBlockComment = false;
            $current .= '*/';
            $i++;
            continue;
        }
        if ($inBlockComment) { $current .= $ch; continue; }

        // String literals
        if (!$inLineComment && !$inBlockComment) {
            if ($ch === "'" && !$inDoubleQuote) { $inSingleQuote = !$inSingleQuote; $current .= $ch; continue; }
            if ($ch === '"' && !$inSingleQuote) { $inDoubleQuote = !$inDoubleQuote; $current .= $ch; continue; }
        }

        // Track BEGIN/END depth (case-insensitive, whole words)
        if (!$inSingleQuote && !$inDoubleQuote && !$inLineComment && !$inBlockComment) {
            // Check for BEGIN (5 chars, followed by non-letter or end of string)
            if ($i + 5 <= $len && strtoupper(substr($sql, $i, 5)) === 'BEGIN') {
                $after = $i + 5 < $len ? $sql[$i + 5] : ' ';
                if (!preg_match('/[a-zA-Z0-9_]/', $after)) {
                    $depth++;
                }
            }
            // Check for END (3 chars, followed by non-letter or end of string)
            if ($i + 3 <= $len && strtoupper(substr($sql, $i, 3)) === 'END') {
                $after = $i + 3 < $len ? $sql[$i + 3] : ' ';
                if (!preg_match('/[a-zA-Z0-9_]/', $after)) {
                    $depth--;
                }
            }
        }

        // Semicolon at depth 0 = statement boundary
        if ($ch === ';' && $depth <= 0 && !$inSingleQuote && !$inDoubleQuote && !$inLineComment && !$inBlockComment) {
            $s = trim($current);
            if ($s && !str_starts_with($s, '--') && !str_starts_with($s, '/*')) {
                $statements[] = $s;
            }
            $current = '';
            continue;
        }

        $current .= $ch;
    }

    // Last statement
    $s = trim($current);
    if ($s && !str_starts_with($s, '--') && !str_starts_with($s, '/*')) {
        $statements[] = $s;
    }

    return $statements;
}

// ─── Main ──────────────────────────────────────────

$schemaFile = __DIR__ . '/schema_turso.sql';
$seedFile   = __DIR__ . '/seed_turso.sql';

if (!file_exists($schemaFile)) {
    die("Error: schema file not found at $schemaFile\n");
}

echo "Reading schema...\n";
$schema = file_get_contents($schemaFile);
$statements = splitSql($schema);
echo "Found " . count($statements) . " statements\n\n";

$success = 0;
$failed = 0;

foreach ($statements as $i => $stmt) {
    $preview = substr(str_replace("\n", " ", $stmt), 0, 80);
    echo "  [" . ($i + 1) . "/" . count($statements) . "] ";

    try {
        executeSql($stmt, $baseUrl, $authToken);
        echo "OK — $preview\n";
        $success++;
    } catch (\Exception $e) {
        echo "FAIL — $preview\n";
        echo "       " . $e->getMessage() . "\n";
        $failed++;
    }
}

echo "\n─── Schema: $success succeeded, $failed failed ───\n";

// ─── Seed data ──────────────────────────────────────

if (file_exists($seedFile)) {
    echo "\nReading seed data...\n";
    $seed = file_get_contents($seedFile);
    $seedStatements = splitSql($seed);
    echo "Found " . count($seedStatements) . " seed statements\n\n";

    $seedSuccess = 0;
    $seedFailed = 0;

    foreach ($seedStatements as $i => $stmt) {
        $preview = substr(str_replace("\n", " ", $stmt), 0, 80);
        echo "  [" . ($i + 1) . "/" . count($seedStatements) . "] ";

        try {
            executeSql($stmt, $baseUrl, $authToken);
            echo "OK — $preview\n";
            $seedSuccess++;
        } catch (\Exception $e) {
            echo "FAIL — $preview\n";
            echo "       " . $e->getMessage() . "\n";
            $seedFailed++;
        }
    }

    echo "\n─── Seed: $seedSuccess succeeded, $seedFailed failed ───\n";
}

// ─── Verify ─────────────────────────────────────────

echo "\n─── Verifying tables ───\n";

$url = $baseUrl . '/v2/pipeline';
$payload = json_encode([
    'requests' => [
        ['type' => 'execute', 'stmt' => ['sql' => "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name", 'args' => []]],
        ['type' => 'close'],
    ],
]);

$ch = curl_init($url);
curl_setopt_array($ch, [
    CURLOPT_POST => true,
    CURLOPT_HTTPHEADER => [
        'Content-Type: application/json',
        'Authorization: Bearer ' . $authToken,
    ],
    CURLOPT_POSTFIELDS => $payload,
    CURLOPT_RETURNTRANSFER => true,
    CURLOPT_TIMEOUT => 15,
]);
$response = curl_exec($ch);
$httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
curl_close($ch);

if ($httpCode === 200) {
    $json = json_decode($response, true);
    $results = $json['results'] ?? [];
    foreach ($results as $result) {
        if (isset($result['response']['result']['rows'])) {
            $rows = $result['response']['result']['rows'];
            $cols = $result['response']['result']['cols'];
            echo "Tables in database:\n";
            foreach ($rows as $row) {
                echo "  - " . $row[0]['value'] . "\n";
            }
            echo "\nTotal: " . count($rows) . " tables\n";
        }
    }
} else {
    echo "Verify failed: HTTP $httpCode\n";
}

echo "\nDone!\n";
