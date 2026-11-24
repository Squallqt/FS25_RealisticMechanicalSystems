-- Copyright © 2026 Squallqt. All rights reserved.

---Vehicle dashboard and notifications
RMS_Hud = {}
local RMS_Hud_mt = Class(RMS_Hud, HUDDisplay)

RMS_Hud.COLOR_GAME_GREEN = HUD.COLOR.ACTIVE
RMS_Hud.INSPECTION_RING_SIZE = 138
RMS_Hud.INSPECTION_PERCENT_SHARE = 0.22
RMS_Hud.INSPECTION_SHADE_ALPHA = 0.55
RMS_Hud.INSPECTION_LABEL_SIZE = 17
RMS_Hud.POWER_REFRESH_MS = 250
RMS_Hud.GEARBOX_OIL_ALERT_TEMP = { DEFAULT = 105, TRUCK = 121 }
RMS_Hud.NOTIFICATION_DURATION_MS = 3000
RMS_Hud.LAMP_BLINK = { PHASE_MS = 500, SHORT_PHASES = 8 }
RMS_Hud.LIT_LAMP_COLOR = { oil = "CRITICAL", battery = "CRITICAL", coolant = "CRITICAL", engine = "WARNING",
    preheat = "WARNING", dpf = "WARNING", service = "WARNING", tractionBattery = "WARNING", limitedPower = "WARNING" }
RMS_Hud.LAMP_BEEP_PAUSE_MS = { DEFAULT = 1800, warning = 1400, service = 2500 }
RMS_Hud.CONDITION_BAR = { FILL_MIN = 0.1, FILL_BY_TIER = { 1, 0.75, 0.5, 0.25, 0.1 } }
RMS_Hud.INDICATOR_ORDER = { "transmission", "engine", "brakes", "battery", "coolant", "dpf", "fanReversal", "preheat",
    "oil", "service", "tractionBattery", "limitedPower", "warning" }
RMS_Hud.LAMP_INK = {
    preheat = { 58, 35, 19 }, warning = { 60, 53, 10 }, oilPressure = { 68, 54, 9 }, oilCan = { 60, 22, 25 },
    limitedPower = { 60, 31, 21 }, tractionBattery = { 58, 43, 15 }, adBlue = { 60, 57, 7 }
}
RMS_Hud.LAMP = { SIZE = 19.2, CELL = 72 }
RMS_Hud.LAMP_SCALE = { preheat = 1.2516, oilCan = 1.5521, limitedPower = 1.3075, tractionBattery = 1.1292 }
RMS_Hud.ROW = { PITCH = 28 }
RMS_Hud.GLOW = { SIZE = 30.4, ALPHA = 0.35 }
RMS_Hud.DASHBOARD = {
    ENGINE_LAMPS = { "engine", "dpf", "fanReversal" },
    READINGS = { "service", "battery", "transmission" },
    LEGACY_READINGS = { "service", "transmission", "battery" },
    PICTO = { engine = "engine", dpf = "particulateFilter", fanReversal = "fanReversal", service = "serviceBook",
        transmission = "transmissionTemperature", battery = "battery", coolant = "coolantAgri", brakes = "brakes", parkBrake = "parkBrake" },
    WATER_SCALE = { LOW = 40, HIGH = 120 },
    LABEL = { 0.5149, 0.5149, 0.5149, 1 },
    SEGMENT_UNLIT = { 0.3049, 0.3049, 0.3049, 0.75 },
    HAIRLINE = { 1, 1, 1, 0.08 },
    RIM = { 1, 1, 1, 0.15 },
    POD_GLASS = { 0, 0, 0, 0.6 },
    OUTLINE = { SAGITTA = 0.05, MIN_STROKE = 1, NUDGE = 0.02, NUDGE_STEPS = 50, TAPER = 6, STRAIGHT = 8 },
    HALO = { MARGIN = 5, ALPHA = 0.45, LEAD_ALPHA = 0.6 },
    LAMP_GLOW = { SIZE = 30, ALPHA = 0.38, GREEN_ALPHA = 0.3 },
    UNIT_GAP = 2,
    READING_PICTO_OFFSET = -3,
    SLIP_READING_OFFSET = 2
}
RMS_Hud.FUEL_ICON = { SIZE = 24, CELL = 30, GAP = 6, INK_HEIGHT = 18, INK_AREA = 0.1539,
    INK = { ["gui.icon_fuel"] = { 8, 23, 16.94 }, ["gui.icon_electricCharge"] = { 2, 28, 15.51 },
        ["gui.icon_methane"] = { 8, 22, 15.59 } } }
RMS_Hud.WEIGHT_ICON = { SLICE = "gui.storeAttribute_maxLoadCapacity", CELL = 36, INK_AREA = 0.4158, INK = { 4, 32, 20.25 } }
RMS_Hud.CARD_GAP = { LABEL = 6, UNIT = 4, AVERAGE = 12, SEPARATOR = 20 }
RMS_Hud.CARD_SCALE = 12 / 13
RMS_Hud.FIGURES_MIDDLE = 13.24 / 35
RMS_Hud.CARD_END_SPACE = { a = 0.1187, h = 0.1087, ["а"] = 0.1277, ["顷"] = 0.0371, t = 0.0018, ["т"] = 0.0381,
    u = 0.1199, ["ч"] = 0.1439, ["д"] = 0.0263, ["时"] = 0.0357, W = 0.0289, ["瓦"] = 0.0385 }

---Returns a value formatted, 0 when it rounds to zero
-- @param float value value
-- @param string numberFormat format of the value
-- @return string text formatted value
local function formatValue(value, numberFormat)
    local text = string.format(numberFormat, value)

    if text == string.format(numberFormat, 0) then
        return "0"
    end

    return text
end

---Returns a consumption to a tenth under 100, whole above
-- @param float value consumption
-- @return string text formatted consumption
local function formatConsumptionValue(value)
    local amount = math.max(value, 0)
    return formatValue(amount, amount < 100 and "%.1f" or "%.0f")
end

---Returns an x on the pixel grid
-- @param float x x (screen)
-- @return float x x on the pixel grid (screen)
local function snapScreenX(x)
    return math.floor(x * g_screenWidth + 0.5) / g_screenWidth
end

---Returns a y on the pixel grid
-- @param float y y (screen)
-- @return float y y on the pixel grid (screen)
local function snapScreenY(y)
    return math.floor(y * g_screenHeight + 0.5) / g_screenHeight
end

---Draws a rule of whole pixels; off the grid a line can vanish
-- @param float x left (screen)
-- @param float y bottom (screen)
-- @param float width width (screen)
-- @param float height height (screen)
-- @param table color rgba color
local function drawRule(x, y, width, height, color)
    width = math.max(math.floor(width * g_screenWidth + 0.5), 1) / g_screenWidth
    height = math.max(math.floor(height * g_screenHeight + 0.5), 1) / g_screenHeight
    drawFilledRect(snapScreenX(x), snapScreenY(y), width, height, color[1], color[2], color[3], color[4])
end

---Sets the text alignments and weight
-- @param integer alignment RenderText alignment
-- @param integer verticalAlignment RenderText vertical alignment
-- @param boolean isBold true for bold
local function setTextStyle(alignment, verticalAlignment, isBold)
    setTextAlignment(alignment)
    setTextVerticalAlignment(verticalAlignment)
    setTextBold(isBold)
end

---Create instance of RMS_Hud, loading its overlays
-- @return table self instance of the HUD
function RMS_Hud:new()
    local self = RMS_Hud:superClass().new(RMS_Hud_mt)

    self.fuelConsumptionHud = {
        icon = g_overlayManager:createOverlay("gui.icon_fuel", 0, 0, 0, 0),
        sliceId = "gui.icon_fuel"
    }
    self.loadMassHud = {
        icon = g_overlayManager:createOverlay(RMS_Hud.WEIGHT_ICON.SLICE, 0, 0, 0, 0)
    }
    local pieces = RMS_HudLayout.pieces
    self.dashboard = {
        glass = g_overlayManager:createOverlay(pieces.panelShade, 0, 0, 0, 0),
        piece = g_overlayManager:createOverlay(pieces.window, 0, 0, 0, 0),
        glow = g_overlayManager:createOverlay(pieces.glow, 0, 0, 0, 0),
        stroke = g_overlayManager:createOverlay(pieces.stroke, 0, 0, 0, 0),
        gauge = g_overlayManager:createOverlay(RMS_HudLayout.gauges.water.piece, 0, 0, 0, 0)
    }
    self.glasses = {}

    self.lampGlow = g_overlayManager:createOverlay("rms_LampGlow.glow", 0, 0, 0, 0)

    self.meterStraight = g_overlayManager:createOverlay("rms_Hud.backgroundStraight", 0, 0, 0, 0)

    self.lampIcons = {}
    for slice in pairs(RMS_Hud.LAMP_INK) do
        self.lampIcons[slice] = g_overlayManager:createOverlay("rms_Hud." .. slice, 0, 0, 0, 0)
    end
    self.lampStates = {}
    self.lampColors, self.routineLamps, self.resolvedLamps = {}, {}, {}
    self.dashboardLamps = { count = 0 }
    self.telemetryText = {}
    self.shownMasses = {}

    self.inspectionProgress = { messageEndTime = 0 }

    return self
end

---Deletes the overlays of the HUD
function RMS_Hud:delete()
    self.fuelConsumptionHud.icon:delete()
    self.loadMassHud.icon:delete()
    self.meterStraight:delete()

    for _, overlay in pairs(self.dashboard) do
        overlay:delete()
    end
    self.lampGlow:delete()

    for _, icon in pairs(self.lampIcons) do
        icon:delete()
    end

    RMS_Hud:superClass().delete(self)
end

---Binds the HUD to a vehicle
-- @param table? vehicle vehicle controlled
function RMS_Hud:setVehicle(vehicle)
    if vehicle == self.vehicle then
        return
    end
    self.vehicle = vehicle
    self.lampStates = {}
    self.vehicleDashboard = nil
    self.powerReading = nil
end

---Blinks and beeps a lamp once as it lights up or turns red
-- @param string id lamp
-- @param integer severity 0 off, then rising with the colour of the lamp
-- @param boolean isMotorOn true while the motor runs
-- @param boolean canBlink true when the lamp may blink
function RMS_Hud:updateLampAlert(id, severity, isMotorOn, canBlink)
    local state = self.lampStates[id]
    if state == nil then
        state = { severity = 0, beepSeverity = 0 }
        self.lampStates[id] = state
    end

    if severity > state.severity then
        state.blinkTime = canBlink and 0 or nil
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
-- @param string id lamp
-- @param table color rgba color of the lit lamp
-- @param boolean isContinuous true for a lamp that keeps blinking
-- @param boolean canBlink true when the lamp may blink
-- @return table color rgba color shown
function RMS_Hud:getLampBlinkColor(id, color, isContinuous, canBlink)
    local state = self.lampStates[id]
    if state.blinkTime == nil then
        return color
    end

    local blink = RMS_Hud.LAMP_BLINK
    local phase = math.floor(state.blinkTime / blink.PHASE_MS)
    if not canBlink or (not isContinuous and phase >= blink.SHORT_PHASES) then
        state.blinkTime = nil
        return color
    end
    state.blinkTime = state.blinkTime + g_currentDt
    if phase % 2 == 1 then
        return RMS_Breakdowns.COLORS.DEFAULT
    end
    return color
end

local hasCVTAddon = RMS_Utils.hasCVTAddon

---Draws the whole HUD for the current frame
function RMS_Hud:draw()
    if not g_currentMission.hud.isVisible then
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

---Shows a notification on the shared HUD instance, with its sound
-- @param string text text
-- @param string title title
function RMS_Hud.showNotification(text, title)
    if RMS_Main.hud ~= nil then
        RMS_Main.hud:setNotification(text, title)
    end
end

---Sets the inspection progress on the shared HUD instance
-- @param float? ratio progress, 0 to 1, nil to hide it
function RMS_Hud.showInspectionProgress(ratio)
    if RMS_Main.hud ~= nil then
        RMS_Main.hud:setInspectionProgress(ratio)
    end
end

---Shows a message where the inspection ring stood on the shared HUD instance
-- @param string text text
-- @param float durationMs duration (ms)
function RMS_Hud.showInspectionMessage(text, durationMs)
    if RMS_Main.hud ~= nil then
        RMS_Main.hud:setInspectionMessage(text, durationMs)
    end
end

---Shows a notification in place of the one on screen, with its sound
-- @param string text text
-- @param string title title
function RMS_Hud:setNotification(text, title)
    self.notification = { text = text, title = utf8ToUpper(title), endTime = g_time + RMS_Hud.NOTIFICATION_DURATION_MS }
    RMS_SoundManager.playSample(RMS_Main.samples.notification2D)
end

---Stores the progress the inspection ring draws, absent to hide it
-- @param float? ratio progress, 0 to 1, nil to hide it
function RMS_Hud:setInspectionProgress(ratio)
    local progress = self.inspectionProgress
    progress.ratio = ratio

    if progress.ratio ~= nil then
        progress.messageText = nil
    end
end

---Stores the message shown where the inspection ring stood
-- @param string text text
-- @param float durationMs duration (ms)
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

---Tells whether a notification is on screen
-- @return boolean isShown true while one shows
function RMS_Hud:getIsNotificationShown()
    local notification = self.notification
    return notification ~= nil and g_time < notification.endTime
end

---Returns the widest notification
-- @return float width width (screen)
function RMS_Hud:getNotificationMaxWidth()
    local speedMeter = g_currentMission.hud.speedMeter
    local meterX = speedMeter.speedBg.x + speedMeter.speedGaugeCenterOffsetX
    local left = meterX + self:scalePixelToScreenWidth(RMS_HudLayout.left)
    return (left - 0.5 - self.messagePaddingX) * 2
end

---Returns the bottom of a notification, above the cards and action band
-- @return float bottom bottom (screen)
function RMS_Hud:getNotificationBottom()
    local hud = g_currentMission.hud
    local band = hud.contextActionDisplay
    local bottom = g_hudAnchorBottom + RMS_Hud.getSpeedMeterLift(self.vehicle)
    if not band:getVisible() or band.controls == nil or hud.ingameMessage:getVisible() then
        return bottom
    end
    -- the band as its draw lays it out
    setTextWrapWidth(band.textMaxWidth)
    local height = getTextHeight(band.textSize, band.text) + band.titleTextOffsetY + band.titleTextSize
    setTextWrapWidth(0)
    height = math.max(height, band.iconOverlay.height, band.buttonHeight)
    local _, bandY = band:getPosition()
    return math.max(bottom, bandY + height + self.messagePaddingY)
end

---Draws the notification: title, line, text and line
function RMS_Hud:drawNotification()
    if not self:getIsNotificationShown() then
        return
    end

    local notification = self.notification
    local title = notification.title
    local paddingX, paddingY = self.messagePaddingX, self.messagePaddingY
    setTextStyle(RenderText.ALIGN_CENTER, RenderText.VERTICAL_ALIGN_TOP, false)
    local posY = self:getNotificationBottom()
    local width = getTextWidth(self.messageTextSize, notification.text) + 2 * paddingX
    width = math.max(math.min(width, self:getNotificationMaxWidth()), self.messageWidth)
    setTextWrapWidth(width - 2 * paddingX)
    local textHeight = getTextHeight(self.messageTextSize, notification.text)
    setTextBold(true)
    local titleHeight = getTextHeight(self.messageTitleSize, title)
    local height = textHeight + 2 * paddingY + titleHeight + 2 * self.messageTitleGap + self.messageBottomGap + 2 * g_pixelSizeY

    local posX = 0.5 - width * 0.5
    local background = HUD.COLOR.BACKGROUND_DARK
    drawFilledRectRound(posX, posY, width, height, 0.25, background[1], background[2], background[3], background[4])

    local green = RMS_Hud.COLOR_GAME_GREEN
    local lineStart, lineEnd = posX + paddingX, posX + width - paddingX
    local textY = posY + height - paddingY
    setTextColor(green[1], green[2], green[3], green[4])
    renderText(0.5, textY, self.messageTitleSize, title)
    textY = textY - titleHeight - self.messageTitleGap - g_pixelSizeY * 0.5
    drawRule(lineStart, textY - g_pixelSizeY * 0.5, lineEnd - lineStart, g_pixelSizeY, green)
    textY = textY - g_pixelSizeY * 0.5 - self.messageTitleGap
    local lineY = textY - textHeight - self.messageBottomGap - g_pixelSizeY * 0.5
    drawRule(lineStart, lineY - g_pixelSizeY * 0.5, lineEnd - lineStart, g_pixelSizeY, green)

    setTextBold(false)
    setTextColor(1, 1, 1, 1)
    renderText(0.5, textY, self.messageTextSize, notification.text)
    setTextWrapWidth(0)
end

---Sizes the icon of a card, in a square of px reference pixels
-- @param table card card
-- @param float px side of the square (reference pixels)
function RMS_Hud:storeCardIcon(card, px)
    local scale = RMS_Hud.CARD_SCALE
    card.width, card.height = self:scalePixelValuesToScreenVector(px * scale, px * scale)
    card.icon:setDimension(card.width, card.height)
    card.iconGap = self:scalePixelToScreenWidth(RMS_Hud.FUEL_ICON.GAP * scale)
