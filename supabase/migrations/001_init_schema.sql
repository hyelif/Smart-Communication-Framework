-- SmartPonic PostgreSQL Schema for Supabase
-- Run this in Supabase SQL Editor after creating the project.
-- Translation from MySQL init.sql to PostgreSQL.

-- ============================================
-- Nodes registry
-- ============================================
CREATE TABLE IF NOT EXISTS nodes (
    id          SERIAL PRIMARY KEY,
    hardware_id VARCHAR(16) NOT NULL UNIQUE,
    name        VARCHAR(64) DEFAULT NULL,
    location    VARCHAR(128) DEFAULT NULL,
    first_seen  TIMESTAMPTZ DEFAULT NOW(),
    last_seen   TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_nodes_hardware_id ON nodes (hardware_id);

-- ============================================
-- Main sensor readings (one row per telemetry packet)
-- ============================================
CREATE TABLE IF NOT EXISTS sensor_readings (
    id          SERIAL PRIMARY KEY,
    hardware_id VARCHAR(16) NOT NULL,
    rssi        INT DEFAULT NULL,
    snr         REAL DEFAULT NULL,
    event_type  VARCHAR(32) DEFAULT 'telemetry',
    created_at  TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_sr_hardware_id ON sensor_readings (hardware_id);
CREATE INDEX IF NOT EXISTS idx_sr_created_at ON sensor_readings (created_at);
CREATE INDEX IF NOT EXISTS idx_sr_hw_created ON sensor_readings (hardware_id, created_at);

-- ============================================
-- Individual sensor data points
-- ============================================
CREATE TABLE IF NOT EXISTS sensor_data (
    id          SERIAL PRIMARY KEY,
    reading_id  INT NOT NULL REFERENCES sensor_readings(id) ON DELETE CASCADE,
    pin         INT NOT NULL,
    sensor      VARCHAR(32) NOT NULL,
    value       VARCHAR(64) NOT NULL,
    created_at  TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_sd_sensor ON sensor_data (sensor);
CREATE INDEX IF NOT EXISTS idx_sd_reading_id ON sensor_data (reading_id);

-- ============================================
-- Invalid sensor readings log
-- ============================================
CREATE TABLE IF NOT EXISTS invalid_sensor_data (
    id          SERIAL PRIMARY KEY,
    hardware_id VARCHAR(16) NOT NULL,
    pin         INT NOT NULL,
    sensor      VARCHAR(32) NOT NULL,
    value       VARCHAR(64) NOT NULL,
    reason      VARCHAR(255) DEFAULT NULL,
    created_at  TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_invalid_hardware_id ON invalid_sensor_data (hardware_id);
CREATE INDEX IF NOT EXISTS idx_invalid_created_at ON invalid_sensor_data (created_at);

-- ============================================
-- Relay command queue
-- ============================================
CREATE TABLE IF NOT EXISTS relay_commands (
    id          SERIAL PRIMARY KEY,
    hardware_id VARCHAR(16) NOT NULL,
    relay_id    SMALLINT NOT NULL,
    action      VARCHAR(4) NOT NULL DEFAULT 'OFF',
    status      VARCHAR(16) DEFAULT 'pending',
    created_at  TIMESTAMPTZ DEFAULT NOW(),
    updated_at  TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_rc_hardware_id ON relay_commands (hardware_id);
CREATE INDEX IF NOT EXISTS idx_rc_status ON relay_commands (status);
CREATE INDEX IF NOT EXISTS idx_rc_hw_status ON relay_commands (hardware_id, status);

-- ============================================
-- Telegram bot polling state
-- ============================================
CREATE TABLE IF NOT EXISTS telegram_bot_state (
    state_key   VARCHAR(64) PRIMARY KEY,
    state_value VARCHAR(255) NOT NULL,
    updated_at  TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================
-- Dashboard: sensor profiles (calibration + thresholds)
-- ============================================
CREATE TABLE IF NOT EXISTS sensor_profiles (
    id              SERIAL PRIMARY KEY,
    sensor_key      VARCHAR(32) NOT NULL UNIQUE,
    label           VARCHAR(64) NOT NULL,
    unit            VARCHAR(16) NOT NULL DEFAULT '',
    family          VARCHAR(64) DEFAULT '',
    accent          VARCHAR(9) DEFAULT '#9ecaff',
    threshold_min   NUMERIC(10,4) DEFAULT NULL,
    threshold_max   NUMERIC(10,4) DEFAULT NULL,
    calibration_a   NUMERIC(10,4) DEFAULT 1.0000,
    calibration_b   NUMERIC(10,4) DEFAULT 0.0000,
    calibration_c   NUMERIC(10,4) DEFAULT 0.0000,
    cal_label_a     VARCHAR(32) DEFAULT 'Scale',
    cal_label_b     VARCHAR(32) DEFAULT 'Offset',
    cal_label_c     VARCHAR(32) DEFAULT 'Reserve',
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================
-- Dashboard: per-sensor data tables (time-series optimized)
-- ============================================
CREATE TABLE IF NOT EXISTS temperature_data (
    id          SERIAL PRIMARY KEY,
    hardware_id VARCHAR(16) NOT NULL,
    reading_id  INT NOT NULL REFERENCES sensor_readings(id) ON DELETE CASCADE,
    pin         INT NOT NULL,
    value       NUMERIC(8,2) NOT NULL,
    created_at  TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_td_hw_created ON temperature_data (hardware_id, created_at);
CREATE INDEX IF NOT EXISTS idx_td_reading_id ON temperature_data (reading_id);

CREATE TABLE IF NOT EXISTS humidity_data (
    id          SERIAL PRIMARY KEY,
    hardware_id VARCHAR(16) NOT NULL,
    reading_id  INT NOT NULL REFERENCES sensor_readings(id) ON DELETE CASCADE,
    pin         INT NOT NULL,
    value       NUMERIC(8,2) NOT NULL,
    created_at  TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_hd_hw_created ON humidity_data (hardware_id, created_at);
CREATE INDEX IF NOT EXISTS idx_hd_reading_id ON humidity_data (reading_id);

CREATE TABLE IF NOT EXISTS water_temp_data (
    id          SERIAL PRIMARY KEY,
    hardware_id VARCHAR(16) NOT NULL,
    reading_id  INT NOT NULL REFERENCES sensor_readings(id) ON DELETE CASCADE,
    pin         INT NOT NULL,
    value       NUMERIC(8,2) NOT NULL,
    created_at  TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_wtd_hw_created ON water_temp_data (hardware_id, created_at);
CREATE INDEX IF NOT EXISTS idx_wtd_reading_id ON water_temp_data (reading_id);

CREATE TABLE IF NOT EXISTS ph_data (
    id          SERIAL PRIMARY KEY,
    hardware_id VARCHAR(16) NOT NULL,
    reading_id  INT NOT NULL REFERENCES sensor_readings(id) ON DELETE CASCADE,
    pin         INT NOT NULL,
    value       NUMERIC(8,2) NOT NULL,
    created_at  TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_phd_hw_created ON ph_data (hardware_id, created_at);
CREATE INDEX IF NOT EXISTS idx_phd_reading_id ON ph_data (reading_id);

CREATE TABLE IF NOT EXISTS tds_data (
    id          SERIAL PRIMARY KEY,
    hardware_id VARCHAR(16) NOT NULL,
    reading_id  INT NOT NULL REFERENCES sensor_readings(id) ON DELETE CASCADE,
    pin         INT NOT NULL,
    value       NUMERIC(10,2) NOT NULL,
    created_at  TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_tdsd_hw_created ON tds_data (hardware_id, created_at);
CREATE INDEX IF NOT EXISTS idx_tdsd_reading_id ON tds_data (reading_id);

CREATE TABLE IF NOT EXISTS turbidity_data (
    id          SERIAL PRIMARY KEY,
    hardware_id VARCHAR(16) NOT NULL,
    reading_id  INT NOT NULL REFERENCES sensor_readings(id) ON DELETE CASCADE,
    pin         INT NOT NULL,
    value       NUMERIC(10,2) NOT NULL,
    created_at  TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_trbd_hw_created ON turbidity_data (hardware_id, created_at);
CREATE INDEX IF NOT EXISTS idx_trbd_reading_id ON turbidity_data (reading_id);

CREATE TABLE IF NOT EXISTS rain_data (
    id          SERIAL PRIMARY KEY,
    hardware_id VARCHAR(16) NOT NULL,
    reading_id  INT NOT NULL REFERENCES sensor_readings(id) ON DELETE CASCADE,
    pin         INT NOT NULL,
    value       VARCHAR(32) NOT NULL,
    created_at  TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_rd_hw_created ON rain_data (hardware_id, created_at);
CREATE INDEX IF NOT EXISTS idx_rd_reading_id ON rain_data (reading_id);

-- ============================================
-- Dashboard: communication health tracking
-- ============================================
CREATE TABLE IF NOT EXISTS communication_health (
    id                SERIAL PRIMARY KEY,
    hardware_id       VARCHAR(16) NOT NULL UNIQUE,
    delivery_rate     NUMERIC(5,2) DEFAULT 100.00,
    total_expected    INT DEFAULT 0,
    total_received    INT DEFAULT 0,
    sequence_gaps     INT DEFAULT 0,
    freshness_seconds INT DEFAULT 0,
    last_rssi         INT DEFAULT NULL,
    last_snr          REAL DEFAULT NULL,
    updated_at        TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================
-- Dashboard: settings key-value store
-- ============================================
CREATE TABLE IF NOT EXISTS dashboard_settings (
    setting_key   VARCHAR(64) PRIMARY KEY,
    setting_value TEXT NOT NULL,
    updated_at    TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================
-- Dashboard: alerts (active/acknowledged/resolved)
-- ============================================
CREATE TABLE IF NOT EXISTS alerts (
    id          SERIAL PRIMARY KEY,
    hardware_id VARCHAR(16) NOT NULL,
    sensor_key  VARCHAR(32) NOT NULL,
    severity    VARCHAR(16) DEFAULT 'warning',
    message     VARCHAR(255) NOT NULL,
    status      VARCHAR(16) DEFAULT 'active',
    created_at  TIMESTAMPTZ DEFAULT NOW(),
    updated_at  TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_alerts_hw_status ON alerts (hardware_id, status);
CREATE INDEX IF NOT EXISTS idx_alerts_created_at ON alerts (created_at);

-- ============================================
-- Dashboard: pending approvals for automation
-- ============================================
CREATE TABLE IF NOT EXISTS pending_approvals (
    id            SERIAL PRIMARY KEY,
    command_id    INT NOT NULL DEFAULT 0,
    hardware_id   VARCHAR(16) NOT NULL,
    relay_id      SMALLINT NOT NULL,
    action        VARCHAR(4) NOT NULL,
    trigger_value NUMERIC(10,4) DEFAULT NULL,
    status        VARCHAR(16) DEFAULT 'pending',
    chat_id       BIGINT DEFAULT NULL,
    created_at    TIMESTAMPTZ DEFAULT NOW(),
    expires_at    TIMESTAMPTZ DEFAULT NULL
);
CREATE INDEX IF NOT EXISTS idx_pa_status ON pending_approvals (status);
CREATE INDEX IF NOT EXISTS idx_pa_hardware_id ON pending_approvals (hardware_id);

-- ============================================
-- Telegram: alert cooldown state
-- ============================================
CREATE TABLE IF NOT EXISTS telegram_alert_state (
    state_key    VARCHAR(190) PRIMARY KEY,
    last_sent_at TIMESTAMPTZ DEFAULT NULL,
    updated_at   TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================
-- Enable Row Level Security (optional, for Supabase Auth)
-- ============================================
ALTER TABLE nodes ENABLE ROW LEVEL SECURITY;
ALTER TABLE sensor_readings ENABLE ROW LEVEL SECURITY;
ALTER TABLE sensor_data ENABLE ROW LEVEL SECURITY;
ALTER TABLE invalid_sensor_data ENABLE ROW LEVEL SECURITY;
ALTER TABLE relay_commands ENABLE ROW LEVEL SECURITY;
ALTER TABLE telegram_bot_state ENABLE ROW LEVEL SECURITY;
ALTER TABLE sensor_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE temperature_data ENABLE ROW LEVEL SECURITY;
ALTER TABLE humidity_data ENABLE ROW LEVEL SECURITY;
ALTER TABLE water_temp_data ENABLE ROW LEVEL SECURITY;
ALTER TABLE ph_data ENABLE ROW LEVEL SECURITY;
ALTER TABLE tds_data ENABLE ROW LEVEL SECURITY;
ALTER TABLE turbidity_data ENABLE ROW LEVEL SECURITY;
ALTER TABLE rain_data ENABLE ROW LEVEL SECURITY;
ALTER TABLE communication_health ENABLE ROW LEVEL SECURITY;
ALTER TABLE dashboard_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE alerts ENABLE ROW LEVEL SECURITY;
ALTER TABLE pending_approvals ENABLE ROW LEVEL SECURITY;
ALTER TABLE telegram_alert_state ENABLE ROW LEVEL SECURITY;
