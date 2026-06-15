const fs = require('fs');
const path = require('path');

const vueFile = path.join(__dirname, 'resources/js/Pages/Dashboard/Overview.vue');
let vue = fs.readFileSync(vueFile, 'utf8');
const phpFile = path.join(__dirname, 'app/Http/Controllers/DashboardController.php');
let php = fs.readFileSync(phpFile, 'utf8');

// ====== PHP PATCHES ======

// PHP 1: poll() - include priority_distribution in signal_stats and ensure all fields
const oldPollResult = `$result = [
            "sensor_readings"   => $this->latestReading($profiles),
            "active_sensors"    => $this->activeSensors($profiles),
            "nodes"             => $this->sanitizeResult(DB::table("nodes")->orderBy("id")->get()),
            "telegram_bot_state"=> $this->sanitizeResult(DB::table("telegram_bot_state")->orderBy("state_key")->get()),
            "active_alerts"     => $this->getAlerts(),
            "signal_stats"      => $this->getSignalStats($range),
            "comm_health"      => $this->getCommHealth(),
            "profiles"          => $profiles,
        ];`;

const newPollResult = `$signalStats = $this->getSignalStats($range);
// Add priority distribution counts to signal_stats
try {
    $allRows = DB::table("sensor_readings")
        ->where("created_at", ">=", DB::raw("NOW() - INTERVAL {$range}"))
        ->select("rssi", "snr")
        ->get();
    $pd = ["excellent"=>0,"good"=>0,"fair"=>0,"poor"=>0,"critical"=>0];
    foreach ($allRows as $r) {
        $rssi = (int)$r->rssi; $snr = (float)$r->snr;
        if ($rssi > -70 && $snr > 15) $pd["excellent"]++;
        elseif ($rssi >= -85 && $snr >= 10) $pd["good"]++;
        elseif ($rssi >= -100 && $snr >= 5) $pd["fair"]++;
        elseif ($rssi >= -110 && $snr >= 0) $pd["poor"]++;
        else $pd["critical"]++;
    }
    $signalStats = array_merge($signalStats, $pd);
} catch (\Exception $e) {}

        $result = [
            "sensor_readings"   => $this->latestReading($profiles),
            "active_sensors"    => $this->activeSensors($profiles),
            "nodes"             => $this->sanitizeResult(DB::table("nodes")->orderBy("id")->get()),
            "telegram_bot_state"=> $this->sanitizeResult(DB::table("telegram_bot_state")->orderBy("state_key")->get()),
            "active_alerts"     => $this->getAlerts(),
            "signal_stats"      => $signalStats,
            "comm_health"      => $this->getCommHealth(),
            "profiles"          => $profiles,
        ];`;
php = php.replace(oldPollResult, newPollResult);

// PHP 2: getSignalStats - also return min_rssi, avg_rssi, avg_snr in a merged format
const oldGetSignalStats = `return response()->json([
            "range" => $range,
            "data"  => $rows->map(fn($r) => [
                "rssi" => (int) $r->rssi,
                "snr"  => (float) $r->snr,
                "time" => $r->created_at,
            ])->values(),
            "priority_distribution" => [
                "excellent" => $priorityDistribution["excellent"],
                "good"      => $priorityDistribution["good"],
                "fair"      => $priorityDistribution["fair"],
                "poor"      => $priorityDistribution["poor"],
                "critical"  => $priorityDistribution["critical"],
            ],
            "critical_count" => $criticalCount,
        ]);`;
const newGetSignalStats = `return response()->json([
            "range" => $range,
            "data"  => $rows->map(fn($r) => [
                "rssi" => (int) $r->rssi,
                "snr"  => (float) $r->snr,
                "time" => $r->created_at,
            ])->values(),
            "min_rssi" => $minRssi,
            "avg_rssi" => $avgRssi,
            "avg_snr"  => $avgSnr,
            "priority_distribution" => [
                "excellent" => $priorityDistribution["excellent"],
                "good"      => $priorityDistribution["good"],
                "fair"      => $priorityDistribution["fair"],
                "poor"      => $priorityDistribution["poor"],
                "critical"  => $priorityDistribution["critical"],
            ],
            "critical_count" => $criticalCount,
        ]);`;
php = php.replace(oldGetSignalStats, newGetSignalStats);

// PHP 3: Fix getSignalStats - define $minRssi, $avgRssi, $avgSnr variables before the response
// Find the location before the return response and add variable definitions
const oldGetSignalStatsBody = `$priorityDistribution = [
            "excellent" => 0,
            "good"      => 0,
            "fair"      => 0,
            "poor"      => 0,
            "critical"  => 0,
        ];

        $criticalCount = 0;
        foreach ($allRows as $r) {
            $rssi = (int) $r->rssi;
            $snr = (float) $r->snr;`;
