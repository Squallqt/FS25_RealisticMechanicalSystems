-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---Vehicle debug readings.
RMS_DebugReading = {}

local SEP = "  ·  "

local SYSTEMS = {
    {key = "engine", name = "Engine", electricName = "Electric motor", electricWord = "electric motor"},
    {key = "transmission", name = "Transmission", word = "transmission"},
    {key = "hydraulics", name = "Hydraulics", word = "hydraulic"},
    {key = "cooling", name = "Cooling"},
    {key = "electrical", name = "Electrical"},
    {key = "chassis", name = "Chassis"},
    {key = "fuel", name = "Fuel", electricName = "Traction battery", word = "fuel"},
    {key = "pto", name = "PTO", word = "pto"}
}

local ACRONYMS = {cvt = "CVT", ecu = "ECU", nox = "NOx", adblue = "AdBlue", hv = "HV", dcdc = "DC/DC", pto = "PTO", gcw = "GCW", ["4wd"] = "4WD"}

---Writes a number with its thousands grouped
local function grouped(value)
    local text = tostring(math.floor(value + 0.5))
    while true do
        local replaced, count = text:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
        text = replaced
        if count == 0 then
            return text
        end
    end
end

---Writes a share in percent
local function pct(value)
    return string.format("%d %%", math.floor(value * 100 + 0.5))
end

---Writes a l10n key of an option as its plain words
local function plainKey(key)
    local words = tostring(key):gsub("^rms_spec_", ""):gsub("^%a+_types?_", ""):gsub("^%a+_", "")
    return (words:gsub("_", " "))
end

local function perMinute(value)
    local rounded = math.floor((value or 0) * 600 + 0.5) / 10
    return string.format("%.1f", rounded == 0 and 0 or rounded)
end

local function signedPerMinute(value)
    local rounded = math.floor((value or 0) * 600 + 0.5) / 10
    return rounded == 0 and "0.0" or string.format("%+.1f", rounded)
end

local function temperature(value)
    return value == -99 and "no reading yet" or string.format("%.1f °C", value)
end

local function getPowerToMass(ratio, basis)
    return string.format("%.1f hp per tonne %s", ratio, basis == "gcw" and "in all" or "towed")
end

local function getServiceLevel(vehicle, systemKey)
    for _, clock in ipairs(vehicle:getServiceClocks()) do
        for _, covered in ipairs(clock.systems) do
            if covered == systemKey then
                return vehicle:getServiceClockLevel(clock)
            end
        end
    end
    return 1
end

---Returns the level of the fluid a system runs on
local function getFluidLevel(vehicle, spec, systemKey)
    if systemKey == "engine" then
        return spec.engineOilLevel
    elseif systemKey == "transmission" then
        return spec.transmissionOilLevel
    end
    return RMS_Fluids.getLevel(vehicle, "hydraulicFluid")
end

local function getHydraulicOilTemperature(spec)
    if RMS_Thermal.getHasSeparateHydraulicCircuit(spec) then
        return spec.rawHydraulicTemperature
    end
    return spec.rawTransmissionTemperature
end

local CAUSES = {
    sf = {"Service overdue", "service", function(_, _, vehicle, systemKey) return "service " .. pct(getServiceLevel(vehicle, systemKey)) end},
    mlf = {"Engine load", "load", function(f) return pct(f.dynamicMotorLoad) .. " load" end},
    aicf = {"Air filter", "air filter", function(_, spec) return pct(spec.airFilterClogging) .. " clogged" end},
    cmf = {"Cold engine worked", "cold", function(f) return string.format("%.0f °C engine", f.engineTemperature) end},
    flf = {"Low fluid", "low fluid", function(_, spec, vehicle, systemKey) return pct(getFluidLevel(vehicle, spec, systemKey)) .. " full" end},
    hmf = {"Engine overheating", "overheating", function(f) return string.format("%.0f °C engine", f.engineTemperature) end},
    pof = {"Pull overload", "pull", function(f) return string.format("%.0f s over its limit", f.pullOverloadTimer) end},
    htf = {"Heavy trailer", "trailer", function(f) return getPowerToMass(f.heavyTrailerMassRatio, f.heavyTrailerMassBasis) end},
    lf = {"Lugging", "lugging", function(_, _, vehicle) return string.format("%.0f rpm", vehicle:getMotor():getLastModulatedMotorRpm()) end},
    wsf = {"Wheel slip", "slip", function(_, spec) return string.format("ground grip %.2f", spec.avgTireGroundFrictionCoeff) end},
    dwf = {"Driveline windup", "windup", function(_, spec) return pct(spec.drivetrain.windupStress) .. " windup" end},
    ctf = {"Cold transmission oil", "cold oil", function(_, spec) return string.format("%.0f °C oil", spec.transmissionTemperature) end},
    hotf = {"Hot transmission oil", "hot oil", function(_, spec) return string.format("%.0f °C oil", spec.transmissionTemperature) end},
    hlf = {"Heavy lift", "heavy lift", function(_, spec) return string.format("lifting %.1f t", spec.raisingMass) end},
    vf = {"Vibration", "vibration", function(f) return string.format("bumps %.2f", f.vibSignal) end},
    cof = {"Cold hydraulic oil", "cold oil", function(_, spec) return string.format("%.0f °C oil", getHydraulicOilTemperature(spec)) end},
    hof = {"Hot hydraulic oil", "hot oil", function(_, spec) return string.format("%.0f °C oil", getHydraulicOilTemperature(spec)) end},
    hfbf = {"Hydraulic filter bypass", "filter bypass", function(_, spec) return "filter " .. pct(spec.hydraulicFilterClogging) end},
    tfbf = {"Gearbox filter bypass", "filter bypass", function(_, spec) return "filter " .. pct(spec.transmissionFilterClogging) end},
    hcf = {"High cooling demand", "cooling demand", function(_, spec) return "thermostat " .. pct(spec.thermostatState) end},
    ohf = {"Overheating", "overheating", function(_, spec) return string.format("%.0f °C engine", spec.engineTemperature) end},
    csf = {"Cold shock", "cold shock", function(_, spec) return string.format("%.0f °C engine", spec.engineTemperature) end},
    wef = {"Weather exposure", "weather", function() return string.format("weather x%.2f", RMS_Main.currentWeatherFactor) end},
    ltf = {"Lights on", "lights", function(_, spec) return string.format("%.0f W lit", spec.electricalBalance.loads.lights * spec.systemVoltageV) end},
    crf = {"Cranking", "cranking", function(f) return string.format("%.1f s cranking", f.crankingTimer / 1000) end},
    lubf = {"Greasing due", "greasing", function(_, spec) return "grease left " .. pct(spec.lubricationLevel) end},
    slf = {"Steering load", "steering", function(f) return pct(f.steerTravelRate) .. " of the lock a second" end},
    tif = {"Impacts", "impacts", function(f) return string.format("%d %s", f.impactCount, f.impactCount == 1 and "impact" or "impacts") end},
    bmf = {"Braking mass", "braking", function(f) return getPowerToMass(f.brakeMassRatio, f.brakeMassBasis) end},
    pbf = {"Driving on the park brake", "park brake", function(_, _, vehicle) return string.format("%.1f km/h", vehicle:getLastSpeed()) end},
    lff = {"Low fuel", "low fuel", function(f) return pct(f.fuelLevel) .. " fuel" end},
    cff = {"Cold fuel", "cold fuel", function(f) return string.format("%.0f °C fuel", f.fuelTemperature) end},
    idf = {"Idling deposits", "idling", function(f) return string.format("%.0f s idling", f.idleTimer) end},
    hpf = {"High injection pressure", "injection", function(f) return "fuel " .. pct(f.currentFuelUsageRatio) .. " of full power" end},
    ddf = {"Deep discharge", "discharge", function(f) return pct(f.fuelLevel) .. " charge" end},
    hdf = {"High draw", "high draw", function(f) return "draw " .. pct(f.currentFuelUsageRatio) .. " of full power" end},
    bhf = {"Pack heat", "pack heat", function(_, spec) return string.format("%.0f °C pack", spec.tractionBatteryTempC) end},
    idfg = {"Sudden damage", "damage", function() return "" end},
    plf = {"PTO load", "PTO load", function(_, spec) return pct(spec.ptoUtilization) .. " of its power" end},
    pef = {"PTO engagements", "engagements", function(_, spec) return string.format("%d engagements", spec.ptoEngagementCount) end},
    prf = {"PTO raised", "PTO raised", function(_, spec) return string.format("%.0f rpm, tool raised", spec.ptoRpm) end}
}

