<?php
// Run via CLI: php telegram_poll.php --once
// Or loop:     php telegram_poll.php --loop

require_once __DIR__ . '/telegram_lib.php';

date_default_timezone_set('Asia/Kuala_Lumpur');

function argvHas(string $flag): bool
{
    global $argv;
    return in_array($flag, $argv, true);
}

function argvValue(string $prefix, ?string $default = null): ?string
{
    global $argv;
    foreach ($argv as $arg) {
        if (!is_string($arg)) {
            continue;
        }
        if (str_starts_with($arg, $prefix)) {
            return substr($arg, strlen($prefix));
        }
    }
    return $default;
}

function telegramReply(array $config, int $chatId, string $text): void
{
    telegramSendMessage($config, $chatId, $text);
}

function cmdHelp(): string
{
    return implode("\n", [
        "SmartPonic Telegram commands:",
        "/whoami - show your chat id",
        "/status [node] - latest node summary",
        "/readings [node] - latest sensor values",
        "/alerts [node] - list active/ack/resolved alerts",
        "/ack <node> <sensor_key> - acknowledge latest active alert",
        "/resolve <node> <sensor_key> - resolve latest alert",
        "/relay <node> <relay_id 0-15> <on|off> - queue relay command",
        "/queue [node] - show pending relay commands",
    ]);
}

