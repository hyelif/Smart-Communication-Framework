import { ref, computed } from 'vue'

/**
 * useStagger composable
 * Manages staggered entrance animation for card grids.
 * Tracks setTimeout IDs for proper cleanup on unmount.
 */
export function useStagger() {
  const visibleIndices = ref(new Set())
  const staggerLock = ref(false)
  const staggerTimeouts = new Set()

  function triggerStagger(count, baseDelay = 60) {
    if (staggerLock.value) return
    staggerLock.value = true
    visibleIndices.value = new Set()
    for (let i = 0; i < count; i++) {
      const delay = baseDelay + i * 60
      const id = setTimeout(() => {
        staggerTimeouts.delete(id)
        visibleIndices.value = new Set([...visibleIndices.value, i])
        if (i === count - 1) {
          staggerLock.value = false
        }
      }, delay)
      staggerTimeouts.add(id)
    }
  }

  function cancelAll() {
    for (const id of staggerTimeouts) {
      clearTimeout(id)
    }
    staggerTimeouts.clear()
    staggerLock.value = false
  }

  function isVisible(index) {
    return visibleIndices.value.has(index)
  }

  const isAnimating = computed(() => staggerLock.value)

  return {
    visibleIndices,
    triggerStagger,
    isVisible,
    isAnimating,
    cancelAll,
  }
}
