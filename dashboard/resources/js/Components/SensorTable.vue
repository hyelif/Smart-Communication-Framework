<script setup>
import { ref, computed } from 'vue'

const props = defineProps({
  sensors: {
    type: Array,
    default: () => [],
  },
  loading: {
    type: Boolean,
    default: false,
  },
})

const emit = defineEmits(['select'])

const sortKey = ref('')
const sortDir = ref('asc')
const searchQuery = ref('')
const selectedKey = ref(null)

const columns = [
  { key: 'label', label: 'Sensor' },
  { key: 'displayValue', label: 'Value' },
  { key: 'unit', label: 'Unit' },
  { key: 'status', label: 'Status' },
  { key: 'pin', label: 'Pin' },
  { key: 'lastUpdated', label: 'Last Updated' },
]

const filteredAndSorted = computed(() => {
  let result = [...props.sensors]

  // Filter
  if (searchQuery.value) {
    const q = searchQuery.value.toLowerCase()
    result = result.filter((s) =>
      s.label?.toLowerCase().includes(q) ||
      s.key?.toLowerCase().includes(q) ||
      s.status?.toLowerCase().includes(q)
    )
  }

  // Sort
  if (sortKey.value) {
    result.sort((a, b) => {
      const aVal = a[sortKey.value] ?? ''
      const bVal = b[sortKey.value] ?? ''
      const cmp = String(aVal).localeCompare(String(bVal), undefined, { numeric: true })
      return sortDir.value === 'asc' ? cmp : -cmp
    })
  }

  return result
})

function toggleSort(key) {
  if (sortKey.value === key) {
    sortDir.value = sortDir.value === 'asc' ? 'desc' : 'asc'
  } else {
    sortKey.value = key
    sortDir.value = 'asc'
  }
}

function statusDotClass(sensor) {
  if (sensor.isHardwareError) return 'bg-red-400'
  if (sensor.isNull) return 'bg-slate-400'
  if (sensor.status === 'low') return 'bg-amber-400'
  if (sensor.status === 'high') return 'bg-red-400'
  return 'bg-emerald-400'
}

function statusLabel(sensor) {
  if (sensor.isHardwareError) return 'Error'
  if (sensor.isNull) return 'Offline'
  if (sensor.status === 'low') return 'Low'
  if (sensor.status === 'high') return 'High'
  return 'Normal'
}

function formatLastUpdated(sensor) {
  if (!sensor.lastUpdated) return '--'
  if (sensor.lastUpdated instanceof Date) {
    return sensor.lastUpdated.toLocaleTimeString()
  }
  return String(sensor.lastUpdated)
}

function handleRowClick(sensor) {
  selectedKey.value = sensor.key
  emit('select', sensor)
}

const skeletonRows = Array.from({ length: 5 }, (_, i) => ({ id: i }))
</script>

<template>
  <div class="mac-card p-5">
    <!-- Search bar -->
    <div class="flex items-center gap-2 mb-4">
      <span class="material-symbols-outlined text-slate-500">search</span>
      <input
        v-model="searchQuery"
        type="text"
        placeholder="Search sensors..."
        class="bg-transparent border-none text-sm text-white placeholder-slate-500 focus:outline-none w-full"
      />
      <span v-if="searchQuery && !loading" class="text-xs text-slate-500 whitespace-nowrap">
        {{ filteredAndSorted.length }} result{{ filteredAndSorted.length === 1 ? '' : 's' }}
      </span>
    </div>

    <!-- Loading skeleton -->
    <template v-if="loading">
      <div class="overflow-x-auto">
        <table class="data-table">
          <thead>
            <tr>
              <th v-for="col in columns" :key="col.key">
                {{ col.label }}
              </th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="row in skeletonRows" :key="row.id">
              <td v-for="col in columns" :key="col.key">
                <div
                  class="skeleton-bar rounded h-4"
                  :style="{ width: col.key === 'label' ? '8rem' : col.key === 'displayValue' ? '4rem' : '5rem' }"
                />
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </template>

    <!-- Normal or empty state -->
    <template v-else>
      <div class="overflow-x-auto">
        <table class="data-table">
          <thead>
            <tr>
              <th
                v-for="col in columns"
                :key="col.key"
                @click="toggleSort(col.key)"
              >
                {{ col.label }}
                <span
                  v-if="sortKey === col.key"
                  class="material-symbols-outlined text-xs align-middle ml-0.5"
                >
                  {{ sortDir === 'asc' ? 'arrow_upward' : 'arrow_downward' }}
                </span>
              </th>
            </tr>
          </thead>
          <tbody v-if="filteredAndSorted.length > 0">
            <tr
              v-for="sensor in filteredAndSorted"
              :key="sensor.key"
              @click="handleRowClick(sensor)"
              :class="[
                'cursor-pointer transition-colors',
                selectedKey === sensor.key ? 'bg-surface-container-high' : 'hover:bg-surface-container-high/50',
              ]"
            >
              <td class="font-medium text-white">{{ sensor.label }}</td>
              <td class="font-mono tabular-nums">{{ sensor.displayValue ?? '--' }}</td>
              <td class="text-slate-500">{{ sensor.unit || '' }}</td>
              <td>
                <span class="inline-flex items-center gap-1.5 text-xs">
                  <span class="w-1.5 h-1.5 rounded-full" :class="statusDotClass(sensor)" />
                  {{ statusLabel(sensor) }}
                </span>
              </td>
              <td class="text-slate-500">Pin {{ sensor.pin }}</td>
              <td class="text-slate-500">{{ formatLastUpdated(sensor) }}</td>
            </tr>
          </tbody>
        </table>
      </div>

      <!-- Empty state: no sensors at all -->
      <div
        v-if="!loading && sensors.length === 0"
        class="flex flex-col items-center justify-center py-10 text-center"
      >
        <span class="material-symbols-outlined text-4xl text-slate-600 mb-3 empty-state-icon">
          sensors_off
        </span>
        <p class="text-sm text-slate-500">No sensors available</p>
      </div>

      <!-- Empty state: filtered but no match -->
      <div
        v-else-if="!loading && searchQuery && filteredAndSorted.length === 0"
        class="flex flex-col items-center justify-center py-10 text-center"
      >
        <span class="material-symbols-outlined text-4xl text-slate-600 mb-3 empty-state-icon">
          search_off
        </span>
        <p class="text-sm text-slate-500">No sensors match your search</p>
        <button
          class="text-xs text-accent hover:text-accent-dim mt-2 transition-colors"
          @click="searchQuery = ''"
        >
          Clear filter
        </button>
      </div>
    </template>
  </div>
</template>
