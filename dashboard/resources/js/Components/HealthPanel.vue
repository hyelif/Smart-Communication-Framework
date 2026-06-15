<script setup>
import { computed } from 'vue'
import { useSensorHistory } from '../Composables/useSensorHistory'

const props = defineProps({
  sensors: { type: Array, default: () => [] },
  profiles: { type: Object, default: () => ({}) },
  minutesSince: { type: Number, default: null },
  lastUpdated: { type: String, default: '' },
})

const { computeAnomalyScore, computeHealthScore, computeTrend } = useSensorHistory()

const sensorScores = computed(() => {
  return props.sensors.map(s => {
    const val = parseFloat(s.value)
    const profile = props.profiles[s.key] || {}
    const anomaly = isNaN(val) ? 0 : computeAnomalyScore(s.key, val, profile, props.minutesSince)
    const health = computeHealthScore(anomaly)
    const trend = isNaN(val) ? 'stable' : computeTrend(s.key, profile)
    const status = s.status || 'normal'
    return {
      key: s.key,
      label: s.label || s.key,
      value: isNaN(val) ? '--' : val,
      unit: s.unit || '',
      health,
      anomaly,
      trend,
      status,
      color: profile.color || '#64748b',
      tMin: profile.t_min,
      tMax: profile.t_max,
    }
  })
})

const systemHealth = computed(() => {
  const scores = sensorScores.value
  if (scores.length === 0) return { health: 100, trend: 'stable', atRisk: 0, total: 0 }
  const avg = scores.reduce((a, s) => a + s.health, 0) / scores.length
  const atRisk = scores.filter(s => s.health < 70).length
  const declining = scores.filter(s => s.trend === 'declining').length
  const improving = scores.filter(s => s.trend === 'improving').length
  let trend = 'stable'
  if (declining > improving && declining >= scores.length / 3) trend = 'declining'
  else if (improving > declining && improving >= scores.length / 3) trend = 'improving'
  return { health: Math.round(avg), trend, atRisk, total: scores.length }
})

function healthColor(h) {
  if (h >= 80) return 'text-emerald-400'
  if (h >= 60) return 'text-amber-400'
  return 'text-red-400'
}

function healthBg(h) {
  if (h >= 80) return 'bg-emerald-500/10 border-emerald-500/20'
  if (h >= 60) return 'bg-amber-500/10 border-amber-500/20'
  return 'bg-red-500/10 border-red-500/20'
}

function healthBarColor(h) {
  if (h >= 80) return '#34d399'
  if (h >= 60) return '#f59e0b'
  return '#ef4444'
}

function statusBadge(status) {
  if (status === 'low') return { text: 'Low', class: 'bg-amber-500/15 text-amber-400' }
  if (status === 'high') return { text: 'High', class: 'bg-red-500/15 text-red-400' }
  return { text: 'Normal', class: 'bg-emerald-500/15 text-emerald-400' }
}

function trendIcon(t) {
  if (t === 'improving') return 'trending_up'
  if (t === 'declining') return 'trending_down'
  return 'trending_flat'
}

function trendColor(t) {
  if (t === 'improving') return 'text-emerald-400'
  if (t === 'declining') return 'text-red-400'
  return 'text-slate-500'
}

const ringCircumference = 2 * Math.PI * 42
</script>

