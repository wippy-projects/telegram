local funcs = require("funcs")
local logger = require("logger")

local function handler(update)
    local chat_id = update.message.chat.id
    local user_name = update.message.from
        and update.message.from.first_name
        or "there"

    local text = "Hello, " .. user_name .. "!\n\n"
        .. "I'm a Wippy-powered Telegram bot.\n"
        .. "Type /help to see available commands."

    local _, err = funcs.call("telegram.sdk:send_message", {
        chat_id = chat_id,
        text = text
    })

    if err then
        logger:error("Failed to send start message", {
            chat_id = chat_id,
            error = tostring(err)
        })
    end
end

return { handler = handler }
