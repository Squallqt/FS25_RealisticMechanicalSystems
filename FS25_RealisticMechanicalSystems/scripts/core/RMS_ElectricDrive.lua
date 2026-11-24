-- Copyright © 2026 Squallqt. All rights reserved.

---Traction battery temperature and charge limits
RMS_ElectricDrive = {}

local COLD_BATTERY_ID = "COLD_TRACTION_BATTERY"

---Counts the thresholds a temperature has gone past, in the order they are met
-- @param float temperature temperature (deg C)
-- @param table thresholds thresholds (deg C)
-- @return integer stage thresholds gone past
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
-- @param float condition condition of the battery, 0 to 1
-- @param float lostToCells share failed cells take on top of the wear, 0 or negative
-- @return float share share, to the thousandth
function RMS_ElectricDrive.getCapacityShare(condition, lostToCells)
    local share = (1 - (1 - condition) * RMS_Config.ELECTRIC_DRIVE.BATTERY_CAPACITY_FADE) * (1 + lostToCells)
    return math.floor(share * 1000 + 0.5) / 1000
end

---Returns the capacity share the traction battery of a vehicle still holds
-- @param table vehicle vehicle
-- @return float share share, to the thousandth
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

---Returns the share of the charge power a battery accepts at a temperature
-- @param float temperature temperature (deg C)
-- @return float share share accepted
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
-- @param table object object charged
-- @param integer fillUnitIndex fill unit charged
-- @return float share share accepted
function RMS_ElectricDrive.getChargeAcceptance(object, fillUnitIndex)
    local spec = object.spec_RealisticMechanicalSystems
    if spec == nil or spec.isExcludedVehicle or not spec.isElectricVehicle
            or fillUnitIndex ~= object:getConsumerFillUnitIndex(FillType.ELECTRICCHARGE) then
        return 1
    end

    spec.tractionBatteryChargeTime = g_currentMission.time

    local chargerFault = spec.activeEffects.CHARGE_ACCEPTANCE_MODIFIER
    local chargerShare = chargerFault ~= nil and 1 + chargerFault.value or 1
    return getColdChargeAcceptance(spec.tractionBatteryTempC) * chargerShare
end

---Tells whether a value is a finite number
-- @param any value value
-- @return boolean isFinite true for a finite number
local function isFiniteChargeValue(value)
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

---Returns the level, capacity and elapsed time of a charge to observe, nil when none
-- @param table trigger load trigger
-- @param table object object charged
-- @param float dt time since the last frame (ms)
-- @return float? level level before the step
-- @return float? capacity capacity
-- @return float? elapsedMS game time of the step (ms)
local function getChargeObservationInputs(trigger, object, dt)
    local spec = object.spec_RealisticMechanicalSystems
    local fillUnitIndex = trigger.fillUnitIndex
    if spec == nil or spec.isExcludedVehicle or not spec.isElectricVehicle
            or trigger.selectedFillType ~= FillType.ELECTRICCHARGE
            or fillUnitIndex ~= object:getConsumerFillUnitIndex(FillType.ELECTRICCHARGE) then
        return nil
    end

    local capacity = object:getFillUnitCapacity(fillUnitIndex)
    local level = object:getFillUnitFillLevel(fillUnitIndex)
    if not isFiniteChargeValue(capacity) or capacity <= 0 then
        return nil
    end

    local elapsedMS = dt
    if trigger.useTimeScale then
        elapsedMS = elapsedMS * g_currentMission:getEffectiveTimeScale()
    end
    return level, capacity, elapsedMS
end

---Adds the energy a charge step brought to the traction battery
-- @param table object object charged
-- @param integer fillUnitIndex fill unit charged
-- @param float levelBefore level before the step
-- @param float capacity capacity
-- @param float elapsedMS game time of the step (ms)
local function recordChargeObservation(object, fillUnitIndex, levelBefore, capacity, elapsedMS)
    local spec = object.spec_RealisticMechanicalSystems
    local observation = spec.tractionBatteryChargeObservation
    if observation == nil then
        observation = { energy = 0, capacityShare = 0, elapsedMS = 0 }
        spec.tractionBatteryChargeObservation = observation
    end
    observation.elapsedMS = observation.elapsedMS + elapsedMS

    local levelAfter = object:getFillUnitFillLevel(fillUnitIndex)
    if levelAfter > levelBefore then
        local accepted = levelAfter - levelBefore
        observation.energy = observation.energy + accepted
        observation.capacityShare = observation.capacityShare + accepted / capacity
    end
end

---Consumes the transient charging observations
-- @param table vehicle vehicle
-- @return float energy energy taken
-- @return float capacityShare share of the capacity taken
-- @return float elapsedMS game time observed (ms)
function RMS_ElectricDrive.consumeChargeObservation(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    local observation = spec.tractionBatteryChargeObservation
    if observation == nil then
        return 0, 0, 0
    end
    spec.tractionBatteryChargeObservation = nil
    return observation.energy, observation.capacityShare, observation.elapsedMS
end

---Runs a load trigger, slicing the energy a slowed traction battery takes
-- @param table trigger load trigger
-- @param function superFunc original function
-- @param float dt time since the last frame (ms)
-- @return any ... what the game's function returns
function RMS_ElectricDrive.updateLoadTrigger(trigger, superFunc, dt)
    local object = trigger.currentFillableObject
    if not trigger.isServer or not trigger.isLoading or object == nil then
        return superFunc(trigger, dt)
    end

    local fillUnitIndex = trigger.fillUnitIndex
    local levelBefore, capacity, elapsedMS = getChargeObservationInputs(trigger, object, dt)
    ---Records the charge step, passing on what it is given
    -- @param any ... values passed on
    -- @return any ... the values given
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
-- @return boolean isCharging true while it charges
function RMS_ElectricDrive.getIsCharging(vehicle)
    local chargeTime = vehicle.spec_RealisticMechanicalSystems.tractionBatteryChargeTime
    return chargeTime ~= nil and g_currentMission.time - chargeTime < 1000
end

---Advances the traction battery through the common role kernel
-- @param table vehicle vehicle
-- @param float dtOperatingMS operating interval (ms)
-- @param float ambientC ambient temperature (deg C)
-- @param float dtBatteryMS battery interval (ms)
-- @param float ambientPrev ambient temperature at the previous step (deg C)
-- @param table inputs native thermal inputs
function RMS_ElectricDrive.updateBatteryTemperature(vehicle, dtOperatingMS, ambientC, dtBatteryMS, ambientPrev, inputs)
    local spec = vehicle.spec_RealisticMechanicalSystems
    if dtBatteryMS <= 0 then return end
    local _, chargedShare, chargingMS = RMS_ElectricDrive.consumeChargeObservation(vehicle)
    local workShare = inputs.motorStarted and dtOperatingMS / dtBatteryMS or 0
    local nextTemperature = RMS_Thermal.advanceRole(vehicle, "battery", spec.tractionBatteryTempC, dtBatteryMS,
        ambientPrev, ambientC, inputs, {
            workShare = workShare, chargeCapacityShare = chargedShare,
            forcedActive = inputs.motorStarted or chargingMS > 0 or RMS_ElectricDrive.getIsCharging(vehicle),
            fluidKey = "coolantLevel"
        })
    spec.tractionBatteryTempC = nextTemperature
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
