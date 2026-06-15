<?php

namespace App\Http\Controllers;

use Illuminate\Http\Request;
use Illuminate\Support\Facades\Cache;

class TelegramController extends Controller
{
    private const POLL_PID_KEY = 'telegram_poll_pid';

    public function status()
    {
        $pid = Cache::get(self::POLL_PID_KEY);
        $running = $pid ? $this->isProcessRunning($pid) : false;

        if (!$running) {
            Cache::forget(self::POLL_PID_KEY);
        }

        return response()->json([
            'running' => $running,
            'pid' => $running ? $pid : null,
        ]);
    }

    public function start()
    {
        $pid = Cache::get(self::POLL_PID_KEY);
        if ($pid && $this->isProcessRunning($pid)) {
            return response()->json(['status' => 'already_running', 'pid' => $pid]);
        }

        $scriptPath = base_path('PHP/telegram_poll.php');
        if (!file_exists($scriptPath)) {
            return response()->json(['status' => 'error', 'message' => 'Poll script not found'], 500);
        }

        // Find PHP binary
        $phpBin = $this->findPhpBinary();
        if (!$phpBin) {
            return response()->json(['status' => 'error', 'message' => 'PHP binary not found'], 500);
        }

        // Launch via PowerShell and capture PID
        $psCmd = 'powershell -Command "Start-Process -NoNewWindow -FilePath \'' . $phpBin . '\' -ArgumentList \'' . $scriptPath . '\', \'--loop\' -PassThru | Select-Object -ExpandProperty Id"';
        $output = [];
        exec($psCmd, $output, $exitCode);

        $pid = isset($output[0]) ? (int) trim($output[0]) : 0;

        if ($pid > 0 && $this->isProcessRunning($pid)) {
            Cache::put(self::POLL_PID_KEY, $pid, now()->addDay());
            return response()->json(['status' => 'started', 'pid' => $pid]);
        }

        return response()->json(['status' => 'error', 'message' => 'Failed to start poll process'], 500);
    }

    public function stop()
    {
        $pid = Cache::get(self::POLL_PID_KEY);
        if (!$pid) {
            return response()->json(['status' => 'not_running']);
        }

        if ($this->isProcessRunning($pid)) {
            exec('powershell -Command "taskkill /F /PID ' . $pid . '"', $output, $exitCode);
        }

        Cache::forget(self::POLL_PID_KEY);

        return response()->json(['status' => 'stopped']);
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
        // Common PHP paths on Windows
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

        // Fallback: try PATH
        $output = [];
        exec('where php 2>NUL', $output);
        if (!empty($output[0])) {
            return trim($output[0]);
        }

        return null;
    }
}
