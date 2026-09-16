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

---Returns the length of a three-dimensional vector
-- @param float x x component
-- @param float y y component
-- @param float z z component
-- @return float length vector length
local function getVectorLength(x, y, z)
    return math.sqrt(x * x + y * y + z * z)
end

---Normalizes a three-dimensional vector, returning the fallback direction for a null vector
-- @param float x x component
-- @param float y y component
-- @param float z z component
-- @param float? fallbackX fallback x component
-- @param float? fallbackY fallback y component
-- @param float? fallbackZ fallback z component
-- @return float x normalized x component
-- @return float y normalized y component
-- @return float z normalized z component
local function normalizeVector(x, y, z, fallbackX, fallbackY, fallbackZ)
    local length = getVectorLength(x, y, z)
    if length <= 0.000001 then
        return fallbackX or 0, fallbackY or 1, fallbackZ or 0
    end

    return x / length, y / length, z / length
end

---Returns the dot product of two three-dimensional vectors
local function dotProduct(ax, ay, az, bx, by, bz)
    return ax * bx + ay * by + az * bz
end

---Returns the cross product of two three-dimensional vectors
local function crossProduct(ax, ay, az, bx, by, bz)
    return ay * bz - az * by, az * bx - ax * bz, ax * by - ay * bx
end

---Builds a stable orthonormal basis around a direction
-- @return float sideX
-- @return float sideY
-- @return float sideZ
-- @return float forwardX
-- @return float forwardY
-- @return float forwardZ
local function getDirectionBasis(directionX, directionY, directionZ)
    local referenceX, referenceY, referenceZ = 0, 1, 0
    if math.abs(directionY) > 0.9 then
        referenceX, referenceY, referenceZ = 1, 0, 0
    end

    local sideX, sideY, sideZ = crossProduct(directionX, directionY, directionZ,
        referenceX, referenceY, referenceZ)
    sideX, sideY, sideZ = normalizeVector(sideX, sideY, sideZ, 1, 0, 0)
    local forwardX, forwardY, forwardZ = crossProduct(sideX, sideY, sideZ,
        directionX, directionY, directionZ)
    forwardX, forwardY, forwardZ = normalizeVector(forwardX, forwardY, forwardZ, 0, 0, 1)

    return sideX, sideY, sideZ, forwardX, forwardY, forwardZ
end

---Returns a deterministic value between zero and one for one puff serial
local function getDeterministicValue(serial, salt)
    local value = math.sin(serial * 12.9898 + salt * 78.233) * 43758.5453

    return value - math.floor(value)
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

-- GIANTS only renders the sprite, RMS owns every puff
local MANAGED_RENDERER_FUNCTIONS = {
    "getGeometry",
    "getMaxNumOfParticles",
    "getNumOfParticlesToEmitPerMs",
    "getParticleSystemLifespan",
    "getParticleSystemSpeed",
    "getParticleSystemSpeedRandom",
    "getParticleSystemNormalSpeed",
    "getParticleSystemTangentSpeed",
    "getParticleSystemDamping",
    "getParticleSystemSpriteScaleX",
    "getParticleSystemSpriteScaleXGain",
    "getParticleSystemSpriteScaleY",
    "getParticleSystemSpriteScaleYGain",
    "getEmitterShapeVelocityScale",
    "addParticleSystemSimulationTime",
    "setMaxNumOfParticles",
    "setNumOfParticlesToEmitPerMs",
    "setParticleSystemSpeed",
    "setParticleSystemSpeedRandom",
    "setParticleSystemNormalSpeed",
    "setParticleSystemTangentSpeed",
    "setEmitterShapeVelocityScale",
    "raycastClosest"
}

---Tells whether the engine exposes every primitive used by the RMS puff renderer
local function getHasManagedRendererApi()
    for _, functionName in ipairs(MANAGED_RENDERER_FUNCTIONS) do
        if type(_G[functionName]) ~= "function" then
            return false
        end
    end

    return true
end

