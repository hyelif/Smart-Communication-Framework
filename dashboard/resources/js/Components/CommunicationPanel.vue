<script setup>
import { ref, computed, onMounted, watch, nextTick } from 'vue'
import StatCard from './StatCard.vue'
import SignalChart from '../Pages/Dashboard/SignalChart.vue'

const props = defineProps({
  signalStats: { type: Object, default: () => ({}) },
  signalData: { type: Array, default: () => [] },
  loading: { type: Boolean, default: false },
  signalRange: { type: String, default: '24 HOUR' },
})

const emit = defineEmits(['update:signal-range', 'retry'])

const rangeOptions = [
  { value: '1 HOUR', label: '1H' },
  { value: '6 HOUR', label: '6H' },
  { value: '24 HOUR', label: '24H' },
  { value: '7 DAY', label: '7D' },
  { value: '30 DAY', label: '30D' },
]

// ── Online status ───────────────────────────────
const isOnline = computed(() => {
  return props.signalStats?.is_online === true
})

// ── Signal Quality ──────────────────────────────────────────
const signalQuality = computed(() => {
  const rssi = props.signalStats?.avg_rssi
  if (!isOnline.value) return { label: 'No Signal', color: 'text-slate-400', bars: 0, barColor: '#64748b' }
  if (rssi > -60) return { label: 'Excellent', color: 'text-emerald-400', bars: 5, barColor: '#34d399' }
  if (rssi > -75) return { label: 'Good', color: 'text-cyan-400', bars: 4, barColor: '#22d3ee' }
  if (rssi > -85) return { label: 'Fair', color: 'text-amber-400', bars: 3, barColor: '#f59e0b' }
  if (rssi > -95) return { label: 'Poor', color: 'text-orange-400', bars: 2, barColor: '#f97316' }
  return { label: 'Critical', color: 'text-red-400', bars: 1, barColor: '#ef4444' }
})

// ── Panel Background Tint ───────────────────────────────────
const bgGradientStyle = computed(() => {
  const c = signalQuality.value.barColor
  return { background: `linear-gradient(135deg, ${c}0d 0%, transparent 55%)` }
})

// ── Quality Badge Helpers ───────────────────────────────────
const badgeClass = computed(() => {
  const q = signalQuality.value
  if (q.label === 'Excellent') return 'mac-badge bg-emerald-500/15 text-emerald-400'
  if (q.label === 'Good') return 'mac-badge bg-cyan-500/15 text-cyan-400'
  if (q.label === 'Fair') return 'mac-badge bg-amber-500/15 text-amber-400'
  if (q.label === 'Poor' || q.label === 'Critical') return 'mac-badge bg-red-500/15 text-red-400'
  return 'mac-badge bg-slate-500/15 text-slate-400'
})

const dotClass = computed(() => {
  const q = signalQuality.value
  if (q.label === 'Excellent') return 'bg-emerald-400'
  if (q.label === 'Good') return 'bg-cyan-400'
  if (q.label === 'Fair') return 'bg-amber-400'
  if (q.label === 'Poor' || q.label === 'Critical') return 'bg-red-400'
  return 'bg-slate-400'
})

// ── Animated Values ─────────────────────────────────────────
const animatedRssi = ref(null)
const animatedSnr = ref(null)
const animatedCritical = ref(null)

function animateValue(targetRef, target, duration = 900) {
  const start = performance.now()
  const startVal = targetRef.value ?? 0
  const diff = target - startVal
  if (Math.abs(diff) < 0.5) {
    targetRef.value = target
    return
  }

  function step(now) {
    const elapsed = now - start
    const progress = Math.min(elapsed / duration, 1)
    // ease-out cubic
    const eased = 1 - Math.pow(1 - progress, 3)
    const current = startVal + diff * eased
    targetRef.value = Number.isInteger(target) ? Math.round(current) : +current.toFixed(1)
    if (progress < 1) requestAnimationFrame(step)
  }
  requestAnimationFrame(step)
}

watch(() => props.signalStats, (stats) => {
  const online = stats?.is_online === true

  if (online && stats?.avg_rssi != null) animateValue(animatedRssi, stats.avg_rssi)
  else animatedRssi.value = null

  if (online && stats?.avg_snr != null) animateValue(animatedSnr, stats.avg_snr)
  else animatedSnr.value = null

  if (online && stats?.critical != null) animateValue(animatedCritical, stats.critical)
  else animatedCritical.value = null
}, { immediate: true })

