<?php

namespace App\Http\Controllers;

use App\Services\TursoService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Cache;
use Inertia\Inertia;

class DashboardController extends Controller
{
    // Cache TTL in seconds
    private const CACHE_TTL_SHORT = 15;
    private const CACHE_TTL_MEDIUM = 60;
    private const CACHE_TTL_LONG = 300;

    private const MAX_TREND_POINTS = 150;
    private const MAX_SIGNAL_POINTS = 150;

    private const ALLOWED_RANGES = ['1 HOUR', '6 HOUR', '24 HOUR', '7 DAY', '30 DAY'];

    private TursoService $turso;

    public function __construct(TursoService $turso)
    {
        $this->turso = $turso;
    }

    public function index()
    {
        $profiles = $this->getCachedProfiles();

        return Inertia::render("Dashboard/Overview", [
            "sensorReadings"   => $this->getLatestReading($profiles),
            "activeSensors"    => $this->getActiveSensors($profiles),
            "telegramBotState" => $this->getCachedBotState(),
            "nodes"            => $this->getCachedNodes(),
            "profiles"         => $profiles,
            "activeAlerts"     => $this->getCachedAlerts(),
            "signalStats"      => $this->getSignalStatsCached("24 HOUR"),
            "commHealth"       => $this->getCommHealthCached(),
        ]);
    }

    private function validateRange(string $range): string
    {
        return in_array($range, self::ALLOWED_RANGES, true) ? $range : '24 HOUR';
    }

    public function poll(Request $request)
    {
        $range = $this->validateRange($request->query("range", "24 HOUR"));
        $profiles = $this->getCachedProfiles();

        $result = [
            "sensor_readings"   => $this->getLatestReading($profiles),
            "active_sensors"    => $this->getActiveSensors($profiles),
            "nodes"             => $this->getCachedNodes(),
            "telegram_bot_state"=> $this->getCachedBotState(),
            "active_alerts"     => $this->getCachedAlerts(),
            "signal_stats"      => $this->getSignalStatsCached($range),
            "comm_health"       => $this->getCommHealthCached(),
            "profiles"          => $profiles,
            "timestamp"         => now()->toIso8601String(),
        ];

        return response()->json($result);
    }

    public function sensorTrends(Request $request)
    {
        $range  = $this->validateRange($request->query("range", "24 HOUR"));
        $sensor = $request->query("sensor", "Temperature");
        $cacheKey = "sensor_trends:{$sensor}:{$range}";

        $data = Cache::remember($cacheKey, self::CACHE_TTL_MEDIUM, function () use ($range, $sensor) {
            $rows = $this->turso->query(
                "SELECT sd.value, sr.created_at"
                . " FROM sensor_data AS sd"
                . " JOIN sensor_readings AS sr ON sd.reading_id = sr.id"
                . " WHERE sd.sensor = ?"
                . " AND sr.created_at >= datetime('now', '-{$this->sqliteRange($range)}')"
                . " ORDER BY sr.created_at"
                . " LIMIT ?",
                [$sensor, self::MAX_TREND_POINTS * 2]
            );

            if (count($rows) > self::MAX_TREND_POINTS) {
                $step = ceil(count($rows) / self::MAX_TREND_POINTS);
                $rows = $this->arrayNth($rows, $step);
            }

            return array_values(array_filter(array_map(fn($r) => [
                "value" => is_numeric($r['value']) ? (float) $r['value'] : null,
                "time"  => $r['created_at'],
            ], $rows), fn($r) => $r['value'] !== null));
        });

        return response()->json([
            "sensor" => $sensor,
            "range"  => $range,
            "data"   => $data,
            "count"  => count($data),
        ]);
    }

