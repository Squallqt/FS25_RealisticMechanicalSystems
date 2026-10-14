-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---Debug HUD pages, showing the live simulation values of the active vehicle

local hasCVTTransmission = RMS_Utils.hasCVTTransmission
local hasCVTAddon = RMS_Utils.hasCVTAddon

---Builds the motor telemetry lines
local function buildMotorTelemetryLines(vehicle, spec, motor, getStateValue, hasActiveCVTAddon)
    local values = {}
    values.availableTorque = tonumber(getStateValue(
        "motorAvailableTorque",
        motor.getMotorAvailableTorque ~= nil and motor:getMotorAvailableTorque() or 0
    )) or 0
    values.externalTorque = tonumber(getStateValue(
        "motorExternalTorque",
        motor.getMotorExternalTorque ~= nil and motor:getMotorExternalTorque() or 0
    )) or 0
    values.motorRotSpeed = tonumber(getStateValue(
        "motorRotSpeed",
        motor.getMotorRotSpeed ~= nil and motor:getMotorRotSpeed() or 0
    )) or 0
    values.motorPower = values.motorRotSpeed * (values.availableTorque - values.externalTorque) * 1000
    values.peakPowerHp = (tonumber(getStateValue("peakMotorPower", motor.peakMotorPower)) or 0) * 1.36
    values.lastRpm = tonumber(getStateValue(
        "lastModulatedMotorRpm",
        motor.getLastModulatedMotorRpm ~= nil and motor:getLastModulatedMotorRpm() or 0
    )) or 0
    values.maxRpm = math.max(tonumber(getStateValue("maxMotorRpm", motor.maxRpm)) or 1, 1)
    values.rpmLoad = values.lastRpm / values.maxRpm
    values.motorLoad = tonumber(getStateValue(
        "motorLoad",
        vehicle.getMotorLoadPercentage ~= nil and vehicle:getMotorLoadPercentage() or 0
    )) or 0
    values.dynamicMotorLoad = tonumber(getStateValue("dynamicMotorLoad", spec.dynamicMotorLoad)) or values.motorLoad
    values.currentSpeed = tonumber(getStateValue(
        "currentSpeedKmh",
        vehicle.getLastSpeed ~= nil and vehicle:getLastSpeed() or 0
    )) or 0
    values.avgAbsDiffAcc = tonumber(getStateValue("avgAbsDiffAcc", spec.avgAbsDiffAcc)) or 0
    values.currentGear = tonumber(getStateValue("currentGear", motor.gear)) or 0
    values.draftMaxForce = tonumber(getStateValue("activeDraftMaxForce", spec.activeDraftMaxForce)) or 0
    values.draftEffectiveForceCap = tonumber(getStateValue("activeDraftEffectiveForceCap", spec.activeDraftEffectiveForceCap)) or 0
    values.effectiveCapPerHp = values.peakPowerHp > 0 and (values.draftEffectiveForceCap / values.peakPowerHp) or 0

    local lines = {
        {
            text = string.format(
                "sp: %.1f km/h | hp: %.0f/%.0f | ml/dml: %.0f%%/%.0f%% | diff acc avg: %.2f | rpm: %.0f%%",
                values.currentSpeed,
                values.motorPower / 735.5,
                values.peakPowerHp,
                math.max(values.motorLoad * 100, 0),
                math.max(values.dynamicMotorLoad * 100, 0),
                values.avgAbsDiffAcc,
                math.max(values.rpmLoad * 100, 0)
            ),
            color = {1, 1, 1, 1},
            sizeScale = 0.95
        },
        {
            text = string.format(
                "g: %d | draft max/eff/per hp: %.2f/%.2f/%.2f",
                values.currentGear,
                values.draftMaxForce,
                values.draftEffectiveForceCap,
                values.effectiveCapPerHp
            ),
            color = {1, 1, 1, 1},
            sizeScale = 0.95
        }
    }

    if hasActiveCVTAddon then
        local cvtAddonSpec = vehicle.spec_CVTaddon or {}
        local cvtAddonDebug = getStateValue("cvtAddon", {
            damage = tonumber(cvtAddonSpec.CVTdamage) or 0,
            warnDamage = cvtAddonSpec.forDBL_warndamage == 1,
            critDamage = cvtAddonSpec.forDBL_critdamage == 1,
            warnHeat = cvtAddonSpec.forDBL_warnheat == 1,
            critHeat = cvtAddonSpec.forDBL_critheat == 1,
            highPressure = cvtAddonSpec.forDBL_highpressure == 1
        }) or {}
        table.insert(lines, {
            text = string.format(
                "CA: damage: %.6f%% | wd: %s, cd: %s | wh: %s, ch: %s | hp: %s",
                tonumber(cvtAddonDebug.damage) or 0,
                tostring(cvtAddonDebug.warnDamage == true),
                tostring(cvtAddonDebug.critDamage == true),
                tostring(cvtAddonDebug.warnHeat == true),
                tostring(cvtAddonDebug.critHeat == true),
                tostring(cvtAddonDebug.highPressure == true)
            ),
            color = {1, 0.92, 0.78, 1},
            sizeScale = 0.95
        })
    end

    return lines
end


---Draws the prebuilt debug lines of the active vehicle
-- @param table cache prebuilt debug lines
function RMS_Hud:renderActiveVehicleDebugCache(cache)
    if cache == nil then
        return
    end

    local panel = cache.panel
    if panel ~= nil then
        local color = panel.color or {0, 0, 0, 0.7}
        self:drawPanelBackground(
            panel.x,
            panel.y,
            panel.width,
            panel.height,
            color
        )
    end

    local commands = cache.commands
    if commands == nil or #commands == 0 then
        return
    end

    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextVerticalAlignment(RenderText.VERTICAL_ALIGN_TOP)

    local lastBold = nil
    for _, command in ipairs(commands) do
        local isBold = command.bold == true
        if lastBold ~= isBold then
            setTextBold(isBold)
            lastBold = isBold
        end

        local color = command.color or {1, 1, 1, 1}
        setTextColor(color[1], color[2], color[3], color[4] or 1)
        renderText(command.x, command.y, command.size, command.text or "")
    end

    if lastBold then
        setTextBold(false)
    end

    setTextColor(1, 1, 1, 1)
end