// ── Sparkline (last 20 RSSI values) ─────────────────────────
const rawSparkline = computed(() => {
  const data = props.signalData || []
  return data.slice(-20).map(d => {
    const v = parseFloat(d.rssi)
    return isNaN(v) ? null : v
  }).filter(v => v != null)
})

const normalizedSparkline = computed(() => {
  const vals = rawSparkline.value
  if (vals.length < 2) return []
  const min = Math.min(...vals)
  const max = Math.max(...vals)
  const range = max - min || 1
  return vals.map(v => (v - min) / range)
})

// ── Segmented Bars Entrance ─────────────────────────────────
const barsVisible = ref(false)
onMounted(() => { setTimeout(() => { barsVisible.value = true }, 200) })

// ── Chart Fade-in ───────────────────────────────────────────
const chartReady = ref(false)
watch(() => props.signalData, (data) => {
  if (data?.length > 0) {
    setTimeout(() => { chartReady.value = true }, 350)
  } else {
    chartReady.value = false
  }
}, { immediate: true })

// ── Range Slider Active Indicator ───────────────────────────
const rangeRef = ref(null)
const indicatorStyle = ref({ width: '0px', left: '0px' })

function updateIndicator() {
  if (!rangeRef.value) return
  const active = rangeRef.value.querySelector('[aria-selected="true"]')
  if (!active) return
  const cr = rangeRef.value.getBoundingClientRect()
  const br = active.getBoundingClientRect()
  indicatorStyle.value = {
    width: `${br.width}px`,
    left: `${br.left - cr.left}px`,
  }
}

watch(() => props.signalRange, () => nextTick(() => updateIndicator()))
onMounted(() => nextTick(() => updateIndicator()))

// ── State Checks ────────────────────────────────────────────
const hasHistory = computed(() => {
  return (props.signalData?.length > 0)
})

const hasStats = computed(() => {
  return isOnline.value && (props.signalStats?.avg_rssi != null || props.signalStats?.avg_snr != null)
})

const isEmpty = computed(() => {
  if (props.loading) return false
  return !hasHistory.value && !isOnline.value
})

const showDecorations = computed(() => !props.loading && isOnline.value)

const hasSignalData = computed(() => props.signalData?.length > 0)

// ── Show charts whenever we have history (even if node is offline) ──
const neverHadData = computed(() => {
  const s = props.signalStats
  return !s || !s.total || s.total === 0
})

// ── Sparkline bar color ─────────────────────────────────────
const sparklineGradient = computed(() => {
  const c = signalQuality.value.barColor
  return `linear-gradient(180deg, ${c} 0%, ${c}33 100%)`
})

function formatStaleness(seconds) {
  if (seconds == null) return ''
  if (seconds < 60) return `${seconds}s ago`
  if (seconds < 3600) return `${Math.round(seconds / 60)}m ago`
  return `${Math.round(seconds / 3600)}h ago`
}
</script>

