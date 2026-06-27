$ErrorActionPreference = "Stop"
. (Join-Path (Split-Path $PSScriptRoot -Parent) '_common.ps1')

$exePath = Join-Path $BinDir 'MediaMCPServer.exe'
if (-not (Test-Path $exePath)) { Write-Error "Executable not found. Run build.ps1 first." }

function Assert-JsonLine([string]$Label, [string]$Line) {
    if ([string]::IsNullOrWhiteSpace($Line)) {
        throw "Empty stdout line for $Label"
    }
    try {
        $null = $Line | ConvertFrom-Json
    } catch {
        throw "stdout is not valid JSON for ${Label}: $Line"
    }
}

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $exePath
$psi.Arguments = '--stdio'
$psi.UseShellExecute = $false
$psi.RedirectStandardInput = $true
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.CreateNoWindow = $true

$proc = [System.Diagnostics.Process]::Start($psi)
try {
    $initReq = '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"stdio-json-test","version":"1"}}}'
    $proc.StandardInput.WriteLine($initReq)
    Assert-JsonLine 'initialize' ($proc.StandardOutput.ReadLine())

    $proc.StandardInput.WriteLine('{"jsonrpc":"2.0","method":"notifications/initialized"}')
    Start-Sleep -Milliseconds 150

    $listReq = '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}'
    $proc.StandardInput.WriteLine($listReq)
    Assert-JsonLine 'tools/list' ($proc.StandardOutput.ReadLine())
} finally {
    $proc.StandardInput.Close()
    if (-not $proc.WaitForExit(15000)) { $proc.Kill() }
    $proc.Close()
}

Write-Host "stdio stdout JSON-only test passed." -ForegroundColor Green
