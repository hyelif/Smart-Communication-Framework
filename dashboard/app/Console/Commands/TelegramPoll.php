<?php

namespace App\Console\Commands;

use Illuminate\Console\Command;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;

class TelegramPoll extends Command
{
    protected $signature = 'telegram:poll
                            {--timeout=10 : Long-poll timeout in seconds}
                            {--once : Process one batch then exit (for cron)}';

    protected $description = 'Poll Telegram for bot commands and process them';

    private const ALLOWED_COMMANDS = ['/start', '/status', '/nodes', '/alerts', '/readings'];

    public function handle()
    {
        $botToken = env('TELEGRAM_BOT_TOKEN');
        if (!$botToken) {
            $this->error('TELEGRAM_BOT_TOKEN not set');
            return 1;
        }

        $timeout = min((int) $this->option('timeout'), 30);
        $once = (bool) $this->option('once');

        $this->info('Telegram poll starting...');

        do {
            try {
                $this->processUpdates($botToken, $timeout);
            } catch (\Exception $e) {
                Log::error('Telegram poll error: ' . $e->getMessage());
                $this->error('Error: ' . $e->getMessage());
                if ($once) break;
                sleep(5);
            }
        } while (!$once);

        $this->info('Telegram poll finished');
        return 0;
    }

    private function processUpdates(string $botToken, int $timeout): void
    {
        $lastUpdateId = $this->getLastUpdateId();

        $response = Http::timeout($timeout + 5)
            ->get("https://api.telegram.org/bot{$botToken}/getUpdates", [
                'offset'  => $lastUpdateId + 1,
                'timeout' => $timeout,
            ]);

        if (!$response->successful()) {
            $this->warn('Telegram API returned ' . $response->status());
            return;
        }

        $updates = $response->json()['result'] ?? [];

        foreach ($updates as $update) {
            $this->processUpdate($botToken, $update);
            $this->saveLastUpdateId($update['update_id']);
        }

        if (count($updates) > 0) {
            $this->info('Processed ' . count($updates) . ' updates');
        }
    }

    private function processUpdate(string $botToken, array $update): void
    {
        $message = $update['message'] ?? [];
        $chatId  = $message['chat']['id'] ?? null;
        $text    = trim($message['text'] ?? '');

        if (!$chatId || !$text) return;

        // Check if chat is authorized
        $allowedChats = explode(',', env('TELEGRAM_ALLOWED_CHAT_IDS', ''));
        if (!in_array((string)$chatId, $allowedChats, true)) {
            return;
        }

        $response = match (true) {
            str_starts_with($text, '/start')   => $this->cmdStart(),
            str_starts_with($text, '/status')  => $this->cmdStatus(),
            str_starts_with($text, '/nodes')   => $this->cmdNodes(),
            str_starts_with($text, '/alerts')  => $this->cmdAlerts(),
            str_starts_with($text, '/readings') => $this->cmdReadings(),
            default => null,
        };

        if ($response) {
            Http::timeout(10)
                ->post("https://api.telegram.org/bot{$botToken}/sendMessage", [
                    'chat_id'    => $chatId,
                    'text'       => $response,
                    'parse_mode' => 'HTML',
                ]);
        }
    }

    private function cmdStart(): string
    {
        return "🤖 <b>SmartPonic Bot</b>\n"
             . "Available commands:\n"
             . "/status — System status\n"
             . "/nodes — List nodes\n"
             . "/alerts — Active alerts\n"
             . "/readings — Latest sensor readings";
    }

    private function cmdStatus(): string
    {
        $latest = $this->tursoQuery("SELECT * FROM sensor_readings ORDER BY id DESC LIMIT 1");
        if (!$latest) return "⚠️ No data received yet.";

        $nodeCount = $this->tursoCount('nodes');
        $alertCount = $this->tursoCountWhere('alerts', "status = 'active'");

        return "📊 <b>System Status</b>\n"
             . "Nodes: {$nodeCount}\n"
             . "Active alerts: {$alertCount}\n"
             . "Last reading: {$latest['created_at']}\n"
             . "RSSI: {$latest['rssi']} dBm | SNR: {$latest['snr']} dB";
    }

