-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---Console commands of the mod, acting on the vehicle the player sits in

local ensureFactorStats = RealisticMechanicalSystems.ensureFactorStats
local getVehicleOperatingHours = RealisticMechanicalSystems.getVehicleOperatingHours
local initializeVehicleConditionFromVanillaPrice = RealisticMechanicalSystems.initializeVehicleConditionFromVanillaPrice

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

---
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

---Splits the console arguments on whitespace
local function parseArguments(argString, ...)
    local extraArgs = { ... }
    local hasExtraArgs = #extraArgs > 0

    if hasExtraArgs then
        local args = {}

        ---Appends a token to the argument list, split on whitespace
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

---Splits a dotted path into tokens, numbers converted
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

---Converts a console value to a boolean, nil, a number or the raw string
local function parseConsoleValue(rawValue)
    if rawValue == nil then
        return nil, false
    end

    local lowerValue = string.lower(tostring(rawValue))
    if lowerValue == "true" then
        return true, true
    end
    if lowerValue == "false" then
        return false, true
    end
    if lowerValue == "nil" then
        return nil, true
    end

    local numberValue = tonumber(rawValue)
    if numberValue ~= nil then
        return numberValue, true
    end

    return rawValue, true
end

---Returns the table holding the last token of a dotted path
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

---Returns the fill unit and fill type the vehicle actually burns
local function getPrimaryFuelConsumerInfo(vehicle)
    if vehicle == nil or vehicle.spec_motorized == nil or vehicle.spec_motorized.consumers == nil then
        return nil, nil
    end

    local preferredTypes = { FillType.DIESEL, FillType.METHANE, FillType.ELECTRICCHARGE }

    ---Tells whether a fill type is one the engine burns
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

---Keeps the clogging consistent after a console write
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

---Prints a spec value, walking nested tables
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
        local childPrefix = string.format("%s[%s]", prefix, tostring(key))
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
-- @param string? rawArgs console arguments
-- @param string? rawValue value to write
function RealisticMechanicalSystems.ConsoleCommands:setSpecVar(rawArgs, rawValue)
    if not g_currentMission:getIsServer() then
        local vehicle = self:getTargetVehicle()
        if vehicle then RMS_ConsoleCommandEvent.sendToServer("setSpecVar", rawArgs, rawValue, vehicle) end
        return
    end
    local vehicle = self:getTargetVehicle()
    if not vehicle then return end

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
        print("Example: rms_setSpecVar systems.engine.condition 0.85")
        return
    end

    local spec = vehicle.spec_RealisticMechanicalSystems
    local value, valueParsed = parseConsoleValue(valueToken)
    if not valueParsed then
        print("RMS Error: Failed to parse value.")
        return
    end

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
    for _, system in pairs(spec.systems or {}) do
        if parent == system and key == "condition" then
            vehicle:updateConditionLevel()
            break
        end
    end

    local syncedCloggingState = syncConsoleCloggingState(vehicle, spec, parent, key)

    print(string.format("RMS: spec_RealisticMechanicalSystems.%s changed on '%s': %s -> %s", path, vehicle:getFullName(), tostring(oldValue), tostring(parent[key])))
    if syncedCloggingState then
        print(string.format(
            "RMS: clogging state synced on '%s' (radiator=%.2f, airFilter=%.2f).",
            vehicle:getFullName(),
            tonumber(spec.radiatorClogging) or 0,
            tonumber(spec.airFilterClogging) or 0
        ))
    end
end

---Prints a spec variable, usage rms_printSpecVar <path>
-- @param string? rawArgs console arguments
function RealisticMechanicalSystems.ConsoleCommands:printSpecVar(rawArgs)
    if not g_currentMission:getIsServer() then
        local vehicle = self:getTargetVehicle()
        if vehicle then RMS_ConsoleCommandEvent.sendToServer("printSpecVar", rawArgs, nil, vehicle) end
        return
    end

    local vehicle = self:getTargetVehicle()
    if not vehicle then return end

    local args = parseArguments(rawArgs)
    local path = args and args[1] or nil
    if path == nil then
        print("RMS Error: Usage: rms_printSpecVar <path>")
        print("Example: rms_printSpecVar systems.engine")
        return
    end

    local spec = vehicle.spec_RealisticMechanicalSystems
    local parent, key, _, err = resolvePathParent(spec, path)
    if parent == nil then
        print(string.format("RMS Error: Invalid RMS spec path '%s': %s", path, tostring(err)))
        return
    end

    if parent == spec and (key == "rawEngineTemperature" or key == "engineTemperature") then
        RMS_Thermal.getEngineTemperature(vehicle)
    end
    local value = parent[key]
    if value == nil then
        print(string.format("RMS: spec_RealisticMechanicalSystems.%s = nil", path))
        return
    end

    if type(value) == "table" then
        print(string.format("RMS: spec_RealisticMechanicalSystems.%s on '%s':", path, vehicle:getFullName()))
        printSpecValueRecursive("spec_RealisticMechanicalSystems." .. path, value, {}, 0)
    else
        print(string.format(
            "RMS: spec_RealisticMechanicalSystems.%s on '%s' = %s",
            path,
            vehicle:getFullName(),
            tostring(value)
        ))
    end
