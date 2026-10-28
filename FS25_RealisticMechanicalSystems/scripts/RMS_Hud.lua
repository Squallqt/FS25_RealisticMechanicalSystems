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
RMS_Hud.TRANSMISSION_OIL_TEMP_WARNING = 99
RMS_Hud.TELLTALE_YEARS = { engine = 1990, transmission = 1990, brakes = 1980, battery = 1950, coolant = 1950, warning = 1990,
    service = 1970, oil = 1950 }
RMS_Hud.ARC_ORDER = { "brakes", "engine", "dpf", "coolant", "fanReversal", "transmission", "battery" }
-- Gearbox before warning: a gearbox fault also lights the warning.
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
-- Row and service lamp size, times LAMP.SIZE
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
-- Linear grey of the game's rpm bars
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
-- Park brake lamp beside the gear: box and gap, reference px
RMS_Hud.PARK_BRAKE = { SIZE = 27.6, GAP = 5.5 }
-- INK: ink left, right and weight centre from the top, slice px
RMS_Hud.FUEL_ICON = { SIZE = 21, CELL = 30, GAP = 6,
    INK = { ["gui.icon_fuel"] = { 8, 23, 16.94 }, ["gui.icon_electricCharge"] = { 2, 28, 15.51 },
        ["gui.icon_methane"] = { 8, 22, 15.59 } } }

local lampLayouts = {}

---Returns the angular and radial extent of a lamp and its value below it
-- @param table unit lamp: ink width and height, reading width or nil, reference px
-- @param float phi angle of the lamp centre, radians anticlockwise from the right of the gauge centre
-- @param float radius reference px from the gauge centre
-- @return float low smallest angle from phi they cover, radians
-- @return float high largest
-- @return float near nearest reference px from the gauge centre
-- @return float far farthest
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

---Rounds a half angle up to the atlas cell grid
local function getCellHalf(half)
    local cell = RMS_Hud.CELL
    local steps = math.ceil((math.deg(half) - cell.HALF_MIN) / cell.HALF_STEP - 1e-6)
    return math.rad(math.min(cell.HALF_MAX, cell.HALF_MIN + math.max(0, steps) * cell.HALF_STEP))
end

---Places the lamp cells left of the dial
-- @param table units ordered lamps: id, ink width and height, reading width or nil, reference px
-- @return table layout by lamp id: lamp centre x and y; cell angle phi, half angle and slice
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
-- @param integer count lamps the machine carries in the row
-- @return table offsets x of each ink centre, reference px from the gauge centre
function RMS_Hud.getRowLayout(count)
    local offsets = {}
    for index = 1, count do
        offsets[index] = (index - (count + 1) * 0.5) * RMS_Hud.ROW.PITCH
    end
    return offsets
end

---Returns a bubble centre, flush with the top or bottom of the dial
-- @param boolean isHigh front axle above, wheel slip below
-- @return float x centre, reference px from the gauge centre
-- @return float y centre
function RMS_Hud.getBubbleCentre(isHigh)
    local y = 116 - RMS_Hud.BUBBLE.RADIUS
    return RMS_Hud.BUBBLE.X, isHigh and y or -y
end

-- @param float inkHeight ink height of the symbol
-- @return float symbolY centre of the symbol ink, reference px from the bubble centre
-- @return float valueY y of the value text
-- @return float valueBottom y of the foot of the value
function RMS_Hud.getBubbleContent(inkHeight)
    local bubble = RMS_Hud.BUBBLE
    local height = inkHeight + bubble.SYMBOL_GAP + bubble.VALUE_HEIGHT
    local valueBottom = -height * 0.5
    return height * 0.5 - inkHeight * 0.5, valueBottom + bubble.VALUE_HEIGHT - bubble.VALUE_TOP_ABOVE_ANCHOR, valueBottom
end

---Formats a number, dropping its decimals when it rounds to zero
local function formatValue(value, numberFormat)
    local amount = tonumber(value) or 0
    local text = string.format(numberFormat, amount)

    if text == string.format(numberFormat, 0) then
        return "0"
    end

    return text
end

---Formats a consumption readout, one decimal below a hundred
local function formatConsumptionValue(value)
    local amount = math.max(tonumber(value) or 0, 0)
    return formatValue(amount, amount < 100 and "%.1f" or "%.0f")
end

---Rounds a horizontal screen position to the nearest screen pixel
local function snapScreenX(x)
    return math.floor(x * g_screenWidth + 0.5) / g_screenWidth
end

---Rounds a vertical screen position to the nearest screen pixel
local function snapScreenY(y)
    return math.floor(y * g_screenHeight + 0.5) / g_screenHeight
end

---Create instance of RMS_Hud, loading its overlays and its sounds
-- @return table self instance of class RMS_Hud
function RMS_Hud:new()
	local self = RMS_Hud:superClass().new(RMS_Hud_mt)
	self.vehicle = nil
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

    self.lampScales = {}
    local function lampIcon(slice)
        local icon = g_overlayManager:createOverlay("rms_Hud." .. slice, 0, 0, 0, 0)
        self.lampScales[icon] = RMS_Hud.LAMP_SCALE[slice] or 1
        return icon
    end

    local engineIcon = lampIcon("engine")
    local coolantIcon = lampIcon("coolant")
    local serviceIcon = lampIcon("service")
    local oilIcon = lampIcon("oilPressure")

    self.indicators = {
        engine = {
            name = 'engine',
            icon = engineIcon,
            icons = {
                normal = engineIcon,
                fault = lampIcon("engine"),
                classic = lampIcon("engineClassic")
            },
            year = RMS_Hud.TELLTALE_YEARS.engine
        },
        transmission = {
            name = 'transmission',
            icon = lampIcon("transmissionTemperature"),
            year = RMS_Hud.TELLTALE_YEARS.transmission
        },
        brakes = {
            name = 'brakes',
            icon = lampIcon("brakes"),
            year = RMS_Hud.TELLTALE_YEARS.brakes
        },
        battery = {
            name = 'battery',
            icon = lampIcon("battery"),
            year = RMS_Hud.TELLTALE_YEARS.battery
        },
        coolant = {
            name = 'coolant',
            icon = coolantIcon,
            icons = { normal = coolantIcon, coolantRoad = lampIcon("coolantRoad") },
            year = RMS_Hud.TELLTALE_YEARS.coolant
        },
        dpf = {
            name = 'dpf',
            icon = lampIcon("particulateFilter")
        },
        fanReversal = {
            name = 'fanReversal',
            icon = lampIcon("fanReversal")
        },
        warning = {
            name = 'warning',
            icon = lampIcon("warning"),
            year = RMS_Hud.TELLTALE_YEARS.warning
        },
        preheat = {
            name = 'preheat',
            icon = lampIcon("preheat")
        },
        service = {
            name = 'service',
            icon = serviceIcon,
            icons = { normal = serviceIcon, wrench = lampIcon("wrench") },
            year = RMS_Hud.TELLTALE_YEARS.service
        },
        oil = {
            name = 'oil',
            icon = oilIcon,
            icons = { normal = oilIcon, oilCan = lampIcon("oilCan") },
            year = RMS_Hud.TELLTALE_YEARS.oil
        },
        tractionBattery = {
            name = 'tractionBattery',
            icon = lampIcon("tractionBattery")
        },
        limitedPower = {
            name = 'limitedPower',
            icon = lampIcon("limitedPower")
        }
    }

    self.indicatorRuntime = {}
    self.indicatorSoundConfig = {
        engine =        { cooldownMs = 1800 },
        transmission =  { cooldownMs = 1800 },
        brakes =        { cooldownMs = 1800 },
        battery =       { cooldownMs = 1800 },
        coolant =       { cooldownMs = 1800 },
        dpf =           { cooldownMs = 1800 },
        warning =       { cooldownMs = 1400 },
        preheat =       { cooldownMs = 1800 },
        service =       { cooldownMs = 2500 },
        oil =           { cooldownMs = 1800 },
        tractionBattery = { cooldownMs = 1800 },
        limitedPower =  { cooldownMs = 1800 }
    }

    self.indicatorValueText = {}

    self.loadMassText = {}

    self.notificationPanel = {
        title = nil,
        text = nil,
        endTime = nil,
        isVisible = false,
        isPersistent = false,
        closeGlyphSize = 26,
        closeGlyphTextSpacing = 6
    }

    self.inspectionProgress = {
        ratio = nil,
        messageText = nil,
        messageEndTime = 0
    }

    self.notificationCloseGlyph = nil
    self.notificationCloseGlyphInputMode = nil
    self.notificationInputContextName = nil
    self.notificationCloseActionEventId = nil

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

    for _, indicator in pairs(self.indicators) do
        if indicator.icons ~= nil then
            for _, icon in pairs(indicator.icons) do
                icon:delete()
            end
            indicator.icons = nil
        else
            indicator.icon:delete()
        end
        indicator.icon = nil
    end

    if self.notificationCloseGlyph ~= nil then
        self.notificationCloseGlyph:delete()
        self.notificationCloseGlyph = nil
    end

    RMS_Hud:superClass().delete(self)
