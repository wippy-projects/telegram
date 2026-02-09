local http = require("http")
local json = require("json")
local registry = require("registry")
local funcs = require("funcs")
local env = require("env")
local logger = require("logger")

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

--- Find and call a command handler from registry.
local function dispatch_command(cmd: string, update)
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
