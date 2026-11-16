-- Copyright © 2026 Squallqt. All rights reserved.

---Vehicle debug window.
RMS_DebugWindow = {}

RMS_DebugWindow.VIEW = {OVERVIEW = 1, PARTS = 2, MACHINE = 3}
local VIEW = RMS_DebugWindow.VIEW
local VIEW_NAMES = {"Overview", "Parts", "Machine"}

local REFRESH_MS = 500
local READING_LIFE_MS = 2 * REFRESH_MS
local SEP = "  ·  "

-- pixels of a 2560 x 1440 screen at interface scale 1
local SCREEN_W, SCREEN_H = 2560, 1440
local SIDE = {x = 40, y = 312, w = 440, bottom = 1010}
local MAIN = {x = 500, y = 140, w = 2020, bottom = 1010}
local PAD = 28
local GAP = 20
local SCROLL_W = 6
local WHEEL_STEP = 72
-- past eight fill types, the views keep room to scroll
local MIN_VIEWPORT = 340
-- the capitals of the game font stand 25 of its 35 units on the line
local CAP_HALF = 25 / 35 / 2

local function srgb(hex, alpha)
    local color = {}
    for index = 1, 3 do
        local value = tonumber(hex:sub(index * 2 - 1, index * 2), 16) / 255
        color[index] = value <= 0.04045 and value / 12.92 or ((value + 0.055) / 1.055) ^ 2.4
    end
    color[4] = alpha or 1
    return color
end

local COLOR = {
    panel = srgb("090a08", 0.965),
    card = srgb("ffffff", 0.022),
    tile = srgb("ffffff", 0.045),
    stripe = srgb("ffffff", 0.018),
    active = srgb("ffffff", 0.07),
    line = srgb("ffffff", 0.08),
    track = srgb("ffffff", 0.10),
    chip = srgb("ffffff", 0.08),
    effect = srgb("ffffff", 0.06),
    text = srgb("f2f5e8"),
    label = srgb("a6a99b"),
    dim = srgb("77796f"),
    ok = srgb("8fc31f"),
    yellow = srgb("f1d548"),
    orange = srgb("f29a3a"),
    red = srgb("f0544a"),
    blue = srgb("4aa8e6"),
    bar = srgb("c4c8b8"),
    heat = srgb("ec9a46"),
    normal = srgb("5d6058"),
    tick = srgb("f2f5e8", 0.9),
    axis = srgb("ffffff", 0.18)
}
-- causes of a card in order of their share, never a colour of judgement
local CAUSE_COLORS = {srgb("4fb4dc"), srgb("b48ae8"), srgb("45c79c"), srgb("e384bd"), srgb("8f9bf2"), srgb("d9b25a"), srgb("6fd0d6")}
local LAMP_COLORS = {COLOR.red, COLOR.orange, COLOR.blue, COLOR.label}

RMS_DebugWindow.isOpen = false
RMS_DebugWindow.view = VIEW.OVERVIEW
RMS_DebugWindow.scroll = {0, 0, 0}
RMS_DebugWindow.sideScroll = 0
RMS_DebugWindow.vehicle = nil
RMS_DebugWindow.reading = nil
RMS_DebugWindow.refreshTime = -math.huge
RMS_DebugWindow.commands = nil
RMS_DebugWindow.hits = {}

local L = {}

local function setScreen()
    local scale = math.min(g_gameSettings:getValue(GameSettings.SETTING.UI_SCALE), 1)
    L.unit = math.min(g_screenHeight / SCREEN_H * scale, g_screenWidth * 0.98 / (MAIN.x + MAIN.w - SIDE.x))
    L.left = (g_screenWidth - SCREEN_W * L.unit) / 2
    L.commands = {}
    L.isMeasuring = false
    L.clip = nil
    L.hits = {}
    L.overflows = {}
end

local function screenX(x)
    return (L.left + x * L.unit) / g_screenWidth
end

local function screenY(y)
    return 1 - y * L.unit / g_screenHeight
end

local function toRefX(posX)
    return (posX * g_screenWidth - L.left) / L.unit
end

local function toRefY(posY)
    return (1 - posY) * g_screenHeight / L.unit
end

local function textSize(px)
    return px * L.unit / g_screenHeight
end

local function measure(text, px, bold)
    setTextBold(bold == true)
    local width = getTextWidth(textSize(px), text) * g_screenWidth / L.unit
    setTextBold(false)
    return width
end

-- the engine counts corner radii in 20 px of a 1080p screen
local function corner(radius)
    return radius * L.unit * 1080 / g_screenHeight / 20
end

---Draws a rectangle, cut to the scrolled area while one is set
local function rect(x, y, w, h, color, radius)
    if L.isMeasuring or w <= 0 or h <= 0 then
        return
    end
    local clip = L.clip
    if clip ~= nil then
        y = y - clip.offset
        if y + h <= clip.top or y >= clip.bottom then
            return
        end
    end
    local command = {x = screenX(x), y = screenY(y + h), w = w * L.unit / g_screenWidth, h = h * L.unit / g_screenHeight,
        color = color, corner = corner(radius or 0)}
    if clip ~= nil then
        command.clipY1, command.clipY2 = screenY(clip.bottom), screenY(clip.top)
    end
    table.insert(L.commands, command)
end

---Writes a text centred on y, only whole inside a scrolled area
-- @param table? options bold, align (RenderText), box: width it must hold within
local function label(x, y, text, px, color, options)
    if L.isMeasuring or text == nil or text == "" then
        return
    end
    options = options or {}
    local bold = options.bold == true
    local width = measure(text, px, bold)
    if options.box ~= nil and width > options.box + 0.5 then
        table.insert(L.overflows, {text = text, width = width, box = options.box})
    end
    local clip = L.clip
    if clip ~= nil then
        y = y - clip.offset
        if y - px * 0.6 < clip.top or y + px * 0.6 > clip.bottom then
            return width
        end
    end
    local align = options.align or RenderText.ALIGN_LEFT
    table.insert(L.commands, {x = screenX(x), y = screenY(y), size = textSize(px), text = text, color = color, bold = bold, align = align})
    return width
end

local function hit(kind, x, y, w, h, value)
    table.insert(L.hits, {kind = kind, x = x, y = y, w = w, h = h, value = value})
end

local function splitItems(text)
    local items, start = {}, 1
    while true do
        local first, last = text:find(SEP, start, true)
        if first == nil then
            table.insert(items, text:sub(start))
            return items
        end
        table.insert(items, text:sub(start, first - 1))
        start = last + 1
    end
end

---Puts items on lines of a width, broken between two items only
local function wrapItems(items, w, px, bold)
    local lines, line = {}, nil
    for _, entry in ipairs(items) do
        local joined = line == nil and entry or line .. SEP .. entry
        if line ~= nil and measure(joined, px, bold) > w then
            table.insert(lines, line)
            line = entry
        else
            line = joined
        end
    end
    table.insert(lines, line or "")
    return lines
end

