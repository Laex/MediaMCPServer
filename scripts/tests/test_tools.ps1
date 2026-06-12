$ErrorActionPreference = "Stop"
. (Join-Path (Split-Path $PSScriptRoot -Parent) '_common.ps1')

$exePath = Join-Path $BinDir 'MediaMCPServer.exe'
$testImage = Join-Path $OpenCvRoot 'bin\test.png'
$outputFrame = Join-Path $MediaDir 'captures\test_webcam_frame.jpg'

if (-not (Test-Path $exePath)) { Write-Error "Executable not found. Run build.ps1 first." }

function Start-McpSession {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $exePath
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    return [System.Diagnostics.Process]::Start($psi)
}

function Send-McpRequest($proc, [string]$jsonLine) {
    $proc.StandardInput.WriteLine($jsonLine)
    return $proc.StandardOutput.ReadLine() | ConvertFrom-Json
}

function Show-ToolResult($name, $response) {
    Write-Host "`n--- $name ---" -ForegroundColor Cyan
    if ($response.error) { Write-Host "JSON-RPC ERROR: $($response.error.message)" -ForegroundColor Red; return }
    $text = $response.result.content[0].text
    $payload = $text | ConvertFrom-Json
    if ($payload.error) { Write-Host "TOOL ERROR: $($payload.error)" -ForegroundColor Red }
    else { Write-Host ($payload | ConvertTo-Json -Compress -Depth 6) -ForegroundColor Green }
}

$proc = Start-McpSession
try {
    $null = Send-McpRequest $proc '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"tool-test","version":"1.0"}}}'
    $proc.StandardInput.WriteLine('{"jsonrpc":"2.0","method":"notifications/initialized"}')
    Start-Sleep -Milliseconds 100
    Show-ToolResult 'webcam_list' (Send-McpRequest $proc '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"webcam_list","arguments":{}}}')
    Show-ToolResult 'camera_discover' (Send-McpRequest $proc '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"camera_discover","arguments":{}}}')
    if (Test-Path $testImage) {
        $detectReq = '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"image_detect_objects","arguments":{"imagePath":"' + ($testImage -replace '\\','\\') + '"}}}'
        Show-ToolResult 'image_detect_objects' (Send-McpRequest $proc $detectReq)
    }
    $frameReq = '{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"webcam_grab_frame","arguments":{"cameraIndex":0,"outputPath":"' + ($outputFrame -replace '\\','\\') + '"}}}'
    Show-ToolResult 'webcam_grab_frame' (Send-McpRequest $proc $frameReq)
} finally {
    $proc.StandardInput.Close()
    if (-not $proc.WaitForExit(10000)) { $proc.Kill() }
    $proc.Close()
}

Write-Host "`nAll tool tests finished." -ForegroundColor Green
