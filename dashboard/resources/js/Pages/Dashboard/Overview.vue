<script setup>
import { ref, shallowRef, onMounted, onUnmounted, computed, watch, nextTick } from 'vue'
import StatCard from '../../Components/StatCard.vue'
import SensorCard from '../../Components/SensorCard.vue'
import TabBar from '../../Components/TabBar.vue'
import CommunicationPanel from '../../Components/CommunicationPanel.vue'
import AnalyticsPanel from '../../Components/AnalyticsPanel.vue'
import NodesPanel from '../../Components/NodesPanel.vue'
import AlertsPanel from '../../Components/AlertsPanel.vue'
import SettingsPanel from '../../Components/SettingsPanel.vue'
import SensorModal from '../../Components/SensorModal.vue'
import NodeDetailModal from '../../Components/NodeDetailModal.vue'
import HealthPanel from '../../Components/HealthPanel.vue'
import SimulationPanel from '../../Components/SimulationPanel.vue'
import KeyboardShortcuts from '../../Components/KeyboardShortcuts.vue'
import ScrollToTop from '../../Components/ScrollToTop.vue'
import ToastNotification from '../../Components/ToastNotification.vue'
import { useToast } from '../../Composables/useToast'
import { useSensorHistory } from '../../Composables/useSensorHistory'
import { useConnectionStatus } from '../../Composables/useConnectionStatus'
import { useTabNavigation } from '../../Composables/useTabNavigation'
import { useTween } from '../../Composables/useTween'
import { useStagger } from '../../Composables/useStagger'

const props = defineProps({
  sensorReadings: Object,
  activeSensors: Array,
  telegramBotState: Array,
  nodes: Array,
  profiles: Object,
  activeAlerts: Array,
  signalStats: Object,
  commHealth: Object,
})

const activeTab = ref('overview')
const latest = shallowRef(props.sensorReadings || {})
const STALE_THRESHOLD_MINUTES = 5
const sensors = shallowRef(props.activeSensors || [])
const botState = shallowRef(props.telegramBotState || [])
const alerts = shallowRef(props.activeAlerts || [])
const signal = shallowRef(props.signalStats || {})
const health = shallowRef(props.commHealth || {})
const allProfiles = shallowRef(props.profiles || {})
const nodesData = shallowRef(props.nodes || [])
const loading = ref(false)
const hasLoadedOnce = ref(!!(props.activeSensors && props.activeSensors.length > 0))
const emptyPollCount = ref(0)
const selectedRange = ref('24 HOUR')
const signalRange = ref('24 HOUR')
const signalData = shallowRef([])
const analyticsData = shallowRef(null)
const signalLoading = ref(false)
const analyticsLoading = ref(false)
const sensorError = ref(false)
const modalOpen = ref(false)
const modalSensor = ref(null)
const nodeModalOpen = ref(false)
const nodeModalNode = ref(null)
const mounted = ref(false)

// Composables
const { freshnessMinutes, lastUpdated, updateTimestamp } = useConnectionStatus(health, latest)
const { tweenedValues, startTween, cancelAll: cancelTweens } = useTween()
const { visibleIndices, triggerStagger, isVisible, isAnimating, cancelAll: cancelStagger } = useStagger()
const { activeGlobalTab, setActiveTab } = useTabNavigation()
const { addToast } = useToast()
const { recordSnapshot } = useSensorHistory()
const showShortcuts = ref(false)
const lastFocusedElement = ref(null)

let pollTimer = null
let errorTimer = null

// ─── AbortController management ───
const activeControllers = new Set()

function abortableFetch(url, options = {}) {
  const controller = new AbortController()
  activeControllers.add(controller)
  const signal = controller.signal
  const promise = fetch(url, { ...options, signal })
  promise.finally(() => activeControllers.delete(controller))
  return { promise, controller }
}

function abortAllFetches() {
  for (const c of activeControllers) {
    c.abort()
  }
  activeControllers.clear()
}

