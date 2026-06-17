#!/usr/bin/env bash
# SmartPonic — Render.com startup script
set -e

echo "=== SmartPonic Dashboard — Starting ==="

# Install PHP dependencies
echo "→ Installing Composer dependencies..."
composer install --no-dev --optimize-autoloader --no-interaction

# Cache Laravel configs for production
echo "→ Caching Laravel configs..."
php artisan config:cache
php artisan route:cache
php artisan view:cache

# Run pending migrations (if any)
echo "→ Running migrations..."
php artisan migrate --force

# Start PHP built-in server (Render sets $PORT)
PORT=${PORT:-8000}
echo "→ Starting server on 0.0.0.0:${PORT}"
php artisan serve --host=0.0.0.0 --port=${PORT}
