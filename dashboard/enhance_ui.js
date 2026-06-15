const fs = require('fs');
const path = require('path');

const file = path.join(__dirname, 'resources/js/Pages/Dashboard/Overview.vue');
let content = fs.readFileSync(file, 'utf8');

// 1. Replace "dropdown option hours" segmented control with nicer straight toggle buttons
// Find the rangeOptions and make them more visually prominent
const oldRangeOptions = `const rangeOptions = [
  { value: '1 HOUR', label: '1H' },
  { value: '6 HOUR', label: '6H' },
  { value: '24 HOUR', label: '24H' },
  { value: '7 DAY', label: '7D' },
  { value: '30 DAY', label: '30D' },
]`;
const newRangeOptions = `const rangeOptions = [
  { value: '1 HOUR', label: '1H',  hint: '1 hour' },
  { value: '6 HOUR', label: '6H',  hint: '6 hours' },
  { value: '24 HOUR', label: '24H', hint: '24 hours' },
  { value: '7 DAY', label: '7D',   hint: '7 days' },
  { value: '30 DAY', label: '30D', hint: '30 days' },
]`;
content = content.replace(oldRangeOptions, newRangeOptions);

// 2. Update the sensor card template to show node info and improve layout
const oldSensorCard = `              <!-- Label + pin -->
              <div class="text-[11px] text-slate-400 font-medium mb-2">{{ card.label }}</div>

              <!-- Pin + status badge -->
              <div class="flex items-center justify-between">
                <span class="text-[10px] text-slate-600 font-mono">{{ card.pin }}</span>
                <span class="text-[10px] font-semibold px-1.5 py-0.5 rounded-full" :class="card.badge.class">
                  {{ card.badge.text }}
                </span>
              </div>`;
const newSensorCard = `              <!-- Label -->
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
              </div>`;
content = content.replace(oldSensorCard, newSensorCard);

// 3. Replace the main range selector UI to be a proper segmented control with pill shape
const oldRangeSelector = `        <!-- Time range selector -->
        <div class="flex items-center gap-3">
          <span class="text-xs text-slate-500 uppercase tracking-wider">Range</span>
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
        </div>`;
const newRangeSelector = `        <!-- Time range selector - pill toggle -->
        <div class="flex items-center gap-3">
          <span class="text-[10px] text-slate-500 uppercase tracking-widest font-semibold">Period</span>
          <div class="flex bg-slate-800/80 rounded-full p-0.5 border border-slate-700/60 shadow-inner">
            <button
              v-for="opt in rangeOptions"
              :key="opt.value"
              @click="selectedRange = opt.value"
              class="px-4 py-1.5 text-[10px] font-bold rounded-full transition-all duration-200 min-w-[44px] text-center"
              :class="selectedRange === opt.value
                ? 'bg-gradient-to-r from-cyan-500 to-cyan-400 text-slate-900 shadow-lg shadow-cyan-500/25 scale-105'
                : 'text-slate-500 hover:text-slate-300'"
              :title="opt.hint"
            >
              {{ opt.label }}
            </button>
          </div>
          <span class="text-[10px] text-slate-600">{{ rangeOptions.find(o => o.value === selectedRange)?.hint }}</span>
        </div>`;
content = content.replace(oldRangeSelector, newRangeSelector);

// 4. Improve Communication tab range selector
const oldCommRangeSelector = `            <div class="flex items-center gap-3 mb-3">
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
            </div>`;
const newCommRangeSelector = `            <div class="flex items-center gap-3 mb-3">
              <span class="text-[10px] text-slate-500 uppercase tracking-widest font-semibold">RSSI</span>
              <div class="flex bg-slate-800/80 rounded-full p-0.5 border border-slate-700/60 shadow-inner">
                <button
                  v-for="opt in rangeOptions"
                  :key="opt.value"
                  @click="signalRange = opt.value"
                  class="px-3 py-1 text-[9px] font-bold rounded-full transition-all duration-200 min-w-[36px] text-center"
                  :class="signalRange === opt.value
                    ? 'bg-gradient-to-r from-orange-500 to-orange-400 text-slate-900 shadow-lg shadow-orange-500/25 scale-105'
                    : 'text-slate-500 hover:text-slate-300'"
                  :title="opt.hint"
                >
                  {{ opt.label }}
                </button>
              </div>
            </div>`;
