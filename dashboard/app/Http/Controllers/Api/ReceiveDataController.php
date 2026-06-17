<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Services\TursoService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;

class ReceiveDataController extends Controller
{
    private TursoService $turso;

    public function __construct(TursoService $turso)
    {
        $this->turso = $turso;
    }

    public function __invoke(Request $request)
    {
        // ── 1. Validate HTTP method ──────────────────────────────
        if (!$request->isMethod('post')) {
            return response()->json(['error' => 'Method not allowed'], 405);
        }

        // ── 2. Validate headers ──────────────────────────────────
        $apiKey    = $request->header('X-API-Key', '');
        $timestamp = $request->header('X-Timestamp', '');
        $signature = $request->header('X-Signature', '');

        if ($apiKey !== env('SMARTPONIC_API_KEY', 'smartponic-hq-key')) {
            return response()->json(['error' => 'Invalid API key'], 401);
        }

        if (!is_numeric($timestamp)) {
            return response()->json(['error' => 'Invalid timestamp'], 400);
        }

        $ts = (int)$timestamp;
        $maxAge = (int)env('SMARTPONIC_REQUEST_MAX_AGE', 300);
        if ($ts > 1700000000 && abs(time() - $ts) > $maxAge) {
            return response()->json(['error' => 'Timestamp out of window'], 401);
        }

        // ── 3. Verify body + signature ───────────────────────────
        $rawBody = $request->getContent();
        if (empty($rawBody)) {
            return response()->json(['error' => 'Empty request body'], 400);
        }

        $hmacSecret = env('SMARTPONIC_HMAC_SECRET', 'smartponic-hq-signature-secret');
        $expectedSig = hash('sha256', $timestamp . $rawBody . $hmacSecret);
        if (!hash_equals($expectedSig, $signature)) {
            return response()->json(['error' => 'Invalid signature'], 401);
        }

        // ── 4. Parse JSON ────────────────────────────────────────
        $data = json_decode($rawBody, true);
        if ($data === null) {
            return response()->json(['error' => 'Invalid JSON'], 400);
        }

        $hardwareId    = $data['hardware_id'] ?? '';
        $rssi          = isset($data['rssi'])       ? (int)$data['rssi']       : null;
        $snr           = isset($data['snr'])        ? (float)$data['snr']      : null;
        $eventType     = $data['event_type']         ?? 'telemetry';
        $sensors       = $data['sensors']             ?? [];
        $priorityIdx   = isset($data['priority'])    ? (int)$data['priority']   : 0;
        $reportModeIdx = isset($data['report_mode']) ? (int)$data['report_mode'] : 0;

        $priorityMap   = [0 => 'LOW', 1 => 'MEDIUM', 2 => 'HIGH'];
        $reportModeMap = [0 => 'NORMAL', 1 => 'ABNORMAL', 2 => 'CRITICAL'];
        $priorityStr   = $priorityMap[$priorityIdx]   ?? 'LOW';
        $reportModeStr = $reportModeMap[$reportModeIdx] ?? 'NORMAL';

        if (!preg_match('/^[0-9A-F]{16}$/', $hardwareId)) {
            return response()->json(['error' => 'Invalid hardware_id format'], 400);
        }

        if (!is_array($sensors) || count($sensors) === 0) {
            return response()->json(['error' => 'Missing or empty sensors array'], 400);
        }

        if (count($sensors) > 32) {
            return response()->json(['error' => 'Too many sensors (max 32)'], 400);
        }

        // ── 5. Process ───────────────────────────────────────────
        try {
            $statements = [];

            // Auto-register node
            $statements[] = [
                'sql'    => "INSERT OR IGNORE INTO nodes (hardware_id) VALUES (?)",
                'params' => [$hardwareId],
            ];
            $statements[] = [
                'sql'    => "UPDATE nodes SET last_seen = datetime('now') WHERE hardware_id = ?",
                'params' => [$hardwareId],
            ];

            // Insert sensor_readings
            $statements[] = [
                'sql'    => "INSERT INTO sensor_readings (hardware_id, rssi, snr, event_type, priority, report_mode) VALUES (?, ?, ?, ?, ?, ?)",
                'params' => [$hardwareId, $rssi, $snr, $eventType, $priorityStr, $reportModeStr],
            ];

            $this->turso->transaction($statements);

            // Get the reading ID (last insert rowid)
            $reading = $this->turso->queryOne(
                "SELECT id FROM sensor_readings WHERE hardware_id = ? ORDER BY id DESC LIMIT 1",
                [$hardwareId]
            );
            $readingId = (int)($reading['id'] ?? 0);

            $validCount   = 0;
            $invalidCount = 0;

            foreach ($sensors as $s) {
                $pin    = (int)($s['pin']    ?? 0);
                $sensor =      $s['sensor']  ?? '';
                $value  =      $s['value']   ?? '';

                if ($pin === 0 || $sensor === '' || $value === '') {
                    continue;
                }

                $reason = $this->checkInvalidSensor($sensor, $value);
                if ($reason !== null) {
                    $this->turso->execute(
                        "INSERT INTO invalid_sensor_data (hardware_id, pin, sensor, value, reason) VALUES (?, ?, ?, ?, ?)",
                        [$hardwareId, $pin, $sensor, $value, $reason]
                    );
                    $invalidCount++;
                }

                $this->turso->execute(
                    "INSERT INTO sensor_data (reading_id, pin, sensor, value) VALUES (?, ?, ?, ?)",
                    [$readingId, $pin, $sensor, $value]
                );
                $validCount++;
            }

            return response()->json([
                'status'     => 'ok',
                'reading_id' => $readingId,
                'sensors'    => $validCount,
                'invalid'    => $invalidCount,
            ]);

        } catch (\Exception $e) {
            Log::error('ReceiveData error: ' . $e->getMessage());
            return response()->json(['error' => 'Database error: ' . $e->getMessage()], 500);
        }
    }

    private function checkInvalidSensor(string $sensor, string $value): ?string
    {
        $lower = strtolower(trim($value));

        if ($lower === 'nan') {
            return 'Check DHT sensor (NaN)';
        }
        if (in_array($lower, ['-127', '-127.00', '-127.0'])) {
            return 'Check DS18B20 sensor (open/error)';
        }
        if (!is_numeric($value)) {
            return null;
        }

        $val = (float)$value;
        if ($sensor === 'Humidity' && ($val < 0 || $val > 100)) {
            return 'Humidity out of valid range (0-100%)';
        }
        if ($sensor === 'pH' && ($val < 0 || $val > 14)) {
            return 'pH out of valid range (0-14)';
        }

        return null;
    }
}
