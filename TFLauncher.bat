@echo off
setlocal enabledelayedexpansion

:: Keep window open on error
if "%1"=="RELAUNCH" goto START
cmd /c "%~f0" RELAUNCH
pause
exit

:START
title The Fast Launcher - Minecraft Launcher v0.2
color 0a

:: TFLauncher Configuration
set "LAUNCHER_DIR=%~dp0"
set "VERSIONS_DIR=%LAUNCHER_DIR%versions"
set "LIBRARIES_DIR=%LAUNCHER_DIR%libraries"
set "ASSETS_DIR=%LAUNCHER_DIR%assets"
set "SETTINGS_FILE=%LAUNCHER_DIR%settings.txt"
set "MANIFEST_FILE=%LAUNCHER_DIR%version_manifest_v2.json"
set "MANIFEST_URL=https://piston-meta.mojang.com/mc/game/version_manifest_v2.json"

:: Create launcher directories
if not exist "%VERSIONS_DIR%" mkdir "%VERSIONS_DIR%"
if not exist "%LIBRARIES_DIR%" mkdir "%LIBRARIES_DIR%"
if not exist "%ASSETS_DIR%" mkdir "%ASSETS_DIR%"

:: Load settings
call :LOAD_SETTINGS

:MAIN_MENU
cls
echo.
echo  ========================================
echo    TFLauncher v0.2 By TryFast
echo  ========================================
echo.
echo  Player: %PLAYER_NAME%
echo  Version: %GAME_VERSION%
echo  RAM: %MIN_RAM%MB - %MAX_RAM%MB
echo.
echo  ========================================
echo.
echo  [1] Launch Minecraft
echo  [2] Select Version
echo  [3] Download Version
echo  [4] Settings
echo  [5] Exit
echo.
echo  ========================================
echo.
set /p choice="Select an option: "

if "%choice%"=="1" goto LAUNCH_GAME
if "%choice%"=="2" goto SELECT_VERSION
if "%choice%"=="3" goto DOWNLOAD_VERSION
if "%choice%"=="4" goto SETTINGS_MENU
if "%choice%"=="5" goto EXIT
goto MAIN_MENU

:LAUNCH_GAME
cls
echo.
echo  ========================================
echo    Launching Minecraft %GAME_VERSION%
echo  ========================================
echo.

:: Validate everything first
if "%GAME_VERSION%"=="" (
    echo  ERROR: No version selected!
    echo.
    pause
    goto MAIN_MENU
)

if "%PLAYER_NAME%"=="" (
    echo  ERROR: No player name set!
    echo.
    pause
    goto MAIN_MENU
)

:: Find Java
call :FIND_JAVA
if "%JAVA_EXEC%"=="" (
    echo  ERROR: Java not found!
    echo.
    pause
    goto MAIN_MENU
)

:: Check version exists
if not exist "%VERSIONS_DIR%\%GAME_VERSION%\%GAME_VERSION%.json" (
    echo  ERROR: Version files not found!
    echo  Please download the version first.
    echo.
    pause
    goto MAIN_MENU
)

echo  Status: All checks passed
echo  Java: %JAVA_EXEC%
echo  Player: %PLAYER_NAME%
echo  Version: %GAME_VERSION%
echo.

:: Test if PowerShell script exists
call :CREATE_LAUNCH_SCRIPT

echo  Starting PowerShell launcher...
echo.

:: Create temporary wrapper script with proper escaping
(
echo $LauncherDir = '%LAUNCHER_DIR%'
echo $GameVersion = '%GAME_VERSION%'
echo $PlayerName = '%PLAYER_NAME%'
echo $MinRam = '%MIN_RAM%'
echo $MaxRam = '%MAX_RAM%'
echo $JavaExec = '%JAVA_EXEC%'
echo $ExtraJvmArgs = '%EXTRA_JVM_ARGS%'
echo.
echo ^& '%LAUNCHER_DIR%temp_launch_minecraft.ps1' -LauncherDir $LauncherDir -GameVersion $GameVersion -PlayerName $PlayerName -MinRam $MinRam -MaxRam $MaxRam -JavaExec $JavaExec -ExtraJvmArgs $ExtraJvmArgs
) > "%LAUNCHER_DIR%temp_wrapper.ps1"

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%LAUNCHER_DIR%temp_wrapper.ps1"

set RESULT=%errorlevel%

del "%LAUNCHER_DIR%temp_wrapper.ps1" 2>nul
del "%LAUNCHER_DIR%temp_launch_minecraft.ps1" 2>nul

echo.
if %RESULT% NEQ 0 (
    echo  Launch failed with error code: %RESULT%
    echo  Check the error messages above.
) else (
    echo  Launch completed!
)
echo.
pause
goto MAIN_MENU

:SELECT_VERSION
cls
echo.
echo  ========================================
echo    Select Minecraft Version
echo  ========================================
echo.

set version_count=0

if not exist "%VERSIONS_DIR%\" (
    echo  No versions folder found.
    pause
    goto MAIN_MENU
)

echo  Installed versions:
echo.

for /f "delims=" %%D in ('dir /b /ad "%VERSIONS_DIR%" 2^>nul') do (
    if exist "%VERSIONS_DIR%\%%D\%%D.json" (
        set /a version_count+=1
        echo  [!version_count!] %%D
        set "ver_!version_count!=%%D"
    )
)

if %version_count%==0 (
    echo  No valid versions found.
    echo  Please download a version first.
    pause
    goto MAIN_MENU
)

echo.
echo  [0] Back to main menu
echo.
set /p ver_choice="Select version number: "

if "%ver_choice%"=="0" goto MAIN_MENU

if defined ver_%ver_choice% (
    for %%V in (!ver_%ver_choice%!) do set "GAME_VERSION=%%V"
    call :SAVE_SETTINGS
    echo.
    echo  Version set to: %GAME_VERSION%
    timeout /t 2 /nobreak >nul
) else (
    echo.
    echo  Invalid selection!
    pause
)
goto MAIN_MENU

:DOWNLOAD_VERSION
cls
echo.
echo  ========================================
echo    Download Minecraft Version
echo  ========================================
echo.
echo  Downloading version manifest...

if exist "%MANIFEST_FILE%" (
    echo  Using cached manifest...
) else (
    echo  Fetching from Mojang...
    powershell -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri '%MANIFEST_URL%' -OutFile '%MANIFEST_FILE%'" 2>nul
)

if not exist "%MANIFEST_FILE%" (
    echo  ERROR: Failed to download manifest!
    pause
    goto MAIN_MENU
)

echo  Manifest ready!
echo.
echo  Available versions (showing first 20):
echo.

powershell -NoProfile -ExecutionPolicy Bypass -Command "$json = Get-Content '%MANIFEST_FILE%' -Raw | ConvertFrom-Json; $json.versions | Select-Object -First 20 | ForEach-Object { Write-Host ('  ' + $_.id + ' (' + $_.type + ')') }"

echo.
set /p version_input="Enter version to install (or 0 to cancel): "

if "%version_input%"=="0" goto MAIN_MENU
if "%version_input%"=="" goto MAIN_MENU

echo.
echo  Searching for version %version_input%...

if not exist "%VERSIONS_DIR%\%version_input%" mkdir "%VERSIONS_DIR%\%version_input%"

powershell -NoProfile -ExecutionPolicy Bypass -Command "try { $json = Get-Content '%MANIFEST_FILE%' -Raw | ConvertFrom-Json; $version = $json.versions | Where-Object { $_.id -eq '%version_input%' }; if ($version) { $version.url | Out-File '%LAUNCHER_DIR%temp_url.txt' -Encoding ASCII; exit 0 } else { exit 1 } } catch { exit 1 }"

if errorlevel 1 (
    echo  ERROR: Version not found!
    pause
    goto MAIN_MENU
)

set /p VERSION_URL=<"%LAUNCHER_DIR%temp_url.txt"
del "%LAUNCHER_DIR%temp_url.txt" 2>nul

echo  Found! Downloading manifest...

powershell -NoProfile -ExecutionPolicy Bypass -Command "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri '%VERSION_URL%' -OutFile '%VERSIONS_DIR%\%version_input%\%version_input%.json'"

if not exist "%VERSIONS_DIR%\%version_input%\%version_input%.json" (
    echo  ERROR: Failed to download!
    pause
    goto MAIN_MENU
)

echo  Manifest downloaded!
echo.
echo  Downloading game files (this may take a while)...
echo.

call :CREATE_DOWNLOAD_SCRIPT

powershell -NoProfile -ExecutionPolicy Bypass -File "%LAUNCHER_DIR%temp_download_version.ps1" -VersionDir "%VERSIONS_DIR%\%version_input%" -VersionName "%version_input%" -LibrariesDir "%LIBRARIES_DIR%" -AssetsDir "%ASSETS_DIR%"

set DL_RESULT=%errorlevel%

del "%LAUNCHER_DIR%temp_download_version.ps1" 2>nul

if %DL_RESULT% NEQ 0 (
    echo.
    echo  Download failed!
) else (
    echo.
    echo  Download completed!
    set "GAME_VERSION=%version_input%"
    call :SAVE_SETTINGS
)
pause
goto MAIN_MENU

:SETTINGS_MENU
cls
echo.
echo  ========================================
echo    Settings
echo  ========================================
echo.
echo  [1] Set Player Name
echo  [2] Memory Configuration
echo  [3] Java Configuration
echo  [4] JVM Arguments
echo  [5] Back to Main Menu
echo.
set /p schoice="Select option: "

if "%schoice%"=="1" goto SET_PLAYER_NAME
if "%schoice%"=="2" goto MEMORY_CONFIG
if "%schoice%"=="3" goto JAVA_CONFIG
if "%schoice%"=="4" goto SET_JVM_ARGS
if "%schoice%"=="5" goto MAIN_MENU
goto SETTINGS_MENU

:SET_PLAYER_NAME
cls
echo.
set /p new_name="Enter player name: "
if not "%new_name%"=="" (
    set "PLAYER_NAME=%new_name%"
    call :SAVE_SETTINGS
    echo  Player name set to: %PLAYER_NAME%
) else (
    echo  Player name cannot be empty!
)
pause
goto SETTINGS_MENU

:MEMORY_CONFIG
cls
echo.
echo  ========================================
echo    Memory Settings
echo  ========================================
echo.
echo  Current: Min %MIN_RAM% MB, Max %MAX_RAM% MB
echo  Recommended: Min 1024, Max 2048-4096
echo.
set /p new_min="Minimum RAM (MB): "
set /p new_max="Maximum RAM (MB): "

if "%new_min%"=="" set "new_min=%MIN_RAM%"
if "%new_max%"=="" set "new_max=%MAX_RAM%"

set "MIN_RAM=%new_min%"
set "MAX_RAM=%new_max%"
call :SAVE_SETTINGS

echo.
echo  Memory updated!
pause
goto SETTINGS_MENU

:JAVA_CONFIG
cls
echo.
echo  ========================================
echo    Java Configuration
echo  ========================================
echo.

echo  Local Runtimes:
if exist "%LAUNCHER_DIR%runtime\jre-legacy\bin\javaw.exe" (
    echo  [OK] Legacy: runtime\jre-legacy\bin\javaw.exe
) else (
    echo  [--] Legacy: Not found
)
if exist "%LAUNCHER_DIR%runtime\jdk21\bin\javaw.exe" (
    echo  [OK] Modern: runtime\jdk21\bin\javaw.exe
) else (
    echo  [--] Modern: Not found
)
echo.

call :FIND_JAVA
if not "%JAVA_FOUND%"=="" (
    echo  Current: %JAVA_FOUND%
) else (
    echo  Current: Not found
)

echo.
echo  [1] Auto-detect Java
echo  [2] Set Custom Path
echo  [3] Clear Saved Path
echo  [4] Back
echo.
set /p jc="Select: "

if "%jc%"=="1" (
    set "JAVA_PATH="
    call :SAVE_SETTINGS
    call :FIND_JAVA
    echo.
    if not "%JAVA_FOUND%"=="" (
        echo  Detected: %JAVA_FOUND%
        set "JAVA_PATH=%JAVA_FOUND%"
        call :SAVE_SETTINGS
    ) else (
        echo  No Java found!
    )
    pause
    goto JAVA_CONFIG
)

if "%jc%"=="2" (
    echo.
    set /p custom_path="Enter path to javaw.exe or java.exe: "
    if exist "!custom_path!" (
        set "JAVA_PATH=!custom_path!"
        call :SAVE_SETTINGS
        echo  Java path saved!
    ) else (
        echo  ERROR: File not found!
    )
    pause
    goto JAVA_CONFIG
)

