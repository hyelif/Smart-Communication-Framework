<?php

namespace App\Http\Controllers;

use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use PhpOffice\PhpSpreadsheet\Spreadsheet;
use PhpOffice\PhpSpreadsheet\Writer\Xlsx;
use PhpOffice\PhpSpreadsheet\Style\Alignment;
use PhpOffice\PhpSpreadsheet\Style\Border;
use PhpOffice\PhpSpreadsheet\Style\Fill;
use PhpOffice\PhpSpreadsheet\Chart\Chart;
use PhpOffice\PhpSpreadsheet\Chart\DataSeries;
use PhpOffice\PhpSpreadsheet\Chart\DataSeriesValues;
use PhpOffice\PhpSpreadsheet\Chart\Legend;
use PhpOffice\PhpSpreadsheet\Chart\PlotArea;
use PhpOffice\PhpSpreadsheet\Chart\Title;
use PhpOffice\PhpSpreadsheet\Shared\Date as ExcelDate;

class ExportController extends Controller
{
    private const SENSOR_NAMES = [
        'Temperature' => 'Temperature',
        'Humidity'    => 'Humidity',
        'WaterTemp'   => 'Water Temp',
        'pH'          => 'pH Level',
        'TDS'         => 'TDS',
        'Turbidity'   => 'Turbidity',
        'Rain'        => 'Rain',
    ];

    private const SENSOR_UNITS = [
        'Temperature' => '°C',
        'Humidity'    => '%',
        'WaterTemp'   => '°C',
        'pH'          => 'pH',
        'TDS'         => 'ppm',
        'Turbidity'   => 'NTU',
        'Rain'        => '',
    ];

    private const ALLOWED_RANGES = ['1 HOUR', '6 HOUR', '24 HOUR', '7 DAY', '30 DAY'];
    private const MAX_POINTS_PER_SHEET = 1000;

    public function export(Request $request)
    {
        $range = $this->validateRange($request->query('range', '24 HOUR'));
        $hardwareId = $request->query('hardware_id');

        $sensorTypes = DB::table('sensor_data')
            ->select('sensor')
            ->distinct()
            ->pluck('sensor');

        if ($sensorTypes->isEmpty()) {
            return response()->json(['error' => 'No data found'], 404);
        }

        $spreadsheet = new Spreadsheet();
        $spreadsheet->getProperties()
            ->setCreator('SmartPonic')
            ->setTitle("SmartPonic Sensor Export - {$range}")
            ->setDescription("Multi-sheet sensor data export");

        // Remove default sheet — we'll create per-sensor sheets
        $spreadsheet->removeSheetByIndex(0);

        // Node info sheet
        $this->createNodeInfoSheet($spreadsheet, $hardwareId, $range);

        $first = true;
        $startTime = microtime(true);

        foreach ($sensorTypes as $sensor) {
            $data = $this->fetchSensorData($sensor, $range, $hardwareId);
            if ($data->isEmpty()) continue;

            $sheetLabel = substr(self::SENSOR_NAMES[$sensor] ?? $sensor, 0, 31);
            $sheet = $spreadsheet->createSheet();
            $sheet->setTitle($sheetLabel);

            $this->writeDataSheet($sheet, $sensor, $data);

            $this->addLineChart($spreadsheet, $sheet, $sensor, $data);

            if ($first) {
                $spreadsheet->setActiveSheetIndex(1);
                $first = false;
            }
        }

        $elapsed = round(microtime(true) - $startTime, 2);

        // Write to output buffer — disable calculation engine to avoid chart data parsing issues
        \PhpOffice\PhpSpreadsheet\Calculation\Calculation::getInstance($spreadsheet)->disableCalculationCache();
        ob_start();
        $writer = new Xlsx($spreadsheet);
        $writer->setIncludeCharts(true);
        $writer->save('php://output');
        $content = ob_get_clean();

        $filename = 'smartponic_export_' . strtolower(str_replace(' ', '_', $range)) . '_' . now()->format('Y-m-d_Hi') . '.xlsx';

        return response($content, 200, [
            'Content-Type' => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
            'Content-Disposition' => 'attachment; filename="' . $filename . '"',
            'X-Generation-Time' => $elapsed . 's',
        ]);
    }

