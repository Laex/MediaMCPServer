# End-to-end lecture processing scenario via MCP stdio
param(
    [string]$ConfigPath = (Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'config\lecture_test_source.json')
)
$ErrorActionPreference = "Stop"
. (Join-Path (Split-Path $PSScriptRoot -Parent) '_common.ps1')
Ensure-MediaDirs

$cfg = Get-Content -Path $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
$sourceVideo = $cfg.sourceVideo
$sourceVideoDisplay = if ($cfg.PSObject.Properties['sourceVideoDisplay']) { $cfg.sourceVideoDisplay } else { $sourceVideo }
$runId = $cfg.runId
$lectureTitle = $cfg.title

$exePath = Join-Path $BinDir 'MediaMCPServer.exe'
$captureDir = Join-Path $MediaDir "captures\$runId"
$videoDir = Join-Path $MediaDir 'video'
$outputDir = Join-Path $MediaDir 'output'
$reportPath = Join-Path $outputDir "${runId}_report.json"
$notesPath = Join-Path $outputDir "${runId}_notes.md"

New-Item -ItemType Directory -Force -Path $captureDir, $videoDir, $outputDir | Out-Null

if (-not (Test-Path $exePath)) { throw "MediaMCPServer.exe not found: $exePath" }
if (-not (Test-Path $sourceVideo)) { throw "Source video not found: $sourceVideo" }

$state = [ordered]@{
    sourceVideo = $sourceVideo
    sourceVideoDisplay = $sourceVideoDisplay
    startedAt   = (Get-Date).ToString('o')
    steps       = @()
    errors      = @()
}

function Start-McpSession {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $exePath
    $psi.WorkingDirectory = $BinDir
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    return [System.Diagnostics.Process]::Start($psi)
}

function Invoke-McpRequest($proc, [int]$id, [string]$method, $params, [int]$timeoutSec = 600) {
    $body = @{ jsonrpc = '2.0'; id = $id; method = $method; params = $params } | ConvertTo-Json -Compress -Depth 8
    $proc.StandardInput.WriteLine($body)

    $deadline = (Get-Date).AddSeconds($timeoutSec)
    while ((Get-Date) -lt $deadline) {
        $line = $proc.StandardOutput.ReadLine()
        if ([string]::IsNullOrWhiteSpace($line)) { Start-Sleep -Milliseconds 50; continue }
        $resp = $line | ConvertFrom-Json
        if ($resp.id -eq $id) {
            if ($resp.error) { throw "JSON-RPC error in $method : $($resp.error.message)" }
            return $resp.result
        }
    }
    throw "Timeout waiting for $method (${timeoutSec}s)"
}

function Invoke-McpTool($proc, [int]$id, [string]$name, [hashtable]$toolArgs, [int]$timeoutSec = 600) {
    $result = Invoke-McpRequest $proc $id 'tools/call' @{ name = $name; arguments = $toolArgs } $timeoutSec
    return ($result.content[0].text | ConvertFrom-Json)
}

function Add-Step([string]$name, $result) {
    $entry = [ordered]@{ tool = $name; at = (Get-Date).ToString('o'); result = $result }
    $script:state.steps += ,$entry
    if ($result.error) { $script:state.errors += "$name : $($result.error)" }
    Write-Host "`n=== $name ===" -ForegroundColor Cyan
    if ($result.error) { Write-Host "ERROR: $($result.error)" -ForegroundColor Red }
    else { Write-Host "OK" -ForegroundColor Green }
}

function Format-Timecode([int]$ms) {
    $ts = [TimeSpan]::FromMilliseconds($ms)
    return '{0:D2}:{1:D2}:{2:D2}' -f [int]$ts.TotalHours, $ts.Minutes, $ts.Seconds
}

function Get-KeepSegments($silenceSegments, [int]$durationMs, [int]$minGapMs = 500) {
    $sorted = @($silenceSegments | Sort-Object { [int]$_.startMs })
    $keep = @()
    $pos = 0
    foreach ($seg in $sorted) {
        $s = [int]$seg.startMs
        $e = [int]$seg.endMs
        if ($s -gt $pos + $minGapMs) {
            $keep += [pscustomobject]@{ startMs = $pos; endMs = $s }
        }
        $pos = [Math]::Max($pos, $e)
    }
    if ($durationMs -gt $pos + $minGapMs) {
        $keep += [pscustomobject]@{ startMs = $pos; endMs = $durationMs }
    }
    return $keep
}

