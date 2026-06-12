param(
    [switch]$DownloadDeps
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot '_common.ps1')

if ($DownloadDeps) {
    Write-Host "Downloading dependencies before build..." -ForegroundColor Cyan
    & (Join-Path $PSScriptRoot 'download_deps.ps1')
}

Write-Host "=== Building Media MCP Server ===" -ForegroundColor Cyan

$dcc = Get-DelphiCompiler
if (-not $dcc) {
    Write-Error "Delphi compiler (dcc64.exe or dcc32.exe) could not be found!"
}
Write-Host "Using compiler: $dcc" -ForegroundColor Green

New-Item -ItemType Directory -Force -Path $BinDir | Out-Null
New-Item -ItemType Directory -Force -Path $DcuDir | Out-Null

$parent = Split-Path $ProjectRoot -Parent
$searchPaths = @(
    (Join-Path $OpenCvRoot 'source'),
    (Join-Path $parent 'Delphi-FFMPEG\source'),
    (Join-Path $parent 'Delphi-ONVIF\src'),
    (Join-Path $parent 'Delphi-ONVIF\src\ThirdParty')
)
$searchPathStr = ($searchPaths -join ';')

$dpr = Join-Path $SrcDir 'MediaMCPServer.dpr'
Write-Host "Compiling $dpr ..." -ForegroundColor Cyan
Push-Location $SrcDir
try {
    & $dcc -B -Q -W "-E$BinDir" "-N$DcuDir" "-I$searchPathStr" "-U$searchPathStr" -NS"System;System.Win;Winapi;Vcl;Vcl.Imaging" MediaMCPServer.dpr
    if ($LASTEXITCODE -ne 0) { throw "dcc exited with code $LASTEXITCODE" }
} finally {
    Pop-Location
}

Write-Host "Compilation finished successfully!" -ForegroundColor Green

$modelsDest = Join-Path $BinDir 'models'
New-Item -ItemType Directory -Force -Path $modelsDest | Out-Null
$readmeSrc = Join-Path $ProjectRoot 'docs\models-readme.txt'
if (Test-Path $readmeSrc) {
    Copy-Item $readmeSrc (Join-Path $modelsDest 'readme.txt') -Force
}

$missingRuntime = -not (Test-Path (Join-Path $BinDir 'opencv_delphi_wrapper.dll')) -or
    -not (Get-ChildItem $BinDir -Filter 'avcodec-*.dll' -ErrorAction SilentlyContinue)
if ($missingRuntime) {
    Write-Host "Runtime DLLs missing in bin\ - run .\install.ps1 or .\scripts\download_deps.ps1" -ForegroundColor Yellow
}

Ensure-MediaDirs
if (Test-Path (Join-Path $MediaDir 'readme.txt')) {
    Write-Host "  Media storage: $MediaDir" -ForegroundColor Gray
}

Write-Host "=== Build Complete ===" -ForegroundColor Green
Write-Host "Target output: $(Join-Path $BinDir 'MediaMCPServer.exe')" -ForegroundColor Green
