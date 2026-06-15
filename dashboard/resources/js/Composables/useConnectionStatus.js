import { ref, computed } from 'vue'

/**
 * useConnectionStatus composable
 * Tracks connection freshness and provides computed status.
 */
export function useConnectionStatus(healthRef, latestRef) {
  const lastUpdated = ref(new Date().toLocaleTimeString())

  const freshnessMinutes = computed(() => {
    const health = healthRef.value || {}
    const latest = latestRef.value || {}
    if (health.freshness_seconds != null) {
      return Math.round((health.freshness_seconds / 60) * 10) / 10
    }
    if (latest.minutes_since != null) {
      return latest.minutes_since
    }
    return null
  })

  const isFresh = computed(() => {
    const m = freshnessMinutes.value
    return m !== null && m <= 1
  })

  const isStale = computed(() => {
    const m = freshnessMinutes.value
    return m !== null && m > 5 && m <= 15
  })

  const connectionStatus = computed(() => {
    const m = freshnessMinutes.value
    if (m === null) return 'disconnected'
    if (m <= 1) return 'connected'
    if (m <= 5) return 'connected'
    if (m <= 15) return 'degraded'
    return 'disconnected'
  })

  function updateTimestamp() {
    lastUpdated.value = new Date().toLocaleTimeString()
  }

  return {
    connectionStatus,
    freshnessMinutes,
    isStale,
    isFresh,
    lastUpdated,
    updateTimestamp,
  }
}
