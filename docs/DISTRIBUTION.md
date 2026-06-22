# Media-MCP-Server — Production Distribution

Pre-built Windows x64 package. **No Delphi, CMake, or compiler required** on the target machine.

GitHub Releases ship a **lite** ZIP by default (small download; runtime deps fetched by `install.ps1`). An optional **full** offline ZIP includes all DLLs and models.

See **[RELEASE.md](RELEASE.md)** for maintainer publishing workflow.

## Package contents (lite — GitHub default)

```
media-mcp-server-X-win64-lite/
├── bin/                  MediaMCPServer.exe, opencv_delphi_wrapper.dll, launch_http*.cmd
├── scripts/              download_deps.ps1, download_models.ps1, …
├── data/media/           User storage (empty)
├── config/               MCP templates + deps_urls.json
├── docs/                 INSTALLATION.md, WSL.md, EXAMPLES.md, RELEASE.md
├── install.ps1           Download deps + configure MCP + start HTTP
├── README.md
└── VERSION.txt
```

## Package contents (full — offline)

Same as lite, plus in `bin\`: FFmpeg DLLs, OpenCV DLLs, ONNX models.

## Deploy to production

1. Download `media-mcp-server-*-lite.zip` from **GitHub Releases** (or copy full ZIP).
2. Extract to a permanent path, e.g. `C:\Tools\media-mcp-server\`
3. Open PowerShell in that folder:

```powershell
.\install.ps1
```

**Lite:** downloads FFmpeg, OpenCV, and ONNX models (internet required).  
**Full:** use `.\install.ps1 -SkipDownload` to skip download.

4. Configure your MCP client — see **docs/INSTALLATION.md**

## install.ps1 options

```powershell
.\install.ps1                    # download deps (lite) + HTTP config + start server
.\install.ps1 -SkipDownload      # skip download (full offline package)
.\install.ps1 -ForceDownload     # re-download all runtime deps
.\install.ps1 -NoStartServer     # do not start HTTP process
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
.\scripts\package.ps1 -Version "1.0.3"              # lite (default)
.\scripts\package.ps1 -Version "1.0.3" -Variant full
.\scripts\release.ps1 -Version "1.0.3" -Publish      # GitHub Release
```

Output in `dist\`:

- `media-mcp-server-X-win64-lite.zip` — for GitHub Releases
- `media-mcp-server-X-win64-full.zip` — optional offline bundle

Verify before packaging:

```powershell
.\scripts\verify_package.ps1 -Lite -Strict    # lite
.\scripts\verify_install.ps1 -Strict          # full
```

Publishing: **[RELEASE.md](RELEASE.md)**

## Troubleshooting

| Issue | Fix |
|-------|-----|
| MCP server errored | Run `.\install.ps1`; check `url` in MCP config; start HTTP: `cd bin; .\launch_http.cmd` |
| Yellow MCP status | Reload IDE window (Cursor: Reload Window); confirm 47 tools are listed |
| DLL load failed | Extract full ZIP; `cwd` must point to `bin\` |
| Models not found | Run `.\install.ps1` (lite) or use full ZIP |
| JSON syntax error | Paths must use `\\` not `\` |
