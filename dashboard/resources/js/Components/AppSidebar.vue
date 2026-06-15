<script setup>
import { computed } from 'vue'
import ConnectionStatus from './ConnectionStatus.vue'
import { useTabNavigation } from '../Composables/useTabNavigation'

const props = defineProps({
  collapsed: { type: Boolean, default: false },
  currentRoute: { type: String, default: '' },
  freshnessMinutes: { type: Number, default: null },
})

const emit = defineEmits(['toggle-collapse'])

const { setActiveTab } = useTabNavigation()

const mainNavLinks = [
  { id: 'dashboard', label: 'Dashboard', icon: 'dashboard' },
  { id: 'nodes', label: 'Nodes', icon: 'sensors' },
  { id: 'alerts', label: 'Alerts', icon: 'notifications' },
  { id: 'simulate', label: 'Simulate', icon: 'tune' },
]

const bottomNavLinks = [
  { id: 'health', label: 'Health', icon: 'monitor_heart' },
  { id: 'settings', label: 'Settings', icon: 'settings' },
]

const currentBaseRoute = computed(() => {
  const comp = props.currentRoute || ''
  if (comp.includes('Dashboard')) return 'dashboard'
  if (comp.includes('Nodes')) return 'nodes'
  if (comp.includes('Alerts')) return 'alerts'
  if (comp.includes('Settings')) return 'settings'
  if (comp.includes('Health')) return 'health'
  if (comp.includes('Simulate')) return 'simulate'
  return 'dashboard'
})

const tabIdMap = {
  dashboard: 'overview',
  nodes: 'nodes',
  alerts: 'alerts',
  settings: 'settings',
  health: 'health',
  simulate: 'simulate',
}

function navigate(link) {
  const mapped = tabIdMap[link.id]
  if (mapped) setActiveTab(mapped)
}
</script>

<template>
  <aside
    role="navigation"
    aria-label="Main navigation"
    :class="[
      'mac-panel flex flex-col transition-all duration-300 ease-in-out-smooth overflow-hidden',
      collapsed ? 'w-16' : 'w-56',
    ]"
  >
    <!-- macOS Traffic Light Dots + Brand -->
    <div class="flex items-center h-11 px-4 mt-2 flex-shrink-0">
      <div class="mac-dots">
        <span class="mac-dot mac-dot-red" />
        <span class="mac-dot mac-dot-yellow" />
        <span class="mac-dot mac-dot-green" />
      </div>
      <div v-show="!collapsed" class="flex items-center gap-2 ml-4">
        <span class="material-symbols-outlined text-primary text-lg flex-shrink-0">eco</span>
        <span class="text-sm font-bold gradient-text whitespace-nowrap">smartponic</span>
      </div>
    </div>

    <!-- Divider -->
    <div class="mx-4 my-2 h-px bg-white/5" />

    <!-- Main nav links -->
    <nav class="flex-1 py-1 space-y-0.5 px-2 overflow-y-auto">
      <div class="mac-sidebar-section">Menu</div>
      <a
        v-for="link in mainNavLinks"
        :key="link.id"
        href="#"
        @click.prevent="navigate(link)"
        :class="['mac-sidebar-item', { active: currentBaseRoute === link.id }]"
        :aria-current="currentBaseRoute === link.id ? 'page' : undefined"
        :title="collapsed ? link.label : undefined"
      >
        <span class="material-symbols-outlined text-lg flex-shrink-0">{{ link.icon }}</span>
        <span
          v-show="!collapsed"
          class="whitespace-nowrap transition-opacity duration-200"
        >
          {{ link.label }}
        </span>
      </a>
    </nav>

    <!-- Bottom section -->
    <div class="py-1 space-y-0.5 px-2 flex-shrink-0">
      <div v-show="!collapsed" class="mac-sidebar-section">System</div>
      <a
        v-for="link in bottomNavLinks"
        :key="link.id"
        href="#"
        @click.prevent="navigate(link)"
        :class="['mac-sidebar-item', { active: currentBaseRoute === link.id }]"
        :aria-current="currentBaseRoute === link.id ? 'page' : undefined"
        :title="collapsed ? link.label : undefined"
      >
        <span class="material-symbols-outlined text-lg flex-shrink-0">{{ link.icon }}</span>
        <span
          v-show="!collapsed"
          class="whitespace-nowrap transition-opacity duration-200"
        >
          {{ link.label }}
        </span>
      </a>
    </div>

    <!-- Bottom status -->
    <div class="px-4 py-3 flex-shrink-0 border-t border-white/5">
      <div v-if="!collapsed" class="flex items-center gap-2">
        <ConnectionStatus variant="mini" :freshness-minutes="freshnessMinutes" />
        <span class="mac-caption">v2.0</span>
      </div>
      <div v-else class="flex justify-center">
        <ConnectionStatus variant="dot" :freshness-minutes="freshnessMinutes" />
      </div>
    </div>

    <!-- Collapse toggle -->
    <button
      @click="emit('toggle-collapse')"
      class="hidden md:flex items-center justify-center h-8 text-slate-500 hover:text-slate-300 hover:bg-white/5 transition-colors text-sm"
      aria-label="Toggle sidebar"
    >
      <span class="material-symbols-outlined text-sm">
        {{ collapsed ? 'chevron_right' : 'chevron_left' }}
      </span>
    </button>
  </aside>
</template>
