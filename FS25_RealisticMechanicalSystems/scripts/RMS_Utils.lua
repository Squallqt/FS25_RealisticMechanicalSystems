-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---Shared RMS utilities.
RMS_Utils = {}

---Returns the container locked on a hook lift
-- @param table? vehicle vehicle
-- @return table? container locked container
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
-- @param float dt time since last call in ms
-- @param float meanTimeInMinutes mean time between events in minutes
-- @return float chance probability for this frame
function RMS_Utils.getChancePerFrameFromMeanTime(dt, meanTimeInMinutes)
    if meanTimeInMinutes <= 0 then
        return 1.0
    end
    local meanTimeInMs = meanTimeInMinutes * 60 * 1000
    return dt / meanTimeInMs
end

---Tells whether the vehicle drives a PTO output
-- @param table? vehicle vehicle
-- @return boolean hasCapability true with a PTO output
function RMS_Utils.hasPtoOutputCapability(vehicle)
    local ptoSpec = vehicle ~= nil and vehicle.spec_powerTakeOffs or nil
    if ptoSpec == nil or type(ptoSpec.outputPowerTakeOffs) ~= "table" then
        return false
    end

    return next(ptoSpec.outputPowerTakeOffs) ~= nil
end

---Tells whether an attacher joint lifts hydraulically
-- @param table? jointDesc attacher joint description
-- @return boolean isLift true for a lifting joint
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
-- @param table? vehicle vehicle
-- @return boolean hasCapability true with a lifting joint
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
-- @param table? vehicle vehicle
-- @return boolean hasCapability true with an actuator
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

---Tells whether a connection hose entry carries hydraulics
local function getIsHydraulicConnectionEntry(entry)
    return type(entry) == "table"
        and type(entry.type) == "string"
        and string.sub(string.upper(entry.type), 1, 9) == "HYDRAULIC"
end

---Tells whether a moving tool is driven hydraulically
-- @param table? tool moving tool
-- @return boolean isHydraulic true for a hydraulic tool
function RMS_Utils.getIsHydraulicMovingTool(tool)
    return type(tool) == "table" and tool.playSound == true
end

---Tells whether the vehicle or an attached implement carries hydraulic hoses
-- @param table? vehicle vehicle
-- @param table? visited vehicles already walked
-- @return boolean hasCapability true with hoses
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
-- @param table? vehicle vehicle
-- @return boolean hasCapability true with hydraulics
function RMS_Utils.hasHydraulicCapability(vehicle)
    local visited = {}

    ---Tells whether this vehicle or one of its implements carries the capability
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
-- @param table? vehicle vehicle
-- @return boolean hasCapability true with a controllable target
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
-- @param table? vehicle vehicle
-- @param float totalTorque torque drawn by the implements
-- @return float utilization share of the capacity used
-- @return float motorSideTorque torque seen on the motor side
-- @return float nativeCapacityTorque torque the engine can pass
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
-- @param float utilization share of the PTO capacity used
-- @param table config PTO factor configuration
-- @return float factor load factor
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
-- @param table? vehicle vehicle
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
-- @param table? vehicle vehicle
-- @param table? engagementTorques rated torque per engaged implement
-- @param table? previousActiveLinks links active on the previous sample
-- @param float? rpmShare engine speed share above idle on the previous sample
-- @return float damage condition removed
-- @return boolean isShock true when one of them was engaged above idle
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
-- @param table? activeLinks links active now
-- @param table? previousActiveLinks links active on the previous frame
-- @return integer count number of new engagements
function RMS_Utils.getPtoEngagementTransitionCount(activeLinks, previousActiveLinks)
    local count = 0
    for consumer, _ in pairs(activeLinks or {}) do
        if previousActiveLinks == nil or previousActiveLinks[consumer] ~= true then
            count = count + 1
        end
    end
    return count
end

-- @param table tool moving tool
-- @return boolean isLoader true for a loader arm or tool
function RMS_Utils.getIsLoaderMovingTool(tool)
    return tool.axis == "AXIS_FRONTLOADER_ARM" or tool.axis == "AXIS_FRONTLOADER_TOOL"
end

-- @param table vehicle vehicle
-- @return table? output front output, nil without a separate front PTO
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

---Walks one PTO branch and adds its demand to the shared accumulator
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
                if isEngaged then
                    data.activeLinks[consumer] = true

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

-- @param table? vehicle vehicle
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
        isRaised = false
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
-- @param table? vehicle vehicle
-- @param boolean isTurnedOn true to turn them on
-- @param string? side "front", "rear", or nil for all outputs
-- @return boolean changed true when at least one implement changed
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

---Shows a level on the level gauge of a screen
-- @param table fillElement bar of the gauge
-- @param table underElement red end of the bar
-- @param float trackWidth width of the whole bar
-- @param float level fill ratio of the circuit
function RMS_Utils.setLevelGauge(fillElement, underElement, trackWidth, level)
    local fill, color = RMS_Fluids.getGaugeFill(level, RMS_Utils.COLOR.HIGHLIGHT)
    fillElement:setVisible(fill > 0)
    underElement:setVisible(fill <= 0)
    fillElement:setSize(GuiUtils.alignValueToScreenPixels(trackWidth * fill, true), nil)
    fillElement:setImageColor(nil, color[1], color[2], color[3], color[4])
end

-- @param float? level fluid level
-- @return float shortage 0 above that level, up to 1 on an empty circuit
function RMS_Utils.getFluidShortage(level)
    local start = RMS_Config.FLUIDS.LEVEL_MIN_MARK
    if start <= 0 then
        return 0
    end

    return math.clamp((start - math.clamp(tonumber(level) or 1, 0, 1)) / start, 0, 1)
end

---Returns the squared distance past a threshold, 0 on the safe side of it
-- @param float level value to rate
-- @param float threshold value the effect starts at
-- @param boolean lessIsWorse true when falling below the threshold is the bad direction
-- @param float? customMax value reaching the full effect
-- @return float multiplier effect multiplier
function RMS_Utils.calculateQuadraticMultiplier(level, threshold, lessIsWorse, customMax)
    if (lessIsWorse and level >= threshold) or (not lessIsWorse and level <= threshold) then
        return 0.0
    end
    if lessIsWorse then
        local lowerBound = tonumber(customMax)
        local denominator = threshold

        if lowerBound ~= nil and lowerBound < threshold then
            denominator = math.max(threshold - lowerBound, 0.0001)
            level = math.max(level, lowerBound)
        else
            denominator = math.max(threshold, 0.0001)
        end

        local normalizedValue = (threshold - level) / denominator
        return normalizedValue * normalizedValue
    else
        local normalizedValue = (level - threshold) / ((customMax or 1) - threshold)
        return normalizedValue * normalizedValue
    end
end

---Returns the lugging severity of a motor, high load at low rpm
-- @param table motor native vehicle motor
-- @param float motorLoad load applied to the affected system
-- @param float loadThreshold load below which lugging adds no wear
-- @return float severity factor between zero and one
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

-- @param string partId breakdown id of the part
-- @param float fromWear wear the part had
-- @param float toWear wear the part reaches
-- @return float probability failure probability over that wear
function RMS_Utils.getPartFailureChance(partId, fromWear, toWear)
    local C = RMS_Config.CORE
    local life = C.COMPONENT_LIVES[RMS_Breakdowns.BreakdownRegistry[partId].component]
    local lives = C.MACHINE_LIFE_HOURS / life.scale
    return 1 - math.exp((fromWear * lives) ^ life.shape - (toWear * lives) ^ life.shape)
end

---Returns a part's wear over the risk horizon; a lamp's only while lit
-- @param string partId breakdown id of the part
-- @return float wear wear over the horizon
function RMS_Utils.getPartRiskHorizon(partId)
    local C = RMS_Config.CORE
    if RMS_Breakdowns.BreakdownRegistry[partId].wearsWhile ~= nil then
        return C.RISK_HORIZON_WEAR * C.USED_VEHICLE_HISTORY.LIT_SHARE
    end
    return C.RISK_HORIZON_WEAR
end

---Returns a part's risk over the wear ahead, as a multiple of new
-- @param string partId breakdown id of the part
-- @param float wear wear of the part
-- @return float ratio risk over the wear ahead against that of a new part
function RMS_Utils.getPartRiskRatio(partId, wear)
    local horizon = RMS_Utils.getPartRiskHorizon(partId)
    return RMS_Utils.getPartFailureChance(partId, wear, wear + horizon) / RMS_Utils.getPartFailureChance(partId, 0, horizon)
end

-- @param string partId breakdown id of the part
-- @param float wear wear of the part
-- @return boolean isWorn true past its B10 life with its risk past the high ratio
function RMS_Utils.getIsPartWorn(partId, wear)
    return wear >= RMS_Utils.getPartB10Wear(partId) and RMS_Utils.getPartRiskRatio(partId, wear) >= RMS_Config.CORE.RISK_RATIO_HIGH
end

-- @param string partId breakdown id of the part
-- @return float wear B10 life as a share of the life of the machine
function RMS_Utils.getPartB10Wear(partId)
    local C = RMS_Config.CORE
    local life = C.COMPONENT_LIVES[RMS_Breakdowns.BreakdownRegistry[partId].component]
    return life.scale * (-math.log(1 - C.WORN_PART_FAILED_SHARE)) ^ (1 / life.shape) / C.MACHINE_LIFE_HOURS
end

---Returns a system's risk over the wear ahead, as a multiple of new
-- @param table vehicle vehicle
-- @param string systemKey system key
-- @param table partWear wear of each part, live or as a report measured it
-- @return float? ratio relative failure risk, nil without part wear
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
-- @param float? ratio risk against that of the same parts new
-- @return integer? tier 1 to 3, nil when no RMS assessment is available
function RMS_Utils.getBreakdownRiskTier(ratio)
    if ratio == nil then return nil end
    if ratio < RMS_Config.CORE.RISK_RATIO_MODERATE then return 1 end
    if ratio < RMS_Config.CORE.RISK_RATIO_HIGH then return 2 end
    return 3