    public function signalHistory(Request $request)
    {
        $range = $this->validateRange($request->query("range", "24 HOUR"));
        $cacheKey = "signal_history:" . md5($range);

        $result = Cache::remember($cacheKey, self::CACHE_TTL_SHORT, function () use ($range) {
            $stats = $this->turso->queryOne(
                "SELECT"
                . " COUNT(*) as total,"
                . " MIN(rssi) as min_rssi,"
                . " MAX(rssi) as max_rssi,"
                . " AVG(rssi) as avg_rssi,"
                . " AVG(snr) as avg_snr,"
                . " SUM(CASE WHEN rssi < -100 OR snr < 5 THEN 1 ELSE 0 END) as critical_count"
                . " FROM sensor_readings"
                . " WHERE created_at >= datetime('now', '-{$this->sqliteRange($range)}')",
            );

            $rows = $this->turso->query(
                "SELECT rssi, snr, created_at"
                . " FROM sensor_readings"
                . " WHERE created_at >= datetime('now', '-{$this->sqliteRange($range)}')"
                . " ORDER BY created_at"
                . " LIMIT ?",
                [self::MAX_SIGNAL_POINTS * 2]
            );

            if (count($rows) > self::MAX_SIGNAL_POINTS) {
                $step = ceil(count($rows) / self::MAX_SIGNAL_POINTS);
                $rows = $this->arrayNth($rows, $step);
            }

            return [
                "data"  => array_values(array_map(fn($r) => [
                    "rssi" => (int) $r['rssi'],
                    "snr"  => (float) $r['snr'],
                    "time" => $r['created_at'],
                ], $rows)),
                "stats" => [
                    "total"    => (int) ($stats['total'] ?? 0),
                    "min_rssi" => (int) ($stats['min_rssi'] ?? 0),
                    "max_rssi" => (int) ($stats['max_rssi'] ?? 0),
                    "avg_rssi" => round((float) ($stats['avg_rssi'] ?? 0), 1),
                    "avg_snr"  => round((float) ($stats['avg_snr'] ?? 0), 1),
                    "critical" => (int) ($stats['critical_count'] ?? 0),
                ],
                "count" => count($rows),
            ];
        });

        return response()->json(array_merge($result, ["range" => $range]));
    }

    public function analytics(Request $request)
    {
        $range = $this->validateRange($request->query("range", "24 HOUR"));
        $cacheKey = "analytics:{$range}";

        $data = Cache::remember($cacheKey, self::CACHE_TTL_MEDIUM, function () use ($range) {
            try {
                $priorityStats = $this->turso->queryOne(
                    "SELECT"
                    . " SUM(CASE WHEN priority = 'HIGH' THEN 1 ELSE 0 END) as high,"
                    . " SUM(CASE WHEN priority = 'MEDIUM' THEN 1 ELSE 0 END) as medium,"
                    . " SUM(CASE WHEN priority = 'LOW' THEN 1 ELSE 0 END) as low,"
                    . " COUNT(*) as total"
                    . " FROM sensor_readings"
                    . " WHERE created_at >= datetime('now', '-{$this->sqliteRange($range)}')",
                );

                $modeStats = $this->turso->queryOne(
                    "SELECT"
                    . " SUM(CASE WHEN report_mode = 'NORMAL' THEN 1 ELSE 0 END) as normal,"
                    . " SUM(CASE WHEN report_mode = 'ABNORMAL' THEN 1 ELSE 0 END) as abnormal,"
                    . " SUM(CASE WHEN report_mode = 'CRITICAL' THEN 1 ELSE 0 END) as critical,"
                    . " COUNT(*) as total"
                    . " FROM sensor_readings"
                    . " WHERE created_at >= datetime('now', '-{$this->sqliteRange($range)}')",
                );

                return [
                    "priority"    => [
                        "HIGH"   => (int) ($priorityStats['high'] ?? 0),
                        "MEDIUM" => (int) ($priorityStats['medium'] ?? 0),
                        "LOW"    => (int) ($priorityStats['low'] ?? 0),
                        "total"  => (int) ($priorityStats['total'] ?? 0),
                    ],
                    "report_mode" => [
                        "NORMAL"   => (int) ($modeStats['normal'] ?? 0),
                        "ABNORMAL" => (int) ($modeStats['abnormal'] ?? 0),
                        "CRITICAL" => (int) ($modeStats['critical'] ?? 0),
                        "total"    => (int) ($modeStats['total'] ?? 0),
                    ],
                ];
            } catch (\Exception $e) {
                return [
                    "priority"    => ["HIGH" => 0, "MEDIUM" => 0, "LOW" => 0, "total" => 0],
                    "report_mode" => ["NORMAL" => 0, "ABNORMAL" => 0, "CRITICAL" => 0, "total" => 0],
                ];
            }
        });

        return response()->json(array_merge($data, [
            "range"        => $range,
            "generated_at" => now()->toIso8601String(),
        ]));
    }

