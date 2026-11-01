# We parse the script using AST instead of regex for better reliability
$scriptContent = Get-Content -Path "clean-storage.ps1" -Raw
$ast = [System.Management.Automation.Language.Parser]::ParseInput($scriptContent, [ref]$null, [ref]$null)

$functions = @("Format-ByteSize", "Get-PathSize", "Test-CommandExists", "Remove-FolderContentsSafely", "Get-OutdatedSubdirectories", "Invoke-CleanupItem", "Collect-CleanupTargets")

foreach ($func in $functions) {
    # Find the function definition AST
    $funcAst = $ast.Find({
        param($astNode)
        $astNode -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $astNode.Name -eq $func
    }, $true)

    if ($funcAst) {
        Set-Item -Path "Function:global:$func" -Value $funcAst.Body.GetScriptBlock()
    }
}

Describe "clean-storage.ps1 tests" {
    Context "Format-ByteSize" {
        It "formats 0 B correctly" {
            Format-ByteSize -Bytes 0 | Should -Be "0 B"
        }
        It "formats negative inputs correctly" {
            # Let's see what it actually evaluates to. Based on the script:
            # if ($Bytes -ge 1KB) is false, so it falls to return "{0} B" -f $Bytes
            Format-ByteSize -Bytes -1024 | Should -Be "-1024 B"
        }
        It "formats KB boundary correctly" {
            Format-ByteSize -Bytes 1024 | Should -Be "1.00 KB"
        }
        It "formats MB boundary correctly" {
            Format-ByteSize -Bytes 1048576 | Should -Be "1.00 MB"
        }
        It "formats GB boundary correctly" {
            Format-ByteSize -Bytes 1073741824 | Should -Be "1.00 GB"
        }
    }

    Context "Get-OutdatedSubdirectories" {
        BeforeAll {
            # TestDrive is natively provided by Pester
            New-Item -Path "$TestDrive\mockdir" -ItemType Directory -Force | Out-Null
            New-Item -Path "$TestDrive\mockdir\app-1.0.0" -ItemType Directory -Force | Out-Null
            New-Item -Path "$TestDrive\mockdir\app-1.0.1" -ItemType Directory -Force | Out-Null
            New-Item -Path "$TestDrive\mockdir\app-1.0.2" -ItemType Directory -Force | Out-Null
        }
        It "identifies all but the newest directory when sorted by name" {
            $result = Get-OutdatedSubdirectories -ParentPath "$TestDrive\mockdir" -Filter "app-*"
            $result.Count | Should -Be 2
            ($result -match "app-1.0.0").Count | Should -Be 1
            ($result -match "app-1.0.1").Count | Should -Be 1
            ($result -match "app-1.0.2").Count | Should -Be 0
        }
    }

    Context "Collect-CleanupTargets" {
        BeforeAll {
            $script:originalTemp = $env:TEMP
            $script:originalLocalAppData = $env:LOCALAPPDATA
            $script:originalAppData = $env:APPDATA
            $script:originalUserProfile = $env:USERPROFILE

            $env:TEMP = "$TestDrive\temp"
            $env:LOCALAPPDATA = "$TestDrive\localappdata"
            $env:APPDATA = "$TestDrive\appdata"
            $env:USERPROFILE = "$TestDrive\userprofile"
        }
        AfterAll {
            $env:TEMP = $script:originalTemp
            $env:LOCALAPPDATA = $script:originalLocalAppData
            $env:APPDATA = $script:originalAppData
            $env:USERPROFILE = $script:originalUserProfile
        }
        It "returns valid PSCustomObject schemas" {
            $targets = Collect-CleanupTargets

            if ($targets.Count -gt 0) {
                foreach ($t in $targets) {
                    $t.PSObject.Properties.Name -contains "Id" | Should -Be $true
                    $t.PSObject.Properties.Name -contains "Name" | Should -Be $true
                    $t.PSObject.Properties.Name -contains "DisplayPath" | Should -Be $true
                    $t.PSObject.Properties.Name -contains "ActionType" | Should -Be $true
                    $t.PSObject.Properties.Name -contains "SizeBytes" | Should -Be $true
                    $t.PSObject.Properties.Name -contains "Impact" | Should -Be $true
                }
            } else {
                New-Item -Path $env:TEMP -ItemType Directory -Force | Out-Null
                New-Item -Path "$env:TEMP\file.txt" -ItemType File -Value "hello" | Out-Null

                $targets = Collect-CleanupTargets
                $targets.Count | Should -BeGreaterThan 0
                foreach ($t in $targets) {
                    $t.PSObject.Properties.Name -contains "Id" | Should -Be $true
                    $t.PSObject.Properties.Name -contains "Name" | Should -Be $true
                    $t.PSObject.Properties.Name -contains "DisplayPath" | Should -Be $true
                    $t.PSObject.Properties.Name -contains "ActionType" | Should -Be $true
                    $t.PSObject.Properties.Name -contains "SizeBytes" | Should -Be $true
                    $t.PSObject.Properties.Name -contains "Impact" | Should -Be $true
                }
            }
        }
    }
}
