# Architecture

Overview of how the Telegram package is structured, how requests flow, and how files are organized.

---

## Package Structure

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

The package **does not own any infrastructure**. Your app provides the HTTP router, env storage, and process host;
the package handles webhook dispatch, command routing, and the Telegram API client.

---

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
│     ├─ voice    → registry.find(telegram.handler)   │
│     │            → funcs.call(handler)              │
│     ├─ audio    → registry.find(telegram.handler)   │
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

### Key design decisions

- **HTTP 200 returned immediately** — handler logic runs after the response, so Telegram never retries due to timeouts.
- **Registry-based dispatch** — the webhook handler discovers commands and update handlers via `registry.find()`.
  Consumers add new handlers without modifying the package.
- **Secret token validation** — the `X-Telegram-Bot-Api-Secret-Token` header is checked against the
  `TELEGRAM_WEBHOOK_SECRET` env variable. Requests with a missing or invalid token get a 403 response.

---

## Namespace Hierarchy

| Namespace           | Responsibility                                                                   |
|---------------------|----------------------------------------------------------------------------------|
| `telegram`          | Root — `ns.definition`, `ns.requirement` declarations, env variable entries      |
| `telegram.handler`  | Webhook HTTP endpoint + CLI process commands (register/delete webhook)           |
| `telegram.commands` | Built-in `/start` and `/help` command handlers (registered via `registry.entry`) |
| `telegram.sdk`      | Telegram Bot API client functions (`send_message`, `set_webhook`, etc.)          |

---

## Entry Kinds Used

| Kind             | Purpose                                          |
|------------------|--------------------------------------------------|
| `ns.definition`  | Package metadata                                 |
| `ns.requirement` | Declares what consumers must provide             |
| `env.variable`   | Bot token, webhook URL, webhook secret           |
| `http.endpoint`  | `POST /webhook`                                  |
| `function.lua`   | Webhook handler, SDK functions, command handlers |
| `process.lua`    | CLI commands (register/delete webhook)           |
| `registry.entry` | Command registration (`/start`, `/help`)         |
| `library.lua`    | Type definitions                                 |

---

## File Layout

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
    ├── types.lua            # Telegram type definitions (Message, Voice, Audio, File, etc.)
    └── client.lua           # API client (sendMessage, getFile, downloadFile, etc.)
```

---

## Requirements

The package declares three `ns.requirement` entries that consumers must provide:

| Requirement      | Injects Into                         | Description                                   |
|------------------|--------------------------------------|-----------------------------------------------|
| `webhook_router` | `.meta.router` on webhook endpoint   | HTTP router where the endpoint mounts         |
| `env_storage`    | `.storage` on `env.variable` entries | Backend for bot token and secrets             |
| `process_host`   | `.host` on `process.service` entries | Execution host (for future stateful handlers) |
