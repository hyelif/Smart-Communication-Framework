import { ref, computed } from 'vue'

const MAX_HISTORY = 5
const history = ref({}) // { sensorKey: [value1, value2, ...] }

export function useSensorHistory() {
  function recordSnapshot(sensors) {
    for (const s of sensors) {
      const key = s.key
      const val = parseFloat(s.value)
      if (isNaN(val)) continue

      if (!history.value[key]) {
        history.value[key] = []
      }
      history.value[key].push(val)
      if (history.value[key].length > MAX_HISTORY) {
        history.value[key].shift()
      }
    }
  }

  function getHistory(key) {
    return history.value[key] || []
  }

  function getAverage(key) {
    const vals = getHistory(key)
    if (vals.length === 0) return null
    return vals.reduce((a, b) => a + b, 0) / vals.length
  }

  function getStdDev(key) {
    const vals = getHistory(key)
    if (vals.length < 2) return null
    const avg = getAverage(key)
    const variance = vals.reduce((sq, v) => sq + (v - avg) ** 2, 0) / vals.length
    return Math.sqrt(variance)
  }

  function getPrevious(key) {
    const vals = getHistory(key)
    return vals.length >= 2 ? vals[vals.length - 2] : null
  }

  function getRateOfChange(key, minutesSince) {
    const prev = getPrevious(key)
    const current = getHistory(key).slice(-1)[0]
    if (prev === null || current === null || !minutesSince || minutesSince === 0) return 0
    return Math.abs(current - prev) / minutesSince
  }

  function computeAnomalyScore(key, currentValue, profile, minutesSince) {
    if (currentValue === null || currentValue === undefined) return 0
    let score = 0

    // 1. Proximity to threshold (0-40)
    const tMin = profile?.t_min
    const tMax = profile?.t_max
    if (tMin !== null && tMax !== null) {
      const range = tMax - tMin
      if (range > 0) {
        const mid = (tMax + tMin) / 2
        const dist = Math.abs(currentValue - mid)
        const pct = dist / (range / 2)
        if (currentValue < tMin || currentValue > tMax) {
          score += 40
        } else if (pct >= 0.95) {
          score += 35
        } else if (pct >= 0.9) {
          score += 30
        } else if (pct >= 0.8) {
          score += 20
        } else if (pct >= 0.6) {
          score += 10
        }
      }
    } else if (tMin !== null) {
      if (currentValue < tMin) score += 40
      else {
        const pct = Math.abs(currentValue - tMin) / Math.abs(tMin || 1)
        if (pct < 0.05) score += 35
        else if (pct < 0.1) score += 30
      }
    } else if (tMax !== null) {
      if (currentValue > tMax) score += 40
      else {
        const pct = Math.abs(currentValue - tMax) / Math.abs(tMax || 1)
        if (pct < 0.05) score += 35
        else if (pct < 0.1) score += 30
      }
    }

    // 2. Rate of change (0-30)
    const rate = getRateOfChange(key, minutesSince)
    if (rate > 5) score += 30
    else if (rate > 2) score += 20
    else if (rate > 0.5) score += 10

    // 3. Historical deviation (0-30)
    const avg = getAverage(key)
    const std = getStdDev(key)
    if (avg !== null && std !== null && std > 0) {
      const zScore = Math.abs(currentValue - avg) / std
      if (zScore > 3) score += 30
      else if (zScore > 2) score += 20
      else if (zScore > 1.5) score += 10
    }

    return Math.min(100, Math.max(0, score))
  }

  function computeHealthScore(anomalyScore) {
    return Math.max(0, 100 - anomalyScore)
  }

  function computeTrend(key, profile) {
    const vals = getHistory(key)
    if (vals.length < 2) return 'stable'
    const current = vals[vals.length - 1]
    const prev = vals[vals.length - 2]
    if (current === prev) return 'stable'
    const tMin = profile?.t_min
    const tMax = profile?.t_max
    if (tMin === null && tMax === null) return 'stable'
    // Moving toward threshold = declining, away = improving
    if (tMin !== null && tMax !== null) {
      const mid = (tMax + tMin) / 2
      const prevDist = Math.abs(prev - mid)
      const currDist = Math.abs(current - mid)
      return currDist < prevDist ? 'improving' : 'declining'
    }
    return current > prev ? 'declining' : 'improving'
  }

  function clearHistory() {
    history.value = {}
  }

  return {
    history,
    recordSnapshot,
    getHistory,
    getAverage,
    getStdDev,
    getPrevious,
    getRateOfChange,
    computeAnomalyScore,
    computeHealthScore,
    computeTrend,
    clearHistory,
  }
}