end

---Formats an assessed risk as Low, Moderate or High
-- @param integer? tier recorded risk category
-- @return string text localized category, unknown for older reports
function RMS_Utils.formatBreakdownRisk(tier)
    local keys = {"low", "moderate", "high"}
    local key = keys[tier]
    return g_i18n:getText(key ~= nil and ("rms_report_risk_" .. key) or "rms_report_state_not_available")
end

---Splits a decimal hour count into whole hours and minutes
-- @param float? totalHours hours to split
-- @return integer hours whole hours
-- @return integer minutes remaining minutes
function RMS_Utils.convertHoursToHoursAndMinutes(totalHours)
    if totalHours == nil then
        return 0, 0
    end
    local totalMinutes = math.floor(math.max(totalHours, 0) * 60 + 0.5)
    return math.floor(totalMinutes / 60), totalMinutes % 60
end

---Resizes the money box around its label and its value
-- @param table? labelElement label element
-- @param table? valueElement value element
-- @param table? boxElement box element
-- @param table? bgElement background element
-- @param string labelText label text
-- @param string valueText value text
function RMS_Utils.updateMoneyBoxLayout(labelElement, valueElement, boxElement, bgElement, labelText, valueText)
    if labelElement == nil or valueElement == nil or boxElement == nil or bgElement == nil then
        return
    end

    if labelElement.setText ~= nil then
        labelElement:setText(tostring(labelText or ""))
    end
    if valueElement.setText ~= nil then
        valueElement:setText(tostring(valueText or ""))
    end

    if boxElement.invalidateLayout ~= nil then
        boxElement:invalidateLayout()
    end

    local targetWidth = nil
    if boxElement.flowSizes ~= nil then
        targetWidth = boxElement.flowSizes[1]
    end

    if targetWidth == nil or targetWidth <= 0 then
        return
    end

    local horizontalPadding = (bgElement.position[1] - boxElement.position[1]) * 2
    local bgHeight = (bgElement.size ~= nil and bgElement.size[2]) or ((boxElement.size ~= nil and boxElement.size[2]) or 0.03)
    targetWidth = targetWidth + horizontalPadding

    if bgElement.setSize ~= nil then
        bgElement:setSize(targetWidth, bgHeight)
    end

    if bgElement.invalidateLayout ~= nil then
        bgElement:invalidateLayout()
    end
end

---Fits the recap vehicle card beside an optional follow-up card.
-- @param table dialog workshop procedure dialog
-- @param boolean hasFollowUp whether the follow-up card is visible
function RMS_Utils.updateRecapVehicleCard(dialog, hasFollowUp)
    local cardWidth = hasFollowUp and dialog.recapAddonBlock.size[1] or dialog.recapQuoteBlock.size[1]
    local textWidth = hasFollowUp and dialog.recapAddon.size[1] or dialog.recapOptions.size[1]
    dialog.recapVehicleBlock:setSize(cardWidth, nil)
    dialog.recapVehicleSurface:setSize(cardWidth, nil)
    dialog.recapVehicleLayout:setSize(cardWidth, nil)
    dialog.recapVehicleLabel:setSize(textWidth, nil)
    dialog.recapVehicle:setSize(textWidth, nil)
    dialog.recapVehicleLayout:invalidateLayout()
end

---Renders a table as a readable string
-- @param any tbl table to render
-- @return string text rendered table
function RMS_Utils.tableToString(tbl)
    if not tbl or next(tbl) == nil then
        return "{}" 
    end
    
    local parts = {}
    for k, v in pairs(tbl) do
        local valueStr
        if type(v) == 'table' then
            valueStr = RMS_Utils.tableToString(v)
        else
            valueStr = tostring(v)
        end
        table.insert(parts, string.format("%s = %s", tostring(k), valueStr))
    end
    return "{ " .. table.concat(parts, ", ") .. " }"
end

---Returns the key holding a value in a table
-- @param table? tbl table to search
-- @param any value value to find
-- @return any? key matching key
function RMS_Utils.getKeyByValue(tbl, value)
    for key, val in pairs(tbl) do
        if val == value then
            return key
        end
    end
    return nil
end

---Tells whether at least one diagnosed breakdown is selected for repair
-- @param table? vehicle vehicle
-- @return boolean hasSelection true with a visible selected breakdown
function RMS_Utils.hasSelectedVisibleBreakdown(vehicle)
    local activeBreakdowns = vehicle ~= nil and vehicle.getActiveBreakdowns ~= nil and vehicle:getActiveBreakdowns() or nil
    for _, breakdown in pairs(activeBreakdowns or {}) do
        if breakdown.isVisible and breakdown.isSelectedForRepair then
            return true
        end
    end

    return false
end

-- @param table? items stage items, each common to every mode or tied to one by its branch
-- @param table breakdown active breakdown
-- @return table items items of the breakdown's mode
function RMS_Utils.getBranchItems(items, breakdown)
    local branchItems = {}
    for _, item in ipairs(items or {}) do
        if item.branch == nil or item.branch == breakdown.branch then
            table.insert(branchItems, item)
        end
    end
    return branchItems
end

---Serializes the active breakdowns into one string
-- @param table? breakdownsTable active breakdowns
-- @return string serialized serialized breakdowns
function RMS_Utils.serializeBreakdowns(breakdownsTable)
    local parts = {}
    for id, breakdown in pairs(breakdownsTable) do
        local visible = breakdown.isVisible and 1 or 0
        local selected = breakdown.isSelectedForRepair and 1 or 0
        local active = breakdown.isActive ~= false and 1 or 0
        local resumeTimer = math.max(tonumber(breakdown.resumeTimer) or 0, 0)
        local source = math.max(math.floor(tonumber(breakdown.source) or 0), 0)
        local effectTargetIndex = math.max(math.floor(tonumber(breakdown.effectTargetIndex) or 0), 0)
        local branch = math.max(math.floor(tonumber(breakdown.branch) or 0), 0)

        local system = string.format("%s,%d,%.2f,%d,%d,%d,%.2f,%d,%d,%d,%d,%s", id, breakdown.stage, breakdown.progressTimer or 0,
            visible, selected, active, resumeTimer, source, effectTargetIndex, branch,
            breakdown.warrantyServiceOverdue == nil and -1 or breakdown.warrantyServiceOverdue and 1 or 0, breakdown.usedPartHours or "")
        table.insert(parts, system)
    end
    return table.concat(parts, ";")
end

---Serializes a date into one string
-- @param table? dateTable date holding day, month and year
-- @return string serialized serialized date
function RMS_Utils.serializeDate(dateTable)
    if dateTable == nil or dateTable.day == nil then
        return ""
    end
    return string.format("%d,%d,%d", dateTable.day, dateTable.month, dateTable.year)
end

---Escapes the delimiters of a string so it survives serialization
-- @param any value value to escape
-- @return string text escaped value
function RMS_Utils.encodeDelimitedString(value)
    if value == nil then
        return ""
    end

    return (tostring(value):gsub("([^%w%-%._~])", function(char)
        return string.format("%%%02X", string.byte(char))
    end))
end

---Restores the delimiters escaped by the encoder
-- @param any value escaped value
-- @return string text restored value
function RMS_Utils.decodeDelimitedString(value)
    if value == nil or value == "" then
        return ""
    end

    return (tostring(value):gsub("%%(%x%x)", function(hex)
        return string.char(tonumber(hex, 16))
    end))
end

---Rebuilds a date from its serialized form
-- @param string? dateString serialized date
-- @return table? date date holding day, month and year
function RMS_Utils.deserializeDate(dateString)
    if dateString == nil or dateString == "" then
        return {}
    end
    
    local day, month, year = string.match(dateString, "([^,]+),([^,]+),([^,]+)")
    if day and month and year then
        return {
            day = tonumber(day),
            month = tonumber(month),
            year = tonumber(year)
        }
    end
    return {}
end

---Rebuilds the active breakdowns from their serialized form
-- @param string? breakdownString serialized breakdowns
-- @return table breakdowns active breakdowns
function RMS_Utils.deserializeBreakdowns(breakdownString)
    local breakdowns = {}
    if breakdownString == nil or breakdownString == "" then
        return breakdowns
    end
    
    for part in string.gmatch(breakdownString, "([^;]+)") do
        local id, stage, timer, isVisible, isSelected, isActive, resumeTimer, source, effectTargetIndex, branch, warrantyServiceOverdue, usedPartHours =
            string.match(
                part,
                "([^,]+),([^,]+),([^,]+),([^,]+),([^,]+),([^,]+),([^,]+),([^,]+),?([^,]*),?([^,]*),?([^,]*),?([^,]*)"
            )
        
        if id then
            breakdowns[id] = {
                stage = tonumber(stage),
                progressTimer = tonumber(timer),
                isVisible = (tonumber(isVisible) == 1),
                isSelectedForRepair = (tonumber(isSelected) == 1),
                isActive = (tonumber(isActive) == 1),
                resumeTimer = math.max(tonumber(resumeTimer) or 0, 0),
                source = tonumber(source) or RealisticMechanicalSystems.BREAKDOWN_SOURCES.RANDOM,
                effectTargetIndex = math.max(math.floor(tonumber(effectTargetIndex) or 0), 0),
                branch = math.max(math.floor(tonumber(branch) or 0), 0),
                warrantyServiceOverdue = tonumber(warrantyServiceOverdue) == 1,
                usedPartHours = tonumber(usedPartHours)
            }
            if tonumber(warrantyServiceOverdue) == -1 then breakdowns[id].warrantyServiceOverdue = nil end
        end
    end
    return breakdowns
end


