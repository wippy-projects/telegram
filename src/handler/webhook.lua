local http = require("http")
local json = require("json")
local registry = require("registry")
local funcs = require("funcs")
local env = require("env")
local logger = require("logger")

-- ── Helpers ──────────────────────────────────────────────

--- Extract the chat ID from any update type.
local function get_chat_id(update): number?
    if update.message and update.message.chat then
        return update.message.chat.id
    end
    if update.callback_query and update.callback_query.message then
        return update.callback_query.message.chat.id
    end
    if update.edited_message and update.edited_message.chat then
        return update.edited_message.chat.id
    end
    if update.channel_post and update.channel_post.chat then
        return update.channel_post.chat.id
    end
    return nil
end

--- Build the conversation registry name for a given chat.
local function conversation_reg_name(chat_id: number): string
    return "telegram.conversation:" .. tostring(chat_id)
end

-- ── Update Type Detection ────────────────────────────────

--- Detect the type of a Telegram update.
--- Returns: update_type, value (command name or callback data), update
local function detect_update_type(update)
    if update.message and update.message.text then
        local cmd = update.message.text:match("^(/[%w_]+)")
        if cmd then
            return "command", cmd, update
        end
        return "text", nil, update
    end

    if update.message and update.message.voice then
        return "voice", nil, update
    end

    if update.message and update.message.audio then
        return "audio", nil, update
    end

    if update.callback_query then
        return "callback_query", update.callback_query.data, update
    end

    if update.inline_query then
        return "inline_query", nil, update
    end

    if update.edited_message then
        return "edited_message", nil, update
    end

    if update.channel_post then
        return "channel_post", nil, update
    end

    if update.my_chat_member then
        return "chat_member", nil, update
    end

    return "unknown", nil, update
end

-- ── Conversation Session Management ──────────────────────

--- Try to forward an update to an active conversation session.
--- Returns true if forwarded, false if no active session exists.
local function try_forward_to_conversation(chat_id: number, update_type: string, update): boolean
    local reg_name = conversation_reg_name(chat_id)
    local pid, err = process.registry.lookup(reg_name)
    if err or not pid then
        return false
    end

    -- Build the payload for the session process
    local payload = {}

    if update_type == "text" or update_type == "command" then
        payload.text = update.message.text
    elseif update_type == "callback_query" then
        payload.callback_data = update.callback_query.data
        payload.callback_query_id = update.callback_query.id
    elseif update_type == "voice" then
        payload.voice = update.message.voice
    elseif update_type == "audio" then
        payload.audio = update.message.audio
    end

    -- Include the full update for advanced flows
    payload.update = update

    process.send(pid, "user_input", payload)
    return true
end

