@echo off
setlocal

REM Runs the Driftline Godot headless server with Ctrl+C support.
REM This calls the PowerShell script which creates a quit-flag file on Ctrl+C.

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0run_server.ps1"
