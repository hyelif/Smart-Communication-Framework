import { ref } from 'vue'

const activeGlobalTab = ref('overview')

export function useTabNavigation() {
  function setActiveTab(tab) {
    activeGlobalTab.value = tab
  }

  return {
    activeGlobalTab,
    setActiveTab,
  }
}
