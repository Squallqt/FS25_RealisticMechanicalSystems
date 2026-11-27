-- Copyright © 2026 Squallqt. All rights reserved.

---Vehicle breakdown effects
RMS_Breakdowns = {}

local BRAKE_SOUND_SPEED_THRESHOLD = 15

source(g_currentModDirectory .. "scripts/core/RMS_BreakdownRegistry.lua")


RMS_Breakdowns.EffectApplicators = {}

---Returns the text describing a stage on a vehicle
-- @param table vehicle vehicle
-- @param table stageData stage of the breakdown
-- @param table breakdown state of the breakdown
-- @param table definition definition of the breakdown
-- @return string description l10n key
function RMS_Breakdowns.getStageDescription(vehicle, stageData, breakdown, definition)
    local variant = RMS_Utils.getBreakdownNameVariant(vehicle, definition)
    local variantDescription = variant ~= nil and stageData.variantDescriptions[variant] or nil
    if type(variantDescription) == "table" then
        return variantDescription[breakdown.branch]
    elseif variantDescription ~= nil then
        return variantDescription
    end
    if stageData.electricDescription ~= nil and vehicle.spec_RealisticMechanicalSystems.isElectricVehicle then
        return stageData.electricDescription
    end
    if stageData.branchDescriptions ~= nil and stageData.branchDescriptions[breakdown.branch] ~= nil then
        return stageData.branchDescriptions[breakdown.branch]
    end
    return stageData.description
end

---Starts the update an effect runs each step, applied again keeping its first one
-- @param table vehicle vehicle
-- @param string effectName effect
-- @param function update update run each step
local function startFrameUpdate(vehicle, effectName, update)
    local updates = vehicle.spec_RealisticMechanicalSystems.activeFunctions
    updates[effectName] = updates[effectName] or update
end

---Returns what an effect has under way, kept through a recalculation
-- @param table vehicle vehicle
-- @param string effectName effect
-- @return table state status and timer of its event, then its own fields
function RMS_Breakdowns.getEffectState(vehicle, effectName)
    local states = vehicle.spec_RealisticMechanicalSystems.effectStates
    states[effectName] = states[effectName] or { status = "IDLE", timer = 0 }
    return states[effectName]
end

local getEffectState = RMS_Breakdowns.getEffectState

---Returns the RMS state of a machine, nil while it still loads
-- @param table vehicle vehicle
-- @return table? spec RMS specialization of the vehicle
function RMS_Breakdowns.getLoadedSpec(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    return spec ~= nil and spec.activeEffects ~= nil and spec or nil
end

local getLoadedSpec = RMS_Breakdowns.getLoadedSpec

---Stops the update of an effect and drops what it had under way
-- @param table vehicle vehicle
-- @param string effectName effect
local function stopFrameUpdate(vehicle, effectName)
    local spec = vehicle.spec_RealisticMechanicalSystems
    spec.activeFunctions[effectName] = nil
    spec.effectStates[effectName] = nil
end

---Warns the driver of the machine, nobody else
-- @param table vehicle vehicle
-- @param string textKey l10n key
-- @param integer duration duration (ms)
function RMS_Breakdowns.showWarning(vehicle, textKey, duration)
    if vehicle:getIsActiveForInput(true) then
        g_currentMission:showBlinkingWarning(g_i18n:getText(textKey), duration)
    end
end

local showWarning = RMS_Breakdowns.showWarning

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
-- @param table vehicle vehicle
-- @return string family Car, Tractor4, Tractor6 or Heavy
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

---Returns the time from the catch to the engine start
-- @param table vehicle vehicle
-- @return integer delay catch in the catch sound of its family (ms)
function RMS_Breakdowns.getStarterCatchDelay(vehicle)
    return STARTER_CATCHES[RMS_Breakdowns.getStarterFamily(vehicle)].catch
end

---Returns the run up from the engine start to the idle
-- @param table vehicle vehicle
-- @return integer runUp run up (ms)
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
-- @param table vehicle vehicle
-- @param float dt time since the last frame (ms)
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
-- @param table vehicle vehicle
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

---Stops an engine running or starting, which the game never does when it may not run
-- @param table vehicle vehicle
local function stopRunningEngine(vehicle)
    local motorState = vehicle:getMotorState()
    if motorState == MotorState.ON or motorState == MotorState.STARTING then
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
    apply = function(vehicle) RMS_Electrical.switchOffAllLights(vehicle, true) end
}

local LIGHT_CIRCUITS = {
    LOW_BEAM_FAILURE = "LIGHT_TYPE_DEFAULT",
    HIGH_BEAM_FAILURE = "LIGHT_TYPE_HIGHBEAM",
    FRONT_WORK_LIGHTS_FAILURE = "LIGHT_TYPE_WORK_FRONT",
    REAR_WORK_LIGHTS_FAILURE = "LIGHT_TYPE_WORK_BACK"
}

---Tells whether one of the lights carries a light type and is mounted
-- @param table vehicle vehicle
-- @param table lights lights
-- @param integer lightType light type
-- @return boolean holdsType true when one does
local function getHoldsLightType(vehicle, lights, lightType)
    for _, light in ipairs(lights) do
        for _, lampLightType in ipairs(light.lightTypes or {}) do
            if lampLightType == lightType and RMS_Electrical.getIsLampMounted(vehicle, light.node) then
                return true
            end
        end
    end
    return false
end

---Tells whether the machine carries a lamp of a light type
-- @param table vehicle vehicle
-- @param integer lightType light type
-- @return boolean carriesType true when it carries one
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

    getIsCarried = function(vehicle) return RMS_Electrical.getMountedBeaconCount(vehicle) > 0 end
}

RMS_Breakdowns.EffectApplicators.TURN_LIGHTS_FAILURE = {
    apply = function(vehicle)
        if vehicle:getTurnLightState() ~= Lights.TURNLIGHT_OFF then
            vehicle:setTurnLightState(Lights.TURNLIGHT_OFF, true, true)
        end
    end,

    getIsCarried = RMS_Electrical.getCarriesTurnLights
}

---Tells whether the machine carries the lamps of a light circuit
-- @param table vehicle vehicle
-- @param string effectName effect of the circuit failure
-- @return boolean carriesCircuit true when it carries them
function RMS_Breakdowns.getCarriesLightCircuit(vehicle, effectName)
    return RMS_Breakdowns.EffectApplicators[effectName].getIsCarried(vehicle)
end

---Tells whether a light circuit is switched on
-- @param table vehicle vehicle
-- @param string effectName effect of the circuit failure
-- @return boolean isLit true when switched on
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
-- @param table self vehicle
-- @param function superFunc original function
-- @param integer lightsTypesMask light types mask
-- @param boolean force force action
-- @param boolean noEventSend no event send
function RMS_Breakdowns.setLightsTypesMask(self, superFunc, lightsTypesMask, force, noEventSend)
    local rootVehicle = self:getRootVehicle()
    local spec = rootVehicle.spec_RealisticMechanicalSystems
    local effects = spec ~= nil and spec.activeEffects or {}
    if spec ~= nil and spec.activeEffects ~= nil and RMS_Electrical.getKeepsLightsOff(rootVehicle) then
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

---Returns a state of the root vehicle once it has loaded
-- @param table vehicle vehicle
-- @param function getState reads the state of a vehicle
-- @return any state state, false while the root vehicle loads
local function getRootState(vehicle, getState)
    local rootVehicle = vehicle:getRootVehicle()
    return getLoadedSpec(rootVehicle) ~= nil and getState(rootVehicle)
end

---Tells whether the root vehicle has no current for its lamps
-- @param table vehicle vehicle
-- @return boolean isUnpowered true without current
local function getIsUnpowered(vehicle)
    return getRootState(vehicle, RMS_Electrical.getIsUnpowered)
end

---Keeps the beacon lights out as the lights, or without their circuit
-- @param table self vehicle
-- @param function superFunc original function
-- @param boolean visibility new visibility
-- @param boolean force force action
-- @param boolean noEventSend no event send
function RMS_Breakdowns.setBeaconLightsVisibility(self, superFunc, visibility, force, noEventSend)
    local spec = self:getRootVehicle().spec_RealisticMechanicalSystems
    local activeEffects = spec ~= nil and spec.activeEffects or {}
    local isKeptOff = getRootState(self, RMS_Electrical.getKeepsLightsOff)
    superFunc(self, visibility and activeEffects.BEACON_LIGHTS_FAILURE == nil and not isKeptOff, force, noEventSend)
end

---Keeps the turn and hazard lights out without their circuit or current
-- @param table self vehicle
-- @param function superFunc original function
-- @param integer state one of the constants Lights.TURNLIGHT_*
-- @param boolean force force action
-- @param boolean noEventSend no event send
function RMS_Breakdowns.setTurnLightState(self, superFunc, state, force, noEventSend)
    local spec = self:getRootVehicle().spec_RealisticMechanicalSystems
    local activeEffects = spec ~= nil and spec.activeEffects or {}
    if activeEffects.TURN_LIGHTS_FAILURE ~= nil or getIsUnpowered(self)
        or state ~= Lights.TURNLIGHT_HAZARD and getRootState(self, RMS_Electrical.getKeepsLightsOff) then
        state = Lights.TURNLIGHT_OFF
    end
    superFunc(self, state, force, noEventSend)
end

---Puts the lamps out without current, the driver sitting in or not
-- @param table self vehicle
-- @param function superFunc original function
-- @param boolean onlyPowered argument of the game's function
-- @return boolean isActive true when the lamps may light
function RMS_Breakdowns.getIsActiveForLights(self, superFunc, onlyPowered)
    return not getIsUnpowered(self) and superFunc(self, onlyPowered)
end

---Tells whether a wheel has its physics shape
-- @param table? wheel wheel
-- @return boolean hasShape true with its shape
local function getHasWheelShape(wheel)
    return wheel ~= nil and wheel.physics.wheelShape ~= 0
end

-- a right wheel has isLeft false or lies at a positive x of the root
local SEIZED_WHEEL_CHOICES = {
    function(wheel, x) return (not wheel.isLeft or x > 0) and wheel.physics.brakeFactor > 0 end,
    function(wheel, x) return not wheel.isLeft or x > 0 end,
    function(wheel) return wheel.physics.brakeFactor > 0 end,
    function() return true end
}

---Returns the wheel a seizure locks: the foremost of the first choice any wheel meets
-- @param table vehicle vehicle
-- @return table? wheel wheel, nil without a wheel shape
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
                local x, _, z = localToLocal(candidate.driveNode, rootNode, 0, 0, 0)
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
    remove = function(vehicle) stopFrameUpdate(vehicle, "BRAKE_FORCE_MODIFIER") end
}

---Refreshes the steering faults
-- @param table vehicle vehicle
local function refreshSteeringFaults(vehicle) RMS_Steering.refreshFaults(vehicle) end

for _, effectId in ipairs({ "STEERING_STATIC_BIAS_EFFECT", "BRAKE_PULL_EFFECT", "STEERING_PLAY_EFFECT", "STEERING_WHEEL_FREE_EFFECT" }) do
    RMS_Breakdowns.EffectApplicators[effectId] = { apply = refreshSteeringFaults, remove = refreshSteeringFaults }
end

RMS_Breakdowns.EffectApplicators.WHEEL_SEIZURE_EFFECT = {
    remove = function(vehicle) vehicle.spec_RealisticMechanicalSystems.wheelSeizureTargetIndex = nil end
}

local MISFIRE_SOUND_DIP = 0.6

---Dips the engine sounds on each misfire while the engine coughs
-- @param table vehicle vehicle
-- @param table cough state of the cough
-- @param float dt time of the step (ms)
local function updateMisfireSound(vehicle, cough, dt)
    local dip = 0
    if cough.status == "CHOKING" then
        -- Four-stroke firing frequency: one cycle per two revolutions
        cough.misfireCycles = (cough.misfireCycles or 0) + dt * vehicle:getMotor():getLastModulatedMotorRpm() / 120000
        if cough.misfireCycles >= 1 then
            cough.misfireCycles = cough.misfireCycles % 1
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

---Takes the cruise control off for a cough, kept to give back
-- @param table vehicle vehicle
-- @param table cough state of the cough
function RMS_Breakdowns.startEngineCough(vehicle, cough)
    cough.status, cough.timer, cough.cruiseState = "CHOKING", 0, vehicle:getCruiseControlState()
    if cough.cruiseState ~= 0 then
        vehicle:setCruiseControlState(0, true)
    end
end

---Runs the coughs of a hesitating engine, extraData {duration in ms, motorLoad, amplitude}
-- @param table vehicle vehicle
-- @param float dt time of the step (ms)
local function updateEngineCough(vehicle, dt)
    local effect = vehicle.spec_RealisticMechanicalSystems.activeEffects.ENGINE_HESITATION_CHANCE
    local cough = getEffectState(vehicle, "ENGINE_HESITATION_CHANCE")
    if vehicle.isClient then
        updateMisfireSound(vehicle, cough, dt)
    end

    if cough.status == "CHOKING" then
        cough.timer = cough.timer + dt
        if cough.timer > effect.extraData.duration then
            if cough.cruiseState ~= 0 then
                vehicle:setCruiseControlState(cough.cruiseState, true)
            end
            cough.status, cough.timer = "IDLE", 0
        end
    elseif RMS_Utils.getMotorLoad(vehicle) > effect.extraData.motorLoad and vehicle.isServer
        and math.random() < RMS_Utils.getChancePerFrameFromMeanTime(dt, effect.value) then
        RMS_Breakdowns.startEngineCough(vehicle, cough)
        RMS_EffectSyncEvent.send(vehicle, "ENGINE_HESITATION_CHANCE", "CHOKING")
    end