$probe = $null
$scenes = $null
$silence = $null
$timeline = @()
$keep = @()
$durationMs = 0

$proc = Start-McpSession
try {
    $null = Invoke-McpRequest $proc 1 'initialize' @{
        protocolVersion = '2024-11-05'; capabilities = @{}; clientInfo = @{ name = 'lecture-test'; version = '1.0' }
    } 30
    $proc.StandardInput.WriteLine('{"jsonrpc":"2.0","method":"notifications/initialized"}')
    Start-Sleep -Milliseconds 200

    $probe = Invoke-McpTool $proc 2 'video_probe' @{ sourceUrl = $sourceVideo } 300
    Add-Step 'video_probe' $probe
    if ($probe.probe.duration.value) {
        $durationMs = [int]([double]$probe.probe.duration.value / 1000)
    } elseif ($probe.PSObject.Properties['durationMs']) {
        $durationMs = [int]$probe.durationMs
    }
    Write-Host "DurationMs: $durationMs" -ForegroundColor DarkGray

    $scenes = Invoke-McpTool $proc 3 'video_scene_detect' @{
        sourceUrl = $sourceVideo; threshold = 0.15; maxScenes = 60
    } 1800
    Add-Step 'video_scene_detect' $scenes

    $silence = Invoke-McpTool $proc 4 'video_detect_silence' @{
        sourceUrl = $sourceVideo; noiseDb = -35; minSilenceMs = 5000
    } 3600
    Add-Step 'video_detect_silence' $silence

    $sceneList = @($scenes.scenes)
    $idx = 0
    foreach ($scene in $sceneList) {
        $t = [int]$scene.timeMs
        $framePath = Join-Path $captureDir ("slide_{0:D3}_{1}ms.jpg" -f $idx, $t)
        $thumb = Invoke-McpTool $proc (10 + $idx) 'video_thumbnail' @{
            sourceUrl = $sourceVideo; outputPath = $framePath; timeOffsetMs = $t
        } 120
        if ($thumb.error) {
            $timeline += [pscustomobject]@{ timeMs = $t; timecode = (Format-Timecode $t); frame = $null; ocrCount = 0; qrText = $null; error = $thumb.error }
            $idx++
            continue
        }
        $ocr = Invoke-McpTool $proc (100 + $idx) 'image_detect_text' @{ imagePath = $framePath } 180
        $qr = Invoke-McpTool $proc (200 + $idx) 'image_read_qrcode' @{ imagePath = $framePath } 60
        $qrText = $null
        if ($qr.PSObject.Properties['text']) { $qrText = $qr.text }
        elseif ($qr.PSObject.Properties['decoded']) { $qrText = $qr.decoded }
        elseif ($qr.PSObject.Properties['data']) { $qrText = $qr.data }
        $timeline += [pscustomobject]@{
            timeMs = $t; timecode = (Format-Timecode $t); frame = $framePath
            ocrCount = if ($ocr.count) { [int]$ocr.count } else { 0 }; qrText = $qrText
        }
        $idx++
    }
    $state.timeline = $timeline

    $keep = Get-KeepSegments $silence.silenceSegments $durationMs
    if ($keep.Count -eq 0 -and $durationMs -gt 0) {
        $keep = @([pscustomobject]@{ startMs = 0; endMs = $durationMs })
        Write-Host "No silence cuts: keeping full lecture ($durationMs ms)" -ForegroundColor Yellow
    }
    $state.keepSegments = $keep
    $segPaths = @()
    $segIdx = 0
    foreach ($seg in $keep) {
        $out = Join-Path $videoDir ("${runId}_seg_{0:D3}.mp4" -f $segIdx)
        $trim = Invoke-McpTool $proc (300 + $segIdx) 'video_trim' @{
            sourceUrl = $sourceVideo; outputPath = $out; startMs = [int]$seg.startMs; endMs = [int]$seg.endMs
        } 900
        Add-Step "video_trim_$segIdx" $trim
        if (-not $trim.error) { $segPaths += $out }
        $segIdx++
        if ($segIdx -ge 30) { break }
    }

    $cutPath = Join-Path $videoDir "${runId}_cut.mp4"
    if ($segPaths.Count -gt 1) {
        $concat = Invoke-McpTool $proc 400 'video_concat' @{ inputPaths = $segPaths; outputPath = $cutPath } 1800
        Add-Step 'video_concat' $concat
    } elseif ($segPaths.Count -eq 1) {
        Copy-Item $segPaths[0] $cutPath -Force
        Add-Step 'video_concat' @{ status = 'skipped'; reason = 'single segment copied' }
    } else {
        Copy-Item $sourceVideo $cutPath -Force
        Add-Step 'video_concat' @{ status = 'fallback'; reason = 'source copied unchanged' }
    }

    $scaledPath = Join-Path $videoDir "${runId}_720p.mp4"
    $scale = Invoke-McpTool $proc 401 'video_scale' @{
        sourceUrl = $cutPath; outputPath = $scaledPath; width = 1280; height = 720
        maxDurationMs = [Math]::Max($durationMs, 7200000)
    } 3600
    Add-Step 'video_scale' $scale

    $finalPath = Join-Path $outputDir "${runId}_telegram.mp4"
    $remux = Invoke-McpTool $proc 402 'video_remux' @{ sourceUrl = $scaledPath; outputPath = $finalPath } 1800
    Add-Step 'video_remux' $remux
    $state.finalVideo = $finalPath

} catch {
    $state.fatal = $_.Exception.Message
    $state.errors += $_.Exception.Message
    Write-Host "FATAL: $($_.Exception.Message)" -ForegroundColor Red
} finally {
    if ($proc -and -not $proc.HasExited) {
        try { $proc.StandardInput.Close() } catch {}
        if (-not $proc.WaitForExit(5000)) { $proc.Kill() }
        $proc.Close()
    }
}