---Formats a finish hour, adding the days crossed before it
-- @param float? finishTime hour of the day
-- @param integer? daysToAdd whole days crossed
-- @return string text formatted finish time
function RMS_Utils.formatFinishTime(finishTime, daysToAdd)
   if finishTime == nil then
        return ""
    end
    
    local finishTimeHours, finishTimeMinutes = RMS_Utils.convertHoursToHoursAndMinutes(finishTime)
    daysToAdd = (daysToAdd or 0) + math.floor(finishTimeHours / 24)
    finishTimeHours = finishTimeHours % 24
    local daysText = ""

    if daysToAdd == 1 then
        daysText = g_i18n:getText('rms_spec_tomorrow_at')
    elseif daysToAdd == 2 then
        daysText =  g_i18n:getText('rms_spec_day_after_tomorrow_at')
    elseif daysToAdd > 2 then
        daysText = g_i18n:getText('rms_spec_in_days_at')
        daysText = string.gsub(daysText, "{days}", daysToAdd)
    end

    return string.format("%s%02d:%02d", daysText, finishTimeHours, finishTimeMinutes)
end

---Returns the current primary keyboard binding of an action
-- @param string actionName input action name
-- @param string? fallbackText text returned when no keyboard binding can be resolved
-- @return string bindingText localized key names joined as a chord
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
-- @return float temperature ambient temperature in degrees
function RMS_Utils.getAmbientTemperature()
    return g_currentMission.environment.weather:getCurrentTemperature()
end

---Formats a duration in hours and minutes
-- @param float? duration duration in hours
-- @return string text formatted duration
function RMS_Utils.formatDuration(duration)
    if duration == nil then
        return ""
    end
    local durationHours, durationMinutes = RMS_Utils.convertHoursToHoursAndMinutes(duration)
    local days = math.floor(durationHours / 24)
    local daysText = ""
    if days > 0 then
        durationHours = durationHours - days * 24
        local dayKey = days == 1 and 'rms_spec_day_one' or 'rms_spec_day_s'
        daysText = string.format("%s %s ", days, g_i18n:getText(dayKey))
    end

    local durationText = ""
    if durationHours == 0 and durationMinutes > 0 then
        local minuteKey = durationMinutes == 1 and 'rms_spec_minute_one' or 'rms_spec_minute_s'
        durationText = string.format(g_i18n:getText('rms_spec_duration_format_minutes'), durationMinutes, g_i18n:getText(minuteKey))
    elseif durationHours > 0 and durationMinutes == 0 then
        local hourKey = durationHours == 1 and 'rms_spec_hour_one' or 'rms_spec_hour_s'
        durationText = string.format(g_i18n:getText('rms_spec_duration_format_hours'), durationHours, g_i18n:getText(hourKey))
    elseif durationHours > 0 and durationMinutes > 0 then
        local hourKey = durationHours == 1 and 'rms_spec_hour_one' or 'rms_spec_hour_s'
        local minuteKey = durationMinutes == 1 and 'rms_spec_minute_one' or 'rms_spec_minute_s'
        local hoursText = string.format(g_i18n:getText('rms_spec_duration_format_hours'), durationHours, g_i18n:getText(hourKey))
        local minutesText = string.format(g_i18n:getText('rms_spec_duration_format_minutes'), durationMinutes, g_i18n:getText(minuteKey))
        durationText = string.format(g_i18n:getText('rms_spec_duration_format_combined'), hoursText, minutesText)
    end

    return string.format("%s%s", daysText, durationText)
end


RMS_Utils.CONDITION_LEVELS = {0.8, 0.6, 0.4, 0.2}

local CONDITION_STATE_NAMES = {"EXCELLENT", "GOOD", "NORMAL", "BAD", "TERRIBLE"}

local SERVICE_LEVELS = {0.9, 0.7, 0.6, 0.5}

local SERVICE_STATE_NAMES = {"OPTIMAL", "SERVICE_GOOD", "RECOMMENDED", "REQUIRED", "OVERDUE"}

---Returns the tier a condition falls in, 1 being the best
-- @param float? condition condition level
-- @return integer tier condition tier
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
-- @param float? condition condition level
-- @param boolean? isCompleteInspection true after a complete inspection
-- @return string text formatted condition
function RMS_Utils.formatCondition(condition, isCompleteInspection)
    local STATES = RealisticMechanicalSystems.STATES
    if isCompleteInspection == nil then
        return g_i18n:getText(STATES.UNKNOWN)
    end
    if isCompleteInspection then
        return string.format("%.0f%%", condition * 100)
    end
    return g_i18n:getText(STATES[CONDITION_STATE_NAMES[RMS_Utils.getConditionTier(condition)]])
end

---Returns the share of the service interval still to run
-- @param float? service service level
-- @return float ratio remaining share
function RMS_Utils.getServiceIntervalRemainingRatio(service)
    local threshold = math.clamp(tonumber(RMS_Config.CORE.SERVICE_EXPIRED_THRESHOLD) or 0.5, 0.0, 0.9999)
    local activeRange = math.max(1.0 - threshold, 0.0001)
    return math.clamp(((tonumber(service) or 0.0) - threshold) / activeRange, 0.0, 1.0)
end

---Formats a service level, exact after a complete inspection
-- @param float? service service level
-- @param boolean? isCompleteInspection true after a complete inspection
-- @return string text formatted service level
function RMS_Utils.formatService(service, isCompleteInspection)
    local STATES = RealisticMechanicalSystems.STATES
    if isCompleteInspection == nil then
        return g_i18n:getText(STATES.UNKNOWN)
    end
    if isCompleteInspection then
        return string.format("%.0f%%", RMS_Utils.getServiceIntervalRemainingRatio(service) * 100)
    end
    return g_i18n:getText(STATES[SERVICE_STATE_NAMES[RMS_Utils.getServiceTier(service)]])
end


---Returns the tier a service level falls in, 1 being the best
-- @param float? service service level
-- @return integer tier service tier
function RMS_Utils.getServiceTier(service)
    service = tonumber(service) or 0.0
    for tier = 1, #SERVICE_LEVELS do
        if service >= SERVICE_LEVELS[tier] then
            return tier
        end
    end
    return #SERVICE_LEVELS + 1
end


---Returns the top of a tier
local function getTierCeiling(levels, tier)
    return tier > 1 and levels[tier - 1] or 1.0
end


---Returns the condition ring ratio, exact after a complete inspection
-- @param float? condition condition level
-- @param boolean? isCompleteInspection true after a complete inspection
-- @return float ratio ring ratio
function RMS_Utils.getConditionRingRatio(condition, isCompleteInspection)
    if isCompleteInspection == nil then
        return 0.0
    end
    if isCompleteInspection then
        return math.clamp(tonumber(condition) or 0.0, 0.0, 1.0)
    end
    return getTierCeiling(RMS_Utils.CONDITION_LEVELS, RMS_Utils.getConditionTier(condition))
end


---Returns the service ring ratio, exact after a complete inspection
-- @param float? service service level
-- @param boolean? isCompleteInspection true after a complete inspection
-- @return float ratio ring ratio
function RMS_Utils.getServiceRingRatio(service, isCompleteInspection)
    if isCompleteInspection == nil then
        return 0.0
    end
    if isCompleteInspection then
        return RMS_Utils.getServiceIntervalRemainingRatio(service)
    end
    return RMS_Utils.getServiceIntervalRemainingRatio(getTierCeiling(SERVICE_LEVELS, RMS_Utils.getServiceTier(service)))
end


---Formats how many whole hours of work an inspection report is old
-- @param float? hours hours of work since the report, nil without one
-- @return string text localized age of the report
function RMS_Utils.formatReportAge(hours)
    if hours == nil then
        return g_i18n:getText("rms_spec_never")
    elseif hours < 1 then
        return g_i18n:getText("rms_spec_work_under_hour_ago")
    end
    return string.format(g_i18n:getText("rms_spec_work_hours_ago_format"), g_i18n:formatNumber(math.floor(hours), 0), g_i18n:getText("rms_spec_op_hours_short"))
end

---Formats how long ago a date was, in months
-- @param table? pastDate date holding year and month
-- @return string text localized elapsed time
function RMS_Utils.formatTimeAgo(pastDate) 
    if type(pastDate) ~= "table" or not pastDate.year or not pastDate.month then
        return g_i18n:getText('rms_spec_never')
    end

    local env = g_currentMission and g_currentMission.environment
    if not env then
        return ""
    end

    local currentMonthsTotal = env.currentYear * 12 + env.currentPeriod
    local pastMonthsTotal = pastDate.year * 12 + pastDate.month

    local monthsAgo = math.max(0, currentMonthsTotal - pastMonthsTotal)

    if monthsAgo == 0 then
        return g_i18n:getText('rms_spec_this_month')
    else
        return string.format(
            g_i18n:getText('rms_spec_months_ago_format'), 
            monthsAgo, 
            g_i18n:getText(monthsAgo == 1 and 'rms_spec_month_ago_one' or 'rms_spec_months_ago_unit')
        )
    end
end

-- @param table? pastDate year and month, nil without maintenance
-- @return string text localized attribute
function RMS_Utils.formatShopLastMaintenance(pastDate)
    if type(pastDate) ~= "table" or not pastDate.year or not pastDate.month then
        return g_i18n:getText("rms_shop_last_maintenance_never")
    end
    local env = g_currentMission.environment
    local monthsAgo = math.max(0, env.currentYear * 12 + env.currentPeriod - (pastDate.year * 12 + pastDate.month))
    if monthsAgo == 0 then
        return g_i18n:getText("rms_shop_last_maintenance_this_month")
    end
    return string.format(g_i18n:getText("rms_shop_last_maintenance_months_ago"), monthsAgo,
        g_i18n:getText(monthsAgo == 1 and "rms_spec_month_ago_one" or "rms_spec_months_ago_unit"))
end

-- @param float damage repair need of the machine, 0 to 1
-- @return string care careful, regular or neglected
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

