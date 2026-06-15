<script setup>
import { ref } from 'vue'
import DownloadBar from './DownloadBar.vue'

const RANGES = ['1 HOUR', '6 HOUR', '24 HOUR', '7 DAY', '30 DAY']
const selectedRange = ref('24 HOUR')
const exporting = ref(false)
const error = ref(null)

async function doExport() {
  exporting.value = true
  error.value = null
  try {
    const url = `/api/dashboard/export?range=${encodeURIComponent(selectedRange.value)}`
    const res = await fetch(url)
    if (!res.ok) {
      const text = await res.text()
      throw new Error(text || `HTTP ${res.status}`)
    }
    const blob = await res.blob()
    const disposition = res.headers.get('Content-Disposition') || ''
    const match = disposition.match(/filename="?(.+?)"?$/)
    const filename = match ? match[1] : `smartponic_export_${selectedRange.value.toLowerCase().replace(' ', '_')}.xlsx`
    const urlObj = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = urlObj
    a.download = filename
    document.body.appendChild(a)
    a.click()
    document.body.removeChild(a)
    URL.revokeObjectURL(urlObj)
  } catch (e) {
    error.value = e.message
    setTimeout(() => { error.value = null }, 5000)
  } finally {
    exporting.value = false
  }
}
</script>

<template>
  <div class="space-y-6">
    <!-- ═══ Data Export Section ═══ -->
    <div class="mac-card p-5">
      <div class="flex items-center gap-3 mb-4">
        <div class="w-10 h-10 rounded-lg bg-cyan-500/12 flex items-center justify-center shrink-0">
          <span class="material-symbols-outlined text-cyan-400">file_download</span>
        </div>
        <div>
          <h3 class="text-sm font-semibold text-white">Excel Export</h3>
          <p class="text-[11px] text-slate-500">Download multi-sheet Excel with per-sensor data &amp; charts</p>
        </div>
      </div>
      <div class="flex items-center gap-2">
        <select
          v-model="selectedRange"
          class="bg-slate-800 border border-slate-600 rounded-lg px-3 py-2 text-xs text-slate-200 focus:outline-none focus:border-cyan-500"
        >
          <option v-for="r in RANGES" :key="r" :value="r">{{ r }}</option>
        </select>
        <button
          @click="doExport"
          :disabled="exporting"
          class="flex items-center gap-1.5 px-4 py-2 rounded-lg text-xs font-medium transition-colors"
          :class="exporting
            ? 'bg-slate-700 text-slate-400 cursor-wait'
            : 'bg-cyan-600 hover:bg-cyan-500 text-white'"
        >
          <span v-if="exporting" class="material-symbols-outlined text-sm animate-spin">progress_activity</span>
          <span v-else class="material-symbols-outlined text-sm">download</span>
          <span>{{ exporting ? 'Exporting...' : 'Export Excel' }}</span>
        </button>
      </div>
      <div
        v-if="error"
        class="mt-2 px-3 py-1.5 rounded bg-red-500/10 border border-red-500/20 text-red-400 text-xs"
      >{{ error }}</div>
    </div>

    <!-- ═══ Original CSV Export ═══ -->
    <div class="mac-card p-5">
      <div class="flex items-center gap-3 mb-4">
        <div class="w-10 h-10 rounded-lg bg-emerald-500/12 flex items-center justify-center shrink-0">
          <span class="material-symbols-outlined text-emerald-400">description</span>
        </div>
        <div>
          <h3 class="text-sm font-semibold text-white">Analytics &amp; CSV Export</h3>
          <p class="text-[11px] text-slate-500">Download range-based analytics Excel or snapshot as CSV</p>
        </div>
      </div>
      <DownloadBar />
    </div>
  </div>
</template>