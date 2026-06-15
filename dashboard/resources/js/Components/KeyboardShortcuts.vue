<script setup>
const shortcuts = [
  { key: '1-5', desc: 'Switch tabs' },
  { key: 'R', desc: 'Refresh data' },
  { key: '?', desc: 'Toggle shortcuts' },
  { key: 'Esc', desc: 'Close modals' },
  { key: 'Ctrl+B', desc: 'Toggle sidebar' },
  { key: '← →', desc: 'Navigate tabs' },
]

defineProps({
  open: { type: Boolean, default: false },
})

const emit = defineEmits(['close'])
</script>

<template>
  <Teleport to="body">
    <Transition name="fade">
      <div v-if="open" class="shortcuts-overlay" @click.self="emit('close')">
        <div class="shortcuts-panel mac-entrance">
          <div class="flex items-center justify-between mb-4">
            <h2 class="shortcuts-title">Keyboard Shortcuts</h2>
            <button class="text-slate-500 hover:text-white transition-colors material-symbols-outlined" @click="emit('close')" aria-label="Close shortcuts">close</button>
          </div>
          <div class="shortcuts-grid">
            <div v-for="s in shortcuts" :key="s.key" class="shortcut-row">
              <span class="shortcut-key">{{ s.key }}</span>
              <span class="shortcut-desc">{{ s.desc }}</span>
            </div>
          </div>
          <p class="text-[10px] text-slate-600 mt-4 text-center">Press <kbd class="shortcut-key">?</kbd> to toggle</p>
        </div>
      </div>
    </Transition>
  </Teleport>
</template>
