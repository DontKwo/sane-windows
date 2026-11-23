[CmdletBinding()]
param(
    [string]$OutputPath = ""
)

$ErrorActionPreference = 'Stop'
$RootDir = Split-Path -Parent $PSScriptRoot
$GuiDir = Join-Path $RootDir "gui"
$BuildDir = Join-Path $RootDir "build"
$CsFile = Join-Path $PSScriptRoot "SaneWindowsHost.cs"
$AssetsZip = Join-Path $BuildDir "app-assets.zip"
$StageDir = Join-Path $BuildDir "gui-stage"

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $BuildDir "SaneWindows-Windows.exe"
}

if (-not (Test-Path (Join-Path $GuiDir "index.html"))) {
    throw "gui/index.html missing."
}

New-Item -ItemType Directory -Path $BuildDir -Force | Out-Null
if (Test-Path $StageDir) {
    Remove-Item -LiteralPath $StageDir -Recurse -Force
}
New-Item -ItemType Directory -Path $StageDir -Force | Out-Null
Copy-Item -Path (Join-Path $GuiDir "*") -Destination $StageDir -Recurse -Force
$IconPng = Join-Path $RootDir "assets\icon.png"
if (Test-Path $IconPng) {
    Copy-Item -LiteralPath $IconPng -Destination (Join-Path $StageDir "icon.png") -Force
}
if (Test-Path $AssetsZip) {
    Remove-Item -LiteralPath $AssetsZip -Force
}

Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::CreateFromDirectory($StageDir, $AssetsZip, [System.IO.Compression.CompressionLevel]::Optimal, $false)

$WinRoot = if ($env:WINDIR) { $env:WINDIR } else { $env:SystemRoot }
$CscCandidates = @(
    (Join-Path $WinRoot "Microsoft.NET\Framework64\v4.0.30319\csc.exe"),
    (Join-Path $WinRoot "Microsoft.NET\Framework\v4.0.30319\csc.exe")
)
$CscPath = $CscCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $CscPath) {
    throw "Could not locate .NET Framework csc.exe."
}

$BrandIco = Join-Path $RootDir "assets\icon.ico"
$CscArgs = @(
    "/nologo",
    "/optimize+",
    "/target:winexe",
    "/out:$OutputPath"
)
if (Test-Path $BrandIco) {
    $CscArgs += "/win32icon:$BrandIco"
}
$CscArgs += @(
    "/resource:$AssetsZip,app-assets.zip",
    "/reference:System.dll",
    "/reference:System.Core.dll",
    "/reference:System.IO.Compression.dll",
    "/reference:System.Net.Http.dll",
    "/reference:System.Web.Extensions.dll",
    $CsFile
)

& $CscPath @CscArgs
if ($LASTEXITCODE -ne 0) {
    throw "csc.exe failed with exit code $LASTEXITCODE"
}
Write-Host "Built $OutputPath"
