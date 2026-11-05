-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---Vehicle dashboard and notifications.
RMS_Hud = {}
local RMS_Hud_mt = Class(RMS_Hud, HUDDisplay)

RMS_Hud.COLOR_GAME_GREEN = HUD.COLOR.ACTIVE
RMS_Hud.INSPECTION_RING_SIZE = 138
RMS_Hud.INSPECTION_PERCENT_SHARE = 0.22
RMS_Hud.INSPECTION_SHADE_ALPHA = 0.55
RMS_Hud.INSPECTION_LABEL_SIZE = 17
RMS_Hud.CONSUMPTION_REFRESH_INTERVAL = 500
RMS_Hud.CONSUMPTION_PER_AREA_BUCKETS = 10
RMS_Hud.MOTOR_LOAD_BUCKETS = 2
RMS_Hud.GEARBOX_OIL_ALERT_TEMP = { DEFAULT = 105, TRUCK = 121 }
RMS_Hud.NOTIFICATION_DURATION_MS = 3000
RMS_Hud.LAMP_BLINK = { PHASE_MS = 500, SHORT_PHASES = 8 }
RMS_Hud.LIT_LAMP_COLOR = { oil = "CRITICAL", battery = "CRITICAL", coolant = "CRITICAL", engine = "WARNING",
    preheat = "WARNING", dpf = "WARNING", service = "WARNING", tractionBattery = "WARNING", limitedPower = "WARNING" }
RMS_Hud.LAMP_BEEP_PAUSE_MS = { DEFAULT = 1800, warning = 1400, service = 2500 }
RMS_Hud.CONDITION_BAR = { FILL_MIN = 0.1, FILL_BY_TIER = { 1, 0.75, 0.5, 0.25, 0.1 } }
RMS_Hud.ARC_ORDER = { "brakes", "engine", "dpf", "coolant", "fanReversal", "transmission", "battery" }
RMS_Hud.INDICATOR_ORDER = { "transmission", "engine", "brakes", "battery", "coolant", "dpf", "fanReversal", "preheat",
    "oil", "service", "tractionBattery", "limitedPower", "warning" }
RMS_Hud.LAMP_SLICE = { transmission = "transmissionTemperature", dpf = "particulateFilter", oil = "oilPressure" }
RMS_Hud.ROAD_LAMP_SLICE = { oil = "oilCan", coolant = "coolantRoad", service = "wrench" }
RMS_Hud.MACHINE_LAMP_SLICE = { service = "wrench" }
-- Lamp ink on its 72 px cell: width, height, px below the ink
RMS_Hud.LAMP_INK = {
    brakes = { 59, 43, 15 }, battery = { 59, 43, 15 }, preheat = { 58, 35, 19 }, warning = { 60, 53, 10 },
    transmissionTemperature = { 60, 60, 6 }, engine = { 42, 54, 9 }, engineClassic = { 59, 44, 14 },
    oilPressure = { 68, 54, 9 }, coolant = { 61, 59, 7 }, service = { 60, 36, 18 }, limitedPower = { 60, 31, 21 },
    tractionBattery = { 58, 43, 15 }, particulateFilter = { 58, 43, 15 }, fanReversal = { 48, 60, 6 },
    oilCan = { 60, 22, 25 }, coolantRoad = { 60, 52, 10 }, wrench = { 60, 56, 8 }
}
RMS_Hud.LAMP = { SIZE = 19.2, CELL = 72, VALUE_SIZE = 9, VALUE_GAP = 2.5, VALUE_TOP = 2.05, VALUE_HEIGHT = 6.7 }
RMS_Hud.LAMP_SCALE = { preheat = 1.2516, oilCan = 1.5521, limitedPower = 1.3075, tractionBattery = 1.1292,
    service = 1.2134, wrench = 0.9728 }
RMS_Hud.VALUE_WIDTH = { engine = 24.71, coolant = 25.61, transmission = 25.61, battery = 24.87 }
-- Reference px from the gauge centre, baked into hud/rms_hud.dds
RMS_Hud.CELL = { IN = 113, RADIUS = 129.8, OUT = 146, MARGIN = 2, SPACE = 2.4, HALF_MIN = 3, HALF_MAX = 10,
    HALF_STEP = 0.2, EXTENT = { -147, -26.3526, -110.2833, 26.3526 }, BOX = { -173.5, -45, -83.5, 45 }, ALPHA = 0.62 }
RMS_Hud.BACKGROUND = { BOX = { -180, -116, 0, 116 }, EDGE = 161.584, CORNER = 17.8 }
RMS_Hud.GAUGE = { IN = 149, OUT = 155.5, SPAN = 39, PITCH = 5.2, GAP = 1.2, LOW = 40, HIGH = 120, GLOW = 11,
    GLOW_ALPHA = 0.22, UNLIT_ALPHA = 0.75, BAND_IN = 156.5, BAND_OUT = 158,
    BAR_EXTENT = { -3.75, -2.4908, 3.75, 2.4908 }, BAR_BOX = { -6.25, -6.25, 6.25, 6.25 },
    BAND_EXTENT = { -1.25, -3.3259, 1.25, 3.3259 }, BAND_BOX = { -4.75, -4.75, 4.75, 4.75 } }
RMS_Hud.GAUGE_GREY = { 0.3049, 0.3049, 0.3049 }
RMS_Hud.GAUGE_LIT = { 1, 1, 1 }
RMS_Hud.ROW = { PITCH = 28 }
RMS_Hud.PICTURE_SCALE = 19 / 72
local bubbleScale = 1.2
RMS_Hud.BUBBLE = { RADIUS = 20 * bubbleScale, DARK_RADIUS = 16.5 * bubbleScale, SYMBOL_GAP = 2.5 * bubbleScale,
    VALUE_SIZE = 8 * bubbleScale, VALUE_HEIGHT = 5.95 * bubbleScale, VALUE_TOP_ABOVE_ANCHOR = 1.82 * bubbleScale,
    PICTURE_SCALE = RMS_Hud.PICTURE_SCALE * bubbleScale, X = -155.6427, POD_BOX = 21 }
RMS_Hud.DRIVE_INK_HEIGHT = { frontWheelDrive = 35 * RMS_Hud.BUBBLE.PICTURE_SCALE, diffLock = 48 * RMS_Hud.BUBBLE.PICTURE_SCALE }
RMS_Hud.WHEEL_SLIP_INK_HEIGHT = 41 * RMS_Hud.BUBBLE.PICTURE_SCALE
RMS_Hud.GLOW = { SIZE = 30.4, ALPHA = 0.35 }
RMS_Hud.PARK_BRAKE = { SIZE = 27.6, GAP = 5.5 }
-- INK: ink left, right and weight centre from the top, slice px
RMS_Hud.FUEL_ICON = { SIZE = 21, CELL = 30, GAP = 6,
    INK = { ["gui.icon_fuel"] = { 8, 23, 16.94 }, ["gui.icon_electricCharge"] = { 2, 28, 15.51 },
        ["gui.icon_methane"] = { 8, 22, 15.59 } } }

local lampLayouts = {}

local function getLampSpan(unit, phi, radius)
    local lamp = RMS_Hud.LAMP
    local boxes = { { -unit.inkWidth * 0.5, -unit.inkHeight * 0.5, unit.inkWidth * 0.5, unit.inkHeight * 0.5 } }
    if unit.valueWidth ~= nil then
        local top = -unit.inkHeight * 0.5 - lamp.VALUE_GAP
        boxes[2] = { -unit.valueWidth * 0.5, top - lamp.VALUE_HEIGHT, unit.valueWidth * 0.5, top }
    end
    local cx, cy = radius * math.cos(phi), radius * math.sin(phi)
    local low, high, near, far = math.huge, -math.huge, math.huge, 0
    for _, box in ipairs(boxes) do
        for _, x in ipairs({ box[1], box[3] }) do
            for _, y in ipairs({ box[2], box[4] }) do
                local px, py = cx + x, cy + y
                local angle = (math.atan2(py, px) - phi + math.pi) % (2 * math.pi) - math.pi
                low, high = math.min(low, angle), math.max(high, angle)
                local r = math.sqrt(px * px + py * py)
                near, far = math.min(near, r), math.max(far, r)
            end
        end
    end
    return low, high, near, far
end

local function getCellHalf(half)
    local cell = RMS_Hud.CELL
    local steps = math.ceil((math.deg(half) - cell.HALF_MIN) / cell.HALF_STEP - 1e-6)
    return math.rad(math.min(cell.HALF_MAX, cell.HALF_MIN + math.max(0, steps) * cell.HALF_STEP))
end