<template>
  <div
    class="relative overflow-hidden rounded-xl transition-all duration-700"
    :style="bgGradientStyle"
  >
    <!-- ═══ Background animated wave ═══ -->
    <svg
      v-if="showDecorations"
      class="absolute inset-0 w-full h-full pointer-events-none"
      viewBox="0 0 1200 400"
      preserveAspectRatio="none"
      aria-hidden="true"
    >
      <path
        class="signal-wave-1"
        d="M0,220 C200,120 400,320 600,220 C800,120 1000,320 1200,220 L1200,400 L0,400 Z"
        :fill="signalQuality.barColor"
      />
      <path
        class="signal-wave-2"
        d="M0,260 C200,360 400,160 600,260 C800,360 1000,160 1200,260 L1200,400 L0,400 Z"
        :fill="signalQuality.barColor"
      />
    </svg>

    <!-- ═══ Loading skeleton ═══ -->
    <div v-if="loading" class="space-y-4 p-1">
      <div class="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 gap-4 mb-6">
        <div v-for="n in 3" :key="n" class="stat-card">
          <div class="skeleton-text w-20 mb-2" />
          <div class="skeleton-metric" />
        </div>
      </div>
      <div class="mac-card p-5">
        <div class="skeleton-text w-40 mb-4" />
        <div class="skeleton-bar h-2 rounded-full mb-4" />
        <div class="skeleton-text w-full h-48" />
      </div>
    </div>

    <!-- ═══ Error state ═══ -->
    <div
      v-else-if="!signalStats && !loading"
      class="card-panel text-center py-8"
      role="alert"
      aria-live="assertive"
    >
      <span class="material-symbols-outlined text-4xl text-slate-600 mb-3">signal_wifi_off</span>
      <p class="text-slate-500 text-sm mb-2">Failed to load signal data</p>
      <button @click="emit('retry')" class="btn btn-primary text-xs">Retry</button>
    </div>

    <!-- ═══ Empty state (no history at all) ═══ -->
    <div
      v-else-if="!hasHistory && !loading"
      class="card-panel text-center py-12"
      role="status"
      aria-live="polite"
    >
      <div class="flex justify-center mb-4">
        <div class="flex items-end gap-1.5 h-10 opacity-30">
          <div v-for="i in 5" :key="i"
            class="w-4 rounded-t-sm bg-slate-600"
            :style="{ height: (i * 5 + 4) + 'px' }"
          />
        </div>
      </div>
      <p class="text-slate-500 text-sm mb-1">No signal data yet</p>
      <p class="text-slate-600 text-xs">Signal metrics will appear here once received</p>
    </div>

    <!-- ═══ Content (history or node online) ═══ -->
    <div v-else class="relative z-10 space-y-4">
      <!-- ── Quality badge + Segmented signal bars ── -->
      <div class="mac-card p-4 flex items-center justify-between">
        <div class="flex items-center gap-3">
          <span v-if="isOnline" class="w-2.5 h-2.5 rounded-full" :class="[dotClass, 'shadow-sm']" :style="{ boxShadow: `0 0 8px ${signalQuality.barColor}66` }" />
          <span v-else class="w-2.5 h-2.5 rounded-full bg-slate-500/50 shadow-sm" />
          <span :class="badgeClass">{{ signalQuality.label }}</span>
          <span v-if="!isOnline && props.signalStats?.freshness_seconds != null" class="mac-caption text-slate-500 ml-1">
            ({{ formatStaleness(props.signalStats.freshness_seconds) }})
          </span>
        </div>

        <div class="flex items-center gap-3">
          <span class="mac-caption">Signal</span>
          <div class="flex items-end gap-1 h-8">
            <div
              v-for="i in 5"
              :key="i"
              class="w-3 rounded-t-sm transition-all duration-500 ease-[cubic-bezier(0.16,1,0.3,1)]"
              :class="barsVisible ? 'opacity-100 scale-y-100' : 'opacity-0 scale-y-0'"
              :style="{
                height: barsVisible ? (i * 6 + 2) + 'px' : '0px',
                transitionDelay: (i * 80) + 'ms',
                transformOrigin: 'bottom',
                background: i <= signalQuality.bars
                  ? `linear-gradient(180deg, ${signalQuality.barColor}, ${signalQuality.barColor}66)`
                  : 'rgba(51, 65, 85, 0.5)',
                borderRadius: '2px 2px 0 0',
              }"
            />
          </div>
        </div>
      </div>

      <!-- ── Stat cards with sparklines ── -->
      <div class="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 gap-4">
        <StatCard
          label="Avg RSSI"
          :value="animatedRssi != null ? animatedRssi : '--'"
          sublabel="dBm"
          :icon-class="signalQuality.color"
          icon="signal_cellular_alt"
          variant="compact"
        >
          <template #extra>
            <div v-if="normalizedSparkline.length > 0" class="sparkline mt-2">
              <div
                v-for="(val, idx) in normalizedSparkline"
                :key="idx"
                class="sparkline-bar"
                :style="{
                  height: Math.max(3, val * 20) + 'px',
                  background: sparklineGradient,
                }"
              />
            </div>
          </template>
        </StatCard>

        <StatCard
          label="Avg SNR"
          :value="animatedSnr != null ? animatedSnr : '--'"
          sublabel="dB"
          icon="graphic_eq"
          variant="compact"
        >
          <template #extra>
            <div v-if="normalizedSparkline.length > 0" class="sparkline mt-2">
              <div
                v-for="(val, idx) in normalizedSparkline"
                :key="idx"
                class="sparkline-bar"
                :style="{
                  height: Math.max(3, val * 20) + 'px',
                  background: sparklineGradient,
                }"
              />
            </div>
          </template>
        </StatCard>

        <StatCard
          label="Critical Signals"
          :value="animatedCritical != null ? String(animatedCritical) : '--'"
          :icon-class="animatedCritical > 0 ? 'text-red-400' : ''"
          icon="warning"
          variant="compact"
        >
          <template #extra>
            <div v-if="normalizedSparkline.length > 0" class="sparkline mt-2">
              <div
                v-for="(val, idx) in normalizedSparkline"
                :key="idx"
                class="sparkline-bar"
                :style="{
                  height: Math.max(3, val * 20) + 'px',
                  background: sparklineGradient,
                }"
              />
            </div>
          </template>
        </StatCard>
      </div>

      <!-- ── Signal Chart ── -->
      <div
        class="card-panel transition-all duration-600 ease-[cubic-bezier(0.16,1,0.3,1)]"
        :class="chartReady ? 'opacity-100 translate-y-0' : 'opacity-0 translate-y-3'"
      >
        <div class="flex items-center justify-between mb-4">
          <span class="text-sm font-medium text-slate-400">Signal History</span>

          <!-- Range selector with sliding indicator -->
          <div
            ref="rangeRef"
            class="relative flex gap-1"
            role="tablist"
            aria-label="Signal time range"
          >
            <div
              class="absolute bottom-0 h-0.5 rounded-full transition-all duration-300 ease-[cubic-bezier(0.16,1,0.3,1)]"
              :class="signalQuality.color.replace('text-', 'bg-')"
              :style="indicatorStyle"
            />
            <button
              v-for="opt in rangeOptions"
              :key="opt.value"
              @click="emit('update:signal-range', opt.value)"
              :class="[
                'text-xs px-2 py-1.5 rounded-md transition-all duration-200',
                signalRange === opt.value
                  ? 'text-cyan-400'
                  : 'text-slate-500 hover:text-slate-300',
              ]"
              role="tab"
              :aria-selected="signalRange === opt.value"
            >
              {{ opt.label }}
            </button>
          </div>
        </div>

        <Transition name="fade">
          <SignalChart
            :key="'rssi-' + signalRange"
            :data="signalData"
            field="rssi"
            color="#22d3ee"
          />
        </Transition>
      </div>

      <!-- ── SNR Chart ── -->
      <div
        class="card-panel transition-all duration-600 ease-[cubic-bezier(0.16,1,0.3,1)]"
        :class="chartReady ? 'opacity-100 translate-y-0' : 'opacity-0 translate-y-3'"
      >
        <div class="flex items-center justify-between mb-4">
          <span class="text-sm font-medium text-slate-400">SNR History</span>
          <span class="text-[10px] text-slate-600">Signal-to-Noise Ratio</span>
        </div>

        <Transition name="fade">
          <SignalChart
            :key="'snr-' + signalRange"
            :data="signalData"
            field="snr"
            color="#a78bfa"
          />
        </Transition>
      </div>
    </div>
  </div>
