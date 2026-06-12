# Media-MCP-Server

MCP server (stdio + Streamable HTTP) for media processing via **OpenCV 5**, **FFmpeg**, and **ONVIF**.

## Quick start (development)

```powershell
cd MediaMCPServer
.\install.ps1
```

Then **Cursor → Settings → MCP → Refresh**.

## Quick start (production package)

Extract `dist\media-mcp-server-*.zip`, then:

```powershell
.\install.ps1
```

Open the extracted folder as a Cursor workspace and refresh MCP.

## Project layout

```
MediaMCPServer/
├── README.md
├── install.ps1              # entry point (dev)
├── build.ps1                # entry point (dev)
├── src/                     # Delphi source (.pas, .dpr)
├── scripts/
│   ├── install.ps1
│   ├── build.ps1
│   ├── package.ps1          # create production ZIP
│   ├── dist_install.ps1     # installer inside distribution
│   ├── setup_mcp.ps1
│   ├── verify_install.ps1
│   └── tests/
├── config/
│   └── mcp.json.template
├── docs/
│   ├── INSTALLATION.md      # setup for Cursor, Codex, Antigravity, …
│   ├── EXAMPLES.md          # complex use cases & agent workflows
│   ├── DISTRIBUTION.md
│   └── models-readme.txt
├── data/media/              # user captures, output, faces, video
├── bin/                     # runtime (exe, dll, models) — gitignored
└── dist/                    # production packages — gitignored
```

## Requirements (build machine)

| Component | Purpose |
|-----------|---------|
| Windows 10/11 x64 | Platform |
| RAD Studio / Delphi dcc64 | Build server |
| MSVC + CMake | Build `opencv_delphi_wrapper.dll` (if needed) |
| OpenCV 5.0 built | Native DLLs via `OpenCV_DIR` |
| Sibling repos (compile) | `OpenCV\OpenCV 5.0`, `Delphi-FFMPEG`, `Delphi-ONVIF` |
| Network | Direct download of models/DLLs via `scripts\download_deps.ps1` |

## Scripts

| Command | Description |
|---------|-------------|
| `.\install.ps1` | Full install (download deps + build + MCP config) |
| `.\build.ps1` | Build only |
| `.\scripts\download_deps.ps1` | Download models + FFmpeg + OpenCV runtime to `bin\` |
| `.\scripts\download_models.ps1` | ONNX models only |
| `.\scripts\download_ffmpeg_dll.ps1` | FFmpeg DLLs only |
| `.\scripts\download_opencv_runtime.ps1` | OpenCV DLLs + build `opencv_delphi_wrapper.dll` |
| `.\scripts\package.ps1` | Create production ZIP in `dist\` |
| `.\scripts\setup_mcp.ps1` | Regenerate `.cursor/mcp.json` |
| `.\scripts\verify_install.ps1` | Check installation |
| `.\scripts\tests\test_tools.ps1` | Smoke test via stdio |
| `.\scripts\tests\test_http_mcp.ps1` | Smoke test via Streamable HTTP |

### install.ps1 options

```powershell
.\install.ps1 -OpenCvDir "C:\opencv\build"
.\install.ps1 -Force -SkipDownload
.\install.ps1 -StrictVerify
```

## MCP clients

Supported environments: **Cursor**, **OpenAI Codex**, **Google Antigravity**, **Windsurf**, **Claude Desktop**, **VS Code**.

See **[docs/INSTALLATION.md](docs/INSTALLATION.md)** for step-by-step setup in each IDE/CLI.

**Complex workflow examples** (webinar recap; ONVIF/RTSP warehouse monitoring; USB webcam access control): **[docs/EXAMPLES.md](docs/EXAMPLES.md)**.

Quick config (Cursor / Antigravity / Windsurf / Claude):

### Streamable HTTP

```powershell
.\bin\MediaMCPServer.exe --http --port 8765
# or: .\bin\launch_http.cmd
```

Client config: `"url": "http://127.0.0.1:8765/mcp"` — see `config/mcp.http.json.template` and [docs/INSTALLATION.md](docs/INSTALLATION.md).

### stdio

```json
{
  "mcpServers": {
    "media-mcp-server": {
      "command": "D:\\...\\bin\\MediaMCPServer.exe",
      "args": [],
      "cwd": "D:\\...\\bin"
    }
  }
}
```

Codex uses `~/.codex/config.toml` — see `config/codex.config.toml.template`.


## Environment variables

| Variable | Purpose |
|----------|---------|
| `OpenCV_DIR` | CMake path to OpenCV build |
| `OPENCV_MODELS_PATH` / `MEDIA_MCP_MODELS_PATH` | ONNX models directory |
| `MEDIA_MCP_DATA_PATH` | Override `data\media\` |
| `MEDIA_MCP_DEBUG=1` | Log to stderr |
| `MEDIA_MCP_TRANSPORT=http` | Start in HTTP mode (same as `--http`) |
| `MEDIA_MCP_HTTP_HOST` | HTTP bind host (default `127.0.0.1`) |
| `MEDIA_MCP_HTTP_PORT` | HTTP port (default `8765`) |
| `MEDIA_MCP_HTTP_PATH` | HTTP path (default `/mcp`) |

## Tools (47)

**FFmpeg:** `video_probe`, `video_grab_frame`, `video_scene_detect`, `video_trim`, …  
**OpenCV:** `image_detect_objects`, `image_detect_faces`, `face_enroll`, `face_identify`, …  
**Camera:** `webcam_list`, `webcam_grab_frame`, `video_track_object`  
**ONVIF:** `camera_discover`, `onvif_get_stream_uri`, …

## Production release

On a **developer machine** with a full build:

```powershell
.\install.ps1
.\scripts\package.ps1
```

Creates `dist\media-mcp-server-YYYY.MM.DD-win64.zip`:

- `bin\` — exe, DLLs, ONNX models
- `data\media\` — empty user storage
- `config\` — MCP config template
- `install.ps1` — configures Cursor / Claude Desktop MCP
- `README.md`, `VERSION.txt`

On **target machine** (no Delphi):

```powershell
# extract ZIP, then:
.\install.ps1
```

See [docs/DISTRIBUTION.md](docs/DISTRIBUTION.md) for deployment details.

## Troubleshooting

| Issue | Fix |
|-------|-----|
| MCP JSON error | Run `.\scripts\setup_mcp.ps1` (paths must use `\\` in JSON) |
| Yellow MCP status | Wait or reload window; check tools count in MCP panel |
| Missing models | `.\scripts\download_models.ps1 -Force` |
| Missing FFmpeg | `.\scripts\download_ffmpeg_dll.ps1 -Force` |
| OpenCV load error | `.\scripts\download_opencv_runtime.ps1 -Force` |
| DLL load failed (package) | Extract full ZIP; do not copy only `.exe` |
