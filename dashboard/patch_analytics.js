const fs = require('fs');
const path = require('path');

const file = path.join(__dirname, 'app/Http/Controllers/DashboardController.php');
let content = fs.readFileSync(file, 'utf8');

// Fix analytics endpoint to return system_status, critical_events, counts, percentages
const oldAnalyticsReturn = `$stats[$key] = [
                "min" => $row->min_val ?? 0,
                "max" => $row->max_val ?? 0,
                "avg" => $row->avg_val ?? 0,
            ];
        }

        return response()->json(["sensor_stats" => $stats]);`;

const newAnalyticsReturn = `$stats[$key] = [
                "min" => $row->min_val ?? 0,
                "max" => $row->max_val ?? 0,
                "avg" => $row->avg_val ?? 0,
            ];
        }

        // Also compute counts, percentages, critical_events, system_status
        $period = $range;
        $thresholds = [
            "Temperature" => ["normal_min" => 22, "normal_max" => 30, "critical_low" => 18, "critical_high" => 34],
            "Humidity"    => ["normal_min" => 40, "normal_max" => 80, "critical_low" => 30, "critical_high" => 90],
            "WaterTemp"   => ["normal_min" => 20, "normal_max" => 28, "critical_low" => 15, "critical_high" => 32],
            "pH"          => ["normal_min" => 5.8, "normal_max" => 7.5, "critical_low" => 5.0, "critical_high" => 8.5],
            "TDS"         => ["normal_min" => 200, "normal_max" => 1200, "critical_low" => 100, "critical_high" => 1500],
            "Turbidity"   => ["normal_min" => 0, "normal_max" => 100, "critical_low" => -1, "critical_high" => 150],
            "Rain"        => ["normal_min" => 0, "normal_max" => 1, "critical_low" => 0, "critical_high" => 2],
        ];
        $data = DB::table("sensor_data as sd")
            ->join("sensor_readings as sr", "sd.reading_id", "=", "sr.id")
            ->where("sr.created_at", ">=", DB::raw("NOW() - INTERVAL {" . $period . "}"))
            ->whereRaw("sd.value REGEXP \"^-?[0-9]+(\\\\.[0-9]+)?$\"")
            ->select("sd.sensor", "sd.value", "sr.created_at")
            ->orderBy("sr.created_at")
            ->get();
        $counts = ["NORMAL" => 0, "ABNORMAL" => 0, "CRITICAL" => 0];
        $criticalEvents = [];
        foreach ($data as $row) {
            $value = (float)$row->value;
            $class = "NORMAL";
            if (isset($thresholds[$row->sensor])) {
                $t = $thresholds[$row->sensor];
                if (!is_numeric($value) || $value == -127 || $value == -999) {
                    $class = "CRITICAL";
                } elseif ($value < $t["critical_low"] || $value > $t["critical_high"]) {
                    $class = "CRITICAL";
                } elseif ($value < $t["normal_min"] || $value > $t["normal_max"]) {
                    $class = "ABNORMAL";
                }
            }
            $counts[$class]++;
            if ($class === "CRITICAL") {
                $criticalEvents[] = [
                    "time"   => date("H:i", strtotime($row->created_at)),
                    "sensor" => $row->sensor,
                    "value"  => round($value, 2),
                ];
            }
        }
        $total = $counts["NORMAL"] + $counts["ABNORMAL"] + $counts["CRITICAL"];
        $percentages = [];
        if ($total > 0) {
            $percentages["NORMAL"] = round($counts["NORMAL"] / $total * 100, 1);
            $percentages["ABNORMAL"] = round($counts["ABNORMAL"] / $total * 100, 1);
            $percentages["CRITICAL"] = round($counts["CRITICAL"] / $total * 100, 1);
        } else {
            $percentages = ["NORMAL" => 0, "ABNORMAL" => 0, "CRITICAL" => 0];
        }
        $criticalPct = $percentages["CRITICAL"] ?? 0;
        $systemStatus = $criticalPct > 20 ? "CRITICAL" : ($criticalPct > 5 ? "WARNING" : "NOMINAL");

        return response()->json([
            "sensor_stats" => $stats,
            "counts" => $counts,
            "percentages" => $percentages,
            "critical_events" => array_slice($criticalEvents, 0, 20),
            "system_status" => $systemStatus,
        ]);`;
content = content.replace(oldAnalyticsReturn, newAnalyticsReturn);

fs.writeFileSync(file, content, 'utf8');
console.log('Analytics endpoint enhanced successfully');