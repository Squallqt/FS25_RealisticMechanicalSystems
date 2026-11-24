-- Copyright © 2026 Squallqt. All rights reserved.

---Exhaust emission and plume simulation
RMS_Exhaust = {}
RMS_Exhaust.modDirectory = g_currentModDirectory

---Returns a value clamped between two bounds
-- @param float value value
-- @param float minimum lower bound
-- @param float maximum upper bound
-- @return float value clamped value
local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(value, maximum))
end

---Returns the value between two values at a share
-- @param float startValue value at 0
-- @param float endValue value at 1
-- @param float alpha share
-- @return float value value at the share
local function lerp(startValue, endValue, alpha)
    return startValue + (endValue - startValue) * alpha
end

---Returns a finite number clamped, the default when it is not one
-- @param any value value
-- @param float defaultValue value when it is not a finite number
-- @param float? minimum lower bound, none when nil
-- @param float? maximum upper bound, none when nil
-- @return float number number
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

---Returns the length of a vector
-- @param float x x
-- @param float y y
-- @param float z z
-- @return float length length
local function getVectorLength(x, y, z)
    return math.sqrt(x * x + y * y + z * z)
end

---Returns a unit vector, the fallback for a null one
-- @param float x x
-- @param float y y
-- @param float z z
-- @param float? fallbackX x of the fallback, 0 when nil
-- @param float? fallbackY y of the fallback, 1 when nil
-- @param float? fallbackZ z of the fallback, 0 when nil
-- @return float x x
-- @return float y y
-- @return float z z
local function normalizeVector(x, y, z, fallbackX, fallbackY, fallbackZ)
    local length = getVectorLength(x, y, z)
    if length <= 0.000001 then
        return fallbackX or 0, fallbackY or 1, fallbackZ or 0
    end

    return x / length, y / length, z / length
end

---Returns the dot product of two vectors
-- @param float ax x of the first vector
-- @param float ay y of the first vector
-- @param float az z of the first vector
-- @param float bx x of the second vector
-- @param float by y of the second vector
-- @param float bz z of the second vector
-- @return float product dot product
local function dotProduct(ax, ay, az, bx, by, bz)
    return ax * bx + ay * by + az * bz
end

---Returns the cross product of two vectors
-- @param float ax x of the first vector
-- @param float ay y of the first vector
-- @param float az z of the first vector
-- @param float bx x of the second vector
-- @param float by y of the second vector
-- @param float bz z of the second vector
-- @return float x x
-- @return float y y
-- @return float z z
local function crossProduct(ax, ay, az, bx, by, bz)
    return ay * bz - az * by, az * bx - ax * bz, ax * by - ay * bx
end

---Returns two unit vectors square to a direction and to each other
-- @param float directionX x of the direction
-- @param float directionY y of the direction
-- @param float directionZ z of the direction
-- @return float sideX x of the side vector
-- @return float sideY y of the side vector
-- @return float sideZ z of the side vector
-- @return float forwardX x of the forward vector
-- @return float forwardY y of the forward vector
-- @return float forwardZ z of the forward vector
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

---Returns a value between 0 and 1 drawn from a serial and a salt
-- @param integer serial serial of the puff
-- @param float salt salt of the draw
-- @return float value value, 0 to 1
local function getDeterministicValue(serial, salt)
    local value = math.sin(serial * 12.9898 + salt * 78.233) * 43758.5453

    return value - math.floor(value)
end

---Returns the share a value climbs between two bounds
-- @param float value value
-- @param float from value at 0
-- @param float to value at 1
-- @return float share share, 0 to 1
local function getRamp(value, from, to)
    return clamp((value - from) / (to - from), 0, 1)
end

