-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---Live vehicle state snapshot feeding the wear, thermal and breakdown models

---Sums the draft demand of the working implements
local function updateActiveDraftStats(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    if spec == nil then
        return 0, 0
    end

    local result = {
        maxForce = 0,
        effectiveForceCap = 0,
        count = 0
    }
    local visited = {}

    ---Walks the implement chain summing the working draft demand
    local function collectDraftStats(rootVehicle)
        if rootVehicle == nil or visited[rootVehicle] then
            return
        end

        visited[rootVehicle] = true

        local attachedImplements = rootVehicle.getAttachedImplements ~= nil and rootVehicle:getAttachedImplements() or nil
        if attachedImplements == nil then
            return
        end

        for _, implement in pairs(attachedImplements) do
            local object = implement ~= nil and implement.object or nil
            if object ~= nil and not visited[object] then
                local powerConsumer = object.spec_powerConsumer
                if powerConsumer ~= nil then
                    local maxForce = tonumber(powerConsumer.maxForce) or 0
                    local multiplier = object.getPowerMultiplier ~= nil and (tonumber(object:getPowerMultiplier()) or 0) or 1
                    local speed = math.abs(tonumber(object.lastSpeedReal) or 0)
                    local movingDirection = tonumber(object.movingDirection) or 0
                    local forceDir = tonumber(powerConsumer.forceDir) or 0

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

---Raises the motor load with driveline vibration during field work
local function updateDynamicMotorLoad(vehicle, dt)
    local spec = vehicle.spec_RealisticMechanicalSystems
    if spec == nil then
        return 0
    end

    local motorLoad = RealisticMechanicalSystems.sanitizeNumber(vehicle:getMotorLoadPercentage(), 0, 0, 1.5)
    local hasMoreRealistic = g_modIsLoaded["MoreRealistic"] == true

    if hasMoreRealistic then
        spec.dynamicMotorLoad = motorLoad
        return
    end

    local dynamicMotorLoad = motorLoad

    if vehicle:getIsOnField() then
        local isWorking = false
        if vehicle.spec_attacherJoints and vehicle.spec_attacherJoints.attachedImplements and next(vehicle.spec_attacherJoints.attachedImplements) ~= nil then
            for _, implementData in pairs(vehicle.spec_attacherJoints.attachedImplements) do
                if implementData.object ~= nil then
                    local implement = implementData.object
                    if implement:getIsLowered() then
                        isWorking = true
                    end
                end
            end
        end

        if isWorking then
            local motor = vehicle:getMotor()
            local peakPowerHp = RealisticMechanicalSystems.sanitizeNumber((motor.peakMotorPower or 0) * 1.36, 0, 0)
            local avgAbsDiffAcc = RealisticMechanicalSystems.sanitizeNumber(spec.avgAbsDiffAcc, 0, 0, 100)
            if peakPowerHp > 0.001 then
                local activeDraftEffectiveForceCap = RealisticMechanicalSystems.sanitizeNumber(spec.activeDraftEffectiveForceCap, 0, 0, 1000000)
                dynamicMotorLoad = math.min(motorLoad + math.min(avgAbsDiffAcc / 3, 0.15) * ((activeDraftEffectiveForceCap / peakPowerHp) / 0.15) ^ 2, 1.15)
            end
        end
    end

    spec.dynamicMotorLoad = RealisticMechanicalSystems.sanitizeNumber(dynamicMotorLoad, motorLoad, 0, 1.5)

end

---Keeps the rolling average of the motor's differential acceleration
local function updateAvgAbsDiffAccWindow(spec, motor, dt)
    if spec == nil or motor == nil then
        if spec ~= nil then
            spec.avgAbsDiffAcc = 0
        end
        return 0
    end

    local windowDurationMs = 500
    local diffAcc = math.abs(tonumber(motor.differentialRotAccelerationSmoothed) or 0)

    if spec._avgAbsDiffAccSamples == nil then
        spec._avgAbsDiffAccSamples = {}
    end

    local samples = spec._avgAbsDiffAccSamples

    for i = #samples, 1, -1 do
        local sample = samples[i]
        sample.ageMs = (tonumber(sample.ageMs) or 0) + (tonumber(dt) or 0)

        if sample.ageMs > windowDurationMs then
            table.remove(samples, i)
        end
    end

    table.insert(samples, {
        ageMs = 0,
        value = diffAcc
    })

    if #samples == 0 then
        spec.avgAbsDiffAcc = 0
        return 0
    end

    local sum = 0
    for i = 1, #samples do
        sum = sum + (tonumber(samples[i].value) or 0)
    end

    local avg = sum / #samples
    spec.avgAbsDiffAcc = avg
end

---Flags the vehicle as cranking
local function updateStarterState(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    if spec == nil then
        return false
    end

    -- an electric machine has no starter to crank
    if spec.isElectricVehicle then
        spec.isCranking = false
        return
    end

    local engineHardStartEffect = spec.activeEffects ~= nil and spec.activeEffects.ENGINE_HARD_START_MODIFIER or nil
    local glowPlugHardStartEffect = spec.activeEffects ~= nil and spec.activeEffects.GLOW_PLUG_HARD_START_MODIFIER or nil
    local engineFailedEffect = spec.activeEffects ~= nil and spec.activeEffects.ENGINE_FAILURE or nil

    local isCranking = vehicle:getMotorState() == MotorState.STARTING
        or (engineHardStartEffect ~= nil
            and engineHardStartEffect.extraData ~= nil
            and engineHardStartEffect.extraData.status ~= nil
            and (engineHardStartEffect.extraData.status == "CRANKING"
                or engineHardStartEffect.extraData.status == "PASSED"))
        or (glowPlugHardStartEffect ~= nil
            and glowPlugHardStartEffect.extraData ~= nil
            and glowPlugHardStartEffect.extraData.status ~= nil
            and (glowPlugHardStartEffect.extraData.status == "CRANKING"
                or glowPlugHardStartEffect.extraData.status == "PASSED"))
        or (engineFailedEffect ~= nil
            and engineFailedEffect.extraData ~= nil
            and engineFailedEffect.extraData.status ~= nil
            and engineFailedEffect.extraData.status == "CRANKING")

    spec.isCranking = isCranking
end

---Measures wheel slip from the driven wheel speeds, ignored while braking
local function updateWheelSlip(vehicle)
    local spec_wheels = vehicle.spec_wheels
    local spec = vehicle.spec_RealisticMechanicalSystems
    if spec == nil then
        return
    end
    if spec_wheels == nil or spec_wheels.wheels == nil then
        spec.wheelSlipIntensity = 0
        spec._wheelSlipPreviousSample = 0
        spec._wheelSlipOlderSample = 0
        return
    end

    local brakeThreshold = tonumber(RMS_Config.CORE.CHASSIS_FACTOR_DATA.BRAKE_PEDAL_THRESHOLD) or 0.15
    if (tonumber(spec_wheels.brakePedal) or 0) > brakeThreshold then
        spec.wheelSlipIntensity = 0
        spec._wheelSlipPreviousSample = 0
        spec._wheelSlipOlderSample = 0
        return
    end

    local drivetrainState = RMS_Drivetrain.getState(vehicle)
    local wheelSpeedSum = 0
    local drivenWheelCount = 0
    ---Adds the ground speed of a grounded wheel to the sum
    local function addWheelSpeed(wheelIndex)
        local wheel = spec_wheels.wheels[tonumber(wheelIndex)]
        local physicsWheel = wheel ~= nil and wheel.physics or nil
        if physicsWheel ~= nil and physicsWheel.wheelShapeCreated and physicsWheel.hasGroundContact then
            local radius = tonumber(physicsWheel.radius) or 0
            if radius > 0 then
                local axleSpeed = getWheelShapeAxleSpeed(wheel.node, physicsWheel.wheelShape)
                wheelSpeedSum = wheelSpeedSum + math.abs((tonumber(axleSpeed) or 0) * radius)
                drivenWheelCount = drivenWheelCount + 1
            end
        end
    end

    local layout = drivetrainState ~= nil and drivetrainState.layout or nil
    if RMS_Drivetrain.getIsAvailable(vehicle) and layout ~= nil then
        for _, wheelIndex in ipairs(layout.primaryWheelIndices) do
            addWheelSpeed(wheelIndex)
        end

        local fourWheelDrive = layout.centerIdx0 == nil
            or drivetrainState.driveMode == RMS_Drivetrain.MODE.FOUR_WD
            or (drivetrainState.driveMode == RMS_Drivetrain.MODE.AUTO and drivetrainState.autoEngaged)
        if fourWheelDrive then
            for _, wheelIndex in ipairs(layout.engageableWheelIndices) do
                addWheelSpeed(wheelIndex)
            end
        end
    else
        local differentials = vehicle.spec_motorized ~= nil and vehicle.spec_motorized.differentials or nil
        if differentials ~= nil and next(differentials) ~= nil then
            local addedWheels = {}
            for _, differential in ipairs(differentials) do
                if differential.diffIndex1IsWheel then
                    local wheelIndex = tonumber(differential.diffIndex1)
                    if wheelIndex ~= nil and not addedWheels[wheelIndex] then
                        addedWheels[wheelIndex] = true
                        addWheelSpeed(wheelIndex)
                    end
                end
                if differential.diffIndex2IsWheel then
                    local wheelIndex = tonumber(differential.diffIndex2)
                    if wheelIndex ~= nil and not addedWheels[wheelIndex] then
                        addedWheels[wheelIndex] = true
                        addWheelSpeed(wheelIndex)
                    end
                end
            end
        else
            for wheelIndex, wheel in ipairs(spec_wheels.wheels) do
                local physicsWheel = wheel.physics
                if physicsWheel ~= nil and (tonumber(physicsWheel.driveMode) or 0) ~= 0 then
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
    local groundSpeed = math.abs((tonumber(vehicle.lastSpeedReal) or 0) * 1000)
    local longitudinalSlipIntensity = 0
    -- slip compares the wheel speed with the ground speed
    if wheelSpeed > 0.0001 then
        longitudinalSlipIntensity = math.clamp((wheelSpeed - groundSpeed) / wheelSpeed, 0, 1)
    end

    -- isolated physics spikes are rejected, sustained slip kept
    local previousSlip = spec._wheelSlipPreviousSample
    local olderSlip = spec._wheelSlipOlderSample
    spec._wheelSlipPreviousSample = longitudinalSlipIntensity
    spec._wheelSlipOlderSample = previousSlip
    spec.wheelSlipIntensity = longitudinalSlipIntensity + previousSlip + olderSlip
        - math.min(longitudinalSlipIntensity, previousSlip, olderSlip)
        - math.max(longitudinalSlipIntensity, previousSlip, olderSlip)
end

---Averages the tyre friction and the surface hardness of grounded wheels
local function updateWheelGroundState(vehicle)
    local spec_wheels = vehicle.spec_wheels
    local spec = vehicle.spec_RealisticMechanicalSystems
    if spec == nil then return end
    if spec_wheels == nil or spec_wheels.wheels == nil then
        spec.avgTireGroundFrictionCoeff = 0
        spec.avgGroundSurfaceFactor = 0
        return
    end

    local frictionSum = 0
    local frictionCount = 0
    local surfaceFactorSum = 0
    local groundedWheelCount = 0
    for _, wheel in ipairs(spec_wheels.wheels) do
        local physics = wheel ~= nil and wheel.physics or nil
        if physics ~= nil and physics.hasGroundContact == true then
            groundedWheelCount = groundedWheelCount + 1

            local coeff = tonumber(physics.tireGroundFrictionCoeff)
            if coeff ~= nil and coeff > 0 then
                frictionSum = frictionSum + coeff
                frictionCount = frictionCount + 1
            end

            local densityType = physics.densityType or FieldGroundType.NONE
            local groundDepth = math.clamp(tonumber(physics.groundDepth) or 0, 0, 1)
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
local HYDRAULIC_LIFT_RATIO_INTERPOLATION_RATE = 1 / 1000

---Sums the tire load of the wheels touching ground
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

---Tells whether an attacher joint type is one of the trailer types
local function isTrailerJointType(jointTypeId)
    return jointTypeId == AttacherJoints.JOINTTYPE_TRAILER
        or jointTypeId == AttacherJoints.JOINTTYPE_TRAILERLOW
        or jointTypeId == AttacherJoints.JOINTTYPE_TRAILERCAR
        or jointTypeId == AttacherJoints.JOINTTYPE_SEMITRAILERCAR
end

---Tells whether an attacher joint is moving
local function getMoveState(vehicle, moveKey, jointDesc, nextMoveAlphaCache)
    local spec = vehicle.spec_RealisticMechanicalSystems
    if spec == nil then
        return false
    end
    local moveAlpha = jointDesc ~= nil and (jointDesc.moveAlpha or 0) or 0
    local prevMoveAlphaCache = spec.hydraulicsMoveAlphaCache or {}
    
    local prevMoveAlpha = prevMoveAlphaCache[moveKey]
    nextMoveAlphaCache[moveKey] = moveAlpha

    if prevMoveAlpha ~= nil then
        return math.abs(moveAlpha - prevMoveAlpha) > 0.0001
    end

    local isMovingRaw = jointDesc ~= nil and jointDesc.isMoving == true
    return isMovingRaw and moveAlpha > 0.001 and moveAlpha < 0.999
end

---Reads the hydraulic motion of cylinders, joint control and hammer
local function getHydraulicMotionFlags(vehicle)
    local isCylinderedMoving = false
    local isAttacherJointControlMoving = false
    local isHydraulicHammerActive = false

    if vehicle ~= nil and vehicle.spec_cylindered ~= nil then
        local cylinderedSpec = vehicle.spec_cylindered
        isCylinderedMoving = RMS_Utils.hasHydraulicActuatorCapability(vehicle)
            and (cylinderedSpec.movingToolNeedsSound == true or cylinderedSpec.movingPartNeedsSound == true)
    end

    if vehicle ~= nil and vehicle.spec_attacherJointControl ~= nil then
        local lastMoveTime = tonumber(vehicle.spec_attacherJointControl.lastMoveTime)
        isAttacherJointControlMoving = lastMoveTime ~= nil and lastMoveTime + 100 > g_time
    end

    if vehicle ~= nil and vehicle.spec_hydraulicHammer ~= nil and vehicle.getIsTurnedOn ~= nil then
        isHydraulicHammerActive = vehicle:getIsTurnedOn()
    end

    return isCylinderedMoving, isAttacherJointControlMoving, isHydraulicHammerActive
end

---Walks the implement chain for lifted mass and hydraulic flags
local function updateImplementChainState(vehicle, dt)
    local spec = vehicle.spec_RealisticMechanicalSystems
    if spec == nil then
        return 0
    end

    spec.liftedMass = 0
    spec.isImplementLifted = false
    spec.isImplementOperating = false
    spec.isImplementLowered = false
    spec.isHydraulicActive = false
    spec.isHydraulicLiftMoving = false
    spec.hydraulicLiftMassByJoint = {}
    spec.hydraulicActiveTargetCount = 0

    local nextMoveAlphaCache = {}
    local nextLiftRatioCache = {}
    local implements = {}
    local implementNames = RMS_Utils.getIsDebugDataWanted(vehicle) and {} or nil
    local liftBranches = {}
    local visited = {}
    local maxCutterArea = 0

    ---Walks one branch of the implement chain
    local function collectImplementState(vehicleObj, parentObj, jointDesc, jointDescIndex, isHead, liftBranch)
        if vehicleObj == nil or visited[vehicleObj] then
            return
        end

        visited[vehicleObj] = true
        local supportWheelLoad = getWheelSupportLoad(vehicleObj)
        local isMoving = false
        if isHead then
            if vehicleObj.spec_attacherJoints ~= nil and vehicleObj.spec_attacherJoints.attacherJoints ~= nil then
                for index, headJointDesc in pairs(vehicleObj.spec_attacherJoints.attacherJoints) do
                    if RMS_Utils.getIsHydraulicLiftJoint(headJointDesc) then
                        isMoving = isMoving or getMoveState(vehicleObj, "__head:" .. tostring(index), headJointDesc, nextMoveAlphaCache)
                    end
                end
            end
        else
            local moveKey = string.format("%s:%s", tostring(vehicleObj), tostring(jointDescIndex or -1))
            if jointDesc ~= nil and RMS_Utils.getIsHydraulicLiftJoint(jointDesc) then
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
            mass = vehicleObj.getTotalMass ~= nil and (vehicleObj:getTotalMass(true) or 0) or 0,
            jointTypeId = isHead and 0 or (jointDesc ~= nil and jointDesc.jointType or nil),
            isLowered = isLowered,
            isMoving = isMoving,
            isCylinderedMoving = isCylinderedMoving,
            isAttacherJointControlMoving = isAttacherJointControlMoving,
            isHydraulicHammerActive = isHydraulicHammerActive
        }
        table.insert(implements, implementData)

        if not isHead then
            if implementNames ~= nil then
                table.insert(implementNames, vehicleObj.getFullName ~= nil and vehicleObj:getFullName()
                    or tostring(vehicleObj.configFileName or vehicleObj.customEnvironment or "implement"))
            end
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

        local attachedImplements = vehicleObj.getAttachedImplements ~= nil and vehicleObj:getAttachedImplements() or nil
        if attachedImplements ~= nil then
            for _, implementData in pairs(attachedImplements) do
                local childObj = implementData ~= nil and implementData.object or nil
                if childObj ~= nil then
                    local childJointDesc = nil
                    if vehicleObj.spec_attacherJoints ~= nil and vehicleObj.spec_attacherJoints.attacherJoints ~= nil then
                        childJointDesc = vehicleObj.spec_attacherJoints.attacherJoints[implementData.jointDescIndex]
                    end
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
                spec.isImplementLifted = spec.isImplementLifted or liftRatioState.applied > 0
                if branch.jointDesc ~= nil and RMS_Utils.getIsHydraulicLiftJoint(branch.jointDesc) then
                    spec.hydraulicLiftMassByJoint[branch.jointDesc] = liftedBranchMass
                end
            end
        end
    end

    local isOnField = vehicle.getIsOnField ~= nil and vehicle:getIsOnField() or false
    local lastSpeed = vehicle.getLastSpeed ~= nil and vehicle:getLastSpeed() or 0
    local isTurnedOn = vehicle.getIsTurnedOn == nil or vehicle:getIsTurnedOn()

    spec.hydraulicsMoveAlphaCache = nextMoveAlphaCache
    spec.hydraulicsLiftRatioCache = nextLiftRatioCache
    spec.isImplementOperating = spec.isHydraulicActive
    if implementNames ~= nil then
        spec.debugData = spec.debugData or {}
        spec.debugData.implements = spec.debugData.implements or {}
        spec.debugData.implements.names = implementNames
    end
    spec.hasDebris = maxCutterArea > 0 and isOnField and lastSpeed >= 0.5 and isTurnedOn
end


---Measures chassis vibration from the suspension travel of grounded wheels
local function updateChassisVibState(vehicle, dt)
    local spec = vehicle.spec_RealisticMechanicalSystems
    if spec == nil then
        return
    end

    local vibState = spec.chassisVibState
    local prevSuspension = vibState.prevSuspension

    local speed = vehicle:getLastSpeed()
    local vibRaw = 0
    local vibSpeedFactor = 0

    if speed > 0.003 and vehicle.spec_wheels ~= nil and vehicle.spec_wheels.wheels ~= nil then
        local sumSuspNorm = 0
        local countSuspNorm = 0

        for wheelIndex, wheel in ipairs(vehicle.spec_wheels.wheels) do
            local runtimeWheel = wheel.physics or wheel
            local netInfo = runtimeWheel.netInfo or wheel.netInfo
            local suspTravel = tonumber(runtimeWheel.suspTravel or wheel.suspTravel) or 0
            local suspLength = tonumber((netInfo and netInfo.suspensionLength) or runtimeWheel.suspensionLength or wheel.suspensionLength) or 0
            local prevSuspLength = tonumber(prevSuspension[wheelIndex]) or suspLength
            local suspDelta = math.abs(suspLength - prevSuspLength)
            prevSuspension[wheelIndex] = suspLength

            local suspNorm = 0
            if suspTravel > 0.0001 then
                suspNorm = math.min(suspDelta / suspTravel, 3.0)
            end

            local hasGroundContact = false
            if wheel.physics ~= nil and wheel.physics.hasGroundContact ~= nil then
                hasGroundContact = wheel.physics.hasGroundContact == true
            elseif runtimeWheel.hasGroundContact ~= nil then
                hasGroundContact = runtimeWheel.hasGroundContact == true
            elseif wheel.hasGroundContact ~= nil then
                hasGroundContact = wheel.hasGroundContact == true
            end

            if hasGroundContact then
                sumSuspNorm = sumSuspNorm + suspNorm
                countSuspNorm = countSuspNorm + 1
            end
        end

        vibRaw = countSuspNorm > 0 and (sumSuspNorm / countSuspNorm) or 0
        vibSpeedFactor = math.clamp(speed, 0.0, 50.0) / 50.0
    end

    local vibSignal = vibRaw * vibSpeedFactor
    local alpha = dt / (300 + dt)

    vibState.raw = vibRaw
    vibState.signal = vibSignal
    vibState.smoothed = vibState.smoothed + (vibSignal - vibState.smoothed) * alpha
    vibState.isWearing = vibState.smoothed > RMS_Config.CORE.CHASSIS_FACTOR_DATA.VIB_FACTOR_THRESHOLD
end

---Measures the steering travel, the steered axle load and the wheel angle
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

    -- the steering as a share of its lock, whoever drives
    local lock = vehicle.rotatedTime >= 0 and vehicle.maxRotTime or -vehicle.minRotTime
    local position = lock > 0 and vehicle.rotatedTime / lock or 0
    steerState.travelRate = math.abs(position - steerState.position) / (dt * 0.001)
    steerState.position = position

    local drivable = vehicle.spec_drivable
    steerState.angleMagnitude = angle
    steerState.inputMagnitude = drivable ~= nil and math.abs(drivable.axisSide) or 0
    steerState.groundContact = groundContact
    -- past the load its relief valve is set for, a steering stalls instead of pushing harder
    steerState.axleLoadRatio = restLoad > 0 and math.min(tireLoad / restLoad, C.STEER_LOAD_AXLE_RATIO_MAX) or 1
    steerState.isMoving = steerState.travelRate > C.STEER_LOAD_RATE_DEADZONE
end

---Reads the brake pedal, the towed mass and the power to mass ratios
local function updateChassisBrakingState(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    if spec == nil then
        return
    end

    local brakeState = spec.chassisBrakeState
    brakeState.pedal = 0
    brakeState.massRatio = 0
    brakeState.trailerMass = 0
    brakeState.totalMass = 0
    brakeState.hpTrailerMassRatio = 1000
    brakeState.hpGrossMassRatio = 1000
    brakeState.isBraking = false
    brakeState.isBrakingByAxis = false

    local totalMass = vehicle:getTotalMass()
    local selfMass = vehicle:getTotalMass(true)
    local trailerMass = math.max(totalMass - selfMass, 0)
    local motor = vehicle.getMotor ~= nil and vehicle:getMotor() or nil
    local horsepower = math.max(((motor ~= nil and motor.peakMotorPower) or 0) * 1.36, 0.001)
    brakeState.trailerMass = trailerMass
    brakeState.totalMass = totalMass
    brakeState.hpTrailerMassRatio = horsepower / math.max(trailerMass, 0.01)
    brakeState.hpGrossMassRatio = horsepower / math.max(totalMass, 0.01)

    local drivable = vehicle.spec_drivable
    if drivable == nil or vehicle.spec_wheels == nil then
        return
    end

    -- only the brake pedal counts as braking, not the hold of a park brake
    local brakePedalRaw = RMS_Drivetrain.getGameBrakePedal(vehicle)
    local axisForward = drivable.axisForward
    local movingDirection = tonumber(vehicle.movingDirection) or 0
    local directionMode = vehicle.getDirectionChangeMode ~= nil and vehicle:getDirectionChangeMode() or 1
    local isBrakingByAxis = false

    if directionMode == 2 then
        isBrakingByAxis = axisForward < -0.01
    else
        isBrakingByAxis = movingDirection ~= 0 and axisForward ~= 0 and math.sign(movingDirection) ~= math.sign(axisForward)
    end

    local brakePedalThreshold = tonumber(RMS_Config.CORE.CHASSIS_FACTOR_DATA.BRAKE_PEDAL_THRESHOLD) or 0.15
    local brakePedal = math.clamp(brakePedalRaw, 0, 1)
    local isBraking = isBrakingByAxis or brakePedal > brakePedalThreshold

    local ownMass = vehicle:getTotalMass(true)
    local totalMass = vehicle:getTotalMass()
    local brakeMassRatio = ownMass > 0 and math.max(totalMass / ownMass, 0) or 0

    brakeState.pedal = brakePedal
    brakeState.massRatio = brakeMassRatio
    brakeState.isBraking = isBraking
    brakeState.isBrakingByAxis = isBrakingByAxis
end

---Tracks the fuel level, the consumption and the wet stacking deposits
local function updateFuelState(vehicle, dt)
    local spec = vehicle.spec_RealisticMechanicalSystems
    if spec == nil then
        return
    end

    local fuelState = spec.fuelState

    ---Returns the fill level of the fuel the vehicle burns
    local function resolveFuelLevel()
        local fuelFillUnit = nil
        if vehicle.getConsumerFillUnitIndex ~= nil then
            fuelFillUnit = vehicle:getConsumerFillUnitIndex(FillType.DIESEL)
        end

        if type(fuelFillUnit) == "table" then
            fuelFillUnit = tonumber(fuelFillUnit.fillUnitIndex or fuelFillUnit.index or fuelFillUnit[1])
        end

        local dieselType = FillType.DIESEL
        local methaneType = FillType.METHANE
        local electricType = FillType.ELECTRICCHARGE

        if fuelFillUnit == nil and vehicle.spec_motorized ~= nil and vehicle.spec_motorized.consumers ~= nil then
            for _, consumer in pairs(vehicle.spec_motorized.consumers) do
                if consumer ~= nil and consumer.fillUnitIndex ~= nil then
                    local fillType = consumer.fillType
                    if fillType == dieselType or fillType == methaneType or fillType == electricType then
                        fuelFillUnit = consumer.fillUnitIndex
                        break
                    end
                end
            end
        end

        if fuelFillUnit ~= nil then
            local fuelLiters = tonumber(vehicle:getFillUnitFillLevel(fuelFillUnit)) or 0
            local fuelCapacity = tonumber(vehicle:getFillUnitCapacity(fuelFillUnit)) or 0
            return fuelCapacity > 0 and (fuelLiters / fuelCapacity) or 0
        end

        return 0
    end

    ---Returns the current fuel usage as a ratio of the maximum usage
    local function resolveFuelUsageRatio()
        local motorizedSpec = vehicle.spec_motorized
        if motorizedSpec == nil then
            return 0
        end

        local fuelConsumer = nil

        if motorizedSpec.consumersByFillTypeName ~= nil then
            fuelConsumer = motorizedSpec.consumersByFillTypeName["DIESEL"]
                or motorizedSpec.consumersByFillTypeName["METHANE"]
                or motorizedSpec.consumersByFillTypeName["ELECTRICCHARGE"]
        end

        if fuelConsumer == nil and motorizedSpec.consumers ~= nil then
            for _, consumer in pairs(motorizedSpec.consumers) do
                if consumer ~= nil and consumer.fillType ~= nil then
                    if consumer.fillType == FillType.DIESEL
                    or consumer.fillType == FillType.METHANE
                    or consumer.fillType == FillType.ELECTRICCHARGE then
                        fuelConsumer = consumer
                        break
                    end
                end
            end
        end

        local baseFuelUsageLh = 0
        if fuelConsumer ~= nil and fuelConsumer.usage ~= nil then
            if fuelConsumer.permanentConsumption then
                baseFuelUsageLh = (fuelConsumer.usage or 0) * 60 * 60 * 1000
            else
                baseFuelUsageLh = fuelConsumer.usage or 0
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
            local vehicleDamage = vehicle:getVehicleDamage() or 0
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
        -- a battery has no fuel temperature and leaves no deposits, only its draw is read
        fuelState.currentUsageRatio = vehicle:getIsMotorStarted() and resolveFuelUsageRatio() or 0
    elseif vehicle.getIsMotorStarted ~= nil and vehicle:getIsMotorStarted() then
        fuelState.currentUsageRatio = resolveFuelUsageRatio()

        local environmentTemp = RMS_Utils.getAmbientTemperature()

        fuelState.temperature = math.max(RealisticMechanicalSystems.sanitizeNumber(spec.rawEngineTemperature or spec.engineTemperature, environmentTemp, -80, 160) / 3.6, environmentTemp)

        local idleSpeedThreshold = RMS_Config.CORE.FUEL_FACTOR_DATA.IDLE_DEPOSIT_SPEED_THRESHOLD
        local idleLoadThreshold = RMS_Config.CORE.FUEL_FACTOR_DATA.IDLE_DEPOSIT_LOAD_THRESHOLD
        local motorLoad = vehicle.getMotorLoadPercentage ~= nil and (vehicle:getMotorLoadPercentage() or 0) or 0
        local idleTimer = math.max(tonumber(fuelState.idleTimer) or 0, 0)
        local isIdle = (vehicle:getLastSpeed() or 0) <= idleSpeedThreshold and motorLoad <= idleLoadThreshold

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
            engineTemperature = spec.rawEngineTemperature or spec.engineTemperature,
            isIdle = isIdle,
            isDiesel = spec.isDieselVehicle,
            isMotorStarted = true
        })
    else
        fuelState.currentUsageRatio = 0
        fuelState.temperature = 0
        fuelState.idleTimer = 0
    end