end

---Binds the HUD to a vehicle and resets its per vehicle state
-- @param table? vehicle vehicle
function RMS_Hud:setVehicle(vehicle)
    if self.vehicle ~= vehicle then
        self.indicatorRuntime = {}
        self.telemetryDisplayValues.motorLoad = 0
        self.motorLoadAverage = { buckets = {}, current = { value = 0, time = 0 }, timer = 0 }
        self:resetConsumptionAverages()
    end

    self.vehicle = vehicle
end

---Returns the blink and sound state of an indicator, creating it on first use
-- @param string indicatorId dashboard indicator id
-- @return table state indicator runtime state
function RMS_Hud:getIndicatorRuntimeState(indicatorId)
    if self.indicatorRuntime == nil then
        self.indicatorRuntime = {}
    end

    if self.indicatorRuntime[indicatorId] == nil then
        self.indicatorRuntime[indicatorId] = {
            isLit = false,
            soundPlayedForCurrentActivation = false,
            lastSoundTime = 0,
            severity = 0,
            lastSoundSeverity = 0,
            blinkStartTime = 0,
            blinkActive = false
        }
    end

    return self.indicatorRuntime[indicatorId]
end

---Starts the blink cycle of an indicator
-- @param string indicatorId dashboard indicator id
function RMS_Hud:startIndicatorBlink(indicatorId)
    local runtimeState = self:getIndicatorRuntimeState(indicatorId)
    local vehicle = self.vehicle
    if vehicle == nil or vehicle.getMotorState == nil or vehicle:getMotorState() ~= MotorState.ON then
        runtimeState.blinkActive = false
        runtimeState.blinkStartTime = 0
        return
    end

    local now = g_currentMission.time

    runtimeState.blinkActive = true
    runtimeState.blinkStartTime = now
end

---Applies the blink colour of an indicator for this frame
-- @param string indicatorId dashboard indicator id
-- @param table targetColor colour the indicator lights in
-- @param boolean blinkWhileActive true to keep blinking while it stays lit
function RMS_Hud:applyIndicatorBlink(indicatorId, targetColor, blinkWhileActive)
    local runtimeState = self:getIndicatorRuntimeState(indicatorId)
    local colors = RMS_Breakdowns.COLORS
    local vehicle = self.vehicle
    if runtimeState == nil or runtimeState.blinkActive ~= true then
        return targetColor
    end

    if vehicle == nil or vehicle.getMotorState == nil or vehicle:getMotorState() ~= MotorState.ON then
        runtimeState.blinkActive = false
        runtimeState.blinkStartTime = 0
        return targetColor
    end

    local now = g_currentMission.time
    local blinkIntervalMs = 600
    local totalPhases = 4
    local elapsed = math.max(now - (runtimeState.blinkStartTime or 0), 0)
    local phaseIndex = math.floor(elapsed / blinkIntervalMs)

    if not blinkWhileActive and phaseIndex >= totalPhases then
        runtimeState.blinkActive = false
        return targetColor
    end

    if phaseIndex % 2 == 1 then
        return colors.DEFAULT
    end

    return targetColor
end

---Plays the warning or alarm sound once when an indicator lights up
-- @param string indicatorId dashboard indicator id
-- @param table runtimeState indicator runtime state
-- @param integer severity indicator severity
function RMS_Hud:tryPlayIndicatorActivationSound(indicatorId, runtimeState, severity)
    local vehicle = self.vehicle
    if vehicle == nil or vehicle.spec_RealisticMechanicalSystems == nil then
        return false
    end

    local config = self.indicatorSoundConfig ~= nil and self.indicatorSoundConfig[indicatorId] or nil
    if config == nil then
        return false
    end

    if vehicle.getMotorState == nil or vehicle:getMotorState() ~= MotorState.ON then
        return false
    end

    local spec = vehicle.spec_RealisticMechanicalSystems
    local samples = spec.samples
    if samples == nil then
        return false
    end

    local sample = severity >= 2 and samples.alarm or samples.warning
    if sample == nil then
        return false
    end

    local now = g_currentMission.time
    local cooldownMs = math.max(tonumber(config.cooldownMs) or 0, 0)
    local elapsed = now - (runtimeState.lastSoundTime or 0)

    if runtimeState.soundPlayedForCurrentActivation and severity <= (runtimeState.lastSoundSeverity or 0) then
        return false
    end

    if elapsed < cooldownMs then
        return false
    end

    RMS_SoundManager.playSample(sample)
    runtimeState.lastSoundTime = now
    runtimeState.soundPlayedForCurrentActivation = true
    runtimeState.lastSoundSeverity = severity or 0
    return true
end

---Lights or clears an indicator, with its blink and its sound
-- @param string indicatorId dashboard indicator id
-- @param boolean shouldLight true when the indicator must be lit
-- @param table targetColor colour the indicator lights in
function RMS_Hud:syncIndicatorActivation(indicatorId, shouldLight, targetColor)
    local runtimeState = self:getIndicatorRuntimeState(indicatorId)
    local colors = RMS_Breakdowns.COLORS
    local severity = 0

    if shouldLight then
        if targetColor == colors.CRITICAL then
            severity = 2
        elseif targetColor == colors.WARNING then
            severity = 1
        end
    end

    local wasLit = runtimeState.isLit == true
    local previousSeverity = runtimeState.severity or 0
    local turnedOn = shouldLight and not wasLit
    local turnedOff = not shouldLight and wasLit
    local escalatedToCritical = shouldLight and previousSeverity == 1 and severity == 2

    if turnedOn then
        runtimeState.isLit = true
        runtimeState.severity = severity
        if severity > 0 then
            self:startIndicatorBlink(indicatorId)
        end
        self:tryPlayIndicatorActivationSound(indicatorId, runtimeState, severity)
    elseif escalatedToCritical then
        runtimeState.isLit = true
        runtimeState.severity = severity
        if severity > 0 then
            self:startIndicatorBlink(indicatorId)
        end
        self:tryPlayIndicatorActivationSound(indicatorId, runtimeState, severity)
    elseif turnedOff then
        runtimeState.isLit = false
        runtimeState.severity = 0
        runtimeState.soundPlayedForCurrentActivation = false
        runtimeState.lastSoundSeverity = 0
        runtimeState.blinkActive = false
        runtimeState.blinkStartTime = 0
    else
        runtimeState.isLit = shouldLight
        runtimeState.severity = severity
    end
end

local hasCVTTransmission = RMS_Utils.hasCVTTransmission
local hasCVTAddon = RMS_Utils.hasCVTAddon