---Places the lamp cells left of the dial
function RMS_Hud.getLampLayout(units)
    local keys = {}
    for index, unit in ipairs(units) do
        keys[index] = string.format("%s:%.3f:%.3f:%s", unit.id, unit.inkWidth, unit.inkHeight, tostring(unit.valueWidth))
    end
    local key = table.concat(keys, ";")
    if lampLayouts[key] == nil then
        local cell = RMS_Hud.CELL
        local radius = cell.RADIUS
        local places = {}
        for index = 1, #units do
            places[index] = { phi = math.pi, centre = math.pi, radius = radius, half = math.rad(cell.HALF_MIN) }
        end
        for _ = 1, 8 do
            local total = cell.SPACE / radius * (#units - 1)
            for index, unit in ipairs(units) do
                local place = places[index]
                local _, _, near, far = getLampSpan(unit, place.phi, radius)
                local inner, outer = near - cell.IN, cell.OUT - far
                place.radius = radius
                if inner < cell.MARGIN or outer < cell.MARGIN then
                    local isCentred = inner + outer < 2 * cell.MARGIN
                    local isInward = inner < cell.MARGIN
                    for _ = 1, 6 do
                        if isCentred then
                            place.radius = place.radius + (outer - inner) * 0.5
                        elseif isInward then
                            place.radius = place.radius + cell.MARGIN - inner
                        else
                            place.radius = place.radius - (cell.MARGIN - outer)
                        end
                        _, _, near, far = getLampSpan(unit, place.phi, place.radius)
                        inner, outer = near - cell.IN, cell.OUT - far
                    end
                end
                local low, high = getLampSpan(unit, place.phi, place.radius)
                place.offset = (low + high) * 0.5
                place.half = getCellHalf((high - low) * 0.5 + cell.MARGIN / radius)
                total = total + 2 * place.half
            end
            local angle = math.pi - total * 0.5
            for _, place in ipairs(places) do
                place.centre = angle + place.half
                place.phi = place.centre - place.offset
                angle = angle + 2 * place.half + cell.SPACE / radius
            end
        end
        local layout = {}
        for index, unit in ipairs(units) do
            local place = places[index]
            layout[unit.id] = { x = place.radius * math.cos(place.phi), y = place.radius * math.sin(place.phi),
                phi = place.centre, half = place.half,
                cell = string.format("rms_Hud.cell%03d", math.floor(math.deg(place.half) * 10 + 0.5)) }
        end
        lampLayouts[key] = layout
    end
    return lampLayouts[key]
end

---Places the row lamps one pitch apart, centred on the axis
function RMS_Hud.getRowLayout(count)
    local offsets = {}
    for index = 1, count do
        offsets[index] = (index - (count + 1) * 0.5) * RMS_Hud.ROW.PITCH
    end
    return offsets
end

---Returns a bubble centre, flush with the top or bottom of the dial
function RMS_Hud.getBubbleCentre(isHigh)
    local y = 116 - RMS_Hud.BUBBLE.RADIUS
    return RMS_Hud.BUBBLE.X, isHigh and y or -y
end

function RMS_Hud.getBubbleContent(inkHeight)
    local bubble = RMS_Hud.BUBBLE
    local height = inkHeight + bubble.SYMBOL_GAP + bubble.VALUE_HEIGHT
    local valueBottom = -height * 0.5
    return height * 0.5 - inkHeight * 0.5, valueBottom + bubble.VALUE_HEIGHT - bubble.VALUE_TOP_ABOVE_ANCHOR, valueBottom
end

local function formatValue(value, numberFormat)
    local amount = tonumber(value) or 0
    local text = string.format(numberFormat, amount)

    if text == string.format(numberFormat, 0) then
        return "0"
    end

    return text
end

local function formatConsumptionValue(value)
    local amount = math.max(tonumber(value) or 0, 0)
    return formatValue(amount, amount < 100 and "%.1f" or "%.0f")
end

local function snapScreenX(x)
    return math.floor(x * g_screenWidth + 0.5) / g_screenWidth
end

local function snapScreenY(y)
    return math.floor(y * g_screenHeight + 0.5) / g_screenHeight
end

local function setTextStyle(alignment, verticalAlignment, isBold)
    setTextAlignment(alignment)
    setTextVerticalAlignment(verticalAlignment)
    setTextBold(isBold)
end

local function squeezeSpaces(text)
    return text:gsub("%s+", " "):match("^ ?(.-) ?$")
end

---Create instance of RMS_Hud, loading its overlays
function RMS_Hud:new()
    local self = RMS_Hud:superClass().new(RMS_Hud_mt)

    self.telemetryDisplayValues = {
        motorLoad = 0
    }
    self.motorLoadAverage = { buckets = {}, current = { value = 0, time = 0 }, timer = 0 }
    self.consumption = {
        buckets = {},
        current = { litres = 0, hectares = 0 },
        timer = 0,
        perHour = 0,
        perArea = nil
    }
    self.wheelSlipHud = {
        icon = g_overlayManager:createOverlay("rms_Hud.wheelSlip", 0, 0, 0, 0)
    }
    self.fuelConsumptionHud = {
        icon = g_overlayManager:createOverlay("gui.icon_fuel", 0, 0, 0, 0),
        sliceId = "gui.icon_fuel"
    }
    self.halfMoon = {
        background = g_overlayManager:createOverlay("rms_Hud.background", 0, 0, 0, 0),
        cell = g_overlayManager:createOverlay("rms_Hud.cell030", 0, 0, 0, 0),
        bar = g_overlayManager:createOverlay("rms_Hud.bar", 0, 0, 0, 0),
        band = g_overlayManager:createOverlay("rms_Hud.band", 0, 0, 0, 0)
    }
    self.sliceUvs = {}
    self.turnedUvs = {}

    self.bubble = g_overlayManager:createOverlay("rms_Hud.pod", 0, 0, 0, 0)
    self.lampGlow = g_overlayManager:createOverlay("rms_LampGlow.glow", 0, 0, 0, 0)

    self.drivetrainHud = {
        icons = {
            frontWheelDrive = { overlay = g_overlayManager:createOverlay("rms_Hud.frontWheelDrive", 0, 0, 0, 0), width = 86, height = 72 },
            diffLock        = { overlay = g_overlayManager:createOverlay("rms_Hud.diffLock", 0, 0, 0, 0),        width = 72, height = 72 }
        }
    }

    self.parkBrakeHud = {
        icon = g_overlayManager:createOverlay("rms_Hud.parkBrake", 0, 0, 0, 0)
    }

    self.lampIcons = {}
    for slice in pairs(RMS_Hud.LAMP_INK) do
        self.lampIcons[slice] = g_overlayManager:createOverlay("rms_Hud." .. slice, 0, 0, 0, 0)
    end
    self.lampStates = {}
    self.loadMassText = {}

    self.notification = nil
    self.closeText = g_i18n:getText("button_ok")

    self.inspectionProgress = {
        ratio = nil,
        messageText = nil,
        messageEndTime = 0
    }

    return self
end

---Deletes the overlays of the HUD
function RMS_Hud:delete()
    self:setNotificationInputActive(false)
    self.wheelSlipHud.icon:delete()
    self.wheelSlipHud.icon = nil
    self.fuelConsumptionHud.icon:delete()
    self.fuelConsumptionHud.icon = nil
    self.parkBrakeHud.icon:delete()
    self.parkBrakeHud.icon = nil

    for _, overlay in pairs(self.halfMoon) do
        overlay:delete()
    end
    self.halfMoon = nil

    self.bubble:delete()
    self.bubble = nil
    self.lampGlow:delete()
    self.lampGlow = nil

    for _, icon in pairs(self.drivetrainHud.icons) do
        icon.overlay:delete()
        icon.overlay = nil
    end

    for _, icon in pairs(self.lampIcons) do
        icon:delete()
    end
    self.lampIcons = nil
    self.closeGlyph:delete()
    self.closeGlyph = nil

    RMS_Hud:superClass().delete(self)
end

---Binds the HUD to a vehicle; another one resets lamps and averages
function RMS_Hud:setVehicle(vehicle)
    if vehicle == self.vehicle then
        return
    end
    self.vehicle = vehicle
    self.lampStates = {}
    self.telemetryDisplayValues.motorLoad = 0
    self.motorLoadAverage = { buckets = {}, current = { value = 0, time = 0 }, timer = 0 }
    self:resetConsumptionAverages()
end

---Lighting up or turning red, a lamp blinks and beeps once
function RMS_Hud:updateLampAlert(id, severity, isMotorOn)
    local state = self.lampStates[id]
    if state == nil then
        state = { severity = 0, beepSeverity = 0 }
        self.lampStates[id] = state
    end

    if severity > state.severity then
        state.blinkTime = isMotorOn and 0 or nil
        if isMotorOn and severity > state.beepSeverity then
            local time = g_currentMission.time
            local pause = RMS_Hud.LAMP_BEEP_PAUSE_MS[id] or RMS_Hud.LAMP_BEEP_PAUSE_MS.DEFAULT
            if state.beepTime == nil or time - state.beepTime >= pause then
                local samples = self.vehicle.spec_RealisticMechanicalSystems.samples
                local sample = samples.warning
                if severity == 2 then
                    sample = samples.alarm
                end
                RMS_SoundManager.playSample(sample)
                state.beepTime, state.beepSeverity = time, severity
            end
        end
    elseif severity == 0 then
        state.blinkTime, state.beepSeverity = nil, 0
    end
    state.severity = severity
end

---Returns the colour a lamp shows, dark every other blink phase
function RMS_Hud:getLampBlinkColor(id, color, isContinuous, isMotorOn)
    local state = self.lampStates[id]
    if state.blinkTime == nil then
        return color
    end

    local blink = RMS_Hud.LAMP_BLINK
    local phase = math.floor(state.blinkTime / blink.PHASE_MS)
    if not isMotorOn or (not isContinuous and phase >= blink.SHORT_PHASES) then
        state.blinkTime = nil
        return color
    end
    state.blinkTime = state.blinkTime + g_currentDt
    if phase % 2 == 1 then
        return RMS_Breakdowns.COLORS.DEFAULT
    end
    return color
end

local hasCVTTransmission = RMS_Utils.hasCVTTransmission
local hasCVTAddon = RMS_Utils.hasCVTAddon

---Draws the whole HUD for the current frame
function RMS_Hud:draw()
    local isHudVisible = g_currentMission.hud.isVisible
    self:setNotificationInputActive(isHudVisible and not g_gui:getIsGuiVisible() and self:hasClosableNotification())
    if not isHudVisible then
        return
    end

    local vehicle = self.vehicle
    self:drawNotification()
    self:drawInspectionProgress()
    RMS_DebugWindow.draw(vehicle)
    if vehicle ~= nil then
        self:drawDashboard()
        self:drawTelemetryCards()
    end

    setTextStyle(RenderText.ALIGN_LEFT, RenderText.VERTICAL_ALIGN_BASELINE, false)
    setTextColor(1, 1, 1, 1)
end

---Shows a notification on the shared HUD instance
-- @param float? durationMs display time, 0 or less until the player closes it
function RMS_Hud.showNotification(text, durationMs, title, playSound)
    if RMS_Main.hud ~= nil then
        RMS_Main.hud:setNotification(text, durationMs, title, playSound)
    end
end

---Sets the inspection progress on the shared HUD instance
function RMS_Hud.showInspectionProgress(ratio)
    if RMS_Main.hud ~= nil then
        RMS_Main.hud:setInspectionProgress(ratio)
    end
end

---Shows a message where the inspection ring stood on the shared HUD instance
function RMS_Hud.showInspectionMessage(text, durationMs)
    if RMS_Main.hud ~= nil then
        RMS_Main.hud:setInspectionMessage(text, durationMs)
    end
end

---Shows a notification in place of the one on screen
function RMS_Hud:setNotification(text, durationMs, title, playSound)
    text = squeezeSpaces(text)
    if text == "" then
        self.notification = nil
        return
    end
    if title ~= nil then
        title = squeezeSpaces(title)
        title = title ~= "" and utf8ToUpper(title) or nil
    end

    durationMs = durationMs or RMS_Hud.NOTIFICATION_DURATION_MS
    local isPersistent = durationMs <= 0
    self.notification = { text = text, title = title, isPersistent = isPersistent,
        endTime = not isPersistent and g_time + durationMs or nil }

    if playSound then
        RMS_SoundManager.playSample(RMS_Main.samples.notification2D)
    end
end

---Tells whether a notification the player closes is on screen
function RMS_Hud:hasClosableNotification()
    local notification = self.notification
    return notification ~= nil and notification.isPersistent
end

---Binds the close key while a closable notification is shown
function RMS_Hud:setNotificationInputActive(isActive)
    local inputBinding = g_inputBinding
    local contextName = isActive and inputBinding:getContextName() or nil

    if self.closeEventId ~= nil and self.closeEventContext ~= contextName then
        inputBinding:beginActionEventsModification(self.closeEventContext)
        inputBinding:removeActionEvent(self.closeEventId)
        inputBinding:endActionEventsModification()
        self.closeEventId, self.closeEventContext = nil, nil
    end

    if contextName ~= nil and self.closeEventId == nil then
        inputBinding:beginActionEventsModification(contextName)
        local _, eventId = inputBinding:registerActionEvent(InputAction.RMS_CLOSE_NOTIFICATION, self, self.onCloseNotification,
            false, true, false, true, nil, false)
        inputBinding:setActionEventTextVisibility(eventId, false)
        inputBinding:endActionEventsModification()
        self.closeEventId, self.closeEventContext = eventId, contextName
    end
end

---Closes the notification the player closes
function RMS_Hud:onCloseNotification()
    if self:hasClosableNotification() then
        self.notification = nil
    end
end

---Stores the progress the inspection ring draws, absent to hide it
function RMS_Hud:setInspectionProgress(ratio)
    local progress = self.inspectionProgress
    progress.ratio = ratio ~= nil and math.clamp(ratio, 0, 1) or nil

    if progress.ratio ~= nil then
        progress.messageText = nil
    end
end

---Stores the message shown where the inspection ring stood
function RMS_Hud:setInspectionMessage(text, durationMs)
    local progress = self.inspectionProgress
    progress.messageText = text
    progress.messageEndTime = g_time + durationMs
end

---Draws the inspection progress as a ring filling up around its percentage
function RMS_Hud:drawInspectionProgress()
    local progress = self.inspectionProgress
    local ratio = progress.ratio
    local hasMessage = progress.messageText ~= nil and g_time < progress.messageEndTime
    if ratio == nil and not hasMessage then
        return
    end

    local centerX, centerY = 0.5, 0.46
    local labelSize = self:scalePixelToScreenHeight(RMS_Hud.INSPECTION_LABEL_SIZE)
    setTextStyle(RenderText.ALIGN_CENTER, RenderText.VERTICAL_ALIGN_BASELINE, true)
    setTextColor(1, 1, 1, 1)
    if ratio == nil then
        renderText(centerX, centerY, labelSize, progress.messageText)
        return
    end

    local ringWidth, ringHeight = self:scalePixelValuesToScreenVector(RMS_Hud.INSPECTION_RING_SIZE, RMS_Hud.INSPECTION_RING_SIZE)
    local disc = RMS_ProgressRing.disc
    disc:setDimension(ringWidth, ringHeight)
    disc:setPosition(centerX - ringWidth * 0.5, centerY - ringHeight * 0.5)
    disc:setColor(0, 0, 0, RMS_Hud.INSPECTION_SHADE_ALPHA)
    disc:render()
    local grey = Dashboard.COLORS.GREY
    RMS_ProgressRing.render(centerX, centerY, ringWidth, ringHeight, ratio, HUD.COLOR.ACTIVE, {grey[1], grey[2], grey[3], RMS_Hud.INSPECTION_SHADE_ALPHA})

    local percentSize = ringHeight * RMS_Hud.INSPECTION_PERCENT_SHARE
    renderText(centerX, centerY - percentSize * 0.4, percentSize, string.format("%d%%", math.floor(ratio * 100 + 1e-6)))
    renderText(centerX, centerY + ringHeight * 0.5 + labelSize * 0.6, labelSize, g_i18n:getText("rms_field_inspection_progress"))
end

---Draws the notification: title, line, text, line and close key
function RMS_Hud:drawNotification()
    local notification = self.notification
    if notification == nil then
        return
    end
    if notification.endTime ~= nil and g_time >= notification.endTime then
        self.notification = nil
        return
    end

    local title, width = notification.title, self.messageWidth
    local paddingX, paddingY = self.messagePaddingX, self.messagePaddingY
    setTextWrapWidth(width - 2 * paddingX)
    setTextStyle(RenderText.ALIGN_CENTER, RenderText.VERTICAL_ALIGN_TOP, false)
    local textHeight = getTextHeight(self.messageTextSize, notification.text)
    local height = textHeight + 2 * paddingY
    local titleHeight = 0
    if title ~= nil then
        setTextBold(true)
        titleHeight = getTextHeight(self.messageTitleSize, title)
        height = height + titleHeight + 2 * self.messageTitleGap + self.messageCloseGap + 2 * g_pixelSizeY
        if notification.isPersistent then
            height = height + self.messageCloseHeight
        end
    end

    local posX, posY = 0.5 - width * 0.5, g_hudAnchorBottom
    local background = HUD.COLOR.BACKGROUND_DARK
    drawFilledRectRound(posX, posY, width, height, 0.25, background[1], background[2], background[3], background[4])

    local green = RMS_Hud.COLOR_GAME_GREEN
    local lineStart, lineEnd = posX + paddingX, posX + width - paddingX
    local textY = posY + height - paddingY
    if title ~= nil then
        setTextColor(green[1], green[2], green[3], green[4])
        renderText(0.5, textY, self.messageTitleSize, title)
        textY = textY - titleHeight - self.messageTitleGap - g_pixelSizeY * 0.5
        drawLine2D(lineStart, textY, lineEnd, textY, g_pixelSizeY, green[1], green[2], green[3], green[4])
        textY = textY - g_pixelSizeY * 0.5 - self.messageTitleGap
        local lineY = textY - textHeight - self.messageCloseGap - g_pixelSizeY * 0.5
        drawLine2D(lineStart, lineY, lineEnd, lineY, g_pixelSizeY, green[1], green[2], green[3], green[4])
    end

    setTextBold(false)
    setTextColor(1, 1, 1, 1)
    renderText(0.5, textY, self.messageTextSize, notification.text)
    setTextWrapWidth(0)
    if title ~= nil and notification.isPersistent then
        self:drawCloseControl(posY + paddingY)
    end
end

---Draws the close key and its OK, centred on the panel
function RMS_Hud:drawCloseControl(bottomY)
    local inputMode = g_inputBinding:getInputHelpMode()
    if inputMode ~= self.closeGlyphInputMode then
        self.closeGlyph:setAction(InputAction.RMS_CLOSE_NOTIFICATION, nil, nil, true)
        self.closeGlyphInputMode = inputMode
    end

    local keyWidth, textSize = self.closeGlyph:getGlyphWidth(), self.messageTextSize
    local keyX = 0.5 - (keyWidth + self.closeTextGap + getTextWidth(textSize, self.closeText)) * 0.5
    local keyY = bottomY + (self.messageCloseHeight - self.closeGlyphHeight) * 0.5
    self.closeGlyph:setPosition(keyX, keyY)
    self.closeGlyph:draw()

    setTextStyle(RenderText.ALIGN_LEFT, RenderText.VERTICAL_ALIGN_MIDDLE, true)
    setTextColor(1, 1, 1, 0.95)
    renderText(keyX + keyWidth + self.closeTextGap - self.closeTextShiftX,
        keyY + self.closeGlyphHeight * 0.5 + self.closeTextShiftY, textSize, self.closeText)
end

---Recomputes every HUD size and position for the current screen resolution
function RMS_Hud:storeScaledValues()
    local function pixelSize(width, height)
        width, height = self:scalePixelValuesToScreenVector(width, height)
        return math.max(math.floor(width * g_screenWidth + 0.5), 1) / g_screenWidth,
            math.max(math.floor(height * g_screenHeight + 0.5), 1) / g_screenHeight
    end

    local lamp = RMS_Hud.LAMP
    for slice, icon in pairs(self.lampIcons) do
        local size = lamp.SIZE * (RMS_Hud.LAMP_SCALE[slice] or 1)
        icon:setDimension(pixelSize(size, size))
    end
    self.lampValueSize = self:scalePixelToScreenHeight(lamp.VALUE_SIZE)

    local speedMeter = g_currentMission.hud.speedMeter
    local serviceAnchorY = (speedMeter.gaugeTextOffsets[4].offsetY + speedMeter.gaugeTextOffsets[7].offsetY) * 0.5
    self.rowCenterY = serviceAnchorY - self:scalePixelToScreenHeight(10)
    -- The service anchor is the foot of an 11 px mark.
    self.serviceCentreY = serviceAnchorY + self:scalePixelToScreenHeight(5.5)

    local back = RMS_Hud.BACKGROUND.BOX
    self.halfMoon.background:setDimension(self:scalePixelValuesToScreenVector(back[3] - back[1], back[4] - back[2]))

    local bubble = RMS_Hud.BUBBLE
    self.bubble:setDimension(pixelSize(bubble.POD_BOX * 2, bubble.POD_BOX * 2))
    self.bubble:setColor(0, 0, 0, RMS_Hud.CELL.ALPHA)
    self.bubbleValueSize = self:scalePixelToScreenHeight(bubble.VALUE_SIZE)
    self.wheelSlipHud.icon:setDimension(pixelSize(72 * bubble.PICTURE_SCALE, 72 * bubble.PICTURE_SCALE))
    for _, iconData in pairs(self.drivetrainHud.icons) do
        iconData.overlay:setDimension(pixelSize(iconData.width * bubble.PICTURE_SCALE, iconData.height * bubble.PICTURE_SCALE))
    end

    self.lampGlow:setDimension(pixelSize(RMS_Hud.GLOW.SIZE, RMS_Hud.GLOW.SIZE))

    if self.parkBrakeHud ~= nil and self.parkBrakeHud.icon ~= nil then
        local parkWidth, parkHeight = self:scalePixelValuesToScreenVector(RMS_Hud.PARK_BRAKE.SIZE, RMS_Hud.PARK_BRAKE.SIZE)
        self.parkBrakeHud.icon:setDimension(parkWidth, parkHeight)
        self.parkBrakeHud.width = parkWidth
        self.parkBrakeHud.height = parkHeight
        self.parkBrakeHud.gapX = self:scalePixelToScreenWidth(RMS_Hud.PARK_BRAKE.GAP)
        self.parkBrakeHud.offsetY = self:scalePixelToScreenHeight(0)
    end

    self.loadMassText.size = self:scalePixelToScreenHeight(13)
    self.loadMassText.paddingH, self.loadMassText.paddingV = self:scalePixelValuesToScreenVector(10, 4)
    self.telemetryCardGap = self:scalePixelToScreenWidth(4)

    local fuelIcon = RMS_Hud.FUEL_ICON
    local fuelIconWidth, fuelIconHeight = self:scalePixelValuesToScreenVector(fuelIcon.SIZE, fuelIcon.SIZE)
    self.fuelConsumptionHud.icon:setDimension(fuelIconWidth, fuelIconHeight)
    self.fuelConsumptionHud.width = fuelIconWidth
    self.fuelConsumptionHud.height = fuelIconHeight
    self.fuelConsumptionHud.iconGap = self:scalePixelToScreenWidth(fuelIcon.GAP)

    self.messageWidth = self:scalePixelToScreenWidth(640)
    self.messagePaddingX, self.messagePaddingY = self:scalePixelValuesToScreenVector(20, 20)
    self.messageTitleSize = self:scalePixelToScreenHeight(19)
    self.messageTextSize = self:scalePixelToScreenHeight(17)
    self.messageTitleGap = self:scalePixelToScreenHeight(10)
    self.messageCloseGap = self:scalePixelToScreenHeight(15)
    self.messageCloseHeight = self:scalePixelToScreenHeight(30)
    self.closeTextGap, self.closeTextShiftY = self:scalePixelValuesToScreenVector(6, 2)
    self.closeTextShiftX = self:scalePixelToScreenWidth(4)

    local glyphWidth, glyphHeight = self:scalePixelValuesToScreenVector(26, 26)
    if self.closeGlyph ~= nil then
        self.closeGlyph:delete()
    end
    self.closeGlyph = InputGlyphElement.new(g_inputDisplayManager, glyphWidth, glyphHeight)
    self.closeGlyph:setKeyboardGlyphColor(RMS_Hud.COLOR_GAME_GREEN, {0, 0, 0, 0.8})
    self.closeGlyph:setButtonGlyphColor(RMS_Hud.COLOR_GAME_GREEN)
    self.closeGlyphHeight = glyphHeight
    self.closeGlyphInputMode = nil
end

function RMS_Hud.getIsParticulateFilterCalling(spec)
    return spec.fuelState.particulateFilterLevel >= 1 and not spec.fuelState.isParticulateFilterRegenerating
end

---Returns the offset putting a row lamp's ink bottom on the warning's
function RMS_Hud.getRowLampLift(slice)
    local lamp = RMS_Hud.LAMP
    local function foot(name)
        return (RMS_Hud.LAMP_INK[name][3] - lamp.CELL * 0.5) * lamp.SIZE * (RMS_Hud.LAMP_SCALE[name] or 1) / lamp.CELL
    end
    return foot("warning") - foot(slice)
end

---Returns the road or machine slice replacing the tractor one
function RMS_Hud.getFamilyLampSlice(id, isRoadVehicle, isMachine)
    if isRoadVehicle then
        return RMS_Hud.ROAD_LAMP_SLICE[id]
    elseif isMachine then
        return RMS_Hud.MACHINE_LAMP_SLICE[id]
    end
    return nil
end

---Returns the picture a lamp takes on this vehicle
function RMS_Hud.getLampSlice(id, spec, isRoadVehicle, isMachine)
    if id == "engine" and (isRoadVehicle or spec.isElectricVehicle) then
        return "engineClassic"
    end
    return RMS_Hud.getFamilyLampSlice(id, isRoadVehicle, isMachine) or RMS_Hud.LAMP_SLICE[id] or id
end

---Tells whether the level of the engine oil lights the oil lamp
function RMS_Hud.getIsOilPressureLow(spec)
    return (tonumber(spec.engineOilLevel) or 1) <= RMS_Config.FLUIDS.LEVEL_CRITICALLY_LOW
end

---Returns the coolant lamp colour key for the drive temperature
function RMS_Hud.getCoolantTelltaleState(spec)
    local telltale = RMS_Thermal.getDriveValues(spec).TELLTALE
    local temperature = spec.engineTemperature

    if temperature >= telltale.CRITICAL then
        return "CRITICAL"
    elseif temperature > telltale.WARNING then
        return "WARNING"
    end
    return nil
end

---Returns the colour a lit lamp has on a real dashboard
function RMS_Hud.getLitLampColor(id, color, spec)
    local colors = RMS_Breakdowns.COLORS
    if color == colors.DEFAULT or color == colors.COOL then
        return color
    elseif id == "fanReversal" then
        return RMS_Hud.COLOR_GAME_GREEN
    elseif id == "transmission" then
        return spec.isTruck and colors.WARNING or colors.CRITICAL
    end
    local litColor = RMS_Hud.LIT_LAMP_COLOR[id]
    return litColor ~= nil and colors[litColor] or color
end

---Returns the colour of every lamp this frame
function RMS_Hud.getLampColors(vehicle, motorState, isServiceOverdue, cvtFaultColor)
    local spec = vehicle.spec_RealisticMechanicalSystems
    local colors = RMS_Breakdowns.COLORS
    local isOff = motorState == MotorState.OFF
    -- A routine lamp is a check or a normal operation: no blink, no beep
    local lampColors, isRoutine = {}, {}

    for _, id in ipairs(RMS_Hud.INDICATOR_ORDER) do
        lampColors[id] = colors.DEFAULT
        local light = spec.activeIndicators[id]
        if light ~= nil then
            light.isActive = not isOff and not light.switchOff(vehicle) and (light.isActive or light.switchOn(vehicle))
            if light.isActive then
                lampColors[id] = light.color
            end
        end
    end
    if isOff then
        return lampColors, isRoutine
    end

    -- A gearbox fault lights the warning, its lamp the oil temperature
    local gearboxFault = lampColors.transmission
    if cvtFaultColor == colors.CRITICAL or gearboxFault == colors.DEFAULT then
        gearboxFault = cvtFaultColor
    end
    if gearboxFault ~= colors.DEFAULT and (lampColors.warning == colors.DEFAULT or gearboxFault == colors.CRITICAL) then
        lampColors.warning = gearboxFault
    end
    local oilAlertTemp = RMS_Hud.GEARBOX_OIL_ALERT_TEMP[spec.isTruck and "TRUCK" or "DEFAULT"]
    lampColors.transmission = spec.transmissionTemperature > oilAlertTemp and colors.WARNING or colors.DEFAULT

    if spec.fanReversalTime > 0 then
        lampColors.fanReversal, isRoutine.fanReversal = RMS_Hud.COLOR_GAME_GREEN, true
    end
    local coolantState = RMS_Hud.getCoolantTelltaleState(spec)
    if coolantState ~= nil and (coolantState == "CRITICAL" or lampColors.coolant == colors.DEFAULT) then
        lampColors.coolant = colors[coolantState]
    end
    if isServiceOverdue then
        lampColors.service = colors.WARNING
    end
    if RMS_Hud.getIsOilPressureLow(spec) then
        lampColors.oil = colors.CRITICAL
    end
    if lampColors.dpf == colors.DEFAULT then
        if spec.fuelState.isParticulateFilterRegenerating then
            lampColors.dpf, isRoutine.dpf = colors.WARNING, true
        elseif RMS_Hud.getIsParticulateFilterCalling(spec) then
            lampColors.dpf = colors.WARNING
        end
    end

    if RMS_Preheat.isLampTestActive(vehicle) then
        for id in pairs(lampColors) do
            lampColors[id], isRoutine[id] = colors.WARNING, true
        end
        return lampColors, isRoutine
    end
    if RMS_Preheat.isHeating(vehicle) and lampColors.preheat == colors.DEFAULT then
        lampColors.preheat, isRoutine.preheat = colors.WARNING, true
    end
    -- Charge and oil pressure lamps stay lit until the engine runs
    if motorState == MotorState.IGNITION or motorState == MotorState.STARTING then
        for _, id in ipairs({ "battery", "oil" }) do
            if lampColors[id] == colors.DEFAULT then
                lampColors[id], isRoutine[id] = colors.WARNING, true
            end
        end
    end
    return lampColors, isRoutine
end

---Builds the figures drawn beside the telltales
function RMS_Hud.getGaugeValues(spec, motorLoad, showTransmissionTemperature)
    local overloadThreshold = spec.isElectricVehicle and RMS_Config.ELECTRIC_DRIVE.MOTOR_OVERLOADED_THRESHOLD
        or RMS_Config.CORE.ENGINE_FACTOR_DATA.MOTOR_OVERLOADED_THRESHOLD
    local overloadLoad = motorLoad
    if not spec.isElectricVehicle and motorLoad > 0 then
        overloadLoad = tonumber(spec.dynamicMotorLoad) or motorLoad
    end
    local values = {
        coolant = { text = g_i18n:formatTemperature(spec.engineTemperature, 0) },
        engine = { text = string.format("%.0f%%", math.max(motorLoad * 100, 0)), isWarning = overloadLoad > overloadThreshold },
        battery = { text = formatValue(spec.batteryIsolated and 0 or spec.systemVoltageV, "%.1f") .. "V" }
    }
    if showTransmissionTemperature then
        values.transmission = { text = g_i18n:formatTemperature(spec.transmissionTemperature, 0) }
    end
    return values
end

---Draws the dashboard indicators, the gauges and the vehicle condition
function RMS_Hud:drawDashboard()
    local vehicle, speedMeter = self.vehicle, g_currentMission.hud.speedMeter
    local spec = vehicle.spec_RealisticMechanicalSystems
    if spec == nil or spec.isExcludedVehicle then
        return
    end

    RMS_Thermal.getEngineTemperature(vehicle)
    local colors = RMS_Breakdowns.COLORS
    local motorState = vehicle:getMotorState()
    local isMotorOn = motorState == MotorState.ON
    local isRoadVehicle = RMS_Drivetrain.getIsRoadVehicleCategory(vehicle)
    local isMachine = RMS_Drivetrain.getIsMachineCategory(vehicle)
    local cvtAddonSpec = hasCVTAddon(vehicle) and vehicle.spec_CVTaddon or nil
    local cvtFaultColor = colors.DEFAULT
    if cvtAddonSpec ~= nil then
        if cvtAddonSpec.forDBL_critdamage == 1 then
            cvtFaultColor = colors.CRITICAL
        elseif cvtAddonSpec.forDBL_warndamage == 1 or cvtAddonSpec.forDBL_highpressure == 1 then
            cvtFaultColor = colors.WARNING
        end
    end
    local isServiceOverdue = vehicle:getServiceLevel() < RMS_Config.CORE.SERVICE_EXPIRED_THRESHOLD
    local lampColors, isRoutine = RMS_Hud.getLampColors(vehicle, motorState, isServiceOverdue, cvtFaultColor)

    speedMeter.speedTextSize = self:scalePixelToScreenHeight(43)
    local posX, posY = speedMeter.speedBg:getPosition()
    posX, posY = posX + speedMeter.speedGaugeCenterOffsetX, posY + speedMeter.speedGaugeCenterOffsetY
    local hasTransmissionOilTempDisplay = hasCVTTransmission(vehicle) or cvtAddonSpec ~= nil
    local lamp = RMS_Hud.LAMP

    local units, unitsById = {}, {}
    for _, id in ipairs(RMS_Hud.ARC_ORDER) do
        if RealisticMechanicalSystems.getIsTelltaleFitted(vehicle, id) then
            local ink = RMS_Hud.LAMP_INK[RMS_Hud.getLampSlice(id, spec, isRoadVehicle, isMachine)]
            local hasValue = id == "engine" or id == "coolant" or id == "battery" or (id == "transmission" and hasTransmissionOilTempDisplay)
            local unit = { id = id, inkWidth = ink[1] * lamp.SIZE / lamp.CELL, inkHeight = ink[2] * lamp.SIZE / lamp.CELL,
                valueWidth = hasValue and RMS_Hud.VALUE_WIDTH[id] or nil }
            units[#units + 1] = unit
            unitsById[id] = unit
        end
    end
    local layout = RMS_Hud.getLampLayout(units)
    local hasDriveBubble = RMS_Drivetrain.getIsAvailable(vehicle) and RMS_Drivetrain.getState(vehicle) ~= nil
    self:drawHalfMoon(posX, posY, units, layout, spec, motorState ~= MotorState.OFF, hasDriveBubble, not isRoadVehicle)

    local rowIds = {}
    for _, id in ipairs({ spec.isElectricVehicle and "limitedPower" or "preheat", "warning",
        spec.isElectricVehicle and "tractionBattery" or "oil" }) do
        if RealisticMechanicalSystems.getIsTelltaleFitted(vehicle, id) then
            rowIds[#rowIds + 1] = id
        end
    end
    local rowPlaces = {}
    for index, x in ipairs(RMS_Hud.getRowLayout(#rowIds)) do
        rowPlaces[rowIds[index]] = x
    end

    local lamps = {}
    for _, id in ipairs(RMS_Hud.INDICATOR_ORDER) do
        local slice = RMS_Hud.getLampSlice(id, spec, isRoadVehicle, isMachine)
        local x, y
        if layout[id] ~= nil then
            x = posX + self:scalePixelToScreenWidth(layout[id].x)
            y = posY + self:scalePixelToScreenHeight(layout[id].y)
        elseif rowPlaces[id] ~= nil then
            x = posX + self:scalePixelToScreenWidth(rowPlaces[id])
            y = posY + self.rowCenterY + self:scalePixelToScreenHeight(RMS_Hud.getRowLampLift(slice))
        elseif id == "service" and RealisticMechanicalSystems.getIsTelltaleFitted(vehicle, id) then
            x, y = posX, posY + self.serviceCentreY
        end

        local color = lampColors[id]
        local severity = 0
        if x ~= nil and not isRoutine[id] then
            if color == colors.CRITICAL then
                severity = 2
            elseif color == colors.WARNING then
                severity = 1
            end
        end
        self:updateLampAlert(id, severity, isMotorOn)
        color = RMS_Hud.getLitLampColor(id, color, spec)
        if not isRoutine[id] then
            local light = spec.activeIndicators[id]
            local isContinuous = light ~= nil and light.blinkWhileActive
                or id == "dpf" and color == colors.WARNING and RMS_Hud.getIsParticulateFilterCalling(spec)
            color = self:getLampBlinkColor(id, color, isContinuous, isMotorOn)
        end

        if x ~= nil then
            local icon = self.lampIcons[slice]
            icon:setPosition(snapScreenX(x - icon.width * 0.5), snapScreenY(y - icon.height * 0.5))
            lamps[#lamps + 1] = { icon = icon, color = color, x = x, y = y }
        end
    end

    -- Draw glows first to keep them behind neighbouring lamps.
    local glow = RMS_Hud.GLOW
    for _, lit in ipairs(lamps) do
        if lit.color ~= colors.DEFAULT then
            self.lampGlow:setPosition(snapScreenX(lit.x - self.lampGlow.width * 0.5), snapScreenY(lit.y - self.lampGlow.height * 0.5))
            self.lampGlow:setColor(lit.color[1], lit.color[2], lit.color[3], glow.ALPHA)
            self.lampGlow:render()
        end
    end
    for _, lit in ipairs(lamps) do
        lit.icon:setColor(unpack(lit.color))
        lit.icon:render()
    end

    local motorLoad = isMotorOn and self:updateMotorLoadAverage(math.clamp(tonumber(spec.dynamicMotorLoad) or 0, 0, 1)) or 0
    self.telemetryDisplayValues.motorLoad = motorLoad
    local showTransmissionTemperatureText = hasTransmissionOilTempDisplay and unitsById.transmission ~= nil
    local gaugeValues = RMS_Hud.getGaugeValues(spec, motorLoad, showTransmissionTemperatureText)

    setTextStyle(RenderText.ALIGN_CENTER, RenderText.VERTICAL_ALIGN_MIDDLE, true)
    for _, indicatorName in ipairs({ "coolant", "transmission", "engine", "battery" }) do
        local gaugeValue = gaugeValues[indicatorName]
        local place, unit = layout[indicatorName], unitsById[indicatorName]
        if gaugeValue ~= nil and place ~= nil and unit.valueWidth ~= nil then
            local valueSize = self.lampValueSize
            local valueWidth = getTextWidth(valueSize, gaugeValue.text)
            local maxWidth = self:scalePixelToScreenWidth(unit.valueWidth)
            if valueWidth > maxWidth then
                valueSize = valueSize * maxWidth / valueWidth
            end
            local valueTop = place.y - unit.inkHeight * 0.5 - lamp.VALUE_GAP
            local color = gaugeValue.isWarning and colors.WARNING or RMS_Hud.GAUGE_LIT
            setTextColor(color[1], color[2], color[3], 1)
            renderText(snapScreenX(posX + self:scalePixelToScreenWidth(place.x)),
                snapScreenY(posY + self:scalePixelToScreenHeight(valueTop - lamp.VALUE_TOP)), valueSize, gaugeValue.text)
        end
    end

    self:drawDrivetrainDisplay(vehicle, posX, posY)
    if not isRoadVehicle then
        self:drawWheelSlipDisplay(spec, posX, posY)
    end
    self:drawParkBrakeDisplay(vehicle)
    self:drawOdometer()
end

---Draws the half-moon: background, lamp cells, coolant gauge
function RMS_Hud:drawHalfMoon(posX, posY, units, layout, spec, isPowered, hasHigh, hasLow)
    local halfMoon = self.halfMoon
    local back = RMS_Hud.BACKGROUND.BOX
    halfMoon.background:setSliceId(hasHigh and (hasLow and "rms_Hud.backgroundBubbles" or "rms_Hud.backgroundHigh")
        or (hasLow and "rms_Hud.backgroundLow" or "rms_Hud.background"))
    halfMoon.background:setPosition(posX + self:scalePixelToScreenWidth(back[1]), posY + self:scalePixelToScreenHeight(back[2]))
    halfMoon.background:setColor(0, 0, 0, 1)
    halfMoon.background:render()

    local cell = RMS_Hud.CELL
    halfMoon.cell:setColor(0, 0, 0, cell.ALPHA)
    -- Cells are baked pointing left and turned about the gauge centre.
    for _, unit in ipairs(units) do
        local place = layout[unit.id]
        self:drawTurned(halfMoon.cell, place.cell, cell.BOX, cell.EXTENT, posX, posY, place.phi - math.pi)
    end

    self:drawCoolantGauge(posX, posY, spec, isPowered)
end

---Turns an atlas picture by its UVs; overlay rotation distorts it
function RMS_Hud:drawTurned(overlay, sliceId, box, extent, x, y, angle)
    local uvs = self.sliceUvs[sliceId]
    if uvs == nil then
        uvs = g_overlayManager:getSliceInfoById(sliceId).uvs
        self.sliceUvs[sliceId] = uvs
    end
    local c, s = math.cos(angle), math.sin(angle)
    local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
    for _, px in ipairs({ extent[1], extent[3] }) do
        for _, py in ipairs({ extent[2], extent[4] }) do
            local tx, ty = c * px - s * py, s * px + c * py
            x0, x1 = math.min(x0, tx), math.max(x1, tx)
            y0, y1 = math.min(y0, ty), math.max(y1, ty)
        end
    end
    -- UV corner order: bottom left, top left, bottom right, top right
    local turned, index = self.turnedUvs, 0
    for _, qx in ipairs({ x0, x1 }) do
        for _, qy in ipairs({ y0, y1 }) do
            local tx, ty = c * qx + s * qy, c * qy - s * qx
            turned[index + 1] = uvs[1] + (tx - box[1]) / (box[3] - box[1]) * (uvs[5] - uvs[1])
            turned[index + 2] = uvs[2] + (ty - box[2]) / (box[4] - box[2]) * (uvs[4] - uvs[2])
            index = index + 2
        end
    end
    overlay:setUVs(turned)
    overlay:setPosition(x + self:scalePixelToScreenWidth(x0), y + self:scalePixelToScreenHeight(y0))
    overlay:setDimension(self:scalePixelToScreenWidth(x1 - x0), self:scalePixelToScreenHeight(y1 - y0))
    overlay:render()
end

---Draws the coolant gauge and its zone band
function RMS_Hud:drawCoolantGauge(posX, posY, spec, isPowered)
    local gauge = RMS_Hud.GAUGE
    local telltale = RMS_Thermal.getDriveValues(spec).TELLTALE
    local temperature = tonumber(spec.engineTemperature) or gauge.LOW
    local share = isPowered and math.clamp((temperature - gauge.LOW) / (gauge.HIGH - gauge.LOW), 0, 1) or 0
    local mid = (gauge.IN + gauge.OUT) * 0.5
    local bandMid = (gauge.BAND_IN + gauge.BAND_OUT) * 0.5
    local span = math.rad(gauge.SPAN)
    local count = math.floor(2 * span * mid / gauge.PITCH + 0.5)
    local step = 2 * span / count
    local bar, band, glow = self.halfMoon.bar, self.halfMoon.band, self.lampGlow
    local glowWidth, glowHeight = glow.width, glow.height
    glow:setDimension(self:scalePixelValuesToScreenVector(gauge.GLOW, gauge.GLOW))
    for index = 0, count - 1 do
        local angle = math.pi + span - (index + 0.5) * step
        local c, s = math.cos(angle), math.sin(angle)
        local isLit = (index + 0.5) / count <= share
        local color, alpha = RMS_Hud.GAUGE_GREY, gauge.UNLIT_ALPHA
        if isLit then
            color, alpha = RMS_Hud.GAUGE_LIT, 1
        end
        local x = posX + self:scalePixelToScreenWidth(mid * c)
        local y = posY + self:scalePixelToScreenHeight(mid * s)
        if isLit then
            glow:setPosition(x - glow.width * 0.5, y - glow.height * 0.5)
            glow:setColor(color[1], color[2], color[3], gauge.GLOW_ALPHA)
            glow:render()
        end
        bar:setColor(color[1], color[2], color[3], alpha)
        self:drawTurned(bar, "rms_Hud.bar", gauge.BAR_BOX, gauge.BAR_EXTENT, x, y, angle)
        local level = gauge.LOW + (index + 0.5) / count * (gauge.HIGH - gauge.LOW)
        local zone = level > telltale.WARNING and RMS_Breakdowns.COLORS.CRITICAL
            or not spec.isElectricVehicle and level < RMS_Config.CORE.ENGINE_FACTOR_DATA.COLD_MOTOR_TEMP_THRESHOLD
                and RMS_Breakdowns.COLORS.COOL
            or RMS_Hud.COLOR_GAME_GREEN
        band:setColor(zone[1], zone[2], zone[3], 1)
        self:drawTurned(band, "rms_Hud.band", gauge.BAND_BOX, gauge.BAND_EXTENT,
            posX + self:scalePixelToScreenWidth(bandMid * c), posY + self:scalePixelToScreenHeight(bandMid * s), angle)
    end
    glow:setDimension(glowWidth, glowHeight)
end

---Draws the native odometer, or the trip meter read off it
function RMS_Hud:drawOdometer()
    local speedMeter = g_currentMission.hud.speedMeter
    local kilometers = RMS_Utils.getOdometerKilometers(self.vehicle)
    if kilometers == nil or speedMeter == nil or speedMeter.vehicle ~= self.vehicle or not speedMeter.isVehicleDrawSafe then
        return
    end

    local label = "ODO"
    local spec = self.vehicle.spec_RealisticMechanicalSystems
    if spec.odometerShowsTrip then
        label = "TRIP"
        kilometers = math.max(kilometers - spec.tripStartKilometers, 0)
    end
    -- Wrap displayed tenths only; preserve the lifetime reading.
    local displayTenths = math.floor(kilometers * 10 + 0.5) % 100000
    local value = string.format("%04d.%d km", math.floor(displayTenths / 10), displayTenths % 10)
    local size = speedMeter:scalePixelToScreenHeight(10)
    local gap = speedMeter:scalePixelToScreenWidth(4)
    setTextStyle(RenderText.ALIGN_LEFT, RenderText.VERTICAL_ALIGN_BOTTOM, true)

    -- Reserve maximum glyph widths to prevent digit shifts.
    local widestDigit = "0"
    for digit = 1, 9 do
        local text = tostring(digit)
        if getTextWidth(size, text) > getTextWidth(size, widestDigit) then
            widestDigit = text
        end
    end
    local layoutValue = value:gsub("%d", widestDigit)

    local labelWidth = getTextWidth(size, label)
    local valueWidth = getTextWidth(size, layoutValue)
    local width = labelWidth + gap + valueWidth

    local bgX, bgY = speedMeter.speedBg:getPosition()
    local x = bgX + speedMeter.speedGaugeCenterOffsetX - width * 0.5
    local y = bgY + speedMeter.speedGaugeCenterOffsetY + speedMeter.workingHoursSeperatorOffsetY
        + speedMeter:scalePixelToScreenHeight(4)
    setTextColor(unpack(HUD.COLOR.ACTIVE))
    renderText(x, y, size, label)
    local valueX = x + labelWidth + gap
    local prefix = (value:match("^0+") or ""):sub(1, 3)
    if prefix ~= "" then
        setTextColor(unpack(HUD.COLOR.INACTIVE))
        renderText(valueX, y, size, prefix)
        valueX = valueX + getTextWidth(size, prefix)
    end
    setTextColor(1, 1, 1, 1)
    renderText(valueX, y, size, value:sub(#prefix + 1))
    setTextBold(false)
end

local function drawBubble(self, isHigh, posX, posY, inkHeight)
    local bubbleX, bubbleY = RMS_Hud.getBubbleCentre(isHigh)
    local centreX = posX + self:scalePixelToScreenWidth(bubbleX)
    local centreY = posY + self:scalePixelToScreenHeight(bubbleY)
    self.bubble:setPosition(snapScreenX(centreX - self.bubble.width * 0.5), snapScreenY(centreY - self.bubble.height * 0.5))
    self.bubble:render()

    local symbolY, valueY = RMS_Hud.getBubbleContent(inkHeight)
    return centreY + self:scalePixelToScreenHeight(symbolY), centreY + self:scalePixelToScreenHeight(valueY), centreX
end

local function drawBubbleValue(self, centreX, valueY, text, color)
    setTextStyle(RenderText.ALIGN_CENTER, RenderText.VERTICAL_ALIGN_MIDDLE, true)
    setTextColor(color[1], color[2], color[3], color[4])
    renderText(snapScreenX(centreX), snapScreenY(valueY), self.bubbleValueSize, text)
end

---Draws the wheel slip in its bubble below the left of the dial
function RMS_Hud:drawWheelSlipDisplay(spec, posX, posY)
    local wheelSlip = math.clamp(tonumber(spec.wheelSlipIntensity) or 0, 0, 1)
    local symbolY, valueY, centreX = drawBubble(self, false, posX, posY, RMS_Hud.WHEEL_SLIP_INK_HEIGHT)

    local icon = self.wheelSlipHud.icon
    icon:setPosition(snapScreenX(centreX - icon.width * 0.5), snapScreenY(symbolY - icon.height * 0.5))
    icon:setVisible(true)
    icon:setColor(1, 1, 1, 1)
    icon:render()
    drawBubbleValue(self, centreX, valueY, string.format("%.0f%%", wheelSlip * 100), {1, 1, 1, 1})
end

function RMS_Hud.getDrivetrainDisplay(state, hasFrontAxleSwitch, time)
    local colors = RMS_Breakdowns.COLORS
    local windupStress = tonumber(state.windupStress) or 0
    if state.diffLockEngaged then
        local isBlinkOn = math.floor(time / 250) % 2 == 0
        return "diffLock", (windupStress > RMS_Config.DRIVETRAIN.WINDUP_CRITICAL_THRESHOLD and isBlinkOn) and colors.CRITICAL or colors.WARNING
    end
    if not hasFrontAxleSwitch then
        return "diffLock", colors.DEFAULT
    end
    local isDriving = state.driveMode == RMS_Drivetrain.MODE.FOUR_WD
        or (state.driveMode == RMS_Drivetrain.MODE.AUTO and state.autoEngaged == true)
    if not isDriving then
        return "frontWheelDrive", colors.DEFAULT
    end
    local isWindingUp = state.windupActive == true and windupStress > RMS_Config.DRIVETRAIN.WINDUP_4WD_WARNING_THRESHOLD
    return "frontWheelDrive", isWindingUp and colors.WARNING or RMS_Hud.COLOR_GAME_GREEN
end

function RMS_Hud:drawDrivetrainDisplay(vehicle, posX, posY)
    if not RMS_Drivetrain.getIsAvailable(vehicle) then
        return
    end

    local state = RMS_Drivetrain.getState(vehicle)
    if state == nil then
        return
    end

    local iconId, color = RMS_Hud.getDrivetrainDisplay(state, RMS_Drivetrain.getHasCenterDifferential(vehicle), g_time or 0)
    local symbolY, valueY, centreX = drawBubble(self, true, posX, posY, RMS_Hud.DRIVE_INK_HEIGHT[iconId])
    local overlay = self.drivetrainHud.icons[iconId].overlay
    overlay:setPosition(snapScreenX(centreX - overlay.width * 0.5), snapScreenY(symbolY - overlay.height * 0.5))
    overlay:setVisible(true)
    overlay:setColor(color[1], color[2], color[3], color[4])
    overlay:render()

    local modeKey = "rms_hud_drive_2wd"
    if state.driveMode == RMS_Drivetrain.MODE.AUTO then
        modeKey = "rms_hud_drive_auto"
    elseif state.driveMode == RMS_Drivetrain.MODE.FOUR_WD then
        modeKey = "rms_hud_drive_4wd"
    end
    drawBubbleValue(self, centreX, valueY, g_i18n:getText(modeKey), color)
end

---Draws the park brake indicator
function RMS_Hud:drawParkBrakeDisplay(vehicle)
    if self.parkBrakeHud == nil or self.parkBrakeHud.icon == nil then
        return
    end
    if not RMS_Drivetrain.getIsParkBrakeManaged(vehicle) then
        return
    end

    local sm = g_currentMission.hud.speedMeter
    if sm == nil or sm.gearIcon == nil then
        return
    end

    local gearIconX, gearIconY = sm.gearIcon:getPosition()
    local gearIconHeight = sm.gearIcon.height or 0
    local icon = self.parkBrakeHud.icon
    icon:setPosition(gearIconX - self.parkBrakeHud.width - self.parkBrakeHud.gapX,
        gearIconY + (gearIconHeight - (self.parkBrakeHud.height or 0)) * 0.5 + (self.parkBrakeHud.offsetY or 0))
    icon:setVisible(true)

    local colors = RMS_Breakdowns.COLORS
    local color = RMS_Drivetrain.getState(vehicle).parkBrake and colors.CRITICAL or colors.DEFAULT
    icon:setColor(color[1], color[2], color[3], color[4])
    icon:render()
end


---Draws the fuel consumption and load mass cards
function RMS_Hud:drawTelemetryCards()
    local speedMeter = g_currentMission.hud.speedMeter
    if speedMeter == nil or speedMeter.speedBg == nil then
        return
    end

    local cardRightX = speedMeter:getPosition()
    cardRightX = self:drawLoadMass(cardRightX) or cardRightX
    self:drawFuelConsumption(cardRightX)
end

local function getSteeringAssistWidth(vehicle)
    local width = 0
    local root = vehicle.rootVehicle or vehicle

    for _, child in pairs(root.childVehicles or {}) do
        local workAreaSpec = child.spec_workArea
        if workAreaSpec ~= nil and workAreaSpec.workAreas ~= nil then
            for _, workArea in pairs(workAreaSpec.workAreas) do
                if g_workAreaTypeManager:getWorkAreaTypeIsSteeringAssistArea(workArea.type) then
                    width = math.max(width, tonumber(workArea.workWidth) or 0)
                end
            end
        end
    end

    return width
end

---Returns the speed and the area the controlled vehicle works
function RMS_Hud:getConsumptionAreaRate()
    local speed = self.vehicle.getLastSpeed ~= nil and (tonumber(self.vehicle:getLastSpeed()) or 0) or 0
    local width = self.vehicle.getAttacherToolWorkingWidth ~= nil and (tonumber(self.vehicle:getAttacherToolWorkingWidth()) or 0) or 0

    if width <= 0 then
        width = getSteeringAssistWidth(self.vehicle)
    end

    local guidanceSpec = self.vehicle.spec_globalPositioningSystem
    if guidanceSpec ~= nil and guidanceSpec.guidanceData ~= nil and guidanceSpec.guidanceData.width ~= nil then
        width = tonumber(guidanceSpec.guidanceData.width) or width
    end

    -- From km/h and m to ha/h
    return speed, (speed * width) / 10
end

---Clears the consumption samples and their averages
function RMS_Hud:resetConsumptionAverages()
    local state = self.consumption
    state.buckets = {}
    state.current = { litres = 0, hectares = 0 }
    state.timer = 0
    state.perHour = 0
    state.perArea = nil
end

---Uses the native hourly readout and samples the consumption per worked area
function RMS_Hud:updateConsumptionAverages(consumptionPerHour, areaRate)
    local state = self.consumption
    local dt = tonumber(g_currentDt) or 0
    local current = state.current

    -- lastFuelUsageDisplay is already averaged by GIANTS.
    state.perHour = consumptionPerHour

    if areaRate > 0 then
        current.litres = current.litres + consumptionPerHour * dt / (60 * 60 * 1000)
        current.hectares = current.hectares + areaRate * dt / (60 * 60 * 1000)
    end

    state.timer = state.timer + dt
    if state.timer < RMS_Hud.CONSUMPTION_REFRESH_INTERVAL then
        return
    end
    state.timer = 0

    table.insert(state.buckets, 1, current)
    while #state.buckets > RMS_Hud.CONSUMPTION_PER_AREA_BUCKETS do
        table.remove(state.buckets)
    end
    state.current = { litres = 0, hectares = 0 }

    local litresSum, hectaresSum = 0, 0
    for _, bucket in ipairs(state.buckets) do
        litresSum = litresSum + bucket.litres
        hectaresSum = hectaresSum + bucket.hectares
    end

    state.perArea = hectaresSum > 0.0001 and litresSum / hectaresSum or nil
end

---Samples the engine load and refreshes its average once a second
function RMS_Hud:updateMotorLoadAverage(motorLoad)
    local state = self.motorLoadAverage
    local dt = tonumber(g_currentDt) or 0

    state.current.value = state.current.value + motorLoad * dt
    state.current.time = state.current.time + dt
    state.timer = state.timer + dt

    if state.timer >= RMS_Hud.CONSUMPTION_REFRESH_INTERVAL then
        state.timer = 0
        table.insert(state.buckets, 1, state.current)
        while #state.buckets > RMS_Hud.MOTOR_LOAD_BUCKETS do
            table.remove(state.buckets)
        end
        state.current = { value = 0, time = 0 }
    end

    local valueSum, timeSum = 0, 0
    for _, bucket in ipairs(state.buckets) do
        valueSum = valueSum + bucket.value
        timeSum = timeSum + bucket.time
    end

    return timeSum > 0 and valueSum / timeSum or motorLoad
end

local function drawCardSeparator(x, panelY, panelH, color)
    local lineHeight = panelH * 0.55
    local bottom = panelY + (panelH - lineHeight) * 0.5
    drawLine2D(x, bottom, x, bottom + lineHeight, g_pixelSizeX, color[1], color[2], color[3], color[4])
end

---Draws the fuel consumption card
function RMS_Hud:drawFuelConsumption(cardRightX)
    if self.vehicle.spec_RealisticMechanicalSystems == nil or self.vehicle.spec_motorized == nil then
        return
    end

    local _, fuelCapacity, fuelType = SpeedMeterDisplay.getVehicleFuelLevelAndCapacity(self.vehicle)
    if fuelCapacity == nil or fuelCapacity <= 0 then
        return
    end

    local consumptionPerHour = self.vehicle:getIsMotorStarted() and self.vehicle.spec_motorized.lastFuelUsageDisplay or 0
    local speed, areaRate = self:getConsumptionAreaRate()
    self:updateConsumptionAverages(consumptionPerHour, speed > 0.9 and areaRate or 0)

    local isElectric = fuelType == FillType.ELECTRICCHARGE
    local isMethane = fuelType == FillType.METHANE
    local perHourUnit = isElectric and "kW" or (isMethane and "kg/h" or "L/h")
    local perAreaUnit = isElectric and "kWh/ha" or (isMethane and "kg/ha" or "L/ha")
    local perHourStr = formatConsumptionValue(self.consumption.perHour)
    local perAreaStr = self.consumption.perArea ~= nil and formatConsumptionValue(self.consumption.perArea) or "-"

    local speedMeter = g_currentMission.hud.speedMeter
    local size = self.loadMassText.size or 0.01
    local padH = self.loadMassText.paddingH or 0
    local padV = self.loadMassText.paddingV or 0
    local sliceId = isElectric and "gui.icon_electricCharge" or (isMethane and "gui.icon_methane" or "gui.icon_fuel")
    local fuelIcon = RMS_Hud.FUEL_ICON
    local ink = fuelIcon.INK[sliceId]
    local iconBoxWidth = self.fuelConsumptionHud.width or 0
    local inkLeft = iconBoxWidth * ink[1] / fuelIcon.CELL
    local iconWidth = iconBoxWidth * (ink[2] - ink[1]) / fuelIcon.CELL
    local iconHeight = self.fuelConsumptionHud.height or 0
    local iconGap = self.fuelConsumptionHud.iconGap or 0
    local unitGap = self:scalePixelToScreenWidth(4)
    local separatorGap = self:scalePixelToScreenWidth(20)
    local perHourValueWidth = getTextWidth(size, perHourStr)
    local perHourUnitWidth = getTextWidth(size, perHourUnit)
    local perAreaValueWidth = getTextWidth(size, perAreaStr)
    local perAreaUnitWidth = getTextWidth(size, perAreaUnit)
    local perHourWidth = perHourValueWidth + unitGap + perHourUnitWidth
    local perAreaWidth = perAreaValueWidth + unitGap + perAreaUnitWidth
    local fullWidth = iconWidth + iconGap + perHourWidth + separatorGap + perAreaWidth
    local textHeight = getTextHeight(size, perHourStr)
    local panelH = textHeight + padV * 2
    local panelW = fullWidth + padH * 2
    local _, smBottomY = speedMeter:getPosition()
    local panelX = cardRightX - panelW
    local panelY = (smBottomY - panelH) * 0.5
    local startX = panelX + padH
    local textX = startX + iconWidth + iconGap
    local textY = panelY + panelH * 0.5 + self:scalePixelToScreenHeight(2)
    -- Figures of a middle-aligned text sit this far below its anchor.
    local lamp = RMS_Hud.LAMP
    local figuresMiddleY = textY - size * (lamp.VALUE_HEIGHT * 0.5 - lamp.VALUE_TOP) / lamp.VALUE_SIZE

    local bg = HUD.COLOR.BACKGROUND
    drawFilledRectRound(panelX, panelY, panelW, panelH, 0.35, bg[1], bg[2], bg[3], bg[4])

    local icon = self.fuelConsumptionHud.icon
    if self.fuelConsumptionHud.sliceId ~= sliceId then
        icon:setSliceId(sliceId)
        self.fuelConsumptionHud.sliceId = sliceId
    end
    local green = HUD.COLOR.ACTIVE
    icon:setPosition(startX - inkLeft, figuresMiddleY - iconHeight * (1 - ink[3] / fuelIcon.CELL))
    icon:setColor(green[1], green[2], green[3], green[4])
    icon:setVisible(true)
    icon:render()

    drawCardSeparator(textX + perHourWidth + separatorGap * 0.5, panelY, panelH, green)

    setTextStyle(RenderText.ALIGN_LEFT, RenderText.VERTICAL_ALIGN_MIDDLE, true)
    setTextColor(1, 1, 1, 1)
    renderText(textX, textY, size, perHourStr)
    setTextBold(false)
    setTextColor(1, 1, 1, 0.55)
    renderText(textX + perHourValueWidth + unitGap, textY, size, perHourUnit)

    textX = textX + perHourWidth + separatorGap
    setTextBold(true)
    setTextColor(1, 1, 1, 1)
    renderText(textX, textY, size, perAreaStr)
    setTextBold(false)
    setTextColor(1, 1, 1, 0.55)
    renderText(textX + perAreaValueWidth + unitGap, textY, size, perAreaUnit)
end


---Returns the colour of a load severity
function RMS_Hud:getLoadSeverityColor(severity)
    local colors = RMS_Breakdowns.COLORS
    local s = math.clamp(tonumber(severity) or 0, 0, 1)

    if s <= 0 then
        return HUD.COLOR.ACTIVE
    end

    return {
        colors.WARNING[1] + (colors.CRITICAL[1] - colors.WARNING[1]) * s,
        colors.WARNING[2] + (colors.CRITICAL[2] - colors.WARNING[2]) * s,
        colors.WARNING[3] + (colors.CRITICAL[3] - colors.WARNING[3]) * s,
        1
    }
end

---Formats a mass in tons
function RMS_Hud:formatMass(massTons)
    return formatValue(math.max(tonumber(massTons) or 0, 0), "%.1f") .. " t"
end

---Returns a mass that only changes past a threshold
function RMS_Hud:getStableDisplayMass(cacheKey, massTons)
    local mass = math.max(tonumber(massTons) or 0, 0)
    local displayStep = 0.1
    local roundedMass = math.floor(mass / displayStep + 0.5) * displayStep
    local cachedMass = tonumber(self.loadMassText[cacheKey])

    if cachedMass == nil or math.abs(mass - cachedMass) >= displayStep then
        cachedMass = roundedMass
        self.loadMassText[cacheKey] = cachedMass
    end

    return cachedMass
end

---Draws the load mass card
function RMS_Hud:drawLoadMass(cardRightX)
    local vehicle, spec = self.vehicle, self.vehicle.spec_RealisticMechanicalSystems
    if spec == nil then
        return cardRightX
    end

    local selfMass  = tonumber(vehicle:getTotalMass(true)) or 0
    local totalMass = tonumber(vehicle:getTotalMass())     or 0
    local lockedHookLiftContainer = RMS_Utils.getLockedHookLiftContainer(vehicle)
    local carriedMass = lockedHookLiftContainer ~= nil and (tonumber(lockedHookLiftContainer:getTotalMass()) or 0) or 0
    local vehicleMass = math.min(selfMass + carriedMass, totalMass)
    local towedMass = math.max(totalMass - vehicleMass, 0)

    local loadColor = HUD.COLOR.ACTIVE

    if spec.isExcludedVehicle ~= true and towedMass > 0.1 then
        local motor      = vehicle.getMotor ~= nil and vehicle:getMotor() or nil
        local horsepower = math.max(((motor ~= nil and motor.peakMotorPower) or 0) * 1.36, 0.001)
        local isTruck    = spec.isTruck == true
        local ratioBasis = isTruck and totalMass or towedMass
        local powerToWeight = horsepower / math.max(ratioBasis, 0.01)

        local threshold, fullEffect = RMS_Utils.getHeavyTrailerRatioLevels(isTruck)

        local trailerSeverity = RMS_Utils.calculateQuadraticMultiplier(powerToWeight, threshold, true, fullEffect)

        loadColor = self:getLoadSeverityColor(trailerSeverity)
    end

    local _, smBottomY = g_currentMission.hud.speedMeter:getPosition()
    local padH = self.loadMassText.paddingH or 0
    local padV = self.loadMassText.paddingV or 0
    local size = self.loadMassText.size or 0.01
    local sep  = "     "

    local displaySelfMass = self:getStableDisplayMass("displaySelfMass", vehicleMass)
    local displayTowedMass = self:getStableDisplayMass("displayTowedMass", towedMass)
    local displayTotalMass = displaySelfMass + displayTowedMass

    local tractorLabel = g_i18n:getText("rms_hud_mass_tractor") .. "  "
    local tractorValue = self:formatMass(displaySelfMass)
    local chargeLabel  = g_i18n:getText("rms_hud_mass_towed")   .. "  "
    local chargeValue  = self:formatMass(displayTowedMass)
    local totalLabel   = g_i18n:getText("rms_hud_mass_total")    .. "  "
    local totalValue   = self:formatMass(displayTotalMass)

    local wTL  = getTextWidth(size, tractorLabel)
    local wTV  = getTextWidth(size, tractorValue)
    local wCL  = getTextWidth(size, chargeLabel)
    local wCV  = getTextWidth(size, chargeValue)
    local wOL  = getTextWidth(size, totalLabel)
    local wOV  = getTextWidth(size, totalValue)
    local wsep = getTextWidth(size, sep)
    local w1   = wTL + wTV
    local w2   = wCL + wCV
    local w3   = wOL + wOV
    local fullW = w1 + wsep + w2 + wsep + w3

    local textHeight = getTextHeight(size, totalValue)
    local panelH = textHeight + padV * 2
    local panelW = fullW + padH * 2
    local panelX = cardRightX - panelW
    local panelY = (smBottomY - panelH) * 0.5
    local startX = panelX + padH
    local textY  = panelY + panelH * 0.5 + self:scalePixelToScreenHeight(2)

    local bg = HUD.COLOR.BACKGROUND
    drawFilledRectRound(panelX, panelY, panelW, panelH, 0.35, bg[1], bg[2], bg[3], bg[4])

    local green    = HUD.COLOR.ACTIVE
    drawCardSeparator(startX + w1 + wsep * 0.5, panelY, panelH, green)
    drawCardSeparator(startX + w1 + wsep + w2 + wsep * 0.5, panelY, panelH, green)

    local cx = startX
    local dimLabel = {1, 1, 1, 0.55}
    setTextStyle(RenderText.ALIGN_LEFT, RenderText.VERTICAL_ALIGN_MIDDLE, false)
    setTextColor(unpack(dimLabel))
    renderText(cx, textY, size, tractorLabel)
    setTextBold(true)
    setTextColor(1, 1, 1, 1)
    renderText(cx + wTL, textY, size, tractorValue)

    cx = cx + w1 + wsep

    setTextBold(false)
    setTextColor(unpack(dimLabel))
    renderText(cx, textY, size, chargeLabel)
    setTextBold(true)
    setTextColor(loadColor[1], loadColor[2], loadColor[3], 1)
    renderText(cx + wCL, textY, size, chargeValue)

    cx = cx + w2 + wsep

    setTextBold(false)
    setTextColor(unpack(dimLabel))
    renderText(cx, textY, size, totalLabel)
    setTextBold(true)
    setTextColor(loadColor[1], loadColor[2], loadColor[3], 1)
    renderText(cx + wOL, textY, size, totalValue)

    return panelX - (self.telemetryCardGap or 0)
end

---Returns the damage the game's bar shows for the selected machine
function RMS_Hud.getSelectedDamage(vehicle)
    for _, child in ipairs(vehicle.rootVehicle.childVehicles) do
        if child:getIsSelected() and child.getDamageShowOnHud ~= nil and child:getDamageShowOnHud() then
            if child.getLastInspectedCondition == nil then
                return child:getDamageAmount()
            end
            -- An RMS machine shows its last inspection, empty before any
            local condition, isComplete = child:getLastInspectedCondition()
            local bar = RMS_Hud.CONDITION_BAR
            if isComplete == nil then
                return 1
            elseif isComplete then
                return 1 - math.max(condition, bar.FILL_MIN)
            end
            return 1 - bar.FILL_BY_TIER[RMS_Utils.getConditionTier(condition)]
        end
    end
    return nil
end

local shownDamage = 0

local function getShownDamage()
    return shownDamage
end

---Draws the speed meter, its damage bar for the selected machine
function RMS_Hud.drawSpeedMeter(speedMeter, superFunc)
    local vehicle = speedMeter.vehicle
    local damage
    if vehicle ~= nil and speedMeter.isVehicleDrawSafe then
        local spec = vehicle.spec_RealisticMechanicalSystems
        if spec == nil or not spec.isExcludedVehicle then
            damage = RMS_Hud.getSelectedDamage(vehicle)
        end
    end
    if damage == nil then
        superFunc(speedMeter)
        return
    end

    -- The game shows the worst damage; all report the shown one
    shownDamage = damage
    local vehicles = vehicle.rootVehicle.childVehicles
    local getDamageAmounts = {}
    for index, child in ipairs(vehicles) do
        getDamageAmounts[index] = child.getDamageAmount
        if child.getDamageAmount ~= nil then
            child.getDamageAmount = getShownDamage
        end
    end
    superFunc(speedMeter)
    for index, child in ipairs(vehicles) do
        child.getDamageAmount = getDamageAmounts[index]
    end
end

---Adds the grease points due, else what is left before the next ones
local function addGreasingLine(vehicle, box)
    local spec = RMS_Greasing.getSpec(vehicle)
    if spec == nil or not spec.isVehicleNeedLubricate then
        return
    end

    local greasing = RMS_Greasing.read(vehicle)
    if greasing.due > 0 then
        box:addLine(g_i18n:getText("rms_inspection_status_grease_due"), tostring(greasing.due), greasing.state == "late")
    else
        box:addLine(g_i18n:getText("rms_fleet_greasing_next"), greasing.next ~= nil and RMS_Utils.formatGreasingLeft(greasing.next)
            or g_i18n:getText("rms_fleet_greasing_period_day"))
    end
end

---Adds the RMS lines to the vanilla vehicle info box
function RMS_Hud:showInfoVehicle(box)
    local spec = self.spec_RealisticMechanicalSystems
    if spec == nil then
        addGreasingLine(self, box)
        return
    elseif spec.isExcludedVehicle then
        return
    end

    local schedule = self:getServiceSchedule()
    local _, isReportOutdated = self:getInspectionReportAge()
    box:addLine(g_i18n:getText('rms_ws_label_condition'), RMS_Utils.formatCondition(self:getLastInspectedCondition()), isReportOutdated)
    if schedule ~= nil then
        -- Native info-box rows cannot resize text.
        box:addLine(RMS_Utils.formatMaintenanceLevel(self, schedule.maintenanceType), RMS_Utils.formatServiceDeadline(schedule), schedule.overdue)
    end
    addGreasingLine(self, box)

    if spec.batteryIsolated then
        box:addLine(g_i18n:getText("rms_battery_isolator_info"), nil, true)
    end

    local state = spec.currentState
    if state ~= RealisticMechanicalSystems.STATUS.READY and state ~= RealisticMechanicalSystems.STATUS.BROKEN then
        box:addLine(string.format(g_i18n:getText("rms_spec_last_maintenance_until_format"), RMS_Utils.formatServiceState(state),
            RMS_Utils.formatFinishTime(self:getServiceFinishTime())))
    end
end

Vehicle.showInfo = Utils.appendedFunction(Vehicle.showInfo, RMS_Hud.showInfoVehicle)
SpeedMeterDisplay.draw = Utils.overwrittenFunction(SpeedMeterDisplay.draw, RMS_Hud.drawSpeedMeter)
