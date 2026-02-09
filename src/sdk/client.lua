local http_client = require("http_client")
local json = require("json")
local env = require("env")
local logger = require("logger")

local BASE_URL = "https://api.telegram.org/bot"

--- Call a Telegram Bot API method.
local function api_call(method: string, payload: any?)
    local token = env.get("TELEGRAM_BOT_TOKEN")
    if not token then
        return nil, errors.new({kind = errors.INVALID, message = "TELEGRAM_BOT_TOKEN not configured"})
    end

    local url = BASE_URL .. token .. "/" .. method

    local resp, err = http_client.post(url, {
        headers = {["Content-Type"] = "application/json"},
        body = json.encode(payload or {})
    })

    if err then
        logger:error("Telegram API request failed", {method = method, error = tostring(err)})
        return nil, err
    end

    local body = json.decode(resp.body)

    if not body.ok then
        local api_err = errors.new({kind = errors.INTERNAL, message = body.description or "Unknown Telegram API error"})
        logger:error("Telegram API error", {
            method = method,
            error_code = body.error_code,
            description = body.description
        })
        return nil, api_err
    end

    return body.result, nil
end

-- ── Exported methods ────────────────────────────────────

local function send_message(params: SendMessageParams)
    return api_call("sendMessage", params)
end

local function set_webhook(params: SetWebhookParams)
    return api_call("setWebhook", params)
end

local function delete_webhook()
    return api_call("deleteWebhook", {})
end

local function get_me()
    return api_call("getMe", {})
end

return {
    send_message = send_message,
    set_webhook = set_webhook,
    delete_webhook = delete_webhook,
    get_me = get_me
}