---Reads the motion and lifetime authored in one RMS plume asset
-- @param entityId node particle-system shape node
-- @return table? profile immutable puff profile
local function readPuffProfile(node)
    local geometry = getGeometry(node)
    if geometry == nil or geometry == 0 then
        return nil
    end

    local profile = {
        geometry = geometry,
        maxCount = getMaxNumOfParticles(geometry),
        rate = getNumOfParticlesToEmitPerMs(geometry),
        lifespan = getParticleSystemLifespan(geometry),
        speed = getParticleSystemSpeed(geometry),
        speedRandom = getParticleSystemSpeedRandom(geometry),
        normalSpeed = getParticleSystemNormalSpeed(geometry),
        tangentSpeed = getParticleSystemTangentSpeed(geometry),
        damping = getParticleSystemDamping(geometry),
        spriteScaleX = getParticleSystemSpriteScaleX(geometry),
        spriteScaleXGain = getParticleSystemSpriteScaleXGain(geometry),
        spriteScaleY = getParticleSystemSpriteScaleY(geometry),
        spriteScaleYGain = getParticleSystemSpriteScaleYGain(geometry),
        emitterVelocityScale = getEmitterShapeVelocityScale(geometry)
    }

    for key, value in pairs(profile) do
        if key ~= "geometry" and (type(value) ~= "number" or value ~= value) then
            return nil
        end
    end
    if profile.maxCount < 1 or profile.rate <= 0 or profile.lifespan <= 0 then
        return nil
    end

    return profile
end

---Returns the bounding-sphere radius of one camera-facing puff
-- @param table puff managed puff
-- @return float radius radius in metres
function RMS_Exhaust.getPuffRadius(puff)
    local profile = puff.profile
    local age = clamp(getNumber(puff.age, 0, 0), 0, profile.lifespan)
    local sizeX = math.max(profile.spriteScaleX + profile.spriteScaleXGain * age, 0)
    local sizeY = math.max(profile.spriteScaleY + profile.spriteScaleYGain * age, 0)

    return math.sqrt(sizeX * sizeX + sizeY * sizeY) * 0.5
end

---Returns the optical alpha after a contacted puff has spread along a surface
-- @param table puff managed puff
-- @return float alpha rendered alpha
function RMS_Exhaust.getPuffRenderAlpha(puff)
    local alpha = clamp(getNumber(puff.baseAlpha, puff.alpha or 0, 0, 1), 0, 1)
    local contactRadius = getNumber(puff.contactRadius, 0, 0)
    local surfaceTravel = getNumber(puff.surfaceTravel, 0, 0)
    if contactRadius > 0 and surfaceTravel > 0 then
        alpha = alpha * ((contactRadius / (contactRadius + surfaceTravel)) ^ 0.57)
    end

    return alpha
end

---Projects an impacting puff onto a surface while retaining its tangential momentum
-- @param table puff managed puff
-- @param table hit raycast hit with point, normal and incoming direction
-- @param float radius current puff radius
function RMS_Exhaust.resolvePuffImpact(puff, hit, radius)
    local normalX, normalY, normalZ = normalizeVector(hit.nx, hit.ny, hit.nz, 0, -1, 0)
    if dotProduct(normalX, normalY, normalZ, hit.dx or 0, hit.dy or 0, hit.dz or 0) > 0 then
        normalX, normalY, normalZ = -normalX, -normalY, -normalZ
    end

    local margin = math.max(radius * 0.02, 0.005)
    puff.x = hit.x + normalX * (radius + margin)
    puff.y = hit.y + normalY * (radius + margin)
    puff.z = hit.z + normalZ * (radius + margin)

    local normalSpeed = dotProduct(puff.vx, puff.vy, puff.vz, normalX, normalY, normalZ)
    if normalSpeed < 0 then
        local blockedSpeed = -normalSpeed
        puff.vx = puff.vx - normalSpeed * normalX
        puff.vy = puff.vy - normalSpeed * normalY
        puff.vz = puff.vz - normalSpeed * normalZ

        local spreadX = puff.spreadX - dotProduct(puff.spreadX, puff.spreadY, puff.spreadZ,
            normalX, normalY, normalZ) * normalX
        local spreadY = puff.spreadY - dotProduct(puff.spreadX, puff.spreadY, puff.spreadZ,
            normalX, normalY, normalZ) * normalY
        local spreadZ = puff.spreadZ - dotProduct(puff.spreadX, puff.spreadY, puff.spreadZ,
            normalX, normalY, normalZ) * normalZ
        spreadX, spreadY, spreadZ = normalizeVector(spreadX, spreadY, spreadZ, 1, 0, 0)
        local surfaceSpread = blockedSpeed * clamp(puff.profile.tangentSpeed, 0, 1)
        puff.vx = puff.vx + spreadX * surfaceSpread
        puff.vy = puff.vy + spreadY * surfaceSpread
        puff.vz = puff.vz + spreadZ * surfaceSpread
    end

    if puff.contactRadius == nil then
        puff.contactRadius = math.max(radius, 0.001)
        puff.surfaceTravel = 0
    end
    puff.contact = {
        x = hit.x,
        y = hit.y,
        z = hit.z,
        nx = normalX,
        ny = normalY,
        nz = normalZ,
        objectId = hit.objectId
    }
    puff.collisionCount = (puff.collisionCount or 0) + 1
