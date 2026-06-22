# Create a pre-built distribution package (no Delphi compiler required on target machine)
param(
    [string]$Version = "",
    [string]$OutputDir = "",
    [ValidateSet('lite', 'full', 'both')]
    [string]$PackageVariant = 'lite',
    [switch]$SkipVerify
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot '_common.ps1')

if (-not $Version) {
    $Version = Get-Date -Format 'yyyy.MM.dd'
}

$distRoot = if ($OutputDir) { $OutputDir } else { Join-Path $ProjectRoot 'dist' }

$runtimeScriptNames = @(
    'download_deps.ps1',
    'download_models.ps1',
    'download_ffmpeg_dll.ps1',
    'download_opencv_runtime.ps1',
    'verify_install.ps1',
    '_common.ps1',
    '_download_common.ps1'
)

$wslScriptRelPaths = @(
    'setup_wsl_http.ps1',
    'setup_wsl_mcp.sh',
    'tests\test_http_mcp_wsl.sh'
)

function Copy-PackageScripts([string]$PkgDir) {
    $pkgScripts = Join-Path $PkgDir 'scripts'
    New-Item -ItemType Directory -Force -Path $pkgScripts | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $pkgScripts 'tests') | Out-Null

    foreach ($name in $runtimeScriptNames) {
        $src = Join-Path $PSScriptRoot $name
        if (-not (Test-Path $src)) { throw "Missing packaging script: $src" }
        Copy-Item $src (Join-Path $pkgScripts $name) -Force
    }

    foreach ($rel in $wslScriptRelPaths) {
        $src = Join-Path $PSScriptRoot $rel
        if (-not (Test-Path $src)) { continue }
        $dest = Join-Path $pkgScripts $rel
        $destDir = Split-Path $dest -Parent
        if ($destDir -and -not (Test-Path $destDir)) {
            New-Item -ItemType Directory -Force -Path $destDir | Out-Null
        }
        Copy-Item $src $dest -Force
    }
}

function Copy-PackageCommon([string]$PkgDir, [string]$Version, [string]$PackageVariant) {
    $mediaSubs = @('captures', 'output', 'faces', 'video')
    foreach ($sub in $mediaSubs) {
        New-Item -ItemType Directory -Force -Path (Join-Path $PkgDir "data\media\$sub") | Out-Null
    }
    $mediaReadme = Join-Path $ProjectRoot 'data\media\readme.txt'
    if (Test-Path $mediaReadme) {
        Copy-Item $mediaReadme (Join-Path $PkgDir 'data\media\readme.txt') -Force
    }

    $pkgConfig = Join-Path $PkgDir 'config'
    New-Item -ItemType Directory -Force -Path $pkgConfig | Out-Null
    Get-ChildItem (Join-Path $ProjectRoot 'config') -File |
        Where-Object { $_.Name -notmatch '\.snippet(\.|$)' } |
        Copy-Item -Destination $pkgConfig -Force

    Copy-PackageScripts $PkgDir

    $pkgDocs = Join-Path $PkgDir 'docs'
    New-Item -ItemType Directory -Force -Path $pkgDocs | Out-Null
    Copy-Item (Join-Path $PSScriptRoot 'dist_install.ps1') (Join-Path $PkgDir 'install.ps1') -Force
    Copy-Item (Join-Path $ProjectRoot 'docs\DISTRIBUTION.md') (Join-Path $PkgDir 'README.md') -Force -ErrorAction SilentlyContinue
    Copy-Item (Join-Path $ProjectRoot 'docs\INSTALLATION.md') (Join-Path $pkgDocs 'INSTALLATION.md') -Force -ErrorAction SilentlyContinue
    Copy-Item (Join-Path $ProjectRoot 'docs\WSL.md') (Join-Path $pkgDocs 'WSL.md') -Force -ErrorAction SilentlyContinue
    Copy-Item (Join-Path $ProjectRoot 'docs\EXAMPLES.md') (Join-Path $pkgDocs 'EXAMPLES.md') -Force -ErrorAction SilentlyContinue
    Copy-Item (Join-Path $ProjectRoot 'docs\RELEASE.md') (Join-Path $pkgDocs 'RELEASE.md') -Force -ErrorAction SilentlyContinue

    $variantLabel = if ($PackageVariant -eq 'lite') {
        'lite (runtime deps downloaded by install.ps1)'
    } else {
        'full (offline, all DLLs and models included)'
    }

    Set-Content -Path (Join-Path $PkgDir 'VERSION.txt') -Value @(
        'Media MCP Server distribution'
        "Version: $Version"
        'Platform: win64'
        "Package: $PackageVariant"
        "Built: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        ''
        'No Delphi or compiler required on target machine.'
        $variantLabel
    ) -Encoding UTF8
}

function New-PackageZip([string]$PkgDir, [string]$ZipPath) {
    if (Test-Path $ZipPath) { Remove-Item $ZipPath -Force }
    Compress-Archive -Path $PkgDir -DestinationPath $ZipPath -CompressionLevel Optimal
}