const tabs = [
  { id: 'overview', label: 'Overview', icon: 'grid' },
  { id: 'communication', label: 'Communication', icon: 'zap' },
  { id: 'analytics', label: 'Analytics', icon: 'chart' },
]

// ─── Hardware error threshold ───
const HARDWARE_ERROR_VALUES = [-127, -127.0, 9999]

function isHardwareError(v) {
  if (v === null || v === undefined || v === '--') return false
  const n = parseFloat(v)
  if (isNaN(n)) return false
  return HARDWARE_ERROR_VALUES.includes(n)
}

// ─── Freshness helpers ───
function freshnessClass(mins) {
  if (mins == null) return 'text-slate-400'
  if (mins <= 1) return 'text-emerald-400'
  if (mins <= 5) return 'text-cyan-400'
  if (mins <= 15) return 'text-amber-400'
  return 'text-red-400'
}

function freshnessStatus(mins) {
  if (mins == null) return 'Unknown'
  if (mins <= 1) return 'Fresh'
  if (mins <= 5) return 'Recent'
  if (mins <= 15) return 'Stale'
  return 'Lost'
}

function toNum(v) {
  const n = parseFloat(v)
  return isNaN(n) ? null : n
}

// ─── Polling ───
const pollDashboard = async () => {
  if (!hasLoadedOnce.value) loading.value = true
  try {
    const url = '/api/dashboard/poll?range=' + encodeURIComponent(selectedRange.value)
    const { promise } = abortableFetch(url)
    const res = await promise
    if (res.ok) {
      const json = await res.json()
      latest.value = json.sensor_readings || {}
      if (json.active_sensors && json.active_sensors.length > 0) {
        sensors.value = json.active_sensors
        recordSnapshot(json.active_sensors)
        emptyPollCount.value = 0
        hasLoadedOnce.value = true
      } else {
        sensors.value = []
        hasLoadedOnce.value = false
      }
      botState.value = json.telegram_bot_state || []
      alerts.value = json.active_alerts || []
      signal.value = json.signal_stats || {}
      health.value = json.comm_health || {}
      if (json.profiles) allProfiles.value = json.profiles
      if (json.nodes) nodesData.value = json.nodes
      updateTimestamp()
      sensorError.value = false
      if (errorTimer) { clearTimeout(errorTimer); errorTimer = null }
    } else {
      sensorError.value = true
    }
  } catch (e) {
    if (e?.name === 'AbortError') return
    sensorError.value = true
    if (!errorTimer) errorTimer = setTimeout(() => { sensorError.value = false }, 10000)
  }
  finally { loading.value = false }
}

// ─── Signal/Analytics fetching ───
const fetchSignalData = async () => {
  signalLoading.value = true
  try {
    const url = '/api/dashboard/signal-history?range=' + encodeURIComponent(signalRange.value)
    const { promise } = abortableFetch(url)
    const res = await promise
    if (res.ok) {
      const json = await res.json()
      signalData.value = json.data || []
    }
  } catch (e) {
    if (e?.name === 'AbortError') return
    console.error('Signal fetch failed:', e)
  }
  finally { signalLoading.value = false }
}

const fetchAnalytics = async () => {
  analyticsLoading.value = true
  try {
    const url = '/api/dashboard/analytics?range=' + encodeURIComponent(selectedRange.value)
    const { promise } = abortableFetch(url)
    const res = await promise
    if (res.ok) {
      const json = await res.json()
      analyticsData.value = json
    }
  } catch (e) {
    if (e?.name === 'AbortError') return
    console.error('Analytics fetch failed:', e)
  }
  finally { analyticsLoading.value = false }
}

// ─── Modal ───
function openModal(sensor) {
  lastFocusedElement.value = document.activeElement
  modalSensor.value = sensor
  modalOpen.value = true
  document.body.style.overflow = 'hidden'
}

function closeModal() {
  modalOpen.value = false
  document.body.style.overflow = ''
  nextTick(() => lastFocusedElement.value?.focus())
}