---Builds and draws the debug panel of the active vehicle
function RMS_Hud:drawActiveVehicleHUD()
    local vehicle = self.vehicle
    if vehicle == nil or vehicle.spec_RealisticMechanicalSystems == nil then
        return
    end
    local liveSpec = vehicle.spec_RealisticMechanicalSystems
    local spec = liveSpec
    local hydraulicFluidLevel = RMS_Fluids.getLevel(vehicle, "hydraulicFluid")
    local motor = vehicle:getMotor()
    if motor == nil then
        return
    end

    local panel = self.activeVehicleDebugPanel
    local debugSnapshot = nil
    RMS_DebugSnapshot.request(vehicle)
    if not vehicle.isServer then
        debugSnapshot = RMS_DebugSnapshot.get(vehicle)
        if debugSnapshot == nil then
            local statusHeight = 0.075
            self:drawPanelBackground(panel.x, panel.y, panel.width, statusHeight, {0, 0, 0, 0.7})
            setTextAlignment(RenderText.ALIGN_LEFT)
            setTextVerticalAlignment(RenderText.VERTICAL_ALIGN_TOP)
            setTextBold(true)
            setTextColor(1, 1, 1, 1)
            renderText(
                panel.x + panel.padding,
                panel.y + statusHeight - panel.padding,
                self.text.headerSize,
                vehicle:getFullName() .. " | Waiting for server debug snapshot..."
            )
            setTextBold(false)
            return
        end
    end

    local debugData = vehicle.isServer and (spec.debugData or {}) or (debugSnapshot.debugData or {})
    local factorStatsSource = vehicle.isServer and (spec.factorStats or {}) or (debugSnapshot.factorStats or {})
    local debugState = not vehicle.isServer and (debugSnapshot.state or {}) or {}

    -- on a dedicated client the server-owned values below come from one snapshot
    if not vehicle.isServer then
        spec = debugState
    end

    ---Returns a debug value, the stored one when the live one is unavailable
    local function getDebugStateValue(key, liveValue)
        if vehicle.isServer then
            return liveValue
        end
        local snapshotValue = debugState[key]
        if snapshotValue == nil then
            return liveValue
        end
        return snapshotValue
    end

    local cache = self.activeVehicleDebugCache
    local now = g_currentMission.time
    local debugViewMode = tostring(RMS_Hud.debugViewMode or "default")
    local refreshIntervalMs = vehicle.isServer
        and (cache.refreshIntervalMs or 100)
        or RMS_DebugSnapshot.REQUEST_INTERVAL_MS
    if cache.vehicle == vehicle
            and cache.viewMode == debugViewMode
            and cache.commands ~= nil
            and (now - (cache.lastUpdateTime or 0)) < refreshIntervalMs then
        self:renderActiveVehicleDebugCache(cache)
        return
    end

    local textSettings = self.text
    local fontStep = 0.001
    local activeHeaderSize = textSettings.headerSize + fontStep
    local activeNormalSize = textSettings.normalSize + fontStep
    local activeLineHeight = panel.lineHeight + fontStep
    local sectionGap = activeLineHeight * 0.65

    if debugViewMode == "factorStats" then
        self:drawFactorStatsVehicleHUD(
            vehicle,
            spec,
            factorStatsSource,
            panel,
            activeHeaderSize,
            activeNormalSize,
            activeLineHeight,
            sectionGap
        )
        return
    end

    local queuedCommands = {}

    ---Queues one text to draw at a position
    local function queueText(x, y, size, text, color, isBold)
        table.insert(queuedCommands, {
            x = x,
            y = y,
            size = size,
            text = text,
            color = color or {1, 1, 1, 1},
            bold = isBold == true
        })
    end

    ---Appends one line to a debug section
    local function addLine(target, text, color, sizeScale)
        table.insert(target, {
            text = text,
            color = color or {1, 1, 1, 1},
            sizeScale = sizeScale or 1.0
        })
    end

    ---Cuts a line to its width, continuations indented
    local function wrapLineToWidth(text, size, maxWidth)
        if maxWidth <= 0 or getTextWidth(size, text) <= maxWidth then
            return {text}
        end

        local parts = {}
        local indent = ""
        local current = nil

        for word in string.gmatch(text, "%S+") do
            local candidate = (current == nil) and (indent .. word) or (current .. " " .. word)
            if current ~= nil and getTextWidth(size, candidate) > maxWidth then
                table.insert(parts, current)
                indent = "  "
                current = indent .. word
            else
                current = candidate
            end
        end

        if current ~= nil then
            table.insert(parts, current)
        end

        return parts
    end

    ---Returns the colour of a temperature
    local function getTempColor(temp)
        if temp > 105 then
            return {1, 0.6, 0.6, 1}
        elseif temp > 95 then
            return {1, 1, 0.6, 1}
        end

        return {0.6, 0.8, 1, 1}
    end

    ---Packs several entries onto as few lines as the limit allows
    local function packEntries(entries, maxPerLine, color, sizeScale)
        local lines = {}
        if #entries == 0 then
            addLine(lines, "None", color, sizeScale)
            return lines
        end

        local lineEntries = {}
        for i, entry in ipairs(entries) do
            table.insert(lineEntries, entry)
            if #lineEntries >= maxPerLine or i == #entries then
                addLine(lines, table.concat(lineEntries, ", "), color, sizeScale)
                lineEntries = {}
            end
        end

        return lines
    end

    ---Renders a list as a comma separated string
    local function listToString(list)
        if list == nil or #list == 0 then
            return "-"
        end

        return table.concat(list, ",")
    end

    ---Builds the entries of a pending stress transition
    local function buildPendingSystemTransitionEntries(startMap, targetMap, currentValueGetter, formatter)
        local entries = {}
        startMap = startMap or {}
        targetMap = targetMap or {}

        for systemKey, startValue in pairs(startMap) do
            local targetValue = targetMap[systemKey]
            if targetValue ~= nil then
                local currentValue = currentValueGetter(systemKey)
                table.insert(entries, string.format(
                    "%s: %s->%s (cur %s)",
                    tostring(systemKey),
                    formatter(startValue),
                    formatter(targetValue),
                    formatter(currentValue)
                ))
            end
        end

        table.sort(entries)
        return entries
    end

    ---Localizes a debug value when it is an l10n key
    local function localizeDebugValue(value)
        if value == nil then
            return "-"
        end

        if type(value) == "boolean" then
            local key = value and "rms_ws_option_yes" or "rms_ws_option_no"
            if g_i18n:hasText(key) then
                return g_i18n:getText(key)
            end
            return tostring(value)
        end

        local key = tostring(value)
        if key == "" then
            return "-"
        end

        if g_i18n:hasText(key) then
            return g_i18n:getText(key)
        end

        return key
    end

    ---Returns the colour of a condition factor
    local function getConditionFactorColor(value)
        local v = math.max(value or 0, 0)
        local green = {0.72, 1.0, 0.72, 1}
        local yellow = {1.0, 1.0, 0.62, 1}
        local red = {1.0, 0.62, 0.62, 1}

        if v <= 0.01 then
            local t = math.max(math.min(v / 0.01, 1), 0)
            return {
                green[1] + (yellow[1] - green[1]) * t,
                green[2] + (yellow[2] - green[2]) * t,
                green[3] + (yellow[3] - green[3]) * t,
                1
            }
        end

        local t = math.max(math.min((v - 0.01) / 0.01, 1), 0)
        return {
            yellow[1] + (red[1] - yellow[1]) * t,
            yellow[2] + (red[2] - yellow[2]) * t,
            yellow[3] + (red[3] - yellow[3]) * t,
            1
        }
    end

    ---Returns the readable name of a breakdown source
    local function getBreakdownSourceLabel(source)
        if source == RealisticMechanicalSystems.BREAKDOWN_SOURCES.POOR_PARTS then
            return "PARTS"
        elseif source == RealisticMechanicalSystems.BREAKDOWN_SOURCES.QUICK_FIX then
            return "QFIX"
        end
        return "RAND"
    end

    local breakdownEntries = {}
    if spec.activeBreakdowns and next(spec.activeBreakdowns) ~= nil then
        for id, breakdown in pairs(spec.activeBreakdowns) do
            local visible = breakdown.isVisible and "V" or "-"
            local selected = breakdown.isSelectedForRepair and "S" or "-"
            local active = breakdown.isActive ~= false and "A" or "-"
            local resumeTimerS = math.max((tonumber(breakdown.resumeTimer) or 0) / 1000, 0)
            local source = getBreakdownSourceLabel(breakdown.source)
            local stage = tonumber(breakdown.stage) or 0
            local progressTimerS = math.max((tonumber(breakdown.progressTimer) or 0) / 1000, 0)

            table.insert(breakdownEntries, string.format(
                "%s[st:%d|pr:%.0fs|rs:%.0fs|%s%s%s|src:%s]",
                id,
                stage,
                progressTimerS,
                resumeTimerS,
                visible,
                selected,
                active,
                source
            ))
        end
    end
    table.sort(breakdownEntries)
    local breakdownLines = packEntries(breakdownEntries, 4, {1, 0.8, 0.8, 1}, 0.95)

    local effectEntries = {}
    if spec.activeEffects and next(spec.activeEffects) ~= nil then
        for id, effect in pairs(spec.activeEffects) do
            table.insert(effectEntries, string.format("%s:%.2f", id, effect.value))
        end
    end
    table.sort(effectEntries)
    local effectLines = packEntries(effectEntries, 4, {0.8, 0.8, 1, 1}, 0.95)

    local aiCruiseLines = {}
    local isAiActive = getDebugStateValue(
        "isAiActive",
        vehicle.getIsAIActive ~= nil and vehicle:getIsAIActive() == true
    ) == true
    if isAiActive and debugData.aiWorker then
        local dbg = debugData.aiWorker
        local ccState = tonumber(getDebugStateValue(
            "cruiseControlState",
            vehicle.getCruiseControlState ~= nil and vehicle:getCruiseControlState() or 0
        )) or 0

        addLine(aiCruiseLines, string.format(
            "cc state: %d | overload: %.2f | limit: %.1f km/h",
            ccState,
            dbg.overload or 0,
            dbg.speedLimit or 0
        ), {0.75, 1, 0.85, 1}, 0.95)
    end

    local bcw = RMS_Config.CORE.BASE_SYSTEMS_WEAR

    ---Formats a ratio as a percentage
    local function asPercent(value)
        return (value or 0) * 100
    end

    ---Formats an applied multiplier
    local function formatAppliedMultiplier(value)
        local formatted = string.format("%.2f", tonumber(value) or 0)
        formatted = formatted:gsub("(%..-)0+$", "%1")
        formatted = formatted:gsub("%.$", "")
        return "x" .. formatted
    end

    ---Returns the condition of a system
    local function getSystemCondition(systemKey)
        local systemData = spec.systems and spec.systems[systemKey]
        if type(systemData) == "table" then
            return systemData.condition or 0
        end
        return systemData or 0
    end

    ---Returns the stress of a system
    local function getSystemStress(systemKey)
        local systemData = spec.systems and spec.systems[systemKey]
        if type(systemData) == "table" then
            return systemData.stress or 0
        end
        return 0
    end

    ---Tells whether a system is enabled on this vehicle
    local function isSystemEnabled(systemKey)
        local systemData = spec.systems and spec.systems[systemKey]
        if type(systemData) == "table" then
            return systemData.enabled ~= false
        end
        return true
    end

    local engineDbg = debugData.engine or {}
    local transmissionDbg = debugData.transmission or {}
    local hydraulicsDbg = debugData.hydraulics or {}
    local coolingDbg = debugData.cooling or {}
    local electricalDbg = debugData.electrical or {}
    local chassisDbg = debugData.chassis or {}
    local fuelDbg = debugData.fuel or {}
    local ptoDbg = debugData.pto or {}
    local serviceDbg = debugData.service or {}
    local batteryDbg = debugData.battery or {}
    local drivetrainDbg = debugData.drivetrain or {}

    local overviewLines = {}
    local serviceWearRate = serviceDbg.totalWearRate or RMS_Config.CORE.BASE_SERVICE_WEAR or 0
    local weatherFactor = tonumber(getDebugStateValue(
        "weatherFactor",
        RMS_Main.currentWeatherFactor or 1
    )) or 1
    local dirtLevel = tonumber(getDebugStateValue(
        "dirtAmount",
        vehicle.getDirtAmount ~= nil and vehicle:getDirtAmount() or 0
    )) or 0
    local radiatorClogging = spec.radiatorClogging
    local airFilterClogging = spec.airFilterClogging
    local airFilterResidue = spec.airFilterResidue
    local lubricationLevel = spec.lubricationLevel
    local radiatorDbg = debugData.radiator or {}
    local airFilterDbg = debugData.airFilter or {}
    local radiatorMultiplier = radiatorDbg.totalMultiplier or 0
    local airFilterMultiplier = airFilterDbg.totalMultiplier or 0
    local cloggingIsOnField = radiatorDbg.isOnField == true or airFilterDbg.isOnField == true
    local cloggingHasDust = radiatorDbg.hasDust == true or airFilterDbg.hasDust == true
    local cloggingHasDebris = radiatorDbg.hasDebris == true or airFilterDbg.hasDebris == true
    local cloggingWetnessFactor = airFilterDbg.baseWetnessFactor or radiatorDbg.baseWetnessFactor or 1
    local currentOperatingSeconds = 0
    currentOperatingSeconds = math.floor((tonumber(getDebugStateValue(
        "operatingTimeMs",
        vehicle.getOperatingTime ~= nil and vehicle:getOperatingTime() or 0
    )) or 0) / 1000)
    -- only the service clocks the machine carries
    local serviceClockKeys, serviceClockLevels = {}, {}
    for _, clock in ipairs(vehicle:getServiceClocks()) do
        table.insert(serviceClockKeys, string.sub(clock.key, 1, 1))
        table.insert(serviceClockLevels, string.format("%.2f%%", asPercent(spec[clock.levelKey] or 0)))
    end

    addLine(overviewLines, string.format(
        "op.sec: %ds (real: %ds) | condition: %.2f%% | service %s: %s | service_wear: %.2f%% | rel: %.2f%% | wf: %.3f | roof: %s | lube: %.2f%%",
        currentOperatingSeconds,
        math.floor((tonumber(spec.realOperatingTime) or 0) / 1000),
        asPercent(spec.conditionLevel or 0),
        table.concat(serviceClockKeys, "/"),
        table.concat(serviceClockLevels, " / "),
        asPercent(serviceWearRate),
        asPercent(spec.reliability or 0),
        weatherFactor,
        tostring(getDebugStateValue("isUnderRoof", spec.isUnderRoof == true) == true),
        asPercent(lubricationLevel)
    ), {1, 1, 1, 1}, 0.95)

    addLine(overviewLines, string.format(
        "Clogging: Dirt %.2f%% | Radiator: %.2f%% (%s) | Filter: %.2f%%, residue: %.2f%% (%s) | field: %s, dust: %s, debris: %s, wetness: %.3f",
        asPercent(dirtLevel),
        asPercent(radiatorClogging),
        formatAppliedMultiplier(radiatorMultiplier),
        asPercent(airFilterClogging),
        asPercent(airFilterResidue),
        formatAppliedMultiplier(airFilterMultiplier),
        tostring(cloggingIsOnField),
        tostring(cloggingHasDust),
        tostring(cloggingHasDebris),
        cloggingWetnessFactor
    ), {1, 1, 1, 1}, 0.95)

    -- only the circuits the machine has
    local fluidEntries = {}
    if RMS_Fluids.hasCircuit(vehicle, "engineOil") then
        table.insert(fluidEntries, string.format("engine oil %.2f%%", asPercent(spec.engineOilLevel or 1)))
    end
    if isSystemEnabled("cooling") then
        table.insert(fluidEntries, string.format("coolant %.2f%% (leak %.3f/h)",
            asPercent(spec.coolantLevel or 1), tonumber(spec.coolantLeakRate) or 0))
    end
    if isSystemEnabled("transmission") then
        table.insert(fluidEntries, string.format("transmission %.2f%% (leak %.3f/h)",
            asPercent(spec.transmissionOilLevel or 1), tonumber(spec.transmissionOilLeakRate) or 0))
    end
    if isSystemEnabled("hydraulics") then
        table.insert(fluidEntries, string.format("hydraulic %.2f%% (leak %.3f/h)",
            asPercent(spec == liveSpec and hydraulicFluidLevel or spec.hydraulicFluidLevel or 1), tonumber(spec.hydraulicFluidLeakRate) or 0))
    end
    addLine(overviewLines, "Fluids: " .. table.concat(fluidEntries, " | "), {1, 1, 1, 1}, 0.95)

    do
        local drivetrainModeNames = { [0] = "4x2", [1] = "4WD", [2] = "AUTO" }
        local parkKindNames = { [0] = "lever", [1] = "auto", [2] = "air" }
        addLine(overviewLines, string.format(
            "Drivetrain: ctl: %s | mode: %s | autoEng: %s | lock: %s | park: %s (%s) | windup: %.1f%% (wf: %.2f)",
            tostring(drivetrainDbg.hasControl == true),
            drivetrainModeNames[tonumber(drivetrainDbg.driveMode) or -1] or "n/a",
            tostring(drivetrainDbg.autoEngaged == true),
            tostring(drivetrainDbg.diffLockEngaged == true),
            tostring(drivetrainDbg.parkBrake == true),
            parkKindNames[tonumber(drivetrainDbg.parkKind) or -1] or "n/a",
            asPercent(drivetrainDbg.windupStress or 0),
            tonumber(drivetrainDbg.windupWearFactor) or 0
        ), {1, 1, 1, 1}, 0.95)
        local axleRatioValues = {}
        for _, entry in ipairs(drivetrainDbg.axleRatios or {}) do
            local ratio = tonumber(entry.ratio)
            table.insert(axleRatioValues, string.format(
                "%s %s / cap %.2f",
                entry.label or "?",
                ratio ~= nil and string.format("%.2f", ratio) or "n/a",
                tonumber(entry.cap) or 0
            ))
        end
        if #axleRatioValues > 0 then
            addLine(
                overviewLines,
                "Axle ratio: " .. table.concat(axleRatioValues, " | "),
                {1, 1, 1, 1},
                0.95
            )
        end
    end

    do
        -- exhaust particles are computed and drawn on the client
        local smoke = type(liveSpec.exhaustSmoke) == "table" and liveSpec.exhaustSmoke or {}
        local exhaustDbg = type(liveSpec.debugData) == "table" and type(liveSpec.debugData.exhaust) == "table"
            and liveSpec.debugData.exhaust or {}

        local profile = {tostring(spec.year or "?")}
        if smoke.isStageV == true then table.insert(profile, "StageV") end
        if smoke.hasDEF == true then table.insert(profile, "DEF") end
        if smoke.isMethane == true then table.insert(profile, "methane") end
        if smoke.hasTurbo == true then table.insert(profile, "turbo") end

        -- one line for the engine emissions and the local plume
        local line = "Exhaust: off | " .. table.concat(profile, " ")
        if smoke.isActive == true then
            line = string.format(
                "Exhaust: %s | black %.0f%% blue %.0f%% white %.0f%% | opacity %.0f%% vapour %.0f%%%s | gas %.0fC at %.1f m/s | wind %.1f m/s sheltered %.0f%%",
                table.concat(profile, " "),
                asPercent(smoke.soot),
                asPercent(smoke.oil),
                asPercent(smoke.unburnt),
                asPercent(exhaustDbg.opacity),
                asPercent(exhaustDbg.vapour),
                exhaustDbg.burstCause ~= nil and (" | burst " .. tostring(exhaustDbg.burstCause)) or "",
                tonumber(exhaustDbg.gasTemperature) or 0,
                tonumber(exhaustDbg.exitSpeed) or 0,
                tonumber(exhaustDbg.windSpeed) or 0,
                asPercent(exhaustDbg.shelter)
            )
        end
        if exhaustDbg.isOverridden == true then
            line = line .. " | override"
        end
        -- orange when the game refused per puff sprite control
        addLine(overviewLines, line, exhaustDbg.isSpriteControlled == false and {1, 0.6, 0.2, 1} or {1, 1, 1, 1}, 0.95)
    end

    local engineMaxFactor = math.max(
        engineDbg.motorLoadFactor or 0,
        engineDbg.airFilterCloggingFactor or 0,
        engineDbg.expiredServiceFactor or 0,
        engineDbg.coldMotorFactor or 0,
        engineDbg.hotMotorFactor or 0
    ) * bcw
    local transmissionMaxFactor = math.max(
        transmissionDbg.expiredServiceFactor or 0,
        transmissionDbg.pullOverloadFactor or 0,
        transmissionDbg.heavyTrailerFactor or 0,
        transmissionDbg.luggingFactor or 0,
        transmissionDbg.wheelSlipFactor or 0,
        transmissionDbg.drivetrainWindupFactor or 0,
        transmissionDbg.coldTransFactor or 0,
        transmissionDbg.hotTransFactor or 0
    ) * bcw
    local hydraulicsMaxFactor = math.max(
        hydraulicsDbg.expiredServiceFactor or 0,
        hydraulicsDbg.heavyLiftFactor or 0,
        hydraulicsDbg.vibFactor or 0,
        hydraulicsDbg.operatingFactor or 0,
        hydraulicsDbg.coldOilFactor or 0,
        hydraulicsDbg.hotOilFactor or 0
    ) * bcw
    local coolingMaxFactor = math.max(
        coolingDbg.expiredServiceFactor or 0,
        coolingDbg.highCoolingFactor or 0,
        coolingDbg.overheatFactor or 0,
        coolingDbg.coldShockFactor or 0
    ) * bcw
    local electricalMaxFactor = math.max(
        electricalDbg.weatherExposureFactor or 0,
        electricalDbg.lightsFactor or 0,
        electricalDbg.crankingStressFactor or 0,
        electricalDbg.overheatFactor or 0,
        electricalDbg.vibFactor or 0
    ) * bcw
    local chassisMaxFactor = math.max(
        chassisDbg.lubricationFactor or 0,
        chassisDbg.vibFactor or 0,
        chassisDbg.steerLoadFactor or 0,
        chassisDbg.brakeMassFactor or 0
    ) * bcw
    local fuelMaxFactor = math.max(
        fuelDbg.expiredServiceFactor or 0,
        fuelDbg.lowFuelStarvationFactor or 0,
        fuelDbg.coldFuelFactor or 0,
        fuelDbg.idleDepositFactor or 0,
        fuelDbg.highPressureFactor or 0,
        fuelDbg.deepDischargeFactor or 0,
        fuelDbg.highDrawFactor or 0,
        fuelDbg.batteryHeatFactor or 0
    ) * bcw
    local ptoMaxFactor = math.max(
        ptoDbg.expiredServiceFactor or 0,
        ptoDbg.ptoLoadFactor or 0,
        ptoDbg.ptoRaisedFactor or 0
    ) * bcw
    ---Formats the current contribution of one wear factor
    local function formatFactorLine(shortName, factorValue)
        return string.format("%s: %.2f", shortName, asPercent((factorValue or 0) * bcw))
    end

    local avgTireGroundFrictionCoeff = tonumber(getDebugStateValue("avgTireGroundFrictionCoeff", spec.avgTireGroundFrictionCoeff)) or 0

    ---Builds every debug line of one system
    local function buildSystemLines(systemKey, dbg, maxFactor, factorEntries)
        local lines = {}
        addLine(lines, string.format(
            "C: %.1f (-%.2f)",
            asPercent(getSystemCondition(systemKey)),
            asPercent((dbg.totalWearRate or 0) * bcw)
        ), getConditionFactorColor(maxFactor), 0.84)
        addLine(lines, string.format(
            "S: %.2f (+%.2f) | a: %.2f",
            asPercent(getSystemStress(systemKey)),
            asPercent(dbg.instantStressRate or 0),
            asPercent(dbg._avgStress or 0)
        ), {1, 1, 1, 1}, 0.84)

        addLine(lines, string.format(
            "B: %.2f | %.2f",
            asPercent(dbg.breakdownProbability or 0),
            asPercent(dbg.critBreakdownProbability or 0)
        ), {1, 0.82, 0.82, 1}, 0.80)

        for _, entry in ipairs(factorEntries) do
            if entry.shortName ~= nil then
                addLine(
                    lines,
                    formatFactorLine(entry.shortName, entry.value),
                    {0.92, 0.96, 1.0, 1},
                    0.80
                )
            end

            -- complements go on their own indented line
            local extraInfo = entry.extraInfo ~= nil and tostring(entry.extraInfo) or ""
            if extraInfo ~= "" then
                addLine(lines, "  (" .. extraInfo .. ")", {0.92, 0.96, 1.0, 1}, 0.80)
            end
        end

        return lines
    end

    local isElectric = liveSpec.isElectricVehicle == true
    local engineLines = buildSystemLines("engine", engineDbg, engineMaxFactor, isElectric and {
        { shortName = "mlf", value = engineDbg.motorLoadFactor or 0, extraInfo = string.format("dml: %.2f", engineDbg.dynamicMotorLoad or 0) },
        { shortName = "hmf", value = engineDbg.hotMotorFactor or 0, extraInfo = string.format("t: %.1f C", engineDbg.engineTemperature or 0) }
    } or {
        { shortName = "sf", value = engineDbg.expiredServiceFactor or 0 },
        { shortName = "mlf", value = engineDbg.motorLoadFactor or 0, extraInfo = string.format("dml: %.2f", engineDbg.dynamicMotorLoad or 0) },
        { shortName = "lf", value = engineDbg.luggingFactor or 0 },
        { shortName = "aicf", value = engineDbg.airFilterCloggingFactor or 0 },
        { shortName = "cmf", value = engineDbg.coldMotorFactor or 0 },
        { shortName = "hmf", value = engineDbg.hotMotorFactor or 0 },
        { shortName = "flf", value = engineDbg.lowFluidFactor or 0 }
    })

    local transmissionLines = buildSystemLines("transmission", transmissionDbg, transmissionMaxFactor, {
        { shortName = "sf", value = transmissionDbg.expiredServiceFactor or 0 },
        {
            shortName = "pof",
            value = transmissionDbg.pullOverloadFactor or 0,
            extraInfo = string.format(
                "%.1f->%.1f",
                transmissionDbg.pullOverloadTimer or 0,
                transmissionDbg.pullOverloadTimerMin or 0
            )
        },
        {
            shortName = "htf",
            value = transmissionDbg.heavyTrailerFactor or 0,
            extraInfo = string.format(
                "hp/%s: %.1f",
                (transmissionDbg.heavyTrailerMassBasis == "gcw") and "gcw" or "trl",
                transmissionDbg.heavyTrailerMassRatio or 0
            )
        },
        { shortName = "lf", value = transmissionDbg.luggingFactor or 0 },
        { shortName = "wsf", value = transmissionDbg.wheelSlipFactor or 0, extraInfo = string.format("c: %.2f", avgTireGroundFrictionCoeff) },
        {
            shortName = "dwf",
            value = transmissionDbg.drivetrainWindupFactor or 0,
            extraInfo = string.format(
                "w: %.1f%% lock: %s",
                asPercent(drivetrainDbg.windupStress or 0),
                (drivetrainDbg.diffLockEngaged == true) and "Y" or "N"
            )
        },
        { shortName = "ctf", value = transmissionDbg.coldTransFactor or 0 },
        { shortName = "hotf", value = transmissionDbg.hotTransFactor or 0 },
        { shortName = "flf", value = transmissionDbg.lowFluidFactor or 0 }
    })

    local hydraulicsLines = buildSystemLines("hydraulics", hydraulicsDbg, hydraulicsMaxFactor, {
        { shortName = "sf", value = hydraulicsDbg.expiredServiceFactor or 0 },
        { shortName = "hlf", value = hydraulicsDbg.heavyLiftFactor or 0, extraInfo = string.format("mr: %.2f", asPercent(hydraulicsDbg.heavyLiftMassRatio or 0)) },
        { shortName = "vf", value = hydraulicsDbg.vibFactor or 0, extraInfo = string.format("s: %.2f", asPercent(hydraulicsDbg.vibSignal or 0)) },
        { shortName = "of", value = hydraulicsDbg.operatingFactor or 0, extraInfo = string.format("active: %s", tostring(hydraulicsDbg.isHydraulicActive == true)) },
        { shortName = "cof", value = hydraulicsDbg.coldOilFactor or 0 },
        { shortName = "hof", value = hydraulicsDbg.hotOilFactor or 0 },
        { shortName = "flf", value = hydraulicsDbg.lowFluidFactor or 0 }
    })

    local coolingLines = buildSystemLines("cooling", coolingDbg, coolingMaxFactor, {
        { shortName = "sf", value = coolingDbg.expiredServiceFactor or 0 },
        { shortName = "hcf", value = coolingDbg.highCoolingFactor or 0, extraInfo = string.format("ts: %.1f", asPercent(spec.thermostatState or 0)) },
        { shortName = "ohf", value = coolingDbg.overheatFactor or 0 },
        { shortName = "csf", value = coolingDbg.coldShockFactor or 0 }
    })

    local electricalLines = buildSystemLines("electrical", electricalDbg, electricalMaxFactor, {
        { shortName = "wef", value = electricalDbg.weatherExposureFactor or 0 },
        { shortName = "ltf", value = electricalDbg.lightsFactor or 0 },
        {
            shortName = "crf",
            value = electricalDbg.crankingStressFactor or 0,
            extraInfo = string.format(
                "c: %s, t: %ds",
                tostring(getDebugStateValue("isCranking", spec.isCranking == true) == true),
                math.floor(((electricalDbg.crankingTimer or 0) / 1000) + 0.0001)
            )
        },
        { shortName = "ohf", value = electricalDbg.overheatFactor or 0 },
        {
            shortName = "vf",
            value = electricalDbg.vibFactor or 0,
            extraInfo = string.format(
                "r/s: %.2f / %.2f",
                asPercent(electricalDbg.vibRaw or 0),
                asPercent(electricalDbg.vibSignal or 0)
            )
        }
    })

    local chassisLines = buildSystemLines("chassis", chassisDbg, chassisMaxFactor, {
        { shortName = "lubf", value = chassisDbg.lubricationFactor or 0 },
        {
            shortName = "vf",
            value = chassisDbg.vibFactor or 0,
            extraInfo = string.format(
                "r/s: %.2f / %.2f",
                asPercent(chassisDbg.vibRaw or 0),
                asPercent(chassisDbg.vibSignal or 0)
            )
        },
        {
            shortName = "slf",
            value = chassisDbg.steerLoadFactor or 0,
            extraInfo = string.format(
                "ls: %.2f t: %.2f l: %.2f c: %.2f",
                chassisDbg.steerLowSpeedFactor or 0,
                chassisDbg.steerTravelRate or 0,
                chassisDbg.steerAxleLoadRatio or 0,
                chassisDbg.steerGroundFrictionCoeff or 0
            )
        },
        -- an impact is a hit and no wear rate: it is counted, with the km/h the last one took
        { extraInfo = string.format("tif n: %d last: %.1f km/h", chassisDbg.impactCount or 0, chassisDbg.impactSpeedLoss or 0) },
        { extraInfo = string.format("play: %.1f pull: %.1f", chassisDbg.steerPlay or 0, chassisDbg.steerPull or 0) },
        {
            shortName = "bmf",
            value = chassisDbg.brakeMassFactor or 0,
            extraInfo = string.format(
                "hp/%s: %.1f",
                (chassisDbg.brakeMassBasis == "gcw") and "gcw" or "trl",
                chassisDbg.brakeMassRatio or 0
            )
        }
    })

    local fuelLines = buildSystemLines("fuel", fuelDbg, fuelMaxFactor, isElectric and {
        { shortName = "ddf", value = fuelDbg.deepDischargeFactor or 0, extraInfo = string.format("lvl: %.2f", asPercent(fuelDbg.fuelLevel or 0)) },
        { shortName = "hdf", value = fuelDbg.highDrawFactor or 0, extraInfo = string.format("r: %.3f", fuelDbg.currentFuelUsageRatio or 0) },
        { shortName = "bhf", value = fuelDbg.batteryHeatFactor or 0, extraInfo = string.format("pack: %.1f C", liveSpec.tractionBatteryTempC or 0) }
    } or {
        { shortName = "sf", value = fuelDbg.expiredServiceFactor or 0 },
        { shortName = "lff", value = fuelDbg.lowFuelStarvationFactor or 0, extraInfo = string.format("lvl: %.2f", asPercent(fuelDbg.fuelLevel or 0)) },
        { shortName = "cff", value = fuelDbg.coldFuelFactor or 0, extraInfo = string.format("ft: %.1f C", fuelDbg.fuelTemperature or 0) },
        { shortName = "idf", value = fuelDbg.idleDepositFactor or 0, extraInfo = string.format("t: %.0fs", fuelDbg.idleTimer or 0) },
        { shortName = "hpf", value = fuelDbg.highPressureFactor or 0, extraInfo = string.format("r: %.3f", fuelDbg.currentFuelUsageRatio or 0) }
    })

    local ptoLines = buildSystemLines("pto", ptoDbg, ptoMaxFactor, {
        { shortName = "sf", value = ptoDbg.expiredServiceFactor or 0 },
        {
            shortName = "plf",
            value = ptoDbg.ptoLoadFactor or 0,
            extraInfo = string.format(
                "active: %s rpm: %.0f kW: %.1f u: %.3f",
                tostring(ptoDbg.isPtoActive == true),
                ptoDbg.ptoRpm or 0,
                ptoDbg.ptoPower or 0,
                ptoDbg.ptoUtilization or 0
            )
        },
        { shortName = "prf", value = ptoDbg.ptoRaisedFactor or 0 },
        {
            shortName = "pef",
            value = ptoDbg.ptoEngagementDamage or 0,
            extraInfo = string.format(
                "cycles: %d dmg: %.4f",
                ptoDbg.ptoEngagementCount or 0,
                ptoDbg.ptoEngagementDamage or 0
            )
        }
    })


    local systemSections = {}
    if isSystemEnabled("engine") then
        table.insert(systemSections, {title = isElectric and "Electric motor" or "Engine", lines = engineLines})
    end
    if isSystemEnabled("transmission") then
        table.insert(systemSections, {title = "Transmission", lines = transmissionLines})
    end
    if isSystemEnabled("hydraulics") then
        table.insert(systemSections, {title = "Hydraulics", lines = hydraulicsLines})
    end
    if isSystemEnabled("cooling") then
        table.insert(systemSections, {title = "Cooling", lines = coolingLines})
    end
    if isSystemEnabled("electrical") then
        table.insert(systemSections, {title = "Electrical", lines = electricalLines})
    end
    if isSystemEnabled("chassis") then
        table.insert(systemSections, {title = "Chassis", lines = chassisLines})
    end
    if isSystemEnabled("fuel") then
        table.insert(systemSections, {title = isElectric and "Traction battery" or "Fuel", lines = fuelLines})
    end
    if isSystemEnabled("pto") then
        table.insert(systemSections, {title = "PTO", lines = ptoLines})
    end

    local engineTempLines = {}
    addLine(engineTempLines, string.format(
        "T: %.1fC | ts: %.3f | h/c: %.3f/%.3f | r/s/c: %.3f/%.3f/%.3f",
        spec.engineTemperature,
        spec.thermostatState,
        (debugData.engineTemp or {}).totalHeat or 0,
        (debugData.engineTemp or {}).totalCooling or 0,
        (debugData.engineTemp or {}).radiatorCooling or 0,
        (debugData.engineTemp or {}).speedCooling or 0,
        (debugData.engineTemp or {}).convectionCooling or 0
    ), getTempColor(spec.engineTemperature), 0.95)

    local hasActiveCVTAddon = hasCVTAddon(vehicle)
    local vehicleHasCVT = hasCVTTransmission(vehicle)

    local showTransmissionSection = vehicleHasCVT and spec.transmissionTemperature > -30
    local transmissionTempLines = {}
    if showTransmissionSection then
        addLine(transmissionTempLines, string.format(
            "T: %.1fC (raw: %.1fC) | ts: %.3f | h: %.3f(i/l: %.3f/%.2f) | c: %.3f(cl/s/cv: %.3f/%.3f/%.3f) | eh=%.3f ph=%.3f hh=%.3f",
            spec.transmissionTemperature,
            spec.rawTransmissionTemperature or spec.transmissionTemperature or -99,
            spec.transmissionThermostatState,
            (debugData.transmissionTemp or {}).totalHeat or 0,
            (debugData.transmissionTemp or {}).idleHeat or 0,
            (debugData.transmissionTemp or {}).loadFactor or 0,
            (debugData.transmissionTemp or {}).totalCooling or 0,
            (debugData.transmissionTemp or {}).coolerCooling or 0,
            (debugData.transmissionTemp or {}).speedCooling or 0,
            (debugData.transmissionTemp or {}).convectionCooling or 0,
            (debugData.transmissionTemp or {}).extraTransmissionHeat or 0,
            (debugData.transmissionTemp or {}).ptoHeat or 0,
            (debugData.transmissionTemp or {}).hydraulicHeat or 0
        ), getTempColor(spec.transmissionTemperature), 0.95)
    end

    local motorTelemetryLines = buildMotorTelemetryLines(
        vehicle,
        spec,
        motor,
        getDebugStateValue,
        hasActiveCVTAddon
    )

    -- state, balance by source and by consumer, start
    local batteryLines = {}
    local soc = spec.batterySoc
    local capacityAh = batteryDbg.capacityAh or 0
    -- the circuit is sized on every machine, a client reads it from its own vehicle
    local seriesBatteries = vehicle.spec_RealisticMechanicalSystems.electricalRating.seriesBatteries

    addLine(batteryLines, string.format(
        "State: %d V circuit %.2fV (rest %.2fV) | %.1f Ah of %.0f Ah (%.1f%%) | out of reach %.0f%% at %.1fC | parked draw %.0f mA | isolator %s | cables %s",
        12 * seriesBatteries,
        spec.systemVoltageV,
        batteryDbg.restingV or 0,
        soc * capacityAh,
        capacityAh,
        asPercent(soc),
        asPercent(batteryDbg.floorSoc or 0),
        batteryDbg.ambientC or 0,
        (batteryDbg.restingA or 0) * 1000,
        spec.batteryIsolated and "open" or "closed",
        batteryDbg.partnerName or "-"
    ), {0.9, 1.0, 0.9, 1}, 0.95)

    addLine(batteryLines, string.format(
        "Battery: %+.1fA | %s: %.1fA | Charger: %.1fA | Loads: base %.1fA | cab %.1fA | lights %.1fA | starter %.1fA | preheat %.1fA",
        batteryDbg.batteryA or 0,
        isElectric and "Converter" or "Alternator",
        batteryDbg.generatorA or 0,
        batteryDbg.chargerA or 0,
        batteryDbg.baseA or 0,
        batteryDbg.cabA or 0,
        batteryDbg.lightsA or 0,
        batteryDbg.starterA or 0,
        batteryDbg.preheatA or 0
    ), {0.85, 0.95, 1.0, 1}, 0.95)

    addLine(batteryLines, string.format(
        "Start: %.2fV under the starter (min %.1fV) | speed %.0f%% | battery %.2f mOhm | circuit %.2f mOhm",
        batteryDbg.startingV or 0,
        RMS_Config.ELECTRICAL.MIN_CRANKING_VOLTAGE_V * seriesBatteries,
        asPercent(batteryDbg.crankingSpeed or 0),
        (batteryDbg.resistanceOhm or 0) * 1000,
        (batteryDbg.circuitOhm or 0) * 1000
    ), {1.0, 0.95, 0.85, 1}, 0.95)

    local preheatIsDiesel = getDebugStateValue("preheatIsDiesel", RMS_Preheat.isDieselVehicle(vehicle)) == true
    if preheatIsDiesel then
        local preheatState = tonumber(getDebugStateValue("preheatState", spec.preheatState)) or RMS_Preheat.STATE.IDLE
        local preheatStateName = tostring(getDebugStateValue("preheatStateName", RMS_Preheat.getStateName(preheatState)))
        local preheatEngineTemperatureC = tonumber(getDebugStateValue("preheatEngineTemperatureC", RMS_Preheat.getEngineTemperatureC(vehicle))) or 0
        local preheatLampTestActive = getDebugStateValue("preheatLampTestActive", spec.preheatLampTestActive == true) == true
        local preheatLampTestRemainingMs = tonumber(getDebugStateValue("preheatLampTestRemainingMs", spec.preheatLampTestRemainingMs)) or 0
        local preheatRemainingMs = tonumber(getDebugStateValue("preheatRemainingMs", spec.preheatRemainingMs)) or 0
        local preheatRequiredMs = tonumber(getDebugStateValue("preheatRequiredMs", spec.preheatRequiredMs)) or 0
        local preheatWasRequired = getDebugStateValue("preheatWasRequired", spec.preheatWasRequired == true) == true
        local preheatAutomaticCrank = getDebugStateValue("preheatAutomaticCrank", spec.preheatAutomaticCrank == true) == true
        local preheatAutomaticCrankElapsedMs = tonumber(getDebugStateValue("preheatAutomaticCrankElapsedMs", spec.preheatAutomaticCrankElapsedMs)) or 0
        local preheatGlowPlugFailureSeverity = tonumber(getDebugStateValue("preheatGlowPlugFailureSeverity", RMS_Preheat.getGlowPlugFailureSeverity(vehicle))) or 0
        local preheatColdStartFaultSeverity = tonumber(getDebugStateValue("preheatColdStartFaultSeverity", spec.preheatColdStartFaultSeverity)) or 0
        local glowHardStartEffect = spec.activeEffects ~= nil and spec.activeEffects.GLOW_PLUG_HARD_START_MODIFIER or nil
        local localGlowHardStartStatus = glowHardStartEffect ~= nil
            and glowHardStartEffect.extraData ~= nil
            and glowHardStartEffect.extraData.status
            or "NONE"
        local preheatGlowHardStartStatus = tostring(getDebugStateValue("preheatGlowHardStartStatus", localGlowHardStartStatus))
        local localGlowHardStartBlocked = glowHardStartEffect ~= nil
            and glowHardStartEffect.extraData ~= nil
            and glowHardStartEffect.extraData.blockStart == true
            and preheatIsDiesel
            and preheatEngineTemperatureC < RMS_Config.PREHEAT.START_ASSIST_TEMPERATURE_C
        local preheatGlowHardStartBlocked = getDebugStateValue("preheatGlowHardStartBlocked", localGlowHardStartBlocked) == true

        addLine(batteryLines, string.format(
            "Preheat: %s | engine: %.1fC | required: %.1fs | remaining: %.1fs | requested cold: %s",
            preheatStateName,
            preheatEngineTemperatureC,
            preheatRequiredMs / 1000,
            preheatRemainingMs / 1000,
            tostring(preheatWasRequired)
        ), {0.9, 1.0, 0.9, 1}, 0.95)

        addLine(batteryLines, string.format(
            "Preheat control: lamp test %s (%.1fs) | auto crank %s (%.1f/%.1fs) | glow fault %d | cold fault %d | glow starter %s | blocked %s",
            tostring(preheatLampTestActive),
            preheatLampTestRemainingMs / 1000,
            tostring(preheatAutomaticCrank),
            preheatAutomaticCrankElapsedMs / 1000,
            RMS_Config.PREHEAT.MAX_AUTOMATIC_CRANK_MS / 1000,
            preheatGlowPlugFailureSeverity,
            preheatColdStartFaultSeverity,
            preheatGlowHardStartStatus,
            tostring(preheatGlowHardStartBlocked)
        ), {0.85, 0.95, 1.0, 1}, 0.95)
    end

    if (batteryDbg.externalConnected or 0) > 0 then
        addLine(batteryLines, string.format(
            "External: %s | bal %.1fA | com: %.1fA",
            tostring(batteryDbg.externalPartnerName or "-"),
            batteryDbg.externalBalanceCurrentA or 0,
            batteryDbg.externalCommonNetA or 0
        ), {0.85, 0.95, 1.0, 1}, 0.95)
    end

    local serviceDataLines = {}
    local states = RealisticMechanicalSystems.STATUS
    local isUnderService = spec.currentState ~= states.READY
    if isUnderService then
        local pendingInspectionQueue = getDebugStateValue("pendingInspectionQueue", spec.pendingInspectionQueue or {}) or {}
        local pendingRepairQueue = getDebugStateValue("pendingRepairQueue", spec.pendingRepairQueue or {}) or {}
        local pendingSelectedBreakdowns = getDebugStateValue("pendingSelectedBreakdowns", spec.pendingSelectedBreakdowns or {}) or {}
        local progressPercent = 0
        if (spec.pendingProgressTotalTime or 0) > 0 then
            local progressRatio = math.min(math.max((spec.pendingProgressElapsedTime or 0) / spec.pendingProgressTotalTime, 0), 1)
            progressPercent = math.floor(progressRatio * 100)
        end

        addLine(serviceDataLines, string.format(
            "cur/pl/ws: %s/%s/%s | o1/o2/o3/price: %s/%s/%s/%s",
            localizeDebugValue(spec.currentState),
            localizeDebugValue(spec.plannedState),
            localizeDebugValue(spec.workshopType),
            localizeDebugValue(spec.serviceOptionOne),
            localizeDebugValue(spec.serviceOptionTwo),
            localizeDebugValue(spec.serviceOptionThree),
            tostring(getDebugStateValue("pendingServicePrice", spec.pendingServicePrice))
        ), {1, 0.95, 0.75, 1}, 0.95)
        addLine(serviceDataLines, string.format(
            "tm/el/tt(ms): %.0f/%.0f/%.0f | prg: %d%% | step: %d | q(sel/insp/rep): %d/%d/%d",
            spec.maintenanceTimer or 0,
            spec.pendingProgressElapsedTime or 0,
            spec.pendingProgressTotalTime or 0,
            progressPercent,
            spec.pendingProgressStepIndex or 0,
            #pendingSelectedBreakdowns,
            #pendingInspectionQueue,
            #pendingRepairQueue
        ), {1, 0.95, 0.75, 1}, 0.95)
        addLine(serviceDataLines, string.format(
            "svc s->t: %s->%s | cur s/c: %.4f/%.4f",
            RMS_Utils.serializeNumericMap(getDebugStateValue("pendingServiceClockStart", spec.pendingServiceClockStart or {}) or {}),
            RMS_Utils.serializeNumericMap(getDebugStateValue("pendingServiceClockTarget", spec.pendingServiceClockTarget or {}) or {}),
            spec.serviceLevel or 0,
            spec.conditionLevel or 0
        ), {1, 0.95, 0.75, 1}, 0.95)

        if spec.currentState == states.OVERHAUL then
            local overhaulSystemStart = getDebugStateValue("pendingOverhaulSystemStart", spec.pendingOverhaulSystemStart or {}) or {}
            local overhaulSystemTarget = getDebugStateValue("pendingOverhaulSystemTarget", spec.pendingOverhaulSystemTarget or {}) or {}
            local overhaulStressStart = getDebugStateValue("pendingOverhaulSystemStressStart", spec.pendingOverhaulSystemStressStart or {}) or {}
            local overhaulStressTarget = getDebugStateValue("pendingOverhaulSystemStressTarget", spec.pendingOverhaulSystemStressTarget or {}) or {}
            local conditionEntries = buildPendingSystemTransitionEntries(
                overhaulSystemStart,
                overhaulSystemTarget,
                function(systemKey)
                    local systemData = spec.systems and spec.systems[systemKey]
                    return type(systemData) == "table" and (tonumber(systemData.condition) or 0) or 0
                end,
                function(value)
                    return string.format("%.3f", tonumber(value) or 0)
                end
            )
            local stressEntries = buildPendingSystemTransitionEntries(
                overhaulStressStart,
                overhaulStressTarget,
                function(systemKey)
                    local systemData = spec.systems and spec.systems[systemKey]
                    return type(systemData) == "table" and (tonumber(systemData.stress) or 0) or 0
                end,
                function(value)
                    return string.format("%.3f", tonumber(value) or 0)
                end
            )

            addLine(serviceDataLines, "ovh cond:", {1, 0.95, 0.75, 1}, 0.95)
            local conditionLines = packEntries(conditionEntries, 2, {1, 0.95, 0.75, 1}, 0.95)
            for _, line in ipairs(conditionLines) do
                table.insert(serviceDataLines, line)
            end

            addLine(serviceDataLines, "ovh stress:", {1, 0.95, 0.75, 1}, 0.95)
            local stressLines = packEntries(stressEntries, 2, {1, 0.95, 0.75, 1}, 0.95)
            for _, line in ipairs(stressLines) do
                table.insert(serviceDataLines, line)
            end
        elseif spec.currentState == states.REPAIR then
            local repairStressEntries = buildPendingSystemTransitionEntries(
                getDebugStateValue("pendingRepairSystemStressStart", spec.pendingRepairSystemStressStart or {}) or {},
                getDebugStateValue("pendingRepairSystemStressTarget", spec.pendingRepairSystemStressTarget or {}) or {},
                function(systemKey)
                    local systemData = spec.systems and spec.systems[systemKey]
                    return type(systemData) == "table" and (tonumber(systemData.stress) or 0) or 0
                end,
                function(value)
                    return string.format("%.3f", tonumber(value) or 0)
                end
            )

            if #repairStressEntries > 0 then
                addLine(serviceDataLines, "rep stress:", {1, 0.95, 0.75, 1}, 0.95)
                local repairStressLines = packEntries(repairStressEntries, 2, {1, 0.95, 0.75, 1}, 0.95)
                for _, line in ipairs(repairStressLines) do
                    table.insert(serviceDataLines, line)
                end
            end
        elseif spec.currentState == states.MAINTENANCE and spec.serviceOptionOne == RealisticMechanicalSystems.MAINTENANCE_TYPES.PREVENTIVE then
            local preventiveStressEntries = buildPendingSystemTransitionEntries(
                getDebugStateValue("pendingPreventiveSystemStressStart", spec.pendingPreventiveSystemStressStart or {}) or {},
                getDebugStateValue("pendingPreventiveSystemStressTarget", spec.pendingPreventiveSystemStressTarget or {}) or {},
                function(systemKey)
                    local systemData = spec.systems and spec.systems[systemKey]
                    return type(systemData) == "table" and (tonumber(systemData.stress) or 0) or 0
                end,
                function(value)
                    return string.format("%.3f", tonumber(value) or 0)
                end
            )

            addLine(serviceDataLines, string.format(
                "prev sys: %d | factor: %.3f",
                #preventiveStressEntries,
                RMS_Config.MAINTENANCE.MAINTENANCE_PREVENTIVE_STRESS_REMOVE_MULTIPLIER
            ), {1, 0.95, 0.75, 1}, 0.95)

            local preventiveStressLines = packEntries(preventiveStressEntries, 2, {1, 0.95, 0.75, 1}, 0.95)
            for _, line in ipairs(preventiveStressLines) do
                table.insert(serviceDataLines, line)
            end
        end

        addLine(serviceDataLines, "sel: " .. listToString(pendingSelectedBreakdowns), {1, 0.95, 0.75, 1}, 0.95)
        addLine(serviceDataLines, "insp: " .. listToString(pendingInspectionQueue), {1, 0.95, 0.75, 1}, 0.95)
        addLine(serviceDataLines, "rep: " .. listToString(pendingRepairQueue), {1, 0.95, 0.75, 1}, 0.95)
    end

    local overviewSection = {title = "Overall", lines = overviewLines}
    local sections = {
        {title = isElectric and "Drive Temp" or "Engine Temp", lines = engineTempLines}
    }
    local implementLines = {}
    addLine(implementLines, string.format(
        "Implements: lowered: %s | hydraulic: %s | lifted: %s | hydraulicTargets: %d | liftedMass: %.1f | debris: %s",
        tostring(getDebugStateValue("isImplementLowered", spec.isImplementLowered == true) == true),
        tostring(getDebugStateValue("isImplementOperating", spec.isImplementOperating == true) == true),
        tostring(getDebugStateValue("isImplementLifted", spec.isImplementLifted == true) == true),
        tonumber(getDebugStateValue("hydraulicActiveTargetCount", spec.hydraulicActiveTargetCount)) or 0,
        tonumber(getDebugStateValue("liftedMass", spec.liftedMass)) or 0,
        tostring(getDebugStateValue("hasDebris", spec.hasDebris == true) == true)
    ), {1, 1, 1, 1}, 0.95)

    local implementNames = (debugData.implements or {}).names or {}
    local implementNamesText = string.format(
        "Attached (%d): %s",
        #implementNames,
        #implementNames > 0 and table.concat(implementNames, " | ") or "-"
    )
    for _, line in ipairs(wrapLineToWidth(implementNamesText, activeNormalSize * 0.95, panel.width - panel.padding * 2)) do
        addLine(implementLines, line, {1, 1, 1, 1}, 0.95)
    end

    if showTransmissionSection then
        table.insert(sections, {title = "CVT Temp", lines = transmissionTempLines})
    end

    table.insert(sections, {title = "Motor telemetry", lines = motorTelemetryLines})
    table.insert(sections, {title = "Battery", lines = batteryLines, showTitle = false})
    if isUnderService then
        table.insert(sections, {title = "Service Data", lines = serviceDataLines})
    end
    if #breakdownEntries > 0 then
        table.insert(sections, {title = "Active Breakdowns", lines = breakdownLines})
    end
    if #effectEntries > 0 then
        table.insert(sections, {title = "Active Effects", lines = effectLines})
    end

    if #aiCruiseLines > 0 then
        table.insert(sections, {title = "AI Worker", lines = aiCruiseLines})
    end

    table.insert(sections, {title = "Implements", lines = implementLines, showTitle = false})

    local systemColumns = math.min(8, math.max(#systemSections, 1))
    local systemGapX = 0.002
    local systemGapY = sectionGap * 0.16
    local systemLineIndent = 0.003
    local systemCardWidth = ((panel.width - panel.padding * 2) - (systemColumns - 1) * systemGapX) / systemColumns

    setTextBold(false)
    for _, section in ipairs(systemSections) do
        local wrappedLines = {}
        for _, line in ipairs(section.lines) do
            local lineSize = activeNormalSize * (line.sizeScale or 1.0)
            for _, part in ipairs(wrapLineToWidth(line.text or "", lineSize, systemCardWidth - systemLineIndent)) do
                table.insert(wrappedLines, {text = part, color = line.color, sizeScale = line.sizeScale})
            end
        end
        section.lines = wrappedLines
    end

    local systemRows = (#systemSections > 0) and math.ceil(#systemSections / systemColumns) or 0
    local rowHeights = {}
    local totalSystemHeight = 0

    for row = 1, systemRows do
        local rowMaxLines = 0
        for col = 1, systemColumns do
            local index = (row - 1) * systemColumns + col
            local section = systemSections[index]
            if section ~= nil then
                rowMaxLines = math.max(rowMaxLines, #section.lines)
            end
        end
        local rowHeight = (rowMaxLines + 1) * activeLineHeight
        rowHeights[row] = rowHeight
        totalSystemHeight = totalSystemHeight + rowHeight
    end
    if systemRows > 1 then
        totalSystemHeight = totalSystemHeight + (systemRows - 1) * systemGapY
    end

    local totalSectionHeight = 0
    local allLinearSections = {}
    table.insert(allLinearSections, overviewSection)
    for _, section in ipairs(sections) do
        table.insert(allLinearSections, section)
    end

    for _, section in ipairs(allLinearSections) do
        totalSectionHeight = totalSectionHeight + (math.max(#section.lines, 1) * activeLineHeight)
    end
    if #systemSections > 0 then
        totalSectionHeight = totalSectionHeight + sectionGap + totalSystemHeight + sectionGap
    end

    local dynamicHeight = (panel.padding * 2) + activeHeaderSize + totalSectionHeight + 0.02

    local textStartX = panel.x + panel.padding
    local currentY = panel.y + dynamicHeight - panel.padding

    local vehicleTypeCategory = self:getVehicleTypeCategoryLabel(vehicle)
    local headerText = string.format("%s %s | Type/Category: %s", vehicle:getFullName(), tostring(spec.year), vehicleTypeCategory)
    queueText(textStartX, currentY, activeHeaderSize, headerText, {1, 1, 1, 1}, true)
    currentY = currentY - activeHeaderSize - activeLineHeight

    ---Draws one debug section and returns the height it took
    local function drawSection(section)
        local sectionLines = section.lines or {}
        local showTitle = section.showTitle ~= false
        if #sectionLines == 0 then
            if showTitle then
                queueText(textStartX, currentY, activeNormalSize, section.title .. ":", {1, 1, 1, 1}, false)
            end
            currentY = currentY - activeLineHeight
            return
        end

        local firstLine = sectionLines[1]
        local firstColor = firstLine.color or {1, 1, 1, 1}
        local firstSize = activeNormalSize * (firstLine.sizeScale or 1.0)
        local firstText = firstLine.text or ""
        if showTitle then
            firstText = section.title .. ": " .. firstText
        end
        queueText(textStartX, currentY, firstSize, firstText, firstColor, false)
        currentY = currentY - activeLineHeight

        for index = 2, #sectionLines do
            local line = sectionLines[index]
            local lineText = line.text or ""
            local lineColor = line.color or {1, 1, 1, 1}
            local lineSize = activeNormalSize * (line.sizeScale or 1.0)
            queueText(textStartX, currentY, lineSize, lineText, lineColor, false)
            currentY = currentY - activeLineHeight
        end
    end

    drawSection(overviewSection)

    if #systemSections > 0 then
        currentY = currentY - sectionGap
        local gridStartX = textStartX
        local rowY = currentY

        for row = 1, systemRows do
            local rowHeight = rowHeights[row] or activeLineHeight
            for col = 1, systemColumns do
                local index = (row - 1) * systemColumns + col
                local section = systemSections[index]
                if section ~= nil then
                    local cardX = gridStartX + (col - 1) * (systemCardWidth + systemGapX)
                    local cardY = rowY
                    queueText(cardX, cardY, activeNormalSize, section.title .. ":", {1, 1, 1, 1}, false)

                    local cardLineY = cardY - activeLineHeight
                    for _, line in ipairs(section.lines) do
                        local lineText = line.text or ""
                        local lineColor = line.color or {1, 1, 1, 1}
                        local lineSize = activeNormalSize * (line.sizeScale or 1.0)
                        queueText(cardX + systemLineIndent, cardLineY, lineSize, lineText, lineColor, false)
                        cardLineY = cardLineY - activeLineHeight
                    end
                end
            end

            rowY = rowY - rowHeight
            if row < systemRows then
                rowY = rowY - systemGapY
            end
        end

        currentY = currentY - totalSystemHeight
        currentY = currentY - sectionGap
    end

    for _, section in ipairs(sections) do
        drawSection(section)
    end

    cache.lastUpdateTime = now
    cache.vehicle = vehicle
    cache.viewMode = debugViewMode
    cache.panel = {
        x = panel.x,
        y = panel.y,
        width = panel.width,
        height = dynamicHeight,
        color = {0, 0, 0, 0.7}
    }
    cache.commands = queuedCommands

    self:renderActiveVehicleDebugCache(cache)
end

---Draws the accumulated wear factor statistics
-- @param table vehicle vehicle
-- @param table spec vehicle spec
-- @param table factorStatsRaw raw factor statistics
-- @param table panel panel geometry
-- @param float activeHeaderSize header text size
-- @param float activeNormalSize body text size
-- @param float activeLineHeight line height
-- @param float sectionGap gap between two sections
function RMS_Hud:drawFactorStatsVehicleHUD(vehicle, spec, factorStatsRaw, panel, activeHeaderSize, activeNormalSize, activeLineHeight, sectionGap)
    local queuedCommands = {}

    ---Queues one text to draw at a position
    local function queueText(x, y, size, text, color, isBold)
        table.insert(queuedCommands, {
            x = x,
            y = y,
            size = size,
            text = text,
            color = color or {1, 1, 1, 1},
            bold = isBold == true
        })
    end

    ---Appends one line to a debug section
    local function addLine(target, text, color, sizeScale)
        table.insert(target, {
            text = text,
            color = color or {1, 1, 1, 1},
            sizeScale = sizeScale or 1.0
        })
    end

    ---Packs several entries onto as few lines as the limit allows
    local function packEntries(entries, maxPerLine, color, sizeScale)
        local lines = {}
        if #entries == 0 then
            addLine(lines, "-", color, sizeScale)
            return lines
        end

        local lineEntries = {}
        for i, entry in ipairs(entries) do
            table.insert(lineEntries, entry)
            if #lineEntries >= maxPerLine or i == #entries then
                addLine(lines, table.concat(lineEntries, " | "), color, sizeScale)
                lineEntries = {}
            end
        end

        return lines
    end

    ---Formats a ratio as a percentage
    local function toPct(value)
        return (tonumber(value) or 0) * 100
    end

    ---Returns the localized title of a system
    local function getSystemTitle(systemKey)
        local names = {
            engine = "Engine",
            transmission = "Transmission",
            hydraulics = "Hydraulics",
            cooling = "Cooling",
            electrical = "Electrical",
            chassis = "Chassis",
            fuel = "Fuel",
            pto = "PTO",
            materialFlow = "Material Flow"
        }
        if vehicle.spec_RealisticMechanicalSystems.isElectricVehicle then
            names.engine, names.fuel = "Electric motor", "Traction battery"
        end
        return names[systemKey] or tostring(systemKey)
    end

    local sections = {}
    factorStatsRaw = factorStatsRaw or {}
    local factorStats = {}
    for rawSystemKey, rawStats in pairs(factorStatsRaw) do
        if type(rawStats) == "table" then
            local normalizedKey = tostring(rawSystemKey)
            local loweredKey = string.lower(normalizedKey)
            if loweredKey == "materialflow" then
                normalizedKey = "materialFlow"
            end

            if factorStats[normalizedKey] == nil then
                factorStats[normalizedKey] = {}
            end

            for statKey, statValue in pairs(rawStats) do
                local numericValue = tonumber(statValue)
                if numericValue ~= nil and string.sub(tostring(statKey), 1, 1) ~= "_" then
                    factorStats[normalizedKey][statKey] = (tonumber(factorStats[normalizedKey][statKey]) or 0) + numericValue
                end
            end
        end
    end

    local orderedSystems = {
        "engine", "transmission", "hydraulics", "cooling",
        "electrical", "chassis", "fuel", "pto", "materialFlow"
    }

    local usedSystems = {}
    for _, systemKey in ipairs(orderedSystems) do
        local stats = factorStats[systemKey]
        if type(stats) == "table" then
            usedSystems[systemKey] = true
            local lines = {}
            addLine(lines, string.format(
                "total: %.3f%% | stress: %.3f%%",
                toPct(stats.total),
                toPct(stats.stress)
            ), {1, 1, 1, 1}, 0.95)

            local factorEntries = {}
            for key, value in pairs(stats) do
                if key ~= "total" and key ~= "stress" and key ~= "operatingHours" then
                    local numericValue = tonumber(value)
                    if numericValue ~= nil and math.abs(numericValue) > 0 then
                        table.insert(factorEntries, { key = key, value = numericValue })
                    end
                end
            end

            table.sort(factorEntries, function(a, b)
                return math.abs(a.value) > math.abs(b.value)
            end)

            if #factorEntries > 0 then
                addLine(lines, "", {1, 1, 1, 1}, 0.9)
            end

            for _, entry in ipairs(factorEntries) do
                local alias = tostring(entry.key)
                local accumulatedConditionDamage = tonumber(entry.value) or 0
                local lineText = string.format("%s: %.3f%%", alias, toPct(accumulatedConditionDamage))

                addLine(lines, lineText, {0.92, 0.96, 1.0, 1}, 0.9)
            end

            table.insert(sections, { title = getSystemTitle(systemKey), lines = lines })
        end
    end

    for systemKey, stats in pairs(factorStats) do
        if type(stats) == "table" and not usedSystems[systemKey] then
            local lines = {}
            addLine(lines, string.format(
                "total: %.3f%% | stress: %.3f%%",
                toPct(stats.total),
                toPct(stats.stress)
            ), {1, 1, 1, 1}, 0.95)
            table.insert(sections, { title = getSystemTitle(systemKey), lines = lines })
        end
    end

    local totalSectionHeight = 0
    for _, section in ipairs(sections) do
        totalSectionHeight = totalSectionHeight + (math.max(#section.lines, 1) * activeLineHeight)
    end
    totalSectionHeight = totalSectionHeight + (math.max(#sections - 1, 0) * sectionGap)

    local dynamicHeight = (panel.padding * 2) + activeHeaderSize + totalSectionHeight + 0.02
    local textStartX = panel.x + panel.padding
    local currentY = panel.y + dynamicHeight - panel.padding

    local vehicleTypeCategory = self:getVehicleTypeCategoryLabel(vehicle)
    local startOperatingHours = 0
    for _, stats in pairs(factorStatsRaw) do
        if type(stats) == "table" and tonumber(stats.operatingHours) ~= nil then
            startOperatingHours = tonumber(stats.operatingHours) or 0
            break
        end
    end
    local headerText = string.format("%s %s | Type/Category: %s [Factor Stats] | start.op.h: %.1fh",
        vehicle:getFullName(), tostring(spec.year), vehicleTypeCategory, startOperatingHours)
    queueText(textStartX, currentY, activeHeaderSize, headerText, {1, 1, 1, 1}, true)
    currentY = currentY - activeHeaderSize - activeLineHeight

    ---Draws one debug section and returns the height it took
    local function drawSection(section)
        local sectionLines = section.lines or {}
        if #sectionLines == 0 then
            queueText(textStartX, currentY, activeNormalSize, section.title .. ":", {1, 1, 1, 1}, false)
            currentY = currentY - activeLineHeight
            return
        end

        local firstLine = sectionLines[1]
        local firstColor = firstLine.color or {1, 1, 1, 1}
        local firstSize = activeNormalSize * (firstLine.sizeScale or 1.0)
        queueText(textStartX, currentY, firstSize, section.title .. ": " .. (firstLine.text or ""), firstColor, false)
        currentY = currentY - activeLineHeight

        for index = 2, #sectionLines do
            local line = sectionLines[index]
            local lineText = line.text or ""
            local lineColor = line.color or {1, 1, 1, 1}
            local lineSize = activeNormalSize * (line.sizeScale or 1.0)
            queueText(textStartX + 0.01, currentY, lineSize, lineText, lineColor, false)
            currentY = currentY - activeLineHeight
        end
    end

    for index, section in ipairs(sections) do
        drawSection(section)
        if index < #sections then
            currentY = currentY - sectionGap
        end
    end

    local now = g_currentMission.time
    local cache = self.activeVehicleDebugCache
    cache.lastUpdateTime = now
    cache.vehicle = vehicle
    cache.viewMode = "factorStats"
    cache.panel = {
        x = panel.x,
        y = panel.y,
        width = panel.width,
        height = dynamicHeight,
        color = {0, 0, 0, 0.7}
    }
    cache.commands = queuedCommands

    self:renderActiveVehicleDebugCache(cache)
end
