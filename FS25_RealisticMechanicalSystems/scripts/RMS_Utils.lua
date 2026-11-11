-- Copyright © 2026 Squallqt. All rights reserved.

---Shared RMS utilities.
RMS_Utils = {}
---1 for a set flag, 0 for an unset one
local function toFlag(value)
    return value and 1 or 0
end

---Whole, non negative count read from a number or a string
local function toCount(value)
    return math.max(math.floor(tonumber(value) or 0), 0)
end

---Fields of a saved breakdown: eight always, five added since
local BREAKDOWN_ENTRY_PATTERN = string.rep("([^,]+),", 7) .. "([^,]+)" .. string.rep(",?([^,]*)", 5)

---Unit text of a count, singular for one
local function getCountUnit(count, singular, plural)
    return g_i18n:getText(count == 1 and singular or plural)
end

---Formats a ratio as a whole percentage
local function formatPercent(ratio)
    return string.format("%.0f%%", ratio * 100)
end

---Tier of a value against descending levels, 1 at or above the first
local function getLevelTier(levels, value)
    for tier, level in ipairs(levels) do
        if value >= level then
            return tier
        end
    end
    return #levels + 1
end

---Sorted entries of a save field, joined by semicolons
local function joinSaveEntries(entries)
    table.sort(entries)
    return table.concat(entries, ";")
end

---Entries of a save field, comma separated in older saves
local function splitSaveEntries(serialized)
    local entries = {}
    if serialized == nil or serialized == "" then
        return entries
    end
    local separator = string.find(serialized, ";", 1, true) ~= nil and ";" or ","
    for entry in string.gmatch(serialized, "[^" .. separator .. "]+") do
        table.insert(entries, entry)
    end
    return entries
end

---Condition and switch of a system, a bare number counting as on
local function readSystemState(systemData)
    if type(systemData) == "table" then
        return tonumber(systemData.condition) or 1.0, RMS_Utils.normalizeBoolValue(systemData.enabled, true)
    end
    return tonumber(systemData) or 1.0, true
end

---Tells whether a system counts, a bare value counting as on
local function getIsSystemOn(systemData)
    return type(systemData) ~= "table" or systemData.enabled ~= false
end

---Weight the configuration gives a system, its key matched in any case
local function getConfiguredSystemWeight(systemKey)
    local weights = RMS_Config.CORE.SYSTEM_WEIGHTS
    local weight = tonumber(weights[systemKey])
    if weight == nil then
        local wanted = string.lower(tostring(systemKey))
        for key, value in pairs(weights) do
            if string.lower(tostring(key)) == wanted then
                weight = tonumber(value) or 0
                break
            end
        end
    end
    return math.max(weight or 0, 0)
end

---Key of the vehicle's systems behind a system name or enum key
local function resolveVehicleSystemKey(vehicleSystems, name, systems)
    if vehicleSystems[name] ~= nil then
        return name
    end
    local lowered = string.lower(name)
    if type(systems) == "table" then
        if type(systems[string.upper(name)]) == "string" and vehicleSystems[lowered] ~= nil then
            return lowered
        end
        local enumKey = RMS_Utils.getKeyByValue(systems, name)
        if type(enumKey) == "string" and vehicleSystems[string.lower(enumKey)] ~= nil then
            return string.lower(enumKey)
        end
    end
    for key in pairs(vehicleSystems) do
        if string.lower(tostring(key)) == lowered then
            return key
        end
    end
    return lowered
end

---Words a save or the console may hold for a boolean
local BOOL_WORDS = {
    ["true"] = true, ["1"] = true, on = true, yes = true,
    ["false"] = false, ["0"] = false, off = false, no = false
}

---Log field of the entry itself, saved as text
local function entryText(key, default)
    return {
        write = function(entry) return tostring(entry[key] or default) end,
        read = function(entry, _, raw) entry[key] = raw ~= "" and raw or default end
    }
end

---Log field of the entry itself, saved as a number
local function entryNumber(key, default)
    return {
        write = function(entry) return tostring(entry[key] or default) end,
        read = function(entry, _, raw) entry[key] = tonumber(raw) or default end
    }
end

---Log field of the entry itself, saved as a boolean
local function entryFlag(key, default)
    return {
        write = function(entry) return tostring(RMS_Utils.normalizeBoolValue(entry[key], default)) end,
        read = function(entry, _, raw) entry[key] = RMS_Utils.normalizeBoolValue(raw, default) end
    }
end

---Log field of the condition data, saved as a number
-- @param float? default value when missing, none keeps it empty
local function conditionNumber(key, default)
    return {
        write = function(_, data) return tostring(data[key] or default or "") end,
        read = function(_, data, raw) data[key] = tonumber(raw) or default end
    }
end

---Log field of the condition data, saved as escaped text
local function conditionEncoded(key, serialize, deserialize)
    return {
        write = function(_, data) return RMS_Utils.encodeDelimitedString(serialize(data[key])) end,
        read = function(_, data, raw) data[key] = deserialize(RMS_Utils.decodeDelimitedString(raw or "")) end
    }
end

---Fields of a maintenance log entry, in their saved order
local LOG_ENTRY_FIELDS = {
    entryNumber("id", 0),
    {
        write = function(entry) return tostring(entry.type or "") end,
        read = function(entry, _, raw) entry.type = raw ~= "" and raw or nil end
    },
    entryNumber("price", 0),
    {
        write = function(entry) return RMS_Utils.serializeDate(entry.date) end,
        read = function(entry, _, raw) entry.date = RMS_Utils.deserializeDate(raw) end
    },
    entryText("location", "UNKNOWN"),
    entryText("optionOne", "NONE"),
    entryText("optionTwo", "NONE"),
    entryFlag("isVisible", true),
    entryFlag("isCompleted", true),
    conditionNumber("year", 0),
    conditionNumber("operatingHours", 0),
    conditionNumber("age", 0),
    conditionNumber("condition", 1),
    conditionNumber("service", 1),
    conditionNumber("reliability", 1),
    -- Kept empty, older saves wrote here
    { write = function() return "" end },
    conditionEncoded("systems",
        function(systems) return RMS_Utils.serializeSystemsState(RMS_Utils.createSystemsSnapshot(systems)) end,
        function(text) return RMS_Utils.createSystemsSnapshot(RMS_Utils.deserializeSystemsState(text)) end),
    conditionNumber("batterySoc", 1),
    conditionEncoded("activeEffects",
        function(effects) return RMS_Utils.serializeEffectSnapshot(effects) end,
        function(text) return RMS_Utils.deserializeEffectSnapshot(text) end),
    conditionEncoded("activeBreakdowns",
        function(breakdowns) return RMS_Utils.serializeBreakdowns(breakdowns or {}) end,
        function(text) return RMS_Utils.deserializeBreakdowns(text) end),
    conditionEncoded("selectedBreakdowns",
        function(ids) return table.concat(ids or {}, ",") end,
        function(text) return RMS_Utils.parseCsvList(text) end),
    conditionEncoded("activeIndicators",
        function(indicators)
            local ids = {}
            for id, isActive in pairs(indicators or {}) do
                if isActive then
                    table.insert(ids, tostring(id))
                end
            end
            table.sort(ids)
            return table.concat(ids, ",")
        end,
        function(text)
            local indicators = {}
            for _, id in ipairs(RMS_Utils.parseCsvList(text)) do
                indicators[id] = true
            end
            return indicators
        end),
    {
        write = function(entry) return RMS_Utils.encodeDelimitedString(RMS_Utils.serializeInvoice(entry.invoice)) end,
        read = function(entry, _, raw) entry.invoice = RMS_Utils.deserializeInvoice(RMS_Utils.decodeDelimitedString(raw or "")) end
    },
    conditionNumber("odometerKilometers"),
    conditionNumber("wearExcess"),
    conditionEncoded("wearCauses",
        function(causes) return RMS_Utils.serializeWearCauses(causes) end,
        function(text) return RMS_Utils.deserializeWearCauses(text) end),
    conditionEncoded("partWear",
        function(wear) return RMS_Utils.serializeNumericMap(wear) end,
        function(text) return RMS_Utils.deserializeNumericMap(text) end)
}


---Returns the container locked on a hook lift
function RMS_Utils.getLockedHookLiftContainer(vehicle)
    local hookLift = vehicle ~= nil and vehicle.spec_hookLiftTrailer or nil
    local attachedContainer = hookLift ~= nil and hookLift.attachedContainer or nil
    local container = attachedContainer ~= nil and attachedContainer.object or nil

    if hookLift == nil or hookLift.containerLockState ~= true or container == nil or container.spec_hookLiftContainer == nil then
        return nil
    end

    return container
end

---Converts a mean time between events into a per frame probability
function RMS_Utils.getChancePerFrameFromMeanTime(dt, meanTimeInMinutes)
    -- No mean time: the event is certain
    if meanTimeInMinutes <= 0 then
        return 1.0
    end
    return dt / (meanTimeInMinutes * 60000)
end

---Tells whether the vehicle drives a PTO output
function RMS_Utils.hasPtoOutputCapability(vehicle)
    local ptoSpec = vehicle ~= nil and vehicle.spec_powerTakeOffs or nil
    if ptoSpec == nil or type(ptoSpec.outputPowerTakeOffs) ~= "table" then
        return false
    end

    return next(ptoSpec.outputPowerTakeOffs) ~= nil
end

---Tells whether an attacher joint lifts hydraulically
function RMS_Utils.getIsHydraulicLiftJoint(jointDesc)
    if type(jointDesc) ~= "table" then
        return false
    end

    local jointType = jointDesc.jointType
    local isTrailerJoint = jointType == AttacherJoints.JOINTTYPE_TRAILER
        or jointType == AttacherJoints.JOINTTYPE_TRAILERLOW
        or jointType == AttacherJoints.JOINTTYPE_TRAILERCAR
    return jointDesc.allowsLowering == true and not isTrailerJoint
end

---Tells whether the vehicle can lift an implement hydraulically
function RMS_Utils.hasHydraulicLiftCapability(vehicle)
    local attacherJointsSpec = vehicle ~= nil and vehicle.spec_attacherJoints or nil
    if attacherJointsSpec ~= nil then
        for _, jointDesc in pairs(attacherJointsSpec.attacherJoints) do
            if RMS_Utils.getIsHydraulicLiftJoint(jointDesc) then
                return true
            end
        end
    end

    return false
end

---Tells whether the vehicle carries a hydraulic actuator
function RMS_Utils.hasHydraulicActuatorCapability(vehicle)
    if vehicle == nil then
        return false
    end

    if RMS_Utils.hasHydraulicLiftCapability(vehicle) then
        return true
    end

    local cylinderedSpec = vehicle.spec_cylindered
    if cylinderedSpec ~= nil and type(cylinderedSpec.movingTools) == "table" then
        for _, tool in pairs(cylinderedSpec.movingTools) do
            if RMS_Utils.getIsHydraulicMovingTool(tool) then
                return true
            end
        end
    end
    if cylinderedSpec ~= nil and type(cylinderedSpec.movingParts) == "table" then
        for _, part in pairs(cylinderedSpec.movingParts) do
            if RMS_Utils.getIsHydraulicMovingTool(part) then
                return true
            end
        end
    end

    return vehicle.spec_attacherJointControl ~= nil
        or vehicle.spec_hydraulicHammer ~= nil
        or vehicle.spec_hookLiftTrailer ~= nil
end

local function getIsHydraulicConnectionEntry(entry)
    return type(entry) == "table"
        and type(entry.type) == "string"
        and string.sub(string.upper(entry.type), 1, 9) == "HYDRAULIC"
end

---Tells whether a moving tool is driven hydraulically
function RMS_Utils.getIsHydraulicMovingTool(tool)
    return type(tool) == "table" and tool.playSound == true
end

---Tells whether the vehicle or an attached implement carries hydraulic hoses
function RMS_Utils.hasHydraulicHoseCapability(vehicle, visited)
    visited = visited or {}
    if vehicle == nil or visited[vehicle] then
        return false
    end
    visited[vehicle] = true

    local connectionHosesSpec = vehicle.spec_connectionHoses
    if connectionHosesSpec ~= nil then
        for _, entry in ipairs(connectionHosesSpec.hoseNodes or {}) do
            if getIsHydraulicConnectionEntry(entry) then
                return true
            end
        end

        for _, entry in ipairs(connectionHosesSpec.targetNodes or {}) do
            if getIsHydraulicConnectionEntry(entry) then
                return true
            end
        end

        for _, localHose in ipairs(connectionHosesSpec.localHoseNodes or {}) do
            if getIsHydraulicConnectionEntry(localHose.hose)
                or getIsHydraulicConnectionEntry(localHose.target) then
                return true
            end
        end

        for _, entry in ipairs(connectionHosesSpec.customHoses or {}) do
            if getIsHydraulicConnectionEntry(entry) then
                return true
            end
        end

        for _, entry in ipairs(connectionHosesSpec.customHoseTargets or {}) do
            if getIsHydraulicConnectionEntry(entry) then
                return true
            end
        end
    end

    local children = vehicle.getChildVehicles ~= nil and vehicle:getChildVehicles() or {}
    for _, childVehicle in pairs(children) do
        if RMS_Utils.hasHydraulicHoseCapability(childVehicle, visited) then
            return true
        end
    end

    return false
end

---Tells whether the vehicle has a hydraulic circuit at all
function RMS_Utils.hasHydraulicCapability(vehicle)
    local visited = {}

    local function hasCapability(vehicleObj)
        if vehicleObj == nil or visited[vehicleObj] then
            return false
        end
        visited[vehicleObj] = true

        if RMS_Utils.hasHydraulicActuatorCapability(vehicleObj) then
            return true
        end

        local children = vehicleObj.getChildVehicles ~= nil and vehicleObj:getChildVehicles() or {}
        for _, childVehicle in pairs(children) do
            if hasCapability(childVehicle) then
                return true
            end
        end

        return false
    end

    return hasCapability(vehicle) or RMS_Utils.hasHydraulicHoseCapability(vehicle)
end

---Tells whether the player can drive a hydraulic function of the vehicle
function RMS_Utils.hasHydraulicControllableTargetCapability(vehicle)
    local visited = {}

    local function hasTarget(vehicleObj)
        if vehicleObj == nil or visited[vehicleObj] then
            return false
        end
        visited[vehicleObj] = true

        if RMS_Utils.hasHydraulicLiftCapability(vehicleObj) then
            return true
        end

        local cylinderedSpec = vehicleObj.spec_cylindered
        if cylinderedSpec ~= nil then
            for _, tool in pairs(cylinderedSpec.movingTools or {}) do
                if RMS_Utils.getIsHydraulicMovingTool(tool)
                    and (tool.rotSpeed ~= nil or tool.transSpeed ~= nil or tool.animSpeed ~= nil) then
                    return true
                end
            end
        end

        local children = vehicleObj.getChildVehicles ~= nil and vehicleObj:getChildVehicles() or {}
        for _, childVehicle in pairs(children) do
            if hasTarget(childVehicle) then
                return true
            end
        end

        return false
    end

    return hasTarget(vehicle)
