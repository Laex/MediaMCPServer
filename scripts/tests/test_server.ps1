$ErrorActionPreference = "Stop"
. (Join-Path (Split-Path $PSScriptRoot -Parent) '_common.ps1')

$exePath = Join-Path $BinDir 'MediaMCPServer.exe'
if (-not (Test-Path $exePath)) { Write-Error "Executable not found: $exePath" }

$proc = Start-Process -FilePath $exePath -ArgumentList '--stdio' -NoNewWindow -PassThru -RedirectStandardInput pipe -RedirectStandardOutput pipe
$proc.StandardInput.WriteLine('{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1"}}}')
$response = $proc.StandardOutput.ReadLine()
Write-Host "Response: $response"
$proc.StandardInput.Close()
$proc.WaitForExit(5000) | Out-Null
