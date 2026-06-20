# SmartPonic v2 — Cloud Migration Plan

## Overview

Migrate SmartPonic v2 from localhost (XAMPP + MySQL) to cloud services.

| Component | Current | Target | Status |
|-----------|---------|--------|--------|
| **Database** | MySQL (local XAMPP) | **Turso** (libSQL/SQLite-based, serverless) | ✅ Done |
| **Backend API** | Standalone PHP (local Apache) | **Laravel controllers** (merged into dashboard app) | ✅ Done |
| **Dashboard** | Laravel + Vue SPA (local artisan) | **Render.com** (deployed web service) | ✅ Done |
| **ESP32 → Cloud** | LoRa → HQ Gateway → localhost | LoRa → HQ Gateway → **Render.com URL** | 🔧 Code updated, not yet flashed |
| **Telegram Bot** | PHP poll script (local) | **Render.com** (background worker or cron) | 🔧 Artisan command created, not deployed |
| **Version Control** | Local only | **GitHub** (private repo) | ✅ Done |

---

## Phase 1: Turso Database Setup ✅

| Task | Status |
|------|--------|
| Turso account & database created | ✅ Done |
| Schema converted & tables created | ✅ Done |
| Seed data inserted (profiles, settings) | ✅ Done |
| Historical data migrated (693 readings, 1,155 data points) | ⚠️ Partial |

### 1.1 Create Turso Account & Database

```bash
# Install Turso CLI
curl -sSfL https://get.turso.tech/install.sh | sh

# Login
turso auth login

# Create database
turso db create smartponic-db

# Get connection details
turso db show --url smartponic-db        # → libsql://smartponic-db-org.turso.io
turso db tokens create smartponic-db     # → long auth token
```

Save these credentials:
- **Database URL**: `libsql://smartponic-db-org.turso.io`
- **Auth Token**: (the long token generated above)

### 1.2 Convert MySQL Schema → SQLite-Compatible

Turso uses libSQL (a SQLite fork). Key differences from MySQL:

| MySQL Feature | SQLite Equivalent |
|---------------|-------------------|
| `AUTO_INCREMENT` | `INTEGER PRIMARY KEY AUTOINCREMENT` |
| `VARCHAR(n)` | `TEXT` |
| `DECIMAL(10,2)` | `REAL` |
| `ENUM('a','b','c')` | `TEXT CHECK(value IN ('a','b','c'))` |
| `TIMESTAMP DEFAULT CURRENT_TIMESTAMP` | `TEXT DEFAULT (datetime('now'))` |
| `ON UPDATE CURRENT_TIMESTAMP` | Use trigger |
| `FOREIGN KEY ... REFERENCES` | Supported, enable with `PRAGMA foreign_keys = ON` |
| `INDEX` | Same syntax |
| `ENGINE=InnoDB` | Remove (not applicable) |

### 1.3 Create Tables in Turso

Run the converted schema via Turso CLI:

```bash
# Pipe the schema file to Turso
turso db shell smartponic-db < database/schema_turso.sql
```

**Converted schema** (`database/schema_turso.sql`):

