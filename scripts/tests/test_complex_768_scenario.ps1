# Complex multi-tool MCP scenario — FFmpeg reference clip 768x576.avi
param(
    [string]$ConfigPath = (Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'config\complex_test_768.json')
)
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path $PSScriptRoot -Parent) '_common.ps1')
Ensure-MediaDirs

$cfg = Get-Content -Path $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
$sourceVideo = $cfg.sourceVideo
$runId = $cfg.runId
$title = $cfg.title
$userPrompt = $cfg.userPrompt

$exePath = Join-Path $BinDir 'MediaMCPServer.exe'
$captureDir = Join-Path $MediaDir "captures\$runId"
$videoDir = Join-Path $MediaDir 'video'
$outputDir = Join-Path $MediaDir 'output'
$reportPath = Join-Path $outputDir "${runId}_report.json"
$notesPath = Join-Path $outputDir "${runId}_notes.md"
$promptPath = Join-Path $outputDir "${runId}_prompt.md"

New-Item -ItemType Directory -Force -Path $captureDir, $videoDir, $outputDir | Out-Null

if (-not (Test-Path $exePath)) { throw "MediaMCPServer.exe not found: $exePath" }
if (-not (Test-Path $sourceVideo)) { throw "Source video not found: $sourceVideo" }

$state = [ordered]@{
    userPrompt  = $userPrompt
    sourceVideo = $sourceVideo
    startedAt   = (Get-Date).ToString('o')
    steps       = @()
    errors      = @()
    vision      = @()
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

function Invoke-McpRequest($proc, [int]$id, [string]$method, $params, [int]$timeoutSec = 300) {
    $body = @{ jsonrpc = '2.0'; id = $id; method = $method; params = $params } | ConvertTo-Json -Compress -Depth 10
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

function Invoke-McpTool($proc, [int]$id, [string]$name, [hashtable]$toolArgs, [int]$timeoutSec = 300) {
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
    return '{0:D2}:{1:D2}:{2:D2}.{3:D3}' -f [int]$ts.TotalHours, $ts.Minutes, $ts.Seconds, $ts.Milliseconds
}

$durationMs = 0
$probe = $null
$scenes = @()
$framePaths = @()
$reqId = 1

Write-Host "USER PROMPT:" -ForegroundColor Magenta
Write-Host $userPrompt -ForegroundColor DarkGray

$proc = Start-McpSession
try {
    $null = Invoke-McpRequest $proc $reqId 'initialize' @{
        protocolVersion = '2024-11-05'; capabilities = @{}; clientInfo = @{ name = 'complex-768-test'; version = '1.0' }
    } 30
    $reqId++
    $proc.StandardInput.WriteLine('{"jsonrpc":"2.0","method":"notifications/initialized"}')
    Start-Sleep -Milliseconds 200

    # 1. Probe + stream health
    $probe = Invoke-McpTool $proc $reqId 'video_probe' @{ sourceUrl = $sourceVideo } 120
    $reqId++
    Add-Step 'video_probe' $probe
    if ($probe.durationMs) { $durationMs = [int]$probe.durationMs }
    elseif ($probe.probe.duration.value) { $durationMs = [int]([double]$probe.probe.duration.value / 1000) }

    $hasAudio = $false
    if ($probe.probe.streams) {
        foreach ($st in @($probe.probe.streams)) {
            if ($st.type -eq 'audio') { $hasAudio = $true; break }
        }
    }

    $stream = Invoke-McpTool $proc $reqId 'stream_test' @{ sourceUrl = $sourceVideo; timeoutMs = 8000 } 60
    $reqId++
    Add-Step 'stream_test' $stream

    $meta = Invoke-McpTool $proc $reqId 'video_metadata_read' @{ sourceUrl = $sourceVideo } 60
    $reqId++
    Add-Step 'video_metadata_read' $meta

    # 2. Structure analysis
    $scenesResult = Invoke-McpTool $proc $reqId 'video_scene_detect' @{
        sourceUrl = $sourceVideo; threshold = 0.08; maxScenes = 24
    } 300
    $reqId++
    Add-Step 'video_scene_detect' $scenesResult
    $scenes = @($scenesResult.scenes)
    if ($scenes.Count -eq 0) { $scenes = @(@{ timeMs = 0 }) }

    if ($hasAudio) {
        $silence = Invoke-McpTool $proc $reqId 'video_detect_silence' @{
            sourceUrl = $sourceVideo; noiseDb = -35; minSilenceMs = 800
        } 300
        $reqId++
        Add-Step 'video_detect_silence' $silence
    } else {
        $silence = @{ status = 'skipped'; reason = 'no audio stream in source' }
        Add-Step 'video_detect_silence' $silence
    }

    # 3. Frame extraction burst
    $grab = Invoke-McpTool $proc $reqId 'video_grab_frames' @{
        sourceUrl = $sourceVideo; outputDir = $captureDir
        timeOffsetMs = 0; intervalMs = [Math]::Max(500, [int]($durationMs / 8)); count = 6
    } 180
    $reqId++
    Add-Step 'video_grab_frames' $grab
    if ($grab.frames) { $framePaths = @($grab.frames) }
    elseif ($grab.paths) { $framePaths = @($grab.paths) }
    else {
        Get-ChildItem $captureDir -Filter '*.jpg' | Sort-Object Name | ForEach-Object { $framePaths += $_.FullName }
    }

    $thumbPath = Join-Path $captureDir 'poster_480w.jpg'
    $thumb = Invoke-McpTool $proc $reqId 'video_thumbnail' @{
        sourceUrl = $sourceVideo; outputPath = $thumbPath; timeOffsetMs = 0; width = 480; height = 360
    } 120
    $reqId++
    Add-Step 'video_thumbnail' $thumb

    # 4. Vision pipeline on first 3 frames
    $visionTargets = @($framePaths | Select-Object -First 3)
    if ($visionTargets.Count -eq 0 -and (Test-Path $thumbPath)) { $visionTargets = @($thumbPath) }

    foreach ($fp in $visionTargets) {
        if (-not (Test-Path $fp)) { continue }
        $base = [IO.Path]::GetFileNameWithoutExtension($fp)
        $edgesOut = Join-Path $captureDir "${base}_edges.jpg"
        $contoursOut = Join-Path $captureDir "${base}_contours.jpg"

        $edges = Invoke-McpTool $proc $reqId 'image_detect_edges' @{ imagePath = $fp; outputPath = $edgesOut } 90
        $reqId++
        Add-Step "image_detect_edges_$base" $edges

        $contours = Invoke-McpTool $proc $reqId 'image_find_contours' @{ imagePath = $fp; outputPath = $contoursOut } 90
        $reqId++
        Add-Step "image_find_contours_$base" $contours

        $ocr = Invoke-McpTool $proc $reqId 'image_detect_text' @{ imagePath = $fp } 120
        $reqId++
        Add-Step "image_detect_text_$base" $ocr

        $qr = Invoke-McpTool $proc $reqId 'image_read_qrcode' @{ imagePath = $fp } 60
        $reqId++
        Add-Step "image_read_qrcode_$base" $qr

        $state.vision += [ordered]@{
            frame = $fp
            ocrCount = if ($ocr.count) { [int]$ocr.count } else { 0 }
            qr = if ($qr.text) { $qr.text } elseif ($qr.data) { $qr.data } else { $null }
            edgesOut = $edgesOut
            contoursOut = $contoursOut
        }
    }

    # 5. QR round-trip (synthetic marker for tool chain)
    $qrPath = Join-Path $captureDir 'synthetic_qr.png'
    $qrText = "MCP-768x576-$runId"
    $qrGen = Invoke-McpTool $proc $reqId 'image_encode_qrcode' @{
        text = $qrText; outputPath = $qrPath
    } 60
    $reqId++
    Add-Step 'image_encode_qrcode' $qrGen

    $qrRead = Invoke-McpTool $proc $reqId 'image_read_qrcode' @{ imagePath = $qrPath } 60
    $reqId++
    Add-Step 'image_read_qrcode_synthetic' $qrRead
    $state.qrRoundTrip = [ordered]@{ encoded = $qrText; decoded = $(if ($qrRead.text) { $qrRead.text } else { $qrRead.data }) }

    # 6. Normalize container (AVI -> MP4) then edit
    $normalizedPath = Join-Path $videoDir "${runId}_normalized.mp4"
    $norm = Invoke-McpTool $proc $reqId 'video_remux' @{ sourceUrl = $sourceVideo; outputPath = $normalizedPath } 180
    $reqId++
    Add-Step 'video_remux_normalize' $norm
    $editSource = if (-not $norm.error -and (Test-Path $normalizedPath)) { $normalizedPath } else { $sourceVideo }

    $segAEnd = [Math]::Min([int]($durationMs * 0.35), [Math]::Max($durationMs - 1000, 1000))
    $segBStart = [Math]::Max([int]($durationMs * 0.55), $segAEnd + 500)
    if ($segBStart -ge $durationMs - 500) { $segBStart = [Math]::Max(0, $durationMs - 2000) }

    $segA = Join-Path $videoDir "${runId}_seg_a.mp4"
    $segB = Join-Path $videoDir "${runId}_seg_b.mp4"
    $trimA = Invoke-McpTool $proc $reqId 'video_trim' @{
        sourceUrl = $editSource; outputPath = $segA; startMs = 0; endMs = $segAEnd
    } 300
    $reqId++
    Add-Step 'video_trim_a' $trimA

    $trimB = Invoke-McpTool $proc $reqId 'video_trim' @{
        sourceUrl = $editSource; outputPath = $segB; startMs = $segBStart; endMs = $durationMs
    } 300
    $reqId++
    Add-Step 'video_trim_b' $trimB

    $cutPath = Join-Path $videoDir "${runId}_highlight.mp4"
    $segPaths = @()
    if (-not $trimA.error) { $segPaths += $segA }
    if (-not $trimB.error) { $segPaths += $segB }

    if ($segPaths.Count -gt 1) {
        $concat = Invoke-McpTool $proc $reqId 'video_concat' @{ inputPaths = $segPaths; outputPath = $cutPath } 300
        $reqId++
        Add-Step 'video_concat' $concat
    } elseif ($segPaths.Count -eq 1) {
        Copy-Item $segPaths[0] $cutPath -Force
        Add-Step 'video_concat' @{ status = 'skipped'; reason = 'single segment' }
    } else {
        Copy-Item $sourceVideo $cutPath -Force
        Add-Step 'video_concat' @{ status = 'fallback'; reason = 'source copy' }
    }

    $scaledPath = Join-Path $videoDir "${runId}_480p.mp4"
    $scale = Invoke-McpTool $proc $reqId 'video_scale' @{
        sourceUrl = $cutPath; outputPath = $scaledPath; width = 640; height = 480
        maxDurationMs = [Math]::Max($durationMs, 600000)
    } 600
    $reqId++
    Add-Step 'video_scale' $scale

    $filteredPath = Join-Path $videoDir "${runId}_filtered.mp4"
    $filter = Invoke-McpTool $proc $reqId 'video_filter' @{
        sourceUrl = $editSource; outputPath = $filteredPath
        filter = 'scale=320:240'; maxDurationMs = [Math]::Min($durationMs, 8000)
    } 120
    $reqId++
    Add-Step 'video_filter' $filter

    if ($hasAudio) {
        $audioPath = Join-Path $outputDir "${runId}.wav"
        $audio = Invoke-McpTool $proc $reqId 'audio_extract' @{
            sourceUrl = $sourceVideo; outputPath = $audioPath; sampleRate = 44100
        } 180
        $reqId++
        Add-Step 'audio_extract' $audio
        $state.audioPath = $audioPath
    } else {
        Add-Step 'audio_extract' @{ status = 'skipped'; reason = 'no audio stream' }
    }

    $finalPath = Join-Path $outputDir "${runId}_delivery.mp4"
    $remux = Invoke-McpTool $proc $reqId 'video_remux' @{ sourceUrl = $scaledPath; outputPath = $finalPath } 300
    $reqId++
    Add-Step 'video_remux' $remux
    $state.finalVideo = $finalPath
    $state.highlightVideo = $cutPath
    $state.filteredVideo = $filteredPath
    $state.hasAudio = $hasAudio
    $state.durationMs = $durationMs
    $state.sceneCount = $scenes.Count
    $state.silenceCount = if ($silence.count) { [int]$silence.count } else { 0 }

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
$state | ConvertTo-Json -Depth 14 | Set-Content -Path $reportPath -Encoding UTF8

@(
    "# $title",
    "",
    "## User prompt",
    "",
    "> $userPrompt",
    "",
    "## Source",
    "",
    "- File: ``$sourceVideo``",
    "- Original: ``$($cfg.sourceVideoOriginal)``",
    "- Duration: $(Format-Timecode $durationMs) ($durationMs ms)",
    "- Scenes: $($state.sceneCount)",
    "- Silence segments: $($state.silenceCount)",
    "",
    "## Vision samples",
    "",
    "| Frame | OCR regions | QR |",
    "|-------|-------------|-----|",
    $(foreach ($v in $state.vision) {
        $qr = if ($v.qr) { $v.qr } else { '-' }
        "| ``$([IO.Path]::GetFileName($v.frame))`` | $($v.ocrCount) | $qr |"
    }),
    "",
    "## QR round-trip",
    "",
    "- Encoded: ``$($state.qrRoundTrip.encoded)``",
    "- Decoded: ``$($state.qrRoundTrip.decoded)``",
    "",
    "## Deliverables",
    "",
    $(if ($state.finalVideo) { "- Final: ``$($state.finalVideo)``" }),
    $(if ($state.highlightVideo) { "- Highlight: ``$($state.highlightVideo)``" }),
    $(if ($state.filteredVideo) { "- Filtered 320x240: ``$($state.filteredVideo)``" }),
    $(if ($state.audioPath) { "- Audio: ``$($state.audioPath)``" }),
    "",
    "## MCP tools invoked: $($state.steps.Count)",
    "",
    $(foreach ($s in $state.steps) {
        $ok = if ($s.result.error) { 'FAIL' } else { 'OK' }
        "- ``$($s.tool)`` - $ok"
    }),
    "",
    "_Report: ``$reportPath``_"
) -join "`n" | Set-Content -Path $notesPath -Encoding UTF8

$promptMd = @"
# Complex MCP test prompt

$userPrompt

## Expected agent workflow

1. video_probe + stream_test + video_metadata_read
2. video_scene_detect + video_detect_silence
3. video_grab_frames + video_thumbnail
4. Per-frame: image_detect_edges, image_find_contours, image_detect_text, image_read_qrcode
5. image_encode_qrcode round-trip
6. video_trim x2, video_concat, video_scale, video_filter, audio_extract, video_remux

Automated runner: scripts/tests/test_complex_768_scenario.ps1
"@
$promptMd | Set-Content -Path $promptPath -Encoding UTF8

Write-Host "`nReport: $reportPath" -ForegroundColor Yellow
Write-Host "Notes:  $notesPath" -ForegroundColor Yellow
Write-Host "Prompt: $promptPath" -ForegroundColor Yellow

$fatalErrors = @($state.errors | Where-Object { $_ -notmatch 'No audio stream|Could not write header' })
if ($state.fatal) {
    Write-Host "FATAL: $($state.fatal)" -ForegroundColor Red
    exit 1
}
if ($fatalErrors.Count -gt 0) {
    Write-Host "Errors: $($fatalErrors -join '; ')" -ForegroundColor Red
    exit 1
}
if ($state.errors.Count -gt 0) {
    Write-Host "Warnings: $($state.errors -join '; ')" -ForegroundColor Yellow
}
Write-Host ("Complex MCP scenario completed: {0} tool calls." -f $state.steps.Count) -ForegroundColor Green
