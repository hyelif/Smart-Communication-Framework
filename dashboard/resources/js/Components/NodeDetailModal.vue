<script setup>
import { ref, watch, nextTick, shallowRef, onUnmounted } from 'vue'

const props = defineProps({
  open: { type: Boolean, default: false },
  node: { type: Object, default: null },
})

const emit = defineEmits(['close'])

const readings = shallowRef([])
const nodeInfo = shallowRef(null)
const modalLoading = ref(false)
const modalError = ref(false)
const modalContentRef = ref(null)

// ─── AbortController ───
let fetchController = null

async function fetchNodeSensors() {
  if (!props.node?.hardware_id) return

  if (fetchController) {
    fetchController.abort()
    fetchController = null
  }

  modalLoading.value = true
  modalError.value = false
  try {
    const controller = new AbortController()
    fetchController = controller
    const url = '/api/dashboard/node-sensors?hardware_id=' + encodeURIComponent(props.node.hardware_id)
    const res = await fetch(url, { signal: controller.signal })
    if (res.ok) {
      const json = await res.json()
      readings.value = json.readings || []
      nodeInfo.value = json.node || null
    } else {
      modalError.value = true
    }
  } catch (e) {
    if (e?.name === 'AbortError') return
    modalError.value = true
  } finally {
    fetchController = null
    modalLoading.value = false
  }
}

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
  return `${diffDays}d ago`
}

function formatDateTime(dateStr) {
  if (!dateStr) return '--'
  try {
    const d = new Date(dateStr)
    return d.toLocaleDateString([], {
      month: 'short', day: 'numeric', year: 'numeric',
      hour: '2-digit', minute: '2-digit',
    })
  } catch {
    return dateStr
  }
}

function toNum(v) {
  const n = parseFloat(v)
  return isNaN(n) ? null : n
}

// ─── Focus trap ───
function handleKeydown(e) {
  if (!props.open) return
  if (e.key === 'Escape') { emit('close'); return }
  if (e.key === 'Tab') {
    const focusable = modalContentRef.value?.querySelectorAll(
      'button, [href], input, select, textarea, [tabindex]:not([tabindex="-1"])'
    )
    if (!focusable || focusable.length === 0) return
    const first = focusable[0]
    const last = focusable[focusable.length - 1]
    if (e.shiftKey) {
      if (document.activeElement === first) { e.preventDefault(); last.focus() }
    } else {
      if (document.activeElement === last) { e.preventDefault(); first.focus() }
    }
  }
}

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

watch(() => props.node, () => {
  if (props.open && props.node?.hardware_id) {
    fetchNodeSensors()
  }
})