--- Start a new conversation session for a flow entry.
local function start_conversation(entry: table, update)
    local chat_id = get_chat_id(update)
    if not chat_id then
        logger:error("Cannot start conversation: no chat_id")
        return
    end

    local reg_name = conversation_reg_name(chat_id)

    -- Check if a session already exists for this chat
    local existing_pid, _ = process.registry.lookup(reg_name)
    if existing_pid then
        -- Cancel the existing session so we can start fresh
        logger:info("Restarting conversation", {chat_id = chat_id})
        process.cancel(existing_pid, "5s")
        -- Small delay to let the old session clean up
        -- The new session will register once it starts
    end

    local flow_id = entry.meta.flow
    local host_id = entry.meta.host

    if not flow_id then
        logger:error("Conversation entry missing 'flow' in meta", {entry = entry.id})
        return
    end

    if not host_id then
        logger:error("Conversation entry missing 'host' in meta", {entry = entry.id})
        return
    end

    -- Load the flow definition via require (it's a library.lua)
    -- The flow is loaded by the session process itself via its imports,
    -- but we need to pass it. Use funcs to load the library and get the flow table.
    local flow, load_err = funcs.call(flow_id)
    if load_err then
        logger:error("Failed to load conversation flow", {
            flow = flow_id,
            error = tostring(load_err),
        })
        return
    end

    -- Spawn the conversation session process
    local pid, spawn_err = process.spawn(
        "telegram.conversation:session",
        host_id,
        chat_id,
        flow
    )

    if spawn_err then
        logger:error("Failed to spawn conversation session", {
            chat_id = chat_id,
            flow = flow_id,
            error = tostring(spawn_err),
        })
        return
    end

    logger:info("Conversation started", {
        chat_id = chat_id,
        flow = flow_id,
        pid = pid,
    })
end

-- ── Dispatch Functions ───────────────────────────────────

--- Check if a command is a conversation trigger and start it.
--- Returns true if handled as a conversation, false otherwise.
local function try_dispatch_conversation(cmd: string, update): boolean
    local entries, err = registry.find({
        ["meta.type"] = "telegram.conversation",
        ["meta.trigger"] = cmd,
    })
    if err then
        logger:error("Failed to query conversation registry", {error = tostring(err)})
        return false
    end

    if #entries > 0 and entries[1].meta then
        start_conversation(entries[1], update)
        return true
    end

    return false
end

--- Find and call a command handler from registry.
local function dispatch_command(cmd: string, update)
    -- First check for conversation triggers
    if try_dispatch_conversation(cmd, update) then
        return
    end

    -- Check for active conversation — a command during a conversation
    -- that isn't /cancel or /back falls through to the session process.
    local chat_id = get_chat_id(update)
    if chat_id then
        if try_forward_to_conversation(chat_id, "command", update) then
            return
        end
    end

    -- Regular command dispatch
    local entries, err = registry.find({["meta.type"] = "telegram.command", ["meta.command"] = cmd})
    if err then
        logger:error("Failed to query registry", {error = tostring(err)})
        return
    end

    for _, entry in ipairs(entries) do
        if entry.meta then
            local handler_id: string = tostring(entry.meta.handler)
            local _, call_err = funcs.call(handler_id, update)
            if call_err then
                logger:error("Command handler failed", {
                    command = cmd,
                    handler = handler_id,
                    error = tostring(call_err)
                })
            end
            return
        end
    end

    logger:warn("No handler for command", {command = cmd})
end

--- Find and call a generic update type handler from registry.
local function dispatch_update(update_type: string, update)
    -- Check for active conversation session first
    local chat_id = get_chat_id(update)
    if chat_id then
        if try_forward_to_conversation(chat_id, update_type, update) then
            return
        end
    end

    -- Fall through to regular handler dispatch
    local entries, err = registry.find({["meta.type"] = "telegram.handler", ["meta.update_type"] = update_type})
    if err then
        logger:error("Failed to query registry for handlers", {error = tostring(err)})
        return
    end

    for _, entry in ipairs(entries) do
        if entry.meta then
            local handler_id: string = tostring(entry.meta.handler)
            local _, call_err = funcs.call(handler_id, update)
            if call_err then
                logger:error("Update handler failed", {
                    update_type = update_type,
                    handler = handler_id,
                    error = tostring(call_err)
                })
            end
            return
        end
    end

    logger:debug("No handler for update type", {update_type = update_type})
end

-- ── Webhook HTTP Handler ─────────────────────────────────

--- Webhook HTTP handler — receives Telegram updates.
local function handler()
    local req = http.request()
    local res = http.response()

    -- 1. Validate secret token
    local secret = env.get("TELEGRAM_WEBHOOK_SECRET")
    if secret then
        local header_secret = req:header("X-Telegram-Bot-Api-Secret-Token")
        if header_secret ~= secret then
            res:set_status(403)
            return res:write_json({error = "Forbidden"})
        end
    end

    -- 2. Parse JSON body
    local update, err = req:body_json()
    if err then
        res:set_status(400)
        return res:write_json({error = "Invalid JSON"})
    end

    logger:info("Webhook received", {update_id = update.update_id})

    -- 3. Always respond 200 (Telegram retries on non-2xx)
    res:set_status(200)
    res:write_json({ok = true})

    -- 4. Detect and dispatch
    local update_type, value, _ = detect_update_type(update)

    if update_type == "command" and value then
        dispatch_command(value, update)
    else
        dispatch_update(update_type, update)
    end
end

return { handler = handler }
