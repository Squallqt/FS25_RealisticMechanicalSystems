-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---Exhaust smoke model, colouring and driving the plume particles from soot, oil, unburnt fuel and gas flow
RMS_Exhaust = RMS_Exhaust or {}
RMS_Exhaust.modDirectory = g_currentModDirectory

-- plume sources loaded once for the session, every vehicle cloning from them
RMS_Exhaust.plumeSources = nil

---Clamps a value between two bounds
-- @param float value value to clamp
-- @param float minimum lower bound
-- @param float maximum upper bound
-- @return float value clamped value
local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(value, maximum))
end

---Interpolates linearly between two values
-- @param float startValue value at alpha 0
-- @param float endValue value at alpha 1
-- @param float alpha interpolation factor
-- @return float value interpolated value
local function lerp(startValue, endValue, alpha)
    return startValue + (endValue - startValue) * alpha
end

---Converts a value to a number, rejecting nan and infinity, then clamps it
-- @param any value value to convert
-- @param float defaultValue value used when the conversion fails
-- @param float? minimum lower bound
-- @param float? maximum upper bound
-- @return float number converted number
local function getNumber(value, defaultValue, minimum, maximum)
    local number = tonumber(value)
    if number == nil or number ~= number or number == math.huge or number == -math.huge then
        number = defaultValue
    end
    if minimum ~= nil then
        number = math.max(number, minimum)
    end
    if maximum ~= nil then
        number = math.min(number, maximum)
    end

    return number
end

---Maps a value onto a 0 to 1 ramp between two thresholds
-- @param float value value to map
-- @param float from value mapping to 0
-- @param float to value mapping to 1
-- @return float ratio position on the ramp
local function getRamp(value, from, to)
    if to <= from then
        return value >= to and 1 or 0
    end

    return clamp((value - from) / (to - from), 0, 1)
end

