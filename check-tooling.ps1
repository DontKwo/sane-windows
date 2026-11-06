<#
.SYNOPSIS
Diagnoses, installs, and updates developer CLIs and versions.
#>

[CmdletBinding()]
param(
    [switch]$Install,
    [switch]$Update,
    [string[]]$Tool = @()
)

$allTools = @(
    "git", "uv", "python", "pnpm", "npm", "cargo", "docker", "wsl"
)

# Tool package mapping for package managers and self-updaters
$toolDefinitions = @{
    "git" = @{
        WingetId     = "Git.Git"
        ScoopApp     = "git"
        ChocoPackage = "git"
        UpdateCmd    = "winget upgrade --id Git.Git -e --accept-source-agreements --accept-package-agreements"
    }
    "uv" = @{
        WingetId     = "astral-sh.uv"
        ScoopApp     = "uv"
        ChocoPackage = "uv"
        SelfUpdate   = { uv self update }
        InstallCmd   = "powershell -ExecutionPolicy ByPass -c `"irm https://astral.sh/uv/install.ps1 | iex`""
    }
    "python" = @{
        WingetId     = "Python.Python.3.12"
        ScoopApp     = "python"
        ChocoPackage = "python"
    }
    "pnpm" = @{
        WingetId     = "pnpm.pnpm"
        ScoopApp     = "pnpm"
        ChocoPackage = "pnpm"
        SelfUpdate   = {
            if (Get-Command npm -ErrorAction SilentlyContinue) {
                & npm install -g pnpm
            } elseif (Get-Command corepack -ErrorAction SilentlyContinue) {
                & corepack prepare pnpm@latest --activate
            }
        }
    }
    "npm" = @{
        WingetId     = "OpenJS.NodeJS"
        ScoopApp     = "nodejs"
        ChocoPackage = "nodejs"
        SelfUpdate   = { & npm install -g npm@latest }
    }
    "cargo" = @{
        WingetId     = "Rustlang.Rustup"
        ScoopApp     = "rustup"
        ChocoPackage = "rustup.install"
        SelfUpdate   = {
            if (Get-Command rustup -ErrorAction SilentlyContinue) {
                & rustup update
            }
        }
    }
    "docker" = @{
        WingetId     = "Docker.DockerDesktop"
        ScoopApp     = "docker"
        ChocoPackage = "docker-desktop"
    }
    "wsl" = @{
        WingetId     = "Microsoft.WSL"
        InstallCmd   = "wsl --install --no-distribution"
        SelfUpdate   = { & wsl --update }
    }
}

function Get-AvailablePackageManager {
    if (Get-Command winget -ErrorAction SilentlyContinue) { return "winget" }
    if (Get-Command scoop -ErrorAction SilentlyContinue) { return "scoop" }
    if (Get-Command choco -ErrorAction SilentlyContinue) { return "choco" }
    return $null
}

function Install-SingleTool {
    param([string]$ToolName, [string]$PackageManager)
    Write-Host "[*] Installing $ToolName..." -ForegroundColor Cyan
    $def = $toolDefinitions[$ToolName]
    if (-not $def) {
        Write-Warning "Unknown tool: $ToolName"
        return
    }

    if ($PackageManager -eq "winget" -and $def.ContainsKey("WingetId")) {
        $id = $def.WingetId
        & winget install --id $id -e --accept-source-agreements --accept-package-agreements
        return
    }

    if ($PackageManager -eq "scoop" -and $def.ContainsKey("ScoopApp")) {
        $app = $def.ScoopApp
        & scoop install $app
        return
    }

    if ($PackageManager -eq "choco" -and $def.ContainsKey("ChocoPackage")) {
        $pkg = $def.ChocoPackage
        & choco install $pkg -y
        return
    }

    if ($def.ContainsKey("InstallCmd")) {
        Invoke-Expression $def.InstallCmd
        return
    }

    Write-Warning "No supported package manager found (winget, scoop, choco) to install $ToolName."
}

function Update-SingleTool {
    param([string]$ToolName, [string]$PackageManager)
    Write-Host "[*] Updating $ToolName..." -ForegroundColor Cyan
    $def = $toolDefinitions[$ToolName]
    if (-not $def) {
        Write-Warning "Unknown tool: $ToolName"
        return
    }

    if ($def.ContainsKey("SelfUpdate")) {
        try {
            & $def.SelfUpdate
            return
        } catch {
            Write-Warning "Self-update failed for $ToolName : $_"
        }
    }

    if ($PackageManager -eq "winget" -and $def.ContainsKey("WingetId")) {
        $id = $def.WingetId
        & winget upgrade --id $id -e --accept-source-agreements --accept-package-agreements
        return
    }

    if ($PackageManager -eq "scoop" -and $def.ContainsKey("ScoopApp")) {
        $app = $def.ScoopApp
        & scoop update $app
        return
    }

    if ($PackageManager -eq "choco" -and $def.ContainsKey("ChocoPackage")) {
        $pkg = $def.ChocoPackage
        & choco upgrade $pkg -y
        return
    }

    Write-Warning "No updater available for $ToolName."
}

# Determine which tools to target
$targetTools = if ($Tool.Count -gt 0) {
    $Tool | ForEach-Object { $_.ToLower() }
} else {
    $allTools
}

$pm = Get-AvailablePackageManager

# Perform actions if requested
if ($Install) {
    foreach ($t in $targetTools) {
        $cmd = Get-Command $t -ErrorAction SilentlyContinue
        if (-not $cmd) {
            Install-SingleTool -ToolName $t -PackageManager $pm
        } else {
            Write-Host "[OK] $t is already installed." -ForegroundColor Green
        }
    }
}

if ($Update) {
    foreach ($t in $targetTools) {
        $cmd = Get-Command $t -ErrorAction SilentlyContinue
        if ($cmd) {
            Update-SingleTool -ToolName $t -PackageManager $pm
        } else {
            Write-Warning "$t is not installed. Use -Install to install it."
        }
    }
}

# Always output current diagnostics
$results = foreach ($toolName in $allTools) {
    # Check if tool is available in PATH
    $command = Get-Command $toolName -ErrorAction SilentlyContinue

    if ($command) {
        $status = "Installed"
        try {
            # Execute and extract first line of version
            $output = & $toolName --version 2>&1 | Out-String
            $version = ($output.Trim() -split '\r?\n')[0].Trim()
        } catch {
            $version = "Unknown"
        }
    } else {
        $status = "Missing"
        $version = "N/A"
    }

    [PSCustomObject]@{
        Tool    = $toolName
        Status  = $status
        Version = $version
    }
}

# Output results in aligned table
$results | Format-Table -AutoSize