end

---Lists every breakdown id of the registry
function RealisticMechanicalSystems.ConsoleCommands:listBreakdowns()
    print("--- Available Breakdowns ---")
    
    local breakdownIds = {}
    for id, data in pairs(RMS_Breakdowns.BreakdownRegistry) do
        table.insert(breakdownIds, string.format(" - %s (%s)", id, data.part or data.system or "No name"))
    end

    if #breakdownIds > 0 then
        table.sort(breakdownIds)
        print(table.concat(breakdownIds, "\n"))
    else
        print("  No breakdowns found in the registry.")
    end
    print("----------------------------")
end

---Adds a breakdown, usage rms_addBreakdown [id] [stage]
-- @param string? rawArgs console arguments
-- @param string? rawArgTwo second console argument
function RealisticMechanicalSystems.ConsoleCommands:addBreakdown(rawArgs, rawArgTwo)
    if not g_currentMission:getIsServer() then
        local vehicle = self:getTargetVehicle()
        if vehicle then RMS_ConsoleCommandEvent.sendToServer("addBreakdown", rawArgs, rawArgTwo, vehicle) end
        return
    end
    local args = parseArguments(rawArgs, rawArgTwo)
    local vehicle = self:getTargetVehicle()
    if not vehicle then return end

    if not args or not args[1] then
        local randomId = vehicle:getRandomBreakdown()
        if randomId then
            vehicle:addBreakdown(randomId, 1)
            print(string.format("RMS: Added random breakdown '%s' to '%s'.", randomId, vehicle:getFullName()))
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
    
    -- a filter breakdown follows the filter's clogging, which is set to the stage instead
    local filter = RMS_Consumables.getFilterOfBreakdown(breakdownId)
    if filter ~= nil then
        vehicle.spec_RealisticMechanicalSystems[filter.stateKey] = RMS_Config.FIELD_CARE.FILTER_STAGE_THRESHOLDS[stage]
        RMS_Consumables.syncFilterBreakdowns(vehicle)
    else
        vehicle:addBreakdown(breakdownId, stage)
    end
    print(string.format("RMS: Added breakdown '%s' at stage %d to '%s'.", breakdownId, stage, vehicle:getFullName()))
end

---Removes a breakdown, usage rms_removeBreakdown [id]
-- @param string? rawArgs console arguments
function RealisticMechanicalSystems.ConsoleCommands:removeBreakdown(rawArgs)
    if not g_currentMission:getIsServer() then
        local vehicle = self:getTargetVehicle()
        if vehicle then RMS_ConsoleCommandEvent.sendToServer("removeBreakdown", rawArgs, nil, vehicle) end
        return
    end
    local args = parseArguments(rawArgs)
    local vehicle = self:getTargetVehicle()
    if not vehicle then return end

    -- a filter breakdown would come back from the clogging left behind, so the filter is renewed
    if args and args[1] then
        local breakdownId = string.upper(args[1])
        if RMS_Consumables.getFilterOfBreakdown(breakdownId) ~= nil then
            RMS_Consumables.renewFilters(vehicle, breakdownId)
        else
            vehicle:removeBreakdown(breakdownId)
        end
    else
        RMS_Consumables.renewFilters(vehicle)
        vehicle:removeBreakdown()
    end
end

