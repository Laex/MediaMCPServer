# Shared paths for Media MCP Server scripts
if ($PSScriptRoot -match '[\\/]tests$') {
    $script:ProjectRoot = (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent)
} elseif ($PSScriptRoot -match '[\\/]scripts$') {
    $script:ProjectRoot = (Split-Path $PSScriptRoot -Parent)
} else {
    $script:ProjectRoot = $PSScriptRoot
}

$script:BinDir       = Join-Path $ProjectRoot 'bin'
$script:SrcDir       = Join-Path $ProjectRoot 'src'
$script:DcuDir       = Join-Path $ProjectRoot 'dcu'
$script:DataDir      = Join-Path $ProjectRoot 'data'
$script:MediaDir     = Join-Path $ProjectRoot 'data\media'
$script:ConfigDir    = Join-Path $ProjectRoot 'config'
$script:CursorDir    = Join-Path $ProjectRoot '.cursor'
$script:ParentDir = Split-Path $ProjectRoot -Parent
$parentDir = $script:ParentDir
$openCvCandidates = @(
    (Join-Path $parentDir 'OpenCV\OpenCV 5.0'),
    (Join-Path $parentDir 'OpenCV 5.0')
)
$script:OpenCvRoot = $openCvCandidates[0]
foreach ($candidate in $openCvCandidates) {
    if (Test-Path $candidate) {
        $script:OpenCvRoot = $candidate
        break
    }
}
$script:FfmpegBin    = Join-Path $parentDir 'Delphi-FFMPEG\bin'

function Get-DelphiCompiler {
    $dcc = $null
    $newestStudio = $null
    $studioPaths = Get-ChildItem 'C:\Program Files (x86)\Embarcadero\Studio\*' -Directory -ErrorAction SilentlyContinue
    if ($studioPaths) {
        $newestStudio = $studioPaths | Sort-Object Name -Descending | Select-Object -First 1
        $compiler64 = Join-Path $newestStudio.FullName 'bin\dcc64.exe'
        if (Test-Path $compiler64) { $dcc = $compiler64 }
    }
    if (-not $dcc) {
        $dccCmd = Get-Command 'dcc64.exe' -ErrorAction SilentlyContinue
        if ($dccCmd) { $dcc = $dccCmd.Source }
    }
    if (-not $dcc) {
        if ($newestStudio) {
            $compiler32 = Join-Path $newestStudio.FullName 'bin\dcc32.exe'
            if (Test-Path $compiler32) { $dcc = $compiler32 }
        }
        if (-not $dcc) {
            $dccCmd = Get-Command 'dcc32.exe' -ErrorAction SilentlyContinue
            if ($dccCmd) { $dcc = $dccCmd.Source }
        }
    }
    return $dcc
}

function Ensure-MediaDirs {
    foreach ($sub in @('captures', 'output', 'faces', 'video')) {
        New-Item -ItemType Directory -Force -Path (Join-Path $MediaDir $sub) | Out-Null
    }
}