end

RMS_Breakdowns.EffectApplicators.ENGINE_HESITATION_CHANCE = {
    apply = function(vehicle) startFrameUpdate(vehicle, "ENGINE_HESITATION_CHANCE", updateEngineCough) end,

    remove = function(vehicle)
        stopFrameUpdate(vehicle, "ENGINE_HESITATION_CHANCE")
        if vehicle.isClient then
            for _, sample in ipairs(vehicle.spec_motorized.motorSamples) do
                RMS_SoundManager.setSampleVolumeOffset(sample, 0)
            end
        end
    end
}

---Tells whether the driver brakes with the drive axis
-- @param table vehicle vehicle
-- @param float axisForward drive axis
-- @param boolean isManualDirection true when the driver changes direction by hand
-- @return boolean isBraking true while braking
local function getIsBraking(vehicle, axisForward, isManualDirection)
    if isManualDirection then
        return axisForward < -0.01
    end
    return vehicle.movingDirection ~= 0 and axisForward ~= 0 and math.sign(vehicle.movingDirection) ~= math.sign(axisForward)
end

---Returns the throttle held to a limit, in automatic direction on the pedal the machine rolls on
-- @param table vehicle vehicle
-- @param float axisForward drive axis
-- @param float limit highest throttle
-- @param boolean isManualDirection true when the driver changes direction by hand
-- @return float axisForward drive axis
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

---Plays the squeal of worn friction as a hard stop passes through town speed
-- @param table vehicle vehicle
-- @param table spec RMS specialization of the vehicle
-- @param table effect brake effect
-- @param float axisForward drive axis
local function playBrakeSqueal(vehicle, spec, effect, axisForward)
    local speed = vehicle:getLastSpeed()
    local braking = getEffectState(vehicle, "BRAKE_FORCE_MODIFIER")
    local previousSpeed = braking.speed or speed
    braking.speed = speed
    if previousSpeed >= BRAKE_SOUND_SPEED_THRESHOLD and speed < BRAKE_SOUND_SPEED_THRESHOLD and math.abs(axisForward) > 0.999
        and RMS_Drivetrain.getIsRoadVehicleCategory(vehicle) and math.random() < math.abs(effect.value) then
        RMS_SoundManager.playSample(spec.samples.brakes)
        RMS_EffectSyncEvent.send(vehicle, "BRAKE_FORCE_MODIFIER", "SOUND")
    end
end

---Locks the seized wheel by its brake
-- @param table vehicle vehicle
-- @param float intensity seizure, 0 to 1
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
    setWheelShapeProps(wheel.node, physics.wheelShape, 0, math.max(brakeForce, 100) * intensity, physics.steeringAngle,
        math.max(physics.rotationDamping * (3 + 4 * intensity), 5))
end

---Applies the pedal effects and the wheel seizure to the physics step
-- @param table vehicle vehicle
-- @param function superFunc original function
-- @param float axisForward forward axis
-- @param float axisSide side axis
-- @param boolean doHandbrake true to apply the handbrake
-- @param float dt time of the step (ms)
-- @return float acceleration what the game's function returns
function RMS_Breakdowns.updateVehiclePhysics(vehicle, superFunc, axisForward, axisSide, doHandbrake, dt)
    local spec = vehicle.spec_RealisticMechanicalSystems
    local effects = spec.activeEffects
    local isManualDirection = vehicle:getDirectionChangeMode() == VehicleMotor.DIRECTION_CHANGE_MODE_MANUAL
    local cough = spec.effectStates.ENGINE_HESITATION_CHANCE
    if cough ~= nil and cough.status == "CHOKING" then
        axisForward = axisForward * (1 - effects.ENGINE_HESITATION_CHANCE.extraData.amplitude)
    end
    if effects.ENGINE_LIMP_EFFECT ~= nil then
        axisForward = limitThrottle(vehicle, axisForward, 1 + effects.ENGINE_LIMP_EFFECT.value, isManualDirection)
    end

    local brake = effects.BRAKE_FORCE_MODIFIER
    if brake ~= nil and getIsBraking(vehicle, axisForward, isManualDirection) then
        playBrakeSqueal(vehicle, spec, brake, axisForward)
        axisForward = axisForward * math.max(1 + brake.value, 0.01)
    end

    local result = superFunc(vehicle, axisForward, axisSide, doHandbrake, dt)

    local seizure = effects.WHEEL_SEIZURE_EFFECT
    if seizure ~= nil and vehicle.isAddedToPhysics then
        seizeWheel(vehicle, seizure.value)
    end
    return result
end

---Makes the game read the torque curve again
-- @param table vehicle vehicle
local function refreshTorqueCurve(vehicle) vehicle:updateMotorProperties() end

RMS_Breakdowns.EffectApplicators.ENGINE_TORQUE_MODIFIER = { apply = refreshTorqueCurve, remove = refreshTorqueCurve }
RMS_Breakdowns.EffectApplicators.ENGINE_THERMAL_TORQUE_LIMIT = RMS_Breakdowns.EffectApplicators.ENGINE_TORQUE_MODIFIER

RMS_Breakdowns.EffectApplicators.DRIVE_LOSS_EFFECT = {

}

RMS_Breakdowns.EffectApplicators.TRAILER_BRAKE_FAILURE = {
}

AttacherJoints.onBrake = Utils.overwrittenFunction(AttacherJoints.onBrake, function(self, superFunc, brakePedal)
    local spec = getLoadedSpec(self)
    local effect = spec ~= nil and spec.activeEffects.TRAILER_BRAKE_FAILURE or nil
    if effect ~= nil then
        brakePedal = brakePedal * (1 + effect.value)
    end
    superFunc(self, brakePedal)
end)

VehicleMotor.getMaxClutchTorque = Utils.overwrittenFunction(VehicleMotor.getMaxClutchTorque, function(self, superFunc)
    local spec = getLoadedSpec(self.vehicle)
    local effect = spec ~= nil and spec.activeEffects.DRIVE_LOSS_EFFECT or nil
    if effect == nil then
        return superFunc(self)
    end
    return superFunc(self) * (1 - effect.value)
end)

RMS_Breakdowns.EffectApplicators.FOUR_WD_ENGAGE_FAILURE = {

}
RMS_Breakdowns.EffectApplicators.FOUR_WD_STUCK_ENGAGED = {

}
RMS_Breakdowns.EffectApplicators.DIFF_LOCK_ENGAGE_FAILURE = {

}
RMS_Breakdowns.EffectApplicators.DIFF_LOCK_STUCK_ENGAGED = {

}

---Empties the particulate filter of its soot and ash, as a new or cleaned filter
-- @param table vehicle vehicle
function RMS_Breakdowns.cleanParticulateFilter(vehicle)
    local fuelState = vehicle.spec_RealisticMechanicalSystems.fuelState
    fuelState.particulateFilterLevel, fuelState.particulateFilterAsh, fuelState.particulateFilterOilAsh = 0, 0, 0
end

---Sets the soot overload and the ash breakdowns of the particulate filter
-- @param table vehicle vehicle
function RMS_Breakdowns.updateParticulateFilterOverload(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    local fuelState = spec.fuelState
    local config = RMS_Config.EXHAUST.PARTICULATE_FILTER
    local breakdownId = "PARTICULATE_FILTER_SOOT_OVERLOAD"
    local breakdown = spec.activeBreakdowns[breakdownId]
    local isBlocked = spec.activeEffects.PARTICULATE_FILTER_BLOCKED ~= nil
    local isOut = spec.activeBreakdowns.PARTICULATE_FILTER_ASH ~= nil or spec.activeBreakdowns.PARTICULATE_FILTER_FAILURE ~= nil

    if fuelState.isFilterOut and not isOut then
        RMS_Breakdowns.cleanParticulateFilter(vehicle)
    end
    if (fuelState.isParticulateFilterOverloaded and breakdown == nil) or (fuelState.isParticulateFilterBlocked and not isBlocked) then
        -- the ash stays, as after a regeneration
        fuelState.particulateFilterLevel = fuelState.particulateFilterAsh
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

    if spec.activeBreakdowns.PARTICULATE_FILTER_ASH == nil and fuelState.particulateFilterAsh >= 1 then
        spec.partAbuse.PARTICULATE_FILTER_ASH = fuelState.particulateFilterOilAsh > 0 and RealisticMechanicalSystems.WARRANTY_ABUSE.oil or nil
        vehicle:addBreakdown("PARTICULATE_FILTER_ASH", { stage = 1, isVisible = true })
        isOut = true
    end
    fuelState.isFilterOut = isOut
end

---Sets the torque and speed caps of the AdBlue inducement and the full filter
-- @param table vehicle vehicle
-- @param float dt time of the step (ms)
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

    local tank = RMS_AdBlue.getInducement(vehicle)
    local targetTorque, rpmCap = 1, nil
    if tank == "SEVERE" or inducement ~= nil and spec.scrInducementHours >= inducement.SEVERE_HOURS then
        targetTorque = config.SCR_INDUCEMENT.SEVERE_TORQUE
        rpmCap = vehicle:getMotor().peakMotorPowerRotSpeed * 30 / math.pi * config.SCR_INDUCEMENT.SEVERE_RPM
    elseif tank == "LOW" or inducement ~= nil and spec.scrInducementHours >= inducement.LOW_HOURS then
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
    local spec = getLoadedSpec(vehicle)
    if spec ~= nil then
        local effect = spec.activeEffects.ENGINE_TORQUE_MODIFIER
        if effect ~= nil then
            torque = torque * math.max((1 + effect.value), 0.2)
        end
        torque = torque * RMS_Thermal.getEngineTorqueFactor(vehicle) * spec.engineTorqueCap
            * RMS_EngineRemap.getTorqueFactor(vehicle)
        local rpmCap = spec.engineRpmCap
        if rpmCap ~= nil and rpm > rpmCap - 50 then
            torque = torque * math.clamp((rpmCap - rpm) / 50, 0, 1)
        end
    end
    return torque
end)
                  
RMS_Breakdowns.EffectApplicators.FUEL_CONSUMPTION_MODIFIER = {
}

---Burns the fuel a breakdown wastes, a remapped engine at stock load
-- @param table vehicle vehicle
-- @param function superFunc original function
-- @param float dt time of the step (ms)
-- @param float accInput accelerator input
-- @return any ... what the game's function returns, on a machine RMS leaves alone
function RMS_Breakdowns.updateConsumersOverwrite(vehicle, superFunc, dt, accInput)
    local waste = vehicle.spec_RealisticMechanicalSystems.activeEffects.FUEL_CONSUMPTION_MODIFIER
    local adBlue, diesel = RMS_AdBlue.getConsumers(vehicle)
    if adBlue == nil and waste == nil and not RMS_EngineRemap.getIsRemapped(vehicle) then
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
        end
    end
    local pending = adBlue ~= nil and adBlue.fillLevelToChange or 0
    if adBlue ~= nil then
        adBlue.usage = diesel.usage * RMS_AdBlue.getRatio(vehicle)
    end
    for index in pairs(usages) do
        local consumer = motorized.consumers[index]
        consumer.usage = consumer.usage * factor
    end
    superFunc(vehicle, dt, accInput)
    for index, usage in pairs(usages) do
        motorized.consumers[index].usage = usage
    end
    if adBlue ~= nil then
        RMS_AdBlue.chargeWorker(vehicle, adBlue, pending)
    end
    motorized.smoothedLoadPercentage = load
end

-- a worn clutch takes longer to bite, the game slipping it meanwhile
RMS_Breakdowns.EffectApplicators.TRANSMISSION_SLIP_EFFECT = {
    apply = function(vehicle, effect)
        local spec, motor = vehicle.spec_RealisticMechanicalSystems, vehicle:getMotor()
        spec.stockClutchSlippingTime = spec.stockClutchSlippingTime or motor.clutchSlippingTime
        motor.clutchSlippingTime = spec.stockClutchSlippingTime * (1 + effect.value) ^ 3
    end,

    remove = function(vehicle)
        local spec = vehicle.spec_RealisticMechanicalSystems
        vehicle:getMotor().clutchSlippingTime = spec.stockClutchSlippingTime
        spec.stockClutchSlippingTime = nil
    end
}

RMS_Breakdowns.EffectApplicators.CVT_SLIP_EFFECT = {}
RMS_Breakdowns.EffectApplicators.CVT_MAX_RATIO_MODIFIER = {}

local TRANSMISSION_SLIP_CONVERGENCE_PER_SECOND = 0.9
local TRANSMISSION_SLIP_RESUME_GAP_SECONDS = 0.25

---Returns the seconds since the last slip ratio, none after a pause
-- @param table spec RMS specialization of the vehicle
-- @param string lastTimeKey spec field of the last time
-- @return float seconds time (s)
local function getSlipSeconds(spec, lastTimeKey)
    local now = g_currentMission.time
    local seconds = math.max((now - (spec[lastTimeKey] or now)) / 1000, 0)
    spec[lastTimeKey] = now
    return seconds > TRANSMISSION_SLIP_RESUME_GAP_SECONDS and 0 or seconds
end