---Draws the whole HUD for the current frame
function RMS_Hud:draw()
    local isHudVisible = g_currentMission.hud.isVisible
    local isGuiVisible = g_gui:getIsGuiVisible()
    self:setNotificationInputActive(isHudVisible and not isGuiVisible and self:hasClosableNotification())

    if not isHudVisible then
        return
    end

    self:drawNotificationPanel()
    self:drawInspectionProgress()
    RMS_DebugWindow.draw(self.vehicle)

    if self.vehicle ~= nil then
        self:drawDashboard()
        self:drawTelemetryCards()
    end
end


---Shows a notification on the shared HUD instance
-- @param string text notification text
-- @param float? durationMs display duration in ms, absent for a persistent one
-- @param string? title notification title
-- @param boolean? playSound true to play the notification sound
function RMS_Hud.showNotification(text, durationMs, title, playSound)
    if RMS_Main.hud ~= nil then
        RMS_Main.hud:setNotification(text, durationMs, title, playSound)
    end
end

---Sets the inspection progress on the shared HUD instance
-- @param float? ratio progress between 0 and 1
function RMS_Hud.showInspectionProgress(ratio)
    if RMS_Main.hud ~= nil then
        RMS_Main.hud:setInspectionProgress(ratio)
    end
end

---Shows a message where the inspection ring stood on the shared HUD instance
-- @param string text message shown
-- @param float durationMs time the message stays on screen
function RMS_Hud.showInspectionMessage(text, durationMs)
    if RMS_Main.hud ~= nil then
        RMS_Main.hud:setInspectionMessage(text, durationMs)
    end
end

---Stores the notification to draw and starts its timer
-- @param string text notification text
-- @param float? durationMs display duration in ms, absent for a persistent one
-- @param string? title notification title
-- @param boolean? playSound true to play the notification sound
function RMS_Hud:setNotification(text, durationMs, title, playSound)
    local panel = self.notificationPanel
    local normalizedText = tostring(text or ""):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    local normalizedTitle = tostring(title or ""):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    local parsedDurationMs = tonumber(durationMs)

    if normalizedText == "" then
        self:clearNotification()
        return
    end

    if normalizedTitle == "" then
        normalizedTitle = nil
    else
        normalizedTitle = utf8ToUpper(normalizedTitle)
    end

    panel.title = normalizedTitle
    panel.text = normalizedText
    panel.isPersistent = parsedDurationMs ~= nil and parsedDurationMs <= 0
    if panel.isPersistent then
        panel.endTime = nil
    else
        panel.endTime = g_time + math.max(parsedDurationMs or 3000, 0)
    end
    panel.isVisible = true

    if playSound then
        RMS_SoundManager.playSample(RMS_Main.samples.notification2D)
    end
end

---Clears the notification and its input binding
function RMS_Hud:clearNotification()
    local panel = self.notificationPanel
    panel.title = nil
    panel.text = nil
    panel.endTime = nil
    panel.isVisible = false
    panel.isPersistent = false
end

---Registers or drops the action closing a persistent notification
-- @param boolean isActive true to register it
function RMS_Hud:setNotificationInputActive(isActive)
    local inputBinding = g_inputBinding
    local contextName = isActive and inputBinding.currentContextName or nil

    if self.notificationCloseActionEventId ~= nil
        and (not isActive or self.notificationInputContextName ~= contextName) then
        inputBinding:beginActionEventsModification(self.notificationInputContextName)
        inputBinding:removeActionEvent(self.notificationCloseActionEventId)
        inputBinding:endActionEventsModification()

        self.notificationInputContextName = nil
        self.notificationCloseActionEventId = nil
    end

    if isActive and contextName ~= nil and self.notificationCloseActionEventId == nil then
        inputBinding:beginActionEventsModification(contextName)
        local _, eventId = inputBinding:registerActionEvent(
            InputAction.RMS_CLOSE_NOTIFICATION,
            self,
            self.onCloseNotificationInput,
            false,
            true,
            false,
            true,
            nil,
            false
        )
        inputBinding:setActionEventTextVisibility(eventId, false)
        inputBinding:endActionEventsModification()

        self.notificationInputContextName = contextName
        self.notificationCloseActionEventId = eventId
    end
end

---Closes the persistent notification on player input
function RMS_Hud:onCloseNotificationInput()
    self:closePersistentNotification()
end

---Tells whether a notification the player can close is shown
-- @return boolean hasClosable true when one is shown
function RMS_Hud:hasClosableNotification()
    local panel = self.notificationPanel

    return panel ~= nil and panel.isVisible and panel.isPersistent
end

---Closes the persistent notification
function RMS_Hud:closePersistentNotification()
    if not self:hasClosableNotification() then
        return false
    end

    self:clearNotification()

    return true
end

---Draws the divider line of the notification panel
-- @param float x x position
-- @param float y y position
-- @param float width divider width
-- @param float height divider height
-- @param table color rgba channels
function RMS_Hud:drawNotificationDivider(x, y, width, height, color)
    local snappedX, snappedY, snappedWidth, snappedHeight = self:snapScreenRect(x, y, width, height)
    drawFilledRect(
        snappedX,
        snappedY,
        snappedWidth,
        snappedHeight,
        color[1],
        color[2],
        color[3],
        color[4] or 1
    )
end

---Returns the input glyph closing the notification
-- @param float glyphWidth glyph width
-- @param float glyphHeight glyph height
-- @return table? glyph input glyph element
function RMS_Hud:getNotificationCloseGlyph(glyphWidth, glyphHeight)
    if self.notificationCloseGlyph == nil then
        self.notificationCloseGlyph = InputGlyphElement.new(g_inputDisplayManager, glyphWidth, glyphHeight)
        self.notificationCloseGlyph:setKeyboardGlyphColor(RMS_Hud.COLOR_GAME_GREEN, {0, 0, 0, 0.8})
        self.notificationCloseGlyph:setButtonGlyphColor(RMS_Hud.COLOR_GAME_GREEN)
    elseif self.notificationCloseGlyph.baseWidth ~= glyphWidth or self.notificationCloseGlyph.baseHeight ~= glyphHeight then
        self.notificationCloseGlyph:delete()
        self.notificationCloseGlyph = InputGlyphElement.new(g_inputDisplayManager, glyphWidth, glyphHeight)
        self.notificationCloseGlyph:setKeyboardGlyphColor(RMS_Hud.COLOR_GAME_GREEN, {0, 0, 0, 0.8})
        self.notificationCloseGlyph:setButtonGlyphColor(RMS_Hud.COLOR_GAME_GREEN)
        self.notificationCloseGlyphInputMode = nil
    end

    local inputMode = g_inputBinding:getInputHelpMode()
    if self.notificationCloseGlyphInputMode ~= inputMode then
        self.notificationCloseGlyph:setAction(InputAction.RMS_CLOSE_NOTIFICATION, nil, nil, true)
        self.notificationCloseGlyphInputMode = inputMode
    end

    return self.notificationCloseGlyph
end

---Snaps a rectangle to whole pixels
-- @param float x x position
-- @param float y y position
-- @param float width rectangle width
-- @param float height rectangle height
-- @return float x snapped x position
-- @return float y snapped y position
-- @return float width snapped width
-- @return float height snapped height
function RMS_Hud:snapScreenRect(x, y, width, height)
    local snappedX = math.floor(x * g_screenWidth + 0.5) / g_screenWidth
    local snappedY = math.floor(y * g_screenHeight + 0.5) / g_screenHeight
    local snappedWidth = math.max(math.floor(width * g_screenWidth + 0.5) / g_screenWidth, 1 / g_screenWidth)
    local snappedHeight = math.max(math.floor(height * g_screenHeight + 0.5) / g_screenHeight, 1 / g_screenHeight)

    return snappedX, snappedY, snappedWidth, snappedHeight
end

