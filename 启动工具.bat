@echo off
if "%~1"=="" (
    start "Powkiddy A20 Toolkit" cmd /k "%~f0" --run
    exit /b
)

setlocal EnableDelayedExpansion
color 0A
set ZH=powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0zh.ps1"
set PS=powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0modules"

:: ============================================================
:MAIN_MENU
cls
echo.
echo   ==========================================================
%ZH% title
echo   ==========================================================
echo.
%ZH% main_1
%ZH% main_2
%ZH% main_3
%ZH% main_4
%ZH% main_0
echo.
echo   ==========================================================
echo.
set CHOICE=
for /f "delims=" %%P in ('%ZH% prompt') do set PROMPT_TEXT=%%P
set /p CHOICE="  %PROMPT_TEXT%: "

if "!CHOICE!"=="1" goto :MAGISK_MENU
if "!CHOICE!"=="2" goto :HDMI_MENU
if "!CHOICE!"=="3" goto :FACTORY_MENU
if "!CHOICE!"=="4" goto :GAMEPAD_MENU
if "!CHOICE!"=="0" goto :END
echo.
%ZH% invalid
timeout /t 2 /nobreak >nul
goto :MAIN_MENU

:: ============================================================
:MAGISK_MENU
cls
echo.
echo   ==========================================================
%ZH% magisk_t
echo   ==========================================================
echo.
%ZH% magisk_1
%ZH% magisk_2
%ZH% magisk_3
%ZH% back
echo.
echo   ==========================================================
echo.
set CHOICE=
for /f "delims=" %%P in ('%ZH% prompt') do set PROMPT_TEXT=%%P
set /p CHOICE="  %PROMPT_TEXT%: "

if "!CHOICE!"=="1" goto :REPAIR_MAGISK
if "!CHOICE!"=="2" goto :INSTALL_MAGISK
if "!CHOICE!"=="3" goto :FIX_ENV
if "!CHOICE!"=="0" goto :MAIN_MENU
echo.
%ZH% invalid
timeout /t 2 /nobreak >nul
goto :MAGISK_MENU

:: ============================================================
:HDMI_MENU
cls
echo.
echo   ==========================================================
%ZH% hdmi_t
echo   ==========================================================
echo.
%ZH% hdmi_1
%ZH% hdmi_2
%ZH% back
echo.
echo   ==========================================================
echo.
set CHOICE=
for /f "delims=" %%P in ('%ZH% prompt') do set PROMPT_TEXT=%%P
set /p CHOICE="  %PROMPT_TEXT%: "

if "!CHOICE!"=="1" goto :INSTALL_HDMI
if "!CHOICE!"=="2" goto :UNINSTALL_HDMI
if "!CHOICE!"=="0" goto :MAIN_MENU
echo.
%ZH% invalid
timeout /t 2 /nobreak >nul
goto :HDMI_MENU

:: ============================================================
:FACTORY_MENU
cls
echo.
echo   ==========================================================
%ZH% factory_t
echo   ==========================================================
echo.
%ZH% factory_1
%ZH% factory_2
%ZH% factory_3
%ZH% back
echo.
echo   ==========================================================
echo.
set CHOICE=
for /f "delims=" %%P in ('%ZH% prompt') do set PROMPT_TEXT=%%P
set /p CHOICE="  %PROMPT_TEXT%: "

if "!CHOICE!"=="1" goto :RESTORE_BOOT
if "!CHOICE!"=="2" goto :RESTORE_SU
if "!CHOICE!"=="3" goto :FULL_RESTORE
if "!CHOICE!"=="0" goto :MAIN_MENU
echo.
%ZH% invalid
timeout /t 2 /nobreak >nul
goto :FACTORY_MENU

:: ============================================================
:GAMEPAD_MENU
cls
echo.
echo   ==========================================================
%ZH% gamepad_t
echo   ==========================================================
echo.
%ZH% gamepad_1
%ZH% gamepad_2
%ZH% back
echo.
echo   ==========================================================
echo.
set CHOICE=
for /f "delims=" %%P in ('%ZH% prompt') do set PROMPT_TEXT=%%P
set /p CHOICE="  %PROMPT_TEXT%: "

if "!CHOICE!"=="1" goto :INSTALL_GAMEPAD
if "!CHOICE!"=="2" goto :UNINSTALL_GAMEPAD
if "!CHOICE!"=="0" goto :MAIN_MENU
echo.
%ZH% invalid
timeout /t 2 /nobreak >nul
goto :GAMEPAD_MENU

:: ============================================================
:REPAIR_MAGISK
echo.
%PS%\Repair-Magisk.ps1
echo.
pause
goto :MAGISK_MENU

:: ============================================================
:INSTALL_MAGISK
echo.
%PS%\Install-Magisk.ps1
echo.
pause
goto :MAGISK_MENU

:: ============================================================
:FIX_ENV
echo.
%PS%\Fix-MagiskEnv.ps1
echo.
pause
goto :MAGISK_MENU

:: ============================================================
:INSTALL_HDMI
echo.
%PS%\HdmiMonitor.ps1 -Action install
echo.
pause
goto :HDMI_MENU

:: ============================================================
:UNINSTALL_HDMI
echo.
%PS%\HdmiMonitor.ps1 -Action uninstall
echo.
pause
goto :HDMI_MENU

:: ============================================================
:RESTORE_BOOT
echo.
%PS%\Restore-FactoryBoot.ps1
echo.
pause
goto :FACTORY_MENU

:: ============================================================
:RESTORE_SU
echo.
%PS%\Restore-FactorySu.ps1
echo.
pause
goto :FACTORY_MENU

:: ============================================================
:FULL_RESTORE
echo.
%PS%\Full-Restore.ps1
echo.
pause
goto :FACTORY_MENU

:: ============================================================
:INSTALL_GAMEPAD
echo.
%PS%\GamepadFix.ps1 -Action install
echo.
pause
goto :GAMEPAD_MENU

:: ============================================================
:UNINSTALL_GAMEPAD
echo.
%PS%\GamepadFix.ps1 -Action uninstall
echo.
pause
goto :GAMEPAD_MENU

:: ============================================================
:END
echo.
%ZH% bye
echo.
timeout /t 1 /nobreak >nul
