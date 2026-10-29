BeforeAll {
    # Extract the function from setup.ps1 and load it
    $code = Get-Content -Path $PSScriptRoot/setup.ps1 -Raw
    $match = [regex]::Match($code, '(?s)function ConvertFrom-SimpleYaml\s*\{.*?\n    return \$root\n\}')
    if ($match.Success) {
        Invoke-Expression $match.Value
    } else {
        throw "Could not extract ConvertFrom-SimpleYaml from setup.ps1"
    }
}

Describe "ConvertFrom-SimpleYaml" {
    It "Parses simple YAML section" {
        $yaml = @"
section:
  key: value
"@
        $result = ConvertFrom-SimpleYaml -YamlContent $yaml
        $result.section.key | Should -Be "value"
    }

    It "Parses simple YAML list" {
        $yaml = @"
section:
  listkey:
    - value1
    - value2
"@
        $result = ConvertFrom-SimpleYaml -YamlContent $yaml
        $result.section.listkey[0] | Should -Be "value1"
        $result.section.listkey[1] | Should -Be "value2"
    }

    It "Parses simple YAML booleans and integers" {
        $yaml = @"
section:
  true_val: true
  false_val: false
  int_val: 42
  neg_int_val: -12
"@
        $result = ConvertFrom-SimpleYaml -YamlContent $yaml
        $result.section.true_val | Should -Be $true
        $result.section.false_val | Should -Be $false
        $result.section.int_val | Should -Be 42
        $result.section.neg_int_val | Should -Be -12
    }

    It "Ignores comments and empty lines" {
        $yaml = @"
# comment
section:

  key: value
  # another comment
"@
        $result = ConvertFrom-SimpleYaml -YamlContent $yaml
        $result.section.key | Should -Be "value"
    }

    It "Strips quotes from values" {
        $yaml = @"
section:
  key1: "value1"
  key2: 'value2'
  listkey:
    - "val3"
    - 'val4'
"@
        $result = ConvertFrom-SimpleYaml -YamlContent $yaml
        $result.section.key1 | Should -Be "value1"
        $result.section.key2 | Should -Be "value2"
        $result.section.listkey[0] | Should -Be "val3"
        $result.section.listkey[1] | Should -Be "val4"
    }
}
