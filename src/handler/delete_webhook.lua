local io = require("io")
local funcs = require("funcs")

local function main(): integer
    io.print("=== Telegram Webhook Removal ===")
    io.print("")

    local _, err = funcs.call("telegram.sdk:delete_webhook")
    if err then
        io.print("ERROR: " .. tostring(err))
        return 1
    end

    io.print("Webhook removed successfully.")
    return 0
end

return { main = main }
