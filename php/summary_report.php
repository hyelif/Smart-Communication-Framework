<?php
/**
 * SmartPonic System Summary Report
 * Generates analytics summary every 6 hours
 * Run via: php summary_report.php [period]
 */

require_once __DIR__ . "/db.php";

class SystemSummaryReport {
    
    private $thresholds = [
        "Temperature" => ["normal_min" => 22, "normal_max" => 30, "critical_low" => 18, "critical_high" => 34],
        "Humidity"    => ["normal_min" => 40, "normal_max" => 80, "critical_low" => 30, "critical_high" => 90],
        "WaterTemp"   => ["normal_min" => 20, "normal_max" => 28, "critical_low" => 15, "critical_high" => 32],
        "pH"          => ["normal_min" => 5.8, "normal_max" => 7.5, "critical_low" => 5.0, "critical_high" => 8.5],
        "TDS"         => ["normal_min" => 200, "normal_max" => 1200, "critical_low" => 100, "critical_high" => 1500],
        "Turbidity"   => ["normal_min" => 0, "normal_max" => 100, "critical_low" => -1, "critical_high" => 150],
        "Rain"        => ["normal_min" => 0, "normal_max" => 1, "critical_low" => 0, "critical_high" => 2],
    ];
    
    private $db;
    
    public function __construct() {
        $this->db = getDb();
    }
    
    public function classifyReading(string $sensor, float $value): string {
        if (!isset($this->thresholds[$sensor])) {
            return "NORMAL";
        }
        
        $t = $this->thresholds[$sensor];
        
        if (!is_numeric($value) || $value == -127 || $value == -999) {
            return "CRITICAL";
        }
        
        if ($value < $t["critical_low"] || $value > $t["critical_high"]) {
            return "CRITICAL";
        }
        
        if ($value < $t["normal_min"] || $value > $t["normal_max"]) {
            return "ABNORMAL";
        }
        
        return "NORMAL";
    }
    
    public function getSummaryData(string $startTime, string $endTime): array {
        $sql = "SELECT sd.sensor, sd.value, sr.created_at
                FROM sensor_data sd
                JOIN sensor_readings sr ON sd.reading_id = sr.id
                WHERE sr.created_at BETWEEN :start AND :end
                AND sd.value REGEXP :pattern
                ORDER BY sr.created_at";
        
        $stmt = $this->db->prepare($sql);
        $stmt->execute(["start" => $startTime, "end" => $endTime, "pattern" => "^-?[0-9]+(\.[0-9]+)?$"]);
        return $stmt->fetchAll(PDO::FETCH_ASSOC);
    }
    
    public function generateReport(string $period = "6 HOUR"): array {
        $endTime = date("Y-m-d H:i:s");
        $startTime = date("Y-m-d H:i:s", strtotime("-{$period}"));
        
        $data = $this->getSummaryData($startTime, $endTime);
        
        $total = count($data);
        $counts = ["NORMAL" => 0, "ABNORMAL" => 0, "CRITICAL" => 0];
        $sensorStats = [];
        $criticalEvents = [];
        
        foreach ($data as $row) {
            $sensor = $row["sensor"];
            $value = (float)$row["value"];
            $time = date("H:i", strtotime($row["created_at"]));
            
            if (!isset($sensorStats[$sensor])) {
                $sensorStats[$sensor] = ["values" => [], "critical_count" => 0];
            }
            
            $class = $this->classifyReading($sensor, $value);
            $counts[$class]++;
            
            if ($class === "CRITICAL") {
                $sensorStats[$sensor]["critical_count"]++;
                $criticalEvents[] = [
                    "time" => $time,
                    "sensor" => $sensor,
                    "value" => $value
                ];
            }
            
            if (is_numeric($value) && $value > -127 && $value < 9999) {
                $sensorStats[$sensor]["values"][] = $value;
            }
        }
        
        $stats = [];
        foreach ($sensorStats as $sensor => $info) {
            $values = $info["values"];
            if (count($values) > 0) {
                $stats[$sensor] = [
                    "max" => max($values),
                    "min" => min($values),
                    "avg" => array_sum($values) / count($values),
                    "critical" => $info["critical_count"]
                ];
            }
        }
        
        $percentages = [];
        if ($total > 0) {
            $percentages = [
                "NORMAL" => round(($counts["NORMAL"] / $total) * 100, 1),
                "ABNORMAL" => round(($counts["ABNORMAL"] / $total) * 100, 1),
                "CRITICAL" => round(($counts["CRITICAL"] / $total) * 100, 1),
            ];
        }
        
        $criticalPct = $percentages["CRITICAL"] ?? 0;
        if ($criticalPct <= 2) {
            $status = "STABLE";
        } elseif ($criticalPct <= 10) {
            $status = "MODERATE INSTABILITY";
        } else {
            $status = "CRITICAL INSTABILITY";
        }
        
        return [
            "date" => date("Y-m-d"),
            "period" => $period,
            "start_time" => $startTime,
            "end_time" => $endTime,
            "total_records" => $total,
            "counts" => $counts,
            "percentages" => $percentages,
            "sensor_stats" => $stats,
            "critical_events" => $criticalEvents,
            "system_status" => $status
        ];
    }
    