function Build-PackageVariant {
    param(
        [string]$PackageVariant,
        [string]$Version,
        [string]$DistRoot
    )

    $suffix = if ($PackageVariant -eq 'lite') { '-lite' } else { '-full' }
    $pkgName = "media-mcp-server-$Version-win64$suffix"
    $pkgDir = Join-Path $DistRoot $pkgName
    $zipPath = Join-Path $DistRoot "$pkgName.zip"

    Write-Host ""
    Write-Host "=== Packaging: $PackageVariant ===" -ForegroundColor Cyan
    Write-Host "Folder: $pkgDir"

    if (Test-Path $pkgDir) { Remove-Item $pkgDir -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $pkgDir | Out-Null

    $pkgBin = Join-Path $pkgDir 'bin'
    New-Item -ItemType Directory -Force -Path $pkgBin | Out-Null

    $exeSrc = Join-Path $BinDir 'MediaMCPServer.exe'
    if (-not (Test-Path $exeSrc)) { throw "Missing required file: $exeSrc" }
    Copy-Item $exeSrc $pkgBin -Force

    $wrapperSrc = Join-Path $BinDir 'opencv_delphi_wrapper.dll'
    if (-not (Test-Path $wrapperSrc)) { throw "Missing required file: $wrapperSrc" }
    Copy-Item $wrapperSrc $pkgBin -Force

    Get-ChildItem $BinDir -Filter 'launch_http*.cmd' -ErrorAction SilentlyContinue |
        Copy-Item -Destination $pkgBin -Force

    if ($PackageVariant -eq 'full') {
        Get-ChildItem $BinDir -Filter '*.dll' | Where-Object {
            $name = $_.Name
            if ($name -eq 'opencv_delphi_wrapper.dll') { return $false }
            if ($name -match 'd\.dll$') {
                $releaseName = $name -replace 'd\.dll$', '.dll'
                if (Test-Path (Join-Path $BinDir $releaseName)) { return $false }
            }
            $true
        } | Copy-Item -Destination $pkgBin -Force

        foreach ($onnx in @('backbone.onnx', 'neckhead.onnx')) {
            $src = Join-Path $BinDir $onnx
            if (Test-Path $src) { Copy-Item $src $pkgBin -Force }
        }

        $srcModels = Join-Path $BinDir 'models'
        if (Test-Path $srcModels) {
            Copy-Item $srcModels (Join-Path $pkgBin 'models') -Recurse -Force
        }
    } else {
        New-Item -ItemType Directory -Force -Path (Join-Path $pkgBin 'models') | Out-Null
        $modelsKeep = Join-Path $ProjectRoot 'bin\models\.gitkeep'
        if (Test-Path $modelsKeep) {
            Copy-Item $modelsKeep (Join-Path $pkgBin 'models\.gitkeep') -Force
        }
    }

    Copy-PackageCommon $pkgDir $Version $PackageVariant

    New-Item -ItemType Directory -Force -Path $DistRoot | Out-Null
    New-PackageZip $pkgDir $zipPath

    $zipSize = [math]::Round((Get-Item $zipPath).Length / 1MB, 1)
    Write-Host "ZIP: $zipPath ($zipSize MB)" -ForegroundColor Green

    return [PSCustomObject]@{
        Variant = $PackageVariant
        Folder = $pkgDir
        Zip = $zipPath
        SizeMb = $zipSize
    }
}

Write-Host "=== Media MCP Server - Package ===" -ForegroundColor Cyan
Write-Host "Version: $Version"
Write-Host "Variant: $PackageVariant"
Write-Host "Output:  $distRoot"

if (-not $SkipVerify) {
    if ($PackageVariant -in @('lite', 'both')) {
        & (Join-Path $PSScriptRoot 'verify_package.ps1') -Lite -Strict
        if ($LASTEXITCODE -ne 0) { throw 'Lite package verification failed.' }
    }
    if ($PackageVariant -in @('full', 'both')) {
        & (Join-Path $PSScriptRoot 'verify_package.ps1') -Strict
        if ($LASTEXITCODE -ne 0) { throw 'Full package verification failed. Run .\install.ps1 first.' }
    }
}

$built = @()
if ($PackageVariant -in @('lite', 'both')) {
    $built += Build-PackageVariant -PackageVariant 'lite' -Version $Version -DistRoot $distRoot
}
if ($PackageVariant -in @('full', 'both')) {
    $built += Build-PackageVariant -PackageVariant 'full' -Version $Version -DistRoot $distRoot
}

Write-Host ""
Write-Host '=== Package complete ===' -ForegroundColor Green
foreach ($item in $built) {
    Write-Host "  $($item.Variant): $($item.Zip) ($($item.SizeMb) MB)" -ForegroundColor Gray
}
Write-Host ""
Write-Host 'Deploy: extract ZIP, run .\install.ps1' -ForegroundColor Cyan
Write-Host 'GitHub:  .\scripts\release.ps1 -Version <tag> -Publish' -ForegroundColor Cyan
exit 0
