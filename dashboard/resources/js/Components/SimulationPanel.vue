<script setup>
import { computed, reactive, watch } from 'vue'

const props = defineProps({
  profiles: { type: Object, default: () => ({}) },
  currentValues: { type: Object, default: () => ({}) },
})

// Slider range config per sensor key
const sliderConfig = {
  temperature: { min: 0, max: 50, step: 0.5 },
  humidity: { min: 0, max: 100, step: 1 },
  watertemp: { min: 0, max: 50, step: 0.5 },
  ph: { min: 0, max: 14, step: 0.1 },
  tds: { min: 0, max: 2000, step: 10 },
  turbidity: { min: 0, max: 2000, step: 10 },
  rain: { min: 0, max: 1, step: 1 },
}

// Sensor display order
const sensorKeys = ['temperature', 'humidity', 'watertemp', 'ph', 'tds', 'turbidity', 'rain']

// Initialize simulated values from current values
const simulated = reactive({})

watch(() => props.currentValues, (vals) => {
  for (const key of sensorKeys) {
    if (simulated[key] === undefined && vals[key] !== undefined) {
      simulated[key] = vals[key]
    }
  }
}, { immediate: true })

function getStatus(key, value) {
  const profile = props.profiles[key]
  if (!profile) return 'normal'
  const tMin = profile.t_min
  const tMax = profile.t_max
  if (tMin !== null && value < tMin) return 'low'
  if (tMax !== null && value > tMax) return 'high'
  return 'normal'
}

const simulatedStatuses = computed(() => {
  const result = {}
  for (const key of sensorKeys) {
    const val = simulated[key]
    if (val !== undefined) {
      result[key] = getStatus(key, val)
    }
  }
  return result
})

const currentStatuses = computed(() => {
  const result = {}
  for (const key of sensorKeys) {
    const val = props.currentValues[key]
    if (val !== undefined) {
      result[key] = getStatus(key, val)
    }
  }
  return result
})

const alertCount = computed(() => {
  let count = 0
  for (const status of Object.values(simulatedStatuses.value)) {
    if (status === 'low' || status === 'high') count++
  }
  return count
})

const hasChanges = computed(() => {
  for (const key of sensorKeys) {
    const sim = simulated[key]
    const cur = props.currentValues[key]
    if (sim !== undefined && cur !== undefined && sim !== cur) return true
  }
  return false
})

function statusColor(status) {
  if (status === 'normal') return 'text-emerald-400'
  if (status === 'low') return 'text-amber-400'
  if (status === 'high') return 'text-red-400'
  return 'text-slate-500'
}

function statusDot(status) {
  if (status === 'normal') return 'bg-emerald-400'
  if (status === 'low') return 'bg-amber-400'
  if (status === 'high') return 'bg-red-400'
  return 'bg-slate-400'
}

function formatVal(v) {
  if (v === undefined || v === null) return '--'
  if (Number.isInteger(v)) return v.toString()
  return v.toFixed(1)
}

function profileLabel(key) {
  return props.profiles[key]?.label || key.charAt(0).toUpperCase() + key.slice(1)
}

function profileUnit(key) {
  return props.profiles[key]?.unit || ''
}

function profileColor(key) {
  return props.profiles[key]?.color || '#22d3ee'
}
</script>