```sql
PRAGMA foreign_keys = ON;

-- Nodes registry
CREATE TABLE IF NOT EXISTS nodes (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    hardware_id TEXT NOT NULL UNIQUE,
    name        TEXT DEFAULT NULL,
    location    TEXT DEFAULT NULL,
    first_seen  TEXT DEFAULT (datetime('now')),
    last_seen   TEXT DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_nodes_hardware_id ON nodes(hardware_id);

-- Main sensor readings (one row per telemetry packet)
CREATE TABLE IF NOT EXISTS sensor_readings (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    hardware_id TEXT NOT NULL,
    rssi        INTEGER DEFAULT NULL,
    snr         REAL DEFAULT NULL,
    event_type  TEXT DEFAULT 'telemetry',
    priority    TEXT DEFAULT 'LOW',
    report_mode TEXT DEFAULT 'NORMAL',
    created_at  TEXT DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_sr_hardware_id ON sensor_readings(hardware_id);
CREATE INDEX IF NOT EXISTS idx_sr_created_at ON sensor_readings(created_at);
CREATE INDEX IF NOT EXISTS idx_sr_hw_created ON sensor_readings(hardware_id, created_at);

-- Individual sensor data points
CREATE TABLE IF NOT EXISTS sensor_data (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    reading_id  INTEGER NOT NULL,
    pin         INTEGER NOT NULL,
    sensor      TEXT NOT NULL,
    value       TEXT NOT NULL,
    created_at  TEXT DEFAULT (datetime('now')),
    FOREIGN KEY (reading_id) REFERENCES sensor_readings(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_sd_sensor ON sensor_data(sensor);
CREATE INDEX IF NOT EXISTS idx_sd_reading_id ON sensor_data(reading_id);

-- Invalid sensor readings log
CREATE TABLE IF NOT EXISTS invalid_sensor_data (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    hardware_id TEXT NOT NULL,
    pin         INTEGER NOT NULL,
    sensor      TEXT NOT NULL,
    value       TEXT NOT NULL,
    reason      TEXT DEFAULT NULL,
    created_at  TEXT DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_inv_hardware_id ON invalid_sensor_data(hardware_id);
CREATE INDEX IF NOT EXISTS idx_inv_created_at ON invalid_sensor_data(created_at);

-- Relay command queue
CREATE TABLE IF NOT EXISTS relay_commands (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    hardware_id TEXT NOT NULL,
    relay_id    INTEGER NOT NULL,
    action      TEXT NOT NULL DEFAULT 'OFF',
    status      TEXT NOT NULL DEFAULT 'pending'
                CHECK(status IN ('pending','approved','sent','done','failed')),
    created_at  TEXT DEFAULT (datetime('now')),
    updated_at  TEXT DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_rc_hardware_id ON relay_commands(hardware_id);
CREATE INDEX IF NOT EXISTS idx_rc_status ON relay_commands(status);
CREATE INDEX IF NOT EXISTS idx_rc_hw_status ON relay_commands(hardware_id, status);

-- Sensor profiles (calibration + thresholds)
CREATE TABLE IF NOT EXISTS sensor_profiles (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    sensor_key      TEXT NOT NULL UNIQUE,
    label           TEXT NOT NULL,
    unit            TEXT NOT NULL DEFAULT '',
    family          TEXT DEFAULT '',
    accent          TEXT DEFAULT '#9ecaff',
    threshold_min   REAL DEFAULT NULL,
    threshold_max   REAL DEFAULT NULL,
    calibration_a   REAL DEFAULT 1.0,
    calibration_b   REAL DEFAULT 0.0,
    calibration_c   REAL DEFAULT 0.0,
    cal_label_a     TEXT DEFAULT 'Scale',
    cal_label_b     TEXT DEFAULT 'Offset',
    cal_label_c     TEXT DEFAULT 'Reserve',
    updated_at      TEXT DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_sp_sensor_key ON sensor_profiles(sensor_key);

-- Dashboard settings key-value store
CREATE TABLE IF NOT EXISTS dashboard_settings (
    setting_key   TEXT PRIMARY KEY,
    setting_value TEXT NOT NULL,
    updated_at    TEXT DEFAULT (datetime('now'))
);

-- Alerts
CREATE TABLE IF NOT EXISTS alerts (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    hardware_id TEXT NOT NULL,
    sensor_key  TEXT NOT NULL,
    severity    TEXT NOT NULL DEFAULT 'warning'
                CHECK(severity IN ('info','warning','critical')),
    message     TEXT NOT NULL,
    status      TEXT NOT NULL DEFAULT 'active'
                CHECK(status IN ('active','acknowledged','resolved')),
    created_at  TEXT DEFAULT (datetime('now')),
    updated_at  TEXT DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_al_hw_status ON alerts(hardware_id, status);
CREATE INDEX IF NOT EXISTS idx_al_created_at ON alerts(created_at);

-- Pending approvals
CREATE TABLE IF NOT EXISTS pending_approvals (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    command_id   INTEGER NOT NULL DEFAULT 0,
    hardware_id  TEXT NOT NULL,
    relay_id     INTEGER NOT NULL,
    action       TEXT NOT NULL,
    trigger_value REAL DEFAULT NULL,
    status       TEXT NOT NULL DEFAULT 'pending'
                 CHECK(status IN ('pending','approved','cancelled','expired')),
    chat_id      INTEGER DEFAULT NULL,
    created_at   TEXT DEFAULT (datetime('now')),
    expires_at   TEXT DEFAULT NULL
);
CREATE INDEX IF NOT EXISTS idx_pa_status ON pending_approvals(status);
CREATE INDEX IF NOT EXISTS idx_pa_hardware_id ON pending_approvals(hardware_id);

-- Communication health
CREATE TABLE IF NOT EXISTS communication_health (
    id               INTEGER PRIMARY KEY AUTOINCREMENT,
    hardware_id      TEXT NOT NULL UNIQUE,
    delivery_rate    REAL DEFAULT 100.0,
    total_expected   INTEGER DEFAULT 0,
    total_received   INTEGER DEFAULT 0,
    sequence_gaps    INTEGER DEFAULT 0,
    freshness_seconds INTEGER DEFAULT 0,
    last_rssi        INTEGER DEFAULT NULL,
    last_snr         REAL DEFAULT NULL,
    updated_at       TEXT DEFAULT (datetime('now'))
);

-- Telegram bot state
CREATE TABLE IF NOT EXISTS telegram_bot_state (
    state_key   TEXT PRIMARY KEY,
    state_value TEXT NOT NULL,
    updated_at  TEXT DEFAULT (datetime('now'))
);

-- Telegram alert cooldown state
CREATE TABLE IF NOT EXISTS telegram_alert_state (
    state_key    TEXT PRIMARY KEY,
    last_sent_at TEXT DEFAULT NULL,
    updated_at   TEXT DEFAULT (datetime('now'))
);

-- Triggers for updated_at
CREATE TRIGGER IF NOT EXISTS trg_relay_commands_updated
    AFTER UPDATE ON relay_commands
    FOR EACH ROW
BEGIN
    UPDATE relay_commands SET updated_at = datetime('now') WHERE id = OLD.id;
END;

CREATE TRIGGER IF NOT EXISTS trg_alerts_updated
    AFTER UPDATE ON alerts
    FOR EACH ROW
BEGIN
    UPDATE alerts SET updated_at = datetime('now') WHERE id = OLD.id;
END;

CREATE TRIGGER IF NOT EXISTS trg_nodes_last_seen
    AFTER UPDATE ON nodes
    FOR EACH ROW
BEGIN
    UPDATE nodes SET last_seen = datetime('now') WHERE id = OLD.id;
END;
```

