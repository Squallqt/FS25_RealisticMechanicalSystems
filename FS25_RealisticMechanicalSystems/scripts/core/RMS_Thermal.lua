-- Copyright © 2026 Squallqt. All rights reserved.

---Engine, oil and traction-battery temperatures
RMS_Thermal = {}

local sanitizeNumber = RealisticMechanicalSystems.sanitizeNumber
local DAY_MS = 24 * 60 * 60 * 1000

---Tells whether a value is a finite number
-- @param any value value
-- @return boolean isFinite true for a finite number
local function isFinite(value)
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

---Returns a temperature, the fallback when it is unset
-- @param any value temperature, -99 or not a number when unset
-- @param float? fallback temperature when unset (deg C)
-- @return float? temperature temperature (deg C), nil when unset without a fallback
local function getTemperature(value, fallback)
    if isFinite(value) and value ~= -99 then
        return value
    end
    return fallback
end

---Tells whether a system of the machine is enabled
-- @param table spec RMS specialization of the vehicle
-- @param string key key of the system
-- @return boolean isEnabled true when enabled
local function getSystemEnabled(spec, key)
    return spec.systems[key].enabled
end

---Returns the drive limits used by temperature consumers
-- @param table spec RMS specialization of the vehicle
-- @return table values thermal configuration of the drive
function RMS_Thermal.getDriveValues(spec)
    return spec.isElectricVehicle and RMS_Config.ELECTRIC_DRIVE.THERMAL or RMS_Config.THERMAL
end

---Returns the monotonic in-world time in ms
-- @return float time world time (ms)
function RMS_Thermal.getWorldTimeMS()
    local environment = g_currentMission.environment
    return environment.currentMonotonicDay * DAY_MS + environment.dayTime
end

---Tells whether the vehicle has a separate hydraulic oil circuit
-- @param table spec RMS specialization of the vehicle
-- @return boolean isSeparate true with a separate circuit
function RMS_Thermal.getHasSeparateHydraulicCircuit(spec)
    return not spec.hasCommonSump and getSystemEnabled(spec, "hydraulics") and spec.fluidCapacities.hydraulicFluid > 0
end

---Reads native load, real rpm and applied power against the native peak
-- @param table vehicle vehicle
-- @param boolean isMotorStarted true while the engine runs
-- @return table inputs load, rpm, power and fan of the engine
function RMS_Thermal.getNativeThermalInputs(vehicle, isMotorStarted)
    local spec = vehicle.spec_RealisticMechanicalSystems
    local motor = vehicle:getMotor()
    local load = sanitizeNumber(RMS_EngineRemap.getStockLoad(vehicle, vehicle:getMotorLoadPercentage()), 0, 0, 1.5)
        * RMS_Thermal.getEngineTorqueFactor(vehicle)
    local maxRpm = sanitizeNumber(motor:getMaxRpm(), 0, 0)
    local rpm = maxRpm > 0 and sanitizeNumber(motor:getLastRealMotorRpm() / maxRpm, 0, 0, 1.5) or 0
    local ratedRpm = sanitizeNumber(motor.peakMotorPowerRotSpeed, 0, 0) * 30 / math.pi
    local fanSpeed = ratedRpm > 0 and sanitizeNumber(motor:getLastRealMotorRpm() / ratedRpm, 0, 0, 1) or 0
    local applied = sanitizeNumber(motor:getMotorAppliedTorque(), 0, 0)
    local peakPower = sanitizeNumber(motor.peakMotorPower, 0, 0)
    local rotation = sanitizeNumber(motor:getMotorRotSpeed(), 0, 0)
    local power = peakPower > 0 and applied * rotation / peakPower or nil
    local external = sanitizeNumber(motor:getMotorExternalTorque(), 0, 0)
    local externalShare = applied > 0 and math.clamp(external / math.max(applied, external), 0, 1) or 0
    local externalLoad = load * externalShare
    return {
        motorStarted = isMotorStarted,
        load = load, rpm = rpm, fanSpeed = fanSpeed, power = power, external = externalLoad, drive = load - externalLoad,
        speed = math.min(math.abs(vehicle:getLastSpeed()) / 50, 1),
        hydraulic = spec.isHydraulicActive and getSystemEnabled(spec, "hydraulics") and 1 or 0
    }
end