    public function formatReport(array $report): string {
        $output = [];
        
        $output[] = "=== SYSTEM SUMMARY REPORT ===";
        $output[] = "";
        $output[] = "Date: " . $report["date"];
        $output[] = "Period: Last " . $report["period"];
        $output[] = "";
        $output[] = "Total Records: " . $report["total_records"];
        $output[] = sprintf("Normal Conditions: %d (%.1f%%)", 
            $report["counts"]["NORMAL"], $report["percentages"]["NORMAL"]);
        $output[] = sprintf("Abnormal Conditions: %d (%.1f%%)", 
            $report["counts"]["ABNORMAL"], $report["percentages"]["ABNORMAL"]);
        $output[] = sprintf("Critical Conditions: %d (%.1f%%)", 
            $report["counts"]["CRITICAL"], $report["percentages"]["CRITICAL"]);
        $output[] = "";
        
        $sensorLabels = [
            "Temperature" => "Temperature",
            "Humidity" => "Humidity",
            "WaterTemp" => "Water Temp",
            "pH" => "pH",
            "TDS" => "TDS",
            "Turbidity" => "Turbidity",
            "Rain" => "Rain"
        ];
        
        foreach ($report["sensor_stats"] as $sensor => $stats) {
            $label = $sensorLabels[$sensor] ?? $sensor;
            $unit = $this->getSensorUnit($sensor);
            $output[] = $label . ":";
            $output[] = sprintf("  Max: %.1f%s", $stats["max"], $unit);
            $output[] = sprintf("  Min: %.1f%s", $stats["min"], $unit);
            $output[] = sprintf("  Avg: %.1f%s", $stats["avg"], $unit);
            $output[] = "";
        }
        
        if (count($report["critical_events"]) > 0) {
            $output[] = "Critical Events:";
            foreach (array_slice($report["critical_events"], 0, 10) as $event) {
                $output[] = sprintf("  %s -> %s %.1f", 
                    $event["time"], 
                    $event["sensor"], 
                    $event["value"]);
            }
            $output[] = "";
        }
        
        $output[] = "System Status:";
        $output[] = "  " . $report["system_status"];
        $output[] = "";
        $output[] = "---------------------------------------";
        
        return implode("\n", $output);
    }
    
    private function getSensorUnit(string $sensor): string {
        $units = [
            "Temperature" => chr(176) . "C",
            "Humidity" => "%",
            "WaterTemp" => chr(176) . "C",
            "pH" => " pH",
            "TDS" => " ppm",
            "Turbidity" => " NTU",
            "Rain" => ""
        ];
        return $units[$sensor] ?? "";
    }
}

// CLI Execution
if (php_sapi_name() === "cli" || (isset($argv) && count($argv) > 0)) {
    $period = $argv[1] ?? "6 HOUR";
    
    echo "Generating System Summary Report...\n";
    echo "Period: {$period}\n\n";
    
    $report = new SystemSummaryReport();
    $result = $report->generateReport($period);
    
    echo $report->formatReport($result);
    echo "\n";
}