end

---Reads the PTO torque, rpm, power and use, and counts engagements
local function updatePtoState(vehicle, dt)
    local spec = vehicle.spec_RealisticMechanicalSystems
    local systemData = spec.systems.pto

    if systemData == nil or systemData.enabled == false then
        spec.isPtoActive = false
        spec.ptoTorque = 0
        spec.ptoRpm = 0
        spec.ptoPower = 0
        spec.ptoUtilization = 0
        spec.isPtoImplementRaised = false
        if type(spec.ptoPreviousActiveLinks) ~= "table" or next(spec.ptoPreviousActiveLinks) ~= nil then
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

    local previousActiveLinks = spec.ptoPreviousActiveLinks or {}
    local newEngagementCount = RMS_Utils.getPtoEngagementTransitionCount(ptoData.activeLinks, previousActiveLinks)
    if newEngagementCount > 0 then
        spec.ptoEngagementCount = (tonumber(spec.ptoEngagementCount) or 0) + newEngagementCount
        spec.ptoEngagementSequence = (tonumber(spec.ptoEngagementSequence) or 0) + newEngagementCount
        local damage, isShock = RMS_Utils.getPtoEngagementDamage(vehicle, ptoData.engagementTorques, previousActiveLinks, spec.ptoLastRpmShare)
        spec.ptoEngagementDamage = (tonumber(spec.ptoEngagementDamage) or 0) + damage
        if isShock then
            spec.ptoShockSequence = (tonumber(spec.ptoShockSequence) or 0) + 1
        end
    end
    spec.ptoPreviousActiveLinks = ptoData.activeLinks
    spec.isPtoImplementRaised = ptoData.isRaised

    -- an engagement is judged on the engine speed before the game revs up for it
    spec.ptoLastRpmShare = RMS_Utils.getMotorRpmShareAboveIdle(vehicle)
