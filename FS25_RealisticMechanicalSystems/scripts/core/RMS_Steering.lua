-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---Steering faults applied to the angles the game sends to the physics
RMS_Steering = {}

local DEG = math.pi / 180
local FULL_TURN = 2 * math.pi
-- km/h a free fall gains each second
local GRAVITY = 9.81 * 3.6

-- breakdowns owning the wheel a pull or a broken rod end acts on
local TARGET_BREAKDOWNS = { "STEERING_LINKAGE_WEAR", "TRACK_TENSIONER_MALFUNCTION" }

---Returns the steering faults in force on a vehicle
local function getFaults(spec)
    local effects = spec.activeEffects
    local play = effects.STEERING_PLAY_EFFECT
    local pull = effects.STEERING_STATIC_BIAS_EFFECT
    return (play ~= nil and play.value or 0) * DEG,
        (pull ~= nil and pull.value or 0) * DEG,
        effects.STEERING_WHEEL_FREE_EFFECT ~= nil
end

---Returns the side a wheel sits on
local function getWheelSide(wheel)
    return wheel.physics.positionX >= 0 and 1 or -1
end

---Returns the steered wheels of a vehicle
local function getSteeredWheels(vehicle)
    local steered = {}
    for _, wheel in ipairs(vehicle.spec_wheels.wheels) do
        if RMS_Drivetrain.getIsWheelSteerable(wheel) then
            steered[#steered + 1] = wheel
        end
    end
    return steered
end

---Resolves the wheel a pull or a broken rod end acts on
local function resolveTarget(vehicle, state)
    local spec = vehicle.spec_RealisticMechanicalSystems
    local breakdown = nil
    for _, id in ipairs(TARGET_BREAKDOWNS) do
        breakdown = breakdown or spec.activeBreakdowns[id]
    end

    state.isTargetResolved = true
    state.targetWheel = nil
    state.targetSide = 0
    if breakdown == nil then
        return
    end

    -- an articulated machine has no steered wheel: the draw only picks a side
    local steered = getSteeredWheels(vehicle)
    local count = math.max(#steered, 2)
    if vehicle.isServer and (breakdown.effectTargetIndex < 1 or breakdown.effectTargetIndex > count) then
        breakdown.effectTargetIndex = math.random(1, count)
        RealisticMechanicalSystems.raiseRMSDirty(vehicle, RealisticMechanicalSystems.SYNC_GROUP.BREAKDOWNS)
    end

    local index = breakdown.effectTargetIndex
    if index >= 1 and index <= count then
        state.targetWheel = steered[index]
        state.targetSide = state.targetWheel ~= nil and getWheelSide(state.targetWheel) or (index == 1 and 1 or -1)
    end
end

---Hooks the per wheel steering call of the game while a fault is active
-- @param table vehicle vehicle
function RMS_Steering.refreshFaults(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    local effects = spec.activeEffects
    local isActive = effects.STEERING_PLAY_EFFECT ~= nil
        or effects.STEERING_STATIC_BIAS_EFFECT ~= nil
        or effects.STEERING_WHEEL_FREE_EFFECT ~= nil

    if isActive then
        if spec.steeringFault == nil then
            spec.steeringFault = {
                parts = {},
                suspension = {},
                nativeSteeringCall = vehicle.customSteeringAngleFunction
            }
            vehicle.customSteeringAngleFunction = true
        end
        -- the wheel is looked up on the next steering call, when a vehicle still loading has its wheels set up
        spec.steeringFault.isTargetResolved = false
    elseif spec.steeringFault ~= nil then
        vehicle.customSteeringAngleFunction = spec.steeringFault.nativeSteeringCall
        spec.steeringFault = nil
    end
end

---Returns the state of a steered part, starting at rest on its command
local function getPartState(state, part, command)
    local partState = state.parts[part]
    if partState == nil then
        partState = { offset = 0, command = command, caster = command }
        state.parts[part] = partState
    end
    return partState
end

---Returns how far a wheel's suspension moved since its last reading
local function readSuspensionStroke(state, wheel)
    local physics = wheel.physics
    local length = physics.netInfo.suspensionLength
    local last = state.suspension[wheel] or length
    state.suspension[wheel] = length
    return math.clamp((length - last) / physics.suspTravel, -1, 1)
end

---Moves a steered part inside its play
local function updatePlay(partState, command, kick, play, speed, dt)
    local C = RMS_Config.CORE.CHASSIS_FACTOR_DATA
    local speedShare = math.min(speed / C.STEER_PLAY_FULL_SPEED, 1)
    local offset = partState.offset - (command - partState.command) + kick * C.STEER_PLAY_KICK_GAIN * speedShare * play
    local trailed = -math.clamp(command, -play, play)
    local alpha = 1 - math.exp(-dt / (C.STEER_PLAY_RECENTER_TIME * 1000) * speedShare)

    partState.offset = math.clamp(offset + (trailed - offset) * alpha, -play, play)
    partState.command = command
    return partState.offset
end

---Returns the wobble of a worn front end
local function getShimmy(play, speed)
    local C = RMS_Config.CORE.CHASSIS_FACTOR_DATA
    if play < C.STEER_SHIMMY_MIN_PLAY * DEG then
        return 0
    end

    local share
    if speed <= C.STEER_SHIMMY_SPEED_PEAK then
        share = (speed - C.STEER_SHIMMY_SPEED_MIN) / (C.STEER_SHIMMY_SPEED_PEAK - C.STEER_SHIMMY_SPEED_MIN)
    else
        share = (C.STEER_SHIMMY_SPEED_MAX - speed) / (C.STEER_SHIMMY_SPEED_MAX - C.STEER_SHIMMY_SPEED_PEAK)
    end
    return play * C.STEER_SHIMMY_SHARE * math.clamp(share, 0, 1) * math.sin(g_time * 0.001 * FULL_TURN * C.STEER_SHIMMY_FREQUENCY)
end

---Returns how much of a fault remains near a steering stop
local function getStopShare(command, rotMin, rotMax)
    local margin = math.min(rotMax - command, command - rotMin)
    return math.clamp(margin / (RMS_Config.CORE.CHASSIS_FACTOR_DATA.STEER_STOP_BLEND * DEG), 0, 1)
end

---Returns the angle of a wheel whose rod end let go
local function getFreeWheelAngle(vehicle, wheel, partState, command, speed, dt)
    local C = RMS_Config.CORE.CHASSIS_FACTOR_DATA
    local physics = wheel.physics

    -- only the server runs the caster routine, a client shows the commanded angle
    if vehicle.isServer then
        partState.caster = Utils.getVersatileRotation(wheel.repr, wheel.node, dt, physics.positionX, physics.positionY, physics.positionZ, partState.caster, physics.rotMin, physics.rotMax)
    else
        partState.caster = command
    end

    local flutterShare = math.clamp((speed - C.STEER_FREE_FLUTTER_SPEED_MIN) / (C.STEER_FREE_FLUTTER_SPEED_MAX - C.STEER_FREE_FLUTTER_SPEED_MIN), 0, 1)
    local flutter = C.STEER_FREE_FLUTTER_ANGLE * DEG * flutterShare * math.sin(g_time * 0.001 * FULL_TURN * C.STEER_SHIMMY_FREQUENCY)
    return math.clamp(partState.caster + flutter, physics.rotMin, physics.rotMax)
end

---Applies the steering faults to the angle the game computed for a wheel
-- @param table vehicle vehicle
-- @param function superFunc super function
-- @param table wheel wheel
-- @param float dt time since last call in ms
-- @param float steeringAngle angle the game commands in rad
-- @return float steeringAngle angle sent to the physics in rad
function RMS_Steering.updateSteeringAngle(vehicle, superFunc, wheel, dt, steeringAngle)
    steeringAngle = superFunc(vehicle, wheel, dt, steeringAngle)

    local spec = vehicle.spec_RealisticMechanicalSystems
    local state = spec.steeringFault
    if state == nil then
        return steeringAngle
    end

    if not state.isTargetResolved then
        resolveTarget(vehicle, state)
    end

    local play, pull, isFree = getFaults(spec)
    local physics = wheel.physics
    local speed = vehicle:getLastSpeed()
    local partState = getPartState(state, wheel, steeringAngle)
    local side = getWheelSide(wheel)
    local stroke = readSuspensionStroke(state, wheel)

    if wheel == state.targetWheel and isFree then
        return getFreeWheelAngle(vehicle, wheel, partState, steeringAngle, speed, dt)
    end

    local offset = updatePlay(partState, steeringAngle, side * stroke, play, speed, dt)
    offset = math.clamp(offset + getShimmy(play, speed), -play, play)
    if wheel == state.targetWheel then
        offset = offset + side * pull
    end

    local faulty = steeringAngle + offset * getStopShare(steeringAngle, physics.rotMin, physics.rotMax)
    return math.clamp(faulty, physics.rotMin, physics.rotMax)
end

---Returns the articulation angle untouched for types without their own hook
-- @param table vehicle vehicle
-- @param float steeringAngle angle the game commands in rad
-- @param float dt time since last call in ms
-- @return float steeringAngle same angle
function RMS_Steering.passArticulatedAxisRotation(vehicle, steeringAngle, dt)
    return steeringAngle
end

---Applies the steering faults to the articulation angle
-- @param table vehicle vehicle
-- @param function superFunc super function
-- @param float steeringAngle angle the game commands in rad
-- @param float dt time since last call in ms
-- @return float steeringAngle angle the articulation takes in rad
function RMS_Steering.updateArticulatedAxisRotation(vehicle, superFunc, steeringAngle, dt)
    steeringAngle = superFunc(vehicle, steeringAngle, dt)

    local spec = vehicle.spec_RealisticMechanicalSystems
    local state = spec.steeringFault
    if state == nil then
        return steeringAngle
    end

    if not state.isTargetResolved then
        resolveTarget(vehicle, state)
    end

    local play, pull, isFree = getFaults(spec)
    if isFree then
        play = RMS_Config.CORE.CHASSIS_FACTOR_DATA.STEER_FREE_ARTICULATION_PLAY * DEG
    end

    -- the wheels of both sides push the joint against each other
    local wheels = vehicle.spec_wheels.wheels
    local kick = 0
    for _, wheel in ipairs(wheels) do
        kick = kick + getWheelSide(wheel) * readSuspensionStroke(state, wheel)
    end

    local axis = vehicle.spec_articulatedAxis
    local speed = vehicle:getLastSpeed()
    local partState = getPartState(state, axis, steeringAngle)
    local offset = updatePlay(partState, steeringAngle, kick / #wheels, play, speed, dt)
    offset = math.clamp(offset + getShimmy(play, speed), -play, play) + state.targetSide * pull

    local faulty = steeringAngle + offset * getStopShare(steeringAngle, axis.rotMin, axis.rotMax)
    return math.clamp(faulty, axis.rotMin, axis.rotMax)
end

---Returns the most speed the tyres of a machine can take off it
local function getGripLimit(vehicle)
    local grip = 0
    for _, wheel in ipairs(vehicle.spec_wheels.wheels) do
        grip = math.max(grip, wheel.physics.frictionScale * wheel.physics.tireGroundFrictionCoeff)
    end
    -- a tyre holds its grip times the weight it carries, and a slope adds its own pull
    return GRAVITY * math.sqrt(1 + grip * grip)
end

---Damages the chassis for one impact, by the speed it took off the machine
local function applyImpact(vehicle, speedLoss)
    local C = RMS_Config.CORE.CHASSIS_FACTOR_DATA
    local spec = vehicle.spec_RealisticMechanicalSystems
    local damage = math.min(speedLoss * C.TERRAIN_IMPACT_DAMAGE_PER_KMH, C.TERRAIN_IMPACT_MAX_DAMAGE)

    vehicle:applyInstantDamageToSystem(RealisticMechanicalSystems.SYSTEMS.CHASSIS, damage, "terrainImpactFactor")
    spec.terrainImpacts.count = spec.terrainImpacts.count + 1
    spec.terrainImpacts.lastSpeedLoss = speedLoss
    spec.terrainImpactTutorialTimer = C.TERRAIN_IMPACT_TUTORIAL_MS
end

---Times the shaking and impact tutorial tips
-- @param table vehicle vehicle
-- @param float dt time since last call in ms
function RMS_Steering.updateTutorialTimers(vehicle, dt)
    local spec = vehicle.spec_RealisticMechanicalSystems
    local C = RMS_Config.CORE.CHASSIS_FACTOR_DATA

    if spec.chassisVibState.isWearing then
        spec.vibrationTutorialTimer = math.min(spec.vibrationTutorialTimer + dt, C.VIB_TUTORIAL_MS)
    else
        spec.vibrationTutorialTimer = math.max(spec.vibrationTutorialTimer - dt, 0)
    end
    spec.terrainImpactTutorialTimer = math.max(spec.terrainImpactTutorialTimer - dt, 0)
end

---Reads an impact off a speed loss beyond what the tyres can take
-- @param table vehicle vehicle
-- @param float dt time since last call in ms
function RMS_Steering.updateTerrainImpacts(vehicle, dt)
    local spec = vehicle.spec_RealisticMechanicalSystems
    if not spec.systems.chassis.enabled then
        return
    end

    local C = RMS_Config.CORE.CHASSIS_FACTOR_DATA
    local impacts = spec.terrainImpacts

    -- the speed of the body along the ground, bounces left out
    local velocityX, _, velocityZ = getLocalLinearVelocity(vehicle.components[1].node)
    local speed = MathUtil.vector2Length(velocityX, velocityZ) * 3.6
    -- a speed loss beyond what the tyres can take is an impact
    local heldSpeed = speed
    if speed < impacts.heldSpeed and impacts.heldSpeed >= C.TERRAIN_IMPACT_MIN_SPEED_LOSS then
        heldSpeed = math.max(impacts.heldSpeed - getGripLimit(vehicle) * dt * 0.001, speed)
    end
    local speedLoss = heldSpeed - speed

    if speedLoss >= C.TERRAIN_IMPACT_MIN_SPEED_LOSS and speedLoss >= impacts.speedLoss then
        impacts.speedLoss = speedLoss
    elseif impacts.speedLoss > 0 then
        applyImpact(vehicle, impacts.speedLoss)
        impacts.speedLoss = 0
        heldSpeed = speed
    end
    impacts.heldSpeed = heldSpeed
end
