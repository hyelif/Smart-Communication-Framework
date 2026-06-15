<script setup>
import { ref, onMounted, onUnmounted, computed } from 'vue'
import { usePage } from '@inertiajs/inertia-vue3'
import AppSidebar from '../Components/AppSidebar.vue'
import AppHeader from '../Components/AppHeader.vue'
import MobileNav from '../Components/MobileNav.vue'

const { component } = usePage()

const sidebarCollapsed = ref(false)
const mobileNavOpen = ref(false)

const pageTitle = computed(() => {
  const comp = component.value || ''
  if (comp.includes('Dashboard')) return 'Dashboard'
  return 'Dashboard'
})

const sharedProps = computed(() => {
  const page = usePage()
  return page.props?.value || {}
})

const lastUpdated = computed(() => sharedProps.value.lastUpdated || null)
const connectionStatus = computed(() => sharedProps.value.connectionStatus || 'disconnected')
const alertCount = computed(() => sharedProps.value.alertCount || 0)
const freshnessMinutes = computed(() => sharedProps.value.freshnessMinutes ?? null)

function toggleMobileSidebar() {
  mobileNavOpen.value = !mobileNavOpen.value
}

function closeMobileSidebar() {
  mobileNavOpen.value = false
}

function handleKeydown(e) {
  if (e.ctrlKey && e.key === 'b') {
    e.preventDefault()
    sidebarCollapsed.value = !sidebarCollapsed.value
    try {
      localStorage.setItem('sidebarCollapsed', String(sidebarCollapsed.value))
    } catch { /* localStorage unavailable */ }
  }
  if (e.key === 'Escape' && mobileNavOpen.value) {
    mobileNavOpen.value = false
  }
}

let resizeHandler = null

onMounted(() => {
  try {
    const saved = localStorage.getItem('sidebarCollapsed')
    if (saved !== null) {
      sidebarCollapsed.value = saved === 'true'
    }
  } catch { /* localStorage unavailable */ }

  resizeHandler = () => {
    if (window.innerWidth < 768) {
      sidebarCollapsed.value = false
      mobileNavOpen.value = false
    }
  }
  window.addEventListener('resize', resizeHandler)
  document.addEventListener('keydown', handleKeydown)
})

onUnmounted(() => {
  if (resizeHandler) window.removeEventListener('resize', resizeHandler)
  document.removeEventListener('keydown', handleKeydown)
})
</script>

<template>
  <div class="flex h-screen bg-surface overflow-hidden">
    <!-- Skip link -->
    <a
      href="#main-content"
      class="sr-only focus:not-sr-only focus:fixed focus:top-4 focus:left-4 focus:z-60 focus:px-4 focus:py-2 focus:bg-primary focus:text-on-primary focus:rounded-md focus:text-sm focus:font-semibold"
    >
      Skip to main content
    </a>

    <!-- Desktop sidebar -->
    <AppSidebar
      :collapsed="sidebarCollapsed"
      :current-route="component"
      :freshness-minutes="freshnessMinutes"
      class="hidden md:flex"
      @toggle-collapse="sidebarCollapsed = !sidebarCollapsed"
    />

    <!-- Mobile sidebar overlay -->
    <Transition name="fade">
      <div
        v-if="mobileNavOpen"
        class="fixed inset-0 bg-black/50 z-30 md:hidden"
        @click="closeMobileSidebar"
      />
    </Transition>

    <!-- Mobile sidebar panel -->
    <Transition name="slide-right">
      <AppSidebar
        v-if="mobileNavOpen"
        class="fixed left-0 top-0 z-40 h-full md:hidden"
        :current-route="component"
        :freshness-minutes="freshnessMinutes"
        @toggle-collapse="closeMobileSidebar"
      />
    </Transition>

    <!-- Main area -->
    <div class="flex-1 flex flex-col min-w-0">
      <AppHeader
        :title="pageTitle"
        :last-updated="lastUpdated"
        :connection-status="connectionStatus"
        :alert-count="alertCount"
        :freshness-minutes="freshnessMinutes"
        @toggle-sidebar="toggleMobileSidebar"
      />

      <main
        id="main-content"
        role="main"
        class="flex-1 overflow-y-auto p-5 md:p-7 lg:p-8 pb-20 md:pb-7 lg:pb-8"
      >
        <div class="max-w-7xl mx-auto">
          <Transition name="page" mode="out-in">
            <slot :key="$page.url" />
          </Transition>
        </div>
      </main>
    </div>

    <!-- Mobile bottom nav -->
    <MobileNav
      :current-route="component"
      :alert-count="alertCount"
      class="md:hidden"
    />
  </div>
</template>