    public function systemSummary(Request $request)
    {
        $profiles = $this->getCachedProfiles();

        return response()->json([
            "comm_health"     => $this->getCommHealthCached(),
            "sensor_readings" => $this->getLatestReading($profiles),
            "active_sensors"  => $this->getActiveSensors($profiles),
            "active_alerts"   => $this->getCachedAlerts(),
            "nodes"           => $this->getCachedNodes(),
            "profiles"        => $profiles,
            "timestamp"       => now()->toIso8601String(),
        ]);
    }

    // ─── CACHED HELPERS ─────────────────────────────────────────

    private function getCachedProfiles()
    {
        return Cache::remember("sensor_profiles", self::CACHE_TTL_LONG, function () {
            return $this->fetchProfiles();
        });
    }

    private function getCachedBotState()
    {
        return Cache::remember("telegram_bot_state", self::CACHE_TTL_MEDIUM, function () {
            try {
                $rows = $this->turso->query("SELECT * FROM telegram_bot_state ORDER BY state_key");
                return $this->sanitizeResult($rows);
            } catch (\Exception $e) {
                return [];
            }
        });
    }

    private function getCachedNodes()
    {
        return Cache::remember("nodes", self::CACHE_TTL_LONG, function () {
            try {
                $rows = $this->turso->query("SELECT * FROM nodes ORDER BY id");
                return $this->sanitizeResult($rows);
            } catch (\Exception $e) {
                return [];
            }
        });
    }

    private function getCachedAlerts()
    {
        return Cache::remember("active_alerts", self::CACHE_TTL_SHORT, function () {
            return $this->fetchAlerts();
        });
    }

    private function getSignalStatsCached($range)
    {
        return Cache::remember("signal_stats:" . md5($range), self::CACHE_TTL_SHORT, function () use ($range) {
            return $this->computeSignalStats($range);
        });
    }

    private function getCommHealthCached()
    {
        return Cache::remember("comm_health", self::CACHE_TTL_SHORT, function () {
            return $this->computeCommHealth();
        });
    }

    // ─── DATA FETCHERS ─────────────────────────────────────────

    private function fetchProfiles()
    {
        try {
            $rows = $this->turso->query("SELECT * FROM sensor_profiles");
            $profiles = [];
            foreach ($rows as $row) {
                $key = strtolower($row['sensor_key'] ?? '');
                if ($key === '') continue;
                $profiles[$key] = [
                    "label" => $row['label'] ?? $key,
                    "unit"  => $row['unit'] ?? '',
                    "icon"  => $this->sensorIcon($row['family'] ?? ''),
                    "color" => $row['accent'] ?? '#22d3ee',
                    "t_min" => (float) ($row['threshold_min'] ?? 0),
                    "t_max" => (float) ($row['threshold_max'] ?? 100),
                ];
            }
            return $profiles;
        } catch (\Exception $e) {
            return $this->defaultProfiles();
        }
    }

