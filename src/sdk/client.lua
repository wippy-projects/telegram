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

local function send_chat_action(params)
    return api_call("sendChatAction", params)
end

--- Answer a callback query (inline button press).
--- Stops the loading spinner on the button.
local function answer_callback_query(params)
    return api_call("answerCallbackQuery", params)
end

--- Edit the reply markup of an existing message (e.g. remove inline keyboard).
local function edit_message_reply_markup(params)
    return api_call("editMessageReplyMarkup", params)
end

--- Get file info by file_id (returns file_path for download).
local function get_file(file_id: string)
    return api_call("getFile", {file_id = file_id})
end

--- Download file content from Telegram servers.
--- Returns raw file content (string) or nil, error.
local function download_file(file_path: string)
    local token = env.get("TELEGRAM_BOT_TOKEN")
    if not token then
        return nil, errors.new({kind = errors.INVALID, message = "TELEGRAM_BOT_TOKEN not configured"})
    end

    local url = "https://api.telegram.org/file/bot" .. token .. "/" .. file_path

    local resp, err = http_client.get(url, {timeout = 60})
    if err then
        logger:error("Failed to download file", {file_path = file_path, error = tostring(err)})
        return nil, err
    end

    if resp.status_code ~= 200 then
        local dl_err = errors.new({kind = errors.INTERNAL, message = "File download failed with status " .. tostring(resp.status_code)})
        return nil, dl_err
    end

    return resp.body, nil
end

return {
    send_message = send_message,
    set_webhook = set_webhook,
    delete_webhook = delete_webhook,
    get_me = get_me,
    send_chat_action = send_chat_action,
    answer_callback_query = answer_callback_query,
    edit_message_reply_markup = edit_message_reply_markup,
    get_file = get_file,
    download_file = download_file,
}