---Returns the slip of a worn clutch, the engine running ahead while it accelerates at speed
-- @param table motor motor
-- @param table spec RMS specialization of the vehicle
-- @param float slip value of the slip effect
-- @param float minRatio lowest gear ratio
-- @return float slip share the ratio grows by
local function getClutchSlip(motor, spec, slip, minRatio)
    spec.slipAccumulatedMod = spec.slipAccumulatedMod or 0
    local seconds = getSlipSeconds(spec, "slipLastUpdateMs")
    local speedFactor = math.min(motor.vehicle:getLastSpeed() / (motor:getMaximumForwardSpeed() * 3.6), 1)
    if minRatio == 0 or speedFactor <= 0.5 then
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

---Returns the ratio a slipping variator holds at low speed, and whether it slips
-- @param table motor motor
-- @param table spec RMS specialization of the vehicle
-- @param float slip value of the slip effect
-- @param float minRatio lowest gear ratio
-- @param float maxRatio highest gear ratio
-- @return float minRatio lowest gear ratio
-- @return boolean isSlipping true while it slips
local function getVariatorSlip(motor, spec, slip, minRatio, maxRatio)
    local vehicle = motor.vehicle
    local seconds = getSlipSeconds(spec, "cvtSlipLastUpdateMs")
    local lastAcceleration = spec.cvtSlipLastAccelerationFactor or 0
    local speedFactor = math.min(vehicle:getLastSpeed() / (motor:getMaximumForwardSpeed() * 3.6 / 2), 1)
    if minRatio == 0 or maxRatio == 0 or speedFactor >= 0.5 then
        return minRatio, false
    end
    local decayPerSecond = 0.01 / slip * math.max(speedFactor, 0.1) / (RMS_Utils.getMotorLoad(vehicle) + 0.2)
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
    local spec = getLoadedSpec(self.vehicle)
    if spec == nil then
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

    local pressureDrop = spec.effectStates.CVT_PRESSURE_DROP_CHANCE
    if pressureDrop ~= nil and pressureDrop.timer > 0 then
        minRatio = minRatio * 1.5
    end
    return minRatio, maxRatio
end)

---Engages a delayed powershift gear, the effect value the delay in s, no gear biting from 1
-- @param table vehicle vehicle
-- @param float dt time of the step (ms)
local function updatePowershiftEngagement(vehicle, dt)
    local engagement = getEffectState(vehicle, "POWERSHIFT_ENGAGEMENT_LAG_AND_HARSH_EFFECT")
    if engagement.status ~= "DELAYED" or not vehicle:getIsMotorStarted() then
        return
    end
    local spec = vehicle.spec_RealisticMechanicalSystems
    engagement.timer = engagement.timer + dt
    if engagement.timer > spec.activeEffects.POWERSHIFT_ENGAGEMENT_LAG_AND_HARSH_EFFECT.value * 1000 then
        engagement.status = "ENGAGING"
        vehicle:getMotor():applyTargetGear()
        engagement.status = "IDLE"
        RMS_SoundManager.playSample(spec.samples.powershiftClunk)
        RMS_EffectSyncEvent.send(vehicle, "POWERSHIFT_ENGAGEMENT_LAG_AND_HARSH_EFFECT", "CLUNK")
    end
end

RMS_Breakdowns.EffectApplicators.POWERSHIFT_ENGAGEMENT_LAG_AND_HARSH_EFFECT = {
    apply = function(vehicle) startFrameUpdate(vehicle, "POWERSHIFT_ENGAGEMENT_LAG_AND_HARSH_EFFECT", updatePowershiftEngagement) end,
    remove = function(vehicle) stopFrameUpdate(vehicle, "POWERSHIFT_ENGAGEMENT_LAG_AND_HARSH_EFFECT") end
}

-- a worn pack engages each gear late, or never at the end of its life
VehicleMotor.applyTargetGear = Utils.overwrittenFunction(VehicleMotor.applyTargetGear, function(self, superFunc)
    local vehicle = self.vehicle
    local spec = getLoadedSpec(vehicle)
    local effect = spec ~= nil and spec.activeEffects.POWERSHIFT_ENGAGEMENT_LAG_AND_HARSH_EFFECT or nil
    if effect == nil then
        return superFunc(self)
    end
    local engagement = getEffectState(vehicle, "POWERSHIFT_ENGAGEMENT_LAG_AND_HARSH_EFFECT")
    if engagement.status == "ENGAGING" then
        return superFunc(self)
    elseif effect.value >= 1 then
        self.targetGear = self.previousGear
        return superFunc(self)
    end
    engagement.status, engagement.timer = "DELAYED", 0
end)

---Collects the lift joints holding an implement, then the cylinders, of the chain
-- @param table vehicle vehicle
-- @param table functions lift joints and moving tools collected
-- @param table visited vehicles already collected
local function collectHydraulicFunctions(vehicle, functions, visited)
    if visited[vehicle] then
        return
    end
    visited[vehicle] = true

    local attacherSpec = vehicle.spec_attacherJoints
    if attacherSpec ~= nil then
        for _, implement in pairs(attacherSpec.attachedImplements) do
            local joint = attacherSpec.attacherJoints[implement.jointDescIndex]
            if RMS_Utils.getIsHydraulicLiftJoint(joint) then
                table.insert(functions, joint)
            end
        end
    end
    if vehicle.spec_cylindered ~= nil then
        for _, tool in ipairs(vehicle.spec_cylindered.movingTools) do
            if RMS_Utils.getIsHydraulicMovingTool(tool) and (tool.rotSpeed ~= nil or tool.transSpeed ~= nil or tool.animSpeed ~= nil) then
                table.insert(functions, tool)
            end
        end
    end
    for _, child in pairs(vehicle:getChildVehicles()) do
        collectHydraulicFunctions(child, functions, visited)
    end
end

---Returns a mass against the machine's own mass
-- @param table vehicle vehicle
-- @param float mass mass (t)
-- @return float ratio ratio, 0 to 1
local function getHydraulicMassRatio(vehicle, mass)
    return math.clamp(mass / math.max(vehicle:getTotalMass(true), 0.01), 0, 1)
end

---Returns the active breakdown carrying an effect
-- @param table spec RMS specialization of the vehicle
-- @param string effectId effect
-- @return table? breakdown state of the breakdown, nil without one
function RMS_Breakdowns.getBreakdownCarryingEffect(spec, effectId)
    for breakdownId, breakdown in pairs(spec.activeBreakdowns) do
        if breakdown.isActive then
            local stageData = RMS_Breakdowns.BreakdownRegistry[breakdownId].stages[breakdown.stage]
            for _, effectData in ipairs(RMS_Utils.getBranchItems(stageData.effects, breakdown)) do
                if effectData.id == effectId then
                    return breakdown
                end
            end
        end
    end
    return nil
end