content = content.replace(oldCommRangeSelector, newCommRangeSelector);

// 5. Improve Analytics period selector (make it consistent)
const oldAnalyticsPeriodSelector = `            <div class="flex items-center gap-3 mb-0">
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
            </div>`;
const newAnalyticsPeriodSelector = `            <div class="flex items-center gap-3">
              <span class="text-[10px] text-slate-500 uppercase tracking-widest font-semibold">Period</span>
              <div class="flex bg-slate-800/80 rounded-full p-0.5 border border-slate-700/60 shadow-inner">
                <button
                  v-for="opt in rangeOptions"
                  :key="opt.value"
                  @click="selectedRange = opt.value"
                  class="px-3 py-1 text-[9px] font-bold rounded-full transition-all duration-200 min-w-[36px] text-center"
                  :class="selectedRange === opt.value
                    ? 'bg-gradient-to-r from-violet-500 to-purple-400 text-slate-900 shadow-lg shadow-violet-500/25 scale-105'
                    : 'text-slate-500 hover:text-slate-300'"
                  :title="opt.hint"
                >
                  {{ opt.label }}
                </button>
              </div>
              <span class="text-[10px] text-slate-600">{{ rangeOptions.find(o => o.value === selectedRange)?.hint }}</span>
            </div>`;
content = content.replace(oldAnalyticsPeriodSelector, newAnalyticsPeriodSelector);

// 6. Add a section header style for the Overview sensor section
const oldSensorSectionHeader = `        <!-- Sensor cards grid - adaptive to active sensors -->
        <div>
          <div v-if="sensors.length === 0" class="flex flex-col items-center justify-center py-16 text-slate-500">
            <span class="text-4xl mb-3">?</span>
            <span class="text-sm">No active sensors found</span>
          </div>`;
const newSensorSectionHeader = `        <!-- Sensor cards grid - adaptive to active sensors -->
        <div>
          <div class="flex items-center justify-between mb-3">
            <div class="flex items-center gap-2">
              <span class="w-1 h-4 rounded-full bg-cyan-400"></span>
              <span class="text-xs text-slate-400 font-semibold uppercase tracking-widest">Sensor Readings</span>
            </div>
            <span class="text-[10px] text-slate-600">{{ sensors.length }} active</span>
          </div>
          <div v-if="sensors.length === 0" class="flex flex-col items-center justify-center py-12 text-slate-500 bg-slate-800/20 rounded-xl border border-slate-800">
            <svg class="w-8 h-8 mb-2 opacity-50" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M9.172 16.172a4 4 0 015.656 0M9 10h.01M15 10h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
            </svg>
            <span class="text-xs">No active sensors found</span>
          </div>`;
content = content.replace(oldSensorSectionHeader, newSensorSectionHeader);

// 7. Improve modal range selector
const oldModalRangeSelector = `              <div class="inline-flex bg-slate-800/60 rounded-lg p-0.5 border border-slate-700/50">
                <button
                  v-for="opt in rangeOptions"
                  :key="opt.value"
                  @click="selectedRange = opt.value"
                  class="px-2.5 py-1 text-[10px] font-semibold rounded-md transition-all"
                  :class="selectedRange === opt.value
                    ? 'bg-cyan-400 text-slate-900 shadow-sm'
                    : 'text-slate-400 hover:text-slate-200'"
                >
                  {{ opt.label }}
                </button>
              </div>`;
const newModalRangeSelector = `              <div class="flex bg-slate-800/80 rounded-full p-0.5 border border-slate-700/60 shadow-inner">
                <button
                  v-for="opt in rangeOptions"
                  :key="opt.value"
                  @click="selectedRange = opt.value"
                  class="px-3 py-1 text-[9px] font-bold rounded-full transition-all duration-200 min-w-[36px] text-center"
                  :class="selectedRange === opt.value
                    ? 'bg-gradient-to-r from-cyan-500 to-cyan-400 text-slate-900 shadow-lg shadow-cyan-500/25 scale-105'
                    : 'text-slate-500 hover:text-slate-300'"
                >
                  {{ opt.label }}
                </button>
              </div>`;
content = content.replace(oldModalRangeSelector, newModalRangeSelector);

fs.writeFileSync(file, content, 'utf8');
console.log('UI enhancements applied successfully');