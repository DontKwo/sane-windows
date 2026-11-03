<#
.SYNOPSIS
Diagnoses installed developer CLIs and versions.
#>

[CmdletBinding()]
param()

$tools = @(
    "git", "uv", "python", "pnpm", "npm", "cargo", "docker", "wsl"
)

$results = foreach ($tool in $tools) {
    # Check if tool is available in PATH
    $command = Get-Command $tool -ErrorAction SilentlyContinue

    if ($command) {
        $status = "Installed"
        try {
            # Execute and extract first line of version
            $output = & $tool --version 2>&1 | Out-String
            $version = ($output.Trim() -split '\r?\n')[0].Trim()
        } catch {
            $version = "Unknown"
        }
    } else {
        $status = "Missing"
        $version = "N/A"
    }

    [PSCustomObject]@{
        Tool    = $tool
        Status  = $status
        Version = $version
    }
}

# Output results in aligned table
$results | Format-Table -AutoSize
