@echo off
title Stop Spotify Backend & Tunnel
echo ========================================================
echo   Stopping Spotify Ingestion Backend and Ngrok Tunnel
echo ========================================================
echo.
taskkill /F /IM python.exe /T 2>nul
taskkill /F /IM ngrok.exe /T 2>nul
taskkill /F /IM cloudflared.exe /T 2>nul
echo.
echo All backend and tunnel services have been stopped.
echo ========================================================
timeout /t 3 >nul
