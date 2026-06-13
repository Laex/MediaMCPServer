# Media-MCP-Server — Production Distribution

Pre-built Windows x64 package. **No Delphi, CMake, or compiler required** on the target machine.

## Package contents

```
media-mcp-server-YYYY.MM.DD-win64/
├── bin/                  MediaMCPServer.exe, DLLs, ONNX models
├── data/media/           User captures, output, faces, video
├── config/               MCP config templates (all clients)
├── docs/INSTALLATION.md  Setup guide (Cursor, Codex, Antigravity, …)
├── docs/WSL.md           WSL client setup (HTTP to Windows server)
├── docs/EXAMPLES.md      Complex use cases (webinar recap, OCR, montage)
├── install.ps1           Configure MCP clients
├── README.md             This file
└── VERSION.txt
```

## Deploy to production

1. Copy `media-mcp-server-*.zip` to the target PC.
2. Extract to a permanent path, e.g. `C:\Tools\media-mcp-server\`
3. Open PowerShell in that folder:

```powershell
.\install.ps1
```

4. Configure your MCP client — see **docs/INSTALLATION.md**

## install.ps1 options

```powershell
.\install.ps1                    # HTTP config + start server (default)
.\install.ps1 -Mode cursor       # .cursor/mcp.json (HTTP)
.\install.ps1 -Mode stdio        # stdio config instead of HTTP
.\install.ps1 -Mode codex        # .codex/config.toml
.\install.ps1 -Mode antigravity  # snippet for Antigravity
.\install.ps1 -Mode windsurf     # snippet for Windsurf
.\install.ps1 -Mode claude       # Claude Desktop
.\install.ps1 -Mode snippets     # all snippets in config\
.\install.ps1 -Mode wsl          # HTTP config for WSL clients
.\install.ps1 -Mode print        # print JSON + TOML to console
.\install.ps1 -TargetDir "D:\Apps\media-mcp-server"
```

Full per-client instructions: [INSTALLATION.md](INSTALLATION.md)  
WSL (client in Linux, server on Windows): [WSL.md](WSL.md)

## MCP configuration

`install.ps1` generates HTTP config by default:

```json
{
  "mcpServers": {
    "media-mcp-server": {
      "url": "http://127.0.0.1:8765/mcp"
    }
  }
}
```

- `url` — Streamable HTTP endpoint (server must be running: `cd bin; .\launch_http.cmd`)
- **stdio (optional):** `.\install.ps1 -Mode stdio` — uses `command`, `args: ["--stdio"]`, `cwd`
- Use **double backslashes** in JSON paths (stdio mode)

Templates: `config\mcp.json.template` (HTTP), `config\mcp.stdio.json.template`

## Requirements (target machine)

- Windows 10/11 x64
- Webcam (optional, for camera tools)
- Network (optional, for ONVIF / RTSP)

Visual C++ Redistributable may be required if not already installed (`vcruntime*.dll` are bundled when present in the build).

## Environment variables

| Variable | Purpose |
|----------|---------|
| `MEDIA_MCP_DATA_PATH` | Override `data\media\` location |
| `OPENCV_MODELS_PATH` | Override `bin\models\` |
| `MEDIA_MCP_DEBUG=1` | Enable stderr logging |

## Building the package (developer machine)

On a machine **with** RAD Studio and built dependencies:

```powershell
cd MediaMCPServer
.\install.ps1
.\scripts\package.ps1
```

Optional version tag:

```powershell
.\scripts\package.ps1 -Version "1.0.0"
```

Output:

- `dist\media-mcp-server-YYYY.MM.DD-win64\` — unpacked folder
- `dist\media-mcp-server-YYYY.MM.DD-win64.zip` — deployable archive

Verify before packaging:

```powershell
.\scripts\verify_install.ps1 -Strict
```

## Troubleshooting

| Issue | Fix |
|-------|-----|
| MCP server errored | Run `.\install.ps1`; check `url` in MCP config; start HTTP: `cd bin; .\launch_http.cmd` |
| Yellow MCP status | Reload IDE window (Cursor: Reload Window); confirm 47 tools are listed |
| DLL load failed | Extract full ZIP; `cwd` must point to `bin\` |
| Models not found | Ensure `bin\models\` exists inside package |
| JSON syntax error | Paths must use `\\` not `\` |
