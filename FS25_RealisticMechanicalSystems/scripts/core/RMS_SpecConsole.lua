-- Copyright © 2026 Squallqt. All rights reserved.

---Console commands of the mod, acting on the vehicle the player sits in

local ensureFactorStats = RealisticMechanicalSystems.ensureFactorStats
local getVehicleOperatingHours = RealisticMechanicalSystems.getVehicleOperatingHours

RealisticMechanicalSystems.ConsoleCommands = {}

local consolePrint = print

---Prints locally, or sends a server command's output to its requester
function RealisticMechanicalSystems.ConsoleCommands:printOutput(...)
    if self._outputConnection ~= nil then
        local values = {}
        for index = 1, select("#", ...) do
            values[index] = tostring(select(index, ...))
        end
        self._outputConnection:sendEvent(RMS_ConsoleCommandEvent.new("__response", table.concat(values, "\t")))
        return
    end
    consolePrint(...)
end

local function print(...)
    RealisticMechanicalSystems.ConsoleCommands:printOutput(...)
end

---Returns the vehicle the commands act on
-- @return table? vehicle target vehicle, nil when none qualifies
function RealisticMechanicalSystems.ConsoleCommands:getTargetVehicle()
    if RealisticMechanicalSystems.ConsoleCommands._overrideVehicle ~= nil then
        local v = RealisticMechanicalSystems.ConsoleCommands._overrideVehicle
        if v.spec_RealisticMechanicalSystems ~= nil then
            return v
        end
        print("RMS Error: Override vehicle does not have RealisticMechanicalSystems support.")
        return nil
    end
    local vehicle = g_localPlayer ~= nil
        and g_localPlayer.getCurrentVehicle ~= nil
        and g_localPlayer:getCurrentVehicle()
        or nil
    if not vehicle or not vehicle.spec_RealisticMechanicalSystems then
        print("RMS Error: You must be in a vehicle with RealisticMechanicalSystems support.")
        return nil
    end
    return vehicle
end

---Target vehicle on the server; a client sends the command there instead
-- @return table? vehicle nil on a client or without a target
function RealisticMechanicalSystems.ConsoleCommands:getServerVehicle(command, argOne, argTwo)
    local vehicle = self:getTargetVehicle()
    if vehicle ~= nil and not g_currentMission:getIsServer() then
        RMS_ConsoleCommandEvent.sendToServer(command, argOne, argTwo, vehicle)
        return nil
    end
    return vehicle
end

---Number of entries of a table, nil counting as empty
local function countEntries(entries)
    local count = 0
    for _ in pairs(entries or {}) do
        count = count + 1
    end
    return count
end

local function parseArguments(argString, ...)
    local extraArgs = { ... }
    local hasExtraArgs = #extraArgs > 0

    if hasExtraArgs then
        local args = {}

        local function appendToken(token)
            if token == nil then
                return
            end
            token = tostring(token)
            if token == "" then
                return
            end

            if string.find(token, "%s") then
                for splitToken in string.gmatch(token, "[^%s]+") do
                    table.insert(args, splitToken)
                end
            else
                table.insert(args, token)
            end
        end

        appendToken(argString)
        for _, extraArg in ipairs(extraArgs) do
            appendToken(extraArg)
        end

    return args
end

    if argString == nil or type(argString) ~= 'string' or argString == '' then
        return {}
    end

    local args = {}
    for arg in string.gmatch(argString, "[^%s]+") do
        table.insert(args, arg)
    end
    return args
end

local function parsePathTokens(path)
    local tokens = {}
    if type(path) ~= "string" or path == "" then
        return tokens
    end

    for token in string.gmatch(path, "[^%.]+") do
        local numberToken = tonumber(token)
        if numberToken ~= nil then
            table.insert(tokens, numberToken)
        else
            table.insert(tokens, token)
        end
    end

    return tokens
end

---Console word as a Lua value: boolean, nil, number, else the word
local function parseConsoleValue(rawValue)
    local lowerValue = string.lower(tostring(rawValue))
    if lowerValue == "true" then
        return true
    end
    if lowerValue == "false" then
        return false
    end
    if lowerValue == "nil" then
        return nil
    end

    local numberValue = tonumber(rawValue)
    if numberValue ~= nil then
        return numberValue
    end

    return rawValue
end