---Returns the emission factor of the production year, read from an era table
-- @param integer year production year
-- @param table? eraFactors era table, the particulate one by default
-- @return float factor emission factor
function RMS_Exhaust.getEraFactor(year, eraFactors)
    local factors = eraFactors or RMS_Config.EXHAUST.ERA_FACTORS
    for _, entry in ipairs(factors) do
        if year < entry[1] then
            return entry[2]
        end
    end

    return factors[#factors][2]
end

---Tells whether the engine falls under Stage V
-- @param integer year production year
-- @param any peakPowerKw peak power (kW)
-- @return boolean isStageV true under Stage V
function RMS_Exhaust.getIsStageV(year, peakPowerKw)
    local config = RMS_Config.EXHAUST.STAGE_V
    local power = getNumber(peakPowerKw, 0, 0)
    if power < config.MIN_POWER_KW then
        return false
    end

    if power >= config.MID_POWER_MIN_KW and power < config.MID_POWER_MAX_KW then
        return year >= config.MID_POWER_YEAR
    end

    return year >= config.OUTER_POWER_YEAR
end

---Tells whether the engine falls under Stage IV
-- @param integer year production year
-- @param any peakPowerKw peak power (kW)
-- @return boolean isStageIV true under Stage IV
function RMS_Exhaust.getIsStageIV(year, peakPowerKw)
    local config = RMS_Config.EXHAUST.STAGE_IV
    local power = getNumber(peakPowerKw, 0, 0)
    if power < config.MIN_POWER_KW or power > config.MAX_POWER_KW then
        return false
    end

    return year >= (power >= config.HIGH_POWER_MIN_KW and config.HIGH_POWER_YEAR or config.MID_POWER_YEAR)
end

---Builds wet stacking up at idle and burns it off under load
-- @param table input level, diesel, idle time and state, load, step and engine temperature of a running engine
-- @return float level wet stacking, 0 to 1
function RMS_Exhaust.calculateWetStackingLevel(input)
    local currentLevel = input.currentLevel
    if not input.isDiesel then
        return 0
    end

    local fuelConfig = RMS_Config.CORE.FUEL_FACTOR_DATA
    local idleTimer = input.idleTimer
    local load = getNumber(input.load, 0, 0, 1.5)
    local dt = input.dt
    local coldTemperature = RMS_Config.CORE.ENGINE_FACTOR_DATA.COLD_MOTOR_TEMP_THRESHOLD
    local operatingTemperature = RMS_Config.THERMAL.PID_TARGET_TEMP
    local engineTemperature = input.engineTemperature

    if input.isIdle then
        if idleTimer < fuelConfig.IDLE_DEPOSIT_FACTOR_TIMER_THRESHOLD then
            return currentLevel
        end

        local coldRisk = 1 - getRamp(engineTemperature, coldTemperature, operatingTemperature)
        local coldMultiplier = 1 + coldRisk
        local idleStep = dt / 1000
        local threshold = fuelConfig.IDLE_DEPOSIT_FACTOR_TIMER_THRESHOLD
        local buildupDuration = fuelConfig.IDLE_DEPOSIT_FACTOR_MAX_TIMER - threshold
        local previousIdleTimer = math.max(idleTimer - idleStep, 0)
        local buildupStart = math.max(previousIdleTimer, threshold)
        local buildupSeconds = math.max(idleTimer - buildupStart, 0)
        local buildup = (buildupSeconds / buildupDuration) * coldMultiplier

        return clamp(currentLevel + buildup, 0, 1)
    end

    local loadFactor = getRamp(load, fuelConfig.IDLE_DEPOSIT_LOAD_THRESHOLD, 1)
    local temperatureFactor = getRamp(engineTemperature, coldTemperature, operatingTemperature)
    local cleanupDuration = fuelConfig.IDLE_DEPOSIT_FACTOR_MAX_TIMER - fuelConfig.IDLE_DEPOSIT_FACTOR_TIMER_THRESHOLD
    local cleanup = (dt / 1000) / cleanupDuration * loadFactor * temperatureFactor

    return clamp(currentLevel - cleanup, 0, 1)
end

---Returns the soot of the particulate filter, the regeneration time and whether it regenerates
-- @param table input level, ash, Stage V, blocking, load, step, coolant temperature and regeneration time of a running engine
-- @return float level soot level, 1 being the load that calls a regeneration
-- @return float regenerationMs time of the regeneration under way (ms)
-- @return boolean isRegenerating true while it regenerates
function RMS_Exhaust.calculateParticulateFilterLoad(input)
    local config = RMS_Config.EXHAUST.PARTICULATE_FILTER
    if not input.isStageV then
        return 0, 0, false
    end

    local level = input.currentLevel
    if input.isBlocked or level >= config.SERVICE_LEVEL then
        return config.SERVICE_LEVEL, 0, false
    end

    local dt = input.dt
    if level >= 1 and input.coolantTemperature >= config.REGENERATION_COOLANT then
        local regenerationMs = input.regenerationMs + dt
        if regenerationMs >= config.REGENERATION_MS then
            -- the ash stays: the filter fills again sooner
            return input.ash, 0, false
        end
        return level, regenerationMs, true
    end

    local load = getNumber(input.load, 0, 0, 1)
    local hours = dt / (60 * 60 * 1000)
    level = level + (1 - load / config.PASSIVE_LOAD) / config.FILL_HOURS * hours

    return clamp(level, 0, config.SERVICE_LEVEL), 0, false
end

---Returns the filter ash, 1 calling a cleaning, and its oil part
-- @param table input ash, oil ash, Stage V, step and share of suited oil of a running engine
-- @return float ash ash
-- @return float oilAsh ash of the oil
function RMS_Exhaust.calculateParticulateFilterAsh(input)
    local config = RMS_Config.EXHAUST.PARTICULATE_FILTER
    local ash, oilAsh = input.ash, input.oilAsh
    if not input.isStageV then
        return ash, oilAsh
    end

    local C = RMS_Config.CORE
    local workHours = input.dt / (60 * 60 * 1000) * C.BASE_SYSTEMS_WEAR * C.MACHINE_LIFE_HOURS
    local base = workHours / config.ASH_CLEANING_HOURS
    local extra = base * (1 - input.suitedShare) * (config.UNSUITED_OIL_ASH - 1)

    return math.min(ash + base + extra, 1), math.min(oilAsh + extra, 1)
end

---Returns the target soot, oil and unburnt fractions of the engine
-- @param table input engine, load, boost, clogging, service, temperature, preheat and effects
-- @return table targets era factor, Stage V, boost deficit, soot, oil and unburnt
function RMS_Exhaust.calculateTargets(input)
    local config = RMS_Config.EXHAUST
    local sootConfig = config.SOOT
    local oilConfig = config.OIL
    local unburntConfig = config.UNBURNT
    local load = input.load
    local eraFactor = RMS_Exhaust.getEraFactor(input.year)
    local isStageV = RMS_Exhaust.getIsStageV(input.year, input.peakPowerKw)
    local wetStackingLevel = input.wetStackingLevel

    local fuelDelivery = lerp(sootConfig.FUEL_IDLE_SHARE, 1, clamp(load, 0, 1))

    local sootContinuous = getRamp(load, sootConfig.LOAD_THRESHOLD, sootConfig.LOAD_FULL) * sootConfig.LOAD_MAX
    sootContinuous = sootContinuous + wetStackingLevel * sootConfig.WET_STACKING_MAX * fuelDelivery

    local boostDeficit = 0
    if input.hasTurbo then
        boostDeficit = clamp(load - input.boost, 0, 1)
        sootContinuous = sootContinuous
            + getRamp(boostDeficit, sootConfig.BOOST_DEFICIT_THRESHOLD, sootConfig.BOOST_DEFICIT_FULL) * sootConfig.TRANSIENT_MAX
    end

    local clogging = input.airFilterClogging
    local cloggingCurve = clogging * clogging
    if clogging > sootConfig.AIR_FILTER_KNEE then
        cloggingCurve = cloggingCurve + (clogging - sootConfig.AIR_FILTER_KNEE)
    end
    sootContinuous = sootContinuous + math.min(cloggingCurve, 1) * sootConfig.AIR_FILTER_MAX * fuelDelivery

    local serviceLoss = 1 - input.serviceLevel
    sootContinuous = sootContinuous
        + getRamp(serviceLoss, sootConfig.SERVICE_THRESHOLD, 1) * sootConfig.SERVICE_MAX * fuelDelivery

    local breakdownFactor = math.max(eraFactor, config.ERA_BREAKDOWN_FLOOR)
    local sootBreakdown = input.sootEffect * sootConfig.BREAKDOWN_MAX

    local sootProfileFactor = 1
    if input.isMethane then
        sootProfileFactor = sootProfileFactor * config.METHANE_SOOT_FACTOR
    end
    if input.hasDEF then
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

    local oilBreakdown = input.oilEffect * oilConfig.BREAKDOWN_MAX
    if load <= oilConfig.IDLE_LOAD_THRESHOLD then
        oilBreakdown = oilBreakdown * oilConfig.IDLE_BOOST
    end
    local oil = clamp(oilBreakdown * breakdownFactor, 0, 1)

    local cold = 1 - getRamp(input.engineTemperature, unburntConfig.COLD_FULL_C, unburntConfig.COLD_THRESHOLD_C)
    local unburntContinuous = cold * unburntConfig.COLD_MAX
    if input.isStarting then
        unburntContinuous = unburntContinuous * unburntConfig.CRANKING_BOOST
    end
    unburntContinuous = unburntContinuous + (input.preheatSeverity / 4) * cold * unburntConfig.PREHEAT_FAULT_MAX
    local unburntBreakdown = input.unburntEffect * unburntConfig.BREAKDOWN_MAX
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

---Returns the value of an effect between 0 and 1
-- @param table spec RMS specialization of the vehicle
-- @param string effectId effect
-- @return float intensity value, 0 without the effect
local function getEffectIntensity(spec, effectId)
    local effect = spec.activeEffects[effectId]
    return effect ~= nil and effect.value or 0
end

---Returns a value eased toward its target, rising and falling at their own pace
-- @param float current value now
-- @param float target target
-- @param float dt time since the last frame (ms)
-- @param float? riseTau pace of a rise (ms), the default when nil
-- @param float? fallTau pace of a fall (ms), the default when nil
-- @return float value eased value
local function getSmoothed(current, target, dt, riseTau, fallTau)
    local tau = target > current and (riseTau or RMS_Config.EXHAUST.RISE_TAU)
        or (fallTau or RMS_Config.EXHAUST.FALL_TAU)
    local alpha = math.min(dt / (tau + dt), 1)

    return current + alpha * (target - current)
end

---Returns the tint of the smoke by its soot, oil and unburnt fuel
-- @param float soot soot
-- @param float oil oil
-- @param float unburnt unburnt fuel
-- @return float red red
-- @return float green green
-- @return float blue blue
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

---Returns the opacity of the smoke above its floor
-- @param float soot soot
-- @param float oil oil
-- @param float unburnt unburnt fuel
-- @return float opacity opacity, 0 to 1
local function getOpacity(soot, oil, unburnt)
    local config = RMS_Config.EXHAUST
    local opticalDepth = config.K_SOOT * soot + config.K_OIL * oil + config.K_UNBURNT * unburnt
    local raw = 1 - math.exp(-opticalDepth)
    local floor = config.OPACITY_FLOOR

    return math.max(raw - floor, 0) / (1 - floor)
end

---Returns the boost of a turbocharged engine
-- @param table vehicle vehicle
-- @param table state smoke state
-- @return float boost boost, 0 to 1
local function getBoost(vehicle, state)
    if not state.hasTurbo then
        return 0
    end

    return getNumber(vehicle:getMotor().lastTurboScale, 0, 0, 1)
end

---Returns the engine speed against its maximum
-- @param table vehicle vehicle
-- @return float scale engine speed share
local function getRpmScale(vehicle)
    local maxRpm = vehicle:getMotor():getMaxRpm()
    if maxRpm <= 0 then
        return 0
    end

    return vehicle:getMotorRpmReal() / maxRpm
end

---Returns the gas flow against the full flow, boost counted
-- @param table vehicle vehicle
-- @param table state smoke state
-- @return float flow flow, 0 to 1
local function getFlow(vehicle, state)
    local gain = RMS_Config.EXHAUST.FLOW_BOOST_GAIN

    return clamp(getRpmScale(vehicle) * (1 + gain * getBoost(vehicle, state)) / (1 + gain), 0, 1)
end

---Tells whether the engine starts or runs
-- @param table vehicle vehicle
-- @return boolean isRendered true while it starts or runs
local function getIsSmokeRendered(vehicle)
    local motorState = vehicle:getMotorState()

    return motorState == MotorState.STARTING or motorState == MotorState.ON
end

---Returns the peak power of the engine
-- @param table vehicle vehicle
-- @return float power peak power (kW)
local function getPeakPowerKw(vehicle)
    return getNumber(vehicle:getMotor().peakMotorPower, 0, 0)
end

---Tells whether a Stage V diesel carries a particulate filter
-- @param table vehicle vehicle
-- @return boolean hasFilter true for such a diesel
function RMS_Exhaust.getHasParticulateFilter(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    return spec.isDieselVehicle and RMS_Exhaust.getIsStageV(spec.year, getPeakPowerKw(vehicle))
end

---Resolves once the turbo, the AdBlue and the methane of the engine
-- @param table vehicle vehicle
-- @param table state smoke state
local function resolveEmissionProfile(vehicle, state)
    if state.profileResolved then
        return
    end

    state.hasTurbo = getPeakPowerKw(vehicle) >= RMS_Config.CORE.TURBO_MIN_POWER_KW

    local consumers = vehicle.spec_motorized.consumersByFillTypeName
    state.hasDEF = consumers["DEF"] ~= nil
    state.isMethane = consumers["METHANE"] ~= nil
    state.profileResolved = true
end

local WET_WEATHER_TYPES = {"RAIN", "SNOW", "HAIL"}

---Returns the wetness of the air by the weather and the ground
-- @return float wetness wetness, 0 to 1
local function getAirWetness()
    for _, name in ipairs(WET_WEATHER_TYPES) do
        if RMS_Main.currentWeather == WeatherType[name] then
            return 1
        end
    end

    return getNumber(g_currentMission.environment.weather:getGroundWetness(), 0, 0, 1) * 0.5
end

---Returns the optical depth of the water vapour condensing in cold air
-- @param table input ambient temperature, wetness, load and engine temperature
-- @return float tau optical depth of the vapour
-- @return float coldness share of the full condensation the ambient temperature allows
function RMS_Exhaust.calculateVapourTarget(input)
    local config = RMS_Config.EXHAUST.VAPOUR
    local ambient = getNumber(input.ambientTemperature, 15, -80, 80)
    local coldness = 1 - getRamp(ambient, config.FULL_C, config.START_C)
    if coldness <= 0 then
        return 0, 0
    end

    local humidity = clamp(config.HUMIDITY_BASE + config.HUMIDITY_WEATHER * input.wetness, 0, 1)
    local fuel = lerp(config.IDLE_SHARE, 1, clamp(input.load, 0, 1))
    local coldTemperature = RMS_Config.CORE.ENGINE_FACTOR_DATA.COLD_MOTOR_TEMP_THRESHOLD
    local operatingTemperature = RMS_Config.THERMAL.PID_TARGET_TEMP
    local coldEngine = 1 - getRamp(input.engineTemperature, coldTemperature, operatingTemperature)

    return config.K * coldness * humidity * fuel * (1 + config.COLD_ENGINE_BOOST * coldEngine), coldness
end

---Returns the temperature of the gas entering the exhaust line
-- @param float load share of the stock torque, above 1 on a remapped engine
-- @param float ambientC ambient temperature (deg C)
-- @param boolean isRegenerating true while the particulate filter regenerates
-- @return float temperature temperature (deg C)
function RMS_Exhaust.getLineInletTemperature(load, ambientC, isRegenerating)
    local config = RMS_Config.EXHAUST.EGT
    local temperature = ambientC + lerp(config.RISE_IDLE_K, config.RISE_FULL_K, math.min(load, 1))
        + config.OVERLOAD_K * math.max(load - 1, 0)
    if isRegenerating then
        temperature = math.max(temperature, config.REGENERATION_C)
    end

    return temperature
end

---Returns the temperature of the exhaust line, which the gas leaves at
-- @param table input flow as a share of the full gas flow, stoppedDt in world time
-- @return float temperature temperature (deg C)
function RMS_Exhaust.calculateLineTemperature(input)
    local config = RMS_Config.EXHAUST.EGT
    local ambient = input.ambientTemperature
    local current = input.currentTemperature
    if input.isMotorStarted then
        local inlet = RMS_Exhaust.getLineInletTemperature(input.load, ambient, input.isRegenerating)

        return inlet + (current - inlet) * math.exp(-input.dt * input.flow / config.LINE_TAU)
    end

    return ambient + (current - ambient) * math.exp(-input.stoppedDt / config.LINE_COOLING_TAU)
end

---Returns the eddy velocity of the air at a point
-- @param float x x of the point
-- @param float y y of the point
-- @param float z z of the point
-- @param float timeSeconds time (s)
-- @param float amplitude amplitude (m/s)
-- @return float velocityX x of the velocity (m/s)
-- @return float velocityY y of the velocity (m/s)
-- @return float velocityZ z of the velocity (m/s)
function RMS_Exhaust.getTurbulenceVelocity(x, y, z, timeSeconds, amplitude)
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

    local scale = amplitude / weights

    return velocityX * scale, velocityY * scale * config.VERTICAL_SHARE, velocityZ * scale
end

---Returns the sprite size of a puff at its age
-- @param table puff puff
-- @return float size size (m)
local function getPuffSize(puff)
    local age = clamp(puff.age, 0, puff.lifespan)

    return math.max(puff.sizeStart + puff.sizeGain * age, 0)
end

---Returns the width the shared plume schedule gives a puff at its age
-- @param table puff puff
-- @return float size width (m)
local function getScheduleSize(puff)
    local schedule = puff.spacing
    local age = clamp(puff.age, 0, puff.lifespan)

    return math.max(schedule.sizeStart + schedule.sizeGain * age, 0)
end

---Returns the width a puff spreads to at its age
-- @param table puff puff
-- @return float size width (m)
local function getSpreadSize(puff)
    local profile = puff.spacing.jetProfile
    if puff.spriteRatio == nil then
        return getPuffSize(puff)
    end

    local age = clamp(puff.age, 0, puff.lifespan)
    local position = age / profile.stepMs + 1
    local index = math.min(math.floor(position), #profile.widths - 1)
    local widths = profile.widths
    local width = widths[index] + (widths[index + 1] - widths[index]) * math.min(position - index, 1)

    return math.max(width * puff.spriteRatio, getPuffSize(puff))
end

---Returns the bounding-sphere radius of one camera-facing puff
-- @param table puff puff
-- @return float radius radius (m)
function RMS_Exhaust.getPuffRadius(puff)
    return getPuffSize(puff) * RMS_Config.EXHAUST.PUFF.RADIUS_SHARE
end

---Returns the optical depths of the smoke and the vapour of one puff
-- @param table puff puff
-- @return float smoke optical depth of the smoke
-- @return float vapour optical depth of the vapour
function RMS_Exhaust.getPuffOpticalDepths(puff)
    local sizeStart = math.max(puff.sizeStart, 0.001)
    local dilution = (sizeStart / math.max(getSpreadSize(puff), sizeStart)) ^ 2 * puff.weight
    local smoke = puff.tau * dilution
    local vapour = puff.tauVapour * dilution
    if vapour > 0 then
        vapour = vapour * math.exp(-puff.age / puff.evaporationMs)
    end

    return smoke, vapour
end

---Returns the alpha a puff is drawn with
-- @param table puff puff
-- @return float alpha alpha, 0 to 1
function RMS_Exhaust.getPuffRenderAlpha(puff)
    local puffConfig = RMS_Config.EXHAUST.PUFF
    local smoke, vapour = RMS_Exhaust.getPuffOpticalDepths(puff)
    local alpha = clamp((1 - math.exp(-(smoke + vapour))) * puffConfig.SPRITE_ALPHA_GAIN, 0, 1)
    if puff.fadesOut then
        alpha = alpha * clamp((puff.lifespan - puff.age) / puffConfig.FADE_OUT_MS, 0, 1)
    end
    local contactRadius = puff.contactRadius or 0
    local surfaceTravel = puff.surfaceTravel
    if contactRadius > 0 and surfaceTravel > 0 then
        alpha = alpha * ((contactRadius / (contactRadius + surfaceTravel)) ^ 0.57)
    end

    return alpha
end

---Returns the angle gas hotter than the air bends light by
-- @param float rise temperature of the gas over the air (K)
-- @param float ambientC ambient temperature (deg C)
-- @return float angle angle (rad)
function RMS_Exhaust.getHeatDeflection(rise, ambientC)
    local config = RMS_Config.EXHAUST.HEAT

    -- the refractivity of a gas follows its density
    return config.PATH_FACTOR * config.AIR_REFRACTIVITY * rise / (ambientC + 273.15 + rise)
end

---Returns the angle the gas of a puff bends light by
-- @param table puff heat puff
-- @return float angle angle (rad)
function RMS_Exhaust.getPuffHeatDeflection(puff)
    local rise = puff.deltaT * (puff.jetStart / puff.width) ^ RMS_Config.EXHAUST.EGT.DILUTION_EXPONENT

    return RMS_Exhaust.getHeatDeflection(rise, puff.ambientC)
end

---Returns the colour a puff is drawn with
-- @param table puff puff
-- @return float red red
-- @return float green green
-- @return float blue blue
function RMS_Exhaust.getPuffRenderColour(puff)
    local smoke, vapour = RMS_Exhaust.getPuffOpticalDepths(puff)
    if vapour <= 0 then
        return puff.red, puff.green, puff.blue
    end

    local tint = RMS_Config.EXHAUST.VAPOUR_TINT
    local share = vapour / (smoke + vapour)

    return lerp(puff.red, tint[1], share), lerp(puff.green, tint[2], share), lerp(puff.blue, tint[3], share)
end

---Projects an impacting puff onto a surface, keeping its tangential momentum
-- @param table puff puff
-- @param table hit hit of the surface
-- @param float radius radius of the puff (m)
-- @param float? pushLimit maximum surface displacement (m), nil unbounded
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

---Returns the width of a jet after a step and the distance it travelled
-- @param float width width (m)
-- @param float relativeSpeed speed against the air (m/s)
-- @param float stepSeconds step (s)
-- @return float width width (m)
-- @return float distance distance (m)
local function getJetStep(width, relativeSpeed, stepSeconds)
    local spread = RMS_Config.EXHAUST.PUFF.JET_SPREAD
    local widened = math.sqrt(width * width + 2 * spread * relativeSpeed * width * stepSeconds)

    return widened, (widened - width) / spread
end

---Advances one puff through entrainment, wind, eddies, buoyancy and contacts
-- @param table puff puff
-- @param float dt time to advance (ms)
-- @param table environment wind, air temperature, eddies and contact tests
function RMS_Exhaust.advancePuff(puff, dt, environment)
    local puffConfig = RMS_Config.EXHAUST.PUFF
    local turbulenceConfig = RMS_Config.EXHAUST.TURBULENCE
    local dilutionExponent = RMS_Config.EXHAUST.EGT.DILUTION_EXPONENT
    local ambientKelvin = getNumber(environment.ambientC, 15, -80, 80) + 273.15
    local windSpeed = environment.windSpeed
    local remainingMs = dt

    while remainingMs > 0 and puff.age < puff.lifespan do
        local stepMs = math.min(remainingMs, 50)
        local stepSeconds = stepMs / 1000
        remainingMs = remainingMs - stepMs
        puff.age = math.min(puff.age + stepMs, puff.lifespan)
        local radius = RMS_Exhaust.getPuffRadius(puff)

        if puff.contact ~= nil and not environment.hasContact(puff, puff.contact, radius) then
            puff.contact = nil
        end

        local shelterTarget = puff.shelterTarget
        local shelter = puff.shelter
        shelter = shelter + (shelterTarget - shelter) * math.min(stepMs / (puffConfig.SHELTER_TAU + stepMs), 1)
        puff.shelter = shelter
        local windScale = lerp(1, puffConfig.SHELTER_WIND_SHARE, shelter)

        local amplitude = turbulenceConfig.BASE + turbulenceConfig.PER_WIND * windSpeed * windScale
        local eddyX, eddyY, eddyZ = environment.getTurbulence(puff.x, puff.y, puff.z)
        local airX = environment.windX * windScale + eddyX * amplitude
        local airY = environment.windY * windScale + eddyY * amplitude
        local airZ = environment.windZ * windScale + eddyZ * amplitude

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

        local relativeX, relativeY, relativeZ = puff.vx - airX, puff.vy - airY, puff.vz - airZ
        local relativeSpeed = getVectorLength(relativeX, relativeY, relativeZ)
        local crossSpeed = 0
        local puffSpeed = getVectorLength(puff.vx, puff.vy, puff.vz)
        if puffSpeed > 0.001 then
            local airAlong = dotProduct(airX, airY, airZ, puff.vx, puff.vy, puff.vz) / puffSpeed
            local airSpeed = getVectorLength(airX, airY, airZ)
            crossSpeed = math.sqrt(math.max(airSpeed * airSpeed - airAlong * airAlong, 0))
        end
        local width = puff.width
        local jetWidth, relativeTravel = getJetStep(width, relativeSpeed, stepSeconds)
        local widened = jetWidth + (puffConfig.JET_CROSS_SPREAD * crossSpeed
            + puff.ambientGrowth) * stepSeconds
        puff.width = widened
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

        local deltaT0 = puff.deltaT
        if deltaT0 > 0 then
            local deltaT = deltaT0 * (puff.jetStart / widened) ^ dilutionExponent
            local lift = 9.81 * deltaT / (ambientKelvin + deltaT) * stepSeconds
            puff.vy = puff.vy + lift
            travelY = travelY + lift * stepSeconds * 0.5
        end

        local previousX, previousY, previousZ = puff.x, puff.y, puff.z
        local nextX = puff.x + travelX
        local nextY = puff.y + travelY
        local nextZ = puff.z + travelZ
        local hit = environment.trace(puff, puff.x, puff.y, puff.z, nextX, nextY, nextZ, radius)

        local pushLimit = puffConfig.SURFACE_PUSH_SPEED * stepSeconds
        if hit ~= nil then
            RMS_Exhaust.resolvePuffImpact(puff, hit, radius, pushLimit)
            local remainingShare = 1 - hit.fraction
            nextX = puff.x + puff.vx * stepSeconds * remainingShare
            nextY = puff.y + puff.vy * stepSeconds * remainingShare
            nextZ = puff.z + puff.vz * stepSeconds * remainingShare
        end

        if puff.contact == nil and puff.vy > 0 and radius >= puffConfig.ROOF_PROBE_MIN_RADIUS then
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
            puff.surfaceTravel = puff.surfaceTravel
                + math.sqrt(tangentX * tangentX + tangentY * tangentY + tangentZ * tangentZ)
        end

        puff.x, puff.y, puff.z = nextX, nextY, nextZ
    end
end

---Lays out the widths and speeds of the jet over its life
-- @param table emission emission of the plume
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

---Returns a series of the jet profile at an age
-- @param table profile jet profile
-- @param table series widths or speeds of the profile
-- @param float ageMs age (ms)
-- @return float value value at the age
local function sampleJetProfile(profile, series, ageMs)
    local position = math.max(ageMs, 0) / profile.stepMs + 1
    local index = math.min(math.floor(position), #series - 1)
    local share = math.min(position - index, 1)

    return series[index] + (series[index + 1] - series[index]) * share
end

---Returns the width of the jet at an age
-- @param table emission emission of the plume
-- @param float ageMs age (ms)
-- @return float width width (m)
local function getJetWidth(emission, ageMs)
    return sampleJetProfile(emission.jetProfile, emission.jetProfile.widths, ageMs)
end

---Returns the spacing of puffs of a size along the jet
-- @param table emission emission of the plume
-- @param float size size of the puffs (m)
-- @return float spacing spacing (m)
local function getPuffSpacing(emission, size)
    local ageMs = math.max(size - emission.sizeStart, 0) / math.max(emission.sizeGain, 0.000001)
    local speed = sampleJetProfile(emission.jetProfile, emission.jetProfile.speeds, ageMs)

    return math.max(speed, emission.dispersalSpeed) / emission.rate
end

---Returns the optical depth of the plume where its puffs reach a size
-- @param table emission emission of the plume
-- @param float size size of the puffs (m)
-- @return float tau optical depth
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

---Returns the share of the plume one puff stands for
-- @param table puff puff
-- @param float size width the shared plume schedule gives the puff at its age, in metres
-- @return float weight weight, 0 for a puff its level retires
function RMS_Exhaust.getThinningWeight(puff, size)
    local excess = size / getPuffSpacing(puff.spacing, size) / RMS_Config.EXHAUST.PUFF.OVERLAP_TARGET
    if excess <= 1 then
        return 1
    end

    local stage = math.log(excess) / math.log(2)
    local level = puff.level
    local levelMax = RMS_Config.EXHAUST.PUFF.THIN_LEVEL_MAX
    if level >= levelMax then
        return 2 ^ math.min(stage, levelMax)
    elseif stage <= level then
        return 2 ^ stage
    elseif stage < level + 1 then
        return 2 ^ (level + 1) - 2 ^ stage
    end

    return 0
end

---Returns the age the plume stays visible to
-- @param table emission emission of the plume
-- @return float lifespan age (ms)
local function getVisibleLifespan(emission)
    local puffConfig = RMS_Config.EXHAUST.PUFF
    local visible = puffConfig.TAU_VISIBLE
    local low = emission.sizeStart
    local high = math.max(puffConfig.SIZE_MAX, low)
    local size = high

    if getPlumeOpticalDepth(emission, low) < visible then
        size = low
    elseif getPlumeOpticalDepth(emission, high) < visible then
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

---Sets the age each thinning level retires its puffs at
-- @param table emission emission of the plume
-- @param table lifespans retire age by level (ms)
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

---Loads the emitter shape and the sprites of the plume once, testing their controls
-- @return boolean isValid true when the plume can be drawn
local function loadPlumeSources()
    if RMS_Exhaust.plumeSources ~= nil then
        return RMS_Exhaust.plumeSources.isValid
    end

    local config = RMS_Config.EXHAUST
    local sources = { isValid = false }
    RMS_Exhaust.plumeSources = sources

    local shapeRoot = loadI3DFile(RMS_Exhaust.modDirectory .. config.PLUME_EMIT_SHAPE, false, false, false)
    if shapeRoot == 0 then
        return false
    end

    local emitShape = getChildAt(shapeRoot, 0)
    if emitShape == 0 then
        return false
    end

    link(getRootNode(), emitShape)
    sources.emitShape = emitShape

    local file = config.PLUME_DIRECTORY .. config.PLUME_SPRITES .. "/" .. config.PLUME_FILE
    local root = loadI3DFile(RMS_Exhaust.modDirectory .. file, false, false, false)
    if root == 0 then
        return false
    end

    local node = getChildAt(root, 0)
    if node == 0 then
        return false
    end

    link(getRootNode(), node)
    setVisibility(node, false)
    local geometry = getGeometry(node)
    if geometry == 0 then
        return false
    end

    sources.assetLifespan = getParticleSystemLifespan(geometry)
    sources.assetSize = getParticleSystemSpriteScaleX(geometry)
    sources.assetSizeGain = getParticleSystemSpriteScaleXGain(geometry)

    -- Verify particle controls by reading back the written values
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

    sources.flushMs = math.max(config.PUFF.LIFE_MAX, sources.assetLifespan) + 1000

    sources.puffNode = node
    sources.isValid = true

    -- heat sprites must take the size and lifespan of the gas
    if sources.canSetLifespan and sources.canSetSize then
        local heatRoot = loadI3DFile(RMS_Exhaust.modDirectory .. config.PLUME_DIRECTORY .. config.PLUME_SPRITES .. "/" .. config.PLUME_HEAT_FILE,
            false, false, false)
        local heatNode = getChildAt(heatRoot, 0)
        link(getRootNode(), heatNode)
        setVisibility(heatNode, false)
        sources.heatNode = heatNode
    end

    return true
end

---Shows or hides the game's own exhaust
-- @param table vehicle vehicle
-- @param table effects exhaust effects of the game
-- @param boolean isNative true to show it
local function setNativeExhaustState(vehicle, effects, isNative)
    local isDrawn = isNative and getIsSmokeRendered(vehicle)
    local motorizedSpec = vehicle.spec_motorized
    if motorizedSpec.exhaustParticleSystems ~= nil then
        for _, particleSystem in pairs(motorizedSpec.exhaustParticleSystems) do
            ParticleUtil.setEmittingState(particleSystem, isDrawn)
        end
    end

    if motorizedSpec.effects ~= nil then
        if isDrawn then
            g_effectManager:startEffects(motorizedSpec.effects)
        else
            g_effectManager:stopEffects(motorizedSpec.effects)
        end
    end

    for _, effect in pairs(effects) do
        setVisibility(effect.effectNode, isDrawn)
    end
end

---Keeps the game's own exhaust off
-- @param table vehicle vehicle
local function enforceNativeSilence(vehicle)
    local motorizedSpec = vehicle.spec_motorized
    if motorizedSpec.exhaustParticleSystems ~= nil then
        for _, particleSystem in pairs(motorizedSpec.exhaustParticleSystems) do
            if particleSystem.isEmitting ~= false then
                ParticleUtil.setEmittingState(particleSystem, false)
            end
        end
    end

    if motorizedSpec.effects ~= nil then
        g_effectManager:stopEffects(motorizedSpec.effects)
    end

    for _, effect in pairs(motorizedSpec.exhaustEffects) do
        if getVisibility(effect.effectNode) then
            setVisibility(effect.effectNode, false)
        end
    end
end

---Logs the exhaust sources the game draws beside the plume
-- @param table vehicle vehicle
-- @param table effects exhaust effects of the game
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
            particleCount = particleCount + 1
            local node = particleSystem.emitterShape or particleSystem.shape
            if node ~= nil and node ~= 0 then
                local _, y, _ = getWorldTranslation(node)
                table.insert(offsets, string.format("%+.2f m", y - outletY))
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
            vehicle:getFullName(), particleCount,
            #offsets > 0 and table.concat(offsets, ", ") or "-", effectCount)
    end
end

---Hands the exhaust to the game or to the plume
-- @param table vehicle vehicle
-- @param table state smoke state
-- @param boolean isNative true to hand it to the game
local function setNativeOwnership(vehicle, state, isNative)
    if state.isNativeOwned == isNative then
        return
    end

    setNativeExhaustState(vehicle, vehicle.spec_motorized.exhaustEffects, isNative)
    state.isNativeOwned = isNative
end

---Returns the collision mask puffs stop against
-- @return integer mask collision mask
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
        mask = bit32.bor(mask, CollisionFlag[name])
    end

    RMS_Exhaust.puffCollisionMask = mask

    return mask
end

---Receives the closest solid hit of the synchronous puff raycast
-- @param entityId transformId object hit
-- @param float x x of the hit
-- @param float y y of the hit
-- @param float z z of the hit
-- @param float distance distance (m)
-- @param float nx x of the normal
-- @param float ny y of the normal
-- @param float nz z of the normal
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

---Tells whether a hit object belongs to the vehicle
-- @param table vehicle vehicle
-- @param table? object object hit
-- @return boolean isOwn true when it belongs to it
local function getIsOwnVehicleHit(vehicle, object)
    if object == nil then
        return false
    end
    if object == vehicle then
        return true
    end

    return object.rootVehicle == vehicle.rootVehicle
end

---Returns the first solid hit of a ray, triggers and the vehicle at the outlet passed through
-- @param table vehicle vehicle
-- @param table puff puff
-- @param float originX x of the origin
-- @param float originY y of the origin
-- @param float originZ z of the origin
-- @param float directionX x of the direction
-- @param float directionY y of the direction
-- @param float directionZ z of the direction
-- @param float distance length of the ray (m)
-- @return table? hit hit, nil without one
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

        -- A zero-distance hit starts inside the vehicle collider
        if travelled == 0 and hit.distance <= RMS_Config.EXHAUST.PUFF.INSIDE_HIT_DISTANCE then
            return nil
        end

        local object = g_currentMission:getNodeObject(hit.objectId)
        local isTrigger = getHasTrigger(hit.objectId)
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

---Returns the hit of a puff moving between two points
-- @param table vehicle vehicle
-- @param table puff puff
-- @param float fromX x of the start
-- @param float fromY y of the start
-- @param float fromZ z of the start
-- @param float toX x of the end
-- @param float toY y of the end
-- @param float toZ z of the end
-- @param float radius radius of the puff (m)
-- @return table? hit hit, nil without one
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

---Returns the hit above a rising puff
-- @param table vehicle vehicle
-- @param table puff puff
-- @param float x x of the puff
-- @param float y y of the puff
-- @param float z z of the puff
-- @param float radius radius of the puff (m)
-- @return table? hit hit, nil without one
local function probePuffAbove(vehicle, puff, x, y, z, radius)
    local hit = castPuffRay(vehicle, puff, x, y, z, 0, 1, 0, radius)
    if hit == nil then
        return nil
    end

    hit.dx, hit.dy, hit.dz = 0, 1, 0

    return hit
end

---Tells whether a puff still touches its surface, updating the contact
-- @param table vehicle vehicle
-- @param table puff puff
-- @param table contact contact of the puff
-- @param float radius radius of the puff (m)
-- @return boolean hasContact true while it touches
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

---Returns the wind velocity
-- @return float windX x of the wind (m/s)
-- @return float windY y of the wind, 0
-- @return float windZ z of the wind (m/s)
local function getWindVelocity()
    local updater = g_currentMission.environment.weather.windUpdater
    local velocity = getNumber(updater.currentVelocity, 0, 0)

    return getNumber(updater.currentDirX, 0) * velocity, 0,
        getNumber(updater.currentDirZ, 0) * velocity
end

---Returns the collision mask a lee is searched against
-- @return integer mask collision mask
local function getLeeCollisionMask()
    if RMS_Exhaust.leeCollisionMask ~= nil then
        return RMS_Exhaust.leeCollisionMask
    end

    local mask = 0
    for _, name in ipairs({"STATIC_OBJECT", "BUILDING", "TREE"}) do
        mask = bit32.bor(mask, CollisionFlag[name])
    end

    RMS_Exhaust.leeCollisionMask = mask

    return mask
end

---Receives the closest hit of a lee raycast
-- @param entityId transformId object hit
-- @param float x x of the hit
-- @param float y y of the hit
-- @param float z z of the hit
-- @param float distance distance (m)
function RMS_Exhaust:onLeeRaycast(transformId, x, y, z, distance)
    self.leeRaycastHit = {objectId = transformId, x = x, y = y, z = z, distance = distance}
end

---Returns the first solid hit of a lee ray, triggers passed through
-- @param float originX x of the origin
-- @param float originY y of the origin
-- @param float originZ z of the origin
-- @param float directionX x of the direction
-- @param float directionY y of the direction
-- @param float directionZ z of the direction
-- @param float distance length of the ray (m)
-- @return table? hit hit, nil without one
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

        if not getHasTrigger(hit.objectId) then
            hit.distance = travelled + hit.distance

            return hit
        end

        travelled = travelled + hit.distance + 0.01
    end

    return nil
end

---Finds the face sheltering the outlet from the wind, and its height
-- @param table state smoke state
-- @param float x x of the outlet
-- @param float y y of the outlet
-- @param float z z of the outlet
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

    local probeX, probeZ = face.x - directionX * 0.3, face.z - directionZ * 0.3
    local probeHeight = puffConfig.LEE_PROBE_HEIGHT
    local top = castLeeRay(probeX, y + probeHeight, probeZ, 0, -1, 0, probeHeight)
    local topY = top ~= nil and top.y or y
    local groundY = y - puffConfig.LEE_GROUND_FALLBACK
    local terrain = g_currentMission.terrainRootNode
    if terrain ~= nil then
        groundY = getTerrainHeightAtWorldPos(terrain, probeX, 0, probeZ)
    end

    lee.isValid = true
    lee.faceX, lee.faceZ = face.x, face.z
    lee.directionX, lee.directionZ = directionX, directionZ
    lee.topY = topY
    lee.height = math.max(topY - groundY, 0.5)
end

---Returns the shelter the lee of a face gives at a point
-- @param table lee lee of the outlet
-- @param float x x of the point
-- @param float y y of the point
-- @param float z z of the point
-- @return float shelter shelter, 0 to 1
local function getLeeShelter(lee, x, y, z)
    if not lee.isValid then
        return 0
    end

    local puffConfig = RMS_Config.EXHAUST.PUFF
    local downwind = (x - lee.faceX) * lee.directionX + (z - lee.faceZ) * lee.directionZ
    if downwind < 0 then
        return 0
    end

    local share = lerp(puffConfig.LEE_WIND_SHARE, 1,
        getRamp(downwind / lee.height, puffConfig.LEE_FULL_HEIGHTS, puffConfig.LEE_RECOVERY_HEIGHTS))
    share = lerp(share, 1, getRamp(y - lee.topY, 0, puffConfig.LEE_TOP_BLEND))

    return clamp((1 - share) / (1 - puffConfig.SHELTER_WIND_SHARE), 0, 1)
end

---Returns the shelter at a point: indoors, under the roof, or in a lee
-- @param table vehicle vehicle
-- @param float x x of the point
-- @param float y y of the point
-- @param float z z of the point
-- @param float pipeX x of the outlet
-- @param float pipeZ z of the outlet
-- @return float shelter shelter, 0 to 1
local function getShelterTarget(vehicle, x, y, z, pipeX, pipeZ)
    if g_currentMission.indoorMask:getIsIndoorAtWorldPosition(x, z) then
        return 1
    end

    local spec = vehicle.spec_RealisticMechanicalSystems
    if spec.isUnderRoof then
        local radius = RMS_Config.EXHAUST.PUFF.SHELTER_RADIUS
        local deltaX, deltaZ = x - pipeX, z - pipeZ
        if deltaX * deltaX + deltaZ * deltaZ <= radius * radius then
            return 1
        end
    end

    return getLeeShelter(spec.exhaustSmoke.lee, x, y, z)
end

---Returns the thinning level of a puff by its rank
-- @param integer rank rank of the puff
-- @return integer level thinning level
local function getThinningLevel(rank)
    local levelMax = RMS_Config.EXHAUST.PUFF.THIN_LEVEL_MAX
    local level = 0
    while rank > 0 and rank % 2 == 0 and level < levelMax do
        rank = rank / 2
        level = level + 1
    end

    return level
end

---Creates a puff slot, its emitter and its single particle sprite
-- @param boolean? isHeat true for a heat puff
-- @return table? slot slot, nil without geometry
local function createPuffSlot(isHeat)
    local config = RMS_Config.EXHAUST
    local sources = RMS_Exhaust.plumeSources
    -- heat puffs carry a far bounding sphere, never clipped on it
    local clipDistance = isHeat and 2 * config.HEAT.SORT_DISTANCE or config.PLUME_CLIP_DISTANCE
    local root = createTransformGroup("rmsManagedPuff")
    link(getRootNode(), root)

    local emitterShape = clone(sources.emitShape, true, false, true)
    link(root, emitterShape)
    setScale(emitterShape, 0.001, 0.001, 0.001)
    setClipDistance(emitterShape, clipDistance)

    local node = clone(isHeat and sources.heatNode or sources.puffNode, true, false, true)
    link(root, node)
    setVisibility(node, true)
    setClipDistance(node, clipDistance)

    local renderer = {}
    ParticleUtil.loadParticleSystemFromNode(node, renderer, false, false, true)
    ParticleUtil.setEmitterShape(renderer, emitterShape)
    ParticleUtil.setEmittingState(renderer, false)

    local geometry = getGeometry(renderer.shape)
    if geometry == 0 then
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

---Deletes the puff slots of a layer
-- @param table layer puff layer
local function deletePuffPool(layer)
    for _, slot in ipairs(layer.pool) do
        ParticleUtil.deleteParticleSystem(slot.renderer)
        delete(slot.root)
    end
    layer.pool = {}
    layer.freeSlots = {}
end

---Stops the emission of every plume
-- @param table state smoke state
local function stopPlumes(state)
    if state.plumes == nil then
        return
    end

    for _, plume in ipairs(state.plumes) do
        plume.isEmitting = false
        plume.emissionAccumulator = 0
    end
end

---Returns a puff layer, the plume holding its smoke puffs, plume.heat its heat puffs
-- @param table layer fields of the layer
-- @return table layer puff layer
local function newPuffLayer(layer)
    layer.pool = {}
    layer.freeSlots = {}
    layer.emissionAccumulator = 0
    layer.isEmitting = false
    layer.activePuffs = 0
    layer.nextRank = 0

    return layer
end

---Deletes the plumes and hands the exhaust back to the game
-- @param table vehicle vehicle
-- @param table state smoke state
local function deletePlumes(vehicle, state)
    if state.plumes == nil then
        return
    end

    for _, plume in ipairs(state.plumes) do
        deletePuffPool(plume)
        if plume.heat ~= nil then
            deletePuffPool(plume.heat)
        end
    end

    state.plumes = nil
    setNativeOwnership(vehicle, state, true)
end

---Creates a plume per exhaust outlet
-- @param table vehicle vehicle
-- @param table state smoke state
-- @param table effects exhaust effects of the game
local function createPlumes(vehicle, state, effects)
    if not loadPlumeSources() then
        return
    end

    local plumes = {}
    for _, effect in pairs(effects) do
        local plume = newPuffLayer({
            linkNode = effect.node,
            effect = effect,
            lastPipeX = nil,
            lastPipeY = nil,
            lastPipeZ = nil,
            pipeVelocityX = 0,
            pipeVelocityY = 0,
            pipeVelocityZ = 0
        })
        if RMS_Exhaust.plumeSources.heatNode ~= nil then
            -- outlet and eddy travel along the camera right and up axes (m)
            plume.heat = newPuffLayer({isHeat = true, outletX = 0, outletY = 0, scrollX = 0, scrollY = 0})
        end
        table.insert(plumes, plume)
    end

    state.plumes = plumes
    surveyNativeSources(vehicle, effects)
    setNativeOwnership(vehicle, state, false)
end

---Creates the plumes once
-- @param table vehicle vehicle
-- @param table state smoke state
-- @param table effects exhaust effects of the game
local function ensurePlumes(vehicle, state, effects)
    if state.plumes == nil then
        createPlumes(vehicle, state, effects)
    end
end

---Returns the outlet position and updates its velocity
-- @param table plume plume
-- @param float dt time since the last frame (ms)
-- @return float x x of the outlet
-- @return float y y of the outlet
-- @return float z z of the outlet
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

---Returns a free puff slot, a new one while the pool has room
-- @param table layer puff layer
-- @return table? slot slot, nil when the pool is full
local function getPuffSlot(layer)
    local freeCount = #layer.freeSlots
    if freeCount > 0 then
        local slot = layer.freeSlots[freeCount]
        layer.freeSlots[freeCount] = nil
        return slot
    end

    local poolMax = layer.isHeat and RMS_Config.EXHAUST.HEAT.POOL_MAX or RMS_Config.EXHAUST.PUFF.POOL_MAX
    if #layer.pool >= poolMax then
        return nil
    end

    local slot = createPuffSlot(layer.isHeat)
    if slot ~= nil then
        table.insert(layer.pool, slot)
    end

    return slot
end

---Draws a heat puff, its deflection on screen and its sort distance
-- @param table state smoke state
-- @param table heat heat layer
-- @param table slot slot of the puff
local function drawHeatPuff(state, heat, slot)
    local puff = slot.puff
    local shape = slot.renderer.shape
    setShaderParameterRecursive(shape, "heat", state.heatScreenPerRad * RMS_Exhaust.getPuffHeatDeflection(puff), heat.scrollX, heat.scrollY, 0,
        false)
    setShaderParameterRecursive(shape, "heatOutlet", heat.outletX, heat.outletY, 0, 0, false)

    -- farthest bounding sphere centre draws first: heat before the rest
    local distance = RMS_Config.EXHAUST.HEAT.SORT_DISTANCE
    local directionX, directionY, directionZ = normalizeVector(puff.x - state.cameraX, puff.y - state.cameraY, puff.z - state.cameraZ, 0, 0, 1)
    setShapeBoundingSphere(shape, directionX * distance, directionY * distance, directionZ * distance,
        distance + RMS_Config.EXHAUST.PUFF.SIZE_MAX)
end

---Spawns a puff at the outlet, its sprite set for its life
-- @param table state smoke state
-- @param table plume plume
-- @param table layer puff layer
-- @param table emission emission of the layer
-- @param float ageOffset age the puff starts at (ms)
-- @return boolean isSpawned true when a slot was free
local function spawnPuff(state, plume, layer, emission, ageOffset)
    local slot = getPuffSlot(layer)
    if slot == nil then
        return false
    end

    local puffConfig = RMS_Config.EXHAUST.PUFF
    -- own serials: heat puffs never shift the draws of the smoke
    local serialKey = layer.isHeat and "nextHeatSerial" or "nextPuffSerial"
    state[serialKey] = state[serialKey] + 1
    local serial = state[serialKey]
    local directionX, directionY, directionZ = localDirectionToWorld(plume.linkNode, 0, 1, 0)
    directionX, directionY, directionZ = normalizeVector(directionX, directionY, directionZ, 0, 1, 0)
    local sideX, sideY, sideZ, forwardX, forwardY, forwardZ = getDirectionBasis(
        directionX, directionY, directionZ)

    local angle = getDeterministicValue(serial, 1) * math.pi * 2
    local spreadX = sideX * math.cos(angle) + forwardX * math.sin(angle)
    local spreadY = sideY * math.cos(angle) + forwardY * math.sin(angle)
    local spreadZ = sideZ * math.cos(angle) + forwardZ * math.sin(angle)
    local initialSpeed = emission.speed
    local lateralSpeed = emission.speed * puffConfig.SPREAD_SHARE * getDeterministicValue(serial, 3)

    layer.nextRank = layer.nextRank + 1
    local level = getThinningLevel(layer.nextRank)

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
        width = emission.jetStart,
        spriteRatio = sources.canSetSize and puffConfig.SPRITE_GAS_RATIO or nil,
        ambientGrowth = emission.ambientGrowth,
        tau = emission.tau,
        tauVapour = emission.tauVapour,
        evaporationMs = emission.evaporationMs,
        deltaT = emission.deltaT,
        ambientC = emission.ambientC,
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

    local offset = clamp(ageOffset, 0, lifespan * 0.5)
    puff.age = puff.age + offset
    local offsetSeconds = offset / 1000
    local jetStart = emission.jetStart
    local jetWidth = math.sqrt(jetStart * jetStart + 2 * puffConfig.JET_SPREAD * initialSpeed * jetStart * offsetSeconds)
    local jetDistance = (jetWidth - jetStart) / puffConfig.JET_SPREAD
    local jetSlowdown = jetStart / jetWidth
    puff.width = jetWidth
    puff.vx = directionX * initialSpeed * jetSlowdown + spreadX * lateralSpeed + plume.pipeVelocityX
    puff.vy = directionY * initialSpeed * jetSlowdown + spreadY * lateralSpeed + plume.pipeVelocityY
    puff.vz = directionZ * initialSpeed * jetSlowdown + spreadZ * lateralSpeed + plume.pipeVelocityZ
    local carriedX = (spreadX * lateralSpeed + plume.pipeVelocityX) * offsetSeconds
    local carriedY = (spreadY * lateralSpeed + plume.pipeVelocityY) * offsetSeconds
    local carriedZ = (spreadZ * lateralSpeed + plume.pipeVelocityZ) * offsetSeconds
    local originX, originY, originZ = getWorldTranslation(plume.linkNode)
    local outletJitter = jetWidth * 0.25 * (getDeterministicValue(serial, 8) * 2 - 1)
    local clearance = jetWidth * 0.5 + 0.005
    puff.x = originX + directionX * (clearance + jetDistance) + spreadX * outletJitter + carriedX
    puff.y = originY + directionY * (clearance + jetDistance) + spreadY * outletJitter + carriedY
    puff.z = originZ + directionZ * (clearance + jetDistance) + spreadZ * outletJitter + carriedZ
    puff.selfIgnoreUntil = clamp(clearance / math.max(initialSpeed, 0.1) * 2000, 25, 250)

    -- Expire the previous sprite before reusing its slot
    local geometry = slot.geometry
    ParticleUtil.setEmittingState(slot.renderer, false)
    addParticleSystemSimulationTime(geometry, sources.flushMs)

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

    -- the slot is reused only once this sprite has died
    slot.puff = puff
    slot.elapsed = 1
    slot.releaseAt = (sources.canSetLifespan and spriteLifespan or sources.assetLifespan) + 100
    slot.isInUse = true
    setWorldTranslation(slot.root, puff.x, puff.y, puff.z)
    setVisibility(slot.root, true)
    slot.isShown = true
    if layer.isHeat then
        drawHeatPuff(state, layer, slot)
    else
        local red, green, blue = RMS_Exhaust.getPuffRenderColour(puff)
        local alpha = RMS_Exhaust.getPuffRenderAlpha(puff)
        puff.lastRenderedAlpha = alpha
        puff.lastRenderedRed = red
        setShaderParameterRecursive(slot.renderer.shape, "colorAlpha", red, green, blue, alpha, false)
    end
    ParticleUtil.setEmittingState(slot.renderer, false)
    ParticleUtil.resetNumOfEmittedParticles(slot.renderer)
    ParticleUtil.setEmittingState(slot.renderer, true)
    addParticleSystemSimulationTime(geometry, 1)
    ParticleUtil.setEmittingState(slot.renderer, false)

    return true
end

---Advances and draws the puffs of a layer, freeing their slots
-- @param table vehicle vehicle
-- @param table state smoke state
-- @param table plume plume
-- @param table layer puff layer
-- @param float dt time since the last frame (ms)
-- @param table environment wind, air temperature, eddies and contact tests
-- @return integer active puffs still alive
local function updatePuffLayer(vehicle, state, plume, layer, dt, environment)
    local puffConfig = RMS_Config.EXHAUST.PUFF
    local active = 0
    for _, slot in ipairs(layer.pool) do
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
                    puff.lifespan = puff.age
                else
                    setWorldTranslation(slot.root, puff.x, puff.y, puff.z)
                    if layer.isHeat then
                        drawHeatPuff(state, layer, slot)
                    else
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
            end

            if puff.age < puff.lifespan then
                active = active + 1
            elseif slot.isShown ~= false then
                setVisibility(slot.root, false)
                slot.isShown = false
            end

            if slot.elapsed >= slot.releaseAt then
                slot.isInUse = false
                slot.puff = nil
                table.insert(layer.freeSlots, slot)
            end
        end
    end
    layer.activePuffs = active

    return active
end

---Advances the smoke and heat puffs of every plume
-- @param table vehicle vehicle
-- @param table state smoke state
-- @param float dt time since the last frame (ms)
local function updatePuffPools(vehicle, state, dt)
    if state.plumes == nil then
        state.activePuffs = 0
        state.activeHeatPuffs = 0
        return
    end

    local windX, windY, windZ = getWindVelocity()
    local windSpeed = getVectorLength(windX, 0, windZ)
    local timeSeconds = g_time / 1000
    local environment = {
        windX = windX,
        windY = windY,
        windZ = windZ,
        windSpeed = windSpeed,
        ambientC = state.ambientC,
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

    local heatConfig = RMS_Config.EXHAUST.HEAT
    local camera = getCamera()
    -- from rad of deflection to screen heights, at the screen centre
    state.heatScreenPerRad = heatConfig.GAIN / (2 * math.tan(getFovY(camera) * 0.5))
    state.cameraX, state.cameraY, state.cameraZ = getWorldTranslation(camera)

    local activePuffs, activeHeatPuffs = 0, 0
    for _, plume in ipairs(state.plumes) do
        local pipeX, pipeY, pipeZ = updatePipeVelocity(plume, dt)
        activePuffs = activePuffs + updatePuffLayer(vehicle, state, plume, plume, dt, environment)

        local heat = plume.heat
        if heat ~= nil then
            heat.outletX, heat.outletY = worldToLocal(camera, pipeX, pipeY, pipeZ)
            local directionX, directionY = worldDirectionToLocal(camera, localDirectionToWorld(plume.linkNode, 0, 1, 0))
            local travel = state.heatEmission.speed * dt / 1000
            heat.scrollX = (heat.scrollX + directionX * travel) % heatConfig.SCROLL_PERIOD
            heat.scrollY = (heat.scrollY + directionY * travel) % heatConfig.SCROLL_PERIOD
            activeHeatPuffs = activeHeatPuffs + updatePuffLayer(vehicle, state, plume, heat, dt, environment)
        end
    end

    state.activePuffs = activePuffs
    state.activeHeatPuffs = activeHeatPuffs
end

local BURST_DRIVERS = {"boost", "unburnt", "wetStacking", "preheat", "fault"}

---Resets the smoke state
-- @param table state smoke state
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
    state.activeHeatPuffs = 0
    state.gasTemperature = nil
    state.lineWorldTime = nil
    state.heatDeflection = 0
    state.pipeShelter = 0
    state.lee = {isValid = false}
    state.leeTimer = 0
    state.nextPuffSerial = 0
    state.nextHeatSerial = 0
    state.burst = 0
    state.burstRefractory = 0
    state.tuneTimer = 0
    state.isActive = false
    state.emission = {}
    state.heatEmission = {speed = 0}

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
-- @param table vehicle vehicle
function RMS_Exhaust.initSpec(vehicle)
    local state = {
        profileResolved = false,
        hasTurbo = false,
        hasDEF = false,
        isMethane = false,
        isNativeOwned = true
    }
    vehicle.spec_RealisticMechanicalSystems.exhaustSmoke = state
    resetState(state)
end

---Drops the plumes, gives the exhaust back and clears the smoke state
-- @param table vehicle vehicle
function RMS_Exhaust.reset(vehicle)
    local state = vehicle.spec_RealisticMechanicalSystems.exhaustSmoke
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
    local effects = vehicle.spec_motorized.exhaustEffects

    if next(effects) == nil or spec.isElectricVehicle then
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

    local load = spec.dynamicMotorLoad
    local motorState = vehicle:getMotorState()
    local wetStackingLevel = spec.fuelState.wetStackingLevel
    local preheatSeverity = spec.preheatColdStartFaultSeverity
    local sootEffect = getEffectIntensity(spec, "EXHAUST_SOOT")
    local oilEffect = getEffectIntensity(spec, "EXHAUST_OIL")
    local unburntEffect = getEffectIntensity(spec, "EXHAUST_UNBURNT")
    local engineTemperature = spec.rawEngineTemperature

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
    state.ambientC = RMS_Utils.getAmbientTemperature()
    state.targetVapour, state.coldness = RMS_Exhaust.calculateVapourTarget({
        ambientTemperature = state.ambientC,
        wetness = getAirWetness(),
        load = load,
        engineTemperature = engineTemperature
    })

    local drivers = state.drivers
    drivers.boost = targets.boostDeficit
    drivers.unburnt = targets.unburnt
    drivers.wetStacking = wetStackingLevel * clamp(load, 0, 1)
    drivers.preheat = preheatSeverity / 4
    drivers.fault = math.max(sootEffect, oilEffect, unburntEffect)

    state.isActive = true
    ensurePlumes(vehicle, state, effects)
    if state.plumes ~= nil and not state.isNativeOwned then
        enforceNativeSilence(vehicle)
    end
end

---Starts a burst on the sharpest rise of its drivers
-- @param table state smoke state
-- @param float dt time since the last tuning (ms)
local function updateBurstEdges(state, dt)
    local config = RMS_Config.EXHAUST
    local edges = config.BURST_EDGE
    local drivers = state.drivers
    local slow = state.slowDrivers

    local follow = math.min(dt / (config.BURST_SLOW_TAU + dt), 1)
    local latch = state.burstLatch
    local isRefractory = state.burstRefractory > 0
    local bestStrength = 0

    ---Keeps the strongest rise of a driver past its threshold
    -- @param string key driver
    -- @param float threshold rise that starts a burst
    local function testEdge(key, threshold)
        local driver = drivers[key]
        local rise = driver - slow[key]
        slow[key] = slow[key] + (driver - slow[key]) * follow

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
        end
    end

    testEdge("boost", edges.BOOST_DEFICIT)
    testEdge("unburnt", edges.UNBURNT)
    testEdge("wetStacking", edges.WET_STACKING)
    testEdge("preheat", edges.PREHEAT)
    testEdge("fault", edges.FAULT)

    if bestStrength > 0 then
        state.burst = math.max(state.burst, bestStrength)
        state.burstRefractory = config.BURST_REFRACTORY
    end
end

---Sets the optical depth of a puff by the overlap of the plume
-- @param table emission emission of the plume
local function updatePuffDensity(emission)
    local sizeStart = emission.sizeStart
    local overlap = sizeStart / getPuffSpacing(emission, sizeStart)
    local referenceSize = math.max(RMS_Config.EXHAUST.PUFF.REFERENCE_SIZE, sizeStart)
    local referenceOverlap = math.max(referenceSize / getPuffSpacing(emission, referenceSize), 1)
    local referenceAge = (referenceSize - sizeStart) / math.max(emission.sizeGain, 0.000001)

    emission.tau = emission.tauTarget / overlap
    emission.tauVapour = emission.vapourTarget / referenceOverlap * (referenceSize / sizeStart) ^ 2
        * math.exp(referenceAge / emission.evaporationMs)
end

---Returns the outlet diameter by the engine power
-- @param table vehicle vehicle
-- @return float diameter diameter (m)
local function getPipeDiameter(vehicle)
    local puffConfig = RMS_Config.EXHAUST.PUFF

    return clamp(puffConfig.PIPE_DIAMETER_PER_SQRT_KW * math.sqrt(getPeakPowerKw(vehicle)),
        puffConfig.PIPE_DIAMETER_MIN, puffConfig.PIPE_DIAMETER_MAX)
end

---Lays out the jet at the outlet: speed, size, wind, shelter and rate
-- @param table vehicle vehicle
-- @param table state smoke state
-- @param table emission emission of the plume
-- @param float exitSpeed speed at the outlet (m/s)
-- @param float deltaT temperature of the gas over the air (K)
-- @param float dt time since the last frame (ms)
local function updateJet(vehicle, state, emission, exitSpeed, deltaT, dt)
    local config = RMS_Config.EXHAUST
    local puffConfig = config.PUFF

    local plume = state.plumes[1]
    state.leeTimer = state.leeTimer - dt
    if state.leeTimer <= 0 then
        updateLee(state, plume.lastPipeX, plume.lastPipeY, plume.lastPipeZ)
        state.leeTimer = puffConfig.SHELTER_CHECK_MS
    end
    local shelterTarget = getShelterTarget(vehicle, plume.lastPipeX, plume.lastPipeY, plume.lastPipeZ, plume.lastPipeX,
        plume.lastPipeZ)
    state.pipeShelter = state.pipeShelter + (shelterTarget - state.pipeShelter)
        * math.min(dt / (puffConfig.SHELTER_TAU + dt), 1)
    local windX, _, windZ = getWindVelocity()
    local windSpeed = getVectorLength(windX, 0, windZ) * lerp(1, puffConfig.SHELTER_WIND_SHARE, state.pipeShelter)

    local jetStart = getPipeDiameter(vehicle)
    emission.speed = exitSpeed
    emission.jetStart = jetStart
    emission.sizeStart = jetStart * puffConfig.SPRITE_GAS_RATIO
    emission.windSpeed = windSpeed
    emission.shelter = state.pipeShelter
    emission.dispersalSpeed = config.TURBULENCE.BASE + config.TURBULENCE.PER_WIND * windSpeed + puffConfig.RISE_SPEED
    emission.ambientGrowth = puffConfig.GROWTH_BASE + puffConfig.GROWTH_PER_WIND * windSpeed
    emission.deltaT = deltaT
    emission.ambientC = state.ambientC
    updateJetProfile(emission)

    local outletSpeed = math.max(getVectorLength(exitSpeed, windSpeed, 0), emission.dispersalSpeed)
    local rate = clamp(puffConfig.OVERLAP_TARGET * outletSpeed / emission.sizeStart, puffConfig.RATE_MIN,
        puffConfig.RATE_MAX)
    local sources = RMS_Exhaust.plumeSources
    if not sources.canSetLifespan then
        rate = math.min(rate, 0.8 * puffConfig.POOL_MAX * 1000 / math.max(sources.assetLifespan, 1))
    end
    emission.rate = rate
end

---Returns the sprite growth fitting the jet width at an age
-- @param table emission emission of the plume
-- @param float fitMs age to fit (ms)
-- @return float growth growth (m/ms)
local function getGrowthFit(emission, fitMs)
    return math.max(RMS_Config.EXHAUST.PUFF.SPRITE_GAS_RATIO * (getJetWidth(emission, fitMs) - emission.jetStart) / fitMs, 0.00005)
end

---Sets the retire age and growth of each thinning level
-- @param table emission emission of the plume
local function updateThinning(emission)
    local puffConfig = RMS_Config.EXHAUST.PUFF
    emission.retireLifespans = emission.retireLifespans or {}
    updateRetireLifespans(emission, emission.retireLifespans)

    emission.levelGains = emission.levelGains or {}
    for level = 0, puffConfig.THIN_LEVEL_MAX do
        local gain = emission.sizeGain
        if RMS_Exhaust.plumeSources.canSetSize then
            local levelLifespan = emission.retireLifespans[level] or emission.lifespan
            gain = getGrowthFit(emission, clamp(levelLifespan * puffConfig.GROWTH_FIT_SHARE, puffConfig.GROWTH_FIT_LEVEL_MIN_MS,
                puffConfig.GROWTH_FIT_MAX_MS))
        end
        emission.levelGains[level] = gain
    end
end

---Returns the emission of the plume: jet, optical depth, colour and life
-- @param table vehicle vehicle
-- @param table state smoke state
-- @param float opacity opacity of the smoke
-- @param float vapour optical depth of the vapour
-- @param float flow gas flow, 0 to 1
-- @param float burst burst, 0 to 1
-- @param float dt time since the last frame (ms)
-- @return table emission emission of the plume
local function updateEmission(vehicle, state, opacity, vapour, flow, burst, dt)
    local config = RMS_Config.EXHAUST
    local puffConfig = config.PUFF
    local emission = state.emission

    local deltaT = math.max(state.gasTemperature - state.ambientC, 0)
    local gasKelvin = getNumber(state.ambientC, 15, -80, 80) + 273.15 + deltaT
    local fullKelvin = 293.15 + config.EGT.RISE_FULL_K
    local exitSpeed = math.max(puffConfig.EXIT_SPEED_MIN, puffConfig.EXIT_SPEED_FULL * flow * gasKelvin / fullKelvin)
        * (1 + burst * config.BURST_SPEED_GAIN)
    updateJet(vehicle, state, emission, exitSpeed, deltaT, dt)
    emission.rate = emission.rate * (1 + burst * config.BURST_EMIT_GAIN)

    local evaporationMs = lerp(config.VAPOUR.EVAPORATION_WARM_MS, config.VAPOUR.EVAPORATION_COLD_MS, state.coldness)
    local tauTarget = -math.log(math.max(1 - opacity, 0.001)) * (1 + burst * config.BURST_TAU_GAIN)
    emission.tauTarget = tauTarget
    emission.vapourTarget = vapour
    emission.evaporationMs = evaporationMs

    local sources = RMS_Exhaust.plumeSources
    if sources.canSetSize then
        local fitMs = puffConfig.GROWTH_FIT_MIN_MS
        for _ = 1, 2 do
            emission.sizeGain = getGrowthFit(emission, fitMs)
            updatePuffDensity(emission)
            fitMs = clamp(getVisibleLifespan(emission) * puffConfig.GROWTH_FIT_SHARE,
                puffConfig.GROWTH_FIT_MIN_MS, puffConfig.GROWTH_FIT_MAX_MS)
        end
    else
        emission.sizeStart = sources.assetSize
        emission.sizeGain = sources.assetSizeGain
        updatePuffDensity(emission)
    end

    emission.red = state.red
    emission.green = state.green
    emission.blue = state.blue
    emission.isVisible = tauTarget + vapour > puffConfig.TAU_VISIBLE
    emission.lifespan = getVisibleLifespan(emission)
    updateThinning(emission)

    return emission
end

---Tells whether the outlet stands within heat sight of the camera
-- @param table state smoke state
-- @return boolean isInSight true within sight
local function getIsHeatInSight(state)
    local plume = state.plumes[1]

    return getVectorLength(state.cameraX - plume.lastPipeX, state.cameraY - plume.lastPipeY, state.cameraZ - plume.lastPipeZ)
        <= RMS_Config.EXHAUST.HEAT.CLIP_DISTANCE
end

local HEAT_JET_FIELDS = {"speed", "jetStart", "sizeStart", "windSpeed", "shelter", "dispersalSpeed", "ambientGrowth", "deltaT",
    "ambientC", "jetProfile", "rate"}

---Updates the heat emission, its puffs riding the jet last laid out in state.emission
-- @param table state smoke state
local function updateHeatEmission(state)
    local config = RMS_Config.EXHAUST
    local heatConfig = config.HEAT
    local puffConfig = config.PUFF
    local heat = state.heatEmission
    for _, key in ipairs(HEAT_JET_FIELDS) do
        heat[key] = state.emission[key]
    end

    state.heatDeflection = RMS_Exhaust.getHeatDeflection(heat.deltaT, heat.ambientC)
    heat.isVisible = state.heatDeflection > heatConfig.MIN_DEFLECTION and getIsHeatInSight(state)
    if not heat.isVisible then
        return
    end

    -- gas rise that bends light by MIN_DEFLECTION, where a puff ends
    local visibleRise = heatConfig.MIN_DEFLECTION * (heat.ambientC + 273.15)
        / (heatConfig.PATH_FACTOR * heatConfig.AIR_REFRACTIVITY - heatConfig.MIN_DEFLECTION)
    local width = heat.jetStart * (heat.deltaT / visibleRise) ^ (1 / config.EGT.DILUTION_EXPONENT)
    local profile = heat.jetProfile
    local widths = profile.widths
    local index = 2
    while index < #widths and widths[index] < width do
        index = index + 1
    end
    heat.lifespan = (index - 2 + math.min((width - widths[index - 1]) / (widths[index] - widths[index - 1]), 1)) * profile.stepMs
    heat.sizeGain = getGrowthFit(heat, clamp(heat.lifespan * puffConfig.GROWTH_FIT_SHARE, puffConfig.GROWTH_FIT_LEVEL_MIN_MS,
        puffConfig.GROWTH_FIT_MAX_MS))
    updateThinning(heat)
end

---Emits the puffs a layer owes this frame, returning how many
-- @param table state smoke state
-- @param table plume plume
-- @param table layer puff layer
-- @param table emission emission of the layer
-- @param float dt time since the last frame (ms)
-- @return integer spawned puffs spawned
local function emitPuffs(state, plume, layer, emission, dt)
    local shouldEmit = emission.isVisible and getEffectiveVisibility(plume.linkNode)
    if layer.isEmitting ~= shouldEmit then
        layer.isEmitting = shouldEmit
        layer.emissionAccumulator = shouldEmit and math.max(layer.emissionAccumulator, 1) or 0
    end
    if not shouldEmit then
        return 0
    end

    layer.emissionAccumulator = layer.emissionAccumulator + emission.rate * math.min(dt, 100) / 1000
    local spawnCount = math.floor(layer.emissionAccumulator)
    layer.emissionAccumulator = layer.emissionAccumulator - spawnCount
    local interval = 1000 / emission.rate
    local spawned = 0
    for index = 1, spawnCount do
        local ageOffset = math.min((spawnCount - index + layer.emissionAccumulator) * interval, dt)
        if spawnPuff(state, plume, layer, emission, ageOffset) then
            layer.activePuffs = layer.activePuffs + 1
            spawned = spawned + 1
        else
            layer.emissionAccumulator = 0
            break
        end
    end

    return spawned
end

---Emits the heat puffs of every plume
-- @param table state smoke state
-- @param float dt time since the last frame (ms)
local function emitHeat(state, dt)
    updateHeatEmission(state)
    for _, plume in ipairs(state.plumes) do
        state.activeHeatPuffs = state.activeHeatPuffs + emitPuffs(state, plume, plume.heat, state.heatEmission, dt)
    end
end

---Updates the temperature of the exhaust line
-- @param table vehicle vehicle
-- @param table state smoke state
-- @param float dt time since the last frame (ms)
-- @param boolean isMotorStarted true while the engine smokes
-- @param float flow gas flow, 0 to 1
local function updateLineTemperature(vehicle, state, dt, isMotorStarted, flow)
    local spec = vehicle.spec_RealisticMechanicalSystems
    local ambient = RMS_Utils.getAmbientTemperature()
    local isRegenerating = spec.fuelState.isParticulateFilterRegenerating
    local worldTime = RMS_Thermal.getWorldTimeMS()
    local stoppedDt = dt
    if state.lineWorldTime ~= nil then
        stoppedDt = math.max(worldTime - state.lineWorldTime, 0)
    end
    state.lineWorldTime = worldTime
    state.ambientC = ambient

    if state.gasTemperature == nil then
        -- an engine first seen running has been running for a while
        state.gasTemperature = vehicle:getMotorState() == MotorState.ON
            and RMS_Exhaust.getLineInletTemperature(state.load, ambient, isRegenerating) or ambient
    end
    state.gasTemperature = RMS_Exhaust.calculateLineTemperature({
        currentTemperature = state.gasTemperature,
        ambientTemperature = ambient,
        isMotorStarted = isMotorStarted,
        load = state.load,
        flow = flow,
        isRegenerating = isRegenerating,
        dt = dt,
        stoppedDt = stoppedDt
    })
end

---Returns the rise over the air of the air a stopped line heats
-- @param table state smoke state
-- @param float lineTemperature temperature of the line (deg C)
-- @return float rise rise (K)
local function getConvectionRise(state, lineTemperature)
    return math.max(lineTemperature - state.ambientC, 0) * RMS_Config.EXHAUST.HEAT.CONVECTION_SHARE
end

---Tells whether a stopped machine shimmers in sight of the camera
-- @param table vehicle vehicle
-- @return boolean isInSight true when it shimmers in sight
function RMS_Exhaust.getIsStoppedHeatInSight(vehicle)
    local state = vehicle.spec_RealisticMechanicalSystems.exhaustSmoke
    if state.gasTemperature == nil or RMS_Exhaust.plumeSources.heatNode == nil then
        return false
    end

    state.cameraX, state.cameraY, state.cameraZ = getWorldTranslation(getCamera())
    if not getIsHeatInSight(state) then
        return false
    end

    local worldTime = RMS_Thermal.getWorldTimeMS()
    local stoppedDt = 0
    if state.lineWorldTime ~= nil then
        stoppedDt = math.max(worldTime - state.lineWorldTime, 0)
    end

    local lineTemperature = RMS_Exhaust.calculateLineTemperature({
        currentTemperature = state.gasTemperature,
        ambientTemperature = state.ambientC,
        isMotorStarted = false,
        stoppedDt = stoppedDt
    })
    return RMS_Exhaust.getHeatDeflection(getConvectionRise(state, lineTemperature), state.ambientC) > RMS_Config.EXHAUST.HEAT.MIN_DEFLECTION
end

---Emits the air the line of a stopped engine heats, rising from the outlet
-- @param table vehicle vehicle
-- @param table state smoke state
-- @param float dt time since the last frame (ms)
-- @return boolean isVisible true while the heat shows
local function emitConvection(vehicle, state, dt)
    local deltaT = getConvectionRise(state, state.gasTemperature)
    state.heatDeflection = RMS_Exhaust.getHeatDeflection(deltaT, state.ambientC)
    if not (state.heatDeflection > RMS_Config.EXHAUST.HEAT.MIN_DEFLECTION and getIsHeatInSight(state)) then
        return false
    end

    -- speed the lighter air gains while it rises by one pipe diameter
    local speed = math.sqrt(9.81 * deltaT / (state.ambientC + 273.15 + deltaT) * getPipeDiameter(vehicle))
    updateJet(vehicle, state, state.emission, speed, deltaT, dt)
    emitHeat(state, dt)

    return state.heatEmission.isVisible
end

---Drives the smoke and heat puffs of the plume
-- @param table vehicle vehicle
-- @param float dt time since the last frame (ms)
function RMS_Exhaust.applyShader(vehicle, dt)
    local spec = vehicle.spec_RealisticMechanicalSystems
    local state = spec.exhaustSmoke
    updatePuffPools(vehicle, state, dt)

    if state.plumes == nil then
        return
    end

    local config = RMS_Config.EXHAUST
    local hasHeat = RMS_Exhaust.plumeSources.heatNode ~= nil
    local isSmoking = state.isActive and getIsSmokeRendered(vehicle)
    local flowScale = isSmoking and getFlow(vehicle, state) or 0
    updateLineTemperature(vehicle, state, dt, isSmoking, flowScale)

    local isConvecting = not isSmoking and hasHeat and emitConvection(vehicle, state, dt)
    if (isSmoking or isConvecting or state.activePuffs > 0 or state.activeHeatPuffs > 0) then
        vehicle:raiseActive()
    end

    if not isSmoking then
        return
    end

    state.burst = state.burst * math.exp(-dt / config.BURST_DECAY_TAU)
    if state.burst < 0.001 then
        state.burst = 0
    end
    state.burstRefractory = math.max(state.burstRefractory - dt, 0)

    local sootRiseTau = state.burst > 0 and config.BURST_RISE_TAU or config.SOOT_RISE_TAU
    local riseTau = state.burst > 0 and config.BURST_RISE_TAU or nil
    state.soot = getSmoothed(state.soot, state.targetSoot, dt, sootRiseTau, config.SOOT_FALL_TAU)
    state.oil = getSmoothed(state.oil, state.targetOil, dt, riseTau)
    state.unburnt = getSmoothed(state.unburnt, state.targetUnburnt, dt, riseTau)
    state.vapour = getSmoothed(state.vapour, state.targetVapour, dt, config.VAPOUR_TAU, config.VAPOUR_TAU)
    local targetRed, targetGreen, targetBlue = getTintMix(state.soot, state.oil, state.unburnt)
    state.red = getSmoothed(state.red, targetRed, dt, config.TINT_TAU, config.TINT_TAU)
    state.green = getSmoothed(state.green, targetGreen, dt, config.TINT_TAU, config.TINT_TAU)
    state.blue = getSmoothed(state.blue, targetBlue, dt, config.TINT_TAU, config.TINT_TAU)

    local opacity = getOpacity(state.soot, state.oil, state.unburnt)
    local vapour = state.vapour
    state.opacity = opacity

    state.tuneTimer = state.tuneTimer + dt
    if state.tuneTimer >= config.TUNE_INTERVAL then
        updateBurstEdges(state, state.tuneTimer)
        state.tuneTimer = 0
    end

    local burst = state.burst * opacity
    local emission = updateEmission(vehicle, state, opacity, vapour, flowScale, burst, dt)
    for _, plume in ipairs(state.plumes) do
        state.activePuffs = state.activePuffs + emitPuffs(state, plume, plume, emission, dt)
    end

    if hasHeat then
        emitHeat(state, dt)
    end

    state.vapourOpacity = 1 - math.exp(-vapour)
    state.exitSpeed = emission.speed
    state.windSpeed = emission.windSpeed
end
