-- Copyright © 2026 Squallqt. All rights reserved.

---Console commands of the mod, acting on the vehicle the player sits in

RealisticMechanicalSystems.ConsoleCommands = {}

local consolePrint = print

---Prints locally, or sends a server command's output to its requester
-- @param any ... values printed
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

---Prints through printOutput, to the requester of a server command
-- @param any ... values printed
local function print(...)
    RealisticMechanicalSystems.ConsoleCommands:printOutput(...)
end

---Returns the vehicle the commands act on
-- @return table? vehicle target vehicle, nil when none qualifies
function RealisticMechanicalSystems.ConsoleCommands:getTargetVehicle()
    if RealisticMechanicalSystems.ConsoleCommands._overrideVehicle ~= nil then
        return RealisticMechanicalSystems.ConsoleCommands._overrideVehicle
    end
    local vehicle = g_localPlayer ~= nil and g_localPlayer:getCurrentVehicle() or nil
    if not vehicle or not vehicle.spec_RealisticMechanicalSystems then
        print("RMS Error: You must be in a vehicle with RealisticMechanicalSystems support.")
        return nil
    end
    return vehicle
end

---Returns the target vehicle on the server, a client sending the command there instead
-- @param string command command
-- @param string? argOne first argument
-- @param string? argTwo second argument
-- @return table? vehicle nil on a client or without a target
function RealisticMechanicalSystems.ConsoleCommands:getServerVehicle(command, argOne, argTwo)
    local vehicle = self:getTargetVehicle()
    if vehicle ~= nil and not g_currentMission:getIsServer() then
        RMS_ConsoleCommandEvent.sendToServer(command, argOne, argTwo, vehicle)
        return nil
    end
    return vehicle
end

---Returns the words of the console arguments
-- @param string? argString first argument, or every word in one text
-- @param any ... further arguments
-- @return table args words
local function parseArguments(argString, ...)
    local extraArgs = { ... }
    local hasExtraArgs = #extraArgs > 0

    if hasExtraArgs then
        local args = {}

        ---Adds a word to the arguments
        -- @param string? token word
        local function appendToken(token)
            if token == nil then
                return
            end
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

    if argString == nil or argString == '' then
        return {}
    end

    local args = {}
    for arg in string.gmatch(argString, "[^%s]+") do
        table.insert(args, arg)
    end
    return args
end

---Lists every breakdown id of the registry
function RealisticMechanicalSystems.ConsoleCommands:listBreakdowns()
    local lines = {}
    for id, data in pairs(RMS_Breakdowns.BreakdownRegistry) do
        local ways = data.branches ~= nil and string.format(", fails in %d ways", data.branches) or ""
        table.insert(lines, string.format(" - %s (%s)%s", id, data.part, ways))
    end
    table.sort(lines)

    print("--- Available Breakdowns ---")
    print(table.concat(lines, "\n"))
    print("----------------------------")
end

---Adds a breakdown, usage rms_addBreakdown [id] [stage] [way]
-- @param string? rawArgs breakdown
-- @param string? rawArgTwo stage
-- @param string? rawArgThree way
function RealisticMechanicalSystems.ConsoleCommands:addBreakdown(rawArgs, rawArgTwo, rawArgThree)
    local stageAndWay = rawArgThree ~= nil and string.format("%s %s", tostring(rawArgTwo), rawArgThree) or rawArgTwo
    local vehicle = self:getServerVehicle("addBreakdown", rawArgs, stageAndWay)
    if vehicle == nil then
        return
    end
    local args = parseArguments(rawArgs, rawArgTwo, rawArgThree)

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

    if not registryEntry.isApplicable(vehicle) then
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
-- @param string? rawArgs breakdown
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

    id = string.upper(id)
    if RMS_Consumables.getFilterOfBreakdown(id) == nil then
        vehicle:removeBreakdown(id)
    else
        RMS_Consumables.renewFilters(vehicle, id)
    end
end

