$ErrorActionPreference = "Stop"
. (Join-Path (Split-Path $PSScriptRoot -Parent) '_common.ps1')

$exePath = Join-Path $BinDir 'MediaMCPServer.exe'
if (-not (Test-Path $exePath)) { Write-Error "Run build.ps1 first: $exePath" }

$testImage = Join-Path $OpenCvRoot 'bin\test.png'
$textSample = Join-Path $OpenCvRoot 'bin\text_sample.png'
$demoQr = Join-Path $OpenCvRoot 'bin\demo_obj_qrcode.png'
$demoAruco = Join-Path $OpenCvRoot 'bin\demo_obj_aruco.png'
$demoCircles = Join-Path $OpenCvRoot 'bin\demo_obj_circles.png'

# Fallback: frame from prior FFmpeg capture runs
if (-not (Test-Path $testImage)) {
    $fallbacks = @(
        (Join-Path $MediaDir 'captures\ffmpeg_all_20260612_141406\frame_0.jpg'),
        (Join-Path $MediaDir 'captures\complex_768x576\frame_0.jpg')
    )
    foreach ($fb in $fallbacks) {
        if (Test-Path $fb) { $testImage = $fb; break }
    }
}
if (-not (Test-Path $testImage)) { Write-Error "No test image found (expected OpenCV\OpenCV 5.0\bin\test.png)" }

$runId = 'opencv_all_' + (Get-Date -Format 'yyyyMMdd_HHmmss')
$capDir = Join-Path $MediaDir "captures\$runId"
$outDir = Join-Path $MediaDir "output\$runId"
$vidDir = Join-Path $MediaDir "video\$runId"
New-Item -ItemType Directory -Force -Path $capDir, $outDir, $vidDir | Out-Null

$results = [System.Collections.Generic.List[object]]::new()
$pass = 0
$fail = 0
$skip = 0

function Esc([string]$p) { return $p -replace '\\', '\\' }

