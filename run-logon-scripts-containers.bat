@echo off
title Redgate Demo Environment — Starting Up

REM ============================================================
REM bootstrap.bat
REM Orchestrates all numbered logon scripts in order.
REM Called by Task Scheduler on user logon.
REM ============================================================

set SCRIPT_DIR=%~dp0

REM Step 1 — Git pull to get latest versions of all scripts
echo Pulling latest scripts from Git...
pwsh.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Normal -File "%SCRIPT_DIR%_git_pull.ps1"

REM Step 2 — Run all numbered scripts in order
REM The for loop picks up any new scripts added to Git automatically
for %%f in ("%SCRIPT_DIR%??.ps1" "%SCRIPT_DIR%??_*.ps1") do (
    pwsh.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Normal -File "%%f"
    if errorlevel 1 (
        echo.
        echo ERROR: Bootstrap failed at %%~nf
        echo Check logs at C:\git\Admin\logs\
        echo.
        pause
        exit /b 1
    )
)

exit /b 0