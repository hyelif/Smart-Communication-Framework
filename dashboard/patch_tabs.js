const fs = require('fs');
const path = require('path');

const file = path.join(__dirname, 'resources/js/Pages/Dashboard/Overview.vue');
let content = fs.readFileSync(file, 'utf8');

// Fix Communication tab - replace the signalData section to include SNR chart and add RSSI/SNR distribution
const oldSignalSection = `          <div>
            <div class="flex items-center gap-3 mb-3">
              <span class="text-xs text-slate-500 uppercase tracking-wider">RSSI History</span>
              <div class="inline-flex bg-slate-800/60 rounded-lg p-0.5 border border-slate-700/50">
                <button
                  v-for="opt in rangeOptions"
                  :key="opt.value"
                  @click="signalRange = opt.value"
                  class="px-2.5 py-1 text-[10px] font-semibold rounded-md transition-all"
                  :class="signalRange === opt.value
                    ? 'bg-cyan-400 text-slate-900 shadow-sm'
                    : 'text-slate-400 hover:text-slate-200'"
                >
                  {{ opt.label }}
                </button>
              </div>
            </div>
            <div v-if="signalData.length > 0">
              <SignalChart :data="signalData" />
            </div>
            <div v-else class="h-48 flex items-center justify-center bg-slate-800/30 rounded-xl border border-slate-800">
              <span class="text-slate-500 text-sm">No signal history data available</span>
            </div>
          </div>
        </div>
      </div>`;

const newSignalSection = `          <div>
            <div class="flex items-center gap-3 mb-3">
              <span class="text-xs text-slate-500 uppercase tracking-wider">RSSI History</span>
              <div class="inline-flex bg-slate-800/60 rounded-lg p-0.5 border border-slate-700/50">
                <button
                  v-for="opt in rangeOptions"
                  :key="opt.value"
                  @click="signalRange = opt.value"
                  class="px-2.5 py-1 text-[10px] font-semibold rounded-md transition-all"
                  :class="signalRange === opt.value
                    ? 'bg-cyan-400 text-slate-900 shadow-sm'
                    : 'text-slate-400 hover:text-slate-200'"
                >
                  {{ opt.label }}
                </button>
              </div>
            </div>
            <div v-if="signalData.length > 0">
              <SignalChart :data="signalData" field="rssi" color="#f97316" />
            </div>
            <div v-else class="h-48 flex items-center justify-center bg-slate-800/30 rounded-xl border border-slate-800">
              <span class="text-slate-500 text-sm">No signal history data available</span>
            </div>
          </div>

          <!-- SNR History Chart -->
          <div class="mt-6">
            <div class="flex items-center gap-3 mb-3">
              <span class="text-xs text-slate-500 uppercase tracking-wider">SNR History</span>
            </div>
            <div v-if="signalData.length > 0">
              <SignalChart :data="signalData" field="snr" color="#a78bfa" />
            </div>
            <div v-else class="h-40 flex items-center justify-center bg-slate-800/30 rounded-xl border border-slate-800">
              <span class="text-slate-500 text-sm">No SNR history data available</span>
            </div>
          </div>

          <!-- Signal Priority Distribution -->
          <div class="mt-6">
            <div class="text-xs text-slate-500 uppercase tracking-wider mb-3">Signal Quality Distribution</div>
            <div class="grid grid-cols-5 gap-2">
              <div class="text-center p-2 bg-emerald-500/10 rounded-lg border border-emerald-500/20">
                <div class="text-sm font-bold text-emerald-400">{{ signal.excellent ?? 0 }}</div>
                <div class="text-[9px] text-slate-500 mt-0.5">Excellent</div>
              </div>
              <div class="text-center p-2 bg-cyan-500/10 rounded-lg border border-cyan-500/20">
                <div class="text-sm font-bold text-cyan-400">{{ signal.good ?? 0 }}</div>
                <div class="text-[9px] text-slate-500 mt-0.5">Good</div>
              </div>
              <div class="text-center p-2 bg-amber-500/10 rounded-lg border border-amber-500/20">
                <div class="text-sm font-bold text-amber-400">{{ signal.fair ?? 0 }}</div>
                <div class="text-[9px] text-slate-500 mt-0.5">Fair</div>
              </div>
              <div class="text-center p-2 bg-red-500/10 rounded-lg border border-red-500/20">
                <div class="text-sm font-bold text-red-400">{{ signal.poor ?? 0 }}</div>
                <div class="text-[9px] text-slate-500 mt-0.5">Poor</div>
              </div>
              <div class="text-center p-2 bg-slate-500/10 rounded-lg border border-slate-500/20">
                <div class="text-sm font-bold text-slate-400">{{ signal.critical ?? 0 }}</div>
                <div class="text-[9px] text-slate-500 mt-0.5">Critical</div>
              </div>
            </div>
          </div>
        </div>
      </div>`;