---Puts words on lines of a width, a longer word cut between letters
local function wrapWords(text, w, px, bold)
    local lines, line = {}, nil
    for word in text:gmatch("%S+") do
        local joined = line == nil and word or line .. " " .. word
        if measure(joined, px, bold) <= w then
            line = joined
        else
            if line ~= nil then
                table.insert(lines, line)
            end
            line = word
            while measure(line, px, bold) > w and utf8Strlen(line) > 1 do
                local length, count = utf8Strlen(line), 1
                while count < length - 1 and measure(utf8Substr(line, 0, count + 1), px, bold) <= w do
                    count = count + 1
                end
                table.insert(lines, utf8Substr(line, 0, count))
                line = utf8Substr(line, count, length - count)
            end
        end
    end
    table.insert(lines, line or "")
    return lines
end

local function pct(value)
    return string.format("%d %%", math.floor(value * 100 + 0.5))
end

-- a rate of wear in % of life per hour, to three figures
local function perHour(rate)
    local format = rate < 9.995 and "%.2f %%/h" or rate < 99.95 and "%.1f %%/h" or "%.0f %%/h"
    return string.format(format, rate)
end

local function bar(x, y, w, h, share, color, tick)
    rect(x, y, w, h, COLOR.track, h / 2)
    if share > 0 then
        rect(x, y, math.max(w * math.min(share, 1), h), h, color, h / 2)
    end
    if tick ~= nil and tick >= 0 then
        rect(x + w * tick - 1, y - 3, 2, h + 6, COLOR.tick)
    end
end

local function card(x, y, w, h, color)
    rect(x, y, w, h, color or COLOR.card, 10)
end

local function hairline(x, y, w, color)
    rect(x, y, w, 1, color or COLOR.line)
end

local function title(x, y, w, text, note)
    rect(x, y + 3, 4, 18, HUD.COLOR.ACTIVE, 2)
    local width = label(x + 14, y + 12, text:upper(), 16, HUD.COLOR.ACTIVE, {bold = true}) or measure(text:upper(), 16, true)
    if note ~= nil and note ~= "" then
        label(x + w, y + 12, note, 14, COLOR.dim, {align = RenderText.ALIGN_RIGHT, box = w - width - 40})
    end
end

local CHIP_H, CHIP_ROW = 22, 28

local function chipWidth(entry, px)
    return measure(entry.text, px, entry.bold) + 16 + (entry.dot and 14 or 0)
end

local function chip(x, y, entry, px)
    local w = chipWidth(entry, px)
    local color = entry.color
    rect(x, y - CHIP_H / 2, w, CHIP_H, entry.background or {color[1], color[2], color[3], 0.16}, CHIP_H / 2)
    local dot = entry.dot and 14 or 0
    if entry.dot then
        rect(x + 8, y - 4, 8, 8, entry.color, 4)
    end
    label(x + 8 + dot, y, entry.text, px, entry.color, {bold = entry.bold})
    return w
end

---Lays chips on lines of a width
-- @return float height used
local function chips(x, y, w, entries)
    local cx, cy = x, y
    for _, entry in ipairs(entries) do
        local cw = chipWidth(entry, 14)
        if cx > x and cx + cw > x + w then
            cx, cy = x, cy + CHIP_ROW
        end
        if cw > w and not L.isMeasuring then
            table.insert(L.overflows, {text = entry.text, width = cw, box = w})
        end
        chip(cx, cy, entry, 14)
        cx = cx + cw + 6
    end
    return cy - y + CHIP_ROW
end

local RISK_TIERS = {{"low", COLOR.ok}, {"moderate", COLOR.yellow}, {"high", COLOR.red}}

local function getRiskTier(risk)
    return RISK_TIERS[RMS_Utils.getBreakdownRiskTier(risk)]
end

local function partColor(part)
    return part.stage > 0 and COLOR.red or part.isWorn and COLOR.orange or nil
end

local function chanceText(part)
    if part.stage > 0 then
        return "failing"
    end
    local percent = math.floor(part.chance * 1000 + 0.5) / 10
    return percent == 0 and "<0.1 %" or percent == 100 and "100 %" or string.format("%.1f %%", percent)
end

---Runs a part of the layout without drawing it, for its height
local function measureHeight(draw)
    local wasMeasuring = L.isMeasuring
    L.isMeasuring = true
    local height = draw()
    L.isMeasuring = wasMeasuring
    return height
end

---Draws a scroll bar and returns where it stands
-- @param string kind hit kind of its track
-- @return table top, viewport, height, thumbY, thumbH, maxScroll
local function scrollBar(kind, trackX, top, viewport, height, scroll, isMouse)
    local maxScroll = height - viewport
    local thumbH = math.max(viewport * viewport / height, 40)
    local thumbY = top + (viewport - thumbH) * scroll / maxScroll
    rect(trackX, top, SCROLL_W, viewport, COLOR.track, SCROLL_W / 2)
    rect(trackX, thumbY, SCROLL_W, thumbH, RMS_DebugWindow.dragTarget == kind and COLOR.text or COLOR.bar, SCROLL_W / 2)
    if isMouse then
        hit(kind, trackX - 10, top, SCROLL_W + 20, viewport)
    end
    return {top = top, viewport = viewport, height = height, thumbY = thumbY, thumbH = thumbH, maxScroll = maxScroll}
end

---Draws the sheet of the machine from y
-- @return float height used
local function drawSheet(reading, x, y, w)
    local top = y
    if reading == nil then
        label(x, y + 15, "Waiting for the server", 20, COLOR.label, {bold = true, box = w})
        y = y + 30
    else
        for _, line in ipairs(wrapWords(reading.name, w, 26, true)) do
            label(x, y + 15, line, 26, COLOR.text, {bold = true, box = w})
            y = y + 32
        end
        for _, line in ipairs(wrapItems(reading.kind, w, 17)) do
            label(x, y + 11, line, 17, COLOR.label, {box = w})
            y = y + 24
        end
        y = y + 14
        local vitals = reading.vitals
        local tw = (w - 3 * 8) / 4
        for index, entry in ipairs({{vitals.condition, "Condition"}, {vitals.lifeUsed, "Life used"}, {vitals.reliability, "Reliability"},
            {vitals.faults, "Faults so far"}}) do
            local tx = x + (index - 1) * (tw + 8)
            card(tx, y, tw, 70, COLOR.tile)
            label(tx + tw / 2, y + 28, entry[1], 26, COLOR.text, {bold = true, align = RenderText.ALIGN_CENTER, box = tw - 8})
            label(tx + tw / 2, y + 54, entry[2], 13, COLOR.label, {align = RenderText.ALIGN_CENTER, box = tw - 6})
        end
        y = y + 70
        if vitals.faultsNote ~= "" then
            y = y + 6
            for _, line in ipairs(wrapWords(vitals.faultsNote, w, 13)) do
                label(x + w, y + 8, line, 13, COLOR.dim, {align = RenderText.ALIGN_RIGHT, box = w})
                y = y + 18
            end
        end
        y = y + 18
        for _, fact in ipairs(reading.facts) do
            label(x, y + 7, fact[1]:upper(), 13, COLOR.dim, {bold = true})
            y = y + 18
            for _, line in ipairs(wrapItems(splitItems(fact[2]), w, 17)) do
                label(x, y + 11, line, 17, COLOR.text, {box = w})
                y = y + 23
            end
            y = y + 10
        end
    end
    return y - top
