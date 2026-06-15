const fs = require('fs');
const path = require('path');

const file = path.join(__dirname, 'resources/js/Pages/Dashboard/Overview.vue');
let content = fs.readFileSync(file, 'utf8');

// 1. Replace toNum function with robust version + add isSensorError helper
const oldToNum = `function toNum(v) {
  const n = parseFloat(v)
  return isNaN(n) ? null : n
}`;
const newToNum = `function toNum(v) {
  if (v === null || v === undefined || v === '') return null
  const n = parseFloat(v)
  return isNaN(n) || !isFinite(n) ? null : n
}

function isSensorError(v) {
  const n = toNum(v)
  return n === null || n <= -127 || n >= 127
}`;
content = content.replace(oldToNum, newToNum);

// 2. Fix sensorCards computed - add error handling for displayValue, badge, unit
const oldSensorCards = `const sensorCards = computed(() => {
  if (!sensors.value || sensors.value.length === 0) return []

  return sensors.value.map(s => {
    const profile = allProfiles.value[s.key] || {}
    const numVal = toNum(s.value)
    const displayValue = numVal != null ? numVal.toFixed(1) : '--'

    let badge = { text: 'Normal', class: 'bg-emerald-500/20 text-emerald-400', dot: 'bg-emerald-400' }
    if (s.status === 'low') badge = { text: 'Low', class: 'bg-amber-500/20 text-amber-400', dot: 'bg-amber-400' }
    if (s.status === 'high') badge = { text: 'High', class: 'bg-red-500/20 text-red-400', dot: 'bg-red-400' }
    if (s.status === 'critical') badge = { text: 'Critical', class: 'bg-red-500/30 text-red-400', dot: 'bg-red-500 animate-pulse' }

    const color = s.color || profile.color || '#9ecaff'
    const icon = s.icon || profile.icon || '?'
    const unit = s.unit || ''
    const label = s.label || s.key || ''
    const pin = s.pin != null ? 'GPIO ' + s.pin : ''

    return { ...s, displayValue, badge, color, icon, unit, label, pin, profile }
  })
})`;
const newSensorCards = `const sensorCards = computed(() => {
  if (!sensors.value || sensors.value.length === 0) return []

  return sensors.value.map(s => {
    const profile = allProfiles.value[s.key] || {}
    const numVal = toNum(s.value)
    const hasError = isSensorError(s.value)

    let displayValue = '--'
    if (numVal != null && !hasError) {
      displayValue = numVal.toFixed(1)
    }

    let badge = { text: 'Normal', class: 'bg-emerald-500/20 text-emerald-400', dot: 'bg-emerald-400' }
    if (hasError) {
      badge = { text: 'Error', class: 'bg-slate-500/20 text-slate-400', dot: 'bg-slate-400' }
    } else if (s.status === 'low') {
      badge = { text: 'Low', class: 'bg-amber-500/20 text-amber-400', dot: 'bg-amber-400' }
    } else if (s.status === 'high') {
      badge = { text: 'High', class: 'bg-red-500/20 text-red-400', dot: 'bg-red-400' }
    } else if (s.status === 'critical') {
      badge = { text: 'Critical', class: 'bg-red-500/30 text-red-400', dot: 'bg-red-500 animate-pulse' }
    }

    const color = s.color || profile.color || '#9ecaff'
    const icon = s.icon || profile.icon || '?'
    const unit = hasError ? '' : (s.unit || '')
    const label = s.label || s.key || ''
    const pin = s.pin != null ? 'GPIO ' + s.pin : ''

    return { ...s, displayValue, badge, color, icon, unit, label, pin, profile, hasError }
  })
})`;
content = content.replace(oldSensorCards, newSensorCards);

// 3. Fix downloadSystemSummary - guard against null stats values
const oldDownloadStats = `    for (const [sensor, stats] of Object.entries(data.sensor_stats || {})) {
      const label = sensor === 'WaterTemp' ? 'Water Temp' : sensor
      report += label + ': Max ' + toNum(stats.max).toFixed(1) + ', Min ' + toNum(stats.min).toFixed(1) + ', Avg ' + toNum(stats.avg).toFixed(1) + '\\n'
    }`;
const newDownloadStats = `    for (const [sensor, stats] of Object.entries(data.sensor_stats || {})) {
      const label = sensor === 'WaterTemp' ? 'Water Temp' : sensor
      const maxV = toNum(stats.max); const minV = toNum(stats.min); const avgV = toNum(stats.avg)
      report += label + ': Max ' + (maxV !== null ? maxV.toFixed(1) : '--') + ', Min ' + (minV !== null ? minV.toFixed(1) : '--') + ', Avg ' + (avgV !== null ? avgV.toFixed(1) : '--') + '\\n'
    }`;
content = content.replace(oldDownloadStats, newDownloadStats);