end

---Compares the PTO torque with the capacity the engine natively offers
function RMS_Utils.getPtoNativeCapacityData(vehicle, totalTorque)
    local motor = vehicle ~= nil and vehicle.getMotor ~= nil and vehicle:getMotor() or nil
    local ptoMotorRpmRatio = motor ~= nil and motor.getPtoMotorRpmRatio ~= nil
        and (tonumber(motor:getPtoMotorRpmRatio()) or 0) or 0
    local peakTorque = motor ~= nil and motor.getPeakTorque ~= nil
        and (tonumber(motor:getPeakTorque()) or 0) or 0
    local motorSideTorque = ptoMotorRpmRatio > 0 and math.max(tonumber(totalTorque) or 0, 0) / ptoMotorRpmRatio or 0
    local nativeCapacityTorque = math.max(peakTorque * 0.9, 0)
    local utilization = nativeCapacityTorque > 0 and motorSideTorque / nativeCapacityTorque or 0

    return utilization, motorSideTorque, nativeCapacityTorque
end

---Returns the wear factor of a PTO utilization
function RMS_Utils.calculatePtoLoadFactor(utilization, config)
    local load = math.max(tonumber(utilization) or 0, 0)
    local threshold = tonumber(config.LOAD_FACTOR_THRESHOLD) or 0
    if load <= threshold then
        return 0
    end

    local multiplier = math.max(tonumber(config.LOAD_FACTOR_MULTIPLIER) or 0, 0)
    local fullEffect = math.max(tonumber(config.LOAD_FACTOR_FULL_EFFECT) or 1, threshold + 0.0001)
    local factor = RMS_Utils.calculateQuadraticMultiplier(load, threshold, false, fullEffect) * multiplier
    factor = math.min(factor, multiplier)

    if load > fullEffect then
        local overloadMultiplier = math.max(tonumber(config.OVERLOAD_FACTOR_MULTIPLIER) or 0, 0)
        local overloadFullEffect = math.max(tonumber(config.OVERLOAD_FACTOR_FULL_EFFECT) or 1, fullEffect + 0.0001)
        factor = factor + math.min((load - fullEffect) / (overloadFullEffect - fullEffect), 1) * overloadMultiplier
    end

    return factor
end

---Returns the engine speed as a share of its range from idle to maximum
-- @return float share 0 at idle or with the engine off, 1 at maximum rpm
function RMS_Utils.getMotorRpmShareAboveIdle(vehicle)
    local motor = vehicle ~= nil and vehicle.getMotor ~= nil and vehicle:getMotor() or nil
    if motor == nil or vehicle.getIsMotorStarted == nil or not vehicle:getIsMotorStarted() then
        return 0
    end

    local minRpm = tonumber(motor.minRpm) or 0
    local maxRpm = tonumber(motor.maxRpm) or 0
    if maxRpm <= minRpm then
        return 0
    end

    return math.clamp(((tonumber(motor:getLastModulatedMotorRpm()) or 0) - minRpm) / (maxRpm - minRpm), 0, 1)
end

---Returns the condition new PTO engagements take
function RMS_Utils.getPtoEngagementDamage(vehicle, engagementTorques, previousActiveLinks, rpmShare)
    local config = RMS_Config.CORE.PTO_FACTOR_DATA
    local rpmFactor = RMS_Utils.calculateQuadraticMultiplier(math.clamp(tonumber(rpmShare) or 0, 0, 1),
        config.ENGAGEMENT_SHOCK_RPM_THRESHOLD, false)
    local damage = 0
    local isShock = false

    for consumer, ratedTorque in pairs(engagementTorques or {}) do
        if previousActiveLinks == nil or previousActiveLinks[consumer] ~= true then
            local size = math.clamp(RMS_Utils.getPtoNativeCapacityData(vehicle, ratedTorque), config.ENGAGEMENT_SHOCK_MIN_SIZE, 1)
            damage = damage + config.ENGAGEMENT_CLUTCH_DAMAGE + config.ENGAGEMENT_SHOCK_DAMAGE * rpmFactor * size
            isShock = isShock or rpmFactor > 0
        end
    end

    return damage, isShock
end

---Counts the PTO links that became active since the previous frame
function RMS_Utils.getPtoEngagementTransitionCount(activeLinks, previousActiveLinks)
    local count = 0
    for consumer, _ in pairs(activeLinks or {}) do
        if previousActiveLinks == nil or previousActiveLinks[consumer] ~= true then
            count = count + 1
        end
    end
    return count
end

function RMS_Utils.getIsLoaderMovingTool(tool)
    return tool.axis == "AXIS_FRONTLOADER_ARM" or tool.axis == "AXIS_FRONTLOADER_TOOL"
end

function RMS_Utils.getFrontPtoOutput(vehicle)
    local outputs = vehicle.getOutputPowerTakeOffs ~= nil and vehicle:getOutputPowerTakeOffs() or nil
    if outputs == nil or #outputs < 2 then
        return nil
    end

    local joints = vehicle.spec_attacherJoints.attacherJoints
    for _, output in ipairs(outputs) do
        local isFront = next(output.attacherJointIndices) ~= nil
        for index in pairs(output.attacherJointIndices) do
            local _, _, z = localToLocal(joints[index].jointTransform, vehicle.rootNode, 0, 0, 0)
            isFront = isFront and z > 0
        end
        if isFront then
            return output
        end
    end
    return nil
end

local function getShaftEndAngle(node, x, y, z, length)
    local dirX, dirY, dirZ = localDirectionToWorld(node, 0, 0, 1)
    return math.deg(math.acos(math.clamp(math.abs(dirX * x + dirY * y + dirZ * z) / length, 0, 1)))
end

---Returns the angle of the worse joint of a shaft, zero when collapsed
function RMS_Utils.getPtoShaftAngle(output)
    local outputNode, inputNode = output.outputNode, output.connectedInput.inputNode
    local x1, y1, z1 = getWorldTranslation(outputNode)
    local x2, y2, z2 = getWorldTranslation(inputNode)
    local x, y, z = x2 - x1, y2 - y1, z2 - z1
    local length = math.sqrt(x * x + y * y + z * z)
    if length < 0.001 then
        return 0
    end
    return math.max(getShaftEndAngle(outputNode, x, y, z, length), getShaftEndAngle(inputNode, x, y, z, length))
end

-- a fitted shaft works straight: only the angle the driver adds counts
local function getDriverShaftAngle(output, consumer)
    local angle = RMS_Utils.getPtoShaftAngle(output)
    if output.rmsWorkConsumer ~= consumer then
        output.rmsWorkConsumer, output.rmsWorkAngle = consumer, nil
    end
    local isLowerable = consumer.getAllowsLowering ~= nil and consumer:getAllowsLowering()
    if not isLowerable then
        -- a trailed one runs straightest going straight
        output.rmsWorkAngle = math.min(output.rmsWorkAngle or angle, angle)
    elseif consumer.getIsLowered ~= nil and consumer:getIsLowered(true) then
        output.rmsWorkAngle = angle
    end
    if output.rmsWorkAngle == nil then
        return angle
    end
    return RMS_Config.CORE.PTO_FACTOR_DATA.SHAFT_ANGLE_REFERENCE + math.max(angle - output.rmsWorkAngle, 0)
end

local function collectConnectedPtoData(vehicleObj, data, visited, isOutputCounted)
    if vehicleObj == nil or visited[vehicleObj] then
        return
    end
    visited[vehicleObj] = true

    if vehicleObj.getOutputPowerTakeOffs == nil then
        return
    end

    local outputs = vehicleObj:getOutputPowerTakeOffs()
    for _, output in pairs(outputs or {}) do
        local consumer = output.connectedVehicle
        if output.connectedInput ~= nil and consumer ~= nil and (isOutputCounted == nil or isOutputCounted(output)) then
            if data.connectedVehicles[consumer] ~= true then
                data.connectedVehicles[consumer] = true

                local isEngaged = consumer.getIsPowerTakeOffActive ~= nil and consumer:getIsPowerTakeOffActive() or false
                local torque = 0
                if consumer.getConsumedPtoTorque ~= nil then
                    local consumedTorque = consumer:getConsumedPtoTorque(nil, true)
                    torque = tonumber(consumedTorque) or 0
                end
                local measuredRpm = consumer.getPtoRpm ~= nil and (tonumber(consumer:getPtoRpm()) or 0) or 0
                local configuredRpm = consumer.spec_powerConsumer ~= nil
                    and (tonumber(consumer.spec_powerConsumer.ptoRpm) or 0) or 0
                local rpm = measuredRpm
                if isEngaged and rpm <= 0 then
                    rpm = configuredRpm
                end
                local power = torque * rpm * math.pi / 30

                data.torque = data.torque + torque
                data.rpm = math.max(data.rpm, rpm)
                data.power = data.power + power

                if isEngaged or measuredRpm > 0 or torque > 0 then
                    data.isActive = true
                end
                local shaftAngle = getDriverShaftAngle(output, consumer)
                if isEngaged then
                    data.activeLinks[consumer] = true
                    data.shaftAngle = math.max(data.shaftAngle, shaftAngle)

                    if consumer.spec_sprayer == nil then
                        local neededMaxPower = consumer.spec_powerConsumer ~= nil
                            and (tonumber(consumer.spec_powerConsumer.neededMaxPtoPower) or 0) or 0
                        data.engagementTorques[consumer] = configuredRpm > 0 and neededMaxPower / (configuredRpm * math.pi / 30) or 0

                        if vehicleObj.spec_combine == nil
                            and consumer.getAllowsLowering ~= nil and consumer:getAllowsLowering()
                            and consumer.getIsLowered ~= nil and not consumer:getIsLowered(true) then
                            data.isRaised = true
                        end
                    end
                end
            end

            collectConnectedPtoData(consumer, data, visited)
        end
    end
end

-- @param string? side "front", "rear", or nil for all outputs
-- @return table data PTO torque, rpm, power, active state and links
function RMS_Utils.getConnectedPtoData(vehicle, side)
    local data = {
        isActive = false,
        torque = 0,
        rpm = 0,
        power = 0,
        connectedVehicles = {},
        activeLinks = {},
        engagementTorques = {},
        isRaised = false,
        shaftAngle = 0
    }
    local visited = {}

    local isOutputCounted = nil
    if side ~= nil then
        local frontOutput = RMS_Utils.getFrontPtoOutput(vehicle)
        isOutputCounted = function(output)
            return (output == frontOutput) == (side == "front")
        end
    end

    collectConnectedPtoData(vehicle, data, visited, isOutputCounted)
    return data
end

---Turns every implement driven by the PTO on or off
-- @param string? side "front", "rear", or nil for all outputs
function RMS_Utils.setConnectedPtoConsumersTurnedOn(vehicle, isTurnedOn, side)
    local changed = false
    local ptoData = RMS_Utils.getConnectedPtoData(vehicle, side)

    for consumer, _ in pairs(ptoData.connectedVehicles) do
        if consumer.getIsTurnedOn ~= nil
            and consumer.setIsTurnedOn ~= nil
            and consumer:getIsTurnedOn() ~= isTurnedOn then
            consumer:setIsTurnedOn(isTurnedOn)
            changed = true
        end
    end

    return changed
end

local machineHit = {}

function machineHit:onRaycastHit(hitActorId, x, y, z, distance, nx, ny, nz, subShapeIndex, hitShapeId)
    local vehicle = g_currentMission.vehicleSystem:getVehicleByNodeId(hitActorId, hitShapeId)
    if vehicle ~= nil and vehicle.spec_RealisticMechanicalSystems ~= nil then
        self.vehicle, self.distance = vehicle, distance
        return false
    end
    return true
end

---Returns the first machine a tool node points at, and its distance
function RMS_Utils.raycastMachine(node)
    machineHit.vehicle, machineHit.distance = nil, nil
    local x, y, z = getWorldTranslation(node)
    local dirX, dirY, dirZ = localDirectionToWorld(node, 0, 0, -1)
    raycastAll(x, y, z, dirX, dirY, dirZ, RMS_Config.FIELD_CARE.RAYCAST_DISTANCE, "onRaycastHit", machineHit, nil, false, true)
    return machineHit.vehicle, machineHit.distance
end

---Returns the gap between segments in px: halved past 30, none past 60
function RMS_Utils.getSegmentGap(count, gap)
    return count > 60 and 0 or count > 30 and gap / 2 or gap
end

local function fillPixels(left, width, y, height, color)
    drawFilledRect(left * g_pixelSizeX, y, width * g_pixelSizeX, height, color[1], color[2], color[3], color[4] or 1)
end

---Draws a row of segments on whole pixels, the first ones lit
-- @return float? x of the first unlit segment, nil on a bar too dense to split
-- @return float? y
-- @return float? width
-- @return float? height
function RMS_Utils.drawSegments(x, y, width, height, count, lit, litColor, restColor, gap)
    local left, total = math.floor(x / g_pixelSizeX + 0.5), math.floor(width / g_pixelSizeX + 0.5)
    y, height = math.floor(y / g_pixelSizeY + 0.5) * g_pixelSizeY, math.floor(height / g_pixelSizeY + 0.5) * g_pixelSizeY
    local gapPixels = math.floor(gap / g_pixelSizeX + 0.5)
    local segment = math.floor((total - gapPixels * (count - 1)) / count)
    if gapPixels == 0 or segment < 2 then
        local litWidth = math.floor(total * lit / count + 0.5)
        fillPixels(left, litWidth, y, height, litColor)
        fillPixels(left + litWidth, total - litWidth, y, height, restColor)
        return
    end

    local extra, position, nextX, nextWidth = total - segment * count - gapPixels * (count - 1), left, nil, nil
    for index = 1, count do
        local segmentWidth = segment + (index <= extra and 1 or 0)
        fillPixels(position, segmentWidth, y, height, index <= lit and litColor or restColor)
        if index == lit + 1 then
            nextX, nextWidth = position * g_pixelSizeX, segmentWidth * g_pixelSizeX
        end
        position = position + segmentWidth + gapPixels
    end
    if nextX ~= nil then
        return nextX, y, nextWidth, height
    end
end

---Shows a level on the level gauge of a screen
function RMS_Utils.setLevelGauge(fillElement, underElement, trackWidth, level)
    local fill, color = RMS_Fluids.getGaugeFill(level, RMS_Utils.COLOR.HIGHLIGHT)
    fillElement:setVisible(fill > 0)
    underElement:setVisible(fill <= 0)
    fillElement:setSize(GuiUtils.alignValueToScreenPixels(trackWidth * fill, true), nil)
    fillElement:setImageColor(nil, color[1], color[2], color[3], color[4])
    underElement:setImageColor(nil, color[1], color[2], color[3], color[4])