    private function createNodeInfoSheet(Spreadsheet $spreadsheet, ?string $hardwareId, string $range): void
    {
        $sheet = $spreadsheet->createSheet();
        $sheet->setTitle('Node Info');
        $sheet->setCellValue('A1', 'SmartPonic Export Summary');
        $sheet->getStyle('A1')->getFont()->setBold(true)->setSize(14);

        $sheet->setCellValue('A3', 'Generated At:');
        $sheet->setCellValue('B3', now()->format('Y-m-d H:i:s'));
        $sheet->setCellValue('A4', 'Time Range:');
        $sheet->setCellValue('B4', $range);

        if ($hardwareId) {
            $node = DB::table('nodes')->where('hardware_id', $hardwareId)->first();
            $sheet->setCellValue('A5', 'Hardware ID:');
            $sheet->setCellValue('B5', $hardwareId);
            if ($node) {
                $sheet->setCellValue('A6', 'Node Name:');
                $sheet->setCellValue('B6', $node->name ?? '-');
                $sheet->setCellValue('A7', 'Location:');
                $sheet->setCellValue('B7', $node->location ?? '-');
            }
        }

        $sensorCount = DB::table('sensor_data')
            ->select('sensor')
            ->distinct()
            ->pluck('sensor')
            ->toArray();

        $sheet->setCellValue('A9', 'Sensors Available:');
        $sheet->setCellValue('B9', implode(', ', $sensorCount));

        $stats = DB::table('sensor_readings')
            ->where('created_at', '>=', DB::raw("NOW() - INTERVAL {$range}"))
            ->selectRaw('COUNT(*) as readings, MIN(created_at) as earliest, MAX(created_at) as latest')
            ->first();

        if ($stats && $stats->readings) {
            $sheet->setCellValue('A10', 'Total Readings:');
            $sheet->setCellValue('B10', (int) $stats->readings);
            $sheet->setCellValue('A11', 'Earliest:');
            $sheet->setCellValue('B11', $stats->earliest);
            $sheet->setCellValue('A12', 'Latest:');
            $sheet->setCellValue('B12', $stats->latest);
        }

        $sheet->getStyle('A3:A12')->getFont()->setBold(true);
        $sheet->getColumnDimension('A')->setWidth(18);
        $sheet->getColumnDimension('B')->setWidth(40);
    }

    private function fetchSensorData(string $sensor, string $range, ?string $hardwareId)
    {
        $query = DB::table('sensor_data as sd')
            ->join('sensor_readings as sr', 'sd.reading_id', '=', 'sr.id')
            ->where('sd.sensor', $sensor)
            ->where('sr.created_at', '>=', DB::raw("NOW() - INTERVAL {$range}"))
            ->orderBy('sr.created_at')
            ->select('sd.value', 'sr.created_at', 'sr.rssi', 'sr.hardware_id');

        if ($hardwareId) {
            $query->where('sr.hardware_id', $hardwareId);
        }

        $rows = $query->get();

        // Downsample if needed
        if ($rows->count() > self::MAX_POINTS_PER_SHEET) {
            $step = ceil($rows->count() / self::MAX_POINTS_PER_SHEET);
            return $rows->nth($step);
        }

        return $rows;
    }

