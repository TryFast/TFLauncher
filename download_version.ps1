param(
    [string]$VersionDir,
    [string]$VersionName,
    [string]$LibrariesDir,
    [string]$AssetsDir
)

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Download-WithRetry {
    param(
        [string]$Url,
        [string]$OutFile,
        [int]$MaxRetries = 3
    )
    
    $retryCount = 0
    while ($retryCount -lt $MaxRetries) {
        try {
            $parentDir = Split-Path $OutFile -Parent
            if (!(Test-Path $parentDir)) {
                New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
            }
            
            # Skip if file exists and has content
            if (Test-Path $OutFile) {
                $fileInfo = Get-Item $OutFile
                if ($fileInfo.Length -gt 0) {
                    return $true
                }
            }
            
            Invoke-WebRequest -Uri $Url -OutFile $OutFile -TimeoutSec 60
            return $true
        } catch {
            $retryCount++
            if ($retryCount -lt $MaxRetries) {
                Start-Sleep -Seconds 2
            } else {
                Write-Host "    Failed to download: $Url" -ForegroundColor Red
                return $false
            }
        }
    }
    return $false
}

try {
    $versionJsonPath = Join-Path $VersionDir "$VersionName.json"
    
    if (!(Test-Path $versionJsonPath)) {
        Write-Host "  ERROR: Version manifest not found!" -ForegroundColor Red
        exit 1
    }
    
    $versionJson = Get-Content $versionJsonPath -Raw | ConvertFrom-Json
    
    # Download client JAR
    Write-Host "  [1/4] Downloading client JAR..."
    $clientUrl = $versionJson.downloads.client.url
    $clientPath = Join-Path $VersionDir "$VersionName.jar"
    
    if (Download-WithRetry -Url $clientUrl -OutFile $clientPath) {
        $sizeMB = [math]::Round((Get-Item $clientPath).Length / 1MB, 2)
        Write-Host "    Client JAR: $sizeMB MB" -ForegroundColor Green
    } else {
        Write-Host "    ERROR: Failed to download client JAR" -ForegroundColor Red
        exit 1
    }
    
    # Download libraries
    Write-Host "  [2/4] Downloading libraries..."
    $libCount = 0
    $libTotal = 0
    
    foreach ($lib in $versionJson.libraries) {
        $libTotal++
    }
    
    foreach ($lib in $versionJson.libraries) {
        # Check rules
        $allowLib = $true
        
        if ($lib.rules) {
            $allowLib = $false
            foreach ($rule in $lib.rules) {
                if ($rule.action -eq "allow") {
                    if (!$rule.os -or $rule.os.name -eq "windows") {
                        $allowLib = $true
                    }
                } elseif ($rule.action -eq "disallow") {
                    if ($rule.os -and $rule.os.name -eq "windows") {
                        $allowLib = $false
                    }
                }
            }
        }
        
        if (!$allowLib) { continue }
        
        # Download artifact (main library)
        if ($lib.downloads.artifact) {
            $libPath = Join-Path $LibrariesDir $lib.downloads.artifact.path
            if (Download-WithRetry -Url $lib.downloads.artifact.url -OutFile $libPath) {
                $libCount++
            }
        }
        
        # Download natives
        if ($lib.downloads.classifiers) {
            $osKey = "natives-windows"
            if ($lib.downloads.classifiers.$osKey) {
                $nativePath = Join-Path $LibrariesDir $lib.downloads.classifiers.$osKey.path
                if (Download-WithRetry -Url $lib.downloads.classifiers.$osKey.url -OutFile $nativePath) {
                    $libCount++
                }
            }
        }
        
        if ($libCount % 10 -eq 0) {
            Write-Host "    Progress: $libCount/$libTotal" -ForegroundColor Cyan
        }
    }
    
    Write-Host "    Libraries: $libCount/$libTotal" -ForegroundColor Green
    
    # Download inherited version if exists
    if ($versionJson.inheritsFrom) {
        $inheritedVersion = $versionJson.inheritsFrom
        Write-Host "  [2.5/4] Downloading inherited version: $inheritedVersion..."
        
        $inheritedDir = Join-Path (Split-Path $VersionDir -Parent) $inheritedVersion
        $inheritedJsonPath = Join-Path $inheritedDir "$inheritedVersion.json"
        
        if (!(Test-Path $inheritedDir)) {
            New-Item -ItemType Directory -Path $inheritedDir -Force | Out-Null
        }
        
        # Find inherited version URL from manifest
        $manifestPath = Join-Path (Split-Path $VersionDir -Parent | Split-Path -Parent) "version_manifest_v2.json"
        
        if (Test-Path $manifestPath) {
            $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
            $inheritedVersionInfo = $manifest.versions | Where-Object { $_.id -eq $inheritedVersion }
            
            if ($inheritedVersionInfo) {
                Download-WithRetry -Url $inheritedVersionInfo.url -OutFile $inheritedJsonPath | Out-Null
                
                if (Test-Path $inheritedJsonPath) {
                    $inheritedJson = Get-Content $inheritedJsonPath -Raw | ConvertFrom-Json
                    
                    # Download inherited JAR
                    if ($inheritedJson.downloads.client) {
                        $inheritedJarPath = Join-Path $inheritedDir "$inheritedVersion.jar"
                        Download-WithRetry -Url $inheritedJson.downloads.client.url -OutFile $inheritedJarPath | Out-Null
                    }
                    
                    # Download inherited libraries
                    $inheritedLibCount = 0
                    foreach ($lib in $inheritedJson.libraries) {
                        $allowLib = $true
                        
                        if ($lib.rules) {
                            $allowLib = $false
                            foreach ($rule in $lib.rules) {
                                if ($rule.action -eq "allow") {
                                    if (!$rule.os -or $rule.os.name -eq "windows") {
                                        $allowLib = $true
                                    }
                                } elseif ($rule.action -eq "disallow") {
                                    if ($rule.os -and $rule.os.name -eq "windows") {
                                        $allowLib = $false
                                    }
                                }
                            }
                        }
                        
                        if (!$allowLib) { continue }
                        
                        if ($lib.downloads.artifact) {
                            $libPath = Join-Path $LibrariesDir $lib.downloads.artifact.path
                            if (Download-WithRetry -Url $lib.downloads.artifact.url -OutFile $libPath) {
                                $inheritedLibCount++
                            }
                        }
                        
                        if ($lib.downloads.classifiers) {
                            $osKey = "natives-windows"
                            if ($lib.downloads.classifiers.$osKey) {
                                $nativePath = Join-Path $LibrariesDir $lib.downloads.classifiers.$osKey.path
                                if (Download-WithRetry -Url $lib.downloads.classifiers.$osKey.url -OutFile $nativePath) {
                                    $inheritedLibCount++
                                }
                            }
                        }
                    }
                    
                    Write-Host "    Inherited libraries: $inheritedLibCount" -ForegroundColor Green
                }
            }
        }
    }
    
    # Download logging configuration
    Write-Host "  [3/4] Downloading logging configuration..."
    
    if ($versionJson.logging -and $versionJson.logging.client -and $versionJson.logging.client.file) {
        $logConfigUrl = $versionJson.logging.client.file.url
        $logConfigId = $versionJson.logging.client.file.id
        $logConfigDir = Join-Path $AssetsDir "log_configs"
        
        if (!(Test-Path $logConfigDir)) {
            New-Item -ItemType Directory -Path $logConfigDir -Force | Out-Null
        }
        
        $logConfigPath = Join-Path $logConfigDir $logConfigId
        
        if (Download-WithRetry -Url $logConfigUrl -OutFile $logConfigPath) {
            Write-Host "    Logging config: OK" -ForegroundColor Green
        }
    } else {
        Write-Host "    Logging config: Not required" -ForegroundColor Yellow
    }
    
    # Download assets
    Write-Host "  [4/4] Downloading assets..."
    
    if ($versionJson.assetIndex) {
        $assetIndexUrl = $versionJson.assetIndex.url
        $assetIndexId = $versionJson.assetIndex.id
        $assetIndexDir = Join-Path $AssetsDir "indexes"
        
        if (!(Test-Path $assetIndexDir)) {
            New-Item -ItemType Directory -Path $assetIndexDir -Force | Out-Null
        }
        
        $assetIndexPath = Join-Path $assetIndexDir "$assetIndexId.json"
        
        if (!(Download-WithRetry -Url $assetIndexUrl -OutFile $assetIndexPath)) {
            Write-Host "    ERROR: Failed to download asset index" -ForegroundColor Red
            exit 1
        }
        
        $assetIndex = Get-Content $assetIndexPath -Raw | ConvertFrom-Json
        $assetCount = 0
        $totalAssets = ($assetIndex.objects | Get-Member -MemberType NoteProperty).Count
        
        Write-Host "    Total assets: $totalAssets" -ForegroundColor Cyan
        
        foreach ($asset in $assetIndex.objects.PSObject.Properties) {
            $hash = $asset.Value.hash
            $hashPrefix = $hash.Substring(0, 2)
            $assetUrl = "https://resources.download.minecraft.net/$hashPrefix/$hash"
            $assetPath = Join-Path (Join-Path $AssetsDir "objects") (Join-Path $hashPrefix $hash)
            
            if (Download-WithRetry -Url $assetUrl -OutFile $assetPath) {
                $assetCount++
                
                if ($assetCount % 100 -eq 0) {
                    $percent = [math]::Round(($assetCount / $totalAssets) * 100, 1)
                    Write-Host "    Progress: $assetCount/$totalAssets ($percent%)" -ForegroundColor Cyan
                }
            }
        }
        
        Write-Host "    Assets: $assetCount/$totalAssets" -ForegroundColor Green
    } else {
        Write-Host "    No asset index found" -ForegroundColor Yellow
    }
    
    Write-Host ""
    Write-Host "  Download Complete!" -ForegroundColor Green
    exit 0
    
} catch {
    Write-Host ""
    Write-Host "  ERROR: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}