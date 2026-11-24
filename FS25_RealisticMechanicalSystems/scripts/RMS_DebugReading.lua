-- Copyright © 2026 Squallqt. All rights reserved.

---Debug reading of a vehicle: built on the server, sent to the debug window
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
    {key = "pto", name = "PTO", word = "pto"},
    {key = "harvest", name = "Harvest", word = "harvest"}
}

RMS_DebugReading.GROUPS = {
    {title = "Engine and heat", column = 1}, {title = "Around", column = 1},
    {title = "Service", column = 2}, {title = "Fluids", column = 2}, {title = "Warranty", column = 2},
    {title = "Filters and dirt", column = 3}, {title = "Exhaust", column = 3}, {title = "Traction battery", column = 3},
    {title = "Electrical", column = 4}, {title = "Starting", column = 4},
    {title = "Drive", column = 5}, {title = "Work", column = 5}
}

RMS_DebugReading.ROW = {ITEMS = 1, CHART = 2, GAUGES = 3, CLOCK = 4}
local ROW = RMS_DebugReading.ROW

RMS_DebugReading.LAMP = {RED = 1, AMBER = 2, BLUE = 3, GREY = 4}

local ACRONYMS = {cvt = "CVT", ecu = "ECU", nox = "NOx", adblue = "AdBlue", hv = "HV", dcdc = "DC/DC", pto = "PTO", ["4wd"] = "4WD"}

---Returns a number rounded, its thousands grouped by commas
-- @param float value number
-- @return string text grouped number
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

---Returns a share as a whole percentage
-- @param float value share, 0 to 1
-- @return string text percentage
local function pct(value)
    return string.format("%d %%", math.floor(value * 100 + 0.5))
end

---Returns yes or no
-- @param any value truth value
-- @return string text "yes" or "no"
local function yesNo(value)
    return value and "yes" or "no"
end

---Returns the words of a text key, its prefixes left out
-- @param string key text key
-- @return string text words of the key
local function plainKey(key)
    local words = tostring(key):gsub("^rms_spec_", ""):gsub("^%a+_types?_", ""):gsub("^%a+_", "")
    return (words:gsub("_", " "))
end

---Returns a heat flow in deg C per minute from deg C per ms, never -0.0
-- @param float value heat flow (deg C per ms)
-- @return float flow heat flow (deg C per minute)
local function perMinute(value)
    local rounded = math.floor((value or 0) * 600 + 0.5) / 10
    return rounded == 0 and 0 or rounded
end

---Returns a temperature text, no reading before the first one
-- @param float value temperature (deg C), -99 before the first reading
-- @return string text temperature
local function temperature(value)
    return value == -99 and "no reading yet" or string.format("%.1f °C", value)
end

---Returns the power to mass text of a braking basis
-- @param float ratio power to mass (hp per tonne)
-- @param string basis "gcw" for the whole train, else the towed mass
-- @return string text power to mass
local function getPowerToMass(ratio, basis)
    return string.format("%.1f hp per tonne %s", ratio, basis == "gcw" and "in all" or "towed")
end

---Returns an item of a row
-- @param string label label
-- @param any value value
-- @return table item item of a row
local function item(label, value)
    return {label = label, value = value}
end

---Returns a row of items
-- @param string label label of the row
-- @param table items items of the row
-- @return table row row of items
local function itemsRow(label, items)
    return {label = label, kind = ROW.ITEMS, items = items}
end

---Returns the level of the service clock covering a system
-- @param table vehicle vehicle
-- @param string systemKey key of the system
-- @return float level service level, 1 without a clock
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

---Returns the name of the current weather
-- @return string name weather, lower case
local function getWeatherName()
    return WeatherType.getName(RMS_Main.currentWeather):lower()
end

---Returns the temperature of the oil the hydraulics run on
-- @param table spec RMS specialization of the vehicle
-- @return float temperature temperature (deg C)
local function getHydraulicOilTemperature(spec)
    if RMS_Thermal.getHasSeparateHydraulicCircuit(spec) then
        return spec.rawHydraulicTemperature
    end
    return spec.rawTransmissionTemperature
end

-- alias={name, short name, measure(factors, spec, vehicle, system)}
local CAUSES = {
    sf = {"Service overdue", "service", function(_, _, vehicle, systemKey) return "service " .. pct(getServiceLevel(vehicle, systemKey)) end},
    mlf = {"Engine load", "load", function(f) return pct(f.dynamicMotorLoad) .. " load" end},
    aicf = {"Air filter", "air filter", function(_, spec) return pct(spec.airFilterClogging) .. " clogged" end},
    cmf = {"Cold engine worked", "cold", function(f) return string.format("%.0f °C engine", f.engineTemperature) end},
    hmf = {"Engine overheating", "overheating", function(f) return string.format("%.0f °C engine", f.engineTemperature) end},
    pof = {"Pull overload", "pull", function(f) return pct(f.driveTorqueRatio) .. " of rated torque" end},
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
    wef = {"Weather exposure", "weather", function() return "weather " .. getWeatherName() end},
    crf = {"Cranking", "cranking", function(f) return string.format("%.1f s cranking", f.crankingTimer / 1000) end},
    shf = {"Starter heat", "starter heat", function(_, spec) return string.format("%.0f K over rest", spec.starterHeatK) end},
    lubf = {"Greasing late", "greasing", function(_, spec) return pct(1 - spec.lubricationLevel) .. " of an interval late" end},
    slf = {"Steering load", "steering", function(f) return pct(f.steerTravelRate) .. " of the lock a second" end},
    tif = {"Impacts", "impacts", function(f) return string.format("%d %s", f.impactCount, f.impactCount == 1 and "impact" or "impacts") end},
    bmf = {"Braking mass", "braking", function(f) return getPowerToMass(f.brakeMassRatio, f.brakeMassBasis) end},
    pbf = {"Driving on the park brake", "park brake", function(_, _, vehicle) return string.format("%.1f km/h", vehicle:getLastSpeed()) end},
    lff = {"Low fuel", "low fuel", function(f) return pct(f.fuelLevel) .. " fuel" end},
    cff = {"Cold fuel", "cold fuel", function(f) return string.format("%.0f °C fuel", f.fuelTemperature) end},
    idf = {"Idling deposits", "idling", function(f) return string.format("%.0f s idling", f.idleTimer) end},
    hpf = {"High injection pressure", "injection", function(f) return "fuel " .. pct(f.currentFuelUsageRatio) .. " of full power" end},
    ddf = {"Deep discharge", "discharge", function(f) return pct(f.fuelLevel) .. " charge" end},
    bhf = {"Pack heat", "pack heat", function(_, spec) return string.format("%.0f °C pack", spec.tractionBatteryTempC) end},
    plf = {"PTO load", "PTO load", function(_, spec) return pct(spec.ptoUtilization) .. " of its power" end},
    pef = {"PTO engagements", "engagements", function(_, spec) return string.format("%d engagements", spec.ptoEngagementCount) end},
    prf = {"PTO shaft angle", "shaft angle", function(_, spec)
        if spec.frontPtoShaftAngle / spec.frontPtoShaftLimit > spec.ptoShaftAngle / spec.ptoShaftLimit then
            return string.format("front joint %.0f of %.0f deg", spec.frontPtoShaftAngle, spec.frontPtoShaftLimit)
        end
        return string.format("rear joint %.0f of %.0f deg", spec.ptoShaftAngle, spec.ptoShaftLimit) end},
    hef = {"Harvest overload", "overload", function(f) return "effort " .. pct(f.harvestEffort) end},
    hgf = {"Grain flow", "grain flow", function(f) return "flow " .. pct(f.harvestGrain) end},
    hsf = {"Chopper load", "chopper", function(f) return "load " .. pct(f.harvestChopper) end},
    hstf = {"Stones", "stones", function(f) return string.format("stone wear x%.2f", 1 + f.harvestStone) end},
    hrf = {"Rice", "rice", function() return "abrasive rice straw" end},
    hwf = {"Wet crop", "wet crop", function(f) return f.harvestSource == "rh" and "crop too damp" or "rain on the crop" end},
    hdef = {"Header starts", "header starts", function(_, spec)
        return string.format("%d starts", spec.headerDrive ~= nil and spec.headerDrive.starts or 0) end},
    hdlf = {"Header greasing late", "header greasing", function(f) return pct(f.headerGreasingLate or 0) .. " of an interval late" end}
}

local SOURCES = {"wear", "poor parts", "quick fix"}

