param(
    [string]$LauncherDir,
    [string]$GameVersion,
    [string]$PlayerName,
    [string]$MinRam,
    [string]$MaxRam,
    [string]$JavaExec,
    [string]$ExtraJvmArgs = ""
)

$ErrorActionPreference = 'Stop'

# Validate parameters
if ([string]::IsNullOrWhiteSpace($LauncherDir)) {
    Write-Host "  ERROR: LauncherDir parameter is missing!" -ForegroundColor Red
    exit 1
}

if ([string]::IsNullOrWhiteSpace($GameVersion)) {
    Write-Host "  ERROR: GameVersion parameter is missing!" -ForegroundColor Red
    exit 1
}

if ([string]::IsNullOrWhiteSpace($PlayerName)) {
    Write-Host "  ERROR: PlayerName parameter is missing!" -ForegroundColor Red
    exit 1
}

# Paths
$versionDir = Join-Path $LauncherDir "versions\$GameVersion"
$librariesDir = Join-Path $LauncherDir "libraries"
$assetsDir = Join-Path $LauncherDir "assets"
$nativesDir = Join-Path $versionDir "natives"
$versionJson = Join-Path $versionDir "$GameVersion.json"

Write-Host "  Loading version manifest..."

if (-not (Test-Path $versionJson)) {
    Write-Host "  ERROR: Version manifest not found: $versionJson" -ForegroundColor Red
    exit 1
}

$json = Get-Content $versionJson -Raw | ConvertFrom-Json

# Generate UUID for offline player
function Get-OfflineUUID {
    param([string]$PlayerName)
    
    $md5 = [System.Security.Cryptography.MD5]::Create()
    $bytes = [System.Text.Encoding]::UTF8.GetBytes("OfflinePlayer:$PlayerName")
    $hash = $md5.ComputeHash($bytes)
    
    # Convert to hex string
    $hex = [System.BitConverter]::ToString($hash).Replace("-", "").ToLower()
    
    # Format as UUID (version 3, variant 8)
    $uuid = $hex.Substring(0, 12)
    $uuid += [Convert]::ToString(([Convert]::ToInt32($hex.Substring(12, 2), 16) -band 0x0f) -bor 0x30, 16).PadLeft(2, '0')
    $uuid += $hex.Substring(14, 2)
    $uuid += [Convert]::ToString(([Convert]::ToInt32($hex.Substring(16, 2), 16) -band 0x3f) -bor 0x80, 16).PadLeft(2, '0')
    $uuid += $hex.Substring(18, 14)
    
    return $uuid
}

$uuid = Get-OfflineUUID -PlayerName $PlayerName

# Get assets index
$assetsIndex = if ($json.assetIndex) { $json.assetIndex.id } elseif ($json.assets) { $json.assets } else { "legacy" }

# Get main class
$mainClass = $json.mainClass

# Check for inherited version
$inheritsFrom = $null
if ($json.inheritsFrom) {
    $inheritsFrom = $json.inheritsFrom
    $inheritedJsonPath = Join-Path $LauncherDir "versions\$inheritsFrom\$inheritsFrom.json"
    
    if (Test-Path $inheritedJsonPath) {
        Write-Host "  Loading inherited version: $inheritsFrom"
        $inheritedJson = Get-Content $inheritedJsonPath -Raw | ConvertFrom-Json
        
        # Use inherited jar if current version doesn't have one
        $currentJar = Join-Path $versionDir "$GameVersion.jar"
        $inheritedJar = Join-Path $LauncherDir "versions\$inheritsFrom\$inheritsFrom.jar"
        
        if (-not (Test-Path $currentJar) -and (Test-Path $inheritedJar)) {
            Copy-Item $inheritedJar $currentJar -Force
            Write-Host "  Copied inherited JAR"
        }
        
        # Use inherited assets if not specified
        if (-not $json.assetIndex -and $inheritedJson.assetIndex) {
            $assetsIndex = $inheritedJson.assetIndex.id
        } elseif (-not $json.assetIndex -and $inheritedJson.assets) {
            $assetsIndex = $inheritedJson.assets
        }
    }
}

Write-Host "  Assets index: $assetsIndex"

# Extract natives
Write-Host "  Extracting natives..."

if (Test-Path $nativesDir) {
    Remove-Item $nativesDir -Recurse -Force -ErrorAction SilentlyContinue
}
New-Item -ItemType Directory -Path $nativesDir -Force | Out-Null

