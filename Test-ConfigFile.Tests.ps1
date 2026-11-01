Describe "Test-ConfigFile" {
    BeforeAll {
        # Extract Write-Warn and Test-ConfigFile functions from setup.ps1 and load them
        $code = Get-Content -Path "$PSScriptRoot/setup.ps1" -Raw
        $ast = [System.Management.Automation.Language.Parser]::ParseInput($code, [ref]$null, [ref]$null)

        $warnFunc = $ast.Find({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $args[0].Name -eq 'Write-Warn' }, $true)
        if ($warnFunc) {
            Invoke-Expression $warnFunc.Extent.Text
        } else {
            throw "Could not extract Write-Warn from setup.ps1"
        }

        $configFunc = $ast.Find({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $args[0].Name -eq 'Test-ConfigFile' }, $true)
        if ($configFunc) {
            Invoke-Expression $configFunc.Extent.Text
        } else {
            throw "Could not extract Test-ConfigFile from setup.ps1"
        }

        $yamlFunc = $ast.Find({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $args[0].Name -eq 'ConvertFrom-SimpleYaml' }, $true)
        if ($yamlFunc) {
            Invoke-Expression $yamlFunc.Extent.Text
        }
    }

    It "Validates the real config.yaml with no warnings" {
        $realYaml = Get-Content -Path "$PSScriptRoot/config.yaml" -Raw
        $config = ConvertFrom-SimpleYaml -YamlContent $realYaml

        Mock Write-Warn {}

        $result = Test-ConfigFile -Config $config
        $result | Should -Be $true
        Should -Invoke -CommandName Write-Warn -Times 0
    }

    It "Returns true when Config is null or empty" {
        Mock Write-Warn {}

        $result1 = Test-ConfigFile -Config $null
        $result1 | Should -Be $true

        $result2 = Test-ConfigFile -Config @{}
        $result2 | Should -Be $true
        Should -Invoke -CommandName Write-Warn -Times 0
    }

    It "Detects unsupported keys within a valid section" {
        $config = @{
            privacy = @{
                disable_telemetry = $true
                unknown_option_typo = $true
            }
        }

        Mock Write-Warn {}

        $result = Test-ConfigFile -Config $config
        $result | Should -Be $false
        Should -Invoke -CommandName Write-Warn -Times 1 -ParameterFilter {
            $Text -eq "Unrecognized setting in config.yaml: [privacy] -> unknown_option_typo"
        }
    }

    It "Detects unknown sections with keys" {
        $config = @{
            unknown_section = @{
                some_key = $true
            }
        }

        Mock Write-Warn {}

        $result = Test-ConfigFile -Config $config
        $result | Should -Be $false
        Should -Invoke -CommandName Write-Warn -Times 1 -ParameterFilter {
            $Text -eq "Unrecognized setting in config.yaml: [unknown_section] -> some_key"
        }
    }

    It "Detects multiple unsupported keys across multiple sections" {
        $config = @{
            privacy = @{
                telemetry_typo = $true
            }
            explorer = @{
                explorer_typo = $false
            }
        }

        Mock Write-Warn {}

        $result = Test-ConfigFile -Config $config
        $result | Should -Be $false
        Should -Invoke -CommandName Write-Warn -Times 2
    }
}
