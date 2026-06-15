const fs = require('fs');
const path = require('path');

const file = path.join(__dirname, 'resources/js/Pages/Dashboard/Overview.vue');
let content = fs.readFileSync(file, 'utf8');

// ===== 1. Add sensor icon map and helper functions =====
const oldSignalFunctions = `function signalClass(rssi) {
  if (rssi == null) return 'text-slate-400'
  if (rssi > -60) return 'text-emerald-400'
  if (rssi > -75) return 'text-cyan-400'
  if (rssi > -85) return 'text-amber-400'
  return 'text-red-400'
}

function signalBarClass(rssi) {
  if (rssi == null) return 'bg-slate-500'
  if (rssi > -60) return 'bg-emerald-500'
  if (rssi > -75) return 'bg-cyan-500'
  if (rssi > -85) return 'bg-amber-500'
  return 'bg-red-500'
}

function signalBarWidth(rssi) {
  if (rssi == null) return 0
  return Math.max(0, Math.min(100, (rssi + 100) * 2))
}`;
const newSignalFunctions = `function signalClass(rssi) {
  if (rssi == null) return 'text-slate-400'
  if (rssi > -60) return 'text-emerald-400'
  if (rssi > -75) return 'text-cyan-400'
  if (rssi > -85) return 'text-amber-400'
  return 'text-red-400'
}

function signalBarClass(rssi) {
  if (rssi == null) return 'bg-slate-500'
  if (rssi > -60) return 'bg-emerald-500'
  if (rssi > -75) return 'bg-cyan-500'
  if (rssi > -85) return 'bg-amber-500'
  return 'bg-red-500'
}

function signalBarWidth(rssi) {
  if (rssi == null) return 0
  return Math.max(0, Math.min(100, (rssi + 100) * 2))
}

// Sensor icon SVG paths by key
const sensorIconPaths = {
  temperature: 'M9 20a1 1 0 100-2 1 1 0 000 2zM9 20V10m0 0a4 4 0 100-8 4 4 0 000 8z',
  humidity: 'M12 4.5c-3.033 0-5.5 2.467-5.5 5.5 0 5.256 5.5 10 5.5 10s5.5-4.744 5.5-10c0-3.033-2.467-5.5-5.5-5.5zm0 12.5c-1.657 0-3-1.343-3-3s1.343-3 3-3 3 1.343 3 3-1.343 3-3 3z',
  watertemp: 'M20 7l-8-4-8 4m16 0l-8 4m8-4v10l-8 4m0-10L4 7m8 4v10M4 7v10l8 4',
  ph: 'M7 12h10M7 8h10M7 16h10M5 20h14',
  tds: 'M3 3v18h18M9 17V9m4 8V5m4 12v-4',
  turbidity: 'M3 14h3v7H3zm7-7h3v14h-3zm7-4h3v18h-3z',
  rain: 'M20 17.58A5 5 0 0018 8h-1.26A8 8 0 104 15.25M8 16h8M8 12h8M8 8h8',
  relay: 'M9 3H5a2 2 0 00-2 2v4m6-6h10a2 2 0 012 2v4M9 3v11m0 0H5a2 2 0 01-2-2V9m6 8h4a2 2 0 002-2V9m0 0H5a2 2 0 01-2-2V5',
}

function getSensorIcon(key) {
  const icon = sensorIconPaths[key] || sensorIconPaths.temperature
  return '<svg class="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="1.8">' +
    icon.split('\n').map(p => '<path stroke-linecap="round" stroke-linejoin="round" d="' + p.trim() + '" />').join('') +
    '</svg>'
}`;
content = content.replace(oldSignalFunctions, newSignalFunctions);

