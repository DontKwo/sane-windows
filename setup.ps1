<#
.SYNOPSIS
    Sane Windows: Windows QOL, Privacy, Performance, and Developer Ergonomics.

.DESCRIPTION
    Applies configuration from config.yaml, takes snapshots before modifying anything,
    only applies changes if the value would be different, and supports full rollbacks.

.PARAMETER ConfigPath
    Path to the YAML configuration file (default: .\config.yaml).

.PARAMETER Revert
    Reverts system settings to a previously saved snapshot.

.PARAMETER SnapshotPath
    Path to a specific snapshot JSON file to revert to (default: snapshots\latest.json).

.PARAMETER ListSnapshots
    Lists all saved snapshot files.

.PARAMETER NoExplorerRestart
    Prevents restarting File Explorer after Explorer/Taskbar changes.
#>

[CmdletBinding()]
param(
    [string]$ConfigPath,
    [switch]$Revert,
    [string]$SnapshotPath,
    [switch]$ListSnapshots,
    [switch]$NoExplorerRestart,
    [switch]$VerboseOutput,
    [switch]$Yes,
    [switch]$WhatIf,
    [switch]$ExportConfig,
    [string]$ExportPath
)

$ErrorActionPreference = 'Stop'

# --- OS Platform Guard ---
if ([System.Environment]::OSVersion.Platform -ne [System.PlatformID]::Win32NT) {
    Write-Host "`n[ERROR] Sane Windows is designed exclusively for Windows environments." -ForegroundColor Red
    Write-Host "Detected OS Platform: $([System.Environment]::OSVersion.Platform)" -ForegroundColor Yellow
    Write-Host "Execution aborted. Windows tweaks cannot be applied to Linux/macOS.`n" -ForegroundColor Yellow
    exit 1
}

# --- Windows Version Detection ---
$script:WinBuild = [System.Environment]::OSVersion.Version.Build
$script:IsWindows11 = ($script:WinBuild -ge 22000)
$script:IsWindows11_23H2 = ($script:WinBuild -ge 22631)

$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Definition }
if (-not $ScriptDir) { $ScriptDir = (Get-Location).Path }
if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $ConfigPath = Join-Path $ScriptDir "config.yaml"
}

$script:changedList = [System.Collections.ArrayList]@()

# UI Colors & Formatting
function Write-Header {
    param([string]$Text)
    Write-Host "`n=================================================================" -ForegroundColor Cyan
    Write-Host " $Text" -ForegroundColor Cyan
    Write-Host "=================================================================`n" -ForegroundColor Cyan
}

function Write-Step {
    param([string]$Text)
    if ($VerboseOutput) {
        Write-Host "[+] $Text" -ForegroundColor Yellow
    }
}

function Write-Changed {
    param([string]$Category, [string]$Setting, [string]$OldVal, [string]$NewVal)
    $null = $script:changedList.Add([PSCustomObject]@{
        Category = $Category
        Setting  = $Setting
        OldValue = $OldVal
        NewValue = $NewVal
    })
    Write-Host "  [CHANGED] " -ForegroundColor Green -NoNewline
    Write-Host "$Category." -ForegroundColor Cyan -NoNewline
    Write-Host "$Setting" -ForegroundColor White -NoNewline
    Write-Host " : " -ForegroundColor Gray -NoNewline
    Write-Host "$OldVal" -ForegroundColor DarkGray -NoNewline
    Write-Host " -> " -ForegroundColor Gray -NoNewline
    Write-Host "$NewVal" -ForegroundColor Green
}

function Write-Unchanged {
    param([string]$Setting, [string]$Val)
    # Intentionally silent by default; only show if -VerboseOutput is passed
    if ($VerboseOutput) {
        Write-Host "    [UNCHANGED] $Setting : already $Val" -ForegroundColor DarkGray
    }
}

function Write-Skipped {
    param([string]$Setting, [string]$Reason)
    if ($VerboseOutput) {
        Write-Host "    [SKIPPED]   $Setting : $Reason" -ForegroundColor DarkYellow
    }
}

function Write-Info {
    param([string]$Text)
    if ($VerboseOutput) {
        Write-Host "    [i] $Text" -ForegroundColor Gray
    }
}

function Write-Success {
    param([string]$Text)
    Write-Host "    [OK] $Text" -ForegroundColor Green
}

function Write-Warn {
    param([string]$Text)
    Write-Host "    [!] $Text" -ForegroundColor Yellow
}

# --- Elevation Check ---
function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# --- Lightweight Pure-PowerShell YAML Parser ---
function ConvertFrom-SimpleYaml {
    param([string]$YamlContent)
    $lines = $YamlContent -split "`r?`n"
    $root = @{}
    $currentSection = $null
    $currentListKey = $null

    foreach ($rawLine in $lines) {
        $line = $rawLine
        if ($line -match '^\s*#') { continue }
        if ($line.Trim().Length -eq 0) { continue }

        # Section header: "section:"
        if ($line -match '^([a-zA-Z0-9_-]+):\s*$') {
            $sectionName = $matches[1]
            $root[$sectionName] = @{}
            $currentSection = $sectionName
            $currentListKey = $null
            continue
        }

        # List item: "  - value"
        if ($line -match '^\s+-\s+(.+)$') {
            $val = $matches[1].Trim().Trim('"').Trim("'")
            if ($currentSection -and $currentListKey) {
                $root[$currentSection][$currentListKey] += @($val)
            }
            continue
        }

        # Key-Value: "  key: value"
        if ($line -match '^\s+([a-zA-Z0-9_-]+):\s*(.*)$') {
            $key = $matches[1]
            $valStr = $matches[2].Trim()
            $currentListKey = $null

            if ($valStr -eq '') {
                $currentListKey = $key
                $root[$currentSection][$key] = @()
            } else {
                $val = $valStr
                if ($valStr -ieq 'true') { $val = $true }
                elseif ($valStr -ieq 'false') { $val = $false }
                elseif ($valStr -match '^-?\d+$') { $val = [int]$valStr }
                else { $val = $valStr.Trim('"').Trim("'") }
                $root[$currentSection][$key] = $val
            }
            continue
        }
    }
    return $root
}

# --- Safe Registry Access ---
function Get-RegValSafe {
    param([string]$KeyPath, [string]$ValName)
    if (-not (Test-Path -LiteralPath $KeyPath)) { return $null }
    try {
        $item = Get-ItemProperty -LiteralPath $KeyPath -Name $ValName -ErrorAction SilentlyContinue
        if ($null -ne $item -and $null -ne $item.$ValName) {
            return $item.$ValName
        }
    } catch { }
    return $null
}

