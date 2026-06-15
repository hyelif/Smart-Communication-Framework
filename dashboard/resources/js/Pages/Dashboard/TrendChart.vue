<script setup>
import { ref, computed, onMounted, watch, onUnmounted, nextTick } from 'vue'
import { Chart, registerables } from 'chart.js'

Chart.register(...registerables)

const props = defineProps({
  data: { type: Array, default: () => [] },
  profile: { type: Object, default: () => ({}) },
  color: { type: String, default: '#22d3ee' },
  showPrediction: { type: Boolean, default: true },
})

const canvasRef = ref(null)
const chartRef = ref(null)
const hasData = ref(false)
const breachInfo = ref(null)

function toNum(v) {
  if (v === null || v === undefined || v === '') return null
  const n = parseFloat(v)
  return isNaN(n) || !isFinite(n) ? null : n
}

// ─── Linear Regression ───
function linearRegression(pts) {
  const n = pts.length
  if (n < 3) return null
  let sumX = 0, sumY = 0, sumXY = 0, sumX2 = 0
  for (let i = 0; i < n; i++) {
    const y = toNum(pts[i].value)
    if (y === null) continue
    sumX += i
    sumY += y
    sumXY += i * y
    sumX2 += i * i
  }
  const slope = (n * sumXY - sumX * sumY) / (n * sumX2 - sumX * sumX)
  const intercept = (sumY - slope * sumX) / n
  return { slope, intercept }
}

