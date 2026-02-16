# Keyboard Builder

Fluent API for building Telegram inline keyboards, reply keyboards, keyboard removal, and force reply markup.

Available as a library module at `telegram.sdk:keyboard` — pure Lua, no I/O, no module dependencies.

---

## Quick Start

```lua
local kb = require("keyboard")

-- Build an inline keyboard
local markup = kb.inline()
    :row()
        :callback("✅ Approve", "approve:123")
        :callback("❌ Reject", "reject:123")
    :row()
        :url("🔗 View details", "https://example.com/orders/123")
    :build()

-- Use with send_message
funcs.call("telegram.sdk:send_message", {
    chat_id = chat_id,
    text = "Review request #123",
    reply_markup = markup,
})
```

---

## Inline Keyboard

Create interactive button rows attached to messages.

```lua
local markup = kb.inline()
    :row()
        :callback("Button A", "action:a")
        :callback("Button B", "action:b")
    :row()
        :url("Open link", "https://example.com")
    :row()
        :switch_inline("Share", "query text")
    :row()
        :web_app("Launch App", "https://app.example.com")
    :build()
```

### Inline button methods

| Method | Description |
|--------|-------------|
| `:button(text, opts)` | Generic button — pass any option table |
| `:callback(text, data)` | Callback data button (max 64 bytes) |
| `:url(text, url)` | Open a URL |
| `:switch_inline(text, query)` | Switch to inline mode |
| `:switch_inline_current(text, query)` | Inline mode in current chat |
| `:web_app(text, url)` | Open a Web App |

### Dynamic keyboards from data

```lua
local items = {
    {id = "1", name = "Pizza"},
    {id = "2", name = "Burger"},
    {id = "3", name = "Sushi"},
}

local builder = kb.inline()
for _, item in ipairs(items) do
    builder:row():callback(item.name, "order:" .. item.id)
end
local markup = builder:build()
```

### Pagination helper

Adds a navigation row with prev / current / next buttons:

```lua
local markup = kb.inline()
    :row()
        :callback("Item A", "select:a")
        :callback("Item B", "select:b")
    :pagination_row({
        current_page = 2,
        total_pages = 5,
        callback_prefix = "page:",  -- generates "page:1", "page:3"
    })
    :build()
-- Produces row: [« 1] [· 2 ·] [3 »]
```

#### Pagination options

| Option | Type | Description |
|--------|------|-------------|
| `current_page` | number | Current page number (required) |
| `total_pages` | number | Total number of pages (required) |
| `callback_prefix` | string | Prefix for callback data (default: `"page:"`) |

The pagination row is skipped when `total_pages` is 1 or less.

---

## Reply Keyboard

Persistent button menu displayed below the input field.

```lua
local markup = kb.reply()
    :row()
        :button("📊 Status")
        :button("📋 Help")
    :row()
        :button("⚙️ Settings")
    :resize()
    :one_time()
    :placeholder("Choose an option...")
    :build()
```

### Reply button methods

| Method | Description |
|--------|-------------|
| `:button(text)` | Simple text button |
| `:contact(text)` | Request user's phone number |
| `:location(text)` | Request user's location |
| `:poll(text, type?)` | Request to create a poll (optional type: `"quiz"` or `"regular"`) |

### Reply keyboard options

| Method | Description |
|--------|-------------|
| `:resize()` | Fit keyboard height to number of buttons |
| `:one_time()` | Hide keyboard after a button is pressed |
| `:persistent()` | Always show the keyboard |
| `:selective()` | Show only to mentioned/replied-to users |
| `:placeholder(text)` | Input field placeholder (max 64 chars) |

---

## Remove Keyboard

Hide an active reply keyboard.

```lua
local markup = kb.remove()
    :selective()  -- optional: only for specific users
    :build()

funcs.call("telegram.sdk:send_message", {
    chat_id = chat_id,
    text = "Keyboard removed.",
    reply_markup = markup,
})
```

---

## Force Reply

Force the user's client to display a reply interface.

```lua
local markup = kb.force_reply()
    :placeholder("Type your answer...")
    :selective()
    :build()
```

---

## Complete Example: Interactive Menu

A command that shows a menu and handles button presses.

### Registry entries

```yaml
# Commands and handlers in your app's _index.yaml
- name: menu
  kind: registry.entry
  meta:
    type: telegram.command
    command: /menu
    description: "Show main menu"
    handler: app:show_menu

- name: menu_callback
  kind: registry.entry
  meta:
    type: telegram.handler
    update_type: callback_query
    handler: app:handle_menu_callback

- name: show_menu
  kind: function.lua
  source: file://show_menu.lua
  method: handler
  modules: [ funcs ]

- name: handle_menu_callback
  kind: function.lua
  source: file://handle_menu_callback.lua
  method: handler
  modules: [ funcs ]
```

### Command handler — show_menu.lua

```lua
local funcs = require("funcs")
local kb = require("keyboard")

local function handler(update)
    local markup = kb.inline()
        :row()
            :callback("📊 Status", "menu:status")
            :callback("📋 Tasks", "menu:tasks")
        :row()
            :callback("⚙️ Settings", "menu:settings")
        :build()

    funcs.call("telegram.sdk:send_message", {
        chat_id = update.message.chat.id,
        text = "What would you like to do?",
        reply_markup = markup,
    })
end

return { handler = handler }
```

### Callback handler — handle_menu_callback.lua

```lua
local funcs = require("funcs")

local function handler(update)
    local cb = update.callback_query
    local data = cb.data  -- "menu:status", "menu:tasks", etc.

    -- Acknowledge the callback (stops loading spinner)
    funcs.call("telegram.sdk:answer_callback_query", {
        callback_query_id = cb.id,
    })

    if data == "menu:status" then
        funcs.call("telegram.sdk:send_message", {
            chat_id = cb.message.chat.id,
            text = "All systems operational ✅",
        })
    elseif data == "menu:tasks" then
        funcs.call("telegram.sdk:send_message", {
            chat_id = cb.message.chat.id,
            text = "You have 3 pending tasks.",
        })
    elseif data == "menu:settings" then
        funcs.call("telegram.sdk:send_message", {
            chat_id = cb.message.chat.id,
            text = "Settings coming soon.",
        })
    end
end

return { handler = handler }
```

---

## Output Format

Each builder's `:build()` returns a table that matches Telegram's `reply_markup` format:

| Builder | Output structure |
|---------|-----------------|
| `kb.inline():build()` | `{inline_keyboard = {{...}, ...}}` |
| `kb.reply():build()` | `{keyboard = {{...}, ...}, resize_keyboard = ..., ...}` |
| `kb.remove():build()` | `{remove_keyboard = true, ...}` |
| `kb.force_reply():build()` | `{force_reply = true, ...}` |

Pass the result directly as the `reply_markup` field in `telegram.sdk:send_message`.

---

## Notes

- **No modules required** — the keyboard library is pure Lua table construction. Just `require("keyboard")` in any
  function that has `telegram.sdk:keyboard` available as a library dependency.
- **Auto-row creation** — if you call a button method without calling `:row()` first, a row is created automatically.
- **Chainable** — all methods return `self`, so you can chain everything in a single expression.
- `answer_callback_query` is not part of the keyboard builder — it's a separate SDK function
  for acknowledging inline button presses.
