# Conversation State Machine

A declarative framework for building multi-step Telegram conversations — wizards, forms, onboarding flows — using
Wippy's process-per-user actor pattern.

Each active conversation runs as an isolated process with its own state, timeout, and lifecycle. No shared state, no
Redis, no database — just lightweight actor processes.

---

## How It Works

```
User sends /order
    │
    ▼
Webhook detects "command" → checks for telegram.conversation trigger
    │
    ▼
Spawns a session process (one per chat)
    ├── Registers: process.registry("telegram.conversation:<chat_id>")
    ├── Sends first step prompt
    ├── Receives user messages via inbox
    ├── Validates input per step definition
    ├── Transitions to next step or shows error
    ├── Accumulates collected data across steps
    ├── On final step: calls on_complete with collected data
    └── Auto-expires via time.after(TTL)
```

Subsequent text and callback messages from the same chat are automatically forwarded to the active session process by
the webhook dispatcher. When the conversation completes, times out, or is cancelled, the session process exits and
cleans up its registry entry.

---

## Quick Start

### 1. Define a flow

Create a flow definition as a `library.lua` that returns a table:

```lua
-- src/flows/feedback_flow.lua
local kb = require("keyboard")

local flow = {
    name = "feedback",
    ttl = "5m",
    cancel_command = "/cancel",

    steps = {
        {
            id = "rating",
            prompt = "How would you rate our service?",
            keyboard = kb.inline()
                :row()
                    :callback("⭐", "rate:1")
                    :callback("⭐⭐", "rate:2")
                    :callback("⭐⭐⭐", "rate:3")
                :row()
                    :callback("⭐⭐⭐⭐", "rate:4")
                    :callback("⭐⭐⭐⭐⭐", "rate:5")
                :build(),
            input_type = "callback_query",
            validate = function(data)
                local n = tonumber(data:match("rate:(%d)"))
                if n and n >= 1 and n <= 5 then
                    return n, nil
                end
                return nil, "Please tap a rating button."
            end,
        },
        {
            id = "comment",
            prompt = function(state)
                return "Thanks for the " .. state.rating .. "-star rating! Any comments? (or /cancel to skip)"
            end,
            validate = function(text)
                return text, nil  -- accept anything
            end,
        },
    },

    on_complete = function(chat_id, state)
        return "Thank you for your feedback! 🙏"
    end,

    on_timeout = function(chat_id, state, current_step)
        return "⏰ Feedback session expired."
    end,

    on_cancel = function(chat_id, state, current_step)
        return "Feedback cancelled."
    end,
}

return flow
```

### 2. Register in your app

```yaml
# src/_index.yaml (your app)
entries:
  # Flow definition (library)
  - name: feedback_flow
    kind: library.lua
    source: file://flows/feedback_flow.lua
    imports:
      keyboard: telegram.sdk:keyboard

  # Conversation entry (discovered by webhook dispatcher)
  - name: feedback_conversation
    kind: registry.entry
    meta:
      type: telegram.conversation
      trigger: /feedback
      description: "Give us feedback"
      flow: app:feedback_flow
      host: app:processes
```

That's it. When a user sends `/feedback`, the webhook dispatcher finds the `telegram.conversation` entry, loads the
flow, spawns a session process on `app:processes`, and drives the conversation.

### 3. Make sure your app has a process host

```yaml
# Your app needs a process host for conversation sessions
- name: processes
  kind: process.host
  host:
    workers: 32
  lifecycle:
    auto_start: true
```

---

## Flow Definition Reference

A flow is a Lua table returned by a `library.lua` module:

```lua
local flow = {
    name = "my_flow",              -- Flow name (for logging)
    ttl = "10m",                   -- Session timeout (default: "10m")
    cancel_command = "/cancel",    -- Cancel command (default: "/cancel")
    back_command = "/back",        -- Back command (default: "/back")

    steps = { ... },               -- Array of step definitions

    on_complete = function(chat_id, state) ... end,    -- All steps done
    on_timeout = function(chat_id, state, step) ... end,  -- Session expired
    on_cancel = function(chat_id, state, step) ... end,   -- User cancelled
}
```

### Flow fields

| Field            | Type     | Required | Description                                                                                 |
|------------------|----------|----------|---------------------------------------------------------------------------------------------|
| `name`           | string   | yes      | Flow identifier for logging                                                                 |
| `ttl`            | string   | no       | Session timeout duration (default: `"10m"`)                                                 |
| `cancel_command` | string   | no       | Command to cancel (default: `"/cancel"`)                                                    |
| `back_command`   | string   | no       | Command to go back (default: `"/back"`)                                                     |
| `steps`          | table    | yes      | Array of step definitions                                                                   |
| `on_complete`    | function | no       | Called with `(chat_id, state)` when all steps pass. Return a string to send a message.      |
| `on_timeout`     | function | no       | Called with `(chat_id, state, current_step)` on timeout. Return a string to send a message. |
| `on_cancel`      | function | no       | Called with `(chat_id, state, current_step)` on cancel. Return a string to send a message.  |

