-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---Exhaust smoke model, colouring and driving the plume puffs from soot, oil, unburnt fuel, water vapour and gas flow
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
        return config.CLEAN_TINT[1], config.CLEAN_TINT[2], config.CLEAN_TINT[3]
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
local function getOpacity(soot, oil, unburnt)
    local config = RMS_Config.EXHAUST
    local opticalDepth = config.K_SOOT * soot + config.K_OIL * oil + config.K_UNBURNT * unburnt
    local raw = 1 - math.exp(-opticalDepth)
    local floor = config.OPACITY_FLOOR

    return math.max(raw - floor, 0) / (1 - floor)
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

-- the air humidity a condensing plume depends on, rain and snow saturating it
local WET_WEATHER_TYPES = {"RAIN", "SNOW", "HAIL", "FOG"}

---Returns the ambient temperature of the current weather
-- @return float temperature ambient temperature in degrees
local function getAmbientTemperature()
    if RMS_Electrical ~= nil and RMS_Electrical.getEnvironmentTemperatureC ~= nil then
        return RMS_Electrical.getEnvironmentTemperatureC()
    end

    return 15
end

---Returns how wet the air is, from the ground wetness and a falling precipitation
-- @return float wetness wetness between 0 and 1
local function getAirWetness()
    local weather = g_currentMission ~= nil and g_currentMission.environment ~= nil
        and g_currentMission.environment.weather or nil
    local wetness = 0
    if weather ~= nil and weather.getGroundWetness ~= nil then
        wetness = getNumber(weather:getGroundWetness(), 0, 0, 1) * 0.5
    end

    local weatherType = RMS_Main ~= nil and RMS_Main.currentWeather or nil
    if WeatherType ~= nil and weatherType ~= nil then
        for _, name in ipairs(WET_WEATHER_TYPES) do
            if WeatherType[name] ~= nil and weatherType == WeatherType[name] then
                return 1
            end
        end
    end

    return wetness
end

---Returns the optical depth of the water vapour condensing in cold air, which a sound engine makes too
-- the combustion water condenses where the hot gas mixes with air below the dew point, so the cold and the
-- humidity of the air set it, not the state of the engine
-- @param table input ambient temperature, air wetness, load and engine temperature
-- @return float tau vapour optical depth at the reference puff size
-- @return float coldness share of the full condensation the ambient temperature allows
function RMS_Exhaust.calculateVapourTarget(input)
    local config = RMS_Config.EXHAUST.VAPOUR
    local ambient = getNumber(input.ambientTemperature, 15, -80, 80)
    local coldness = 1 - getRamp(ambient, config.FULL_C, config.START_C)
    if coldness <= 0 then
        return 0, 0
    end

    local humidity = clamp(config.HUMIDITY_BASE + config.HUMIDITY_WEATHER * getNumber(input.wetness, 0, 0, 1), 0, 1)
    local fuel = lerp(config.IDLE_SHARE, 1, clamp(getNumber(input.load, 0, 0, 1.5), 0, 1))
    local coldTemperature = RMS_Config.CORE.ENGINE_FACTOR_DATA.COLD_MOTOR_TEMP_THRESHOLD
    local operatingTemperature = RMS_Config.THERMAL.PID_TARGET_TEMP
    local engineTemperature = getNumber(input.engineTemperature, operatingTemperature, -80, 160)
    local coldEngine = 1 - getRamp(engineTemperature, coldTemperature, operatingTemperature)

    return config.K * coldness * humidity * fuel * (1 + config.COLD_ENGINE_BOOST * coldEngine), coldness
end

---Returns the temperature rise of the exhaust gas over the air, higher under load and on a warm engine
-- @param float load engine load
-- @param float engineTemperature engine temperature in degrees
-- @return float rise temperature rise in kelvin
function RMS_Exhaust.getExhaustGasTemperatureRise(load, engineTemperature)
    local config = RMS_Config.EXHAUST.EGT
    local coldTemperature = RMS_Config.CORE.ENGINE_FACTOR_DATA.COLD_MOTOR_TEMP_THRESHOLD
    local operatingTemperature = RMS_Config.THERMAL.PID_TARGET_TEMP
    local warmth = getRamp(getNumber(engineTemperature, operatingTemperature, -80, 160), coldTemperature, operatingTemperature)
    local rise = lerp(config.RISE_IDLE_K, config.RISE_FULL_K, clamp(getNumber(load, 0, 0, 1.5), 0, 1))

    return rise * lerp(config.COLD_FACTOR, 1, warmth)
end

---Returns the eddy velocity of the air at a point, shared by every puff so neighbours meander together
-- each component ignores its own axis, so the field carries no divergence and the plume neither gathers
-- nor tears apart where the eddies meet
-- @param float x world x, already shifted against the wind so the eddies drift with it
-- @param float y world y
-- @param float z world z, already shifted against the wind
-- @param float timeSeconds time in seconds
-- @param float amplitude peak eddy speed in m/s
-- @return float x eddy velocity x
-- @return float y eddy velocity y
-- @return float z eddy velocity z
function RMS_Exhaust.getTurbulenceVelocity(x, y, z, timeSeconds, amplitude)
    if amplitude <= 0 then
        return 0, 0, 0
    end

    local config = RMS_Config.EXHAUST.TURBULENCE
    local velocityX, velocityY, velocityZ, weights = 0, 0, 0, 0
    for index, octave in ipairs(config.OCTAVES) do
        local wavenumber = 2 * math.pi / octave.wavelength
        local phase = timeSeconds * octave.frequency * 2 * math.pi
        local offset = index * 1.7
        velocityX = velocityX + octave.weight * math.sin(wavenumber * (0.8 * y + 0.6 * z) + phase + offset)
        velocityY = velocityY + octave.weight * math.sin(wavenumber * (0.8 * z + 0.6 * x) + phase * 1.13 + offset * 2.3)
        velocityZ = velocityZ + octave.weight * math.sin(wavenumber * (0.8 * x + 0.6 * y) + phase * 0.91 + offset * 3.1)
        weights = weights + octave.weight
    end

    local scale = amplitude / math.max(weights, 0.001)

    return velocityX * scale, velocityY * scale * config.VERTICAL_SHARE, velocityZ * scale
end

