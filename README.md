# Telegram Bot Webhook Handler

Provides Telegram bot webhook handling with registry-based command routing.

Designed as a reusable module that plugs into any Wippy application via `ns.dependency` — the package doesn't own any
infrastructure. Your app provides the HTTP router, env storage, and process host; the package handles everything else.

## Features

- **Webhook endpoint** with secret token validation (`X-Telegram-Bot-Api-Secret-Token`)
- **Automatic command dispatch** via registry — add commands without modifying the package
- **Generic update handlers** for non-command updates (callbacks, inline queries, etc.)
- **Telegram SDK** with typed API client (`sendMessage`, `setWebhook`, `deleteWebhook`, `getMe`)
- **CLI tools** to register/remove webhooks
- **Built-in `/start` and `/help` commands** — `/help` auto-discovers all registered commands

## Architecture

```
┌──────────────────────────────────────────────────────────────┐
│  PACKAGE (butschster/telegram)                               │
│                                                              │
│  ns.requirements (injected by consumer):                     │
│    ● webhook_router  → HTTP router for endpoints             │
│    ● env_storage     → where bot token & secrets live        │
│    ● process_host    → execution host for processes          │
│                                                              │
│  telegram/           Core: env vars, ns.definition           │
│  telegram.handler/   Webhook endpoint, CLI commands          │
│  telegram.commands/  /start, /help handlers                  │
│  telegram.sdk/       API client (sendMessage, setWebhook)    │
└──────────────────────────────────────────────────────────────┘
                         ▲
                         │  ns.dependency + parameters
                         │
┌──────────────────────────────────────────────────────────────┐
│  YOUR APP                                                    │
│                                                              │
│  Provides:                                                   │
│    ● http.service + http.router  → webhook_router            │
│    ● env.storage.file            → env_storage               │
│    ● process.host                → process_host              │
└──────────────────────────────────────────────────────────────┘
```

## Installation

### 1. Create `src/_telegram.yaml`

The dependency and its router **must** live in a separate file with `namespace: telegram` (matching the package's own
namespace). This is required because the webhook endpoint resolves its router reference at entry load time — before
`ns.requirement` parameter injection takes place. By defining the router in the package's namespace, the reference
`telegram:router` exists when the endpoint needs it.

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

  # Router must be defined here (in the telegram namespace) so that
  # telegram.handler:webhook.endpoint can resolve its meta.router reference.
  - name: router
    kind: http.router
    meta:
      server: app:gateway
    prefix: /telegram
```

> **Note:** Ideally you should be able to pass any router (e.g. `app:my_router`) as the `webhook_router` parameter and
> define everything in your app's namespace. This is a known limitation — `ns.requirement` injection currently happens
> after entry references are resolved. This workaround will be removed once the resolution order is fixed in Wippy.

### 2. Ensure your app provides the required infrastructure

Your app's `_index.yaml` should already have these (or similar) entries:

```yaml
# src/_index.yaml
version: "1.0"
namespace: app

entries:
  # ── Infrastructure (you probably already have these) ───

  - name: env_file
    kind: env.storage.file
    file_path: ./.env
    auto_create: true
    file_mode: 0600

  - name: processes
    kind: process.host
    lifecycle:
      auto_start: true

  - name: gateway
    kind: http.service
    addr: ":8080"
    lifecycle:
      auto_start: true
```

## Configuration

Set these environment variables in your `.env` file:

| Variable                  | Required    | Description                                                              |
|---------------------------|-------------|--------------------------------------------------------------------------|
| `TELEGRAM_BOT_TOKEN`      | Yes         | Bot token from [@BotFather](https://t.me/BotFather)                      |
| `TELEGRAM_WEBHOOK_URL`    | Yes         | Public URL for webhook (e.g. `https://your-domain.com/telegram/webhook`) |
| `TELEGRAM_WEBHOOK_SECRET` | Recommended | Secret token for webhook validation                                      |

```env
TELEGRAM_BOT_TOKEN=123456:ABC-DEF1234ghIkl-zyx57W2v1u123ew11
TELEGRAM_WEBHOOK_URL=https://your-domain.com/telegram/webhook
TELEGRAM_WEBHOOK_SECRET=your-random-secret-string
```

## Usage

### Register the webhook

```bash
wippy run register-webhook
```

This verifies your bot token via `getMe`, then registers the webhook URL with Telegram.

### Remove the webhook

```bash
wippy run delete-webhook
```

### Start the server

```bash
wippy run
```

The webhook endpoint listens at `POST /telegram/webhook` (path relative to your router prefix).

## Adding Custom Commands

Add commands to your app without modifying the package — the dispatcher discovers them via `registry.find()`.

Create a registry entry and a handler function in your app's `_index.yaml`:

```yaml
# Registry entry — discovered by the dispatcher
- name: status
  kind: registry.entry
  meta:
    type: telegram.command
    command: /status
    description: "Check system status"
    handler: app:status_handler

# Handler function
- name: status_handler
  kind: function.lua
  source: file://status.lua
  method: handler
  modules: [ funcs, logger ]
```

