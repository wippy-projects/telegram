-- Telegram Bot API type definitions
-- See: https://core.telegram.org/bots/api

-- ── Literal union types ────────────────────────────────

type ChatType = "private" | "group" | "supergroup" | "channel"

type ParseMode = "HTML" | "Markdown" | "MarkdownV2"

type UpdateType = "command" | "text" | "callback_query" | "inline_query" | "edited_message" | "channel_post" | "chat_member" | "unknown"

type MessageEntityType = "mention" | "hashtag" | "cashtag" | "bot_command" | "url" | "email" | "phone_number" | "bold" | "italic" | "underline" | "strikethrough" | "spoiler" | "code" | "pre" | "text_link" | "text_mention" | "custom_emoji"

-- ── Core types ─────────────────────────────────────────

type Chat = {
    id: number,
    type: ChatType,
    title?: string,
    username?: string,
    first_name?: string,
    last_name?: string
}

type User = {
    id: number,
    is_bot: boolean,
    first_name: string,
    last_name?: string,
    username?: string,
    language_code?: string
}

type MessageEntity = {
    type: MessageEntityType,
    offset: number,
    length: number,
    url?: string,
    user?: User,
    language?: string,
    custom_emoji_id?: string
}

type Message = {
    message_id: number,
    from?: User,
    chat: Chat,
    date: number,
    text?: string,
    entities?: {MessageEntity},
    reply_to_message?: Message
}

type CallbackQuery = {
    id: string,
    from: User,
    message?: Message,
    inline_message_id?: string,
    chat_instance?: string,
    data?: string,
    game_short_name?: string
}

type InlineQuery = {
    id: string,
    from: User,
    query: string,
    offset: string,
    chat_type?: ChatType
}

type ChatMemberUpdated = {
    chat: Chat,
    from: User,
    date: number,
    old_chat_member: table,
    new_chat_member: table
}

type ChosenInlineResult = {
    result_id: string,
    from: User,
    query: string,
    inline_message_id?: string
}

type Update = {
    update_id: number,
    message?: Message,
    edited_message?: Message,
    channel_post?: Message,
    edited_channel_post?: Message,
    callback_query?: CallbackQuery,
    inline_query?: InlineQuery,
    chosen_inline_result?: ChosenInlineResult,
    my_chat_member?: ChatMemberUpdated,
    chat_member?: ChatMemberUpdated
}

-- ── Parameter types ────────────────────────────────────

type SendMessageParams = {
    chat_id: number | string,
    text: string @min_len(1),
    parse_mode?: ParseMode,
    reply_markup?: table,
    reply_to_message_id?: number,
    disable_notification?: boolean
}

type SetWebhookParams = {
    url: string @min_len(1),
    secret_token?: string,
    allowed_updates?: {string},
    max_connections?: number @min(1) @max(100)
}

-- ── Response types ─────────────────────────────────────

type ApiResponse = {
    ok: boolean,
    result?: any,
    description?: string,
    error_code?: number
}
