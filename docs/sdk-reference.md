# Telegram SDK Reference

Quick reference for all SDK functions and patterns.

---

## SDK Functions

All functions are called via `funcs.call()`:

```lua
local funcs = require("funcs")
local result, err = funcs.call("telegram.sdk:<function>", ...)
```

### send_message

Send a text message to a chat.

```lua
local result, err = funcs.call("telegram.sdk:send_message", {
    chat_id = 123456789,        -- required: number or string
    text = "Hello!",            -- required: message text
    parse_mode = "HTML",        -- optional: "HTML", "Markdown", "MarkdownV2"
    reply_to_message_id = 42,   -- optional: reply to specific message
    disable_notification = true, -- optional: silent message
    reply_markup = {...},       -- optional: inline keyboard, etc.
})
```

### send_photo_url

Send a photo by URL. Telegram downloads the image from the provided URL.

```lua
local result, err = funcs.call("telegram.sdk:send_photo_url", {
    chat_id = 123456789,        -- required
    photo = "https://example.com/image.jpg",  -- required: image URL
    caption = "Check this out!", -- optional
    parse_mode = "HTML",        -- optional
})
```

### send_chat_action

Show typing or upload indicator.

```lua
funcs.call("telegram.sdk:send_chat_action", {
    chat_id = 123456789,
    action = "typing",  -- "typing", "upload_photo", "upload_video",
                        -- "upload_voice", "upload_document", "find_location"
})
```

### answer_callback_query

Acknowledge an inline button press. Stops the loading spinner on the button.

```lua
funcs.call("telegram.sdk:answer_callback_query", {
    callback_query_id = callback_query.id,  -- required
    text = "Done!",                          -- optional: notification text
    show_alert = false,                      -- optional: show as alert popup
    cache_time = 0,                          -- optional: cache seconds
})
```

### get_file

Get file metadata. Returns a table with `file_id`, `file_unique_id`, `file_size`, `file_path`.

```lua
local file_info, err = funcs.call("telegram.sdk:get_file", "BAADBAADAgAD...")
-- file_info.file_path → "voice/file_123.oga"
```

### download_file

Download file content from Telegram servers. Takes the `file_path` from `get_file`.

```lua
local raw_bytes, err = funcs.call("telegram.sdk:download_file", file_info.file_path)
-- raw_bytes is a string containing the file data
```

### get_me

Get bot info.

```lua
local bot, err = funcs.call("telegram.sdk:get_me")
-- bot.id, bot.first_name, bot.username
```

### get_chat

Get up-to-date information about a chat. For private chats, returns full user profile including bio and photo info.

```lua
local chat, err = funcs.call("telegram.sdk:get_chat", chat_id)
-- chat.id, chat.type, chat.first_name, chat.last_name,
-- chat.username, chat.bio, chat.photo
```

### get_user_profile_photos

Get a list of profile pictures for a user.

```lua
local photos, err = funcs.call("telegram.sdk:get_user_profile_photos", {
    user_id = 123456789,     -- required
    offset = 0,              -- optional: sequential number of the first photo
    limit = 100,             -- optional: 1-100 (default: 100)
})
-- photos.total_count, photos.photos (array of PhotoSize arrays)
```

### set_webhook

Register a webhook URL with Telegram.

```lua
funcs.call("telegram.sdk:set_webhook", {
    url = "https://example.com/telegram/webhook",
    secret_token = "my-secret",    -- optional
    allowed_updates = {"message"},  -- optional
    max_connections = 40,           -- optional: 1-100
})
```

### delete_webhook

Remove the webhook.

```lua
funcs.call("telegram.sdk:delete_webhook")
```

---

## Update Types

The webhook handler detects these update types and dispatches to registered handlers:

| Update Type      | Trigger                           | Message Field    |
|------------------|-----------------------------------|------------------|
| `command`        | Text starting with `/`            | `message.text`   |
| `text`           | Plain text message                | `message.text`   |
| `voice`          | Voice note (recorded in Telegram) | `message.voice`  |
| `audio`          | Audio file (music, recording)     | `message.audio`  |
| `callback_query` | Inline button press               | `callback_query` |
| `inline_query`   | Inline mode query                 | `inline_query`   |
| `edited_message` | Edited message                    | `edited_message` |
| `channel_post`   | Channel message                   | `channel_post`   |
| `chat_member`    | Chat member status change         | `my_chat_member` |

### Registering handlers

Commands use `meta.type: telegram.command`:

```yaml
- name: my_command
  kind: registry.entry
  meta:
    type: telegram.command
    command: /mycommand
    description: "What the command does"
    handler: app:my_command_handler
```

All other types use `meta.type: telegram.handler`:

```yaml
- name: my_handler
  kind: registry.entry
  meta:
    type: telegram.handler
    update_type: voice       # text, voice, audio, callback_query, etc.
    handler: app:my_handler_func
```

---

## Common Patterns

### Download any file type

```lua
local function download_telegram_file(file_id)
    local file_info, err = funcs.call("telegram.sdk:get_file", file_id)
    if err then return nil, err end

    local content, dl_err = funcs.call("telegram.sdk:download_file", file_info.file_path)
    if dl_err then return nil, dl_err end

    return content, nil
end
```

### Reply to a specific message

```lua
funcs.call("telegram.sdk:send_message", {
    chat_id = chat_id,
    text = "This is a reply",
    reply_to_message_id = update.message.message_id,
})
```

### Extract user info

```lua
local function get_user_info(update)
    local from = update.message and update.message.from
    if not from then return nil end

    return {
        id = from.id,
        username = from.username,
        first_name = from.first_name,
        last_name = from.last_name,
        language = from.language_code,
    }
end
```