if "%jc%"=="3" (
    set "JAVA_PATH="
    call :SAVE_SETTINGS
    echo  Path cleared!
    pause
    goto JAVA_CONFIG
)

if "%jc%"=="4" goto SETTINGS_MENU
goto JAVA_CONFIG

:SET_JVM_ARGS
cls
echo.
echo  Current JVM Args: %EXTRA_JVM_ARGS%
echo.
echo  Example: -XX:+UseG1GC -XX:+UnlockExperimentalVMOptions
echo.
set /p new_args="Enter JVM arguments (or press Enter to keep current): "
if not "%new_args%"=="" (
    set "EXTRA_JVM_ARGS=%new_args%"
    call :SAVE_SETTINGS
    echo  JVM arguments updated!
) else (
    echo  Keeping current arguments.
)
pause
goto SETTINGS_MENU

:LOAD_SETTINGS
set "PLAYER_NAME=Player"
set "GAME_VERSION=1.8.9"
set "MIN_RAM=1024"
set "MAX_RAM=2048"
set "EXTRA_JVM_ARGS="
set "JAVA_PATH="

if exist "%SETTINGS_FILE%" (
    for /f "usebackq tokens=1* delims==" %%a in ("%SETTINGS_FILE%") do (
        set "%%a=%%b"
    )
)
exit /b 0

:SAVE_SETTINGS
(
    echo PLAYER_NAME=%PLAYER_NAME%
    echo GAME_VERSION=%GAME_VERSION%
    echo MIN_RAM=%MIN_RAM%
    echo MAX_RAM=%MAX_RAM%
    echo EXTRA_JVM_ARGS=%EXTRA_JVM_ARGS%
    echo JAVA_PATH=%JAVA_PATH%
) > "%SETTINGS_FILE%"
exit /b 0

:FIND_JAVA
set "JAVA_EXEC="
set "JAVA_FOUND="

:: Check saved path first
if defined JAVA_PATH (
    if exist "%JAVA_PATH%" (
        set "JAVA_EXEC=%JAVA_PATH%"
        set "JAVA_FOUND=%JAVA_PATH%"
        exit /b 0
    )
)

:: Check local runtimes
if exist "%LAUNCHER_DIR%runtime\jdk21\bin\javaw.exe" (
    set "JAVA_EXEC=%LAUNCHER_DIR%runtime\jdk21\bin\javaw.exe"
    set "JAVA_FOUND=%LAUNCHER_DIR%runtime\jdk21\bin\javaw.exe"
    exit /b 0
)

if exist "%LAUNCHER_DIR%runtime\jre-legacy\bin\javaw.exe" (
    set "JAVA_EXEC=%LAUNCHER_DIR%runtime\jre-legacy\bin\javaw.exe"
    set "JAVA_FOUND=%LAUNCHER_DIR%runtime\jre-legacy\bin\javaw.exe"
    exit /b 0
)

:: Check system PATH
where javaw.exe >nul 2>&1
if %errorlevel%==0 (
    for /f "delims=" %%i in ('where javaw.exe 2^>nul') do (
        set "JAVA_EXEC=%%i"
        set "JAVA_FOUND=%%i"
        exit /b 0
    )
)

:: Check common paths
for %%P in (
    "C:\Program Files\Java"
    "C:\Program Files (x86)\Java"
    "C:\Program Files\Eclipse Adoptium"
) do (
    if exist %%P (
        for /f "delims=" %%D in ('dir /b /ad %%P 2^>nul') do (
            if exist "%%P\%%D\bin\javaw.exe" (
                set "JAVA_EXEC=%%P\%%D\bin\javaw.exe"
                set "JAVA_FOUND=%%P\%%D\bin\javaw.exe"
                exit /b 0
            )
        )
    )
)

exit /b 1


