<script setup>
import { computed } from 'vue'

const props = defineProps({
  total: { type: Number, default: 0 },
  critical: { type: Number, default: 0 },
  warning: { type: Number, default: 0 },
  variant: {
    type: String,
    default: 'icon',
    validator: (v) => ['icon', 'summary'].includes(v),
  },
})

const displayCount = computed(() => {
  if (props.total > 99) return '99+'
  return String(props.total)
})

const hasAlerts = computed(() => props.total > 0)
const hasCritical = computed(() => props.critical > 0)
</script>

<template>
  <div
    v-if="variant === 'icon'"
    :aria-label="`${total} active alerts, ${critical} critical`"
    role="status"
    aria-live="polite"
    class="relative inline-flex items-center"
  >
    <span class="material-symbols-outlined text-slate-400">notifications</span>
    <span
      v-if="hasAlerts"
      :class="[
        'absolute -top-1.5 -right-1.5 w-4 h-4 rounded-full flex items-center justify-center text-[9px] font-bold',
        hasCritical ? 'bg-red-500 text-white animate-pulse-glow-danger' : 'bg-amber-500 text-white',
      ]"
    >
      {{ displayCount }}
    </span>
  </div>

  <div
    v-else
    :aria-label="`${total} active alerts, ${critical} critical`"
    role="status"
    aria-live="polite"
    class="mac-card p-4"
  >
    <div class="flex items-center gap-2 mb-2">
      <span class="material-symbols-outlined text-sm" :class="hasCritical ? 'text-red-400' : 'text-slate-500'">warning</span>
      <span class="mac-heading">Alerts</span>
    </div>
    <div class="flex items-baseline gap-2">
      <span class="text-xl font-bold text-white">{{ total }}</span>
      <span class="mac-caption">active</span>
    </div>
    <div class="flex gap-3 mt-1">
      <span v-if="critical" class="mac-caption text-red-400">{{ critical }} critical</span>
      <span v-if="warning" class="mac-caption text-amber-400">{{ warning }} warnings</span>
    </div>
  </div>
</template>