function computePrediction(pts) {
  const valid = pts.filter(p => toNum(p.value) !== null)
  if (valid.length < 3) return { labels: [], values: [], breach: null }

  const reg = linearRegression(valid)
  if (!reg) return { labels: [], values: [], breach: null }

  // Use last 20 points max for prediction
  const recent = valid.slice(-20)
  const reg2 = linearRegression(recent)
  if (!reg2) return { labels: [], values: [], breach: null }

  // Estimate average time interval between points
  const n = valid.length
  let intervalMs = 3600000 // default 1h
  if (n > 1 && valid[0].time && valid[n - 1].time) {
    const t0 = new Date(valid[0].time).getTime()
    const t1 = new Date(valid[n - 1].time).getTime()
    intervalMs = (t1 - t0) / (n - 1)
  }
  // Cap interval to reasonable range (5min to 6h)
  intervalMs = Math.max(300000, Math.min(intervalMs, 21600000))

  // Project 8 steps forward
  const steps = 8
  const lastIdx = recent.length - 1
  const lastTime = new Date(valid[valid.length - 1].time).getTime()
  const predLabels = []
  const predValues = []
  let breach = null
  const tMin = toNum(props.profile.t_min)
  const tMax = toNum(props.profile.t_max)

  for (let i = 1; i <= steps; i++) {
    const idx = lastIdx + i
    const val = reg2.slope * idx + reg2.intercept
    const t = new Date(lastTime + intervalMs * i)
    predLabels.push(t.toLocaleString('en-US', { month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' }))
    predValues.push(val)

    // Check breach (first crossing only)
    if (!breach) {
      if (tMin !== null && val < tMin) {
        const hoursFromNow = (intervalMs * i) / 3600000
        breach = { type: 'min', threshold: tMin, hours: Math.round(hoursFromNow * 10) / 10 }
      } else if (tMax !== null && val > tMax) {
        const hoursFromNow = (intervalMs * i) / 3600000
        breach = { type: 'max', threshold: tMax, hours: Math.round(hoursFromNow * 10) / 10 }
      }
    }
  }

  return { labels: predLabels, values: predValues, breach }
}

const thresholdPlugin = {
  id: 'thresholdZones',
  beforeDraw(chart) {
    const { ctx, chartArea, scales } = chart
    const { top, bottom, left, right } = chartArea
    if (!scales?.y) return

    const yScale = scales.y
    const tMin = toNum(props.profile.t_min)
    const tMax = toNum(props.profile.t_max)
    if (tMin === null && tMax === null) return

    const w = right - left
    ctx.save()
    ctx.setLineDash([4, 3])
    ctx.lineWidth = 1
    ctx.font = '8px sans-serif'

    if (tMin !== null && tMax !== null) {
      const yTop = yScale.getPixelForValue(tMax)
      const yBot = yScale.getPixelForValue(tMin)
      if (yTop !== undefined && yBot !== undefined) {
        ctx.fillStyle = 'rgba(34, 197, 94, 0.06)'
        ctx.fillRect(left, yTop, w, yBot - yTop)
        ctx.fillStyle = 'rgba(239, 68, 68, 0.08)'
        ctx.fillRect(left, yBot, w, bottom - yBot)
        ctx.fillRect(left, top, w, yTop - top)
        ctx.strokeStyle = '#ef4444'
        ctx.beginPath(); ctx.moveTo(left, yTop); ctx.lineTo(right, yTop); ctx.stroke()
        ctx.fillStyle = '#ef4444'
        ctx.fillText('Max:' + props.profile.t_max, left + 3, yTop - 3)
        ctx.strokeStyle = '#f59e0b'
        ctx.beginPath(); ctx.moveTo(left, yBot); ctx.lineTo(right, yBot); ctx.stroke()
        ctx.fillStyle = '#f59e0b'
        ctx.fillText('Min:' + props.profile.t_min, left + 3, yBot + 9)
      }
    } else if (tMin !== null) {
      const yLine = yScale.getPixelForValue(tMin)
      if (yLine !== undefined) {
        ctx.strokeStyle = '#f59e0b'
        ctx.beginPath(); ctx.moveTo(left, yLine); ctx.lineTo(right, yLine); ctx.stroke()
        ctx.fillStyle = '#f59e0b'
        ctx.fillText('Min:' + props.profile.t_min, left + 3, yLine - 3)
      }
    } else if (tMax !== null) {
      const yLine = yScale.getPixelForValue(tMax)
      if (yLine !== undefined) {
        ctx.strokeStyle = '#ef4444'
        ctx.beginPath(); ctx.moveTo(left, yLine); ctx.lineTo(right, yLine); ctx.stroke()
        ctx.fillStyle = '#ef4444'
        ctx.fillText('Max:' + props.profile.t_max, left + 3, yLine - 3)
      }
    }
    ctx.restore()
  }
}

Chart.register(thresholdPlugin)

function buildChart() {
  if (!canvasRef.value) return

  const pts = props.data || []
  const labels = pts.map(p => {
    if (!p.time) return ''
    try {
      const d = new Date(p.time)
      return d.toLocaleString('en-US', { month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' })
    } catch { return p.time }
  })
  let values = pts.map(p => {
    const v = toNum(p.value)
    return v
  })
  hasData.value = values.some(v => v !== null)

  // If no valid values, show flat 0 line so the chart doesn't disappear
  if (!hasData.value && pts.length > 0) {
    values = pts.map(() => 0)
    hasData.value = true
  } else if (pts.length === 0) {
    const fallbackLabels = ['']
    const fallbackValues = [0]
    labels.push(...fallbackLabels)
    values.push(...fallbackValues)
    hasData.value = true
  }

  // Compute prediction
  let predLabels = [], predValues = []
  if (props.showPrediction && hasData.value) {
    const pred = computePrediction(pts)
    predLabels = pred.labels
    predValues = pred.values
    breachInfo.value = pred.breach
  } else {
    breachInfo.value = null
  }

  const ctx = canvasRef.value.getContext('2d')
  if (!ctx) return

  const gradient = ctx.createLinearGradient(0, 0, 0, 264)
  gradient.addColorStop(0, props.color + '30')
  gradient.addColorStop(1, props.color + '03')

  const datasets = [{
    label: 'Value',
    data: values,
    borderColor: props.color,
    backgroundColor: gradient,
    borderWidth: 1.5,
    pointRadius: 0,
    pointHoverRadius: 4,
    fill: true,
    tension: 0.3,
  }]

  // Add prediction dataset
  if (predValues.length > 0) {
    // Extend labels with prediction labels
    const allLabels = [...labels, ...predLabels]
    // Pad historical dataset with nulls for prediction region
    const paddedValues = [...values, ...new Array(predValues.length).fill(null)]

    datasets[0].data = paddedValues
    datasets.push({
      label: 'Predicted',
      data: [...new Array(values.length).fill(null), ...predValues],
      borderColor: props.color + '80',
      backgroundColor: 'transparent',
      borderWidth: 1.5,
      borderDash: [5, 4],
      pointRadius: 0,
      pointHoverRadius: 3,
      fill: false,
      tension: 0.3,
    })

    chartRef.value = new Chart(ctx, {
      type: 'line',
      data: { labels: allLabels, datasets },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        animation: false,
        interaction: { intersect: false, mode: 'nearest', axis: 'x' },
        plugins: {
          legend: { display: false },
          tooltip: {
            enabled: true,
            backgroundColor: '#1e293b',
            titleColor: '#94a3b8',
            bodyColor: '#e2e8f0',
            borderColor: '#475569',
            borderWidth: 1,
            padding: 8,
            cornerRadius: 6,
            displayColors: false,
            callbacks: {
              title: (items) => items[0]?.label || '',
              label: (item) => {
                const v = item.parsed.y
                const unit = props.profile?.unit || ''
                const label = item.datasetIndex === 1 ? 'Predicted' : ''
                return v != null ? `${label} ${v.toFixed(1)} ${unit}`.trim() : '--'
              }
            }
          },
          thresholdZones: true
        },
        scales: {
          x: {
            display: true,
            grid: { color: '#1e293b', drawBorder: false },
            ticks: {
              color: '#64748b',
              font: { size: 9 },
              maxTicksLimit: 8,
              maxRotation: 0,
            }
          },
          y: {
            display: true,
            grid: { color: '#1e293b', drawBorder: false },
            ticks: {
              color: '#64748b',
              font: { size: 9 },
              maxTicksLimit: 5,
              padding: 4,
            }
          }
        }
      },
    })
    return
  }

  // No prediction — standard chart
  chartRef.value = new Chart(ctx, {
    type: 'line',
    data: { labels, datasets },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      animation: false,
      interaction: { intersect: false, mode: 'nearest', axis: 'x' },
      plugins: {
        legend: { display: false },
        tooltip: {
          enabled: true,
          backgroundColor: '#1e293b',
          titleColor: '#94a3b8',
          bodyColor: '#e2e8f0',
          borderColor: '#475569',
          borderWidth: 1,
          padding: 8,
          cornerRadius: 6,
          displayColors: false,
          callbacks: {
            title: (items) => items[0]?.label || '',
            label: (item) => {
              const v = item.parsed.y
              const unit = props.profile?.unit || ''
              return v != null ? `${v.toFixed(1)} ${unit}` : '--'
            }
          }
        },
        thresholdZones: true
      },
      scales: {
        x: {
          display: true,
          grid: { color: '#1e293b', drawBorder: false },
          ticks: {
            color: '#64748b',
            font: { size: 9 },
            maxTicksLimit: 6,
            maxRotation: 0,
          }
        },
        y: {
          display: true,
          grid: { color: '#1e293b', drawBorder: false },
          ticks: {
            color: '#64748b',
            font: { size: 9 },
            maxTicksLimit: 5,
            padding: 4,
          }
        }
      }
    },
  })
}

function updateChart() {
  if (!chartRef.value) return

  const pts = props.data || []
  const labels = pts.map(p => {
    if (!p.time) return ''
    try {
      const d = new Date(p.time)
      return d.toLocaleString('en-US', { month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' })
    } catch { return p.time }
  })
  let values = pts.map(p => {
    const v = toNum(p.value)
    return v
  })
  hasData.value = values.some(v => v !== null)

  // If no valid values, show flat 0 line
  if (!hasData.value && pts.length > 0) {
    values = pts.map(() => 0)
    hasData.value = true
  } else if (pts.length === 0) {
    const fallbackLabels = ['']
    const fallbackValues = [0]
    labels.push(...fallbackLabels)
    values.push(...fallbackValues)
    hasData.value = true
  }

  // Compute prediction
  let predLabels = [], predValues = []
  if (props.showPrediction && hasData.value) {
    const pred = computePrediction(pts)
    predLabels = pred.labels
    predValues = pred.values
    breachInfo.value = pred.breach
  } else {
    breachInfo.value = null
  }

  const chart = chartRef.value

  if (predValues.length > 0) {
    const allLabels = [...labels, ...predLabels]
    chart.data.labels = allLabels
    chart.data.datasets[0].data = [...values, ...new Array(predValues.length).fill(null)]
    if (chart.data.datasets.length > 1) {
      chart.data.datasets[1].data = [...new Array(values.length).fill(null), ...predValues]
    } else {
      chart.data.datasets.push({
        label: 'Predicted',
        data: [...new Array(values.length).fill(null), ...predValues],
        borderColor: props.color + '80',
        backgroundColor: 'transparent',
        borderWidth: 1.5,
        borderDash: [5, 4],
        pointRadius: 0,
        pointHoverRadius: 3,
        fill: false,
        tension: 0.3,
      })
    }
  } else {
    chart.data.labels = labels
    chart.data.datasets[0].data = values
    if (chart.data.datasets.length > 1) {
      chart.data.datasets.splice(1)
    }
  }
  chart.update('none')
}

watch(() => props.data?.length ?? 0, () => {
  if (chartRef.value) {
    nextTick(() => updateChart())
  } else {
    nextTick(() => buildChart())
  }
})

watch(() => props.profile, () => {
  if (chartRef.value) {
    chartRef.value.update('none')
  }
})

watch(() => props.showPrediction, () => {
  if (chartRef.value) {
    nextTick(() => updateChart())
  } else {
    nextTick(() => buildChart())
  }
})

onMounted(() => {
  nextTick(() => buildChart())
})

onUnmounted(() => {
  if (chartRef.value) {
    chartRef.value.destroy()
    chartRef.value = null
  }
})
</script>

<template>
  <div>
    <!-- Fixed-height chart container — prevents resize loop -->
    <div class="chart-container" style="height: 264px;">
      <canvas ref="canvasRef" class="w-full h-full"></canvas>
      <div v-if="!hasData" class="absolute inset-0 flex items-center justify-center pointer-events-none">
        <span class="text-xs text-slate-500">No trend data</span>
      </div>
    </div>

    <!-- Legend (outside chart container to avoid resize interference) -->
    <div class="flex items-center gap-4 mt-2 text-[10px] flex-wrap px-1">
      <div v-if="hasData && profile.t_min != null && profile.t_max != null" class="flex items-center gap-1.5">
        <span class="w-3 h-2 rounded-sm bg-green-500/30"></span>
        <span class="text-slate-500">Safe</span>
      </div>
      <div v-if="hasData && profile.t_min != null && profile.t_max != null" class="flex items-center gap-1.5">
        <span class="w-3 h-2 rounded-sm bg-red-500/30"></span>
        <span class="text-slate-500">Danger</span>
      </div>
      <div v-if="breachInfo" class="flex items-center gap-1.5">
        <span class="w-4 h-0 border-t border-dashed" :style="{ borderColor: color + '80' }"></span>
        <span class="text-slate-500">Predicted</span>
      </div>
    </div>

    <!-- Breach indicator (outside chart container) -->
    <div v-if="breachInfo" class="mt-1.5 px-1">
      <div
        class="inline-flex items-center gap-1.5 px-2 py-1 rounded-md text-[10px] font-semibold"
        :class="breachInfo.type === 'max' ? 'bg-red-500/10 text-red-400' : 'bg-amber-500/10 text-amber-400'"
      >
        <span class="material-symbols-outlined text-[12px]">warning</span>
        <span>
          Predicted to breach {{ breachInfo.type === 'max' ? 'maximum' : 'minimum' }}
          ({{ breachInfo.threshold }}{{ profile.unit || '' }})
          in ~{{ breachInfo.hours }}h
        </span>
      </div>
    </div>
  </div>
</template>
