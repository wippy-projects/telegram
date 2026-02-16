# Using LLM with Telegram SDK

Build AI-powered Telegram bots by combining the Telegram SDK with Wippy's LLM and Agent modules.

---

## Prerequisites

Your app needs the Telegram package, LLM module, and (optionally) the Agent module:

```yaml
# src/_index.yaml
version: "1.0"
namespace: app

entries:
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

  # ── Dependencies ────────────────────────────────────
  - name: dep.llm
    kind: ns.dependency
    component: wippy/llm
    version: "*"
    parameters:
      - name: env_storage
        value: app:env_file
      - name: process_host
        value: app:processes

  - name: dep.agent
    kind: ns.dependency
    component: wippy/agent
    version: "*"
```

And a model definition:

```yaml
  - name: gpt-4o
    kind: registry.entry
    meta:
      name: gpt-4o
      type: llm.model
      title: GPT-4o
      capabilities: [ generate, tool_use, structured_output, vision ]
      class: [ smart, balanced ]
      priority: 100
    max_tokens: 128000
    output_tokens: 16384
    providers:
      - id: wippy.llm.openai:provider
        provider_model: gpt-4o
```

---

## Example 1: Simple Text Reply with LLM

The simplest integration — receive a text message, send it to the LLM, reply with the result.

### Registry

```yaml
# src/ai/_index.yaml
version: "1.0"
namespace: app.ai

entries:
  - name: text_handler_entry
    kind: registry.entry
    meta:
      type: telegram.handler
      update_type: text
      handler: app.ai:text_handler

  - name: text_handler
    kind: function.lua
    source: file://handler.lua
    method: text_handler
    modules: [ funcs, logger ]
    imports:
      llm: wippy.llm:llm
```

### Handler

```lua
-- src/ai/handler.lua
local funcs = require("funcs")
local logger = require("logger")
local llm = require("llm")

local function text_handler(update)
    local chat_id = update.message.chat.id
    local user_text = update.message.text

    -- Show typing indicator
    funcs.call("telegram.sdk:send_chat_action", {
        chat_id = chat_id,
        action = "typing",
    })

    -- Call the LLM
    local response, err = llm.generate(user_text, {
        model = "gpt-4o",
        temperature = 0.7,
        max_tokens = 1024,
    })

    if err then
        logger:error("LLM error", {error = tostring(err)})
        funcs.call("telegram.sdk:send_message", {
            chat_id = chat_id,
            text = "Sorry, something went wrong.",
        })
        return
    end

    funcs.call("telegram.sdk:send_message", {
        chat_id = chat_id,
        text = response.result,
    })
end

return { text_handler = text_handler }
```

> **Note:** This is stateless — each message is independent with no conversation history.

---

## Example 2: Multi-Turn Conversations with Prompt Builder

Use a per-user process to maintain conversation history across messages.

### Registry

```yaml
# src/chat/_index.yaml
version: "1.0"
namespace: app.chat

entries:
  - name: text_handler_entry
    kind: registry.entry
    meta:
      type: telegram.handler
      update_type: text
      handler: app.chat:entry

  - name: entry
    kind: function.lua
    source: file://entry.lua
    method: handler
    modules: [ funcs, logger ]

  - name: session
    kind: process.lua
    source: file://session.lua
    method: main
    modules: [ funcs, logger, time ]
    imports:
      llm: wippy.llm:llm
      prompt: wippy.llm:prompt
```

### Entry point (finds or spawns per-user session)

```lua
-- src/chat/entry.lua
local funcs = require("funcs")
local logger = require("logger")

local function handler(update)
    local chat_id = update.message.chat.id
    local text = update.message.text
    local reg_name = "chat:" .. tostring(chat_id)

    -- Find existing session for this user
    local pid = process.registry.lookup(reg_name)

    if not pid then
        -- Spawn a new session process
        pid = process.spawn_monitored("app.chat:session", "app:processes", chat_id)
        if not pid then
            funcs.call("telegram.sdk:send_message", {
                chat_id = chat_id,
                text = "Sorry, couldn't start a chat session.",
            })
            return
        end
    end

    -- Forward the message to the session process
    process.send(pid, "user_message", {chat_id = chat_id, text = text})
end

return { handler = handler }
```

### Session process (maintains conversation state)

