-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---Engine, oil and traction-battery temperatures.
RMS_Thermal = RMS_Thermal or {}

local sanitizeNumber = RealisticMechanicalSystems.sanitizeNumber
local DAY_MS = 24 * 60 * 60 * 1000

---
local function isFinite(value)
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

---
local function getTemperature(value, fallback)
    if isFinite(value) and value ~= -99 then
        return value
    end
    return fallback
end

---
local function getSystemEnabled(spec, key)
    local system = spec.systems ~= nil and spec.systems[key] or nil
    return system == nil or system.enabled ~= false
end

---Returns the drive limits used by temperature consumers
function RMS_Thermal.getDriveValues(spec)
    return spec.isElectricVehicle and RMS_Config.ELECTRIC_DRIVE.THERMAL or RMS_Config.THERMAL
end

---Returns the monotonic in-world time in ms, nil without the native clock
function RMS_Thermal.getWorldTimeMS()
    local environment = g_currentMission.environment
    if not isFinite(environment.currentMonotonicDay) or not isFinite(environment.dayTime) then
        return nil
    end
    local time = environment.currentMonotonicDay * DAY_MS + environment.dayTime
    return isFinite(time) and time or nil
end

---Tells whether the vehicle has a separate hydraulic oil circuit
function RMS_Thermal.getHasSeparateHydraulicCircuit(spec)
    return spec ~= nil and spec.hasCommonSump ~= true and getSystemEnabled(spec, "hydraulics")
        and sanitizeNumber(spec.fluidCapacities ~= nil and spec.fluidCapacities.hydraulicFluid or nil, 0, 0) > 0
end

---Reads native load, real rpm and applied power against the native peak
function RMS_Thermal.getNativeThermalInputs(vehicle, isMotorStarted)
    local spec = vehicle.spec_RealisticMechanicalSystems
    local motor = vehicle:getMotor()
    local load = sanitizeNumber(vehicle:getMotorLoadPercentage(), 0, 0, 1.5) * RMS_Thermal.getEngineTorqueFactor(vehicle)
    local maxRpm = sanitizeNumber(motor:getMaxRpm(), 0, 0)
    local rpm = maxRpm > 0 and sanitizeNumber(motor:getLastRealMotorRpm() / maxRpm, 0, 0, 1.5) or 0
    local ratedRpm = sanitizeNumber(motor.peakMotorPowerRotSpeed, 0, 0) * 30 / math.pi
    local fanSpeed = ratedRpm > 0 and sanitizeNumber(motor:getLastRealMotorRpm() / ratedRpm, 0, 0, 1) or 0
    local applied = sanitizeNumber(motor:getMotorAppliedTorque(), 0, 0)
    local peakPower = sanitizeNumber(motor.peakMotorPower, 0, 0)
    local rotation = motor.getMotorRotSpeed ~= nil and sanitizeNumber(motor:getMotorRotSpeed(), 0, 0) or nil
    local power = peakPower > 0 and rotation ~= nil and applied * rotation / peakPower or nil
    if not isFinite(power) then power = nil end
    local external = sanitizeNumber(motor:getMotorExternalTorque(), 0, 0)
    local externalShare = applied > 0 and math.clamp(external / math.max(applied, external), 0, 1) or 0
    local externalLoad = load * externalShare
    return {
        motorStarted = isMotorStarted == true,
        load = load, rpm = rpm, fanSpeed = fanSpeed, power = power, external = externalLoad, drive = load - externalLoad,
        speed = math.clamp(math.abs(sanitizeNumber(vehicle:getLastSpeed(), 0)) / 50, 0, 1),
        hydraulic = spec.isHydraulicActive and getSystemEnabled(spec, "hydraulics") and 1 or 0
    }
end

---Returns the native engine state when RMS owns its temperature
local function getManagedMotorTemperature(vehicle)
    local spec = vehicle ~= nil and vehicle.spec_RealisticMechanicalSystems or nil
    local motorized = vehicle ~= nil and vehicle.spec_motorized or nil
    if spec == nil or spec.isExcludedVehicle or motorized == nil
        or RMS_Utils.hasCVTAddon(vehicle) then
        return nil
    end
    return motorized.motorTemperature
end

