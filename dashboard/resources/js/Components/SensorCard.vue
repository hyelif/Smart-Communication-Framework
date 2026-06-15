<script setup>
import { computed, ref, watch } from 'vue'

const props = defineProps({
  sensor: { type: Object, required: true },
  tweenedValue: { type: Number, default: null },
  visible: { type: Boolean, default: false },
  index: { type: Number, default: 0 },
})

const emit = defineEmits(['click'])

const sensorType = computed(() => {
  const label = (props.sensor.label || '').toLowerCase()
  if (label.includes('temp') || label.includes('suhu')) return 'temperature'
  if (label.includes('ph')) return 'ph'
  if (label.includes('tds') || label.includes('ec') || label.includes('ppm')) return 'tds'
  if (label.includes('humidity') || label.includes('kelembaban') || label.includes('humi')) return 'humidity'
  return 'default'
})

const typeColors = computed(() => {
  const map = {
    temperature: { accent: '#f97316', text: '#fb923c' },
    humidity:    { accent: '#22d3ee', text: '#22d3ee' },
    ph:          { accent: '#a78bfa', text: '#c4b5fd' },
    tds:         { accent: '#34d399', text: '#6ee7b7' },
    default:     { accent: '#64748b', text: '#94a3b8' },
  }
  return map[sensorType.value] || map.default
})

const sensorStyle = computed(() => ({
  '--sensor-accent': typeColors.value.accent,
  '--sensor-text': typeColors.value.text,
  '--stagger-delay': `${props.index * 0.08}s`,
}))

const displayValue = computed(() => {
  if (props.tweenedValue !== null) return props.tweenedValue.toFixed(1)
  if (props.sensor.key === 'rain') {
    const v = props.sensor.displayValue
    if (v === '1' || v === 1 || v === '1.0') return 'Sunny'
    if (v === '0' || v === 0 || v === '0.0') return 'Raining'
  }
  return props.sensor.displayValue ?? '--'
})

const trend = ref(null)
watch(() => props.tweenedValue, (newVal, oldVal) => {
  if (oldVal !== null && newVal !== null && newVal !== oldVal) {
    trend.value = newVal > oldVal ? 'up' : 'down'
  }
})

const valueFlash = ref(null)
watch(() => props.tweenedValue, (newVal, oldVal) => {
  if (oldVal !== null && newVal !== null && newVal !== oldVal) {
    valueFlash.value = newVal > oldVal ? 'increase' : 'decrease'
    setTimeout(() => { valueFlash.value = null }, 700)
  }
})

const badge = computed(() => {
  const s = props.sensor
  if (s.isHardwareError) return { text: 'CHECK WIRING', class: 'mac-badge bg-red-500/15 text-red-400' }
  if (s.isNull) return { text: 'OFFLINE', class: 'mac-badge bg-slate-500/15 text-slate-400' }
  if (s.status === 'low') return { text: 'Low', class: 'mac-badge bg-amber-500/15 text-amber-400' }
  if (s.status === 'high') return { text: 'High', class: 'mac-badge bg-red-500/15 text-red-400' }
  return { text: 'Normal', class: 'mac-badge bg-emerald-500/15 text-emerald-400' }
})

const cardState = computed(() => {
  const s = props.sensor
  if (s.isHardwareError) return 'error'
  if (s.status === 'high') return 'alert'
  if (s.status === 'low') return 'warning'
  return 'normal'
})

const sparklineBars = computed(() => {
  const key = props.sensor.key || 'default'
  let hash = 0
  for (let i = 0; i < key.length; i++) {
    hash = ((hash << 5) - hash) + key.charCodeAt(i)
  }
  const bars = []
  for (let i = 0; i < 5; i++) {
    const val = Math.abs(Math.sin(hash * (i + 1) * 7.3)) * 0.5 + 0.3
    bars.push(val)
  }
  return bars
})

const ariaLabel = computed(() => {
  const s = props.sensor
  return `${s.label}: ${displayValue.value} ${s.unit || ''}, status ${badge.value.text}`
})

const rippleContainer = ref(null)

function handleClick(event) {
  emit('click')
  createRipple(event)
}

function createRipple(event) {
  const container = rippleContainer.value
  if (!container) return
  const rect = container.getBoundingClientRect()
  const ripple = document.createElement('span')
  ripple.className = 'sensor-ripple'
  const size = Math.max(rect.width, rect.height) * 1.2
  const clientX = event.clientX ?? (rect.left + rect.width / 2)
  const clientY = event.clientY ?? (rect.top + rect.height / 2)
  ripple.style.width = `${size}px`
  ripple.style.height = `${size}px`
  ripple.style.left = `${clientX - rect.left - size / 2}px`
  ripple.style.top = `${clientY - rect.top - size / 2}px`
  container.appendChild(ripple)
  ripple.addEventListener('animationend', () => ripple.remove())
}
</script>

<template>
  <div
    :class="['mac-card p-4', `sensor-${cardState}`, 'stagger-enter', 'cursor-pointer mac-hover-lift', { visible, 'sensor-offline': sensor.isNull || sensor.isHardwareError }]"
    :style="sensorStyle"
    role="button"
    tabindex="0"
    :aria-label="ariaLabel"
    @click="handleClick"
    @keydown.enter="emit('click')"
    @keydown.space.prevent="emit('click')"
  >
    <div v-if="sensor.isNull || sensor.isHardwareError" class="sensor-ghost-pattern" />

    <template v-if="sensor.loading">
      <div class="skeleton-text w-24 mb-3" />
      <div class="skeleton-metric mb-3" />
      <div class="skeleton-badge" />
    </template>

    <template v-else>
      <div class="flex items-center justify-between mb-2 relative z-10">
        <div class="flex items-center gap-2">
          <span class="mac-status-dot" :class="badge.class.includes('emerald') ? 'text-emerald-400' : badge.class.includes('red') ? 'text-red-400' : badge.class.includes('amber') ? 'text-amber-400' : 'text-slate-400'" />
          <span class="text-sm font-medium text-slate-300">{{ sensor.label }}</span>
        </div>
        <span :class="badge.class">{{ badge.text }}</span>
      </div>

      <div class="flex items-baseline gap-1.5 mb-1 relative z-10">
        <span
          class="sensor-value-text"
          :class="{ 'flash-increase': valueFlash === 'increase', 'flash-decrease': valueFlash === 'decrease' }"
          aria-live="polite"
        >{{ displayValue }}</span>
        <span v-if="sensor.unit && sensor.key !== 'rain'" class="mac-caption">{{ sensor.unit }}</span>
        <span v-if="trend" class="sensor-trend" :class="`trend-${trend}`" aria-hidden="true">{{ trend === 'up' ? '▴' : '▾' }}</span>
      </div>

      <div class="mac-caption relative z-10">Pin {{ sensor.pin }}</div>

      <div v-if="!sensor.isNull && !sensor.isHardwareError" class="sensor-sparkline relative z-10" aria-hidden="true">
        <div
          v-for="(bar, i) in sparklineBars" :key="i"
          class="sensor-sparkline-bar"
          :style="{ height: (bar * 14) + 'px', background: `linear-gradient(180deg, ${typeColors.accent} 0%, ${typeColors.accent}33 100%)` }"
        />
      </div>

      <div class="sensor-click-hint">
        <span class="material-symbols-outlined text-[10px]">touch_app</span>
        Click to view graph
      </div>
    </template>

    <div class="sensor-ripple-container" ref="rippleContainer" />
  </div>
</template>
