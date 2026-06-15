-- SmartPonic Phase 4 Migration
-- Tables needed for Telegram alerts, approvals, and cooldown tracking

-- ============================================
-- Alerts tracking (active/acknowledged/resolved)
-- ============================================
CREATE TABLE IF NOT EXISTS alerts (
    id          INT AUTO_INCREMENT PRIMARY KEY,
    hardware_id VARCHAR(16) NOT NULL,
    alert_key   VARCHAR(64) NOT NULL,
    type        VARCHAR(32) NOT NULL DEFAULT 'threshold',
    message     VARCHAR(255) NOT NULL,
    status      ENUM('active','acknowledged','resolved') DEFAULT 'active',
    created_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_hardware_id (hardware_id),
    INDEX idx_status (status),
    INDEX idx_alert_key (alert_key)
) ENGINE=InnoDB;

-- ============================================
-- Telegram alert cooldown state
-- ============================================
CREATE TABLE IF NOT EXISTS telegram_alert_state (
    state_key   VARCHAR(190) PRIMARY KEY,
    last_sent_at TIMESTAMP NULL,
    updated_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB;

-- ============================================
-- Pending approvals for human-in-the-loop
-- ============================================
CREATE TABLE IF NOT EXISTS pending_approvals (
    id           INT AUTO_INCREMENT PRIMARY KEY,
    command_id   INT UNSIGNED NOT NULL DEFAULT 0,
    rule_id      INT DEFAULT 0,
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
