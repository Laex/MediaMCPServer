$ErrorActionPreference = "Stop"
. (Join-Path (Split-Path $PSScriptRoot -Parent) '_common.ps1')

$Port = if ($env:MEDIA_MCP_HTTP_PORT) { [int]$env:MEDIA_MCP_HTTP_PORT } else { 9876 }
$BaseUrl = "http://127.0.0.1:$Port/mcp"
$ExePath = Join-Path $BinDir 'MediaMCPServer.exe'

if (-not (Test-Path $ExePath)) { Write-Error "Executable not found: $ExePath" }

$proc = Start-Process -FilePath $ExePath -ArgumentList @('--http', '--port', $Port) -WorkingDirectory $BinDir -PassThru -WindowStyle Hidden
Start-Sleep -Seconds 2

function Invoke-McpHttp {
    param([string]$Body, [string]$SessionId = '')
    $headers = @{
        'Accept' = 'application/json, text/event-stream'
        'Content-Type' = 'application/json'
    }
    if ($SessionId) { $headers['Mcp-Session-Id'] = $SessionId }
    try {
        $resp = Invoke-WebRequest -Uri $BaseUrl -Method POST -Headers $headers -Body $Body -UseBasicParsing
        return @{ Status = $resp.StatusCode; Headers = $resp.Headers; Content = $resp.Content }
    } catch {
        if ($_.Exception.Response) {
            $r = $_.Exception.Response
            $reader = New-Object System.IO.StreamReader($r.GetResponseStream())
            $content = $reader.ReadToEnd()
            return @{ Status = [int]$r.StatusCode; Headers = @{}; Content = $content }
        }
        throw
    }
}

try {
    Write-Host "HTTP MCP test: $BaseUrl" -ForegroundColor Cyan
    $init = Invoke-McpHttp '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"http-test","version":"1"}}}'
    if ($init.Status -ne 200) { throw "initialize failed: $($init.Status) $($init.Content)" }
    $session = $init.Headers['Mcp-Session-Id']
    if (-not $session) { $session = $init.Headers['mcp-session-id'] }
    if (-not $session) { throw 'Missing Mcp-Session-Id header' }
    Write-Host "Session: $session" -ForegroundColor Green

    $ack = Invoke-McpHttp '{"jsonrpc":"2.0","method":"notifications/initialized"}' $session
    if ($ack.Status -ne 202) { throw "initialized notification failed: $($ack.Status)" }

    $tools = Invoke-McpHttp '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}' $session
    $toolCount = ($tools.Content | ConvertFrom-Json).result.tools.Count
    Write-Host "tools/list: $toolCount tools" -ForegroundColor Green

    $ping = Invoke-McpHttp '{"jsonrpc":"2.0","id":3,"method":"ping"}' $session
    if ($ping.Status -ne 200) { throw "ping failed: $($ping.Status)" }
    Write-Host "ping: OK" -ForegroundColor Green
    Write-Host "`nHTTP MCP test passed." -ForegroundColor Green
} finally {
    if ($proc -and -not $proc.HasExited) { $proc.Kill() }
}