:CREATE_DOWNLOAD_SCRIPT
setlocal
set "PS1_FILE=%LAUNCHER_DIR%temp_download_version.ps1"
(
echo cGFyYW0oDQogICAgW3N0cmluZ10kVmVyc2lvbkRpciwNCiAgICBbc3RyaW5nXSRWZXJzaW9uTmFtZSwNCiAgICBbc3RyaW5nXSRMaWJyYXJpZXNEaXIsDQogICAgW3N0cmluZ10kQXNzZXRzRGlyDQopDQoNCiRFcnJvckFjdGlvblByZWZlcmVuY2UgPSAnQ29udGludWUnDQokUHJvZ3Jlc3NQcmVmZXJlbmNlID0gJ1NpbGVudGx5Q29udGludWUnDQpbTmV0LlNlcnZpY2VQb2ludE1hbmFnZXJdOjpTZWN1cml0eVByb3RvY29sID0gW05ldC5TZWN1cml0eVByb3RvY29sVHlwZV06OlRsczEyDQoNCmZ1bmN0aW9uIERvd25sb2FkLVdpdGhSZXRyeSB7DQogICAgcGFyYW0oDQogICAgICAgIFtzdHJpbmddJFVybCwNCiAgICAgICAgW3N0cmluZ10kT3V0RmlsZSwNCiAgICAgICAgW2ludF0kTWF4UmV0cmllcyA9IDMNCiAgICApDQogICAgDQogICAgJHJldHJ5Q291bnQgPSAwDQogICAgd2hpbGUgKCRyZXRyeUNvdW50IC1sdCAkTWF4UmV0cmllcykgew0KICAgICAgICB0cnkgew0KICAgICAgICAgICAgJHBhcmVudERpciA9IFNwbGl0LVBhdGggJE91dEZpbGUgLVBhcmVudA0KICAgICAgICAgICAgaWYgKCEoVGVzdC1QYXRoICRwYXJlbnREaXIpKSB7DQogICAgICAgICAgICAgICAgTmV3LUl0ZW0gLUl0ZW1UeXBlIERpcmVjdG9yeSAtUGF0aCAkcGFyZW50RGlyIC1Gb3JjZSB8IE91dC1OdWxsDQogICAgICAgICAgICB9DQogICAgICAgICAgICANCiAgICAgICAgICAgICMgU2tpcCBpZiBmaWxlIGV4aXN0cyBhbmQgaGFzIGNvbnRlbnQNCiAgICAgICAgICAgIGlmIChUZXN0LVBhdGggJE91dEZpbGUpIHsNCiAgICAgICAgICAgICAgICAkZmlsZUluZm8gPSBHZXQtSXRlbSAkT3V0RmlsZQ0KICAgICAgICAgICAgICAgIGlmICgkZmlsZUluZm8uTGVuZ3RoIC1ndCAwKSB7DQogICAgICAgICAgICAgICAgICAgIHJldHVybiAkdHJ1ZQ0KICAgICAgICAgICAgICAgIH0NCiAgICAgICAgICAgIH0NCiAgICAgICAgICAgIA0KICAgICAgICAgICAgSW52b2tlLVdlYlJlcXVlc3QgLVVyaSAkVXJsIC1PdXRGaWxlICRPdXRGaWxlIC1UaW1lb3V0U2VjIDYwDQogICAgICAgICAgICByZXR1cm4gJHRydWUNCiAgICAgICAgfSBjYXRjaCB7DQogICAgICAgICAgICAkcmV0cnlDb3VudCsrDQogICAgICAgICAgICBpZiAoJHJldHJ5Q291bnQgLWx0ICRNYXhSZXRyaWVzKSB7DQogICAgICAgICAgICAgICAgU3RhcnQtU2xlZXAgLVNlY29uZHMgMg0KICAgICAgICAgICAgfSBlbHNlIHsNCiAgICAgICAgICAgICAgICBXcml0ZS1Ib3N0ICIgICAgRmFpbGVkIHRvIGRvd25sb2FkOiAkVXJsIiAtRm9yZWdyb3VuZENvbG9yIFJlZA0KICAgICAgICAgICAgICAgIHJldHVybiAkZmFsc2UNCiAgICAgICAgICAgIH0NCiAgICAgICAgfQ0KICAgIH0NCiAgICByZXR1cm4gJGZhbHNlDQp9DQoNCnRyeSB7DQogICAgJHZlcnNpb25Kc29uUGF0aCA9IEpvaW4tUGF0aCAkVmVyc2lvbkRpciAiJFZlcnNpb25OYW1lLmpzb24iDQogICAgDQogICAgaWYgKCEoVGVzdC1QYXRoICR2ZXJzaW9uSnNvblBhdGgpKSB7DQogICAgICAgIFdyaXRlLUhvc3QgIiAgRVJST1I6IFZlcnNpb24gbWFuaWZlc3Qgbm90IGZvdW5kISIgLUZvcmVncm91bmRDb2xvciBSZWQNCiAgICAgICAgZXhpdCAxDQogICAgfQ0KICAgIA0KICAgICR2ZXJzaW9uSnNvbiA9IEdldC1Db250ZW50ICR2ZXJzaW9uSnNvblBhdGggLVJhdyB8IENvbnZlcnRGcm9tLUpzb24NCiAgICANCiAgICAjIERvd25sb2FkIGNsaWVudCBKQVINCiAgICBXcml0ZS1Ib3N0ICIgIFsxLzRdIERvd25sb2FkaW5nIGNsaWVudCBKQVIuLi4iDQogICAgJGNsaWVudFVybCA9ICR2ZXJzaW9uSnNvbi5kb3dubG9hZHMuY2xpZW50LnVybA0KICAgICRjbGllbnRQYXRoID0gSm9pbi1QYXRoICRWZXJzaW9uRGlyICIkVmVyc2lvbk5hbWUuamFyIg0KICAgIA0KICAgIGlmIChEb3dubG9hZC1XaXRoUmV0cnkgLVVybCAkY2xpZW50VXJsIC1PdXRGaWxlICRjbGllbnRQYXRoKSB7DQogICAgICAgICRzaXplTUIgPSBbbWF0aF06OlJvdW5kKChHZXQtSXRlbSAkY2xpZW50UGF0aCkuTGVuZ3RoIC8gMU1CLCAyKQ0KICAgICAgICBXcml0ZS1Ib3N0ICIgICAgQ2xpZW50IEpBUjogJHNpemVNQiBNQiIgLUZvcmVncm91bmRDb2xvciBHcmVlbg0KICAgIH0gZWxzZSB7DQogICAgICAgIFdyaXRlLUhvc3QgIiAgICBFUlJPUjogRmFpbGVkIHRvIGRvd25sb2FkIGNsaWVudCBKQVIiIC1Gb3JlZ3JvdW5kQ29sb3IgUmVkDQogICAgICAgIGV4aXQgMQ0KICAgIH0NCiAgICANCiAgICAjIERvd25sb2FkIGxpYnJhcmllcw0KICAgIFdyaXRlLUhvc3QgIiAgWzIvNF0gRG93bmxvYWRpbmcgbGlicmFyaWVzLi4uIg0KICAgICRsaWJDb3VudCA9IDANCiAgICAkbGliVG90YWwgPSAwDQogICAgDQogICAgZm9yZWFjaCAoJGxpYiBpbiAkdmVyc2lvbkpzb24ubGlicmFyaWVzKSB7DQogICAgICAgICRsaWJUb3RhbCsrDQogICAgfQ0KICAgIA0KICAgIGZvcmVhY2ggKCRsaWIgaW4gJHZlcnNpb25Kc29uLmxpYnJhcmllcykgew0KICAgICAgICAjIENoZWNrIHJ1bGVzDQogICAgICAgICRhbGxvd0xpYiA9ICR0cnVlDQogICAgICAgIA0KICAgICAgICBpZiAoJGxpYi5ydWxlcykgew0KICAgICAgICAgICAgJGFsbG93TGliID0gJGZhbHNlDQogICAgICAgICAgICBmb3JlYWNoICgkcnVsZSBpbiAkbGliLnJ1bGVzKSB7DQogICAgICAgICAgICAgICAgaWYgKCRydWxlLmFjdGlvbiAtZXEgImFsbG93Iikgew0KICAgICAgICAgICAgICAgICAgICBpZiAoISRydWxlLm9zIC1vciAkcnVsZS5vcy5uYW1lIC1lcSAid2luZG93cyIpIHsNCiAgICAgICAgICAgICAgICAgICAgICAgICRhbGxvd0xpYiA9ICR0cnVlDQogICAgICAgICAgICAgICAgICAgIH0NCiAgICAgICAgICAgICAgICB9IGVsc2VpZiAoJHJ1bGUuYWN0aW9uIC1lcSAiZGlzYWxsb3ciKSB7DQogICAgICAgICAgICAgICAgICAgIGlmICgkcnVsZS5vcyAtYW5kICRydWxlLm9zLm5hbWUgLWVxICJ3aW5kb3dzIikgew0KICAgICAgICAgICAgICAgICAgICAgICAgJGFsbG93TGliID0gJGZhbHNlDQogICAgICAgICAgICAgICAgICAgIH0NCiAgICAgICAgICAgICAgICB9DQogICAgICAgICAgICB9DQogICAgICAgIH0NCiAgICAgICAgDQogICAgICAgIGlmICghJGFsbG93TGliKSB7IGNvbnRpbnVlIH0NCiAgICAgICAgDQogICAgICAgICMgRG93bmxvYWQgYXJ0aWZhY3QgKG1haW4gbGlicmFyeSkNCiAgICAgICAgaWYgKCRsaWIuZG93bmxvYWRzLmFydGlmYWN0KSB7DQogICAgICAgICAgICAkbGliUGF0aCA9IEpvaW4tUGF0aCAkTGlicmFyaWVzRGlyICRsaWIuZG93bmxvYWRzLmFydGlmYWN0LnBhdGgNCiAgICAgICAgICAgIGlmIChEb3dubG9hZC1XaXRoUmV0cnkgLVVybCAkbGliLmRvd25sb2Fkcy5hcnRpZmFjdC51cmwgLU91dEZpbGUgJGxpYlBhdGgpIHsNCiAgICAgICAgICAgICAgICAkbGliQ291bnQrKw0KICAgICAgICAgICAgfQ0KICAgICAgICB9DQogICAgICAgIA0KICAgICAgICAjIERvd25sb2FkIG5hdGl2ZXMNCiAgICAgICAgaWYgKCRsaWIuZG93bmxvYWRzLmNsYXNzaWZpZXJzKSB7DQogICAgICAgICAgICAkb3NLZXkgPSAibmF0aXZlcy13aW5kb3dzIg0KICAgICAgICAgICAgaWYgKCRsaWIuZG93bmxvYWRzLmNsYXNzaWZpZXJzLiRvc0tleSkgew0KICAgICAgICAgICAgICAgICRuYXRpdmVQYXRoID0gSm9pbi1QYXRoICRMaWJyYXJpZXNEaXIgJGxpYi5kb3dubG9hZHMuY2xhc3NpZmllcnMuJG9zS2V5LnBhdGgNCiAgICAgICAgICAgICAgICBpZiAoRG93bmxvYWQtV2l0aFJldHJ5IC1VcmwgJGxpYi5kb3dubG9hZHMuY2xhc3NpZmllcnMuJG9zS2V5LnVybCAtT3V0RmlsZSAkbmF0aXZlUGF0aCkgew0KICAgICAgICAgICAgICAgICAgICAkbGliQ291bnQrKw0KICAgICAgICAgICAgICAgIH0NCiAgICAgICAgICAgIH0NCiAgICAgICAgfQ0KICAgICAgICANCiAgICAgICAgaWYgKCRsaWJDb3VudCAlIDEwIC1lcSAwKSB7DQogICAgICAgICAgICBXcml0ZS1Ib3N0ICIgICAgUHJvZ3Jlc3M6ICRsaWJDb3VudC8kbGliVG90YWwiIC1Gb3JlZ3JvdW5kQ29sb3IgQ3lhbg0KICAgICAgICB9DQogICAgfQ0KICAgIA0KICAgIFdyaXRlLUhvc3QgIiAgICBMaWJyYXJpZXM6ICRsaWJDb3VudC8kbGliVG90YWwiIC1Gb3JlZ3JvdW5kQ29sb3IgR3JlZW4NCiAgICANCiAgICAjIERvd25sb2FkIGluaGVyaXRlZCB2ZXJzaW9uIGlmIGV4aXN0cw0KICAgIGlmICgkdmVyc2lvbkpzb24uaW5oZXJpdHNGcm9tKSB7DQogICAgICAgICRpbmhlcml0ZWRWZXJzaW9uID0gJHZlcnNpb25Kc29uLmluaGVyaXRzRnJvbQ0KICAgICAgICBXcml0ZS1Ib3N0ICIgIFsyLjUvNF0gRG93bmxvYWRpbmcgaW5oZXJpdGVkIHZlcnNpb246ICRpbmhlcml0ZWRWZXJzaW9uLi4uIg0KICAgICAgICANCiAgICAgICAgJGluaGVyaXRlZERpciA9IEpvaW4tUGF0aCAoU3BsaXQtUGF0aCAkVmVyc2lvbkRpciAtUGFyZW50KSAkaW5oZXJpdGVkVmVyc2lvbg0KICAgICAgICAkaW5oZXJpdGVkSnNvblBhdGggPSBKb2luLVBhdGggJGluaGVyaXRlZERpciAiJGluaGVyaXRlZFZlcnNpb24uanNvbiINCiAgICAgICAgDQogICAgICAgIGlmICghKFRlc3QtUGF0aCAkaW5oZXJpdGVkRGlyKSkgew0KICAgICAgICAgICAgTmV3LUl0ZW0gLUl0ZW1UeXBlIERpcmVjdG9yeSAtUGF0aCAkaW5oZXJpdGVkRGlyIC1Gb3JjZSB8IE91dC1OdWxsDQogICAgICAgIH0NCiAgICAgICAgDQogICAgICAgICMgRmluZCBpbmhlcml0ZWQgdmVyc2lvbiBVUkwgZnJvbSBtYW5pZmVzdA0KICAgICAgICAkbWFuaWZlc3RQYXRoID0gSm9pbi1QYXRoIChTcGxpdC1QYXRoICRWZXJzaW9uRGlyIC1QYXJlbnQgfCBTcGxpdC1QYXRoIC1QYXJlbnQpICJ2ZXJzaW9uX21hbmlmZXN0X3YyLmpzb24iDQogICAgICAgIA0KICAgICAgICBpZiAoVGVzdC1QYXRoICRtYW5pZmVzdFBhdGgpIHsNCiAgICAgICAgICAgICRtYW5pZmVzdCA9IEdldC1Db250ZW50ICRtYW5pZmVzdFBhdGggLVJhdyB8IENvbnZlcnRGcm9tLUpzb24NCiAgICAgICAgICAgICRpbmhlcml0ZWRWZXJzaW9uSW5mbyA9ICRtYW5pZmVzdC52ZXJzaW9ucyB8IFdoZXJlLU9iamVjdCB7ICRfLmlkIC1lcSAkaW5oZXJpdGVkVmVyc2lvbiB9DQogICAgICAgICAgICANCiAgICAgICAgICAgIGlmICgkaW5oZXJpdGVkVmVyc2lvbkluZm8pIHsNCiAgICAgICAgICAgICAgICBEb3dubG9hZC1XaXRoUmV0cnkgLVVybCAkaW5oZXJpdGVkVmVyc2lvbkluZm8udXJsIC1PdXRGaWxlICRpbmhlcml0ZWRKc29uUGF0aCB8IE91dC1OdWxsDQogICAgICAgICAgICAgICAgDQogICAgICAgICAgICAgICAgaWYgKFRlc3QtUGF0aCAkaW5oZXJpdGVkSnNvblBhdGgpIHsNCiAgICAgICAgICAgICAgICAgICAgJGluaGVyaXRlZEpzb24gPSBHZXQtQ29udGVudCAkaW5oZXJpdGVkSnNvblBhdGggLVJhdyB8IENvbnZlcnRGcm9tLUpzb24NCiAgICAgICAgICAgICAgICAgICAgDQogICAgICAgICAgICAgICAgICAgICMgRG93bmxvYWQgaW5oZXJpdGVkIEpBUg0KICAgICAgICAgICAgICAgICAgICBpZiAoJGluaGVyaXRlZEpzb24uZG93bmxvYWRzLmNsaWVudCkgew0KICAgICAgICAgICAgICAgICAgICAgICAgJGluaGVyaXRlZEphclBhdGggPSBKb2luLVBhdGggJGluaGVyaXRlZERpciAiJGluaGVyaXRlZFZlcnNpb24uamFyIg0KICAgICAgICAgICAgICAgICAgICAgICAgRG93bmxvYWQtV2l0aFJldHJ5IC1VcmwgJGluaGVyaXRlZEpzb24uZG93bmxvYWRzLmNsaWVudC51cmwgLU91dEZpbGUgJGluaGVyaXRlZEphclBhdGggfCBPdXQtTnVsbA0KICAgICAgICAgICAgICAgICAgICB9DQogICAgICAgICAgICAgICAgICAgIA0KICAgICAgICAgICAgICAgICAgICAjIERvd25sb2FkIGluaGVyaXRlZCBsaWJyYXJpZXMNCiAgICAgICAgICAgICAgICAgICAgJGluaGVyaXRlZExpYkNvdW50ID0gMA0KICAgICAgICAgICAgICAgICAgICBmb3JlYWNoICgkbGliIGluICRpbmhlcml0ZWRKc29uLmxpYnJhcmllcykgew0KICAgICAgICAgICAgICAgICAgICAgICAgJGFsbG93TGliID0gJHRydWUNCiAg>"%LAUNCHER_DIR%temp_b64.txt"
echo ICAgICAgICAgICAgICAgICAgICAgIA0KICAgICAgICAgICAgICAgICAgICAgICAgaWYgKCRsaWIucnVsZXMpIHsNCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAkYWxsb3dMaWIgPSAkZmFsc2UNCiAgICAgICAgICAgICAgICAgICAgICAgICAgICBmb3JlYWNoICgkcnVsZSBpbiAkbGliLnJ1bGVzKSB7DQogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIGlmICgkcnVsZS5hY3Rpb24gLWVxICJhbGxvdyIpIHsNCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIGlmICghJHJ1bGUub3MgLW9yICRydWxlLm9zLm5hbWUgLWVxICJ3aW5kb3dzIikgew0KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICRhbGxvd0xpYiA9ICR0cnVlDQogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICB9DQogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIH0gZWxzZWlmICgkcnVsZS5hY3Rpb24gLWVxICJkaXNhbGxvdyIpIHsNCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIGlmICgkcnVsZS5vcyAtYW5kICRydWxlLm9zLm5hbWUgLWVxICJ3aW5kb3dzIikgew0KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICRhbGxvd0xpYiA9ICRmYWxzZQ0KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgfQ0KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICB9DQogICAgICAgICAgICAgICAgICAgICAgICAgICAgfQ0KICAgICAgICAgICAgICAgICAgICAgICAgfQ0KICAgICAgICAgICAgICAgICAgICAgICAgDQogICAgICAgICAgICAgICAgICAgICAgICBpZiAoISRhbGxvd0xpYikgeyBjb250aW51ZSB9DQogICAgICAgICAgICAgICAgICAgICAgICANCiAgICAgICAgICAgICAgICAgICAgICAgIGlmICgkbGliLmRvd25sb2Fkcy5hcnRpZmFjdCkgew0KICAgICAgICAgICAgICAgICAgICAgICAgICAgICRsaWJQYXRoID0gSm9pbi1QYXRoICRMaWJyYXJpZXNEaXIgJGxpYi5kb3dubG9hZHMuYXJ0aWZhY3QucGF0aA0KICAgICAgICAgICAgICAgICAgICAgICAgICAgIGlmIChEb3dubG9hZC1XaXRoUmV0cnkgLVVybCAkbGliLmRvd25sb2Fkcy5hcnRpZmFjdC51cmwgLU91dEZpbGUgJGxpYlBhdGgpIHsNCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgJGluaGVyaXRlZExpYkNvdW50KysNCiAgICAgICAgICAgICAgICAgICAgICAgICAgICB9DQogICAgICAgICAgICAgICAgICAgICAgICB9DQogICAgICAgICAgICAgICAgICAgICAgICANCiAgICAgICAgICAgICAgICAgICAgICAgIGlmICgkbGliLmRvd25sb2Fkcy5jbGFzc2lmaWVycykgew0KICAgICAgICAgICAgICAgICAgICAgICAgICAgICRvc0tleSA9ICJuYXRpdmVzLXdpbmRvd3MiDQogICAgICAgICAgICAgICAgICAgICAgICAgICAgaWYgKCRsaWIuZG93bmxvYWRzLmNsYXNzaWZpZXJzLiRvc0tleSkgew0KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAkbmF0aXZlUGF0aCA9IEpvaW4tUGF0aCAkTGlicmFyaWVzRGlyICRsaWIuZG93bmxvYWRzLmNsYXNzaWZpZXJzLiRvc0tleS5wYXRoDQogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIGlmIChEb3dubG9hZC1XaXRoUmV0cnkgLVVybCAkbGliLmRvd25sb2Fkcy5jbGFzc2lmaWVycy4kb3NLZXkudXJsIC1PdXRGaWxlICRuYXRpdmVQYXRoKSB7DQogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAkaW5oZXJpdGVkTGliQ291bnQrKw0KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICB9DQogICAgICAgICAgICAgICAgICAgICAgICAgICAgfQ0KICAgICAgICAgICAgICAgICAgICAgICAgfQ0KICAgICAgICAgICAgICAgICAgICB9DQogICAgICAgICAgICAgICAgICAgIA0KICAgICAgICAgICAgICAgICAgICBXcml0ZS1Ib3N0ICIgICAgSW5oZXJpdGVkIGxpYnJhcmllczogJGluaGVyaXRlZExpYkNvdW50IiAtRm9yZWdyb3VuZENvbG9yIEdyZWVuDQogICAgICAgICAgICAgICAgfQ0KICAgICAgICAgICAgfQ0KICAgICAgICB9DQogICAgfQ0KICAgIA0KICAgICMgRG93bmxvYWQgbG9nZ2luZyBjb25maWd1cmF0aW9uDQogICAgV3JpdGUtSG9zdCAiICBbMy80XSBEb3dubG9hZGluZyBsb2dnaW5nIGNvbmZpZ3VyYXRpb24uLi4iDQogICAgDQogICAgaWYgKCR2ZXJzaW9uSnNvbi5sb2dnaW5nIC1hbmQgJHZlcnNpb25Kc29uLmxvZ2dpbmcuY2xpZW50IC1hbmQgJHZlcnNpb25Kc29uLmxvZ2dpbmcuY2xpZW50LmZpbGUpIHsNCiAgICAgICAgJGxvZ0NvbmZpZ1VybCA9ICR2ZXJzaW9uSnNvbi5sb2dnaW5nLmNsaWVudC5maWxlLnVybA0KICAgICAgICAkbG9nQ29uZmlnSWQgPSAkdmVyc2lvbkpzb24ubG9nZ2luZy5jbGllbnQuZmlsZS5pZA0KICAgICAgICAkbG9nQ29uZmlnRGlyID0gSm9pbi1QYXRoICRBc3NldHNEaXIgImxvZ19jb25maWdzIg0KICAgICAgICANCiAgICAgICAgaWYgKCEoVGVzdC1QYXRoICRsb2dDb25maWdEaXIpKSB7DQogICAgICAgICAgICBOZXctSXRlbSAtSXRlbVR5cGUgRGlyZWN0b3J5IC1QYXRoICRsb2dDb25maWdEaXIgLUZvcmNlIHwgT3V0LU51bGwNCiAgICAgICAgfQ0KICAgICAgICANCiAgICAgICAgJGxvZ0NvbmZpZ1BhdGggPSBKb2luLVBhdGggJGxvZ0NvbmZpZ0RpciAkbG9nQ29uZmlnSWQNCiAgICAgICAgDQogICAgICAgIGlmIChEb3dubG9hZC1XaXRoUmV0cnkgLVVybCAkbG9nQ29uZmlnVXJsIC1PdXRGaWxlICRsb2dDb25maWdQYXRoKSB7DQogICAgICAgICAgICBXcml0ZS1Ib3N0ICIgICAgTG9nZ2luZyBjb25maWc6IE9LIiAtRm9yZWdyb3VuZENvbG9yIEdyZWVuDQogICAgICAgIH0NCiAgICB9IGVsc2Ugew0KICAgICAgICBXcml0ZS1Ib3N0ICIgICAgTG9nZ2luZyBjb25maWc6IE5vdCByZXF1aXJlZCIgLUZvcmVncm91bmRDb2xvciBZZWxsb3cNCiAgICB9DQogICAgDQogICAgIyBEb3dubG9hZCBhc3NldHMNCiAgICBXcml0ZS1Ib3N0ICIgIFs0LzRdIERvd25sb2FkaW5nIGFzc2V0cy4uLiINCiAgICANCiAgICBpZiAoJHZlcnNpb25Kc29uLmFzc2V0SW5kZXgpIHsNCiAgICAgICAgJGFzc2V0SW5kZXhVcmwgPSAkdmVyc2lvbkpzb24uYXNzZXRJbmRleC51cmwNCiAgICAgICAgJGFzc2V0SW5kZXhJZCA9ICR2ZXJzaW9uSnNvbi5hc3NldEluZGV4LmlkDQogICAgICAgICRhc3NldEluZGV4RGlyID0gSm9pbi1QYXRoICRBc3NldHNEaXIgImluZGV4ZXMiDQogICAgICAgIA0KICAgICAgICBpZiAoIShUZXN0LVBhdGggJGFzc2V0SW5kZXhEaXIpKSB7DQogICAgICAgICAgICBOZXctSXRlbSAtSXRlbVR5cGUgRGlyZWN0b3J5IC1QYXRoICRhc3NldEluZGV4RGlyIC1Gb3JjZSB8IE91dC1OdWxsDQogICAgICAgIH0NCiAgICAgICAgDQogICAgICAgICRhc3NldEluZGV4UGF0aCA9IEpvaW4tUGF0aCAkYXNzZXRJbmRleERpciAiJGFzc2V0SW5kZXhJZC5qc29uIg0KICAgICAgICANCiAgICAgICAgaWYgKCEoRG93bmxvYWQtV2l0aFJldHJ5IC1VcmwgJGFzc2V0SW5kZXhVcmwgLU91dEZpbGUgJGFzc2V0SW5kZXhQYXRoKSkgew0KICAgICAgICAgICAgV3JpdGUtSG9zdCAiICAgIEVSUk9SOiBGYWlsZWQgdG8gZG93bmxvYWQgYXNzZXQgaW5kZXgiIC1Gb3JlZ3JvdW5kQ29sb3IgUmVkDQogICAgICAgICAgICBleGl0IDENCiAgICAgICAgfQ0KICAgICAgICANCiAgICAgICAgJGFzc2V0SW5kZXggPSBHZXQtQ29udGVudCAkYXNzZXRJbmRleFBhdGggLVJhdyB8IENvbnZlcnRGcm9tLUpzb24NCiAgICAgICAgJGFzc2V0Q291bnQgPSAwDQogICAgICAgICR0b3RhbEFzc2V0cyA9ICgkYXNzZXRJbmRleC5vYmplY3RzIHwgR2V0LU1lbWJlciAtTWVtYmVyVHlwZSBOb3RlUHJvcGVydHkpLkNvdW50DQogICAgICAgIA0KICAgICAgICBXcml0ZS1Ib3N0ICIgICAgVG90YWwgYXNzZXRzOiAkdG90YWxBc3NldHMiIC1Gb3JlZ3JvdW5kQ29sb3IgQ3lhbg0KICAgICAgICANCiAgICAgICAgZm9yZWFjaCAoJGFzc2V0IGluICRhc3NldEluZGV4Lm9iamVjdHMuUFNPYmplY3QuUHJvcGVydGllcykgew0KICAgICAgICAgICAgJGhhc2ggPSAkYXNzZXQuVmFsdWUuaGFzaA0KICAgICAgICAgICAgJGhhc2hQcmVmaXggPSAkaGFzaC5TdWJzdHJpbmcoMCwgMikNCiAgICAgICAgICAgICRhc3NldFVybCA9ICJodHRwczovL3Jlc291cmNlcy5kb3dubG9hZC5taW5lY3JhZnQubmV0LyRoYXNoUHJlZml4LyRoYXNoIg0KICAgICAgICAgICAgJGFzc2V0UGF0aCA9IEpvaW4tUGF0aCAoSm9pbi1QYXRoICRBc3NldHNEaXIgIm9iamVjdHMiKSAoSm9pbi1QYXRoICRoYXNoUHJlZml4ICRoYXNoKQ0KICAgICAgICAgICAgDQogICAgICAgICAgICBpZiAoRG93bmxvYWQtV2l0aFJldHJ5IC1VcmwgJGFzc2V0VXJsIC1PdXRGaWxlICRhc3NldFBhdGgpIHsNCiAgICAgICAgICAgICAgICAkYXNzZXRDb3VudCsrDQogICAgICAgICAgICAgICAgDQogICAgICAgICAgICAgICAgaWYgKCRhc3NldENvdW50ICUgMTAwIC1lcSAwKSB7DQogICAgICAgICAgICAgICAgICAgICRwZXJjZW50ID0gW21hdGhdOjpSb3VuZCgoJGFzc2V0Q291bnQgLyAkdG90YWxBc3NldHMpICogMTAwLCAxKQ0KICAgICAgICAgICAgICAgICAgICBXcml0ZS1Ib3N0ICIgICAgUHJvZ3Jlc3M6ICRhc3NldENvdW50LyR0b3RhbEFzc2V0cyAoJHBlcmNlbnQlKSIgLUZvcmVncm91bmRDb2xvciBDeWFuDQogICAgICAgICAgICAgICAgfQ0KICAgICAgICAgICAgfQ0KICAgICAgICB9DQogICAgICAgIA0KICAgICAgICBXcml0ZS1Ib3N0ICIgICAgQXNzZXRzOiAkYXNzZXRDb3VudC8kdG90YWxBc3NldHMiIC1Gb3JlZ3JvdW5kQ29sb3IgR3JlZW4NCiAgICB9IGVsc2Ugew0KICAgICAgICBXcml0ZS1Ib3N0ICIgICAgTm8gYXNzZXQgaW5kZXggZm91bmQiIC1Gb3JlZ3JvdW5kQ29sb3IgWWVsbG93DQogICAgfQ0KICAgIA0KICAgIFdyaXRlLUhvc3QgIiINCiAgICBXcml0ZS1Ib3N0ICIgIERvd25sb2FkIENvbXBsZXRlISIgLUZvcmVncm91bmRDb2xvciBHcmVlbg0KICAgIGV4aXQgMA0KICAgIA0KfSBjYXRjaCB7DQogICAgV3JpdGUtSG9zdCAiIg0KICAgIFdyaXRlLUhvc3QgIiAgRVJST1I6ICQoJF8uRXhjZXB0aW9uLk1lc3NhZ2UpIiAtRm9yZWdyb3VuZENvbG9yIFJlZA0KICAgIGV4aXQgMQ0KfQ==>>"%LAUNCHER_DIR%temp_b64.txt"
) >nul 2>&1
powershell -NoProfile -ExecutionPolicy Bypass -Command "$b64 = Get-Content '%LAUNCHER_DIR%temp_b64.txt' -Raw; $bytes = [Convert]::FromBase64String($b64); [IO.File]::WriteAllBytes('%PS1_FILE%', $bytes)" >nul 2>&1
del "%LAUNCHER_DIR%temp_b64.txt" 2>nul
endlocal
exit /b 0


