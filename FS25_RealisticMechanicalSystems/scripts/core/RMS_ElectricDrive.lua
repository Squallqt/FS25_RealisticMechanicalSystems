-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---Electric vehicles: temperature of the traction battery and what the cold does to it
RMS_ElectricDrive = RMS_ElectricDrive or {}

local COLD_BATTERY_ID = "COLD_TRACTION_BATTERY"

---Counts the thresholds a temperature has gone past, in the order they are met
-- @param float temperature temperature in degrees
-- @param table thresholds thresholds, rising for heat and falling for cold
-- @return integer stage thresholds passed, 0 before the first
function RMS_ElectricDrive.getTemperatureStage(temperature, thresholds)
    local isRising = thresholds[#thresholds] > thresholds[1]
    local stage = 0
    for index, threshold in ipairs(thresholds) do
        if (isRising and temperature > threshold) or (not isRising and temperature < threshold) then
            stage = index
        end
    end
    return stage
end

---Returns the share of its original capacity a traction battery holds
-- @param float condition condition of the traction battery from 0 to 1
-- @param float lostToCells share failed cells take on top of the wear, 0 or negative
-- @return float share share between the faded capacity and 1
function RMS_ElectricDrive.getCapacityShare(condition, lostToCells)
    local share = (1 - (1 - condition) * RMS_Config.ELECTRIC_DRIVE.BATTERY_CAPACITY_FADE) * (1 + lostToCells)
    return math.floor(share * 1000 + 0.5) / 1000
end

---Returns the capacity share the traction battery of a vehicle still holds
-- @param table vehicle vehicle
-- @return float factor share between the faded capacity and 1
function RMS_ElectricDrive.getCapacityFactor(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    local cellFault = spec.activeEffects.TRACTION_BATTERY_CAPACITY_MODIFIER
    return RMS_ElectricDrive.getCapacityShare(spec.systems.fuel.condition, cellFault ~= nil and cellFault.value or 0)
end

---Gives the traction battery the capacity its wear leaves it
-- @param table vehicle vehicle
function RMS_ElectricDrive.applyBatteryCapacity(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    local fillUnitIndex = vehicle:getConsumerFillUnitIndex(FillType.ELECTRICCHARGE)
    local capacity = spec.tractionBatteryNominalCapacity * RMS_ElectricDrive.getCapacityFactor(vehicle)

    -- the server tells the clients in game, a joining one works it out from the wear
    vehicle:setFillUnitCapacity(fillUnitIndex, capacity, not vehicle.isServer)

    if vehicle.isServer then
        local surplus = vehicle:getFillUnitFillLevel(fillUnitIndex) - capacity
        if surplus > 0 then
            vehicle:addFillUnitFillLevel(vehicle:getOwnerFarmId(), fillUnitIndex, -surplus, FillType.ELECTRICCHARGE, ToolType.UNDEFINED)
        end
    end
end

---Records the original capacity of the traction battery, then applies its wear
-- @param table vehicle vehicle
function RMS_ElectricDrive.initBatteryCapacity(vehicle)
    local fillUnitIndex = vehicle:getConsumerFillUnitIndex(FillType.ELECTRICCHARGE)
    vehicle.spec_RealisticMechanicalSystems.tractionBatteryNominalCapacity = vehicle:getFillUnitCapacity(fillUnitIndex)
    RMS_ElectricDrive.applyBatteryCapacity(vehicle)
end

---Returns the share of a station's power the cells accept at a temperature
local function getColdChargeAcceptance(temperature)
    local curve = RMS_Config.ELECTRIC_DRIVE.CHARGE_ACCEPTANCE_CURVE
    if temperature <= curve[1][1] then
        return curve[1][2]
    end
    for index = 2, #curve do
        local low, high = curve[index - 1], curve[index]
        if temperature <= high[1] then
            return low[2] + (high[2] - low[2]) * (temperature - low[1]) / (high[1] - low[1])
        end
    end
    return curve[#curve][2]
end

---Returns the share of a station's power a fill unit takes
-- @param table object object a load trigger is filling
-- @param integer fillUnitIndex fill unit the trigger fills
-- @return float acceptance share between 0 and 1, 1 for anything but the traction battery of an electric
function RMS_ElectricDrive.getChargeAcceptance(object, fillUnitIndex)
    local spec = object.spec_RealisticMechanicalSystems
    if spec == nil or spec.isExcludedVehicle or not spec.isElectricVehicle
            or fillUnitIndex ~= object:getConsumerFillUnitIndex(FillType.ELECTRICCHARGE) then
        return 1
    end

    spec.tractionBatteryChargeTime = g_currentMission.time

    -- a failing on-board charger passes on only part of what the cells would take
    local chargerFault = spec.activeEffects.CHARGE_ACCEPTANCE_MODIFIER
    local chargerShare = chargerFault ~= nil and math.max(1 + chargerFault.value, 0) or 1
    return getColdChargeAcceptance(spec.tractionBatteryTempC) * chargerShare
end

---Tells whether a native fill-unit value is finite
local function isFiniteChargeValue(value)
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

---Snapshots a server charging interval before the station updates the fill unit
local function getChargeObservationInputs(trigger, object, dt)
    local spec = object.spec_RealisticMechanicalSystems
    local fillUnitIndex = trigger.fillUnitIndex
    if not object.isServer or spec == nil or spec.isExcludedVehicle or not spec.isElectricVehicle
            or trigger.selectedFillType ~= FillType.ELECTRICCHARGE
            or fillUnitIndex ~= object:getConsumerFillUnitIndex(FillType.ELECTRICCHARGE) then
        return nil
    end

    local capacity = object:getFillUnitCapacity(fillUnitIndex)
    local level = object:getFillUnitFillLevel(fillUnitIndex)
    if not isFiniteChargeValue(capacity) or capacity <= 0 or not isFiniteChargeValue(level)
            or not isFiniteChargeValue(dt) or dt < 0 then
        return nil
    end

    local elapsedMS = dt
    if trigger.useTimeScale then
        elapsedMS = elapsedMS * g_currentMission:getEffectiveTimeScale()
    end
    if not isFiniteChargeValue(elapsedMS) or elapsedMS < 0 then
        return nil
    end
    return level, capacity, elapsedMS
end

---Records the positive native fill-level change of an interval
local function recordChargeObservation(object, fillUnitIndex, levelBefore, capacity, elapsedMS)
    local spec = object.spec_RealisticMechanicalSystems
    local observation = spec.tractionBatteryChargeObservation
    if observation == nil then
        observation = { energy = 0, capacityShare = 0, elapsedMS = 0 }
        spec.tractionBatteryChargeObservation = observation
    end
    observation.elapsedMS = observation.elapsedMS + elapsedMS

    local levelAfter = object:getFillUnitFillLevel(fillUnitIndex)
    if isFiniteChargeValue(levelAfter) and levelAfter > levelBefore then
        local accepted = levelAfter - levelBefore
        observation.energy = observation.energy + accepted
        observation.capacityShare = observation.capacityShare + accepted / capacity
    end
end

---Consumes the transient charging observations
-- @param table vehicle vehicle
-- @return float energy positive amount accepted in native ELECTRICCHARGE fill units
-- @return float capacityShare sum of accepted amount divided by each interval's effective capacity
-- @return float elapsedMS charging interval duration, following the load trigger's time scale
function RMS_ElectricDrive.consumeChargeObservation(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    local observation = spec ~= nil and spec.tractionBatteryChargeObservation or nil
    if observation == nil then
        return 0, 0, 0
    end
    spec.tractionBatteryChargeObservation = nil
    return observation.energy, observation.capacityShare, observation.elapsedMS
end

---Runs a load trigger, slicing the energy a slowed traction battery takes
-- @param table trigger load trigger
-- @param function superFunc super function
-- @param float dt time since last call in ms
function RMS_ElectricDrive.updateLoadTrigger(trigger, superFunc, dt)
    local object = trigger.currentFillableObject
    if not trigger.isServer or not trigger.isLoading or object == nil then
        return superFunc(trigger, dt)
    end

    local fillUnitIndex = trigger.fillUnitIndex
    local levelBefore, capacity, elapsedMS = getChargeObservationInputs(trigger, object, dt)
    ---
    local function finishCharge(...)
        if levelBefore ~= nil then
            recordChargeObservation(object, fillUnitIndex, levelBefore, capacity, elapsedMS)
        end
        return ...
    end

    local acceptance = RMS_ElectricDrive.getChargeAcceptance(object, trigger.fillUnitIndex)
    if acceptance >= 1 then
        trigger.rmsChargeBudget = 0
        return finishCharge(superFunc(trigger, dt))
    elseif acceptance <= 0 then
        trigger:setIsLoading(false)
        return finishCharge()
    end

    local delta = trigger.fillLitersPerMS * acceptance * dt
    if trigger.useTimeScale then
        delta = delta * g_currentMission:getEffectiveTimeScale()
    end
    trigger.rmsChargeBudget = (trigger.rmsChargeBudget or 0) + delta

    if trigger.rmsChargeBudget >= RMS_Config.ELECTRIC_DRIVE.CHARGE_SLICE then
        local fillDelta = trigger.source:addFillLevelToFillableObject(object, trigger.fillUnitIndex, trigger.selectedFillType,
            trigger.rmsChargeBudget, trigger.dischargeInfo, ToolType.TRIGGER)
        trigger.rmsChargeBudget = 0
        if fillDelta == nil or math.abs(fillDelta) < 0.0001 then
            trigger:setIsLoading(false)
        end
    end
    trigger:raiseActive()
    finishCharge()
end

---Tells whether the traction battery is taking charge from a station
-- @param table vehicle vehicle
-- @return boolean isCharging true while a station fills it
function RMS_ElectricDrive.getIsCharging(vehicle)
    local chargeTime = vehicle.spec_RealisticMechanicalSystems.tractionBatteryChargeTime
    return chargeTime ~= nil and g_currentMission.time - chargeTime < 1000
end

---Advances the traction battery through the common role kernel
-- @param table vehicle vehicle
-- @param float dtOperatingMS running time represented by this interval, in milliseconds
-- @param float ambientC current ambient temperature in degrees Celsius
-- @param float? dtBatteryMS total elapsed battery interval, in milliseconds; operating dt is the compatibility fallback
-- @param float? ambientPrev previous ambient sample
-- @param table? inputs native thermal input snapshot
function RMS_ElectricDrive.updateBatteryTemperature(vehicle, dtOperatingMS, ambientC, dtBatteryMS, ambientPrev, inputs)
    local spec = vehicle.spec_RealisticMechanicalSystems
    local operating = RealisticMechanicalSystems.sanitizeNumber(dtOperatingMS, 0, 0)
    local elapsed = dtBatteryMS ~= nil and RealisticMechanicalSystems.sanitizeNumber(dtBatteryMS, 0, 0) or operating
    if elapsed <= 0 then return end
    inputs = inputs or RMS_Thermal.getNativeThermalInputs(vehicle, vehicle:getIsMotorStarted())
    local _, chargedShare, chargingMS = RMS_ElectricDrive.consumeChargeObservation(vehicle)
    local temperature = spec.tractionBatteryTempC
    if not isFiniteChargeValue(temperature) or temperature == -99 then
        temperature = ambientC
    end
    local workShare = inputs.motorStarted and math.clamp(operating / elapsed, 0, 1) or 0
    local nextTemperature, values = RMS_Thermal.advanceRole(vehicle, "battery", temperature, elapsed,
        ambientPrev or ambientC, ambientC, inputs, {
            workShare = workShare, chargeCapacityShare = chargedShare,
            forcedActive = inputs.motorStarted or chargingMS > 0 or RMS_ElectricDrive.getIsCharging(vehicle),
            fluidKey = "coolantLevel"
        })
    spec.tractionBatteryTempC = nextTemperature
    local batteryDebug = RMS_Utils.getIsDebugDataWanted(vehicle) and spec.debugData ~= nil and spec.debugData.batteryTemp or nil
    if batteryDebug ~= nil then
        for key, value in pairs(values) do batteryDebug[key] = value end
        batteryDebug.acceptedChargeCapacityShare = chargedShare
        batteryDebug.chargingElapsedMS = chargingMS
        batteryDebug.workShare = workShare
    end
end

---Keeps the cold battery state in step with its temperature
-- @param table vehicle vehicle
function RMS_ElectricDrive.syncColdBattery(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    if not vehicle.isServer then
        return
    end

    local stage = RMS_ElectricDrive.getTemperatureStage(spec.tractionBatteryTempC, RMS_Config.ELECTRIC_DRIVE.BATTERY_COLD_STAGES)
    local active = vehicle:getActiveBreakdowns()[COLD_BATTERY_ID]

    if stage == 0 then
        if active ~= nil then
            vehicle:removeBreakdown(COLD_BATTERY_ID)
        end
    elseif active == nil then
        vehicle:addBreakdown(COLD_BATTERY_ID, stage)
    elseif active.stage ~= stage then
        vehicle:changeBreakdownStage(COLD_BATTERY_ID, stage)
    end
end
