Describe "clean-storage JSON Export" {
    BeforeAll {
        $code = Get-Content -Path "$PSScriptRoot/clean-storage.ps1" -Raw
        $script:ast = [System.Management.Automation.Language.Parser]::ParseInput($code, [ref]$null, [ref]$null)
        $funcs = $script:ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
        foreach ($f in $funcs) {
            Set-Item -Path "Function:global:$($f.Name)" -Value $f.Body.GetScriptBlock()
        }
    }

    It "Contains -ExportJson and -ExportPath parameters in the script param block" {
        $paramBlock = $script:ast.ParamBlock
        $paramNames = $paramBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath }

        $paramNames | Should -Contain "ExportJson"
        $paramNames | Should -Contain "ExportPath"
    }

    It "Exports machine-readable JSON to stdout when -ExportJson is specified" {
        $global:ExportJson = $true
        $global:ExportPath = ""
        $global:WhatIf = $false
        $global:Yes = $false
        $global:Interactive = $false

        function global:Collect-CleanupTargets {
            return @(
                [PSCustomObject]@{
                    Id          = "test-temp"
                    Name        = "Test Temp Cache"
                    DisplayPath = "C:\Test\Temp"
                    TargetPath  = "C:\Test\Temp"
                    ActionType  = "DeleteFiles"
                    SizeBytes   = 2097152L
                    Impact      = "Test impact warning"
                },
                [PSCustomObject]@{
                    Id            = "test-cmd"
                    Name          = "Test Command Target"
                    DisplayPath   = "docker prune"
                    ActionType    = "Command"
                    ActionCommand = "docker prune"
                    TargetPath    = ""
                    SizeBytes     = 0L
                    Impact        = "Docker impact warning"
                }
            )
        }

        $rawJson = Main
        $rawJson | Should -Not -BeNullOrEmpty

        $parsed = $rawJson | ConvertFrom-Json
        $parsed.Timestamp | Should -Not -BeNullOrEmpty
        $parsed.ComputerName | Should -Not -BeNullOrEmpty
        $parsed.TotalReclaimableBytes | Should -Be 2097152
        $parsed.FormattedTotalSize | Should -Be "2.00 MB"
        $parsed.Targets.Count | Should -Be 2

        $parsed.Targets[0].Id | Should -Be "test-temp"
        $parsed.Targets[0].Name | Should -Be "Test Temp Cache"
        $parsed.Targets[0].DisplayPath | Should -Be "C:\Test\Temp"
        $parsed.Targets[0].ActionType | Should -Be "DeleteFiles"
        $parsed.Targets[0].SizeBytes | Should -Be 2097152
        $parsed.Targets[0].PSObject.Properties.Name | Should -Not -Contain "Impact"
        $parsed.Targets[0].PSObject.Properties.Name | Should -Not -Contain "TargetPath"

        $parsed.Targets[1].Id | Should -Be "test-cmd"
        $parsed.Targets[1].ActionType | Should -Be "Command"
        $parsed.Targets[1].SizeBytes | Should -Be 0
    }

    It "Writes JSON report to file when -ExportPath is specified" {
        $tempExportFile = Join-Path ([System.IO.Path]::GetTempPath()) "audit_test_export.json"
        if (Test-Path $tempExportFile) { Remove-Item $tempExportFile -Force }

        $global:ExportJson = $true
        $global:ExportPath = $tempExportFile

        function global:Collect-CleanupTargets {
            return @(
                [PSCustomObject]@{
                    Id          = "sample-target"
                    Name        = "Sample Target"
                    DisplayPath = "C:\Sample"
                    TargetPath  = "C:\Sample"
                    ActionType  = "DeletePath"
                    SizeBytes   = 1024L
                    Impact      = "Sample Impact"
                }
            )
        }

        $stdout = Main
        $stdout | Should -BeNullOrEmpty

        Test-Path $tempExportFile | Should -Be $true
        $fileContent = Get-Content -LiteralPath $tempExportFile -Raw
        $parsed = $fileContent | ConvertFrom-Json
        $parsed.TotalReclaimableBytes | Should -Be 1024
        $parsed.Targets[0].Id | Should -Be "sample-target"

        Remove-Item $tempExportFile -Force
    }

    It "Does not perform deletion or prompting when -ExportJson is present" {
        $global:ExportJson = $true
        $global:ExportPath = ""
        $script:invokedCleanup = $false

        function global:Invoke-CleanupItem {
            $script:invokedCleanup = $true
            return 0L
        }

        function global:Collect-CleanupTargets {
            return @(
                [PSCustomObject]@{
                    Id          = "mock-target"
                    Name        = "Mock Target"
                    DisplayPath = "C:\Mock"
                    TargetPath  = "C:\Mock"
                    ActionType  = "DeleteFiles"
                    SizeBytes   = 5000L
                    Impact      = "Mock"
                }
            )
        }

        $null = Main
        $script:invokedCleanup | Should -Be $false
    }
}
