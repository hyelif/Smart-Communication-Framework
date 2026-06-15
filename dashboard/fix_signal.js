const fs = require('fs');
const path = require('path');

const file = path.join(__dirname, 'resources/js/Pages/Dashboard/Overview.vue');
let content = fs.readFileSync(file, 'utf8');

// Fix fetchSignalData to also update signal with priority distribution data
const oldFetchSignalData = `const fetchSignalData = async () => {
  try {
    const url = '/api/dashboard/signal-history?range=' + encodeURIComponent(signalRange.value)
    const res = await fetch(url)
    if (res.ok) {
      const json = await res.json()
      signalData.value = json.data || []
    }
  } catch (e) { signalData.value = [] }
}`;
const newFetchSignalData = `const fetchSignalData = async () => {
  try {
    const url = '/api/dashboard/signal-history?range=' + encodeURIComponent(signalRange.value)
    const res = await fetch(url)
    if (res.ok) {
      const json = await res.json()
      signalData.value = json.data || []
      // Also update signal with distribution stats for the comm tab
      if (json.priority_distribution) {
        signal.value = {
          ...signal.value,
          excellent: json.priority_distribution.excellent ?? 0,
          good:      json.priority_distribution.good ?? 0,
          fair:      json.priority_distribution.fair ?? 0,
          poor:      json.priority_distribution.poor ?? 0,
          critical:  json.priority_distribution.critical ?? 0,
        }
      }
    }
  } catch (e) { signalData.value = [] }
}`;
content = content.replace(oldFetchSignalData, newFetchSignalData);

// Also update pollDashboard to initialize signal with excellent/good/fair/poor/critical = 0
const oldPollSignal = `signal.value = json.signal_stats || {}`;
const newPollSignal = `signal.value = { ...json.signal_stats || {}, excellent: 0, good: 0, fair: 0, poor: 0, critical: 0 }`;
content = content.replace(oldPollSignal, newPollSignal);

fs.writeFileSync(file, content, 'utf8');
console.log('Signal distribution fix applied');