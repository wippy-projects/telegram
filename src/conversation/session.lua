local funcs = require("funcs")
local logger = require("logger")
local time = require("time")

--- Send a text message (with optional reply_markup) to a chat.
local function send_message(chat_id: number, text: string, reply_markup: table?)
    local params = {chat_id = chat_id, text = text}
    if reply_markup then
        params.reply_markup = reply_markup
    end
    local _, err = funcs.call("telegram.sdk:send_message", params)
    if err then
        logger:error("Failed to send message", {chat_id = chat_id, error = tostring(err)})
    end
end

--- Resolve a step's prompt — may be a string or a function(state) -> string.
local function resolve_prompt(step: table, state: table): string
    if type(step.prompt) == "function" then
        return step.prompt(state)
    end
    return step.prompt
end

--- Send the prompt for a given step, including any keyboard markup.
local function send_step_prompt(chat_id: number, step: table, state: table)
    local text = resolve_prompt(step, state)
    send_message(chat_id, text, step.keyboard)
end

--- Find the next applicable step index, skipping conditional steps whose
--- condition evaluates to false. Returns nil if all steps are exhausted.
local function next_step_index(steps: table, current: number, state: table): number?
    local idx = current + 1
    while idx <= #steps do
        local step = steps[idx]
        if step.condition == nil or step.condition(state) then
            return idx
        end
        idx = idx + 1
    end
    return nil
end

--- Find the previous applicable step index (for back navigation).
--- Returns nil if already at the first step.
local function prev_step_index(steps: table, current: number, state: table): number?
    local idx = current - 1
    while idx >= 1 do
        local step = steps[idx]
        if step.condition == nil or step.condition(state) then
            return idx
        end
        idx = idx - 1
    end
    return nil
end

--- Find the first applicable step index.
local function first_step_index(steps: table, state: table): number?
    for i, step in ipairs(steps) do
        if step.condition == nil or step.condition(state) then
            return i
        end
    end
    return nil
end

--- Main session process entry point.
--- Arguments: chat_id (number), flow (table — the flow definition)
local function main(chat_id: number, flow: table)
    local reg_name = "telegram.conversation:" .. tostring(chat_id)

    -- Register in the process name registry so the webhook
    -- dispatcher can find us and forward user messages.
    local ok, reg_err = process.registry.register(reg_name)
    if reg_err then
        logger:error("Failed to register conversation session", {
            chat_id = chat_id,
            error = tostring(reg_err),
        })
        return 1
    end

    local steps = flow.steps
    local state = {}
    local cancel_cmd = flow.cancel_command or "/cancel"
    local back_cmd = flow.back_command or "/back"

    -- Find first applicable step
    local current_step = first_step_index(steps, state)
    if not current_step then
        logger:warn("Flow has no applicable steps", {flow = flow.name})
        process.registry.unregister(reg_name)
        return 0
    end

    -- Send the first step prompt
    send_step_prompt(chat_id, steps[current_step], state)

    local inbox = process.inbox()
    local events = process.events()
    local timeout = time.after(flow.ttl or "10m")

    while true do
        local r = channel.select {
            events:case_receive(),
            inbox:case_receive(),
            timeout:case_receive(),
        }

        -- ── Lifecycle events ────────────────────────────
        if r.channel == events then
            if r.value.kind == process.event.CANCEL then
                logger:info("Conversation session cancelled by system", {chat_id = chat_id})
                process.registry.unregister(reg_name)
                return 0
            end

        -- ── Timeout ─────────────────────────────────────
        elseif r.channel == timeout then
            if flow.on_timeout then
                local msg = flow.on_timeout(chat_id, state, steps[current_step])
                if msg then send_message(chat_id, msg) end
            else
                send_message(chat_id, "⏰ Session expired. Please start again.")
            end
            logger:info("Conversation session timed out", {
                chat_id = chat_id,
                flow = flow.name,
                step = steps[current_step].id,
            })
            process.registry.unregister(reg_name)
            return 0

        -- ── User input ──────────────────────────────────
        elseif r.channel == inbox then
            local msg = r.value
            local topic = msg:topic()
            local payload = msg:payload()

            if topic == "user_input" then
                local input_text = payload.text
                local input_callback = payload.callback_data

                -- Check for cancel command
                if input_text and input_text == cancel_cmd then
                    if flow.on_cancel then
                        local cancel_msg = flow.on_cancel(chat_id, state, steps[current_step])
                        if cancel_msg then send_message(chat_id, cancel_msg) end
                    else
                        send_message(chat_id, "❌ Cancelled.")
                    end
                    process.registry.unregister(reg_name)
                    return 0
                end

                -- Check for back command
                if input_text and input_text == back_cmd then
                    local step = steps[current_step]
                    if step.allow_back then
                        local prev = prev_step_index(steps, current_step, state)
                        if prev then
                            -- Clear the value collected at the step we're going back to
                            state[steps[prev].id] = nil
                            current_step = prev
                            send_step_prompt(chat_id, steps[current_step], state)
                            -- Reset timeout
                            timeout = time.after(flow.ttl or "10m")
                        else
                            send_message(chat_id, "Already at the first step.")
                        end
                    else
                        send_message(chat_id, "Back navigation is not available for this step.")
                    end
                    goto continue
                end

                -- Determine the raw input value based on step's expected input type
                local step = steps[current_step]
                local raw_input
                if step.input_type == "callback_query" then
                    raw_input = input_callback
                else
                    -- Default: text input. For multi-input steps pass
                    -- the entire payload so validate can inspect both.
                    if step.input_types then
                        raw_input = payload
                    else
                        raw_input = input_text
                    end
                end

                if raw_input == nil then
                    -- Wrong input type for this step (e.g. text when expecting callback)
                    send_message(chat_id, "⚠️ Please use the expected input method for this step.")
                    goto continue
                end

                -- Validate
                local value, val_err
                if step.validate then
                    value, val_err = step.validate(raw_input)
                else
                    -- No validation — accept as-is
                    value = raw_input
                end

                if val_err then
                    send_message(chat_id, "⚠️ " .. val_err)
                    goto continue
                end

                -- Store validated value
                state[step.id] = value

                -- Advance to next step
                local next_idx = next_step_index(steps, current_step, state)

                if not next_idx then
                    -- All steps completed
                    local result_msg
                    if flow.on_complete then
                        result_msg = flow.on_complete(chat_id, state)
                    end
                    if result_msg then
                        send_message(chat_id, result_msg)
                    end
                    logger:info("Conversation completed", {
                        chat_id = chat_id,
                        flow = flow.name,
                    })
                    process.registry.unregister(reg_name)
                    return 0
                end

                current_step = next_idx

                -- Reset timeout on progress
                timeout = time.after(flow.ttl or "10m")

                -- Send next step prompt
                send_step_prompt(chat_id, steps[current_step], state)
            end

            ::continue::
        end
    end
end

return { main = main }
