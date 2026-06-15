<script setup>
import { computed } from 'vue'
import { useTabNavigation } from '../Composables/useTabNavigation'

const props = defineProps({
  currentRoute: { type: String, default: '' },
  alertCount: { type: Number, default: 0 },
})

const { setActiveTab } = useTabNavigation()

const navItems = [
  { id: 'dashboard', label: 'Dashboard', icon: 'dashboard' },
  { id: 'alerts', label: 'Alerts', icon: 'notifications' },
  { id: 'nodes', label: 'Nodes', icon: 'sensors' },
  { id: 'settings', label: 'Settings', icon: 'settings' },
]

const currentBaseRoute = computed(() => {
  const comp = props.currentRoute || ''
  if (comp.includes('Dashboard')) return 'dashboard'
  if (comp.includes('Nodes')) return 'nodes'
  if (comp.includes('Alerts')) return 'alerts'
  if (comp.includes('Settings')) return 'settings'
  return 'dashboard'
})

const tabIdMap = {
  dashboard: 'overview',
  nodes: 'nodes',
  alerts: 'alerts',
  settings: 'settings',
}

function navigate(item) {
  const mapped = tabIdMap[item.id]
  if (mapped) setActiveTab(mapped)
}
</script>

<template>
  <nav
    class="fixed bottom-0 left-0 right-0 h-14 z-40 flex items-center justify-around px-2 bg-surface-container/80 backdrop-blur-2xl border-t border-white/5"
    role="navigation"
    aria-label="Mobile navigation"
  >
    <a
      v-for="item in navItems"
      :key="item.id"
      href="#"
      @click.prevent="navigate(item)"
      class="flex flex-col items-center gap-0.5 py-1 px-3 rounded-lg transition-colors duration-200"
      :class="currentBaseRoute === item.id ? 'text-primary' : 'text-on-surface-variant'"
      :aria-current="currentBaseRoute === item.id ? 'page' : undefined"
    >
      <span class="material-symbols-outlined text-lg">{{ item.icon }}</span>
      <span class="text-[9px] font-medium">{{ item.label }}</span>
    </a>
  </nav>
</template>
