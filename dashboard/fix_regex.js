const fs = require('fs');
const path = require('path');

const file = path.join(__dirname, 'app/Http/Controllers/DashboardController.php');
let content = fs.readFileSync(file, 'utf8');

// Fix the broken REGEXP line
content = content.replace(
  `->whereRaw("sd.value REGEXP "^-?[0-9]+(\\\\.[0-9]+)?$"")`,
  '->whereRaw(\'sd.value REGEXP "^-?[0-9]+(\\\\.[0-9]+)?$"\')'
);

fs.writeFileSync(file, content, 'utf8');
console.log('Fixed REGEXP line');