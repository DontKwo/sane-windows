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