---Draws the rounded background of a panel
-- @param float x x position
-- @param float y y position
-- @param float width panel width
-- @param float height panel height
-- @param table color rgba channels
function RMS_Hud:drawPanelBackground(x, y, width, height, color)
    if width <= 0 or height <= 0 then
        return
    end

    local panelColor = color or {0, 0, 0, 0.7}
    local panelX, panelY, panelWidth, panelHeight = self:snapScreenRect(x, y, width, height)
    drawFilledRectRound(
        panelX,
        panelY,
        panelWidth,
        panelHeight,
        0.25,
        panelColor[1],
        panelColor[2],
        panelColor[3],
        panelColor[4] or 1
    )
end

---Stores the progress the inspection ring draws, absent to hide it
-- @param float? ratio progress between 0 and 1
function RMS_Hud:setInspectionProgress(ratio)
    local progress = self.inspectionProgress
    progress.ratio = ratio ~= nil and math.clamp(ratio, 0, 1) or nil

    if progress.ratio ~= nil then
        progress.messageText = nil
    end
end

---Stores the message shown where the inspection ring stood
-- @param string text message shown
-- @param float durationMs time the message stays on screen
function RMS_Hud:setInspectionMessage(text, durationMs)
    local progress = self.inspectionProgress
    progress.messageText = text
    progress.messageEndTime = g_time + durationMs
end

---Draws the inspection progress as a ring filling up around its percentage
function RMS_Hud:drawInspectionProgress()
    local progress = self.inspectionProgress
    local ratio = progress.ratio
    local centerX, centerY = 0.5, 0.46

    if ratio == nil then
        if progress.messageText ~= nil and g_time < progress.messageEndTime then
            setTextAlignment(RenderText.ALIGN_CENTER)
            setTextBold(true)
            setTextColor(1, 1, 1, 1)
            renderText(centerX, centerY, self:scalePixelToScreenHeight(RMS_Hud.INSPECTION_LABEL_SIZE), progress.messageText)
            setTextBold(false)
            setTextAlignment(RenderText.ALIGN_LEFT)
        end

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
    local labelSize = self:scalePixelToScreenHeight(RMS_Hud.INSPECTION_LABEL_SIZE)
    setTextAlignment(RenderText.ALIGN_CENTER)
    setTextBold(true)
    setTextColor(1, 1, 1, 1)
    renderText(centerX, centerY - percentSize * 0.4, percentSize, string.format("%d%%", math.floor(ratio * 100 + 1e-6)))
    renderText(centerX, centerY + ringHeight * 0.5 + labelSize * 0.6, labelSize, g_i18n:getText("rms_field_inspection_progress"))
    setTextBold(false)

    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextColor(1, 1, 1, 1)
end

---Draws the notification panel and its text
function RMS_Hud:drawNotificationPanel()
    local panel = self.notificationPanel
    if panel == nil or not panel.isVisible or panel.text == nil then
        return
    end

    if panel.endTime ~= nil and g_time >= panel.endTime then
        self:clearNotification()
        return
    end

    local panelWidth = self:scalePixelToScreenWidth(640)
    local panelX = 0.5 - panelWidth * 0.5
    local panelY = g_hudAnchorBottom
    local paddingX = self:scalePixelToScreenWidth(20)
    local paddingY = self:scalePixelToScreenHeight(20)
    local maxTextWidth = panelWidth - paddingX * 2
    local titleTextSize = self:scalePixelToScreenHeight(19)
    local textSize = self:scalePixelToScreenHeight(17)
    local titleSpacing = self:scalePixelToScreenHeight(10)
    local sectionSpacing = self:scalePixelToScreenHeight(15)
    local dividerHeight = self:scalePixelToScreenHeight(1)
    local closeRowHeight = self:scalePixelToScreenHeight(30)
    local hasTitle = panel.title ~= nil
    local closeGlyphVisible = panel.isPersistent and hasTitle
    local closeGlyphWidth = closeGlyphVisible and self:scalePixelToScreenWidth(panel.closeGlyphSize or 18) or 0
    local closeGlyphHeight = closeGlyphVisible and self:scalePixelToScreenHeight(panel.closeGlyphSize or 18) or 0

    setTextAlignment(RenderText.ALIGN_CENTER)
    setTextVerticalAlignment(RenderText.VERTICAL_ALIGN_TOP)
    setTextWrapWidth(maxTextWidth)

    local titleHeight = 0
    if hasTitle then
        setTextBold(true)
        titleHeight = getTextHeight(titleTextSize, panel.title)
    end

    setTextBold(false)
    local textHeight = getTextHeight(textSize, panel.text)
    local titleSectionHeight = hasTitle and (titleHeight + titleSpacing * 2 + dividerHeight) or 0
    local closeSectionHeight = hasTitle and (sectionSpacing + dividerHeight + (closeGlyphVisible and closeRowHeight or 0)) or 0
    local dynamicHeight = paddingY * 2 + titleSectionHeight + textHeight + closeSectionHeight

    self:drawPanelBackground(
        panelX,
        panelY,
        panelWidth,
        dynamicHeight,
        HUD.COLOR.BACKGROUND_DARK
    )

    local centerX = 0.5
    local dividerWidth = panelWidth - paddingX * 2
    local currentY = panelY + dynamicHeight - paddingY

    if hasTitle then
        setTextBold(true)
        setTextColor(unpack(RMS_Hud.COLOR_GAME_GREEN))
        renderText(centerX, currentY, titleTextSize, panel.title)
        currentY = currentY - titleHeight - titleSpacing

        self:drawNotificationDivider(panelX + paddingX, currentY - dividerHeight, dividerWidth, dividerHeight, RMS_Hud.COLOR_GAME_GREEN)
        currentY = currentY - dividerHeight - titleSpacing
    end

    setTextBold(false)
    setTextColor(1, 1, 1, 1)
    renderText(centerX, currentY, textSize, panel.text)
    currentY = currentY - textHeight
    setTextWrapWidth(0)

    if hasTitle then
        currentY = currentY - sectionSpacing
        self:drawNotificationDivider(panelX + paddingX, currentY - dividerHeight, dividerWidth, dividerHeight, RMS_Hud.COLOR_GAME_GREEN)

        if closeGlyphVisible then
            local glyph = self:getNotificationCloseGlyph(closeGlyphWidth, closeGlyphHeight)
            if glyph ~= nil then
                local glyphWidth = glyph:getGlyphWidth()
                local okText = "OK"
                local okTextSize = textSize
                local textSpacing = self:scalePixelToScreenWidth(panel.closeGlyphTextSpacing or 6)
                local okTextWidth = getTextWidth(okTextSize, okText)
                local glyphX = centerX - (glyphWidth + textSpacing + okTextWidth) * 0.5
                local glyphY = panelY + paddingY + (closeRowHeight - closeGlyphHeight) * 0.5
                glyph:setPosition(glyphX, glyphY)
                glyph:draw()

                setTextAlignment(RenderText.ALIGN_LEFT)
                setTextVerticalAlignment(RenderText.VERTICAL_ALIGN_MIDDLE)
                setTextBold(true)
                setTextColor(1, 1, 1, 0.95)
                renderText(glyphX + glyphWidth + textSpacing - self:scalePixelToScreenWidth(4), glyphY + closeGlyphHeight * 0.5 + self:scalePixelToScreenHeight(2), okTextSize, okText)
            end
        end
    end

    setTextBold(false)
    setTextColor(1, 1, 1, 1)
    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextVerticalAlignment(RenderText.VERTICAL_ALIGN_BOTTOM)
end