<template>
  <div>
    <!-- Header -->
    <div class="flex items-center justify-between mb-5">
      <div>
        <h1 class="mac-title">What-If Simulator</h1>
        <p class="mac-caption mt-0.5">Adjust sliders to simulate sensor changes and see predicted effects</p>
      </div>
    </div>

    <!-- Slider Cards -->
    <div class="space-y-3 mb-6">
      <div
        v-for="key in sensorKeys"
        :key="key"
        class="mac-card p-4"
      >
        <div class="flex items-center justify-between mb-2">
          <div class="flex items-center gap-2">
            <span class="w-2 h-2 rounded-full" :class="statusDot(simulatedStatuses[key] || 'normal')" />
            <span class="text-sm font-medium text-slate-300">{{ profileLabel(key) }}</span>
          </div>
          <div class="flex items-center gap-3 text-xs">
            <span class="text-slate-500">Current: <span class="text-slate-300 font-medium">{{ formatVal(currentValues[key]) }}{{ profileUnit(key) }}</span></span>
            <span class="text-slate-600">→</span>
            <span class="font-semibold" :class="statusColor(simulatedStatuses[key] || 'normal')">
              {{ formatVal(simulated[key]) }}{{ profileUnit(key) }}
            </span>
          </div>
        </div>

        <!-- Custom slider -->
        <div class="relative">
          <input
            v-if="sliderConfig[key]"
            v-model.number="simulated[key]"
            type="range"
            :min="sliderConfig[key].min"
            :max="sliderConfig[key].max"
            :step="sliderConfig[key].step"
            class="sim-slider"
            :style="{
              background: `linear-gradient(90deg, ${profileColor(key)} 0%, ${profileColor(key)}33 100%)`
            }"
          />
        </div>

        <!-- Status badges -->
        <div class="flex items-center justify-between mt-2 text-[10px]">
          <span class="text-slate-600">{{ sliderConfig[key]?.min }}</span>
          <div class="flex items-center gap-2">
            <span
              v-if="currentStatuses[key]"
              class="inline-flex items-center gap-1 px-1.5 py-0.5 rounded"
              :class="currentStatuses[key] === 'normal' ? 'bg-emerald-500/10 text-emerald-400' : currentStatuses[key] === 'low' ? 'bg-amber-500/10 text-amber-400' : 'bg-red-500/10 text-red-400'"
            >
              <span class="w-1.5 h-1.5 rounded-full" :class="statusDot(currentStatuses[key])" />
              Current: {{ currentStatuses[key] }}
            </span>
            <span
              v-if="simulatedStatuses[key] && simulated[key] !== currentValues[key]"
              class="inline-flex items-center gap-1 px-1.5 py-0.5 rounded"
              :class="simulatedStatuses[key] === 'normal' ? 'bg-emerald-500/10 text-emerald-400' : simulatedStatuses[key] === 'low' ? 'bg-amber-500/10 text-amber-400' : 'bg-red-500/10 text-red-400'"
            >
              <span class="w-1.5 h-1.5 rounded-full" :class="statusDot(simulatedStatuses[key])" />
              Simulated: {{ simulatedStatuses[key] }}
            </span>
          </div>
          <span class="text-slate-600">{{ sliderConfig[key]?.max }}</span>
        </div>
      </div>
    </div>

    <!-- Comparison Summary -->
    <div class="mac-card p-4" v-if="hasChanges">
      <h3 class="text-sm font-semibold text-slate-300 mb-3">Simulation Summary</h3>
      <div class="space-y-2">
        <div
          v-for="key in sensorKeys"
          :key="key"
          v-show="simulated[key] !== currentValues[key]"
          class="flex items-center justify-between text-xs py-1.5 px-2 rounded-lg"
          :class="simulatedStatuses[key] !== 'normal' ? 'bg-red-500/5' : 'bg-emerald-500/5'"
        >
          <span class="text-slate-400">{{ profileLabel(key) }}</span>
          <div class="flex items-center gap-2">
            <span class="text-slate-500">{{ formatVal(currentValues[key]) }}{{ profileUnit(key) }}</span>
            <span class="text-slate-600 material-symbols-outlined text-[12px]">arrow_forward</span>
            <span class="font-semibold" :class="statusColor(simulatedStatuses[key] || 'normal')">
              {{ formatVal(simulated[key]) }}{{ profileUnit(key) }}
            </span>
            <span
              class="px-1.5 py-0.5 rounded text-[9px] font-semibold uppercase"
              :class="simulatedStatuses[key] === 'normal' ? 'bg-emerald-500/10 text-emerald-400' : simulatedStatuses[key] === 'low' ? 'bg-amber-500/10 text-amber-400' : 'bg-red-500/10 text-red-400'"
            >
              {{ simulatedStatuses[key] }}
            </span>
          </div>
        </div>
      </div>

      <!-- Alert simulation -->
      <div v-if="alertCount > 0" class="mt-3 pt-3 border-t border-white/5">
        <div class="flex items-center gap-2 text-xs">
          <span class="material-symbols-outlined text-sm text-red-400">warning</span>
          <span class="text-red-400 font-semibold">Would trigger {{ alertCount }} alert{{ alertCount > 1 ? 's' : '' }}</span>
        </div>
      </div>
      <div v-else class="mt-3 pt-3 border-t border-white/5">
        <div class="flex items-center gap-2 text-xs">
          <span class="material-symbols-outlined text-sm text-emerald-400">check_circle</span>
          <span class="text-emerald-400 font-semibold">No alerts triggered — all values within normal range</span>
        </div>
      </div>
    </div>

    <!-- No changes message -->
    <div v-if="!hasChanges && Object.keys(currentValues).length > 0" class="mac-card p-4 text-center">
      <span class="material-symbols-outlined text-2xl text-slate-600">tune</span>
      <p class="text-sm text-slate-500 mt-2">Adjust any slider above to see simulation results</p>
    </div>
  </div>
</template>
