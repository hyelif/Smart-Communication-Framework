<script setup>
import { ref, onErrorCaptured } from 'vue'

const error = ref(null)
const errorInfo = ref(null)

onErrorCaptured((err, instance, info) => {
  error.value = err
  errorInfo.value = info
  console.error('[ErrorBoundary]', err, info)
  return false
})

function reset() {
  error.value = null
  errorInfo.value = null
}
</script>

<template>
  <div v-if="error" class="min-h-screen bg-[#0f172a] flex items-center justify-center p-8">
    <div class="max-w-lg text-center mac-card p-8">
      <div class="text-4xl mb-4">&#9888;</div>
      <h2 class="text-xl font-bold text-white mb-2">Something went wrong</h2>
      <p class="text-slate-400 text-sm mb-6">{{ error?.message || 'An unexpected error occurred' }}</p>
      <button
        @click="reset"
        class="px-4 py-2 text-sm font-semibold rounded-lg bg-cyan-400 text-slate-900 hover:bg-cyan-300 transition-colors"
      >
        Retry
      </button>
    </div>
  </div>
  <slot v-else />
</template>