const newGetSignalStatsBody = `$priorityDistribution = [
            "excellent" => 0,
            "good"      => 0,
            "fair"      => 0,
            "poor"      => 0,
            "critical"  => 0,
        ];

        $allRssi = [];
        $allSnr  = [];
        foreach ($allRows as $r) {
            if ($r->rssi !== null) $allRssi[] = (int)$r->rssi;
            if ($r->snr  !== null) $allSnr[]  = (float)$r->snr;
        }
        $minRssi = count($allRssi) > 0 ? min($allRssi) : null;
        $avgRssi = count($allRssi) > 0 ? round(array_sum($allRssi) / count($allRssi), 1) : null;
        $avgSnr  = count($allSnr)  > 0 ? round(array_sum($allSnr)  / count($allSnr),  1) : null;

        $criticalCount = 0;
        foreach ($allRows as $r) {
            $rssi = (int) $r->rssi;
            $snr = (float) $r->snr;`;
php = php.replace(oldGetSignalStatsBody, newGetSignalStatsBody);

fs.writeFileSync(phpFile, php, 'utf8');
console.log('PHP patches applied');

// ====== VUE PATCHES ======

// Vue 1: Add a computed that groups sensorCards by node_id for adaptive multi-node display
// Find sensorCards computed and add node grouping
const oldSensorCardsEnd = `    return { ...s, displayValue, badge, color, icon, unit, label, pin, profile, hasError }
  })
})`;
const newSensorCardsEnd = `    return { ...s, displayValue, badge, color, icon, unit, label, pin, profile, hasError }
  })
})

// Group sensor cards by node_id for adaptive display
const sensorCardsByNode = computed(() => {
  const groups = {}
  for (const card of sensorCards.value) {
    const nodeKey = card.node_id || card.hardware_id || 'unknown'
    if (!groups[nodeKey]) groups[nodeKey] = []
    groups[nodeKey].push(card)
  }
  return groups
})

// Active node labels
const nodeLabels = computed(() => {
  const map = {}
  for (const node of nodes.value || []) {
    map[node.id] = node.name || node.hardware_id || ('Node ' + node.id)
  }
  return map
})`;
vue = vue.replace(oldSensorCardsEnd, newSensorCardsEnd);

// Vue 2: Replace simple sensor grid with node-grouped adaptive cards
const oldSensorGrid = `          <div v-if="sensors.length === 0" class="flex flex-col items-center justify-center py-12 text-slate-500 bg-slate-800/20 rounded-xl border border-slate-800">
            <svg class="w-8 h-8 mb-2 opacity-50" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M9.172 16.172a4 4 0 015.656 0M9 10h.01M15 10h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
            </svg>
            <span class="text-xs">No active sensors found</span>
          </div>
          <div v-else class="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 xl:grid-cols-6 gap-3">
            <div
              v-for="card in sensorCards"
              :key="card.key"
              @click="openModal(card)"
              class="card-sensor group cursor-pointer"
              :style="{ '--accent': card.color }"
              :class="card.hasError ? 'opacity-60 grayscale' : ''"
            >
              <!-- Top row: icon + status dot -->
              <div class="flex items-center justify-between mb-3">
                <span class="text-lg">{{ card.icon }}</span>
                <span class="w-2 h-2 rounded-full" :class="card.badge.dot"></span>
              </div>

              <!-- Value -->
              <div class="text-2xl font-bold mb-1 leading-tight" :style="{ color: card.color }">
                {{ card.displayValue }}
                <span class="text-xs font-normal text-slate-500">{{ card.unit }}</span>
              </div>

              <!-- Label -->
              <div class="text-[11px] text-slate-300 font-semibold mb-0.5 truncate">{{ card.label }}</div>
              <!-- Node + Pin row -->
              <div class="flex items-center justify-between mb-2">
                <span class="text-[9px] text-slate-600 font-mono">{{ card.pin }}</span>
                <span v-if="card.node_id" class="text-[9px] text-slate-600 font-mono">#{{ card.node_id }}</span>
              </div>
              <!-- Status badge -->
              <div class="flex items-center justify-between mt-auto">
                <div class="flex items-center gap-1">
                  <span class="w-1.5 h-1.5 rounded-full" :class="card.badge.dot"></span>
                  <span class="text-[10px] font-semibold" :class="card.badge.class">
                    {{ card.badge.text }}
                  </span>
                </div>
                <span v-if="card.profile?.t_min != null && card.profile?.t_max != null" class="text-[9px] text-slate-600">
                  {{ card.profile.t_min }}–{{ card.profile.t_max }}
                </span>
              </div>

              <!-- Hover accent bar -->
              <div class="absolute bottom-0 left-0 right-0 h-0.5 bg-cyan-400 opacity-0 group-hover:opacity-100 transition-opacity" :style="{ background: card.color }"></div>
            </div>
          </div>
        </div>`;
