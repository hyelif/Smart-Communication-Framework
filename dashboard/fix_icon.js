const fs = require('fs');
const path = require('path');

const file = path.join(__dirname, 'resources/js/Pages/Dashboard/Overview.vue');
let content = fs.readFileSync(file, 'utf8');

// Fix the broken getSensorIcon function - replace multiline template with proper string
const broken = `function getSensorIcon(key) {
  const icon = sensorIconPaths[key] || sensorIconPaths.temperature
  return '<svg class="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="1.8">' +
    icon.split('
').map(p => '<path stroke-linecap="round" stroke-linejoin="round" d="' + p.trim() + '" />').join('') +
    '</svg>'
}`;
const fixed = `function getSensorIcon(key) {
  const iconPaths = sensorIconPaths[key] || sensorIconPaths.temperature
  const paths = iconPaths.split('\\n').map(p => '<path stroke-linecap="round" stroke-linejoin="round" d="' + p.trim() + '" />').join('')
  return '<svg class="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="1.8">' + paths + '</svg>'
}`;
content = content.replace(broken, fixed);

fs.writeFileSync(file, content, 'utf8');
console.log('getSensorIcon fixed');