end

---Advances one RMS puff through drag, wind, buoyancy, turbulence and solid contacts
-- @param table puff managed puff
-- @param float dt elapsed time in ms
-- @param table? environment trace and support callbacks plus wind velocity
function RMS_Exhaust.advancePuff(puff, dt, environment)
    environment = environment or {}
    local remainingMs = math.max(getNumber(dt, 0, 0), 0)
    local profile = puff.profile
    local lifespanSeconds = math.max(profile.lifespan / 1000, 0.001)

    while remainingMs > 0 and puff.age < profile.lifespan do
        local stepMs = math.min(remainingMs, 50)
        local stepSeconds = stepMs / 1000
        remainingMs = remainingMs - stepMs
        puff.age = math.min(puff.age + stepMs, profile.lifespan)

        if puff.contact ~= nil and environment.hasContact ~= nil
                and not environment.hasContact(puff, puff.contact, RMS_Exhaust.getPuffRadius(puff)) then
            puff.contact = nil
        end

        local windX = getNumber(environment.windX, 0)
        local windY = getNumber(environment.windY, 0)
        local windZ = getNumber(environment.windZ, 0)
        local drag = math.exp(-math.max(profile.damping, 0) * stepSeconds)
        puff.vx = windX + (puff.vx - windX) * drag
        puff.vy = windY + (puff.vy - windY) * drag
        puff.vz = windZ + (puff.vz - windZ) * drag

        local lifeShare = clamp(puff.age / profile.lifespan, 0, 1)
        local buoyancy = puff.initialSpeed / lifespanSeconds * (1 - lifeShare)
        puff.vy = puff.vy + buoyancy * stepSeconds

        local turbulence = profile.speedRandom * 1000 / lifespanSeconds
        local phase = puff.phase + lifeShare * math.pi * 2
        puff.vx = puff.vx + puff.noiseX * math.sin(phase) * turbulence * stepSeconds
        puff.vy = puff.vy + puff.noiseY * math.sin(phase * 0.73) * turbulence * stepSeconds
        puff.vz = puff.vz + puff.noiseZ * math.cos(phase) * turbulence * stepSeconds

        local previousX, previousY, previousZ = puff.x, puff.y, puff.z
        local nextX = puff.x + puff.vx * stepSeconds
        local nextY = puff.y + puff.vy * stepSeconds
        local nextZ = puff.z + puff.vz * stepSeconds
        local radius = RMS_Exhaust.getPuffRadius(puff)
        local hit = environment.trace ~= nil
            and environment.trace(puff, puff.x, puff.y, puff.z, nextX, nextY, nextZ, radius) or nil

        if hit ~= nil then
            RMS_Exhaust.resolvePuffImpact(puff, hit, radius)
            local remainingShare = clamp(1 - getNumber(hit.fraction, 1, 0, 1), 0, 1)
            nextX = puff.x + puff.vx * stepSeconds * remainingShare
            nextY = puff.y + puff.vy * stepSeconds * remainingShare
            nextZ = puff.z + puff.vz * stepSeconds * remainingShare
        end

        if puff.contact ~= nil then
            local contact = puff.contact
            local distance = dotProduct(nextX - contact.x, nextY - contact.y, nextZ - contact.z,
                contact.nx, contact.ny, contact.nz)
            local clearance = radius + math.max(radius * 0.02, 0.005)
            if distance < clearance then
                local correction = clearance - distance
                nextX = nextX + contact.nx * correction
                nextY = nextY + contact.ny * correction
                nextZ = nextZ + contact.nz * correction

                local inwardSpeed = dotProduct(puff.vx, puff.vy, puff.vz,
                    contact.nx, contact.ny, contact.nz)
                if inwardSpeed < 0 then
                    puff.vx = puff.vx - inwardSpeed * contact.nx
                    puff.vy = puff.vy - inwardSpeed * contact.ny
                    puff.vz = puff.vz - inwardSpeed * contact.nz
                end
            end

            local moveX = nextX - previousX
            local moveY = nextY - previousY
            local moveZ = nextZ - previousZ
            local normalMove = dotProduct(moveX, moveY, moveZ,
                contact.nx, contact.ny, contact.nz)
            local tangentX = moveX - normalMove * contact.nx
            local tangentY = moveY - normalMove * contact.ny
            local tangentZ = moveZ - normalMove * contact.nz
            puff.surfaceTravel = (puff.surfaceTravel or 0)
                + math.sqrt(tangentX * tangentX + tangentY * tangentY + tangentZ * tangentZ)
        end

        puff.x, puff.y, puff.z = nextX, nextY, nextZ
    end