</template>

<style scoped>
/* ── Signal Wave Animations ── */
@keyframes wave-drift-1 {
  0%   { transform: translateX(0) scaleY(1); }
  25%  { transform: translateX(-150px) scaleY(1.15); }
  50%  { transform: translateX(-300px) scaleY(1); }
  75%  { transform: translateX(-150px) scaleY(0.85); }
  100% { transform: translateX(0) scaleY(1); }
}
@keyframes wave-drift-2 {
  0%   { transform: translateX(0) scaleY(1); }
  25%  { transform: translateX(150px) scaleY(0.85); }
  50%  { transform: translateX(300px) scaleY(1); }
  75%  { transform: translateX(150px) scaleY(1.15); }
  100% { transform: translateX(0) scaleY(1); }
}
.signal-wave-1 {
  opacity: 0.035;
  animation: wave-drift-1 12s ease-in-out infinite;
}
.signal-wave-2 {
  opacity: 0.025;
  animation: wave-drift-2 16s ease-in-out infinite;
  animation-delay: -4s;
}

/* ── Quality Dot Pulse ── */
@keyframes dot-pulse {
  0%, 100% { opacity: 1; }
  50% { opacity: 0.55; }
}
.animate-dot-pulse {
  animation: dot-pulse 2.4s ease-in-out infinite;
}

/* ── prefers-reduced-motion ── */
@media (prefers-reduced-motion: reduce) {
  .signal-wave-1,
  .signal-wave-2 {
    animation: none;
    opacity: 0.02;
  }
  .animate-dot-pulse {
    animation: none;
  }
}
</style>