local function resolvePathParent(rootTable, fullPath)
    if type(rootTable) ~= "table" then
        return nil, nil, nil, "Root is not a table."
    end

    local tokens = parsePathTokens(fullPath)
    if #tokens == 0 then
        return nil, nil, nil, "Path is empty."
    end

    local current = rootTable
    for i = 1, #tokens - 1 do
        local key = tokens[i]
        if type(current) ~= "table" then
            return nil, nil, nil, string.format("Path segment '%s' is not a table.", tostring(key))
        end

        current = current[key]
        if current == nil then
            return nil, nil, nil, string.format("Path segment '%s' does not exist.", tostring(key))
        end
    end

    return current, tokens[#tokens], tokens
end

local function getPrimaryFuelConsumerInfo(vehicle)
    if vehicle == nil or vehicle.spec_motorized == nil or vehicle.spec_motorized.consumers == nil then
        return nil, nil
    end

    local preferredTypes = { FillType.DIESEL, FillType.METHANE, FillType.ELECTRICCHARGE }

    local function isPreferred(fillType)
        for _, preferredType in ipairs(preferredTypes) do
            if fillType == preferredType then
                return true
            end
        end
        return false
    end

    local fallbackConsumer = nil
    local defFillType = FillType.DEF
    for _, consumer in pairs(vehicle.spec_motorized.consumers) do
        if consumer ~= nil and consumer.fillUnitIndex ~= nil and consumer.fillType ~= nil then
            if isPreferred(consumer.fillType) then
                return consumer.fillUnitIndex, consumer.fillType
            end

            if fallbackConsumer == nil and (defFillType == nil or consumer.fillType ~= defFillType) then
                fallbackConsumer = consumer
            end
        end
    end

    if fallbackConsumer ~= nil then
        return fallbackConsumer.fillUnitIndex, fallbackConsumer.fillType
    end

    return nil, nil
end

local function syncConsoleCloggingState(vehicle, spec, parent, key)
    if vehicle == nil or spec == nil or parent ~= spec then
        return false
    end

    if key ~= "radiatorClogging" and key ~= "airFilterClogging" then
        return false
    end

    spec.radiatorClogging = math.clamp(tonumber(spec.radiatorClogging) or 0, 0.0, 1.0)
    spec.airFilterClogging = math.clamp(tonumber(spec.airFilterClogging) or 0, 0.0, 1.0)

    RealisticMechanicalSystems.raiseRMSDirty(vehicle, RealisticMechanicalSystems.SYNC_GROUP.FIELDCARE)

    return true
end

local function printSpecValueRecursive(prefix, value, visited, depth)
    visited = visited or {}
    depth = depth or 0

    if type(value) ~= "table" then
        print(string.format("%s = %s", prefix, tostring(value)))
        return
    end

    if visited[value] then
        print(string.format("%s = <recursive>", prefix))
        return
    end

    visited[value] = true
    print(string.format("%s = {", prefix))

    local keys = {}
    for key, _ in pairs(value) do
        table.insert(keys, key)
    end

    table.sort(keys, function(a, b)
        if type(a) == type(b) then
            if type(a) == "number" or type(a) == "string" then
                return a < b
            end
        end
        return tostring(a) < tostring(b)
    end)

    local indent = string.rep("  ", depth + 1)
    for _, key in ipairs(keys) do
        local childValue = value[key]
        if type(childValue) == "table" then
            print(string.format("%s[%s] = {", indent, tostring(key)))
            printSpecValueRecursive(indent .. "  ", childValue, visited, depth + 1)
            print(string.format("%s}", indent))
        else
            print(string.format("%s[%s] = %s", indent, tostring(key), tostring(childValue)))
        end
    end

    print(string.format("%s}", string.rep("  ", depth)))
end

---Sets a spec variable, usage rms_setSpecVar <path> <value>
function RealisticMechanicalSystems.ConsoleCommands:setSpecVar(rawArgs, rawValue)
    local vehicle = self:getServerVehicle("setSpecVar", rawArgs, rawValue)
    if vehicle == nil then
        return
    end

    local path = nil
    local valueToken = nil

    if rawValue ~= nil then
        path = tostring(rawArgs)
        valueToken = tostring(rawValue)
    else
        local args = parseArguments(rawArgs)
        path = args and args[1] or nil
        valueToken = args and args[2] or nil
    end

    if path == nil or valueToken == nil then
        print("RMS Error: Usage: rms_setSpecVar <path> <value>")
        print("Example: rms_setSpecVar batterySoc 0.5")
        return
    end

    local spec = vehicle.spec_RealisticMechanicalSystems
    local value = parseConsoleValue(valueToken)
    local parent, key, _, err = resolvePathParent(spec, path)
    if parent == nil then
        print(string.format("RMS Error: Invalid RMS spec path '%s': %s", path, tostring(err)))
        return
    end

    local oldValue = parent[key]
    if parent == spec and (key == "conditionLevel" or key == "transmissionTemperature" or key == "hydraulicTemperature") then
        print("RMS Error: This value is calculated. Set system condition or the raw oil temperature instead.")
        return
    end
    for _, system in pairs(spec.systems) do
        if parent == system and key == "condition" then
            print("RMS Error: This value is calculated from the wear of its parts. Use rms_setSystemCondition or rms_setPartWear instead.")
            return
        end
    end
    if parent == spec.electricalRating or parent == spec and (key == "systemVoltageV" or key == "rawSystemVoltageV") then
        print("RMS Error: This value is calculated. Set batterySoc instead.")
        return
    end
    if parent == spec and key == "batterySoc" and (type(value) ~= "number" or value ~= value or value < 0 or value > 1) then
        print("RMS Error: The state of charge is a number between 0 and 1.")
        return
    end
    if parent == spec and (key == "rawTransmissionTemperature" or key == "rawHydraulicTemperature") then
        if type(value) ~= "number" or value ~= value or value <= -math.huge or value >= math.huge or value == -99 then
            print("RMS Error: Oil temperature must be a finite number in degrees Celsius.")
            return
        end
        if key == "rawHydraulicTemperature" and not RMS_Thermal.getHasSeparateHydraulicCircuit(spec) then
            print("RMS Error: This vehicle has no separate hydraulic oil circuit. For a common sump, use rawTransmissionTemperature.")
            return
        end
    end
    if parent == spec and (key == "rawEngineTemperature" or key == "engineTemperature") then
        if RMS_Thermal.setEngineTemperature(vehicle, value) == nil then
            print("RMS Error: Invalid physical engine temperature.")
            return
        end
    else
        parent[key] = value
    end
    if parent == spec then
        if key == "rawEngineTemperature" or key == "engineTemperature" then
            spec._thermalEngineWorldTime = RMS_Thermal.getWorldTimeMS()
            spec._thermalEngineAmbient = nil
        elseif key == "rawTransmissionTemperature" or key == "rawHydraulicTemperature" then
            spec._thermalOilWorldTime = RMS_Thermal.getWorldTimeMS()
            spec._thermalOilAmbient = nil
        end
    end
    -- Clamped before the change is printed
    local isCloggingSynced = syncConsoleCloggingState(vehicle, spec, parent, key)
    local name = vehicle:getFullName()
    print(string.format("RMS: spec_RealisticMechanicalSystems.%s changed on '%s': %s -> %s", path, name, tostring(oldValue), tostring(parent[key])))
    if isCloggingSynced then
        print(string.format("RMS: clogging state synced on '%s' (radiator=%.2f, airFilter=%.2f).", name,
            spec.radiatorClogging, spec.airFilterClogging))
    end
end

---Prints a spec variable, usage rms_printSpecVar <path>
function RealisticMechanicalSystems.ConsoleCommands:printSpecVar(rawArgs)
    local vehicle = self:getServerVehicle("printSpecVar", rawArgs)
    if vehicle == nil then
        return
    end

    local path = parseArguments(rawArgs)[1]
    if path == nil then
        print("RMS Error: Usage: rms_printSpecVar <path>")
        print("Example: rms_printSpecVar systems.engine")
        return
    end

    local spec = vehicle.spec_RealisticMechanicalSystems
    local holder, field, _, problem = resolvePathParent(spec, path)
    if holder == nil then
        print(string.format("RMS Error: Invalid RMS spec path '%s': %s", path, tostring(problem)))
        return
    end
    -- The engine temperature is brought up to date when read
    if holder == spec and (field == "rawEngineTemperature" or field == "engineTemperature") then
        RMS_Thermal.getEngineTemperature(vehicle)
    end

    local value = holder[field]
    local fullPath = "spec_RealisticMechanicalSystems." .. path
    if value == nil then
        print(string.format("RMS: %s = nil", fullPath))
    elseif type(value) == "table" then
        print(string.format("RMS: %s on '%s':", fullPath, vehicle:getFullName()))
        printSpecValueRecursive(fullPath, value, {}, 0)
    else
        print(string.format("RMS: %s on '%s' = %s", fullPath, vehicle:getFullName(), tostring(value)))
    end
end

---Lists every breakdown id of the registry
function RealisticMechanicalSystems.ConsoleCommands:listBreakdowns()
    local lines = {}
    for id, data in pairs(RMS_Breakdowns.BreakdownRegistry) do
        local ways = data.branches ~= nil and string.format(", fails in %d ways", data.branches) or ""
        table.insert(lines, string.format(" - %s (%s)%s", id, data.part or data.system or "No name", ways))
    end
    table.sort(lines)

    print("--- Available Breakdowns ---")
    print(#lines > 0 and table.concat(lines, "\n") or "  No breakdowns found in the registry.")
    print("----------------------------")
end

---Adds a breakdown, usage rms_addBreakdown [id] [stage] [way]
function RealisticMechanicalSystems.ConsoleCommands:addBreakdown(rawArgs, rawArgTwo, rawArgThree)
    local stageAndWay = rawArgThree ~= nil and string.format("%s %s", tostring(rawArgTwo), rawArgThree) or rawArgTwo
    local vehicle = self:getServerVehicle("addBreakdown", rawArgs, stageAndWay)
    if vehicle == nil then
        return
    end
    local args = parseArguments(rawArgs, rawArgTwo, rawArgThree)

    -- Without an id, one the machine can have, at its first stage
    if args[1] == nil then
        local id = vehicle:getRandomBreakdown()
        if id ~= nil then
            vehicle:addBreakdown(id, 1)
            print(string.format("RMS: Added random breakdown '%s' to '%s'.", id, vehicle:getFullName()))
        end
        return
    end

    local breakdownId = string.upper(args[1])
    local stage = tonumber(args[2] or 1)

    local registryEntry = RMS_Breakdowns.BreakdownRegistry[breakdownId]
    if not registryEntry then
        print(string.format("RMS Error: Breakdown with ID '%s' not found.", breakdownId))
        self:listBreakdowns()
        return
    end
    
    local maxStages = #registryEntry.stages
    if stage == nil or stage ~= math.floor(stage) or stage < 1 or stage > maxStages then
        print(string.format("RMS Error: Invalid integer stage '%s' for breakdown '%s'. Valid stages are 1 to %d.", tostring(args[2]), breakdownId, maxStages))
        return
    end

    if registryEntry.isApplicable ~= nil and not registryEntry.isApplicable(vehicle) then
        print(string.format("RMS Error: Breakdown with ID '%s' not applicable to %s", breakdownId, vehicle:getFullName()))
        return
    end

    local branch = tonumber(args[3])
    if args[3] ~= nil and (registryEntry.branches == nil or branch == nil or branch ~= math.floor(branch)
        or branch < 1 or branch > registryEntry.branches) then
        print(string.format("RMS Error: Invalid way '%s' for breakdown '%s'. %s", tostring(args[3]), breakdownId,
            registryEntry.branches ~= nil and string.format("Valid ways are 1 to %d.", registryEntry.branches) or "It fails in a single way."))
        return
    end
    
    local present = vehicle:getActiveBreakdowns()[breakdownId]
    if present ~= nil then
        local presentWay = registryEntry.branches ~= nil and string.format(", way %d", present.branch) or ""
        print(string.format("RMS Error: '%s' is already on '%s' at stage %d%s. Remove it first: rms_removeBreakdown %s",
            breakdownId, vehicle:getFullName(), present.stage, presentWay, breakdownId))
        return
    end

    local filter = RMS_Consumables.getFilterOfBreakdown(breakdownId)
    if filter ~= nil then
        vehicle.spec_RealisticMechanicalSystems[filter.stateKey] = RMS_Config.FIELD_CARE.FILTER_STAGE_THRESHOLDS[stage]
        RMS_Consumables.syncFilterBreakdowns(vehicle)
    else
        vehicle:addBreakdown(breakdownId, { stage = stage, branch = branch })
    end
    local added = vehicle:getActiveBreakdowns()[breakdownId]
    local way = registryEntry.branches ~= nil and added ~= nil and string.format(", way %d of %d", added.branch, registryEntry.branches) or ""
    print(string.format("RMS: Added breakdown '%s' at stage %d%s to '%s'.", breakdownId, stage, way, vehicle:getFullName()))
end

---Removes a breakdown, usage rms_removeBreakdown [id]
function RealisticMechanicalSystems.ConsoleCommands:removeBreakdown(rawArgs)
    local vehicle = self:getServerVehicle("removeBreakdown", rawArgs)
    if vehicle == nil then
        return
    end
    local id = parseArguments(rawArgs)[1]
    if id == nil then
        RMS_Consumables.renewFilters(vehicle)
        vehicle:removeBreakdown()
        return
    end

    -- A clogged filter clears with a new filter
    id = string.upper(id)
    if RMS_Consumables.getFilterOfBreakdown(id) == nil then
        vehicle:removeBreakdown(id)
    else
        RMS_Consumables.renewFilters(vehicle, id)
    end
end

---Changes a breakdown stage, usage rms_advanceBreakdown [id] [stage|reverse]
function RealisticMechanicalSystems.ConsoleCommands:changeBreakdownStage(rawArgs, rawArgTwo)
    local vehicle = self:getServerVehicle("changeBreakdownStage", rawArgs, rawArgTwo)
    if vehicle == nil then
        return
    end
    local args = parseArguments(rawArgs, rawArgTwo)

    local spec = vehicle.spec_RealisticMechanicalSystems
    local advancedCount = 0

    local function parseStageArg(rawValue)
        if rawValue == nil then
            return nil
        end

        local lowered = string.lower(tostring(rawValue))
        if lowered == "true" or lowered == "reverse" or lowered == "down" or lowered == "prev" then
            return true
        end

        local numeric = tonumber(rawValue)
        if numeric ~= nil and numeric >= 1 and numeric == math.floor(numeric) then
            return numeric
        end

        return nil
    end

    if not args or not args[1] then
        if next(spec.activeBreakdowns) == nil then
            print("RMS: No active breakdowns to advance.")
            return
        end

        for id, breakdown in pairs(vehicle:getActiveBreakdowns()) do
            local previousStage = breakdown.stage
            vehicle:changeBreakdownStage(id)
            if breakdown.stage ~= previousStage then
                print(string.format("RMS: Changed breakdown '%s' from stage %d to stage %d.", id, previousStage, breakdown.stage))
                advancedCount = advancedCount + 1
            else
                print(string.format("RMS: Breakdown '%s' stage unchanged (%d).", id, breakdown.stage))
            end
        end
    else
        local breakdownId = string.upper(args[1])
        local foundBreakdown = spec.activeBreakdowns[breakdownId]

        if not foundBreakdown then
            print(string.format("RMS Error: Active breakdown with ID '%s' not found on this vehicle.", breakdownId))
            return
        end

        local targetStage = parseStageArg(args[2])
        local registryEntry = RMS_Breakdowns.BreakdownRegistry[breakdownId]
        if args[2] ~= nil and (targetStage == nil
            or (type(targetStage) == "number" and registryEntry ~= nil and targetStage > #registryEntry.stages)) then
            print("RMS Error: Use an existing integer stage or reverse. Usage: rms_advanceBreakdown [id] [stage|reverse]")
            return
        end
        local previousStage = foundBreakdown.stage
        vehicle:changeBreakdownStage(breakdownId, targetStage)
        if foundBreakdown.stage ~= previousStage then
            print(string.format("RMS: Changed breakdown '%s' from stage %d to stage %d.", breakdownId, previousStage, foundBreakdown.stage))
            advancedCount = advancedCount + 1
        else
            print(string.format("RMS: Breakdown '%s' stage unchanged (%d).", breakdownId, foundBreakdown.stage))
        end
    end

    if advancedCount > 0 then
        print(string.format("RMS: Recalculated effects for '%s'.", vehicle:getFullName()))
    end
end

---Sets one system condition, usage rms_setSystemCondition [system] [0-1]
function RealisticMechanicalSystems.ConsoleCommands:setSystemCondition(rawArgs, rawArgTwo)
    local vehicle = self:getServerVehicle("setSystemCondition", rawArgs, rawArgTwo)
    if vehicle == nil then
        return
    end
    local args = parseArguments(rawArgs, rawArgTwo)
    local spec = vehicle.spec_RealisticMechanicalSystems
    local requestedSystem = args[1]
    if requestedSystem == nil then
        print("RMS Error: Missing system. Usage: rms_setSystemCondition [system] [0.0-1.0]")
        return
    end

    local systemKey = RMS_Utils.resolveConsoleSystemKey(spec, requestedSystem)

    if systemKey == false then
        local availableSystems = {}
        for key, _ in pairs(spec.systems or {}) do
            table.insert(availableSystems, tostring(key))
        end
        table.sort(availableSystems)
        print(string.format("RMS Error: Unknown system '%s'. Available systems: %s", tostring(requestedSystem), table.concat(availableSystems, ", ")))
        return
    end

    local value = tonumber(args and args[2] or nil)
    if value == nil or value < 0 or value > 1 then
        print("RMS Error: Invalid value. Please provide a number between 0.0 and 1.0.")
        return
    end

    for _, partId in ipairs(spec.systemParts[systemKey]) do
        spec.partWear[partId] = 1 - value
        spec.partImpactWear[partId] = nil
        spec.partDrawnWear[partId] = nil
    end
    RealisticMechanicalSystems.refreshSystemCondition(spec, systemKey)
    print(string.format("RMS: Set condition for system '%s' on '%s' to %.2f.", tostring(systemKey), vehicle:getFullName(), value))

    vehicle:updateConditionLevel()
end

---Sets every system condition, usage rms_setCondition [0-1]
function RealisticMechanicalSystems.ConsoleCommands:setCondition(rawArgs)
    local vehicle = self:getServerVehicle("setCondition", rawArgs)
    if vehicle == nil then
        return
    end
    local spec = vehicle.spec_RealisticMechanicalSystems
    local targetCondition = tonumber(parseArguments(rawArgs)[1])
    if targetCondition == nil or targetCondition < 0 or targetCondition > 1 then
        print("RMS Error: Invalid value. Please provide a number between 0.0 and 1.0.")
        return
    end

    local changedSystems = 0

    for systemKey, systemData in pairs(spec.systems) do
        if systemData.enabled ~= false then
            for _, partId in ipairs(spec.systemParts[systemKey]) do
                spec.partWear[partId] = 1 - targetCondition
                spec.partImpactWear[partId] = nil
                spec.partDrawnWear[partId] = nil
            end
            RealisticMechanicalSystems.refreshSystemCondition(spec, systemKey)
            changedSystems = changedSystems + 1
        end
    end

    if changedSystems == 0 then
        print("RMS Error: No enabled systems were found on the current vehicle.")
        return
    end

    vehicle:updateConditionLevel()
    print(string.format("RMS: Set condition for %d enabled systems on '%s' to %.3f. Final overall condition: %.3f.",
        changedSystems, vehicle:getFullName(), targetCondition, vehicle.spec_RealisticMechanicalSystems.conditionLevel or 0))
end

function RealisticMechanicalSystems.ConsoleCommands:setPartWear(rawArgs, rawArgTwo)
    local vehicle = self:getServerVehicle("setPartWear", rawArgs, rawArgTwo)
    if vehicle == nil then
        return
    end
    local args = parseArguments(rawArgs, rawArgTwo)

    local spec = vehicle.spec_RealisticMechanicalSystems
    local partId = args and args[1] and string.upper(args[1]) or nil
    local systemKey = nil
    for key, parts in pairs(spec.systemParts) do
        for _, id in ipairs(parts) do
            if id == partId then
                systemKey = key
            end
        end
    end
    if systemKey == nil then
        local partIds = {}
        for _, parts in pairs(spec.systemParts) do
            for _, id in ipairs(parts) do
                table.insert(partIds, id)
            end
        end
        table.sort(partIds)
        print(string.format("RMS Error: Unknown part '%s'. Parts of this vehicle: %s", tostring(partId), table.concat(partIds, ", ")))
        return
    end

    local value = tonumber(args[2])
    if value == nil or value < 0 then
        print("RMS Error: Invalid value. Please provide a wear from 0.0, 1.0 being the life of the machine.")
        return
    end

    spec.partWear[partId] = value
    spec.partImpactWear[partId] = nil
    spec.partDrawnWear[partId] = nil
    RealisticMechanicalSystems.refreshSystemCondition(spec, systemKey)
    vehicle:updateConditionLevel()
    print(string.format("RMS: Set wear of part '%s' on '%s' to %.2f, risk x%.2f that of a new part.", partId, vehicle:getFullName(),
        value, RMS_Utils.getPartRiskRatio(partId, value)))
end

---Sets the service clocks, usage rms_setService [0-1] [clock]
function RealisticMechanicalSystems.ConsoleCommands:setService(rawArgs, rawArgTwo)
    local vehicle = self:getServerVehicle("setService", rawArgs, rawArgTwo)
    if vehicle == nil then
        return
    end
    local args = parseArguments(rawArgs, rawArgTwo)
    local spec = vehicle.spec_RealisticMechanicalSystems
    -- Without a level, the clocks of a fresh service
    local value = args[1] == nil and 1.0 or tonumber(args[1])
    if value == nil or value < 0 or value > 1 then
        print("RMS Error: Invalid value. Please provide a number between 0.0 and 1.0.")
        return
    end

    local clockKey = args[2]
    local setClockKeys = {}
    for _, clock in ipairs(RealisticMechanicalSystems.SERVICE_CLOCKS) do
        if clockKey == nil or clock.key == clockKey then
            spec[clock.levelKey] = value
            table.insert(setClockKeys, clock.key)
        end
    end

    if #setClockKeys == 0 then
        print("RMS Error: Unknown service clock. Use engine, transmission, hydraulic or coolant.")
        return
    end

    print(string.format("RMS: Set service clocks %s for '%s' to %.2f.", table.concat(setClockKeys, ", "), vehicle:getFullName(), value))
end

function RealisticMechanicalSystems.ConsoleCommands:reinitializeVehicle(care)
    local vehicle = self:getServerVehicle("reinitializeVehicle", care)
    if vehicle == nil then
        return
    end

    local spec = vehicle.spec_RealisticMechanicalSystems
    if (vehicle.isUnderService ~= nil and vehicle:isUnderService()) or (tonumber(spec.maintenanceTimer) or 0) > 0 then
        print("RMS Error: Wait until the current workshop procedure is finished before reinitializing this vehicle.")
        return
    end

    care = care or RMS_Utils.getOwnerCare(vehicle:getDamageAmount())
    if RMS_Config.CORE.USED_VEHICLE_HISTORY.CARE_CAUSES[care] == nil then
        print("Usage: rms_reinitializeVehicle [careful|regular|neglected]")
        return
    end

    RealisticMechanicalSystems.initializeUsedVehicle(vehicle, care, true)
    print(string.format("RMS: Reinitialized '%s' as a used machine of %.1f hours, previous owner %s. Overall condition: %.3f.",
        vehicle:getFullName(), vehicle:getOperatingTime() / 3600000, care, spec.conditionLevel))
end

---Re-resolves fluid capacities, keeping the liters
function RealisticMechanicalSystems.ConsoleCommands:reinitializeFluidCapacities()
    local vehicle = self:getServerVehicle("reinitializeFluidCapacities")
    if vehicle == nil then
        return
    end

    RMS_Fluids.reinitializeVehicleCapacities(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    print(string.format(
        "RMS: Re-resolved physical fluid capacities for '%s' from %s: engine=%.2f L, coolant=%.2f L, transmission=%.2f L, hydraulic=%.2f L.",
        vehicle:getFullName(),
        tostring(spec.fluidCapacitySource or "unknown"),
        RMS_Fluids.getCapacity(vehicle, "engineOil"),
        RMS_Fluids.getCapacity(vehicle, "coolant"),
        RMS_Fluids.getCapacity(vehicle, "transmissionOil"),
        RMS_Fluids.getCapacity(vehicle, "hydraulicFluid")
    ))
end

---Entries of a list joined by commas, a dash for none
local function joinList(list)
    return (list == nil or #list == 0) and "-" or table.concat(list, ", ")
end

---Prints the service and workshop state variables
function RealisticMechanicalSystems.ConsoleCommands:getServiceState()
    local vehicle = self:getServerVehicle("getServiceState")
    if vehicle == nil then
        return
    end

    local spec = vehicle.spec_RealisticMechanicalSystems
    local elapsed, total = spec.pendingProgressElapsedTime or 0, spec.pendingProgressTotalTime or 0
    local progress = total > 0 and math.floor(math.clamp(elapsed / total, 0, 1) * 100) or 0
    local selectedForRepair = 0
    for _, breakdown in pairs(spec.activeBreakdowns or {}) do
        if breakdown.isSelectedForRepair then
            selectedForRepair = selectedForRepair + 1
        end
    end
    local queues = {
        { "pendingSelectedBreakdowns", spec.pendingSelectedBreakdowns or {} },
        { "pendingInspectionQueue", spec.pendingInspectionQueue or {} },
        { "pendingRepairQueue", spec.pendingRepairQueue or {} }
    }
    local serialize = RMS_Utils.serializeNumericMap

    local lines = {
        "--- RMS Service State ---",
        "Vehicle: " .. vehicle:getFullName(),
        string.format("State: current=%s planned=%s workshop=%s",
            tostring(spec.currentState), tostring(spec.plannedState), tostring(spec.workshopType)),
        string.format("Timer: maintenanceTimer=%.0fms elapsed=%.0fms total=%.0fms progress=%d%% stepIndex=%d",
            spec.maintenanceTimer or 0, elapsed, total, progress, spec.pendingProgressStepIndex or 0),
        string.format("Options: optionOne=%s optionTwo=%s optionThree=%s price=%s", tostring(spec.serviceOptionOne),
            tostring(spec.serviceOptionTwo), tostring(spec.serviceOptionThree), tostring(spec.pendingServicePrice)),
        string.format("Targets: serviceStart=%s serviceTarget=%s overhaulParts=%d", serialize(spec.pendingServiceClockStart),
            serialize(spec.pendingServiceClockTarget), countEntries(spec.pendingOverhaulPartTarget)),
        string.format("Levels: service engine=%.4f transmission=%.4f hydraulics=%.4f coolant=%.4f condition=%.4f",
            spec.serviceLevel, spec.transmissionServiceLevel, spec.hydraulicServiceLevel, spec.coolantServiceLevel,
            spec.conditionLevel or 0),
        "Service calendar: " .. serialize(spec.serviceCalendar),
        string.format("Queues: selected=%d inspection=%d repair=%d", #queues[1][2], #queues[2][2], #queues[3][2]),
        string.format("Breakdowns: active=%d selectedForRepair=%d", countEntries(spec.activeBreakdowns), selectedForRepair)
    }
    for _, queue in ipairs(queues) do
        if #queue[2] > 0 then
            table.insert(lines, queue[1] .. ": " .. table.concat(queue[2], ", "))
        end
    end
    for _, line in ipairs(lines) do
        print(line)
    end
end

---Prints an entry of the service log, its condition data when verbose
local function printServiceLogEntry(index, entry, isVerbose)
    local date = entry.date
    local dateText = date == nil and "n/a" or string.format("%02d/%02d/%04d", date.day or 0, date.month or 0, date.year or 0)
    print(string.format("[%d] id=%s type=%s date=%s price=%s visible=%s completed=%s", index, tostring(entry.id),
        tostring(entry.type), dateText, tostring(entry.price), tostring(entry.isVisible), tostring(entry.isCompleted ~= false)))
    print(string.format("    options: one=%s two=%s three=%s location=%s", tostring(entry.optionOne),
        tostring(entry.optionTwo), tostring(entry.optionThree), tostring(entry.location)))
    if not isVerbose then
        return
    end

    local data = entry.conditionData or {}
    local selected = data.selectedBreakdowns or {}
    print(string.format("    conditionData: year=%s opHours=%s age=%s condition=%s service=%s reliability=%s",
        tostring(data.year), tostring(data.operatingHours), tostring(data.age), tostring(data.condition),
        tostring(data.service), tostring(data.reliability)))
    print(string.format("    conditionData: batterySoc=%s systems=%d", tostring(data.batterySoc), countEntries(data.systems)))
    print(string.format("    conditionData: activeBreakdowns=%d selectedBreakdowns=%d", countEntries(data.activeBreakdowns), #selected))
    print("    selectedBreakdowns: " .. joinList(selected))
end

---Prints the service log, usage rms_showServiceLog [index]
function RealisticMechanicalSystems.ConsoleCommands:showServiceLog(rawArgs)
    local vehicle = self:getServerVehicle("showServiceLog", rawArgs)
    if vehicle == nil then
        return
    end

    local entries = vehicle.spec_RealisticMechanicalSystems.maintenanceLog or {}
    if #entries == 0 then
        print("RMS: Service log is empty.")
        return
    end

    local requested = parseArguments(rawArgs)[1]
    if requested == nil then
        print(string.format("--- RMS Service Log (%d entries) ---", #entries))
        for index, entry in ipairs(entries) do
            printServiceLogEntry(index, entry, false)
        end
        return
    end

    local index = tonumber(requested)
    if index == nil or index % 1 ~= 0 or index < 1 or index > #entries then
        print(string.format("RMS Error: Invalid integer log index '%s'. Valid range: 1..%d", tostring(requested), #entries))
        return
    end
    print(string.format("--- RMS Service Log Entry %d/%d ---", index, #entries))
    printServiceLogEntry(index, entries[index], true)
end

---Prints how RMS reads the vehicle, its specializations on request
function RealisticMechanicalSystems.ConsoleCommands:getDebugVehicleInfo(rawArgs)
    local vehicle = self:getServerVehicle("getDebugVehicleInfo", rawArgs)
    if vehicle == nil then
        return
    end

    local motor = vehicle:getMotor()
    local category = g_storeManager:getItemByXMLFilename(vehicle.configFileName).categoryName
    local rating = vehicle.spec_RealisticMechanicalSystems.electricalRating
    print("--- Vehicle Debug Info ---")
    print("RawBrand: " .. g_brandManager:getBrandByIndex(vehicle:getBrand()).name)
    print("Name: " .. vehicle:getFullName())
    print("Type/Category: " .. vehicle.type.name .. "/" .. tostring(category))
    print("Property state: " .. tostring(vehicle.propertyState))
    print(string.format("%d V circuit: battery %.0f Ah, alternator %.0f A, starter %.1f kW (%.0f A), %d work lamps, base load %.0f A, calculators %s",
        12 * rating.seriesBatteries, rating.batteryCapacityAh, rating.alternatorA, rating.starterKw, rating.starterRatedA, rating.workLamps,
        rating.baseLoadA, tostring(rating.hasCalculators)))
    print("Transmission: " .. table.concat({ tostring(motor.minForwardGearRatio), tostring(motor.gearType), tostring(motor.groupType) }, ", "))
    print("RMS transmission type: " .. tostring(vehicle:getTransmissionType()))
    print("XML/shop transmission name: " .. tostring(RealisticMechanicalSystems.getTransmissionNameFromXML(vehicle)))
    if parseArguments(rawArgs)[1] == nil then
        return
    end

    local rule = "--------------------------"
    print(rule)
    local names = table.clone(vehicle.type.specializationNames)
    table.sort(names)
    print(string.format("Attached Specializations (%d total):", #names))
    for index, name in ipairs(names) do
        print(string.format("  %d. %s", index, name))
    end
    print(rule)
end

---Sets the dirt amount, usage rms_setDirtAmount [0.0-1.0]
function RealisticMechanicalSystems.ConsoleCommands:setDirtAmount(rawArgs)
    local vehicle = self:getServerVehicle("setDirtAmount", rawArgs)
    if vehicle == nil then
        return
    end
    if vehicle.spec_washable == nil then
        print(string.format("RMS Error: Vehicle '%s' is not washable.", vehicle:getFullName()))
        return
    end

    local amount = parseArguments(rawArgs)[1]
    if amount == nil then
        print("RMS Error: Missing argument. Usage: rms_setDirtAmount <amount>")
        print("Please provide a dirt amount between 0.0 (clean) and 1.0 (fully dirty).")
        return
    end
    local value = tonumber(amount)
    if value == nil or value < 0 or value > 1 then
        print("RMS Error: Invalid value. Please provide a number between 0.0 and 1.0.")
        return
    end

    vehicle:setDirtAmount(value)
    print(string.format("RMS: Set Dirt amount for '%s' to %.2f.", vehicle:getFullName(), value))
end

---Sets the greasing left of a machine and its implements
function RealisticMechanicalSystems.ConsoleCommands:setGreasing(rawArgs)
    local vehicle = self:getServerVehicle("setGreasing", rawArgs)
    if vehicle == nil then
        return
    end

    local value = tonumber(parseArguments(rawArgs)[1])
    if value == nil or value < 0 or value > 1 then
        print("RMS Error: Invalid value. Usage: rms_setGreasing <0.0-1.0>")
        return
    end

    local isGreased = false
    for _, child in ipairs(vehicle:getChildVehicles()) do
        if RMS_Greasing.getSpec(child) ~= nil and RMS_Greasing.getTiers(child) ~= nil then
            RMS_Greasing.setIntervalLeft(child, value)
            print(string.format("RMS: Set greasing for '%s' to %.2f, %d grease points due.", child:getFullName(), value,
                RMS_Greasing.getDuePoints(child)))
            isGreased = true
        end
    end
    if not isGreased then
        print(string.format("RMS Error: Vehicle '%s' has no grease points.", vehicle:getFullName()))
    end
end

---Sets the paint wear, usage rms_setPaintWear [0-1]
function RealisticMechanicalSystems.ConsoleCommands:setPaintWear(rawArgs)
    local vehicle = self:getServerVehicle("setPaintWear", rawArgs)
    if vehicle == nil then
        return
    end

    if vehicle.spec_wearable == nil then
        print(string.format("RMS Error: Vehicle '%s' has no paint wear.", vehicle:getFullName()))
        return
    end

    local value = tonumber(parseArguments(rawArgs)[1])
    if value == nil or value < 0 or value > 1 then
        print("RMS Error: Invalid value. Usage: rms_setPaintWear <0.0-1.0>")
        return
    end

    for _, nodeData in ipairs(vehicle.spec_wearable.wearableNodes) do
        vehicle:setNodeWearAmount(nodeData, value, true)
    end
    print(string.format("RMS: Set paint wear for '%s' to %.2f.", vehicle:getFullName(), value))
end

---Sets fuel or traction charge, usage rms_setFuelLevel [0-1 or 1-100]
function RealisticMechanicalSystems.ConsoleCommands:setFuelLevel(rawArgs)
    local vehicle = self:getServerVehicle("setFuelLevel", rawArgs)
    if vehicle == nil then
        return
    end

    local requested = parseArguments(rawArgs)[1]
    if requested == nil then
        print("RMS Error: Usage: rms_setFuelLevel <value>")
        print("Value: 0..1 is a fraction; above 1..100 is a percentage (use 0.01 for 1%).")
        print("Example: rms_setFuelLevel 0.25")
        print("Example: rms_setFuelLevel 25")
        return
    end
    local ratio = tonumber(requested)
    if ratio == nil then
        print("RMS Error: Invalid value. Expected number.")
        return
    end
    -- Above 1, a percentage
    if ratio > 100 then
        print("RMS Error: Value must be 0.0..1.0 or 0..100.")
        return
    elseif ratio > 1 then
        ratio = ratio / 100
    elseif ratio < 0 then
        print("RMS Error: Value must be between 0.0 and 1.0 (or 0..100%).")
        return
    end

    local fillUnit, fillType = getPrimaryFuelConsumerInfo(vehicle)
    if fillUnit == nil then
        print(string.format("RMS Error: Fuel consumer not found for '%s'.", vehicle:getFullName()))
        return
    end
    local capacity = vehicle:getFillUnitCapacity(fillUnit)
    if capacity <= 0 then
        print(string.format("RMS Error: Invalid fuel capacity for '%s' (fillUnit %s).", vehicle:getFullName(), tostring(fillUnit)))
        return
    end

    -- Through the fill unit, which keeps consumption and HUD in step
    local missing = capacity * ratio - vehicle:getFillUnitFillLevel(fillUnit)
    if missing > 0.0001 or missing < -0.0001 then
        vehicle:addFillUnitFillLevel(vehicle:getOwnerFarmId(), fillUnit, missing, fillType, ToolType.UNDEFINED)
    end
    local level = vehicle:getFillUnitFillLevel(fillUnit)
    print(string.format("RMS: Energy fill level set on '%s' -> %.1f / %.1f (%.1f%%), fillType=%s, fillUnit=%s",
        vehicle:getFullName(), level, capacity, level / capacity * 100, tostring(fillType), tostring(fillUnit)))
end

---Clears the accumulated wear factor statistics of the vehicle
function RealisticMechanicalSystems.ConsoleCommands:resetFactorStats()
    local vehicle = self:getServerVehicle("resetFactorStats")
    if vehicle == nil then
        return
    end

    -- Each counter restarts from zero at the hours of now
    local spec = vehicle.spec_RealisticMechanicalSystems
    local hours = getVehicleOperatingHours(vehicle)
    for _, stats in pairs(ensureFactorStats(spec)) do
        if type(stats) == "table" then
            for key, value in pairs(stats) do
                if tonumber(value) ~= nil then
                    stats[key] = 0
                end
            end
            stats.total = 0
            stats.operatingHours = hours
        end
    end
    spec.terrainImpacts.count = 0
    spec.terrainImpacts.lastSpeedLoss = 0
    spec.ptoEngagementCount = 0

    print(string.format("RMS: Factor stats reset for '%s'.", vehicle:getFullName()))
end

---Forces the exhaust smoke this computer draws on every vehicle
function RealisticMechanicalSystems.ConsoleCommands:exhaustOverride(rawArgs, ...)
    local args = parseArguments(rawArgs, ...)
    local first = args[1] ~= nil and string.lower(tostring(args[1])) or nil
    if first == nil or first == "off" then
        RMS_Exhaust.override = nil
        print("RMS: exhaust override off")
        return
    end

    local override = {}
    local names = {"opacity", "flow", "vapour"}
    for index, name in ipairs(names) do
        local token = args[index]
        if token ~= nil and token ~= "-" then
            local value = tonumber(token)
            if value == nil or value < 0 or (name ~= "vapour" and value > 1) then
                print("RMS Error: Usage: rms_exhaustOverride <opacity 0-1|-> [flow 0-1|-] [vapour >=0|-] | off")
                return
            end
            override[name] = value
        end
    end

    RMS_Exhaust.override = override
    print(string.format("RMS: exhaust override opacity %s flow %s vapour %s",
        tostring(override.opacity or "engine"), tostring(override.flow or "engine"), tostring(override.vapour or "engine")))
end

RealisticMechanicalSystems.ConsoleCommands.parseArguments = parseArguments
RealisticMechanicalSystems.ConsoleCommands.resolvePathParent = resolvePathParent

addConsoleCommand("rms_listBreakdowns", "Lists all available breakdown IDs.", "listBreakdowns", RealisticMechanicalSystems.ConsoleCommands)
addConsoleCommand("rms_addBreakdown", "Adds a breakdown. Usage: rms_addBreakdown [id] [stage] [way]", "addBreakdown", RealisticMechanicalSystems.ConsoleCommands)
addConsoleCommand("rms_removeBreakdown", "Removes a breakdown. Usage: rms_removeBreakdown [id]", "removeBreakdown", RealisticMechanicalSystems.ConsoleCommands)
addConsoleCommand("rms_advanceBreakdown", "Changes breakdown stages. Usage: rms_advanceBreakdown [id] [stage|reverse]", "changeBreakdownStage", RealisticMechanicalSystems.ConsoleCommands)
addConsoleCommand("rms_setCondition", "Sets condition for all enabled systems. Usage: rms_setCondition [0.0-1.0]", "setCondition", RealisticMechanicalSystems.ConsoleCommands)
addConsoleCommand("rms_setSystemCondition", "Sets system condition. Usage: rms_setSystemCondition [system] [0.0-1.0]", "setSystemCondition", RealisticMechanicalSystems.ConsoleCommands)
addConsoleCommand("rms_setPartWear", "Sets the wear of one part, 1.0 being the life of the machine. Usage: rms_setPartWear [breakdown id] [wear]", "setPartWear",
    RealisticMechanicalSystems.ConsoleCommands)
addConsoleCommand("rms_setService", "Sets vehicle service clocks. Usage: rms_setService [0.0-1.0] [engine|transmission|hydraulic|coolant]",
    "setService", RealisticMechanicalSystems.ConsoleCommands)
addConsoleCommand("rms_reinitializeVehicle", "Seeds the vehicle again as a used machine of its hours. Usage: rms_reinitializeVehicle [careful|regular|neglected]",
    "reinitializeVehicle", RealisticMechanicalSystems.ConsoleCommands)
addConsoleCommand("rms_reinitializeFluidCapacities", "Re-resolves physical fluid capacities while preserving liters.", "reinitializeFluidCapacities", RealisticMechanicalSystems.ConsoleCommands)
addConsoleCommand("rms_getServiceState", "Prints current service/workshop state variables.", "getServiceState", RealisticMechanicalSystems.ConsoleCommands)
addConsoleCommand("rms_showServiceLog", "Shows service log. Usage: rms_showServiceLog [integer index]", "showServiceLog", RealisticMechanicalSystems.ConsoleCommands)
addConsoleCommand("rms_getDebugVehicleInfo", "Prints how RMS reads the vehicle. Usage: rms_getDebugVehicleInfo [1 to list its specializations]",
    "getDebugVehicleInfo", RealisticMechanicalSystems.ConsoleCommands)
addConsoleCommand("rms_setDirtAmount", "Sets vehicle dirt amount. Usage: rms_setDirtAmount [0.0-1.0]", "setDirtAmount", RealisticMechanicalSystems.ConsoleCommands)
addConsoleCommand("rms_setPaintWear", "Sets vehicle paint wear. Usage: rms_setPaintWear [0.0-1.0]", "setPaintWear", RealisticMechanicalSystems.ConsoleCommands)
addConsoleCommand("rms_setGreasing", "Sets the greasing interval left of the vehicle and its implements, 0 making every grease point due. Usage: rms_setGreasing [0.0-1.0]", "setGreasing",
    RealisticMechanicalSystems.ConsoleCommands)
addConsoleCommand("rms_setFuelLevel", "Sets fuel or traction charge. Usage: rms_setFuelLevel [fraction 0..1 or percentage >1..100]", "setFuelLevel", RealisticMechanicalSystems.ConsoleCommands)
addConsoleCommand("rms_resetFactorStats", "Resets accumulated factor stats for current vehicle.", "resetFactorStats", RealisticMechanicalSystems.ConsoleCommands)
addConsoleCommand("rms_setSpecVar", "Sets physical RMS vehicle state, including raw oil temperatures. Usage: rms_setSpecVar <path> <value>", "setSpecVar", RealisticMechanicalSystems.ConsoleCommands)
addConsoleCommand("rms_printSpecVar", "Prints RMS specialization variable on current vehicle. Usage: rms_printSpecVar <path>", "printSpecVar", RealisticMechanicalSystems.ConsoleCommands)
addConsoleCommand("rms_exhaustOverride",
    "Forces the exhaust smoke this computer draws on every vehicle. Usage: rms_exhaustOverride <opacity 0-1|-> [flow 0-1|-] [vapour >=0|-] | off",
    "exhaustOverride", RealisticMechanicalSystems.ConsoleCommands)