---Recomputes every HUD size and position for the current screen resolution
function RMS_Hud:storeScaledValues()
    local function pixelSize(width, height)
        width, height = self:scalePixelValuesToScreenVector(width, height)
        return math.max(math.floor(width * g_screenWidth + 0.5), 1) / g_screenWidth,
            math.max(math.floor(height * g_screenHeight + 0.5), 1) / g_screenHeight
    end

    local lamp = RMS_Hud.LAMP
    for _, indicator in pairs(self.indicators) do
        for _, icon in pairs(indicator.icons or { indicator.icon }) do
            local size = lamp.SIZE * self.lampScales[icon]
            icon:setDimension(pixelSize(size, size))
        end
    end
    self.indicatorValueText.size = self:scalePixelToScreenHeight(lamp.VALUE_SIZE)

    local speedMeter = g_currentMission.hud.speedMeter
    local serviceAnchorY = (speedMeter.gaugeTextOffsets[4].offsetY + speedMeter.gaugeTextOffsets[7].offsetY) * 0.5
    self.rowCenterY = serviceAnchorY - self:scalePixelToScreenHeight(10)
    -- The service anchor is the foot of an 11 px mark.
    self.indicators.service.centreY = serviceAnchorY + self:scalePixelToScreenHeight(5.5)

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
end

---Tells whether a vehicle carries a telltale
-- @param string indicatorId telltale name
-- @param integer? indicatorYear year the telltale appeared on dashboards
-- @param table spec vehicle RMS state
-- @param boolean hasEngineOil true when the vehicle holds engine oil
-- @return boolean isFitted true when the dashboard of this vehicle has it
function RMS_Hud.getIsTelltaleFitted(indicatorId, indicatorYear, spec, hasEngineOil)
    if indicatorId == "preheat" then
        return spec.isDieselVehicle == true
    elseif indicatorId == "dpf" then
        return spec.hasParticulateFilter == true
    elseif indicatorId == "tractionBattery" or indicatorId == "limitedPower" then
        return spec.isElectricVehicle == true
    elseif indicatorId == "fanReversal" then
        return spec.hasReversibleFan == true
    elseif indicatorId == "oil" and not hasEngineOil then
        return false
    end
    return indicatorYear <= spec.year
end

-- @param table spec vehicle RMS state
-- @return boolean isCalling true from the regeneration level while no regeneration runs
function RMS_Hud.getIsParticulateFilterCalling(spec)
    return spec.fuelState.particulateFilterLevel >= 1 and not spec.fuelState.isParticulateFilterRegenerating
end

---Returns the offset putting a row lamp's ink bottom on the warning's
-- @param string slice slice of the lamp
-- @return float lift reference px, negative downward
function RMS_Hud.getRowLampLift(slice)
    local lamp = RMS_Hud.LAMP
    local function foot(name)
        return (RMS_Hud.LAMP_INK[name][3] - lamp.CELL * 0.5) * lamp.SIZE * (RMS_Hud.LAMP_SCALE[name] or 1) / lamp.CELL
    end
    return foot("warning") - foot(slice)
end

---Returns the road or machine slice replacing the tractor one
-- @param string id lamp id
-- @param boolean isRoadVehicle true for a car or a truck
-- @param boolean isMachine true for a loader, a forklift or a forestry machine
-- @return string? sliceName nil for the tractor's
function RMS_Hud.getFamilyLampSlice(id, isRoadVehicle, isMachine)
    if isRoadVehicle then
        return RMS_Hud.ROAD_LAMP_SLICE[id]
    elseif isMachine then
        return RMS_Hud.MACHINE_LAMP_SLICE[id]
    end
    return nil
end

---Returns the picture the motor telltale takes
-- @param table spec vehicle RMS state
-- @param boolean isRoadVehicle true for a car or a truck
-- @param boolean isFaultShown lamp test or active fault telltale
-- @return string iconKey classic, fault or normal
function RMS_Hud.getEngineTelltaleIconKey(spec, isRoadVehicle, isFaultShown)
    if isRoadVehicle or spec.isElectricVehicle then
        return "classic"
    elseif isFaultShown then
        return "fault"
    end
    return "normal"
end

---Tells whether the level of the engine oil lights the oil lamp
-- @param table spec vehicle RMS state
-- @return boolean isLow true when the engine oil is critically low
function RMS_Hud.getIsOilPressureLow(spec)
    return (tonumber(spec.engineOilLevel) or 1) <= RMS_Config.FLUIDS.LEVEL_CRITICALLY_LOW
end

---Returns the coolant lamp colour key for the drive temperature
-- @param table spec vehicle RMS state
-- @return string? colorKey WARNING, CRITICAL, or nil when unlit
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

---Builds the figures drawn beside the telltales
-- @param table spec vehicle RMS state
-- @param float motorLoad averaged motor load from 0 to 1
-- @param boolean showTransmissionTemperature gearbox temperature available
-- @param boolean useFahrenheit true to show temperatures in Fahrenheit
-- @return table values readout text and isWarning by telltale name
function RMS_Hud.getGaugeValues(spec, motorLoad, showTransmissionTemperature, useFahrenheit)
    local engineTemp, transTemp, tempSign = spec.engineTemperature, spec.transmissionTemperature, "°C"
    if useFahrenheit then
        engineTemp = engineTemp * 1.8 + 32
        transTemp = transTemp * 1.8 + 32
        tempSign = "°F"
    end

    local overloadThreshold = spec.isElectricVehicle and RMS_Config.ELECTRIC_DRIVE.MOTOR_OVERLOADED_THRESHOLD
        or RMS_Config.CORE.ENGINE_FACTOR_DATA.MOTOR_OVERLOADED_THRESHOLD
    local overloadLoad = motorLoad
    if not spec.isElectricVehicle and motorLoad > 0 then
        overloadLoad = tonumber(spec.dynamicMotorLoad) or motorLoad
    end
    local values = {
        coolant = { text = string.format("%.0f%s", engineTemp, tempSign) },
        engine = { text = string.format("%.0f%%", math.max(motorLoad * 100, 0)), isWarning = overloadLoad > overloadThreshold },
        battery = { text = formatValue(spec.batteryIsolated and 0 or spec.systemVoltageV, "%.1f") .. "V" }
    }
    if showTransmissionTemperature then
        values.transmission = { text = string.format("%.0f%s", transTemp, tempSign) }
    end
    return values
end