    private function cmdNodes(): string
    {
        $nodes = $this->tursoQueryAll("SELECT * FROM nodes ORDER BY id");
        if (empty($nodes)) return "No nodes registered.";

        $text = "📡 <b>Registered Nodes</b>\n";
        foreach ($nodes as $node) {
            $text .= "• {$node['hardware_id']}";
            if ($node['name']) $text .= " ({$node['name']})";
            $text .= "\n  Last seen: {$node['last_seen']}\n";
        }
        return $text;
    }

    private function cmdAlerts(): string
    {
        $alerts = $this->tursoQueryAll(
            "SELECT * FROM alerts WHERE status = ? ORDER BY created_at DESC LIMIT 10",
            ['active']
        );

        if (empty($alerts)) return "✅ No active alerts.";

        $text = "🔔 <b>Active Alerts</b>\n";
        foreach ($alerts as $a) {
            $icon = $a['severity'] === 'critical' ? '🔴' : ($a['severity'] === 'warning' ? '🟡' : '🔵');
            $text .= "{$icon} {$a['message']}\n";
        }
        return $text;
    }

    private function cmdReadings(): string
    {
        $latest = $this->tursoQuery("SELECT * FROM sensor_readings ORDER BY id DESC LIMIT 1");
        if (!$latest) return "⚠️ No readings yet.";

        $sensors = $this->tursoQueryAll(
            "SELECT sensor, value FROM sensor_data WHERE reading_id = ?",
            [$latest['id']]
        );

        $text = "📡 <b>Latest Readings</b>\n"
              . "Node: {$latest['hardware_id']}\n"
              . "Time: {$latest['created_at']}\n\n";

        foreach ($sensors as $s) {
            $text .= "{$s['sensor']}: {$s['value']}\n";
        }

        return $text;
    }

    // ─── Turso helpers (no DB facade dependency) ───────────────

    private function tursoQuery(string $sql, array $params = []): ?array
    {
        try {
            $service = app(\App\Services\TursoService::class);
            return $service->queryOne($sql, $params);
        } catch (\Exception $e) {
            Log::error('Telegram Turso query error: ' . $e->getMessage());
            return null;
        }
    }

    private function tursoQueryAll(string $sql, array $params = []): array
    {
        try {
            $service = app(\App\Services\TursoService::class);
            return $service->query($sql, $params);
        } catch (\Exception $e) {
            Log::error('Telegram Turso queryAll error: ' . $e->getMessage());
            return [];
        }
    }

    private function tursoCount(string $table): int
    {
        $row = $this->tursoQuery("SELECT COUNT(*) as cnt FROM {$table}");
        return (int) ($row['cnt'] ?? 0);
    }

    private function tursoCountWhere(string $table, string $where): int
    {
        $row = $this->tursoQuery("SELECT COUNT(*) as cnt FROM {$table} WHERE {$where}");
        return (int) ($row['cnt'] ?? 0);
    }

    // ─── State persistence ─────────────────────────────────────

    private function getLastUpdateId(): int
    {
        $row = $this->tursoQuery(
            "SELECT state_value FROM telegram_bot_state WHERE state_key = ?",
            ['last_update_id']
        );
        return (int) ($row['state_value'] ?? 0);
    }

    private function saveLastUpdateId(int $id): void
    {
        try {
            $service = app(\App\Services\TursoService::class);
            $service->execute(
                "INSERT INTO telegram_bot_state (state_key, state_value, updated_at)"
                . " VALUES (?, ?, datetime('now'))"
                . " ON CONFLICT(state_key) DO UPDATE SET state_value = ?, updated_at = datetime('now')",
                ['last_update_id', (string) $id, (string) $id]
            );
        } catch (\Exception $e) {
            Log::error('Telegram save state error: ' . $e->getMessage());
        }
    }
}