---

## Step Definition Reference

Each step collects one piece of data from the user:

```lua
{
    id = "product",
    prompt = "What product?",          -- string or function(state) -> string
    keyboard = kb.inline():...:build(),  -- optional reply_markup
    input_type = "callback_query",     -- optional: "text" (default) or "callback_query"
    input_types = {"text", "location"},  -- optional: accept multiple input types
    allow_back = true,                 -- optional: allow /back navigation
    condition = function(state) ... end,  -- optional: skip if returns false
    validate = function(input) ... end,   -- optional: validate and transform input
}
```

### Step fields

| Field         | Type               | Required | Description                                                        |
|---------------|--------------------|----------|--------------------------------------------------------------------|
| `id`          | string             | yes      | Key used to store the value in `state`                             |
| `prompt`      | string or function | yes      | Message to send. If function, receives `state` and returns string. |
| `keyboard`    | table              | no       | `reply_markup` table from keyboard builder                         |
| `input_type`  | string             | no       | Expected input: `"text"` (default) or `"callback_query"`           |
| `input_types` | table              | no       | Accept multiple types — validate receives full payload             |
| `allow_back`  | boolean            | no       | Allow `/back` to return to previous step                           |
| `condition`   | function           | no       | `function(state) -> boolean` — skip step if false                  |
| `validate`    | function           | no       | `function(input) -> (value, nil)` or `(nil, error_string)`         |

### Validation

The `validate` function receives the raw input and should return either:

- `value, nil` — validation passed, `value` is stored in `state[step.id]`
- `nil, "error message"` — validation failed, error shown to user, step repeats

If no `validate` function is provided, the raw input is stored as-is.

```lua
validate = function(text)
    local n = tonumber(text)
    if n and n >= 1 and n <= 10 then
        return n, nil
    end
    return nil, "Please enter a number between 1 and 10."
end
```

### Dynamic prompts

Prompts can be functions that receive the accumulated state, useful for summary steps or context-dependent messages:

```lua
prompt = function(state)
    return string.format("You selected %s. How many?", state.product)
end
```

---

## Features

### Conditional steps

Skip steps based on previously collected data:

```lua
{
    id = "gift_wrap",
    prompt = "Would you like gift wrapping? (yes/no)",
    condition = function(state)
        return state.order_type == "gift"
    end,
    validate = function(text)
        local lower = text:lower()
        if lower == "yes" or lower == "no" then
            return lower == "yes", nil
        end
        return nil, "Please answer yes or no."
    end,
}
```

### Back navigation

Enable per-step back navigation with `/back`:

```lua
{
    id = "quantity",
    prompt = "How many? (1-10)\nSend /back to change product.",
    allow_back = true,
    validate = function(text) ... end,
}
```

When the user sends `/back`, the session moves to the previous applicable step and clears its stored value.

### Callback query input

For steps that use inline keyboard buttons instead of text input:

```lua
{
    id = "confirm",
    prompt = "Confirm your order?",
    keyboard = kb.inline()
        :row()
            :callback("✅ Yes", "confirm:yes")
            :callback("❌ No", "confirm:no")
        :build(),
    input_type = "callback_query",
    validate = function(data)
        if data == "confirm:yes" then return true, nil end
        if data == "confirm:no" then return false, nil end
        return nil, "Please use the buttons."
    end,
}
```

### Session timeout

Each conversation has a configurable TTL. The timeout resets on every successful step transition. When the session
times out, `on_timeout` is called and the session process exits.

### Cancel command

Users can send the cancel command (default `/cancel`) at any point during a conversation. The `on_cancel` callback
is called and the session exits.

### Automatic session restart

If a user sends a conversation trigger command while a session is already active (e.g. sends `/order` during an
existing order flow), the old session is cancelled and a new one starts.

---

## Registry Entry Format

```yaml
- name: my_conversation
  kind: registry.entry
  meta:
    type: telegram.conversation
    trigger: /mycommand        # Command that starts this conversation
    description: "Description" # Shown in /help (optional)
    flow: app:my_flow          # Reference to flow library.lua
    host: app:processes        # Process host for session processes
```

| Meta field    | Type   | Required | Description                                            |
|---------------|--------|----------|--------------------------------------------------------|
| `type`        | string | yes      | Must be `"telegram.conversation"`                      |
| `trigger`     | string | yes      | Command that starts the conversation (e.g. `"/order"`) |
| `description` | string | no       | Shown in /help alongside regular commands              |
| `flow`        | string | yes      | Registry reference to the flow `library.lua`           |
| `host`        | string | yes      | Process host to spawn session processes on             |

---

## Complete Example: Order Flow

### Flow definition

