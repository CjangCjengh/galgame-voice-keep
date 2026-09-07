@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0patch-voice-keep.ps1" -Mode Launch -GameDirectory "%~dp0"
if errorlevel 1 pause
