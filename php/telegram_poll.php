<?php
/**
 * SmartPonic Telegram Bot — Polling Command Handler
 *
 * Usage:
 *   php telegram_poll.php --once     (single poll, for cron)
 *   php telegram_poll.php --loop     (continuous long-poll)
 *
 * Commands (HTML-formatted responses):
 *   /start               Welcome message
 *   /help                List commands
 *   /whoami              Show your chat ID (no auth needed)
 *   /status              System overview
 *   /nodes               List all registered nodes
 *   /readings [hw_id]    Latest sensor values
 *   /alerts [hw_id]      List active alerts
 *   /ack <hw_id> <id>    Acknowledge an alert
 *   /resolve <hw_id> <id> Mark alert as resolved
 *   /relay <hw_id> <relay_id> <on|off>  Queue a relay command
 *   /queue [hw_id]       View pending relay commands
 *   /approve <id>        Approve a pending automation command
 *   /cancel <id>         Cancel a pending automation command
 */

require_once __DIR__ . '/telegram_lib.php';

// ──────────────────────────────────────────────
//  Constants
// ──────────────────────────────────────────────
define('FRESHNESS_WARNING_S', 300);   // 5 min — STALE
define('FRESHNESS_OFFLINE_S', 900);   // 15 min — OFFLINE
define('APPROVAL_EXPIRY_S', 600);     // 10 min

// ──────────────────────────────────────────────
//  Command handlers
// ──────────────────────────────────────────────

function cmdStart(int $chatId): void
{
    $msg = "<b>\xF0\x9F\x8C\xB1 SmartPonic Bot</b>\n\n"
        . "Welcome! I report your aquaponic sensor data.\n\n"
        . "Send /help to see available commands.\n"
        . "Send /whoami to get your chat ID (needed for access).";

    telegramSendMessage($chatId, $msg);
}

function cmdHelp(int $chatId): void
{
    $msg = "<b>Commands</b>\n\n"
        . "/whoami \xE2\x80\x94 Show your chat ID\n"
        . "/status \xE2\x80\x94 System overview\n"
        . "/nodes \xE2\x80\x94 List all nodes\n"
        . "/readings &lt;hw_id&gt; \xE2\x80\x94 Latest readings\n"
        . "/alerts &lt;hw_id&gt; \xE2\x80\x94 List active alerts\n"
        . "/ack &lt;hw_id&gt; &lt;id&gt; \xE2\x80\x94 Acknowledge an alert\n"
        . "/resolve &lt;hw_id&gt; &lt;id&gt; \xE2\x80\x94 Resolve an alert\n"
        . "<b>Relay Control</b>\n"
        . "/relay0 on|off \xE2\x80\x94 Relay 0 (Water Pump)\n"
        . "/relay1 on|off \xE2\x80\x94 Relay 1 (Backup)\n"
        . "/relay &lt;hw_id&gt; &lt;id&gt; &lt;on|off&gt; \xE2\x80\x94 Full relay command\n"
        . "/queue &lt;hw_id&gt; \xE2\x80\x94 View pending relay commands\n"
        . "/approve &lt;id&gt; \xE2\x80\x94 Approve automation command\n"
        . "/cancel &lt;id&gt; \xE2\x80\x94 Cancel automation command\n"
        . "/help \xE2\x80\x94 This message";

    telegramSendMessage($chatId, $msg);
}

function cmdWhoami(int $chatId): void
{
    $msg = "Your chat ID: <code>$chatId</code>\n\n"
        . "Give this to the administrator to grant you access.";

    telegramSendMessage($chatId, $msg);
}