---Returns the name of a part, the system word left out
-- @param string partId part or breakdown
-- @param string? systemWord word of the system to leave out
-- @return string name name of the part
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

---Returns the name of a system, its electric name on an electric machine
-- @param table system system of the reading
-- @param boolean isElectric true on an electric machine
-- @return string name name of the system
local function getSystemName(system, isElectric)
    return isElectric and system.electricName or system.name
end

local GEARBOXES = {manual = "manual gearbox", manual_powershift = "semi-powershift", automatic = "automatic gearbox",
    powershift = "powershift", variable = "CVT"}

---Returns the year, family, gearbox and energy of a machine
-- @param table vehicle vehicle
-- @param table spec RMS specialization of the vehicle
-- @return table kind words of the kind
local function getKind(vehicle, spec)
    local profile = RMS_Fluids.getProfileName(vehicle)
    local kind = {tostring(spec.year), profile:sub(1, 1) .. (profile:sub(2):lower():gsub("_", " "))}
    local gearbox = GEARBOXES[vehicle:getTransmissionType()]
    if gearbox ~= nil and not spec.isElectricVehicle then
        table.insert(kind, gearbox)
    end
    if spec.isElectricVehicle then
        table.insert(kind, "electric")
    else
        local energy = vehicle.spec_motorized.consumersByFillTypeName.METHANE ~= nil and "methane" or "diesel"
        table.insert(kind, energy .. (spec.hasParticulateFilter and " Stage V" or ""))
    end
    return kind
end

---Returns the faults a machine had, quick fixes left out
-- @param table vehicle vehicle
-- @param table spec RMS specialization of the vehicle
-- @return integer count number of faults
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

---Returns the peak power now over the peak of the new torque curve
-- @param table motor motor of the vehicle
-- @return float share peak power now over the peak of its new torque curve
local function getPowerShare(motor)
    local peak = 0
    for rpm = motor.minRpm, motor.maxRpm, 10 do
        peak = math.max(peak, motor:getTorqueCurveValue(rpm) * rpm)
    end
    return peak * math.pi / 30 / motor.peakMotorPower
end

---Returns the remap state text
-- @param table vehicle vehicle
-- @param table spec RMS specialization of the vehicle
-- @return string text remap state
local function getRemapText(vehicle, spec)
    if not RMS_EngineRemap.getIsEligible(vehicle) and not RMS_EngineRemap.getIsRemapped(vehicle) then
        return "not offered (no engine control unit, not owned)"
    end
    local stockHp = RMS_EngineRemap.getStockPeaks(vehicle)
    local gain = RMS_EngineRemap.getGain(vehicle)
    if not RMS_EngineRemap.getIsRemapped(vehicle) then
        return string.format("stock %.0f hp" .. SEP .. "a remap would give %.0f hp (+%.0f %%)%s", stockHp, stockHp * (1 + gain), gain * 100,
            spec.warrantyVoided and SEP .. "warranty lost to an earlier remap" or "")
    end
    return string.format("remapped %.0f hp, stock %.0f hp (+%.0f %%)" .. SEP .. "at age %d months" .. SEP .. "free restore until age %d months",
        stockHp * (1 + gain), stockHp, gain * 100, spec.remapAge, RMS_EngineRemap.getFreeRestoreUntil(vehicle))
end

---Reads the name, kind, vitals and facts of a machine
-- @param table vehicle vehicle
-- @param table spec RMS specialization of the vehicle
-- @param table reading reading being built
local function readHeader(vehicle, spec, reading)
    local R = RealisticMechanicalSystems
    reading.name = vehicle:getFullName()
    reading.kind = getKind(vehicle, spec)

    local lifeUsed = R.getRealOperatingHours(vehicle) * RMS_Config.CORE.BASE_SYSTEMS_WEAR
    local isTractor = string.find(RMS_Fluids.getVehicleCategory(vehicle), "^TRACTORS") ~= nil
    reading.vitals = {
        condition = pct(vehicle:getConditionLevel()),
        lifeUsed = pct(lifeUsed),
        reliability = string.format("%.2f", spec.reliability),
        faults = tostring(countFaults(vehicle, spec)),
        faultsNote = not isTractor and "" or spec.isElectricVehicle and "an electric tractor sees about 10 in its life"
            or "a tractor sees about 16 in its life"
    }

    local power = RMS_Fluids.getEnginePower(vehicle)
    local share = getPowerShare(vehicle:getMotor())
    reading.facts = {
        {"Hour meter", string.format("%.1f h of play = %s h of work", vehicle:getFormattedOperatingTime(),
            grouped(lifeUsed * RMS_Config.CORE.MACHINE_LIFE_HOURS))},
        {"Power", string.format("new %.0f hp = %.0f kW" .. SEP .. "now %.0f hp = %.0f kW (%s)", power, power / RMS_Fluids.KW_TO_HP,
            power * share, power * share / RMS_Fluids.KW_TO_HP, pct(share))},
        {"Remap", getRemapText(vehicle, spec)}
    }
end