    private function defaultProfiles()
    {
        return [
            "temperature" => ["label" => "Temperature", "unit" => "°C", "icon" => "🌡️", "color" => "#f97316", "t_min" => 18, "t_max" => 35],
            "humidity"    => ["label" => "Humidity", "unit" => "%", "icon" => "💧", "color" => "#22d3ee", "t_min" => 30, "t_max" => 90],
            "watertemp"   => ["label" => "Water Temp", "unit" => "°C", "icon" => "🌊", "color" => "#06b6d4", "t_min" => 15, "t_max" => 32],
            "ph"          => ["label" => "pH", "unit" => "pH", "icon" => "⚗️", "color" => "#a855f7", "t_min" => 5.5, "t_max" => 8.5],
            "tds"         => ["label" => "TDS", "unit" => "ppm", "icon" => "🔬", "color" => "#10b981", "t_min" => 0, "t_max" => 1200],
            "turbidity"   => ["label" => "Turbidity", "unit" => "NTU", "icon" => "🌫️", "color" => "#64748b", "t_min" => 0, "t_max" => 1000],
            "rain"        => ["label" => "Rain", "unit" => "", "icon" => "🌧️", "color" => "#3b82f6", "t_min" => 0, "t_max" => 1],
        ];
    }

    private function fetchAlerts()
    {
        try {
            $rows = $this->turso->query(
                "SELECT * FROM alerts WHERE status = ? ORDER BY created_at DESC LIMIT 50",
                ['active']
            );
            return $this->sanitizeResult($rows);
        } catch (\Exception $e) {
            return [];
        }
    }

    private function computeSignalStats($range)
    {
        try {
            $stats = $this->turso->queryOne(
                "SELECT"
                . " COUNT(*) as total,"
                . " AVG(rssi) as avg_rssi,"
                . " MIN(rssi) as min_rssi,"
                . " MAX(rssi) as max_rssi,"
                . " AVG(snr) as avg_snr"
                . " FROM sensor_readings"
                . " WHERE created_at >= datetime('now', '-{$this->sqliteRange($range)}')",
            );

            $total = (int) ($stats['total'] ?? 0);
            $hasData = $total > 0;

            $pd = $this->turso->queryOne(
                "SELECT"
                . " SUM(CASE WHEN rssi > -70 AND snr > 15 THEN 1 ELSE 0 END) as excellent,"
                . " SUM(CASE WHEN rssi >= -85 AND snr >= 10 THEN 1 ELSE 0 END) as good,"
                . " SUM(CASE WHEN rssi >= -100 AND snr >= 5 THEN 1 ELSE 0 END) as fair,"
                . " SUM(CASE WHEN rssi >= -110 AND snr >= 0 THEN 1 ELSE 0 END) as poor,"
                . " SUM(CASE WHEN rssi < -110 OR snr < 0 THEN 1 ELSE 0 END) as critical"
                . " FROM sensor_readings"
                . " WHERE created_at >= datetime('now', '-{$this->sqliteRange($range)}')",
            );

            // Determine how fresh the latest reading is
            $lastReading = $this->turso->queryOne(
                "SELECT created_at FROM sensor_readings ORDER BY id DESC LIMIT 1"
            );
            $freshnessSeconds = $lastReading
                ? max(0, time() - strtotime($lastReading['created_at']))
                : null;

            return [
                "total"              => $total,
                "avg_rssi"           => $hasData ? round((float) ($stats['avg_rssi'] ?? 0), 1) : null,
                "min_rssi"           => $hasData ? (int) ($stats['min_rssi'] ?? -120) : null,
                "max_rssi"           => $hasData ? (int) ($stats['max_rssi'] ?? 0) : null,
                "avg_snr"            => $hasData ? round((float) ($stats['avg_snr'] ?? 0), 1) : null,
                "excellent"          => (int) ($pd['excellent'] ?? 0),
                "good"               => (int) ($pd['good'] ?? 0),
                "fair"               => (int) ($pd['fair'] ?? 0),
                "poor"               => (int) ($pd['poor'] ?? 0),
                "critical"           => (int) ($pd['critical'] ?? 0),
                "freshness_seconds"  => $freshnessSeconds,
                "is_online"          => $freshnessSeconds !== null && $freshnessSeconds < 300,
            ];
        } catch (\Exception $e) {
            return [
                "total" => 0, "avg_rssi" => null, "avg_snr" => null,
                "excellent" => 0, "good" => 0, "fair" => 0, "poor" => 0, "critical" => 0,
                "freshness_seconds" => null, "is_online" => false,
            ];
        }
    }

