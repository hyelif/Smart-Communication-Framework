# SmartPonic Dashboard — Production-Grade UI/UX Design Plan

> **Target Stack:** Laravel 10 + Vue 3 (Composition API) + Inertia + Tailwind CSS v4 + Chart.js
> **Status:** Design Plan v1.0 — Ready for Implementation
> **Audience:** Frontend implementation team

---

## Table of Contents

1. [Layout Architecture](#1-layout-architecture)
2. [Component Decomposition](#2-component-decomposition)
3. [Design System Refinements](#3-design-system-refinements)
4. [State Patterns for Every Component](#4-state-patterns-for-every-component)
5. [Accessibility Requirements](#5-accessibility-requirements)
6. [Responsive Behavior](#6-responsive-behavior)
7. [Animation & Micro-interactions](#7-animation--micro-interactions)
8. [Implementation Order](#8-implementation-order)

---

## 1. Layout Architecture

### 1.1 App Shell Structure

```
+----------------------------------------------------------+
|  AppLayout.vue                                            |
|  +--------+---------------------------------------------+ |
|  |        |  HeaderBar.vue                               | |
|  |        |  +----------------------------------------+ | |
|  |        |  | Page title | Last updated | Status | : | | |
|  |        |  +----------------------------------------+ | |
|  |        |                                             | |
|  | Sidebar|  <slot />  (Page content via Inertia)       | |
|  |        |                                             | |
|  |        |  +----------------------------------------+ | |
|  |        |  | [Footer / status bar — optional]       | | |
|  |        |  +----------------------------------------+ | |
|  +--------+---------------------------------------------+ |
+----------------------------------------------------------+
```

### 1.2 Sidebar (`AppSidebar.vue`)

**Props:**
```ts
interface AppSidebarProps {
  collapsed: boolean       // controlled by parent, toggled via hamburger
  currentRoute: string     // 'dashboard' | 'alerts' | 'nodes' | 'settings'
}
```

**Structure:**
- **Logo / Brand area** (top): `smartponic` wordmark + leaf icon. Links to `/`.
- **Nav links** (middle):
  - Dashboard (`/`) — icon: `dashboard`
  - Alerts (`/alerts`) — icon: `notifications` (with AlertBadge dot)
  - Nodes (`/nodes`) — icon: `sensors`
  - Settings (`/settings`) — icon: `settings`
- **Status indicator** (bottom): ConnectionStatus.vue mini variant + version label.

**Slots:** None.

**CSS classes for states:**
- Default: `w-64` (expanded), `w-16` (collapsed)
- Transition: `transition-all duration-300 ease-out-soft`
- Active nav link: `bg-primary-container/10 text-primary border-r-2 border-primary`
- Inactive nav link: `text-on-surface-variant hover:bg-surface-container-high hover:text-on-surface`

**Events emitted:**
- `@toggle-collapse` — emitted when hamburger clicked

### 1.3 Header Bar (`AppHeader.vue`)

**Props:**
```ts
interface AppHeaderProps {
  title: string              // page title, passed from Inertia
  lastUpdated: string | null // localized time string
  connectionStatus: 'connected' | 'degraded' | 'disconnected'
  alertCount: number         // total active alerts
}
```

**Structure:**
```
+------------------------------------------------------------------+
| [hamburger]  Page Title          Last updated: 14:32:05   [🟢] [👤] |
+------------------------------------------------------------------+
```

- Left: hamburger button (visible on mobile, toggles sidebar on desktop)
- Center-left: Page title (`text-headline-lg font-headline-lg`)
- Center-right: "Last updated: {time}" label (`text-xs text-on-surface-variant`)
- Right group:
  - ConnectionStatus.vue (mini dot variant)
  - User avatar placeholder (circle with initials, `w-8 h-8 rounded-full bg-surface-container-high`)
  - Optional: AlertBadge.vue (bell icon with count)

**Events emitted:**
- `@toggle-sidebar` — emitted when hamburger clicked

### 1.4 Main Content Area

- Wrapper: `<main class="flex-1 p-4 md:p-6 lg:p-8 overflow-y-auto">`
- Max width: `max-w-7xl mx-auto`
- Background: `bg-surface` (`#0f172a`)
- Scrollbar: custom thin scrollbar (already defined in app.css)

### 1.5 Mobile Bottom Navigation (`MobileNav.vue`)

Visible only on screens `< 768px`. Fixed to bottom.

**Props:**
```ts
interface MobileNavProps {
  currentRoute: string
  alertCount: number
}
```

**Structure:**
```
+--------------------------------------------------+
| [Dashboard] [Alerts] [Nodes] [Settings]          |
+--------------------------------------------------+
```

- Each item: icon + label, `flex flex-col items-center gap-0.5`
- Active: `text-primary` / Inactive: `text-on-surface-variant`
- Container: `fixed bottom-0 left-0 right-0 h-16 bg-surface-container border-t border-outline/30 z-40`

---

## 2. Component Decomposition

### 2.1 Complete Component Tree

```
AppLayout.vue
├── AppSidebar.vue
│   └── ConnectionStatus.vue (mini variant)
├── AppHeader.vue
│   ├── ConnectionStatus.vue (mini dot)
│   └── AlertBadge.vue
├── MobileNav.vue (shown <768px)
└── <slot /> (Inertia page)
    └── Pages/Dashboard/Overview.vue (refactored)
        ├── TabBar.vue
        ├── StatCard.vue (x3: Health, Freshness, Alerts)
        ├── SensorCard.vue (xN, in grid)
        ├── DownloadBar.vue
        ├── CommunicationPanel.vue
        │   ├── StatCard.vue (x3: RSSI, SNR, Critical)
        │   └── SignalChart.vue (existing)
        ├── AnalyticsPanel.vue
        └── SensorModal.vue
            └── TrendChart.vue (existing)
```

### 2.2 Component Specifications

---

#### `AppLayout.vue`

**File:** `resources/js/Layouts/AppLayout.vue`

**Purpose:** Persistent app shell wrapping all Inertia pages.

**Props:** None (uses Inertia shared data).

**Slots:**
- `default` — page content

**State:**
- `sidebarCollapsed: ref(false)` — toggles sidebar width
- `mobileNavOpen: ref(false)` — mobile sidebar overlay

**Template structure:**
```html
<div class="flex h-screen bg-surface overflow-hidden">
  <!-- Desktop sidebar -->
  <AppSidebar
    :collapsed="sidebarCollapsed"
    :current-route="$page.component"
    class="hidden md:flex"
    @toggle-collapse="sidebarCollapsed = !sidebarCollapsed"
  />
  <!-- Mobile sidebar overlay -->
  <Transition name="fade">
    <div v-if="mobileNavOpen" class="fixed inset-0 bg-black/50 z-30 md:hidden"
      @click="mobileNavOpen = false" />
  </Transition>
  <Transition name="slide-right">
    <AppSidebar v-if="mobileNavOpen"
      class="fixed left-0 top-0 z-40 h-full md:hidden"
      :current-route="$page.component"
      @toggle-collapse="mobileNavOpen = false" />
  </Transition>
  <!-- Main area -->
  <div class="flex-1 flex flex-col min-w-0">
    <AppHeader
      :title="pageTitle"
      :last-updated="lastUpdated"
      :connection-status="connectionStatus"
      :alert-count="alertCount"
      @toggle-sidebar="toggleMobileSidebar"
    />
    <main class="flex-1 overflow-y-auto p-4 md:p-6 lg:p-8">
      <div class="max-w-7xl mx-auto">
        <slot />
      </div>
    </main>
  </div>
  <!-- Mobile bottom nav -->
  <MobileNav
    :current-route="$page.component"
    :alert-count="alertCount"
    class="md:hidden"
  />
</div>
```

**Composables used:**
- `useConnectionStatus` — returns `{ connectionStatus, lastUpdated }`
- `usePageTitle` — returns `{ pageTitle }` derived from route

**Key behaviors:**
- On mount, reads `sidebarCollapsed` from `localStorage`
- On resize to `<768px`, forces sidebar closed
- Keyboard shortcut `Ctrl+B` toggles sidebar

---

#### `SensorCard.vue`

**File:** `resources/js/Components/SensorCard.vue`

**Purpose:** Individual sensor display card with status, value, and click-to-open-modal behavior.

**Props:**
```ts
interface SensorCardProps {
  sensor: {
    key: string
    label: string
    value: string | number | null
    unit: string
    pin: number | string
    status: 'normal' | 'low' | 'high'
    displayValue: string
    color: string
    icon?: string
  }
  tweenedValue?: number | null   // animated display value from parent
  visible: boolean                // stagger entrance control
  index: number                   // for stagger delay
}
```

**Events emitted:**
- `@click` — opens SensorModal with this sensor's data

**States:**

| State | Visual |
|-------|--------|
| **Loading** | Skeleton: `skeleton-text` for label, `skeleton-metric` for value, `skeleton-badge` for status |
| **Empty** (value is null/--) | Value shows `--`, badge shows `OFFLINE` in slate, dot is slate |
| **Error** (hardware error -127/9999) | Card has `sensor-error` class, red glow border, badge shows `CHECK WIRING` in red |
| **Normal** | Card has `sensor-normal` class, subtle cyan glow on hover |
| **Warning** (status=low) | Card has `sensor-warning` class, amber glow border, badge shows `Low` in amber |
| **Alert** (status=high) | Card has `sensor-alert` class, red glow border, badge shows `High` in red |
| **Edge: stale data** (>15 min since reading) | Badge shows `Stale` in amber, dot is amber |
| **Edge: missing sensor key** | Falls back to `sensor-unknown` class, generic label |

**Template structure:**
```html
<div
  :class="[cardClass, 'cursor-pointer', 'stagger-enter', { visible }]"
  role="button"
  tabindex="0"
  :aria-label="`${sensor.label}: ${sensor.displayValue} ${sensor.unit}, status ${sensor.status}`"
  @click="$emit('click')"
  @keydown.enter="$emit('click')"
  @keydown.space.prevent="$emit('click')"
>
  <!-- Card header -->
  <div class="flex items-center justify-between mb-3">
    <div class="flex items-center gap-2">
      <span class="w-2 h-2 rounded-full" :class="badge.dot" />
      <span class="text-sm font-medium text-slate-300">{{ sensor.label }}</span>
    </div>
    <span class="text-[10px] font-medium px-2 py-0.5 rounded-full" :class="badge.class">
      {{ badge.text }}
    </span>
  </div>
  <!-- Card value -->
  <div class="flex items-baseline gap-1.5 mb-2">
    <span class="text-metric-value font-metric-value text-white tween-value">
      {{ displayValue }}
    </span>
    <span class="text-sm text-slate-500">{{ sensor.unit }}</span>
  </div>
  <!-- Pin info -->
  <div class="text-[10px] text-slate-600">Pin {{ sensor.pin }}</div>
</div>
```

**Computed:**
- `badge` — derived from sensor.status + hardware error check
- `cardClass` — derived from sensor.status + hardware error check
- `displayValue` — uses tweenedValue if available, else sensor.displayValue

---

#### `StatCard.vue`

**File:** `resources/js/Components/StatCard.vue`

**Purpose:** Reusable stat display card for system health, freshness, alerts, signal stats.

**Props:**
```ts
interface StatCardProps {
  label: string              // e.g. "System Health"
  value: string | number     // e.g. "98%"
  sublabel?: string          // e.g. "delivery"
  meta?: string              // e.g. "120h uptime"
  icon?: string              // Material symbol name, e.g. "monitor_heart"
  iconClass?: string         // dynamic color class for icon
  trend?: 'up' | 'down' | 'neutral'  // optional trend indicator
  loading?: boolean          // shows skeleton when true
  variant?: 'default' | 'compact' | 'highlight'
}
```

**States:**

| State | Visual |
|-------|--------|
| **Loading** | Skeleton: `skeleton-text w-20` for label, `skeleton-metric` for value |
| **Empty** (value is null/--) | Value shows `--`, sublabel hidden |
| **Normal** | Full stat card with icon, value, sublabel, meta |
| **Highlight** | `variant="highlight"` adds accent border-left and brighter value color |
| **Compact** | `variant="compact"` smaller padding, used inside CommunicationPanel |

**Template structure:**
```html
<div :class="['stat-card', variantClass]">
  <div class="flex items-center gap-2 mb-2">
    <span v-if="icon" class="material-symbols-outlined text-sm" :class="iconClass">{{ icon }}</span>
    <span class="text-xs font-medium text-slate-500 uppercase tracking-wider">{{ label }}</span>
  </div>
  <div v-if="!loading" class="flex items-baseline gap-3">
    <span class="text-2xl font-bold text-white">{{ value }}</span>
    <span v-if="sublabel" class="text-xs text-slate-500">{{ sublabel }}</span>
  </div>
  <div v-else class="skeleton-metric mb-1" />
  <p v-if="meta && !loading" class="text-xs text-slate-500 mt-1">{{ meta }}</p>
  <div v-if="trend && !loading" class="flex items-center gap-1 mt-1">
    <span class="material-symbols-outlined text-sm" :class="trendClass">
      {{ trend === 'up' ? 'trending_up' : trend === 'down' ? 'trending_down' : 'remove' }}
    </span>
  </div>
</div>
```

---

#### `SensorModal.vue`

**File:** `resources/js/Components/SensorModal.vue`

**Purpose:** Sensor detail modal with trend chart, range selector, and current value.

**Props:**
```ts
interface SensorModalProps {
  open: boolean
  sensor: {
    key: string
    label: string
    displayValue: string
    unit: string
    color?: string
    t_min?: number
    t_max?: number
  } | null
}
```

**Events emitted:**
- `@close` — request to close modal

**Internal state:**
- `modalRange: ref('24 HOUR')` — selected range for trend chart
- `trendData: shallowRef([])` — fetched trend data
- `modalLoading: ref(false)` — trend loading state
- `modalError: ref(false)` — trend fetch error

**States:**

| State | Visual |
|-------|--------|
| **Closed** | Not rendered (v-if on teleport wrapper) |
| **Opening** | Transition: overlay fades in, content scales from 0.92 with spring easing |
| **Loading trend** | Spinner in chart area: `spinner-soft w-6 h-6` centered in h-64 container |
| **Trend loaded** | TrendChart with data + threshold zones |
| **Trend empty** | "No trend data available" centered in chart area |
| **Trend error** | "Failed to load trend data. Retry" with retry button |
| **Closing** | Transition: overlay fades out, content scales to 0.95 |

**Accessibility:**
- Focus trap: on open, focus first focusable element. Tab cycles within modal. Escape closes.
- `role="dialog"`, `aria-modal="true"`, `aria-labelledby="modal-title"`
- On close, restore focus to the sensor card that triggered it
- `aria-label` on close button: "Close sensor details"

**Template structure:**
```html
<Teleport to="body">
  <Transition name="modal">
    <div v-if="open" class="modal-overlay" @click.self="$emit('close')"
      role="dialog" aria-modal="true" :aria-labelledby="`modal-title-${sensor?.key}`">
      <div class="modal-content" ref="modalContentRef">
        <!-- Header -->
        <div class="flex items-center justify-between mb-4">
          <div>
            <h2 :id="`modal-title-${sensor?.key}`" class="text-headline-md font-headline-md text-white">
              {{ sensor?.label || 'Sensor Details' }}
            </h2>
            <p class="text-xs text-slate-500 mt-0.5">{{ sensor?.key }}</p>
          </div>
          <button @click="$emit('close')" class="..." aria-label="Close sensor details">
            <span class="material-symbols-outlined">close</span>
          </button>
        </div>
        <!-- Current value -->
        <div class="flex items-baseline gap-2 mb-4">
          <span class="text-hero-metric font-hero-metric text-white tween-value">
            {{ sensor?.displayValue ?? '--' }}
          </span>
          <span class="text-sm text-slate-500">{{ sensor?.unit }}</span>
        </div>
        <!-- Range selector -->
        <div class="flex gap-1 mb-4" role="tablist" aria-label="Time range">
          <button v-for="opt in rangeOptions" :key="opt.value"
            @click="modalRange = opt.value"
            :class="['text-xs px-2 py-1 rounded-md transition-colors', ...]"
            role="tab" :aria-selected="modalRange === opt.value">
            {{ opt.label }}
          </button>
        </div>
        <!-- Chart area -->
        <div v-if="modalLoading" class="h-64 flex items-center justify-center">
          <div class="spinner-soft w-6 h-6" role="status" aria-label="Loading trend data" />
        </div>
        <div v-else-if="modalError" class="h-64 flex flex-col items-center justify-center gap-2">
          <span class="text-slate-500 text-sm">Failed to load trend data</span>
          <button @click="fetchTrends" class="btn btn-primary text-xs">Retry</button>
        </div>
        <TrendChart v-else-if="trendData.length > 0"
          :data="trendData" :profile="sensor || {}" :color="sensor?.color || '#22d3ee'" />
        <div v-else class="h-64 flex items-center justify-center">
          <span class="text-slate-500 text-sm">No trend data available</span>
        </div>
      </div>
    </div>
  </Transition>
</Teleport>
```

---

#### `TabBar.vue`

**File:** `resources/js/Components/TabBar.vue`

**Purpose:** Reusable tab navigation component.

**Props:**
```ts
interface TabBarProps {
  tabs: Array<{ id: string; label: string; icon?: string }>
  active: string
}
```

**Events emitted:**
- `@update:active` — emitted with new tab id on click

**States:**

| State | Visual |
|-------|--------|
| **Normal** | Horizontal pill-style tabs, active tab has cyan bg/color |
| **Single tab** | Renders normally (no special handling needed) |
| **Edge: empty tabs** | Renders nothing (v-if on wrapper) |

**Accessibility:**
- `role="tablist"` on container
- `role="tab"` on each button
- `aria-selected` on active tab
- `aria-controls` pointing to tab panel id

---

#### `DownloadBar.vue`

**File:** `resources/js/Components/DownloadBar.vue`

**Purpose:** Export buttons row (Summary + CSV).

**Props:**
```ts
interface DownloadBarProps {
  sensors: Array<{ key: string; label: string; value: string | number; unit: string; pin: string | number; status: string }>
}
```

**Events emitted:** None (handles downloads internally).

**States:**

| State | Visual |
|-------|--------|
| **Normal** | Two buttons: "Summary" (primary) and "CSV" (secondary) |
| **Downloading** | Button shows spinner, disabled state during fetch |
| **Error** | Toast notification (future) or console error fallback |

**Methods:**
- `downloadSystemSummary()` — fetches `/api/dashboard/system-summary`, generates .txt
- `downloadCsv()` — generates CSV from sensors prop, triggers download

---

#### `CommunicationPanel.vue`

**File:** `resources/js/Components/CommunicationPanel.vue`

**Purpose:** Signal stats, RSSI bar, and signal chart.

**Props:**
```ts
interface CommunicationPanelProps {
  signalStats: {
    avg_rssi: number | null
    avg_snr: number | null
    critical: number | null
    min_rssi?: number
    max_rssi?: number
  }
  signalData: Array<{ time: string; rssi: number; snr: number }>
  loading: boolean
  signalRange: string
}
```

**Events emitted:**
- `@update:signal-range` — when range selector changes

**Sub-components used:**
- `StatCard.vue` (x3: Avg RSSI, Avg SNR, Critical Signals)
- `SignalChart.vue` (existing)

**States:**

| State | Visual |
|-------|--------|
| **Loading** | 3 skeleton stat cards + skeleton chart panel |
| **Loaded with data** | Full stats + RSSI bar + SignalChart |
| **Loaded, empty data** | Stats show `--`, chart shows "No signal data" |
| **Error** (fetch failed) | Error banner "Failed to load signal data" with retry |

---

#### `AnalyticsPanel.vue`

**File:** `resources/js/Components/AnalyticsPanel.vue`

**Purpose:** Analytics data display with key-value grid.

**Props:**
```ts
interface AnalyticsPanelProps {
  data: Record<string, any> | null
  loading: boolean
}
```

**States:**

| State | Visual |
|-------|--------|
| **Loading** | Skeleton: card panel with multiple skeleton lines |
| **Loaded with data** | Grid of stat cards, one per key-value pair |
| **Loaded, empty** (`data` is null or `{}`) | Empty state: analytics icon + "No analytics data available" |
| **Error** | Error banner with retry |

---

#### `ConnectionStatus.vue`

**File:** `resources/js/Components/ConnectionStatus.vue`

**Purpose:** Live connection indicator showing node/signal health.

**Props:**
```ts
interface ConnectionStatusProps {
  variant: 'full' | 'mini' | 'dot'
  freshnessMinutes: number | null
  rssi: number | null
  snr: number | null
  isStale: boolean
  isFresh: boolean
}
```

**States:**

| State | Visual |
|-------|--------|
| **Fresh** (<=1 min) | Green dot + "Connected" label |
| **Recent** (<=5 min) | Cyan dot + "Recent" label |
| **Stale** (<=15 min) | Amber dot + "Stale" label |
| **Lost** (>15 min) | Red dot + "Lost" label, pulse animation |
| **Unknown** (null) | Gray dot + "Unknown" label |
| **Mini variant** | Just the colored dot, no label |
| **Dot variant** | Single pulsing dot (used in header) |

**Accessibility:**
- `role="status"` with `aria-live="polite"`
- `aria-label` describing current state

---

#### `AlertBadge.vue`

**File:** `resources/js/Components/AlertBadge.vue`

**Purpose:** Alert summary display — bell icon with count badge.

**Props:**
```ts
interface AlertBadgeProps {
  total: number
  critical: number
  warning: number
  variant: 'icon' | 'summary'
}
```

**States:**

| State | Visual |
|-------|--------|
| **No alerts** | Bell icon, no badge dot |
| **Has alerts** | Bell icon + red dot with count (if total > 0) |
| **Critical alerts** | Bell icon + red pulsing dot, critical count shown |
| **Summary variant** | Full stat card: total count + critical/warning breakdown |
| **Edge: large count** | Badge shows `99+` if total > 99 |

**Accessibility:**
- `aria-label` on badge: `"{total} active alerts, {critical} critical"`
- `role="status"` with `aria-live="polite"`

---

## 3. Design System Refinements

### 3.1 Color Token System

The existing CSS already defines good tokens. Standardize usage:

| Token | CSS Variable | Hex | Usage |
|-------|-------------|-----|-------|
| `bg-surface` | `--color-surface` | `#0f172a` | Page background |
| `bg-surface-container` | `--color-surface-container` | `#171f33` | Card backgrounds |
| `bg-surface-container-high` | `--color-surface-container-high` | `#222a3d` | Hover states, elevated surfaces |
| `bg-surface-container-highest` | `--color-surface-container-highest` | `#2d3449` | Modal backgrounds |
| `text-on-surface` | `--color-on-surface` | `#dae2fd` | Primary text |
| `text-on-surface-variant` | `--color-on-surface-variant` | `#bbc9cd` | Secondary text |
| `text-outline` | `--color-outline` | `#859397` | Borders, dividers |
| `text-outline-variant` | `--color-outline-variant` | `#3c494c` | Subtle borders |
| `bg-primary` | `--color-primary` | `#8aebff` | Primary buttons, active states |
| `text-primary` | `--color-primary` | `#8aebff` | Accent text, links |
| `bg-primary-container` | `--color-primary-container` | `#22d3ee` | Primary hover, tab active bg |
| `text-status-success` | `--color-status-success` | `#10b981` | Fresh/healthy indicators |
| `text-status-warning` | `--color-status-warning` | `#f59e0b` | Warning/stale indicators |
| `text-status-danger` | `--color-status-danger` | `#ef4444` | Critical/error indicators |

**Semantic color usage rules:**
- All text on dark surfaces must pass WCAG AA (4.5:1 contrast). The existing palette does this.
- Never use pure white (`#ffffff`) for text — use `#dae2fd` (on-surface) or `#e2e8f0` (body).
- Status colors are used for both text and backgrounds (with opacity modifiers: `/10`, `/20`).

### 3.2 Spacing Scale

Use Tailwind v4 spacing utilities. Standardized component spacing:

| Token | Value | Usage |
|-------|-------|-------|
| `gap-1` | `0.25rem` | Tab groups, inline icon+text |
| `gap-2` | `0.5rem` | Card header elements, button icon+label |
| `gap-3` | `0.75rem` | Between stat cards, form fields |
| `gap-4` | `1rem` | Grid gaps, section spacing |
| `gap-6` | `1.5rem` | Between major sections |
| `p-4` | `1rem` | Card padding (mobile) |
| `p-5` | `1.25rem` | Card padding (desktop) |
| `p-6` | `1.5rem` | Panel padding |
| `px-4 py-3` | - | Button padding |

### 3.3 Typography Hierarchy

| Element | Class | Size | Weight | Line Height |
|---------|-------|------|--------|-------------|
| Page title | `text-headline-lg font-headline-lg` | 20px | 700 | 28px |
| Modal title | `text-headline-md font-headline-md` | 18px | 700 | 24px |
| Sensor value | `text-metric-value font-metric-value` | 30px | 700 | 1.2 |
| Modal hero value | `text-hero-metric font-hero-metric` | 36px | 900 | 1.2 |
| Stat label | `text-xs font-medium uppercase tracking-wider` | 12px | 600 | 16px |
| Card label | `text-sm font-medium` | 14px | 500 | 20px |
| Body text | `text-sm` | 14px | 400 | 20px |
| Metadata | `text-[10px]` | 10px | 500 | 14px |
| Chart labels | `text-[9px]` | 9px | 400 | 12px |

### 3.4 Elevation / Shadow System

| Level | Usage | Shadow |
|-------|-------|--------|
| 0 | Cards (default) | None — border-based separation |
| 1 | Card hover | `0 8px 24px rgba(0, 0, 0, 0.2)` |
| 2 | Modal | `0 25px 50px rgba(0, 0, 0, 0.4)` |
| 3 | Sidebar | `4px 0 24px rgba(0, 0, 0, 0.3)` |
| 4 | Toast/notification | `0 10px 30px rgba(0, 0, 0, 0.4)` |

### 3.5 Border Radius Scale

| Token | Value | Usage |
|-------|-------|-------|
| `rounded-sm` | `0.25rem` | Badges, small indicators |
| `rounded-md` | `0.5rem` | Buttons, tab pills |
| `rounded-lg` | `0.75rem` | Cards, panels |
| `rounded-xl` | `1rem` | Modal content |
| `rounded-2xl` | `1.25rem` | Large modals, dialogs |
| `rounded-full` | `9999px` | Pills, badges, avatars |

### 3.6 Animation Tokens

| Token | Value | Usage |
|-------|-------|-------|
| `duration-fast` | `150ms` | Button active, hover transitions |
| `duration-normal` | `300ms` | Tab switch, fade transitions |
| `duration-slow` | `500ms` | Stagger entrance, sidebar expand |
| `ease-organic` | `cubic-bezier(0.34, 1.56, 0.64, 1)` | Modal spring, card hover lift |
| `ease-out-soft` | `cubic-bezier(0.16, 1, 0.3, 1)` | Stagger entrance, value tweens |
| `ease-in-out-smooth` | `cubic-bezier(0.65, 0, 0.35, 1)` | Sidebar collapse, general transitions |

---

## 4. State Patterns for Every Component

### 4.1 AppLayout.vue

| State | Behavior |
|-------|----------|
| **Loading** | Not applicable (shell renders immediately, child pages handle their own loading) |
| **Empty** | Not applicable |
| **Error** | ErrorBoundary.vue (already implemented) catches render errors |
| **Edge: mobile** | Sidebar hidden, MobileNav shown. Sidebar accessible via overlay. |
| **Edge: slow network** | Sidebar renders immediately, content areas show skeletons |
| **Edge: localStorage unavailable** | Sidebar defaults to expanded, no crash |

### 4.2 SensorCard.vue

| State | Visual |
|-------|--------|
| **Loading** | 3 skeleton lines (label, metric, badge) |
| **Empty** (value=null) | Value `--`, badge `OFFLINE`, slate colors |
| **Error** (hardware) | Red glow border, badge `CHECK WIRING`, red dot |
| **Normal** | Normal card, cyan accent hover |
| **Warning** (status=low) | Amber glow border, badge `Low` |
| **Alert** (status=high) | Red glow border, badge `High` |
| **Edge: NaN value** | Treated as null, shows `--` |
| **Edge: missing profile** | Uses sensor.key as label, no unit suffix |
| **Edge: stale data** | Badge shows `Stale` with amber color (derived from freshness) |
| **Edge: rapid updates** | Value tweens smoothly from old to new (800ms ease-out) |

### 4.3 StatCard.vue

| State | Visual |
|-------|--------|
| **Loading** | `skeleton-text` for label, `skeleton-metric` for value |
| **Empty** (value=null) | Value shows `--`, sublabel and meta hidden |
| **Normal** | Full rendering with icon, value, sublabel, meta |
| **Edge: very long value** | `truncate` class, tooltip on hover |
| **Edge: zero value** | Shows `0` (not empty) — zero is valid data |
| **Edge: negative value** | Shows normally (valid for RSSI, SNR) |

### 4.4 SensorModal.vue

| State | Visual |
|-------|--------|
| **Closed** | Not rendered |
| **Opening** | Spring animation (scale 0.92 -> 1, opacity 0 -> 1) |
| **Loading trend** | Centered spinner in chart area |
| **Trend loaded** | TrendChart with threshold zones |
| **Trend empty** | "No trend data available" centered |
| **Trend error** | Error message + Retry button |
| **Closing** | Scale 0.95, opacity 0 |
| **Edge: sensor prop null** | Title shows "Sensor Details", value shows `--` |
| **Edge: no thresholds** | TrendChart renders without threshold zones |
| **Edge: rapid open/close** | Debounce close to prevent flicker |

### 4.5 TabBar.vue

| State | Visual |
|-------|--------|
| **Normal** | Pill tabs, active highlighted |
| **Edge: single tab** | Renders normally |
| **Edge: empty tabs array** | Renders nothing |
| **Edge: long label** | `whitespace-nowrap` with horizontal scroll on overflow |

### 4.6 DownloadBar.vue

| State | Visual |
|-------|--------|
| **Normal** | Two buttons enabled |
| **Downloading** | Button shows spinner, disabled |
| **Error** | Toast notification (future), button re-enabled |
| **Edge: no sensors** | CSV button disabled with tooltip "No data to export" |
| **Edge: network failure** | Error logged, button re-enabled |

### 4.7 CommunicationPanel.vue

| State | Visual |
|-------|--------|
| **Loading** | 3 skeleton stat cards + skeleton chart |
| **Loaded with data** | Full stats + RSSI bar + SignalChart |
| **Loaded, empty data** | Stats show `--`, chart shows "No signal data" |
| **Error** | Error banner with retry button |
| **Edge: partial stats** | Available stats shown, missing ones show `--` |
| **Edge: single data point** | Chart renders single point (no line) |

### 4.8 AnalyticsPanel.vue

| State | Visual |
|-------|--------|
| **Loading** | Skeleton lines in card panel |
| **Loaded with data** | Grid of stat cards |
| **Loaded, empty** | Empty state with analytics icon |
| **Error** | Error banner with retry |
| **Edge: nested objects** | Values that are objects are JSON-stringified |
| **Edge: very large values** | `truncate` with title tooltip |

### 4.9 ConnectionStatus.vue

| State | Visual |
|-------|--------|
| **Fresh** (<=1 min) | Green dot, "Connected" text |
| **Recent** (<=5 min) | Cyan dot, "Recent" text |
| **Stale** (<=15 min) | Amber dot, "Stale" text |
| **Lost** (>15 min) | Red pulsing dot, "Lost" text |
| **Unknown** (null) | Gray dot, "Unknown" text |
| **Mini variant** | Dot only |
| **Edge: rapid state change** | Color transition is smooth (300ms) |

### 4.10 AlertBadge.vue

| State | Visual |
|-------|--------|
| **No alerts** | Bell icon, no badge |
| **Has alerts** | Bell + red dot with count |
| **Critical alerts** | Red pulsing dot |
| **Summary variant** | Full stat card with breakdown |
| **Edge: count > 99** | Shows `99+` |
| **Edge: only info alerts** | Shows count but no critical/warning breakdown |

---

## 5. Accessibility Requirements

### 5.1 Focus Management

| Component | Requirement |
|-----------|-------------|
| **SensorModal** | Trap focus within modal when open. First focusable element receives focus. Tab cycles through all focusable elements. Escape closes. On close, restore focus to triggering element. |
| **Sidebar** | Nav links are focusable via Tab. Skip link at top to jump to main content. |
| **SensorCard** | `tabindex="0"`, Enter/Space opens modal. Focus visible ring on keyboard nav. |
| **TabBar** | Arrow keys navigate between tabs (Left/Right). Home/End goes to first/last. |
| **DownloadBar** | Buttons are focusable, show focus ring. |
| **Modal overlay** | Click on overlay closes modal (already implemented). |

### 5.2 ARIA Attributes

| Component | Attributes |
|-----------|------------|
| **AppLayout** | `<main>` has `role="main"`, skip link `<a href="#main-content">` |
| **Sidebar** | `role="navigation"`, `aria-label="Main navigation"` |
| **TabBar** | Container: `role="tablist"`, each tab: `role="tab"`, `aria-selected`, `aria-controls="panel-{id}"` |
| **Tab panels** | `role="tabpanel"`, `aria-labelledby="tab-{id}"` |
| **SensorCard** | `role="button"`, `aria-label="{label}: {value} {unit}, status {status}"` |
| **SensorModal** | `role="dialog"`, `aria-modal="true"`, `aria-labelledby="modal-title"` |
| **ConnectionStatus** | `role="status"`, `aria-live="polite"`, `aria-label="Connection: {state}"` |
| **AlertBadge** | `aria-label="{total} active alerts, {critical} critical"` |
| **Error banner** | `role="alert"`, `aria-live="assertive"` |
| **Loading skeletons** | `aria-hidden="true"` (not announced to screen readers) |
| **Spinner** | `role="status"`, `aria-label="Loading"` |

### 5.3 Keyboard Navigation

| Shortcut | Action | Scope |
|----------|--------|-------|
| `Tab` | Move focus to next focusable element | Global |
| `Shift+Tab` | Move focus to previous focusable element | Global |
| `Enter` / `Space` | Activate button, open modal | SensorCard, buttons |
| `Escape` | Close modal, dismiss overlay | SensorModal, mobile sidebar |
| `Ctrl+B` | Toggle sidebar | Global |
| `Left/Right Arrow` | Navigate tabs | TabBar |
| `Home/End` | First/last tab | TabBar |

### 5.4 Color Contrast

All text must meet WCAG AA minimum (4.5:1 for normal text, 3:1 for large text):

| Element | Foreground | Background | Ratio | Status |
|---------|-----------|------------|-------|--------|
| Page title | `#e2e8f0` | `#0f172a` | 12.5:1 | Pass |
| Body text | `#94a3b8` | `#0f172a` | 7.5:1 | Pass |
| Secondary text | `#64748b` | `#0f172a` | 4.7:1 | Pass (AA) |
| Stat value | `#ffffff` | `#1e293b` | 13.7:1 | Pass |
| Disabled text | `#475569` | `#0f172a` | 3.3:1 | Fail — use `#64748b` min |
| Badge text (emerald) | `#34d399` | `#0f172a` | 6.5:1 | Pass |
| Badge text (red) | `#f87171` | `#0f172a` | 6.8:1 | Pass |
| Badge text (amber) | `#fbbf24` | `#0f172a` | 8.8:1 | Pass |

### 5.5 Reduced Motion

- All animations respect `prefers-reduced-motion: reduce`
- When reduced motion is detected:
  - Stagger entrance: all cards appear at once (no delay)
  - Value tweens: instant snap to final value
  - Modal transitions: instant opacity toggle
  - Sidebar: instant expand/collapse
  - Pulse animations: disabled

Implementation:
```css
@media (prefers-reduced-motion: reduce) {
  *, *::before, *::after {
    animation-duration: 0.01ms !important;
    transition-duration: 0.01ms !important;
  }
  .stagger-enter { opacity: 1; transform: none; }
}
```

---

## 6. Responsive Behavior

### 6.1 Breakpoint Strategy

| Breakpoint | Width | Layout |
|------------|-------|--------|
| **Mobile** | `< 640px` | Single column, bottom nav, no sidebar |
| **Tablet** | `640px - 1024px` | 2-column grid, collapsible sidebar |
| **Desktop** | `> 1024px` | 3-column grid, full sidebar |

### 6.2 Mobile (< 640px)

- **Sidebar**: Hidden. Accessible via hamburger overlay (full-screen slide-in).
- **Bottom nav**: Fixed `MobileNav.vue` at bottom, `h-16`, with 4 icons.
- **Sensor grid**: `grid-cols-1`
- **Stat row**: `grid-cols-1`
- **Modal**: Full-screen (`inset-0 m-0 rounded-none max-w-none max-h-none`), close button top-right.
- **Padding**: `p-4`, bottom padding `pb-20` to account for bottom nav.
- **Tab bar**: Horizontal scroll if tabs overflow (`overflow-x-auto`).

### 6.3 Tablet (640px - 1024px)

- **Sidebar**: Collapsible. Default collapsed (`w-16`), expandable to `w-64`.
- **Sensor grid**: `grid-cols-2`
- **Stat row**: `grid-cols-2` (3rd stat spans full width or goes to next row)
- **Modal**: Centered, `max-w-2xl`.
- **Padding**: `p-6`

### 6.4 Desktop (> 1024px)

- **Sidebar**: Full width (`w-64`), always visible.
- **Sensor grid**: `grid-cols-3`
- **Stat row**: `grid-cols-3`
- **Modal**: Centered, `max-w-3xl`.
- **Padding**: `p-8`

### 6.5 Responsive Component Variants

| Component | Mobile | Tablet | Desktop |
|-----------|--------|--------|---------|
| `AppSidebar` | Overlay (hidden by default) | Collapsible `w-16`/`w-64` | Fixed `w-64` |
| `MobileNav` | Visible | Hidden | Hidden |
| `SensorCard` | Full width | Half width | Third width |
| `SensorModal` | Full-screen | Centered modal | Centered modal |
| `StatCard` | Full width | 2 cols | 3 cols |
| `TabBar` | Scrollable | Normal | Normal |

---

## 7. Animation & Micro-interactions

### 7.1 Card Entrance Stagger (Keep Existing)

- **Selector**: `.stagger-enter` / `.stagger-enter.visible`
- **Animation**: translateY(16px) -> translateY(0), opacity 0 -> 1
- **Duration**: 500ms per card
- **Delay**: 60ms between each card (baseDelay + index * 60ms)
- **Easing**: `cubic-bezier(0.16, 1, 0.3, 1)` (ease-out-soft)
- **Trigger**: On first load and on tab switch to Overview
- **Lock**: `staggerLock` ref prevents re-trigger during animation

### 7.2 Value Transition Tweens (Keep Existing, Optimize)

- **Mechanism**: `requestAnimationFrame`-based tween
- **Duration**: 800ms
- **Easing**: `cubic-bezier(0.16, 1, 0.3, 1)` (ease-out-soft) — currently using `1 - (1-t)^3`
- **Optimization**: Only tween when value actually changes (already implemented). Skip tween for null/error values.
- **Future**: Consider moving to a composable `useTween(target, duration)` for reuse.

### 7.3 Page Transitions Between Tabs

- **Wrapper**: `<Transition name="fade" mode="out-in">` around tab content
- **Enter**: opacity 0 -> 1, translateY(10px) -> 0
- **Leave**: opacity 1 -> 0, translateY(0) -> -4px
- **Duration**: 300ms
- **Easing**: `cubic-bezier(0.65, 0, 0.35, 1)` for opacity, `cubic-bezier(0.16, 1, 0.3, 1)` for transform

### 7.4 Sidebar Expand/Collapse

- **Trigger**: Hamburger button click, `Ctrl+B` keyboard shortcut
- **Animation**: Width transition `w-64` <-> `w-16`
- **Duration**: 300ms
- **Easing**: `cubic-bezier(0.65, 0, 0.35, 1)`
- **Content**: Icons remain visible when collapsed, labels fade out with `overflow-hidden`
- **Mobile overlay**: Fade in/out with 200ms

### 7.5 Modal Open/Close with Spring Easing

- **Overlay**: Fade in/out, 300ms
- **Content**: Scale 0.92 -> 1 (open), 1 -> 0.95 (close)
- **Open easing**: `cubic-bezier(0.34, 1.56, 0.64, 1)` (spring-like overshoot)
- **Close easing**: `cubic-bezier(0.65, 0, 0.35, 1)` (smooth out)
- **Duration**: 350ms open, 200ms close

### 7.6 Status Indicator Pulse Animations

- **Fresh (green)**: `pulse-glow` — 2s infinite, green glow
- **Lost (red)**: `pulse-glow-danger` — 1.5s infinite, red glow
- **Warning (amber)**: `pulse-glow-amber` — 2s infinite, amber glow
- **Implementation**: CSS keyframes (already defined in app.css)

### 7.7 Card Hover/Active Micro-interactions

- **Hover**: translateY(-2px), enhanced border glow, 200ms ease-organic
- **Active**: scale(0.97), 150ms ease-organic
- **Stat card hover**: Border lightens, subtle shadow, 300ms ease-in-out-smooth

### 7.8 Skeleton Shimmer

- **Animation**: `shimmer` keyframes (background-position 200% -> -200%)
- **Duration**: 1.8s
- **Easing**: `cubic-bezier(0.65, 0, 0.35, 1)`
- **Gradient**: `#1e293b 25% -> #334155 40% -> #1e293b 55%`

---

## 8. Implementation Order

### Phase 1: Foundation (Day 1)

1. Create `resources/js/Composables/` directory
2. Create `useConnectionStatus.js` — composable for polling + connection state
3. Create `useTween.js` — composable for value tweening (extracted from Overview.vue)
4. Create `useStagger.js` — composable for stagger entrance animation
5. Create `resources/js/Layouts/AppLayout.vue` — shell with sidebar + header
6. Create `resources/js/Components/AppSidebar.vue`
7. Create `resources/js/Components/AppHeader.vue`
8. Create `resources/js/Components/MobileNav.vue`
9. Update `resources/js/app.js` to use AppLayout as default layout
10. Update `resources/css/app.css` with new utility classes

### Phase 2: Core Components (Day 2)

1. Create `resources/js/Components/StatCard.vue`
2. Create `resources/js/Components/SensorCard.vue`
3. Create `resources/js/Components/TabBar.vue`
4. Create `resources/js/Components/DownloadBar.vue`
5. Create `resources/js/Components/ConnectionStatus.vue`
6. Create `resources/js/Components/AlertBadge.vue`

### Phase 3: Tab Panels (Day 3)

1. Create `resources/js/Components/CommunicationPanel.vue`
2. Create `resources/js/Components/AnalyticsPanel.vue`
3. Create `resources/js/Components/SensorModal.vue`
4. Refactor `resources/js/Pages/Dashboard/Overview.vue` to use all new components

### Phase 4: Polish (Day 4)

1. Add `prefers-reduced-motion` support
2. Audit all ARIA attributes and keyboard navigation
3. Test responsive behavior at all breakpoints
4. Add page transition animations
5. Final accessibility audit

---

## Appendix A: File Structure After Implementation

```
resources/js/
├── app.js
├── design-plan.md                          ← this document
├── Composables/
│   ├── useConnectionStatus.js
│   ├── useTween.js
│   └── useStagger.js
├── Components/
│   ├── ErrorBoundary.vue
│   ├── AppSidebar.vue
│   ├── AppHeader.vue
│   ├── MobileNav.vue
│   ├── StatCard.vue
│   ├── SensorCard.vue
│   ├── TabBar.vue
│   ├── DownloadBar.vue
│   ├── ConnectionStatus.vue
│   ├── AlertBadge.vue
│   ├── CommunicationPanel.vue
│   ├── AnalyticsPanel.vue
│   └── SensorModal.vue
├── Layouts/
│   └── AppLayout.vue
├── Pages/
│   └── Dashboard/
│       ├── Overview.vue                    ← refactored (significantly smaller)
│       ├── SignalChart.vue                 ← unchanged
│       └── TrendChart.vue                  ← unchanged
└── css/
    └── app.css                             ← extended with new utilities
```

## Appendix B: Data Flow Diagram

```
Inertia (server-side props)
  │
  ▼
Overview.vue (page component)
  │
  ├── Props passed to children:
  │   ├── StatCard ← health, freshness, alerts data
  │   ├── SensorCard[] ← sensors array (computed with profiles)
  │   ├── DownloadBar ← sensors array
  │   ├── CommunicationPanel ← signalStats, signalData, signalRange
  │   ├── AnalyticsPanel ← analyticsData
  │   └── SensorModal ← selected sensor, trendData
  │
  ├── Internal state:
  │   ├── activeTab, selectedRange, signalRange, modalRange
  │   ├── latest, sensors, alerts, signal, health
  │   ├── trendData, signalData, analyticsData
  │   ├── loading flags (signalLoading, analyticsLoading, modalLoading)
  │   ├── error flags (sensorError)
  │   └── modal state (modalOpen, modalSensor)
  │
  └── Polling:
      ├── pollDashboard() → 30s interval
      ├── fetchTrends() → on modal open / range change
      ├── fetchSignalData() → on tab switch to Communication / range change
      └── fetchAnalytics() → on tab switch to Analytics
```

## Appendix C: Composable Specifications

### `useConnectionStatus.js`
```ts
interface UseConnectionStatusReturn {
  connectionStatus: ComputedRef<'connected' | 'degraded' | 'disconnected'>
  freshnessMinutes: ComputedRef<number | null>
  isStale: ComputedRef<boolean>
  isFresh: ComputedRef<boolean>
  lastUpdated: Ref<string>
  pollDashboard: () => Promise<void>
}
```

### `useTween.js`
```ts
interface UseTweenReturn {
  tweenedValues: Reactive<Record<string, number>>
  startTween: (key: string, from: number, to: number, duration?: number) => void
  cancelAll: () => void
}
```

### `useStagger.js`
```ts
interface UseStaggerReturn {
  visibleIndices: Ref<Set<number>>
  triggerStagger: (count: number, baseDelay?: number) => void
  isVisible: (index: number) => boolean
  isAnimating: ComputedRef<boolean>
}
```
