<?php
/**
 * SmartPonic Telegram Bot Configuration
 *
 * Copy this file to telegram_config.php and fill in your values.
 * telegram_config.php is gitignored — secrets stay local.
 */

// Bot token from @BotFather
define('TELEGRAM_BOT_TOKEN', '1234567890:ABCdefGHIjklMNOpqrsTUVwxyzABCDEFGHIJklmno');

// Allowed chat IDs — users who can issue commands.
// Find your chat ID by sending /start to the bot and checking the logs,
// or use /whoami once the bot is running.
define('TELEGRAM_ALLOWED_CHAT_IDS', serialize([
    // 123456789,  // replace with your chat ID
]));

// API base URL (no trailing slash)
define('TELEGRAM_API_URL', 'https://api.telegram.org/bot' . TELEGRAM_BOT_TOKEN);
