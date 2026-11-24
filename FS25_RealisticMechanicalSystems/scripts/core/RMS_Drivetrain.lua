-- Copyright © 2026 Squallqt. All rights reserved.

---Drivetrain and park brake control
RMS_Drivetrain = {}

RMS_Drivetrain.MODE = {
    TWO_WD  = 0,
    FOUR_WD = 1,
    AUTO    = 2
}

RMS_Drivetrain.MODE_L10N = {
    [0] = "rms_drivetrain_mode_4x2",
    [1] = "rms_drivetrain_mode_4wd",
    [2] = "rms_drivetrain_mode_auto"
}

RMS_Drivetrain.PARK_KIND = {
    LEVER     = 0,
    AUTOMATIC = 1,
    AIR_VALVE = 2
}

local PARK_THROTTLE_THRESHOLD = 0.2
local PARK_STANDSTILL_KMH = 1.0

local LOCKED_MIN_TORQUE_RATIO = 0.1
local LOCKED_MAX_TORQUE_RATIO = 0.9
local LOCKED_TORQUE_GAIN = 2 -- share/s per relative speed gap
local LOCKED_GAP_CAP = 0.25
local LOCKED_MIN_SPEED = 0.1389 -- m/s
local DIRECTION_CHANGE_SPEED = 0.0003 -- m/ms, below which a pedal changes direction
local TRACK_STEER_INPUT_EPSILON = 0.001
local AXLE_RATIO_MIN_SPEED = 0.05
local AXLE_RATIO_MAX = 99
local DIFF_LOCK_RELEASE_KMH = 10

local sanitizeNumber = RealisticMechanicalSystems.sanitizeNumber

---Returns the drivetrain settings
-- @return table config drivetrain settings
local function getConfig()
    return RMS_Config.DRIVETRAIN
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
-- @param table vehicle vehicle
-- @return table? names category names, nil without a store item
local function getStoreCategoryNames(vehicle)
    local storeItem = g_storeManager:getItemByXMLFilename(vehicle.configFileName)
    return storeItem ~= nil and storeItem.categoryNames or nil
end

---Tells whether the vehicle sits in one of the store categories
-- @param table vehicle vehicle
-- @param table categories true by upper case category name
-- @return boolean isInCategories true in one of them
function RMS_Drivetrain.getIsInCategories(vehicle, categories)
    local categoryNames = getStoreCategoryNames(vehicle)
    if categoryNames == nil then
        return false
    end

    for _, categoryName in ipairs(categoryNames) do
        if categories[categoryName] then
            return true
        end
    end

    return false
end

---Tells whether the vehicle sits in one of the excluded road categories
-- @param table vehicle vehicle
-- @return boolean isRoadVehicle true in one of them
function RMS_Drivetrain.getIsRoadVehicleCategory(vehicle)
    return RMS_Drivetrain.getIsInCategories(vehicle, getConfig().EXCLUDED_CATEGORIES)
end

---Tells whether the vehicle sits in one of the machine categories
-- @param table vehicle vehicle
-- @return boolean isMachine true in one of them
function RMS_Drivetrain.getIsMachineCategory(vehicle)
    return RMS_Drivetrain.getIsInCategories(vehicle, getConfig().MACHINE_CATEGORIES)
end

---Returns the harvest organ set of a self-propelled harvester
-- @param table vehicle vehicle
-- @return string? kind organ set, nil for any other vehicle
function RMS_Drivetrain.getHarvestKind(vehicle)
    if vehicle.spec_combine == nil or vehicle.spec_motorized == nil then
        return nil
    end
    for _, categoryName in ipairs(getStoreCategoryNames(vehicle) or {}) do
        local kind = RMS_Config.CORE.HARVEST_FACTOR_DATA.KINDS[categoryName]
        if kind ~= nil then
            return kind
        end
    end
    return nil
end

---Tells whether a wheel steers, on its rotation range or its rotation speed
-- @param table wheel wheel
-- @return boolean isSteerable true when it steers
function RMS_Drivetrain.getIsWheelSteerable(wheel)
    local physics = wheel.physics
    if math.abs(physics.rotMax - physics.rotMin) > 0.01 then
        return true
    end
    return math.abs(physics.rotSpeed) > 0.001
end

---Returns the position of a wheel along the machine
-- @param table wheel wheel
-- @return float z position along the machine
local function getWheelLocalZ(wheel)
    return wheel.physics.positionZ
end

---Returns the axle speed of a wheel, 0 without the wheel or before its shape exists
-- @param table? wheel wheel
-- @return float speed axle speed (rad/s)
local function getWheelAxleSpeed(wheel)
    if wheel == nil or not wheel.physics.wheelShapeCreated then
        return 0
    end
    return getWheelShapeAxleSpeed(wheel.node, wheel.physics.wheelShape)
end