```lua
-- src/chat/session.lua
local funcs = require("funcs")
local logger = require("logger")
local time = require("time")
local llm = require("llm")
local prompt = require("prompt")

local SESSION_TTL = "30m"

local function send_typing(chat_id)
    funcs.call("telegram.sdk:send_chat_action", {chat_id = chat_id, action = "typing"})
end

local function send_message(chat_id, text)
    funcs.call("telegram.sdk:send_message", {chat_id = chat_id, text = text})
end

local function main(chat_id)
    local reg_name = "chat:" .. tostring(chat_id)
    process.registry.register(reg_name)

    logger:info("Chat session started", {chat_id = chat_id})

    -- Build conversation with system prompt
    local conversation = prompt.new()
    conversation:add_system(
        "You are a helpful Telegram bot. Keep responses concise — they're displayed on mobile."
    )

    local inbox = process.inbox()
    local events = process.events()
    local timeout = time.after(SESSION_TTL)

    while true do
        local r = channel.select {
            events:case_receive(),
            inbox:case_receive(),
            timeout:case_receive(),
        }

        if r.channel == events then
            if r.value.kind == process.event.CANCEL then
                process.registry.unregister(reg_name)
                return 0
            end

        elseif r.channel == timeout then
            -- Session expired
            send_message(chat_id, "Session expired after 30 minutes of inactivity.")
            process.registry.unregister(reg_name)
            return 0

        elseif r.channel == inbox then
            local msg = r.value
            if msg:topic() == "user_message" then
                local data = msg:payload():data()

                -- Reset inactivity timer
                timeout = time.after(SESSION_TTL)

                -- Add user message to conversation
                conversation:add_user(data.text)

                send_typing(chat_id)

                -- Call LLM with full conversation history
                local response, err = llm.generate(conversation, {
                    model = "gpt-4o",
                    temperature = 0.7,
                    max_tokens = 1024,
                })

                if err then
                    logger:error("LLM error", {error = tostring(err)})
                    send_message(chat_id, "Sorry, I had trouble with that. Try again?")
                else
                    -- Add assistant response to history
                    conversation:add_assistant(response.result)
                    send_message(chat_id, response.result)
                end
            end
        end
    end
end

return { main = main }
```

### Architecture

```
User sends message
    │
    ▼
Webhook → text_handler_entry → entry.lua
    │
    ├── process.registry.lookup("chat:<chat_id>")
    │   ├── found → forward message
    │   └── not found → spawn session process
    │
    ▼
Session Process (per-user, long-running)
    │
    ├── Maintains prompt builder (conversation history)
    ├── Calls llm.generate() with full context
    ├── Sends response via telegram.sdk:send_message
    └── Auto-expires after 30min inactivity
```

---

## Example 3: Agent with Tools

Use the Agent framework for a more structured approach with tool calling.

### Registry

```yaml
# src/agent/_index.yaml
version: "1.0"
namespace: app.agent

entries:
  # ── Agent Definition ────────────────────────────────
  - name: assistant
    kind: registry.entry
    meta:
      type: agent.gen1
      name: telegram-assistant
      title: Telegram Assistant
    prompt: |
      You are a helpful Telegram bot assistant.
      Keep responses concise for mobile readability.
      Use tools when they help answer the question.
    model: gpt-4o
    max_tokens: 1024
    temperature: 0.7
    tools:
      - app.agent:get_time

  # ── Tool: Current Time ──────────────────────────────
  - name: get_time
    kind: function.lua
    meta:
      type: tool
      title: Current Time
      input_schema: '{"type": "object", "properties": {}, "additionalProperties": false}'
      llm_alias: get_current_time
      llm_description: Get the current date and time.
    source: file://tools.lua
    method: get_time
    modules: [ time ]

  # ── Telegram Handler ────────────────────────────────
  - name: text_handler_entry
    kind: registry.entry
    meta:
      type: telegram.handler
      update_type: text
      handler: app.agent:entry

  - name: entry
    kind: function.lua
    source: file://entry.lua
    method: handler
    modules: [ funcs, logger ]

  - name: session
    kind: process.lua
    source: file://session.lua
    method: main
    modules: [ funcs, logger, time, json ]
    imports:
      prompt: wippy.llm:prompt
      agent_context: wippy.agent:context
```

### Tool implementation

```lua
-- src/agent/tools.lua
local time = require("time")

local function get_time()
    local now = time.now()
    return {
        utc = now:format("2006-01-02T15:04:05Z"),
        unix = now:unix(),
    }
end

return { get_time = get_time }
```

