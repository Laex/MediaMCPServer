#!/usr/bin/env bash
# Smoke test for Streamable HTTP MCP from WSL (server must run on Windows).
set -euo pipefail

PORT="${MCP_HTTP_PORT:-8765}"
PATH_SUFFIX="${MCP_HTTP_PATH:-/mcp}"
HOST="${MCP_HTTP_HOST:-}"

get_windows_host_ip() {
    if [[ -f /etc/resolv.conf ]]; then
        awk '/^nameserver / { print $2; exit }' /etc/resolv.conf
    fi
}

resolve_base_url() {
    local host_ip candidate

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
        echo "ERROR: MCP server not reachable at 127.0.0.1 or ${host_ip}:${PORT}" >&2
        echo "Start on Windows: cd bin && .\\launch_http_wsl.cmd" >&2
        exit 1
    fi

    echo "ERROR: MCP server not reachable at 127.0.0.1:${PORT}" >&2
    exit 1
}

mcp_post() {
    local url="$1"
    local body="$2"
    local session="${3:-}"
    local headers=(-H 'Accept: application/json, text/event-stream' -H 'Content-Type: application/json')
    if [[ -n "$session" ]]; then
        headers+=(-H "Mcp-Session-Id: ${session}")
    fi
    curl -sfS -m 15 -D - -o /tmp/mcp_wsl_body.txt -X POST "$url" "${headers[@]}" -d "$body"
}

BASE_URL="$(resolve_base_url)"
echo "HTTP MCP test (WSL): $BASE_URL"

INIT_BODY='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"wsl-http-test","version":"1"}}}'
RESP_HEADERS="$(mcp_post "$BASE_URL" "$INIT_BODY")"
SESSION="$(echo "$RESP_HEADERS" | awk 'BEGIN{IGNORECASE=1} /^[Mm]cp-[Ss]ession-[Ii]d:/ {sub(/^[^:]*:[ \t]*/, ""); gsub(/\r/, ""); print; exit}')"
if [[ -z "$SESSION" ]]; then
    echo "ERROR: initialize succeeded but Mcp-Session-Id header missing" >&2
    echo "$RESP_HEADERS" >&2
    exit 1
fi
echo "Session: $SESSION"

mcp_post "$BASE_URL" '{"jsonrpc":"2.0","method":"notifications/initialized"}' "$SESSION" >/dev/null

TOOLS_RESP="$(mcp_post "$BASE_URL" '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}' "$SESSION")"
TOOL_COUNT="$(python3 -c "import json; print(len(json.load(open('/tmp/mcp_wsl_body.txt'))['result']['tools']))" 2>/dev/null || echo "?")"
echo "tools/list: ${TOOL_COUNT} tools"

mcp_post "$BASE_URL" '{"jsonrpc":"2.0","id":3,"method":"ping"}' "$SESSION" >/dev/null
echo "ping: OK"
echo ""
echo "HTTP MCP test passed (WSL)."