// 4. Fix downloadCsv - guard against null values
const oldDownloadCsv = `const downloadCsv = () => {
  const rows = [['Sensor', 'Pin', 'Value', 'Unit', 'Status']]
  for (const s of sensors.value) {
    const displayValue = toNum(s.value) != null ? toNum(s.value).toFixed(1) : s.value
    rows.push([s.label, String(s.pin), displayValue, s.unit, s.status])
  }`;
const newDownloadCsv = `const downloadCsv = () => {
  const rows = [['Sensor', 'Pin', 'Value', 'Unit', 'Status']]
  for (const s of sensors.value) {
    const numVal = toNum(s.value)
    const displayValue = (numVal !== null && !isSensorError(s.value)) ? numVal.toFixed(1) : (s.value || '--')
    rows.push([s.label, String(s.pin), displayValue, s.unit, s.status])
  }`;
content = content.replace(oldDownloadCsv, newDownloadCsv);

// 5. Fix sensor card template - add hasError styling and unit guard
// Add grayscale + opacity when hasError in the card
const oldCardSensor = `<div
              v-for="card in sensorCards"
              :key="card.key"
              @click="openModal(card)"
              class="card-sensor group cursor-pointer"
              :style="{ '--accent': card.color }"
            >`;
const newCardSensor = `<div
              v-for="card in sensorCards"
              :key="card.key"
              @click="openModal(card)"
              class="card-sensor group cursor-pointer"
              :style="{ '--accent': card.color }"
              :class="card.hasError ? 'opacity-60 grayscale' : ''"
            >`;
content = content.replace(oldCardSensor, newCardSensor);

// 6. Fix stat cards - add colored icon boxes for better UI
const oldStatCards = `        <!-- Top stats row -->
        <div class="grid grid-cols-2 md:grid-cols-4 gap-3">
          <div class="card-stat">
            <span class="text-[10px] text-slate-500 uppercase tracking-wider">Node</span>
            <span :class="latest?.node_online ? 'text-emerald-400' : 'text-red-400'" class="text-sm font-bold flex items-center gap-1.5 mt-1">
              <span class="w-2 h-2 rounded-full" :class="latest?.node_online ? 'bg-emerald-400 animate-pulse' : 'bg-red-400'"></span>
              {{ latest?.node_online ? 'Online' : 'Offline' }}
            </span>
          </div>
          <div class="card-stat">
            <span class="text-[10px] text-slate-500 uppercase tracking-wider">Signal (RSSI)</span>
            <span class="text-sm font-bold mt-1 block" :class="signalClass(latest?.rssi)">{{ latest?.rssi ?? '--' }} dBm</span>
            <div class="h-1.5 bg-slate-700 rounded-full overflow-hidden mt-2">
              <div class="h-full rounded-full transition-all" :class="signalBarClass(latest?.rssi)" :style="{ width: signalBarWidth(latest?.rssi) + '%' }"></div>
            </div>
          </div>
          <div class="card-stat">
            <span class="text-[10px] text-slate-500 uppercase tracking-wider">Last Reading</span>
            <span class="text-sm font-bold mt-1 block" :class="freshnessClass(freshnessMins)">{{ health?.freshness_label || '--' }}</span>
          </div>
          <div class="card-stat">
            <span class="text-[10px] text-slate-500 uppercase tracking-wider">Alerts</span>
            <span class="text-sm font-bold mt-1 block" :class="alertsSummary.critical > 0 ? 'text-red-400' : alertsSummary.warning > 0 ? 'text-amber-400' : 'text-emerald-400'">
              {{ alertsSummary.active }} active
            </span>
          </div>
        </div>`;