end

---Returns the squared distance past a threshold, 0 on the safe side of it
-- @param float? customMax end of the scale: floor when less is worse, else ceiling (default 1)
function RMS_Utils.calculateQuadraticMultiplier(level, threshold, lessIsWorse, customMax)
    local distance
    if lessIsWorse then
        if level >= threshold then
            return 0.0
        end
        local floor = tonumber(customMax)
        if floor ~= nil and floor < threshold then
            distance = (threshold - math.max(level, floor)) / math.max(threshold - floor, 0.0001)
        else
            distance = (threshold - level) / math.max(threshold, 0.0001)
        end
    else
        if level <= threshold then
            return 0.0
        end
        distance = (level - threshold) / ((customMax or 1) - threshold)
    end
    return distance * distance
end

---Returns the lugging severity of a motor, high load at low rpm
function RMS_Utils.getEngineLuggingSeverity(motor, motorLoad, loadThreshold)
    local minimum = RealisticMechanicalSystems.sanitizeNumber(motor:getMinRpm(), 0, 0)
    local maximum = RealisticMechanicalSystems.sanitizeNumber(motor:getMaxRpm(), 0, 0)
    if minimum <= 0 or maximum <= minimum or loadThreshold >= 1 then return 0 end

    local rangeShare = RMS_Config.CORE.LUGGING_RPM_RANGE_THRESHOLD
    local start = minimum + (maximum - minimum) * rangeShare
    local rpm = RealisticMechanicalSystems.sanitizeNumber(motor:getLastRealMotorRpm(), maximum, 0)
    local loadShare = math.clamp((motorLoad - loadThreshold) / (1 - loadThreshold), 0, 1)
    local rpmShare = math.clamp((start - rpm) / (start - minimum), 0, 1)
    return loadShare * loadShare * rpmShare * rpmShare
end

---Returns the torque against the torque at peak power the block holds
function RMS_Utils.getRatedTorqueRatio(vehicle, stockLoad)
    local motor = vehicle.spec_motorized.motor
    local sanitize = RealisticMechanicalSystems.sanitizeNumber
    local ratedSpeed = sanitize(motor.peakMotorPowerRotSpeed, 0, 0)
    local rated = ratedSpeed > 0 and sanitize(motor.peakMotorPower, 0, 0) / ratedSpeed or 0
    local rpm = sanitize(motor:getLastRealMotorRpm(), ratedSpeed * 30 / math.pi, 0)
    local rise = rated > 0 and sanitize(motor:getTorqueCurve():get(rpm), rated, 0) / rated or 1
    return stockLoad * rise / RMS_EngineRemap.getOverloadRatio(vehicle)
end

---Life law past the rated level: wear grows as the ratio to the exponent
function RMS_Utils.getLifeLawFactor(ratio, exponent)
    return ratio > 1 and ratio ^ exponent - 1 or 0
end

---Wear of a cold circuit, as liners wear by their start temperature
function RMS_Utils.getColdWearFactor(temperature, reference)
    local C = RMS_Config.CORE.ENGINE_FACTOR_DATA
    if temperature >= reference then
        return 0
    end
    local measured = C.COLD_MOTOR_TEMP_THRESHOLD - C.COLD_MOTOR_MEASURED_MIN
    return math.exp(C.COLD_MOTOR_WEAR_SLOPE * math.min(reference - temperature, measured)) - 1
end

---Wear past a temperature, life halved every HEAT_HALVING_K
function RMS_Utils.getHeatWearFactor(temperature, reference)
    if temperature <= reference then
        return 0
    end
    return 2 ^ ((temperature - reference) / RMS_Config.CORE.HEAT_HALVING_K) - 1
end

function RMS_Utils.getPartFailureChance(partId, fromWear, toWear)
    local C = RMS_Config.CORE
    local life = C.COMPONENT_LIVES[RMS_Breakdowns.BreakdownRegistry[partId].component]
    local lives = C.MACHINE_LIFE_HOURS / life.scale
    return 1 - math.exp((fromWear * lives) ^ life.shape - (toWear * lives) ^ life.shape)
end

---Returns a part's wear over the risk horizon; a lamp's only while lit
function RMS_Utils.getPartRiskHorizon(partId)
    local C = RMS_Config.CORE
    if RMS_Breakdowns.BreakdownRegistry[partId].wearsWhile ~= nil then
        return C.RISK_HORIZON_WEAR * C.USED_VEHICLE_HISTORY.LIT_SHARE
    end
    return C.RISK_HORIZON_WEAR
end

---Returns a part's risk over the wear ahead, as a multiple of new
function RMS_Utils.getPartRiskRatio(partId, wear)
    local horizon = RMS_Utils.getPartRiskHorizon(partId)
    return RMS_Utils.getPartFailureChance(partId, wear, wear + horizon) / RMS_Utils.getPartFailureChance(partId, 0, horizon)
end

function RMS_Utils.getIsPartWorn(partId, wear)
    return wear >= RMS_Utils.getPartB10Wear(partId) and RMS_Utils.getPartRiskRatio(partId, wear) >= RMS_Config.CORE.WORN_PART_RISK_RATIO
end

function RMS_Utils.getPartB10Wear(partId)
    local C = RMS_Config.CORE
    local life = C.COMPONENT_LIVES[RMS_Breakdowns.BreakdownRegistry[partId].component]
    return life.scale * (-math.log(1 - C.WORN_PART_FAILED_SHARE)) ^ (1 / life.shape) / C.MACHINE_LIFE_HOURS
end

---Returns a system's risk over the wear ahead, as a multiple of new
function RMS_Utils.getSystemRiskRatio(vehicle, systemKey, partWear)
    local survival, newSurvival = nil, 1
    for _, partId in ipairs(vehicle.spec_RealisticMechanicalSystems.systemParts[systemKey]) do
        if partWear[partId] ~= nil then
            local horizon = RMS_Utils.getPartRiskHorizon(partId)
            survival = (survival or 1) * (1 - RMS_Utils.getPartFailureChance(partId, partWear[partId], partWear[partId] + horizon))
            newSurvival = newSurvival * (1 - RMS_Utils.getPartFailureChance(partId, 0, horizon))
        end
    end
    if survival == nil then
        return nil
    end
    return (1 - survival) / (1 - newSurvival)
end

---Converts a risk ratio to the tier of a report
-- @return integer? tier 1 to 3, nil when no RMS assessment is available
function RMS_Utils.getBreakdownRiskTier(ratio)
    if ratio == nil then return nil end
    if ratio < RMS_Config.CORE.RISK_RATIO_MODERATE then return 1 end
    if ratio < RMS_Config.CORE.RISK_RATIO_HIGH then return 2 end
    return 3
end

---Formats an assessed risk as Low, Moderate or High
function RMS_Utils.formatBreakdownRisk(tier)
    local keys = {"low", "moderate", "high"}
    local key = keys[tier]
    return g_i18n:getText(key ~= nil and ("rms_report_risk_" .. key) or "rms_report_state_not_available")
end

---Splits a decimal hour count into whole hours and minutes
function RMS_Utils.convertHoursToHoursAndMinutes(totalHours)
    local minutes = totalHours ~= nil and math.floor(math.max(totalHours, 0) * 60 + 0.5) or 0
    return math.floor(minutes / 60), minutes % 60
end

---Writes the farm balance as the shop does, red below zero
function RMS_Utils.setBalance(moneyBox, moneyBoxBg, balanceElement)
    local money = g_currentMission:getMoney()
    local GUI_PROFILE = ShopMenu.GUI_PROFILE
    balanceElement:applyProfile(math.floor(money) <= -1 and GUI_PROFILE.SHOP_MONEY_NEGATIVE or GUI_PROFILE.SHOP_MONEY, nil, true)
    balanceElement:setText(g_i18n:formatMoney(money, 0, true, false))
    moneyBox:invalidateLayout()
    moneyBoxBg:setSize(moneyBox.flowSizes[1] + 60 * g_pixelSizeScaledX)
end

local function layOut(element)
    for _, child in ipairs(element.elements) do
        layOut(child)
    end
    -- a layout box, told as TextElement:updateSize tells one
    if element.invalidateLayout ~= nil then
        element:invalidateLayout()
    end
end

---Clones a template at the end of its parent, then deletes the template
function RMS_Utils.cloneTemplate(template, count)
    local parent = template.parent
    template:unlinkElement()
    local clones = {}
    for index = 1, count do
        clones[index] = template:clone(parent)
        clones[index].templateIndex = index
    end
    template:delete()
    -- GuiElement:clone adds a child to its box before giving it its size
    layOut(parent)
    return clones
end

---Insets a card background in its frame by whole screen pixels
function RMS_Utils.insetCardBackground(card)
    local frame, background = card:getDescendantByName("frame"), card:getDescendantByName("background")
    -- two reference pixels: whole, every edge rounds alike on the screen
    local pixels = math.max(math.floor(2 * g_pixelSizeScaledX * g_screenWidth + 0.5), 1)
    local insetX, insetY = pixels / g_screenWidth, pixels / g_screenHeight
    background:setPosition(frame.position[1] + insetX, frame.position[2] - insetY)
    background:setSize(frame.size[1] - 2 * insetX, frame.size[2] - 2 * insetY)
end

---Returns the machine a tool is connected to, server or client
function RMS_Utils.getConnectedObject(spec)
    if spec.targetObjectId ~= nil then
        return NetworkUtil.getObject(spec.targetObjectId)
    end
    return spec.target
end

---Returns the key holding a value in a table
function RMS_Utils.getKeyByValue(tbl, value)
    for key, entry in pairs(tbl) do
        if entry == value then
            return key
        end
    end
    return nil
end

---Tells whether at least one diagnosed breakdown is selected for repair
function RMS_Utils.hasSelectedVisibleBreakdown(vehicle)
    local breakdowns = vehicle ~= nil and vehicle.getActiveBreakdowns ~= nil and vehicle:getActiveBreakdowns() or {}
    for _, breakdown in pairs(breakdowns) do
        if breakdown.isSelectedForRepair and breakdown.isVisible then
            return true
        end
    end
    return false
end

---Ids of the breakdowns the workshop knows, worst stage first
function RMS_Utils.getVisibleBreakdownIds(vehicle)
    local breakdowns = vehicle:getActiveBreakdowns()
    local ids = {}
    for id, breakdown in pairs(breakdowns) do
        if breakdown.isVisible then
            table.insert(ids, id)
        end
    end
    table.sort(ids, function(a, b)
        local aStage, bStage = breakdowns[a].stage or 0, breakdowns[b].stage or 0
        if aStage ~= bStage then
            return aStage > bStage
        end
        return tostring(a) < tostring(b)
    end)
    return ids
end

---Stage and description of a known breakdown, as the workshop words them
function RMS_Utils.getBreakdownTexts(vehicle, id, breakdown)
    local SOURCES = RealisticMechanicalSystems.BREAKDOWN_SOURCES
    if breakdown.isActive == false and breakdown.source == SOURCES.QUICK_FIX then
        return g_i18n:getText("rms_breakdowns_quick_fix_stage"), g_i18n:getText("rms_breakdowns_temporarily_repaired_description")
    elseif breakdown.isActive == false and breakdown.source == SOURCES.POOR_PARTS then
        return g_i18n:getText("rms_breakdowns_defected_parts_stage"), g_i18n:getText("rms_breakdowns_defected_parts_detected_description")
    end
    local definition = RMS_Breakdowns.BreakdownRegistry[id]
    local stage = definition.stages[breakdown.stage]
    return g_i18n:getText(stage.severity), g_i18n:getText(RMS_Breakdowns.getStageDescription(vehicle, stage, breakdown, definition))
end

---Returns the name a breakdown takes where its organ differs, if any
function RMS_Utils.getBreakdownNameVariant(vehicle, definition)
    if vehicle == nil or definition.getNameVariant == nil then
        return nil
    end
    return definition.getNameVariant(vehicle)
end

---Returns the text key of the part a breakdown hits on a vehicle
function RMS_Utils.getBreakdownPartKey(vehicle, definition)
    local variant = RMS_Utils.getBreakdownNameVariant(vehicle, definition)
    return variant ~= nil and definition.variantParts[variant] or definition.part or definition.system
end

---Name of the part a breakdown hits on a vehicle
function RMS_Utils.getBreakdownPartName(id, vehicle)
    return g_i18n:getText(RMS_Utils.getBreakdownPartKey(vehicle, RMS_Breakdowns.BreakdownRegistry[id]))
end

-- @param table? items stage items, each common to every mode or tied to one by its branch
function RMS_Utils.getBranchItems(items, breakdown)
    local branchItems = {}
    for _, item in ipairs(items or {}) do
        if item.branch == nil or item.branch == breakdown.branch then
            table.insert(branchItems, item)
        end
    end
    return branchItems
end

---Writes the active breakdowns, one comma separated entry each
function RMS_Utils.serializeBreakdowns(breakdownsTable)
    local entries = {}
    for id, breakdown in pairs(breakdownsTable) do
        local overdue = breakdown.warrantyServiceOverdue
        table.insert(entries, string.format("%s,%d,%.2f,%d,%d,%d,%.2f,%d,%d,%d,%d,%s,%d", id, breakdown.stage,
            breakdown.progressTimer or 0, toFlag(breakdown.isVisible), toFlag(breakdown.isSelectedForRepair),
            toFlag(breakdown.isActive ~= false), math.max(tonumber(breakdown.resumeTimer) or 0, 0),
            toCount(breakdown.source), toCount(breakdown.effectTargetIndex), toCount(breakdown.branch),
            overdue == nil and -1 or toFlag(overdue), breakdown.usedPartHours or "", toCount(breakdown.warrantyAbuse)))
    end
    return table.concat(entries, ";")
end

---Writes a date as day, month and year, empty without a day
function RMS_Utils.serializeDate(dateTable)
    local hasDay = dateTable ~= nil and dateTable.day ~= nil
    return hasDay and string.format("%d,%d,%d", dateTable.day, dateTable.month, dateTable.year) or ""
end

---Percent-escapes all but letters, digits and - . _ ~
function RMS_Utils.encodeDelimitedString(value)
    if value == nil then
        return ""
    end
    local escaped = string.gsub(tostring(value), "[^%w%-%._~]", function(char)
        return string.format("%%%02X", string.byte(char))
    end)
    return escaped
end

---Restores the characters escaped by encodeDelimitedString
function RMS_Utils.decodeDelimitedString(value)
    local decoded = string.gsub(tostring(value or ""), "%%(%x%x)", function(hex)
        return string.char(tonumber(hex, 16))
    end)
    return decoded
