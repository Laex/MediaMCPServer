# Install pre-built Media MCP Server package (no compilation)
param(
    [string]$TargetDir = "",
    [ValidateSet('cursor', 'claude', 'codex', 'antigravity', 'windsurf', 'wsl', 'stdio', 'snippets', 'print', 'all')]
    [string]$Mode = 'all',
    [string]$ServerName = 'media-mcp-server',
    [switch]$StartServer,
    [switch]$NoStartServer,
    [switch]$SkipDownload,
    [switch]$ForceDownload
)

$ErrorActionPreference = "Stop"

# Package root = directory containing this install.ps1
$PkgRoot = if ($TargetDir) { (Resolve-Path $TargetDir).Path } else { $PSScriptRoot }
$BinDir = Join-Path $PkgRoot 'bin'
$ExePath = Join-Path $BinDir 'MediaMCPServer.exe'
$MediaDir = Join-Path $PkgRoot 'data\media'
$ConfigDir = Join-Path $PkgRoot 'config'
$HttpUrl = 'http://127.0.0.1:8765/mcp'

function Test-Package {
    $missing = @()
    foreach ($f in @('MediaMCPServer.exe', 'opencv_delphi_wrapper.dll')) {
        if (-not (Test-Path (Join-Path $BinDir $f))) { $missing += $f }
    }
    if ($missing.Count -gt 0) {
        throw "Invalid package - missing in bin\: $($missing -join ', ')"
    }
}

function New-McpStdioJson([string]$Exe, [string]$Cwd) {
    @{
        mcpServers = @{
            $ServerName = @{
                command = $Exe
                args = @('--stdio')
                cwd = $Cwd
            }
        }
    } | ConvertTo-Json -Depth 5
}

function New-McpHttpJson([string]$Url) {
    @{
        mcpServers = @{
            $ServerName = @{
                url = $Url
            }
        }
    } | ConvertTo-Json -Depth 5
}

function New-AntigravityHttpJson([string]$Url) {
    @{
        mcpServers = @{
            $ServerName = @{
                serverUrl = $Url
            }
        }
    } | ConvertTo-Json -Depth 5
}

function New-CodexHttpToml([string]$Url) {
    @"
# Media MCP Server - Streamable HTTP (default)
[mcp_servers.$ServerName]
url = "$Url"
enabled = true
startup_timeout_sec = 30
tool_timeout_sec = 120
"@
}

function New-CodexStdioToml([string]$Exe, [string]$Cwd) {
    $exePath = $Exe -replace '\\', '/'
    $cwdPath = $Cwd -replace '\\', '/'
    @"
# Media MCP Server - stdio transport (optional)
[mcp_servers.$ServerName]
command = "$exePath"
args = ["--stdio"]
cwd = "$cwdPath"
enabled = true
startup_timeout_sec = 30
tool_timeout_sec = 120
"@
}

function Write-ConfigFile([string]$Path, [string]$Content) {
    $dir = Split-Path $Path -Parent
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    Set-Content -Path $Path -Value $Content -Encoding UTF8
    Write-Host "  Written: $Path" -ForegroundColor Green
}

function Write-Snippets([string]$Exe, [string]$Cwd, [string]$Url, [switch]$StdioOnly) {
    New-Item -ItemType Directory -Force -Path $ConfigDir | Out-Null
    if (-not $StdioOnly) {
        $httpJson = New-McpHttpJson $Url
        Write-ConfigFile (Join-Path $ConfigDir 'mcp.json.snippet') $httpJson
        Write-ConfigFile (Join-Path $ConfigDir 'claude_desktop_config.snippet.json') $httpJson
        Write-ConfigFile (Join-Path $ConfigDir 'windsurf.mcp_config.snippet.json') $httpJson
        Write-ConfigFile (Join-Path $ConfigDir 'antigravity.mcp_config.snippet.json') (New-AntigravityHttpJson $Url)
        Write-ConfigFile (Join-Path $ConfigDir 'codex.config.snippet.toml') (New-CodexHttpToml $Url)
    }
    $stdioJson = New-McpStdioJson $Exe $Cwd
    Write-ConfigFile (Join-Path $ConfigDir 'mcp.stdio.json.snippet') $stdioJson
    Write-ConfigFile (Join-Path $ConfigDir 'codex.stdio.config.snippet.toml') (New-CodexStdioToml $Exe $Cwd)
    Write-Host "  Merge snippets into your client config (see docs\INSTALLATION.md)" -ForegroundColor Gray
}

