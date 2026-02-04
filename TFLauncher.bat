@echo off
setlocal enabledelayedexpansion

:: Keep window open on error
if "%1"=="RELAUNCH" goto START
cmd /c "%~f0" RELAUNCH
pause
exit

:START
title TFLauncher - Minecraft Launcher v0.1
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
echo    TFLauncher v0.1
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
if not exist "%~dp0launch_minecraft.ps1" (
    echo  ERROR: launch_minecraft.ps1 not found!
    echo  Make sure all launcher files are in the same folder.
    echo.
    pause
    goto MAIN_MENU
)

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
echo ^& '%~dp0launch_minecraft.ps1' -LauncherDir $LauncherDir -GameVersion $GameVersion -PlayerName $PlayerName -MinRam $MinRam -MaxRam $MaxRam -JavaExec $JavaExec -ExtraJvmArgs $ExtraJvmArgs
) > "%LAUNCHER_DIR%temp_wrapper.ps1"

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%LAUNCHER_DIR%temp_wrapper.ps1"

set RESULT=%errorlevel%

del "%LAUNCHER_DIR%temp_wrapper.ps1" 2>nul

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

if not exist "%~dp0download_version.ps1" (
    echo  ERROR: download_version.ps1 not found!
    pause
    goto MAIN_MENU
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0download_version.ps1" -VersionDir "%VERSIONS_DIR%\%version_input%" -VersionName "%version_input%" -LibrariesDir "%LIBRARIES_DIR%" -AssetsDir "%ASSETS_DIR%"

if errorlevel 1 (
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

:EXIT
cls
echo.
echo  Thanks for using TFLauncher!
timeout /t 2 /nobreak >nul
exit