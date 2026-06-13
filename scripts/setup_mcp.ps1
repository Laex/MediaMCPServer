param(
    [string]$ServerName = 'media-mcp-server',
    [switch]$Stdio,
    [switch]$Wsl,
    [string]$HttpHost = '127.0.0.1',
    [int]$Port = 8765,
    [string]$Path = '/mcp',
    [switch]$StartServer,
    [switch]$NoStartServer
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot '_common.ps1')

if ($Wsl) {
    $wslArgs = @('-Port', $Port, '-Path', $Path, '-WriteSnippets')
    if ($StartServer) { $wslArgs += '-StartServer' }
    & (Join-Path $PSScriptRoot 'setup_wsl_http.ps1') @wslArgs
    exit $LASTEXITCODE
}

$ExePath = Join-Path $BinDir 'MediaMCPServer.exe'
$McpJson = Join-Path $CursorDir 'mcp.json'

if (-not (Test-Path $ExePath)) {
    throw "Executable not found. Run build.ps1 first: $ExePath"
}

New-Item -ItemType Directory -Force -Path $CursorDir | Out-Null

if ($Stdio) {
    $config = @{
        mcpServers = @{
            $ServerName = @{
                command = (Resolve-Path $ExePath).Path
                args = @('--stdio')
                cwd = (Resolve-Path $BinDir).Path
            }
        }
    }
} else {
    $endpoint = "http://${HttpHost}:${Port}$Path"
    $config = @{
        mcpServers = @{
            $ServerName = @{
                url = $endpoint
            }
        }
    }
}

$json = $config | ConvertTo-Json -Depth 5
Set-Content -Path $McpJson -Value $json -Encoding UTF8

Write-Host "MCP config written: $McpJson" -ForegroundColor Green
Write-Host $json

$shouldStart = $StartServer -or (-not $Stdio -and -not $NoStartServer)
if ($shouldStart -and -not $Stdio) {
    $endpoint = "http://${HttpHost}:${Port}$Path"
    Write-Host ""
    Write-Host "Streamable HTTP endpoint: $endpoint" -ForegroundColor Cyan
    $listener = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
    if ($listener) {
        Write-Host "HTTP server already listening on port $Port" -ForegroundColor Yellow
    } else {
        $proc = Start-Process -FilePath $ExePath `
            -ArgumentList @('--host', $HttpHost, '--port', $Port, '--path', $Path) `
            -WorkingDirectory $BinDir `
            -WindowStyle Hidden `
            -PassThru
        Start-Sleep -Seconds 2
        Write-Host "Started MediaMCPServer HTTP (PID $($proc.Id))" -ForegroundColor Green
    }
} elseif (-not $Stdio) {
    Write-Host ""
    Write-Host "Start server: cd bin; .\launch_http.cmd" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Settings -> MCP -> Refresh" -ForegroundColor Cyan