function Start-HttpServerIfNeeded {
    if ($NoStartServer) { return }
    if (-not ($StartServer -or $Mode -in @('all', 'cursor', 'codex', 'wsl'))) { return }
    $listener = Get-NetTCPConnection -LocalPort 8765 -State Listen -ErrorAction SilentlyContinue
    if ($listener) {
        Write-Host "HTTP server already listening on port 8765" -ForegroundColor Yellow
        return
    }
    $proc = Start-Process -FilePath $ExePath `
        -ArgumentList @('--host', '127.0.0.1', '--port', '8765', '--path', '/mcp') `
        -WorkingDirectory $BinDir `
        -WindowStyle Hidden `
        -PassThru
    Start-Sleep -Seconds 2
    Write-Host "Started MediaMCPServer HTTP (PID $($proc.Id))" -ForegroundColor Green
}

function Install-RuntimeDependencies {
    if ($SkipDownload) {
        Write-Host "Skipping dependency download (-SkipDownload)" -ForegroundColor Yellow
        return
    }

    $downloadScript = Join-Path $PkgRoot 'scripts\download_deps.ps1'
    if (-not (Test-Path $downloadScript)) {
        Write-Host "No scripts\download_deps.ps1 — assuming full offline package" -ForegroundColor DarkGray
        return
    }

    Write-Host ""
    Write-Host "Downloading runtime dependencies (FFmpeg, OpenCV, ONNX models)..." -ForegroundColor Cyan
    Write-Host "Internet connection required on first install." -ForegroundColor DarkGray

    $dlArgs = @()
    if ($ForceDownload) { $dlArgs += '-Force' }
    & $downloadScript @dlArgs
    if ($LASTEXITCODE -ne 0) { throw "download_deps.ps1 failed with exit code $LASTEXITCODE" }

    $verifyScript = Join-Path $PkgRoot 'scripts\verify_install.ps1'
    if (Test-Path $verifyScript) {
        Write-Host ""
        Write-Host "Verifying downloaded runtime..." -ForegroundColor Cyan
        & $verifyScript -Strict
        if ($LASTEXITCODE -ne 0) { throw 'Runtime verification failed after download.' }
    }
}

Write-Host "=== Media MCP Server - Package Install ===" -ForegroundColor Cyan
Write-Host "Package: $PkgRoot"

Test-Package

foreach ($sub in @('captures', 'output', 'faces', 'video')) {
    New-Item -ItemType Directory -Force -Path (Join-Path $MediaDir $sub) | Out-Null
}

Install-RuntimeDependencies

$exePath = (Resolve-Path $ExePath).Path
$binPath = (Resolve-Path $BinDir).Path
$useStdio = $Mode -eq 'stdio'
$mcpJson = if ($useStdio) { New-McpStdioJson $exePath $binPath } else { New-McpHttpJson $HttpUrl }
$codexToml = if ($useStdio) { New-CodexStdioToml $exePath $binPath } else { New-CodexHttpToml $HttpUrl }

Write-Host ""
Write-Host "MCP executable: $exePath" -ForegroundColor Gray
Write-Host "Transport:      $(if ($useStdio) { 'stdio' } else { "HTTP $HttpUrl" })" -ForegroundColor Gray

if ($Mode -eq 'wsl' -or ($Mode -eq 'all' -and -not $useStdio)) {
    if ($Mode -eq 'wsl') {
        Write-Host ""
        Write-Host "WSL / HTTP (Streamable HTTP for Linux-side MCP clients):" -ForegroundColor Cyan
    }
    $httpJson = New-McpHttpJson $HttpUrl
    New-Item -ItemType Directory -Force -Path $ConfigDir | Out-Null
    Write-ConfigFile (Join-Path $ConfigDir 'mcp.wsl.http.json.snippet') $httpJson
    Write-ConfigFile (Join-Path $ConfigDir 'codex.http.wsl.config.snippet.toml') (New-CodexHttpToml $HttpUrl)
    if ($Mode -eq 'wsl') {
        $cursorPath = Join-Path $PkgRoot '.cursor\mcp.json'
        Write-ConfigFile $cursorPath $httpJson
        Write-Host "  NAT WSL2: cd bin; .\launch_http_wsl.cmd" -ForegroundColor Gray
        Write-Host "  Configure in WSL: bash scripts/setup_wsl_mcp.sh" -ForegroundColor Gray
        Write-Host "  See docs\WSL.md" -ForegroundColor Gray
    }
}

if ($Mode -eq 'cursor' -or $Mode -eq 'all' -or $Mode -eq 'stdio') {
    Write-Host ""
    Write-Host "Cursor (project-level):" -ForegroundColor Cyan
    $cursorPath = Join-Path $PkgRoot '.cursor\mcp.json'
    Write-ConfigFile $cursorPath $mcpJson
    if (-not $useStdio) {
        Write-Host "  Start HTTP: cd bin; .\launch_http.cmd" -ForegroundColor Gray
    }
    Write-Host "  Open this folder in Cursor, then Settings -> MCP -> Refresh"
}

