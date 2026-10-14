-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---Drivetrain system: drive mode, differential lock, windup and park brake
RMS_Drivetrain = RMS_Drivetrain or {}

-- drive modes, in cycling order
RMS_Drivetrain.MODE = {
    TWO_WD  = 0,
    FOUR_WD = 1,
    AUTO    = 2
}

-- l10n key of each drive mode
RMS_Drivetrain.MODE_L10N = {
    [0] = "rms_drivetrain_mode_4x2",
    [1] = "rms_drivetrain_mode_4wd",
    [2] = "rms_drivetrain_mode_auto"
}

-- park brake kinds, by who applies the brake and what releases it
RMS_Drivetrain.PARK_KIND = {
    LEVER     = 0,
    AUTOMATIC = 1,
    AIR_VALVE = 2
}

local PARK_THROTTLE_THRESHOLD = 0.2
local PARK_STANDSTILL_KMH = 1.0

local LOCKED_MIN_TORQUE_RATIO = 0.1
local LOCKED_MAX_TORQUE_RATIO = 0.9
local LOCKED_TORQUE_DEAD_ZONE = 0.02
local LOCKED_WHEEL_SPEED_FILTER = 0.2
local TRACK_STEER_INPUT_EPSILON = 0.001
local DEBUG_RATIO_MIN_SPEED = 0.05
local DEBUG_RATIO_MAX = 99
local DIFF_LOCK_RELEASE_KMH = 10

local sanitizeNumber = RealisticMechanicalSystems.sanitizeNumber

---Returns the drivetrain configuration section
local function getConfig()
    return RMS_Config.DRIVETRAIN
end

---Returns the share of motor torque sent to the driveline
-- @param table? vehicle vehicle
-- @return float load driveline load ratio between 0 and 1
function RMS_Drivetrain.getDrivelineLoad(vehicle)
    local motor = vehicle ~= nil and vehicle.getMotor ~= nil and vehicle:getMotor() or nil
    if motor == nil
            or motor.getMotorAppliedTorque == nil
            or motor.getMotorExternalTorque == nil
            or motor.getMotorAvailableTorque == nil then
        return 0
    end

    local availableTorque = sanitizeNumber(motor:getMotorAvailableTorque(), 0, 0)
    if availableTorque <= 0.0001 then
        return 0
    end

    local appliedTorque = sanitizeNumber(motor:getMotorAppliedTorque(), 0, 0)
    local externalTorque = sanitizeNumber(motor:getMotorExternalTorque(), 0, 0)
    return math.clamp((appliedTorque - externalTorque) / availableTorque, 0, 1)
end

---Asks the other drivetrain mod to switch off the functions RMS drives
function RMS_Drivetrain.claimFromOtherMod()
    if not g_modIsLoaded["FS25_EnhancedVehicle"] then
        return
    end

    local otherMod = FS25_EnhancedVehicle.FS25_EnhancedVehicle
    if otherMod == nil or otherMod.functionEnable == nil then
        return
    end

    if getConfig().ENABLED and otherMod:functionStatus("differential") then
        otherMod:functionEnable("differential", false)
    end
    if getConfig().PARKBRAKE_ENABLED and otherMod:functionStatus("park") then
        otherMod:functionEnable("park", false)
    end
    if otherMod:functionStatus("odometer") then
        otherMod:functionEnable("odometer", false)
    end
end

---Returns the store categories of a vehicle
local function getStoreCategoryNames(vehicle)
    if vehicle == nil or vehicle.configFileName == nil then
        return nil
    end

    local storeItem = g_storeManager:getItemByXMLFilename(vehicle.configFileName)
    if storeItem == nil then
        return nil
    end

    if storeItem.categoryNames ~= nil and #storeItem.categoryNames > 0 then
        return storeItem.categoryNames
    end

    if storeItem.categoryName ~= nil then
        return { storeItem.categoryName }
    end

    return nil
end

---Tells whether the vehicle sits in one of the excluded road categories
-- @param table? vehicle vehicle
-- @return boolean isRoadVehicle true for an excluded category
function RMS_Drivetrain.getIsRoadVehicleCategory(vehicle)
    local categoryNames = getStoreCategoryNames(vehicle)
    if categoryNames == nil then
        return false
    end

    local excludedCategories = getConfig().EXCLUDED_CATEGORIES
    for _, categoryName in ipairs(categoryNames) do
        local normalizedCategoryName = string.upper(tostring(categoryName or ""))
        if excludedCategories ~= nil and excludedCategories[normalizedCategoryName] == true then
            return true
        end
    end

    return false
end

---Tells whether a wheel steers, on its rotation range or its rotation speed
-- @param table? wheel wheel
-- @return boolean isSteerable true for a steering wheel
function RMS_Drivetrain.getIsWheelSteerable(wheel)
    local physics = wheel ~= nil and wheel.physics or nil
    if physics == nil then return false end
    local rotMin = tonumber(physics.rotMin) or 0
    local rotMax = tonumber(physics.rotMax) or 0
    if math.abs(rotMax - rotMin) > 0.01 then
        return true
    end
    return math.abs(tonumber(physics.rotSpeed) or 0) > 0.001
end

---Returns the longitudinal position of a wheel
local function getWheelLocalZ(wheel)
    local physics = wheel ~= nil and wheel.physics or nil
    if physics == nil then return 0 end
    return tonumber(physics.positionZ) or (physics.netInfo ~= nil and tonumber(physics.netInfo.z)) or 0
end

---Returns the axle speed of a wheel, 0 without a wheel shape
local function getWheelAxleSpeed(wheel)
    local physics = wheel ~= nil and wheel.physics or nil
    if wheel == nil or wheel.node == nil or physics == nil or not physics.wheelShapeCreated then
        return 0
    end
    return tonumber(getWheelShapeAxleSpeed(wheel.node, physics.wheelShape)) or 0
end