### 1.4 Seed Default Data

```bash
turso db shell smartponic-db < database/seed_turso.sql
```

**Seed data** (`database/seed_turso.sql`):

```sql
-- Default sensor profiles
INSERT OR IGNORE INTO sensor_profiles (sensor_key, label, unit, family, accent, threshold_min, threshold_max, calibration_a, calibration_b, cal_label_a, cal_label_b) VALUES
('temperature', 'Temperature', 'C', 'DHT22', '#fce442', 22, 34, 1, 0, 'Scale', 'Offset'),
('humidity', 'Humidity', '%', 'DHT22', '#00fbfb', 45, 85, 1, 0, 'Scale', 'Offset'),
('waterTemp', 'Water Temp', 'C', 'Water Temperature', '#1e95f2', 20, 30, 1, 0, 'Scale', 'Offset'),
('ph', 'pH', 'pH', 'Water Quality', '#9ecaff', 5.8, 7.2, 1, 0, 'Slope', 'Offset'),
('tds', 'TDS', 'ppm', 'Water Quality', '#5cf2b5', 300, 1200, 1, 0, 'Multiplier', 'Offset'),
('turbidity', 'Turbidity', 'NTU', 'Water Quality', '#ffa94d', 0, 120, 1, 0, 'Scale', 'Offset'),
('rain', 'Rain', 'state', 'Environment', '#ff7aa2', NULL, NULL, 1, 0, 'Scale', 'Offset');

-- Default dashboard settings
INSERT OR IGNORE INTO dashboard_settings (setting_key, setting_value) VALUES
('retention_policy', 'keep_forever'),
('export_format', 'excel'),
('default_range', '24h'),
('alert_notifications', 'dashboard_only');
```

---

## Phase 2: Backend Migration (PHP → Laravel) ✅

| Task | Status |
|------|--------|
| ReceiveDataController created | ✅ Done |
| ControlQueueController created | ✅ Done |
| API routes registered | ✅ Done |
| DashboardController → TursoService | ✅ Done |
| ExportController → TursoService | ✅ Done |
| Zero `DB::` references in `app/` | ✅ Done |
| TursoService uses `env()` (no config:cache) | ✅ Done |

### 2.1 Install Turso Laravel Driver

```bash
cd dashboard

# Install the official Turso Laravel package
composer require turso/libsql-laravel

# Publish config (if needed)
php artisan vendor:publish --provider="Turso\LibSQL\LibSQLServiceProvider"
```

### 2.2 Configure Database Connection

**`config/database.php`** — add the `libsql` connection:

```php
'libsql' => [
    'driver' => 'libsql',
    'url' => env('TURSO_DATABASE_URL'),
    'password' => env('TURSO_AUTH_TOKEN'),
],
```

**`.env`** — update database settings:

```env
DB_CONNECTION=libsql
TURSO_DATABASE_URL=libsql://smartponic-db-org.turso.io
TURSO_AUTH_TOKEN=your-auth-token-here

# Remove old MySQL settings
# DB_HOST=127.0.0.1
# DB_DATABASE=smartponic
# DB_USERNAME=root
# DB_PASSWORD=
```

### 2.3 Create ReceiveData Controller

Convert `PHP/receive_data.php` into a Laravel controller:

**`app/Http/Controllers/Api/ReceiveDataController.php`**:

