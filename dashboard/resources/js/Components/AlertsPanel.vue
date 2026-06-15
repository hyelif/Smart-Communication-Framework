<script setup>
import { ref, computed, onMounted, watch, nextTick } from 'vue'

const props = defineProps({
  alerts: { type: Array, default: () => [] },
  loading: { type: Boolean, default: false },
  error: { type: Boolean, default: false },
})

const emit = defineEmits(['retry'])

// ─── Stagger entrance ───
const visible = ref(false)

function triggerStagger() {
  nextTick(() => {
    requestAnimationFrame(() => { visible.value = true })
  })
}

watch(() => props.alerts, (val) => {
  if (val && val.length > 0) { triggerStagger() }
  else { visible.value = false }
}, { immediate: true })

onMounted(() => {
  if (props.alerts && props.alerts.length > 0) { triggerStagger() }
})

// ─── Dismissed alerts ───
const dismissedAlerts = ref(new Set())

function dismissAlert(id) {
  dismissedAlerts.value = new Set([...dismissedAlerts.value, id])
}

const activeAlerts = computed(() => {
  return props.alerts.filter(a => !dismissedAlerts.value.has(a.id))
})

// ─── Severity filter ───
const severityFilter = ref('all')

const severityOptions = [
  { id: 'all', label: 'All', color: 'text-slate-400' },
  { id: 'critical', label: 'Critical', color: 'text-red-400' },
  { id: 'warning', label: 'Warning', color: 'text-amber-400' },
  { id: 'info', label: 'Info', color: 'text-blue-400' },
]

// ─── Helpers ───
function timeAgo(dateStr) {
  if (!dateStr) return '--'
  const now = new Date()
  const date = new Date(dateStr)
  const diffMs = now - date
  const diffSeconds = Math.floor(diffMs / 1000)
  if (diffSeconds < 60) return 'Just now'
  const diffMinutes = Math.floor(diffSeconds / 60)
  if (diffMinutes < 60) return `${diffMinutes}m ago`
  const diffHours = Math.floor(diffMinutes / 60)
  if (diffHours < 24) return `${diffHours}h ago`
  const diffDays = Math.floor(diffHours / 24)
  if (diffDays < 30) return `${diffDays}d ago`
  try {
    return date.toLocaleDateString([], { month: 'short', day: 'numeric' })
  } catch { return dateStr }
}

const severityConfig = {
  critical: { icon: 'dangerous', dot: 'bg-red-400', bg: 'bg-red-500/8', border: 'border-l-red-500', label: 'text-red-400', badge: 'bg-red-500/15 text-red-400' },
  warning:  { icon: 'warning',   dot: 'bg-amber-400', bg: 'bg-amber-500/8', border: 'border-l-amber-500', label: 'text-amber-400', badge: 'bg-amber-500/15 text-amber-400' },
  info:     { icon: 'info',      dot: 'bg-blue-400', bg: 'bg-blue-500/8', border: 'border-l-blue-500', label: 'text-blue-400', badge: 'bg-blue-500/15 text-blue-400' },
}

// ─── Computed ───
const filteredAlerts = computed(() => {
  const items = activeAlerts.value || []
  if (severityFilter.value === 'all') return items
  return items.filter(a => a.severity === severityFilter.value)
})

const isEmpty = computed(() => {
  if (props.loading) return false
  return activeAlerts.value.length === 0 && dismissedAlerts.value.size === 0
})

const filteredEmpty = computed(() => {
  if (props.loading) return false
  if (activeAlerts.value.length === 0) return false
  return filteredAlerts.value.length === 0
})

const alertCounts = computed(() => {
  const items = activeAlerts.value || []
  return {
    all: items.length,
    critical: items.filter(a => a.severity === 'critical').length,
    warning: items.filter(a => a.severity === 'warning').length,
    info: items.filter(a => a.severity === 'info').length,
  }
})
</script>

