-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---Vehicle breakdown effects.
RMS_Breakdowns = {}

local log_dbg = RMS_Utils.createLogger("[RMS_BREAKDOWNS]")

local BRAKE_SOUND_SPEED_THRESHOLD = 15

source(g_currentModDirectory .. "scripts/core/RMS_BreakdownRegistry.lua")


RMS_Breakdowns.EffectApplicators = {}

---Returns the text describing a stage on a vehicle
-- @param table vehicle vehicle
-- @param table stageData stage of a registry entry
-- @param table? breakdown active breakdown and failure mode
-- @return string key text key
function RMS_Breakdowns.getStageDescription(vehicle, stageData, breakdown)
    if stageData.electricDescription ~= nil and vehicle.spec_RealisticMechanicalSystems.isElectricVehicle then
        return stageData.electricDescription
    end
    if stageData.branchDescriptions ~= nil and breakdown ~= nil and stageData.branchDescriptions[breakdown.branch] ~= nil then
        return stageData.branchDescriptions[breakdown.branch]
    end
    return stageData.description
end

---Registers the per frame function of an effect, keeping any already registered
local function addFuncToActive(v, effectName, func)
    if v.spec_RealisticMechanicalSystems.activeFunctions[effectName] == nil then
        v.spec_RealisticMechanicalSystems.activeFunctions[effectName] = func
    end
end

---Drops the per frame function of an effect
local function removeFuncFromActive(v, effectName)
    if v.spec_RealisticMechanicalSystems.activeFunctions[effectName] ~= nil then
        v.spec_RealisticMechanicalSystems.activeFunctions[effectName] = nil
    end
end

---Returns the starter effect while cranking or catching
local function getStarterEffect(spec)
    if spec == nil or spec.activeEffects == nil then
        return nil
    end

    for _, effectId in ipairs({ "ENGINE_FAILURE", "ENGINE_HARD_START_MODIFIER", "GLOW_PLUG_HARD_START_MODIFIER" }) do
        local effect = spec.activeEffects[effectId]
        if effect ~= nil and effect.extraData ~= nil
            and (effect.extraData.status == "CRANKING" or effect.extraData.status == "PASSED") then
            return effect
        end
    end

    return nil
end

---Tells whether the starter is being asked for
local function getIsStarterRequestActive(vehicle, effect)
    local spec = vehicle ~= nil and vehicle.spec_RealisticMechanicalSystems or nil
    return spec ~= nil and (spec.startButtonHeld == true
        or (effect ~= nil and effect.extraData ~= nil and effect.extraData.automaticCrank == true))
end

local function getStarterVehicle(vehicle)
    local own = RMS_StarterSoundsData.VEHICLES[string.lower(vehicle.configFileName or "")]
    if own ~= nil then
        return own, true
    end

    local storeItem = g_storeManager:getItemByXMLFilename(vehicle.configFileName)
    local category = storeItem ~= nil and storeItem.categoryName or nil
    local power = RMS_Fluids.getEnginePower(vehicle)
    -- Break ties by filename to keep starter selection deterministic.
    local nearest, nearestGap, nearestKey = nil, math.huge, nil
    for key, candidate in pairs(RMS_StarterSoundsData.VEHICLES) do
        local gap = math.abs(candidate[2] - power) + (candidate[1] == category and 0 or 100000)
        if gap < nearestGap or (gap == nearestGap and key < nearestKey) then
            nearest, nearestGap, nearestKey = candidate, gap, key
        end
    end
    return nearest, false
end

local function newStarter(vehicle)
    local starterVehicle, isOwn = getStarterVehicle(vehicle)
    return {
        isOwn = isOwn,
        filename = starterVehicle[3],
        main = { entry = RMS_StarterSoundsData.SOUNDS[string.lower(starterVehicle[3])], position = 0 },
        layers = {}
    }
end

