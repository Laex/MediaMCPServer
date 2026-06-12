$ErrorActionPreference = "Stop"
. (Join-Path (Split-Path $PSScriptRoot -Parent) '_common.ps1')

$exePath = Join-Path $BinDir 'MediaMCPServer.exe'
$outFrame = Join-Path $MediaDir 'captures\webcam_now.jpg'

if (-not (Test-Path $exePath)) { Write-Error "Run build.ps1 first." }

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
    if ($response.error) { Write-Host "JSON-RPC ERROR: $($response.error.message)" -ForegroundColor Red; return $null }
    $payload = $response.result.content[0].text | ConvertFrom-Json
    if ($payload.error) { Write-Host "TOOL ERROR: $($payload.error)" -ForegroundColor Red; return $null }
    Write-Host ($payload | ConvertTo-Json -Compress -Depth 8) -ForegroundColor Green
    return $payload
}

function Invoke-McpTool($name, [string]$argumentsJson, $id) {
    $proc = Start-McpSession
    try {
        $null = Send-McpRequest $proc '{"jsonrpc":"2.0","id":0,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"webcam-mcp-test","version":"1"}}}'
        $proc.StandardInput.WriteLine('{"jsonrpc":"2.0","method":"notifications/initialized","params":{}}')
        $req = '{"jsonrpc":"2.0","id":' + $id + ',"method":"tools/call","params":{"name":"' + $name + '","arguments":' + $argumentsJson + '}}'
        return Show-ToolResult $name (Send-McpRequest $proc $req)
    } finally {
        $proc.StandardInput.Close()
        if (-not $proc.WaitForExit(180000)) { $proc.Kill() }
        $proc.Close()
    }
}

Write-Host "MCP webcam check" -ForegroundColor Yellow
$outEsc = $outFrame -replace '\\', '\\'
$grab = Invoke-McpTool 'webcam_grab_frame' ('{"cameraIndex":0,"outputPath":"' + $outEsc + '"}') 2
if ($grab -and $grab.outputPath) {
    $imgEsc = $grab.outputPath -replace '\\', '\\'
    Invoke-McpTool 'image_detect_faces' ('{"imagePath":"' + $imgEsc + '"}') 4 | Out-Null
    Invoke-McpTool 'image_detect_objects' ('{"imagePath":"' + $imgEsc + '"}') 5 | Out-Null
    Invoke-McpTool 'face_identify' ('{"imagePath":"' + $imgEsc + '","threshold":0.8}') 6 | Out-Null
}

Write-Host "`nDone (MCP only)." -ForegroundColor Green
