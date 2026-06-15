<script setup>
import { ref, watch, nextTick, shallowRef, onUnmounted } from 'vue'
import TrendChart from '../Pages/Dashboard/TrendChart.vue'

const props = defineProps({
  open: { type: Boolean, default: false },
  sensor: { type: Object, default: null },
  tweenedValue: { type: Number, default: null },
})

const emit = defineEmits(['close'])

const modalRange = ref('24 HOUR')
const showPrediction = ref(true)
const trendData = shallowRef([])
const modalLoading = ref(false)
const modalError = ref(false)
const modalContentRef = ref(null)

const rangeOptions = [
  { value: '1 HOUR', label: '1H' },
  { value: '6 HOUR', label: '6H' },
  { value: '24 HOUR', label: '24H' },
  { value: '7 DAY', label: '7D' },
  { value: '30 DAY', label: '30D' },
]

// ─── AbortController management ───
let trendsController = null
let fetchTrendsTimeout = null

async function fetchTrends() {
  if (!props.sensor) return
  const dbName = {
    temperature: 'Temperature', humidity: 'Humidity', waterTemp: 'WaterTemp',
    ph: 'pH', tds: 'TDS', turbidity: 'Turbidity', rain: 'Rain', relay: 'Relay',
  }[props.sensor.key] || props.sensor.label

  // Cancel previous in-flight request
  if (trendsController) {
    trendsController.abort()
    trendsController = null
  }

  modalLoading.value = true
  modalError.value = false
  try {
    const controller = new AbortController()
    trendsController = controller
    const url = '/api/dashboard/sensor-trends?sensor=' + encodeURIComponent(dbName) + '&range=' + encodeURIComponent(modalRange.value)
    const res = await fetch(url, { signal: controller.signal })
    if (res.ok) {
      const json = await res.json()
      trendData.value = json.data || []
    } else {
      modalError.value = true
    }
  } catch (e) {
    if (e?.name === 'AbortError') return
    console.error('Trend fetch failed:', e)
    modalError.value = true
  } finally {
    if (trendsController) {
      trendsController = null
    }
    modalLoading.value = false
  }
}

// Focus trap
function handleKeydown(e) {
  if (!props.open) return
  if (e.key === 'Escape') {
    emit('close')
    return
  }
  if (e.key === 'Tab') {
    const focusable = modalContentRef.value?.querySelectorAll(
      'button, [href], input, select, textarea, [tabindex]:not([tabindex="-1"])'
    )
    if (!focusable || focusable.length === 0) return
    const first = focusable[0]
    const last = focusable[focusable.length - 1]
    if (e.shiftKey) {
      if (document.activeElement === first) {
        e.preventDefault()
        last.focus()
      }
    } else {
      if (document.activeElement === last) {
        e.preventDefault()
        first.focus()
      }
    }
  }
}

// Focus first element on open
watch(() => props.open, (isOpen) => {
  if (isOpen) {
    document.addEventListener('keydown', handleKeydown)
    nextTick(() => {
      const firstFocusable = modalContentRef.value?.querySelector('button')
      firstFocusable?.focus()
    })
  } else {
    document.removeEventListener('keydown', handleKeydown)
  }
})

// Fetch immediately when sensor changes (user action)
watch(() => props.sensor, () => {
  if (fetchTrendsTimeout) {
    clearTimeout(fetchTrendsTimeout)
    fetchTrendsTimeout = null
  }
  if (props.open && props.sensor) {
    fetchTrends()
  }
})

// Debounce range changes by 300ms
watch(modalRange, () => {
  if (!props.open || !props.sensor) return
  if (fetchTrendsTimeout) clearTimeout(fetchTrendsTimeout)
  fetchTrendsTimeout = setTimeout(() => fetchTrends(), 300)
})

// Cleanup on unmount
onUnmounted(() => {
  if (trendsController) {
    trendsController.abort()
    trendsController = null
  }
  if (fetchTrendsTimeout) {
    clearTimeout(fetchTrendsTimeout)
    fetchTrendsTimeout = null
  }
  document.removeEventListener('keydown', handleKeydown)
})
</script>

<template>
  <Teleport to="body">
    <Transition name="modal">
      <div
        v-if="open"
        class="modal-overlay"
        @click.self="emit('close')"
        role="dialog"
        aria-modal="true"
        :aria-labelledby="`modal-title-${sensor?.key || 'default'}`"
      >
        <div class="mac-sheet p-5 max-w-2xl w-full max-h-[85vh] overflow-y-auto" ref="modalContentRef">
          <!-- Header -->
          <div class="flex items-center justify-between mb-4">
            <div>
              <h2
                :id="`modal-title-${sensor?.key || 'default'}`"
                class="text-headline-md font-headline-md text-white"
              >
                {{ sensor?.label || 'Sensor Details' }}
              </h2>
              <p class="text-xs text-slate-500 mt-0.5">{{ sensor?.key }}</p>
            </div>
            <button
              @click="emit('close')"
              class="text-slate-500 hover:text-white transition-colors active-scale p-1"
              aria-label="Close sensor details"
            >
              <span class="material-symbols-outlined">close</span>
            </button>
          </div>

          <!-- Current value -->
          <div class="flex items-baseline gap-2 mb-4">
            <span class="text-hero-metric font-hero-metric text-white tween-value">
              {{ tweenedValue != null ? tweenedValue.toFixed(1) : (sensor?.displayValue ?? '--') }}
            </span>
            <span class="text-sm text-slate-500">{{ sensor?.unit || '' }}</span>
          </div>

          <!-- Range selector + Prediction toggle -->
          <div class="flex items-center justify-between mb-4">
            <div class="flex gap-1" role="tablist" aria-label="Time range">
              <button
                v-for="opt in rangeOptions"
                :key="opt.value"
                @click="modalRange = opt.value"
                :class="[
                  'text-xs px-2 py-1 rounded-md transition-colors',
                  modalRange === opt.value
                    ? 'bg-cyan-400/10 text-cyan-400'
                    : 'text-slate-500 hover:text-slate-300',
                ]"
                role="tab"
                :aria-selected="modalRange === opt.value"
              >
                {{ opt.label }}
              </button>
            </div>
            <button
              @click="showPrediction = !showPrediction"
              :class="[
                'text-xs px-2 py-1 rounded-md transition-colors flex items-center gap-1',
                showPrediction
                  ? 'bg-cyan-400/10 text-cyan-400'
                  : 'text-slate-500 hover:text-slate-300',
              ]"
              aria-label="Toggle prediction"
            >
              <span class="material-symbols-outlined text-[10px]">trending_up</span>
              Predict
            </button>
          </div>

          <!-- Chart area -->
          <div v-if="modalLoading" class="h-64 flex items-center justify-center">
            <div class="spinner-soft w-6 h-6" role="status" aria-label="Loading trend data" />
          </div>
          <div v-else-if="modalError" class="h-64 flex flex-col items-center justify-center gap-2">
            <span class="text-slate-500 text-sm">Failed to load trend data</span>
            <button @click="fetchTrends" class="btn btn-primary text-xs">Retry</button>
          </div>
          <TrendChart
          v-else
          :data="trendData"
          :profile="sensor || {}"
          :color="sensor?.key === 'temperature' ? '#f97316' : '#22d3ee'"
          :show-prediction="showPrediction"
        />
        </div>
      </div>
    </Transition>
  </Teleport>
</template>
