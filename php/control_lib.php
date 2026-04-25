<?php

function ensureRelayCommandsTable(PDO $pdo): void
{
    // Use MyISAM to avoid InnoDB tablespace issues on some XAMPP setups.
    $pdo->exec("
        CREATE TABLE IF NOT EXISTS relay_commands (
            id INT AUTO_INCREMENT PRIMARY KEY,
            node_id INT NOT NULL,
            relay_id INT NOT NULL,
            action VARCHAR(10) NOT NULL,
            requested_by_chat_id BIGINT NULL,
            requested_by_label VARCHAR(120) NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            status VARCHAR(20) NOT NULL DEFAULT 'pending',
            sent_at TIMESTAMP NULL,
            done_at TIMESTAMP NULL,
            result_message VARCHAR(255) NULL,
            INDEX idx_relay_cmd_node_status_created (node_id, status, created_at)
        ) ENGINE=MyISAM
    ");
}

function createRelayCommand(
    PDO $pdo,
    int $nodeId,
    int $relayId,
    string $action,
    ?int $chatId = null,
    ?string $requestedByLabel = null
): int {
    ensureRelayCommandsTable($pdo);

    $action = strtoupper(trim($action));
    if (!in_array($action, ['ON', 'OFF'], true)) {
        throw new InvalidArgumentException('Invalid relay action');
    }

    if ($nodeId <= 0) {
        throw new InvalidArgumentException('Invalid node id');
    }

    if ($relayId < 0 || $relayId > 15) {
        throw new InvalidArgumentException('Relay id out of range (0-15)');
    }

    $stmt = $pdo->prepare("
        INSERT INTO relay_commands (node_id, relay_id, action, requested_by_chat_id, requested_by_label)
        VALUES (:node_id, :relay_id, :action, :chat_id, :label)
    ");
    $stmt->execute([
        ':node_id' => $nodeId,
        ':relay_id' => $relayId,
        ':action' => $action,
        ':chat_id' => $chatId,
        ':label' => $requestedByLabel,
    ]);

    return (int) $pdo->lastInsertId();
}

function fetchPendingRelayCommands(PDO $pdo, int $nodeId, int $limit = 5): array
{
    ensureRelayCommandsTable($pdo);
    $limit = max(1, min(20, $limit));

    $stmt = $pdo->prepare("
        SELECT id, node_id, relay_id, action, created_at
        FROM relay_commands
        WHERE node_id = :node_id
          AND status = 'pending'
        ORDER BY created_at ASC, id ASC
        LIMIT {$limit}
    ");
    $stmt->execute([':node_id' => $nodeId]);
    return $stmt->fetchAll() ?: [];
}

function markRelayCommandSent(PDO $pdo, int $commandId): bool
{
    ensureRelayCommandsTable($pdo);
    $stmt = $pdo->prepare("
        UPDATE relay_commands
        SET status = 'sent', sent_at = CURRENT_TIMESTAMP
        WHERE id = :id AND status = 'pending'
    ");
    $stmt->execute([':id' => $commandId]);
    return $stmt->rowCount() > 0;
}

function markRelayCommandDone(PDO $pdo, int $commandId, string $status, ?string $resultMessage = null): bool
{
    ensureRelayCommandsTable($pdo);
    $status = strtolower(trim($status));
    $allowed = ['done', 'failed'];
    if (!in_array($status, $allowed, true)) {
        throw new InvalidArgumentException('Invalid completion status');
    }

    $stmt = $pdo->prepare("
        UPDATE relay_commands
        SET status = :status,
            done_at = CURRENT_TIMESTAMP,
            result_message = :msg
        WHERE id = :id
    ");
    $stmt->execute([
        ':id' => $commandId,
        ':status' => $status,
        ':msg' => $resultMessage,
    ]);
    return $stmt->rowCount() > 0;
}
