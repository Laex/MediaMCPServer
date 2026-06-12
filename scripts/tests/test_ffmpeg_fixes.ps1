$ErrorActionPreference = "Stop"
. (Join-Path (Split-Path $PSScriptRoot -Parent) '_common.ps1')

$exePath = Join-Path $BinDir 'MediaMCPServer.exe'
$videoPath = Join-Path (Split-Path $ProjectRoot -Parent) 'Delphi-FFMPEG\resource\768x576.avi'
$trimOut = Join-Path (Join-Path $MediaDir 'video') 'trim_fix_test.mp4'

function Start-McpSession {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $exePath
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
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

function Invoke-Tool($proc, $id, [string]$name, [string]$argumentsJson) {
    $req = '{"jsonrpc":"2.0","id":' + $id + ',"method":"tools/call","params":{"name":"' + $name + '","arguments":' + $argumentsJson + '}}'
    $resp = Send-McpRequest $proc $req
    if ($resp.error) { throw $resp.error.message }
    return $resp.result.content[0].text | ConvertFrom-Json
}

$proc = Start-McpSession
try {
    $null = Send-McpRequest $proc '{"jsonrpc":"2.0","id":0,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"ffmpeg-fix-test","version":"1"}}}'
    $proc.StandardInput.WriteLine('{"jsonrpc":"2.0","method":"notifications/initialized","params":{}}')

    $videoEsc = $videoPath -replace '\\', '\\'
    $trimEsc = $trimOut -replace '\\', '\\'

    $meta = Invoke-Tool $proc 1 'video_metadata_read' ('{"sourceUrl":"' + $videoEsc + '"}')
    Write-Host "metadata_read:" ($meta | ConvertTo-Json -Compress -Depth 5) -ForegroundColor Cyan
    if (-not $meta.metadata -or ($meta.metadata.Count -eq 0)) { throw 'metadata_read returned empty metadata' }

    $trim = Invoke-Tool $proc 2 'video_trim' ('{"sourceUrl":"' + $videoEsc + '","outputPath":"' + $trimEsc + '","startMs":0,"endMs":5000}')
    Write-Host "video_trim:" ($trim | ConvertTo-Json -Compress -Depth 5) -ForegroundColor Green
    if ($trim.error) { throw $trim.error }
    if (-not (Test-Path $trimOut)) { throw "trim output not created: $trimOut" }
} finally {
    $proc.StandardInput.Close()
    if (-not $proc.WaitForExit(180000)) { $proc.Kill() }
    $proc.Close()
}

Write-Host "FFmpeg fix tests passed." -ForegroundColor Green