:CREATE_LAUNCH_SCRIPT
setlocal
set "PS1_FILE=%LAUNCHER_DIR%temp_launch_minecraft.ps1"
(
echo cGFyYW0oDQogICAgW3N0cmluZ10kTGF1bmNoZXJEaXIsDQogICAgW3N0cmluZ10kR2FtZVZlcnNpb24sDQogICAgW3N0cmluZ10kUGxheWVyTmFtZSwNCiAgICBbc3RyaW5nXSRNaW5SYW0sDQogICAgW3N0cmluZ10kTWF4UmFtLA0KICAgIFtzdHJpbmddJEphdmFFeGVjLA0KICAgIFtzdHJpbmddJEV4dHJhSnZtQXJncyA9ICIiDQopDQoNCiRFcnJvckFjdGlvblByZWZlcmVuY2UgPSAnU3RvcCcNCg0KIyBWYWxpZGF0ZSBwYXJhbWV0ZXJzDQppZiAoW3N0cmluZ106OklzTnVsbE9yV2hpdGVTcGFjZSgkTGF1bmNoZXJEaXIpKSB7DQogICAgV3JpdGUtSG9zdCAiICBFUlJPUjogTGF1bmNoZXJEaXIgcGFyYW1ldGVyIGlzIG1pc3NpbmchIiAtRm9yZWdyb3VuZENvbG9yIFJlZA0KICAgIGV4aXQgMQ0KfQ0KDQppZiAoW3N0cmluZ106OklzTnVsbE9yV2hpdGVTcGFjZSgkR2FtZVZlcnNpb24pKSB7DQogICAgV3JpdGUtSG9zdCAiICBFUlJPUjogR2FtZVZlcnNpb24gcGFyYW1ldGVyIGlzIG1pc3NpbmchIiAtRm9yZWdyb3VuZENvbG9yIFJlZA0KICAgIGV4aXQgMQ0KfQ0KDQppZiAoW3N0cmluZ106OklzTnVsbE9yV2hpdGVTcGFjZSgkUGxheWVyTmFtZSkpIHsNCiAgICBXcml0ZS1Ib3N0ICIgIEVSUk9SOiBQbGF5ZXJOYW1lIHBhcmFtZXRlciBpcyBtaXNzaW5nISIgLUZvcmVncm91bmRDb2xvciBSZWQNCiAgICBleGl0IDENCn0NCg0KIyBQYXRocw0KJHZlcnNpb25EaXIgPSBKb2luLVBhdGggJExhdW5jaGVyRGlyICJ2ZXJzaW9uc1wkR2FtZVZlcnNpb24iDQokbGlicmFyaWVzRGlyID0gSm9pbi1QYXRoICRMYXVuY2hlckRpciAibGlicmFyaWVzIg0KJGFzc2V0c0RpciA9IEpvaW4tUGF0aCAkTGF1bmNoZXJEaXIgImFzc2V0cyINCiRuYXRpdmVzRGlyID0gSm9pbi1QYXRoICR2ZXJzaW9uRGlyICJuYXRpdmVzIg0KJHZlcnNpb25Kc29uID0gSm9pbi1QYXRoICR2ZXJzaW9uRGlyICIkR2FtZVZlcnNpb24uanNvbiINCg0KV3JpdGUtSG9zdCAiICBMb2FkaW5nIHZlcnNpb24gbWFuaWZlc3QuLi4iDQoNCmlmICgtbm90IChUZXN0LVBhdGggJHZlcnNpb25Kc29uKSkgew0KICAgIFdyaXRlLUhvc3QgIiAgRVJST1I6IFZlcnNpb24gbWFuaWZlc3Qgbm90IGZvdW5kOiAkdmVyc2lvbkpzb24iIC1Gb3JlZ3JvdW5kQ29sb3IgUmVkDQogICAgZXhpdCAxDQp9DQoNCiRqc29uID0gR2V0LUNvbnRlbnQgJHZlcnNpb25Kc29uIC1SYXcgfCBDb252ZXJ0RnJvbS1Kc29uDQoNCiMgR2VuZXJhdGUgVVVJRCBmb3Igb2ZmbGluZSBwbGF5ZXINCmZ1bmN0aW9uIEdldC1PZmZsaW5lVVVJRCB7DQogICAgcGFyYW0oW3N0cmluZ10kUGxheWVyTmFtZSkNCiAgICANCiAgICAkbWQ1ID0gW1N5c3RlbS5TZWN1cml0eS5DcnlwdG9ncmFwaHkuTUQ1XTo6Q3JlYXRlKCkNCiAgICAkYnl0ZXMgPSBbU3lzdGVtLlRleHQuRW5jb2RpbmddOjpVVEY4LkdldEJ5dGVzKCJPZmZsaW5lUGxheWVyOiRQbGF5ZXJOYW1lIikNCiAgICAkaGFzaCA9ICRtZDUuQ29tcHV0ZUhhc2goJGJ5dGVzKQ0KICAgIA0KICAgICMgQ29udmVydCB0byBoZXggc3RyaW5nDQogICAgJGhleCA9IFtTeXN0ZW0uQml0Q29udmVydGVyXTo6VG9TdHJpbmcoJGhhc2gpLlJlcGxhY2UoIi0iLCAiIikuVG9Mb3dlcigpDQogICAgDQogICAgIyBGb3JtYXQgYXMgVVVJRCAodmVyc2lvbiAzLCB2YXJpYW50IDgpDQogICAgJHV1aWQgPSAkaGV4LlN1YnN0cmluZygwLCAxMikNCiAgICAkdXVpZCArPSBbQ29udmVydF06OlRvU3RyaW5nKChbQ29udmVydF06OlRvSW50MzIoJGhleC5TdWJzdHJpbmcoMTIsIDIpLCAxNikgLWJhbmQgMHgwZikgLWJvciAweDMwLCAxNikuUGFkTGVmdCgyLCAnMCcpDQogICAgJHV1aWQgKz0gJGhleC5TdWJzdHJpbmcoMTQsIDIpDQogICAgJHV1aWQgKz0gW0NvbnZlcnRdOjpUb1N0cmluZygoW0NvbnZlcnRdOjpUb0ludDMyKCRoZXguU3Vic3RyaW5nKDE2LCAyKSwgMTYpIC1iYW5kIDB4M2YpIC1ib3IgMHg4MCwgMTYpLlBhZExlZnQoMiwgJzAnKQ0KICAgICR1dWlkICs9ICRoZXguU3Vic3RyaW5nKDE4LCAxNCkNCiAgICANCiAgICByZXR1cm4gJHV1aWQNCn0NCg0KJHV1aWQgPSBHZXQtT2ZmbGluZVVVSUQgLVBsYXllck5hbWUgJFBsYXllck5hbWUNCg0KIyBHZXQgYXNzZXRzIGluZGV4DQokYXNzZXRzSW5kZXggPSBpZiAoJGpzb24uYXNzZXRJbmRleCkgeyAkanNvbi5hc3NldEluZGV4LmlkIH0gZWxzZWlmICgkanNvbi5hc3NldHMpIHsgJGpzb24uYXNzZXRzIH0gZWxzZSB7ICJsZWdhY3kiIH0NCg0KIyBHZXQgbWFpbiBjbGFzcw0KJG1haW5DbGFzcyA9ICRqc29uLm1haW5DbGFzcw0KDQojIENoZWNrIGZvciBpbmhlcml0ZWQgdmVyc2lvbg0KJGluaGVyaXRzRnJvbSA9ICRudWxsDQppZiAoJGpzb24uaW5oZXJpdHNGcm9tKSB7DQogICAgJGluaGVyaXRzRnJvbSA9ICRqc29uLmluaGVyaXRzRnJvbQ0KICAgICRpbmhlcml0ZWRKc29uUGF0aCA9IEpvaW4tUGF0aCAkTGF1bmNoZXJEaXIgInZlcnNpb25zXCRpbmhlcml0c0Zyb21cJGluaGVyaXRzRnJvbS5qc29uIg0KICAgIA0KICAgIGlmIChUZXN0LVBhdGggJGluaGVyaXRlZEpzb25QYXRoKSB7DQogICAgICAgIFdyaXRlLUhvc3QgIiAgTG9hZGluZyBpbmhlcml0ZWQgdmVyc2lvbjogJGluaGVyaXRzRnJvbSINCiAgICAgICAgJGluaGVyaXRlZEpzb24gPSBHZXQtQ29udGVudCAkaW5oZXJpdGVkSnNvblBhdGggLVJhdyB8IENvbnZlcnRGcm9tLUpzb24NCiAgICAgICAgDQogICAgICAgICMgVXNlIGluaGVyaXRlZCBqYXIgaWYgY3VycmVudCB2ZXJzaW9uIGRvZXNuJ3QgaGF2ZSBvbmUNCiAgICAgICAgJGN1cnJlbnRKYXIgPSBKb2luLVBhdGggJHZlcnNpb25EaXIgIiRHYW1lVmVyc2lvbi5qYXIiDQogICAgICAgICRpbmhlcml0ZWRKYXIgPSBKb2luLVBhdGggJExhdW5jaGVyRGlyICJ2ZXJzaW9uc1wkaW5oZXJpdHNGcm9tXCRpbmhlcml0c0Zyb20uamFyIg0KICAgICAgICANCiAgICAgICAgaWYgKC1ub3QgKFRlc3QtUGF0aCAkY3VycmVudEphcikgLWFuZCAoVGVzdC1QYXRoICRpbmhlcml0ZWRKYXIpKSB7DQogICAgICAgICAgICBDb3B5LUl0ZW0gJGluaGVyaXRlZEphciAkY3VycmVudEphciAtRm9yY2UNCiAgICAgICAgICAgIFdyaXRlLUhvc3QgIiAgQ29waWVkIGluaGVyaXRlZCBKQVIiDQogICAgICAgIH0NCiAgICAgICAgDQogICAgICAgICMgVXNlIGluaGVyaXRlZCBhc3NldHMgaWYgbm90IHNwZWNpZmllZA0KICAgICAgICBpZiAoLW5vdCAkanNvbi5hc3NldEluZGV4IC1hbmQgJGluaGVyaXRlZEpzb24uYXNzZXRJbmRleCkgew0KICAgICAgICAgICAgJGFzc2V0c0luZGV4ID0gJGluaGVyaXRlZEpzb24uYXNzZXRJbmRleC5pZA0KICAgICAgICB9IGVsc2VpZiAoLW5vdCAkanNvbi5hc3NldEluZGV4IC1hbmQgJGluaGVyaXRlZEpzb24uYXNzZXRzKSB7DQogICAgICAgICAgICAkYXNzZXRzSW5kZXggPSAkaW5oZXJpdGVkSnNvbi5hc3NldHMNCiAgICAgICAgfQ0KICAgIH0NCn0NCg0KV3JpdGUtSG9zdCAiICBBc3NldHMgaW5kZXg6ICRhc3NldHNJbmRleCINCg0KIyBFeHRyYWN0IG5hdGl2ZXMNCldyaXRlLUhvc3QgIiAgRXh0cmFjdGluZyBuYXRpdmVzLi4uIg0KDQppZiAoVGVzdC1QYXRoICRuYXRpdmVzRGlyKSB7DQogICAgUmVtb3ZlLUl0ZW0gJG5hdGl2ZXNEaXIgLVJlY3Vyc2UgLUZvcmNlIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlDQp9DQpOZXctSXRlbSAtSXRlbVR5cGUgRGlyZWN0b3J5IC1QYXRoICRuYXRpdmVzRGlyIC1Gb3JjZSB8IE91dC1OdWxsDQoNCkFkZC1UeXBlIC1Bc3NlbWJseU5hbWUgU3lzdGVtLklPLkNvbXByZXNzaW9uLkZpbGVTeXN0ZW0NCg0KJG5hdGl2ZXNFeHRyYWN0ZWQgPSAwDQoNCmZvcmVhY2ggKCRsaWIgaW4gJGpzb24ubGlicmFyaWVzKSB7DQogICAgIyBDaGVjayBydWxlcyB0byBzZWUgaWYgbGlicmFyeSBzaG91bGQgYmUgbG9hZGVkDQogICAgJGFsbG93TGliID0gJHRydWUNCiAgICANCiAgICBpZiAoJGxpYi5ydWxlcykgew0KICAgICAgICAkYWxsb3dMaWIgPSAkZmFsc2UNCiAgICAgICAgZm9yZWFjaCAoJHJ1bGUgaW4gJGxpYi5ydWxlcykgew0KICAgICAgICAgICAgaWYgKCRydWxlLmFjdGlvbiAtZXEgImFsbG93Iikgew0KICAgICAgICAgICAgICAgIGlmICgtbm90ICRydWxlLm9zIC1vciAkcnVsZS5vcy5uYW1lIC1lcSAid2luZG93cyIpIHsNCiAgICAgICAgICAgICAgICAgICAgJGFsbG93TGliID0gJHRydWUNCiAgICAgICAgICAgICAgICB9DQogICAgICAgICAgICB9IGVsc2VpZiAoJHJ1bGUuYWN0aW9uIC1lcSAiZGlzYWxsb3ciKSB7DQogICAgICAgICAgICAgICAgaWYgKCRydWxlLm9zIC1hbmQgJHJ1bGUub3MubmFtZSAtZXEgIndpbmRvd3MiKSB7DQogICAgICAgICAgICAgICAgICAgICRhbGxvd0xpYiA9ICRmYWxzZQ0KICAgICAgICAgICAgICAgIH0NCiAgICAgICAgICAgIH0NCiAgICAgICAgfQ0KICAgIH0NCiAgICANCiAgICBpZiAoLW5vdCAkYWxsb3dMaWIpIHsgY29udGludWUgfQ0KICAgIA0KICAgICMgQ2hlY2sgZm9yIG5hdGl2ZXMNCiAgICBpZiAoJGxpYi5uYXRpdmVzIC1hbmQgJGxpYi5uYXRpdmVzLndpbmRvd3MpIHsNCiAgICAgICAgJG5hdGl2ZUtleSA9ICRsaWIubmF0aXZlcy53aW5kb3dzDQogICAgICAgIA0KICAgICAgICBpZiAoJGxpYi5kb3dubG9hZHMuY2xhc3NpZmllcnMuJG5hdGl2ZUtleSkgew0KICAgICAgICAgICAgJG5hdGl2ZVBhdGggPSBKb2luLVBhdGggJGxpYnJhcmllc0RpciAkbGliLmRvd25sb2Fkcy5jbGFzc2lmaWVycy4kbmF0aXZlS2V5LnBhdGgNCiAgICAgICAgICAgIA0KICAgICAgICAgICAgaWYgKFRlc3QtUGF0aCAkbmF0aXZlUGF0aCkgew0KICAgICAgICAgICAgICAgIHRyeSB7DQogICAgICAgICAgICAgICAgICAgICMgRXh0cmFjdCBuYXRpdmUgbGlicmFyeQ0KICAgICAgICAgICAgICAgICAgICAkemlwID0gW1N5c3RlbS5JTy5Db21wcmVzc2lvbi5aaXBGaWxlXTo6T3BlblJlYWQoJG5hdGl2ZVBhdGgpDQogICAgICAgICAgICAgICAgICAgIA0KICAgICAgICAgICAgICAgICAgICBmb3JlYWNoICgkZW50cnkgaW4gJHppcC5FbnRyaWVzKSB7DQogICAgICAgICAgICAgICAgICAgICAgICAjIFNraXAgTUVUQS1JTkYgYW5kIG5vbi1kbGwgZmlsZXMNCiAgICAgICAgICAgICAgICAgICAgICAgIGlmICgkZW50cnkuRnVsbE5hbWUgLWxpa2UgIk1FVEEtSU5GLyoiIC1vciAkZW50cnkuRnVsbE5hbWUgLWxpa2UgIiouZ2l0IiAtb3IgJGVudHJ5LkZ1bGxOYW1lIC1saWtlICIqLnNoYTEiKSB7DQogICAgICAgICAgICAgICAgICAgICAgICAgICAgY29udGludWUNCiAgICAgICAgICAgICAgICAgICAgICAgIH0NCiAgICAgICAgICAgICAgICAgICAgICAgIA0KICAgICAgICAgICAgICAgICAgICAgICAgIyBFeHRyYWN0IGZpbGUNCiAgICAgICAgICAgICAgICAgICAgICAgICRkZXN0UGF0aCA9IEpvaW4tUGF0aCAkbmF0aXZlc0RpciAkZW50cnkuTmFtZQ0KICAgICAgICAgICAgICAgICAgICAgICAgDQogICAgICAgICAgICAgICAgICAgICAgICBpZiAoJGVudHJ5Lk5hbWUpIHsNCiAgICAgICAgICAgICAgICAgICAgICAgICAgICBbU3lzdGVtLklPLkNvbXByZXNzaW9uLlppcEZpbGVFeHRlbnNpb25zXTo6RXh0cmFjdFRvRmlsZSgkZW50cnksICRkZXN0UGF0aCwgJHRydWUpDQogICAgICAgICAgICAgICAgICAgICAgICAgICAgJG5hdGl2ZXNFeHRyYWN0ZWQrKw0KICAgICAgICAgICAgICAgICAgICAgICAgfQ0KICAgICAgICAgICAgICAgICAgICB9DQogICAgICAgICAgICAgICAgICAgIA0KICAgICAgICAgICAgICAgICAgICAkemlwLkRpc3Bvc2UoKQ0KICAgICAgICAgICAgICAgIH0gY2F0Y2ggew0KICAgICAgICAgICAgICAgICAgICBXcml0ZS1Ib3N0ICIgICAgV2FybmluZzogRmFpbGVkIHRvIGV4dHJhY3QgJG5hdGl2ZVBhdGgiIC1Gb3JlZ3JvdW5kQ29sb3IgWWVsbG93DQogICAgICAgICAgICAgICAgfQ0KICAgICAgICAgICAgfQ0KICAgICAgICB9DQogICAgfQ0KfQ0KDQojIElmIGluaGVyaXRlZCB2ZXJzaW9uLCBhbHNvIGV4dHJhY3QgaXRzIG5h>"%LAUNCHER_DIR%temp_b64.txt"
echo dGl2ZXMNCmlmICgkaW5oZXJpdHNGcm9tIC1hbmQgKFRlc3QtUGF0aCAkaW5oZXJpdGVkSnNvblBhdGgpKSB7DQogICAgJGluaGVyaXRlZE5hdGl2ZXNEaXIgPSBKb2luLVBhdGggJExhdW5jaGVyRGlyICJ2ZXJzaW9uc1wkaW5oZXJpdHNGcm9tXG5hdGl2ZXMiDQogICAgDQogICAgZm9yZWFjaCAoJGxpYiBpbiAkaW5oZXJpdGVkSnNvbi5saWJyYXJpZXMpIHsNCiAgICAgICAgJGFsbG93TGliID0gJHRydWUNCiAgICAgICAgDQogICAgICAgIGlmICgkbGliLnJ1bGVzKSB7DQogICAgICAgICAgICAkYWxsb3dMaWIgPSAkZmFsc2UNCiAgICAgICAgICAgIGZvcmVhY2ggKCRydWxlIGluICRsaWIucnVsZXMpIHsNCiAgICAgICAgICAgICAgICBpZiAoJHJ1bGUuYWN0aW9uIC1lcSAiYWxsb3ciKSB7DQogICAgICAgICAgICAgICAgICAgIGlmICgtbm90ICRydWxlLm9zIC1vciAkcnVsZS5vcy5uYW1lIC1lcSAid2luZG93cyIpIHsNCiAgICAgICAgICAgICAgICAgICAgICAgICRhbGxvd0xpYiA9ICR0cnVlDQogICAgICAgICAgICAgICAgICAgIH0NCiAgICAgICAgICAgICAgICB9IGVsc2VpZiAoJHJ1bGUuYWN0aW9uIC1lcSAiZGlzYWxsb3ciKSB7DQogICAgICAgICAgICAgICAgICAgIGlmICgkcnVsZS5vcyAtYW5kICRydWxlLm9zLm5hbWUgLWVxICJ3aW5kb3dzIikgew0KICAgICAgICAgICAgICAgICAgICAgICAgJGFsbG93TGliID0gJGZhbHNlDQogICAgICAgICAgICAgICAgICAgIH0NCiAgICAgICAgICAgICAgICB9DQogICAgICAgICAgICB9DQogICAgICAgIH0NCiAgICAgICAgDQogICAgICAgIGlmICgtbm90ICRhbGxvd0xpYikgeyBjb250aW51ZSB9DQogICAgICAgIA0KICAgICAgICBpZiAoJGxpYi5uYXRpdmVzIC1hbmQgJGxpYi5uYXRpdmVzLndpbmRvd3MpIHsNCiAgICAgICAgICAgICRuYXRpdmVLZXkgPSAkbGliLm5hdGl2ZXMud2luZG93cw0KICAgICAgICAgICAgDQogICAgICAgICAgICBpZiAoJGxpYi5kb3dubG9hZHMuY2xhc3NpZmllcnMuJG5hdGl2ZUtleSkgew0KICAgICAgICAgICAgICAgICRuYXRpdmVQYXRoID0gSm9pbi1QYXRoICRsaWJyYXJpZXNEaXIgJGxpYi5kb3dubG9hZHMuY2xhc3NpZmllcnMuJG5hdGl2ZUtleS5wYXRoDQogICAgICAgICAgICAgICAgDQogICAgICAgICAgICAgICAgaWYgKFRlc3QtUGF0aCAkbmF0aXZlUGF0aCkgew0KICAgICAgICAgICAgICAgICAgICB0cnkgew0KICAgICAgICAgICAgICAgICAgICAgICAgJHppcCA9IFtTeXN0ZW0uSU8uQ29tcHJlc3Npb24uWmlwRmlsZV06Ok9wZW5SZWFkKCRuYXRpdmVQYXRoKQ0KICAgICAgICAgICAgICAgICAgICAgICAgDQogICAgICAgICAgICAgICAgICAgICAgICBmb3JlYWNoICgkZW50cnkgaW4gJHppcC5FbnRyaWVzKSB7DQogICAgICAgICAgICAgICAgICAgICAgICAgICAgaWYgKCRlbnRyeS5GdWxsTmFtZSAtbGlrZSAiTUVUQS1JTkYvKiIgLW9yICRlbnRyeS5GdWxsTmFtZSAtbGlrZSAiKi5naXQiIC1vciAkZW50cnkuRnVsbE5hbWUgLWxpa2UgIiouc2hhMSIpIHsNCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgY29udGludWUNCiAgICAgICAgICAgICAgICAgICAgICAgICAgICB9DQogICAgICAgICAgICAgICAgICAgICAgICAgICAgDQogICAgICAgICAgICAgICAgICAgICAgICAgICAgJGRlc3RQYXRoID0gSm9pbi1QYXRoICRuYXRpdmVzRGlyICRlbnRyeS5OYW1lDQogICAgICAgICAgICAgICAgICAgICAgICAgICAgDQogICAgICAgICAgICAgICAgICAgICAgICAgICAgaWYgKCRlbnRyeS5OYW1lIC1hbmQgLW5vdCAoVGVzdC1QYXRoICRkZXN0UGF0aCkpIHsNCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgW1N5c3RlbS5JTy5Db21wcmVzc2lvbi5aaXBGaWxlRXh0ZW5zaW9uc106OkV4dHJhY3RUb0ZpbGUoJGVudHJ5LCAkZGVzdFBhdGgsICR0cnVlKQ0KICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAkbmF0aXZlc0V4dHJhY3RlZCsrDQogICAgICAgICAgICAgICAgICAgICAgICAgICAgfQ0KICAgICAgICAgICAgICAgICAgICAgICAgfQ0KICAgICAgICAgICAgICAgICAgICAgICAgDQogICAgICAgICAgICAgICAgICAgICAgICAkemlwLkRpc3Bvc2UoKQ0KICAgICAgICAgICAgICAgICAgICB9IGNhdGNoIHsNCiAgICAgICAgICAgICAgICAgICAgICAgIFdyaXRlLUhvc3QgIiAgICBXYXJuaW5nOiBGYWlsZWQgdG8gZXh0cmFjdCAkbmF0aXZlUGF0aCIgLUZvcmVncm91bmRDb2xvciBZZWxsb3cNCiAgICAgICAgICAgICAgICAgICAgfQ0KICAgICAgICAgICAgICAgIH0NCiAgICAgICAgICAgIH0NCiAgICAgICAgfQ0KICAgIH0NCn0NCg0KV3JpdGUtSG9zdCAiICBFeHRyYWN0ZWQgJG5hdGl2ZXNFeHRyYWN0ZWQgbmF0aXZlIGZpbGVzIg0KDQojIEJ1aWxkIGNsYXNzcGF0aA0KV3JpdGUtSG9zdCAiICBCdWlsZGluZyBjbGFzc3BhdGguLi4iDQoNCiRjbGFzc3BhdGggPSBAKCkNCg0KZm9yZWFjaCAoJGxpYiBpbiAkanNvbi5saWJyYXJpZXMpIHsNCiAgICAkYWxsb3dMaWIgPSAkdHJ1ZQ0KICAgIA0KICAgIGlmICgkbGliLnJ1bGVzKSB7DQogICAgICAgICRhbGxvd0xpYiA9ICRmYWxzZQ0KICAgICAgICBmb3JlYWNoICgkcnVsZSBpbiAkbGliLnJ1bGVzKSB7DQogICAgICAgICAgICBpZiAoJHJ1bGUuYWN0aW9uIC1lcSAiYWxsb3ciKSB7DQogICAgICAgICAgICAgICAgaWYgKC1ub3QgJHJ1bGUub3MgLW9yICRydWxlLm9zLm5hbWUgLWVxICJ3aW5kb3dzIikgew0KICAgICAgICAgICAgICAgICAgICAkYWxsb3dMaWIgPSAkdHJ1ZQ0KICAgICAgICAgICAgICAgIH0NCiAgICAgICAgICAgIH0gZWxzZWlmICgkcnVsZS5hY3Rpb24gLWVxICJkaXNhbGxvdyIpIHsNCiAgICAgICAgICAgICAgICBpZiAoJHJ1bGUub3MgLWFuZCAkcnVsZS5vcy5uYW1lIC1lcSAid2luZG93cyIpIHsNCiAgICAgICAgICAgICAgICAgICAgJGFsbG93TGliID0gJGZhbHNlDQogICAgICAgICAgICAgICAgfQ0KICAgICAgICAgICAgfQ0KICAgICAgICB9DQogICAgfQ0KICAgIA0KICAgIGlmICgtbm90ICRhbGxvd0xpYikgeyBjb250aW51ZSB9DQogICAgDQogICAgIyBTa2lwIG5hdGl2ZXMgaW4gY2xhc3NwYXRoDQogICAgaWYgKCRsaWIubmF0aXZlcykgeyBjb250aW51ZSB9DQogICAgDQogICAgaWYgKCRsaWIuZG93bmxvYWRzLmFydGlmYWN0KSB7DQogICAgICAgICRsaWJQYXRoID0gSm9pbi1QYXRoICRsaWJyYXJpZXNEaXIgJGxpYi5kb3dubG9hZHMuYXJ0aWZhY3QucGF0aA0KICAgICAgICBpZiAoVGVzdC1QYXRoICRsaWJQYXRoKSB7DQogICAgICAgICAgICAkY2xhc3NwYXRoICs9ICRsaWJQYXRoDQogICAgICAgIH0NCiAgICB9DQp9DQoNCiMgQWRkIGluaGVyaXRlZCBsaWJyYXJpZXMNCmlmICgkaW5oZXJpdHNGcm9tIC1hbmQgKFRlc3QtUGF0aCAkaW5oZXJpdGVkSnNvblBhdGgpKSB7DQogICAgZm9yZWFjaCAoJGxpYiBpbiAkaW5oZXJpdGVkSnNvbi5saWJyYXJpZXMpIHsNCiAgICAgICAgJGFsbG93TGliID0gJHRydWUNCiAgICAgICAgDQogICAgICAgIGlmICgkbGliLnJ1bGVzKSB7DQogICAgICAgICAgICAkYWxsb3dMaWIgPSAkZmFsc2UNCiAgICAgICAgICAgIGZvcmVhY2ggKCRydWxlIGluICRsaWIucnVsZXMpIHsNCiAgICAgICAgICAgICAgICBpZiAoJHJ1bGUuYWN0aW9uIC1lcSAiYWxsb3ciKSB7DQogICAgICAgICAgICAgICAgICAgIGlmICgtbm90ICRydWxlLm9zIC1vciAkcnVsZS5vcy5uYW1lIC1lcSAid2luZG93cyIpIHsNCiAgICAgICAgICAgICAgICAgICAgICAgICRhbGxvd0xpYiA9ICR0cnVlDQogICAgICAgICAgICAgICAgICAgIH0NCiAgICAgICAgICAgICAgICB9IGVsc2VpZiAoJHJ1bGUuYWN0aW9uIC1lcSAiZGlzYWxsb3ciKSB7DQogICAgICAgICAgICAgICAgICAgIGlmICgkcnVsZS5vcyAtYW5kICRydWxlLm9zLm5hbWUgLWVxICJ3aW5kb3dzIikgew0KICAgICAgICAgICAgICAgICAgICAgICAgJGFsbG93TGliID0gJGZhbHNlDQogICAgICAgICAgICAgICAgICAgIH0NCiAgICAgICAgICAgICAgICB9DQogICAgICAgICAgICB9DQogICAgICAgIH0NCiAgICAgICAgDQogICAgICAgIGlmICgtbm90ICRhbGxvd0xpYikgeyBjb250aW51ZSB9DQogICAgICAgIGlmICgkbGliLm5hdGl2ZXMpIHsgY29udGludWUgfQ0KICAgICAgICANCiAgICAgICAgaWYgKCRsaWIuZG93bmxvYWRzLmFydGlmYWN0KSB7DQogICAgICAgICAgICAkbGliUGF0aCA9IEpvaW4tUGF0aCAkbGlicmFyaWVzRGlyICRsaWIuZG93bmxvYWRzLmFydGlmYWN0LnBhdGgNCiAgICAgICAgICAgIGlmICgoVGVzdC1QYXRoICRsaWJQYXRoKSAtYW5kICgkY2xhc3NwYXRoIC1ub3Rjb250YWlucyAkbGliUGF0aCkpIHsNCiAgICAgICAgICAgICAgICAkY2xhc3NwYXRoICs9ICRsaWJQYXRoDQogICAgICAgICAgICB9DQogICAgICAgIH0NCiAgICB9DQp9DQoNCiMgQWRkIGNsaWVudCBqYXINCiRjbGllbnRKYXIgPSBKb2luLVBhdGggJHZlcnNpb25EaXIgIiRHYW1lVmVyc2lvbi5qYXIiDQppZiAoVGVzdC1QYXRoICRjbGllbnRKYXIpIHsNCiAgICAkY2xhc3NwYXRoICs9ICRjbGllbnRKYXINCn0gZWxzZSB7DQogICAgV3JpdGUtSG9zdCAiICBFUlJPUjogQ2xpZW50IEpBUiBub3QgZm91bmQ6ICRjbGllbnRKYXIiIC1Gb3JlZ3JvdW5kQ29sb3IgUmVkDQogICAgZXhpdCAxDQp9DQoNCiRjbGFzc3BhdGhTdHJpbmcgPSAkY2xhc3NwYXRoIC1qb2luICI7Ig0KDQpXcml0ZS1Ib3N0ICIgIENsYXNzcGF0aCBidWlsdCB3aXRoICQoJGNsYXNzcGF0aC5Db3VudCkgZW50cmllcyINCg0KIyBCdWlsZCBnYW1lIGFyZ3VtZW50cw0KJGdhbWVBcmdzID0gQCgpDQoNCiMgQ2hlY2sgaWYgdXNpbmcgbW9kZXJuIGFyZ3VtZW50cyBmb3JtYXQNCmlmICgkanNvbi5hcmd1bWVudHMpIHsNCiAgICAjIE1vZGVybiBmb3JtYXQgKDEuMTMrKQ0KICAgIGlmICgkanNvbi5hcmd1bWVudHMuZ2FtZSkgew0KICAgICAgICBmb3JlYWNoICgkYXJnIGluICRqc29uLmFyZ3VtZW50cy5nYW1lKSB7DQogICAgICAgICAgICBpZiAoJGFyZyAtaXMgW3N0cmluZ10pIHsNCiAgICAgICAgICAgICAgICAkZ2FtZUFyZ3MgKz0gJGFyZw0KICAgICAgICAgICAgfQ0KICAgICAgICB9DQogICAgfQ0KICAgIA0KICAgICMgQWRkIGluaGVyaXRlZCBnYW1lIGFyZ3VtZW50cw0KICAgIGlmICgkaW5oZXJpdHNGcm9tIC1hbmQgKFRlc3QtUGF0aCAkaW5oZXJpdGVkSnNvblBhdGgpIC1hbmQgJGluaGVyaXRlZEpzb24uYXJndW1lbnRzIC1hbmQgJGluaGVyaXRlZEpzb24uYXJndW1lbnRzLmdhbWUpIHsNCiAgICAgICAgZm9yZWFjaCAoJGFyZyBpbiAkaW5oZXJpdGVkSnNvbi5hcmd1bWVudHMuZ2FtZSkgew0KICAgICAgICAgICAgaWYgKCRhcmcgLWlzIFtzdHJpbmddIC1hbmQgJGdhbWVBcmdzIC1ub3Rjb250YWlucyAkYXJnKSB7DQogICAgICAgICAgICAgICAgJGdhbWVBcmdzICs9ICRhcmcNCiAgICAgICAgICAgIH0NCiAgICAgICAgfQ0KICAgIH0NCn0gZWxzZWlmICgkanNvbi5taW5lY3JhZnRBcmd1bWVudHMpIHsNCiAgICAjIExlZ2FjeSBmb3JtYXQgKHByZS0xLjEzKQ0KICAgICRnYW1lQXJncyA9ICRqc29uLm1pbmVjcmFmdEFyZ3VtZW50cyAtc3BsaXQgJyAnDQp9DQoNCiMgQnVpbGQgSlZNIGFyZ3VtZW50cw0KJGp2bUFyZ3MgPSBAKCkNCg0KaWYgKCRqc29uLmFyZ3VtZW50cyAtYW5kICRqc29uLmFyZ3VtZW50cy5qdm0pIHsNCiAgICBmb3JlYWNoICgkYXJnIGluICRqc29uLmFyZ3VtZW50cy5qdm0pIHsNCiAgICAgICAgaWYgKCRhcmcgLWlzIFtzdHJpbmddKSB7DQogICAgICAgICAgICAkanZtQXJncyArPSAkYXJnDQogICAgICAgIH0NCiAgICB9DQp9DQoNCiMgQWRkIGluaGVyaXRlZCBKVk0gYXJndW1lbnRzDQppZiAoJGluaGVyaXRzRnJvbSAtYW5kIChUZXN0LVBhdGggJGluaGVyaXRlZEpzb25QYXRoKSAtYW5kICRpbmhlcml0ZWRKc29uLmFyZ3VtZW50cyAtYW5kICRpbmhlcml0ZWRKc29uLmFyZ3VtZW50cy5qdm0pIHsNCiAgICBmb3JlYWNoICgkYXJnIGluICRpbmhlcml0ZWRKc29uLmFyZ3VtZW50cy5qdm0p>>"%LAUNCHER_DIR%temp_b64.txt"
echo IHsNCiAgICAgICAgaWYgKCRhcmcgLWlzIFtzdHJpbmddIC1hbmQgJGp2bUFyZ3MgLW5vdGNvbnRhaW5zICRhcmcpIHsNCiAgICAgICAgICAgICRqdm1BcmdzICs9ICRhcmcNCiAgICAgICAgfQ0KICAgIH0NCn0NCg0KIyBEZWZhdWx0IEpWTSBhcmd1bWVudHMgaWYgbm9uZSBzcGVjaWZpZWQNCmlmICgkanZtQXJncy5Db3VudCAtZXEgMCkgew0KICAgICRqdm1BcmdzID0gQCgNCiAgICAgICAgIi1EamF2YS5saWJyYXJ5LnBhdGg9JG5hdGl2ZXNEaXIiLA0KICAgICAgICAiLWNwIiwNCiAgICAgICAgJGNsYXNzcGF0aFN0cmluZw0KICAgICkNCn0NCg0KIyBDaGVjayBmb3IgbG9nZ2luZyBjb25maWd1cmF0aW9uDQokbG9nZ2luZ0FyZyA9ICIiDQppZiAoJGpzb24ubG9nZ2luZyAtYW5kICRqc29uLmxvZ2dpbmcuY2xpZW50IC1hbmQgJGpzb24ubG9nZ2luZy5jbGllbnQuZmlsZSkgew0KICAgICRsb2dDb25maWdJZCA9ICRqc29uLmxvZ2dpbmcuY2xpZW50LmZpbGUuaWQNCiAgICAkbG9nQ29uZmlnUGF0aCA9IEpvaW4tUGF0aCAkYXNzZXRzRGlyICJsb2dfY29uZmlnc1wkbG9nQ29uZmlnSWQiDQogICAgDQogICAgaWYgKFRlc3QtUGF0aCAkbG9nQ29uZmlnUGF0aCkgew0KICAgICAgICAkbG9nZ2luZ0FyZyA9ICItRGxvZzRqLmNvbmZpZ3VyYXRpb25GaWxlPWAiJGxvZ0NvbmZpZ1BhdGhgIiINCiAgICB9DQp9IGVsc2VpZiAoJGluaGVyaXRzRnJvbSAtYW5kICRpbmhlcml0ZWRKc29uLmxvZ2dpbmcgLWFuZCAkaW5oZXJpdGVkSnNvbi5sb2dnaW5nLmNsaWVudCAtYW5kICRpbmhlcml0ZWRKc29uLmxvZ2dpbmcuY2xpZW50LmZpbGUpIHsNCiAgICAkbG9nQ29uZmlnSWQgPSAkaW5oZXJpdGVkSnNvbi5sb2dnaW5nLmNsaWVudC5maWxlLmlkDQogICAgJGxvZ0NvbmZpZ1BhdGggPSBKb2luLVBhdGggJGFzc2V0c0RpciAibG9nX2NvbmZpZ3NcJGxvZ0NvbmZpZ0lkIg0KICAgIA0KICAgIGlmIChUZXN0LVBhdGggJGxvZ0NvbmZpZ1BhdGgpIHsNCiAgICAgICAgJGxvZ2dpbmdBcmcgPSAiLURsb2c0ai5jb25maWd1cmF0aW9uRmlsZT1gIiRsb2dDb25maWdQYXRoYCIiDQogICAgfQ0KfQ0KDQojIERldGVybWluZSBvcHRpbWFsIEpWTSBhcmdzIGJhc2VkIG9uIHZlcnNpb24NCiR2ZXJzaW9uUGFydHMgPSAkR2FtZVZlcnNpb24gLXNwbGl0ICdcLicNCiRpc09sZFZlcnNpb24gPSAkZmFsc2UNCg0KaWYgKCR2ZXJzaW9uUGFydHNbMF0gLWVxICIxIiAtYW5kIFtpbnRdJHZlcnNpb25QYXJ0c1sxXSAtbGUgNykgew0KICAgICRpc09sZFZlcnNpb24gPSAkdHJ1ZQ0KfQ0KDQojIEV4dHJhIHBlcmZvcm1hbmNlIEpWTSBhcmd1bWVudHMNCiRwZXJmb3JtYW5jZUFyZ3MgPSBpZiAoJGlzT2xkVmVyc2lvbikgew0KICAgICItWFg6K1VzZUNvbmNNYXJrU3dlZXBHQyAtWFg6K0NNU0luY3JlbWVudGFsTW9kZSAtWFg6LVVzZUFkYXB0aXZlU2l6ZVBvbGljeSAtWG1uMTI4TSINCn0gZWxzZSB7DQogICAgIi1YWDorVW5sb2NrRXhwZXJpbWVudGFsVk1PcHRpb25zIC1YWDorVXNlRzFHQyAtWFg6RzFOZXdTaXplUGVyY2VudD0yMCAtWFg6RzFSZXNlcnZlUGVyY2VudD0yMCAtWFg6TWF4R0NQYXVzZU1pbGxpcz01MCAtWFg6RzFIZWFwUmVnaW9uU2l6ZT0zMk0iDQp9DQoNCiMgQnVpbGQgZmluYWwgbGF1bmNoIGNvbW1hbmQNCiRsYXVuY2hBcmdzID0gQCgNCiAgICAiLVhtcyR7TWluUmFtfU0iLA0KICAgICItWG14JHtNYXhSYW19TSIsDQogICAgJHBlcmZvcm1hbmNlQXJncywNCiAgICAiLURsb2c0ajIuZm9ybWF0TXNnTm9Mb29rdXBzPXRydWUiDQopDQoNCmlmICgkbG9nZ2luZ0FyZykgew0KICAgICRsYXVuY2hBcmdzICs9ICRsb2dnaW5nQXJnDQp9DQoNCmlmICgkRXh0cmFKdm1BcmdzKSB7DQogICAgJGxhdW5jaEFyZ3MgKz0gJEV4dHJhSnZtQXJncyAtc3BsaXQgJyAnDQp9DQoNCiMgQWRkIEpWTSBhcmd1bWVudHMNCmZvcmVhY2ggKCRhcmcgaW4gJGp2bUFyZ3MpIHsNCiAgICAkbGF1bmNoQXJncyArPSAkYXJnDQp9DQoNCiMgQWRkIG1haW4gY2xhc3MNCiRsYXVuY2hBcmdzICs9ICRtYWluQ2xhc3MNCg0KIyBBZGQgZ2FtZSBhcmd1bWVudHMgd2l0aCByZXBsYWNlbWVudHMNCmZvcmVhY2ggKCRhcmcgaW4gJGdhbWVBcmdzKSB7DQogICAgJGFyZyA9ICRhcmcuUmVwbGFjZSgnJHthdXRoX3BsYXllcl9uYW1lfScsICRQbGF5ZXJOYW1lKQ0KICAgICRhcmcgPSAkYXJnLlJlcGxhY2UoJyR7dmVyc2lvbl9uYW1lfScsICRHYW1lVmVyc2lvbikNCiAgICAkYXJnID0gJGFyZy5SZXBsYWNlKCcke2dhbWVfZGlyZWN0b3J5fScsICRMYXVuY2hlckRpcikNCiAgICAkYXJnID0gJGFyZy5SZXBsYWNlKCcke2Fzc2V0c19yb290fScsIChKb2luLVBhdGggJExhdW5jaGVyRGlyICJhc3NldHMiKSkNCiAgICAkYXJnID0gJGFyZy5SZXBsYWNlKCcke2Fzc2V0c19pbmRleF9uYW1lfScsICRhc3NldHNJbmRleCkNCiAgICAkYXJnID0gJGFyZy5SZXBsYWNlKCcke2F1dGhfdXVpZH0nLCAkdXVpZCkNCiAgICAkYXJnID0gJGFyZy5SZXBsYWNlKCcke2F1dGhfYWNjZXNzX3Rva2VufScsICIwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMCIpDQogICAgJGFyZyA9ICRhcmcuUmVwbGFjZSgnJHtjbGllbnRpZH0nLCAiMDAwMCIpDQogICAgJGFyZyA9ICRhcmcuUmVwbGFjZSgnJHthdXRoX3h1aWR9JywgIjAwMDAiKQ0KICAgICRhcmcgPSAkYXJnLlJlcGxhY2UoJyR7dXNlcl9wcm9wZXJ0aWVzfScsICJ7fSIpDQogICAgJGFyZyA9ICRhcmcuUmVwbGFjZSgnJHt1c2VyX3R5cGV9JywgIm1vamFuZyIpDQogICAgJGFyZyA9ICRhcmcuUmVwbGFjZSgnJHt2ZXJzaW9uX3R5cGV9JywgInJlbGVhc2UiKQ0KICAgICRhcmcgPSAkYXJnLlJlcGxhY2UoJyR7YXV0aF9zZXNzaW9ufScsICIwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMCIpDQogICAgJGFyZyA9ICRhcmcuUmVwbGFjZSgnJHtnYW1lX2Fzc2V0c30nLCAoSm9pbi1QYXRoICRMYXVuY2hlckRpciAicmVzb3VyY2VzIikpDQogICAgJGFyZyA9ICRhcmcuUmVwbGFjZSgnJHtjbGFzc3BhdGh9JywgJGNsYXNzcGF0aFN0cmluZykNCiAgICAkYXJnID0gJGFyZy5SZXBsYWNlKCcke25hdGl2ZXNfZGlyZWN0b3J5fScsICRuYXRpdmVzRGlyKQ0KICAgICRhcmcgPSAkYXJnLlJlcGxhY2UoJyR7bGF1bmNoZXJfbmFtZX0nLCAiVEZMYXVuY2hlciIpDQogICAgJGFyZyA9ICRhcmcuUmVwbGFjZSgnJHtsYXVuY2hlcl92ZXJzaW9ufScsICIyLjAiKQ0KICAgICRhcmcgPSAkYXJnLlJlcGxhY2UoJyR7Y2xhc3NwYXRoX3NlcGFyYXRvcn0nLCAiOyIpDQogICAgJGFyZyA9ICRhcmcuUmVwbGFjZSgnJHtsaWJyYXJ5X2RpcmVjdG9yeX0nLCAkbGlicmFyaWVzRGlyKQ0KICAgIA0KICAgICRsYXVuY2hBcmdzICs9ICRhcmcNCn0NCg0KIyBIYW5kbGUgYXNzZXRzIGZvciBvbGQgdmVyc2lvbnMNCmlmICgkYXNzZXRzSW5kZXggLWVxICJsZWdhY3kiIC1vciAkYXNzZXRzSW5kZXggLWVxICJwcmUtMS42Iikgew0KICAgIFdyaXRlLUhvc3QgIiAgQ29udmVydGluZyBsZWdhY3kgYXNzZXRzLi4uIg0KICAgIA0KICAgICRyZXNvdXJjZXNEaXIgPSBKb2luLVBhdGggJExhdW5jaGVyRGlyICJyZXNvdXJjZXMiDQogICAgJGFzc2V0SW5kZXhQYXRoID0gSm9pbi1QYXRoICRhc3NldHNEaXIgImluZGV4ZXNcJGFzc2V0c0luZGV4Lmpzb24iDQogICAgDQogICAgaWYgKFRlc3QtUGF0aCAkYXNzZXRJbmRleFBhdGgpIHsNCiAgICAgICAgJGFzc2V0SW5kZXhKc29uID0gR2V0LUNvbnRlbnQgJGFzc2V0SW5kZXhQYXRoIC1SYXcgfCBDb252ZXJ0RnJvbS1Kc29uDQogICAgICAgIA0KICAgICAgICAkY29udmVydGVkID0gMA0KICAgICAgICBmb3JlYWNoICgkYXNzZXQgaW4gJGFzc2V0SW5kZXhKc29uLm9iamVjdHMuUFNPYmplY3QuUHJvcGVydGllcykgew0KICAgICAgICAgICAgJGhhc2ggPSAkYXNzZXQuVmFsdWUuaGFzaA0KICAgICAgICAgICAgJGFzc2V0TmFtZSA9ICRhc3NldC5OYW1lLlJlcGxhY2UoJy8nLCAnXCcpDQogICAgICAgICAgICANCiAgICAgICAgICAgICRzb3VyY2VQYXRoID0gSm9pbi1QYXRoICRhc3NldHNEaXIgIm9iamVjdHNcJCgkaGFzaC5TdWJzdHJpbmcoMCwyKSlcJGhhc2giDQogICAgICAgICAgICAkZGVzdFBhdGggPSBKb2luLVBhdGggJHJlc291cmNlc0RpciAkYXNzZXROYW1lDQogICAgICAgICAgICANCiAgICAgICAgICAgIGlmICgoVGVzdC1QYXRoICRzb3VyY2VQYXRoKSAtYW5kIC1ub3QgKFRlc3QtUGF0aCAkZGVzdFBhdGgpKSB7DQogICAgICAgICAgICAgICAgJGRlc3REaXIgPSBTcGxpdC1QYXRoICRkZXN0UGF0aCAtUGFyZW50DQogICAgICAgICAgICAgICAgaWYgKC1ub3QgKFRlc3QtUGF0aCAkZGVzdERpcikpIHsNCiAgICAgICAgICAgICAgICAgICAgTmV3LUl0ZW0gLUl0ZW1UeXBlIERpcmVjdG9yeSAtUGF0aCAkZGVzdERpciAtRm9yY2UgfCBPdXQtTnVsbA0KICAgICAgICAgICAgICAgIH0NCiAgICAgICAgICAgICAgICBDb3B5LUl0ZW0gJHNvdXJjZVBhdGggJGRlc3RQYXRoIC1Gb3JjZQ0KICAgICAgICAgICAgICAgICRjb252ZXJ0ZWQrKw0KICAgICAgICAgICAgfQ0KICAgICAgICB9DQogICAgICAgIA0KICAgICAgICBpZiAoJGNvbnZlcnRlZCAtZ3QgMCkgew0KICAgICAgICAgICAgV3JpdGUtSG9zdCAiICBDb252ZXJ0ZWQgJGNvbnZlcnRlZCBsZWdhY3kgYXNzZXRzIg0KICAgICAgICB9DQogICAgfQ0KfQ0KDQojIFNhdmUgbGF1bmNoIGNvbW1hbmQgdG8gZmlsZSBmb3IgZGVidWdnaW5nDQokbGF1bmNoQ29tbWFuZCA9ICJgIiRKYXZhRXhlY2AiICIgKyAoJGxhdW5jaEFyZ3MgLWpvaW4gJyAnKQ0KJGxhdW5jaENvbW1hbmQgfCBPdXQtRmlsZSAoSm9pbi1QYXRoICRMYXVuY2hlckRpciAibGFzdF9sYXVuY2gudHh0IikgLUVuY29kaW5nIFVURjgNCg0KV3JpdGUtSG9zdCAiIg0KV3JpdGUtSG9zdCAiICBMYXVuY2hpbmcgTWluZWNyYWZ0Li4uIiAtRm9yZWdyb3VuZENvbG9yIEdyZWVuDQpXcml0ZS1Ib3N0ICIiDQoNCiMgTGF1bmNoIHRoZSBnYW1lDQpTZXQtTG9jYXRpb24gJExhdW5jaGVyRGlyDQokcHJvY2VzcyA9IFN0YXJ0LVByb2Nlc3MgLUZpbGVQYXRoICRKYXZhRXhlYyAtQXJndW1lbnRMaXN0ICRsYXVuY2hBcmdzIC1Xb3JraW5nRGlyZWN0b3J5ICRMYXVuY2hlckRpciAtUGFzc1RocnUNCg0KV3JpdGUtSG9zdCAiICBHYW1lIHByb2Nlc3Mgc3RhcnRlZCAoUElEOiAkKCRwcm9jZXNzLklkKSkiDQpXcml0ZS1Ib3N0ICIgIExhdW5jaCBjb21tYW5kIHNhdmVkIHRvOiBsYXN0X2xhdW5jaC50eHQiDQoNCmV4aXQgMA==>>"%LAUNCHER_DIR%temp_b64.txt"
) >nul 2>&1
powershell -NoProfile -ExecutionPolicy Bypass -Command "$b64 = Get-Content '%LAUNCHER_DIR%temp_b64.txt' -Raw; $bytes = [Convert]::FromBase64String($b64); [IO.File]::WriteAllBytes('%PS1_FILE%', $bytes)" >nul 2>&1
del "%LAUNCHER_DIR%temp_b64.txt" 2>nul
endlocal
exit /b 0

:EXIT
cls
echo.
echo  Thanks for using TFLauncher!
timeout /t 2 /nobreak >nul
exit