    private function computeCommHealth()
    {
        try {
            $last  = $this->turso->queryOne("SELECT * FROM sensor_readings ORDER BY id DESC LIMIT 1");
            $first = $this->turso->queryOne("SELECT created_at FROM sensor_readings ORDER BY id ASC LIMIT 1");
            $cnt   = $this->turso->queryOne("SELECT COUNT(*) as cnt FROM sensor_readings");

            $count = (int) ($cnt['cnt'] ?? 0);
            $hasData = $count > 0;

            $freshnessSeconds = $last ? max(0, time() - strtotime($last['created_at'])) : 0;
            $uptimeHours = $first ? round((time() - strtotime($first['created_at'])) / 3600, 1) : 0;
            $alertSummary = $this->getAlertSummaryCached();

            if (!$hasData) {
                return [
                    "delivery_rate"    => null,
                    "total_expected"   => 0,
                    "total_received"   => 0,
                    "sequence_gaps"    => 0,
                    "freshness_seconds" => null,
                    "freshness_label"  => "No data",
                    "is_fresh"         => false,
                    "is_stale"         => true,
                    "last_seen"        => null,
                    "last_rssi"        => null,
                    "last_snr"         => null,
                    "uptime_hours"     => 0,
                    "alert_summary"    => $alertSummary,
                ];
            }

            return [
                "delivery_rate"    => 100.0,
                "total_expected"   => $count,
                "total_received"   => $count,
                "sequence_gaps"    => 0,
                "freshness_seconds" => (int) $freshnessSeconds,
                "freshness_label"  => $this->formatFreshness($freshnessSeconds),
                "is_fresh"         => $freshnessSeconds < 60,
                "is_stale"         => $freshnessSeconds > 300,
                "last_seen"        => $last['created_at'] ?? null,
                "last_rssi"        => $last ? (int) $last['rssi'] : null,
                "last_snr"         => $last ? (float) $last['snr'] : null,
                "uptime_hours"     => (float) $uptimeHours,
                "alert_summary"    => $alertSummary,
            ];
        } catch (\Exception $e) {
            return [
                "delivery_rate" => null, "total_expected" => 0, "total_received" => 0,
                "freshness_seconds" => null, "freshness_label" => "No data",
                "is_fresh" => false, "is_stale" => true,
                "alert_summary" => ["total" => 0, "critical" => 0, "warning" => 0, "info" => 0],
            ];
        }
    }

    private function getAlertSummaryCached()
    {
        try {
            $active   = $this->turso->queryOne(
                "SELECT COUNT(*) as cnt FROM alerts WHERE status = ?", ['active']
            );
            $critical = $this->turso->queryOne(
                "SELECT COUNT(*) as cnt FROM alerts WHERE status = ? AND severity = ?",
                ['active', 'critical']
            );
            $warning  = $this->turso->queryOne(
                "SELECT COUNT(*) as cnt FROM alerts WHERE status = ? AND severity = ?",
                ['active', 'warning']
            );
            $info     = $this->turso->queryOne(
                "SELECT COUNT(*) as cnt FROM alerts WHERE status = ? AND severity = ?",
                ['active', 'info']
            );
            return [
                "total"    => (int) ($active['cnt'] ?? 0),
                "critical" => (int) ($critical['cnt'] ?? 0),
                "warning"  => (int) ($warning['cnt'] ?? 0),
                "info"     => (int) ($info['cnt'] ?? 0),
            ];
        } catch (\Exception $e) {
            return ["total" => 0, "critical" => 0, "warning" => 0, "info" => 0];
        }
    }

    private function getLatestReading($profiles)
    {
        try {
            $latest = $this->turso->queryOne(
                "SELECT * FROM sensor_readings ORDER BY id DESC LIMIT 1"
            );
            if (!$latest) return null;

            $minutes = $latest['created_at']
                ? round((time() - strtotime($latest['created_at'])) / 60, 1)
                : 0;

            return [
                "id"            => (int) $latest['id'],
                "hardware_id"   => $latest['hardware_id'],
                "rssi"          => (int) $latest['rssi'],
                "snr"           => (float) $latest['snr'],
                "signal_label"  => $this->signalLabel($latest['rssi']),
                "minutes_since" => (float) $minutes,
                "node_online"   => $minutes < 5,
                "created_at"    => $latest['created_at'],
            ];
        } catch (\Exception $e) {
            return null;
        }
    }

