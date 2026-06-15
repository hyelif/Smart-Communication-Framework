<script setup>
import { ref, computed, watch, onMounted, nextTick } from 'vue'

const props = defineProps({
  data: { type: Object, default: null },
  loading: { type: Boolean, default: false },
})

const emit = defineEmits(['retry'])

// ─── Stagger entrance ───
const visible = ref(false)

function triggerStagger() {
  nextTick(() => {
    requestAnimationFrame(() => {
      visible.value = true
    })
  })
}

watch(() => props.data, (val) => {
  if (val && !val.error) {
    triggerStagger()
  } else {
    visible.value = false
  }
}, { immediate: true })

onMounted(() => {
  if (props.data && !props.data.error) {
    triggerStagger()
  }
})

// ─── Animated counter (ease-out cubic) ───
const animated = ref({})

function tween(key, target, duration = 900) {
  if (target == null) {
    animated.value[key] = 0
    return
  }
  if (target === 0) {
    animated.value[key] = 0
    return
  }
  const start = performance.now()
  const from = 0
  function frame(now) {
    const t = Math.min((now - start) / duration, 1)
    const e = 1 - Math.pow(1 - t, 3) // ease-out cubic
    animated.value[key] = Math.round(from + (target - from) * e)
    if (t < 1) requestAnimationFrame(frame)
  }
  requestAnimationFrame(frame)
}

watch(() => props.data, (val) => {
  if (!val || val.error) return
  const p = val.priority || {}
  const r = val.report_mode || {}
  tween('pHigh', p.HIGH || 0)
  tween('pMed', p.MEDIUM || 0)
  tween('pLow', p.LOW || 0)
  tween('pTotal', p.total || 0)
  tween('rNorm', r.NORMAL || 0)
  tween('rAbnorm', r.ABNORMAL || 0)
  tween('rCrit', r.CRITICAL || 0)
  tween('rTotal', r.total || 0)
}, { immediate: true })

// ─── Percentage helpers ───
const priorityPct = computed(() => {
  const p = props.data?.priority
  const total = p?.total || 0
  return {
    high:   total ? +((p.HIGH   || 0) / total * 100).toFixed(1) : 0,
    medium: total ? +((p.MEDIUM || 0) / total * 100).toFixed(1) : 0,
    low:    total ? +((p.LOW    || 0) / total * 100).toFixed(1) : 0,
  }
})

const reportPct = computed(() => {
  const r = props.data?.report_mode
  const total = r?.total || 0
  return {
    normal:   total ? +((r.NORMAL   || 0) / total * 100).toFixed(1) : 0,
    abnormal: total ? +((r.ABNORMAL || 0) / total * 100).toFixed(1) : 0,
    critical: total ? +((r.CRITICAL || 0) / total * 100).toFixed(1) : 0,
  }
})

// ─── Sparkline bar heights (deterministic pattern) ───
const sparkBars = [35, 50, 28, 65, 45, 80, 55, 72, 40, 90, 60, 75]

function sparkSlice(start, count = 6) {
  return sparkBars.slice(start, start + count)
}

// ─── Format generated_at ───
const formattedTime = computed(() => {
  if (!props.data?.generated_at) return '--'
  try {
    const d = new Date(props.data.generated_at)
    return d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' })
  } catch {
    return props.data.generated_at
  }
})
</script>