function openNodeModal(node) {
  lastFocusedElement.value = document.activeElement
  nodeModalNode.value = node
  nodeModalOpen.value = true
  document.body.style.overflow = 'hidden'
}

function closeNodeModal() {
  nodeModalOpen.value = false
  nodeModalNode.value = null
  document.body.style.overflow = ''
  nextTick(() => lastFocusedElement.value?.focus())
}

function handleKeydown(e) {
  if (e.key === 'Escape' && modalOpen.value) { closeModal(); return }
  if (e.key === 'Escape' && nodeModalOpen.value) { closeNodeModal(); return }
  if (e.key === 'Escape' && showShortcuts.value) { showShortcuts.value = false; return }

  // Don't trigger shortcuts when typing in inputs
  if (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA') return

  if (e.key === '?') {
    showShortcuts.value = !showShortcuts.value
  } else if (e.key === 'r' || e.key === 'R') {
    pollDashboard()
    addToast('Refreshing data...', 'info', 1500)
  } else if (e.key >= '1' && e.key <= '5') {
    const tabIndex = parseInt(e.key) - 1
    const allTabs = [...tabs, ...['nodes', 'alerts', 'settings'].map(id => ({ id }))]
    if (allTabs[tabIndex]) {
      activeTab.value = allTabs[tabIndex].id
    }
  }
}

// ─── Lifecycle ───
onMounted(() => {
  mounted.value = true
  pollDashboard()
  pollTimer = setInterval(() => {
    if (document.visibilityState === 'visible') pollDashboard()
  }, 30000)
  document.addEventListener('keydown', handleKeydown)
})

onUnmounted(() => {
  if (pollTimer) clearInterval(pollTimer)
  if (errorTimer) clearTimeout(errorTimer)
  cancelTweens()
  cancelStagger()
  abortAllFetches()
  document.removeEventListener('keydown', handleKeydown)
})

watch(activeTab, (tab) => {
  if (tab === 'communication') fetchSignalData()
  if (tab === 'analytics') fetchAnalytics()
  if (tab === 'overview' && sensors.value?.length && !isAnimating) {
    nextTick(() => triggerStagger(sensors.value.length))
  }
})

watch(signalRange, () => fetchSignalData())

// ─── Sync with sidebar/mobile tab navigation ───
watch(activeGlobalTab, (tab) => {
  if (tab !== activeTab.value) {
    activeTab.value = tab
  }
})

watch(activeTab, (tab) => {
  if (tab !== activeGlobalTab.value) {
    setActiveTab(tab)
  }
})

// ─── Computed: alerts summary ───
const alertsSummary = computed(() => {
  if (health.value?.alert_summary) {
    const s = health.value.alert_summary
    return { active: s.total ?? s.active ?? 0, critical: s.critical ?? 0, warning: s.warning ?? 0, info: s.info ?? 0 }
  }
  const items = alerts.value || []
  const active = items.length
  const critical = items.filter(a => a.severity === 'critical').length
  const warning = items.filter(a => a.severity === 'warning').length
  return { active, critical, warning, info: 0 }
})

// ─── Adaptive sensor cards ───
const sensorCards = computed(() => {
  if (!sensors.value || sensors.value.length === 0) return []

  // Freshness check: if latest reading is stale, mark all sensors as offline
  const minsSince = latest.value?.minutes_since
  const isStale = minsSince != null && minsSince > STALE_THRESHOLD_MINUTES

  return sensors.value.map(s => {
    const profile = allProfiles.value[s.key] || {}
    const numVal = toNum(s.value)
    const displayValue = numVal != null ? numVal.toFixed(1) : '--'

    const hwError = isHardwareError(numVal)
    const isNull = numVal === null || isStale

    let badge
    if (hwError) {
      badge = { text: 'CHECK WIRING', class: 'bg-red-500/20 text-red-400', dot: 'bg-red-400' }
    } else if (isNull) {
      badge = { text: 'OFFLINE', class: 'bg-slate-500/20 text-slate-400', dot: 'bg-slate-400' }
    } else if (s.status === 'low') {
      badge = { text: 'Low', class: 'bg-amber-500/20 text-amber-400', dot: 'bg-amber-400' }
    } else if (s.status === 'high') {
      badge = { text: 'High', class: 'bg-red-500/20 text-red-400', dot: 'bg-red-400' }
    } else {
      badge = { text: 'Normal', class: 'bg-emerald-500/20 text-emerald-400', dot: 'bg-emerald-400' }
    }

    let cardClass = 'sensor-card sensor-normal'
    if (hwError) cardClass = 'sensor-card sensor-error'
    else if (s.status === 'high') cardClass = 'sensor-card sensor-alert'
    else if (s.status === 'low') cardClass = 'sensor-card sensor-warning'

    return {
      ...profile,
      ...s,
      displayValue: isNull ? '--' : displayValue,
      badge,
      cardClass,
      isHardwareError: hwError,
      isNull,
    }
  })
})

// ─── Tween watcher ───
watch(() => sensorCards?.value, (cards, oldCards) => {
  if (!oldCards || oldCards.length === 0) return
  for (const card of cards) {
    if (card.isNull || card.isHardwareError) continue
    const old = oldCards.find(c => c.key === card.key)
    if (!old || old.isNull || old.isHardwareError) continue
    const oldNum = parseFloat(old.displayValue)
    const newNum = parseFloat(card.displayValue)
    if (!isNaN(oldNum) && !isNaN(newNum) && oldNum !== newNum) {
      startTween(card.key, oldNum, newNum)
    }
  }
})

// ─── Default sensor types fallback ───
const defaultSensorTypes = [
  { key: 'temperature', label: 'Temperature', unit: '°C', icon: 'device_thermostat', color: '#f97316' },
  { key: 'humidity', label: 'Humidity', unit: '%', icon: 'water_drop', color: '#22d3ee' },
  { key: 'ph', label: 'pH', unit: 'pH', icon: 'science', color: '#a78bfa' },
  { key: 'tds', label: 'TDS', unit: 'ppm', icon: 'water', color: '#34d399' },
]

// ─── Offline placeholders ───
const offlinePlaceholders = computed(() => {
  const profiles = allProfiles.value || {}
  const entries = Object.entries(profiles)
  const source = entries.length > 0 ? entries : defaultSensorTypes.map(d => [d.key, d])
  return source.map(([key, profile]) => ({
    key,
    label: profile.label || key,
    unit: profile.unit || '',
    icon: profile.icon || '',
    color: profile.color || '#64748b',
    displayValue: '--',
    isNull: true,
    isHardwareError: false,
    status: 'offline',
    pin: '--',
  }))
})

const dataReady = computed(() => !loading.value && sensorCards.value.length > 0)

// ─── Stagger trigger on first load ───
watch(() => sensorCards?.value, (cards, oldCards) => {
  if (cards.length > 0 && mounted.value && (!oldCards || oldCards.length === 0)) {
    nextTick(() => triggerStagger(cards.length))
  }
})

// ─── System health stats ───
const healthDeliveryRate = computed(() => {
  if (health.value?.delivery_rate != null) {
    return Number(health.value.delivery_rate).toFixed(0) + '%'
  }
  return null
})

const healthUptime = computed(() => {
  if (health.value?.uptime_hours != null) {
    return health.value.uptime_hours.toFixed(1) + 'h uptime'
  }
  return ''
})

const freshnessValue = computed(() => {
  return freshnessMinutes.value != null ? freshnessMinutes.value.toFixed(1) : null
})

const freshnessLabel = computed(() => {
  const m = freshnessMinutes.value
  if (m == null) return ''
  if (m < 1) return 'just now'
  if (m < 60) return 'min ago'
  if (m < 1440) return `${Math.round(m / 60)}h ago`
  return `${Math.round(m / 1440)}d ago`
})

// ─── Current sensor values for simulator ───
const currentSensorValues = computed(() => {
  const vals = {}
  for (const s of sensorCards.value) {
    const num = parseFloat(s.value)
    vals[s.key] = isNaN(num) ? null : num
  }
  return vals
})

// ─── Weather condition from rain sensor ───
const weatherCondition = computed(() => {
  if (!sensors.value || sensors.value.length === 0) return 'unknown'
  const rain = sensors.value.find(s => s.key === 'rain')
  if (!rain) return 'unknown'
  const v = parseFloat(rain.value)
  if (isNaN(v)) return 'unknown'
  return v >= 0.5 ? 'sunny' : 'rainy'
})

const weatherLabel = computed(() => {
  if (weatherCondition.value === 'rainy') return 'Raining'
  if (weatherCondition.value === 'sunny') return 'Clear'
  return 'No Data'
})

// Stable rain drops (computed once, not per render)
const rainDrops = Array.from({ length: 60 }, (_, i) => ({
  left: String(((i * 17 + 31) % 100)),
  delay: String(((i * 7) % 20) / 10),
  duration: String(0.4 + ((i * 13) % 6) / 10),
}))

const sunRays = Array.from({ length: 12 }, (_, i) => i)
</script>

<template>
  <div>
    <!-- Error Banner -->
    <div
      v-if="sensorError"
      class="mb-4 px-4 py-2.5 rounded-lg bg-red-500/10 border border-red-500/20 text-red-400 text-sm flex items-center gap-2"
      role="alert"
      aria-live="assertive"
    >
      <span class="material-symbols-outlined text-sm">error</span>
      <span>Connection issue — retrying...</span>
    </div>

    <!-- Tab Bar -->
    <TabBar v-if="['overview', 'communication', 'analytics'].includes(activeTab)" :tabs="tabs" :active="activeTab" @update:active="activeTab = $event" />

    <!-- ═══ Tab Content ═══ -->
    <Transition name="tab-fade" mode="out-in">
      <div v-if="activeTab === 'overview'" key="overview" role="tabpanel" id="panel-overview" aria-labelledby="tab-overview" class="relative">
        <!-- Weather Background -->
        <div v-if="weatherCondition !== 'unknown'" class="weather-bg" :class="`weather-${weatherCondition}`" aria-hidden="true">
          <div class="weather-bg-overlay" />
          <!-- Rain particles -->
          <div v-if="weatherCondition === 'rainy'" class="rain-container" aria-hidden="true">
            <div v-for="(drop, i) in rainDrops" :key="i" class="rain-drop" :style="{ left: drop.left + '%', animationDelay: drop.delay + 's', animationDuration: drop.duration + 's' }" />
          </div>
          <!-- Sun glow -->
          <div v-if="weatherCondition === 'sunny'" class="sun-glow" aria-hidden="true">
            <div class="sun-ray" v-for="n in sunRays" :key="n" :style="{ transform: 'rotate(' + (n * 30) + 'deg)' }" />
          </div>
        </div>
        <!-- Stat Row -->
        <div class="grid grid-cols-1 sm:grid-cols-2 gap-3 mb-5">
          <StatCard
            label="System Health"
            :value="healthDeliveryRate ?? '--'"
            sublabel="delivery"
            :meta="healthUptime"
            icon="monitor_heart"
            icon-class="text-cyan-400"
          />
          <StatCard
            label="Freshness"
            :value="freshnessValue ?? '--'"
            :sublabel="freshnessLabel"
            :meta="lastUpdated ? 'Last: ' + lastUpdated : freshnessStatus(freshnessMinutes)"
            icon="schedule"
            :icon-class="freshnessClass(freshnessMinutes)"
          />
        </div>

        <!-- Sensor Grid: Loading -->
        <div v-if="!hasLoadedOnce && loading" class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-3" aria-hidden="true">
          <div v-for="n in 6" :key="n" class="sensor-card">
            <div class="skeleton-text w-24 mb-3" />
            <div class="skeleton-metric mb-3" />
            <div class="skeleton-badge" />
          </div>
        </div>

        <!-- Sensor Grid: Offline Placeholders -->
        <div v-else-if="!hasLoadedOnce && sensorCards.length === 0">
          <div class="mb-3 px-3 py-2 rounded-lg bg-slate-500/10 border border-slate-500/20 text-slate-400 text-xs flex items-center gap-2">
            <span class="material-symbols-outlined text-sm">sensors_off</span>
            <span>Node is offline — showing expected sensor types</span>
          </div>
          <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-3">
            <SensorCard
              v-for="(card, index) in offlinePlaceholders"
              :key="card.key || index"
              :sensor="card"
              :visible="true"
              :index="index"
              @click="openModal(card)"
            />
          </div>
        </div>

        <!-- Sensor Grid: Data -->
        <div v-else class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-3">
          <SensorCard
            v-for="(card, index) in sensorCards"
            :key="card.key || index"
            :sensor="card"
            :tweened-value="tweenedValues[card.key] ?? null"
            :visible="true"
            :index="index"
            @click="openModal(card)"
          />
        </div>
      </div>

      <div v-else-if="activeTab === 'nodes'" key="nodes" role="tabpanel" id="panel-nodes" aria-labelledby="tab-nodes">
        <NodesPanel
          :nodes="nodesData"
          :loading="loading"
          @select="openNodeModal"
        />
      </div>

      <div v-else-if="activeTab === 'alerts'" key="alerts" role="tabpanel" id="panel-alerts" aria-labelledby="tab-alerts">
        <AlertsPanel
          :alerts="alerts"
          :loading="loading"
        />
      </div>

      <div v-else-if="activeTab === 'communication'" key="communication" role="tabpanel" id="panel-communication" aria-labelledby="tab-communication">
        <CommunicationPanel
          :signal-stats="signal"
          :signal-data="signalData"
          :loading="signalLoading"
          :signal-range="signalRange"
          @update:signal-range="signalRange = $event"
        />
      </div>

      <div v-else-if="activeTab === 'analytics'" key="analytics" role="tabpanel" id="panel-analytics" aria-labelledby="tab-analytics">
        <AnalyticsPanel
          :data="analyticsData"
          :loading="analyticsLoading"
        />
      </div>

      <div v-else-if="activeTab === 'health'" key="health" role="tabpanel" id="panel-health" aria-labelledby="tab-health">
        <HealthPanel
          :sensors="sensors"
          :profiles="allProfiles"
          :minutes-since="latest.minutes_since"
          :last-updated="lastUpdated"
        />
      </div>

      <div v-else-if="activeTab === 'settings'" key="settings" role="tabpanel" id="panel-settings" aria-labelledby="tab-settings">
        <SettingsPanel />
      </div>

      <div v-else-if="activeTab === 'simulate'" key="simulate" role="tabpanel" id="panel-simulate" aria-labelledby="tab-simulate">
        <SimulationPanel
          :profiles="allProfiles"
          :current-values="currentSensorValues"
        />
      </div>
    </Transition>

    <!-- ═══ Sensor Modal ═══ -->
    <SensorModal
      :open="modalOpen"
      :sensor="modalSensor"
      :tweened-value="tweenedValues[modalSensor?.key] ?? null"
      @close="closeModal"
    />

    <!-- ═══ Node Detail Modal ═══ -->
    <NodeDetailModal
      :open="nodeModalOpen"
      :node="nodeModalNode"
      @close="closeNodeModal"
    />

    <!-- ═══ Toast Notifications ═══ -->
    <ToastNotification />

    <!-- ═══ Keyboard Shortcuts ═══ -->
    <KeyboardShortcuts :open="showShortcuts" @close="showShortcuts = false" />

    <!-- ═══ Scroll to Top ═══ -->
    <ScrollToTop />
  </div>
</template>
