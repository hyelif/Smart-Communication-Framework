<?php

namespace App\Http\Middleware;

use Illuminate\Http\Request;
use Illuminate\Support\Facades\App;
use Inertia\Middleware;

class HandleInertiaRequests extends Middleware
{
    /**
     * The root template that's loaded on the first page visit.
     *
     * @see https://inertiajs.com/server-side-setup#root-template
     *
     * @var string
     */
    protected $rootView = 'app';

    /**
     * Pin the asset version to the manifest file's mtime so Inertia
     * doesn't trigger a full-page reload on every poll cycle when
     * the manifest is read fresh each time.
     */
    public function version(Request $request): ?string
    {
        if (App::environment('local')) {
            $manifest = public_path('build/manifest.json');
            if (file_exists($manifest)) {
                return 'v1.' . filemtime($manifest);
            }
        }
        return parent::version($request);
    }

    /**
     * Define the props that are shared by default.
     *
     * @see https://inertiajs.com/shared-data
     *
     * @return array<string, mixed>
     */
    public function share(Request $request): array
    {
        return array_merge(parent::share($request), [
            //
        ]);
    }
}
