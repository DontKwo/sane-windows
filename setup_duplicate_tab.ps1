<#
.SYNOPSIS
    Configures Windows Terminal and PowerShell so that Ctrl + Shift + D opens a new tab
    in the exact same directory as the current tab.

.DESCRIPTION
    By default in Windows Terminal, duplicating a tab (Ctrl + Shift + D) resets to the profile's
    default directory because PowerShell does not report its current working directory (CWD).
    
    This script:
    1. Ensures the PowerShell execution policy allows running profile scripts.
    2. Injects the OSC 9;9 escape sequence hook into PowerShell profiles (both Windows PowerShell
       5.1 and PowerShell 7+) so directory changes are immediately communicated to Windows Terminal.
    3. Preserves any existing prompt customization (Oh My Posh, Starship, posh-git, etc.).
    4. Configures Windows Terminal settings.json to explicitly bind Ctrl + Shift + D to duplicateTab.
    5. Configures Command Prompt (cmd.exe) prompt variable to report CWD as well.

.PARAMETER Uninstall
    Removes the CWD tracker from PowerShell profiles and restores Windows Terminal settings.

.EXAMPLE
    .\setup_duplicate_tab.ps1
    Installs and configures everything.

.EXAMPLE
    .\setup_duplicate_tab.ps1 -Uninstall
    Removes the setup and restores previous configurations.
#>

