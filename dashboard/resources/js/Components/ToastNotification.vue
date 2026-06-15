<script setup>
import { useToast } from '../Composables/useToast'

const { toasts, removeToast } = useToast()
</script>

<template>
  <Teleport to="body">
    <div class="toast-container" role="status" aria-live="polite" aria-label="Notifications">
      <div
        v-for="t in toasts"
        :key="t.id"
        :class="['toast', `toast-${t.type}`, { visible: t.visible }]"
      >
        <span
          class="material-symbols-outlined toast-icon"
          :class="t.type === 'success' ? 'text-emerald-400' : t.type === 'error' ? 'text-red-400' : 'text-cyan-400'"
        >
          {{ t.type === 'success' ? 'check_circle' : t.type === 'error' ? 'error' : 'info' }}
        </span>
        <span class="flex-1">{{ t.message }}</span>
        <button class="toast-close material-symbols-outlined text-sm" @click="removeToast(t.id)" aria-label="Dismiss">close</button>
      </div>
    </div>
  </Teleport>
</template>
