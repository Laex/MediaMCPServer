# Media-MCP-Server

MCP server (Streamable HTTP + optional stdio) for media processing via **OpenCV 5**, **FFmpeg**, and **ONVIF**.

## Quick start (development)

```powershell
cd MediaMCPServer
.\install.ps1
```

Then refresh MCP in your client and ensure the HTTP server is running (see [docs/INSTALLATION.md](docs/INSTALLATION.md)).

## Quick start (production package)

Extract `dist\media-mcp-server-*.zip`, then:

```powershell
.\install.ps1
```

Open the extracted folder as a workspace in your MCP client and refresh the server list.

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
│   ├── INSTALLATION.md      # MCP client setup (all supported IDEs)
│   ├── WSL.md               # WSL client + Windows server (HTTP)
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
| `.\scripts\setup_mcp.ps1` | Regenerate project MCP config (HTTP, starts server) |
| `.\scripts\setup_mcp.ps1 -Stdio` | stdio MCP config instead of HTTP |
| `.\scripts\setup_mcp.ps1 -Wsl` | WSL HTTP setup (Windows side) |
| `.\scripts\setup_wsl_http.ps1` | Detect WSL networking, start HTTP, write snippets |
| `bash scripts/setup_wsl_mcp.sh` | Configure MCP in WSL (run inside WSL) |
| `.\scripts\verify_install.ps1` | Check installation |
| `.\scripts\tests\test_http_mcp.ps1` | Smoke test via Streamable HTTP (default) |
| `.\scripts\tests\test_tools.ps1` | Smoke test via stdio (`--stdio`) |
| `bash scripts/tests/test_http_mcp_wsl.sh` | HTTP smoke test from WSL |

### install.ps1 options

```powershell
.\install.ps1 -OpenCvDir "C:\opencv\build"
.\install.ps1 -Force -SkipDownload
.\install.ps1 -StrictVerify
```

## MCP clients

Supported MCP clients and per-IDE setup: **[docs/INSTALLATION.md](docs/INSTALLATION.md)**.

**Complex workflow examples** (webinar recap; ONVIF/RTSP warehouse monitoring; USB webcam access control): **[docs/EXAMPLES.md](docs/EXAMPLES.md)**.

Quick config (Streamable HTTP — default):

```powershell
.\bin\MediaMCPServer.exe
# or: .\bin\launch_http.cmd
```

Client config: `"url": "http://127.0.0.1:8765/mcp"` — see `config/mcp.json.template` and [docs/INSTALLATION.md](docs/INSTALLATION.md).

### stdio (optional)

Run the server with `--stdio` and use `command` + `cwd` in client config — see `config/mcp.stdio.json.template`.

**WSL:** client in WSL, server on Windows — [docs/WSL.md](docs/WSL.md).


## Environment variables

| Variable | Purpose |
|----------|---------|
| `OpenCV_DIR` | CMake path to OpenCV build |
| `OPENCV_MODELS_PATH` / `MEDIA_MCP_MODELS_PATH` | ONNX models directory |
| `MEDIA_MCP_DATA_PATH` | Override `data\media\` |
| `MEDIA_MCP_DEBUG=1` | Log to stderr |
| `MEDIA_MCP_TRANSPORT=stdio` | Force stdio mode (default is HTTP) |
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
- `install.ps1` — configures MCP clients
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
| MCP connection refused | Start HTTP server: `cd bin; .\launch_http.cmd` |
| MCP JSON error | Run `.\scripts\setup_mcp.ps1` |
| Yellow MCP status | Wait or reload window; check tools count in MCP panel |
| Missing models | `.\scripts\download_models.ps1 -Force` |
| Missing FFmpeg | `.\scripts\download_ffmpeg_dll.ps1 -Force` |
| OpenCV load error | `.\scripts\download_opencv_runtime.ps1 -Force` |
| DLL load failed (package) | Extract full ZIP; do not copy only `.exe` |
