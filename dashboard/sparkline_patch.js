const fs = require('fs');
const path = require('path');

const vueFile = path.join(__dirname, 'resources/js/Pages/Dashboard/Overview.vue');
let vue = fs.readFileSync(vueFile, 'utf8');

// ===== 1. Add MiniSpark component + sparkline data computation =====
const oldSetupEnd = `const nodeLabels = computed(() => {
  const map = {}
  for (const node of nodes.value || []) {
    map[node.id] = node.name || node.hardware_id || ('Node ' + node.id)
  }
  return map
})`;
const newSetupEnd = `const nodeLabels = computed(() => {
  const map = {}
  for (const node of nodes.value || []) {
    map[node.id] = node.name || node.hardware_id || ('Node ' + node.id)
  }
  return map
})

// Sparkline data per sensor (last 20 readings for mini chart)
// Fetches aggregated sparkline data from the poll response
const sparklineData = shallowRef({})
const sparklineColors = {
  temperature: '#f97316', humidity: '#38bdf8', watertemp: '#22d3ee',
  ph: '#a78bfa', tds: '#34d399', turbidity: '#fb923c', rain: '#60a5fa', relay: '#f472b6',
}

async function fetchSparklines() {
  try {
    const url = '/api/dashboard/sensor-trends?range=6%20HOUR'
    const res = await fetch(url)
    if (!res.ok) return
    const json = await res.json()
    if (json.data) {
      const grouped = {}
      for (const pt of json.data) {
        const key = pt.sensor?.toLowerCase() || 'unknown'
        if (!grouped[key]) grouped[key] = []
        grouped[key].push(pt.value)
        if (grouped[key].length > 20) grouped[key].shift()
      }
      sparklineData.value = grouped
    }
  } catch (e) {}
}

watch(activeTab, (tab) => {
  if (tab === 'communication') fetchSignalData()
  if (tab === 'analytics') fetchAnalytics()
})

watch(activeTab, (tab) => {
  if (tab === 'overview') fetchSparklines()
}, { immediate: true })

// Inline mini sparkline renderer - returns SVG path string
function getSparkPath(key) {
  const values = sparklineData.value[key] || []
  if (values.length < 2) return ''
  const nums = values.map(v => {
    const n = parseFloat(v)
    return isNaN(n) || !isFinite(n) ? null : n
  }).filter(v => v !== null)
  if (nums.length < 2) return ''
  const W = 80, H = 28
  const minV = Math.min(...nums), maxV = Math.max(...nums)
  const range = maxV - minV || 1
  const pts = nums.map((v, i) => {
    const x = (i / (nums.length - 1)) * W
    const y = H - ((v - minV) / range) * H
    return x.toFixed(1) + ',' + y.toFixed(1)
  })
  return 'M ' + pts.join(' L ')
}

function getSparkColor(key) {
  return sparklineColors[key] || '#22d3ee'
}`;
vue = vue.replace(oldSetupEnd, newSetupEnd);

// ===== 2. Update sensor card template to include sparkline =====
const oldCardFooter = `                  <!-- Footer: pin + threshold range -->
                  <div class="flex items-center justify-between mt-auto relative">
                    <span class="text-[9px] text-slate-600 font-mono">{{ card.pin }}</span>
                    <span class="text-[9px] font-mono px-1.5 py-0.5 rounded-full"
                      :style="{ backgroundColor: card.color + '15', color: card.color + 'cc' }"
                      v-if="card.profile?.t_min != null && card.profile?.t_max != null">
                      {{ card.profile.t_min }}–{{ card.profile.t_max }}
                    </span>
                  </div>

                  <!-- Bottom status strip -->
                  <div class="absolute bottom-0 left-0 right-0 h-0.5 transition-all duration-200"
                    :style="{ background: card.color, opacity: '0' }"
                    :class="'group-hover:!opacity-100'"></div>
                </div>
              </div>`;