function fetchStatus(PDO $pdo, int $nodeId): array
{
    $stmt = $pdo->prepare("
        SELECT id, created_at, rssi, snr, priority_level, report_mode, sequence_number, latitude, longitude, distance_m
        FROM sensor_readings
        WHERE node_id = :node_id
        ORDER BY created_at DESC, id DESC
        LIMIT 1
    ");
    $stmt->execute([':node_id' => $nodeId]);
    $row = $stmt->fetch();
    return $row ?: [];
}

function formatStatusMessage(PDO $pdo, int $nodeId): string
{
    $latest = fetchStatus($pdo, $nodeId);
    if (!$latest) {
        return "Node {$nodeId}: no readings yet.";
    }

    $alerts = getActiveAlerts($pdo, $nodeId);
    $activeCount = 0;
    foreach ($alerts as $a) {
        if (($a['status'] ?? '') === 'active') {
            $activeCount++;
        }
    }

    $loc = [];
    if ($latest['latitude'] !== null && $latest['longitude'] !== null) {
        $loc[] = 'Lat ' . (string) $latest['latitude'];
        $loc[] = 'Lon ' . (string) $latest['longitude'];
    }
    if ($latest['distance_m'] !== null) {
        $loc[] = 'Dist ' . (string) $latest['distance_m'] . ' m';
    }

    return implode("\n", array_filter([
        "Node {$nodeId} status",
        "Last: " . (string) $latest['created_at'],
        "Priority: " . (string) ($latest['priority_level'] ?? 'LOW') . " | Mode: " . (string) ($latest['report_mode'] ?? 'NORMAL'),
        "Seq: " . (string) ($latest['sequence_number'] === null ? '-' : $latest['sequence_number']),
        "RSSI/SNR: " . (string) ($latest['rssi'] === null ? '-' : $latest['rssi']) . " / " . (string) ($latest['snr'] === null ? '-' : $latest['snr']),
        $loc ? ("Location: " . implode(' | ', $loc)) : null,
        "Alerts: {$activeCount} active",
    ]));
}

function formatAlertsMessage(PDO $pdo, int $nodeId): string
{
    $alerts = getActiveAlerts($pdo, $nodeId);
    if (!$alerts) {
        return "Node {$nodeId}: no alert history yet.";
    }

    $lines = ["Node {$nodeId} alerts (latest first):"];
    $count = 0;
    foreach ($alerts as $a) {
        $count++;
        if ($count > 12) {
            $lines[] = "...";
            break;
        }
        $lines[] = "#{$a['id']} [" . ($a['status'] ?? '-') . "] " . ($a['sensor_key'] ?? '-') . " - " . ($a['message'] ?? '');
    }
    return implode("\n", $lines);
}

function fetchLatestReading(PDO $pdo, int $nodeId): array
{
    $stmt = $pdo->prepare("
        SELECT id, created_at, rssi, snr, priority_level, report_mode, sequence_number
        FROM sensor_readings
        WHERE node_id = :node_id
        ORDER BY created_at DESC, id DESC
        LIMIT 1
    ");
    $stmt->execute([':node_id' => $nodeId]);
    $row = $stmt->fetch();
    return $row ?: [];
}

function formatReadingsMessage(PDO $pdo, int $nodeId): string
{
    $latest = fetchLatestReading($pdo, $nodeId);
    if (!$latest) {
        return "Node {$nodeId}: no readings yet.";
    }

    $readingId = (int) $latest['id'];
    $defs = sensorDefinitions();

    $lines = [];
    $lines[] = "Node {$nodeId} readings";
    $lines[] = "Reading ID {$readingId} @ " . (string) $latest['created_at'];
    $lines[] = "Priority " . (string) ($latest['priority_level'] ?? 'LOW') . " | Mode " . (string) ($latest['report_mode'] ?? 'NORMAL');

    $sig = [];
    if ($latest['rssi'] !== null) {
        $sig[] = 'RSSI ' . (string) $latest['rssi'];
    }
    if ($latest['snr'] !== null) {
        $sig[] = 'SNR ' . (string) $latest['snr'];
    }
    if ($sig) {
        $lines[] = implode(' | ', $sig);
    }

    $lines[] = "Sensors:";
    $found = 0;
    foreach ($defs as $sensorKey => $meta) {
        $table = $meta['table'];
        $stmt = $pdo->prepare("
            SELECT pin_number, value
            FROM {$table}
            WHERE node_id = :node_id AND reading_id = :reading_id
            ORDER BY id ASC
        ");
        $stmt->execute([
            ':node_id' => $nodeId,
            ':reading_id' => $readingId,
        ]);
        $rows = $stmt->fetchAll() ?: [];
        foreach ($rows as $row) {
            $found++;
            $unit = $meta['unit'] !== 'state' ? (' ' . $meta['unit']) : '';
            $lines[] = "- {$meta['label']} (pin " . (int) $row['pin_number'] . "): " . (string) $row['value'] . $unit;
            if ($found >= 18) {
                $lines[] = "...";
                break 2;
            }
        }
    }

    if ($found === 0) {
        $lines[] = "- (no sensor rows for latest reading)";
    }

    return implode("\n", $lines);
}

function parseCommand(string $text): array
{
    $text = trim($text);
    if ($text === '') {
        return ['', []];
    }

    $parts = preg_split('/\s+/', $text);
    $cmd = strtolower($parts[0] ?? '');
    $args = array_slice($parts, 1);

    if (str_contains($cmd, '@')) {
        $cmd = strtolower(explode('@', $cmd, 2)[0]);
    }

    return [$cmd, $args];
}

function telegramFreshnessCheck(PDO $pdo, array $config): void
{
    $chatId = $config['default_alert_chat_id'] ?? null;
    if ($chatId === null) {
        return;
    }

    $warningS = max(30, (int) ($config['freshness_warning_s'] ?? 300));
    $offlineS = max($warningS, (int) ($config['freshness_offline_s'] ?? 900));

    $nodesStmt = $pdo->query("SELECT id FROM nodes ORDER BY id ASC");
    $nodes = $nodesStmt->fetchAll() ?: [];
    foreach ($nodes as $node) {
        $nodeId = (int) ($node['id'] ?? 0);
        if ($nodeId <= 0) {
            continue;
        }

        $latestStmt = $pdo->prepare("
            SELECT created_at
            FROM sensor_readings
            WHERE node_id = :node_id
            ORDER BY created_at DESC, id DESC
            LIMIT 1
        ");
        $latestStmt->execute([':node_id' => $nodeId]);
        $createdAt = $latestStmt->fetchColumn();
        if ($createdAt === false || $createdAt === null) {
            continue;
        }

        $lastTs = strtotime((string) $createdAt);
        if ($lastTs === false) {
            continue;
        }

        $ageS = time() - $lastTs;
        $offlineKey = "node:{$nodeId}:offline";
        $recoveredKey = "node:{$nodeId}:recovered";

        if ($ageS >= $offlineS) {
            if (telegramShouldSendAlert($pdo, $offlineKey, 300)) {
                $mins = (int) floor($ageS / 60);
                telegramSendMessage($config, (int) $chatId, "SmartPonic OFFLINE\nNode {$nodeId} has no fresh data for {$mins} min.\nLast: {$createdAt}");
                telegramMarkAlertSent($pdo, $offlineKey);
            }
            continue;
        }

        if ($ageS >= $warningS) {
            $staleKey = "node:{$nodeId}:stale";
            if (telegramShouldSendAlert($pdo, $staleKey, 300)) {
                $mins = (int) floor($ageS / 60);
                telegramSendMessage($config, (int) $chatId, "SmartPonic STALE\nNode {$nodeId} last update {$mins} min ago.\nLast: {$createdAt}");
                telegramMarkAlertSent($pdo, $staleKey);
            }
            continue;
        }

        $offlineSentAt = telegramGetAlertLastSentAt($pdo, $offlineKey);
        if ($offlineSentAt !== null && (time() - $offlineSentAt) < 24 * 3600) {
            if (telegramShouldSendAlert($pdo, $recoveredKey, 600)) {
                telegramSendMessage($config, (int) $chatId, "SmartPonic RECOVERED\nNode {$nodeId} is back online.\nLast: {$createdAt}");
                telegramMarkAlertSent($pdo, $recoveredKey);
            }
        }
    }
}

$config = telegramLoadConfig();
if ($config === null) {
    fwrite(STDERR, "Telegram not configured. Create php/telegram_config.php (see php/telegram_config.example.php).\n");
    exit(2);
}

$once = argvHas('--once');
$loop = argvHas('--loop') || !$once;
$debug = argvHas('--debug');
$deleteWebhook = argvHas('--delete-webhook');
$selfTest = argvHas('--self-test');
$sleepSeconds = 2;

if ($selfTest) {
    $me = telegramApiRequest($config, 'getMe', []);
    $hook = telegramApiRequest($config, 'getWebhookInfo', []);

    $meOk = is_array($me) && ($me['ok'] ?? false);
    $meHttp = is_array($me) && isset($me['http_code']) ? (int) $me['http_code'] : 0;
    $meDesc = is_array($me) && isset($me['description']) ? (string) $me['description'] : '';

    $hookOk = is_array($hook) && ($hook['ok'] ?? false);
    $hookHttp = is_array($hook) && isset($hook['http_code']) ? (int) $hook['http_code'] : 0;
    $hookDesc = is_array($hook) && isset($hook['description']) ? (string) $hook['description'] : '';

    $username = $meOk && isset($me['result']['username']) ? (string) $me['result']['username'] : '';
    $hookUrl = $hookOk && isset($hook['result']['url']) ? (string) $hook['result']['url'] : '';
    $pending = $hookOk && isset($hook['result']['pending_update_count']) ? (int) $hook['result']['pending_update_count'] : null;

    echo "Telegram self-test\n";
    echo "- getMe: " . ($meOk ? "OK" : "FAIL") . " (HTTP {$meHttp})" . ($meDesc !== '' ? " {$meDesc}" : "") . "\n";
    if ($username !== '') {
        echo "- bot: @" . $username . "\n";
    }
    echo "- getWebhookInfo: " . ($hookOk ? "OK" : "FAIL") . " (HTTP {$hookHttp})" . ($hookDesc !== '' ? " {$hookDesc}" : "") . "\n";
    echo "- webhook url: " . ($hookUrl !== '' ? $hookUrl : '(none)') . "\n";
    if ($pending !== null) {
        echo "- pending updates: {$pending}\n";
    }
    echo "- curl available: " . (function_exists('curl_init') ? "yes" : "no") . "\n";
    exit(($meOk && $hookOk) ? 0 : 1);
}

if ($deleteWebhook) {
    $resp = telegramApiRequest($config, 'deleteWebhook', ['drop_pending_updates' => 'true']);
    $ok = is_array($resp) && ($resp['ok'] ?? false);
    $httpCode = is_array($resp) && isset($resp['http_code']) ? (int) $resp['http_code'] : 0;
    $desc = is_array($resp) && isset($resp['description']) ? (string) $resp['description'] : '';
    fwrite(STDERR, ($ok ? "Webhook deleted" : "Failed to delete webhook") . " (HTTP {$httpCode}). " . $desc . "\n");
    exit($ok ? 0 : 1);
}

require_once __DIR__ . '/db.php';
require_once __DIR__ . '/dashboard_store.php';
require_once __DIR__ . '/control_lib.php';

try {
    // Prefer explicit connect for CLI so we get actionable errors.
    if (function_exists('smartponicConnect')) {
        $pdo = smartponicConnect(true);
    }
    telegramEnsureTables($pdo);
} catch (PDOException $e) {
    fwrite(STDERR, "Database error: " . $e->getMessage() . "\n");
    fwrite(STDERR, "Fix: start MySQL in XAMPP and ensure database `smartponic` exists (see php/db.php).\n");
    exit(3);
}

do {
    if ($once) {
        echo "Telegram poller: once mode (send /whoami, then run again if needed)\n";
    } elseif ($debug) {
        echo "Telegram poller: loop mode (debug enabled)\n";
    }
    $offset = telegramGetLastUpdateId($pdo) + 1;
    $resp = telegramGetUpdates($config, $offset, 25);

    if (!is_array($resp) || !($resp['ok'] ?? false)) {
        $httpCode = is_array($resp) && isset($resp['http_code']) ? (int) $resp['http_code'] : 0;
        $desc = is_array($resp) && isset($resp['description']) ? (string) $resp['description'] : '';
        $err = is_array($resp) && isset($resp['error']) ? (string) $resp['error'] : '';
        echo "Telegram getUpdates failed (HTTP {$httpCode}). " . ($desc !== '' ? $desc : $err) . "\n";
        if ($desc !== '' && str_contains(strtolower($desc), 'webhook')) {
            echo "Tip: your bot may have a webhook set. If so, remove it first.\n";
        }
        if ($once) {
            exit(1);
        }
        sleep($sleepSeconds);
        continue;
    }

    $updates = is_array($resp['result'] ?? null) ? $resp['result'] : [];
    if ($debug) {
        echo "Received updates: " . count($updates) . "\n";
    }
    if ($once && count($updates) === 0) {
        echo "No new Telegram updates received.\n";
        echo "Tip: send /whoami to the bot FIRST, then run: C:\\xampp\\php\\php.exe .\\php\\telegram_poll.php --once\n";
    }
	    foreach ($updates as $update) {
        $updateId = isset($update['update_id']) ? (int) $update['update_id'] : 0;
        if ($updateId > 0) {
            telegramSetLastUpdateId($pdo, $updateId);
        }

        $message = $update['message'] ?? null;
        if (!is_array($message)) {
            continue;
        }

        $chat = $message['chat'] ?? null;
        if (!is_array($chat) || !isset($chat['id'])) {
            continue;
        }

        $chatId = (int) $chat['id'];
        $text = isset($message['text']) ? (string) $message['text'] : '';
        [$cmd, $args] = parseCommand($text);

        if ($debug) {
            echo "Update {$updateId} chat {$chatId} cmd {$cmd}\n";
        }

        if ($cmd === '/whoami') {
            telegramReply($config, $chatId, "Your chat id: {$chatId}");
            continue;
        }

        if ($cmd === '/start' || $cmd === '/help') {
            telegramReply($config, $chatId, cmdHelp());
            continue;
        }

        if (!telegramIsAllowedChat($config, $chatId)) {
            telegramReply($config, $chatId, "Unauthorized chat. Use /whoami and add your chat id to allowed_chat_ids.");
            continue;
        }

        if ($cmd === '/status') {
            $nodeId = isset($args[0]) && ctype_digit($args[0]) ? (int) $args[0] : 1;
            telegramReply($config, $chatId, formatStatusMessage($pdo, $nodeId));
            continue;
        }

        if ($cmd === '/alerts') {
            $nodeId = isset($args[0]) && ctype_digit($args[0]) ? (int) $args[0] : 1;
            telegramReply($config, $chatId, formatAlertsMessage($pdo, $nodeId));
            continue;
        }

        if ($cmd === '/readings') {
            $nodeId = isset($args[0]) && ctype_digit($args[0]) ? (int) $args[0] : 1;
            telegramReply($config, $chatId, formatReadingsMessage($pdo, $nodeId));
            continue;
        }

        if ($cmd === '/relay') {
            $nodeId = isset($args[0]) && ctype_digit($args[0]) ? (int) $args[0] : 0;
            $relayId = isset($args[1]) && ctype_digit($args[1]) ? (int) $args[1] : -1;
            $action = isset($args[2]) ? strtoupper(trim((string) $args[2])) : '';
            $action = $action === 'ON' || $action === 'OFF' ? $action : ($action === '1' ? 'ON' : ($action === '0' ? 'OFF' : $action));

            if ($nodeId <= 0 || $relayId < 0 || $action === '') {
                telegramReply($config, $chatId, "Usage: /relay <node> <relay_id 0-15> <on|off>");
                continue;
            }

            try {
                $cmdId = createRelayCommand($pdo, $nodeId, $relayId, $action, $chatId, 'telegram');
                telegramReply($config, $chatId, "Queued relay command #{$cmdId}: node {$nodeId} relay {$relayId} {$action}. (HQ must poll control_queue.php to execute)");
            } catch (Exception $e) {
                telegramReply($config, $chatId, "Failed to queue relay command: " . $e->getMessage());
            }
            continue;
        }

        if ($cmd === '/queue') {
            $nodeId = isset($args[0]) && ctype_digit($args[0]) ? (int) $args[0] : 1;
            $pending = fetchPendingRelayCommands($pdo, $nodeId, 8);
            if (!$pending) {
                telegramReply($config, $chatId, "Node {$nodeId}: no pending relay commands.");
            } else {
                $lines = ["Node {$nodeId} pending relay commands:"];
                foreach ($pending as $c) {
                    $lines[] = "#{$c['id']} relay " . (int) $c['relay_id'] . " " . (string) $c['action'] . " @ " . (string) $c['created_at'];
                }
                telegramReply($config, $chatId, implode("\n", $lines));
            }
            continue;
        }

        if ($cmd === '/ack' || $cmd === '/resolve') {
            $nodeId = isset($args[0]) && ctype_digit($args[0]) ? (int) $args[0] : 0;
            $sensorKey = isset($args[1]) ? trim((string) $args[1]) : '';
            if ($nodeId <= 0 || $sensorKey === '') {
                telegramReply($config, $chatId, "Usage: {$cmd} <node> <sensor_key>");
                continue;
            }

            if ($cmd === '/ack') {
                $r = acknowledgeAlert($pdo, $nodeId, $sensorKey);
                telegramReply($config, $chatId, "Ack {$sensorKey} on node {$nodeId}: affected {$r['affected']} row(s).");
            } else {
                $r = resolveAlert($pdo, $nodeId, $sensorKey);
                telegramReply($config, $chatId, "Resolve {$sensorKey} on node {$nodeId}: affected {$r['affected']} row(s).");
            }
            continue;
        }

	        if ($cmd !== '') {
	            telegramReply($config, $chatId, "Unknown command. Send /help");
	        }
	    }

	    if (!$once) {
	        static $lastFreshnessCheck = 0;
	        if (time() - $lastFreshnessCheck >= 60) {
	            $lastFreshnessCheck = time();
	            try {
	                telegramFreshnessCheck($pdo, $config);
	            } catch (Exception $e) {
	                // ignore
	            }
	        }
	    }
	
	    if ($once) {
	        break;
	    }
} while ($loop);
