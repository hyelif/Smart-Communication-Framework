<script setup>
import { computed } from 'vue'
import { useSensorHistory } from '../Composables/useSensorHistory'

const props = defineProps({
  sensors: { type: Array, default: () => [] },
  profiles: { type: Object, default: () => ({}) },
  minutesSince: { type: Number, default: null },
})

const { computeAnomalyScore, computeHealthScore, computeTrend } = useSensorHistory()

const sensorScores = computed(() => {
  return props.sensors.map(s => {
    const val = parseFloat(s.value)
    const profile = props.profiles[s.key] || {}
    const anomaly = isNaN(val) ? 0 : computeAnomalyScore(s.key, val, profile, props.minutesSince)
    const health = computeHealthScore(anomaly)
    const trend = isNaN(val) ? 'stable' : computeTrend(s.key, profile)
    return { key: s.key, label: s.label || s.key, value: val, unit: s.unit || '', health, anomaly, trend, color: profile.color || '#64748b' }
  })
})

const systemHealth = computed(() => {
  const scores = sensorScores.value
  if (scores.length === 0) return { health: 100, trend: 'stable', atRisk: 0 }
  const avg = scores.reduce((a, s) => a + s.health, 0) / scores.length
  const atRisk = scores.filter(s => s.health < 70).length

  // Overall trend: if most sensors are declining, system is declining
  const declining = scores.filter(s => s.trend === 'declining').length
  const improving = scores.filter(s => s.trend === 'improving').length
  let trend = 'stable'
  if (declining > improving && declining >= scores.length / 3) trend = 'declining'
  else if (improving > declining && improving >= scores.length / 3) trend = 'improving'

  return { health: Math.round(avg), trend, atRisk, total: scores.length }
})

function healthColor(health) {
  if (health >= 80) return 'text-emerald-400'
  if (health >= 60) return 'text-amber-400'
  return 'text-red-400'
}

function healthBg(health) {
  if (health >= 80) return 'bg-emerald-500/10'
  if (health >= 60) return 'bg-amber-500/10'
  return 'bg-red-500/10'
}

function trendIcon(trend) {
  if (trend === 'improving') return 'trending_up'
  if (trend === 'declining') return 'trending_down'
  return 'trending_flat'
}

function trendColor(trend) {
  if (trend === 'improving') return 'text-emerald-400'
  if (trend === 'declining') return 'text-red-400'
  return 'text-slate-500'
}

function barWidth(health) {
  return Math.max(4, health) + '%'
}
</script>

<template>
  <div class="mac-card p-4">
    <!-- Header -->
    <div class="flex items-center justify-between mb-3">
      <div class="flex items-center gap-2">
        <span class="material-symbols-outlined text-sm text-cyan-400">monitor_heart</span>
        <span class="text-sm font-semibold text-slate-300">System Health</span>
      </div>
      <div v-if="systemHealth.atRisk > 0" class="flex items-center gap-1 text-[10px] text-amber-400">
        <span class="material-symbols-outlined text-[12px]">warning</span>
        <span>{{ systemHealth.atRisk }} at risk</span>
      </div>
    </div>

    <!-- Overall health ring -->
    <div class="flex items-center gap-4 mb-4">
      <div class="relative w-16 h-16 flex items-center justify-center">
        <svg class="w-16 h-16 -rotate-90" viewBox="0 0 64 64">
          <circle cx="32" cy="32" r="28" fill="none" stroke="rgba(255,255,255,0.04)" stroke-width="4" />
          <circle
            cx="32" cy="32" r="28" fill="none"
            :stroke="systemHealth.health >= 80 ? '#34d399' : systemHealth.health >= 60 ? '#f59e0b' : '#ef4444'"
            stroke-width="4"
            stroke-linecap="round"
            :stroke-dasharray="2 * Math.PI * 28"
            :stroke-dashoffset="2 * Math.PI * 28 * (1 - systemHealth.health / 100)"
            class="transition-all duration-700"
          />
        </svg>
        <span class="absolute text-lg font-bold" :class="healthColor(systemHealth.health)">{{ systemHealth.health }}%</span>
      </div>
      <div>
        <div class="flex items-center gap-1.5 text-xs">
          <span class="material-symbols-outlined text-sm" :class="trendColor(systemHealth.trend)">{{ trendIcon(systemHealth.trend) }}</span>
          <span :class="trendColor(systemHealth.trend)" class="font-medium capitalize">{{ systemHealth.trend }}</span>
        </div>
        <p class="text-[10px] text-slate-600 mt-0.5">{{ systemHealth.total }} sensors monitored</p>
      </div>
    </div>

    <!-- Per-sensor health bars -->
    <div class="space-y-2">
      <div v-for="s in sensorScores" :key="s.key" class="flex items-center gap-2">
        <span class="w-1.5 h-1.5 rounded-full" :class="healthColor(s.health)" />
        <span class="text-[11px] text-slate-400 w-20 truncate">{{ s.label }}</span>
        <div class="flex-1 h-1.5 rounded-full bg-white/5 overflow-hidden">
          <div
            class="h-full rounded-full transition-all duration-500"
            :style="{ width: barWidth(s.health), background: s.health >= 80 ? '#34d399' : s.health >= 60 ? '#f59e0b' : '#ef4444' }"
          />
        </div>
        <span class="text-[10px] font-mono w-8 text-right" :class="healthColor(s.health)">{{ s.health }}%</span>
        <span class="material-symbols-outlined text-[10px]" :class="trendColor(s.trend)">{{ trendIcon(s.trend) }}</span>
      </div>
    </div>

    <!-- Empty state -->
    <div v-if="sensorScores.length === 0" class="text-center py-4">
      <span class="text-xs text-slate-500">No sensor data available</span>
    </div>
  </div>
</template>
