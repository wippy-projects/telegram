-- Telegram Bot API type definitions
-- See: https://core.telegram.org/bots/api

type Chat = {
    id: number,
    type: string,
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
    type: string,
    offset: number,
    length: number
}

type Message = {
    message_id: number,
    from?: User,
    chat: Chat,
    date: number,
    text?: string,
    entities?: {MessageEntity}
}

type CallbackQuery = {
    id: string,
    from: User,
    message?: Message,
    data?: string
}

type Update = {
    update_id: number,
    message?: Message,
    edited_message?: Message,
    channel_post?: Message,
    edited_channel_post?: Message,
    callback_query?: CallbackQuery,
    inline_query?: table,
    chosen_inline_result?: table,
    my_chat_member?: table,
    chat_member?: table
}

type SendMessageParams = {
    chat_id: number | string,
    text: string @min_len(1),
    parse_mode?: string,
    reply_markup?: table
}

type SetWebhookParams = {
    url: string @min_len(1),
    secret_token?: string,
    allowed_updates?: {string}
}

type ApiResponse = {
    ok: boolean,
    result?: any,
    description?: string,
    error_code?: number
}