onUnmounted(() => {
  if (fetchController) {
    fetchController.abort()
    fetchController = null
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
        :aria-labelledby="`node-modal-title-${node?.hardware_id || 'default'}`"
      >
        <div class="mac-sheet p-5 max-w-2xl w-full max-h-[85vh] overflow-y-auto" ref="modalContentRef">
          <!-- Header -->
          <div class="flex items-center justify-between mb-4">
            <div>
              <h2
                :id="`node-modal-title-${node?.hardware_id || 'default'}`"
                class="text-headline-md font-headline-md text-white"
              >
                {{ nodeInfo?.name || node?.name || 'Node Details' }}
              </h2>
              <p class="text-xs text-slate-500 mt-0.5">
                {{ node?.hardware_id }}
                <span v-if="nodeInfo?.location" class="ml-2"> &middot; {{ nodeInfo.location }}</span>
              </p>
            </div>
            <button
              @click="emit('close')"
              class="text-slate-500 hover:text-white transition-colors active-scale p-1"
              aria-label="Close node details"
            >
              <span class="material-symbols-outlined">close</span>
            </button>
          </div>

          <!-- Loading -->
          <div v-if="modalLoading" class="py-16 flex items-center justify-center">
            <div class="spinner-soft w-6 h-6" role="status" aria-label="Loading sensor data" />
          </div>

          <!-- Error -->
          <div v-else-if="modalError" class="py-16 flex flex-col items-center justify-center gap-3">
            <span class="material-symbols-outlined text-3xl text-red-400">cloud_off</span>
            <span class="text-slate-400 text-sm">Failed to load sensor data</span>
            <button @click="fetchNodeSensors" class="btn btn-primary text-xs">Retry</button>
          </div>

          <!-- Empty -->
          <div v-else-if="readings.length === 0" class="py-16 flex flex-col items-center justify-center gap-3">
            <span class="material-symbols-outlined text-3xl text-slate-600">sensors_off</span>
            <span class="text-slate-500 text-sm">No sensor data recorded for this node</span>
          </div>

          <!-- Data -->
          <template v-else>
            <!-- Node summary -->
            <div class="flex flex-wrap items-center gap-4 mb-5 p-3 rounded-lg bg-slate-800/40 border border-slate-700/30">
              <div class="flex items-center gap-2 text-xs text-slate-400">
                <span class="material-symbols-outlined text-sm">signal_cellular_alt</span>
                RSSI: <span class="text-slate-200 font-mono">{{ readings[0]?.rssi ?? '--' }}</span>
              </div>
              <div class="flex items-center gap-2 text-xs text-slate-400">
                <span class="material-symbols-outlined text-sm">wifi</span>
                SNR: <span class="text-slate-200 font-mono">{{ readings[0]?.snr ?? '--' }}</span>
              </div>
              <div class="flex items-center gap-2 text-xs text-slate-400">
                <span class="material-symbols-outlined text-sm">priority_high</span>
                Mode: <span class="text-slate-200 font-mono">{{ readings[0]?.report_mode ?? '--' }}</span>
              </div>
              <div class="flex items-center gap-2 text-xs text-slate-400 ml-auto">
                <span class="material-symbols-outlined text-sm">schedule</span>
                {{ timeAgo(readings[0]?.created_at) }}
              </div>
            </div>

            <!-- Readings list -->
            <div class="space-y-3 max-h-96 overflow-y-auto custom-scrollbar pr-1">
              <div
                v-for="reading in readings"
                :key="reading.id"
                class="rounded-lg bg-slate-800/20 border border-slate-700/20 p-3"
              >
                <!-- Reading header -->
                <div class="flex items-center justify-between mb-2 pb-2 border-b border-slate-700/20">
                  <span class="text-[10px] font-mono text-slate-500">#{{ reading.id }}</span>
                  <span class="text-[10px] text-slate-500">{{ formatDateTime(reading.created_at) }}</span>
                </div>

                <!-- Sensor values grid -->
                <div
                  v-if="reading.sensors && reading.sensors.length > 0"
                  class="grid grid-cols-2 sm:grid-cols-3 gap-2"
                >
                  <div
                    v-for="sensor in reading.sensors"
                    :key="sensor.key"
                    class="flex items-center gap-2 p-2 rounded bg-slate-900/30"
                  >
                    <span
                      class="w-2 h-2 rounded-full shrink-0"
                      :style="{ backgroundColor: sensor.color || '#64748b' }"
                    />
                    <div class="min-w-0">
                      <p class="text-[10px] text-slate-500 truncate">{{ sensor.label }}</p>
                      <p class="text-xs font-mono text-slate-200 tabular-nums">
                        {{ toNum(sensor.value) != null ? Number(sensor.value).toFixed(1) : '--' }}
                        <span class="text-[10px] text-slate-600">{{ sensor.unit }}</span>
                      </p>
                    </div>
                  </div>
                </div>
                <div v-else class="text-[10px] text-slate-600 italic py-1">
                  No sensor data in this reading
                </div>
              </div>
            </div>
          </template>
        </div>
      </div>
    </Transition>
  </Teleport>
</template>