end

---Loads the emitter surface and the step sources once for the session
-- @return boolean loaded true once every source is available
local function loadPlumeSources()
    if RMS_Exhaust.plumeSources ~= nil then
        return RMS_Exhaust.plumeSources.isValid
    end

    local config = RMS_Config.EXHAUST
    local sources = {
        isValid = false,
        sprites = config.PLUME_SPRITES,
        hasManagedRendererApi = getHasManagedRendererApi(),
        steps = {},
        profiles = {}
    }
    RMS_Exhaust.plumeSources = sources
    if not sources.hasManagedRendererApi then
        return false
    end

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
            local profile = readPuffProfile(node)
            if profile == nil then
                return false
            end
            sources.steps[index] = node
            sources.profiles[index] = profile
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

---Returns the collision mask of solid world geometry a smoke puff cannot cross
local function getPuffCollisionMask()
    if RMS_Exhaust.puffCollisionMask ~= nil then
        return RMS_Exhaust.puffCollisionMask
    end

    local mask = 0
    local names = {
        "STATIC_OBJECT", "BUILDING", "TERRAIN", "TERRAIN_DELTA",
        "ROAD", "VEHICLE", "DYNAMIC_OBJECT", "TREE"
    }
    for _, name in ipairs(names) do
        local flag = CollisionFlag ~= nil and CollisionFlag[name] or nil
        if type(flag) == "number" then
            if bit32 ~= nil and bit32.bor ~= nil then
                mask = bit32.bor(mask, flag)
            else
                mask = mask + flag
            end
        end
    end

    RMS_Exhaust.puffCollisionMask = mask

    return mask
end

---Receives the closest solid hit of the synchronous puff raycast
function RMS_Exhaust:onPuffRaycast(transformId, x, y, z, distance, nx, ny, nz)
    self.puffRaycastHit = {
        objectId = transformId,
        x = x,
        y = y,
        z = z,
        distance = distance,
        nx = nx,
        ny = ny,
        nz = nz
    }
end

---Tells whether an early puff raycast hit belongs to its own vehicle
local function getIsOwnVehicleHit(vehicle, object)
    if object == nil then
        return false
    end
    if object == vehicle then
        return true
    end

    return object.rootVehicle ~= nil and vehicle.rootVehicle ~= nil
        and object.rootVehicle == vehicle.rootVehicle
end

---Casts through ignored trigger and own-vehicle hits until the first physical surface
local function castPuffRay(vehicle, puff, originX, originY, originZ, directionX, directionY, directionZ, distance)
    if distance <= 0.000001 then
        return nil
    end

    local travelled = 0
    local startX, startY, startZ = originX, originY, originZ
    for _ = 1, 12 do
        local remaining = distance - travelled
        if remaining <= 0.000001 then
            return nil
        end

        RMS_Exhaust.puffRaycastHit = nil
        raycastClosest(startX, startY, startZ, directionX, directionY, directionZ, remaining,
            "onPuffRaycast", RMS_Exhaust, getPuffCollisionMask())
        local hit = RMS_Exhaust.puffRaycastHit
        if hit == nil then
            return nil
        end

        local object = g_currentMission ~= nil and g_currentMission.getNodeObject ~= nil
            and g_currentMission:getNodeObject(hit.objectId) or nil
        local isTrigger = type(getHasTrigger) == "function" and getHasTrigger(hit.objectId)
        local ignoreOwnVehicle = puff.age <= puff.selfIgnoreUntil and getIsOwnVehicleHit(vehicle, object)
        if not isTrigger and not ignoreOwnVehicle then
            hit.distance = travelled + hit.distance
            return hit
        end

        local advance = hit.distance + 0.002
        travelled = travelled + advance
        startX = originX + directionX * travelled
        startY = originY + directionY * travelled
        startZ = originZ + directionZ * travelled
    end

    return nil
