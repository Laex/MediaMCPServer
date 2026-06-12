@echo off
cd /d "%~dp0"

rem Media MCP Server - Streamable HTTP launcher
rem Override any value via environment variables before running.

if not defined MEDIA_MCP_HTTP_HOST set "MEDIA_MCP_HTTP_HOST=127.0.0.1"
if not defined MEDIA_MCP_HTTP_PORT set "MEDIA_MCP_HTTP_PORT=8765"
if not defined MEDIA_MCP_HTTP_PATH set "MEDIA_MCP_HTTP_PATH=/mcp"

rem Suppress noisy OpenCV stderr (unused camera/DNN backends)
if not defined OPENCV_LOG_LEVEL set "OPENCV_LOG_LEVEL=ERROR"

rem User media storage (captures, output, faces, video)
if not defined MEDIA_MCP_DATA_PATH set "MEDIA_MCP_DATA_PATH=%~dp0..\data\media"

rem Optional: set MEDIA_MCP_DEBUG=1 for server-side MCP logs on stderr

echo [media-mcp] Streamable HTTP
echo [media-mcp] Endpoint : http://%MEDIA_MCP_HTTP_HOST%:%MEDIA_MCP_HTTP_PORT%%MEDIA_MCP_HTTP_PATH%
echo [media-mcp] Data     : %MEDIA_MCP_DATA_PATH%
echo [media-mcp] Press Ctrl+C to stop.

"%~dp0MediaMCPServer.exe" --http --host "%MEDIA_MCP_HTTP_HOST%" --port %MEDIA_MCP_HTTP_PORT% --path "%MEDIA_MCP_HTTP_PATH%" %*