    private function writeDataSheet($sheet, string $sensor, $data): void
    {
        $unit = self::SENSOR_UNITS[$sensor] ?? '';
        $label = self::SENSOR_NAMES[$sensor] ?? $sensor;

        // Title row
        $sheet->setCellValue('A1', "{$label} Sensor Data ({$unit})");
        $sheet->getStyle('A1')->getFont()->setBold(true)->setSize(12);
        $sheet->mergeCells('A1:D1');

        // Headers
        $headers = ['Timestamp', 'Value', 'Unit', 'RSSI'];
        foreach (['A', 'B', 'C', 'D'] as $i => $col) {
            $sheet->setCellValue("{$col}3", $headers[$i]);
        }
        $headerStyle = $sheet->getStyle('A3:D3');
        $headerStyle->getFont()->setBold(true);
        $headerStyle->getFill()->setFillType(Fill::FILL_SOLID)->getStartColor()->setARGB('FF1E293B');
        $headerStyle->getFont()->getColor()->setARGB('FFFFFFFF');
        $headerStyle->getAlignment()->setHorizontal(Alignment::HORIZONTAL_CENTER);

        // Data rows
        $row = 4;
        $numericCount = 0;
        foreach ($data as $d) {
            $sheet->setCellValue("A{$row}", $d->created_at);
            $sheet->setCellValue("C{$row}", $unit);

            if (is_numeric($d->value)) {
                $sheet->setCellValue("B{$row}", (float) $d->value);
                $numericCount++;
            } else {
                $sheet->setCellValue("B{$row}", $d->value);
            }

            $sheet->setCellValue("D{$row}", $d->rssi ?? '');
            $row++;
        }

        // Column widths
        $sheet->getColumnDimension('A')->setWidth(22);
        $sheet->getColumnDimension('B')->setWidth(14);
        $sheet->getColumnDimension('C')->setWidth(8);
        $sheet->getColumnDimension('D')->setWidth(10);

        // Auto-filter
        $lastRow = $row - 1;
        $sheet->setAutoFilter("A3:D{$lastRow}");

        // Number format for value column
        if ($numericCount > 0) {
            $sheet->getStyle("B4:B{$lastRow}")->getNumberFormat()->setFormatCode('0.0');
        }

        // Style table borders
        $tableRange = "A3:D{$lastRow}";
        $sheet->getStyle($tableRange)->getBorders()->getAllBorders()
            ->setBorderStyle(Border::BORDER_THIN);
    }

    private function addLineChart(Spreadsheet $spreadsheet, $sheet, string $sensor, $data): void
    {
        if ($data->count() < 2) return;

        // Check if numeric
        $numericData = $data->filter(fn($d) => is_numeric($d->value));
        if ($numericData->count() < 2) return;

        $label = self::SENSOR_NAMES[$sensor] ?? $sensor;

        // Write chart data in a hidden area (below the main table)
        $dataStartRow = $data->count() + 6; // Start after table
        $chartLabelRow = $dataStartRow;

        $sheet->setCellValue("A{$chartLabelRow}", 'Chart Timestamp');
        $sheet->setCellValue("B{$chartLabelRow}", $label);

        $chartDataRow = $chartLabelRow + 1;
        $chartRow = $chartDataRow;
        foreach ($numericData as $d) {
            $sheet->setCellValue("A{$chartRow}", $d->created_at);
            $sheet->setCellValue("B{$chartRow}", (float) $d->value);
            $chartRow++;
        }
        $chartEndRow = $chartRow - 1;

        // Build chart series with string x-axis
        $sheetRef = "'{$sheet->getTitle()}'";
        $xValues = new DataSeriesValues(
            DataSeriesValues::DATASERIES_TYPE_STRING,
            "{$sheetRef}!\$A\${$chartDataRow}:\$A\${$chartEndRow}",
            null,
            $chartEndRow - $chartDataRow + 1
        );

        $yValues = new DataSeriesValues(
            DataSeriesValues::DATASERIES_TYPE_NUMBER,
            "{$sheetRef}!\$B\${$chartDataRow}:\$B\${$chartEndRow}",
            null,
            $chartEndRow - $chartDataRow + 1
        );

        $seriesLabel = new DataSeriesValues(
            DataSeriesValues::DATASERIES_TYPE_STRING,
            null,
            null,
            1,
            [$label]
        );

        $series = new DataSeries(
            DataSeries::TYPE_LINECHART,
            null,
            [0],
            [$seriesLabel],
            [$xValues],
            [$yValues]
        );

        $plotArea = new PlotArea(null, [$series]);
        $legend = new Legend(Legend::POSITION_BOTTOM, null, false);
        $title = new Title("{$label} — Time Series");

        $chart = new Chart(
            "chart_{$sensor}",
            $title,
            $legend,
            $plotArea,
            true
        );

        // Position chart below the data table
        $chart->setTopLeftPosition('E3');
        $chart->setBottomRightPosition('O22');
        $sheet->addChart($chart);
    }