const newCardFooter = `                  <!-- Footer: sparkline + threshold -->
                  <div class="flex items-center justify-between mt-auto relative">
                    <span class="text-[9px] text-slate-600 font-mono">{{ card.pin }}</span>
                    <!-- Mini sparkline chart -->
                    <svg v-if="getSparkPath(card.key)" :width="48" :height="20" class="overflow-visible">
                      <defs>
                        <linearGradient :id="'sg-' + card.key" x1="0" y1="0" x2="0" y2="1">
                          <stop offset="0%" :stop-color="card.color" stop-opacity="0.4" />
                          <stop offset="100%" :stop-color="card.color" stop-opacity="0" />
                        </linearGradient>
                      </defs>
                      <path
                        :d="getSparkPath(card.key)"
                        fill="none"
                        :stroke="card.color"
                        stroke-width="1.5"
                        stroke-linecap="round"
                        stroke-linejoin="round"
                        class="transition-all duration-300"
                      />
                    </svg>
                    <span class="text-[9px] font-mono px-1.5 py-0.5 rounded-full"
                      :style="{ backgroundColor: card.color + '15', color: card.color + 'cc' }"
                      v-if="card.profile?.t_min != null && card.profile?.t_max != null">
                      {{ card.profile.t_min }}–{{ card.profile.t_max }}
                    </span>
                  </div>

                  <!-- Bottom status strip -->
                  <div class="absolute bottom-0 left-0 right-0 h-0.5 transition-all duration-200"
                    :style="{ background: card.color, opacity: '0' }"
                    :class="'group-hover:!opacity-100'"></div>
                </div>
              </div>`;
vue = vue.replace(oldCardFooter, newCardFooter);

// ===== 3. Replace the stat card labels to be uppercase tracking =====
const oldStatLabel = `              <span class="text-[10px] text-slate-500 uppercase tracking-wider">Node</span>`;
const newStatLabel = `              <span class="text-[9px] text-slate-500 uppercase tracking-widest font-bold">Node</span>`;
vue = vue.replace(oldStatLabel, newStatLabel);

// ===== 4. Make stat values bigger/more prominent =====
const oldNodeStat = `<span :class="latest?.node_online ? 'text-emerald-400' : 'text-red-400'" class="text-sm font-bold flex items-center gap-1.5">
              <span class="w-2 h-2 rounded-full" :class="latest?.node_online ? 'bg-emerald-400 animate-pulse' : 'bg-red-400'"></span>
              {{ latest?.node_online ? 'Online' : 'Offline' }}
            </span>`;
const newNodeStat = `<span :class="latest?.node_online ? 'text-emerald-400' : 'text-red-400'" class="text-base font-black tracking-tight flex items-center gap-1.5">
              <span class="w-2 h-2 rounded-full" :class="latest?.node_online ? 'bg-emerald-400 animate-pulse' : 'bg-red-400'"></span>
              {{ latest?.node_online ? 'Online' : 'Offline' }}
            </span>`;
vue = vue.replace(oldNodeStat, newNodeStat);

// ===== 5. Update pill range selectors to be more compact pill buttons =====
const oldOverviewRange = `        <div class="flex items-center gap-3">
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
const newOverviewRange = `        <div class="flex items-center gap-3">
          <div class="flex bg-slate-800/80 rounded-full p-0.5 border border-slate-700/60 shadow-inner">
            <button
              v-for="opt in rangeOptions"
              :key="opt.value"
              @click="selectedRange = opt.value"
              class="px-3 py-1 text-[9px] font-black tracking-wider uppercase rounded-full transition-all duration-200 min-w-[40px] text-center"
              :class="selectedRange === opt.value
                ? 'bg-gradient-to-r from-cyan-500 to-cyan-400 text-slate-900 shadow-lg shadow-cyan-500/25 scale-105'
                : 'text-slate-500 hover:text-slate-300'"
              :title="opt.hint"
            >
              {{ opt.label }}
            </button>
          </div>
        </div>`;
vue = vue.replace(oldOverviewRange, newOverviewRange);

fs.writeFileSync(vueFile, vue, 'utf8');
console.log('Sparklines + card UI applied');