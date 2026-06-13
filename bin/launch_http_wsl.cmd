@echo off
cd /d "%~dp0"

rem Media MCP Server - HTTP launcher for WSL clients (NAT WSL2)
rem Binds 0.0.0.0 so WSL can reach the server via the Windows host IP.
rem For WSL mirrored networking (Win11+), launch_http.cmd on 127.0.0.1 is enough.

if not defined MEDIA_MCP_HTTP_HOST set "MEDIA_MCP_HTTP_HOST=0.0.0.0"
if not defined MEDIA_MCP_HTTP_PORT set "MEDIA_MCP_HTTP_PORT=8765"
if not defined MEDIA_MCP_HTTP_PATH set "MEDIA_MCP_HTTP_PATH=/mcp"

if not defined OPENCV_LOG_LEVEL set "OPENCV_LOG_LEVEL=ERROR"
if not defined MEDIA_MCP_DATA_PATH set "MEDIA_MCP_DATA_PATH=%~dp0..\data\media"

echo [media-mcp] Streamable HTTP (WSL / LAN bind)
echo [media-mcp] Endpoint : http://%MEDIA_MCP_HTTP_HOST%:%MEDIA_MCP_HTTP_PORT%%MEDIA_MCP_HTTP_PATH%
echo [media-mcp] Data     : %MEDIA_MCP_DATA_PATH%
echo [media-mcp] WSL URL  : run scripts\setup_wsl_http.ps1 for client config hints
echo [media-mcp] Press Ctrl+C to stop.

"%~dp0MediaMCPServer.exe" --host "%MEDIA_MCP_HTTP_HOST%" --port %MEDIA_MCP_HTTP_PORT% --path "%MEDIA_MCP_HTTP_PATH%" %*
