$content = Get-Content -Raw setup.ps1

$oldFunc = @"
function Set-RegValSafe {
    param([string]`$KeyPath, [string]`$ValName, `$Value, [string]`$Type = "DWord")
    if (-not (Test-Path -LiteralPath `$KeyPath)) {
        if (`$KeyPath -like "HKCU:\*") {
            `$sub = `$KeyPath.Substring(5)
            [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey(`$sub) | Out-Null
        } elseif (`$KeyPath -like "HKLM:\*") {
            `$sub = `$KeyPath.Substring(5)
            [Microsoft.Win32.Registry]::LocalMachine.CreateSubKey(`$sub) | Out-Null
        } else {
            New-Item -Path `$KeyPath -Force -ErrorAction Stop | Out-Null
        }
    }
    Set-ItemProperty -LiteralPath `$KeyPath -Name `$ValName -Value `$Value -Type `$Type -Force -ErrorAction Stop | Out-Null
}
"@

$newFunc = @"
function Set-RegValSafe {
    param([string]`$KeyPath, [string]`$ValName, `$Value, [string]`$Type = "DWord")
    if (-not (Test-Path -LiteralPath `$KeyPath)) {
        try {
            if (`$KeyPath -like "HKCU:\*") {
                `$sub = `$KeyPath.Substring(5)
                `$key = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey(`$sub)
                if (`$key) { Write-Verbose "Created HKCU registry key: `$sub" }
            } elseif (`$KeyPath -like "HKLM:\*") {
                `$sub = `$KeyPath.Substring(5)
                `$key = [Microsoft.Win32.Registry]::LocalMachine.CreateSubKey(`$sub)
                if (`$key) { Write-Verbose "Created HKLM registry key: `$sub" }
            } else {
                `$key = New-Item -Path `$KeyPath -Force -ErrorAction Stop
                if (`$key) { Write-Verbose "Created registry path: `$KeyPath" }
            }
        } catch {
            Write-Warn "Failed to create registry key `$KeyPath : `$_"
            throw
        }
    }
    try {
        `$prop = Set-ItemProperty -LiteralPath `$KeyPath -Name `$ValName -Value `$Value -Type `$Type -Force -ErrorAction Stop
        if (`$prop) { Write-Verbose "Set registry value `$ValName at `$KeyPath" }
    } catch {
        Write-Warn "Failed to set registry value `$ValName at `$KeyPath : `$_"
        throw
    }
}
"@

$content = $content.Replace($oldFunc, $newFunc)
Set-Content -Path setup.ps1 -Value $content -NoNewline
