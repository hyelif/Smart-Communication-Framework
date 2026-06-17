<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Services\TursoService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;

class ControlQueueController extends Controller
{
    private TursoService $turso;

    public function __construct(TursoService $turso)
    {
        $this->turso = $turso;
    }

    public function __invoke(Request $request)
    {
        if (!$request->isMethod('post')) {
            return response()->json(['error' => 'Method not allowed'], 405);
        }

        // HMAC auth (same as ReceiveData)
        $apiKey    = $request->header('X-API-Key', '');
        $timestamp = $request->header('X-Timestamp', '');
        $signature = $request->header('X-Signature', '');

        if ($apiKey !== env('SMARTPONIC_API_KEY', 'smartponic-hq-key')) {
            return response()->json(['error' => 'Invalid API key'], 401);
        }

        $rawBody = $request->getContent();
        $hmacSecret = env('SMARTPONIC_HMAC_SECRET', 'smartponic-hq-signature-secret');
        $expectedSig = hash('sha256', $timestamp . $rawBody . $hmacSecret);
        if (!hash_equals($expectedSig, $signature)) {
            return response()->json(['error' => 'Invalid signature'], 401);
        }

        $data = json_decode($rawBody, true);
        if ($data === null) {
            return response()->json(['error' => 'Invalid JSON'], 400);
        }

        $action     = $data['action'] ?? '';
        $hardwareId = $data['hardware_id'] ?? '';

        try {
            return match ($action) {
                'get_pending' => $this->getPending($hardwareId),
                'mark_sent'   => $this->markSent($data),
                'ack'         => $this->acknowledge($data),
                default       => response()->json(['error' => 'Unknown action'], 400),
            };
        } catch (\Exception $e) {
            Log::error('ControlQueue error: ' . $e->getMessage());
            return response()->json(['error' => 'Internal error'], 500);
        }
    }

    private function getPending(string $hardwareId)
    {
        $commands = $this->turso->query(
            "SELECT id, relay_id, action FROM relay_commands WHERE hardware_id = ? AND status = 'approved' ORDER BY id LIMIT 10",
            [$hardwareId]
        );

        return response()->json([
            'status'   => 'ok',
            'commands' => array_map(fn($c) => [
                'id'       => (int)$c['id'],
                'relay_id' => (int)$c['relay_id'],
                'action'   => $c['action'],
            ], $commands),
        ]);
    }

    private function markSent(array $data)
    {
        $cmdId = $data['command_id'] ?? 0;
        $this->turso->execute(
            "UPDATE relay_commands SET status = 'sent' WHERE id = ? AND status = 'approved'",
            [(int)$cmdId]
        );

        return response()->json(['status' => 'ok']);
    }

    private function acknowledge(array $data)
    {
        $cmdId  = $data['command_id'] ?? 0;
        $result = $data['result'] ?? 'done';

        $this->turso->execute(
            "UPDATE relay_commands SET status = ? WHERE id = ? AND status = 'sent'",
            [$result === 'done' ? 'done' : 'failed', (int)$cmdId]
        );

        return response()->json(['status' => 'ok']);
    }
}
