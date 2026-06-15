-- SmartPonic Seed Data for Supabase
-- Run after 001_init_schema.sql

-- ============================================
-- Default sensor profiles
-- ============================================
INSERT INTO sensor_profiles (sensor_key, label, unit, family, accent, threshold_min, threshold_max, calibration_a, calibration_b, calibration_c, cal_label_a, cal_label_b, cal_label_c) VALUES
    ('temperature', 'Temperature', 'C', 'DHT22', '#fce442', 22, 34, 1, 0, 0, 'Scale', 'Offset', 'Reserve'),
    ('humidity',    'Humidity',    '%', 'DHT22', '#00fbfb', 45, 85, 1, 0, 0, 'Scale', 'Offset', 'Reserve'),
    ('waterTemp',   'Water Temp',  'C', 'Water Temperature', '#1e95f2', 20, 30, 1, 0, 0, 'Scale', 'Offset', 'Reserve'),
    ('ph',          'pH',           'pH', 'Water Quality', '#9ecaff', 5.8, 7.2, 1, 0, 0, 'Slope', 'Offset', 'Reserve'),
    ('tds',         'TDS',          'ppm', 'Water Quality', '#5cf2b5', 300, 1200, 1, 0, 0, 'Multiplier', 'Offset', 'Reserve'),
    ('turbidity',   'Turbidity',    'NTU', 'Water Quality', '#ffa94d', 0, 120, 1, 0, 0, 'Scale', 'Offset', 'Clear Ref'),
    ('rain',        'Rain',         'state', 'Environment', '#ff7aa2', NULL, NULL, 1, 0, 0, 'Scale', 'Offset', 'Reserve')
ON CONFLICT (sensor_key) DO UPDATE SET
    label = EXCLUDED.label,
    unit = EXCLUDED.unit,
    family = EXCLUDED.family,
    accent = EXCLUDED.accent,
    threshold_min = EXCLUDED.threshold_min,
    threshold_max = EXCLUDED.threshold_max;

-- ============================================
-- Default dashboard settings
-- ============================================
INSERT INTO dashboard_settings (setting_key, setting_value) VALUES
    ('retention_policy', 'keep_forever'),
    ('export_format', 'excel'),
    ('default_range', '24h'),
    ('alert_notifications', 'dashboard_only')
ON CONFLICT (setting_key) DO NOTHING;
