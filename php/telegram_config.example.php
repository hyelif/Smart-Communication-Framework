<?php
// Copy to `php/telegram_config.php` (ignored by git) and fill in real values.

return [
    // Bot token from @BotFather (keep secret; never commit).
    'bot_token' => '8635772990:AAE_sU0VGXRovOoJCNahlwbeJJf5YGHkqeI',

    // Allowlist of chat IDs permitted to use control commands.
    // Example: [123456789, -1001234567890]
    'allowed_chat_ids' => [],

    // Default chat ID to receive alerts (optional).
    'default_alert_chat_id' => null,

    // Anti-spam defaults (seconds).
    'cooldown_critical_s' => 0,
    'cooldown_abnormal_s' => 300,
];
