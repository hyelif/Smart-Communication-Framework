<script setup>
import { ref } from 'vue'

const props = defineProps({
  tabs: { type: Array, default: () => [] },
  active: { type: String, required: true },
})

const emit = defineEmits(['update:active'])
const tabListRef = ref(null)

function handleKeydown(e) {
  const currentIndex = props.tabs.findIndex(t => t.id === props.active)
  if (e.key === 'ArrowRight' || e.key === 'ArrowDown') {
    e.preventDefault()
    const next = (currentIndex + 1) % props.tabs.length
    emit('update:active', props.tabs[next].id)
  } else if (e.key === 'ArrowLeft' || e.key === 'ArrowUp') {
    e.preventDefault()
    const prev = (currentIndex - 1 + props.tabs.length) % props.tabs.length
    emit('update:active', props.tabs[prev].id)
  } else if (e.key === 'Home') {
    e.preventDefault()
    emit('update:active', props.tabs[0].id)
  } else if (e.key === 'End') {
    e.preventDefault()
    emit('update:active', props.tabs[props.tabs.length - 1].id)
  }
}
</script>

<template>
  <div
    v-if="tabs.length > 0"
    ref="tabListRef"
    role="tablist"
    class="mac-segmented mb-6 w-full sm:w-fit overflow-x-auto"
    tabindex="0"
    @keydown="handleKeydown"
    aria-label="Dashboard tabs"
  >
    <button
      v-for="tab in tabs"
      :key="tab.id"
      role="tab"
      :aria-selected="active === tab.id"
      :aria-controls="`panel-${tab.id}`"
      :tabindex="active === tab.id ? '0' : '-1'"
      @click="emit('update:active', tab.id)"
      :class="['mac-segment', { active: active === tab.id }]"
    >
      {{ tab.label }}
    </button>
  </div>
</template>
