$ErrorActionPreference = "Stop"
. (Join-Path (Split-Path $PSScriptRoot -Parent) '_common.ps1')

$exePath = Join-Path $BinDir 'MediaMCPServer.exe'
if (-not (Test-Path $exePath)) { Write-Error "Run build.ps1 first: $exePath" }

$videoAvi = Join-Path (Join-Path $MediaDir 'input') '768x576.avi'
if (-not (Test-Path $videoAvi)) {
    $videoAvi = Join-Path (Split-Path $ProjectRoot -Parent) 'Delphi-FFMPEG\resource\768x576.avi'
}
$videoMp4 = Join-Path (Join-Path $MediaDir 'input') 'lecture_kinematika_1.mp4'

if (-not (Test-Path $videoAvi)) { Write-Error "Test AVI not found" }
if (-not (Test-Path $videoMp4)) { Write-Error "Test MP4 with audio not found: $videoMp4" }

$runId = 'ffmpeg_all_' + (Get-Date -Format 'yyyyMMdd_HHmmss')
$capDir = Join-Path $MediaDir "captures\$runId"
$vidDir = Join-Path $MediaDir "video\$runId"
$outDir = Join-Path $MediaDir "output\$runId"
New-Item -ItemType Directory -Force -Path $capDir, $vidDir, $outDir | Out-Null

$results = [System.Collections.Generic.List[object]]::new()
$pass = 0
$fail = 0
$skip = 0

function Esc([string]$p) { return $p -replace '\\', '\\' }

function Start-McpSession {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $exePath
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $proc = [System.Diagnostics.Process]::Start($psi)
    # Drain stderr so libx264/FFmpeg logs cannot block the MCP process
    $proc.EnableRaisingEvents = $true
    $null = Register-ObjectEvent -InputObject $proc -EventName ErrorDataReceived -Action { } -SupportEvent
    $proc.BeginErrorReadLine()
    return $proc
}

function Send-McpRequest($proc, [string]$jsonLine) {
    $proc.StandardInput.WriteLine($jsonLine)
    return $proc.StandardOutput.ReadLine() | ConvertFrom-Json
}

function Invoke-McpTool($proc, [int]$id, [string]$name, [string]$argumentsJson) {
    try {
        $req = '{"jsonrpc":"2.0","id":' + $id + ',"method":"tools/call","params":{"name":"' + $name + '","arguments":' + $argumentsJson + '}}'
        $resp = Send-McpRequest $proc $req
        if ($resp.error) {
            return @{ tool = $name; ok = $false; error = $resp.error.message; payload = $null }
        }
        $payload = $resp.result.content[0].text | ConvertFrom-Json
        if ($payload.error) {
            return @{ tool = $name; ok = $false; error = $payload.error; payload = $payload }
        }
        return @{ tool = $name; ok = $true; error = $null; payload = $payload }
    } catch {
        return @{ tool = $name; ok = $false; error = $_.Exception.Message; payload = $null }
    }
}

function Add-Result($r, [string]$note) {
    $status = if ($r.ok) { 'PASS' } else { 'FAIL' }
    Write-Host ("  [{0}] {1} - {2}" -f $status, $r.tool, $note) -ForegroundColor $(if ($r.ok) { 'Green' } else { 'Red' })
    if ($r.error) { Write-Host "         $($r.error)" -ForegroundColor DarkRed }
    $script:results.Add([pscustomobject]@{
        tool   = $r.tool
        status = $status
        note   = $note
        error  = $r.error
        detail = if ($r.payload) { ($r.payload | ConvertTo-Json -Compress -Depth 4) } else { $null }
    })
    if ($r.ok) { $script:pass++ } else { $script:fail++ }
}

function Add-Skip([string]$tool, [string]$reason) {
    Write-Host ("  [SKIP] {0} - {1}" -f $tool, $reason) -ForegroundColor Yellow
    $script:results.Add([pscustomobject]@{
        tool = $tool; status = 'SKIP'; note = $reason; error = $null; detail = $null
    })
    $script:skip++
}

Write-Host "=== FFmpeg MCP tools test run: $runId ===" -ForegroundColor Yellow
Write-Host "AVI: $videoAvi"
Write-Host "MP4: $videoMp4"

$aviEsc = Esc $videoAvi
$mp4Esc = Esc $videoMp4
$reqId = 1