local SOURCES = {"wear", "poor parts", "quick fix"}

-- @param string partId breakdown id of the part
-- @param string? systemWord word its system drops
-- @return string name
function RMS_DebugReading.getPartName(partId, systemWord)
    local key = RMS_Breakdowns.BreakdownRegistry[partId].part:gsub("^rms_breakdowns_part_", "")
    if systemWord ~= nil then
        local prefix = systemWord:gsub(" ", "_") .. "_"
        if key:sub(1, #prefix) == prefix then
            key = key:sub(#prefix + 1)
        end
    end
    key = key:gsub("four_wd", "4wd")
    local words = {}
    for word in key:gmatch("[^_]+") do
        table.insert(words, ACRONYMS[word] or word)
    end
    local name = table.concat(words, " ")
    return name:sub(1, 1):upper() .. name:sub(2)
end

---Names the system of a vehicle
local function getSystemName(system, isElectric)
    return isElectric and system.electricName or system.name
end

local GEARBOXES = {manual = "manual gearbox", manual_powershift = "semi-powershift", automatic = "automatic gearbox",
    powershift = "powershift", variable = "CVT"}

local function getKind(vehicle, spec)
    local profile = RMS_Fluids.getProfileName(vehicle)
    local parts = {profile:sub(1, 1) .. (profile:sub(2):lower():gsub("_", " "))}
    local gearbox = GEARBOXES[vehicle:getTransmissionType()]
    if gearbox ~= nil and not spec.isElectricVehicle then
        table.insert(parts, gearbox)
    end
    if spec.isElectricVehicle then
        table.insert(parts, "electric")
    else
        local energy = vehicle.spec_motorized.consumersByFillTypeName.METHANE ~= nil and "methane" or "diesel"
        table.insert(parts, energy .. (spec.hasParticulateFilter and " Stage V" or ""))
    end
    return table.concat(parts, SEP)
end

local function countFaults(vehicle, spec)
    local R = RealisticMechanicalSystems
    local count = 0
    for _, entry in ipairs(spec.maintenanceLog) do
        if entry.type == R.STATUS.REPAIR or entry.type == R.STATUS.OVERHAUL then
            count = count + #entry.conditionData.selectedBreakdowns
        end
    end
    for _, breakdown in pairs(vehicle:getActiveBreakdowns()) do
        if breakdown.source ~= R.BREAKDOWN_SOURCES.QUICK_FIX then
            count = count + 1
        end
    end
    return count
end

---Returns the share of its new peak power the engine gives now
-- @param table motor vehicle motor
-- @return float share peak power now over the peak of its new torque curve
local function getPowerShare(motor)
    local peak = 0
    for rpm = motor.minRpm, motor.maxRpm, 10 do
        peak = math.max(peak, motor:getTorqueCurveValue(rpm) * rpm)
    end
    return peak * math.pi / 30 / motor.peakMotorPower
end

---Reads the title line, the life and the service of the machine
local function readHeader(vehicle, spec, reading)
    local R = RealisticMechanicalSystems
    reading.title = table.concat({vehicle:getFullName(), tostring(spec.year), getKind(vehicle, spec)}, SEP)

    local lifeUsed = R.getRealOperatingHours(vehicle) * RMS_Config.CORE.BASE_SYSTEMS_WEAR
    local report = R.getReferenceReport(vehicle)
    local reportText = "none"
    if report ~= nil then
        local hours, isOutdated = vehicle:getInspectionReportAge()
        local kind = report.type == R.STATUS.INSPECTION and plainKey(report.optionOne) .. " inspection" or plainKey(report.type)
        reportText = string.format("%s %.1f h ago%s", kind, hours, isOutdated and " (out of date)" or "")
    end
    local power = RMS_Fluids.getEnginePower(vehicle)
    local share = getPowerShare(vehicle:getMotor())
    reading.facts = {
        {"Power", string.format("new %.0f hp = %.0f kW  ·  now %.0f hp = %.0f kW (%s)", power, power / RMS_Fluids.KW_TO_HP,
            power * share, power * share / RMS_Fluids.KW_TO_HP, pct(share))},
        {"Hour meter", string.format("%.1f h of play = %s h of work", vehicle:getFormattedOperatingTime(), grouped(lifeUsed * RMS_Config.CORE.MACHINE_LIFE_HOURS))},
        {"Life used", pct(lifeUsed)},
        {"Condition", pct(vehicle:getConditionLevel())},
        {"Reliability", string.format("%.2f", spec.reliability)},
        {"Faults so far", string.format("%d (for reference, a powershift tractor sees about 16 in its life)", countFaults(vehicle, spec))},
        {"Report", reportText}
    }

    local names = {engine = "Engine oil", transmission = "Transmission", hydraulic = "Hydraulic", coolant = "Coolant"}
    local SOURCE = RMS_ProductionYear.SOURCE
    local provenance = "unknown (default)"
    if spec.yearSource == SOURCE.FILE then
        provenance = "vehicle file"
    elseif spec.yearSource == SOURCE.REFERENCE then
        provenance = "RMS reference"
    end
    local built = string.format("%d, %s", spec.year, provenance)
    if not spec.isElectricVehicle then
        built = built .. string.format("  ·  engine oil every %d h", R.getServiceProgramHours(vehicle, "engine"))
    end
    reading.service = {{"Built", built}}
    for _, clock in ipairs(vehicle:getServiceClocks()) do
        local used, interval = vehicle:getServiceClockHours(clock)
        local level = string.format("level %s, due at %s", pct(vehicle:getServiceClockLevel(clock)),
            pct(RMS_Config.CORE.SERVICE_EXPIRED_THRESHOLD))
        local left = {}
        if interval < math.huge then
            table.insert(left, string.format("%.1f h", interval - used))
        end
        if clock.months ~= nil then
            local elapsed = math.max(vehicle.age - (spec.serviceCalendar[clock.key] or vehicle.age), 0)
            table.insert(left, string.format("%d months", clock.months - elapsed))
        end
        local isDue = vehicle:getServiceClockLevel(clock) <= RMS_Config.CORE.SERVICE_EXPIRED_THRESHOLD
        local text = isDue and "overdue  (" .. level .. ")" or #left > 0 and table.concat(left, " or ") .. " left  (" .. level .. ")" or level
        table.insert(reading.service, {names[clock.key], text})
    end
    table.insert(reading.service, {"Greasing", spec.isVehicleNeedLubricate and pct(spec.lubricationLevel) or "not needed"})
end

---Writes a system's lifetime wear and the share of each cause
local function getSince(stats)
    local total = stats.total
    if total <= 0 then
        return "wear taken 0 %"
    end
    local causes = 0
    for alias, wear in pairs(stats) do
        if CAUSES[alias] ~= nil and wear > 0 then
            causes = causes + wear
        end
    end
    local whole = math.max(total, causes)
    local shares = {}
    for alias, wear in pairs(stats) do
        if CAUSES[alias] ~= nil and wear / whole >= 0.005 then
            table.insert(shares, {CAUSES[alias][2], wear / whole})
        end
    end
    table.sort(shares, function(a, b) return a[2] > b[2] end)
    local parts = {"wear taken " .. pct(total), "normal " .. pct((whole - causes) / whole)}
    for index = 1, math.min(#shares, 2) do
        table.insert(parts, shares[index][1] .. " " .. pct(shares[index][2]))
    end
    return table.concat(parts, SEP)
end

local function readSystems(vehicle, spec, reading)
    local rateScale = RMS_Config.CORE.BASE_SYSTEMS_WEAR * 100
    reading.systems, reading.wearNow = {}, {}
    for _, system in ipairs(SYSTEMS) do
        local parts = spec.systemParts[system.key]
        if parts ~= nil and #parts > 0 and spec.systems[system.key].enabled ~= false then
            local word = spec.isElectricVehicle and system.electricWord or system.word
            local rows, order = {}, {}
            for index, partId in ipairs(parts) do
                local wear = spec.partWear[partId]
                local breakdown = spec.activeBreakdowns[partId]
                local b10 = RMS_Utils.getPartB10Wear(partId)
                local row = {
                    name = RMS_DebugReading.getPartName(partId, word),
                    wear = wear,
                    chance = RMS_Utils.getPartFailureChance(partId, wear, wear + RMS_Utils.getPartRiskHorizon(partId)),
                    isWorn = RMS_Utils.getIsPartWorn(partId, wear),
                    stage = breakdown ~= nil and breakdown.stage or 0,
                    tick = b10 <= 1 and b10 or -1
                }
                order[row] = index
                table.insert(rows, row)
            end
            table.sort(rows, function(a, b)
                if a.stage ~= b.stage then return a.stage > b.stage end
                if a.isWorn ~= b.isWorn then return a.isWorn end
                if a.chance ~= b.chance then return a.chance > b.chance end
                if a.wear ~= b.wear then return a.wear > b.wear end
                return order[a] < order[b]
            end)

            local name = getSystemName(system, spec.isElectricVehicle)
            local factors = spec.systemWearNow[system.key]
            table.insert(reading.systems, {
                name = name,
                condition = spec.systems[system.key].condition,
                risk = RMS_Utils.getSystemRiskRatio(vehicle, system.key, spec.partWear),
                wearing = (spec.systemWearRateNow[system.key] or 0) * rateScale,
                normal = rateScale / spec.reliability,
                since = getSince(spec.factorStats[system.key]),
                parts = rows
            })

            if factors ~= nil then
                local causes = {}
                for factorName, value in pairs(factors) do
                    local alias = RealisticMechanicalSystems.FACTOR_STATS_ALIASES[factorName]
                    if alias ~= nil and value > 0 and CAUSES[alias] ~= nil then
                        local cause = CAUSES[alias]
                        table.insert(causes, {label = cause[1], measure = cause[3](factors, spec, vehicle, system.key),
                            rate = value * rateScale / spec.reliability})
                    end
                end
                if #causes > 0 then
                    table.sort(causes, function(a, b) return a.rate > b.rate end)
                    table.insert(reading.wearNow, {system = name, causes = causes})
                end
            end
        end
    end
end

---Returns a fault name; a fault without a system is named by its id
local function getFaultName(breakdownId, systemWord)
    if RMS_Breakdowns.BreakdownRegistry[breakdownId].system == nil then
        return breakdownId:sub(1, 1) .. breakdownId:sub(2):lower():gsub("_", " ")
    end
    return RMS_DebugReading.getPartName(breakdownId, systemWord)
end

---Finds the system a breakdown belongs to
local function getBreakdownSystem(definition, isElectric)
    for _, system in ipairs(SYSTEMS) do
        if RMS_Utils.getSystemKey(RealisticMechanicalSystems.SYSTEMS, definition.system) == system.key then
            return getSystemName(system, isElectric), isElectric and system.electricWord or system.word
        end
    end
    return "Machine", nil
end

---Reads the faults, the lamps, the display, the codes and the effects
local function readFaults(vehicle, spec, reading)
    local R = RealisticMechanicalSystems
    local isInWorkshop = spec.currentState ~= R.STATUS.READY
    reading.faults = {}
    for breakdownId, breakdown in pairs(vehicle:getActiveBreakdowns()) do
        local definition = RMS_Breakdowns.BreakdownRegistry[breakdownId]
        local systemName, word = getBreakdownSystem(definition, spec.isElectricVehicle)
        local stageCount = #definition.stages
        local info = {systemName, string.format("severity %d of %d", breakdown.stage, stageCount)}
        if breakdown.warrantyServiceOverdue then table.insert(info, "warranty refused: service overdue when fault occurred") end
        if breakdown.usedPartHours ~= nil then
            table.insert(info, string.format("donor %d h", RealisticMechanicalSystems.getUsedPartMeterHours(breakdown.usedPartHours)))
        end
        if breakdown.branch ~= nil and breakdown.branch > 0 then
            table.insert(info, "way " .. breakdown.branch)
        end
        table.insert(info, breakdown.isVisible and "seen" or "hidden")
        table.insert(info, SOURCES[breakdown.source])
        table.insert(info, breakdown.isSelectedForRepair and "selected for repair" or "not selected")

        local progress = R.getStageProgress(definition, breakdown)
        local nextText
        if isInWorkshop then
            nextText = "held while in the workshop"
        elseif breakdown.isActive == false then
            nextText = string.format("resumes in %.1f h", breakdown.resumeTimer / 3600000)
        elseif breakdown.stage >= stageCount then
            nextText = "at its worst"
        else
            local duration = R.getStageDuration(definition.stages[breakdown.stage])
            if duration == nil then
                nextText = "does not progress"
            else
                local left = (duration - breakdown.progressTimer) / (1 + (spec.partStrain[breakdownId] or 0)) / 3600000
                nextText = string.format("%s to severity %d, about %.1f h", pct(progress), breakdown.stage + 1, left)
            end
        end
        table.insert(reading.faults, {
            name = getFaultName(breakdownId, word),
            info = table.concat(info, SEP),
            progress = progress,
            next = nextText,
            isSeen = breakdown.isVisible == true
        })
    end
    table.sort(reading.faults, function(a, b) return a.name < b.name end)

    local colours = {[RMS_Breakdowns.COLORS.CRITICAL] = "red", [RMS_Breakdowns.COLORS.WARNING] = "amber",
        [RMS_Breakdowns.COLORS.COOL] = "blue", [RMS_Breakdowns.COLORS.DEFAULT] = "grey"}
    local lamps = {}
    for indicatorId, indicator in pairs(spec.activeIndicators) do
        table.insert(lamps, string.format("%s (%s)", indicatorId:gsub("(%l)(%u)", "%1 %2"):lower(), colours[indicator.color]))
    end
    table.sort(lamps)
    local shown = {}
    for key in pairs(spec.displayedFaultCodes or {}) do
        local spn, fmi = key:match("^(%d+) (%d+)$")
        table.insert(shown, string.format("SPN %s FMI %s", spn, fmi))
    end
    table.sort(shown)
    local readCodes = RMS_DiagnosticTool.readFaultCodes(vehicle)
    local codes = {}
    for _, entry in ipairs(readCodes or {}) do
        local code = entry.spn ~= nil and string.format("SPN %d FMI %d", entry.spn, entry.fmi)
            or getBreakdownSystem(RMS_Breakdowns.BreakdownRegistry[entry.breakdownId], spec.isElectricVehicle) .. " lamp, no code"
        table.insert(codes, code .. (spec.activeBreakdowns[entry.breakdownId].isVisible and "" or " (hidden)"))
    end
    local effects = {}
    for effectId, effect in pairs(spec.activeEffects) do
        if type(effect.value) == "number" then
            local key = effectId:lower():gsub("_modifier$", ""):gsub("_effect$", "")
            local words = {}
            for word in key:gmatch("[^_]+") do
                table.insert(words, ACRONYMS[word] or word)
            end
            table.insert(effects, string.format("%s %.2f", table.concat(words, " "), effect.value))
        end
    end
    table.sort(effects)
    reading.alerts = {
        {"Lamps", #lamps > 0 and table.concat(lamps, SEP) or "none"},
        {"Display", #shown > 0 and table.concat(shown, SEP) or "none"},
        {"Codes", readCodes == nil and "unreadable, battery cut off" or #codes > 0 and table.concat(codes, SEP) or "none"},
        {"Effects", #effects > 0 and table.concat(effects, SEP) or "none"}
    }
end

local function readWork(spec, reading)
    local R = RealisticMechanicalSystems
    reading.work = {}
    if spec.currentState == R.STATUS.READY then
        return
    end
    local places = {[R.WORKSHOP.DEALER] = "at the dealer", [R.WORKSHOP.MOBILE] = "mobile workshop", [R.WORKSHOP.OWN] = "farm workshop"}
    local options = {plainKey(spec.currentState), places[spec.workshopType]}
    for _, option in ipairs({spec.serviceOptionOne, spec.serviceOptionTwo}) do
        if option ~= nil and option ~= "" and option ~= "NONE" then
            table.insert(options, plainKey(option))
        end
    end
    local progress = spec.pendingProgressTotalTime > 0 and spec.pendingProgressElapsedTime / spec.pendingProgressTotalTime or 0
    table.insert(reading.work, {"Work", table.concat(options, SEP) .. ", then " .. plainKey(spec.plannedState)})
    local queue = spec.currentState == R.STATUS.REPAIR and spec.pendingRepairQueue
        or (spec.currentState == R.STATUS.INSPECTION or spec.currentState == R.STATUS.MAINTENANCE) and spec.pendingInspectionQueue or {}
    local done = #queue > 0 and string.format("  ·  %d of %d done", spec.pendingProgressStepIndex, #queue) or ""
    table.insert(reading.work, {"Progress", string.format("%s  ·  %.1f h left%s", pct(progress),
        (spec.pendingProgressTotalTime - spec.pendingProgressElapsedTime) / 3600000, done)})
    table.insert(reading.work, {"Price", g_i18n:formatMoney(spec.pendingServicePrice or 0)})
    for _, queue in ipairs({{"Repairs", spec.pendingRepairQueue}, {"Inspections", spec.pendingInspectionQueue}}) do
        local names = {}
        for _, breakdownId in ipairs(queue[2]) do
            table.insert(names, getFaultName(breakdownId))
        end
        table.insert(reading.work, {queue[1], #names > 0 and table.concat(names, SEP) or "none"})
    end
    local renewed = {}
    for partId, startWear in pairs(spec.pendingOverhaulPartStart or {}) do
        table.insert(renewed, string.format("%s %s to %s", RMS_DebugReading.getPartName(partId), pct(startWear),
            pct(spec.pendingOverhaulPartTarget[partId])))
    end
    table.sort(renewed)
    if #renewed > 0 then
        table.insert(reading.work, {"Parts renewed", table.concat(renewed, SEP)})
    end
    local clocks = {}
    for key, start in pairs(spec.pendingServiceClockStart or {}) do
        table.insert(clocks, string.format("%s %s to %s", key, pct(start), pct(spec.pendingServiceClockTarget[key])))
    end
    table.sort(clocks)
    if #clocks > 0 then
        table.insert(reading.work, {"Service to", table.concat(clocks, SEP)})
    end
end

local function collectToolNames(vehicle, names)
    if vehicle.getAttachedImplements == nil then
        return names
    end
    for _, implement in ipairs(vehicle:getAttachedImplements()) do
        table.insert(names, implement.object:getFullName())
        collectToolNames(implement.object, names)
    end
    return names
end

---Writes what the reversible fan does, on its timer or from the cab
local function getReversibleFanText(spec)
    local fan = RMS_Config.THERMAL.REVERSIBLE_FAN
    if not spec.hasReversibleFan then
        return ""
    elseif spec.fanReversalTime > 0 then
        return "  ·  fan reversing"
    elseif spec.year < fan.AUTO_MIN_YEAR then
        return "  ·  reversible fan, from the cab only"
    end
    return string.format("  ·  reversible fan, next in %d min", math.ceil((fan.AUTO_INTERVAL_MS - spec.fanRunningSinceReversal) / 60000))
end

local function readEngineRows(vehicle, spec, rows)
    local heat = spec.engineHeatBalance
    table.insert(rows, {"Engine", string.format("%s  ·  thermostat %s  ·  fan %s%s", temperature(spec.engineTemperature),
        pct(spec.thermostatState), pct(heat.fan or 0), getReversibleFanText(spec))})
    table.insert(rows, {"Heat", string.format("net %s °C/min  ·  engine %s  ·  radiator %s  ·  driving %s  ·  air %s",
        signedPerMinute((heat.totalHeat or 0) - (heat.totalCooling or 0)), signedPerMinute(heat.totalHeat),
        signedPerMinute(-(heat.radiatorCooling or 0)), signedPerMinute(-(heat.speedCooling or 0)), signedPerMinute(-(heat.convectionCooling or 0)))})
end

---Writes an oil as the model heats it, then as its gauge follows it
local function getOilTemperature(raw, gauge)
    return raw == -99 and temperature(-99) or string.format("%s (gauge %s)", temperature(raw), temperature(gauge))
end

local function readOilRows(spec, rows)
    local capacities = spec.fluidCapacities or {}
    local isCommon = spec.hasCommonSump == true
    if (capacities.transmissionOil or 0) > 0 and (spec.systems.transmission.enabled ~= false or isCommon and spec.systems.hydraulics.enabled ~= false) then
        local oil = spec.transmissionHeatBalance
        local gearsHeat = (oil.totalHeat or 0) - (oil.idleHeat or 0) - (oil.ptoHeat or 0) - (oil.hydraulicHeat or 0)
        table.insert(rows, {"Gearbox oil", string.format("%s  ·  thermostat %s%s  ·  net %s °C/min  ·  heat %s (idling %s, gears %s, "
            .. "PTO %s, hydraulics %s)  ·  cooler %s  ·  driving %s  ·  air %s", getOilTemperature(spec.rawTransmissionTemperature,
            spec.transmissionTemperature), pct(spec.transmissionThermostatState), isCommon and "  ·  shared with the hydraulics" or "",
            signedPerMinute((oil.totalHeat or 0) - (oil.totalCooling or 0)), signedPerMinute(oil.totalHeat), perMinute(oil.idleHeat),
            perMinute(gearsHeat), perMinute(oil.ptoHeat), perMinute(oil.hydraulicHeat), signedPerMinute(-(oil.coolerCooling or 0)),
            signedPerMinute(-(oil.speedCooling or 0)), signedPerMinute(-(oil.convectionCooling or 0)))})
    end
    if RMS_Thermal.getHasSeparateHydraulicCircuit(spec) then
        table.insert(rows, {"Hydraulic oil", getOilTemperature(spec.rawHydraulicTemperature, spec.hydraulicTemperature)})
    end
end

---Reads the battery of the 12 V circuit and its balance
local function readBatteryRows(vehicle, spec, rows)
    local balance = spec.electricalBalance
    local rating = spec.electricalRating
    local label = spec.isElectricVehicle and "12 V battery" or "Battery"
    if balance == nil then
        table.insert(rows, {label, string.format("%.1f V  ·  %s", spec.systemVoltageV, pct(spec.batterySoc))})
        return
    end
    -- Suppress negative zero after rounding.
    local batteryA = math.floor(balance.batteryA * 10 + 0.5) / 10
    table.insert(rows, {label, string.format("%.1f V  ·  %s (%.0f of %.0f Ah)  ·  %+.1f A", spec.systemVoltageV, pct(spec.batterySoc),
        spec.batterySoc * balance.capacityAh, balance.capacityAh, batteryA == 0 and 0 or batteryA)})
    table.insert(rows, {"At rest", string.format("%.2f V  ·  ambient %.0f °C  ·  cold holds back %s",
        RMS_Electrical.getRestingVoltage(rating, spec.batterySoc), balance.ambientC, pct(balance.floorSoc))})
    local partner = spec.externalPowerConnection
    table.insert(rows, {"Parked draw", string.format("%.0f mA  ·  isolator %s  ·  %s  ·  %s", RMS_Electrical.getRestingDraw(spec) * 1000,
        spec.batteryIsolated and "open" or "closed", partner ~= nil and "cables to " .. partner:getFullName() or "no cables",
        balance.chargerOutA > 0 and string.format("charger %.1f A", balance.chargerOutA) or "no charger")})
    local loads = balance.loads
    if spec.isElectricVehicle then
        table.insert(rows, {"Currents", string.format("converter up to %.1f A  ·  base %.1f A  ·  cab %.1f A  ·  lights %.1f A",
            balance.generatorA, loads.base, loads.cab, loads.lights)})
    else
        table.insert(rows, {"Currents", string.format("alternator up to %.1f A  ·  base %.1f A  ·  cab %.1f A  ·  lights %.1f A  ·  starter %.0f A  ·  preheat %.0f A",
            balance.generatorA, loads.base, loads.cab, loads.lights, loads.starter, loads.preheat)})
        table.insert(rows, {"Last start", string.format("%.1f V under the starter  ·  %s cranking speed",
            RMS_Electrical.getStartingVoltage(vehicle), pct(RMS_Electrical.getCrankingSpeed(vehicle)))})
        table.insert(rows, {"Resistance", string.format("battery %.1f mOhm  ·  circuit %.1f mOhm", balance.resistanceOhm * 1000, balance.circuitOhm * 1000)})
    end
end

local function readExhaustRows(spec)
    local smoke = spec.exhaustSmoke
    local smokeText = not smoke.isActive and "no smoke" or string.format("black %s  ·  blue %s  ·  white %s  ·  opacity %s  ·  vapour %s",
        pct(smoke.soot), pct(smoke.oil), pct(smoke.unburnt), pct(smoke.opacity), pct(smoke.vapourOpacity or 0))
    local gas = not smoke.isActive and "no plume" or string.format("%.0f °C at %.1f m/s  ·  wind %.1f m/s  ·  sheltered %s%s",
        smoke.gasTemperature, smoke.exitSpeed, smoke.windSpeed, pct(smoke.pipeShelter), smoke.isOverridden and "  ·  override" or "")
    return {"Smoke", smokeText}, {"Exhaust gas", gas}
end

local function getGear(motor)
    if motor.forwardGears == nil and motor.backwardGears == nil then
        local directions = {D = "forward", R = "reverse", N = "neutral"}
        return directions[motor:getGearToDisplay(false)]
    end
    local group, hasGroups = motor:getGearGroupToDisplay(false)
    local shifting = motor.gearShiftMode == VehicleMotor.SHIFT_MODE_AUTOMATIC and "automatic shifting"
        or motor.gearShiftMode == VehicleMotor.SHIFT_MODE_MANUAL_CLUTCH and "manual with clutch" or "manual shifting"
    return string.format("gear %s%s, %s", motor:getGearToDisplay(false), hasGroups and " in range " .. group or "", shifting)
end

---Reads the rows of the machine itself, only those it has
local function readMachine(vehicle, spec, reading)
    local rows = {}
    if spec.isElectricVehicle then
        local heat = spec.engineHeatBalance
        table.insert(rows, {"Drive", string.format("%s  ·  net %s °C/min  ·  motor %s  ·  cooling %s  ·  fan %s", temperature(spec.engineTemperature),
            signedPerMinute((heat.totalHeat or 0) - (heat.totalCooling or 0)), signedPerMinute(heat.totalHeat),
            signedPerMinute(-(heat.totalCooling or 0)), pct(heat.fan or 0))})
    else
        readEngineRows(vehicle, spec, rows)
    end
    readOilRows(spec, rows)

    local levels = {}
    if RMS_Fluids.hasCircuit(vehicle, "engineOil") then table.insert(levels, "oil " .. pct(spec.engineOilLevel)) end
    if spec.systems.cooling.enabled ~= false then table.insert(levels, "coolant " .. pct(spec.coolantLevel)) end
    if spec.systems.transmission.enabled ~= false then table.insert(levels, "transmission " .. pct(spec.transmissionOilLevel)) end
    if spec.systems.hydraulics.enabled ~= false then table.insert(levels, "hydraulic " .. pct(RMS_Fluids.getLevel(vehicle, "hydraulicFluid"))) end
    table.insert(rows, {"Levels", table.concat(levels, SEP)})
    local isRunning = vehicle:getIsMotorStarted()
    local stopped = spec.isElectricVehicle and "motor off" or "engine stopped"
    local losses = {}
    if spec.systems.engine.enabled and not spec.isElectricVehicle then
        table.insert(losses, string.format("oil burnt %.2f L/h of play", RMS_Consumables.getEngineOilBurnRate(vehicle) * RMS_Fluids.getCapacity(vehicle, "engineOil")))
    end
    for _, leak in ipairs({{"coolant", "coolant", spec.coolantLeakRate}, {"transmission", "transmissionOil", spec.transmissionOilLeakRate},
        {"hydraulic", "hydraulicFluid", spec.hydraulicFluidLeakRate}}) do
        if leak[3] > 0 then
            table.insert(losses, string.format("%s leak %.2f L/h of play", leak[1], leak[3] * RMS_Fluids.getCapacity(vehicle, leak[2])))
        end
    end
    table.insert(rows, {"Losses", not isRunning and "none, " .. stopped or #losses > 0 and table.concat(losses, SEP) or "no leak"})

    local filters = {}
    if not spec.isElectricVehicle then
        table.insert(filters, string.format("air %s (residue %s)", pct(spec.airFilterClogging), pct(spec.airFilterResidue)))
    end
    table.insert(filters, "radiator " .. pct(spec.radiatorClogging))
    if not spec.isElectricVehicle then table.insert(filters, "fuel " .. pct(spec.fuelFilterClogging)) end
    table.insert(filters, "hydraulic " .. pct(spec.hydraulicFilterClogging))
    for _, filter in ipairs({ { "TRANSMISSION_FILTER_CLOGGING", "transmission " }, { "ADBLUE_FILTER_CLOGGING", "AdBlue " } }) do
        local entry = RMS_Consumables.getFilterOfBreakdown(filter[1])
        if RMS_Consumables.getHasFilter(vehicle, entry) then
            table.insert(filters, filter[2] .. pct(spec[entry.stateKey]))
        end
    end
    table.insert(rows, {"Filters", table.concat(filters, SEP)})
    local dirt = vehicle.spec_washable ~= nil and "machine " .. pct(vehicle:getDirtAmount()) or "machine never dirty"
    table.insert(rows, {"Dirt", string.format("%s  ·  %s  ·  clogging rate x%.1f", dirt, spec.hasDebris and "debris" or "no debris",
        math.max(spec.radiatorCloggingRate, spec.airFilterCloggingRate))})

    if not spec.isElectricVehicle then
        local smokeRow, gasRow = readExhaustRows(spec)
        table.insert(rows, smokeRow)
        table.insert(rows, gasRow)
        if spec.hasParticulateFilter then
            table.insert(rows, {"DPF", string.format("soot %s  ·  %s  ·  engine %s", pct(spec.fuelState.particulateFilterLevel),
                spec.fuelState.isParticulateFilterRegenerating and "regenerating" or "not regenerating",
                spec.isEngineDerated and "derated" or "not derated")})
        end
        local defIndex = vehicle:getConsumerFillUnitIndex(FillType.DEF)
        if defIndex ~= nil then
            table.insert(rows, {"AdBlue", string.format("%s  ·  %s", pct(vehicle:getFillUnitFillLevelPercentage(defIndex)),
                spec.scrInducementHours > 0 and string.format("inducement %.1f h", spec.scrInducementHours) or "no inducement")})
        end
    else
        -- Native electric consumption is kWh/h, equivalent to kW.
        local packIndex = vehicle:getConsumerFillUnitIndex(FillType.ELECTRICCHARGE)
        local energy, capacity = vehicle:getFillUnitFillLevel(packIndex), vehicle:getFillUnitCapacity(packIndex)
        table.insert(rows, {"Pack", string.format("%s  ·  %.1f of %.1f kWh  ·  %s", pct(energy / capacity), energy, capacity,
            isRunning and string.format("drawing %.0f kW", vehicle.spec_motorized.lastFuelUsage) or "drawing nothing")})
        table.insert(rows, {"Pack health", string.format("capacity left %s  ·  %.0f °C  ·  %s", pct(RMS_ElectricDrive.getCapacityFactor(vehicle)),
            spec.tractionBatteryTempC, RMS_ElectricDrive.getIsCharging(vehicle) and "charging" or "not charging")})
    end

    readBatteryRows(vehicle, spec, rows)

    if RMS_Preheat.isDieselVehicle(vehicle) then
        table.insert(rows, {"Preheat", string.format("%s  ·  %.1f s needed  ·  %.1f s left  ·  lamp test %s", RMS_Preheat.getStateName(spec.preheatState):lower(),
            spec.preheatRequiredMs / 1000, spec.preheatRemainingMs / 1000, spec.preheatLampTestActive and "on" or "over")})
        table.insert(rows, {"Auto crank", string.format("%.1f of %.0f s  ·  glow fault %d  ·  cold start fault %d",
            spec.preheatAutomaticCrankElapsedMs / 1000, RMS_Config.PREHEAT.MAX_AUTOMATIC_CRANK_MS / 1000,
            RMS_Preheat.getGlowPlugFailureSeverity(vehicle), spec.preheatColdStartFaultSeverity)})
    end

    local drive = spec.drivetrain
    local modes = {[RMS_Drivetrain.MODE.TWO_WD] = "2WD", [RMS_Drivetrain.MODE.FOUR_WD] = "4WD", [RMS_Drivetrain.MODE.AUTO] = "auto"}
    local driveText = RMS_Config.DRIVETRAIN.ENABLED and "permanent drive, left to the game" or "left to the game, option off"
    if RMS_Drivetrain.getIsAvailable(vehicle) then
        driveText = string.format("%s  ·  4WD %s  ·  diff lock %s  ·  windup %s", modes[drive.driveMode],
            drive.autoEngaged and "engaged" or "off", drive.diffLockEngaged and "on" or "off", pct(drive.windupStress or 0))
    end
    table.insert(rows, {"Drive train", driveText})
    local kinds = {[RMS_Drivetrain.PARK_KIND.LEVER] = "lever", [RMS_Drivetrain.PARK_KIND.AUTOMATIC] = "automatic",
        [RMS_Drivetrain.PARK_KIND.AIR_VALVE] = "air"}
    table.insert(rows, {"Park brake", RMS_Drivetrain.getIsParkBrakeManaged(vehicle)
        and string.format("%s  ·  %s", drive.parkBrake and "on" or "off", kinds[drive.parkKind]) or "left to the game, option off"})
    local axles = {}
    for _, axle in ipairs(RMS_Drivetrain.getAxleRatios(vehicle)) do
        table.insert(axles, string.format("%s %s, up to %.2f", axle.label,
            axle.ratio ~= nil and string.format("one %.2f times the other", axle.ratio) or "standing", axle.cap))
    end
    if #axles > 0 then
        table.insert(rows, {"Axles", table.concat(axles, SEP)})
    end
    if spec.systems.pto.enabled ~= false then
        table.insert(rows, {"PTO", string.format("%s  ·  %.0f rpm  ·  %.0f kW  ·  %s used  ·  %d engagements", spec.isPtoActive and "on" or "off",
            spec.ptoRpm, spec.ptoPower, pct(spec.ptoUtilization), spec.ptoEngagementCount)})
    end

    local motor = vehicle:getMotor()
    local drivePower = isRunning and motor:getMotorRotSpeed() * (motor:getMotorAppliedTorque() - motor:getMotorExternalTorque()) or 0
    local otherPower = isRunning and motor:getMotorRotSpeed() * motor:getMotorExternalTorque() or 0
    table.insert(rows, {"Motor", string.format("%.1f km/h  ·  %.0f rpm  ·  %s  ·  %.0f kW to the transmission  ·  %.0f kW to PTO and "
        .. "hydraulics", vehicle:getLastSpeed(), motor:getLastModulatedMotorRpm(), getGear(motor), drivePower, otherPower)})
    table.insert(rows, {"Load", isRunning and string.format("%s RMS  ·  %s game", pct(spec.dynamicMotorLoad),
        pct(vehicle:getMotorLoadPercentage())) or stopped})
    local draft = spec.activeDraftMaxForce > 0 and string.format("tool draft %.1f kN of its %.1f kN", spec.activeDraftEffectiveForceCap,
        spec.activeDraftMaxForce) or "no tool pulling"
    table.insert(rows, {"Traction", string.format("%s  ·  slip %s  ·  ground grip %.2f", draft, pct(spec.wheelSlipIntensity),
        spec.avgTireGroundFrictionCoeff)})
    local chassis = spec.systemWearNow.chassis or {}
    local impacts = spec.terrainImpacts.count
    local impactText = impacts == 0 and "no impacts" or string.format("%d %s (last -%.1f km/h)", impacts,
        impacts == 1 and "impact" or "impacts", spec.terrainImpacts.lastSpeedLoss)
    table.insert(rows, {"Chassis", string.format("%s  ·  steering play %.1f°  ·  pull %.1f°", impactText, chassis.steerPlay or 0,
        chassis.steerPull or 0)})

    local wearScale = RMS_Config.CORE.BASE_SYSTEMS_WEAR / RMS_Config.CORE.REFERENCE_SYSTEMS_WEAR
    local warning = RMS_Config.CORE.AVG_STRESS_WARNING_THRESHOLD * wearScale
    local overloads = {}
    for _, system in ipairs(SYSTEMS) do
        local stats = spec.factorStats[system.key]
        if stats ~= nil and stats._avgStress ~= nil and stats._avgStress > 0 then
            table.insert(overloads, string.format("%s %s", getSystemName(system, spec.isElectricVehicle):lower(), pct(stats._avgStress / warning)))
        end
    end
    table.insert(rows, {"Overload", #overloads > 0 and table.concat(overloads, SEP) .. " of the warning" or "none"})

    table.insert(rows, {"Around", string.format("%s  ·  %s  ·  ground wet %s  ·  %s  ·  weather x%.2f", vehicle:getIsOnField() and "on a field" or "off field",
        spec.isRaisingDust and "dust" or "no dust", pct(g_currentMission.environment.weather:getGroundWetness()),
        spec.isUnderRoof and "under a roof" or "outdoors", RMS_Main.currentWeatherFactor)})
    local tools = collectToolNames(vehicle, {})
    local hitch = spec.raisingMass > 0 and string.format("lifting %.1f t", spec.raisingMass) or spec.isImplementLowered and "lowered" or "raised"
    table.insert(rows, {"Attached", #tools > 0 and string.format("%s  (%s)", table.concat(tools, SEP), hitch) or "none"})

    if vehicle.spec_lights ~= nil then
        local mask, lit = vehicle:getLightsTypesMask(), {}
        for _, light in ipairs({{Lights.LIGHT_TYPE_DEFAULT, "road"}, {Lights.LIGHT_TYPE_WORK_BACK, "work back"},
            {Lights.LIGHT_TYPE_WORK_FRONT, "work front"}, {Lights.LIGHT_TYPE_HIGHBEAM, "high beam"}}) do
            if math.floor(mask / 2 ^ light[1]) % 2 == 1 then
                table.insert(lit, light[2])
            end
        end
        if vehicle:getBeaconLightsVisibility() then
            table.insert(lit, "beacon")
        end
        local turns = {[Lights.TURNLIGHT_LEFT] = "left signal", [Lights.TURNLIGHT_RIGHT] = "right signal", [Lights.TURNLIGHT_HAZARD] = "hazards"}
        if turns[vehicle:getTurnLightState()] ~= nil then
            table.insert(lit, turns[vehicle:getTurnLightState()])
        end
        local out = {}
        for partId in pairs(spec.activeBreakdowns) do
            if partId:find("LIGHTS_FAILURE", 1, true) or partId:find("BEAM_FAILURE", 1, true) then
                table.insert(out, RMS_DebugReading.getPartName(partId))
            end
        end
        table.sort(out)
        table.insert(rows, {"Lights", string.format("%s  ·  %s", #lit > 0 and table.concat(lit, ", ") or "off",
            #out > 0 and table.concat(out, ", ") .. " out" or "none out")})
    end

    if vehicle:getIsAIActive() then
        table.insert(rows, {"Worker", string.format("overload %.2f  ·  speed limit %s", spec.aiWorkerOverload,
            spec.aiWorkerSpeedLimit ~= nil and string.format("%.1f km/h", spec.aiWorkerSpeedLimit) or "none")})
    end
    local addon = vehicle.spec_CVTaddon
    if RMS_Utils.hasCVTAddon(vehicle) and addon ~= nil then
        table.insert(rows, {"CVT Addon", string.format("damage %.4f  ·  damage warning %s  ·  heat warning %s  ·  high pressure %s",
            addon.CVTdamage or 0, addon.forDBL_warndamage == 1 and "on" or "off", addon.forDBL_warnheat == 1 and "on" or "off",
            addon.forDBL_highpressure == 1 and "on" or "off")})
    end
    local months, hours = vehicle:getWarrantyLimits()
    local factoryActive = vehicle.age < months and RealisticMechanicalSystems.getRealOperatingHours(vehicle) < hours
    local warrantyState = factoryActive and "active" or "expired"
    if vehicle.propertyState == VehiclePropertyState.LEASED then warrantyState = "lease" end
    table.insert(rows, {"Warranty", string.format("%s (%s): age < %d months, meter < %d h of play",
        spec.warrantyPlan == 1 and "factory" or "extension", warrantyState, months, hours)})
    local ids = {}
    for id, expiry in pairs(spec.partWarranty) do
        if vehicle.age < expiry then table.insert(ids, id) end
    end
    table.sort(ids)
    for _, id in ipairs(ids) do
        table.insert(rows, {"Part cover", string.format("%s: until age %d months", RMS_DebugReading.getPartName(id), spec.partWarranty[id])})
    end
    ids = {}
    for id, expiry in pairs(spec.usedPartWarranty) do
        if vehicle.age < expiry then table.insert(ids, id) end
    end
    table.sort(ids)
    for _, id in ipairs(ids) do
        table.insert(rows, {"Used cover", string.format("%s: until age %d months (parts only)", RMS_DebugReading.getPartName(id), spec.usedPartWarranty[id])})
    end
    reading.machine = rows
end

-- @param table vehicle vehicle
-- @return table reading debug blocks
function RMS_DebugReading.read(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    local reading = {}
    readHeader(vehicle, spec, reading)
    readSystems(vehicle, spec, reading)
    readFaults(vehicle, spec, reading)
    readWork(spec, reading)
    readMachine(vehicle, spec, reading)
    return reading
end

-- @param table vehicle vehicle
-- @param table reading reading received
function RMS_DebugReading.useLocalExhaust(vehicle, reading)
    local spec = vehicle.spec_RealisticMechanicalSystems
    if spec.isElectricVehicle then
        return
    end
    local smokeRow, gasRow = readExhaustRows(spec)
    for index, row in ipairs(reading.machine) do
        if row[1] == smokeRow[1] then
            reading.machine[index] = smokeRow
        elseif row[1] == gasRow[1] then
            reading.machine[index] = gasRow
        end
    end
end

-- Fixed field order; field names are not sent.
local ROWS = {list = {fields = {{1, "string"}, {2, "string"}}}}
local SCHEMA = {fields = {
    {"title", "string"},
    {"facts", ROWS},
    {"service", ROWS},
    {"systems", {list = {fields = {{"name", "string"}, {"condition", "float"}, {"risk", "float"}, {"wearing", "float"}, {"normal", "float"},
        {"since", "string"}, {"parts", {list = {fields = {{"name", "string"}, {"wear", "float"}, {"chance", "float"}, {"isWorn", "bool"},
        {"stage", "byte"}, {"tick", "float"}}}}}}}}},
    {"wearNow", {list = {fields = {{"system", "string"},
        {"causes", {list = {fields = {{"label", "string"}, {"measure", "string"}, {"rate", "float"}}}}}}}}},
    {"faults", {list = {fields = {{"name", "string"}, {"info", "string"}, {"progress", "float"}, {"next", "string"}, {"isSeen", "bool"}}}}},
    {"alerts", ROWS},
    {"work", ROWS},
    {"machine", ROWS}
}}

---Writes one value of a reading by its place in the shape
local function writeValue(streamId, schema, value)
    if schema == "string" then
        streamWriteString(streamId, value)
    elseif schema == "float" then
        streamWriteFloat32(streamId, value)
    elseif schema == "bool" then
        streamWriteBool(streamId, value)
    elseif schema == "byte" then
        streamWriteUInt8(streamId, value)
    elseif schema.list ~= nil then
        streamWriteUInt8(streamId, #value)
        for _, item in ipairs(value) do
            writeValue(streamId, schema.list, item)
        end
    else
        for _, field in ipairs(schema.fields) do
            writeValue(streamId, field[2], value[field[1]])
        end
    end
end

---Reads one value of a reading by its place in the shape
local function readValue(streamId, schema)
    if schema == "string" then
        return streamReadString(streamId)
    elseif schema == "float" then
        return streamReadFloat32(streamId)
    elseif schema == "bool" then
        return streamReadBool(streamId)
    elseif schema == "byte" then
        return streamReadUInt8(streamId)
    elseif schema.list ~= nil then
        local items = {}
        for index = 1, streamReadUInt8(streamId) do
            items[index] = readValue(streamId, schema.list)
        end
        return items
    end
    local value = {}
    for _, field in ipairs(schema.fields) do
        value[field[1]] = readValue(streamId, field[2])
    end
    return value
end

---Writes a reading to a stream
-- @param integer streamId stream id
-- @param table reading reading
function RMS_DebugReading.writeStream(streamId, reading)
    writeValue(streamId, SCHEMA, reading)
end

---Reads a reading from a stream
-- @param integer streamId stream id
-- @return table reading reading
function RMS_DebugReading.readStream(streamId)
    return readValue(streamId, SCHEMA)
end
