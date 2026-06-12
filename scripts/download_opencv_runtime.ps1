param(
    [string]$OpenCvDir = $env:OpenCV_DIR,
    [string]$WrapperSourceRoot = '',
    [string]$Cmake = '',
    [switch]$Force
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot '_common.ps1')
. (Join-Path $PSScriptRoot '_download_common.ps1')

$manifest = Get-DepsManifest
$WrapperDllName = 'opencv_delphi_wrapper.dll'
$wrapperDest = Join-Path $BinDir $WrapperDllName
New-Item -ItemType Directory -Force -Path $BinDir | Out-Null
New-Item -ItemType Directory -Force -Path $DepsCacheDir | Out-Null

function Find-Cmake {
    if ($Cmake -and (Test-Path $Cmake)) { return $Cmake }
    $cmd = Get-Command cmake.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

function Resolve-WrapperSourceRoot {
    if ($WrapperSourceRoot -and (Test-Path $WrapperSourceRoot)) {
        return (Resolve-Path $WrapperSourceRoot).Path
    }
    $candidates = @(
        (Join-Path $OpenCvRoot 'wrapper'),
        (Join-Path $ProjectRoot 'third_party\opencv_delphi_wrapper')
    )
    foreach ($path in $candidates) {
        if (Test-Path (Join-Path $path 'CMakeLists.txt')) {
            return (Resolve-Path $path).Path
        }
    }
    return $null
}

function Resolve-OpenCvBuildDir([string]$SearchRoot) {
    $config = Get-ChildItem -Path $SearchRoot -Recurse -Filter 'OpenCVConfig.cmake' -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if (-not $config) { return $null }
    return $config.Directory.FullName
}

function Install-OpenCvDllsFromBuild([string]$BuildDir) {
    $patterns = @(
        (Join-Path $BuildDir 'x64\vc17\bin'),
        (Join-Path $BuildDir 'x64\vc16\bin'),
        (Join-Path $BuildDir 'bin')
    )
    foreach ($dir in $patterns) {
        if ((Copy-MatchingDlls $dir $BinDir -Force:$Force) -gt 0) {
            Write-Host "  OpenCV runtime from $dir" -ForegroundColor Green
            return $true
        }
    }
    return $false
}

function Ensure-OpenCvWindowsPackage {
  param([string]$PreferredBuildDir = '')

    if ($PreferredBuildDir -and (Install-OpenCvDllsFromBuild $PreferredBuildDir)) {
        return $PreferredBuildDir
    }

    $world = Get-ChildItem $BinDir -Filter 'opencv_world*.dll' -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notmatch 'd\.dll$' } |
        Select-Object -First 1
    if ($world -and -not $Force) {
        Write-Host "  [skip] OpenCV runtime already in bin\ ($($world.Name))" -ForegroundColor DarkGray
        if ($PreferredBuildDir) { return $PreferredBuildDir }
        return $null
    }

    Write-DownloadStep 'OpenCV 5.0 Windows package'
    $exePath = Join-Path $DepsCacheDir 'opencv-5.0.0-windows.exe'
    Invoke-DownloadFile $manifest.opencv.windowsExe $exePath 'opencv-5.0.0-windows.exe' -Force:$Force -MinBytes 10000000

    $extractRoot = Join-Path $DepsCacheDir 'opencv-5.0.0-windows'
    if ((Test-Path $extractRoot) -and $Force) {
        Remove-Item $extractRoot -Recurse -Force
    }
    if (-not (Test-Path $extractRoot)) {
        New-Item -ItemType Directory -Force -Path $extractRoot | Out-Null
        Write-Host '  [run]  Extracting OpenCV self-extractor...' -ForegroundColor Yellow
        $proc = Start-Process -FilePath $exePath -ArgumentList "-o`"$extractRoot`"", '-y' -Wait -PassThru -NoNewWindow
        if ($proc.ExitCode -ne 0) {
            throw "OpenCV extractor failed with exit code $($proc.ExitCode)"
        }
    }

    $buildDir = Resolve-OpenCvBuildDir $extractRoot
    if (-not $buildDir) {
        throw "OpenCVConfig.cmake not found under $extractRoot"
    }
    if (-not (Install-OpenCvDllsFromBuild $buildDir)) {
        throw "No OpenCV DLLs found under $buildDir"
    }
    return $buildDir
}

function Build-OpenCvWrapper([string]$WrapperRoot, [string]$OpenCvBuildDir) {
    $cmakeExe = Find-Cmake
    if (-not $cmakeExe) {
        throw 'cmake.exe not found - required to build opencv_delphi_wrapper.dll'
    }

    $buildDir = Join-Path $DepsCacheDir 'opencv_delphi_wrapper_build'
    $builtWrapper = Join-Path $buildDir 'Release' $WrapperDllName
    if ((Test-Path $builtWrapper) -and -not $Force) {
        Copy-Item $builtWrapper $wrapperDest -Force
        Write-Host "  Installed $WrapperDllName (cached build)" -ForegroundColor Green
        return
    }

    Write-DownloadStep 'Build opencv_delphi_wrapper.dll'
    Write-Host "  Wrapper source: $WrapperRoot" -ForegroundColor DarkGray
    Write-Host "  OpenCV_DIR:       $OpenCvBuildDir" -ForegroundColor DarkGray

    if ((Test-Path $buildDir) -and $Force) {
        Remove-Item $buildDir -Recurse -Force
    }
    if (-not (Test-Path $buildDir)) {
        & $cmakeExe -B $buildDir -S $WrapperRoot -D "OpenCV_DIR=$OpenCvBuildDir" -A x64
        if ($LASTEXITCODE -ne 0) { throw "cmake configure failed with code $LASTEXITCODE" }
    }
    & $cmakeExe --build $buildDir --config Release
    if ($LASTEXITCODE -ne 0) { throw "cmake build failed with code $LASTEXITCODE" }
    if (-not (Test-Path $builtWrapper)) {
        throw "Wrapper build failed: $builtWrapper not found"
    }
    Copy-Item $builtWrapper $wrapperDest -Force
    Write-Host "  Installed $WrapperDllName" -ForegroundColor Green
}

Write-Host "Media MCP Server - download OpenCV runtime" -ForegroundColor White
Write-Host "Target: $BinDir" -ForegroundColor DarkGray

$openCvBuildDir = $OpenCvDir
if ($openCvBuildDir) {
    $resolved = Resolve-OpenCvBuildDir $openCvBuildDir
    if ($resolved) { $openCvBuildDir = $resolved }
}

if (-not $openCvBuildDir) {
    $openCvBuildDir = Ensure-OpenCvWindowsPackage
} else {
    $openCvBuildDir = Ensure-OpenCvWindowsPackage -PreferredBuildDir $openCvBuildDir
}

if (-not (Test-Path $wrapperDest) -or $Force) {
    $wrapperRoot = Resolve-WrapperSourceRoot
    if (-not $wrapperRoot) {
        throw @"
opencv_delphi_wrapper.dll is missing and wrapper sources were not found.
Clone Delphi-OpenCV5 (OpenCV\OpenCV 5.0) for wrapper sources, or pass:
  -WrapperSourceRoot 'D:\path\to\OpenCV 5.0\wrapper'
"@
    }
    if (-not $openCvBuildDir) {
        throw 'OpenCV build directory could not be resolved for wrapper build.'
    }
    Build-OpenCvWrapper $wrapperRoot $openCvBuildDir
} else {
    Write-Host "  [skip] $WrapperDllName already in bin\" -ForegroundColor DarkGray
}

if (Test-Path $wrapperDest) {
    Write-Host "OK: $wrapperDest" -ForegroundColor Green
} else {
    throw "MISSING: $WrapperDllName in bin\"
}

Write-DownloadStep 'Done'
