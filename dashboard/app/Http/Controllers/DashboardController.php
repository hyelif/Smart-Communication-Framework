<?php

namespace App\Http\Controllers;

use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
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
            $rows = DB::table("sensor_data as sd")
                ->join("sensor_readings as sr", "sd.reading_id", "=", "sr.id")
                ->where("sd.sensor", $sensor)
                ->where("sr.created_at", ">=", DB::raw("NOW() - INTERVAL {$range}"))
                ->whereRaw("sd.value REGEXP '^-?[0-9]+(\\.[0-9]+)?$'")
                ->orderBy("sr.created_at")
                ->select("sd.value", "sr.created_at")
                ->limit(self::MAX_TREND_POINTS * 2)
                ->get();

            if ($rows->count() > self::MAX_TREND_POINTS) {
                $step = ceil($rows->count() / self::MAX_TREND_POINTS);
                $rows = $rows->nth($step);
            }

            return $rows->map(fn($r) => [
                "value" => (float) $r->value,
                "time"  => $r->created_at,
            ])->values()->toArray();
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
            $stats = DB::table("sensor_readings")
                ->where("created_at", ">=", DB::raw("NOW() - INTERVAL {$range}"))
                ->selectRaw("COUNT(*) as total, MIN(rssi) as min_rssi, MAX(rssi) as max_rssi, AVG(rssi) as avg_rssi, AVG(snr) as avg_snr, SUM(CASE WHEN rssi < -100 OR snr < 5 THEN 1 ELSE 0 END) as critical_count")
                ->first();

            $rows = DB::table("sensor_readings")
                ->where("created_at", ">=", DB::raw("NOW() - INTERVAL {$range}"))
                ->orderBy("created_at")
                ->select("rssi", "snr", "created_at")
                ->limit(self::MAX_SIGNAL_POINTS * 2)
                ->get();

            if ($rows->count() > self::MAX_SIGNAL_POINTS) {
                $step = ceil($rows->count() / self::MAX_SIGNAL_POINTS);
                $rows = $rows->nth($step);
            }

            return [
                "data"  => $rows->map(fn($r) => ["rssi" => (int) $r->rssi, "snr" => (float) $r->snr, "time" => $r->created_at])->values()->toArray(),
                "stats" => [
                    "total" => (int) ($stats->total ?? 0),
                    "min_rssi" => (int) ($stats->min_rssi ?? 0),
                    "max_rssi" => (int) ($stats->max_rssi ?? 0),
                    "avg_rssi" => round((float) ($stats->avg_rssi ?? 0), 1),
                    "avg_snr"  => round((float) ($stats->avg_snr ?? 0), 1),
                    "critical" => (int) ($stats->critical_count ?? 0),
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
                $priorityStats = DB::table("sensor_readings")
                    ->where("created_at", ">=", DB::raw("NOW() - INTERVAL {$range}"))
                    ->selectRaw("SUM(CASE WHEN priority = 'HIGH' THEN 1 ELSE 0 END) as high, SUM(CASE WHEN priority = 'MEDIUM' THEN 1 ELSE 0 END) as medium, SUM(CASE WHEN priority = 'LOW' THEN 1 ELSE 0 END) as low, COUNT(*) as total")
                    ->first();

                $modeStats = DB::table("sensor_readings")
                    ->where("created_at", ">=", DB::raw("NOW() - INTERVAL {$range}"))
                    ->selectRaw("SUM(CASE WHEN report_mode = 'NORMAL' THEN 1 ELSE 0 END) as normal, SUM(CASE WHEN report_mode = 'ABNORMAL' THEN 1 ELSE 0 END) as abnormal, SUM(CASE WHEN report_mode = 'CRITICAL' THEN 1 ELSE 0 END) as critical, COUNT(*) as total")
                    ->first();

                return [
                    "priority" => ["HIGH" => (int) ($priorityStats->high ?? 0), "MEDIUM" => (int) ($priorityStats->medium ?? 0), "LOW" => (int) ($priorityStats->low ?? 0), "total" => (int) ($priorityStats->total ?? 0)],
                    "report_mode" => ["NORMAL" => (int) ($modeStats->normal ?? 0), "ABNORMAL" => (int) ($modeStats->abnormal ?? 0), "CRITICAL" => (int) ($modeStats->critical ?? 0), "total" => (int) ($modeStats->total ?? 0)],
                ];
            } catch (\Exception $e) {
                return ["priority" => ["HIGH" => 0, "MEDIUM" => 0, "LOW" => 0, "total" => 0], "report_mode" => ["NORMAL" => 0, "ABNORMAL" => 0, "CRITICAL" => 0, "total" => 0]];
            }
        });

        return response()->json(array_merge($data, ["range" => $range, "generated_at" => now()->toIso8601String()]));
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

    // CACHED HELPERS

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
                return $this->sanitizeResult(DB::table("telegram_bot_state")->orderBy("state_key")->get());
            } catch (\Exception $e) {
                return [];
            }
        });
    }

    private function getCachedNodes()
    {
        return Cache::remember("nodes", self::CACHE_TTL_LONG, function () {
            try {
                return $this->sanitizeResult(DB::table("nodes")->orderBy("id")->get());
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

    private function fetchProfiles()
    {
        try {
            $rows = DB::table("sensor_profiles")->get();
            $profiles = [];
            foreach ($rows as $row) {
                $key = strtolower($row->sensor_name ?? '');
                $profiles[$key] = [
                    "label" => $row->display_name ?? $key,
                    "unit"  => $row->unit ?? '',
                    "icon"  => $row->icon ?? "\u2753",
                    "color" => $row->color ?? "#22d3ee",
                    "t_min" => (float) ($row->threshold_min ?? 0),
                    "t_max" => (float) ($row->threshold_max ?? 100),
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
            return DB::table("alerts")->where("status", "active")->orderByDesc("created_at")->limit(50)->get()->toArray();
        } catch (\Exception $e) {
            return [];
        }
    }

    private function computeSignalStats($range)
    {
        try {
            $stats = DB::table("sensor_readings")
                ->where("created_at", ">=", DB::raw("NOW() - INTERVAL {$range}"))
                ->selectRaw("COUNT(*) as total, AVG(rssi) as avg_rssi, MIN(rssi) as min_rssi, MAX(rssi) as max_rssi, AVG(snr) as avg_snr")
                ->first();

            $total = (int) ($stats->total ?? 0);
            $hasData = $total > 0;

            $pd = DB::table("sensor_readings")
                ->where("created_at", ">=", DB::raw("NOW() - INTERVAL {$range}"))
                ->selectRaw("SUM(CASE WHEN rssi > -70 AND snr > 15 THEN 1 ELSE 0 END) as excellent, SUM(CASE WHEN rssi >= -85 AND snr >= 10 THEN 1 ELSE 0 END) as good, SUM(CASE WHEN rssi >= -100 AND snr >= 5 THEN 1 ELSE 0 END) as fair, SUM(CASE WHEN rssi >= -110 AND snr >= 0 THEN 1 ELSE 0 END) as poor, SUM(CASE WHEN rssi < -110 OR snr < 0 THEN 1 ELSE 0 END) as critical")
                ->first();

            // Determine how fresh the latest reading is
            $lastReading = DB::table("sensor_readings")->orderByDesc("id")->first();
            $freshnessSeconds = $lastReading ? max(0, time() - strtotime($lastReading->created_at)) : null;

            return [
                "total" => $total,
                "avg_rssi" => $hasData ? round((float) ($stats->avg_rssi ?? 0), 1) : null,
                "min_rssi" => $hasData ? (int) ($stats->min_rssi ?? -120) : null,
                "max_rssi" => $hasData ? (int) ($stats->max_rssi ?? 0) : null,
                "avg_snr" => $hasData ? round((float) ($stats->avg_snr ?? 0), 1) : null,
                "excellent" => (int) ($pd->excellent ?? 0),
                "good" => (int) ($pd->good ?? 0),
                "fair" => (int) ($pd->fair ?? 0),
                "poor" => (int) ($pd->poor ?? 0),
                "critical" => (int) ($pd->critical ?? 0),
                "freshness_seconds" => $freshnessSeconds,
                "is_online" => $freshnessSeconds !== null && $freshnessSeconds < 300,
            ];
        } catch (\Exception $e) {
            return ["total" => 0, "avg_rssi" => null, "avg_snr" => null, "excellent" => 0, "good" => 0, "fair" => 0, "poor" => 0, "critical" => 0, "freshness_seconds" => null, "is_online" => false];
        }
    }

    private function computeCommHealth()
    {
        try {
            $last = DB::table("sensor_readings")->orderByDesc("id")->first();
            $first = DB::table("sensor_readings")->orderBy("id", "asc")->first();
            $cnt = DB::table("sensor_readings")->count();

            $hasData = $cnt > 0;

            $freshnessSeconds = $last ? max(0, time() - strtotime($last->created_at)) : 0;
            $uptimeHours = $first ? round((time() - strtotime($first->created_at)) / 3600, 1) : 0;
            $alertSummary = $this->getAlertSummaryCached();

            if (!$hasData) {
                return [
                    "delivery_rate" => null,
                    "total_expected" => 0,
                    "total_received" => 0,
                    "sequence_gaps" => 0,
                    "freshness_seconds" => null,
                    "freshness_label" => "No data",
                    "is_fresh" => false,
                    "is_stale" => true,
                    "last_seen" => null,
                    "last_rssi" => null,
                    "last_snr" => null,
                    "uptime_hours" => 0,
                    "alert_summary" => $alertSummary,
                ];
            }

            return [
                "delivery_rate" => 100.0,
                "total_expected" => (int) $cnt,
                "total_received" => (int) $cnt,
                "sequence_gaps" => 0,
                "freshness_seconds" => (int) $freshnessSeconds,
                "freshness_label" => $this->formatFreshness($freshnessSeconds),
                "is_fresh" => $freshnessSeconds < 60,
                "is_stale" => $freshnessSeconds > 300,
                "last_seen" => $last ? $last->created_at : null,
                "last_rssi" => $last ? (int) $last->rssi : null,
                "last_snr" => $last ? (float) $last->snr : null,
                "uptime_hours" => (float) $uptimeHours,
                "alert_summary" => $alertSummary,
            ];
        } catch (\Exception $e) {
            return ["delivery_rate" => null, "total_expected" => 0, "total_received" => 0, "freshness_seconds" => null, "freshness_label" => "No data", "is_fresh" => false, "is_stale" => true, "alert_summary" => ["total" => 0, "critical" => 0, "warning" => 0, "info" => 0]];
        }
    }

    private function getAlertSummaryCached()
    {
        try {
            $active = DB::table("alerts")->where("status", "active")->count();
            $critical = DB::table("alerts")->where("status", "active")->where("severity", "critical")->count();
            $warning = DB::table("alerts")->where("status", "active")->where("severity", "warning")->count();
            $info = DB::table("alerts")->where("status", "active")->where("severity", "info")->count();
            return ["total" => (int) $active, "critical" => (int) $critical, "warning" => (int) $warning, "info" => (int) $info];
        } catch (\Exception $e) {
            return ["total" => 0, "critical" => 0, "warning" => 0, "info" => 0];
        }
    }

    private function getLatestReading($profiles)
    {
        try {
            $latest = DB::table("sensor_readings")->orderByDesc("id")->first();
            if (!$latest) return null;

            $minutes = $latest->created_at ? round((time() - strtotime($latest->created_at)) / 60, 1) : 0;

            return [
                "id" => (int) $latest->id,
                "hardware_id" => $latest->hardware_id,
                "rssi" => (int) $latest->rssi,
                "snr" => (float) $latest->snr,
                "signal_label" => $this->signalLabel($latest->rssi),
                "minutes_since" => (float) $minutes,
                "node_online" => $minutes < 5,
                "created_at" => $latest->created_at,
            ];
        } catch (\Exception $e) {
            return null;
        }
    }

    private function getActiveSensors($profiles)
    {
        try {
            $latest = DB::table("sensor_readings")->orderByDesc("id")->first();
            if (!$latest) return [];

            // Staleness check: if the latest reading is older than 5 minutes, return empty
            $minutesSince = $latest->created_at
                ? round((time() - strtotime($latest->created_at)) / 60, 1)
                : 0;
            if ($minutesSince > 5) return [];

            $rows = DB::table("sensor_data")->where("reading_id", $latest->id)->limit(20)->get();

            return $rows->map(function ($row) use ($profiles) {
                $key = strtolower($row->sensor);
                $profile = $profiles[$key] ?? null;
                $rawValue = $row->value;
                $value = ($rawValue === "nan" || $rawValue === "NaN") ? null : $rawValue;

                $status = "normal";
                if ($profile && $value !== null && is_numeric($value)) {
                    $v = (float) $value;
                    if ($v < $profile["t_min"] || $v > $profile["t_max"]) {
                        $status = $v < $profile["t_min"] ? "low" : "high";
                    }
                }

                return [
                    "key" => $key,
                    "sensor" => $row->sensor,
                    "pin" => $row->pin,
                    "value" => $value,
                    "status" => $status,
                    "unit" => $profile["unit"] ?? "",
                    "label" => $profile["label"] ?? $key,
                    "icon" => $profile["icon"] ?? "\u2753",
                    "color" => $profile["color"] ?? "#888888",
                    "badge" => [
                        "text" => strtoupper($status),
                        "class" => $status === "normal" ? "bg-emerald-400/10 text-emerald-400" : ($status === "low" ? "bg-blue-400/10 text-blue-400" : "bg-red-400/10 text-red-400"),
                    ],
                ];
            })->values()->toArray();
        } catch (\Exception $e) {
            return [];
        }
    }

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

    private function sanitizeResult($collection)
    {
        return json_decode(json_encode($collection), true);
    }

    public function nodeSensors(Request $request)
    {
        $hardwareId = $request->query("hardware_id");
        if (!$hardwareId) {
            return response()->json(["error" => "hardware_id is required"], 400);
        }

        $cacheKey = "node_sensors:" . md5($hardwareId);
        $data = Cache::remember($cacheKey, self::CACHE_TTL_SHORT, function () use ($hardwareId) {
            try {
                $readings = DB::table("sensor_readings")
                    ->where("hardware_id", $hardwareId)
                    ->orderByDesc("id")
                    ->limit(20)
                    ->get();

                if ($readings->isEmpty()) {
                    return ["node" => null, "readings" => []];
                }

                $readingIds = $readings->pluck("id");
                $sensorData = DB::table("sensor_data")
                    ->whereIn("reading_id", $readingIds)
                    ->orderBy("reading_id")
                    ->orderBy("sensor")
                    ->get()
                    ->groupBy("reading_id");

                $profiles = $this->getCachedProfiles();

                $result = $readings->map(function ($reading) use ($sensorData, $profiles) {
                    $sensors = collect();
                    if ($sensorData->has($reading->id)) {
                        $sensors = collect($sensorData[$reading->id])->map(function ($row) use ($profiles) {
                            $key = strtolower($row->sensor);
                            $profile = $profiles[$key] ?? null;
                            $rawValue = $row->value;
                            $value = ($rawValue === "nan" || $rawValue === "NaN") ? null : $rawValue;

                            return [
                                "key" => $key,
                                "sensor" => $row->sensor,
                                "pin" => $row->pin,
                                "value" => $value,
                                "unit" => $profile["unit"] ?? "",
                                "label" => $profile["label"] ?? $key,
                                "icon" => $profile["icon"] ?? "?",
                                "color" => $profile["color"] ?? "#888888",
                            ];
                        })->values();
                    }

                    return [
                        "id" => (int) $reading->id,
                        "rssi" => (int) $reading->rssi,
                        "snr" => (float) $reading->snr,
                        "priority" => $reading->priority ?? "NORMAL",
                        "report_mode" => $reading->report_mode ?? "NORMAL",
                        "created_at" => $reading->created_at,
                        "sensors" => $sensors,
                    ];
                });

                $node = DB::table("nodes")->where("hardware_id", $hardwareId)->first();

                return [
                    "node" => $node ? [
                        "hardware_id" => $node->hardware_id,
                        "name" => $node->name,
                        "location" => $node->location,
                        "first_seen" => $node->first_seen,
                        "last_seen" => $node->last_seen,
                    ] : null,
                    "readings" => $result,
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