---Collects the wheels a differential drives, through the graph
-- @param table differentials differentials of the vehicle
-- @param integer diffIndex0 differential, counted from 0
-- @param table wheelIndices wheels collected
-- @param table visited differentials already followed
local function collectWheelIndices(differentials, diffIndex0, wheelIndices, visited)
    local runtimeIndex = diffIndex0 + 1
    if runtimeIndex < 1 or visited[runtimeIndex] then return end
    local differential = differentials[runtimeIndex]
    if differential == nil then return end
    visited[runtimeIndex] = true

    if differential.diffIndex1IsWheel then
        wheelIndices[#wheelIndices + 1] = differential.diffIndex1
    else
        collectWheelIndices(differentials, differential.diffIndex1, wheelIndices, visited)
    end
    if differential.diffIndex2IsWheel then
        wheelIndices[#wheelIndices + 1] = differential.diffIndex2
    else
        collectWheelIndices(differentials, differential.diffIndex2, wheelIndices, visited)
    end
end

---Returns the share of steered wheels and the mean position of an axle
-- @param table vehicle vehicle
-- @param table wheelIndices wheels of the axle
-- @return float steeredShare share of steered wheels
-- @return float z mean position along the machine
local function getAxleScore(vehicle, wheelIndices)
    local steerableCount, zSum, count = 0, 0, 0
    for _, wheelIndex in ipairs(wheelIndices) do
        local wheel = vehicle:getWheelFromWheelIndex(wheelIndex)
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

---Tells whether the machine runs on two tracks
-- @param table vehicle vehicle
-- @return boolean isTwinTrack true on two tracks
local function getIsTwinTrack(vehicle)
    local spec_crawlers = vehicle.spec_crawlers
    local crawlers = spec_crawlers ~= nil and spec_crawlers.crawlers or nil
    if crawlers == nil or #crawlers ~= 2 then
        return false
    end

    local wheels = vehicle.spec_wheels.wheels
    if #wheels == 0 then
        return false
    end

    local crawlerTireType = WheelsUtil.getTireType("crawler")
    if crawlerTireType == nil then
        return false
    end

    for _, wheel in ipairs(wheels) do
        if wheel.physics.tireType ~= crawlerTireType then
            return false
        end
    end

    return true
end

---Tells whether the machine steers by its articulated frame
-- @param table vehicle vehicle
-- @return boolean isArticulated true with an articulated frame
local function getIsRigidAllWheelDrive(vehicle)
    local articulatedAxis = vehicle.spec_articulatedAxis
    return articulatedAxis ~= nil and articulatedAxis.componentJoint ~= nil
end

---Returns the center, primary axle and lockable differentials of a vehicle
-- @param table vehicle vehicle
-- @return table? layout layout, nil without a differential RMS can drive
function RMS_Drivetrain.buildLayout(vehicle)
    local differentials = vehicle.spec_motorized.differentials
    if next(differentials) == nil then
        return nil
    end

    local isTwinTrack = getIsTwinTrack(vehicle)
    local isRigidAllWheelDrive = not isTwinTrack and getIsRigidAllWheelDrive(vehicle)
    local layout = {
        differentialCount = #differentials,
        isTwinTrack = isTwinTrack,
        isPermanentAllWheelDrive = false,
        originals = {},
        centerIdx0 = nil,
        primaryIdx0 = nil,
        engageableWheelIndices = {},
        primaryWheelIndices = {},
        lockableIdx0 = {}
    }

    local referencedAsChild = {}
    for _, differential in ipairs(differentials) do
        if not differential.diffIndex1IsWheel then
            referencedAsChild[differential.diffIndex1 + 1] = true
        end
        if not differential.diffIndex2IsWheel then
            referencedAsChild[differential.diffIndex2 + 1] = true
        end
    end

    local rootCount = 0
    local mixedRootIdx0 = nil
    for i, differential in ipairs(differentials) do
        local idx0 = i - 1
        layout.originals[idx0] = {
            torqueRatio = differential.torqueRatio,
            maxSpeedRatio = differential.maxSpeedRatio,
            diffIndex1 = differential.diffIndex1,
            diffIndex1IsWheel = differential.diffIndex1IsWheel,
            diffIndex2 = differential.diffIndex2,
            diffIndex2IsWheel = differential.diffIndex2IsWheel
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

    if isTwinTrack or isRigidAllWheelDrive then
        layout.centerIdx0 = nil
    end

    if rootCount == 1 and mixedRootIdx0 ~= nil and not isTwinTrack then
        layout.isPermanentAllWheelDrive = true
        layout.centerIdx0 = nil
    elseif layout.centerIdx0 ~= nil then
        local center = differentials[layout.centerIdx0 + 1]
        local out1Idx0 = center.diffIndex1
        local out2Idx0 = center.diffIndex2

        local out1Wheels, out2Wheels = {}, {}
        collectWheelIndices(differentials, out1Idx0, out1Wheels, {})
        collectWheelIndices(differentials, out2Idx0, out2Wheels, {})

        local steer1, z1 = getAxleScore(vehicle, out1Wheels)
        local steer2, z2 = getAxleScore(vehicle, out2Wheels)

        local out1IsEngageable
        if steer1 ~= steer2 then
            out1IsEngageable = steer1 > steer2
        else
            out1IsEngageable = z1 > z2 -- Vehicle forward axis is +Z
        end

        if out1IsEngageable then
            layout.primaryIdx0 = out2Idx0
            layout.engageableWheelIndices, layout.primaryWheelIndices = out1Wheels, out2Wheels
        else
            layout.primaryIdx0 = out1Idx0
            layout.engageableWheelIndices, layout.primaryWheelIndices = out2Wheels, out1Wheels
        end

        for i, differential in ipairs(differentials) do
            if differential.diffIndex1IsWheel and differential.diffIndex2IsWheel then
                layout.lockableIdx0[#layout.lockableIdx0 + 1] = i - 1
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
-- @param table vehicle vehicle
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
        _lockedTorqueRatios = {},
        _wasAddedToPhysics = false,
        _autoConditionTimer = 0,
        _lastNotifiedMode = nil,
        _lastNotifiedLock = nil,
        _windupWarningCooldown = 0,
        _parkWarningCooldown = 0,
        _parkStandstillMs = 0,
        _parkWasAIActive = false,
        _parkGamePedal = 1,
        isDriverBraking = false
    }
end

---Returns the drivetrain state of a vehicle
-- @param table vehicle vehicle
-- @return table state drivetrain state
function RMS_Drivetrain.getState(vehicle)
    return vehicle.spec_RealisticMechanicalSystems.drivetrain
end

---Tells whether the drivetrain system runs on this vehicle
-- @param table vehicle vehicle
-- @return boolean isAvailable true when it runs
function RMS_Drivetrain.getIsAvailable(vehicle)
    return RMS_Drivetrain.getState(vehicle).hasControl and getConfig().ENABLED
end

---Tells whether the vehicle carries a center differential
-- @param table vehicle vehicle
-- @return boolean hasCenterDiff true with one
function RMS_Drivetrain.getHasCenterDifferential(vehicle)
    return RMS_Drivetrain.getState(vehicle).hasCenterDiff
end

---Builds the drivetrain layout once the wheels exist
-- @param table vehicle vehicle
-- @param table state drivetrain state
-- @return boolean hasLayout true once a layout exists
local function ensureLayout(vehicle, state)
    if state.layoutAnalyzed then
        return state.layout ~= nil
    end
    if #vehicle.spec_wheels.wheels == 0 then
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
    local isPermanentAllWheelDrive = state.layout ~= nil and state.layout.isPermanentAllWheelDrive
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

---Tells whether electronics run the front axle and diff lock
-- @param table vehicle vehicle
-- @return boolean hasDriveManagement true with electronics
function RMS_Drivetrain.getHasDriveManagement(vehicle)
    local C = getConfig()
    return vehicle.spec_RealisticMechanicalSystems.year >= C.DRIVE_MANAGEMENT_MIN_YEAR
        and RMS_Drivetrain.getIsInCategories(vehicle, C.DRIVE_MANAGEMENT_CATEGORIES)
end

---Tells whether the drive mode selector offers AUTO
-- @param table vehicle vehicle
-- @return boolean hasAutoMode true when it offers AUTO
function RMS_Drivetrain.getHasAutoMode(vehicle)
    return RMS_Drivetrain.getHasCenterDifferential(vehicle) and RMS_Drivetrain.getHasDriveManagement(vehicle)
end

---Keeps whether the driver brakes
-- @param table vehicle vehicle
-- @param float brakePedal brake pedal
-- @param boolean automaticBrake true when the game brakes by itself
-- @param float currentSpeed speed (m/ms)
function RMS_Drivetrain.onVehiclePhysicsUpdate(vehicle, brakePedal, automaticBrake, currentSpeed)
    RMS_Drivetrain.getState(vehicle).isDriverBraking = not automaticBrake and math.abs(brakePedal) > 0
        and math.abs(currentSpeed) > DIRECTION_CHANGE_SPEED
end

---Tells whether the driver brakes the machine
-- @param table vehicle vehicle
-- @return boolean isBraking true while the driver brakes
local function getIsDriverBraking(vehicle)
    return RMS_Drivetrain.getState(vehicle).isDriverBraking
end

---Returns the steering angle of the machine
-- @param table vehicle vehicle
-- @return float angle steering angle (rad)
local function getSteeringAngle(vehicle)
    return vehicle.spec_RealisticMechanicalSystems.chassisSteerState.angleMagnitude
end

---Returns the full steering lock of the machine
-- @param table vehicle vehicle
-- @return float lock steering lock (rad)
local function getSteeringLock(vehicle)
    local lock = 0
    for _, wheel in ipairs(vehicle.spec_wheels.wheels) do
        if RMS_Drivetrain.getIsWheelSteerable(wheel) then
            lock = math.max(lock, math.abs(wheel.physics.rotMax), math.abs(wheel.physics.rotMin))
        end
    end
    local articulatedAxis = vehicle.spec_articulatedAxis
    if articulatedAxis ~= nil and articulatedAxis.componentJoint ~= nil then
        lock = math.max(lock, math.abs(articulatedAxis.rotMax), math.abs(articulatedAxis.rotMin))
    end
    return lock
end

---Returns the steering angle past which a function releases, short of the full lock
-- @param table vehicle vehicle
-- @param float degrees angle set (deg)
-- @return float limit steering angle (rad)
local function getSteeringLimit(vehicle, degrees)
    local limit = math.rad(degrees)
    local lock = getSteeringLock(vehicle) - math.rad(getConfig().STEERING_LOCK_MARGIN)
    return lock > 0 and math.min(limit, lock) or limit
end

---Tells whether the front axle is driven, the faults counted
-- @param table vehicle vehicle
-- @param table state drivetrain state
-- @return boolean isDriven true when driven
local function getEffectiveFourWheelDrive(vehicle, state)
    if state.layout == nil or state.layout.centerIdx0 == nil then
        return true 
    end
    local effects = vehicle.spec_RealisticMechanicalSystems.activeEffects
    if effects.FOUR_WD_STUCK_ENGAGED ~= nil then
        return true
    elseif effects.FOUR_WD_ENGAGE_FAILURE ~= nil then
        return false
    end
    if state.diffLockEngaged and RMS_Drivetrain.getHasDriveManagement(vehicle) then
        return true
    end
    if state.driveMode == RMS_Drivetrain.MODE.FOUR_WD then
        return true
    elseif state.driveMode == RMS_Drivetrain.MODE.AUTO then
        return state.autoEngaged
    end
    return false
end

---Tells whether the front axle is driven
-- @param table vehicle vehicle
-- @return boolean isDriven true when driven
function RMS_Drivetrain.getIsFrontAxleDriven(vehicle)
    return getEffectiveFourWheelDrive(vehicle, RMS_Drivetrain.getState(vehicle))
end

---Tells whether the driver chose the diff lock or the 4WD by hand
-- @param table vehicle vehicle
-- @return boolean isChosen true when chosen by hand
function RMS_Drivetrain.getIsWindupChosen(vehicle)
    local state = RMS_Drivetrain.getState(vehicle)
    local effects = vehicle.spec_RealisticMechanicalSystems.activeEffects
    if state.diffLockEngaged then
        return state.diffLockRequested and effects.DIFF_LOCK_STUCK_ENGAGED == nil
    end
    return state.driveMode == RMS_Drivetrain.MODE.FOUR_WD and effects.FOUR_WD_STUCK_ENGAGED == nil
        and state.layout ~= nil and not state.layout.isPermanentAllWheelDrive
end

---Returns the speed ratio a differential takes, an axle locked or open
-- @param table original differential as the game set it
-- @param boolean lockEngaged true with the diff lock engaged
-- @return float ratio maximum speed ratio
local function getTargetSpeedRatio(original, lockEngaged)
    local C = getConfig()

    if original.diffIndex1IsWheel and original.diffIndex2IsWheel then
        if lockEngaged then
            return C.LOCKED_AXLE_SPEED_RATIO
        end
        return math.max(original.maxSpeedRatio, C.OPEN_AXLE_SPEED_RATIO)
    end

    return original.maxSpeedRatio
end

---Returns the differentials to install, the front axle left out in 2WD
-- @param table vehicle vehicle
-- @param table state drivetrain state
-- @param boolean useFullGraph true to install every differential
-- @return table? plan differentials to install, nil when one cannot be built
-- @return table? sourceToNative installed differential by original one
local function buildDifferentialPlan(vehicle, state, useFullGraph)
    local layout = state.layout
    local lockEngaged = state.diffLockEngaged
    local plan = {}
    local sourceToNative = {}
    local visiting = {}

    ---Adds a differential to the plan after the ones it drives
    -- @param any sourceIdx0 original differential, counted from 0
    -- @return integer? nativeIdx0 installed differential, nil when it cannot be built
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

        ---Returns the wheel shape or the installed differential an output drives
        -- @param any outputIndex wheel or differential
        -- @param boolean outputIsWheel true for a wheel
        -- @return integer? output wheel shape or installed differential, nil when missing
        local function resolveOutput(outputIndex, outputIsWheel)
            if outputIsWheel then
                local wheel = vehicle:getWheelFromWheelIndex(outputIndex)
                local wheelShape = wheel ~= nil and wheel.physics.wheelShape or 0
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
            maxSpeedRatio = getTargetSpeedRatio(original, lockEngaged)
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

---Installs a differential graph on the machine
-- @param table vehicle vehicle
-- @param table state drivetrain state
-- @param boolean useFullGraph true to install every differential
-- @return boolean isInstalled true when installed
local function installDifferentialGraph(vehicle, state, useFullGraph)
    local spec_motorized = vehicle.spec_motorized
    if spec_motorized.motorizedNode == nil or not vehicle.isAddedToPhysics then
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

---Puts the original differential graph back
-- @param table vehicle vehicle
-- @param table state drivetrain state
-- @return boolean isRestored true when restored
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
-- @param boolean force true to install it again
function RMS_Drivetrain.applyState(vehicle, force)
    if not vehicle.isServer then return end

    local state = RMS_Drivetrain.getState(vehicle)
    local spec_motorized = vehicle.spec_motorized
    if not state.hasControl or state.layout == nil or spec_motorized.motorizedNode == nil then
        return
    end
    if not vehicle.isAddedToPhysics then
        return
    end

    local fourWheelDrive = getEffectiveFourWheelDrive(vehicle, state)
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
    if not vehicle.isServer then
        return
    end

    if not state.parkBrake then
        RMS_Drivetrain.setDrivetrainState(vehicle, state.driveMode, state.diffLockRequested, true)
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

---Returns the torque ratio shifted to the slower wheel, a 1.0 speed ratio alone never locking
-- @param float torqueRatio torque ratio
-- @param float speed1 speed of the first wheel (m/s)
-- @param float speed2 speed of the second wheel (m/s)
-- @param float gearRatio gear ratio, below 0 in reverse
-- @param float dt time of the step (ms)
-- @return float torqueRatio torque ratio
local function getLockedTorqueRatio(torqueRatio, speed1, speed2, gearRatio, dt)
    if gearRatio < 0 then
        speed1 = -speed1
        speed2 = -speed2
    end

    local meanSpeed = (speed1 + speed2) * 0.5
    if meanSpeed < LOCKED_MIN_SPEED then
        return torqueRatio
    end

    local gap = math.clamp((speed2 - speed1) / meanSpeed, -LOCKED_GAP_CAP, LOCKED_GAP_CAP)
    torqueRatio = torqueRatio + gap * LOCKED_TORQUE_GAIN * dt / 1000
    return math.clamp(torqueRatio, LOCKED_MIN_TORQUE_RATIO, LOCKED_MAX_TORQUE_RATIO)
end

---Returns the speed at the tread of a wheel
-- @param table vehicle vehicle
-- @param any wheelIndex wheel
-- @return float speed speed (m/s)
local function getWheelPeripheralSpeed(vehicle, wheelIndex)
    local wheel = vehicle:getWheelFromWheelIndex(wheelIndex)
    local physics = wheel ~= nil and wheel.physics or nil
    return physics ~= nil and getWheelAxleSpeed(wheel) * physics.radius or 0
end

---Updates the axle differentials, locked or open
-- @param table vehicle vehicle
-- @param table state drivetrain state
-- @param float dt time of the step (ms)
local function applyDifferentialLock(vehicle, state, dt)
    local spec_motorized = vehicle.spec_motorized
    local activeIndices = state._activeDifferentialIndices
    if spec_motorized.motorizedNode == nil or activeIndices == nil or not vehicle.isAddedToPhysics then
        return
    end

    local lockEngaged = state.diffLockEngaged
    if not lockEngaged and state._appliedLock == false then
        return
    end

    local layout = state.layout
    local gearRatio = spec_motorized.motor.gearRatio
    if lockEngaged and state._appliedLock ~= true then
        state._lockedTorqueRatios = {}
    end

    for sourceIdx0 = 0, layout.differentialCount - 1 do
        local nativeIdx0 = activeIndices[sourceIdx0]
        local original = layout.originals[sourceIdx0]
        if nativeIdx0 ~= nil then
            local torqueRatio = original.torqueRatio
            if lockEngaged and original.diffIndex1IsWheel and original.diffIndex2IsWheel then
                torqueRatio = getLockedTorqueRatio(state._lockedTorqueRatios[sourceIdx0] or torqueRatio,
                    getWheelPeripheralSpeed(vehicle, original.diffIndex1),
                    getWheelPeripheralSpeed(vehicle, original.diffIndex2),
                    gearRatio, dt)
                state._lockedTorqueRatios[sourceIdx0] = torqueRatio
            end

            updateDifferential(spec_motorized.motorizedNode, nativeIdx0, torqueRatio, getTargetSpeedRatio(original, lockEngaged))
        end
    end

    state._appliedLock = lockEngaged
end

---Reapplies the managed graph and brakes after the game rebuilds physics
-- @param table vehicle vehicle
-- @param function superFunc original function
-- @return boolean success true when added to physics
function RMS_Drivetrain.addToPhysics(vehicle, superFunc)
    local success = superFunc(vehicle)
    if not success then
        return false
    end

    local spec = vehicle.spec_RealisticMechanicalSystems
    local state = spec.drivetrain
    state._wasAddedToPhysics = vehicle.isAddedToPhysics
    RMS_Drivetrain.restoreFreeRolling(vehicle)

    if vehicle.isServer
        and not spec.isExcludedVehicle
        and getConfig().ENABLED
        and ensureLayout(vehicle, state)
        and state.hasControl then
        RMS_Drivetrain.applyState(vehicle, true)
        applyDifferentialLock(vehicle, state, 0)
    end

    return true
end

local PARK_SAMPLES = {
    [RMS_Drivetrain.PARK_KIND.LEVER]     = { [true] = "parkBrakeLeverApply", [false] = "parkBrakeLeverRelease" },
    [RMS_Drivetrain.PARK_KIND.AUTOMATIC] = { [true] = "parkBrakeAutoApply",  [false] = "parkBrakeAutoRelease" },
    [RMS_Drivetrain.PARK_KIND.AIR_VALVE] = { [true] = "parkBrakeTruckApply", [false] = "parkBrakeTruckRelease" }
}
local PARK_SWITCH_SAMPLES = { [true] = "parkBrakeSwitchOn", [false] = "parkBrakeSwitchOff" }

---Returns the throttle the driver gives
-- @param table vehicle vehicle
-- @return float throttle throttle, 0 to 1
local function getThrottle(vehicle)
    local spec_drivable = vehicle.spec_drivable
    return spec_drivable ~= nil and math.abs(spec_drivable.axisForward) or 0
end

---Tells whether the driver asks to drive
-- @param table vehicle vehicle
-- @return boolean hasDemand true on the throttle or the cruise control
local function getHasDriveDemand(vehicle)
    if vehicle.spec_drivable == nil then
        return false
    end

    return getThrottle(vehicle) > PARK_THROTTLE_THRESHOLD
        or vehicle:getCruiseControlState() ~= Drivable.CRUISECONTROL_STATE_OFF
end

---Tells whether the vehicle is towed
-- @param table vehicle vehicle
-- @return boolean isTowed true when attached
local function getIsTowed(vehicle)
    return vehicle.getAttacherVehicle ~= nil and vehicle:getAttacherVehicle() ~= nil
end

---Tells whether RMS runs the park brake of this vehicle
-- @param table vehicle vehicle
-- @return boolean isManaged true when RMS runs it
function RMS_Drivetrain.getIsParkBrakeManaged(vehicle)
    return getConfig().PARKBRAKE_ENABLED and not vehicle.spec_RealisticMechanicalSystems.isExcludedVehicle
end

---Returns the brake pedal the park brake holds by its kind
-- @param table state drivetrain state
-- @return float pedal brake pedal, 0 to 1
local function getParkBrakeHold(state)
    if state.parkKind == RMS_Drivetrain.PARK_KIND.AUTOMATIC then
        return 1
    elseif state.parkKind == RMS_Drivetrain.PARK_KIND.AIR_VALVE then
        return getConfig().PARKBRAKE_AIR_HOLD
    end
    return getConfig().PARKBRAKE_LEVER_HOLD
end

---Returns the brake pedal a dragging park brake leaves
-- @param table vehicle vehicle
-- @return float pedal brake pedal, 0 to 1
local function getParkBrakeDragPedal(vehicle)
    return vehicle.spec_RealisticMechanicalSystems.parkBrakeDrag * getParkBrakeHold(RMS_Drivetrain.getState(vehicle))
end

---Returns the drivetrain state while RMS runs its park brake
-- @param table vehicle vehicle
-- @return table? state drivetrain state, nil otherwise
local function getActingParkState(vehicle)
    if not RMS_Drivetrain.getIsParkBrakeManaged(vehicle) or vehicle:getIsAIActive() or getIsTowed(vehicle) then
        return nil
    end

    return RMS_Drivetrain.getState(vehicle)
end

---Tells whether a gearbox holds the machine through its clutch
-- @param table motor motor
-- @return boolean hasClutch true for such a gearbox
local function getHasClutchGearbox(motor)
    return motor.minForwardGearRatio == nil and motor.gearType ~= VehicleMotor.TRANSMISSION_TYPE.POWERSHIFT
end

---Tells whether a gear holds the machine with the engine off
-- @param table vehicle vehicle
-- @return boolean isHeld true when a gear holds it
local function getIsHeldInGear(vehicle)
    return not vehicle:getIsMotorStarted()
        and getHasClutchGearbox(vehicle:getMotor())
        and not vehicle:getIsMotorInNeutral()
end

---Tells whether nothing holds the machine
-- @param table vehicle vehicle
-- @return boolean isRollingFree true when nothing holds it
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
-- @param float brakePedal brake pedal the game asks for
-- @return float pedal brake pedal
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
-- @param function superFunc original function
-- @param float brakePedal brake pedal the game asks for
-- @param any ... further arguments of the game's function
-- @return any ... what the game's function returns
function RMS_Drivetrain.brake(vehicle, superFunc, brakePedal, ...)
    RMS_Drivetrain.getState(vehicle)._parkGamePedal = brakePedal

    return superFunc(vehicle, math.max(RMS_Drivetrain.getParkBrakePedal(vehicle, brakePedal), getParkBrakeDragPedal(vehicle)), ...)
end

---Returns the brake pedal the game asked for, the park brake left out
-- @param table vehicle vehicle
-- @return float pedal brake pedal
function RMS_Drivetrain.getGameBrakePedal(vehicle)
    return RMS_Drivetrain.getState(vehicle)._parkGamePedal
end

---Runs the park brake around the physics step of the game
-- @param table vehicle vehicle
-- @param function superFunc original function
-- @param float axisForward forward axis
-- @param float axisSide side axis
-- @param boolean doHandbrake true to apply the handbrake
-- @param float dt time of the step (ms)
-- @return float acceleration what the game's function returns
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

    local brakePedal = math.max(getConfig().PARKBRAKE_ROLLING_RESISTANCE, getParkBrakeDragPedal(vehicle))
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

---Plays the sound of the park brake by its kind
-- @param table vehicle vehicle
-- @param table state drivetrain state
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
-- @param boolean wasEntered true when the local player sat in it
function RMS_Drivetrain.onDriverLeft(vehicle, wasEntered)
    if not RMS_Drivetrain.getIsParkBrakeManaged(vehicle) or vehicle:getIsAIActive() then
        return
    end

    local state = RMS_Drivetrain.getState(vehicle)
    local isAutomatic = state.parkKind == RMS_Drivetrain.PARK_KIND.AUTOMATIC
    if vehicle.isServer then
        if isAutomatic and not state.parkBrake and vehicle:getLastSpeed() < PARK_STANDSTILL_KMH then
            RMS_Drivetrain.setParkBrake(vehicle, true)
        end
        RMS_Drivetrain.restoreFreeRolling(vehicle)
    end

    if wasEntered and not isAutomatic and not state.parkBrake then
        g_currentMission:showBlinkingWarning(g_i18n:getText("rms_drivetrain_warning_parkbrake_released"), 4000)
    end
end

---Returns the wear the park brake takes from driving against it applied
-- @param table vehicle vehicle
-- @return float factor wear factor
function RMS_Drivetrain.getParkBrakeDragFactor(vehicle)
    if not RMS_Drivetrain.getIsParkBrakeEngaged(vehicle) or vehicle:getLastSpeed() < PARK_STANDSTILL_KMH then
        return 0
    end

    return getConfig().PARKBRAKE_DRAG_WEAR_MULTIPLIER
end

---Sets the drive mode, the lock request and the park brake, and syncs them
-- @param table vehicle vehicle
-- @param integer driveMode one of MODE
-- @param boolean diffLockRequested true to request the diff lock
-- @param boolean parkBrake true to apply it
function RMS_Drivetrain.setDrivetrainState(vehicle, driveMode, diffLockRequested, parkBrake)
    local state = vehicle.spec_RealisticMechanicalSystems.drivetrain
    if state.layout ~= nil and state.layout.isPermanentAllWheelDrive then
        driveMode = RMS_Drivetrain.MODE.FOUR_WD
        diffLockRequested = false
    end

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
        RMS_DrivetrainEvent.sendEvent(vehicle)
    end
end

---Sets the park brake
-- @param table vehicle vehicle
-- @param boolean engaged true to apply it
function RMS_Drivetrain.setParkBrake(vehicle, engaged)
    local state = RMS_Drivetrain.getState(vehicle)
    RMS_Drivetrain.setDrivetrainState(vehicle, state.driveMode, state.diffLockRequested, engaged)
end

---Steps to the next drive mode
-- @param table vehicle vehicle
function RMS_Drivetrain.cycleDriveMode(vehicle)
    local state = RMS_Drivetrain.getState(vehicle)
    if not state.hasCenterDiff then return end

    local nextMode
    if state.driveMode == RMS_Drivetrain.MODE.TWO_WD then
        nextMode = RMS_Drivetrain.MODE.FOUR_WD
    elseif state.driveMode == RMS_Drivetrain.MODE.FOUR_WD then
        nextMode = RMS_Drivetrain.getHasAutoMode(vehicle) and RMS_Drivetrain.MODE.AUTO or RMS_Drivetrain.MODE.TWO_WD
    else
        nextMode = RMS_Drivetrain.MODE.TWO_WD
    end

    RMS_Drivetrain.setDrivetrainState(vehicle, nextMode, state.diffLockRequested, state.parkBrake)
end

---Toggles the differential lock request
-- @param table vehicle vehicle
function RMS_Drivetrain.toggleDiffLock(vehicle)
    local state = RMS_Drivetrain.getState(vehicle)
    if not state.hasControl then return end
    RMS_Drivetrain.setDrivetrainState(vehicle, state.driveMode, not state.diffLockRequested, state.parkBrake)
end

---Toggles the park brake, an automatic one releasing on a running engine only
-- @param table vehicle vehicle
function RMS_Drivetrain.toggleParkBrake(vehicle)
    local state = RMS_Drivetrain.getState(vehicle)
    if state.parkBrake and state.parkKind == RMS_Drivetrain.PARK_KIND.AUTOMATIC and not vehicle:getIsMotorStarted() then
        g_currentMission:showBlinkingWarning(g_i18n:getText("rms_drivetrain_warning_parkbrake_engine_off"), 2500)
        return
    end
    if not state.parkBrake and vehicle.spec_drivable ~= nil then
        vehicle:setCruiseControlState(Drivable.CRUISECONTROL_STATE_OFF)
    end
    RMS_Drivetrain.setParkBrake(vehicle, not state.parkBrake)
end

---Engages or releases the front axle in AUTO
-- @param table vehicle vehicle
-- @param table state drivetrain state
-- @param float dt time of the step (ms)
local function updateAutoMode(vehicle, state, dt)
    if state.driveMode ~= RMS_Drivetrain.MODE.AUTO or not RMS_Drivetrain.getHasAutoMode(vehicle) then return end

    local C = getConfig()
    local speed = vehicle:getLastSpeed()
    local wantsEngage = getIsDriverBraking(vehicle)
        or (speed <= C.AUTO_DISENGAGE_SPEED and getSteeringAngle(vehicle) <= getSteeringLimit(vehicle, C.AUTO_DISENGAGE_STEER_ANGLE))

    if wantsEngage then
        state.autoEngaged = true
        state._autoConditionTimer = 0
    elseif state.autoEngaged then
        state._autoConditionTimer = state._autoConditionTimer + dt
        if state._autoConditionTimer >= C.AUTO_HYSTERESIS_MS then
            state.autoEngaged = false
            state._autoConditionTimer = 0
        end
    end
end

---Tells whether the diff lock may hold
-- @param table vehicle vehicle
-- @return boolean canHold true when it may hold
local function getCanHoldDiffLock(vehicle)
    local C = getConfig()
    local speed = vehicle:getLastSpeed()
    if not RMS_Drivetrain.getHasDriveManagement(vehicle) then
        return speed <= DIFF_LOCK_RELEASE_KMH
    end
    return speed <= C.DIFF_LOCK_RELEASE_SPEED
        and getSteeringAngle(vehicle) <= getSteeringLimit(vehicle, C.DIFF_LOCK_RELEASE_STEER_ANGLE)
        and not getIsDriverBraking(vehicle)
end

---Engages or releases the diff lock
-- @param table vehicle vehicle
-- @param table state drivetrain state
local function updateDiffLockState(vehicle, state)
    local effects = vehicle.spec_RealisticMechanicalSystems.activeEffects
    if effects.DIFF_LOCK_STUCK_ENGAGED ~= nil or effects.DIFF_LOCK_ENGAGE_FAILURE ~= nil then
        state.diffLockEngaged = effects.DIFF_LOCK_STUCK_ENGAGED ~= nil
        return
    end

    if state.diffLockRequested then
        local canHold = getCanHoldDiffLock(vehicle)
        if state.diffLockEngaged then
            if not canHold then
                state.diffLockEngaged = false
                RMS_Drivetrain.setDrivetrainState(vehicle, state.driveMode, false, state.parkBrake)
            end
        elseif canHold then
            state.diffLockEngaged = true
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

---Builds and releases the windup of a locked driveline
-- @param table vehicle vehicle
-- @param table state drivetrain state
-- @param table spec RMS specialization of the vehicle
-- @param float dt time of the step (ms)
local function updateWindupModel(vehicle, state, spec, dt)
    local C = getConfig()
    local fourWheelDrive = state.layout ~= nil and state.layout.centerIdx0 ~= nil and getEffectiveFourWheelDrive(vehicle, state)
        and (state.driveMode ~= RMS_Drivetrain.MODE.AUTO or spec.activeEffects.FOUR_WD_STUCK_ENGAGED ~= nil)
    local windupFactor = 0

    if state.diffLockEngaged then
        windupFactor = 1.0
    elseif fourWheelDrive then
        windupFactor = C.WINDUP_4WD_FACTOR
    end

    if not state.diffLockEngaged then
        state._windupDamageLatched = false
    end

    if windupFactor <= 0 or vehicle:getIsAIActive() then
        state.windupActive = false
        state.windupStress = math.max(state.windupStress - (dt / 1000) * C.WINDUP_RELEASE_RATE, 0)
        state.windupWearFactor = 0
        return
    end

    local speed = vehicle:getLastSpeed()
    local friction = sanitizeNumber(spec.avgTireGroundFrictionCoeff, 0, 0, 3)
    local steerState = spec.chassisSteerState
    local steering = steerState.angleMagnitude
    local trackSteeringInput = sanitizeNumber(steerState.inputMagnitude, 0, 0, 1)
    local isTwinTrack = state.layout ~= nil and state.layout.isTwinTrack
    local isSteering = (isTwinTrack and trackSteeringInput > TRACK_STEER_INPUT_EPSILON)
        or steering > C.WINDUP_STEER_THRESHOLD
    local surfaceFactor = state.diffLockEngaged and 1 or sanitizeNumber(spec.avgGroundSurfaceFactor, 0, 0, 1)

    local isWindingUp = speed > 1.0
        and isSteering
        and surfaceFactor > 0
        and friction >= C.WINDUP_FRICTION_THRESHOLD

    state.windupActive = isWindingUp

    if isWindingUp then
        local stressLimit = state.diffLockEngaged and 1.0 or C.WINDUP_4WD_MAX_STRESS
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
        if spec.systems.transmission.enabled then
            vehicle:applyInstantDamageToSystem(RealisticMechanicalSystems.SYSTEMS.TRANSMISSION, C.WINDUP_INSTANT_DAMAGE, nil,
                RMS_Drivetrain.getIsWindupChosen(vehicle) and "windup" or nil)
            state._windupDamageLatched = true
            state.windupStress = 0.5
            RealisticMechanicalSystems.raiseRMSDirty(vehicle, RealisticMechanicalSystems.SYNC_GROUP.WEAR)
        end
    end

    if state.windupStress > 0 and isWindingUp then
        state.windupWearFactor = (1 + state.windupStress) ^ C.WINDUP_GEAR_EXPONENT - 1
    else
        state.windupWearFactor = 0
    end

end

---Notifies the driver of the mode, lock, park brake and windup
-- @param table vehicle vehicle
-- @param table state drivetrain state
-- @param float dt time of the step (ms)
local function updateLocalNotifications(vehicle, state, dt)
    if g_dedicatedServerInfo ~= nil then return end
    local isControlled = vehicle:getIsActiveForInput(true)
        and not vehicle:getIsAIActive()
    if not isControlled then
        state._lastNotifiedMode = state.driveMode
        state._lastNotifiedLock = state.diffLockEngaged
        return
    end

    if state._lastNotifiedMode ~= state.driveMode then
        if state._lastNotifiedMode ~= nil then
            local modeText = g_i18n:getText(RMS_Drivetrain.MODE_L10N[state.driveMode])
            g_currentMission.hud:addSideNotification({1, 1, 1, 1}, string.format(g_i18n:getText("rms_drivetrain_notify_mode"), modeText))
        end
        state._lastNotifiedMode = state.driveMode
    end

    if state._lastNotifiedLock ~= state.diffLockEngaged then
        if state._lastNotifiedLock ~= nil then
            local key = state.diffLockEngaged and "rms_drivetrain_notify_lock_on" or "rms_drivetrain_notify_lock_off"
            g_currentMission.hud:addSideNotification({1, 1, 1, 1}, g_i18n:getText(key))
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

    state._windupWarningCooldown = math.max(state._windupWarningCooldown - dt, 0)
    local C = getConfig()
    local warningThreshold = state.diffLockEngaged and C.WINDUP_WARNING_THRESHOLD or C.WINDUP_4WD_WARNING_THRESHOLD
    if state.windupActive and state.windupStress > warningThreshold and state._windupWarningCooldown <= 0 then
        local warningKey = state.diffLockEngaged and "rms_drivetrain_warning_difflock_windup" or "rms_drivetrain_warning_4wd_windup"
        g_currentMission:showBlinkingWarning(g_i18n:getText(warningKey), 2500)
        state._windupWarningCooldown = 5000
    end
end

---Applies or releases the park brake by its kind and the driver
-- @param table vehicle vehicle
-- @param table state drivetrain state
-- @param float dt time of the step (ms)
local function updateParkBrakeState(vehicle, state, dt)
    if not RMS_Drivetrain.getIsParkBrakeManaged(vehicle) then
        return
    end

    -- keeps the park brake of the other drivetrain mod released
    if vehicle.vData ~= nil and vehicle.vData.want ~= nil then
        vehicle.vData.want[13] = false
    end

    local isAIActive = vehicle:getIsAIActive()
    local wasAIActive = state._parkWasAIActive
    state._parkWasAIActive = isAIActive
    if isAIActive then
        if state.parkBrake then
            RMS_Drivetrain.setParkBrake(vehicle, false)
        end
        return
    end

    local isControlled = vehicle:getIsControlled()
    if wasAIActive and not isControlled and not state.parkBrake then
        RMS_Drivetrain.setParkBrake(vehicle, true)
        return
    end

    if state.parkKind ~= RMS_Drivetrain.PARK_KIND.AUTOMATIC then
        return
    end

    local isMotorStarted = vehicle:getIsMotorStarted()
    local hasDriveDemand = isControlled and isMotorStarted and getHasDriveDemand(vehicle)
    if state.parkBrake then
        if hasDriveDemand then
            RMS_Drivetrain.setParkBrake(vehicle, false)
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
        RMS_Drivetrain.setParkBrake(vehicle, true)
    end
end

---Returns the speed ratio and cap of each driven axle
-- @param table vehicle vehicle
-- @return table ratios list of {label, ratio, cap}, ratio nil while the axle barely turns
function RMS_Drivetrain.getAxleRatios(vehicle)
    local state = vehicle.spec_RealisticMechanicalSystems.drivetrain
    local layout = state.layout
    local activeIndices = state._activeDifferentialIndices
    local entries = {}
    if layout == nil or activeIndices == nil then
        return entries
    end

    local lockEngaged = state.diffLockEngaged
    for sourceIdx0 = 0, layout.differentialCount - 1 do
        local original = layout.originals[sourceIdx0]
        if original.diffIndex1IsWheel and original.diffIndex2IsWheel and activeIndices[sourceIdx0] ~= nil then
            local wheel1 = vehicle:getWheelFromWheelIndex(original.diffIndex1)
            local wheel2 = vehicle:getWheelFromWheelIndex(original.diffIndex2)
            local speed1 = math.abs(getWheelAxleSpeed(wheel1))
            local speed2 = math.abs(getWheelAxleSpeed(wheel2))
            local fast, slow = math.max(speed1, speed2), math.min(speed1, speed2)
            table.insert(entries, {
                label = string.format("wheels %d and %d", original.diffIndex1, original.diffIndex2),
                ratio = fast >= AXLE_RATIO_MIN_SPEED and math.min(fast / math.max(slow, fast / AXLE_RATIO_MAX), AXLE_RATIO_MAX) or nil,
                cap = getTargetSpeedRatio(original, lockEngaged)
            })
        end
    end
    return entries
end

---Runs the drive modes, the lock and the windup on the managed graph
-- @param table vehicle vehicle
-- @param table state drivetrain state
-- @param table spec RMS specialization of the vehicle
-- @param float dt time of the step (ms)
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

    local isAddedToPhysics = vehicle.isAddedToPhysics
    local physicsRestored = isAddedToPhysics and not state._wasAddedToPhysics
    state._wasAddedToPhysics = isAddedToPhysics

    local prevAutoEngaged = state.autoEngaged
    local prevDiffLockEngaged = state.diffLockEngaged
    local prevWindupActive = state.windupActive
    local prevWindupQuantized = math.floor(state.windupStress * 255 + 0.5)

    updateAutoMode(vehicle, state, dt)
    updateDiffLockState(vehicle, state)
    updateWindupModel(vehicle, state, spec, dt)
    RMS_Drivetrain.applyState(vehicle, physicsRestored)
    applyDifferentialLock(vehicle, state, dt)

    local windupQuantized = math.floor(state.windupStress * 255 + 0.5)
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
-- @param float dt time of the step (ms)
function RMS_Drivetrain.updateDrivetrain(vehicle, dt)
    local spec = vehicle.spec_RealisticMechanicalSystems
    local state = spec.drivetrain

    if vehicle.isServer then
        updateParkBrakeState(vehicle, state, dt)
        updateManagedGraph(vehicle, state, spec, dt)
    end

    updateLocalNotifications(vehicle, state, dt)
end

---Returns the wear factor the accumulated windup contributes
-- @param table vehicle vehicle
-- @return float factor wear factor
function RMS_Drivetrain.getWindupWearFactor(vehicle)
    return RMS_Drivetrain.getState(vehicle).windupWearFactor
end

---Writes the drivetrain state
-- @param table vehicle vehicle
-- @param integer streamId stream ID
function RMS_Drivetrain.writeStreamState(vehicle, streamId)
    local state = RMS_Drivetrain.getState(vehicle)
    streamWriteBool(streamId, state.hasControl)
    streamWriteBool(streamId, state.hasCenterDiff)
    streamWriteUIntN(streamId, state.driveMode, 2)
    streamWriteBool(streamId, state.autoEngaged)
    streamWriteBool(streamId, state.diffLockRequested)
    streamWriteBool(streamId, state.diffLockEngaged)
    streamWriteBool(streamId, state.parkBrake)
    streamWriteUIntN(streamId, state.parkKind, 2)
    streamWriteBool(streamId, state.windupActive)
    streamWriteUInt8(streamId, math.floor(state.windupStress * 255 + 0.5))
end

---Reads the drivetrain state
-- @param table vehicle vehicle
-- @param integer streamId stream ID
-- @param boolean? isArrival true on joining, playing no sound
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
    local parkChanged = state.parkBrake ~= parkBrake
    state.hasControl = hasControl
    state.hasCenterDiff = hasCenterDiff
    state.driveMode = driveMode
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

---Writes the drive mode and the lock request to the savegame
-- @param table vehicle vehicle
-- @param table xmlFile savegame file
-- @param string key key of the drivetrain
function RMS_Drivetrain.saveToXMLFile(vehicle, xmlFile, key)
    local state = RMS_Drivetrain.getState(vehicle)
    xmlFile:setValue(key .. "#driveMode", state.driveMode)
    xmlFile:setValue(key .. "#diffLockRequested", state.diffLockRequested)
end

---Reads the drive mode and the lock request from the savegame
-- @param table vehicle vehicle
-- @param table xmlFile savegame file
-- @param string key key of the drivetrain
function RMS_Drivetrain.loadFromSavegame(vehicle, xmlFile, key)
    local state = RMS_Drivetrain.getState(vehicle)
    state.driveMode = math.clamp(xmlFile:getValue(key .. "#driveMode", state.driveMode), 0, 2)
    state.diffLockRequested = xmlFile:getValue(key .. "#diffLockRequested", state.diffLockRequested)
end

---Input action stepping to the next drive mode
-- @param table vehicle vehicle
-- @param string actionName input action
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
-- @param string actionName input action
-- @param float inputValue input value
-- @param any callbackState callback state
-- @param boolean isAnalog true for an analog input
function RMS_Drivetrain.actionToggleDiffLock(vehicle, actionName, inputValue, callbackState, isAnalog)
    if not RMS_Drivetrain.getIsAvailable(vehicle) then return end
    RMS_Drivetrain.toggleDiffLock(vehicle)
end

---Input action toggling the park brake
-- @param table vehicle vehicle
-- @param string actionName input action
-- @param float inputValue input value
-- @param any callbackState callback state
-- @param boolean isAnalog true for an analog input
function RMS_Drivetrain.actionToggleParkBrake(vehicle, actionName, inputValue, callbackState, isAnalog)
    if not RMS_Drivetrain.getIsParkBrakeManaged(vehicle) then return end
    RMS_Drivetrain.toggleParkBrake(vehicle)
end

---Registers the drivetrain input actions
-- @param table vehicle vehicle
-- @param boolean isActiveForInputIgnoreSelection true when the vehicle takes input, selected or not
function RMS_Drivetrain.registerActionEvents(vehicle, isActiveForInputIgnoreSelection)
    local spec = vehicle.spec_RealisticMechanicalSystems
    local state = spec.drivetrain
    vehicle:clearActionEventsTable(spec.drivetrainActionEvents)

    local isActiveForInputWithAI = vehicle:getIsActiveForInput(false, true)
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
-- @return boolean isEngaged true when engaged
function RMS_Drivetrain.getIsParkBrakeEngaged(vehicle)
    return RMS_Drivetrain.getIsParkBrakeManaged(vehicle) and RMS_Drivetrain.getState(vehicle).parkBrake
end