---Draws the dashboard indicators, the gauges and the vehicle condition
function RMS_Hud:drawDashboard()
    if self.vehicle == nil or self.vehicle.spec_RealisticMechanicalSystems == nil or self.vehicle.spec_RealisticMechanicalSystems.isExcludedVehicle then
        return
    end

    local vehicle = self.vehicle
    local spec = vehicle.spec_RealisticMechanicalSystems
    RMS_Thermal.getEngineTemperature(vehicle)
    local colors = RMS_Breakdowns.COLORS
    local activeIndicators = spec.activeIndicators
    local isServiceOverdue = self.vehicle:getServiceLevel() < RMS_Config.CORE.SERVICE_EXPIRED_THRESHOLD
    local motorState = vehicle:getMotorState()
    local preheatState = spec.preheatState or RMS_Preheat.STATE.IDLE
    local isLampTestActive = RMS_Preheat.isLampTestActive(vehicle)
    local isRoadVehicle = RMS_Drivetrain.getIsRoadVehicleCategory(vehicle)
    local isMachine = RMS_Drivetrain.getIsMachineCategory(vehicle)
    local cvtAddonSpec = hasCVTAddon(vehicle) and vehicle.spec_CVTaddon or nil
    local hasCVTFaultWarning = cvtAddonSpec ~= nil
        and (cvtAddonSpec.forDBL_warndamage == 1
            or cvtAddonSpec.forDBL_critdamage == 1
            or cvtAddonSpec.forDBL_highpressure == 1)
    local hasCVTCriticalFault = cvtAddonSpec ~= nil
        and cvtAddonSpec.forDBL_critdamage == 1

    local transmissionFaultColor = colors.DEFAULT

    ---Returns the colour an indicator lights in, the highest priority winning
    local function calculateIndicatorTargetColor(hudIndicatorId, mutateActiveState)
        local targetColor = colors.DEFAULT
        local isRoutineIgnitionIndicator = false

        if motorState ~= MotorState.OFF then
            local activeData = activeIndicators[hudIndicatorId]
            if activeData then
                local isActive = activeData.isActive
                local shouldBeOn = activeData.switchOn(vehicle)
                local shouldBeOff = activeData.switchOff(vehicle)

                if isActive and not shouldBeOff then
                    targetColor = activeData.color
                elseif shouldBeOn and not shouldBeOff then
                    if mutateActiveState then
                        activeData.isActive = true
                    end
                    targetColor = activeData.color
                elseif shouldBeOff and mutateActiveState then
                    activeData.isActive = false
                end
            end

            if hudIndicatorId == self.indicators.transmission.name then
                -- A gearbox fault lights the warning, not the gearbox lamp.
                transmissionFaultColor = targetColor
                if hasCVTCriticalFault then
                    transmissionFaultColor = colors.CRITICAL
                elseif transmissionFaultColor == colors.DEFAULT and hasCVTFaultWarning then
                    transmissionFaultColor = colors.WARNING
                end
                targetColor = colors.DEFAULT
            end
            if hudIndicatorId == self.indicators.warning.name and transmissionFaultColor ~= colors.DEFAULT
                    and (targetColor == colors.DEFAULT or transmissionFaultColor == colors.CRITICAL) then
                targetColor = transmissionFaultColor
            end
            if hudIndicatorId == self.indicators.fanReversal.name and (tonumber(spec.fanReversalTime) or 0) > 0 then
                targetColor = RMS_Hud.COLOR_GAME_GREEN
                isRoutineIgnitionIndicator = true
            end

            if hudIndicatorId == self.indicators.coolant.name then
                local coolantState = RMS_Hud.getCoolantTelltaleState(spec)
                if coolantState == "CRITICAL" or (coolantState ~= nil and targetColor == colors.DEFAULT) then
                    targetColor = colors[coolantState]
                end
            end
            if hudIndicatorId == self.indicators.transmission.name
                    and targetColor == colors.DEFAULT
                    and spec.transmissionTemperature > RMS_Hud.TRANSMISSION_OIL_TEMP_WARNING
                    and spec.transmissionTemperature < 110 then
                targetColor = colors.WARNING
            elseif hudIndicatorId == self.indicators.transmission.name and spec.transmissionTemperature >= 110 then targetColor = colors.CRITICAL end

            if hudIndicatorId == self.indicators.service.name and isServiceOverdue then targetColor = colors.WARNING end
            if hudIndicatorId == self.indicators.oil.name and RMS_Hud.getIsOilPressureLow(spec) then
                targetColor = colors.CRITICAL
            end

            if hudIndicatorId == self.indicators.dpf.name and targetColor == colors.DEFAULT then
                if spec.fuelState.isParticulateFilterRegenerating then
                    targetColor = colors.WARNING
                    isRoutineIgnitionIndicator = true
                elseif RMS_Hud.getIsParticulateFilterCalling(spec) then
                    targetColor = colors.WARNING
                end
            end

            if isLampTestActive then
                targetColor = colors.WARNING
                isRoutineIgnitionIndicator = true
            elseif hudIndicatorId == self.indicators.preheat.name
                    and preheatState == RMS_Preheat.STATE.PREHEATING
                    and targetColor == colors.DEFAULT then
                targetColor = colors.WARNING
                isRoutineIgnitionIndicator = true
            elseif (motorState == MotorState.IGNITION or motorState == MotorState.STARTING)
                    and (hudIndicatorId == self.indicators.battery.name or hudIndicatorId == self.indicators.oil.name)
                    and targetColor == colors.DEFAULT then
                targetColor = colors.WARNING
                isRoutineIgnitionIndicator = true
            end
        else
            local activeData = activeIndicators[hudIndicatorId]
            if activeData and mutateActiveState then
                activeData.isActive = false
            end
        end

        return targetColor, isRoutineIgnitionIndicator
    end

    g_currentMission.hud.speedMeter.speedTextSize = self:scalePixelToScreenHeight(43)
    local speedBgX, speedBgY = g_currentMission.hud.speedMeter.speedBg:getPosition()
    local posX = speedBgX + g_currentMission.hud.speedMeter.speedGaugeCenterOffsetX
    local posY = speedBgY + g_currentMission.hud.speedMeter.speedGaugeCenterOffsetY
    local hasTransmissionOilTempDisplay = hasCVTTransmission(vehicle) or cvtAddonSpec ~= nil
    local hasEngineOil = RMS_Fluids.getCapacity(vehicle, "engineOil") > 0
    local lamp = RMS_Hud.LAMP

    local units, unitsById = {}, {}
    for _, id in ipairs(RMS_Hud.ARC_ORDER) do
        if RMS_Hud.getIsTelltaleFitted(id, self.indicators[id].year, spec, hasEngineOil) then
            local inkKey = RMS_Hud.getFamilyLampSlice(id, isRoadVehicle, isMachine) or RMS_Hud.LAMP_SLICE[id] or id
            if id == "engine" and RMS_Hud.getEngineTelltaleIconKey(spec, isRoadVehicle, false) == "classic" then
                inkKey = "engineClassic"
            end
            local ink = RMS_Hud.LAMP_INK[inkKey]
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
        if RMS_Hud.getIsTelltaleFitted(id, self.indicators[id].year, spec, hasEngineOil) then
            rowIds[#rowIds + 1] = id
        end
    end
    local rowPlaces = {}
    for index, x in ipairs(RMS_Hud.getRowLayout(#rowIds)) do
        rowPlaces[rowIds[index]] = x
    end

    local lamps = {}
    for _, hudIndicatorId in ipairs(RMS_Hud.INDICATOR_ORDER) do
        local hudIndicatorData = self.indicators[hudIndicatorId]
        local targetColor, isRoutineIgnitionIndicator = calculateIndicatorTargetColor(hudIndicatorId, true)
        local activeIndicatorData = activeIndicators[hudIndicatorId]
        local hasActiveBreakdown = activeIndicatorData ~= nil and activeIndicatorData.isActive == true
        local icon = hudIndicatorData.icon

        if hudIndicatorId == self.indicators.engine.name then
            icon = hudIndicatorData.icons[RMS_Hud.getEngineTelltaleIconKey(spec, isRoadVehicle, isLampTestActive or hasActiveBreakdown)]
        elseif hudIndicatorData.icons ~= nil then
            icon = hudIndicatorData.icons[RMS_Hud.getFamilyLampSlice(hudIndicatorId, isRoadVehicle, isMachine) or "normal"]
        end
        hudIndicatorData.icon = icon

        local isIndicatorVisible = RMS_Hud.getIsTelltaleFitted(hudIndicatorId, hudIndicatorData.year, spec, hasEngineOil)
        local place, unit = layout[hudIndicatorId], unitsById[hudIndicatorId]
        local centreX, centreY
        if place ~= nil then
            centreX = posX + self:scalePixelToScreenWidth(place.x)
            centreY = posY + self:scalePixelToScreenHeight(place.y)
        elseif rowPlaces[hudIndicatorId] ~= nil then
            local slice = RMS_Hud.getFamilyLampSlice(hudIndicatorId, isRoadVehicle, isMachine)
                or RMS_Hud.LAMP_SLICE[hudIndicatorId] or hudIndicatorId
            centreX = posX + self:scalePixelToScreenWidth(rowPlaces[hudIndicatorId])
            centreY = posY + self.rowCenterY + self:scalePixelToScreenHeight(RMS_Hud.getRowLampLift(slice))
        elseif hudIndicatorId == self.indicators.service.name then
            centreX, centreY = posX, posY + hudIndicatorData.centreY
        else
            isIndicatorVisible = false
        end
        if isIndicatorVisible then
            icon:setPosition(snapScreenX(centreX - icon.width * 0.5), snapScreenY(centreY - icon.height * 0.5))
        end
        icon:setVisible(isIndicatorVisible)

        local isAudibleIndicator = targetColor ~= colors.DEFAULT and targetColor ~= colors.COOL
        local shouldActivateIndicator = isIndicatorVisible and isAudibleIndicator and not isRoutineIgnitionIndicator
        self:syncIndicatorActivation(hudIndicatorId, shouldActivateIndicator, targetColor)

        local blinkWhileActive = (activeIndicatorData ~= nil and activeIndicatorData.blinkWhileActive == true)
            or (hudIndicatorId == self.indicators.dpf.name and targetColor == colors.WARNING and RMS_Hud.getIsParticulateFilterCalling(spec))
        local displayColor = isRoutineIgnitionIndicator and targetColor or self:applyIndicatorBlink(hudIndicatorId, targetColor, blinkWhileActive)
        if isIndicatorVisible then
            lamps[#lamps + 1] = { icon = icon, color = displayColor, x = centreX, y = centreY }
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

    local motorLoad = 0
    if vehicle:getIsMotorStarted() then
        motorLoad = self:updateMotorLoadAverage(math.clamp(tonumber(spec.dynamicMotorLoad) or 0, 0, 1))
    end
    self.telemetryDisplayValues.motorLoad = motorLoad

    local showTransmissionTemperatureText = hasTransmissionOilTempDisplay and unitsById.transmission ~= nil
    local gaugeValues = RMS_Hud.getGaugeValues(spec, motorLoad, showTransmissionTemperatureText,
        g_gameSettings:getValue(GameSettings.SETTING.USE_FAHRENHEIT))

    setTextAlignment(RenderText.ALIGN_CENTER)
    setTextVerticalAlignment(RenderText.VERTICAL_ALIGN_MIDDLE)
    setTextBold(true)

    local defaultTextColor = {1, 1, 1, 1}
    for _, indicatorName in ipairs({ "coolant", "transmission", "engine", "battery" }) do
        local gaugeValue = gaugeValues[indicatorName]
        local place, unit = layout[indicatorName], unitsById[indicatorName]
        if gaugeValue ~= nil and place ~= nil and unit.valueWidth ~= nil then
            local valueSize = self.indicatorValueText.size
            local valueWidth = getTextWidth(valueSize, gaugeValue.text)
            local maxWidth = self:scalePixelToScreenWidth(unit.valueWidth)
            if valueWidth > maxWidth then
                valueSize = valueSize * maxWidth / valueWidth
            end
            local valueTop = place.y - unit.inkHeight * 0.5 - lamp.VALUE_GAP

            local color = gaugeValue.isWarning and colors.WARNING or defaultTextColor
            setTextColor(color[1], color[2], color[3], color[4])
            renderText(snapScreenX(posX + self:scalePixelToScreenWidth(place.x)),
                snapScreenY(posY + self:scalePixelToScreenHeight(valueTop - lamp.VALUE_TOP)), valueSize, gaugeValue.text)
        end
    end
    setTextColor(1, 1, 1, 1)

    self:drawDrivetrainDisplay(vehicle, posX, posY)
    if not isRoadVehicle then
        self:drawWheelSlipDisplay(spec, posX, posY)
    end
    self:drawParkBrakeDisplay(vehicle)
    self:drawOdometer()

    setTextVerticalAlignment(RenderText.VERTICAL_ALIGN_BOTTOM)
    setTextBold(false)
end

---Draws the half-moon: background, lamp cells, coolant gauge
-- @param float posX x of the gauge centre, screen
-- @param float posY y of the gauge centre
-- @param table units lamps of the column, in order
-- @param table layout their places, by lamp id
-- @param table spec vehicle RMS state
-- @param boolean isPowered ignition on
-- @param boolean hasHigh drive bubble drawn above
-- @param boolean hasLow wheel slip bubble drawn below
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
-- @param table overlay overlay of the atlas
-- @param string sliceId slice of the picture
-- @param table box reference px the slice covers, from the point it turns about: x0, y0, x1, y1
-- @param table extent reference px of the picture itself, same frame
-- @param float x screen x of the point
-- @param float y screen y of the point
-- @param float angle radians, anticlockwise
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
-- @param float posX x of the gauge centre, screen
-- @param float posY y of the gauge centre
-- @param table spec vehicle RMS state
-- @param boolean isPowered ignition on
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
    setTextBold(true)
    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextVerticalAlignment(RenderText.VERTICAL_ALIGN_BOTTOM)

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

---Draws a bubble beside the half-moon and places what it holds
-- @param boolean isHigh front axle above, wheel slip below
-- @param float posX x of the gauge centre, screen
-- @param float posY y of the gauge centre
-- @param float inkHeight ink height of the symbol it holds
-- @return float symbolY y of the symbol centre
-- @return float valueY y of the value text
-- @return float centreX x of the bubble centre
local function drawBubble(self, isHigh, posX, posY, inkHeight)
    local bubbleX, bubbleY = RMS_Hud.getBubbleCentre(isHigh)
    local centreX = posX + self:scalePixelToScreenWidth(bubbleX)
    local centreY = posY + self:scalePixelToScreenHeight(bubbleY)
    self.bubble:setPosition(snapScreenX(centreX - self.bubble.width * 0.5), snapScreenY(centreY - self.bubble.height * 0.5))
    self.bubble:render()

    local symbolY, valueY = RMS_Hud.getBubbleContent(inkHeight)
    return centreY + self:scalePixelToScreenHeight(symbolY), centreY + self:scalePixelToScreenHeight(valueY), centreX
end

---Writes the value of a bubble under its symbol
local function drawBubbleValue(self, centreX, valueY, text, color)
    setTextAlignment(RenderText.ALIGN_CENTER)
    setTextVerticalAlignment(RenderText.VERTICAL_ALIGN_MIDDLE)
    setTextBold(true)
    setTextColor(color[1], color[2], color[3], color[4])
    renderText(snapScreenX(centreX), snapScreenY(valueY), self.bubbleValueSize, text)
    setTextColor(1, 1, 1, 1)
end

---Draws the wheel slip in its bubble below the left of the dial
-- @param table spec vehicle spec
-- @param float posX x of the gauge centre, screen
-- @param float posY y of the gauge centre
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

-- @param table state drivetrain state
-- @param boolean hasFrontAxleSwitch true when the front axle drive can be switched
-- @param float time game time in ms
-- @return string iconId picture shown
-- @return table color its color
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

-- @param table vehicle vehicle
-- @param float posX x of the gauge centre, screen
-- @param float posY y of the gauge centre
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
-- @param table vehicle vehicle
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

---Returns the widest steering assist work area of the whole combination
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

---Returns the fuel consumption per worked area
-- @return float? rate consumption per hectare
function RMS_Hud:getConsumptionAreaRate()
    local vehicle = self.vehicle
    if vehicle == nil then
        return 0, 0
    end

    local speed = vehicle.getLastSpeed ~= nil and (tonumber(vehicle:getLastSpeed()) or 0) or 0
    local width = vehicle.getAttacherToolWorkingWidth ~= nil and (tonumber(vehicle:getAttacherToolWorkingWidth()) or 0) or 0

    if width <= 0 then
        width = getSteeringAssistWidth(vehicle)
    end

    local guidanceSpec = vehicle.spec_globalPositioningSystem
    if guidanceSpec ~= nil and guidanceSpec.guidanceData ~= nil and guidanceSpec.guidanceData.width ~= nil then
        width = tonumber(guidanceSpec.guidanceData.width) or width
    end

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
-- @param float consumptionPerHour consumption in units per hour
-- @param float areaRate worked area rate in hectares per hour
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
-- @param float motorLoad current engine load between 0 and 1
-- @return float average averaged engine load
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

---Draws the fuel consumption card
-- @param float cardRightX right edge of the card
function RMS_Hud:drawFuelConsumption(cardRightX)
    local vehicle = self.vehicle
    if vehicle == nil or vehicle.spec_RealisticMechanicalSystems == nil or vehicle.spec_motorized == nil then
        return
    end

    local _, fuelCapacity, fuelType = SpeedMeterDisplay.getVehicleFuelLevelAndCapacity(vehicle)
    if fuelCapacity == nil or fuelCapacity <= 0 then
        return
    end

    local motorizedSpec = vehicle.spec_motorized
    local consumptionPerHour = 0
    if vehicle:getIsMotorStarted() then
        consumptionPerHour = math.max(tonumber(motorizedSpec.lastFuelUsageDisplay or motorizedSpec.lastFuelUsage) or 0, 0)
    end

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

    local separatorLineW = 1 / g_screenWidth
    local separatorLineH = panelH * 0.55
    local separatorLineX = textX + perHourWidth + separatorGap * 0.5 - separatorLineW * 0.5
    local separatorLineY = panelY + (panelH - separatorLineH) * 0.5
    self:drawNotificationDivider(separatorLineX, separatorLineY, separatorLineW, separatorLineH, green)

    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextVerticalAlignment(RenderText.VERTICAL_ALIGN_MIDDLE)
    setTextBold(true)
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

    setTextColor(1, 1, 1, 1)
    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextVerticalAlignment(RenderText.VERTICAL_ALIGN_BOTTOM)
end


---Returns the colour of a load severity
-- @param integer severity load severity
-- @return table color rgba channels
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
-- @param float massTons mass in tons
-- @return string text formatted mass
function RMS_Hud:formatMass(massTons)
    return formatValue(math.max(tonumber(massTons) or 0, 0), "%.1f") .. " t"
end

---Returns a mass that only changes past a threshold
-- @param string cacheKey key the mass is cached under
-- @param float massTons mass in tons
-- @return float mass stable mass
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
-- @param float cardRightX right edge of the card
function RMS_Hud:drawLoadMass(cardRightX)
    local vehicle = self.vehicle
    if vehicle == nil or vehicle.getTotalMass == nil then
        return cardRightX
    end

    local spec = vehicle.spec_RealisticMechanicalSystems
    if spec == nil then
        return cardRightX
    end

    local speedMeter = g_currentMission.hud.speedMeter
    if speedMeter == nil or speedMeter.speedBg == nil then
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

    local sepLineW = 1 / g_screenWidth
    local sepLineH = panelH * 0.55
    local sepLineY = panelY + (panelH - sepLineH) * 0.5
    local green    = HUD.COLOR.ACTIVE
    self:drawNotificationDivider(startX + w1 + wsep * 0.5 - sepLineW * 0.5,             sepLineY, sepLineW, sepLineH, green)
    self:drawNotificationDivider(startX + w1 + wsep + w2 + wsep * 0.5 - sepLineW * 0.5, sepLineY, sepLineW, sepLineH, green)

    local cx = startX
    local dimLabel = {1, 1, 1, 0.55}

    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextVerticalAlignment(RenderText.VERTICAL_ALIGN_MIDDLE)

    setTextBold(false)
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

    setTextBold(false)
    setTextColor(1, 1, 1, 1)
    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextVerticalAlignment(RenderText.VERTICAL_ALIGN_BOTTOM)

    return panelX - (self.telemetryCardGap or 0)
end


local INSPECTED_DAMAGE_CEILING = 0.9

local TIER_DAMAGE_AMOUNTS = {0.0, 0.25, 0.5, 0.75, INSPECTED_DAMAGE_CEILING}

local originalSpeedMeterDisplayDraw = SpeedMeterDisplay.draw
SpeedMeterDisplay.draw = function(self, ...)
    local vehicle = self.vehicle
    if vehicle == nil or not self.isVehicleDrawSafe or vehicle.rootVehicle == nil then
        return originalSpeedMeterDisplayDraw(self, ...)
    end

    local spec = vehicle.spec_RealisticMechanicalSystems
    if spec ~= nil and spec.isExcludedVehicle then
        return originalSpeedMeterDisplayDraw(self, ...)
    end

    local selectedTool = nil
    local useCustomValue = false
    local customDamageAmount = 0

    for _, implement in ipairs(vehicle.rootVehicle.childVehicles) do
        if implement:getIsSelected() and implement.getDamageShowOnHud ~= nil and implement:getDamageShowOnHud() then
            selectedTool = implement
            break
        end
    end

    if selectedTool ~= nil then
        useCustomValue = true
        if selectedTool.getServiceLevel ~= nil then
            local condition, isCompleteInspection = vehicle:getLastInspectedCondition()
            condition = math.clamp(condition or 0, 0, 1)
            if isCompleteInspection == nil then
                customDamageAmount = 1.0
            elseif isCompleteInspection then
                customDamageAmount = math.min(1 - condition, INSPECTED_DAMAGE_CEILING)
            else
                customDamageAmount = TIER_DAMAGE_AMOUNTS[RMS_Utils.getConditionTier(condition)]
            end
        else
            customDamageAmount = selectedTool:getDamageAmount()
        end
    end

    local originalGetDamageMethods = {}
    if useCustomValue then
        local allVehicles = vehicle.rootVehicle.childVehicles
        
        for _, v in ipairs(allVehicles) do
            if v.getDamageAmount ~= nil then
                originalGetDamageMethods[v] = v.getDamageAmount
                v.getDamageAmount = function()
                    return customDamageAmount
                end
            end
        end
    end

    local result = originalSpeedMeterDisplayDraw(self, ...)

    if useCustomValue then
        for vehicleInstance, originalMethod in pairs(originalGetDamageMethods) do
            vehicleInstance.getDamageAmount = originalMethod
        end
    end

    return result
end


---Adds the RMS lines to the vanilla vehicle info box
-- @param table box info box
function RMS_Hud:showInfoVehicle(box)
    if self.spec_RealisticMechanicalSystems ~= nil and not self.spec_RealisticMechanicalSystems.isExcludedVehicle then
        local spec = self.spec_RealisticMechanicalSystems
        
        local schedule = self:getServiceSchedule()
        local _, isReportOutdated = self:getInspectionReportAge()
        box:addLine(g_i18n:getText('rms_ws_label_condition'), RMS_Utils.formatCondition(self:getLastInspectedCondition()), isReportOutdated)
        if schedule ~= nil then
            -- Native info-box rows cannot resize text.
            local hasHours = schedule.interval < math.huge
            local deadline = hasHours and RMS_Utils.formatHours(math.max(schedule.interval - schedule.used, 0))
                or RMS_Utils.formatMonths(schedule.remainingMonths)
            box:addLine(RMS_Utils.formatMaintenanceLevel(self, schedule.maintenanceType), deadline, schedule.overdue)
            if hasHours and schedule.months ~= nil then
                box:addLine(RMS_Utils.formatServiceReason(self, schedule, true), RMS_Utils.formatMonths(schedule.remainingMonths), schedule.calendarDue)
            end
        end

        if spec.batteryIsolated then
            box:addLine(g_i18n:getText("rms_battery_isolator_info"), nil, true)
        end

        
        if spec.currentState ~= RealisticMechanicalSystems.STATUS.READY and spec.currentState ~= RealisticMechanicalSystems.STATUS.BROKEN then
            local maintenanceStatusText = string.format(
                g_i18n:getText("rms_spec_last_maintenance_until_format"),
                RMS_Utils.formatServiceState(spec.currentState),
                RMS_Utils.formatFinishTime(self:getServiceFinishTime())
            )
            box:addLine(maintenanceStatusText)
        end
    end
end

Vehicle.showInfo = Utils.appendedFunction(Vehicle.showInfo, RMS_Hud.showInfoVehicle)
