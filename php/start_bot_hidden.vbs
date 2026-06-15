' SmartPonic Telegram Bot — hidden startup launcher
' This runs the bot with no console window.

Dim shell
Set shell = CreateObject("WScript.Shell")
shell.Run "C:\xampp\php\php.exe C:\Users\HAKIMIE\smartponic_v2\PHP\telegram_poll.php --loop", 0, False
Set shell = Nothing
