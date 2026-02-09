# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

A publishable Wippy Hub package (`butschster/telegram`) that provides Telegram bot webhook handling with registry-based
command routing. It is a **library package**, not a standalone app — consumers provide infrastructure (HTTP router, env
storage, process host) via `ns.dependency` parameters.

## Commands

```bash
# Start the dev server (uses dev/ as the app entry point via wippy.lock)
wippy run

# Register webhook with Telegram
wippy run register-webhook

# Remove webhook
wippy run delete-webhook

# Lint a specific namespace
wippy lint --ns=telegram
wippy lint --ns=telegram.*
wippy lint --ns=telegram.sdk
```

## Architecture

### Namespace hierarchy

- `telegram` (root) — `ns.definition`, `ns.requirement` declarations, env variable entries
- `telegram.handler` — Webhook HTTP endpoint + CLI process commands
- `telegram.commands` — Built-in `/start` and `/help` command handlers (registered via `registry.entry`)
- `telegram.sdk` — Telegram Bot API client functions (`send_message`, `set_webhook`, `delete_webhook`, `get_me`)

### Key patterns

**Registry-based dispatch**: The webhook handler (`src/handler/webhook.lua`) uses
`registry.find({kind = "registry.entry"})` to discover commands (`meta.type == "telegram.command"`) and update
handlers (`meta.type == "telegram.handler"`). Consumers add commands by creating `registry.entry` entries in their own
namespace — no modification of this package needed.

**Dependency injection via ns.requirement**: The package declares three requirements in `src/_index.yaml`:

- `webhook_router` → injected into `telegram.handler:webhook.endpoint` at `.meta.router`
- `env_storage` → injected into env variable entries at `.storage`
- `process_host` → reserved for future stateful handlers (targets currently empty)

**Cross-entry function calls**: Handlers call SDK functions via `funcs.call("telegram.sdk:send_message", params)`. The
SDK (`src/sdk/client.lua`) wraps the Telegram Bot API with `http_client.post()`.

### Entry kinds used

| Kind             | Purpose                                          |
|------------------|--------------------------------------------------|
| `ns.definition`  | Package metadata                                 |
| `ns.requirement` | Declares what consumers must provide             |
| `env.variable`   | Bot token, webhook URL, webhook secret           |
| `http.endpoint`  | POST /webhook                                    |
| `function.lua`   | Webhook handler, SDK functions, command handlers |
| `process.lua`    | CLI commands (register/delete webhook)           |
| `registry.entry` | Command registration (/start, /help)             |
| `library.lua`    | Type definitions                                 |

## Lua conventions

- Handlers are Lua modules returning a table of named functions (e.g., `return { handler = handler }`)
- Modules are declared in `_index.yaml` entry definitions (`modules: [http, json, registry, funcs, env, logger]`) and
  loaded via `require()`
- Error handling follows the `result, err` two-return pattern — always check `err` before using `result`
- CLI processes (`process.lua`) return an integer exit code from `main()`
- Type definitions use Luau-style type annotations (`type Chat = { id: number, ... }`)

## Documentation access

The `context.yaml` file defines tools for querying Wippy documentation at `home.wj.wippy.ai/llm/`. Key doc paths:
`lua/core/process`, `lua/core/funcs`, `lua/core/registry`, `lua/http/http`, `lua/http/client`, `http/server`,
`http/router`, `http/endpoint`, `guides/publishing`, `guides/dependency-management`.

## Wippy Documentation

- Docs site: https://home.wj.wippy.ai/
- LLM-friendly index: https://home.wj.wippy.ai/llms.txt
- Batch fetch pages: `https://home.wj.wippy.ai/llm/context?paths=<comma-separated-paths>`
- Search: `https://home.wj.wippy.ai/llm/search?q=<query>`

