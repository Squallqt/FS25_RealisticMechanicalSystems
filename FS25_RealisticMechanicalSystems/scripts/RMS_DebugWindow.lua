-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---Vehicle debug window.
RMS_DebugWindow = {}

local REFRESH_MS = 500
local READING_LIFE_MS = 2 * REFRESH_MS
local SEP = "  ·  "

local SCREEN_W, SCREEN_H = 2560, 1440
local PANEL_X, PANEL_Y, PANEL_W, PANEL_H = 40, 140, 2480, 920
local LEFT, WIDTH = 56, 2448
local ZONE_TOP, CONTENT_TOP, BOTTOM = 238, 274, 1048
local CARD_W, CARD_GAP, CARD_PAD, PARTS_TOP = 344, 12, 12, 118
local PART_PITCH, PART_PITCH_MIN = 21, 18
local NAME_W, BAR_W, WEAR_W, RISK_W = 184, 30, 42, 52
local PARTS_W = 4 * CARD_W + 3 * CARD_GAP
local MIDDLE_X, MIDDLE_W = LEFT + PARTS_W + 20, 440
local MACHINE_X = MIDDLE_X + MIDDLE_W + 20
local MACHINE_W = LEFT + WIDTH - MACHINE_X
local MACHINE_LABEL_W = 90
local SPACING_MIN = 0.8
local CHANCE_HIGH = 0.1

local COLOR = {
    panel = {0.0037, 0.0037, 0.0037, 0.86},
    card = {1, 1, 1, 0.045},
    line = {1, 1, 1, 0.10},
    track = {1, 1, 1, 0.13},
    text = {0.8963, 0.9216, 0.8148, 1},
    label = {0.3663, 0.3763, 0.3372, 1},
    dim = {0.1746, 0.1812, 0.159, 1},
    ok = {0.3005, 0.7011, 0, 1},
    yellow = {0.8469, 0.7758, 0.2016, 1},
    orange = {0.8469, 0.5029, 0.15, 1},
    red = {0.8796, 0.1812, 0.1812, 1},
    bar = {0.5841, 0.5972, 0.521, 1},
    tick = {0.8963, 0.9216, 0.8148, 0.85}
}

RMS_DebugWindow.vehicle = nil
RMS_DebugWindow.refreshTime = -math.huge
RMS_DebugWindow.commands = nil

local L = {}

---Fits the debug layout to the screen.
local function setScreen()
    local scale = math.min(g_gameSettings:getValue(GameSettings.SETTING.UI_SCALE), 1)
    L.unit = math.min(g_screenHeight / SCREEN_H * scale, g_screenWidth * 0.98 / PANEL_W)
    L.left = (g_screenWidth - SCREEN_W * L.unit) / 2
    L.commands = {}
    L.isMeasuring = false
end

---Converts a layout x coordinate to screen space.
local function screenX(x)
    return (L.left + x * L.unit) / g_screenWidth
end

---Converts a layout y coordinate to screen space.
local function screenY(y)
    return 1 - y * L.unit / g_screenHeight
end

---Converts a layout text size to screen space.
local function textSize(px)
    return px * L.unit / g_screenHeight
end

---Returns text width in layout pixels.
local function measure(text, px, bold)
    setTextBold(bold == true)
    local width = getTextWidth(textSize(px), text) * g_screenWidth / L.unit
    setTextBold(false)
    return width
end

---Adds a filled rectangle
local function rect(x, y, w, h, color, isRound)
    if L.isMeasuring then
        return
    end
    table.insert(L.commands, {x = screenX(x), y = screenY(y + h), w = w * L.unit / g_screenWidth, h = h * L.unit / g_screenHeight,
        color = color, isRound = isRound})
end

local function label(x, y, w, h, text, px, color, bold, align)
    if L.isMeasuring or text == "" then
        return
    end
    align = align or RenderText.ALIGN_LEFT
    if measure(text, px, bold) > w then
        setTextBold(bold == true)
        text = Utils.limitTextToWidth(text, textSize(px), w * L.unit / g_screenWidth, false, "...")
        setTextBold(false)
    end
    local anchor = align == RenderText.ALIGN_RIGHT and x + w or align == RenderText.ALIGN_CENTER and x + w / 2 or x
    table.insert(L.commands, {x = screenX(anchor), y = screenY(y + h / 2), size = textSize(px), text = text, color = color,
        bold = bold == true, align = align})
