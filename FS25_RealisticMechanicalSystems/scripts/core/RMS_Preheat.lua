-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---Diesel glow plugs: preheat time, lamps and cold start help
RMS_Preheat = RMS_Preheat or {}

---Returns the engine temperature, falling back to ambient when it is unset
function RMS_Preheat.getEngineTemperatureC(vehicle)
    local spec = vehicle ~= nil and vehicle.spec_RealisticMechanicalSystems or nil
    local engineTemperature = spec ~= nil and tonumber(spec.rawEngineTemperature or spec.engineTemperature) or nil
    local environmentTemperature = RMS_Utils.getAmbientTemperature()

    if engineTemperature == nil or engineTemperature <= -90 then
        return environmentTemperature
    end

    return RealisticMechanicalSystems.sanitizeNumber(engineTemperature, environmentTemperature, -80, 160)
end

---Returns the severity of the glow plug failure effect, 0 when absent
-- @return integer severity severity between 0 and 4
function RMS_Preheat.getGlowPlugFailureSeverity(vehicle)
    local spec = vehicle ~= nil and vehicle.spec_RealisticMechanicalSystems or nil
    local effect = spec ~= nil and spec.activeEffects ~= nil and spec.activeEffects.GLOW_PLUG_FAILURE or nil
    return math.floor(RealisticMechanicalSystems.sanitizeNumber(effect ~= nil and effect.value or 0, 0, 0, 4))
end

---Tells whether the vehicle burns diesel
function RMS_Preheat.isDieselVehicle(vehicle)
    local spec = vehicle ~= nil and vehicle.spec_RealisticMechanicalSystems or nil
    if spec ~= nil and spec.isDieselVehicle ~= nil then
        return spec.isDieselVehicle
    end

    local motorizedSpec = vehicle ~= nil and vehicle.spec_motorized or nil
    if motorizedSpec == nil then
        return false
    end

    local motor = motorizedSpec.motor
    if motor ~= nil and motor.maxRpm > RMS_Config.CORE.PETROL_ABOVE_MAX_RPM then
        return false
    end

    return motorizedSpec.consumersByFillType ~= nil
        and motorizedSpec.consumersByFillType[FillType.DIESEL] ~= nil
end

---Interpolates the preheat duration on the configured temperature curve
-- @return integer duration preheat duration in ms, 0 above the activation temperature
function RMS_Preheat.getRequiredDurationMs(vehicle)
    if not RMS_Preheat.isDieselVehicle(vehicle) then
        return 0
    end

    local curve = RMS_Config.PREHEAT.WAIT_TIME_CURVE
    local engineTemperature = RMS_Preheat.getEngineTemperatureC(vehicle)

    if engineTemperature >= RMS_Config.PREHEAT.ACTIVATION_TEMPERATURE_C then
        return 0
    end

    if engineTemperature <= curve[1][1] then
        return curve[1][2]
    end

    for index = 2, #curve do
        local previousPoint = curve[index - 1]
        local currentPoint = curve[index]
        if engineTemperature <= currentPoint[1] then
            local temperatureRange = currentPoint[1] - previousPoint[1]
            if temperatureRange <= 0 then
                return currentPoint[2]
            end

            local alpha = (engineTemperature - previousPoint[1]) / temperatureRange
            return math.max(math.floor(previousPoint[2] + (currentPoint[2] - previousPoint[2]) * alpha + 0.5), 0)
        end
    end

    return 0
end

function RMS_Preheat.isColdStartAssistanceRequired(vehicle)
    return RMS_Preheat.isDieselVehicle(vehicle)
        and RMS_Preheat.getEngineTemperatureC(vehicle) < RMS_Config.PREHEAT.START_ASSIST_TEMPERATURE_C
end

---Tells whether the glow plugs are currently heating
function RMS_Preheat.isHeating(vehicle)
    local spec = vehicle ~= nil and vehicle.spec_RealisticMechanicalSystems or nil
    return spec ~= nil and spec.startState == RMS_Start.STATE.PREHEATING and spec.preheatWasRequired == true
end

---Tells whether the dashboard lamp test is running
function RMS_Preheat.isLampTestActive(vehicle)
    local spec = vehicle ~= nil and vehicle.spec_RealisticMechanicalSystems or nil
    return spec ~= nil and spec.preheatLampTestActive == true
end

---Tells whether failing glow plugs make this start hard
function RMS_Preheat.shouldApplyGlowPlugHardStart(vehicle)
    local spec = vehicle ~= nil and vehicle.spec_RealisticMechanicalSystems or nil
    if spec == nil or spec.startState == RMS_Start.STATE.IDLE then
        return false
    end

    return spec.preheatWasRequired == true
        and RMS_Preheat.isColdStartAssistanceRequired(vehicle)
        and RMS_Preheat.getGlowPlugFailureSeverity(vehicle) > 0
end
