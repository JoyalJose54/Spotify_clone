@echo off
title Spotify Ingestion Backend (PC + Cloudflare Tunnel)
echo ========================================================
echo   Starting Spotify Ingestion Backend on PC
echo ========================================================
echo.

cd /d "%~dp0cloud_functions"

echo [1/2] Launching Python Backend on http://127.0.0.1:8080...
start "Spotify Backend Server" cmd /k "python main.py"

echo [2/2] Launching Cloudflare Tunnel for secure mobile access...
echo.
echo Look for the link ending in .trycloudflare.com below!
echo Copy that link and paste it in your Flutter app's Ingestion settings.
echo ========================================================
echo.

"C:\Program Files (x86)\cloudflared\cloudflared.exe" tunnel --url http://127.0.0.1:8080
pause