end

---Refreshes the vehicle state on the server, each group on its interval
-- @param float dt time since last call in ms
function RealisticMechanicalSystems:updateVehicleStateSnapshot(dt)
    local spec = self.spec_RealisticMechanicalSystems
    if not self.isServer or spec == nil or spec.isExcludedVehicle then return end

    local delayOne = RMS_Config.UPDATE_VEHICLE_STATE_DELAY_ONE
    local delayTwo = RMS_Config.UPDATE_VEHICLE_STATE_DELAY_TWO
    local delayThree = RMS_Config.UPDATE_VEHICLE_STATE_DELAY_THREE

    spec.updateVehicleStateTimerOne = spec.updateVehicleStateTimerOne + dt
    spec.updateVehicleStateTimerTwo = spec.updateVehicleStateTimerTwo + dt
    spec.updateVehicleStateTimerThree = spec.updateVehicleStateTimerThree + dt

    -- GROUP 1
    if spec.updateVehicleStateTimerOne >= delayOne then
        spec.updateVehicleStateTimerOne = spec.updateVehicleStateTimerOne % delayOne
        updatePtoState(self, delayOne)
        updateAvgAbsDiffAccWindow(spec, self:getMotor(), delayOne)
        updateDynamicMotorLoad(self, delayOne)
    end

    -- GROUP 2
    if spec.updateVehicleStateTimerTwo >= delayTwo then
        spec.updateVehicleStateTimerTwo = spec.updateVehicleStateTimerTwo % delayTwo
        updateStarterState(self)
        updateWheelSlip(self)
        updateChassisVibState(self, delayTwo)
        RMS_Steering.updateTutorialTimers(self, delayTwo)
        updateChassisSteeringState(self, delayTwo)
        updateChassisBrakingState(self)
    end
    
    -- GROUP 3
    if spec.updateVehicleStateTimerThree >= delayThree then
        spec.updateVehicleStateTimerThree = spec.updateVehicleStateTimerThree % delayThree
        updateActiveDraftStats(self)
        updateWheelGroundState(self)
        updateImplementChainState(self, delayThree)
        updateFuelState(self, delayThree)
        spec.isUnderRoof = self:isUnderRoof()
    end
end
