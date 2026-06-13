param(
    [switch]$SkipDownload,
    [switch]$SkipBuild,
    [switch]$SkipMcpConfig,
    [switch]$Force,
    [string]$OpenCvDir = $env:OpenCV_DIR,
    [switch]$StrictVerify
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot '_common.ps1')

Write-Host @"

  Media MCP Server - Install
  ==========================
  Downloads ONNX models, FFmpeg and OpenCV runtime DLLs directly,
  builds MediaMCPServer.exe, configures MCP (HTTP).

"@ -ForegroundColor Cyan

Write-Host "Project root: $ProjectRoot" -ForegroundColor DarkGray

$dcc = Get-DelphiCompiler
if ($dcc) {
    Write-Host "  Delphi compiler: $dcc" -ForegroundColor Green
} else {
    Write-Warning "  dcc64.exe not found - build step will fail without RAD Studio."
}

if (Test-Path $OpenCvRoot) {
    Write-Host "  OpenCV Delphi sources: $OpenCvRoot" -ForegroundColor DarkGray
} else {
    Write-Warning "  OpenCV Delphi sources not found (needed for compile + wrapper build)"
}
foreach ($name in @('Delphi-FFMPEG', 'Delphi-ONVIF')) {
    $s = Join-Path $ParentDir $name
    if (Test-Path $s) {
        Write-Host "  Delphi sources: $s" -ForegroundColor DarkGray
    } else {
        Write-Warning "  Missing Delphi sources: $s (required for build)"
    }
}

if (-not $SkipDownload) {
    $dlArgs = @()
    if ($Force) { $dlArgs += '-Force' }
    if ($OpenCvDir) { $dlArgs += '-OpenCvDir'; $dlArgs += $OpenCvDir }
    & (Join-Path $PSScriptRoot 'download_deps.ps1') @dlArgs
} else {
    Write-Host "Skipping download (-SkipDownload)" -ForegroundColor Yellow
}

if (-not $SkipBuild) {
    & (Join-Path $PSScriptRoot 'build.ps1')
} else {
    Write-Host "Skipping build (-SkipBuild)" -ForegroundColor Yellow
}

Ensure-MediaDirs

if (-not $SkipMcpConfig) {
    & (Join-Path $PSScriptRoot 'setup_mcp.ps1')
} else {
    Write-Host "Skipping MCP config (-SkipMcpConfig)" -ForegroundColor Yellow
}

Write-Host ""
$verifyArgs = @()
if ($StrictVerify) { $verifyArgs += '-Strict' }
& (Join-Path $PSScriptRoot 'verify_install.ps1') @verifyArgs
