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

    Context "Collect-CleanupTargets" {
        BeforeEach {
            # Isolate environment variables to $TestDrive and mock Test-IsAdmin.
            $script:origTemp = $env:TEMP
            $script:origLocal = $env:LOCALAPPDATA
            $script:origUser = $env:USERPROFILE
            $script:origApp = $env:APPDATA
            $script:origSys = $env:SystemRoot

            $env:TEMP = Join-Path $TestDrive "temp"
            $env:LOCALAPPDATA = Join-Path $TestDrive "localappdata"
            $env:USERPROFILE = Join-Path $TestDrive "userprofile"
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
            $env:APPDATA = $script:origApp
            $env:SystemRoot = $script:origSys
        }

        It "Returns cleanup targets containing standard required properties" {
            $targets = Collect-CleanupTargets
            $targets.Count | Should -BeGreaterThan 0

            $expectedProps = @("Id", "Name", "DisplayPath", "ActionType", "SizeBytes", "Impact")
            foreach ($t in $targets) {
                foreach ($prop in $expectedProps) {
                    $propVal = $t.PSObject.Properties[$prop]
                    $propVal | Should -Not -BeNullOrEmpty
                }
            }
        }
    }
}