function cmdStatus(int $chatId): void
{
    $db = getDb();

    $nodeCount    = $db->query("SELECT COUNT(*) AS cnt FROM nodes")->fetch()['cnt'];
    $readingCount = $db->query("SELECT COUNT(*) AS cnt FROM sensor_readings")->fetch()['cnt'];
    $lastReading  = $db->query("SELECT MAX(created_at) AS last FROM sensor_readings")->fetch()['last'];
    $alertCount   = $db->query("SELECT COUNT(*) AS cnt FROM alerts WHERE status = 'active'")->fetch()['cnt'];
    $pendingRelay = $db->query("SELECT COUNT(*) AS cnt FROM relay_commands WHERE status IN ('pending','approved')")->fetch()['cnt'];

    $lastStr = $lastReading
        ? date('Y-m-d H:i:s', strtotime($lastReading))
        : "\xE2\x80\x94";

    $msg = "<b>\xF0\x9F\x93\x8A System Status</b>\n\n"
        . "Nodes: <b>$nodeCount</b>\n"
        . "Total readings: <b>$readingCount</b>\n"
        . "Active alerts: <b>$alertCount</b>\n"
        . "Pending relays: <b>$pendingRelay</b>\n"
        . "Last data: <code>" . telegramEscapeHtml($lastStr) . "</code>";

    telegramSendMessage($chatId, $msg);
}

function cmdNodes(int $chatId): void
{
    $db = getDb();
    $rows = $db->query("SELECT hardware_id, name, location, last_seen FROM nodes ORDER BY hardware_id")->fetchAll();

    if (empty($rows)) {
        telegramSendMessage($chatId, "No nodes registered yet.");
        return;
    }

    $lines = ["<b>\xF0\x9F\x93\xA1 Nodes</b>\n"];
    foreach ($rows as $r) {
        $name = $r['name'] ?? "\xE2\x80\x94";
        $loc  = $r['location'] ?? "\xE2\x80\x94";
        $hw   = telegramEscapeHtml($r['hardware_id']);
        $seen = date('Y-m-d H:i', strtotime($r['last_seen']));

        $lines[] = "<code>$hw</code>"
                 . " \xE2\x80\x94 " . telegramEscapeHtml($name)
                 . " (" . telegramEscapeHtml($loc) . ")"
                 . "\n  Last: $seen";
    }

    telegramSendMessage($chatId, telegramTruncate(implode("\n", $lines)));
}

function cmdReadings(int $chatId, ?string $hwId = null): void
{
    $db = getDb();

    if ($hwId !== null) {
        if (!preg_match('/^[A-Za-z0-9]+$/', $hwId)) {
            telegramSendMessage($chatId, "Invalid hardware ID. Use hex format like <code>A1B2C3D4E5F6A7B8</code>.");
            return;
        }

        $stmt = $db->prepare("SELECT name, location FROM nodes WHERE hardware_id = ?");
        $stmt->execute([$hwId]);
        $node = $stmt->fetch();

        if (!$node) {
            telegramSendMessage($chatId, "Node <code>" . telegramEscapeHtml($hwId) . "</code> not found.");
            return;
        }

        $stmt = $db->prepare(
            "SELECT sr.rssi, sr.snr, sr.created_at,
                    sd.pin, sd.sensor, sd.value
               FROM sensor_readings sr
               JOIN sensor_data sd ON sd.reading_id = sr.id
              WHERE sr.id = (SELECT MAX(id) FROM sensor_readings WHERE hardware_id = ?)
              ORDER BY sd.pin"
        );
        $stmt->execute([$hwId]);
        $rows = $stmt->fetchAll();

        if (empty($rows)) {
            telegramSendMessage($chatId, "No readings for node <code>" . telegramEscapeHtml($hwId) . "</code> yet.");
            return;
        }

        $name = $node['name'] ? telegramEscapeHtml($node['name']) : $hwId;
        $time = date('Y-m-d H:i:s', strtotime($rows[0]['created_at']));
        $rssi = $rows[0]['rssi'] ?? "\xE2\x80\x94";
        $snr  = $rows[0]['snr']  ?? "\xE2\x80\x94";

        $lines = ["<b>\xF0\x9F\x93\xA1 $name</b>\n"];
        $lines[] = "\xF0\x9F\x95\x90 $time";
        $lines[] = "\xF0\x9F\x93\xB6 RSSI: $rssi | SNR: $snr\n";

        foreach ($rows as $r) {
            $sensor = telegramEscapeHtml($r['sensor']);
            $value  = telegramEscapeHtml($r['value']);
            $pin    = $r['pin'];
            $lines[] = "  GPIO$pin <b>$sensor</b>: $value";
        }

        telegramSendMessage($chatId, telegramTruncate(implode("\n", $lines)));

    } else {
        $rows = $db->query(
            "SELECT sr.hardware_id, sr.rssi, sr.snr, sr.created_at,
                    sd.pin, sd.sensor, sd.value
               FROM sensor_readings sr
               JOIN sensor_data sd ON sd.reading_id = sr.id
               JOIN (
                   SELECT hardware_id, MAX(id) AS max_id
                     FROM sensor_readings
                    GROUP BY hardware_id
               ) latest ON latest.max_id = sr.id
              ORDER BY sr.hardware_id, sd.pin"
        )->fetchAll();

        if (empty($rows)) {
            telegramSendMessage($chatId, "No readings yet.");
            return;
        }

        $byNode = [];
        foreach ($rows as $r) {
            $byNode[$r['hardware_id']][] = $r;
        }

        $lines = ["<b>\xF0\x9F\x93\x8A Latest Readings</b>\n"];
        foreach ($byNode as $hwId => $sensors) {
            $first = $sensors[0];
            $time  = date('Y-m-d H:i', strtotime($first['created_at']));
            $lines[] = "\n<code>" . telegramEscapeHtml($hwId) . "</code> \xF0\x9F\x95\x90 $time";

            foreach ($sensors as $s) {
                $sensor = telegramEscapeHtml($s['sensor']);
                $value  = telegramEscapeHtml($s['value']);
                $lines[] = "  \xE2\x94\x9C $sensor: $value";
            }
        }

        telegramSendMessage($chatId, telegramTruncate(implode("\n", $lines)));
    }
}

