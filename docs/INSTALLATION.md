# Установка Media-MCP-Server в различные среды

Руководство по подключению MCP-сервера к IDE и CLI-агентам. Сервер работает только на **Windows 10/11 x64**.

Поддерживаемые транспорты MCP:

| Транспорт | Режим | Когда использовать |
|-----------|-------|-------------------|
| **Streamable HTTP** (по умолчанию) | Отдельный HTTP-процесс | Cursor, Codex, Antigravity, WSL, удалённый доступ |
| **stdio** (опционально) | Клиент запускает `MediaMCPServer.exe --stdio` | Локальная отладка, клиенты без HTTP |

## Перед началом

1. После установки запустите HTTP-сервер (если `install.ps1` не запустил его автоматически):

```powershell
cd bin
.\launch_http.cmd
```

2. Обновите список MCP-серверов в клиенте. Ожидайте **47 tools**.

### Вариант A — готовый пакет (продакшен)

1. Распакуйте `media-mcp-server-*.zip` в постоянную папку, например `C:\Tools\media-mcp-server\`
2. Запустите установщик:

```powershell
cd C:\Tools\media-mcp-server
.\install.ps1
```

Скрипт создаёт `.cursor\mcp.json` с HTTP `url`, запускает сервер и пишет сниппеты в `config\`.

Точечная установка:

```powershell
.\install.ps1 -Mode cursor
.\install.ps1 -Mode codex
.\install.ps1 -Mode antigravity
.\install.ps1 -Mode windsurf
.\install.ps1 -Mode claude
.\install.ps1 -Mode wsl
.\install.ps1 -Mode stdio      # stdio вместо HTTP
.\install.ps1 -Mode snippets   # все сниппеты в config\
```

### Вариант B — сборка из исходников (разработка)

```powershell
cd MediaMCPServer
.\install.ps1
.\scripts\setup_mcp.ps1   # только Cursor
```

### Общие правила конфигурации (HTTP — по умолчанию)

| Параметр | Значение |
|----------|----------|
| `url` | `http://127.0.0.1:8765/mcp` |

Для **stdio** (опционально):

| Параметр | Значение |
|----------|----------|
| `command` | Абсолютный путь к `bin\MediaMCPServer.exe` |
| `args` | `["--stdio"]` |
| `cwd` | Абсолютный путь к `bin\` (для загрузки DLL и моделей) |

Замените `C:\Tools\media-mcp-server` на свой путь установки. В JSON используйте двойные обратные слэши (`\\`).

Опциональные переменные окружения (`env`):

| Переменная | Назначение |
|------------|------------|
| `MEDIA_MCP_DATA_PATH` | Каталог пользовательских данных (по умолчанию `data\media\`) |
| `MEDIA_MCP_MODELS_PATH` | Каталог ONNX-моделей (по умолчанию `bin\models\`) |
| `MEDIA_MCP_DEBUG=1` | Логирование в stderr |

После изменения конфига перезапустите клиент или обновите список MCP-серверов. Ожидайте **47 tools**.

---

## Streamable HTTP

HTTP-сервер слушает один endpoint (по умолчанию `http://127.0.0.1:8765/mcp`), управляет сессиями через заголовок `Mcp-Session-Id`.

### Запуск

```powershell
cd bin
.\MediaMCPServer.exe
# или
.\launch_http.cmd
```

По умолчанию `MediaMCPServer.exe` запускается в HTTP-режиме. Для stdio: `.\MediaMCPServer.exe --stdio`.

Параметры и переменные окружения:

| Параметр / переменная | По умолчанию | Описание |
|-----------------------|--------------|----------|
| *(без флагов)* | HTTP | Streamable HTTP (режим по умолчанию) |
| `--stdio` / `MEDIA_MCP_TRANSPORT=stdio` | — | Включить stdio вместо HTTP |
| `--http` | — | Устаревший алиас; HTTP и так по умолчанию |
| `--host` / `MEDIA_MCP_HTTP_HOST` | `127.0.0.1` | Адрес привязки |
| `--port` / `MEDIA_MCP_HTTP_PORT` | `8765` | Порт |
| `--path` / `MEDIA_MCP_HTTP_PATH` | `/mcp` | URL-путь endpoint |

> По умолчанию сервер слушает только **localhost**. Не меняйте host на `0.0.0.0` без аутентификации и firewall.

### Конфигурация клиентов (HTTP)

**Cursor / Windsurf / Claude** (`url`):

```json
{
  "mcpServers": {
    "media-mcp-server": {
      "url": "http://127.0.0.1:8765/mcp"
    }
  }
}
```

**OpenAI Codex** (TOML):

```toml
[mcp_servers.media-mcp-server]
url = "http://127.0.0.1:8765/mcp"
enabled = true
```

**Google Antigravity** (`serverUrl`, не `url`):

```json
{
  "mcpServers": {
    "media-mcp-server": {
      "serverUrl": "http://127.0.0.1:8765/mcp"
    }
  }
}
```

Шаблоны: `config\mcp.http.json.template`, `config\codex.http.config.toml.template`, `config\antigravity.http.mcp_config.template.json`