-- @param string care careful, regular or neglected
-- @return float damage repair need the care reads back from
function RMS_Utils.getOwnerCareDamage(care)
    local history = RMS_Config.CORE.USED_VEHICLE_HISTORY
    local third = ({ careful = 0, regular = 1, neglected = 2 })[care]
    return history.DAMAGE_MIN + (third + 0.5) / 3 * (history.DAMAGE_MAX - history.DAMAGE_MIN)
end

-- @param table vehicle vehicle a player sells
-- @return string care careful, regular or neglected
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
-- @param float damage repair need the game drew for the offer
-- @return string text localized attribute
function RMS_Utils.formatOwnerCare(damage)
    return g_i18n:getText(OWNER_CARE_LABELS[RMS_Utils.getOwnerCare(damage)])
end


---Reads the native lifetime odometer, already expressed in kilometres
-- @param table? vehicle vehicle owning the Drivable specialization
-- @return float? kilometers native reading, nil when unavailable
function RMS_Utils.getOdometerKilometers(vehicle)
    local drivable = vehicle ~= nil and vehicle.spec_drivable or nil
    local kilometers = drivable ~= nil and tonumber(drivable.odometerMilage) or nil
    if kilometers == nil or kilometers ~= kilometers or kilometers < 0 or kilometers == math.huge then
        return nil
    end
    return kilometers
end

-- @param float? kilometers odometer reading in kilometres
-- @return string text decimal reading and unit, or missing-reading label
function RMS_Utils.formatOdometerKilometers(kilometers)
    kilometers = tonumber(kilometers)
    if kilometers == nil or kilometers ~= kilometers or kilometers < 0 or kilometers == math.huge then
        return g_i18n:getText("rms_odometer_not_recorded")
    end
    local value = g_i18n:formatNumber(kilometers, 1)
    local decimalPattern = g_i18n.decimalSeparator:gsub("(%W)", "%%%1")
    return (value:gsub(decimalPattern .. "(%d)$", ".%1")) .. " km"
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

---Names the actual circuit which causes the next service recommendation.
function RMS_Utils.formatServiceReason(vehicle, schedule, compact)
    if schedule == nil then return "" end
    local keys = {engineOil = "rms_inspection_engine_oil", transmissionOil = "rms_inspection_transmission_oil",
        hydraulicFluid = "rms_inspection_hydraulic_fluid", coolant = "rms_inspection_coolant"}
    local circuit = schedule.clock.circuits[1]
    local key = RMS_Fluids.getCircuitTextKey(vehicle, circuit, keys[circuit])
    if compact and key == "rms_fluid_circuit_transmissionHydraulic" then key = "rms_fluid_hud_transmissionHydraulic" end
    return g_i18n:getText(key)
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
    return table.concat(values, " / ")
end

---Says which change the next service is for and when it falls due
-- @param table vehicle vehicle
-- @param table? schedule service schedule
-- @param boolean? compact use short common-sump name
-- @return string text change and its deadline
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
-- @return string text short duration
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
-- @param table vehicle vehicle
-- @param string maintenanceType maintenance type
-- @return string name level name
function RMS_Utils.formatMaintenanceLevel(vehicle, maintenanceType)
    return string.format(g_i18n:getText("rms_spec_maintenance_level"),
        RMS_Utils.formatHours(vehicle:getMaintenanceLevelInterval(maintenanceType)))
end

---Names the first option of a service
-- @param table vehicle vehicle
-- @param string serviceType service type
-- @param string optionOne first service option
-- @return string name option name
function RMS_Utils.formatServiceOption(vehicle, serviceType, optionOne)
    if serviceType == RealisticMechanicalSystems.STATUS.MAINTENANCE then
        return RMS_Utils.formatMaintenanceLevel(vehicle, optionOne)
    end
    return g_i18n:getText(optionOne)
end

---Returns the interval of the lightest maintenance fitting a new air filter
-- @param table vehicle vehicle
-- @return string hours interval with its unit
function RMS_Utils.formatAirFilterServiceHours(vehicle)
    for _, maintenanceType in ipairs(vehicle:getMaintenanceTypes()) do
        if RealisticMechanicalSystems.getMaintenanceRenewsAirFilter(maintenanceType) then
            return RMS_Utils.formatHours(vehicle:getMaintenanceLevelInterval(maintenanceType))
        end
    end
end


---Returns the label of a value against four descending thresholds
-- @param float value value to rate
-- @param float ideal best threshold
-- @param float high second threshold
-- @param float mid third threshold
-- @param float low worst threshold
-- @param any ... labels from best to worst
-- @return string label matching label
function RMS_Utils.getValueLabel(value, ideal, high, mid, low, ...)
    local labels = {...}
    if value >= ideal then
        return labels[1]
    elseif value >= high then
        return labels[2]
    elseif value >= mid then
        return labels[3]
    elseif value >= low then
        return labels[4]
    else
        return labels[5]
    end
end

---Returns the label of a value against four ascending thresholds
-- @param float value value to rate
-- @param float ideal best threshold
-- @param float low second threshold
-- @param float mid third threshold
-- @param float high worst threshold
-- @param any ... labels from best to worst
-- @return string label matching label
function RMS_Utils.getValueLabelInverted(value, ideal, low, mid, high, ...)
    local labels = {...}
    if value <= ideal then
        return labels[1]
    elseif value <= low then
        return labels[2]
    elseif value <= mid then
        return labels[3]
    elseif value <= high then
        return labels[4]
    else
        return labels[5]
    end
end


local RELIABILITY_LABELS = { "rms_reliability_average", "rms_reliability_fair", "rms_reliability_good", "rms_reliability_very_good" }
local SHOP_RELIABILITY_LABELS = { "rms_shop_reliability_average", "rms_shop_reliability_fair", "rms_shop_reliability_good",
    "rms_shop_reliability_very_good" }

---Formats a reliability value as its localized label
-- @param float? value reliability value
-- @param boolean? isShop true for a shop attribute, which no label names
-- @return string text localized label
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

---
function RMS_Utils.getServiceAccessLabourFactor(vehicle, category)
    return RMS_Utils.getServiceAccessProfile(vehicle)[category] or 1
end

---
function RMS_Utils.formatServiceAccess(vehicle, storeItem, configurations, isShop)
    local profile = RMS_Utils.getServiceAccessProfile(vehicle, storeItem, configurations)
    return g_i18n:getText(isShop and profile.shopLabel or profile.label)
end

---Returns the colour of an original reliability
-- @param float? value reliability
-- @return float r, g, b, a colour
function RMS_Utils.getReliabilityColor(value)
    return RMS_Utils.getValueColor(tonumber(value) or 1, 1.1, 1.1, 1.0, 0, false)
end

---Returns the colour of the ease of service of a vehicle
-- @param table vehicle vehicle
-- @return float r, g, b, a colour
function RMS_Utils.getServiceAccessColor(vehicle)
    local profiles = RMS_Config.SERVICE_ACCESS_PROFILES
    local profile = RMS_Utils.getServiceAccessProfile(vehicle)
    local tier = profile == profiles.SIMPLE and 1 or profile == profiles.COMPLEX and 3 or 2
    return RMS_Utils.getValueColorInverted(tier, 1, 1, 2, 3, false)
end

---Writes the causes of wear as alias:share pairs
-- @param table? causes share of each cause over the normal wear, by alias
-- @return string text written causes
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
-- @param string? text written causes
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

RMS_Utils.LOG_ICON_PROFILES = {
    square = {row = "rms_logTypeIcon", detail = "rms_logDetailIcon"},
    wide = {row = "rms_logTypeIconWide", detail = "rms_logDetailIconWide"},
    maintenance = {row = "rms_logTypeIconMaintenance", detail = "rms_logDetailIconMaintenance"},
    refill = {row = "rms_logTypeIconRefill", detail = "rms_logDetailIconRefill"}
}

---Formats a maintenance log date in the same compact form as the report screen
-- @param table? entry maintenance log entry
-- @return string dateText formatted date
function RMS_Utils.formatMaintenanceLogDate(entry)
    local year = entry ~= nil and entry.date ~= nil and tonumber(entry.date.year) or 0
    local yearText = year >= 10 and tostring(year) or "0" .. tostring(year)
    local day = entry ~= nil and entry.date ~= nil and tonumber(entry.date.day) or 1
    local month = entry ~= nil and entry.date ~= nil and tonumber(entry.date.month) or 1
    return string.format("%s %s. '%s", day, g_i18n:formatPeriod(month, true), yearText)
end

---Names a service state, the repaint by its RMS name
-- @param string status service state
-- @return string text localized name
function RMS_Utils.formatServiceState(status)
    if status == RealisticMechanicalSystems.STATUS.BODYWORK then
        return g_i18n:getText("rms_spec_state_bodywork")
    end
    return g_i18n:getText(status)
end

---Returns the label, colour and icon of an intervention type
-- @param table? entry maintenance log entry
-- @return string typeText localized intervention name
-- @return table color RGBA text color
-- @return string iconSliceId native GUI slice
-- @return string iconStyle icon geometry category
function RMS_Utils.getLogTypePresentation(entry)
    local status = RealisticMechanicalSystems.STATUS
    local entryType = entry ~= nil and entry.type or nil

    if entryType == status.REPAIR then
        return g_i18n:getText("rms_ws_action_repair"), {0.88, 0.12, 0.12, 1}, "gui.contextAction_icon_repair", "wide"
    elseif entryType == status.MAINTENANCE then
        return g_i18n:getText("rms_ws_action_maintenance"), RMS_Utils.COLOR.HIGHLIGHT, "rms_Hud.maintenance", "maintenance"
    elseif entryType == status.INSPECTION then
        return g_i18n:getText("rms_ws_action_inspection"), {1, 1, 1, 1}, "gui.icon_vehicleDealer_search", "square"
    elseif entryType == status.OVERHAUL then
        return g_i18n:getText("rms_ws_action_overhaul"), {1, 0.5, 0, 1}, "gui.icon_ingameMenu_options", "square"
    elseif entryType == status.REFILL then
        return g_i18n:getText("rms_ws_action_refill"), RMS_Utils.COLOR.HIGHLIGHT, "rms_WorkshopFluids.engineOil", "refill"
    elseif entryType == status.BODYWORK then
        return g_i18n:getText("rms_spec_state_bodywork"), {1, 1, 1, 1}, "gui.icon_vehicleDealer_machines", "square"
    elseif entryType == RealisticMechanicalSystems.LOG_DIAGNOSTIC_READING then
        return g_i18n:getText("rms_diagnostic_log_title"), {1, 1, 1, 1}, "rms_Diagnostic.stethoscope", "square"
    end

    return "-", {1, 1, 1, 1}, "gui.icon_ingameMenu_options", "square"
