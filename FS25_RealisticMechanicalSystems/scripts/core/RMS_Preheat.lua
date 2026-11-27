-- Copyright © 2026 Squallqt. All rights reserved.

---Diesel glow plugs: preheat time, lamps and cold start help
RMS_Preheat = {}

---Returns the engine temperature, falling back to ambient when it is unset
-- @param table vehicle vehicle
-- @return float temperature temperature (deg C)
function RMS_Preheat.getEngineTemperatureC(vehicle)
    local engineTemperature = vehicle.spec_RealisticMechanicalSystems.rawEngineTemperature
    local environmentTemperature = RMS_Utils.getAmbientTemperature()

    if engineTemperature <= -90 then
        return environmentTemperature
    end

    return RealisticMechanicalSystems.sanitizeNumber(engineTemperature, environmentTemperature, -80, 160)
end

---Returns the severity of the glow plug failure effect, 0 when absent
-- @param table vehicle vehicle
-- @return integer severity severity between 0 and 4
function RMS_Preheat.getGlowPlugFailureSeverity(vehicle)
    local effect = vehicle.spec_RealisticMechanicalSystems.activeEffects.GLOW_PLUG_FAILURE
    return effect ~= nil and math.floor(effect.value) or 0
end

---Tells whether the vehicle burns diesel
-- @param table vehicle vehicle
-- @return boolean isDiesel true for a diesel
function RMS_Preheat.isDieselVehicle(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    if spec.isDieselVehicle ~= nil then
        return spec.isDieselVehicle
    end

    local motorizedSpec = vehicle.spec_motorized
    if motorizedSpec.motor.maxRpm > RMS_Config.CORE.PETROL_ABOVE_MAX_RPM then
        return false
    end

    return motorizedSpec.consumersByFillType[FillType.DIESEL] ~= nil
end

---Interpolates the preheat duration on the configured temperature curve
-- @param table vehicle vehicle
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

    local index = 2
    while engineTemperature > curve[index][1] do
        index = index + 1
    end
    local previousPoint, currentPoint = curve[index - 1], curve[index]
    local alpha = (engineTemperature - previousPoint[1]) / (currentPoint[1] - previousPoint[1])
    return math.floor(previousPoint[2] + (currentPoint[2] - previousPoint[2]) * alpha + 0.5)
end

---Tells whether a diesel is cold enough to need its glow plugs
-- @param table vehicle vehicle
-- @return boolean isRequired true when it needs them
function RMS_Preheat.isColdStartAssistanceRequired(vehicle)
    return RMS_Preheat.isDieselVehicle(vehicle)
        and RMS_Preheat.getEngineTemperatureC(vehicle) < RMS_Config.PREHEAT.START_ASSIST_TEMPERATURE_C
end

---Tells whether the glow plugs are currently heating
-- @param table vehicle vehicle
-- @return boolean isHeating true while they heat
function RMS_Preheat.isHeating(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    return spec.startState == RMS_Start.STATE.PREHEATING and spec.preheatWasRequired
end

---Tells whether the dashboard lamp test is running
-- @param table vehicle vehicle
-- @return boolean isActive true while it runs
function RMS_Preheat.isLampTestActive(vehicle)
    return vehicle.spec_RealisticMechanicalSystems.preheatLampTestActive
end

---Tells whether failing glow plugs make this start hard
-- @param table vehicle vehicle
-- @return boolean isHard true for a hard start
function RMS_Preheat.shouldApplyGlowPlugHardStart(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    if spec.startState == RMS_Start.STATE.IDLE then
        return false
    end

    return spec.preheatWasRequired
        and RMS_Preheat.isColdStartAssistanceRequired(vehicle)
        and RMS_Preheat.getGlowPlugFailureSeverity(vehicle) > 0
end
