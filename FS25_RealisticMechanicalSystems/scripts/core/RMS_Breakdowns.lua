-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---Vehicle breakdown effects.
RMS_Breakdowns = {}

local log_dbg = RMS_Utils.createLogger("[RMS_BREAKDOWNS]")

local BRAKE_SOUND_SPEED_THRESHOLD = 15

source(g_currentModDirectory .. "scripts/core/RMS_BreakdownRegistry.lua")


RMS_Breakdowns.EffectApplicators = {}

---Returns the text describing a stage on a vehicle
function RMS_Breakdowns.getStageDescription(vehicle, stageData, breakdown, definition)
    local variant = RMS_Utils.getBreakdownNameVariant(vehicle, definition)
    local variantDescription = variant ~= nil and stageData.variantDescriptions[variant] or nil
    if type(variantDescription) == "table" then
        return variantDescription[breakdown ~= nil and breakdown.branch or 1]
    elseif variantDescription ~= nil then
        return variantDescription
    end
    if stageData.electricDescription ~= nil and vehicle.spec_RealisticMechanicalSystems.isElectricVehicle then
        return stageData.electricDescription
    end
    if stageData.branchDescriptions ~= nil and breakdown ~= nil and stageData.branchDescriptions[breakdown.branch] ~= nil then
        return stageData.branchDescriptions[breakdown.branch]
    end
    return stageData.description
end

-- an effect applied again while it runs keeps its first frame update
local function startFrameUpdate(vehicle, effectName, update)
    local updates = vehicle.spec_RealisticMechanicalSystems.activeFunctions
    updates[effectName] = updates[effectName] or update
end

local function stopFrameUpdate(vehicle, effectName)
    vehicle.spec_RealisticMechanicalSystems.activeFunctions[effectName] = nil
end

-- power splitting four and six cylinder tractors, in hp
local STARTER_SIX_CYLINDER_HP = 150
-- catch sound of each family: its catch and its end, in ms
local STARTER_CATCHES = {
    Car = { catch = 237, length = 1031 },
    Tractor4 = { catch = 65, length = 716 },
    Tractor6 = { catch = 717, length = 1120 },
    Heavy = { catch = 311, length = 1418 }
}
-- fade from the starter loop into the catch sound, in ms
local STARTER_JOIN = 30

---Returns the starter family of a machine, by store category and power
function RMS_Breakdowns.getStarterFamily(vehicle)
    local storeItem = g_storeManager:getItemByXMLFilename(vehicle.configFileName)
    local category = storeItem ~= nil and storeItem.categoryName or ""
    if category == "CARS" then
        return "Car"
    elseif category == "TRUCKS" or category:sub(-10) == "HARVESTERS" then
        return "Heavy"
    elseif category == "TRACTORSS" then
        return "Tractor4"
    end

    local isSmall = RMS_Fluids.getEnginePower(vehicle) <= STARTER_SIX_CYLINDER_HP
    if category == "TRACTORSM" or category == "TRACTORSL" then
        return isSmall and "Tractor4" or "Tractor6"
    end
    return isSmall and "Tractor4" or "Heavy"
end

---Returns the time from the catch to the engine start, in ms
-- @param table vehicle vehicle
-- @return integer delay the catch in the catch sound of its family
function RMS_Breakdowns.getStarterCatchDelay(vehicle)
    return STARTER_CATCHES[RMS_Breakdowns.getStarterFamily(vehicle)].catch
end

---Returns the run up from the engine start to the idle, in ms
function RMS_Breakdowns.getStarterRunUp(vehicle)
    local catch = STARTER_CATCHES[RMS_Breakdowns.getStarterFamily(vehicle)]
    return catch.length - catch.catch
end

---Shares the volume of the engine sounds and of the catch sound
-- @param table vehicle vehicle
-- @param float progress 0 at the engine start, 1 once the engine sounds alone
local function setStarterHandover(vehicle, progress)
    local engineShare = math.sin(progress * math.pi / 2)
    for _, sample in ipairs(vehicle.spec_motorized.motorSamples) do
        RMS_SoundManager.setSampleVolumeOffset(sample, RMS_SoundManager.getSampleVolume(sample) * (engineShare - 1))
    end
    local catchSample = vehicle.spec_RealisticMechanicalSystems.samples.starterCatch
    RMS_SoundManager.setSampleVolumeOffset(catchSample, RMS_SoundManager.getSampleVolume(catchSample) * (math.cos(progress * math.pi / 2) - 1))
end

---Turns the starter of a hard start, then plays its catch
function RMS_Breakdowns.updateStarter(vehicle, dt)
    local spec = vehicle.spec_RealisticMechanicalSystems
    if not vehicle.isClient or spec.isElectricVehicle then
        return
    end

    if spec.starterHandover ~= nil then
        spec.starterHandover = spec.starterHandover + dt
        local progress = math.min(spec.starterHandover / RMS_Breakdowns.getStarterRunUp(vehicle), 1)
        setStarterHandover(vehicle, progress)
        if progress >= 1 then
            RMS_SoundManager.setSampleVolumeOffset(spec.samples.starterCatch, 0)
            spec.starterHandover = nil
        end
    end

    local samples = spec.samples
    local state = spec.startState
    local crankSpeed = state == RMS_Start.STATE.CRANKING and RMS_Electrical.getCrankingSpeed(vehicle) or 0
    if state == RMS_Start.STATE.CATCHING and spec.isStarterTurning then
        -- loop first: stopping the engagement alone starts the queued loop
        RMS_SoundManager.stopSample(samples.starter, 0, STARTER_JOIN)
        RMS_SoundManager.stopSample(samples.starterIntro, 0, STARTER_JOIN)
        RMS_SoundManager.setSampleVolumeOffset(samples.starterCatch, 0)
        RMS_SoundManager.playSample(samples.starterCatch)
        spec.isStarterTurning = nil
        spec.isStarterCatching = true
    elseif crankSpeed > 0 then
        RMS_SoundManager.setSamplePitchOffset(samples.starterIntro, crankSpeed - 1)
        RMS_SoundManager.setSamplePitchOffset(samples.starter, crankSpeed - 1)
        if not spec.isStarterTurning then
            -- the engagement of the recording, the game chaining its loop
            RMS_SoundManager.playSample(samples.starterIntro)
            RMS_SoundManager.playSample(samples.starter, samples.starterIntro)
            spec.isStarterTurning = true
        end
    elseif spec.isStarterTurning then
        RMS_SoundManager.stopSample(samples.starter, 0, 0)
        RMS_SoundManager.stopSample(samples.starterIntro, 0, 0)
        spec.isStarterTurning = nil
    end
end

