-- ============================================================
-- SmartPonic v2 — Turso Seed Data
-- ============================================================
-- Usage:  turso db shell smartponic-db < database/seed_turso.sql
-- ============================================================

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

-- Default Telegram bot state
INSERT OR IGNORE INTO telegram_bot_state (state_key, state_value) VALUES
('last_update_id', '0'),
('bot_status', 'stopped');
