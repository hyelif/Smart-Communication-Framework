<?php

namespace App\Providers;

use Illuminate\Support\ServiceProvider;
use Illuminate\Support\Facades\App;
use Illuminate\Support\Facades\Cache;
use App\Services\TursoService;

class AppServiceProvider extends ServiceProvider
{
    private const POLL_PID_KEY = 'telegram_poll_pid';
    private const BOT_COOLDOWN_KEY = 'telegram_auto_start_cooldown';
    private const COOLDOWN_SECONDS = 30;

    public function register(): void
    {
        $this->app->singleton(TursoService::class, function () {
            return new TursoService();
        });
    }

    public function boot(): void
    {
        if (App::environment('local')) {
            $this->validateViteHotFile();
        }

        // Auto-start Telegram bot if it's not running.
        // Uses a 30s cooldown so every request doesn't try to launch it.
        $this->ensureTelegramBotRunning();
    }

    private function ensureTelegramBotRunning(): void
    {
        // Cooldown: only check once every 60 seconds
        if (Cache::get(self::BOT_COOLDOWN_KEY)) {
            return;
        }
        Cache::put(self::BOT_COOLDOWN_KEY, true, 60);

        // Check if ANY telegram_poll.php process is already running (not just our cached PID)
        if ($this->isTelegramProcessRunning()) {
            return; // bot is already alive
        }

        // Also check the cached PID as a fast path
        $pid = Cache::get(self::POLL_PID_KEY);
        if ($pid && $this->isProcessRunning($pid)) {
            return;
        }

        // No bot running — launch it.
        $scriptPath = 'C:\\Users\\HAKIMIE\\smartponic_v2\\PHP\\telegram_poll.php';
        if (!file_exists($scriptPath)) {
            logger()->warning('Telegram auto-start: poll script not found at ' . $scriptPath);
            return;
        }

        $phpBin = $this->findPhpBinary();
        if (!$phpBin) {
            logger()->warning('Telegram auto-start: PHP binary not found');
            return;
        }

        // Launch hidden background process and capture PID.
        // Use WindowStyle Hidden (not NoNewWindow) so the child process
        // is fully detached from the console — otherwise the infinite
        // bot loop can interfere with exec() return.
        $psCmd = 'powershell -Command "Start-Process -WindowStyle Hidden -FilePath \'' . $phpBin . '\' -ArgumentList \'' . $scriptPath . '\', \'--loop\' -PassThru | Select-Object -ExpandProperty Id"';
        $output = [];
        exec($psCmd, $output, $exitCode);

        $newPid = isset($output[0]) ? (int) trim($output[0]) : 0;

        if ($newPid > 0 && $this->isProcessRunning($newPid)) {
            Cache::put(self::POLL_PID_KEY, $newPid, now()->addDay());
            logger()->info("Telegram bot auto-started (PID: {$newPid})");
        } else {
            logger()->warning('Telegram auto-start: failed to start poll process');
        }
    }

    private function isTelegramProcessRunning(): bool
    {
        $output = [];
        exec('powershell -Command "Get-Process php* | Select-Object Id,CommandLine | ConvertTo-Json" 2>NUL', $output);
        $json = implode('', $output);
        if (empty($json)) return false;

        $processes = json_decode($json, true);
        if (empty($processes)) return false;

        // If single object, wrap in array
        if (isset($processes['Id'])) {
            $processes = [$processes];
        }

        foreach ($processes as $p) {
            $cmdLine = $p['CommandLine'] ?? '';
            if (str_contains($cmdLine, 'telegram_poll.php')) {
                return true;
            }
        }
        return false;
    }

    private function isProcessRunning(int $pid): bool
    {
        $output = [];
        exec('powershell -Command "tasklist /FI \'PID eq ' . $pid . '\' /NH"', $output);
        foreach ($output as $line) {
            if (str_contains($line, (string)$pid)) {
                return true;
            }
        }
        return false;
    }

    private function findPhpBinary(): ?string
    {
        $candidates = [
            'C:\\xampp\\php\\php.exe',
            'C:\\php\\php.exe',
            'C:\\Program Files\\php\\php.exe',
            'C:\\Program Files (x86)\\php\\php.exe',
        ];

        foreach ($candidates as $path) {
            if (file_exists($path)) {
                return $path;
            }
        }

        $output = [];
        exec('where php 2>NUL', $output);
        if (!empty($output[0])) {
            return trim($output[0]);
        }

        return null;
    }

    private function validateViteHotFile(): void
    {
        $hotPath = public_path('hot');

        if (!file_exists($hotPath)) {
            return;
        }

        $content = file_get_contents($hotPath);

        if ($content === false || $content === '') {
            return;
        }

        // Fix 0.0.0.0 to 127.0.0.1
        $fixed = str_replace('http://0.0.0.0:', 'http://127.0.0.1:', $content);

        if ($fixed !== $content) {
            file_put_contents($hotPath, $fixed);
            $content = $fixed;
            logger()->warning('Vite hot file contained 0.0.0.0 -> corrected to 127.0.0.1.');
        }

        // If Vite dev server is not reachable, remove hot file to fall back to
        // compiled assets in public/build/. This prevents a blank/broken UI when
        // Vite was left running from a prior session but is no longer available.
        $parsedUrl = parse_url(trim($content));
        $host = $parsedUrl['host'] ?? '127.0.0.1';
        $port = $parsedUrl['port'] ?? 5173;

        $fp = @fsockopen($host, $port, $errno, $errstr, 1.0);
        if ($fp === false) {
            @unlink($hotPath);
            logger()->warning("Vite hot file removed: dev server not reachable at {$host}:{$port}");
        } else {
            fclose($fp);
        }
    }
}