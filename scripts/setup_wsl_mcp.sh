#!/usr/bin/env bash
# Configure MCP clients in WSL to use Media-MCP-Server over HTTP on Windows.
set -euo pipefail

SERVER_NAME="${MCP_SERVER_NAME:-media-mcp-server}"
PORT="${MCP_HTTP_PORT:-8765}"
PATH_SUFFIX="${MCP_HTTP_PATH:-/mcp}"
HOST=""
PROJECT_DIR=""
WRITE_GLOBAL=0
START_SERVER_HINT=1

usage() {
    cat <<'EOF'
Usage: setup_wsl_mcp.sh [options]

Configure Streamable HTTP MCP for WSL clients (server runs on Windows).

Options:
  --host HOST       Windows endpoint host (default: auto-detect)
  --port PORT       HTTP port (default: 8765)
  --path PATH       HTTP path (default: /mcp)
  --project DIR     Write .cursor/mcp.json into DIR (default: current directory)
  --global          Also print ~/.cursor/mcp.json instructions
  -h, --help        Show this help

Auto-detection order:
  1. http://127.0.0.1:PORT/PATH  (WSL mirrored networking)
  2. http://WINDOWS_HOST:PORT/PATH  (NAT WSL2 via /etc/resolv.conf)

Prerequisite on Windows:
  cd bin && ./launch_http.cmd          # mirrored networking
  cd bin && ./launch_http_wsl.cmd      # NAT WSL2 (bind 0.0.0.0)
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --host) HOST="$2"; shift 2 ;;
        --port) PORT="$2"; shift 2 ;;
        --path) PATH_SUFFIX="$2"; shift 2 ;;
        --project) PROJECT_DIR="$2"; shift 2 ;;
        --global) WRITE_GLOBAL=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
    esac
done

if [[ -z "$PATH_SUFFIX" ]]; then
    PATH_SUFFIX="/mcp"
fi
if [[ "$PATH_SUFFIX" != /* ]]; then
    PATH_SUFFIX="/$PATH_SUFFIX"
fi

get_windows_host_ip() {
    if [[ -f /etc/resolv.conf ]]; then
        awk '/^nameserver / { print $2; exit }' /etc/resolv.conf
    fi
}

test_endpoint() {
    local url="$1"
    curl -sfS -m 5 -X POST "$url" \
        -H 'Accept: application/json, text/event-stream' \
        -H 'Content-Type: application/json' \
        -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"wsl-setup","version":"1"}}}' \
        >/dev/null 2>&1
}

resolve_url() {
    local candidate host_ip

    if [[ -n "$HOST" ]]; then
        echo "http://${HOST}:${PORT}${PATH_SUFFIX}"
        return
    fi

    candidate="http://127.0.0.1:${PORT}${PATH_SUFFIX}"
    if test_endpoint "$candidate"; then
        echo "$candidate"
        return
    fi

    host_ip="$(get_windows_host_ip || true)"
    if [[ -n "$host_ip" ]]; then
        candidate="http://${host_ip}:${PORT}${PATH_SUFFIX}"
        if test_endpoint "$candidate"; then
            echo "$candidate"
            return
        fi
        echo "WARN: server not reachable; using ${candidate} (start HTTP on Windows first)" >&2
        echo "$candidate"
        return
    fi

    echo "WARN: using http://127.0.0.1:${PORT}${PATH_SUFFIX} (server not verified)" >&2
    echo "http://127.0.0.1:${PORT}${PATH_SUFFIX}"
}

write_mcp_json() {
    local target="$1"
    local url="$2"
    local dir

    dir="$(dirname "$target")"
    mkdir -p "$dir"
    cat >"$target" <<EOF
{
  "mcpServers": {
    "${SERVER_NAME}": {
      "url": "${url}"
    }
  }
}
EOF
    echo "Written: $target"
}

URL="$(resolve_url)"
echo "MCP endpoint: $URL"

if [[ -z "$PROJECT_DIR" ]]; then
    PROJECT_DIR="$(pwd)"
fi
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"
write_mcp_json "${PROJECT_DIR}/.cursor/mcp.json" "$URL"

if [[ $WRITE_GLOBAL -eq 1 ]]; then
    echo ""
    echo "For user-level Cursor config, merge into ~/.cursor/mcp.json:"
    cat <<EOF
{
  "mcpServers": {
    "${SERVER_NAME}": {
      "url": "${URL}"
    }
  }
}
EOF
fi

if [[ $START_SERVER_HINT -eq 1 ]]; then
    echo ""
    echo "If MCP fails to connect, start the server on Windows:"
    echo "  PowerShell: cd bin; .\\launch_http.cmd       # WSL mirrored"
    echo "  PowerShell: cd bin; .\\launch_http_wsl.cmd    # NAT WSL2"
    echo "  Or: .\\scripts\\setup_wsl_http.ps1 -StartServer"
fi

echo ""
echo "In Cursor (WSL): Settings -> MCP -> Refresh. Expect 47 tools."
