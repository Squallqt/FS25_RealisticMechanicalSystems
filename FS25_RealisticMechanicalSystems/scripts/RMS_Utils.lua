-- Copyright © 2026 Squallqt. All rights reserved.

---Shared RMS utilities
RMS_Utils = {}
---Returns 1 for a set flag, 0 for an unset one
-- @param any value flag
-- @return integer flag 1 or 0
local function toFlag(value)
    return value and 1 or 0
end

---Returns a whole, non negative count read from a number or a string
-- @param any value number or string
-- @return integer count count
local function toCount(value)
    return math.max(math.floor(tonumber(value) or 0), 0)
end

-- fields of a saved breakdown: eight always, five added since
local BREAKDOWN_ENTRY_PATTERN = string.rep("([^,]+),", 7) .. "([^,]+)" .. string.rep(",?([^,]*)", 5)

---Returns the unit text of a count, singular for one
-- @param integer count count
-- @param string singular l10n key of the singular
-- @param string plural l10n key of the plural
-- @return string text unit
local function getCountUnit(count, singular, plural)
    return g_i18n:getText(count == 1 and singular or plural)
end

---Formats a ratio as a whole percentage
-- @param float ratio ratio
-- @return string text percentage
local function formatPercent(ratio)
    return string.format("%.0f%%", ratio * 100)
end

---Returns the tier of a value against descending levels, 1 at or above the first
-- @param table levels descending levels
-- @param float value value
-- @return integer tier tier
local function getLevelTier(levels, value)
    for tier, level in ipairs(levels) do
        if value >= level then
            return tier
        end
    end
    return #levels + 1
end

---Returns the entries of a save field sorted and joined by semicolons
-- @param table entries entries
-- @return string serialized entries joined
local function joinSaveEntries(entries)
    table.sort(entries)
    return table.concat(entries, ";")
end

---Returns the entries of a save field
-- @param string serialized save field
-- @return table entries entries
local function splitSaveEntries(serialized)
    local entries = {}
    for entry in string.gmatch(serialized, "[^;]+") do
        table.insert(entries, entry)
    end
    return entries
end

---Returns the key of the vehicle's systems behind a system name or enum key
-- @param table vehicleSystems systems of the vehicle
-- @param string name system name or enum key
-- @param table systems system names by enum key
-- @return string key key of the system
local function resolveVehicleSystemKey(vehicleSystems, name, systems)
    if vehicleSystems[name] ~= nil then
        return name
    end
    local lowered = string.lower(name)
    if type(systems[string.upper(name)]) == "string" and vehicleSystems[lowered] ~= nil then
        return lowered
    end
    local enumKey = RMS_Utils.getKeyByValue(systems, name)
    if type(enumKey) == "string" and vehicleSystems[string.lower(enumKey)] ~= nil then
        return string.lower(enumKey)
    end
    for key in pairs(vehicleSystems) do
        if string.lower(tostring(key)) == lowered then
            return key
        end
    end
    return lowered
end

---Returns a log field of the entry itself, saved as text
-- @param string key field of the entry
-- @param string? default value when missing
-- @return table field write and read of the field
local function entryText(key, default)
    return {
        write = function(entry) return tostring(entry[key] or default) end,
        read = function(entry, _, raw) entry[key] = raw ~= "" and raw or default end
    }
end

---Returns a log field of the entry itself, saved as a number
-- @param string key field of the entry
-- @param float? default value when missing
-- @return table field write and read of the field
local function entryNumber(key, default)
    return {
        write = function(entry) return tostring(entry[key] or default) end,
        read = function(entry, _, raw) entry[key] = tonumber(raw) or default end
    }
end

---Returns a log field of the entry itself, saved as a boolean
-- @param string key field of the entry
-- @param boolean default value when missing
-- @return table field write and read of the field
local function entryFlag(key, default)
    return {
        write = function(entry) return tostring(RMS_Utils.normalizeBoolValue(entry[key], default)) end,
        read = function(entry, _, raw) entry[key] = RMS_Utils.normalizeBoolValue(raw, default) end
    }
end

---Returns a log field of the condition data, saved as a number
-- @param string key field of the condition data
-- @param float? default value when missing, none keeps it empty
-- @return table field write and read of the field
local function conditionNumber(key, default)
    return {
        write = function(_, data) return tostring(data[key] or default or "") end,
        read = function(_, data, raw) data[key] = tonumber(raw) or default end
    }
end

---Returns a log field of the condition data, saved as escaped text
-- @param string key field of the condition data
-- @param function serialize writes the value as text
-- @param function deserialize reads the value from text
-- @return table field write and read of the field
local function conditionEncoded(key, serialize, deserialize)
    return {
        write = function(_, data) return RMS_Utils.encodeDelimitedString(serialize(data[key])) end,
        read = function(_, data, raw) data[key] = deserialize(RMS_Utils.decodeDelimitedString(raw)) end
    }
end

