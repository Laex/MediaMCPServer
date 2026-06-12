# Установка Media-MCP-Server в различные среды

Руководство по подключению MCP-сервера к IDE и CLI-агентам. Сервер работает только на **Windows 10/11 x64**.

Поддерживаемые транспорты MCP:

| Транспорт | Режим | Когда использовать |
|-----------|-------|-------------------|
| **stdio** (по умолчанию) | Клиент запускает `MediaMCPServer.exe` | Cursor, локальная разработка |
| **Streamable HTTP** | Отдельный HTTP-процесс | Codex, Antigravity, удалённый доступ |

## Перед началом

### Вариант A — готовый пакет (продакшен)

1. Распакуйте `media-mcp-server-*.zip` в постоянную папку, например `C:\Tools\media-mcp-server\`
2. Запустите установщик:

```powershell
cd C:\Tools\media-mcp-server
.\install.ps1
```

Скрипт создаёт `.cursor\mcp.json` и сниппеты в `config\` для других клиентов.

Точечная установка:

```powershell
.\install.ps1 -Mode cursor
.\install.ps1 -Mode codex
.\install.ps1 -Mode antigravity
.\install.ps1 -Mode windsurf
.\install.ps1 -Mode claude
.\install.ps1 -Mode snippets   # все сниппеты в config\
```

### Вариант B — сборка из исходников (разработка)

```powershell
cd MediaMCPServer
.\install.ps1
.\scripts\setup_mcp.ps1   # только Cursor
```

### Общие правила конфигурации

| Параметр | Значение |
|----------|----------|
| `command` | Абсолютный путь к `bin\MediaMCPServer.exe` |
| `cwd` | Абсолютный путь к `bin\` (для загрузки DLL и моделей) |
| `args` | `[]` (пустой массив) |

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
.\MediaMCPServer.exe --http
# или
.\launch_http.cmd
```

Параметры и переменные окружения:

| Параметр / переменная | По умолчанию | Описание |
|-----------------------|--------------|----------|
| `--http` | — | Включить HTTP-режим |
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

## Cursor

**Файл:** `.cursor\mcp.json` в корне workspace (проектный уровень)

**Автоустановка:** `.\install.ps1 -Mode cursor` или `.\scripts\setup_mcp.ps1` (dev)

**Ручная настройка:**

```json
{
  "mcpServers": {
    "media-mcp-server": {
      "command": "C:\\Tools\\media-mcp-server\\bin\\MediaMCPServer.exe",
      "args": [],
      "cwd": "C:\\Tools\\media-mcp-server\\bin"
    }
  }
}
```

**Проверка:** откройте папку установки как workspace → **Settings → MCP → Refresh**. Статус может быть жёлтым при загрузке — убедитесь, что отображается 47 инструментов.

Шаблон: `config\mcp.json.template`

---

## OpenAI Codex (CLI / Desktop / IDE)

**Файлы конфигурации:**

| Область | Путь |
|---------|------|
| Глобально | `%USERPROFILE%\.codex\config.toml` |
| Проект | `.codex\config.toml` в корне проекта (нужен trusted project) |

**Автоустановка:** `.\install.ps1 -Mode codex` — создаёт `.codex\config.toml` в папке пакета и сниппет в `config\codex.config.toml`

**CLI (интерактивно):**

```powershell
codex mcp add media-mcp-server -- `
  C:\Tools\media-mcp-server\bin\MediaMCPServer.exe
