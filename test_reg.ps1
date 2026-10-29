$ErrorActionPreference = 'Stop'
$testKey = "HKCU:\Software\TestSaneWindows123"
Write-Host "Creating key..."
$key = New-Item -Path $testKey -Force
Write-Host "Key created: $($key -eq $null)"

Write-Host "Setting prop..."
$prop = Set-ItemProperty -LiteralPath $testKey -Name "TestVal" -Value 1 -Type DWord -Force
Write-Host "Prop set: $($prop -eq $null)"
Remove-Item -Path $testKey -Force