$state.finishedAt = (Get-Date).ToString('o')
$state | ConvertTo-Json -Depth 12 | Set-Content -Path $reportPath -Encoding UTF8

$md = @()
$md += "# $lectureTitle"
$md += ""
$md += "Source: ``$sourceVideoDisplay``"
if ($probe) {
    $md += "Duration: $(Format-Timecode $durationMs) ($durationMs ms)"
    if ($probe.width -and $probe.height) { $md += "Resolution: $($probe.width)x$($probe.height)" }
}
$md += ""
$md += "## Slide timeline"
$md += ""
$md += "| Timecode | OCR regions | QR | Frame |"
$md += "|----------|-------------|-----|-------|"
foreach ($item in $timeline) {
    $qr = if ($item.qrText) { $item.qrText } else { '-' }
    $md += "| $($item.timecode) | $($item.ocrCount) | $qr | ``$($item.frame)`` |"
}
$md += ""
$md += "## Silence periods (>5s)"
$md += ""
if ($silence -and $silence.silenceSegments) {
    foreach ($s in $silence.silenceSegments) {
        $md += "- $(Format-Timecode ([int]$s.startMs)) - $(Format-Timecode ([int]$s.endMs))"
    }
} else { $md += "_None detected or analysis failed._" }
$md += ""
$md += "## Edit"
$md += ""
$md += "- Segments kept: $($keep.Count)"
if ($state.finalVideo) { $md += "- Final video: ``$($state.finalVideo)``" }
$md += ""
$md += "_Note: image_detect_text returns text region polygons only (detection), not recognized characters._"
$md -join "`n" | Set-Content -Path $notesPath -Encoding UTF8

Write-Host "`nReport: $reportPath" -ForegroundColor Yellow
Write-Host "Notes:  $notesPath" -ForegroundColor Yellow
if ($state.errors.Count -gt 0) {
    Write-Host "Errors: $($state.errors -join '; ')" -ForegroundColor Red
    exit 1
}
Write-Host "Lecture scenario completed." -ForegroundColor Green
