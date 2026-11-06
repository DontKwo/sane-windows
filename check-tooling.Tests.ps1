Describe "check-tooling.ps1" {
    It "Diagnoses tools and outputs table" {
        $output = & "$PSScriptRoot/check-tooling.ps1" | Out-String
        $output | Should -Match "Tool"
        $output | Should -Match "Status"
        $output | Should -Match "Version"
        $output | Should -Match "git"
    }

    It "Supports -Tool filtering and -Install flag without error" {
        $output = & "$PSScriptRoot/check-tooling.ps1" -Tool git -Install 6>&1 | Out-String
        $output | Should -Match "git"
        $output | Should -Match "already installed"
    }

    It "Parses script without syntax errors using AST" {
        $code = Get-Content "$PSScriptRoot/check-tooling.ps1" -Raw
        $tokens = $null
        $errs = $null
        [void][System.Management.Automation.Language.Parser]::ParseInput($code, [ref]$tokens, [ref]$errs)
        $errs | Should -BeNullOrEmpty
    }
}