// ──────────────────────────────────────────────
//  /alerts [hw_id]
// ──────────────────────────────────────────────
function cmdAlerts(int $chatId, ?string $hwId = null): void
{
    $db = getDb();

    if ($hwId !== null) {
        if (!preg_match('/^[A-Za-z0-9]+$/', $hwId)) {
            telegramSendMessage($chatId, "Invalid hardware ID.");
            return;
        }
        $stmt = $db->prepare(
            "SELECT id, sensor_key, severity, message, status, created_at
               FROM alerts
              WHERE hardware_id = ?
              ORDER BY created_at DESC
              LIMIT 20"
        );
        $stmt->execute([$hwId]);
        $rows = $stmt->fetchAll();
    } else {
        $rows = $db->query(
            "SELECT id, hardware_id, sensor_key, severity, message, status, created_at
               FROM alerts
              WHERE status = 'active'
              ORDER BY created_at DESC
              LIMIT 20"
        )->fetchAll();
    }

    if (empty($rows)) {
        telegramSendMessage($chatId, "No alerts" . ($hwId ? " for this node" : "") . ".");
        return;
    }

    $lines = ["<b>\xF0\x9F\x9A\xA8 Alerts</b>\n"];
    foreach ($rows as $r) {
        $hw  = telegramEscapeHtml($r['hardware_id']);
        $msg = telegramEscapeHtml($r['message']);
        $time = date('Y-m-d H:i', strtotime($r['created_at']));
        $statusIcon = $r['status'] === 'active' ? "\xF0\x9F\x94\xB4" : ($r['status'] === 'acknowledged' ? "\xF0\x9F\x9F\xA1" : "\xF0\x9F\x9F\xA2");
        $lines[] = "$statusIcon #{$r['id']} <code>$hw</code>";
        $lines[] = "  $msg";
        $lines[] = "  $time [" . $r['status'] . "]\n";
    }

    telegramSendMessage($chatId, telegramTruncate(implode("\n", $lines)));
}