end

---Sweeps the bounding sphere of one puff over its next movement segment
local function tracePuff(vehicle, puff, fromX, fromY, fromZ, toX, toY, toZ, radius)
    local deltaX, deltaY, deltaZ = toX - fromX, toY - fromY, toZ - fromZ
    local movementLength = getVectorLength(deltaX, deltaY, deltaZ)
    if movementLength <= 0.000001 then
        return nil
    end

    local directionX, directionY, directionZ = deltaX / movementLength, deltaY / movementLength, deltaZ / movementLength
    local hit = castPuffRay(vehicle, puff, fromX, fromY, fromZ,
        directionX, directionY, directionZ, movementLength + radius)
    if hit == nil then
        return nil
    end

    hit.dx, hit.dy, hit.dz = directionX, directionY, directionZ
    hit.fraction = clamp((hit.distance - radius) / movementLength, 0, 1)

    return hit
end

---Checks that the contacted surface still exists beneath a sliding puff
local function hasPuffContact(vehicle, puff, contact, radius)
    local margin = math.max(radius * 0.02, 0.005)
    local originX = puff.x + contact.nx * margin
    local originY = puff.y + contact.ny * margin
    local originZ = puff.z + contact.nz * margin
    local distance = radius + margin * 4
    local hit = castPuffRay(vehicle, puff, originX, originY, originZ,
        -contact.nx, -contact.ny, -contact.nz, distance)
    if hit == nil then
        return false
    end

    local normalX, normalY, normalZ = normalizeVector(hit.nx, hit.ny, hit.nz,
        contact.nx, contact.ny, contact.nz)
    if dotProduct(normalX, normalY, normalZ, contact.nx, contact.ny, contact.nz) < 0.5 then
        return false
    end

    contact.x, contact.y, contact.z = hit.x, hit.y, hit.z
    contact.nx, contact.ny, contact.nz = normalX, normalY, normalZ
    contact.objectId = hit.objectId

    return true
end

---Returns the current weather wind as a world velocity
local function getWindVelocity()
    local weather = g_currentMission ~= nil and g_currentMission.environment ~= nil
        and g_currentMission.environment.weather or nil
    local updater = weather ~= nil and weather.windUpdater or nil
    if updater == nil then
        return 0, 0, 0
    end

    local velocity = getNumber(updater.currentVelocity, 0, 0)

    return getNumber(updater.currentDirX, 0) * velocity, 0,
        getNumber(updater.currentDirZ, 0) * velocity
end

---Creates one reusable one-sprite renderer for an RMS-managed puff
local function createPuffSlot(step)
    local config = RMS_Config.EXHAUST
    local sources = RMS_Exhaust.plumeSources
    local root = createTransformGroup("rmsManagedPuff")
    link(getRootNode(), root)

    local emitterShape = clone(sources.emitShape, true, false, true)
    link(root, emitterShape)
    setScale(emitterShape, 0.001, 0.001, 0.001)
    setClipDistance(emitterShape, config.PLUME_CLIP_DISTANCE)

    local node = clone(step.sourceNode, true, false, true)
    link(root, node)
    setClipDistance(node, config.PLUME_CLIP_DISTANCE)

    local renderer = {}
    ParticleUtil.loadParticleSystemFromNode(node, renderer, false, false, true)
    ParticleUtil.setEmitterShape(renderer, emitterShape)
    ParticleUtil.setEmittingState(renderer, false)

    local geometry = getGeometry(renderer.shape)
    if geometry == nil or geometry == 0 then
        ParticleUtil.deleteParticleSystem(renderer)
        delete(root)
        return nil
    end

    setMaxNumOfParticles(geometry, 1)
    setNumOfParticlesToEmitPerMs(geometry, 1)
    setParticleSystemSpeed(geometry, 0)
    setParticleSystemSpeedRandom(geometry, 0)
    setParticleSystemNormalSpeed(geometry, 0)
    setParticleSystemTangentSpeed(geometry, 0)
    setEmitterShapeVelocityScale(geometry, 0)
    setVisibility(root, false)

    return {
        root = root,
        node = node,
        emitterShape = emitterShape,
        renderer = renderer,
        isInUse = false,
        elapsed = 0
    }
