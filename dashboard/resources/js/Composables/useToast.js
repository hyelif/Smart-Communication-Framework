import { ref, shallowRef } from 'vue'

const toasts = shallowRef([])
let nextId = 0

export function useToast() {
  function addToast(message, type = 'info', duration = null) {
    const id = ++nextId
    const toast = { id, message, type, duration: duration || (type === 'error' ? 6000 : 3000), visible: false }
    toasts.value = [...toasts.value, toast]

    setTimeout(() => {
      const t = toasts.value.find(t => t.id === id)
      if (t) t.visible = true
      toasts.value = [...toasts.value]
    }, 50)

    setTimeout(() => removeToast(id), toast.duration)
    return id
  }

  function removeToast(id) {
    const t = toasts.value.find(t => t.id === id)
    if (t) t.visible = false
    toasts.value = [...toasts.value]
    setTimeout(() => {
      toasts.value = toasts.value.filter(t => t.id !== id)
    }, 350)
  }

  return { toasts, addToast, removeToast }
}