---Finds the function a valve fault hits, drawn once and found again on a new chain
-- @param table vehicle vehicle
-- @param string effectName effect
local function updateHydraulicTarget(vehicle, effectName)
    local breakdown = RMS_Breakdowns.getBreakdownCarryingEffect(vehicle.spec_RealisticMechanicalSystems, effectName)
    if breakdown == nil then
        return
    end
    local state = getEffectState(vehicle, effectName)
    local hash = vehicle:getChildVehicleHash()
    if state.hash == hash and state.index == breakdown.effectTargetIndex and state.index ~= 0 then
        return
    end

    local functions = {}
    collectHydraulicFunctions(vehicle, functions, {})
    if breakdown.effectTargetIndex == 0 and #functions > 0 and vehicle.isServer then
        breakdown.effectTargetIndex = math.random(1, #functions)
        RealisticMechanicalSystems.raiseRMSDirty(vehicle, RealisticMechanicalSystems.SYNC_GROUP.BREAKDOWNS)
    end
    state.hash, state.index, state.target = hash, breakdown.effectTargetIndex, functions[breakdown.effectTargetIndex]
end

---Returns the function a valve fault hits
-- @param table spec RMS specialization of the vehicle
-- @param string effectName effect
-- @return table? target lift joint or moving tool, nil without one
local function getHydraulicTarget(spec, effectName)
    local state = spec.activeEffects[effectName] ~= nil and spec.effectStates[effectName] or nil
    return state ~= nil and state.target or nil
end

---Creates the applicator of a valve fault on one function
-- @param string effectName effect
-- @return table applicator apply and remove
local function createHydraulicTargetApplicator(effectName)
    ---Finds the function the fault hits
    -- @param table vehicle vehicle
    local function update(vehicle)
        updateHydraulicTarget(vehicle, effectName)
    end
    return {
        apply = function(vehicle)
            startFrameUpdate(vehicle, effectName, update)
            update(vehicle)
        end,
        remove = function(vehicle) stopFrameUpdate(vehicle, effectName) end
    }
end

RMS_Breakdowns.EffectApplicators.HYDRAULIC_SPEED_MODIFIER = {}
RMS_Breakdowns.EffectApplicators.LOADER_CONTROL_EFFECT = {}
RMS_Breakdowns.EffectApplicators.LIFT_CONTROL_FAILURE = {}
RMS_Breakdowns.EffectApplicators.HYDRAULIC_FUNCTION_ERRATIC_EFFECT = createHydraulicTargetApplicator("HYDRAULIC_FUNCTION_ERRATIC_EFFECT")
RMS_Breakdowns.EffectApplicators.HYDRAULIC_FUNCTION_BLOCKED_EFFECT = createHydraulicTargetApplicator("HYDRAULIC_FUNCTION_BLOCKED_EFFECT")

---Scales the damping of the cab, suspensionParameters[axis] being {spring, damping}
-- @param table vehicle vehicle
-- @param float factor factor of the stock damping
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

---Tells whether an implement is folded on its transport locks
-- @param table implement implement
-- @return boolean isFolded true when folded
local function getIsFoldedAway(implement)
    return implement.getIsUnfolded ~= nil and not implement:getIsUnfolded()
end

---Restores the lift ranges no longer sagging, sags {joint = {top, share}}; a lift the driver lowers sets its own
-- @param table state state of the hold drift
-- @param table kept true by joint still sagging
local function restoreLiftRanges(state, kept)
    for joint, sag in pairs(state.sags) do
        if kept[joint] == nil then
            if not joint.moveDown then
                joint.upperAlpha = sag.top
            end
            state.sags[joint] = nil
        end
    end
end

---Sinks a raised implement, the top of its lift range sliding down
-- @param table vehicle vehicle
-- @param float dt time of the step (ms)
local function updateHoldDrift(vehicle, dt)
    local spec = vehicle.spec_RealisticMechanicalSystems
    local breakdown = RMS_Breakdowns.getBreakdownCarryingEffect(spec, "HYDRAULIC_HOLD_DRIFT_EFFECT")
    local attacherSpec = vehicle.spec_attacherJoints
    if not vehicle.isServer or breakdown == nil or attacherSpec == nil then
        return
    end

    local lifts = {}
    for _, implement in pairs(attacherSpec.attachedImplements) do
        if RMS_Utils.getIsHydraulicLiftJoint(attacherSpec.attacherJoints[implement.jointDescIndex]) then
            table.insert(lifts, implement)
        end
    end
    if #lifts > 0 and (breakdown.effectTargetIndex <= 0 or breakdown.effectTargetIndex > #lifts) then
        breakdown.effectTargetIndex = math.random(1, #lifts)
        RealisticMechanicalSystems.raiseRMSDirty(vehicle, RealisticMechanicalSystems.SYNC_GROUP.BREAKDOWNS)
    end

    local state = getEffectState(vehicle, "HYDRAULIC_HOLD_DRIFT_EFFECT")
    local drift = spec.activeEffects.HYDRAULIC_HOLD_DRIFT_EFFECT.value
    local kept = {}
    for index, implement in ipairs(lifts) do
        local joint = attacherSpec.attacherJoints[implement.jointDescIndex]
        if index == breakdown.effectTargetIndex and not joint.moveDown and not getIsFoldedAway(implement.object) then
            local sag = state.sags[joint]
            local massRatio = getHydraulicMassRatio(vehicle, spec.hydraulicLiftMassByJoint[joint] or 0)
            if sag == nil and massRatio > 0 then
                sag = { top = joint.upperAlpha, share = math.max(drift * massRatio, 0.01) }
            end
            if sag ~= nil then
                local step = math.abs(joint.lowerAlpha - sag.top) * sag.share * dt / joint.moveDefaultTime
                joint.upperAlpha = joint.upperAlpha + math.clamp(joint.lowerAlpha - joint.upperAlpha, -step, step)
                if joint.upperAlpha == joint.lowerAlpha then
                    -- on the ground it counts as lowered, one press raises it
                    joint.upperAlpha = sag.top
                    vehicle:setJointMoveDown(implement.jointDescIndex, true, false)
                else
                    state.sags[joint], kept[joint] = sag, true
                end
            end
        end
    end
    restoreLiftRanges(state, kept)
end

RMS_Breakdowns.EffectApplicators.HYDRAULIC_HOLD_DRIFT_EFFECT = {
    apply = function(vehicle)
        local state = getEffectState(vehicle, "HYDRAULIC_HOLD_DRIFT_EFFECT")
        state.sags = state.sags or {}
        startFrameUpdate(vehicle, "HYDRAULIC_HOLD_DRIFT_EFFECT", updateHoldDrift)
    end,

    remove = function(vehicle)
        restoreLiftRanges(getEffectState(vehicle, "HYDRAULIC_HOLD_DRIFT_EFFECT"), {})
        stopFrameUpdate(vehicle, "HYDRAULIC_HOLD_DRIFT_EFFECT")
    end
}

---Returns the speed share of every hydraulic function, set by the pump and the fluid
-- @param table vehicle vehicle
-- @param table effects active effects
-- @return float share share of the speed
local function getHydraulicSpeedShare(vehicle, effects)
    local pump = effects.HYDRAULIC_SPEED_MODIFIER
    return math.max(1 + RMS_Fluids.getHydraulicSpeedModifier(vehicle, pump ~= nil and pump.value or 0), 0)
end

---Returns the speed share of a function on a sticking spool valve, moving one update in two
-- @param table? effect erratic function effect
-- @return float share share of the speed
local function getErraticShare(effect)
    local isFlowing = math.floor(g_currentMission.time / RMS_Config.CORE_UPDATE_DELAY) % 2 == 0
    if effect == nil then
        return 1
    end
    return isFlowing and 1 + effect.value or 0
end

---Returns the share of its speed a lift joint moves at under the faults
-- @param table joint attacher joint
-- @param table faults hydraulic faults of the machine
-- @return float share share of the speed
local function getLiftJointShare(joint, faults)
    if faults.isLiftFailed or joint == faults.blocked then
        return 0
    end
    local share = joint.moveDown and 1 or faults.raise
    if joint == faults.erratic then
        share = share * faults.erraticShare
    end
    return share
end

---Slows or stops the lift joints by the hydraulic faults of the machine
-- @param table self vehicle
-- @param function superFunc original function
-- @param float dt time since the last call (ms)
-- @param any ... further arguments of the game's function
-- @return any result what the game's function returns
function RMS_Breakdowns.applyHydraulicDamageToAttacher(self, superFunc, dt, ...)
    local rootVehicle = self:getRootVehicle()
    local spec = getLoadedSpec(rootVehicle)
    if spec == nil then
        return superFunc(self, dt, ...)
    end

    local effects = spec.activeEffects
    local faults = { raise = getHydraulicSpeedShare(rootVehicle, effects),
        isLiftFailed = effects.LIFT_CONTROL_FAILURE ~= nil, blocked = getHydraulicTarget(spec, "HYDRAULIC_FUNCTION_BLOCKED_EFFECT"),
        erratic = getHydraulicTarget(spec, "HYDRAULIC_FUNCTION_ERRATIC_EFFECT"),
        erraticShare = getErraticShare(effects.HYDRAULIC_FUNCTION_ERRATIC_EFFECT) }

    local attacherSpec = self.spec_attacherJoints
    local stockTimes = {}
    for _, implement in pairs(attacherSpec.attachedImplements) do
        local joint = attacherSpec.attacherJoints[implement.jointDescIndex]
        if implement.object ~= nil and RMS_Utils.getIsHydraulicLiftJoint(joint) then
            local share = getLiftJointShare(joint, faults)
            if share ~= 1 then
                local stock = { share = share, defaultTime = joint.moveDefaultTime, time = joint.moveTime }
                joint.moveDefaultTime = share > 0 and stock.defaultTime / share or math.huge
                joint.moveTime = share > 0 and stock.time / share or math.huge
                stock.slowedTime = joint.moveTime
                stockTimes[joint] = stock
            end
        end
    end

    local result = superFunc(self, dt, ...)

    -- a time the game computed on the slowed one goes back to its own speed
    for joint, stock in pairs(stockTimes) do
        joint.moveDefaultTime = stock.defaultTime
        if joint.moveTime == stock.slowedTime or stock.share == 0 then
            joint.moveTime = stock.time
        else
            joint.moveTime = joint.moveTime * stock.share
        end
    end
    return result
end

---Slows or stops the hydraulic cylinders by the faults of the machine
-- @param table self vehicle
-- @param function superFunc original function
-- @param float dt time since the last call (ms)
-- @param any ... further arguments of the game's function
-- @return any result what the game's function returns
function RMS_Breakdowns.applyHydraulicDamageToCylindered(self, superFunc, dt, ...)
    local rootVehicle = self:getRootVehicle()
    local spec = getLoadedSpec(rootVehicle)
    if spec == nil then
        return superFunc(self, dt, ...)
    end

    local effects = spec.activeEffects
    local speed = getHydraulicSpeedShare(rootVehicle, effects)
    local erratic = getHydraulicTarget(spec, "HYDRAULIC_FUNCTION_ERRATIC_EFFECT")
    local blocked = getHydraulicTarget(spec, "HYDRAULIC_FUNCTION_BLOCKED_EFFECT")
    local loader = effects.LOADER_CONTROL_EFFECT
    local stockSpeeds = {}
    for _, tool in ipairs(self.spec_cylindered.movingTools) do
        if RMS_Utils.getIsHydraulicMovingTool(tool) then
            local share = speed
            if tool == erratic then
                share = share * getErraticShare(effects.HYDRAULIC_FUNCTION_ERRATIC_EFFECT)
            end
            if tool == blocked then
                share = 0
            end
            if loader ~= nil and RMS_Utils.getIsLoaderMovingTool(tool) then
                share = share * (1 + loader.value)
            end
            if share ~= 1 then
                stockSpeeds[tool] = { tool.rotSpeed, tool.transSpeed, tool.animSpeed }
                tool.rotSpeed = tool.rotSpeed ~= nil and tool.rotSpeed * share or nil
                tool.transSpeed = tool.transSpeed ~= nil and tool.transSpeed * share or nil
                tool.animSpeed = tool.animSpeed ~= nil and tool.animSpeed * share or nil
            end
        end
    end

    local result = superFunc(self, dt, ...)

    for tool, speeds in pairs(stockSpeeds) do
        tool.rotSpeed, tool.transSpeed, tool.animSpeed = speeds[1], speeds[2], speeds[3]
    end
    return result
end

---Slows the attacher joint an implement steers by the pump faults
-- @param table self vehicle
-- @param function superFunc original function
-- @param float dt time since the last call (ms)
-- @param any ... further arguments of the game's function
-- @return any result what the game's function returns
function RMS_Breakdowns.applyHydraulicDamageToAttacherJointControl(self, superFunc, dt, ...)
    local rootVehicle = self:getRootVehicle()
    local spec = getLoadedSpec(rootVehicle)
    local joint = self.spec_attacherJointControl.jointDesc
    local share = spec ~= nil and getHydraulicSpeedShare(rootVehicle, spec.activeEffects) or 1
    if share == 1 or joint == nil then
        return superFunc(self, dt, ...)
    end

    local moveTime = joint.moveTime
    joint.moveTime = share > 0 and moveTime / share or math.huge
    local result = superFunc(self, dt, ...)
    joint.moveTime = moveTime
    return result
end

---Spaces the blows of a hydraulic hammer by the pump faults
-- @param table self vehicle
-- @param function superFunc original function
-- @param any ... arguments of the game's function
-- @return any result what the game's function returns, false without pump
function RMS_Breakdowns.applyHydraulicDamageToHammer(self, superFunc, ...)
    local rootVehicle = self:getRootVehicle()
    local spec = getLoadedSpec(rootVehicle)
    local share = spec ~= nil and getHydraulicSpeedShare(rootVehicle, spec.activeEffects) or 1
    if share == 1 then
        return superFunc(self, ...)
    elseif share <= 0 then
        return false
    end

    local workNode = self.spec_hydraulicHammer.workNode
    local intervalMin, intervalMax = workNode.hitIntervalMin, workNode.hitIntervalMax
    workNode.hitIntervalMin, workNode.hitIntervalMax = math.ceil(intervalMin / share), math.ceil(intervalMax / share)
    local result = superFunc(self, ...)
    workNode.hitIntervalMin, workNode.hitIntervalMax = intervalMin, intervalMax
    return result
end

AttacherJoints.onUpdateTick = Utils.overwrittenFunction(AttacherJoints.onUpdateTick, RMS_Breakdowns.applyHydraulicDamageToAttacher)
Cylindered.onUpdate = Utils.overwrittenFunction(Cylindered.onUpdate, RMS_Breakdowns.applyHydraulicDamageToCylindered)
AttacherJointControl.onUpdate = Utils.overwrittenFunction(AttacherJointControl.onUpdate,
    RMS_Breakdowns.applyHydraulicDamageToAttacherJointControl)
HydraulicHammer.hydraulicHammerRaycastCallback = Utils.overwrittenFunction(HydraulicHammer.hydraulicHammerRaycastCallback,
    RMS_Breakdowns.applyHydraulicDamageToHammer)

RMS_Breakdowns.EffectApplicators.MAX_SPEED_MODIFIER = {}

---Lowers the speed limit by worn harvest organs and top speed faults
-- @param table vehicle vehicle
-- @param function superFunc original function
-- @param boolean onlyIfWorking only if working
-- @return float limit speed limit (km/h)
-- @return boolean doCheckSpeedLimit do check speed limit
function RMS_Breakdowns.getSpeedLimitOverwrite(vehicle, superFunc, onlyIfWorking)
    local speedLimit, doCheckSpeedLimit = superFunc(vehicle, onlyIfWorking)
    local spec = getLoadedSpec(vehicle)
    if spec == nil then
        return speedLimit, doCheckSpeedLimit
    end
    local effects = spec.activeEffects

    local throughput = effects.HARVEST_THROUGHPUT_LIMIT
    if throughput ~= nil and speedLimit < math.huge and vehicle:getIsTurnedOn() then
        speedLimit = speedLimit * (1 - throughput.value)
    end

    local topSpeed = effects.MAX_SPEED_MODIFIER
    if topSpeed ~= nil then
        if speedLimit == math.huge then
            speedLimit = vehicle:getMotor().maxForwardSpeedOrigin * 3.6
        end
        speedLimit = speedLimit - speedLimit * topSpeed.value
    end
    return speedLimit, doCheckSpeedLimit
end

-- {spec field, value at rest, lowest value}, rest + effect value
local SPEC_VALUES = {
    ENGINE_HEAT_MODIFIER = { "extraEngineHeat", 0 },
    TRANSMISSION_HEAT_MODIFIER = { "extraTransmissionHeat", 0 },
    HYDRAULIC_HEAT_MODIFIER = { "extraHydraulicHeat", 0 },
    ELECTRICAL_LEAKAGE_EFFECT = { "circuitLeakageFactor", 0 },
    ELECTRICAL_CONTACT_RESISTANCE_EFFECT = { "circuitResistanceFactor", 0 },
    COOLANT_LEAK_RATE = { "coolantLeakRate", 0 },
    TRANSMISSION_OIL_LEAK_RATE = { "transmissionOilLeakRate", 0 },
    HYDRAULIC_FLUID_LEAK_RATE = { "hydraulicFluidLeakRate", 0 },
    THERMOSTAT_HEALTH_MODIFIER = { "thermostatHealth", 1 },
    RADIATOR_HEALTH_MODIFIER = { "radiatorHealth", 1 },
    FAN_CLUTCH_MODIFIER = { "fanClutchHealth", 1 },
    BATTERY_HEALTH_MODIFIER = { "batteryHealth", 1, 0.0001 },
    ALTERNATOR_HEALTH_MODIFIER = { "alternatorHealth", 1, 0.0001 },
    STARTER_HEALTH_MODIFIER = { "starterHealth", 1 }
}

for effectId, field in pairs(SPEC_VALUES) do
    local name, rest, lowest = field[1], field[2], field[3] or -math.huge
    RMS_Breakdowns.EffectApplicators[effectId] = {
        apply = function(vehicle, effect) vehicle.spec_RealisticMechanicalSystems[name] = math.max(rest + effect.value, lowest) end,
        remove = function(vehicle) vehicle.spec_RealisticMechanicalSystems[name] = rest end
    }
end

---Sets the drag of the park brake
-- @param table vehicle vehicle
-- @param float drag drag
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

---Swings the idle around the stock one, a share of it over a period
-- @param table vehicle vehicle
-- @param table swing state of the swing
-- @param table effect effect of the swing
-- @param float dt time of the step (ms)
local function swingIdle(vehicle, swing, effect, dt)
    swing.timer = swing.timer + dt
    local stockIdle = vehicle.spec_RealisticMechanicalSystems.stockIdleRpm
    vehicle:getMotor().minRpm = stockIdle * (1 + effect.value * math.sin(2 * math.pi * swing.timer / effect.extraData.period))
end

---Starts an idle swing, the stock idle kept while either swing runs
-- @param table vehicle vehicle
-- @param string effectName effect
-- @param function update update run each step
local function startIdleSwing(vehicle, effectName, update)
    local spec = vehicle.spec_RealisticMechanicalSystems
    spec.stockIdleRpm = spec.stockIdleRpm or vehicle:getMotor().minRpm
    startFrameUpdate(vehicle, effectName, update)
end

---Stops an idle swing, the stock idle back
-- @param table vehicle vehicle
-- @param string effectName effect
-- @param string otherName effect of the other swing
local function stopIdleSwing(vehicle, effectName, otherName)
    local spec = vehicle.spec_RealisticMechanicalSystems
    stopFrameUpdate(vehicle, effectName)
    if spec.stockIdleRpm ~= nil then
        vehicle:getMotor().minRpm = spec.stockIdleRpm
    end
    if spec.activeEffects[otherName] == nil then
        spec.stockIdleRpm = nil
    end
end

---Swings the idle of a standing machine, extraData {period in ms}
-- @param table vehicle vehicle
-- @param float dt time of the step (ms)
local function updateIdleHunting(vehicle, dt)
    local spec = vehicle.spec_RealisticMechanicalSystems
    local swing = getEffectState(vehicle, "IDLE_HUNTING_EFFECT")
    if vehicle:getIsMotorStarted() and vehicle:getLastSpeed() < 0.01 then
        swingIdle(vehicle, swing, spec.activeEffects.IDLE_HUNTING_EFFECT, dt)
    elseif vehicle:getMotor().minRpm ~= spec.stockIdleRpm then
        vehicle:getMotor().minRpm = spec.stockIdleRpm
        swing.timer = 0
    end
end

RMS_Breakdowns.EffectApplicators.IDLE_HUNTING_EFFECT = {
    apply = function(vehicle) startIdleSwing(vehicle, "IDLE_HUNTING_EFFECT", updateIdleHunting) end,
    remove = function(vehicle) stopIdleSwing(vehicle, "IDLE_HUNTING_EFFECT", "GLOW_PLUG_COLD_IDLE_EFFECT") end
}

---Swings the idle of a cold engine on bad glow plugs, unless the idle already hunts
-- @param table vehicle vehicle
-- @param float dt time of the step (ms)
local function updateGlowPlugColdIdle(vehicle, dt)
    local spec = vehicle.spec_RealisticMechanicalSystems
    local swing = getEffectState(vehicle, "GLOW_PLUG_COLD_IDLE_EFFECT")
    local isHunting = spec.activeEffects.IDLE_HUNTING_EFFECT ~= nil
    if spec.preheatColdStartFaultSeverity >= 2 and spec.rawEngineTemperature < RMS_Config.CORE.ENGINE_FACTOR_DATA.COLD_MOTOR_TEMP_THRESHOLD
        and vehicle:getIsMotorStarted() and vehicle:getLastSpeed() < 0.01 and not isHunting then
        swingIdle(vehicle, swing, spec.activeEffects.GLOW_PLUG_COLD_IDLE_EFFECT, dt)
        return
    end
    swing.timer = 0
    if not isHunting then
        vehicle:getMotor().minRpm = spec.stockIdleRpm
    end
end

RMS_Breakdowns.EffectApplicators.GLOW_PLUG_COLD_IDLE_EFFECT = {
    apply = function(vehicle) startIdleSwing(vehicle, "GLOW_PLUG_COLD_IDLE_EFFECT", updateGlowPlugColdIdle) end,
    remove = function(vehicle) stopIdleSwing(vehicle, "GLOW_PLUG_COLD_IDLE_EFFECT", "IDLE_HUNTING_EFFECT") end
}

---Stops a noise and puts its sample back as loaded
-- @param table sample sample
local function silenceNoise(sample)
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

local NOISE_ATTACK_MS = 220
local NOISE_RELEASE_MS = 520
local NOISE_MIN_VOLUME = 0.02
local TURBO_BOOST_START = 0.02

---Returns the noise eased toward the share of its cause, faster in than out
-- @param table noise state of the noise
-- @param float target share of its cause, 0 to 1
-- @param float dt time of the step (ms)
-- @return float gate share, 0 to 1
local function easeNoiseGate(noise, target, dt)
    local gate = noise.gate or 0
    local share = math.min(dt / (target > gate and NOISE_ATTACK_MS or NOISE_RELEASE_MS), 1)
    noise.gate = gate + (target - gate) * share
    return noise.gate
end

local KNOCK_RECORDING_RPM = { engineKnocking = 670, pistonSlap = 580, valveTrainNoise = 710, injectorKnock = 1620, highPressurePump = 800 }
local CRANK_DRIVEN_NOISES = { waterPumpBearing = true, accessoryBelt = true, fanNoice = true, fanBladeImbalance = true,
    transmissionPump = true, hydraulicPump = true, engineKnocking = true, pistonSlap = true, valveTrainNoise = true,
    highPressurePump = true }
-- {full speed in m/s, pitch at full speed, exponent, pitch of the load}
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
local CLUNK_LOAD_MS = 500
local BUMP_STROKE_MS = 500

---Tells whether the steering moves
-- @param table vehicle vehicle
-- @param table noise state of the noise
-- @param float dt time of the step (ms)
-- @return boolean isMoving true while it moves
local function getIsSteeringMoving(vehicle, noise, dt)
    local lock = vehicle.rotatedTime >= 0 and vehicle.maxRotTime or -vehicle.minRotTime
    local position = lock > 0 and vehicle.rotatedTime / lock or 0
    local lastPosition = noise.steering or position
    noise.steering = position
    return math.abs(position - lastPosition) / (dt * 0.001) > RMS_Config.CORE.CHASSIS_FACTOR_DATA.STEER_LOAD_RATE_DEADZONE
end

---Tells whether a loader arm moves
-- @param table vehicle vehicle
-- @param table noise state of the noise
-- @return boolean isMoving true while one moves
local function getIsLoaderMoving(vehicle, noise)
    noise.positions = noise.positions or {}
    local isMoving = false
    for _, tool in ipairs(vehicle.spec_cylindered.movingTools) do
        if RMS_Utils.getIsLoaderMovingTool(tool) then
            local position = tool.curRot[tool.rotationAxis] + tool.curTrans[tool.translationAxis]
            isMoving = isMoving or noise.positions[tool] ~= nil and position ~= noise.positions[tool]
            noise.positions[tool] = position
        end
    end
    return isMoving
end

---Tells whether the front shafts take up their play as the drive changes direction
-- @param table vehicle vehicle
-- @param table noise state of the noise
-- @param float dt time of the step (ms)
-- @return boolean isTakenUp true while they take it up
local function getIsFrontDriveTakenUp(vehicle, noise, dt)
    local direction = vehicle:getLastSpeed() > 0.5 and vehicle.movingDirection or 0
    if direction ~= 0 and direction ~= (noise.direction or 0) and RMS_Drivetrain.getIsFrontAxleDriven(vehicle) then
        noise.loadedFor = CLUNK_LOAD_MS
    end
    noise.direction = direction
    noise.loadedFor = math.max((noise.loadedFor or 0) - dt, 0)
    return noise.loadedFor > 0
end

---Tells whether the cab bumps, a wheel stroking faster than its travel in half a second
-- @param table vehicle vehicle
-- @param table noise state of the noise
-- @param float dt time of the step (ms)
-- @return boolean isBumping true while it bumps
local function getIsCabBumping(vehicle, noise, dt)
    noise.lengths = noise.lengths or {}
    for index, wheel in ipairs(vehicle.spec_wheels.wheels) do
        local length = wheel.physics.netInfo.suspensionLength
        local lastLength = noise.lengths[index] or length
        noise.lengths[index] = length
        if math.abs(length - lastLength) / wheel.physics.suspTravel > dt / BUMP_STROKE_MS then
            noise.loadedFor = CLUNK_LOAD_MS
        end
    end
    noise.loadedFor = math.max((noise.loadedFor or 0) - dt, 0)
    return noise.loadedFor > 0
end

---Creates the applicator of worn joints knocking while their part moves, louder as they wear
-- @param string effectName effect
-- @param string sampleName sample
-- @param function getIsMoving tells whether the part moves
-- @return table applicator apply and remove
local function createClunkEffectApplicator(effectName, sampleName, getIsMoving)
    ---Knocks by chance while the part moves
    -- @param table vehicle vehicle
    -- @param float dt time of the step (ms)
    local function update(vehicle, dt)
        local spec = vehicle.spec_RealisticMechanicalSystems
        local effect, sample = spec.activeEffects[effectName], spec.samples[sampleName]
        if sample == nil or not vehicle:getIsMotorStarted() then
            return
        end
        if getIsMoving(vehicle, getEffectState(vehicle, effectName), dt)
            and math.random() < RMS_Utils.getChancePerFrameFromMeanTime(dt, CLUNK_MEAN_SECONDS / effect.value / 60) then
            sample.rmsOriginalVolumeScale = sample.rmsOriginalVolumeScale or sample.volumeScale
            sample.volumeScale = sample.rmsOriginalVolumeScale * effect.value
            RMS_SoundManager.playSample(sample)
        end
    end
    return {
        apply = function(vehicle) startFrameUpdate(vehicle, effectName, update) end,
        remove = function(vehicle) stopFrameUpdate(vehicle, effectName) end
    }
end

-- each gate turns a reading of the machine into the share of the noise
local NOISE_GATES = {
    boost = function(_, _, reading) return math.clamp((reading.boost - TURBO_BOOST_START) / (1 - TURBO_BOOST_START), 0, 1) end,
    speed = function(_, _, reading) return math.clamp((reading.speed - 0.2) / 1.8, 0, 1) end,
    pto = function(_, _, reading) return reading.pto.isActive and reading.pto.rpm > 0 and 1 or 0 end,
    harvest = function(vehicle) return vehicle.getIsTurnedOn ~= nil and vehicle:getIsTurnedOn() and 1 or 0 end,
    steer = function(vehicle, noise, reading) return getIsSteeringMoving(vehicle, noise, reading.dt) and 1 or 0 end,
    hot = function(_, _, reading) return reading.hot end
}

---Returns the pitch of a noise by its cause
-- @param string sampleName sample
-- @param table reading reading of the machine
-- @param float gate share of the noise, 0 to 1
-- @return float pitch pitch offset
local function getNoisePitch(sampleName, reading, gate)
    local speedPitch = SPEED_PITCH[sampleName]
    if KNOCK_RECORDING_RPM[sampleName] ~= nil then
        return reading.lastRpm / KNOCK_RECORDING_RPM[sampleName] - 1
    elseif sampleName == "turboWhistle" then
        local boost = math.clamp((reading.boost - TURBO_BOOST_START) / (1 - TURBO_BOOST_START), 0, 1)
        return (0.20 * boost + 0.16 * (reading.rpm ^ 1.20) * boost + 0.03 * reading.load * boost) * gate
    elseif speedPitch ~= nil then
        local speed = math.clamp(reading.speed / speedPitch[1], 0, 1)
        return (speedPitch[2] * (speed ^ speedPitch[3]) + speedPitch[4] * reading.load * speed) * gate
    elseif FIXED_PITCH[sampleName] then
        return 0
    end
    local intensity = (0.30 + 0.70 * reading.rpm) * (0.65 + 0.35 * reading.load) * (0.70 + 0.30 * reading.hot)
    return 0.24 * (reading.rpm ^ 1.35) + 0.04 * intensity * reading.rpm
end

---Reads the engine speed, load and heat a noise follows, as shares
-- @param table vehicle vehicle
-- @param table motor motor
-- @param string? gateName gate of the noise
-- @param float crankRpm engine speed the starter gives (rpm), 0 while it does not turn the engine
-- @param float dt time of the step (ms)
-- @return table reading reading of the machine
local function readNoiseCause(vehicle, motor, gateName, crankRpm, dt)
    local spec = vehicle.spec_RealisticMechanicalSystems
    local reading = { dt = dt, lastRpm = math.max(motor:getLastModulatedMotorRpm(), crankRpm),
        load = math.clamp(RMS_Utils.getMotorLoad(vehicle), 0, 1),
        boost = math.clamp(motor.lastTurboScale, 0, 1), hot = math.clamp((spec.engineTemperature - 70) / 40, 0, 1),
        speed = vehicle:getLastSpeed() / 3.6 }
    local rpm = reading.lastRpm
    if gateName == "pto" then
        reading.pto = RMS_Utils.getConnectedPtoData(vehicle)
        rpm = math.max(reading.pto.rpm, 0) * motor:getPtoMotorRpmRatio()
    end
    reading.rpm = math.clamp((rpm - motor.minRpm) / math.max(motor.maxRpm - motor.minRpm, 1), 0, 1)
    return reading
end

---Creates the applicator of a worn part sounding while the engine runs, or while the starter turns a part the crankshaft drives, gated by what moves it
-- @param string effectName effect
-- @param string sampleName sample
-- @param string? gateName gate of the noise, nil while the engine runs
-- @return table applicator apply and remove
local function createEngineNoiseEffectApplicator(effectName, sampleName, gateName)
    ---Plays the noise at the volume and pitch of its cause
    -- @param table vehicle vehicle
    -- @param float dt time of the step (ms)
    local function update(vehicle, dt)
        local spec = vehicle.spec_RealisticMechanicalSystems
        local sample = spec.samples[sampleName]
        if sample == nil then
            return
        end
        local noise = getEffectState(vehicle, effectName)
        local crankSpeed = 0
        if CRANK_DRIVEN_NOISES[sampleName] and RMS_Start.getIsCranking(vehicle) then
            crankSpeed = RMS_Electrical.getCrankingSpeed(vehicle)
        end
        if not vehicle:getIsMotorStarted() and crankSpeed <= 0 then
            silenceNoise(sample)
            noise.gate = nil
            return
        end

        local crankRpm = 0
        if not spec.isElectricVehicle then
            crankRpm = crankSpeed * RMS_Config.ELECTRICAL.CRANKING_RPM
        end
        local motor = vehicle:getMotor()
        local reading = readNoiseCause(vehicle, motor, gateName, crankRpm, dt)
        local volume = math.clamp(spec.activeEffects[effectName].value, 0, 2)
        local gate = 1
        if gateName ~= nil then
            gate = easeNoiseGate(noise, NOISE_GATES[gateName](vehicle, noise, reading), dt)
            volume = volume * gate
        end
        if volume <= NOISE_MIN_VOLUME then
            if gateName == nil or gate <= 0.001 then
                silenceNoise(sample)
                noise.gate = nil
                return
            end
            volume = NOISE_MIN_VOLUME
        end

        sample.rmsOriginalLoops = sample.rmsOriginalLoops or sample.loops
        sample.rmsOriginalVolumeScale = sample.rmsOriginalVolumeScale or sample.volumeScale
        sample.loops = 0
        sample.volumeScale = sample.rmsOriginalVolumeScale * volume
        RMS_SoundManager.setSamplePlaying(sample, true)
        RMS_SoundManager.setSampleVolumeOffset(sample, 0)
        RMS_SoundManager.setSamplePitchOffset(sample, getNoisePitch(sampleName, reading, gate))
    end

    return {
        apply = function(vehicle) startFrameUpdate(vehicle, effectName, update) end,
        remove = function(vehicle)
            local sample = vehicle.spec_RealisticMechanicalSystems.samples[sampleName]
            if sample ~= nil then
                silenceNoise(sample)
            end
            stopFrameUpdate(vehicle, effectName)
        end
    }
end

-- effect id, sample, gate: what lets the noise be heard
for _, noise in ipairs({
    { "ENGINE_KNOCKING_NOISE_EFFECT", "engineKnocking" },
    { "VALVE_TRAIN_NOISE_EFFECT", "valveTrainNoise" },
    { "TURBO_WHISTLE_NOISE_EFFECT", "turboWhistle", "boost" },
    { "FAN_CLUTCH_NOISE_EFFECT", "fanNoice" },
    { "FAN_BLADE_NOISE_EFFECT", "fanBladeImbalance" },
    { "TRACK_CLATTER_NOISE_EFFECT", "trackClatter", "speed" },
    { "WHEEL_HUB_BEARING_NOISE_EFFECT", "wheelHubBearingNoise", "speed" },
    { "WHEEL_SEIZURE_GRIND_NOISE_EFFECT", "wheelSeizureGrind", "speed" },
    { "PTO_BEARING_NOISE_EFFECT", "ptoBearingNoise", "pto" },
    { "GEAR_WHINE_NOISE_EFFECT", "gearWhineNoise", "speed" },
    { "GEARBOX_BEARING_NOISE_EFFECT", "gearboxBearingNoise", "speed" },
    { "PISTON_SLAP_NOISE_EFFECT", "pistonSlap" },
    { "INJECTOR_KNOCK_NOISE_EFFECT", "injectorKnock" },
    { "HIGH_PRESSURE_PUMP_NOISE_EFFECT", "highPressurePump" },
    { "BELT_SQUEAL_NOISE_EFFECT", "accessoryBelt" },
    { "WATER_PUMP_BEARING_NOISE_EFFECT", "waterPumpBearing" },
    { "TRANSMISSION_PUMP_NOISE_EFFECT", "transmissionPump" },
    { "HYDROSTATIC_WHINE_NOISE_EFFECT", "hydrostaticWhine", "speed" },
    { "HYDRAULIC_PUMP_NOISE_EFFECT", "hydraulicPump" },
    { "COOLANT_STEAM_NOISE_EFFECT", "coolantSteam", "hot" },
    { "GAS_LEAK_NOISE_EFFECT", "gasLeak" },
    { "PARK_BRAKE_DRAG_NOISE_EFFECT", "parkBrakeDrag", "speed" },
    { "STEERING_ORBITROL_NOISE_EFFECT", "steeringOrbitrol", "steer" },
    { "TRACK_ROLLER_NOISE_EFFECT", "trackRoller", "speed" },
    { "PTO_SPLINES_NOISE_EFFECT", "ptoSplines", "pto" },
    { "HARVEST_BEARING_NOISE_EFFECT", "ptoBearingNoise", "harvest" },
    { "HEADER_BELT_SQUEAL_NOISE_EFFECT", "headerBelt", "harvest" },
    { "ELECTRIC_MOTOR_BEARING_NOISE_EFFECT", "electricMotorBearing", "speed" }
}) do
    RMS_Breakdowns.EffectApplicators[noise[1]] = createEngineNoiseEffectApplicator(noise[1], noise[2], noise[3])
end

-- circuit = {effect of the pump's faults, sample}
local AERATION_WHINES = { transmissionOil = { "TRANSMISSION_PUMP_NOISE_EFFECT", "transmissionPump" },
    hydraulicFluid = { "HYDRAULIC_PUMP_NOISE_EFFECT", "hydraulicPump" } }
local AERATION_WHINE_VOLUME = 0.8

---Makes a pump whine while it draws air, its faults aside
-- @param table vehicle vehicle
function RMS_Breakdowns.updateAerationWhines(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    for circuit, whine in pairs(AERATION_WHINES) do
        local sample = spec.samples[whine[2]]
        if sample ~= nil and spec.activeEffects[whine[1]] == nil then
            local isWhining = spec.pickupUncovered[circuit] == true and vehicle:getIsMotorStarted()
            if isWhining then
                sample.rmsOriginalLoops = sample.rmsOriginalLoops or sample.loops
                sample.rmsOriginalVolumeScale = sample.rmsOriginalVolumeScale or sample.volumeScale
                sample.loops = 0
                sample.volumeScale = sample.rmsOriginalVolumeScale * AERATION_WHINE_VOLUME
                RMS_SoundManager.setSamplePlaying(sample, true)
            elseif spec.aerationWhining[circuit] then
                silenceNoise(sample)
            end
            spec.aerationWhining[circuit] = isWhining
        else
            spec.aerationWhining[circuit] = false
        end
    end
end

---Makes the slip clutch of a header heard while it slips
-- @param table vehicle vehicle
function RMS_Breakdowns.updateHeaderSlip(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    local sample = spec.samples.headerSlipClutch
    if sample == nil then
        return
    end
    local isSlipping = spec.isHeaderSlipping and vehicle:getIsMotorStarted()
    if isSlipping then
        sample.rmsOriginalLoops = sample.rmsOriginalLoops or sample.loops
        sample.loops = 0
        RMS_SoundManager.setSamplePlaying(sample, true)
    elseif spec.isHeaderSlipHeard then
        silenceNoise(sample)
    end
    spec.isHeaderSlipHeard = isSlipping
end

RMS_Breakdowns.EffectApplicators.STEERING_LINKAGE_NOISE_EFFECT = createClunkEffectApplicator("STEERING_LINKAGE_NOISE_EFFECT",
    "steeringLinkage", getIsSteeringMoving)
RMS_Breakdowns.EffectApplicators.STEERING_KNUCKLE_NOISE_EFFECT = createClunkEffectApplicator("STEERING_KNUCKLE_NOISE_EFFECT",
    "steeringKnuckle", getIsSteeringMoving)
RMS_Breakdowns.EffectApplicators.LOADER_PINS_NOISE_EFFECT = createClunkEffectApplicator("LOADER_PINS_NOISE_EFFECT", "loaderPins",
    getIsLoaderMoving)
RMS_Breakdowns.EffectApplicators.FRONT_AXLE_SHAFT_NOISE_EFFECT = createClunkEffectApplicator("FRONT_AXLE_SHAFT_NOISE_EFFECT",
    "frontAxleShaft", getIsFrontDriveTakenUp)
RMS_Breakdowns.EffectApplicators.CAB_DAMPER_NOISE_EFFECT = createClunkEffectApplicator("CAB_DAMPER_NOISE_EFFECT", "cabDamper",
    getIsCabBumping)

---Creates the applicator of a part bursting, heard once, never again from a save or a join
-- @param string effectName effect
-- @param string sampleName sample
-- @param function getIsDriven tells whether the part is driven
-- @return table applicator apply and remove
local function createBurstSoundApplicator(effectName, sampleName, getIsDriven)
    return {
        apply = function(vehicle, _, _, isRestoring)
            local burst = getEffectState(vehicle, effectName)
            if burst.status == "IDLE" then
                burst.status = "BURST"
                if not isRestoring and getIsDriven(vehicle) then
                    RMS_SoundManager.playSample(vehicle.spec_RealisticMechanicalSystems.samples[sampleName])
                end
            end
        end,
        remove = function(vehicle) stopFrameUpdate(vehicle, effectName) end
    }
end

RMS_Breakdowns.EffectApplicators.HOSE_BURST_NOISE_EFFECT = createBurstSoundApplicator("HOSE_BURST_NOISE_EFFECT", "hoseBurst",
    function(vehicle) return vehicle:getIsMotorStarted() end)
RMS_Breakdowns.EffectApplicators.HEADER_SHAFT_BREAK_NOISE_EFFECT = createBurstSoundApplicator("HEADER_SHAFT_BREAK_NOISE_EFFECT",
    "headerShaftBreak", function(vehicle) return vehicle:getIsMotorStarted() end)
RMS_Breakdowns.EffectApplicators.PTO_SHAFT_BREAK_NOISE_EFFECT = createBurstSoundApplicator("PTO_SHAFT_BREAK_NOISE_EFFECT", "ptoShaftBreak",
    function(vehicle)
        local ptoData = RMS_Utils.getConnectedPtoData(vehicle)
        return ptoData.isActive and ptoData.rpm > 0
    end)

---Drops the variator pressure by chance, extraData {duration in ms}
-- @param table vehicle vehicle
-- @param float dt time of the step (ms)
local function updatePressureDrop(vehicle, dt)
    if not vehicle:getIsMotorStarted() or vehicle:getLastSpeed() <= 1 then
        return
    end
    local drop = getEffectState(vehicle, "CVT_PRESSURE_DROP_CHANCE")
    local effect = vehicle.spec_RealisticMechanicalSystems.activeEffects.CVT_PRESSURE_DROP_CHANCE
    if drop.timer > 0 then
        drop.timer = math.max(drop.timer - dt, 0)
    elseif vehicle.isServer and math.random() < RMS_Utils.getChancePerFrameFromMeanTime(dt, effect.value) then
        drop.timer = math.max(effect.extraData.duration - dt, 0)
    end
end

RMS_Breakdowns.EffectApplicators.CVT_PRESSURE_DROP_CHANCE = {
    apply = function(vehicle)
        if vehicle:getMotor().minForwardGearRatio ~= nil then
            startFrameUpdate(vehicle, "CVT_PRESSURE_DROP_CHANCE", updatePressureDrop)
        end
    end,
    remove = function(vehicle) stopFrameUpdate(vehicle, "CVT_PRESSURE_DROP_CHANCE") end
}

---Stalls the engine by chance, the effect value a mean time in minutes; a helper drives on
-- @param table vehicle vehicle
-- @param float dt time of the step (ms)
local function updateEngineStalls(vehicle, dt)
    local effect = vehicle.spec_RealisticMechanicalSystems.activeEffects.ENGINE_STALLS_CHANCE
    if vehicle.isServer and vehicle:getIsMotorStarted() and not vehicle:getIsAIActive()
        and math.random() < RMS_Utils.getChancePerFrameFromMeanTime(dt, effect.value) then
        vehicle:stopMotor()
        RMS_EffectSyncEvent.send(vehicle, "ENGINE_STALLS_CHANCE", "STALLED")
        showWarning(vehicle, "rms_breakdowns_engine_stalled_message", 5000)
    end
end

RMS_Breakdowns.EffectApplicators.ENGINE_STALLS_CHANCE = {
    apply = function(vehicle) startFrameUpdate(vehicle, "ENGINE_STALLS_CHANCE", updateEngineStalls) end,
    remove = function(vehicle) stopFrameUpdate(vehicle, "ENGINE_STALLS_CHANCE") end
}

-- first year a shaft can drop by itself
local PTO_DROP_FIRST_YEAR = 1990

RMS_Breakdowns.WORK_STOP_MESSAGES = {
    PTO_AUTO_DISENGAGE_CHANCE = "rms_breakdowns_pto_auto_disengage_message",
    FRONT_PTO_AUTO_DISENGAGE_CHANCE = "rms_breakdowns_front_pto_auto_disengage_message",
    HARVEST_BLOCKAGE_CHANCE = "rms_breakdowns_harvest_blockage_message",
    HARVEST_FAILURE = "rms_breakdowns_harvest_failure_message"
}

-- the shaft monitor of a harvester sounds as an organ stops or slows
RMS_Breakdowns.SHAFT_ALARMS = { HARVEST_BLOCKAGE_CHANCE = true, HARVEST_FAILURE = true, CHOPPER_FAILURE = true }

---Sounds the shaft speed alarm in the cab of a harvester
-- @param table vehicle vehicle
function RMS_Breakdowns.soundShaftAlarm(vehicle)
    RMS_SoundManager.playSample(vehicle.spec_RealisticMechanicalSystems.samples.alarm)
end

---Creates the applicator of a PTO dropping out, the effect value a mean time in s between two drops
-- @param string effectName effect
-- @param string side rear or front
-- @return table applicator apply and remove
local function createPtoDropApplicator(effectName, side)
    ---Drops the PTO by chance while it turns
    -- @param table vehicle vehicle
    -- @param float dt time of the step (ms)
    local function update(vehicle, dt)
        local spec = vehicle.spec_RealisticMechanicalSystems
        local effect = spec.activeEffects[effectName]
        if vehicle.isServer and spec.year >= PTO_DROP_FIRST_YEAR and RMS_Utils.getConnectedPtoData(vehicle, side).isActive
            and math.random() < RMS_Utils.getChancePerFrameFromMeanTime(dt, effect.value / 60) then
            RMS_Utils.setConnectedPtoConsumersTurnedOn(vehicle, false, side)
            showWarning(vehicle, RMS_Breakdowns.WORK_STOP_MESSAGES[effectName], 4000)
            RMS_EffectSyncEvent.send(vehicle, effectName, "DISENGAGED")
        end
    end
    return {
        apply = function(vehicle) startFrameUpdate(vehicle, effectName, update) end,
        remove = function(vehicle) stopFrameUpdate(vehicle, effectName) end
    }
end

---Creates the applicator of a broken PTO, holding its consumers off
-- @param string effectName effect
-- @param string side rear or front
-- @return table applicator apply and remove
local function createPtoFailureApplicator(effectName, side)
    ---Holds the consumers of the PTO off
    -- @param table vehicle vehicle
    local function update(vehicle)
        if vehicle.isServer then
            RMS_Utils.setConnectedPtoConsumersTurnedOn(vehicle, false, side)
        end
    end
    return {
        apply = function(vehicle) startFrameUpdate(vehicle, effectName, update) end,
        remove = function(vehicle) stopFrameUpdate(vehicle, effectName) end
    }
end

RMS_Breakdowns.EffectApplicators.PTO_AUTO_DISENGAGE_CHANCE = createPtoDropApplicator("PTO_AUTO_DISENGAGE_CHANCE", "rear")
RMS_Breakdowns.EffectApplicators.PTO_FAILURE = createPtoFailureApplicator("PTO_FAILURE", "rear")
RMS_Breakdowns.EffectApplicators.FRONT_PTO_AUTO_DISENGAGE_CHANCE = createPtoDropApplicator("FRONT_PTO_AUTO_DISENGAGE_CHANCE", "front")
RMS_Breakdowns.EffectApplicators.FRONT_PTO_FAILURE = createPtoFailureApplicator("FRONT_PTO_FAILURE", "front")
RMS_Breakdowns.EffectApplicators.PTO_STUCK_ENGAGED_CHANCE = {}
RMS_Breakdowns.EffectApplicators.PTO_ENGAGEMENT_BLOCKED_CHANCE = {}

---Lowers the threshing of a combine by a loss
-- @param table vehicle vehicle
-- @param float loss share of the threshing lost
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
    apply = function(vehicle, effect)
        setThreshingLoss(vehicle, math.clamp(effect.value, 0, RMS_Config.CORE.HARVEST_FACTOR_DATA.MAX_GRAIN_LOSS))
    end,
    remove = function(vehicle) setThreshingLoss(vehicle, 0) end
}

---Blocks the harvest by chance while crop feeds the machine, the effect value a mean time in minutes
-- @param table vehicle vehicle
-- @param float dt time of the step (ms)
local function updateHarvestBlockage(vehicle, dt)
    local spec = vehicle.spec_RealisticMechanicalSystems
    local state = spec.harvestState
    if vehicle.isServer and vehicle:getIsTurnedOn() and state ~= nil and (state.tonPerHour or 0) > 0
        and math.random() < RMS_Utils.getChancePerFrameFromMeanTime(dt, spec.activeEffects.HARVEST_BLOCKAGE_CHANCE.value) then
        vehicle:setIsTurnedOn(false)
        RealisticMechanicalSystems.onHeaderBlocked(vehicle)
        RMS_Breakdowns.soundShaftAlarm(vehicle)
        showWarning(vehicle, RMS_Breakdowns.WORK_STOP_MESSAGES.HARVEST_BLOCKAGE_CHANCE, 4000)
        RMS_EffectSyncEvent.send(vehicle, "HARVEST_BLOCKAGE_CHANCE", "BLOCKED")
    end
end

RMS_Breakdowns.EffectApplicators.HARVEST_BLOCKAGE_CHANCE = {
    apply = function(vehicle) startFrameUpdate(vehicle, "HARVEST_BLOCKAGE_CHANCE", updateHarvestBlockage) end,
    remove = function(vehicle) stopFrameUpdate(vehicle, "HARVEST_BLOCKAGE_CHANCE") end
}

---Stops the harvest on the alarm as the organ breaks
-- @param table vehicle vehicle
local function stopHarvest(vehicle)
    if vehicle.isServer and vehicle:getIsTurnedOn() then
        vehicle:setIsTurnedOn(false)
        RMS_Breakdowns.soundShaftAlarm(vehicle)
        showWarning(vehicle, RMS_Breakdowns.WORK_STOP_MESSAGES.HARVEST_FAILURE, 4000)
        RMS_EffectSyncEvent.send(vehicle, "HARVEST_FAILURE", "STOPPED")
    end
end

RMS_Breakdowns.EffectApplicators.HARVEST_FAILURE = {
    apply = function(vehicle) startFrameUpdate(vehicle, "HARVEST_FAILURE", stopHarvest) end,
    remove = function(vehicle) stopFrameUpdate(vehicle, "HARVEST_FAILURE") end
}

---Returns the crop in the combine, its grain tank first, then its last cut
-- @param table vehicle vehicle
-- @return table? fruitDesc crop
local function getCombineFruit(vehicle)
    local spec_combine = vehicle.spec_combine
    local fillType = vehicle:getFillUnitFillType(spec_combine.bufferFillUnitIndex or spec_combine.fillUnitIndex)
    local fruitType = g_fruitTypeManager:getFruitTypeIndexByFillTypeIndex(fillType)
    if fruitType == nil or fruitType == FruitType.UNKNOWN then
        fruitType = spec_combine.lastValidInputFruitType
    end
    return g_fruitTypeManager:getFruitTypeByIndex(fruitType)
end

---Tells whether a broken chopper meets a crop the game lays in a swath
-- @param table vehicle vehicle
-- @return boolean isLocked true for such a crop
local function getIsChopperLocked(vehicle)
    local spec = getLoadedSpec(vehicle)
    if spec == nil or spec.activeEffects.CHOPPER_FAILURE == nil or not vehicle.spec_combine.swath.isAvailable then
        return false
    end
    local fruitDesc = getCombineFruit(vehicle)
    return fruitDesc ~= nil and fruitDesc.hasWindrow == true
end

---Holds a broken chopper still: straw in a swath, or falling unchopped
-- @param table vehicle vehicle
local function updateChopperFailure(vehicle)
    local spec_combine = vehicle.spec_combine
    local state = RMS_Breakdowns.getEffectState(vehicle, "CHOPPER_FAILURE")
    if spec_combine == nil or not vehicle:getIsTurnedOn() then
        state.status, state.isStill = "IDLE", nil
        return
    end
    -- the game starts the chopper drive each time the threshing starts
    if vehicle.isClient and not state.isStill then
        state.isStill = true
        g_animationManager:stopAnimations(spec_combine.chopperAnimationNodes)
        g_soundManager:stopSample(spec_combine.samples.chopperStart)
        g_soundManager:stopSample(spec_combine.samples.chopperWork)
    end
    local fruitDesc = getCombineFruit(vehicle)
    if not vehicle.isServer or fruitDesc == nil then
        return
    end
    local isSwath = getIsChopperLocked(vehicle)
    if isSwath and not spec_combine.isSwathActive then
        vehicle:setIsSwathActive(true)
    end
    if state.status == "IDLE" then
        state.status = "ALARMED"
        RMS_Breakdowns.soundShaftAlarm(vehicle)
        RMS_EffectSyncEvent.send(vehicle, "CHOPPER_FAILURE", isSwath and "SWATH" or "UNCHOPPED")
        showWarning(vehicle, isSwath and "rms_breakdowns_chopper_failure_message" or "rms_breakdowns_chopper_failure_unchopped_message", 4000)
    end
end

RMS_Breakdowns.EffectApplicators.CHOPPER_FAILURE = {
    apply = function(vehicle) startFrameUpdate(vehicle, "CHOPPER_FAILURE", updateChopperFailure) end,
    remove = function(vehicle) stopFrameUpdate(vehicle, "CHOPPER_FAILURE") end
}

---Lets the straw of a broken chopper fall unchopped, stubble unshredded
-- @param table vehicle vehicle
-- @param function superFunc original function
-- @param table workArea work area
-- @param any ... further arguments of the game's function
-- @return any ... what the game's function returns, 0 and 0 with a broken chopper
function RMS_Breakdowns.processCombineChopperArea(vehicle, superFunc, workArea, ...)
    if vehicle.spec_RealisticMechanicalSystems.activeEffects.CHOPPER_FAILURE == nil then
        return superFunc(vehicle, workArea, ...)
    end
    local spec_combine = vehicle.spec_combine
    if not spec_combine.isSwathActive then
        local parameters = spec_combine.workAreaParameters
        parameters.droppedLiters = parameters.litersToDrop
    end
    return 0, 0
end

---Keeps the swath of a broken chopper, whoever asks to chop again
-- @param table vehicle vehicle
-- @param function superFunc original function
-- @param boolean isSwathActive new state
-- @param boolean? noEventSend true when the change came over the network
-- @param any ... further arguments of the game's function
-- @return any ... what the game's function returns
function RMS_Breakdowns.setIsSwathActive(vehicle, superFunc, isSwathActive, noEventSend, ...)
    if not isSwathActive and not noEventSend and getIsChopperLocked(vehicle) then
        return
    end
    return superFunc(vehicle, isSwathActive, noEventSend, ...)
end

---Tells the driver who asks to chop that the chopper is broken
-- @param table vehicle vehicle
-- @param function superFunc original function
-- @param any ... arguments of the game's function
-- @return any ... what the game's function returns
function RMS_Breakdowns.actionEventToggleChopper(vehicle, superFunc, ...)
    if vehicle.spec_combine.isSwathActive and getIsChopperLocked(vehicle) then
        showWarning(vehicle, "rms_breakdowns_chopper_failure_message", 4000)
        return
    end
    return superFunc(vehicle, ...)
end

Combine.actionEventToggleChopper = Utils.overwrittenFunction(Combine.actionEventToggleChopper, RMS_Breakdowns.actionEventToggleChopper)

---Returns why a turn on is refused: a broken harvest or a PTO engagement that slips
-- @param table vehicle vehicle turned on
-- @param table rootVehicle root vehicle
-- @param table spec RMS specialization of the root vehicle
-- @return string? reason l10n key, nil when not refused
local function getTurnOnRefusal(vehicle, rootVehicle, spec)
    local effects = spec.activeEffects
    if vehicle == rootVehicle and effects.HARVEST_FAILURE ~= nil then
        return "rms_breakdowns_harvest_failure_message"
    end
    local attempt, engagement = spec.turnOnAttempt, effects.PTO_ENGAGEMENT_BLOCKED_CHANCE
    if engagement == nil or attempt == nil or not RMS_Utils.getConnectedPtoData(rootVehicle, "rear").connectedVehicles[vehicle] then
        return nil
    end
    if attempt.isRefused == nil then
        attempt.isRefused = math.random() < engagement.value
    end
    return attempt.isRefused and "rms_breakdowns_pto_engagement_blocked_message" or nil
end

---Refuses a broken harvest, or a PTO whose engagement slips
-- @param table vehicle vehicle
-- @param function superFunc original function
-- @return boolean canBeTurnedOn true when it may turn on
-- @return any warning warning of the game's function
function RMS_Breakdowns.getCanBeTurnedOn(vehicle, superFunc)
    local canBeTurnedOn, warning = superFunc(vehicle)
    local rootVehicle = vehicle.rootVehicle
    local spec = getLoadedSpec(rootVehicle)
    if not canBeTurnedOn or spec == nil or vehicle:getIsTurnedOn() then
        return canBeTurnedOn, warning
    end
    local refusal = getTurnOnRefusal(vehicle, rootVehicle, spec)
    if refusal == nil then
        return canBeTurnedOn, warning
    end
    local attempt = spec.turnOnAttempt
    if attempt ~= nil and not attempt.isWarned then
        attempt.isWarned = true
        showWarning(rootVehicle, refusal, 4000)
    end
    return false, warning
end

---Runs a turn on the driver asks for, which a worn engagement may refuse once
-- @param table vehicle vehicle
-- @param function turnOn turn on of the game
-- @return any result what the turn on returns
local function withTurnOnAttempt(vehicle, turnOn)
    local spec = vehicle.rootVehicle.spec_RealisticMechanicalSystems
    if spec == nil then
        return turnOn()
    end
    spec.turnOnAttempt = {}
    local result = turnOn()
    spec.turnOnAttempt = nil
    return result
end

---Runs the turn on key as a turn on attempt
-- @param table vehicle vehicle
-- @param function superFunc original function
-- @param string actionName input action
-- @param float inputValue input value
-- @param any callbackState callback state
-- @param boolean isAnalog true for an analog input
-- @return any result what the game's function returns
function RMS_Breakdowns.actionEventTurnOn(vehicle, superFunc, actionName, inputValue, callbackState, isAnalog)
    return withTurnOnAttempt(vehicle, function() return superFunc(vehicle, actionName, inputValue, callbackState, isAnalog) end)
end

---Runs the controller turn on as a turn on attempt
-- @param table vehicle vehicle
-- @param function superFunc original function
-- @param any direction direction of the controller
-- @return any result what the game's function returns
function RMS_Breakdowns.actionControllerTurnOnEvent(vehicle, superFunc, direction)
    return withTurnOnAttempt(vehicle, function() return superFunc(vehicle, direction) end)
end

---Keeps a PTO turning when its worn clutch does not release
-- @param table vehicle vehicle
-- @param function superFunc original function
-- @param boolean isTurnedOn new state
-- @param boolean? noEventSend true when the change came over the network
-- @return any ... what the game's function returns
function RMS_Breakdowns.setIsTurnedOn(vehicle, superFunc, isTurnedOn, noEventSend)
    local rootVehicle = vehicle.rootVehicle
    local spec = getLoadedSpec(rootVehicle)
    local stuck = spec ~= nil and spec.activeEffects.PTO_STUCK_ENGAGED_CHANCE or nil
    if stuck ~= nil and not isTurnedOn and not noEventSend and vehicle:getIsTurnedOn() and rootVehicle:getIsMotorStarted()
        and RMS_Utils.getConnectedPtoData(rootVehicle, "rear").connectedVehicles[vehicle] and math.random() < stuck.value then
        showWarning(rootVehicle, "rms_breakdowns_pto_stuck_engaged_message", 4000)
        return
    end
    return superFunc(vehicle, isTurnedOn, noEventSend)
end

TurnOnVehicle.getCanBeTurnedOn = Utils.overwrittenFunction(TurnOnVehicle.getCanBeTurnedOn, RMS_Breakdowns.getCanBeTurnedOn)
TurnOnVehicle.setIsTurnedOn = Utils.overwrittenFunction(TurnOnVehicle.setIsTurnedOn, RMS_Breakdowns.setIsTurnedOn)
TurnOnVehicle.actionEventTurnOn = Utils.overwrittenFunction(TurnOnVehicle.actionEventTurnOn, RMS_Breakdowns.actionEventTurnOn)
TurnOnVehicle.actionEventTurnOnAll = Utils.overwrittenFunction(TurnOnVehicle.actionEventTurnOnAll, RMS_Breakdowns.actionEventTurnOn)
TurnOnVehicle.actionControllerTurnOnEvent = Utils.overwrittenFunction(TurnOnVehicle.actionControllerTurnOnEvent,
    RMS_Breakdowns.actionControllerTurnOnEvent)

---Keeps the shaft file of the game, which names its joints
-- @param table vehicle vehicle
-- @param function superFunc original function
-- @param table powerTakeOff power take off
-- @param string xmlFilename file of the shaft
-- @return any ... what the game's function returns
function RMS_Breakdowns.loadPowerTakeOffFromConfigFile(vehicle, superFunc, powerTakeOff, xmlFilename)
    powerTakeOff.rmsShaftModel = xmlFilename:match("([^/\\]+)%.xml$")
    return superFunc(vehicle, powerTakeOff, xmlFilename)
end

PowerTakeOffs.loadPowerTakeOffFromConfigFile = Utils.overwrittenFunction(PowerTakeOffs.loadPowerTakeOffFromConfigFile,
    RMS_Breakdowns.loadPowerTakeOffFromConfigFile)

---Blocks the AI helper from starting a vehicle whose engine cannot run
-- @param table self vehicle
-- @param function superFunc original function
-- @param any ... arguments of the game's function
-- @return boolean canStart true when the helper may start
function RMS_Breakdowns.getCanStartAIVehicle(self, superFunc, ...)
    if not superFunc(self, ...) then
        return false
    end

    return self:getIsMotorStarted() or not RMS_Start.getIsColdBlocked(self)
end

---Ends the grind of a refused shift, extraData {duration in ms}
-- @param table vehicle vehicle
-- @param float dt time of the step (ms)
local function updateShiftGrind(vehicle, dt)
    local spec = vehicle.spec_RealisticMechanicalSystems
    local grind = getEffectState(vehicle, "GEAR_SHIFT_FAILURE_CHANCE")
    local effect = spec.activeEffects.GEAR_SHIFT_FAILURE_CHANCE
    if grind.status == "FAILED" and vehicle:getIsMotorStarted() then
        grind.timer = grind.timer + dt
        if grind.timer > effect.extraData.duration then
            grind.status, grind.timer = "IDLE", 0
        end
    end
end

RMS_Breakdowns.EffectApplicators.GEAR_SHIFT_FAILURE_CHANCE = {
    apply = function(vehicle) startFrameUpdate(vehicle, "GEAR_SHIFT_FAILURE_CHANCE", updateShiftGrind) end,
    remove = function(vehicle) stopFrameUpdate(vehicle, "GEAR_SHIFT_FAILURE_CHANCE") end
}

---Returns the shift failure effect and its grind state
-- @param table motor motor
-- @return table? effect shift failure effect, nil without one
-- @return table? grind state of the grind
local function getShiftGrind(motor)
    local vehicle = motor.vehicle
    local spec = getLoadedSpec(vehicle)
    local effect = spec ~= nil and spec.activeEffects.GEAR_SHIFT_FAILURE_CHANCE or nil
    return effect, effect ~= nil and getEffectState(vehicle, "GEAR_SHIFT_FAILURE_CHANCE") or nil
end

---Starts the grind of a refused shift, with its sound
-- @param table vehicle vehicle
-- @param table grind state of the grind
-- @param float duration duration sent to the clients (ms)
local function startShiftGrind(vehicle, grind, duration)
    grind.status, grind.timer = "FAILED", 0
    RMS_SoundManager.playSample(vehicle.spec_RealisticMechanicalSystems.samples.transmissionShiftFailed)
    RMS_EffectSyncEvent.send(vehicle, "GEAR_SHIFT_FAILURE_CHANCE", "FAILED", duration)
end

---Tells whether a gear asked is refused: while the box grinds, or by chance
-- @param table motor motor
-- @return boolean isRefused true when refused
local function getIsShiftRefused(motor)
    local effect, grind = getShiftGrind(motor)
    if effect == nil then
        return false
    elseif grind.status == "FAILED" then
        return true
    elseif motor.vehicle.isServer and math.random() < effect.value then
        startShiftGrind(motor.vehicle, grind, 0)
        return true
    end
    return false
end

VehicleMotor.shiftGear = Utils.overwrittenFunction(VehicleMotor.shiftGear, function(self, superFunc, up)
    if not getIsShiftRefused(self) then
        return superFunc(self, up)
    end
end)

VehicleMotor.selectGear = Utils.overwrittenFunction(VehicleMotor.selectGear, function(self, superFunc, gearIndex, activation)
    local effect, grind = getShiftGrind(self)
    if effect ~= nil and (grind.status == "FAILED" or activation and getIsShiftRefused(self)) then
        return
    end
    return superFunc(self, gearIndex, activation)
end)

-- an automatic shift the box refuses takes as long as the grind
VehicleMotor.updateGear = Utils.overwrittenFunction(VehicleMotor.updateGear, function(self, superFunc, acceleratorPedal, brakePedal, dt)
    local wasShifting = self.gear == 0 and self.gearChangeTimer > 0
    local acceleratorPedalOut, brakePedalOut = superFunc(self, acceleratorPedal, brakePedal, dt)
    local effect, grind = getShiftGrind(self)
    if effect ~= nil and self.gear == 0 and self.gearChangeTimer > 0 and not wasShifting then
        if self.vehicle.isServer and math.random() < effect.value then
            local duration = effect.extraData.duration
            self.gearChangeTimer, self.autoGearChangeTimer = duration, duration
            startShiftGrind(self.vehicle, grind, duration)
        end
        if effect.value >= 1 then
            self.targetGear = self.previousGear
        end
    end
    return acceleratorPedalOut, brakePedalOut
end)

---Throws the gear out under load by chance, extraData {duration in ms}
-- @param table vehicle vehicle
-- @param float dt time of the step (ms)
local function updateGearRejection(vehicle, dt)
    local spec = vehicle.spec_RealisticMechanicalSystems
    local effect = spec.activeEffects.GEAR_REJECTION_CHANCE
    if not vehicle:getIsMotorStarted() then
        return
    end
    local rejection = getEffectState(vehicle, "GEAR_REJECTION_CHANCE")
    local motor = vehicle:getMotor()
    if rejection.status == "REJECTED" then
        motor.targetGear = 0
        rejection.timer = rejection.timer + dt
        if vehicle.isServer and rejection.timer >= effect.extraData.duration then
            rejection.status, rejection.timer = "IDLE", 0
            RMS_SoundManager.playSample(spec.samples.transmissionShiftFailed)
            RMS_EffectSyncEvent.send(vehicle, "GEAR_REJECTION_CHANCE", "IDLE")
        end
    elseif vehicle.isServer and RMS_Utils.getMotorLoad(vehicle) > 0.8
        and math.random() < RMS_Utils.getChancePerFrameFromMeanTime(dt, effect.value) then
        RMS_Breakdowns.rejectGear(vehicle, rejection)
        RMS_EffectSyncEvent.send(vehicle, "GEAR_REJECTION_CHANCE", "REJECTED")
    end
end

---Throws the gear out to neutral, with its sound and warning
-- @param table vehicle vehicle
-- @param table rejection state of the rejection
function RMS_Breakdowns.rejectGear(vehicle, rejection)
    rejection.status, rejection.timer = "REJECTED", 0
    vehicle:getMotor():setGear(0, false)
    RMS_SoundManager.playSample(vehicle.spec_RealisticMechanicalSystems.samples.gearDisengage)
    showWarning(vehicle, "rms_breakdowns_gear_disengage_message", 3000)
end

RMS_Breakdowns.EffectApplicators.GEAR_REJECTION_CHANCE = {
    apply = function(vehicle) startFrameUpdate(vehicle, "GEAR_REJECTION_CHANCE", updateGearRejection) end,
    remove = function(vehicle) stopFrameUpdate(vehicle, "GEAR_REJECTION_CHANCE") end
}

---Flickers the lit lights by chance, then gives them back, extraData {duration in ms}
-- @param table vehicle vehicle
-- @param float dt time of the step (ms)
local function updateLightsFlicker(vehicle, dt)
    local effect = vehicle.spec_RealisticMechanicalSystems.activeEffects.LIGHTS_FLICKER_CHANCE
    if not vehicle:getIsMotorStarted() or vehicle.spec_lights == nil then
        return
    end
    local flicker = getEffectState(vehicle, "LIGHTS_FLICKER_CHANCE")
    if flicker.status == "FLICKING" then
        if flicker.timer < effect.extraData.duration then
            flicker.timer = flicker.timer + dt
            vehicle:setLightsTypesMask(math.random(0, vehicle.spec_lights.maxLightStateMask), true, true)
        else
            flicker.status, flicker.timer = "IDLE", 0
            vehicle:setLightsTypesMask(flicker.mask, true, true)
        end
    elseif vehicle.isServer and math.random() < RMS_Utils.getChancePerFrameFromMeanTime(dt, effect.value)
        and vehicle:getLightsTypesMask() ~= 0 then
        RMS_Breakdowns.startLightsFlicker(flicker, vehicle:getLightsTypesMask())
        RMS_EffectSyncEvent.send(vehicle, "LIGHTS_FLICKER_CHANCE", "FLICKING", flicker.mask)
    end
end

---Starts a flicker, the lights the driver had on kept to give back
-- @param table flicker state of the flicker
-- @param integer mask light types mask the driver had on
function RMS_Breakdowns.startLightsFlicker(flicker, mask)
    flicker.status, flicker.timer, flicker.mask = "FLICKING", 0, mask
end

RMS_Breakdowns.EffectApplicators.LIGHTS_FLICKER_CHANCE = {
    apply = function(vehicle) startFrameUpdate(vehicle, "LIGHTS_FLICKER_CHANCE", updateLightsFlicker) end,
    remove = function(vehicle) stopFrameUpdate(vehicle, "LIGHTS_FLICKER_CHANCE") end
}

RMS_Breakdowns.EffectApplicators.EMPTY_EFFECT = {}

---Returns the text refusing a start
-- @param table vehicle vehicle
-- @return string? reason text key, nil when nothing of the kind stands in the way
function RMS_Breakdowns.getStartBlockReason(vehicle)
    local reason = RMS_BatteryCharger.getStartBlockReason(vehicle)
    if reason ~= nil then
        return reason
    end

    if vehicle.spec_RealisticMechanicalSystems.batteryIsolated and vehicle:getIsControlled() and not vehicle:getIsAIActive() then
        return "rms_battery_isolator_open"
    end
    return nil
end

---Returns why the engine may not run: an RMS refusal, else the game's warning
-- @param table self vehicle
-- @param function superFunc original function
-- @return string? warning warning text, nil without one
function RMS_Breakdowns.getMotorNotAllowedWarning(self, superFunc)
    local spec = self.spec_RealisticMechanicalSystems
    local reason = nil
    -- warnings stack; the run check shows the service one
    if spec.isExcludedVehicle or not self:isUnderService() then
        reason = RMS_Breakdowns.getStartBlockReason(self)
    end
    return reason ~= nil and g_i18n:getText(reason) or RMS_AdBlue.callWithoutTank(self, superFunc)
end

---Tells whether the engine may run, the key handing its start to RMS
-- @param table self vehicle
-- @param function superFunc original function
-- @return boolean canRun true when it may run
function RMS_Breakdowns.getCanMotorRun(self, superFunc)
    local spec = self.spec_RealisticMechanicalSystems
    if spec.isExcludedVehicle then
        return superFunc(self)
    end
    if self:isUnderService() then
        if self:getIsActiveForInput(true) then
            g_currentMission:showBlinkingWarning(g_i18n:getText(self:getCurrentStatus()) .. " " .. g_i18n:getText("rms_breakdown_at_progress_message", 100))
        end
        return false
    end
    if RMS_Breakdowns.getStartBlockReason(self) ~= nil then
        return false
    end

    local failure = spec.activeEffects.ENGINE_FAILURE
    if failure ~= nil and not failure.extraData.starter then
        return false
    end

    return RMS_AdBlue.callWithoutTank(self, superFunc) and not RMS_Start.takeKeyStart(self)
end