end

---Recomputes every HUD size and position for the current screen resolution
function RMS_Hud:storeScaledValues()
    self.glasses = {}
    self.gaugeGeometry = {}
    self.vehicleDashboard = nil
    self.odometerLayout = nil
    ---Returns a size on whole screen pixels, one at least
    -- @param float width width (screen)
    -- @param float height height (screen)
    -- @return float width width on whole pixels (screen)
    -- @return float height height on whole pixels (screen)
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

    local speedMeter = g_currentMission.hud.speedMeter
    local serviceAnchorY = (speedMeter.gaugeTextOffsets[4].offsetY + speedMeter.gaugeTextOffsets[7].offsetY) * 0.5
    self.rowCenterY = serviceAnchorY - self:scalePixelToScreenHeight(10)
    -- The service anchor is the foot of an 11 px mark
    self.serviceCentreY = serviceAnchorY + self:scalePixelToScreenHeight(5.5)

    self.lampGlow:setDimension(pixelSize(RMS_Hud.GLOW.SIZE, RMS_Hud.GLOW.SIZE))

    local cardScale = RMS_Hud.CARD_SCALE
    self.telemetryText.size = self:scalePixelToScreenHeight(13 * cardScale)
    self.telemetryText.paddingH, self.telemetryText.paddingV = self:scalePixelValuesToScreenVector(10 * cardScale, 4 * cardScale)
    self.telemetryCardGap = self:scalePixelToScreenWidth(4 * cardScale)
    -- the game's gap between its meter and its fill levels
    self.telemetryCardGapY = self:scalePixelToScreenHeight(4)

    local fuelIcon, weightIcon = RMS_Hud.FUEL_ICON, RMS_Hud.WEIGHT_ICON
    -- the weight with as much ink as the pump
    local weightSize = fuelIcon.SIZE * math.sqrt(fuelIcon.INK_AREA / weightIcon.INK_AREA)
    self:storeCardIcon(self.fuelConsumptionHud, fuelIcon.SIZE)
    self:storeCardIcon(self.loadMassHud, weightSize)

    self.messageWidth = self:scalePixelToScreenWidth(640)
    self.messagePaddingX, self.messagePaddingY = self:scalePixelValuesToScreenVector(20, 20)
    self.messageTitleSize = self:scalePixelToScreenHeight(19)
    self.messageTextSize = self:scalePixelToScreenHeight(17)
    self.messageTitleGap = self:scalePixelToScreenHeight(10)
    self.messageBottomGap = self:scalePixelToScreenHeight(15)
end

---Tells whether a full particulate filter waits for its regeneration
-- @param table spec RMS specialization of the vehicle
-- @return boolean isCalling true while it waits
function RMS_Hud.getIsParticulateFilterCalling(spec)
    return spec.fuelState.particulateFilterLevel >= 1 and not spec.fuelState.isParticulateFilterRegenerating
end

---Returns the lift aligning a row lamp by its ink
-- @param string slice picture of the lamp
-- @return float lift lift (reference pixels)
function RMS_Hud.getRowLampLift(slice)
    local lamp = RMS_Hud.LAMP
    ---Returns the foot of the ink of a lamp about the middle of its cell
    -- @param string name picture of the lamp
    -- @return float foot foot (reference pixels)
    local function foot(name)
        return (RMS_Hud.LAMP_INK[name][3] - lamp.CELL * 0.5) * lamp.SIZE * (RMS_Hud.LAMP_SCALE[name] or 1) / lamp.CELL
    end
    local reference = slice == "oilCan" and "preheat" or slice
    return foot("warning") - foot(reference)
end

---Returns the picture of a dial lamp
-- @param string id lamp
-- @param boolean isRoadVehicle true for a road vehicle
-- @return string slice picture
function RMS_Hud.getDialLampSlice(id, isRoadVehicle)
    if id == "oil" then
        return isRoadVehicle and "oilCan" or "oilPressure"
    end
    return id
end

---Tells whether the engine oil pump draws air, lighting the oil lamp
-- @param table spec RMS specialization of the vehicle
-- @return boolean isLow true while it draws air
function RMS_Hud.getIsOilPressureLow(spec)
    return spec.pickupUncovered ~= nil and spec.pickupUncovered.engineOil == true
end

---Returns the coolant lamp colour key for the drive temperature
-- @param table spec RMS specialization of the vehicle
-- @return string? state "CRITICAL" or "WARNING", nil when off
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

---Returns the colour a lit lamp has
-- @param string id lamp
-- @param table color rgba color asked
-- @param table spec RMS specialization of the vehicle
-- @return table color rgba color
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
-- @param table vehicle vehicle
-- @param integer motorState MotorState
-- @param boolean isServiceOverdue true when the service is overdue
-- @param table? cvtFaultColor rgba color of a gearbox fault
-- @param table lampColors colors by lamp, filled
-- @param table isRoutine routine lamps by lamp, filled
-- @return table lampColors colors by lamp
-- @return table isRoutine routine lamps by lamp
function RMS_Hud.getLampColors(vehicle, motorState, isServiceOverdue, cvtFaultColor, lampColors, isRoutine)
    local spec = vehicle.spec_RealisticMechanicalSystems
    local colors = RMS_Breakdowns.COLORS
    local isOff = motorState == MotorState.OFF
    -- A routine lamp is a check or a normal operation: no blink, no beep

    for _, id in ipairs(RMS_Hud.INDICATOR_ORDER) do
        lampColors[id] = colors.DEFAULT
        isRoutine[id] = nil
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
    if motorState == MotorState.IGNITION or motorState == MotorState.STARTING then
        for _, id in ipairs({ "battery", "oil" }) do
            if lampColors[id] == colors.DEFAULT then
                lampColors[id], isRoutine[id] = colors.WARNING, true
            end
        end
    end
    return lampColors, isRoutine
end

---Returns the steps a reading shows
-- @param integer shown steps shown
-- @param float value value in steps
-- @return integer steps steps to show
local function holdSteps(shown, value)
    local reached = math.floor(value)
    if reached >= shown then
        return reached
    end
    return math.min(shown, math.floor(value + 0.5))
end

---Tells whether the wear counts an engine load as an overload
-- @param table vehicle vehicle
-- @param float load engine load
-- @return boolean isOverloaded true for an overload
function RMS_Hud.getIsOverloaded(vehicle, load)
    -- the load the wear reads
    local stockLoad = RealisticMechanicalSystems.sanitizeNumber(RMS_EngineRemap.getStockLoad(vehicle, load), 0, 0, 1.5)
    return stockLoad > RMS_Config.CORE.ENGINE_FACTOR_DATA.MOTOR_OVERLOADED_THRESHOLD * RMS_EngineRemap.getOverloadRatio(vehicle)
end

---Updates the power gauge and its figure
-- @param table vehicle vehicle
-- @param boolean isRunning engine running
-- @return integer squares squares lit
-- @return string figure whole percent
-- @return boolean isWarning true for an overload
function RMS_Hud:updatePowerReading(vehicle, isRunning)
    if not isRunning then
        self.powerReading = nil
        return 0, "0", false
    end
    local load = vehicle:getMotor():getSmoothLoadPercentage()
    local squares = math.clamp(load, 0, 1) * RMS_HudLayout.gauges.power.count
    local reading = self.powerReading
    if reading == nil then
        reading = { buffer = ValueBuffer.new(RMS_Hud.POWER_REFRESH_MS), time = 0, squares = 0,
            figure = math.floor(math.clamp(load * 100, 0, 100)) }
        self.powerReading = reading
    end
    reading.buffer:add(load)
    reading.time = reading.time + g_currentDt
    if reading.time > RMS_Hud.POWER_REFRESH_MS then
        reading.time = 0
        reading.figure = holdSteps(reading.figure, math.clamp(reading.buffer:getAverage() * 100, 0, 100))
    end
    reading.squares = holdSteps(reading.squares, squares)
    return reading.squares, string.format("%d", reading.figure), RMS_Hud.getIsOverloaded(vehicle, load)
end

---Tells whether a machine has a screen
-- @param table vehicle vehicle
-- @return boolean hasScreen true with a screen
function RMS_Hud.getHasScreen(vehicle)
    return RMS_Utils.getHasDashboardScreen(vehicle)
end

---Returns the picture of a dashboard lamp
-- @param string id lamp
-- @param table spec RMS specialization of the vehicle
-- @param boolean isRoadVehicle true for a road vehicle
-- @param boolean isMachine true for a working machine
-- @return string picto picture
function RMS_Hud.getDashboardPicto(id, spec, isRoadVehicle, isMachine)
    if id == "engine" and (isRoadVehicle or spec.isElectricVehicle) then
        return "engineClassic"
    elseif id == "coolant" and isRoadVehicle then
        return "coolantRoad"
    elseif id == "service" and (isRoadVehicle or isMachine) then
        return "wrench"
    end
    return RMS_Hud.DASHBOARD.PICTO[id]
end

local DRIVE_LAMPS = { P = "park", B = "brakes", D = "diff" }
local DRIVE_READINGS = { R = "pto", T = "fwd", S = "slip" }

local panels = {} -- dialKey -> engine -> drive -> panel

