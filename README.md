# Telegram Bot Webhook Handler

Provides Telegram bot webhook handling with registry-based command routing.

Designed as a reusable module that plugs into any Wippy application via `ns.dependency` — the package doesn't own any
infrastructure. Your app provides the HTTP router, env storage, and process host; the package handles everything else.

## Features

- **Webhook endpoint** with secret token validation (`X-Telegram-Bot-Api-Secret-Token`)
- **Automatic command dispatch** via registry — add commands without modifying the package
- **Generic update handlers** for non-command updates (callbacks, inline queries, etc.)
- **Telegram SDK** with typed API client (`sendMessage`, `setWebhook`, `deleteWebhook`, `getMe`, `getFile`,
  `downloadFile`)
- **CLI tools** to register/remove webhooks
- **Built-in `/start` and `/help` commands** — `/help` auto-discovers all registered commands

## Quick Start

### 1. Add the dependency

Create `src/_telegram.yaml` with the package dependency and a router in the `telegram` namespace:

```yaml
# src/_telegram.yaml
version: "1.0"
namespace: telegram

entries:
  - name: dep.telegram
    kind: ns.dependency
    component: butschster/telegram
    version: "*"
    parameters:
      - name: telegram:webhook_router
        value: telegram:router
      - name: telegram:env_storage
        value: app:env_file

  - name: router
    kind: http.router
    meta:
      server: app:gateway
    prefix: /telegram
```

> See [Installation & Configuration](docs/installation.md) for full setup instructions and known limitations.

### 2. Configure environment

```env
TELEGRAM_BOT_TOKEN=123456:ABC-DEF1234ghIkl-zyx57W2v1u123ew11
TELEGRAM_WEBHOOK_URL=https://your-domain.com/telegram/webhook
TELEGRAM_WEBHOOK_SECRET=your-random-secret-string
```

### 3. Register webhook and start

```bash
wippy run register-webhook
wippy run
```

## Documentation

| Topic                                                 | Description                                                       |
|-------------------------------------------------------|-------------------------------------------------------------------|
| [Installation & Configuration](docs/installation.md)  | Full setup guide, env variables, requirements                     |
| [Architecture](docs/architecture.md)                  | Package structure, request flow, namespace hierarchy, file layout |
| [Custom Commands & Handlers](docs/custom-handlers.md) | Adding bot commands and update type handlers                      |
| [SDK Reference](docs/sdk-reference.md)                | All Telegram API functions (`send_message`, `get_file`, etc.)     |
| [Voice & Audio Messages](docs/voice-messages.md)      | Handling voice notes, audio files, transcription with Whisper     |
| [LLM Integration](docs/llm-integration.md)            | Building AI-powered bots: text, multi-turn, agents, voice → LLM   |
| [Local Development](docs/local-development.md)        | Dev setup, useful commands, `dev/` directory                      |

## Adding a Custom Command

Register a command entry and handler in your app — the dispatcher discovers them automatically:

```yaml
- name: status
  kind: registry.entry
  meta:
    type: telegram.command
    command: /status
    description: "Check system status"
    handler: app:status_handler

- name: status_handler
  kind: function.lua
  source: file://status.lua
  method: handler
  modules: [ funcs, logger ]
```

```lua
local funcs = require("funcs")

local function handler(update)
    funcs.call("telegram.sdk:send_message", {
        chat_id = update.message.chat.id,
        text = "All systems operational."
    })
end

return { handler = handler }
```

See [Custom Commands & Handlers](docs/custom-handlers.md) for update type handlers, supported types, and how discovery
works.

## License

MIT