    public function summaryExport(Request $request)
    {
        $range = $this->validateRange($request->query('range', '6 HOUR'));
        $spreadsheet = new Spreadsheet();
        $spreadsheet->getProperties()
            ->setCreator('SmartPonic')
            ->setTitle("SmartPonic Analytics - {$range}")
            ->setDescription("Range-based analytics report over {$range}");

        $sheet = $spreadsheet->getActiveSheet();
        $sheet->setTitle('Analytics');

        // ─── Title ───
        $sheet->setCellValue('A1', 'SmartPonic Range Analytics Report');
        $sheet->getStyle('A1')->getFont()->setBold(true)->setSize(16);
        $sheet->mergeCells('A1:F1');

        $sheet->setCellValue('A2', "Generated: " . now()->format('Y-m-d H:i:s') . "  |  Range: {$range}");
        $sheet->getStyle('A2')->getFont()->setColor(new \PhpOffice\PhpSpreadsheet\Style\Color(\PhpOffice\PhpSpreadsheet\Style\Color::COLOR_DARKGREEN));
        $sheet->mergeCells('A2:F2');

        $row = 4;
        $intervalSql = "NOW() - INTERVAL {$range}";

        // ═══════════════════════════════════════════════════
        // Section 1: Instability & System Health
        // ═══════════════════════════════════════════════════
        $sheet->setCellValue("A{$row}", 'Instability & System Health');
        $sheet->getStyle("A{$row}")->getFont()->setBold(true)->setSize(12);
        $sheet->getStyle("A{$row}")->getFont()->getColor()->setARGB('FFF59E0B');
        $sheet->mergeCells("A{$row}:F{$row}");
        $row++;

        try {
            $readingsTotal = DB::table('sensor_readings')
                ->where('created_at', '>=', DB::raw($intervalSql))
                ->count();

            $criticalReadings = DB::table('sensor_readings')
                ->where('created_at', '>=', DB::raw($intervalSql))
                ->where('report_mode', 'CRITICAL')
                ->count();

            $abnormalReadings = DB::table('sensor_readings')
                ->where('created_at', '>=', DB::raw($intervalSql))
                ->where('report_mode', 'ABNORMAL')
                ->count();

            $highPriority = DB::table('sensor_readings')
                ->where('created_at', '>=', DB::raw($intervalSql))
                ->where('priority', 'HIGH')
                ->count();

            $instabilityPct = $readingsTotal > 0
                ? round((($criticalReadings + $abnormalReadings) / $readingsTotal) * 100, 1)
                : 0;

            $poorSignal = DB::table('sensor_readings')
                ->where('created_at', '>=', DB::raw($intervalSql))
                ->where(function ($q) {
                    $q->where('rssi', '<', -100)->orWhere('snr', '<', 5);
                })
                ->count();

            $signalIssuePct = $readingsTotal > 0
                ? round(($poorSignal / $readingsTotal) * 100, 1)
                : 0;

            $headers = ['Metric', 'Value', 'Notes'];
            foreach (['A', 'B', 'C'] as $i => $col) {
                $sheet->setCellValue("{$col}{$row}", $headers[$i]);
            }
            $this->styleHeaderRow($sheet, $row, 3);
            $row++;

            $metrics = [
                ['Total Readings', $readingsTotal, "Over {$range}"],
                ['Critical Events', $criticalReadings, 'report_mode=CRITICAL (sensor out of safe range)'],
                ['Abnormal Events', $abnormalReadings, 'report_mode=ABNORMAL (sensor approaching threshold)'],
                ['High Priority', $highPriority, 'priority=HIGH (sensor error or extreme value)'],
                ['Instability Rate', "{$instabilityPct}%", '% of readings that are ABNORMAL or CRITICAL'],
                ['Poor Signal Count', $poorSignal, 'RSSI < -100 or SNR < 5 dB'],
                ['Signal Issue Rate', "{$signalIssuePct}%", '% of readings with poor signal quality'],
            ];

            foreach ($metrics as $m) {
                $vStyle = $sheet->getStyle("B{$row}");
                if (str_contains($m[0], 'Rate') || str_contains($m[0], 'Instability')) {
                    $pct = (float) str_replace('%', '', $m[1]);
                    if ($pct > 30) {
                        $vStyle->getFont()->getColor()->setARGB('FFEF4444');
                    } elseif ($pct > 10) {
                        $vStyle->getFont()->getColor()->setARGB('FFF59E0B');
                    } else {
                        $vStyle->getFont()->getColor()->setARGB('FF22C55E');
                    }
                }
                if (str_contains($m[0], 'Critical') && $m[1] > 0) {
                    $vStyle->getFont()->getColor()->setARGB('FFEF4444');
                }
                $sheet->setCellValue("A{$row}", $m[0]);
                $sheet->setCellValue("B{$row}", $m[1]);
                $sheet->setCellValue("C{$row}", $m[2]);
                $sheet->getStyle("A{$row}")->getFont()->setBold(true);
                $row++;
            }
        } catch (\Exception $e) {
            $sheet->setCellValue("A{$row}", 'Data temporarily unavailable');
            $row++;
        }

        // ═══════════════════════════════════════════════════
        // Section 2: Per-Sensor Statistics Over Range
        // ═══════════════════════════════════════════════════
        $row++;
        $sheet->setCellValue("A{$row}", 'Per-Sensor Statistics');
        $sheet->getStyle("A{$row}")->getFont()->setBold(true)->setSize(12);
        $sheet->mergeCells("A{$row}:F{$row}");
        $row++;

        try {
            $activeSensorTypes = DB::table('sensor_data as sd')
                ->join('sensor_readings as sr', 'sd.reading_id', '=', 'sr.id')
                ->where('sr.created_at', '>=', DB::raw($intervalSql))
                ->whereRaw('sd.value REGEXP \'^-?[0-9]+(\\.[0-9]+)?$\'')
                ->select('sd.sensor',
                    DB::raw('MIN(CAST(sd.value AS DECIMAL(10,2))) as min_val'),
                    DB::raw('MAX(CAST(sd.value AS DECIMAL(10,2))) as max_val'),
                    DB::raw('AVG(CAST(sd.value AS DECIMAL(10,2))) as avg_val'),
                    DB::raw('STD(CAST(sd.value AS DECIMAL(10,2))) as std_val'),
                    DB::raw('COUNT(*) as sample_count'))
                ->groupBy('sd.sensor')
                ->orderBy('sd.sensor')
                ->get();

            if ($activeSensorTypes->isNotEmpty()) {
                $headers = ['Sensor', 'Min', 'Max', 'Avg', 'Std Dev', 'Samples'];
                $cols = ['A', 'B', 'C', 'D', 'E', 'F'];
                foreach ($cols as $i => $col) {
                    $sheet->setCellValue("{$col}{$row}", $headers[$i]);
                }
                $this->styleHeaderRow($sheet, $row, 6);
                $row++;

                $profiles = $this->getCachedProfiles();
                foreach ($activeSensorTypes as $s) {
                    $key = strtolower($s->sensor);
                    $profile = $profiles[$key] ?? null;
                    $unit = $profile['unit'] ?? '';
                    $sheet->setCellValue("A{$row}", $s->sensor . " ({$unit})");
                    $sheet->setCellValue("B{$row}", round((float) $s->min_val, 1));
                    $sheet->setCellValue("C{$row}", round((float) $s->max_val, 1));
                    $sheet->setCellValue("D{$row}", round((float) $s->avg_val, 1));
                    $sheet->setCellValue("E{$row}", round((float) $s->std_val, 2));
                    $sheet->setCellValue("F{$row}", (int) $s->sample_count);
                    if ($profile) {
                        $avg = (float) $s->avg_val;
                        $avgStyle = $sheet->getStyle("D{$row}");
                        if ($avg < $profile['t_min'] || $avg > $profile['t_max']) {
                            $avgStyle->getFont()->getColor()->setARGB('FFEF4444');
                            $avgStyle->getFont()->setBold(true);
                        }
                    }
                    $row++;
                }
            } else {
                $sheet->setCellValue("A{$row}", 'No numeric sensor data in this range');
                $row++;
            }
        } catch (\Exception $e) {
            $sheet->setCellValue("A{$row}", 'Sensor stats temporarily unavailable');
            $row++;
        }

        // ═══════════════════════════════════════════════════
        // Section 3: Signal Quality Distribution
        // ═══════════════════════════════════════════════════
        $row++;
        $sheet->setCellValue("A{$row}", 'Signal Quality Distribution');
        $sheet->getStyle("A{$row}")->getFont()->setBold(true)->setSize(12);
        $sheet->mergeCells("A{$row}:F{$row}");
        $row++;

        try {
            $signal = $this->computeSignalStats($range);
            $totalSignal = max(1, (int) ($signal['total'] ?? 1));

            $headers = ['Quality Tier', 'Count', 'Percentage'];
            foreach (['A', 'B', 'C'] as $i => $col) {
                $sheet->setCellValue("{$col}{$row}", $headers[$i]);
            }
            $this->styleHeaderRow($sheet, $row, 3);
            $row++;

            $tiers = [
                ['Excellent (RSSI > -70, SNR > 15)', $signal['excellent'] ?? 0, 'FF22C55E'],
                ['Good (RSSI > -85, SNR > 10)', $signal['good'] ?? 0, 'FF3B82F6'],
                ['Fair (RSSI > -100, SNR > 5)', $signal['fair'] ?? 0, 'FFF59E0B'],
                ['Poor (RSSI > -110, SNR > 0)', $signal['poor'] ?? 0, 'FFEF4444'],
                ['Critical (RSSI < -110, SNR < 0)', $signal['critical'] ?? 0, 'FFDC2626'],
            ];

            foreach ($tiers as $t) {
                $pct = round(($t[1] / $totalSignal) * 100, 1);
                $barLen = max(1, round($pct / 5));
                $sheet->setCellValue("A{$row}", $t[0]);
                $sheet->setCellValue("B{$row}", $t[1]);
                $sheet->setCellValue("C{$row}", "{$pct}%");
                $sheet->getStyle("A{$row}")->getFont()->setBold(true);
                $sheet->getStyle("B{$row}")->getFont()->getColor()->setARGB($t[2]);
                $sheet->getStyle("B{$row}")->getFont()->setBold(true);
                $sheet->setCellValue("D{$row}", str_repeat('█', min(20, $barLen)));
                $row++;
            }

            $sheet->setCellValue("A{$row}", 'Avg RSSI');
            $sheet->setCellValue("B{$row}", ($signal['avg_rssi'] ?? 'N/A') . ' dBm');
            $sheet->getStyle("A{$row}")->getFont()->setBold(true);
            $row++;
            $sheet->setCellValue("A{$row}", 'Avg SNR');
            $sheet->setCellValue("B{$row}", ($signal['avg_snr'] ?? 'N/A') . ' dB');
            $sheet->getStyle("A{$row}")->getFont()->setBold(true);
            $row++;
        } catch (\Exception $e) {
            $sheet->setCellValue("A{$row}", 'Signal data temporarily unavailable');
            $row++;
        }

        // ═══════════════════════════════════════════════════
        // Section 4: Priority & Report Mode Breakdown
        // ═══════════════════════════════════════════════════
        $row++;
        $sheet->setCellValue("A{$row}", 'Priority & Report Mode Breakdown');
        $sheet->getStyle("A{$row}")->getFont()->setBold(true)->setSize(12);
        $sheet->mergeCells("A{$row}:F{$row}");
        $row++;

        try {
            $modeBreakdown = DB::table('sensor_readings')
                ->where('created_at', '>=', DB::raw($intervalSql))
                ->select('report_mode', DB::raw('COUNT(*) as cnt'))
                ->groupBy('report_mode')
                ->orderBy('cnt', 'desc')
                ->get();

            $prioBreakdown = DB::table('sensor_readings')
                ->where('created_at', '>=', DB::raw($intervalSql))
                ->select('priority', DB::raw('COUNT(*) as cnt'))
                ->groupBy('priority')
                ->orderBy('cnt', 'desc')
                ->get();

            $modeColors = ['NORMAL' => 'FF22C55E', 'ABNORMAL' => 'FFF59E0B', 'CRITICAL' => 'FFEF4444'];
            $prioColors = ['LOW' => 'FF22C55E', 'MEDIUM' => 'FFF59E0B', 'HIGH' => 'FFEF4444'];

            $sheet->setCellValue("A{$row}", 'Report Mode');
            $sheet->setCellValue("B{$row}", 'Count');
            $this->styleHeaderRow($sheet, $row, 2);
            $row++;
            foreach ($modeBreakdown as $m) {
                $sheet->setCellValue("A{$row}", $m->report_mode ?? 'UNKNOWN');
                $sheet->setCellValue("B{$row}", (int) $m->cnt);
                $sheet->getStyle("A{$row}")->getFont()->setBold(true);
                $sheet->getStyle("A{$row}")->getFont()->getColor()->setARGB($modeColors[$m->report_mode] ?? 'FF64748B');
                $row++;
            }

            $row++;
            $sheet->setCellValue("A{$row}", 'Priority');
            $sheet->setCellValue("B{$row}", 'Count');
            $this->styleHeaderRow($sheet, $row, 2);
            $row++;
            foreach ($prioBreakdown as $p) {
                $sheet->setCellValue("A{$row}", $p->priority ?? 'UNKNOWN');
                $sheet->setCellValue("B{$row}", (int) $p->cnt);
                $sheet->getStyle("A{$row}")->getFont()->setBold(true);
                $sheet->getStyle("A{$row}")->getFont()->getColor()->setARGB($prioColors[$p->priority] ?? 'FF64748B');
                $row++;
            }
        } catch (\Exception $e) {
            $sheet->setCellValue("A{$row}", 'Breakdown temporarily unavailable');
            $row++;
        }

        // ═══════════════════════════════════════════════════
        // Section 5: Latest Sensor Snapshot
        // ═══════════════════════════════════════════════════
        $row++;
        $sheet->setCellValue("A{$row}", 'Latest Sensor Snapshot');
        $sheet->getStyle("A{$row}")->getFont()->setBold(true)->setSize(12);
        $sheet->mergeCells("A{$row}:F{$row}");
        $row++;

        try {
            $profiles = $this->getCachedProfiles();
            $activeSensors = $this->getActiveSensors($profiles);
            if (count($activeSensors) > 0) {
                $headers = ['Sensor', 'Pin', 'Value', 'Unit', 'Status'];
                $cols = ['A', 'B', 'C', 'D', 'E'];
                foreach ($cols as $i => $col) {
                    $sheet->setCellValue("{$col}{$row}", $headers[$i]);
                }
                $this->styleHeaderRow($sheet, $row, 5);
                $row++;
                foreach ($activeSensors as $s) {
                    $sheet->setCellValue("A{$row}", $s['label'] ?? $s['key'] ?? '-');
                    $sheet->setCellValue("B{$row}", $s['pin'] ?? '-');
                    $sheet->setCellValue("C{$row}", is_numeric($s['value']) ? (float) $s['value'] : ($s['value'] ?? '--'));
                    $sheet->setCellValue("D{$row}", $s['unit'] ?? '');
                    $sheet->setCellValue("E{$row}", strtoupper($s['status'] ?? 'unknown'));
                    $statusColor = match ($s['status'] ?? '') {
                        'normal' => 'FF22C55E', 'low' => 'FF3B82F6', 'high' => 'FFEF4444',
                        default => 'FF64748B',
                    };
                    $sheet->getStyle("E{$row}")->getFont()->getColor()->setARGB($statusColor);
                    $sheet->getStyle("E{$row}")->getFont()->setBold(true);
                    $row++;
                }
            } else {
                $sheet->setCellValue("A{$row}", 'No active sensors or node is offline');
                $row++;
            }
        } catch (\Exception $e) {
            $sheet->setCellValue("A{$row}", 'Sensor snapshot unavailable');
            $row++;
        }

        // ─── Column widths ───
        $sheet->getColumnDimension('A')->setWidth(28);
        $sheet->getColumnDimension('B')->setWidth(16);
        $sheet->getColumnDimension('C')->setWidth(30);
        $sheet->getColumnDimension('D')->setWidth(12);
        $sheet->getColumnDimension('E')->setWidth(12);
        $sheet->getColumnDimension('F')->setWidth(12);

        // ─── Output ───
        ob_start();
        $writer = new Xlsx($spreadsheet);
        $writer->save('php://output');
        $content = ob_get_clean();

        $filename = 'smartponic_analytics_' . strtolower(str_replace(' ', '_', $range)) . '_' . now()->format('Y-m-d_Hi') . '.xlsx';

        return response($content, 200, [
            'Content-Type' => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
            'Content-Disposition' => 'attachment; filename="' . $filename . '"',
        ]);
    }

