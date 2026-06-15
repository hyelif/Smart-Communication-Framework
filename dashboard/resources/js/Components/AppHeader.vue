<script setup>
import ConnectionStatus from './ConnectionStatus.vue'
import AlertBadge from './AlertBadge.vue'

defineProps({
  title: { type: String, default: 'Dashboard' },
  lastUpdated: { type: String, default: null },
  connectionStatus: { type: String, default: 'disconnected' },
  alertCount: { type: Number, default: 0 },
  freshnessMinutes: { type: Number, default: null },
})

const emit = defineEmits(['toggle-sidebar'])
</script>

<template>
  <header class="mac-toolbar h-11 flex items-center justify-between px-4 flex-shrink-0">
    <!-- Left: hamburger (mobile) + traffic lights + app name + page -->
    <div class="flex items-center gap-2 min-w-0">
      <button
        @click="emit('toggle-sidebar')"
        class="md:hidden text-slate-400 hover:text-white transition-colors p-1 -ml-1"
        aria-label="Toggle navigation menu"
      >
        <span class="material-symbols-outlined">menu</span>
      </button>
      <span class="text-xs font-semibold text-slate-500 hidden sm:inline">SmartPonic</span>
      <span class="text-xs text-slate-700 hidden sm:inline">▸</span>
      <h1 class="text-sm font-semibold text-slate-200 truncate max-w-[200px]">{{ title }}</h1>
    </div>

    <!-- Right: status, alerts, user -->
    <div class="flex items-center gap-3 md:gap-4 flex-shrink-0">
      <ConnectionStatus variant="mini" :freshness-minutes="freshnessMinutes" />
      <AlertBadge :total="alertCount" :critical="0" :warning="0" variant="icon" />
      <div
        class="w-7 h-7 rounded-full bg-gradient-to-br from-cyan-400 to-purple-500 flex items-center justify-center text-[10px] font-bold text-white cursor-default shadow-sm"
        aria-label="User menu"
        role="button"
        tabindex="0"
      >
        SP
      </div>
    </div>
  </header>
</template>