---Hands the catch over to the engine sounds, past their start recordings
function RMS_Breakdowns.onStarterCaught(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    if not spec.isStarterCatching then
        return
    end
    spec.isStarterCatching = nil
    local motorized = vehicle.spec_motorized
    RMS_SoundManager.stopSample(motorized.samples.motorStart, 0, 0)
    -- silent before they play: the game applies an offset some frames later
    spec.starterHandover = 0
    setStarterHandover(vehicle, 0)
    for _, sample in ipairs(motorized.motorSamples) do
        RMS_SoundManager.playSampleFrom(sample, RMS_SoundManager.getSampleStartDuration(sample))
    end
end

RMS_Breakdowns.EffectApplicators.SELF_DISAPPEARING_BREAKDOWN_EFFECT = {
    apply = function(vehicle, effect) vehicle:removeBreakdown(effect.extraData.breakdownId) end
}

-- the game never stops an engine already running when it may not run
local function stopRunningEngine(vehicle)
    if vehicle:getIsMotorStarted() then
        vehicle:stopMotor()
    end
end

RMS_Breakdowns.EffectApplicators.ENGINE_FAILURE = {
    apply = function(vehicle) startFrameUpdate(vehicle, "ENGINE_FAILURE", stopRunningEngine) end,
    remove = function(vehicle) stopFrameUpdate(vehicle, "ENGINE_FAILURE") end
}

-- read by the start sequence, listed for their side notifications
RMS_Breakdowns.EffectApplicators.ENGINE_HARD_START_MODIFIER = {}
RMS_Breakdowns.EffectApplicators.GLOW_PLUG_HARD_START_MODIFIER = {}

RMS_Breakdowns.EffectApplicators.LIGHTS_FAILURE = {
    apply = function(vehicle)
        if vehicle:getLightsTypesMask() ~= 0 then
            vehicle:setLightsTypesMask(0, true, true)
        end
    end
}

local LIGHT_CIRCUITS = {
    LOW_BEAM_FAILURE = "LIGHT_TYPE_DEFAULT",
    HIGH_BEAM_FAILURE = "LIGHT_TYPE_HIGHBEAM",
    FRONT_WORK_LIGHTS_FAILURE = "LIGHT_TYPE_WORK_FRONT",
    REAR_WORK_LIGHTS_FAILURE = "LIGHT_TYPE_WORK_BACK"
}

local function getIsLampMounted(vehicle, node)
    local isComponent = false
    while node ~= 0 and not isComponent do
        if not getVisibility(node) then
            return false
        end
        for _, component in ipairs(vehicle.components) do
            isComponent = isComponent or component.node == node
        end
        node = getParent(node)
    end
    return true
end

local function getHoldsLightType(vehicle, lights, lightType)
    for _, light in ipairs(lights) do
        for _, lampLightType in ipairs(light.lightTypes or {}) do
            if lampLightType == lightType and getIsLampMounted(vehicle, light.node) then
                return true
            end
        end
    end
    return false
end

local function getHoldsMountedLamp(vehicle, lights)
    for _, light in ipairs(lights) do
        if getIsLampMounted(vehicle, light.node) then
            return true
        end
    end
    return false
end

local function getCarriesLightType(vehicle, lightType)
    local spec = vehicle.spec_lights
    if spec == nil then
        return false
    end
    for _, lights in pairs(spec.staticLights) do
        if getHoldsLightType(vehicle, lights, lightType) then
            return true
        end
    end
    for _, profile in pairs(spec.realLights) do
        for _, lights in pairs(profile) do
            if getHoldsLightType(vehicle, lights, lightType) then
                return true
            end
        end
    end
    return false
end

local function getCarriesTurnLights(vehicle)
    local spec = vehicle.spec_lights
    if spec == nil then
        return false
    end
    if getHoldsMountedLamp(vehicle, spec.staticLights.turnLightsLeft) then
        return true
    end
    for _, profile in pairs(spec.realLights) do
        if getHoldsMountedLamp(vehicle, profile.turnLightsLeft) then
            return true
        end
    end
    return false
end

for effectName, lightTypeName in pairs(LIGHT_CIRCUITS) do
    RMS_Breakdowns.EffectApplicators[effectName] = {
        -- the same mask set again puts the failed circuit out
        apply = function(vehicle) vehicle:setLightsTypesMask(vehicle:getLightsTypesMask(), true, true) end,
        getIsCarried = function(vehicle) return getCarriesLightType(vehicle, Lights[lightTypeName]) end
    }
end

RMS_Breakdowns.EffectApplicators.BEACON_LIGHTS_FAILURE = {
    apply = function(vehicle)
        if vehicle:getBeaconLightsVisibility() then
            vehicle:setBeaconLightsVisibility(false, true, true)
        end
    end,

    getIsCarried = function(vehicle)
        if vehicle.spec_lights == nil then
            return false
        end
        for _, beaconLight in ipairs(vehicle.spec_lights.beaconLights) do
            if beaconLight.linkNode ~= nil and getIsLampMounted(vehicle, beaconLight.linkNode)
                or beaconLight.linkNode == nil and getHoldsMountedLamp(vehicle, beaconLight.staticLights or {}) then
                return true
            end
        end
        return false
    end
}

RMS_Breakdowns.EffectApplicators.TURN_LIGHTS_FAILURE = {
    apply = function(vehicle)
        if vehicle:getTurnLightState() ~= Lights.TURNLIGHT_OFF then
            vehicle:setTurnLightState(Lights.TURNLIGHT_OFF, true, true)
        end
    end,

    getIsCarried = getCarriesTurnLights
}

---Tells whether the machine carries the lamps of a light circuit
function RMS_Breakdowns.getCarriesLightCircuit(vehicle, effectName)
    return RMS_Breakdowns.EffectApplicators[effectName].getIsCarried(vehicle)
end

function RMS_Breakdowns.getIsLightCircuitLit(vehicle, effectName)
    local lightTypeName = LIGHT_CIRCUITS[effectName]
    if lightTypeName ~= nil then
        return bit32.band(vehicle:getLightsTypesMask(), 2 ^ Lights[lightTypeName]) ~= 0
    elseif effectName == "BEACON_LIGHTS_FAILURE" then
        return vehicle:getBeaconLightsVisibility()
    end
    return vehicle:getTurnLightState() ~= Lights.TURNLIGHT_OFF
end

---Keeps every failed light circuit out, all of them without current
function RMS_Breakdowns.setLightsTypesMask(self, superFunc, lightsTypesMask, force, noEventSend)
    local rootVehicle = self:getRootVehicle()
    local spec = rootVehicle.spec_RealisticMechanicalSystems
    local effects = spec ~= nil and spec.activeEffects or {}
    if spec ~= nil and spec.activeEffects ~= nil and (effects.LIGHTS_FAILURE ~= nil or RMS_Electrical.getKeepsLightsOff(rootVehicle)) then
        if self:getLightsTypesMask() ~= 0 then
            superFunc(self, 0, force, noEventSend)
        end
        return
    end
    for effectName, lightTypeName in pairs(LIGHT_CIRCUITS) do
        if effects[effectName] ~= nil then
            lightsTypesMask = bit32.band(lightsTypesMask, bit32.bnot(2 ^ Lights[lightTypeName]))
        end
    end
    superFunc(self, lightsTypesMask, force, noEventSend)
end

---Keeps the beacon lights out while their circuit has failed
function RMS_Breakdowns.setBeaconLightsVisibility(self, superFunc, visibility, force, noEventSend)
    local spec = self:getRootVehicle().spec_RealisticMechanicalSystems
    local activeEffects = spec ~= nil and spec.activeEffects or {}
    superFunc(self, visibility and activeEffects.BEACON_LIGHTS_FAILURE == nil, force, noEventSend)
end

---Keeps the turn and hazard lights out while their circuit has failed
function RMS_Breakdowns.setTurnLightState(self, superFunc, state, force, noEventSend)
    local spec = self:getRootVehicle().spec_RealisticMechanicalSystems
    local activeEffects = spec ~= nil and spec.activeEffects or {}
    if activeEffects.TURN_LIGHTS_FAILURE ~= nil then
        state = Lights.TURNLIGHT_OFF
    end
    superFunc(self, state, force, noEventSend)
end

local function getHasWheelShape(wheel)
    return wheel ~= nil and wheel.node ~= nil and wheel.node ~= 0 and wheel.physics.wheelShape ~= 0
end

-- a right wheel has isLeft false or lies at a positive x of the root
local SEIZED_WHEEL_CHOICES = {
    function(wheel, x) return (wheel.isLeft == false or x > 0) and wheel.physics.brakeFactor > 0 end,
    function(wheel, x) return wheel.isLeft == false or x > 0 end,
    function(wheel) return wheel.physics.brakeFactor > 0 end,
    function() return true end
}

-- the foremost wheel of the first choice any wheel meets
local function getSeizedWheel(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    local wheels = vehicle.spec_wheels.wheels
    local wheel = wheels[spec.wheelSeizureTargetIndex]
    if getHasWheelShape(wheel) then
        return wheel
    end

    local rootNode = vehicle.components[1].node
    for _, getIsChoice in ipairs(SEIZED_WHEEL_CHOICES) do
        local bestIndex, bestZ = nil, -math.huge
        for index, candidate in ipairs(wheels) do
            if getHasWheelShape(candidate) then
                local x, _, z = localToLocal(candidate.driveNode or candidate.node, rootNode, 0, 0, 0)
                if getIsChoice(candidate, x) and (bestIndex == nil or z > bestZ) then
                    bestIndex, bestZ = index, z
                end
            end
        end
        if bestIndex ~= nil then
            spec.wheelSeizureTargetIndex = bestIndex
            return wheels[bestIndex]
        end
    end
    spec.wheelSeizureTargetIndex = nil
    return nil
end

RMS_Breakdowns.EffectApplicators.BRAKE_FORCE_MODIFIER = {
}

local function refreshSteeringFaults(vehicle) RMS_Steering.refreshFaults(vehicle) end

for _, effectId in ipairs({ "STEERING_STATIC_BIAS_EFFECT", "BRAKE_PULL_EFFECT", "STEERING_PLAY_EFFECT", "STEERING_WHEEL_FREE_EFFECT" }) do
    RMS_Breakdowns.EffectApplicators[effectId] = { apply = refreshSteeringFaults, remove = refreshSteeringFaults }
end

RMS_Breakdowns.EffectApplicators.WHEEL_SEIZURE_EFFECT = {
    remove = function(vehicle) vehicle.spec_RealisticMechanicalSystems.wheelSeizureTargetIndex = nil end
}

local MISFIRE_SOUND_DIP = 0.6

local function updateMisfireSound(vehicle, extra, dt)
    local dip = 0
    if extra.status == "CHOKING" then
        -- Four-stroke firing frequency: one cycle per two revolutions.
        extra.misfireCycles = (extra.misfireCycles or 0) + dt * vehicle:getMotor():getLastModulatedMotorRpm() / 120000
        if extra.misfireCycles >= 1 then
            extra.misfireCycles = extra.misfireCycles % 1
            dip = MISFIRE_SOUND_DIP
        end
    end
    -- the engine sounds fading in after a hard start keep their own volume
    if vehicle.spec_RealisticMechanicalSystems.starterHandover ~= nil then
        return
    end
    for _, sample in ipairs(vehicle.spec_motorized.motorSamples) do
        RMS_SoundManager.setSampleVolumeOffset(sample, -dip * sample.current.volume * sample.volumeScale)
    end
end

-- extraData={status, timer, duration, motorLoad, amplitude, cruiseState}
local function updateEngineCough(vehicle, dt)
    local effect = vehicle.spec_RealisticMechanicalSystems.activeEffects.ENGINE_HESITATION_CHANCE
    local cough = effect.extraData
    if vehicle.isClient then
        updateMisfireSound(vehicle, cough, dt)
    end

    if cough.status == "CHOKING" then
        cough.timer = cough.timer + dt
        if cough.timer > cough.duration then
            if cough.cruiseState ~= 0 then
                vehicle:setCruiseControlState(cough.cruiseState, true)
            end
            cough.status, cough.timer = "IDLE", 0
        end
    elseif vehicle:getMotorLoadPercentage() > cough.motorLoad and vehicle.isServer and effect.value > 0
        and math.random() < RMS_Utils.getChancePerFrameFromMeanTime(dt, effect.value) and cough.status == "IDLE" then
        local cruiseState = vehicle:getCruiseControlState()
        if cruiseState ~= 0 then
            cough.cruiseState = cruiseState
            vehicle:setCruiseControlState(0, true)
        end
        cough.status = "CHOKING"
        RMS_EffectSyncEvent.send(vehicle, "ENGINE_HESITATION_CHANCE", "CHOKING", 0)
    end
end

RMS_Breakdowns.EffectApplicators.ENGINE_HESITATION_CHANCE = {
    -- a cough goes on through a recalculation of the breakdowns
    apply = function(vehicle, effect)
        local spec = vehicle.spec_RealisticMechanicalSystems
        local previous, cough = spec.engineCough, effect.extraData
        if previous ~= nil and previous ~= cough then
            cough.status, cough.timer, cough.cruiseState = previous.status, previous.timer, previous.cruiseState
            cough.misfireCycles = previous.misfireCycles
        end
        spec.engineCough = cough
        startFrameUpdate(vehicle, "ENGINE_HESITATION_CHANCE", updateEngineCough)
    end,

    remove = function(vehicle)
        vehicle.spec_RealisticMechanicalSystems.engineCough = nil
        stopFrameUpdate(vehicle, "ENGINE_HESITATION_CHANCE")
        if vehicle.isClient then
            for _, sample in ipairs(vehicle.spec_motorized.motorSamples) do
                RMS_SoundManager.setSampleVolumeOffset(sample, 0)
            end
        end
    end
}

local function getIsBraking(vehicle, axisForward, isManualDirection)
    if isManualDirection then
        return axisForward < -0.01
    end
    return vehicle.movingDirection ~= 0 and axisForward ~= 0 and math.sign(vehicle.movingDirection) ~= math.sign(axisForward)
end

-- automatic direction: the pedal the machine rolls on accelerates
local function limitThrottle(vehicle, axisForward, limit, isManualDirection)
    if math.abs(axisForward) <= limit then
        return axisForward
    elseif isManualDirection then
        return math.min(axisForward, limit)
    elseif math.sign(vehicle.movingDirection) == math.sign(axisForward) then
        return math.sign(axisForward) * limit
    end
    return axisForward
end

local function playBrakeSqueal(vehicle, spec, effect, axisForward)
    local speed = vehicle:getLastSpeed()
    local previousSpeed = effect.extraData.previousSpeed or speed
    effect.extraData.previousSpeed = speed
    if previousSpeed >= BRAKE_SOUND_SPEED_THRESHOLD and speed < BRAKE_SOUND_SPEED_THRESHOLD and math.abs(axisForward) > 0.999
        and RMS_Drivetrain.getIsRoadVehicleCategory(vehicle) and math.random() < math.abs(effect.value) then
        RMS_SoundManager.playSample(spec.samples.brakes)
        RMS_EffectSyncEvent.send(vehicle, "BRAKE_FORCE_MODIFIER", "SOUND", 0)
    end
end

local function seizeWheel(vehicle, intensity)
    local wheel = getSeizedWheel(vehicle)
    if wheel == nil then
        return
    end
    local brakeForce = vehicle:getBrakeForce()
    if brakeForce <= 0 then
        brakeForce = vehicle.spec_motorized.motor:getBrakeForce()
    end
    local physics = wheel.physics
    physics.torque = 0
    setWheelShapeProps(wheel.node, physics.wheelShape, 0, math.max(math.max(brakeForce, 100) * intensity, 100), physics.steeringAngle,
        math.max(physics.rotationDamping * (3 + 4 * intensity), 5))
end

---Applies the pedal effects and the wheel seizure to the physics step
function RMS_Breakdowns.updateVehiclePhysics(vehicle, superFunc, axisForward, axisSide, doHandbrake, dt)
    local spec = vehicle.spec_RealisticMechanicalSystems
    if spec == nil then
        return superFunc(vehicle, axisForward, axisSide, doHandbrake, dt)
    end

    local effects = spec.activeEffects
    local isManualDirection = vehicle:getDirectionChangeMode() == VehicleMotor.DIRECTION_CHANGE_MODE_MANUAL
    local hesitation = effects.ENGINE_HESITATION_CHANCE
    if hesitation ~= nil and hesitation.extraData ~= nil and hesitation.extraData.status == "CHOKING" then
        axisForward = axisForward * math.max(1 - hesitation.extraData.amplitude, 0)
    end
    if effects.ENGINE_LIMP_EFFECT ~= nil then
        axisForward = limitThrottle(vehicle, axisForward, math.max(1 + effects.ENGINE_LIMP_EFFECT.value, 0.2), isManualDirection)
    end

    local brake = effects.BRAKE_FORCE_MODIFIER
    if brake ~= nil and brake.value ~= 0 and getIsBraking(vehicle, axisForward, isManualDirection) then
        if vehicle.isServer and brake.extraData ~= nil then
            playBrakeSqueal(vehicle, spec, brake, axisForward)
        end
        axisForward = axisForward * math.max(1 + brake.value, 0.01)
    end

    local result = superFunc(vehicle, axisForward, axisSide, doHandbrake, dt)

    local seizure = effects.WHEEL_SEIZURE_EFFECT
    if seizure ~= nil and seizure.value > 0 and vehicle.isAddedToPhysics then
        seizeWheel(vehicle, math.min(seizure.value, 1))
    end
    return result
end

-- the game reads the torque curve again on updateMotorProperties
local function refreshTorqueCurve(vehicle) vehicle:updateMotorProperties() end

RMS_Breakdowns.EffectApplicators.ENGINE_TORQUE_MODIFIER = { apply = refreshTorqueCurve, remove = refreshTorqueCurve }
RMS_Breakdowns.EffectApplicators.ENGINE_THERMAL_TORQUE_LIMIT = RMS_Breakdowns.EffectApplicators.ENGINE_TORQUE_MODIFIER

RMS_Breakdowns.EffectApplicators.DRIVE_LOSS_EFFECT = {

}

RMS_Breakdowns.EffectApplicators.TRAILER_BRAKE_FAILURE = {
}

AttacherJoints.onBrake = Utils.overwrittenFunction(AttacherJoints.onBrake, function(self, superFunc, brakePedal)
    local spec = self.spec_RealisticMechanicalSystems
    local effect = spec ~= nil and spec.activeEffects.TRAILER_BRAKE_FAILURE or nil
    if effect ~= nil then
        brakePedal = brakePedal * math.max(1 + effect.value, 0)
    end
    superFunc(self, brakePedal)
end)

VehicleMotor.getMaxClutchTorque = Utils.overwrittenFunction(VehicleMotor.getMaxClutchTorque, function(self, superFunc)
    local spec_rms = self.vehicle ~= nil and self.vehicle.spec_RealisticMechanicalSystems or nil
    local effect = spec_rms ~= nil and spec_rms.activeEffects ~= nil and spec_rms.activeEffects.DRIVE_LOSS_EFFECT or nil
    if effect == nil then
        return superFunc(self)
    end
    return superFunc(self) * math.max(1 - effect.value, 0)
end)

RMS_Breakdowns.EffectApplicators.FOUR_WD_ENGAGE_FAILURE = {

}
RMS_Breakdowns.EffectApplicators.FOUR_WD_STUCK_ENGAGED = {

}
RMS_Breakdowns.EffectApplicators.DIFF_LOCK_ENGAGE_FAILURE = {

}
RMS_Breakdowns.EffectApplicators.DIFF_LOCK_STUCK_ENGAGED = {

}

function RMS_Breakdowns.updateParticulateFilterOverload(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    local fuelState = spec.fuelState
    local config = RMS_Config.EXHAUST.PARTICULATE_FILTER
    local breakdownId = "PARTICULATE_FILTER_SOOT_OVERLOAD"
    local breakdown = spec.activeBreakdowns[breakdownId]
    local isBlocked = spec.activeEffects.PARTICULATE_FILTER_BLOCKED ~= nil

    if (fuelState.isParticulateFilterOverloaded and breakdown == nil) or (fuelState.isParticulateFilterBlocked and not isBlocked) then
        fuelState.particulateFilterLevel = 0
    end
    fuelState.isParticulateFilterBlocked = isBlocked

    local level = fuelState.particulateFilterLevel
    local stage = level >= config.SERVICE_LEVEL and 2 or level >= config.DERATE_LEVEL and 1 or 0
    if stage == 0 then
        if breakdown ~= nil then
            vehicle:removeBreakdown(breakdownId)
        end
    elseif breakdown == nil then
        vehicle:addBreakdown(breakdownId, { stage = stage, isVisible = true })
    elseif breakdown.stage ~= stage then
        breakdown.stage = stage
        vehicle:recalculateAndApplyEffects()
        RealisticMechanicalSystems.raiseRMSDirty(vehicle, RealisticMechanicalSystems.SYNC_GROUP.BREAKDOWNS)
    end
    fuelState.isParticulateFilterOverloaded = stage > 0
end

function RMS_Breakdowns.updateEngineDerate(vehicle, dt)
    local spec = vehicle.spec_RealisticMechanicalSystems
    local config = RMS_Config.EXHAUST

    local inducement = nil
    if spec.activeEffects.SCR_DOSING_FAILURE ~= nil then
        inducement = config.SCR_INDUCEMENT.DOSING
    elseif spec.activeEffects.NOX_MONITORING_FAILURE ~= nil then
        inducement = config.SCR_INDUCEMENT.MONITORING
    end

    if inducement == nil then
        spec.scrInducementHours = 0
    elseif vehicle:getIsMotorStarted() then
        spec.scrInducementHours = spec.scrInducementHours + dt / (60 * 60 * 1000)
    end

    local targetTorque, rpmCap = 1, nil
    if inducement ~= nil and spec.scrInducementHours >= inducement.SEVERE_HOURS then
        targetTorque = config.SCR_INDUCEMENT.SEVERE_TORQUE
        rpmCap = vehicle:getMotor().peakMotorPowerRotSpeed * 30 / math.pi * config.SCR_INDUCEMENT.SEVERE_RPM
    elseif inducement ~= nil and spec.scrInducementHours >= inducement.LOW_HOURS then
        targetTorque = config.SCR_INDUCEMENT.LOW_TORQUE
    end

    local torqueStep = config.SCR_INDUCEMENT.TORQUE_STEP_PER_MINUTE * dt / (60 * 1000)
    local torqueCap = spec.engineTorqueCap
    spec.engineTorqueCap = targetTorque < torqueCap and math.max(torqueCap - torqueStep, targetTorque) or targetTorque

    if spec.fuelState.particulateFilterLevel >= config.PARTICULATE_FILTER.DERATE_LEVEL then
        rpmCap = math.min(rpmCap or math.huge, config.PARTICULATE_FILTER.DERATE_RPM)
    end
    spec.engineRpmCap = rpmCap
    spec.isEngineDerated = rpmCap ~= nil or spec.engineTorqueCap < 1
end

VehicleMotor.getTorqueCurveValue = Utils.overwrittenFunction(VehicleMotor.getTorqueCurveValue, function(self, superFunc, rpm)
    local torque = superFunc(self, rpm)
    local vehicle = self.vehicle
    if vehicle ~= nil then
        local spec_rms = vehicle.spec_RealisticMechanicalSystems
        if spec_rms ~= nil and spec_rms.activeEffects ~= nil then
            local effect = spec_rms.activeEffects.ENGINE_TORQUE_MODIFIER
            if effect ~= nil and effect.value ~= nil then
                torque = torque * math.max((1 + effect.value), 0.2)
            end
            torque = torque * RMS_Thermal.getEngineTorqueFactor(vehicle) * spec_rms.engineTorqueCap
                * RMS_EngineRemap.getTorqueFactor(vehicle)
            local rpmCap = spec_rms.engineRpmCap
            if rpmCap ~= nil and rpm > rpmCap - 50 then
                torque = torque * math.clamp((rpmCap - rpm) / 50, 0, 1)
            end
        end
    end
    return torque
end)
                  
RMS_Breakdowns.EffectApplicators.FUEL_CONSUMPTION_MODIFIER = {
}

---Burns the fuel a breakdown wastes, a remapped engine at stock load
function RMS_Breakdowns.updateConsumersOverwrite(vehicle, superFunc, dt, accInput)
    local spec = vehicle.spec_RealisticMechanicalSystems
    local waste = spec ~= nil and spec.activeEffects ~= nil and spec.activeEffects.FUEL_CONSUMPTION_MODIFIER or nil
    if spec == nil or spec.activeEffects == nil or waste == nil and not RMS_EngineRemap.getIsRemapped(vehicle) then
        return superFunc(vehicle, dt, accInput)
    end

    local motorized = vehicle.spec_motorized
    local factor = 1 + (waste ~= nil and waste.value or 0)
    local load = motorized.smoothedLoadPercentage
    local usages = {}
    motorized.smoothedLoadPercentage = RMS_EngineRemap.getStockLoad(vehicle, load)
    for index, consumer in pairs(motorized.consumers) do
        if consumer.permanentConsumption then
            usages[index] = consumer.usage
            consumer.usage = consumer.usage * factor
        end
    end
    superFunc(vehicle, dt, accInput)
    for index, usage in pairs(usages) do
        motorized.consumers[index].usage = usage
    end
    motorized.smoothedLoadPercentage = load
end

RMS_Breakdowns.EffectApplicators.TRANSMISSION_SLIP_EFFECT = {
    apply = function(vehicle, effect)
        local motor = vehicle:getMotor()
        local spec = vehicle.spec_RealisticMechanicalSystems
        if motor ~= nil then
            spec.stockClutchSlippingTime = spec.stockClutchSlippingTime or motor.clutchSlippingTime
            motor.clutchSlippingTime = spec.stockClutchSlippingTime * (1 + effect.value) ^ 3
        end
    end,

    remove = function(vehicle)
        local motor = vehicle:getMotor()
        local spec = vehicle.spec_RealisticMechanicalSystems
        if motor ~= nil and spec.stockClutchSlippingTime ~= nil then
            motor.clutchSlippingTime = spec.stockClutchSlippingTime
            spec.stockClutchSlippingTime = nil
        end
    end
}

RMS_Breakdowns.EffectApplicators.CVT_SLIP_EFFECT = {
    remove = function(vehicle)
        local motor = vehicle:getMotor()
        if motor ~= nil then
            motor:setExternalTorqueVirtualMultiplicator(1)
        end
    end
}

RMS_Breakdowns.EffectApplicators.CVT_MAX_RATIO_MODIFIER = {
}

local TRANSMISSION_SLIP_CONVERGENCE_PER_SECOND = 0.9
local TRANSMISSION_SLIP_RESUME_GAP_SECONDS = 0.25

-- seconds since the last ratio of the slip, none after a pause
local function getSlipSeconds(spec, lastTimeKey)
    local now = g_currentMission.time
    local seconds = math.max((now - (spec[lastTimeKey] or now)) / 1000, 0)
    spec[lastTimeKey] = now
    return seconds > TRANSMISSION_SLIP_RESUME_GAP_SECONDS and 0 or seconds
end

-- a worn clutch lets the engine run ahead while it accelerates at speed
local function getClutchSlip(motor, spec, slip, minRatio)
    spec.slipAccumulatedMod = spec.slipAccumulatedMod or 0
    local seconds = getSlipSeconds(spec, "slipLastUpdateMs")
    local speedFactor = math.min(motor.vehicle:getLastSpeed() / (motor:getMaximumForwardSpeed() * 3.6), 1)
    if slip <= 0 or minRatio == 0 or speedFactor <= 0.5 then
        return 0
    end
    local acceleration = math.min(math.max(0, motor.motorRotAccelerationSmoothed / motor.motorRotationAccelerationLimit * 5), 1)
    local step = TRANSMISSION_SLIP_CONVERGENCE_PER_SECOND * seconds * (1 - math.min(speedFactor, 0.9))
    if spec.slipAccumulatedMod < acceleration then
        spec.slipAccumulatedMod = math.min(spec.slipAccumulatedMod + step, 1)
    else
        spec.slipAccumulatedMod = math.max(spec.slipAccumulatedMod - step, 0)
    end
    return slip * spec.slipAccumulatedMod
end

-- a slipping variator holds the ratio the engine reached at low speed
local function getVariatorSlip(motor, spec, slip, minRatio, maxRatio)
    local vehicle = motor.vehicle
    local seconds = getSlipSeconds(spec, "cvtSlipLastUpdateMs")
    local lastAcceleration = spec.cvtSlipLastAccelerationFactor or 0
    local speedFactor = math.min(vehicle:getLastSpeed() / (motor:getMaximumForwardSpeed() * 3.6 / 2), 1)
    if slip <= 0 or minRatio == 0 or maxRatio == 0 or speedFactor >= 0.5 then
        return minRatio, false
    end
    local decayPerSecond = 0.01 / slip * math.max(speedFactor, 0.1) / (vehicle:getMotorLoadPercentage() + 0.2)
        / (vehicle:getTotalMass() / vehicle:getTotalMass(true))
    local acceleration = math.clamp(motor.motorRotAccelerationSmoothed / math.max(motor.motorRotationAccelerationLimit, 0.000001), 0, 1)
    if acceleration < lastAcceleration then
        acceleration = math.clamp(lastAcceleration - decayPerSecond * seconds, 0, 1)
    end
    spec.cvtSlipLastAccelerationFactor = acceleration
    return math.clamp(motor.gearRatio * acceleration, math.min(minRatio, minRatio * 10), math.max(minRatio, minRatio * 10)),
        acceleration >= 0.98 and speedFactor < 0.8
end

-- a ratio a hundred times longer leaves the wheels no drive at all
VehicleMotor.getMinMaxGearRatio = Utils.overwrittenFunction(VehicleMotor.getMinMaxGearRatio, function(self, superFunc)
    local minRatio, maxRatio = superFunc(self)
    local spec = self.vehicle ~= nil and self.vehicle.spec_RealisticMechanicalSystems or nil
    if spec == nil or spec.activeEffects == nil then
        return minRatio, maxRatio
    end
    local effects = spec.activeEffects

    local clutchSlip = effects.TRANSMISSION_SLIP_EFFECT
    if clutchSlip ~= nil then
        if clutchSlip.value >= 1 then
            return minRatio * 100, maxRatio * 100
        end
        local slip = getClutchSlip(self, spec, clutchSlip.value, minRatio)
        minRatio, maxRatio = minRatio * (1 + slip), maxRatio * (1 + slip)
    end

    local isVariatorSlipping = false
    local variatorSlip = effects.CVT_SLIP_EFFECT
    if variatorSlip ~= nil and self.minForwardGearRatio ~= nil then
        if variatorSlip.value >= 1 then
            return minRatio * 100, maxRatio * 100
        end
        minRatio, isVariatorSlipping = getVariatorSlip(self, spec, variatorSlip.value, minRatio, maxRatio)
    end

    local longRatio = effects.CVT_MAX_RATIO_MODIFIER
    local speedFactor = math.min(self.vehicle:getLastSpeed() / (self:getMaximumForwardSpeed() * 3.6 / 2), 1)
    if longRatio ~= nil and self.minForwardGearRatio ~= nil and not isVariatorSlipping and speedFactor > 0.5 then
        minRatio = minRatio + minRatio * longRatio.value * speedFactor
    end

    local pressureDrop = effects.CVT_PRESSURE_DROP_CHANCE
    if pressureDrop ~= nil and pressureDrop.extraData ~= nil and pressureDrop.extraData.status == "PROGRESS"
        and (pressureDrop.extraData.timer or 0) > 0 then
        minRatio = minRatio * 1.5
    end
    return minRatio, maxRatio
end)

-- extraData={status, timer in ms, duration in ms, backup}
local function updatePowershiftEngagement(vehicle, dt)
    local spec = vehicle.spec_RealisticMechanicalSystems
    local effect = spec.activeEffects.POWERSHIFT_ENGAGEMENT_LAG_AND_HARSH_EFFECT
    if not vehicle:getIsMotorStarted() or effect == nil or effect.value <= 0 or effect.extraData.status == "IDLE" then
        return
    end
    local engagement, motor = effect.extraData, vehicle:getMotor()
    engagement.timer = engagement.timer + dt
    if engagement.status == "DELAYED" and engagement.timer > effect.value * 1000 then
        engagement.timer, engagement.status = 0, "PASSED"
        if engagement.backup then
            engagement.backup = motor.minGearRatio
            motor.minGearRatio = 999.9
        end
        motor:applyTargetGear()
        RMS_SoundManager.playSample(spec.samples.powershiftClunk)
        RMS_EffectSyncEvent.send(vehicle, "POWERSHIFT_ENGAGEMENT_LAG_AND_HARSH_EFFECT", "CLUNK", 0)
    elseif engagement.status == "PASSED" and engagement.timer > engagement.duration then
        if engagement.backup then
            motor.minGearRatio = engagement.backup
        end
        engagement.status = "IDLE"
    end
end

RMS_Breakdowns.EffectApplicators.POWERSHIFT_ENGAGEMENT_LAG_AND_HARSH_EFFECT = {
    apply = function(vehicle) startFrameUpdate(vehicle, "POWERSHIFT_ENGAGEMENT_LAG_AND_HARSH_EFFECT", updatePowershiftEngagement) end,
    remove = function(vehicle) stopFrameUpdate(vehicle, "POWERSHIFT_ENGAGEMENT_LAG_AND_HARSH_EFFECT") end
}

-- a powershift past engaging stays in its gear
VehicleMotor.applyTargetGear = Utils.overwrittenFunction(VehicleMotor.applyTargetGear, function(self, superFunc)
    local spec = self.vehicle ~= nil and self.vehicle.spec_RealisticMechanicalSystems or nil
    local effect = spec ~= nil and spec.activeEffects ~= nil and spec.activeEffects.POWERSHIFT_ENGAGEMENT_LAG_AND_HARSH_EFFECT or nil
    if effect == nil or effect.extraData.status ~= "IDLE" then
        return superFunc(self)
    elseif effect.value >= 1 then
        self.targetGear = self.previousGear
        return superFunc(self)
    end
    effect.extraData.status, effect.extraData.timer = "DELAYED", 0
end)


local function isHydraulicHoldDriftBlockedByFold(implement)
    if implement == nil then
        return false
    end

    if implement.getIsUnfolded ~= nil then
        local isUnfolded = implement:getIsUnfolded()
        if isUnfolded ~= nil then
            return not isUnfolded
        end
    end

    if implement.getFoldAnimTime ~= nil then
        local foldAnimTime = implement:getFoldAnimTime()
        if foldAnimTime ~= nil then
            return foldAnimTime < 0.99
        end
    end

    return false
end

local function setHydraulicHoldDriftSpeedLimitBypass(implement, enabled)
    if implement == nil or implement.doCheckSpeedLimit == nil then
        return
    end

    if implement.rmsHoldDriftOrigDoCheckSpeedLimit == nil then
        implement.rmsHoldDriftOrigDoCheckSpeedLimit = implement.doCheckSpeedLimit
        implement.doCheckSpeedLimit = function(obj, ...)
            if obj.rmsHoldDriftBypassSpeedLimit == true then
                local attacherVehicle = obj.getAttacherVehicle ~= nil and obj:getAttacherVehicle() or nil
                if attacherVehicle ~= nil then
                    return false
                end
                obj.rmsHoldDriftBypassSpeedLimit = false
            end

            local origFunc = obj.rmsHoldDriftOrigDoCheckSpeedLimit
            if origFunc ~= nil then
                return origFunc(obj, ...)
            end

            return false
        end
    end

    implement.rmsHoldDriftBypassSpeedLimit = enabled == true
end

local function restoreHydraulicHoldDriftSpeedLimitBypass(implement)
    if implement == nil then
        return
    end

    if implement.rmsHoldDriftOrigDoCheckSpeedLimit ~= nil then
        implement.doCheckSpeedLimit = implement.rmsHoldDriftOrigDoCheckSpeedLimit
        implement.rmsHoldDriftOrigDoCheckSpeedLimit = nil
    end

    implement.rmsHoldDriftBypassSpeedLimit = nil
end

local function getHydraulicMassRatio(vehicle, mass)
    return math.clamp(mass / math.max(vehicle:getTotalMass(true), 0.01), 0, 1)
end

function RMS_Breakdowns.getBreakdownCarryingEffect(spec, effectId)
    for breakdownId, breakdown in pairs(spec.activeBreakdowns or {}) do
        local definition = RMS_Breakdowns.BreakdownRegistry[breakdownId]
        local stageData = definition ~= nil and breakdown.isActive ~= false and definition.stages[breakdown.stage] or nil
        if stageData ~= nil then
            for _, effectData in ipairs(RMS_Utils.getBranchItems(stageData.effects, breakdown)) do
                if effectData.id == effectId then
                    return breakdown
                end
            end
        end
    end
    return nil
end

local function setHydraulicTarget(vehicle, targetIndex, flag)
    local currentIndex = 0
    local visited = {}

    local function scanVehicle(childVehicle)
        if childVehicle == nil or visited[childVehicle] then
            return
        end
        visited[childVehicle] = true

        local attacherSpec = childVehicle.spec_attacherJoints
        if attacherSpec ~= nil then
            for _, implementData in pairs(attacherSpec.attachedImplements or {}) do
                local jointDesc = attacherSpec.attacherJoints[implementData.jointDescIndex]
                if jointDesc ~= nil then
                    jointDesc[flag] = false
                    if RMS_Utils.getIsHydraulicLiftJoint(jointDesc) then
                        currentIndex = currentIndex + 1
                        jointDesc[flag] = currentIndex == targetIndex
                    end
                end
            end
        end

        if childVehicle.spec_cylindered ~= nil then
            for _, tool in ipairs(childVehicle.spec_cylindered.movingTools) do
                tool[flag] = false
                if RMS_Utils.getIsHydraulicMovingTool(tool)
                    and (tool.rotSpeed ~= nil or tool.transSpeed ~= nil or tool.animSpeed ~= nil) then
                    currentIndex = currentIndex + 1
                    tool[flag] = currentIndex == targetIndex
                end
            end
        end

        local children = childVehicle.getChildVehicles ~= nil and childVehicle:getChildVehicles() or {}
        for _, nestedVehicle in pairs(children) do
            scanVehicle(nestedVehicle)
        end
    end

    scanVehicle(vehicle)

    return currentIndex
end

RMS_Breakdowns.EffectApplicators.HYDRAULIC_SPEED_MODIFIER = {

}

RMS_Breakdowns.EffectApplicators.LOADER_CONTROL_EFFECT = {

}

-- suspensionParameters[axis]={spring, damping} of the cab node
local function setCabDamping(vehicle, factor)
    for _, suspension in ipairs(vehicle.spec_suspensions.suspensionNodes) do
        if suspension.isRotational and not suspension.useCharacterTorso then
            local parameters = suspension.suspensionParameters
            suspension.rmsDamping = suspension.rmsDamping or { parameters[1][2], parameters[2][2], parameters[3][2] }
            for axis, damping in ipairs(suspension.rmsDamping) do
                parameters[axis][2] = damping * factor
            end
        end
    end
end

RMS_Breakdowns.EffectApplicators.CAB_DAMPING_MODIFIER = {
    apply = function(vehicle, effect) setCabDamping(vehicle, 1 + effect.value) end,
    remove = function(vehicle) setCabDamping(vehicle, 1) end
}

local function createHydraulicTargetApplicator(effectName, flag)
    return {
        getEffectName = function()
            return effectName
        end,

        apply = function(vehicle, effectData, handler)
            local activeFunc = function(v, dt)
                local spec = v.spec_RealisticMechanicalSystems
                local breakdown = spec ~= nil and spec.activeEffects ~= nil and spec.activeEffects[effectName] ~= nil
                    and RMS_Breakdowns.getBreakdownCarryingEffect(spec, effectName) or nil
                if breakdown == nil then
                    return
                end
                local childVehicleHash = v:getChildVehicleHash()

                if breakdown.targetChildVehicleHash ~= childVehicleHash or breakdown.effectTargetIndex == 0 then
                    local targetCount = setHydraulicTarget(v, breakdown.effectTargetIndex, flag)
                    local previousTargetIndex = breakdown.effectTargetIndex
                    if breakdown.effectTargetIndex == 0 and targetCount > 0 and v.isServer then
                        breakdown.effectTargetIndex = math.random(1, targetCount)
                        setHydraulicTarget(v, breakdown.effectTargetIndex, flag)
                    end
                    breakdown.targetChildVehicleHash = childVehicleHash

                    if previousTargetIndex ~= breakdown.effectTargetIndex then
                        RealisticMechanicalSystems.raiseRMSDirty(v, RealisticMechanicalSystems.SYNC_GROUP.BREAKDOWNS)
                    end
                end
            end

            startFrameUpdate(vehicle, effectName, activeFunc)
            activeFunc(vehicle, 0)
        end,

        remove = function(vehicle, handler)
            setHydraulicTarget(vehicle, 0, flag)
            stopFrameUpdate(vehicle, handler.getEffectName())
        end
    }
end

RMS_Breakdowns.EffectApplicators.HYDRAULIC_FUNCTION_ERRATIC_EFFECT = createHydraulicTargetApplicator("HYDRAULIC_FUNCTION_ERRATIC_EFFECT", "rmsHydraulicErraticTarget")
RMS_Breakdowns.EffectApplicators.HYDRAULIC_FUNCTION_BLOCKED_EFFECT = createHydraulicTargetApplicator("HYDRAULIC_FUNCTION_BLOCKED_EFFECT", "rmsHydraulicBlockedTarget")
RMS_Breakdowns.EffectApplicators.LIFT_CONTROL_FAILURE = {

}

RMS_Breakdowns.EffectApplicators.HYDRAULIC_HOLD_DRIFT_EFFECT = {
    getEffectName = function()
        return "HYDRAULIC_HOLD_DRIFT_EFFECT"
    end,

    apply = function(vehicle, effectData, handler)
        local activeFunc = function(v, dt) 
            if not v.isServer then
                return
            end

            local rootSpec = v.spec_RealisticMechanicalSystems
            local activeEffect = rootSpec ~= nil and rootSpec.activeEffects ~= nil
                and rootSpec.activeEffects.HYDRAULIC_HOLD_DRIFT_EFFECT or nil
            local breakdown = rootSpec ~= nil and RMS_Breakdowns.getBreakdownCarryingEffect(rootSpec, "HYDRAULIC_HOLD_DRIFT_EFFECT") or nil
            local targetCount = 0
            local attacherSpec = v.spec_attacherJoints
            if attacherSpec == nil or activeEffect == nil or breakdown == nil then
                return
            end

            for _, implementData in pairs(attacherSpec.attachedImplements or {}) do
                local jointDesc = attacherSpec.attacherJoints[implementData.jointDescIndex]
                if jointDesc ~= nil and RMS_Utils.getIsHydraulicLiftJoint(jointDesc) then
                    targetCount = targetCount + 1
                end
            end

            if targetCount > 0 and (breakdown.effectTargetIndex <= 0 or breakdown.effectTargetIndex > targetCount) then
                breakdown.effectTargetIndex = math.random(1, targetCount)
                RealisticMechanicalSystems.raiseRMSDirty(v, RealisticMechanicalSystems.SYNC_GROUP.BREAKDOWNS)
            end

            if v.spec_attacherJoints and v.spec_attacherJoints.attachedImplements and next(v.spec_attacherJoints.attachedImplements) ~= nil then
                local currentTargetIndex = 0
                for _, implementData in pairs(v.spec_attacherJoints.attachedImplements) do
                    if implementData.object ~= nil then
                        local implement = implementData.object
                        local jointDescIndex = implementData.jointDescIndex
                        local jointDesc = v.spec_attacherJoints.attacherJoints[jointDescIndex]
                        if jointDesc ~= nil and RMS_Utils.getIsHydraulicLiftJoint(jointDesc) then
                            currentTargetIndex = currentTargetIndex + 1
                            local isTarget = currentTargetIndex == breakdown.effectTargetIndex
                            local liftedMass = (rootSpec.hydraulicLiftMassByJoint or {})[jointDesc] or 0
                            local loadMassRatio = getHydraulicMassRatio(v, liftedMass)
                            local canDriftUnderLoad = isTarget and loadMassRatio > 0
                            local driftBlockedByFold = isHydraulicHoldDriftBlockedByFold(implement)
                            local isLowered = implement:getIsLowered()
                            if jointDesc.rmsHoldDriftForced == true then
                                if not canDriftUnderLoad or driftBlockedByFold or (isLowered and not jointDesc.isMoving) or jointDesc.moveDown == false then
                                    jointDesc.rmsHoldDriftForced = false
                                end
                            end

                            if canDriftUnderLoad and not driftBlockedByFold and not isLowered and not jointDesc.isMoving and jointDesc.moveDown == false then
                                jointDesc.rmsHoldDriftForced = true
                                v:setJointMoveDown(jointDescIndex, true, false)
                            end

                            local bypassWorkSpeedLimit = isTarget and jointDesc.rmsHoldDriftForced == true and jointDesc.moveDown == true and jointDesc.isMoving == true and not driftBlockedByFold
                            if bypassWorkSpeedLimit then
                                setHydraulicHoldDriftSpeedLimitBypass(implement, true)
                            else
                                restoreHydraulicHoldDriftSpeedLimitBypass(implement)
                            end
                        end
                    end
                end
            end
        end
        startFrameUpdate(vehicle, handler.getEffectName(), activeFunc)
    end,

    remove = function(vehicle, handler)
        if vehicle.spec_attacherJoints ~= nil and vehicle.spec_attacherJoints.attachedImplements ~= nil then
            for _, implementData in pairs(vehicle.spec_attacherJoints.attachedImplements) do
                if implementData.object ~= nil then
                    restoreHydraulicHoldDriftSpeedLimitBypass(implementData.object)
                end

                local jointDesc = vehicle.spec_attacherJoints.attacherJoints[implementData.jointDescIndex]
                if jointDesc ~= nil then
                    jointDesc.rmsHoldDriftForced = false
                end
            end
        end

        stopFrameUpdate(vehicle, handler.getEffectName())
    end
}

---Slows the attacher joint movement by the hydraulic effects
function RMS_Breakdowns.applyHydraulicDamageToAttacher(self, superFunc, dt, ...)
    local rootVehicle = self:getRootVehicle()
    local spec = self.spec_attacherJoints
    local rootSpec = rootVehicle.spec_RealisticMechanicalSystems
    local activeEffects = rootSpec ~= nil and rootSpec.activeEffects or nil
    local hydraulicEffect = activeEffects ~= nil and activeEffects.HYDRAULIC_SPEED_MODIFIER or nil
    local hydraulicHoldEffect = activeEffects ~= nil and activeEffects.HYDRAULIC_HOLD_DRIFT_EFFECT or nil
    local erraticEffect = activeEffects ~= nil and activeEffects.HYDRAULIC_FUNCTION_ERRATIC_EFFECT or nil
    local isFunctionBlocked = activeEffects ~= nil and activeEffects.HYDRAULIC_FUNCTION_BLOCKED_EFFECT ~= nil
    local isLiftControlFailed = activeEffects ~= nil and activeEffects.LIFT_CONTROL_FAILURE ~= nil
    local hydraulicModifier = RMS_Fluids.getHydraulicSpeedModifier(rootVehicle, (hydraulicEffect and hydraulicEffect.value) or 0)
    local erraticModifier = (erraticEffect and erraticEffect.value) or 0
    local hydraulicHoldEffectValue = hydraulicHoldEffect ~= nil and (tonumber(hydraulicHoldEffect.value) or 0) or 0

    if hydraulicHoldEffectValue > 0 and (tonumber(rootSpec ~= nil and rootSpec.liftedMass or 0) or 0) <= 0 then
        hydraulicHoldEffectValue = 0
    end

    if hydraulicModifier == 0 and hydraulicHoldEffectValue == 0 and erraticModifier == 0 and not isFunctionBlocked and not isLiftControlFailed then
        return superFunc(self, dt, ...)
    end

    local raisePerformance = math.max(0, 1.0 + hydraulicModifier)
    local erraticPerformance = math.max(0.05, 1.0 + erraticModifier)
    local erraticPhaseActive = math.floor(g_currentMission.time / RMS_Config.CORE_UPDATE_DELAY) % 2 == 0
    local originalMoveTimes = {}

    for _, implement in pairs(spec.attachedImplements) do
        if implement.object ~= nil then
            local jointDesc = spec.attacherJoints[implement.jointDescIndex]

            if not RMS_Utils.getIsHydraulicLiftJoint(jointDesc) then
                jointDesc = nil
            end

            if jointDesc ~= nil then
                originalMoveTimes[jointDesc] = {
                    moveDefaultTime = jointDesc.moveDefaultTime,
                    moveTime = jointDesc.moveTime
                }
            end

            if jointDesc ~= nil and jointDesc.rmsHoldDriftForced == true and jointDesc.moveDown == false then
                jointDesc.rmsHoldDriftForced = false
            end

            if jointDesc ~= nil then
                local performance = 1
                local shouldAdjust = false

                if jointDesc.moveDown == true and jointDesc.rmsHoldDriftForced == true and hydraulicHoldEffectValue > 0 then
                    local liftedMass = rootSpec ~= nil
                        and (rootSpec.hydraulicLiftMassByJoint or {})[jointDesc] or 0
                    local loadMassRatio = getHydraulicMassRatio(rootVehicle, liftedMass)
                    if loadMassRatio > 0 then
                        performance = math.max(hydraulicHoldEffectValue * loadMassRatio, 0.01)
                        shouldAdjust = true
                    end
                else
                    if jointDesc.moveDown == false and hydraulicModifier ~= 0 then
                        performance = performance * raisePerformance
                        shouldAdjust = true
                    end
                    if jointDesc.rmsHydraulicErraticTarget == true and erraticModifier ~= 0 then
                        performance = performance * (erraticPhaseActive and erraticPerformance or 0)
                        shouldAdjust = true
                    end
                end

                if isLiftControlFailed or isFunctionBlocked and jointDesc.rmsHydraulicBlockedTarget == true then
                    performance = 0
                    shouldAdjust = true
                end

                if shouldAdjust then
                    local originalTimes = originalMoveTimes[jointDesc]
                    jointDesc.moveDefaultTime = performance > 0
                        and originalTimes.moveDefaultTime / performance or math.huge
                    if originalTimes.moveTime ~= nil then
                        jointDesc.moveTime = performance > 0
                            and originalTimes.moveTime / performance or math.huge
                    end
                end
            end
        end
    end

    local result = superFunc(self, dt, ...)

    for _, implement in pairs(spec.attachedImplements) do
        if implement.object ~= nil then
            local jointDesc = spec.attacherJoints[implement.jointDescIndex]
            
            if jointDesc ~= nil and originalMoveTimes[jointDesc] ~= nil then
                jointDesc.moveDefaultTime = originalMoveTimes[jointDesc].moveDefaultTime
                jointDesc.moveTime = originalMoveTimes[jointDesc].moveTime
            end
        end
    end

    return result
end


---Slows the cylindered part movement by the hydraulic effects
function RMS_Breakdowns.applyHydraulicDamageToCylindered(self, superFunc, dt, ...)
    local rootVehicle = self:getRootVehicle()
    local spec = self.spec_cylindered

    local hydraulicEffect = rootVehicle.spec_RealisticMechanicalSystems and rootVehicle.spec_RealisticMechanicalSystems.activeEffects.HYDRAULIC_SPEED_MODIFIER
    local erraticEffect = rootVehicle.spec_RealisticMechanicalSystems and rootVehicle.spec_RealisticMechanicalSystems.activeEffects.HYDRAULIC_FUNCTION_ERRATIC_EFFECT
    local isFunctionBlocked = rootVehicle.spec_RealisticMechanicalSystems ~= nil
        and rootVehicle.spec_RealisticMechanicalSystems.activeEffects.HYDRAULIC_FUNCTION_BLOCKED_EFFECT ~= nil
    local loaderEffect = rootVehicle.spec_RealisticMechanicalSystems and rootVehicle.spec_RealisticMechanicalSystems.activeEffects.LOADER_CONTROL_EFFECT
    local hydraulicModifier = RMS_Fluids.getHydraulicSpeedModifier(rootVehicle, (hydraulicEffect and hydraulicEffect.value) or 0)
    local erraticModifier = (erraticEffect and erraticEffect.value) or 0
    if hydraulicModifier == 0 and erraticModifier == 0 and not isFunctionBlocked and loaderEffect == nil then
        return superFunc(self, dt, ...)
    end

    local performance = math.max(0, 1.0 + hydraulicModifier)
    local erraticPerformance = math.max(0.05, 1.0 + erraticModifier)
    local erraticPhaseActive = math.floor(g_currentMission.time / RMS_Config.CORE_UPDATE_DELAY) % 2 == 0
    local originalSpeeds = {}

    for _, tool in ipairs(spec.movingTools) do
        if RMS_Utils.getIsHydraulicMovingTool(tool) then
            local original = {
                rotSpeed = tool.rotSpeed,
                transSpeed = tool.transSpeed,
                animSpeed = tool.animSpeed
            }
            originalSpeeds[tool] = original

            local toolPerformance = performance
            if tool.rmsHydraulicErraticTarget == true then
                toolPerformance = toolPerformance * (erraticPhaseActive and erraticPerformance or 0)
            end
            if isFunctionBlocked and tool.rmsHydraulicBlockedTarget == true then
                toolPerformance = 0
            end
            if loaderEffect ~= nil and RMS_Utils.getIsLoaderMovingTool(tool) then
                toolPerformance = toolPerformance * math.max(0, 1 + loaderEffect.value)
            end

            if original.rotSpeed ~= nil then
                tool.rotSpeed = original.rotSpeed * toolPerformance
            end
            if original.transSpeed ~= nil then
                tool.transSpeed = original.transSpeed * toolPerformance
            end
            if original.animSpeed ~= nil then
                tool.animSpeed = original.animSpeed * toolPerformance
            end
        end
    end

    local result = superFunc(self, dt, ...)

    for _, tool in ipairs(spec.movingTools) do
        if originalSpeeds[tool] ~= nil then
            if tool.rotSpeed ~= nil then
                tool.rotSpeed = originalSpeeds[tool].rotSpeed
            end
            if tool.transSpeed ~= nil then
                tool.transSpeed = originalSpeeds[tool].transSpeed
            end
            if tool.animSpeed ~= nil then
                tool.animSpeed = originalSpeeds[tool].animSpeed
            end
        end
    end

    return result
end

---Slows the attacher joint control movement by the hydraulic effects
function RMS_Breakdowns.applyHydraulicDamageToAttacherJointControl(self, superFunc, dt, ...)
    local rootVehicle = self:getRootVehicle()
    local effect = rootVehicle.spec_RealisticMechanicalSystems
        and rootVehicle.spec_RealisticMechanicalSystems.activeEffects.HYDRAULIC_SPEED_MODIFIER
    local modifier = RMS_Fluids.getHydraulicSpeedModifier(rootVehicle, effect ~= nil and (tonumber(effect.value) or 0) or 0)
    local spec = self.spec_attacherJointControl
    local jointDesc = spec ~= nil and spec.jointDesc or nil
    local originalMoveTime = jointDesc ~= nil and tonumber(jointDesc.moveTime) or nil

    if modifier == 0 or originalMoveTime == nil then
        return superFunc(self, dt, ...)
    end

    local performance = math.max(0, 1 + modifier)
    jointDesc.moveTime = performance > 0 and originalMoveTime / performance or math.huge
    local result = superFunc(self, dt, ...)
    jointDesc.moveTime = originalMoveTime

    return result
end

---Slows the hydraulic hammer by the hydraulic effects
function RMS_Breakdowns.applyHydraulicDamageToHammer(self, superFunc, actorId, x, y, z, distance, nx, ny, nz, subShapeIndex, shapeId, isLast)
    local rootVehicle = self:getRootVehicle()
    local effect = rootVehicle.spec_RealisticMechanicalSystems
        and rootVehicle.spec_RealisticMechanicalSystems.activeEffects.HYDRAULIC_SPEED_MODIFIER
    local modifier = RMS_Fluids.getHydraulicSpeedModifier(rootVehicle, effect ~= nil and (tonumber(effect.value) or 0) or 0)
    if modifier == 0 then
        return superFunc(self, actorId, x, y, z, distance, nx, ny, nz, subShapeIndex, shapeId, isLast)
    end

    local performance = math.max(0, 1 + modifier)
    if performance <= 0 then
        return false
    end

    local workNode = self.spec_hydraulicHammer.workNode
    local originalMin = workNode.hitIntervalMin
    local originalMax = workNode.hitIntervalMax
    workNode.hitIntervalMin = math.ceil(originalMin / performance)
    workNode.hitIntervalMax = math.ceil(originalMax / performance)
    local result = superFunc(self, actorId, x, y, z, distance, nx, ny, nz, subShapeIndex, shapeId, isLast)
    workNode.hitIntervalMin = originalMin
    workNode.hitIntervalMax = originalMax

    return result
end


do
    if not RMS_Breakdowns._hydraulicSpeedHooksInstalled then
        local hydraulicSpeedHookDefs = {
            { objectName = "AttacherJoints", field = "onUpdateTick", wrapperName = "applyHydraulicDamageToAttacher" },
            { objectName = "Cylindered", field = "onUpdate", wrapperName = "applyHydraulicDamageToCylindered" },
            { objectName = "AttacherJointControl", field = "onUpdate", wrapperName = "applyHydraulicDamageToAttacherJointControl" },
            { objectName = "HydraulicHammer", field = "hydraulicHammerRaycastCallback", wrapperName = "applyHydraulicDamageToHammer" }
        }

        for _, def in ipairs(hydraulicSpeedHookDefs) do
            local targetObject = _G[def.objectName]
            local wrapperFunc = RMS_Breakdowns[def.wrapperName]
            if targetObject ~= nil and targetObject[def.field] ~= nil and wrapperFunc ~= nil then
                targetObject[def.field] = Utils.overwrittenFunction(targetObject[def.field], wrapperFunc)
                log_dbg("HYDRAULIC hook installed:", string.format("%s.%s", def.objectName, def.field))
            else
                log_dbg("HYDRAULIC hook skipped:", string.format("%s.%s", def.objectName, def.field))
            end
        end

        RMS_Breakdowns._hydraulicSpeedHooksInstalled = true
    end
end

RMS_Breakdowns.EffectApplicators.MAX_SPEED_MODIFIER = {

}

---Lowers the vehicle speed limit by the maximum speed modifier
function RMS_Breakdowns.getSpeedLimitOverwrite(vehicle, superFunc, onlyIfWorking)
    local speedLimit, doCheckSpeedLimit = superFunc(vehicle, onlyIfWorking)

    local spec_rms = vehicle.spec_RealisticMechanicalSystems
    if spec_rms == nil or spec_rms.activeEffects == nil then
        return speedLimit, doCheckSpeedLimit
    end

    local throughput = spec_rms.activeEffects.HARVEST_THROUGHPUT_LIMIT
    if throughput ~= nil and speedLimit ~= nil and speedLimit < math.huge and vehicle:getIsTurnedOn() then
        speedLimit = speedLimit * (1 - math.clamp(tonumber(throughput.value) or 0, 0, 0.9))
    end

    local effect = spec_rms.activeEffects.MAX_SPEED_MODIFIER
    if effect == nil or effect.value == nil then
        return speedLimit, doCheckSpeedLimit
    end

    local reduction = math.clamp(tonumber(effect.value) or 0, 0, 0.99)
    if reduction <= 0 then
        return speedLimit, doCheckSpeedLimit
    end

    local motor = vehicle:getMotor()

    if speedLimit == nil or speedLimit >= math.huge then
        local baseMaxMps = nil
        if motor ~= nil then
            baseMaxMps = tonumber(motor.maxForwardSpeedOrigin)
                or tonumber(motor.maxForwardSpeed)
                or (motor.getMaximumForwardSpeed ~= nil and tonumber(motor:getMaximumForwardSpeed()) or nil)
        end
        if baseMaxMps ~= nil then
            speedLimit = baseMaxMps * 3.6
        end
    end

    if speedLimit ~= nil and speedLimit < math.huge then
        speedLimit = speedLimit - speedLimit * reduction
    end

    return speedLimit or math.huge, doCheckSpeedLimit
end

-- {spec field, value at rest, lowest value}, rest + effect value
local SPEC_VALUES = {
    CONDITION_WEAR_MODIFIER = { "extraConditionWear", 0 },
    SERVICE_WEAR_MODIFIER = { "extraServiceWear", 0 },
    ENGINE_HEAT_MODIFIER = { "extraEngineHeat", 0 },
    TRANSMISSION_HEAT_MODIFIER = { "extraTransmissionHeat", 0 },
    HYDRAULIC_HEAT_MODIFIER = { "extraHydraulicHeat", 0 },
    ELECTRICAL_LEAKAGE_EFFECT = { "circuitLeakageFactor", 0 },
    ELECTRICAL_CONTACT_RESISTANCE_EFFECT = { "circuitResistanceFactor", 0 },
    COOLANT_LEAK_RATE = { "coolantLeakRate", 0, 0 },
    TRANSMISSION_OIL_LEAK_RATE = { "transmissionOilLeakRate", 0, 0 },
    HYDRAULIC_FLUID_LEAK_RATE = { "hydraulicFluidLeakRate", 0, 0 },
    THERMOSTAT_HEALTH_MODIFIER = { "thermostatHealth", 1, 0.1 },
    TRANSMISSION_THERMOSTAT_HEALTH_MODIFIER = { "transmissionThermostatHealth", 1, 0.1 },
    RADIATOR_HEALTH_MODIFIER = { "radiatorHealth", 1, 0.1 },
    FAN_CLUTCH_MODIFIER = { "fanClutchHealth", 1, 0.1 },
    BATTERY_HEALTH_MODIFIER = { "batteryHealth", 1, 0.0001 },
    ALTERNATOR_HEALTH_MODIFIER = { "alternatorHealth", 1, 0.0001 },
    STARTER_HEALTH_MODIFIER = { "starterHealth", 1, 0 }
}

for effectId, field in pairs(SPEC_VALUES) do
    local name, rest, lowest = field[1], field[2], field[3] or -math.huge
    RMS_Breakdowns.EffectApplicators[effectId] = {
        apply = function(vehicle, effect) vehicle.spec_RealisticMechanicalSystems[name] = math.max(rest + effect.value, lowest) end,
        remove = function(vehicle) vehicle.spec_RealisticMechanicalSystems[name] = rest end
    }
end

local function setParkBrakeDrag(vehicle, drag)
    vehicle.spec_RealisticMechanicalSystems.parkBrakeDrag = drag
    RMS_Drivetrain.refreshParkBrakePedal(vehicle)
end

RMS_Breakdowns.EffectApplicators.PARK_BRAKE_DRAG_EFFECT = {
    apply = function(vehicle, effect) setParkBrakeDrag(vehicle, effect.value) end,
    remove = function(vehicle) setParkBrakeDrag(vehicle, 0) end
}

RMS_Breakdowns.EffectApplicators.THERMOSTAT_STUCK_EFFECT = {
    apply = function(vehicle, effect) vehicle.spec_RealisticMechanicalSystems.thermostatStuckedPosition = effect.extraData.stuckPosition end,
    remove = function(vehicle) vehicle.spec_RealisticMechanicalSystems.thermostatStuckedPosition = nil end
}

-- the transmission thermostat sticks where it stands when it fails
RMS_Breakdowns.EffectApplicators.TRANSMISSION_THERMOSTAT_STUCK_EFFECT = {
    apply = function(vehicle)
        local spec = vehicle.spec_RealisticMechanicalSystems
        if (spec.transmissionThermostatStuckedPosition or -1) < 0 then
            spec.transmissionThermostatStuckedPosition = spec.transmissionThermostatState
        end
    end,
    remove = function(vehicle) vehicle.spec_RealisticMechanicalSystems.transmissionThermostatStuckedPosition = nil end
}

local function updateIdleHuntingMotor(motor, effectData, dt, rpmBackup, shouldHunt, allowRestore, resetWhenInactive)
    if shouldHunt then
        if rpmBackup == nil or rpmBackup == 0 then
            rpmBackup = motor.minRpm
        end
        effectData.extraData.timer = (effectData.extraData.timer or 0) + dt
        motor.minRpm = rpmBackup * (1 + effectData.value * math.sin(2 * math.pi * effectData.extraData.timer / effectData.extraData.period))
    else
        local restored = false
        if allowRestore and rpmBackup ~= nil and rpmBackup ~= 0 and rpmBackup ~= motor.minRpm then
            motor.minRpm = rpmBackup
            restored = true
        end
        if resetWhenInactive or restored then
            effectData.extraData.timer = 0
        end
    end

    return rpmBackup
end

local function updateIdleHunting(vehicle, dt)
    local spec = vehicle.spec_RealisticMechanicalSystems
    spec.idleHuntingRpmBackup = updateIdleHuntingMotor(vehicle:getMotor(), spec.activeEffects.IDLE_HUNTING_EFFECT, dt,
        spec.idleHuntingRpmBackup, vehicle:getIsMotorStarted() and vehicle:getLastSpeed() < 0.01, true, false)
end

RMS_Breakdowns.EffectApplicators.IDLE_HUNTING_EFFECT = {
    -- the swing of the idle goes on through a recalculation
    apply = function(vehicle, effect)
        local spec = vehicle.spec_RealisticMechanicalSystems
        spec.idleHuntingRpmBackup = spec.idleHuntingRpmBackup or vehicle:getMotor().minRpm
        if spec.idleHunting ~= nil and spec.idleHunting ~= effect.extraData then
            effect.extraData.timer = spec.idleHunting.timer
        end
        spec.idleHunting = effect.extraData
        startFrameUpdate(vehicle, "IDLE_HUNTING_EFFECT", updateIdleHunting)
    end,

    remove = function(vehicle)
        local spec = vehicle.spec_RealisticMechanicalSystems
        if spec.idleHuntingRpmBackup ~= nil then
            vehicle:getMotor().minRpm = spec.idleHuntingRpmBackup
        end
        spec.idleHuntingRpmBackup, spec.idleHunting = nil, nil
        stopFrameUpdate(vehicle, "IDLE_HUNTING_EFFECT")
    end
}

RMS_Breakdowns.EffectApplicators.GLOW_PLUG_COLD_IDLE_EFFECT = {
    getEffectName = function()
        return "GLOW_PLUG_COLD_IDLE_EFFECT"
    end,

    apply = function(vehicle, effectData, handler)
        local effectName = handler.getEffectName()
        local motor = vehicle:getMotor()
        local spec = vehicle.spec_RealisticMechanicalSystems
        if spec.glowPlugColdIdleRpmBackup == nil then
            spec.glowPlugColdIdleRpmBackup = motor.minRpm
        end
        local activeFunc = function(v, dt)
            local spec = v.spec_RealisticMechanicalSystems
            local effect = spec ~= nil and spec.activeEffects ~= nil and spec.activeEffects[effectName] or nil
            if effect == nil or effect.extraData == nil then
                return
            end

            local coldThreshold = RMS_Config.CORE.ENGINE_FACTOR_DATA.COLD_MOTOR_TEMP_THRESHOLD
            local engineTemperature = RealisticMechanicalSystems.sanitizeNumber(spec.rawEngineTemperature or spec.engineTemperature, coldThreshold, -80, 160)
            local otherIdleHuntingActive = spec.activeEffects.IDLE_HUNTING_EFFECT ~= nil
            local shouldHunt = spec.preheatColdStartFaultSeverity >= 2
                and engineTemperature < coldThreshold
                and v:getIsMotorStarted()
                and v:getLastSpeed() < 0.01
                and not otherIdleHuntingActive

            if otherIdleHuntingActive and spec.glowPlugColdIdleRpmBackup ~= nil then
                spec.idleHuntingRpmBackup = spec.glowPlugColdIdleRpmBackup
            end

            spec.glowPlugColdIdleRpmBackup = updateIdleHuntingMotor(
                motor,
                effect,
                dt,
                spec.glowPlugColdIdleRpmBackup,
                shouldHunt,
                not otherIdleHuntingActive,
                true
            )

        end

        startFrameUpdate(vehicle, effectName, activeFunc)
    end,

    remove = function(vehicle, handler)
        local spec = vehicle.spec_RealisticMechanicalSystems
        local motor = vehicle:getMotor()
        if spec ~= nil and spec.glowPlugColdIdleRpmBackup ~= nil then
            if spec.activeEffects.IDLE_HUNTING_EFFECT ~= nil then
                spec.idleHuntingRpmBackup = spec.glowPlugColdIdleRpmBackup
            end
            motor.minRpm = spec.glowPlugColdIdleRpmBackup
        end
        spec.glowPlugColdIdleRpmBackup = nil
        stopFrameUpdate(vehicle, handler.getEffectName())
    end
}

local function rmsStopAndResetNoiseSample(sample)
    if sample == nil then return end
    RMS_SoundManager.setSamplePlaying(sample, false, 0, 0)
    RMS_SoundManager.setSampleVolumeOffset(sample, 0)
    RMS_SoundManager.setSamplePitchOffset(sample, 0)
    if sample.rmsOriginalLoops ~= nil then
        sample.loops = sample.rmsOriginalLoops
    end
    if sample.rmsOriginalVolumeScale ~= nil then
        sample.volumeScale = sample.rmsOriginalVolumeScale
    end
end

local function rmsUpdateNoiseGate(spec, effectName, targetGate, dt)
    spec.__rmsNoiseGates = spec.__rmsNoiseGates or {}
    local previousGate = math.clamp(tonumber(spec.__rmsNoiseGates[effectName]) or 0, 0, 1)
    local attackMs = 220
    local releaseMs = 520
    local responseMs = targetGate > previousGate and attackMs or releaseMs
    local alpha = math.min((tonumber(dt) or 0) / math.max(responseMs, 1), 1)
    local gate = previousGate + (targetGate - previousGate) * alpha
    gate = math.clamp(gate, 0, 1)
    spec.__rmsNoiseGates[effectName] = gate
    return gate
end

local KNOCK_RECORDING_RPM = { engineKnocking = 670, pistonSlap = 580, valveTrainNoise = 710, injectorKnock = 1620, highPressurePump = 800 }
local SPEED_PITCH = {
    wheelHubBearingNoise = { 15.0, 0.12, 1.10, 0.03 },
    wheelSeizureGrind = { 12.0, 0.06, 1.05, 0.05 },
    trackClatter = { 15.0, 0.08, 1.05, 0.02 },
    trackRoller = { 15.0, 0.12, 1.10, 0.03 },
    gearWhineNoise = { 15.0, 0.12, 1.10, 0.03 },
    gearboxBearingNoise = { 15.0, 0.12, 1.10, 0.03 },
    hydrostaticWhine = { 15.0, 0.12, 1.10, 0.03 },
    electricMotorBearing = { 15.0, 0.12, 1.10, 0.03 },
    parkBrakeDrag = { 12.0, 0.06, 1.05, 0.05 }
}
local FIXED_PITCH = { steeringOrbitrol = true, coolantSteam = true, gasLeak = true }
local CLUNK_MEAN_SECONDS = 1.2

local function getIsSteeringMoving(vehicle, spec_rms, effectName, dt)
    local lock = vehicle.rotatedTime >= 0 and vehicle.maxRotTime or -vehicle.minRotTime
    local position = lock > 0 and vehicle.rotatedTime / lock or 0
    spec_rms.__rmsNoiseSteerPositions = spec_rms.__rmsNoiseSteerPositions or {}
    local lastPosition = spec_rms.__rmsNoiseSteerPositions[effectName] or position
    spec_rms.__rmsNoiseSteerPositions[effectName] = position
    return math.abs(position - lastPosition) / (dt * 0.001) > RMS_Config.CORE.CHASSIS_FACTOR_DATA.STEER_LOAD_RATE_DEADZONE
end

local function getIsLoaderMoving(vehicle, spec_rms)
    spec_rms.__rmsNoiseLoaderPositions = spec_rms.__rmsNoiseLoaderPositions or {}
    local positions = spec_rms.__rmsNoiseLoaderPositions
    local isMoving = false
    for _, tool in ipairs(vehicle.spec_cylindered.movingTools) do
        if RMS_Utils.getIsLoaderMovingTool(tool) then
            local position = tool.curRot[tool.rotationAxis] + tool.curTrans[tool.translationAxis]
            if positions[tool] ~= nil and position ~= positions[tool] then
                isMoving = true
            end
            positions[tool] = position
        end
    end
    return isMoving
end

local CLUNK_LOAD_MS = 500
local BUMP_STROKE_MS = 500

local function getIsFrontDriveTakenUp(vehicle, spec_rms, effectName, dt)
    spec_rms.__rmsNoiseDriveStates = spec_rms.__rmsNoiseDriveStates or {}
    local state = spec_rms.__rmsNoiseDriveStates[effectName] or { direction = 0, loadedFor = 0 }
    spec_rms.__rmsNoiseDriveStates[effectName] = state
    local direction = vehicle:getLastSpeed() > 0.5 and vehicle.movingDirection or 0
    if direction ~= 0 and direction ~= state.direction and RMS_Drivetrain.getIsFrontAxleDriven(vehicle) then
        state.loadedFor = CLUNK_LOAD_MS
    end
    state.direction = direction
    state.loadedFor = math.max(state.loadedFor - dt, 0)
    return state.loadedFor > 0
end

local function getIsCabBumping(vehicle, spec_rms, effectName, dt)
    spec_rms.__rmsNoiseBumpStates = spec_rms.__rmsNoiseBumpStates or {}
    local state = spec_rms.__rmsNoiseBumpStates[effectName] or { lengths = {}, loadedFor = 0 }
    spec_rms.__rmsNoiseBumpStates[effectName] = state
    for index, wheel in ipairs(vehicle.spec_wheels.wheels) do
        local length = wheel.physics.netInfo.suspensionLength
        local last = state.lengths[index] or length
        state.lengths[index] = length
        if math.abs(length - last) / wheel.physics.suspTravel > dt / BUMP_STROKE_MS then
            state.loadedFor = CLUNK_LOAD_MS
        end
    end
    state.loadedFor = math.max(state.loadedFor - dt, 0)
    return state.loadedFor > 0
end

local function createClunkEffectApplicator(effectName, sampleName, getIsMoving)
    return {
        getEffectName = function()
            return effectName
        end,

        apply = function(vehicle, effectData, handler)
            startFrameUpdate(vehicle, effectName, function(v, dt)
                local spec_rms = v.spec_RealisticMechanicalSystems
                local effect = spec_rms.activeEffects[effectName]
                local sample = spec_rms.samples[sampleName]
                if effect == nil or sample == nil or not v:getIsMotorStarted() then
                    return
                end
                if getIsMoving(v, spec_rms, effectName, dt)
                    and math.random() < RMS_Utils.getChancePerFrameFromMeanTime(dt, CLUNK_MEAN_SECONDS / effect.value / 60) then
                    sample.rmsOriginalVolumeScale = sample.rmsOriginalVolumeScale or sample.volumeScale
                    sample.volumeScale = sample.rmsOriginalVolumeScale * effect.value
                    RMS_SoundManager.playSample(sample)
                end
            end)
        end,

        remove = function(vehicle, handler)
            stopFrameUpdate(vehicle, handler.getEffectName())
        end
    }
end

local function createEngineNoiseEffectApplicator(effectName, sampleName, gateMode)
    return {
        getEffectName = function()
            return effectName
        end,

        apply = function(vehicle, effectData, handler)
            log_dbg(string.format("Applying %s effect", effectName))
            local activeFunc = function(v, dt)
                local spec_rms = v.spec_RealisticMechanicalSystems
                if spec_rms == nil or spec_rms.samples == nil then return end
                local motor = v:getMotor()
                if motor == nil then return end

                local sample = spec_rms.samples[sampleName]
                if sample == nil then return end

                local currentEffect = spec_rms.activeEffects and spec_rms.activeEffects[effectName]
                local baseVolumeScale = math.clamp(tonumber(currentEffect and currentEffect.value) or tonumber(effectData.value) or 1, 0, 2)

                if not v:getIsMotorStarted() then
                    rmsStopAndResetNoiseSample(sample)
                    if spec_rms.__rmsNoiseGates ~= nil then
                        spec_rms.__rmsNoiseGates[effectName] = nil
                    end
                    return
                end

                local minRpm = tonumber(motor.minRpm) or 800
                local maxRpm = math.max(tonumber(motor.maxRpm) or (minRpm + 1), minRpm + 1)
                local lastRpm = (motor.getLastModulatedMotorRpm ~= nil and tonumber(motor:getLastModulatedMotorRpm())) or tonumber(motor.lastMotorRpm) or minRpm
                local rpmN = math.clamp((lastRpm - minRpm) / (maxRpm - minRpm), 0, 1)
                local loadN = math.clamp(tonumber(v:getMotorLoadPercentage()) or 0, 0, 1)
                local boostN = math.clamp(tonumber(motor.lastTurboScale) or 0, 0, 1)
                local hotN = math.clamp(((tonumber(spec_rms.engineTemperature) or 0) - 70) / 40, 0, 1)
                local speedMps = v:getLastSpeed() / 3.6
                local ptoData = nil

                if gateMode == "pto" then
                    ptoData = RMS_Utils.getConnectedPtoData(v)
                    local ptoRpm = math.max(tonumber(ptoData.rpm) or 0, 0)
                    local ptoMotorRpm = ptoRpm * motor:getPtoMotorRpmRatio()
                    rpmN = math.clamp((ptoMotorRpm - minRpm) / (maxRpm - minRpm), 0, 1)
                end

                local dynamicIntensity =
                    (0.30 + 0.70 * rpmN)
                    * (0.65 + 0.35 * loadN)
                    * (0.70 + 0.30 * hotN)
                dynamicIntensity = math.clamp(dynamicIntensity, 0, 1.6)

                local gate = 1
                if gateMode == "boost" then
                    local boostThreshold = 0.02
                    local targetGate = math.clamp((boostN - boostThreshold) / (1 - boostThreshold), 0, 1)
                    gate = rmsUpdateNoiseGate(spec_rms, effectName, targetGate, dt)
                    baseVolumeScale = baseVolumeScale * gate
                elseif gateMode == "speed" then
                    local speedThresholdMps = 0.20
                    local fullSpeedMps = 2.00
                    local targetGate = math.clamp((speedMps - speedThresholdMps) / (fullSpeedMps - speedThresholdMps), 0, 1)
                    gate = rmsUpdateNoiseGate(spec_rms, effectName, targetGate, dt)
                    baseVolumeScale = baseVolumeScale * gate
                elseif gateMode == "pto" then
                    local targetGate = ptoData ~= nil and ptoData.isActive and (tonumber(ptoData.rpm) or 0) > 0 and 1 or 0
                    gate = rmsUpdateNoiseGate(spec_rms, effectName, targetGate, dt)
                    baseVolumeScale = baseVolumeScale * gate
                elseif gateMode == "harvest" then
                    gate = rmsUpdateNoiseGate(spec_rms, effectName, v.getIsTurnedOn ~= nil and v:getIsTurnedOn() and 1 or 0, dt)
                    baseVolumeScale = baseVolumeScale * gate
                elseif gateMode == "steer" then
                    local isSteering = getIsSteeringMoving(v, spec_rms, effectName, dt)
                    gate = rmsUpdateNoiseGate(spec_rms, effectName, isSteering and 1 or 0, dt)
                    baseVolumeScale = baseVolumeScale * gate
                elseif gateMode == "hot" then
                    gate = rmsUpdateNoiseGate(spec_rms, effectName, hotN, dt)
                    baseVolumeScale = baseVolumeScale * gate
                end

                if baseVolumeScale <= 0.02 then
                    if gateMode ~= nil and gate > 0.001 then
                        baseVolumeScale = 0.02
                    else
                        rmsStopAndResetNoiseSample(sample)
                        if spec_rms.__rmsNoiseGates ~= nil then
                            spec_rms.__rmsNoiseGates[effectName] = nil
                        end
                        return
                    end
                end

                if sample.rmsOriginalLoops == nil then
                    sample.rmsOriginalLoops = sample.loops
                end
                if sample.rmsOriginalVolumeScale == nil then
                    sample.rmsOriginalVolumeScale = sample.volumeScale
                end
                sample.loops = 0
                sample.volumeScale = sample.rmsOriginalVolumeScale * baseVolumeScale

                RMS_SoundManager.setSamplePlaying(sample, true)

                RMS_SoundManager.setSampleVolumeOffset(sample, 0)
                local pitchOffset
                local speedPitch = SPEED_PITCH[sampleName]
                if KNOCK_RECORDING_RPM[sampleName] ~= nil then
                    pitchOffset = lastRpm / KNOCK_RECORDING_RPM[sampleName] - 1
                elseif sampleName == "turboWhistle" then
                    local boostThreshold = 0.02
                    local boostGate = math.clamp((boostN - boostThreshold) / (1 - boostThreshold), 0, 1)
                    pitchOffset = (0.20 * boostGate + 0.16 * (rpmN ^ 1.20) * boostGate + 0.03 * loadN * boostGate) * gate
                elseif speedPitch ~= nil then
                    local speedN = math.clamp(speedMps / speedPitch[1], 0, 1)
                    pitchOffset = (speedPitch[2] * (speedN ^ speedPitch[3]) + speedPitch[4] * loadN * speedN) * gate
                elseif FIXED_PITCH[sampleName] then
                    pitchOffset = 0
                else
                    pitchOffset = 0.24 * (rpmN ^ 1.35) + 0.04 * dynamicIntensity * rpmN
                end
                RMS_SoundManager.setSamplePitchOffset(sample, pitchOffset)
            end

            startFrameUpdate(vehicle, effectName, activeFunc)
        end,

        remove = function(vehicle, handler)
            log_dbg(string.format("Removing %s effect", effectName))
            local spec_rms = vehicle.spec_RealisticMechanicalSystems
            if spec_rms ~= nil and spec_rms.samples ~= nil then
                rmsStopAndResetNoiseSample(spec_rms.samples[sampleName])
                if spec_rms.__rmsNoiseGates ~= nil then
                    spec_rms.__rmsNoiseGates[effectName] = nil
                end
            end
            stopFrameUpdate(vehicle, handler.getEffectName())
        end
    }
end

RMS_Breakdowns.EffectApplicators.ENGINE_KNOCKING_NOISE_EFFECT = createEngineNoiseEffectApplicator("ENGINE_KNOCKING_NOISE_EFFECT", "engineKnocking", nil)
RMS_Breakdowns.EffectApplicators.VALVE_TRAIN_NOISE_EFFECT = createEngineNoiseEffectApplicator("VALVE_TRAIN_NOISE_EFFECT", "valveTrainNoise", nil)
RMS_Breakdowns.EffectApplicators.TURBO_WHISTLE_NOISE_EFFECT = createEngineNoiseEffectApplicator("TURBO_WHISTLE_NOISE_EFFECT", "turboWhistle", "boost")
RMS_Breakdowns.EffectApplicators.FAN_CLUTCH_NOISE_EFFECT = createEngineNoiseEffectApplicator("FAN_CLUTCH_NOISE_EFFECT", "fanNoice", nil)
RMS_Breakdowns.EffectApplicators.FAN_BLADE_NOISE_EFFECT = createEngineNoiseEffectApplicator("FAN_BLADE_NOISE_EFFECT", "fanBladeImbalance", nil)
RMS_Breakdowns.EffectApplicators.TRACK_CLATTER_NOISE_EFFECT = createEngineNoiseEffectApplicator("TRACK_CLATTER_NOISE_EFFECT", "trackClatter", "speed")
RMS_Breakdowns.EffectApplicators.WHEEL_HUB_BEARING_NOISE_EFFECT = createEngineNoiseEffectApplicator("WHEEL_HUB_BEARING_NOISE_EFFECT", "wheelHubBearingNoise", "speed")
RMS_Breakdowns.EffectApplicators.WHEEL_SEIZURE_GRIND_NOISE_EFFECT = createEngineNoiseEffectApplicator("WHEEL_SEIZURE_GRIND_NOISE_EFFECT", "wheelSeizureGrind", "speed")
RMS_Breakdowns.EffectApplicators.PTO_BEARING_NOISE_EFFECT = createEngineNoiseEffectApplicator("PTO_BEARING_NOISE_EFFECT", "ptoBearingNoise", "pto")
RMS_Breakdowns.EffectApplicators.GEAR_WHINE_NOISE_EFFECT = createEngineNoiseEffectApplicator("GEAR_WHINE_NOISE_EFFECT", "gearWhineNoise", "speed")
RMS_Breakdowns.EffectApplicators.GEARBOX_BEARING_NOISE_EFFECT = createEngineNoiseEffectApplicator("GEARBOX_BEARING_NOISE_EFFECT", "gearboxBearingNoise", "speed")
RMS_Breakdowns.EffectApplicators.PISTON_SLAP_NOISE_EFFECT = createEngineNoiseEffectApplicator("PISTON_SLAP_NOISE_EFFECT", "pistonSlap", nil)
RMS_Breakdowns.EffectApplicators.INJECTOR_KNOCK_NOISE_EFFECT = createEngineNoiseEffectApplicator("INJECTOR_KNOCK_NOISE_EFFECT", "injectorKnock", nil)
RMS_Breakdowns.EffectApplicators.HIGH_PRESSURE_PUMP_NOISE_EFFECT = createEngineNoiseEffectApplicator("HIGH_PRESSURE_PUMP_NOISE_EFFECT", "highPressurePump", nil)
RMS_Breakdowns.EffectApplicators.BELT_SQUEAL_NOISE_EFFECT = createEngineNoiseEffectApplicator("BELT_SQUEAL_NOISE_EFFECT", "accessoryBelt", nil)
RMS_Breakdowns.EffectApplicators.WATER_PUMP_BEARING_NOISE_EFFECT = createEngineNoiseEffectApplicator("WATER_PUMP_BEARING_NOISE_EFFECT", "waterPumpBearing", nil)
RMS_Breakdowns.EffectApplicators.TRANSMISSION_PUMP_NOISE_EFFECT = createEngineNoiseEffectApplicator("TRANSMISSION_PUMP_NOISE_EFFECT", "transmissionPump", nil)
RMS_Breakdowns.EffectApplicators.HYDROSTATIC_WHINE_NOISE_EFFECT = createEngineNoiseEffectApplicator("HYDROSTATIC_WHINE_NOISE_EFFECT", "hydrostaticWhine", "speed")
RMS_Breakdowns.EffectApplicators.HYDRAULIC_PUMP_NOISE_EFFECT = createEngineNoiseEffectApplicator("HYDRAULIC_PUMP_NOISE_EFFECT", "hydraulicPump", nil)
RMS_Breakdowns.EffectApplicators.COOLANT_STEAM_NOISE_EFFECT = createEngineNoiseEffectApplicator("COOLANT_STEAM_NOISE_EFFECT", "coolantSteam", "hot")
RMS_Breakdowns.EffectApplicators.GAS_LEAK_NOISE_EFFECT = createEngineNoiseEffectApplicator("GAS_LEAK_NOISE_EFFECT", "gasLeak", nil)
RMS_Breakdowns.EffectApplicators.PARK_BRAKE_DRAG_NOISE_EFFECT = createEngineNoiseEffectApplicator("PARK_BRAKE_DRAG_NOISE_EFFECT", "parkBrakeDrag", "speed")
RMS_Breakdowns.EffectApplicators.STEERING_LINKAGE_NOISE_EFFECT = createClunkEffectApplicator("STEERING_LINKAGE_NOISE_EFFECT", "steeringLinkage",
    getIsSteeringMoving)
RMS_Breakdowns.EffectApplicators.STEERING_KNUCKLE_NOISE_EFFECT = createClunkEffectApplicator("STEERING_KNUCKLE_NOISE_EFFECT", "steeringKnuckle",
    getIsSteeringMoving)
RMS_Breakdowns.EffectApplicators.STEERING_ORBITROL_NOISE_EFFECT = createEngineNoiseEffectApplicator("STEERING_ORBITROL_NOISE_EFFECT", "steeringOrbitrol", "steer")
RMS_Breakdowns.EffectApplicators.TRACK_ROLLER_NOISE_EFFECT = createEngineNoiseEffectApplicator("TRACK_ROLLER_NOISE_EFFECT", "trackRoller", "speed")
RMS_Breakdowns.EffectApplicators.LOADER_PINS_NOISE_EFFECT = createClunkEffectApplicator("LOADER_PINS_NOISE_EFFECT", "loaderPins", getIsLoaderMoving)
RMS_Breakdowns.EffectApplicators.FRONT_AXLE_SHAFT_NOISE_EFFECT = createClunkEffectApplicator("FRONT_AXLE_SHAFT_NOISE_EFFECT",
    "frontAxleShaft", getIsFrontDriveTakenUp)
RMS_Breakdowns.EffectApplicators.CAB_DAMPER_NOISE_EFFECT = createClunkEffectApplicator("CAB_DAMPER_NOISE_EFFECT", "cabDamper",
    getIsCabBumping)
RMS_Breakdowns.EffectApplicators.PTO_SPLINES_NOISE_EFFECT = createEngineNoiseEffectApplicator("PTO_SPLINES_NOISE_EFFECT", "ptoSplines", "pto")
RMS_Breakdowns.EffectApplicators.HARVEST_BEARING_NOISE_EFFECT = createEngineNoiseEffectApplicator("HARVEST_BEARING_NOISE_EFFECT",
    "ptoBearingNoise", "harvest")
RMS_Breakdowns.EffectApplicators.ELECTRIC_MOTOR_BEARING_NOISE_EFFECT = createEngineNoiseEffectApplicator("ELECTRIC_MOTOR_BEARING_NOISE_EFFECT",
    "electricMotorBearing", "speed")

RMS_Breakdowns.EffectApplicators.HOSE_BURST_NOISE_EFFECT = {
    getEffectName = function()
        return "HOSE_BURST_NOISE_EFFECT"
    end,

    apply = function(vehicle, effectData, handler, isRestoring)
        local spec = vehicle.spec_RealisticMechanicalSystems
        if not spec.hasHoseBurst then
            spec.hasHoseBurst = true
            -- Do not replay a burst restored from a save or join stream.
            if not isRestoring and vehicle:getIsMotorStarted() then
                RMS_SoundManager.playSample(spec.samples.hoseBurst)
            end
        end
    end,

    remove = function(vehicle, handler)
        vehicle.spec_RealisticMechanicalSystems.hasHoseBurst = nil
    end
}

RMS_Breakdowns.EffectApplicators.PTO_SHAFT_BREAK_NOISE_EFFECT = {
    getEffectName = function()
        return "PTO_SHAFT_BREAK_NOISE_EFFECT"
    end,

    apply = function(vehicle, effectData, handler, isRestoring)
        local spec = vehicle.spec_RealisticMechanicalSystems
        if not spec.hasPtoShaftBroken then
            spec.hasPtoShaftBroken = true
            -- Do not replay a break restored from a save or join stream.
            local ptoData = RMS_Utils.getConnectedPtoData(vehicle)
            if not isRestoring and ptoData.isActive and (tonumber(ptoData.rpm) or 0) > 0 then
                RMS_SoundManager.playSample(spec.samples.ptoShaftBreak)
            end
        end
    end,

    remove = function(vehicle, handler)
        vehicle.spec_RealisticMechanicalSystems.hasPtoShaftBroken = nil
    end
}


RMS_Breakdowns.EffectApplicators.CVT_PRESSURE_DROP_CHANCE = {
    getEffectName = function()
        return "CVT_PRESSURE_DROP_CHANCE"
    end,

    apply = function(vehicle, effectData, handler)
        local motor = vehicle:getMotor()
        if motor == nil then return end
        if motor.minForwardGearRatio == nil then return end
        local effectName = handler.getEffectName()

        local activeFunc = function(v, dt)

            if v:getIsMotorStarted() and v:getLastSpeed() > 1 then
                local effect = v.spec_RealisticMechanicalSystems.activeEffects.CVT_PRESSURE_DROP_CHANCE
                if effect == nil then
                    return
                end
                effect.extraData = effect.extraData or {}
                effect.extraData.status = tostring(effect.extraData.status or "IDLE")
                effect.extraData.timer = tonumber(effect.extraData.timer) or 0
                effect.extraData.duration = tonumber(effect.extraData.duration) or 200

                if v.isServer and effect.extraData.status == 'IDLE' and math.random() < RMS_Utils.getChancePerFrameFromMeanTime(dt, effect.value) then
                    effect.extraData.status = 'DROP'
                    effect.extraData.timer = effect.extraData.duration

                    RMS_EffectSyncEvent.send(v, handler.getEffectName(), "DROP", effect.extraData.timer, 0, 0)
                end
                if effect.extraData.status == 'DROP' and effect.extraData.timer > 0 then
                    effect.extraData.status = 'PROGRESS'
                end
                if effect.extraData.status == 'PROGRESS' then
                    effect.extraData.timer = effect.extraData.timer - dt
                end
                if effect.extraData.timer <= 0 then
                    effect.extraData.timer = 0
                    effect.extraData.status = 'IDLE'
                end
            end
        end
        startFrameUpdate(vehicle, effectName, activeFunc)
    end,

    remove = function(vehicle, handler)
        stopFrameUpdate(vehicle, handler.getEffectName())
    end
}

RMS_Breakdowns.EffectApplicators.ENGINE_STALLS_CHANCE = {
    getEffectName = function() return "ENGINE_STALLS_CHANCE" end,
    apply = function(vehicle, effectData, handler)
        local effectName = handler.getEffectName()
        local activeFunc = function(v, dt)

            if not v.isServer then return end

            if v:getIsMotorStarted() and not v:getIsAIActive() then
                local effect = v.spec_RealisticMechanicalSystems.activeEffects.ENGINE_STALLS_CHANCE
                if effect and effect.value > 0 then
                    if math.random() < RMS_Utils.getChancePerFrameFromMeanTime(dt, effect.value) then
                        if v.stopMotor then
                            v:stopMotor()

                            RMS_EffectSyncEvent.send(v, "ENGINE_STALLS_CHANCE", "STALLED")

                            if v:getIsActiveForInput(true) then
                                g_currentMission:showBlinkingWarning(g_i18n:getText("rms_breakdowns_engine_stalled_message"), 5000) 
                            end
                        end
                    end
                end
            end
        end
        startFrameUpdate(vehicle, effectName, activeFunc)
    end,
    remove = function(vehicle, handler)
        stopFrameUpdate(vehicle, handler.getEffectName())
    end,
}

local function createPtoAutoDisengageApplicator(effectName, side, messageKey)
    return {
        getEffectName = function() return effectName end,
        apply = function(vehicle, effectData, handler)
            local activeFunc = function(v, dt)

                local spec = v.spec_RealisticMechanicalSystems
                local effect = spec ~= nil and spec.activeEffects ~= nil and spec.activeEffects[effectName] or nil
                if effect == nil or (tonumber(effect.value) or 0) <= 0 or (tonumber(spec.year) or 0) < 1990 then
                    return
                end

                effect.extraData = effect.extraData or {}
                if effect.extraData.status == nil then
                    effect.extraData.status = "IDLE"
                end

                if effect.extraData.status == "DISENGAGED" then
                    if v.isServer then
                        RMS_Utils.setConnectedPtoConsumersTurnedOn(v, false, side)
                    end
                    if v:getIsActiveForInput(true) then
                        g_currentMission:showBlinkingWarning(g_i18n:getText(messageKey), 4000)
                    end
                    effect.extraData.status = "IDLE"
                    return
                end

                if not v.isServer then
                    return
                end

                if not RMS_Utils.getConnectedPtoData(v, side).isActive then
                    return
                end

                local meanTimeInMinutes = (tonumber(effect.value) or 0) / 60
                if effect.extraData.status == "IDLE" and math.random() < RMS_Utils.getChancePerFrameFromMeanTime(dt, meanTimeInMinutes) then
                    effect.extraData.status = "DISENGAGED"
                    RMS_EffectSyncEvent.send(v, effectName, "DISENGAGED", 0, 0, 0)
                end
            end

            startFrameUpdate(vehicle, effectName, activeFunc)
        end,
        remove = function(vehicle, handler)
            stopFrameUpdate(vehicle, handler.getEffectName())
        end
    }
end

local function createPtoFailureApplicator(effectName, side)
    return {
        getEffectName = function() return effectName end,
        apply = function(vehicle, effectData, handler)
            local activeFunc = function(v, dt)
                local effect = v.spec_RealisticMechanicalSystems.activeEffects[effectName]
                if v.isServer and effect ~= nil and (tonumber(effect.value) or 0) > 0 then
                    RMS_Utils.setConnectedPtoConsumersTurnedOn(v, false, side)
                end
            end
            startFrameUpdate(vehicle, effectName, activeFunc)
        end,
        remove = function(vehicle, handler)
            stopFrameUpdate(vehicle, handler.getEffectName())
        end
    }
end

RMS_Breakdowns.EffectApplicators.PTO_AUTO_DISENGAGE_CHANCE = createPtoAutoDisengageApplicator("PTO_AUTO_DISENGAGE_CHANCE", "rear",
    "rms_breakdowns_pto_auto_disengage_message")
RMS_Breakdowns.EffectApplicators.PTO_FAILURE = createPtoFailureApplicator("PTO_FAILURE", "rear")
RMS_Breakdowns.EffectApplicators.FRONT_PTO_AUTO_DISENGAGE_CHANCE = createPtoAutoDisengageApplicator("FRONT_PTO_AUTO_DISENGAGE_CHANCE",
    "front", "rms_breakdowns_front_pto_auto_disengage_message")
RMS_Breakdowns.EffectApplicators.FRONT_PTO_FAILURE = createPtoFailureApplicator("FRONT_PTO_FAILURE", "front")

RMS_Breakdowns.EffectApplicators.PTO_STUCK_ENGAGED_CHANCE = {
}

local function setThreshingLoss(vehicle, loss)
    local spec_combine = vehicle.spec_combine
    if spec_combine == nil then
        return
    end
    local spec = vehicle.spec_RealisticMechanicalSystems
    spec.baseThreshingScale = spec.baseThreshingScale or spec_combine.threshingScale
    spec_combine.threshingScale = spec.baseThreshingScale * (1 - loss)
end

RMS_Breakdowns.EffectApplicators.HARVEST_GRAIN_LOSS = {
    apply = function(vehicle, effectData, handler)
        setThreshingLoss(vehicle, math.clamp(tonumber(effectData.value) or 0, 0, RMS_Config.CORE.HARVEST_FACTOR_DATA.MAX_GRAIN_LOSS))
    end,
    remove = function(vehicle, handler)
        setThreshingLoss(vehicle, 0)
    end
}

local function setHarvestPowerDemand(vehicle, extra)
    local spec_powerConsumer = vehicle.spec_powerConsumer
    if spec_powerConsumer == nil then
        return
    end
    local spec = vehicle.spec_RealisticMechanicalSystems
    spec.basePtoPower = spec.basePtoPower or { spec_powerConsumer.neededMinPtoPower, spec_powerConsumer.neededMaxPtoPower }
    spec_powerConsumer.neededMinPtoPower = spec.basePtoPower[1] * (1 + extra)
    spec_powerConsumer.neededMaxPtoPower = spec.basePtoPower[2] * (1 + extra)
end

RMS_Breakdowns.EffectApplicators.HARVEST_POWER_DEMAND = {
    apply = function(vehicle, effectData, handler)
        setHarvestPowerDemand(vehicle, math.max(tonumber(effectData.value) or 0, 0))
    end,
    remove = function(vehicle, handler)
        setHarvestPowerDemand(vehicle, 0)
    end
}

RMS_Breakdowns.EffectApplicators.HARVEST_BLOCKAGE_CHANCE = {
    getEffectName = function() return "HARVEST_BLOCKAGE_CHANCE" end,
    apply = function(vehicle, effectData, handler)
        startFrameUpdate(vehicle, "HARVEST_BLOCKAGE_CHANCE", function(v, dt)
            local effect = v.spec_RealisticMechanicalSystems.activeEffects.HARVEST_BLOCKAGE_CHANCE
            if effect == nil then
                return
            end
            effect.extraData = effect.extraData or {}
            if effect.extraData.status == "BLOCKED" then
                if v.isServer then
                    v:setIsTurnedOn(false)
                end
                if v:getIsActiveForInput(true) then
                    g_currentMission:showBlinkingWarning(g_i18n:getText("rms_breakdowns_harvest_blockage_message"), 4000)
                end
                effect.extraData.status = "IDLE"
                return
            end
            if v.isServer and v:getIsTurnedOn() and v:getLastSpeed() > 0.5
                and math.random() < RMS_Utils.getChancePerFrameFromMeanTime(dt, tonumber(effect.value) or 0) then
                effect.extraData.status = "BLOCKED"
                RMS_EffectSyncEvent.send(v, "HARVEST_BLOCKAGE_CHANCE", "BLOCKED", 0, 0, 0)
            end
        end)
    end,
    remove = function(vehicle, handler)
        stopFrameUpdate(vehicle, "HARVEST_BLOCKAGE_CHANCE")
    end
}

RMS_Breakdowns.EffectApplicators.HARVEST_FAILURE = {
    getEffectName = function() return "HARVEST_FAILURE" end,
    apply = function(vehicle, effectData, handler)
        startFrameUpdate(vehicle, "HARVEST_FAILURE", function(v, dt)
            if v.isServer and v:getIsTurnedOn() then
                v:setIsTurnedOn(false)
            end
        end)
    end,
    remove = function(vehicle, handler)
        stopFrameUpdate(vehicle, "HARVEST_FAILURE")
    end
}

-- a crop without windrow is spread by the chopper, the harvest stops
RMS_Breakdowns.EffectApplicators.CHOPPER_FAILURE = {
    getEffectName = function() return "CHOPPER_FAILURE" end,
    apply = function(vehicle, effectData, handler)
        startFrameUpdate(vehicle, "CHOPPER_FAILURE", function(v, dt)
            local spec_combine = v.spec_combine
            if not v.isServer or spec_combine == nil or spec_combine.isSwathActive or not v:getIsTurnedOn() then
                return
            end
            local fruitDesc = g_fruitTypeManager:getFruitTypeByIndex(spec_combine.lastValidInputFruitType)
            local isSwath = spec_combine.swath.isAvailable and fruitDesc ~= nil and fruitDesc.hasWindrow
            if isSwath then
                v:setIsSwathActive(true)
            else
                v:setIsTurnedOn(false)
            end
            RMS_EffectSyncEvent.send(v, "CHOPPER_FAILURE", isSwath and "SWATH" or "STOPPED", 0, 0, 0)
            if v:getIsActiveForInput(true) then
                g_currentMission:showBlinkingWarning(g_i18n:getText(isSwath and "rms_breakdowns_chopper_failure_message"
                    or "rms_breakdowns_chopper_failure_spread_message"), 4000)
            end
        end)
    end,
    remove = function(vehicle, handler)
        stopFrameUpdate(vehicle, "CHOPPER_FAILURE")
    end
}

RMS_Breakdowns.EffectApplicators.PTO_ENGAGEMENT_BLOCKED_CHANCE = {
    getEffectName = function() return "PTO_ENGAGEMENT_BLOCKED_CHANCE" end,
    apply = function(vehicle, effectData, handler)
    end,
    remove = function(vehicle, handler)
    end
}

---Blocks turning an implement on while the PTO engagement is blocked
function RMS_Breakdowns.getCanBeTurnedOn(vehicle, superFunc)
    local canBeTurnedOn, warning = superFunc(vehicle)
    if not canBeTurnedOn or vehicle.getIsTurnedOn == nil or vehicle:getIsTurnedOn() then
        return canBeTurnedOn, warning
    end

    local rootVehicle = vehicle.rootVehicle
    local spec = rootVehicle ~= nil and rootVehicle.spec_RealisticMechanicalSystems or nil
    if vehicle == rootVehicle and spec ~= nil and spec.activeEffects ~= nil and spec.activeEffects.HARVEST_FAILURE ~= nil then
        if spec.ptoEngagementAttempt == true and spec.ptoEngagementAttemptWarningShown ~= true and rootVehicle:getIsActiveForInput(true) then
            g_currentMission:showBlinkingWarning(g_i18n:getText("rms_breakdowns_harvest_failure_message"), 4000)
            spec.ptoEngagementAttemptWarningShown = true
        end
        return false, warning
    end
    local effect = spec ~= nil and spec.activeEffects ~= nil and spec.activeEffects.PTO_ENGAGEMENT_BLOCKED_CHANCE or nil
    if effect == nil or spec.ptoEngagementAttempt ~= true then
        return canBeTurnedOn, warning
    end

    local ptoData = RMS_Utils.getConnectedPtoData(rootVehicle, "rear")
    if ptoData.connectedVehicles[vehicle] ~= true then
        return canBeTurnedOn, warning
    end

    if spec.ptoEngagementAttemptBlocked == nil then
        spec.ptoEngagementAttemptBlocked = math.random() < math.clamp(tonumber(effect.value) or 0, 0, 1)
    end

    if spec.ptoEngagementAttemptBlocked then
        if spec.ptoEngagementAttemptWarningShown ~= true
            and rootVehicle.getIsActiveForInput ~= nil
            and rootVehicle:getIsActiveForInput(true) then
            g_currentMission:showBlinkingWarning(g_i18n:getText("rms_breakdowns_pto_engagement_blocked_message"), 4000)
            spec.ptoEngagementAttemptWarningShown = true
        end
        return false, warning
    end

    return canBeTurnedOn, warning
end

local function runWithPtoEngagementAttempt(vehicle, callback)
    local rootVehicle = vehicle.rootVehicle
    local spec = rootVehicle ~= nil and rootVehicle.spec_RealisticMechanicalSystems or nil
    if spec ~= nil then
        spec.ptoEngagementAttempt = true
        spec.ptoEngagementAttemptBlocked = nil
        spec.ptoEngagementAttemptWarningShown = nil
    end
    local result = {callback()}
    if spec ~= nil then
        spec.ptoEngagementAttempt = false
        spec.ptoEngagementAttemptBlocked = nil
        spec.ptoEngagementAttemptWarningShown = nil
    end
    return unpack(result)
end

---Counts a PTO engagement attempt around the vanilla turn on action
function RMS_Breakdowns.actionEventTurnOn(vehicle, superFunc, actionName, inputValue, callbackState, isAnalog)
    return runWithPtoEngagementAttempt(vehicle, function()
        return superFunc(vehicle, actionName, inputValue, callbackState, isAnalog)
    end)
end

---Counts a PTO engagement attempt around the action controller turn on
function RMS_Breakdowns.actionControllerTurnOnEvent(vehicle, superFunc, direction)
    return runWithPtoEngagementAttempt(vehicle, function()
        return superFunc(vehicle, direction)
    end)
end

-- Switch off only at the source of the event.
-- @param boolean? noEventSend true when the change came over the network
function RMS_Breakdowns.setIsTurnedOn(vehicle, superFunc, isTurnedOn, noEventSend)
    local rootVehicle = vehicle.rootVehicle
    local spec = rootVehicle ~= nil and rootVehicle.spec_RealisticMechanicalSystems or nil
    local effect = spec ~= nil and spec.activeEffects ~= nil and spec.activeEffects.PTO_STUCK_ENGAGED_CHANCE or nil
    if effect ~= nil and not isTurnedOn and noEventSend ~= true and vehicle:getIsTurnedOn() and rootVehicle:getIsMotorStarted()
        and RMS_Utils.getConnectedPtoData(rootVehicle, "rear").connectedVehicles[vehicle] == true
        and math.random() < effect.value then
        if rootVehicle:getIsActiveForInput(true) then
            g_currentMission:showBlinkingWarning(g_i18n:getText("rms_breakdowns_pto_stuck_engaged_message"), 4000)
        end
        return
    end
    return superFunc(vehicle, isTurnedOn, noEventSend)
end

TurnOnVehicle.getCanBeTurnedOn = Utils.overwrittenFunction(TurnOnVehicle.getCanBeTurnedOn, RMS_Breakdowns.getCanBeTurnedOn)
TurnOnVehicle.setIsTurnedOn = Utils.overwrittenFunction(TurnOnVehicle.setIsTurnedOn, RMS_Breakdowns.setIsTurnedOn)
TurnOnVehicle.actionEventTurnOn = Utils.overwrittenFunction(TurnOnVehicle.actionEventTurnOn, RMS_Breakdowns.actionEventTurnOn)
TurnOnVehicle.actionEventTurnOnAll = Utils.overwrittenFunction(TurnOnVehicle.actionEventTurnOnAll, RMS_Breakdowns.actionEventTurnOn)
TurnOnVehicle.actionControllerTurnOnEvent = Utils.overwrittenFunction(TurnOnVehicle.actionControllerTurnOnEvent, RMS_Breakdowns.actionControllerTurnOnEvent)


---Blocks the AI helper from starting a vehicle whose engine cannot run
function RMS_Breakdowns.getCanStartAIVehicle(self, superFunc, ...)
    if not superFunc(self, ...) then
        return false
    end

    return self:getIsMotorStarted() or not RMS_Start.getIsColdBlocked(self)
end

RMS_Breakdowns.EffectApplicators.GEAR_SHIFT_FAILURE_CHANCE = {
    getEffectName = function()
        return "GEAR_SHIFT_FAILURE_CHANCE" 
    end,

    apply = function(vehicle, effectData, handler)

        local effectName = handler.getEffectName()

        if vehicle.spec_RealisticMechanicalSystems.activeFunctions[effectName] == nil then
            vehicle.spec_RealisticMechanicalSystems.activeFunctions[effectName] = function(v, dt)
                
                if v:getIsMotorStarted() then
                    local spec = v.spec_RealisticMechanicalSystems           
                    local effect = spec.activeEffects.GEAR_SHIFT_FAILURE_CHANCE
                    if effect and effect.value > 0 and effect.extraData.status == "FAILED" then
                        effect.extraData.timer = effect.extraData.timer + dt
                        if effect.extraData.timer > effect.extraData.duration then
                            effect.extraData.timer = 0
                            effect.extraData.status = "IDLE"
                        end
                    end
                end
            end
        end
    end,

    remove = function(vehicle, handler)

        local effectName = handler.getEffectName()
        if vehicle.spec_RealisticMechanicalSystems.activeFunctions[effectName] ~= nil then
            vehicle.spec_RealisticMechanicalSystems.activeFunctions[effectName] = nil
        end
    end
}

VehicleMotor.shiftGear = Utils.overwrittenFunction(VehicleMotor.shiftGear, function(self, superFunc, up)
    local vehicle = self.vehicle
    if vehicle ~= nil then
        local spec_rms = vehicle.spec_RealisticMechanicalSystems
        if spec_rms ~= nil and spec_rms.activeEffects ~= nil then
            local effect = spec_rms.activeEffects.GEAR_SHIFT_FAILURE_CHANCE
            if effect ~= nil and effect.value ~= nil then
                if effect.extraData.status == "FAILED" then return end
                if vehicle.isServer and math.random() < effect.value then
                    effect.extraData.status = "FAILED"
                    RMS_SoundManager.playSample(spec_rms.samples.transmissionShiftFailed)
                    RMS_EffectSyncEvent.send(vehicle, "GEAR_SHIFT_FAILURE_CHANCE", "FAILED", 0, 1, 0)
                    return
                end
            end
        end
    end
    return superFunc(self, up)
end)

VehicleMotor.selectGear = Utils.overwrittenFunction(VehicleMotor.selectGear, function(self, superFunc, gearIndex, activation)
    local vehicle = self.vehicle
    if vehicle ~= nil then
        local spec_rms = vehicle.spec_RealisticMechanicalSystems
        if spec_rms ~= nil and spec_rms.activeEffects ~= nil then
            local effect = spec_rms.activeEffects.GEAR_SHIFT_FAILURE_CHANCE
            if effect ~= nil and effect.value ~= nil then
                if effect.extraData.status == "FAILED" then return end
                if activation then
                    if vehicle.isServer and math.random() < effect.value then
                        effect.extraData.status = "FAILED"
                        RMS_SoundManager.playSample(spec_rms.samples.transmissionShiftFailed)
                        RMS_EffectSyncEvent.send(vehicle, "GEAR_SHIFT_FAILURE_CHANCE", "FAILED", 0, 1, 0)
                        return
                    end
                end
            end
        end
    end
    return superFunc(self, gearIndex, activation)
end)

VehicleMotor.updateGear = Utils.overwrittenFunction(VehicleMotor.updateGear, function(self, superFunc, acceleratorPedal, brakePedal, dt)
    local vehicle = self.vehicle
    local wasShifting = (self.gear == 0 and self.gearChangeTimer > 0)
    local adjAcceleratorPedal, adjBrakePedal = superFunc(self, acceleratorPedal, brakePedal, dt)
    local isShifting = (self.gear == 0 and self.gearChangeTimer > 0)

    if vehicle ~= nil and isShifting and not wasShifting then
        local spec_rms = vehicle.spec_RealisticMechanicalSystems
        if spec_rms ~= nil and spec_rms.activeEffects ~= nil then
            local effect = spec_rms.activeEffects.GEAR_SHIFT_FAILURE_CHANCE
            if effect ~= nil and effect.value ~= nil then
                if vehicle.isServer and math.random() < effect.value then
                    effect.extraData.status = "FAILED"
                    effect.extraData.timer = 0

                    self.gearChangeTimer = effect.extraData.duration
                    self.autoGearChangeTimer = effect.extraData.duration

                    RMS_SoundManager.playSample(spec_rms.samples.transmissionShiftFailed)
                    RMS_EffectSyncEvent.send(vehicle, "GEAR_SHIFT_FAILURE_CHANCE", "FAILED", 0, 1, effect.extraData.duration)
                end
                if effect.value >= 1.0 then
                    self.targetGear = self.previousGear
                end
            end
        end
    end

    return adjAcceleratorPedal, adjBrakePedal
end)

RMS_Breakdowns.EffectApplicators.GEAR_REJECTION_CHANCE = {
    getEffectName = function() return "GEAR_REJECTION_CHANCE" end,
    apply = function(vehicle, effectData, handler)
        local effectName = handler.getEffectName()
        local activeFunc = function(v, dt)
            if v:getIsMotorStarted() then
                local effect = v.spec_RealisticMechanicalSystems.activeEffects.GEAR_REJECTION_CHANCE
                if effect and effect.value > 0 then
                    local motor = v:getMotor()
                    if effect.extraData.status == 'REJECTED' then
                        motor.targetGear = 0
                        effect.extraData.timer = effect.extraData.timer + dt
                        if v.isServer and effect.extraData.timer >= effect.extraData.duration then
                            effect.extraData.status = 'IDLE'
                            effect.extraData.timer = 0
                            RMS_SoundManager.playSample(v.spec_RealisticMechanicalSystems.samples.transmissionShiftFailed)
                            RMS_EffectSyncEvent.send(v, "GEAR_REJECTION_CHANCE", "IDLE", 0, 1)
                        end

                    elseif v.isServer and v:getMotorLoadPercentage() > 0.8 and effect.extraData.status == 'IDLE' then
                        if math.random() < RMS_Utils.getChancePerFrameFromMeanTime(dt, effect.value) then
                            effect.extraData.status = 'REJECTED'
                            effect.extraData.timer = 0
                            if motor and motor.setGear then
                                motor:setGear(0, false)

                                RMS_EffectSyncEvent.send(v, "GEAR_REJECTION_CHANCE", "REJECTED", 0)
                                RMS_SoundManager.playSample(v.spec_RealisticMechanicalSystems.samples.gearDisengage)
                                if v:getIsActiveForInput(true) then
                                    g_currentMission:showBlinkingWarning(g_i18n:getText("rms_breakdowns_gear_disengage_message"), 3000)
                                end
                            end
                        end
                    end
                end
            end
        end
        startFrameUpdate(vehicle, effectName, activeFunc)
    end,
    remove = function(vehicle, handler)
        stopFrameUpdate(vehicle, handler.getEffectName())
    end
}

RMS_Breakdowns.EffectApplicators.LIGHTS_FLICKER_CHANCE = {
    getEffectName = function()
        return "LIGHTS_FLICKER_CHANCE" 
    end,

    apply = function(vehicle, effectData, handler)

        local effectName = handler.getEffectName()

        local activeFunc = function(v, dt)
                if v:getIsMotorStarted() then
                    local spec = v.spec_RealisticMechanicalSystems
                    local effect = spec.activeEffects.LIGHTS_FLICKER_CHANCE
                    if effect and effect.value > 0 then
                        if v.spec_lights == nil then return end

                        if effect.extraData.status == 'FLICKING' and effect.extraData.timer < effect.extraData.duration then
                            effect.extraData.timer = effect.extraData.timer + dt
                            local maxMask = v.spec_lights.maxLightStateMask
                            local randomMask = math.random(0, maxMask)
                            v:setLightsTypesMask(randomMask, true, true)

                        elseif effect.extraData.status == 'FLICKING' and effect.extraData.timer > effect.extraData.duration then
                            effect.extraData.status = 'IDLE'
                            effect.extraData.timer = 0
                            v:setLightsTypesMask(effect.extraData.maskBackup, true, true)

                        elseif v.isServer and effect.extraData.status == 'IDLE' then
                            if math.random() < RMS_Utils.getChancePerFrameFromMeanTime(dt, effect.value) then
                                effect.extraData.maskBackup = v:getLightsTypesMask()
                                if effect.extraData.maskBackup == 0 then return end
                                effect.extraData.status = 'FLICKING'

                                RMS_EffectSyncEvent.send(v, "LIGHTS_FLICKER_CHANCE", "FLICKING", 0, effect.extraData.maskBackup)

                            end
                        end
                    end
                end
            end
        startFrameUpdate(vehicle, effectName, activeFunc)
    end,

    remove = function(vehicle, handler)
        stopFrameUpdate(vehicle, handler.getEffectName())
    end
}

RMS_Breakdowns.EffectApplicators.EMPTY_EFFECT = {
}

---Returns the text refusing a start
-- @return string? reason text key, nil when nothing of the kind stands in the way
function RMS_Breakdowns.getStartBlockReason(vehicle)
    local reason = RMS_BatteryCharger.getStartBlockReason(vehicle)
    if reason ~= nil then
        return reason
    end

    local spec = vehicle.spec_RealisticMechanicalSystems
    if spec ~= nil and spec.batteryIsolated and vehicle:getIsControlled() and not vehicle:getIsAIActive() then
        return "rms_battery_isolator_open"
    end
    return nil
end

---Preserves native warnings and explains what refuses the start
function RMS_Breakdowns.getMotorNotAllowedWarning(self, superFunc)
    local reason = RMS_Breakdowns.getStartBlockReason(self)
    return reason ~= nil and g_i18n:getText(reason) or superFunc(self)
end

---Tells whether the engine may run, the key handing its start to RMS
function RMS_Breakdowns.getCanMotorRun(self, superFunc)
    local spec = self.spec_RealisticMechanicalSystems
    if spec == nil or spec.isExcludedVehicle then
        return superFunc(self)
    end
    if RMS_Breakdowns.getStartBlockReason(self) ~= nil then
        return false
    end

    local failure = spec.activeEffects.ENGINE_FAILURE
    if failure ~= nil then
        if not failure.extraData.starter then
            return false
        end
    elseif self:isUnderService() then
        if self:getIsActiveForInput(true) then
            g_currentMission:showBlinkingWarning(g_i18n:getText(self:getCurrentStatus()) .. " " .. g_i18n:getText("rms_breakdown_at_progress_message", 100))
        end
        return false
    end

    return superFunc(self) and not RMS_Start.takeKeyStart(self)
end
