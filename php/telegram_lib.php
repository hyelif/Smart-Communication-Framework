<?php
/**
 * SmartPonic Telegram Bot — Core Library
 *
 * Telegram API helpers: messaging, updates, auth, formatting.
 * Uses file_get_contents() with stream context (no cURL dependency).
 */

require_once __DIR__ . '/telegram_config.php';
require_once __DIR__ . '/db.php';

// ──────────────────────────────────────────────
//  API request
// ──────────────────────────────────────────────

function telegramApiRequest(string $method, array $data = []): ?array
{
    $url = TELEGRAM_API_URL . '/' . $method;
    $json = json_encode($data);

    $ctx = stream_context_create([
        'http' => [
            'method'           => 'POST',
            'header'           => "Content-Type: application/json\r\n",
            'content'          => $json,
            'ignore_errors'    => true,
            'timeout'          => 30,
        ],
        'ssl' => [
            'verify_peer'      => false,
            'verify_peer_name' => false,
        ],
    ]);

    $response = @file_get_contents($url, false, $ctx);
    if ($response === false) {
        $error = error_get_last();
        error_log('Telegram API request failed: ' . $method . ' - ' . ($error['message'] ?? 'unknown error'));
        return null;
    }

    $decoded = json_decode($response, true);
    if (!is_array($decoded) || !($decoded['ok'] ?? false)) {
        error_log('Telegram API error: ' . ($decoded['description'] ?? 'unknown'));
        return null;
    }

    return $decoded['result'] ?? null;
}

// ──────────────────────────────────────────────
//  Send message
// ──────────────────────────────────────────────

function telegramSendMessage(int $chatId, string $text, string $parseMode = 'HTML'): ?array
{
    return telegramApiRequest('sendMessage', [
        'chat_id'                  => $chatId,
        'text'                     => $text,
        'parse_mode'               => $parseMode,
        'disable_web_page_preview' => true,
    ]);
}

// ──────────────────────────────────────────────
//  Get updates (long-poll)
// ──────────────────────────────────────────────

function telegramGetUpdates(?int $offset = null, int $timeout = 25): ?array
{
    $data = [
        'timeout'      => $timeout,
        'allowed_updates' => ['message'],
    ];
    if ($offset !== null) {
        $data['offset'] = $offset;
    }

    return telegramApiRequest('getUpdates', $data);
}

// ──────────────────────────────────────────────
//  Polling offset persistence
// ──────────────────────────────────────────────

function telegramGetLastUpdateId(): int
{
    $db = getDb();
    $stmt = $db->prepare("SELECT state_value FROM telegram_bot_state WHERE state_key = 'last_update_id'");
    $stmt->execute();
    $row = $stmt->fetch();
    return $row ? (int) $row['state_value'] : 0;
}

function telegramSetLastUpdateId(int $updateId): void
{
    $db = getDb();
    $stmt = $db->prepare(
        "INSERT INTO telegram_bot_state (state_key, state_value)
         VALUES ('last_update_id', ?)
         ON DUPLICATE KEY UPDATE state_value = VALUES(state_value)"
    );
    $stmt->execute([(string) $updateId]);
}

// ──────────────────────────────────────────────
//  Access control
// ──────────────────────────────────────────────

function telegramIsAllowedChat(int $chatId): bool
{
    $allowed = unserialize(TELEGRAM_ALLOWED_CHAT_IDS);
    if (!is_array($allowed)) {
        return false;
    }
    return in_array($chatId, $allowed, true);
}

// ──────────────────────────────────────────────
//  Formatting helpers
// ──────────────────────────────────────────────

function telegramEscapeHtml(string $text): string
{
    return htmlspecialchars($text, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
}

/**
 * Truncate message to stay under Telegram's 4096-character limit.
 */
function telegramTruncate(string $text, int $limit = 4000): string
{
    if (mb_strlen($text) <= $limit) {
        return $text;
    }
    return mb_substr($text, 0, $limit) . "\n\n… truncated";
}