The handler receives the full Telegram `update` table:

```lua
local funcs = require("funcs")
local logger = require("logger")

local function handler(update)
    local chat_id = update.message.chat.id

    local _, err = funcs.call("telegram.sdk:send_message", {
        chat_id = chat_id,
        text = "All systems operational."
    })

    if err then
        logger:error("Failed to send status", {error = tostring(err)})
    end
end

return { handler = handler }
```

The command automatically appears in `/help` output.

## Adding Update Type Handlers

Handle non-command updates (callback queries, inline queries, etc.) with the same pattern:

```yaml
- name: callback_handler_entry
  kind: registry.entry
  meta:
    type: telegram.handler
    update_type: callback_query
    handler: app:callback_handler

- name: callback_handler
  kind: function.lua
  source: file://callback.lua
  method: handler
  modules: [ funcs, logger ]
```

Supported update types: `text`, `callback_query`, `inline_query`, `edited_message`, `channel_post`, `chat_member`.

## SDK Functions

Call Telegram API methods from anywhere via `funcs.call()`:

```lua
local funcs = require("funcs")

-- Send a message
local result, err = funcs.call("telegram.sdk:send_message", {
    chat_id = 123456789,
    text = "Hello!",
    parse_mode = "HTML"        -- optional
})

-- Get bot info
local me, err = funcs.call("telegram.sdk:get_me")

-- Register webhook
local _, err = funcs.call("telegram.sdk:set_webhook", {
    url = "https://example.com/telegram/webhook",
    secret_token = "my-secret"  -- optional
})

-- Remove webhook
local _, err = funcs.call("telegram.sdk:delete_webhook")
```

## Request Flow

```
Telegram Cloud
     │
     │  POST /telegram/webhook
     │  Header: X-Telegram-Bot-Api-Secret-Token: <secret>
     │  Body: { "update_id": ..., "message": { "text": "/start", ... } }
     │
     ▼
┌─────────────────────────────────────────────────────┐
│  Your App's HTTP Layer                              │
│  http.service (:8080) → http.router (/telegram)     │
│    └── POST /webhook  (package-owned endpoint)      │
└───────────────────────┬─────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────┐
│  1. Validate secret token header     → 403 if bad   │
│  2. Parse JSON body                  → 400 if bad   │
│  3. Return HTTP 200 immediately                     │
│  4. Detect update type                              │
│     ├─ /command → registry.find(telegram.command)   │
│     │            → funcs.call(handler)              │
│     ├─ other    → registry.find(telegram.handler)   │
│     │            → funcs.call(handler)              │
│     └─ unknown  → log, skip                         │
└───────────────────────┬─────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────┐
│  Command/Update Handler                             │
│  funcs.call("telegram.sdk:send_message", {...})     │
│    → Telegram Bot API                               │
└─────────────────────────────────────────────────────┘
```

## Project Structure

```
src/
├── _index.yaml              # telegram: ns.definition, ns.requirements, env vars
├── handler/
│   ├── _index.yaml          # telegram.handler: webhook endpoint + CLI commands
│   ├── webhook.lua          # Webhook handler with dispatch logic
│   ├── register_webhook.lua # CLI: register webhook
│   └── delete_webhook.lua   # CLI: remove webhook
├── commands/
│   ├── _index.yaml          # telegram.commands: /start and /help
│   ├── start.lua            # Welcome message handler
│   └── help.lua             # Dynamic command list handler
└── sdk/
    ├── _index.yaml          # telegram.sdk: API client functions
    ├── types.lua            # Telegram type definitions
    └── client.lua           # API client (sendMessage, setWebhook, etc.)

dev/                         # Development app (NOT published)
├── _index.yaml              # app: HTTP server, router, env storage, ns.dependency
└── .env                     # Bot token and webhook config
```

## Local Development

The `dev/` directory contains a consumer app for local testing. The `wippy.lock` file points to the local `src/`
directory:

```yaml
directories:
  modules: .wippy
  src: ./dev
replacements:
  - from: butschster/telegram
    to: ./src
```

To develop locally:

1. Get a bot token from [@BotFather](https://t.me/BotFather)
2. Copy your token into `dev/.env`
3. Expose your local server (e.g. via ngrok: `ngrok http 8080`)
4. Set `TELEGRAM_WEBHOOK_URL` to your ngrok URL + `/telegram/webhook`
5. Start the server: `wippy run`
6. Register the webhook: `wippy run -x telegram.handler:register_webhook`
7. Send `/start` to your bot

## Requirements

The package declares three `ns.requirement` entries that consumers must provide:

| Requirement      | Injects Into                       | Description                                   |
|------------------|------------------------------------|-----------------------------------------------|
| `webhook_router` | `.meta.router` on webhook endpoint | HTTP router where the endpoint mounts         |
| `env_storage`    | `.storage` on env.variable entries | Backend for bot token and secrets             |
| `process_host`   | `.host` on process.service entries | Execution host (for future stateful handlers) |

## License

MIT
