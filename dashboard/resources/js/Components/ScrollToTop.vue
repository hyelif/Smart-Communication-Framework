<script setup>
import { ref, onMounted, onUnmounted } from 'vue'

const visible = ref(false)
let scrollHandler = null

onMounted(() => {
  scrollHandler = () => {
    const scrollY = window.scrollY || document.querySelector('main')?.scrollTop || 0
    visible.value = scrollY > 300
  }
  document.querySelector('main')?.addEventListener('scroll', scrollHandler)
})

onUnmounted(() => {
  if (scrollHandler) document.querySelector('main')?.removeEventListener('scroll', scrollHandler)
})

function scrollToTop() {
  document.querySelector('main')?.scrollTo({ top: 0, behavior: 'smooth' })
}
</script>

<template>
  <Teleport to="body">
    <button
      :class="['scroll-top-btn material-symbols-outlined', { visible }]"
      @click="scrollToTop"
      aria-label="Scroll to top"
      title="Scroll to top"
    >arrow_upward</button>
  </Teleport>
</template>