content = content.replace(oldSignalSection, newSignalSection);

// Fix Analytics tab - replace to add critical events panel and system status
const oldAnalyticsTab = `      <!-- Analytics Tab -->
      <div v-if="activeTab === 'analytics'" class="space-y-4">
        <div class="card-panel">
          <h3 class="text-lg font-bold text-white mb-4">Sensor Analytics</h3>
          <div class="flex items-center gap-3 mb-4">
            <span class="text-xs text-slate-500 uppercase tracking-wider">Period</span>
            <div class="inline-flex bg-slate-800/60 rounded-lg p-0.5 border border-slate-700/50">
              <button
                v-for="opt in rangeOptions"
                :key="opt.value"
                @click="selectedRange = opt.value"
                class="px-3 py-1.5 text-[11px] font-semibold rounded-md transition-all"
                :class="selectedRange === opt.value
                  ? 'bg-cyan-400 text-slate-900 shadow-sm'
                  : 'text-slate-400 hover:text-slate-200'"
              >
                {{ opt.label }}
              </button>
            </div>
          </div>
          <div v-if="analyticsData?.sensor_stats" class="space-y-3">
            <div v-for="(stats, sensor) in analyticsData.sensor_stats" :key="sensor" class="flex items-center justify-between p-3 bg-slate-800/50 rounded-lg">
              <span class="text-sm font-semibold text-white">{{ sensor }}</span>
              <div class="flex gap-6 text-xs">
                <span class="text-slate-500">Min: <span class="text-white font-medium">{{ Number(stats.min).toFixed(1) }}</span></span>
                <span class="text-slate-500">Avg: <span class="text-cyan-400 font-medium">{{ Number(stats.avg).toFixed(1) }}</span></span>
                <span class="text-slate-500">Max: <span class="text-red-400 font-medium">{{ Number(stats.max).toFixed(1) }}</span></span>
              </div>
            </div>
          </div>
          <div v-else class="py-12 text-center text-slate-500 text-sm">
            No analytics data available for this period
          </div>
        </div>
      </div>`;