```php
<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;

class ReceiveDataController extends Controller
{
    public function __invoke(Request $request)
    {
        // 1. Validate HTTP method
        if (!$request->isMethod('post')) {
            return response()->json(['error' => 'Method not allowed'], 405);
        }

        // 2. Validate headers
        $apiKey    = $request->header('X-API-Key', '');
        $timestamp = $request->header('X-Timestamp', '');
        $signature = $request->header('X-Signature', '');

        if ($apiKey !== env('SMARTPONIC_API_KEY', 'smartponic-hq-key')) {
            return response()->json(['error' => 'Invalid API key'], 401);
        }

        if (!is_numeric($timestamp)) {
            return response()->json(['error' => 'Invalid timestamp'], 400);
        }

        $ts = (int)$timestamp;
        $maxAge = (int)env('SMARTPONIC_REQUEST_MAX_AGE', 300);
        if ($ts > 1700000000 && abs(time() - $ts) > $maxAge) {
            return response()->json(['error' => 'Timestamp out of window'], 401);
        }

        // 3. Verify body + signature
        $rawBody = $request->getContent();
        if (empty($rawBody)) {
            return response()->json(['error' => 'Empty request body'], 400);
        }

        $hmacSecret = env('SMARTPONIC_HMAC_SECRET', 'smartponic-hq-signature-secret');
        $expectedSig = hash('sha256', $timestamp . $rawBody . $hmacSecret);
        if (!hash_equals($expectedSig, $signature)) {
            return response()->json(['error' => 'Invalid signature'], 401);
        }

        // 4. Parse JSON
        $data = json_decode($rawBody, true);
        if ($data === null) {
            return response()->json(['error' => 'Invalid JSON'], 400);
        }

        $hardwareId  = $data['hardware_id'] ?? '';
        $rssi        = isset($data['rssi'])       ? (int)$data['rssi']       : null;
        $snr         = isset($data['snr'])        ? (float)$data['snr']      : null;
        $eventType   = $data['event_type']        ?? 'telemetry';
        $sensors     = $data['sensors']            ?? [];
        $priorityIdx = isset($data['priority'])    ? (int)$data['priority']   : 0;
        $reportModeIdx = isset($data['report_mode']) ? (int)$data['report_mode'] : 0;

        $priorityMap   = [0 => 'LOW', 1 => 'MEDIUM', 2 => 'HIGH'];
        $reportModeMap = [0 => 'NORMAL', 1 => 'ABNORMAL', 2 => 'CRITICAL'];
        $priorityStr   = $priorityMap[$priorityIdx]   ?? 'LOW';
        $reportModeStr = $reportModeMap[$reportModeIdx] ?? 'NORMAL';

        if (!preg_match('/^[0-9A-F]{16}$/', $hardwareId)) {
            return response()->json(['error' => 'Invalid hardware_id format'], 400);
        }

        if (!is_array($sensors) || count($sensors) === 0) {
            return response()->json(['error' => 'Missing or empty sensors array'], 400);
        }

        if (count($sensors) > 32) {
            return response()->json(['error' => 'Too many sensors (max 32)'], 400);
        }

        // 5. Process
        try {
            DB::beginTransaction();

            // Auto-register node
            DB::table('nodes')->insertOrIgnore(['hardware_id' => $hardwareId]);
            DB::table('nodes')->where('hardware_id', $hardwareId)
              ->update(['last_seen' => DB::raw("datetime('now')")]);

            // Insert sensor_readings
            $readingId = DB::table('sensor_readings')->insertGetId([
                'hardware_id' => $hardwareId,
                'rssi'        => $rssi,
                'snr'         => $snr,
                'event_type'  => $eventType,
                'priority'    => $priorityStr,
                'report_mode' => $reportModeStr,
            ]);

            $validCount   = 0;
            $invalidCount = 0;

            foreach ($sensors as $s) {
                $pin    = (int)($s['pin']    ?? 0);
                $sensor =      $s['sensor']  ?? '';
                $value  =      $s['value']   ?? '';

                if ($pin === 0 || $sensor === '' || $value === '') {
                    continue;
                }

                $reason = $this->checkInvalidSensor($sensor, $value);
                if ($reason !== null) {
                    DB::table('invalid_sensor_data')->insert([
                        'hardware_id' => $hardwareId,
                        'pin'         => $pin,
                        'sensor'      => $sensor,
                        'value'       => $value,
                        'reason'      => $reason,
                    ]);
                    $invalidCount++;
                }

                DB::table('sensor_data')->insert([
                    'reading_id' => $readingId,
                    'pin'        => $pin,
                    'sensor'     => $sensor,
                    'value'      => $value,
                ]);
                $validCount++;
            }

            DB::commit();

            return response()->json([
                'status'     => 'ok',
                'reading_id' => $readingId,
                'sensors'    => $validCount,
                'invalid'    => $invalidCount,
            ]);

        } catch (\Exception $e) {
            DB::rollBack();
            Log::error('ReceiveData error: ' . $e->getMessage());
            return response()->json(['error' => 'Database error'], 500);
        }
    }

    private function checkInvalidSensor(string $sensor, string $value): ?string
    {
        $lower = strtolower(trim($value));

        if ($lower === 'nan') {
            return 'Check DHT sensor (NaN)';
        }
        if (in_array($lower, ['-127', '-127.00', '-127.0'])) {
            return 'Check DS18B20 sensor (open/error)';
        }
        if (!is_numeric($value)) {
            return null;
        }

        $val = (float)$value;
        if ($sensor === 'Humidity' && ($val < 0 || $val > 100)) {
            return 'Humidity out of valid range (0-100%)';
        }
        if ($sensor === 'pH' && ($val < 0 || $val > 14)) {
            return 'pH out of valid range (0-14)';
        }

        return null;
    }
}
```

### 2.4 Create ControlQueue Controller

Convert `PHP/control_queue.php` into a Laravel controller:

**`app/Http/Controllers/Api/ControlQueueController.php`**:

```php
<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;

class ControlQueueController extends Controller
{
    public function __invoke(Request $request)
    {
        if (!$request->isMethod('post')) {
            return response()->json(['error' => 'Method not allowed'], 405);
        }

        // HMAC auth (same as ReceiveData)
        $apiKey    = $request->header('X-API-Key', '');
        $timestamp = $request->header('X-Timestamp', '');
        $signature = $request->header('X-Signature', '');

        if ($apiKey !== env('SMARTPONIC_API_KEY', 'smartponic-hq-key')) {
            return response()->json(['error' => 'Invalid API key'], 401);
        }

        $rawBody = $request->getContent();
        $hmacSecret = env('SMARTPONIC_HMAC_SECRET', 'smartponic-hq-signature-secret');
        $expectedSig = hash('sha256', $timestamp . $rawBody . $hmacSecret);
        if (!hash_equals($expectedSig, $signature)) {
            return response()->json(['error' => 'Invalid signature'], 401);
        }

        $data = json_decode($rawBody, true);
        if ($data === null) {
            return response()->json(['error' => 'Invalid JSON'], 400);
        }

        $action     = $data['action'] ?? '';
        $hardwareId = $data['hardware_id'] ?? '';

        try {
            return match ($action) {
                'get_pending' => $this->getPending($hardwareId),
                'mark_sent'   => $this->markSent($data),
                'ack'         => $this->acknowledge($data),
                default       => response()->json(['error' => 'Unknown action'], 400),
            };
        } catch (\Exception $e) {
            Log::error('ControlQueue error: ' . $e->getMessage());
            return response()->json(['error' => 'Internal error'], 500);
        }
    }

    private function getPending(string $hardwareId)
    {
        $commands = DB::table('relay_commands')
            ->where('hardware_id', $hardwareId)
            ->where('status', 'approved')
            ->orderBy('id')
            ->limit(10)
            ->get();

        return response()->json([
            'status'   => 'ok',
            'commands' => $commands->map(fn($c) => [
                'id'       => $c->id,
                'relay_id' => $c->relay_id,
                'action'   => $c->action,
            ]),
        ]);
    }

    private function markSent(array $data)
    {
        $cmdId = $data['command_id'] ?? 0;
        DB::table('relay_commands')
            ->where('id', $cmdId)
            ->where('status', 'approved')
            ->update(['status' => 'sent']);

        return response()->json(['status' => 'ok']);
    }

    private function acknowledge(array $data)
    {
        $cmdId  = $data['command_id'] ?? 0;
        $result = $data['result'] ?? 'done';

        DB::table('relay_commands')
            ->where('id', $cmdId)
            ->where('status', 'sent')
            ->update(['status' => $result === 'done' ? 'done' : 'failed']);

        return response()->json(['status' => 'ok']);
    }
}
```

### 2.5 Register Routes