// ──────────────────────────────────────────────
//  /ack <hw_id> <alert_id>
// ──────────────────────────────────────────────
function cmdAck(int $chatId, string $hwId, string $alertIdStr): void
{
    $db = getDb();
    $alertId = (int)$alertIdStr;
    if ($alertId <= 0) {
        telegramSendMessage($chatId, "Usage: /ack &lt;hw_id&gt; &lt;alert_id&gt;");
        return;
    }

    $stmt = $db->prepare(
        "UPDATE alerts SET status = 'acknowledged' WHERE id = ? AND hardware_id = ? AND status = 'active'"
    );
    $stmt->execute([$alertId, $hwId]);

    if ($stmt->rowCount() > 0) {
        telegramSendMessage($chatId, "Alert #$alertId acknowledged \xF0\x9F\x9F\xA1");
    } else {
        telegramSendMessage($chatId, "Alert #$alertId not found or already resolved.");
    }
}

// ──────────────────────────────────────────────
//  /resolve <hw_id> <alert_id>
// ──────────────────────────────────────────────
function cmdResolve(int $chatId, string $hwId, string $alertIdStr): void
{
    $db = getDb();
    $alertId = (int)$alertIdStr;
    if ($alertId <= 0) {
        telegramSendMessage($chatId, "Usage: /resolve &lt;hw_id&gt; &lt;alert_id&gt;");
        return;
    }

    $stmt = $db->prepare(
        "UPDATE alerts SET status = 'resolved' WHERE id = ? AND hardware_id = ? AND status != 'resolved'"
    );
    $stmt->execute([$alertId, $hwId]);

    if ($stmt->rowCount() > 0) {
        telegramSendMessage($chatId, "Alert #$alertId resolved \xF0\x9F\x9F\xA2");
    } else {
        telegramSendMessage($chatId, "Alert #$alertId not found or already resolved.");
    }
}

// ──────────────────────────────────────────────
//  /relay <hw_id> <relay_id> <on|off>
// ──────────────────────────────────────────────
function cmdRelay(int $chatId, string $hwId, string $relayIdStr, string $action): void
{
    $db = getDb();

    if (!preg_match('/^[0-9A-F]{16}$/i', $hwId)) {
        telegramSendMessage($chatId, "Invalid hardware ID format.");
        return;
    }

    $relayId = (int)$relayIdStr;
    if ($relayId < 0 || $relayId > 255) {
        telegramSendMessage($chatId, "Relay ID must be 0-255.");
        return;
    }

    $action = strtoupper($action);
    if (!in_array($action, ['ON', 'OFF'], true)) {
        telegramSendMessage($chatId, "Action must be <b>on</b> or <b>off</b>.");
        return;
    }

    // Check node exists
    $stmt = $db->prepare("SELECT hardware_id FROM nodes WHERE hardware_id = ?");
    $stmt->execute([$hwId]);
    if (!$stmt->fetch()) {
        telegramSendMessage($chatId, "Node <code>" . telegramEscapeHtml($hwId) . "</code> not found.");
        return;
    }

    $stmt = $db->prepare(
        "INSERT INTO relay_commands (hardware_id, relay_id, action, status) VALUES (?, ?, ?, 'approved')"
    );
    $stmt->execute([$hwId, $relayId, $action]);
    $cmdId = (int)$db->lastInsertId();

    telegramSendMessage($chatId,
        "Queued relay command #$cmdId\n"
        . "Node: <code>" . telegramEscapeHtml($hwId) . "</code>\n"
        . "Relay: $relayId \xE2\x86\x92 $action\n"
        . "Status: approved \xE2\x9C\x85\n"
        . "HQ will pick it up within 4 seconds"
    );
}

