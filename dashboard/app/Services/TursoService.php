<?php

namespace App\Services;

use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;

/**
 * Turso HTTP API Service
 *
 * Wraps the Turso /v2/pipeline HTTP API so we don't need
 * any PHP extension or special driver. Works on any hosting.
 *
 * Usage:
 *   $turso = app(TursoService::class);
 *
 *   // Select
 *   $rows = $turso->query("SELECT * FROM nodes WHERE hardware_id = ?", ['A1B2...']);
 *
 *   // Insert
 *   $id = $turso->insert("INSERT INTO nodes (hardware_id) VALUES (?)", ['A1B2...']);
 *
 *   // Update / Delete
 *   $turso->execute("UPDATE nodes SET name = ? WHERE hardware_id = ?", ['Node 1', 'A1B2...']);
 */
class TursoService
{
    private string $baseUrl;
    private string $authToken;

    public function __construct()
    {
        $this->baseUrl   = rtrim(env('TURSO_DATABASE_URL', ''), '/');
        $this->authToken = env('TURSO_AUTH_TOKEN', '');

        // Convert libsql:// to https:// for HTTP API
        if (str_starts_with($this->baseUrl, 'libsql://')) {
            $this->baseUrl = 'https://' . substr($this->baseUrl, 9);
        }
    }

    /**
     * Run a SELECT query and return rows as arrays.
     */
    public function query(string $sql, array $params = []): array
    {
        $response = $this->pipeline([
            $this->buildRequest('execute', $sql, $params),
            ['type' => 'close'],
        ]);

        // The response structure from Turso HTTP API:
        // { "type": "ok", "response": { "type": "execute", "result": { "cols": [...], "rows": [...] } } }
        $executeResponse = $response['response'] ?? [];
        $result = $executeResponse['result'] ?? [];
        $cols   = $result['cols'] ?? [];
        $rows   = $result['rows'] ?? [];

        return array_map(function ($row) use ($cols) {
            $assoc = [];
            foreach ($cols as $i => $col) {
                $assoc[$col['name']] = $row[$i]['value'] ?? null;
            }
            return $assoc;
        }, $rows);
    }

    /**
     * Run a SELECT and return the first row, or null.
     */
    public function queryOne(string $sql, array $params = []): ?array
    {
        $rows = $this->query($sql, $params);
        return $rows[0] ?? null;
    }

    /**
     * Run an INSERT and return the last insert ID.
     */
    public function insert(string $sql, array $params = []): int
    {
        $response = $this->pipeline([
            $this->buildRequest('execute', $sql, $params),
            ['type' => 'close'],
        ]);

        $executeResponse = $response['response'] ?? [];
        return $executeResponse['result']['last_insert_rowid'] ?? 0;
    }

    /**
     * Run INSERT OR IGNORE (no error if duplicate).
     */
    public function insertOrIgnore(string $sql, array $params = []): void
    {
        $this->pipeline([
            $this->buildRequest('execute', $sql, $params),
            ['type' => 'close'],
        ]);
    }

    /**
     * Run an INSERT and return the generated ID.
     */
    public function insertGetId(string $sql, array $params = []): int
    {
        return $this->insert($sql, $params);
    }

    /**
     * Run UPDATE, DELETE, or any statement that doesn't return rows.
     */
    public function execute(string $sql, array $params = []): int
    {
        $response = $this->pipeline([
            $this->buildRequest('execute', $sql, $params),
            ['type' => 'close'],
        ]);

        $executeResponse = $response['response'] ?? [];
        return $executeResponse['result']['affected_row_count'] ?? 0;
    }

    /**
     * Run multiple statements in a transaction.
     * Each statement is ['sql' => '...', 'params' => [...]]
     */
    public function transaction(array $statements): bool
    {
        $requests = [
            ['type' => 'execute', 'stmt' => ['sql' => 'BEGIN TRANSACTION']],
        ];

        foreach ($statements as $stmt) {
            $requests[] = $this->buildRequest('execute', $stmt['sql'], $stmt['params'] ?? []);
        }

        $requests[] = ['type' => 'execute', 'stmt' => ['sql' => 'COMMIT']];
        $requests[] = ['type' => 'close'];

        try {
            $this->pipeline($requests);
            return true;
        } catch (\Exception $e) {
            // Try to rollback
            try {
                $this->pipeline([
                    ['type' => 'execute', 'stmt' => ['sql' => 'ROLLBACK']],
                    ['type' => 'close'],
                ]);
            } catch (\Exception $rollbackError) {
                Log::error('Turso rollback failed: ' . $rollbackError->getMessage());
            }
            throw $e;
        }
    }

    /**
     * Get the last inserted row ID from the last INSERT.
     */
    public function lastInsertId(): int
    {
        $row = $this->queryOne('SELECT last_insert_rowid() as id');
        return (int)($row['id'] ?? 0);
    }

    /**
     * Check if the database connection is working.
     */
    public function health(): bool
    {
        try {
            $this->query('SELECT 1 as ok');
            return true;
        } catch (\Exception $e) {
            return false;
        }
    }

    // ─── Private helpers ──────────────────────────────────────────

    private function pipeline(array $requests): array
    {
        $url = $this->baseUrl . '/v2/pipeline';

        $response = Http::withToken($this->authToken)
            ->timeout(15)
            ->post($url, [
                'requests' => $requests,
            ]);

        if (!$response->successful()) {
            $body = $response->body();
            Log::error('Turso API error', [
                'status' => $response->status(),
                'body'   => substr($body, 0, 500),
                'sql'    => $this->extractSqlForLog($requests),
            ]);
            throw new \RuntimeException(
                'Turso API error: HTTP ' . $response->status() . ' — ' . substr($body, 0, 200)
            );
        }

        $json = $response->json();

        // Check for SQL errors in response
        if (isset($json['error'])) {
            throw new \RuntimeException('Turso SQL error: ' . $json['error']);
        }

        // Check each result for errors
        $results = $json['results'] ?? [];
        foreach ($results as $result) {
            if (isset($result['error'])) {
                throw new \RuntimeException('Turso SQL error: ' . $result['error']['message'] ?? json_encode($result['error']));
            }
        }

        // Return the first execute result
        foreach ($results as $result) {
            if (isset($result['response']['type']) && $result['response']['type'] === 'execute') {
                return $result;
            }
        }

        return $results[0] ?? [];
    }

    private function buildRequest(string $type, string $sql, array $params = []): array
    {
        $args = [];
        foreach ($params as $param) {
            if (is_null($param)) {
                $args[] = ['type' => 'null', 'value' => null];
            } else {
                // Turso HTTP API expects all values as strings
                $args[] = ['type' => 'text', 'value' => (string)$param];
            }
        }

        return [
            'type' => $type,
            'stmt' => [
                'sql'  => $sql,
                'args' => $args,
            ],
        ];
    }

    private function extractSqlForLog(array $requests): string
    {
        foreach ($requests as $r) {
            if (isset($r['stmt']['sql'])) {
                return $r['stmt']['sql'];
            }
        }
        return '(unknown)';
    }
}
