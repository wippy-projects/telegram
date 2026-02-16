# Custom Commands & Handlers

Add your own commands and update handlers without modifying the Telegram package.

The webhook dispatcher discovers handlers via `registry.find()` — you just register entries in your app's namespace.

---

## Adding Commands

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
-- status.lua
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

---

## Adding Update Type Handlers

Handle non-command updates (callback queries, inline queries, etc.) with the same pattern, using
`meta.type: telegram.handler` instead of `telegram.command`:

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

### Supported update types

| Update Type      | Trigger                           | Message Field    |
|------------------|-----------------------------------|------------------|
| `text`           | Plain text message                | `message.text`   |
| `voice`          | Voice note (recorded in Telegram) | `message.voice`  |
| `audio`          | Audio file (music, recording)     | `message.audio`  |
| `callback_query` | Inline button press               | `callback_query` |
| `inline_query`   | Inline mode query                 | `inline_query`   |
| `edited_message` | Edited message                    | `edited_message` |
| `channel_post`   | Channel message                   | `channel_post`   |
| `chat_member`    | Chat member status change         | `my_chat_member` |

---

## How Discovery Works

The webhook handler (`src/handler/webhook.lua`) uses this logic:

1. **Commands** (`/start`, `/status`, etc.) — searches for entries with `meta.type == "telegram.command"` and matching
   `meta.command` value.
2. **Update types** (`text`, `voice`, `callback_query`, etc.) — searches for entries with
   `meta.type == "telegram.handler"` and matching `meta.update_type` value.
3. Once found, calls the handler via `funcs.call(meta.handler, update)`.

This means you can add commands from any namespace in your app — the dispatcher will find them as long as the registry
entries have the correct `meta` fields.

---

## See Also

- [Voice & Audio Messages](voice-messages.md) — detailed guide for handling voice notes and audio files
- [LLM Integration](llm-integration.md) — building AI-powered bots with conversation state
- [SDK Reference](sdk-reference.md) — all available Telegram API functions