Add-Type -AssemblyName System.IO.Compression.FileSystem

$nativesExtracted = 0

foreach ($lib in $json.libraries) {
    # Check rules to see if library should be loaded
    $allowLib = $true
    
    if ($lib.rules) {
        $allowLib = $false
        foreach ($rule in $lib.rules) {
            if ($rule.action -eq "allow") {
                if (-not $rule.os -or $rule.os.name -eq "windows") {
                    $allowLib = $true
                }
            } elseif ($rule.action -eq "disallow") {
                if ($rule.os -and $rule.os.name -eq "windows") {
                    $allowLib = $false
                }
            }
        }
    }
    
    if (-not $allowLib) { continue }
    
    # Check for natives
    if ($lib.natives -and $lib.natives.windows) {
        $nativeKey = $lib.natives.windows
        
        if ($lib.downloads.classifiers.$nativeKey) {
            $nativePath = Join-Path $librariesDir $lib.downloads.classifiers.$nativeKey.path
            
            if (Test-Path $nativePath) {
                try {
                    # Extract native library
                    $zip = [System.IO.Compression.ZipFile]::OpenRead($nativePath)
                    
                    foreach ($entry in $zip.Entries) {
                        # Skip META-INF and non-dll files
                        if ($entry.FullName -like "META-INF/*" -or $entry.FullName -like "*.git" -or $entry.FullName -like "*.sha1") {
                            continue
                        }
                        
                        # Extract file
                        $destPath = Join-Path $nativesDir $entry.Name
                        
                        if ($entry.Name) {
                            [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $destPath, $true)
                            $nativesExtracted++
                        }
                    }
                    
                    $zip.Dispose()
                } catch {
                    Write-Host "    Warning: Failed to extract $nativePath" -ForegroundColor Yellow
                }
            }
        }
    }
}

# If inherited version, also extract its natives
if ($inheritsFrom -and (Test-Path $inheritedJsonPath)) {
    $inheritedNativesDir = Join-Path $LauncherDir "versions\$inheritsFrom\natives"
    
    foreach ($lib in $inheritedJson.libraries) {
        $allowLib = $true
        
        if ($lib.rules) {
            $allowLib = $false
            foreach ($rule in $lib.rules) {
                if ($rule.action -eq "allow") {
                    if (-not $rule.os -or $rule.os.name -eq "windows") {
                        $allowLib = $true
                    }
                } elseif ($rule.action -eq "disallow") {
                    if ($rule.os -and $rule.os.name -eq "windows") {
                        $allowLib = $false
                    }
                }
            }
        }
        
        if (-not $allowLib) { continue }
        
        if ($lib.natives -and $lib.natives.windows) {
            $nativeKey = $lib.natives.windows
            
            if ($lib.downloads.classifiers.$nativeKey) {
                $nativePath = Join-Path $librariesDir $lib.downloads.classifiers.$nativeKey.path
                
                if (Test-Path $nativePath) {
                    try {
                        $zip = [System.IO.Compression.ZipFile]::OpenRead($nativePath)
                        
                        foreach ($entry in $zip.Entries) {
                            if ($entry.FullName -like "META-INF/*" -or $entry.FullName -like "*.git" -or $entry.FullName -like "*.sha1") {
                                continue
                            }
                            
                            $destPath = Join-Path $nativesDir $entry.Name
                            
                            if ($entry.Name -and -not (Test-Path $destPath)) {
                                [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $destPath, $true)
                                $nativesExtracted++
                            }
                        }
                        
                        $zip.Dispose()
                    } catch {
                        Write-Host "    Warning: Failed to extract $nativePath" -ForegroundColor Yellow
                    }
                }
            }
        }
    }
}

Write-Host "  Extracted $nativesExtracted native files"

# Build classpath
Write-Host "  Building classpath..."

$classpath = @()

foreach ($lib in $json.libraries) {
    $allowLib = $true
    
    if ($lib.rules) {
        $allowLib = $false
        foreach ($rule in $lib.rules) {
            if ($rule.action -eq "allow") {
                if (-not $rule.os -or $rule.os.name -eq "windows") {
                    $allowLib = $true
                }
            } elseif ($rule.action -eq "disallow") {
                if ($rule.os -and $rule.os.name -eq "windows") {
                    $allowLib = $false
                }
            }
        }
    }
    
    if (-not $allowLib) { continue }
    
    # Skip natives in classpath
    if ($lib.natives) { continue }
    
    if ($lib.downloads.artifact) {
        $libPath = Join-Path $librariesDir $lib.downloads.artifact.path
        if (Test-Path $libPath) {
            $classpath += $libPath
        }
    }
}

