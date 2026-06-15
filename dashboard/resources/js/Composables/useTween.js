import { shallowRef } from 'vue'

/**
 * useTween composable
 * Provides requestAnimationFrame-based value tweening.
 * Uses shallowRef to avoid deep reactivity overhead on every animation frame.
 * Cancels previous tween for the same key before starting a new one.
 */
export function useTween() {
  const tweenedValues = shallowRef({})
  const activeTweens = new Map()

  function startTween(key, from, to, duration = 800) {
    // Cancel existing tween for this key to prevent concurrent animations
    if (activeTweens.has(key)) {
      cancelAnimationFrame(activeTweens.get(key))
      activeTweens.delete(key)
    }

    const start = performance.now()
    const delta = to - from

    const step = (now) => {
      const elapsed = now - start
      const t = Math.min(elapsed / duration, 1)
      const eased = 1 - Math.pow(1 - t, 3)
      tweenedValues.value = { ...tweenedValues.value, [key]: from + delta * eased }
      if (t < 1) {
        activeTweens.set(key, requestAnimationFrame(step))
      } else {
        activeTweens.delete(key)
        tweenedValues.value = { ...tweenedValues.value, [key]: to }
      }
    }
    activeTweens.set(key, requestAnimationFrame(step))
  }

  function cancelAll() {
    for (const [, frameId] of activeTweens) {
      cancelAnimationFrame(frameId)
    }
    activeTweens.clear()
  }

  return {
    tweenedValues,
    startTween,
    cancelAll,
  }
}