```lua
-- src/flows/order_flow.lua
local kb = require("keyboard")

local flow = {
    name = "order",
    ttl = "10m",
    cancel_command = "/cancel",

    steps = {
        {
            id = "product",
            prompt = "What would you like to order?",
            keyboard = kb.reply()
                :row():button("📱 Phone"):button("💻 Laptop")
                :row():button("🎧 Headphones")
                :resize():one_time()
                :build(),
            validate = function(text)
                local products = {
                    ["📱 Phone"] = "Phone",
                    ["💻 Laptop"] = "Laptop",
                    ["🎧 Headphones"] = "Headphones",
                }
                if products[text] then
                    return products[text], nil
                end
                return nil, "Please choose from the options above."
            end,
        },
        {
            id = "quantity",
            prompt = function(state)
                return "How many " .. state.product .. "s? (1-10)\nSend /back to change product."
            end,
            allow_back = true,
            validate = function(text)
                local n = tonumber(text)
                if n and n >= 1 and n <= 10 then
                    return n, nil
                end
                return nil, "Please enter a number between 1 and 10."
            end,
        },
        {
            id = "address",
            prompt = "Where should we deliver? Please send your full address.",
            allow_back = true,
            validate = function(text)
                if #text < 10 then
                    return nil, "Address seems too short. Please provide a full address."
                end
                return text, nil
            end,
        },
        {
            id = "gift_wrap",
            prompt = "Would you like gift wrapping? (yes/no)",
            condition = function(state)
                return state.quantity == 1  -- only offer for single items
            end,
            validate = function(text)
                local lower = text:lower()
                if lower == "yes" or lower == "no" then
                    return lower == "yes", nil
                end
                return nil, "Please answer yes or no."
            end,
        },
        {
            id = "confirm",
            prompt = function(state)
                local lines = {
                    "📋 Order summary:\n",
                    "Product: " .. state.product,
                    "Quantity: " .. tostring(state.quantity),
                    "Address: " .. state.address,
                }
                if state.gift_wrap ~= nil then
                    table.insert(lines, "Gift wrap: " .. (state.gift_wrap and "Yes" or "No"))
                end
                table.insert(lines, "\nConfirm this order?")
                return table.concat(lines, "\n")
            end,
            keyboard = kb.inline()
                :row()
                    :callback("✅ Confirm", "confirm:yes")
                    :callback("❌ Cancel", "confirm:no")
                :build(),
            input_type = "callback_query",
            validate = function(data)
                if data == "confirm:yes" then return true, nil end
                if data == "confirm:no" then return false, nil end
                return nil, "Please use the buttons above."
            end,
        },
    },

    on_complete = function(chat_id, state)
        if state.confirm then
            return "✅ Order placed! We'll send you a confirmation shortly."
        else
            return "Order cancelled."
        end
    end,

    on_timeout = function(chat_id, state, current_step)
        return "⏰ Order session expired. Send /order to start again."
    end,

    on_cancel = function(chat_id, state, current_step)
        return "❌ Order cancelled."
    end,
}

return flow
```

### Registry entries

```yaml
entries:
  # Flow definition
  - name: order_flow
    kind: library.lua
    source: file://flows/order_flow.lua
    imports:
      keyboard: telegram.sdk:keyboard

  # Conversation trigger
  - name: order_conversation
    kind: registry.entry
    meta:
      type: telegram.conversation
      trigger: /order
      description: "Place a new order"
      flow: app:order_flow
      host: app:processes
```

---

## Dispatch Flow

The webhook dispatcher integrates conversation support with the following priority:

1. **Command received** → check for `telegram.conversation` trigger → if found, start/restart session
2. **Command during active session** → forward to session process (handles `/cancel`, `/back` internally)
3. **Text or callback_query** → check for active session → if found, forward to session process
4. **No active session** → fall through to regular `telegram.command` or `telegram.handler` dispatch

This means conversations take priority over regular text/callback handlers while active, but regular command
handlers still work if no conversation is triggered.

---

## Architecture: Why Actors?

| Aspect          | Traditional Framework     | Wippy Conversation SM        |
|-----------------|---------------------------|------------------------------|
| Session state   | Redis/DB per user         | Process-local memory         |
| Isolation       | Shared state + locks      | Process isolation            |
| Timeout         | Cron jobs or polling      | `time.after()` per process   |
| Cleanup         | Manual garbage collection | Process exit = cleanup       |
| Discovery       | Configuration files       | Registry-based               |
| Concurrency     | Thread pools              | One process per conversation |
| Fault tolerance | Manual error recovery     | Supervisor restart           |

Each conversation session is a lightweight process (~13KB). A bot handling 10,000 concurrent conversations uses roughly
130MB — well within reach of a single node.

---

## Limitations

- **No persistence across restarts** — conversation state lives in process memory. If the runtime restarts,
  active sessions are lost. (A persistence layer is planned as a separate feature.)
- **Linear flow only** — steps proceed sequentially (with optional skips via `condition`). Branching/tree flows
  are planned for v2.
- **Text and callback input** — media input (photos, documents, location) requires using `input_types` with custom
  validation. Native media step support is planned for v2.