function Start-McpSession {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $exePath
    $psi.Arguments = '--stdio'
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $psi.WorkingDirectory = $BinDir
    $proc = [System.Diagnostics.Process]::Start($psi)
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

function Add-Result($r, [string]$note, [switch]$SkipOnNoFace) {
    if (-not $r.ok -and $SkipOnNoFace -and $r.error -match 'No face') {
        Add-Skip $r.tool $r.error
        return
    }
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

Write-Host "=== OpenCV MCP tools test run: $runId ===" -ForegroundColor Yellow
Write-Host "Test image: $testImage"

$imgEsc = Esc $testImage
$reqId = 1
$proc = Start-McpSession

try {
    $null = Send-McpRequest $proc '{"jsonrpc":"2.0","id":0,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"opencv-all-tools","version":"1"}}}'
    $proc.StandardInput.WriteLine('{"jsonrpc":"2.0","method":"notifications/initialized","params":{}}')

    # Core detection
    $r = Invoke-McpTool $proc $reqId 'image_detect_objects' ('{"imagePath":"' + $imgEsc + '"}'); $reqId++
    Add-Result $r 'YOLOX object detection'

    $r = Invoke-McpTool $proc $reqId 'image_detect_faces' ('{"imagePath":"' + $imgEsc + '"}'); $reqId++
    Add-Result $r 'YuNet face detection'

    # DNN tools
    $r = Invoke-McpTool $proc $reqId 'image_classify' ('{"imagePath":"' + $imgEsc + '"}'); $reqId++
    Add-Result $r 'MobileNet classify'

    $segOut = Join-Path $outDir 'segment_mask.png'
    $r = Invoke-McpTool $proc $reqId 'image_segment_person' ('{"imagePath":"' + $imgEsc + '","outputPath":"' + (Esc $segOut) + '"}'); $reqId++
    Add-Result $r 'person segmentation'

    $textImg = if (Test-Path $textSample) { $textSample } else { $testImage }
    $r = Invoke-McpTool $proc $reqId 'image_detect_text' ('{"imagePath":"' + (Esc $textImg) + '"}'); $reqId++
    Add-Result $r 'PPOCR text detection'

    $eastImg = if (Test-Path $textSample) { $textSample } else { $testImage }
    $r = Invoke-McpTool $proc $reqId 'image_detect_text_east' ('{"imagePath":"' + (Esc $eastImg) + '"}'); $reqId++
    Add-Result $r 'EAST text detection'

    # Face registry
    $r = Invoke-McpTool $proc $reqId 'face_list' '{}'; $reqId++
    Add-Result $r 'face_list'

    # Image processing
    $qrReadImg = if (Test-Path $demoQr) { $demoQr } else { $testImage }
    $r = Invoke-McpTool $proc $reqId 'image_read_qrcode' ('{"imagePath":"' + (Esc $qrReadImg) + '"}'); $reqId++
    Add-Result $r 'read QR'

    $qrOut = Join-Path $outDir 'generated_qr.png'
    $r = Invoke-McpTool $proc $reqId 'image_encode_qrcode' ('{"text":"MCP-OpenCV-test","outputPath":"' + (Esc $qrOut) + '"}'); $reqId++
    Add-Result $r 'encode QR'

    $r = Invoke-McpTool $proc $reqId 'image_read_barcode' ('{"imagePath":"' + $imgEsc + '"}'); $reqId++
    Add-Result $r 'read barcode (may be 0)'

    $arucoImg = if (Test-Path $demoAruco) { $demoAruco } else { $testImage }
    $r = Invoke-McpTool $proc $reqId 'image_detect_aruco' ('{"imagePath":"' + (Esc $arucoImg) + '"}'); $reqId++
    Add-Result $r 'ArUco markers'

    $tmplOut = Join-Path $outDir 'template_match.png'
    $r = Invoke-McpTool $proc $reqId 'image_template_match' ('{"imagePath":"' + $imgEsc + '","templatePath":"' + $imgEsc + '","outputPath":"' + (Esc $tmplOut) + '"}'); $reqId++
    Add-Result $r 'template match self'

    $contOut = Join-Path $outDir 'contours.png'
    $r = Invoke-McpTool $proc $reqId 'image_find_contours' ('{"imagePath":"' + $imgEsc + '","outputPath":"' + (Esc $contOut) + '"}'); $reqId++
    Add-Result $r 'find contours'

    $edgeOut = Join-Path $outDir 'edges.png'
    $r = Invoke-McpTool $proc $reqId 'image_detect_edges' ('{"imagePath":"' + $imgEsc + '","outputPath":"' + (Esc $edgeOut) + '"}'); $reqId++
    Add-Result $r 'Canny edges'

    $lineOut = Join-Path $outDir 'lines.png'
    $r = Invoke-McpTool $proc $reqId 'image_detect_lines' ('{"imagePath":"' + $imgEsc + '","outputPath":"' + (Esc $lineOut) + '"}'); $reqId++
    Add-Result $r 'Hough lines'

    $circImg = if (Test-Path $demoCircles) { $demoCircles } else { $testImage }
    $circOut = Join-Path $outDir 'circles.png'
    $r = Invoke-McpTool $proc $reqId 'image_detect_circles' ('{"imagePath":"' + (Esc $circImg) + '","outputPath":"' + (Esc $circOut) + '"}'); $reqId++
    Add-Result $r 'Hough circles'

    $xfOut = Join-Path $outDir 'transform.png'
    $r = Invoke-McpTool $proc $reqId 'image_transform' ('{"imagePath":"' + $imgEsc + '","outputPath":"' + (Esc $xfOut) + '","width":320,"height":240}'); $reqId++
    Add-Result $r 'resize transform'

    $annOut = Join-Path $outDir 'annotated.png'
    $r = Invoke-McpTool $proc $reqId 'image_annotate' ('{"imagePath":"' + $imgEsc + '","outputPath":"' + (Esc $annOut) + '","mode":"both"}'); $reqId++
    Add-Result $r 'annotate objects+faces'

    # Two-frame optical flow (same image => low motion)
    $flowOut = Join-Path $outDir 'optical_flow.png'
    $r = Invoke-McpTool $proc $reqId 'image_optical_flow' ('{"imagePath1":"' + $imgEsc + '","imagePath2":"' + $imgEsc + '","outputPath":"' + (Esc $flowOut) + '"}'); $reqId++
    Add-Result $r 'Farneback optical flow'

    # Webcam tools (hardware-dependent)
    $r = Invoke-McpTool $proc $reqId 'webcam_list' '{}'; $reqId++
    if ($r.ok -and $r.payload.cameras -and $r.payload.cameras.Count -gt 0) {
        Add-Result $r 'webcam_list'
        $frameOut = Join-Path $capDir 'webcam_frame.jpg'
        $r = Invoke-McpTool $proc $reqId 'webcam_grab_frame' ('{"cameraIndex":0,"outputPath":"' + (Esc $frameOut) + '"}'); $reqId++
        Add-Result $r 'webcam_grab_frame'

        if ($r.ok -and (Test-Path $frameOut)) {
            $faceEsc = Esc $frameOut
            $r = Invoke-McpTool $proc $reqId 'face_compare' ('{"imagePath1":"' + $faceEsc + '","imagePath2":"' + $faceEsc + '"}'); $reqId++
            Add-Result $r 'face_compare webcam frame' -SkipOnNoFace
            $r = Invoke-McpTool $proc $reqId 'face_enroll' ('{"imagePath":"' + $faceEsc + '","name":"test_opencv_run"}'); $reqId++
            Add-Result $r 'face_enroll from webcam' -SkipOnNoFace
            $r = Invoke-McpTool $proc $reqId 'face_identify' ('{"imagePath":"' + $faceEsc + '"}'); $reqId++
            Add-Result $r 'face_identify enrolled' -SkipOnNoFace
        } else {
            Add-Skip 'face_compare' 'no webcam frame with face'
            Add-Skip 'face_enroll' 'no webcam frame'
            Add-Skip 'face_identify' 'no webcam frame'
        }

        $vidOut = Join-Path $vidDir 'webcam_clip.avi'
        $r = Invoke-McpTool $proc $reqId 'webcam_record_video' ('{"cameraIndex":0,"outputPath":"' + (Esc $vidOut) + '","durationMs":1500}'); $reqId++
        Add-Result $r 'webcam_record_video 1.5s'

        if (Test-Path (Join-Path $BinDir 'backbone.onnx')) {
            $trackOut = Join-Path $vidDir 'track.avi'
            $r = Invoke-McpTool $proc $reqId 'video_track_object' ('{"cameraIndex":0,"x":50,"y":50,"width":120,"height":120,"frameCount":10,"outputPath":"' + (Esc $trackOut) + '"}'); $reqId++
            Add-Result $r 'video_track_object'
        } else {
            Add-Skip 'video_track_object' 'backbone.onnx not in bin'
        }
    } else {
        Add-Skip 'webcam_grab_frame' 'no webcam detected'
        Add-Skip 'face_compare' 'no webcam'
        Add-Skip 'face_enroll' 'no webcam'
        Add-Skip 'face_identify' 'no webcam'
        Add-Skip 'webcam_record_video' 'no webcam detected'
        Add-Skip 'video_track_object' 'no webcam detected'
        if (-not $r.ok) { Add-Result $r 'webcam_list failed' } else { Add-Result $r 'webcam_list (empty)' }
    }

} finally {
    $proc.StandardInput.Close()
    if (-not $proc.WaitForExit(120000)) { $proc.Kill() }
    $proc.Close()
}

$reportPath = Join-Path $outDir 'opencv_tools_report.json'
$summary = [pscustomobject]@{
    runId   = $runId
    pass    = $pass
    fail    = $fail
    skip    = $skip
    results = $results
}
$summary | ConvertTo-Json -Depth 6 | Set-Content -Path $reportPath -Encoding UTF8

Write-Host ""
Write-Host "=== Summary: $pass PASS, $fail FAIL, $skip SKIP ===" -ForegroundColor $(if ($fail -eq 0) { 'Green' } else { 'Red' })
Write-Host "Report: $reportPath"

if ($fail -gt 0) { exit 1 }
