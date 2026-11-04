Describe "clean-storage" {
    BeforeAll {
        # Parse clean-storage.ps1 using AST and extract target functions into session.
        $scriptPath = Join-Path $PSScriptRoot "clean-storage.ps1"
        $ast = [System.Management.Automation.Language.Parser]::ParseInput((Get-Content -Path $scriptPath -Raw), [ref]$null, [ref]$null)
        $requiredFuncs = @(
            "Format-ByteSize", "Get-PathSize", "Test-IsAdmin", "Test-CommandExists",
            "Remove-FolderContentsSafely", "Get-OutdatedSubdirectories", "Invoke-CleanupItem", "Collect-CleanupTargets"
        )
        $funcDefs = $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
        foreach ($name in $requiredFuncs) {
            $def = $funcDefs | Where-Object { $_.Name -eq $name }
            if (-not $def) {
                throw "Missing required function: $name"
            }
            Set-Item -Path "Function:global:$name" -Value $def.Body.GetScriptBlock()
        }
    }

    Context "Function extraction check" {
        It "Extracts all required functions" {
            $requiredFuncs = @(
                "Format-ByteSize", "Get-PathSize", "Test-IsAdmin", "Test-CommandExists",
                "Remove-FolderContentsSafely", "Get-OutdatedSubdirectories", "Invoke-CleanupItem", "Collect-CleanupTargets"
            )
            foreach ($name in $requiredFuncs) {
                (Get-Command -Name $name -ErrorAction SilentlyContinue) | Should -Not -BeNullOrEmpty
            }
        }
    }

    Context "Format-ByteSize" {
        It "Formats 0 bytes correctly" {
            Format-ByteSize -Bytes 0 | Should -Be "0 B"
        }

        It "Formats negative byte values correctly" {
            Format-ByteSize -Bytes -1024 | Should -Be "-1024 B"
        }

        It "Formats 1024 bytes as 1.00 KB" {
            Format-ByteSize -Bytes 1024 | Should -Be "1.00 KB"
        }

        It "Formats 1048576 bytes as 1.00 MB" {
            Format-ByteSize -Bytes 1048576 | Should -Be "1.00 MB"
        }

        It "Formats 1073741824 bytes as 1.00 GB" {
            Format-ByteSize -Bytes 1073741824 | Should -Be "1.00 GB"
        }
    }

    Context "Get-OutdatedSubdirectories" {
        It "Returns all but the newest subdirectories" {
            $baseDir = Join-Path $TestDrive "claude-apps"
            New-Item -ItemType Directory -Path (Join-Path $baseDir "app-1.0.0") -Force | Out-Null
            New-Item -ItemType Directory -Path (Join-Path $baseDir "app-1.0.1") -Force | Out-Null
            New-Item -ItemType Directory -Path (Join-Path $baseDir "app-1.0.2") -Force | Out-Null

            $outdated = Get-OutdatedSubdirectories -ParentPath $baseDir -Filter "app-*"
            $outdated.Count | Should -Be 2
            $outdated[0] | Should -Be (Join-Path $baseDir "app-1.0.0")
            $outdated[1] | Should -Be (Join-Path $baseDir "app-1.0.1")
        }
    }

    Context "Remove-FolderContentsSafely with -MinAgeDays" {
        It "Preserves newer files and deletes older files when MinAgeDays is set" {
            $testDir = Join-Path $TestDrive "minage-test"
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null

            # Create older and newer test files
            $oldFile = New-Item -ItemType File -Path (Join-Path $testDir "old.txt") -Force
            $newFile = New-Item -ItemType File -Path (Join-Path $testDir "new.txt") -Force
            $oldFile.LastWriteTime = (Get-Date).AddDays(-10)
            $newFile.LastWriteTime = (Get-Date).AddDays(-1)

            Remove-FolderContentsSafely -DirectoryPath $testDir -MinAgeDays 5 | Out-Null

            Test-Path $oldFile.FullName | Should -Be $false
            Test-Path $newFile.FullName | Should -Be $true
        }

        It "Deletes all files when MinAgeDays is 0" {
            $testDir = Join-Path $TestDrive "minage-test-zero"
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null

            # Create test files
            $file1 = New-Item -ItemType File -Path (Join-Path $testDir "file1.txt") -Force
            $file2 = New-Item -ItemType File -Path (Join-Path $testDir "file2.txt") -Force
            $file1.LastWriteTime = (Get-Date).AddDays(-10)
            $file2.LastWriteTime = (Get-Date).AddDays(-1)

            Remove-FolderContentsSafely -DirectoryPath $testDir -MinAgeDays 0 | Out-Null

            Test-Path $file1.FullName | Should -Be $false
            Test-Path $file2.FullName | Should -Be $false
        }
    }

    Context "Collect-CleanupTargets" {
        BeforeEach {
            # Isolate environment variables to $TestDrive and mock Test-IsAdmin.
            $script:origTemp = $env:TEMP
            $script:origLocal = $env:LOCALAPPDATA
            $script:origUser = $env:USERPROFILE
            $script:origApp = $env:APPDATA
            $script:origProgramData = $env:ProgramData
            $script:origSys = $env:SystemRoot

            $env:TEMP = Join-Path $TestDrive "temp"
            $env:LOCALAPPDATA = Join-Path $TestDrive "localappdata"
            $env:USERPROFILE = Join-Path $TestDrive "userprofile"
            $env:ProgramData = Join-Path $TestDrive "programdata"
            $env:APPDATA = Join-Path $TestDrive "appdata"
            $env:SystemRoot = Join-Path $TestDrive "systemroot"

            New-Item -ItemType Directory -Path $env:TEMP -Force | Out-Null
            Set-Content -Path (Join-Path $env:TEMP "sample.tmp") -Value "temporary data"

            function global:Test-IsAdmin { return $false }
        }

        AfterEach {
            # Restore environment variables.
            $env:TEMP = $script:origTemp
            $env:LOCALAPPDATA = $script:origLocal
            $env:USERPROFILE = $script:origUser
            $env:ProgramData = $script:origProgramData
            $env:APPDATA = $script:origApp
            $env:SystemRoot = $script:origSys
        }

        It "Returns cleanup targets containing standard required properties" {
            $pathsToCreate = @(
                (Join-Path $env:LOCALAPPDATA "Google\Chrome\User Data\Default\Cache"),
                (Join-Path $env:LOCALAPPDATA "Microsoft\Edge\User Data\Default\Cache"),
                (Join-Path $env:LOCALAPPDATA "Mozilla\Firefox\Profiles"),
                (Join-Path $env:LOCALAPPDATA "uv\cache"),
                (Join-Path $env:LOCALAPPDATA "pip\cache"),
                (Join-Path $env:LOCALAPPDATA "npm-cache"),
                (Join-Path $env:USERPROFILE ".cargo\registry"),
                (Join-Path $env:USERPROFILE ".gradle\caches"),
                (Join-Path $env:LOCALAPPDATA "Microsoft\VisualStudio"),
                (Join-Path $env:LOCALAPPDATA "Microsoft\MSBuild")
            )
            foreach ($p in $pathsToCreate) {
                New-Item -ItemType Directory -Path $p -Force | Out-Null
                Set-Content -Path (Join-Path $p "test.txt") -Value "test"
            }
            function global:Test-CommandExists { return $true }
            $targets = Collect-CleanupTargets
            $targets.Count | Should -BeGreaterOrEqual 10

            $expectedProps = @("Id", "Name", "ActionType")
            foreach ($t in $targets) {
                foreach ($prop in $expectedProps) {
                    $propVal = $t.PSObject.Properties[$prop].Value
                    $propVal | Should -Not -BeNullOrEmpty
                }
            }
        }
    }
}

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

    It "Validates JSON schema against schema requirements" {
        $global:ExportJson = $true
        $global:ExportPath = ""

        function global:Collect-CleanupTargets {
            return @(
                [PSCustomObject]@{
                    Id          = "schema-test"
                    Name        = "Schema Test Target"
                    ActionType  = "Command"
                    SizeBytes   = 1024L
                }
            )
        }

        $rawJson = Main
        $parsed = $rawJson | ConvertFrom-Json

        $parsed.PSObject.Properties.Name | Should -Contain "Timestamp"
        $parsed.PSObject.Properties.Name | Should -Contain "Targets"
        $parsed.PSObject.Properties.Name | Should -Contain "TotalReclaimableBytes"

        foreach ($target in $parsed.Targets) {
            $target.PSObject.Properties.Name | Should -Contain "Id"
            $target.PSObject.Properties.Name | Should -Contain "Name"
            $target.PSObject.Properties.Name | Should -Contain "ActionType"
        }
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
