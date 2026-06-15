<script setup>
import { ref, computed } from 'vue'

const props = defineProps({
  sensors: {
    type: Array,
    default: () => [],
  },
})

const RANGES = ['1 HOUR', '6 HOUR', '24 HOUR', '7 DAY', '30 DAY']
const summaryRange = ref('6 HOUR')
const summaryLoading = ref(false)
const csvLoading = ref(false)

const hasSensors = computed(() => props.sensors.length > 0)

async function downloadSummary() {
  summaryLoading.value = true
  try {
    const url = `/api/dashboard/export-summary?range=${encodeURIComponent(summaryRange.value)}`
    const res = await fetch(url)
    if (!res.ok) throw new Error(`HTTP ${res.status}`)
    const blob = await res.blob()
    const disposition = res.headers.get('Content-Disposition') || ''
    const match = disposition.match(/filename="?(.+?)"?$/)
    const filename = match ? match[1] : `smartponic_analytics_${summaryRange.value.toLowerCase().replace(' ', '_')}.xlsx`
    const urlObj = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = urlObj
    a.download = filename
    document.body.appendChild(a)
    a.click()
    document.body.removeChild(a)
    URL.revokeObjectURL(urlObj)
  } catch (e) {
    console.error('Summary download failed:', e)
  } finally {
    summaryLoading.value = false
  }
}

function downloadCsv() {
  csvLoading.value = true
  try {
    const rows = [['Sensor', 'Pin', 'Value', 'Unit', 'Status']]
    for (const s of props.sensors) {
      const numVal = parseFloat(s.value)
      const displayValue = !isNaN(numVal) ? numVal.toFixed(1) : s.value
      rows.push([s.label, String(s.pin), displayValue, s.unit, s.status])
    }
    const csv = rows.map(r => r.join(',')).join('\n')
    const blob = new Blob([csv], { type: 'text/csv' })
    const a = document.createElement('a')
    a.href = URL.createObjectURL(blob)
    a.download = 'smartponic_' + new Date().toISOString().slice(0, 10) + '.csv'
    a.click()
  } catch (e) {
    console.error('CSV download failed:', e)
  } finally {
    csvLoading.value = false
  }
}
</script>

<template>
  <div class="flex flex-col gap-3">
    <!-- Summary Excel with range selector -->
    <div class="flex items-center gap-2">
      <select
        v-model="summaryRange"
        class="bg-slate-800 border border-slate-600 rounded-lg px-3 py-2 text-xs text-slate-200 focus:outline-none focus:border-cyan-500"
      >
        <option v-for="r in RANGES" :key="r" :value="r">{{ r }}</option>
      </select>
      <button
        @click="downloadSummary"
        :disabled="summaryLoading"
        class="flex items-center gap-1.5 px-4 py-2 rounded-lg text-xs font-medium transition-colors"
        :class="summaryLoading
          ? 'bg-slate-700 text-slate-400 cursor-wait'
          : 'bg-emerald-600 hover:bg-emerald-500 text-white'"
      >
        <span v-if="summaryLoading" class="material-symbols-outlined text-sm animate-spin">progress_activity</span>
        <span v-else class="material-symbols-outlined text-sm">assignment</span>
        <span>{{ summaryLoading ? 'Generating...' : 'Analytics Excel' }}</span>
      </button>
    </div>
    <!-- CSV -->
    <div class="flex items-center gap-2">
      <button
        @click="downloadCsv"
        :disabled="csvLoading || !hasSensors"
        :title="!hasSensors ? 'No data to export' : ''"
        class="flex items-center gap-1.5 px-4 py-2 rounded-lg text-xs font-medium transition-colors"
        :class="csvLoading || !hasSensors
          ? 'bg-slate-700 text-slate-400 cursor-wait'
          : 'bg-slate-600 hover:bg-slate-500 text-white'"
      >
        <span v-if="csvLoading" class="material-symbols-outlined text-sm animate-spin">progress_activity</span>
        <span v-else class="material-symbols-outlined text-sm">table_rows</span>
        <span>{{ csvLoading ? 'Exporting...' : 'CSV Snapshot' }}</span>
      </button>
    </div>
  </div>
</template>