    private function getActiveSensors($profiles)
    {
        try {
            $latest = $this->turso->queryOne(
                "SELECT * FROM sensor_readings ORDER BY id DESC LIMIT 1"
            );
            if (!$latest) return [];

            // Staleness check: if the latest reading is older than 5 minutes, return empty
            $minutesSince = $latest['created_at']
                ? round((time() - strtotime($latest['created_at'])) / 60, 1)
                : 0;
            if ($minutesSince > 5) return [];

            $rows = $this->turso->query(
                "SELECT * FROM sensor_data WHERE reading_id = ? LIMIT 20",
                [$latest['id']]
            );

            return array_values(array_map(function ($row) use ($profiles) {
                $key = strtolower($row['sensor']);
                $profile = $profiles[$key] ?? null;
                $rawValue = $row['value'];
                $value = ($rawValue === "nan" || $rawValue === "NaN") ? null : $rawValue;

                $status = "normal";
                if ($profile && $value !== null && is_numeric($value)) {
                    $v = (float) $value;
                    if ($v < $profile["t_min"] || $v > $profile["t_max"]) {
                        $status = $v < $profile["t_min"] ? "low" : "high";
                    }
                }

                return [
                    "key"   => $key,
                    "sensor" => $row['sensor'],
                    "pin"   => $row['pin'],
                    "value" => $value,
                    "status" => $status,
                    "unit"  => $profile["unit"] ?? "",
                    "label" => $profile["label"] ?? $key,
                    "icon"  => $profile["icon"] ?? "❓",
                    "color" => $profile["color"] ?? "#888888",
                    "badge" => [
                        "text"  => strtoupper($status),
                        "class" => $status === "normal"
                            ? "bg-emerald-400/10 text-emerald-400"
                            : ($status === "low"
                                ? "bg-blue-400/10 text-blue-400"
                                : "bg-red-400/10 text-red-400"),
                    ],
                ];
            }, $rows));
        } catch (\Exception $e) {
            return [];
        }
    }

    // ─── SIGNAL HELPERS ────────────────────────────────────────

    private function signalLabel($rssi)
    {
        if ($rssi === null) return "Unknown";
        if ($rssi > -60) return "Excellent";
        if ($rssi > -75) return "Good";
        if ($rssi > -90) return "Fair";
        return "Poor";
    }

    private function formatFreshness(int $seconds)
    {
        if ($seconds < 60) return "{$seconds}s ago";
        if ($seconds < 3600) return round($seconds / 60, 1) . "m ago";
        return round($seconds / 3600, 1) . "h ago";
    }

    private function sensorIcon(string $family): string
    {
        $icons = [
            'DHT22'            => '🌡️',
            'Water Temperature' => '🌊',
            'Water Quality'    => '🔬',
            'Environment'      => '🌧️',
        ];
        return $icons[$family] ?? "❓";
    }

    // ─── ARRAY HELPERS ─────────────────────────────────────────

    /**
     * Convert an array of associative arrays to a plain array
     * (replaces json_decode(json_encode(...), true) pattern).
     */
    private function sanitizeResult(array $rows): array
    {
        return $rows;
    }

    /**
     * Convert MySQL INTERVAL range string to SQLite-compatible suffix.
     * e.g. "24 HOUR" → "24 hours", "7 DAY" → "7 days"
     */
    private function sqliteRange(string $range): string
    {
        $map = [
            '1 HOUR'  => '1 hours',
            '6 HOUR'  => '6 hours',
            '24 HOUR' => '24 hours',
            '7 DAY'   => '7 days',
            '30 DAY'  => '30 days',
        ];
        return $map[$range] ?? '24 hours';
    }

