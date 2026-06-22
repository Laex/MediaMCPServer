param(
    [switch]$Lite,
    [switch]$Strict
)

$ErrorActionPreference = "Continue"
. (Join-Path $PSScriptRoot '_common.ps1')

$checks = @()
$ok = 0; $warn = 0; $fail = 0

function Add-Check([string]$Name, [bool]$Pass, [string]$Detail, [string]$Severity = 'error') {
    $script:checks += [PSCustomObject]@{ Name = $Name; Pass = $Pass; Detail = $Detail; Severity = $Severity }
}

$ModelsDir = Join-Path $BinDir 'models'

Add-Check 'MediaMCPServer.exe' (Test-Path (Join-Path $BinDir 'MediaMCPServer.exe')) 'bin\MediaMCPServer.exe'
Add-Check 'opencv_delphi_wrapper.dll' (Test-Path (Join-Path $BinDir 'opencv_delphi_wrapper.dll')) 'OpenCV Delphi bridge'

if (-not $Lite) {
    foreach ($dll in @('avcodec-62.dll', 'avformat-62.dll', 'avutil-60.dll', 'swscale-9.dll')) {
        Add-Check $dll (Test-Path (Join-Path $BinDir $dll)) 'FFmpeg runtime' 'warn'
    }

    $opencvDll = Get-ChildItem $BinDir -Filter 'opencv_world*.dll' -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $opencvDll) {
        $opencvDll = Get-ChildItem $BinDir -Filter 'opencv_core*.dll' -ErrorAction SilentlyContinue | Select-Object -First 1
    }
    Add-Check 'OpenCV runtime DLL' ($null -ne $opencvDll) ($(if ($opencvDll) { $opencvDll.Name } else { 'opencv_world*.dll' }))

    foreach ($m in @('object_detection_yolox_2022nov.onnx', 'face_detection_yunet_2026may.onnx', 'face_recognition_sface_2021dec.onnx')) {
        Add-Check $m (Test-Path (Join-Path $ModelsDir $m)) "bin\models\$m" 'warn'
    }

    Add-Check 'backbone.onnx (TrackerNano)' (Test-Path (Join-Path $BinDir 'backbone.onnx')) 'bin\backbone.onnx' 'warn'
}

Write-Host "=== Media MCP Server - package verification ($(
    if ($Lite) { 'lite' } else { 'full' }
)) ===" -ForegroundColor Cyan
Write-Host "Root: $ProjectRoot"
Write-Host ""

foreach ($c in $checks) {
    $icon = if ($c.Pass) { '[OK]' } elseif ($c.Severity -eq 'warn') { '[!!]' } elseif ($c.Severity -eq 'info') { '[--]' } else { '[XX]' }
    $color = if ($c.Pass) { 'Green' } elseif ($c.Severity -eq 'error') { 'Red' } else { 'Yellow' }
    $line = '{0} {1}' -f $icon, $c.Name
    if ($c.Detail) { $line += " - $($c.Detail)" }
    Write-Host $line -ForegroundColor $color
    if ($c.Pass) { $ok++ } elseif ($c.Severity -eq 'error') { $fail++ } elseif ($c.Severity -eq 'warn') { $warn++ }
}

Write-Host ""
Write-Host ("Passed: {0}  Warnings: {1}  Failed: {2}" -f $ok, $warn, $fail) -ForegroundColor Cyan
if ($fail -gt 0) { exit 1 }
if ($Strict -and $warn -gt 0) { exit 1 }
exit 0