---Changes a breakdown stage, usage rms_advanceBreakdown [id] [stage|reverse]
-- @param string? rawArgs console arguments
-- @param string? rawArgTwo target stage or reverse
function RealisticMechanicalSystems.ConsoleCommands:changeBreakdownStage(rawArgs, rawArgTwo)
    if not g_currentMission:getIsServer() then
        local vehicle = self:getTargetVehicle()
        if vehicle then RMS_ConsoleCommandEvent.sendToServer("changeBreakdownStage", rawArgs, rawArgTwo, vehicle) end
        return
    end
    local args = parseArguments(rawArgs, rawArgTwo)
    local vehicle = self:getTargetVehicle()
    if not vehicle then return end

    local spec = vehicle.spec_RealisticMechanicalSystems
    local advancedCount = 0

    ---Parses the stage argument, accepting a number or the reverse keyword
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
-- @param string? rawArgs console arguments
-- @param string? rawArgTwo second console argument
function RealisticMechanicalSystems.ConsoleCommands:setSystemCondition(rawArgs, rawArgTwo)
    if not g_currentMission:getIsServer() then
        local vehicle = self:getTargetVehicle()
        if vehicle then RMS_ConsoleCommandEvent.sendToServer("setSystemCondition", rawArgs, rawArgTwo, vehicle) end
        return
    end
    local args = parseArguments(rawArgs, rawArgTwo)
    local vehicle = self:getTargetVehicle()
    if not vehicle then return end
    
    local spec = vehicle.spec_RealisticMechanicalSystems

    local requestedSystem = args and args[1] or nil
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

    local systemData = spec.systems[systemKey]
    if type(systemData) == "table" then
        systemData.condition = value
    else
        spec.systems[systemKey] = value
    end
    print(string.format("RMS: Set condition for system '%s' on '%s' to %.2f.", tostring(systemKey), vehicle:getFullName(), value))

    vehicle:updateConditionLevel()
end

---Sets every system condition, usage rms_setCondition [0-1]
-- @param string? rawArgs console arguments
function RealisticMechanicalSystems.ConsoleCommands:setCondition(rawArgs)
    if not g_currentMission:getIsServer() then
        local vehicle = self:getTargetVehicle()
        if vehicle then RMS_ConsoleCommandEvent.sendToServer("setCondition", rawArgs, nil, vehicle) end
        return
    end

    local args = parseArguments(rawArgs)
    local vehicle = self:getTargetVehicle()
    if not vehicle then
        return
    end

    local spec = vehicle.spec_RealisticMechanicalSystems
    local targetCondition = tonumber(args and args[1] or nil)
    if targetCondition == nil or targetCondition < 0 or targetCondition > 1 then
        print("RMS Error: Invalid value. Please provide a number between 0.0 and 1.0.")
        return
    end

    local changedSystems = 0

    for _, systemData in pairs(spec.systems or {}) do
        if type(systemData) == "table" and systemData.enabled ~= false then
            systemData.condition = targetCondition
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

---Sets one system stress, usage rms_setSystemStress [system] [>=0]
-- @param string? rawArgs console arguments
-- @param string? rawArgTwo second console argument
function RealisticMechanicalSystems.ConsoleCommands:setSystemStress(rawArgs, rawArgTwo)
    if not g_currentMission:getIsServer() then
        local vehicle = self:getTargetVehicle()
        if vehicle then RMS_ConsoleCommandEvent.sendToServer("setSystemStress", rawArgs, rawArgTwo, vehicle) end
        return
    end
    local args = parseArguments(rawArgs, rawArgTwo)
    local vehicle = self:getTargetVehicle()
    if not vehicle then return end

    local spec = vehicle.spec_RealisticMechanicalSystems

    local requestedSystem = args and args[1] or nil
    if requestedSystem == nil then
        print("RMS Error: Missing system. Usage: rms_setSystemStress [system] [>=0.0]")
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
    if value == nil or value < 0 then
        print("RMS Error: Invalid value. Please provide a number >= 0.0.")
        return
    end

    local systemData = spec.systems[systemKey]
    if type(systemData) == "table" then
        systemData.stress = value
    else
        spec.systems[systemKey] = { condition = systemData or 1.0, stress = value }
    end
    print(string.format("RMS: Set stress for system '%s' on '%s' to %.4f.", tostring(systemKey), vehicle:getFullName(), value))
end

---Sets the service clocks, usage rms_setService [0-1] [clock]
-- @param string? rawArgs console arguments
-- @param string? rawArgTwo second console argument
function RealisticMechanicalSystems.ConsoleCommands:setService(rawArgs, rawArgTwo)
    if not g_currentMission:getIsServer() then
        local vehicle = self:getTargetVehicle()
        if vehicle then RMS_ConsoleCommandEvent.sendToServer("setService", rawArgs, rawArgTwo, vehicle) end
        return
    end
    local args = parseArguments(rawArgs, rawArgTwo)
    local vehicle = self:getTargetVehicle()
    if not vehicle then return end
    
    local spec = vehicle.spec_RealisticMechanicalSystems
    local value = 1.0

    if args and args[1] then
        local parsedValue = tonumber(args[1])
        if parsedValue == nil or parsedValue < 0 or parsedValue > 1 then
            print("RMS Error: Invalid value. Please provide a number between 0.0 and 1.0.")
            return
        end
        value = parsedValue
    end

    local clockKey = args and args[2]
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