const newAnalyticsTab = `      <!-- Analytics Tab -->
      <div v-if="activeTab === 'analytics'" class="space-y-4">
        <!-- Period selector + System Status row -->
        <div class="grid grid-cols-1 md:grid-cols-3 gap-3">
          <div class="card-panel md:col-span-2">
            <div class="flex items-center gap-3 mb-0">
              <span class="text-xs text-slate-500 uppercase tracking-wider">Period</span>
              <div class="inline-flex bg-slate-800/60 rounded-lg p-0.5 border border-slate-700/50">
                <button
                  v-for="opt in rangeOptions"
                  :key="opt.value"
                  @click="selectedRange = opt.value"
                  class="px-3 py-1 text-[10px] font-semibold rounded-md transition-all"
                  :class="selectedRange === opt.value
                    ? 'bg-cyan-400 text-slate-900 shadow-sm'
                    : 'text-slate-400 hover:text-slate-200'"
                >
                  {{ opt.label }}
                </button>
              </div>
            </div>
          </div>
          <div class="card-panel">
            <div class="text-[10px] text-slate-500 uppercase tracking-wider mb-1">System Status</div>
            <div class="flex items-center gap-2">
              <span v-if="analyticsData?.system_status === 'NOMINAL'" class="w-2.5 h-2.5 rounded-full bg-emerald-400 animate-pulse"></span>
              <span v-else-if="analyticsData?.system_status === 'WARNING'" class="w-2.5 h-2.5 rounded-full bg-amber-400 animate-pulse"></span>
              <span v-else class="w-2.5 h-2.5 rounded-full bg-red-400 animate-pulse"></span>
              <span class="text-sm font-bold" :class="analyticsData?.system_status === 'NOMINAL' ? 'text-emerald-400' : analyticsData?.system_status === 'WARNING' ? 'text-amber-400' : 'text-red-400'">
                {{ analyticsData?.system_status || '--' }}
              </span>
            </div>
          </div>
        </div>

        <!-- Sensor Stats Cards -->
        <div class="card-panel">
          <h3 class="text-sm font-semibold text-white mb-3">Sensor Statistics</h3>
          <div v-if="analyticsData?.sensor_stats" class="space-y-2">
            <div v-for="(stats, sensor) in analyticsData.sensor_stats" :key="sensor" class="flex items-center justify-between p-2.5 bg-slate-800/50 rounded-lg">
              <span class="text-xs font-semibold text-white">{{ sensor }}</span>
              <div class="flex gap-5 text-[10px]">
                <span class="text-slate-500">Min: <span class="text-white font-medium">{{ Number(stats.min).toFixed(1) }}</span></span>
                <span class="text-slate-500">Avg: <span class="text-cyan-400 font-medium">{{ Number(stats.avg).toFixed(1) }}</span></span>
                <span class="text-slate-500">Max: <span class="text-red-400 font-medium">{{ Number(stats.max).toFixed(1) }}</span></span>
                <span class="text-slate-600">n={{ stats.count }}</span>
              </div>
            </div>
          </div>
          <div v-else class="py-8 text-center text-slate-500 text-xs">
            No analytics data available for this period
          </div>
        </div>

        <!-- Critical Events + Threshold Bands Info -->
        <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
          <!-- Critical Events -->
          <div class="card-panel">
            <h3 class="text-sm font-semibold text-white mb-3">Critical Events</h3>
            <div v-if="analyticsData?.critical_events && analyticsData.critical_events.length > 0" class="space-y-1.5 max-h-52 overflow-y-auto">
              <div v-for="(evt, idx) in analyticsData.critical_events" :key="idx" class="flex items-center justify-between p-2 bg-red-500/10 rounded-lg border border-red-500/20">
                <div class="flex items-center gap-2">
                  <span class="w-1.5 h-1.5 rounded-full bg-red-400"></span>
                  <span class="text-xs text-white font-medium">{{ evt.sensor }}</span>
                </div>
                <div class="flex items-center gap-2">
                  <span class="text-xs text-red-400 font-mono">{{ evt.value }}</span>
                  <span class="text-[10px] text-slate-500 font-mono">{{ evt.time }}</span>
                </div>
              </div>
            </div>
            <div v-else class="py-6 text-center text-slate-500 text-xs">
              No critical events in this period
            </div>
          </div>

          <!-- Status Breakdown -->
          <div class="card-panel">
            <h3 class="text-sm font-semibold text-white mb-3">Status Breakdown</h3>
            <div v-if="analyticsData?.percentages" class="space-y-3">
              <div class="flex items-center justify-between p-2.5 bg-emerald-500/10 rounded-lg border border-emerald-500/20">
                <div class="flex items-center gap-2">
                  <span class="w-2 h-2 rounded-full bg-emerald-400"></span>
                  <span class="text-xs text-white font-medium">Normal</span>
                </div>
                <div class="flex items-center gap-2">
                  <span class="text-xs text-slate-400">{{ analyticsData.counts?.NORMAL || 0 }} readings</span>
                  <span class="text-xs font-bold text-emerald-400">{{ analyticsData.percentages?.NORMAL || 0 }}%</span>
                </div>
              </div>
              <div class="flex items-center justify-between p-2.5 bg-amber-500/10 rounded-lg border border-amber-500/20">
                <div class="flex items-center gap-2">
                  <span class="w-2 h-2 rounded-full bg-amber-400"></span>
                  <span class="text-xs text-white font-medium">Abnormal</span>
                </div>
                <div class="flex items-center gap-2">
                  <span class="text-xs text-slate-400">{{ analyticsData.counts?.ABNORMAL || 0 }} readings</span>
                  <span class="text-xs font-bold text-amber-400">{{ analyticsData.percentages?.ABNORMAL || 0 }}%</span>
                </div>
              </div>
              <div class="flex items-center justify-between p-2.5 bg-red-500/10 rounded-lg border border-red-500/20">
                <div class="flex items-center gap-2">
                  <span class="w-2 h-2 rounded-full bg-red-400"></span>
                  <span class="text-xs text-white font-medium">Critical</span>
                </div>
                <div class="flex items-center gap-2">
                  <span class="text-xs text-slate-400">{{ analyticsData.counts?.CRITICAL || 0 }} readings</span>
                  <span class="text-xs font-bold text-red-400">{{ analyticsData.percentages?.CRITICAL || 0 }}%</span>
                </div>
              </div>
            </div>
            <div v-else class="py-6 text-center text-slate-500 text-xs">
              No status data available
            </div>
          </div>
        </div>
      </div>`;
content = content.replace(oldAnalyticsTab, newAnalyticsTab);

fs.writeFileSync(file, content, 'utf8');
console.log('Communication + Analytics tabs enhanced successfully');