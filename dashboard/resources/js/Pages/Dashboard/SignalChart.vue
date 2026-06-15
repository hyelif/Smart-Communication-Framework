<script setup>
import { ref, onMounted, watch, onUnmounted, nextTick } from 'vue'
import { Chart, registerables } from 'chart.js'

Chart.register(...registerables)

const props = defineProps({
  data: { type: Array, default: () => [] },
  field: { type: String, required: true },
  color: { type: String, default: '#f97316' },
})

const canvasRef = ref(null)
const chartRef = ref(null)
const hasData = ref(false)

function buildChart() {
  if (!canvasRef.value) return

  const pts = props.data || []
  let labels = pts.map(p => {
    if (!p.time) return ''
    try {
      const d = new Date(p.time)
      return d.toLocaleString('en-US', { month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' })
    } catch { return p.time }
  })
  let values = pts.map(p => {
    const v = parseFloat(p[props.field])
    return isNaN(v) || !isFinite(v) ? null : v
  })
  hasData.value = values.some(v => v !== null)

  // If there are no values but we have timestamps, show flat 0 line
  if (!hasData.value && pts.length > 0) {
    values = pts.map(() => 0)
    hasData.value = true
  } else if (pts.length === 0) {
    // Show one placeholder point at 0
    labels = ['']
    values = [0]
    hasData.value = true
  }

  const ctx = canvasRef.value.getContext('2d')
  if (!ctx) return

  const gradient = ctx.createLinearGradient(0, 0, 0, 180)
  gradient.addColorStop(0, props.color + '40')
  gradient.addColorStop(1, props.color + '05')

  chartRef.value = new Chart(ctx, {
    type: 'line',
    data: {
      labels,
      datasets: [{
        label: props.field,
        data: values,
        borderColor: props.color,
        backgroundColor: gradient,
        borderWidth: 1.5,
        pointRadius: values.length > 30 ? 0 : 2.5,
        pointHoverRadius: 4,
        pointBackgroundColor: '#0f172a',
        pointBorderColor: props.color,
        pointBorderWidth: 1.5,
        fill: true,
        tension: 0.4,
      }]
    },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      animation: {
        duration: 600,
        easing: 'easeOutQuart',
      },
      interaction: {
        intersect: false,
        mode: 'nearest',
        axis: 'x',
      },
      plugins: {
        legend: { display: false },
        tooltip: {
          enabled: true,
          backgroundColor: '#1e293b',
          titleColor: '#94a3b8',
          bodyColor: '#e2e8f0',
          borderColor: '#475569',
          borderWidth: 1,
          padding: 10,
          cornerRadius: 8,
          displayColors: false,
          callbacks: {
            title: (items) => items[0]?.label || '',
            label: (item) => {
              const v = item.parsed.y
              return v != null ? `${v.toFixed(2)}` : '--'
            }
          }
        }
      },
      scales: {
        x: {
          display: true,
          grid: { color: '#1e293b', drawBorder: false },
          ticks: {
            color: '#64748b',
            font: { size: 9, family: 'Inter' },
            maxTicksLimit: 8,
            maxRotation: 0,
          }
        },
        y: {
          display: true,
          grid: { color: '#1e293b', drawBorder: false },
          ticks: {
            color: '#64748b',
            font: { size: 9, family: 'Inter' },
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
  let labels = pts.map(p => {
    if (!p.time) return ''
    try {
      const d = new Date(p.time)
      return d.toLocaleString('en-US', { month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' })
    } catch { return p.time }
  })
  let values = pts.map(p => {
    const v = parseFloat(p[props.field])
    return isNaN(v) || !isFinite(v) ? null : v
  })
  hasData.value = values.some(v => v !== null)

  // If there are no values but we have timestamps, show flat 0 line
  if (!hasData.value && pts.length > 0) {
    values = pts.map(() => 0)
    hasData.value = true
  } else if (pts.length === 0) {
    labels = ['']
    values = [0]
    hasData.value = true
  }

  const chart = chartRef.value
  chart.data.labels = labels
  chart.data.datasets[0].data = values
  chart.update('none')
}

// Shallow watch on data length — entire array is replaced
watch(() => props.data?.length ?? 0, () => {
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
  <div class="chart-container mac-card p-3">
    <canvas ref="canvasRef" class="w-full" style="height:180px"></canvas>
    <div v-if="!hasData" class="absolute inset-0 flex items-center justify-center pointer-events-none">
      <span class="text-xs text-slate-500">No signal data</span>
    </div>
  </div>
</template>
