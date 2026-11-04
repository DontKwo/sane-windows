<#
.SYNOPSIS
    Cleans system temp folders, application caches, outdated app versions, and developer toolchains.

.DESCRIPTION
    Scans target locations, calculates potential disk reclamation, displays safety warnings,
    and requires explicit user confirmation before removing any files.

.PARAMETER WhatIf
    Previews cleanable items, sizes, and warnings without deleting anything.

.PARAMETER Yes
    Executes all cleaning targets without interactive confirmation.

.PARAMETER Interactive
    Prompts for individual confirmation on each cleanup target.

.PARAMETER ExportJson
    Exports cleanup targets and storage metrics to JSON without deleting.

.PARAMETER ExportPath
    File path to save the JSON audit report.

.PARAMETER MinAgeDays
    Preserves files modified within the specified number of days (default 0 deletes all cleanable files).
#>

[CmdletBinding()]
param(
    [switch]$WhatIf,
    [switch]$Yes,
    [switch]$Interactive,
    [switch]$ExportJson,
    [string]$ExportPath,
    [int]$MinAgeDays = 0
)

$ErrorActionPreference = 'Stop'

# OS platform check
if ([System.Environment]::OSVersion.Platform -ne [System.PlatformID]::Win32NT) {
    Write-Host "[ERROR] This script requires Windows." -ForegroundColor Red
    exit 1
}