---Returns the native engine temperature of a managed machine, nil when RMS does not drive it
-- @param table vehicle vehicle
-- @return table? temperature native motor temperature
local function getManagedMotorTemperature(vehicle)
    if vehicle.spec_RealisticMechanicalSystems.isExcludedVehicle or RMS_Utils.hasCVTAddon(vehicle) then
        return nil
    end
    return vehicle.spec_motorized.motorTemperature
end

---Tells whether the engine protection applies, on native diesel engines with the shared ECU profile
-- @param table vehicle vehicle
-- @return boolean usesProtection true when it applies
function RMS_Thermal.getUsesEngineProtection(vehicle)
    return not vehicle.spec_RealisticMechanicalSystems.isElectricVehicle and getManagedMotorTemperature(vehicle) ~= nil
        and vehicle.spec_motorized.consumersByFillTypeName.DIESEL ~= nil and RMS_Utils.getUsesEngineECUProfile(vehicle)
end

---Returns the thermal torque fraction, apart from wear and engine faults
-- @param table vehicle vehicle
-- @return float factor torque fraction, 0.2 to 1
function RMS_Thermal.getEngineTorqueFactor(vehicle)
    if not RMS_Thermal.getUsesEngineProtection(vehicle) then return 1 end
    local effect = vehicle.spec_RealisticMechanicalSystems.activeEffects.ENGINE_THERMAL_TORQUE_LIMIT
    return effect ~= nil and effect.value or 1
end