---Walks a differential subtree and collects the wheel indices it drives
local function collectWheelIndices(differentials, diffIndex0, wheelIndices, visited)
    local runtimeIndex = (tonumber(diffIndex0) or -1) + 1
    if runtimeIndex < 1 or visited[runtimeIndex] then return end
    local differential = differentials[runtimeIndex]
    if differential == nil then return end
    visited[runtimeIndex] = true

    if differential.diffIndex1IsWheel then
        wheelIndices[#wheelIndices + 1] = tonumber(differential.diffIndex1)
    else
        collectWheelIndices(differentials, differential.diffIndex1, wheelIndices, visited)
    end
    if differential.diffIndex2IsWheel then
        wheelIndices[#wheelIndices + 1] = tonumber(differential.diffIndex2)
    else
        collectWheelIndices(differentials, differential.diffIndex2, wheelIndices, visited)
    end
end

---Returns how steerable an axle is and where it sits along the vehicle
local function getAxleScore(vehicle, wheelIndices)
    local steerableCount, zSum, count = 0, 0, 0
    for _, wheelIndex in ipairs(wheelIndices) do
        local wheel = vehicle.getWheelFromWheelIndex ~= nil and vehicle:getWheelFromWheelIndex(wheelIndex) or nil
        if wheel ~= nil then
            count = count + 1
            zSum = zSum + getWheelLocalZ(wheel)
            if RMS_Drivetrain.getIsWheelSteerable(wheel) then
                steerableCount = steerableCount + 1
            end
        end
    end
    if count == 0 then
        return 0, 0
    end
    return steerableCount / count, zSum / count
end

---Tells whether the vehicle runs on two crawler tracks and nothing else
local function getIsTwinTrack(vehicle)
    local spec_crawlers = vehicle.spec_crawlers
    local crawlers = spec_crawlers ~= nil and spec_crawlers.crawlers or nil
    if crawlers == nil or #crawlers ~= 2 then
        return false
    end

    local wheels = vehicle.spec_wheels ~= nil and vehicle.spec_wheels.wheels or nil
    if wheels == nil or #wheels == 0 then
        return false
    end

    local crawlerTireType = WheelsUtil.getTireType("crawler")
    if crawlerTireType == nil then
        return false
    end

    for _, wheel in ipairs(wheels) do
        local physics = wheel ~= nil and wheel.physics or nil
        if physics == nil or physics.tireType ~= crawlerTireType then
            return false
        end
    end

    return true
end

---Returns the center, primary axle and lockable differentials of a vehicle
-- @param table vehicle vehicle
-- @return table? layout drivetrain layout, nil without differentials
function RMS_Drivetrain.buildLayout(vehicle)
    local spec_motorized = vehicle.spec_motorized
    local differentials = spec_motorized ~= nil and spec_motorized.differentials or nil
    if differentials == nil or next(differentials) == nil then
        return nil
    end

    local isTwinTrack = getIsTwinTrack(vehicle)
    local layout = {
        differentialCount = #differentials,
        isTwinTrack = isTwinTrack,
        isPermanentAllWheelDrive = false,
        originals = {},
        centerIdx0 = nil,
        primaryIdx0 = nil,
        engageableWheelIndices = {},
        primaryWheelIndices = {},
        lockableIdx0 = {},
        engageableAxleIdx0Set = {}
    }

    local referencedAsChild = {}
    for _, differential in ipairs(differentials) do
        if not differential.diffIndex1IsWheel then
            referencedAsChild[(tonumber(differential.diffIndex1) or -1) + 1] = true
        end
        if not differential.diffIndex2IsWheel then
            referencedAsChild[(tonumber(differential.diffIndex2) or -1) + 1] = true
        end
    end

    local rootCount = 0
    local mixedRootIdx0 = nil
    for i, differential in ipairs(differentials) do
        local idx0 = i - 1
        layout.originals[idx0] = {
            torqueRatio = tonumber(differential.torqueRatio) or 0.5,
            maxSpeedRatio = tonumber(differential.maxSpeedRatio) or 1.3,
            diffIndex1 = differential.diffIndex1,
            diffIndex1IsWheel = differential.diffIndex1IsWheel == true,
            diffIndex2 = differential.diffIndex2,
            diffIndex2IsWheel = differential.diffIndex2IsWheel == true
        }

        local isInterAxle = not differential.diffIndex1IsWheel and not differential.diffIndex2IsWheel
        if not referencedAsChild[i] then
            rootCount = rootCount + 1
            local isMixedRoot = differential.diffIndex1IsWheel ~= differential.diffIndex2IsWheel
            if isMixedRoot and mixedRootIdx0 == nil then
                mixedRootIdx0 = idx0
            elseif isInterAxle and layout.centerIdx0 == nil then
                layout.centerIdx0 = idx0
            end
        end
    end

    if isTwinTrack then
        layout.centerIdx0 = nil
    end

    if rootCount == 1 and mixedRootIdx0 ~= nil and not isTwinTrack then
        layout.isPermanentAllWheelDrive = true
        layout.centerIdx0 = nil
    elseif layout.centerIdx0 ~= nil then
        local center = differentials[layout.centerIdx0 + 1]
        local out1Idx0 = tonumber(center.diffIndex1) or 0
        local out2Idx0 = tonumber(center.diffIndex2) or 0

        local out1Wheels, out2Wheels = {}, {}
        collectWheelIndices(differentials, out1Idx0, out1Wheels, {})
        collectWheelIndices(differentials, out2Idx0, out2Wheels, {})

        local steer1, z1 = getAxleScore(vehicle, out1Wheels)
        local steer2, z2 = getAxleScore(vehicle, out2Wheels)

        local out1IsEngageable
        if steer1 ~= steer2 then
            out1IsEngageable = steer1 > steer2
        else
            out1IsEngageable = z1 > z2 -- vehicles face +Z
        end

        if out1IsEngageable then
            layout.primaryIdx0 = out2Idx0
            layout.engageableWheelIndices, layout.primaryWheelIndices = out1Wheels, out2Wheels
        else
            layout.primaryIdx0 = out1Idx0
            layout.engageableWheelIndices, layout.primaryWheelIndices = out2Wheels, out1Wheels
        end

        local engageableWheelSet = {}
        for _, wheelIndex in ipairs(layout.engageableWheelIndices) do
            engageableWheelSet[wheelIndex] = true
        end
        for i, differential in ipairs(differentials) do
            if differential.diffIndex1IsWheel and differential.diffIndex2IsWheel then
                local idx0 = i - 1
                layout.lockableIdx0[#layout.lockableIdx0 + 1] = idx0
                if engageableWheelSet[tonumber(differential.diffIndex1)] or engageableWheelSet[tonumber(differential.diffIndex2)] then
                    layout.engageableAxleIdx0Set[idx0] = true
                end
            end
        end
    else
        for i, differential in ipairs(differentials) do
            if differential.diffIndex1IsWheel and differential.diffIndex2IsWheel then
                local idx0 = i - 1
                layout.primaryIdx0 = layout.primaryIdx0 or idx0
                layout.lockableIdx0[#layout.lockableIdx0 + 1] = idx0
                collectWheelIndices(differentials, idx0, layout.primaryWheelIndices, {})
            end
        end
        if #layout.lockableIdx0 == 0 then
            return nil
        end
    end

    return layout
end

---Creates the drivetrain state on the vehicle spec
-- @param table? vehicle vehicle
function RMS_Drivetrain.initSpec(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    spec.drivetrain = {
        layout = nil,
        layoutAnalyzed = false,
        hasControl = false,
        hasCenterDiff = false,
        driveMode = RMS_Drivetrain.MODE.TWO_WD,
        autoEngaged = false,
        diffLockRequested = false,
        diffLockEngaged = false,
        parkBrake = true,
        parkKind = RMS_Drivetrain.PARK_KIND.LEVER,
        windupStress = 0,
        windupWearFactor = 0,
        windupActive = false,
        _windupDamageLatched = false,
        _appliedMode = nil,
        _appliedLock = nil,
        _activeDifferentialIndices = nil,
        _activeFourWheelDrive = nil,
        _graphManaged = false,
        _wheelPeripheralSpeeds = {},
        _wasAddedToPhysics = false,
        _autoConditionTimer = 0,
        _lastNotifiedMode = nil,
        _lastNotifiedLock = nil,
        _windupWarningCooldown = 0,
        _parkWarningCooldown = 0,
        _parkStandstillMs = 0,
        _parkWasAIActive = false,
        _parkGamePedal = 1
    }
end

---Returns the drivetrain state of a vehicle
-- @param table? vehicle vehicle
-- @return table? state drivetrain state
function RMS_Drivetrain.getState(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    return spec ~= nil and spec.drivetrain or nil
end

---Tells whether the drivetrain system runs on this vehicle
-- @param table? vehicle vehicle
-- @return boolean isAvailable true when RMS drives it
function RMS_Drivetrain.getIsAvailable(vehicle)
    local state = RMS_Drivetrain.getState(vehicle)
    return state ~= nil
        and state.hasControl == true
        and getConfig().ENABLED
end

---Tells whether the vehicle carries a center differential
-- @param table? vehicle vehicle
-- @return boolean hasCenter true with a center differential
function RMS_Drivetrain.getHasCenterDifferential(vehicle)
    local state = RMS_Drivetrain.getState(vehicle)
    return state ~= nil and state.hasCenterDiff == true
end

---Builds the layout on first use and caches it on the state
local function ensureLayout(vehicle, state)
    if state.layoutAnalyzed then
        return state.layout ~= nil
    end
    local spec_wheels = vehicle.spec_wheels
    if spec_wheels == nil or spec_wheels.wheels == nil or #spec_wheels.wheels == 0 then
        return false
    end
    state.layoutAnalyzed = true

    if RMS_Drivetrain.getIsRoadVehicleCategory(vehicle) then
        state.layout = nil
        state.hasControl = false
        state.hasCenterDiff = false
        RealisticMechanicalSystems.raiseRMSDirty(vehicle, RealisticMechanicalSystems.SYNC_GROUP.DRIVETRAIN)
        return false
    end

    state.layout = RMS_Drivetrain.buildLayout(vehicle)
    local isPermanentAllWheelDrive = state.layout ~= nil and state.layout.isPermanentAllWheelDrive == true
    state.hasControl = state.layout ~= nil and not isPermanentAllWheelDrive
    state.hasCenterDiff = state.layout ~= nil and state.layout.centerIdx0 ~= nil
    if isPermanentAllWheelDrive then
        state.driveMode = RMS_Drivetrain.MODE.FOUR_WD
        state.autoEngaged = false
        state.diffLockRequested = false
        state.diffLockEngaged = false
    end
    RealisticMechanicalSystems.raiseRMSDirty(vehicle, RealisticMechanicalSystems.SYNC_GROUP.DRIVETRAIN)
    return state.layout ~= nil
end

---Tells whether all wheels are driven right now
local function getEffectiveFourWheelDrive(state)
    if state.layout == nil or state.layout.centerIdx0 == nil then
        return true -- single-axle machines are always "engaged"
    end
    if state.driveMode == RMS_Drivetrain.MODE.FOUR_WD then
        return true
    elseif state.driveMode == RMS_Drivetrain.MODE.AUTO then
        return state.autoEngaged
    end
    return false
end

---Tells whether the engine locks the center differential itself
local function getIsNativeLock(layout, fourWheelDrive)
    return fourWheelDrive and layout.centerIdx0 ~= nil
end

---Returns the speed ratio of a differential for the current lock state
local function getTargetSpeedRatio(original, lockEngaged, nativeLock)
    local C = getConfig()

    if original.diffIndex1IsWheel and original.diffIndex2IsWheel then
        if lockEngaged then
            return nativeLock and original.maxSpeedRatio or C.LOCKED_AXLE_SPEED_RATIO
        end
        return math.max(original.maxSpeedRatio, C.OPEN_AXLE_SPEED_RATIO)
    end

    return original.maxSpeedRatio
end

---Builds the differential graph to install
local function buildDifferentialPlan(vehicle, state, useFullGraph)
    local layout = state.layout
    local lockEngaged = state.diffLockEngaged == true
    local nativeLock = getIsNativeLock(layout, useFullGraph)
    local plan = {}
    local sourceToNative = {}
    local visiting = {}

    ---Adds a source differential to the plan, its children first
    local function addSourceDifferential(sourceIdx0)
        local nativeIdx0 = sourceToNative[sourceIdx0]
        if nativeIdx0 ~= nil then
            return nativeIdx0
        end
        if visiting[sourceIdx0] then
            return nil
        end

        local original = layout.originals[sourceIdx0]
        if original == nil then
            return nil
        end
        visiting[sourceIdx0] = true

        ---Resolves one differential output to a wheel shape or a child index
        local function resolveOutput(outputIndex, outputIsWheel)
            if outputIsWheel then
                local wheel = vehicle.getWheelFromWheelIndex ~= nil and vehicle:getWheelFromWheelIndex(outputIndex) or nil
                local physics = wheel ~= nil and wheel.physics or nil
                local wheelShape = tonumber(physics ~= nil and physics.wheelShape) or 0
                if wheelShape == 0 then
                    return nil
                end
                return wheelShape
            end
            return addSourceDifferential(outputIndex)
        end

        local output1 = resolveOutput(original.diffIndex1, original.diffIndex1IsWheel)
        local output2 = resolveOutput(original.diffIndex2, original.diffIndex2IsWheel)
        if output1 == nil or output2 == nil then
            return nil
        end

        nativeIdx0 = #plan
        plan[#plan + 1] = {
            output1 = output1,
            output1IsWheel = original.diffIndex1IsWheel,
            output2 = output2,
            output2IsWheel = original.diffIndex2IsWheel,
            torqueRatio = original.torqueRatio,
            maxSpeedRatio = getTargetSpeedRatio(original, lockEngaged, nativeLock)
        }
        sourceToNative[sourceIdx0] = nativeIdx0
        visiting[sourceIdx0] = nil
        return nativeIdx0
    end

    if useFullGraph or layout.centerIdx0 == nil then
        for sourceIdx0 = 0, layout.differentialCount - 1 do
            if addSourceDifferential(sourceIdx0) == nil then
                return nil, nil
            end
        end
    elseif layout.primaryIdx0 == nil or addSourceDifferential(layout.primaryIdx0) == nil then
        return nil, nil
    end

    return plan, sourceToNative
end

---Replaces the engine differential graph with the planned one
local function installDifferentialGraph(vehicle, state, useFullGraph)
    local spec_motorized = vehicle.spec_motorized
    if spec_motorized == nil or spec_motorized.motorizedNode == nil or not vehicle.isAddedToPhysics then
        return false
    end

    local plan, sourceToNative = buildDifferentialPlan(vehicle, state, useFullGraph)
    if plan == nil then
        return false
    end

    local node = spec_motorized.motorizedNode
    removeAllDifferentials(node)
    for _, differential in ipairs(plan) do
        addDifferential(
            node,
            differential.output1,
            differential.output1IsWheel,
            differential.output2,
            differential.output2IsWheel,
            differential.torqueRatio,
            differential.maxSpeedRatio
        )
    end
    vehicle:updateMotorProperties()

    state._activeDifferentialIndices = sourceToNative
    state._activeFourWheelDrive = useFullGraph or state.layout.centerIdx0 == nil
    state._graphManaged = true
    return true
end

---Puts the original differential graph back on the vehicle
local function restoreOriginalDifferentialGraph(vehicle, state)
    if not state._graphManaged then
        return true
    end

    if vehicle.isAddedToPhysics and not installDifferentialGraph(vehicle, state, true) then
        return false
    end

    state._activeDifferentialIndices = nil
    state._activeFourWheelDrive = nil
    state._graphManaged = false
    return true
end

---Installs the differential graph matching the current drive mode
-- @param table vehicle vehicle
-- @param boolean? force true to reinstall even when nothing changed
function RMS_Drivetrain.applyState(vehicle, force)
    if not vehicle.isServer then return end

    local state = RMS_Drivetrain.getState(vehicle)
    local spec_motorized = vehicle.spec_motorized
    if state == nil or not state.hasControl or state.layout == nil or spec_motorized == nil or spec_motorized.motorizedNode == nil then
        return
    end
    if not vehicle.isAddedToPhysics then
        return
    end

    local layout = state.layout
    local fourWheelDrive = getEffectiveFourWheelDrive(state)
    if not force
        and state._graphManaged
        and state._activeFourWheelDrive == fourWheelDrive
        and state._appliedMode == fourWheelDrive then
        return
    end

    if not installDifferentialGraph(vehicle, state, fourWheelDrive) then
        return
    end

    state._appliedMode = fourWheelDrive
    state._appliedLock = nil
end

---Hands the drivetrain back to the game, the machine parked
-- @param table vehicle vehicle
function RMS_Drivetrain.releaseControl(vehicle)
    local state = RMS_Drivetrain.getState(vehicle)
    if state == nil or not vehicle.isServer then
        return
    end

    if not state.parkBrake then
        RMS_Drivetrain.setDrivetrainState(vehicle, state.driveMode, state.diffLockRequested, true, false)
    end
    RMS_Drivetrain.refreshParkBrakePedal(vehicle)

    if state._graphManaged or state._appliedMode ~= nil or state._appliedLock ~= nil then
        state.autoEngaged = false
        state.diffLockEngaged = false
        if restoreOriginalDifferentialGraph(vehicle, state) then
            state._appliedMode = nil
            state._appliedLock = nil
        end
    end

    state._windupDamageLatched = false
    state.windupActive = false
    state.windupStress = 0
    state.windupWearFactor = 0
    RealisticMechanicalSystems.raiseRMSDirty(vehicle, RealisticMechanicalSystems.SYNC_GROUP.DRIVETRAIN)
end

---Shifts the torque ratio toward the slower output of a locked axle differential
local function getLockedTorqueRatio(original, speed1, speed2, gearRatio)
    local torqueRatio = original.torqueRatio

    if gearRatio < 0 then
        speed1 = -speed1
        speed2 = -speed2
    end

    local isStandstill = speed1 < 0.1389 and speed2 < 0.1389
    local isOutOfRange = not (-0.2778 < speed1 and speed1 < 90 and -0.2778 < speed2 and speed2 < 90)
    if isStandstill or isOutOfRange then
        return torqueRatio
    end

    if speed1 < speed2 then
        torqueRatio = 1 - (math.max(speed1, 0) / speed2) * (1 - torqueRatio)
    elseif speed2 < speed1 then
        torqueRatio = torqueRatio * (math.max(speed2, 0) / speed1)
    end

    if math.abs(torqueRatio - original.torqueRatio) < LOCKED_TORQUE_DEAD_ZONE then
        return original.torqueRatio
    end

    return math.clamp(torqueRatio, LOCKED_MIN_TORQUE_RATIO, LOCKED_MAX_TORQUE_RATIO)
end

---Returns the two output speeds of a differential
local function getDifferentialOutputSpeeds(vehicle, state, differentialIdx0, wheelSpeeds, depth)
    local layout = state.layout
    if depth > layout.differentialCount then
        return 0, 0
    end

    local differential = layout.originals[differentialIdx0]
    if differential == nil then
        return 0, 0
    end

    ---Returns the speed of one output, wheel or child differential
    local function getOutputSpeed(outputIndex, outputIsWheel)
        if outputIsWheel then
            local speed = wheelSpeeds[outputIndex]
            if speed ~= nil then
                return speed
            end

            local wheel = vehicle.getWheelFromWheelIndex ~= nil and vehicle:getWheelFromWheelIndex(outputIndex) or nil
            local physics = wheel ~= nil and wheel.physics or nil
            local rawSpeed = 0
            if wheel ~= nil and wheel.node ~= nil and physics ~= nil and physics.wheelShapeCreated then
                rawSpeed = getWheelAxleSpeed(wheel) * (tonumber(physics.radius) or 0)
            end

            local previousSpeed = state._wheelPeripheralSpeeds[outputIndex]
            speed = previousSpeed == nil and rawSpeed
                or previousSpeed + LOCKED_WHEEL_SPEED_FILTER * (rawSpeed - previousSpeed)
            state._wheelPeripheralSpeeds[outputIndex] = speed
            wheelSpeeds[outputIndex] = speed
            return speed
        end

        local childSpeed1, childSpeed2 = getDifferentialOutputSpeeds(vehicle, state, outputIndex, wheelSpeeds, depth + 1)
        return (childSpeed1 + childSpeed2) * 0.5
    end

    return getOutputSpeed(differential.diffIndex1, differential.diffIndex1IsWheel),
        getOutputSpeed(differential.diffIndex2, differential.diffIndex2IsWheel)
end

---Applies the torque and speed ratios of the current lock state
local function applyDifferentialLock(vehicle, state)
    local spec_motorized = vehicle.spec_motorized
    local activeIndices = state._activeDifferentialIndices
    if spec_motorized == nil or spec_motorized.motorizedNode == nil or activeIndices == nil or not vehicle.isAddedToPhysics then
        return
    end

    local lockEngaged = state.diffLockEngaged == true
    if not lockEngaged and state._appliedLock == false then
        return
    end

    local layout = state.layout
    local nativeLock = getIsNativeLock(layout, state._activeFourWheelDrive == true)
    local wheelSpeeds = {}
    local gearRatio = tonumber(spec_motorized.motor ~= nil and spec_motorized.motor.gearRatio) or 0

    if lockEngaged and state._appliedLock ~= true then
        state._wheelPeripheralSpeeds = {}
    else
        state._wheelPeripheralSpeeds = state._wheelPeripheralSpeeds or {}
    end

    for sourceIdx0 = 0, layout.differentialCount - 1 do
        local nativeIdx0 = activeIndices[sourceIdx0]
        local original = layout.originals[sourceIdx0]
        if nativeIdx0 ~= nil and original ~= nil then
            local isAxleDifferential = original.diffIndex1IsWheel and original.diffIndex2IsWheel
            local torqueRatio = original.torqueRatio
            local maxSpeedRatio = getTargetSpeedRatio(original, lockEngaged, nativeLock)
            if lockEngaged and isAxleDifferential and not nativeLock then
                local speed1, speed2 = getDifferentialOutputSpeeds(vehicle, state, sourceIdx0, wheelSpeeds, 1)
                torqueRatio = getLockedTorqueRatio(original, speed1, speed2, gearRatio)
            end

            updateDifferential(spec_motorized.motorizedNode, nativeIdx0, torqueRatio, maxSpeedRatio)
        end
    end

    state._appliedLock = lockEngaged
end

---Reapplies the managed graph and brakes after the game rebuilds physics
-- @param table vehicle vehicle
-- @param function superFunc overwritten function
-- @return boolean success true when the vehicle was added to physics
function RMS_Drivetrain.addToPhysics(vehicle, superFunc)
    local success = superFunc(vehicle)
    if not success then
        return false
    end

    local spec = vehicle.spec_RealisticMechanicalSystems
    local state = spec ~= nil and spec.drivetrain or nil
    if state == nil then
        return true
    end

    state._wasAddedToPhysics = vehicle.isAddedToPhysics == true
    RMS_Drivetrain.restoreFreeRolling(vehicle)

    if vehicle.isServer
        and not spec.isExcludedVehicle
        and getConfig().ENABLED
        and ensureLayout(vehicle, state)
        and state.hasControl then
        RMS_Drivetrain.applyState(vehicle, true)
        applyDifferentialLock(vehicle, state)
    end

    return true
end

-- sample played on a park brake change, per kind then per new state
local PARK_SAMPLES = {
    [RMS_Drivetrain.PARK_KIND.LEVER]     = { [true] = "parkBrakeLeverApply", [false] = "parkBrakeLeverRelease" },
    [RMS_Drivetrain.PARK_KIND.AUTOMATIC] = { [true] = "parkBrakeAutoApply",  [false] = "parkBrakeAutoRelease" },
    [RMS_Drivetrain.PARK_KIND.AIR_VALVE] = { [true] = "parkBrakeTruckApply", [false] = "parkBrakeTruckRelease" }
}
-- an automatic park brake on a machine without air brakes is heard as its switch
local PARK_SWITCH_SAMPLES = { [true] = "parkBrakeSwitchOn", [false] = "parkBrakeSwitchOff" }

---Returns how far the driver presses a drive pedal
local function getThrottle(vehicle)
    local spec_drivable = vehicle.spec_drivable
    return spec_drivable ~= nil and math.abs(spec_drivable.axisForward) or 0
end

---Tells whether the driver asks the machine to move
local function getHasDriveDemand(vehicle)
    if vehicle.spec_drivable == nil then
        return false
    end

    return getThrottle(vehicle) > PARK_THROTTLE_THRESHOLD
        or vehicle:getCruiseControlState() ~= Drivable.CRUISECONTROL_STATE_OFF
end

---Tells whether another vehicle tows this one
local function getIsTowed(vehicle)
    return vehicle.getAttacherVehicle ~= nil and vehicle:getAttacherVehicle() ~= nil
end

---Tells whether RMS runs the park brake of this vehicle
-- @param table vehicle vehicle
-- @return boolean isManaged true when the park brake is simulated
function RMS_Drivetrain.getIsParkBrakeManaged(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    local state = spec ~= nil and spec.drivetrain or nil
    return state ~= nil
        and getConfig().PARKBRAKE_ENABLED
        and not spec.isExcludedVehicle
end

---Returns the share of the brake pedal the applied park brake holds
local function getParkBrakeHold(state)
    if state.parkKind == RMS_Drivetrain.PARK_KIND.AUTOMATIC then
        return 1
    elseif state.parkKind == RMS_Drivetrain.PARK_KIND.AIR_VALVE then
        return getConfig().PARKBRAKE_AIR_HOLD
    end
    return getConfig().PARKBRAKE_LEVER_HOLD
end

---Returns the drivetrain state while the park brake acts on the brakes
local function getActingParkState(vehicle)
    if not RMS_Drivetrain.getIsParkBrakeManaged(vehicle) or vehicle:getIsAIActive() or getIsTowed(vehicle) then
        return nil
    end

    return RMS_Drivetrain.getState(vehicle)
end

---Tells whether a motor drives through a gearbox with a clutch
local function getHasClutchGearbox(motor)
    return motor.minForwardGearRatio == nil and motor.gearType ~= VehicleMotor.TRANSMISSION_TYPE.POWERSHIFT
end

---Tells whether the stopped engine holds the machine through an engaged gear
local function getIsHeldInGear(vehicle)
    return not vehicle:getIsMotorStarted()
        and getHasClutchGearbox(vehicle:getMotor())
        and not vehicle:getIsMotorInNeutral()
end

---Tells whether nothing holds the machine
-- @param table vehicle vehicle
-- @return boolean isRollingFree true while the machine rolls on its own
function RMS_Drivetrain.getIsRollingFree(vehicle)
    local state = getActingParkState(vehicle)
    if state == nil or state.parkBrake or state.parkKind == RMS_Drivetrain.PARK_KIND.AUTOMATIC
            or getIsHeldInGear(vehicle) then
        return false
    end

    return not vehicle:getIsControlled() or vehicle:getMotor().lowBrakeForceLocked == true
end

---Returns the brake pedal the park brake makes of the one the game asks for
-- @param table vehicle vehicle
-- @param float brakePedal brake pedal asked by the game
-- @return float brakePedal brake pedal to apply
function RMS_Drivetrain.getParkBrakePedal(vehicle, brakePedal)
    local state = getActingParkState(vehicle)
    if state == nil then
        return brakePedal
    elseif state.parkBrake then
        return math.max(brakePedal, getParkBrakeHold(state))
    elseif RMS_Drivetrain.getIsRollingFree(vehicle) then
        return getConfig().PARKBRAKE_ROLLING_RESISTANCE
    end

    return brakePedal
end

---Applies the brake pedal the park brake leaves
-- @param table vehicle vehicle
-- @param function superFunc overwritten function
-- @param float brakePedal brake pedal asked by the game
-- @param any ... additional brake arguments
function RMS_Drivetrain.brake(vehicle, superFunc, brakePedal, ...)
    local state = RMS_Drivetrain.getState(vehicle)
    if state ~= nil then
        state._parkGamePedal = brakePedal
    end

    return superFunc(vehicle, RMS_Drivetrain.getParkBrakePedal(vehicle, brakePedal), ...)
end

---Returns the brake pedal the game asks for, before the park brake adds its hold
-- @param table vehicle vehicle
-- @return float brakePedal brake pedal between 0 and 1
function RMS_Drivetrain.getGameBrakePedal(vehicle)
    return RMS_Drivetrain.getState(vehicle)._parkGamePedal
end

---Runs the park brake around the physics step of the game
-- @param table vehicle vehicle
-- @param function superFunc overwritten function
-- @param float axisForward forward axis input
-- @param float axisSide side axis input
-- @param boolean doHandbrake handbrake input
-- @param float dt time since last call in ms
-- @return float acceleration acceleration the game applied
function RMS_Drivetrain.updateVehiclePhysics(vehicle, superFunc, axisForward, axisSide, doHandbrake, dt)
    if RMS_Drivetrain.getIsParkBrakeEngaged(vehicle) then
        if RMS_Drivetrain.getState(vehicle).parkKind == RMS_Drivetrain.PARK_KIND.AUTOMATIC then
            axisForward = 0
            doHandbrake = true
        elseif vehicle:getCruiseControlState() ~= Drivable.CRUISECONTROL_STATE_OFF then
            vehicle:setCruiseControlState(Drivable.CRUISECONTROL_STATE_OFF)
        end
    end

    local acceleration = superFunc(vehicle, axisForward, axisSide, doHandbrake, dt)

    if RMS_Drivetrain.getIsRollingFree(vehicle) then
        vehicle:stopVehicle()
    end

    return acceleration
end

---Puts a free rolling machine back on its rolling resistance
-- @param table vehicle vehicle
function RMS_Drivetrain.restoreFreeRolling(vehicle)
    if not vehicle.isServer or not vehicle.isAddedToPhysics or not RMS_Drivetrain.getIsRollingFree(vehicle) then
        return
    end

    local brakePedal = getConfig().PARKBRAKE_ROLLING_RESISTANCE
    for _, wheel in ipairs(vehicle.spec_wheels.wheels) do
        wheel:setBrakePedal(brakePedal)
    end
    SpecializationUtil.raiseEvent(vehicle, "onBrake", brakePedal)
end

---Passes the last brake request through the park brake again
-- @param table vehicle vehicle
function RMS_Drivetrain.refreshParkBrakePedal(vehicle)
    if not vehicle.isServer or not vehicle.isAddedToPhysics then
        return
    end

    vehicle:brake(RMS_Drivetrain.getState(vehicle)._parkGamePedal)
    RMS_Drivetrain.restoreFreeRolling(vehicle)
end

---Passes every tracked machine through the park brake again
function RMS_Drivetrain.refreshAllParkBrakePedals()
    for _, vehicle in pairs(RMS_Main.vehicles) do
        RMS_Drivetrain.refreshParkBrakePedal(vehicle)
    end
end

---Plays the sound of the park brake being applied or released
local function playParkBrakeSound(vehicle, state)
    if not vehicle.isClient or not RMS_Drivetrain.getIsParkBrakeManaged(vehicle) then
        return
    end

    local samples = PARK_SAMPLES[state.parkKind]
    if state.parkKind == RMS_Drivetrain.PARK_KIND.AUTOMATIC and vehicle.spec_motorized.consumersByFillTypeName.AIR == nil then
        samples = PARK_SWITCH_SAMPLES
    end
    RMS_SoundManager.playSample(vehicle.spec_RealisticMechanicalSystems.samples[samples[state.parkBrake]])
end

---Resolves the park brake a vehicle carries: air valve, automatic or lever
-- @param table vehicle vehicle
function RMS_Drivetrain.resolveParkBrakeKind(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    local state = spec.drivetrain
    local kind = RMS_Drivetrain.PARK_KIND.LEVER

    if RMS_Drivetrain.getIsRoadVehicleCategory(vehicle) then
        if vehicle.spec_motorized.consumersByFillTypeName.AIR ~= nil then
            kind = RMS_Drivetrain.PARK_KIND.AIR_VALVE
        end
    elseif not getHasClutchGearbox(vehicle:getMotor()) and spec.year >= getConfig().PARKBRAKE_AUTO_MIN_YEAR then
        kind = RMS_Drivetrain.PARK_KIND.AUTOMATIC
    end

    if state.parkKind ~= kind then
        state.parkKind = kind
        RealisticMechanicalSystems.raiseRMSDirty(vehicle, RealisticMechanicalSystems.SYNC_GROUP.DRIVETRAIN)
        RMS_Drivetrain.refreshParkBrakePedal(vehicle)
    end
end

---Runs the park brake as the driver leaves
-- @param table vehicle vehicle
-- @param boolean wasEntered true for the player who was driving
function RMS_Drivetrain.onDriverLeft(vehicle, wasEntered)
    if not RMS_Drivetrain.getIsParkBrakeManaged(vehicle) or vehicle:getIsAIActive() then
        return
    end

    local state = RMS_Drivetrain.getState(vehicle)
    local isAutomatic = state.parkKind == RMS_Drivetrain.PARK_KIND.AUTOMATIC
    if vehicle.isServer then
        if isAutomatic and not state.parkBrake and vehicle:getLastSpeed() < PARK_STANDSTILL_KMH then
            RMS_Drivetrain.setParkBrake(vehicle, true, false)
        end
        RMS_Drivetrain.restoreFreeRolling(vehicle)
    end

    if wasEntered and not isAutomatic and not state.parkBrake then
        g_currentMission:showBlinkingWarning(g_i18n:getText("rms_drivetrain_warning_parkbrake_released"), 4000)
    end
end

---Returns the wear the brakes take from driving against the applied park brake
-- @param table vehicle vehicle
-- @return float factor wear factor, zero while the brake is released or the machine stands
function RMS_Drivetrain.getParkBrakeDragFactor(vehicle)
    if not RMS_Drivetrain.getIsParkBrakeEngaged(vehicle) or vehicle:getLastSpeed() < PARK_STANDSTILL_KMH then
        return 0
    end

    return getConfig().PARKBRAKE_DRAG_WEAR_MULTIPLIER
end

---Sets the drive mode, the lock request and the park brake, and syncs them
-- @param table vehicle vehicle
-- @param integer? driveMode drive mode
-- @param boolean? diffLockRequested true to ask for the lock
-- @param boolean? parkBrake true to engage the park brake
-- @param boolean? noEventSend no event send
function RMS_Drivetrain.setDrivetrainState(vehicle, driveMode, diffLockRequested, parkBrake, noEventSend)
    local state = RMS_Drivetrain.getState(vehicle)
    if state == nil then return end

    if state.layout ~= nil and state.layout.isPermanentAllWheelDrive == true then
        driveMode = RMS_Drivetrain.MODE.FOUR_WD
        diffLockRequested = false
    else
        driveMode = math.clamp(math.floor(tonumber(driveMode) or state.driveMode), 0, 2)
        if not getConfig().ALLOW_AUTO_MODE and driveMode == RMS_Drivetrain.MODE.AUTO then
            driveMode = RMS_Drivetrain.MODE.FOUR_WD
        end
        diffLockRequested = diffLockRequested == true
    end
    if parkBrake == nil then parkBrake = state.parkBrake end
    parkBrake = parkBrake == true

    local parkChanged = state.parkBrake ~= parkBrake
    local changed = state.driveMode ~= driveMode
        or state.diffLockRequested ~= diffLockRequested
        or parkChanged
    state.driveMode = driveMode
    state.diffLockRequested = diffLockRequested
    state.parkBrake = parkBrake

    if parkChanged then
        state._parkStandstillMs = 0
        playParkBrakeSound(vehicle, state)
        RMS_Drivetrain.refreshParkBrakePedal(vehicle)
    end

    if vehicle.isServer then
        if state.driveMode ~= RMS_Drivetrain.MODE.AUTO then
            state.autoEngaged = false
            state._autoConditionTimer = 0
        end
        if changed then
            RealisticMechanicalSystems.raiseRMSDirty(vehicle, RealisticMechanicalSystems.SYNC_GROUP.DRIVETRAIN)
        end
    elseif changed then
        RMS_DrivetrainEvent.sendEvent(vehicle, noEventSend)
    end
end

---Sets the park brake
-- @param table vehicle vehicle
-- @param boolean engaged true to engage it
-- @param boolean? noEventSend no event send
function RMS_Drivetrain.setParkBrake(vehicle, engaged, noEventSend)
    local state = RMS_Drivetrain.getState(vehicle)
    if state == nil then return end
    RMS_Drivetrain.setDrivetrainState(vehicle, state.driveMode, state.diffLockRequested, engaged, noEventSend)
end

---Steps to the next drive mode, skipping the automatic one when it is disabled
-- @param table vehicle vehicle
function RMS_Drivetrain.cycleDriveMode(vehicle)
    local state = RMS_Drivetrain.getState(vehicle)
    if state == nil or not state.hasCenterDiff then return end

    local nextMode
    if state.driveMode == RMS_Drivetrain.MODE.TWO_WD then
        nextMode = RMS_Drivetrain.MODE.FOUR_WD
    elseif state.driveMode == RMS_Drivetrain.MODE.FOUR_WD then
        nextMode = getConfig().ALLOW_AUTO_MODE and RMS_Drivetrain.MODE.AUTO or RMS_Drivetrain.MODE.TWO_WD
    else
        nextMode = RMS_Drivetrain.MODE.TWO_WD
    end

    RMS_Drivetrain.setDrivetrainState(vehicle, nextMode, state.diffLockRequested, state.parkBrake)
end

---Toggles the differential lock request
-- @param table vehicle vehicle
function RMS_Drivetrain.toggleDiffLock(vehicle)
    local state = RMS_Drivetrain.getState(vehicle)
    if state == nil or not state.hasControl then return end
    RMS_Drivetrain.setDrivetrainState(vehicle, state.driveMode, not state.diffLockRequested, state.parkBrake)
end

---Toggles the park brake, an automatic one releasing on a running engine only
-- @param table vehicle vehicle
function RMS_Drivetrain.toggleParkBrake(vehicle)
    local state = RMS_Drivetrain.getState(vehicle)
    if state == nil then return end
    if state.parkBrake and state.parkKind == RMS_Drivetrain.PARK_KIND.AUTOMATIC and not vehicle:getIsMotorStarted() then
        g_currentMission:showBlinkingWarning(g_i18n:getText("rms_drivetrain_warning_parkbrake_engine_off"), 2500)
        return
    end
    if not state.parkBrake and vehicle.spec_drivable ~= nil then
        vehicle:setCruiseControlState(Drivable.CRUISECONTROL_STATE_OFF)
    end
    RMS_Drivetrain.setParkBrake(vehicle, not state.parkBrake)
end

---Engages all wheel drive on slip or load at low speed
local function updateAutoMode(vehicle, state, spec, dt)
    if state.driveMode ~= RMS_Drivetrain.MODE.AUTO then return end

    local C = getConfig()
    local speed = sanitizeNumber(vehicle:getLastSpeed(), 0, 0, 1000)
    local slip = sanitizeNumber(spec.wheelSlipIntensity, 0, 0, 3)
    local motorLoad = sanitizeNumber(spec.dynamicMotorLoad or 0, 0, 0, 1.5)

    local wantsEngage = slip > C.AUTO_ENGAGE_SLIP_THRESHOLD
        or (speed < C.AUTO_ENGAGE_SPEED and motorLoad > C.AUTO_ENGAGE_LOAD_THRESHOLD)

    if state.autoEngaged then
        local wantsRelease = speed > C.AUTO_DISENGAGE_SPEED and slip < 0.05
        if wantsRelease then
            state._autoConditionTimer = state._autoConditionTimer + dt
            if state._autoConditionTimer >= C.AUTO_HYSTERESIS_MS then
                state.autoEngaged = false
                state._autoConditionTimer = 0
            end
        else
            state._autoConditionTimer = 0
        end
    else
        if wantsEngage then
            state.autoEngaged = true
            state._autoConditionTimer = 0
        end
    end
end

---Engages the lock below the release speed and drops it above
local function updateDiffLockState(vehicle, state, dt)
    local speed = sanitizeNumber(vehicle:getLastSpeed(), 0, 0, 1000)

    if state.diffLockRequested then
        if state.diffLockEngaged then
            if speed > DIFF_LOCK_RELEASE_KMH then
                state.diffLockEngaged = false
                RMS_Drivetrain.setDrivetrainState(vehicle, state.driveMode, false, state.parkBrake, false)
            end
        else
            if speed <= DIFF_LOCK_RELEASE_KMH then
                state.diffLockEngaged = true
            end
        end
    else
        state.diffLockEngaged = false
    end
end

---Tells whether the vehicle is turning
-- @param table vehicle vehicle
-- @return boolean isTurning true while turning
function RMS_Drivetrain.getIsTurning(vehicle)
    local steerState = vehicle.spec_RealisticMechanicalSystems.chassisSteerState
    local steeringAngle = steerState.angleMagnitude
    if steeringAngle > getConfig().WINDUP_STEER_THRESHOLD then
        return true
    end

    return getIsTwinTrack(vehicle)
        and steerState.inputMagnitude > TRACK_STEER_INPUT_EPSILON
end

---Accumulates drivetrain windup while turning locked or in all wheel drive
local function updateWindupModel(vehicle, state, spec, dt)
    local C = getConfig()
    local fourWheelDrive = state.layout ~= nil and state.layout.centerIdx0 ~= nil and getEffectiveFourWheelDrive(state)
    local windupFactor = 0

    if state.diffLockEngaged then
        windupFactor = 1.0
    elseif fourWheelDrive then
        windupFactor = math.max(tonumber(C.WINDUP_4WD_FACTOR) or 0, 0)
    end

    if not state.diffLockEngaged then
        state._windupDamageLatched = false
    end

    if windupFactor <= 0
        or (vehicle.getIsAIActive ~= nil and vehicle:getIsAIActive()) then
        state.windupActive = false
        state.windupStress = math.max(state.windupStress - (dt / 1000) * C.WINDUP_RELEASE_RATE, 0)
        state.windupWearFactor = 0
        return
    end

    local speed = sanitizeNumber(vehicle:getLastSpeed(), 0, 0, 1000)
    local friction = sanitizeNumber(spec.avgTireGroundFrictionCoeff, 0, 0, 3)
    local steerState = spec.chassisSteerState
    local steering = sanitizeNumber(steerState ~= nil and steerState.angleMagnitude or 0, 0, 0)
    local trackSteeringInput = sanitizeNumber(steerState ~= nil and steerState.inputMagnitude or 0, 0, 0, 1)
    local isTwinTrack = state.layout ~= nil and state.layout.isTwinTrack == true
    local isSteering = (isTwinTrack and trackSteeringInput > TRACK_STEER_INPUT_EPSILON)
        or steering > C.WINDUP_STEER_THRESHOLD
    local surfaceFactor = state.diffLockEngaged and 1 or sanitizeNumber(spec.avgGroundSurfaceFactor, 0, 0, 1)

    local isWindingUp = speed > 1.0
        and isSteering
        and surfaceFactor > 0
        and friction >= C.WINDUP_FRICTION_THRESHOLD

    state.windupActive = isWindingUp

    if isWindingUp then
        local stressLimit = state.diffLockEngaged and 1.0 or math.max(tonumber(C.WINDUP_4WD_MAX_STRESS) or 0, 0)
        local steerFactor = isTwinTrack and trackSteeringInput or math.min(steering / 0.5, 1.0)
        local frictionFactor = math.min(friction / math.max(C.WINDUP_FRICTION_THRESHOLD, 0.001), 1.5)
        local speedFactor = math.min(speed / 10.0, 1.0)
        local rate = C.WINDUP_ACCUMULATION_RATE * steerFactor * frictionFactor * speedFactor * surfaceFactor * windupFactor
        if state.windupStress > stressLimit then
            state.windupStress = math.max(state.windupStress - (dt / 1000) * C.WINDUP_RELEASE_RATE, stressLimit)
        else
            state.windupStress = math.min(state.windupStress + (dt / 1000) * rate, stressLimit)
        end
    else
        local releaseBoost = 1.0 + (1.0 - surfaceFactor) + math.max(1.2 - friction, 0)
        state.windupStress = math.max(state.windupStress - (dt / 1000) * C.WINDUP_RELEASE_RATE * releaseBoost, 0)
    end

    if state.windupStress <= 0 then
        state._windupDamageLatched = false
    end

    if state.diffLockEngaged and state.windupStress >= 1.0 and not state._windupDamageLatched then
        local transmissionSystem = spec.systems ~= nil and spec.systems.transmission or nil
        if transmissionSystem ~= nil and transmissionSystem.enabled == true and vehicle.applyInstantDamageToSystem ~= nil then
            vehicle:applyInstantDamageToSystem(RealisticMechanicalSystems.SYSTEMS.TRANSMISSION, C.WINDUP_INSTANT_DAMAGE)
            state._windupDamageLatched = true
            state.windupStress = 0.5
            RealisticMechanicalSystems.raiseRMSDirty(vehicle, RealisticMechanicalSystems.SYNC_GROUP.WEAR)
        end
    end

    if state.windupStress > 0 and isWindingUp then
        state.windupWearFactor = state.windupStress * C.WINDUP_WEAR_MULTIPLIER * windupFactor
    else
        state.windupWearFactor = 0
    end

end

---Shows the drive mode, lock and park brake messages to the driving player
local function updateLocalNotifications(vehicle, state, dt)
    if g_dedicatedServerInfo ~= nil then return end
    local isControlled = vehicle:getIsActiveForInput(true)
        and not vehicle:getIsAIActive()
    if not isControlled then
        state._lastNotifiedMode = state.driveMode
        state._lastNotifiedAutoEngaged = state.autoEngaged
        state._lastNotifiedLock = state.diffLockEngaged
        return
    end

    local driveModeChanged = state._lastNotifiedMode ~= state.driveMode
    if driveModeChanged then
        if state._lastNotifiedMode ~= nil then
            local modeText = g_i18n:getText(RMS_Drivetrain.MODE_L10N[state.driveMode] or "rms_drivetrain_mode_4wd")
            g_currentMission.hud:addSideNotification({1, 1, 1, 1}, string.format(g_i18n:getText("rms_drivetrain_notify_mode"), modeText))
            RMS_SoundManager.playSample(RMS_Main.samples.notification2D)
        end
        state._lastNotifiedMode = state.driveMode
    end

    if driveModeChanged or state.driveMode ~= RMS_Drivetrain.MODE.AUTO then
        state._lastNotifiedAutoEngaged = state.autoEngaged
    elseif state._lastNotifiedAutoEngaged ~= state.autoEngaged then
        if state._lastNotifiedAutoEngaged ~= nil then
            local modeKey = state.autoEngaged and "rms_drivetrain_mode_4wd" or "rms_drivetrain_mode_4x2"
            local modeText = g_i18n:getText(modeKey)
            g_currentMission.hud:addSideNotification({1, 1, 1, 1}, string.format(g_i18n:getText("rms_drivetrain_notify_mode"), modeText))
            RMS_SoundManager.playSample(RMS_Main.samples.notification2D)
        end
        state._lastNotifiedAutoEngaged = state.autoEngaged
    end

    if state._lastNotifiedLock ~= state.diffLockEngaged then
        if state._lastNotifiedLock ~= nil then
            local key = state.diffLockEngaged and "rms_drivetrain_notify_lock_on" or "rms_drivetrain_notify_lock_off"
            g_currentMission.hud:addSideNotification({1, 1, 1, 1}, g_i18n:getText(key))
            RMS_SoundManager.playSample(RMS_Main.samples.notification2D)
        end
        state._lastNotifiedLock = state.diffLockEngaged
    end

    state._parkWarningCooldown = math.max(state._parkWarningCooldown - dt, 0)
    if state._parkWarningCooldown <= 0
            and state.parkKind ~= RMS_Drivetrain.PARK_KIND.AUTOMATIC
            and RMS_Drivetrain.getIsParkBrakeEngaged(vehicle)
            and getThrottle(vehicle) > PARK_THROTTLE_THRESHOLD then
        g_currentMission:showBlinkingWarning(g_i18n:getText("rms_drivetrain_warning_parkbrake"), 2000)
        state._parkWarningCooldown = 4000
    end

    state._windupWarningCooldown = math.max((state._windupWarningCooldown or 0) - dt, 0)
    local C = getConfig()
    local warningThreshold = state.diffLockEngaged and C.WINDUP_WARNING_THRESHOLD or C.WINDUP_4WD_WARNING_THRESHOLD
    if state.windupActive and state.windupStress > warningThreshold and state._windupWarningCooldown <= 0 then
        local warningKey = state.diffLockEngaged and "rms_drivetrain_warning_difflock_windup" or "rms_drivetrain_warning_4wd_windup"
        g_currentMission:showBlinkingWarning(g_i18n:getText(warningKey), 2500)
        state._windupWarningCooldown = 5000
    end
end

---Runs the park brake of a worker and the automatic one
local function updateParkBrakeState(vehicle, state, dt)
    if not RMS_Drivetrain.getIsParkBrakeManaged(vehicle) then
        return
    end

    -- the park brake of the other drivetrain mod stays released while RMS holds this one
    if vehicle.vData ~= nil and vehicle.vData.want ~= nil then
        vehicle.vData.want[13] = false
    end

    local isAIActive = vehicle:getIsAIActive()
    local wasAIActive = state._parkWasAIActive
    state._parkWasAIActive = isAIActive
    if isAIActive then
        if state.parkBrake then
            RMS_Drivetrain.setParkBrake(vehicle, false, false)
        end
        return
    end

    local isControlled = vehicle:getIsControlled()
    if wasAIActive and not isControlled and not state.parkBrake then
        RMS_Drivetrain.setParkBrake(vehicle, true, false)
        return
    end

    if state.parkKind ~= RMS_Drivetrain.PARK_KIND.AUTOMATIC then
        return
    end

    local isMotorStarted = vehicle:getIsMotorStarted()
    local hasDriveDemand = isControlled and isMotorStarted and getHasDriveDemand(vehicle)
    if state.parkBrake then
        if hasDriveDemand then
            RMS_Drivetrain.setParkBrake(vehicle, false, false)
        end
        return
    end

    local isStanding = vehicle:getLastSpeed() < PARK_STANDSTILL_KMH
    if isStanding and not hasDriveDemand then
        state._parkStandstillMs = state._parkStandstillMs + dt
    else
        state._parkStandstillMs = 0
    end

    if isStanding and (not isControlled
            or not isMotorStarted
            or state._parkStandstillMs >= getConfig().PARKBRAKE_AUTO_STANDSTILL_MS) then
        RMS_Drivetrain.setParkBrake(vehicle, true, false)
    end
end

---Samples the wheel speed ratio of each axle differential
local function updateDebugAxleRatios(vehicle, state, dbg)
    local layout = state.layout
    local activeIndices = state._activeDifferentialIndices
    local entries = dbg.axleRatios or {}
    dbg.axleRatios = entries

    if layout == nil or activeIndices == nil then
        for index = #entries, 1, -1 do
            entries[index] = nil
        end
        return
    end

    local lockEngaged = state.diffLockEngaged == true
    local nativeLock = getIsNativeLock(layout, state._activeFourWheelDrive == true)
    local entryCount = 0

    for sourceIdx0 = 0, layout.differentialCount - 1 do
        local original = layout.originals[sourceIdx0]
        if original ~= nil and original.diffIndex1IsWheel and original.diffIndex2IsWheel
                and activeIndices[sourceIdx0] ~= nil then
            entryCount = entryCount + 1
            local entry = entries[entryCount] or {}
            entries[entryCount] = entry

            entry.label = string.format("W%d/W%d", original.diffIndex1, original.diffIndex2)
            entry.cap = getTargetSpeedRatio(original, lockEngaged, nativeLock)

            local wheel1 = vehicle.getWheelFromWheelIndex ~= nil and vehicle:getWheelFromWheelIndex(original.diffIndex1) or nil
            local wheel2 = vehicle.getWheelFromWheelIndex ~= nil and vehicle:getWheelFromWheelIndex(original.diffIndex2) or nil
            local speed1 = math.abs(getWheelAxleSpeed(wheel1))
            local speed2 = math.abs(getWheelAxleSpeed(wheel2))
            local fast, slow = math.max(speed1, speed2), math.min(speed1, speed2)

            entry.ratio = nil
            if fast >= DEBUG_RATIO_MIN_SPEED then
                entry.ratio = math.min(fast / math.max(slow, fast / DEBUG_RATIO_MAX), DEBUG_RATIO_MAX)
            end
        end
    end

    for index = #entries, entryCount + 1, -1 do
        entries[index] = nil
    end
end

---Fills the drivetrain debug data
local function updateDebugData(vehicle, state, spec)
    if not RMS_Utils.getIsDebugDataWanted(vehicle) or spec.debugData == nil or spec.debugData.drivetrain == nil then
        return
    end

    local dbg = spec.debugData.drivetrain
    dbg.hasControl = state.hasControl
    dbg.driveMode = state.driveMode
    dbg.autoEngaged = state.autoEngaged
    dbg.diffLockEngaged = state.diffLockEngaged
    dbg.parkBrake = state.parkBrake
    dbg.parkKind = state.parkKind
    dbg.windupStress = state.windupStress
    dbg.windupWearFactor = state.windupWearFactor

    updateDebugAxleRatios(vehicle, state, dbg)
end

---Runs the differential graph RMS manages: automatic mode, lock and windup
local function updateManagedGraph(vehicle, state, spec, dt)
    if not ensureLayout(vehicle, state) then return end

    if not getConfig().ENABLED then
        if state._graphManaged or state._appliedMode ~= nil or state._appliedLock ~= nil then
            state.autoEngaged = false
            state.diffLockEngaged = false
            if restoreOriginalDifferentialGraph(vehicle, state) then
                state._appliedMode = nil
                state._appliedLock = nil
            end
        end

        local hadWindupState = state.windupActive or state.windupStress ~= 0 or state.windupWearFactor ~= 0
        state._windupDamageLatched = false
        state.windupActive = false
        if hadWindupState then
            state.windupStress = 0
            state.windupWearFactor = 0
            RealisticMechanicalSystems.raiseRMSDirty(vehicle, RealisticMechanicalSystems.SYNC_GROUP.DRIVETRAIN)
        end
        return
    end

    if state.driveMode == RMS_Drivetrain.MODE.AUTO and not getConfig().ALLOW_AUTO_MODE then
        RMS_Drivetrain.setDrivetrainState(vehicle, RMS_Drivetrain.MODE.FOUR_WD, state.diffLockRequested, state.parkBrake, false)
    end

    local isAddedToPhysics = vehicle.isAddedToPhysics == true
    local physicsRestored = isAddedToPhysics and not state._wasAddedToPhysics
    state._wasAddedToPhysics = isAddedToPhysics

    local prevAutoEngaged = state.autoEngaged
    local prevDiffLockEngaged = state.diffLockEngaged
    local prevWindupActive = state.windupActive
    local prevWindupQuantized = math.floor(sanitizeNumber(state.windupStress, 0, 0, 1) * 255 + 0.5)

    updateAutoMode(vehicle, state, spec, dt)
    updateDiffLockState(vehicle, state, dt)
    updateWindupModel(vehicle, state, spec, dt)
    RMS_Drivetrain.applyState(vehicle, physicsRestored)
    applyDifferentialLock(vehicle, state)

    local windupQuantized = math.floor(sanitizeNumber(state.windupStress, 0, 0, 1) * 255 + 0.5)
    local physicalStateChanged = prevAutoEngaged ~= state.autoEngaged
        or prevDiffLockEngaged ~= state.diffLockEngaged
        or prevWindupActive ~= state.windupActive
        or prevWindupQuantized ~= windupQuantized
    if physicalStateChanged then
        RealisticMechanicalSystems.raiseRMSDirty(vehicle, RealisticMechanicalSystems.SYNC_GROUP.DRIVETRAIN)
    end
end

---Runs the drivetrain update: park brake, differential graph, notifications
-- @param table vehicle vehicle
-- @param float dt time since last call in ms
function RMS_Drivetrain.updateDrivetrain(vehicle, dt)
    local spec = vehicle.spec_RealisticMechanicalSystems
    local state = spec ~= nil and spec.drivetrain or nil
    if state == nil then return end

    if vehicle.isServer then
        updateParkBrakeState(vehicle, state, dt)
        updateManagedGraph(vehicle, state, spec, dt)
        updateDebugData(vehicle, state, spec)
    end

    updateLocalNotifications(vehicle, state, dt)
end

---Returns the wear factor the accumulated windup contributes
-- @param table vehicle vehicle
-- @return float factor windup wear factor
function RMS_Drivetrain.getWindupWearFactor(vehicle)
    local state = RMS_Drivetrain.getState(vehicle)
    if state == nil then return 0 end
    return sanitizeNumber(state.windupWearFactor, 0, 0, 100)
end

---Writes the drive mode, the lock request and the park brake
-- @param table vehicle vehicle
-- @param integer streamId streamId
function RMS_Drivetrain.writeStreamState(vehicle, streamId)
    local state = RMS_Drivetrain.getState(vehicle)
    streamWriteBool(streamId, state ~= nil and state.hasControl or false)
    streamWriteBool(streamId, state ~= nil and state.hasCenterDiff or false)
    streamWriteUIntN(streamId, state ~= nil and state.driveMode or RMS_Drivetrain.MODE.FOUR_WD, 2)
    streamWriteBool(streamId, state ~= nil and state.autoEngaged or false)
    streamWriteBool(streamId, state ~= nil and state.diffLockRequested or false)
    streamWriteBool(streamId, state ~= nil and state.diffLockEngaged or false)
    streamWriteBool(streamId, state ~= nil and state.parkBrake or false)
    streamWriteUIntN(streamId, state ~= nil and state.parkKind or RMS_Drivetrain.PARK_KIND.LEVER, 2)
    streamWriteBool(streamId, state ~= nil and state.windupActive or false)
    streamWriteUInt8(streamId, math.floor(sanitizeNumber(state ~= nil and state.windupStress or 0, 0, 0, 1) * 255 + 0.5))
end

---Reads the drive mode, the lock request and the park brake
-- @param table vehicle vehicle
-- @param integer streamId streamId
-- @param boolean? isArrival true for the stream a joining player receives, which plays no park brake sound
function RMS_Drivetrain.readStreamState(vehicle, streamId, isArrival)
    local hasControl = streamReadBool(streamId)
    local hasCenterDiff = streamReadBool(streamId)
    local driveMode = streamReadUIntN(streamId, 2)
    local autoEngaged = streamReadBool(streamId)
    local diffLockRequested = streamReadBool(streamId)
    local diffLockEngaged = streamReadBool(streamId)
    local parkBrake = streamReadBool(streamId)
    local parkKind = streamReadUIntN(streamId, 2)
    local windupActive = streamReadBool(streamId)
    local windupStress = streamReadUInt8(streamId) / 255

    local state = RMS_Drivetrain.getState(vehicle)
    if state == nil then return end
    local parkChanged = state.parkBrake ~= parkBrake
    state.hasControl = hasControl
    state.hasCenterDiff = hasCenterDiff
    state.driveMode = math.clamp(driveMode, 0, 2)
    state.autoEngaged = autoEngaged
    state.diffLockRequested = diffLockRequested
    state.diffLockEngaged = diffLockEngaged
    state.parkBrake = parkBrake
    state.parkKind = parkKind
    state.windupActive = windupActive
    state.windupStress = windupStress

    if parkChanged and not isArrival then
        playParkBrakeSound(vehicle, state)
    end
end

---Writes the drivetrain state to the savegame, the park brake left out
-- @param table vehicle vehicle
-- @param XMLFile xmlFile XMLFile instance
-- @param string key xml key
function RMS_Drivetrain.saveToXMLFile(vehicle, xmlFile, key)
    local state = RMS_Drivetrain.getState(vehicle)
    if state == nil then return end
    xmlFile:setValue(key .. "#driveMode", state.driveMode)
    xmlFile:setValue(key .. "#diffLockRequested", state.diffLockRequested == true)
end

---Reads the drivetrain state from the savegame
-- @param table vehicle vehicle
-- @param XMLFile xmlFile XMLFile instance
-- @param string key xml key
function RMS_Drivetrain.loadFromSavegame(vehicle, xmlFile, key)
    local state = RMS_Drivetrain.getState(vehicle)
    if state == nil then return end
    state.driveMode = math.clamp(math.floor(tonumber(xmlFile:getValue(key .. "#driveMode", state.driveMode)) or state.driveMode), 0, 2)
    state.diffLockRequested = xmlFile:getValue(key .. "#diffLockRequested", state.diffLockRequested) == true
end

---Input action stepping to the next drive mode
-- @param table vehicle vehicle
-- @param string actionName input action name
-- @param float inputValue input value
-- @param any callbackState callback state
-- @param boolean isAnalog true for an analog input
function RMS_Drivetrain.actionToggleDriveMode(vehicle, actionName, inputValue, callbackState, isAnalog)
    if not RMS_Drivetrain.getIsAvailable(vehicle)
            or not RMS_Drivetrain.getHasCenterDifferential(vehicle) then
        return
    end
    RMS_Drivetrain.cycleDriveMode(vehicle)
end

---Input action toggling the differential lock
-- @param table vehicle vehicle
-- @param string actionName input action name
-- @param float inputValue input value
-- @param any callbackState callback state
-- @param boolean isAnalog true for an analog input
function RMS_Drivetrain.actionToggleDiffLock(vehicle, actionName, inputValue, callbackState, isAnalog)
    if not RMS_Drivetrain.getIsAvailable(vehicle) then return end
    RMS_Drivetrain.toggleDiffLock(vehicle)
end

---Input action toggling the park brake
-- @param table vehicle vehicle
-- @param string actionName input action name
-- @param float inputValue input value
-- @param any callbackState callback state
-- @param boolean isAnalog true for an analog input
function RMS_Drivetrain.actionToggleParkBrake(vehicle, actionName, inputValue, callbackState, isAnalog)
    if not RMS_Drivetrain.getIsParkBrakeManaged(vehicle) then return end
    RMS_Drivetrain.toggleParkBrake(vehicle)
end

---Registers the drivetrain input actions
-- @param table vehicle vehicle
-- @param boolean isActiveForInputIgnoreSelection true if active for input
function RMS_Drivetrain.registerActionEvents(vehicle, isActiveForInputIgnoreSelection)
    local spec = vehicle.spec_RealisticMechanicalSystems
    local state = spec ~= nil and spec.drivetrain or nil
    if state == nil then return end

    spec.drivetrainActionEvents = spec.drivetrainActionEvents or {}
    vehicle:clearActionEventsTable(spec.drivetrainActionEvents)

    local isActiveForInputWithAI = vehicle.getIsActiveForInput ~= nil
        and vehicle:getIsActiveForInput(false, true)
    if not isActiveForInputIgnoreSelection and not isActiveForInputWithAI then return end
    if spec.isExcludedVehicle then return end

    if getConfig().ENABLED and state.hasControl then
        if state.hasCenterDiff or not state.layoutAnalyzed then
            local _, modeEventId = vehicle:addActionEvent(spec.drivetrainActionEvents, InputAction.RMS_TOGGLE_4WD, vehicle,
                RMS_Drivetrain.actionToggleDriveMode, false, true, false, true, nil)
            if modeEventId ~= nil then
                g_inputBinding:setActionEventText(modeEventId, g_i18n:getText("input_RMS_TOGGLE_4WD"))
                g_inputBinding:setActionEventTextPriority(modeEventId, GS_PRIO_HIGH)
                g_inputBinding:setActionEventTextVisibility(modeEventId, true)
            end
        end

        local _, lockEventId = vehicle:addActionEvent(spec.drivetrainActionEvents, InputAction.RMS_TOGGLE_DIFFLOCK, vehicle,
            RMS_Drivetrain.actionToggleDiffLock, false, true, false, true, nil)
        if lockEventId ~= nil then
            g_inputBinding:setActionEventText(lockEventId, g_i18n:getText("input_RMS_TOGGLE_DIFFLOCK"))
            g_inputBinding:setActionEventTextPriority(lockEventId, GS_PRIO_HIGH)
            g_inputBinding:setActionEventTextVisibility(lockEventId, true)
        end
    end

    if isActiveForInputIgnoreSelection and RMS_Drivetrain.getIsParkBrakeManaged(vehicle) then
        local _, parkEventId = vehicle:addActionEvent(spec.drivetrainActionEvents, InputAction.RMS_TOGGLE_PARKBRAKE, vehicle,
            RMS_Drivetrain.actionToggleParkBrake, false, true, false, true, nil)
        if parkEventId ~= nil then
            g_inputBinding:setActionEventText(parkEventId, g_i18n:getText("input_RMS_TOGGLE_PARKBRAKE"))
            g_inputBinding:setActionEventTextPriority(parkEventId, GS_PRIO_HIGH)
            g_inputBinding:setActionEventTextVisibility(parkEventId, true)
        end
    end
end

---Tells whether the park brake is engaged
-- @param table vehicle vehicle
-- @return boolean isEngaged true while it holds the vehicle
function RMS_Drivetrain.getIsParkBrakeEngaged(vehicle)
    return RMS_Drivetrain.getIsParkBrakeManaged(vehicle) and RMS_Drivetrain.getState(vehicle).parkBrake
end
