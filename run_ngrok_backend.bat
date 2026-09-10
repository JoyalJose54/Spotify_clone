@echo off
title Spotify Ingestion Backend (Ngrok Permanent Tunnel)
echo ========================================================
echo   Starting Spotify Ingestion Backend (Permanent Tunnel)
echo ========================================================
echo.

cd /d "%~dp0cloud_functions"

echo [1/2] Starting Python Backend on http://127.0.0.1:8080...
start "Spotify Backend Server" cmd /k "python main.py"

set NGROK_DOMAIN=removal-magnolia-overhand.ngrok-free.dev
if exist "%~dp0ngrok_domain.txt" (
    set /p NGROK_DOMAIN=<"%~dp0ngrok_domain.txt"
)

echo.
echo [2/2] Launching Permanent Tunnel at https://%NGROK_DOMAIN% ...
echo ========================================================
echo   Permanent URL: https://%NGROK_DOMAIN%
echo   Leave this window open while using the app!
echo   (For silent background auto-start on boot, run: run_backend_silent.vbs)
echo ========================================================
echo.
ngrok http --domain=%NGROK_DOMAIN% 8080
pause