### Проверка HTTP

```powershell
.\scripts\tests\test_http_mcp.ps1
```

---

## WSL (Windows Subsystem for Linux)

Если **Cursor / Codex открыт в WSL**, а сервер остаётся на Windows, используйте **Streamable HTTP** — stdio с `MediaMCPServer.exe` из WSL Remote не работает.

**Полное руководство:** [WSL.md](WSL.md)

### Кратко

1. **Windows** — запустите HTTP-сервер:

```powershell
cd bin
.\launch_http.cmd          # WSL mirrored (Win11+)
# или
.\launch_http_wsl.cmd      # NAT WSL2 (bind 0.0.0.0)
```

2. **WSL** — настройте MCP-клиент:

```bash
bash scripts/setup_wsl_mcp.sh
bash scripts/tests/test_http_mcp_wsl.sh
```

3. **Cursor** → Settings → MCP → Refresh (ожидайте 47 tools). Другие клиенты — см. разделы ниже в этом файле.

| Режим WSL | URL в `mcp.json` | Сервер на Windows |
|-----------|------------------|-------------------|
| Mirrored | `http://127.0.0.1:8765/mcp` | `launch_http.cmd` |
| NAT | `http://<windows-host-ip>:8765/mcp` | `launch_http_wsl.cmd` |

IP Windows-хоста в NAT: `grep nameserver /etc/resolv.conf | awk '{print $2}'`

Шаблоны: `config\mcp.wsl.http.json.template`, `config\codex.http.wsl.config.toml.template`

Установка сниппетов (пакет): `.\install.ps1 -Mode wsl`

Разработка: `.\scripts\setup_mcp.ps1` (HTTP + автозапуск сервера) или `.\scripts\setup_mcp.ps1 -Stdio`

---

## Cursor

**Файл:** `.cursor\mcp.json` в корне workspace (проектный уровень)

**Автоустановка:** `.\install.ps1 -Mode cursor` или `.\scripts\setup_mcp.ps1` (dev)

**Ручная настройка (HTTP — по умолчанию):**

```json
{
  "mcpServers": {
    "media-mcp-server": {
      "url": "http://127.0.0.1:8765/mcp"
    }
  }
}
```

Перед подключением запустите HTTP-сервер: `cd bin; .\launch_http.cmd`

**stdio (опционально):** см. `config\mcp.stdio.json.template`

**Проверка:** откройте папку установки как workspace → **Settings → MCP → Refresh**. Статус может быть жёлтым при загрузке — убедитесь, что отображается 47 инструментов.

Шаблон: `config\mcp.json.template`

---

## OpenAI Codex (CLI / Desktop / IDE)

**Файлы конфигурации:**

| Область | Путь |
|---------|------|
| Глобально | `%USERPROFILE%\.codex\config.toml` |
| Проект | `.codex\config.toml` в корне проекта (нужен trusted project) |

**Автоустановка:** `.\install.ps1 -Mode codex` — создаёт `.codex\config.toml` с HTTP `url`

**CLI (интерактивно, stdio):**

```powershell
codex mcp add media-mcp-server -- `
  C:\Tools\media-mcp-server\bin\MediaMCPServer.exe --stdio