end

---Reads a date written by serializeDate, empty when unreadable
function RMS_Utils.deserializeDate(dateString)
    local day, month, year = string.match(dateString or "", "([^,]+),([^,]+),([^,]+)")
    if day == nil then
        return {}
    end
    return { day = tonumber(day), month = tonumber(month), year = tonumber(year) }
end

---Reads the breakdowns written by serializeBreakdowns, older saves too
function RMS_Utils.deserializeBreakdowns(breakdownString)
    local breakdowns = {}
    for entry in string.gmatch(breakdownString or "", "[^;]+") do
        local fields = { string.match(entry, BREAKDOWN_ENTRY_PATTERN) }
        if fields[1] ~= nil then
            local breakdown = {
                stage = tonumber(fields[2]),
                progressTimer = tonumber(fields[3]),
                isVisible = tonumber(fields[4]) == 1,
                isSelectedForRepair = tonumber(fields[5]) == 1,
                isActive = tonumber(fields[6]) == 1,
                resumeTimer = math.max(tonumber(fields[7]) or 0, 0),
                source = tonumber(fields[8]) or RealisticMechanicalSystems.BREAKDOWN_SOURCES.RANDOM,
                effectTargetIndex = toCount(fields[9]),
                branch = toCount(fields[10]),
                warrantyAbuse = RealisticMechanicalSystems.WARRANTY_ABUSES[toCount(fields[13])] and toCount(fields[13]) or nil,
                usedPartHours = tonumber(fields[12])
            }
            -- -1: no warranty verdict saved
            local overdue = tonumber(fields[11])
            if overdue ~= -1 then
                breakdown.warrantyServiceOverdue = overdue == 1
            end
            breakdowns[fields[1]] = breakdown
        end
    end
    return breakdowns
end


---Formats a finish hour, adding the days crossed before it
-- @param float? finishTime hour of the day
function RMS_Utils.formatFinishTime(finishTime, daysToAdd)
    if finishTime == nil then
        return ""
    end
    local hours, minutes = RMS_Utils.convertHoursToHoursAndMinutes(finishTime)
    local days = (daysToAdd or 0) + math.floor(hours / 24)
    local dayText = ""
    if days == 1 then
        dayText = g_i18n:getText("rms_spec_tomorrow_at")
    elseif days == 2 then
        dayText = g_i18n:getText("rms_spec_day_after_tomorrow_at")
    elseif days > 2 then
        dayText = string.gsub(g_i18n:getText("rms_spec_in_days_at"), "{days}", days)
    end
    return string.format("%s%02d:%02d", dayText, hours % 24, minutes)
end

---Returns the current primary keyboard binding of an action
function RMS_Utils.getPrimaryKeyboardInputText(actionName, fallbackText)
    for _, action in ipairs(g_inputBinding.actions) do
        if action.name == actionName and type(action.primaryKeyboardInput) == "string" then
            local keyNames = {}
            for inputName in string.gmatch(action.primaryKeyboardInput, "%S+") do
                local inputId = Input[inputName]
                local keyName = inputId ~= nil and KeyboardHelper.getDisplayKeyName(inputId) or nil

                if keyName ~= nil and keyName ~= "" then
                    table.insert(keyNames, keyName)
                end
            end

            if #keyNames > 0 then
                return table.concat(keyNames, " + ")
            end
        end
    end

    return fallbackText or ""
end

---Returns the ambient temperature of the current weather
function RMS_Utils.getAmbientTemperature()
    return g_currentMission.environment.weather:getCurrentTemperature()
end

---Formats a duration in days, hours and minutes
-- @param float? duration duration in hours
function RMS_Utils.formatDuration(duration)
    if duration == nil then
        return ""
    end
    local hours, minutes = RMS_Utils.convertHoursToHoursAndMinutes(duration)
    local days = math.floor(hours / 24)
    hours = hours - days * 24

    local text = days > 0 and string.format("%s %s ", days, getCountUnit(days, "rms_spec_day_one", "rms_spec_day_s")) or ""
    local hoursText = hours > 0 and string.format(g_i18n:getText("rms_spec_duration_format_hours"), hours,
        getCountUnit(hours, "rms_spec_hour_one", "rms_spec_hour_s")) or nil
    local minutesText = minutes > 0 and string.format(g_i18n:getText("rms_spec_duration_format_minutes"), minutes,
        getCountUnit(minutes, "rms_spec_minute_one", "rms_spec_minute_s")) or nil
    if hoursText ~= nil and minutesText ~= nil then
        return text .. string.format(g_i18n:getText("rms_spec_duration_format_combined"), hoursText, minutesText)
    end
    return text .. (hoursText or minutesText or "")
end


RMS_Utils.CONDITION_LEVELS = {0.8, 0.6, 0.4, 0.2}

local CONDITION_STATE_NAMES = {"EXCELLENT", "GOOD", "NORMAL", "BAD", "TERRIBLE"}

local SERVICE_LEVELS = {0.9, 0.7, 0.6, 0.5}

local SERVICE_STATE_NAMES = {"OPTIMAL", "SERVICE_GOOD", "RECOMMENDED", "REQUIRED", "OVERDUE"}

---Returns the tier a condition falls in, 1 being the best
function RMS_Utils.getConditionTier(condition)
    local levels = RMS_Utils.CONDITION_LEVELS
    for tier = 1, #levels do
        if condition >= levels[tier] then
            return tier
        end
    end
    return #levels + 1
end

---Formats a condition, exact after a complete inspection
function RMS_Utils.formatCondition(condition, isCompleteInspection)
    local STATES = RealisticMechanicalSystems.STATES
    if isCompleteInspection == nil then
        return g_i18n:getText(STATES.UNKNOWN)
    elseif not isCompleteInspection then
        return g_i18n:getText(STATES[CONDITION_STATE_NAMES[RMS_Utils.getConditionTier(condition)]])
    end
    return formatPercent(condition)
end

---Returns the share of the service interval still to run
function RMS_Utils.getServiceIntervalRemainingRatio(service)
    local threshold = math.clamp(tonumber(RMS_Config.CORE.SERVICE_EXPIRED_THRESHOLD) or 0.5, 0.0, 0.9999)
    local left = ((tonumber(service) or 0.0) - threshold) / math.max(1.0 - threshold, 0.0001)
    return math.clamp(left, 0.0, 1.0)
end

---Formats a service level, exact after a complete inspection
function RMS_Utils.formatService(service, isCompleteInspection)
    local STATES = RealisticMechanicalSystems.STATES
    if isCompleteInspection == nil then
        return g_i18n:getText(STATES.UNKNOWN)
    elseif not isCompleteInspection then
        return g_i18n:getText(STATES[SERVICE_STATE_NAMES[RMS_Utils.getServiceTier(service)]])
    end
    return formatPercent(RMS_Utils.getServiceIntervalRemainingRatio(service))
end


---Returns the tier a service level falls in, 1 being the best
function RMS_Utils.getServiceTier(service)
    return getLevelTier(SERVICE_LEVELS, tonumber(service) or 0.0)
end


local function getTierCeiling(levels, tier)
    return tier > 1 and levels[tier - 1] or 1.0
end


---Returns the condition ring ratio, exact after a complete inspection
function RMS_Utils.getConditionRingRatio(condition, isCompleteInspection)
    if isCompleteInspection == nil then
        return 0.0
    elseif not isCompleteInspection then
        return getTierCeiling(RMS_Utils.CONDITION_LEVELS, RMS_Utils.getConditionTier(condition))
    end
    return math.clamp(tonumber(condition) or 0.0, 0.0, 1.0)
end


---Returns the service ring ratio, exact after a complete inspection
function RMS_Utils.getServiceRingRatio(service, isCompleteInspection)
    if isCompleteInspection == nil then
        return 0.0
    elseif not isCompleteInspection then
        service = getTierCeiling(SERVICE_LEVELS, RMS_Utils.getServiceTier(service))
    end
    return RMS_Utils.getServiceIntervalRemainingRatio(service)
end


---Formats how many whole hours of work an inspection report is old
function RMS_Utils.formatReportAge(hours)
    if hours == nil then
        return g_i18n:getText("rms_spec_never")
    elseif hours < 1 then
        return g_i18n:getText("rms_spec_work_under_hour_ago")
    end
    return string.format(g_i18n:getText("rms_spec_work_hours_ago_format"), g_i18n:formatNumber(math.floor(hours), 0), g_i18n:getText("rms_spec_op_hours_short"))
end

-- texts of a date counted in months: none, this month, months ago
local MONTHS_AGO_TEXTS = {
    fleet = { "rms_spec_never", "rms_spec_this_month", "rms_spec_months_ago_format" },
    shop = { "rms_shop_last_maintenance_never", "rms_shop_last_maintenance_this_month", "rms_shop_last_maintenance_months_ago" }
}

local function formatMonthsAgo(pastDate, texts)
    if pastDate == nil then
        return g_i18n:getText(texts[1])
    end
    local environment = g_currentMission.environment
    local monthsAgo = math.max(0, (environment.currentYear - pastDate.year) * 12 + environment.currentPeriod - pastDate.month)
    if monthsAgo == 0 then
        return g_i18n:getText(texts[2])
    end
    return string.format(g_i18n:getText(texts[3]), monthsAgo,
        g_i18n:getText(monthsAgo == 1 and "rms_spec_month_ago_one" or "rms_spec_months_ago_unit"))
end

---Formats how long ago a date was, in months
function RMS_Utils.formatTimeAgo(pastDate)
    return formatMonthsAgo(pastDate, MONTHS_AGO_TEXTS.fleet)
end

---Formats the last maintenance of a machine as the shop lists it
function RMS_Utils.formatShopLastMaintenance(pastDate)
    return formatMonthsAgo(pastDate, MONTHS_AGO_TEXTS.shop)
end

function RMS_Utils.getOwnerCare(damage)
    local history = RMS_Config.CORE.USED_VEHICLE_HISTORY
    local share = (damage - history.DAMAGE_MIN) / (history.DAMAGE_MAX - history.DAMAGE_MIN)
    if share < 1 / 3 then
        return "careful"
    elseif share < 2 / 3 then
        return "regular"
    end
    return "neglected"
end

function RMS_Utils.getOwnerCareDamage(care)
    local history = RMS_Config.CORE.USED_VEHICLE_HISTORY
    local third = ({ careful = 0, regular = 1, neglected = 2 })[care]
    return history.DAMAGE_MIN + (third + 0.5) / 3 * (history.DAMAGE_MAX - history.DAMAGE_MIN)
end

