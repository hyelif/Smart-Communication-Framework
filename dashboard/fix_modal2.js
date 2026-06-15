const fs = require('fs');
const path = require('path');

const file = path.join(__dirname, 'resources/js/Pages/Dashboard/Overview.vue');
let content = fs.readFileSync(file, 'utf8');

// Fix: missing closing </div> after modal header buttons, before chart area
const bad = `            </div>
          <div class="p-8">`;
const good = `            </div>
          </div>
          <div class="p-8">`;
content = content.replace(bad, good);

fs.writeFileSync(file, content, 'utf8');
console.log('Modal closing div fixed');