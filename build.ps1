#!/usr/bin/env pwsh

# PowerShell build script for Windows
param(
    [switch]$Force
)

$ErrorActionPreference = "Stop"

$ZIG_VERSION_FILE = ".zigversion"
$DEFAULT_ZIG_VERSION = "0.14"
$ZIG_DIR = ".zig-install"
$ZIG_BIN = ""

Write-Host "[->] Windows PowerShell build script for loxz" -ForegroundColor Cyan

# Check for system zig and verify version
$systemZig = Get-Command zig -ErrorAction SilentlyContinue
$needsDownload = $false

if ($systemZig) {
    Write-Host "[+] Found system 'zig' at: $($systemZig.Source)" -ForegroundColor Green
    
    # Check if we need a specific version and if -Force is used
    if ($Force -and (Test-Path $ZIG_VERSION_FILE)) {
        $REQUIRED_VERSION = Get-Content $ZIG_VERSION_FILE -Raw | ForEach-Object { $_.Trim() }
        $currentVersion = & "$($systemZig.Source)" version
        
        if ($currentVersion -eq $REQUIRED_VERSION) {
            Write-Host "[+] System Zig version $currentVersion matches required version" -ForegroundColor Green
            $ZIG_BIN = $systemZig.Source
        } else {
            Write-Host "[!] -Force specified: System Zig version $currentVersion does not match required version $REQUIRED_VERSION" -ForegroundColor Yellow
            Write-Host "[->] Will download and use required version $REQUIRED_VERSION" -ForegroundColor Cyan
            $needsDownload = $true
        }
    } else {
        # Use system Zig regardless of version when -Force is not specified
        if (Test-Path $ZIG_VERSION_FILE) {
            $REQUIRED_VERSION = Get-Content $ZIG_VERSION_FILE -Raw | ForEach-Object { $_.Trim() }
            $currentVersion = & "$($systemZig.Source)" version
            if ($currentVersion -ne $REQUIRED_VERSION) {
                Write-Host "" -ForegroundColor Yellow
                Write-Host "WARNING: Version mismatch detected!" -ForegroundColor Yellow
                Write-Host "  Required version (from .zigversion): $REQUIRED_VERSION" -ForegroundColor Yellow
                Write-Host "  System Zig version: $currentVersion" -ForegroundColor Yellow
                Write-Host "  Continuing with system Zig (use -Force to download exact version)" -ForegroundColor Yellow
                Write-Host "" -ForegroundColor Yellow
            } else {
                Write-Host "[+] System Zig version matches required version: $currentVersion" -ForegroundColor Green
            }
        }
        $ZIG_BIN = $systemZig.Source
    }
} else {
    Write-Host "[!] 'zig' binary not found in system PATH." -ForegroundColor Yellow
    $needsDownload = $true
}

