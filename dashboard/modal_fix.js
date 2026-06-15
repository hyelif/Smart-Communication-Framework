const fs = require('fs');
const path = require('path');

const file = path.join(__dirname, 'resources/js/Pages/Dashboard/Overview.vue');
let content = fs.readFileSync(file, 'utf8');

// ===== 1. Fix the duplicate/broken watch and add fetchSparklines properly =====
// Remove the broken second watch block that was injected by previous patch
const brokenWatch = `watch(activeTab, (tab) => {
  if (tab === 'communication') fetchSignalData()
  if (tab === 'analytics') fetchAnalytics()
})

watch(signalRange, () => fetchSignalData())
watch(modalSensor, () => fetchTrends())

// Adaptive sensor cards from activeSensors prop (dynamic GPIO nodes)`;
const fixedWatch = `watch(activeTab, (tab) => {
  if (tab === 'communication') fetchSignalData()
  if (tab === 'analytics') fetchAnalytics()
  if (tab === 'overview') fetchSparklines()
})

watch(signalRange, () => fetchSignalData())
watch(modalSensor, () => fetchTrends())

// Adaptive sensor cards from activeSensors prop (dynamic GPIO nodes)`;
content = content.replace(brokenWatch, fixedWatch);

// ===== 2. Remove the incorrectly injected sparkline code that ended up in wrong place =====
// Find and remove the broken sparkline fetch near the nodeLabels computed
const brokenSparklines = `// Inline mini sparkline renderer - returns SVG path string
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
content = content.replace(brokenSparklines, '');

// ===== 3. Fix fetchSparklines - remove the broken self-referential line =====
const brokenFetchSpark = `async function fetchSparklines() {
  if (tab === 'overview') fetchSparklines()`;
const fixedFetchSpark = `async function fetchSparklines() {`;
content = content.replace(brokenFetchSpark, fixedFetchSpark);

// ===== 4. Move sparkline data to after nodeLabels, add helper functions properly =====
// Find the location after nodeLabels computed and add sparkline helpers there
const oldNodeLabelsEnd = `const nodeLabels = computed(() => {
  const map = {}
  for (const node of nodes.value || []) {
    map[node.id] = node.name || node.hardware_id || ('Node ' + node.id)
  }
  return map
})`;
const newNodeLabelsEnd = `const nodeLabels = computed(() => {
  const map = {}
  for (const node of nodes.value || []) {
    map[node.id] = node.name || node.hardware_id || ('Node ' + node.id)
  }
  return map
})

// Sparkline colors per sensor key
const sparkColors = {
  temperature: '#f97316', humidity: '#38bdf8', watertemp: '#22d3ee',
  ph: '#a78bfa', tds: '#34d399', turbidity: '#fb923c', rain: '#60a5fa', relay: '#f472b6',
}
const sparklineRaw = shallowRef({})

async function fetchSparklines() {
  try {
    const url = '/api/dashboard/sensor-trends?range=6%20HOUR'
    const res = await fetch(url)
    if (!res.ok) return
    const json = await res.json()
    const grouped = {}
    for (const pt of json.data || []) {
      const key = (pt.sensor || '').toLowerCase().replace('watertemp', 'watertemp')
      if (!grouped[key]) grouped[key] = []
      grouped[key].push(pt.value)
      if (grouped[key].length > 20) grouped[key].shift()
    }
    sparklineRaw.value = grouped
  } catch (e) {}
}

function getSparkPath(key) {
  const vals = sparklineRaw.value[key] || []
  if (vals.length < 2) return ''
  const nums = vals.map(v => { const n = parseFloat(v); return (isNaN(n) || !isFinite(n)) ? null : n }).filter(v => v !== null)
  if (nums.length < 2) return ''
  const W = 80, H = 28
  const mn = Math.min(...nums), mx = Math.max(...nums)
  const range = mx - mn || 1
  return 'M ' + nums.map((v, i) => ((i / (nums.length - 1)) * W).toFixed(1) + ',' + (H - ((v - mn) / range) * H).toFixed(1)).join(' L ')
}`;
content = content.replace(oldNodeLabelsEnd, newNodeLabelsEnd);

// ===== 5. Make modal trend chart 10% bigger =====
// Increase the modal max-width and the chart container
const oldModalContainer = `<div class="relative w-full max-w-3xl bg-[#0f172a] border border-slate-700 rounded-2xl shadow-2xl overflow-hidden">
          <div class="flex items-center justify-between px-6 py-4 border-b border-slate-800">
            <h3 class="text-lg font-bold text-white">{{ modalSensor?.label }}</h3>`;
const newModalContainer = `<div class="relative w-full max-w-4xl bg-[#0f172a] border border-slate-700 rounded-2xl shadow-2xl overflow-hidden">
          <div class="flex items-center justify-between px-8 py-5 border-b border-slate-800">
            <div class="flex items-center gap-3">
              <div class="w-10 h-10 rounded-xl flex items-center justify-center" :style="{ backgroundColor: (modalSensor?.color || '#22d3ee') + '20' }">
                <span v-if="modalSensor?.iconSvg" class="text-xl" v-html="modalSensor.iconSvg"></span>
              </div>
              <div>
                <h3 class="text-lg font-bold text-white">{{ modalSensor?.label }}</h3>
                <div class="text-[10px] text-slate-500 uppercase tracking-wider">{{ modalSensor?.pin }}</div>
              </div>
            </div>`;
content = content.replace(oldModalContainer, newModalContainer);

// Make the chart area taller (10% bigger)
const oldChartArea = `          <div class="p-6">
            <div v-if="modalLoading" class="h-60 flex items-center justify-center">
              <div class="w-8 h-8 border-2 border-cyan-400 border-t-transparent rounded-full animate-spin"></div>
            </div>
            <TrendChart
              v-else-if="trendData.length > 0"
              :data="trendData"
              :profile="modalSensor?.profile || {}"
              :color="modalSensor?.color || '#22d3ee'"
            />
            <div v-else class="h-60 flex items-center justify-center text-slate-500">No data available</div>
          </div>`;
const newChartArea = `          <div class="p-8">
            <div v-if="modalLoading" class="h-[324px] flex items-center justify-center">
              <div class="w-8 h-8 border-2 border-cyan-400 border-t-transparent rounded-full animate-spin"></div>
            </div>
            <TrendChart
              v-else-if="trendData.length > 0"
              :data="trendData"
              :profile="modalSensor?.profile || {}"
              :color="modalSensor?.color || '#22d3ee'"
            />
            <div v-else class="h-[324px] flex items-center justify-center text-slate-500">No data available</div>
          </div>`;
content = content.replace(oldChartArea, newChartArea);

// ===== 6. Close the new header div properly and fix the range selector in modal =====
const oldModalHeaderEnd = `              <div class="flex bg-slate-800/80 rounded-full p-0.5 border border-slate-700/60 shadow-inner">
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
              </div>
              <button @click="closeModal" class="p-2 rounded-lg hover:bg-slate-800 text-slate-400 hover:text-white">
                <svg class="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
                </svg>
              </button>
            </div>
          </div>`;
const newModalHeaderEnd = `            <div class="flex items-center gap-3">
              <div class="flex bg-slate-800/80 rounded-full p-0.5 border border-slate-700/60 shadow-inner">
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
              </div>
              <button @click="closeModal" class="p-2 rounded-lg hover:bg-slate-800 text-slate-400 hover:text-white">
                <svg class="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
                </svg>
              </button>
            </div>
          </div>`;
content = content.replace(oldModalHeaderEnd, newModalHeaderEnd);

// ===== 7. Make sure modalSensor has iconSvg - add it to openModal =====
const oldOpenModal = `const openModal = (sensor) => {
  modalSensor.value = sensor
  modalOpen.value = true
  fetchTrends()
}`;
const newOpenModal = `const openModal = (sensor) => {
  const iconSvg = getSensorIcon(sensor.key)
  modalSensor.value = { ...sensor, iconSvg }
  modalOpen.value = true
  fetchTrends()
}`;
content = content.replace(oldOpenModal, newOpenModal);

fs.writeFileSync(file, content, 'utf8');
console.log('All patches applied');