end

---Parts a row into its items
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

local function wrap(text, w, px, bold)
    local lines, line = {}, nil
    for _, item in ipairs(splitItems(text)) do
        local joined = line == nil and item or line .. SEP .. item
        if line ~= nil and measure(joined, px, bold) > w then
            table.insert(lines, line)
            line = item
        else
            line = joined
        end
    end
    table.insert(lines, line)
    return lines
end

---Adds a bar filled to a share, with the tick of a share on it
local function bar(x, y, w, h, share, color, tick)
    rect(x, y, w, h, COLOR.track)
    rect(x, y, math.max(w * math.min(share, 1), 2), h, color)
    if tick ~= nil and tick >= 0 then
        rect(x + w * tick - 1, y - 3, 2, h + 6, COLOR.tick)
    end
end

---Adds the title of a zone, its accent and its rule
local function title(x, y, w, text, right)
    rect(x, y + 4, 4, 20, HUD.COLOR.ACTIVE)
    label(x + 14, y, w - 14, 28, text:upper(), 17, HUD.COLOR.ACTIVE, true)
    if right ~= nil then
        label(x + 160, y, w - 160, 28, right, 14, COLOR.label, false, RenderText.ALIGN_RIGHT)
    end
    rect(x, y + 31, w, 1, COLOR.line)
end

---Risk colour against new: red from x2, yellow from x1.5
local function riskColor(risk)
    return risk >= 2 and COLOR.red or risk >= 1.5 and COLOR.yellow or COLOR.ok
end

local NOTE_H = 20

local function placeBlocks(blocks, x, w, top)
    local heights, total = {}, 0
    L.isMeasuring = true
    for index, block in ipairs(blocks) do
        heights[index] = block.draw(top, 1)
        total = total + heights[index]
    end
    L.isMeasuring = false
    local spacing = math.max(math.min((BOTTOM - top) / math.max(total, 1), 1), SPACING_MIN)

    local fitting = #blocks
    if total * spacing > BOTTOM - top then
        fitting = 0
        local used = 0
        for index = 1, #blocks do
            if used + heights[index] * spacing > BOTTOM - top - NOTE_H then
                break
            end
            used = used + heights[index] * spacing
            fitting = index
        end
    end

    local y = top
    for index = 1, fitting do
        y = y + blocks[index].draw(y, spacing)
    end
    local left = 0
    for index = fitting + 1, #blocks do
        left = left + (blocks[index].isGap and 0 or 1)
    end
    if left > 0 then
        label(x, BOTTOM - NOTE_H, w, NOTE_H, string.format("%d more rows below the window", left), 14, COLOR.dim)
    end
end

---Block of rows; a long value wraps under its label
local function rowBlocks(blocks, rows, x, w, labelW, pitch, px)
    for _, row in ipairs(rows) do
        table.insert(blocks, {draw = function(y, spacing)
            local lines = wrap(row[2], w - labelW - 4, px)
            local step = pitch * spacing
            label(x, y, labelW, step, row[1], px, COLOR.label)
            for index, line in ipairs(lines) do
                label(x + labelW + 4, y + (index - 1) * step, w - labelW - 4, step, line, px, COLOR.text)
            end
            return #lines * step
        end})
    end
end

---A block of space between two parts of a column
local function gapBlock(blocks, height)
    table.insert(blocks, {isGap = true, draw = function(_, spacing)
        return height * spacing
    end})
end

---Adds a line of facts, each label followed by its value
local function addFacts(x, y, items, lead)
    if lead ~= nil then
        label(x, y, 100, 22, lead, 15, HUD.COLOR.ACTIVE, true)
        x = x + 104
    end
    for _, item in ipairs(items) do
        local labelW, valueW = math.ceil(measure(item[1], 15)) + 8, math.ceil(measure(item[2], 15, true)) + 30
        label(x, y, labelW, 22, item[1], 15, COLOR.label)
        label(x + labelW, y, valueW, 22, item[2], 15, COLOR.text, true)
        x = x + labelW + valueW
    end
end