<template>
  <div>
    <!-- Header -->
    <div class="flex items-center justify-between mb-5">
      <div>
        <h1 class="mac-title">System Health</h1>
        <p class="mac-caption mt-0.5">Real-time health monitoring and anomaly detection</p>
      </div>
      <div v-if="systemHealth.atRisk > 0" class="flex items-center gap-1.5 px-3 py-1.5 rounded-lg bg-red-500/10 border border-red-500/20 text-xs text-red-400">
        <span class="material-symbols-outlined text-sm">warning</span>
        <span class="font-semibold">{{ systemHealth.atRisk }} at risk</span>
      </div>
    </div>

    <!-- Overall Health Card -->
    <div class="mac-card p-5 mb-5">
      <div class="flex items-center gap-6">
        <!-- Large ring -->
        <div class="relative w-28 h-28 flex items-center justify-center flex-shrink-0">
          <svg class="w-28 h-28 -rotate-90" viewBox="0 0 100 100">
            <circle cx="50" cy="50" r="42" fill="none" stroke="rgba(255,255,255,0.04)" stroke-width="6" />
            <circle
              cx="50" cy="50" r="42" fill="none"
              :stroke="healthBarColor(systemHealth.health)"
              stroke-width="6"
              stroke-linecap="round"
              :stroke-dasharray="ringCircumference"
              :stroke-dashoffset="ringCircumference * (1 - systemHealth.health / 100)"
              class="transition-all duration-700"
            />
          </svg>
          <div class="absolute flex flex-col items-center">
            <span class="text-3xl font-bold" :class="healthColor(systemHealth.health)">{{ systemHealth.health }}%</span>
          </div>
        </div>

        <!-- Stats -->
        <div class="space-y-2">
          <div class="flex items-center gap-2 text-sm">
            <span class="material-symbols-outlined text-lg" :class="trendColor(systemHealth.trend)">{{ trendIcon(systemHealth.trend) }}</span>
            <span :class="trendColor(systemHealth.trend)" class="font-semibold capitalize">{{ systemHealth.trend }}</span>
          </div>
          <div class="text-xs text-slate-500 flex items-center gap-3">
            <span>{{ systemHealth.total }} sensors</span>
            <span class="w-1 h-1 rounded-full bg-slate-600" />
            <span>{{ systemHealth.atRisk }} at risk</span>
            <span class="w-1 h-1 rounded-full bg-slate-600" />
            <span v-if="lastUpdated">Updated {{ lastUpdated }}</span>
          </div>
        </div>
      </div>
    </div>

    <!-- Per-Sensor Grid -->
    <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-3">
      <div
        v-for="s in sensorScores"
        :key="s.key"
        class="mac-card p-4"
        :class="s.health < 70 ? 'border-red-500/20' : s.health < 80 ? 'border-amber-500/20' : ''"
      >
        <!-- Header -->
        <div class="flex items-center justify-between mb-2">
          <div class="flex items-center gap-2">
            <span class="w-2 h-2 rounded-full" :class="healthColor(s.health)" />
            <span class="text-sm font-medium text-slate-300">{{ s.label }}</span>
          </div>
          <span class="material-symbols-outlined text-sm" :class="trendColor(s.trend)">{{ trendIcon(s.trend) }}</span>
        </div>

        <!-- Value -->
        <div class="flex items-baseline gap-1 mb-2">
          <span class="text-xl font-bold text-white tabular-nums">{{ typeof s.value === 'number' ? s.value.toFixed(1) : s.value }}</span>
          <span class="text-xs text-slate-500">{{ s.unit }}</span>
        </div>

        <!-- Health bar -->
        <div class="h-2 rounded-full bg-white/5 overflow-hidden mb-2">
          <div
            class="h-full rounded-full transition-all duration-500"
            :style="{ width: Math.max(4, s.health) + '%', background: healthBarColor(s.health) }"
          />
        </div>

        <!-- Footer -->
        <div class="flex items-center justify-between">
          <span class="text-xs font-semibold" :class="healthColor(s.health)">{{ s.health }}% health</span>
          <span class="text-[10px] px-1.5 py-0.5 rounded-full font-medium" :class="statusBadge(s.status).class">
            {{ statusBadge(s.status).text }}
          </span>
        </div>
      </div>
    </div>

    <!-- Empty -->
    <div v-if="sensorScores.length === 0" class="mac-card p-8 text-center">
      <span class="material-symbols-outlined text-3xl text-slate-600">monitor_heart</span>
      <p class="text-sm text-slate-500 mt-2">No sensor data available</p>
    </div>
  </div>
</template>