if ($needsDownload) {

    # Check for existing zig in .zig-install
    $existingZig = $null
    if (Test-Path $ZIG_DIR) {
        $zigCandidates = Get-ChildItem -Path $ZIG_DIR -Recurse -Name "zig.exe" -ErrorAction SilentlyContinue
        foreach ($candidate in $zigCandidates) {
            $candidatePath = Join-Path $ZIG_DIR $candidate
            # Verify it's a Windows PE executable by checking the file header
            try {
                $bytes = [System.IO.File]::ReadAllBytes($candidatePath) | Select-Object -First 64
                # Check for PE header signature (MZ at start, PE signature later)
                if ($bytes[0] -eq 0x4D -and $bytes[1] -eq 0x5A) {
                    # Found MZ header, this looks like a Windows executable
                    $existingZig = $candidate
                    break
                }
            } catch {
                # If we can't read the file, skip it
                continue
            }
        }
    }
    
    if ($existingZig) {
        $ZIG_BIN = Join-Path $ZIG_DIR $existingZig
        Write-Host "[+] Found existing Windows zig.exe at: $ZIG_BIN" -ForegroundColor Green
    } else {
        # Prompt user to download zig
        if (-not $Force) {
            $response = Read-Host "Do you want to download Zig as per .zigversion and install to .zig-install/? [Y/n]"
            if ($response -match "^[Nn]") {
                Write-Host "[X] Aborted." -ForegroundColor Red
                exit 1
            }
        }

        # Get Zig version
        if (Test-Path $ZIG_VERSION_FILE) {
            $ZIG_VERSION = Get-Content $ZIG_VERSION_FILE -Raw | ForEach-Object { $_.Trim() }
        } else {
            Write-Host "[X] $ZIG_VERSION_FILE not found! Defaulting to zig $DEFAULT_ZIG_VERSION" -ForegroundColor Yellow
            $ZIG_VERSION = $DEFAULT_ZIG_VERSION
        }
        Write-Host "[->] Zig version to download: $ZIG_VERSION" -ForegroundColor Cyan

        # Detect architecture
        $ARCH = $env:PROCESSOR_ARCHITECTURE
        switch ($ARCH) {
            "AMD64" { $ARCH = "x86_64" }
            "ARM64" { $ARCH = "aarch64" }
            "x86" { $ARCH = "x86" }
            default {
                Write-Host "[X] Unsupported architecture: $ARCH" -ForegroundColor Red
                Write-Host "[!] Supported architectures: x86_64 (AMD64), aarch64 (ARM64), x86" -ForegroundColor Yellow
                exit 1
            }
        }

        $PLATFORM = "windows"
        $EXT = "zip"
        $ZIG_ZIP = "zig-$ARCH-$PLATFORM-$ZIG_VERSION.$EXT"
        $ZIG_URL = "https://ziglang.org/download/$ZIG_VERSION/$ZIG_ZIP"
        $TEMP_PATH = Join-Path $env:TEMP $ZIG_ZIP

        Write-Host "[v] Downloading Zig from $ZIG_URL..." -ForegroundColor Cyan
        
        # Create .zig-install directory (clean it if it exists to avoid conflicts)
        if (Test-Path $ZIG_DIR) {
            Write-Host "[i] Cleaning existing .zig-install directory..." -ForegroundColor Gray
            Remove-Item $ZIG_DIR -Recurse -Force -ErrorAction SilentlyContinue
        }
        New-Item -ItemType Directory -Path $ZIG_DIR -Force | Out-Null

        try {
            # Download with progress
            $webClient = New-Object System.Net.WebClient
            $webClient.DownloadFile($ZIG_URL, $TEMP_PATH)
            Write-Host "[+] Download completed" -ForegroundColor Green
        } catch {
            Write-Host "[X] Download failed. Trying master builds URL..." -ForegroundColor Yellow
            $ZIG_URL = "https://ziglang.org/builds/$ZIG_ZIP"
            Write-Host "[->] Trying: $ZIG_URL" -ForegroundColor Cyan
            
            try {
                if (-not $webClient) { $webClient = New-Object System.Net.WebClient }
                $webClient.DownloadFile($ZIG_URL, $TEMP_PATH)
                Write-Host "[+] Download completed from master builds" -ForegroundColor Green
            } catch {
                Write-Host "[X] Both download URLs failed. Please check the Zig version in .zigversion" -ForegroundColor Red
                Write-Host "[!] Available versions: https://ziglang.org/download/" -ForegroundColor Yellow
                exit 1
            }
        } finally {
            if ($webClient) { $webClient.Dispose() }
        }

        # Verify the downloaded file exists and has content
        if (-not (Test-Path $TEMP_PATH) -or (Get-Item $TEMP_PATH).Length -eq 0) {
            Write-Host "[X] Downloaded file is invalid or empty" -ForegroundColor Red
            exit 1
        }

        Write-Host "[<>] Extracting Zig..." -ForegroundColor Cyan
        Write-Host "[i] Download location: $TEMP_PATH" -ForegroundColor Gray
        Write-Host "[i] Extract destination: $ZIG_DIR" -ForegroundColor Gray
        
        # Check if destination already exists and might cause conflicts
        if (Test-Path $ZIG_DIR) {
            $existingFiles = Get-ChildItem -Path $ZIG_DIR -Recurse -Force | Measure-Object
            Write-Host "[i] Found $($existingFiles.Count) existing files in $ZIG_DIR" -ForegroundColor Gray
        }
        
        try {
            # Extract using .NET
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            Write-Host "[i] Starting extraction..." -ForegroundColor Gray
            [System.IO.Compression.ZipFile]::ExtractToDirectory($TEMP_PATH, $ZIG_DIR)
            Write-Host "[+] Extraction completed" -ForegroundColor Green
        } catch {
            Write-Host "[X] Failed to extract Zig archive: $($_.Exception.Message)" -ForegroundColor Red
            Write-Host "[i] Exception type: $($_.Exception.GetType().Name)" -ForegroundColor Gray
            if ($_.Exception.InnerException) {
                Write-Host "[i] Inner exception: $($_.Exception.InnerException.Message)" -ForegroundColor Gray
            }
            exit 1
        }

        # Clean up temporary download file and notify user
        Write-Host "[i] Cleaning up temporary artifacts..." -ForegroundColor Gray
        if (Test-Path $TEMP_PATH) {
            Remove-Item $TEMP_PATH -Force -ErrorAction SilentlyContinue
            Write-Host "[+] Removed temporary download file: $TEMP_PATH" -ForegroundColor Green
        }
        
        # Clean up any other temporary files that might have been created
        $tempPattern = Join-Path $env:TEMP "zig-*-windows-*.zip*"
        $tempFiles = Get-ChildItem -Path $tempPattern -ErrorAction SilentlyContinue
        if ($tempFiles) {
            $tempFiles | Remove-Item -Force -ErrorAction SilentlyContinue
            Write-Host "[+] Cleaned up $($tempFiles.Count) additional temporary Zig files" -ForegroundColor Green
        }
        
        Write-Host "[+] Temporary cleanup completed" -ForegroundColor Green

        # Find the zig executable and verify it's a Windows PE executable
        $zigExe = $null
        $zigCandidates = Get-ChildItem -Path $ZIG_DIR -Recurse -Name "zig.exe" -ErrorAction SilentlyContinue
        foreach ($candidate in $zigCandidates) {
            $candidatePath = Join-Path $ZIG_DIR $candidate
            try {
                $bytes = [System.IO.File]::ReadAllBytes($candidatePath) | Select-Object -First 64
                # Check for PE header signature (MZ at start indicates Windows executable)
                if ($bytes[0] -eq 0x4D -and $bytes[1] -eq 0x5A) {
                    $zigExe = $candidate
                    break
                }
            } catch {
                continue
            }
        }
        
        if (-not $zigExe) {
            Write-Host "[X] Failed to find a valid Windows 'zig.exe' after extraction." -ForegroundColor Red
            Write-Host "[!] Found files may be for different platform (Linux/macOS)" -ForegroundColor Yellow
            exit 1
        }

        $ZIG_BIN = Join-Path $ZIG_DIR $zigExe
        Write-Host "[+] Zig installed to: $ZIG_BIN" -ForegroundColor Green
    }
}

# Build loxz
Write-Host "[*] Building loxz with $ZIG_BIN..." -ForegroundColor Cyan
try {
    & "$ZIG_BIN" build -Doptimize=ReleaseFast
    if ($LASTEXITCODE -ne 0) {
        throw "Zig build failed with exit code $LASTEXITCODE"
    }
} catch {
    Write-Host "[X] Build failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Move built binary
$BUILT_BIN = ".\zig-out\bin\loxz.exe"
if (-not (Test-Path $BUILT_BIN)) {
    Write-Host "[X] Build failed, binary not found at $BUILT_BIN" -ForegroundColor Red
    exit 1
}

Copy-Item $BUILT_BIN ".\loxz.exe" -Force
Write-Host "[+] loxz built and copied to .\loxz.exe" -ForegroundColor Green
