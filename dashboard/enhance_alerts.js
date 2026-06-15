const fs = require('fs');
const path = require('path');

const file = path.join(__dirname, 'app/Http/Controllers/DashboardController.php');
let content = fs.readFileSync(file, 'utf8');

// Enhance getAlerts - add severity icons and readable timestamps
const oldGetAlerts = `private function getAlerts()
    {
        try {
            return DB::table("alerts")->where("status","active")->orderByDesc("created_at")->get()->toArray();
        } catch (\Exception $e) { return []; }
    }`;
const newGetAlerts = `private function getAlerts()
    {
        try {
            $alerts = DB::table("alerts")->where("status","active")->orderByDesc("created_at")->get();
            return $alerts->map(function($a) {
                $sev = $a->severity ?? "info";
                $sevIcons = [
                    "critical" => "<svg class=\"w-4 h-4\" fill=\"none\" viewBox=\"0 0 24 24\" stroke=\"currentColor\"><path stroke-linecap=\"round\" stroke-linejoin=\"round\" stroke-width=\"2\" d=\"M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z\" /></svg>",
                    "warning"  => "<svg class=\"w-4 h-4\" fill=\"none\" viewBox=\"0 0 24 24\" stroke=\"currentColor\"><path stroke-linecap=\"round\" stroke-linejoin=\"round\" stroke-width=\"2\" d=\"M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z\" /></svg>",
                    "info"     => "<svg class=\"w-4 h-4\" fill=\"none\" viewBox=\"0 0 24 24\" stroke=\"currentColor\"><path stroke-linecap=\"round\" stroke-linejoin=\"round\" stroke-width=\"2\" d=\"M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z\" /></svg>",
                ];
                $sevColors = [
                    "critical" => "text-red-400",
                    "warning"  => "text-amber-400",
                    "info"     => "text-blue-400",
                ];
                $bgColors = [
                    "critical" => "bg-red-500/10 border-red-500/30",
                    "warning"  => "bg-amber-500/10 border-amber-500/30",
                    "info"     => "bg-blue-500/10 border-blue-500/30",
                ];
                return [
                    "id"          => $a->id,
                    "sensor"      => $a->sensor ?? $a->message ?? "System",
                    "message"     => $a->message ?? "",
                    "severity"    => $sev,
                    "icon"        => $sevIcons[$sev] ?? $sevIcons["info"],
                    "icon_class"  => $sevColors[$sev] ?? "text-blue-400",
                    "bg_class"    => $bgColors[$sev] ?? "bg-blue-500/10 border-blue-500/30",
                    "status"      => $a->status ?? "active",
                    "created_at"  => $a->created_at,
                    "time_ago"    => $this->timeAgo($a->created_at),
                ];
            })->toArray();
        } catch (\Exception $e) { return []; }
    }

    private function timeAgo($timestamp) {
        if (!$timestamp) return "unknown";
        $diff = time() - strtotime($timestamp);
        if ($diff < 60) return $diff . "s ago";
        if ($diff < 3600) return round($diff/60) . "m ago";
        if ($diff < 86400) return round($diff/3600) . "h ago";
        return round($diff/86400) . "d ago";
    }`;
content = content.replace(oldGetAlerts, newGetAlerts);

fs.writeFileSync(file, content, 'utf8');
console.log('getAlerts enhanced');