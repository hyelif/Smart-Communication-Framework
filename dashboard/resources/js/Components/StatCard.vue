<script setup>
import { ref, computed, watch, onMounted } from 'vue'

const props = defineProps({
  label: { type: String, required: true },
  value: { type: [String, Number], default: null },
  sublabel: { type: String, default: '' },
  meta: { type: String, default: '' },
  icon: { type: String, default: '' },
  iconClass: { type: String, default: '' },
  trend: {
    type: String,
    default: '',
    validator: (v) => ['', 'up', 'down', 'neutral'].includes(v),
  },
  loading: { type: Boolean, default: false },
  variant: {
    type: String,
    default: 'default',
    validator: (v) => ['default', 'compact', 'highlight'].includes(v),
  },
  delay: { type: Number, default: 0 },
  accentColor: { type: String, default: '' },
})

const isEmpty = computed(
  () => props.value === null || props.value === undefined || props.value === '--',
)

const displayValue = ref('')
const animatedValue = ref(0)
const isNumeric = ref(false)
const decimalPlaces = ref(0)
const prefix = ref('')
const suffix = ref('')

watch(
  () => props.value,
  (newVal) => {
    if (newVal === null || newVal === undefined || newVal === '--') {
      displayValue.value = '--'
      isNumeric.value = false
      return
    }

    const strVal = String(newVal)
    const match = strVal.match(/(-?\d+\.?\d*)/)

    if (!match) {
      displayValue.value = strVal
      isNumeric.value = false
      return
    }

    const numStr = match[1]
    const num = parseFloat(numStr)
    if (isNaN(num)) {
      displayValue.value = strVal
      isNumeric.value = false
      return
    }

    prefix.value = strVal.substring(0, match.index)
    suffix.value = strVal.substring(match.index + numStr.length)

    const parts = numStr.split('.')
    decimalPlaces.value = parts.length > 1 ? parts[1].length : 0

    isNumeric.value = true

    const startValue = animatedValue.value
    const startTime = performance.now()
    const duration = 800

    function step(now) {
      const elapsed = now - startTime
      const progress = Math.min(elapsed / duration, 1)
      const eased = 1 - Math.pow(1 - progress, 3)
      animatedValue.value = startValue + eased * (num - startValue)
      if (progress < 1) {
        requestAnimationFrame(step)
      } else {
        animatedValue.value = num
      }
    }
    requestAnimationFrame(step)
  },
  { immediate: true },
)

const formattedAnimatedValue = computed(() => {
  if (displayValue.value === '--') return '--'
  if (isNumeric.value) {
    return prefix.value + animatedValue.value.toFixed(decimalPlaces.value) + suffix.value
  }
  return displayValue.value
})

const isVisible = ref(false)
onMounted(() => {
  setTimeout(() => { isVisible.value = true }, props.delay)
})

const variantClass = computed(() => ({
  'mac-card': true,
  'p-4': props.variant !== 'compact',
  'p-3': props.variant === 'compact',
}))

const trendClass = computed(() => {
  if (props.trend === 'up') return 'text-emerald-400'
  if (props.trend === 'down') return 'text-red-400'
  return 'text-slate-500'
})

const trendIcon = computed(() => {
  if (props.trend === 'up') return 'trending_up'
  if (props.trend === 'down') return 'trending_down'
  return 'remove'
})

const iconBgClass = computed(() => {
  if (!props.iconClass) return 'bg-cyan-400/10'
  const colorMap = {
    'text-cyan-400': 'bg-cyan-400/10',
    'text-emerald-400': 'bg-emerald-400/10',
    'text-amber-400': 'bg-amber-400/10',
    'text-red-400': 'bg-red-400/10',
    'text-slate-400': 'bg-slate-400/10',
    'text-slate-500': 'bg-slate-500/10',
  }
  return colorMap[props.iconClass] || 'bg-cyan-400/10'
})
</script>

<template>
  <div :class="variantClass">
    <div
      class="relative z-10 transition-all duration-500 ease-out-soft"
      :class="{
        'opacity-0 translate-y-2': !isVisible,
        'opacity-100 translate-y-0': isVisible,
      }"
      :style="{ transitionDelay: delay + 'ms' }"
    >
      <div class="flex items-center gap-2 mb-1.5">
        <div v-if="icon" class="flex items-center justify-center w-7 h-7 rounded-full" :class="iconBgClass">
          <span class="material-symbols-outlined text-sm" :class="iconClass || 'text-slate-500'">{{ icon }}</span>
        </div>
        <span class="mac-heading">{{ label }}</span>
      </div>

      <template v-if="loading">
        <div class="skeleton-metric mb-1" />
        <div class="skeleton-text w-20" />
      </template>

      <template v-else-if="isEmpty">
        <div class="flex items-baseline gap-2">
          <span class="text-xl font-bold text-slate-500">--</span>
          <span v-if="sublabel" class="mac-caption">{{ sublabel }}</span>
        </div>
      </template>

      <template v-else>
        <div class="flex items-baseline gap-2">
          <span class="text-xl font-bold text-white truncate counter-value">{{ formattedAnimatedValue }}</span>
          <span v-if="sublabel" class="mac-caption">{{ sublabel }}</span>
        </div>
        <p v-if="meta" class="mac-caption mt-0.5 truncate" :title="meta">{{ meta }}</p>
        <div v-if="trend" class="flex items-center gap-1 mt-0.5">
          <span class="material-symbols-outlined text-sm" :class="trendClass">{{ trendIcon }}</span>
        </div>
        <slot name="extra" />
      </template>
    </div>
  </div>
</template>