// ──────────────────────────────────────────────
//  /queue [hw_id]
// ──────────────────────────────────────────────
function cmdQueue(int $chatId, ?string $hwId = null): void
{
    $db = getDb();

    if ($hwId !== null) {
        if (!preg_match('/^[0-9A-F]{16}$/i', $hwId)) {
            telegramSendMessage($chatId, "Invalid hardware ID format.");
            return;
        }
        $stmt = $db->prepare(
            "SELECT id, relay_id, action, status, created_at
               FROM relay_commands
              WHERE hardware_id = ? AND status IN ('pending','approved','sent')
              ORDER BY created_at ASC
              LIMIT 20"
        );
        $stmt->execute([$hwId]);
        $rows = $stmt->fetchAll();
    } else {
        $rows = $db->query(
            "SELECT id, hardware_id, relay_id, action, status, created_at
               FROM relay_commands
              WHERE status IN ('pending','approved','sent')
              ORDER BY created_at ASC
              LIMIT 20"
        )->fetchAll();
    }

    if (empty($rows)) {
        telegramSendMessage($chatId, "No pending relay commands.");
        return;
    }

    $lines = ["<b>\xF0\x9F\x93\x8B Relay Queue</b>\n"];
    foreach ($rows as $r) {
        $hw = telegramEscapeHtml($r['hardware_id']);
        $statusIcon = $r['status'] === 'pending' ? "\xF0\x9F\x95\x99" : ($r['status'] === 'approved' ? "\xE2\x9C\x85" : "\xF0\x9F\x93\xA1");
        $lines[] = "$statusIcon #{$r['id']} <code>$hw</code> relay {$r['relay_id']} \xE2\x86\x92 {$r['action']}";
        $lines[] = "  Status: {$r['status']} at " . date('Y-m-d H:i', strtotime($r['created_at']));
    }

    telegramSendMessage($chatId, telegramTruncate(implode("\n", $lines)));
}

// ──────────────────────────────────────────────
//  /approve <approval_id>
// ──────────────────────────────────────────────
function cmdApprove(int $chatId, string $idStr): void
{
    $db = getDb();
    $approvalId = (int)$idStr;
    if ($approvalId <= 0) {
        telegramSendMessage($chatId, "Usage: /approve &lt;approval_id&gt;");
        return;
    }

    // Find pending approval
    $stmt = $db->prepare(
        "SELECT * FROM pending_approvals WHERE id = ? AND status = 'pending'"
    );
    $stmt->execute([$approvalId]);
    $approval = $stmt->fetch();

    if (!$approval) {
        telegramSendMessage($chatId, "Approval #$approvalId not found or already processed.");
        return;
    }

    // Check expiry
    if ($approval['expires_at'] && strtotime($approval['expires_at']) < time()) {
        $db->prepare("UPDATE pending_approvals SET status = 'expired' WHERE id = ?")->execute([$approvalId]);
        telegramSendMessage($chatId, "Approval #$approvalId has expired \xF0\x9F\x95\x93");
        return;
    }

    $db->beginTransaction();
    try {
        // Mark approval as approved
        $db->prepare("UPDATE pending_approvals SET status = 'approved', chat_id = ? WHERE id = ?")
           ->execute([$chatId, $approvalId]);

        // Create relay command
        $stmt = $db->prepare(
            "INSERT INTO relay_commands (hardware_id, relay_id, action, status) VALUES (?, ?, ?, 'approved')"
        );
        $stmt->execute([$approval['hardware_id'], $approval['relay_id'], $approval['action']]);
        $cmdId = (int)$db->lastInsertId();

        // Link command
        $db->prepare("UPDATE pending_approvals SET command_id = ? WHERE id = ?")
           ->execute([$cmdId, $approvalId]);

        $db->commit();

        telegramSendMessage($chatId,
            "Approved automation command #$approvalId \xE2\x9C\x85\n"
            . "Relay command #$cmdId created (node <code>" . telegramEscapeHtml($approval['hardware_id'])
            . "</code> relay {$approval['relay_id']} \xE2\x86\x92 {$approval['action']})"
        );
    } catch (Throwable $e) {
        $db->rollBack();
        telegramSendMessage($chatId, "Error processing approval: " . $e->getMessage());
    }
}

