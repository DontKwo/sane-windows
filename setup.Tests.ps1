Describe "Get-RegistryTargets" {
    BeforeAll {
        # Extract Get-RegistryTargets from setup.ps1
        $code = Get-Content -Path "$PSScriptRoot/setup.ps1" -Raw
        $ast = [System.Management.Automation.Language.Parser]::ParseInput($code, [ref]$null, [ref]$null)
        $func = $ast.Find({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $args[0].Name -eq 'Get-RegistryTargets' }, $true)
        if ($func) {
            Invoke-Expression $func.Extent.Text
        } else {
            throw "Could not extract Get-RegistryTargets from setup.ps1"
        }
    }

    It "Returns expected categories" {
        $targets = Get-RegistryTargets
        $sections = $targets | ForEach-Object { $_.Section } | Select-Object -Unique

        $sections | Should -Contain "privacy"
        $sections | Should -Contain "explorer"
        $sections | Should -Contain "performance"
        $sections | Should -Contain "ui_debloat"
        $sections | Should -Contain "developer"
        $sections | Should -Contain "windows_update"
    }

    It "Returns expected keys and types (DWord vs String)" {
        $targets = Get-RegistryTargets

        # Test DWord conversion
        $telemetry = $targets | Where-Object { $_.Key -eq "disable_telemetry_hklm1" }
        $telemetry.Type | Should -Be "DWord"
        $telemetry.Path | Should -Be "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"

        # Test String conversion
        $stickyKeys = $targets | Where-Object { $_.Key -eq "sticky_keys" }
        $stickyKeys.Type | Should -Be "String"
        $stickyKeys.Name | Should -Be "Flags"
    }
}

Describe "Get-HumanReadableSettingDescription" {
    BeforeAll {
        $code = Get-Content -Path "$PSScriptRoot/setup.ps1" -Raw
        $ast = [System.Management.Automation.Language.Parser]::ParseInput($code, [ref]$null, [ref]$null)
        $func = $ast.Find({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $args[0].Name -eq 'Get-HumanReadableSettingDescription' }, $true)
        if ($func) {
            Invoke-Expression $func.Extent.Text
        } else {
            throw "Could not extract Get-HumanReadableSettingDescription from setup.ps1"
        }
    }

    It "Returns human-readable descriptions for configured settings" {
        $descExp = Get-HumanReadableSettingDescription -Category "explorer" -SettingName "show_file_extensions"
        $descExp | Should -Be "Show file extensions for known file types"

        $descPriv = Get-HumanReadableSettingDescription -Category "privacy" -SettingName "disable_telemetry_policies"
        $descPriv | Should -Be "Disable Windows telemetry policies"

        $descUI = Get-HumanReadableSettingDescription -Category "ui_debloat" -SettingName "classic_context_menu"
        $descUI | Should -Be "Restore classic Windows 10 right-click context menu"

        $descTab = Get-HumanReadableSettingDescription -Category "developer" -SettingName "show_cwd_in_tab_title"
        $descTab | Should -Be "Show current folder path in Terminal tab title"
    }

    It "Falls back gracefully for unknown settings" {
        $fallback = Get-HumanReadableSettingDescription -Category "custom" -SettingName "my_cool_setting"
        $fallback | Should -Be "my cool setting"
    }
}

Describe "Format-HumanReadableValue" {
    BeforeAll {
        $code = Get-Content -Path "$PSScriptRoot/setup.ps1" -Raw
        $ast = [System.Management.Automation.Language.Parser]::ParseInput($code, [ref]$null, [ref]$null)
        $func = $ast.Find({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $args[0].Name -eq 'Format-HumanReadableValue' }, $true)
        if ($func) {
            Invoke-Expression $func.Extent.Text
        } else {
            throw "Could not extract Format-HumanReadableValue from setup.ps1"
        }
    }

    It "Formats null and missing values as <none>" {
        Format-HumanReadableValue -Value $null | Should -Be "<none>"
    }

    It "Formats standard booleans and numeric 0/1 to true and false" {
        Format-HumanReadableValue -Value 1 | Should -Be "true"
        Format-HumanReadableValue -Value 0 | Should -Be "false"
        Format-HumanReadableValue -Value "1" | Should -Be "true"
        Format-HumanReadableValue -Value "0" | Should -Be "false"
        Format-HumanReadableValue -Value "True" | Should -Be "true"
        Format-HumanReadableValue -Value "False" | Should -Be "false"
    }

    It "Handles inverted registry values properly" {
        Format-HumanReadableValue -Value 0 -Category "explorer" -SettingName "show_file_extensions" | Should -Be "true"
        Format-HumanReadableValue -Value 1 -Category "explorer" -SettingName "show_file_extensions" | Should -Be "false"

        Format-HumanReadableValue -Value 1 -Category "explorer" -SettingName "launch_to_this_pc" | Should -Be "true"
        Format-HumanReadableValue -Value 2 -Category "explorer" -SettingName "launch_to_this_pc" | Should -Be "false"

        Format-HumanReadableValue -Value 4 -Category "privacy" -SettingName "disable_diagtrack_service" | Should -Be "true"
        Format-HumanReadableValue -Value 2 -Category "privacy" -SettingName "disable_diagtrack_service" | Should -Be "false"
    }

    It "Preserves descriptive strings or complex values" {
        Format-HumanReadableValue -Value "Windows 10 Classic Style" | Should -Be "Windows 10 Classic Style"
        Format-HumanReadableValue -Value "Uninstall" | Should -Be "Uninstall"
    }
}

