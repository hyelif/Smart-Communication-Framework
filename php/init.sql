-- SmartPonic Database Schema
-- Run this in phpMyAdmin (XAMPP) to create the database

-- Create database
CREATE DATABASE IF NOT EXISTS smartponic;
USE smartponic;

-- Nodes table (stores node information)
CREATE TABLE IF NOT EXISTS nodes (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    location VARCHAR(255),
    latitude DECIMAL(10,6) NULL,
    longitude DECIMAL(10,6) NULL,
    distance_m DECIMAL(10,2) NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

-- Sensor readings table (main reading record)
CREATE TABLE IF NOT EXISTS sensor_readings (
    id INT AUTO_INCREMENT PRIMARY KEY,
    node_id INT NOT NULL,
    rssi INT,
    snr FLOAT,
    priority_level VARCHAR(20) NULL,
    report_mode VARCHAR(20) NULL,
    sequence_number INT NULL,
    latitude DECIMAL(10,6) NULL,
    longitude DECIMAL(10,6) NULL,
    distance_m DECIMAL(10,2) NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (node_id) REFERENCES nodes(id) ON DELETE CASCADE,
    INDEX idx_node_created (node_id, created_at)
);

-- Separate sensor tables (individual sensor values by type)
CREATE TABLE IF NOT EXISTS temperature_data (
    id INT AUTO_INCREMENT PRIMARY KEY,
    reading_id INT NOT NULL,
    node_id INT NOT NULL,
    pin_number INT NOT NULL,
    value VARCHAR(100) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (reading_id) REFERENCES sensor_readings(id) ON DELETE CASCADE,
    FOREIGN KEY (node_id) REFERENCES nodes(id) ON DELETE CASCADE,
    INDEX idx_temperature_node_created (node_id, created_at)
);

CREATE TABLE IF NOT EXISTS humidity_data (
    id INT AUTO_INCREMENT PRIMARY KEY,
    reading_id INT NOT NULL,
    node_id INT NOT NULL,
    pin_number INT NOT NULL,
    value VARCHAR(100) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (reading_id) REFERENCES sensor_readings(id) ON DELETE CASCADE,
    FOREIGN KEY (node_id) REFERENCES nodes(id) ON DELETE CASCADE,
    INDEX idx_humidity_node_created (node_id, created_at)
);

CREATE TABLE IF NOT EXISTS water_temp_data (
    id INT AUTO_INCREMENT PRIMARY KEY,
    reading_id INT NOT NULL,
    node_id INT NOT NULL,
    pin_number INT NOT NULL,
    value VARCHAR(100) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (reading_id) REFERENCES sensor_readings(id) ON DELETE CASCADE,
    FOREIGN KEY (node_id) REFERENCES nodes(id) ON DELETE CASCADE,
    INDEX idx_water_temp_node_created (node_id, created_at)
);

CREATE TABLE IF NOT EXISTS ph_data (
    id INT AUTO_INCREMENT PRIMARY KEY,
    reading_id INT NOT NULL,
    node_id INT NOT NULL,
    pin_number INT NOT NULL,
    value VARCHAR(100) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (reading_id) REFERENCES sensor_readings(id) ON DELETE CASCADE,
    FOREIGN KEY (node_id) REFERENCES nodes(id) ON DELETE CASCADE,
    INDEX idx_ph_node_created (node_id, created_at)
);

CREATE TABLE IF NOT EXISTS tds_data (
    id INT AUTO_INCREMENT PRIMARY KEY,
    reading_id INT NOT NULL,
    node_id INT NOT NULL,
    pin_number INT NOT NULL,
    value VARCHAR(100) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (reading_id) REFERENCES sensor_readings(id) ON DELETE CASCADE,
    FOREIGN KEY (node_id) REFERENCES nodes(id) ON DELETE CASCADE,
    INDEX idx_tds_node_created (node_id, created_at)
);

CREATE TABLE IF NOT EXISTS turbidity_data (
    id INT AUTO_INCREMENT PRIMARY KEY,
    reading_id INT NOT NULL,
    node_id INT NOT NULL,
    pin_number INT NOT NULL,
    value VARCHAR(100) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (reading_id) REFERENCES sensor_readings(id) ON DELETE CASCADE,
    FOREIGN KEY (node_id) REFERENCES nodes(id) ON DELETE CASCADE,
    INDEX idx_turbidity_node_created (node_id, created_at)
);

CREATE TABLE IF NOT EXISTS rain_data (
    id INT AUTO_INCREMENT PRIMARY KEY,
    reading_id INT NOT NULL,
    node_id INT NOT NULL,
    pin_number INT NOT NULL,
    value VARCHAR(100) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (reading_id) REFERENCES sensor_readings(id) ON DELETE CASCADE,
    FOREIGN KEY (node_id) REFERENCES nodes(id) ON DELETE CASCADE,
    INDEX idx_rain_node_created (node_id, created_at)
);

CREATE TABLE IF NOT EXISTS dashboard_settings (
    setting_key VARCHAR(100) PRIMARY KEY,
    setting_value TEXT NOT NULL,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS sensor_profiles (
    id INT AUTO_INCREMENT PRIMARY KEY,
    node_id INT NOT NULL,
    sensor_key VARCHAR(50) NOT NULL,
    threshold_min DECIMAL(12,4) NULL,
    threshold_max DECIMAL(12,4) NULL,
    calibration_a DECIMAL(12,4) NOT NULL DEFAULT 1.0000,
    calibration_b DECIMAL(12,4) NOT NULL DEFAULT 0.0000,
    calibration_c DECIMAL(12,4) NOT NULL DEFAULT 0.0000,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uniq_node_sensor (node_id, sensor_key),
    INDEX idx_sensor_profiles_node (node_id),
    FOREIGN KEY (node_id) REFERENCES nodes(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS invalid_sensor_data (
    id INT AUTO_INCREMENT PRIMARY KEY,
    node_id INT NOT NULL,
    reading_id INT NULL,
    sensor_name VARCHAR(100) NOT NULL,
    pin_number INT NOT NULL,
    raw_value VARCHAR(100) NOT NULL,
    reason VARCHAR(255) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_invalid_node_created (node_id, created_at)
);

-- Communication health tracking
CREATE TABLE IF NOT EXISTS communication_health (
    id INT AUTO_INCREMENT PRIMARY KEY,
    node_id INT NOT NULL,
    metric_key VARCHAR(50) NOT NULL,
    metric_value VARCHAR(255) NOT NULL,
    recorded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_comm_health_node_recorded (node_id, recorded_at)
);

-- Alerts acknowledge/resolve tracking
CREATE TABLE IF NOT EXISTS alerts (
    id INT AUTO_INCREMENT PRIMARY KEY,
    node_id INT NOT NULL,
    sensor_key VARCHAR(50) NOT NULL,
    label VARCHAR(100) NOT NULL,
    message TEXT NOT NULL,
    severity VARCHAR(20) NOT NULL DEFAULT 'warning',
    status VARCHAR(20) NOT NULL DEFAULT 'active',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    acknowledged_at TIMESTAMP NULL,
    resolved_at TIMESTAMP NULL,
    INDEX idx_alerts_node_created (node_id, created_at),
    INDEX idx_alerts_status (status)
);

-- Relay control command queue (polled by HQ)
-- Note: MyISAM chosen to avoid InnoDB tablespace issues on some XAMPP setups.
CREATE TABLE IF NOT EXISTS relay_commands (
    id INT AUTO_INCREMENT PRIMARY KEY,
    node_id INT NOT NULL,
    relay_id INT NOT NULL,
    action VARCHAR(10) NOT NULL,
    requested_by_chat_id BIGINT NULL,
    requested_by_label VARCHAR(120) NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    status VARCHAR(20) NOT NULL DEFAULT 'pending',
    sent_at TIMESTAMP NULL,
    done_at TIMESTAMP NULL,
    result_message VARCHAR(255) NULL,
    INDEX idx_relay_cmd_node_status_created (node_id, status, created_at)
) ENGINE=MyISAM;

-- Remove old generic tables if they still exist
DROP TABLE IF EXISTS sensor_data_misc;
DROP TABLE IF EXISTS sensor_data;

-- Insert default node
INSERT INTO nodes (id, name, location) VALUES (1, 'Node 1', 'Greenhouse')
ON DUPLICATE KEY UPDATE name = 'Node 1';

INSERT INTO dashboard_settings (setting_key, setting_value) VALUES ('retention_policy', 'keep_forever')
ON DUPLICATE KEY UPDATE setting_value = VALUES(setting_value);

-- Sample queries to get latest readings
-- SELECT * FROM ph_data WHERE node_id = 1 ORDER BY created_at DESC LIMIT 20;
-- SELECT * FROM temperature_data WHERE node_id = 1 ORDER BY created_at DESC LIMIT 20;