if ($Mode -eq 'codex' -or $Mode -eq 'all' -or $Mode -eq 'stdio') {
    Write-Host ""
    Write-Host "OpenAI Codex (project-level):" -ForegroundColor Cyan
    $codexPath = Join-Path $PkgRoot '.codex\config.toml'
    Write-ConfigFile $codexPath $codexToml
    Write-Host "  Trust this project in Codex, then run /mcp in a session"
}

if ($Mode -eq 'antigravity' -or $Mode -eq 'snippets' -or $Mode -eq 'all') {
    if ($Mode -eq 'antigravity') {
        Write-Host ""
        Write-Host "Google Antigravity:" -ForegroundColor Cyan
        Write-Host "  Config file: $env:USERPROFILE\.gemini\antigravity\mcp_config.json" -ForegroundColor Gray
        Write-Host "  Agent panel -> Manage MCP Servers -> View raw config" -ForegroundColor Gray
        Write-Host "  Add the media-mcp-server block from:" -ForegroundColor Gray
        $snippet = Join-Path $ConfigDir 'antigravity.mcp_config.snippet.json'
        Write-Snippets $exePath $binPath $HttpUrl | Out-Null
        Write-Host "  $snippet" -ForegroundColor Green
    }
}

if ($Mode -eq 'windsurf' -or $Mode -eq 'snippets' -or $Mode -eq 'all') {
    if ($Mode -eq 'windsurf') {
        Write-Host ""
        Write-Host "Windsurf:" -ForegroundColor Cyan
        Write-Host "  Config file: $env:USERPROFILE\.codeium\windsurf\mcp_config.json" -ForegroundColor Gray
        Write-Host "  Cascade MCP hammer icon -> Configure" -ForegroundColor Gray
        $snippet = Join-Path $ConfigDir 'windsurf.mcp_config.snippet.json'
        Write-Snippets $exePath $binPath $HttpUrl | Out-Null
        Write-Host "  Add block from: $snippet" -ForegroundColor Green
    }
}

if ($Mode -eq 'claude' -or $Mode -eq 'all' -or $Mode -eq 'stdio') {
    Write-Host ""
    Write-Host "Claude Desktop:" -ForegroundColor Cyan
    $claudeDir = Join-Path $env:APPDATA 'Claude'
    $claudeCfg = Join-Path $claudeDir 'claude_desktop_config.json'
    if (Test-Path $claudeDir) {
        if (Test-Path $claudeCfg) {
            Write-Host "  Found existing config: $claudeCfg" -ForegroundColor Yellow
            Write-Host "  Merge manually - add media-mcp-server block" -ForegroundColor Yellow
            $example = Join-Path $ConfigDir 'claude_desktop_config.snippet.json'
            New-Item -ItemType Directory -Force -Path $ConfigDir | Out-Null
            Write-ConfigFile $example $mcpJson
        } else {
            Write-ConfigFile $claudeCfg $mcpJson
        }
    } else {
        Write-Host "  Claude Desktop not found at $claudeDir" -ForegroundColor Yellow
        $example = Join-Path $ConfigDir 'claude_desktop_config.snippet.json'
        New-Item -ItemType Directory -Force -Path $ConfigDir | Out-Null
        Write-ConfigFile $example $mcpJson
    }
}

if ($Mode -eq 'snippets' -or $Mode -eq 'all') {
    Write-Host ""
    Write-Host "Config snippets (all clients):" -ForegroundColor Cyan
    Write-Snippets $exePath $binPath $HttpUrl
}

if ($Mode -eq 'print') {
    Write-Host ""
    Write-Host "JSON (HTTP, default):" -ForegroundColor Cyan
    Write-Host (New-McpHttpJson $HttpUrl)
    Write-Host ""
    Write-Host "TOML (HTTP, default):" -ForegroundColor Cyan
    Write-Host (New-CodexHttpToml $HttpUrl)
    Write-Host ""
    Write-Host "Start server:" -ForegroundColor Cyan
    Write-Host "  cd `"$BinDir`""
    Write-Host "  .\MediaMCPServer.exe"
    Write-Host "  # or: .\launch_http.cmd"
}

if (-not $useStdio) {
    Start-HttpServerIfNeeded
}

Write-Host ""
Write-Host "Environment (optional):" -ForegroundColor Cyan
Write-Host "  MEDIA_MCP_DATA_PATH = custom data folder"
Write-Host "  OPENCV_MODELS_PATH  = custom models folder"
Write-Host "  MEDIA_MCP_TRANSPORT = stdio   # force stdio instead of HTTP"
Write-Host ""
Write-Host "Re-download deps: .\install.ps1 -ForceDownload"
Write-Host "Skip download:    .\install.ps1 -SkipDownload   # full offline package"
Write-Host ""
Write-Host "See docs\INSTALLATION.md for per-client setup details." -ForegroundColor Cyan
Write-Host "Install complete." -ForegroundColor Green
