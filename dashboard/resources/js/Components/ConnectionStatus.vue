<script setup>
import { computed } from 'vue'

const props = defineProps({
  variant: {
    type: String,
    default: 'full',
    validator: (v) => ['full', 'mini', 'dot'].includes(v),
  },
  freshnessMinutes: { type: Number, default: null },
  rssi: { type: Number, default: null },
  snr: { type: Number, default: null },
  isStale: { type: Boolean, default: false },
  isFresh: { type: Boolean, default: false },
})

const status = computed(() => {
  const m = props.freshnessMinutes
  if (m === null) return { label: 'Unknown', dotClass: 'text-slate-400', pulseClass: '', ariaLabel: 'Connection: Unknown' }
  if (m <= 1) return { label: 'Connected', dotClass: 'text-emerald-400', pulseClass: 'animate-pulse-glow', ariaLabel: 'Connection: Connected' }
  if (m <= 5) return { label: 'Recent', dotClass: 'text-cyan-400', pulseClass: '', ariaLabel: 'Connection: Recent' }
  if (m <= 15) return { label: 'Stale', dotClass: 'text-amber-400', pulseClass: 'animate-pulse-glow-amber', ariaLabel: 'Connection: Stale' }
  return { label: 'Lost', dotClass: 'text-red-400', pulseClass: 'animate-pulse-glow-danger', ariaLabel: 'Connection: Lost' }
})
</script>

<template>
  <div
    role="status"
    :aria-live="status.label === 'Lost' ? 'assertive' : 'polite'"
    :aria-label="status.ariaLabel"
    class="mac-status"
  >
    <span
      :class="['mac-status-dot', status.dotClass, status.pulseClass]"
    />
    <span v-if="variant !== 'dot'" class="mac-caption" :class="status.dotClass">
      {{ status.label }}
    </span>
  </div>
</template>
