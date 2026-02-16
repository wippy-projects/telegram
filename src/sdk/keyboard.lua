-- Telegram Keyboard Builder
-- Fluent API for building inline keyboards, reply keyboards,
-- keyboard removal, and force reply markup.

-- ── Inline Keyboard Builder ──────────────────────────────

local InlineBuilder = {}
InlineBuilder.__index = InlineBuilder

--- Start a new row of buttons.
function InlineBuilder:row()
    table.insert(self._rows, {})
    return self
end

--- Add a button with arbitrary options to the current row.
--- Creates a row automatically if none exists.
function InlineBuilder:button(text: string, opts: table?)
    local btn = {text = text}
    if opts then
        for k, v in pairs(opts) do btn[k] = v end
    end
    if #self._rows == 0 then self:row() end
    table.insert(self._rows[#self._rows], btn)
    return self
end

--- Shorthand: callback_data button.
function InlineBuilder:callback(text: string, data: string)
    return self:button(text, {callback_data = data})
end

--- Shorthand: URL button.
function InlineBuilder:url(text: string, url: string)
    return self:button(text, {url = url})
end

--- Shorthand: switch_inline_query button.
function InlineBuilder:switch_inline(text: string, query: string)
    return self:button(text, {switch_inline_query = query})
end

--- Shorthand: switch_inline_query_current_chat button.
function InlineBuilder:switch_inline_current(text: string, query: string)
    return self:button(text, {switch_inline_query_current_chat = query})
end

--- Shorthand: web_app button.
function InlineBuilder:web_app(text: string, url: string)
    return self:button(text, {web_app = {url = url}})
end

--- Add a pagination row with prev/current/next navigation.
--- opts: { current_page: number, total_pages: number, callback_prefix: string }
function InlineBuilder:pagination_row(opts: table)
    local page = opts.current_page
    local total = opts.total_pages
    local prefix = opts.callback_prefix or "page:"

    if total <= 1 then return self end

    self:row()

    if page > 1 then
        self:callback("« " .. tostring(page - 1), prefix .. tostring(page - 1))
    end

    self:callback("· " .. tostring(page) .. " ·", prefix .. tostring(page))

    if page < total then
        self:callback(tostring(page + 1) .. " »", prefix .. tostring(page + 1))
    end

    return self
end

--- Build the final reply_markup table.
function InlineBuilder:build(): InlineKeyboardMarkup
    return {inline_keyboard = self._rows}
end

-- ── Reply Keyboard Builder ───────────────────────────────

local ReplyBuilder = {}
ReplyBuilder.__index = ReplyBuilder

--- Start a new row of buttons.
function ReplyBuilder:row()
    table.insert(self._rows, {})
    return self
end

--- Add a text button to the current row.
function ReplyBuilder:button(text: string)
    if #self._rows == 0 then self:row() end
    table.insert(self._rows[#self._rows], {text = text})
    return self
end

--- Add a "request contact" button.
function ReplyBuilder:contact(text: string)
    if #self._rows == 0 then self:row() end
    table.insert(self._rows[#self._rows], {text = text, request_contact = true})
    return self
end

--- Add a "request location" button.
function ReplyBuilder:location(text: string)
    if #self._rows == 0 then self:row() end
    table.insert(self._rows[#self._rows], {text = text, request_location = true})
    return self
end

--- Add a "create poll" button.
function ReplyBuilder:poll(text: string, poll_type: string?)
    if #self._rows == 0 then self:row() end
    local btn = {text = text, request_poll = {}}
    if poll_type then btn.request_poll.type = poll_type end
    table.insert(self._rows[#self._rows], btn)
    return self
end

--- Fit keyboard height to the number of buttons.
function ReplyBuilder:resize()
    self._opts.resize_keyboard = true
    return self
end

--- Hide keyboard after a button is pressed.
function ReplyBuilder:one_time()
    self._opts.one_time_keyboard = true
    return self
end

--- Always show the keyboard.
function ReplyBuilder:persistent()
    self._opts.is_persistent = true
    return self
end

--- Show keyboard only to mentioned/replied-to users.
function ReplyBuilder:selective()
    self._opts.selective = true
    return self
end

--- Set input field placeholder text (max 64 chars).
function ReplyBuilder:placeholder(text: string)
    self._opts.input_field_placeholder = text
    return self
end

--- Build the final reply_markup table.
function ReplyBuilder:build(): ReplyKeyboardMarkup
    local markup = {keyboard = self._rows}
    for k, v in pairs(self._opts) do markup[k] = v end
    return markup
end

-- ── Remove Keyboard Builder ──────────────────────────────

local RemoveBuilder = {}
RemoveBuilder.__index = RemoveBuilder

--- Show removal only to mentioned/replied-to users.
function RemoveBuilder:selective()
    self._opts.selective = true
    return self
end

--- Build the final reply_markup table.
function RemoveBuilder:build(): ReplyKeyboardRemove
    local markup = {remove_keyboard = true}
    for k, v in pairs(self._opts) do markup[k] = v end
    return markup
end

-- ── Force Reply Builder ──────────────────────────────────

local ForceReplyBuilder = {}
ForceReplyBuilder.__index = ForceReplyBuilder

--- Set input field placeholder text (max 64 chars).
function ForceReplyBuilder:placeholder(text: string)
    self._opts.input_field_placeholder = text
    return self
end

--- Force reply only for mentioned/replied-to users.
function ForceReplyBuilder:selective()
    self._opts.selective = true
    return self
end

--- Build the final reply_markup table.
function ForceReplyBuilder:build(): ForceReply
    local markup = {force_reply = true}
    for k, v in pairs(self._opts) do markup[k] = v end
    return markup
end

-- ── Public API ───────────────────────────────────────────

--- Create a new inline keyboard builder.
local function inline()
    return setmetatable({_rows = {}}, InlineBuilder)
end

--- Create a new reply keyboard builder.
local function reply()
    return setmetatable({_rows = {}, _opts = {}}, ReplyBuilder)
end

--- Create a keyboard removal builder.
local function remove()
    return setmetatable({_opts = {}}, RemoveBuilder)
end

--- Create a force reply builder.
local function force_reply()
    return setmetatable({_opts = {}}, ForceReplyBuilder)
end

return {
    inline = inline,
    reply = reply,
    remove = remove,
    force_reply = force_reply,
}
