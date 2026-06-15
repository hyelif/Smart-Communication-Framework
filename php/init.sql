-- SmartPonic Database Schema
-- Run this to initialize the database

CREATE DATABASE IF NOT EXISTS smartponic
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;

USE smartponic;

-- ============================================
-- Nodes registry
-- ============================================
CREATE TABLE IF NOT EXISTS nodes (
    id          INT AUTO_INCREMENT PRIMARY KEY,
    hardware_id VARCHAR(16) NOT NULL UNIQUE,
    name        VARCHAR(64) DEFAULT NULL,
    location    VARCHAR(128) DEFAULT NULL,
    first_seen  TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_seen   TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_hardware_id (hardware_id)
) ENGINE=InnoDB;

-- ============================================
-- Main sensor readings (one row per telemetry packet)
-- ============================================
CREATE TABLE IF NOT EXISTS sensor_readings (
    id          INT AUTO_INCREMENT PRIMARY KEY,
    hardware_id VARCHAR(16) NOT NULL,
    rssi        INT DEFAULT NULL,
    snr         FLOAT DEFAULT NULL,
    event_type  VARCHAR(32) DEFAULT 'telemetry',
    created_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_hardware_id (hardware_id),
    INDEX idx_created_at (created_at),
    INDEX idx_hw_created (hardware_id, created_at)
) ENGINE=InnoDB;

-- ============================================
-- Individual sensor data points
-- ============================================
CREATE TABLE IF NOT EXISTS sensor_data (
    id          INT AUTO_INCREMENT PRIMARY KEY,
    reading_id  INT NOT NULL,
    pin         INT NOT NULL,
    sensor      VARCHAR(32) NOT NULL,
    value       VARCHAR(64) NOT NULL,
    created_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (reading_id) REFERENCES sensor_readings(id) ON DELETE CASCADE,
    INDEX idx_sensor (sensor),
    INDEX idx_reading_id (reading_id)
) ENGINE=InnoDB;

-- ============================================
-- Invalid sensor readings log
-- ============================================
CREATE TABLE IF NOT EXISTS invalid_sensor_data (
    id          INT AUTO_INCREMENT PRIMARY KEY,
    hardware_id VARCHAR(16) NOT NULL,
    pin         INT NOT NULL,
    sensor      VARCHAR(32) NOT NULL,
    value       VARCHAR(64) NOT NULL,
    reason      VARCHAR(255) DEFAULT NULL,
    created_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_hardware_id (hardware_id),
    INDEX idx_created_at (created_at)
) ENGINE=InnoDB;

-- ============================================
-- Relay command queue
-- ============================================
CREATE TABLE IF NOT EXISTS relay_commands (
    id          INT AUTO_INCREMENT PRIMARY KEY,
    hardware_id VARCHAR(16) NOT NULL,
    relay_id    TINYINT UNSIGNED NOT NULL,
    action      VARCHAR(4) NOT NULL DEFAULT 'OFF',
    status      ENUM('pending','approved','sent','done','failed') DEFAULT 'pending',
    created_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_hardware_id (hardware_id),
    INDEX idx_status (status),
    INDEX idx_hw_status (hardware_id, status)
) ENGINE=InnoDB;

