# Build distribution package(s) and optionally publish to GitHub Releases
param(
    [Parameter(Mandatory = $true)]
    [string]$Version,
    [ValidateSet('lite', 'full', 'both')]
    [string]$PackageVariant = 'lite',
    [switch]$SkipBuild,
    [switch]$SkipVerify,
    [switch]$Publish,
    [switch]$Draft,
    [string]$NotesFile = ""
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot '_common.ps1')

$tag = if ($Version -match '^v') { $Version } else { "v$Version" }
$tagVersion = $tag.TrimStart('v')

Write-Host "=== Media MCP Server - GitHub Release ===" -ForegroundColor Cyan
Write-Host "Tag:     $tag"
Write-Host "Package: $PackageVariant"

if (-not $SkipBuild) {
    $proc = Get-Process MediaMCPServer -ErrorAction SilentlyContinue
    if ($proc) {
        Write-Host "Stopping running MediaMCPServer (PID $($proc.Id))..." -ForegroundColor Yellow
        $proc | Stop-Process -Force
        Start-Sleep -Seconds 1
    }
    & (Join-Path $PSScriptRoot 'build.ps1')
}

$pkgScript = Join-Path $PSScriptRoot 'package.ps1'
if ($SkipVerify) {
    & $pkgScript -Version $tagVersion -PackageVariant $PackageVariant -SkipVerify
} else {
    & $pkgScript -Version $tagVersion -PackageVariant $PackageVariant
}
if ($LASTEXITCODE -ne 0) { throw 'package.ps1 failed' }

$distRoot = Join-Path $ProjectRoot 'dist'
$assets = @()
if ($PackageVariant -in @('lite', 'both')) {
    $liteZip = Join-Path $distRoot "media-mcp-server-$tagVersion-win64-lite.zip"
    if (-not (Test-Path $liteZip)) { throw "Missing lite package: $liteZip" }
    $assets += $liteZip
}
if ($PackageVariant -in @('full', 'both')) {
    $fullZip = Join-Path $distRoot "media-mcp-server-$tagVersion-win64-full.zip"
    if (-not (Test-Path $fullZip)) { throw "Missing full package: $fullZip" }
    $assets += $fullZip
}

foreach ($zip in $assets) {
    $hash = Get-FileHash $zip -Algorithm SHA256
  $sizeMb = [math]::Round((Get-Item $zip).Length / 1MB, 1)
    Write-Host ""
    Write-Host "Asset: $(Split-Path $zip -Leaf) ($sizeMb MB)" -ForegroundColor Green
    Write-Host "SHA256: $($hash.Hash)" -ForegroundColor DarkGray
}

if (-not $Publish) {
    Write-Host ""
    Write-Host "Packages ready in dist\. To publish:" -ForegroundColor Cyan
    Write-Host "  .\scripts\release.ps1 -Version $tagVersion -Publish" -ForegroundColor White
    exit 0
}

$gh = Get-Command gh -ErrorAction SilentlyContinue
if (-not $gh) {
    throw 'GitHub CLI (gh) not found. Install from https://cli.github.com/ or upload ZIPs manually.'
}

if (-not $NotesFile) {
    $NotesFile = Join-Path $env:TEMP "media-mcp-release-$tagVersion.md"
    $liteName = "media-mcp-server-$tagVersion-win64-lite.zip"
    $fullName = "media-mcp-server-$tagVersion-win64-full.zip"
    @"
## Media MCP Server $tagVersion — Windows x64

MCP server for media processing (OpenCV 5, FFmpeg, ONVIF). **47 tools**. Streamable HTTP by default.

### Requirements
- Windows 10/11 x64
- Internet on first install (**lite** package)

### Install (recommended — lite)
1. Download ``$liteName``
2. Extract to e.g. ``C:\Tools\media-mcp-server\``
3. PowerShell in that folder:

``````powershell
.\install.ps1
``````

``install.ps1`` downloads FFmpeg/OpenCV DLLs and ONNX models, configures MCP, and starts HTTP.

4. Refresh MCP in your client. Expect **47 tools**.

### Offline install (full)
Use ``$fullName`` if you need an offline bundle with all DLLs and models included.
Run ``.\install.ps1 -SkipDownload`` after extract.

### HTTP endpoint
``http://127.0.0.1:8765/mcp`` — start manually: ``cd bin; .\launch_http.cmd``

### Docs (inside archive)
- ``docs/INSTALLATION.md`` — MCP clients
- ``docs/WSL.md`` — WSL client + Windows server
"@ | Set-Content -Path $NotesFile -Encoding UTF8
}

Write-Host ""
Write-Host "Publishing GitHub Release $tag ..." -ForegroundColor Cyan

$releaseArgs = @('release', 'create', $tag, '--title', "Media MCP Server $tagVersion (Windows x64)")
if ($Draft) { $releaseArgs += '--draft' }
$releaseArgs += '--notes-file', $NotesFile
$releaseArgs += $assets

& gh @releaseArgs
if ($LASTEXITCODE -ne 0) { throw "gh release create failed with exit code $LASTEXITCODE" }

$repo = (& gh repo view --json nameWithOwner -q .nameWithOwner 2>$null)
if ($repo) {
    Write-Host ""
    Write-Host "Published: https://github.com/$repo/releases/tag/$tag" -ForegroundColor Green
} else {
    Write-Host "Release published." -ForegroundColor Green
}

exit 0
