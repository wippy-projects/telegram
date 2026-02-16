# Voice & Audio Messages

Handle voice notes and audio files sent by Telegram users.

---

## How It Works

When a user sends a voice message or audio file, the webhook handler detects it as a `voice` or `audio` update type.
The SDK provides two functions to retrieve the file content:

1. **`telegram.sdk:get_file`** — calls Telegram's `getFile` API, returns metadata including `file_path`
2. **`telegram.sdk:download_file`** — downloads the actual file bytes using the `file_path`

```
User sends voice note
    │
    ▼
Webhook (detect_update_type → "voice")
    │
    ▼
registry.find({meta.type = "telegram.handler", meta.update_type = "voice"})
    │
    ▼
Your handler function
    │
    ├── telegram.sdk:get_file(file_id)        → { file_path = "voice/file_123.oga" }
    ├── telegram.sdk:download_file(file_path)  → raw OGG/OPUS bytes
    └── Do something with the audio (transcribe, store, analyze...)
```

## Quick Start

### 1. Register a voice handler

```yaml
# src/voice/_index.yaml
version: "1.0"
namespace: app.voice

entries:
  - name: handler_entry
    kind: registry.entry
    meta:
      type: telegram.handler
      update_type: voice
      handler: app.voice:handler

  - name: handler
    kind: function.lua
    source: file://handler.lua
    method: handler
    modules: [funcs, logger]
```

### 2. Implement the handler

```lua
-- src/voice/handler.lua
local funcs = require("funcs")
local logger = require("logger")

local function handler(update)
    local message = update.message
    local chat_id = message.chat.id
    local voice = message.voice

    logger:info("Voice received", {
        chat_id = chat_id,
        duration = voice.duration,
        mime_type = voice.mime_type,
        file_size = voice.file_size,
    })

    -- Step 1: Get file metadata
    local file_info, err = funcs.call("telegram.sdk:get_file", voice.file_id)
    if err then
        logger:error("get_file failed", {error = tostring(err)})
        funcs.call("telegram.sdk:send_message", {
            chat_id = chat_id,
            text = "Sorry, couldn't process your voice message.",
        })
        return
    end

    -- Step 2: Download the raw audio bytes
    local audio_bytes, dl_err = funcs.call("telegram.sdk:download_file", file_info.file_path)
    if dl_err then
        logger:error("download_file failed", {error = tostring(dl_err)})
        return
    end

    logger:info("Audio downloaded", {size = #audio_bytes})

    -- Step 3: Do something with the audio
    -- Send it to a transcription API, store it, analyze it, etc.
    funcs.call("telegram.sdk:send_message", {
        chat_id = chat_id,
        text = "Got your voice message! (" .. voice.duration .. "s)",
    })
end

return { handler = handler }
```

---

## Handling Audio Files

Audio files (music, recordings sent as attachments) use `update_type: audio` instead of `voice`.
The structure is identical, but the message field is `message.audio` instead of `message.voice`.

```yaml
  - name: audio_handler_entry
    kind: registry.entry
    meta:
      type: telegram.handler
      update_type: audio
      handler: app.voice:handler
```

```lua
-- Works for both voice and audio
local function extract_file_id(message)
    if message.voice then
        return message.voice.file_id, message.voice.mime_type or "audio/ogg"
    end
    if message.audio then
        return message.audio.file_id, message.audio.mime_type or "audio/mpeg"
    end
    return nil, nil
end
```

---

## Voice Object Fields

| Field            | Type    | Description                         |
|------------------|---------|-------------------------------------|
| `file_id`        | string  | Identifier for downloading the file |
| `file_unique_id` | string  | Unique ID (stable across bots)      |
| `duration`       | number  | Duration in seconds                 |
| `mime_type`      | string? | MIME type (usually `audio/ogg`)     |
| `file_size`      | number? | File size in bytes                  |

## Audio Object Fields

| Field            | Type    | Description                         |
|------------------|---------|-------------------------------------|
| `file_id`        | string  | Identifier for downloading the file |
| `file_unique_id` | string  | Unique ID (stable across bots)      |
| `duration`       | number  | Duration in seconds                 |
| `performer`      | string? | Audio performer                     |
| `title`          | string? | Audio title                         |
| `file_name`      | string? | Original filename                   |
| `mime_type`      | string? | MIME type (usually `audio/mpeg`)    |
| `file_size`      | number? | File size in bytes                  |

---

## Transcription with OpenAI Whisper

A common use case is converting voice messages to text using OpenAI's Whisper API.

### Add a transcription function

```yaml
  - name: transcribe
    kind: function.lua
    source: file://transcribe.lua
    method: transcribe
    modules: [http_client, json, env, logger]
```

### Implement transcription

```lua
-- src/voice/transcribe.lua
local http_client = require("http_client")
local json = require("json")
local env = require("env")
local logger = require("logger")

local function transcribe(audio_content, filename, mime_type)
    local api_key = env.get("OPENAI_API_KEY")
    if not api_key then
        return nil, errors.new({kind = errors.INVALID, message = "OPENAI_API_KEY not set"})
    end

    local base_url = env.get("OPENAI_BASE_URL") or "https://api.openai.com/v1"
    local model = env.get("WHISPER_MODEL") or "whisper-1"

    local resp, err = http_client.post(base_url .. "/audio/transcriptions", {
        headers = {
            ["Authorization"] = "Bearer " .. api_key,
        },
        form = {
            model = model,
        },
        files = {
            {
                name = "file",
                filename = filename or "voice.ogg",
                content = audio_content,
                content_type = mime_type or "audio/ogg",
            },
        },
        timeout = 60,
    })

    if err then
        return nil, err
    end

    if resp.status_code ~= 200 then
        logger:error("Whisper API error", {status = resp.status_code, body = resp.body})
        return nil, errors.new({kind = errors.INTERNAL, message = "Whisper returned " .. resp.status_code})
    end

    local result = json.decode(resp.body)
    return result.text, nil
end

return { transcribe = transcribe }
```

### Use in the voice handler

```lua
local function handler(update)
    local chat_id = update.message.chat.id
    local voice = update.message.voice

    -- Show typing while processing
    funcs.call("telegram.sdk:send_chat_action", {chat_id = chat_id, action = "typing"})

    -- Download audio
    local file_info = funcs.call("telegram.sdk:get_file", voice.file_id)
    local audio = funcs.call("telegram.sdk:download_file", file_info.file_path)

    -- Transcribe
    local text, err = funcs.call("app.voice:transcribe", audio, "voice.ogg", "audio/ogg")
    if err then
        funcs.call("telegram.sdk:send_message", {
            chat_id = chat_id,
            text = "Sorry, couldn't transcribe your message.",
        })
        return
    end

    funcs.call("telegram.sdk:send_message", {
        chat_id = chat_id,
        text = "You said: " .. text,
    })
end
```

---

## Limits & Notes

- Bots can download files up to **20 MB** via `getFile`
- Voice notes are OGG files encoded with OPUS
- The download URL from `getFile` is valid for **at least 1 hour**
- OpenAI Whisper supports: `mp3`, `mp4`, `mpeg`, `mpga`, `m4a`, `ogg`, `wav`, `webm` (max 25 MB)
- Voice notes over 1 MB may be sent as documents by Telegram