---Returns the emission factor of the production year, read from an era table
-- @param integer? year vehicle production year
-- @param table? eraFactors era table, the particulate one by default
-- @return float factor era emission factor
function RMS_Exhaust.getEraFactor(year, eraFactors)
    local factors = eraFactors or RMS_Config.EXHAUST.ERA_FACTORS
    local resolvedYear = getNumber(year, RMS_VehicleYears ~= nil and RMS_VehicleYears.DEFAULT_YEAR or 2000)
    for _, entry in ipairs(factors) do
        if resolvedYear < entry[1] then
            return entry[2]
        end
    end

    return factors[#factors][2]
end

---Tells whether the engine falls under Stage V, on its power band and production year
-- @param integer? year vehicle production year
-- @param float? peakPowerKw peak engine power in kw
-- @return boolean isStageV true for a Stage V engine
function RMS_Exhaust.getIsStageV(year, peakPowerKw)
    local config = RMS_Config.EXHAUST.STAGE_V
    local resolvedYear = getNumber(year, RMS_VehicleYears ~= nil and RMS_VehicleYears.DEFAULT_YEAR or 2000)
    local power = getNumber(peakPowerKw, 0, 0)
    if power < config.MIN_POWER_KW or power > config.MAX_POWER_KW then
        return false
    end

    if power >= config.MID_POWER_MIN_KW and power < config.MID_POWER_MAX_KW then
        return resolvedYear >= config.MID_POWER_YEAR
    end

    return resolvedYear >= config.OUTER_POWER_YEAR
end

---Builds wet stacking up while a diesel engine idles, and burns it off under load once warm
-- @param table input current level, engine state, load, idle timer and temperature
-- @return float level wet stacking level between 0 and 1
function RMS_Exhaust.calculateWetStackingLevel(input)
    local currentLevel = getNumber(input.currentLevel, 0, 0, 1)
    if input.isDiesel ~= true then
        return 0
    end
    if input.isMotorStarted ~= true then
        return currentLevel
    end

    local fuelConfig = RMS_Config.CORE.FUEL_FACTOR_DATA
    local idleTimer = getNumber(input.idleTimer, 0, 0, fuelConfig.IDLE_DEPOSIT_FACTOR_MAX_TIMER)
    local load = getNumber(input.load, 0, 0, 1.5)
    local dt = getNumber(input.dt, 100, 1)
    local coldTemperature = RMS_Config.CORE.ENGINE_FACTOR_DATA.COLD_MOTOR_TEMP_THRESHOLD
    local operatingTemperature = RMS_Config.THERMAL.PID_TARGET_TEMP
    local engineTemperature = getNumber(input.engineTemperature, operatingTemperature, -80, 160)

    if input.isIdle == true then
        if idleTimer < fuelConfig.IDLE_DEPOSIT_FACTOR_TIMER_THRESHOLD then
            return currentLevel
        end

        local coldRisk = 1 - getRamp(engineTemperature, coldTemperature, operatingTemperature)
        local coldMultiplier = 1 + coldRisk
        local idleStep = dt / 1000
        local threshold = fuelConfig.IDLE_DEPOSIT_FACTOR_TIMER_THRESHOLD
        local buildupDuration = math.max(fuelConfig.IDLE_DEPOSIT_FACTOR_MAX_TIMER - threshold, 1)
        local previousIdleTimer = math.max(idleTimer - idleStep, 0)
        local buildupStart = math.max(previousIdleTimer, threshold)
        local buildupSeconds = math.max(idleTimer - buildupStart, 0)
        local buildup = (buildupSeconds / buildupDuration) * coldMultiplier

        return clamp(currentLevel + buildup, 0, 1)
    end

    local loadFactor = getRamp(load, fuelConfig.IDLE_DEPOSIT_LOAD_THRESHOLD, 1)
    local temperatureFactor = getRamp(engineTemperature, coldTemperature, operatingTemperature)
    local cleanupDuration = math.max(
        fuelConfig.IDLE_DEPOSIT_FACTOR_MAX_TIMER - fuelConfig.IDLE_DEPOSIT_FACTOR_TIMER_THRESHOLD,
        1
    )
    local cleanup = (dt / 1000) / cleanupDuration * loadFactor * temperatureFactor

    return clamp(currentLevel - cleanup, 0, 1)
end

---Returns the target soot, oil and unburnt fractions of the engine
-- @param table input engine, wear, breakdown and fuel inputs
-- @return table targets emission targets
function RMS_Exhaust.calculateTargets(input)
    local config = RMS_Config.EXHAUST
    local sootConfig = config.SOOT
    local oilConfig = config.OIL
    local unburntConfig = config.UNBURNT
    local load = getNumber(input.load, 0, 0, 1.5)
    local eraFactor = RMS_Exhaust.getEraFactor(input.year)
    local isStageV = RMS_Exhaust.getIsStageV(input.year, input.peakPowerKw)
    local wetStackingLevel = getNumber(input.wetStackingLevel, 0, 0, 1)

    -- nothing makes soot on its own, a deposit or a choked filter only dirty the fuel that burns
    local fuelDelivery = lerp(sootConfig.FUEL_IDLE_SHARE, 1, clamp(load, 0, 1))

    local sootContinuous = getRamp(load, sootConfig.LOAD_THRESHOLD, sootConfig.LOAD_FULL) * sootConfig.LOAD_MAX
    sootContinuous = sootContinuous + wetStackingLevel * sootConfig.WET_STACKING_MAX * fuelDelivery

    -- fuel enters before the turbo has the air to burn it, on a pickup and on a lugging engine alike
    local boostDeficit = 0
    if input.hasTurbo == true then
        boostDeficit = clamp(load - getNumber(input.boost, 0, 0, 1), 0, 1)
        sootContinuous = sootContinuous
            + getRamp(boostDeficit, sootConfig.BOOST_DEFICIT_THRESHOLD, sootConfig.BOOST_DEFICIT_FULL) * sootConfig.TRANSIENT_MAX
    end

    local clogging = getNumber(input.airFilterClogging, 0, 0, 1)
    local cloggingCurve = clogging * clogging
    if clogging > sootConfig.AIR_FILTER_KNEE then
        cloggingCurve = cloggingCurve + (clogging - sootConfig.AIR_FILTER_KNEE)
    end
    sootContinuous = sootContinuous + math.min(cloggingCurve, 1) * sootConfig.AIR_FILTER_MAX * fuelDelivery

    local serviceLoss = 1 - getNumber(input.serviceLevel, 1, 0, 1)
    sootContinuous = sootContinuous
        + getRamp(serviceLoss, sootConfig.SERVICE_THRESHOLD, 1) * sootConfig.SERVICE_MAX * fuelDelivery

    local breakdownFactor = math.max(eraFactor, config.ERA_BREAKDOWN_FLOOR)
    local sootBreakdown = getNumber(input.sootEffect, 0, 0, 1) * sootConfig.BREAKDOWN_MAX

    -- a fault upstream overwhelms a filter sized for normal running, so it keeps a floor
    local sootProfileFactor = 1
    if input.isMethane == true then
        sootProfileFactor = sootProfileFactor * config.METHANE_SOOT_FACTOR
    end
    if input.hasDEF == true then
        sootProfileFactor = sootProfileFactor * config.DEF_SOOT_FACTOR
    end
    if isStageV then
        sootProfileFactor = sootProfileFactor * config.STAGE_V.SOOT_FACTOR
    end
    local sootFaultFactor = math.max(sootProfileFactor, config.AFTERTREATMENT_FAULT_FLOOR)
    local soot = clamp(
        sootContinuous * eraFactor * sootProfileFactor + sootBreakdown * breakdownFactor * sootFaultFactor,
        0,
        1
    )

    local oilBreakdown = getNumber(input.oilEffect, 0, 0, 1) * oilConfig.BREAKDOWN_MAX
    if load <= oilConfig.IDLE_LOAD_THRESHOLD then
        oilBreakdown = oilBreakdown * oilConfig.IDLE_BOOST
    end
    local oil = clamp(oilBreakdown * breakdownFactor, 0, 1)

    local engineTemperature = getNumber(input.engineTemperature, unburntConfig.COLD_THRESHOLD_C, -80, 160)
    local cold = 1 - getRamp(engineTemperature, unburntConfig.COLD_FULL_C, unburntConfig.COLD_THRESHOLD_C)
    local unburntContinuous = cold * unburntConfig.COLD_MAX
    if input.isStarting == true then
        unburntContinuous = unburntContinuous * unburntConfig.CRANKING_BOOST
    end
    local preheatSeverity = getNumber(input.preheatSeverity, 0, 0, 4)
    unburntContinuous = unburntContinuous + (preheatSeverity / 4) * cold * unburntConfig.PREHEAT_FAULT_MAX
    local unburntBreakdown = getNumber(input.unburntEffect, 0, 0, 1) * unburntConfig.BREAKDOWN_MAX
    local unburntEraFactor = RMS_Exhaust.getEraFactor(input.year, config.UNBURNT_ERA_FACTORS)
    local unburnt = clamp(unburntContinuous * unburntEraFactor + unburntBreakdown * breakdownFactor, 0, 1)

    return {
        eraFactor = eraFactor,
        isStageV = isStageV,
        boostDeficit = boostDeficit,
        soot = soot,
        oil = oil,
        unburnt = unburnt
    }
end

---Returns the intensity of an active effect, 0 when absent
-- @param table spec vehicle spec
-- @param string effectId effect id
-- @return float intensity intensity between 0 and 1
local function getEffectIntensity(spec, effectId)
    local effect = spec.activeEffects ~= nil and spec.activeEffects[effectId] or nil
    return clamp(effect ~= nil and getNumber(effect.value, 0) or 0, 0, 1)
end

---Eases a value toward its target, rising and falling on their own time constants
-- @param float current current value
-- @param float target target value
-- @param float dt time since last call in ms
-- @param float? riseTau rise time constant in ms, the shared one by default
-- @param float? fallTau fall time constant in ms, the shared one by default
-- @return float value smoothed value
local function getSmoothed(current, target, dt, riseTau, fallTau)
    local tau = target > current and (riseTau or RMS_Config.EXHAUST.RISE_TAU)
        or (fallTau or RMS_Config.EXHAUST.FALL_TAU)
    local alpha = math.min(dt / (tau + dt), 1)

    return current + alpha * (target - current)
end

---Mixes the three smoke channels by concentration
-- @param float soot soot fraction
-- @param float oil oil fraction
-- @param float unburnt unburnt fuel fraction
-- @return float red
-- @return float green
-- @return float blue
local function getTintMix(soot, oil, unburnt)
    local config = RMS_Config.EXHAUST
    local total = soot + oil + unburnt
    if total <= 0 then
        return config.HEAT_TINT[1], config.HEAT_TINT[2], config.HEAT_TINT[3]
    end

    local sootTint = config.SOOT_TINT
    local oilTint = config.OIL_TINT
    local unburntTint = config.UNBURNT_TINT

    return (soot * sootTint[1] + oil * oilTint[1] + unburnt * unburntTint[1]) / total,
        (soot * sootTint[2] + oil * oilTint[2] + unburnt * unburntTint[2]) / total,
        (soot * sootTint[3] + oil * oilTint[3] + unburnt * unburntTint[3]) / total
end

---Turns the three channel concentrations into what the plume blocks of the light behind it
-- concentrations add up in optical depth, not in opacity, so the channels go through Beer-Lambert
-- @param float soot soot fraction
-- @param float oil oil fraction
-- @param float unburnt unburnt fuel fraction
-- @return float opacity opacity between 0 and 1
-- @return float opticalDepth optical depth of the three channels
local function getOpacity(soot, oil, unburnt)
    local config = RMS_Config.EXHAUST
    local opticalDepth = config.K_SOOT * soot + config.K_OIL * oil + config.K_UNBURNT * unburnt
    local raw = 1 - math.exp(-opticalDepth)
    local floor = config.OPACITY_FLOOR

    return math.max(raw - floor, 0) / (1 - floor), opticalDepth
end

---Returns the boost pressure of the motor, 0 on a naturally aspirated engine
-- @param table vehicle vehicle
-- @param table state exhaust smoke state
-- @return float boost boost between 0 and 1
local function getBoost(vehicle, state)
    if not state.hasTurbo then
        return 0
    end

    local motor = vehicle.getMotor ~= nil and vehicle:getMotor() or nil

    return motor ~= nil and getNumber(motor.lastTurboScale, 0, 0, 1) or 0
end

---Returns the current motor rpm as a fraction of its maximum
-- @param table vehicle vehicle
-- @return float scale rpm ratio, 0 without a motor
local function getRpmScale(vehicle)
    local motor = vehicle.getMotor ~= nil and vehicle:getMotor() or nil
    if motor == nil then
        return 0
    end

    local maxRpm = motor:getMaxRpm()
    if maxRpm == nil or maxRpm <= 0 then
        return 0
    end

    return (vehicle:getMotorRpmReal() or 0) / maxRpm
end

---Returns the gas flow leaving the pipe, 0 at rest and 1 at full rpm with the turbo up
-- normalised by the most the formula can reach, so the whole range is usable
-- @param table vehicle vehicle
-- @param table state exhaust smoke state
-- @return float flow gas flow between 0 and 1
local function getFlow(vehicle, state)
    local gain = RMS_Config.EXHAUST.FLOW_BOOST_GAIN

    return clamp(getRpmScale(vehicle) * (1 + gain * getBoost(vehicle, state)) / (1 + gain), 0, 1)
end

---Tells whether smoke is drawn, the motor being started or running
-- @param table vehicle vehicle
-- @return boolean isRendered true while smoke is drawn
local function getIsSmokeRendered(vehicle)
    local motorState = vehicle.getMotorState ~= nil and vehicle:getMotorState() or MotorState.OFF

    return motorState == MotorState.STARTING or motorState == MotorState.ON
end

---Returns the peak engine power
-- @param table vehicle vehicle
-- @return float power peak power in kw, 0 without a motor
local function getPeakPowerKw(vehicle)
    local motor = vehicle.getMotor ~= nil and vehicle:getMotor() or nil
    return motor ~= nil and getNumber(motor.peakMotorPower, 0, 0) or 0
end

---Reads the turbocharger and the DEF and methane consumers of the vehicle once and caches the result
-- @param table vehicle vehicle
-- @param table state exhaust smoke state
local function resolveEmissionProfile(vehicle, state)
    if state.profileResolved then
        return
    end

    state.hasTurbo = getPeakPowerKw(vehicle) >= RMS_Config.CORE.TURBO_MIN_POWER_KW

    local motorizedSpec = vehicle.spec_motorized
    local consumers = motorizedSpec ~= nil and motorizedSpec.consumersByFillTypeName or nil
    if consumers == nil then
        return
    end

    state.hasDEF = consumers["DEF"] ~= nil
    state.isMethane = consumers["METHANE"] ~= nil
    state.profileResolved = true
end

---Loads the emitter surface and the step sources once for the session
-- @return boolean loaded true once every source is available
local function loadPlumeSources()
    if RMS_Exhaust.plumeSources ~= nil then
        return RMS_Exhaust.plumeSources.isValid
    end

    local config = RMS_Config.EXHAUST
    local sources = {isValid = false, sprites = config.PLUME_SPRITES, steps = {}}
    RMS_Exhaust.plumeSources = sources

    local shapeRoot = loadI3DFile(RMS_Exhaust.modDirectory .. config.PLUME_EMIT_SHAPE, false, false, false)
    if shapeRoot == nil or shapeRoot == 0 then
        return false
    end

    local emitShape = getChildAt(shapeRoot, 0)
    if emitShape == nil or emitShape == 0 then
        return false
    end

    link(getRootNode(), emitShape)
    sources.emitShape = emitShape

    local directory = config.PLUME_DIRECTORY .. config.PLUME_SPRITES .. "/"
    for index, stepConfig in ipairs(config.PLUME_STEPS) do
        if stepConfig.isNative ~= true then
        local root = loadI3DFile(RMS_Exhaust.modDirectory .. directory .. stepConfig.file, false, false, false)
        if root == nil or root == 0 then
            return false
        end

        local node = getChildAt(root, 0)
        if node == nil or node == 0 then
            return false
        end

        link(getRootNode(), node)
        sources.steps[index] = node
        end
    end

    sources.isValid = true

    return true
end

---Tells how far up the step ladder the player allows the plume to go on their own machine
-- @return integer topStep highest step drawn, 0 when the player turned the plume off
local function getTopStep()
    local detail = getNumber(RMS_Config.LOCAL.EXHAUST_SMOKE_DETAIL, #RMS_Config.EXHAUST.PLUME_STEPS, 0)

    return math.floor(math.min(detail, #RMS_Config.EXHAUST.PLUME_STEPS))
end

---Hands the exhaust over to the plumes, silencing what the engine draws on its own
-- @param table effects exhaust effects
-- @param table? nativeParticles engine exhaust particle systems
-- @param boolean isNative true to give the engine its exhaust back
local function setNativeExhaustState(effects, nativeParticles, isNative)
    if nativeParticles ~= nil then
        for _, particleSystem in pairs(nativeParticles) do
            ParticleUtil.setEmittingState(particleSystem, isNative)
        end
    end

    -- the engine hides this node at load and never shows it, so hidden is the state to hand back
    for _, effect in pairs(effects) do
        setVisibility(effect.effectNode, false)
    end
end

---Gives the exhaust of the vehicle back to the engine, or takes it away, only on a change
-- @param table vehicle vehicle
-- @param table state exhaust smoke state
-- @param boolean isNative true to give the engine its exhaust back
local function setNativeOwnership(vehicle, state, isNative)
    if state.isNativeOwned == isNative then
        return
    end

    local motorizedSpec = vehicle.spec_motorized
    local effects = motorizedSpec ~= nil and motorizedSpec.exhaustEffects or nil
    if effects == nil then
        return
    end

    setNativeExhaustState(effects, motorizedSpec.exhaustParticleSystems, isNative)
    state.isNativeOwned = isNative
    state.isHeatVisible = isNative
end

---Stops every step of the vehicle, the particles already out finishing their life
-- @param table state exhaust smoke state
local function stopPlumes(state)
    if state.plumes == nil then
        return
    end

    for _, plume in ipairs(state.plumes) do
        for _, step in ipairs(plume.steps) do
            if step.isNative ~= true and step.isEmitting then
                step.isEmitting = false
                step.share = 0
                step.alpha = 0
                ParticleUtil.setEmittingState(step.particleSystem, false)
            end
        end
    end
end

---Deletes the plumes of the vehicle and gives the exhaust back to the engine
-- @param table vehicle vehicle
-- @param table state exhaust smoke state
local function deletePlumes(vehicle, state)
    if state.plumes == nil then
        return
    end

    for _, plume in ipairs(state.plumes) do
        for _, step in ipairs(plume.steps) do
            if step.isNative ~= true then
                ParticleUtil.deleteParticleSystem(step.particleSystem)
            end
        end
        delete(plume.emitter)
    end

    state.plumes = nil
    setNativeOwnership(vehicle, state, true)
end

---Builds the plume steps on every exhaust node of the vehicle
-- @param table vehicle vehicle
-- @param table state exhaust smoke state
-- @param table effects exhaust effects
local function createPlumes(vehicle, state, effects)
    if getTopStep() == 0 or not loadPlumeSources() then
        return
    end

    local config = RMS_Config.EXHAUST
    local sources = RMS_Exhaust.plumeSources
    local plumes = {}

    for _, effect in pairs(effects) do
        local emitter = createTransformGroup("rmsPlumeEmitter")
        link(effect.node, emitter)
        setTranslation(emitter, 0, 0, 0)
        setRotation(emitter, 0, 0, 0)

        local emitterShape = clone(sources.emitShape, true, false, true)
        link(emitter, emitterShape)
        setClipDistance(emitterShape, config.PLUME_CLIP_DISTANCE)

        local steps = {}
        for index, stepConfig in ipairs(config.PLUME_STEPS) do
            if stepConfig.isNative == true then
                steps[index] = {id = stepConfig.id, isNative = true, share = 0, alpha = 0}
            else
            local node = clone(sources.steps[index], true, false, true)
            link(emitter, node)
            setClipDistance(node, config.PLUME_CLIP_DISTANCE)

            local particleSystem = {}
            ParticleUtil.loadParticleSystemFromNode(node, particleSystem, false, true, false)
            ParticleUtil.setEmitterShape(particleSystem, emitterShape)
            ParticleUtil.setEmittingState(particleSystem, false)
            ParticleUtil.setMaxNumOfParticlesToEmitScale(particleSystem, 1.0)

            steps[index] = {
                id = stepConfig.id,
                isColourless = stepConfig.isColourless == true,
                alphaMax = stepConfig.alphaMax,
                emitMin = stepConfig.emitMin,
                emitMax = stepConfig.emitMax,
                speedMin = stepConfig.speedMin,
                speedMax = stepConfig.speedMax,
                tintWash = stepConfig.tintWash or 0,
                node = node,
                particleSystem = particleSystem,
                baseSpeed = ParticleUtil.getParticleSystemSpeed(particleSystem) or 0,
                baseSpeedRandom = ParticleUtil.getParticleSystemSpeedRandom(particleSystem) or 0,
                isEmitting = false,
                share = 0,
                alpha = 0,
                lastAlpha = -1,
                lastEmit = -1
            }
            end
        end

        table.insert(plumes, {emitter = emitter, emitterShape = emitterShape, linkNode = effect.node, steps = steps})
    end

    state.plumes = plumes
    setNativeOwnership(vehicle, state, false)
end

---Creates the plumes on the first engine run, and drops them once the player wants none
-- @param table vehicle vehicle
-- @param table state exhaust smoke state
-- @param table effects exhaust effects
local function ensurePlumes(vehicle, state, effects)
    if getTopStep() == 0 then
        deletePlumes(vehicle, state)
        return
    end

    if state.plumes == nil then
        createPlumes(vehicle, state, effects)
    end
end

-- the mechanical causes a burst can key on, one follower and one latch each
local BURST_DRIVERS = {"boost", "unburnt", "wetStacking", "preheat", "fault"}

---Resets the smoke state to a clean engine
-- @param table state exhaust smoke state
local function resetState(state)
    state.soot = 0
    state.oil = 0
    state.unburnt = 0
    state.eraFactor = 1
    state.isStageV = false
    state.red = RMS_Config.EXHAUST.HEAT_TINT[1]
    state.green = RMS_Config.EXHAUST.HEAT_TINT[2]
    state.blue = RMS_Config.EXHAUST.HEAT_TINT[3]
    state.tintRed = -1
    state.tintGreen = -1
    state.tintBlue = -1
    state.targetSoot = 0
    state.targetOil = 0
    state.targetUnburnt = 0
    state.boostDeficit = 0
    state.opticalDepth = 0
    state.opacity = 0
    state.stepAlphaMax = 0
    state.stepWash = 0
    state.flow = 0
    state.ladder = 0
    state.currentStep = 0
    state.nextStep = 0
    state.crossfade = 0
    state.alpha = 0
    state.emitScale = 0
    state.drawnShare = 0
    state.emitterCount = 0
    state.heatShare = 0
    state.isHeatVisible = false
    state.burst = 0
    state.burstCause = nil
    state.burstRefractory = 0
    state.tuneTimer = 0
    state.isActive = false

    -- the followers begin at rest, so a cause already high on the first cranking tick reads as a rise
    state.drivers = state.drivers or {}
    state.slowDrivers = state.slowDrivers or {}
    state.burstLatch = state.burstLatch or {}
    for _, key in ipairs(BURST_DRIVERS) do
        state.drivers[key] = 0
        state.slowDrivers[key] = 0
        state.burstLatch[key] = false
    end
end

---Creates the exhaust smoke state on the vehicle spec
-- @param table? vehicle vehicle
function RMS_Exhaust.initSpec(vehicle)
    local spec = vehicle ~= nil and vehicle.spec_RealisticMechanicalSystems or nil
    if spec == nil then
        return
    end

    local state = {
        profileResolved = false,
        hasTurbo = false,
        hasDEF = false,
        isMethane = false,
        isNativeOwned = true
    }
    spec.exhaustSmoke = state
    resetState(state)
end

---Drops the plumes, gives the exhaust back to the engine and clears the smoke state
-- @param table? vehicle vehicle
function RMS_Exhaust.reset(vehicle)
    if vehicle == nil then
        return
    end

    local spec = vehicle.spec_RealisticMechanicalSystems
    local state = spec ~= nil and spec.exhaustSmoke or nil
    if state == nil then
        return
    end

    deletePlumes(vehicle, state)
    resetState(state)
end

---Refreshes the emission targets and the burst drivers the renderer reads
-- @param table vehicle vehicle
function RMS_Exhaust.update(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    local state = spec.exhaustSmoke
    local motorizedSpec = vehicle.spec_motorized
    local effects = motorizedSpec ~= nil and motorizedSpec.exhaustEffects or nil

    if effects == nil or next(effects) == nil then
        return
    end

    local config = RMS_Config.EXHAUST
    if not config.ENABLED then
        RMS_Exhaust.reset(vehicle)
        return
    end

    if not getIsSmokeRendered(vehicle) then
        stopPlumes(state)
        state.isActive = false
        return
    end

    resolveEmissionProfile(vehicle, state)

    local load = getNumber(spec.dynamicMotorLoad, 0, 0, 1.5)
    local motorState = vehicle.getMotorState ~= nil and vehicle:getMotorState() or MotorState.OFF
    local wetStackingLevel = spec.fuelState ~= nil and spec.fuelState.wetStackingLevel or 0
    local preheatSeverity = getNumber(spec.preheatColdStartFaultSeverity, 0, 0, 4)
    local sootEffect = getEffectIntensity(spec, "EXHAUST_SOOT")
    local oilEffect = getEffectIntensity(spec, "EXHAUST_OIL")
    local unburntEffect = getEffectIntensity(spec, "EXHAUST_UNBURNT")

    local targets = RMS_Exhaust.calculateTargets({
        year = spec.year,
        peakPowerKw = getPeakPowerKw(vehicle),
        hasDEF = state.hasDEF,
        isMethane = state.isMethane,
        load = load,
        hasTurbo = state.hasTurbo,
        boost = getBoost(vehicle, state),
        airFilterClogging = spec.airFilterClogging,
        serviceLevel = spec.serviceLevel,
        engineTemperature = spec.rawEngineTemperature or spec.engineTemperature,
        isStarting = motorState == MotorState.STARTING,
        preheatSeverity = preheatSeverity,
        wetStackingLevel = wetStackingLevel,
        sootEffect = sootEffect,
        oilEffect = oilEffect,
        unburntEffect = unburntEffect
    })

    state.eraFactor = targets.eraFactor
    state.isStageV = targets.isStageV
    state.boostDeficit = targets.boostDeficit
    state.targetSoot = targets.soot
    state.targetOil = targets.oil
    state.targetUnburnt = targets.unburnt

    local drivers = state.drivers
    drivers.boost = targets.boostDeficit
    drivers.unburnt = targets.unburnt
    drivers.wetStacking = getNumber(wetStackingLevel, 0, 0, 1) * clamp(load, 0, 1)
    drivers.preheat = preheatSeverity / 4
    drivers.fault = math.max(sootEffect, oilEffect, unburntEffect)

    state.isActive = true
    ensurePlumes(vehicle, state, effects)
end

---Arms a burst when a mechanical cause runs ahead of its own slow follower
-- measured against a lagging follower, so a step change arms it and a slow drift never does
-- @param table state exhaust smoke state
-- @param float dt time since the last renderer tick in ms
local function updateBurstEdges(state, dt)
    local config = RMS_Config.EXHAUST
    local edges = config.BURST_EDGE
    local drivers = state.drivers
    local slow = state.slowDrivers

    local follow = math.min(dt / (config.BURST_SLOW_TAU + dt), 1)
    local latch = state.burstLatch
    local isRefractory = state.burstRefractory > 0
    local bestStrength = 0
    local bestCause = nil

    local function testEdge(key, threshold, cause)
        local driver = drivers[key]
        local rise = driver - slow[key]
        slow[key] = slow[key] + (driver - slow[key]) * follow

        -- the latch only clears once the gap collapses, so a level that stays high is a sustain
        if rise < threshold * config.BURST_LATCH_RESET then
            latch[key] = false
        end
        if latch[key] or isRefractory or rise < threshold then
            return
        end

        latch[key] = true
        local strength = clamp(rise / (threshold * 2), 0, 1)
        if strength > bestStrength then
            bestStrength = strength
            bestCause = cause
        end
    end

    testEdge("boost", edges.BOOST_DEFICIT, "boost")
    testEdge("unburnt", edges.UNBURNT, "cold")
    testEdge("wetStacking", edges.WET_STACKING, "wetStacking")
    testEdge("preheat", edges.PREHEAT, "preheat")
    testEdge("fault", edges.FAULT, "fault")

    if bestCause ~= nil then
        state.burst = math.max(state.burst, bestStrength)
        state.burstCause = bestCause
        state.burstRefractory = config.BURST_REFRACTORY
    end
end

---Places the plume on the step ladder and hands the pair of steps that may emit
-- @param float opacity opacity between 0 and 1
-- @param float burst burst strength between 0 and 1
-- @param integer topStep highest step the player allows
-- @return float ladder position on the ladder
-- @return integer current step drawn
-- @return integer next step faded into
-- @return float crossfade share handed to the next step
local function getLadderPosition(opacity, burst, topStep)
    local config = RMS_Config.EXHAUST
    local span = #config.PLUME_STEPS - 1
    local ladder = 1 + span * (opacity ^ config.LADDER_GAMMA) + burst * config.BURST_LADDER_GAIN
    ladder = clamp(ladder, 1, topStep)

    local current = math.floor(ladder)
    local crossfade = ladder - current
    if not config.LADDER_CROSSFADE then
        current = math.min(math.floor(ladder + 0.5), topStep)
        crossfade = 0
    end
    if current >= topStep then
        current = topStep
        crossfade = 0
    end

    return ladder, current, math.min(current + 1, topStep), crossfade
end

---Drives the plume particles from the smoothed channels, the gas flow and the transient bursts
-- @param table vehicle vehicle
-- @param float dt time since last call in ms
function RMS_Exhaust.applyShader(vehicle, dt)
    local spec = vehicle.spec_RealisticMechanicalSystems
    local state = spec.exhaustSmoke
    if not state.isActive or state.plumes == nil or not getIsSmokeRendered(vehicle) then
        return
    end

    local config = RMS_Config.EXHAUST
    local topStep = getTopStep()
    if topStep == 0 then
        return
    end

    state.burst = state.burst * math.exp(-dt / config.BURST_DECAY_TAU)
    if state.burst < 0.001 then
        state.burst = 0
        state.burstCause = nil
    end
    state.burstRefractory = math.max(state.burstRefractory - dt, 0)

    local sootRiseTau = state.burst > 0 and config.BURST_RISE_TAU or config.SOOT_RISE_TAU
    local riseTau = state.burst > 0 and config.BURST_RISE_TAU or nil
    state.soot = getSmoothed(state.soot, state.targetSoot, dt, sootRiseTau, config.SOOT_FALL_TAU)
    state.oil = getSmoothed(state.oil, state.targetOil, dt, riseTau)
    state.unburnt = getSmoothed(state.unburnt, state.targetUnburnt, dt, riseTau)
    -- one shader value tints every particle already in the air, so the mix has to travel slowly
    local targetRed, targetGreen, targetBlue = getTintMix(state.soot, state.oil, state.unburnt)
    state.red = getSmoothed(state.red, targetRed, dt, config.TINT_TAU, config.TINT_TAU)
    state.green = getSmoothed(state.green, targetGreen, dt, config.TINT_TAU, config.TINT_TAU)
    state.blue = getSmoothed(state.blue, targetBlue, dt, config.TINT_TAU, config.TINT_TAU)

    local opacity, opticalDepth = getOpacity(state.soot, state.oil, state.unburnt)
    state.opacity = opacity
    state.opticalDepth = opticalDepth

    state.tuneTimer = state.tuneTimer + dt
    local isTuneTick = state.tuneTimer >= config.TUNE_INTERVAL
    if isTuneTick then
        updateBurstEdges(state, state.tuneTimer)
        state.tuneTimer = 0
    end

    -- the plume follows the gas flow, which a turbo raises well above what the rpm alone gives
    local boost = getBoost(vehicle, state)
    local flowScale = getFlow(vehicle, state)
    state.flow = flowScale

    local burst = state.burst * opacity
    local ladder, currentStep, nextStep, crossfade = getLadderPosition(opacity, burst, topStep)
    state.ladder = ladder
    state.currentStep = currentStep
    state.nextStep = nextStep
    state.crossfade = crossfade

    state.heatShare = currentStep == 1 and (1 - crossfade) or 0

    local intensity = clamp(getNumber(config.INTENSITY, 1), 1, 3)
    local opacityAlpha = opacity ^ config.ALPHA_GAMMA
    local emitGain = 1 + burst * config.BURST_EMIT_GAIN
    local emitterCount = 0

    -- two systems overlap during a fade, and the draw order between them flips with the camera,
    -- so they have to look the same and differ only in how many particles each one sends out
    local stepsConfig = config.PLUME_STEPS
    local fadeLow = stepsConfig[math.max(currentStep, 2)]
    local fadeHigh = stepsConfig[math.max(nextStep, 2)]
    local sharedAlphaMax = lerp(fadeLow.alphaMax, fadeHigh.alphaMax, crossfade)
    local sharedWash = lerp(fadeLow.tintWash or 0, fadeHigh.tintWash or 0, crossfade)
    state.stepAlphaMax = sharedAlphaMax
    state.stepWash = sharedWash

    state.alpha = 0
    state.emitScale = 0
    state.drawnShare = 0

    -- the steps that share a pipe have to carry the same tint on the same tick, or the cloud
    -- shows two populations of different colours
    local hasNewTint = math.abs(state.red - state.tintRed) >= config.TUNE_EPSILON
        or math.abs(state.green - state.tintGreen) >= config.TUNE_EPSILON
        or math.abs(state.blue - state.tintBlue) >= config.TUNE_EPSILON
    if isTuneTick and hasNewTint then
        state.tintRed = state.red
        state.tintGreen = state.green
        state.tintBlue = state.blue
    end

    for plumeIndex, plume in ipairs(state.plumes) do
        local isPlumeVisible = getEffectiveVisibility(plume.linkNode)
        for index, step in ipairs(plume.steps) do
            local share = 0
            if index == currentStep then
                share = 1 - crossfade
            elseif index == nextStep and crossfade > 0 then
                share = crossfade
            end

            if step.isNative then
                step.share = isPlumeVisible and share or 0
            else
                local alpha = math.min(sharedAlphaMax * opacityAlpha * intensity, 1)

                local shareThreshold = step.isEmitting and config.STEP_SHARE_OFF or config.STEP_SHARE_ON
                local shouldEmit = isPlumeVisible and share >= shareThreshold and alpha >= config.PLUME_ALPHA_MIN

                step.share = share
                step.alpha = shouldEmit and alpha or 0
                local particleSystem = step.particleSystem
                local hasStarted = false

                if step.isEmitting ~= shouldEmit then
                    step.isEmitting = shouldEmit
                    ParticleUtil.setEmittingState(particleSystem, shouldEmit)
                    if shouldEmit then
                        hasStarted = true
                        ParticleUtil.resetNumOfEmittedParticles(particleSystem)
                    end
                end

                if shouldEmit then
                    if plumeIndex == 1 then
                        emitterCount = emitterCount + 1
                    end

                    local emitScale = lerp(step.emitMin, step.emitMax, flowScale) * share * emitGain
                    local hasMoved = math.abs(alpha - step.lastAlpha) >= config.TUNE_EPSILON
                        or math.abs(emitScale - step.lastEmit) >= config.TUNE_EPSILON

                    if hasStarted or (isTuneTick and (hasMoved or hasNewTint)) then
                        step.lastAlpha = alpha
                        step.lastEmit = emitScale

                        local grey = (state.red + state.green + state.blue) / 3
                        setShaderParameterRecursive(particleSystem.shape, "colorAlpha",
                            lerp(state.red, grey, sharedWash),
                            lerp(state.green, grey, sharedWash),
                            lerp(state.blue, grey, sharedWash), alpha, false)
                        ParticleUtil.setEmitCountScale(particleSystem, emitScale)

                        local speedScale = lerp(step.speedMin, step.speedMax, flowScale)
                        ParticleUtil.setParticleSystemSpeed(particleSystem, step.baseSpeed * speedScale)
                        ParticleUtil.setParticleSystemSpeedRandom(particleSystem, step.baseSpeedRandom * speedScale)
                    end

                    if share > state.drawnShare then
                        state.drawnShare = share
                        state.alpha = alpha
                        state.emitScale = emitScale
                    end
                end
            end
        end
    end

    state.emitterCount = emitterCount

    if RMS_Utils.getIsDebugDataWanted(vehicle) then
        local dbg = spec.debugData.exhaust
        dbg.hasTurbo = state.hasTurbo == true
        dbg.boost = boost
        dbg.boostDeficit = state.boostDeficit
        dbg.flow = flowScale
        dbg.opticalDepth = opticalDepth
        dbg.opacity = opacity
        dbg.ladder = ladder
        dbg.currentStep = currentStep
        dbg.nextStep = nextStep
        dbg.crossfade = crossfade
        dbg.alpha = state.alpha
        dbg.emitScale = state.emitScale
        dbg.burst = state.burst
        dbg.burstCause = state.burstCause
        dbg.emitterCount = state.emitterCount
        dbg.heatShare = state.heatShare
        dbg.steps = state.plumes[1] ~= nil and state.plumes[1].steps or nil
    end
end

---Draws the heat step with the exhaust effect of the vehicle, a refraction rather than a sprite
-- @param table vehicle vehicle
function RMS_Exhaust.applyNativeHeat(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    local state = spec.exhaustSmoke
    if not state.isActive or state.isNativeOwned then
        return
    end

    local motorizedSpec = vehicle.spec_motorized
    local effects = motorizedSpec ~= nil and motorizedSpec.exhaustEffects or nil
    if effects == nil then
        return
    end

    local config = RMS_Config.EXHAUST
    local heat = config.PLUME_STEPS[1]

    -- the shader builds its refraction from the cloud texture and the fresnel alone, and floors the
    -- blend at a quarter whatever alpha it is handed, so size is the only lever on how much shows
    local coldTemperature = RMS_Config.CORE.ENGINE_FACTOR_DATA.COLD_MOTOR_TEMP_THRESHOLD
    local operatingTemperature = RMS_Config.THERMAL.PID_TARGET_TEMP
    local temperature = getNumber(spec.rawEngineTemperature or spec.engineTemperature, operatingTemperature, -80, 160)
    local warmth = getRamp(temperature, coldTemperature, operatingTemperature)
    local flowScale = getFlow(vehicle, state)
    local alpha = lerp(heat.alphaMin, heat.alphaMax, flowScale)
    local scale = lerp(heat.scaleMin, heat.scaleMax, flowScale) * lerp(config.HEAT_COLD_FACTOR, 1, warmth)
    local tint = config.HEAT_TINT

    for _, effect in pairs(effects) do
        setShaderParameter(effect.effectNode, "exhaustColor", tint[1], tint[2], tint[3], alpha, false)
        setShaderParameter(effect.effectNode, "param", effect.xRot, effect.zRot, 0, scale, false)
    end

    if not state.isHeatVisible then
        state.isHeatVisible = true
        for _, effect in pairs(effects) do
            setVisibility(effect.effectNode, true)
        end
    end
end