function Set-RegValSafe {
    param([string]$KeyPath, [string]$ValName, $Value, [string]$Type = "DWord")
    if (-not (Test-Path -LiteralPath $KeyPath)) {
        if ($KeyPath -like "HKCU:\*") {
            $sub = $KeyPath.Substring(5)
            [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($sub) | Out-Null
        } elseif ($KeyPath -like "HKLM:\*") {
            $sub = $KeyPath.Substring(5)
            [Microsoft.Win32.Registry]::LocalMachine.CreateSubKey($sub) | Out-Null
        } else {
            New-Item -Path $KeyPath -Force -ErrorAction Stop | Out-Null
        }
    }
    Set-ItemProperty -LiteralPath $KeyPath -Name $ValName -Value $Value -Type $Type -Force -ErrorAction Stop | Out-Null
}

function Remove-RegValSafe {
    param([string]$KeyPath, [string]$ValName)
    if (Test-Path -LiteralPath $KeyPath) {
        Remove-ItemProperty -LiteralPath $KeyPath -Name $ValName -Force -ErrorAction SilentlyContinue
    }
}

# --- Context Menu Helpers ---
function Set-UserContextMenu {
    param(
        [string]$SubKeyPath,
        [string]$MenuText,
        [string]$IconPath,
        [string]$CommandStr
    )
    $key = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($SubKeyPath)
    if ($MenuText) { $key.SetValue("", $MenuText) }
    if ($IconPath) { $key.SetValue("Icon", $IconPath) }
    $cmdKey = $key.CreateSubKey("command")
    $cmdKey.SetValue("", $CommandStr)
    $cmdKey.Close()
    $key.Close()
}

function Remove-UserContextMenu {
    param([string]$SubKeyPath)
    try {
        [Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree($SubKeyPath, $false)
    } catch { }
}

function Find-VsCodePath {
    $cmd = Get-Command code -ErrorAction SilentlyContinue
    if ($cmd) {
        $codeDir = Split-Path -Parent $cmd.Source
        $parentExe = Join-Path (Split-Path -Parent $codeDir) "Code.exe"
        if (Test-Path -LiteralPath $parentExe) { return $parentExe }
        $binExe = Join-Path $codeDir "Code.exe"
        if (Test-Path -LiteralPath $binExe) { return $binExe }
    }
    $candidates = @(
        "$env:LOCALAPPDATA\Programs\Microsoft VS Code\Code.exe",
        "$env:ProgramFiles\Microsoft VS Code\Code.exe",
        "${env:ProgramFiles(x86)}\Microsoft VS Code\Code.exe"
    )
    foreach ($c in $candidates) {
        if (Test-Path -LiteralPath $c) { return $c }
    }
    return $null
}

function Find-WindowsTerminalPath {
    $cmd = Get-Command wt -ErrorAction SilentlyContinue
    if ($cmd -and (Test-Path -LiteralPath $cmd.Source)) { return $cmd.Source }
    $wtApp = "$env:LOCALAPPDATA\Microsoft\WindowsApps\wt.exe"
    if (Test-Path -LiteralPath $wtApp) { return $wtApp }
    return "wt.exe"
}

function Test-UltimatePerformanceUnlocked {
    try {
        $schemes = Get-ChildItem "HKLM:\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes" -ErrorAction SilentlyContinue
        foreach ($s in $schemes) {
            $fn = (Get-ItemProperty $s.PSPath -Name "FriendlyName" -ErrorAction SilentlyContinue).FriendlyName
            if ($fn -like "*Ultimate Performance*" -or $s.PSChildName -eq "e9a42b02-d5df-448d-aa00-03f14749eb61") {
                return $true
            }
        }
    } catch { }
    return $false
}

function Get-TerminalCopyPasteConfigured {
    $wtPath = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
    if (-not (Test-Path -LiteralPath $wtPath)) { return $false }
    try {
        $wt = Get-Content -LiteralPath $wtPath -Raw | ConvertFrom-Json
        $copyShift = $wt.keybindings | Where-Object { ($_.id -like "*copy*" -or $_.command -eq "copy" -or ($_.command.action -eq "copy")) -and $_.keys -eq "ctrl+shift+c" }
        $pasteShift = $wt.keybindings | Where-Object { ($_.id -like "*paste*" -or $_.command -eq "paste") -and $_.keys -eq "ctrl+shift+v" }
        $cUnbound = $wt.keybindings | Where-Object { $_.keys -eq "ctrl+c" -and ($_.action -eq "unbound" -or $_.command -eq "unbound" -or [string]::IsNullOrEmpty($_.id)) }
        $vUnbound = $wt.keybindings | Where-Object { $_.keys -eq "ctrl+v" -and ($_.action -eq "unbound" -or $_.command -eq "unbound" -or [string]::IsNullOrEmpty($_.id)) }
        return ($null -ne $copyShift -and $null -ne $pasteShift -and $null -ne $cUnbound -and $null -ne $vUnbound)
    } catch { return $false }
}

function Set-TerminalCopyPasteKeybindings {
    param([bool]$Enable)
    $wtPath = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
    if (-not (Test-Path -LiteralPath $wtPath)) { return }
    try {
        $wt = Get-Content -LiteralPath $wtPath -Raw | ConvertFrom-Json
        $kbs = [System.Collections.ArrayList]@()
        if ($wt.keybindings) {
            foreach ($kb in $wt.keybindings) {
                if ($kb.keys -in @("ctrl+c", "ctrl+v", "ctrl+shift+c", "ctrl+shift+v")) {
                    continue
                }
                $null = $kbs.Add($kb)
            }
        }
        if ($Enable) {
            $copyAction = $wt.actions | Where-Object { $_.command -eq "copy" -or ($_.command.action -eq "copy") }
            $copyId = if ($copyAction) { $copyAction.id } else { $null }

            $pasteAction = $wt.actions | Where-Object { $_.command -eq "paste" }
            $pasteId = if ($pasteAction) { $pasteAction.id } else { $null }

            $copyBinding = if ($copyId) { [PSCustomObject]@{ id = $copyId; keys = "ctrl+shift+c" } } else { [PSCustomObject]@{ command = [PSCustomObject]@{ action = "copy"; singleLine = $false }; keys = "ctrl+shift+c" } }
            $pasteBinding = if ($pasteId) { [PSCustomObject]@{ id = $pasteId; keys = "ctrl+shift+v" } } else { [PSCustomObject]@{ command = "paste"; keys = "ctrl+shift+v" } }

            $null = $kbs.Add($copyBinding)
            $null = $kbs.Add($pasteBinding)
            $null = $kbs.Add([PSCustomObject]@{ command = "unbound"; keys = "ctrl+v" })
            $null = $kbs.Add([PSCustomObject]@{ command = "unbound"; keys = "ctrl+c" })
        } else {
            $copyAction = $wt.actions | Where-Object { $_.command -eq "copy" -or ($_.command.action -eq "copy") }
            if ($copyAction) {
                $null = $kbs.Add([PSCustomObject]@{ id = $copyAction.id; keys = "ctrl+c" })
            }
            $pasteAction = $wt.actions | Where-Object { $_.command -eq "paste" }
            if ($pasteAction) {
                $null = $kbs.Add([PSCustomObject]@{ id = $pasteAction.id; keys = "ctrl+v" })
            }
        }
        $wt.keybindings = $kbs
        $json = $wt | ConvertTo-Json -Depth 20
        [System.IO.File]::WriteAllText($wtPath, $json, [System.Text.Encoding]::UTF8)
    } catch {
        Write-Warn "Failed to update Windows Terminal settings.json: $_"
    }
}

# --- Config Exporter ---
function Export-CurrentConfiguration {
    param([string]$OutputPath)
    Write-Header "Exporting Current Machine Configuration"

    # Privacy
    $tele1 = Get-RegValSafe -KeyPath "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -ValName "AllowTelemetry"
    $tele2 = Get-RegValSafe -KeyPath "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection" -ValName "AllowTelemetry"
    $isTelemetryDisabled = ($tele1 -eq 0 -or $tele2 -eq 0)

    $isAdIdDisabled = ((Get-RegValSafe -KeyPath "HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo" -ValName "Enabled") -eq 0)

    $bing1 = Get-RegValSafe -KeyPath "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -ValName "BingSearchEnabled"
    $bing2 = Get-RegValSafe -KeyPath "HKCU:\Software\Policies\Microsoft\Windows\Explorer" -ValName "DisableSearchBoxSuggestions"
    $isBingDisabled = ($bing1 -eq 0 -or $bing2 -eq 1)

    $act = Get-RegValSafe -KeyPath "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -ValName "EnableActivityFeed"
    $isActDisabled = ($act -eq 0)

    $siuf = Get-RegValSafe -KeyPath "HKCU:\Software\Microsoft\Siuf\Rules" -ValName "NumberOfSIUFInPeriod"
    $isFeedbackDisabled = ($siuf -eq 0)

    # Telemetry scheduled tasks
    $appraiserTask = Get-ScheduledTask -TaskPath "\Microsoft\Windows\Application Experience\" -TaskName "Microsoft Compatibility Appraiser" -ErrorAction SilentlyContinue
    if (-not $appraiserTask) {
        $appraiserTask = Get-ScheduledTask -TaskPath "\Microsoft\Windows\Application Experience\" -TaskName "Microsoft Compatibility Appraiser Exp" -ErrorAction SilentlyContinue
    }
    $isTelemetryTasksDisabled = if ($appraiserTask) { $appraiserTask.State -eq "Disabled" } else { $false }

    # Explorer
    $showExt = ((Get-RegValSafe -KeyPath "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -ValName "HideFileExt") -eq 0)
    $showHidden = ((Get-RegValSafe -KeyPath "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -ValName "Hidden") -eq 1)
    $launchThisPC = ((Get-RegValSafe -KeyPath "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -ValName "LaunchTo") -eq 1)
    $classicContext = (Test-Path -LiteralPath "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32")
    $showFullPath = ((Get-RegValSafe -KeyPath "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\CabinetState" -ValName "FullPath") -eq 1)
    $showSeconds = ((Get-RegValSafe -KeyPath "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -ValName "ShowSecondsInSystemClock") -eq 1)
    $hasVsCodeMenu = (Test-Path -LiteralPath "HKCU:\Software\Classes\Directory\Background\shell\VSCode")
    $hasTerminalMenu = (Test-Path -LiteralPath "HKCU:\Software\Classes\Directory\Background\shell\wt")

    $isTaskbarEndTask = ((Get-RegValSafe -KeyPath "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\TaskbarDeveloperSettings" -ValName "TaskbarEndTask") -eq 1)
    $isSearchHighlightsDisabled = ((Get-RegValSafe -KeyPath "HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings" -ValName "IsDynamicSearchBoxEnabled") -eq 0)
    $isStorePromptDisabled = ((Get-RegValSafe -KeyPath "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer" -ValName "NoUseStoreOpenWith") -eq 1)
    $isLockOverlayDisabled = ((Get-RegValSafe -KeyPath "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -ValName "RotatingLockScreenOverlayEnabled") -eq 0)
    $isLockSubDisabled = ((Get-RegValSafe -KeyPath "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -ValName "SubscribedContent-338387Enabled") -eq 0)
    $isLockScreenAdsDisabled = ($isLockOverlayDisabled -and $isLockSubDisabled)
    $isSnapAssistDisabled = ((Get-RegValSafe -KeyPath "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -ValName "SnapAssist") -eq 0)
    $isMouseStickyCornersDisabled = ((Get-RegValSafe -KeyPath "HKCU:\Control Panel\Desktop" -ValName "MouseCornerClipLength") -eq 0)

    # Performance
    $disableDelay = ((Get-RegValSafe -KeyPath "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize" -ValName "StartupDelayInMSec") -eq 0)
    $edge1 = Get-RegValSafe -KeyPath "HKLM:\SOFTWARE\Policies\Microsoft\Edge" -ValName "StartupBoostEnabled"
    $disableEdge = ($edge1 -eq 0)
    $disableFastStart = ((Get-RegValSafe -KeyPath "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power" -ValName "HiberbootEnabled") -eq 0)
    $isUltimateUnlocked = (Test-UltimatePerformanceUnlocked)

    # UI Debloat
    $hideCopilot = ((Get-RegValSafe -KeyPath "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -ValName "ShowCopilotButton") -eq 0)
    $hideTaskView = ((Get-RegValSafe -KeyPath "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -ValName "ShowTaskViewButton") -eq 0)
    $hideWidgets = ((Get-RegValSafe -KeyPath "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -ValName "TaskbarDa") -eq 0)
    $silenceTips = ((Get-RegValSafe -KeyPath "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -ValName "SubscribedContent-338388Enabled") -eq 0)
    
    $skFlags = Get-RegValSafe -KeyPath "HKCU:\Control Panel\Accessibility\StickyKeys" -ValName "Flags"
    $disableSticky = if ($skFlags) { (([int]$skFlags) -band 4) -eq 0 } else { $false }

    # Developer
    $enableLongPaths = ((Get-RegValSafe -KeyPath "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" -ValName "LongPathsEnabled") -eq 1)
    $crlfVal = (git config --global core.autocrlf 2>$null)
    $gitCrlf = ($crlfVal -ieq 'true')

    $docs = [Environment]::GetFolderPath('MyDocuments')
    $p1 = Join-Path $docs "WindowsPowerShell\Microsoft.PowerShell_profile.ps1"
    $p2 = Join-Path $docs "PowerShell\Microsoft.PowerShell_profile.ps1"
    $psShortcuts = $false
    if ((Test-Path -LiteralPath $p1) -and ((Get-Content -LiteralPath $p1 -Raw) -match "# >>> (Sane Windows|Useful Setup) Developer Ergonomics >>>")) { $psShortcuts = $true }
    if ((Test-Path -LiteralPath $p2) -and ((Get-Content -LiteralPath $p2 -Raw) -match "# >>> (Sane Windows|Useful Setup) Developer Ergonomics >>>")) { $psShortcuts = $true }

    $wtSettings = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
    $termDup = $false
    if (Test-Path -LiteralPath $wtSettings) {
        $rawWt = Get-Content -LiteralPath $wtSettings -Raw
        if ($rawWt -match "duplicateTab") { $termDup = $true }
    }
    $isCtrlShiftCopyPaste = (Get-TerminalCopyPasteConfigured)

    # Windows Update
    $noAutoReboot = ((Get-RegValSafe -KeyPath "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -ValName "NoAutoRebootWithLoggedOnUsers") -eq 1)
    $excludeDrivers = ((Get-RegValSafe -KeyPath "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -ValName "ExcludeWUDriversInQualityUpdate") -eq 1)

    function To-YBool($b) { if ($b) { "true" } else { "false" } }

    $exportDir = Split-Path -Parent $OutputPath
    if ($exportDir -and -not (Test-Path -LiteralPath $exportDir)) {
        New-Item -ItemType Directory -Path $exportDir -Force | Out-Null
    }

    $yaml = @"
# ==============================================================================
# Sane Windows - Windows Quality-of-Life & Performance Configuration
# Exported from machine: $env:COMPUTERNAME on $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
# ==============================================================================
# Edit any setting below (true/false) and run 'setup.bat' or '.\setup.ps1'.
# A snapshot of all your settings is saved before ANY change is made, so you
# can revert anytime using 'setup.bat -Revert'.
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. Privacy & Anti-Telemetry (Stop Windows Tracking)
# ------------------------------------------------------------------------------
privacy:
  # Restricts diagnostic data collection to the minimum security level
  disable_telemetry: $(To-YBool $isTelemetryDisabled)

  # Disables advertising ID, tracking across apps, and tailored experiences
  disable_advertising_id: $(To-YBool $isAdIdDisabled)

  # Disables Bing/web search results inside Start Menu search (pure local search)
  disable_bing_search: $(To-YBool $isBingDisabled)

  # Stops collecting and uploading Timeline / activity history
  disable_activity_history: $(To-YBool $isActDisabled)

  # Disables feedback popups ("How likely are you to recommend Windows...")
  disable_feedback_prompts: $(To-YBool $isFeedbackDisabled)

  # Disables background telemetry and customer experience scheduled tasks
  disable_telemetry_tasks: $(To-YBool $isTelemetryTasksDisabled)


# ------------------------------------------------------------------------------
# 2. File Explorer & Navigation Sanity
# ------------------------------------------------------------------------------
explorer:
  # Show file extensions (.py, .exe, .json, .txt, etc.)
  show_file_extensions: $(To-YBool $showExt)

  # Show hidden files, folders, and drives (AppData, .git, etc.)
  show_hidden_files: $(To-YBool $showHidden)

  # Open File Explorer directly to "This PC" instead of "Home / Quick Access"
  launch_to_this_pc: $(To-YBool $launchThisPC)

  # Windows 11: Restores classic Windows 10 right-click context menu (no "Show more options")
  classic_context_menu: $(To-YBool $classicContext)

  # Displays the full file system path in Explorer title bars
  show_full_path_in_title: $(To-YBool $showFullPath)

  # Displays seconds in the taskbar system clock
  show_seconds_in_clock: $(To-YBool $showSeconds)

  # Adds "Open with Code" to right-click context menu for folders and files
  add_open_with_code: $(To-YBool $hasVsCodeMenu)

  # Adds "Open in Windows Terminal" to right-click context menu for folders and backgrounds
  add_open_in_terminal: $(To-YBool $hasTerminalMenu)

  # Windows 11 (23H2+): Enables "End Task" on taskbar app right-click menu
  enable_taskbar_end_task: $(To-YBool $isTaskbarEndTask)

  # Disables web search highlights, cartoons, and doodles inside the taskbar search box
  disable_search_highlights: $(To-YBool $isSearchHighlightsDisabled)

  # Prevents "Search the Microsoft Store for an app" popup when opening unknown file types
  disable_store_app_prompt: $(To-YBool $isStorePromptDisabled)

  # Disables lock screen rotating spotlights, ads, fun facts, and tips
  disable_lock_screen_ads: $(To-YBool $isLockScreenAdsDisabled)

  # Disables Snap Assist popups (multi-window thumbnail suggestions & flyouts when snapping)
  disable_snap_assist_popups: $(To-YBool $isSnapAssistDisabled)

  # Disables multi-monitor cursor sticky corners (allows smooth mouse transitions between displays)
  disable_mouse_sticky_corners: $(To-YBool $isMouseStickyCornersDisabled)


# ------------------------------------------------------------------------------
# 3. Startup Speed & System Performance
# ------------------------------------------------------------------------------
performance:
  # Removes the built-in artificial startup delay for desktop apps
  disable_startup_delay: $(To-YBool $disableDelay)

  # Stops Microsoft Edge from pre-launching and idling in the background
  disable_edge_background_tasks: $(To-YBool $disableEdge)

  # Disables Fast Startup (prevents hibernation-related kernel state corruption)
  disable_fast_startup: $(To-YBool $disableFastStart)

  # Unlocks the hidden Windows "Ultimate Performance" power scheme
  unlock_ultimate_performance: $(To-YBool $isUltimateUnlocked)


# ------------------------------------------------------------------------------
# 4. UI Cleanliness & De-bloat
# ------------------------------------------------------------------------------
ui_debloat:
  # Hides the Copilot button from the taskbar
  hide_taskbar_copilot_button: $(To-YBool $hideCopilot)

  # Hides the Task View (virtual desktops) button from the taskbar
  hide_taskbar_task_view: $(To-YBool $hideTaskView)

  # Hides the Widgets / Weather button from the taskbar
  hide_taskbar_widgets: $(To-YBool $hideWidgets)

  # Silences tips, tricks, suggested content, and promotional notifications
  silence_tips_and_suggestions: $(To-YBool $silenceTips)

  # Disables Sticky Keys, Toggle Keys, and Filter Keys shortcut popups (5x Shift, etc.)
  disable_sticky_keys_popup: $(To-YBool $disableSticky)

  # Automatically uninstalls pre-installed promotional junk apps
  remove_bloatware_apps: false

  # List of app packages to remove if installed
  bloatware_list:
    - Microsoft.BingNews
    - Microsoft.BingWeather
    - Microsoft.GetHelp
    - Microsoft.Getstarted
    - Microsoft.MicrosoftSolitaireCollection
    - Microsoft.SkypeApp
    - Microsoft.Todos
    - Microsoft.ZuneVideo
    - Clipchamp.Clipchamp
    - ByteDancePte.Ltd.TikTok
    - Disney.37853FC2267DE
    - SpotifyAB.SpotifyMusic


# ------------------------------------------------------------------------------
# 5. Developer & Terminal Ergonomics
# ------------------------------------------------------------------------------
developer:
  # Enables Win32 Long Path support (>260 character paths for Python/Node)
  enable_long_paths: $(To-YBool $enableLongPaths)

  # Configures git global core.autocrlf to true (avoids line-ending issues)
  configure_git_autocrlf: $(To-YBool $gitCrlf)

  # Adds PowerShell aliases ('which', 'll') and PSReadLine prediction autocomplete
  enable_powershell_shortcuts: $(To-YBool $psShortcuts)

  # Binds Ctrl+Shift+D in Terminal and installs OSC 9;9 CWD tracker
  enable_terminal_duplicate_tab: $(To-YBool $termDup)

  # Requires Ctrl+Shift+C to copy and Ctrl+Shift+V to paste in Terminal & PowerShell
  require_ctrl_shift_copy_paste: $(To-YBool $isCtrlShiftCopyPaste)


# ------------------------------------------------------------------------------
# 6. Windows Update Control
# ------------------------------------------------------------------------------
windows_update:
  # Prevents Windows from automatically rebooting for updates while a user is logged in
  no_auto_restart_logged_on: $(To-YBool $noAutoReboot)

  # Excludes third-party driver updates from routine Windows Updates (prevents GPU driver overwrites)
  exclude_drivers: $(To-YBool $excludeDrivers)
"@

    [System.IO.File]::WriteAllText($OutputPath, $yaml, [System.Text.Encoding]::UTF8)
    Write-Host " [OK] Current machine configuration exported to:" -ForegroundColor Green
    Write-Host "      $OutputPath`n" -ForegroundColor Cyan
    Write-Host " To use this as your active configuration, run:" -ForegroundColor Gray
    Write-Host "      Copy-Item `"$OutputPath`" `"$ScriptDir\config.yaml`"`n" -ForegroundColor Yellow
}



# --- Snapshot Engine ---
$SnapshotsDir = Join-Path $ScriptDir "snapshots"
if (-not (Test-Path $SnapshotsDir)) {
    New-Item -ItemType Directory -Path $SnapshotsDir -Force | Out-Null
}

function Get-CurrentSystemState {
    $state = [ordered]@{
        timestamp = (Get-Date).ToString("o")
        isAdmin   = (Test-IsAdmin)
        registry  = [ordered]@{}
        git       = [ordered]@{}
        terminal  = [ordered]@{}
        profiles  = [ordered]@{}
    }

    # Registry Settings Definitions
    $regTargets = @(
        # Privacy
        @{ Section="privacy"; Key="disable_telemetry_hklm1"; Path="HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"; Name="AllowTelemetry"; Type="DWord" },
        @{ Section="privacy"; Key="disable_telemetry_hklm2"; Path="HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection"; Name="AllowTelemetry"; Type="DWord" },
        @{ Section="privacy"; Key="advertising_id"; Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo"; Name="Enabled"; Type="DWord" },
        @{ Section="privacy"; Key="tailored_experiences"; Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy"; Name="TailoredExperiencesWithDiagnosticDataEnabled"; Type="DWord" },
        @{ Section="privacy"; Key="bing_search_explorer"; Path="HKCU:\Software\Policies\Microsoft\Windows\Explorer"; Name="DisableSearchBoxSuggestions"; Type="DWord" },
        @{ Section="privacy"; Key="bing_search_enabled"; Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\Search"; Name="BingSearchEnabled"; Type="DWord" },
        @{ Section="privacy"; Key="bing_cortana_consent"; Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\Search"; Name="CortanaConsent"; Type="DWord" },
        @{ Section="privacy"; Key="activity_history_feed"; Path="HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"; Name="EnableActivityFeed"; Type="DWord" },
        @{ Section="privacy"; Key="activity_history_pub"; Path="HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"; Name="PublishUserActivities"; Type="DWord" },
        @{ Section="privacy"; Key="activity_history_up"; Path="HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"; Name="UploadUserActivities"; Type="DWord" },
        @{ Section="privacy"; Key="feedback_siuf"; Path="HKCU:\Software\Microsoft\Siuf\Rules"; Name="NumberOfSIUFInPeriod"; Type="DWord" },
        @{ Section="privacy"; Key="feedback_notif"; Path="HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"; Name="DoNotShowFeedbackNotifications"; Type="DWord" },

        # Explorer
        @{ Section="explorer"; Key="hide_file_ext"; Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name="HideFileExt"; Type="DWord" },
        @{ Section="explorer"; Key="hidden_files"; Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name="Hidden"; Type="DWord" },
        @{ Section="explorer"; Key="launch_to"; Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name="LaunchTo"; Type="DWord" },
        @{ Section="explorer"; Key="full_path_title"; Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\CabinetState"; Name="FullPath"; Type="DWord" },

        # Performance
        @{ Section="performance"; Key="startup_delay"; Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize"; Name="StartupDelayInMSec"; Type="DWord" },
        @{ Section="performance"; Key="edge_startup_boost"; Path="HKLM:\SOFTWARE\Policies\Microsoft\Edge"; Name="StartupBoostEnabled"; Type="DWord" },
        @{ Section="performance"; Key="edge_background_mode"; Path="HKLM:\SOFTWARE\Policies\Microsoft\Edge"; Name="BackgroundModeEnabled"; Type="DWord" },
        @{ Section="performance"; Key="fast_startup"; Path="HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power"; Name="HiberbootEnabled"; Type="DWord" },

        # UI Debloat
        @{ Section="ui_debloat"; Key="copilot_button"; Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name="ShowCopilotButton"; Type="DWord" },
        @{ Section="ui_debloat"; Key="task_view_button"; Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name="ShowTaskViewButton"; Type="DWord" },
        @{ Section="ui_debloat"; Key="widgets_button"; Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name="TaskbarDa"; Type="DWord" },
        @{ Section="ui_debloat"; Key="content_delivery_338388"; Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Name="SubscribedContent-338388Enabled"; Type="DWord" },
        @{ Section="ui_debloat"; Key="content_delivery_338389"; Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Name="SubscribedContent-338389Enabled"; Type="DWord" },
        @{ Section="ui_debloat"; Key="content_delivery_353694"; Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Name="SubscribedContent-353694Enabled"; Type="DWord" },
        @{ Section="ui_debloat"; Key="content_delivery_353696"; Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Name="SubscribedContent-353696Enabled"; Type="DWord" },
        @{ Section="ui_debloat"; Key="content_delivery_softlanding"; Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Name="SoftLandingEnabled"; Type="DWord" },
        @{ Section="ui_debloat"; Key="content_delivery_syspane"; Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Name="SystemPaneSuggestionsEnabled"; Type="DWord" },

        # Explorer Additions
        @{ Section="explorer"; Key="clock_seconds"; Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name="ShowSecondsInSystemClock"; Type="DWord" },
        @{ Section="explorer"; Key="taskbar_end_task"; Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\TaskbarDeveloperSettings"; Name="TaskbarEndTask"; Type="DWord" },
        @{ Section="explorer"; Key="search_highlights"; Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings"; Name="IsDynamicSearchBoxEnabled"; Type="DWord" },
        @{ Section="explorer"; Key="store_app_prompt"; Path="HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer"; Name="NoUseStoreOpenWith"; Type="DWord" },
        @{ Section="explorer"; Key="lock_screen_overlay"; Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Name="RotatingLockScreenOverlayEnabled"; Type="DWord" },
        @{ Section="explorer"; Key="lock_screen_sub"; Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"; Name="SubscribedContent-338387Enabled"; Type="DWord" },
        @{ Section="explorer"; Key="snap_assist"; Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name="SnapAssist"; Type="DWord" },
        @{ Section="explorer"; Key="snap_assist_flyout"; Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name="EnableSnapAssistFlyout"; Type="DWord" },
        @{ Section="explorer"; Key="snap_bar"; Path="HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"; Name="EnableSnapBar"; Type="DWord" },
        @{ Section="explorer"; Key="mouse_corner_clip_length"; Path="HKCU:\Control Panel\Desktop"; Name="MouseCornerClipLength"; Type="DWord" },

        # UI Debloat Additions (Accessibility Hotkeys)
        @{ Section="ui_debloat"; Key="sticky_keys"; Path="HKCU:\Control Panel\Accessibility\StickyKeys"; Name="Flags"; Type="String" },
        @{ Section="ui_debloat"; Key="toggle_keys"; Path="HKCU:\Control Panel\Accessibility\ToggleKeys"; Name="Flags"; Type="String" },
        @{ Section="ui_debloat"; Key="filter_keys"; Path="HKCU:\Control Panel\Accessibility\Keyboard Response"; Name="Flags"; Type="String" },

        # Developer
        @{ Section="developer"; Key="long_paths"; Path="HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem"; Name="LongPathsEnabled"; Type="DWord" },

        # Windows Update
        @{ Section="windows_update"; Key="no_auto_reboot"; Path="HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"; Name="NoAutoRebootWithLoggedOnUsers"; Type="DWord" },
        @{ Section="windows_update"; Key="exclude_drivers"; Path="HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"; Name="ExcludeWUDriversInQualityUpdate"; Type="DWord" }
    )

    foreach ($t in $regTargets) {
        $regKeyId = "$($t.Path)::$($t.Name)"
        $state.registry[$regKeyId] = @{
            Path     = $t.Path
            Name     = $t.Name
            Type     = $t.Type
            Value    = (Get-RegValSafe -KeyPath $t.Path -ValName $t.Name)
            Existed  = ($null -ne (Get-RegValSafe -KeyPath $t.Path -ValName $t.Name))
        }
    }

    # Context Menu States
    $state.contextMenu = [ordered]@{
        vscodeDirectoryBackground   = (Test-Path -LiteralPath 'HKCU:\Software\Classes\Directory\Background\shell\VSCode')
        vscodeDirectory             = (Test-Path -LiteralPath 'HKCU:\Software\Classes\Directory\shell\VSCode')
        vscodeFile                  = (Test-Path -LiteralPath 'HKCU:\Software\Classes\*\shell\VSCode')
        terminalDirectoryBackground = (Test-Path -LiteralPath 'HKCU:\Software\Classes\Directory\Background\shell\wt')
        terminalDirectory           = (Test-Path -LiteralPath 'HKCU:\Software\Classes\Directory\shell\wt')
    }

    # Classic Context Menu CLSID
    $clsidPath = "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32"
    $state.registry["$clsidPath::(Default)"] = @{
        Path    = $clsidPath
        Name    = "(Default)"
        Type    = "String"
        Value   = if (Test-Path -LiteralPath $clsidPath) { (Get-Item -LiteralPath $clsidPath).GetValue("") } else { $null }
        Existed = (Test-Path -LiteralPath $clsidPath)
    }

    # Git
    if (Get-Command git -ErrorAction SilentlyContinue) {
        try {
            $crlf = (git config --global core.autocrlf 2>$null)
            $state.git["core.autocrlf"] = $crlf
        } catch { }
    }

    # Terminal Settings
    $wtPath = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
    if (Test-Path -LiteralPath $wtPath) {
        try {
            $wtRaw = Get-Content -LiteralPath $wtPath -Raw
            $state.terminal["duplicateTabBound"] = ($wtRaw -match "duplicateTab")
            $state.terminal["ctrlShiftCopyPaste"] = (Get-TerminalCopyPasteConfigured)
        } catch { }
    }

    # Power State
    $state.power = @{
        ultimatePerformanceUnlocked = (Test-UltimatePerformanceUnlocked)
    }

    return $state
}

function Save-Snapshot {
    param($State)
    $ts = (Get-Date).ToString("yyyyMMdd_HHmmss")
    $snapshotFile = Join-Path $SnapshotsDir "snapshot_$ts.json"
    $latestFile   = Join-Path $SnapshotsDir "latest.json"

    $json = $State | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText($snapshotFile, $json, [System.Text.Encoding]::UTF8)
    [System.IO.File]::WriteAllText($latestFile, $json, [System.Text.Encoding]::UTF8)
    return $snapshotFile
}

# --- Config Export Execution ---
if ($ExportConfig) {
    $targetExport = if ($ExportPath) { $ExportPath } else { Join-Path $ScriptDir "config.exported.yaml" }
    Export-CurrentConfiguration -OutputPath $targetExport
    exit 0
}

# --- Revert Engine ---
if ($ListSnapshots) {
    Write-Header "Saved Setting Snapshots"
    $files = Get-ChildItem -Path $SnapshotsDir -Filter "snapshot_*.json" | Sort-Object LastWriteTime -Descending
    if ($files.Count -eq 0) {
        Write-Host "No snapshots found in $SnapshotsDir" -ForegroundColor Yellow
    } else {
        foreach ($f in $files) {
            Write-Host "  $($f.Name)  (Created: $($f.LastWriteTime))" -ForegroundColor Cyan
        }
    }
    exit 0
}

if ($Revert) {
    Write-Header "Reverting System Settings from Snapshot"
    $targetSnapshot = if ($SnapshotPath) { $SnapshotPath } else { Join-Path $SnapshotsDir "latest.json" }

    if (-not (Test-Path $targetSnapshot)) {
        Write-Host "Snapshot file not found: $targetSnapshot" -ForegroundColor Red
        exit 1
    }

    Write-Info "Loading snapshot: $targetSnapshot"
    $snapData = Get-Content $targetSnapshot -Raw | ConvertFrom-Json

    # Save a safety snapshot before reverting
    $safetySnap = Save-Snapshot -State (Get-CurrentSystemState)
    Write-Info "Pre-revert safety snapshot saved: $safetySnap"

    $revertedCount = 0
    $explorerNeedsRestart = $false

    # Revert Registry
    foreach ($prop in $snapData.registry.PSObject.Properties) {
        $item = $prop.Value
        $path = $item.Path
        $name = $item.Name
        $existed = $item.Existed
        $origVal = $item.Value

        # Special case: Classic Context Menu
        if ($path -like "*86ca1aa0-34aa-4e8b-a509-50c905bae2a2*") {
            if (-not $existed -and (Test-Path "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}")) {
                Remove-Item -Path "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}" -Recurse -Force
                Write-Changed "Classic Context Menu" "Classic" "Windows 11 Default"
                $revertedCount++
                $explorerNeedsRestart = $true
            }
            continue
        }

        # Check HKLM elevation
        if ($path -like "HKLM:*" -and -not (Test-IsAdmin)) {
            Write-Skipped "$path::$name" "Requires Administrator elevation to revert"
            continue
        }

        if (-not $existed) {
            if ($null -ne (Get-RegValSafe -KeyPath $path -ValName $name)) {
                Remove-RegValSafe -KeyPath $path -ValName $name
                Write-Changed "$path::$name" "Modified" "Removed (did not originally exist)"
                $revertedCount++
                if ($path -like "*Explorer*") { $explorerNeedsRestart = $true }
            }
        } else {
            $currVal = Get-RegValSafe -KeyPath $path -ValName $name
            if ($currVal -ne $origVal) {
                Set-RegValSafe -KeyPath $path -ValName $name -Value $origVal -Type $item.Type
                Write-Changed "$path::$name" "$currVal" "$origVal"
                $revertedCount++
                if ($path -like "*Explorer*") { $explorerNeedsRestart = $true }
            }
        }
    }

    # Revert Git
    if ($snapData.git) {
        if ($snapData.git.'core.autocrlf') {
            git config --global core.autocrlf $snapData.git.'core.autocrlf'
            Write-Changed "git core.autocrlf" "Modified" "$($snapData.git.'core.autocrlf')"
            $revertedCount++
        } else {
            git config --global --unset core.autocrlf 2>$null
            Write-Changed "git core.autocrlf" "Modified" "Unset"
            $revertedCount++
        }
    }

    # Revert Context Menus
    if ($snapData.contextMenu) {
        if ($snapData.contextMenu.vscode) {
            if (-not $snapData.contextMenu.vscode.directoryBackground) {
                Remove-UserContextMenu -SubKeyPath "Software\Classes\Directory\Background\shell\VSCode"
            }
            if (-not $snapData.contextMenu.vscode.directory) {
                Remove-UserContextMenu -SubKeyPath "Software\Classes\Directory\shell\VSCode"
            }
            if (-not $snapData.contextMenu.vscode.file) {
                Remove-UserContextMenu -SubKeyPath "Software\Classes\*\shell\VSCode"
            }
            Remove-UserContextMenu -SubKeyPath "Software\Classes\Drive\shell\VSCode"
            Write-Changed "Context Menu" "Open with Code" "Modified" "Restored from snapshot"
            $revertedCount++
        }
        if ($snapData.contextMenu.terminal) {
            if (-not $snapData.contextMenu.terminal.directoryBackground) {
                Remove-UserContextMenu -SubKeyPath "Software\Classes\Directory\Background\shell\wt"
            }
            if (-not $snapData.contextMenu.terminal.directory) {
                Remove-UserContextMenu -SubKeyPath "Software\Classes\Directory\shell\wt"
            }
            Remove-UserContextMenu -SubKeyPath "Software\Classes\Drive\shell\wt"
            Write-Changed "Context Menu" "Open in Windows Terminal" "Modified" "Restored from snapshot"
            $revertedCount++
        }
    }

    # Revert Terminal Copy/Paste Keybindings
    if ($snapData.terminal -and $snapData.terminal.ctrlShiftCopyPaste -eq $false) {
        Set-TerminalCopyPasteKeybindings -Enable $false
        Write-Changed "Windows Terminal" "ctrlShiftCopyPaste" "Modified" "Restored to defaults"
        $revertedCount++
    }

    # Revert PowerShell profiles
    & "$ScriptDir\setup_duplicate_tab.ps1" -Uninstall | Out-Null
    Write-Info "PowerShell profile duplicate tab hooks reverted."

    if ($explorerNeedsRestart -and -not $NoExplorerRestart) {
        Write-Step "Restarting File Explorer to apply reverted settings..."
        Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    }

    Write-Host "`nReversion complete! $revertedCount settings restored to snapshot state." -ForegroundColor Green
    exit 0
}

# --- Main Setup Flow ---
Write-Header "Sane Windows: Windows QOL & Machine Configuration"

if (-not (Test-Path $ConfigPath)) {
    Write-Host "Configuration file not found: $ConfigPath" -ForegroundColor Red
    exit 1
}

Write-Info "Loading configuration from: $ConfigPath"
$configContent = Get-Content $ConfigPath -Raw
$config = ConvertFrom-SimpleYaml $configContent

$isAdmin = Test-IsAdmin
if (-not $isAdmin) {
    Write-Warn "Running without Administrator privileges."
    Write-Info "Per-user tweaks (Explorer, Taskbar, Bing Search, Terminal, PowerShell) will apply fully."
    Write-Info "Machine-wide tweaks (Fast Startup, Long Paths, Machine Telemetry) require Admin and will be skipped."
}

# Collect planned changes
$script:pendingChanges = [System.Collections.ArrayList]@()

function Register-PlannedChange {
    param(
        [string]$Category,
        [string]$SettingName,
        [string]$CurrentValue,
        [string]$DesiredValue,
        [scriptblock]$Action,
        $Arguments = @(),
        [bool]$AffectsExplorer = $false
    )
    $null = $script:pendingChanges.Add([PSCustomObject]@{
        Category        = $Category
        Setting         = $SettingName
        CurrentValue    = $CurrentValue
        DesiredValue    = $DesiredValue
        Action          = $Action
        Arguments       = $Arguments
        AffectsExplorer = $AffectsExplorer
    })
}

function Check-RegChange {
    param(
        [string]$Category,
        [string]$SettingName,
        [string]$RegPath,
        [string]$ValName,
        $DesiredValue,
        [string]$Type = "DWord"
    )
    $currVal = Get-RegValSafe -KeyPath $RegPath -ValName $ValName

    # Check if requires admin
    if (($RegPath -like "HKLM:*" -or $RegPath -like "*\Policies\*") -and -not $isAdmin) {
        if ($VerboseOutput) {
            Write-Skipped "$Category.$SettingName" "Requires Administrator elevation"
        }
        return
    }

    if ($currVal -ne $DesiredValue) {
        $displayOld = if ($null -eq $currVal) { "<none>" } else { "$currVal" }
        $affectsExp = ($RegPath -like "*Explorer*" -or $RegPath -like "*Search*")
        Register-PlannedChange -Category $Category -SettingName $SettingName -CurrentValue $displayOld -DesiredValue "$DesiredValue" -AffectsExplorer $affectsExp -Arguments @($RegPath, $ValName, $DesiredValue, $Type) -Action {
            param($kp, $vn, $dv, $tp)
            Set-RegValSafe -KeyPath $kp -ValName $vn -Value $dv -Type $tp
        }
    } else {
        Write-Unchanged "$Category.$SettingName" "$DesiredValue"
    }
}

# -------------------------------------------------------------
# 1. Privacy & Anti-Telemetry Settings
# -------------------------------------------------------------
Write-Step "Inspecting Privacy & Anti-Telemetry Settings..."

if ($null -ne $config['privacy']['disable_telemetry']) {
    $teleVal = if ($config['privacy']['disable_telemetry']) { 0 } else { 3 }
    Check-RegChange -Category "privacy" -SettingName "disable_telemetry_policies" -RegPath "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -ValName "AllowTelemetry" -DesiredValue $teleVal
    Check-RegChange -Category "privacy" -SettingName "disable_telemetry_system" -RegPath "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection" -ValName "AllowTelemetry" -DesiredValue $teleVal
}

if ($null -ne $config['privacy']['disable_advertising_id']) {
    $adVal = if ($config['privacy']['disable_advertising_id']) { 0 } else { 1 }
    Check-RegChange -Category "privacy" -SettingName "advertising_id" -RegPath "HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo" -ValName "Enabled" -DesiredValue $adVal
    Check-RegChange -Category "privacy" -SettingName "tailored_experiences" -RegPath "HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy" -ValName "TailoredExperiencesWithDiagnosticDataEnabled" -DesiredValue $adVal
}

if ($null -ne $config['privacy']['disable_bing_search']) {
    $bingBox = if ($config['privacy']['disable_bing_search']) { 1 } else { 0 }
    $bingVal = if ($config['privacy']['disable_bing_search']) { 0 } else { 1 }
    Check-RegChange -Category "privacy" -SettingName "disable_search_box_suggestions" -RegPath "HKCU:\Software\Policies\Microsoft\Windows\Explorer" -ValName "DisableSearchBoxSuggestions" -DesiredValue $bingBox
    Check-RegChange -Category "privacy" -SettingName "bing_search_enabled" -RegPath "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -ValName "BingSearchEnabled" -DesiredValue $bingVal
    Check-RegChange -Category "privacy" -SettingName "cortana_consent" -RegPath "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -ValName "CortanaConsent" -DesiredValue $bingVal
}

if ($null -ne $config['privacy']['disable_activity_history']) {
    $actVal = if ($config['privacy']['disable_activity_history']) { 0 } else { 1 }
    Check-RegChange -Category "privacy" -SettingName "activity_feed" -RegPath "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -ValName "EnableActivityFeed" -DesiredValue $actVal
    Check-RegChange -Category "privacy" -SettingName "publish_user_activities" -RegPath "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -ValName "PublishUserActivities" -DesiredValue $actVal
    Check-RegChange -Category "privacy" -SettingName "upload_user_activities" -RegPath "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -ValName "UploadUserActivities" -DesiredValue $actVal
}

if ($null -ne $config['privacy']['disable_feedback_prompts']) {
    $siufVal = if ($config['privacy']['disable_feedback_prompts']) { 0 } else { 1 }
    $fbNotif = if ($config['privacy']['disable_feedback_prompts']) { 1 } else { 0 }
    Check-RegChange -Category "privacy" -SettingName "siuf_period" -RegPath "HKCU:\Software\Microsoft\Siuf\Rules" -ValName "NumberOfSIUFInPeriod" -DesiredValue $siufVal
    Check-RegChange -Category "privacy" -SettingName "feedback_notifications" -RegPath "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -ValName "DoNotShowFeedbackNotifications" -DesiredValue $fbNotif
}

if ($config['privacy']['disable_telemetry_tasks']) {
    if (-not $isAdmin) {
        if ($VerboseOutput) {
            Write-Skipped "privacy.disable_telemetry_tasks" "Requires Administrator elevation"
        }
    } else {
        $tasksToDisable = @(
            @{ Path="\Microsoft\Windows\Application Experience\"; Name="Microsoft Compatibility Appraiser" },
            @{ Path="\Microsoft\Windows\Application Experience\"; Name="Microsoft Compatibility Appraiser Exp" },
            @{ Path="\Microsoft\Windows\Application Experience\"; Name="ProgramDataUpdater" },
            @{ Path="\Microsoft\Windows\Customer Experience Improvement Program\"; Name="Consolidator" },
            @{ Path="\Microsoft\Windows\Customer Experience Improvement Program\"; Name="UsbCeip" },
            @{ Path="\Microsoft\Windows\DiskDiagnostic\"; Name="Microsoft-Windows-DiskDiagnosticDataCollector" }
        )
        $activeTasks = @()
        foreach ($t in $tasksToDisable) {
            $taskObj = Get-ScheduledTask -TaskPath $t.Path -TaskName $t.Name -ErrorAction SilentlyContinue
            if ($taskObj -and $taskObj.State -ne "Disabled") {
                $activeTasks += $t
            }
        }
        if ($activeTasks.Count -gt 0) {
            Register-PlannedChange -Category "privacy" -SettingName "disable_telemetry_tasks" -CurrentValue "$($activeTasks.Count) tasks active" -DesiredValue "Disable $($activeTasks.Count) tasks" -AffectsExplorer $false -Action {
                foreach ($at in $tasksToDisable) {
                    $to = Get-ScheduledTask -TaskPath $at.Path -TaskName $at.Name -ErrorAction SilentlyContinue
                    if ($to -and $to.State -ne "Disabled") {
                        Disable-ScheduledTask -TaskPath $at.Path -TaskName $at.Name -ErrorAction SilentlyContinue | Out-Null
                    }
                }
            }
        } else {
            Write-Unchanged "privacy.disable_telemetry_tasks" "Disabled"
        }
    }
}

# -------------------------------------------------------------
# 2. Explorer & Navigation Sanity
# -------------------------------------------------------------
Write-Step "Inspecting File Explorer & Navigation Settings..."

if ($null -ne $config['explorer']['show_file_extensions']) {
    $extVal = if ($config['explorer']['show_file_extensions']) { 0 } else { 1 }
    Check-RegChange -Category "explorer" -SettingName "show_file_extensions" -RegPath "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -ValName "HideFileExt" -DesiredValue $extVal
}

if ($null -ne $config['explorer']['show_hidden_files']) {
    $hiddenVal = if ($config['explorer']['show_hidden_files']) { 1 } else { 2 }
    Check-RegChange -Category "explorer" -SettingName "show_hidden_files" -RegPath "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -ValName "Hidden" -DesiredValue $hiddenVal
}

if ($null -ne $config['explorer']['launch_to_this_pc']) {
    $launchVal = if ($config['explorer']['launch_to_this_pc']) { 1 } else { 2 }
    Check-RegChange -Category "explorer" -SettingName "launch_to_this_pc" -RegPath "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -ValName "LaunchTo" -DesiredValue $launchVal
}

if ($null -ne $config['explorer']['show_full_path_in_title']) {
    $fullPathVal = if ($config['explorer']['show_full_path_in_title']) { 1 } else { 0 }
    Check-RegChange -Category "explorer" -SettingName "show_full_path_in_title" -RegPath "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\CabinetState" -ValName "FullPath" -DesiredValue $fullPathVal
}

if ($null -ne $config['explorer']['classic_context_menu']) {
    if (-not $script:IsWindows11) {
        Write-Skipped "explorer.classic_context_menu" "Native to Windows 10 (Windows 11 only)"
    } else {
        $clsidKey = "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}"
        $isClassic = (Test-Path "$clsidKey\InprocServer32")
        if ($config['explorer']['classic_context_menu']) {
            if (-not $isClassic) {
                Register-PlannedChange -Category "explorer" -SettingName "classic_context_menu" -CurrentValue "Windows 11 Modern" -DesiredValue "Windows 10 Classic Style" -AffectsExplorer $true -Arguments @($clsidKey) -Action {
                    param($k)
                    New-Item -Path "$k\InprocServer32" -Force | Out-Null
                    Set-Item -Path "$k\InprocServer32" -Value "" | Out-Null
                }
            } else {
                Write-Unchanged "explorer.classic_context_menu" "Enabled (Windows 10 Style)"
            }
        } else {
            if ($isClassic) {
                Register-PlannedChange -Category "explorer" -SettingName "classic_context_menu" -CurrentValue "Windows 10 Classic Style" -DesiredValue "Windows 11 Modern" -AffectsExplorer $true -Arguments @($clsidKey) -Action {
                    param($k)
                    Remove-Item -Path $k -Recurse -Force -ErrorAction SilentlyContinue
                }
            } else {
                Write-Unchanged "explorer.classic_context_menu" "Windows 11 Modern"
            }
        }
    }
}

if ($null -ne $config['explorer']['show_seconds_in_clock']) {
    $secVal = if ($config['explorer']['show_seconds_in_clock']) { 1 } else { 0 }
    Check-RegChange -Category "explorer" -SettingName "show_seconds_in_clock" -RegPath "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -ValName "ShowSecondsInSystemClock" -DesiredValue $secVal
}

if ($null -ne $config['explorer']['add_open_with_code']) {
    $codePath = Find-VsCodePath
    $hasVsCodeMenu = (Test-Path -LiteralPath "HKCU:\Software\Classes\Directory\Background\shell\VSCode")
    if ($config['explorer']['add_open_with_code']) {
        if (-not $codePath) {
            Write-Skipped "explorer.add_open_with_code" "VS Code executable not found on system"
        } elseif (-not $hasVsCodeMenu) {
            Register-PlannedChange -Category "explorer" -SettingName "add_open_with_code" -CurrentValue "<none>" -DesiredValue "Add Open with Code to context menu" -AffectsExplorer $false -Arguments @($codePath) -Action {
                param($cp)
                Set-UserContextMenu -SubKeyPath "Software\Classes\Directory\Background\shell\VSCode" -MenuText "Open with Code" -IconPath $cp -CommandStr "`"$cp`" `"%V`""
                Set-UserContextMenu -SubKeyPath "Software\Classes\Directory\shell\VSCode" -MenuText "Open with Code" -IconPath $cp -CommandStr "`"$cp`" `"%1`""
                Set-UserContextMenu -SubKeyPath "Software\Classes\*\shell\VSCode" -MenuText "Open with Code" -IconPath $cp -CommandStr "`"$cp`" `"%1`""
                Set-UserContextMenu -SubKeyPath "Software\Classes\Drive\shell\VSCode" -MenuText "Open with Code" -IconPath $cp -CommandStr "`"$cp`" `"%1`""
            }
        } else {
            Write-Unchanged "explorer.add_open_with_code" "Registered"
        }
    } else {
        if ($hasVsCodeMenu) {
            Register-PlannedChange -Category "explorer" -SettingName "add_open_with_code" -CurrentValue "Registered" -DesiredValue "Remove Open with Code from context menu" -AffectsExplorer $false -Action {
                Remove-UserContextMenu -SubKeyPath "Software\Classes\Directory\Background\shell\VSCode"
                Remove-UserContextMenu -SubKeyPath "Software\Classes\Directory\shell\VSCode"
                Remove-UserContextMenu -SubKeyPath "Software\Classes\*\shell\VSCode"
                Remove-UserContextMenu -SubKeyPath "Software\Classes\Drive\shell\VSCode"
            }
        } else {
            Write-Unchanged "explorer.add_open_with_code" "Not Registered"
        }
    }
}

if ($null -ne $config['explorer']['add_open_in_terminal']) {
    $wtPath = Find-WindowsTerminalPath
    $hasWtMenu = (Test-Path -LiteralPath "HKCU:\Software\Classes\Directory\Background\shell\wt")
    if ($config['explorer']['add_open_in_terminal']) {
        if (-not $hasWtMenu) {
            Register-PlannedChange -Category "explorer" -SettingName "add_open_in_terminal" -CurrentValue "<none>" -DesiredValue "Add Open in Windows Terminal to context menu" -AffectsExplorer $false -Arguments @($wtPath) -Action {
                param($wp)
                Set-UserContextMenu -SubKeyPath "Software\Classes\Directory\Background\shell\wt" -MenuText "Open in Windows Terminal" -IconPath $wp -CommandStr "`"$wp`" -d `"%V`""
                Set-UserContextMenu -SubKeyPath "Software\Classes\Directory\shell\wt" -MenuText "Open in Windows Terminal" -IconPath $wp -CommandStr "`"$wp`" -d `"%1`""
                Set-UserContextMenu -SubKeyPath "Software\Classes\Drive\shell\wt" -MenuText "Open in Windows Terminal" -IconPath $wp -CommandStr "`"$wp`" -d `"%1`""
            }
        } else {
            Write-Unchanged "explorer.add_open_in_terminal" "Registered"
        }
    } else {
        if ($hasWtMenu) {
            Register-PlannedChange -Category "explorer" -SettingName "add_open_in_terminal" -CurrentValue "Registered" -DesiredValue "Remove Open in Windows Terminal from context menu" -AffectsExplorer $false -Action {
                Remove-UserContextMenu -SubKeyPath "Software\Classes\Directory\Background\shell\wt"
                Remove-UserContextMenu -SubKeyPath "Software\Classes\Directory\shell\wt"
                Remove-UserContextMenu -SubKeyPath "Software\Classes\Drive\shell\wt"
            }
        } else {
            Write-Unchanged "explorer.add_open_in_terminal" "Not Registered"
        }
    }
}

if ($null -ne $config['explorer']['enable_taskbar_end_task']) {
    if (-not $script:IsWindows11_23H2) {
        Write-Skipped "explorer.enable_taskbar_end_task" "Requires Windows 11 23H2 (Build 22631+) or newer"
    } else {
        $endTaskVal = if ($config['explorer']['enable_taskbar_end_task']) { 1 } else { 0 }
        Check-RegChange -Category "explorer" -SettingName "enable_taskbar_end_task" -RegPath "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\TaskbarDeveloperSettings" -ValName "TaskbarEndTask" -DesiredValue $endTaskVal
    }
}

if ($null -ne $config['explorer']['disable_search_highlights']) {
    $searchHighVal = if ($config['explorer']['disable_search_highlights']) { 0 } else { 1 }
    Check-RegChange -Category "explorer" -SettingName "disable_search_highlights" -RegPath "HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings" -ValName "IsDynamicSearchBoxEnabled" -DesiredValue $searchHighVal
}

if ($null -ne $config['explorer']['disable_store_app_prompt']) {
    $storePromptVal = if ($config['explorer']['disable_store_app_prompt']) { 1 } else { 0 }
    Check-RegChange -Category "explorer" -SettingName "disable_store_app_prompt" -RegPath "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer" -ValName "NoUseStoreOpenWith" -DesiredValue $storePromptVal
}

if ($null -ne $config['explorer']['disable_lock_screen_ads']) {
    $lockAdVal = if ($config['explorer']['disable_lock_screen_ads']) { 0 } else { 1 }
    Check-RegChange -Category "explorer" -SettingName "lock_screen_overlay" -RegPath "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -ValName "RotatingLockScreenOverlayEnabled" -DesiredValue $lockAdVal
    Check-RegChange -Category "explorer" -SettingName "lock_screen_sub" -RegPath "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -ValName "SubscribedContent-338387Enabled" -DesiredValue $lockAdVal
}

if ($null -ne $config['explorer']['disable_snap_assist_popups']) {
    $snapVal = if ($config['explorer']['disable_snap_assist_popups']) { 0 } else { 1 }
    Check-RegChange -Category "explorer" -SettingName "snap_assist" -RegPath "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -ValName "SnapAssist" -DesiredValue $snapVal
    Check-RegChange -Category "explorer" -SettingName "snap_assist_flyout" -RegPath "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -ValName "EnableSnapAssistFlyout" -DesiredValue $snapVal
    Check-RegChange -Category "explorer" -SettingName "snap_bar" -RegPath "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -ValName "EnableSnapBar" -DesiredValue $snapVal
}

if ($null -ne $config['explorer']['disable_mouse_sticky_corners']) {
    $cornerVal = if ($config['explorer']['disable_mouse_sticky_corners']) { 0 } else { 6 }
    Check-RegChange -Category "explorer" -SettingName "mouse_sticky_corners" -RegPath "HKCU:\Control Panel\Desktop" -ValName "MouseCornerClipLength" -DesiredValue $cornerVal
}


# -------------------------------------------------------------
# 3. Startup Speed & Performance
# -------------------------------------------------------------
Write-Step "Inspecting Startup & System Performance Settings..."

if ($null -ne $config['performance']['disable_startup_delay']) {
    $delayVal = if ($config['performance']['disable_startup_delay']) { 0 } else { 1 }
    Check-RegChange -Category "performance" -SettingName "startup_delay" -RegPath "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize" -ValName "StartupDelayInMSec" -DesiredValue $delayVal
}

if ($null -ne $config['performance']['disable_edge_background_tasks']) {
    $edgeVal = if ($config['performance']['disable_edge_background_tasks']) { 0 } else { 1 }
    Check-RegChange -Category "performance" -SettingName "edge_startup_boost" -RegPath "HKLM:\SOFTWARE\Policies\Microsoft\Edge" -ValName "StartupBoostEnabled" -DesiredValue $edgeVal
    Check-RegChange -Category "performance" -SettingName "edge_background_mode" -RegPath "HKLM:\SOFTWARE\Policies\Microsoft\Edge" -ValName "BackgroundModeEnabled" -DesiredValue $edgeVal
}

if ($null -ne $config['performance']['disable_fast_startup']) {
    $fastStartVal = if ($config['performance']['disable_fast_startup']) { 0 } else { 1 }
    Check-RegChange -Category "performance" -SettingName "disable_fast_startup" -RegPath "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power" -ValName "HiberbootEnabled" -DesiredValue $fastStartVal
}

if ($config['performance']['unlock_ultimate_performance']) {
    $isUnlocked = Test-UltimatePerformanceUnlocked
    if (-not $isUnlocked) {
        Register-PlannedChange -Category "performance" -SettingName "unlock_ultimate_performance" -CurrentValue "Hidden" -DesiredValue "Unlocked" -AffectsExplorer $false -Action {
            powercfg -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 | Out-Null
        }
    } else {
        Write-Unchanged "performance.unlock_ultimate_performance" "Unlocked"
    }
}

# -------------------------------------------------------------
# 4. UI Cleanliness & De-bloat
# -------------------------------------------------------------
Write-Step "Inspecting UI Cleanliness & De-bloat Settings..."

if ($null -ne $config['ui_debloat']['hide_taskbar_copilot_button']) {
    if (-not $script:IsWindows11) {
        Write-Skipped "ui_debloat.hide_copilot" "Windows 11 taskbar feature"
    } else {
        $copilotVal = if ($config['ui_debloat']['hide_taskbar_copilot_button']) { 0 } else { 1 }
        Check-RegChange -Category "ui_debloat" -SettingName "hide_copilot" -RegPath "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -ValName "ShowCopilotButton" -DesiredValue $copilotVal
    }
}

if ($null -ne $config['ui_debloat']['hide_taskbar_task_view']) {
    $taskViewVal = if ($config['ui_debloat']['hide_taskbar_task_view']) { 0 } else { 1 }
    Check-RegChange -Category "ui_debloat" -SettingName "hide_task_view" -RegPath "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -ValName "ShowTaskViewButton" -DesiredValue $taskViewVal
}

if ($null -ne $config['ui_debloat']['hide_taskbar_widgets']) {
    if (-not $script:IsWindows11) {
        Write-Skipped "ui_debloat.hide_widgets" "Windows 11 taskbar feature"
    } else {
        $widgetsVal = if ($config['ui_debloat']['hide_taskbar_widgets']) { 0 } else { 1 }
        Check-RegChange -Category "ui_debloat" -SettingName "hide_widgets" -RegPath "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -ValName "TaskbarDa" -DesiredValue $widgetsVal
    }
}

if ($null -ne $config['ui_debloat']['silence_tips_and_suggestions']) {
    $tipsVal = if ($config['ui_debloat']['silence_tips_and_suggestions']) { 0 } else { 1 }
    $cdm = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
    Check-RegChange -Category "ui_debloat" -SettingName "silence_suggestions_338388" -RegPath $cdm -ValName "SubscribedContent-338388Enabled" -DesiredValue $tipsVal
    Check-RegChange -Category "ui_debloat" -SettingName "silence_suggestions_338389" -RegPath $cdm -ValName "SubscribedContent-338389Enabled" -DesiredValue $tipsVal
    Check-RegChange -Category "ui_debloat" -SettingName "silence_suggestions_353694" -RegPath $cdm -ValName "SubscribedContent-353694Enabled" -DesiredValue $tipsVal
    Check-RegChange -Category "ui_debloat" -SettingName "silence_suggestions_353696" -RegPath $cdm -ValName "SubscribedContent-353696Enabled" -DesiredValue $tipsVal
    Check-RegChange -Category "ui_debloat" -SettingName "soft_landing" -RegPath $cdm -ValName "SoftLandingEnabled" -DesiredValue $tipsVal
    Check-RegChange -Category "ui_debloat" -SettingName "system_pane_suggestions" -RegPath $cdm -ValName "SystemPaneSuggestionsEnabled" -DesiredValue $tipsVal
}

# Bloatware App Removal
if ($config['ui_debloat']['remove_bloatware_apps'] -and $config['ui_debloat']['bloatware_list']) {
    $appsToRemove = $config['ui_debloat']['bloatware_list']
    foreach ($appPkg in $appsToRemove) {
        $installed = Get-AppxPackage -Name $appPkg -ErrorAction SilentlyContinue
        if ($installed) {
            Register-PlannedChange -Category "ui_debloat" -SettingName "remove_app" -CurrentValue "$appPkg (installed)" -DesiredValue "Uninstall" -AffectsExplorer $false -Arguments @($appPkg) -Action {
                param($pkg)
                $target = Get-AppxPackage -Name $pkg -ErrorAction SilentlyContinue
                if ($target) { $target | Remove-AppxPackage -ErrorAction SilentlyContinue }
            }
        } else {
            Write-Unchanged "ui_debloat.remove_app" "$appPkg (not installed)"
        }
    }
}

if ($null -ne $config['ui_debloat']['disable_sticky_keys_popup']) {
    $skFlags = Get-RegValSafe -KeyPath "HKCU:\Control Panel\Accessibility\StickyKeys" -ValName "Flags"
    $isCurrentlyDisabled = if ($skFlags) { (([int]$skFlags) -band 4) -eq 0 } else { $false }
    if ($config['ui_debloat']['disable_sticky_keys_popup']) {
        if (-not $isCurrentlyDisabled) {
            $displayOld = if ($skFlags) { "Enabled (Flags=$skFlags)" } else { "Enabled (Default)" }
            Register-PlannedChange -Category "ui_debloat" -SettingName "disable_sticky_keys_popup" -CurrentValue $displayOld -DesiredValue "Disabled (No Popups)" -AffectsExplorer $false -Action {
                Set-RegValSafe -KeyPath "HKCU:\Control Panel\Accessibility\StickyKeys" -ValName "Flags" -Value "506" -Type "String"
                Set-RegValSafe -KeyPath "HKCU:\Control Panel\Accessibility\ToggleKeys" -ValName "Flags" -Value "58" -Type "String"
                Set-RegValSafe -KeyPath "HKCU:\Control Panel\Accessibility\Keyboard Response" -ValName "Flags" -Value "122" -Type "String"
            }
        } else {
            Write-Unchanged "ui_debloat.disable_sticky_keys_popup" "Disabled (No Popups)"
        }
    } else {
        if ($isCurrentlyDisabled) {
            Register-PlannedChange -Category "ui_debloat" -SettingName "disable_sticky_keys_popup" -CurrentValue "Disabled" -DesiredValue "Enabled (Default)" -AffectsExplorer $false -Action {
                Set-RegValSafe -KeyPath "HKCU:\Control Panel\Accessibility\StickyKeys" -ValName "Flags" -Value "510" -Type "String"
                Set-RegValSafe -KeyPath "HKCU:\Control Panel\Accessibility\ToggleKeys" -ValName "Flags" -Value "62" -Type "String"
                Set-RegValSafe -KeyPath "HKCU:\Control Panel\Accessibility\Keyboard Response" -ValName "Flags" -Value "126" -Type "String"
            }
        } else {
            Write-Unchanged "ui_debloat.disable_sticky_keys_popup" "Enabled (Default)"
        }
    }
}

# -------------------------------------------------------------
# 5. Developer & Terminal Ergonomics
# -------------------------------------------------------------
Write-Step "Inspecting Developer & Terminal Ergonomics..."

if ($null -ne $config['developer']['enable_long_paths']) {
    $longVal = if ($config['developer']['enable_long_paths']) { 1 } else { 0 }
    Check-RegChange -Category "developer" -SettingName "enable_long_paths" -RegPath "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" -ValName "LongPathsEnabled" -DesiredValue $longVal
}

if ($config['developer']['configure_git_autocrlf']) {
    if (Get-Command git -ErrorAction SilentlyContinue) {
        $currCrlf = (git config --global core.autocrlf 2>$null)
        if ($currCrlf -ne 'true') {
            $displayOld = if ($currCrlf) { $currCrlf } else { "<none>" }
            Register-PlannedChange -Category "developer" -SettingName "git_autocrlf" -CurrentValue $displayOld -DesiredValue "true" -AffectsExplorer $false -Action {
                git config --global core.autocrlf true
            }
        } else {
            Write-Unchanged "developer.git_autocrlf" "true"
        }
    }
}

# Developer Aliases and PSReadLine in PowerShell Profiles
if ($config['developer']['enable_powershell_shortcuts']) {
    $devAliasMarkerStart = "# >>> Sane Windows Developer Ergonomics >>>"
    $devAliasMarkerEnd   = "# <<< Sane Windows Developer Ergonomics <<<"
    $legacyMarkerStart   = "# >>> Useful Setup Developer Ergonomics >>>"
    $legacyMarkerEnd     = "# <<< Useful Setup Developer Ergonomics <<<"

    $copyPasteHandlers = ""
    if ($config['developer']['require_ctrl_shift_copy_paste']) {
        $copyPasteHandlers = @"

        # Require Ctrl+Shift+C and Ctrl+Shift+V for Copy & Paste
        Set-PSReadLineKeyHandler -Chord 'Ctrl+Shift+c', 'Ctrl+Shift+C' -Function Copy -ErrorAction SilentlyContinue
        Set-PSReadLineKeyHandler -Chord 'Ctrl+Shift+v', 'Ctrl+Shift+V' -Function Paste -ErrorAction SilentlyContinue
        Set-PSReadLineKeyHandler -Chord 'Ctrl+v' -ScriptBlock { } -ErrorAction SilentlyContinue
        Set-PSReadLineKeyHandler -Chord 'Ctrl+c' -Function CancelLine -ErrorAction SilentlyContinue
"@
    }

    $devAliasSnippet = @"
# >>> Sane Windows Developer Ergonomics >>>
# Shortcuts & Aliases
if (-not (Get-Command which -ErrorAction SilentlyContinue)) {
    Set-Alias -Name which -Value Get-Command -Scope Global
}
if (-not (Get-Command ll -ErrorAction SilentlyContinue)) {
    function global:ll { Get-ChildItem -Path `$args }
}

# PSReadLine history prediction autocomplete & keybindings
if (Get-Module -ListAvailable -Name PSReadLine) {
    try {
        Set-PSReadLineOption -PredictionSource History -ErrorAction SilentlyContinue$copyPasteHandlers
    } catch { }
}
# <<< Sane Windows Developer Ergonomics <<<
"@

    $docs = [Environment]::GetFolderPath('MyDocuments')
    $psProfiles = @(
        (Join-Path $docs "WindowsPowerShell\Microsoft.PowerShell_profile.ps1"),
        (Join-Path $docs "PowerShell\Microsoft.PowerShell_profile.ps1")
    )

    foreach ($p in $psProfiles) {
        $pContent = if (Test-Path $p) { Get-Content $p -Raw } else { "" }
        if ($null -eq $pContent) { $pContent = "" }

        $needsUpdate = $false
        if ($pContent -notmatch [regex]::Escape($devAliasMarkerStart)) {
            $needsUpdate = $true
        } elseif ($config['developer']['require_ctrl_shift_copy_paste'] -and ($pContent -notmatch "Set-PSReadLineKeyHandler -Chord 'Ctrl\+Shift\+c'")) {
            $needsUpdate = $true
        }

        if ($needsUpdate) {
            $profName = Split-Path $p -Leaf
            Register-PlannedChange -Category "developer" -SettingName "powershell_shortcuts" -CurrentValue "<needs update>" -DesiredValue "Inject shortcuts into $profName" -AffectsExplorer $false -Arguments @($p, $devAliasSnippet, $devAliasMarkerStart, $devAliasMarkerEnd, $legacyMarkerStart, $legacyMarkerEnd) -Action {
                param($prof, $snip, $startMarker, $endMarker, $legStart, $legEnd)
                $pDir = Split-Path -Parent $prof
                if (-not (Test-Path $pDir)) { New-Item -ItemType Directory -Path $pDir -Force | Out-Null }
                $existing = if (Test-Path $prof) { Get-Content $prof -Raw } else { "" }
                if ($null -eq $existing) { $existing = "" }

                if ($existing -match [regex]::Escape($legStart)) {
                    $legPattern = "(?s)" + [regex]::Escape($legStart) + ".*?" + [regex]::Escape($legEnd)
                    $existing = [regex]::Replace($existing, $legPattern, "")
                }

                if ($existing -match [regex]::Escape($startMarker)) {
                    $pattern = "(?s)" + [regex]::Escape($startMarker) + ".*?" + [regex]::Escape($endMarker)
                    $newContent = [regex]::Replace($existing, $pattern, $snip)
                    Set-Content -Path $prof -Value $newContent -NoNewline
                } else {
                    $newP = if ($existing.Trim().Length -gt 0) { $existing.TrimEnd() + "`r`n`r`n" + $snip + "`r`n" } else { $snip + "`r`n" }
                    Set-Content -Path $prof -Value $newP -NoNewline
                }
            }
        } else {
            Write-Unchanged "developer.powershell_shortcuts" "$p (already active)"
        }
    }
}

# Terminal Duplicate Tab (Ctrl+Shift+D in same CWD)
if ($config['developer']['enable_terminal_duplicate_tab']) {
    $wtPath = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
    $isConfigured = $false
    if (Test-Path $wtPath) {
        $raw = Get-Content $wtPath -Raw
        if ($raw -match "duplicateTab") { $isConfigured = $true }
    }
    if (-not $isConfigured) {
        Register-PlannedChange -Category "developer" -SettingName "terminal_duplicate_tab" -CurrentValue "Default" -DesiredValue "Ctrl+Shift+D in same CWD" -AffectsExplorer $false -Arguments @($ScriptDir) -Action {
            param($sd)
            & "$sd\setup_duplicate_tab.ps1" -Quiet
        }
    } else {
        Write-Unchanged "developer.terminal_duplicate_tab" "Ctrl+Shift+D in same CWD"
    }
}

# Terminal Copy/Paste (Require Ctrl+Shift+C and Ctrl+Shift+V)
if ($null -ne $config['developer']['require_ctrl_shift_copy_paste']) {
    $isWtConfigured = Get-TerminalCopyPasteConfigured
    if ($config['developer']['require_ctrl_shift_copy_paste']) {
        if (-not $isWtConfigured) {
            Register-PlannedChange -Category "developer" -SettingName "terminal_ctrl_shift_copy_paste" -CurrentValue "Default (Ctrl+C/V)" -DesiredValue "Require Ctrl+Shift+C/V" -AffectsExplorer $false -Action {
                Set-TerminalCopyPasteKeybindings -Enable $true
            }
        } else {
            Write-Unchanged "developer.terminal_ctrl_shift_copy_paste" "Require Ctrl+Shift+C/V"
        }
    } else {
        if ($isWtConfigured) {
            Register-PlannedChange -Category "developer" -SettingName "terminal_ctrl_shift_copy_paste" -CurrentValue "Require Ctrl+Shift+C/V" -DesiredValue "Default (Ctrl+C/V)" -AffectsExplorer $false -Action {
                Set-TerminalCopyPasteKeybindings -Enable $false
            }
        } else {
            Write-Unchanged "developer.terminal_ctrl_shift_copy_paste" "Default (Ctrl+C/V)"
        }
    }
}

# -------------------------------------------------------------
# 6. Windows Update Control
# -------------------------------------------------------------
Write-Step "Inspecting Windows Update Control Settings..."

if ($config['windows_update']) {
    if ($null -ne $config['windows_update']['no_auto_restart_logged_on']) {
        $rebootVal = if ($config['windows_update']['no_auto_restart_logged_on']) { 1 } else { 0 }
        Check-RegChange -Category "windows_update" -SettingName "no_auto_restart_logged_on" -RegPath "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -ValName "NoAutoRebootWithLoggedOnUsers" -DesiredValue $rebootVal
    }

    if ($null -ne $config['windows_update']['exclude_drivers']) {
        $driverVal = if ($config['windows_update']['exclude_drivers']) { 1 } else { 0 }
        Check-RegChange -Category "windows_update" -SettingName "exclude_drivers" -RegPath "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate" -ValName "ExcludeWUDriversInQualityUpdate" -DesiredValue $driverVal
    }
}

# -------------------------------------------------------------
# Confirmation & Execution Phase
# -------------------------------------------------------------
if ($script:pendingChanges.Count -eq 0) {
    Write-Host "`n=================================================================" -ForegroundColor Cyan
    Write-Host " Setup Complete: All settings already match config.yaml." -ForegroundColor Green
    Write-Host " 0 changes needed." -ForegroundColor Green
    Write-Host "=================================================================`n" -ForegroundColor Cyan
    exit 0
}

Write-Header "Planned Changes Preview"
Write-Host " The following $($script:pendingChanges.Count) setting(s) will be modified:`n" -ForegroundColor Yellow

$displayTable = $script:pendingChanges | ForEach-Object {
    [PSCustomObject]@{
        Category     = $_.Category
        Setting      = $_.Setting
        CurrentValue = $_.CurrentValue
        DesiredValue = $_.DesiredValue
    }
}

$displayTable | Format-Table -Property @{Label="Category"; Expression={$_.Category}; Width=12}, @{Label="Setting"; Expression={$_.Setting}; Width=32}, @{Label="Current Value"; Expression={$_.CurrentValue}; Width=20}, @{Label="New Value"; Expression={$_.DesiredValue}; Width=25} -AutoSize

Write-Host "=================================================================`n" -ForegroundColor Cyan

if ($WhatIf) {
    Write-Host "[i] -WhatIf specified: Dry run preview complete. No changes were applied.`n" -ForegroundColor Cyan
    exit 0
}

# Interactive Confirmation
if (-not $Yes) {
    $choice = Read-Host "Apply these $($script:pendingChanges.Count) change(s)? [Y/n]"
    if ($choice -ne '' -and $choice -notmatch '^[Yy]$') {
        Write-Host "`n[x] Aborted by user. No changes were made.`n" -ForegroundColor Yellow
        exit 0
    }
}

Write-Host "`n[+] Applying changes..." -ForegroundColor Cyan

# Take safety snapshot before applying
$initialState = Get-CurrentSystemState
$snapshotFile = Save-Snapshot -State $initialState
Write-Success "Saved pre-change snapshot to: $snapshotFile"

$explorerNeedsRestart = $false
$appliedCount = 0

foreach ($change in $script:pendingChanges) {
    try {
        if ($change.Arguments -and $change.Arguments.Count -gt 0) {
            $argList = $change.Arguments
            & $change.Action @argList
        } else {
            & $change.Action
        }
        Write-Host "  [APPLIED] " -ForegroundColor Green -NoNewline
        Write-Host "$($change.Category)." -ForegroundColor Cyan -NoNewline
        Write-Host "$($change.Setting)" -ForegroundColor White -NoNewline
        Write-Host " : " -ForegroundColor Gray -NoNewline
        Write-Host "$($change.CurrentValue)" -ForegroundColor DarkGray -NoNewline
        Write-Host " -> " -ForegroundColor Gray -NoNewline
        Write-Host "$($change.DesiredValue)" -ForegroundColor Green
        $appliedCount++
        if ($change.AffectsExplorer) {
            $explorerNeedsRestart = $true
        }
    } catch {
        Write-Warn "Failed to apply $($change.Category).$($change.Setting): $_"
    }
}

if ($explorerNeedsRestart -and -not $NoExplorerRestart) {
    Write-Host "`n  [*] Restarting File Explorer to apply UI & Explorer changes..." -ForegroundColor Yellow
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1
}

Write-Host "`n=================================================================" -ForegroundColor Cyan
Write-Host " Setup complete! Successfully applied $appliedCount change(s)." -ForegroundColor Green
Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host " Snapshot saved: $snapshotFile" -ForegroundColor DarkGray
Write-Host " To revert any changes at any time, run: .\setup.ps1 -Revert`n" -ForegroundColor DarkGray
