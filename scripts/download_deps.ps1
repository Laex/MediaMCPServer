param(
    [switch]$Force,
    [switch]$ModelsOnly,
    [switch]$FfmpegOnly,
    [switch]$OpenCvOnly,
    [string]$OpenCvDir = $env:OpenCV_DIR,
    [string]$WrapperSourceRoot = '',
    [string]$Cmake = ''
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot '_common.ps1')

Write-Host "Media MCP Server - download dependencies" -ForegroundColor White
Write-Host "Target bin: $BinDir" -ForegroundColor DarkGray

$commonArgs = @()
if ($Force) { $commonArgs += '-Force' }

if (-not $FfmpegOnly -and -not $OpenCvOnly) {
    & (Join-Path $PSScriptRoot 'download_models.ps1') @commonArgs
}

if (-not $ModelsOnly -and -not $OpenCvOnly) {
    & (Join-Path $PSScriptRoot 'download_ffmpeg_dll.ps1') @commonArgs
}

if (-not $ModelsOnly -and -not $FfmpegOnly) {
    $ocvArgs = @()
    if ($Force) { $ocvArgs += '-Force' }
    if ($OpenCvDir) { $ocvArgs += '-OpenCvDir'; $ocvArgs += $OpenCvDir }
    if ($WrapperSourceRoot) { $ocvArgs += '-WrapperSourceRoot'; $ocvArgs += $WrapperSourceRoot }
    if ($Cmake) { $ocvArgs += '-Cmake'; $ocvArgs += $Cmake }
    & (Join-Path $PSScriptRoot 'download_opencv_runtime.ps1') @ocvArgs
}

Write-Host ""
Write-Host "=== All downloads complete ===" -ForegroundColor Green