end

---Fills one text row split into the requested columns and hides unused columns
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
-- @param table items ordered text items
-- @param integer index row index
-- @param table cell list row element
-- @param string leftAttribute left text attribute name
-- @param string rightAttribute right text attribute name
-- @param string rightBulletAttribute right bullet attribute name
function RMS_Utils.populateTwoColumnTextRow(items, index, cell, leftAttribute, rightAttribute, rightBulletAttribute)
    populateTextColumnsRow(items, index, cell, {
        {text = leftAttribute},
        {text = rightAttribute, bullet = rightBulletAttribute}
    })
end

---Fills a three-column text row and hides its unused center and right columns
-- @param table items ordered text items
-- @param integer index row index
-- @param table cell list row element
-- @param string leftAttribute left text attribute name
-- @param string centerAttribute center text attribute name
-- @param string centerBulletAttribute center bullet attribute name
-- @param string rightAttribute right text attribute name
-- @param string rightBulletAttribute right bullet attribute name
function RMS_Utils.populateThreeColumnTextRow(items, index, cell, leftAttribute, centerAttribute, centerBulletAttribute, rightAttribute, rightBulletAttribute)
    populateTextColumnsRow(items, index, cell, {
        {text = leftAttribute},
        {text = centerAttribute, bullet = centerBulletAttribute},
        {text = rightAttribute, bullet = rightBulletAttribute}
    })
end

local COLOR_IDEAL  = {0.12, 0.88, 0.0, 1.0}  -- super green
local COLOR_GREEN  = {0.3, 0.7, 0.0, 1.0}    -- green
local COLOR_YELLOW = {0.85, 0.78, 0.2, 1.0}  -- yellow
local COLOR_ORANGE = {0.85, 0.5, 0.15, 1.0}  -- orange
local COLOR_RED    = {0.8, 0.2, 0.2, 1.0}    -- red
local COLOR_UNKNOWN = {0.5, 0.5, 0.5, 1.0}   -- grey

local SERVICE_COLOR_LEVELS = {0.9, 0.5, 0.2, 0.001}

---Interpolates between two colours
local function lerpColor(a, b, t)
    return {
        a[1] + (b[1] - a[1]) * t,
        a[2] + (b[2] - a[2]) * t,
        a[3] + (b[3] - a[3]) * t,
        a[4] + (b[4] - a[4]) * t,
    }
end

---Returns the colour of a value on a five tier scale
local function getScaleColor(scale, value, ideal, high, mid, low, smooth)
    local c

    if smooth then
        if value >= ideal then
            c = scale[1]
        elseif value >= high then
            local t = 1.0 - (value - high) / (ideal - high)
            c = lerpColor(scale[1], scale[2], t)
        elseif value >= mid then
            local t = 1.0 - (value - mid) / (high - mid)
            c = lerpColor(scale[2], scale[3], t)
        elseif value >= low then
            local t = 1.0 - (value - low) / (mid - low)
            c = lerpColor(scale[3], scale[4], t)
        else
            local t = math.min(1.0, (low - value) / low)
            c = lerpColor(scale[4], scale[5], t)
        end
    else
        if value >= ideal then
            c = scale[1]
        elseif value >= high then
            c = scale[2]
        elseif value >= mid then
            c = scale[3]
        elseif value >= low then
            c = scale[4]
        else
            c = scale[5]
        end
    end

    return c[1], c[2], c[3], c[4]
end

local TEXT_SCALE = {COLOR_IDEAL, COLOR_GREEN, COLOR_YELLOW, COLOR_ORANGE, COLOR_RED}

---Returns the colour of a value against four descending thresholds
-- @param float value value to rate
-- @param float ideal best threshold
-- @param float high second threshold
-- @param float mid third threshold
-- @param float low worst threshold
-- @param boolean? smooth true to blend between the tiers
-- @return float r red channel
-- @return float g green channel
-- @return float b blue channel
-- @return float a alpha channel
function RMS_Utils.getValueColor(value, ideal, high, mid, low, smooth)
    return getScaleColor(TEXT_SCALE, value, ideal, high, mid, low, smooth)
end

---Returns the colour of a gauge fill
-- @param float value value to rate
-- @param float ideal best threshold
-- @param float high second threshold
-- @param float mid third threshold
-- @param float low worst threshold
-- @param boolean? smooth true to blend between the tiers
-- @return float r red channel
-- @return float g green channel
-- @return float b blue channel
-- @return float a alpha channel
function RMS_Utils.getGaugeColor(value, ideal, high, mid, low, smooth)
    local green = RMS_Utils.COLOR.HIGHLIGHT
    local scale = {green, green, COLOR_YELLOW, COLOR_ORANGE, COLOR_RED}

    return getScaleColor(scale, value, ideal, high, mid, low, smooth)
end

---Returns the colour of a condition, grey while the inspection is incomplete
-- @param float? condition condition level
-- @param boolean? isCompleteInspection true after a complete inspection
-- @return float r red channel
-- @return float g green channel
-- @return float b blue channel
-- @return float a alpha channel
function RMS_Utils.getConditionColor(condition, isCompleteInspection)
    if isCompleteInspection == nil then
        return unpack(COLOR_UNKNOWN)
    end

    local ideal, high, mid, low = unpack(RMS_Utils.CONDITION_LEVELS)
    return RMS_Utils.getValueColor(condition, ideal, high, mid, low, false)
end