**`routes/api.php`** (create this file if it doesn't exist):

```php
<?php

use Illuminate\Support\Facades\Route;
use App\Http\Controllers\Api\ReceiveDataController;
use App\Http\Controllers\Api\ControlQueueController;

// ESP32 telemetry ingestion (no CSRF, no auth middleware — uses HMAC)
Route::post('/receive-data', ReceiveDataController::class);
Route::post('/control-queue', ControlQueueController::class);
```

**`bootstrap/app.php`** — ensure `api` middleware group is configured:

```php
->withRouting(
    api: __DIR__.'/../routes/api.php',
    // ...
)
```

### 2.6 Update DashboardController for Turso

The existing `DashboardController.php` uses Laravel's query builder which works with Turso via the libsql driver. However, some MySQL-specific SQL needs updating:

1. **`DB::raw("NOW() - INTERVAL {$range}")`** → `DB::raw("datetime('now', '-{$rangeSql}')")`
2. **`REGEXP`** → Use `GLOB` or `LIKE` (SQLite doesn't have REGEXP by default)
3. **`UNIX_TIMESTAMP()`** → `strftime('%s', ...)`

Create a helper trait or update the controller methods to handle SQLite syntax.

### 2.7 Environment Configuration for Production

**`.env.production`** template:

```env
APP_NAME=SmartPonic
APP_ENV=production
APP_DEBUG=false
APP_KEY=base64:7fSdWc8whcnh4TpRh52r+KPm35UwjLhevTEo/CGGbgM=
APP_URL=https://smartponic.onrender.com

LOG_CHANNEL=stack
LOG_LEVEL=warning

DB_CONNECTION=libsql
TURSO_DATABASE_URL=libsql://smartponic-db-org.turso.io
TURSO_AUTH_TOKEN=your-auth-token-here

BROADCAST_DRIVER=log
CACHE_DRIVER=file
FILESYSTEM_DISK=local
QUEUE_CONNECTION=sync
SESSION_DRIVER=file
SESSION_LIFETIME=120

# Security keys for ESP32 HMAC
SMARTPONIC_API_KEY=smartponic-hq-key
SMARTPONIC_HMAC_SECRET=smartponic-hq-signature-secret
SMARTPONIC_AUTH_KEY=AQUA77
SMARTPONIC_REQUEST_MAX_AGE=300

# Telegram bot
TELEGRAM_BOT_TOKEN=your-telegram-bot-token
TELEGRAM_ALLOWED_CHAT_IDS=your-chat-id
```

---

## Phase 3: Deploy to Render.com ✅

| Task | Status |
|------|--------|
| Dockerfile created (php:8.2-cli) | ✅ Done |
| render.yaml created (Docker runtime) | ✅ Done |
| start.sh created | ✅ Done |
| .env.production template created | ✅ Done |
| GitHub repo `render-host` created | ✅ Done |
| Dashboard live at `smartponic-dashboard.onrender.com` | ✅ Done |
| Health endpoint working | ✅ Done |
| Data ingestion working (POST /api/receive-data) | ✅ Done |
| cron-job.org keep-alive | ⏳ Not yet set up |

### 3.1 Prepare the Laravel App for Render

**`render.yaml`** (Render Blueprint — optional but recommended):

```yaml
services:
  - type: web
    name: smartponic-dashboard
    env: php
    buildCommand: |
      composer install --no-dev --optimize-autoloader
      php artisan config:cache
      php artisan route:cache
      php artisan view:cache
    startCommand: |
      php artisan serve --host=0.0.0.0 --port=$PORT
    envVars:
      - key: APP_ENV
        value: production
      - key: APP_DEBUG
        value: false
      - key: APP_KEY
        value: base64:7fSdWc8whcnh4TpRh52r+KPm35UwjLhevTEo/CGGbgM=
      - key: APP_URL
        value: https://smartponic.onrender.com
      - key: DB_CONNECTION
        value: libsql
      - key: TURSO_DATABASE_URL
        sync: false  # Set manually in Render dashboard
      - key: TURSO_AUTH_TOKEN
        sync: false  # Set manually in Render dashboard
      - key: SMARTPONIC_API_KEY
        value: smartponic-hq-key
      - key: SMARTPONIC_HMAC_SECRET
        value: smartponic-hq-signature-secret
      - key: SMARTPONIC_AUTH_KEY
        value: AQUA77
      - key: SMARTPONIC_REQUEST_MAX_AGE
        value: "300"
      - key: LOG_CHANNEL
        value: stack
      - key: LOG_LEVEL
        value: warning
```

**`start.sh`** (alternative startup script):

```bash
#!/usr/bin/env bash
# Render.com start script for SmartPonic Laravel app

# Exit on error
set -e

# Install dependencies
composer install --no-dev --optimize-autoloader --no-interaction

# Cache Laravel configs
php artisan config:cache
php artisan route:cache
php artisan view:cache

# Run any pending migrations
php artisan migrate --force

# Start PHP built-in server (Render sets $PORT)
php artisan serve --host=0.0.0.0 --port=${PORT:-8000}
```

### 3.2 Push to GitHub

```bash
# Initialize git (if not already)
cd C:\Users\HAKIMIE\smartponic_v2
git init
git add .
git commit -m "Prepare for cloud migration"

# Create private repo on GitHub first, then:
git remote add origin https://github.com/your-username/smartponic-v2.git
git push -u origin main
```

### 3.3 Deploy on Render

1. **Log in** to [render.com](https://render.com) (use GitHub OAuth)
2. **Click** "New +" → "Web Service"
3. **Connect** your GitHub repository (`smartponic-v2`)
4. **Configure**:
   - **Name**: `smartponic-dashboard`
   - **Region**: Choose closest to your location
   - **Branch**: `main`
   - **Runtime**: `PHP`
   - **Build Command**: `composer install --no-dev --optimize-autoloader && php artisan config:cache && php artisan route:cache && php artisan view:cache`
   - **Start Command**: `php artisan serve --host=0.0.0.0 --port=$PORT`
   - **Plan**: Free
5. **Add Environment Variables** (from `.env.production`):
   - `TURSO_DATABASE_URL` = `libsql://smartponic-db-org.turso.io`
   - `TURSO_AUTH_TOKEN` = (your Turso token)
   - `SMARTPONIC_API_KEY` = `smartponic-hq-key`
   - `SMARTPONIC_HMAC_SECRET` = `smartponic-hq-signature-secret`
   - `SMARTPONIC_AUTH_KEY` = `AQUA77`
   - `SMARTPONIC_REQUEST_MAX_AGE` = `300`
   - `APP_KEY` = (your Laravel app key)
   - `APP_ENV` = `production`
   - `APP_DEBUG` = `false`
   - `LOG_LEVEL` = `warning`
6. **Click** "Deploy Web Service"

### 3.4 Important: Render Free Tier Limitations

| Limitation | Impact | Mitigation |
|------------|--------|------------|
| **Spins down after 15 min inactivity** | Dashboard may take 30-60s to load on first visit | Use a uptime monitor (e.g., cron-job.org, UptimeRobot free tier) to ping every 10 min |
| **750 hours/month** | One service runs 24/7 = 744h, fits in free tier | OK for a single service |
| **No persistent disk** | SQLite file storage not suitable | Turso is external, so this is fine |
| **Bandwidth: 100GB/month** | Sufficient for IoT data | Monitor usage |

---

## Phase 4: ESP32 HQ Gateway Update 🔧

| Task | Status |
|------|--------|
| Firmware URLs updated in code | ✅ Done |
| Physical device flashed with new firmware | ❌ Not yet |

### 4.1 Update Firmware Endpoint URL

In `firmware_esp32/ESP32_HQ_Site/src/main_full.cpp`, change:

```cpp
// OLD — local endpoint
const char* API_URL     = "http://172.20.10.3/smartponic/receive_data.php";
const char* CONTROL_URL = "http://172.20.10.3/smartponic/control_queue.php";

// NEW — cloud endpoint
const char* API_URL     = "https://smartponic-dashboard.onrender.com/api/receive-data";
const char* CONTROL_URL = "https://smartponic-dashboard.onrender.com/api/control-queue";
```

### 4.2 Update API Keys (Optional)

If you change the API key / HMAC secret, update both:
- Render environment variables (`SMARTPONIC_API_KEY`, `SMARTPONIC_HMAC_SECRET`)
- ESP32 firmware constants (`gApiKey`, `gHmacSecret`)

### 4.3 Flash the Updated Firmware

```bash
cd firmware_esp32/ESP32_HQ_Site
pio run --target upload
```

---

## Phase 5: Telegram Bot Migration 🔧

| Task | Status |
|------|--------|
| `app/Console/Commands/TelegramPoll.php` created | ✅ Done |
| `php artisan telegram:poll` registered | ✅ Done |
| Running on Render (cron-job.org or Supervisor) | ❌ Not yet |

### 5.1 Convert Telegram Poll Script

The current `PHP/telegram_poll.php` runs as a long-running process. On Render, this can be:

**Option A: Render Cron Job** (recommended)
- Create a Laravel artisan command that polls Telegram once
- Schedule it via Render's cron to run every 30-60 seconds

**`app/Console/Commands/TelegramPoll.php`**:

```php
<?php

namespace App\Console\Commands;

use Illuminate\Console\Command;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;

class TelegramPoll extends Command
{
    protected $signature = 'telegram:poll';
    protected $description = 'Poll Telegram for bot commands';

    public function handle()
    {
        $botToken = env('TELEGRAM_BOT_TOKEN');
        if (!$botToken) {
            $this->error('TELEGRAM_BOT_TOKEN not set');
            return 1;
        }

        // Get last processed update ID
        $lastUpdateId = DB::table('telegram_bot_state')
            ->where('state_key', 'last_update_id')
            ->value('state_value') ?? 0;

        // Fetch updates from Telegram
        $response = Http::get("https://api.telegram.org/bot{$botToken}/getUpdates", [
            'offset' => (int)$lastUpdateId + 1,
            'timeout' => 10,
        ]);

        if (!$response->successful()) {
            $this->error('Telegram API error');
            return 1;
        }

        $updates = $response->json()['result'] ?? [];

        foreach ($updates as $update) {
            $this->processUpdate($update);
            DB::table('telegram_bot_state')->upsert(
                ['state_key' => 'last_update_id', 'state_value' => $update['update_id']],
                'state_key',
                ['state_value', 'updated_at' => DB::raw("datetime('now')")]
            );
        }

        $this->info('Processed ' . count($updates) . ' updates');
        return 0;
    }

    private function processUpdate(array $update)
    {
        $message = $update['message'] ?? [];
        $chatId  = $message['chat']['id'] ?? null;
        $text    = trim($message['text'] ?? '');

        if (!$chatId || !$text) return;

        // Check if chat is authorized
        $allowedChats = explode(',', env('TELEGRAM_ALLOWED_CHAT_IDS', ''));
        if (!in_array((string)$chatId, $allowedChats)) {
            return;
        }

        // Handle commands
        $botToken = env('TELEGRAM_BOT_TOKEN');
        $response = match (true) {
            str_starts_with($text, '/start')  => $this->cmdStart($chatId),
            str_starts_with($text, '/status') => $this->cmdStatus($chatId),
            str_starts_with($text, '/nodes')  => $this->cmdNodes($chatId),
            str_starts_with($text, '/alerts') => $this->cmdAlerts($chatId),
            default => null,
        };

        if ($response) {
            Http::post("https://api.telegram.org/bot{$botToken}/sendMessage", [
                'chat_id' => $chatId,
                'text'    => $response,
                'parse_mode' => 'HTML',
            ]);
        }
    }

    private function cmdStart(int $chatId): string
    {
        return "🤖 <b>SmartPonic Bot</b>\n"
             . "Available commands:\n"
             . "/status — System status\n"
             . "/nodes — List nodes\n"
             . "/alerts — Active alerts\n"
             . "/readings — Latest sensor readings";
    }

    private function cmdStatus(int $chatId): string
    {
        $latest = DB::table('sensor_readings')->orderByDesc('id')->first();
        if (!$latest) return "⚠️ No data received yet.";

        $nodeCount = DB::table('nodes')->count();
        $alertCount = DB::table('alerts')->where('status', 'active')->count();

        return "📊 <b>System Status</b>\n"
             . "Nodes: {$nodeCount}\n"
             . "Active alerts: {$alertCount}\n"
             . "Last reading: {$latest->created_at}\n"
             . "RSSI: {$latest->rssi} dBm | SNR: {$latest->snr} dB";
    }

    private function cmdNodes(int $chatId): string
    {
        $nodes = DB::table('nodes')->get();
        if ($nodes->isEmpty()) return "No nodes registered.";

        $text = "📡 <b>Registered Nodes</b>\n";
        foreach ($nodes as $node) {
            $text .= "• {$node->hardware_id}";
            if ($node->name) $text .= " ({$node->name})";
            $text .= "\n  Last seen: {$node->last_seen}\n";
        }
        return $text;
    }

    private function cmdAlerts(int $chatId): string
    {
        $alerts = DB::table('alerts')
            ->where('status', 'active')
            ->orderByDesc('created_at')
            ->limit(10)
            ->get();

        if ($alerts->isEmpty()) return "✅ No active alerts.";

        $text = "🔔 <b>Active Alerts</b>\n";
        foreach ($alerts as $a) {
            $icon = $a->severity === 'critical' ? '🔴' : ($a->severity === 'warning' ? '🟡' : '🔵');
            $text .= "{$icon} {$a->message}\n";
        }
        return $text;
    }
}
```

**Option B: Background Worker on Render**
- Use Render's "Background Worker" service type
- Runs the Telegram poll as a long-running process
- More complex but real-time

### 5.2 Schedule Telegram Poll (Render Cron)

Render doesn't have a built-in cron for free tier. Alternatives:
1. **External cron service** (cron-job.org, free): Hit `https://smartponic-dashboard.onrender.com/api/telegram/poll` every 60s
2. **Laravel Scheduler** with a Render cron job (paid Render add-on)
3. **Keep running locally** — the Telegram bot stays on your local machine, only the dashboard moves to cloud

**Recommended**: Keep Telegram bot running locally for now (simplest), or use cron-job.org to hit a web endpoint.

---

## Phase 6: Verification ⚠️

### 6.1 Test Checklist

- [x] Turso database created and tables exist
- [x] Laravel connects to Turso locally
- [x] `POST /api/receive-data` accepts ESP32 data (tested on Render ✅)
- [x] `POST /api/control-queue` returns pending commands
- [x] Dashboard loads on Render.com URL
- [x] Dashboard polls and displays live sensor data
- [ ] ESP32 HQ Gateway sends data to Render URL (code updated, device not flashed)
- [ ] Telegram bot responds to commands (command created, not deployed)
- [ ] Alerts trigger correctly
- [ ] Relay commands flow dashboard → ESP32

### 6.2 Test Commands

```bash
# Test database connection
curl https://smartponic-dashboard.onrender.com/api/health

# Simulate a sensor reading
curl -X POST https://smartponic-dashboard.onrender.com/api/receive-data \
  -H "Content-Type: application/json" \
  -H "X-API-Key: smartponic-hq-key" \
  -H "X-Timestamp: $(date +%s)" \
  -H "X-Signature: $(echo -n "$(date +%s){\"hardware_id\":\"A1B2C3D4E5F67890\",\"sensors\":[{\"pin\":4,\"sensor\":\"Temperature\",\"value\":\"28.5\"}]}smartponic-hq-signature-secret" | sha256sum | cut -d' ' -f1)" \
  -d '{"hardware_id":"A1B2C3D4E5F67890","rssi":-45,"snr":10.5,"sensors":[{"pin":4,"sensor":"Temperature","value":"28.5"},{"pin":5,"sensor":"Humidity","value":"65.2"}]}'

# Check dashboard loads
curl https://smartponic-dashboard.onrender.com/
```

### 6.3 Rollback Plan

If something goes wrong:
1. **ESP32**: Re-flash with old localhost URL
2. **Dashboard**: Keep old XAMPP + local Laravel running
3. **Database**: MySQL data is untouched — Turso is additive

---

## Architecture Diagram (After Migration)

```
┌─────────────────────┐     LoRa 433 MHz     ┌──────────────────────┐
│  ESP32 Sensor Node  │ ────────────────────▶ │  ESP32 HQ Gateway    │
│  (end device)       │     AES-encrypted     │  (lolin_s2_mini)     │
└─────────────────────┘                       └──────────┬───────────┘
                                                          │ HTTP POST
                                                          │ (HMAC-signed)
                                                          ▼
┌──────────────────────────────────────────────────────────────────┐
│                    Render.com (Web Service)                       │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │              Laravel Application                         │    │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  │    │
│  │  │ ReceiveData  │  │ControlQueue  │  │ Dashboard    │  │    │
│  │  │ Controller   │  │Controller    │  │ Controller   │  │    │
│  │  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘  │    │
│  │         │                 │                  │          │    │
│  │         └──────────┬──────┘──────────────────┘          │    │
│  │                    │                                     │    │
│  │              ┌─────▼──────┐                              │    │
│  │              │ libSQL     │                              │    │
│  │              │ Driver     │                              │    │
│  │              └─────┬──────┘                              │    │
│  └────────────────────┼────────────────────────────────────┘    │
└───────────────────────┼────────────────────────────────────────┘
                        │ libSQL protocol
                        ▼
┌──────────────────────────────────────────────────────────────────┐
│                    Turso (Cloud Database)                        │
│                                                                  │
│  ┌──────────┐  ┌──────────────┐  ┌──────────────┐              │
│  │  nodes   │  │sensor_readings│  │ sensor_data  │  ...tables   │
│  └──────────┘  └──────────────┘  └──────────────┘              │
└──────────────────────────────────────────────────────────────────┘

                        ◄── HTTPS ──►
┌──────────────────────┐              ┌──────────────────────┐
│  Web Browser         │              │  Telegram App        │
│  (Dashboard UI)      │              │  (Bot Commands)      │
└──────────────────────┘              └──────────────────────┘
```

---

## Timeline Estimate

| Phase | Tasks | Estimated Time | Actual |
|-------|-------|----------------|--------|
| **Phase 1** | Turso setup, schema conversion, table creation | 1-2 hours | ✅ Done |
| **Phase 2** | Laravel controllers, routes, Turso driver config | 3-4 hours | ✅ Done |
| **Phase 3** | GitHub push, Render deployment, env config | 1-2 hours | ✅ Done |
| **Phase 4** | ESP32 firmware update, flash | 1 hour | 🔧 Code done, not flashed |
| **Phase 5** | Telegram bot migration | 1-2 hours | 🔧 Command done, not deployed |
| **Phase 6** | Testing, verification, rollback prep | 2-3 hours | ⚠️ Partial |
| **Total** | | **~9-14 hours** | **~8 hours completed** |

---

## Potential Issues & Mitigations

| Issue | Risk | Mitigation |
|-------|------|------------|
| **Turso driver FFI on Render** | Medium — Render's PHP may not have FFI enabled | Test locally first; fallback to Turso HTTP API directly |
| **SQLite concurrency** | Low — single writer, but IoT data is sequential | Turso handles this with distributed SQLite |
| **Render free tier spin-down** | Medium — 30-60s cold start | Use cron-job.org to ping every 10 min |
| **ESP32 can't reach Render** | Low — HTTPS may need certificate update | Test with curl first; use IP fallback if needed |
| **Data migration from MySQL** | Medium — need to export existing data | Use `mysqldump` + conversion script |
| **Telegram bot uptime** | Medium — bot needs to be always-on | Use cron-job.org or keep local instance |