```

**Ручная настройка (TOML):**

```toml
[mcp_servers.media-mcp-server]
command = "C:/Tools/media-mcp-server/bin/MediaMCPServer.exe"
args = []
cwd = "C:/Tools/media-mcp-server/bin"
enabled = true
startup_timeout_sec = 30
tool_timeout_sec = 120
```

> Секция называется `mcp_servers`, не `mcpServers`. В TOML допустимы прямые слэши `/`.

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

**Ручная настройка (stdio):**

```json
{
  "mcpServers": {
    "media-mcp-server": {
      "command": "C:\\Tools\\media-mcp-server\\bin\\MediaMCPServer.exe",
      "args": [],
      "cwd": "C:\\Tools\\media-mcp-server\\bin"
    }
  }
}
```

Добавьте блок в существующий `mcpServers`, не перезаписывая другие серверы.

**Проверка:** **Manage MCP Servers** → включите сервер → убедитесь, что tools появились. При необходимости перезапустите Antigravity.

> Для HTTP-серверов Antigravity использует поле `serverUrl` (не `url`). Media-MCP-Server — локальный stdio, `serverUrl` не нужен.

Шаблон: `config\antigravity.mcp_config.template.json`

---

## Windsurf (Codeium Cascade)

**Файл:** `%USERPROFILE%\.codeium\windsurf\mcp_config.json`

**Автоустановка:** `.\install.ps1 -Mode windsurf` — сниппет в `config\windsurf.mcp_config.json`

**Как открыть:** иконка молотка (MCP) в Cascade → **Configure**

**Ручная настройка:**

```json
{
  "mcpServers": {
    "media-mcp-server": {
      "command": "C:\\Tools\\media-mcp-server\\bin\\MediaMCPServer.exe",
      "args": [],
      "cwd": "C:\\Tools\\media-mcp-server\\bin"
    }
  }
}
```

**Проверка:** нажмите **Refresh** (🔄) в панели MCP. Логи: `%USERPROFILE%\.codeium\windsurf\logs\`

Шаблон: `config\windsurf.mcp_config.template.json`

Документация: [Windsurf MCP](https://docs.windsurf.com/windsurf/cascade/mcp)

---

## Claude Desktop

**Файл:** `%APPDATA%\Claude\claude_desktop_config.json`

**Автоустановка:** `.\install.ps1 -Mode claude`

**Ручная настройка:**

```json
{
  "mcpServers": {
    "media-mcp-server": {
      "command": "C:\\Tools\\media-mcp-server\\bin\\MediaMCPServer.exe",
      "args": [],
      "cwd": "C:\\Tools\\media-mcp-server\\bin"
    }
  }
}
```

Полностью перезапустите Claude Desktop после сохранения.

> На Windows поле `cwd` в некоторых версиях может игнорироваться. Если сервер не стартует, укажите абсолютный путь в `command` и задайте `MEDIA_MCP_DATA_PATH` через `env`.

Шаблон: `config\claude_desktop_config.template.json`

---

## VS Code (GitHub Copilot / MCP)

VS Code с поддержкой MCP использует файл `.vscode\mcp.json` (workspace) или пользовательские настройки в зависимости от версии и расширения.

**Пример (workspace):**

```json
{
  "servers": {
    "media-mcp-server": {
      "type": "stdio",
      "command": "C:\\Tools\\media-mcp-server\\bin\\MediaMCPServer.exe",
      "args": [],
      "cwd": "C:\\Tools\\media-mcp-server\\bin"
    }
  }
}
```

Формат может отличаться между расширениями (Copilot, Claude Code, Continue). Используйте `.\install.ps1 -Mode print` для JSON-блока и адаптируйте под ваше расширение.

---

## Проверка работоспособности

### Быстрый тест из PowerShell

```powershell
cd C:\Tools\media-mcp-server
.\scripts\tests\test_tools.ps1   # только dev-репозиторий

# или вручную:
$exe = "C:\Tools\media-mcp-server\bin\MediaMCPServer.exe"
# ... см. scripts\tests\test_tools.ps1
```

### Что проверить в клиенте

1. Сервер в списке MCP без ошибки (красный статус)
2. Отображается **47 tools**
3. Тестовый вызов: `webcam_list` или `video_probe`

---

## Устранение неполадок по клиентам

| Симптом | Cursor | Codex | Antigravity / Windsurf | Claude Desktop |
|---------|--------|-------|------------------------|----------------|
| Сервер не в списке | Refresh / Reload Window | `/mcp`, trusted project | Refresh / restart IDE | Полный перезапуск |
| Жёлтый статус | Подождать; проверить tools | Увеличить `startup_timeout_sec` | Toggle off/on | — |
| DLL load error | `cwd` → `bin\` | `cwd` в TOML | `cwd` в JSON | `cwd` + `env` |
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
- [EXAMPLES.md](EXAMPLES.md) — сложные сценарии: конспект вебинара, ONVIF/RTSP-склад, USB webcam (контроль доступа)
