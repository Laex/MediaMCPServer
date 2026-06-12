param(
    [switch]$Force
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot '_common.ps1')
. (Join-Path $PSScriptRoot '_download_common.ps1')

$manifest = Get-DepsManifest
$url = $manifest.ffmpeg.zip
New-Item -ItemType Directory -Force -Path $BinDir | Out-Null
New-Item -ItemType Directory -Force -Path $DepsCacheDir | Out-Null

Write-Host "Media MCP Server - download FFmpeg DLLs" -ForegroundColor White
Write-Host "Target: $BinDir" -ForegroundColor DarkGray
Write-Host "URL: $url" -ForegroundColor DarkGray

$zipPath = Join-Path $DepsCacheDir 'ffmpeg-win64-gpl-shared.zip'
$extractPath = Join-Path $DepsCacheDir 'ffmpeg_extract'

if (-not $Force) {
    $existing = @('avcodec-62.dll', 'avformat-62.dll', 'avutil-60.dll', 'swscale-9.dll') |
        Where-Object { Test-Path (Join-Path $BinDir $_) }
    if ($existing.Count -eq 4) {
        Write-Host "  [skip] FFmpeg DLLs already present in bin\" -ForegroundColor DarkGray
        return
    }
}

Write-DownloadStep 'FFmpeg shared build (BtbN)'
Invoke-DownloadFile $url $zipPath 'ffmpeg-n8.1-win64-gpl-shared.zip' -Force:$Force -MinBytes 1000000

if (Test-Path $extractPath) { Remove-Item $extractPath -Recurse -Force }
New-Item -ItemType Directory -Force -Path $extractPath | Out-Null
Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force

$rootFolder = Get-ChildItem -Path $extractPath -Directory | Select-Object -First 1
if (-not $rootFolder) { throw "FFmpeg archive has no root folder: $extractPath" }
$dllSource = Join-Path $rootFolder.FullName 'bin'
if (-not (Test-Path $dllSource)) { throw "FFmpeg bin folder not found: $dllSource" }

Write-DownloadStep 'Install FFmpeg DLLs'
$copied = Copy-MatchingDlls $dllSource $BinDir -Force:$Force
if ($copied -eq 0) {
    Write-Host '  All FFmpeg DLLs up to date' -ForegroundColor DarkGray
}

Write-DownloadStep 'Done'
