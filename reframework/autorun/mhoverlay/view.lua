local View = {}
local Icons = require("mhoverlay/icons")
local Locale = require("mhoverlay/locale")

local function translate(settings, key, ...)
    return Locale.t(key, settings.language, ...)
end

local colors = {
    text = 0xFFF2F2F2,
    muted = 0xFFB8B8B8,
    bar_background = 0xFF39332F,
    health = 0xFF69BE88,
    warning = 0xFF55BBFF,
    rage = 0xFF5985F0,
    stamina = 0xFF70CDE8,
}

local function text(draw_api, value, x, y, color)
    draw_api.text(value, x + 1, y + 1, 0xFF000000)
    draw_api.text(value, x, y, color)
end

local function short_name(name, limit)
    name = name:gsub("[%c]", " ")
    local length = utf8.len(name)
    if not length then error("Nombre con UTF-8 invalido", 0) end
    if length <= limit then return name end
    return name:sub(1, utf8.offset(name, limit - 2) - 1) .. "..."
end

local function draw_health(draw_api, x, y, width, height, ratio, alpha)
    local lines = math.max(1, math.ceil(height))
    for line = 0, lines - 1 do
        local t = line / math.max(1, lines - 1)
        local inset = math.abs(t - 0.5) * math.min(12, width / 12)
        draw_api.filled_rect(x + inset, y + line, width - inset * 2,
            math.min(1, height - line), (alpha << 24) | 0x504A42)
        local fill = math.max(0, width * ratio - inset * 2)
        for segment = 0, 15 do
            local left = width * segment / 16
            local size = math.min(width / 16, fill - left)
            if size > 0 then
                local mix = segment / 15
                local color = 0xFF000000 | (math.floor(245 - 30 * mix) << 16)
                    | (math.floor(150 + 45 * mix) << 8) | math.floor(65 - 60 * mix)
                draw_api.filled_rect(x + inset + left, y + line, size,
                    math.min(1, height - line), color)
            end
        end
    end
    for step = 1, 9 do
        local left = width * step / 10
        if left + height * 0.5 < width * ratio then
            for line = 1, math.max(0, lines - 2) do
                draw_api.filled_rect(x + left + line * 0.4, y + line,
                    math.min(1, height), math.min(1, height - line), 0x66403B28)
            end
        end
    end
end

local function draw_crest(draw_api, x, y, scale, alpha)
    local function block(dx, dy, w, h, color)
        draw_api.filled_rect(x + dx * scale, y + dy * scale, w * scale, h * scale, color)
    end
    local function stroke(x1, y1, x2, y2, color)
        local steps = math.ceil(math.max(math.abs(x2 - x1), math.abs(y2 - y1)))
        for step = 0, steps do
            local t = steps == 0 and 0 or step / steps
            block(x1 + (x2 - x1) * t, y1 + (y2 - y1) * t, 2, 2, color)
        end
    end
    for line = 0, 65 do
        local half = 33 - math.abs(line - 32.5)
        block(33 - half, line, half * 2, 1, (alpha << 24) | 0x272624)
    end
    for _, side in ipairs({ -1, 1 }) do
        stroke(33 + side * 7, 37, 33 + side * 19, 17, 0xFFF29D49)
        stroke(33 + side * 19, 17, 33 + side * 21, 6, colors.text)
        stroke(33 + side * 7, 37, 33 + side * 14, 47, colors.text)
        stroke(33 + side * 14, 47, 33, 56, 0xFFF29D49)
    end
    block(28, 25, 12, 18, colors.muted)
    block(27, 29, 4, 4, (alpha << 24) | 0x171717)
    block(37, 29, 4, 4, (alpha << 24) | 0x171717)
    stroke(33, 41, 33, 52, 0xFFD7C600)
end

function View.timer(seconds)
    local whole = math.ceil(math.max(0, seconds))
    return string.format("%d:%02d", math.floor(whole / 60), whole % 60)
end

