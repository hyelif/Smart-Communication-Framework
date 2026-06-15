<script setup>
import { ref, computed, onMounted, watch, nextTick } from 'vue'

const props = defineProps({
  nodes: { type: Array, default: () => [] },
  loading: { type: Boolean, default: false },
  error: { type: Boolean, default: false },
})

const emit = defineEmits(['retry', 'select'])

// ─── Stagger entrance ───
const visible = ref(false)

function triggerStagger() {
  nextTick(() => {
    requestAnimationFrame(() => {
      visible.value = true
    })
  })
}

watch(() => props.nodes, (val) => {
  if (val && val.length > 0) {
    triggerStagger()
  } else {
    visible.value = false
  }
}, { immediate: true })

onMounted(() => {
  if (props.nodes && props.nodes.length > 0) {
    triggerStagger()
  }
})

// ─── Search ───
const searchQuery = ref('')

const filteredNodes = computed(() => {
  const q = searchQuery.value.toLowerCase().trim()
  if (!q) return props.nodes
  return props.nodes.filter(n =>
    (n.name || '').toLowerCase().includes(q) ||
    (n.hardware_id || '').toLowerCase().includes(q) ||
    (n.location || '').toLowerCase().includes(q)
  )
})

// ─── Helpers ───

function isOnline(lastSeen) {
  if (!lastSeen) return false
  const now = new Date()
  const last = new Date(lastSeen)
  const diffMs = now - last
  const diffMinutes = diffMs / 60000
  return diffMinutes < 5
}

function timeAgo(dateStr) {
  if (!dateStr) return '--'
  const now = new Date()
  const date = new Date(dateStr)
  const diffMs = now - date
  const diffSeconds = Math.floor(diffMs / 1000)

  if (diffSeconds < 60) return 'Just now'
  const diffMinutes = Math.floor(diffSeconds / 60)
  if (diffMinutes < 60) return `${diffMinutes}m ago`
  const diffHours = Math.floor(diffMinutes / 60)
  if (diffHours < 24) return `${diffHours}h ago`
  const diffDays = Math.floor(diffHours / 24)
  if (diffDays < 30) return `${diffDays}d ago`
  return formatDate(dateStr)
}

function formatDate(dateStr) {
  if (!dateStr) return '--'
  try {
    const d = new Date(dateStr)
    return d.toLocaleDateString([], { month: 'short', day: 'numeric', year: 'numeric' })
  } catch {
    return dateStr
  }
}

function formatDateTime(dateStr) {
  if (!dateStr) return '--'
  try {
    const d = new Date(dateStr)
    return d.toLocaleDateString([], {
      month: 'short',
      day: 'numeric',
      year: 'numeric',
      hour: '2-digit',
      minute: '2-digit',
    })
  } catch {
    return dateStr
  }
}

// ─── Computed ───

const nodesWithStatus = computed(() => {
  return (filteredNodes.value || []).map((node, idx) => ({
    ...node,
    online: isOnline(node.last_seen),
    timeAgoLabel: timeAgo(node.last_seen),
    firstSeenFormatted: formatDateTime(node.first_seen),
    lastSeenFormatted: formatDateTime(node.last_seen),
    _index: idx,
  }))
})

const isEmpty = computed(() => {
  if (props.loading) return false
  return !props.nodes || props.nodes.length === 0
})

const nodeCount = computed(() => {
  return (props.nodes || []).length
})

const onlineCount = computed(() => {
  return (props.nodes || []).filter(n => isOnline(n.last_seen)).length
})

const offlineCount = computed(() => {
  return nodeCount.value - onlineCount.value
})
</script>

