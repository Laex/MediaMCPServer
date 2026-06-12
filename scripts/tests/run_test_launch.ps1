. (Join-Path (Split-Path $PSScriptRoot -Parent) '_common.ps1')
$p = Start-Process -FilePath (Join-Path $BinDir 'MediaMCPServer.exe') -NoNewWindow -PassThru -ErrorAction SilentlyContinue
Write-Host "Started PID: $($p.Id)"