<template>
  <div>
    <!-- ═══ LOADING STATE ═══ -->
    <div v-if="loading" class="space-y-5" aria-hidden="true">
      <div class="mac-card p-4 hover-lift-enhanced">
        <div class="flex flex-wrap items-center gap-6">
          <div class="skeleton-text w-28" />
          <div class="skeleton-text w-24" />
          <div class="skeleton-text w-20" />
          <div class="skeleton-text w-16" />
        </div>
      </div>
      <div class="mac-card p-4 space-y-4">
        <div v-for="n in 5" :key="n" class="flex items-start gap-3">
          <div class="skeleton-text w-2 h-2 rounded-full mt-1" />
          <div class="flex-1 space-y-2">
            <div class="skeleton-text w-3/4" />
            <div class="skeleton-text w-1/2" />
          </div>
          <div class="skeleton-text w-16" />
        </div>
      </div>
    </div>

    <!-- ═══ ERROR STATE ═══ -->
    <div
      v-else-if="error"
      class="card-panel text-center py-12"
      role="alert"
      aria-live="assertive"
    >
      <div class="flex flex-col items-center gap-4">
        <div class="w-14 h-14 rounded-full bg-red-500/10 flex items-center justify-center">
          <span class="material-symbols-outlined text-3xl text-red-400">error_outline</span>
        </div>
        <div>
          <p class="text-slate-300 text-sm font-medium mb-1">Failed to load alerts</p>
          <p class="text-slate-500 text-xs">Could not retrieve alert data</p>
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

    <!-- ═══ EMPTY STATE ═══ -->
    <div
      v-else-if="isEmpty"
      class="card-panel text-center py-16"
    >
      <div class="flex flex-col items-center gap-4">
        <div class="relative">
          <span class="material-symbols-outlined text-6xl text-slate-700 animate-float">notifications_off</span>
          <span class="material-symbols-outlined text-2xl text-emerald-400 absolute -top-1 -right-2">check_circle</span>
        </div>
        <p class="text-slate-400 text-sm font-medium">No active alerts</p>
        <p class="text-slate-600 text-xs">Everything looks good — no alerts to display</p>
      </div>
    </div>

    <!-- ═══ DATA DISPLAY ═══ -->
    <div v-else class="space-y-6">
      <!-- ─── Summary Bar ─── -->
      <div class="mac-card p-4 flex flex-wrap items-center justify-between gap-4">
        <div class="flex items-center gap-3 min-w-0">
          <div class="w-10 h-10 rounded-lg bg-red-500/12 flex items-center justify-center shrink-0">
            <span class="material-symbols-outlined text-red-400">notifications_active</span>
          </div>
          <div class="min-w-0">
            <p class="text-[11px] font-medium text-slate-500 uppercase tracking-wider">Total Alerts</p>
            <p class="text-xl font-bold text-white tabular-nums leading-tight">{{ alertCounts.all }}</p>
          </div>
        </div>
        <div class="flex items-center gap-3 min-w-0">
          <div class="w-10 h-10 rounded-lg bg-red-500/12 flex items-center justify-center shrink-0">
            <span class="material-symbols-outlined text-red-400">dangerous</span>
          </div>
          <div class="min-w-0">
            <p class="text-[11px] font-medium text-slate-500 uppercase tracking-wider">Critical</p>
            <p class="text-xl font-bold text-red-400 tabular-nums leading-tight">{{ alertCounts.critical }}</p>
          </div>
        </div>
        <div class="flex items-center gap-3 min-w-0">
          <div class="w-10 h-10 rounded-lg bg-amber-500/12 flex items-center justify-center shrink-0">
            <span class="material-symbols-outlined text-amber-400">warning</span>
          </div>
          <div class="min-w-0">
            <p class="text-[11px] font-medium text-slate-500 uppercase tracking-wider">Warning</p>
            <p class="text-xl font-bold text-amber-400 tabular-nums leading-tight">{{ alertCounts.warning }}</p>
          </div>
        </div>
        <div class="flex items-center gap-3 min-w-0">
          <div class="w-10 h-10 rounded-lg bg-blue-500/12 flex items-center justify-center shrink-0">
            <span class="material-symbols-outlined text-blue-400">info</span>
          </div>
          <div class="min-w-0">
            <p class="text-[11px] font-medium text-slate-500 uppercase tracking-wider">Info</p>
            <p class="text-xl font-bold text-blue-400 tabular-nums leading-tight">{{ alertCounts.info }}</p>
          </div>
        </div>
      </div>

      <!-- ─── Severity Filter Tabs ─── -->
      <div class="flex items-center gap-2 flex-wrap">
        <button
          v-for="opt in severityOptions"
          :key="opt.id"
          @click="severityFilter = opt.id"
          :class="[
            'text-xs px-3 py-1.5 rounded-lg transition-all duration-200 font-medium',
            severityFilter === opt.id
              ? 'bg-slate-700/60 text-white'
              : 'text-slate-500 hover:text-slate-300 hover:bg-slate-800/40',
          ]"
        >
          {{ opt.label }}
          <span class="ml-1.5 text-[10px] opacity-60">({{ alertCounts[opt.id] || 0 }})</span>
        </button>
      </div>

      <!-- ─── Filtered Empty ─── -->
      <div
        v-if="filteredEmpty"
        class="card-panel text-center py-8"
      >
        <p class="text-slate-500 text-sm">No {{ severityFilter === 'all' ? '' : severityFilter }} alerts</p>
      </div>

      <!-- ─── Alert List ─── -->
      <div v-else class="space-y-2">
        <TransitionGroup name="list">
          <div
            v-for="(alert, index) in filteredAlerts"
            :key="alert.id || index"
            class="stagger-enter rounded-lg px-4 py-3 transition-all duration-200 hover:-translate-y-0.5 flex items-start gap-2"
            :class="[visible ? 'visible' : '', severityConfig[alert.severity]?.bg || 'bg-slate-800/30']"
            :style="{
              transitionDelay: `${index * 50}ms`,
              borderLeft: `3px solid ${alert.severity === 'critical' ? '#ef4444' : alert.severity === 'warning' ? '#f59e0b' : '#3b82f6'}`,
            }"
        >
          <div class="flex items-start justify-between gap-3">
            <div class="flex items-start gap-2.5 min-w-0 flex-1">
              <!-- Severity icon -->
              <span
                class="material-symbols-outlined text-sm mt-0.5 flex-shrink-0"
                :class="severityConfig[alert.severity]?.label || 'text-slate-400'"
              >
                {{ severityConfig[alert.severity]?.icon || 'circle' }}
              </span>

              <div class="min-w-0 flex-1">
                <!-- Message -->
                <p class="text-sm text-slate-200 leading-snug">{{ alert.message }}</p>

                <!-- Meta row -->
                <div class="flex flex-wrap items-center gap-x-3 gap-y-1 mt-1">
                  <span class="text-[11px] text-slate-500 font-mono">{{ alert.hardware_id }}</span>
                  <span v-if="alert.sensor_key" class="text-[11px] text-slate-500">sensor: {{ alert.sensor_key }}</span>
                  <span
                    class="text-[11px] font-medium px-1.5 py-0.5 rounded-full"
                    :class="severityConfig[alert.severity]?.badge || 'bg-slate-500/15 text-slate-400'"
                  >
                    {{ alert.severity }}
                  </span>
                </div>
              </div>
            </div>

            <!-- Time -->
            <span class="text-[11px] text-slate-500 whitespace-nowrap flex-shrink-0 tabular-nums">
              {{ timeAgo(alert.created_at) }}
            </span>
            <!-- Dismiss -->
            <button
              class="text-slate-600 hover:text-slate-300 transition-colors material-symbols-outlined text-sm flex-shrink-0 -mr-1"
              @click.stop="dismissAlert(alert.id)"
              aria-label="Dismiss alert"
              title="Dismiss"
            >close</button>
          </div>
          </div>
        </TransitionGroup>
      </div>
    </div>
  </div>
</template>