// ──────────────────────────────────────────────
//  /cancel <approval_id>
// ──────────────────────────────────────────────
function cmdCancel(int $chatId, string $idStr): void
{
    $db = getDb();
    $approvalId = (int)$idStr;
    if ($approvalId <= 0) {
        telegramSendMessage($chatId, "Usage: /cancel &lt;approval_id&gt;");
        return;
    }

    $stmt = $db->prepare(
        "UPDATE pending_approvals SET status = 'cancelled', chat_id = ? WHERE id = ? AND status = 'pending'"
    );
    $stmt->execute([$chatId, $approvalId]);

    if ($stmt->rowCount() > 0) {
        telegramSendMessage($chatId, "Cancelled automation command #$approvalId \xE2\x9C\x97");
    } else {
        telegramSendMessage($chatId, "Approval #$approvalId not found or already processed.");
    }
}

// ──────────────────────────────────────────────
//  Freshness monitoring
// ──────────────────────────────────────────────
function telegramFreshnessCheck(): void
{
    $db = getDb();
    $nodes = $db->query("SELECT hardware_id, last_seen FROM nodes")->fetchAll();

    foreach ($nodes as $node) {
        $hwId = $node['hardware_id'];
        $lastSeen = $node['last_seen'];

        if (!$lastSeen) continue;

        $age = time() - strtotime($lastSeen);

        // Check if node was previously offline (has an active OFFLINE alert)
        $offlineKey = "freshness:{$hwId}:offline";
        $stmt = $db->prepare("SELECT last_sent_at FROM telegram_alert_state WHERE state_key = ?");
        $stmt->execute([$offlineKey]);
        $offlineState = $stmt->fetch();
        $wasOffline = ($offlineState !== false);

        if ($age >= FRESHNESS_OFFLINE_S) {
            // Send OFFLINE alert (with cooldown)
            if (telegramShouldSendAlert($offlineKey, 300)) {
                $msg = "\xF0\x9F\x94\xB4 <b>SmartPonic OFFLINE</b>\n"
                     . "Node <code>" . telegramEscapeHtml($hwId) . "</code> has not reported for "
                     . floor($age / 60) . " minutes.\n"
                     . "Last seen: " . date('Y-m-d H:i:s', strtotime($lastSeen));

                $chats = unserialize(TELEGRAM_ALLOWED_CHAT_IDS);
                foreach ($chats as $chatId) {
                    telegramSendMessage($chatId, $msg);
                }
                telegramUpdateAlertState($offlineKey);
            }
        } elseif ($age >= FRESHNESS_WARNING_S) {
            // Send STALE alert (with cooldown)
            $staleKey = "freshness:{$hwId}:stale";
            if (telegramShouldSendAlert($staleKey, 300)) {
                $msg = "\xF0\x9F\x9F\xA1 <b>SmartPonic STALE</b>\n"
                     . "Node <code>" . telegramEscapeHtml($hwId) . "</code> last reported "
                     . floor($age / 60) . " minutes ago.\n"
                     . "Last seen: " . date('Y-m-d H:i:s', strtotime($lastSeen));

                $chats = unserialize(TELEGRAM_ALLOWED_CHAT_IDS);
                foreach ($chats as $chatId) {
                    telegramSendMessage($chatId, $msg);
                }
                telegramUpdateAlertState($staleKey);
            }

            // Clear offline state if was offline
            if ($wasOffline) {
                $db->prepare("DELETE FROM telegram_alert_state WHERE state_key = ?")->execute([$offlineKey]);
                $msg = "\xF0\x9F\x9F\xA2 <b>SmartPonic RECOVERED</b>\n"
                     . "Node <code>" . telegramEscapeHtml($hwId) . "</code> is back online.\n"
                     . "Last seen: " . date('Y-m-d H:i:s', strtotime($lastSeen));

                $chats = unserialize(TELEGRAM_ALLOWED_CHAT_IDS);
                foreach ($chats as $chatId) {
                    telegramSendMessage($chatId, $msg);
                }
            }
        } else {
            // Node is healthy — clear any stale/offline state
            if ($wasOffline) {
                $db->prepare("DELETE FROM telegram_alert_state WHERE state_key = ?")->execute([$offlineKey]);
                $msg = "\xF0\x9F\x9F\xA2 <b>SmartPonic RECOVERED</b>\n"
                     . "Node <code>" . telegramEscapeHtml($hwId) . "</code> is back online.";

                $chats = unserialize(TELEGRAM_ALLOWED_CHAT_IDS);
                foreach ($chats as $chatId) {
                    telegramSendMessage($chatId, $msg);
                }
            }
        }
    }
}

