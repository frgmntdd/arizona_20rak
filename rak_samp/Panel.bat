@echo off
cd /d "%~dp0"
where py >nul 2>nul
if errorlevel 1 (
  echo Python 3.10 or newer is required. Install Python from python.org and run this file again.
  pause
  exit /b 1
)
py -3 panel\server.py --open
pause