-- ============================================
-- Telegram bot polling state
-- ============================================
CREATE TABLE IF NOT EXISTS telegram_bot_state (
    state_key   VARCHAR(64) PRIMARY KEY,
    state_value VARCHAR(255) NOT NULL,
    updated_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB;

-- ============================================
-- Dashboard: sensor profiles (calibration + thresholds)
-- ============================================
CREATE TABLE IF NOT EXISTS sensor_profiles (
    id              INT AUTO_INCREMENT PRIMARY KEY,
    sensor_key      VARCHAR(32) NOT NULL UNIQUE,
    label           VARCHAR(64) NOT NULL,
    unit            VARCHAR(16) NOT NULL DEFAULT '',
    family          VARCHAR(64) DEFAULT '',
    accent          VARCHAR(9) DEFAULT '#9ecaff',
    threshold_min   DECIMAL(10,4) DEFAULT NULL,
    threshold_max   DECIMAL(10,4) DEFAULT NULL,
    calibration_a   DECIMAL(10,4) DEFAULT 1.0000,
    calibration_b   DECIMAL(10,4) DEFAULT 0.0000,
    calibration_c   DECIMAL(10,4) DEFAULT 0.0000,
    cal_label_a     VARCHAR(32) DEFAULT 'Scale',
    cal_label_b     VARCHAR(32) DEFAULT 'Offset',
    cal_label_c     VARCHAR(32) DEFAULT 'Reserve',
    updated_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_sensor_key (sensor_key)
) ENGINE=InnoDB;

-- ============================================
-- Dashboard: per-sensor data tables (time-series optimized)
-- ============================================
CREATE TABLE IF NOT EXISTS temperature_data (
    id          INT AUTO_INCREMENT PRIMARY KEY,
    hardware_id VARCHAR(16) NOT NULL,
    reading_id  INT NOT NULL,
    pin         INT NOT NULL,
    value       DECIMAL(8,2) NOT NULL,
    created_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_hw_created (hardware_id, created_at),
    INDEX idx_reading_id (reading_id)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS humidity_data (
    id          INT AUTO_INCREMENT PRIMARY KEY,
    hardware_id VARCHAR(16) NOT NULL,
    reading_id  INT NOT NULL,
    pin         INT NOT NULL,
    value       DECIMAL(8,2) NOT NULL,
    created_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_hw_created (hardware_id, created_at),
    INDEX idx_reading_id (reading_id)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS water_temp_data (
    id          INT AUTO_INCREMENT PRIMARY KEY,
    hardware_id VARCHAR(16) NOT NULL,
    reading_id  INT NOT NULL,
    pin         INT NOT NULL,
    value       DECIMAL(8,2) NOT NULL,
    created_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_hw_created (hardware_id, created_at),
    INDEX idx_reading_id (reading_id)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS ph_data (
    id          INT AUTO_INCREMENT PRIMARY KEY,
    hardware_id VARCHAR(16) NOT NULL,
    reading_id  INT NOT NULL,
    pin         INT NOT NULL,
    value       DECIMAL(8,2) NOT NULL,
    created_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_hw_created (hardware_id, created_at),
    INDEX idx_reading_id (reading_id)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS tds_data (
    id          INT AUTO_INCREMENT PRIMARY KEY,
    hardware_id VARCHAR(16) NOT NULL,
    reading_id  INT NOT NULL,
    pin         INT NOT NULL,
    value       DECIMAL(10,2) NOT NULL,
    created_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_hw_created (hardware_id, created_at),
    INDEX idx_reading_id (reading_id)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS turbidity_data (
    id          INT AUTO_INCREMENT PRIMARY KEY,
    hardware_id VARCHAR(16) NOT NULL,
    reading_id  INT NOT NULL,
    pin         INT NOT NULL,
    value       DECIMAL(10,2) NOT NULL,
    created_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_hw_created (hardware_id, created_at),
    INDEX idx_reading_id (reading_id)
) ENGINE=InnoDB;

CREATE TABLE IF NOT EXISTS rain_data (
    id          INT AUTO_INCREMENT PRIMARY KEY,
    hardware_id VARCHAR(16) NOT NULL,
    reading_id  INT NOT NULL,
    pin         INT NOT NULL,
    value       VARCHAR(32) NOT NULL,
    created_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_hw_created (hardware_id, created_at),
    INDEX idx_reading_id (reading_id)
) ENGINE=InnoDB;

-- ============================================
-- Dashboard: communication health tracking
-- ============================================
CREATE TABLE IF NOT EXISTS communication_health (
    id              INT AUTO_INCREMENT PRIMARY KEY,
    hardware_id     VARCHAR(16) NOT NULL,
    delivery_rate   DECIMAL(5,2) DEFAULT 100.00,
    total_expected  INT DEFAULT 0,
    total_received  INT DEFAULT 0,
    sequence_gaps   INT DEFAULT 0,
    freshness_seconds INT DEFAULT 0,
    last_rssi       INT DEFAULT NULL,
    last_snr        FLOAT DEFAULT NULL,
    updated_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uk_hardware_id (hardware_id)
) ENGINE=InnoDB;

-- ============================================
-- Dashboard: settings key-value store
-- ============================================
CREATE TABLE IF NOT EXISTS dashboard_settings (
    setting_key  VARCHAR(64) PRIMARY KEY,
    setting_value TEXT NOT NULL,
    updated_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB;

-- ============================================
-- Dashboard: alerts (active/acknowledged/resolved)
-- ============================================
CREATE TABLE IF NOT EXISTS alerts (
    id          INT AUTO_INCREMENT PRIMARY KEY,
    hardware_id VARCHAR(16) NOT NULL,
    sensor_key  VARCHAR(32) NOT NULL,
    severity    ENUM('info','warning','critical') DEFAULT 'warning',
    message     VARCHAR(255) NOT NULL,
    status      ENUM('active','acknowledged','resolved') DEFAULT 'active',
    created_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_hw_status (hardware_id, status),
    INDEX idx_created_at (created_at)
) ENGINE=InnoDB;

-- ============================================
-- Dashboard: pending approvals for automation
-- ============================================
CREATE TABLE IF NOT EXISTS pending_approvals (
    id           INT AUTO_INCREMENT PRIMARY KEY,
    command_id   INT UNSIGNED NOT NULL DEFAULT 0,
    hardware_id  VARCHAR(16) NOT NULL,
    relay_id     TINYINT UNSIGNED NOT NULL,
    action       VARCHAR(4) NOT NULL,
    trigger_value DECIMAL(10,4) DEFAULT NULL,
    status       ENUM('pending','approved','cancelled','expired') DEFAULT 'pending',
    chat_id      BIGINT DEFAULT NULL,
    created_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    expires_at   TIMESTAMP NULL,
    INDEX idx_status (status),
    INDEX idx_hardware_id (hardware_id)
) ENGINE=InnoDB;

-- ============================================
-- Telegram: alert cooldown state
-- ============================================
CREATE TABLE IF NOT EXISTS telegram_alert_state (
    state_key   VARCHAR(190) PRIMARY KEY,
    last_sent_at TIMESTAMP NULL,
    updated_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB;

