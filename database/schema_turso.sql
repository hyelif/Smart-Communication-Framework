-- ============================================================
-- SmartPonic v2 — Turso (libSQL/SQLite) Database Schema
-- ============================================================
-- Usage:  turso db shell smartponic-db < database/schema_turso.sql
-- ============================================================

PRAGMA foreign_keys = ON;

-- ============================================
-- Nodes registry
-- ============================================
CREATE TABLE IF NOT EXISTS nodes (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    hardware_id TEXT NOT NULL UNIQUE,
    name        TEXT DEFAULT NULL,
    location    TEXT DEFAULT NULL,
    first_seen  TEXT DEFAULT (datetime('now')),
    last_seen   TEXT DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_nodes_hardware_id ON nodes(hardware_id);

-- ============================================
-- Main sensor readings (one row per telemetry packet)
-- ============================================
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

-- ============================================
-- Individual sensor data points
-- ============================================
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

-- ============================================
-- Invalid sensor readings log
-- ============================================
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

-- ============================================
-- Relay command queue
-- ============================================
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

-- ============================================
-- Sensor profiles (calibration + thresholds)
-- ============================================
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

-- ============================================
-- Dashboard settings key-value store
-- ============================================
CREATE TABLE IF NOT EXISTS dashboard_settings (
    setting_key   TEXT PRIMARY KEY,
    setting_value TEXT NOT NULL,
    updated_at    TEXT DEFAULT (datetime('now'))
);

-- ============================================
-- Alerts (active/acknowledged/resolved)
-- ============================================
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

-- ============================================
-- Pending approvals for automation
-- ============================================
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

-- ============================================
-- Communication health tracking
-- ============================================
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

-- ============================================
-- Users (multi-user auth)
-- ============================================
CREATE TABLE IF NOT EXISTS users (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    username    TEXT NOT NULL UNIQUE,
    password    TEXT NOT NULL,  -- SHA-256 hash
    created_at  TEXT DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_users_username ON users(username);

-- ============================================
-- User-to-node mapping (many-to-many)
-- ============================================
CREATE TABLE IF NOT EXISTS user_nodes (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id     INTEGER NOT NULL,
    hardware_id TEXT NOT NULL,
    label       TEXT DEFAULT NULL,
    FOREIGN KEY (user_id) REFERENCES users(id),
    FOREIGN KEY (hardware_id) REFERENCES nodes(hardware_id),
    UNIQUE(user_id, hardware_id)
);
CREATE INDEX IF NOT EXISTS idx_un_user_id ON user_nodes(user_id);
CREATE INDEX IF NOT EXISTS idx_un_hardware_id ON user_nodes(hardware_id);

-- ============================================
-- Seed: default admin user (password: admin)
-- SHA-256 of "admin" = 8c6976e5b5410415bde908bd4dee15dfb167a9c873fc4bb8a81f6f2ab448a918
-- ============================================
INSERT OR IGNORE INTO users (username, password)
VALUES ('admin', '8c6976e5b5410415bde908bd4dee15dfb167a9c873fc4bb8a81f6f2ab448a918');

-- ============================================
-- Triggers for updated_at auto-update
-- SQLite doesn't have ON UPDATE CURRENT_TIMESTAMP
-- so we use triggers instead
-- ============================================

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

CREATE TRIGGER IF NOT EXISTS trg_sensor_profiles_updated
    AFTER UPDATE ON sensor_profiles
    FOR EACH ROW
BEGIN
    UPDATE sensor_profiles SET updated_at = datetime('now') WHERE id = OLD.id;
END;

CREATE TRIGGER IF NOT EXISTS trg_dashboard_settings_updated
    AFTER UPDATE ON dashboard_settings
    FOR EACH ROW
BEGIN
    UPDATE dashboard_settings SET updated_at = datetime('now') WHERE id = OLD.id;
END;

CREATE TRIGGER IF NOT EXISTS trg_communication_health_updated
    AFTER UPDATE ON communication_health
    FOR EACH ROW
BEGIN
    UPDATE communication_health SET updated_at = datetime('now') WHERE id = OLD.id;
END;

-- ============================================
-- Done
-- ============================================
PRAGMA foreign_keys = ON;
