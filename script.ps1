#Requires -RunAsAdministrator
<#
.SYNOPSIS
Combined installation script for Godspeed CLI, daemon, and required dependencies.
#>

Write-Host "Starting Godspeed Full Installation..." -ForegroundColor Cyan

#region Admin Check
$currentPrincipal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "This script must be run as Administrator. Please right-click and 'Run as Administrator'." -ForegroundColor Red
    exit
}
#endregion

#region Node.js and NVM Setup
Write-Host "`nChecking Node.js installation..." -ForegroundColor Cyan

# Improved NVM detection
$nvmInstalled = $false
try {
    $nvmVersion = cmd /c nvm version 2>&1
    if (-not ($nvmVersion -match "not recognized")) {
        $nvmInstalled = $true
        $nvmPath = (Get-ItemProperty "HKCU:\Environment").NVM_HOME
    }
} catch { }

# Check existing Node installation
$nodeInstalled = Get-Command node -ErrorAction SilentlyContinue

if ($nodeInstalled) {
    Write-Host "Node.js detected. Checking installation source..."
    
    if (-not $nvmInstalled) {
        Write-Host "NVM not detected. Checking for winget installation..."
        $wingetNode = winget list --id OpenJS.NodeJS | Select-String -Pattern 'OpenJS.NodeJS'
        
        if ($wingetNode) {
            Write-Host "Removing winget-installed Node.js..."
            winget uninstall -e --id OpenJS.NodeJS
        }
        else {
            Write-Host "Non-NVM Node.js installation detected. Please remove manually and restart the script." -ForegroundColor Red
            exit
        }
    }
}

# Install/Update NVM
if (-not $nvmInstalled) {
    Write-Host "Installing NVM for Windows..." -ForegroundColor Cyan
    winget install -e --id CoreyButler.NVMforWindows
    
    # Force refresh environment variables
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
    
    # Set NVM_HOME if not present
    $nvmHome = [Environment]::GetEnvironmentVariable("NVM_HOME", "User")
    if (-not $nvmHome) {
        $nvmDir = "${env:ProgramFiles}\NVM for Windows"
        [Environment]::SetEnvironmentVariable("NVM_HOME", $nvmDir, "User")
        $env:NVM_HOME = $nvmDir
    }
    
    # Wait for environment to update
    Write-Host "Waiting for environment to update..." -ForegroundColor Yellow
    Start-Sleep -Seconds 10
    
    # Verify NVM is now available
    try {
        $nvmCheck = cmd /c nvm version 2>&1
        if ($nvmCheck -match "not recognized") {
            throw "NVM still not recognized"
        }
        $nvmInstalled = $true
    } catch {
        Write-Host "NVM installation verification failed. Please restart your shell and run the script again." -ForegroundColor Red
        exit
    }
}

# Install Node.js via NVM
Write-Host "Installing Node.js LTS via NVM..." -ForegroundColor Cyan
cmd /c "nvm install lts"
cmd /c "nvm use lts"

# Force refresh PATH after NVM changes
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

# Verify Node and npm are available
try {
    $nodeVersion = node -v
    $npmVersion = npm -v
    Write-Host "Node.js version: $nodeVersion"
    Write-Host "npm version: $npmVersion"
} catch {
    Write-Host "Node/npm commands not available. Trying to refresh environment..." -ForegroundColor Yellow
    
    # Additional environment refresh attempts
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
    $env:Path += ";$env:NVM_HOME"
    
    # Final verification
    if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
        Write-Host "Node/npm still not available. Please restart your shell and run the script again." -ForegroundColor Red
        exit
    }
}

# Enable Corepack and pnpm
Write-Host "Configuring package managers..." -ForegroundColor Cyan
try {
    corepack enable
    corepack prepare pnpm@latest --activate
} catch {
    Write-Host "Corepack commands failed. Trying alternative approach..." -ForegroundColor Yellow
    
    # Add Node.js global binaries to PATH if not already there
    $nodePath = cmd /c "nvm which current" | Select-Object -First 1
    $nodeDir = [System.IO.Path]::GetDirectoryName($nodePath)
    if (-not $env:Path.Contains($nodeDir)) {
        $env:Path += ";$nodeDir"
    }
    
    # Retry corepack
    corepack enable
    corepack prepare pnpm@latest --activate
}
#endregion


#region Git Installation
Write-Host "`nInstalling Git..." -ForegroundColor Cyan
winget install -e --id Git.Git

# Refresh environment variables after Git installation
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