local function engageStarter(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    local starter = newStarter(vehicle)
    local motorSamples = vehicle.isClient and vehicle.spec_motorized.motorSamples or {}
    for _, sample in ipairs(motorSamples) do
        local entry = starter.isOwn and sample.filename ~= nil and RMS_StarterSoundsData.SOUNDS[string.lower(sample.filename)] or nil
        if entry ~= nil then
            table.insert(starter.layers, { sample = sample, entry = entry, position = 0 })
        end
    end
    if #starter.layers == 0 and motorSamples[1] ~= nil then
        spec.samples.borrowedStarter = spec.samples.borrowedStarter or RMS_SoundManager.cloneSample(motorSamples[1], starter.filename)
        table.insert(starter.layers, { sample = spec.samples.borrowedStarter, entry = starter.main.entry, position = 0, isBorrowed = true })
    end
    for _, layer in ipairs(starter.layers) do
        RMS_SoundManager.playSample(layer.sample)
    end
    spec.starter = starter
end

---Stops the starter before the engine catches
local function releaseStarter(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    for _, layer in ipairs(spec.starter.layers) do
        RMS_SoundManager.setSamplePitchOffset(layer.sample, 0)
        RMS_SoundManager.stopSample(layer.sample, 0)
    end
    spec.starter = nil
end

local function turnStarterRecording(recording, dt, speed, isHeld)
    recording.position = recording.position + dt * speed
    if isHeld and recording.position >= recording.entry[1] then
        recording.position = recording.position - recording.entry[2]
        RMS_SoundManager.playSampleFrom(recording.sample, recording.position)
    end
end

-- @param table vehicle vehicle
-- @param float dt time since the last frame in ms
function RMS_Breakdowns.updateStarter(vehicle, dt)
    local spec = vehicle.spec_RealisticMechanicalSystems
    if spec.isElectricVehicle or vehicle:getIsMotorStarted() then
        return
    end

    local effect = getStarterEffect(spec)
    local crankSpeed = effect ~= nil and (effect.extraData.crankSpeed or RMS_Electrical.getCrankingSpeed(vehicle)) or 0
    local isHeld = effect ~= nil and effect.extraData.status == "CRANKING"
    local isTurning = crankSpeed > 0 and (not isHeld or getIsStarterRequestActive(vehicle, effect))
    if not isTurning then
        if spec.starter ~= nil then
            releaseStarter(vehicle)
        end
        return
    end

    if spec.starter == nil then
        engageStarter(vehicle)
    end
    turnStarterRecording(spec.starter.main, dt, crankSpeed, isHeld)
    for _, layer in ipairs(spec.starter.layers) do
        local isCaught = layer.position >= layer.entry[3]
        RMS_SoundManager.setSamplePitchOffset(layer.sample, isCaught and 0 or crankSpeed - 1)
        turnStarterRecording(layer, dt, RMS_SoundManager.getSamplePitch(layer.sample), isHeld or layer.isBorrowed)
    end
end

-- @param table vehicle vehicle
-- @param float crankSpeed speed of the starter, 1 at its reference speed
-- @return float delay delay in ms
function RMS_Breakdowns.getStarterCatchDelay(vehicle, crankSpeed)
    local starter = vehicle.spec_RealisticMechanicalSystems.starter or newStarter(vehicle)
    if not starter.isOwn then
        return 0
    end
    return math.max(0, (starter.main.entry[3] - starter.main.position) / crankSpeed)
end

-- @param table vehicle vehicle
function RMS_Breakdowns.onStarterCaught(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    if spec.starter == nil then
        return
    end
    for _, layer in ipairs(spec.starter.layers) do
        RMS_SoundManager.setSamplePitchOffset(layer.sample, 0)
        if layer.isBorrowed then
            RMS_SoundManager.stopSample(layer.sample, 0)
        else
            RMS_SoundManager.playSampleFrom(layer.sample, layer.position)
        end
    end
    spec.starter = nil
end

local function playDeadStartSound(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    if spec.isElectricVehicle or spec.batteryIsolated or vehicle:getIsMotorStarted() then
        return
    end
    if RMS_Electrical.getStartingVoltage(vehicle) < RMS_Electrical.getMinCrankingVoltage(vehicle) then
        RMS_SoundManager.playSample(spec.samples.batteryClicking)
    elseif vehicle:hasBreakdown("STARTER_RELAY_FAILURE") or vehicle:hasBreakdown("ENGINE_JAM") or spec.starterHealth <= 0 then
        RMS_SoundManager.playSample(spec.samples.starterRelayClick)
    end
end

RMS_Breakdowns.EffectApplicators.SELF_DISAPPEARING_BREAKDOWN_EFFECT = {
    apply = function(vehicle, effectData, handler)
        vehicle:removeBreakdown(effectData.extraData.breakdownId)
    end,

}

RMS_Breakdowns.EffectApplicators.ENGINE_FAILURE = {
    getEffectName = function()
        return "ENGINE_FAILURE"
    end,
    apply = function(vehicle, effectData, handler)
        local effectName = handler.getEffectName()
        local spec = vehicle.spec_RealisticMechanicalSystems
        local activeFunc = function(v, dt)
            local currentEffect = v.spec_RealisticMechanicalSystems.activeEffects ~= nil and v.spec_RealisticMechanicalSystems.activeEffects[effectName] or nil
            if currentEffect == nil or currentEffect.extraData == nil then
                return
            end

            if currentEffect.extraData.status ~= nil and currentEffect.extraData.status == 'CRANKING' then
                if currentEffect.extraData.crankSpeed == nil then
                    currentEffect.extraData.crankSpeed = RMS_Electrical.getCrankingSpeed(v)
                end
            end

            if v:getIsMotorStarted() then
                v:stopMotor()
            end
            if currentEffect.extraData.status ~= nil and currentEffect.extraData.status == 'CRANKING' then
                local startRequestActive = getIsStarterRequestActive(v, currentEffect)
                if not startRequestActive then
                    currentEffect.extraData.status = 'IDLE'
                    currentEffect.extraData.crankSpeed = nil
                    currentEffect.extraData.automaticCrank = false
                    RMS_EffectSyncEvent.send(v, effectName, "IDLE", 0, 0, 0)
                end
            end
        end
        addFuncToActive(vehicle, effectName, activeFunc)
    end,
    remove = function(vehicle, handler)
        removeFuncFromActive(vehicle, handler.getEffectName())
    end,
}

RMS_Breakdowns.EffectApplicators.LIGHTS_FAILURE = {
    apply = function(vehicle, effectData, handler)
        local currentLightMask = vehicle:getLightsTypesMask()
        if currentLightMask ~= 0 then
            vehicle:setLightsTypesMask(0, true, true)
        end
    end,

}

local LIGHT_CIRCUITS = {
    LOW_BEAM_FAILURE = "LIGHT_TYPE_DEFAULT",
    HIGH_BEAM_FAILURE = "LIGHT_TYPE_HIGHBEAM",
    FRONT_WORK_LIGHTS_FAILURE = "LIGHT_TYPE_WORK_FRONT",
    REAR_WORK_LIGHTS_FAILURE = "LIGHT_TYPE_WORK_BACK"
}

---Tells whether a list of lamps holds one of a light type
local function getHoldsLightType(lights, lightType)
    for _, light in ipairs(lights) do
        for _, lampLightType in ipairs(light.lightTypes or {}) do
            if lampLightType == lightType then
                return true
            end
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
        if getHoldsLightType(lights, lightType) then
            return true
        end
    end
    for _, profile in pairs(spec.realLights) do
        for _, lights in pairs(profile) do
            if getHoldsLightType(lights, lightType) then
                return true
            end
        end
    end
    return false
end

---Tells whether the machine carries turn lights
local function getCarriesTurnLights(vehicle)
    local spec = vehicle.spec_lights
    if spec == nil then
        return false
    end
    if #spec.staticLights.turnLightsLeft > 0 then
        return true
    end
    for _, profile in pairs(spec.realLights) do
        if #profile.turnLightsLeft > 0 then
            return true
        end
    end
    return false
end

for effectName, lightTypeName in pairs(LIGHT_CIRCUITS) do
    RMS_Breakdowns.EffectApplicators[effectName] = {
        apply = function(vehicle, effectData, handler)
            vehicle:setLightsTypesMask(vehicle:getLightsTypesMask(), true, true)
        end,

        getIsCarried = function(vehicle)
            return getCarriesLightType(vehicle, Lights[lightTypeName])
        end
    }
end

RMS_Breakdowns.EffectApplicators.BEACON_LIGHTS_FAILURE = {
    apply = function(vehicle, effectData, handler)
        if vehicle:getBeaconLightsVisibility() then
            vehicle:setBeaconLightsVisibility(false, true, true)
        end
    end,

    getIsCarried = function(vehicle)
        return vehicle.spec_lights ~= nil and #vehicle.spec_lights.beaconLights > 0
    end
}

RMS_Breakdowns.EffectApplicators.TURN_LIGHTS_FAILURE = {
    apply = function(vehicle, effectData, handler)
        if vehicle:getTurnLightState() ~= Lights.TURNLIGHT_OFF then
            vehicle:setTurnLightState(Lights.TURNLIGHT_OFF, true, true)
        end
    end,

    getIsCarried = getCarriesTurnLights
}

---Tells whether the machine carries the lamps of a light circuit
-- @param table vehicle vehicle
-- @param string effectName effect putting the circuit out
-- @return boolean isCarried true when the machine has those lamps
function RMS_Breakdowns.getCarriesLightCircuit(vehicle, effectName)
    return RMS_Breakdowns.EffectApplicators[effectName].getIsCarried(vehicle)
end

-- @param table vehicle vehicle
-- @param string effectName effect putting the circuit out
-- @return boolean isLit true while the circuit is switched on
function RMS_Breakdowns.getIsLightCircuitLit(vehicle, effectName)
    local lightTypeName = LIGHT_CIRCUITS[effectName]
    if lightTypeName ~= nil then
        return bit32.band(vehicle:getLightsTypesMask(), 2 ^ Lights[lightTypeName]) ~= 0
    elseif effectName == "BEACON_LIGHTS_FAILURE" then
        return vehicle:getBeaconLightsVisibility()
    end
    return vehicle:getTurnLightState() ~= Lights.TURNLIGHT_OFF
end

-- @param table self vehicle
-- @param function superFunc super function
-- @param integer lightsTypesMask light types mask
-- @param boolean force force
-- @param boolean noEventSend no event send
function RMS_Breakdowns.setLightsTypesMask(self, superFunc, lightsTypesMask, force, noEventSend)
    local rootVehicle = self:getRootVehicle()
    local spec = rootVehicle.spec_RealisticMechanicalSystems
    -- a machine still loading has no RMS state yet
    if spec == nil or spec.activeEffects == nil then
        superFunc(self, lightsTypesMask, force, noEventSend)
    elseif spec.activeEffects.LIGHTS_FAILURE == nil and not RMS_Electrical.getKeepsLightsOff(rootVehicle) then
        for effectName, lightTypeName in pairs(LIGHT_CIRCUITS) do
            if spec.activeEffects[effectName] ~= nil then
                lightsTypesMask = bit32.band(lightsTypesMask, bit32.bnot(2 ^ Lights[lightTypeName]))
            end
        end
        superFunc(self, lightsTypesMask, force, noEventSend)
    elseif self:getLightsTypesMask() ~= 0 then
        superFunc(self, 0, force, noEventSend)
    end
end

---Keeps the beacon lights out while their circuit has failed
-- @param table self vehicle
-- @param function superFunc super function
-- @param boolean visibility true to switch them on
-- @param boolean force force
-- @param boolean noEventSend no event send
function RMS_Breakdowns.setBeaconLightsVisibility(self, superFunc, visibility, force, noEventSend)
    local spec = self:getRootVehicle().spec_RealisticMechanicalSystems
    local activeEffects = spec ~= nil and spec.activeEffects or {}
    superFunc(self, visibility and activeEffects.BEACON_LIGHTS_FAILURE == nil, force, noEventSend)
end

---Keeps the turn and hazard lights out while their circuit has failed
-- @param table self vehicle
-- @param function superFunc super function
-- @param integer state turn light state
-- @param boolean force force
-- @param boolean noEventSend no event send
function RMS_Breakdowns.setTurnLightState(self, superFunc, state, force, noEventSend)
    local spec = self:getRootVehicle().spec_RealisticMechanicalSystems
    local activeEffects = spec ~= nil and spec.activeEffects or {}
    if activeEffects.TURN_LIGHTS_FAILURE ~= nil then
        state = Lights.TURNLIGHT_OFF
    end
    superFunc(self, state, force, noEventSend)
end

local function getWheelSeizureTargetWheel(vehicle)
    local spec_rms = vehicle.spec_RealisticMechanicalSystems
    local spec_wheels = vehicle.spec_wheels
    if spec_rms == nil or spec_wheels == nil or spec_wheels.wheels == nil then
        return nil
    end

    local wheels = spec_wheels.wheels

    ---Collects the runtime fields of a wheel into one table
    local function resolveWheelRuntime(wheel)
        local runtimeWheel = (wheel ~= nil and wheel.physics ~= nil) and wheel.physics or wheel
        if runtimeWheel == nil then
            return nil
        end

        local data = {
            wheel = wheel
        }

        data.node = runtimeWheel.node or (wheel and wheel.node) or nil
        data.wheelShape = runtimeWheel.wheelShape or (wheel and wheel.wheelShape) or nil
        data.wheelShapeCreated = (runtimeWheel.wheelShapeCreated == true) or (wheel and wheel.wheelShapeCreated == true) or false
        data.isLeft = runtimeWheel.isLeft
        if data.isLeft == nil and wheel ~= nil then
            data.isLeft = wheel.isLeft
        end
        data.brakeFactor = tonumber(runtimeWheel.brakeFactor) or tonumber(wheel and wheel.brakeFactor) or 0
        data.driveNode = runtimeWheel.driveNode or (wheel and wheel.driveNode) or data.node
        data.positionX = tonumber(runtimeWheel.positionX) or tonumber(wheel and wheel.positionX) or 0
        data.positionZ = tonumber(runtimeWheel.positionZ) or tonumber(wheel and wheel.positionZ) or 0
        data.steeringAngle = tonumber(runtimeWheel.steeringAngle) or tonumber(wheel and wheel.steeringAngle) or 0
        data.rotationDamping = tonumber(runtimeWheel.rotationDamping) or tonumber(wheel and wheel.rotationDamping) or 0
        data.torqueTarget = runtimeWheel

        return data
    end

    ---Tells whether a wheel carries a usable node and wheel shape
    local function isValidWheelData(wd)
        return wd ~= nil
            and wd.node ~= nil and wd.node ~= 0
            and wd.wheelShape ~= nil and wd.wheelShape ~= 0
    end
    local cachedIndex = spec_rms.wheelSeizureTargetIndex
    if cachedIndex ~= nil then
        local cachedWheel = wheels[cachedIndex]
        local cachedData = resolveWheelRuntime(cachedWheel)
        if isValidWheelData(cachedData) then
            return cachedData
        end
    end

    local rootNode = vehicle.components and vehicle.components[1] and vehicle.components[1].node
    ---Returns the local position of a wheel
    local function getWheelLocalPos(wheelData)
        if rootNode ~= nil and wheelData ~= nil then
            local sampleNode = wheelData.driveNode or wheelData.node
            if sampleNode ~= nil then
                local x, _, z = localToLocal(sampleNode, rootNode, 0, 0, 0)
                return x or 0, z or 0
            end
        end
        return wheelData and wheelData.positionX or 0, wheelData and wheelData.positionZ or 0
    end

    ---Returns the first wheel matching a predicate
    local function pickBest(predicate)
        local bestIndex = nil
        local bestZ = -math.huge
        for i, wheel in ipairs(wheels) do
            local wheelData = resolveWheelRuntime(wheel)
            if isValidWheelData(wheelData) and predicate(wheelData) then
                local _, z = getWheelLocalPos(wheelData)
                if bestIndex == nil or z > bestZ then
                    bestIndex = i
                    bestZ = z
                end
            end
        end
        return bestIndex
    end

    local bestIndex = pickBest(function(wheelData)
        local x = getWheelLocalPos(wheelData)
        return (wheelData.isLeft == false or x > 0) and wheelData.brakeFactor > 0
    end)

    if bestIndex == nil then
        bestIndex = pickBest(function(wheelData)
            local x = getWheelLocalPos(wheelData)
            return (wheelData.isLeft == false or x > 0)
        end)
    end

    if bestIndex == nil then
        bestIndex = pickBest(function(wheelData)
            return wheelData.brakeFactor > 0
        end)
    end

    if bestIndex == nil then
        bestIndex = pickBest(function(_)
            return true
        end)
    end

    spec_rms.wheelSeizureTargetIndex = bestIndex
    if bestIndex ~= nil then
        return resolveWheelRuntime(wheels[bestIndex])
    end
    return nil
end

RMS_Breakdowns.EffectApplicators.BRAKE_FORCE_MODIFIER = {
}

local steeringFaultApplicator = {
    apply = function(vehicle, effectData, handler)
        RMS_Steering.refreshFaults(vehicle)
    end,

    remove = function(vehicle, handler)
        RMS_Steering.refreshFaults(vehicle)
    end
}

RMS_Breakdowns.EffectApplicators.STEERING_STATIC_BIAS_EFFECT = steeringFaultApplicator

RMS_Breakdowns.EffectApplicators.BRAKE_PULL_EFFECT = steeringFaultApplicator

RMS_Breakdowns.EffectApplicators.STEERING_PLAY_EFFECT = steeringFaultApplicator

RMS_Breakdowns.EffectApplicators.STEERING_WHEEL_FREE_EFFECT = steeringFaultApplicator

RMS_Breakdowns.EffectApplicators.WHEEL_SEIZURE_EFFECT = {
    remove = function(vehicle, handler)
        if vehicle.spec_RealisticMechanicalSystems ~= nil then
            vehicle.spec_RealisticMechanicalSystems.wheelSeizureTargetIndex = nil
        end
    end
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
    for _, sample in ipairs(vehicle.spec_motorized.motorSamples) do
        RMS_SoundManager.setSampleVolumeOffset(sample, -dip * sample.current.volume * sample.volumeScale)
    end
end

RMS_Breakdowns.EffectApplicators.ENGINE_HESITATION_CHANCE = {
    getEffectName = function() return "ENGINE_HESITATION_CHANCE" end,

    apply = function(vehicle, effectData, handler)

        local effectName = handler.getEffectName()
        local activeFunc = function(v, dt)
            local extra = effectData.extraData
            if v.isClient then
                updateMisfireSound(v, extra, dt)
            end

            if extra.status == "CHOKING" then
                extra.timer = extra.timer + dt
                if extra.timer > extra.duration then
                    if extra.cruiseState ~= 0 then
                        v:setCruiseControlState(extra.cruiseState, true)
                    end
                    extra.status = "IDLE"
                    extra.timer = 0
                end
            elseif v:getMotorLoadPercentage() > extra.motorLoad then
                if v.isServer and effectData.value > 0 and math.random() < RMS_Utils.getChancePerFrameFromMeanTime(dt, effectData.value) and extra.status == "IDLE" then

                    local cruiseState = v:getCruiseControlState()
                    if cruiseState ~= 0 then
                        extra.cruiseState = cruiseState
                        v:setCruiseControlState(0, true)
                    end
                    extra.status = "CHOKING"
                    RMS_EffectSyncEvent.send(v, "ENGINE_HESITATION_CHANCE", "CHOKING", 0)

                end
            end
        end
        addFuncToActive(vehicle, effectName, activeFunc)
    end,

    remove = function(vehicle, handler)
        removeFuncFromActive(vehicle, handler.getEffectName())
        if vehicle.isClient then
            for _, sample in ipairs(vehicle.spec_motorized.motorSamples) do
                RMS_SoundManager.setSampleVolumeOffset(sample, 0)
            end
        end
    end
}

---Applies the pedal effects and the wheel seizure to the physics step
-- @param table vehicle vehicle
-- @param function superFunc super function
-- @param float axisForward forward axis input
-- @param float axisSide side axis input
-- @param boolean doHandbrake handbrake input
-- @param float dt time since last call in ms
function RMS_Breakdowns.updateVehiclePhysics(vehicle, superFunc, axisForward, axisSide, doHandbrake, dt)
    local spec_rms = vehicle.spec_RealisticMechanicalSystems
    if spec_rms == nil then
        return superFunc(vehicle, axisForward, axisSide, doHandbrake, dt)
    end

    local brakeEffect = spec_rms and spec_rms.activeEffects.BRAKE_FORCE_MODIFIER
    local limpEffect = spec_rms and spec_rms.activeEffects.ENGINE_LIMP_EFFECT
    local hesitationEffect = spec_rms and spec_rms.activeEffects.ENGINE_HESITATION_CHANCE
    local wheelSeizureEffect = spec_rms and spec_rms.activeEffects.WHEEL_SEIZURE_EFFECT
    local isBraking = false
    local drivingMode = vehicle:getDirectionChangeMode()

    if hesitationEffect and hesitationEffect.extraData and hesitationEffect.extraData.status == "CHOKING" then
        axisForward = axisForward * math.max(1 - hesitationEffect.extraData.amplitude, 0)
    end

    if limpEffect and limpEffect.value then
        local maxAllowedAcceleration = math.max(1 + limpEffect.value, 0.2)
        if math.abs(axisForward) > maxAllowedAcceleration then
            if drivingMode == 2 then
                if axisForward > maxAllowedAcceleration then
                    axisForward = maxAllowedAcceleration
                end
            else
                if math.sign(vehicle.movingDirection) == math.sign(axisForward) then
                    if axisForward > 0 then
                        axisForward = maxAllowedAcceleration
                    else
                        axisForward = -1 * maxAllowedAcceleration
                    end
                end
            end
        end
    end

    if brakeEffect and brakeEffect.value ~= 0 then
        if drivingMode == 2 then
            isBraking = axisForward < -0.01
        else
            isBraking = vehicle.movingDirection ~= 0 and axisForward ~= 0 and math.sign(vehicle.movingDirection) ~= math.sign(axisForward)
        end
        
        if isBraking then
            local modifier = math.max(0.01, 1 + brakeEffect.value) 
            local origAxisForward = axisForward
            axisForward = axisForward * modifier
            if vehicle.isServer and brakeEffect.extraData ~= nil then
                local speed = vehicle:getLastSpeed()
                local previousSpeed = brakeEffect.extraData.previousSpeed or speed
                brakeEffect.extraData.previousSpeed = speed

                if previousSpeed >= BRAKE_SOUND_SPEED_THRESHOLD and speed < BRAKE_SOUND_SPEED_THRESHOLD
                    and math.abs(origAxisForward) > 0.999 and RMS_Drivetrain.getIsRoadVehicleCategory(vehicle)
                    and math.random() < math.abs(brakeEffect.value) then
                    RMS_SoundManager.playSample(spec_rms.samples.brakes)
                    RMS_EffectSyncEvent.send(vehicle, "BRAKE_FORCE_MODIFIER", "SOUND", 0)
                end
            end
        end
    end

    local result = superFunc(vehicle, axisForward, axisSide, doHandbrake, dt)

    if wheelSeizureEffect ~= nil and (tonumber(wheelSeizureEffect.value) or 0) > 0 and vehicle.isAddedToPhysics then
        local wheelData = getWheelSeizureTargetWheel(vehicle)
        if wheelData ~= nil and wheelData.node ~= nil and wheelData.node ~= 0 and wheelData.wheelShape ~= nil and wheelData.wheelShape ~= 0 then
            local intensity = math.clamp(tonumber(wheelSeizureEffect.value) or 1.0, 0, 1.0)
            local baseBrakeForce = 0
            if vehicle.getBrakeForce ~= nil then
                baseBrakeForce = tonumber(vehicle:getBrakeForce()) or 0
            end
            if baseBrakeForce <= 0 and vehicle.spec_motorized ~= nil and vehicle.spec_motorized.motor ~= nil and vehicle.spec_motorized.motor.getBrakeForce ~= nil then
                baseBrakeForce = tonumber(vehicle.spec_motorized.motor:getBrakeForce()) or 0
            end
            baseBrakeForce = math.max(baseBrakeForce, 100)

            local lockBrakeForce = math.max(baseBrakeForce * intensity, 100)
            local lockDamping = math.max((tonumber(wheelData.rotationDamping) or 0) * (3 + 4 * intensity), 5)

            if wheelData.torqueTarget ~= nil then
                wheelData.torqueTarget.torque = 0
            end
            if wheelData.wheel ~= nil and wheelData.wheel ~= wheelData.torqueTarget then
                wheelData.wheel.torque = 0
            end
            setWheelShapeProps(
                wheelData.node,
                wheelData.wheelShape,
                0,
                lockBrakeForce,
                wheelData.steeringAngle or 0,
                lockDamping
            )
        end
    end

    return result
end

RMS_Breakdowns.EffectApplicators.ENGINE_TORQUE_MODIFIER = {
    apply = function(vehicle, effectData, handler)
        vehicle:updateMotorProperties()
    end,

    remove = function(vehicle, handler)
        vehicle:updateMotorProperties()
    end
}

-- Refresh the native torque curve after thermal derating.
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

-- @param table vehicle vehicle
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

-- @param table vehicle vehicle
-- @param float dt time since last call in ms
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

---Applies the fuel consumption modifier to the consumers of the vehicle
-- @param table vehicle vehicle
-- @param float dt time since last call in ms
-- @param float accInput acceleration input
function RMS_Breakdowns.updateConsumers(vehicle, dt, accInput)
	local spec = vehicle.spec_motorized
	local idleFactor = 0.5
	local rpmPercentage = (spec.motor.lastMotorRpm - spec.motor.minRpm) / (spec.motor.maxRpm - spec.motor.minRpm)
	local rpmFactor = idleFactor + rpmPercentage * (1 - idleFactor)
	local loadFactor = math.max(spec.smoothedLoadPercentage * rpmPercentage, 0)
	local motorFactor = 0.5 * (0.2 * rpmFactor + 1.8 * loadFactor)
    local timeScale = 1

    if g_modIsLoaded["FS25_ingameTimeOperatingHours"] then
        timeScale = g_currentMission.missionInfo.timeScale or 1
        if timeScale <= 0 then
            timeScale = 1
        end
    end

    local fuelUsageFactors = {
        [1] = 1.0,
        [2] = 1.5,
        [3] = 2.5
    }
    
    local fuelSetting = g_currentMission.missionInfo.fuelUsage
    
    local usageFactor = fuelUsageFactors[fuelSetting] or 1.5

	local damage = vehicle:getVehicleDamage()

	if damage > 0 then
		usageFactor = usageFactor * (1 + damage * Motorized.DAMAGED_USAGE_INCREASE)
	end

    if vehicle.spec_RealisticMechanicalSystems ~= nil then
        local fuelEffect = vehicle.spec_RealisticMechanicalSystems.activeEffects.FUEL_CONSUMPTION_MODIFIER
        local rmsFuelModifier = (fuelEffect and fuelEffect.value) or 0
        usageFactor = usageFactor * (1 + rmsFuelModifier)
    end

	for _, consumer in pairs(spec.consumers) do
		if consumer.permanentConsumption and consumer.usage > 0 then
			local usedThisFrame = usageFactor * motorFactor * consumer.usage * dt * timeScale
			local used = usedThisFrame

			if used ~= 0 then
				consumer.fillLevelToChange = consumer.fillLevelToChange + used

				if math.abs(consumer.fillLevelToChange) > 1 then
					used = consumer.fillLevelToChange
					consumer.fillLevelToChange = 0
					local fillType = vehicle:getFillUnitLastValidFillType(consumer.fillUnitIndex)
					local stats = g_currentMission:farmStats(vehicle:getOwnerFarmId())

					stats:updateStats("fuelUsage", used)

					if vehicle:getIsAIActive() and (fillType == FillType.DIESEL or fillType == FillType.DEF) and g_currentMission.missionInfo.helperBuyFuel then
						if fillType == FillType.DIESEL then
							local price = used * g_currentMission.economyManager:getCostPerLiter(fillType) * 1.5

							stats:updateStats("expenses", price)
							g_currentMission:addMoney(-price, vehicle:getOwnerFarmId(), MoneyType.PURCHASE_FUEL, true)
						end

						used = 0
					end

					if fillType == consumer.fillType then
						vehicle:addFillUnitFillLevel(vehicle:getOwnerFarmId(), consumer.fillUnitIndex, -used, fillType, ToolType.UNDEFINED)
					end
				end

				local usage = usedThisFrame / dt * 1000 * 60 * 60
                if timeScale ~= 0 then
                    usage = usage / timeScale
                end

				if consumer.fillType == FillType.DIESEL or consumer.fillType == FillType.ELECTRICCHARGE or consumer.fillType == FillType.METHANE then
					spec.lastFuelUsage = usage
				elseif consumer.fillType == FillType.DEF then
					spec.lastDefUsage = usage
				end
			end
		end
	end

	if spec.consumersByFillTypeName.AIR ~= nil then
		local consumer = spec.consumersByFillTypeName.AIR
		local fillType = vehicle:getFillUnitLastValidFillType(consumer.fillUnitIndex)

		if fillType == consumer.fillType then
			local usage = 0
			local direction = vehicle.movingDirection * vehicle:getReverserDirection()
			local forwardBrake = direction > 0 and accInput < 0
			local backwardBrake = direction < 0 and accInput > 0
			local brakeIsPressed = vehicle:getLastSpeed() > 1 and (forwardBrake or backwardBrake)

			if brakeIsPressed then
				local delta = math.abs(accInput) * dt * vehicle:getAirConsumerUsage() / 1000

				vehicle:addFillUnitFillLevel(vehicle:getOwnerFarmId(), consumer.fillUnitIndex, -delta, consumer.fillType, ToolType.UNDEFINED)

				usage = delta / dt * 1000
			end

			local fillLevelPercentage = vehicle:getFillUnitFillLevelPercentage(consumer.fillUnitIndex)

			if fillLevelPercentage < consumer.refillCapacityPercentage then
				consumer.doRefill = true
			elseif fillLevelPercentage == 1 then
				consumer.doRefill = false
			end

			if consumer.doRefill then
				local delta = consumer.refillLitersPerSecond / 1000 * dt

				vehicle:addFillUnitFillLevel(vehicle:getOwnerFarmId(), consumer.fillUnitIndex, delta, consumer.fillType, ToolType.UNDEFINED)

				usage = -delta / dt * 1000
			end

			spec.lastAirUsage = usage
		end
	end
end

---Replaces the vanilla consumer update with the modified one
-- @param table vehicle vehicle
-- @param function superFunc super function
-- @param float dt time since last call in ms
-- @param float accInput acceleration input
function RMS_Breakdowns.updateConsumersOverwrite(vehicle, superFunc, dt, accInput)
    local spec_rms = vehicle.spec_RealisticMechanicalSystems
    if spec_rms ~= nil and spec_rms.activeEffects ~= nil then
        local effect = spec_rms.activeEffects.FUEL_CONSUMPTION_MODIFIER
        if effect ~= nil and effect.value ~= nil then
            return RMS_Breakdowns.updateConsumers(vehicle, dt, accInput)
        end
    end
    return superFunc(vehicle, dt, accInput)
end

RMS_Breakdowns.EffectApplicators.TRANSMISSION_SLIP_EFFECT = {
    apply = function(vehicle, effectData, handler)
        local motor = vehicle:getMotor()
        if motor == nil then return end

        local spec_rms = vehicle.spec_RealisticMechanicalSystems
        if spec_rms._origClutchSlippingTime == nil then
            spec_rms._origClutchSlippingTime = motor.clutchSlippingTime
        end
        motor.clutchSlippingTime = spec_rms._origClutchSlippingTime * (1 + effectData.value) ^ 3
    end,

    remove = function(vehicle, handler)
        local motor = vehicle:getMotor()
        if motor == nil then return end

        local spec_rms = vehicle.spec_RealisticMechanicalSystems
        if spec_rms._origClutchSlippingTime ~= nil then
            motor.clutchSlippingTime = spec_rms._origClutchSlippingTime
            spec_rms._origClutchSlippingTime = nil
        end
    end
}

RMS_Breakdowns.EffectApplicators.CVT_SLIP_EFFECT = {

    remove = function(vehicle, handler)
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

VehicleMotor.getMinMaxGearRatio = Utils.overwrittenFunction(VehicleMotor.getMinMaxGearRatio, function(self, superFunc)
    local minRatio, maxRatio = superFunc(self)
    local vehicle = self.vehicle
    if vehicle == nil then return minRatio, maxRatio end

    local spec_rms = vehicle.spec_RealisticMechanicalSystems
    if spec_rms == nil or spec_rms.activeEffects == nil then return minRatio, maxRatio end

    local slipEffect = spec_rms.activeEffects.TRANSMISSION_SLIP_EFFECT
    if slipEffect ~= nil and slipEffect.value ~= nil then
        local modifier = tonumber(slipEffect.value) or 0

        if modifier >= 1 then
            return minRatio * 100, maxRatio * 100
        end

        spec_rms.slipAccumulatedMod = spec_rms.slipAccumulatedMod or 0

        local nowMs = g_currentMission.time
        local lastUpdateMs = spec_rms.slipLastUpdateMs or nowMs
        local dtSec = math.max((nowMs - lastUpdateMs) / 1000, 0)
        spec_rms.slipLastUpdateMs = nowMs
        if dtSec > TRANSMISSION_SLIP_RESUME_GAP_SECONDS then dtSec = 0 end

        local speedFactor = math.min(self.vehicle:getLastSpeed() / (self:getMaximumForwardSpeed() * 3.6), 1.0)

        if modifier > 0 and minRatio ~= 0 and speedFactor > 0.5 then
            local motorAccel = self.motorRotAccelerationSmoothed
            local accelerationFactor = math.min(math.max(0, motorAccel / self.motorRotationAccelerationLimit * 5), 1.0)

            local step = TRANSMISSION_SLIP_CONVERGENCE_PER_SECOND * dtSec * (1 - math.min(speedFactor, 0.9))
            if spec_rms.slipAccumulatedMod < accelerationFactor then
                spec_rms.slipAccumulatedMod = math.min(spec_rms.slipAccumulatedMod + step, 1.0)
            else
                spec_rms.slipAccumulatedMod = math.max(spec_rms.slipAccumulatedMod - step, 0.0)
            end

            local dynamicModifier = modifier * spec_rms.slipAccumulatedMod
            minRatio = minRatio * (1 + dynamicModifier)
            maxRatio = maxRatio * (1 + dynamicModifier)
        end
    end

    local cvtSlipEffect = spec_rms.activeEffects.CVT_SLIP_EFFECT
    local isSliping = false
    if cvtSlipEffect ~= nil and cvtSlipEffect.value ~= nil and self.minForwardGearRatio ~= nil then
        local modifier = tonumber(cvtSlipEffect.value) or 0

        if modifier >= 1 then
            return minRatio * 100, maxRatio * 100
        end

        local nowMs = g_currentMission.time
        local lastUpdateMs = spec_rms.cvtSlipLastUpdateMs or nowMs
        local dtSec = math.max((nowMs - lastUpdateMs) / 1000, 0)
        spec_rms.cvtSlipLastUpdateMs = nowMs
        if dtSec > TRANSMISSION_SLIP_RESUME_GAP_SECONDS then dtSec = 0 end

        local lastAccelerationFactor = spec_rms.cvtSlipLastAccelerationFactor or 0
        local speedFactor = math.min(self.vehicle:getLastSpeed() / (self:getMaximumForwardSpeed() * 3.6 / 2), 1.0)
        local loadFactor = vehicle:getMotorLoadPercentage() + 0.2
        local massFactor = vehicle:getTotalMass() / vehicle:getTotalMass(true)

        if modifier > 0 and minRatio ~= 0 and maxRatio ~= 0 and speedFactor < 0.5 then
            local decatPerSecond = 0.01 / modifier * math.max(speedFactor, 0.1) * 1 / loadFactor * 1 / massFactor
            local motorAccel = self.motorRotAccelerationSmoothed
            local accelLimit = math.max(tonumber(self.motorRotationAccelerationLimit) or 0, 0.000001)
            local accelerationFactor = math.clamp(motorAccel / accelLimit, 0, 1)
            if accelerationFactor < lastAccelerationFactor then
                accelerationFactor = math.clamp(lastAccelerationFactor - decatPerSecond * dtSec, 0, 1)
            end
            spec_rms.cvtSlipLastAccelerationFactor = accelerationFactor
            isSliping = accelerationFactor >= 0.98 and speedFactor < 0.8

            local clampMin = math.min(minRatio, minRatio * 10)
            local clampMax = math.max(minRatio, minRatio * 10)
            minRatio = math.clamp(self.gearRatio * accelerationFactor, clampMin, clampMax)
        end
    end

    local cvtMaxEffect = spec_rms.activeEffects.CVT_MAX_RATIO_MODIFIER
    local speedFactor = math.min(self.vehicle:getLastSpeed() / (self:getMaximumForwardSpeed() * 3.6 / 2), 1.0)
    if cvtMaxEffect ~= nil and cvtMaxEffect.value ~= nil and self.minForwardGearRatio ~= nil and not isSliping and speedFactor > 0.5 then
        local value = tonumber(cvtMaxEffect.value) or 0
        minRatio = minRatio + minRatio * value * speedFactor
    end

    local pressureDropEffect = spec_rms.activeEffects.CVT_PRESSURE_DROP_CHANCE
    if pressureDropEffect ~= nil and pressureDropEffect.extraData ~= nil
        and pressureDropEffect.extraData.status == "PROGRESS"
        and (pressureDropEffect.extraData.timer or 0) > 0 then
        minRatio = minRatio * 1.5
    end

    return minRatio, maxRatio
end)

RMS_Breakdowns.EffectApplicators.POWERSHIFT_ENGAGEMENT_LAG_AND_HARSH_EFFECT = {
    getEffectName = function()
        return "POWERSHIFT_ENGAGEMENT_LAG_AND_HARSH_EFFECT" 
    end,

    apply = function(vehicle, effectData, handler)

        local effectName = handler.getEffectName()

        if vehicle.spec_RealisticMechanicalSystems.activeFunctions[effectName] == nil then
            vehicle.spec_RealisticMechanicalSystems.activeFunctions[effectName] = function(v, dt)
                
                if v:getIsMotorStarted() then
                    local spec = v.spec_RealisticMechanicalSystems
                    local effect = spec.activeEffects.POWERSHIFT_ENGAGEMENT_LAG_AND_HARSH_EFFECT
                    if effect and effect.value > 0 and effect.extraData.status ~= "IDLE" then
                        local motor = v:getMotor()
                        effect.extraData.timer = effect.extraData.timer + dt

                        if effect.extraData.timer > effect.value * 1000 and effect.extraData.status == "DELAYED" then
                            effect.extraData.timer = 0
                            effect.extraData.status = "PASSED"
                            if effect.extraData.backup then
                                effect.extraData.backup = motor.minGearRatio
                                motor.minGearRatio = 999.9
                            end
                            motor:applyTargetGear()
                            RMS_SoundManager.playSample(spec.samples.powershiftClunk)
                            RMS_EffectSyncEvent.send(v, "POWERSHIFT_ENGAGEMENT_LAG_AND_HARSH_EFFECT", "CLUNK", 0)
                        elseif effect.extraData.timer > effect.extraData.duration and effect.extraData.status == "PASSED" then
                            if effect.extraData.backup then
                                motor.minGearRatio = effect.extraData.backup
                            end
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

VehicleMotor.applyTargetGear = Utils.overwrittenFunction(VehicleMotor.applyTargetGear, function(self, superFunc)
    local vehicle = self.vehicle
    if vehicle ~= nil then
        local spec_rms = vehicle.spec_RealisticMechanicalSystems
        if spec_rms ~= nil and spec_rms.activeEffects ~= nil then
            local effect = spec_rms.activeEffects.POWERSHIFT_ENGAGEMENT_LAG_AND_HARSH_EFFECT
            if effect ~= nil and effect.value ~= nil and effect.extraData.status == "IDLE" then
                if effect.value >= 1.0 then
                    self.targetGear = self.previousGear
                    return superFunc(self)
                end
                effect.extraData.status = "DELAYED"
                effect.extraData.timer = 0
                return
            end
        end
    end
    return superFunc(self)
end)


---Tells whether a folded implement blocks the hydraulic drift
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

---Bypasses the implement speed limit so the forced drop can run
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

---Puts the implement speed limit back
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

---Returns the lifted mass over the hydraulic capacity of the vehicle
local function getHydraulicMassRatio(vehicle, mass)
    return math.clamp(mass / math.max(vehicle:getTotalMass(true), 0.01), 0, 1)
end

-- @param table spec RMS spec of the vehicle
-- @param string effectId effect id
-- @return table? breakdown active breakdown
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

    ---Walks the implement chain looking for a hydraulic function to act on
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

RMS_Breakdowns.EffectApplicators.CAB_DAMPING_MODIFIER = {
    apply = function(vehicle, effectData, handler)
        for _, suspension in ipairs(vehicle.spec_suspensions.suspensionNodes) do
            if suspension.isRotational and not suspension.useCharacterTorso then
                local parameters = suspension.suspensionParameters
                suspension.rmsDamping = suspension.rmsDamping or { parameters[1][2], parameters[2][2], parameters[3][2] }
                for axis = 1, 3 do
                    parameters[axis][2] = suspension.rmsDamping[axis] * (1 + effectData.value)
                end
            end
        end
    end,

    remove = function(vehicle, handler)
        for _, suspension in ipairs(vehicle.spec_suspensions.suspensionNodes) do
            if suspension.rmsDamping ~= nil then
                for axis = 1, 3 do
                    suspension.suspensionParameters[axis][2] = suspension.rmsDamping[axis]
                end
            end
        end
    end
}

-- @param string effectName effect id
-- @param string flag field marking the function it acts on
-- @return table applicator
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

            addFuncToActive(vehicle, effectName, activeFunc)
            activeFunc(vehicle, 0)
        end,

        remove = function(vehicle, handler)
            setHydraulicTarget(vehicle, 0, flag)
            removeFuncFromActive(vehicle, handler.getEffectName())
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
        addFuncToActive(vehicle, handler.getEffectName(), activeFunc)
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

        removeFuncFromActive(vehicle, handler.getEffectName())
    end
}

---Slows the attacher joint movement by the hydraulic effects
-- @param table self vehicle
-- @param function superFunc super function
-- @param float dt time since last call in ms
-- @param any ... further arguments
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
-- @param table self vehicle
-- @param function superFunc super function
-- @param float dt time since last call in ms
-- @param any ... further arguments
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
-- @param table self vehicle
-- @param function superFunc super function
-- @param float dt time since last call in ms
-- @param any ... further arguments
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
-- @param table self vehicle
-- @param function superFunc super function
-- @param entityId actorId actor id
-- @param float x hit x position
-- @param float y hit y position
-- @param float z hit z position
-- @param float distance hit distance
-- @param float nx hit normal x
-- @param float ny hit normal y
-- @param float nz hit normal z
-- @param integer subShapeIndex sub shape index
-- @param entityId shapeId shape id
-- @param boolean isLast true on the last hit
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
-- @param table vehicle vehicle
-- @param function superFunc super function
-- @param boolean onlyIfWorking only if working
-- @return float speedLimit speed limit
function RMS_Breakdowns.getSpeedLimitOverwrite(vehicle, superFunc, onlyIfWorking)
    local speedLimit, doCheckSpeedLimit = superFunc(vehicle, onlyIfWorking)

    local spec_rms = vehicle.spec_RealisticMechanicalSystems
    if spec_rms == nil or spec_rms.activeEffects == nil then
        return speedLimit, doCheckSpeedLimit
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

RMS_Breakdowns.EffectApplicators.CONDITION_WEAR_MODIFIER = {
    apply = function(vehicle, effectData, handler)
        local spec = vehicle.spec_RealisticMechanicalSystems
        spec.extraConditionWear = effectData.value
    end,

    remove = function(vehicle, handler)
        local spec = vehicle.spec_RealisticMechanicalSystems
        spec.extraConditionWear = 0
    end
}

RMS_Breakdowns.EffectApplicators.SERVICE_WEAR_MODIFIER = {
    apply = function(vehicle, effectData, handler)
        local spec = vehicle.spec_RealisticMechanicalSystems
        spec.extraServiceWear = effectData.value
    end,

    remove = function(vehicle, handler)
        local spec = vehicle.spec_RealisticMechanicalSystems
        spec.extraServiceWear = 0
    end
}

RMS_Breakdowns.EffectApplicators.ENGINE_HEAT_MODIFIER = {
    apply = function(vehicle, effectData, handler)
        local spec = vehicle.spec_RealisticMechanicalSystems
        spec.extraEngineHeat = effectData.value
    end,

    remove = function(vehicle, handler)
        local spec = vehicle.spec_RealisticMechanicalSystems
        spec.extraEngineHeat = 0
    end
}

RMS_Breakdowns.EffectApplicators.TRANSMISSION_HEAT_MODIFIER = {
    apply = function(vehicle, effectData, handler)
        local spec = vehicle.spec_RealisticMechanicalSystems
        spec.extraTransmissionHeat = effectData.value
    end,

    remove = function(vehicle, handler)
        local spec = vehicle.spec_RealisticMechanicalSystems
        spec.extraTransmissionHeat = 0
    end
}

RMS_Breakdowns.EffectApplicators.HYDRAULIC_HEAT_MODIFIER = {
    apply = function(vehicle, effectData, handler)
        local spec = vehicle.spec_RealisticMechanicalSystems
        spec.extraHydraulicHeat = effectData.value
    end,

    remove = function(vehicle, handler)
        local spec = vehicle.spec_RealisticMechanicalSystems
        spec.extraHydraulicHeat = 0
    end
}

RMS_Breakdowns.EffectApplicators.THERMOSTAT_HEALTH_MODIFIER = {
    apply = function(vehicle, effectData, handler)
        local spec = vehicle.spec_RealisticMechanicalSystems
        spec.thermostatHealth = math.max(1.0 + effectData.value, 0.1)
    end,

    remove = function(vehicle, handler)
        local spec = vehicle.spec_RealisticMechanicalSystems
        spec.thermostatHealth = 1.0
    end
}

RMS_Breakdowns.EffectApplicators.COOLANT_LEAK_RATE = {
    apply = function(vehicle, effectData, handler)
        local spec = vehicle.spec_RealisticMechanicalSystems
        spec.coolantLeakRate = math.max(effectData.value, 0)
    end,

    remove = function(vehicle, handler)
        local spec = vehicle.spec_RealisticMechanicalSystems
        spec.coolantLeakRate = 0
    end
}

RMS_Breakdowns.EffectApplicators.TRANSMISSION_OIL_LEAK_RATE = {
    apply = function(vehicle, effectData, handler)
        local spec = vehicle.spec_RealisticMechanicalSystems
        spec.transmissionOilLeakRate = math.max(effectData.value, 0)
    end,

    remove = function(vehicle, handler)
        local spec = vehicle.spec_RealisticMechanicalSystems
        spec.transmissionOilLeakRate = 0
    end
}

RMS_Breakdowns.EffectApplicators.HYDRAULIC_FLUID_LEAK_RATE = {
    apply = function(vehicle, effectData, handler)
        local spec = vehicle.spec_RealisticMechanicalSystems
        spec.hydraulicFluidLeakRate = math.max(effectData.value, 0)
    end,

    remove = function(vehicle, handler)
        local spec = vehicle.spec_RealisticMechanicalSystems
        spec.hydraulicFluidLeakRate = 0
    end
}

RMS_Breakdowns.EffectApplicators.RADIATOR_HEALTH_MODIFIER = {
    apply = function(vehicle, effectData, handler)
        local spec = vehicle.spec_RealisticMechanicalSystems
        spec.radiatorHealth = math.max(1.0 + effectData.value, 0.1)
    end,

    remove = function(vehicle, handler)
        local spec = vehicle.spec_RealisticMechanicalSystems
        spec.radiatorHealth = 1.0
    end
}

RMS_Breakdowns.EffectApplicators.BATTERY_HEALTH_MODIFIER = {
    apply = function(vehicle, effectData, handler)
        local spec = vehicle.spec_RealisticMechanicalSystems
        spec.batteryHealth = math.max(1.0 + effectData.value, 0.0001)
    end,

    remove = function(vehicle, handler)
        local spec = vehicle.spec_RealisticMechanicalSystems
        spec.batteryHealth = 1.0
    end
}

RMS_Breakdowns.EffectApplicators.ALTERNATOR_HEALTH_MODIFIER = {
    apply = function(vehicle, effectData, handler)
        local spec = vehicle.spec_RealisticMechanicalSystems
        spec.alternatorHealth = math.max(1.0 + effectData.value, 0.0001)
    end,

    remove = function(vehicle, handler)
        local spec = vehicle.spec_RealisticMechanicalSystems
        spec.alternatorHealth = 1.0
    end
}

RMS_Breakdowns.EffectApplicators.STARTER_HEALTH_MODIFIER = {
    apply = function(vehicle, effectData, handler)
        local spec = vehicle.spec_RealisticMechanicalSystems
        spec.starterHealth = math.max(1.0 + effectData.value, 0)
    end,

    remove = function(vehicle, handler)
        local spec = vehicle.spec_RealisticMechanicalSystems
        spec.starterHealth = 1.0
    end
}

RMS_Breakdowns.EffectApplicators.PARK_BRAKE_DRAG_EFFECT = {
    apply = function(vehicle, effectData, handler)
        vehicle.spec_RealisticMechanicalSystems.parkBrakeDrag = effectData.value
        RMS_Drivetrain.refreshParkBrakePedal(vehicle)
    end,

    remove = function(vehicle, handler)
        vehicle.spec_RealisticMechanicalSystems.parkBrakeDrag = 0
        RMS_Drivetrain.refreshParkBrakePedal(vehicle)
    end
}

RMS_Breakdowns.EffectApplicators.FAN_CLUTCH_MODIFIER = {
    apply = function(vehicle, effectData, handler)
        local spec = vehicle.spec_RealisticMechanicalSystems
        spec.fanClutchHealth = math.max(1.0 + effectData.value, 0.1)
    end,

    remove = function(vehicle, handler)
        local spec = vehicle.spec_RealisticMechanicalSystems
        spec.fanClutchHealth = 1.0
    end
}

RMS_Breakdowns.EffectApplicators.THERMOSTAT_STUCK_EFFECT = {
    apply = function(vehicle, effectData, handler)
        vehicle.spec_RealisticMechanicalSystems.thermostatStuckedPosition = effectData.extraData.stuckPosition
    end,

    remove = function(vehicle, handler)
        local spec = vehicle.spec_RealisticMechanicalSystems
        spec.thermostatStuckedPosition = nil
    end
}

RMS_Breakdowns.EffectApplicators.TRANSMISSION_THERMOSTAT_HEALTH_MODIFIER = {
    apply = function(vehicle, effectData, handler)
        local spec = vehicle.spec_RealisticMechanicalSystems
        spec.transmissionThermostatHealth = math.max(1.0 + effectData.value, 0.1)
    end,

    remove = function(vehicle, handler)
        local spec = vehicle.spec_RealisticMechanicalSystems
        spec.transmissionThermostatHealth = 1.0
    end
}

RMS_Breakdowns.EffectApplicators.TRANSMISSION_THERMOSTAT_STUCK_EFFECT = {
    apply = function(vehicle, effectData, handler)
        local spec = vehicle.spec_RealisticMechanicalSystems

        if spec.transmissionThermostatStuckedPosition == nil or spec.transmissionThermostatStuckedPosition < 0 then
            spec.transmissionThermostatStuckedPosition = spec.transmissionThermostatState
        end
    end,

    remove = function(vehicle, handler)
        local spec = vehicle.spec_RealisticMechanicalSystems
        spec.transmissionThermostatStuckedPosition = nil
    end
}

---Swings the idle rpm while the hunting effect runs, and restores it afterwards
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

RMS_Breakdowns.EffectApplicators.IDLE_HUNTING_EFFECT = {
    getEffectName = function()
        return "IDLE_HUNTING_EFFECT" 
    end,

    apply = function(vehicle, effectData, handler)

        local effectName = handler.getEffectName()
        local motor = vehicle:getMotor()
        local spec = vehicle.spec_RealisticMechanicalSystems

        if spec.idleHuntingRpmBackup == nil then
            spec.idleHuntingRpmBackup = motor.minRpm
        end

        local activeFunc = function(v, dt)
            local activeSpec = v.spec_RealisticMechanicalSystems
            activeSpec.idleHuntingRpmBackup = updateIdleHuntingMotor(
                motor,
                effectData,
                dt,
                activeSpec.idleHuntingRpmBackup,
                v:getIsMotorStarted() and v:getLastSpeed() < 0.01,
                true,
                false
            )
        end
        addFuncToActive(vehicle, effectName, activeFunc)
    end,

    remove = function(vehicle, handler)
        local spec = vehicle.spec_RealisticMechanicalSystems
        local motor = vehicle:getMotor()

        if spec.idleHuntingRpmBackup ~= nil then
            motor.minRpm = spec.idleHuntingRpmBackup
        end

        spec.idleHuntingRpmBackup = nil
        removeFuncFromActive(vehicle, handler.getEffectName())
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

        addFuncToActive(vehicle, effectName, activeFunc)
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
        removeFuncFromActive(vehicle, handler.getEffectName())
    end
}

RMS_Breakdowns.EffectApplicators.ELECTRICAL_LEAKAGE_EFFECT = {
    apply = function(vehicle, effectData, handler)
        vehicle.spec_RealisticMechanicalSystems.circuitLeakageFactor = effectData.value
    end,

    remove = function(vehicle, handler)
        vehicle.spec_RealisticMechanicalSystems.circuitLeakageFactor = 0
    end
}

RMS_Breakdowns.EffectApplicators.ELECTRICAL_CONTACT_RESISTANCE_EFFECT = {
    apply = function(vehicle, effectData, handler)
        vehicle.spec_RealisticMechanicalSystems.circuitResistanceFactor = effectData.value
    end,

    remove = function(vehicle, handler)
        vehicle.spec_RealisticMechanicalSystems.circuitResistanceFactor = 0
    end
}




---Stops a noise sample and clears its offsets
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

---Eases a noise gate toward its target
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

-- @param string effectName effect id
-- @param string sampleName sample of the clunks
-- @param function getIsMoving tells whether the joint moves this frame
-- @return table applicator
local function createClunkEffectApplicator(effectName, sampleName, getIsMoving)
    return {
        getEffectName = function()
            return effectName
        end,

        apply = function(vehicle, effectData, handler)
            addFuncToActive(vehicle, effectName, function(v, dt)
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
            removeFuncFromActive(vehicle, handler.getEffectName())
        end
    }
end

---Builds an effect applicator that plays one engine noise sample through a gate
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

            addFuncToActive(vehicle, effectName, activeFunc)
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
            removeFuncFromActive(vehicle, handler.getEffectName())
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
        addFuncToActive(vehicle, effectName, activeFunc)
    end,

    remove = function(vehicle, handler)
        removeFuncFromActive(vehicle, handler.getEffectName())
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
        addFuncToActive(vehicle, effectName, activeFunc)
    end,
    remove = function(vehicle, handler)
        removeFuncFromActive(vehicle, handler.getEffectName())
    end,
}

-- @param string effectName effect id
-- @param string side "rear" or "front"
-- @param string messageKey warning shown to the driver
-- @return table applicator
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
                    elseif v:getIsActiveForInput(true) then
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

            addFuncToActive(vehicle, effectName, activeFunc)
        end,
        remove = function(vehicle, handler)
            removeFuncFromActive(vehicle, handler.getEffectName())
        end
    }
end

---Builds the applicator that keeps one side of the PTO from running
-- @param string effectName effect id
-- @param string side "rear" or "front"
-- @return table applicator
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
            addFuncToActive(vehicle, effectName, activeFunc)
        end,
        remove = function(vehicle, handler)
            removeFuncFromActive(vehicle, handler.getEffectName())
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

RMS_Breakdowns.EffectApplicators.PTO_ENGAGEMENT_BLOCKED_CHANCE = {
    getEffectName = function() return "PTO_ENGAGEMENT_BLOCKED_CHANCE" end,
    apply = function(vehicle, effectData, handler)
    end,
    remove = function(vehicle, handler)
    end
}

---Blocks turning an implement on while the PTO engagement is blocked
-- @param table vehicle vehicle
-- @param function superFunc super function
-- @return boolean canBeTurnedOn true when it may start
function RMS_Breakdowns.getCanBeTurnedOn(vehicle, superFunc)
    local canBeTurnedOn, warning = superFunc(vehicle)
    if not canBeTurnedOn or vehicle.getIsTurnedOn == nil or vehicle:getIsTurnedOn() then
        return canBeTurnedOn, warning
    end

    local rootVehicle = vehicle.rootVehicle
    local spec = rootVehicle ~= nil and rootVehicle.spec_RealisticMechanicalSystems or nil
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

---Runs a callback while the PTO engagement attempt is being counted
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
-- @param table vehicle vehicle
-- @param function superFunc super function
-- @param string actionName input action name
-- @param float inputValue input value
-- @param any callbackState callback state
-- @param boolean isAnalog true for an analog input
function RMS_Breakdowns.actionEventTurnOn(vehicle, superFunc, actionName, inputValue, callbackState, isAnalog)
    return runWithPtoEngagementAttempt(vehicle, function()
        return superFunc(vehicle, actionName, inputValue, callbackState, isAnalog)
    end)
end

---Counts a PTO engagement attempt around the action controller turn on
-- @param table vehicle vehicle
-- @param function superFunc super function
-- @param integer direction turn on direction
function RMS_Breakdowns.actionControllerTurnOnEvent(vehicle, superFunc, direction)
    return runWithPtoEngagementAttempt(vehicle, function()
        return superFunc(vehicle, direction)
    end)
end

-- Switch off only at the source of the event.
-- @param table vehicle vehicle
-- @param function superFunc super function
-- @param boolean isTurnedOn true to turn it on
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


---Counts the time the starter has turned and tells whether the engine catches
local function tryStartMotor(effect, dt, engTemp)
    local data = effect.extraData
    data.crankedMs = data.crankedMs + dt

    local seconds = effect.value
    if engTemp <= -10 then
        seconds = seconds + (-10 - engTemp) / 2
    elseif engTemp >= 30 then
        seconds = seconds * (1 - 0.3 * math.clamp((engTemp - 30) / 60, 0, 1))
    end

    return data.crankSpeed >= RMS_Config.ELECTRICAL.FIRING_CRANKING_SPEED and data.crankedMs >= seconds * 1000 / data.crankSpeed
end

---Installs the hard start effect, cranking until the engine catches or gives up
local function applyHardStartModifier(vehicle, effectName)
    local activeFunc = function(v, dt)
        local spec = v.spec_RealisticMechanicalSystems
        if spec == nil then return end
        local effect = spec.activeEffects ~= nil and spec.activeEffects[effectName] or nil
        if effect == nil or effect.extraData == nil then
            return
        end

        if effect.extraData.status == "CRANKING" and effect.extraData.crankSpeed == nil then
            effect.extraData.crankSpeed = RMS_Electrical.getCrankingSpeed(v)
            effect.extraData.crankedMs = 0
        end

        effect.extraData.timer = math.max((effect.extraData.timer or 0) - dt, 0)

        if effect.extraData.timer <= 0 and effect.extraData.status == "PASSED" then
            if v.getCanMotorRun == nil or v:getCanMotorRun() then
                v:startMotor(false, true)
            end
            effect.extraData.status = "IDLE"
            effect.extraData.crankSpeed = nil
            effect.extraData.automaticCrank = false
        end

        local startRequestActive = getIsStarterRequestActive(v, effect)
        if not v:getIsMotorStarted() and startRequestActive and effect.extraData.status == "CRANKING" then
            local rawEngineTemp = spec.rawEngineTemperature or spec.engineTemperature or -99
            if v.isServer
                and effect.extraData.blockStart ~= true
                and tryStartMotor(effect, dt, rawEngineTemp) then
                local catchDelay = RMS_Breakdowns.getStarterCatchDelay(v, effect.extraData.crankSpeed)
                effect.extraData.timer = catchDelay
                effect.extraData.status = "PASSED"
                RMS_Preheat.onCrankPassed(v)
                RMS_EffectSyncEvent.send(v, effectName, "PASSED", catchDelay, 0, 0)
            end
        elseif not startRequestActive and effect.extraData.status == "CRANKING" then
            effect.extraData.status = "IDLE"
            effect.extraData.crankSpeed = nil
            effect.extraData.automaticCrank = false
        end
    end

    addFuncToActive(vehicle, effectName, activeFunc)
end

---Removes the hard start effect
local function removeHardStartModifier(vehicle, effectName)
    local effect = vehicle.spec_RealisticMechanicalSystems
        and vehicle.spec_RealisticMechanicalSystems.activeEffects
        and vehicle.spec_RealisticMechanicalSystems.activeEffects[effectName]
        or nil
    if effect ~= nil and effect.extraData ~= nil then
        effect.extraData.status = "IDLE"
        effect.extraData.timer = 0
        effect.extraData.crankSpeed = nil
        effect.extraData.automaticCrank = false
    end
    removeFuncFromActive(vehicle, effectName)
end

RMS_Breakdowns.EffectApplicators.ENGINE_HARD_START_MODIFIER = {
    getEffectName = function() return "ENGINE_HARD_START_MODIFIER" end,
    apply = function(vehicle, effectData, handler)
        applyHardStartModifier(vehicle, handler.getEffectName())
    end,
    remove = function(vehicle, handler)
        removeHardStartModifier(vehicle, handler.getEffectName())
    end
}

RMS_Breakdowns.EffectApplicators.GLOW_PLUG_HARD_START_MODIFIER = {
    getEffectName = function() return "GLOW_PLUG_HARD_START_MODIFIER" end,
    apply = function(vehicle, effectData, handler)
        applyHardStartModifier(vehicle, handler.getEffectName())
    end,
    remove = function(vehicle, handler)
        removeHardStartModifier(vehicle, handler.getEffectName())
    end
}

---Tracks the start button state and forwards it to the server
-- @param table self vehicle
-- @param string actionName input action name
-- @param float inputValue input value
-- @param any callbackState callback state
-- @param boolean isAnalog true for an analog input
-- @param boolean isMouse true for a mouse input
-- @param integer deviceCategory input device category
-- @param any binding input binding
function RMS_Breakdowns.onStartButtonAction(self, actionName, inputValue, callbackState, isAnalog, isMouse, deviceCategory, binding)
    local spec = self ~= nil and self.spec_RealisticMechanicalSystems or nil
    if spec == nil then
        return
    end

    local value = tonumber(inputValue) or 0
    local isPressed = binding ~= nil and binding.isPressed == true
    local currentlyHeld = isPressed or value > 0.5
    local wasHeld = spec.startButtonHeld == true

    local _prevStartButtonDown = spec.startButtonDown
    local _prevStartButtonUp = spec.startButtonUp
    local _prevStartButtonHeld = spec.startButtonHeld

    spec.startButtonDown = currentlyHeld and not wasHeld
    spec.startButtonUp = not currentlyHeld and wasHeld
    spec.startButtonHeld = currentlyHeld

    if _prevStartButtonDown ~= spec.startButtonDown or _prevStartButtonUp ~= spec.startButtonUp or _prevStartButtonHeld ~= spec.startButtonHeld then
        RMS_StartButtonEvent.send(self, spec.startButtonDown, spec.startButtonHeld, spec.startButtonUp)
    end

    if spec.startButtonDown then
        playDeadStartSound(self)
        local wasPreheatFailed = RMS_Preheat.isFailed(self)
        RMS_Preheat.requestStart(self)

        if wasPreheatFailed then
            return
        end

        local automaticMotorStartEnabled = g_currentMission.missionInfo.automaticMotorStartEnabled == true

        if not automaticMotorStartEnabled then
            if actionName == InputAction.TOGGLE_MOTOR_STATE then
                Motorized.actionEventToggleMotorState(self, actionName, inputValue, callbackState, isAnalog)
            elseif actionName == InputAction.MOTOR_STATE_ON then
                Motorized.actionEventSetMotorStateOn(self, actionName, inputValue, callbackState, isAnalog)
            end
        end
    end
end

---Tells whether failing glow plugs block a cold start
local function isColdGlowPlugStartBlocked(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    if spec == nil or spec.isExcludedVehicle or spec.activeEffects == nil then
        return false
    end

    local effect = spec.activeEffects.GLOW_PLUG_HARD_START_MODIFIER

    return effect ~= nil
        and effect.extraData ~= nil
        and effect.extraData.blockStart == true
        and RMS_Preheat.isColdStartAssistanceRequired(vehicle)
end

---Blocks the AI helper from starting a vehicle whose engine cannot run
-- @param table self vehicle
-- @param function superFunc super function
-- @param any ... further arguments
-- @return boolean canStart true when the helper may start it
function RMS_Breakdowns.getCanStartAIVehicle(self, superFunc, ...)
    if not superFunc(self, ...) then
        return false
    end

    if self.getIsMotorStarted ~= nil
        and not self:getIsMotorStarted()
        and isColdGlowPlugStartBlocked(self) then
        return false
    end

    return true
end

---Runs the hard start sequence before letting the vanilla start go through
-- @param table self vehicle
-- @param function superFunc super function
-- @param boolean noEventSend no event send
-- @param boolean passed true once the start already went through
function RMS_Breakdowns.startMotor(self, superFunc, noEventSend, passed)
    local spec = self.spec_RealisticMechanicalSystems
    local reason = RMS_Breakdowns.getStartBlockReason(self)
    if reason ~= nil then
        if self.isClient and self:getIsActiveForInput(true) then
            g_currentMission:showBlinkingWarning(g_i18n:getText(reason), 2000)
        end
        return
    end
    if self.isServer and spec ~= nil and spec.batteryIsolated then
        RMS_Electrical.setBatteryIsolated(self, false)
    end
    local engineFailure = spec and spec.activeEffects.ENGINE_FAILURE
    local engineHardStart = spec and spec.activeEffects.ENGINE_HARD_START_MODIFIER
    local glowPlugHardStart = spec and spec.activeEffects.GLOW_PLUG_HARD_START_MODIFIER
    if spec ~= nil and spec.isElectricVehicle then
        engineHardStart = nil
    end
    if glowPlugHardStart ~= nil and not RMS_Preheat.shouldApplyGlowPlugHardStart(self) then
        glowPlugHardStart = nil
    end
    local isGlowPlugStartBlocked = glowPlugHardStart ~= nil
        and glowPlugHardStart.extraData.blockStart == true

    if self:getIsAIActive() and not engineFailure then
        if isColdGlowPlugStartBlocked(self) then
            return
        end

        superFunc(self, noEventSend)
        return
    end

    if RMS_Preheat.shouldDeferStart(self, passed) then
        return
    end

    local selectedHardStart = engineHardStart
    local selectedHardStartId = "ENGINE_HARD_START_MODIFIER"
    if glowPlugHardStart ~= nil
        and (isGlowPlugStartBlocked
            or selectedHardStart == nil
            or glowPlugHardStart.value > selectedHardStart.value) then
        selectedHardStart = glowPlugHardStart
        selectedHardStartId = "GLOW_PLUG_HARD_START_MODIFIER"
    end

    local automaticMotorStartEnabled = g_currentMission.missionInfo.automaticMotorStartEnabled == true
    local hasManualStartInput = spec ~= nil and (spec.startButtonHeld == true
        or spec.startButtonDown == true
        or RMS_Preheat.isAutomaticCrankActive(self))
    local isAutomaticStartAttempt = automaticMotorStartEnabled and not hasManualStartInput


    if spec == nil or (engineFailure == nil and selectedHardStart == nil) or passed then
        superFunc(self, noEventSend)
        return
    end

    if engineFailure then
        if engineFailure.extraData.starter then
            if isAutomaticStartAttempt then
                return
            end
            if engineFailure.extraData.status == 'IDLE' then
                local automaticCrank = RMS_Preheat.isAutomaticCrankActive(self)
                engineFailure.extraData.status = 'CRANKING'
                engineFailure.extraData.automaticCrank = automaticCrank
                RMS_EffectSyncEvent.send(self, 'ENGINE_FAILURE', "CRANKING", 0, automaticCrank and 1 or 0, 0)
            end
        end
        return
    end

    if selectedHardStart and selectedHardStart.extraData.status == 'IDLE' then
        if isAutomaticStartAttempt then
            return
        end
        local automaticCrank = RMS_Preheat.isAutomaticCrankActive(self)
        selectedHardStart.extraData.status = 'CRANKING'
        selectedHardStart.extraData.automaticCrank = automaticCrank
        RMS_EffectSyncEvent.send(self, selectedHardStartId, "CRANKING", 0, automaticCrank and 1 or 0, 0)
        return
    end
end

---Stops the starter and clears the cranking state
-- @param table? vehicle vehicle
function RMS_Breakdowns.cancelStarterCranking(vehicle)
    local spec = vehicle ~= nil and vehicle.spec_RealisticMechanicalSystems or nil
    if spec == nil or spec.activeEffects == nil then
        return
    end

    for _, effectId in ipairs({ "ENGINE_FAILURE", "ENGINE_HARD_START_MODIFIER", "GLOW_PLUG_HARD_START_MODIFIER" }) do
        local effect = spec.activeEffects[effectId]
        if effect ~= nil and effect.extraData ~= nil and effect.extraData.status == "CRANKING" then
            effect.extraData.status = "IDLE"
            effect.extraData.timer = 0
            effect.extraData.crankSpeed = nil
            effect.extraData.automaticCrank = false
            RMS_EffectSyncEvent.send(vehicle, effectId, "IDLE", 0, 0, 0)
        end
    end
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
        addFuncToActive(vehicle, effectName, activeFunc)
    end,
    remove = function(vehicle, handler)
        removeFuncFromActive(vehicle, handler.getEffectName())
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
        addFuncToActive(vehicle, effectName, activeFunc)
    end,

    remove = function(vehicle, handler)
        removeFuncFromActive(vehicle, handler.getEffectName())
    end
}

RMS_Breakdowns.EffectApplicators.EMPTY_EFFECT = {
}

---Returns the text refusing a start
-- @param table vehicle vehicle
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

-- @param table self vehicle
-- @param function superFunc super function
-- @return boolean canRun true when the engine may run
function RMS_Breakdowns.getCanMotorRun(self, superFunc)
    local spec = self.spec_RealisticMechanicalSystems
    if spec == nil or spec.isExcludedVehicle then
        return superFunc(self)
    end

    if RMS_Breakdowns.getStartBlockReason(self) ~= nil then return false end

    if (spec and spec.activeEffects.ENGINE_FAILURE) then
        if not spec.activeEffects.ENGINE_FAILURE.extraData.starter then
            return false
        end
    elseif self:isUnderService() then
        if self:getIsActiveForInput(true) then
            g_currentMission:showBlinkingWarning(g_i18n:getText(self:getCurrentStatus()) .. " " .. g_i18n:getText("rms_breakdown_at_progress_message", 100)) 
        end
        return false
    end

    if RMS_Preheat.shouldBlockMotorRun(self, superFunc) then
        return false
    end

    return superFunc(self)
end