// ===== 2. Update sensorCards computed to include iconSvg =====
const oldSensorCardsEnd = `    return { ...s, displayValue, badge, color, icon, unit, label, pin, profile, hasError }
  })
})`;
const newSensorCardsEnd = `    const iconSvg = getSensorIcon(s.key)

    return { ...s, displayValue, badge, color, icon, iconSvg, unit, label, pin, profile, hasError }
  })
})`;
content = content.replace(oldSensorCardsEnd, newSensorCardsEnd);

// ===== 3. Replace sensor card template with redesigned layout =====
const oldCardTemplate = `              <div class="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 xl:grid-cols-6 gap-3">
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
              </div>`;
const newCardTemplate = `              <div class="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 xl:grid-cols-6 gap-3">
                <div
                  v-for="card in cards"
                  :key="card.key"
                  @click="openModal(card)"
                  class="card-sensor group cursor-pointer relative overflow-hidden"
                  :style="{ '--accent': card.color }"
                  :class="card.hasError ? 'opacity-50 grayscale' : ''"
                >
                  <!-- Background glow on hover -->
                  <div class="absolute inset-0 opacity-0 group-hover:opacity-100 transition-opacity duration-300 pointer-events-none"
                    :style="{ background: 'radial-gradient(ellipse at top, ' + card.color + '0d, transparent 70%)' }">
                  </div>

                  <!-- Header: icon circle + status dot -->
                  <div class="flex items-center justify-between mb-3 relative">
                    <div class="w-10 h-10 rounded-xl flex items-center justify-center transition-all duration-200 group-hover:scale-110"
                      :style="{ backgroundColor: card.color + '20' }">
                      <span class="transition-colors" :style="{ color: card.color }" v-html="card.iconSvg"></span>
                    </div>
                    <span class="w-2.5 h-2.5 rounded-full ring-2 ring-slate-800 transition-all" :class="card.badge.dot"></span>
                  </div>

                  <!-- Value + Unit -->
                  <div class="mb-2 relative">
                    <div class="flex items-end gap-1 leading-none">
                      <span class="text-2xl font-black tracking-tight" :style="{ color: card.color }">
                        {{ card.displayValue }}
                      </span>
                      <span class="text-[10px] font-semibold mb-0.5" :style="{ color: card.color + '99' }">
                        {{ card.unit }}
                      </span>
                    </div>
                  </div>

                  <!-- Label -->
                  <div class="text-[11px] font-bold text-slate-200 mb-2 leading-tight truncate relative">
                    {{ card.label }}
                  </div>

                  <!-- Footer: pin + threshold range -->
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
content = content.replace(oldCardTemplate, newCardTemplate);

// ===== 4. Update card-sensor style =====
const oldCardSensorStyle = `.card-sensor {
  position: relative;
  background: rgba(15,23,42,0.8);
  border-radius: 0.75rem;
  border: 1px solid rgb(30,41,59);
  padding: 1rem;
  transition: all 0.2s;
  overflow: hidden;
  cursor: pointer;
}
.card-sensor:hover {
  border-color: var(--accent, #22d3ee);
  background: rgba(15,23,42,0.95);
  transform: translateY(-2px);
  box-shadow: 0 8px 24px rgba(0,0,0,0.4);
}`;
const newCardSensorStyle = `.card-sensor {
  position: relative;
  background: rgba(15,23,42,0.8);
  border-radius: 0.875rem;
  border: 1px solid rgba(51,65,85,0.6);
  padding: 0.875rem;
  transition: all 0.25s cubic-bezier(0.4, 0, 0.2, 1);
  overflow: hidden;
  cursor: pointer;
}
.card-sensor:hover {
  border-color: var(--accent, #22d3ee);
  background: rgba(15,23,42,0.95);
  transform: translateY(-3px) scale(1.02);
  box-shadow: 0 12px 32px rgba(0,0,0,0.5), 0 0 0 1px var(--accent, #22d3ee) inset;
}`;
content = content.replace(oldCardSensorStyle, newCardSensorStyle);

fs.writeFileSync(file, content, 'utf8');
console.log('Sensor card redesign applied');