end

---Deletes every renderer allocated by one plume step
local function deletePuffPool(step)
    for _, slot in ipairs(step.pool) do
        ParticleUtil.deleteParticleSystem(slot.renderer)
        delete(slot.root)
    end
    step.pool = {}
    step.particleSystem.isDeleted = true
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
                step.particleSystem.isEmitting = false
                step.particleSystem.emitScale = 0
                step.emissionAccumulator = 0
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
                deletePuffPool(step)
            end
        end
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
        local steps = {}
        for index, stepConfig in ipairs(config.PLUME_STEPS) do
            if stepConfig.isNative == true then
                steps[index] = {id = stepConfig.id, isNative = true, share = 0, alpha = 0}
            else
                local profile = sources.profiles[index]
                steps[index] = {
                    id = stepConfig.id,
                    isColourless = stepConfig.isColourless == true,
                    alphaMax = stepConfig.alphaMax,
                    emitMin = stepConfig.emitMin,
                    emitMax = stepConfig.emitMax,
                    speedMin = stepConfig.speedMin,
                    speedMax = stepConfig.speedMax,
                    tintWash = stepConfig.tintWash or 0,
                    sourceNode = sources.steps[index],
                    profile = profile,
                    particleSystem = {
                        shape = sources.steps[index],
                        isEmitting = false,
                        emitScale = 0,
                        speed = profile.speed,
                        isDeleted = false
                    },
                    baseSpeed = profile.speed,
                    baseSpeedRandom = profile.speedRandom,
                    pool = {},
                    emissionAccumulator = 0,
                    isEmitting = false,
                    share = 0,
                    alpha = 0,
                    lastAlpha = -1,
                    lastEmit = -1,
                    activePuffs = 0,
                    collisionCount = 0
                }
            end
        end

        table.insert(plumes, {
            linkNode = effect.node,
            effect = effect,
            steps = steps,
            lastPipeX = nil,
            lastPipeY = nil,
            lastPipeZ = nil,
            pipeVelocityX = 0,
            pipeVelocityY = 0,
            pipeVelocityZ = 0
        })
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

---Updates the world velocity of one exhaust outlet
local function updatePipeVelocity(plume, dt)
    local x, y, z = getWorldTranslation(plume.linkNode)
    if plume.lastPipeX ~= nil and dt > 0 then
        local seconds = dt / 1000
        plume.pipeVelocityX = (x - plume.lastPipeX) / seconds
        plume.pipeVelocityY = (y - plume.lastPipeY) / seconds
        plume.pipeVelocityZ = (z - plume.lastPipeZ) / seconds
    else
        plume.pipeVelocityX = 0
        plume.pipeVelocityY = 0
        plume.pipeVelocityZ = 0
    end
    plume.lastPipeX, plume.lastPipeY, plume.lastPipeZ = x, y, z

    return x, y, z
end

---Returns an idle puff slot, allocating one lazily up to the source asset's particle cap
local function getPuffSlot(step)
    for _, slot in ipairs(step.pool) do
        if not slot.isInUse then
            return slot
        end
    end

    if #step.pool >= math.floor(step.profile.maxCount) then
        return nil
    end

    local slot = createPuffSlot(step)
    if slot ~= nil then
        table.insert(step.pool, slot)
    end

    return slot
end