<template>
  <div>
    <!-- ═══════════════════════════════════════════════════════════════
         LOADING STATE
         ═══════════════════════════════════════════════════════════════ -->
    <div v-if="loading" class="space-y-5" aria-hidden="true">
      <!-- Summary skeleton -->
      <div class="mac-card p-5">
        <div class="flex flex-wrap items-center gap-6">
          <div class="skeleton-text w-28" />
          <div class="skeleton-text w-24" />
          <div class="skeleton-text w-20" />
        </div>
      </div>
      <!-- Section 1 skeleton -->
      <div class="mac-card p-5">
        <div class="skeleton-text w-36 mb-5" />
        <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
          <div v-for="i in 4" :key="'a' + i" class="rounded-xl bg-surface-lighter/40 p-4 space-y-3">
            <div class="flex items-center gap-2">
              <div class="skeleton-text w-5 h-5 rounded-lg" />
              <div class="skeleton-text w-24" />
            </div>
            <div class="skeleton-metric" />
            <div class="skeleton-text w-full" />
          </div>
        </div>
      </div>
      <!-- Section 2 skeleton -->
      <div class="mac-card p-5">
        <div class="skeleton-text w-36 mb-5" />
        <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
          <div v-for="i in 4" :key="'b' + i" class="rounded-xl bg-surface-lighter/40 p-4 space-y-3">
            <div class="flex items-center gap-2">
              <div class="skeleton-text w-5 h-5 rounded-lg" />
              <div class="skeleton-text w-24" />
            </div>
            <div class="skeleton-metric" />
            <div class="skeleton-text w-full" />
          </div>
        </div>
      </div>
    </div>

    <!-- ═══════════════════════════════════════════════════════════════
         EMPTY STATE
         ═══════════════════════════════════════════════════════════════ -->
    <div
      v-else-if="!data || Object.keys(data).length === 0"
      class="card-panel text-center py-16"
    >
      <div class="flex flex-col items-center gap-4">
        <div class="relative">
          <span class="material-symbols-outlined text-6xl text-slate-700 animate-float">analytics</span>
          <span class="material-symbols-outlined text-2xl text-slate-600 absolute -top-1 -right-2 animate-pulse">insights</span>
        </div>
        <p class="text-slate-400 text-sm font-medium">No analytics data available</p>
        <p class="text-slate-600 text-xs">Data will appear once sensor readings are collected</p>
      </div>
    </div>

    <!-- ═══════════════════════════════════════════════════════════════
         ERROR STATE
         ═══════════════════════════════════════════════════════════════ -->
    <div
      v-else-if="data?.error"
      class="card-panel text-center py-12"
      role="alert"
      aria-live="assertive"
    >
      <div class="flex flex-col items-center gap-4">
        <div class="w-14 h-14 rounded-full bg-red-500/10 flex items-center justify-center">
          <span class="material-symbols-outlined text-3xl text-red-400">error_outline</span>
        </div>
        <div>
          <p class="text-slate-300 text-sm font-medium mb-1">Failed to load analytics data</p>
          <p class="text-slate-500 text-xs">{{ data.error }}</p>
        </div>
        <button
          @click="emit('retry')"
          class="btn btn-primary text-xs inline-flex items-center gap-1.5 active-scale"
        >
          <span class="material-symbols-outlined text-sm">refresh</span>
          Retry
        </button>
      </div>
    </div>

    <!-- ═══════════════════════════════════════════════════════════════
         DATA DISPLAY
         ═══════════════════════════════════════════════════════════════ -->
    <div v-else class="space-y-6">

      <!-- ─── Summary Bar ─── -->
      <div class="glass-card-enhanced rounded-xl p-4 flex flex-wrap items-center justify-between gap-4">
        <!-- Total readings -->
        <div class="flex items-center gap-3 min-w-0">
          <div class="w-10 h-10 rounded-lg bg-cyan-500/12 flex items-center justify-center shrink-0">
            <span class="material-symbols-outlined text-cyan-400">database</span>
          </div>
          <div class="min-w-0">
            <p class="text-[11px] font-medium text-slate-500 uppercase tracking-wider">Total Readings</p>
            <p class="text-xl font-bold text-white tabular-nums leading-tight">{{ animated.pTotal ?? 0 }}</p>
          </div>
        </div>
        <!-- Time range -->
        <div class="flex items-center gap-3 min-w-0">
          <div class="w-10 h-10 rounded-lg bg-violet-500/12 flex items-center justify-center shrink-0">
            <span class="material-symbols-outlined text-violet-400">schedule</span>
          </div>
          <div class="min-w-0">
            <p class="text-[11px] font-medium text-slate-500 uppercase tracking-wider">Time Range</p>
            <p class="text-base font-semibold text-white leading-tight">{{ data.range || '--' }}</p>
          </div>
        </div>
        <!-- Generated at -->
        <div class="flex items-center gap-3 min-w-0">
          <div class="w-10 h-10 rounded-lg bg-emerald-500/12 flex items-center justify-center shrink-0">
            <span class="material-symbols-outlined text-emerald-400">update</span>
          </div>
          <div class="min-w-0">
            <p class="text-[11px] font-medium text-slate-500 uppercase tracking-wider">Generated</p>
            <p class="text-base font-semibold text-white leading-tight tabular-nums">{{ formattedTime }}</p>
          </div>
        </div>
      </div>

      <!-- ─── Priority Breakdown Section ─── -->
      <div>
        <div class="section-header">
          <span class="material-symbols-outlined text-amber-400 text-lg">priority_high</span>
          <span class="section-header-title">Priority Breakdown</span>
          <span v-if="data.priority?.total" class="section-header-badge">{{ data.priority.total }} total</span>
        </div>

        <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
          <!-- HIGH card -->
          <div
            class="glass-card-enhanced rounded-xl p-4 stagger-enter hover:-translate-y-0.5 transition-all duration-200"
            :class="{ visible }"
            style="transition-delay: 0ms"
          >
            <div class="flex items-start justify-between mb-3">
              <div class="flex items-center gap-2.5">
                <div class="w-8 h-8 rounded-lg bg-red-500/15 flex items-center justify-center shrink-0">
                  <span class="material-symbols-outlined text-red-400 text-sm">arrow_upward</span>
                </div>
                <div>
                  <p class="text-xs font-medium text-slate-500 uppercase tracking-wider">High Priority</p>
                </div>
              </div>
              <span class="text-2xl font-bold text-red-400 tabular-nums counter-value">{{ animated.pHigh ?? 0 }}</span>
            </div>
            <!-- Progress bar -->
            <div class="progress-bar mb-2">
              <div
                class="progress-bar-fill red"
                :style="{ width: visible ? priorityPct.high + '%' : '0%' }"
              />
            </div>
            <div class="flex items-center justify-between">
              <span class="text-xs text-slate-500">{{ priorityPct.high }}% of total</span>
              <!-- CSS sparkline -->
              <div class="sparkline" aria-hidden="true">
                <div
                  v-for="(h, i) in sparkSlice(0, 6)"
                  :key="i"
                  class="sparkline-bar"
                  :style="{ height: (h / 100) * 24 + 'px', background: 'linear-gradient(180deg, #ef4444 0%, rgba(239,68,68,0.25) 100%)' }"
                />
              </div>
            </div>
          </div>

          <!-- MEDIUM card -->
          <div
            class="glass-card-enhanced rounded-xl p-4 stagger-enter hover:-translate-y-0.5 transition-all duration-200"
            :class="{ visible }"
            style="transition-delay: 80ms"
          >
            <div class="flex items-start justify-between mb-3">
              <div class="flex items-center gap-2.5">
                <div class="w-8 h-8 rounded-lg bg-amber-500/15 flex items-center justify-center shrink-0">
                  <span class="material-symbols-outlined text-amber-400 text-sm">remove</span>
                </div>
                <div>
                  <p class="text-xs font-medium text-slate-500 uppercase tracking-wider">Medium Priority</p>
                </div>
              </div>
              <span class="text-2xl font-bold text-amber-400 tabular-nums counter-value">{{ animated.pMed ?? 0 }}</span>
            </div>
            <div class="progress-bar mb-2">
              <div
                class="progress-bar-fill amber"
                :style="{ width: visible ? priorityPct.medium + '%' : '0%' }"
              />
            </div>
            <div class="flex items-center justify-between">
              <span class="text-xs text-slate-500">{{ priorityPct.medium }}% of total</span>
              <div class="sparkline" aria-hidden="true">
                <div
                  v-for="(h, i) in sparkSlice(3, 6)"
                  :key="i"
                  class="sparkline-bar"
                  :style="{ height: (h / 100) * 24 + 'px', background: 'linear-gradient(180deg, #f59e0b 0%, rgba(245,158,11,0.25) 100%)' }"
                />
              </div>
            </div>
          </div>

          <!-- LOW card -->
          <div
            class="glass-card-enhanced rounded-xl p-4 stagger-enter hover:-translate-y-0.5 transition-all duration-200"
            :class="{ visible }"
            style="transition-delay: 160ms"
          >
            <div class="flex items-start justify-between mb-3">
              <div class="flex items-center gap-2.5">
                <div class="w-8 h-8 rounded-lg bg-emerald-500/15 flex items-center justify-center shrink-0">
                  <span class="material-symbols-outlined text-emerald-400 text-sm">arrow_downward</span>
                </div>
                <div>
                  <p class="text-xs font-medium text-slate-500 uppercase tracking-wider">Low Priority</p>
                </div>
              </div>
              <span class="text-2xl font-bold text-emerald-400 tabular-nums counter-value">{{ animated.pLow ?? 0 }}</span>
            </div>
            <div class="progress-bar mb-2">
              <div
                class="progress-bar-fill green"
                :style="{ width: visible ? priorityPct.low + '%' : '0%' }"
              />
            </div>
            <div class="flex items-center justify-between">
              <span class="text-xs text-slate-500">{{ priorityPct.low }}% of total</span>
              <div class="sparkline" aria-hidden="true">
                <div
                  v-for="(h, i) in sparkSlice(6, 6)"
                  :key="i"
                  class="sparkline-bar"
                  :style="{ height: (h / 100) * 24 + 'px', background: 'linear-gradient(180deg, #10b981 0%, rgba(16,185,129,0.25) 100%)' }"
                />
              </div>
            </div>
          </div>

          <!-- Priority Distribution summary card -->
          <div
            class="glass-card-enhanced rounded-xl p-4 stagger-enter hover:-translate-y-0.5 transition-all duration-200"
            :class="{ visible }"
            style="transition-delay: 240ms"
          >
            <div class="flex items-start justify-between mb-3">
              <div class="flex items-center gap-2.5">
                <div class="w-8 h-8 rounded-lg bg-cyan-500/15 flex items-center justify-center shrink-0">
                  <span class="material-symbols-outlined text-cyan-400 text-sm">donut_small</span>
                </div>
                <div>
                  <p class="text-xs font-medium text-slate-500 uppercase tracking-wider">Distribution</p>
                </div>
              </div>
              <span class="text-2xl font-bold text-white tabular-nums counter-value">{{ animated.pTotal ?? 0 }}</span>
            </div>
            <!-- Stacked bar -->
            <div class="flex h-2 rounded-full overflow-hidden gap-0.5 mb-3">
              <div
                class="h-full rounded-full transition-all duration-700 ease-out-soft"
                :style="{ width: priorityPct.high + '%', background: '#ef4444' }"
              />
              <div
                class="h-full rounded-full transition-all duration-700 ease-out-soft"
                :style="{ width: priorityPct.medium + '%', background: '#f59e0b' }"
              />
              <div
                class="h-full rounded-full transition-all duration-700 ease-out-soft"
                :style="{ width: priorityPct.low + '%', background: '#10b981' }"
              />
            </div>
            <div class="flex flex-wrap gap-x-4 gap-y-1 text-[11px]">
              <span class="flex items-center gap-1.5 text-slate-400">
                <span class="w-2 h-2 rounded-full bg-red-400 shrink-0" />
                High: {{ data.priority?.HIGH || 0 }}
              </span>
              <span class="flex items-center gap-1.5 text-slate-400">
                <span class="w-2 h-2 rounded-full bg-amber-400 shrink-0" />
                Med: {{ data.priority?.MEDIUM || 0 }}
              </span>
              <span class="flex items-center gap-1.5 text-slate-400">
                <span class="w-2 h-2 rounded-full bg-emerald-400 shrink-0" />
                Low: {{ data.priority?.LOW || 0 }}
              </span>
            </div>
          </div>
        </div>
      </div>

      <!-- ─── Report Mode Distribution Section ─── -->
      <div>
        <div class="section-header">
          <span class="material-symbols-outlined text-cyan-400 text-lg">report</span>
          <span class="section-header-title">Report Mode Distribution</span>
          <span v-if="data.report_mode?.total" class="section-header-badge">{{ data.report_mode.total }} total</span>
        </div>

        <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
          <!-- NORMAL card -->
          <div
            class="glass-card-enhanced rounded-xl p-4 stagger-enter hover:-translate-y-0.5 transition-all duration-200"
            :class="{ visible }"
            style="transition-delay: 0ms"
          >
            <div class="flex items-start justify-between mb-3">
              <div class="flex items-center gap-2.5">
                <div class="w-8 h-8 rounded-lg bg-emerald-500/15 flex items-center justify-center shrink-0">
                  <span class="material-symbols-outlined text-emerald-400 text-sm">check_circle</span>
                </div>
                <div>
                  <p class="text-xs font-medium text-slate-500 uppercase tracking-wider">Normal</p>
                </div>
              </div>
              <span class="text-2xl font-bold text-emerald-400 tabular-nums counter-value">{{ animated.rNorm ?? 0 }}</span>
            </div>
            <div class="progress-bar mb-2">
              <div
                class="progress-bar-fill green"
                :style="{ width: visible ? reportPct.normal + '%' : '0%' }"
              />
            </div>
            <div class="flex items-center justify-between">
              <span class="text-xs text-slate-500">{{ reportPct.normal }}% of total</span>
              <div class="sparkline" aria-hidden="true">
                <div
                  v-for="(h, i) in sparkSlice(1, 6)"
                  :key="i"
                  class="sparkline-bar"
                  :style="{ height: (h / 100) * 24 + 'px', background: 'linear-gradient(180deg, #10b981 0%, rgba(16,185,129,0.25) 100%)' }"
                />
              </div>
            </div>
          </div>

          <!-- ABNORMAL card -->
          <div
            class="glass-card-enhanced rounded-xl p-4 stagger-enter hover:-translate-y-0.5 transition-all duration-200"
            :class="{ visible }"
            style="transition-delay: 80ms"
          >
            <div class="flex items-start justify-between mb-3">
              <div class="flex items-center gap-2.5">
                <div class="w-8 h-8 rounded-lg bg-amber-500/15 flex items-center justify-center shrink-0">
                  <span class="material-symbols-outlined text-amber-400 text-sm">warning</span>
                </div>
                <div>
                  <p class="text-xs font-medium text-slate-500 uppercase tracking-wider">Abnormal</p>
                </div>
              </div>
              <span class="text-2xl font-bold text-amber-400 tabular-nums counter-value">{{ animated.rAbnorm ?? 0 }}</span>
            </div>
            <div class="progress-bar mb-2">
              <div
                class="progress-bar-fill amber"
                :style="{ width: visible ? reportPct.abnormal + '%' : '0%' }"
              />
            </div>
            <div class="flex items-center justify-between">
              <span class="text-xs text-slate-500">{{ reportPct.abnormal }}% of total</span>
              <div class="sparkline" aria-hidden="true">
                <div
                  v-for="(h, i) in sparkSlice(4, 6)"
                  :key="i"
                  class="sparkline-bar"
                  :style="{ height: (h / 100) * 24 + 'px', background: 'linear-gradient(180deg, #f59e0b 0%, rgba(245,158,11,0.25) 100%)' }"
                />
              </div>
            </div>
          </div>

          <!-- CRITICAL card -->
          <div
            class="glass-card-enhanced rounded-xl p-4 stagger-enter hover:-translate-y-0.5 transition-all duration-200"
            :class="{ visible }"
            style="transition-delay: 160ms"
          >
            <div class="flex items-start justify-between mb-3">
              <div class="flex items-center gap-2.5">
                <div class="w-8 h-8 rounded-lg bg-red-500/15 flex items-center justify-center shrink-0">
                  <span class="material-symbols-outlined text-red-400 text-sm">dangerous</span>
                </div>
                <div>
                  <p class="text-xs font-medium text-slate-500 uppercase tracking-wider">Critical</p>
                </div>
              </div>
              <span class="text-2xl font-bold text-red-400 tabular-nums counter-value">{{ animated.rCrit ?? 0 }}</span>
            </div>
            <div class="progress-bar mb-2">
              <div
                class="progress-bar-fill red"
                :style="{ width: visible ? reportPct.critical + '%' : '0%' }"
              />
            </div>
            <div class="flex items-center justify-between">
              <span class="text-xs text-slate-500">{{ reportPct.critical }}% of total</span>
              <div class="sparkline" aria-hidden="true">
                <div
                  v-for="(h, i) in sparkSlice(7, 6)"
                  :key="i"
                  class="sparkline-bar"
                  :style="{ height: (h / 100) * 24 + 'px', background: 'linear-gradient(180deg, #ef4444 0%, rgba(239,68,68,0.25) 100%)' }"
                />
              </div>
            </div>
          </div>

          <!-- Report Distribution summary card -->
          <div
            class="glass-card-enhanced rounded-xl p-4 stagger-enter hover:-translate-y-0.5 transition-all duration-200"
            :class="{ visible }"
            style="transition-delay: 240ms"
          >
            <div class="flex items-start justify-between mb-3">
              <div class="flex items-center gap-2.5">
                <div class="w-8 h-8 rounded-lg bg-cyan-500/15 flex items-center justify-center shrink-0">
                  <span class="material-symbols-outlined text-cyan-400 text-sm">donut_small</span>
                </div>
                <div>
                  <p class="text-xs font-medium text-slate-500 uppercase tracking-wider">Distribution</p>
                </div>
              </div>
              <span class="text-2xl font-bold text-white tabular-nums counter-value">{{ animated.rTotal ?? 0 }}</span>
            </div>
            <!-- Stacked bar -->
            <div class="flex h-2 rounded-full overflow-hidden gap-0.5 mb-3">
              <div
                class="h-full rounded-full transition-all duration-700 ease-out-soft"
                :style="{ width: reportPct.normal + '%', background: '#10b981' }"
              />
              <div
                class="h-full rounded-full transition-all duration-700 ease-out-soft"
                :style="{ width: reportPct.abnormal + '%', background: '#f59e0b' }"
              />
              <div
                class="h-full rounded-full transition-all duration-700 ease-out-soft"
                :style="{ width: reportPct.critical + '%', background: '#ef4444' }"
              />
            </div>
            <div class="flex flex-wrap gap-x-4 gap-y-1 text-[11px]">
              <span class="flex items-center gap-1.5 text-slate-400">
                <span class="w-2 h-2 rounded-full bg-emerald-400 shrink-0" />
                Normal: {{ data.report_mode?.NORMAL || 0 }}
              </span>
              <span class="flex items-center gap-1.5 text-slate-400">
                <span class="w-2 h-2 rounded-full bg-amber-400 shrink-0" />
                Abnormal: {{ data.report_mode?.ABNORMAL || 0 }}
              </span>
              <span class="flex items-center gap-1.5 text-slate-400">
                <span class="w-2 h-2 rounded-full bg-red-400 shrink-0" />
                Critical: {{ data.report_mode?.CRITICAL || 0 }}
              </span>
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