-- fields of a maintenance log entry, in their saved order
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
        function(breakdowns) return RMS_Utils.serializeBreakdowns(breakdowns) end,
        function(text) return RMS_Utils.deserializeBreakdowns(text) end),
    conditionEncoded("selectedBreakdowns",
        function(ids) return table.concat(ids, ",") end,
        function(text) return RMS_Utils.parseCsvList(text) end),
    conditionEncoded("activeIndicators",
        function(indicators)
            local ids = {}
            for id in pairs(indicators) do
                table.insert(ids, tostring(id))
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
        read = function(entry, _, raw) entry.invoice = RMS_Utils.deserializeInvoice(RMS_Utils.decodeDelimitedString(raw)) end
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
-- @param table? vehicle vehicle
-- @return table? container container locked
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
-- @param float dt time of the frame (ms)
-- @param float meanTimeInMinutes mean time between events (min)
-- @return float chance chance of the frame
function RMS_Utils.getChancePerFrameFromMeanTime(dt, meanTimeInMinutes)
    if meanTimeInMinutes <= 0 then
        return 1.0
    end
    return dt / (meanTimeInMinutes * 60000)
end

---Tells whether the vehicle drives a PTO output
-- @param table vehicle vehicle
-- @return boolean hasOutput true with an output
function RMS_Utils.hasPtoOutputCapability(vehicle)
    local ptoSpec = vehicle ~= nil and vehicle.spec_powerTakeOffs or nil
    if ptoSpec == nil or type(ptoSpec.outputPowerTakeOffs) ~= "table" then
        return false
    end

    return next(ptoSpec.outputPowerTakeOffs) ~= nil
end

local GRAIN_HEADER_DRIVE_RPM = 490
local FORAGE_HEADER_DRIVE_RPM = { maize = 400, direct = 750, pickup = 595 }
local ptoDisplayProfiles = setmetatable({}, { __mode = "k" })

---Tells whether the vehicle drives its mowers
-- @param table vehicle vehicle
-- @return boolean isMower true for a self-propelled mower
function RMS_Utils.getIsSelfPropelledMower(vehicle)
    return vehicle.typeName == "selfPropelledMower"
end

---Tells whether the PTO system wears
-- @param table vehicle vehicle
-- @return boolean isWearable true when it wears
function RMS_Utils.getHasWearablePto(vehicle)
    return RMS_Utils.hasPtoOutputCapability(vehicle) and not RMS_Utils.getIsSelfPropelledMower(vehicle)
        and (vehicle.spec_combine == nil or RMS_Drivetrain.getHarvestKind(vehicle) == nil)
end

---Returns the nominal speed of a forage header
-- @param table cutter header
-- @return float? rpm nominal speed (rpm)
local function getForageHeaderDriveRpm(cutter)
    local workArea = cutter.spec_workArea
    for _, area in ipairs(workArea ~= nil and workArea.workAreas or {}) do
        if area.functionName == "processPickupCutterArea" then
            return FORAGE_HEADER_DRIVE_RPM.pickup
        end
    end
    local spec = cutter.spec_cutter
    if spec.fruitTypeIndices ~= nil then
        local maize = g_fruitTypeManager:getFruitTypeByName("MAIZE")
        if maize ~= nil and table.hasElement(spec.fruitTypeIndices, maize.index) then
            return FORAGE_HEADER_DRIVE_RPM.maize
        end
        if spec.allowsForageGrowthState then
            return FORAGE_HEADER_DRIVE_RPM.direct
        end
    end
    return nil
end

---Returns the fixed properties of the PTO display
-- @param table vehicle vehicle
-- @return table profile properties of the display
local function getPtoDisplayProfile(vehicle)
    local profile = ptoDisplayProfiles[vehicle]
    if profile == nil then
        local kind = vehicle.spec_combine ~= nil and RMS_Drivetrain.getHarvestKind(vehicle) or nil
        profile = { kind = kind, mower = RMS_Utils.getIsSelfPropelledMower(vehicle) }
        if kind == "grain" then
            profile.headerRpm = vehicle.spec_cutter == nil and GRAIN_HEADER_DRIVE_RPM or nil
        elseif vehicle.spec_cutter ~= nil then
            profile.headerRpm = getForageHeaderDriveRpm(vehicle)
        end
        ptoDisplayProfiles[vehicle] = profile
    end
    return profile
end

---Tells whether the dashboard has a screen
-- @param table vehicle vehicle
-- @return boolean hasScreen true with a screen
function RMS_Utils.getHasDashboardScreen(vehicle)
    return vehicle.spec_RealisticMechanicalSystems.isElectricVehicle or RMS_Utils.getUsesEngineECUProfile(vehicle)
end

---Returns the attached combine module that drives a header
-- @param table vehicle vehicle
-- @return table? module combine module
local function getAttachedCombineDrive(vehicle)
    local joints = vehicle.spec_attacherJoints
    if joints ~= nil then
        for _, implement in ipairs(joints.attachedImplements) do
            local object = implement.object
            if object ~= nil and object.spec_combine ~= nil and object.spec_motorized == nil
                and RMS_Utils.hasPtoOutputCapability(object) then
                return object
            end
        end
    end
    return nil
end

---Tells whether the vehicle shows a PTO reading
-- @param table vehicle vehicle
-- @return boolean hasDisplay true with a reading
function RMS_Utils.getHasPtoDisplay(vehicle)
    local profile = getPtoDisplayProfile(vehicle)
    return profile.kind == "grain" or profile.kind == "forage" or profile.mower or RMS_Utils.hasPtoOutputCapability(vehicle)
        or getAttachedCombineDrive(vehicle) ~= nil
end

---Returns the reading of the connected PTO chain
-- @param table vehicle vehicle
-- @param table profile properties of the display
-- @return boolean active the shaft is turning
-- @return float? rpm speed shown (rpm), nil when no turning implement gives one
local function getConnectedPtoDisplay(vehicle, profile)
    local active, rpm = false, nil
    local outputs = vehicle.spec_powerTakeOffs ~= nil and vehicle.spec_powerTakeOffs.outputPowerTakeOffs or nil
    for _, output in ipairs(outputs or {}) do
        local tool = output.connectedVehicle
        if output.connectedInput ~= nil then
            if profile.front == nil then
                profile.front = RMS_Utils.getFrontPtoOutput(vehicle, true) or false
            end
            local rating, family = RMS_Greasing.getImplementPtoRating(tool, output == profile.front)
            local isTurning = output.isActive == true
            if family == "ptoPassThrough" then
                isTurning, rating = getConnectedPtoDisplay(tool, getPtoDisplayProfile(tool))
            else
                isTurning = tool.isActive and tool:getIsPowerTakeOffActive()
            end
            if isTurning then
                active = true
                if rating ~= nil then
                    rpm = math.max(rpm or 0, rating)
                end
            end
        end
    end
    return active, not active and 0 or rpm
end

---Returns the running state and the nominal tool speed
-- @param table vehicle vehicle
-- @return boolean active the shaft is turning
-- @return float? rpm nil when no rating is available
function RMS_Utils.getPtoDisplay(vehicle)
    local profile = getPtoDisplayProfile(vehicle)
    local isHeader = profile.kind == "grain" or profile.kind == "forage"
    local nominal = profile.headerRpm
    local isMotorStarted = vehicle:getIsMotorStarted()
    if profile.mower or profile.kind == "grain" and vehicle.spec_cutter ~= nil then
        local active = isMotorStarted and vehicle:getIsTurnedOn()
        return active, not active and 0 or nominal
    end
    if isHeader then
        local active, rpm = false, nil
        for cutter in pairs(vehicle.spec_combine.attachedCutters) do
            local rating = nominal
            if profile.kind == "forage" then
                rating = getPtoDisplayProfile(cutter).headerRpm
            end
            if isMotorStarted and cutter.getIsTurnedOn ~= nil and cutter:getIsTurnedOn() then
                active = true
                if rating ~= nil then
                    rpm = math.max(rpm or 0, rating)
                end
            end
        end
        if active then
            return true, rpm
        end
        return false, 0
    end
    if not isMotorStarted then
        return false, 0
    end
    local module = getAttachedCombineDrive(vehicle)
    if module ~= nil then
        return getConnectedPtoDisplay(module, getPtoDisplayProfile(module))
    end
    return getConnectedPtoDisplay(vehicle, profile)
end

---Tells whether an attacher joint lifts hydraulically
-- @param table jointDesc attacher joint
-- @return boolean isLift true for a hydraulic lift
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
-- @param table vehicle vehicle
-- @return boolean hasLift true when it can
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
-- @param table vehicle vehicle
-- @return boolean hasActuator true with one
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

---Tells whether a hose entry is hydraulic
-- @param any entry hose entry
-- @return boolean isHydraulic true for a hydraulic hose
local function getIsHydraulicConnectionEntry(entry)
    return type(entry) == "table"
        and type(entry.type) == "string"
        and string.sub(string.upper(entry.type), 1, 9) == "HYDRAULIC"
end

---Tells whether a moving tool is driven hydraulically
-- @param any tool moving tool
-- @return boolean isHydraulic true when hydraulic
function RMS_Utils.getIsHydraulicMovingTool(tool)
    return type(tool) == "table" and tool.playSound == true
end

---Tells whether the vehicle or an attached implement carries hydraulic hoses
-- @param table vehicle vehicle
-- @param table? visited vehicles already looked at
-- @return boolean hasHoses true with hoses
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
-- @param table vehicle vehicle
-- @return boolean hasHydraulics true with a circuit
function RMS_Utils.hasHydraulicCapability(vehicle)
    local visited = {}

    ---Tells whether a vehicle of the chain moves something hydraulically
    -- @param table vehicleObj vehicle
    -- @return boolean hasCapability true when it does
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
-- @param table vehicle vehicle
-- @return boolean hasTarget true when the player can
function RMS_Utils.hasHydraulicControllableTargetCapability(vehicle)
    local visited = {}

    ---Tells whether a vehicle of the chain has a hydraulic function the player drives
    -- @param table vehicleObj vehicle
    -- @return boolean hasTarget true when it has one
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
-- @param table vehicle vehicle
-- @param float totalTorque PTO torque asked
-- @return float utilization share of the capacity used
-- @return float motorSideTorque torque at the engine
-- @return float nativeCapacityTorque capacity of the engine
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
-- @param float utilization share of the capacity used
-- @param table config PTO configuration
-- @return float factor wear factor
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
-- @param table vehicle vehicle
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
-- @param table vehicle vehicle
-- @param table engagementTorques torque of each link
-- @param table previousActiveLinks links active at the previous frame
-- @param float rpmShare engine speed above idle, 0 to 1
-- @return float damage condition taken
-- @return boolean isShock true for an engagement at speed
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
-- @param table activeLinks links active now
-- @param table previousActiveLinks links active at the previous frame
-- @return integer count links that became active
function RMS_Utils.getPtoEngagementTransitionCount(activeLinks, previousActiveLinks)
    local count = 0
    for consumer, _ in pairs(activeLinks or {}) do
        if previousActiveLinks == nil or previousActiveLinks[consumer] ~= true then
            count = count + 1
        end
    end
    return count
end

---Tells whether a moving tool is a front loader arm or tool
-- @param table tool moving tool
-- @return boolean isLoader true for a front loader
function RMS_Utils.getIsLoaderMovingTool(tool)
    return tool.axis == "AXIS_FRONTLOADER_ARM" or tool.axis == "AXIS_FRONTLOADER_TOOL"
end

---Returns the PTO output of the front hitches, nil without one
-- @param table vehicle vehicle
-- @param boolean? includeSingle true to count a vehicle with one output
-- @return table? output PTO output
function RMS_Utils.getFrontPtoOutput(vehicle, includeSingle)
    local outputs = vehicle.getOutputPowerTakeOffs ~= nil and vehicle:getOutputPowerTakeOffs() or nil
    if outputs == nil or #outputs == 0 or #outputs < 2 and not includeSingle then
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

---Returns the unit line of a shaft from its tractor joint to its implement joint
-- @param table output PTO output
-- @return float? x nil when the shaft is collapsed
-- @return float? y y of the line
-- @return float? z z of the line
function RMS_Utils.getPtoShaftLine(output)
    local input = output.connectedInput
    local offset = input.zOffset or 0
    local x1, y1, z1 = localToWorld(output.outputNode, 0, 0, offset)
    local x2, y2, z2 = localToWorld(input.inputNode, 0, 0, -offset)
    local x, y, z = x2 - x1, y2 - y1, z2 - z1
    local length = math.sqrt(x * x + y * y + z * z)
    if length < 0.001 then
        return nil
    end
    return x / length, y / length, z / length
end

---Returns the angle in deg between two lines of a shaft, which never folds back
-- @param float ax x of the first line
-- @param float ay y of the first line
-- @param float az z of the first line
-- @param float bx x of the second line
-- @param float by y of the second line
-- @param float bz z of the second line
-- @return float angle angle (deg)
local function getBend(ax, ay, az, bx, by, bz)
    return math.deg(math.acos(math.clamp(math.abs(ax * bx + ay * by + az * bz), 0, 1)))
end

---Returns the bends of a towed shaft against itself swung in line about the hitch
-- @param table vehicleObj implement
-- @param table output PTO output of the tractor
-- @param table consumer PTO input of the implement
-- @param table hitch attacher joint of the implement
-- @return float tractorBend bend at the tractor joint (deg)
-- @return float implementBend bend at the implement joint (deg)
-- @return boolean isTractorNearer the turn falls mostly on the tractor joint
local function getTowedBends(vehicleObj, output, consumer, hitch)
    local input = output.connectedInput
    -- the frames carrying both ends: an articulated tractor's rear one
    local root = vehicleObj:getParentComponent(output.outputNode)
    local body = consumer:getParentComponent(input.inputNode)
    local offset = input.zOffset or 0
    local ax, ay, az = worldToLocal(root, localToWorld(output.outputNode, 0, 0, offset))
    local bx, by, bz = worldToLocal(root, localToWorld(input.inputNode, 0, 0, -offset))
    local hx, hy, hz = worldToLocal(root, getWorldTranslation(hitch.node))
    local isTractorNearer = (ax - hx) ^ 2 + (ay - hy) ^ 2 + (az - hz) ^ 2 <= (bx - hx) ^ 2 + (by - hy) ^ 2 + (bz - hz) ^ 2
    local fx, _, fz = worldDirectionToLocal(root, localDirectionToWorld(body, 0, 0, 1))
    local yaw = math.atan2(fx, fz)
    local c, s = math.cos(yaw), math.sin(yaw)
    local dx, dz = bx - hx, bz - hz
    local cx, cz = hx + dx * c - dz * s, hz + dx * s + dz * c
    local lx, ly, lz = bx - ax, by - ay, bz - az
    local mx, my, mz = cx - ax, by - ay, cz - az
    local l = math.max(math.sqrt(lx * lx + ly * ly + lz * lz), 0.001)
    local m = math.max(math.sqrt(mx * mx + my * my + mz * mz), 0.001)
    lx, ly, lz, mx, my, mz = lx / l, ly / l, lz / l, mx / m, my / m, mz / m
    -- in line, then turned with the implement
    local tx, tz = mx * c + mz * s, mz * c - mx * s
    return getBend(lx, ly, lz, mx, my, mz), getBend(lx, ly, lz, tx, my, tz), isTractorNearer
end

---Returns the life coefficient of a cardan cross at a joint angle
-- @param float angle joint angle (deg)
-- @return float life life coefficient
local function getCrossLife(angle)
    local points = RMS_Config.CORE.PTO_FACTOR_DATA.SHAFT_CROSS_LIFE
    angle = math.clamp(angle, points[1][1], points[#points][1])
    for i = 2, #points do
        local low, high = points[i - 1], points[i]
        if angle <= high[1] then
            return low[2] + (high[2] - low[2]) * (angle - low[1]) / (high[1] - low[1])
        end
    end
    return points[#points][2]
end

---Keeps each side's joint nearest its limit and the worst cross wear
-- @param table shaft angle and limit kept for this PTO side
-- @param table data PTO data being collected
-- @param float bend deg of the joint, aligned at work
-- @param boolean isWide wide-angle joint: two crosses share its angle
-- @param boolean isUnderPower implement at work: a plain joint holds less
-- @param float torqueShare torque against the one the driveline is built for
local function addJointStrain(shaft, data, bend, isWide, isUnderPower, torqueShare)
    local C = RMS_Config.CORE.PTO_FACTOR_DATA
    local levels = RMS_Config.CORE.DIRECT_FAILURES
    local limit = (isWide and levels.PTO_SHAFT_ANGLE_WIDE or isUnderPower and levels.PTO_SHAFT_ANGLE
        or levels.PTO_SHAFT_ANGLE_TURNING).limit
    if bend / limit > shaft.angle / shaft.limit then
        shaft.angle, shaft.limit = bend, limit
    end
    -- a cross lasts its rated life up to its rating angle
    local cross = math.max(bend / (isWide and 2 or 1), C.SHAFT_ANGLE_REFERENCE)
    local lifeLoss = getCrossLife(C.SHAFT_ANGLE_REFERENCE) / getCrossLife(cross) - 1
    data.shaftWear = math.max(data.shaftWear, lifeLoss * torqueShare ^ C.SHAFT_TORQUE_EXPONENT)
end

---Bends both joints of a towed shaft and strains its PTO side
-- @param table vehicleObj implement
-- @param table output PTO output of the tractor
-- @param table consumer PTO input of the implement
-- @param float torqueShare torque against the one the driveline is built for
-- @param table shaft angle and limit kept for this PTO side
-- @param table data PTO data being collected
local function addShaftStrain(vehicleObj, output, consumer, torqueShare, shaft, data)
    if RMS_Utils.getPtoShaftLine(output) == nil or consumer:getAllowsLowering() then
        return
    end
    local hitch = consumer:getActiveInputAttacherJoint()
    if hitch == nil then
        return
    end
    local isLowered = consumer.getIsLowered == nil or consumer:getIsLowered(true)
    local tractorBend, implementBend, isTractorNearer = getTowedBends(vehicleObj, output, consumer, hitch)

    -- two crosses where the game draws a wide-angle joint
    local input = output.connectedInput
    local isDouble = input.endJoint2 ~= nil
    local isWideBothEnds = RMS_Config.CORE.PTO_FACTOR_DATA.SHAFT_WIDE_BOTH_ENDS[input.rmsShaftModel] == true
    -- a towed implement turns on a wide-angle joint nearest its hitch
    addJointStrain(shaft, data, tractorBend, isDouble or isTractorNearer, isLowered, torqueShare)
    addJointStrain(shaft, data, implementBend, isDouble and isWideBothEnds or not isTractorNearer, isLowered, torqueShare)
end

---Collects the torque, speed, power and shaft strain of the implements a PTO drives
-- @param table vehicleObj vehicle
-- @param table data PTO data being collected
-- @param table visited vehicles already looked at
-- @param function? isOutputCounted tells whether an output is counted
-- @param table? frontOutput front PTO of the gathering vehicle
-- @param table? sideShaft strain of the side driving the vehicle
local function collectConnectedPtoData(vehicleObj, data, visited, isOutputCounted, frontOutput, sideShaft)
    if visited[vehicleObj] then
        return
    end
    visited[vehicleObj] = true

    if vehicleObj.getOutputPowerTakeOffs == nil then
        return
    end

    local outputs = vehicleObj:getOutputPowerTakeOffs()
    for _, output in pairs(outputs) do
        local consumer = output.connectedVehicle
        if output.connectedInput ~= nil and (isOutputCounted == nil or isOutputCounted(output)) then
            local shaft = sideShaft or (output == frontOutput and data.frontShaft or data.rearShaft)
            if data.connectedVehicles[consumer] ~= true then
                data.connectedVehicles[consumer] = true

                local isEngaged = consumer:getIsPowerTakeOffActive()
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
                local neededMaxPower = consumer.spec_powerConsumer ~= nil
                    and (tonumber(consumer.spec_powerConsumer.neededMaxPtoPower) or 0) or 0
                local ratedTorque = configuredRpm > 0 and neededMaxPower / (configuredRpm * math.pi / 30) or 0
                local torqueShare = ratedTorque > 0 and math.clamp(torque / ratedTorque, 0, 1) or 0
                if isEngaged then
                    data.activeLinks[consumer] = true
                    if vehicleObj.spec_combine == nil then
                        addShaftStrain(vehicleObj, output, consumer, torqueShare, shaft, data)
                    end
                    if consumer.spec_sprayer == nil then
                        data.engagementTorques[consumer] = ratedTorque
                    end
                end
            end

            collectConnectedPtoData(consumer, data, visited, nil, nil, shaft)
        end
    end
end

---Returns what the PTO drives, on one side or both
-- @param table vehicle vehicle
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
        rearShaft = { angle = 0, limit = RMS_Config.CORE.DIRECT_FAILURES.PTO_SHAFT_ANGLE.limit },
        frontShaft = { angle = 0, limit = RMS_Config.CORE.DIRECT_FAILURES.PTO_SHAFT_ANGLE.limit },
        shaftWear = 0
    }
    local visited = {}

    local frontOutput = RMS_Utils.getFrontPtoOutput(vehicle)
    local isOutputCounted = nil
    if side ~= nil then
        isOutputCounted = function(output)
            return (output == frontOutput) == (side == "front")
        end
    end

    collectConnectedPtoData(vehicle, data, visited, isOutputCounted, frontOutput)
    return data
end

---Turns every implement driven by the PTO on or off
-- @param table vehicle vehicle
-- @param boolean isTurnedOn true to turn them on
-- @param string? side "front", "rear", or nil for all outputs
-- @return boolean changed true when one changed
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

---Called on a hit of the machine raycast, stopping on a machine RMS manages
-- @param entityId hitActorId actor hit
-- @param float x hit x (world)
-- @param float y hit y (world)
-- @param float z hit z (world)
-- @param float distance distance to the hit (m)
-- @param float nx normal x
-- @param float ny normal y
-- @param float nz normal z
-- @param integer subShapeIndex sub shape hit
-- @param entityId hitShapeId shape hit
-- @return boolean continue true to look past the hit
function machineHit:onRaycastHit(hitActorId, x, y, z, distance, nx, ny, nz, subShapeIndex, hitShapeId)
    local vehicle = g_currentMission.vehicleSystem:getVehicleByNodeId(hitActorId, hitShapeId)
    if vehicle ~= nil and vehicle.spec_RealisticMechanicalSystems ~= nil then
        self.vehicle, self.distance = vehicle, distance
        return false
    end
    return true
end

---Returns the first machine a tool node points at, and its distance
-- @param entityId node node of the tool
-- @return table? machine machine
-- @return float? distance distance (m)
function RMS_Utils.raycastMachine(node)
    machineHit.vehicle, machineHit.distance = nil, nil
    local x, y, z = getWorldTranslation(node)
    local dirX, dirY, dirZ = localDirectionToWorld(node, 0, 0, -1)
    raycastAll(x, y, z, dirX, dirY, dirZ, RMS_Config.FIELD_CARE.RAYCAST_DISTANCE, "onRaycastHit", machineHit, nil, false, true)
    return machineHit.vehicle, machineHit.distance
end

---Returns the gap between segments in px: halved past 30, none past 60
-- @param integer count number of segments
-- @param float gap gap (px)
-- @return float gap gap (px)
function RMS_Utils.getSegmentGap(count, gap)
    return count > 60 and 0 or count > 30 and gap / 2 or gap
end

---Draws a rectangle on whole pixels
-- @param integer left left (screen pixels)
-- @param integer width width (screen pixels)
-- @param float y bottom (screen)
-- @param float height height (screen)
-- @param table color rgba color
local function fillPixels(left, width, y, height, color)
    drawFilledRect(left * g_pixelSizeX, y, width * g_pixelSizeX, height, color[1], color[2], color[3], color[4] or 1)
end

---Draws a row of segments on whole pixels, the first ones lit
-- @param float x left (screen)
-- @param float y bottom (screen)
-- @param float width width (screen)
-- @param float height height (screen)
-- @param integer count number of segments
-- @param integer lit segments lit
-- @param table litColor rgba color of the lit segments
-- @param table restColor rgba color of the others
-- @param float gap gap between segments (screen)
-- @return float? x of the first unlit segment, nil on a bar too dense to split
-- @return float? y bottom of the segment (screen)
-- @return float? width width of the segment (screen)
-- @return float? height height of the segment (screen)
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
-- @param table fillElement fill of the gauge
-- @param table underElement fill under the minimum mark
-- @param float trackWidth width of the track (screen)
-- @param float level level, 0 to 1
function RMS_Utils.setLevelGauge(fillElement, underElement, trackWidth, level)
    local fill, color = RMS_Fluids.getGaugeFill(level, RMS_Utils.COLOR.HIGHLIGHT)
    fillElement:setVisible(fill > 0)
    underElement:setVisible(fill <= 0)
    fillElement:setSize(GuiUtils.alignValueToScreenPixels(trackWidth * fill, true), nil)
    fillElement:setImageColor(nil, color[1], color[2], color[3], color[4])
    underElement:setImageColor(nil, color[1], color[2], color[3], color[4])
end

---Returns the squared distance past a threshold, 0 on the safe side of it
-- @param float level level
-- @param float threshold threshold
-- @param boolean lessIsWorse true when a lower level is worse
-- @param float? customMax end of the scale: floor when less is worse, else ceiling (default 1)
-- @return float multiplier squared distance, 0 to 1
function RMS_Utils.calculateQuadraticMultiplier(level, threshold, lessIsWorse, customMax)
    local distance
    if lessIsWorse then
        if level >= threshold then
            return 0.0
        end
        local floor = customMax
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
-- @param table motor motor of the vehicle
-- @param float motorLoad engine load
-- @param float loadThreshold load the lugging starts at
-- @return float severity severity, 0 to 1
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
-- @param table vehicle vehicle
-- @param float stockLoad share of the stock torque
-- @return float ratio torque ratio
function RMS_Utils.getRatedTorqueRatio(vehicle, stockLoad)
    local motor = vehicle.spec_motorized.motor
    local sanitize = RealisticMechanicalSystems.sanitizeNumber
    local ratedSpeed = sanitize(motor.peakMotorPowerRotSpeed, 0, 0)
    local rated = ratedSpeed > 0 and sanitize(motor.peakMotorPower, 0, 0) / ratedSpeed or 0
    local rpm = sanitize(motor:getLastRealMotorRpm(), ratedSpeed * 30 / math.pi, 0)
    local rise = rated > 0 and sanitize(motor:getTorqueCurve():get(rpm), rated, 0) / rated or 1
    return stockLoad * rise / RMS_EngineRemap.getOverloadRatio(vehicle)
end

---Returns the life law factor past the rated level, wear growing as the ratio to the exponent
-- @param float ratio ratio to the rated level
-- @param float exponent exponent of the life law
-- @return float factor extra wear, 0 up to the rated level
function RMS_Utils.getLifeLawFactor(ratio, exponent)
    return ratio > 1 and ratio ^ exponent - 1 or 0
end

---Returns the wear of a cold circuit, by its start temperature
-- @param float temperature temperature (deg C)
-- @param float reference temperature the wear starts under (deg C)
-- @return float factor extra wear
function RMS_Utils.getColdWearFactor(temperature, reference)
    local C = RMS_Config.CORE.ENGINE_FACTOR_DATA
    if temperature >= reference then
        return 0
    end
    local measured = C.COLD_MOTOR_TEMP_THRESHOLD - C.COLD_MOTOR_MEASURED_MIN
    return math.exp(C.COLD_MOTOR_WEAR_SLOPE * math.min(reference - temperature, measured)) - 1
end

---Returns the wear past a temperature, life halved every HEAT_HALVING_K
-- @param float temperature temperature (deg C)
-- @param float reference temperature the wear starts at (deg C)
-- @return float factor extra wear
function RMS_Utils.getHeatWearFactor(temperature, reference)
    if temperature <= reference then
        return 0
    end
    return 2 ^ ((temperature - reference) / RMS_Config.CORE.HEAT_HALVING_K) - 1
end

---Returns the chance a part fails between two wears
-- @param string partId part
-- @param float fromWear wear now
-- @param float toWear wear ahead
-- @return float chance chance, 0 to 1
function RMS_Utils.getPartFailureChance(partId, fromWear, toWear)
    local C = RMS_Config.CORE
    local life = C.COMPONENT_LIVES[RMS_Breakdowns.BreakdownRegistry[partId].component]
    local lives = C.MACHINE_LIFE_HOURS / life.scale
    return 1 - math.exp((fromWear * lives) ^ life.shape - (toWear * lives) ^ life.shape)
end

---Returns a part's wear over the risk horizon; a lamp's only while lit
-- @param string partId part
-- @return float wear wear of the horizon
function RMS_Utils.getPartRiskHorizon(partId)
    local C = RMS_Config.CORE
    if RMS_Breakdowns.BreakdownRegistry[partId].wearsWhile ~= nil then
        return C.RISK_HORIZON_WEAR * C.USED_VEHICLE_HISTORY.LIT_SHARE
    end
    return C.RISK_HORIZON_WEAR
end

---Returns a part's risk over the wear ahead, as a multiple of new
-- @param string partId part
-- @param float wear wear of the part
-- @return float ratio risk ratio
function RMS_Utils.getPartRiskRatio(partId, wear)
    local horizon = RMS_Utils.getPartRiskHorizon(partId)
    return RMS_Utils.getPartFailureChance(partId, wear, wear + horizon) / RMS_Utils.getPartFailureChance(partId, 0, horizon)
end

---Tells whether a part is worn: past its B10 wear and at the risk ratio of a worn part
-- @param string partId part
-- @param float wear wear of the part
-- @return boolean isWorn true when worn
function RMS_Utils.getIsPartWorn(partId, wear)
    return wear >= RMS_Utils.getPartB10Wear(partId) and RMS_Utils.getPartRiskRatio(partId, wear) >= RMS_Config.CORE.WORN_PART_RISK_RATIO
end

RMS_Utils.WORN_PARTS_SHOWN = 3

---Lists the worn parts a complete report found, most at risk first
-- @param table vehicle vehicle
-- @param table conditionData condition data of the report
-- @param integer count most parts listed
-- @param function? isKept tells whether a part is still listed
-- @return table entries partId, title, severity and text of each worn part
function RMS_Utils.getWornPartEntries(vehicle, conditionData, count, isKept)
    local R = RealisticMechanicalSystems
    local activeBreakdowns, adjusted, worn = conditionData.activeBreakdowns, {}, {}
    for _, partId in ipairs(R.MAJOR_SERVICE_CHECKS) do
        adjusted[partId] = true
    end
    local systemParts = vehicle.spec_RealisticMechanicalSystems.systemParts
    for systemKey, system in pairs(conditionData.systems) do
        if system.enabled then
            for _, partId in ipairs(systemParts[systemKey]) do
                local wear = conditionData.partWear[partId]
                if wear ~= nil and activeBreakdowns[partId] == nil and RMS_Utils.getIsPartWorn(partId, wear)
                    and (isKept == nil or isKept(partId)) then
                    table.insert(worn, { partId = partId, systemKey = systemKey, ratio = RMS_Utils.getPartRiskRatio(partId, wear) })
                end
            end
        end
    end
    table.sort(worn, function(a, b)
        if a.ratio ~= b.ratio then
            return a.ratio > b.ratio
        end
        return a.partId < b.partId
    end)
    local entries = {}
    for index = 1, math.min(#worn, count) do
        local part = worn[index]
        local systemName = g_i18n:getText(RMS_Utils.getSystemLabel(vehicle, RMS_Utils.getSystemNameByKey(R.SYSTEMS, part.systemKey)))
        local text = adjusted[part.partId]
            and string.format(g_i18n:getText("rms_report_worn_part_adjust"), systemName,
                RMS_Utils.formatMaintenanceLevel(vehicle, R.MAINTENANCE_TYPES.PREVENTIVE))
            or string.format(g_i18n:getText("rms_report_worn_part_replace"), systemName)
        table.insert(entries, { partId = part.partId, title = RMS_Utils.getBreakdownPartName(part.partId, vehicle),
            severity = string.format(g_i18n:getText("rms_report_worn_part_risk"), g_i18n:formatNumber(part.ratio, 1)), text = text })
    end
    return entries
end

---Lists the worn parts of the last complete report still on the machine
-- @param table vehicle vehicle
-- @return table entries partId, title, severity and text of the three most at risk
function RMS_Utils.getInspectedWornParts(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    for index = #spec.maintenanceLog, 1, -1 do
        local entry = spec.maintenanceLog[index]
        if RealisticMechanicalSystems.getIsCompleteReport(entry) then
            local found = entry.conditionData.partWear
            return RMS_Utils.getWornPartEntries(vehicle, entry.conditionData, RMS_Utils.WORN_PARTS_SHOWN, function(partId)
                return vehicle:getActiveBreakdowns()[partId] == nil and (spec.partWear[partId] or 0) >= found[partId]
            end)
        end
    end
    return {}
end

---Returns the wear at which 1 in 10 of a part has failed
-- @param string partId part
-- @return float wear wear
function RMS_Utils.getPartB10Wear(partId)
    local C = RMS_Config.CORE
    local life = C.COMPONENT_LIVES[RMS_Breakdowns.BreakdownRegistry[partId].component]
    return life.scale * (-math.log(1 - C.WORN_PART_FAILED_SHARE)) ^ (1 / life.shape) / C.MACHINE_LIFE_HOURS
end

---Returns a system's risk over the wear ahead, as a multiple of new
-- @param table vehicle vehicle
-- @param string systemKey key of the system
-- @param table partWear wear of each part
-- @return float? ratio risk ratio, nil without a part
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
-- @param float? ratio risk ratio
-- @return integer? tier 1 to 3, nil when no RMS assessment is available
function RMS_Utils.getBreakdownRiskTier(ratio)
    if ratio == nil then return nil end
    if ratio < RMS_Config.CORE.RISK_RATIO_MODERATE then return 1 end
    if ratio < RMS_Config.CORE.RISK_RATIO_HIGH then return 2 end
    return 3
end

---Formats an assessed risk as Low, Moderate or High
-- @param integer? tier tier
-- @return string text risk
function RMS_Utils.formatBreakdownRisk(tier)
    local keys = {"low", "moderate", "high"}
    local key = keys[tier]
    return g_i18n:getText(key ~= nil and ("rms_report_risk_" .. key) or "rms_report_state_not_available")
end

---Splits a decimal hour count into whole hours and minutes
-- @param float totalHours hours
-- @return integer hours whole hours
-- @return integer minutes minutes
function RMS_Utils.convertHoursToHoursAndMinutes(totalHours)
    local minutes = math.floor(math.max(totalHours, 0) * 60 + 0.5)
    return math.floor(minutes / 60), minutes % 60
end

---Writes the farm balance, red below zero
-- @param table moneyBox box of the balance
-- @param table moneyBoxBg background of the box
-- @param table balanceElement text of the balance
function RMS_Utils.setBalance(moneyBox, moneyBoxBg, balanceElement)
    local money = g_currentMission:getMoney()
    local GUI_PROFILE = ShopMenu.GUI_PROFILE
    balanceElement:applyProfile(math.floor(money) <= -1 and GUI_PROFILE.SHOP_MONEY_NEGATIVE or GUI_PROFILE.SHOP_MONEY, nil, true)
    balanceElement:setText(g_i18n:formatMoney(money, 0, true, false))
    moneyBox:invalidateLayout()
    moneyBoxBg:setSize(moneyBox.flowSizes[1] + 60 * g_pixelSizeScaledX)
end

---Lays an element and its children out again
-- @param table element element
local function layOut(element)
    for _, child in ipairs(element.elements) do
        layOut(child)
    end
    if element.invalidateLayout ~= nil then
        element:invalidateLayout()
    end
end

---Clones a template at the end of its parent, then deletes the template
-- @param table template template
-- @param integer count number of clones
-- @return table clones clones
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
-- @param table card card
function RMS_Utils.insetCardBackground(card)
    local frame, background = card:getDescendantByName("frame"), card:getDescendantByName("background")
    -- two reference pixels: whole, every edge rounds alike on the screen
    local pixels = math.max(math.floor(2 * g_pixelSizeScaledX * g_screenWidth + 0.5), 1)
    local insetX, insetY = pixels / g_screenWidth, pixels / g_screenHeight
    background:setPosition(frame.position[1] + insetX, frame.position[2] - insetY)
    background:setSize(frame.size[1] - 2 * insetX, frame.size[2] - 2 * insetY)
end

---Returns the machine a tool is connected to, server or client
-- @param table spec specialization of the tool
-- @return table? object machine connected
function RMS_Utils.getConnectedObject(spec)
    if spec.targetObjectId ~= nil then
        return NetworkUtil.getObject(spec.targetObjectId)
    end
    return spec.target
end

---Returns the key holding a value in a table
-- @param table tbl table
-- @param any value value
-- @return any key key, nil when not found
function RMS_Utils.getKeyByValue(tbl, value)
    for key, entry in pairs(tbl) do
        if entry == value then
            return key
        end
    end
    return nil
end

---Returns the ids of the known breakdowns the workshop can repair now, worst stage first
-- @param table vehicle vehicle
-- @return table ids breakdowns
function RMS_Utils.getRepairableBreakdownIds(vehicle)
    local breakdowns = vehicle:getActiveBreakdowns()
    local ids = {}
    for id, breakdown in pairs(breakdowns) do
        if breakdown.isVisible and RealisticMechanicalSystems.getCanRepairFault(vehicle, id) then
            table.insert(ids, id)
        end
    end
    table.sort(ids, function(a, b)
        local aStage, bStage = breakdowns[a].stage, breakdowns[b].stage
        if aStage ~= bStage then
            return aStage > bStage
        end
        return a < b
    end)
    return ids
end

---Returns the stage and description of a known breakdown, as the workshop words them
-- @param table vehicle vehicle
-- @param string id breakdown
-- @param table breakdown state of the breakdown
-- @return string stageText stage
-- @return string descriptionText description
function RMS_Utils.getBreakdownTexts(vehicle, id, breakdown)
    local SOURCES = RealisticMechanicalSystems.BREAKDOWN_SOURCES
    if not breakdown.isActive and breakdown.source == SOURCES.QUICK_FIX then
        return g_i18n:getText("rms_breakdowns_quick_fix_stage"), g_i18n:getText("rms_breakdowns_temporarily_repaired_description")
    elseif not breakdown.isActive and breakdown.source == SOURCES.POOR_PARTS then
        return g_i18n:getText("rms_breakdowns_defected_parts_stage"), g_i18n:getText("rms_breakdowns_defected_parts_detected_description")
    end
    local definition = RMS_Breakdowns.BreakdownRegistry[id]
    local stage = definition.stages[breakdown.stage]
    return g_i18n:getText(stage.severity), g_i18n:getText(RMS_Breakdowns.getStageDescription(vehicle, stage, breakdown, definition))
end

---Returns the name a breakdown takes where its organ differs, if any
-- @param table? vehicle vehicle
-- @param table definition definition of the breakdown
-- @return string? variant variant of the name
function RMS_Utils.getBreakdownNameVariant(vehicle, definition)
    if vehicle == nil or definition.getNameVariant == nil then
        return nil
    end
    return definition.getNameVariant(vehicle)
end

---Returns the text key of the part a breakdown hits on a vehicle
-- @param table vehicle vehicle
-- @param table definition definition of the breakdown
-- @return string textKey l10n key
function RMS_Utils.getBreakdownPartKey(vehicle, definition)
    local variant = RMS_Utils.getBreakdownNameVariant(vehicle, definition)
    return variant ~= nil and definition.variantParts[variant] or definition.part or definition.system
end

---Returns the name of the part a breakdown hits on a vehicle
-- @param string id breakdown
-- @param table vehicle vehicle
-- @return string name name of the part
function RMS_Utils.getBreakdownPartName(id, vehicle)
    return g_i18n:getText(RMS_Utils.getBreakdownPartKey(vehicle, RMS_Breakdowns.BreakdownRegistry[id]))
end

---Returns the items of a stage for the way of a breakdown
-- @param table? items stage items, each common to every mode or tied to one by its branch
-- @param table breakdown state of the breakdown
-- @return table items items of its way
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
-- @param table breakdownsTable breakdowns
-- @return string serialized breakdowns
function RMS_Utils.serializeBreakdowns(breakdownsTable)
    local entries = {}
    for id, breakdown in pairs(breakdownsTable) do
        local overdue = breakdown.warrantyServiceOverdue
        table.insert(entries, string.format("%s,%d,%.2f,%d,%d,%d,%.2f,%d,%d,%d,%d,%s,%d", id, breakdown.stage,
            breakdown.progressTimer, toFlag(breakdown.isVisible), toFlag(breakdown.isSelectedForRepair),
            toFlag(breakdown.isActive), breakdown.resumeTimer,
            breakdown.source, breakdown.effectTargetIndex, breakdown.branch,
            overdue == nil and -1 or toFlag(overdue), breakdown.usedPartHours or "", toCount(breakdown.warrantyAbuse)))
    end
    return table.concat(entries, ";")
end

---Writes a date as day, month and year, empty without a day
-- @param table? dateTable date
-- @return string serialized date
function RMS_Utils.serializeDate(dateTable)
    local hasDay = dateTable ~= nil and dateTable.day ~= nil
    return hasDay and string.format("%d,%d,%d", dateTable.day, dateTable.month, dateTable.year) or ""
end

---Returns a text percent-escaped but for letters, digits and - . _ ~
-- @param string value text
-- @return string encoded text escaped
function RMS_Utils.encodeDelimitedString(value)
    local escaped = string.gsub(value, "[^%w%-%._~]", function(char)
        return string.format("%%%02X", string.byte(char))
    end)
    return escaped
end

---Returns a text with the characters encodeDelimitedString escaped restored
-- @param string value text escaped
-- @return string decoded text
function RMS_Utils.decodeDelimitedString(value)
    local decoded = string.gsub(value, "%%(%x%x)", function(hex)
        return string.char(tonumber(hex, 16))
    end)
    return decoded
end

---Reads a date written by serializeDate, empty when unreadable
-- @param string? dateString serialized date
-- @return table date day, month and year
function RMS_Utils.deserializeDate(dateString)
    local day, month, year = string.match(dateString or "", "([^,]+),([^,]+),([^,]+)")
    if day == nil then
        return {}
    end
    return { day = tonumber(day), month = tonumber(month), year = tonumber(year) }
end

---Reads the breakdowns serializeBreakdowns wrote, older saves too, keeping the known ones at a stage they have
-- @param string? breakdownString serialized breakdowns
-- @return table breakdowns breakdowns
function RMS_Utils.deserializeBreakdowns(breakdownString)
    local breakdowns = {}
    for entry in string.gmatch(breakdownString or "", "[^;]+") do
        local fields = { string.match(entry, BREAKDOWN_ENTRY_PATTERN) }
        local definition = fields[1] ~= nil and RMS_Breakdowns.BreakdownRegistry[fields[1]] or nil
        if definition ~= nil then
            local breakdown = {
                stage = math.clamp(math.floor(tonumber(fields[2]) or 1), 1, #definition.stages),
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
-- @param integer? daysToAdd days crossed
-- @return string text finish time
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
-- @param string actionName input action
-- @param string? fallbackText text without a binding
-- @return string text binding
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
-- @return float temperature temperature (deg C)
function RMS_Utils.getAmbientTemperature()
    return g_currentMission.environment.weather:getCurrentTemperature()
end

---Formats a duration in days, hours and minutes
-- @param float? duration duration in hours
-- @return string text duration
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
-- @param float condition condition, 0 to 1
-- @return integer tier tier
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
-- @param float? condition condition, 0 to 1
-- @param boolean isCompleteInspection true after a complete inspection
-- @return string text condition
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
-- @param float? service service level
-- @return float share share, 0 to 1
function RMS_Utils.getServiceIntervalRemainingRatio(service)
    local threshold = RMS_Config.CORE.SERVICE_EXPIRED_THRESHOLD
    local left = ((tonumber(service) or 0.0) - threshold) / (1.0 - threshold)
    return math.clamp(left, 0.0, 1.0)
end

---Formats a service level, exact after a complete inspection
-- @param float? service service level
-- @param boolean isCompleteInspection true after a complete inspection
-- @return string text service level
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
-- @param float? service service level
-- @return integer tier tier
function RMS_Utils.getServiceTier(service)
    return getLevelTier(SERVICE_LEVELS, tonumber(service) or 0.0)
end


---Returns the top of a tier, 1 for the first
-- @param table levels descending levels
-- @param integer tier tier
-- @return float ceiling top of the tier
local function getTierCeiling(levels, tier)
    return tier > 1 and levels[tier - 1] or 1.0
end


---Returns the condition ring ratio, exact after a complete inspection
-- @param float? condition condition, 0 to 1
-- @param boolean isCompleteInspection true after a complete inspection
-- @return float ratio ratio, 0 to 1
function RMS_Utils.getConditionRingRatio(condition, isCompleteInspection)
    if isCompleteInspection == nil then
        return 0.0
    elseif not isCompleteInspection then
        return getTierCeiling(RMS_Utils.CONDITION_LEVELS, RMS_Utils.getConditionTier(condition))
    end
    return math.clamp(tonumber(condition) or 0.0, 0.0, 1.0)
end


---Returns the service ring ratio, exact after a complete inspection
-- @param float? service service level
-- @param boolean isCompleteInspection true after a complete inspection
-- @return float ratio ratio, 0 to 1
function RMS_Utils.getServiceRingRatio(service, isCompleteInspection)
    if isCompleteInspection == nil then
        return 0.0
    elseif not isCompleteInspection then
        service = getTierCeiling(SERVICE_LEVELS, RMS_Utils.getServiceTier(service))
    end
    return RMS_Utils.getServiceIntervalRemainingRatio(service)
end


---Formats how many whole hours of work an inspection report is old
-- @param float? hours hours of work since the report
-- @return string text age
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

---Returns how many months ago a date was, in the texts given
-- @param table? pastDate date
-- @param table texts l10n keys: none, this month, months ago
-- @return string text months ago
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
-- @param table? pastDate date
-- @return string text months ago
function RMS_Utils.formatTimeAgo(pastDate)
    return formatMonthsAgo(pastDate, MONTHS_AGO_TEXTS.fleet)
end

---Formats the last maintenance of a machine
-- @param table? pastDate date of the last maintenance
-- @return string text months ago
function RMS_Utils.formatShopLastMaintenance(pastDate)
    return formatMonthsAgo(pastDate, MONTHS_AGO_TEXTS.shop)
end

---Returns the care of an owner by the damage of a used offer
-- @param float damage damage of the offer
-- @return string care "careful", "regular" or "neglected"
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

---Returns the damage a used offer shows for a care
-- @param string care "careful", "regular" or "neglected"
-- @return float damage damage
function RMS_Utils.getOwnerCareDamage(care)
    local history = RMS_Config.CORE.USED_VEHICLE_HISTORY
    local third = ({ careful = 0, regular = 1, neglected = 2 })[care]
    return history.DAMAGE_MIN + (third + 0.5) / 3 * (history.DAMAGE_MAX - history.DAMAGE_MIN)
end

---Returns the care a machine was sold in
-- @param table vehicle vehicle
-- @return string care "careful", "regular" or "neglected"
function RMS_Utils.getSellerCare(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    for breakdownId in pairs(spec.activeBreakdowns) do
        if RMS_Breakdowns.BreakdownRegistry[breakdownId].isPartFault then
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
-- @param float damage damage of the offer
-- @return string text care
function RMS_Utils.formatOwnerCare(damage)
    return g_i18n:getText(OWNER_CARE_LABELS[RMS_Utils.getOwnerCare(damage)])
end


---Reads the native lifetime odometer, already expressed in kilometres
-- @param table vehicle vehicle
-- @return float? kilometers distance (km)
function RMS_Utils.getOdometerKilometers(vehicle)
    local drivable = vehicle ~= nil and vehicle.spec_drivable or nil
    local kilometers = drivable ~= nil and tonumber(drivable.odometerMilage) or nil
    if kilometers == nil or kilometers ~= kilometers or kilometers < 0 or kilometers == math.huge then
        return nil
    end
    return kilometers
end

---Returns an odometer reading in the game's unit
-- @param float? kilometers distance (km)
-- @return string text distance
function RMS_Utils.formatOdometerKilometers(kilometers)
    kilometers = tonumber(kilometers)
    if kilometers == nil or kilometers ~= kilometers or kilometers < 0 or kilometers == math.huge then
        return g_i18n:getText("rms_odometer_not_recorded")
    end
    return g_i18n:formatNumber(g_i18n:getDistance(kilometers), 1) .. " " .. g_i18n:getMeasuringUnit()
end


---Formats hour-meter values and hourly deadlines
-- @param float? hours hours
-- @return string text hours
function RMS_Utils.formatHours(hours)
    return string.format("%s %s", g_i18n:formatNumber(tonumber(hours) or 0, 1), g_i18n:getText("rms_spec_op_hours_short"))
end


---Formats whole calendar months in the player's language
-- @param float months months
-- @return string text months
function RMS_Utils.formatMonths(months)
    local count = math.max(months or 0, 0)
    return string.format(g_i18n:getText(count == 1 and "rms_service_month" or "rms_service_months"), g_i18n:formatNumber(count, 0))
end

---Formats an amount of a greasing interval in its unit
-- @param table tier greasing tier
-- @param float amount amount in the unit of the tier
-- @return string text amount
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
-- @param table tier greasing tier
-- @return string text time left
function RMS_Utils.formatGreasingLeft(tier)
    return RMS_Utils.formatGreasingAmount(tier, math.max(tier.interval - tier.elapsed, 0))
end

---Returns the circuit the next service is recommended for
-- @param table vehicle vehicle
-- @param table schedule service schedule
-- @param boolean? compact true for the short name
-- @return string text circuit
function RMS_Utils.formatServiceReason(vehicle, schedule, compact)
    if schedule == nil then return "" end
    return g_i18n:getText(RMS_Fluids.getCircuitTextKey(vehicle, schedule.clock.circuits[1], compact))
end

---Formats the two limits of a service deadline
-- @param table? schedule service schedule
-- @param boolean? showInterval true for the interval instead of what is left
-- @return string text deadline
function RMS_Utils.formatServiceDeadline(schedule, showInterval)
    if schedule == nil then return "" end
    local hours = showInterval and schedule.interval or math.max(schedule.interval - schedule.used, 0)
    local months = showInterval and schedule.months or schedule.remainingMonths
    return string.format(g_i18n:getText("rms_service_either"), RMS_Utils.formatHours(hours), RMS_Utils.formatMonths(months))
end

---Returns which change the next service is for and when it falls due
-- @param table vehicle vehicle
-- @param table schedule service schedule
-- @param boolean? compact true for the short name
-- @return string text service due
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
-- @return string text duration
function RMS_Utils.formatShortDuration(duration)
    local hours, minutes = RMS_Utils.convertHoursToHoursAndMinutes(duration)
    if hours == 0 then
        return string.format(g_i18n:getText("rms_ws_levels_duration_minutes"), minutes)
    elseif minutes == 0 then
        return string.format(g_i18n:getText("rms_ws_levels_duration_hours"), hours)
    end
    return string.format(g_i18n:getText("rms_ws_levels_duration"), hours, minutes)
end

---Returns the name of a maintenance level, by the hours between two of them on the machine
-- @param table vehicle vehicle
-- @param string maintenanceType RealisticMechanicalSystems.MAINTENANCE_TYPES
-- @return string text maintenance level
function RMS_Utils.formatMaintenanceLevel(vehicle, maintenanceType)
    return string.format(g_i18n:getText("rms_spec_maintenance_level"),
        RMS_Utils.formatHours(vehicle:getMaintenanceLevelInterval(maintenanceType)))
end

---Formats an engine power
-- @param float hp power (hp)
-- @return string text power
function RMS_Utils.formatPower(hp)
    return string.format(g_i18n:getText("shop_maxPowerValueSingle"), MathUtil.round(hp))
end

---Returns the name of the first option of a service
-- @param table vehicle vehicle
-- @param string serviceType RealisticMechanicalSystems.STATUS of the service
-- @param string optionOne first option of the service
-- @param string? workshopType of a remap to come, nil for the software fitted
-- @return string text option
function RMS_Utils.formatServiceOption(vehicle, serviceType, optionOne, workshopType)
    if serviceType == RealisticMechanicalSystems.STATUS.MAINTENANCE then
        return RMS_Utils.formatMaintenanceLevel(vehicle, optionOne)
    elseif serviceType == RealisticMechanicalSystems.STATUS.REMAP then
        local stockHp = RMS_EngineRemap.getStockPeaks(vehicle)
        local power = optionOne == RMS_EngineRemap.REMAP and stockHp * (1 + RMS_EngineRemap.getGain(vehicle, workshopType)) or stockHp
        return string.format("%s · %s", g_i18n:getText(optionOne), RMS_Utils.formatPower(power))
    end
    return g_i18n:getText(optionOne)
end

---Returns the interval of the lightest maintenance fitting a new air filter
-- @param table vehicle vehicle
-- @return string? text interval
function RMS_Utils.formatAirFilterServiceHours(vehicle)
    for _, maintenanceType in ipairs(vehicle:getMaintenanceTypes()) do
        if RealisticMechanicalSystems.getMaintenanceRenewsAirFilter(maintenanceType) then
            return RMS_Utils.formatHours(vehicle:getMaintenanceLevelInterval(maintenanceType))
        end
    end
end


---Returns the label of a value against four descending thresholds
-- @param float value value
-- @param float ideal first threshold
-- @param float high second threshold
-- @param float mid third threshold
-- @param float low fourth threshold
-- @param any ... the five labels, best first
-- @return string label label
function RMS_Utils.getValueLabel(value, ideal, high, mid, low, ...)
    return ({ ... })[getLevelTier({ ideal, high, mid, low }, value)]
end


local RELIABILITY_LABELS = { "rms_reliability_average", "rms_reliability_fair", "rms_reliability_good", "rms_reliability_very_good" }
local SHOP_RELIABILITY_LABELS = { "rms_shop_reliability_average", "rms_shop_reliability_fair", "rms_shop_reliability_good",
    "rms_shop_reliability_very_good" }

---Formats a reliability value as its localized label
-- @param float value reliability
-- @param boolean? isShop true for the shop labels
-- @return string text reliability
function RMS_Utils.formatReliability(value, isShop)
    value = tonumber(value) or 1
    local tier = value < 1.0 and 1 or value < 1.1 and 2 or value < 1.2 and 3 or 4
    return g_i18n:getText((isShop and SHOP_RELIABILITY_LABELS or RELIABILITY_LABELS)[tier])
end

---Returns the fill type names a shop configuration consumes, as the shop reads its fuel
-- @param table storeItem store item
-- @param table? configurations configurations picked
-- @return table fillTypes fill type names
local function getStoreConsumerFillTypes(storeItem, configurations)
    local index = 1
    local motor = configurations ~= nil and configurations.motor or nil
    local motorConfigurations = storeItem.configurations ~= nil and storeItem.configurations.motor or nil
    if motor ~= nil and motorConfigurations ~= nil and motorConfigurations[motor] ~= nil then
        index = motorConfigurations[motor].consumerConfigurationIndex or index
    end
    local fillTypes = {}
    local fuel = storeItem.specs ~= nil and storeItem.specs.fuel or nil
    for _, consumer in ipairs(fuel ~= nil and fuel.consumers[index] or {}) do
        fillTypes[string.upper(consumer.fillType or "")] = true
    end
    return fillTypes
end

---Returns the ease of service class of an owned machine or of a shop configuration
-- @param table? vehicle owned machine
-- @param table? storeItem store item
-- @param table? configurations configurations picked
-- @return string key "SIMPLE", "STANDARD" or "COMPLEX"
function RMS_Utils.getServiceAccessKey(vehicle, storeItem, configurations)
    local isElectric, hasControllers
    if vehicle ~= nil and vehicle.spec_RealisticMechanicalSystems ~= nil then
        isElectric = vehicle.spec_RealisticMechanicalSystems.isElectricVehicle
        hasControllers = RMS_DiagnosticTool.getHasControllers(vehicle)
    else
        local fillTypes = getStoreConsumerFillTypes(storeItem, configurations)
        local year, source = RMS_ProductionYear.getYear(storeItem)
        isElectric = fillTypes.ELECTRICCHARGE == true and fillTypes.DIESEL == nil and fillTypes.METHANE == nil
        hasControllers = isElectric
            or RMS_Utils.getHasEngineECU(fillTypes.DEF == true, year, source ~= RMS_ProductionYear.SOURCE.UNKNOWN)
    end
    return isElectric and "COMPLEX" or hasControllers and "STANDARD" or "SIMPLE"
end

---Returns the ease of service label of an owned machine or of a shop configuration
-- @param table? vehicle owned machine
-- @param table? storeItem store item
-- @param table? configurations configurations picked
-- @param boolean? isShop true for the shop label
-- @return string text ease of service
function RMS_Utils.formatServiceAccess(vehicle, storeItem, configurations, isShop)
    local profile = RMS_Config.SERVICE_ACCESS_PROFILES[RMS_Utils.getServiceAccessKey(vehicle, storeItem, configurations)]
    return g_i18n:getText(isShop and profile.shopLabel or profile.label)
end

---Returns the colour of an original reliability
-- @param float? value reliability
-- @return float r red
-- @return float g green
-- @return float b blue
-- @return float a alpha
function RMS_Utils.getReliabilityColor(value)
    return RMS_Utils.getValueColor(tonumber(value) or 1, 1.1, 1.1, 1.0, 0, false)
end

---Returns the colour of the ease of service of a vehicle
-- @param table vehicle vehicle
-- @return float r red
-- @return float g green
-- @return float b blue
-- @return float a alpha
function RMS_Utils.getServiceAccessColor(vehicle)
    local tier = RMS_Config.SERVICE_ACCESS_PROFILES[RMS_Utils.getServiceAccessKey(vehicle)].tier
    return RMS_Utils.getValueColorInverted(tier, 1, 1, 2, 3, false)
end

---Writes the causes of wear as alias:share pairs
-- @param table? causes share of each cause over the normal wear, by alias
-- @return string serialized causes
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
-- @param string? text serialized causes
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
    QUOTE_LINE = {0.5028, 0.5028, 0.5028, 1.0},
    DISABLED = {0.3, 0.3, 0.3, 1.0},
    MAIN_DARK = {0.00439, 0.00478, 0.00368, 1.0},
    ALERT = {0.88, 0.18, 0.18, 1.0},
    RING_TRACK = {0.04374, 0.04374, 0.04374, 1.0},
    STAGE = {
        {0.89627, 0.92158, 0.81485, 1.0},
        {0.85, 0.78, 0.2, 1.0},
        {0.85, 0.5, 0.15, 1.0},
        {0.8, 0.2, 0.2, 1.0}
    }
}

---Returns the entries of the maintenance log the record shows, newest first
-- @param table vehicle vehicle
-- @return table entries log entries
function RMS_Utils.getVisibleLogEntries(vehicle)
    local log = vehicle.spec_RealisticMechanicalSystems.maintenanceLog
    local entries = {}
    for index = #log, 1, -1 do
        if log[index].isVisible then
            table.insert(entries, log[index])
        end
    end
    return entries
end

---Returns the count of breakdowns resolved by the completed repairs and overhauls of a log
-- @param table log maintenance log
-- @return integer count breakdowns resolved
function RMS_Utils.getResolvedBreakdownsCount(log)
    local STATUS, count = RealisticMechanicalSystems.STATUS, 0
    for _, entry in ipairs(log) do
        if entry.isCompleted and (entry.type == STATUS.REPAIR or entry.type == STATUS.OVERHAUL) then
            count = count + #entry.conditionData.selectedBreakdowns
        end
    end
    return count
end

---Formats a maintenance log date in the same compact form as the report screen
-- @param table entry log entry
-- @return string text date
function RMS_Utils.formatMaintenanceLogDate(entry)
    local year = entry ~= nil and entry.date ~= nil and tonumber(entry.date.year) or 0
    local yearText = year >= 10 and tostring(year) or "0" .. tostring(year)
    local day = entry ~= nil and entry.date ~= nil and tonumber(entry.date.day) or 1
    local month = entry ~= nil and entry.date ~= nil and tonumber(entry.date.month) or 1
    return string.format("%s %s. '%s", day, g_i18n:formatPeriod(month, true), yearText)
end

---Returns the name of a service state, the repaint by its RMS name
-- @param string status RealisticMechanicalSystems.STATUS
-- @return string text name of the state
function RMS_Utils.formatServiceState(status)
    if status == RealisticMechanicalSystems.STATUS.BODYWORK then
        return g_i18n:getText("rms_spec_state_bodywork")
    end
    return g_i18n:getText(status)
end

---Returns the label, colour and icon of an intervention type
-- @param table entry log entry
-- @return string label label
-- @return table color rgba color
-- @return string iconSliceId slice of the icon
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

---Fills the text columns of a row, empty ones hidden
-- @param table items texts of the list
-- @param integer index row
-- @param table cell cell to fill
-- @param table columns attributes of the columns
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
-- @param table items texts of the list
-- @param integer index row
-- @param table cell cell to fill
-- @param string leftAttribute attribute of the left text
-- @param string rightAttribute attribute of the right text
-- @param string rightBulletAttribute attribute of the right bullet
function RMS_Utils.populateTwoColumnTextRow(items, index, cell, leftAttribute, rightAttribute, rightBulletAttribute)
    populateTextColumnsRow(items, index, cell, {
        {text = leftAttribute},
        {text = rightAttribute, bullet = rightBulletAttribute}
    })
end

-- two best colours of the value scales, the stage colours following
local SCALE_BEST = {0.12, 0.88, 0.0, 1.0}
local SCALE_GOOD = {0.3, 0.7, 0.0, 1.0}

local SERVICE_COLOR_LEVELS = {0.9, 0.5, 0.2, 0.001}

-- colours of a value scale, best band first
local TEXT_SCALE = { SCALE_BEST, SCALE_GOOD, RMS_Utils.COLOR.STAGE[2], RMS_Utils.COLOR.STAGE[3], RMS_Utils.COLOR.STAGE[4] }

---Returns the colour between two colours, at a share of the way
-- @param table from rgba color at 0
-- @param table to rgba color at 1
-- @param float share share of the way, 0 to 1
-- @return table color rgba color
local function mixColors(from, to, share)
    local mixed = {}
    for channel = 1, 4 do
        mixed[channel] = from[channel] + (to[channel] - from[channel]) * share
    end
    return mixed
end

---Returns the colour of a value on a five colour scale cut by four limits
-- @param table scale the five colours, best first
-- @param table limits the four limits
-- @param integer direction 1 when a higher value is better, -1 when a lower one is
-- @param float value value
-- @param boolean? smooth true to blend between the colours
-- @return float r red
-- @return float g green
-- @return float b blue
-- @return float a alpha
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
-- @param float value value
-- @param float ideal first threshold
-- @param float high second threshold
-- @param float mid third threshold
-- @param float low fourth threshold
-- @param boolean? smooth true to blend between the colours
-- @return float r red
-- @return float g green
-- @return float b blue
-- @return float a alpha
function RMS_Utils.getValueColor(value, ideal, high, mid, low, smooth)
    return getBandColor(TEXT_SCALE, { ideal, high, mid, low }, 1, value, smooth)
end

---Returns the colour of a gauge fill
-- @param float value value
-- @param float ideal first threshold
-- @param float high second threshold
-- @param float mid third threshold
-- @param float low fourth threshold
-- @param boolean? smooth true to blend between the colours
-- @return float r red
-- @return float g green
-- @return float b blue
-- @return float a alpha
function RMS_Utils.getGaugeColor(value, ideal, high, mid, low, smooth)
    local green = RMS_Utils.COLOR.HIGHLIGHT
    local STAGE = RMS_Utils.COLOR.STAGE
    return getBandColor({ green, green, STAGE[2], STAGE[3], STAGE[4] }, { ideal, high, mid, low }, 1, value, smooth)
end

---Returns the colour of a condition, grey while the inspection is incomplete
-- @param float? condition condition, 0 to 1
-- @param boolean isCompleteInspection true after a complete inspection
-- @return float r red
-- @return float g green
-- @return float b blue
-- @return float a alpha
function RMS_Utils.getConditionColor(condition, isCompleteInspection)
    if isCompleteInspection == nil then
        return unpack(RMS_Utils.COLOR.TEXT_DIM)
    end
    local ideal, high, mid, low = unpack(RMS_Utils.CONDITION_LEVELS)
    return RMS_Utils.getValueColor(condition, ideal, high, mid, low, false)
end

---Lists the parts the workshop's repairs fitted after a report
-- @param table vehicle vehicle
-- @param table report log entry of the report
-- @return table fitted true by part id
local function getPartsFittedSince(vehicle, report)
    local R, fitted, isAfter = RealisticMechanicalSystems, {}, false
    for _, entry in ipairs(vehicle.spec_RealisticMechanicalSystems.maintenanceLog) do
        if isAfter and entry.type == R.STATUS.REPAIR then
            local reached = entry.conditionData.selectedBreakdowns
            for _, line in ipairs(entry.invoice or {}) do
                if (line.kind == "repair" or line.kind == "preventive") and (line.repairType or entry.optionOne) ~= R.REPAIR_TYPES.LOW
                    and (entry.isCompleted or line.kind == "repair" and table.hasElement(reached, line.key)) then
                    for _, parts in ipairs({ line.ownParts or { line.key }, line.kitParts or {}, line.wornParts or {} }) do
                        for _, partId in ipairs(parts) do
                            fitted[partId] = true
                        end
                    end
                end
            end
        end
        isAfter = isAfter or entry == report
    end
    return fitted
end

---Returns the rank of a part row: failed, worn, replaced, measured, unmeasured
-- @param table row part row
-- @return integer rank rank, 0 first
local function getPartRowRank(row)
    if row.isReplaced then
        return 2
    elseif row.condition == nil then
        return 4
    elseif row.isFailed then
        return 0
    elseif row.isWorn then
        return 1
    end
    return 3
end

---Returns the system and part rows of an inspection report, and the foot text
-- @param table vehicle vehicle
-- @param table report log entry of the report
-- @param table systems systems of the report
-- @param boolean isMeasured true for a complete report
-- @param boolean isOutdated true for a report out of date
-- @param string? openSystem system unfolded
-- @return table rows rows of the condition list
-- @return string footText text under the list
function RMS_Utils.getConditionRows(vehicle, report, systems, isMeasured, isOutdated, openSystem)
    local partsReport, partsHours = RealisticMechanicalSystems.getPartsReport(vehicle)
    local fitted = partsReport ~= nil and getPartsFittedSince(vehicle, partsReport) or {}
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
                local failed = partsReport.conditionData.activeBreakdowns
                for _, partId in ipairs(parts) do
                    local wear = partsReport.conditionData.partWear[partId]
                    if fitted[partId] then
                        table.insert(partRows, {kind = "part", name = RMS_Utils.getBreakdownPartName(partId, vehicle), isReplaced = true})
                    else
                        table.insert(partRows, {kind = "part", name = RMS_Utils.getBreakdownPartName(partId, vehicle),
                            condition = wear ~= nil and 1 - math.min(wear, 1) or nil, isFailed = wear ~= nil and failed[partId] ~= nil,
                            isWorn = wear ~= nil and RMS_Utils.getIsPartWorn(partId, wear)})
                    end
                end
                table.sort(partRows, function(a, b)
                    local rankA, rankB = getPartRowRank(a), getPartRowRank(b)
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

---Fills a system row of a condition card
-- @param table cell cell to fill
-- @param table row system row
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

---Fills a part row of a condition card
-- @param table cell cell to fill
-- @param table row part row
local function populateConditionPartCell(cell, row)
    local nameElement, stateElement, valueElement = cell:getAttribute("name"), cell:getAttribute("state"), cell:getAttribute("value")
    if cell.rmsStateRight == nil then
        cell.rmsValueColor = {unpack(valueElement.textColor)}
        cell.rmsStateWidth = stateElement.size[1]
        cell.rmsStateRight = stateElement.position[1] + cell.rmsStateWidth
        cell.rmsNameGap = 6 * g_pixelSizeScaledX
    end

    local stateText, color = "", cell.rmsValueColor
    if row.isReplaced then
        stateText, color = g_i18n:getText("rms_fleet_part_replaced"), RMS_Utils.COLOR.HIGHLIGHT
    elseif row.condition == nil then
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
-- @param table cell cell to fill
-- @param table row row
function RMS_Utils.populateConditionCell(cell, row)
    if row.kind == "system" then
        populateConditionSystemCell(cell, row)
    else
        populateConditionPartCell(cell, row)
    end
end

---Reloads a list, each shown row taking the template it now needs
-- @param table list list
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

---Returns the colour of a service level, grey while the inspection is incomplete
-- @param float? service service level
-- @param boolean isCompleteInspection true after a complete inspection
-- @return float r red
-- @return float g green
-- @return float b blue
-- @return float a alpha
function RMS_Utils.getServiceColor(service, isCompleteInspection)
    if isCompleteInspection == nil then
        return unpack(RMS_Utils.COLOR.TEXT_DIM)
    end

    local ideal, high, mid, low = unpack(SERVICE_COLOR_LEVELS)
    return RMS_Utils.getValueColor(RMS_Utils.getServiceIntervalRemainingRatio(service), ideal, high, mid, low, isCompleteInspection)
end

---Returns the colour of a value against four ascending thresholds
-- @param float value value
-- @param float ideal first threshold
-- @param float low second threshold
-- @param float mid third threshold
-- @param float high fourth threshold
-- @param boolean? smooth true to blend between the colours
-- @return float r red
-- @return float g green
-- @return float b blue
-- @return float a alpha
function RMS_Utils.getValueColorInverted(value, ideal, low, mid, high, smooth)
    return getBandColor(TEXT_SCALE, { ideal, low, mid, high }, -1, value, smooth)
end

local SAVEGAME_OPTIONAL_FLOAT_SENTINEL = -1

---Converts a saved flag to a boolean: a boolean, a number, "true" or "false"
-- @param any value flag
-- @param boolean defaultValue value when nil
-- @return boolean value boolean
function RMS_Utils.normalizeBoolValue(value, defaultValue)
    local kind = type(value)
    if kind == "nil" then
        return defaultValue
    elseif kind == "number" then
        return value ~= 0
    elseif kind == "string" then
        return value == "true"
    end
    return value
end


---Encodes a float that may be absent
-- @param float? value value
-- @return float encoded value, negative when absent
function RMS_Utils.encodeOptionalFloat(value)
    return value ~= nil and tonumber(value) or SAVEGAME_OPTIONAL_FLOAT_SENTINEL
end

---Decodes a float that may be absent, negative meaning absent
-- @param any value encoded value
-- @return float? value value, nil when absent
function RMS_Utils.decodeOptionalFloat(value)
    local number = tonumber(value)
    if number ~= nil and not (number < 0) then
        return number
    end
    return nil
end

---Splits a comma separated string into its trimmed, non empty items
-- @param string? csvString comma separated string
-- @return table items items
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
-- @param table effects active effects
-- @return string serialized effects
function RMS_Utils.serializeEffectSnapshot(effects)
    local entries = {}
    for effectId, effectData in pairs(effects) do
        local value = type(effectData) == "table" and tonumber(effectData.value) or nil
        table.insert(entries, tostring(effectId) .. "|" .. (value ~= nil and string.format("%.6f", value) or ""))
    end
    return joinSaveEntries(entries)
end

---Reads the effects serializeEffectSnapshot wrote
-- @param string serialized serialized effects
-- @return table effects effects
function RMS_Utils.deserializeEffectSnapshot(serialized)
    local effects = {}
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
-- @param table systems system names by enum key
-- @param string systemKey key of the system
-- @return string name system name
function RMS_Utils.getSystemNameByKey(systems, systemKey)
    local wanted = string.lower(tostring(systemKey))
    for key, name in pairs(systems) do
        if string.lower(tostring(key)) == wanted then
            return name
        end
    end
    return tostring(systemKey)
end

---Writes the condition and switch of every system
-- @param table systems systems
-- @return string serialized systems
function RMS_Utils.serializeSystemsState(systems)
    local entries = {}
    for systemKey, systemData in pairs(systems) do
        table.insert(entries, string.format("%s|%.6f|%d", tostring(systemKey), systemData.condition, toFlag(systemData.enabled)))
    end
    return joinSaveEntries(entries)
end

---Reads the systems written by serializeSystemsState, older saves too
-- @param string serialized serialized systems
-- @return table systems systems
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
-- @param table systems systems
-- @return table snapshot condition by system
function RMS_Utils.createSystemsSnapshot(systems)
    local snapshot = {}
    for systemKey, systemData in pairs(systems) do
        snapshot[systemKey] = { condition = systemData.condition, enabled = systemData.enabled }
    end
    return snapshot
end

---Writes a map of numbers as key|value entries
-- @param table? valueMap numbers by key
-- @return string serialized map
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

---Reads a map written by serializeNumericMap
-- @param string serialized serialized map
-- @return table values numbers by key
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
-- @param table vehicle vehicle
-- @param string textKey l10n key of the system
-- @return string textKey l10n key on this vehicle
function RMS_Utils.getSystemLabel(vehicle, textKey)
    if vehicle.spec_RealisticMechanicalSystems.isElectricVehicle then
        return ELECTRIC_SYSTEM_LABELS[textKey] or textKey
    end
    return textKey
end

---Returns the system key behind a system name
-- @param table systems system names by enum key
-- @param string? systemName system name
-- @return string key key of the system
function RMS_Utils.getSystemKey(systems, systemName)
    local key = RMS_Utils.getKeyByValue(systems, systemName) or ""
    return string.lower(key)
end

---Returns a real price in game money, scaled by the economic difficulty
-- @param float realPrice price
-- @return float price price in game money
function RMS_Utils.getGamePrice(realPrice)
    return realPrice * (EconomyManager.getCostMultiplier() / EconomyManager.COST_MULTIPLIER[EconomicDifficulty.NORMAL])
end

---Returns the share of its price a machine keeps at an age and hours of work
-- @param table vehicle vehicle
-- @param float age age (years)
-- @param float workHours hours of work of a real machine
-- @return float share share of the price
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

---Returns the market value of a machine, its repairs and repaint taken off
-- @param table vehicle vehicle
-- @return float value value
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
-- @param table vehicle vehicle
-- @param boolean isDirectSell true at the dealer
-- @return float? value payment, nil when the machine is not owned
function RMS_Utils.getResaleValue(vehicle, isDirectSell)
    if vehicle.propertyState ~= VehiclePropertyState.OWNED then
        return nil
    end
    local multiplier = isDirectSell and EconomyManager.DIRECT_SELL_MULTIPLIER or 1
    return math.min(math.floor(vehicle:getSellPrice() * multiplier), vehicle:getPrice())
end

---Returns the hours of the hour meter, to the tenth, on any machine
-- @param table vehicle vehicle
-- @return float hours floored to the tenth
function RMS_Utils.getHourMeter(vehicle)
    return math.floor(vehicle:getOperatingTime() / 360000) / 10
end

---Returns what a vehicle card lists: age, hours, distance or condition, value
-- @param table vehicle vehicle
-- @param boolean isTracked true when RMS tracks the vehicle
-- @param boolean isDirectSell true for the dealer's resale value
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
-- @param table rows rows
-- @param table vehicle vehicle
-- @param boolean isTracked true when RMS tracks the vehicle
-- @param boolean isDirectSell true for the dealer's resale value
function RMS_Utils.writeVehicleFacts(rows, vehicle, isTracked, isDirectSell)
    for index, fact in ipairs(RMS_Utils.getVehicleFacts(vehicle, isTracked, isDirectSell)) do
        local row = rows[index]
        local icon = row:getDescendantByName("icon")
        icon:setVisible(not fact.isOdometer)
        row:getDescendantByName("badge"):setVisible(fact.isOdometer == true)
        if not fact.isOdometer then
            icon:setImageSlice(nil, fact.icon)
        end
        RMS_Utils.writeRow(row, fact.label, fact.value)
    end
end

---Writes a row cloned from a template, its pill closed on the value
-- @param table row row
-- @param string labelText label
-- @param string valueText value
function RMS_Utils.writeRow(row, labelText, valueText)
    RMS_Utils.fitRowValue(row:getDescendantByName("label"), row:getDescendantByName("pill"), row:getDescendantByName("value"), labelText, valueText)
end

---Returns the share of the machine a system weighs among its enabled systems
-- @param table vehicle vehicle
-- @param string? systemName system name
-- @param table systems system names by enum key
-- @return float share share, 0 to 1
function RMS_Utils.getEffectiveSystemWeight(vehicle, systemName, systems)
    if type(systemName) ~= "string" then
        return 0
    end

    local spec = vehicle.spec_RealisticMechanicalSystems
    local systemKey = resolveVehicleSystemKey(spec.systems, systemName, systems)
    local systemData = spec.systems[systemKey]
    if systemData == nil or not systemData.enabled then
        return 0
    end

    local weights, total = RMS_Config.CORE.SYSTEM_WEIGHTS, 0
    for key, data in pairs(spec.systems) do
        if data.enabled then
            total = total + weights[key]
        end
    end
    return weights[systemKey] / total
end

---Returns the enabled systems whose condition permits an overhaul
-- @param table vehicle vehicle
-- @return table systems system names
function RMS_Utils.getEligibleOverhaulSystems(vehicle)
    local values = {}
    for _, systemName in ipairs(RMS_Utils.getOverhaulSystems(vehicle)) do
        local systemData = vehicle.spec_RealisticMechanicalSystems.systems[RMS_Utils.getSystemKey(RealisticMechanicalSystems.SYSTEMS, systemName)]
        if systemData.condition < 0.5 then
            values[#values + 1] = systemName
        end
    end
    return values
end

---Returns the systems an overhaul works on
-- @param table vehicle vehicle
-- @return table systems system names
function RMS_Utils.getOverhaulSystems(vehicle)
    local values = {}
    for _, systemName in ipairs(RealisticMechanicalSystems.SYSTEMS_ORDER) do
        if RMS_Utils.getEffectiveSystemWeight(vehicle, systemName, RealisticMechanicalSystems.SYSTEMS) > 0 then
            values[#values + 1] = systemName
        end
    end
    return values
end

---Copies the entries of a table, an empty table for anything else
-- @param any original value
-- @return table copy copy
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
-- @param any original value
-- @param table? seen tables already copied
-- @return any copy copy
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
-- @param table? invoice invoice lines
-- @return string serialized kind, key, mode, liters and price of each line
function RMS_Utils.serializeInvoice(invoice)
    local lines = {}
    for _, line in ipairs(invoice or {}) do
        local text = string.format("%s,%s,%s,%.6f,%.4f,%s", tostring(line.kind or ""), tostring(line.key or ""),
            tostring(line.mode or ""), tonumber(line.liters) or 0, tonumber(line.price) or 0, line.warrantyReason or "")
        if line.labour ~= nil then
            text = text .. string.format(",%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%s,%s,%s,%s,%s", line.labour, line.hours, line.parts,
                line.kit, line.worn, line.gross, line.partType or "", line.repairType or "", table.concat(line.ownParts, "|"),
                table.concat(line.kitParts, "|"), table.concat(line.wornParts, "|")) .. (line.months ~= nil and "," .. line.months or "")
        end
        lines[#lines + 1] = text
    end
    return table.concat(lines, ";")
end

---Splits a list of part ids written by serializeInvoice
-- @param string? text part ids
-- @return table parts part ids
local function splitParts(text)
    local parts = {}
    for partId in string.gmatch(text or "", "[^|]+") do
        table.insert(parts, partId)
    end
    return parts
end

---Rebuilds invoice lines from their serialized form
-- @param string? serialized serialized invoice
-- @return table? invoice invoice lines, nil without one
function RMS_Utils.deserializeInvoice(serialized)
    if serialized == nil or serialized == "" then
        return nil
    end

    local invoice = {}
    for value in string.gmatch(serialized, "[^;]+") do
        local fields = {}
        for field in string.gmatch(value .. ",", "([^,]*),") do
            table.insert(fields, field)
        end
        local kind = fields[1]
        if kind ~= nil and kind ~= "" then
            local line = { kind = kind, key = fields[2] or "", mode = fields[3] ~= "" and fields[3] or nil,
                liters = tonumber(fields[4]) or 0, price = tonumber(fields[5]) or 0,
                warrantyReason = fields[6] ~= nil and fields[6] ~= "" and fields[6] or nil }
            -- the costs of a repair, logged since the quote shows them
            if #fields >= 17 then
                line.labour, line.hours, line.parts = tonumber(fields[7]), tonumber(fields[8]), tonumber(fields[9])
                line.kit, line.worn, line.gross = tonumber(fields[10]), tonumber(fields[11]), tonumber(fields[12])
                line.partType, line.repairType = fields[13], fields[14]
                line.ownParts, line.kitParts, line.wornParts = splitParts(fields[15]), splitParts(fields[16]), splitParts(fields[17])
                line.months = tonumber(fields[18])
            end
            table.insert(invoice, line)
        end
    end
    return invoice
end

---Serializes one maintenance log entry into a string
-- @param table entry log entry
-- @return string serialized log entry
function RMS_Utils.serializeMaintenanceLogEntry(entry)
    local fields = {}
    for index, field in ipairs(LOG_ENTRY_FIELDS) do
        fields[index] = field.write(entry, entry.conditionData)
    end
    return table.concat(fields, "|")
end

---Rebuilds a maintenance log entry from its serialized form
-- @param string serialized serialized log entry
-- @return table entry log entry
function RMS_Utils.deserializeMaintenanceLogEntry(serialized)
    local fields = {}
    for field in string.gmatch(serialized .. "|", "(.-)|") do
        table.insert(fields, field)
    end

    local entry = { conditionData = {} }
    for index, field in ipairs(LOG_ENTRY_FIELDS) do
        if field.read ~= nil then
            field.read(entry, entry.conditionData, fields[index])
        end
    end
    return entry
end

---Returns the interface of the harvesting mod, kept in its own mod table
-- @return table? api interface, nil without the mod
function RMS_Utils.getHarvestModApi()
    local modEnv = _G.FS25_RealisticHarvesting
    return modEnv ~= nil and modEnv.RHM_Api or nil
end

---Tells whether the CVT addon mod drives the transmission of this vehicle
-- @param table? vehicle vehicle
-- @return boolean hasAddon true when it does
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
-- @param table vehicle vehicle
-- @return boolean hasCVT true with one
function RMS_Utils.hasCVTTransmission(vehicle)
    if vehicle == nil or vehicle.getMotor == nil then
        return false
    end
    local motor = vehicle:getMotor()
    return motor ~= nil and motor.minForwardGearRatio ~= nil and not RMS_Utils.getIsElectricVehicle(vehicle)
end

---Tells whether the vehicle runs on electricity alone
-- @param table vehicle vehicle
-- @return boolean isElectric true for an electric vehicle
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

---Tells whether a combustion engine has an ECU, by its AdBlue and its year
-- @param boolean usesDef true when it burns AdBlue
-- @param any year production year
-- @param boolean isYearKnown true when the year is known
-- @return boolean hasECU true with an ECU
function RMS_Utils.getHasEngineECU(usesDef, year, isYearKnown)
    return usesDef or isYearKnown and (tonumber(year) or 0) >= 2000
end

---Tells whether an engine uses the shared ECU profile
-- @param table vehicle vehicle
-- @return boolean usesProfile true when it does
function RMS_Utils.getUsesEngineECUProfile(vehicle)
    local spec = vehicle ~= nil and vehicle.spec_RealisticMechanicalSystems or nil
    if spec == nil or RMS_Utils.getIsElectricVehicle(vehicle) then
        return false
    end

    local motorized = vehicle.spec_motorized
    local consumers = motorized ~= nil and motorized.consumersByFillTypeName or nil
    return RMS_Utils.getHasEngineECU(consumers ~= nil and consumers.DEF ~= nil, spec.year, spec.yearIsKnown)
end

---Returns the fan drive type for the machine's generation
-- @param table vehicle vehicle
-- @return string fanDrive "ELECTRIC", "ELECTRONIC", "VISCOUS" or "DIRECT"
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
-- @param table vehicle vehicle
-- @return float threshold ratio the effect starts at
-- @return float fullEffect ratio of the full effect
function RMS_Utils.getHeavyTrailerRatioLevels(vehicle)
    local C = RMS_Config.CORE.CHASSIS_FACTOR_DATA
    if vehicle.spec_RealisticMechanicalSystems.isTruck then
        return C.HEAVY_TRAILER_TRUCK_MASS_RATIO_THRESHOLD, C.HEAVY_TRAILER_TRUCK_MASS_RATIO_FULL_EFFECT
    end
    local powerPerOwnMass = vehicle:getMotor().peakMotorPower * 1.36 / math.max(vehicle:getTotalMass(true), 0.01)
    return powerPerOwnMass / C.HEAVY_TRAILER_MASS_RATIO_THRESHOLD, powerPerOwnMass / C.HEAVY_TRAILER_MASS_RATIO_FULL_EFFECT
end

---Builds a logger printing only while debug mode is on
-- @param string prefix prefix of the lines
-- @return function logger logger
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

---Closes a pill on its value, its label shrunk to leave it room
-- @param table pill pill
-- @param table value text of the value
-- @param string? anchor "center" to centre the pill, else it keeps its right edge
-- @param table? label text of the label
local function fitPill(pill, value, anchor, label)
    -- the boxes the XML declares, read before the first fit moves them
    if pill.rmsPillBox == nil then
        pill.rmsPillBox = { x = pill.position[1], width = pill.size[1], padding = value.position[1] - pill.position[1],
            labelGap = label ~= nil and pill.position[1] - label.position[1] - label.size[1] or nil }
    end
    local box = pill.rmsPillBox
    ---Sets the width of the pill and places it by its anchor
    -- @param float width width (screen)
    local function close(width)
        local x = anchor == "center" and box.x + (box.width - width) / 2 or box.x + box.width - width
        pill:setPosition(x, nil)
        pill:setSize(width, nil)
        -- a scrolling text divides by its width each time it moves
        value:setSize(width - box.padding * 2, nil)
        value:setPosition(x + box.padding, nil)
    end
    ---Returns the width of the pill closed on its value
    -- @return float width width (screen)
    local function getClosedWidth()
        return math.min(box.width, value:getTextWidth(true) * 1.001 + box.padding * 2)
    end

    close(box.width)
    close(getClosedWidth())
    if label == nil then
        return
    end
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
-- @param table pill pill
-- @param table value text of the value
-- @param string? anchor "center" to centre the pill, else it keeps its right edge
-- @param string valueText value
function RMS_Utils.fitValuePill(pill, value, anchor, valueText)
    value:setText(valueText)
    fitPill(pill, value, anchor)
end

---Writes a row, label and value, and fits its pill
-- @param table label text of the label
-- @param table pill pill
-- @param table value text of the value
-- @param string labelText label
-- @param string valueText value
function RMS_Utils.fitRowValue(label, pill, value, labelText, valueText)
    label:setText(labelText)
    value:setText(valueText)
    fitPill(pill, value, nil, label)
end

---Fits every pill of a screen on the value written after it
-- @param table element screen or branch
function RMS_Utils.fitValuePills(element)
    local children = element.elements
    for index, child in ipairs(children) do
        RMS_Utils.fitValuePills(child)
        -- a pill declares its anchor in its profile, its value follows it
        local anchor = g_gui:getProfile(child.profile):getValue("rmsPillAnchor")
        if anchor ~= nil then
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

---Scrolls a text at the shared speed
-- @param table element scrolling text
-- @param float dt time since the last frame (ms)
local function updateScrollingText(element, dt)
    TextElement.update(element, dt * RMS_Utils.SCROLL_SPEED)
end

---Places a scrolling text, its offset rewound
-- @param table element scrolling text
local function updateScrollingTextPosition(element)
    TextElement.updateAbsolutePosition(element)
    -- Rewind the native offset without advancing its retained clock
    TextElement.update(element, 0)
end

---Puts every scrolling text of a branch on the shared speed, cells included
-- @param table element branch
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
-- @param table? element branch
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
-- @param table button action button
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
-- @param table labelElement text of the label
-- @param table valueElement text of the value
-- @param string labelText label
-- @param string valueText value
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


---Gives the children of an element its selection, a row its highlight
-- @param table element element
-- @param table? row list row whose highlight the children take as their focus
function RMS_Utils.mirrorSelectionToChildren(element, row)
    for _, child in ipairs(element.elements) do
        child.getIsSelected = function()
            return element:getIsSelected()
        end
        if row ~= nil then
            child.getIsFocused = function()
                return row:getIsSelected() or row:getIsHighlighted()
            end
        end
    end
end


---Returns the element of a column a row enters it at, from the left or the right
-- @param table rows rows of the column
-- @param integer rowIndex row
-- @param boolean isFromRight true when entering from the right
-- @return table? element element, nil past the rows
local function getFocusColumnEntry(rows, rowIndex, isFromRight)
    if rows == nil then
        return nil
    end

    local row = rows[math.min(rowIndex, #rows)]
    return isFromRight and row[#row] or row[1]
end

---Links the focus over what a screen shows
-- @param table top element above the columns
-- @param table columns columns of rows of elements
-- @param table? preferred element to enter on
-- @return table? entry element the focus enters on
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
    if top ~= nil then
        FocusManager:linkElements(top, FocusManager.TOP, nil)
        FocusManager:linkElements(top, FocusManager.BOTTOM, entry ~= top and entry or first)
    end
    return entry
end

---Registers a cloned branch in the focus, each element with a new id
-- @param table element branch
function RMS_Utils.registerFocus(element)
    -- a clone carries the focus ids of its source, which the manager skips
    element.focusId = nil
    for _, child in ipairs(element:getDescendants()) do
        child.focusId = nil
    end
    FocusManager:loadElementFromCustomValues(element)
end

---Puts a screen in its own focus, the frames placed in it included
-- @param table screen screen
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
-- @param table? entry element to hand it to
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
-- @return string slice slice
function RMS_Utils.getCurrencySlice()
    return CURRENCY_SLICES[g_gameSettings:getValue("moneyUnit")]
end

---Shows the glyph of the money unit the player set
-- @param table element picture
function RMS_Utils.setCurrencyIcon(element)
    element:setImageSlice(nil, RMS_Utils.getCurrencySlice())
end

---Writes the picture, the brand and the model of a vehicle
-- @param table vehicle vehicle
-- @param table imageElement picture
-- @param table brandElement text of the brand
-- @param table modelElement text of the model
function RMS_Utils.setVehicleIdentity(vehicle, imageElement, brandElement, modelElement)
    imageElement:setImageFilename(vehicle:getImageFilename())
    local brand = g_brandManager:getBrandByIndex(vehicle:getBrand())
    brandElement:setText(brand.name ~= "NONE" and brand.title or "")
    modelElement:setText(vehicle:getName())
end

---Returns what the last inspection report reads, as the workshop shows it
-- @param table vehicle vehicle
-- @return table reading texts, colours and ratios of the reading
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
-- @param table box button bar
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