### Entry point (same pattern as Example 2)

```lua
-- src/agent/entry.lua
local funcs = require("funcs")
local logger = require("logger")

local function handler(update)
    local chat_id = update.message.chat.id
    local text = update.message.text
    local reg_name = "agent:" .. tostring(chat_id)

    local pid = process.registry.lookup(reg_name)

    if not pid then
        pid = process.spawn_monitored("app.agent:session", "app:processes", chat_id)
        if not pid then
            funcs.call("telegram.sdk:send_message", {
                chat_id = chat_id,
                text = "Sorry, couldn't start a session.",
            })
            return
        end
    end

    process.send(pid, "user_message", {chat_id = chat_id, text = text})
end

return { handler = handler }
```

### Agent session with tool execution loop

```lua
-- src/agent/session.lua
local funcs = require("funcs")
local logger = require("logger")
local time = require("time")
local json = require("json")
local prompt = require("prompt")
local agent_context = require("agent_context")

local SESSION_TTL = "30m"

local function send_typing(chat_id)
    funcs.call("telegram.sdk:send_chat_action", {chat_id = chat_id, action = "typing"})
end

local function send_message(chat_id, text)
    funcs.call("telegram.sdk:send_message", {chat_id = chat_id, text = text})
end

--- Execute tool calls and add results to conversation.
local function execute_tools(tool_calls, conversation)
    for _, tc in ipairs(tool_calls) do
        local args = tc.arguments
        if type(args) == "string" then
            args = json.decode(args) or {}
        end

        local result, err = funcs.call(tc.registry_id, args)
        local result_str
        if err then
            result_str = json.encode({error = tostring(err)})
        else
            result_str = json.encode(result)
        end

        conversation:add_function_call(tc.name, tc.arguments, tc.id)
        conversation:add_function_result(tc.name, result_str, tc.id)
    end
end

--- Run a full turn: call agent, execute tools in a loop, return final text.
local function run_turn(runner, conversation)
    while true do
        local response, err = runner:step(conversation)
        if err then
            return nil, err
        end

        -- If no tool calls, we're done
        if not response.tool_calls or #response.tool_calls == 0 then
            return response.result, nil
        end

        -- Execute tools and loop back for the agent to use results
        execute_tools(response.tool_calls, conversation)
    end
end

local function main(chat_id)
    local reg_name = "agent:" .. tostring(chat_id)
    process.registry.register(reg_name)

    logger:info("Agent session started", {chat_id = chat_id})

    -- Load the agent
    local ctx = agent_context.new()
    local runner, load_err = ctx:load_agent("app.agent:assistant")
    if load_err then
        logger:error("Failed to load agent", {error = tostring(load_err)})
        send_message(chat_id, "Sorry, failed to initialize.")
        process.registry.unregister(reg_name)
        return 1
    end

    local conversation = prompt.new()
    local inbox = process.inbox()
    local events = process.events()
    local timeout = time.after(SESSION_TTL)

    while true do
        local r = channel.select {
            events:case_receive(),
            inbox:case_receive(),
            timeout:case_receive(),
        }

        if r.channel == events then
            if r.value.kind == process.event.CANCEL then
                process.registry.unregister(reg_name)
                return 0
            end

        elseif r.channel == timeout then
            send_message(chat_id, "Session expired.")
            process.registry.unregister(reg_name)
            return 0

        elseif r.channel == inbox then
            local msg = r.value
            if msg:topic() == "shutdown" then
                process.registry.unregister(reg_name)
                return 0
            end

            if msg:topic() == "user_message" then
                local data = msg:payload():data()

                timeout = time.after(SESSION_TTL)
                conversation:add_user(data.text)
                send_typing(chat_id)

                local reply, err = run_turn(runner, conversation)
                if err then
                    logger:error("Agent error", {error = tostring(err)})
                    send_message(chat_id, "Sorry, something went wrong.")
                else
                    conversation:add_assistant(reply)
                    send_message(chat_id, reply)
                end
            end
        end
    end
end

return { main = main }
```

---

## Example 4: Voice → LLM (Combining Voice + AI)

Transcribe voice messages and feed them into the LLM conversation. Builds on Examples 2/3.

### Add voice handler entry alongside text