---Reads the service clocks, greasing, build and report
-- @param table vehicle vehicle
-- @param table spec RMS specialization of the vehicle
-- @param table groups groups of the machine view by title
local function readService(vehicle, spec, groups)
    local R = RealisticMechanicalSystems
    local rows = {}
    local names = {engine = "Engine oil", transmission = "Transmission", hydraulic = "Hydraulic", coolant = "Coolant"}
    local due = RMS_Config.CORE.SERVICE_EXPIRED_THRESHOLD
    for _, clock in ipairs(vehicle:getServiceClocks()) do
        local used, interval = vehicle:getServiceClockHours(clock)
        local level = vehicle:getServiceClockLevel(clock)
        local elapsed = math.max(vehicle.age - (spec.serviceCalendar[clock.key] or vehicle.age), 0)
        local left = { string.format("%.1f h", interval - used), string.format("%d months", clock.months - elapsed) }
        local isDue = level <= due
        table.insert(rows, {label = names[clock.key], kind = ROW.CLOCK, level = level, due = due, overdue = isDue,
            left = isDue and "overdue" or #left > 0 and table.concat(left, " or ") .. " left" or ""})
    end
    if spec.isVehicleNeedLubricate then
        table.insert(rows, itemsRow("Greasing", {item("points due", tostring(spec.greasingDuePoints or 0)),
            item("late", pct(1 - spec.lubricationLevel) .. " of an interval"), item("day worked", yesNo(RMS_Greasing.getIsWorkedToday(vehicle)))}))
    else
        table.insert(rows, itemsRow("Greasing", {item("", "not needed")}))
    end
    for _, child in ipairs(vehicle:getChildVehicles()) do
        local childSpec = child.spec_rmsImplementGreasing
        if childSpec ~= nil and childSpec.isVehicleNeedLubricate then
            table.insert(rows, itemsRow("Implement", {item("", child:getFullName()), item("points due", tostring(childSpec.greasingDuePoints)),
                item("late", pct(1 - childSpec.lubricationLevel)), item("wears", string.format("×%.2f", RMS_Greasing.getWearFactor(child))),
                item("day worked", yesNo(RMS_Greasing.getIsWorkedToday(child)))}))
        end
    end

    local SOURCE = RMS_ProductionYear.SOURCE
    local provenance = "unknown (default)"
    if spec.yearSource == SOURCE.FILE then
        provenance = "vehicle file"
    elseif spec.yearSource == SOURCE.REFERENCE then
        provenance = "RMS reference"
    end
    local built = {item("year", tostring(spec.year)), item("dated by", provenance)}
    if not spec.isElectricVehicle then
        table.insert(built, item("engine oil every", string.format("%d h", R.getServiceProgramHours(vehicle, "engine"))))
    end
    table.insert(rows, itemsRow("Built", built))

    local report = R.getReferenceReport(vehicle)
    if report ~= nil then
        local hours, isOutdated = vehicle:getInspectionReportAge()
        local kind = report.type == R.STATUS.INSPECTION and plainKey(report.optionOne) .. " inspection" or plainKey(report.type)
        table.insert(rows, itemsRow("Report", {item(kind, string.format("%.1f h ago%s", hours, isOutdated and " (out of date)" or ""))}))
    else
        table.insert(rows, itemsRow("Report", {item("", "none")}))
    end
    groups["Service"] = {rows = rows, note = string.format("white mark: due at %s", pct(due))}
end

---Returns the shares of normal wear and of each cause in a system
-- @param table stats wear statistics of the system
-- @return table shares {name, share}, normal first, then every cause
local function getSystemShares(stats)
    local total = stats.total or 0
    local causes = 0
    local merged = {}
    for alias, wear in pairs(stats) do
        if CAUSES[alias] ~= nil and type(wear) == "number" and wear > 0 then
            causes = causes + wear
            local name = CAUSES[alias][2]
            merged[name] = (merged[name] or 0) + wear
        end
    end
    local whole = math.max(total, causes)
    local list = {}
    for name, wear in pairs(merged) do
        table.insert(list, {name = name, share = whole > 0 and wear / whole or 0})
    end
    table.sort(list, function(a, b)
        if a.share ~= b.share then return a.share > b.share end
        return a.name < b.name
    end)
    local shares = {{name = "normal", share = whole > 0 and (whole - causes) / whole or 0}}
    for _, entry in ipairs(list) do
        table.insert(shares, entry)
    end
    return shares
end

---Returns the causes of the wear of a part
-- @param table spec RMS specialization of the vehicle
-- @param string systemKey key of the system
-- @param integer index part of the system
-- @param string partId part
-- @param table shares shares of the system
-- @return table causes {cause, share}, cause the index of its name in the system shares
local function getPartCauses(spec, systemKey, index, partId, shares)
    local record = RealisticMechanicalSystems.getPartCauseWear(spec, systemKey, index, partId)
    local byName, total = {}, 0
    for alias, wear in pairs(record) do
        if wear > 0 then
            -- hydraulic work completes the normal rate, as the system counts it
            local name = CAUSES[alias] ~= nil and CAUSES[alias][2] or "normal"
            byName[name] = (byName[name] or 0) + wear
            total = total + wear
        end
    end
    local causes = {}
    if total <= 0 then
        return causes
    end
    for position, entry in ipairs(shares) do
        if byName[entry.name] ~= nil then
            table.insert(causes, {cause = position, share = byName[entry.name] / total})
            byName[entry.name] = nil
        end
    end
    for name, wear in pairs(byName) do
        table.insert(shares, {name = name, share = 0})
        table.insert(causes, {cause = #shares, share = wear / total})
    end
    return causes
end

---Reads the systems, their parts and the wear under way
-- @param table vehicle vehicle
-- @param table spec RMS specialization of the vehicle
-- @param table reading reading being built
local function readSystems(vehicle, spec, reading)
    local rateScale = RMS_Config.CORE.BASE_SYSTEMS_WEAR * 100
    reading.systems, reading.wearNow = {}, {}
    for _, system in ipairs(SYSTEMS) do
        local parts = spec.systemParts[system.key]
        if parts ~= nil and #parts > 0 and spec.systems[system.key].enabled then
            local word = spec.isElectricVehicle and system.electricWord or system.word
            local stats = spec.factorStats[system.key] or {}
            local shares = getSystemShares(stats)
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
                    tick = b10 <= 1 and b10 or -1,
                    strain = (spec.partStrain[partId] or 0) > 0,
                    causes = getPartCauses(spec, system.key, index, partId, shares)
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
                wearTaken = stats.total or 0,
                shares = shares,
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
    local normal = rateScale / spec.reliability
    reading.legend = {fullAfter = 100 / normal, horizon = RMS_Config.CORE.RISK_HORIZON_WEAR * 100 / normal}
end

---Returns the name of a fault
-- @param string breakdownId breakdown
-- @param string? systemWord word of the system to leave out
-- @return string name name of the fault
local function getFaultName(breakdownId, systemWord)
    local definition = RMS_Breakdowns.BreakdownRegistry[breakdownId]
    if definition.system == nil or definition.part == RMS_Breakdowns.PARTS.VEHICLE then
        return breakdownId:sub(1, 1) .. breakdownId:sub(2):lower():gsub("_", " ")
    end
    return RMS_DebugReading.getPartName(breakdownId, systemWord)
end

---Returns the system name and word of a breakdown
-- @param table definition definition of the breakdown
-- @param boolean isElectric true on an electric machine
-- @return string name name of the system
-- @return string? word word of the system
local function getBreakdownSystem(definition, isElectric)
    for _, system in ipairs(SYSTEMS) do
        if RMS_Utils.getSystemKey(RealisticMechanicalSystems.SYSTEMS, definition.system) == system.key then
            return getSystemName(system, isElectric), isElectric and system.electricWord or system.word
        end
    end
    return "Machine", nil
end

local ABUSE_READINGS = {
    impact = "hit by a collision", heat = "heat past the warning", low_level = "oil too low",
    fuel_dry = "tank run dry", park_brake = "parking brake on", pto_engagement = "PTO engaged high",
    stones = "stones", starter = "starter held", pto_angle = "PTO shaft angle", windup = "lock or 4WD on hard ground",
    filter = "clogged filter", trailer = "trailer too heavy", aftermarket_part = "aftermarket part fitted", used_part = "used part fitted",
    oil = "unsuited engine oil", header_engagement = "header started above idle",
}

---Reads the faults, lamps, codes and effects
-- @param table vehicle vehicle
-- @param table spec RMS specialization of the vehicle
-- @param table reading reading being built
local function readFaults(vehicle, spec, reading)
    local R = RealisticMechanicalSystems
    local isInWorkshop = spec.currentState ~= R.STATUS.READY
    reading.faults = {}
    for breakdownId, breakdown in pairs(vehicle:getActiveBreakdowns()) do
        local definition = RMS_Breakdowns.BreakdownRegistry[breakdownId]
        local systemName, word = getBreakdownSystem(definition, spec.isElectricVehicle)
        local stageCount = #definition.stages
        local flags, notes = {}, {}
        if breakdown.warrantyServiceOverdue then table.insert(notes, "warranty refused: service overdue when fault occurred") end
        if breakdown.warrantyAbuse ~= nil then
            table.insert(notes, "warranty refused: " .. ABUSE_READINGS[R.WARRANTY_ABUSES[breakdown.warrantyAbuse]])
        end
        if breakdown.usedPartHours ~= nil then
            table.insert(flags, string.format("donor %d h", RealisticMechanicalSystems.getUsedPartMeterHours(breakdown.usedPartHours)))
        end
        local defective = breakdownId == "MAINTENANCE_WITH_POOR_QUALITY_CONSUMABLES" and RMS_Consumables.getDefectiveFilter(vehicle) or nil
        if defective ~= nil then
            table.insert(notes, RMS_DebugReading.getPartName(defective.breakdownId) .. " defective, its circuit wears as in bypass until changed")
        elseif breakdown.branch ~= nil and breakdown.branch > 0 then
            table.insert(flags, "way " .. breakdown.branch)
        end
        table.insert(flags, breakdown.isVisible and "seen" or "hidden")
        table.insert(flags, SOURCES[breakdown.source])
        table.insert(flags, breakdown.isSelectedForRepair and "selected for repair" or "not selected")

        local progress = R.getStageProgress(definition, breakdown)
        local nextText
        if isInWorkshop then
            nextText = "held while in the workshop"
        elseif not breakdown.isActive then
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
            system = systemName,
            stage = breakdown.stage,
            stages = stageCount,
            progress = progress,
            next = nextText,
            isSeen = breakdown.isVisible == true,
            flags = flags,
            notes = notes
        })
    end
    table.sort(reading.faults, function(a, b) return a.name < b.name end)

    local LAMP = RMS_DebugReading.LAMP
    local colours = {[RMS_Breakdowns.COLORS.CRITICAL] = LAMP.RED, [RMS_Breakdowns.COLORS.WARNING] = LAMP.AMBER,
        [RMS_Breakdowns.COLORS.COOL] = LAMP.BLUE, [RMS_Breakdowns.COLORS.DEFAULT] = LAMP.GREY}
    local lamps = {}
    for indicatorId, indicator in pairs(spec.activeIndicators) do
        table.insert(lamps, {text = (indicatorId:gsub("(%l)(%u)", "%1 %2"):lower()), color = colours[indicator.color]})
    end
    table.sort(lamps, function(a, b) return a.text < b.text end)
    local shown = {}
    for key in pairs(spec.displayedFaultCodes or {}) do
        local spn, fmi = key:match("^(%d+) (%d+)$")
        table.insert(shown, string.format("SPN %s FMI %s", spn, fmi))
    end
    table.sort(shown)
    local readCodes = RMS_DiagnosticTool.readFaultCodes(vehicle)
    local codes = {}
    if readCodes == nil then
        table.insert(codes, "unreadable, battery cut off")
    end
    for _, entry in ipairs(readCodes or {}) do
        local code = entry.spn ~= nil and string.format("SPN %d FMI %d", entry.spn, entry.fmi)
            or getBreakdownSystem(RMS_Breakdowns.BreakdownRegistry[entry.breakdownId], spec.isElectricVehicle) .. " lamp, no code"
        local breakdown = spec.activeBreakdowns[entry.breakdownId]
        table.insert(codes, code .. ((breakdown == nil or breakdown.isVisible) and "" or " (hidden)"))
    end
    local effects = {}
    for effectId, effect in pairs(spec.activeEffects) do
        if type(effect.value) == "number" then
            local key = effectId:lower():gsub("_modifier$", ""):gsub("_effect$", "")
            local words = {}
            for word in key:gmatch("[^_]+") do
                table.insert(words, ACRONYMS[word] or word)
            end
            table.insert(effects, {label = table.concat(words, " "), value = string.format("%.2f", effect.value)})
        end
    end
    table.sort(effects, function(a, b) return a.label < b.label end)
    reading.alerts = {lamps = lamps, display = shown, codes = codes, effects = effects}
end

---Reads the workshop work under way
-- @param table spec RMS specialization of the vehicle
-- @param table reading reading being built
local function readWork(spec, reading)
    local R = RealisticMechanicalSystems
    reading.work = {isActive = false, title = "", chips = {}, price = "", progress = 0, progressText = "", repairs = {},
        inspections = {}, renewed = {}, serviceTo = {}}
    if spec.currentState == R.STATUS.READY then
        return
    end
    local work = reading.work
    local places = {[R.WORKSHOP.DEALER] = "at the dealer", [R.WORKSHOP.MOBILE] = "mobile workshop", [R.WORKSHOP.OWN] = "farm workshop"}
    local state = plainKey(spec.currentState)
    work.isActive = true
    work.title = state:sub(1, 1):upper() .. state:sub(2)
    table.insert(work.chips, places[spec.workshopType])
    for index, option in ipairs({spec.serviceOptionOne, spec.serviceOptionTwo}) do
        if option ~= nil and option ~= "" and option ~= "NONE" then
            -- the colors of a repaint travel as a code
            local isColors = spec.currentState == R.STATUS.BODYWORK and index == 2
            table.insert(work.chips, isColors and "new colors" or plainKey(option))
        end
    end
    work.progress = spec.pendingProgressTotalTime > 0 and spec.pendingProgressElapsedTime / spec.pendingProgressTotalTime or 0
    local queue = spec.currentState == R.STATUS.REPAIR and spec.pendingRepairQueue
        or (spec.currentState == R.STATUS.INSPECTION or spec.currentState == R.STATUS.MAINTENANCE) and spec.pendingInspectionQueue or {}
    local done = #queue > 0 and string.format(SEP .. "%d of %d done", spec.pendingProgressStepIndex, #queue) or ""
    work.progressText = string.format("%s" .. SEP .. "%.1f h left%s", pct(work.progress),
        (spec.pendingProgressTotalTime - spec.pendingProgressElapsedTime) / 3600000, done)
    work.price = g_i18n:formatMoney(spec.pendingServicePrice or 0)
    for _, breakdownId in ipairs(spec.pendingRepairQueue) do
        table.insert(work.repairs, getFaultName(breakdownId))
    end
    for _, breakdownId in ipairs(spec.pendingInspectionQueue) do
        table.insert(work.inspections, getFaultName(breakdownId))
    end
    for partId, startWear in pairs(spec.pendingOverhaulPartStart) do
        table.insert(work.renewed, {name = RMS_DebugReading.getPartName(partId), from = startWear, to = spec.pendingOverhaulPartTarget[partId]})
    end
    table.sort(work.renewed, function(a, b) return a.name < b.name end)
    for key, start in pairs(spec.pendingServiceClockStart) do
        table.insert(work.serviceTo, {name = key, from = start, to = spec.pendingServiceClockTarget[key]})
    end
    table.sort(work.serviceTo, function(a, b) return a.name < b.name end)
end

---Collects the names of the implements attached, through the chain
-- @param table vehicle vehicle
-- @param table names names found
-- @return table names names found
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

---Returns the state of the reversible fan
-- @param table spec RMS specialization of the vehicle
-- @return string text state of the fan
local function getReversibleFanText(spec)
    local fan = RMS_Config.THERMAL.REVERSIBLE_FAN
    if spec.fanReversalTime > 0 then
        return "reversing"
    elseif spec.year < fan.AUTO_MIN_YEAR then
        return "from the cab only"
    end
    return string.format("next in %d min", math.ceil((fan.AUTO_INTERVAL_MS - spec.fanRunningSinceReversal) / 60000))
end

---Returns a row charting heat flows
-- @param string label label of the row
-- @param float net net heat flow (deg C per ms)
-- @param table flows heat flows
-- @return table row chart row
local function chartRow(label, net, flows)
    return {label = label, kind = ROW.CHART, net = perMinute(net), unit = "°C/min", flows = flows}
end

---Returns a heat flow of a chart
-- @param string name name of the flow
-- @param float value heat flow (deg C per ms)
-- @return table flow flow of the chart
local function flow(name, value)
    return {name = name, value = perMinute(value)}
end

---Reads the engine, gearbox and hydraulic temperatures and heat flows
-- @param table spec RMS specialization of the vehicle
-- @param table groups groups of the machine view by title
local function readHeat(spec, groups)
    local rows = {}
    local heat = spec.engineHeatBalance
    if spec.isElectricVehicle then
        table.insert(rows, itemsRow("Motor", {item("temperature", temperature(spec.engineTemperature)), item("fan", pct(heat.fan or 0))}))
        table.insert(rows, chartRow("Heat", (heat.totalHeat or 0) - (heat.totalCooling or 0),
            {flow("motor", heat.totalHeat), flow("cooling", -(heat.totalCooling or 0))}))
    else
        local engine = {item("temperature", temperature(spec.engineTemperature)), item("thermostat", pct(spec.thermostatState)),
            item("fan", pct(heat.fan or 0))}
        if spec.hasReversibleFan then
            table.insert(engine, item("reversible fan", getReversibleFanText(spec)))
        end
        table.insert(rows, itemsRow("Engine", engine))
        table.insert(rows, chartRow("Heat", (heat.totalHeat or 0) - (heat.totalCooling or 0), {flow("engine", heat.totalHeat),
            flow("radiator", -(heat.radiatorCooling or 0)), flow("driving", -(heat.speedCooling or 0)), flow("air", -(heat.convectionCooling or 0))}))
    end

    local isCommon = spec.hasCommonSump
    if spec.fluidCapacities.transmissionOil > 0 and (spec.systems.transmission.enabled or isCommon and spec.systems.hydraulics.enabled) then
        local oil = spec.transmissionHeatBalance
        local gearsHeat = (oil.totalHeat or 0) - (oil.idleHeat or 0) - (oil.ptoHeat or 0) - (oil.hydraulicHeat or 0)
        local items = {item("temperature", temperature(spec.rawTransmissionTemperature))}
        if spec.rawTransmissionTemperature ~= -99 then
            table.insert(items, item("gauge", temperature(spec.transmissionTemperature)))
        end
        table.insert(items, item("thermostat", pct(spec.transmissionThermostatState)))
        if isCommon then
            table.insert(items, item("sump", "shared with the hydraulics"))
        end
        table.insert(rows, itemsRow("Gearbox oil", items))
        table.insert(rows, chartRow("Oil heat", (oil.totalHeat or 0) - (oil.totalCooling or 0), {flow("idling", oil.idleHeat),
            flow("gears", gearsHeat), flow("PTO", oil.ptoHeat), flow("hydraulics", oil.hydraulicHeat), flow("cooler", -(oil.coolerCooling or 0)),
            flow("driving", -(oil.speedCooling or 0)), flow("air", -(oil.convectionCooling or 0))}))
    end
    if RMS_Thermal.getHasSeparateHydraulicCircuit(spec) then
        local items = {item("temperature", temperature(spec.rawHydraulicTemperature))}
        if spec.rawHydraulicTemperature ~= -99 then
            table.insert(items, item("gauge", temperature(spec.hydraulicTemperature)))
        end
        table.insert(rows, itemsRow("Hydraulic oil", items))
    end
    groups["Engine and heat"] = {rows = rows}
end

---Reads the fluid levels, losses, filters and dirt
-- @param table vehicle vehicle
-- @param table spec RMS specialization of the vehicle
-- @param table groups groups of the machine view by title
local function readFluids(vehicle, spec, groups)
    ---Returns the notes of a pump, the lean it stays covered to and the air it drew, and whether it draws air
    -- @param string circuit fluid circuit
    -- @return table notes notes of the pump
    -- @return boolean isAir true while it draws air
    local function pickup(circuit)
        local partId = RMS_Fluids.PICKUP_PARTS[circuit]
        if not RMS_Fluids.hasCircuit(vehicle, circuit) or not RMS_Breakdowns.BreakdownRegistry[partId].isApplicable(vehicle) then
            return {}, false
        end
        local notes = {}
        local isAir = spec.pickupUncovered[circuit] == true
        if isAir then
            table.insert(notes, "DRAWS AIR")
        else
            local margin = math.deg(math.atan(math.max(RMS_Fluids.getPickupMargin(RMS_Fluids.getLevel(vehicle, circuit)), 0)))
            table.insert(notes, string.format("covered to %.0f°", margin))
        end
        if vehicle.isServer and (spec.pickupAirTime[partId] or 0) > 0 then
            table.insert(notes, string.format("air %.0f s", spec.pickupAirTime[partId]))
        end
        return notes, isAir
    end
    ---Returns a gauge row
    -- @param string label label of the row
    -- @param float share share filled, 0 to 1
    -- @param table? notes notes of the row
    -- @param boolean? isAlert true to show it as an alert
    -- @return table row gauge row
    local function gauge(label, share, notes, isAlert)
        return {label = label, share = share, value = pct(share), note = table.concat(notes or {}, SEP), alert = isAlert == true}
    end
    local gauges = {}
    if RMS_Fluids.hasCircuit(vehicle, "engineOil") then
        local notes, isAir = pickup("engineOil")
        if RMS_Fluids.getNeedsLowAshOil(vehicle) then
            table.insert(notes, pct(spec.engineOilSuitedShare) .. " suited")
        end
        table.insert(gauges, gauge("engine oil", spec.engineOilLevel, notes, isAir))
    end
    if spec.systems.cooling.enabled then
        table.insert(gauges, gauge("coolant", spec.coolantLevel))
    end
    if spec.systems.transmission.enabled then
        local notes, isAir = pickup("transmissionOil")
        table.insert(gauges, gauge("transmission", spec.transmissionOilLevel, notes, isAir))
    end
    if spec.systems.hydraulics.enabled then
        local notes, isAir = pickup("hydraulicFluid")
        table.insert(gauges, gauge("hydraulic", RMS_Fluids.getLevel(vehicle, "hydraulicFluid"), notes, isAir))
    end
    local rows = {{label = "Levels", kind = ROW.GAUGES, gauges = gauges}}
    if vehicle.isServer then
        table.insert(rows, itemsRow("", {item("oil leans", string.format("%.0f°", math.deg(math.atan(RMS_Fluids.getSumpLean(vehicle)))))}))
    end

    local losses = {}
    if not vehicle:getIsMotorStarted() then
        table.insert(losses, item("", "none, " .. (spec.isElectricVehicle and "motor off" or "engine stopped")))
    else
        if spec.systems.engine.enabled and not spec.isElectricVehicle then
            table.insert(losses, item("oil burnt", string.format("%.2f L/h of play",
                RMS_Consumables.getEngineOilBurnRate(vehicle) * RMS_Fluids.getCapacity(vehicle, "engineOil"))))
        end
        for _, leak in ipairs({{"coolant", "coolant", spec.coolantLeakRate}, {"transmission", "transmissionOil", spec.transmissionOilLeakRate},
            {"hydraulic", "hydraulicFluid", spec.hydraulicFluidLeakRate}}) do
            if leak[3] > 0 then
                table.insert(losses, item(leak[1] .. " leak", string.format("%.2f L/h of play", leak[3] * RMS_Fluids.getCapacity(vehicle, leak[2]))))
            end
        end
        if #losses == 0 then
            table.insert(losses, item("", "no leak"))
        end
    end
    table.insert(rows, itemsRow("Losses", losses))
    groups["Fluids"] = {rows = rows}

    local filters = {}
    if not spec.isElectricVehicle then
        local air = gauge("air", spec.airFilterClogging)
        air.note = "residue " .. pct(spec.airFilterResidue)
        table.insert(filters, air)
    end
    table.insert(filters, gauge("radiator", spec.radiatorClogging))
    if not spec.isElectricVehicle then
        table.insert(filters, gauge("fuel", spec.fuelFilterClogging))
    end
    table.insert(filters, gauge("hydraulic", spec.hydraulicFilterClogging))
    for _, filter in ipairs({{"TRANSMISSION_FILTER_CLOGGING", "transmission"}, {"ADBLUE_FILTER_CLOGGING", "AdBlue"},
        {"SPARK_PLUG_WEAR", "spark plugs"}}) do
        local entry = RMS_Consumables.getFilterOfBreakdown(filter[1])
        if RMS_Consumables.getHasFilter(vehicle, entry) then
            table.insert(filters, gauge(filter[2], spec[entry.stateKey]))
        end
    end
    local dirt = vehicle.spec_washable ~= nil and pct(vehicle:getDirtAmount()) or "never dirty"
    groups["Filters and dirt"] = {rows = {{label = "Filters", kind = ROW.GAUGES, gauges = filters, caption = "clogged"},
        itemsRow("Dirt", {item("machine", dirt), item("debris", yesNo(spec.hasDebris)),
            item("clogging rate", string.format("×%.1f", math.max(spec.radiatorCloggingRate, spec.airFilterCloggingRate)))})}}
end

---Returns the smoke and exhaust gas rows
-- @param table spec RMS specialization of the vehicle
-- @return table smoke smoke row
-- @return table gas exhaust gas row
local function readExhaustRows(spec)
    local smoke = spec.exhaustSmoke
    local smokeItems = {item("", "no smoke")}
    if smoke.isActive then
        smokeItems = {item("black", pct(smoke.soot)), item("blue", pct(smoke.oil)), item("white", pct(smoke.unburnt)),
            item("opacity", pct(smoke.opacity)), item("vapour", pct(smoke.vapourOpacity or 0))}
    end
    -- shimmer: light deflection at the outlet, in mrad
    local gasItems = {item("", "no plume")}
    if smoke.isActive then
        gasItems = {item("temperature", string.format("%.0f °C", smoke.gasTemperature)), item("speed", string.format("%.1f m/s", smoke.exitSpeed)),
            item("shimmer", string.format("%.2f mrad", smoke.heatDeflection * 1000)), item("wind", string.format("%.1f m/s", smoke.windSpeed)),
            item("sheltered", pct(smoke.pipeShelter))}
    elseif smoke.gasTemperature ~= nil then
        gasItems = {item("", "engine stopped"), item("line", string.format("%.0f °C", smoke.gasTemperature)),
            item("shimmer", string.format("%.2f mrad", smoke.heatDeflection * 1000))}
    end
    return itemsRow("Smoke", smokeItems), itemsRow("Exhaust gas", gasItems)
end

---Reads the exhaust, or the traction battery of an electric machine
-- @param table vehicle vehicle
-- @param table spec RMS specialization of the vehicle
-- @param table groups groups of the machine view by title
local function readExhaust(vehicle, spec, groups)
    if spec.isElectricVehicle then
        -- Native electric consumption is kWh/h, equivalent to kW
        local packIndex = vehicle:getConsumerFillUnitIndex(FillType.ELECTRICCHARGE)
        local energy, capacity = vehicle:getFillUnitFillLevel(packIndex), vehicle:getFillUnitCapacity(packIndex)
        groups["Traction battery"] = {rows = {
            itemsRow("Pack", {item("charge", pct(energy / capacity)), item("energy", string.format("%.1f of %.1f kWh", energy, capacity)),
                item("drawing", vehicle:getIsMotorStarted() and string.format("%.0f kW", vehicle.spec_motorized.lastFuelUsage) or "nothing")}),
            itemsRow("Pack health", {item("capacity left", pct(RMS_ElectricDrive.getCapacityFactor(vehicle))),
                item("temperature", string.format("%.0f °C", spec.tractionBatteryTempC)),
                item("charging", yesNo(RMS_ElectricDrive.getIsCharging(vehicle)))})}}
        return
    end
    local smokeRow, gasRow = readExhaustRows(spec)
    local rows = {smokeRow, gasRow}
    if spec.hasParticulateFilter then
        table.insert(rows, itemsRow("DPF", {item("soot", pct(spec.fuelState.particulateFilterLevel)),
            item("ash", pct(spec.fuelState.particulateFilterAsh)), item("regenerating", yesNo(spec.fuelState.isParticulateFilterRegenerating)),
            item("derated", yesNo(spec.isEngineDerated))}))
    end
    local defIndex = vehicle:getConsumerFillUnitIndex(FillType.DEF)
    if defIndex ~= nil then
        local tank = RMS_AdBlue.getInducement(vehicle)
        local cause = tank ~= nil and string.lower(tank) .. " tank"
            or spec.scrInducementHours > 0 and string.format("dosing fault, %.1f h", spec.scrInducementHours) or "none"
        table.insert(rows, itemsRow("AdBlue", {item("tank", pct(vehicle:getFillUnitFillLevelPercentage(defIndex))),
            item("per diesel", string.format("%.1f %%", RMS_AdBlue.getRatio(vehicle) * 100)), item("derate", cause),
            item("low tank", RMS_AdBlue.getHasInducement(vehicle) and "derates" or "warns only")}))
    end
    groups["Exhaust"] = {rows = rows}
end

---Reads the battery, rest, draw, currents and resistance
-- @param table spec RMS specialization of the vehicle
-- @param table groups groups of the machine view by title
local function readElectrical(spec, groups)
    local rows = {}
    local balance = spec.electricalBalance
    local rating = spec.electricalRating
    local label = spec.isElectricVehicle and "12 V battery" or "Battery"
    if balance == nil then
        table.insert(rows, itemsRow(label, {item("voltage", string.format("%.1f V", spec.systemVoltageV)), item("charge", pct(spec.batterySoc))}))
        groups["Electrical"] = {rows = rows}
        return
    end
    -- Suppress negative zero after rounding
    local batteryA = math.floor(balance.batteryA * 10 + 0.5) / 10
    table.insert(rows, itemsRow(label, {item("voltage", string.format("%.1f V", spec.systemVoltageV)),
        item("charge", string.format("%s (%.0f of %.0f Ah)", pct(spec.batterySoc), spec.batterySoc * balance.capacityAh, balance.capacityAh)),
        item("current", string.format("%+.1f A", batteryA == 0 and 0 or batteryA))}))
    table.insert(rows, itemsRow("At rest", {item("voltage", string.format("%.2f V", RMS_Electrical.getRestingVoltage(rating, spec.batterySoc))),
        item("ambient", string.format("%.0f °C", balance.ambientC)),
        item("cold holds back", pct(balance.floorSoc) .. (balance.reachSoc < balance.floorSoc and ", given under a starting aid" or ""))}))
    local partner = spec.externalPowerConnection
    table.insert(rows, itemsRow("Parked draw", {item("draw", string.format("%.0f mA", RMS_Electrical.getRestingDraw(spec) * 1000)),
        item("isolator", spec.batteryIsolated and "open" or "closed"), item("cables", partner ~= nil and "to " .. partner:getFullName() or "none"),
        item("charger", balance.chargerOutA > 0 and string.format("%.1f A", balance.chargerOutA) or "none")}))
    local loads = balance.loads
    local currents = {item(spec.isElectricVehicle and "converter" or "alternator", string.format("up to %.1f A", balance.generatorA)),
        item("base", string.format("%.1f A", loads.base)), item("cab", string.format("%.1f A", loads.cab)),
        item("lights", string.format("%.1f A", loads.lights))}
    if not spec.isElectricVehicle then
        table.insert(currents, item("starter", string.format("%.1f A", loads.starter)))
        table.insert(currents, item("preheat", string.format("%.1f A", loads.preheat)))
    end
    table.insert(rows, itemsRow("Currents", currents))
    if not spec.isElectricVehicle then
        table.insert(rows, itemsRow("Resistance", {item("battery", string.format("%.1f mOhm", balance.resistanceOhm * 1000)),
            item("circuit", string.format("%.1f mOhm", balance.circuitOhm * 1000))}))
    end
    groups["Electrical"] = {rows = rows}
end

---Reads the last start, the start sequence and the preheat
-- @param table vehicle vehicle
-- @param table spec RMS specialization of the vehicle
-- @param table groups groups of the machine view by title
local function readStarting(vehicle, spec, groups)
    if spec.isElectricVehicle then
        return
    end
    local rows = {}
    if spec.electricalBalance ~= nil then
        table.insert(rows, itemsRow("Last start", {item("under the starter", string.format("%.1f V", RMS_Electrical.getStartingVoltage(vehicle))),
            item("cranking speed", pct(RMS_Electrical.getCrankingSpeed(vehicle))), item("starter", RMS_Breakdowns.getStarterFamily(vehicle))}))
    end
    local need = RMS_Start.getCrankNeed(vehicle)
    table.insert(rows, itemsRow("Start", {item("state", string.format("%s for %.1f s", RMS_Start.STATE_NAME[spec.startState], spec.startTimerMs / 1000)),
        item("starter heat", string.format("%.0f K", spec.starterHeatK)),
        item("cranked", string.format("%.1f of %s s", spec.crankProgressS, need == nil and "0.0" or need == math.huge and "never" or string.format("%.1f", need)))}))
    if RMS_Preheat.isDieselVehicle(vehicle) then
        table.insert(rows, itemsRow("Preheat", {item("needed", string.format("%.1f s", spec.preheatRequiredMs / 1000)),
            item("left", string.format("%.1f s", spec.preheatRemainingMs / 1000)), item("lamp test", spec.preheatLampTestActive and "on" or "over"),
            item("glow fault", tostring(RMS_Preheat.getGlowPlugFailureSeverity(vehicle))),
            item("cold start fault", tostring(spec.preheatColdStartFaultSeverity))}))
    end
    groups["Starting"] = {rows = rows}
end

---Returns the gear text of a motor
-- @param table motor motor of the vehicle
-- @return string text gear
local function getGear(motor)
    if motor.forwardGears == nil and motor.backwardGears == nil then
        local directions = {D = "forward", R = "reverse", N = "neutral"}
        return directions[motor:getGearToDisplay(false)]
    end
    local group, hasGroups = motor:getGearGroupToDisplay(false)
    local shifting = motor.gearShiftMode == VehicleMotor.SHIFT_MODE_AUTOMATIC and "automatic shifting"
        or motor.gearShiftMode == VehicleMotor.SHIFT_MODE_MANUAL_CLUTCH and "manual with clutch" or "manual shifting"
    return string.format("%s%s, %s", motor:getGearToDisplay(false), hasGroups and " in range " .. group or "", shifting)
end

---Reads the motor, load, drive train, axles, traction, chassis and overload
-- @param table vehicle vehicle
-- @param table spec RMS specialization of the vehicle
-- @param table groups groups of the machine view by title
local function readDrive(vehicle, spec, groups)
    local rows = {}
    local isRunning = vehicle:getIsMotorStarted()
    local stopped = spec.isElectricVehicle and "motor off" or "engine stopped"
    local motor = vehicle:getMotor()
    local drivePower = isRunning and motor:getMotorRotSpeed() * (motor:getMotorAppliedTorque() - motor:getMotorExternalTorque()) or 0
    local otherPower = isRunning and motor:getMotorRotSpeed() * motor:getMotorExternalTorque() or 0
    table.insert(rows, itemsRow("Motor", {item("speed", string.format("%.1f km/h", vehicle:getLastSpeed())),
        item(spec.isElectricVehicle and "motor" or "engine", string.format("%.0f rpm", motor:getLastModulatedMotorRpm())), item("gear", getGear(motor)),
        item("to the transmission", string.format("%.0f kW", drivePower)), item("to PTO and hydraulics", string.format("%.0f kW", otherPower))}))
    table.insert(rows, itemsRow("Load", isRunning and {item("RMS", pct(spec.dynamicMotorLoad)), item("game", pct(vehicle:getMotorLoadPercentage()))}
        or {item("", stopped)}))

    local drive = spec.drivetrain
    local modes = {[RMS_Drivetrain.MODE.TWO_WD] = "2WD", [RMS_Drivetrain.MODE.FOUR_WD] = "4WD", [RMS_Drivetrain.MODE.AUTO] = "auto"}
    if RMS_Drivetrain.getIsAvailable(vehicle) then
        local mode = RMS_Drivetrain.getHasCenterDifferential(vehicle) and modes[drive.driveMode] or "no selector"
        table.insert(rows, itemsRow("Drive train", {item("mode", mode), item("4WD", RMS_Drivetrain.getIsFrontAxleDriven(vehicle) and "engaged" or "off"),
            item("diff lock", drive.diffLockEngaged and "on" or "off"), item("windup", pct(drive.windupStress))}))
    else
        table.insert(rows, itemsRow("Drive train", {item("", RMS_Config.DRIVETRAIN.ENABLED and "permanent drive, left to the game"
            or "left to the game, option off")}))
    end
    local kinds = {[RMS_Drivetrain.PARK_KIND.LEVER] = "lever", [RMS_Drivetrain.PARK_KIND.AUTOMATIC] = "automatic",
        [RMS_Drivetrain.PARK_KIND.AIR_VALVE] = "air"}
    table.insert(rows, itemsRow("Park brake", RMS_Drivetrain.getIsParkBrakeManaged(vehicle)
        and {item("brake", drive.parkBrake and "on" or "off"), item("kind", kinds[drive.parkKind])} or {item("", "left to the game, option off")}))
    local axles = {}
    for _, axle in ipairs(RMS_Drivetrain.getAxleRatios(vehicle)) do
        table.insert(axles, item(axle.label, string.format("%s, up to %.2f", axle.ratio ~= nil and string.format("%.2f to 1", axle.ratio) or "standing",
            axle.cap)))
    end
    if #axles > 0 then
        table.insert(rows, itemsRow("Axles", axles))
    end
    table.insert(rows, itemsRow("Traction", {item("tool draft", spec.activeDraftMaxForce > 0
        and string.format("%.1f of %.1f kN", spec.activeDraftEffectiveForceCap, spec.activeDraftMaxForce) or "no tool pulling"),
        item("slip", pct(spec.wheelSlipIntensity)), item("ground grip", string.format("%.2f", spec.avgTireGroundFrictionCoeff))}))
    local chassis = spec.systemWearNow.chassis or {}
    local impacts = spec.terrainImpacts.count
    table.insert(rows, itemsRow("Chassis", {item("impacts", impacts == 0 and "none"
        or string.format("%d, last -%.1f km/h", impacts, spec.terrainImpacts.lastSpeedLoss)),
        item("steering play", string.format("%.1f°", chassis.steerPlay or 0)), item("pull", string.format("%.1f°", chassis.steerPull or 0))}))

    local wearScale = RMS_Config.CORE.BASE_SYSTEMS_WEAR / RMS_Config.CORE.REFERENCE_SYSTEMS_WEAR
    local warning = RMS_Config.CORE.AVG_STRESS_WARNING_THRESHOLD * wearScale
    local overloads = {}
    for _, system in ipairs(SYSTEMS) do
        local stats = spec.factorStats[system.key]
        if stats ~= nil and stats._avgStress ~= nil and stats._avgStress > 0 then
            table.insert(overloads, item(getSystemName(system, spec.isElectricVehicle):lower(), pct(stats._avgStress / warning) .. " of the warning"))
        end
    end
    table.insert(rows, itemsRow("Overload", #overloads > 0 and overloads or {item("", "none")}))
    groups["Drive"] = {rows = rows}
end

---Reads the harvest, header drive, PTO, attached tools, trip and worker
-- @param table vehicle vehicle
-- @param table spec RMS specialization of the vehicle
-- @param table groups groups of the machine view by title
local function readWorkRows(vehicle, spec, groups)
    local rows = {}
    if spec.systems.harvest.enabled and not RMS_Utils.getIsSelfPropelledMower(vehicle) then
        local state = spec.harvestState or {}
        local effect = spec.activeEffects.HARVEST_GRAIN_LOSS
        local loss = math.clamp(effect ~= nil and effect.value or 0, 0, RMS_Config.CORE.HARVEST_FACTOR_DATA.MAX_GRAIN_LOSS)
        local items = {item("kind", state.kind or RMS_Drivetrain.getHarvestKind(vehicle)),
            item("measured by", state.source == "rh" and "Realistic Harvesting" or "RMS")}
        if spec.isHarvestRunning then
            table.insert(items, item("crop", tostring(state.crop):lower()))
            table.insert(items, item("flow", string.format("%.0f t/h", state.tonPerHour)))
            table.insert(items, item("rotary", string.format("%.0f kW", state.rotaryKw)))
            table.insert(items, item("work", pct(state.effort) .. " of full"))
            table.insert(items, item("chopper", string.format("%.0f kW", state.chopperKw)))
        else
            table.insert(items, item("state", "stopped"))
        end
        table.insert(items, item("harvested", string.format("%.0f t", state.tons or 0)))
        table.insert(items, item("grain lost to wear", string.format("%.1f %%", loss * 100)))
        table.insert(rows, itemsRow("Harvest", items))
    end
    local drive = spec.headerDrive
    if drive ~= nil then
        local header = drive.header
        local C = RMS_Config.CORE.HEADER_DRIVE
        local items = {item("header", header ~= nil and header:getFullName() or "none")}
        if header ~= nil then
            table.insert(items, item("driven", drive.isTurning and string.format("%.0f kW", drive.powerW / 1000) or "stopped"))
        end
        table.insert(items, item("starts", tostring(drive.starts)))
        if drive.starts > 0 then
            table.insert(items, item("last start", string.format("%s speed, %.0f kJ", pct(drive.lastStartShare), drive.lastStartJ / 1000)))
        end
        local clutch = "holds"
        if header ~= nil and RMS_Greasing.getIsLimiterSeized(header) then
            clutch = "seized, grease the header"
        elseif drive.slipMs > 0 then
            clutch = string.format("slipping %.1f of %.1f s", drive.slipMs / 1000, drive.slipLimitMs / 1000)
        end
        table.insert(items, item("slip clutch", clutch))
        table.insert(items, item("slips past", string.format("work %s", pct(C.SLIP_EFFORT))))
        table.insert(rows, itemsRow("Header drive", items))
    end
    if RMS_Utils.getHasDashboardScreen(vehicle) and RMS_Utils.getHasPtoDisplay(vehicle) then
        local isTurning, rpm = RMS_Utils.getPtoDisplay(vehicle)
        local items = {item("state", isTurning and "on" or "off")}
        table.insert(items, item("speed", rpm ~= nil and string.format("%.0f rpm", rpm) or "-"))
        if spec.systems.pto.enabled then
            table.insert(items, item("power", string.format("%.0f kW", spec.ptoPower)))
            table.insert(items, item("used", pct(spec.ptoUtilization)))
            table.insert(items, item("engagements", tostring(spec.ptoEngagementCount)))
        end
        table.insert(rows, itemsRow("PTO", items))
    end
    local attached = {}
    for _, name in ipairs(collectToolNames(vehicle, {})) do
        table.insert(attached, item("", name))
    end
    if #attached > 0 then
        table.insert(attached, item("hitch", spec.raisingMass > 0 and string.format("lifting %.1f t", spec.raisingMass)
            or spec.isImplementLowered and "lowered" or "raised"))
    else
        table.insert(attached, item("", "none"))
    end
    table.insert(rows, itemsRow("Attached", attached))
    table.insert(rows, itemsRow("Trip", {
        item("burnt", string.format("%.1f l in %.1f h", spec.tripFuelLitres, spec.tripEngineTime / 3600000)),
        item("worked", string.format("%.2f ha with %.1f l", spec.tripWorkedHectares, spec.tripWorkFuelLitres)),
        item("width", string.format("%.1f m", spec.tripWorkingWidth or 0))}))
    if vehicle:getIsAIActive() then
        table.insert(rows, itemsRow("Worker", {item("overload", string.format("%.2f", spec.aiWorkerOverload)),
            item("speed limit", spec.aiWorkerSpeedLimit ~= nil and string.format("%.1f km/h", spec.aiWorkerSpeedLimit) or "none"),
            item("throttle without moving", string.format("%.0f of %d s", spec.aiWorkerBlockedMs / 1000, RMS_Config.CORE.AI_WORKER.BLOCKED_SECONDS))}))
    end
    local addon = vehicle.spec_CVTaddon
    if RMS_Utils.hasCVTAddon(vehicle) then
        table.insert(rows, itemsRow("CVT Addon", {item("damage", string.format("%.4f", addon.CVTdamage or 0)),
            item("damage warning", addon.forDBL_warndamage == 1 and "on" or "off"), item("heat warning", addon.forDBL_warnheat == 1 and "on" or "off"),
            item("high pressure", addon.forDBL_highpressure == 1 and "on" or "off")}))
    end
    groups["Work"] = {rows = rows}
end

---Reads the surroundings and the lights
-- @param table vehicle vehicle
-- @param table spec RMS specialization of the vehicle
-- @param table groups groups of the machine view by title
local function readAround(vehicle, spec, groups)
    local rows = {itemsRow("Around", {item("place", vehicle:getIsOnField() and "on a field" or "off field"), item("dust", yesNo(spec.isRaisingDust)),
        item("ground wet", pct(g_currentMission.environment.weather:getGroundWetness())), item("roof", spec.isUnderRoof and "under a roof" or "outdoors"),
        item("weather", getWeatherName())})}
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
        table.insert(rows, itemsRow("Lights", {item("lit", #lit > 0 and table.concat(lit, ", ") or "off"),
            item("out", #out > 0 and table.concat(out, ", ") or "none")}))
    end
    groups["Around"] = {rows = rows}
end

---Reads the warranty and the part covers
-- @param table vehicle vehicle
-- @param table spec RMS specialization of the vehicle
-- @param table groups groups of the machine view by title
local function readWarranty(vehicle, spec, groups)
    local months, hours = vehicle:getWarrantyLimits()
    local state = RealisticMechanicalSystems.getIsWithinWarrantyLimits(vehicle) and "active" or "expired"
    if vehicle.propertyState == VehiclePropertyState.LEASED then state = "lease" end
    if spec.warrantyVoided then state = "lost to a remap" end
    local rows = {itemsRow("Warranty", {item("plan", (spec.warrantyPlan == 1 and "factory" or "extension") .. ", " .. state),
        item("until age", string.format("%d months", months)), item("until meter", string.format("%d h of play", hours))})}
    for _, cover in ipairs({{"Part cover", spec.partWarranty, ""}, {"Used cover", spec.usedPartWarranty, ", parts only"}}) do
        local ids = {}
        for id, expiry in pairs(cover[2]) do
            if vehicle.age < expiry then table.insert(ids, id) end
        end
        table.sort(ids)
        for _, id in ipairs(ids) do
            table.insert(rows, itemsRow(cover[1], {item(RMS_DebugReading.getPartName(id), string.format("until age %d months%s", cover[2][id], cover[3]))}))
        end
    end
    groups["Warranty"] = {rows = rows}
end

---Reads the machine view, group by group
-- @param table vehicle vehicle
-- @param table spec RMS specialization of the vehicle
-- @param table reading reading being built
local function readMachine(vehicle, spec, reading)
    local groups = {}
    readHeat(spec, groups)
    readAround(vehicle, spec, groups)
    readService(vehicle, spec, groups)
    readFluids(vehicle, spec, groups)
    readWarranty(vehicle, spec, groups)
    readExhaust(vehicle, spec, groups)
    readElectrical(spec, groups)
    readStarting(vehicle, spec, groups)
    readDrive(vehicle, spec, groups)
    readWorkRows(vehicle, spec, groups)
    reading.machine = {}
    for _, group in ipairs(RMS_DebugReading.GROUPS) do
        local read = groups[group.title]
        if read ~= nil then
            table.insert(reading.machine, {title = group.title, column = group.column, note = read.note or "", rows = read.rows})
        end
    end
end

---Returns the reading of a machine
-- @param table vehicle vehicle
-- @return table reading reading
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

---Finds a row of the machine view by its group and label
-- @param table reading reading
-- @param string title title of the group
-- @param string label label of the row
-- @return table? row row, nil when not found
-- @return table? group group of the row
-- @return integer? index index of the row in its group
function RMS_DebugReading.findRow(reading, title, label)
    for _, group in ipairs(reading.machine) do
        if group.title == title then
            for index, row in ipairs(group.rows) do
                if row.label == label then
                    return row, group, index
                end
            end
        end
    end
    return nil
end

---Puts the exhaust this computer draws in a reading
-- @param table vehicle vehicle
-- @param table reading reading
function RMS_DebugReading.useLocalExhaust(vehicle, reading)
    local spec = vehicle.spec_RealisticMechanicalSystems
    if spec.isElectricVehicle then
        return
    end
    for _, row in ipairs({readExhaustRows(spec)}) do
        local _, group, index = RMS_DebugReading.findRow(reading, "Exhaust", row.label)
        group.rows[index] = row
    end
end

-- Fixed field order; field names are not sent
local ROWS = {list = {fields = {{1, "string"}, {2, "string"}}}}
local STRINGS = {list = "string"}
local ITEMS = {list = {fields = {{"label", "string"}, {"value", "string"}}}}
local SCHEMA = {fields = {
    {"name", "string"},
    {"kind", STRINGS},
    {"vitals", {fields = {{"condition", "string"}, {"lifeUsed", "string"}, {"reliability", "string"}, {"faults", "string"},
        {"faultsNote", "string"}}}},
    {"facts", ROWS},
    {"legend", {fields = {{"fullAfter", "float"}, {"horizon", "float"}}}},
    {"systems", {list = {fields = {{"name", "string"}, {"condition", "float"}, {"risk", "float"}, {"wearing", "float"}, {"normal", "float"},
        {"wearTaken", "float"}, {"shares", {list = {fields = {{"name", "string"}, {"share", "float"}}}}},
        {"parts", {list = {fields = {{"name", "string"}, {"wear", "float"}, {"chance", "float"}, {"isWorn", "bool"}, {"stage", "byte"},
        {"tick", "float"}, {"strain", "bool"}, {"causes", {list = {fields = {{"cause", "byte"}, {"share", "float"}}}}}}}}}}}}},
    {"wearNow", {list = {fields = {{"system", "string"},
        {"causes", {list = {fields = {{"label", "string"}, {"measure", "string"}, {"rate", "float"}}}}}}}}},
    {"faults", {list = {fields = {{"name", "string"}, {"system", "string"}, {"stage", "byte"}, {"stages", "byte"}, {"progress", "float"},
        {"next", "string"}, {"isSeen", "bool"}, {"flags", STRINGS}, {"notes", STRINGS}}}}},
    {"alerts", {fields = {{"lamps", {list = {fields = {{"text", "string"}, {"color", "byte"}}}}}, {"display", STRINGS}, {"codes", STRINGS},
        {"effects", ITEMS}}}},
    {"work", {fields = {{"isActive", "bool"}, {"title", "string"}, {"chips", STRINGS}, {"price", "string"}, {"progress", "float"},
        {"progressText", "string"}, {"repairs", STRINGS}, {"inspections", STRINGS},
        {"renewed", {list = {fields = {{"name", "string"}, {"from", "float"}, {"to", "float"}}}}},
        {"serviceTo", {list = {fields = {{"name", "string"}, {"from", "float"}, {"to", "float"}}}}}}}},
    {"machine", {list = {fields = {{"title", "string"}, {"column", "byte"}, {"note", "string"},
        {"rows", {list = {fields = {{"label", "string"}, {"kind", "byte"}, {"items", ITEMS}, {"net", "float"}, {"unit", "string"},
        {"flows", {list = {fields = {{"name", "string"}, {"value", "float"}}}}},
        {"gauges", {list = {fields = {{"label", "string"}, {"share", "float"}, {"value", "string"}, {"note", "string"}, {"alert", "bool"}}}}},
        {"caption", "string"}, {"level", "float"}, {"due", "float"}, {"left", "string"}, {"overdue", "bool"}}}}}}}}}
}}

local EMPTY = {string = "", float = 0, byte = 0}

---Writes a value by its schema
-- @param integer streamId stream id
-- @param any schema schema of the value
-- @param any value value
local function writeValue(streamId, schema, value)
    if schema == "string" or schema == "float" or schema == "byte" then
        if value == nil then
            value = EMPTY[schema]
        end
        if schema == "string" then
            streamWriteString(streamId, value)
        elseif schema == "float" then
            streamWriteFloat32(streamId, value)
        else
            streamWriteUInt8(streamId, value)
        end
    elseif schema == "bool" then
        streamWriteBool(streamId, value == true)
    elseif schema.list ~= nil then
        value = value or {}
        -- a list can pass 255 entries: a cover row per part
        streamWriteUInt16(streamId, #value)
        for _, entry in ipairs(value) do
            writeValue(streamId, schema.list, entry)
        end
    else
        value = value or {}
        for _, field in ipairs(schema.fields) do
            writeValue(streamId, field[2], value[field[1]])
        end
    end
end

---Reads a value by its schema
-- @param integer streamId stream id
-- @param any schema schema of the value
-- @return any value value
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
        local entries = {}
        for index = 1, streamReadUInt16(streamId) do
            entries[index] = readValue(streamId, schema.list)
        end
        return entries
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