end

local function drawSidebar(reading, isMouse)
    local window = RMS_DebugWindow
    local x, w = SIDE.x + 24, SIDE.w - 48
    rect(SIDE.x, SIDE.y, SIDE.w, SIDE.bottom - SIDE.y, COLOR.panel, 14)
    -- the views and how to reach them, at the foot
    local ny = SIDE.bottom - 24 - (26 + 3 * 42 + 4 + 22)

    -- the sheet above them, scrolled past a name of many lines
    local clipTop, top, bottom = SIDE.y + 14, SIDE.y + 22, ny - 22
    local height = measureHeight(function() return drawSheet(reading, x, top, w) end) + top - clipTop
    local maxScroll = math.max(height - (bottom - clipTop), 0)
    window.sideScroll = math.min(math.max(window.sideScroll, 0), maxScroll)
    if maxScroll > 0 then
        L.clip = {top = clipTop, bottom = bottom, offset = window.sideScroll}
    end
    drawSheet(reading, x, top, w)
    L.clip = nil
    window.sideState = maxScroll > 0 and scrollBar("sideTrack", SIDE.x + SIDE.w - (24 + SCROLL_W) / 2, clipTop, bottom - clipTop, height,
        window.sideScroll, isMouse) or nil

    hairline(x, ny - 10, w, COLOR.track)
    label(x, ny + 12, "RMS DEBUG", 15, HUD.COLOR.ACTIVE, {bold = true})
    if isMouse then
        local isHover = RMS_DebugWindow.hover == "close"
        local closeW = label(x + w, ny + 12, "Close  ×", 14, isHover and COLOR.text or COLOR.label, {align = RenderText.ALIGN_RIGHT}) or 0
        hit("close", x + w - closeW - 8, ny, closeW + 16, 24)
    end
    ny = ny + 26
    local counts = {}
    if reading ~= nil then
        local parts, readings = 0, 0
        for _, system in ipairs(reading.systems) do
            parts = parts + #system.parts
        end
        for _, group in ipairs(reading.machine) do
            for _, row in ipairs(group.rows) do
                readings = readings + (row.label ~= "" and 1 or 0)
            end
        end
        counts = {string.format("%d %s", #reading.faults, #reading.faults == 1 and "fault" or "faults"), string.format("%d parts", parts),
            string.format("%d readings", readings)}
    end
    for view, name in ipairs(VIEW_NAMES) do
        local isActive = view == RMS_DebugWindow.view
        local isHover = isMouse and RMS_DebugWindow.hover == "view" .. view
        if isActive or isHover then
            rect(x, ny + 2, w, 38, isActive and COLOR.active or COLOR.card, 9)
        end
        if isActive then
            rect(x, ny + 11, 4, 20, HUD.COLOR.ACTIVE, 2)
        end
        label(x + 18, ny + 21, tostring(view), 15, isActive and HUD.COLOR.ACTIVE or COLOR.dim, {bold = true})
        label(x + 40, ny + 21, name, 18, isActive and COLOR.text or COLOR.label, {bold = isActive})
        label(x + w - 12, ny + 21, counts[view], 14, isActive and COLOR.label or COLOR.dim, {align = RenderText.ALIGN_RIGHT})
        if isMouse then
            hit("view", x, ny + 2, w, 38, view)
        end
        ny = ny + 42
    end
    local keyText = RMS_Utils.getPrimaryKeyboardInputText("RMS_TOGGLE_DEBUG_WINDOW", "Alt Gr + F5")
    label(x, ny + 15, isMouse and "Right click  back to driving" or keyText .. "  use the mouse", 14, COLOR.label, {box = w})
end

local TILE_H, TILES_PER_ROW = 192, 8

---Draws a tile per system, eight to a row, two even rows past eight
-- @return float height used
local function drawTiles(reading, x, y, w)
    local count = #reading.systems
    local perRow = count <= TILES_PER_ROW and count or math.ceil(count / 2)
    local tw = (w - (perRow - 1) * 14) / perRow
    for index, system in ipairs(reading.systems) do
        local tx = x + (index - 1) % perRow * (tw + 14)
        local ty = y + math.floor((index - 1) / perRow) * (TILE_H + 14)
        local ix, iw = tx + 16, tw - 32
        card(tx, ty, tw, TILE_H)
        local risk = {text = string.format("×%.1f", system.risk), bold = true, color = getRiskTier(system.risk)[2]}
        local rw = chipWidth(risk, 15)
        chip(ix + iw - rw, ty + 26, risk, 15)
        label(ix, ty + 26, system.name, 18, COLOR.text, {bold = true, box = iw - rw - 8})
        local conditionW = measure(pct(system.condition), 34, true)
        label(ix, ty + 64, pct(system.condition), 34, COLOR.text, {bold = true})
        label(ix + conditionW + 8, ty + 71, "condition", 14, COLOR.dim)
        bar(ix, ty + 88, iw, 4, system.condition, COLOR.bar)
        if system.wearing > 0 then
            label(ix, ty + 112, "wearing " .. perHour(system.wearing), 15, system.wearing > system.normal * 1.3 and COLOR.yellow or COLOR.text,
                {box = iw})
        else
            label(ix, ty + 112, "not wearing", 15, COLOR.dim)
        end
        hairline(ix, ty + 128, iw)
        label(ix, ty + 144, "MOST AT RISK", 12, COLOR.dim, {bold = true})
        local part = system.parts[1]
        local color = partColor(part)
        local chance = chanceText(part)
        local chanceW = measure(chance, 15, true)
        label(ix + iw, ty + 164, chance, 15, color or (part.chance >= 0.1 and COLOR.yellow or COLOR.text), {bold = true, align = RenderText.ALIGN_RIGHT})
        for line, text in ipairs(wrapWords(part.name, iw - chanceW - 10, 15)) do
            label(ix, ty + 164 + (line - 1) * 20, text, 15, color or COLOR.text, {box = iw - chanceW - 10})
        end
    end
    return math.ceil(count / perRow) * (TILE_H + 14) - 14
end

local EMPTY_COLUMN_H = 300

local function drawWearNow(reading, x, y, w, h)
    local ix, iw = x + 16, w - 32
    card(x, y, w, h)
    title(ix, y + 14, iw, "Wear now", "% of life per hour of play" .. SEP .. "bar: against the normal rate")
    if #reading.wearNow == 0 then
        label(x + w / 2, y + math.min(h, EMPTY_COLUMN_H) / 2 + 20, "Nothing wears it beyond its normal rate right now", 17, COLOR.label,
            {align = RenderText.ALIGN_CENTER, box = iw})
        return EMPTY_COLUMN_H
    end
    local normal = {}
    for _, system in ipairs(reading.systems) do
        normal[system.name] = system.normal
    end
    local cy = y + 62
    for index, group in ipairs(reading.wearNow) do
        if index > 1 then
            hairline(ix, cy - 14, iw)
            cy = cy + 10
        end
        label(ix, cy, group.system, 15, COLOR.text, {bold = true, box = 112})
        for _, cause in ipairs(group.causes) do
            label(ix + 118, cy, cause.label, 15, COLOR.text, {box = 178})
            label(ix + 302, cy, cause.measure, 14, COLOR.label, {box = 174})
            bar(ix + 482, cy - 3, 48, 6, cause.rate / (normal[group.system] or 1), COLOR.yellow)
            label(ix + iw, cy, "+" .. perHour(cause.rate), 15, COLOR.text, {bold = true, align = RenderText.ALIGN_RIGHT, box = 72})
            cy = cy + 26
        end
    end
    return cy - y
end

local function drawWork(reading, x, y, w, h)
    local work = reading.work
    local ix, iw = x + 16, w - 32
    card(x, y, w, h)
    title(ix, y + 14, iw, "Work in progress", "nothing wears in the workshop")
    local cy = y + 66
    label(ix, cy, work.title, 22, COLOR.text, {bold = true})
    label(ix + iw, cy, work.price, 22, COLOR.text, {bold = true, align = RenderText.ALIGN_RIGHT})
    cy = cy + 30
    local entries = {}
    for _, text in ipairs(work.chips) do
        table.insert(entries, {text = text, color = COLOR.label})
    end
    cy = cy + chips(ix, cy, iw, entries) + 8
    bar(ix, cy - 4, iw, 8, work.progress, HUD.COLOR.ACTIVE)
    cy = cy + 22
    label(ix, cy, work.progressText, 15, COLOR.label, {box = iw})
    cy = cy + 36
    for _, list in ipairs({{"REPAIRS", work.repairs}, {"INSPECTIONS", work.inspections}}) do
        label(ix, cy, list[1], 13, COLOR.dim, {bold = true})
        local names = {}
        for _, name in ipairs(list[2]) do
            table.insert(names, {text = name, color = COLOR.text, background = COLOR.chip})
        end
        if #names == 0 then
            names = {{text = "none", color = COLOR.dim}}
        end
        cy = cy + chips(ix + 130, cy, iw - 130, names) + 4
    end
    for _, list in ipairs({{"PARTS RENEWED", work.renewed, COLOR.orange}, {"SERVICE TO", work.serviceTo, COLOR.bar}}) do
        if #list[2] > 0 then
            cy = cy + 4
            label(ix, cy, list[1], 13, COLOR.dim, {bold = true})
            for _, entry in ipairs(list[2]) do
                label(ix + 130, cy, entry.name, 15, COLOR.text, {box = 206})
                bar(ix + 344, cy - 3, 116, 6, entry.from, list[3])
                label(ix + iw, cy, string.format("%s  →  %s", pct(entry.from), pct(entry.to)), 15, COLOR.text,
                    {bold = true, align = RenderText.ALIGN_RIGHT})
                cy = cy + 26
            end
        end
    end
    return cy - y
end

local FAULT_PITCH_MAX, FAULT_PITCH_MIN = 22, 18

local function drawFault(fault, x, y, w, pitch)
    local color = fault.isSeen and COLOR.red or COLOR.orange
    local px, pw = x + 14, w - 14
    local flagLines = wrapItems(fault.flags, pw - 252, 13)
    local lines = 1 + #flagLines + #fault.notes
    local h = lines * pitch + 8
    rect(x, y + 4, 3, h - 8, color, 1.5)
    local cy = y + pitch / 2 + 2
    local nameW = measure(fault.name, 17, true)
    label(px, cy, fault.name, 17, color, {bold = true})
    label(px + nameW + 10, cy + 1, fault.system, 14, COLOR.label)
    local stepX = px + pw - fault.stages * 19 + 3
    for step = 1, fault.stages do
        rect(stepX + (step - 1) * 19, cy - 4, 16, 8, step <= fault.stage and color or COLOR.track, 3)
    end
    label(stepX - 10, cy, string.format("severity %d of %d", fault.stage, fault.stages), 14, COLOR.label, {align = RenderText.ALIGN_RIGHT})
    cy = cy + pitch
    bar(px, cy - 3, 40, 6, fault.progress, color)
    label(px + 50, cy, fault.next, 14, COLOR.text, {box = 190})
    for line, text in ipairs(flagLines) do
        label(px + pw, cy + (line - 1) * pitch, text, 13, COLOR.label, {align = RenderText.ALIGN_RIGHT, box = pw - 252})
    end
    cy = cy + #flagLines * pitch
    for _, note in ipairs(fault.notes) do
        label(px, cy, note, 14, note:find("^warranty") and COLOR.red or COLOR.orange, {box = pw})
        cy = cy + pitch
    end
    return h
end

local function drawFaults(reading, x, y, w, h)
    local ix, iw = x + 16, w - 32
    card(x, y, w, h)
    title(ix, y + 14, iw, "Faults", #reading.faults > 0 and string.format("%d active" .. SEP .. "red seen by the player, orange hidden",
        #reading.faults) or "none")
    if #reading.faults == 0 then
        label(x + w / 2, y + math.min(h, EMPTY_COLUMN_H) / 2 + 20, "No fault on this machine", 17, COLOR.label, {align = RenderText.ALIGN_CENTER})
        return EMPTY_COLUMN_H
    end
    -- the rows close up to fit the column, then it scrolls
    local pitch = FAULT_PITCH_MAX
    local function getRowsHeight()
        local rowsH = 0
        for _, fault in ipairs(reading.faults) do
            rowsH = rowsH + measureHeight(function() return drawFault(fault, ix, 0, iw, pitch) end) + 6
        end
        return rowsH
    end
    while pitch > FAULT_PITCH_MIN and 50 + getRowsHeight() + 14 > h do
        pitch = pitch - 1
    end
    local cy = y + 50
    for index, fault in ipairs(reading.faults) do
        if index > 1 then
            hairline(ix, cy - 3, iw)
        end
        cy = cy + drawFault(fault, ix, cy, iw, pitch) + 6
    end
    return cy - y
end

local function drawDashboard(reading, x, y, w, h)
    local ix, iw = x + 16, w - 32
    card(x, y, w, h)
    title(ix, y + 14, iw, "Dashboard and codes")
    local alerts = reading.alerts
    local cy = y + 62
    local function section(name, note)
        label(ix, cy, name, 13, COLOR.dim, {bold = true})
        if note ~= nil then
            label(ix + iw, cy, note, 13, COLOR.dim, {align = RenderText.ALIGN_RIGHT})
        end
        cy = cy + 26
    end
    local function list(entries)
        if #entries == 0 then
            label(ix, cy, "none", 15, COLOR.dim)
            cy = cy + 36
        else
            cy = cy + chips(ix, cy, iw, entries) + 10
        end
    end
    section("LAMPS LIT")
    local lamps = {}
    for _, lamp in ipairs(alerts.lamps) do
        local color = LAMP_COLORS[lamp.color] or COLOR.label
        table.insert(lamps, {text = lamp.text, color = color, dot = true})
    end
    list(lamps)
    for _, entry in ipairs({{"DISPLAY", "codes the dashboard shows", alerts.display}, {"CODES", "what the diagnostic tool reads", alerts.codes}}) do
        section(entry[1], entry[2])
        local codes = {}
        for _, text in ipairs(entry[3]) do
            table.insert(codes, {text = text, color = text:find("hidden", 1, true) and COLOR.label or COLOR.text, background = COLOR.chip})
        end
        list(codes)
    end
    section("EFFECTS", "what the faults change")
    local effects = {}
    for _, effect in ipairs(alerts.effects) do
        table.insert(effects, {text = effect.label .. " " .. effect.value, color = COLOR.text, background = COLOR.effect})
    end
    list(effects)
    return cy - y
end

local function drawOverview(reading, area)
    local y = area.y + drawTiles(reading, area.x, area.y, area.w) + GAP
    local h = area.bottom - y
    local cw = (area.w - 2 * GAP) / 3
    local columns = {
        {x = area.x, draw = reading.work.isActive and drawWork or drawWearNow},
        {x = area.x + cw + GAP, draw = drawFaults},
        {x = area.x + 2 * (cw + GAP), draw = drawDashboard}
    }
    -- the three columns as tall as the tallest
    for _, column in ipairs(columns) do
        h = math.max(h, measureHeight(function() return column.draw(reading, column.x, y, cw, h) end) + 14)
    end
    for _, column in ipairs(columns) do
        column.draw(reading, column.x, y, cw, h)
    end
    return y + h - area.y
end

-- system places: engine over cooling, transmission over hydraulics...
local PART_GRID = {{{"Engine", "Electric motor"}, {"Transmission"}, {"Fuel", "Traction battery"}, {"Chassis"}},
    {{"Cooling"}, {"Hydraulics"}, {"Electrical"}, {"PTO", "Harvest"}}}

local function findSystem(reading, names)
    for _, system in ipairs(reading.systems) do
        for _, name in ipairs(names) do
            if system.name == name then
                return system
            end
        end
    end
    return nil
end

local function getCauseColor(cause)
    return cause == 1 and COLOR.normal or CAUSE_COLORS[(cause - 2) % #CAUSE_COLORS + 1]
end

local function getLegend(system)
    -- a cause a part still shows keeps its colour named
    local isShown = {}
    for _, part in ipairs(system.parts) do
        for _, entry in ipairs(part.causes) do
            isShown[entry.cause] = entry.cause > 1
        end
    end
    local entries = {{text = string.format("wear taken %s", pct(system.wearTaken))}}
    for index, share in ipairs(system.shares) do
        if share.share >= 0.005 or index == 1 and share.share > 0 or isShown[index] then
            table.insert(entries, {text = string.format("%s %s", share.name, pct(share.share)), color = getCauseColor(index)})
        end
    end
    if #entries == 1 then
        table.insert(entries, {text = "no wear yet"})
    end
    return entries
end

local function getLegendRows(system, w)
    local rows, cx = 1, 0
    for _, entry in ipairs(getLegend(system)) do
        local ew = (entry.color ~= nil and 15 or 0) + measure(entry.text, 14) + 18
        if cx > 0 and cx + ew > w then
            rows, cx = rows + 1, 0
        end
        cx = cx + ew
    end
    return rows
end

local function drawPartCard(system, x, y, w, h, pitch, headH)
    local ix, iw = x + 16, w - 32
    card(x, y, w, h)
    label(ix, y + 24, system.name, 20, COLOR.text, {bold = true})
    label(ix + iw, y + 24, pct(system.condition), 20, COLOR.text, {bold = true, align = RenderText.ALIGN_RIGHT})
    local tier = getRiskTier(system.risk)
    local risk = {text = string.format("risk %s ×%.1f", tier[1], system.risk), bold = true, color = tier[2]}
    local rw = chip(ix, y + 52, risk, 14)
    if system.wearing > 0 then
        label(ix + rw + 12, y + 52, "wearing " .. perHour(system.wearing), 15,
            system.wearing > system.normal * 1.3 and COLOR.yellow or COLOR.label)
    else
        label(ix + rw + 12, y + 52, "not wearing", 15, COLOR.dim)
    end
    label(ix + iw, y + 52, "normal " .. perHour(system.normal), 14, COLOR.dim, {align = RenderText.ALIGN_RIGHT})

    -- what wore the system, in the colours its parts use
    local lx, ly = ix, y + 80
    for _, entry in ipairs(getLegend(system)) do
        local ew = (entry.color ~= nil and 15 or 0) + measure(entry.text, 14) + 18
        if lx > ix and lx + ew > ix + iw then
            lx, ly = ix, ly + 20
        end
        if entry.color ~= nil then
            rect(lx, ly - 5, 10, 10, entry.color, 2)
        end
        label(lx + (entry.color ~= nil and 15 or 0), ly, entry.text, 14, entry.color ~= nil and COLOR.label or COLOR.text)
        lx = lx + ew
    end
    ly = ly + 16
    rect(ix, ly - 3, iw, 6, COLOR.track, 3)
    local total, bx = 0, ix
    for _, share in ipairs(system.shares) do
        total = total + share.share
    end
    for index, share in ipairs(system.shares) do
        local sw = total > 0 and iw * share.share / total or 0
        if sw > 0 then
            rect(bx, ly - 3, math.max(sw, 2), 6, getCauseColor(index))
        end
        bx = bx + sw
    end
    hairline(ix, y + headH - 6, iw)

    for index, part in ipairs(system.parts) do
        local cy = y + headH + (index - 1) * pitch + pitch / 2
        if index % 2 == 0 then
            rect(ix - 6, cy - pitch / 2, iw + 12, pitch, COLOR.stripe, 4)
        end
        local color = partColor(part)
        if part.strain then
            rect(ix - 12, cy - 3, 6, 6, COLOR.text, 3)
        end
        label(ix, cy, part.name, 16, color or COLOR.text, {box = 206})
        bar(ix + 214, cy - 3, 72, 6, part.wear, color or COLOR.bar, part.tick)
        label(ix + 338, cy, pct(part.wear), 15, COLOR.text, {bold = true, align = RenderText.ALIGN_RIGHT, box = 48})
        local sx = ix + 350
        if #part.causes == 0 then
            rect(sx, cy - 4, 36, 8, COLOR.track, 2)
        end
        for _, cause in ipairs(part.causes) do
            local sw = 36 * cause.share
            if sw > 0.2 then
                rect(sx, cy - 4, math.max(sw, 2), 8, getCauseColor(cause.cause))
            end
            sx = sx + sw
        end
        local chanceColor = color or (part.chance >= 0.1 and COLOR.yellow or nil)
        label(ix + iw, cy, chanceText(part), 15, chanceColor or COLOR.text, {bold = chanceColor ~= nil, align = RenderText.ALIGN_RIGHT, box = 52})
    end
end

local LEGEND_H = 30

local function legendText(x, y, text, color, bold)
    label(x, y, text, 14, color, {bold = bold})
    return measure(text, 14, bold)
end

---Keeps the place of a system the machine has not
local function drawAbsentCard(name, x, y, w, h)
    card(x, y, w, h)
    label(x + 16, y + 24, name, 20, COLOR.dim, {bold = true})
    label(x + 16, y + 52, "not followed on this machine", 15, COLOR.dim, {box = w - 32})
end

local function drawPartsLegend(reading, area, y)
    local ly = y + LEGEND_H / 2
    local lx = area.x
    rect(lx, ly - 3, 40, 6, COLOR.track, 3)
    rect(lx, ly - 3, 18, 6, COLOR.bar, 3)
    rect(lx + 28, ly - 8, 2, 16, COLOR.tick)
    lx = lx + 52
    lx = lx + legendText(lx, ly, string.format("wear, full after %.0f h of play at the normal pace; white mark: 1 in 10 of its kind failed by then",
        reading.legend.fullAfter), COLOR.label) + 28
    rect(lx, ly - 4, 24, 8, COLOR.normal)
    rect(lx + 18, ly - 4, 6, 8, CAUSE_COLORS[1])
    lx = lx + 34
    lx = lx + legendText(lx, ly, "what wore the part", COLOR.label) + 28
    lx = lx + legendText(lx, ly, string.format("chance: of failing in the next %.0f h, yellow from 10 %%", reading.legend.horizon), COLOR.label) + 28
    lx = lx + legendText(lx, ly, "risk: against the system new, as the inspection report", COLOR.label) + 28
    rect(lx, ly - 3, 6, 6, COLOR.text, 3)
    lx = lx + 12 + legendText(lx + 12, ly, "worn beyond its normal rate right now", COLOR.label) + 28
    lx = lx + legendText(lx, ly, "worn", COLOR.orange, true) + 20
    lx = lx + legendText(lx, ly, "failing", COLOR.red, true)
    if lx > area.x + area.w and not L.isMeasuring then
        table.insert(L.overflows, {text = "parts legend", width = lx - area.x, box = area.w})
    end
end

local PITCH_MIN, PITCH_MAX = 21, 26

local function drawParts(reading, area)
    local colW = (area.w - 3 * GAP) / 4
    local grid, placed = {}, {}
    for row, places in ipairs(PART_GRID) do
        grid[row] = {}
        for column, names in ipairs(places) do
            -- a place kept, named, for a system the machine has not
            local system = findSystem(reading, names)
            grid[row][column] = system or {absent = names[1]}
            if system ~= nil then
                placed[system] = true
            end
        end
    end
    -- a system without a place of its own goes on a row below
    local extra = 0
    for _, system in ipairs(reading.systems) do
        if not placed[system] then
            local row = #PART_GRID + 1 + math.floor(extra / 4)
            grid[row] = grid[row] or {}
            grid[row][extra % 4 + 1] = system
            extra = extra + 1
        end
    end
    local rowHead, rowParts = {}, {}
    local room, parts = area.bottom - area.y - LEGEND_H - 14 + GAP, 0
    for row = 1, #grid do
        rowHead[row], rowParts[row] = 100, 0
        for column = 1, 4 do
            local system = grid[row][column]
            if system ~= nil and system.absent == nil then
                rowHead[row] = math.max(rowHead[row], 100 + (getLegendRows(system, colW - 32) - 1) * 20)
                rowParts[row] = math.max(rowParts[row], #system.parts)
            end
        end
        room, parts = room - rowHead[row] - 12 - GAP, parts + rowParts[row]
    end
    local pitch = math.max(math.min(math.floor(room / math.max(parts, 1)), PITCH_MAX), PITCH_MIN)
    local y = area.y
    for row = 1, #grid do
        local h = rowHead[row] + rowParts[row] * pitch + 12
        for column = 1, 4 do
            local system, cardX = grid[row][column], area.x + (column - 1) * (colW + GAP)
            if system ~= nil and system.absent ~= nil then
                drawAbsentCard(system.absent, cardX, y, colW, h)
            elseif system ~= nil then
                drawPartCard(system, cardX, y, colW, h, pitch, rowHead[row])
            end
        end
        y = y + h + GAP
    end
    y = y - GAP + 14
    drawPartsLegend(reading, area, y)
    return y + LEGEND_H - area.y
end

local ROW = RMS_DebugReading.ROW
local LABEL_W, LINE = 100, 20

local function itemWidth(entry)
    return (entry.label ~= "" and measure(entry.label, 15) + 8 or 0) + measure(entry.value, 15, true)
end

---Draws a row of the machine view
-- @return float height
local function drawRow(row, x, y, w)
    local vx, vw = x + LABEL_W, w - LABEL_W
    label(x, y + LINE / 2, row.label, 15, COLOR.text, {bold = true, box = LABEL_W - 8})
    local cy = y + LINE / 2
    if row.kind == ROW.CLOCK then
        bar(vx, cy - 3, vw - 56, 6, row.level, row.overdue and COLOR.red or COLOR.bar, row.due)
        label(vx + vw, cy, pct(row.level), 15, COLOR.text, {bold = true, align = RenderText.ALIGN_RIGHT})
        label(vx, cy + LINE - 2, row.left, 14, row.overdue and COLOR.red or COLOR.label, {box = vw})
        return 2 * LINE - 2
    elseif row.kind == ROW.CHART then
        label(vx, cy, "net", 15, COLOR.label)
        label(vx + vw, cy, string.format("%s %s", row.net == 0 and "0.0" or string.format("%+.1f", row.net), row.unit), 15, COLOR.text,
            {bold = true, align = RenderText.ALIGN_RIGHT})
        cy = cy + LINE
        local max = 0.1
        for _, entry in ipairs(row.flows) do
            max = math.max(max, math.abs(entry.value))
        end
        local zone = vw - 92 - 52
        local mid = vx + 92 + zone / 2
        for _, entry in ipairs(row.flows) do
            label(vx, cy, entry.name, 15, COLOR.label, {box = 88})
            rect(mid - 0.5, cy - 8, 1, 16, COLOR.axis)
            local length = zone / 2 * math.abs(entry.value) / max
            if length > 0.5 then
                rect(entry.value > 0 and mid or mid - length, cy - 4, length, 8, entry.value > 0 and COLOR.heat or COLOR.blue, 2)
            end
            label(vx + vw, cy, entry.value == 0 and "0.0" or string.format("%+.1f", entry.value), 15, COLOR.text,
                {bold = true, align = RenderText.ALIGN_RIGHT})
            cy = cy + LINE
        end
        return cy - LINE / 2 - y
    elseif row.kind == ROW.GAUGES then
        if row.caption ~= "" then
            label(x, cy + 18, row.caption, 13, COLOR.dim)
        end
        for _, gauge in ipairs(row.gauges) do
            label(vx, cy, gauge.label, 15, COLOR.label, {box = 100})
            bar(vx + 104, cy - 3, vw - 104 - 52, 6, gauge.share, gauge.alert and COLOR.red or COLOR.bar)
            label(vx + vw, cy, gauge.value, 15, COLOR.text, {bold = true, align = RenderText.ALIGN_RIGHT})
            cy = cy + LINE
            if gauge.note ~= "" then
                for _, line in ipairs(wrapItems(splitItems(gauge.note), vw - 8, 13)) do
                    label(vx + 8, cy - 5, line, 13, gauge.alert and COLOR.red or COLOR.dim, {box = vw - 8})
                    cy = cy + 17
                end
            end
        end
        return cy - LINE / 2 - y
    end
    for _, entry in ipairs(row.items) do
        label(vx, cy, entry.label, 15, COLOR.label)
        if itemWidth(entry) <= vw then
            label(vx + vw, cy, entry.value, 15, COLOR.text, {bold = true, align = RenderText.ALIGN_RIGHT})
            cy = cy + LINE
        else
            if entry.label ~= "" then
                cy = cy + LINE
            end
            for _, line in ipairs(wrapWords(entry.value, vw, 15, true)) do
                label(vx + vw, cy, line, 15, COLOR.text, {bold = true, align = RenderText.ALIGN_RIGHT, box = vw})
                cy = cy + LINE
            end
        end
    end
    return cy - LINE / 2 - y
end

local COLUMNS = 5
local GROUP_TITLE, ROW_GAP, GROUP_GAP = 36, 6, 20

local function drawMachine(reading, area)
    local gap = 18
    local colW = (area.w - (COLUMNS - 1) * gap) / COLUMNS
    local iw = colW - 32
    local function column(index, isDrawn)
        local x = area.x + (index - 1) * (colW + gap) + 16
        local y = area.y + 14
        for _, group in ipairs(reading.machine) do
            if group.column == index then
                if y > area.y + 14 and isDrawn then
                    hairline(x, y - GROUP_GAP / 2, iw, COLOR.track)
                end
                if isDrawn then
                    title(x, y - 2, iw, group.title, group.note)
                end
                y = y + GROUP_TITLE
                for _, row in ipairs(group.rows) do
                    y = y + drawRow(row, x, y, iw) + ROW_GAP
                end
                y = y - ROW_GAP + GROUP_GAP
            end
        end
        return y - GROUP_GAP + 14 - area.y
    end
    local height = area.bottom - area.y
    for index = 1, COLUMNS do
        height = math.max(height, measureHeight(function() return column(index, false) end))
    end
    -- five frames of the same height, each column its groups
    for index = 1, COLUMNS do
        card(area.x + (index - 1) * (colW + gap), area.y, colW, height)
        column(index, true)
    end
    return height
end

-- the game's fill levels climb above its speed meter, a box each
local function getFillLevelsTop()
    local hud = g_currentMission.hud
    local display = hud ~= nil and hud.fillLevelsDisplay or nil
    local vehicle = RMS_DebugWindow.vehicle
    if display == nil or vehicle == nil or vehicle.getFillLevelInformation == nil or display.bgScale == nil then
        return math.huge
    end
    local seen, count = {}, 0
    vehicle:getFillLevelInformation({addFillLevel = function(_, fillType, _, _, _, _, typeId, _, infoText)
        local key = string.format("%s|%s|%s", tostring(fillType), tostring(typeId), tostring(infoText))
        if not seen[key] then
            seen[key], count = true, count + 1
        end
    end})
    if count == 0 then
        return math.huge
    end
    local _, baseY = display:getPosition()
    if hud.speedMeter ~= nil and hud.speedMeter:getVisible() then
        baseY = baseY + (display.offsetY or 0)
    end
    return toRefY(baseY + count * (display.bgScale.height + (display.boxOffsetY or 0)))
end

local VIEW_DRAW = {drawOverview, drawParts, drawMachine}

---Lays out the window for a reading, the views scrolled as kept
-- @param boolean isMouse the window holds the mouse
-- @return table commands to draw each frame
function RMS_DebugWindow.layout(reading, isMouse)
    setScreen()
    local window = RMS_DebugWindow
    local bottom = math.max(math.min(MAIN.bottom, getFillLevelsTop() - 12), MAIN.y + 2 * PAD + MIN_VIEWPORT)
    rect(MAIN.x, MAIN.y, MAIN.w, bottom - MAIN.y, COLOR.panel, 14)
    drawSidebar(reading, isMouse)
    window.scrollState = nil
    if reading == nil then
        window.hits, window.overflows = L.hits, L.overflows
        return L.commands
    end

    local view = window.view
    local area = {x = MAIN.x + PAD, y = MAIN.y + PAD, w = MAIN.w - 2 * PAD, bottom = bottom - PAD}
    local height = measureHeight(function() return VIEW_DRAW[view](reading, area) end)
    local viewport = area.bottom - area.y
    local maxScroll = math.max(height - viewport, 0)
    window.scroll[view] = math.min(math.max(window.scroll[view], 0), maxScroll)
    L.clip = {top = area.y, bottom = area.bottom, offset = window.scroll[view]}
    VIEW_DRAW[view](reading, area)
    L.clip = nil

    if maxScroll > 0 then
        -- the bar in the right padding, the view keeping its width
        window.scrollState = scrollBar("track", area.x + area.w + (PAD - SCROLL_W) / 2, area.y, viewport, height, window.scroll[view], isMouse)
    end
    window.hits, window.overflows = L.hits, L.overflows
    window.contentHeight, window.viewport = height, viewport
    return L.commands
end

local function render(commands)
    setTextVerticalAlignment(RenderText.VERTICAL_ALIGN_BASELINE)
    for _, command in ipairs(commands) do
        local color = command.color
        if command.text == nil then
            if command.clipY1 ~= nil then
                drawFilledRectRound(command.x, command.y, command.w, command.h, command.corner, color[1], color[2], color[3], color[4],
                    0, command.clipY1, 1, command.clipY2)
            else
                drawFilledRectRound(command.x, command.y, command.w, command.h, command.corner, color[1], color[2], color[3], color[4])
            end
        else
            setTextBold(command.bold)
            setTextColor(color[1], color[2], color[3], color[4])
            setTextAlignment(command.align)
            -- capitals centred on the line the layout gave
            renderText(command.x, command.y - CAP_HALF * command.size, command.size, command.text)
        end
    end
    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextBold(false)
    setTextColor(1, 1, 1, 1)
end

local function getReading(vehicle)
    if vehicle.isServer then
        return RMS_DebugReading.read(vehicle)
    end
    RMS_DebugReadingEvent.request(vehicle)
    local received = RMS_DebugReading.serverReading
    if received == nil or received.vehicle ~= vehicle or g_time - received.time > READING_LIFE_MS then
        return nil
    end
    return received.reading
end

---Tells whether the window holds the mouse
function RMS_DebugWindow.getIsMouse()
    return RMS_DebugScreen.INSTANCE ~= nil and RMS_DebugScreen.INSTANCE.isOpen == true
end

---Tells whether the window stays open
function RMS_DebugWindow.getIsOpen()
    return RMS_DebugWindow.isOpen
end

---Lays the window out again at the next frame
function RMS_DebugWindow.invalidate()
    RMS_DebugWindow.refreshTime = -math.huge
end

---Gives the mouse and the controls back; the window stays
function RMS_DebugWindow.releaseMouse()
    RMS_DebugWindow.wantsMouse = false
    RMS_DebugWindow.dragging, RMS_DebugWindow.dragTarget = nil, nil
    RMS_DebugWindow.hover = nil
    if RMS_DebugWindow.getIsMouse() then
        RMS_DebugScreen.INSTANCE:close()
    end
    RMS_DebugWindow.invalidate()
end

---Opens or closes the window of this player
-- @param boolean? withMouse the window takes the mouse as it opens
function RMS_DebugWindow.setOpen(isOpen, withMouse)
    local window = RMS_DebugWindow
    window.isOpen = isOpen
    if isOpen then
        window.wantsMouse = withMouse == true
    else
        window.releaseMouse()
    end
    window.invalidate()
end

---Opens the window with the mouse, or gives it the mouse while it shows
function RMS_DebugWindow.onToggleAction()
    if g_currentMission.isMasterUser then
        RMS_DebugWindow.setOpen(true, true)
    end
end

local function onRegisterGlobalPlayerActionEvents()
    local _, eventId = g_inputBinding:registerActionEvent(InputAction.RMS_TOGGLE_DEBUG_WINDOW, RMS_DebugWindow,
        RMS_DebugWindow.onToggleAction, false, true, false, true)
    g_inputBinding:setActionEventTextVisibility(eventId, false)
end
PlayerInputComponent.registerGlobalPlayerActionEvents = Utils.appendedFunction(PlayerInputComponent.registerGlobalPlayerActionEvents,
    onRegisterGlobalPlayerActionEvents)

---Hides the help box of the game under the window, then gives it back
local function setHelpHidden(isHidden)
    local hud = g_currentMission.hud
    if hud.inputHelp == nil or isHidden == (RMS_DebugWindow.helpWasVisible ~= nil) then
        return
    end
    if isHidden then
        RMS_DebugWindow.helpWasVisible = hud.inputHelp:getVisible()
        hud:setInputHelpVisible(false)
    else
        hud:setInputHelpVisible(RMS_DebugWindow.helpWasVisible)
        RMS_DebugWindow.helpWasVisible = nil
    end
end

local function getIsShown(vehicle)
    local spec = vehicle ~= nil and vehicle.spec_RealisticMechanicalSystems or nil
    return RMS_DebugWindow.isOpen and g_currentMission.isMasterUser and spec ~= nil and not spec.isExcludedVehicle
end

local function refresh(vehicle, isMouse)
    local window = RMS_DebugWindow
    if vehicle ~= window.vehicle or g_time >= window.refreshTime then
        window.vehicle = vehicle
        window.reading = getReading(vehicle)
        window.refreshTime = g_time + REFRESH_MS
        window.commands = nil
    end
    if window.commands == nil or window.layoutIsMouse ~= isMouse then
        window.commands = RMS_DebugWindow.layout(window.reading, isMouse)
        window.layoutIsMouse = isMouse
    end
end

---Gives the window the mouse once no screen of the game shows
function RMS_DebugWindow.update()
    local window = RMS_DebugWindow
    if window.wantsMouse and not g_gui:getIsGuiVisible() then
        window.wantsMouse = false
        if getIsShown(RMS_Main.hud ~= nil and RMS_Main.hud.vehicle or nil) then
            window.invalidate()
            g_gui:showDialog("RMS_DebugScreen")
        end
    end
end

---Draws the window from the HUD, while the player drives
function RMS_DebugWindow.draw(vehicle)
    local isShown = getIsShown(vehicle)
    setHelpHidden(isShown)
    if not isShown then
        return
    end
    refresh(vehicle, false)
    render(RMS_DebugWindow.commands)
end

---Draws the window from its screen, while it holds the mouse
function RMS_DebugWindow.drawMouse()
    local vehicle = RMS_Main.hud ~= nil and RMS_Main.hud.vehicle or nil
    if not getIsShown(vehicle) then
        RMS_DebugWindow.releaseMouse()
        return
    end
    refresh(vehicle, true)
    render(RMS_DebugWindow.commands)
end

local function findHit(x, y)
    for _, area in ipairs(RMS_DebugWindow.hits) do
        if x >= area.x and x <= area.x + area.w and y >= area.y and y <= area.y + area.h then
            return area
        end
    end
    return nil
end

-- the game measures texts as it draws them only while it draws
local function relayout()
    RMS_DebugWindow.commands = nil
end

local function getScrollState(kind)
    local window = RMS_DebugWindow
    return kind == "sideTrack" and window.sideState or window.scrollState
end

---Scrolls the sheet or the view a track belongs to
local function scrollTo(kind, value)
    local window = RMS_DebugWindow
    value = math.min(math.max(value, 0), getScrollState(kind).maxScroll)
    if kind == "sideTrack" then
        window.sideScroll = value
    else
        window.scroll[window.view] = value
    end
    relayout()
end

local function dragTo(y)
    local window = RMS_DebugWindow
    local state = getScrollState(window.dragTarget)
    if state == nil then
        return
    end
    local share = (y - window.dragging - state.top) / math.max(state.viewport - state.thumbH, 1)
    scrollTo(window.dragTarget, math.min(math.max(share, 0), 1) * state.maxScroll)
end

---Handles the mouse while the window holds it
function RMS_DebugWindow.onMouseEvent(posX, posY, isDown, isUp, button)
    local window = RMS_DebugWindow
    if L.unit == nil then
        return
    end
    local x, y = toRefX(posX), toRefY(posY)
    if isDown and button == Input.MOUSE_BUTTON_RIGHT then
        window.releaseMouse()
        return
    end
    if isDown and (button == Input.MOUSE_BUTTON_WHEEL_UP or button == Input.MOUSE_BUTTON_WHEEL_DOWN) then
        -- over the side panel the sheet scrolls, if it can
        local isSide = x < SIDE.x + SIDE.w and window.sideState ~= nil
        local step = button == Input.MOUSE_BUTTON_WHEEL_UP and -WHEEL_STEP or WHEEL_STEP
        if isSide then
            scrollTo("sideTrack", window.sideScroll + step)
        elseif window.scrollState ~= nil then
            scrollTo("track", window.scroll[window.view] + step)
        end
        return
    end
    if window.dragging ~= nil then
        if isUp and button == Input.MOUSE_BUTTON_LEFT then
            window.dragging, window.dragTarget = nil, nil
            relayout()
        else
            dragTo(y)
        end
        return
    end

    local area = findHit(x, y)
    local hover = area ~= nil and area.kind .. tostring(area.value or "") or nil
    if hover ~= window.hover then
        window.hover = hover
        relayout()
    end
    if not isDown or button ~= Input.MOUSE_BUTTON_LEFT or area == nil then
        return
    end
    if area.kind == "view" then
        window.view = area.value
        relayout()
    elseif area.kind == "close" then
        window.setOpen(false)
    elseif (area.kind == "track" or area.kind == "sideTrack") and getScrollState(area.kind) ~= nil then
        local state = getScrollState(area.kind)
        window.dragTarget = area.kind
        if y >= state.thumbY and y <= state.thumbY + state.thumbH then
            window.dragging = y - state.thumbY
        else
            window.dragging = state.thumbH / 2
            dragTo(y)
        end
    end
end
