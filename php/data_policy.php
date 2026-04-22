<?php

require_once __DIR__ . '/dashboard_store.php';

const DEFAULT_DATA_RETENTION_POLICY = 'keep_forever';

function allowedRetentionPolicies(): array
{
    return [
        'keep_forever' => null,
        '30_days' => '-30 days',
        '90_days' => '-90 days',
        '1_year' => '-1 year',
    ];
}

function getDataRetentionPolicy(PDO $pdo): string
{
    try {
        $stmt = $pdo->prepare("
            SELECT setting_value
            FROM dashboard_settings
            WHERE setting_key = :setting_key
            LIMIT 1
        ");
        $stmt->execute([':setting_key' => 'retention_policy']);
        $policy = $stmt->fetchColumn() ?: DEFAULT_DATA_RETENTION_POLICY;
    } catch (Exception $e) {
        $policy = DEFAULT_DATA_RETENTION_POLICY;
    }

    return array_key_exists($policy, allowedRetentionPolicies())
        ? $policy
        : DEFAULT_DATA_RETENTION_POLICY;
}

function dataRetentionCutoff(PDO $pdo): ?string
{
    $policy = getDataRetentionPolicy($pdo);
    $rule = allowedRetentionPolicies()[$policy] ?? null;

    if ($rule === null) {
        return null;
    }

    return date('Y-m-d H:i:s', strtotime($rule));
}

function applyDataRetentionPolicy(PDO $pdo): int
{
    $cutoff = dataRetentionCutoff($pdo);
    if ($cutoff === null) {
        return 0;
    }

    $stmt = $pdo->prepare("
        DELETE FROM sensor_readings
        WHERE created_at < :cutoff
    ");
    $stmt->execute([':cutoff' => $cutoff]);

    return $stmt->rowCount();
}