---Returns the cached panel of a layout
-- @param string dialKey dial
-- @param table? engine engine block of the layout
-- @param table? drive drivetrain block of the layout
-- @return table panel panel
local function getPanel(dialKey, engine, drive)
    local byEngine = panels[dialKey]
    if byEngine == nil then
        byEngine = {}
        panels[dialKey] = byEngine
    end
    local byDrive = byEngine[engine or false]
    if byDrive == nil then
        byDrive = {}
        byEngine[engine or false] = byDrive
    end
    local panel = byDrive[drive or false]
    if panel == nil then
        local blocks = {}
        blocks[#blocks + 1] = engine
        blocks[#blocks + 1] = drive
        panel = { glass = RMS_HudLayout.panel[dialKey], blocks = blocks }
        byDrive[drive or false] = panel
    end
    return panel
end

---Returns what a machine's dashboard shows
-- @param table vehicle vehicle
-- @param boolean isRoadVehicle true for a road vehicle
-- @return table content screen, windows, readings, drivetrain and panel of the dashboard
function RMS_Hud.getDashboardContent(vehicle, isRoadVehicle)
    local isFitted = RealisticMechanicalSystems.getIsTelltaleFitted
    local hasScreen = RMS_Hud.getHasScreen(vehicle)
    local family = hasScreen and "screen" or "plain"
    local windows, readings = {}, {}
    for _, id in ipairs(RMS_Hud.DASHBOARD.ENGINE_LAMPS) do
        if isFitted(vehicle, id) then
            windows[#windows + 1] = id
        end
    end
    local spec = vehicle.spec_RealisticMechanicalSystems
    local readingOrder = hasScreen and RMS_Hud.DASHBOARD.READINGS or RMS_Hud.DASHBOARD.LEGACY_READINGS
    for _, id in ipairs(readingOrder) do
        if isFitted(vehicle, id) then
            -- an electric's reducer has its lamp, no oil reading
            local isReading = hasScreen and not (id == "transmission" and spec.isElectricVehicle)
            local list = isReading and readings or windows
            list[#list + 1] = id
        end
    end

    local drivetrain = nil
    if RMS_Drivetrain.getIsAvailable(vehicle) then
        drivetrain = RMS_Drivetrain.getState(vehicle)
    end
    local hasTile = drivetrain ~= nil and RMS_Drivetrain.getHasCenterDifferential(vehicle)
    local hasSlip = hasScreen and not isRoadVehicle
    local hasBrakes = isFitted(vehicle, "brakes")
    local hasParkBrake = RMS_Drivetrain.getIsParkBrakeManaged(vehicle)
    local row1 = (hasTile and "T" or "") .. (drivetrain ~= nil and "D" or "")
    local row2 = ""
    -- without a screen, the brake lamp sits with the other lamps
    if hasScreen then
        row1 = (hasParkBrake and "P" or "") .. (hasBrakes and "B" or "") .. (drivetrain ~= nil and "D" or "")
        local hasPto = RMS_Utils.getHasPtoDisplay(vehicle)
        row2 = (hasPto and "R" or "") .. (hasTile and "T" or "") .. (hasSlip and "S" or "")
    else
        local index = #windows + 1
        if hasBrakes and hasParkBrake and index % 3 == 0 then
            index = index - 1
        end
        if hasBrakes then
            table.insert(windows, index, "brakes")
            index = index + 1
        end
        if hasParkBrake then
            table.insert(windows, index, "parkBrake")
        end
    end

    local layout = RMS_HudLayout
    local engine = nil
    if #windows > 0 or #readings > 0 then
        if hasScreen then
            engine = layout.engine[string.format("screen:%d:%d", #windows, #readings)]
        else
            engine = layout.engine[string.format("plain:%d:0", #windows)]
        end
    end
    local driveTag = engine ~= nil and engine.driveTag or "none"
    local driveKey = hasScreen and (#row1 .. ":" .. (row2 == "R" and "R" or #row2)) or (row1 .. ":" .. row2)
    local driveLayout = layout.drive[family .. ":" .. driveTag .. ":" .. driveKey]
    local drive = (row1 ~= "" or row2 ~= "") and driveLayout or nil
    if drive ~= nil and hasScreen then
        drive = { top = driveLayout.top, bottom = driveLayout.bottom, outer = driveLayout.outer,
            notch = driveLayout.notch, hairlines = driveLayout.hairlines }
        for index = 1, #row1 do
            drive[DRIVE_LAMPS[row1:sub(index, index)]] = driveLayout.lamps[index]
        end
        for index = 1, #row2 do
            drive[DRIVE_READINGS[row2:sub(index, index)]] = driveLayout.readings[index]
        end
    end
    local dialKey = "screen"
    if not hasScreen then
        dialKey = isFitted(vehicle, "coolant") and "plain" or "bare"
    end
    local pod = nil
    if dialKey ~= "bare" then
        pod = hasScreen and "water" or "plain"
    end
    return { hasScreen = hasScreen, windows = windows, readings = readings, drivetrain = drivetrain,
        hasParkBrake = hasParkBrake, engine = engine, drive = drive, pod = pod,
        panel = getPanel(dialKey, engine, drive ~= nil and driveLayout or nil), dial = layout.dial[dialKey],
        driveGlass = drive ~= nil and driveLayout or nil }
end

---Formats a figure to one decimal
-- @param float value value
-- @return string text formatted value
local function formatTenths(value)
    local tenths = math.floor(math.max(tonumber(value) or 0, 0) * 10 + 0.5)
    return string.format("%d%s%d", math.floor(tenths / 10), g_i18n.decimalSeparator, tenths % 10)
end

---Returns a reading's figure and its unit
-- @param table vehicle vehicle
-- @param table spec RMS specialization of the vehicle
-- @param string id reading
-- @return string figure figure
-- @return string unit unit
function RMS_Hud.getReading(vehicle, spec, id)
    if id == "service" then
        local used, interval = vehicle:getServiceCountdown()
        if interval <= 0 then
            return "-", ""
        end
        return formatTenths(used), "/" .. g_i18n:formatNumber(interval, 1) .. " " .. g_i18n:getText("rms_spec_op_hours_short")
    elseif id == "transmission" then
        local temperature = math.min(spec.transmissionTemperature, RMS_Config.THERMAL.OIL_GAUGE_MAX)
        return string.format("%.0f", g_i18n:getTemperature(temperature)), g_i18n:getTemperatureUnit()
    end
    return formatTenths(spec.batteryIsolated and 0 or spec.systemVoltageV), "V"
end

---Returns the water gauge's figure and unit
-- @param table spec RMS specialization of the vehicle
-- @return string figure figure
-- @return string unit unit
function RMS_Hud.getWaterFigure(spec)
    return string.format("%.0f", g_i18n:getTemperature(spec.engineTemperature)), g_i18n:getTemperatureUnit()
end

---Returns the front-wheel drive lamp's colour
-- @param table state drivetrain state
-- @param table vehicle vehicle
-- @return table color rgba color
function RMS_Hud.getFrontWheelDriveColor(state, vehicle)
    local isDriving = state.driveMode == RMS_Drivetrain.MODE.FOUR_WD
        or (state.driveMode == RMS_Drivetrain.MODE.AUTO and state.autoEngaged)
        or (state.diffLockEngaged and RMS_Drivetrain.getHasDriveManagement(vehicle))
    if not isDriving then
        return RMS_Breakdowns.COLORS.DEFAULT
    end
    local isWindingUp = state.windupActive and state.windupStress > RMS_Config.DRIVETRAIN.WINDUP_4WD_WARNING_THRESHOLD
    return isWindingUp and RMS_Breakdowns.COLORS.WARNING or RMS_Hud.COLOR_GAME_GREEN
end

---Returns the diff lock lamp's colour
-- @param table state drivetrain state
-- @param float time time of the blink (ms)
-- @return table color rgba color
function RMS_Hud.getDiffLockColor(state, time)
    local colors = RMS_Breakdowns.COLORS
    if not state.diffLockEngaged then
        return colors.DEFAULT
    end
    local isBlinkOn = math.floor(time / 250) % 2 == 0
    return (state.windupStress > RMS_Config.DRIVETRAIN.WINDUP_CRITICAL_THRESHOLD and isBlinkOn) and colors.CRITICAL or colors.WARNING
end

---Returns the text of the drive mode
-- @param table state drivetrain state
-- @return string text drive mode
function RMS_Hud.getDriveModeText(state)
    if state.driveMode == RMS_Drivetrain.MODE.AUTO then
        return g_i18n:getText("rms_hud_drive_auto")
    elseif state.driveMode == RMS_Drivetrain.MODE.FOUR_WD then
        return g_i18n:getText("rms_hud_drive_4wd")
    end
    return g_i18n:getText("rms_hud_drive_2wd")
end

---Returns the colour of every lamp this frame
-- @param table spec RMS specialization of the vehicle
-- @param table lampColors colors by lamp
-- @param table isRoutine routine lamps by lamp
-- @param table shown lamps shown by lamp
-- @param boolean isMotorOn true while the motor runs
-- @return table resolved colors shown by lamp
function RMS_Hud:resolveLampColors(spec, lampColors, isRoutine, shown, isMotorOn)
    local colors = RMS_Breakdowns.COLORS
    local resolved = self.resolvedLamps
    for _, id in ipairs(RMS_Hud.INDICATOR_ORDER) do
        local color = lampColors[id]
        local severity = 0
        if shown[id] and not isRoutine[id] then
            if color == colors.CRITICAL then
                severity = 2
            elseif color == colors.WARNING then
                severity = 1
            end
        end
        local light = spec.activeIndicators[id]
        local blinksWhileLit = light ~= nil and light.blinkWhileActive
        local canBlink = isMotorOn or blinksWhileLit
        self:updateLampAlert(id, severity, isMotorOn, canBlink)
        color = RMS_Hud.getLitLampColor(id, color, spec)
        if not isRoutine[id] then
            local isContinuous = blinksWhileLit
                or id == "dpf" and color == colors.WARNING and RMS_Hud.getIsParticulateFilterCalling(spec)
            color = self:getLampBlinkColor(id, color, isContinuous, canBlink)
        end
        resolved[id] = color
    end
    return resolved
end

local FIGURE_COLOR = { 1, 1, 1, 1 }
local GLASS_COVERAGE_STEPS = 63

---Returns the box of a dashboard picture
-- @param string sliceId picture
-- @return table box box (reference pixels)
local function getPieceBox(sliceId)
    return RMS_HudLayout.slices[sliceId].box
end

---Returns a dashboard picture's rectangle on screen
-- @param table box box of the picture (reference pixels)
-- @param float x x of the middle (screen)
-- @param float y y of the middle (screen)
-- @param boolean? isSnapped true to put it on the pixel grid
-- @param boolean? isPlaced whole-pixel size about its given middle
-- @return float left screen space
-- @return float bottom bottom (screen)
-- @return float width width (screen)
-- @return float height height (screen)
function RMS_Hud:getDashboardPieceBounds(box, x, y, isSnapped, isPlaced)
    local left, bottom = x + self:scalePixelToScreenWidth(box[1]), y + self:scalePixelToScreenHeight(box[2])
    local width, height = self:scalePixelToScreenWidth(box[3] - box[1]), self:scalePixelToScreenHeight(box[4] - box[2])
    if isSnapped then
        local middleX, middleY = left + width * 0.5, bottom + height * 0.5
        width = math.max(math.floor(width * g_screenWidth + 0.5), 1) / g_screenWidth
        height = math.max(math.floor(height * g_screenHeight + 0.5), 1) / g_screenHeight
        left, bottom = middleX - width * 0.5, middleY - height * 0.5
        if not isPlaced then
            left, bottom = snapScreenX(left), snapScreenY(bottom)
        end
    end
    return left, bottom, width, height
end

---Draws a dashboard picture in a rectangle, returning it
-- @param table overlay overlay
-- @param string sliceId picture
-- @param table color rgba color
-- @param float left left (screen)
-- @param float bottom bottom (screen)
-- @param float width width (screen)
-- @param float height height (screen)
-- @return float left left (screen)
-- @return float bottom bottom (screen)
-- @return float width width (screen)
-- @return float height height (screen)
local function drawDashboardPieceAt(overlay, sliceId, color, left, bottom, width, height)
    overlay:setSliceId(sliceId)
    overlay:setPosition(left, bottom)
    overlay:setDimension(width, height)
    overlay:setColor(color[1], color[2], color[3], color[4])
    overlay:render()
    return left, bottom, width, height
end

---Draws a dashboard picture about a middle, returning its rectangle
-- @param table overlay overlay
-- @param string sliceId picture
-- @param table box box of the picture (reference pixels)
-- @param float x x of the middle (screen)
-- @param float y y of the middle (screen)
-- @param table color rgba color
-- @param boolean? isSnapped true to put it on the pixel grid
-- @param boolean? isPlaced whole-pixel size about its given middle
-- @return float left left (screen)
-- @return float bottom bottom (screen)
-- @return float width width (screen)
-- @return float height height (screen)
function RMS_Hud:drawDashboardPiece(overlay, sliceId, box, x, y, color, isSnapped, isPlaced)
    return drawDashboardPieceAt(overlay, sliceId, color, self:getDashboardPieceBounds(box, x, y, isSnapped, isPlaced))
end

---Draws a halo centred on a point
-- @param table overlay glow overlay
-- @param float x centre x (screen)
-- @param float y centre y (screen)
-- @param float width width (screen)
-- @param float height height (screen)
-- @param table color rgba color
-- @param float alpha alpha
local function drawHalo(overlay, x, y, width, height, color, alpha)
    overlay:setDimension(width, height)
    overlay:setPosition(x - width * 0.5, y - height * 0.5)
    overlay:setColor(color[1], color[2], color[3], alpha)
    overlay:render()
end

---Returns the centre of the ink of a lamp in its rectangle
-- @param string sliceId picture of the lamp
-- @param float left left (screen)
-- @param float bottom bottom (screen)
-- @param float width width (screen)
-- @param float height height (screen)
-- @return float x centre x (screen)
-- @return float y centre y (screen)
local function getLampCentre(sliceId, left, bottom, width, height)
    local centre = RMS_HudLayout.lampCentres[sliceId]
    return left + width * centre[1], bottom + height * centre[2]
end

---Draws the halo of a lit dial lamp
-- @param table icon overlay of the lamp
-- @param string slice picture of the lamp
-- @param table color rgba color
function RMS_Hud:drawDialLampHalo(icon, slice, color)
    local x, y = icon:getPosition()
    x, y = getLampCentre("rms_Hud." .. slice, x, y, icon.width, icon.height)
    local glow = self.lampGlow
    drawHalo(glow, x, y, glow.width, glow.height, color, RMS_Hud.GLOW.ALPHA)
end

---Adds the points of an arc after its first
-- @param table points x and y in turn
-- @param float centreX centre x (reference pixels)
-- @param float centreY centre y (reference pixels)
-- @param float radius radius (reference pixels)
-- @param float from start angle (rad)
-- @param float to end angle (rad)
-- @param float pxPerRef screen pixels of a reference px
local function addArc(points, centreX, centreY, radius, from, to, pxPerRef)
    local step = 2 * math.acos(math.max(1 - RMS_Hud.DASHBOARD.OUTLINE.SAGITTA / (radius * pxPerRef), 0))
    local count = math.max(math.ceil(math.abs(to - from) / step), 1)
    for i = 1, count do
        local angle = from + (to - from) * i / count
        points[#points + 1] = centreX + radius * math.cos(angle)
        points[#points + 1] = centreY + radius * math.sin(angle)
    end
end

---Returns the angle of a point left of the dial
-- @param float x x (reference pixels)
-- @param float y y (reference pixels)
-- @return float angle angle (rad), 0 to 2 pi
local function getLeftAngle(x, y)
    local angle = math.atan2(y, x)
    return angle < 0 and angle + 2 * math.pi or angle
end

---Returns an angle within a turn after another
-- @param float angle angle (rad)
-- @param float from angle it follows (rad)
-- @return float angle angle (rad)
local function getAngleAfter(angle, from)
    return from + (angle - from) % (2 * math.pi)
end

---Returns the corner centres round a block's notch
-- @param table notch its circle's centre and radius, reference px with y up
-- @param float inner inner radius of the block (reference pixels)
-- @param float round radius of the corners (reference pixels)
-- @param float bottom foot of the block (reference pixels)
-- @return float footX x of the foot corner
-- @return float footY y of the foot corner
-- @return float curveX x of the corner on the notch
-- @return float curveY y of the corner on the notch
local function getNotchCorners(notch, inner, round, bottom)
    local x, y, reach = notch[1], notch[2], notch[3] + round
    local footY = bottom + round
    local distance = math.sqrt(x * x + y * y)
    local along = ((inner + round) ^ 2 - reach * reach + distance * distance) / (2 * distance)
    local across = math.sqrt((inner + round) ^ 2 - along * along)
    local ux, uy = x / distance, y / distance
    local curveX, curveY = ux * along + uy * across, uy * along - ux * across
    if uy * along + ux * across > curveY then
        curveX, curveY = ux * along - uy * across, uy * along + ux * across
    end
    return x - math.sqrt(reach * reach - (footY - y) ^ 2), footY, curveX, curveY
end

---Returns a block's outline about the dial centre
-- @param table block top, bottom, outer radius and notch, reference px
-- @param float pxPerRef screen pixels of a reference px
-- @return table points x and y in turn
local function getBlockLoop(block, pxPerRef)
    local inner, round, outer = RMS_HudLayout.blocks.inner, RMS_HudLayout.blocks.round, block.outer
    local top, bottom = block.top, block.bottom
    ---Returns the point of a row at a distance from the dial centre
    -- @param float y row (reference pixels)
    -- @param float distance distance from the centre (reference pixels)
    -- @return float x x (reference pixels)
    -- @return float y y (reference pixels)
    local function corner(y, distance)
        return -math.sqrt(distance * distance - y * y), y
    end
    local topOuterX, topOuterY = corner(top - round, outer - round)
    local bottomOuterX, bottomOuterY = corner(bottom + round, outer - round)
    local bottomInnerX, bottomInnerY = corner(bottom + round, inner + round)
    local topInnerX, topInnerY = corner(top - round, inner + round)
    local topOuter, bottomOuter = getLeftAngle(topOuterX, topOuterY), getLeftAngle(bottomOuterX, bottomOuterY)
    local bottomInner, topInner = getLeftAngle(bottomInnerX, bottomInnerY), getLeftAngle(topInnerX, topInnerY)
    local points = { topInnerX, top, topOuterX, top }
    addArc(points, topOuterX, topOuterY, round, math.pi * 0.5, topOuter, pxPerRef)
    addArc(points, 0, 0, outer, topOuter, bottomOuter, pxPerRef)
    addArc(points, bottomOuterX, bottomOuterY, round, bottomOuter, math.pi * 1.5, pxPerRef)
    local notch = block.notch
    if notch == nil then
        points[#points + 1], points[#points + 2] = bottomInnerX, bottom
        addArc(points, bottomInnerX, bottomInnerY, round, math.pi * 1.5, bottomInner + math.pi, pxPerRef)
    else
        local footX, footY, curveX, curveY = getNotchCorners(notch, inner, round, bottom)
        points[#points + 1], points[#points + 2] = footX, bottom
        addArc(points, footX, footY, round, math.pi * 1.5, getAngleAfter(math.atan2(notch[2] - footY, notch[1] - footX), math.pi * 1.5), pxPerRef)
        -- clockwise round the notch, the block outside its circle
        local fromFoot = math.atan2(footY - notch[2], footX - notch[1])
        local toCurve = math.atan2(curveY - notch[2], curveX - notch[1])
        addArc(points, notch[1], notch[2], notch[3], fromFoot, fromFoot - (fromFoot - toCurve) % (2 * math.pi), pxPerRef)
        local fromNotch = math.atan2(notch[2] - curveY, notch[1] - curveX)
        addArc(points, curveX, curveY, round, fromNotch, getAngleAfter(math.atan2(-curveY, -curveX), fromNotch), pxPerRef)
        bottomInner = getLeftAngle(curveX, curveY)
    end
    addArc(points, 0, 0, inner, bottomInner, topInner, pxPerRef)
    addArc(points, topInnerX, topInnerY, round, topInner + math.pi, math.pi * 2.5, pxPerRef)
    points[#points], points[#points - 1] = nil, nil
    return points
end

---Returns the leftmost point of a widened block on a row
-- @param table block its top, bottom and outer radius, reference px with y up
-- @param float margin reference px
-- @param float y the row, reference px with y up
-- @return float x reference px or math.huge off its rows
local function getBlockLeft(block, margin, y)
    local round = RMS_HudLayout.blocks.round
    local radius, centre = round + margin, block.outer - round
    local topY, bottomY = block.top - round, block.bottom + round
    if y > topY + radius or y < bottomY - radius then
        return math.huge
    end
    -- arc and corner meet on the line from the dial centre through the corner's centre
    local reach = (centre + radius) / centre
    local cornerY
    if y >= topY * reach then
        cornerY = topY
    elseif y <= bottomY * reach then
        cornerY = bottomY
    else
        return -math.sqrt((centre + radius) ^ 2 - y * y)
    end
    return -math.sqrt(centre * centre - cornerY * cornerY) - math.sqrt(radius * radius - (y - cornerY) ^ 2)
end

---Returns the left side of a block widened by the panel's gutter
-- @param table block its top, bottom and outer radius, reference px with y up
-- @param float pxPerRef screen pixels of a reference px
-- @return table points x and y in turn, top to foot, reference px with y up
local function getBlockSide(block, pxPerRef)
    local round, gutter = RMS_HudLayout.blocks.round, RMS_HudLayout.blocks.gutter
    local radius, centre = round + gutter, block.outer - round
    local topY, bottomY = block.top - round, block.bottom + round
    local topX, bottomX = -math.sqrt(centre * centre - topY * topY), -math.sqrt(centre * centre - bottomY * bottomY)
    local topAngle, bottomAngle = getLeftAngle(topX, topY), getLeftAngle(bottomX, bottomY)
    local points = { 0, block.top + gutter, topX, block.top + gutter }
    addArc(points, topX, topY, radius, math.pi * 0.5, topAngle, pxPerRef)
    addArc(points, 0, 0, block.outer + gutter, topAngle, bottomAngle, pxPerRef)
    addArc(points, bottomX, bottomY, radius, bottomAngle, math.pi * 1.5, pxPerRef)
    points[#points + 1], points[#points + 2] = 0, block.bottom - gutter
    return points
end

---Returns the leftmost point of a widened run on a row
-- @param table points x and y in turn
-- @param integer first first point of the run
-- @param integer last last point of the run
-- @param float y row (reference pixels)
-- @param float radius widening (reference pixels)
-- @return float x reference px or math.huge off the run
local function getRunLeft(points, first, last, y, radius)
    local left = math.huge
    for i = first, last do
        local x1, y1 = points[2 * i - 1], points[2 * i]
        if (y1 - y) ^ 2 <= radius * radius then
            left = math.min(left, x1 - math.sqrt(radius * radius - (y1 - y) ^ 2))
        end
        if i < last then
            local x2, y2 = points[2 * i + 1], points[2 * i + 2]
            if math.min(y1, y2) - radius <= y and math.max(y1, y2) + radius >= y then
                -- the side moved out by the radius, off the region
                local dx, dy = x2 - x1, y2 - y1
                local length = math.sqrt(dx * dx + dy * dy)
                local outX, outY = dy / length * radius, -dx / length * radius
                local fromY, toY = y1 + outY, y2 + outY
                if fromY ~= toY and (fromY - y) * (toY - y) <= 0 then
                    left = math.min(left, x1 + outX + (y - fromY) / (toY - fromY) * dx)
                end
            end
        end
    end
    return left
end

---Returns the nearest point of a polyline
-- @param table points x and y in turn
-- @param float x x (reference pixels)
-- @param float y y (reference pixels)
-- @param float height rows looked at above and below (reference pixels)
-- @return integer index index of the side it lies on
-- @return float x x of the point
-- @return float y y of the point
local function getNearestPoint(points, x, y, height)
    local nearest, index, nearestX, nearestY = math.huge, 1, points[1], points[2]
    for i = 1, #points / 2 - 1 do
        local x1, y1, x2, y2 = points[2 * i - 1], points[2 * i], points[2 * i + 1], points[2 * i + 2]
        if math.min(y1, y2) <= y + height and math.max(y1, y2) >= y - height then
            local dx, dy = x2 - x1, y2 - y1
            local along = math.clamp(((x - x1) * dx + (y - y1) * dy) / (dx * dx + dy * dy), 0, 1)
            local px, py = x1 + along * dx, y1 + along * dy
            local distance = (px - x) ^ 2 + (py - y) ^ 2
            if distance < nearest then
                nearest, index, nearestX, nearestY = distance, i, px, py
            end
        end
    end
    return index, nearestX, nearestY
end

---Returns the panel's glass round its dial and blocks
-- @param table panel its dial's glass and its blocks from the top
-- @param float pxPerRef screen pixels of a reference px
-- @return table loop x and y in turn, anticlockwise, reference px with y up
function RMS_Hud.getPanelLoop(panel, pxPerRef)
    local glass, blocks = panel.glass, panel.blocks
    local gutter, join = RMS_HudLayout.blocks.gutter, RMS_HudLayout.blocks.join
    local loop = {}
    for i = 1, #glass.right do
        loop[i] = glass.right[i]
    end
    if #blocks == 0 then
        for i = 1, #glass.left do
            loop[#loop + 1] = glass.left[i]
        end
        return loop
    end

    local dial = glass.left
    -- the top runs on to the first block's corner
    local upper, index = getBlockSide(blocks[1], pxPerRef), 2
    loop[#loop + 1], loop[#loop + 2] = upper[3], upper[4]
    for k, block in ipairs(blocks) do
        local below = blocks[k + 1]
        if below == nil and block.bottom - gutter <= -RMS_HudLayout.sizes.panel then
            break
        end
        -- the join's centre: where both sides widened by its radius meet
        local from = below ~= nil and below.top + gutter + join or block.bottom - gutter
        local to = block.bottom - gutter - join
        local first, last = #dial / 2, 1
        if below == nil then
            for i = 1, #dial / 2 do
                local y = dial[2 * i]
                if y <= from + join and y >= to - join then
                    first, last = math.min(first, i), math.max(last, i)
                end
            end
            first, last = math.max(first - 1, 1), math.min(last + 1, #dial / 2)
        end
        ---Returns the leftmost point of the side below a join, on a row
        -- @param float y row (reference pixels)
        -- @return float x reference px or math.huge off the side
        local function getLowerLeft(y)
            if below ~= nil then
                return getBlockLeft(below, gutter + join, y)
            end
            return getRunLeft(dial, first, last, y, join)
        end
        if getBlockLeft(block, gutter + join, to) < getLowerLeft(to) then
            -- the circle rests on the block's foot
            from = to
        else
            for _ = 1, 32 do
                local middle = (from + to) * 0.5
                if getBlockLeft(block, gutter + join, middle) < getLowerLeft(middle) then
                    from = middle
                else
                    to = middle
                end
            end
        end
        local centreX = math.max(getBlockLeft(block, gutter + join, from), getLowerLeft(to))
        local centreY = from

        local lower = below ~= nil and getBlockSide(below, pxPerRef) or dial
        -- each side touches the join's circle within its radius of the centre's height
        local upperIndex, upperX, upperY = getNearestPoint(upper, centreX, centreY, join + 1)
        local lowerIndex, lowerX, lowerY = getNearestPoint(lower, centreX, centreY, join + 1)
        for i = index + 1, upperIndex do
            loop[#loop + 1], loop[#loop + 2] = upper[2 * i - 1], upper[2 * i]
        end
        loop[#loop + 1], loop[#loop + 2] = upperX, upperY
        local fromAngle = math.atan2(upperY - centreY, upperX - centreX)
        local toAngle = math.atan2(lowerY - centreY, lowerX - centreX)
        addArc(loop, centreX, centreY, join, fromAngle, fromAngle - (fromAngle - toAngle) % (2 * math.pi), pxPerRef)
        upper, index = lower, lowerIndex
    end
    -- down the dial's glass to the foot, or the last block's corner on it
    local last = upper == dial and #dial / 2 or #upper / 2 - 1
    for i = index + 1, last do
        loop[#loop + 1], loop[#loop + 2] = upper[2 * i - 1], upper[2 * i]
    end
    return loop
end

---Tells whether a joint of two strokes is clear
-- @param float ax x before the joint (screen pixels)
-- @param float ay y before the joint (screen pixels)
-- @param float jx x of the joint (screen pixels)
-- @param float jy y of the joint (screen pixels)
-- @param float bx x after the joint (screen pixels)
-- @param float by y after the joint (screen pixels)
-- @return boolean isClear true when clear
local function isJointClear(ax, ay, jx, jy, bx, by)
    local ux, uy, vx, vy = jx - ax, jy - ay, bx - jx, by - jy
    local lengthA, lengthB = math.sqrt(ux * ux + uy * uy), math.sqrt(vx * vx + vy * vy)
    if lengthA == 0 or lengthB == 0 then
        return true
    end
    ux, uy, vx, vy = ux / lengthA, uy / lengthA, vx / lengthB, vy / lengthB
    for row = math.floor(jy - 2), math.floor(jy + 2) do
        for column = math.floor(jx - 2), math.floor(jx + 2) do
            local qx, qy = column + 0.5 - jx, row + 0.5 - jy
            local alongA, acrossA = qx * ux + qy * uy, math.abs(ux * qy - uy * qx)
            local alongB, acrossB = qx * vx + qy * vy, math.abs(vx * qy - vy * qx)
            local inA = alongA < 0 and alongA >= -lengthA and acrossA < 1.5
            local inB = alongB >= 0 and alongB < lengthB and acrossB < 1.5
            if inA and inB and acrossA < 1 and acrossB < 1 then
                return false
            end
            if not inA and not inB and alongA >= 0 and alongB < 0 and math.min(acrossA, acrossB) < 1 then
                return false
            end
        end
    end
    return true
end

---Tells whether the joint at a point of a loop is clear
-- @param table xs x of each point (screen pixels)
-- @param table ys y of each point (screen pixels)
-- @param integer i point
-- @param integer count number of points
-- @return boolean isClear true when clear
local function isJointClearAt(xs, ys, i, count)
    local p, q = (i - 2) % count + 1, i % count + 1
    return isJointClear(xs[p], ys[p], xs[i], ys[i], xs[q], ys[q])
end

---Tells whether a loop's joint and the slid ones are clear
-- @param table xs x of each point (screen pixels)
-- @param table ys y of each point (screen pixels)
-- @param integer index point
-- @param integer count number of points
-- @return boolean isClear true when clear
local function isLoopClearAt(xs, ys, index, count)
    return isJointClearAt(xs, ys, index, count) and (index == 1 or isJointClearAt(xs, ys, index - 1, count))
        and (index < count or isJointClearAt(xs, ys, 1, count))
end

---Returns the strokes of a 1 px outline round loops
-- @param table loops anticlockwise loops of x and y in turn, reference px with y up
-- @param float centreX dial centre x (screen)
-- @param float centreY dial centre y (screen)
-- @param float toScreenX screen width of a reference px
-- @param float toScreenY screen height of a reference px
-- @return table strokes their start, length and angle, screen space
local function getOutlineStrokes(loops, centreX, centreY, toScreenX, toScreenY)
    local outline, width, height = RMS_Hud.DASHBOARD.OUTLINE, g_screenWidth, g_screenHeight
    local strokes = {}
    for _, loop in ipairs(loops) do
        local xs, ys, insideX, insideY = {}, {}, {}, {}
        for i = 1, #loop / 2 do
            local x, y = (centreX + loop[2 * i - 1] * toScreenX) * width, (centreY + loop[2 * i] * toScreenY) * height
            local last = #xs
            if last == 0 or math.sqrt((x - xs[last]) ^ 2 + (y - ys[last]) ^ 2) >= outline.MIN_STROKE then
                xs[last + 1], ys[last + 1] = x, y
            end
        end
        if math.sqrt((xs[#xs] - xs[1]) ^ 2 + (ys[#ys] - ys[1]) ^ 2) < outline.MIN_STROKE then
            xs[#xs], ys[#ys] = nil, nil
        end
        local count = #xs
        for i = 1, count do
            local p, q = (i - 2) % count + 1, i % count + 1
            local tx, ty = xs[q] - xs[p], ys[q] - ys[p]
            local length = math.sqrt(tx * tx + ty * ty)
            insideX[i], insideY[i] = xs[i] - ty / length * 0.5, ys[i] + tx / length * 0.5
        end

        local shiftX, shiftY, runX, runY = {}, {}, {}, {}
        for i = 1, count do
            shiftX[i], shiftY[i] = 0, 0
        end
        for i = 1, count do
            local j = i % count + 1
            local dx, dy = insideX[j] - insideX[i], insideY[j] - insideY[i]
            if math.abs(dy) < 0.05 and math.abs(dx) >= outline.STRAIGHT then
                local y = math.floor((insideY[i] + insideY[j]) * 0.5) + 0.5
                shiftY[i], shiftY[j] = y - insideY[i], y - insideY[j]
                runX[i], runY[i], runX[j], runY[j] = dx, 0, dx, 0
            elseif math.abs(dx) < 0.05 and math.abs(dy) >= outline.STRAIGHT then
                local x = math.floor((insideX[i] + insideX[j]) * 0.5) + 0.5
                shiftX[i], shiftX[j] = x - insideX[i], x - insideX[j]
                runX[i], runY[i], runX[j], runY[j] = 0, dy, 0, dy
            end
        end
        for i = 1, count do
            if runX[i] ~= nil then
                for direction = -1, 1, 2 do
                    local k, along = i, 0
                    while true do
                        local following = (k - 1 + direction) % count + 1
                        along = along + math.sqrt((insideX[following] - insideX[k]) ^ 2 + (insideY[following] - insideY[k]) ^ 2)
                        if runX[following] ~= nil or along >= outline.TAPER then
                            break
                        end
                        local fade = 1 - along / outline.TAPER
                        if math.abs(shiftX[i] * fade) > math.abs(shiftX[following]) then
                            shiftX[following] = shiftX[i] * fade
                        end
                        if math.abs(shiftY[i] * fade) > math.abs(shiftY[following]) then
                            shiftY[following] = shiftY[i] * fade
                        end
                        k = following
                    end
                end
            end
        end
        local px, py = {}, {}
        for i = 1, count do
            px[i], py[i] = insideX[i] + shiftX[i], insideY[i] + shiftY[i]
        end

        for i = 1, count do
            if not isLoopClearAt(px, py, i, count) then
                local p, q = (i - 2) % count + 1, i % count + 1
                local tx, ty = runX[i] or (px[q] - px[p]), runY[i] or (py[q] - py[p])
                local length = math.sqrt(tx * tx + ty * ty)
                tx, ty = tx / length * outline.NUDGE, ty / length * outline.NUDGE
                local x, y = px[i], py[i]
                for step = 1, outline.NUDGE_STEPS do
                    px[i], py[i] = x + tx * step, y + ty * step
                    if isLoopClearAt(px, py, i, count) then
                        break
                    end
                    px[i], py[i] = x - tx * step, y - ty * step
                    if isLoopClearAt(px, py, i, count) then
                        break
                    end
                    px[i], py[i] = x, y
                end
            end
        end

        for i = 1, count do
            local j = i % count + 1
            local dx, dy = px[j] - px[i], py[j] - py[i]
            strokes[#strokes + 1] = { x = px[i] / width, y = (py[i] - 1.5) / height,
                length = math.sqrt(dx * dx + dy * dy) / width, angle = math.atan2(dy, dx) }
        end
    end
    return strokes
end

---Adds an interval's coverage to a subpixel row
-- @param table events coverage changes by column
-- @param float edge edge (screen pixels)
-- @param float weight weight of the change
local function addCoverage(events, edge, weight)
    local column = math.floor(edge)
    local fraction = edge - column
    events[column] = (events[column] or 0) + (1 - fraction) * weight
    events[column + 1] = (events[column + 1] or 0) + fraction * weight
end

---Rasterizes even-odd loops into pixel spans
-- @param table loops loops of x and y in turn, reference px with y up
-- @param float centreX dial centre x (screen)
-- @param float centreY dial centre y (screen)
-- @param float toScreenX screen width of a reference px
-- @param float toScreenY screen height of a reference px
-- @param integer cut column a span always ends at
-- @return table spans pixel spans
local function getGlassSpans(loops, centreX, centreY, toScreenX, toScreenY, cut)
    local width, height = g_screenWidth, g_screenHeight
    local subrows, crossings, coverage = 4, {}, {}
    for _, loop in ipairs(loops) do
        local px, py = {}, {}
        for i = 1, #loop, 2 do
            px[#px + 1] = (centreX + loop[i] * toScreenX) * width
            py[#py + 1] = (centreY + loop[i + 1] * toScreenY) * height
        end
        for i, low in ipairs(py) do
            local j = i % #py + 1
            local high = py[j]
            if low ~= high then
                local from = math.max(0, math.ceil(math.min(low, high) * subrows - 0.5))
                local to = math.min(height * subrows, math.ceil(math.max(low, high) * subrows - 0.5)) - 1
                local slope = (px[j] - px[i]) / (high - low)
                for sample = from, to do
                    local xs = crossings[sample]
                    if xs == nil then
                        xs = {}
                        crossings[sample] = xs
                    end
                    xs[#xs + 1] = px[i] + ((sample + 0.5) / subrows - low) * slope
                end
            end
        end
    end
    for sample, xs in pairs(crossings) do
        table.sort(xs)
        local row = math.floor(sample / subrows)
        local events = coverage[row]
        if events == nil then
            events = {}
            coverage[row] = events
        end
        for i = 1, #xs - 1, 2 do
            local left, right = math.clamp(xs[i], 0, width), math.clamp(xs[i + 1], 0, width)
            if left < right then
                addCoverage(events, left, 1 / subrows)
                addCoverage(events, right, -1 / subrows)
            end
        end
    end
    local spans, previous = {}, {}
    for row = 0, height - 1 do
        local events = coverage[row]
        local current = {}
        if events ~= nil then
            local columns = {}
            for column, change in pairs(events) do
                if math.abs(change) > 1e-8 then
                    columns[#columns + 1] = column
                end
            end
            if math.abs(events[cut] or 0) <= 1e-8 then
                columns[#columns + 1] = cut
            end
            table.sort(columns)
            local alpha = 0
            for i = 1, #columns - 1 do
                local left, right = columns[i], columns[i + 1]
                alpha = alpha + (events[left] or 0)
                local level = math.floor(math.clamp(alpha, 0, 1) * GLASS_COVERAGE_STEPS + 0.5)
                if level > 0 then
                    local key = (left * (width + 1) + right) * (GLASS_COVERAGE_STEPS + 1) + level
                    local span = previous[key]
                    if span == nil then
                        span = { left = left / width, bottom = row / height, width = (right - left) / width,
                            rows = 0, level = level }
                        spans[#spans + 1] = span
                    end
                    span.rows = span.rows + 1
                    current[key] = span
                end
            end
        end
        previous = current
    end
    return spans
end

---Returns a glass's drawing on this screen
-- @param float centreX dial centre x (screen)
-- @param float centreY dial centre y (screen)
-- @param table part block or panel of the glass
-- @param integer slot cache slot of the glass
-- @return table drawing fills and strokes of the glass
function RMS_Hud:getGlassDrawing(centreX, centreY, part, slot)
    local built = self.glasses[slot]
    if built == nil or built.x ~= centreX or built.y ~= centreY or built.part ~= part
        or built.screenWidth ~= g_screenWidth or built.screenHeight ~= g_screenHeight then
        local toScreenX, toScreenY = self:scalePixelToScreenWidth(1), self:scalePixelToScreenHeight(1)
        built = { x = centreX, y = centreY, part = part, screenWidth = g_screenWidth, screenHeight = g_screenHeight }
        if part.glass == nil then
            local loops = part.outline or { getBlockLoop(part, toScreenY * g_screenHeight) }
            built.left, built.bottom, built.width, built.height = self:getDashboardPieceBounds(getPieceBox(part.slice),
                centreX, centreY, false)
            built.strokes = getOutlineStrokes(loops, centreX, centreY, toScreenX, toScreenY)
        else
            local pieces = RMS_HudLayout.pieces
            local left, bottom, width, height = self:getDashboardPieceBounds(getPieceBox(pieces.panelShade), centreX, centreY, false)
            local uvs = g_overlayManager:getSliceInfoById(pieces.panelShade).uvs
            local uScale, vScale = (uvs[5] - uvs[1]) / width, (uvs[4] - uvs[2]) / height
            local cut = math.ceil(left * g_screenWidth)
            local loops = { RMS_Hud.getPanelLoop(part, toScreenY * g_screenHeight) }
            -- spans left of the shading share the panel's tone
            built.tone, built.fills = g_overlayManager:getSliceInfoById(pieces.panelTone).uvs, {}
            for _, span in ipairs(getGlassSpans(loops, centreX, centreY, toScreenX, toScreenY, cut)) do
                span.height = span.rows / g_screenHeight
                local fill = built.fills[span.level]
                if fill == nil then
                    fill = { tone = {}, shade = {} }
                    built.fills[span.level] = fill
                end
                if span.left * g_screenWidth < cut - 0.5 then
                    table.insert(fill.tone, span)
                else
                    local u0, v0 = uvs[1] + (span.left - left) * uScale, uvs[2] + (span.bottom - bottom) * vScale
                    local u1, v1 = u0 + span.width * uScale, v0 + span.height * vScale
                    span.uvs = { u0, v0, u0, v1, u1, v0, u1, v1 }
                    table.insert(fill.shade, span)
                end
            end
        end
        self.glasses[slot] = built
    end
    return built
end

---Draws a glass and returns its outline
-- @param float centreX dial centre x (screen)
-- @param float centreY dial centre y (screen)
-- @param table part block or panel of the glass
-- @param integer slot cache slot of the glass
-- @return table strokes strokes of the outline
function RMS_Hud:drawGlassFill(centreX, centreY, part, slot)
    local built = self:getGlassDrawing(centreX, centreY, part, slot)
    local glass = self.dashboard.glass
    if built.fills == nil then
        drawDashboardPieceAt(glass, part.slice, FIGURE_COLOR, built.left, built.bottom, built.width, built.height)
        return built.strokes
    end
    glass:setSliceId(RMS_HudLayout.pieces.panelShade)
    for level, fill in pairs(built.fills) do
        glass:setColor(1, 1, 1, level / GLASS_COVERAGE_STEPS)
        if #fill.tone > 0 then
            glass:setUVs(built.tone)
            for _, span in ipairs(fill.tone) do
                renderOverlay(glass.overlayId, span.left, span.bottom, span.width, span.height)
            end
        end
        for _, span in ipairs(fill.shade) do
            glass:setUVs(span.uvs)
            renderOverlay(glass.overlayId, span.left, span.bottom, span.width, span.height)
        end
    end
    return built.strokes
end

---Draws the outline strokes of a glass
-- @param table self HUD
-- @param table? strokes strokes of the outline
local function drawGlassOutline(self, strokes)
    if strokes == nil then
        return
    end
    local id, rim = self.dashboard.stroke.overlayId, RMS_Hud.DASHBOARD.RIM
    local height, pivot = 3 / g_screenHeight, 1.5 / g_screenHeight
    setOverlayColor(id, rim[1], rim[2], rim[3], rim[4])
    for _, stroke in ipairs(strokes) do
        setOverlayRotation(id, stroke.angle, 0, pivot)
        renderOverlay(id, stroke.x, stroke.y, stroke.length, height)
    end
end

local ringCorners = {}

---Caches the coverage of a one-pixel corner
-- @param integer index radius in half pixels
-- @return table pixels column, row and coverage of each pixel
local function getRingCorner(index)
    local pixels = ringCorners[index]
    if pixels == nil then
        local radius, samples = index * 0.5, 32
        local centre = radius + 0.5
        local size = math.ceil(centre)
        pixels = {}
        for column = 0, size - 1 do
            for row = 0, size - 1 do
                local covered = 0
                for i = 0, samples - 1 do
                    for j = 0, samples - 1 do
                        local x, y = column + (i + 0.5) / samples, row + (j + 0.5) / samples
                        local distance
                        if x < centre and y < centre then
                            distance = math.abs(math.sqrt((x - centre) ^ 2 + (y - centre) ^ 2) - radius)
                        elseif y < centre then
                            distance = math.abs(y - 0.5)
                        else
                            distance = math.abs(x - 0.5)
                        end
                        if distance <= 0.5 then
                            covered = covered + 1
                        end
                    end
                end
                if covered > 0 then
                    pixels[#pixels + 1] = { column, row, covered / (samples * samples) }
                end
            end
        end
        ringCorners[index] = pixels
    end
    return pixels
end

---Draws a one-pixel rounded outline
-- @param float left left (screen pixels)
-- @param float bottom bottom (screen pixels)
-- @param float right right (screen pixels)
-- @param float top top (screen pixels)
-- @param float radius screen pixels
-- @param table color rgba color
-- @return integer left screen column
-- @return integer bottom screen row
-- @return integer right screen column
-- @return integer top screen row
function RMS_Hud:drawRoundOutline(left, bottom, right, top, radius, color)
    local x0, x1 = math.floor(left + 0.5), math.floor(right - 0.5)
    local y0, y1 = math.floor(bottom + 0.5), math.floor(top - 0.5)
    local index = math.floor((radius - 0.5) * 2 + 0.5)
    local columns, rows = x1 - x0 + 1, y1 - y0 + 1
    index = math.clamp(index, 1, math.max(math.min(columns, rows) - 1, 1))
    while index > 1 and 2 * math.ceil(index * 0.5 + 0.5) > math.min(columns, rows) do
        index = index - 1
    end
    local size = math.ceil(index * 0.5 + 0.5)
    local width, height = g_screenWidth, g_screenHeight
    local r, g, b, opacity = color[1], color[2], color[3], color[4]
    local px, py = 1 / width, 1 / height
    for _, pixel in ipairs(getRingCorner(index)) do
        local xL, xR = (x0 + pixel[1]) / width, (x1 - pixel[1]) / width
        local yB, yT = (y0 + pixel[2]) / height, (y1 - pixel[2]) / height
        local alpha = opacity * pixel[3]
        drawFilledRect(xL, yT, px, py, r, g, b, alpha)
        drawFilledRect(xR, yT, px, py, r, g, b, alpha)
        drawFilledRect(xL, yB, px, py, r, g, b, alpha)
        drawFilledRect(xR, yB, px, py, r, g, b, alpha)
    end
    if columns > 2 * size then
        drawFilledRect((x0 + size) / width, y1 / height, (columns - 2 * size) / width, 1 / height, color[1], color[2], color[3], color[4])
        drawFilledRect((x0 + size) / width, y0 / height, (columns - 2 * size) / width, 1 / height, color[1], color[2], color[3], color[4])
    end
    if rows > 2 * size then
        drawFilledRect(x0 / width, (y0 + size) / height, 1 / width, (rows - 2 * size) / height, color[1], color[2], color[3], color[4])
        drawFilledRect(x1 / width, (y0 + size) / height, 1 / width, (rows - 2 * size) / height, color[1], color[2], color[3], color[4])
    end
    return x0, y0, x1, y1
end

---Draws the outline of a window or a screen
-- @param table body its body's width and height, reference px
-- @param table box its picture's box, reference px
-- @param float left left of the picture (screen)
-- @param float bottom bottom of the picture (screen)
-- @param float width width of the picture (screen)
-- @param float height height of the picture (screen)
-- @return integer left column of the outline, screen pixels
-- @return integer bottom row
-- @return integer right column
-- @return integer top row
function RMS_Hud:drawBodyOutline(body, box, left, bottom, width, height)
    local boxWidth, boxHeight = box[3] - box[1], box[4] - box[2]
    local insetX = (boxWidth - body.width) * 0.5 / boxWidth * width
    local insetY = (boxHeight - body.height) * 0.5 / boxHeight * height
    return self:drawRoundOutline((left + insetX) * g_screenWidth, (bottom + insetY) * g_screenHeight, (left + width - insetX) * g_screenWidth,
        (bottom + height - insetY) * g_screenHeight, RMS_HudLayout.bodies.corner * width * g_screenWidth / boxWidth,
        RMS_Hud.DASHBOARD.RIM)
end

---Queues a dashboard lamp
-- @param table lamps lamps queued
-- @param string picto picture
-- @param float x x of the middle (screen)
-- @param float y y of the middle (screen)
-- @param table color rgba color
-- @param boolean? isPlaced its middle kept off the pixel grid
-- @param boolean? hasGlow whether a white telltale lights up
local function addLamp(lamps, picto, x, y, color, isPlaced, hasGlow)
    local count = lamps.count + 1
    local lamp = lamps[count]
    if lamp == nil then
        lamp = {}
        lamps[count] = lamp
    end
    lamp.sliceId, lamp.x, lamp.y, lamp.color = RMS_HudLayout.pieces.pictos[picto], x, y, color
    lamp.isPlaced, lamp.hasGlow = isPlaced, hasGlow
    lamps.count = count
end

---Draws a dashboard glow
-- @param float x centre x (screen)
-- @param float y centre y (screen)
-- @param table color rgba color
-- @param float? inkWidth width of the ink it lights (screen)
function RMS_Hud:drawDashboardHalo(x, y, color, inkWidth)
    local glow = RMS_Hud.DASHBOARD.LAMP_GLOW
    local width = self:scalePixelToScreenWidth(glow.SIZE)
    if inkWidth ~= nil then
        width = math.max(width, inkWidth + width * 0.5)
    end
    local overlay = self.dashboard.glow
    overlay:setSliceId(RMS_HudLayout.pieces.glow)
    local alpha = color == RMS_Hud.COLOR_GAME_GREEN and glow.GREEN_ALPHA or glow.ALPHA
    drawHalo(overlay, x, y, width, self:scalePixelToScreenHeight(glow.SIZE), color, alpha)
end

---Draws the queued lamps
-- @param table lamps lamps queued
function RMS_Hud:drawDashboardLamps(lamps)
    local colors = RMS_Breakdowns.COLORS
    for index = 1, lamps.count do
        local lamp = lamps[index]
        lamp.left, lamp.bottom, lamp.width, lamp.height = self:getDashboardPieceBounds(getPieceBox(lamp.sliceId), lamp.x, lamp.y, true, lamp.isPlaced)
        if lamp.color ~= colors.DEFAULT and (lamp.color ~= FIGURE_COLOR or lamp.hasGlow) then
            local x, y = getLampCentre(lamp.sliceId, lamp.left, lamp.bottom, lamp.width, lamp.height)
            self:drawDashboardHalo(x, y, lamp.color)
        end
    end
    for index = 1, lamps.count do
        local lamp = lamps[index]
        drawDashboardPieceAt(self.dashboard.piece, lamp.sliceId, lamp.color, lamp.left, lamp.bottom, lamp.width, lamp.height)
    end
end

---Draws a figure and its unit
-- @param float x left (screen)
-- @param float middleY y of the middle (screen)
-- @param string value figure
-- @param string unit unit
-- @param table color rgba color
-- @param float unitGap gap before the unit (reference pixels)
-- @param boolean? hasGlow true to light it up
function RMS_Hud:drawFigure(x, middleY, value, unit, color, unitGap, hasGlow)
    local sizes = RMS_HudLayout.sizes
    local valueSize = self:scalePixelToScreenHeight(sizes.value)
    local baselineY = snapScreenY(middleY - valueSize * RMS_Hud.FIGURES_MIDDLE)
    setTextStyle(RenderText.ALIGN_LEFT, RenderText.VERTICAL_ALIGN_BASELINE, true)
    local left = snapScreenX(x)
    if hasGlow then
        local width = getTextWidth(valueSize, value)
        local ink = RMS_HudLayout.driveTextCentres[value]
        local centreX = left + width * (ink and ink[1] or 0.5)
        local centreY = baselineY + valueSize * (ink and ink[2] or RMS_Hud.FIGURES_MIDDLE)
        self:drawDashboardHalo(centreX, centreY, color, width)
    end
    setTextColor(color[1], color[2], color[3], 1)
    renderText(left, baselineY, valueSize, value)
    if unit ~= "" then
        local unitColor = color == FIGURE_COLOR and RMS_Hud.DASHBOARD.LABEL or color
        local unitX = x + getTextWidth(valueSize, value) + self:scalePixelToScreenWidth(unitGap)
        setTextBold(false)
        setTextColor(unitColor[1], unitColor[2], unitColor[3], 1)
        renderText(snapScreenX(unitX), baselineY, self:scalePixelToScreenHeight(sizes.unit), unit)
    end
    setTextBold(false)
end

---Returns a figure's width with its unit
-- @param string value figure
-- @param string unit unit
-- @return float width width (screen)
function RMS_Hud:getFigureRoom(value, unit)
    local sizes = RMS_HudLayout.sizes
    setTextBold(true)
    local width = getTextWidth(self:scalePixelToScreenHeight(sizes.value), value)
    setTextBold(false)
    if unit ~= "" then
        width = width + self:scalePixelToScreenWidth(RMS_Hud.DASHBOARD.UNIT_GAP) + getTextWidth(self:scalePixelToScreenHeight(sizes.unit), unit)
    end
    return width
end

---Draws a symbol and its figure
-- @param float anchorX x of the anchor (screen)
-- @param float y y of the middle (screen)
-- @param string picto picture of the symbol
-- @param table color rgba color of the symbol
-- @param string value figure
-- @param string unit unit
-- @param table figureColor rgba color of the figure
-- @param boolean isShown true to show the figure
-- @param table lamps lamps queued
-- @param boolean? isLeftAligned true to align it left of the anchor
-- @param boolean? hasGlow true to light it up
function RMS_Hud:drawSymbolFigure(anchorX, y, picto, color, value, unit, figureColor, isShown, lamps, isLeftAligned, hasGlow)
    local sizes, ink = RMS_HudLayout.sizes, RMS_HudLayout.inks[picto]
    local inkWidth = self:scalePixelToScreenWidth(ink[2] - ink[1] + sizes.textGap)
    local left = anchorX
    local pictoOffset = -ink[1]
    if isLeftAligned then
        pictoOffset = pictoOffset + RMS_Hud.DASHBOARD.READING_PICTO_OFFSET
    else
        left = left - (inkWidth + self:getFigureRoom(value, unit)) * 0.5
    end
    addLamp(lamps, picto, left + self:scalePixelToScreenWidth(pictoOffset), y, color, nil, hasGlow)
    if isShown then
        local hasModeGlow = picto == "frontWheelDrive" and color ~= RMS_Breakdowns.COLORS.DEFAULT and color ~= FIGURE_COLOR
        self:drawFigure(left + inkWidth, y, value, unit, figureColor, RMS_Hud.DASHBOARD.UNIT_GAP, hasModeGlow)
    end
end


---Draws the rules between the readings
-- @param float posX x of the panel (screen)
-- @param float posY y of the panel (screen)
-- @param table? hairlines rules of the layout (reference pixels)
function RMS_Hud:drawReadingRules(posX, posY, hairlines)
    local width = self:scalePixelToScreenWidth(RMS_HudLayout.sizes.readingRule)
    for _, rule in ipairs(hairlines or {}) do
        drawRule(posX + self:scalePixelToScreenWidth(rule[1]), posY + self:scalePixelToScreenHeight(rule[2]) - g_pixelSizeY * 0.5,
            width, g_pixelSizeY, RMS_Hud.DASHBOARD.HAIRLINE)
    end
end

---Returns the colour of a figure
-- @param table lampColor rgba color of its lamp
-- @return table color rgba color
local function getFigureColor(lampColor)
    if lampColor == nil or lampColor == RMS_Breakdowns.COLORS.DEFAULT then
        return FIGURE_COLOR
    end
    return lampColor
end

---Returns the vehicle's cached dashboard
-- @param table vehicle vehicle
-- @param table spec RMS specialization of the vehicle
-- @return table dashboard dashboard
function RMS_Hud:getVehicleDashboard(vehicle, spec)
    local isRoad = RMS_Drivetrain.getIsRoadVehicleCategory(vehicle)
    local isMachine = RMS_Drivetrain.getIsMachineCategory(vehicle)
    local hasScreen = RMS_Hud.getHasScreen(vehicle)
    local hasDrive = RMS_Drivetrain.getIsAvailable(vehicle)
    local hasCenterDiff = hasDrive and RMS_Drivetrain.getHasCenterDifferential(vehicle)
    local hasPark = RMS_Drivetrain.getIsParkBrakeManaged(vehicle)
    local hasPto = hasScreen and RMS_Utils.getHasPtoDisplay(vehicle)
    local isFitted = RealisticMechanicalSystems.getIsTelltaleFitted
    local data = self.vehicleDashboard
    if data == nil or data.hasDrive ~= hasDrive or data.hasCenterDiff ~= hasCenterDiff or data.hasPark ~= hasPark
        or data.hasPto ~= hasPto or data.filter ~= spec.hasParticulateFilter then
        local content = RMS_Hud.getDashboardContent(vehicle, isRoad)
        local slots = { { id = spec.isElectricVehicle and "limitedPower" or "preheat", x = -RMS_Hud.ROW.PITCH },
            { id = "warning" }, { id = spec.isElectricVehicle and "tractionBattery" or "oil", x = RMS_Hud.ROW.PITCH } }
        local shown, dialLamps = {}, {}
        for _, slot in ipairs(slots) do
            if isFitted(vehicle, slot.id) then
                local slice = RMS_Hud.getDialLampSlice(slot.id, isRoad)
                local x, y, lift
                if slot.x == nil then
                    local ink, lamp = RMS_Hud.LAMP_INK[slice], RMS_Hud.LAMP
                    local size = lamp.SIZE * (RMS_Hud.LAMP_SCALE[slice] or 1)
                    local inkMiddle = (ink[3] + ink[2] * 0.5 - lamp.CELL * 0.5) * size / lamp.CELL
                    x, y, lift = 0, self.serviceCentreY, -self:scalePixelToScreenHeight(inkMiddle)
                else
                    x, y = self:scalePixelToScreenWidth(slot.x), self.rowCenterY
                    lift = self:scalePixelToScreenHeight(RMS_Hud.getRowLampLift(slice))
                end
                dialLamps[#dialLamps + 1] = { id = slot.id, icon = self.lampIcons[slice], slice = slice, x = x, y = y, lift = lift }
                shown[slot.id] = true
            end
        end
        for _, list in ipairs({ content.windows, content.readings }) do
            for _, id in ipairs(list) do
                shown[id] = true
            end
        end
        shown.coolant = content.pod ~= nil
        shown.brakes = shown.brakes or content.drive ~= nil and content.drive.brakes ~= nil

        local drive = content.drive
        local windows = {}
        if drive ~= nil then
            if drive.diff ~= nil then
                windows[#windows + 1] = { place = drive.diff, picto = "diffLock" }
            end
            if drive.brakes ~= nil then
                windows[#windows + 1] = { place = drive.brakes, picto = "brakes" }
            end
            if drive.park ~= nil then
                windows[#windows + 1] = { place = drive.park, picto = "parkBrake" }
            end
        end
        local step = 0
        if #windows > 1 then
            step = math.floor(self:scalePixelToScreenWidth(windows[1].place[1] - windows[2].place[1]) * g_screenWidth + 1e-6) / g_screenWidth
        end
        content.driveWindows, content.driveWindowStep = windows, step

        data = { isRoad = isRoad, isMachine = isMachine, hasDrive = hasDrive, hasCenterDiff = hasCenterDiff, hasPark = hasPark,
            hasPto = hasPto, filter = spec.hasParticulateFilter, content = content, shown = shown, dialLamps = dialLamps,
            parts = { content.panel, content.dial, content.engine or false, content.driveGlass or false } }
        self.vehicleDashboard = data
    end
    data.content.drivetrain = hasDrive and RMS_Drivetrain.getState(vehicle) or nil
    return data
end

---Draws the dashboard
function RMS_Hud:drawDashboard()
    local vehicle, speedMeter = self.vehicle, g_currentMission.hud.speedMeter
    local spec = vehicle.spec_RealisticMechanicalSystems
    if spec == nil or spec.isExcludedVehicle then
        return
    end

    local colors = RMS_Breakdowns.COLORS
    local motorState = vehicle:getMotorState()
    local isMotorOn = motorState == MotorState.ON
    local dashboard = self:getVehicleDashboard(vehicle, spec)
    local content, isRoadVehicle, isMachine = dashboard.content, dashboard.isRoad, dashboard.isMachine
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
    local lampColors, isRoutine = RMS_Hud.getLampColors(vehicle, motorState, isServiceOverdue, cvtFaultColor,
        self.lampColors, self.routineLamps)

    speedMeter.speedTextSize = self:scalePixelToScreenHeight(43)
    local posX, posY = speedMeter.speedBg:getPosition()
    posX, posY = posX + speedMeter.speedGaugeCenterOffsetX, posY + speedMeter.speedGaugeCenterOffsetY
    local lamp = self:resolveLampColors(spec, lampColors, isRoutine, dashboard.shown, isMotorOn)
    if content.hasParkBrake then
        lamp.parkBrake = RMS_Drivetrain.getState(vehicle).parkBrake and colors.CRITICAL or colors.DEFAULT
    end

    local white = FIGURE_COLOR
    for index, part in ipairs(dashboard.parts) do
        if part then
            local strokes = self:drawGlassFill(posX, posY, part, index)
            if part == content.dial then
                if content.pod ~= nil then
                    self:drawPodBody(posX, posY, content.pod)
                end
                if content.hasScreen then
                    self:drawPodBody(posX, posY, "power")
                end
            end
            drawGlassOutline(self, strokes)
        end
    end

    -- the gauges and the screen are powered from the ignition on
    local isPowered = motorState ~= MotorState.OFF
    local symbol = isPowered and white or colors.DEFAULT
    local lamps = self.dashboardLamps
    lamps.count = 0
    self:drawWaterGauge(posX, posY, spec, isPowered)
    if content.pod ~= nil then
        local picto = RMS_Hud.getDashboardPicto("coolant", spec, isRoadVehicle, isMachine)
        local value, unit = RMS_Hud.getWaterFigure(spec)
        self:drawPod(posX, posY, content.pod, picto, lamp.coolant, value, unit, getFigureColor(lamp.coolant), isPowered, lamps)
    end
    if content.hasScreen then
        local squares, figure, isWarning = self:updatePowerReading(vehicle, isMotorOn)
        self:drawPowerGauge(posX, posY, squares, isWarning)
        self:drawPod(posX, posY, "power", "enginePower", symbol, figure, "%", isWarning and colors.WARNING or white, isPowered, lamps)
    end
    self:drawEngineBlock(posX, posY, content, lamp, vehicle, spec, isRoadVehicle, isMachine, isPowered, lamps)
    self:drawDriveBlock(posX, posY, content, lamp, vehicle, spec, isPowered, lamps)
    self:drawDashboardLamps(lamps)
    self:drawDialLamps(posX, posY, dashboard.dialLamps, lamp)

    self:drawOdometer()
end

---Returns a pod's centre and half size on screen
-- @param float posX x of the panel (screen)
-- @param float posY y of the panel (screen)
-- @param string podKey pod
-- @return float x centre x (screen)
-- @return float y centre y (screen)
-- @return float halfWidth half width (screen)
-- @return float halfHeight half height (screen)
function RMS_Hud:getPodGeometry(posX, posY, podKey)
    local pod = RMS_HudLayout.pods[podKey]
    local x, y = posX + self:scalePixelToScreenWidth(pod.x), posY + self:scalePixelToScreenHeight(pod.y)
    return x, y, self:scalePixelToScreenWidth(pod.width * 0.5), self:scalePixelToScreenHeight(pod.height * 0.5)
end

local ringEnds = {}

---Returns the coverage of a pod ring's left end
-- @param integer rows rows of the pod, even
-- @return table pixels column, row and coverage of each pixel the ring touches
local function getRingEnd(rows)
    local pixels = ringEnds[rows]
    if pixels == nil then
        pixels = {}
        local radius, centre, samples = (rows - 1) * 0.5, rows * 0.5, 32
        for column = 0, rows / 2 - 1 do
            for row = 0, rows - 1 do
                -- only pixels within reach of the line
                if math.abs(math.sqrt((column + 0.5 - centre) ^ 2 + (row + 0.5 - centre) ^ 2) - radius) < 1.25 then
                    local covered = 0
                    for i = 0, samples - 1 do
                        for j = 0, samples - 1 do
                            local x, y = column + (i + 0.5) / samples - centre, row + (j + 0.5) / samples - centre
                            if math.abs(math.sqrt(x * x + y * y) - radius) <= 0.5 then
                                covered = covered + 1
                            end
                        end
                    end
                    if covered > 0 then
                        pixels[#pixels + 1] = { column, row, covered / (samples * samples) }
                    end
                end
            end
        end
        ringEnds[rows] = pixels
    end
    return pixels
end

---Draws a pod
-- @param float posX x of the panel (screen)
-- @param float posY y of the panel (screen)
-- @param string podKey pod
function RMS_Hud:drawPodBody(posX, posY, podKey)
    local x, y, halfWidth, halfHeight = self:getPodGeometry(posX, posY, podKey)
    local left, right = (x - halfWidth) * g_screenWidth, (x + halfWidth) * g_screenWidth
    local bottom, top = (y - halfHeight) * g_screenHeight, (y + halfHeight) * g_screenHeight
    local x0, x1 = math.floor(left + 0.5), math.floor(right - 0.5)
    local y0, y1 = math.floor(bottom + 0.5), math.floor(top - 0.5)
    -- an even number of rows, each end a half circle about a pixel edge
    if (y1 - y0) % 2 == 0 then
        if math.abs(y1 + 1.5 - (top - 0.5)) < math.abs(y0 - 0.5 - (bottom + 0.5)) then
            y1 = y1 + 1
        else
            y0 = y0 - 1
        end
    end
    local columns, rows = x1 - x0 + 1, y1 - y0 + 1
    local pixelX, pixelY = g_pixelSizeX, g_pixelSizeY

    -- drawFilledRectRound scales its corner of 20 reference pixels
    local _, corner = getNormalizedScreenValues(20, 20)
    local glass = RMS_Hud.DASHBOARD.POD_GLASS
    drawFilledRectRound(x0 * pixelX, y0 * pixelY, columns * pixelX, rows * pixelY, rows * pixelY / (2 * corner),
        glass[1], glass[2], glass[3], glass[4])

    local ring, half = RMS_Hud.COLOR_GAME_GREEN, rows / 2
    drawFilledRect((x0 + half) * pixelX, y0 * pixelY, (columns - rows) * pixelX, pixelY, ring[1], ring[2], ring[3], 1)
    drawFilledRect((x0 + half) * pixelX, y1 * pixelY, (columns - rows) * pixelX, pixelY, ring[1], ring[2], ring[3], 1)
    for _, pixel in ipairs(getRingEnd(rows)) do
        drawFilledRect((x0 + pixel[1]) * pixelX, (y0 + pixel[2]) * pixelY, pixelX, pixelY, ring[1], ring[2], ring[3], pixel[3])
        drawFilledRect((x1 - pixel[1]) * pixelX, (y0 + pixel[2]) * pixelY, pixelX, pixelY, ring[1], ring[2], ring[3], pixel[3])
    end
end

---Draws a pod's symbol and reading
-- @param float posX x of the panel (screen)
-- @param float posY y of the panel (screen)
-- @param string podKey pod
-- @param string picto picture of the symbol
-- @param table color rgba color of the symbol
-- @param string value figure
-- @param string unit unit
-- @param table figureColor rgba color of the figure
-- @param boolean isShown true to show the figure
-- @param table lamps lamps queued
function RMS_Hud:drawPod(posX, posY, podKey, picto, color, value, unit, figureColor, isShown, lamps)
    local x, y = self:getPodGeometry(posX, posY, podKey)
    if podKey == "plain" then
        addLamp(lamps, picto, x, y, color)
        return
    end
    self:drawSymbolFigure(x, y, picto, color, value, unit, figureColor, isShown, lamps)
end

---Draws a gauge piece turned to its place
-- @param float posX x of the dial centre (screen)
-- @param float posY y of the dial centre (screen)
-- @param table segment piece of the gauge
-- @param table color rgba color
function RMS_Hud:drawGaugeSegment(posX, posY, segment, color)
    local id = self.dashboard.gauge.overlayId
    setOverlayUVs(id, unpack(segment.uvs))
    setOverlayColor(id, color[1], color[2], color[3], color[4])
    setOverlayRotation(id, segment.angle, segment.width * 0.5, segment.height * 0.5)
    renderOverlay(id, posX + segment.left, posY + segment.bottom, segment.width, segment.height)
end

---Draws a gauge's pieces
-- @param float posX x of the dial centre (screen)
-- @param float posY y of the dial centre (screen)
-- @param table segments geometry and colours of the pieces
-- @param integer lit the number of lit pieces
-- @param boolean? isWarning true for the warning colours
function RMS_Hud:drawGaugeSegments(posX, posY, segments, lit, isWarning)
    local dash = RMS_Hud.DASHBOARD
    local halo, overlay = dash.HALO, self.dashboard.glow
    overlay:setSliceId(RMS_HudLayout.pieces.glow)
    for index = 1, lit do
        local segment = segments[index]
        local color = isWarning and segment.warning or segment.color
        overlay:setDimension(segment.glowWidth, segment.glowHeight)
        local x, y = posX + segment.glowX, posY + segment.glowY
        overlay:setPosition(x - overlay.width * 0.5, y - overlay.height * 0.5)
        overlay:setColor(color[1], color[2], color[3], index == lit and halo.LEAD_ALPHA or halo.ALPHA)
        overlay:render()
    end
    for index, segment in ipairs(segments) do
        local color = index <= lit and (isWarning and segment.warning or segment.color) or dash.SEGMENT_UNLIT
        self:drawGaugeSegment(posX, posY, segment, color)
    end
end

---Stores a gauge piece and its halo
-- @param string sliceId the piece's picture
-- @param float angle angle of the piece (rad)
-- @param float radius distance from the dial centre (reference pixels)
-- @param float depth across the gauge, reference px
-- @param table color rgba color
-- @return table segment piece of the gauge
function RMS_Hud:makeGaugeSegment(sliceId, angle, radius, depth, color)
    local box = getPieceBox(sliceId)
    local size = depth + 2 * RMS_Hud.DASHBOARD.HALO.MARGIN
    local x, y = self:scalePixelToScreenWidth(radius * math.cos(angle)), self:scalePixelToScreenHeight(radius * math.sin(angle))
    local width, height = self:scalePixelToScreenWidth(box[3] - box[1]), self:scalePixelToScreenHeight(box[4] - box[2])
    return { glowWidth = self:scalePixelToScreenWidth(size), glowHeight = self:scalePixelToScreenHeight(size),
        glowX = x, glowY = y, left = x - width * 0.5, bottom = y - height * 0.5, width = width, height = height,
        angle = angle, color = color, uvs = g_overlayManager:getSliceInfoById(sliceId).uvs }
end

---Stores the water gauge pieces
-- @param float hot temperature of the warning (deg C)
-- @param float? cold temperature of a cold engine (deg C), nil on an electric machine
-- @return table gauge pieces of the gauge
function RMS_Hud:buildWaterGauge(hot, cold)
    local dash, colors = RMS_Hud.DASHBOARD, RMS_Breakdowns.COLORS
    local gauge, scale = RMS_HudLayout.gauges.water, dash.WATER_SCALE
    local radius, ribbonRadius = (gauge.arcIn + gauge.arcOut) * 0.5, (gauge.ribIn + gauge.ribOut) * 0.5
    local segments = {}
    for index = 0, gauge.count - 1 do
        local t = (index + 0.5) / gauge.count
        local angle = math.rad(gauge.footAngle + (gauge.topAngle - gauge.footAngle) * t)
        local level = scale.LOW + t * (scale.HIGH - scale.LOW)
        local zone = RMS_Hud.COLOR_GAME_GREEN
        if level > hot then
            zone = colors.CRITICAL
        elseif cold ~= nil and level < cold then
            zone = colors.COOL
        end
        local segment = self:makeGaugeSegment(gauge.piece, angle, radius, gauge.arcOut - gauge.arcIn,
            zone == colors.CRITICAL and colors.CRITICAL or FIGURE_COLOR)
        segment.ribbon = self:makeGaugeSegment(gauge.ribbon, angle, ribbonRadius, gauge.ribOut - gauge.ribIn, zone)
        segments[index + 1] = segment
    end
    self.gaugeGeometry.water = { hot = hot, cold = cold, segments = segments }
    return self.gaugeGeometry.water
end

---Draws the water gauge
-- @param float posX x of the dial centre (screen)
-- @param float posY y of the dial centre (screen)
-- @param table spec RMS specialization of the vehicle
-- @param boolean isPowered true while the dashboard is powered
function RMS_Hud:drawWaterGauge(posX, posY, spec, isPowered)
    local scale = RMS_Hud.DASHBOARD.WATER_SCALE
    local hot = RMS_Thermal.getDriveValues(spec).TELLTALE.WARNING
    local cold = not spec.isElectricVehicle and RMS_Config.CORE.ENGINE_FACTOR_DATA.COLD_MOTOR_TEMP_THRESHOLD or nil
    local water = self.gaugeGeometry.water
    if water == nil or water.hot ~= hot or water.cold ~= cold then
        water = self:buildWaterGauge(hot, cold)
    end
    local temperature = spec.engineTemperature
    local share = isPowered and math.clamp((temperature - scale.LOW) / (scale.HIGH - scale.LOW), 0, 1) or 0
    local lit = math.floor(share * #water.segments + 1e-9)
    for _, segment in ipairs(water.segments) do
        self:drawGaugeSegment(posX, posY, segment.ribbon, segment.ribbon.color)
    end
    self:drawGaugeSegments(posX, posY, water.segments, lit)
end

---Stores the power gauge pieces
-- @return table gauge pieces of the gauge
function RMS_Hud:buildPowerGauge()
    local gauge, colors = RMS_HudLayout.gauges.power, RMS_Breakdowns.COLORS
    local segments = {}
    for index = 0, gauge.count - 1 do
        local t = (index + 0.5) / gauge.count
        local depth = gauge.thin + (gauge.thick - gauge.thin) * t
        local angle = math.rad(gauge.footAngle + (gauge.topAngle - gauge.footAngle) * t)
        local segment = self:makeGaugeSegment(gauge.pieces[index + 1], angle, gauge.inner + depth * 0.5, depth, FIGURE_COLOR)
        segment.warning = t >= gauge.zone and colors.WARNING or nil
        segments[index + 1] = segment
    end
    self.gaugeGeometry.power = { segments = segments }
    return self.gaugeGeometry.power
end

---Draws the power gauge
-- @param float posX x of the dial centre (screen)
-- @param float posY y of the dial centre (screen)
-- @param integer squares squares lit
-- @param boolean isWarning true for an overload
function RMS_Hud:drawPowerGauge(posX, posY, squares, isWarning)
    local power = self.gaugeGeometry.power or self:buildPowerGauge()
    self:drawGaugeSegments(posX, posY, power.segments, squares, isWarning)
end

---Draws the engine block
-- @param float posX x of the panel (screen)
-- @param float posY y of the panel (screen)
-- @param table content content of the dashboard
-- @param table lamp colors by lamp
-- @param table vehicle vehicle
-- @param table spec RMS specialization of the vehicle
-- @param boolean isRoadVehicle true for a road vehicle
-- @param boolean isMachine true for a working machine
-- @param boolean isPowered true while the dashboard is powered
-- @param table lamps lamps queued
function RMS_Hud:drawEngineBlock(posX, posY, content, lamp, vehicle, spec, isRoadVehicle, isMachine, isPowered, lamps)
    local engine = content.engine
    if engine == nil then
        return
    end
    local window = RMS_HudLayout.pieces.window
    local windowBox = getPieceBox(window)
    local index = 0
    for _, row in ipairs(engine.windows) do
        -- a row's windows a whole-pixel step apart
        local first, step = posX + self:scalePixelToScreenWidth(row[1][1]), 0
        if #row > 1 then
            step = math.floor(self:scalePixelToScreenWidth(row[1][1] - row[2][1]) * g_screenWidth + 0.5) / g_screenWidth
        end
        for column, place in ipairs(row) do
            index = index + 1
            local id = content.windows[index]
            local x, y = first - (column - 1) * step, posY + self:scalePixelToScreenHeight(place[2])
            if not content.hasScreen then
                self:drawBodyOutline(RMS_HudLayout.bodies.window, windowBox,
                    self:drawDashboardPiece(self.dashboard.piece, window, windowBox, x, y, FIGURE_COLOR, true))
            end
            addLamp(lamps, RMS_Hud.getDashboardPicto(id, spec, isRoadVehicle, isMachine), x, y, lamp[id])
        end
    end

    for row, id in ipairs(content.readings) do
        local picto = RMS_Hud.getDashboardPicto(id, spec, isRoadVehicle, isMachine)
        local value, unit = RMS_Hud.getReading(vehicle, spec, id)
        self:drawSymbolFigure(posX + self:scalePixelToScreenWidth(engine.rowStarts[row]), posY + self:scalePixelToScreenHeight(engine.rows[row]),
            picto, lamp[id], value, unit, getFigureColor(lamp[id]), isPowered, lamps, true)
    end

    if isPowered and #content.readings > 1 then
        self:drawReadingRules(posX, posY, engine.hairlines)
    end
end

---Returns the front-wheel drive symbol's colour
-- @param table state drivetrain state
-- @param table vehicle vehicle
-- @param boolean isPowered true while the dashboard is powered
-- @return table color rgba color
local function getFrontWheelDriveSymbolColor(state, vehicle, isPowered)
    if not isPowered then
        return RMS_Breakdowns.COLORS.DEFAULT
    end
    local color = RMS_Hud.getFrontWheelDriveColor(state, vehicle)
    return color == RMS_Breakdowns.COLORS.DEFAULT and FIGURE_COLOR or color
end

---Draws the drivetrain block
-- @param float posX x of the panel (screen)
-- @param float posY y of the panel (screen)
-- @param table content content of the dashboard
-- @param table lamp colors by lamp
-- @param table vehicle vehicle
-- @param table spec RMS specialization of the vehicle
-- @param boolean isPowered true while the dashboard is powered
-- @param table lamps lamps queued
function RMS_Hud:drawDriveBlock(posX, posY, content, lamp, vehicle, spec, isPowered, lamps)
    local drive = content.drive
    if drive == nil then
        return
    end
    local layout = RMS_HudLayout
    local pieces = layout.pieces
    local state = content.drivetrain
    local colors = RMS_Breakdowns.COLORS
    if drive.tile ~= nil then
        local color = getFrontWheelDriveSymbolColor(state, vehicle, isPowered)
        local tile, slice = drive.tile, pieces.tiles.fwd
        local x, y = posX + self:scalePixelToScreenWidth((tile[1] + tile[2]) * 0.5), posY + self:scalePixelToScreenHeight(tile[3])
        self:drawBodyOutline(layout.bodies.fwd, getPieceBox(slice), self:drawDashboardPiece(self.dashboard.piece, slice, getPieceBox(slice),
            x, y, FIGURE_COLOR, true))
        self:drawSymbolFigure(x, y, "frontWheelDrive", color, RMS_Hud.getDriveModeText(state), "", getFigureColor(color), isPowered, lamps)
    end

    local windows, step = content.driveWindows, content.driveWindowStep
    local windowBox = getPieceBox(pieces.window)
    local rowBox = getPieceBox(pieces.pictos.brakes)
    for index, window in ipairs(windows) do
        local x = posX + self:scalePixelToScreenWidth(windows[1].place[1]) - (index - 1) * step
        local y = posY + self:scalePixelToScreenHeight(window.place[2])
        if content.hasScreen then
            local left, bottom, width, height = self:getDashboardPieceBounds(rowBox, x, y, true)
            x, y = left + width * 0.5, bottom + height * 0.5
        else
            local left, bottom, right, top = self:drawBodyOutline(layout.bodies.window, windowBox,
                self:drawDashboardPiece(self.dashboard.piece, pieces.window, windowBox, x, y, FIGURE_COLOR, true))
            x, y = (left + 1 + right) * 0.5 / g_screenWidth, (bottom + 1 + top) * 0.5 / g_screenHeight
        end
        local ink = layout.inks[window.picto]
        local color = lamp[window.picto]
        if window.picto == "diffLock" then
            color = isPowered and RMS_Hud.getDiffLockColor(state, g_time) or colors.DEFAULT
        end
        addLamp(lamps, window.picto, x - self:scalePixelToScreenWidth((ink[1] + ink[2]) * 0.5),
            y - self:scalePixelToScreenHeight((ink[3] + ink[4]) * 0.5), color, true)
    end

    if drive.pto ~= nil then
        local isTurning, rpm = RMS_Utils.getPtoDisplay(vehicle)
        local color = isPowered and FIGURE_COLOR or colors.DEFAULT
        if isPowered and isTurning then
            color = RMS_Hud.COLOR_GAME_GREEN
        end
        local showRpm = isPowered and (rpm ~= nil or isTurning)
        local value = showRpm and (rpm ~= nil and string.format("%.0f", rpm) or "-") or ""
        local unit = isPowered and rpm ~= nil and g_i18n:getText("rms_hud_pto_rpm_unit") or ""
        self:drawSymbolFigure(posX + self:scalePixelToScreenWidth(drive.pto[1]), posY + self:scalePixelToScreenHeight(drive.pto[2]),
            "pto", color, value, unit,
            FIGURE_COLOR, showRpm, lamps, true)
    end
    if drive.fwd ~= nil then
        local color = getFrontWheelDriveSymbolColor(state, vehicle, isPowered)
        self:drawSymbolFigure(posX + self:scalePixelToScreenWidth(drive.fwd[1]), posY + self:scalePixelToScreenHeight(drive.fwd[2]),
            "frontWheelDrive", color, RMS_Hud.getDriveModeText(state), "", getFigureColor(color), isPowered, lamps, true)
    end
    if drive.slip ~= nil then
        local slip = math.clamp(spec.wheelSlipIntensity, 0, 1)
        local x = drive.slip[1] + RMS_Hud.DASHBOARD.SLIP_READING_OFFSET
        self:drawSymbolFigure(posX + self:scalePixelToScreenWidth(x), posY + self:scalePixelToScreenHeight(drive.slip[2]),
            "wheelSlip", isPowered and FIGURE_COLOR or colors.DEFAULT, string.format("%.0f", slip * 100), "%", FIGURE_COLOR,
            isPowered, lamps, true)
    end
    if isPowered then
        self:drawReadingRules(posX, posY, drive.hairlines)
    end
end

---Draws the lamps of the dial
-- @param float posX x of the dial centre (screen)
-- @param float posY y of the dial centre (screen)
-- @param table slots lamp places of the dial
-- @param table lamp colors by lamp
function RMS_Hud:drawDialLamps(posX, posY, slots, lamp)
    local colors = RMS_Breakdowns.COLORS
    for _, slot in ipairs(slots) do
        local icon, color = slot.icon, lamp[slot.id]
        local x, y = posX + slot.x, posY + slot.y + slot.lift
        icon:setPosition(snapScreenX(x - icon.width * 0.5), snapScreenY(y - icon.height * 0.5))
        if color ~= colors.DEFAULT then
            self:drawDialLampHalo(icon, slot.slice, color)
        end
    end
    for _, slot in ipairs(slots) do
        slot.icon:setColor(unpack(lamp[slot.id]))
        slot.icon:render()
    end
end

---Caches the odometer's text widths
-- @param table self HUD
-- @param float size text size
-- @param string unit unit
-- @return table layout widths of the odometer
local function getOdometerLayout(self, size, unit)
    local layout = self.odometerLayout
    if layout == nil or layout.size ~= size or layout.unit ~= unit then
        local widest, widestWidth = "0", getTextWidth(size, "0")
        for digit = 1, 9 do
            local text = tostring(digit)
            local width = getTextWidth(size, text)
            if width > widestWidth then
                widest, widestWidth = text, width
            end
        end
        layout = { size = size, unit = unit, valueWidth = getTextWidth(size, (("0000.0 " .. unit):gsub("%d", widest))),
            ODO = getTextWidth(size, "ODO"), TRIP = getTextWidth(size, "TRIP"),
            zeros = { getTextWidth(size, "0"), getTextWidth(size, "00"), getTextWidth(size, "000") } }
        self.odometerLayout = layout
    end
    return layout
end

---Draws the odometer or the trip meter
function RMS_Hud:drawOdometer()
    local speedMeter = g_currentMission.hud.speedMeter
    local kilometers = RMS_Utils.getOdometerKilometers(self.vehicle)
    if kilometers == nil or speedMeter.vehicle ~= self.vehicle or not speedMeter.isVehicleDrawSafe then
        return
    end

    local label = "ODO"
    local spec = self.vehicle.spec_RealisticMechanicalSystems
    if spec.odometerShowsTrip then
        label = "TRIP"
        kilometers = math.max(kilometers - spec.tripStartKilometers, 0)
    end
    -- the shown tenths wrap past 9999.9
    local displayTenths = math.floor(g_i18n:getDistance(kilometers) * 10 + 0.5) % 100000
    local unit = g_i18n:getMeasuringUnit()
    local value = string.format("%04d.%d %s", math.floor(displayTenths / 10), displayTenths % 10, unit)
    local size = speedMeter:scalePixelToScreenHeight(10)
    local gap = speedMeter:scalePixelToScreenWidth(4)
    setTextStyle(RenderText.ALIGN_LEFT, RenderText.VERTICAL_ALIGN_BOTTOM, true)

    local layout = getOdometerLayout(self, size, unit)
    local labelWidth = layout[label]
    local width = labelWidth + gap + layout.valueWidth

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
        valueX = valueX + layout.zeros[#prefix]
    end
    setTextColor(1, 1, 1, 1)
    renderText(valueX, y, size, value:sub(#prefix + 1))
    setTextBold(false)
end

---Returns the height of a telemetry card
-- @return float height height (screen)
function RMS_Hud:getTelemetryCardHeight()
    local text = self.telemetryText
    return getTextHeight(text.size, "0") + text.paddingV * 2
end

---Returns how far the meter and fill levels rise above the cards
-- @param table? vehicle vehicle
-- @return float lift lift (screen), on whole pixels
function RMS_Hud.getSpeedMeterLift(vehicle)
    local hud = RMS_Main.hud
    if hud == nil or vehicle == nil or vehicle.spec_RealisticMechanicalSystems == nil then
        return 0
    end
    local lift = hud:getTelemetryCardHeight() + hud.telemetryCardGapY
    return math.floor(lift * g_screenHeight + 0.5) / g_screenHeight
end

---Draws the fuel consumption and load mass cards
function RMS_Hud:drawTelemetryCards()
    local speedMeter = g_currentMission.hud.speedMeter
    if self.vehicle.spec_RealisticMechanicalSystems == nil then
        return
    end

    local cardRightX = speedMeter:getPosition()
    self:drawFuelConsumption(self:drawLoadMass(cardRightX))
end

---Draws a green separator one pixel thick, as many rows above as below
-- @param float x x (screen)
-- @param float panelY bottom of the card (screen)
-- @param float panelH height of the card (screen)
-- @param table color rgba color
local function drawCardSeparator(x, panelY, panelH, color)
    local panelRows = math.floor(panelH * g_screenHeight + 0.5)
    local rows = math.floor(panelRows * 0.55)
    rows = rows + (panelRows - rows) % 2
    drawRule(x - g_pixelSizeX * 0.5, panelY + (panelRows - rows) * 0.5 / g_screenHeight, g_pixelSizeX,
        rows / g_screenHeight, color)
end

---Returns an average, a dash without one
-- @param float? value average
-- @return string text average
local function formatAverage(value)
    return value ~= nil and formatConsumptionValue(value) or "-"
end

---Writes a piece of a card's text
-- @param table pieces pieces of the card
-- @param integer index piece
-- @param string text text
-- @param boolean isBold true for bold
-- @param float gap gap before it (screen)
-- @param boolean? hasSeparator a green separator before it
local function setCardPiece(pieces, index, text, isBold, gap, hasSeparator)
    local piece = pieces[index]
    if piece == nil then
        piece = {}
        pieces[index] = piece
    end
    piece[1], piece[2], piece[3], piece[4] = text, isBold, gap, hasSeparator
end

---Drops the pieces of a card past a count
-- @param table pieces pieces of the card
-- @param integer count pieces kept
local function trimCardPieces(pieces, count)
    for index = #pieces, count + 1, -1 do
        pieces[index] = nil
    end
end

local MASS_LABELS = { "rms_hud_mass_tractor", "rms_hud_mass_towed", "rms_hud_mass_total" }

---Returns the gaps of the card texts, in screen width
-- @return float label gap after a label
-- @return float unit gap before a unit
-- @return float separator gap of a separator
-- @return float between gap between the averages
function RMS_Hud:getTelemetryGaps()
    local gap, scale = RMS_Hud.CARD_GAP, RMS_Hud.CARD_SCALE
    return self:scalePixelToScreenWidth(gap.LABEL * scale), self:scalePixelToScreenWidth(gap.UNIT * scale),
        self:scalePixelToScreenWidth(gap.SEPARATOR * scale), self:scalePixelToScreenWidth(gap.AVERAGE * scale)
end

---Draws a card of the bottom row: its green icon, then its texts
-- @param float cardRightX right edge of the card (screen)
-- @param table card card
-- @param float cell size of the icon cell (reference pixels)
-- @param table ink ink of the icon in its cell (reference pixels)
-- @param table pieces each text, bold, gap before it, separator in it
-- @return float right right edge of the next card (screen)
function RMS_Hud:drawTelemetryCard(cardRightX, card, cell, ink, pieces)
    local size, padH = self.telemetryText.size, self.telemetryText.paddingH
    local textWidth = 0
    for _, piece in ipairs(pieces) do
        setTextBold(piece[2])
        piece.width = getTextWidth(size, piece[1])
        textWidth = textWidth + piece[3] + piece.width
    end
    local lastLetter = pieces[#pieces][1]:match("[^\128-\191][\128-\191]*$")
    local endSpace = getTextWidth(size, lastLetter) * (RMS_Hud.CARD_END_SPACE[lastLetter] or 0)

    local inkLeft = card.width * ink[1] / cell
    local iconWidth = card.width * (ink[2] - ink[1]) / cell
    local contentWidth = iconWidth + card.iconGap + textWidth - endSpace
    local panelW = snapScreenX(contentWidth + padH * 2)
    local panelH = snapScreenY(self:getTelemetryCardHeight())
    local _, panelY = g_currentMission.hud.speedMeter:getPosition()
    panelY = snapScreenY(panelY)
    local panelX = snapScreenX(cardRightX) - panelW
    local startX = panelX + (panelW - contentWidth) * 0.5
    local textX = startX + iconWidth + card.iconGap
    local middleY = panelY + panelH * 0.5

    local bg = HUD.COLOR.BACKGROUND
    drawFilledRectRound(panelX, panelY, panelW, panelH, 0.35, bg[1], bg[2], bg[3], bg[4])

    local green = HUD.COLOR.ACTIVE
    local icon = card.icon
    icon:setPosition(startX - inkLeft, middleY - card.height * (1 - ink[3] / cell))
    icon:setColor(green[1], green[2], green[3], green[4])
    icon:setVisible(true)
    icon:render()

    local baselineY = middleY - size * RMS_Hud.FIGURES_MIDDLE
    setTextStyle(RenderText.ALIGN_LEFT, RenderText.VERTICAL_ALIGN_BASELINE, true)
    for _, piece in ipairs(pieces) do
        if piece[4] then
            drawCardSeparator(textX + piece[3] * 0.5, panelY, panelH, green)
        end
        textX = textX + piece[3]
        setTextBold(piece[2])
        setTextColor(1, 1, 1, piece[2] and 1 or 0.55)
        renderText(textX, baselineY, size, piece[1])
        textX = textX + piece.width
    end
    setTextBold(false)
    return panelX - self.telemetryCardGap
end

---Draws the fuel consumption card: now, then the trip's averages
-- @param float cardRightX right edge of the card (screen)
function RMS_Hud:drawFuelConsumption(cardRightX)
    local vehicle = self.vehicle
    local spec = vehicle.spec_RealisticMechanicalSystems

    local _, fuelCapacity, fuelType = SpeedMeterDisplay.getVehicleFuelLevelAndCapacity(vehicle)
    if fuelCapacity == nil or fuelCapacity <= 0 then
        return
    end

    local isElectric = fuelType == FillType.ELECTRICCHARGE
    local isMethane = fuelType == FillType.METHANE
    local amount = g_i18n:getText(isMethane and "unit_kg" or "unit_literShort")
    local perHourUnit = isElectric and g_i18n:getText("rms_hud_unit_kw") or amount .. g_i18n:getText("rms_hud_unit_perHour")
    local perAreaUnit = (isElectric and g_i18n:getText("rms_hud_unit_kwh") or amount) .. "/" .. g_i18n:getText("unit_haShort")
    local perHour = vehicle:getIsMotorStarted() and vehicle.spec_motorized.lastFuelUsageDisplay or 0

    local labelGap, unitGap, separatorGap, averageGap = self:getTelemetryGaps()
    local card = self.fuelConsumptionHud
    card.pieces = card.pieces or {}
    local pieces = card.pieces
    setCardPiece(pieces, 1, formatConsumptionValue(perHour), true, 0)
    setCardPiece(pieces, 2, perHourUnit, false, unitGap)
    local count = 2
    if not spec.isExcludedVehicle then
        setCardPiece(pieces, 3, g_i18n:getText("rms_hud_fuel_average"), false, separatorGap, true)
        setCardPiece(pieces, 4, formatAverage(RMS_TripFuel.getAveragePerHour(spec)), true, labelGap)
        setCardPiece(pieces, 5, perHourUnit, false, unitGap)
        setCardPiece(pieces, 6, formatAverage(RMS_TripFuel.getAveragePerArea(spec)), true, averageGap)
        setCardPiece(pieces, 7, perAreaUnit, false, unitGap)
        count = 7
    end
    trimCardPieces(pieces, count)

    local sliceId = isElectric and "gui.icon_electricCharge" or (isMethane and "gui.icon_methane" or "gui.icon_fuel")
    if card.sliceId ~= sliceId then
        card.icon:setSliceId(sliceId)
        card.sliceId = sliceId
    end
    local fuelIcon = RMS_Hud.FUEL_ICON
    self:drawTelemetryCard(cardRightX, card, fuelIcon.CELL, fuelIcon.INK[sliceId], pieces)
end

---Returns a mass rounded to 100 kg, held until it moves as much
-- @param string key mass shown
-- @param float mass mass (t)
-- @return float shown mass shown (t)
function RMS_Hud:getShownMass(key, mass)
    local shown = self.shownMasses[key]
    if shown == nil or math.abs(mass - shown) >= 0.1 then
        shown = math.floor(mass * 10 + 0.5) / 10
        self.shownMasses[key] = shown
    end
    return shown
end

---Draws the weight card: the machine, what it tows, the whole
-- @param float cardRightX right edge of the card (screen)
-- @return float right right edge of the next card (screen)
function RMS_Hud:drawLoadMass(cardRightX)
    local vehicle = self.vehicle
    local totalMass = vehicle:getTotalMass()
    -- a container locked on a hook lift is carried, not towed
    local container = RMS_Utils.getLockedHookLiftContainer(vehicle)
    local ownMass = vehicle:getTotalMass(true) + (container ~= nil and container:getTotalMass() or 0)
    local shownOwn = self:getShownMass("own", math.min(ownMass, totalMass))
    local shownTowed = self:getShownMass("towed", math.max(totalMass - ownMass, 0))

    local labelGap, unitGap, separatorGap = self:getTelemetryGaps()
    local unit = g_i18n:getText("unit_tonsShort")
    local card = self.loadMassHud
    card.pieces = card.pieces or {}
    local pieces = card.pieces
    for index, labelKey in ipairs(MASS_LABELS) do
        local mass = index == 1 and shownOwn or (index == 2 and shownTowed or shownOwn + shownTowed)
        setCardPiece(pieces, index * 3 - 2, g_i18n:getText(labelKey), false, index > 1 and separatorGap or 0, index > 1)
        setCardPiece(pieces, index * 3 - 1, formatValue(mass, "%.1f"), true, labelGap)
        setCardPiece(pieces, index * 3, unit, false, unitGap)
    end
    local weightIcon = RMS_Hud.WEIGHT_ICON
    return self:drawTelemetryCard(cardRightX, card, weightIcon.CELL, weightIcon.INK, pieces)
end

---Returns the damage the game's bar shows for the selected machine
-- @param table vehicle vehicle controlled
-- @return float? damage damage, 0 to 1, nil to leave the game's
function RMS_Hud.getSelectedDamage(vehicle)
    for _, child in ipairs(vehicle.rootVehicle.childVehicles) do
        if child:getIsSelected() and child.getDamageShowOnHud ~= nil and child:getDamageShowOnHud() then
            if child.getLastInspectedCondition == nil then
                return child:getDamageAmount()
            end
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

---Returns the damage the speed meter shows
-- @return float? damage damage, 0 to 1
local function getShownDamage()
    return shownDamage
end

---Returns how much wider a machine's meter is
-- @param table speedMeter speed meter of the game
-- @param table vehicle vehicle controlled
-- @return float extension both sections
-- @return float adBlueExtension the AdBlue gauge's section
function RMS_Hud.getSpeedMeterExtension(speedMeter, vehicle)
    local section = math.floor(-speedMeter.fuelOffsetX * g_screenWidth + 0.5) / g_screenWidth
    local adBlue = 0
    if RMS_AdBlue.getLevel(vehicle) ~= nil and select(2, SpeedMeterDisplay.getVehicleFuelLevelAndCapacity(vehicle)) ~= nil then
        adBlue = section
    end
    local spec = vehicle.spec_RealisticMechanicalSystems
    local power = 0
    if spec ~= nil and not spec.isExcludedVehicle and RMS_Hud.getHasScreen(vehicle) then
        power = section
    end
    return adBlue + power, adBlue
end

local WHITE = { 1, 1, 1, 1 }

---Draws the AdBlue gauge where the fuel stood, its lamp above
-- @param table speedMeter speed meter of the game
-- @param table vehicle vehicle controlled
-- @param float posX x of the meter (screen)
-- @param float posY y of the meter (screen)
-- @param float extension width added to the meter (screen)
-- @param float adBlueExtension width of the AdBlue section (screen)
-- @param float neighbourOffsetX shift of the gauge beside it (screen)
local function drawAdBlueGauge(speedMeter, vehicle, posX, posY, extension, adBlueExtension, neighbourOffsetX)
    local level = RMS_AdBlue.getLevel(vehicle)
    local config = RMS_Config.EXHAUST.ADBLUE
    -- halfway between the fuel, moved out, and the section that stayed
    local fuelX = posX + speedMeter.sectionOffsetX + speedMeter.fuelOffsetX
    local x = fuelX + extension + (neighbourOffsetX - adBlueExtension) * 0.5
    local y = posY + speedMeter.sectionOffsetY + speedMeter.fuelOffsetY

    local bar, maxWidth = speedMeter.bar, speedMeter.barMaxScaleWidth
    bar:setColor(0, 0, 0, 1)
    bar:setMiddlePart(nil, maxWidth, nil)
    bar:setPosition(x + speedMeter.fuelBarOffsetX, y + speedMeter.fuelBarOffsetY)
    bar:render()
    if level > 0 then
        if level >= config.WARNING_LEVEL then
            bar:setColor(unpack(config.GAUGE_COLOR))
        else
            bar:setColor(1, 0.1233, 0, math.abs(math.cos(g_time / 300)))
        end
        bar:setMiddlePart(nil, math.clamp(maxWidth * level, 0, maxWidth), nil)
        bar:setPosition(x + speedMeter.fuelBarOffsetX, y + speedMeter.fuelBarOffsetY)
        bar:render()
    end

    local hud = RMS_Main.hud
    local icon = hud.lampIcons.adBlue
    local fuelIcon = RMS_Hud.FUEL_ICON
    local size = speedMeter.fuelIcon.height * fuelIcon.INK_HEIGHT / fuelIcon.CELL * RMS_Hud.LAMP.CELL / RMS_Hud.LAMP_INK.adBlue[2]
    local px = math.floor(size * g_screenHeight + 0.5)
    icon:setDimension(px / g_screenWidth, px / g_screenHeight)
    local lit = RMS_AdBlue.getLampColor(level, g_time)
    local centreX = x + speedMeter.fuelIconOffsetX + speedMeter.fuelIcon.width * 0.5
    local centreY = y + speedMeter.fuelIconOffsetY + speedMeter.fuelIcon.height * 0.5
    icon:setPosition(snapScreenX(centreX - icon.width * 0.5), snapScreenY(centreY - icon.height * 0.5))
    if lit ~= nil then
        hud:drawDialLampHalo(icon, "adBlue", lit)
    end
    local color = lit or WHITE
    icon:setColor(color[1], color[2], color[3], color[4])
    icon:render()
end

---Draws the meter wider to the left
-- @param table speedMeter speed meter of the game
-- @param function superFunc original function
-- @param table vehicle vehicle controlled
-- @param float extension width added to the meter (screen)
-- @param float adBlueExtension width of the AdBlue section (screen)
local function drawWiderSpeedMeter(speedMeter, superFunc, vehicle, extension, adBlueExtension)
    local gameX, posY = speedMeter:getPosition()
    local posX = gameX - extension
    speedMeter:setPosition(posX, posY)
    local hasRepair = vehicle.getDamageAmount ~= nil and vehicle:getDamageAmount() ~= nil
    local neighbourKey = hasRepair and "repairOffsetX" or "gearOffsetX"
    local sectionOffsetX, neighbourOffsetX = speedMeter.sectionOffsetX, speedMeter[neighbourKey]
    local rightEnd = speedMeter.speedBgRight
    local ownRender, gameRender = rawget(rightEnd, "render"), rightEnd.render
    local aiSeparatorX, aiTextX, aiIconX = speedMeter.aiSeperatorOffsetX, speedMeter.aiTextOffsetX, speedMeter.aiIconOffsetX
    speedMeter.sectionOffsetX = sectionOffsetX + extension
    speedMeter[neighbourKey] = neighbourOffsetX - adBlueExtension
    speedMeter.aiSeperatorOffsetX = aiSeparatorX + extension
    speedMeter.aiTextOffsetX = aiTextX + extension
    speedMeter.aiIconOffsetX = aiIconX + extension
    -- a straight part of the sheet pushes the game's own end out
    rightEnd.render = function(gameEnd)
        local straight = RMS_Main.hud.meterStraight
        local x, y = gameEnd.x, gameEnd.y
        straight:setDimension(extension, gameEnd.height)
        straight:setPosition(x, y)
        straight:setColor(0, 0, 0, 1)
        straight:render()
        gameEnd:setPosition(x + extension, y)
        gameRender(gameEnd)
        gameEnd:setPosition(x, y)
    end
    superFunc(speedMeter)
    rightEnd.render = ownRender
    speedMeter.sectionOffsetX = sectionOffsetX
    speedMeter[neighbourKey] = neighbourOffsetX
    speedMeter.aiSeperatorOffsetX = aiSeparatorX
    speedMeter.aiTextOffsetX = aiTextX
    speedMeter.aiIconOffsetX = aiIconX
    if adBlueExtension > 0 then
        drawAdBlueGauge(speedMeter, vehicle, posX, posY, extension, adBlueExtension, neighbourOffsetX)
    end
end

---Draws the speed meter, its damage bar for the selected machine
-- @param table speedMeter speed meter of the game
-- @param function superFunc original function
-- @return any result what the game's draw returns, on a meter RMS leaves alone
function RMS_Hud.drawSpeedMeter(speedMeter, superFunc)
    local vehicle = speedMeter.vehicle
    local isDrawn = vehicle ~= nil and speedMeter.isVehicleDrawSafe
    local spec = isDrawn and vehicle.spec_RealisticMechanicalSystems or nil
    local damage = nil
    if isDrawn and (spec == nil or not spec.isExcludedVehicle) then
        damage = RMS_Hud.getSelectedDamage(vehicle)
    end

    local extension, adBlueExtension = 0, 0
    if isDrawn then
        extension, adBlueExtension = RMS_Hud.getSpeedMeterExtension(speedMeter, vehicle)
    end
    local lift = RMS_Hud.getSpeedMeterLift(vehicle)
    if damage == nil and extension <= 0 and lift == 0 then
        return superFunc(speedMeter)
    end

    local gameX, gameY = speedMeter:getPosition()
    speedMeter:setPosition(gameX, gameY + lift)
    local getDamageAmounts = nil
    if damage ~= nil then
        -- every machine of the combination reports the selected one's damage
        shownDamage = damage
        getDamageAmounts = {}
        for _, child in ipairs(vehicle.rootVehicle.childVehicles) do
            if child.getDamageAmount ~= nil then
                getDamageAmounts[child] = rawget(child, "getDamageAmount") or false
                child.getDamageAmount = getShownDamage
            end
        end
    end

    if extension > 0 then
        drawWiderSpeedMeter(speedMeter, superFunc, vehicle, extension, adBlueExtension)
    else
        superFunc(speedMeter)
    end

    if getDamageAmounts ~= nil then
        for child, original in pairs(getDamageAmounts) do
            child.getDamageAmount = original or nil
        end
    end
    speedMeter:setPosition(gameX, gameY)
end

---Draws the fill levels risen with the meter
-- @param table display fill levels display of the game
-- @param function superFunc original function
-- @return any result what the game's draw returns, on a display RMS leaves alone
function RMS_Hud.drawFillLevels(display, superFunc)
    local lift = RMS_Hud.getSpeedMeterLift(display.vehicle)
    if lift == 0 then
        return superFunc(display)
    end
    local gameX, gameY = display:getPosition()
    display:setPosition(gameX, gameY + lift)
    superFunc(display)
    display:setPosition(gameX, gameY)
end

---Adds the grease points due, else what is left before the next ones
-- @param table vehicle vehicle
-- @param table box info box
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

---Adds the AdBlue tank the game keeps out of the info box
-- @param table vehicle vehicle
-- @param table box info box
function RMS_Hud.addAdBlueLine(vehicle, box)
    local tank = RMS_AdBlue.getTank(vehicle)
    local fillUnit = tank ~= nil and vehicle:getFillUnitByIndex(tank) or nil
    if fillUnit == nil or fillUnit.showOnInfoHud or fillUnit.fillLevel <= 0 then
        return
    end
    local precision = fillUnit.uiPrecision
    local text
    if precision > 0 then
        local rounded = MathUtil.round(fillUnit.fillLevel, precision)
        text = string.format("%d%s%0" .. precision .. "d", math.floor(rounded), g_i18n.decimalSeparator,
            (rounded - math.floor(rounded)) * 10 ^ precision)
    else
        text = string.format("%d", MathUtil.round(fillUnit.fillLevel))
    end
    box:addLine(g_fillTypeManager:getFillTypeByIndex(fillUnit.fillType).title, text .. " " .. (fillUnit.unitText or g_i18n:getVolumeUnit()))
end

---Adds the RMS lines to the game's vehicle info box
-- @param table box info box
function RMS_Hud:showInfoVehicle(box)
    local spec = self.spec_RealisticMechanicalSystems
    if spec == nil then
        addGreasingLine(self, box)
        return
    elseif spec.isExcludedVehicle then
        return
    end

    RMS_Hud.addAdBlueLine(self, box)

    local schedule = self:getServiceSchedule()
    local _, isReportOutdated = self:getInspectionReportAge()
    box:addLine(g_i18n:getText('rms_ws_label_condition'), RMS_Utils.formatCondition(self:getLastInspectedCondition()), isReportOutdated)
    if schedule ~= nil then
        -- Native info-box rows cannot resize text
        box:addLine(RMS_Utils.formatMaintenanceLevel(self, schedule.maintenanceType), RMS_Utils.formatServiceDeadline(schedule), schedule.overdue)
    end
    addGreasingLine(self, box)

    if spec.batteryIsolated then
        box:addLine(g_i18n:getText("rms_battery_isolator_info"), nil, true)
    end

    local state = spec.currentState
    if state ~= RealisticMechanicalSystems.STATUS.READY then
        box:addLine(string.format(g_i18n:getText("rms_spec_last_maintenance_until_format"), RMS_Utils.formatServiceState(state),
            RMS_Utils.formatFinishTime(self:getServiceFinishTime())))
    end
end

---Hides the machine name while an RMS message shows
-- @param table hud HUD of the game
-- @param function superFunc original function
function RMS_Hud.drawVehicleName(hud, superFunc)
    if RMS_Main.hud ~= nil and RMS_Main.hud:getIsNotificationShown() then
        return
    end
    superFunc(hud)
end

Vehicle.showInfo = Utils.appendedFunction(Vehicle.showInfo, RMS_Hud.showInfoVehicle)
SpeedMeterDisplay.draw = Utils.overwrittenFunction(SpeedMeterDisplay.draw, RMS_Hud.drawSpeedMeter)
FillLevelsDisplay.draw = Utils.overwrittenFunction(FillLevelsDisplay.draw, RMS_Hud.drawFillLevels)
HUD.drawVehicleName = Utils.overwrittenFunction(HUD.drawVehicleName, RMS_Hud.drawVehicleName)