# Add inherited libraries
if ($inheritsFrom -and (Test-Path $inheritedJsonPath)) {
    foreach ($lib in $inheritedJson.libraries) {
        $allowLib = $true
        
        if ($lib.rules) {
            $allowLib = $false
            foreach ($rule in $lib.rules) {
                if ($rule.action -eq "allow") {
                    if (-not $rule.os -or $rule.os.name -eq "windows") {
                        $allowLib = $true
                    }
                } elseif ($rule.action -eq "disallow") {
                    if ($rule.os -and $rule.os.name -eq "windows") {
                        $allowLib = $false
                    }
                }
            }
        }
        
        if (-not $allowLib) { continue }
        if ($lib.natives) { continue }
        
        if ($lib.downloads.artifact) {
            $libPath = Join-Path $librariesDir $lib.downloads.artifact.path
            if ((Test-Path $libPath) -and ($classpath -notcontains $libPath)) {
                $classpath += $libPath
            }
        }
    }
}

# Add client jar
$clientJar = Join-Path $versionDir "$GameVersion.jar"
if (Test-Path $clientJar) {
    $classpath += $clientJar
} else {
    Write-Host "  ERROR: Client JAR not found: $clientJar" -ForegroundColor Red
    exit 1
}

$classpathString = $classpath -join ";"

Write-Host "  Classpath built with $($classpath.Count) entries"

# Build game arguments
$gameArgs = @()

# Check if using modern arguments format
if ($json.arguments) {
    # Modern format (1.13+)
    if ($json.arguments.game) {
        foreach ($arg in $json.arguments.game) {
            if ($arg -is [string]) {
                $gameArgs += $arg
            }
        }
    }
    
    # Add inherited game arguments
    if ($inheritsFrom -and (Test-Path $inheritedJsonPath) -and $inheritedJson.arguments -and $inheritedJson.arguments.game) {
        foreach ($arg in $inheritedJson.arguments.game) {
            if ($arg -is [string] -and $gameArgs -notcontains $arg) {
                $gameArgs += $arg
            }
        }
    }
} elseif ($json.minecraftArguments) {
    # Legacy format (pre-1.13)
    $gameArgs = $json.minecraftArguments -split ' '
}

# Build JVM arguments
$jvmArgs = @()

if ($json.arguments -and $json.arguments.jvm) {
    foreach ($arg in $json.arguments.jvm) {
        if ($arg -is [string]) {
            $jvmArgs += $arg
        }
    }
}

# Add inherited JVM arguments
if ($inheritsFrom -and (Test-Path $inheritedJsonPath) -and $inheritedJson.arguments -and $inheritedJson.arguments.jvm) {
    foreach ($arg in $inheritedJson.arguments.jvm) {
        if ($arg -is [string] -and $jvmArgs -notcontains $arg) {
            $jvmArgs += $arg
        }
    }
}

# Default JVM arguments if none specified
if ($jvmArgs.Count -eq 0) {
    $jvmArgs = @(
        "-Djava.library.path=$nativesDir",
        "-cp",
        $classpathString
    )
}

# Check for logging configuration
$loggingArg = ""
if ($json.logging -and $json.logging.client -and $json.logging.client.file) {
    $logConfigId = $json.logging.client.file.id
    $logConfigPath = Join-Path $assetsDir "log_configs\$logConfigId"
    
    if (Test-Path $logConfigPath) {
        $loggingArg = "-Dlog4j.configurationFile=`"$logConfigPath`""
    }
} elseif ($inheritsFrom -and $inheritedJson.logging -and $inheritedJson.logging.client -and $inheritedJson.logging.client.file) {
    $logConfigId = $inheritedJson.logging.client.file.id
    $logConfigPath = Join-Path $assetsDir "log_configs\$logConfigId"
    
    if (Test-Path $logConfigPath) {
        $loggingArg = "-Dlog4j.configurationFile=`"$logConfigPath`""
    }
}

# Determine optimal JVM args based on version
$versionParts = $GameVersion -split '\.'
$isOldVersion = $false

if ($versionParts[0] -eq "1" -and [int]$versionParts[1] -le 7) {
    $isOldVersion = $true
}