---Builds the system and part rows from an inspection report.
-- @param table vehicle vehicle
-- @param table report reference report
-- @param table systems systems of the report
-- @param boolean isMeasured true when the report gives figures
-- @param boolean isOutdated true when the report no longer holds
-- @param string? openSystem system unfolded
-- @return table rows card rows
-- @return string footText line under the list
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
                    table.insert(partRows, {kind = "part", name = g_i18n:getText(RMS_Breakdowns.BreakdownRegistry[partId].part),
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

---Fills one system condition row.
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

---Fills one inspected part row.
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
-- @param table cell cell element
-- @param table row card row
function RMS_Utils.populateConditionCell(cell, row)
    if row.kind == "system" then
        populateConditionSystemCell(cell, row)
    else
        populateConditionPartCell(cell, row)
    end
end

---Reloads a list, each shown row taking the template it now needs
-- @param table list list element
function RMS_Utils.reloadListTemplates(list)
    for sectionIndex, section in pairs(list.sections) do
        for index, cell in pairs(section.cells) do
            if cell.reusableName ~= list.dataSource:getCellTypeForItemInSection(list, sectionIndex, index) then
                list:queueReusableCell(cell)
            end
        end
    end
    list:reloadData()
end

-- @param float? service service level
-- @param boolean? isCompleteInspection true after a complete inspection
-- @return float r red channel
-- @return float g green channel
-- @return float b blue channel
-- @return float a alpha channel
function RMS_Utils.getServiceColor(service, isCompleteInspection)
    if isCompleteInspection == nil then
        return unpack(COLOR_UNKNOWN)
    end

    local ideal, high, mid, low = unpack(SERVICE_COLOR_LEVELS)
    return RMS_Utils.getValueColor(RMS_Utils.getServiceIntervalRemainingRatio(service), ideal, high, mid, low, isCompleteInspection)
end

---Returns the colour of a value against four ascending thresholds
-- @param float value value to rate
-- @param float ideal best threshold
-- @param float low second threshold
-- @param float mid third threshold
-- @param float high worst threshold
-- @param boolean? smooth true to blend between the tiers
-- @return float r red channel
-- @return float g green channel
-- @return float b blue channel
-- @return float a alpha channel
function RMS_Utils.getValueColorInverted(value, ideal, low, mid, high, smooth)
    local c

    if smooth then
        if value <= ideal then
            c = COLOR_IDEAL
        elseif value <= low then
            local t = (value - ideal) / (low - ideal)
            c = lerpColor(COLOR_IDEAL, COLOR_GREEN, t)
        elseif value <= mid then
            local t = (value - low) / (mid - low)
            c = lerpColor(COLOR_GREEN, COLOR_YELLOW, t)
        elseif value <= high then
            local t = (value - mid) / (high - mid)
            c = lerpColor(COLOR_YELLOW, COLOR_ORANGE, t)
        else
            local t = math.min(1.0, (value - high) / high)
            c = lerpColor(COLOR_ORANGE, COLOR_RED, t)
        end
    else
        if value <= ideal then
            c = COLOR_IDEAL
        elseif value <= low then
            c = COLOR_GREEN
        elseif value <= mid then
            c = COLOR_YELLOW
        elseif value <= high then
            c = COLOR_ORANGE
        else
            c = COLOR_RED
        end
    end

    return c[1], c[2], c[3], c[4]
end

local SAVEGAME_OPTIONAL_FLOAT_SENTINEL = -1

---Converts a value to a boolean, strings and numbers accepted
-- @param any value value to convert
-- @param boolean? defaultValue value used when nothing is recognised
-- @return boolean value converted value
function RMS_Utils.normalizeBoolValue(value, defaultValue)
    if value == nil then
        return defaultValue == true
    end

    if type(value) == "boolean" then
        return value
    end

    if type(value) == "number" then
        return value ~= 0
    end

    if type(value) == "string" then
        local v = string.lower(value)
        if v == "false" or v == "0" or v == "off" or v == "no" then
            return false
        end
        if v == "true" or v == "1" or v == "on" or v == "yes" then
            return true
        end
    end

    return value and true or false
end


---Encodes a float that may be absent
-- @param float? value value to encode
-- @return string text encoded value
function RMS_Utils.encodeOptionalFloat(value)
    if value == nil then
        return SAVEGAME_OPTIONAL_FLOAT_SENTINEL
    end

    local num = tonumber(value)
    if num == nil then
        return SAVEGAME_OPTIONAL_FLOAT_SENTINEL
    end

    return num
end

---Decodes a float that may be absent
-- @param string? value encoded value
-- @return float? value decoded value
function RMS_Utils.decodeOptionalFloat(value)
    local num = tonumber(value)
    if num == nil or num < 0 then
        return nil
    end

    return num
end

---Splits a comma separated string into a list
-- @param string? csvString comma separated values
-- @return table values value list
function RMS_Utils.parseCsvList(csvString)
    local result = {}
    if csvString == nil or csvString == "" then
        return result
    end

    for item in string.gmatch(csvString, "([^,]+)") do
        local trimmed = tostring(item):gsub("^%s+", ""):gsub("%s+$", "")
        if trimmed ~= "" then
            table.insert(result, trimmed)
        end
    end

    return result
end

---Serializes the active effects into one string
-- @param table? effects active effects
-- @return string serialized serialized effects
function RMS_Utils.serializeEffectSnapshot(effects)
    local entries = {}
    if effects == nil then
        return ""
    end

    for effectId, effectData in pairs(effects) do
        local key = tostring(effectId or "")
        if key ~= "" then
            local encodedValue = ""

            if type(effectData) == "table" then
                local numericValue = tonumber(effectData.value)
                if numericValue ~= nil then
                    encodedValue = string.format("%.6f", numericValue)
                end
            elseif type(effectData) == "number" then
                encodedValue = string.format("%.6f", effectData)
            end

            table.insert(entries, string.format("%s|%s", key, tostring(encodedValue)))
        end
    end

    table.sort(entries)
    return table.concat(entries, ";")
end

---Rebuilds the active effects from their serialized form
-- @param string? serialized serialized effects
-- @return table effects active effects
function RMS_Utils.deserializeEffectSnapshot(serialized)
    local result = {}
    if serialized == nil or serialized == "" then
        return result
    end

    if not string.find(serialized, "|") then
        for _, effectId in ipairs(RMS_Utils.parseCsvList(serialized)) do
            result[effectId] = true
        end
        return result
    end

    for entry in string.gmatch(serialized, "([^;]+)") do
        local effectId, rawValue = string.match(entry, "([^|]+)|([^|]*)")
        if effectId ~= nil and effectId ~= "" then
            local value = tonumber(rawValue)
            if value ~= nil then
                result[effectId] = {
                    id = effectId,
                    value = value
                }
            else
                result[effectId] = true
            end
        end
    end

    return result
end

---Returns the system name behind a system key
-- @param table systems system name table
-- @param string systemKey system key
-- @return string? name system name
function RMS_Utils.getSystemNameByKey(systems, systemKey)
    if systems == nil then
        return tostring(systemKey)
    end

    local normalized = string.lower(tostring(systemKey))
    for enumKey, systemName in pairs(systems) do
        if string.lower(tostring(enumKey)) == normalized then
            return systemName
        end
    end

    return tostring(systemKey)
end

---Serializes the condition of every system
-- @param table? systems system table
-- @return string serialized serialized systems
function RMS_Utils.serializeSystemsState(systems)
    local entries = {}
    if systems == nil then
        return ""
    end

    for systemKey, systemData in pairs(systems) do
        local condition = 1.0
        local enabled = true

        if type(systemData) == "table" then
            condition = tonumber(systemData.condition) or 1.0
            enabled = RMS_Utils.normalizeBoolValue(systemData.enabled, true)
        else
            condition = tonumber(systemData) or 1.0
        end

        table.insert(entries, string.format("%s|%.6f|%d", tostring(systemKey), condition, enabled and 1 or 0))
    end

    table.sort(entries)
    return table.concat(entries, ";")
end

---Rebuilds the system conditions from their serialized form
-- @param string? serialized serialized systems
-- @return table systems system table
function RMS_Utils.deserializeSystemsState(serialized)
    local result = {}
    if serialized == nil or serialized == "" then
        return result
    end

    local separator = ";"
    if not string.find(serialized, ";") then
        separator = ","
    end
    local pattern = "([^" .. separator .. "]+)"

    for entry in string.gmatch(serialized, pattern) do
        local parts = {}
        for part in string.gmatch(entry .. "|", "(.-)|") do
            table.insert(parts, part)
        end

        local key = parts[1]
        if key ~= nil and key ~= "" then
            -- The enabled flag terminates entries from both log formats.
            result[key] = {
                condition = tonumber(parts[2]) or 1.0,
                enabled = RMS_Utils.normalizeBoolValue(tonumber(parts[3] and parts[#parts]), true)
            }
        end
    end

    return result
end

---Copies the condition of every system for a later comparison
-- @param table? systems system table
-- @return table snapshot system snapshot
function RMS_Utils.createSystemsSnapshot(systems)
    local snapshot = {}
    if systems == nil then
        return snapshot
    end

    for systemKey, systemData in pairs(systems) do
        if type(systemData) == "table" then
            snapshot[systemKey] = {
                condition = tonumber(systemData.condition) or 1.0,
                enabled = RMS_Utils.normalizeBoolValue(systemData.enabled, true)
            }
        else
            snapshot[systemKey] = {
                condition = tonumber(systemData) or 1.0,
                enabled = true
            }
        end
    end

    return snapshot
end

---Serializes a map of numbers into one string
-- @param table? valueMap numeric map
-- @return string serialized serialized map
function RMS_Utils.serializeNumericMap(valueMap)
    local entries = {}
    if valueMap == nil then
        return ""
    end

    for key, value in pairs(valueMap) do
        local numericValue = tonumber(value)
        if numericValue ~= nil then
            table.insert(entries, string.format("%s|%.6f", tostring(key), numericValue))
        end
    end

    table.sort(entries)
    return table.concat(entries, ";")
end

---Rebuilds a map of numbers from its serialized form
-- @param string? serialized serialized map
-- @return table valueMap numeric map
function RMS_Utils.deserializeNumericMap(serialized)
    local result = {}
    if serialized == nil or serialized == "" then
        return result
    end

    local separator = ";"
    if not string.find(serialized, ";") then
        separator = ","
    end
    local pattern = "([^" .. separator .. "]+)"

    for entry in string.gmatch(serialized, pattern) do
        local key, valueStr = string.match(entry, "([^|]+)|([^|]+)")
        if key ~= nil then
            local numericValue = tonumber(valueStr)
            if numericValue ~= nil then
                result[key] = numericValue
            end
        end
    end

    return result
end

local ELECTRIC_SYSTEM_LABELS = {
    rms_spec_system_engine = "rms_spec_system_electric_motor",
    rms_spec_system_fuel = "rms_spec_system_traction_battery"
}

---Returns the text naming a system on a vehicle
-- @param table vehicle vehicle
-- @param string textKey system name, any other text key comes back as it is
-- @return string textKey text key to display
function RMS_Utils.getSystemLabel(vehicle, textKey)
    if vehicle.spec_RealisticMechanicalSystems.isElectricVehicle then
        return ELECTRIC_SYSTEM_LABELS[textKey] or textKey
    end
    return textKey
end

---Returns the system key behind a system name
-- @param table systems system name table
-- @param string systemName system name
-- @return string? key system key
function RMS_Utils.getSystemKey(systems, systemName)
    if systems == nil then
        return ""
    end
    return string.lower(RMS_Utils.getKeyByValue(systems, systemName) or "")
end

---Turns a real price into the game's, scaled by the economic difficulty
-- @param float realPrice real price in euros
-- @return float price game price
function RMS_Utils.getGamePrice(realPrice)
    return realPrice * (EconomyManager.getCostMultiplier() / EconomyManager.COST_MULTIPLIER[EconomicDifficulty.NORMAL])
end

-- @param table vehicle vehicle
-- @param float age calendar age in years
-- @param float workHours hours of work of a real machine
-- @return float share remaining value share
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

-- @param table vehicle vehicle
-- @return float value market value
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
    local repairPrice = vehicle:getServicePrice(R.STATUS.REPAIR, R.REPAIR_TYPES.MEDIUM, R.PART_TYPES.OEM, false, R.WORKSHOP.DEALER, true)
    local overhaulPrice = vehicle:getServicePrice(R.STATUS.OVERHAUL, R.OVERHAUL_TYPES.FULL, nil, false, R.WORKSHOP.DEALER)
    local deduction = math.min(repairPrice + R.getCatchUpPrice(vehicle, hours), overhaulPrice)
    return math.max(price * share - deduction - repaintPrice, price * 0.03)
end

---Returns the resale payment of the menu or the dealer
-- @param table vehicle vehicle
-- @param boolean? isDirectSell true for the dealer trigger sale
-- @return integer? value resale value, nil when the vehicle is not the farm's to sell
function RMS_Utils.getResaleValue(vehicle, isDirectSell)
    if vehicle.propertyState ~= VehiclePropertyState.OWNED then
        return nil
    end
    local multiplier = isDirectSell and EconomyManager.DIRECT_SELL_MULTIPLIER or 1
    return math.min(math.floor(vehicle:getSellPrice() * multiplier), vehicle:getPrice())
end

---Returns the weight a system carries on this vehicle
-- @param table? vehicle vehicle
-- @param string systemName system name
-- @param table? systems system table
-- @return float weight system weight
function RMS_Utils.getEffectiveSystemWeight(vehicle, systemName, systems)
    local spec = vehicle ~= nil and vehicle.spec_RealisticMechanicalSystems or nil
    if spec == nil or type(spec.systems) ~= "table" or type(systemName) ~= "string" then
        return 0
    end

    local systemWeights = RMS_Config.CORE.SYSTEM_WEIGHTS

    ---Returns the configured weight of a system key
    local function getConfiguredWeight(systemKey)
        if systemKey == nil then
            return 0
        end

        local directWeight = tonumber(systemWeights[systemKey])
        if directWeight ~= nil then
            return math.max(directWeight, 0)
        end

        local loweredKey = string.lower(tostring(systemKey))
        for weightedKey, weight in pairs(systemWeights) do
            if string.lower(tostring(weightedKey)) == loweredKey then
                return math.max(tonumber(weight) or 0, 0)
            end
        end

        return 0
    end

    ---Resolves a system name to its key, matching case insensitively
    local function resolveSystemKey(name)
        if spec.systems[name] ~= nil then
            return name
        end

        if type(systems) == "table" then
            local enumValue = systems[string.upper(name)]
            if type(enumValue) == "string" then
                local enumKey = string.lower(string.upper(name))
                if spec.systems[enumKey] ~= nil then
                    return enumKey
                end
            end

            local systemKeyByValue = RMS_Utils.getKeyByValue(systems, name)
            if type(systemKeyByValue) == "string" then
                local loweredEnumKey = string.lower(systemKeyByValue)
                if spec.systems[loweredEnumKey] ~= nil then
                    return loweredEnumKey
                end
            end
        end

        local loweredName = string.lower(name)
        for existingKey, _ in pairs(spec.systems) do
            if string.lower(tostring(existingKey)) == loweredName then
                return existingKey
            end
        end

        return loweredName
    end

    local resolvedSystemKey = resolveSystemKey(systemName)
    local targetSystemData = spec.systems[resolvedSystemKey]
    if targetSystemData == nil or (type(targetSystemData) == "table" and targetSystemData.enabled == false) then
        return 0
    end

    local targetWeight = getConfiguredWeight(resolvedSystemKey)
    if targetWeight <= 0 then
        return 0
    end

    local totalEnabledWeight = 0
    for existingKey, systemData in pairs(spec.systems) do
        if type(systemData) ~= "table" or systemData.enabled ~= false then
            local configuredWeight = getConfiguredWeight(existingKey)
            if configuredWeight > 0 then
                totalEnabledWeight = totalEnabledWeight + configuredWeight
            end
        end
    end

    if totalEnabledWeight <= 0 then
        return 0
    end

    return targetWeight / totalEnabledWeight
end

---Returns the enabled systems whose condition permits an overhaul
-- @param table? vehicle vehicle
-- @return table values eligible system l10n keys in declared order
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
-- @param table? vehicle vehicle
-- @return table values system names in display order
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

---Copies a table one level deep
-- @param any original table to copy
-- @return any copy copied table
function RMS_Utils.shallowCopy(original)
    local result = {}
    if type(original) ~= "table" then
        return result
    end
    for key, value in pairs(original) do
        result[key] = value
    end
    return result
end

---Copies a table and everything it holds, guarding against cycles
-- @param any original table to copy
-- @param table? seen tables already copied
-- @return any copy copied table
function RMS_Utils.deepCopy(original, seen)
    if type(original) ~= "table" then
        return original
    end

    seen = seen or {}
    if seen[original] ~= nil then
        return seen[original]
    end

    local result = {}
    seen[original] = result

    for key, value in pairs(original) do
        local copiedKey = RMS_Utils.deepCopy(key, seen)
        result[copiedKey] = RMS_Utils.deepCopy(value, seen)
    end

    return result
end

---Serializes invoice lines into a string
-- @param table? invoice invoice lines
-- @return string serialized kind, key, mode, liters and price of each line
function RMS_Utils.serializeInvoice(invoice)
    local values = {}
    for _, line in ipairs(invoice or {}) do
        table.insert(values, string.format(
            "%s,%s,%s,%.6f,%.4f,%s",
            tostring(line.kind or ""),
            tostring(line.key or ""),
            tostring(line.mode or ""),
            tonumber(line.liters) or 0,
            tonumber(line.price) or 0,
            line.warrantyReason or ""
        ))
    end
    return table.concat(values, ";")
end

---Rebuilds invoice lines from their serialized form
-- @param string? serialized serialized invoice
-- @return table? invoice invoice lines, nil when none were recorded
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
-- @param table? entry maintenance log entry
-- @return string serialized serialized entry
function RMS_Utils.serializeMaintenanceLogEntry(entry)
    if entry == nil then return "" end
    local cd = entry.conditionData or {}
    local serializedSystems = RMS_Utils.encodeDelimitedString(RMS_Utils.serializeSystemsState(RMS_Utils.createSystemsSnapshot(cd.systems)))
    local serializedBreakdowns = RMS_Utils.encodeDelimitedString(RMS_Utils.serializeBreakdowns(cd.activeBreakdowns or {}))
    local serializedSelectedBreakdowns = RMS_Utils.encodeDelimitedString(table.concat(cd.selectedBreakdowns or {}, ","))
    local serializedEffects = RMS_Utils.encodeDelimitedString(RMS_Utils.serializeEffectSnapshot(cd.activeEffects))
    local activeIndicatorIds = {}
    for indicatorId, isActive in pairs(cd.activeIndicators or {}) do
        if isActive then
            table.insert(activeIndicatorIds, tostring(indicatorId))
        end
    end
    table.sort(activeIndicatorIds)
    local serializedIndicators = RMS_Utils.encodeDelimitedString(table.concat(activeIndicatorIds, ","))
    local parts = {
        tostring(entry.id or 0),
        tostring(entry.type or ""),
        tostring(entry.price or 0),
        RMS_Utils.serializeDate(entry.date),
        tostring(entry.location or "UNKNOWN"),
        tostring(entry.optionOne or "NONE"),
        tostring(entry.optionTwo or "NONE"),
        tostring(entry.optionThree or false),
        tostring(RMS_Utils.normalizeBoolValue(entry.isVisible, true)),
        tostring(RMS_Utils.normalizeBoolValue(entry.isCompleted, true)),
        tostring(cd.year or 0),
        tostring(cd.operatingHours or 0),
        tostring(cd.age or 0),
        tostring(cd.condition or 1),
        tostring(cd.service or 1),
        tostring(cd.reliability or 1),
        "", -- Reserved position in previously saved log entries.
        serializedSystems,
        tostring(cd.batterySoc or 1),
        serializedEffects,
        serializedBreakdowns,
        serializedSelectedBreakdowns,
        serializedIndicators,
        RMS_Utils.encodeDelimitedString(RMS_Utils.serializeInvoice(entry.invoice)),
        tostring(cd.odometerKilometers or ""),
        tostring(cd.wearExcess or ""),
        RMS_Utils.encodeDelimitedString(RMS_Utils.serializeWearCauses(cd.wearCauses)),
        RMS_Utils.encodeDelimitedString(RMS_Utils.serializeNumericMap(cd.partWear))
    }
    return table.concat(parts, "|")
end

---Rebuilds a maintenance log entry from its serialized form
-- @param string? serialized serialized entry
-- @return table? entry maintenance log entry
function RMS_Utils.deserializeMaintenanceLogEntry(serialized)
    if serialized == nil or serialized == "" then return nil end
    local parts = {}
    for part in string.gmatch(serialized .. "|", "(.-)|") do
        table.insert(parts, part)
    end
    if #parts < 10 then return nil end

    local result = {
        id = tonumber(parts[1]) or 0,
        type = parts[2] ~= "" and parts[2] or nil,
        price = tonumber(parts[3]) or 0,
        date = RMS_Utils.deserializeDate(parts[4]),
        location = parts[5] ~= "" and parts[5] or "UNKNOWN",
        optionOne = parts[6] ~= "" and parts[6] or "NONE",
        optionTwo = parts[7] ~= "" and parts[7] or "NONE",
        optionThree = RMS_Utils.normalizeBoolValue(parts[8], false),
        isVisible = RMS_Utils.normalizeBoolValue(parts[9], true),
        isCompleted = RMS_Utils.normalizeBoolValue(parts[10], true),
        invoice = RMS_Utils.deserializeInvoice(RMS_Utils.decodeDelimitedString(parts[24] or "")),
        conditionData = {
            year = tonumber(parts[11]) or 0,
            operatingHours = tonumber(parts[12]) or 0,
            odometerKilometers = tonumber(parts[25]),
            age = tonumber(parts[13]) or 0,
            condition = tonumber(parts[14]) or 1,
            service = tonumber(parts[15]) or 1,
            reliability = tonumber(parts[16]) or 1,
            systems = RMS_Utils.createSystemsSnapshot(RMS_Utils.deserializeSystemsState(RMS_Utils.decodeDelimitedString(parts[18] or ""))),
            batterySoc = tonumber(parts[19]) or 1,
            activeBreakdowns = RMS_Utils.deserializeBreakdowns(RMS_Utils.decodeDelimitedString(parts[21] or "")),
            selectedBreakdowns = RMS_Utils.parseCsvList(RMS_Utils.decodeDelimitedString(parts[22] or "")),
            activeEffects = RMS_Utils.deserializeEffectSnapshot(RMS_Utils.decodeDelimitedString(parts[20] or "")),
            activeIndicators = {},
            wearExcess = tonumber(parts[26]),
            wearCauses = RMS_Utils.deserializeWearCauses(RMS_Utils.decodeDelimitedString(parts[27] or "")),
            partWear = RMS_Utils.deserializeNumericMap(RMS_Utils.decodeDelimitedString(parts[28] or ""))
        }
    }
    for _, indicatorId in ipairs(RMS_Utils.parseCsvList(RMS_Utils.decodeDelimitedString(parts[23] or ""))) do
        if indicatorId ~= nil and indicatorId ~= "" then
            result.conditionData.activeIndicators[indicatorId] = true
        end
    end
    return result
end

---Tells whether the CVT addon mod drives the transmission of this vehicle
-- @param table? vehicle vehicle
-- @return boolean hasAddon true when the addon is active on it
function RMS_Utils.hasCVTAddon(vehicle)
    local spec_CVTaddon = vehicle ~= nil and vehicle.spec_CVTaddon or nil
    local cvtAddonConfig = spec_CVTaddon ~= nil and (tonumber(spec_CVTaddon.CVTconfig) or 0) or 0
    return spec_CVTaddon ~= nil
        and spec_CVTaddon.CVTcfgExists
        and cvtAddonConfig ~= 0
        and cvtAddonConfig ~= 8
end

---Tells whether the vehicle runs a continuously variable transmission
-- @param table? vehicle vehicle
-- @return boolean hasCVT true for a CVT
function RMS_Utils.hasCVTTransmission(vehicle)
    local motor = vehicle ~= nil and vehicle.getMotor ~= nil and vehicle:getMotor() or nil
    return motor ~= nil and motor.minForwardGearRatio ~= nil and not RMS_Utils.getIsElectricVehicle(vehicle)
end

---Tells whether the vehicle runs on electricity alone
-- @param table? vehicle vehicle
-- @return boolean isElectric true with an electric consumer and no combustion one
function RMS_Utils.getIsElectricVehicle(vehicle)
    local hasElectricConsumer = false
    local hasCombustionConsumer = false

    if vehicle.spec_motorized and vehicle.spec_motorized.consumers then
        for _, consumer in pairs(vehicle.spec_motorized.consumers) do
            if consumer.fillType == FillType.ELECTRICCHARGE then
                hasElectricConsumer = true
            elseif consumer.fillType == FillType.DIESEL
                    or consumer.fillType == FillType.METHANE then
                hasCombustionConsumer = true
            end
        end
    end

    return hasElectricConsumer and not hasCombustionConsumer
end

---Tells whether an engine uses the shared ECU profile
-- @param table? vehicle vehicle
-- @return boolean usesProfile true for the common combustion-engine ECU profile
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
-- @param table vehicle vehicle
-- @return string drive ELECTRIC, DIRECT, VISCOUS or ELECTRONIC
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

---Returns the power to trailer mass thresholds, trucks having their own
-- @param boolean isTruck true for a truck
-- @return table levels ratio thresholds
function RMS_Utils.getHeavyTrailerRatioLevels(isTruck)
    local C = RMS_Config.CORE.TRANSMISSION_FACTOR_DATA
    if isTruck then
        return C.HEAVY_TRAILER_TRUCK_MASS_RATIO_THRESHOLD, C.HEAVY_TRAILER_TRUCK_MASS_RATIO_FULL_EFFECT
    end
    return C.HEAVY_TRAILER_MASS_RATIO_THRESHOLD, C.HEAVY_TRAILER_MASS_RATIO_FULL_EFFECT
end

---Builds a logger printing only while debug mode is on
-- @param string prefix prefix put in front of each line
-- @return function logger logging function
function RMS_Utils.createLogger(prefix)
    return function(...)
        if RMS_Config.DEBUG then
            local args = {...}
            for i = 1, #args do
                args[i] = tostring(args[i])
            end
            print(prefix .. " " .. table.concat(args, " "))
        end
    end
end

---Resolves a system name typed in the console to the key used by the spec
-- @param table? spec vehicle spec
-- @param any rawSystem system name
-- @return string? systemKey resolved system key
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


local VALUE_PILL_ANCHOR = {
    rms_workshopValuePill = "right",
    rms_workshopValuePillCentered = "center"
}

---Restores a value pill and its text to the boxes the XML declares
local function resetValuePill(valuePill, valueElement)
    if valuePill.rmsPillBox == nil then
        valuePill.rmsPillBox = {
            x = valuePill.position[1],
            width = valuePill.size[1],
            padding = valueElement.position[1] - valuePill.position[1]
        }
    end

    local box = valuePill.rmsPillBox
    valuePill:setPosition(box.x, nil)
    valuePill:setSize(box.width, nil)
    valueElement:setPosition(box.x + box.padding, nil)
    valueElement:setSize(box.width - box.padding * 2, nil)

    return box
end

-- @param table valuePill rounded background of the value
-- @param table valueElement value text drawn inside the pill
-- @param string? anchor "center", otherwise keep right edge
-- @param string? valueText value to write, the one already in place when nil
function RMS_Utils.fitValuePill(valuePill, valueElement, anchor, valueText)
    local box = resetValuePill(valuePill, valueElement)
    valueElement:setText(valueText or valueElement.sourceText or "")

    local width = math.min(box.width, valueElement:getTextWidth(true) + box.padding * 2)
    local x = box.x + box.width - width
    if anchor == "center" then
        x = box.x + (box.width - width) * 0.5
    end

    valuePill:setPosition(x, nil)
    valuePill:setSize(width, nil)
    valueElement:setPosition(x + box.padding, nil)
    valueElement:setSize(width - box.padding * 2, nil)
end

local function giveLabelRoom(label, labelGap, valuePill, valueElement)
    local box = valuePill.rmsPillBox
    while true do
        label:setSize(valuePill.position[1] - labelGap - label.position[1], nil)
        if label.text == label.sourceText
            or valueElement.textSize - valueElement.defaultTextSize * 0.05 <= valueElement.textMinSize then
            return
        end

        -- Leave a width tolerance before native text-size selection.
        local size = valueElement.textSize
        valueElement:setSize(valueElement:getTextWidth(true) * 0.999, nil)
        if valueElement.textSize >= size then
            return
        end
        local width = valueElement:getTextWidth(true) * 1.001 + box.padding * 2
        local x = box.x + box.width - width
        valuePill:setPosition(x, nil)
        valuePill:setSize(width, nil)
        valueElement:setPosition(x + box.padding, nil)
        valueElement:setSize(width - box.padding * 2, nil)
    end
end

---Gives the label left of a value pill the width the pill gave up
local function fitPillLabel(label, valuePill, valueElement)
    if label == nil or label.sourceText == nil then
        return
    end

    if label.rmsLabelGap == nil then
        label.rmsLabelGap = valuePill.rmsPillBox.x - label.position[1] - label.size[1]
    end
    if label.rmsLabelGap < 0 then
        return
    end

    giveLabelRoom(label, label.rmsLabelGap, valuePill, valueElement)
end

---Fits every value pill of a screen to its value
-- @param table element element to walk
function RMS_Utils.fitValuePills(element)
    if element == nil then
        return
    end

    local children = element.elements
    for index = 1, #children do
        RMS_Utils.fitValuePills(children[index])

        local anchor = VALUE_PILL_ANCHOR[children[index].profile]
        if anchor ~= nil and children[index + 1] ~= nil then
            RMS_Utils.fitValuePill(children[index], children[index + 1], anchor)
            if anchor == "right" then
                fitPillLabel(children[index - 1], children[index], children[index + 1])
            end
        end
    end
end

---Fits a row on its value, the title taking back the width the pill gives up
-- @param table titleElement row title element
-- @param table valuePill rounded background of the value
-- @param table valueElement value text drawn inside the pill
-- @param string titleText localized row title
-- @param string valueText localized row value
function RMS_Utils.fitRowValue(titleElement, valuePill, valueElement, titleText, valueText)
    if valuePill.rmsRowBox == nil then
        valuePill.rmsRowBox = {
            titleWidth = titleElement.size[1],
            titleGap = valuePill.position[1] - titleElement.position[1] - titleElement.size[1]
        }
    end

    local box = valuePill.rmsRowBox

    titleElement:setSize(box.titleWidth, nil)
    titleElement:setText(titleText)

    RMS_Utils.fitValuePill(valuePill, valueElement, nil, valueText)
    giveLabelRoom(titleElement, box.titleGap, valuePill, valueElement)
end

RMS_Utils.SCROLL_SPEED = 0.5

---Advances one scrolling text at the shared speed
local function updateScrollingText(element, dt)
    TextElement.update(element, dt * RMS_Utils.SCROLL_SPEED)
end

---Keeps a scrolling text where it was when the engine moves it
local function updateScrollingTextPosition(element)
    TextElement.updateAbsolutePosition(element)
    -- Rewind the native offset without advancing its retained clock.
    TextElement.update(element, 0)
end

---Puts every scrolling text of a branch on the shared speed, cells included
-- @param table element root element to walk
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
-- @param table? element root element to walk
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
-- @param table button action button holding an icon child
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
-- @param table labelElement row label
-- @param table valueElement row value, right aligned
-- @param string labelText localized label
-- @param string valueText localized value
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


-- @param table element button whose children carry the selected artwork
function RMS_Utils.mirrorSelectionToChildren(element)
    for _, child in ipairs(element.elements) do
        child.getIsSelected = function()
            return element:getIsSelected()
        end
    end
end


---Returns the element a sideways move enters a neighbouring column by
local function getFocusColumnEntry(rows, rowIndex, isFromRight)
    if rows == nil then
        return nil
    end

    local row = rows[math.min(rowIndex, #rows)]
    return isFromRight and row[#row] or row[1]
end

---Links the focus over what a screen shows
-- @param table? top element above every column, the tab selector of a workshop screen
-- @param table columns columns of rows of elements
-- @param table? preferred element the screen opens on
-- @return table? entry preferred, first focusable, or top element
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
        FocusManager:linkElements(top, FocusManager.BOTTOM, entry ~= top and entry or nil)
    end
    return entry
end

---Hands the focus to an element when what held it is no longer shown
-- @param table? entry element to focus
function RMS_Utils.keepFocusShown(entry)
    local focused = FocusManager:getFocusedElement()
    if entry ~= nil and (focused == nil or not focused:getIsVisible()) then
        FocusManager:setFocus(entry)
    end
end