[CmdletBinding()]
param(
    [switch]$Uninstall,
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'

function Write-Step {
    param([string]$Message)
    if (-not $Quiet) { Write-Host "`n[+] $Message" -ForegroundColor Cyan }
}

function Write-Success {
    param([string]$Message)
    if (-not $Quiet) { Write-Host "    [OK] $Message" -ForegroundColor Green }
}

function Write-Info {
    param([string]$Message)
    if (-not $Quiet) { Write-Host "    [i] $Message" -ForegroundColor Gray }
}

function Write-Warn {
    param([string]$Message)
    if (-not $Quiet) { Write-Host "    [!] $Message" -ForegroundColor Yellow }
}

# --- Block Marker for PowerShell Profile ---
$MARKER_START = "# >>> Windows Terminal CWD Tracker (Duplicate Tab Support) >>>"
$MARKER_END   = "# <<< Windows Terminal CWD Tracker (Duplicate Tab Support) <<<"

# Using single-quoted here-string to preserve exact literal quotes and variables
$PROFILE_HOOK_SNIPPET = @'
# >>> Windows Terminal CWD Tracker (Duplicate Tab Support) >>>
if (-not $global:__WT_CWD_TRACKER_LOADED) {
    $global:__WT_CWD_TRACKER_LOADED = $true

    # Backup any existing prompt function once
    if (Test-Path Function:\prompt) {
        Copy-Item Function:\prompt Function:\__wt_cwd_original_prompt
    }

    function global:prompt {
        try {
            $loc = $ExecutionContext.SessionState.Path.CurrentLocation
            if ($loc.Provider.Name -eq 'FileSystem') {
                $esc = [char]27
                # Emit OSC 9;9 to notify Windows Terminal of current directory
                [Console]::Write("$esc]9;9;`"$($loc.ProviderPath)`"$esc\")
            }
        } catch { }

        if (Test-Path Function:\__wt_cwd_original_prompt) {
            __wt_cwd_original_prompt
        } else {
            "PS $($ExecutionContext.SessionState.Path.CurrentLocation)$('>' * ($nestedPromptLevel + 1)) "
        }
    }
}
# <<< Windows Terminal CWD Tracker (Duplicate Tab Support) <<<
'@

# Helper function to remove JSON comments safely without breaking strings (e.g., https://)
function Remove-JsonComments {
    param([string]$Json)
    $sb = New-Object System.Text.StringBuilder
    $inString = $false
    $escape = $false
    $i = 0
    $len = $Json.Length
    while ($i -lt $len) {
        $c = $Json[$i]
        if ($inString) {
            $null = $sb.Append($c)
            if ($escape) {
                $escape = $false
            } elseif ($c -eq '\') {
                $escape = $true
            } elseif ($c -eq '"') {
                $inString = $false
            }
            $i++
        } else {
            if ($c -eq '"') {
                $inString = $true
                $null = $sb.Append($c)
                $i++
            } elseif ($c -eq '/' -and ($i + 1) -lt $len -and $Json[$i + 1] -eq '/') {
                $i += 2
                while ($i -lt $len -and $Json[$i] -ne "`n" -and $Json[$i] -ne "`r") {
                    $i++
                }
            } elseif ($c -eq '/' -and ($i + 1) -lt $len -and $Json[$i + 1] -eq '*') {
                $i += 2
                while ($i + 1 -lt $len -and -not ($Json[$i] -eq '*' -and $Json[$i + 1] -eq '/')) {
                    $i++
                }
                $i += 2
            } else {
                $null = $sb.Append($c)
                $i++
            }
        }
    }
    return $sb.ToString()
}

# -------------------------------------------------------------
# 1. Execution Policy Setup
# -------------------------------------------------------------
Write-Step "Checking PowerShell ExecutionPolicy..."
try {
    $effectivePolicy = Get-ExecutionPolicy
    if ($Uninstall) {
        Write-Info "ExecutionPolicy left unchanged ($effectivePolicy)."
    } else {
        if ($effectivePolicy -in @('RemoteSigned', 'Unrestricted', 'Bypass')) {
            Write-Success "ExecutionPolicy is already '$effectivePolicy' (profile scripts can execute)."
        } else {
            Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force -WarningAction SilentlyContinue
            Write-Success "ExecutionPolicy for CurrentUser updated to RemoteSigned."
        }
    }
} catch {
    Write-Warn "Could not check/set ExecutionPolicy: $_"
}

# -------------------------------------------------------------
# 2. PowerShell Profiles Configuration
# -------------------------------------------------------------
Write-Step "Configuring PowerShell Profiles..."

$documentsDir = [Environment]::GetFolderPath('MyDocuments')
$profileCandidates = @()

# Common profile paths for Windows PowerShell (5.1) and PowerShell 7+
if ($PROFILE) {
    $profileCandidates += $PROFILE.ToString()
}
$profileCandidates += (Join-Path $documentsDir "WindowsPowerShell\Microsoft.PowerShell_profile.ps1")
$profileCandidates += (Join-Path $documentsDir "WindowsPowerShell\profile.ps1")
$profileCandidates += (Join-Path $documentsDir "PowerShell\Microsoft.PowerShell_profile.ps1")
$profileCandidates += (Join-Path $documentsDir "PowerShell\profile.ps1")

# Also ask pwsh if installed
if (Get-Command pwsh -ErrorAction SilentlyContinue) {
    try {
        $pwshP = & pwsh -NoProfile -Command '$PROFILE'
        if ($pwshP) { $profileCandidates += $pwshP.Trim() }
    } catch { }
}

$profilePaths = $profileCandidates | Select-Object -Unique

foreach ($pPath in $profilePaths) {
    $parentDir = Split-Path -Parent $pPath
    if (-not (Test-Path $parentDir)) {
        if (-not $Uninstall) {
            # Only create directory if it's the main host profile
            if ($pPath -like "*Microsoft.PowerShell_profile.ps1") {
                New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
            } else {
                continue
            }
        } else {
            continue
        }
    }

    $fileExisted = Test-Path $pPath
    $content = if ($fileExisted) { Get-Content $pPath -Raw } else { "" }
    if ($null -eq $content) { $content = "" }

    if ($Uninstall) {
        if ($content -match [regex]::Escape($MARKER_START)) {
            $pattern = "(?s)\r?\n?" + [regex]::Escape($MARKER_START) + ".*?" + [regex]::Escape($MARKER_END) + "\r?\n?"
            $newContent = [regex]::Replace($content, $pattern, "")
            Set-Content -Path $pPath -Value $newContent -NoNewline
            Write-Success "Removed CWD tracker from: $pPath"
        }
    } else {
        if ($content -match [regex]::Escape($MARKER_START)) {
            # Update existing block to latest snippet
            $pattern = "(?s)" + [regex]::Escape($MARKER_START) + ".*?" + [regex]::Escape($MARKER_END)
            $newContent = [regex]::Replace($content, $pattern, $PROFILE_HOOK_SNIPPET)
            Set-Content -Path $pPath -Value $newContent -NoNewline
            Write-Success "Updated CWD tracker in: $pPath"
        } else {
            # Create a backup if existing content
            if ($fileExisted -and $content.Trim().Length -gt 0) {
                Copy-Item -Path $pPath -Destination "$pPath.bak" -Force
                Write-Info "Created backup at: $pPath.bak"
            }
            $newContent = if ($content.Trim().Length -gt 0) {
                $content.TrimEnd() + "`r`n`r`n" + $PROFILE_HOOK_SNIPPET + "`r`n"
            } else {
                $PROFILE_HOOK_SNIPPET + "`r`n"
            }
            Set-Content -Path $pPath -Value $newContent -NoNewline
            Write-Success "Configured CWD tracker in: $pPath"
        }
    }
}

# -------------------------------------------------------------
# 3. Windows Terminal Settings Configuration
# -------------------------------------------------------------
Write-Step "Configuring Windows Terminal Settings..."

$wtSettingsPaths = @(
    "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json",
    "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json",
    "$env:LOCALAPPDATA\Microsoft\Windows Terminal\settings.json",
    "$env:LOCALAPPDATA\Microsoft\Windows Terminal Preview\settings.json"
)

$foundAnyWT = $false

foreach ($wtPath in $wtSettingsPaths) {
    if (-not (Test-Path $wtPath)) {
        continue
    }

    $foundAnyWT = $true
    Write-Info "Found Windows Terminal settings at: $wtPath"

    try {
        $raw = Get-Content -Path $wtPath -Raw
        $clean = Remove-JsonComments $raw
        $settings = $clean | ConvertFrom-Json

        # Create backup if not already present
        if (-not (Test-Path "$wtPath.bak")) {
            Copy-Item -Path $wtPath -Destination "$wtPath.bak" -Force
            Write-Info "Created settings backup at: $wtPath.bak"
        }

        if ($Uninstall) {
            # Remove duplicateTab action & keybinding if set by us
            if ($settings.actions) {
                $filteredActions = @(
                    foreach ($act in $settings.actions) {
                        if ($act.id -eq "User.duplicateTab") { continue }
                        $act
                    }
                )
                $settings.actions = $filteredActions
            }
            if ($settings.PSObject.Properties['keybindings']) {
                $filteredKb = @(
                    foreach ($kb in $settings.keybindings) {
                        if ($kb.id -eq "User.duplicateTab" -or ($kb.keys -eq "ctrl+shift+d" -and $kb.command -eq "duplicateTab")) { continue }
                        $kb
                    }
                )
                $settings.keybindings = $filteredKb
            }
            $jsonOut = $settings | ConvertTo-Json -Depth 20
            [System.IO.File]::WriteAllText($wtPath, $jsonOut, [System.Text.Encoding]::UTF8)
            Write-Success "Restored Windows Terminal keybindings."
        } else {
            # Find or create duplicateTab action
            $dupAction = $null
            if ($settings.actions) {
                foreach ($act in $settings.actions) {
                    if ($act.command -eq "duplicateTab" -or ($act.command -is [System.Management.Automation.PSCustomObject] -and $act.command.action -eq "duplicateTab")) {
                        $dupAction = $act
                        break
                    }
                }
            } else {
                $settings | Add-Member -NotePropertyName "actions" -NotePropertyValue @() -Force
            }

            if (-not $dupAction) {
                $dupAction = [PSCustomObject]@{
                    command = "duplicateTab"
                    id      = "User.duplicateTab"
                }
                $actList = [System.Collections.ArrayList]@($settings.actions)
                $null = $actList.Add($dupAction)
                $settings.actions = $actList.ToArray()
            }

            $actionId = if ($dupAction.id) { $dupAction.id } else { "User.duplicateTab" }
            if (-not $dupAction.id) {
                $dupAction | Add-Member -NotePropertyName "id" -NotePropertyValue $actionId -Force
            }

            # If keybindings property is used
            if ($settings.PSObject.Properties['keybindings']) {
                $kbList = [System.Collections.ArrayList]@()
                $bound = $false
                foreach ($kb in $settings.keybindings) {
                    if ($kb.keys -eq "ctrl+shift+d") {
                        $kb.id = $actionId
                        $bound = $true
                    }
                    $null = $kbList.Add($kb)
                }
                if (-not $bound) {
                    $newKb = [PSCustomObject]@{
                        id   = $actionId
                        keys = "ctrl+shift+d"
                    }
                    $null = $kbList.Add($newKb)
                }
                $settings.keybindings = $kbList.ToArray()
            } else {
                # Direct inline keys on action
                $dupAction | Add-Member -NotePropertyName "keys" -NotePropertyValue "ctrl+shift+d" -Force
            }

            $jsonOut = $settings | ConvertTo-Json -Depth 20
            [System.IO.File]::WriteAllText($wtPath, $jsonOut, [System.Text.Encoding]::UTF8)
            Write-Success "Bound 'Ctrl + Shift + D' to duplicateTab in: $wtPath"
        }
    } catch {
        Write-Warn "Error updating $wtPath : $_"
    }
}

if (-not $foundAnyWT) {
    Write-Warn "No Windows Terminal installation found in default paths."
    Write-Info "If Windows Terminal is installed later, run this script again to configure it."
}

# -------------------------------------------------------------
# 4. Command Prompt (cmd.exe) Environment Setup
# -------------------------------------------------------------
Write-Step "Configuring Command Prompt (cmd.exe) CWD reporting..."
try {
    $existingPrompt = [Environment]::GetEnvironmentVariable("PROMPT", [EnvironmentVariableTarget]::User)
    $cmdCwdSeq = '$e]9;9;$P$e\'

    if ($Uninstall) {
        if ($existingPrompt -and $existingPrompt.StartsWith($cmdCwdSeq)) {
            $restored = $existingPrompt.Substring($cmdCwdSeq.Length)
            if ($restored -eq '$p$g' -or [string]::IsNullOrEmpty($restored)) {
                [Environment]::SetEnvironmentVariable("PROMPT", $null, [EnvironmentVariableTarget]::User)
            } else {
                [Environment]::SetEnvironmentVariable("PROMPT", $restored, [EnvironmentVariableTarget]::User)
            }
            Write-Success "Removed CWD sequence from User PROMPT variable."
        }
    } else {
        if (-not $existingPrompt) {
            $newPrompt = "$cmdCwdSeq`$p`$g"
            [Environment]::SetEnvironmentVariable("PROMPT", $newPrompt, [EnvironmentVariableTarget]::User)
            Write-Success "Configured User PROMPT to report CWD for cmd.exe."
        } elseif (-not $existingPrompt.Contains('$e]9;9;')) {
            $newPrompt = "$cmdCwdSeq$existingPrompt"
            [Environment]::SetEnvironmentVariable("PROMPT", $newPrompt, [EnvironmentVariableTarget]::User)
            Write-Success "Prepended CWD reporting sequence to existing User PROMPT."
        } else {
            Write-Info "User PROMPT already includes CWD reporting sequence."
        }
    }
} catch {
    Write-Warn "Could not update User PROMPT environment variable: $_"
}

# -------------------------------------------------------------
# Summary
# -------------------------------------------------------------
if (-not $Quiet) {
    Write-Host "`n" + ("=" * 65) -ForegroundColor Green
    if ($Uninstall) {
        Write-Host " Setup removed successfully!" -ForegroundColor Green
        Write-Host " Restart any open Windows Terminal windows for changes to take effect." -ForegroundColor Gray
    } else {
        Write-Host " Setup complete! Ctrl + Shift + D is now ready to use." -ForegroundColor Green
        Write-Host " (" + ("=" * 63) + ")" -ForegroundColor Green
        Write-Host "`nHow to test:" -ForegroundColor Yellow
        Write-Host " 1. Open a new Windows Terminal window (or open a new tab)."
        Write-Host " 2. In PowerShell, navigate anywhere (e.g., cd C:\Users\Josh\projects)."
        Write-Host " 3. Press Ctrl + Shift + D."
        Write-Host " -> A duplicate tab will open in that EXACT same folder!`n" -ForegroundColor Cyan
    }
}

