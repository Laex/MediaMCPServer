# Shared helpers for dependency download scripts (dot-source only)
if (-not $ProjectRoot) {
    if ($PSScriptRoot -match '[\\/]tests$') {
        $script:ProjectRoot = (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent)
    } elseif ($PSScriptRoot -match '[\\/]scripts$') {
        $script:ProjectRoot = (Split-Path $PSScriptRoot -Parent)
    } else {
        $script:ProjectRoot = $PSScriptRoot
    }
}

if (-not $BinDir) {
    $script:BinDir = Join-Path $ProjectRoot 'bin'
}

$script:DepsCacheDir = Join-Path $ProjectRoot '.deps'
$script:DepsManifestPath = Join-Path $ProjectRoot 'config\deps_urls.json'

function Get-DepsManifest {
    if (-not (Test-Path $DepsManifestPath)) {
        throw "Dependency manifest not found: $DepsManifestPath"
    }
    return Get-Content $DepsManifestPath -Raw | ConvertFrom-Json
}

function Write-DownloadStep([string]$Text) {
    Write-Host ""
    Write-Host "=== $Text ===" -ForegroundColor Cyan
}

function Get-OpenCvZooUrl([string]$RelativePath) {
    "https://media.githubusercontent.com/media/opencv/opencv_zoo/main/$RelativePath"
}

function Invoke-DownloadFile {
    param(
        [string]$Url,
        [string]$Dest,
        [string]$Label,
        [switch]$Force,
        [int64]$MinBytes = 1024
    )

    $destDir = Split-Path $Dest -Parent
    if ($destDir -and -not (Test-Path $destDir)) {
        New-Item -ItemType Directory -Force -Path $destDir | Out-Null
    }

    if ((Test-Path $Dest) -and -not $Force) {
        $len = (Get-Item $Dest).Length
        if ($len -ge $MinBytes) {
            Write-Host ("  [skip] {0} ({1:N0} bytes)" -f $Label, $len) -ForegroundColor DarkGray
            return
        }
    }

    Write-Host ("  [get]  {0}" -f $Label) -ForegroundColor Yellow
    $prev = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'
    try {
        Invoke-WebRequest -Uri $Url -OutFile $Dest -UseBasicParsing
    } finally {
        $ProgressPreference = $prev
    }

    $len = (Get-Item $Dest).Length
    if ($len -lt $MinBytes) {
        $head = Get-Content $Dest -TotalCount 3 -ErrorAction SilentlyContinue
        if ($head -match 'git-lfs') {
            Remove-Item $Dest -Force
            throw "LFS pointer instead of binary: $Dest"
        }
    }
    Write-Host ("         -> {0:N0} bytes" -f $len) -ForegroundColor Green
}

function Copy-MatchingDlls {
    param(
        [string]$FromDir,
        [string]$ToDir,
        [switch]$Force
    )

    if (-not (Test-Path $FromDir)) { return 0 }
    $count = 0
    foreach ($pat in @('*.dll')) {
        Get-ChildItem $FromDir -Filter $pat -ErrorAction SilentlyContinue | ForEach-Object {
            $dest = Join-Path $ToDir $_.Name
            if ($Force -or -not (Test-Path $dest) -or $_.LastWriteTime -gt (Get-Item $dest).LastWriteTime) {
                Copy-Item $_.FullName $dest -Force
                Write-Host "  Installed $($_.Name)" -ForegroundColor Gray
                $count++
            }
        }
    }
    return $count
}
