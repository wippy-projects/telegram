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

--- Edit the text of an existing message.
local function edit_message_text(params)
    return api_call("editMessageText", params)
end

--- Delete a message.
local function delete_message(params)
    return api_call("deleteMessage", params)
end

--- Call a Telegram Bot API method with multipart/form-data (for file uploads).
local function api_call_multipart(method: string, form: table, files: table)
    local token = env.get("TELEGRAM_BOT_TOKEN")
    if not token then
        return nil, errors.new({kind = errors.INVALID, message = "TELEGRAM_BOT_TOKEN not configured"})
    end

    local url = BASE_URL .. token .. "/" .. method

    local resp, err = http_client.post(url, {
        form = form,
        files = files,
        timeout = 60,
    })

    if err then
        logger:error("Telegram API multipart request failed", {method = method, error = tostring(err)})
        return nil, err
    end

    local body = json.decode(resp.body)

    if not body.ok then
        local api_err = errors.new({kind = errors.INTERNAL, message = body.description or "Unknown Telegram API error"})
        logger:error("Telegram API error", {
            method = method,
            error_code = body.error_code,
            description = body.description,
        })
        return nil, api_err
    end

    return body.result, nil
end

--- Send a photo to a chat.
--- params.chat_id      (number|string) required
--- params.photo_bytes  (string)        raw image bytes for upload
--- params.filename     (string?)       filename (default: "photo.png")
--- params.content_type (string?)       MIME type (default: "image/png")
--- params.caption      (string?)       photo caption
--- params.parse_mode   (string?)       "HTML" or "MarkdownV2"
--- params.reply_markup (table?)        inline keyboard or other markup
local function send_photo(params)
    local form = {
        chat_id = tostring(params.chat_id),
    }
    if params.caption then form.caption = params.caption end
    if params.parse_mode then form.parse_mode = params.parse_mode end
    if params.reply_markup then form.reply_markup = json.encode(params.reply_markup) end

    local files = {
        {
            name = "photo",
            filename = params.filename or "photo.png",
            content = params.photo_bytes,
            content_type = params.content_type or "image/png",
        },
    }

    return api_call_multipart("sendPhoto", form, files)
end

--- Send a photo by URL. Telegram downloads the image from the URL.
--- params.chat_id    (number|string) required
--- params.photo      (string)        image URL (http/https)
--- params.caption    (string?)       photo caption
--- params.parse_mode (string?)       "HTML" or "MarkdownV2"
local function send_photo_url(params)
    return api_call("sendPhoto", params)
end

--- Send a document (file) to a chat.
--- params.chat_id       (number|string) required
--- params.document_bytes (string)       raw file bytes for upload
--- params.filename       (string)       filename with extension
--- params.content_type   (string?)      MIME type (default: "application/octet-stream")
--- params.caption        (string?)      document caption
--- params.parse_mode     (string?)      "HTML" or "MarkdownV2"
local function send_document(params)
    local form = {
        chat_id = tostring(params.chat_id),
    }
    if params.caption then form.caption = params.caption end
    if params.parse_mode then form.parse_mode = params.parse_mode end

    local files = {
        {
            name = "document",
            filename = params.filename or "file",
            content = params.document_bytes,
            content_type = params.content_type or "application/octet-stream",
        },
    }

    return api_call_multipart("sendDocument", form, files)
end

--- Send a voice message to a chat.
--- params.chat_id       (number|string) required
--- params.voice_bytes   (string)        raw audio bytes (OGG Opus recommended)
--- params.filename      (string?)       filename (default: "voice.ogg")
--- params.content_type  (string?)       MIME type (default: "audio/ogg")
--- params.caption       (string?)       voice message caption
--- params.parse_mode    (string?)       "HTML" or "MarkdownV2"
--- params.duration      (number?)       duration in seconds
local function send_voice(params)
    local form = {
        chat_id = tostring(params.chat_id),
    }
    if params.caption then form.caption = params.caption end
    if params.parse_mode then form.parse_mode = params.parse_mode end
    if params.duration then form.duration = tostring(params.duration) end

    local files = {
        {
            name = "voice",
            filename = params.filename or "voice.ogg",
            content = params.voice_bytes,
            content_type = params.content_type or "audio/ogg",
        },
    }

    return api_call_multipart("sendVoice", form, files)
end

--- Get up-to-date information about a chat (private, group, supergroup, or channel).
--- For private chats, returns user info including bio, photo, etc.
--- @param chat_id number|string — Unique identifier for the target chat
local function get_chat(chat_id)
    return api_call("getChat", {chat_id = chat_id})
end

--- Get a list of profile pictures for a user.
--- @param params table — {user_id: number, offset?: number, limit?: number}
local function get_user_profile_photos(params)
    return api_call("getUserProfilePhotos", params)
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
    send_photo = send_photo,
    send_photo_url = send_photo_url,
    send_voice = send_voice,
    send_document = send_document,
    set_webhook = set_webhook,
    delete_webhook = delete_webhook,
    get_me = get_me,
    send_chat_action = send_chat_action,
    answer_callback_query = answer_callback_query,
    edit_message_text = edit_message_text,
    edit_message_reply_markup = edit_message_reply_markup,
    delete_message = delete_message,
    get_file = get_file,
    download_file = download_file,
    get_chat = get_chat,
    get_user_profile_photos = get_user_profile_photos,
}
