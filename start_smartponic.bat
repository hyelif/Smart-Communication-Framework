@echo off
title SmartPonic Launcher
echo ============================================
echo   SmartPonic System Launcher
echo ============================================
echo.

set XAMPP_DIR=C:\xampp
set DASHBOARD_DIR=C:\Users\HAKIMIE\smartponic_v2\dashboard
set PHP_DIR=C:\Users\HAKIMIE\smartponic_v2\PHP

echo Stopping existing services...
taskkill /F /IM httpd.exe >nul 2>&1
taskkill /F /IM mysqld.exe >nul 2>&1
timeout /t 2 /nobreak >nul

echo.
echo [1/5] Starting Apache (background)...
powershell -Command "Start-Process '%XAMPP_DIR%\apache\bin\httpd.exe' -WindowStyle Hidden"

echo [2/5] Starting MySQL (background)...
powershell -Command "Start-Process '%XAMPP_DIR%\mysql\bin\mysqld.exe' -ArgumentList '--defaults-file=%XAMPP_DIR%\mysql\bin\my.ini','--standalone' -WindowStyle Hidden"

timeout /t 5 /nobreak >nul

echo [3/5] Starting Laravel...
start "Laravel" cmd /k "cd /d %DASHBOARD_DIR% && php artisan serve --host=0.0.0.0 --port=8000"

timeout /t 3 /nobreak >nul

echo [4/5] Starting Vite...
start "Vite" cmd /k "cd /d %DASHBOARD_DIR% && npm run dev -- --host 0.0.0.0"

echo [5/5] Starting Telegram Bot (background)...
powershell -Command "Start-Process php -ArgumentList 'telegram_poll.php --loop' -WorkingDirectory '%PHP_DIR%' -WindowStyle Hidden"

echo.
echo ============================================
echo   All services started!
echo ============================================
echo.
echo   Local:   http://127.0.0.1:8000
echo   Network: http://192.168.0.247:8000
echo.
echo   Vite:    http://localhost:5173
echo.
echo   Keep Laravel and Vite windows open!
echo ============================================
pause
