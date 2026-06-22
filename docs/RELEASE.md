# GitHub Releases — Media-MCP-Server

Publishing pre-built **Windows x64** packages to GitHub Releases.

## Package variants

| Asset | Contents | Size (typ.) | Use case |
|-------|----------|-------------|----------|
| `media-mcp-server-X-win64-lite.zip` | `MediaMCPServer.exe`, `opencv_delphi_wrapper.dll`, install scripts | ~5–20 MB | **Default** — deps downloaded on first `install.ps1` |
| `media-mcp-server-X-win64-full.zip` | Lite + FFmpeg/OpenCV DLLs + ONNX models | ~300–800 MB | Offline install |

Lite package **does not** include FFmpeg/OpenCV DLLs or ONNX models. `install.ps1` runs `scripts\download_deps.ps1` (internet required).

## Maintainer workflow

### 1. Build and package

```powershell
cd MediaMCPServer
.\install.ps1          # dev machine: deps + compile
.\scripts\release.ps1 -Version "1.0.3"
```

Creates `dist\media-mcp-server-1.0.3-win64-lite.zip` (default).

Both lite and full:

```powershell
.\scripts\release.ps1 -Version "1.0.3" -Variant both
```

Skip rebuild if `bin\MediaMCPServer.exe` is already current:

```powershell
.\scripts\release.ps1 -Version "1.0.3" -SkipBuild
```

### 2. Publish to GitHub

Requires [GitHub CLI](https://cli.github.com/) (`gh auth login`):

```powershell
git tag -a v1.0.3 -m "Media MCP Server 1.0.3"
git push origin v1.0.3

.\scripts\release.ps1 -Version "1.0.3" -Publish
```

Draft release:

```powershell
.\scripts\release.ps1 -Version "1.0.3" -Publish -Draft
```

Custom release notes:

```powershell
.\scripts\release.ps1 -Version "1.0.3" -Publish -NotesFile .\release-notes.md
```

### 3. Manual upload (without `gh`)

1. `.\scripts\package.ps1 -Version "1.0.3"`
2. GitHub → **Releases** → **Draft a new release**
3. Tag: `v1.0.3`
4. Attach `dist\media-mcp-server-1.0.3-win64-lite.zip`
5. Publish

## End-user install (from Release)

```powershell
# Download lite ZIP from Releases, extract, then:
cd C:\Tools\media-mcp-server
.\install.ps1
```

`install.ps1`:

1. Downloads FFmpeg DLLs, OpenCV runtime, ONNX models
2. Verifies `bin\`
3. Writes MCP config (HTTP)
4. Starts HTTP server on port 8765

Options:

```powershell
.\install.ps1 -SkipDownload    # full ZIP, offline
.\install.ps1 -ForceDownload   # re-fetch all deps
.\install.ps1 -NoStartServer   # config only, no HTTP process
```

## Scripts reference

| Script | Purpose |
|--------|---------|
| `release.ps1` | Entry: build + package + optional `gh release create` |
| `scripts\release.ps1` | Same |
| `scripts\package.ps1` | `-Variant lite\|full\|both` |
| `scripts\verify_package.ps1` | Pre-package checks |
| `scripts\dist_install.ps1` | Becomes `install.ps1` inside ZIP |

## Checksums

```powershell
Get-FileHash dist\media-mcp-server-1.0.3-win64-lite.zip -Algorithm SHA256
```

`release.ps1` prints SHA256 before publish.

## Notes

- Do **not** commit `dist\*.zip` to git (see `.gitignore`).
- Tag and `-Version` should match (`1.0.3` ↔ tag `v1.0.3`).
- Delphi/RAD Studio is only needed on the **build machine**, not for end users.
