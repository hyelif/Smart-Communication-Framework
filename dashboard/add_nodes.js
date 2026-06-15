const fs = require('fs');
const path = require('path');

const file = path.join(__dirname, 'resources/js/Pages/Dashboard/Overview.vue');
let content = fs.readFileSync(file, 'utf8');

// Add nodes ref to the script setup - it's in props but not initialized as a reactive ref
const oldSensors = `const sensors = shallowRef(props.activeSensors || [])`;
const newSensors = `const sensors = shallowRef(props.activeSensors || [])
const nodes = shallowRef(props.nodes || [])`;
content = content.replace(oldSensors, newSensors);

// Also update pollDashboard to update nodes.value when polling
const oldPollNodes = `health.value = json.comm_health || {}
      if (json.profiles) allProfiles.value = json.profiles
      lastUpdated.value = new Date().toLocaleTimeString()`;
const newPollNodes = `health.value = json.comm_health || {}
      if (json.profiles) allProfiles.value = json.profiles
      if (json.nodes) nodes.value = json.nodes
      lastUpdated.value = new Date().toLocaleTimeString()`;
content = content.replace(oldPollNodes, newPollNodes);

fs.writeFileSync(file, content, 'utf8');
console.log('nodes ref added');