function RMS_Utils.getSellerCare(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    for breakdownId in pairs(spec.activeBreakdowns) do
        if RMS_Breakdowns.BreakdownRegistry[breakdownId].isSelectable then
            return "neglected"
        end
    end
    for _, clock in ipairs(RealisticMechanicalSystems.SERVICE_CLOCKS) do
        if spec[clock.levelKey] < RMS_Config.CORE.SERVICE_EXPIRED_THRESHOLD then
            return "neglected"
        end
    end
    local fieldCare = RMS_Config.FIELD_CARE
    if spec.airFilterClogging > fieldCare.AIR_FILTER_BREAKDOWN_THRESHOLD or spec.lubricationLevel < fieldCare.LUBRICATION_WARNING_THRESHOLD then
        return "regular"
    end
    return "careful"
end

local OWNER_CARE_LABELS = { careful = "rms_owner_care_careful", regular = "rms_owner_care_regular", neglected = "rms_owner_care_neglected" }

---Formats how the previous owner of a used offer looked after it
function RMS_Utils.formatOwnerCare(damage)
    return g_i18n:getText(OWNER_CARE_LABELS[RMS_Utils.getOwnerCare(damage)])
end


---Reads the native lifetime odometer, already expressed in kilometres
function RMS_Utils.getOdometerKilometers(vehicle)
    local drivable = vehicle ~= nil and vehicle.spec_drivable or nil
    local kilometers = drivable ~= nil and tonumber(drivable.odometerMilage) or nil
    if kilometers == nil or kilometers ~= kilometers or kilometers < 0 or kilometers == math.huge then
        return nil
    end
    return kilometers
end

function RMS_Utils.formatOdometerKilometers(kilometers)
    kilometers = tonumber(kilometers)
    if kilometers == nil or kilometers ~= kilometers or kilometers < 0 or kilometers == math.huge then
        return g_i18n:getText("rms_odometer_not_recorded")
    end
    return g_i18n:formatNumber(kilometers, 1) .. " km"
end


---Formats hour-meter values and hourly deadlines
function RMS_Utils.formatHours(hours)
    return string.format("%s %s", g_i18n:formatNumber(tonumber(hours) or 0, 1), g_i18n:getText("rms_spec_op_hours_short"))
end


---Formats whole calendar months in the player's language.
function RMS_Utils.formatMonths(months)
    local count = math.max(months or 0, 0)
    return string.format(g_i18n:getText(count == 1 and "rms_service_month" or "rms_service_months"), g_i18n:formatNumber(count, 0))
end

---Formats an amount of a greasing interval in its unit
function RMS_Utils.formatGreasingAmount(tier, amount)
    local count = math.ceil(amount)
    if tier.unit == "months" then
        return RMS_Utils.formatMonths(count)
    elseif tier.unit == "bales" then
        return string.format(g_i18n:getText("rms_fleet_greasing_bales"), count)
    end
    return string.format(g_i18n:getText(count == 1 and "rms_fleet_greasing_day" or "rms_fleet_greasing_days"), count)
end

---Formats what is left of a greasing interval before its points fall due
function RMS_Utils.formatGreasingLeft(tier)
    return RMS_Utils.formatGreasingAmount(tier, math.max(tier.interval - tier.elapsed, 0))
end

---Names the actual circuit which causes the next service recommendation.
function RMS_Utils.formatServiceReason(vehicle, schedule, compact)
    if schedule == nil then return "" end
    return g_i18n:getText(RMS_Fluids.getCircuitTextKey(vehicle, schedule.clock.circuits[1], compact))
end

---Formats the two limits of a service deadline
function RMS_Utils.formatServiceDeadline(schedule, showInterval)
    if schedule == nil then return "" end
    local values = {}
    if schedule.interval < math.huge then
        local hours = showInterval and schedule.interval or math.max(schedule.interval - schedule.used, 0)
        table.insert(values, RMS_Utils.formatHours(hours))
    end
    local months = showInterval and schedule.months or schedule.remainingMonths
    if months ~= nil then
        table.insert(values, RMS_Utils.formatMonths(months))
    end
    if #values == 2 then
        return string.format(g_i18n:getText("rms_service_either"), values[1], values[2])
    end
    return values[1] or ""
end

---Says which change the next service is for and when it falls due
function RMS_Utils.formatServiceDue(vehicle, schedule, compact)
    local reason = RMS_Utils.formatServiceReason(vehicle, schedule, compact)
    if schedule ~= nil and schedule.calendarDue then
        return reason .. " · " .. g_i18n:getText("rms_service_calendar_due")
    end
    local remaining = schedule ~= nil and schedule.interval - schedule.used or 0
    if remaining < 0 then
        return string.format(g_i18n:getText("rms_inspection_service_overdue"), reason, RMS_Utils.formatHours(math.abs(remaining)))
    end
    return string.format(g_i18n:getText("rms_inspection_service_due_in"), reason, RMS_Utils.formatServiceDeadline(schedule))
end

---Writes a duration short enough for a column, in hours and minutes
-- @param float duration duration in hours
function RMS_Utils.formatShortDuration(duration)
    local hours, minutes = RMS_Utils.convertHoursToHoursAndMinutes(duration)
    if hours == 0 then
        return string.format(g_i18n:getText("rms_ws_levels_duration_minutes"), minutes)
    elseif minutes == 0 then
        return string.format(g_i18n:getText("rms_ws_levels_duration_hours"), hours)
    end
    return string.format(g_i18n:getText("rms_ws_levels_duration"), hours, minutes)
end

---Names a maintenance level by the hours between two of them on the machine
function RMS_Utils.formatMaintenanceLevel(vehicle, maintenanceType)
    return string.format(g_i18n:getText("rms_spec_maintenance_level"),
        RMS_Utils.formatHours(vehicle:getMaintenanceLevelInterval(maintenanceType)))
end

---Formats an engine power as the shop of the game writes it
function RMS_Utils.formatPower(hp)
    return string.format(g_i18n:getText("shop_maxPowerValueSingle"), MathUtil.round(hp))
end

---Names the first option of a service
-- @param string? workshopType of a remap to come, nil for the software fitted
function RMS_Utils.formatServiceOption(vehicle, serviceType, optionOne, workshopType)
    if serviceType == RealisticMechanicalSystems.STATUS.MAINTENANCE then
        return RMS_Utils.formatMaintenanceLevel(vehicle, optionOne)
    elseif serviceType == RealisticMechanicalSystems.STATUS.REMAP and vehicle.spec_motorized ~= nil then
        local stockHp = RMS_EngineRemap.getStockPeaks(vehicle)
        local power = optionOne == RMS_EngineRemap.REMAP and stockHp * (1 + RMS_EngineRemap.getGain(vehicle, workshopType)) or stockHp
        return string.format("%s · %s", g_i18n:getText(optionOne), RMS_Utils.formatPower(power))
    end
    return g_i18n:getText(optionOne)
end

---Returns the interval of the lightest maintenance fitting a new air filter
function RMS_Utils.formatAirFilterServiceHours(vehicle)
    for _, maintenanceType in ipairs(vehicle:getMaintenanceTypes()) do
        if RealisticMechanicalSystems.getMaintenanceRenewsAirFilter(maintenanceType) then
            return RMS_Utils.formatHours(vehicle:getMaintenanceLevelInterval(maintenanceType))
        end
    end
end


---Returns the label of a value against four descending thresholds
function RMS_Utils.getValueLabel(value, ideal, high, mid, low, ...)
    return ({ ... })[getLevelTier({ ideal, high, mid, low }, value)]
end


local RELIABILITY_LABELS = { "rms_reliability_average", "rms_reliability_fair", "rms_reliability_good", "rms_reliability_very_good" }
local SHOP_RELIABILITY_LABELS = { "rms_shop_reliability_average", "rms_shop_reliability_fair", "rms_shop_reliability_good",
    "rms_shop_reliability_very_good" }

---Formats a reliability value as its localized label
function RMS_Utils.formatReliability(value, isShop)
    value = tonumber(value) or 1
    local tier = value < 1.0 and 1 or value < 1.1 and 2 or value < 1.2 and 3 or 4
    return g_i18n:getText((isShop and SHOP_RELIABILITY_LABELS or RELIABILITY_LABELS)[tier])
end

function RMS_Utils.getServiceAccessKey(transmissionName)
    local name = string.lower(tostring(transmissionName or ""))
    if name:find("powershift", 1, true) or name:find("power_shift", 1, true) then return "STANDARD" end
    if name:find("cvt", 1, true) or name:find("variable", 1, true) then return "COMPLEX" end
    if name:find("manual", 1, true) then return "SIMPLE" end
    return "STANDARD"
end

---Loads the service access class of each motor configuration
function RMS_Utils.loadServiceAccess(xmlFile)
    local result = {}
    xmlFile:iterate("vehicle.motorized.motorConfigurations.motorConfiguration", function(index, key)
        local name = xmlFile:getString(key .. ".transmission#name")
        result[index] = name ~= nil and RMS_Utils.getServiceAccessKey(name) or result[1] or "STANDARD"
    end)
    return result
end

---Returns the service access profile of an owned or store vehicle
function RMS_Utils.getServiceAccessProfile(vehicle, storeItem, configurations)
    if storeItem == nil and vehicle ~= nil then
        storeItem = g_storeManager:getItemByXMLFilename(vehicle.configFileName)
    end
    local selected = configurations or (vehicle ~= nil and vehicle.configurations) or {}
    local index = selected.motor or 1
    local classifications = storeItem ~= nil and storeItem.specs ~= nil and storeItem.specs.serviceAccess or {}
    local key = classifications[index] or classifications[1]
    if key == nil and vehicle ~= nil then
        key = RMS_Utils.getServiceAccessKey(RealisticMechanicalSystems.getTransmissionType(vehicle))
    end
    return RMS_Config.SERVICE_ACCESS_PROFILES[key or "STANDARD"]
end

function RMS_Utils.getServiceAccessLabourFactor(vehicle, category)
    return RMS_Utils.getServiceAccessProfile(vehicle)[category] or 1
end

function RMS_Utils.formatServiceAccess(vehicle, storeItem, configurations, isShop)
    local profile = RMS_Utils.getServiceAccessProfile(vehicle, storeItem, configurations)
    return g_i18n:getText(isShop and profile.shopLabel or profile.label)
end

---Returns the colour of an original reliability
function RMS_Utils.getReliabilityColor(value)
    return RMS_Utils.getValueColor(tonumber(value) or 1, 1.1, 1.1, 1.0, 0, false)
end

---Returns the colour of the ease of service of a vehicle
function RMS_Utils.getServiceAccessColor(vehicle)
    local profiles = RMS_Config.SERVICE_ACCESS_PROFILES
    local profile = RMS_Utils.getServiceAccessProfile(vehicle)
    local tier = profile == profiles.SIMPLE and 1 or profile == profiles.COMPLEX and 3 or 2
    return RMS_Utils.getValueColorInverted(tier, 1, 1, 2, 3, false)
end

---Writes the causes of wear as alias:share pairs
-- @param table? causes share of each cause over the normal wear, by alias
function RMS_Utils.serializeWearCauses(causes)
    local parts = {}
    for alias, share in pairs(causes or {}) do
        if share >= 0.0005 then
            table.insert(parts, string.format("%s:%.3f", alias, share))
        end
    end
    table.sort(parts)
    return table.concat(parts, ",")
end

---Reads the causes of wear serializeWearCauses wrote
-- @return table causes share of each cause over the normal wear, by alias
function RMS_Utils.deserializeWearCauses(text)
    local causes = {}
    for alias, share in string.gmatch(text or "", "(%w+):([%d%.]+)") do
        causes[alias] = tonumber(share)
    end
    return causes
end


RMS_Utils.COLOR = {
    TEXT = {0.89627, 0.92158, 0.81485, 1.0},
    HIGHLIGHT = {0.22323, 0.40724, 0.00368, 1.0},
    TEXT_DIM = {0.5, 0.5, 0.5, 1.0},
    ALERT = {0.88, 0.18, 0.18, 1.0},
    RING_TRACK = {0.04374, 0.04374, 0.04374, 1.0},
    STAGE = {
        {0.89627, 0.92158, 0.81485, 1.0},
        {0.85, 0.78, 0.2, 1.0},
        {0.85, 0.5, 0.15, 1.0},
        {0.8, 0.2, 0.2, 1.0}
    }
}

---Entries of the maintenance log the record shows, newest first
function RMS_Utils.getVisibleLogEntries(vehicle)
    local log = vehicle.spec_RealisticMechanicalSystems.maintenanceLog
    local entries = {}
    for index = #log, 1, -1 do
        if RMS_Utils.normalizeBoolValue(log[index].isVisible, true) then
            table.insert(entries, log[index])
        end
    end
    return entries
end

---Breakdowns resolved by the completed repairs and overhauls of a log
function RMS_Utils.getResolvedBreakdownsCount(log)
    local STATUS, count = RealisticMechanicalSystems.STATUS, 0
    for _, entry in ipairs(log) do
        if entry.isCompleted ~= false and (entry.type == STATUS.REPAIR or entry.type == STATUS.OVERHAUL) then
            for _, id in ipairs(entry.conditionData ~= nil and entry.conditionData.selectedBreakdowns or {}) do
                if RMS_Breakdowns.BreakdownRegistry[id] ~= nil then
                    count = count + 1
                end
            end
        end
    end
    return count
end

---Formats a maintenance log date in the same compact form as the report screen
function RMS_Utils.formatMaintenanceLogDate(entry)
    local year = entry ~= nil and entry.date ~= nil and tonumber(entry.date.year) or 0
    local yearText = year >= 10 and tostring(year) or "0" .. tostring(year)
    local day = entry ~= nil and entry.date ~= nil and tonumber(entry.date.day) or 1
    local month = entry ~= nil and entry.date ~= nil and tonumber(entry.date.month) or 1
    return string.format("%s %s. '%s", day, g_i18n:formatPeriod(month, true), yearText)
end

---Names a service state, the repaint by its RMS name
function RMS_Utils.formatServiceState(status)
    if status == RealisticMechanicalSystems.STATUS.BODYWORK then
        return g_i18n:getText("rms_spec_state_bodywork")
    end
    return g_i18n:getText(status)
end

---Returns the label, colour and icon of an intervention type
function RMS_Utils.getLogTypePresentation(entry)
    local status = RealisticMechanicalSystems.STATUS
    local entryType = entry ~= nil and entry.type or nil

    if entryType == status.REPAIR then
        return g_i18n:getText("rms_ws_action_repair"), {0.88, 0.12, 0.12, 1}, "gui.contextAction_icon_repair"
    elseif entryType == status.MAINTENANCE then
        return g_i18n:getText("rms_ws_action_maintenance"), RMS_Utils.COLOR.HIGHLIGHT, "rms_Hud.maintenance"
    elseif entryType == status.INSPECTION then
        return g_i18n:getText("rms_ws_action_inspection"), {1, 1, 1, 1}, "gui.icon_vehicleDealer_search"
    elseif entryType == status.OVERHAUL then
        return g_i18n:getText("rms_ws_action_overhaul"), {1, 0.5, 0, 1}, "gui.icon_ingameMenu_options"
    elseif entryType == status.REFILL then
        return g_i18n:getText("rms_ws_action_refill"), RMS_Utils.COLOR.HIGHLIGHT, "rms_WorkshopFluids.engineOil"
    elseif entryType == status.BODYWORK then
        return g_i18n:getText("rms_spec_state_bodywork"), {1, 1, 1, 1}, "gui.icon_vehicleDealer_machines"
    elseif entryType == status.REMAP then
        return g_i18n:getText("rms_spec_state_remap"), RMS_Utils.COLOR.HIGHLIGHT, "gui.storeAttribute_power"
    elseif entryType == RealisticMechanicalSystems.LOG_DIAGNOSTIC_READING then
        return g_i18n:getText("rms_diagnostic_log_title"), {1, 1, 1, 1}, "rms_Diagnostic.stethoscope"
    end

    return "-", {1, 1, 1, 1}, "gui.icon_ingameMenu_options"
end

local function populateTextColumnsRow(items, index, cell, columns)
    local rowItems = items or {}
    local columnCount = #columns

    for columnIndex, column in ipairs(columns) do
        local text = rowItems[(index - 1) * columnCount + columnIndex] or ""
        local isVisible = text ~= ""
        local textElement = cell:getAttribute(column.text)
        textElement:setText(text)
        textElement:setVisible(isVisible)

        if column.bullet ~= nil then
            cell:getAttribute(column.bullet):setVisible(isVisible)
        end
    end
end

---Fills a two-column text row and hides its unused right column
function RMS_Utils.populateTwoColumnTextRow(items, index, cell, leftAttribute, rightAttribute, rightBulletAttribute)
    populateTextColumnsRow(items, index, cell, {
        {text = leftAttribute},
        {text = rightAttribute, bullet = rightBulletAttribute}
    })
end

---Two best colours of the value scales, the stage colours following
local SCALE_BEST = {0.12, 0.88, 0.0, 1.0}
local SCALE_GOOD = {0.3, 0.7, 0.0, 1.0}

local SERVICE_COLOR_LEVELS = {0.9, 0.5, 0.2, 0.001}

---Colours of a value scale, best band first
local TEXT_SCALE = { SCALE_BEST, SCALE_GOOD, RMS_Utils.COLOR.STAGE[2], RMS_Utils.COLOR.STAGE[3], RMS_Utils.COLOR.STAGE[4] }

---Colour between two colours, at a share of the way
local function mixColors(from, to, share)
    local mixed = {}
    for channel = 1, 4 do
        mixed[channel] = from[channel] + (to[channel] - from[channel]) * share
    end
    return mixed
end

---Colour of a value on a five colour scale cut by four limits
-- @param integer direction 1 when a higher value is better, -1 when a lower one is
local function getBandColor(scale, limits, direction, value, smooth)
    if direction * (value - limits[1]) >= 0 then
        return unpack(scale[1])
    end
    for band = 1, 3 do
        local top, bottom = limits[band], limits[band + 1]
        if direction * (value - bottom) >= 0 then
            local color = smooth and mixColors(scale[band], scale[band + 1], (top - value) / (top - bottom)) or scale[band + 1]
            return unpack(color)
        end
    end
    -- Past the last limit, the worst colour comes as far again
    local last = limits[4]
    local color = smooth and mixColors(scale[4], scale[5], math.min(1.0, direction * (last - value) / last)) or scale[5]
    return unpack(color)
end

---Returns the colour of a value against four descending thresholds
function RMS_Utils.getValueColor(value, ideal, high, mid, low, smooth)
    return getBandColor(TEXT_SCALE, { ideal, high, mid, low }, 1, value, smooth)
end

---Returns the colour of a gauge fill
function RMS_Utils.getGaugeColor(value, ideal, high, mid, low, smooth)
    local green = RMS_Utils.COLOR.HIGHLIGHT
    local STAGE = RMS_Utils.COLOR.STAGE
    return getBandColor({ green, green, STAGE[2], STAGE[3], STAGE[4] }, { ideal, high, mid, low }, 1, value, smooth)
end

---Returns the colour of a condition, grey while the inspection is incomplete
function RMS_Utils.getConditionColor(condition, isCompleteInspection)
    if isCompleteInspection == nil then
        return unpack(RMS_Utils.COLOR.TEXT_DIM)
    end
    local ideal, high, mid, low = unpack(RMS_Utils.CONDITION_LEVELS)
    return RMS_Utils.getValueColor(condition, ideal, high, mid, low, false)
end

---Builds the system and part rows from an inspection report.
function RMS_Utils.getConditionRows(vehicle, report, systems, isMeasured, isOutdated, openSystem)
    local partsReport, partsHours = RealisticMechanicalSystems.getPartsReport(vehicle)
    local systemParts = vehicle.spec_RealisticMechanicalSystems.systemParts
    local rows = {}
    for _, systemL10nKey in ipairs(RealisticMechanicalSystems.SYSTEMS_ORDER) do
        local systemKey = RMS_Utils.getSystemKey(RealisticMechanicalSystems.SYSTEMS, systemL10nKey)
        local systemData = systems[systemKey]
        if type(systemData) == "table" and systemData.enabled ~= false then
            local parts = partsReport ~= nil and systemParts ~= nil and systemParts[systemKey] or {}
            local isOpen = #parts > 0 and openSystem == systemKey
            table.insert(rows, {kind = "system", systemKey = systemKey, canOpen = #parts > 0, isOpen = isOpen,
                name = g_i18n:getText(RMS_Utils.getSystemLabel(vehicle, systemL10nKey)),
                condition = math.clamp(systemData.condition or 1, 0, 1), isMeasured = isMeasured, isOutdated = isOutdated})
            if isOpen then
                local partRows = {}
                local failed = partsReport.conditionData.activeBreakdowns or {}
                for _, partId in ipairs(parts) do
                    local wear = partsReport.conditionData.partWear[partId]
                    table.insert(partRows, {kind = "part", name = RMS_Utils.getBreakdownPartName(partId, vehicle),
                        condition = wear ~= nil and 1 - math.min(wear, 1) or nil, isFailed = wear ~= nil and failed[partId] ~= nil,
                        isWorn = wear ~= nil and RMS_Utils.getIsPartWorn(partId, wear)})
                end
                table.sort(partRows, function(a, b)
                    local rankA = a.condition == nil and 3 or a.isFailed and 0 or a.isWorn and 1 or 2
                    local rankB = b.condition == nil and 3 or b.isFailed and 0 or b.isWorn and 1 or 2
                    if rankA ~= rankB then
                        return rankA < rankB
                    end
                    if (a.condition or 0) ~= (b.condition or 0) then
                        return (a.condition or 0) < (b.condition or 0)
                    end
                    return a.name < b.name
                end)
                for _, partRow in ipairs(partRows) do
                    table.insert(rows, partRow)
                end
            end
        end
    end

    local footText = ""
    if partsReport == nil then
        footText = g_i18n:getText("rms_fleet_parts_need_complete")
    elseif partsReport ~= report then
        footText = string.format(g_i18n:getText("rms_fleet_parts_reading"), RMS_Utils.formatReportAge(partsHours))
    end
    return rows, footText
end

local function populateConditionSystemCell(cell, row)
    local nameElement, valueElement, gauge, rating = cell:getAttribute("name"), cell:getAttribute("value"), cell:getAttribute("gauge"),
        cell:getAttribute("rating")
    local triangle, track = cell:getAttribute("triangle"), cell:getAttribute("track")
    if cell.rmsNameWidth == nil then
        cell.rmsValueColor = {unpack(valueElement.textColor)}
        cell.rmsNameWidth = nameElement.size[1]
        cell.rmsRatingWidth = rating.size[1]
        cell.rmsRatingRight = rating.position[1] + rating.size[1]
        cell.rmsNameGap = 6 * g_pixelSizeScaledX
    end

    cell:getAttribute("band"):setVisible(row.isOpen)
    triangle:setVisible(row.canOpen)
    cell:getAttribute("dot"):setVisible(not row.canOpen)
    triangle:applyProfile(row.isOpen and "rms_fleetStateTriangleOpen" or "rms_fleetStateTriangle", true, true)
    triangle:setImageRotation(row.isOpen and -math.pi / 2 or 0)
    nameElement:applyProfile(row.isOpen and "rms_fleetSystemNameOpen" or "rms_fleetSystemName", true, true)
    track:setVisible(row.isMeasured)
    gauge:setVisible(row.isMeasured)
    valueElement:setVisible(row.isMeasured)
    rating:setVisible(not row.isMeasured)
    valueElement:setText(string.format("%d", math.floor(row.condition * 100 + 0.5)))
    valueElement:setTextColor(unpack(row.isOutdated and RMS_Utils.COLOR.TEXT_DIM or cell.rmsValueColor))
    gauge:setSize(track.size[1] * row.condition, nil)
    rating:setSize(cell.rmsRatingWidth, nil)
    rating:setText(RMS_Utils.formatCondition(row.condition, false))
    if row.isOutdated then
        gauge:setImageColor(nil, unpack(RMS_Utils.COLOR.TEXT_DIM))
        rating:setTextColor(unpack(RMS_Utils.COLOR.TEXT_DIM))
    else
        gauge:setImageColor(nil, RMS_Utils.getGaugeColor(row.condition * 100, 95, 80, 60, 40, true))
        rating:setTextColor(RMS_Utils.getConditionColor(row.condition, false))
    end

    local nameWidth = cell.rmsNameWidth
    if not row.isMeasured then
        nameWidth = cell.rmsRatingRight - rating:getTextWidth() - cell.rmsNameGap - nameElement.position[1]
    end
    nameElement:setSize(nameWidth, nil)
    nameElement:setText(row.name)
end

local function populateConditionPartCell(cell, row)
    local nameElement, stateElement, valueElement = cell:getAttribute("name"), cell:getAttribute("state"), cell:getAttribute("value")
    if cell.rmsStateRight == nil then
        cell.rmsValueColor = {unpack(valueElement.textColor)}
        cell.rmsStateWidth = stateElement.size[1]
        cell.rmsStateRight = stateElement.position[1] + cell.rmsStateWidth
        cell.rmsNameGap = 6 * g_pixelSizeScaledX
    end

    local stateText, color = "", cell.rmsValueColor
    if row.condition == nil then
        stateText, color = g_i18n:getText("rms_fleet_part_unmeasured"), RMS_Utils.COLOR.TEXT_DIM
    elseif row.isFailed then
        stateText, color = g_i18n:getText("rms_fleet_part_failed"), RMS_Utils.COLOR.ALERT
    elseif row.isWorn then
        stateText, color = g_i18n:getText("rms_fleet_part_worn"), RMS_Breakdowns.COLORS.WARNING
    end
    local stateRight = row.condition == nil and valueElement.position[1] + valueElement.size[1] or cell.rmsStateRight
    stateElement:setVisible(stateText ~= "")
    stateElement:setSize(cell.rmsStateWidth, nil)
    stateElement:setText(stateText)
    stateElement:setTextColor(unpack(color))
    local stateWidth = stateText ~= "" and stateElement:getTextWidth() or 0
    stateElement:setSize(stateWidth, nil)
    stateElement:setPosition(stateRight - stateWidth, nil)
    valueElement:setVisible(row.condition ~= nil)
    valueElement:setText(row.condition ~= nil and string.format("%d", math.floor(row.condition * 100 + 0.5)) or "")
    valueElement:setTextColor(unpack(color))

    local nameRight = stateText ~= "" and stateRight - stateWidth or valueElement.position[1]
    nameElement:setSize(math.max(nameRight - cell.rmsNameGap - nameElement.position[1], 0), nil)
    nameElement:setText(row.name)
end

---Fills a row of a condition card, a system or one of its parts
function RMS_Utils.populateConditionCell(cell, row)
    if row.kind == "system" then
        populateConditionSystemCell(cell, row)
    else
        populateConditionPartCell(cell, row)
    end
end

---Reloads a list, each shown row taking the template it now needs
function RMS_Utils.reloadListTemplates(list)
    for sectionIndex, section in pairs(list.sections) do
        local count = list.dataSource:getNumberOfItemsInSection(list, sectionIndex)
        for index, cell in pairs(section.cells) do
            if index > count or cell.reusableName ~= list.dataSource:getCellTypeForItemInSection(list, sectionIndex, index) then
                list:queueReusableCell(cell)
            end
        end
    end
    list:reloadData()
end

function RMS_Utils.getServiceColor(service, isCompleteInspection)
    if isCompleteInspection == nil then
        return unpack(RMS_Utils.COLOR.TEXT_DIM)
    end

    local ideal, high, mid, low = unpack(SERVICE_COLOR_LEVELS)
    return RMS_Utils.getValueColor(RMS_Utils.getServiceIntervalRemainingRatio(service), ideal, high, mid, low, isCompleteInspection)
end

---Returns the colour of a value against four ascending thresholds
function RMS_Utils.getValueColorInverted(value, ideal, low, mid, high, smooth)
    return getBandColor(TEXT_SCALE, { ideal, low, mid, high }, -1, value, smooth)
end

local SAVEGAME_OPTIONAL_FLOAT_SENTINEL = -1

---Converts a value to a boolean, strings and numbers accepted
function RMS_Utils.normalizeBoolValue(value, defaultValue)
    local kind = type(value)
    if kind == "nil" then
        return defaultValue == true
    elseif kind == "boolean" then
        return value
    elseif kind == "number" then
        return value ~= 0
    elseif kind == "string" then
        local word = BOOL_WORDS[string.lower(value)]
        if word ~= nil then
            return word
        end
    end
    -- Any other string or object counts as set
    return true
end


---Encodes a float that may be absent
function RMS_Utils.encodeOptionalFloat(value)
    return value ~= nil and tonumber(value) or SAVEGAME_OPTIONAL_FLOAT_SENTINEL
end

---Decodes a float that may be absent, negative meaning absent
function RMS_Utils.decodeOptionalFloat(value)
    local number = tonumber(value)
    if number ~= nil and not (number < 0) then
        return number
    end
    return nil
end

---Splits a comma separated string into its trimmed, non empty items
function RMS_Utils.parseCsvList(csvString)
    local items = {}
    for item in string.gmatch(csvString or "", "[^,]+") do
        local trimmed = string.match(item, "^%s*(.-)%s*$")
        if trimmed ~= "" then
            table.insert(items, trimmed)
        end
    end
    return items
end

---Writes the active effects as id|value, value empty if not a number
function RMS_Utils.serializeEffectSnapshot(effects)
    local entries = {}
    for effectId, effectData in pairs(effects or {}) do
        local id = effectId and tostring(effectId) or ""
        if id ~= "" then
            local value = type(effectData) == "table" and tonumber(effectData.value) or nil
            if type(effectData) == "number" then
                value = effectData
            end
            table.insert(entries, id .. "|" .. (value ~= nil and string.format("%.6f", value) or ""))
        end
    end
    return joinSaveEntries(entries)
end

---Reads effects from serializeEffectSnapshot, or a plain id list
function RMS_Utils.deserializeEffectSnapshot(serialized)
    local effects = {}
    if serialized == nil or serialized == "" then
        return effects
    end
    -- Older saves list the ids alone
    if string.find(serialized, "|", 1, true) == nil then
        for _, effectId in ipairs(RMS_Utils.parseCsvList(serialized)) do
            effects[effectId] = true
        end
        return effects
    end

    for entry in string.gmatch(serialized, "[^;]+") do
        local effectId, rawValue = string.match(entry, "([^|]+)|([^|]*)")
        if effectId ~= nil then
            local value = tonumber(rawValue)
            effects[effectId] = value ~= nil and { id = effectId, value = value } or true
        end
    end
    return effects
end

---Returns the system name behind a system key, in any case
function RMS_Utils.getSystemNameByKey(systems, systemKey)
    local wanted = string.lower(tostring(systemKey))
    for key, name in pairs(systems or {}) do
        if string.lower(tostring(key)) == wanted then
            return name
        end
    end
    return tostring(systemKey)
end

---Writes the condition and switch of every system
function RMS_Utils.serializeSystemsState(systems)
    local entries = {}
    for systemKey, systemData in pairs(systems or {}) do
        local condition, enabled = readSystemState(systemData)
        table.insert(entries, string.format("%s|%.6f|%d", tostring(systemKey), condition, toFlag(enabled)))
    end
    return joinSaveEntries(entries)
end

---Reads the systems written by serializeSystemsState, older saves too
function RMS_Utils.deserializeSystemsState(serialized)
    local systems = {}
    for _, entry in ipairs(splitSaveEntries(serialized)) do
        local fields = {}
        for field in string.gmatch(entry .. "|", "(.-)|") do
            table.insert(fields, field)
        end
        if fields[1] ~= "" then
            -- The switch ends the entry in both log formats
            local switch = #fields >= 3 and tonumber(fields[#fields]) or nil
            systems[fields[1]] = { condition = tonumber(fields[2]) or 1.0, enabled = RMS_Utils.normalizeBoolValue(switch, true) }
        end
    end
    return systems
end

---Copies the condition of every system for a later comparison
function RMS_Utils.createSystemsSnapshot(systems)
    local snapshot = {}
    for systemKey, systemData in pairs(systems or {}) do
        local condition, enabled = readSystemState(systemData)
        snapshot[systemKey] = { condition = condition, enabled = enabled }
    end
    return snapshot
end

---Writes a map of numbers as key|value entries
function RMS_Utils.serializeNumericMap(valueMap)
    local entries = {}
    for key, value in pairs(valueMap or {}) do
        local number = tonumber(value)
        if number ~= nil then
            table.insert(entries, string.format("%s|%.6f", tostring(key), number))
        end
    end
    return joinSaveEntries(entries)
end

---Reads a map written by serializeNumericMap, older saves too
function RMS_Utils.deserializeNumericMap(serialized)
    local values = {}
    for _, entry in ipairs(splitSaveEntries(serialized)) do
        local key, rawValue = string.match(entry, "([^|]+)|([^|]+)")
        local number = tonumber(rawValue)
        if key ~= nil and number ~= nil then
            values[key] = number
        end
    end
    return values
end

local ELECTRIC_SYSTEM_LABELS = {
    rms_spec_system_engine = "rms_spec_system_electric_motor",
    rms_spec_system_fuel = "rms_spec_system_traction_battery"
}

---Returns the text naming a system on a vehicle
function RMS_Utils.getSystemLabel(vehicle, textKey)
    if vehicle.spec_RealisticMechanicalSystems.isElectricVehicle then
        return ELECTRIC_SYSTEM_LABELS[textKey] or textKey
    end
    return textKey
end

---Returns the system key behind a system name
function RMS_Utils.getSystemKey(systems, systemName)
    local key = systems ~= nil and RMS_Utils.getKeyByValue(systems, systemName) or ""
    return string.lower(key)
end

---Turns a real price into the game's, scaled by the economic difficulty
function RMS_Utils.getGamePrice(realPrice)
    return realPrice * (EconomyManager.getCostMultiplier() / EconomyManager.COST_MULTIPLIER[EconomicDifficulty.NORMAL])
end

-- @param float workHours hours of work of a real machine
function RMS_Utils.getRemainingValueShare(vehicle, age, workHours)
    local C = RMS_Config.CORE.RESALE
    local className = C.PROFILE_CLASSES[RMS_Fluids.getProfileName(vehicle)]
    if className == nil then
        local power = RMS_Fluids.getEnginePower(vehicle)
        className = power < C.TRACTOR_MEDIUM_POWER and "TRACTOR_SMALL" or power <= C.TRACTOR_LARGE_POWER and "TRACTOR_MEDIUM" or "TRACTOR_LARGE"
    end
    local class = C.CLASSES[className]
    local years = math.max(age, workHours / class.hoursPerYear)
    local hoursPerYear = years > 0 and workHours / years or class.hoursPerYear
    local root = math.max(class.c1 - class.c2 * math.sqrt(years) - class.c3 * math.sqrt(hoursPerYear), 0)
    return math.min(root * root, C.NEW_SHARE)
end

function RMS_Utils.getMarketValue(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    local C = RMS_Config.CORE
    local R = RealisticMechanicalSystems
    local price = vehicle:getPrice()
    local hours = spec.realOperatingTime / 3600000
    local share = RMS_Utils.getRemainingValueShare(vehicle, vehicle.age / Environment.PERIODS_IN_YEAR,
        hours * C.BASE_SYSTEMS_WEAR * C.MACHINE_LIFE_HOURS)
    local repaintPrice = (RMS_Bodywork.getPrice(vehicle, RMS_Bodywork.FULL, R.WORKSHOP.DEALER) or 0)
        * math.sqrt(vehicle:getWearTotalAmount())
    local repairPrice = vehicle:getServicePrice(R.STATUS.REPAIR, R.REPAIR_TYPES.MEDIUM, R.PART_TYPES.OEM, R.WORKSHOP.DEALER, true)
    local overhaulPrice = vehicle:getServicePrice(R.STATUS.OVERHAUL, R.OVERHAUL_TYPES.FULL, nil, R.WORKSHOP.DEALER)
    local deduction = math.min(repairPrice + R.getCatchUpPrice(vehicle, hours), overhaulPrice)
    return math.max(price * share - deduction - repaintPrice, price * 0.03)
end

---Returns the resale payment of the menu or the dealer
function RMS_Utils.getResaleValue(vehicle, isDirectSell)
    if vehicle.propertyState ~= VehiclePropertyState.OWNED then
        return nil
    end
    local multiplier = isDirectSell and EconomyManager.DIRECT_SELL_MULTIPLIER or 1
    return math.min(math.floor(vehicle:getSellPrice() * multiplier), vehicle:getPrice())
end

---Hours of the hour meter, to the tenth, on any machine
-- @return float hours floored to the tenth, as Enterable:getFormattedOperatingTime
function RMS_Utils.getHourMeter(vehicle)
    return math.floor(vehicle:getOperatingTime() / 360000) / 10
end

---What a vehicle card lists: age, hours, distance or condition, value
-- @return table facts label, value and pictogram slice of each row, the odometer by its badge
function RMS_Utils.getVehicleFacts(vehicle, isTracked, isDirectSell)
    local third = { label = g_i18n:getText("rms_odometer_label"),
        value = RMS_Utils.formatOdometerKilometers(RMS_Utils.getOdometerKilometers(vehicle)), isOdometer = true }
    if not isTracked then
        -- a machine without wear, as a type without Wearable, stays as new
        local damage = vehicle.getDamageAmount ~= nil and vehicle:getDamageAmount() or 0
        third = { label = g_i18n:getText("rms_ws_label_condition"), value = string.format("%.0f%%", math.clamp(1 - damage, 0, 1) * 100),
            icon = "gui.storeAttribute_condition" }
    end
    local valueLabel, value = g_i18n:getText("rms_ws_label_value"), RMS_Utils.getResaleValue(vehicle, isDirectSell)
    if vehicle.propertyState == VehiclePropertyState.LEASED then
        valueLabel = g_i18n:getText("rms_ingame_menu_header_leasing_price")
        value = vehicle:getPrice() * (EconomyManager.DEFAULT_RUNNING_LEASING_FACTOR + EconomyManager.PER_DAY_LEASING_FACTOR)
    elseif isDirectSell and value ~= nil then
        valueLabel = string.format("%s (+%d%%)", valueLabel, math.floor((EconomyManager.DIRECT_SELL_MULTIPLIER - 1) * 100 + 0.5))
    end
    return {
        { label = g_i18n:getText("rms_ws_label_age"), value = string.format("%d %s", vehicle.age, g_i18n:getText("rms_ws_age_unit")),
            icon = "gui.icon_calendar" },
        { label = g_i18n:getText("rms_ws_label_operating_hours"), value = RMS_Utils.formatHours(RMS_Utils.getHourMeter(vehicle)),
            icon = "gui.storeAttribute_operatingHours" },
        third,
        { label = valueLabel, value = value ~= nil and g_i18n:formatMoney(value, 0, true, false) or "-", icon = RMS_Utils.getCurrencySlice() }
    }
end

-- slice width and height, larger side of its drawing, atlas pixels
RMS_Utils.ICON_DRAWINGS = {
    ["gui.icon_vehicleDealer_search"] = { 72, 72, 62 },
    ["gui.icon_ingameMenu_options"] = { 72, 72, 59 },
    ["gui.icon_vehicleDealer_machines"] = { 72, 72, 61 },
    ["gui.storeAttribute_power"] = { 36, 36, 34 },
    ["gui.contextAction_icon_repairAlert"] = { 64, 48, 39 },
    ["gui.contextAction_icon_repair"] = { 64, 48, 42 },
    ["gui.icon_construction_buildings"] = { 72, 72, 59 },
    ["gui.icon_calendar"] = { 48, 48, 37 },
    ["gui.icon_clock"] = { 48, 48, 34 },
    ["gui.icon_ingameMenu_statistics"] = { 72, 72, 58 },
    ["gui.storeAttribute_operatingHours"] = { 36, 36, 33 },
    ["gui.storeAttribute_condition"] = { 36, 36, 31 },
    ["ui_elements.currency_euro"] = { 48, 48, 38 },
    ["ui_elements.currency_dollar"] = { 48, 48, 38 },
    ["ui_elements.currency_pound"] = { 48, 48, 38 },
    ["rms_Hud.maintenance"] = { 72, 72, 59 },
    ["rms_WorkshopFluids.engineOil"] = { 128, 128, 111 },
    ["rms_Diagnostic.stethoscope"] = { 160, 160, 142 }
}
-- share of its slot the drawing fills
local ICON_FILL = 0.84
-- most stretch of a slice: 1.1 times on a 1440 px screen
local ICON_MAX_SCALE = 1.1 / 1440

---Fits a pictogram so its drawing fills its slot like the others
-- @param table element picture, its slot the size of its first fit
function RMS_Utils.fitIcon(element)
    local width, height, drawing = unpack(RMS_Utils.ICON_DRAWINGS[element.overlay.sliceId])
    element.rmsIconSlot = element.rmsIconSlot or element.size[2]
    local scale = math.min(ICON_FILL * element.rmsIconSlot / drawing, ICON_MAX_SCALE)
    local newWidth, newHeight = width * scale * g_screenHeight / g_screenWidth, height * scale
    -- the same centre, whatever the pivot
    element:setPosition(element.position[1] + (newWidth - element.size[1]) * (element.pivot[1] - 0.5),
        element.position[2] + (newHeight - element.size[2]) * (element.pivot[2] - 0.5))
    element:setSize(newWidth, newHeight)
end

---Writes the facts of a vehicle in rows cloned from one template
function RMS_Utils.writeVehicleFacts(rows, vehicle, isTracked, isDirectSell)
    for index, fact in ipairs(RMS_Utils.getVehicleFacts(vehicle, isTracked, isDirectSell)) do
        local row = rows[index]
        local icon = row:getDescendantByName("icon")
        -- the odometer reads by its badge, every other fact by its pictogram
        icon:setVisible(not fact.isOdometer)
        row:getDescendantByName("badge"):setVisible(fact.isOdometer == true)
        if not fact.isOdometer then
            icon:setImageSlice(nil, fact.icon)
        end
        RMS_Utils.writeRow(row, fact.label, fact.value)
    end
end

---Writes a row cloned from a template, its pill closed on the value
function RMS_Utils.writeRow(row, labelText, valueText)
    RMS_Utils.fitRowValue(row:getDescendantByName("label"), row:getDescendantByName("pill"), row:getDescendantByName("value"), labelText, valueText)
end

---Share of the machine a system weighs among its enabled systems
function RMS_Utils.getEffectiveSystemWeight(vehicle, systemName, systems)
    local spec = vehicle ~= nil and vehicle.spec_RealisticMechanicalSystems or nil
    if spec == nil or type(spec.systems) ~= "table" or type(systemName) ~= "string" then
        return 0
    end

    local systemKey = resolveVehicleSystemKey(spec.systems, systemName, systems)
    local systemData = spec.systems[systemKey]
    local weight = systemData ~= nil and getIsSystemOn(systemData) and getConfiguredSystemWeight(systemKey) or 0
    if weight <= 0 then
        return 0
    end

    local total = 0
    for key, data in pairs(spec.systems) do
        if getIsSystemOn(data) then
            total = total + getConfiguredSystemWeight(key)
        end
    end
    return total > 0 and weight / total or 0
end

---Returns the enabled systems whose condition permits an overhaul
function RMS_Utils.getEligibleOverhaulSystems(vehicle)
    local values = {}
    for _, systemName in ipairs(RMS_Utils.getOverhaulSystems(vehicle)) do
        local systemData = vehicle.spec_RealisticMechanicalSystems.systems[RMS_Utils.getSystemKey(RealisticMechanicalSystems.SYSTEMS, systemName)]
        if (tonumber(systemData.condition) or 1.0) < 0.5 then
            values[#values + 1] = systemName
        end
    end
    return values
end

---Returns the systems an overhaul works on
function RMS_Utils.getOverhaulSystems(vehicle)
    local values = {}
    local spec = vehicle ~= nil and vehicle.spec_RealisticMechanicalSystems or nil
    if spec == nil or type(spec.systems) ~= "table" then
        return values
    end

    for _, systemName in ipairs(RealisticMechanicalSystems.SYSTEMS_ORDER) do
        local systemData = spec.systems[RMS_Utils.getSystemKey(RealisticMechanicalSystems.SYSTEMS, systemName)]
        if type(systemData) == "table" and systemData.enabled ~= false
            and RMS_Utils.getEffectiveSystemWeight(vehicle, systemName, RealisticMechanicalSystems.SYSTEMS) > 0 then
            values[#values + 1] = systemName
        end
    end
    return values
end

---Copies the entries of a table, an empty table for anything else
function RMS_Utils.shallowCopy(original)
    local copy = {}
    if type(original) == "table" then
        for key, value in pairs(original) do
            copy[key] = value
        end
    end
    return copy
end

---Copies a value and every table it reaches, a shared table copied once
function RMS_Utils.deepCopy(original, seen)
    if type(original) ~= "table" then
        return original
    end
    seen = seen or {}
    local copy = seen[original]
    if copy == nil then
        copy = {}
        seen[original] = copy
        for key, value in pairs(original) do
            copy[RMS_Utils.deepCopy(key, seen)] = RMS_Utils.deepCopy(value, seen)
        end
    end
    return copy
end

---Serializes invoice lines into a string
-- @return string serialized kind, key, mode, liters and price of each line
function RMS_Utils.serializeInvoice(invoice)
    local lines = {}
    for _, line in ipairs(invoice or {}) do
        lines[#lines + 1] = string.format("%s,%s,%s,%.6f,%.4f,%s", tostring(line.kind or ""), tostring(line.key or ""),
            tostring(line.mode or ""), tonumber(line.liters) or 0, tonumber(line.price) or 0, line.warrantyReason or "")
    end
    return table.concat(lines, ";")
end

---Rebuilds invoice lines from their serialized form
function RMS_Utils.deserializeInvoice(serialized)
    if serialized == nil or serialized == "" then
        return nil
    end

    local invoice = {}
    for value in string.gmatch(serialized, "[^;]+") do
        local kind, key, mode, liters, price, warrantyReason = string.match(value, "^([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),?([^,]*)$")
        if kind ~= nil and kind ~= "" then
            table.insert(invoice, {
                kind = kind,
                key = key,
                mode = mode ~= "" and mode or nil,
                liters = tonumber(liters) or 0,
                price = tonumber(price) or 0,
                warrantyReason = warrantyReason ~= "" and warrantyReason or nil
            })
        end
    end
    return invoice
end

---Serializes one maintenance log entry into a string
function RMS_Utils.serializeMaintenanceLogEntry(entry)
    if entry == nil then
        return ""
    end
    local fields = {}
    for index, field in ipairs(LOG_ENTRY_FIELDS) do
        fields[index] = field.write(entry, entry.conditionData or {})
    end
    return table.concat(fields, "|")
end

---Rebuilds a maintenance log entry from its serialized form
function RMS_Utils.deserializeMaintenanceLogEntry(serialized)
    if serialized == nil or serialized == "" then
        return nil
    end
    local fields = {}
    for field in string.gmatch(serialized .. "|", "(.-)|") do
        table.insert(fields, field)
    end
    -- Ten fields at least, those of the first log format
    if #fields < 10 then
        return nil
    end

    local entry = { conditionData = {} }
    for index, field in ipairs(LOG_ENTRY_FIELDS) do
        if field.read ~= nil then
            field.read(entry, entry.conditionData, fields[index])
        end
    end
    return entry
end

---Tells whether the CVT addon mod drives the transmission of this vehicle
function RMS_Utils.hasCVTAddon(vehicle)
    local addon = vehicle ~= nil and vehicle.spec_CVTaddon or nil
    if addon == nil or not addon.CVTcfgExists then
        return false
    end
    -- 0 and 8: the addon leaves the transmission alone
    local config = tonumber(addon.CVTconfig) or 0
    return config ~= 0 and config ~= 8
end

---Tells whether the vehicle runs a continuously variable transmission
function RMS_Utils.hasCVTTransmission(vehicle)
    if vehicle == nil or vehicle.getMotor == nil then
        return false
    end
    local motor = vehicle:getMotor()
    return motor ~= nil and motor.minForwardGearRatio ~= nil and not RMS_Utils.getIsElectricVehicle(vehicle)
end

---Tells whether the vehicle runs on electricity alone
function RMS_Utils.getIsElectricVehicle(vehicle)
    local motorized = vehicle.spec_motorized
    local isElectric = false
    for _, consumer in pairs(motorized ~= nil and motorized.consumers or {}) do
        local fillType = consumer.fillType
        if fillType == FillType.DIESEL or fillType == FillType.METHANE then
            return false
        end
        isElectric = isElectric or fillType == FillType.ELECTRICCHARGE
    end
    return isElectric
end

---Tells whether an engine uses the shared ECU profile
function RMS_Utils.getUsesEngineECUProfile(vehicle)
    local spec = vehicle ~= nil and vehicle.spec_RealisticMechanicalSystems or nil
    if spec == nil or RMS_Utils.getIsElectricVehicle(vehicle) then
        return false
    end

    local motorized = vehicle.spec_motorized
    local consumers = motorized ~= nil and motorized.consumersByFillTypeName or nil
    return (consumers ~= nil and consumers.DEF ~= nil)
        or (spec.yearIsKnown == true and (tonumber(spec.year) or 0) >= 2000)
end

---Returns the fan drive type for the machine's generation
function RMS_Utils.getFanDrive(vehicle)
    if RMS_Utils.getIsElectricVehicle(vehicle) then
        return "ELECTRIC"
    end
    local years = RMS_Config.THERMAL.FAN_DRIVE_YEARS
    local year = vehicle.spec_RealisticMechanicalSystems.year
    if year >= years.ELECTRONIC then
        return "ELECTRONIC"
    elseif year >= years.VISCOUS then
        return "VISCOUS"
    end
    return "DIRECT"
end

---Returns the power to mass levels of a heavy load
function RMS_Utils.getHeavyTrailerRatioLevels(vehicle)
    local C = RMS_Config.CORE.TRANSMISSION_FACTOR_DATA
    if vehicle.spec_RealisticMechanicalSystems.isTruck then
        return C.HEAVY_TRAILER_TRUCK_MASS_RATIO_THRESHOLD, C.HEAVY_TRAILER_TRUCK_MASS_RATIO_FULL_EFFECT
    end
    local powerPerOwnMass = vehicle:getMotor().peakMotorPower * 1.36 / math.max(vehicle:getTotalMass(true), 0.01)
    return powerPerOwnMass / C.HEAVY_TRAILER_MASS_RATIO_THRESHOLD, powerPerOwnMass / C.HEAVY_TRAILER_MASS_RATIO_FULL_EFFECT
end

---Builds a logger printing only while debug mode is on
function RMS_Utils.createLogger(prefix)
    return function(...)
        if not RMS_Config.DEBUG then
            return
        end
        local words = { prefix }
        for index = 1, select("#", ...) do
            words[index + 1] = tostring((select(index, ...)))
        end
        print(table.concat(words, " "))
    end
end

---Resolves a system name typed in the console to the key used by the spec
function RMS_Utils.resolveConsoleSystemKey(spec, rawSystem)
    if rawSystem == nil or rawSystem == "" then
        return nil
    end

    local normalized = string.lower(rawSystem)
    for key, _ in pairs(spec.systems or {}) do
        if string.lower(tostring(key)) == normalized then
            return key
        end
    end

    return false
end


local function fitPill(pill, value, anchor, label)
    -- the boxes the XML declares, read before the first fit moves them
    if pill.rmsPillBox == nil then
        pill.rmsPillBox = { x = pill.position[1], width = pill.size[1], padding = value.position[1] - pill.position[1],
            labelGap = label ~= nil and pill.position[1] - label.position[1] - label.size[1] or nil }
    end
    local box = pill.rmsPillBox
    local function close(width)
        local x = anchor == "center" and box.x + (box.width - width) / 2 or box.x + box.width - width
        pill:setPosition(x, nil)
        pill:setSize(width, nil)
        -- a scrolling text divides by its width each time it moves
        value:setSize(width - box.padding * 2, nil)
        value:setPosition(x + box.padding, nil)
    end
    -- a hair over the text, else the game takes a smaller size
    local function getClosedWidth()
        return math.min(box.width, value:getTextWidth(true) * 1.001 + box.padding * 2)
    end

    close(box.width)
    close(getClosedWidth())
    if label == nil then
        return
    end
    -- while the label stays cut, the value drops one size step
    while true do
        label:setSize(pill.position[1] - box.labelGap - label.position[1], nil)
        local size = value.textSize
        if label.text == label.sourceText or size - value.defaultTextSize * 0.05 <= value.textMinSize then
            return
        end
        -- a box a hair narrower makes the game take its next size
        value:setSize(value:getTextWidth(true) * 0.999, nil)
        if value.textSize >= size then
            return
        end
        close(getClosedWidth())
    end
end

---Writes a value into its pill and closes the pill on it
function RMS_Utils.fitValuePill(pill, value, anchor, valueText)
    value:setText(valueText)
    fitPill(pill, value, anchor)
end

---Writes a row, label and value, and fits its pill
function RMS_Utils.fitRowValue(label, pill, value, labelText, valueText)
    label:setText(labelText)
    value:setText(valueText)
    fitPill(pill, value, nil, label)
end

---Fits every pill of a screen on the value written after it
function RMS_Utils.fitValuePills(element)
    local children = element.elements
    for index, child in ipairs(children) do
        RMS_Utils.fitValuePills(child)
        -- a pill declares its anchor in its profile, its value follows it
        local anchor = g_gui:getProfile(child.profile):getValue("rmsPillAnchor")
        if anchor ~= nil then
            -- the label is the text before a right pill, ending before it
            local label = children[index - 1]
            if anchor ~= "right" or label == nil or label.sourceText == nil
                or label.position[1] + label.size[1] > child.position[1] then
                label = nil
            end
            fitPill(child, children[index + 1], anchor, label)
        end
    end
end

RMS_Utils.SCROLL_SPEED = 0.5

local function updateScrollingText(element, dt)
    TextElement.update(element, dt * RMS_Utils.SCROLL_SPEED)
end

local function updateScrollingTextPosition(element)
    TextElement.updateAbsolutePosition(element)
    -- Rewind the native offset without advancing its retained clock.
    TextElement.update(element, 0)
end

---Puts every scrolling text of a branch on the shared speed, cells included
function RMS_Utils.applyScrollSpeed(element)
    if element.textLayoutMode == TextElement.LAYOUT_MODE.SCROLLING then
        element.update = updateScrollingText
        element.updateAbsolutePosition = updateScrollingTextPosition
    end

    for _, child in ipairs(element.elements) do
        RMS_Utils.applyScrollSpeed(child)
    end
end

---Resets scrolling text elements in a GUI branch to the start of their text
function RMS_Utils.resetScrollingTexts(element)
    if element == nil then
        return
    end

    if element.textLayoutMode == TextElement.LAYOUT_MODE.SCROLLING then
        element.scrollTime = 0
        element:updateScrollingParameters()
    end

    for _, child in ipairs(element.elements or {}) do
        RMS_Utils.resetScrollingTexts(child)
    end
end


---Centers the icon and the label of an action button as one block
function RMS_Utils.centerActionContent(button)
    if button.rmsActionBox == nil then
        local iconElement
        for _, child in ipairs(button.elements) do
            if type(child.profile) == "string" and child.profile:find("Icon") ~= nil then
                iconElement = child
            end
        end

        if iconElement == nil then
            return
        end

        button.rmsActionBox = {
            icon = iconElement,
            width = iconElement.size[1],
            gap = button.textOffset[1] - iconElement.position[1] - iconElement.size[1]
        }
    end

    local box = button.rmsActionBox
    local startX = math.max((button.size[1] - (box.width + box.gap + button:getTextWidth(true))) * 0.5, 0)

    box.icon:setPosition(startX, nil)
    button.textOffset[1] = startX + box.width + box.gap
end


---Fits a row without a pill: the value keeps its right edge
function RMS_Utils.fitRowText(labelElement, valueElement, labelText, valueText)
    if valueElement.rmsRowTextBox == nil then
        valueElement.rmsRowTextBox = {
            labelX = labelElement.position[1],
            valueRight = valueElement.position[1] + valueElement.size[1],
            gap = valueElement.position[1] - labelElement.position[1] - labelElement.size[1]
        }
    end

    local box = valueElement.rmsRowTextBox
    valueElement:setPosition(box.labelX, nil)
    valueElement:setSize(box.valueRight - box.labelX, nil)
    valueElement:setText(valueText)

    local width = math.min(box.valueRight - box.labelX - box.gap, valueElement:getTextWidth(true))
    valueElement:setPosition(box.valueRight - width, nil)
    valueElement:setSize(width, nil)
    labelElement:setSize(math.max(box.valueRight - width - box.gap - box.labelX, 0), nil)
    labelElement:setText(labelText)
end


function RMS_Utils.mirrorSelectionToChildren(element)
    for _, child in ipairs(element.elements) do
        child.getIsSelected = function()
            return element:getIsSelected()
        end
    end
end


local function getFocusColumnEntry(rows, rowIndex, isFromRight)
    if rows == nil then
        return nil
    end

    local row = rows[math.min(rowIndex, #rows)]
    return isFromRight and row[#row] or row[1]
end

---Links the focus over what a screen shows
function RMS_Utils.linkFocusColumns(top, columns, preferred)
    local shown = {}
    for _, column in ipairs(columns) do
        local rows = {}
        for _, row in ipairs(column) do
            local elements = {}
            for _, element in ipairs(row) do
                if element:getIsVisible() then
                    table.insert(elements, element)
                end
            end
            if #elements > 0 then
                table.insert(rows, elements)
            end
        end
        if #rows > 0 then
            table.insert(shown, rows)
        end
    end

    local first
    for columnIndex, rows in ipairs(shown) do
        for rowIndex, row in ipairs(rows) do
            local above, below = rows[rowIndex - 1], rows[rowIndex + 1]
            for index, element in ipairs(row) do
                FocusManager:linkElements(element, FocusManager.TOP, above ~= nil and above[math.min(index, #above)] or top)
                FocusManager:linkElements(element, FocusManager.BOTTOM, below ~= nil and below[math.min(index, #below)] or nil)
                FocusManager:linkElements(element, FocusManager.LEFT, row[index - 1] or getFocusColumnEntry(shown[columnIndex - 1], rowIndex, true))
                FocusManager:linkElements(element, FocusManager.RIGHT, row[index + 1] or getFocusColumnEntry(shown[columnIndex + 1], rowIndex, false))
                if first == nil and element:canReceiveFocus() then
                    first = element
                end
            end
        end
    end

    local entry = first or top
    if preferred ~= nil and preferred:getIsVisible() and preferred:canReceiveFocus() then
        entry = preferred
    end
    -- a screen opening on its top element leads down to its first one
    if top ~= nil then
        FocusManager:linkElements(top, FocusManager.TOP, nil)
        FocusManager:linkElements(top, FocusManager.BOTTOM, entry ~= top and entry or first)
    end
    return entry
end

---Registers a cloned branch in the focus, each element with a new id
function RMS_Utils.registerFocus(element)
    -- a clone carries the focus ids of its source, which the manager skips
    element.focusId = nil
    for _, child in ipairs(element:getDescendants()) do
        child.focusId = nil
    end
    FocusManager:loadElementFromCustomValues(element)
end

---Puts a screen in its own focus, the frames placed in it included
function RMS_Utils.registerScreenFocus(screen)
    -- the manager focuses what a controller of the screen's name targets
    for _, element in ipairs(screen:getDescendants()) do
        if element:isa(FrameElement) then
            element.name = screen.name
        end
    end
    FocusManager:setGui(screen.name)
    RMS_Utils.registerFocus(screen)
end

---Hands the focus to an element when what held it is no longer shown
function RMS_Utils.keepFocusShown(entry)
    local focused = FocusManager:getFocusedElement()
    if entry ~= nil and (focused == nil or not focused:getIsVisible()) then
        FocusManager:setFocus(entry)
    end
end

local CURRENCY_SLICES = {
    [GS_MONEY_EURO] = "ui_elements.currency_euro",
    [GS_MONEY_DOLLAR] = "ui_elements.currency_dollar",
    [GS_MONEY_POUND] = "ui_elements.currency_pound"
}

---Returns the slice of the glyph of the money unit the player set
function RMS_Utils.getCurrencySlice()
    return CURRENCY_SLICES[g_gameSettings:getValue("moneyUnit")]
end

---Shows the glyph of the money unit the player set
function RMS_Utils.setCurrencyIcon(element)
    element:setImageSlice(nil, RMS_Utils.getCurrencySlice())
end

---Writes the picture, the brand and the model of a vehicle
function RMS_Utils.setVehicleIdentity(vehicle, imageElement, brandElement, modelElement)
    imageElement:setImageFilename(vehicle:getImageFilename())
    local brand = g_brandManager:getBrandByIndex(vehicle:getBrand())
    brandElement:setText(brand.name ~= "NONE" and brand.title or "")
    modelElement:setText(vehicle:getName())
end

---What the last inspection report reads, as the workshop shows it
function RMS_Utils.getInspectionReading(vehicle)
    local reportHours, isOutdated = vehicle:getInspectionReportAge()
    local service, isServiceComplete = vehicle:getLastInspectedService()
    local condition, isConditionComplete = vehicle:getLastInspectedCondition()
    return {
        isOutdated = isOutdated,
        ageText = RMS_Utils.formatReportAge(reportHours),
        serviceText = RMS_Utils.formatService(service, isServiceComplete),
        serviceColor = isOutdated and RMS_Utils.COLOR.TEXT_DIM or { RMS_Utils.getServiceColor(service, isServiceComplete) },
        serviceRatio = RMS_Utils.getServiceRingRatio(service, isServiceComplete),
        conditionText = RMS_Utils.formatCondition(condition, isConditionComplete),
        conditionColor = isOutdated and RMS_Utils.COLOR.TEXT_DIM or { RMS_Utils.getConditionColor(condition, isConditionComplete) },
        conditionRatio = RMS_Utils.getConditionRingRatio(condition, isConditionComplete)
    }
end

---Shows a separator of a button bar only between two shown buttons
function RMS_Utils.showButtonSeparators(box)
    local separator
    local hasButtonBefore = false
    for _, element in ipairs(box.elements) do
        if element.profile == "fs25_dialogButtonBoxSeparator" then
            element:setVisible(false)
            separator = hasButtonBefore and element or separator
        elseif element:getIsVisible() then
            if separator ~= nil then
                separator:setVisible(true)
            end
            separator, hasButtonBefore = nil, true
        end
    end
    box:invalidateLayout()
end
