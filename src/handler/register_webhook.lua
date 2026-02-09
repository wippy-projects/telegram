local io = require("io")
local funcs = require("funcs")
local env = require("env")

local function main(): integer
    io.print("=== Telegram Webhook Registration ===")
    io.print("")

    -- 1. Verify bot token via getMe
    io.print("Checking bot identity...")
    local me, err = funcs.call("telegram.sdk:get_me")
    if err then
        io.print("ERROR: Failed to reach Telegram API: " .. tostring(err))
        io.print("Check TELEGRAM_BOT_TOKEN in .env")
        return 1
    end
    io.print("  Bot: @" .. (me.username or "unknown"))
    io.print("  Name: " .. me.first_name)
    io.print("")

    -- 2. Read webhook config
    local webhook_url = env.get("TELEGRAM_WEBHOOK_URL")
    if not webhook_url then
        io.print("ERROR: TELEGRAM_WEBHOOK_URL not set")
        return 1
    end

    local secret = env.get("TELEGRAM_WEBHOOK_SECRET")

    -- 3. Register webhook
    io.print("Registering webhook...")
    io.print("  URL: " .. webhook_url)

    local params = {url = webhook_url}
    if secret then
        params.secret_token = secret
        io.print("  Secret: (configured)")
    end

    local _, set_err = funcs.call("telegram.sdk:set_webhook", params)
    if set_err then
        io.print("ERROR: " .. tostring(set_err))
        return 1
    end

    io.print("")
    io.print("Webhook registered successfully!")
    return 0
end

return { main = main }