    private function styleHeaderRow($sheet, int $row, int $colCount): void
    {
        $cols = range('A', 'F');
        $range = "{$cols[0]}{$row}:{$cols[$colCount - 1]}{$row}";
        $sheet->getStyle($range)->getFont()->setBold(true);
        $sheet->getStyle($range)->getFill()
            ->setFillType(\PhpOffice\PhpSpreadsheet\Style\Fill::FILL_SOLID)
            ->getStartColor()->setARGB('FF1E293B');
        $sheet->getStyle($range)->getFont()->getColor()->setARGB('FFFFFFFF');
        $sheet->getStyle($range)->getAlignment()
            ->setHorizontal(\PhpOffice\PhpSpreadsheet\Style\Alignment::HORIZONTAL_CENTER);
        $sheet->getStyle($range)->getBorders()->getAllBorders()
            ->setBorderStyle(\PhpOffice\PhpSpreadsheet\Style\Border::BORDER_THIN);
    }

    private function getCachedProfiles()
    {
        return \Illuminate\Support\Facades\Cache::remember("sensor_profiles", 300, function () {
            return $this->fetchProfiles();
        });
    }

    // ─── Helpers duplicated from DashboardController to keep export self-contained ───

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
                    "icon"  => $row->icon ?? "❓",
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

