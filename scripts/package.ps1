# Create a pre-built distribution package (no Delphi compiler required on target machine)
param(
    [string]$Version = "",
    [string]$OutputDir = "",
    [switch]$SkipVerify
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot '_common.ps1')

if (-not $Version) {
    $Version = Get-Date -Format 'yyyy.MM.dd'
}

$distRoot = if ($OutputDir) { $OutputDir } else { Join-Path $ProjectRoot "dist" }
$pkgName = "media-mcp-server-$Version-win64"
$pkgDir = Join-Path $distRoot $pkgName

Write-Host "=== Media MCP Server - Package ===" -ForegroundColor Cyan
Write-Host "Version: $Version"
Write-Host "Output:  $pkgDir"

if (-not $SkipVerify) {
    & (Join-Path $PSScriptRoot 'verify_install.ps1') -Strict
    if ($LASTEXITCODE -ne 0) {
        throw "Build is incomplete. Run .\install.ps1 first, or use -SkipVerify."
    }
}

if (Test-Path $pkgDir) { Remove-Item $pkgDir -Recurse -Force }
New-Item -ItemType Directory -Force -Path $pkgDir | Out-Null

# --- bin/ (runtime) ---
$pkgBin = Join-Path $pkgDir 'bin'
New-Item -ItemType Directory -Force -Path $pkgBin | Out-Null

$exeSrc = Join-Path $BinDir 'MediaMCPServer.exe'
if (-not (Test-Path $exeSrc)) { throw "Missing required file: $exeSrc" }
Copy-Item $exeSrc $pkgBin -Force

Get-ChildItem $BinDir -Filter '*.dll' | Where-Object {
    # Skip debug OpenCV DLLs when release build is present (smaller production package)
    $name = $_.Name
    if ($name -match 'd\.dll$' -and $name -notmatch 'opencv_delphi_wrapper') {
        $releaseName = $name -replace 'd\.dll$', '.dll'
        if (Test-Path (Join-Path $BinDir $releaseName)) { return $false }
    }
    $true
} | Copy-Item -Destination $pkgBin -Force
foreach ($onnx in @('backbone.onnx', 'neckhead.onnx')) {
    $src = Join-Path $BinDir $onnx
    if (Test-Path $src) { Copy-Item $src $pkgBin -Force }
}
Get-ChildItem $BinDir -Filter 'launch_http*.cmd' -ErrorAction SilentlyContinue |
    Copy-Item -Destination $pkgBin -Force

$pkgModels = Join-Path $pkgBin 'models'
$srcModels = Join-Path $BinDir 'models'
if (Test-Path $srcModels) {
    Copy-Item $srcModels $pkgModels -Recurse -Force
}

# --- data/media/ (empty user storage) ---
$mediaSubs = @('captures', 'output', 'faces', 'video')
foreach ($sub in $mediaSubs) {
    New-Item -ItemType Directory -Force -Path (Join-Path $pkgDir "data\media\$sub") | Out-Null
}
$mediaReadme = Join-Path $ProjectRoot 'data\media\readme.txt'
if (Test-Path $mediaReadme) {
    Copy-Item $mediaReadme (Join-Path $pkgDir 'data\media\readme.txt') -Force
}

# --- config templates ---
$pkgConfig = Join-Path $pkgDir 'config'
New-Item -ItemType Directory -Force -Path $pkgConfig | Out-Null
Get-ChildItem (Join-Path $ProjectRoot 'config') -File | Copy-Item -Destination $pkgConfig -Force

# --- WSL helper scripts ---
$pkgScripts = Join-Path $pkgDir 'scripts'
New-Item -ItemType Directory -Force -Path $pkgScripts | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $pkgScripts 'tests') | Out-Null
foreach ($rel in @(
    'setup_wsl_http.ps1',
    'setup_wsl_mcp.sh',
    'tests\test_http_mcp_wsl.sh'
)) {
    $src = Join-Path $PSScriptRoot $rel
    if (Test-Path $src) {
        $dest = Join-Path $pkgScripts $rel
        $destDir = Split-Path $dest -Parent
        if ($destDir -and -not (Test-Path $destDir)) {
            New-Item -ItemType Directory -Force -Path $destDir | Out-Null
        }
        Copy-Item $src $dest -Force
    }
}

# --- distribution installer & docs ---
$pkgDocs = Join-Path $pkgDir 'docs'
New-Item -ItemType Directory -Force -Path $pkgDocs | Out-Null
Copy-Item (Join-Path $PSScriptRoot 'dist_install.ps1') (Join-Path $pkgDir 'install.ps1') -Force
Copy-Item (Join-Path $ProjectRoot 'docs\DISTRIBUTION.md') (Join-Path $pkgDir 'README.md') -Force -ErrorAction SilentlyContinue
Copy-Item (Join-Path $ProjectRoot 'docs\INSTALLATION.md') (Join-Path $pkgDocs 'INSTALLATION.md') -Force -ErrorAction SilentlyContinue
Copy-Item (Join-Path $ProjectRoot 'docs\WSL.md') (Join-Path $pkgDocs 'WSL.md') -Force -ErrorAction SilentlyContinue
Copy-Item (Join-Path $ProjectRoot 'docs\EXAMPLES.md') (Join-Path $pkgDocs 'EXAMPLES.md') -Force -ErrorAction SilentlyContinue

Set-Content -Path (Join-Path $pkgDir 'VERSION.txt') -Value @(
    "Media MCP Server distribution"
    "Version: $Version"
    "Platform: win64"
    "Built: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    ""
    "No Delphi or compiler required on target machine."
) -Encoding UTF8

# --- ZIP archive ---
New-Item -ItemType Directory -Force -Path $distRoot | Out-Null
$zipPath = Join-Path $distRoot "$pkgName.zip"
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
Compress-Archive -Path $pkgDir -DestinationPath $zipPath -CompressionLevel Optimal

$zipSize = [math]::Round((Get-Item $zipPath).Length / 1MB, 1)
Write-Host ""
Write-Host "Package folder: $pkgDir" -ForegroundColor Green
Write-Host "ZIP archive:    $zipPath ($zipSize MB)" -ForegroundColor Green
Write-Host ""
Write-Host "Deploy: copy ZIP to target PC, extract, run install.ps1" -ForegroundColor Cyan