---Reinitializes the vehicle from the vanilla resale price
function RealisticMechanicalSystems.ConsoleCommands:reinitializeVehicle()
    if not g_currentMission:getIsServer() then
        local vehicle = self:getTargetVehicle()
        if vehicle then RMS_ConsoleCommandEvent.sendToServer("reinitializeVehicle", nil, nil, vehicle) end
        return
    end

    local vehicle = self:getTargetVehicle()
    if not vehicle then return end

    local spec = vehicle.spec_RealisticMechanicalSystems
    if (vehicle.isUnderService ~= nil and vehicle:isUnderService()) or (tonumber(spec.maintenanceTimer) or 0) > 0 then
        print("RMS Error: Wait until the current workshop procedure is finished before reinitializing this vehicle.")
        return
    end

    local ok, targetCondition = initializeVehicleConditionFromVanillaPrice(vehicle, true)
    if not ok then
        print(string.format("RMS Error: Failed to reinitialize '%s'.", vehicle:getFullName()))
        return
    end

    print(string.format(
        "RMS: Reinitialized '%s' from vanilla resale price. Target condition: %.3f, final overall condition: %.3f.",
        vehicle:getFullName(),
        targetCondition or 0,
        vehicle.spec_RealisticMechanicalSystems.conditionLevel or 0
    ))
end

---Re-resolves fluid capacities, keeping the liters
function RealisticMechanicalSystems.ConsoleCommands:reinitializeFluidCapacities()
    if not g_currentMission:getIsServer() then
        local vehicle = self:getTargetVehicle()
        if vehicle then RMS_ConsoleCommandEvent.sendToServer("reinitializeFluidCapacities", nil, nil, vehicle) end
        return
    end

    local vehicle = self:getTargetVehicle()
    if not vehicle then return end

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

