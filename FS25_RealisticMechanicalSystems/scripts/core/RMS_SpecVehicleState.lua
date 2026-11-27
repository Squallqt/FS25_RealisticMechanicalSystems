-- Copyright © 2026 Squallqt. All rights reserved.

---Vehicle state measurements

---Sums the draft force of the implements pulling in the ground
-- @param table vehicle vehicle
local function updateActiveDraftStats(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems

    local result = {
        maxForce = 0,
        effectiveForceCap = 0,
        count = 0
    }
    local visited = {}

    ---Adds the draft of a vehicle and of what it pulls, each once
    -- @param table rootVehicle vehicle
    local function collectDraftStats(rootVehicle)
        if visited[rootVehicle] then
            return
        end

        visited[rootVehicle] = true

        local attachedImplements = rootVehicle.getAttachedImplements ~= nil and rootVehicle:getAttachedImplements() or nil
        if attachedImplements == nil then
            return
        end

        for _, implement in pairs(attachedImplements) do
            local object = implement.object
            if object ~= nil and not visited[object] then
                local powerConsumer = object.spec_powerConsumer
                if powerConsumer ~= nil then
                    local maxForce = powerConsumer.maxForce
                    local multiplier = object:getPowerMultiplier()
                    local speed = math.abs(object.lastSpeedReal)
                    local movingDirection = object.movingDirection
                    local forceDir = powerConsumer.forceDir

                    local isActiveDraft = maxForce > 0
                        and multiplier > 0.001
                        and powerConsumer.forceNode ~= nil
                        and movingDirection == forceDir
                        and speed > 0.0001

                    if isActiveDraft then
                        result.maxForce = result.maxForce + maxForce
                        result.effectiveForceCap = result.effectiveForceCap + maxForce * multiplier
                        result.count = result.count + 1
                    end
                end

                collectDraftStats(object)
            end
        end
    end

    collectDraftStats(vehicle)

    spec.activeDraftMaxForce = result.maxForce 
    spec.activeDraftEffectiveForceCap = result.effectiveForceCap
end

---Stores the load asked of the engine, the harvest load while a harvest loads it, and the engine load at stock power
-- @param table vehicle vehicle
-- @param float dt time of the step (ms)
local function updateDynamicMotorLoad(vehicle, dt)
    local spec = vehicle.spec_RealisticMechanicalSystems
    local motor = vehicle:getMotor()
    local C = RMS_Config.CORE.ENGINE_FACTOR_DATA
    local load = (motor:getMotorAppliedTorque() / math.max(motor:getMotorAvailableTorque(), 0.0001) - C.IDLE_LOAD_SHARE) / (1 - C.IDLE_LOAD_SHARE)
    spec.shownMotorLoad = spec.shownMotorLoad + (load - spec.shownMotorLoad) * (1 - math.exp(-dt * 0.001 / C.SHOWN_LOAD_TAU))
    local harvestLoad = RMS_HarvestLoad.getEngineLoad(vehicle)
    spec.isHarvestLoad = harvestLoad ~= nil
    spec.motorDemand = harvestLoad or spec.shownMotorLoad
    spec.dynamicMotorLoad = RealisticMechanicalSystems.sanitizeNumber(RMS_EngineRemap.getStockLoad(vehicle, RMS_Utils.getMotorLoad(vehicle)),
        0, 0, 1.5)
end

---Stores whether the starter turns the engine
-- @param table vehicle vehicle
local function updateStarterState(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    spec.isCranking = not spec.isElectricVehicle and RMS_Start.getIsCranking(vehicle)
end

---Stores the slip of the driven wheels, a single spike filtered out
-- @param table vehicle vehicle
local function updateWheelSlip(vehicle)
    local spec_wheels = vehicle.spec_wheels
    local spec = vehicle.spec_RealisticMechanicalSystems
    if spec_wheels.brakePedal > RMS_Config.CORE.CHASSIS_FACTOR_DATA.BRAKE_PEDAL_THRESHOLD then
        spec.wheelSlipIntensity = 0
        spec._wheelSlipPreviousSample = 0
        spec._wheelSlipOlderSample = 0
        return
    end

    local drivetrainState = RMS_Drivetrain.getState(vehicle)
    local wheelSpeedSum = 0
    local drivenWheelCount = 0
    ---Adds the ground speed of a driven wheel touching the ground
    -- @param integer wheelIndex wheel
    local function addWheelSpeed(wheelIndex)
        local wheel = spec_wheels.wheels[wheelIndex]
        local physicsWheel = wheel ~= nil and wheel.physics or nil
        if physicsWheel ~= nil and physicsWheel.wheelShapeCreated and physicsWheel.hasGroundContact and physicsWheel.radius > 0 then
            local axleSpeed = getWheelShapeAxleSpeed(wheel.node, physicsWheel.wheelShape)
            wheelSpeedSum = wheelSpeedSum + math.abs(axleSpeed * physicsWheel.radius)
            drivenWheelCount = drivenWheelCount + 1
        end
    end

    local layout = drivetrainState.layout
    if RMS_Drivetrain.getIsAvailable(vehicle) and layout ~= nil then
        for _, wheelIndex in ipairs(layout.primaryWheelIndices) do
            addWheelSpeed(wheelIndex)
        end

        if RMS_Drivetrain.getIsFrontAxleDriven(vehicle) then
            for _, wheelIndex in ipairs(layout.engageableWheelIndices) do
                addWheelSpeed(wheelIndex)
            end
        end
    else
        local differentials = vehicle.spec_motorized.differentials
        if next(differentials) ~= nil then
            local addedWheels = {}
            for _, differential in ipairs(differentials) do
                if differential.diffIndex1IsWheel and not addedWheels[differential.diffIndex1] then
                    addedWheels[differential.diffIndex1] = true
                    addWheelSpeed(differential.diffIndex1)
                end
                if differential.diffIndex2IsWheel and not addedWheels[differential.diffIndex2] then
                    addedWheels[differential.diffIndex2] = true
                    addWheelSpeed(differential.diffIndex2)
                end
            end
        else
            for wheelIndex, wheel in ipairs(spec_wheels.wheels) do
                if wheel.physics.driveMode ~= 0 then
                    addWheelSpeed(wheelIndex)
                end
            end
        end
    end

    if drivenWheelCount == 0 then
        spec.wheelSlipIntensity = 0
        spec._wheelSlipPreviousSample = 0
        spec._wheelSlipOlderSample = 0
        return
    end
    local wheelSpeed = wheelSpeedSum / drivenWheelCount
    local groundSpeed = math.abs(vehicle.lastSpeedReal * 1000)
    local longitudinalSlipIntensity = 0
    if wheelSpeed > 0.0001 then
        longitudinalSlipIntensity = math.clamp((wheelSpeed - groundSpeed) / wheelSpeed, 0, 1)
    end

    -- Reject isolated physics spikes; retain sustained slip
    local previousSlip = spec._wheelSlipPreviousSample
    local olderSlip = spec._wheelSlipOlderSample
    spec._wheelSlipPreviousSample = longitudinalSlipIntensity
    spec._wheelSlipOlderSample = previousSlip
    spec.wheelSlipIntensity = longitudinalSlipIntensity + previousSlip + olderSlip
        - math.min(longitudinalSlipIntensity, previousSlip, olderSlip)
        - math.max(longitudinalSlipIntensity, previousSlip, olderSlip)
end

---Stores the tyre friction and the share of hard ground under the wheels
-- @param table vehicle vehicle
local function updateWheelGroundState(vehicle)
    local spec_wheels = vehicle.spec_wheels
    local spec = vehicle.spec_RealisticMechanicalSystems

    local frictionSum = 0
    local frictionCount = 0
    local surfaceFactorSum = 0
    local groundedWheelCount = 0
    for _, wheel in ipairs(spec_wheels.wheels) do
        local physics = wheel.physics
        if physics.hasGroundContact then
            groundedWheelCount = groundedWheelCount + 1

            local coeff = physics.tireGroundFrictionCoeff
            if coeff > 0 then
                frictionSum = frictionSum + coeff
                frictionCount = frictionCount + 1
            end

            local densityType = physics.densityType or FieldGroundType.NONE
            local groundDepth = math.clamp(physics.groundDepth, 0, 1)
            local groundType = WheelsUtil.getGroundType(
                densityType ~= FieldGroundType.NONE,
                physics.contact ~= WheelContactType.GROUND,
                groundDepth
            )
            if groundType == WheelsUtil.GROUND_ROAD then
                surfaceFactorSum = surfaceFactorSum + 1
            elseif groundType == WheelsUtil.GROUND_HARD_TERRAIN then
                surfaceFactorSum = surfaceFactorSum + (1 - groundDepth)
            end
        end
    end

    spec.avgTireGroundFrictionCoeff = frictionCount > 0 and frictionSum / frictionCount or 0
    spec.avgGroundSurfaceFactor = groundedWheelCount > 0 and surfaceFactorSum / groundedWheelCount or 0
end

local HYDRAULIC_LIFT_RATIO_DEADBAND = 0.05
local LOAD_RISE_DEADBAND = 0.01
local HYDRAULIC_LIFT_RATIO_INTERPOLATION_RATE = 1 / 1000

---Returns the load the wheels of a vehicle carry on the ground
-- @param table vehicle vehicle
-- @return float load load on the wheels
local function getWheelSupportLoad(vehicle)
    local supportWheelLoad = 0

    if vehicle.spec_wheels ~= nil then
        for _, wheel in ipairs(vehicle.spec_wheels.wheels) do
            if wheel.physics.hasGroundContact then
                supportWheelLoad = supportWheelLoad + wheel.physics:getTireLoad()
            end
        end
    end

    return supportWheelLoad
end

---Tells whether a joint type hitches a trailer
-- @param integer jointTypeId AttacherJoints joint type
-- @return boolean isTrailer true for a trailer joint
local function isTrailerJointType(jointTypeId)
    return jointTypeId == AttacherJoints.JOINTTYPE_TRAILER
        or jointTypeId == AttacherJoints.JOINTTYPE_TRAILERLOW
        or jointTypeId == AttacherJoints.JOINTTYPE_TRAILERCAR
        or jointTypeId == AttacherJoints.JOINTTYPE_SEMITRAILERCAR
end

---Tells whether a hitch moves since the last update
-- @param table vehicle vehicle
-- @param any moveKey key of the hitch
-- @param table jointDesc attacher joint
-- @param table nextMoveAlphaCache positions of this update by key
-- @return boolean isMoving true while it moves
local function getMoveState(vehicle, moveKey, jointDesc, nextMoveAlphaCache)
    local spec = vehicle.spec_RealisticMechanicalSystems
    local moveAlpha = jointDesc.moveAlpha or 0
    local prevMoveAlpha = spec.hydraulicsMoveAlphaCache[moveKey]
    nextMoveAlphaCache[moveKey] = moveAlpha

    if prevMoveAlpha ~= nil then
        return math.abs(moveAlpha - prevMoveAlpha) > 0.0001
    end

    local isMovingRaw = jointDesc.isMoving == true
    return isMovingRaw and moveAlpha > 0.001 and moveAlpha < 0.999
end

---Returns whether the cylinders, the joint control and a hammer work
-- @param table vehicle vehicle
-- @return boolean isCylinderedMoving true while a cylinder moves
-- @return boolean isAttacherJointControlMoving true while the joint control moves
-- @return boolean isHydraulicHammerActive true while a hammer works
local function getHydraulicMotionFlags(vehicle)
    local isCylinderedMoving = false
    local isAttacherJointControlMoving = false
    local isHydraulicHammerActive = false

    if vehicle.spec_cylindered ~= nil then
        local cylinderedSpec = vehicle.spec_cylindered
        isCylinderedMoving = RMS_Utils.hasHydraulicActuatorCapability(vehicle)
            and (cylinderedSpec.movingToolNeedsSound == true or cylinderedSpec.movingPartNeedsSound == true)
    end

    if vehicle.spec_attacherJointControl ~= nil then
        isAttacherJointControlMoving = vehicle.spec_attacherJointControl.nextHeightDampingUpdateTime > g_time
    end

    if vehicle.spec_hydraulicHammer ~= nil and vehicle.getIsTurnedOn ~= nil then
        isHydraulicHammerActive = vehicle:getIsTurnedOn()
    end

    return isCylinderedMoving, isAttacherJointControlMoving, isHydraulicHammerActive
end

---Stores the lifted and raising masses and the hydraulic activity of the implements
-- @param table vehicle vehicle
-- @param float dt time of the step (ms)
local function updateImplementChainState(vehicle, dt)
    local spec = vehicle.spec_RealisticMechanicalSystems

    spec.liftedMass = 0
    spec.raisingMass = 0
    spec.isImplementLifted = false
    spec.isImplementLowered = false
    spec.isHydraulicActive = false
    spec.isHydraulicLiftMoving = false
    spec.hydraulicLiftMassByJoint = {}
    spec.hydraulicActiveTargetCount = 0

    local nextMoveAlphaCache = {}
    local nextLiftRatioCache = {}
    local implements = {}
    local liftBranches = {}
    local loads = {}
    local visited = {}
    local maxCutterArea = 0

    ---Notes the load, lift and hydraulics of an implement and of what it carries, each once
    -- @param table vehicleObj implement
    -- @param table? parentObj vehicle it hangs on
    -- @param table? jointDesc attacher joint of the parent
    -- @param integer? jointDescIndex index of the joint
    -- @param boolean isHead true for the vehicle itself
    -- @param table? liftBranch lifted mass the implement adds to, nil to start one
    local function collectImplementState(vehicleObj, parentObj, jointDesc, jointDescIndex, isHead, liftBranch)
        if visited[vehicleObj] then
            return
        end

        visited[vehicleObj] = true
        local supportWheelLoad = getWheelSupportLoad(vehicleObj)
        local isMoving = false
        if isHead then
            if vehicleObj.spec_attacherJoints ~= nil then
                for index, headJointDesc in pairs(vehicleObj.spec_attacherJoints.attacherJoints) do
                    if RMS_Utils.getIsHydraulicLiftJoint(headJointDesc) then
                        isMoving = isMoving or getMoveState(vehicleObj, "__head:" .. tostring(index), headJointDesc, nextMoveAlphaCache)
                    end
                end
            end
        else
            local moveKey = string.format("%s:%s", tostring(vehicleObj), tostring(jointDescIndex))
            if RMS_Utils.getIsHydraulicLiftJoint(jointDesc) then
                isMoving = getMoveState(vehicle, moveKey, jointDesc, nextMoveAlphaCache)
            end
        end

        local isCylinderedMoving, isAttacherJointControlMoving, isHydraulicHammerActive = getHydraulicMotionFlags(vehicleObj)
        local isLowered = false

        if vehicleObj.getIsLowered ~= nil then
            isLowered = vehicleObj:getIsLowered(false)
        elseif jointDesc ~= nil then
            isLowered = jointDesc.moveDown == true
        end

        if vehicleObj.spec_cutter ~= nil and vehicleObj.spec_cutter.workAreaParameters ~= nil then
            maxCutterArea = math.max(maxCutterArea, tonumber(vehicleObj.spec_cutter.workAreaParameters.lastArea) or 0)
        end

        local implementData = {
            mass = vehicleObj:getTotalMass(true),
            jointTypeId = isHead and 0 or jointDesc.jointType,
            isLowered = isLowered,
            isMoving = isMoving,
            isCylinderedMoving = isCylinderedMoving,
            isAttacherJointControlMoving = isAttacherJointControlMoving,
            isHydraulicHammerActive = isHydraulicHammerActive
        }
        table.insert(implements, implementData)

        if not isHead then
            if parentObj == vehicle then
                liftBranch = {
                    root = vehicleObj,
                    mass = 0,
                    supportLoad = 0,
                    jointTypeId = implementData.jointTypeId,
                    jointDesc = jointDesc,
                    isMoving = isMoving,
                    isLowered = isLowered
                }
                table.insert(liftBranches, liftBranch)
            end

            if parentObj == vehicle or not vehicleObj.spec_attachable.isHardAttached then
                liftBranch.mass = liftBranch.mass + implementData.mass
            end
            liftBranch.supportLoad = liftBranch.supportLoad + supportWheelLoad
        end

        if isHead or not isTrailerJointType(liftBranch.jointTypeId) then
            if not isHead then
                loads[#loads + 1] = { node = vehicleObj.rootNode, mass = implementData.mass, branch = liftBranch }
            end
            local mountAttacher = vehicleObj.spec_dynamicMountAttacher
            if mountAttacher ~= nil then
                for object in pairs(mountAttacher.dynamicMountedObjects) do
                    local node = object.nodeId or object.rootNode
                    loads[#loads + 1] = { node = node, mass = getMass(node) }
                end
            end
        end

        local attachedImplements = vehicleObj.getAttachedImplements ~= nil and vehicleObj:getAttachedImplements() or nil
        if attachedImplements ~= nil then
            for _, implementData in pairs(attachedImplements) do
                local childObj = implementData.object
                if childObj ~= nil then
                    local childJointDesc = vehicleObj.spec_attacherJoints.attacherJoints[implementData.jointDescIndex]
                    collectImplementState(childObj, vehicleObj, childJointDesc, implementData.jointDescIndex, false, liftBranch)
                end
            end
        end
    end

    collectImplementState(vehicle, nil, nil, nil, true, nil)
    
    for _, impl in ipairs(implements) do
        if impl.isLowered then
            spec.isImplementLowered = true
        end
        if impl.isMoving or impl.isCylinderedMoving or impl.isAttacherJointControlMoving or impl.isHydraulicHammerActive then
            spec.isHydraulicActive = true
            spec.hydraulicActiveTargetCount = spec.hydraulicActiveTargetCount + 1
        end
        if impl.isMoving then
            spec.isHydraulicLiftMoving = true
        end
    end

    local lockedHookLiftContainer = RMS_Utils.getLockedHookLiftContainer(vehicle)
    for _, branch in ipairs(liftBranches) do
        if not isTrailerJointType(branch.jointTypeId) and branch.root ~= lockedHookLiftContainer then
            local carriedRatio = branch.mass > 0 and math.clamp((branch.mass - branch.supportLoad) / branch.mass, 0, 1) or 0
            local liftRatioState = spec.hydraulicsLiftRatioCache[branch.root] or {
                interpolated = 0,
                applied = 0
            }

            local maxInterpolationStep = dt * HYDRAULIC_LIFT_RATIO_INTERPOLATION_RATE
            local interpolationDelta = math.clamp(
                carriedRatio - liftRatioState.interpolated,
                -maxInterpolationStep,
                maxInterpolationStep
            )
            liftRatioState.interpolated = math.clamp(
                liftRatioState.interpolated + interpolationDelta,
                0,
                1
            )

            if math.abs(liftRatioState.interpolated - liftRatioState.applied) > HYDRAULIC_LIFT_RATIO_DEADBAND then
                liftRatioState.applied = liftRatioState.interpolated
            end

            nextLiftRatioCache[branch.root] = liftRatioState

            if not branch.isLowered then
                local liftedBranchMass = branch.mass * liftRatioState.applied
                spec.liftedMass = spec.liftedMass + liftedBranchMass
                if branch.isMoving then
                    spec.raisingMass = spec.raisingMass + liftedBranchMass
                end
                spec.isImplementLifted = spec.isImplementLifted or liftRatioState.applied > 0
                if branch.jointDesc ~= nil and RMS_Utils.getIsHydraulicLiftJoint(branch.jointDesc) then
                    spec.hydraulicLiftMassByJoint[branch.jointDesc] = liftedBranchMass
                end
            end
        end
    end

    local isOnField = vehicle:getIsOnField()
    local lastSpeed = vehicle:getLastSpeed()
    local isTurnedOn = vehicle.getIsTurnedOn == nil or vehicle:getIsTurnedOn()

    local nextLoadHeightCache = {}
    for _, load in ipairs(loads) do
        local _, height, _ = localToLocal(load.node, vehicle.rootNode, 0, 0, 0)
        local previousHeight = spec.loadHeightCache[load.node]
        nextLoadHeightCache[load.node] = height
        local isWeighedByHitch = load.branch ~= nil and load.branch.isMoving
        if spec.isHydraulicActive and not isWeighedByHitch and previousHeight ~= nil
            and height - previousHeight > LOAD_RISE_DEADBAND then
            spec.raisingMass = spec.raisingMass + load.mass
        end
    end
    spec.loadHeightCache = nextLoadHeightCache

    spec.hydraulicsMoveAlphaCache = nextMoveAlphaCache
    spec.hydraulicsLiftRatioCache = nextLiftRatioCache
    spec.hasDebris = maxCutterArea > 0 and isOnField and lastSpeed >= 0.5 and isTurnedOn
end


---Stores the chassis vibration from the suspension strokes and the speed
-- @param table vehicle vehicle
-- @param float dt time of the step (ms)
local function updateChassisVibState(vehicle, dt)
    local spec = vehicle.spec_RealisticMechanicalSystems

    local vibState = spec.chassisVibState
    local prevSuspension = vibState.prevSuspension

    local speed = vehicle:getLastSpeed()
    local vibRaw = 0
    local vibSpeedFactor = 0

    if speed > 0.003 then
        local sumSuspNorm = 0
        local countSuspNorm = 0

        for wheelIndex, wheel in ipairs(vehicle.spec_wheels.wheels) do
            local suspTravel = wheel.physics.suspTravel
            local suspLength = wheel.physics.netInfo.suspensionLength
            local prevSuspLength = prevSuspension[wheelIndex] or suspLength
            local suspDelta = math.abs(suspLength - prevSuspLength)
            prevSuspension[wheelIndex] = suspLength

            local suspNorm = 0
            if suspTravel > 0.0001 then
                suspNorm = math.min(suspDelta / suspTravel, 3.0)
            end

            if wheel.physics.hasGroundContact then
                sumSuspNorm = sumSuspNorm + suspNorm
                countSuspNorm = countSuspNorm + 1
            end
        end

        vibRaw = countSuspNorm > 0 and (sumSuspNorm / countSuspNorm) or 0
        vibSpeedFactor = math.clamp(speed, 0.0, 50.0) / 50.0
    end

    local vibSignal = vibRaw * vibSpeedFactor
    local alpha = dt / (300 + dt)

    vibState.signal = vibSignal
    vibState.smoothed = vibState.smoothed + (vibSignal - vibState.smoothed) * alpha
end

---Stores the steering angle, its travel rate and the steered axle load
-- @param table vehicle vehicle
-- @param float dt time of the step (ms)
local function updateChassisSteeringState(vehicle, dt)
    local steerState = vehicle.spec_RealisticMechanicalSystems.chassisSteerState
    local C = RMS_Config.CORE.CHASSIS_FACTOR_DATA

    local angle, tireLoad, restLoad, groundContact = 0, 0, 0, 0
    for _, wheel in ipairs(vehicle.spec_wheels.wheels) do
        local physics = wheel.physics
        if RMS_Drivetrain.getIsWheelSteerable(wheel) then
            angle = math.max(angle, math.abs(physics.steeringAngle))
            tireLoad = tireLoad + physics:getTireLoad()
            restLoad = restLoad + physics.restLoad
        end
        if physics.hasGroundContact then
            groundContact = 1
        end
    end

    local articulatedAxis = vehicle.spec_articulatedAxis
    if articulatedAxis ~= nil and articulatedAxis.componentJoint ~= nil then
        angle = math.max(angle, math.abs(articulatedAxis.curRot))
    end

    local lock = vehicle.rotatedTime >= 0 and vehicle.maxRotTime or -vehicle.minRotTime
    local position = lock > 0 and vehicle.rotatedTime / lock or 0
    steerState.travelRate = math.abs(position - steerState.position) / (dt * 0.001)
    steerState.position = position

    local drivable = vehicle.spec_drivable
    steerState.angleMagnitude = angle
    steerState.inputMagnitude = drivable ~= nil and math.abs(drivable.axisSide) or 0
    steerState.groundContact = groundContact
    steerState.axleLoadRatio = restLoad > 0 and math.min(tireLoad / restLoad, C.STEER_LOAD_AXLE_RATIO_MAX) or 1
    steerState.isMoving = steerState.travelRate > C.STEER_LOAD_RATE_DEADZONE
end

---Stores the braking and the power to mass ratios
-- @param table vehicle vehicle
local function updateChassisBrakingState(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems

    local brakeState = spec.chassisBrakeState
    brakeState.pedal = 0
    brakeState.trailerMass = 0
    brakeState.hpTrailerMassRatio = 1000
    brakeState.hpGrossMassRatio = 1000
    brakeState.isBraking = false

    local totalMass = vehicle:getTotalMass()
    local selfMass = vehicle:getTotalMass(true)
    local trailerMass = math.max(totalMass - selfMass, 0)
    local horsepower = math.max(vehicle:getMotor().peakMotorPower * 1.36, 0.001)
    brakeState.trailerMass = trailerMass
    brakeState.hpTrailerMassRatio = horsepower / math.max(trailerMass, 0.01)
    brakeState.hpGrossMassRatio = horsepower / math.max(totalMass, 0.01)

    local drivable = vehicle.spec_drivable
    if drivable == nil then
        return
    end

    -- Exclude park-brake hold from the brake-pedal measurement
    local brakePedalRaw = RMS_Drivetrain.getGameBrakePedal(vehicle)
    local axisForward = drivable.axisForward
    local movingDirection = vehicle.movingDirection
    local directionMode = vehicle.getDirectionChangeMode ~= nil and vehicle:getDirectionChangeMode() or 1
    local isBrakingByAxis = false

    if directionMode == 2 then
        isBrakingByAxis = axisForward < -0.01
    else
        isBrakingByAxis = movingDirection ~= 0 and axisForward ~= 0 and math.sign(movingDirection) ~= math.sign(axisForward)
    end

    local brakePedal = math.clamp(brakePedalRaw, 0, 1)
    local isBraking = isBrakingByAxis or brakePedal > RMS_Config.CORE.CHASSIS_FACTOR_DATA.BRAKE_PEDAL_THRESHOLD

    brakeState.pedal = brakePedal
    brakeState.isBraking = isBraking
end

---Stores the fuel level and use, the idle time and the exhaust deposits
-- @param table vehicle vehicle
-- @param float dt time of the step (ms)
local function updateFuelState(vehicle, dt)
    local spec = vehicle.spec_RealisticMechanicalSystems
    local fuelState = spec.fuelState

    ---Returns the share of the fuel left
    -- @return float level level, 0 to 1
    local function resolveFuelLevel()
        local fuelFillUnit = vehicle:getConsumerFillUnitIndex(FillType.DIESEL)

        if fuelFillUnit == nil then
            for _, consumer in pairs(vehicle.spec_motorized.consumers) do
                local fillType = consumer.fillType
                if fillType == FillType.METHANE or fillType == FillType.ELECTRICCHARGE then
                    fuelFillUnit = consumer.fillUnitIndex
                    break
                end
            end
        end

        if fuelFillUnit ~= nil then
            local fuelLiters = vehicle:getFillUnitFillLevel(fuelFillUnit) or 0
            local fuelCapacity = vehicle:getFillUnitCapacity(fuelFillUnit) or 0
            return fuelCapacity > 0 and (fuelLiters / fuelCapacity) or 0
        end

        return 0
    end

    ---Returns the fuel use against the highest the engine burns
    -- @return float ratio ratio
    local function resolveFuelUsageRatio()
        local motorizedSpec = vehicle.spec_motorized
        local fuelConsumer = motorizedSpec.consumersByFillTypeName["DIESEL"]
            or motorizedSpec.consumersByFillTypeName["METHANE"]
            or motorizedSpec.consumersByFillTypeName["ELECTRICCHARGE"]

        local baseFuelUsageLh = 0
        if fuelConsumer ~= nil then
            if fuelConsumer.permanentConsumption then
                baseFuelUsageLh = fuelConsumer.usage * 60 * 60 * 1000
            else
                baseFuelUsageLh = fuelConsumer.usage
            end
        end

        local currentFuelUsageLh = RealisticMechanicalSystems.sanitizeNumber(motorizedSpec.lastFuelUsage, 0, 0, 10000)

        local fuelUsage = g_currentMission.missionInfo.fuelUsage
        local usageFactor = 1.5
        if fuelUsage == 1 then
            usageFactor = 1.0
        elseif fuelUsage == 3 then
            usageFactor = 2.5
        end

        local damageFactor = 1.0
        if vehicle.getVehicleDamage ~= nil then
            local vehicleDamage = vehicle:getVehicleDamage()
            if vehicleDamage > 0 then
                damageFactor = damageFactor * (1 + vehicleDamage * Motorized.DAMAGED_USAGE_INCREASE)
            end
        end

        local maxFuelUsageLh = baseFuelUsageLh * usageFactor * damageFactor
        if maxFuelUsageLh > 0 then
            return currentFuelUsageLh / maxFuelUsageLh
        end

        return 0
    end

    fuelState.level = resolveFuelLevel()

    if spec.isElectricVehicle then
        fuelState.currentUsageRatio = vehicle:getIsMotorStarted() and resolveFuelUsageRatio() or 0
    elseif vehicle:getIsMotorStarted() then
        fuelState.currentUsageRatio = resolveFuelUsageRatio()

        local environmentTemp = RMS_Utils.getAmbientTemperature()

        fuelState.temperature = math.max(RealisticMechanicalSystems.sanitizeNumber(spec.rawEngineTemperature, environmentTemp, -80, 160) / 3.6, environmentTemp)

        local idleSpeedThreshold = RMS_Config.CORE.FUEL_FACTOR_DATA.IDLE_DEPOSIT_SPEED_THRESHOLD
        local idleLoadThreshold = RMS_Config.CORE.FUEL_FACTOR_DATA.IDLE_DEPOSIT_LOAD_THRESHOLD
        local motorLoad = RMS_Utils.getMotorLoad(vehicle)
        local idleTimer = fuelState.idleTimer
        local isIdle = vehicle:getLastSpeed() <= idleSpeedThreshold and motorLoad <= idleLoadThreshold

        if isIdle then
            idleTimer = math.min(idleTimer + (dt / 1000), RMS_Config.CORE.FUEL_FACTOR_DATA.IDLE_DEPOSIT_FACTOR_MAX_TIMER)
        else
            idleTimer = 0
        end

        fuelState.idleTimer = idleTimer
        fuelState.wetStackingLevel = RMS_Exhaust.calculateWetStackingLevel({
            currentLevel = fuelState.wetStackingLevel,
            idleTimer = idleTimer,
            load = motorLoad,
            dt = dt,
            engineTemperature = spec.rawEngineTemperature,
            isIdle = isIdle,
            isDiesel = spec.isDieselVehicle
        })
        fuelState.particulateFilterAsh, fuelState.particulateFilterOilAsh = RMS_Exhaust.calculateParticulateFilterAsh({
            ash = fuelState.particulateFilterAsh,
            oilAsh = fuelState.particulateFilterOilAsh,
            isStageV = spec.hasParticulateFilter == true,
            suitedShare = spec.engineOilSuitedShare,
            dt = dt
        })
        fuelState.particulateFilterLevel, fuelState.particulateFilterRegenerationMs, fuelState.isParticulateFilterRegenerating =
            RMS_Exhaust.calculateParticulateFilterLoad({
                currentLevel = fuelState.particulateFilterLevel,
                regenerationMs = fuelState.particulateFilterRegenerationMs,
                ash = fuelState.particulateFilterAsh,
                isStageV = spec.hasParticulateFilter == true,
                isBlocked = spec.activeEffects.PARTICULATE_FILTER_BLOCKED ~= nil,
                load = motorLoad,
                coolantTemperature = spec.rawEngineTemperature,
                dt = dt
            })
    else
        fuelState.currentUsageRatio = 0
        fuelState.temperature = 0
        fuelState.idleTimer = 0
        fuelState.particulateFilterRegenerationMs = 0
        fuelState.isParticulateFilterRegenerating = false
    end
end

---Stores the PTO power, its engagements and the shaft angles
-- @param table vehicle vehicle
local function updatePtoState(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    if not spec.systems.pto.enabled then
        spec.isPtoActive = false
        spec.ptoTorque = 0
        spec.ptoRpm = 0
        spec.ptoPower = 0
        spec.ptoUtilization = 0
        spec.ptoShaftAngle, spec.frontPtoShaftAngle = 0, 0
        spec.ptoShaftLimit = RMS_Config.CORE.DIRECT_FAILURES.PTO_SHAFT_ANGLE.limit
        spec.frontPtoShaftLimit = spec.ptoShaftLimit
        spec.ptoShaftWear = 0
        if next(spec.ptoPreviousActiveLinks) ~= nil then
            spec.ptoPreviousActiveLinks = {}
        end
        return
    end

    local ptoData = RMS_Utils.getConnectedPtoData(vehicle)

    spec.isPtoActive = ptoData.isActive
    spec.ptoTorque = math.max(ptoData.torque, 0)
    spec.ptoRpm = math.max(ptoData.rpm, 0)
    spec.ptoPower = math.max(ptoData.power, 0)
    spec.ptoUtilization = RMS_Utils.getPtoNativeCapacityData(vehicle, spec.ptoTorque)

    local previousActiveLinks = spec.ptoPreviousActiveLinks
    local newEngagementCount = RMS_Utils.getPtoEngagementTransitionCount(ptoData.activeLinks, previousActiveLinks)
    if newEngagementCount > 0 then
        spec.ptoEngagementCount = spec.ptoEngagementCount + newEngagementCount
        local rpmShare = vehicle:getIsAIActive() and 0 or spec.ptoLastRpmShare
        local damage, isShock = RMS_Utils.getPtoEngagementDamage(vehicle, ptoData.engagementTorques, previousActiveLinks, rpmShare)
        spec.ptoEngagementDamage = spec.ptoEngagementDamage + damage
        if isShock then
            spec.isPtoEngagementShock = true
        end
    end
    spec.ptoPreviousActiveLinks = ptoData.activeLinks
    local isAIActive = vehicle:getIsAIActive()
    spec.ptoShaftAngle = isAIActive and 0 or ptoData.rearShaft.angle
    spec.ptoShaftLimit = ptoData.rearShaft.limit
    spec.frontPtoShaftAngle = isAIActive and 0 or ptoData.frontShaft.angle
    spec.frontPtoShaftLimit = ptoData.frontShaft.limit
    spec.ptoShaftWear = isAIActive and 0 or ptoData.shaftWear

    local motor = vehicle:getMotor()
    spec.ptoLastRpmShare = math.max(RMS_Utils.getMotorRpmShareAboveIdle(vehicle)
        - (motor:getRequiredMotorRpmRange() - motor.minRpm) / (motor.maxRpm - motor.minRpm), 0)
end

---Returns the speed where the torque curve gives the torque asked, at the lowest the speed where it reaches its peak
-- @param table curve torque curve
-- @param float rpm engine speed (rpm)
-- @param float demand torque asked against the torque at that speed
-- @return float luggedRpm lugged speed (rpm)
local function getLuggedRpm(curve, rpm, demand)
    local upperRpm, upperTorque = rpm, curve:get(rpm)
    local asked = demand * upperTorque
    for index = #curve.keyframes, 1, -1 do
        local keyframe = curve.keyframes[index]
        if keyframe.time < upperRpm then
            if keyframe[1] <= upperTorque then
                return upperRpm
            end
            if keyframe[1] >= asked then
                return upperRpm - (upperRpm - keyframe.time) * (asked - upperTorque) / (keyframe[1] - upperTorque)
            end
            upperRpm, upperTorque = keyframe.time, keyframe[1]
        end
    end
    return upperRpm
end

---Lugs the engine down its torque curve while it is asked more than its full load
-- @param table vehicle vehicle
function RealisticMechanicalSystems.updateEngineLugging(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    spec.rpmDrop = 0
    if vehicle:getIsMotorStarted() and spec.motorDemand > 1 then
        local motor = vehicle:getMotor()
        local rpm = motor:getLastRealMotorRpm()
        spec.rpmDrop = rpm - getLuggedRpm(motor:getTorqueCurve(), rpm, spec.motorDemand)
    end
end

VehicleMotor.getLastModulatedMotorRpm = Utils.overwrittenFunction(VehicleMotor.getLastModulatedMotorRpm, function(self, superFunc)
    local spec = RMS_Breakdowns.getLoadedSpec(self.vehicle)
    return superFunc(self) - (spec ~= nil and spec.rpmDrop or 0)
end)

VehicleMotor.getSmoothLoadPercentage = Utils.overwrittenFunction(VehicleMotor.getSmoothLoadPercentage, function(self, superFunc)
    local spec = RMS_Breakdowns.getLoadedSpec(self.vehicle)
    if spec == nil or not spec.isHarvestLoad then
        return superFunc(self)
    end
    return superFunc(self) - self.smoothedLoadPercentage + RMS_Utils.getMotorLoad(self.vehicle)
end)

---Refreshes the vehicle state on the server, each group on its interval
-- @param float dt time of the step (ms)
function RealisticMechanicalSystems:updateVehicleStateSnapshot(dt)
    local spec = self.spec_RealisticMechanicalSystems
    if not self.isServer or spec.isExcludedVehicle then return end
    updateDynamicMotorLoad(self, dt)

    local delayOne = RMS_Config.UPDATE_VEHICLE_STATE_DELAY_ONE
    local delayTwo = RMS_Config.UPDATE_VEHICLE_STATE_DELAY_TWO
    local delayThree = RMS_Config.UPDATE_VEHICLE_STATE_DELAY_THREE

    spec.updateVehicleStateTimerOne = spec.updateVehicleStateTimerOne + dt
    spec.updateVehicleStateTimerTwo = spec.updateVehicleStateTimerTwo + dt
    spec.updateVehicleStateTimerThree = spec.updateVehicleStateTimerThree + dt

    if spec.updateVehicleStateTimerOne >= delayOne then
        spec.updateVehicleStateTimerOne = spec.updateVehicleStateTimerOne % delayOne
        updatePtoState(self)
    end

    if spec.updateVehicleStateTimerTwo >= delayTwo then
        spec.updateVehicleStateTimerTwo = spec.updateVehicleStateTimerTwo % delayTwo
        updateStarterState(self)
        updateWheelSlip(self)
        updateChassisVibState(self, delayTwo)
        updateChassisSteeringState(self, delayTwo)
        updateChassisBrakingState(self)
    end
    
    if spec.updateVehicleStateTimerThree >= delayThree then
        spec.updateVehicleStateTimerThree = spec.updateVehicleStateTimerThree % delayThree
        updateActiveDraftStats(self)
        updateWheelGroundState(self)
        updateImplementChainState(self, delayThree)
        updateFuelState(self, delayThree)
        RMS_Breakdowns.updateParticulateFilterOverload(self)
        RMS_Breakdowns.updateEngineDerate(self, delayThree)
        spec.isUnderRoof = self:isUnderRoof()
    end
end