$proc = Start-McpSession
try {
    $null = Send-McpRequest $proc '{"jsonrpc":"2.0","id":0,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"ffmpeg-all-tools","version":"1"}}}'
    $proc.StandardInput.WriteLine('{"jsonrpc":"2.0","method":"notifications/initialized","params":{}}')

    # 1 video_probe
    $r = Invoke-McpTool $proc $reqId 'video_probe' ('{"sourceUrl":"' + $aviEsc + '"}'); $reqId++
    Add-Result $r 'probe AVI'
    $durationMs = if ($r.ok -and $r.payload.durationMs) { [int]$r.payload.durationMs } else { 20000 }

    # 2 stream_test
    $r = Invoke-McpTool $proc $reqId 'stream_test' ('{"sourceUrl":"' + $aviEsc + '","timeoutMs":5000}'); $reqId++
    Add-Result $r 'stream_test AVI'

    # 3 video_grab_frame
    $f0 = Join-Path $capDir 'frame_0.jpg'
    $r = Invoke-McpTool $proc $reqId 'video_grab_frame' ('{"sourceUrl":"' + $aviEsc + '","outputPath":"' + (Esc $f0) + '","timeOffsetMs":0}'); $reqId++
    Add-Result $r 'grab frame at 0ms'

    # 4 video_grab_frames
    $r = Invoke-McpTool $proc $reqId 'video_grab_frames' ('{"sourceUrl":"' + $aviEsc + '","outputDir":"' + (Esc $capDir) + '","timeOffsetMs":0,"intervalMs":2000,"count":3}'); $reqId++
    Add-Result $r 'grab 3 frames'

    # 5 video_thumbnail
    $thumb = Join-Path $capDir 'thumb.jpg'
    $r = Invoke-McpTool $proc $reqId 'video_thumbnail' ('{"sourceUrl":"' + $aviEsc + '","outputPath":"' + (Esc $thumb) + '","timeOffsetMs":1000}'); $reqId++
    Add-Result $r 'thumbnail at 1s'

    # 6 video_remux (AVI -> AVI stream copy)
    $remuxAvi = Join-Path $vidDir 'copy.avi'
    $r = Invoke-McpTool $proc $reqId 'video_remux' ('{"sourceUrl":"' + $aviEsc + '","outputPath":"' + (Esc $remuxAvi) + '"}'); $reqId++
    Add-Result $r 'remux AVI->AVI'

    # 7 video_trim (AVI -> MP4 transcode fallback)
    $segA = Join-Path $vidDir 'seg_a.mp4'
    $segEnd = 3000
    $r = Invoke-McpTool $proc $reqId 'video_trim' ('{"sourceUrl":"' + $aviEsc + '","outputPath":"' + (Esc $segA) + '","startMs":0,"endMs":' + $segEnd + '}'); $reqId++
    Add-Result $r "trim 0..${segEnd}ms"

    # 8 video_trim segment B
    $segB = Join-Path $vidDir 'seg_b.mp4'
    $segBStart = 5000
    $segBEnd = [Math]::Min(8000, $durationMs)
    $r = Invoke-McpTool $proc $reqId 'video_trim' ('{"sourceUrl":"' + $aviEsc + '","outputPath":"' + (Esc $segB) + '","startMs":' + $segBStart + ',"endMs":' + $segBEnd + '}'); $reqId++
    Add-Result $r "trim ${segBStart}..${segBEnd}ms"
    $segAOk = (Test-Path $segA)
    $segBOk = (Test-Path $segB)

    # 9 video_concat
  if ($segAOk -and $segBOk) {
        $concatOut = Join-Path $vidDir 'concat.mp4'
        $concatArgs = '{"inputPaths":["' + (Esc $segA) + '","' + (Esc $segB) + '"],"outputPath":"' + (Esc $concatOut) + '"}'
        $r = Invoke-McpTool $proc $reqId 'video_concat' $concatArgs; $reqId++
        Add-Result $r 'concat 2 segments'
    } else {
        Add-Skip 'video_concat' 'trim segments missing'
    }

    # 10 audio_extract — use short MP4 clip fixture (avoid trimming 24min lecture each run)
    $audioClipFixture = Join-Path (Join-Path $MediaDir 'input') 'lecture_clip_5s.mp4'
    $audioClip = Join-Path $vidDir 'audio_clip.mp4'
    if (Test-Path $audioClipFixture) {
        Copy-Item $audioClipFixture $audioClip -Force
        Add-Skip 'video_trim_audio_clip' 'using cached lecture_clip_5s.mp4 fixture'
    } else {
        $r = Invoke-McpTool $proc $reqId 'video_trim' ('{"sourceUrl":"' + $mp4Esc + '","outputPath":"' + (Esc $audioClip) + '","startMs":0,"endMs":5000}'); $reqId++
        Add-Result $r 'prepare 5s clip for audio test (slow first run)'
        if ($r.ok) { Copy-Item $audioClip $audioClipFixture -Force }
    }
    $audioOut = Join-Path $outDir 'audio.pcm'
    if (Test-Path $audioClip) {
        $r = Invoke-McpTool $proc $reqId 'audio_extract' ('{"sourceUrl":"' + (Esc $audioClip) + '","outputPath":"' + (Esc $audioOut) + '","sampleRate":44100}'); $reqId++
        Add-Result $r 'extract audio from 5s MP4 clip'
    } else {
        Add-Skip 'audio_extract' 'audio clip not created'
    }

    # 11 audio_extract expected fail on AVI without audio
    $r = Invoke-McpTool $proc $reqId 'audio_extract' ('{"sourceUrl":"' + $aviEsc + '","outputPath":"' + (Esc (Join-Path $outDir 'no_audio.pcm')) + '"}'); $reqId++
    if (-not $r.ok -and $r.error -match 'No audio') {
        Add-Skip 'audio_extract_no_audio' 'expected: no audio in AVI'
    } else {
        Add-Result $r 'unexpected result for AVI without audio'
    }

    # 12 video_record_segment (AVI container for stream copy)
    $recOut = Join-Path $vidDir 'recorded.avi'
    $r = Invoke-McpTool $proc $reqId 'video_record_segment' ('{"sourceUrl":"' + $aviEsc + '","outputPath":"' + (Esc $recOut) + '","durationMs":3000}'); $reqId++
    Add-Result $r 'record 3s from file'

    # 13 video_scale
    $scaled = Join-Path $vidDir 'scaled_480p.mp4'
    $r = Invoke-McpTool $proc $reqId 'video_scale' ('{"sourceUrl":"' + $aviEsc + '","outputPath":"' + (Esc $scaled) + '","width":640,"height":480,"maxDurationMs":5000}'); $reqId++
    Add-Result $r 'scale to 640x480'

    # 14 video_filter
    $filtered = Join-Path $vidDir 'filtered.mp4'
    $r = Invoke-McpTool $proc $reqId 'video_filter' ('{"sourceUrl":"' + $aviEsc + '","outputPath":"' + (Esc $filtered) + '","filter":"scale=320:240","maxDurationMs":5000}'); $reqId++
    Add-Result $r 'filter scale=320:240'

    # 15 video_detect_silence — on short clip
    if (Test-Path $audioClip) {
        $r = Invoke-McpTool $proc $reqId 'video_detect_silence' ('{"sourceUrl":"' + (Esc $audioClip) + '","noiseDb":-30,"minSilenceMs":500}'); $reqId++
        Add-Result $r 'silence detect on 5s clip'
    } else {
        Add-Skip 'video_detect_silence' 'audio clip not available'
    }

    # 16 video_detect_silence expected fail AVI
    $r = Invoke-McpTool $proc $reqId 'video_detect_silence' ('{"sourceUrl":"' + $aviEsc + '"}'); $reqId++
    if (-not $r.ok -and $r.error -match 'No audio') {
        Add-Skip 'video_detect_silence_no_audio' 'expected: no audio in AVI'
    } else {
        Add-Result $r 'unexpected silence result for AVI'
    }

    # 17 video_scene_detect
    $r = Invoke-McpTool $proc $reqId 'video_scene_detect' ('{"sourceUrl":"' + $aviEsc + '","threshold":0.25,"maxScenes":10}'); $reqId++
    Add-Result $r 'scene detect AVI'

    # 18 video_metadata_read
    $r = Invoke-McpTool $proc $reqId 'video_metadata_read' ('{"sourceUrl":"' + $aviEsc + '"}'); $reqId++
    $metaOk = $r.ok -and $r.payload.metadata -and ($r.payload.metadata.Count -gt 0)
    if ($metaOk) { Add-Result $r 'metadata AVI' }
    else { Add-Result @{ tool = 'video_metadata_read'; ok = $false; error = 'empty metadata'; payload = $r.payload } 'metadata AVI' }

    # 19 video_probe MP4 (short clip)
    if (Test-Path $audioClip) {
        $r = Invoke-McpTool $proc $reqId 'video_probe' ('{"sourceUrl":"' + (Esc $audioClip) + '"}'); $reqId++
        Add-Result $r 'probe 5s MP4 clip'
    } else {
        Add-Skip 'video_probe_mp4' 'clip not available'
    }

    # 20 video_remux MP4->MP4 (h264 stream copy on short clip)
    if (Test-Path $audioClip) {
        $remuxMp4 = Join-Path $vidDir 'clip_copy.mp4'
        $r = Invoke-McpTool $proc $reqId 'video_remux' ('{"sourceUrl":"' + (Esc $audioClip) + '","outputPath":"' + (Esc $remuxMp4) + '"}'); $reqId++
        Add-Result $r 'remux MP4->MP4 clip'
    } else {
        Add-Skip 'video_remux_mp4' 'clip not available'
    }

} finally {
    $proc.StandardInput.Close()
    if (-not $proc.WaitForExit(300000)) { $proc.Kill() }
    $proc.Close()
}

$reportPath = Join-Path $outDir 'ffmpeg_tools_report.json'
$results | ConvertTo-Json -Depth 5 | Set-Content -Path $reportPath -Encoding UTF8

Write-Host "`n=== Summary ===" -ForegroundColor Cyan
$results | ForEach-Object {
    $color = switch ($_.status) { 'PASS' { 'Green' } 'SKIP' { 'Yellow' } default { 'Red' } }
    Write-Host ("[{0}] {1} - {2}" -f $_.status, $_.tool, $_.note) -ForegroundColor $color
    if ($_.error) { Write-Host "       $($_.error)" -ForegroundColor DarkRed }
}

Write-Host "`nPASS: $pass  FAIL: $fail  SKIP: $skip" -ForegroundColor $(if ($fail -eq 0) { 'Green' } else { 'Red' })
Write-Host "Report: $reportPath" -ForegroundColor Gray

if ($fail -gt 0) { exit 1 }