# Verify Git installation
try {
    # Get Git installation path from registry
    $gitInstallPath = (Get-ItemProperty "HKLM:\SOFTWARE\GitForWindows").InstallPath
    if ($gitInstallPath -and (-not $env:Path.Contains($gitInstallPath))) {
        $env:Path += ";$gitInstallPath\bin"
        [Environment]::SetEnvironmentVariable("Path", "$($env:Path);$gitInstallPath\bin", "User")
    }
    
    # Check if git command is now available
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        throw "Git command still not available"
    }
    
    Write-Host "Git version: $(git --version)"
} catch {
    Write-Host "Git installation verification failed. Please restart your shell to access Git commands." -ForegroundColor Yellow
}
#endregion

#region CLI Installation
Write-Host "`nInstalling Godspeed CLI..." -ForegroundColor Cyan
npm install -g @godspeedsystems/godspeed
#endregion

#region Daemon Installation
Write-Host "`nStarting Daemon Installation..." -ForegroundColor Cyan

$daemonUrl = "https://github.com/zero8dotdev/install-godspeed-daemon/releases/download/v1.1.2/godspeed-daemon-win.exe"
$targetDir = "$env:USERPROFILE\AppData\Local\Programs\godspeed"
$destinationPath = "$targetDir\godspeed-daemon.exe"

# Create installation directory
if (-not (Test-Path $targetDir)) {
    New-Item -Path $targetDir -ItemType Directory -Force | Out-Null
}

# Download daemon
try {
    Write-Host "Downloading godspeed-daemon..."
    Invoke-WebRequest -Uri $daemonUrl -OutFile $destinationPath -ErrorAction Stop
}
catch {
    Write-Host "Download failed: $_" -ForegroundColor Red
    exit
}

# Add to PATH
$persistentPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if (-not $persistentPath.Contains($targetDir)) {
    [Environment]::SetEnvironmentVariable('Path', "$persistentPath;$targetDir", 'User')
    $env:Path += ";$targetDir"
}

# Verify installation
if (-not (Test-Path $destinationPath)) {
    Write-Host "Daemon installation failed!" -ForegroundColor Red
    exit
}

# Configuration setup
$godspeedDir = Join-Path $env:USERPROFILE ".godspeed"
$servicesJson = Join-Path $godspeedDir "services.json"

if (-not (Test-Path $godspeedDir)) {
    New-Item -Path $godspeedDir -ItemType Directory | Out-Null
}

if (-not (Test-Path $servicesJson)) {
    [System.IO.File]::WriteAllText($servicesJson, '{ "services": [] }', [System.Text.UTF8Encoding]::new($false))
}

Write-Host "Daemon installation completed successfully!" -ForegroundColor Green
#endregion


#region RAG Node Installation and .env Setup
Write-Host "Installing rag-node ...." -ForegroundColor Cyan
try {
    npm install -g rag-node
} catch {
    Write-Host "rag-node installation failed: $_" -ForegroundColor Red
    exit
}

# Locate global pnpm install directory
Write-Host "Locating global rag-node installation directory..."
$pnpmPrefix = cmd /c "npm prefix -g"
$ragNodeDir = Join-Path $pnpmPrefix "node_modules\rag-node"

if (-not (Test-Path $ragNodeDir)) {
    Write-Host "rag-node installation directory not found at expected location: $ragNodeDir" -ForegroundColor Red
    exit
}

# Prompt user for GOOGLE_API_KEY with masking
Write-Host "`nEnter your GOOGLE_API_KEY for rag-node." -ForegroundColor Cyan
Write-Host "Note: This key will NOT be stored or transmitted to any Godspeed server." -ForegroundColor Yellow
Write-Host "It will remain saved ONLY in the local '.env' file on your machine." -ForegroundColor Yellow
# Write-Host "Paste your key below:" -ForegroundColor Cyan

$plainKey = Read-Host -Prompt "GOOGLE_API_KEY"

# Write to .env file
$envFilePath = Join-Path $ragNodeDir ".env"
try {
    Write-Host "Writing GOOGLE_API_KEY to .env file..."
    Set-Content -Path $envFilePath -Value "GOOGLE_API_KEY=$plainKey"
    Write-Host ".env file created at $envFilePath" -ForegroundColor Green
} catch {
    Write-Host "Failed to write .env file: $_" -ForegroundColor Red
    exit
}
#endregion

# Final checks
Write-Host "`nVerifying installations..." -ForegroundColor Cyan
Write-Host "Node.js version: $(node -v)"
Write-Host "npm version: $(npm -v)"
Write-Host "Git version: $(git --version)"
Write-Host "Godspeed CLI version: $(godspeed --version)"

Write-Host "`nInstallation complete! Please restart your terminal for all changes to take effect." -ForegroundColor Green