```yaml
  # Handle both text and voice the same way
  - name: voice_handler_entry
    kind: registry.entry
    meta:
      type: telegram.handler
      update_type: voice
      handler: app.chat:voice_entry

  - name: voice_entry
    kind: function.lua
    source: file://voice_entry.lua
    method: handler
    modules: [ funcs, logger, http_client, json, env ]

  - name: transcribe
    kind: function.lua
    source: file://voice_entry.lua
    method: transcribe
    modules: [ funcs, logger, http_client, json, env ]
```

### Voice entry — transcribe then forward to same session

```lua
-- src/chat/voice_entry.lua
local funcs = require("funcs")
local logger = require("logger")
local http_client = require("http_client")
local json = require("json")
local env = require("env")

local function transcribe(audio_content, filename, mime_type)
    local api_key = env.get("OPENAI_API_KEY")
    local base_url = env.get("OPENAI_BASE_URL") or "https://api.openai.com/v1"
    local model = env.get("WHISPER_MODEL") or "whisper-1"

    local resp, err = http_client.post(base_url .. "/audio/transcriptions", {
        headers = {["Authorization"] = "Bearer " .. api_key},
        form = {model = model},
        files = {{
            name = "file",
            filename = filename,
            content = audio_content,
            content_type = mime_type,
        }},
        timeout = 60,
    })

    if err then return nil, err end
    if resp.status_code ~= 200 then
        return nil, errors.new({kind = errors.INTERNAL, message = "Whisper status " .. resp.status_code})
    end

    local result = json.decode(resp.body)
    return result.text, nil
end

local function handler(update)
    local chat_id = update.message.chat.id
    local voice = update.message.voice
    if not voice then return end

    funcs.call("telegram.sdk:send_chat_action", {chat_id = chat_id, action = "typing"})

    -- Download voice
    local file_info, err = funcs.call("telegram.sdk:get_file", voice.file_id)
    if err then return end
    local audio = funcs.call("telegram.sdk:download_file", file_info.file_path)

    -- Transcribe
    local text, t_err = funcs.call("app.chat:transcribe", audio, "voice.ogg", "audio/ogg")
    if t_err then
        funcs.call("telegram.sdk:send_message", {
            chat_id = chat_id,
            text = "Sorry, couldn't understand your voice message.",
        })
        return
    end

    -- Forward transcribed text to the same session process as text messages
    local reg_name = "chat:" .. tostring(chat_id)
    local pid = process.registry.lookup(reg_name)

    if not pid then
        pid = process.spawn_monitored("app.chat:session", "app:processes", chat_id)
    end

    if pid then
        process.send(pid, "user_message", {chat_id = chat_id, text = text})
    end
end

return { handler = handler, transcribe = transcribe }
```

The key insight: after transcription, the voice message enters the same pipeline as text. The session process doesn't
need to know whether the input came from voice or text.

---

## Patterns & Tips

### Process-per-user pattern

Every user gets their own long-running process identified by `process.registry.register("prefix:<chat_id>")`.
This gives you isolated state per conversation. The text/voice entry function just looks up or spawns the process.

### Typing indicators

Always call `send_chat_action` before LLM calls. Users need visual feedback that their message is being processed.

```lua
funcs.call("telegram.sdk:send_chat_action", {chat_id = chat_id, action = "typing"})
```

### Token budget for history

Keep conversation history under control. Approximate token count and trim old messages:

```lua
local MAX_TOKENS = 5000

local function trim_history(messages)
    local total = 0
    for i = #messages, 1, -1 do
        total = total + (#messages[i].content / 4)  -- rough estimate: 4 chars ≈ 1 token
    end
    while total > MAX_TOKENS and #messages > 1 do
        local removed = table.remove(messages, 1)
        total = total - (#removed.content / 4)
    end
end
```

### Model selection

Use model classes for flexibility:

```lua
-- Pick the fastest available model
llm.generate(conversation, { model = "class:fast" })

-- Pick a smart model
llm.generate(conversation, { model = "class:smart" })

-- Specific model
llm.generate(conversation, { model = "gpt-4o" })
```

### Error messages

Keep error messages user-friendly. Log the technical details, show a simple message:

```lua
if err then
    logger:error("LLM failed", {error = tostring(err), chat_id = chat_id})
    send_message(chat_id, "Sorry, I'm having trouble right now. Please try again.")
    return
end
```