---Selects the shared ECU profile of native diesel engines managed by RMS
function RMS_Thermal.getUsesEngineProtection(vehicle)
    local spec = vehicle ~= nil and vehicle.spec_RealisticMechanicalSystems or nil
    local motorized = vehicle ~= nil and vehicle.spec_motorized or nil
    local consumers = motorized ~= nil and motorized.consumersByFillTypeName or nil
    return spec ~= nil and not spec.isElectricVehicle and getManagedMotorTemperature(vehicle) ~= nil
        and consumers ~= nil and consumers.DIESEL ~= nil and RMS_Utils.getUsesEngineECUProfile(vehicle)
end

---Returns the thermal torque fraction, apart from wear and engine faults
function RMS_Thermal.getEngineTorqueFactor(vehicle)
    if not RMS_Thermal.getUsesEngineProtection(vehicle) then return 1 end
    local spec = vehicle.spec_RealisticMechanicalSystems
    local effect = spec.activeEffects ~= nil and spec.activeEffects.ENGINE_THERMAL_TORQUE_LIMIT or nil
    return effect ~= nil and sanitizeNumber(effect.value, 1, 0.2, 1) or 1
end

---Updates the engine protection from the shared temperature, in two levels
function RMS_Thermal.syncEngineProtection(vehicle)
    local spec = vehicle ~= nil and vehicle.spec_RealisticMechanicalSystems or nil
    local config = RMS_Config.THERMAL.ENGINE_PROTECTION
    if spec == nil or not vehicle.isServer or config == nil or type(spec.activeBreakdowns) ~= "table" then return end
    local id = "ENGINE_THERMAL_PROTECTION"
    local current = spec.activeBreakdowns[id]
    local previousStage = current ~= nil and sanitizeNumber(current.stage, 1, 1, 2) or 0
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
function RMS_Thermal.setEngineTemperature(vehicle, temperature)
    local spec = vehicle ~= nil and vehicle.spec_RealisticMechanicalSystems or nil
    if spec == nil or getTemperature(temperature, nil) == nil then return end
    local native = getManagedMotorTemperature(vehicle)
    if native ~= nil then
        native.value = temperature
    end
    spec.rawEngineTemperature = temperature
    spec.engineTemperature = temperature
    return temperature
end