<template>
  <div>
    <!-- ═══════════════════════════════════════════════════════════════
         LOADING STATE
         ═══════════════════════════════════════════════════════════════ -->
    <div v-if="loading" class="space-y-5" aria-hidden="true">
      <!-- Summary skeleton -->
      <div class="mac-card p-4 hover-lift-enhanced">
        <div class="flex flex-wrap items-center gap-6">
          <div class="skeleton-text w-28" />
          <div class="skeleton-text w-24" />
          <div class="skeleton-text w-20" />
        </div>
      </div>
      <!-- Node card skeletons -->
      <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        <div v-for="n in 6" :key="n" class="mac-card p-4 space-y-3">
          <div class="flex items-center justify-between">
            <div class="flex items-center gap-2">
              <div class="skeleton-text w-3 h-3 rounded-full" />
              <div class="skeleton-text w-14" />
            </div>
            <div class="skeleton-text w-20" />
          </div>
          <div class="skeleton-text w-full h-px my-2" />
          <div class="flex items-center gap-2">
            <div class="skeleton-text w-4 h-4 rounded" />
            <div class="skeleton-text w-32" />
          </div>
          <div class="flex items-center gap-2">
            <div class="skeleton-text w-4 h-4 rounded" />
            <div class="skeleton-text w-40" />
          </div>
          <div class="flex items-center justify-between mt-2">
            <div class="skeleton-text w-24" />
            <div class="skeleton-text w-16" />
          </div>
        </div>
      </div>
    </div>

    <!-- ═══════════════════════════════════════════════════════════════
         ERROR STATE
         ═══════════════════════════════════════════════════════════════ -->
    <div
      v-else-if="error"
      class="card-panel text-center py-12"
      role="alert"
      aria-live="assertive"
    >
      <div class="flex flex-col items-center gap-4">
        <div class="w-14 h-14 rounded-full bg-red-500/10 flex items-center justify-center">
          <span class="material-symbols-outlined text-3xl text-red-400">cloud_off</span>
        </div>
        <div>
          <p class="text-slate-300 text-sm font-medium mb-1">Failed to load nodes</p>
          <p class="text-slate-500 text-xs">Could not retrieve node data from the gateway</p>
        </div>
        <button
          @click="emit('retry')"
          class="btn btn-primary text-xs inline-flex items-center gap-1.5 active-scale"
        >
          <span class="material-symbols-outlined text-sm">refresh</span>
          Retry
        </button>
      </div>
    </div>

    <!-- ═══════════════════════════════════════════════════════════════
         EMPTY STATE
         ═══════════════════════════════════════════════════════════════ -->
    <div
      v-else-if="isEmpty"
      class="card-panel text-center py-16"
    >
      <div class="flex flex-col items-center gap-4">
        <div class="relative">
          <span class="material-symbols-outlined text-6xl text-slate-700 animate-float">sensors_off</span>
          <span class="material-symbols-outlined text-2xl text-slate-600 absolute -top-1 -right-2 animate-pulse">add_circle</span>
        </div>
        <p class="text-slate-400 text-sm font-medium">No nodes registered</p>
        <p class="text-slate-600 text-xs">Nodes will appear here once they connect to the gateway</p>
      </div>
    </div>

    <!-- ═══════════════════════════════════════════════════════════════
         DATA DISPLAY
         ═══════════════════════════════════════════════════════════════ -->
    <div v-else class="space-y-6">
      <!-- ─── Search ─── -->
      <div class="relative">
        <span class="material-symbols-outlined absolute left-3 top-1/2 -translate-y-1/2 text-sm text-slate-500">search</span>
        <input
          v-model="searchQuery"
          type="text"
          placeholder="Search nodes by name, ID, or location..."
          class="w-full h-10 pl-9 pr-3 rounded-lg bg-white/5 border border-white/5 text-sm text-slate-300 placeholder-slate-600 focus:outline-none focus:border-cyan-400/30 focus:bg-white/8 transition-all"
        />
      </div>

      <!-- ─── Summary Bar ─── -->
      <div class="mac-card p-4 flex flex-wrap items-center justify-between gap-4">
        <div class="flex items-center gap-3 min-w-0">
          <div class="w-10 h-10 rounded-lg bg-cyan-500/12 flex items-center justify-center shrink-0">
            <span class="material-symbols-outlined text-cyan-400">hub</span>
          </div>
          <div class="min-w-0">
            <p class="text-[11px] font-medium text-slate-500 uppercase tracking-wider">Total Nodes</p>
            <p class="text-xl font-bold text-white tabular-nums leading-tight">{{ nodeCount }}</p>
          </div>
        </div>
        <div class="flex items-center gap-3 min-w-0">
          <div class="w-10 h-10 rounded-lg bg-emerald-500/12 flex items-center justify-center shrink-0">
            <span class="material-symbols-outlined text-emerald-400">check_circle</span>
          </div>
          <div class="min-w-0">
            <p class="text-[11px] font-medium text-slate-500 uppercase tracking-wider">Online</p>
            <p class="text-xl font-bold text-emerald-400 tabular-nums leading-tight">{{ onlineCount }}</p>
          </div>
        </div>
        <div class="flex items-center gap-3 min-w-0">
          <div class="w-10 h-10 rounded-lg bg-slate-500/12 flex items-center justify-center shrink-0">
            <span class="material-symbols-outlined text-slate-400">radio_button_unchecked</span>
          </div>
          <div class="min-w-0">
            <p class="text-[11px] font-medium text-slate-500 uppercase tracking-wider">Offline</p>
            <p class="text-xl font-bold text-slate-400 tabular-nums leading-tight">{{ offlineCount }}</p>
          </div>
        </div>
      </div>

      <!-- ─── Node Grid ─── -->
      <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        <div
          v-for="(node, index) in nodesWithStatus"
          :key="node.id || node.hardware_id || index"
          class="mac-card p-4 stagger-enter hover:-translate-y-0.5 transition-all duration-200 cursor-pointer"
          :class="{ visible }"
          :style="{ transitionDelay: `${index * 80}ms` }"
          @click="emit('select', node)"
          role="button"
          tabindex="0"
          @keydown.enter="emit('select', node)"
          @keydown.space.prevent="emit('select', node)"
        >
          <!-- Header: Status dot + Online/Offline + hardware_id -->
          <div class="flex items-center justify-between mb-2">
            <div class="flex items-center gap-2">
              <div class="relative flex items-center justify-center">
                <div
                  class="w-2.5 h-2.5 rounded-full"
                  :class="node.online ? 'bg-emerald-400' : 'bg-slate-500'"
                />
                <div
                  v-if="node.online"
                  class="absolute w-2.5 h-2.5 rounded-full bg-emerald-400/40 animate-ping"
                />
              </div>
              <span
                class="text-[11px] font-semibold uppercase tracking-wider"
                :class="node.online ? 'text-emerald-400' : 'text-slate-400'"
              >
                {{ node.online ? 'Online' : 'Offline' }}
              </span>
            </div>
            <span class="text-[10px] font-mono text-slate-500 bg-slate-800/50 px-1.5 py-0.5 rounded">
              {{ node.hardware_id }}
            </span>
          </div>

          <!-- Divider -->
          <div class="divider my-2" />

          <!-- Name -->
          <div class="flex items-center gap-2 mb-1.5">
            <span class="material-symbols-outlined text-sm text-slate-500">badge</span>
            <span class="text-sm font-medium text-white truncate" :title="node.name">
              {{ node.name || 'Unnamed Node' }}
            </span>
          </div>

          <!-- Location -->
          <div class="flex items-center gap-2 mb-3">
            <span class="material-symbols-outlined text-sm text-slate-500">location_on</span>
            <span class="text-xs text-slate-400 truncate" :title="node.location">
              {{ node.location || 'No location set' }}
            </span>
          </div>

          <!-- Timestamps -->
          <div class="flex items-center justify-between text-[11px] text-slate-500 pt-2 border-t border-slate-700/30">
            <span class="flex items-center gap-1">
              <span class="material-symbols-outlined text-[10px]">calendar_today</span>
              {{ node.firstSeenFormatted }}
            </span>
            <span class="tabular-nums">{{ node.timeAgoLabel }}</span>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
