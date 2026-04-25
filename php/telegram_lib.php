<?php

function telegramLoadConfig(): ?array
{
    $configPath = __DIR__ . DIRECTORY_SEPARATOR . 'telegram_config.php';
    if (!is_file($configPath)) {
        return null;
    }

    $config = require $configPath;
    if (!is_array($config)) {
        return null;
    }

    $config['bot_token'] = isset($config['bot_token']) ? trim((string) $config['bot_token']) : '';
    if ($config['bot_token'] === '') {
        return null;
    }

    $config['allowed_chat_ids'] = is_array($config['allowed_chat_ids'] ?? null) ? $config['allowed_chat_ids'] : [];
    $config['default_alert_chat_id'] = $config['default_alert_chat_id'] ?? null;
    $config['cooldown_critical_s'] = isset($config['cooldown_critical_s']) ? (int) $config['cooldown_critical_s'] : 0;
    $config['cooldown_abnormal_s'] = isset($config['cooldown_abnormal_s']) ? (int) $config['cooldown_abnormal_s'] : 300;

    return $config;
}

function telegramIsAllowedChat(array $config, int $chatId): bool
{
    foreach ($config['allowed_chat_ids'] as $allowed) {
        if ((int) $allowed === $chatId) {
            return true;
        }
    }
    return false;
}

function telegramApiRequest(array $config, string $method, array $params): array
{
    $token = $config['bot_token'];
    $url = 'https://api.telegram.org/bot' . $token . '/' . $method;

    $raw = false;
    $err = '';
    $code = 0;

    if (function_exists('curl_init')) {
        $ch = curl_init($url);
        curl_setopt_array($ch, [
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_POST => true,
            CURLOPT_POSTFIELDS => $params,
            CURLOPT_CONNECTTIMEOUT => 6,
            CURLOPT_TIMEOUT => 12,
        ]);
        $raw = curl_exec($ch);
        $err = curl_error($ch);
        $code = (int) curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);
    } else {
        $context = stream_context_create([
            'http' => [
                'method' => 'POST',
                'header' => "Content-Type: application/x-www-form-urlencoded\r\n",
                'content' => http_build_query($params),
                'timeout' => 12,
            ],
        ]);
        $raw = @file_get_contents($url, false, $context);
        $err = $raw === false ? 'HTTP request failed (curl not available)' : '';
        if (isset($http_response_header) && is_array($http_response_header)) {
            foreach ($http_response_header as $headerLine) {
                if (preg_match('/^HTTP\\/[0-9.]+\\s+(\\d+)/', $headerLine, $m)) {
                    $code = (int) $m[1];
                    break;
                }
            }
        }
    }

    if ($raw === false) {
        return ['ok' => false, 'http_code' => $code, 'error' => $err];
    }

    $decoded = json_decode($raw, true);
    if (!is_array($decoded)) {
        return ['ok' => false, 'http_code' => $code, 'error' => 'Invalid JSON response', 'raw' => $raw];
    }

    $decoded['http_code'] = $code;
    return $decoded;
}

function telegramSendMessage(array $config, int $chatId, string $text, array $options = []): array
{
    $params = array_merge([
        'chat_id' => (string) $chatId,
        'text' => $text,
        'disable_web_page_preview' => 'true',
    ], $options);

    return telegramApiRequest($config, 'sendMessage', $params);
}

function telegramGetUpdates(array $config, int $offset, int $timeoutSeconds = 25): array
{
    return telegramApiRequest($config, 'getUpdates', [
        'offset' => (string) $offset,
        'timeout' => (string) $timeoutSeconds,
        'allowed_updates' => json_encode(['message'], JSON_UNESCAPED_SLASHES),
    ]);
}