    /**
     * Replacement for Collection::nth(): return every $step-th element.
     */
    private function arrayNth(array $items, float $step): array
    {
        $result = [];
        $i = 0;
        foreach ($items as $item) {
            if ($i % (int) $step === 0) {
                $result[] = $item;
            }
            $i++;
        }
        return $result;
    }

    // ─── NODE SENSORS ENDPOINT ──────────────────────────────────

    public function nodeSensors(Request $request)
    {
        $hardwareId = $request->query("hardware_id");
        if (!$hardwareId) {
            return response()->json(["error" => "hardware_id is required"], 400);
        }

        $cacheKey = "node_sensors:" . md5($hardwareId);
        $data = Cache::remember($cacheKey, self::CACHE_TTL_SHORT, function () use ($hardwareId) {
            try {
                $readings = $this->turso->query(
                    "SELECT * FROM sensor_readings"
                    . " WHERE hardware_id = ?"
                    . " ORDER BY id DESC"
                    . " LIMIT 20",
                    [$hardwareId]
                );

                if (empty($readings)) {
                    return ["node" => null, "readings" => []];
                }

                $readingIds = array_column($readings, 'id');

                // Build placeholders for WHERE IN
                $placeholders = implode(',', array_fill(0, count($readingIds), '?'));
                $sensorRows = $this->turso->query(
                    "SELECT * FROM sensor_data"
                    . " WHERE reading_id IN ({$placeholders})"
                    . " ORDER BY reading_id, sensor",
                    $readingIds
                );

                // Group sensor data by reading_id using array_reduce
                $sensorData = array_reduce($sensorRows, function ($carry, $row) {
                    $rid = $row['reading_id'];
                    if (!isset($carry[$rid])) {
                        $carry[$rid] = [];
                    }
                    $carry[$rid][] = $row;
                    return $carry;
                }, []);

                $profiles = $this->getCachedProfiles();

                $result = array_map(function ($reading) use ($sensorData, $profiles) {
                    $rid = $reading['id'];
                    $sensors = isset($sensorData[$rid])
                        ? array_map(function ($row) use ($profiles) {
                            $key = strtolower($row['sensor']);
                            $profile = $profiles[$key] ?? null;
                            $rawValue = $row['value'];
                            $value = ($rawValue === "nan" || $rawValue === "NaN") ? null : $rawValue;

                            return [
                                "key"    => $key,
                                "sensor" => $row['sensor'],
                                "pin"    => $row['pin'],
                                "value"  => $value,
                                "unit"   => $profile["unit"] ?? "",
                                "label"  => $profile["label"] ?? $key,
                                "icon"   => $profile["icon"] ?? "?",
                                "color"  => $profile["color"] ?? "#888888",
                            ];
                        }, $sensorData[$rid])
                        : [];

                    return [
                        "id"          => (int) $reading['id'],
                        "rssi"        => (int) $reading['rssi'],
                        "snr"         => (float) $reading['snr'],
                        "priority"    => $reading['priority'] ?? "NORMAL",
                        "report_mode" => $reading['report_mode'] ?? "NORMAL",
                        "created_at"  => $reading['created_at'],
                        "sensors"     => array_values($sensors),
                    ];
                }, $readings);

                $node = $this->turso->queryOne(
                    "SELECT * FROM nodes WHERE hardware_id = ?",
                    [$hardwareId]
                );

                return [
                    "node" => $node ? [
                        "hardware_id" => $node['hardware_id'],
                        "name"        => $node['name'],
                        "location"    => $node['location'],
                        "first_seen"  => $node['first_seen'],
                        "last_seen"   => $node['last_seen'],
                    ] : null,
                    "readings" => array_values($result),
                ];
            } catch (\Exception $e) {
                return ["node" => null, "readings" => [], "error" => $e->getMessage()];
            }
        });

        return response()->json($data);
    }

    public function clearCache()
    {
        Cache::flush();
        return response()->json(["status" => "ok", "message" => "Cache cleared"]);
    }
}