# Extra performance JVM arguments
$performanceArgs = if ($isOldVersion) {
    "-XX:+UseConcMarkSweepGC -XX:+CMSIncrementalMode -XX:-UseAdaptiveSizePolicy -Xmn128M"
} else {
    "-XX:+UnlockExperimentalVMOptions -XX:+UseG1GC -XX:G1NewSizePercent=20 -XX:G1ReservePercent=20 -XX:MaxGCPauseMillis=50 -XX:G1HeapRegionSize=32M"
}

# Build final launch command
$launchArgs = @(
    "-Xms${MinRam}M",
    "-Xmx${MaxRam}M",
    $performanceArgs,
    "-Dlog4j2.formatMsgNoLookups=true"
)

if ($loggingArg) {
    $launchArgs += $loggingArg
}

if ($ExtraJvmArgs) {
    $launchArgs += $ExtraJvmArgs -split ' '
}

# Add JVM arguments
foreach ($arg in $jvmArgs) {
    $launchArgs += $arg
}

# Add main class
$launchArgs += $mainClass

# Add game arguments with replacements
foreach ($arg in $gameArgs) {
    $arg = $arg.Replace('${auth_player_name}', $PlayerName)
    $arg = $arg.Replace('${version_name}', $GameVersion)
    $arg = $arg.Replace('${game_directory}', $LauncherDir)
    $arg = $arg.Replace('${assets_root}', (Join-Path $LauncherDir "assets"))
    $arg = $arg.Replace('${assets_index_name}', $assetsIndex)
    $arg = $arg.Replace('${auth_uuid}', $uuid)
    $arg = $arg.Replace('${auth_access_token}', "00000000000000000000000000000000")
    $arg = $arg.Replace('${clientid}', "0000")
    $arg = $arg.Replace('${auth_xuid}', "0000")
    $arg = $arg.Replace('${user_properties}', "{}")
    $arg = $arg.Replace('${user_type}', "mojang")
    $arg = $arg.Replace('${version_type}', "release")
    $arg = $arg.Replace('${auth_session}', "00000000000000000000000000000000")
    $arg = $arg.Replace('${game_assets}', (Join-Path $LauncherDir "resources"))
    $arg = $arg.Replace('${classpath}', $classpathString)
    $arg = $arg.Replace('${natives_directory}', $nativesDir)
    $arg = $arg.Replace('${launcher_name}', "TFLauncher")
    $arg = $arg.Replace('${launcher_version}', "2.0")
    $arg = $arg.Replace('${classpath_separator}', ";")
    $arg = $arg.Replace('${library_directory}', $librariesDir)
    
    $launchArgs += $arg
}

# Handle assets for old versions
if ($assetsIndex -eq "legacy" -or $assetsIndex -eq "pre-1.6") {
    Write-Host "  Converting legacy assets..."
    
    $resourcesDir = Join-Path $LauncherDir "resources"
    $assetIndexPath = Join-Path $assetsDir "indexes\$assetsIndex.json"
    
    if (Test-Path $assetIndexPath) {
        $assetIndexJson = Get-Content $assetIndexPath -Raw | ConvertFrom-Json
        
        $converted = 0
        foreach ($asset in $assetIndexJson.objects.PSObject.Properties) {
            $hash = $asset.Value.hash
            $assetName = $asset.Name.Replace('/', '\')
            
            $sourcePath = Join-Path $assetsDir "objects\$($hash.Substring(0,2))\$hash"
            $destPath = Join-Path $resourcesDir $assetName
            
            if ((Test-Path $sourcePath) -and -not (Test-Path $destPath)) {
                $destDir = Split-Path $destPath -Parent
                if (-not (Test-Path $destDir)) {
                    New-Item -ItemType Directory -Path $destDir -Force | Out-Null
                }
                Copy-Item $sourcePath $destPath -Force
                $converted++
            }
        }
        
        if ($converted -gt 0) {
            Write-Host "  Converted $converted legacy assets"
        }
    }
}

# Save launch command to file for debugging
$launchCommand = "`"$JavaExec`" " + ($launchArgs -join ' ')
$launchCommand | Out-File (Join-Path $LauncherDir "last_launch.txt") -Encoding UTF8

Write-Host ""
Write-Host "  Launching Minecraft..." -ForegroundColor Green
Write-Host ""

# Launch the game
Set-Location $LauncherDir
$process = Start-Process -FilePath $JavaExec -ArgumentList $launchArgs -WorkingDirectory $LauncherDir -PassThru

Write-Host "  Game process started (PID: $($process.Id))"
Write-Host "  Launch command saved to: last_launch.txt"

exit 0