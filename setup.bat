@echo off
setlocal
title Useful Setup - Windows QOL ^& System Tweaks

echo ========================================================
echo  Useful Setup: Windows QOL, Performance ^& Ergonomics
echo ========================================================
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup.ps1" %*

echo.
pause