Describe "Format-TabTitlePath and Terminal Tab Title CWD" {
    BeforeAll {
        $code = Get-Content -Path "$PSScriptRoot/setup.ps1" -Raw
        $ast = [System.Management.Automation.Language.Parser]::ParseInput($code, [ref]$null, [ref]$null)
        foreach ($fnName in @('Remove-JsonComments', 'Write-Warn', 'Get-PowerShellProfilePaths', 'Get-WindowsTerminalSettingsPaths', 'Format-TabTitlePath', 'Get-TerminalTabTitleConfigured', 'Set-TerminalTabTitleCwd')) {
            $func = $ast.Find({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $args[0].Name -eq $fnName }, $true)
            if ($func) {
                Invoke-Expression $func.Extent.Text
            } else {
                throw "Could not extract $fnName from setup.ps1"
            }
        }
    }

    It "Formats short paths under HOME with ~ and forward slashes without truncation" {
        Format-TabTitlePath -ProviderPath "C:\Users\Josh\projects" -HomePath "C:\Users\Josh" | Should -Be "~/projects"
        Format-TabTitlePath -ProviderPath "C:\Users\Josh" -HomePath "C:\Users\Josh" | Should -Be "~"
        Format-TabTitlePath -ProviderPath "C:\Users\Josh\" -HomePath "C:\Users\Josh" | Should -Be "~"
    }

    It "Truncates long paths from the left to keep the current folder visible" {
        Format-TabTitlePath -ProviderPath "C:\Users\Josh\projects\sane-windows" -HomePath "C:\Users\Josh" | Should -Be "...s/sane-windows"
        Format-TabTitlePath -ProviderPath "C:\Users\Joshua\projects" -HomePath "C:\Users\Josh" | Should -Be "...oshua/projects"
        Format-TabTitlePath -ProviderPath "C:\Users\Josh\projects\sane-windows" -HomePath "C:\Users\Josh" -MaxLength 21 | Should -Be "...jects/sane-windows"
        Format-TabTitlePath -ProviderPath "C:\Users\Josh\projects\sane-windows" -HomePath "C:\Users\Josh" -MaxLength 0 | Should -Be "~/projects/sane-windows"
    }

    It "Does not false-match sibling user directories or non-HOME drives" {
        Format-TabTitlePath -ProviderPath "C:\Users\Joshua\projects" -HomePath "C:\Users\Josh" -MaxLength 0 | Should -Be "C:/Users/Joshua/projects"
        Format-TabTitlePath -ProviderPath "D:\work\repo" -HomePath "C:\Users\Josh" | Should -Be "D:/work/repo"
        Format-TabTitlePath -ProviderPath "" -HomePath "C:\Users\Josh" | Should -Be ""
    }

    It "Installs, detects, upgrades, and removes CWD tab title hook across profiles and Terminal settings" {
        $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("sane_win_test_" + [guid]::NewGuid().ToString("N"))
        $null = New-Item -ItemType Directory -Path $tempDir -Force
        try {
            $prof1 = Join-Path $tempDir "WindowsPowerShell\Microsoft.PowerShell_profile.ps1"
            $prof2 = Join-Path $tempDir "PowerShell\Microsoft.PowerShell_profile.ps1"
            $wtJson = Join-Path $tempDir "settings.json"

            [System.IO.File]::WriteAllText($wtJson, '{"profiles":{"defaults":{"suppressApplicationTitle":true},"list":[{"name":"Windows PowerShell","suppressApplicationTitle":true}]}}', [System.Text.Encoding]::UTF8)

            Get-TerminalTabTitleConfigured -ProfilePaths @($prof1, $prof2) -WtSettingsPaths @($wtJson) | Should -Be $false

            Set-TerminalTabTitleCwd -Enable $true -ProfilePaths @($prof1, $prof2) -WtSettingsPaths @($wtJson)

            Get-TerminalTabTitleConfigured -ProfilePaths @($prof1, $prof2) -WtSettingsPaths @($wtJson) | Should -Be $true
            $profContent = Get-Content -LiteralPath $prof1 -Raw
            $profContent | Should -Match '\[Console\]::Write\("\$esc\]0;'
            $profContent | Should -Match '\$maxLen = 17'
            $parsedWt = Get-Content -LiteralPath $wtJson -Raw | ConvertFrom-Json
            $parsedWt.profiles.defaults.suppressApplicationTitle | Should -Be $false
            $parsedWt.profiles.list[0].suppressApplicationTitle | Should -Be $false

            $legacyBlock = "# >>> Sane Windows Tab Title CWD >>>`r`nfunction global:prompt { 'old' }`r`n# <<< Sane Windows Tab Title CWD <<<"
            [System.IO.File]::WriteAllText($prof1, $legacyBlock, [System.Text.Encoding]::UTF8)
            Get-TerminalTabTitleConfigured -ProfilePaths @($prof1, $prof2) -WtSettingsPaths @($wtJson) | Should -Be $false

            Set-TerminalTabTitleCwd -Enable $true -ProfilePaths @($prof1, $prof2) -WtSettingsPaths @($wtJson)
            Get-TerminalTabTitleConfigured -ProfilePaths @($prof1, $prof2) -WtSettingsPaths @($wtJson) | Should -Be $true

            Set-TerminalTabTitleCwd -Enable $false -ProfilePaths @($prof1, $prof2) -WtSettingsPaths @($wtJson)
            Get-TerminalTabTitleConfigured -ProfilePaths @($prof1, $prof2) -WtSettingsPaths @($wtJson) | Should -Be $false
        } finally {
            if (Test-Path -LiteralPath $tempDir) {
                Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