---Updates the engine protection from the shared temperature, in two levels
-- @param table vehicle vehicle
function RMS_Thermal.syncEngineProtection(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    local config = RMS_Config.THERMAL.ENGINE_PROTECTION
    if not vehicle.isServer then return end
    local id = "ENGINE_THERMAL_PROTECTION"
    local current = spec.activeBreakdowns[id]
    local previousStage = current ~= nil and current.stage or 0
    local stage = 0
    if RMS_Thermal.getUsesEngineProtection(vehicle) and (current ~= nil or vehicle:getIsMotorStarted()) then
        local temperature = RMS_Thermal.getEngineTemperature(vehicle)
        if temperature >= config.SEVERE_TEMP or (previousStage == 2 and temperature > config.SEVERE_RELEASE_TEMP) then
            stage = 2
        elseif temperature >= config.START_TEMP or (previousStage > 0 and temperature > config.RELEASE_TEMP) then
            stage = 1
        end
    end
    if stage == previousStage then return end
    if stage == 0 then
        vehicle:removeBreakdown(id)
    elseif current == nil then
        vehicle:addBreakdown(id, { stage = stage, isActive = true, isSelectedForRepair = false })
    else
        vehicle:changeBreakdownStage(id, stage)
    end
end

---Stores the engine temperature, the legacy RMS fields mirroring it
-- @param table vehicle vehicle
-- @param float temperature temperature (deg C)
function RMS_Thermal.setEngineTemperature(vehicle, temperature)
    local spec = vehicle.spec_RealisticMechanicalSystems
    if getTemperature(temperature, nil) == nil then return end
    local native = getManagedMotorTemperature(vehicle)
    if native ~= nil then
        native.value = temperature
    end
    spec.rawEngineTemperature = temperature
    spec.engineTemperature = temperature
end

---Sets the engine temperature at load, ambient without a saved one
-- @param table vehicle vehicle
function RMS_Thermal.initializeEngineTemperature(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    RMS_Thermal.setEngineTemperature(vehicle,
        getTemperature(spec.engineTemperature, getTemperature(spec.rawEngineTemperature, RMS_Utils.getAmbientTemperature())))
end

---Reads the engine temperature, taking one set in the game's field
-- @param table vehicle vehicle
-- @return float temperature temperature (deg C)
function RMS_Thermal.getEngineTemperature(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    local native = getManagedMotorTemperature(vehicle)
    local nativeValue = native ~= nil and getTemperature(native.value, nil) or nil
    local temperature = spec.rawEngineTemperature
    if vehicle.isServer and spec.takesEngineTemperature and nativeValue ~= nil and nativeValue ~= temperature then
        temperature = nativeValue
        spec._thermalEngineWorldTime = RMS_Thermal.getWorldTimeMS()
        spec._thermalEngineAmbient = RMS_Utils.getAmbientTemperature()
    end
    if native ~= nil and native.value ~= temperature then
        native.value = temperature
    end
    spec.rawEngineTemperature = temperature
    spec.engineTemperature = temperature
    return temperature
end

---Opens the engine temperature to a value set in the game's field
-- @param table vehicle vehicle
-- @return float temperature temperature (deg C)
function RMS_Thermal.shareEngineTemperature(vehicle)
    -- what was written while the machine loaded is put back first
    local temperature = RMS_Thermal.getEngineTemperature(vehicle)
    vehicle.spec_RealisticMechanicalSystems.takesEngineTemperature = true

    return temperature
end

---Returns the time elapsed for a role, the world time while the engine is off, and the previous ambient
-- @param table spec RMS specialization of the vehicle
-- @param string trackerKey field of the last world time
-- @param string ambientKey field of the last ambient
-- @param float dtOperating operating time of the step (ms)
-- @param boolean isMotorStarted true while the engine runs
-- @param float ambient ambient temperature (deg C)
-- @param float worldTime world time (ms)
-- @return float elapsed time elapsed (ms)
-- @return float previousAmbient ambient at the previous step (deg C)
local function getRoleInterval(spec, trackerKey, ambientKey, dtOperating, isMotorStarted, ambient, worldTime)
    local previousAmbient = getTemperature(spec[ambientKey], ambient)
    local elapsed = dtOperating
    local previousTime = spec[trackerKey]
    if not isMotorStarted then
        elapsed = previousTime ~= nil and math.max(worldTime - previousTime, 0) or 0
    end
    spec[trackerKey] = worldTime
    spec[ambientKey] = ambient
    return elapsed, previousAmbient
end

---Returns the time elapsed for the traction battery, charging included, and the previous ambient
-- @param table spec RMS specialization of the vehicle
-- @param float dtOperating operating time of the step (ms)
-- @param float ambient ambient temperature (deg C)
-- @param float worldTime world time (ms)
-- @param boolean isMotorStarted true while the engine runs
-- @return float elapsed time elapsed (ms)
-- @return float previousAmbient ambient at the previous step (deg C)
local function getBatteryInterval(spec, dtOperating, ambient, worldTime, isMotorStarted)
    local previousAmbient = getTemperature(spec._thermalBatteryAmbient, ambient)
    local previousTime = spec._thermalBatteryWorldTime
    local observation = spec.tractionBatteryChargeObservation
    local chargingMS = observation ~= nil and observation.elapsedMS or 0
    local elapsedWorld = previousTime ~= nil and math.max(worldTime - previousTime, 0) or 0
    spec._thermalBatteryWorldTime = worldTime
    local elapsed = math.max(isMotorStarted and dtOperating or elapsedWorld, chargingMS)
    if not isMotorStarted and previousTime ~= nil and elapsedWorld == 0 then
        elapsed = 0
    end
    spec._thermalBatteryAmbient = ambient
    return elapsed, previousAmbient
end

---Returns the thermostat opening, its stuck position when it sticks
-- @param table profile thermal profile of the role
-- @param float temperature temperature (deg C)
-- @param float? health health of the thermostat, none outside the engine
-- @param float? stuckPosition stuck position, 0 to 1
-- @return float opening opening, 0 to 1
local function getOpening(profile, temperature, health, stuckPosition)
    if stuckPosition ~= nil then
        return stuckPosition
    end
    return math.clamp((temperature - profile.regulatedMin) / (profile.regulatedMax - profile.regulatedMin), 0, 1) * (health or 1)
end

---Returns the share of its cooling the radiator gives, dirt, health and fluid level counted
-- @param table spec RMS specialization of the vehicle
-- @param string fluidKey field of the level of the cooling fluid
-- @param float dirt clogging of the radiator, 0 to 1
-- @return float share share, 0 to 1
local function getExchangeFactor(spec, fluidKey, dirt)
    local radiator = getSystemEnabled(spec, "cooling") and spec.radiatorHealth or 1
    return (1 - dirt * dirt) * radiator * spec[fluidKey]
end

---Returns the share of its airflow the fan gives, none while it reverses
-- @param table spec RMS specialization of the vehicle
-- @param table inputs native thermal inputs
-- @return float share share, 0 to 1
local function getFanAirflow(spec, inputs)
    if spec.isElectricVehicle then
        return 1
    end
    if spec.fanReversalTime > 0 then
        return 0
    end
    return inputs.fanSpeed ^ RMS_Config.THERMAL.FAN_AIRFLOW_EXPONENT
end

---Returns the warmup heat and cooling of a diesel at an ambient and a power
-- @param table warmup warmup table by climate and power
-- @param float ambient ambient temperature (deg C)
-- @param float power engine power
-- @return float heat heating rate
-- @return float cooling cooling rate
local function getDieselWarmupRates(warmup, ambient, power)
    local climates = warmup.climates
    local climateIndex = 1
    while climateIndex < #climates - 1 and ambient > climates[climateIndex + 1].ambient do
        climateIndex = climateIndex + 1
    end
    local low, high = climates[climateIndex], climates[climateIndex + 1]
    local weatherShare = math.clamp((ambient - low.ambient) / (high.ambient - low.ambient), 0, 1)
    local powers = warmup.power
    local powerIndex = 1
    while powerIndex < #powers - 1 and power > powers[powerIndex + 1] do
        powerIndex = powerIndex + 1
    end
    local powerShare = (power - powers[powerIndex]) / (powers[powerIndex + 1] - powers[powerIndex])
    local lowHeat = math.max(low.heat[powerIndex] + (low.heat[powerIndex + 1] - low.heat[powerIndex]) * powerShare, 0)
    local highHeat = math.max(high.heat[powerIndex] + (high.heat[powerIndex + 1] - high.heat[powerIndex]) * powerShare, 0)
    return lowHeat * (1 - weatherShare) + highHeat * weatherShare,
        low.cooling * (1 - weatherShare) + high.cooling * weatherShare
end

---Advances one thermal role with its profile rates and the sampled ambient
-- @param table vehicle vehicle
-- @param string role thermal role
-- @param float temperature temperature (deg C)
-- @param float dtMS interval (ms)
-- @param float ambient0 ambient at the start of the interval (deg C)
-- @param float ambient1 ambient at the end of the interval (deg C)
-- @param table inputs native thermal inputs
-- @param table options work share, charge, forced activity and fluid of the role
-- @return float temperature temperature at the end (deg C)
-- @return table values heat balance of the step
function RMS_Thermal.advanceRole(vehicle, role, temperature, dtMS, ambient0, ambient1, inputs, options)
    local profile = RMS_Config.THERMAL.PROFILES[role]
    local spec = vehicle.spec_RealisticMechanicalSystems
    local elapsed = dtMS / 1000
    local workShare = options.workShare or (inputs.motorStarted and 1 or 0)
    local responseRate = inputs.motorStarted and profile.activeResponseRate or 1
    local idleHeat = profile.heatIdle * workShare
    local ptoHeat = profile.heatExternal * inputs.external * workShare
    local hydraulicHeat = profile.heatHydraulic * (options.hydraulicActivity or 0) * workShare
    local heat = (profile.heatIdle + profile.heatLoad * inputs.load + profile.heatRpm * inputs.rpm
        + profile.heatDrive * inputs.drive + profile.heatExternal * inputs.external
        + profile.heatHydraulic * (options.hydraulicActivity or 0)) * workShare
    local passiveRate = profile.passiveCooling
    if role == "diesel" and inputs.motorStarted and inputs.power ~= nil
        and temperature < profile.regulatedMax then
        local warmShare = math.clamp((temperature - profile.regulatedMin) / (profile.regulatedMax - profile.regulatedMin), 0, 1)
        local warmupHeat, warmupCooling = getDieselWarmupRates(profile.warmup, ambient0, inputs.power)
        heat = heat * warmShare + warmupHeat / responseRate * (1 - warmShare) * workShare
        idleHeat = idleHeat * warmShare
        passiveRate = passiveRate * warmShare + warmupCooling / responseRate * (1 - warmShare)
    end
    heat = math.max(heat + (options.extraHeatRate or 0) * workShare, 0)
    if elapsed > 0 and options.chargeCapacityShare ~= nil then
        heat = heat + profile.heatChargeCapacityShare * options.chargeCapacityShare / elapsed
    end
    heat = heat * responseRate
    idleHeat = idleHeat * responseRate
    ptoHeat = ptoHeat * responseRate
    hydraulicHeat = hydraulicHeat * responseRate

    local dirt = spec.radiatorClogging
    local exchange = getExchangeFactor(spec, options.fluidKey, dirt)
    local active = inputs.motorStarted
    if options.forcedActive ~= nil then active = options.forcedActive end
    local opening = active and getOpening(profile, temperature, options.thermostatHealth, options.stuckPosition) or 0
    local fan = active and spec.fanClutchHealth * getFanAirflow(spec, inputs) or 0
    local passive = passiveRate * responseRate
    local speed = profile.speedCooling * inputs.speed * responseRate
    local forced = profile.forcedCooling * opening * exchange * fan * responseRate
    local coolingRate = passive + speed + forced
    local nextTemperature = math.min(RMS_Thermal.integrateTemperatureExact(temperature, heat, coolingRate, elapsed, ambient0, ambient1),
        profile.boilingPoint or math.huge)
    return nextTemperature, {
        totalHeat = heat, totalCooling = coolingRate * (temperature - ambient0),
        radiatorCooling = forced * (temperature - ambient0), coolerCooling = forced * (temperature - ambient0),
        convectionCooling = passive * (temperature - ambient0), speedCooling = speed * (temperature - ambient0),
        opening = opening, fan = fan, idleHeat = idleHeat, ptoHeat = ptoHeat, hydraulicHeat = hydraulicHeat
    }
end

---Called on update: advances the engine, battery and oil temperatures, each on its own clock
-- @param float dt time of the step (ms)
-- @param boolean? updateEngine true to advance the engine
-- @param boolean? updateTransmission true to advance the oil
function RMS_Thermal:updateThermalSystems(dt, updateEngine, updateTransmission)
    local spec = self.spec_RealisticMechanicalSystems
    local safeDt = dt
    if safeDt <= 0 then
        return
    end
    local started = self:getIsMotorStarted()
    if updateEngine then RMS_Thermal.syncEngineProtection(self) end
    local inputs = RMS_Thermal.getNativeThermalInputs(self, started)
    local ambient = RMS_Utils.getAmbientTemperature()
    local worldTime = RMS_Thermal.getWorldTimeMS()
    RMS_Thermal.getEngineTemperature(self)
    spec.rawTransmissionTemperature = getTemperature(spec.rawTransmissionTemperature, getTemperature(spec.transmissionTemperature, ambient))
    spec.transmissionTemperature = getTemperature(spec.transmissionTemperature, spec.rawTransmissionTemperature)

    if updateEngine then
        local elapsed, previousAmbient = getRoleInterval(spec, "_thermalEngineWorldTime", "_thermalEngineAmbient", safeDt, started, ambient, worldTime)
        RMS_Thermal.updateEngineThermalModel(self, elapsed, spec, started, inputs.load, ambient, spec.radiatorClogging, previousAmbient, inputs)
        if spec.isElectricVehicle then
            local workDt = started and safeDt or 0
            local batteryDt, previousBatteryAmbient = getBatteryInterval(spec, workDt, ambient, worldTime, started)
            RMS_ElectricDrive.updateBatteryTemperature(self, workDt, ambient, batteryDt, previousBatteryAmbient, inputs)
        end
    end
    if updateTransmission then
        local elapsed, previousAmbient = getRoleInterval(spec, "_thermalOilWorldTime", "_thermalOilAmbient", safeDt, started, ambient, worldTime)
        RMS_Thermal.updateTransmissionThermalModel(self, elapsed, spec, started, inputs.load, inputs.rpm, ambient,
            spec.radiatorClogging, previousAmbient, inputs)
    end
end

---Mirrors the native engine state and eases the oil gauges
-- @param float dt time since the last frame (ms)
function RMS_Thermal:getSmoothedTemperature(dt)
    local spec = self.spec_RealisticMechanicalSystems
    local alpha = dt / (RMS_Config.THERMAL.TAU + dt)
    local ambient = RMS_Utils.getAmbientTemperature()
    ---Eases a shown temperature toward its raw value, a jump of 5 deg C at once
    -- @param string rawKey field of the raw temperature
    -- @param string displayKey field of the shown temperature
    local function smooth(rawKey, displayKey)
        local raw = getTemperature(spec[rawKey], ambient)
        local displayed = getTemperature(spec[displayKey], raw)
        spec[displayKey] = math.abs(raw - displayed) >= 5 and raw or displayed + alpha * (raw - displayed)
    end
    RMS_Thermal.getEngineTemperature(self)
    smooth("rawTransmissionTemperature", "transmissionTemperature")
    if RMS_Thermal.getHasSeparateHydraulicCircuit(spec) and isFinite(spec.rawHydraulicTemperature) then
        smooth("rawHydraulicTemperature", "hydraulicTemperature")
    end
end

---Advances the combustion or electric drive temperature
-- @param float dt interval (ms)
-- @param table spec RMS specialization of the vehicle
-- @param boolean isMotorStarted true while the engine runs
-- @param float motorLoad engine load
-- @param float ambient ambient temperature (deg C)
-- @param float dirt clogging of the radiator, 0 to 1
-- @param float ambientPrev ambient at the previous step (deg C)
-- @param table inputs native thermal inputs
function RMS_Thermal:updateEngineThermalModel(dt, spec, isMotorStarted, motorLoad, ambient, dirt, ambientPrev, inputs)
    local role = spec.isElectricVehicle and "evDrive" or "diesel"
    local temperature = RMS_Thermal.getEngineTemperature(self)
    local nextTemperature, values = RMS_Thermal.advanceRole(self, role, temperature, dt, ambientPrev, ambient, inputs, {
        fluidKey = "coolantLevel", thermostatHealth = spec.thermostatHealth, stuckPosition = spec.thermostatStuckedPosition,
        extraHeatRate = (spec.extraEngineHeat + spec.fluidEngineHeat)
            * RMS_Config.THERMAL.PROFILES[role].faultHeatScale
    })
    RMS_Thermal.setEngineTemperature(self, nextTemperature)
    spec.thermostatState = values.opening
    spec.engineHeatBalance = values
    RMS_Thermal.syncEngineProtection(self)
end

---Advances the oil sump, hydraulic work going to the circuit holding its oil
-- @param float dt interval (ms)
-- @param table spec RMS specialization of the vehicle
-- @param boolean isMotorStarted true while the engine runs
-- @param float motorLoad engine load
-- @param float motorRpm engine speed
-- @param float ambient ambient temperature (deg C)
-- @param float dirt clogging of the radiator, 0 to 1
-- @param float ambientPrev ambient at the previous step (deg C)
-- @param table inputs native thermal inputs
function RMS_Thermal:updateTransmissionThermalModel(dt, spec, isMotorStarted, motorLoad, motorRpm, ambient, dirt, ambientPrev, inputs)
    local common = spec.hasCommonSump
    local separateHydraulics = RMS_Thermal.getHasSeparateHydraulicCircuit(spec)
    if separateHydraulics then
        spec.rawHydraulicTemperature = getTemperature(spec.rawHydraulicTemperature, spec.rawTransmissionTemperature)
        spec.hydraulicTemperature = getTemperature(spec.hydraulicTemperature, spec.rawHydraulicTemperature)
    end
    local hydraulicFaultHeat = (spec.extraHydraulicHeat + spec.fluidHydraulicHeat)
        * RMS_Config.THERMAL.PROFILES.hydraulic.faultHeatScale * inputs.hydraulic
    local oilRole = common and "commonOil" or "separateTrans"
    local oilEnabled = spec.fluidCapacities.transmissionOil > 0
        and (getSystemEnabled(spec, "transmission") or (common and getSystemEnabled(spec, "hydraulics")))
    if oilEnabled then
        local temperature = getTemperature(spec.rawTransmissionTemperature, getTemperature(spec.transmissionTemperature, ambient))
        local nextTemperature, values = RMS_Thermal.advanceRole(self, oilRole, temperature,
            dt, ambientPrev, ambient, inputs, {
                fluidKey = "transmissionOilLevel", hydraulicActivity = common and inputs.hydraulic or 0,
                extraHeatRate = (spec.extraTransmissionHeat + spec.fluidTransmissionHeat)
                    * RMS_Config.THERMAL.PROFILES[oilRole].faultHeatScale + (common and hydraulicFaultHeat or 0)
            })
        spec.rawTransmissionTemperature = nextTemperature
        spec.transmissionThermostatState = values.opening
        spec.transmissionHeatBalance = values
    else
        spec.transmissionThermostatState = 0
    end
    if separateHydraulics then
        local temperature = spec.rawHydraulicTemperature
        spec.hydraulicTemperature = getTemperature(spec.hydraulicTemperature, temperature)
        local nextTemperature = RMS_Thermal.advanceRole(self, "hydraulic", temperature,
            dt, ambientPrev, ambient, inputs, {
                fluidKey = "hydraulicFluidLevel", hydraulicActivity = inputs.hydraulic, extraHeatRate = hydraulicFaultHeat
            })
        spec.rawHydraulicTemperature = nextTemperature
    end
end

---Returns a value checked finite, nonnegative when asked
-- @param string name name of the value, for the error
-- @param float value value
-- @param boolean nonnegative true to refuse a negative value
-- @return float value value
local function requireExactThermalInput(name, value, nonnegative)
    if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
        error(name .. " must be a finite number", 3)
    end
    if nonnegative and value < 0 then
        error(name .. " must be nonnegative", 3)
    end
    return value
end

---Returns the compensated sum of four terms
-- @param float a first term
-- @param float b second term
-- @param float c third term
-- @param float d fourth term
-- @return float sum sum
local function sumExactThermalTerms(a, b, c, d)
    local total, correction = 0, 0
    for _, value in ipairs({a, b, c, d}) do
        local nextTotal = total + value
        if math.abs(total) >= math.abs(value) then
            correction = correction + ((total - nextTotal) + value)
        else
            correction = correction + ((value - nextTotal) + total)
        end
        total = nextTotal
    end
    return total + correction
end

---Solves T' = h - k * (T - ambient(t)) over an affine ambient interval
-- @param float temperature temperature at the start (deg C)
-- @param float heatRate constant nonnegative heating rate in degrees Celsius per second
-- @param float coolingRate constant nonnegative cooling coefficient in inverse seconds
-- @param float dtSeconds interval (s)
-- @param float ambient0 ambient at the start (deg C)
-- @param float ambient1 ambient at the end (deg C)
-- @return float temperature temperature at the end (deg C)
function RMS_Thermal.integrateTemperatureExact(temperature, heatRate, coolingRate, dtSeconds, ambient0, ambient1)
    local initial = requireExactThermalInput("temperature", temperature, false)
    local heat = requireExactThermalInput("heatRate", heatRate, true)
    local cooling = requireExactThermalInput("coolingRate", coolingRate, true)
    local elapsed = requireExactThermalInput("dtSeconds", dtSeconds, true)
    local startAmbient = requireExactThermalInput("ambient0", ambient0, false)
    local endAmbient = requireExactThermalInput("ambient1", ambient1, false)

    if elapsed == 0 then
        return initial
    end
    if cooling == 0 then
        return requireExactThermalInput("result", initial + heat * elapsed, false)
    end

    local x = cooling * elapsed
    local rejectedFraction, ambientWeight, heating
    if x < 0.01 then
        -- Series expansion avoids cancellation near zero
        ambientWeight = x * (0.5 + x * (-1 / 6 + x * (1 / 24
            + x * (-1 / 120 + x * (1 / 720 - x / 5040)))))
        local phi = 1 - ambientWeight
        rejectedFraction = x * phi
        heating = heat * (elapsed * phi)
    else
        rejectedFraction = 1 - math.exp(-x)
        ambientWeight = 1 - rejectedFraction / x
        -- Preserve h/k when k*dt overflows
        heating = heat * (rejectedFraction / cooling)
    end

    local result
    if rejectedFraction <= 0.5 then
        result = sumExactThermalTerms(
            initial,
            (startAmbient - initial) * rejectedFraction,
            heating,
            (endAmbient - startAmbient) * ambientWeight
        )
    else
        -- Avoid subtracting the decaying initial state from itself
        result = sumExactThermalTerms(
            initial * math.exp(-x),
            startAmbient * rejectedFraction,
            heating,
            (endAmbient - startAmbient) * ambientWeight
        )
    end
    return requireExactThermalInput("result", result, false)
end

RMS_Thermal.REVERSIBLE_FAN = "rmsReversibleFan"

---Tells whether a store item may take the reversible fan option
-- @param table xmlFile file of the store item
-- @param table storeItem store item
-- @return boolean takesFan true when it may
function RMS_Thermal.getTakesReversibleFan(xmlFile, storeItem)
    if not xmlFile:hasProperty("vehicle.enterable") then
        return false
    end
    for _, categoryName in ipairs(storeItem.categoryNames) do
        if RMS_Config.DRIVETRAIN.EXCLUDED_CATEGORIES[string.upper(categoryName)] then
            return false
        end
    end
    local burnsFuel, usesDef = false, false
    local configurationIndex = 0
    while xmlFile:hasProperty(string.format("vehicle.motorized.consumerConfigurations.consumerConfiguration(%d)", configurationIndex)) do
        local consumerIndex = 0
        while true do
            local fillType = xmlFile:getString(string.format("vehicle.motorized.consumerConfigurations.consumerConfiguration(%d).consumer(%d)#fillType",
                configurationIndex, consumerIndex))
            if fillType == nil then
                break
            end
            fillType = string.upper(fillType)
            burnsFuel = burnsFuel or fillType == "DIESEL" or fillType == "METHANE"
            usesDef = usesDef or fillType == "DEF"
            consumerIndex = consumerIndex + 1
        end
        configurationIndex = configurationIndex + 1
    end
    return burnsFuel and RMS_ProductionYear.getRaisedYear(storeItem, usesDef) >= RMS_Config.THERMAL.REVERSIBLE_FAN.MIN_YEAR
end

---Registers the reversible fan option and adds it to the items taking it
function RMS_Thermal.registerReversibleFan()
    g_vehicleConfigurationManager:addConfigurationType(RMS_Thermal.REVERSIBLE_FAN,
        g_i18n:getText("rms_configuration_reversibleFan"), nil, VehicleConfigurationItem)

    ConfigurationUtil.getConfigurationsFromXML = Utils.overwrittenFunction(ConfigurationUtil.getConfigurationsFromXML,
        function(manager, superFunc, xmlFile, key, baseDir, customEnvironment, isMod, storeItem)
            local configurations, defaultConfigurationIds = superFunc(manager, xmlFile, key, baseDir, customEnvironment, isMod, storeItem)
            if manager ~= g_vehicleConfigurationManager or not RMS_Thermal.getTakesReversibleFan(xmlFile, storeItem) then
                return configurations, defaultConfigurationIds
            end

            local items = {}
            for index, text in ipairs({ "configuration_valueNo", "configuration_valueYes" }) do
                local item = VehicleConfigurationItem.new(RMS_Thermal.REVERSIBLE_FAN)
                item.name = g_i18n:getText(text)
                item.index = index
                item.saveId = tostring(index)
                item.isYesNoOption = true
                items[index] = item
            end
            items[1].isDefault = true
            items[2].price = RMS_Config.THERMAL.REVERSIBLE_FAN.KIT_PRICE

            configurations = configurations or {}
            defaultConfigurationIds = defaultConfigurationIds or {}
            defaultConfigurationIds[RMS_Thermal.REVERSIBLE_FAN] = ConfigurationUtil.getDefaultConfigIdFromItems(items)
            configurations[RMS_Thermal.REVERSIBLE_FAN] = items
            return configurations, defaultConfigurationIds
        end)
end

---Starts a fan reversal on a running engine
-- @param table vehicle vehicle
function RMS_Thermal.startFanReversal(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    if spec.hasReversibleFan and vehicle:getIsMotorStarted() then
        spec.fanReversalTime = RMS_Config.THERMAL.REVERSIBLE_FAN.REVERSAL_MS
        spec.fanRunningSinceReversal = 0
    end
end

---Called on update: runs the fan reversal, triggered on its interval on recent machines
-- @param float dt time of the step (ms)
function RMS_Thermal:updateFanReversal(dt)
    local spec = self.spec_RealisticMechanicalSystems
    if not spec.hasReversibleFan or not self:getIsMotorStarted() then
        if spec.fanReversalTime > 0 then
            spec.fanReversalTime = 0
            RealisticMechanicalSystems.raiseRMSDirty(self, RealisticMechanicalSystems.SYNC_GROUP.FIELDCARE)
        end
        return
    end
    if spec.fanReversalTime <= 0 then
        if spec.year >= RMS_Config.THERMAL.REVERSIBLE_FAN.AUTO_MIN_YEAR then
            spec.fanRunningSinceReversal = spec.fanRunningSinceReversal + dt
            if spec.fanRunningSinceReversal >= RMS_Config.THERMAL.REVERSIBLE_FAN.AUTO_INTERVAL_MS then
                RMS_Thermal.startFanReversal(self)
            end
        end
        return
    end
    spec.fanReversalTime = math.max(spec.fanReversalTime - dt, 0)
    spec.radiatorClogging = math.max(spec.radiatorClogging - RMS_Config.FIELD_CARE.CLEANING_SPEED / 1000 * dt, 0)
    RealisticMechanicalSystems.raiseRMSDirty(self, RealisticMechanicalSystems.SYNC_GROUP.FIELDCARE)
end
