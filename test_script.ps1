try {
    $null = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey("Software\NonExistentKey123")
    Write-Host "Success"
} catch {
    Write-Host "Error"
}