---Changes a breakdown stage, usage rms_advanceBreakdown [id] [stage|reverse]
-- @param string? rawArgs breakdown
-- @param string? rawArgTwo stage or "reverse"
function RealisticMechanicalSystems.ConsoleCommands:changeBreakdownStage(rawArgs, rawArgTwo)
    local vehicle = self:getServerVehicle("changeBreakdownStage", rawArgs, rawArgTwo)
    if vehicle == nil then
        return
    end
    local args = parseArguments(rawArgs, rawArgTwo)

    local spec = vehicle.spec_RealisticMechanicalSystems
    local advancedCount = 0

    ---Reads a stage, or true for reverse
    -- @param string? rawValue stage or "reverse"
    -- @return integer|boolean|nil stage stage, true for reverse, nil when unreadable
    local function parseStageArg(rawValue)
        if rawValue == nil then
            return nil
        end

        local lowered = string.lower(rawValue)
        if lowered == "true" or lowered == "reverse" or lowered == "down" or lowered == "prev" then
            return true
        end

        local numeric = tonumber(rawValue)
        if numeric ~= nil and numeric >= 1 and numeric == math.floor(numeric) then
            return numeric
        end

        return nil
    end

    if args[1] == nil then
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
            or (type(targetStage) == "number" and targetStage > #registryEntry.stages)) then
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

---Sets every system condition, usage rms_setCondition [0-1]
-- @param string? rawArgs condition
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
        if systemData.enabled then
            for _, partId in ipairs(spec.systemParts[systemKey]) do
                spec.partWear[partId] = 1 - targetCondition
                spec.partAbuse[partId] = nil
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
        changedSystems, vehicle:getFullName(), targetCondition, spec.conditionLevel))
end

---Sets the wear of a part, usage rms_setPartWear [id] [wear]
-- @param string? rawArgs part
-- @param string? rawArgTwo wear
function RealisticMechanicalSystems.ConsoleCommands:setPartWear(rawArgs, rawArgTwo)
    local vehicle = self:getServerVehicle("setPartWear", rawArgs, rawArgTwo)
    if vehicle == nil then
        return
    end
    local args = parseArguments(rawArgs, rawArgTwo)

    local spec = vehicle.spec_RealisticMechanicalSystems
    local partId = args[1] and string.upper(args[1])
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
    spec.partAbuse[partId] = nil
    spec.partDrawnWear[partId] = nil
    RealisticMechanicalSystems.refreshSystemCondition(spec, systemKey)
    vehicle:updateConditionLevel()
    print(string.format("RMS: Set wear of part '%s' on '%s' to %.2f, risk x%.2f that of a new part.", partId, vehicle:getFullName(),
        value, RMS_Utils.getPartRiskRatio(partId, value)))
end

---Sets the service clocks, usage rms_setService [0-1] [clock]
-- @param string? rawArgs level
-- @param string? rawArgTwo clock
function RealisticMechanicalSystems.ConsoleCommands:setService(rawArgs, rawArgTwo)
    local vehicle = self:getServerVehicle("setService", rawArgs, rawArgTwo)
    if vehicle == nil then
        return
    end
    local args = parseArguments(rawArgs, rawArgTwo)
    local spec = vehicle.spec_RealisticMechanicalSystems
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

---Sets the greasing left of a machine and its implements
-- @param string? rawArgs share of the intervals left
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

addConsoleCommand("rms_listBreakdowns", "Lists all available breakdown IDs.", "listBreakdowns", RealisticMechanicalSystems.ConsoleCommands)
addConsoleCommand("rms_addBreakdown", "Adds a breakdown. Usage: rms_addBreakdown [id] [stage] [way]", "addBreakdown", RealisticMechanicalSystems.ConsoleCommands)
addConsoleCommand("rms_removeBreakdown", "Removes a breakdown. Usage: rms_removeBreakdown [id]", "removeBreakdown", RealisticMechanicalSystems.ConsoleCommands)
addConsoleCommand("rms_advanceBreakdown", "Changes breakdown stages. Usage: rms_advanceBreakdown [id] [stage|reverse]", "changeBreakdownStage", RealisticMechanicalSystems.ConsoleCommands)
addConsoleCommand("rms_setCondition", "Sets condition for all enabled systems. Usage: rms_setCondition [0.0-1.0]", "setCondition", RealisticMechanicalSystems.ConsoleCommands)
addConsoleCommand("rms_setPartWear", "Sets the wear of one part, 1.0 being the life of the machine. Usage: rms_setPartWear [breakdown id] [wear]", "setPartWear",
    RealisticMechanicalSystems.ConsoleCommands)
addConsoleCommand("rms_setService", "Sets vehicle service clocks. Usage: rms_setService [0.0-1.0] [engine|transmission|hydraulic|coolant]",
    "setService", RealisticMechanicalSystems.ConsoleCommands)
addConsoleCommand("rms_setGreasing", "Sets the greasing interval left of the vehicle and its implements, 0 making every grease point due. Usage: rms_setGreasing [0.0-1.0]", "setGreasing",
    RealisticMechanicalSystems.ConsoleCommands)