function telegramEnsureTables(PDO $pdo): void
{
    static $ensured = false;
    if ($ensured) {
        return;
    }
    $ensured = true;

    $createStateTables = static function (string $suffix, string $engine) use ($pdo): void {
        $bot = 'telegram_bot_state' . $suffix;
        $alert = 'telegram_alert_state' . $suffix;

        $pdo->exec("
            CREATE TABLE IF NOT EXISTS {$bot} (
                id INT PRIMARY KEY,
                last_update_id INT NOT NULL DEFAULT 0,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
            ) ENGINE={$engine}
        ");

        $pdo->exec("
            INSERT IGNORE INTO {$bot} (id, last_update_id)
            VALUES (1, 0)
        ");

        $pdo->exec("
            CREATE TABLE IF NOT EXISTS {$alert} (
                state_key VARCHAR(190) PRIMARY KEY,
                last_sent_at TIMESTAMP NULL,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
            ) ENGINE={$engine}
        ");
    };

    $isTableBroken = static function (PDOException $e): bool {
        $msg = strtolower($e->getMessage());
        // 1932: doesn't exist in engine (InnoDB dictionary mismatch)
        // 1813: tablespace exists / InnoDB file mismatch
        return str_contains($msg, "doesn't exist in engine") || str_contains($msg, 'tablespace');
    };

    try {
        $createStateTables('', 'InnoDB');
        $pdo->query("SELECT last_update_id FROM telegram_bot_state WHERE id = 1")->fetchColumn();
    } catch (PDOException $e) {
        if (!$isTableBroken($e)) {
            throw $e;
        }

        // If InnoDB tables are broken in this DB, avoid touching them further and use a new set.
        // MyISAM avoids InnoDB tablespace issues and is sufficient for simple bot state.
        $createStateTables('_v2', 'MyISAM');
        $pdo->query("SELECT last_update_id FROM telegram_bot_state_v2 WHERE id = 1")->fetchColumn();
    }
}

function telegramResolveStateTables(PDO $pdo): array
{
    static $tables = null;
    if (is_array($tables)) {
        return $tables;
    }

    telegramEnsureTables($pdo);

    try {
        $pdo->query("SELECT last_update_id FROM telegram_bot_state WHERE id = 1")->fetchColumn();
        $tables = ['bot' => 'telegram_bot_state', 'alert' => 'telegram_alert_state'];
        return $tables;
    } catch (PDOException $e) {
        $tables = ['bot' => 'telegram_bot_state_v2', 'alert' => 'telegram_alert_state_v2'];
        return $tables;
    }
}

function telegramGetLastUpdateId(PDO $pdo): int
{
    $t = telegramResolveStateTables($pdo);
    $stmt = $pdo->query("SELECT last_update_id FROM {$t['bot']} WHERE id = 1");
    $value = $stmt->fetchColumn();
    return $value === false ? 0 : (int) $value;
}

function telegramSetLastUpdateId(PDO $pdo, int $updateId): void
{
    $t = telegramResolveStateTables($pdo);
    $stmt = $pdo->prepare("UPDATE {$t['bot']} SET last_update_id = :id WHERE id = 1");
    $stmt->execute([':id' => $updateId]);
}

function telegramShouldSendAlert(PDO $pdo, string $stateKey, int $cooldownSeconds): bool
{
    $t = telegramResolveStateTables($pdo);
    $stmt = $pdo->prepare("SELECT last_sent_at FROM {$t['alert']} WHERE state_key = :k");
    $stmt->execute([':k' => $stateKey]);
    $last = $stmt->fetchColumn();

    if ($last === false || $last === null) {
        return true;
    }

    $lastTs = strtotime((string) $last);
    if ($lastTs === false) {
        return true;
    }

    return (time() - $lastTs) >= $cooldownSeconds;
}

function telegramMarkAlertSent(PDO $pdo, string $stateKey): void
{
    $t = telegramResolveStateTables($pdo);
    $stmt = $pdo->prepare("
        INSERT INTO {$t['alert']} (state_key, last_sent_at)
        VALUES (:k, CURRENT_TIMESTAMP)
        ON DUPLICATE KEY UPDATE last_sent_at = VALUES(last_sent_at)
    ");
    $stmt->execute([':k' => $stateKey]);
}