    private function getActiveSensors($profiles)
    {
        try {
            $latest = DB::table("sensor_readings")->orderByDesc("id")->first();
            if (!$latest) return [];

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
                    "icon" => $profile["icon"] ?? "❓",
                    "color" => $profile["color"] ?? "#888888",
                ];
            })->values()->toArray();
        } catch (\Exception $e) {
            return [];
        }
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
            ];
        } catch (\Exception $e) {
            return ["total" => 0, "avg_rssi" => null, "avg_snr" => null, "excellent" => 0, "good" => 0, "fair" => 0, "poor" => 0, "critical" => 0];
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

            if (!$hasData) {
                return [
                    "delivery_rate" => null,
                    "freshness_label" => "No data",
                    "is_fresh" => false,
                    "is_stale" => true,
                    "last_seen" => null,
                    "last_rssi" => null,
                    "last_snr" => null,
                    "uptime_hours" => 0,
                ];
            }

            return [
                "delivery_rate" => 100.0,
                "freshness_seconds" => (int) $freshnessSeconds,
                "freshness_label" => $this->formatFreshness($freshnessSeconds),
                "is_fresh" => $freshnessSeconds < 60,
                "is_stale" => $freshnessSeconds > 300,
                "last_seen" => $last ? $last->created_at : null,
                "last_rssi" => $last ? (int) $last->rssi : null,
                "last_snr" => $last ? (float) $last->snr : null,
                "uptime_hours" => (float) $uptimeHours,
            ];
        } catch (\Exception $e) {
            return ["delivery_rate" => null, "freshness_label" => "No data", "uptime_hours" => 0];
        }
    }

    private function formatFreshness(int $seconds): string
    {
        if ($seconds < 60) return "{$seconds}s ago";
        if ($seconds < 3600) return round($seconds / 60, 1) . "m ago";
        return round($seconds / 3600, 1) . "h ago";
    }

    private function validateRange(string $range): string
    {
        return in_array(strtoupper($range), self::ALLOWED_RANGES, true)
            ? strtoupper($range)
            : '24 HOUR';
    }
}