---Prints the service and workshop state variables
function RealisticMechanicalSystems.ConsoleCommands:getServiceState()
    if not g_currentMission:getIsServer() then
        local vehicle = self:getTargetVehicle()
        if vehicle then RMS_ConsoleCommandEvent.sendToServer("getServiceState", nil, nil, vehicle) end
        return
    end
    local vehicle = self:getTargetVehicle()
    if not vehicle then return end

    local spec = vehicle.spec_RealisticMechanicalSystems
    local progressPercent = 0
    if (spec.pendingProgressTotalTime or 0) > 0 then
        progressPercent = math.floor(math.max(0, math.min((spec.pendingProgressElapsedTime or 0) / spec.pendingProgressTotalTime, 1)) * 100)
    end

    local selectedForRepairCount = 0
    local activeBreakdownsCount = 0
    for _, breakdown in pairs(spec.activeBreakdowns or {}) do
        activeBreakdownsCount = activeBreakdownsCount + 1
        if breakdown ~= nil and breakdown.isSelectedForRepair then
            selectedForRepairCount = selectedForRepairCount + 1
        end
    end

    print("--- RMS Service State ---")
    print(string.format("Vehicle: %s", vehicle:getFullName()))
    print(string.format("State: current=%s planned=%s workshop=%s", tostring(spec.currentState), tostring(spec.plannedState), tostring(spec.workshopType)))
    print(string.format("Timer: maintenanceTimer=%.0fms elapsed=%.0fms total=%.0fms progress=%d%% stepIndex=%d",
        spec.maintenanceTimer or 0, spec.pendingProgressElapsedTime or 0, spec.pendingProgressTotalTime or 0, progressPercent, spec.pendingProgressStepIndex or 0))
    print(string.format("Options: optionOne=%s optionTwo=%s optionThree=%s price=%s",
        tostring(spec.serviceOptionOne), tostring(spec.serviceOptionTwo), tostring(spec.serviceOptionThree), tostring(spec.pendingServicePrice)))
    local pendingOverhaulSystemsCount = 0
    for _, _ in pairs(spec.pendingOverhaulSystemTarget or {}) do
        pendingOverhaulSystemsCount = pendingOverhaulSystemsCount + 1
    end

    print(string.format("Targets: serviceStart=%s serviceTarget=%s overhaulSystems=%d",
        RMS_Utils.serializeNumericMap(spec.pendingServiceClockStart), RMS_Utils.serializeNumericMap(spec.pendingServiceClockTarget), pendingOverhaulSystemsCount))
    print(string.format("Levels: service engine=%.4f transmission=%.4f hydraulics=%.4f coolant=%.4f condition=%.4f",
        spec.serviceLevel, spec.transmissionServiceLevel, spec.hydraulicServiceLevel, spec.coolantServiceLevel, spec.conditionLevel or 0))
    print("Service calendar: " .. RMS_Utils.serializeNumericMap(spec.serviceCalendar))
    print(string.format("Queues: selected=%d inspection=%d repair=%d", #(spec.pendingSelectedBreakdowns or {}), #(spec.pendingInspectionQueue or {}), #(spec.pendingRepairQueue or {})))
    print(string.format("Breakdowns: active=%d selectedForRepair=%d", activeBreakdownsCount, selectedForRepairCount))

    if #(spec.pendingSelectedBreakdowns or {}) > 0 then
        print("pendingSelectedBreakdowns: " .. table.concat(spec.pendingSelectedBreakdowns, ", "))
    end
    if #(spec.pendingInspectionQueue or {}) > 0 then
        print("pendingInspectionQueue: " .. table.concat(spec.pendingInspectionQueue, ", "))
    end
    if #(spec.pendingRepairQueue or {}) > 0 then
        print("pendingRepairQueue: " .. table.concat(spec.pendingRepairQueue, ", "))
    end
end

---Prints the service log, usage rms_showServiceLog [index]
-- @param string? rawArgs console arguments
function RealisticMechanicalSystems.ConsoleCommands:showServiceLog(rawArgs)
    if not g_currentMission:getIsServer() then
        local vehicle = self:getTargetVehicle()
        if vehicle then RMS_ConsoleCommandEvent.sendToServer("showServiceLog", rawArgs, nil, vehicle) end
        return
    end
    local vehicle = self:getTargetVehicle()
    if not vehicle then return end

    local spec = vehicle.spec_RealisticMechanicalSystems
    local log = spec.maintenanceLog or {}
    local args = parseArguments(rawArgs)

    if #log == 0 then
        print("RMS: Service log is empty.")
        return
    end

    ---Formats a log entry date as day, month and year
    local function formatDate(date)
        if date == nil then
            return "n/a"
        end
        return string.format("%02d/%02d/%04d", date.day or 0, date.month or 0, date.year or 0)
    end

    ---Formats a value as a comma separated list, or as itself when it is not a table
    local function formatList(value)
        if value == nil or #value == 0 then
            return "-"
        end
        return table.concat(value, ", ")
    end

    ---Prints one maintenance log entry, verbose adding its condition snapshot
    local function printLogEntry(index, entry, verbose)
        local cond = entry.conditionData or {}
        local selectedBreakdowns = cond.selectedBreakdowns or {}
        local activeBreakdownsCount = 0
        for _, _ in pairs(cond.activeBreakdowns or {}) do
            activeBreakdownsCount = activeBreakdownsCount + 1
        end

        print(string.format("[%d] id=%s type=%s date=%s price=%s visible=%s completed=%s",
            index, tostring(entry.id), tostring(entry.type), formatDate(entry.date), tostring(entry.price), tostring(entry.isVisible), tostring(entry.isCompleted ~= false)))
        print(string.format("    options: one=%s two=%s three=%s location=%s",
            tostring(entry.optionOne), tostring(entry.optionTwo), tostring(entry.optionThree), tostring(entry.location)))

        if verbose then
            print(string.format("    conditionData: year=%s opHours=%s age=%s condition=%s service=%s reliability=%s",
                tostring(cond.year), tostring(cond.operatingHours), tostring(cond.age), tostring(cond.condition), tostring(cond.service), tostring(cond.reliability)))
            local systemsCount = 0
            for _, _ in pairs(cond.systems or {}) do
                systemsCount = systemsCount + 1
            end
            print(string.format("    conditionData: batterySoc=%s systems=%d",
                tostring(cond.batterySoc), systemsCount))
            print(string.format("    conditionData: activeBreakdowns=%d selectedBreakdowns=%d", activeBreakdownsCount, #selectedBreakdowns))
            print("    selectedBreakdowns: " .. formatList(selectedBreakdowns))
        end
    end

    if args ~= nil and args[1] ~= nil then
        local index = tonumber(args[1])
        if index == nil or index ~= math.floor(index) or index < 1 or index > #log then
            print(string.format("RMS Error: Invalid integer log index '%s'. Valid range: 1..%d", tostring(args[1]), #log))
            return
        end

        print(string.format("--- RMS Service Log Entry %d/%d ---", index, #log))
        printLogEntry(index, log[index], true)
        return
    end

    print(string.format("--- RMS Service Log (%d entries) ---", #log))
    for i, entry in ipairs(log) do
        printLogEntry(i, entry, false)
    end
end

---Prints the debug information of the vehicle
-- @param string? rawArgs console arguments
function RealisticMechanicalSystems.ConsoleCommands:getDebugVehicleInfo(rawArgs)
    if not g_currentMission:getIsServer() then
        local vehicle = self:getTargetVehicle()
        if vehicle then RMS_ConsoleCommandEvent.sendToServer("getDebugVehicleInfo", rawArgs, nil, vehicle) end
        return
    end
    local args = parseArguments(rawArgs)
    local vehicle = self:getTargetVehicle()
    if not vehicle then return end
    
    local spec = vehicle.spec_RealisticMechanicalSystems
    local motor = vehicle:getMotor()

    local storeItem = g_storeManager:getItemByXMLFilename(vehicle.configFileName)
    print("--- Vehicle Debug Info ---")
    print(string.format("RawBrand: %s", g_brandManager:getBrandByIndex(vehicle:getBrand()).name))
    print(string.format("Name: %s", vehicle:getFullName()))
    print(string.format("Type/Category: %s/%s", vehicle.type.name, storeItem.categoryName))
    print(string.format("Property state: %s", vehicle.propertyState))
    local rating = spec.electricalRating
    print(string.format("%d V circuit: battery %.0f Ah, alternator %.0f A, starter %.1f kW (%.0f A), %d work lamps, base load %.0f A, calculators %s",
        12 * rating.seriesBatteries, rating.batteryCapacityAh, rating.alternatorA, rating.starterKw, rating.starterRatedA, rating.workLamps,
        rating.baseLoadA, tostring(rating.hasCalculators)))
    print(string.format("Transmission: %s, %s, %s", motor.minForwardGearRatio, motor.gearType, motor.groupType))
    print(string.format("RMS transmission type: %s", tostring(vehicle:getTransmissionType())))
    print(string.format("XML/shop transmission name: %s", tostring(RealisticMechanicalSystems.getTransmissionNameFromXML(vehicle))))

    if args and args[1] then
        print("--------------------------")

        if vehicle.type and vehicle.type.specializationNames then
            local specNamesCopy = {}
            for _, specName in ipairs(vehicle.type.specializationNames) do
                table.insert(specNamesCopy, specName)
            end
            
            table.sort(specNamesCopy)
            
            print("Attached Specializations (" .. #specNamesCopy .. " total):")
            for i, specName in ipairs(specNamesCopy) do
                print(string.format("  %d. %s", i, specName))
            end
        else
            print("No specializations found for this vehicle type.")
        end
        
        print("--------------------------")
    end
end

---Sets the dirt amount, usage rms_setDirtAmount [0.0-1.0]
-- @param string? rawArgs console arguments
function RealisticMechanicalSystems.ConsoleCommands:setDirtAmount(rawArgs)
    if not g_currentMission:getIsServer() then
        local vehicle = self:getTargetVehicle()
        if vehicle then RMS_ConsoleCommandEvent.sendToServer("setDirtAmount", rawArgs, nil, vehicle) end
        return
    end
    local vehicle = self:getTargetVehicle()
    if not vehicle then
        print("RMS Error: No target vehicle found. Please enter a vehicle.")
        return 
    end

    if vehicle.spec_washable == nil then
        print(string.format("RMS Error: Vehicle '%s' is not washable.", vehicle:getFullName()))
        return
    end

    local args = parseArguments(rawArgs)
    
    if not args or not args[1] then
        print("RMS Error: Missing argument. Usage: rms_setDirtAmount <amount>")
        print("Please provide a dirt amount between 0.0 (clean) and 1.0 (fully dirty).")
        return
    end

    local value = tonumber(args[1])
    if value == nil or value < 0 or value > 1 then
        print("RMS Error: Invalid value. Please provide a number between 0.0 and 1.0.")
        return
    end
    
    vehicle:setDirtAmount(value)
    
    print(string.format("RMS: Set Dirt amount for '%s' to %.2f.", vehicle:getFullName(), value))
end

---Sets the paint wear, usage rms_setPaintWear [0-1]
-- @param string? rawArgs console arguments
function RealisticMechanicalSystems.ConsoleCommands:setPaintWear(rawArgs)
    if not g_currentMission:getIsServer() then
        local vehicle = self:getTargetVehicle()
        if vehicle then RMS_ConsoleCommandEvent.sendToServer("setPaintWear", rawArgs, nil, vehicle) end
        return
    end
    local vehicle = self:getTargetVehicle()
    if not vehicle then return end

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
-- @param string? rawArgs console arguments
function RealisticMechanicalSystems.ConsoleCommands:setFuelLevel(rawArgs)
    if not g_currentMission:getIsServer() then
        local vehicle = self:getTargetVehicle()
        if vehicle then RMS_ConsoleCommandEvent.sendToServer("setFuelLevel", rawArgs, nil, vehicle) end
        return
    end
    local vehicle = self:getTargetVehicle()
    if not vehicle then
        return
    end

    local args = parseArguments(rawArgs)
    if not args or not args[1] then
        print("RMS Error: Usage: rms_setFuelLevel <value>")
        print("Value: 0..1 is a fraction; above 1..100 is a percentage (use 0.01 for 1%).")
        print("Example: rms_setFuelLevel 0.25")
        print("Example: rms_setFuelLevel 25")
        return
    end

    local inputValue = tonumber(args[1])
    if inputValue == nil then
        print("RMS Error: Invalid value. Expected number.")
        return
    end

    if inputValue > 1 then
        if inputValue <= 100 then
            inputValue = inputValue / 100
        else
            print("RMS Error: Value must be 0.0..1.0 or 0..100.")
            return
        end
    end

    if inputValue < 0 or inputValue > 1 then
        print("RMS Error: Value must be between 0.0 and 1.0 (or 0..100%).")
        return
    end

    local fillUnitIndex, fillType = getPrimaryFuelConsumerInfo(vehicle)
    if fillUnitIndex == nil or fillType == nil then
        print(string.format("RMS Error: Fuel consumer not found for '%s'.", vehicle:getFullName()))
        return
    end

    local capacity = tonumber(vehicle:getFillUnitCapacity(fillUnitIndex)) or 0
    if capacity <= 0 then
        print(string.format("RMS Error: Invalid fuel capacity for '%s' (fillUnit %s).", vehicle:getFullName(), tostring(fillUnitIndex)))
        return
    end

    local currentLevel = tonumber(vehicle:getFillUnitFillLevel(fillUnitIndex)) or 0
    local targetLevel = math.clamp(capacity * inputValue, 0, capacity)
    local delta = targetLevel - currentLevel

    if math.abs(delta) > 0.0001 then
        vehicle:addFillUnitFillLevel(vehicle:getOwnerFarmId(), fillUnitIndex, delta, fillType, ToolType.UNDEFINED)
    end

    local resultLevel = tonumber(vehicle:getFillUnitFillLevel(fillUnitIndex)) or targetLevel
    local resultRatio = resultLevel / math.max(capacity, 0.0001)
    print(string.format(
        "RMS: Energy fill level set on '%s' -> %.1f / %.1f (%.1f%%), fillType=%s, fillUnit=%s",
        vehicle:getFullName(),
        resultLevel,
        capacity,
        resultRatio * 100,
        tostring(fillType),
        tostring(fillUnitIndex)
    ))
end

---Clears the accumulated wear factor statistics of the vehicle
function RealisticMechanicalSystems.ConsoleCommands:resetFactorStats()
    if not g_currentMission:getIsServer() then
        local vehicle = self:getTargetVehicle()
        if vehicle then RMS_ConsoleCommandEvent.sendToServer("resetFactorStats", nil, nil, vehicle) end
        return
    end
    local vehicle = self:getTargetVehicle()
    if not vehicle then
        return
    end

    local spec = vehicle.spec_RealisticMechanicalSystems
    local factorStats = ensureFactorStats(spec, vehicle)

    for _, systemStats in pairs(factorStats) do
        if type(systemStats) == "table" then
            for key, value in pairs(systemStats) do
                if key ~= "operatingHours" and tonumber(value) ~= nil then
                    systemStats[key] = 0
                end
            end
            systemStats.total = 0
            systemStats.stress = 0
            systemStats.operatingHours = getVehicleOperatingHours(vehicle)
        end
    end

    print(string.format("RMS: Factor stats reset for '%s'.", vehicle:getFullName()))
end

---Switches the debug HUD view, usage rms_toggleHudDebugView [view]
-- @param string? rawArgs console arguments
function RealisticMechanicalSystems.ConsoleCommands:toggleHudDebugView(rawArgs)
    local args = parseArguments(rawArgs)
    local requestedMode = args and args[1] and string.lower(tostring(args[1])) or nil
    local currentMode = tostring(RMS_Hud.debugViewMode or "default")
    local nextMode = "default"

    if requestedMode == nil or requestedMode == "" or requestedMode == "toggle" then
        if currentMode == "factorStats" then
            nextMode = "default"
        else
            nextMode = "factorStats"
        end
    elseif requestedMode == "default" or requestedMode == "normal" then
        nextMode = "default"
    elseif requestedMode == "stats" or requestedMode == "stat" or requestedMode == "factorstats" or requestedMode == "factor_stats" then
        nextMode = "factorStats"
    else
        print("RMS Error: Usage: rms_toggleHudDebugView [default|stats|toggle]")
        return
    end

    RMS_Hud.debugViewMode = nextMode

    print(string.format("RMS: HUD debug view mode = %s", nextMode))
end

---Forces the exhaust smoke this computer draws on every vehicle
-- @param string? rawArgs "off", or an opacity, a gas flow and a vapour depth, a dash keeping the engine value
-- @param any ... further console arguments
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

-- parsing helpers shared with the development console tools
RealisticMechanicalSystems.ConsoleCommands.parseArguments = parseArguments
RealisticMechanicalSystems.ConsoleCommands.resolvePathParent = resolvePathParent

addConsoleCommand("rms_listBreakdowns", "Lists all available breakdown IDs.", "listBreakdowns", RealisticMechanicalSystems.ConsoleCommands)
addConsoleCommand("rms_addBreakdown", "Adds a breakdown. Usage: rms_addBreakdown [id] [stage]", "addBreakdown", RealisticMechanicalSystems.ConsoleCommands)
addConsoleCommand("rms_removeBreakdown", "Removes a breakdown. Usage: rms_removeBreakdown [id]", "removeBreakdown", RealisticMechanicalSystems.ConsoleCommands)
addConsoleCommand("rms_advanceBreakdown", "Changes breakdown stages. Usage: rms_advanceBreakdown [id] [stage|reverse]", "changeBreakdownStage", RealisticMechanicalSystems.ConsoleCommands)
addConsoleCommand("rms_setCondition", "Sets condition for all enabled systems. Usage: rms_setCondition [0.0-1.0]", "setCondition", RealisticMechanicalSystems.ConsoleCommands)
addConsoleCommand("rms_setSystemCondition", "Sets system condition. Usage: rms_setSystemCondition [system] [0.0-1.0]", "setSystemCondition", RealisticMechanicalSystems.ConsoleCommands)
addConsoleCommand("rms_setSystemStress", "Sets system stress. Usage: rms_setSystemStress [system] [>=0.0]", "setSystemStress", RealisticMechanicalSystems.ConsoleCommands)
addConsoleCommand("rms_setService", "Sets vehicle service clocks. Usage: rms_setService [0.0-1.0] [engine|transmission|hydraulic|coolant]",
    "setService", RealisticMechanicalSystems.ConsoleCommands)
addConsoleCommand("rms_reinitializeVehicle", "Reinitializes vehicle from vanilla resale price logic; unavailable during workshop service.",
    "reinitializeVehicle", RealisticMechanicalSystems.ConsoleCommands)
addConsoleCommand("rms_reinitializeFluidCapacities", "Re-resolves physical fluid capacities while preserving liters.", "reinitializeFluidCapacities", RealisticMechanicalSystems.ConsoleCommands)
addConsoleCommand("rms_getServiceState", "Prints current service/workshop state variables.", "getServiceState", RealisticMechanicalSystems.ConsoleCommands)
addConsoleCommand("rms_showServiceLog", "Shows service log. Usage: rms_showServiceLog [integer index]", "showServiceLog", RealisticMechanicalSystems.ConsoleCommands)
addConsoleCommand("rms_getDebugVehicleInfo", "Prints how RMS reads the vehicle. Usage: rms_getDebugVehicleInfo [1 to list its specializations]",
    "getDebugVehicleInfo", RealisticMechanicalSystems.ConsoleCommands)
addConsoleCommand("rms_setDirtAmount", "Sets vehicle dirt amount. Usage: rms_setDirtAmount [0.0-1.0]", "setDirtAmount", RealisticMechanicalSystems.ConsoleCommands)
addConsoleCommand("rms_setPaintWear", "Sets vehicle paint wear. Usage: rms_setPaintWear [0.0-1.0]", "setPaintWear", RealisticMechanicalSystems.ConsoleCommands)
addConsoleCommand("rms_setFuelLevel", "Sets fuel or traction charge. Usage: rms_setFuelLevel [fraction 0..1 or percentage >1..100]", "setFuelLevel", RealisticMechanicalSystems.ConsoleCommands)
addConsoleCommand("rms_resetFactorStats", "Resets accumulated factor stats for current vehicle.", "resetFactorStats", RealisticMechanicalSystems.ConsoleCommands)
addConsoleCommand("rms_toggleHudDebugView", "Switch debug HUD view. Usage: rms_toggleHudDebugView [default|stats|toggle]", "toggleHudDebugView", RealisticMechanicalSystems.ConsoleCommands)
addConsoleCommand("rms_setSpecVar", "Sets physical RMS vehicle state, including raw oil temperatures. Usage: rms_setSpecVar <path> <value>", "setSpecVar", RealisticMechanicalSystems.ConsoleCommands)
addConsoleCommand("rms_printSpecVar", "Prints RMS specialization variable on current vehicle. Usage: rms_printSpecVar <path>", "printSpecVar", RealisticMechanicalSystems.ConsoleCommands)
addConsoleCommand("rms_exhaustOverride",
    "Forces the exhaust smoke this computer draws on every vehicle. Usage: rms_exhaustOverride <opacity 0-1|-> [flow 0-1|-] [vapour >=0|-] | off",
    "exhaustOverride", RealisticMechanicalSystems.ConsoleCommands)