function Format-ByteSize {
    [OutputType([string])]
    param(
        [long]$Bytes
    )
    # Formats raw byte count into human-readable units.
    if ($Bytes -ge 1GB) { return ("{0:N2} GB" -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ("{0:N2} MB" -f ($Bytes / 1MB)) }
    if ($Bytes -ge 1KB) { return ("{0:N2} KB" -f ($Bytes / 1KB)) }
    return ("{0} B" -f $Bytes)
}

function Get-PathSize {
    [OutputType([long])]
    param(
        [string]$Path
    )
    # Measures total byte size of existing file or folder.
    if (-not (Test-Path -Path $Path)) { return 0L }
    if (-not (Get-Item -Path $Path -Force).PSIsContainer) {
        return (Get-Item -Path $Path -Force).Length
    }
    $total = 0L
    Get-ChildItem -Path $Path -Recurse -Force -File -ErrorAction SilentlyContinue | ForEach-Object {
        $total += $_.Length
    }
    return $total
}

function Test-IsAdmin {
    [OutputType([bool])]
    param()
    # Checks whether the current PowerShell session has elevated privileges.
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-CommandExists {
    [OutputType([bool])]
    param(
        [string]$CommandName
    )
    # Checks whether an executable command exists in system PATH.
    return [bool](Get-Command -Name $CommandName -ErrorAction SilentlyContinue)
}

function Remove-FolderContentsSafely {
    [OutputType([long])]
    param(
        [string]$DirectoryPath,
        [int]$MinAgeDays = 0
    )
    # Deletes directory items while skipping locked or recent files.
    if (-not (Test-Path -Path $DirectoryPath)) { return 0L }
    $freed = 0L
    $cutoff = if ($MinAgeDays -gt 0) { (Get-Date).AddDays(-$MinAgeDays) } else { $null }
    $items = Get-ChildItem -Path $DirectoryPath -Force -ErrorAction SilentlyContinue
    foreach ($item in $items) {
        if ($cutoff -and $item.LastWriteTime -gt $cutoff) {
            continue
        }
        $itemSize = Get-PathSize -Path $item.FullName
        try {
            Remove-Item -Path $item.FullName -Recurse -Force -ErrorAction Stop
            $freed += $itemSize
        } catch {
            # File is currently open or locked by a running process.
        }
    }
    return $freed
}

function Get-OutdatedSubdirectories {
    [OutputType([System.Collections.ArrayList])]
    param(
        [string]$ParentPath,
        [string]$Filter
    )
    # Identifies older version subfolders beneath parent path.
    $results = [System.Collections.ArrayList]@()
    if (-not (Test-Path -Path $ParentPath)) { return $results }
    $dirs = @(Get-ChildItem -Path $ParentPath -Directory -Filter $Filter -ErrorAction SilentlyContinue | Sort-Object Name)
    if ($dirs.Count -gt 1) {
        for ($i = 0; $i -lt ($dirs.Count - 1); $i++) {
            $null = $results.Add($dirs[$i].FullName)
        }
    }
    return $results
}

function Invoke-CleanupItem {
    [OutputType([long])]
    param(
        [PSCustomObject]$Target,
        [bool]$ExecuteDryRun,
        [int]$MinAgeDays = 0
    )
    # Executes the specified cleanup operation or logs dry run preview.
    Write-Host "`nTarget: " -NoNewline -ForegroundColor Cyan
    Write-Host $Target.Name -ForegroundColor White
    Write-Host "Location / Command: " -NoNewline -ForegroundColor Gray
    Write-Host $Target.DisplayPath -ForegroundColor Yellow
    Write-Host "Current Size: " -NoNewline -ForegroundColor Gray
    Write-Host (Format-ByteSize -Bytes $Target.SizeBytes) -ForegroundColor Green
    Write-Host "GUARD WARNING:" -ForegroundColor Red
    Write-Host "  $($Target.Impact)" -ForegroundColor DarkYellow

    if ($ExecuteDryRun) {
        Write-Host "  [WhatIf] Skipped execution (dry run mode)." -ForegroundColor DarkGray
        return 0L
    }

    $initialSize = $Target.SizeBytes
    try {
        if ($Target.ActionType -eq "Command") {
            Write-Host "  Executing command: $($Target.ActionCommand)..." -ForegroundColor Cyan
            Invoke-Expression $Target.ActionCommand | Out-Null
            return $initialSize
        }
        if ($Target.ActionType -eq "DeleteFiles") {
            return (Remove-FolderContentsSafely -DirectoryPath $Target.TargetPath -MinAgeDays $MinAgeDays)
        }
        if ($Target.ActionType -eq "DeleteMultipleFiles") {
            $freedTotal = 0L
            foreach ($subPath in $Target.TargetPaths) {
                if (Test-Path -Path $subPath) {
                    $freedTotal += (Remove-FolderContentsSafely -DirectoryPath $subPath -MinAgeDays $MinAgeDays)
                }
            }
            return $freedTotal
        }
        if ($Target.ActionType -eq "DeletePath") {
            if (Test-Path -Path $Target.TargetPath) {
                Remove-Item -Path $Target.TargetPath -Recurse -Force -ErrorAction Stop
                return $initialSize
            }
        }
        if ($Target.ActionType -eq "DeleteMultiple") {
            $freedTotal = 0L
            foreach ($subPath in $Target.TargetPaths) {
                if (Test-Path -Path $subPath) {
                    $s = Get-PathSize -Path $subPath
                    Remove-Item -Path $subPath -Recurse -Force -ErrorAction Stop
                    $freedTotal += $s
                }
            }
            return $freedTotal
        }
    } catch {
        Write-Host "  [ERROR] $($_.Exception.Message)" -ForegroundColor Red
        return 0L
    }
    return 0L
}

function Collect-CleanupTargets {
    [OutputType([System.Collections.ArrayList])]
    param()
    # Scans and assembles candidate cleanup operations.
    $targets = [System.Collections.ArrayList]@()

    # PSReadLine Command History
    if (Get-Command Get-PSReadLineOption -ErrorAction SilentlyContinue) {
        $historyPath = (Get-PSReadLineOption).HistorySavePath
        if (Test-Path -Path $historyPath) {
            $size = Get-PathSize -Path $historyPath
            if ($size -gt 0) {
                $null = $targets.Add([PSCustomObject]@{
                    Id            = "psreadline-history"
                    Name          = "PSReadLine Command History"
                    DisplayPath   = $historyPath
                    TargetPath    = $historyPath
                    ActionType    = "DeletePath"
                    SizeBytes     = $size
                    Impact        = "PowerShell command history will be deleted. Past commands will not be available for autocompletion."
                })
            }
        }
    }

    # User Temp
    $userTemp = $env:TEMP
    if (Test-Path -Path $userTemp) {
        $size = Get-PathSize -Path $userTemp
        if ($size -gt 0) {
            $null = $targets.Add([PSCustomObject]@{
                Id            = "user-temp"
                Name          = "User Temporary Files"
                DisplayPath   = $userTemp
                TargetPath    = $userTemp
                ActionType    = "DeleteFiles"
                SizeBytes     = $size
                Impact        = "Temporary working files and setup payloads will be deleted. Open programs with unsaved temporary files might lose recovery buffers. Locked files in use are skipped."
            })
        }
    }

    # Chrome Cache
    $chromeCache = Join-Path $env:LOCALAPPDATA "Google\Chrome\User Data\Default\Cache"
    if (Test-Path -Path $chromeCache) {
        if (Get-Process -Name chrome -ErrorAction SilentlyContinue) {
            Write-Warning "Chrome is currently running. Skipping Chrome cache cleanup."
        } else {
            $size = Get-PathSize -Path $chromeCache
            if ($size -gt 0) {
                $null = $targets.Add([PSCustomObject]@{
                    Id            = "chrome-cache"
                    Name          = "Google Chrome Cache"
                    DisplayPath   = $chromeCache
                    TargetPath    = $chromeCache
                    ActionType    = "DeleteFiles"
                    SizeBytes     = $size
                    Impact        = "Browser cache will be deleted. Websites may take slightly longer to load initially."
                })
            }
        }
    }

    # Edge Cache
    $edgeCache = Join-Path $env:LOCALAPPDATA "Microsoft\Edge\User Data\Default\Cache"
    if (Test-Path -Path $edgeCache) {
        if (Get-Process -Name msedge -ErrorAction SilentlyContinue) {
            Write-Warning "Edge is currently running. Skipping Edge cache cleanup."
        } else {
            $size = Get-PathSize -Path $edgeCache
            if ($size -gt 0) {
                $null = $targets.Add([PSCustomObject]@{
                    Id            = "edge-cache"
                    Name          = "Microsoft Edge Cache"
                    DisplayPath   = $edgeCache
                    TargetPath    = $edgeCache
                    ActionType    = "DeleteFiles"
                    SizeBytes     = $size
                    Impact        = "Browser cache will be deleted. Websites may take slightly longer to load initially."
                })
            }
        }
    }

    # Firefox Cache
    $firefoxCache = Join-Path $env:LOCALAPPDATA "Mozilla\Firefox\Profiles"
    if (Test-Path -Path $firefoxCache) {
        if (Get-Process -Name firefox -ErrorAction SilentlyContinue) {
            Write-Warning "Firefox is currently running. Skipping Firefox cache cleanup."
        } else {
            $size = Get-PathSize -Path $firefoxCache
            if ($size -gt 0) {
                $null = $targets.Add([PSCustomObject]@{
                    Id            = "firefox-cache"
                    Name          = "Mozilla Firefox Cache"
                    DisplayPath   = $firefoxCache
                    TargetPath    = $firefoxCache
                    ActionType    = "DeleteFiles"
                    SizeBytes     = $size
                    Impact        = "Browser cache will be deleted. Websites may take slightly longer to load initially."
                })
            }
        }
    }

    # pnpm Cache
    if (Test-CommandExists -CommandName "pnpm") {
        $null = $targets.Add([PSCustomObject]@{
            Id            = "pnpm-store-prune"
            Name          = "pnpm Store Prune"
            DisplayPath   = "pnpm store prune"
            ActionType    = "Command"
            ActionCommand = "pnpm store prune"
            TargetPath    = ""
            SizeBytes     = 0L
            Impact        = "Unused packages from the global pnpm content-addressable store will be pruned."
        })
    }

    # yarn Cache
    if (Test-CommandExists -CommandName "yarn") {
        $null = $targets.Add([PSCustomObject]@{
            Id            = "yarn-cache-clean"
            Name          = "Yarn Package Cache"
            DisplayPath   = "yarn cache clean --all"
            ActionType    = "Command"
            ActionCommand = "yarn cache clean --all"
            TargetPath    = ""
            SizeBytes     = 0L
            Impact        = "Cached yarn packages will be removed. Subsequent yarn installs will re-download archives."
        })
    }

    # uv Python Cache
    $uvCachePath = Join-Path $env:LOCALAPPDATA "uv\cache"
    if ((Test-CommandExists -CommandName "uv") -or (Test-Path -Path $uvCachePath)) {
        $size = Get-PathSize -Path $uvCachePath
        if ($size -gt 0) {
            $hasUv = Test-CommandExists -CommandName "uv"
            $null = $targets.Add([PSCustomObject]@{
                Id            = "uv-cache"
                Name          = "uv Python Package Cache"
                DisplayPath   = if ($hasUv) { "uv cache clean" } else { $uvCachePath }
                ActionType    = if ($hasUv) { "Command" } else { "DeletePath" }
                ActionCommand = "uv cache clean"
                TargetPath    = $uvCachePath
                SizeBytes     = $size
                Impact        = "Cached Python wheels and source tarballs will be removed. Subsequent package builds will re-download archives from PyPI."
            })
        }
    }

    # pip Cache
    $pipCachePath = Join-Path $env:LOCALAPPDATA "pip\cache"
    if ((Test-CommandExists -CommandName "pip") -or (Test-Path -Path $pipCachePath)) {
        $size = Get-PathSize -Path $pipCachePath
        if ($size -gt 0) {
            $hasPip = Test-CommandExists -CommandName "pip"
            $null = $targets.Add([PSCustomObject]@{
                Id            = "pip-cache"
                Name          = "pip Download Cache"
                DisplayPath   = if ($hasPip) { "pip cache purge" } else { $pipCachePath }
                ActionType    = if ($hasPip) { "Command" } else { "DeletePath" }
                ActionCommand = "pip cache purge"
                TargetPath    = $pipCachePath
                SizeBytes     = $size
                Impact        = "Cached wheel downloads will be removed. Subsequent pip installations will download files directly from the network."
            })
        }
    }

    # npm Cache
    $npmCachePath = Join-Path $env:LOCALAPPDATA "npm-cache"
    if ((Test-CommandExists -CommandName "npm") -or (Test-Path -Path $npmCachePath)) {
        $size = Get-PathSize -Path $npmCachePath
        if ($size -gt 0) {
            $hasNpm = Test-CommandExists -CommandName "npm"
            $null = $targets.Add([PSCustomObject]@{
                Id            = "npm-cache"
                Name          = "npm Package Cache"
                DisplayPath   = if ($hasNpm) { "npm cache clean --force" } else { $npmCachePath }
                ActionType    = if ($hasNpm) { "Command" } else { "DeletePath" }
                ActionCommand = "npm cache clean --force"
                TargetPath    = $npmCachePath
                SizeBytes     = $size
                Impact        = "Cached npm tarball archives will be deleted. Future npm installs will pull tarballs from the npm registry."
            })
        }
    }

    # Cargo Registry Cache
    $cargoCachePath = Join-Path $env:USERPROFILE ".cargo\registry\cache"
    if (Test-Path -Path $cargoCachePath) {
        $size = Get-PathSize -Path $cargoCachePath
        if ($size -gt 0) {
            $null = $targets.Add([PSCustomObject]@{
                Id            = "cargo-cache"
                Name          = "Cargo Package Registry Cache"
                DisplayPath   = $cargoCachePath
                TargetPath    = $cargoCachePath
                ActionType    = "DeletePath"
                SizeBytes     = $size
                Impact        = "Downloaded crates.io archives will be deleted. Future cargo builds will re-download packages from the network."
            })
        }
    }

    # NuGet Cache
    $nugetCachePath = Join-Path $env:USERPROFILE ".nuget\packages"
    if ((Test-CommandExists -CommandName "dotnet") -or (Test-Path -Path $nugetCachePath)) {
        $size = Get-PathSize -Path $nugetCachePath
        if ($size -gt 0) {
            $hasDotnet = Test-CommandExists -CommandName "dotnet"
            $null = $targets.Add([PSCustomObject]@{
                Id            = "nuget-cache"
                Name          = "NuGet HTTP Cache"
                DisplayPath   = if ($hasDotnet) { "dotnet nuget locals http-cache --clear" } else { $nugetCachePath }
                ActionType    = if ($hasDotnet) { "Command" } else { "DeletePath" }
                ActionCommand = "dotnet nuget locals http-cache --clear"
                TargetPath    = $nugetCachePath
                SizeBytes     = $size
                Impact        = "Cached NuGet packages will be deleted. Future .NET builds will pull packages from the NuGet registry."
            })
        }
    }

    # vcpkg Cache
    $vcpkgCachePath = Join-Path $env:LOCALAPPDATA "vcpkg\archives"
    if (Test-Path -Path $vcpkgCachePath) {
        $size = Get-PathSize -Path $vcpkgCachePath
        if ($size -gt 0) {
            $null = $targets.Add([PSCustomObject]@{
                Id            = "vcpkg-cache"
                Name          = "vcpkg Downloads Cache"
                DisplayPath   = $vcpkgCachePath
                TargetPath    = $vcpkgCachePath
                ActionType    = "DeletePath"
                SizeBytes     = $size
                Impact        = "Downloaded vcpkg archives will be deleted. Future vcpkg installs will re-download source archives."
            })
        }
    }

    # Gradle Caches
    $gradleCachePath = Join-Path $env:USERPROFILE ".gradle\caches"
    if (Test-Path -Path $gradleCachePath) {
        $size = Get-PathSize -Path $gradleCachePath
        if ($size -gt 0) {
            $null = $targets.Add([PSCustomObject]@{
                Id            = "gradle-cache"
                Name          = "Gradle Caches"
                DisplayPath   = $gradleCachePath
                TargetPath    = $gradleCachePath
                ActionType    = "DeletePath"
                SizeBytes     = $size
                Impact        = "Cached Gradle dependencies and build artifacts will be deleted. Future Gradle builds will be slower and re-download dependencies."
            })
        }
    }

    # Go Build and Module Cache
    if (Test-CommandExists -CommandName "go") {
        $goCache = (go env GOCACHE 2>$null)
        $goModCache = (go env GOMODCACHE 2>$null)
        $size = 0L
        if ($goCache -and (Test-Path -Path $goCache)) { $size += Get-PathSize -Path $goCache }
        if ($goModCache -and (Test-Path -Path $goModCache)) { $size += Get-PathSize -Path $goModCache }

        if ($size -gt 0) {
            $null = $targets.Add([PSCustomObject]@{
                Id            = "go-cache"
                Name          = "Go Build and Module Cache"
                DisplayPath   = "go clean -cache -modcache"
                ActionType    = "Command"
                ActionCommand = "go clean -cache -modcache"
                TargetPath    = ""
                SizeBytes     = $size
                Impact        = "Go build artifacts and downloaded modules will be deleted. Next build will re-download modules and recompile."
            })
        }
    } else {
        $goModCacheFallback = Join-Path $env:USERPROFILE "go\pkg\mod\cache\download"
        if (Test-Path -Path $goModCacheFallback) {
            $size = Get-PathSize -Path $goModCacheFallback
            if ($size -gt 0) {
                $null = $targets.Add([PSCustomObject]@{
                    Id            = "go-mod-cache"
                    Name          = "Go Module Download Cache"
                    DisplayPath   = $goModCacheFallback
                    TargetPath    = $goModCacheFallback
                    ActionType    = "DeletePath"
                    SizeBytes     = $size
                    Impact        = "Downloaded Go modules will be deleted. Next build will re-download modules."
                })
            }
        }
    }

    # Visual Studio Installer Cache
    $vsCachePath = Join-Path $env:ProgramData "Microsoft\VisualStudio\Packages"
    if (Test-Path -Path $vsCachePath) {
        $size = Get-PathSize -Path $vsCachePath
        if ($size -gt 0) {
            $null = $targets.Add([PSCustomObject]@{
                Id            = "vs-installer-cache"
                Name          = "Visual Studio Installer Cache"
                DisplayPath   = $vsCachePath
                TargetPath    = $vsCachePath
                ActionType    = "DeletePath"
                SizeBytes     = $size
                Impact        = "Visual Studio setup packages will be removed. Subsequent installer runs will re-download necessary payloads."
            })
        }
    }

    # MSBuild Cache
    $msbuildCachePath = Join-Path $env:LOCALAPPDATA "Microsoft\MSBuild"
    if (Test-Path -Path $msbuildCachePath) {
        $size = Get-PathSize -Path $msbuildCachePath
        if ($size -gt 0) {
            $null = $targets.Add([PSCustomObject]@{
                Id            = "msbuild-cache"
                Name          = "MSBuild Temporary Cache"
                DisplayPath   = $msbuildCachePath
                TargetPath    = $msbuildCachePath
                ActionType    = "DeletePath"
                SizeBytes     = $size
                Impact        = "MSBuild temporary cache and setup packages will be removed. Subsequent builds will regenerate cached data."
            })
        }
    }

    # Rust Nightly Toolchain
    if (Test-CommandExists -CommandName "rustup") {
        $toolchains = @(rustup toolchain list 2>$null)
        if ($toolchains -match "nightly") {
            $rustupPath = Join-Path $env:USERPROFILE ".rustup\toolchains"
            $nightlyDir = Get-ChildItem -Path $rustupPath -Directory -Filter "*nightly*" -ErrorAction SilentlyContinue | Select-Object -First 1
            $size = if ($nightlyDir) { Get-PathSize -Path $nightlyDir.FullName } else { 1500MB }
            $null = $targets.Add([PSCustomObject]@{
                Id            = "rust-nightly"
                Name          = "Rust Nightly Toolchain"
                DisplayPath   = "rustup toolchain uninstall nightly"
                ActionType    = "Command"
                ActionCommand = "rustup toolchain uninstall nightly"
                TargetPath    = if ($nightlyDir) { $nightlyDir.FullName } else { "" }
                SizeBytes     = $size
                Impact        = "The complete nightly compiler and local HTML documentation will be uninstalled. Projects requiring nightly compiler features will fail until re-installed."
            })
        }
    }

    # Raspberry Pi Imager Cache
    $rpiCache = Join-Path $env:LOCALAPPDATA "Raspberry Pi\Imager\cache"
    if (Test-Path -Path $rpiCache) {
        $size = Get-PathSize -Path $rpiCache
        if ($size -gt 0) {
            $null = $targets.Add([PSCustomObject]@{
                Id            = "rpi-cache"
                Name          = "Raspberry Pi Imager OS Cache"
                DisplayPath   = $rpiCache
                TargetPath    = $rpiCache
                ActionType    = "DeleteFiles"
                SizeBytes     = $size
                Impact        = "Cached operating system disk images will be deleted. Flashing the same OS again will require a fresh download."
            })
        }
    }

    # VS Code Extension VSIX Cache
    $vsixCache = Join-Path $env:APPDATA "Code\CachedExtensionVSIXs"
    if (Test-Path -Path $vsixCache) {
        $size = Get-PathSize -Path $vsixCache
        if ($size -gt 0) {
            $null = $targets.Add([PSCustomObject]@{
                Id            = "vscode-vsix-cache"
                Name          = "VS Code Cached Extension Archives"
                DisplayPath   = $vsixCache
                TargetPath    = $vsixCache
                ActionType    = "DeleteFiles"
                SizeBytes     = $size
                Impact        = "Staged .vsix extension installer packages will be deleted. Installed extensions continue operating normally."
            })
        }
    }

    # Windows Crash Dumps
    $crashDumps = @(
        (Join-Path $env:LOCALAPPDATA "CrashDumps"),
        "C:\Windows\Minidump"
    )
    $validCrashDumps = $crashDumps | Where-Object { Test-Path -Path $_ }
    if ($validCrashDumps.Count -gt 0) {
        $size = 0L
        foreach ($p in $validCrashDumps) { $size += Get-PathSize -Path $p }
        if ($size -gt 0) {
            $null = $targets.Add([PSCustomObject]@{
                Id            = "crash-dumps"
                Name          = "Windows Crash Dumps"
                DisplayPath   = ($validCrashDumps -join ", ")
                TargetPaths   = $validCrashDumps
                ActionType    = "DeleteMultipleFiles"
                SizeBytes     = $size
                Impact        = "Post-mortem memory dump files (.dmp) will be deleted. Past application and system crash state records cannot be recovered."
            })
        }
    }

    # Autodesk Error Reports
    $autodeskCer = Join-Path $env:LOCALAPPDATA "Autodesk\CER"
    if (Test-Path -Path $autodeskCer) {
        $size = Get-PathSize -Path $autodeskCer
        if ($size -gt 0) {
            $null = $targets.Add([PSCustomObject]@{
                Id            = "autodesk-cer"
                Name          = "Autodesk Crash Reports"
                DisplayPath   = $autodeskCer
                TargetPath    = $autodeskCer
                ActionType    = "DeleteFiles"
                SizeBytes     = $size
                Impact        = "Autodesk diagnostic crash logs and report files will be deleted."
            })
        }
    }

    # Outdated Claude Desktop versions
    $claudeAppDir = Join-Path $env:LOCALAPPDATA "AnthropicClaude"
    $oldClaudeDirs = Get-OutdatedSubdirectories -ParentPath $claudeAppDir -Filter "app-*"
    if ($oldClaudeDirs.Count -gt 0) {
        $totalSize = 0L
        foreach ($d in $oldClaudeDirs) { $totalSize += Get-PathSize -Path $d }
        if ($totalSize -gt 0) {
            $null = $targets.Add([PSCustomObject]@{
                Id            = "old-claude"
                Name          = "Outdated Claude Desktop Builds"
                DisplayPath   = ($oldClaudeDirs -join "; ")
                TargetPaths   = $oldClaudeDirs
                ActionType    = "DeleteMultiple"
                SizeBytes     = $totalSize
                Impact        = "Superseded application version directories left by the updater will be deleted. The newest active version is preserved."
            })
        }
    }

    # Outdated MathWorks ServiceHost versions
    $mathworksHostDir = Join-Path $env:LOCALAPPDATA "MathWorks\ServiceHost"
    $oldMathWorksDirs = Get-OutdatedSubdirectories -ParentPath $mathworksHostDir -Filter "v*"
    if ($oldMathWorksDirs.Count -gt 0) {
        $totalSize = 0L
        foreach ($d in $oldMathWorksDirs) { $totalSize += Get-PathSize -Path $d }
        if ($totalSize -gt 0) {
            $null = $targets.Add([PSCustomObject]@{
                Id            = "old-mathworks"
                Name          = "Outdated MathWorks ServiceHost Builds"
                DisplayPath   = ($oldMathWorksDirs -join "; ")
                TargetPaths   = $oldMathWorksDirs
                ActionType    = "DeleteMultiple"
                SizeBytes     = $totalSize
                Impact        = "Superseded ServiceHost versions will be deleted. The latest installed version is preserved."
            })
        }
    }

    # Claude Subagent Workflows
    $claudeProjectsDir = Join-Path $env:USERPROFILE ".claude\projects"
    if (Test-Path -Path $claudeProjectsDir) {
        $workflowDirs = [System.Collections.ArrayList]@()
        $workflowSize = 0L
        Get-ChildItem -Path $claudeProjectsDir -Directory -Recurse -Filter "workflows" -ErrorAction SilentlyContinue | ForEach-Object {
            $s = Get-PathSize -Path $_.FullName
            if ($s -gt 0) {
                $null = $workflowDirs.Add($_.FullName)
                $workflowSize += $s
            }
        }
        if ($workflowSize -gt 0) {
            $null = $targets.Add([PSCustomObject]@{
                Id            = "claude-workflows"
                Name          = "Claude Project Subagent Workflows"
                DisplayPath   = ($workflowDirs -join "; ")
                TargetPaths   = $workflowDirs
                ActionType    = "DeleteMultiple"
                SizeBytes     = $workflowSize
                Impact        = "Historical subagent run output and transcript artifacts will be deleted. Completed session logs cannot be inspected locally."
            })
        }
    }

    # rembg AI Models
    $rembgModels = Join-Path $env:USERPROFILE ".rembg\models"
    if (Test-Path -Path $rembgModels) {
        $size = Get-PathSize -Path $rembgModels
        if ($size -gt 0) {
            $null = $targets.Add([PSCustomObject]@{
                Id            = "rembg-models"
                Name          = "rembg Background Removal Models"
                DisplayPath   = $rembgModels
                TargetPath    = $rembgModels
                ActionType    = "DeleteFiles"
                SizeBytes     = $size
                Impact        = "Downloaded ONNX model weights will be deleted. Rembg will re-download needed model files over the internet on subsequent runs."
            })
        }
    }

    # Docker System Prune
    if (Test-CommandExists -CommandName "docker") {
        $null = $targets.Add([PSCustomObject]@{
            Id            = "docker-prune"
            Name          = "Docker System Prune"
            DisplayPath   = "docker system prune -a --volumes -f"
            ActionType    = "Command"
            ActionCommand = "docker system prune -a --volumes -f"
            TargetPath    = ""
            SizeBytes     = 0L
            Impact        = "All stopped containers, dangling images, unused networks, and build caches will be deleted permanently. Uncommitted container data is lost."
        })
    }

    # Windows Update Download Payload
    if (Test-IsAdmin) {
        $wuDownloadPath = Join-Path $env:SystemRoot "SoftwareDistribution\Download"
        if (Test-Path -Path $wuDownloadPath) {
            $size = Get-PathSize -Path $wuDownloadPath
            if ($size -gt 0) {
                $null = $targets.Add([PSCustomObject]@{
                    Id            = "wu-download"
                    Name          = "Windows Update Downloads"
                    DisplayPath   = $wuDownloadPath
                    TargetPath    = $wuDownloadPath
                    ActionType    = "DeleteFiles"
                    SizeBytes     = $size
                    Impact        = "Downloaded Windows Update installation files will be deleted (requires admin). Interrupted or pending updates will re-download necessary payloads."
                })
            }
        }
    }

    # WSL2 Shutdown
    if (Test-CommandExists -CommandName "wsl") {
        $null = $targets.Add([PSCustomObject]@{
            Id            = "wsl-shutdown"
            Name          = "WSL2 Virtual Machine Shutdown"
            DisplayPath   = "wsl --shutdown"
            ActionType    = "Command"
            ActionCommand = "wsl --shutdown"
            TargetPath    = ""
            SizeBytes     = 0L
            Impact        = "All running WSL2 distributions will be terminated immediately. Unsaved work in Linux terminal sessions will be lost."
        })
    }

    return $targets
}

function Main {
    [OutputType([void])]
    param()
    # Main orchestrator for storage analysis and interactive deletion.
    if (-not $ExportJson) {
        Write-Host "`n=================================================================" -ForegroundColor Cyan
        Write-Host " Sane Windows: Storage & Cache Cleanup" -ForegroundColor Cyan
        Write-Host "=================================================================`n" -ForegroundColor Cyan
    }

    $driveBefore = Get-PSDrive -Name C -ErrorAction SilentlyContinue
    $targets = Collect-CleanupTargets

    if ($ExportJson) {
        $totalBytes = 0L
        $targetList = [System.Collections.ArrayList]@()
        foreach ($t in $targets) {
            if ($t.SizeBytes -gt 0) { $totalBytes += $t.SizeBytes }
            $null = $targetList.Add([PSCustomObject]@{
                Id          = $t.Id
                Name        = $t.Name
                DisplayPath = $t.DisplayPath
                ActionType  = $t.ActionType
                SizeBytes   = $t.SizeBytes
            })
        }

        $hostName = if ($env:COMPUTERNAME) { $env:COMPUTERNAME } else { [System.Environment]::MachineName }
        $report = [ordered]@{
            Timestamp             = (Get-Date).ToString("o")
            ComputerName          = $hostName
            TotalReclaimableBytes = $totalBytes
            FormattedTotalSize    = (Format-ByteSize -Bytes $totalBytes)
            Targets               = @($targetList)
        }
        $json = $report | ConvertTo-Json -Depth 5
        if (-not [string]::IsNullOrWhiteSpace($ExportPath)) {
            $dir = Split-Path -Parent $ExportPath
            if ($dir -and -not (Test-Path -Path $dir)) {
                $null = New-Item -ItemType Directory -Path $dir -Force
            }
            [System.IO.File]::WriteAllText($ExportPath, $json, [System.Text.Encoding]::UTF8)
        } else {
            Write-Output $json
        }
        return
    }

    if ($targets.Count -eq 0) {
        Write-Host "No cleanable targets found. Storage is clean." -ForegroundColor Green
        return
    }

    Write-Host ("Found {0} cleanable target(s):`n" -f $targets.Count) -ForegroundColor White

    $index = 1
    $totalReclaimable = 0L
    foreach ($t in $targets) {
        $sizeStr = if ($t.SizeBytes -gt 0) { Format-ByteSize -Bytes $t.SizeBytes } else { "Dynamic" }
        if ($t.SizeBytes -gt 0) { $totalReclaimable += $t.SizeBytes }
        Write-Host (" [{0}] {1,-36} : {2,9}" -f $index, $t.Name, $sizeStr) -ForegroundColor Yellow
        $index++
    }

    Write-Host ("`nTotal measured reclaimable space: {0}`n" -f (Format-ByteSize -Bytes $totalReclaimable)) -ForegroundColor Green

    if ($WhatIf) {
        Write-Host "Running in WhatIf (dry run) mode. Reviewing each item:" -ForegroundColor Magenta
        foreach ($t in $targets) {
            $null = Invoke-CleanupItem -Target $t -ExecuteDryRun $true -MinAgeDays $MinAgeDays
        }
        Write-Host "`nDry run complete. No files were modified or deleted." -ForegroundColor Green
        return
    }

    $confirmedTargets = [System.Collections.ArrayList]@()

    if ($Yes) {
        Write-Host "Running with -Yes switch. Proceeding with all items automatically." -ForegroundColor Cyan
        $confirmedTargets = $targets
    } elseif ($Interactive) {
        foreach ($t in $targets) {
            $sizeStr = if ($t.SizeBytes -gt 0) { Format-ByteSize -Bytes $t.SizeBytes } else { "Dynamic" }
            Write-Host "`n-----------------------------------------------------------------" -ForegroundColor Gray
            Write-Host "Target: $($t.Name) ($sizeStr)" -ForegroundColor Cyan
            Write-Host "Path:   $($t.DisplayPath)" -ForegroundColor White
            Write-Host "GUARD WARNING:" -ForegroundColor Red
            Write-Host "  $($t.Impact)" -ForegroundColor DarkYellow
            Write-Host "-----------------------------------------------------------------" -ForegroundColor Gray
            
            $answer = Read-Host "Do you agree to proceed with this deletion? [y/N]"
            if ($answer -match "^[Yy]$") {
                $null = $confirmedTargets.Add($t)
            } else {
                Write-Host "Skipped." -ForegroundColor DarkGray
            }
        }
    } else {
        Write-Host "Confirmation required before proceeding." -ForegroundColor Yellow
        Write-Host "Options:" -ForegroundColor White
        Write-Host "  [Y] Yes          - Clean all detected items" -ForegroundColor White
        Write-Host "  [I] Interactive  - Review and confirm each item individually" -ForegroundColor White
        Write-Host "  [N] No           - Abort without making any changes`n" -ForegroundColor White

        $choice = Read-Host "Select an option [Y/I/N] (default: N)"
        if ($choice -match "^[Yy]$") {
            $confirmedTargets = $targets
        } elseif ($choice -match "^[Ii]$") {
            foreach ($t in $targets) {
                $sizeStr = if ($t.SizeBytes -gt 0) { Format-ByteSize -Bytes $t.SizeBytes } else { "Dynamic" }
                Write-Host "`n-----------------------------------------------------------------" -ForegroundColor Gray
                Write-Host "Target: $($t.Name) ($sizeStr)" -ForegroundColor Cyan
                Write-Host "Path:   $($t.DisplayPath)" -ForegroundColor White
                Write-Host "GUARD WARNING:" -ForegroundColor Red
                Write-Host "  $($t.Impact)" -ForegroundColor DarkYellow
                Write-Host "-----------------------------------------------------------------" -ForegroundColor Gray

                $answer = Read-Host "Do you agree to proceed with this deletion? [y/N]"
                if ($answer -match "^[Yy]$") {
                    $null = $confirmedTargets.Add($t)
                } else {
                    Write-Host "Skipped." -ForegroundColor DarkGray
                }
            }
        } else {
            Write-Host "Aborted by user. No files were deleted." -ForegroundColor Yellow
            return
        }
    }

    if ($confirmedTargets.Count -eq 0) {
        Write-Host "`nNo targets selected for cleaning. Exiting." -ForegroundColor Yellow
        return
    }

    Write-Host "`nExecuting cleanup on confirmed targets..." -ForegroundColor Cyan
    $totalReclaimed = 0L
    foreach ($t in $confirmedTargets) {
        $freed = Invoke-CleanupItem -Target $t -ExecuteDryRun $false -MinAgeDays $MinAgeDays
        $totalReclaimed += $freed
    }

    $driveAfter = Get-PSDrive -Name C -ErrorAction SilentlyContinue
    Write-Host "`n=================================================================" -ForegroundColor Green
    Write-Host " Cleanup Completed" -ForegroundColor Green
    Write-Host "=================================================================" -ForegroundColor Green
    if ($driveBefore -and $driveAfter) {
        $actualDiff = $driveAfter.Free - $driveBefore.Free
        if ($actualDiff -gt 0) {
            Write-Host (" Drive C: Free space gained: {0}" -f (Format-ByteSize -Bytes $actualDiff)) -ForegroundColor Green
        }
        Write-Host (" Current Drive C: Free space: {0}" -f (Format-ByteSize -Bytes $driveAfter.Free)) -ForegroundColor White
    } else {
        Write-Host (" Reclaimed space: {0}" -f (Format-ByteSize -Bytes $totalReclaimed)) -ForegroundColor Green
    }
    Write-Host "=================================================================`n" -ForegroundColor Green
}

Main
