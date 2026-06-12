param(
    [string]$OpenCvDir = $env:OpenCV_DIR,
    [string]$WrapperSourceRoot = '',
    [string]$Cmake = '',
    [switch]$Force
)

# Backward-compatible entry point -> direct download / build script
$ErrorActionPreference = "Stop"
$argsList = @()
if ($OpenCvDir) { $argsList += '-OpenCvDir'; $argsList += $OpenCvDir }
if ($WrapperSourceRoot) { $argsList += '-WrapperSourceRoot'; $argsList += $WrapperSourceRoot }
if ($Cmake) { $argsList += '-Cmake'; $argsList += $Cmake }
if ($Force) { $argsList += '-Force' }
& (Join-Path $PSScriptRoot 'download_opencv_runtime.ps1') @argsList