function RMS_Thermal.initializeEngineTemperature(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    return RMS_Thermal.setEngineTemperature(vehicle,
        getTemperature(spec.engineTemperature, getTemperature(spec.rawEngineTemperature, RMS_Utils.getAmbientTemperature())))
end

---Reads the shared native engine temperature
function RMS_Thermal.getEngineTemperature(vehicle)
    local spec = vehicle ~= nil and vehicle.spec_RealisticMechanicalSystems or nil
    if spec == nil then return RMS_Utils.getAmbientTemperature() end
    local native = getManagedMotorTemperature(vehicle)
    local fallback = getTemperature(spec.rawEngineTemperature, getTemperature(spec.engineTemperature, RMS_Utils.getAmbientTemperature()))
    local temperature = native ~= nil and getTemperature(native.value, fallback) or fallback
    if vehicle.isServer and native ~= nil and getTemperature(spec.rawEngineTemperature, nil) ~= nil
        and temperature ~= spec.rawEngineTemperature then
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

---Keeps Dashboard Live's other events while RMS owns the engine temperature
function RMS_Thermal.registerDashboardLiveCompatibility(vehicleType)
    local listeners = vehicleType.eventListeners or {}
    for _, eventName in ipairs({ "onLoadFinished", "onEnterVehicle", "onUpdateTick" }) do
        for index, listener in ipairs(listeners[eventName] or {}) do
            if listener.MOD_NAME == "FS25_DashboardLive" and not listener.rmsThermalAdapter then
                local original = listener[eventName]
                listeners[eventName][index] = setmetatable({ rmsThermalAdapter = true,
                    [eventName] = function(vehicle, ...)
                        if getManagedMotorTemperature(vehicle) == nil then
                            return original(vehicle, ...)
                        end
                        local temperature = RMS_Thermal.getEngineTemperature(vehicle)
                        if vehicle.spec_DashboardLive ~= nil then
                            vehicle.spec_DashboardLive.motorTemperature = temperature
                        end
                        original(vehicle, ...)
                        RMS_Thermal.setEngineTemperature(vehicle, temperature)
                        if vehicle.spec_DashboardLive ~= nil then
                            vehicle.spec_DashboardLive.motorTemperature = temperature
                        end
                    end
                }, { __index = listener })
            end
        end
    end
end

---Selects operating time while running, world time while stopped
local function getRoleInterval(spec, trackerKey, ambientKey, dtOperating, isMotorStarted, ambient, worldTime)
    local previousAmbient = getTemperature(spec[ambientKey], ambient)
    local elapsed = dtOperating
    if worldTime ~= nil then
        local previousTime = spec[trackerKey]
        if not isMotorStarted then
            elapsed = isFinite(previousTime) and math.max(worldTime - previousTime, 0) or 0
        end
        spec[trackerKey] = worldTime
    else
        spec[trackerKey] = nil
    end
    spec[ambientKey] = ambient
    return elapsed, previousAmbient
end

---
local function getBatteryInterval(spec, dtOperating, ambient, worldTime, isMotorStarted)
    local previousAmbient = getTemperature(spec._thermalBatteryAmbient, ambient)
    local previousTime = spec._thermalBatteryWorldTime
    local observation = spec.tractionBatteryChargeObservation
    local chargingMS = observation ~= nil and sanitizeNumber(observation.elapsedMS, 0, 0) or 0
    local elapsedWorld = 0
    if worldTime ~= nil then
        elapsedWorld = isFinite(previousTime) and math.max(worldTime - previousTime, 0) or 0
        spec._thermalBatteryWorldTime = worldTime
    else
        spec._thermalBatteryWorldTime = nil
    end
    local elapsed = math.max(isMotorStarted and dtOperating or elapsedWorld, chargingMS)
    if not isMotorStarted and worldTime ~= nil and isFinite(previousTime) and elapsedWorld == 0 then
        elapsed = 0
    end
    spec._thermalBatteryAmbient = ambient
    return elapsed, previousAmbient
end

---
local function getOpening(profile, temperature, health, stuckPosition)
    if stuckPosition ~= nil then
        return sanitizeNumber(stuckPosition, 0, 0, 1)
    end
    local range = profile.regulatedMax - profile.regulatedMin
    assert(isFinite(range) and range > 0, "RMS thermal regulation range must be positive")
    return math.clamp((temperature - profile.regulatedMin) / range, 0, 1)
        * sanitizeNumber(health, 1, 0, 1)
end

---
local function getExchangeFactor(spec, fluidKey, dirt)
    local radiator = getSystemEnabled(spec, "cooling") and sanitizeNumber(spec.radiatorHealth, 1, 0, 1) or 1
    local fluid = fluidKey ~= nil and sanitizeNumber(spec[fluidKey], 1, 0, 1) or 1
    return (1 - dirt * dirt) * radiator * fluid
end

local function getFanAirflow(spec, inputs)
    if spec.isElectricVehicle then
        return 1
    end
    if sanitizeNumber(spec.fanReversalTime, 0, 0) > 0 then
        return 0
    end
    return inputs.fanSpeed ^ RMS_Config.THERMAL.FAN_AIRFLOW_EXPONENT
end

---Interpolates the common warm-up fit, the nearest rates outside it
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
function RMS_Thermal.advanceRole(vehicle, role, temperature, dtMS, ambient0, ambient1, inputs, options)
    local profile = assert(RMS_Config.THERMAL.PROFILES ~= nil and RMS_Config.THERMAL.PROFILES[role], "Missing RMS thermal role profile: " .. role)
    local spec = vehicle.spec_RealisticMechanicalSystems
    options = options or {}
    local elapsed = sanitizeNumber(dtMS, 0, 0) / 1000
    local workShare = options.workShare ~= nil and sanitizeNumber(options.workShare, 0, 0, 1)
        or (inputs.motorStarted and 1 or 0)
    local responseRate = inputs.motorStarted and sanitizeNumber(profile.activeResponseRate, 1, 0.01) or 1
    local idleHeat = profile.heatIdle * workShare
    local ptoHeat = profile.heatExternal * inputs.external * workShare
    local hydraulicHeat = profile.heatHydraulic * (options.hydraulicActivity or 0) * workShare
    local heat = (profile.heatIdle + profile.heatLoad * inputs.load + profile.heatRpm * inputs.rpm
        + profile.heatDrive * inputs.drive + profile.heatExternal * inputs.external
        + profile.heatHydraulic * (options.hydraulicActivity or 0)) * workShare
    local passiveRate = profile.passiveCooling
    if role == "diesel" and inputs.motorStarted and profile.warmup ~= nil and isFinite(inputs.power)
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

    local dirt = sanitizeNumber(spec.radiatorClogging, 0, 0, 1)
    local exchange = getExchangeFactor(spec, options.fluidKey, dirt)
    local active = inputs.motorStarted
    if options.forcedActive ~= nil then active = options.forcedActive end
    local opening = active and getOpening(profile, temperature, options.thermostatHealth, options.stuckPosition) or 0
    local fan = active and sanitizeNumber(spec.fanClutchHealth, 1, 0, 1) * getFanAirflow(spec, inputs) or 0
    local passive = passiveRate * responseRate
    local speed = profile.speedCooling * inputs.speed * responseRate
    local forced = profile.forcedCooling * opening * exchange * fan * responseRate
    local coolingRate = passive + speed + forced
    local nextTemperature = RMS_Thermal.integrateTemperatureExact(temperature, heat, coolingRate, elapsed, ambient0, ambient1)
    return nextTemperature, {
        totalHeat = heat, totalCooling = coolingRate * (temperature - ambient0),
        radiatorCooling = forced * (temperature - ambient0), coolerCooling = forced * (temperature - ambient0),
        convectionCooling = passive * (temperature - ambient0), speedCooling = speed * (temperature - ambient0),
        coolingRate = coolingRate, forcedCoolingRate = forced, passiveCoolingRate = passive, speedCoolingRate = speed,
        opening = opening, fan = fan, idleHeat = idleHeat, ptoHeat = ptoHeat, hydraulicHeat = hydraulicHeat,
        loadFactor = inputs.drive, externalLoad = inputs.external, nativeLoad = inputs.load, rpmRatio = inputs.rpm,
        elapsedMS = elapsed * 1000
    }
end

---Runs each role on its own clock, the battery at the engine phase boundary
function RMS_Thermal:updateThermalSystems(dt, updateEngine, updateTransmission)
    local spec = self.spec_RealisticMechanicalSystems
    local safeDt = sanitizeNumber(dt, 0, 0)
    if spec == nil or not self.isServer or safeDt <= 0 or self:getMotor() == nil then
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
            if worldTime == nil then
                local observation = spec.tractionBatteryChargeObservation
                local chargingDt = observation ~= nil and sanitizeNumber(observation.elapsedMS, 0, 0) or 0
                batteryDt = math.max(batteryDt, safeDt, chargingDt)
            end
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
function RMS_Thermal:getSmoothedTemperature(dt)
    local spec = self.spec_RealisticMechanicalSystems
    local safeDt = sanitizeNumber(dt, 0, 0)
    if spec == nil or safeDt <= 0 then return end
    local alpha = safeDt / (RMS_Config.THERMAL.TAU + safeDt)
    local ambient = RMS_Utils.getAmbientTemperature()
    ---
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
function RMS_Thermal:updateEngineThermalModel(dt, spec, isMotorStarted, motorLoad, ambient, dirt, ambientPrev, inputs)
    inputs = inputs or RMS_Thermal.getNativeThermalInputs(self, isMotorStarted)
    local role = spec.isElectricVehicle and "evDrive" or "diesel"
    local temperature = RMS_Thermal.getEngineTemperature(self)
    local nextTemperature, values = RMS_Thermal.advanceRole(self, role, temperature, dt, ambientPrev or ambient, ambient, inputs, {
        fluidKey = "coolantLevel", thermostatHealth = spec.thermostatHealth, stuckPosition = spec.thermostatStuckedPosition,
        extraHeatRate = (sanitizeNumber(spec.extraEngineHeat, 0) + sanitizeNumber(spec.fluidEngineHeat, 0))
            * RMS_Config.THERMAL.PROFILES[role].faultHeatScale
    })
    RMS_Thermal.setEngineTemperature(self, nextTemperature)
    spec.thermostatState = values.opening
    spec.engineHeatBalance = values
    RMS_Thermal.syncEngineProtection(self)
end

---Advances the oil sump, hydraulic work going to the circuit holding its oil
function RMS_Thermal:updateTransmissionThermalModel(dt, spec, isMotorStarted, motorLoad, motorRpm, ambient, dirt, ambientPrev, inputs)
    inputs = inputs or RMS_Thermal.getNativeThermalInputs(self, isMotorStarted)
    local common = spec.hasCommonSump == true
    local separateHydraulics = RMS_Thermal.getHasSeparateHydraulicCircuit(spec)
    if separateHydraulics then
        spec.rawHydraulicTemperature = getTemperature(spec.rawHydraulicTemperature, spec.rawTransmissionTemperature)
        spec.hydraulicTemperature = getTemperature(spec.hydraulicTemperature, spec.rawHydraulicTemperature)
    end
    local hydraulicFaultHeat = (sanitizeNumber(spec.extraHydraulicHeat, 0) + sanitizeNumber(spec.fluidHydraulicHeat, 0))
        * RMS_Config.THERMAL.PROFILES.hydraulic.faultHeatScale * inputs.hydraulic
    local oilRole = common and "commonOil" or "separateTrans"
    local oilCapacity = sanitizeNumber(spec.fluidCapacities ~= nil and spec.fluidCapacities.transmissionOil or nil, 0, 0)
    local oilEnabled = oilCapacity > 0
        and (getSystemEnabled(spec, "transmission") or (common and getSystemEnabled(spec, "hydraulics")))
    if oilEnabled then
        local temperature = getTemperature(spec.rawTransmissionTemperature, getTemperature(spec.transmissionTemperature, ambient))
        local nextTemperature, values = RMS_Thermal.advanceRole(self, oilRole, temperature,
            dt, ambientPrev or ambient, ambient, inputs, {
                fluidKey = "transmissionOilLevel", thermostatHealth = spec.transmissionThermostatHealth,
                stuckPosition = spec.transmissionThermostatStuckedPosition, hydraulicActivity = common and inputs.hydraulic or 0,
                extraHeatRate = (sanitizeNumber(spec.extraTransmissionHeat, 0) + sanitizeNumber(spec.fluidTransmissionHeat, 0))
                    * RMS_Config.THERMAL.PROFILES[oilRole].faultHeatScale + (common and hydraulicFaultHeat or 0)
            })
        spec.rawTransmissionTemperature = nextTemperature
        spec.transmissionThermostatState = values.opening
        values.extraTransmissionHeat = spec.extraTransmissionHeat or 0
        spec.transmissionHeatBalance = values
    else
        spec.transmissionThermostatState = 0
    end
    if separateHydraulics then
        local temperature = spec.rawHydraulicTemperature
        spec.hydraulicTemperature = getTemperature(spec.hydraulicTemperature, temperature)
        local nextTemperature = RMS_Thermal.advanceRole(self, "hydraulic", temperature,
            dt, ambientPrev or ambient, ambient, inputs, {
                fluidKey = "hydraulicFluidLevel", hydraulicActivity = inputs.hydraulic, extraHeatRate = hydraulicFaultHeat
            })
        spec.rawHydraulicTemperature = nextTemperature
    end
end

---Requires a finite number, without coercion or fallback
local function requireExactThermalInput(name, value, nonnegative)
    if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
        error(name .. " must be a finite number", 3)
    end
    if nonnegative and value < 0 then
        error(name .. " must be nonnegative", 3)
    end
    return value
end

---Adds four finite terms keeping the small ones
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
-- @param float temperature initial temperature in degrees Celsius
-- @param float heatRate constant nonnegative heating rate in degrees Celsius per second
-- @param float coolingRate constant nonnegative cooling coefficient in inverse seconds
-- @param float dtSeconds nonnegative elapsed time in seconds
-- @param float ambient0 ambient temperature at the start of the interval
-- @param float ambient1 ambient temperature at the end of the interval
-- @return float temperature final temperature, without clamping to ambient
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
        -- Series expansion avoids cancellation near zero.
        ambientWeight = x * (0.5 + x * (-1 / 6 + x * (1 / 24
            + x * (-1 / 120 + x * (1 / 720 - x / 5040)))))
        local phi = 1 - ambientWeight
        rejectedFraction = x * phi
        heating = heat * (elapsed * phi)
    else
        rejectedFraction = 1 - math.exp(-x)
        ambientWeight = 1 - rejectedFraction / x
        -- Preserve h/k when k*dt overflows.
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
        -- Avoid subtracting the decaying initial state from itself.
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

-- @param XMLFile xmlFile vehicle xml file
-- @param table storeItem store item
-- @return boolean takesFan true when the fan suits the machine and its era
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

-- @param table vehicle vehicle
function RMS_Thermal.startFanReversal(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    if spec.hasReversibleFan and vehicle:getIsMotorStarted() then
        spec.fanReversalTime = RMS_Config.THERMAL.REVERSIBLE_FAN.REVERSAL_MS
        spec.fanRunningSinceReversal = 0
    end
end

-- @param float dt time since last call in ms
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
        -- an older fan reverses only from the cab
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