function View.detail_lines(row, settings)
    local lines = {}
    if settings.show_parts and row.parts then
        lines[#lines + 1] = translate(settings, "Roturas completas: %d / %d%s",
            row.parts.broken, row.parts.total, (row.parts.invalid or 0) > 0
                and translate(settings, " (parcial)") or "")
        if (row.parts.invalid or 0) > 0 then
            lines[#lines + 1] = translate(settings, "Partes no leidas: %d", row.parts.invalid)
        end
        if settings.parts_details then
            local shown = math.min(#row.parts.entries, settings.max_parts)
            for index = 1, shown do
                local part = row.parts.entries[index]
                lines[#lines + 1] = translate(settings, "Parte #%d: %s", part.index,
                    translate(settings, part.broken and "completa" or "pendiente"))
            end
            if #row.parts.entries > shown then
                lines[#lines + 1] = translate(settings, "+ %d partes sin mostrar",
                    #row.parts.entries - shown)
            end
        end
    end
    if settings.show_wounds and row.wounds then
        lines[#lines + 1] = translate(settings, "Heridas: estados SDK")
        local labels = {}
        for label in pairs(row.wounds.states) do labels[#labels + 1] = label end
        table.sort(labels)
        for index = 1, math.min(#labels, 8) do
            local label = labels[index]
            lines[#lines + 1] = label .. ": " .. row.wounds.states[label]
        end
        if #labels > 8 then
            lines[#lines + 1] = translate(settings, "+ %d estados sin mostrar", #labels - 8)
        elseif #labels == 0 then
            lines[#lines + 1] = translate(settings, "Sin entradas de heridas")
        end
    end
    return lines
end

local function has_badges(row, settings)
    return (settings.show_parts and row.parts) or (settings.show_wounds and row.wounds)
end

local function row_height(row, settings)
    return (settings.compact and 66 or 88)
        + (settings.show_rage and row.rage and 28 or 0)
        + (settings.show_stamina and row.stamina and 28 or 0)
        + (has_badges(row, settings) and 44 or 0)
end

function View.badges(row, settings)
    local parts = settings.show_parts and row.parts
    local wounds = settings.show_wounds and row.wounds
    local result = {
        { kind = "parts", count = parts and ((parts.invalid or 0) > 0
                and (parts.total > 0 and (parts.broken .. "/" .. parts.total .. "?") or "--?")
                or (parts.broken .. "/" .. parts.total)) or "--",
            color = colors.muted },
    }
    for _, state in ipairs({
        { "NORMAL", colors.health }, { "TEAR", colors.stamina }, { "RAW", colors.rage },
    }) do
        result[#result + 1] = { kind = state[1],
            count = wounds and tostring(wounds.states[state[1]] or 0) or "--", color = state[2] }
    end
    return result
end

local function draw_badges(draw_api, row, settings, x, y, width, scale)
    local cell = (width - 24 * scale) / 4
    for index, badge in ipairs(View.badges(row, settings)) do
        local bx = x + 12 * scale + (index - 1) * cell
        Icons.draw(draw_api, badge.kind, bx, y, 14 * scale,
            badge.count == "--" and colors.muted or badge.color, badge.count == "--")
        text(draw_api, badge.count, bx, y + 16 * scale, badge.color)
    end
end

local function draw_condition(draw_api, state, label, active_label, color, x, y, width, scale)
    local value
    if state.active then
        value = active_label .. "  " .. View.timer(state.remaining)
    else
        value = string.format("%s: %.0f / %.0f", label, state.current, state.maximum)
    end
    text(draw_api, value, x + 12 * scale, y, color)
    draw_api.filled_rect(x + 12 * scale, y + 21 * scale,
        width - 24 * scale, 4 * scale, colors.bar_background)
    draw_api.filled_rect(x + 12 * scale, y + 21 * scale,
        (width - 24 * scale) * state.ratio, 4 * scale, color)
end

function View.layout(settings, rows, display, has_status)
    local scale = settings.scale * settings.monsters_size / 100
    local gap = 8 * scale
    local width = math.min(settings.width * scale, display.x)
    local status_height = has_status and 38 * scale or 0
    local panels = {}
    local next_x, next_y, line_height, extent_x, extent_y = 0, 0, 0, 0, 0
    for _, row in ipairs(rows) do
        local height = row_height(row, settings) * scale
        if settings.horizontal and next_x > 0 and next_x + width > display.x then
            next_x = 0
            next_y = next_y + line_height + gap
            line_height = 0
        end
        if next_y + height + status_height > display.y then
            break
        end
        panels[#panels + 1] = { row = row, x = next_x, y = next_y, height = height }
        extent_x = math.max(extent_x, next_x + width)
        extent_y = math.max(extent_y, next_y + height)
        if settings.horizontal then
            next_x = next_x + width + gap
            line_height = math.max(line_height, height)
        else
            next_y = next_y + height + gap
        end
    end
    local status_y = #panels > 0 and extent_y + gap or 0
    local total_height = has_status and status_y + 30 * scale or extent_y
    local total_width = math.max(extent_x, has_status and width or 0)
    return {
        panels = panels, width = width, status_y = status_y,
        x = math.max(0, math.min(settings.x, display.x - total_width)),
        y = math.max(0, math.min(settings.y, display.y - total_height)),
    }
end

function View.render(draw_api, imgui_api, settings, rows, status, preview)
    if not settings.enabled then
        return
    end
    local scale = settings.scale * settings.monsters_size / 100
    local display = imgui_api.get_display_size()
    if display.x <= 0 or display.y <= 0 then
        return
    end
    local layout = View.layout(settings, rows, display, status ~= nil)
    local width = layout.width
    local background = (math.floor((settings.opacity or 85) * 255 / 100 + 0.5) << 24) | 0x221B18

    local scalable_font = imgui_api.push_font_size ~= nil and imgui_api.pop_font_size ~= nil
    if scalable_font then
        imgui_api.push_font_size(18 * scale)
    end
    local nested_font = false
    local ok, err = pcall(function()
        for _, panel in ipairs(layout.panels) do
            local row = panel.row
            local x, y = layout.x + panel.x, layout.y + panel.y
            draw_api.filled_rect(x, y, width, panel.height, background)
            local name = (row.quest_target and "[M] " or "")
                .. (settings.show_pin and row.pinned and "[*] " or "") .. row.name
            local function fitted(value, available)
                value = short_name(value, 100)
                local function measure(label)
                    if imgui_api.calc_text_size then return imgui_api.calc_text_size(label).x end
                    return utf8.len(label) * 9 * (scalable_font and scale or 1)
                end
                local length = utf8.len(value)
                while measure(value) > available and length > 3 do
                    length = length - 1
                    value = short_name(value, length)
                end
                return value
            end
            local hp_left = settings.show_monster_icons and 80 or 12
            local title_left = settings.show_monster_icons and 80 or 48
            if settings.show_monster_icons then
                Icons.monster(draw_api, row.portrait, x + 8 * scale, y + 8 * scale,
                    (settings.compact and 48 or 64) * scale)
            else
                draw_crest(draw_api, x + 8 * scale, y + 6 * scale, 0.36 * scale,
                    background >> 24)
            end
            text(draw_api, fitted(name, width - (title_left + 10) * scale),
                x + title_left * scale, y + 8 * scale,
                (row.quest_target or row.pinned) and colors.warning or colors.text)
            local label = string.format("%.0f / %.0f HP  (%.1f%%)",
                row.health, row.max_health, row.ratio * 100)
            text(draw_api, fitted(label, width - (hp_left + 12) * scale),
                x + hp_left * scale, y + 33 * scale, colors.muted)
            local bar_y = y + (settings.compact and 55 or 62) * scale
            local bar_height = (settings.compact and 5 or 12) * scale
            draw_health(draw_api, x + hp_left * scale, bar_y, width - (hp_left + 12) * scale,
                bar_height, row.ratio, background >> 24)
            local extra_y = y + ((settings.compact and 66 or 88) - 6) * scale
            local states_height = ((settings.show_rage and row.rage and 28 or 0)
                + (settings.show_stamina and row.stamina and 28 or 0)) * scale
            if states_height >= 56 * scale then
                draw_api.filled_rect(x + 12 * scale, extra_y,
                    width - 24 * scale, 3 * scale, colors.bar_background)
                draw_api.filled_rect(x + 12 * scale, extra_y,
                    (width - 24 * scale) * row.stamina.ratio, 3 * scale, colors.stamina)
                if scalable_font then
                    imgui_api.push_font_size(12 * scale)
                    nested_font = true
                end
                local font_scale = scalable_font and scale or 1
                local function centered(value, cx, cy, color)
                    local function measure(label)
                        return imgui_api.calc_text_size and imgui_api.calc_text_size(label).x
                            or utf8.len(label) * (scalable_font and 6 or 9) * font_scale
                    end
                    local available = (width - 24 * scale) / 3 - 4 * scale
                    local length = utf8.len(value)
                    while measure(value) > available and length > 3 do
                        length = length - 1
                        value = short_name(value, length)
                    end
                    if measure(value) > available then return end
                    local measured = measure(value)
                    text(draw_api, value, cx - measured / 2, cy, color)
                end
                for index, entry in ipairs({
                    { "Furia", row.rage, colors.rage, "rage" },
                    { "Paralisis", row.paralysis, 0xFFD7C600, "paralysis" },
                    { "Aturdim.", row.stun, 0xFFF29D49, "stun" },
                }) do
                    local cx = x + 12 * scale + (index - 0.5) * (width - 24 * scale) / 3
                    local cy = extra_y + 34 * scale
                    local state = entry[2]
                    for step = 0, 47 do
                        local angle = step / 48 * math.pi * 2 - math.pi / 2
                        draw_api.filled_rect(cx + math.cos(angle) * 17 * scale - scale,
                            cy + math.sin(angle) * 17 * scale - scale, 2 * scale, 2 * scale,
                            state and step / 48 < state.ratio and entry[3]
                                or ((background >> 24) << 24) | 0x48443C)
                    end
                    Icons.draw(draw_api, entry[4], cx - 31 * scale, cy - 6 * scale,
                        12 * scale, state and entry[3] or colors.muted, not state)
                    centered(translate(settings, entry[1]), cx, extra_y + 5 * scale, colors.muted)
                    centered(state and ("+" .. (state.observed_count or 0)) or "--",
                        cx, extra_y + 20 * scale, colors.text)
                    centered(state and (state.active and View.timer(state.remaining) or "0:00") or "--:--",
                        cx, extra_y + 34 * scale, colors.muted)
                end
                if scalable_font then
                    imgui_api.pop_font_size()
                    nested_font = false
                end
                extra_y = extra_y + states_height
            else
                if settings.show_rage and row.rage then
                    draw_condition(draw_api, row.rage, translate(settings, "Furia"), translate(settings, "ENFURECIDO"),
                        colors.rage, x, extra_y, width, scale)
                    extra_y = extra_y + 28 * scale
                end
                if settings.show_stamina and row.stamina then
                    draw_condition(draw_api, row.stamina, translate(settings, "Resistencia"), translate(settings, "AGOTADO"),
                        colors.stamina, x, extra_y, width, scale)
                    extra_y = extra_y + 28 * scale
                end
            end
            if has_badges(row, settings) then
                draw_badges(draw_api, row, settings, x, extra_y + 3 * scale, width, scale)
            end
        end
        if status then
            local x, y = layout.x, layout.y + layout.status_y
            draw_api.filled_rect(x, y, width, 30 * scale, background)
            text(draw_api, status, x + 8 * scale, y + 5 * scale,
                preview and colors.warning or colors.muted)
        end
    end)
    if nested_font then imgui_api.pop_font_size() end
    if scalable_font then
        imgui_api.pop_font_size()
    end
    if not ok then
        error(err, 0)
    end
end

function View.damage_number(value)
    if value >= 1000000 then return string.format("%.1fM", value / 1000000) end
    if value >= 10000 then return string.format("%.1fk", value / 1000) end
    return string.format("%.0f", value)
end

local player_colors = { 0xFFE084BA, 0xFFDBCC63, 0xFF82B8EA, 0xFF8BCD87 }

function View.damage_dps(value, language)
    if value and value >= 10000 then
        return View.damage_total(value, language) .. "/s"
    end
    return value and Locale.decimal(string.format("%.1f/s", value), language or "es") or "--/s"
end

function View.damage_total(value, language)
    if value >= 1000 and value < 1000000 then
        return Locale.decimal(string.format("%.1fK", value / 1000), language or "es")
    end
    return Locale.decimal(View.damage_number(value):gsub("k", "K"), language or "es")
end

function View.damage_timer(seconds)
    local whole = math.floor(math.max(0, seconds))
    return string.format("%02d:%02d:%02d", math.floor(whole / 3600),
        math.floor(whole / 60) % 60, whole % 60)
end

function View.render_focus(draw_api, imgui_api, settings, row, preview, status)
    if not settings.enabled or not row then return end
    local display = imgui_api.get_display_size()
    local scalable = imgui_api.push_font_size and imgui_api.pop_font_size
    local scale = math.min(settings.scale * settings.focus_size / 100, display.x / 420,
        (display.y - (scalable and 0 or 20)) / 240)
    if scale <= 0 or display.x < 210 or display.y < 118 then return end
    local width = math.min(settings.focus_width * scale, display.x)
    local height = 240 * scale + (scalable and 0 or 20)
    local x = math.max(0, math.min(settings.focus_x, display.x - width))
    local y = math.max(0, math.min(settings.focus_y, display.y - height))
    local alpha = math.floor(settings.opacity * 255 / 100 + 0.5)
    local blue, cyan = 0xFFF29D49, 0xFFD7C600
    local function block(dx, dy, w, h, color)
        draw_api.filled_rect(x + dx * scale, y + dy * scale, w * scale, h * scale, color)
    end
    local logical_width = width / scale
    local function dark(rgb) return (alpha << 24) | rgb end
    if scalable then imgui_api.push_font_size(18 * scale) end
    local ok, err = pcall(function()
        local function measure(value)
            if imgui_api.calc_text_size then return imgui_api.calc_text_size(value).x / scale end
            local units = 0
            for _, code in utf8.codes(value) do units = units + (code < 128 and 1 or 2) end
            return units * 9 * (scalable and 1 or 1 / scale)
        end
        local function fitted(value, available)
            value = short_name(value, 100)
            local length = utf8.len(value)
            while measure(value) > available and length > 3 do
                length = length - 1
                value = short_name(value, length)
            end
            return value
        end
        local function label(value, dx, dy, color)
            text(draw_api, value, x + dx * scale, y + dy * scale, color or colors.text)
        end
        local function centered(value, cx, cy, color)
            value = fitted(value, logical_width - 8)
            label(value, math.max(4, math.min(cx - measure(value) / 2,
                logical_width - measure(value) - 4)), cy, color)
        end
        local bar_x, bar_end = 76, logical_width - 18
        local bar_width = bar_end - bar_x
        if preview then
            local tag = translate(settings, "DEMO - COMBATE")
            block(bar_x, 0, math.min(measure(tag) + 16, bar_width), 24, dark(0x252320))
            label(fitted(tag, bar_width - 16), bar_x + 8, 2, colors.muted)
        end
        label(fitted(row.name, bar_width), bar_x, 27)
        local percent = Locale.decimal(string.format("%.2f%%", row.ratio * 100), settings.language)
        local hp = string.format("%.0f / %.0f", row.health, row.max_health)
        label(fitted(hp, bar_width - measure(percent) - 16), bar_x, 49, colors.muted)
        label(percent, bar_end - measure(percent), 49)
        draw_health(draw_api, x + bar_x * scale, y + 73 * scale,
            bar_width * scale, 28 * scale, row.ratio, alpha)
        if settings.show_monster_icons then
            Icons.monster(draw_api, row.portrait, x + 5 * scale, y + 53 * scale, 66 * scale)
        else
            draw_crest(draw_api, x + 5 * scale, y + 53 * scale, scale, alpha)
        end
        if settings.show_stamina then
            block(bar_x, 105, bar_width, 3, dark(0x39332F))
            if row.stamina then block(bar_x, 105, bar_width * row.stamina.ratio, 3, colors.stamina) end
        end
        local badge_row = { parts = settings.show_parts and row.parts,
            wounds = settings.show_wounds and row.wounds }
        if settings.show_parts or settings.show_wounds then
            draw_badges(draw_api, badge_row, settings, x + bar_x * scale,
                y + 116 * scale, math.min(440, logical_width - bar_x) * scale, scale)
        end
        local states = {
            { label = "Furia", state = settings.show_rage and row.rage, color = colors.rage, icon = "rage" },
            { label = "Paralisis", state = row.paralysis, color = cyan, icon = "paralysis" },
            { label = "Aturdim.", state = row.stun, color = blue, icon = "stun" },
        }
        local spacing = math.min(150, (logical_width - 16) / 3)
        for index, entry in ipairs(states) do
            local cx, cy = 38 + (index - 1) * spacing, 195
            local state = entry.state
            local ratio = state and state.ratio or 0
            for step = 0, 63 do
                local angle = (step / 64) * math.pi * 2 - math.pi / 2
                local color = step / 64 < ratio
                    and (state.active and entry.color or blue) or dark(0x48443C)
                block(cx + math.cos(angle) * 26 - 1, cy + math.sin(angle) * 26 - 1, 3, 3, color)
            end
            Icons.draw(draw_api, entry.icon, x + (cx + 32) * scale, y + (cy - 9) * scale,
                18 * scale, state and entry.color or colors.muted, not state)
            centered(translate(settings, entry.label), cx, 148, colors.muted)
            centered(state and ("+" .. (state.observed_count or 0)) or "--", cx, 174,
                state and state.active and entry.color or colors.text)
            centered(state and (state.active and View.timer(state.remaining) or "0:00") or "--:--",
                cx, 195, colors.muted)
        end
        if status then label(fitted(status, logical_width - 20), 10, 219, colors.muted) end
    end)
    if scalable then imgui_api.pop_font_size() end
    if not ok then error(err, 0) end
end

local function draw_skull(draw_api, x, y, scale, color)
    for row, pixels in ipairs({
        "0111110", "1111111", "1001001", "1001001",
        "1111111", "0110110", "0111110", "0101010",
    }) do
        for start, run in pixels:gmatch("()(1+)") do
            draw_api.filled_rect(x + (start - 1) * 2 * scale,
                y + (row - 1) * 2 * scale, #run * 2 * scale, 2 * scale, color)
        end
    end
end

function View.render_damage(draw_api, imgui_api, settings, damage, status, preview, retained)
    if not settings.enabled or not settings.show_dps then return end
    if not preview and not damage.active and not status and not retained then return end
    local display = imgui_api.get_display_size()
    local scale = settings.scale * settings.dps_size / 100
    if display.x < 300 * scale or display.y < 86 * scale then return end
    local rows, total = damage:rows()
    local combat_elapsed = 0
    for _, row in ipairs(rows) do combat_elapsed = math.max(combat_elapsed, row.elapsed or 0) end
    if not damage.session and not status then status = translate(settings, "Esperando una mision") end
    if #rows == 0 and not status then status = translate(settings, "Esperando impactos de cazadores") end
    if status then rows, total = {}, 0 end
    local count = math.min(#rows, math.floor((display.y / scale - 62) / 58))
    local width = math.min(settings.dps_width * scale, display.x)
    local height = (status and 86 or (62 + count * 58)) * scale
    local x = math.max(0, math.min(settings.dps_x, display.x - width))
    local y = math.max(0, math.min(settings.dps_y, display.y - height))
    local alpha = math.floor(settings.opacity * 255 / 100 + 0.5)
    local background = (alpha << 24) | 0x242322
    local scalable = imgui_api.push_font_size and imgui_api.pop_font_size
    if scalable then imgui_api.push_font_size(16 * scale) end
    local ok, err = pcall(function()
        local function measure(value)
            if imgui_api.calc_text_size then return imgui_api.calc_text_size(value).x end
            local units = 0
            for _, code in utf8.codes(value) do units = units + (code < 128 and 1 or 2) end
            return units * 9 * (scalable and scale or 1)
        end
        local function fitted(value, available)
            value = short_name(value, 100)
            local length = utf8.len(value)
            while measure(value) > available and length > 3 do
                length = length - 1
                value = short_name(value, length)
            end
            return value
        end
        local function right(value, edge, ry, color)
            text(draw_api, value, edge - measure(value), ry, color)
        end
        draw_api.filled_rect(x, y, width, height, background)
        text(draw_api, View.damage_timer(combat_elapsed),
            x + 12 * scale, y + 9 * scale, colors.text)
        local state = translate(settings, preview and "DEMO"
            or (not damage.session and "SIN MISION"
                or (damage.active and "DPS / COMB." or "ULTIMA CAZA")))
        local faints = damage.faints
        local faint_text = faints and (tostring(faints.count) .. "/"
            .. (faints.limit > 0 and tostring(faints.limit) or "--")) or "--/--"
        local faint_color = faints and faints.count > 0 and colors.warning or colors.muted
        if faints and faints.limit > 0 and faints.count >= faints.limit - 1 then
            faint_color = colors.rage
        end
        local counter_x = x + width - 10 * scale - measure(faint_text)
        text(draw_api, faint_text, counter_x, y + 9 * scale, faint_color)
        draw_skull(draw_api, counter_x - 22 * scale, y + 10 * scale, scale,
            (alpha << 24) | (faint_color & 0xFFFFFF))
        local state_left = x + 24 * scale + measure(View.damage_timer(combat_elapsed))
        local state_right = counter_x - 34 * scale
        if state_right - state_left >= measure("...") then
            right(fitted(state, state_right - state_left), state_right, y + 9 * scale,
                preview and colors.warning or colors.muted)
        end
        draw_api.filled_rect(x, y + 37 * scale, width, scale,
            (alpha << 24) | 0x525150)
        if status then
            text(draw_api, fitted(status, width - 24 * scale),
                x + 12 * scale, y + 51 * scale, colors.muted)
        end
        for index = 1, count do
            local row = rows[index]
            local ry = y + (38 + (index - 1) * 58) * scale
            local color_key = 0
            for byte = 1, #row.id do color_key = color_key + row.id:byte(byte) end
            local color = player_colors[color_key % #player_colors + 1]
            draw_api.filled_rect(x, ry, width * row.ratio, 57 * scale,
                (math.floor(alpha * 0.24) << 24) | (color & 0xFFFFFF))
            draw_api.filled_rect(x, ry, 3 * scale, 57 * scale,
                (alpha << 24) | (color & 0xFFFFFF))
            text(draw_api, tostring(index), x + 12 * scale, ry + 18 * scale, color)
            local label = translate(settings, row.is_support and "[APOYO] " or (row.is_self and "[TU] " or "")) .. row.name
            text(draw_api, fitted(label, width - 236 * scale),
                x + 38 * scale, ry + 7 * scale, colors.text)
            text(draw_api, fitted(row.elapsed and View.damage_timer(row.elapsed) or "--",
                width - 236 * scale),
                x + 38 * scale, ry + 31 * scale, row.in_combat and colors.text or colors.muted)
            right(row.damage_available == false and "--"
                or Locale.decimal(string.format("%.2f%%", row.share * 100), settings.language),
                x + width - 122 * scale, ry + 18 * scale, colors.text)
            text(draw_api, "DPS", x + width - 113 * scale, ry + 7 * scale, colors.muted)
            right(View.damage_dps(row.damage_available ~= false and row.dps or nil, settings.language),
                x + width - 8 * scale, ry + 7 * scale, colors.text)
            text(draw_api, "DMG", x + width - 113 * scale, ry + 31 * scale, colors.muted)
            right(row.damage_available == false and "--" or View.damage_total(row.damage, settings.language),
                x + width - 8 * scale, ry + 31 * scale, color)
            draw_api.filled_rect(x, ry + 57 * scale, width, scale,
                (math.floor(alpha * 0.5) << 24) | 0x525150)
        end
        if not status then
            local group_dps = 0
            for _, row in ipairs(rows) do
                if row.damage_available ~= false then
                    if not row.dps then group_dps = nil; break end
                    group_dps = group_dps + row.dps
                end
            end
            local footer = count < #rows and translate(settings, "+ %d sin mostrar", #rows - count)
                or translate(settings, "Grupo: %s | %s", View.damage_total(total, settings.language),
                    View.damage_dps(group_dps, settings.language))
            text(draw_api, fitted(footer, width - 24 * scale),
                x + 12 * scale, y + height - 21 * scale, colors.muted)
        end
    end)
    if scalable then imgui_api.pop_font_size() end
    if not ok then error(err, 0) end
end

function View.activity_rows(snapshot, settings)
    local rows = {}
    if settings.activities_collection then
        rows[#rows + 1] = { heading = translate(settings, "RECOLECCION DE MATERIALES") }
        local collection = snapshot.collection
        if not collection then
            rows[#rows + 1] = { name = translate(settings, "Materiales"),
                detail = translate(settings, "-- | Ver Diagnostico"), icon = "collection" }
        elseif #collection.collectors == 0 then
            rows[#rows + 1] = { name = translate(settings, "Materiales"),
                detail = translate(settings, "Sin recogidas disponibles"), icon = "collection" }
        else
            for _, npc in ipairs(collection.collectors) do
                rows[#rows + 1] = { name = npc.name, icon = "collection",
                    slots = { occupied = npc.occupied, capacity = npc.capacity },
                    closed = not npc.available,
                    ready = npc.count > 0, full = npc.full,
                }
            end
        end
    end
    if settings.activities_ship then
        local ship = snapshot.ship
        rows[#rows + 1] = { name = translate(settings, "Barco de suministros"), icon = "ship",
            detail = not ship and translate(settings, "-- | Ver Diagnostico")
                or (not ship.opened and translate(settings, "No desbloqueado")
                    or translate(settings, "%s | Dias del ciclo: %d", translate(settings, ship.in_port and "EN PUERTO" or "En viaje"),
                        ship.days)),
            ready = ship and ship.in_port }
    end
    if settings.activities_rations then
        local rations = snapshot.rations
        rows[#rows + 1] = { name = translate(settings, "Raciones"), icon = "rations",
            detail = not rations and translate(settings, "-- | Ver Diagnostico") or nil,
            slots = rations and { occupied = rations.count, capacity = rations.capacity } or nil,
            slot_icon = "rations",
            ready = rations and rations.count > 0, full = rations and rations.full }
    end
    return rows
end

function View.render_mission_preview(draw_api, imgui_api, settings, snapshot)
    if not settings.enabled or not settings.show_mission_preview or not snapshot then return end
    local players = snapshot.players or {}
    local targets = snapshot.targets or {}
    local logical_height = (#targets > 0 and 136 or 117) + #players * 27 + #targets * 21
        + (snapshot.roster_status and 21 or 0)
        + (snapshot.target_status and 21 or 0)
    local display = imgui_api.get_display_size()
    if display.x < 240 or display.y < 120 then return end
    local scale = math.min(settings.scale * settings.mission_size / 100,
        display.x / settings.mission_width, display.y / logical_height)
    if scale <= 0 then return end
    local scalable = imgui_api.push_font_size and imgui_api.pop_font_size
    local vertical_scale = scalable and scale or math.max(1, scale)
    if logical_height * vertical_scale > display.y then
        error("Vista previa: no cabe la fuente fija de REFramework en la altura disponible", 0)
    end
    local width, height = math.min(settings.mission_width * scale, display.x),
        logical_height * vertical_scale
    local x = math.max(0, math.min(settings.mission_x, display.x - width))
    local y = math.max(0, math.min(settings.mission_y, display.y - height))
    local alpha = math.floor(settings.opacity * 255 / 100 + 0.5)
    if scalable then imgui_api.push_font_size(15 * scale) end
    local ok, err = pcall(function()
        local function block(dx, dy, w, h, color)
            draw_api.filled_rect(x + dx * scale, y + dy * vertical_scale,
                w * scale, h * vertical_scale, color)
        end
        local function label(value, dx, dy, color)
            value = short_name(value, 96)
            local function measure()
                if imgui_api.calc_text_size then return imgui_api.calc_text_size(value).x / scale end
                return utf8.len(value) * 9 / scale
            end
            local length = utf8.len(value)
            local available = width / scale - dx - 12
            while measure() > available and length > 3 do
                length = length - 1
                value = short_name(value, length)
            end
            draw_api.text(value, x + dx * scale + 1, y + dy * vertical_scale + 1, 0xFF000000)
            draw_api.text(value, x + dx * scale, y + dy * vertical_scale, color or colors.text)
        end
        local background = (alpha << 24) | 0x201E1B
        block(0, 0, width / scale, logical_height, background)
        block(0, 0, width / scale, 49, (alpha << 24) | 0x51402B)
        label(translate(settings, "MISION SELECCIONADA"), 12, 4, colors.text)
        local count = translate(settings, "%s/%s cazadores",
            snapshot.member_count and tostring(snapshot.member_count) or "--",
            snapshot.member_max and tostring(snapshot.member_max) or "--")
        label(count, 12, 24, colors.muted)
        local line = 57
        if #targets > 0 then
            label(translate(settings, "OBJETIVO"), 12, line, colors.warning)
            line = line + 19
            for _, target in ipairs(targets) do
                label(target, 16, line)
                line = line + 21
            end
        end
        if snapshot.target_status then
            label(translate(settings, snapshot.target_status), 12, line, colors.warning)
            line = line + 21
        end
        label(translate(settings, "CAZADORES"), 12, line, colors.warning)
        line = line + 19
        for index, player in ipairs(players) do
            local host = player.host and translate(settings, "  ANFITRION") or ""
            label(translate(settings, "%d. %s  |  RC %s%s", index, player.name,
                player.rank ~= nil and tostring(player.rank) or "--", host),
                16, line)
            line = line + 27
        end
        if snapshot.roster_status then
            label(snapshot.roster_count and translate(settings, "Datos de cazadores incompletos: %d/%s nombres",
                snapshot.roster_count, snapshot.member_count and tostring(snapshot.member_count) or "--")
                or snapshot.roster_status, 12, line, colors.warning)
            line = line + 21
        end
        label(translate(settings, "Limite: %s desmayos  |  Tiempo: %s",
            snapshot.quest_life and tostring(snapshot.quest_life) or "--",
            snapshot.time_limit and View.timer(snapshot.time_limit) or "--"), 12, line, colors.muted)
        line = line + 20
        label(translate(settings, "HP y desmayos actuales: al entrar a la mision"), 12, line, colors.muted)
    end)
    if scalable then imgui_api.pop_font_size() end
    if not ok then error(err, 0) end
end

local function activity_height(row, width, scale)
    if row.heading then return 25 end
    if row.slots then
        local per_line = math.max(1, math.floor((width / scale - 32 + 3) / 17))
        return math.max(60, 33 + math.ceil(row.slots.capacity / per_line) * 17)
            + (row.closed and row.slots.capacity > 0 and 20 or 0), per_line
    end
    return 60
end

function View.render_activities(draw_api, imgui_api, settings, snapshot, preview)
    if not settings.enabled or not settings.show_activities or not snapshot then return end
    local rows = View.activity_rows(snapshot, settings)
    if #rows == 0 then return end
    local scale = settings.scale * settings.activities_size / 100
    local display = imgui_api.get_display_size()
    if display.x < 300 * scale or display.y < 126 * scale then return end
    local width = math.min(display.x, settings.activities_width * scale)
    local height, count = 41, #rows
    for _, row in ipairs(rows) do height = height + activity_height(row, width, scale) end
    local omitted = 0
    if height * scale > display.y then
        height = height + 24
        while height * scale > display.y and count > 0 do
            height = height - activity_height(rows[count], width, scale)
            if not rows[count].heading then omitted = omitted + 1 end
            count = count - 1
        end
    end
    height = height * scale
    local x = math.max(0, math.min(settings.activities_x, display.x - width))
    local y = math.max(0, math.min(settings.activities_y, display.y - height))
    local alpha = math.floor(255 * settings.opacity / 100)
    local scalable = imgui_api.push_font_size and imgui_api.pop_font_size
    local font_size = scalable and 14 * scale or 14
    local function measure(label)
        if imgui_api.calc_text_size then return imgui_api.calc_text_size(label).x end
        local units = 0
        for _, code in utf8.codes(label) do units = units + (code < 128 and 1 or 2) end
        return units * font_size * 0.7
    end
    local function fitted(value, available)
        value = short_name(value, 160)
        local length = utf8.len(value)
        while measure(value) > (available or width - 32 * scale) and length > 3 do
            length = length - 1
            value = short_name(value, length)
        end
        return value
    end
    if scalable then imgui_api.push_font_size(font_size) end
    local ok, err = pcall(function()
        draw_api.filled_rect(x, y, width, height, (alpha << 24) | 0x201C18)
        draw_api.filled_rect(x, y, width, 3 * scale, 0xFFF29D49)
        text(draw_api, fitted(translate(settings, preview and "ACTIVIDADES - DEMO" or "ACTIVIDADES DEL POBLADO")),
            x + 12 * scale, y + 10 * scale, colors.text)
        local ry = y + 36 * scale
        for index = 1, count do
            local row = rows[index]
            if row.heading then
                text(draw_api, fitted(row.heading), x + 12 * scale, ry + 3 * scale, colors.muted)
                ry = ry + 25 * scale
            else
                local color = row.full and colors.health or (row.ready and colors.warning or colors.muted)
                local row_height, per_line = activity_height(row, width, scale)
                draw_api.filled_rect(x + 8 * scale, ry + 5 * scale, 3 * scale, 41 * scale, color)
                Icons.draw(draw_api, row.icon, x + 16 * scale, ry + 3 * scale, 18 * scale,
                    color, not row.ready)
                local counter = row.slots and string.format("%d/%d", row.slots.occupied, row.slots.capacity)
                local counter_width = counter and measure(counter) or 0
                text(draw_api, fitted(row.name, width - 56 * scale - counter_width),
                    x + 42 * scale, ry + 3 * scale, colors.text)
                if row.slots then
                    text(draw_api, counter, x + width - 16 * scale - counter_width,
                        ry + 3 * scale, color)
                    for slot = 1, row.slots.capacity do
                        local occupied = slot <= row.slots.occupied
                        Icons.draw(draw_api, row.slot_icon or "slot",
                            x + (16 + ((slot - 1) % per_line) * 17) * scale,
                            ry + (25 + math.floor((slot - 1) / per_line) * 17) * scale,
                            14 * scale, occupied and color or 0xFF686460, not occupied)
                    end
                    if row.slots.capacity == 0 or row.closed then
                        text(draw_api, translate(settings, row.closed and "Recepcion cerrada" or "Sin espacios"),
                            x + 16 * scale, ry + (row_height - 20) * scale, colors.muted)
                    end
                else
                    text(draw_api, fitted(row.detail), x + 16 * scale, ry + 25 * scale, color)
                end
                if row.ratio then
                    local bar_width = width - 32 * scale
                    draw_api.filled_rect(x + 16 * scale, ry + 48 * scale, bar_width,
                        3 * scale, (alpha << 24) | 0x504A42)
                    if row.ratio > 0 then
                        draw_api.filled_rect(x + 16 * scale, ry + 48 * scale,
                            bar_width * math.max(0, math.min(1, row.ratio)), 3 * scale, color)
                    end
                end
                ry = ry + row_height * scale
            end
        end
        if omitted > 0 then
            text(draw_api, fitted(translate(settings, "+ %d actividades sin mostrar", omitted)),
                x + 12 * scale, ry + 3 * scale, colors.muted)
        end
    end)
    if scalable then imgui_api.pop_font_size() end
    if not ok then error(err, 0) end
end

function View.render_buffs(draw_api, imgui_api, settings, rows, preview)
    if not settings.enabled or not settings.show_buffs or not rows or #rows == 0 then return end
    local display = imgui_api.get_display_size()
    local scalable = imgui_api.push_font_size and imgui_api.pop_font_size
    local scale = settings.scale * settings.buffs_size / 100
    if not scalable then scale = math.max(1, scale) end
    local width = math.min(settings.buffs_width * scale, display.x)
    local row_height = settings.buffs_names and 76 or 56
    local cell_width = settings.buffs_names and 152 or 64
    if width < 64 * scale or display.y < (28 + row_height) * scale then return end
    local columns = math.max(1, math.min(#rows, math.floor(width / (cell_width * scale))))
    width = math.min(width, columns * cell_width * scale)
    local lines = math.floor((display.y / scale - 28) / row_height)
    local count = math.min(#rows, columns * lines)
    if count < #rows then
        lines = math.floor((display.y / scale - 52) / row_height)
        count = math.min(#rows, columns * lines)
    end
    if count == 0 then return end
    local omitted = #rows - count
    local height = (28 + math.ceil(count / columns) * row_height + (omitted > 0 and 24 or 0)) * scale
    local x = math.max(0, math.min(settings.buffs_x, display.x - width))
    local y = math.max(0, math.min(settings.buffs_y, display.y - height))
    local cell = width / columns
    local alpha = math.floor(settings.opacity * 255 / 100 + 0.5)
    local font_size = scalable and 14 * scale or 16
    if scalable then imgui_api.push_font_size(font_size) end
    local ok, err = pcall(function()
        local function measure(label)
            if imgui_api.calc_text_size then return imgui_api.calc_text_size(label).x end
            return utf8.len(label) * font_size * 0.65
        end
        local function fitted(value, available)
            value = short_name(value, 100)
            local length = utf8.len(value)
            while measure(value) > available and length > 3 do
                length = length - 1
                value = short_name(value, length)
            end
            return value
        end
        draw_api.filled_rect(x, y, width, height, (alpha << 24) | 0x201C18)
        draw_api.filled_rect(x, y, width, 3 * scale, 0xFFF29D49)
        text(draw_api, fitted(preview and "BUFFS - DEMO" or "BUFFS", width - 24 * scale),
            x + 12 * scale, y + 9 * scale, colors.text)
        for index = 1, count do
            local row = rows[index]
            local left = x + ((index - 1) % columns) * cell
            local top = y + (28 + math.floor((index - 1) / columns) * row_height) * scale
            local cx = left + cell / 2
            Icons.draw(draw_api, row.icon, cx - 12 * scale, top + 3 * scale, 24 * scale, row.color)
            local timer = fitted(row.remaining == nil and "ACT" or View.timer(row.remaining), cell - 8 * scale)
            local name = fitted(translate(settings, row.name), cell - 16 * scale)
            text(draw_api, timer, cx - measure(timer) / 2, top + 32 * scale, row.color)
            if settings.buffs_names then
                text(draw_api, name, cx - measure(name) / 2, top + 52 * scale, colors.muted)
            end
        end
        if omitted > 0 then
            text(draw_api, fitted(translate(settings, "+ %d sin mostrar", omitted), width - 24 * scale),
                x + 12 * scale, y + height - 21 * scale, colors.muted)
        end
    end)
    if scalable then imgui_api.pop_font_size() end
    if not ok then error(err, 0) end
end

local stat_attributes = {
    FIRE = { "stat_fire", 0xFF5985F0 },
    WATER = { "stat_water", 0xFFF2BB69 },
    ELEC = { "stat_thunder", 0xFF70DDF2 },
    ICE = { "stat_ice", 0xFFFFE0AB },
    DRAGON = { "stat_dragon", 0xFFB88CDA },
    POISON = { "stat_poison", 0xFFCF88BB },
    PARALYSE = { "paralysis", 0xFF70DDF2 },
    SLEEP = { "stat_sleep", 0xFFE0BC88 },
    BLAST = { "stat_blast", 0xFF73AAF2 },
    NONE = { "stat_none", colors.muted },
}

function View.render_stats(draw_api, imgui_api, settings, stats, preview)
    if not settings.enabled or not settings.show_stats or not stats then return end
    local display = imgui_api.get_display_size()
    local scalable = imgui_api.push_font_size and imgui_api.pop_font_size
    local scale = settings.scale * settings.stats_size / 100
    local header = preview and 20 or 0
    if scalable then
        scale = math.min(scale, display.x / 540, display.y / (56 + header))
    else
        scale = math.max(1, scale)
    end
    if scale <= 0 or display.x < 540 * scale or display.y < (56 + header) * scale then return end
    local width = math.min(math.max(540, settings.stats_width) * scale, display.x)
    local height = (56 + header) * scale
    local x = math.max(0, math.min(settings.stats_x, display.x - width))
    local y = math.max(0, math.min(settings.stats_y, display.y - height))
    local font_size = scalable and 14 * scale or 16
    if scalable then imgui_api.push_font_size(font_size) end
    local ok, err = pcall(function()
        local function measure(value)
            if imgui_api.calc_text_size then return imgui_api.calc_text_size(value).x end
            return utf8.len(value) * font_size * 0.65
        end
        local function number(value)
            if value == nil then return "--" end
            return string.format(value % 1 == 0 and "%.0f" or "%.1f", value)
        end
        local resists = stats.resists or {}
        local attribute = stats.element and stat_attributes[stats.element.id]
            or { "stat_unknown", colors.muted }
        local rows = {
            { "stat_attack", number(stats.attack), colors.rage },
            { "stat_defence", number(stats.defence), colors.stamina },
            { "stat_affinity", number(stats.affinity) .. (stats.affinity ~= nil and "%" or ""), colors.text },
            { attribute[1], number(stats.element and stats.element.value), attribute[2] },
        }
        for _, key in ipairs({ "FIRE", "WATER", "ELEC", "ICE", "DRAGON" }) do
            local spec = stat_attributes[key]
            rows[#rows + 1] = { spec[1], number(resists[key]), spec[2] }
        end
        local cell = width / #rows
        if not scalable then
            for _, row in ipairs(rows) do
                if measure(row[2]) > cell - 8 * scale then return end
            end
        end
        local alpha = math.floor(settings.opacity * 255 / 100 + 0.5)
        draw_api.filled_rect(x, y, width, height, (alpha << 24) | 0x201C18)
        if stats.partial then
            draw_api.filled_rect(x, y, width, 2 * scale, colors.warning)
        end
        if preview then
            text(draw_api, translate(settings, "ESTADISTICAS - DEMO"), x + 8 * scale, y + 3 * scale, colors.muted)
        end
        for index, row in ipairs(rows) do
            local cx = x + (index - 0.5) * cell
            local top = y + header * scale
            Icons.draw(draw_api, row[1], cx - 11 * scale, top + 5 * scale, 22 * scale, row[3])
            local length = measure(row[2])
            local factor = math.min(1, (cell - 8 * scale) / math.max(1, length))
            if scalable and factor < 1 then imgui_api.push_font_size(font_size * factor) end
            local drawn, message = pcall(text, draw_api, row[2],
                cx - length * factor / 2, top + 33 * scale, colors.text)
            if scalable and factor < 1 then imgui_api.pop_font_size() end
            if not drawn then error(message, 0) end
            if index == 3 or index == 4 then
                draw_api.filled_rect(x + index * cell, top + 8 * scale,
                    scale, 40 * scale, (alpha << 24) | 0x504A42)
            end
        end
    end)
    if scalable then imgui_api.pop_font_size() end
    if not ok then error(err, 0) end
end

return View