```

**Ручная настройка (HTTP — по умолчанию):**

```toml
[mcp_servers.media-mcp-server]
url = "http://127.0.0.1:8765/mcp"
enabled = true
startup_timeout_sec = 30
tool_timeout_sec = 120
```

> Секция называется `mcp_servers`, не `mcpServers`. Запустите HTTP-сервер: `cd bin; .\launch_http.cmd`

**stdio (опционально):** `config\codex.stdio.config.toml.template`

**Проверка:** в сессии Codex выполните `/mcp`. Для project-scoped конфига добавьте проект в trusted repos в `~\.codex\config.toml`.

Шаблон: `config\codex.config.toml.template`

Документация: [Codex MCP Servers](https://developers.openai.com/codex/config-reference)

---

## Google Antigravity

**Файл:** `%USERPROFILE%\.gemini\antigravity\mcp_config.json`

**Автоустановка:** `.\install.ps1 -Mode antigravity` — сохраняет готовый блок в `config\antigravity.mcp_config.json`

**Как открыть конфиг в IDE:**

1. Панель Agent (справа) → **⋯** (три точки)
2. **Manage MCP Servers** → **View raw config**

**Ручная настройка (HTTP — по умолчанию):**

```json
{
  "mcpServers": {
    "media-mcp-server": {
      "serverUrl": "http://127.0.0.1:8765/mcp"
    }
  }
}
```

Добавьте блок в существующий `mcpServers`, не перезаписывая другие серверы. Запустите HTTP-сервер: `cd bin; .\launch_http.cmd`

**stdio (опционально):** `command` + `cwd` + `args: ["--stdio"]` — см. старые сниппеты `mcp.stdio.json.snippet`

**Проверка:** **Manage MCP Servers** → включите сервер → убедитесь, что tools появились. При необходимости перезапустите Antigravity.

> Для HTTP Antigravity использует поле `serverUrl` (не `url`).

Шаблон: `config\antigravity.mcp_config.template.json`

---

## Windsurf (Codeium Cascade)

**Файл:** `%USERPROFILE%\.codeium\windsurf\mcp_config.json`

**Автоустановка:** `.\install.ps1 -Mode windsurf` — сниппет в `config\windsurf.mcp_config.json`

**Как открыть:** иконка молотка (MCP) в Cascade → **Configure**

**Ручная настройка (HTTP):**

```json
{
  "mcpServers": {
    "media-mcp-server": {
      "url": "http://127.0.0.1:8765/mcp"
    }
  }
}
```

Запустите HTTP-сервер: `cd bin; .\launch_http.cmd`

**Проверка:** нажмите **Refresh** (🔄) в панели MCP. Логи: `%USERPROFILE%\.codeium\windsurf\logs\`

Шаблон: `config\windsurf.mcp_config.template.json`

Документация: [Windsurf MCP](https://docs.windsurf.com/windsurf/cascade/mcp)

---

## Claude Desktop

**Файл:** `%APPDATA%\Claude\claude_desktop_config.json`

**Автоустановка:** `.\install.ps1 -Mode claude`

**Ручная настройка (HTTP):**

```json
{
  "mcpServers": {
    "media-mcp-server": {
      "url": "http://127.0.0.1:8765/mcp"
    }
  }
}
```

Запустите HTTP-сервер: `cd bin; .\launch_http.cmd`. Полностью перезапустите Claude Desktop после сохранения.

Шаблон: `config\claude_desktop_config.template.json`

---

## VS Code (GitHub Copilot / MCP)

VS Code с поддержкой MCP использует файл `.vscode\mcp.json` (workspace) или пользовательские настройки в зависимости от версии и расширения.

**Пример (workspace, HTTP):**

```json
{
  "servers": {
    "media-mcp-server": {
      "type": "http",
      "url": "http://127.0.0.1:8765/mcp"
    }
  }
}
```

**stdio (опционально):** `"type": "stdio"`, `command`, `args: ["--stdio"]`, `cwd` — см. `config\mcp.stdio.json.template`

Формат может отличаться между расширениями (Copilot, Claude Code, Continue). Используйте `.\install.ps1 -Mode print` для JSON-блока и адаптируйте под ваше расширение.

---

## Проверка работоспособности

### Быстрый тест из PowerShell

```powershell
cd C:\Tools\media-mcp-server
.\scripts\tests\test_http_mcp.ps1

# stdio (опционально):
.\scripts\tests\test_tools.ps1   # только dev-репозиторий
```

### Что проверить в клиенте

1. Сервер в списке MCP без ошибки (красный статус)
2. Отображается **47 tools**
3. Тестовый вызов: `webcam_list` или `video_probe`

---

## Устранение неполадок по клиентам

| Симптом | Cursor | Codex | Antigravity / Windsurf | Claude Desktop |
|---------|--------|-------|------------------------|----------------|
| Сервер не в списке | Refresh / Reload Window; HTTP запущен? | `/mcp`, trusted project; HTTP запущен? | Refresh / restart IDE | Полный перезапуск |
| Жёлтый статус | Подождать; проверить tools | Увеличить `startup_timeout_sec` | Toggle off/on | — |
| Connection refused | `cd bin; .\launch_http.cmd` | То же | То же | То же |
| DLL load error | stdio: `cwd` → `bin\` | stdio: `cwd` в TOML | stdio: `cwd` в JSON | stdio: `cwd` + `env` |
| Путь с пробелами | Абсолютные пути | `/` в TOML | `\\` в JSON | Абсолютные пути |
| Нет моделей | Полный ZIP, не только exe | — | — | — |

Общие решения:

- Запускайте `.\install.ps1` из корня распакованного пакета
- Не копируйте только `MediaMCPServer.exe` — нужны все DLL и `bin\models\`
- Включите `MEDIA_MCP_DEBUG=1` и смотрите stderr в логах MCP-клиента

---

## Сводка путей к конфигурации

| Среда | Файл конфигурации |
|-------|-------------------|
| Cursor | `<workspace>\.cursor\mcp.json` |
| Codex (global) | `%USERPROFILE%\.codex\config.toml` |
| Codex (project) | `<workspace>\.codex\config.toml` |
| Antigravity | `%USERPROFILE%\.gemini\antigravity\mcp_config.json` |
| Windsurf | `%USERPROFILE%\.codeium\windsurf\mcp_config.json` |
| Claude Desktop | `%APPDATA%\Claude\claude_desktop_config.json` |
| VS Code (workspace) | `<workspace>\.vscode\mcp.json` |

См. также:

- [DISTRIBUTION.md](DISTRIBUTION.md) — деплой продакшен-пакета
- [WSL.md](WSL.md) — MCP-клиент в WSL, сервер на Windows (HTTP)
- [EXAMPLES.md](EXAMPLES.md) — сложные сценарии: конспект вебинара, ONVIF/RTSP-склад, USB webcam (контроль доступа)
