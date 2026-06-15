@echo off
title SmartPonic Stopper
echo ============================================
echo   Stopping SmartPonic Services
echo ============================================
echo.

set XAMPP_DIR=C:\xampp

echo Stopping Apache...
taskkill /F /IM httpd.exe >nul 2>&1

echo Stopping MySQL...
taskkill /F /IM mysqld.exe >nul 2>&1

echo Stopping Laravel...
taskkill /F /IM php.exe >nul 2>&1

echo Stopping Vite (Node)...
taskkill /F /IM node.exe >nul 2>&1

echo.
echo ============================================
echo   All services stopped!
echo ============================================
pause