---Emits one independently simulated RMS puff from an exhaust outlet
local function spawnPuff(state, plume, step, speedScale, red, green, blue, alpha)
    local slot = getPuffSlot(step)
    if slot == nil then
        return false
    end

    state.nextPuffSerial = state.nextPuffSerial + 1
    local serial = state.nextPuffSerial
    local directionX, directionY, directionZ = localDirectionToWorld(plume.linkNode, 0, 1, 0)
    directionX, directionY, directionZ = normalizeVector(directionX, directionY, directionZ, 0, 1, 0)
    local sideX, sideY, sideZ, forwardX, forwardY, forwardZ = getDirectionBasis(
        directionX, directionY, directionZ)

    local angle = getDeterministicValue(serial, 1) * math.pi * 2
    local spreadX = sideX * math.cos(angle) + forwardX * math.sin(angle)
    local spreadY = sideY * math.cos(angle) + forwardY * math.sin(angle)
    local spreadZ = sideZ * math.cos(angle) + forwardZ * math.sin(angle)
    local profile = step.profile
    local speedVariation = (getDeterministicValue(serial, 2) * 2 - 1)
        * profile.speedRandom * 1000 * speedScale
    local initialSpeed = math.max(profile.speed * 1000 * speedScale + speedVariation, 0)
        * math.max(profile.normalSpeed, 0)
    local lateralSpeed = (profile.speed * math.max(profile.tangentSpeed, 0)
        + profile.speedRandom * (getDeterministicValue(serial, 3) * 2 - 1)) * 1000 * speedScale

    local puff = {
        serial = serial,
        profile = profile,
        age = 1,
        initialSpeed = initialSpeed,
        vx = directionX * initialSpeed + spreadX * lateralSpeed
            + plume.pipeVelocityX * profile.emitterVelocityScale,
        vy = directionY * initialSpeed + spreadY * lateralSpeed
            + plume.pipeVelocityY * profile.emitterVelocityScale,
        vz = directionZ * initialSpeed + spreadZ * lateralSpeed
            + plume.pipeVelocityZ * profile.emitterVelocityScale,
        spreadX = spreadX,
        spreadY = spreadY,
        spreadZ = spreadZ,
        noiseX = getDeterministicValue(serial, 4) * 2 - 1,
        noiseY = getDeterministicValue(serial, 5) * 2 - 1,
        noiseZ = getDeterministicValue(serial, 6) * 2 - 1,
        phase = getDeterministicValue(serial, 7) * math.pi * 2,
        collisionCount = 0,
        red = red,
        green = green,
        blue = blue,
        alpha = alpha,
        baseAlpha = alpha,
        lastRenderedAlpha = alpha,
        surfaceTravel = 0
    }
    puff.noiseX, puff.noiseY, puff.noiseZ = normalizeVector(
        puff.noiseX, puff.noiseY, puff.noiseZ, spreadX, spreadY, spreadZ)

    local radius = RMS_Exhaust.getPuffRadius(puff)
    local originX, originY, originZ = getWorldTranslation(plume.linkNode)
    local outletJitter = radius * 0.25 * (getDeterministicValue(serial, 8) * 2 - 1)
    local clearance = radius + math.max(radius * 0.02, 0.005)
    puff.x = originX + directionX * clearance + spreadX * outletJitter
    puff.y = originY + directionY * clearance + spreadY * outletJitter
    puff.z = originZ + directionZ * clearance + spreadZ * outletJitter
    puff.selfIgnoreUntil = clamp(clearance / math.max(initialSpeed, 0.1) * 2000, 25, 250)

    slot.puff = puff
    slot.elapsed = 1
    slot.isInUse = true
    setWorldTranslation(slot.root, puff.x, puff.y, puff.z)
    setVisibility(slot.root, true)
    setShaderParameterRecursive(slot.renderer.shape, "colorAlpha", red, green, blue, alpha, false)
    ParticleUtil.setEmittingState(slot.renderer, false)
    ParticleUtil.resetNumOfEmittedParticles(slot.renderer)
    ParticleUtil.setEmittingState(slot.renderer, true)
    addParticleSystemSimulationTime(getGeometry(slot.renderer.shape), 1)
    ParticleUtil.setEmittingState(slot.renderer, false)

    return true
end

