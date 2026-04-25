# SmartPonic Telegram (Option B: Bidirectional)

This repo supports:
- Outbound alerts from `php/receive_data.php` (ABNORMAL/CRITICAL)
- Bidirectional commands via long polling runner `php/telegram_poll.php`

## 1) Create local config (not committed)

Copy `php/telegram_config.example.php` to `php/telegram_config.php` and fill:
- `bot_token`
- `allowed_chat_ids` (admin allowlist)
- `default_alert_chat_id` (where alerts go)

`php/telegram_config.php` is ignored by `.gitignore`.

## 2) Get your chat id

Run the poller once, then send `/whoami` to your bot:

`php php/telegram_poll.php --once`

It will reply with your chat id. Add it to `allowed_chat_ids`.

## 3) Run long polling (Windows Task Scheduler)

Recommended: run every 1 minute (or keep a long-running task).

Example action:
- Program/script: `C:\xampp\php\php.exe`
- Arguments: `php\telegram_poll.php --once`
- Start in: `C:\xampp\htdocs\smartponic` (or your repo `php` folder)

## 4) Commands

- `/status [node]`
- `/readings [node]`
- `/alerts [node]`
- `/ack <node> <sensor_key>`
- `/resolve <node> <sensor_key>`
- `/relay <node> <relay_id 0-15> <on|off>`
- `/queue [node]`

## 5) Relay control (requires firmware integration)

Telegram `/relay` queues a command into MySQL table `relay_commands`.

To actually toggle a relay, the HQ firmware must:
- Poll `control_queue.php` (signed, like `receive_data.php`) to fetch pending commands.
- Send a LoRa control packet to the target node to apply the relay action.
- POST back `ack` to `control_queue.php` with `done|failed`.