const newSensorGrid = `          <div v-if="sensors.length === 0" class="flex flex-col items-center justify-center py-12 text-slate-500 bg-slate-800/20 rounded-xl border border-slate-800">
            <svg class="w-8 h-8 mb-2 opacity-50" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M9.172 16.172a4 4 0 015.656 0M9 10h.01M15 10h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
            </svg>
            <span class="text-xs">No active sensors found</span>
          </div>
          <div v-else>
            <div v-for="(cards, nodeKey) in sensorCardsByNode" :key="nodeKey" class="mb-6">
              <!-- Node group header -->
              <div class="flex items-center gap-2 mb-3">
                <div class="w-5 h-5 rounded-md bg-cyan-500/20 flex items-center justify-center">
                  <svg class="w-3 h-3 text-cyan-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 3v2m6-2v2M9 19v2m6-2v2M5 9H3m2 6H3m18-6h-2m2 6h-2M7 19h10a2 2 0 002-2V7a2 2 0 00-2-2H7a2 2 0 00-2 2v10a2 2 0 002 2zM9 9h6v6H9V9z" />
                  </svg>
                </div>
                <span class="text-[11px] text-slate-400 font-bold uppercase tracking-wider">{{ nodeLabels[nodeKey] || ('Node ' + nodeKey) }}</span>
                <span class="text-[9px] text-slate-600">{{ cards.length }} sensor{{ cards.length !== 1 ? 's' : '' }}</span>
              </div>
              <div class="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 xl:grid-cols-6 gap-3">
                <div
                  v-for="card in cards"
                  :key="card.key"
                  @click="openModal(card)"
                  class="card-sensor group cursor-pointer"
                  :style="{ '--accent': card.color }"
                  :class="card.hasError ? 'opacity-60 grayscale' : ''"
                >
                  <!-- Top row: icon + status dot -->
                  <div class="flex items-center justify-between mb-3">
                    <span class="text-lg">{{ card.icon }}</span>
                    <span class="w-2 h-2 rounded-full" :class="card.badge.dot"></span>
                  </div>

                  <!-- Value -->
                  <div class="text-2xl font-bold mb-1 leading-tight" :style="{ color: card.color }">
                    {{ card.displayValue }}
                    <span class="text-xs font-normal text-slate-500">{{ card.unit }}</span>
                  </div>

                  <!-- Label -->
                  <div class="text-[11px] text-slate-300 font-semibold mb-0.5 truncate">{{ card.label }}</div>
                  <!-- Pin row -->
                  <div class="flex items-center justify-between mb-2">
                    <span class="text-[9px] text-slate-600 font-mono">{{ card.pin }}</span>
                  </div>
                  <!-- Status badge -->
                  <div class="flex items-center justify-between mt-auto">
                    <div class="flex items-center gap-1">
                      <span class="w-1.5 h-1.5 rounded-full" :class="card.badge.dot"></span>
                      <span class="text-[10px] font-semibold" :class="card.badge.class">
                        {{ card.badge.text }}
                      </span>
                    </div>
                    <span v-if="card.profile?.t_min != null && card.profile?.t_max != null" class="text-[9px] text-slate-600">
                      {{ card.profile.t_min }}–{{ card.profile.t_max }}
                    </span>
                  </div>

                  <!-- Hover accent bar -->
                  <div class="absolute bottom-0 left-0 right-0 h-0.5 bg-cyan-400 opacity-0 group-hover:opacity-100 transition-opacity" :style="{ background: card.color }"></div>
                </div>
              </div>
            </div>
          </div>
        </div>`;
vue = vue.replace(oldSensorGrid, newSensorGrid);

// Vue 3: Add a loading skeleton for the header connection status
// The header status already has loading spinner - that's fine.

// Vue 4: Update the header title to show node count more nicely
const oldHeaderTitle = `        <div class="flex items-center gap-3">
          <h1 class="text-xl font-bold text-white">SmartPonic</h1>
          <span class="text-xs text-slate-500 font-mono">{{ nodes?.length ? nodes.length + ' node' : '' }} {{ nodes?.length > 1 ? 's' : '' }}</span>
        </div>`;
const newHeaderTitle = `        <div class="flex items-center gap-3">
          <div class="w-8 h-8 rounded-lg bg-gradient-to-br from-cyan-500 to-emerald-500 flex items-center justify-center shadow-lg shadow-cyan-500/30">
            <svg class="w-4 h-4 text-white" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M3.055 11H5a2 2 0 012 2v1a2 2 0 002 2 2 2 0 012 2v2.945M8 3.935V5.5A2.5 2.5 0 0010.5 8h.5a2 2 0 012 2 2 2 0 104 0 2 2 0 012-2h1.064M15 20.488V18a2 2 0 012-2h3.064" />
            </svg>
          </div>
          <div>
            <h1 class="text-lg font-bold text-white leading-tight">SmartPonic</h1>
            <span class="text-[9px] text-slate-500 font-mono uppercase tracking-wider">
              {{ nodes?.length ? nodes.length + ' node' : '' }} {{ (nodes?.length || 0) > 1 ? 's' : '' }}
            </span>
          </div>
        </div>`;
vue = vue.replace(oldHeaderTitle, newHeaderTitle);

fs.writeFileSync(vueFile, vue, 'utf8');
console.log('Vue patches applied - all done!');