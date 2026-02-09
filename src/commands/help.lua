local funcs = require("funcs")
local registry = require("registry")
local logger = require("logger")

local function handler(update)
    local chat_id = update.message.chat.id

    local entries, err = registry.find({kind = "registry.entry"})
    if err then
        logger:error("Failed to query registry", {error = tostring(err)})
        return
    end

    local lines = {"Available commands:\n"}

    for _, entry in ipairs(entries) do
        if entry.meta and entry.meta.type == "telegram.command" then
            local cmd = entry.meta.command or "?"
            local desc = entry.meta.description or "No description"
            table.insert(lines, cmd .. " — " .. desc)
        end
    end

    if #lines == 1 then
        table.insert(lines, "No commands registered.")
    end

    local _, send_err = funcs.call("telegram.sdk:send_message", {
        chat_id = chat_id,
        text = table.concat(lines, "\n")
    })

    if send_err then
        logger:error("Failed to send help message", {
            chat_id = chat_id,
            error = tostring(send_err)
        })
    end
end

return { handler = handler }