---Returns the most parts a card holds on each row of cards
local function getRowParts(cards)
    local shown = {0, 0}
    for position, card in ipairs(cards) do
        local row = position <= 4 and 1 or 2
        shown[row] = math.max(shown[row], #card.system.parts)
    end
    return shown
end

local function addCards(systems)
    local cards = {}
    for index, system in ipairs(systems) do
        table.insert(cards, {system = system, index = index})
    end
    local room = BOTTOM - CONTENT_TOP - CARD_GAP - 2 * (PARTS_TOP + 8)
    local shown = getRowParts(cards)
    if shown[1] + shown[2] > math.floor(room / PART_PITCH) then
        table.sort(cards, function(a, b)
            if #a.system.parts ~= #b.system.parts then
                return #a.system.parts > #b.system.parts
            end
            return a.index < b.index
        end)
        shown = getRowParts(cards)
    end

    local pitch = math.max(math.min(room / math.max(shown[1] + shown[2], 1), PART_PITCH), PART_PITCH_MIN)
    local capacity = math.floor(room / pitch)
    if shown[1] + shown[2] > capacity then
        shown[2] = math.min(shown[2], math.floor(capacity / 2))
        shown[1] = capacity - shown[2]
    end

    local rowTop = {CONTENT_TOP, CONTENT_TOP + PARTS_TOP + pitch * shown[1] + 8 + CARD_GAP}
    for position, card in ipairs(cards) do
        local row = position <= 4 and 1 or 2
        local s = card.system
        local x, y = LEFT + ((position - 1) % 4) * (CARD_W + CARD_GAP), rowTop[row]
        local inner = CARD_W - 2 * CARD_PAD
        local left = x + CARD_PAD
        rect(x, y, CARD_W, PARTS_TOP + pitch * shown[row] + 8, COLOR.card, true)
        label(left, y + 6, inner - 70, 26, s.name, 17, COLOR.text, true)
        label(left + inner - 70, y + 6, 70, 26, string.format("%d %%", math.floor(s.condition * 100 + 0.5)), 17, COLOR.text, true,
            RenderText.ALIGN_RIGHT)
        label(left, y + 32, inner, 22, string.format("risk x%.1f", s.risk), 15, riskColor(s.risk))
        local wearing = s.wearing > 0 and string.format("wearing %.2f %%/h  (normal %.2f)", s.wearing, s.normal) or "not wearing"
        label(left, y + 32, inner, 22, wearing, 15, s.wearing > s.normal * 1.3 and COLOR.yellow or COLOR.label, false,
            RenderText.ALIGN_RIGHT)
        for index, line in ipairs(wrap(s.since, inner, 14)) do
            label(left, y + 54 + (index - 1) * 20, inner, 20, line, 14, COLOR.label)
        end

        local barX = left + NAME_W + 4
        local wearX = barX + BAR_W + 4
        local riskX = wearX + WEAR_W + 4
        label(left, y + 96, NAME_W, 16, "part", 13, COLOR.dim)
        label(wearX, y + 96, WEAR_W, 16, "wear", 13, COLOR.dim, false, RenderText.ALIGN_RIGHT)
        label(riskX, y + 96, RISK_W, 16, "chance", 13, COLOR.dim, false, RenderText.ALIGN_RIGHT)
        rect(left, y + 114, inner, 1, COLOR.line)

        local fitting = #s.parts > shown[row] and shown[row] - 1 or #s.parts
        for index = 1, fitting do
            local part = s.parts[index]
            local partY = y + PARTS_TOP + (index - 1) * pitch
            local color = part.stage > 0 and COLOR.red or part.isWorn and COLOR.orange or nil
            label(left, partY, NAME_W, pitch, part.name, 15, color or COLOR.text)
            bar(barX, partY + pitch / 2 - 3, BAR_W, 6, part.wear, color or COLOR.bar, part.tick)
            label(wearX, partY, WEAR_W, pitch, string.format("%d%%", math.floor(part.wear * 100 + 0.5)), 15, COLOR.text, true,
                RenderText.ALIGN_RIGHT)
            local percent = math.floor(part.chance * 1000 + 0.5) / 10
            local chance = part.stage > 0 and "failing" or percent == 0 and "<0.1%" or string.format("%.1f%%", percent)
            local chanceColor = color or part.chance >= CHANCE_HIGH and COLOR.yellow or nil
            label(riskX, partY, RISK_W, pitch, chance, 15, chanceColor or COLOR.text, chanceColor ~= nil, RenderText.ALIGN_RIGHT)
        end
        if fitting < #s.parts then
            label(left, y + PARTS_TOP + fitting * pitch, inner, pitch, string.format("%d more, at lower risk", #s.parts - fitting), 14,
                COLOR.dim)
        end
    end
end

local function addMiddle(reading)
    local blocks = {}
    local x, w = MIDDLE_X, MIDDLE_W
    if #reading.work > 0 then
        title(x, ZONE_TOP, w, "Work in progress")
        rowBlocks(blocks, reading.work, x, w, 104, 23, 15)
    else
        title(x, ZONE_TOP, w, "Wear now", "% of life per hour of play")
        table.insert(blocks, {draw = function(y, spacing)
            label(x, y, w, 22 * spacing, "Extra wear right now, on top of the normal rate", 14, COLOR.dim)
            return 26 * spacing
        end})
        if #reading.wearNow == 0 then
            table.insert(blocks, {draw = function(y, spacing)
                label(x, y, w, 24 * spacing, "Nothing on top of the normal rate", 15, COLOR.label)
                return 28 * spacing
            end})
        end
        for _, system in ipairs(reading.wearNow) do
            table.insert(blocks, {draw = function(y, spacing)
                label(x, y, w, 24 * spacing, system.system, 16, COLOR.text, true)
                return 25 * spacing
            end})
            for _, cause in ipairs(system.causes) do
                table.insert(blocks, {draw = function(y, spacing)
                    local h = 23 * spacing
                    label(x + 14, y, 172, h, cause.label, 15, COLOR.text)
                    label(x + 190, y, 170, h, cause.measure, 14, COLOR.label)
                    label(x + 364, y, 76, h, string.format("+%.2f %%/h", cause.rate), 14, COLOR.text, true, RenderText.ALIGN_RIGHT)
                    return h
                end})
            end
            gapBlock(blocks, 6)
        end
    end

    gapBlock(blocks, 8)
    table.insert(blocks, {draw = function(y, spacing)
        title(x, y, w, "Faults", #reading.faults > 0 and string.format("%d active", #reading.faults) or "none")
        return 40 * spacing
    end})
    for _, fault in ipairs(reading.faults) do
        table.insert(blocks, {draw = function(y, spacing)
            local color = fault.isSeen and COLOR.red or COLOR.orange
            local nextW = math.ceil(measure(fault.next, 14)) + 8
            label(x, y, w - nextW, 24 * spacing, fault.name, 16, color, true)
            label(x + w - nextW, y, nextW, 24 * spacing, fault.next, 14, COLOR.text, false, RenderText.ALIGN_RIGHT)
            local lines = wrap(fault.info, w, 13)
            for index, line in ipairs(lines) do
                label(x, y + (24 + (index - 1) * 19) * spacing, w, 19 * spacing, line, 13, COLOR.label)
            end
            return (24 + #lines * 19 + 6) * spacing
        end})
    end
    rowBlocks(blocks, reading.alerts, x, w, 88, 24, 15)
    placeBlocks(blocks, x, w, CONTENT_TOP)
end

-- @param table? reading reading
-- @return table commands rectangles and texts to draw
function RMS_DebugWindow.layout(reading)
    setScreen()
    rect(PANEL_X, PANEL_Y, PANEL_W, PANEL_H, COLOR.panel, true)
    label(LEFT + 4, PANEL_Y + 8, 140, 30, "RMS DEBUG", 20, HUD.COLOR.ACTIVE, true)
    label(LEFT + WIDTH - 880, PANEL_Y + 10, 880, 26, RMS_Utils.getPrimaryKeyboardInputText("RMS_TOGGLE_DEBUG_WINDOW", "Alt Gr + F5")
        .. "  close", 15, COLOR.dim, false, RenderText.ALIGN_RIGHT)
    if reading == nil then
        label(LEFT + 154, PANEL_Y + 8, 1400, 30, "Waiting for the server", 20, COLOR.label, true)
        return L.commands
    end
    label(LEFT + 154, PANEL_Y + 8, 1400, 30, reading.title, 20, COLOR.text, true)
    addFacts(LEFT + 4, PANEL_Y + 40, reading.facts)
    addFacts(LEFT + 4, PANEL_Y + 62, reading.service, "Service")
    rect(LEFT, PANEL_Y + 90, WIDTH, 1, COLOR.line)

    local normal = reading.systems[1].normal
    title(LEFT, ZONE_TOP, PARTS_W, "Parts", string.format("bar: wear, full after %.0f h of play at the normal pace  ·  white tick: 1 in 10 "
        .. "of its kind failed by then  ·  chance: of failing in the next %.0f h, lamps lit half of it, yellow from 10 %%  ·  orange worn  ·  "
        .. "red failing", 100 / normal,
        RMS_Config.CORE.RISK_HORIZON_WEAR * 100 / normal))
    addCards(reading.systems)
    addMiddle(reading)

    title(MACHINE_X, ZONE_TOP, MACHINE_W, "Machine")
    local blocks = {}
    local machineRows = {}
    for _, row in ipairs(reading.machine) do
        if row[1] == "Warranty" or row[1] == "Part cover" or row[1] == "Used cover" then table.insert(machineRows, row) end
    end
    for _, row in ipairs(reading.machine) do
        if row[1] ~= "Warranty" and row[1] ~= "Part cover" and row[1] ~= "Used cover" then table.insert(machineRows, row) end
    end
    rowBlocks(blocks, machineRows, MACHINE_X, MACHINE_W, MACHINE_LABEL_W, 22, 15)
    placeBlocks(blocks, MACHINE_X, MACHINE_W, CONTENT_TOP)
    return L.commands
end

---Draws the commands of the last layout
local function render(commands)
    setTextVerticalAlignment(RenderText.VERTICAL_ALIGN_MIDDLE)
    for _, command in ipairs(commands) do
        local color = command.color
        if command.text == nil then
            if command.isRound then
                drawFilledRectRound(command.x, command.y, command.w, command.h, 0.25, color[1], color[2], color[3], color[4])
            else
                drawFilledRect(command.x, command.y, command.w, command.h, color[1], color[2], color[3], color[4])
            end
        else
            setTextBold(command.bold)
            setTextColor(color[1], color[2], color[3], color[4])
            setTextAlignment(command.align)
            renderText(command.x, command.y, command.size, command.text)
        end
    end
    setTextVerticalAlignment(RenderText.VERTICAL_ALIGN_BASELINE)
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

---Tells whether the window stays open; starts from the saved debug mode
-- @return boolean isOpen true while open
function RMS_DebugWindow.getIsOpen()
    if RMS_DebugWindow.isOpen == nil then
        RMS_DebugWindow.isOpen = g_currentMission:getIsServer() and RMS_Config.DEBUG
    end
    return RMS_DebugWindow.isOpen
end

---Opens or closes the window of an admin
function RMS_DebugWindow.onToggleAction()
    if g_currentMission.isMasterUser then
        RMS_DebugWindow.isOpen = not RMS_DebugWindow.getIsOpen()
    end
end

---Registers the key among the game's global player keys
local function onRegisterGlobalPlayerActionEvents()
    local _, eventId = g_inputBinding:registerActionEvent(InputAction.RMS_TOGGLE_DEBUG_WINDOW, RMS_DebugWindow,
        RMS_DebugWindow.onToggleAction, false, true, false, true)
    g_inputBinding:setActionEventTextVisibility(eventId, false)
end
PlayerInputComponent.registerGlobalPlayerActionEvents = Utils.appendedFunction(PlayerInputComponent.registerGlobalPlayerActionEvents,
    onRegisterGlobalPlayerActionEvents)

-- @param table? vehicle machine the HUD shows
function RMS_DebugWindow.draw(vehicle)
    if not RMS_DebugWindow.getIsOpen() or not g_currentMission.isMasterUser or vehicle == nil then
        return
    end
    local spec = vehicle.spec_RealisticMechanicalSystems
    if spec == nil or spec.isExcludedVehicle then
        return
    end

    local window = RMS_DebugWindow
    if vehicle ~= window.vehicle or g_time >= window.refreshTime then
        local commands = RMS_DebugWindow.layout(getReading(vehicle))
        window.vehicle, window.refreshTime, window.commands = vehicle, g_time + REFRESH_MS, commands
    end
    render(window.commands)
end