// ──────────────────────────────────────────────
//  Alert cooldown helpers
// ──────────────────────────────────────────────
function telegramShouldSendAlert(string $stateKey, int $cooldownSeconds): bool
{
    $db = getDb();
    $stmt = $db->prepare("SELECT last_sent_at FROM telegram_alert_state WHERE state_key = ?");
    $stmt->execute([$stateKey]);
    $row = $stmt->fetch();

    if (!$row || !$row['last_sent_at']) {
        return true;
    }

    $elapsed = time() - strtotime($row['last_sent_at']);
    return $elapsed >= $cooldownSeconds;
}

function telegramUpdateAlertState(string $stateKey): void
{
    $db = getDb();
    $stmt = $db->prepare(
        "INSERT INTO telegram_alert_state (state_key, last_sent_at)
         VALUES (?, NOW())
         ON DUPLICATE KEY UPDATE last_sent_at = VALUES(last_sent_at)"
    );
    $stmt->execute([$stateKey]);
}

// ──────────────────────────────────────────────
//  Pending approval expiry
// ──────────────────────────────────────────────
function expirePendingApprovals(): void
{
    $db = getDb();
    $db->prepare(
        "UPDATE pending_approvals SET status = 'expired'
         WHERE status = 'pending' AND expires_at IS NOT NULL AND expires_at < NOW()"
    )->execute();

    // Clean up expired records older than 24 hours
    $db->prepare(
        "DELETE FROM pending_approvals WHERE status = 'expired' AND created_at < DATE_SUB(NOW(), INTERVAL 24 HOUR)"
    )->execute();
}

// ──────────────────────────────────────────────
//  Helper: get the most recent/default node
// ──────────────────────────────────────────────
function getDefaultNode(): ?string
{
    $db = getDb();
    $stmt = $db->query("SELECT hardware_id FROM nodes ORDER BY last_seen DESC LIMIT 1");
    $row = $stmt->fetch();
    return $row ? $row['hardware_id'] : null;
}

// ──────────────────────────────────────────────
//  Update dispatcher
// ──────────────────────────────────────────────

