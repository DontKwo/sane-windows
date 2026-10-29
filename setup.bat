@echo off
setlocal
title Sane Windows - Windows QOL ^& System Tweaks

echo ========================================================
echo  Sane Windows: Windows QOL, Performance ^& Ergonomics
echo ========================================================
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup.ps1" %*

echo.
pause
