import { createApp, h } from 'vue'
import { createInertiaApp } from '@inertiajs/inertia-vue3'
import { resolvePageComponent } from 'laravel-vite-plugin/inertia-helpers'
import ErrorBoundary from './Components/ErrorBoundary.vue'
import AppLayout from './Layouts/AppLayout.vue'
import './css/app.css'

createInertiaApp({
    resolve: (name) => {
        const page = resolvePageComponent(
            './Pages/' + name + '.vue',
            import.meta.glob('./Pages/**/*.vue')
        )
        return page.then((module) => {
            const pageComponent = module.default
            // Use AppLayout as default layout if page doesn't define its own
            pageComponent.layout = pageComponent.layout || AppLayout
            return module
        })
    },
    setup({ el, App, props, plugin }) {
        const app = createApp({
            render: () => h(ErrorBoundary, () => h(App, props)),
        })
        app.use(plugin)
        app.config.errorHandler = (err, instance, info) => {
            console.error('[Global Vue Error]', err, info)
        }
        app.mount(el)
    },
})