function telegramProcessUpdate(array $update): void
{
    $msg = $update['message'] ?? $update['callback_query']['message'] ?? null;
    if (!$msg || !isset($msg['chat']['id'])) {
        return;
    }

    $chatId  = $msg['chat']['id'];
    $text    = trim($msg['text'] ?? '');
    $parts   = preg_split('/\s+/', $text);
    $command = $parts[0] ?? '';
    $arg1    = $parts[1] ?? null;
    $arg2    = $parts[2] ?? null;
    $arg3    = $parts[3] ?? null;

    // /whoami is always accessible
    if ($command === '/whoami') {
        cmdWhoami($chatId);
        return;
    }

    // Shortcut relay commands: /relay0 on, /relay1 off, etc.
    // Uses the most recently seen node automatically.
    if (preg_match('/^\/relay(\d+)$/i', $command, $m)) {
        if (!$arg1 || !in_array(strtoupper($arg1), ['ON', 'OFF'])) {
            telegramSendMessage($chatId, "Usage: <b>{$command} on|off</b>\nExample: /relay0 on");
            return;
        }
        $relayId = (int)$m[1];
        $action = strtoupper($arg1);
        $defaultNode = getDefaultNode();
        if (!$defaultNode) {
            telegramSendMessage($chatId, "No nodes found. Register a node first.");
            return;
        }
        cmdRelay($chatId, $defaultNode, (string)$relayId, $action);
        return;
    }

    // All other commands require auth
    if (!telegramIsAllowedChat($chatId)) {
        telegramSendMessage(
            $chatId,
            "You are not authorized. Send /whoami to get your chat ID and ask the administrator to add it."
        );
        return;
    }

    switch ($command) {
        case '/start':
            cmdStart($chatId);
            break;

        case '/help':
            cmdHelp($chatId);
            break;

        case '/status':
            cmdStatus($chatId);
            break;

        case '/nodes':
            cmdNodes($chatId);
            break;

        case '/readings':
            cmdReadings($chatId, $arg1);
            break;

        case '/alerts':
            cmdAlerts($chatId, $arg1);
            break;

        case '/ack':
            if ($arg1 && $arg2) {
                cmdAck($chatId, $arg1, $arg2);
            } else {
                telegramSendMessage($chatId, "Usage: /ack &lt;hw_id&gt; &lt;alert_id&gt;");
            }
            break;

        case '/resolve':
            if ($arg1 && $arg2) {
                cmdResolve($chatId, $arg1, $arg2);
            } else {
                telegramSendMessage($chatId, "Usage: /resolve &lt;hw_id&gt; &lt;alert_id&gt;");
            }
            break;

        case '/relay':
            if ($arg1 && $arg2 && $arg3) {
                cmdRelay($chatId, $arg1, $arg2, $arg3);
            } else {
                telegramSendMessage($chatId, "Usage: /relay &lt;hw_id&gt; &lt;relay_id&gt; &lt;on|off&gt;");
            }
            break;

        case '/queue':
            cmdQueue($chatId, $arg1);
            break;

        case '/approve':
            if ($arg1) {
                cmdApprove($chatId, $arg1);
            } else {
                telegramSendMessage($chatId, "Usage: /approve &lt;approval_id&gt;");
            }
            break;

        case '/cancel':
            if ($arg1) {
                cmdCancel($chatId, $arg1);
            } else {
                telegramSendMessage($chatId, "Usage: /cancel &lt;approval_id&gt;");
            }
            break;

        default:
            if (str_starts_with($command, '/')) {
                telegramSendMessage($chatId, "Unknown command. Send /help for available commands.");
            }
            break;
    }
}

// ──────────────────────────────────────────────
//  Poll loop
// ──────────────────────────────────────────────

function telegramPollOnce(): void
{
    $offset = telegramGetLastUpdateId();
    $updates = telegramGetUpdates($offset);

    if ($updates === null || !is_array($updates)) {
        return;
    }

    foreach ($updates as $update) {
        $updateId = $update['update_id'] ?? 0;
        if ($updateId > 0) {
            telegramProcessUpdate($update);
            telegramSetLastUpdateId($updateId + 1);
        }
    }
}

function telegramPollLoop(): void
{
    error_log('Telegram bot: starting long-poll loop');

    $lastFreshnessCheck = 0;
    $lastApprovalExpiry = 0;

    while (true) {
        try {
            $offset = telegramGetLastUpdateId();
            $updates = telegramGetUpdates($offset, 25);

            if ($updates !== null && is_array($updates)) {
                foreach ($updates as $update) {
                    $updateId = $update['update_id'] ?? 0;
                    if ($updateId > 0) {
                        telegramProcessUpdate($update);
                        telegramSetLastUpdateId($updateId + 1);
                    }
                }
            }

            // Freshness monitoring every 60 seconds
            $now = time();
            if ($now - $lastFreshnessCheck >= 60) {
                $lastFreshnessCheck = $now;
                try {
                    telegramFreshnessCheck();
                } catch (Throwable $e) {
                    error_log('Telegram freshness check error: ' . $e->getMessage());
                }
            }

            // Pending approval expiry every 60 seconds
            if ($now - $lastApprovalExpiry >= 60) {
                $lastApprovalExpiry = $now;
                try {
                    expirePendingApprovals();
                } catch (Throwable $e) {
                    error_log('Telegram approval expiry error: ' . $e->getMessage());
                }
            }

        } catch (Throwable $e) {
            error_log('Telegram bot error: ' . $e->getMessage());
            sleep(5);
        }
    }
}

// ──────────────────────────────────────────────
//  Entry point
// ──────────────────────────────────────────────

$args = $argv ?? [];

if (in_array('--loop', $args, true)) {
    telegramPollLoop();
} else {
    telegramPollOnce();
}