-- GIANTS only renders the sprite, RMS owns every puff
local MANAGED_RENDERER_FUNCTIONS = {
    "getGeometry",
    "setMaxNumOfParticles",
    "setNumOfParticlesToEmitPerMs",
    "setParticleSystemSpeed",
    "setParticleSystemSpeedRandom",
    "setParticleSystemNormalSpeed",
    "setParticleSystemTangentSpeed",
    "setEmitterShapeVelocityScale",
    "getParticleSystemLifespan",
    "getParticleSystemSpriteScaleX",
    "getParticleSystemSpriteScaleXGain",
    "setParticleSystemLifespan",
    "setParticleSystemSpriteScaleX",
    "setParticleSystemSpriteScaleY",
    "setParticleSystemSpriteScaleXGain",
    "setParticleSystemSpriteScaleYGain",
    "addParticleSystemSimulationTime",
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

---Returns the width of one camera-facing puff at its current age
-- @param table puff managed puff
-- @return float size sprite width in metres
local function getPuffSize(puff)
    local age = clamp(getNumber(puff.age, 0, 0), 0, puff.lifespan)

    return math.max(puff.sizeStart + puff.sizeGain * age, 0)
end

---Returns the width the shared plume schedule gives a puff at its age: its smoke spreads over that width and its
-- thinning follows it, whatever the width its own sprite is drawn at
-- @param table puff managed puff
-- @return float size schedule width in metres
local function getScheduleSize(puff)
    local schedule = puff.spacing
    if schedule == nil then
        return getPuffSize(puff)
    end

    local age = clamp(getNumber(puff.age, 0, 0), 0, puff.lifespan)

    return math.max(schedule.sizeStart + schedule.sizeGain * age, 0)
end

---Returns the width the smoke of a puff has spread over at its age: the real width of the gas drawn at the sprite
-- scale, the same for every puff of that age so a narrower sprite never shows as a dark bead, or its own sprite
-- once that has grown wider, or when the engine keeps the asset size
-- @param table puff managed puff
-- @return float size spread width in metres
local function getSpreadSize(puff)
    local schedule = puff.spacing
    local profile = schedule ~= nil and schedule.jetProfile or nil
    if profile == nil or puff.spriteRatio == nil then
        return getPuffSize(puff)
    end

    local age = clamp(getNumber(puff.age, 0, 0), 0, puff.lifespan)
    local position = age / profile.stepMs + 1
    local index = math.min(math.floor(position), #profile.widths - 1)
    local widths = profile.widths
    local width = widths[index] + (widths[index + 1] - widths[index]) * math.min(position - index, 1)

    return math.max(width * puff.spriteRatio, getPuffSize(puff))
end

---Returns the bounding-sphere radius of one camera-facing puff
-- @param table puff managed puff
-- @return float radius radius in metres
function RMS_Exhaust.getPuffRadius(puff)
    return getPuffSize(puff) * RMS_Config.EXHAUST.PUFF.RADIUS_SHARE
end

---Returns what the smoke and the water vapour of one puff still block of the light behind it
-- both spread as the plume does at the age of the puff, so the puffs drawn wider near the outlet widen the plume
-- without leaving the narrower ones behind as dark beads, the vapour also evaporating into the drier air around
-- it, and a puff standing for retired neighbours carries their share as well
-- @param table puff managed puff
-- @return float smoke smoke optical depth
-- @return float vapour vapour optical depth
function RMS_Exhaust.getPuffOpticalDepths(puff)
    local sizeStart = math.max(puff.sizeStart, 0.001)
    local dilution = (sizeStart / math.max(getSpreadSize(puff), sizeStart)) ^ 2 * getNumber(puff.weight, 1, 0)
    local smoke = getNumber(puff.tau, 0, 0) * dilution
    local vapour = getNumber(puff.tauVapour, 0, 0) * dilution
    if vapour > 0 then
        vapour = vapour * math.exp(-getNumber(puff.age, 0, 0) / math.max(getNumber(puff.evaporationMs, 1, 1), 1))
    end

    return smoke, vapour
end

---Returns the alpha a puff is drawn with, faded out at the end of the visible plume, lower once a contacted
-- puff has spread along a surface
-- @param table puff managed puff
-- @return float alpha rendered alpha
function RMS_Exhaust.getPuffRenderAlpha(puff)
    local puffConfig = RMS_Config.EXHAUST.PUFF
    local smoke, vapour = RMS_Exhaust.getPuffOpticalDepths(puff)
    local alpha = clamp((1 - math.exp(-(smoke + vapour))) * puffConfig.SPRITE_ALPHA_GAIN, 0, 1)
    if puff.fadesOut == true then
        local age = getNumber(puff.age, 0, 0)
        alpha = alpha * clamp((getNumber(puff.lifespan, age, 0) - age) / puffConfig.FADE_OUT_MS, 0, 1)
    end
    local contactRadius = getNumber(puff.contactRadius, 0, 0)
    local surfaceTravel = getNumber(puff.surfaceTravel, 0, 0)
    if contactRadius > 0 and surfaceTravel > 0 then
        alpha = alpha * ((contactRadius / (contactRadius + surfaceTravel)) ^ 0.57)
    end

    return alpha
end

---Returns the colour a puff is drawn with, its smoke tint whitened by the vapour it still carries
-- @param table puff managed puff
-- @return float red
-- @return float green
-- @return float blue
function RMS_Exhaust.getPuffRenderColour(puff)
    local smoke, vapour = RMS_Exhaust.getPuffOpticalDepths(puff)
    if vapour <= 0 then
        return puff.red, puff.green, puff.blue
    end

    local tint = RMS_Config.EXHAUST.VAPOUR_TINT
    local share = vapour / (smoke + vapour)

    return lerp(puff.red, tint[1], share), lerp(puff.green, tint[2], share), lerp(puff.blue, tint[3], share)
end

---Projects an impacting puff onto a surface while retaining its tangential momentum
-- a puff moving into the surface stops against it, while one that already overlaps it, having grown into it or
-- met it at a glancing angle, eases out instead of jumping its whole overlap in one step
-- @param table puff managed puff
-- @param table hit raycast hit with point, normal and incoming direction
-- @param float radius current puff radius
-- @param float? pushLimit most the puff may be pushed off the surface in this step, in metres, unbounded if nil
function RMS_Exhaust.resolvePuffImpact(puff, hit, radius, pushLimit)
    local normalX, normalY, normalZ = normalizeVector(hit.nx, hit.ny, hit.nz, 0, -1, 0)
    if dotProduct(normalX, normalY, normalZ, hit.dx or 0, hit.dy or 0, hit.dz or 0) > 0 then
        normalX, normalY, normalZ = -normalX, -normalY, -normalZ
    end

    local margin = math.max(radius * 0.02, 0.005)
    local clearance = radius + margin
    local distance = dotProduct(puff.x - hit.x, puff.y - hit.y, puff.z - hit.z, normalX, normalY, normalZ)
    if pushLimit ~= nil and distance < clearance then
        local push = math.min(clearance - math.max(distance, 0), pushLimit)
        puff.x = puff.x + normalX * push
        puff.y = puff.y + normalY * push
        puff.z = puff.z + normalZ * push
    else
        puff.x = hit.x + normalX * clearance
        puff.y = hit.y + normalY * clearance
        puff.z = hit.z + normalZ * clearance
    end

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
        local surfaceSpread = blockedSpeed * RMS_Config.EXHAUST.PUFF.SURFACE_SPREAD
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
end

---Returns how a jet widens and how far it travels through the air over one step, exactly: the momentum it
-- carries per unit of width stays the same, so its width squared grows linearly with time and the distance it
-- covers is the width it gained over its spread
-- @param float width jet width at the start of the step in metres
-- @param float relativeSpeed jet speed through the air in m/s
-- @param float stepSeconds step in seconds
-- @return float width jet width at the end of the step in metres
-- @return float travel distance travelled through the air in metres
local function getJetStep(width, relativeSpeed, stepSeconds)
    local spread = RMS_Config.EXHAUST.PUFF.JET_SPREAD
    if spread <= 0 then
        return width, relativeSpeed * stepSeconds
    end

    local widened = math.sqrt(width * width + 2 * spread * relativeSpeed * width * stepSeconds)

    return widened, (widened - width) / spread
end

---Advances one RMS puff through entrainment, wind, eddies, buoyancy and solid contacts
-- @param table puff managed puff
-- @param float dt elapsed time in ms
-- @param table? environment wind, eddies, ambient temperature and the trace, contact and roof callbacks
function RMS_Exhaust.advancePuff(puff, dt, environment)
    environment = environment or {}
    local puffConfig = RMS_Config.EXHAUST.PUFF
    local turbulenceConfig = RMS_Config.EXHAUST.TURBULENCE
    local dilutionExponent = RMS_Config.EXHAUST.EGT.DILUTION_EXPONENT
    local ambientKelvin = getNumber(environment.ambientC, 15, -80, 80) + 273.15
    local windSpeed = getNumber(environment.windSpeed, 0, 0)
    local remainingMs = math.max(getNumber(dt, 0, 0), 0)

    while remainingMs > 0 and puff.age < puff.lifespan do
        local stepMs = math.min(remainingMs, 50)
        local stepSeconds = stepMs / 1000
        remainingMs = remainingMs - stepMs
        puff.age = math.min(puff.age + stepMs, puff.lifespan)
        local size = getPuffSize(puff)
        local radius = size * puffConfig.RADIUS_SHARE

        if puff.contact ~= nil and environment.hasContact ~= nil
                and not environment.hasContact(puff, puff.contact, radius) then
            puff.contact = nil
        end

        -- a roof overhead keeps most of the wind and of its eddies away
        local shelterTarget = getNumber(puff.shelterTarget, 0, 0, 1)
        local shelter = getNumber(puff.shelter, shelterTarget, 0, 1)
        shelter = shelter + (shelterTarget - shelter) * math.min(stepMs / (puffConfig.SHELTER_TAU + stepMs), 1)
        puff.shelter = shelter
        local windScale = lerp(1, puffConfig.SHELTER_WIND_SHARE, shelter)

        -- the air around the puff: the weather wind plus the eddies drifting with it
        local airX = getNumber(environment.windX, 0) * windScale
        local airY = getNumber(environment.windY, 0) * windScale
        local airZ = getNumber(environment.windZ, 0) * windScale
        if environment.getTurbulence ~= nil then
            local amplitude = turbulenceConfig.BASE + turbulenceConfig.PER_WIND * windSpeed * windScale
            local eddyX, eddyY, eddyZ = environment.getTurbulence(puff.x, puff.y, puff.z)
            airX, airY, airZ = airX + eddyX * amplitude, airY + eddyY * amplitude, airZ + eddyZ * amplitude
        end

        -- the air cannot blow through a surface: it turns along it, and over it when it meets it head on,
        -- so a puff against a wall or a roof is carried away instead of piling up
        if puff.contact ~= nil then
            local contact = puff.contact
            local inward = dotProduct(airX, airY, airZ, contact.nx, contact.ny, contact.nz)
            if inward < 0 then
                airX = airX - inward * contact.nx
                airY = airY - inward * contact.ny
                airZ = airZ - inward * contact.nz
                local overX, overY, overZ = normalizeVector(-contact.ny * contact.nx, 1 - contact.ny * contact.ny,
                    -contact.ny * contact.nz, puff.spreadX, puff.spreadY, puff.spreadZ)
                local turned = -inward * puffConfig.SURFACE_FLOW_SHARE
                airX, airY, airZ = airX + overX * turned, airY + overY * turned, airZ + overZ * turned
            end
        end

        -- the gas widens with the air it swallows: a jet takes in air in proportion to its speed through it, a
        -- crosswind folds in more until it has bent the jet to its own direction, and the eddies keep mixing
        -- after that; the same momentum shared with more air carries it slower. A young jet halves its speed
        -- within a frame, so the step follows the exact jet solution, its width squared growing linearly and its
        -- travel through the air being the width it gained over the spread, rather than a straight Euler step
        -- that would leave the puffs already out behind the ones just emitted and bunch them frame by frame
        local relativeX, relativeY, relativeZ = puff.vx - airX, puff.vy - airY, puff.vz - airZ
        local relativeSpeed = getVectorLength(relativeX, relativeY, relativeZ)
        local crossSpeed = 0
        local puffSpeed = getVectorLength(puff.vx, puff.vy, puff.vz)
        if puffSpeed > 0.001 then
            local airAlong = dotProduct(airX, airY, airZ, puff.vx, puff.vy, puff.vz) / puffSpeed
            local airSpeed = getVectorLength(airX, airY, airZ)
            crossSpeed = math.sqrt(math.max(airSpeed * airSpeed - airAlong * airAlong, 0))
        end
        local width = getNumber(puff.width, puff.sizeStart, 0.001)
        local jetWidth, relativeTravel = getJetStep(width, relativeSpeed, stepSeconds)
        local widened = jetWidth + (puffConfig.JET_CROSS_SPREAD * crossSpeed
            + getNumber(puff.ambientGrowth, 0, 0)) * stepSeconds
        puff.width = widened
        -- a crosswind also pushes on the gas and bends it over, a drag still air does not have
        local dampingShare = clamp(crossSpeed / puffConfig.DAMPING_CROSS_SPEED, puffConfig.DAMPING_FLOOR_SHARE, 1)
        local damping = math.exp(-puffConfig.BASE_DAMPING * dampingShare * stepSeconds)
        local drag = width / widened * damping
        local travelShare = relativeSpeed > 0.000001 and relativeTravel * (1 + damping) * 0.5 / relativeSpeed or 0
        local travelX = airX * stepSeconds + relativeX * travelShare
        local travelY = airY * stepSeconds + relativeY * travelShare
        local travelZ = airZ * stepSeconds + relativeZ * travelShare
        puff.vx = airX + relativeX * drag
        puff.vy = airY + relativeY * drag
        puff.vz = airZ + relativeZ * drag

        -- hot gas rises, its excess heat shared with the air it has taken in, so a plume slowing down keeps its
        -- lift while one torn by the wind loses it
        local deltaT0 = getNumber(puff.deltaT, 0, 0)
        if deltaT0 > 0 then
            local deltaT = deltaT0 * (getNumber(puff.jetStart, width, 0.001) / widened) ^ dilutionExponent
            local lift = 9.81 * deltaT / (ambientKelvin + deltaT) * stepSeconds
            puff.vy = puff.vy + lift
            travelY = travelY + lift * stepSeconds * 0.5
        end

        local previousX, previousY, previousZ = puff.x, puff.y, puff.z
        local nextX = puff.x + travelX
        local nextY = puff.y + travelY
        local nextZ = puff.z + travelZ
        local hit = environment.trace ~= nil
            and environment.trace(puff, puff.x, puff.y, puff.z, nextX, nextY, nextZ, radius) or nil

        local pushLimit = puffConfig.SURFACE_PUSH_SPEED * stepSeconds
        if hit ~= nil then
            RMS_Exhaust.resolvePuffImpact(puff, hit, radius, pushLimit)
            local remainingShare = clamp(1 - getNumber(hit.fraction, 1, 0, 1), 0, 1)
            nextX = puff.x + puff.vx * stepSeconds * remainingShare
            nextY = puff.y + puff.vy * stepSeconds * remainingShare
            nextZ = puff.z + puff.vz * stepSeconds * remainingShare
        end

        -- the sweep follows the centre, so a wide rising puff also looks for a roof it grows into
        if puff.contact == nil and puff.vy > 0 and radius >= puffConfig.ROOF_PROBE_MIN_RADIUS
                and environment.probeAbove ~= nil then
            local roofHit = environment.probeAbove(puff, nextX, nextY, nextZ, radius)
            if roofHit ~= nil then
                RMS_Exhaust.resolvePuffImpact(puff, roofHit, radius, pushLimit)
                nextX, nextY, nextZ = puff.x, puff.y, puff.z
            end
        end

        if puff.contact ~= nil then
            local contact = puff.contact
            local distance = dotProduct(nextX - contact.x, nextY - contact.y, nextZ - contact.z,
                contact.nx, contact.ny, contact.nz)
            local clearance = radius + math.max(radius * 0.02, 0.005)
            if distance < clearance then
                local correction = math.min(clearance - distance, pushLimit)
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

---Integrates the width and the speed of the gas of one puff over its life, as advancePuff moves it without the
-- eddies, the heat and the surfaces: a jet leaving upward into a level wind, kept until the flow or the wind change
-- @param table emission emission parameters of the puffs
local function updateJetProfile(emission)
    local puffConfig = RMS_Config.EXHAUST.PUFF
    local profile = emission.jetProfile
    if profile ~= nil and math.abs(profile.speed - emission.speed) <= profile.speed * 0.01
            and math.abs(profile.windSpeed - emission.windSpeed) <= 0.05 and profile.jetStart == emission.jetStart
            and math.abs(profile.deltaT - emission.deltaT) <= 5 then
        return
    end

    local stepMs = puffConfig.JET_PROFILE_STEP_MS
    local stepSeconds = stepMs / 1000
    local dilutionExponent = RMS_Config.EXHAUST.EGT.DILUTION_EXPONENT
    local ambientKelvin = getNumber(emission.ambientC, 15, -80, 80) + 273.15
    local wind = emission.windSpeed
    local jetStart = emission.jetStart
    local width = jetStart
    local velocityX, velocityY = 0, emission.speed
    local widths, speeds = {width}, {emission.speed}

    -- the jet step is exact, so one step per sample holds the profile within a few percent of a fine one
    for index = 2, math.ceil(puffConfig.LIFE_MAX / stepMs) + 1 do
        local relativeX = velocityX - wind
        local relativeSpeed = math.sqrt(relativeX * relativeX + velocityY * velocityY)
        local speed = math.sqrt(velocityX * velocityX + velocityY * velocityY)
        local crossSpeed = speed > 0.001 and math.abs(wind * velocityY) / speed or 0
        local widened = getJetStep(width, relativeSpeed, stepSeconds)
            + (puffConfig.JET_CROSS_SPREAD * crossSpeed + emission.ambientGrowth) * stepSeconds
        local dampingShare = clamp(crossSpeed / puffConfig.DAMPING_CROSS_SPEED, puffConfig.DAMPING_FLOOR_SHARE, 1)
        local drag = width / widened * math.exp(-puffConfig.BASE_DAMPING * dampingShare * stepSeconds)
        velocityX = wind + relativeX * drag
        velocityY = velocityY * drag
        width = widened
        local deltaT = emission.deltaT * (jetStart / width) ^ dilutionExponent
        velocityY = velocityY + 9.81 * deltaT / (ambientKelvin + deltaT) * stepSeconds
        widths[index] = width
        speeds[index] = math.sqrt(velocityX * velocityX + velocityY * velocityY)
    end

    emission.jetProfile = {
        speed = emission.speed,
        windSpeed = emission.windSpeed,
        jetStart = emission.jetStart,
        deltaT = emission.deltaT,
        stepMs = stepMs,
        widths = widths,
        speeds = speeds
    }
end

---Reads one series of a jet profile at an age, between its samples
-- @param table profile jet profile
-- @param table series widths or speeds of the profile
-- @param float ageMs age in ms
-- @return float value interpolated value
local function sampleJetProfile(profile, series, ageMs)
    local position = math.max(ageMs, 0) / profile.stepMs + 1
    local index = math.min(math.floor(position), #series - 1)
    local share = math.min(position - index, 1)

    return series[index] + (series[index + 1] - series[index]) * share
end

---Returns the width the gas of a puff has reached at an age
-- @param table emission emission parameters of the puffs
-- @param float ageMs age in ms
-- @return float width width in metres
local function getJetWidth(emission, ageMs)
    return sampleJetProfile(emission.jetProfile, emission.jetProfile.widths, ageMs)
end

---Returns the spacing between successive puffs of one outlet once their sprites have grown to a size
-- the jet slows as it widens, but the wind and the eddies keep carrying them apart
-- @param table emission emission parameters of the puffs
-- @param float size sprite width in metres
-- @return float spacing spacing in metres
local function getPuffSpacing(emission, size)
    local ageMs = math.max(size - emission.sizeStart, 0) / math.max(emission.sizeGain, 0.000001)
    local speed = sampleJetProfile(emission.jetProfile, emission.jetProfile.speeds, ageMs)

    return math.max(speed, emission.dispersalSpeed) / math.max(emission.rate, 0.001)
end

---Returns what a side view through the plume blocks where its puffs have grown to a size
-- each puff thins as it grows, while more of its neighbours overlap it as they bunch up
-- @param table emission emission parameters of the puffs
-- @param float size puff width in metres
-- @return float tau optical depth of the smoke and the vapour together
local function getPlumeOpticalDepth(emission, size)
    local overlap = math.max(size / getPuffSpacing(emission, size), 1)
    local dilution = (emission.sizeStart / size) ^ 2
    local tau = emission.tau * dilution * overlap
    if emission.tauVapour > 0 then
        local age = (size - emission.sizeStart) / emission.sizeGain
        tau = tau + emission.tauVapour * dilution * overlap * math.exp(-age / emission.evaporationMs)
    end

    return tau
end

---Returns the share of the plume one puff stands for once its neighbours have started retiring in halves
-- a puff of level L survives L halvings carrying the depth of those that retired, then fades in turn, and at
-- every size the survivors and the fading ones add up exactly to the depth the whole set had
-- @param table puff managed puff
-- @param float size width the shared plume schedule gives the puff at its age, in metres
-- @return float weight optical depth multiplier, 0 once the puff has retired
function RMS_Exhaust.getThinningWeight(puff, size)
    if puff.spacing == nil then
        return 1
    end

    local excess = size / getPuffSpacing(puff.spacing, size) / RMS_Config.EXHAUST.PUFF.OVERLAP_TARGET
    if excess <= 1 then
        return 1
    end

    local stage = math.log(excess) / math.log(2)
    local level = puff.level or 0
    local levelMax = RMS_Config.EXHAUST.PUFF.THIN_LEVEL_MAX
    if level >= levelMax then
        -- the last survivors never retire, each standing for every puff of its stretch from then on
        return 2 ^ math.min(stage, levelMax)
    elseif stage <= level then
        return 2 ^ stage
    elseif stage < level + 1 then
        return 2 ^ (level + 1) - 2 ^ stage
    end

    return 0
end

---Returns the lifespan after which the plume has thinned below what an eye catches
-- read on the whole plume and not on one puff, since a puff too faint alone still darkens its neighbours
-- @param table emission emission parameters of the puffs
-- @return float lifespan lifespan in ms
local function getVisibleLifespan(emission)
    local puffConfig = RMS_Config.EXHAUST.PUFF
    local visible = puffConfig.TAU_VISIBLE
    local low = emission.sizeStart
    local high = math.max(puffConfig.SIZE_MAX, low)
    local size = high

    if getPlumeOpticalDepth(emission, low) < visible then
        size = low
    elseif getPlumeOpticalDepth(emission, high) < visible then
        -- the depth only falls as the puffs grow, so halving the bracket converges on the fade point
        for _ = 1, 16 do
            local middle = (low + high) * 0.5
            if getPlumeOpticalDepth(emission, middle) >= visible then
                low = middle
            else
                high = middle
            end
        end
        size = high
    end

    local lifespan = (size - emission.sizeStart) / math.max(emission.sizeGain, 0.000001)

    return clamp(lifespan, puffConfig.LIFE_MIN, puffConfig.LIFE_MAX)
end

---Returns how long a puff of each thinning level lives before it has faded into its neighbours
-- a level L puff is gone once the overlap reaches the target times 2^(L+1), so its slot frees at that moment
-- @param table emission emission parameters of the puffs
-- @param table lifespans table filled with the lifespan in ms of each level below the top one
local function updateRetireLifespans(emission, lifespans)
    local puffConfig = RMS_Config.EXHAUST.PUFF
    local sizeStart = emission.sizeStart
    local sizeMax = math.max(puffConfig.SIZE_MAX, sizeStart)
    local sizeGain = math.max(emission.sizeGain, 0.000001)

    for level = 0, puffConfig.THIN_LEVEL_MAX - 1 do
        local wanted = puffConfig.OVERLAP_TARGET * 2 ^ (level + 1)
        local retireSize = nil
        if sizeStart / getPuffSpacing(emission, sizeStart) >= wanted then
            retireSize = sizeStart
        elseif sizeMax / getPuffSpacing(emission, sizeMax) >= wanted then
            local low, high = sizeStart, sizeMax
            for _ = 1, 16 do
                local middle = (low + high) * 0.5
                if middle / getPuffSpacing(emission, middle) >= wanted then
                    high = middle
                else
                    low = middle
                end
            end
            retireSize = high
        end

        lifespans[level] = retireSize ~= nil
            and math.min(math.max((retireSize - sizeStart) / sizeGain, 30), emission.lifespan) or nil
    end
end

---Loads the emitter surface and the puff source once for the session
-- @return boolean loaded true once every source is available
local function loadPlumeSources()
    if RMS_Exhaust.plumeSources ~= nil then
        return RMS_Exhaust.plumeSources.isValid
    end

    local config = RMS_Config.EXHAUST
    local sources = {
        isValid = false,
        sprites = config.PLUME_SPRITES,
        hasManagedRendererApi = getHasManagedRendererApi()
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

    local file = config.PLUME_DIRECTORY .. config.PLUME_SPRITES .. "/" .. config.PLUME_FILE
    local root = loadI3DFile(RMS_Exhaust.modDirectory .. file, false, false, false)
    if root == nil or root == 0 then
        return false
    end

    local node = getChildAt(root, 0)
    if node == nil or node == 0 then
        return false
    end

    -- the source only lends its sprite to the clones, it never draws on its own
    link(getRootNode(), node)
    setVisibility(node, false)
    local geometry = getGeometry(node)
    if geometry == nil or geometry == 0 then
        return false
    end

    sources.assetLifespan = getParticleSystemLifespan(geometry)
    sources.assetSize = getParticleSystemSpriteScaleX(geometry)
    sources.assetSizeGain = getParticleSystemSpriteScaleXGain(geometry)

    -- write test values and read them back, so the plume only relies on the sprite control the engine honours
    setParticleSystemLifespan(geometry, 1234, false)
    sources.canSetLifespan = math.abs(getParticleSystemLifespan(geometry) - 1234) < 1
    setParticleSystemLifespan(geometry, sources.assetLifespan, false)
    setParticleSystemSpriteScaleX(geometry, 0.321)
    setParticleSystemSpriteScaleXGain(geometry, 0.00123)
    sources.canSetSize = math.abs(getParticleSystemSpriteScaleX(geometry) - 0.321) < 0.0001
        and math.abs(getParticleSystemSpriteScaleXGain(geometry) - 0.00123) < 0.000001
    setParticleSystemSpriteScaleX(geometry, sources.assetSize)
    setParticleSystemSpriteScaleXGain(geometry, sources.assetSizeGain)
    if not sources.canSetLifespan or not sources.canSetSize then
        Logging.warning("RMS: exhaust sprites ignore their %s, the plume falls back on the asset values",
            not sources.canSetSize and "size" or "lifespan")
    end

    -- simulation time that outlives any sprite a slot may still hold, whichever lifespan it was born with
    sources.flushMs = math.max(config.PUFF.LIFE_MAX, sources.assetLifespan) + 1000

    sources.puffNode = node
    sources.isValid = true

    return true
end

---Hands the exhaust over to the plumes, silencing what the engine and the vehicle draw on their own
-- the engine keeps its scale limits in the same table as its particle systems, hence the type check
-- @param table vehicle vehicle
-- @param table effects exhaust effects
-- @param boolean isNative true to give the engine its exhaust back
local function setNativeExhaustState(vehicle, effects, isNative)
    local motorizedSpec = vehicle.spec_motorized
    if motorizedSpec.exhaustParticleSystems ~= nil then
        for _, particleSystem in pairs(motorizedSpec.exhaustParticleSystems) do
            if type(particleSystem) == "table" then
                ParticleUtil.setEmittingState(particleSystem, isNative)
            end
        end
    end

    if motorizedSpec.effects ~= nil and g_effectManager ~= nil then
        if not isNative then
            g_effectManager:stopEffects(motorizedSpec.effects)
        elseif getIsSmokeRendered(vehicle) then
            g_effectManager:startEffects(motorizedSpec.effects)
        end
    end

    -- the engine hides this node at load and never shows it, so hidden is the state to hand back
    for _, effect in pairs(effects) do
        setVisibility(effect.effectNode, false)
    end
end

---Keeps what the engine and the vehicle draw at the exhaust silent while the plume owns it
-- the engine turns its exhaust particles back on at a motor start and drives the motor effects of the vehicle
-- with the rpm, so a second smoke would appear next to the plume, at the base of the pipe on some models
-- @param table vehicle vehicle
local function enforceNativeSilence(vehicle)
    local motorizedSpec = vehicle.spec_motorized
    if motorizedSpec.exhaustParticleSystems ~= nil then
        for _, particleSystem in pairs(motorizedSpec.exhaustParticleSystems) do
            if type(particleSystem) == "table" and particleSystem.isEmitting ~= false then
                ParticleUtil.setEmittingState(particleSystem, false)
            end
        end
    end

    if motorizedSpec.effects ~= nil and g_effectManager ~= nil then
        g_effectManager:stopEffects(motorizedSpec.effects)
    end
end

---Counts what the engine and the vehicle would draw at the exhaust, logging where it sits against the outlet
-- @param table vehicle vehicle
-- @param table effects exhaust effects
local function surveyNativeSources(vehicle, effects)
    local motorizedSpec = vehicle.spec_motorized
    local outletNode = nil
    for _, effect in pairs(effects) do
        outletNode = outletNode or effect.node
    end
    local outletY = 0
    if outletNode ~= nil then
        local _, y, _ = getWorldTranslation(outletNode)
        outletY = y
    end

    local particleCount = 0
    local offsets = {}
    if motorizedSpec.exhaustParticleSystems ~= nil then
        for _, particleSystem in pairs(motorizedSpec.exhaustParticleSystems) do
            if type(particleSystem) == "table" then
                particleCount = particleCount + 1
                local node = particleSystem.emitterShape or particleSystem.shape
                if node ~= nil and node ~= 0 then
                    local _, y, _ = getWorldTranslation(node)
                    table.insert(offsets, string.format("%+.2f m", y - outletY))
                end
            end
        end
    end

    local effectCount = 0
    if motorizedSpec.effects ~= nil then
        for _ in pairs(motorizedSpec.effects) do
            effectCount = effectCount + 1
        end
    end

    if particleCount > 0 or effectCount > 0 then
        Logging.info("RMS: %s draws its own exhaust too, %d engine particle systems (height against the outlet %s) and %d motor effects, all kept silent while the RMS plume runs",
            vehicle.getFullName ~= nil and vehicle:getFullName() or "vehicle", particleCount,
            #offsets > 0 and table.concat(offsets, ", ") or "-", effectCount)
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

    setNativeExhaustState(vehicle, effects, isNative)
    state.isNativeOwned = isNative
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

        -- PhysX reports a ray starting inside a convex shape at distance 0, facing back along the ray: the puff
        -- is already within that collider, typically the coarse hull of its own vehicle around the outlet, and
        -- there is no surface to slide on, so it leaves freely rather than being shoved back along its path
        if travelled == 0 and hit.distance <= RMS_Config.EXHAUST.PUFF.INSIDE_HIT_DISTANCE then
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

---Looks straight above a wide puff for a roof its growing top already reaches
local function probePuffAbove(vehicle, puff, x, y, z, radius)
    local hit = castPuffRay(vehicle, puff, x, y, z, 0, 1, 0, radius)
    if hit == nil then
        return nil
    end

    hit.dx, hit.dy, hit.dz = 0, 1, 0

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

---Returns the collision mask of the fixed obstacles that keep the wind off their lee
local function getLeeCollisionMask()
    if RMS_Exhaust.leeCollisionMask ~= nil then
        return RMS_Exhaust.leeCollisionMask
    end

    local mask = 0
    for _, name in ipairs({"STATIC_OBJECT", "BUILDING", "TREE"}) do
        local flag = CollisionFlag ~= nil and CollisionFlag[name] or nil
        if type(flag) == "number" then
            if bit32 ~= nil and bit32.bor ~= nil then
                mask = bit32.bor(mask, flag)
            else
                mask = mask + flag
            end
        end
    end

    RMS_Exhaust.leeCollisionMask = mask

    return mask
end

---Receives the closest hit of a lee raycast
function RMS_Exhaust:onLeeRaycast(transformId, x, y, z, distance)
    self.leeRaycastHit = {objectId = transformId, x = x, y = y, z = z, distance = distance}
end

---Casts one lee ray through triggers to the first fixed obstacle
-- @return table? hit point and distance of the obstacle, nil when the way is clear
local function castLeeRay(originX, originY, originZ, directionX, directionY, directionZ, distance)
    local travelled = 0
    for _ = 1, 6 do
        local remaining = distance - travelled
        if remaining <= 0.000001 then
            return nil
        end

        RMS_Exhaust.leeRaycastHit = nil
        raycastClosest(originX + directionX * travelled, originY + directionY * travelled,
            originZ + directionZ * travelled, directionX, directionY, directionZ, remaining,
            "onLeeRaycast", RMS_Exhaust, getLeeCollisionMask())
        local hit = RMS_Exhaust.leeRaycastHit
        if hit == nil then
            return nil
        end

        if not (type(getHasTrigger) == "function" and getHasTrigger(hit.objectId)) then
            hit.distance = travelled + hit.distance

            return hit
        end

        travelled = travelled + hit.distance + 0.01
    end

    return nil
end

---Looks upwind of the outlet for the building, hedge or tree line whose lee the plume stands in
-- the air behind an obstacle keeps a fraction of the wind up to a couple of obstacle heights, then recovers it
-- over some ten heights, so the obstacle is kept as its face, its top and its height
-- @param table state exhaust smoke state
-- @param float x world x of the outlet
-- @param float y world y of the outlet
-- @param float z world z of the outlet
local function updateLee(state, x, y, z)
    local puffConfig = RMS_Config.EXHAUST.PUFF
    local lee = state.lee
    lee.isValid = false

    local windX, _, windZ = getWindVelocity()
    local windSpeed = getVectorLength(windX, 0, windZ)
    if windSpeed < puffConfig.LEE_MIN_WIND then
        return
    end

    local directionX, directionZ = windX / windSpeed, windZ / windSpeed
    local face = castLeeRay(x, y, z, -directionX, 0, -directionZ, puffConfig.LEE_SEARCH_DISTANCE)
    if face == nil then
        return
    end

    -- the top is looked for from above, just behind the face that was hit
    local probeX, probeZ = face.x - directionX * 0.3, face.z - directionZ * 0.3
    local probeHeight = puffConfig.LEE_PROBE_HEIGHT
    local top = castLeeRay(probeX, y + probeHeight, probeZ, 0, -1, 0, probeHeight)
    local topY = top ~= nil and top.y or y
    local groundY = y - puffConfig.LEE_GROUND_FALLBACK
    local terrain = g_currentMission ~= nil and g_currentMission.terrainRootNode or nil
    if terrain ~= nil and type(getTerrainHeightAtWorldPos) == "function" then
        groundY = getTerrainHeightAtWorldPos(terrain, probeX, 0, probeZ)
    end

    lee.isValid = true
    lee.faceX, lee.faceZ = face.x, face.z
    lee.directionX, lee.directionZ = directionX, directionZ
    lee.topY = topY
    lee.height = math.max(topY - groundY, 0.5)
end

---Returns the shelter the obstacle upwind gives a point, 0 in the free wind
-- @param table? lee obstacle upwind of the outlet
-- @param float x world x
-- @param float y world y
-- @param float z world z
-- @return float shelter shelter on the scale of a roof, 1 keeping the wind share left under one
local function getLeeShelter(lee, x, y, z)
    if lee == nil or not lee.isValid then
        return 0
    end

    local puffConfig = RMS_Config.EXHAUST.PUFF
    local downwind = (x - lee.faceX) * lee.directionX + (z - lee.faceZ) * lee.directionZ
    if downwind < 0 then
        return 0
    end

    -- calm close behind, the wind coming back further downwind and over the top of the obstacle
    local share = lerp(puffConfig.LEE_WIND_SHARE, 1,
        getRamp(downwind / lee.height, puffConfig.LEE_FULL_HEIGHTS, puffConfig.LEE_RECOVERY_HEIGHTS))
    share = lerp(share, 1, getRamp(y - lee.topY, 0, puffConfig.LEE_TOP_BLEND))

    return clamp((1 - share) / (1 - puffConfig.SHELTER_WIND_SHARE), 0, 1)
end

---Tells how sheltered from the wind a point is, fully under a roof, from the indoor mask of the map or from the
-- roof test of the vehicle, or partly in the lee of an obstacle upwind
-- the vehicle test also sees sheds the mask misses, so it counts around the vehicle
-- @param table vehicle vehicle
-- @param float x world x
-- @param float y world y
-- @param float z world z
-- @param float? pipeX world x of the outlet
-- @param float? pipeZ world z of the outlet
-- @return float shelter 1 under a roof, 0 in the free wind
local function getShelterTarget(vehicle, x, y, z, pipeX, pipeZ)
    local indoorMask = g_currentMission ~= nil and g_currentMission.indoorMask or nil
    if indoorMask ~= nil and indoorMask.getIsIndoorAtWorldPosition ~= nil
            and indoorMask:getIsIndoorAtWorldPosition(x, z) == true then
        return 1
    end

    local spec = vehicle.spec_RealisticMechanicalSystems
    if spec ~= nil and spec.isUnderRoof == true and pipeX ~= nil then
        local radius = RMS_Config.EXHAUST.PUFF.SHELTER_RADIUS
        local deltaX, deltaZ = x - pipeX, z - pipeZ
        if deltaX * deltaX + deltaZ * deltaZ <= radius * radius then
            return 1
        end
    end

    return getLeeShelter(spec ~= nil and spec.exhaustSmoke ~= nil and spec.exhaustSmoke.lee or nil, x, y, z)
end

---Returns how many halvings a puff survives, from the trailing zeros of its rank in the outlet
-- one puff in two, one in four, one in eight and so on, so every halving keeps an even spread along the plume
-- @param integer rank rank of the puff in its outlet
-- @return integer level halvings survived
local function getThinningLevel(rank)
    local levelMax = RMS_Config.EXHAUST.PUFF.THIN_LEVEL_MAX
    local level = 0
    while rank > 0 and rank % 2 == 0 and level < levelMax do
        rank = rank / 2
        level = level + 1
    end

    return level
end

---Creates one reusable one-sprite renderer for an RMS-managed puff
local function createPuffSlot()
    local config = RMS_Config.EXHAUST
    local sources = RMS_Exhaust.plumeSources
    local root = createTransformGroup("rmsManagedPuff")
    link(getRootNode(), root)

    local emitterShape = clone(sources.emitShape, true, false, true)
    link(root, emitterShape)
    setScale(emitterShape, 0.001, 0.001, 0.001)
    setClipDistance(emitterShape, config.PLUME_CLIP_DISTANCE)

    local node = clone(sources.puffNode, true, false, true)
    link(root, node)
    setVisibility(node, true)
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
        geometry = geometry,
        emitterShape = emitterShape,
        renderer = renderer,
        isInUse = false,
        elapsed = 0
    }
end

---Deletes every renderer allocated by one exhaust outlet
local function deletePuffPool(plume)
    for _, slot in ipairs(plume.pool) do
        ParticleUtil.deleteParticleSystem(slot.renderer)
        delete(slot.root)
    end
    plume.pool = {}
    plume.freeSlots = {}
end

---Stops every outlet of the vehicle, the puffs already out finishing their life
-- @param table state exhaust smoke state
local function stopPlumes(state)
    if state.plumes == nil then
        return
    end

    for _, plume in ipairs(state.plumes) do
        plume.isEmitting = false
        plume.emissionAccumulator = 0
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
        deletePuffPool(plume)
    end

    state.plumes = nil
    setNativeOwnership(vehicle, state, true)
end

---Builds one plume on every exhaust node of the vehicle
-- @param table vehicle vehicle
-- @param table state exhaust smoke state
-- @param table effects exhaust effects
local function createPlumes(vehicle, state, effects)
    if not loadPlumeSources() then
        return
    end

    local plumes = {}
    for _, effect in pairs(effects) do
        table.insert(plumes, {
            linkNode = effect.node,
            effect = effect,
            pool = {},
            freeSlots = {},
            emissionAccumulator = 0,
            isEmitting = false,
            activePuffs = 0,
            nextRank = 0,
            lastPipeX = nil,
            lastPipeY = nil,
            lastPipeZ = nil,
            pipeVelocityX = 0,
            pipeVelocityY = 0,
            pipeVelocityZ = 0
        })
    end

    state.plumes = plumes
    surveyNativeSources(vehicle, effects)
    setNativeOwnership(vehicle, state, false)
end

---Creates the plumes on the first engine run
-- @param table vehicle vehicle
-- @param table state exhaust smoke state
-- @param table effects exhaust effects
local function ensurePlumes(vehicle, state, effects)
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

---Returns an idle puff slot, allocating one lazily up to the pool cap of an outlet
local function getPuffSlot(plume)
    local freeCount = #plume.freeSlots
    if freeCount > 0 then
        local slot = plume.freeSlots[freeCount]
        plume.freeSlots[freeCount] = nil
        return slot
    end

    if #plume.pool >= RMS_Config.EXHAUST.PUFF.POOL_MAX then
        return nil
    end

    local slot = createPuffSlot()
    if slot ~= nil then
        table.insert(plume.pool, slot)
    end

    return slot
end

---Emits one independently simulated RMS puff from an exhaust outlet
-- @param table state exhaust smoke state
-- @param table plume exhaust outlet
-- @param table emission size, growth, lifespan, optical depths, gas temperature and tint of the new puff
-- @param float ageOffset time in ms the puff left the outlet before the end of this frame
-- @return boolean emitted true when a slot was free
local function spawnPuff(state, plume, emission, ageOffset)
    local slot = getPuffSlot(plume)
    if slot == nil then
        return false
    end

    local puffConfig = RMS_Config.EXHAUST.PUFF
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
    -- every puff leaves at the gas speed: a jet slows as it widens, so a faster one would overtake its
    -- neighbours and bunch them into beads
    local initialSpeed = emission.speed
    local lateralSpeed = emission.speed * puffConfig.SPREAD_SHARE * getDeterministicValue(serial, 3)

    plume.nextRank = plume.nextRank + 1
    local level = getThinningLevel(plume.nextRank)

    -- a puff lives until it retires into its neighbours or the plume has thinned out, whichever comes first,
    -- and whatever the engine refuses to change is drawn from the asset, the physics following what is drawn
    local sources = RMS_Exhaust.plumeSources
    local lifespan = emission.retireLifespans[level] or emission.lifespan
    local sizeStart = emission.sizeStart
    local sizeGain = emission.levelGains[level] or emission.sizeGain
    if not sources.canSetLifespan then
        lifespan = sources.assetLifespan
    end
    if not sources.canSetSize then
        sizeStart = sources.assetSize
        sizeGain = sources.assetSizeGain
    end

    local puff = {
        serial = serial,
        level = level,
        spacing = {
            speed = emission.speed,
            sizeStart = emission.sizeStart,
            sizeGain = emission.sizeGain,
            jetProfile = emission.jetProfile,
            dispersalSpeed = emission.dispersalSpeed,
            rate = emission.rate
        },
        weight = 1,
        fadesOut = lifespan >= emission.lifespan or not sources.canSetLifespan,
        shelter = emission.shelter,
        shelterTarget = emission.shelter,
        shelterTimer = puffConfig.SHELTER_CHECK_MS * getDeterministicValue(serial, 9),
        jetStart = emission.jetStart,
        age = 1,
        lifespan = lifespan,
        sizeStart = sizeStart,
        sizeGain = sizeGain,
        radiusStart = sizeStart * puffConfig.RADIUS_SHARE,
        width = emission.jetStart,
        spriteRatio = sources.canSetSize and puffConfig.SPRITE_GAS_RATIO or nil,
        ambientGrowth = emission.ambientGrowth,
        tau = emission.tau,
        tauVapour = emission.tauVapour,
        evaporationMs = emission.evaporationMs,
        deltaT = emission.deltaT,
        vx = directionX * initialSpeed + spreadX * lateralSpeed + plume.pipeVelocityX,
        vy = directionY * initialSpeed + spreadY * lateralSpeed + plume.pipeVelocityY,
        vz = directionZ * initialSpeed + spreadZ * lateralSpeed + plume.pipeVelocityZ,
        spreadX = spreadX,
        spreadY = spreadY,
        spreadZ = spreadZ,
        red = emission.red,
        green = emission.green,
        blue = emission.blue,
        surfaceTravel = 0
    }

    -- the puffs of one frame left the outlet one after the other, so each starts where its jet has taken it by
    -- now, already wider and slower
    local offset = clamp(getNumber(ageOffset, 0, 0), 0, lifespan * 0.5)
    puff.age = puff.age + offset
    local offsetSeconds = offset / 1000
    local jetStart = emission.jetStart
    local jetWidth = math.sqrt(jetStart * jetStart + 2 * puffConfig.JET_SPREAD * initialSpeed * jetStart * offsetSeconds)
    local jetDistance = puffConfig.JET_SPREAD > 0 and (jetWidth - jetStart) / puffConfig.JET_SPREAD
        or initialSpeed * offsetSeconds
    local jetSlowdown = jetStart / jetWidth
    puff.width = jetWidth
    puff.vx = directionX * initialSpeed * jetSlowdown + spreadX * lateralSpeed + plume.pipeVelocityX
    puff.vy = directionY * initialSpeed * jetSlowdown + spreadY * lateralSpeed + plume.pipeVelocityY
    puff.vz = directionZ * initialSpeed * jetSlowdown + spreadZ * lateralSpeed + plume.pipeVelocityZ
    local carriedX = (spreadX * lateralSpeed + plume.pipeVelocityX) * offsetSeconds
    local carriedY = (spreadY * lateralSpeed + plume.pipeVelocityY) * offsetSeconds
    local carriedZ = (spreadZ * lateralSpeed + plume.pipeVelocityZ) * offsetSeconds
    -- the gas leaves the pipe mouth, so the puff sits half its gas width out, its soft sprite edge over the mouth
    local originX, originY, originZ = getWorldTranslation(plume.linkNode)
    local outletJitter = jetWidth * 0.25 * (getDeterministicValue(serial, 8) * 2 - 1)
    local clearance = jetWidth * 0.5 + 0.005
    puff.x = originX + directionX * (clearance + jetDistance) + spreadX * outletJitter + carriedX
    puff.y = originY + directionY * (clearance + jetDistance) + spreadY * outletJitter + carriedY
    puff.z = originZ + directionZ * (clearance + jetDistance) + spreadZ * outletJitter + carriedZ
    puff.selfIgnoreUntil = clamp(clearance / math.max(initialSpeed, 0.1) * 2000, 25, 250)

    local red, green, blue = RMS_Exhaust.getPuffRenderColour(puff)
    local alpha = RMS_Exhaust.getPuffRenderAlpha(puff)
    puff.lastRenderedAlpha = alpha
    puff.lastRenderedRed = red

    -- a slot holds one sprite and the engine will not add a second, so whatever it still shows is aged out
    -- first: a particle system out of view is not always aged by the engine, and a surviving grown sprite
    -- would otherwise be carried to the outlet in place of the new puff
    local geometry = slot.geometry
    ParticleUtil.setEmittingState(slot.renderer, false)
    addParticleSystemSimulationTime(geometry, sources.flushMs)

    -- the sprite takes the size, growth and life of this puff before it is born, so no two need to match, and
    -- a puff that left the outlet earlier in the frame is born at the size it has grown to, with the life left
    local spriteLifespan = math.max(lifespan - offset, 1)
    local spriteSize = sizeStart + sizeGain * offset
    if sources.canSetLifespan then
        setParticleSystemLifespan(geometry, spriteLifespan, false)
    end
    if sources.canSetSize then
        setParticleSystemSpriteScaleX(geometry, spriteSize)
        setParticleSystemSpriteScaleY(geometry, spriteSize)
        setParticleSystemSpriteScaleXGain(geometry, sizeGain)
        setParticleSystemSpriteScaleYGain(geometry, sizeGain)
    end

    -- a slot holds a single sprite, so it waits for the old one to die before taking the next puff, or the
    -- grown sprite would reappear at the outlet in place of the new one
    slot.puff = puff
    slot.elapsed = 1
    slot.releaseAt = (sources.canSetLifespan and spriteLifespan or sources.assetLifespan) + 100
    slot.isInUse = true
    setWorldTranslation(slot.root, puff.x, puff.y, puff.z)
    setVisibility(slot.root, true)
    slot.isShown = true
    setShaderParameterRecursive(slot.renderer.shape, "colorAlpha", red, green, blue, alpha, false)
    ParticleUtil.setEmittingState(slot.renderer, false)
    ParticleUtil.resetNumOfEmittedParticles(slot.renderer)
    ParticleUtil.setEmittingState(slot.renderer, true)
    addParticleSystemSimulationTime(geometry, 1)
    ParticleUtil.setEmittingState(slot.renderer, false)

    return true
end

---Advances all already emitted puffs, including after their engine has stopped
local function updatePuffPools(vehicle, state, dt)
    if state.plumes == nil then
        state.activePuffs = 0
        return
    end

    local puffConfig = RMS_Config.EXHAUST.PUFF
    local windX, windY, windZ = getWindVelocity()
    local windSpeed = getVectorLength(windX, 0, windZ)
    local timeSeconds = getNumber(g_time, 0, 0) / 1000
    local environment = {
        windX = windX,
        windY = windY,
        windZ = windZ,
        windSpeed = windSpeed,
        ambientC = state.ambientC,
        -- the eddies are carried by the wind, so the field is read where the air came from
        getTurbulence = function(x, y, z)
            return RMS_Exhaust.getTurbulenceVelocity(x - windX * timeSeconds, y, z - windZ * timeSeconds,
                timeSeconds, 1)
        end,
        trace = function(puff, fromX, fromY, fromZ, toX, toY, toZ, radius)
            return tracePuff(vehicle, puff, fromX, fromY, fromZ, toX, toY, toZ, radius)
        end,
        hasContact = function(puff, contact, radius)
            return hasPuffContact(vehicle, puff, contact, radius)
        end,
        probeAbove = function(puff, x, y, z, radius)
            return probePuffAbove(vehicle, puff, x, y, z, radius)
        end
    }

    local activePuffs = 0
    for _, plume in ipairs(state.plumes) do
        updatePipeVelocity(plume, dt)
        local plumeActive = 0
        for _, slot in ipairs(plume.pool) do
            if slot.isInUse then
                slot.elapsed = slot.elapsed + dt
                local puff = slot.puff
                if puff.age < puff.lifespan then
                    puff.shelterTimer = puff.shelterTimer - dt
                    if puff.shelterTimer <= 0 then
                        puff.shelterTarget = getShelterTarget(vehicle, puff.x, puff.y, puff.z, plume.lastPipeX,
                            plume.lastPipeZ)
                        puff.shelterTimer = puffConfig.SHELTER_CHECK_MS
                    end

                    RMS_Exhaust.advancePuff(puff, math.min(dt, puff.lifespan - puff.age), environment)
                    puff.weight = RMS_Exhaust.getThinningWeight(puff, getScheduleSize(puff))
                    if puff.weight <= 0 then
                        -- retired into its neighbours, it stops simulating and drawing at once
                        puff.lifespan = puff.age
                    else
                        setWorldTranslation(slot.root, puff.x, puff.y, puff.z)
                        local alpha = RMS_Exhaust.getPuffRenderAlpha(puff)
                        local red, green, blue = RMS_Exhaust.getPuffRenderColour(puff)
                        local threshold = puffConfig.ALPHA_EPSILON * math.max(alpha, puff.lastRenderedAlpha) + 0.0002
                        if math.abs(alpha - puff.lastRenderedAlpha) >= threshold
                                or math.abs(red - puff.lastRenderedRed) >= puffConfig.ALPHA_EPSILON * 0.3 then
                            setShaderParameterRecursive(slot.renderer.shape, "colorAlpha", red, green, blue, alpha, false)
                            puff.lastRenderedAlpha = alpha
                            puff.lastRenderedRed = red
                        end
                    end
                end

                if puff.age < puff.lifespan then
                    plumeActive = plumeActive + 1
                elseif slot.isShown ~= false then
                    setVisibility(slot.root, false)
                    slot.isShown = false
                end

                if slot.elapsed >= slot.releaseAt then
                    slot.isInUse = false
                    slot.puff = nil
                    table.insert(plume.freeSlots, slot)
                end
            end
        end
        plume.activePuffs = plumeActive
        activePuffs = activePuffs + plumeActive
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
    state.vapour = 0
    state.eraFactor = 1
    state.isStageV = false
    state.red = RMS_Config.EXHAUST.CLEAN_TINT[1]
    state.green = RMS_Config.EXHAUST.CLEAN_TINT[2]
    state.blue = RMS_Config.EXHAUST.CLEAN_TINT[3]
    state.targetSoot = 0
    state.targetOil = 0
    state.targetUnburnt = 0
    state.targetVapour = 0
    state.coldness = 0
    state.load = 0
    state.engineTemperature = nil
    state.ambientC = 15
    state.boostDeficit = 0
    state.opacity = 0
    state.activePuffs = 0
    state.pipeShelter = 0
    state.lee = {isValid = false}
    state.leeTimer = 0
    state.nextPuffSerial = 0
    state.burst = 0
    state.burstCause = nil
    state.burstRefractory = 0
    state.tuneTimer = 0
    state.isActive = false
    state.emission = {}

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
    local engineTemperature = spec.rawEngineTemperature or spec.engineTemperature

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
        engineTemperature = engineTemperature,
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
    state.load = load
    state.engineTemperature = engineTemperature
    state.ambientC = getAmbientTemperature()
    state.targetVapour, state.coldness = RMS_Exhaust.calculateVapourTarget({
        ambientTemperature = state.ambientC,
        wetness = getAirWetness(),
        load = load,
        engineTemperature = engineTemperature
    })

    local drivers = state.drivers
    drivers.boost = targets.boostDeficit
    drivers.unburnt = targets.unburnt
    drivers.wetStacking = getNumber(wetStackingLevel, 0, 0, 1) * clamp(load, 0, 1)
    drivers.preheat = preheatSeverity / 4
    drivers.fault = math.max(sootEffect, oilEffect, unburntEffect)

    state.isActive = true
    ensurePlumes(vehicle, state, effects)
    if state.plumes ~= nil and not state.isNativeOwned then
        enforceNativeSilence(vehicle)
    end
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

---Shares the plume opacity out among the puffs overlapping at the outlet, each carrying the depth it will spread
-- over its own sprite as it grows
-- the model opacity is what the gas blocks as it leaves the pipe, so the smoke a puff carries is the exit
-- concentration times the gas volume it stands for, and a plume at full flow holds that much more smoke
-- downstream; the water only condenses a few decimetres out, once the gas has mixed with the cold air
-- @param table emission emission parameters of the puffs
local function updatePuffDensity(emission)
    local sizeStart = emission.sizeStart
    local overlap = sizeStart / getPuffSpacing(emission, sizeStart)
    local referenceSize = math.max(RMS_Config.EXHAUST.PUFF.REFERENCE_SIZE, sizeStart)
    local referenceOverlap = math.max(referenceSize / getPuffSpacing(emission, referenceSize), 1)
    local referenceAge = (referenceSize - sizeStart) / math.max(emission.sizeGain, 0.000001)

    emission.overlap = overlap
    emission.tau = emission.tauTarget / overlap
    emission.tauVapour = emission.vapourTarget / referenceOverlap * (referenceSize / sizeStart) ^ 2
        * math.exp(referenceAge / emission.evaporationMs)
end

---Fills the emission parameters every new puff of this frame shares, from the gas flow and the smoke
-- the model opacity is what a side view through the plume blocks at the reference size, so each puff only
-- carries its share of it, and the rate is whatever keeps enough neighbours overlapping for the plume to
-- read as one continuous body at any wind
-- @param table vehicle vehicle
-- @param table state exhaust smoke state
-- @param float opacity plume opacity between 0 and 1
-- @param float vapour vapour optical depth at the reference size
-- @param float flow gas flow between 0 and 1
-- @param float burst burst strength between 0 and 1
-- @param float dt time since last call in ms
-- @return table emission emission parameters, the rate in puffs per second included
local function updateEmission(vehicle, state, opacity, vapour, flow, burst, dt)
    local config = RMS_Config.EXHAUST
    local puffConfig = config.PUFF
    local emission = state.emission

    -- the wind the outlet stands in, most of it kept away under a roof and part of it behind an obstacle upwind
    local plume = state.plumes[1]
    state.leeTimer = state.leeTimer - dt
    if state.leeTimer <= 0 and plume ~= nil and plume.lastPipeX ~= nil then
        updateLee(state, plume.lastPipeX, plume.lastPipeY, plume.lastPipeZ)
        state.leeTimer = puffConfig.SHELTER_CHECK_MS
    end
    local shelterTarget = plume ~= nil and plume.lastPipeX ~= nil
        and getShelterTarget(vehicle, plume.lastPipeX, plume.lastPipeY, plume.lastPipeZ, plume.lastPipeX,
            plume.lastPipeZ) or 0
    state.pipeShelter = state.pipeShelter + (shelterTarget - state.pipeShelter)
        * math.min(dt / (puffConfig.SHELTER_TAU + dt), 1)
    local windX, _, windZ = getWindVelocity()
    local windSpeed = getVectorLength(windX, 0, windZ) * lerp(1, puffConfig.SHELTER_WIND_SHARE, state.pipeShelter)

    -- the gas volume leaving the pipe follows the mass flow and its temperature, a few m/s at idle and some thirty
    -- at full power, since the pipe is sized for the rated flow whatever the engine
    local deltaT = RMS_Exhaust.getExhaustGasTemperatureRise(state.load, state.engineTemperature)
    local gasKelvin = getNumber(state.ambientC, 15, -80, 80) + 273.15 + deltaT
    local fullKelvin = 293.15 + config.EGT.RISE_FULL_K
    local exitSpeed = math.max(puffConfig.EXIT_SPEED_MIN, puffConfig.EXIT_SPEED_FULL * flow * gasKelvin / fullKelvin)
        * (1 + burst * config.BURST_SPEED_GAIN)
    -- the pipe is sized for the gas flow, so its section follows the power and its diameter the square root
    local jetStart = clamp(puffConfig.PIPE_DIAMETER_PER_SQRT_KW * math.sqrt(getPeakPowerKw(vehicle)),
        puffConfig.PIPE_DIAMETER_MIN, puffConfig.PIPE_DIAMETER_MAX)
    local spriteRatio = puffConfig.SPRITE_GAS_RATIO

    emission.speed = exitSpeed
    emission.jetStart = jetStart
    emission.sizeStart = jetStart * spriteRatio
    emission.windSpeed = windSpeed
    emission.shelter = state.pipeShelter
    emission.dispersalSpeed = config.TURBULENCE.BASE + config.TURBULENCE.PER_WIND * windSpeed + puffConfig.RISE_SPEED
    emission.ambientGrowth = puffConfig.GROWTH_BASE + puffConfig.GROWTH_PER_WIND * windSpeed
    emission.deltaT = deltaT
    emission.ambientC = state.ambientC
    updateJetProfile(emission)

    -- the puffs leave the outlet this far apart for each one per second, so the rate follows from the overlap
    -- wanted right there, the thinning taking the surplus back as they grow
    local outletSpeed = math.max(getVectorLength(exitSpeed, windSpeed, 0), emission.dispersalSpeed)
    local rate = clamp(puffConfig.OVERLAP_TARGET * outletSpeed / emission.sizeStart, puffConfig.RATE_MIN,
        puffConfig.RATE_MAX)
    local sources = RMS_Exhaust.plumeSources
    if not sources.canSetLifespan then
        -- every sprite then lives as long as the asset says, so the rate has to fit the pool
        rate = math.min(rate, 0.8 * puffConfig.POOL_MAX * 1000 / math.max(sources.assetLifespan, 1))
    end
    emission.rate = rate * (1 + burst * config.BURST_EMIT_GAIN)

    local evaporationMs = lerp(config.VAPOUR.EVAPORATION_WARM_MS, config.VAPOUR.EVAPORATION_COLD_MS, state.coldness)
    local tauTarget = -math.log(math.max(1 - opacity, 0.001)) * (1 + burst * config.BURST_TAU_GAIN)
    emission.tauTarget = tauTarget
    emission.vapourTarget = vapour
    emission.evaporationMs = evaporationMs

    if sources.canSetSize then
        -- a sprite grows at one steady rate while the gas widens fast out of the pipe and slowly after, so it
        -- follows the gas over the first part of the life it will be seen for
        local fitMs = puffConfig.GROWTH_FIT_MIN_MS
        for _ = 1, 2 do
            emission.sizeGain = math.max(spriteRatio * (getJetWidth(emission, fitMs) - jetStart) / fitMs, 0.00005)
            updatePuffDensity(emission)
            fitMs = clamp(getVisibleLifespan(emission) * puffConfig.GROWTH_FIT_SHARE,
                puffConfig.GROWTH_FIT_MIN_MS, puffConfig.GROWTH_FIT_MAX_MS)
        end
    else
        -- the sprites keep the asset size, so the overlap and the thinning are worked out on that one
        emission.sizeStart = sources.assetSize
        emission.sizeGain = sources.assetSizeGain
        updatePuffDensity(emission)
    end

    emission.red = state.red
    emission.green = state.green
    emission.blue = state.blue
    emission.isVisible = tauTarget + vapour > puffConfig.TAU_VISIBLE
    emission.lifespan = getVisibleLifespan(emission)
    emission.retireLifespans = emission.retireLifespans or {}
    updateRetireLifespans(emission, emission.retireLifespans)

    -- a sprite can only grow at one rate, so each thinning level follows the gas over its own life: the puffs
    -- that retire near the outlet widen as fast as the jet does there, the ones that carry the plume away as
    -- slowly as it spreads downwind, while the thinning keeps to the shared schedule that holds the smoke mass
    emission.levelGains = emission.levelGains or {}
    for level = 0, puffConfig.THIN_LEVEL_MAX do
        local gain = emission.sizeGain
        if sources.canSetSize then
            local levelLifespan = emission.retireLifespans[level] or emission.lifespan
            local fitMs = clamp(levelLifespan * puffConfig.GROWTH_FIT_SHARE, puffConfig.GROWTH_FIT_LEVEL_MIN_MS,
                puffConfig.GROWTH_FIT_MAX_MS)
            gain = math.max(spriteRatio * (getJetWidth(emission, fitMs) - jetStart) / fitMs, 0.00005)
        end
        emission.levelGains[level] = gain
    end

    return emission
end

---Drives the plume puffs from the smoothed channels, the gas flow and the transient bursts
-- @param table vehicle vehicle
-- @param float dt time since last call in ms
function RMS_Exhaust.applyShader(vehicle, dt)
    local spec = vehicle.spec_RealisticMechanicalSystems
    local state = spec.exhaustSmoke
    local clock = type(getTimeSec) == "function" and getTimeSec or nil
    local startTime = clock ~= nil and clock() or 0
    dt = getNumber(dt, 0, 0)
    updatePuffPools(vehicle, state, dt)

    -- the game only keeps a vehicle left running awake with automatic motor start: otherwise it falls asleep
    -- once nobody is near, and its plume would stop while the engine still runs or hang frozen in the air
    local isSmoking = state.isActive and state.plumes ~= nil and getIsSmokeRendered(vehicle)
    if (isSmoking or state.activePuffs > 0) and vehicle.raiseActive ~= nil then
        vehicle:raiseActive()
    end

    if not isSmoking then
        return
    end

    local config = RMS_Config.EXHAUST
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
    state.vapour = getSmoothed(state.vapour, state.targetVapour, dt, config.VAPOUR_TAU, config.VAPOUR_TAU)
    -- new puffs keep their birth colour
    local targetRed, targetGreen, targetBlue = getTintMix(state.soot, state.oil, state.unburnt)
    state.red = getSmoothed(state.red, targetRed, dt, config.TINT_TAU, config.TINT_TAU)
    state.green = getSmoothed(state.green, targetGreen, dt, config.TINT_TAU, config.TINT_TAU)
    state.blue = getSmoothed(state.blue, targetBlue, dt, config.TINT_TAU, config.TINT_TAU)

    local opacity = getOpacity(state.soot, state.oil, state.unburnt)
    local vapour = state.vapour
    local flowScale = getFlow(vehicle, state)

    -- a tuning override replaces what the engine asks for on this machine only
    local override = RMS_Exhaust.override
    if override ~= nil then
        opacity = override.opacity or opacity
        flowScale = override.flow or flowScale
        vapour = override.vapour or vapour
    end
    state.opacity = opacity

    state.tuneTimer = state.tuneTimer + dt
    if state.tuneTimer >= config.TUNE_INTERVAL then
        updateBurstEdges(state, state.tuneTimer)
        state.tuneTimer = 0
    end

    local burst = state.burst * opacity
    local emission = updateEmission(vehicle, state, opacity, vapour, flowScale, burst, dt)
    -- a forced opacity on a clean engine has no tint of its own, so it borrows the soot one
    if override ~= nil and override.opacity ~= nil and state.soot + state.oil + state.unburnt < 0.01 then
        emission.red, emission.green, emission.blue = unpack(config.SOOT_TINT)
    end
    local canEmit = emission.isVisible and emission.rate > 0

    for _, plume in ipairs(state.plumes) do
        local shouldEmit = canEmit and getEffectiveVisibility(plume.linkNode)
        if plume.isEmitting ~= shouldEmit then
            plume.isEmitting = shouldEmit
            plume.emissionAccumulator = shouldEmit and math.max(plume.emissionAccumulator, 1) or 0
        end

        if shouldEmit then
            plume.emissionAccumulator = plume.emissionAccumulator + emission.rate * math.min(dt, 100) / 1000
            local spawnCount = math.floor(plume.emissionAccumulator)
            plume.emissionAccumulator = plume.emissionAccumulator - spawnCount
            local interval = 1000 / emission.rate
            for index = 1, spawnCount do
                local ageOffset = math.min((spawnCount - index + plume.emissionAccumulator) * interval, dt)
                if spawnPuff(state, plume, emission, ageOffset) then
                    plume.activePuffs = plume.activePuffs + 1
                    state.activePuffs = state.activePuffs + 1
                else
                    plume.emissionAccumulator = 0
                    break
                end
            end
        end
    end

    if RMS_Utils.getIsDebugDataWanted(vehicle) then
        local dbg = spec.debugData.exhaust
        dbg.opacity = opacity
        dbg.vapour = 1 - math.exp(-vapour)
        dbg.gasTemperature = state.ambientC + emission.deltaT
        dbg.exitSpeed = emission.speed
        dbg.windSpeed = emission.windSpeed
        dbg.shelter = state.pipeShelter
        dbg.activePuffs = state.activePuffs
        dbg.burstCause = state.burstCause
        dbg.isOverridden = override ~= nil
        dbg.isSpriteControlled = RMS_Exhaust.plumeSources.canSetSize == true
            and RMS_Exhaust.plumeSources.canSetLifespan == true
        dbg.updateMs = clock ~= nil and (clock() - startTime) * 1000 or 0
    end
end
