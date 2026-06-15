const fs = require('fs');
const path = require('path');

const file = path.join(__dirname, 'resources/js/Pages/Dashboard/Overview.vue');
let content = fs.readFileSync(file, 'utf8');

// Fix the duplicate nested div in the modal header
const badModalHeader = `            <div class="flex items-center gap-3">
            <div class="flex items-center gap-3">
              <div class="flex bg-slate-800/80 rounded-full p-0.5 border border-slate-700/60 shadow-inner">
                <button
                  v-for="opt in rangeOptions"
                  :key="opt.value"
                  @click="selectedRange = opt.value"
                  class="px-3 py-1 text-[9px] font-bold rounded-full transition-all duration-200 min-w-[36px] text-center"
                  :class="selectedRange === opt.value
                    ? 'bg-gradient-to-r from-cyan-500 to-cyan-400 text-slate-900 shadow-lg shadow-cyan-500/25 scale-105'
                    : 'text-slate-500 hover:text-slate-300'"
                >
                  {{ opt.label }}
                </button>
              </div>
              <button @click="closeModal" class="p-2 rounded-lg hover:bg-slate-800 text-slate-400 hover:text-white">
                <svg class="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
                </svg>
              </button>
            </div>
          </div>`;
const goodModalHeader = `            <div class="flex items-center gap-3">
              <div class="flex bg-slate-800/80 rounded-full p-0.5 border border-slate-700/60 shadow-inner">
                <button
                  v-for="opt in rangeOptions"
                  :key="opt.value"
                  @click="selectedRange = opt.value"
                  class="px-3 py-1 text-[9px] font-bold rounded-full transition-all duration-200 min-w-[36px] text-center"
                  :class="selectedRange === opt.value
                    ? 'bg-gradient-to-r from-cyan-500 to-cyan-400 text-slate-900 shadow-lg shadow-cyan-500/25 scale-105'
                    : 'text-slate-500 hover:text-slate-300'"
                >
                  {{ opt.label }}
                </button>
              </div>
              <button @click="closeModal" class="p-2 rounded-lg hover:bg-slate-800 text-slate-400 hover:text-white">
                <svg class="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
                </svg>
              </button>
            </div>`;
content = content.replace(badModalHeader, goodModalHeader);

fs.writeFileSync(file, content, 'utf8');
console.log('Modal fixed');