const newStatCards = `        <!-- Top stats row -->
        <div class="grid grid-cols-2 md:grid-cols-4 gap-3">
          <div class="card-stat">
            <div class="flex items-center gap-2 mb-2">
              <div class="w-8 h-8 rounded-lg bg-emerald-500/20 flex items-center justify-center">
                <svg class="w-4 h-4 text-emerald-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 3v2m6-2v2M9 19v2m6-2v2M5 9H3m2 6H3m18-6h-2m2 6h-2M7 19h10a2 2 0 002-2V7a2 2 0 00-2-2H7a2 2 0 00-2 2v10a2 2 0 002 2zM9 9h6v6H9V9z" />
                </svg>
              </div>
              <span class="text-[10px] text-slate-500 uppercase tracking-wider">Node</span>
            </div>
            <span :class="latest?.node_online ? 'text-emerald-400' : 'text-red-400'" class="text-sm font-bold flex items-center gap-1.5">
              <span class="w-2 h-2 rounded-full" :class="latest?.node_online ? 'bg-emerald-400 animate-pulse' : 'bg-red-400'"></span>
              {{ latest?.node_online ? 'Online' : 'Offline' }}
            </span>
          </div>
          <div class="card-stat">
            <div class="flex items-center gap-2 mb-2">
              <div class="w-8 h-8 rounded-lg bg-cyan-500/20 flex items-center justify-center">
                <svg class="w-4 h-4 text-cyan-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8.111 16.404a5.5 5.5 0 017.778 0M12 20h.01m-7.08-7.071c3.904-3.905 10.236-3.905 14.14 0M1.394 9.393c5.857-5.857 15.355-5.857 21.213 0" />
                </svg>
              </div>
              <span class="text-[10px] text-slate-500 uppercase tracking-wider">Signal (RSSI)</span>
            </div>
            <span class="text-sm font-bold block" :class="signalClass(latest?.rssi)">{{ latest?.rssi ?? '--' }} dBm</span>
            <div class="h-1.5 bg-slate-700 rounded-full overflow-hidden mt-2">
              <div class="h-full rounded-full transition-all" :class="signalBarClass(latest?.rssi)" :style="{ width: signalBarWidth(latest?.rssi) + '%' }"></div>
            </div>
          </div>
          <div class="card-stat">
            <div class="flex items-center gap-2 mb-2">
              <div class="w-8 h-8 rounded-lg bg-amber-500/20 flex items-center justify-center">
                <svg class="w-4 h-4 text-amber-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z" />
                </svg>
              </div>
              <span class="text-[10px] text-slate-500 uppercase tracking-wider">Last Reading</span>
            </div>
            <span class="text-sm font-bold block" :class="freshnessClass(freshnessMins)">{{ health?.freshness_label || '--' }}</span>
          </div>
          <div class="card-stat">
            <div class="flex items-center gap-2 mb-2">
              <div class="w-8 h-8 rounded-lg flex items-center justify-center" :class="alertsSummary.critical > 0 ? 'bg-red-500/20' : alertsSummary.warning > 0 ? 'bg-amber-500/20' : 'bg-emerald-500/20'">
                <svg class="w-4 h-4" :class="alertsSummary.critical > 0 ? 'text-red-400' : alertsSummary.warning > 0 ? 'text-amber-400' : 'text-emerald-400'" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 17h5l-1.405-1.405A2.032 2.032 0 0118 14.158V11a6.002 6.002 0 00-4-5.659V5a2 2 0 10-4 0v.341C7.67 6.165 6 8.388 6 11v3.159c0 .538-.214 1.055-.595 1.436L4 17h5m6 0v1a3 3 0 11-6 0v-1m6 0H9" />
                </svg>
              </div>
              <span class="text-[10px] text-slate-500 uppercase tracking-wider">Alerts</span>
            </div>
            <span class="text-sm font-bold block" :class="alertsSummary.critical > 0 ? 'text-red-400' : alertsSummary.warning > 0 ? 'text-amber-400' : 'text-emerald-400'">
              {{ alertsSummary.active }} active
            </span>
          </div>
        </div>`;
content = content.replace(oldStatCards, newStatCards);

// 7. Fix tab icons - use actual SVG icons instead of placeholders
const oldTabs = `const tabs = [
  { id: 'overview', label: 'Overview', icon: '?' },
  { id: 'communication', label: 'Communication', icon: '?' },
  { id: 'analytics', label: 'Analytics', icon: '?' },
]`;
const newTabs = `const tabs = [
  { id: 'overview', label: 'Overview', icon: 'M3 12l2-2m0 0l7-7 7 7M5 10v10a1 1 0 001 1h3m10-11l2 2m-2-2v10a1 1 0 01-1 1h-3m-6 0a1 1 0 001-1v-4a1 1 0 011-1h2a1 1 0 011 1v4a1 1 0 001 1m-6 0h6' },
  { id: 'communication', label: 'Communication', icon: 'M8.111 16.404a5.5 5.5 0 017.778 0M12 20h.01m-7.08-7.071c3.904-3.905 10.236-3.905 14.14 0M1.394 9.393c5.857-5.857 15.355-5.857 21.213 0' },
  { id: 'analytics', label: 'Analytics', icon: 'M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z' },
]`;
content = content.replace(oldTabs, newTabs);

// 8. Update template tab buttons to show SVG icons
const oldTabButtons = `<button
            v-for="tab in tabs"
            :key="tab.id"
            @click="activeTab = tab.id"
            class="px-4 py-2.5 text-xs font-semibold uppercase tracking-wider border-b-2 transition-all"
            :class="activeTab === tab.id ? 'text-cyan-400 border-cyan-400' : 'text-slate-500 border-transparent hover:text-slate-300'"
          >
            {{ tab.label }}
          </button>`;
const newTabButtons = `<button
            v-for="tab in tabs"
            :key="tab.id"
            @click="activeTab = tab.id"
            class="px-4 py-2.5 text-xs font-semibold uppercase tracking-wider border-b-2 transition-all flex items-center gap-1.5"
            :class="activeTab === tab.id ? 'text-cyan-400 border-cyan-400' : 'text-slate-500 border-transparent hover:text-slate-300'"
          >
            <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" :d="tab.icon" />
            </svg>
            {{ tab.label }}
          </button>`;
content = content.replace(oldTabButtons, newTabButtons);

fs.writeFileSync(file, content, 'utf8');
console.log('Overview.vue patched successfully');