---Advances all already emitted puffs, including after their engine has stopped
local function updatePuffPools(vehicle, state, dt)
    if state.plumes == nil then
        state.activePuffs = 0
        return
    end

    local windX, windY, windZ = getWindVelocity()
    local environment = {
        windX = windX,
        windY = windY,
        windZ = windZ,
        trace = function(puff, fromX, fromY, fromZ, toX, toY, toZ, radius)
            return tracePuff(vehicle, puff, fromX, fromY, fromZ, toX, toY, toZ, radius)
        end,
        hasContact = function(puff, contact, radius)
            return hasPuffContact(vehicle, puff, contact, radius)
        end
    }

    local activePuffs = 0
    for _, plume in ipairs(state.plumes) do
        updatePipeVelocity(plume, dt)
        for _, step in ipairs(plume.steps) do
            if step.isNative ~= true then
                local stepActive = 0
                for _, slot in ipairs(step.pool) do
                    if slot.isInUse then
                        slot.elapsed = slot.elapsed + dt
                        local puff = slot.puff
                        if puff.age < puff.profile.lifespan then
                            local previousCollisions = puff.collisionCount
                            RMS_Exhaust.advancePuff(puff, math.min(dt,
                                puff.profile.lifespan - puff.age), environment)
                            local newCollisions = puff.collisionCount - previousCollisions
                            step.collisionCount = step.collisionCount + newCollisions
                            state.collisionCount = state.collisionCount + newCollisions
                            setWorldTranslation(slot.root, puff.x, puff.y, puff.z)
                            local renderedAlpha = RMS_Exhaust.getPuffRenderAlpha(puff)
                            if math.abs(renderedAlpha - puff.lastRenderedAlpha) >= 0.001 then
                                setShaderParameterRecursive(slot.renderer.shape, "colorAlpha",
                                    puff.red, puff.green, puff.blue, renderedAlpha, false)
                                puff.lastRenderedAlpha = renderedAlpha
                            end
                        end

                        if slot.elapsed < puff.profile.lifespan then
                            stepActive = stepActive + 1
                            activePuffs = activePuffs + 1
                        else
                            setVisibility(slot.root, false)
                        end

                        if slot.elapsed >= puff.profile.lifespan + 100 then
                            slot.isInUse = false
                            slot.puff = nil
                        end
                    end
                end
                step.activePuffs = stepActive
            end
        end
    end
    state.activePuffs = activePuffs
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
    state.activePuffs = 0
    state.collisionCount = 0
    state.nextPuffSerial = 0
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
    dt = getNumber(dt, 0, 0)
    updatePuffPools(vehicle, state, dt)
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
    -- new puffs keep their birth colour
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

    -- every pipe uses the same mixture
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

                if step.isEmitting ~= shouldEmit then
                    step.isEmitting = shouldEmit
                    if shouldEmit then
                        particleSystem.emittedReset = (particleSystem.emittedReset or 0) + 1
                        step.emissionAccumulator = math.max(step.emissionAccumulator, 1)
                    else
                        step.emissionAccumulator = 0
                    end
                    particleSystem.isEmitting = shouldEmit
                end

                if shouldEmit then
                    if plumeIndex == 1 then
                        emitterCount = emitterCount + 1
                    end

                    local emitScale = lerp(step.emitMin, step.emitMax, flowScale) * share * emitGain
                    local hasMoved = math.abs(alpha - step.lastAlpha) >= config.TUNE_EPSILON
                        or math.abs(emitScale - step.lastEmit) >= config.TUNE_EPSILON
                    local speedScale = lerp(step.speedMin, step.speedMax, flowScale)

                    if hasMoved or hasNewTint then
                        step.lastAlpha = alpha
                        step.lastEmit = emitScale
                    end
                    particleSystem.emitScale = emitScale
                    particleSystem.speed = step.baseSpeed * speedScale
                    particleSystem.speedRandom = step.baseSpeedRandom * speedScale

                    local emissionDt = math.min(dt, 100)
                    step.emissionAccumulator = step.emissionAccumulator
                        + step.profile.rate * emitScale * emissionDt
                    local spawnCount = math.floor(step.emissionAccumulator)
                    step.emissionAccumulator = step.emissionAccumulator - spawnCount

                    local grey = (state.red + state.green + state.blue) / 3
                    local red = lerp(state.red, grey, sharedWash)
                    local green = lerp(state.green, grey, sharedWash)
                    local blue = lerp(state.blue, grey, sharedWash)
                    for _ = 1, spawnCount do
                        if spawnPuff(state, plume, step, speedScale, red, green, blue, alpha) then
                            step.activePuffs = step.activePuffs + 1
                            state.activePuffs = state.activePuffs + 1
                        else
                            break
                        end
                    end

                    if share > state.drawnShare then
                        state.drawnShare = share
                        state.alpha = alpha
                        state.emitScale = emitScale
                    end
                else
                    particleSystem.emitScale = 0
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
        dbg.activePuffs = state.activePuffs
        dbg.collisionCount = state.collisionCount
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
