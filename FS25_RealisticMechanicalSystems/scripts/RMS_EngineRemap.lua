-- Copyright © 2026 Squallqt. All rights reserved.

---Engine remapping by a tuner or the dealer
RMS_EngineRemap = {}

RMS_EngineRemap.REMAP = "rms_remap_option"
RMS_EngineRemap.RESTORE = "rms_remap_restore"
-- gain of the weakest and of the strongest engine of a store item
RMS_EngineRemap.LOW_GAIN = 0.20
RMS_EngineRemap.HIGH_GAIN = 0.10
-- tuner price at the reference power
RMS_EngineRemap.PRICE = 1000
RMS_EngineRemap.PRICE_POWER = 160
RMS_EngineRemap.PRICE_EXPONENT = 0.6
RMS_EngineRemap.RESTORE_PRICE = 80
RMS_EngineRemap.FREE_RESTORE_MONTHS = 12
RMS_EngineRemap.DURATION_HOURS = {
    [RMS_EngineRemap.REMAP] = 3,
    [RMS_EngineRemap.RESTORE] = 1
}
-- rpm between two points of the bench curve
RMS_EngineRemap.CURVE_STEP = 10

---Returns the engine configurations of the store item and the one fitted
-- @param table vehicle vehicle
-- @return table? items engine configurations of the store item
-- @return integer index engine configuration fitted
local function getMotorItems(vehicle)
    local storeItem = g_storeManager:getItemByXMLFilename(vehicle.configFileName)
    local items = storeItem ~= nil and storeItem.configurations ~= nil and storeItem.configurations.motor or nil
    return items, vehicle.configurations.motor or 1
end

---Returns the weakest and strongest engines of the store item, power first
-- @param table vehicle vehicle
-- @return float? low power of the weakest engine
-- @return float? high power of the strongest engine
local function getFamilyPower(vehicle)
    local items = getMotorItems(vehicle)
    local low, high = nil, nil
    for _, item in ipairs(items or {}) do
        if item.isSelectable ~= false and item.power ~= nil then
            if low == nil or item.power < low then low = item.power end
            if high == nil or item.power > high then high = item.power end
        end
    end
    return low, high
end

---Tells whether a remap applies to the machine
-- @param table vehicle vehicle
-- @return boolean isEligible true when a remap applies
function RMS_EngineRemap.getIsEligible(vehicle)
    return not vehicle.spec_RealisticMechanicalSystems.isExcludedVehicle and vehicle.propertyState == VehiclePropertyState.OWNED
        and RMS_Utils.getUsesEngineECUProfile(vehicle)
end

---Returns the dealer gain, up to the largest engine of the store item
-- @param table vehicle vehicle
-- @return float gain gain, share of the stock torque
function RMS_EngineRemap.getDealerGain(vehicle)
    local _, high = getFamilyPower(vehicle)
    local power = RMS_Fluids.getEnginePower(vehicle)
    return high ~= nil and power > 0 and math.max(high / power - 1, 0) or 0
end

---Tells whether the dealer remaps, with the factory software
-- @param string? workshopType workshop
-- @return boolean isDealer true at the dealer
function RMS_EngineRemap.getIsDealer(workshopType)
    return workshopType == RealisticMechanicalSystems.WORKSHOP.DEALER
end

---Returns the gain of a remap at a workshop, or of the software fitted
-- @param table vehicle vehicle
-- @param string? workshopType nil for the software fitted
-- @return float gain gain, share of the stock torque
function RMS_EngineRemap.getGain(vehicle, workshopType)
    local isDealer = RMS_EngineRemap.getIsDealer(workshopType)
    if workshopType == nil then
        isDealer = vehicle.spec_RealisticMechanicalSystems.remapByDealer
    end
    if isDealer then
        return RMS_EngineRemap.getDealerGain(vehicle)
    end
    local low, high = getFamilyPower(vehicle)
    local power = RMS_Fluids.getEnginePower(vehicle)
    if low == nil or high <= low then
        return RMS_EngineRemap.HIGH_GAIN
    end
    local share = math.clamp((power - low) / (high - low), 0, 1)
    return RMS_EngineRemap.LOW_GAIN + (RMS_EngineRemap.HIGH_GAIN - RMS_EngineRemap.LOW_GAIN) * share
end

---Tells whether the machine runs remapped software
-- @param table vehicle vehicle
-- @return boolean isRemapped true with remapped software
function RMS_EngineRemap.getIsRemapped(vehicle)
    return vehicle.spec_RealisticMechanicalSystems.remapMotor > 0
end

---Returns the torque factor the remap gives the engine
-- @param table vehicle vehicle
-- @return float factor torque factor, 1 for the stock software
function RMS_EngineRemap.getTorqueFactor(vehicle)
    if not RMS_EngineRemap.getIsRemapped(vehicle) then
        return 1
    end
    local spec = vehicle.spec_RealisticMechanicalSystems
    if spec.remapGain == nil then
        spec.remapGain = RMS_EngineRemap.getGain(vehicle)
    end
    return 1 + spec.remapGain
end

---Converts the native load share to a share of the stock torque
-- @param table vehicle vehicle
-- @param float load native load share
-- @return float stockLoad share of the stock torque
function RMS_EngineRemap.getStockLoad(vehicle, load)
    return load * RMS_EngineRemap.getTorqueFactor(vehicle)
end

---Returns the power of the strongest engine of the store item over the one fitted
-- @param table vehicle vehicle
-- @return float ratio ratio, at least 1
local function getBlockRatio(vehicle)
    local _, high = getFamilyPower(vehicle)
    local power = RMS_Fluids.getEnginePower(vehicle)
    -- engines of one store item share the torque curve shape
    return high ~= nil and power > 0 and math.max(high / power, 1) or 1
end

---Returns how far the overload threshold moves on a remapped engine
-- @param table vehicle vehicle
-- @return float ratio ratio, 1 for the stock software
function RMS_EngineRemap.getOverloadRatio(vehicle)
    if not RMS_EngineRemap.getIsRemapped(vehicle) then
        return 1
    end
    return getBlockRatio(vehicle)
end

---Tells whether the remap takes full load past what the block holds
-- @param table vehicle vehicle
-- @param string? workshopType nil for the software fitted
-- @return boolean isBeyond true past what the block holds
function RMS_EngineRemap.getIsBeyondBlock(vehicle, workshopType)
    local threshold = RMS_Config.CORE.ENGINE_FACTOR_DATA.MOTOR_OVERLOADED_THRESHOLD
    return 1 + RMS_EngineRemap.getGain(vehicle, workshopType) > threshold * getBlockRatio(vehicle)
end

---Returns the stock peaks of the engine
-- @param table vehicle vehicle
-- @return float hp peak power (hp)
-- @return float torque peak torque (Nm)
function RMS_EngineRemap.getStockPeaks(vehicle)
    local motor = vehicle.spec_motorized.motor
    return motor.peakMotorPower * RMS_Fluids.KW_TO_HP, motor.peakMotorTorque * 1000
end

---Returns the tuner price at the game's economic difficulty
-- @param table vehicle vehicle
-- @param string option RMS_EngineRemap.REMAP or RESTORE
-- @return float price price, rounded to ten
function RMS_EngineRemap.getPrice(vehicle, option)
    local price
    if option == RMS_EngineRemap.RESTORE then
        if RMS_EngineRemap.getIsRestoreFree(vehicle) then
            return 0
        end
        price = RMS_EngineRemap.RESTORE_PRICE
    else
        local power = RMS_EngineRemap.getStockPeaks(vehicle)
        price = RMS_EngineRemap.PRICE * (power / RMS_EngineRemap.PRICE_POWER) ^ RMS_EngineRemap.PRICE_EXPONENT
    end
    return math.floor(RMS_Utils.getGamePrice(price) / 10 + 0.5) * 10
end

---Returns the work hours of a remap or of a restore
-- @param string option RMS_EngineRemap.REMAP or RESTORE
-- @return float hours work hours
function RMS_EngineRemap.getDurationHours(option)
    return RMS_EngineRemap.DURATION_HOURS[option] or 0
end

---Returns the age in months up to which a tuner restore is free
-- @param table vehicle vehicle
-- @return integer? age age (months), nil without a tuner remap
function RMS_EngineRemap.getFreeRestoreUntil(vehicle)
    if not RMS_EngineRemap.getIsRemapped(vehicle) or vehicle.spec_RealisticMechanicalSystems.remapByDealer then
        return nil
    end
    return vehicle.spec_RealisticMechanicalSystems.remapAge + RMS_EngineRemap.FREE_RESTORE_MONTHS
end

---Tells whether a restore costs nothing now
-- @param table vehicle vehicle
-- @return boolean isFree true while it is free
function RMS_EngineRemap.getIsRestoreFree(vehicle)
    local untilAge = RMS_EngineRemap.getFreeRestoreUntil(vehicle)
    return untilAge ~= nil and vehicle.age < untilAge
end

---Returns the option a tuner offers the machine now
-- @param table vehicle vehicle
-- @return string option RMS_EngineRemap.REMAP or RESTORE
function RMS_EngineRemap.getOption(vehicle)
    return RMS_EngineRemap.getIsRemapped(vehicle) and RMS_EngineRemap.RESTORE or RMS_EngineRemap.REMAP
end

---Tells whether a workshop remaps or restores, and why not
-- @param table vehicle vehicle
-- @param string? workshopType workshop
-- @param string? option option asked, nil for the one offered
-- @return boolean isAllowed true when the workshop does it
-- @return string? refusal reason of a refusal
function RMS_EngineRemap.getAvailability(vehicle, workshopType, option)
    if not RMS_EngineRemap.getIsEligible(vehicle) then
        return false, vehicle.propertyState ~= VehiclePropertyState.OWNED and "leased" or "notEligible"
    end
    local isDealer = RMS_EngineRemap.getIsDealer(workshopType)
    if RMS_EngineRemap.getIsRemapped(vehicle) then
        if isDealer ~= vehicle.spec_RealisticMechanicalSystems.remapByDealer then
            return false, isDealer and "byTuner" or "byDealer"
        end
    elseif isDealer and RMS_EngineRemap.getDealerGain(vehicle) <= 0 then
        return false, "top"
    end
    return option == nil or option == RMS_EngineRemap.getOption(vehicle), nil
end

---Returns the fitted parts whose warranty runs, the first to end first
-- @param table vehicle vehicle
-- @return table parts id and expiry of each part
function RMS_EngineRemap.getCoveredParts(vehicle)
    local parts = {}
    for id, expiry in pairs(vehicle.spec_RealisticMechanicalSystems.partWarranty) do
        if vehicle.age < expiry then
            table.insert(parts, { id = id, expiry = expiry })
        end
    end
    table.sort(parts, function(a, b)
        return a.expiry < b.expiry or a.expiry == b.expiry and a.id < b.id
    end)
    return parts
end

---Describes what the tuner offers the machine at this workshop
-- @param table vehicle vehicle
-- @param string? workshopType workshop
-- @return table offer refusal or terms of the remap
function RMS_EngineRemap.getOffer(vehicle, workshopType)
    local isAllowed, refusal = RMS_EngineRemap.getAvailability(vehicle, workshopType)
    local offer = { eligible = refusal ~= "notEligible" and refusal ~= "leased", refusal = not isAllowed and refusal or nil,
        option = RMS_EngineRemap.getOption(vehicle) }
    if not offer.eligible then
        return offer
    end
    local stockHp, stockTorque = RMS_EngineRemap.getStockPeaks(vehicle)
    local isRemapped = RMS_EngineRemap.getIsRemapped(vehicle)
    offer.isDealer = isRemapped and vehicle.spec_RealisticMechanicalSystems.remapByDealer
        or not isRemapped and RMS_EngineRemap.getIsDealer(workshopType)
    local gainWorkshop = not isRemapped and workshopType or nil
    offer.gain = RMS_EngineRemap.getGain(vehicle, gainWorkshop)
    offer.isBeyondBlock = RMS_EngineRemap.getIsBeyondBlock(vehicle, gainWorkshop)
    offer.stockHp, offer.stockTorque = stockHp, stockTorque
    offer.remapHp, offer.remapTorque = stockHp * (1 + offer.gain), stockTorque * (1 + offer.gain)
    offer.freeRestoreUntil = RMS_EngineRemap.getFreeRestoreUntil(vehicle)
    offer.restorePrice = math.floor(RMS_Utils.getGamePrice(RMS_EngineRemap.RESTORE_PRICE) / 10 + 0.5) * 10
    offer.warrantyVoided = vehicle.spec_RealisticMechanicalSystems.warrantyVoided
    offer.factoryTerm = RealisticMechanicalSystems.getIsWithinWarrantyLimits(vehicle)
    offer.coveredParts = RMS_EngineRemap.getCoveredParts(vehicle)
    offer.warrantyActive = not offer.warrantyVoided and (offer.factoryTerm or #offer.coveredParts > 0)
    return offer
end

---Samples the stock and remapped curves for the bench chart
-- @param table vehicle vehicle
-- @param string? workshopType of a remap to come, nil for the software fitted
-- @return table curve rpm, stockTorque, remapTorque (Nm), stockHp, remapHp lists and peakRpm
function RMS_EngineRemap.getCurve(vehicle, workshopType)
    local motor = vehicle.spec_motorized.motor
    local torqueCurve = motor:getTorqueCurve()
    local keyframes = torqueCurve.keyframes
    local factor = 1 + RMS_EngineRemap.getGain(vehicle, workshopType)
    local curve = { rpm = {}, stockTorque = {}, remapTorque = {}, stockHp = {}, remapHp = {},
        peakRpm = motor.peakMotorPowerRotSpeed * 30 / math.pi }
    local last = keyframes[#keyframes].time
    local rpm = keyframes[1].time
    while true do
        local torque = torqueCurve:get(rpm) * 1000
        local hp = torque * rpm * math.pi / 30 / 1000 * RMS_Fluids.KW_TO_HP
        table.insert(curve.rpm, rpm)
        table.insert(curve.stockTorque, torque)
        table.insert(curve.remapTorque, torque * factor)
        table.insert(curve.stockHp, hp)
        table.insert(curve.remapHp, hp * factor)
        if rpm >= last then
            break
        end
        rpm = math.min(rpm + RMS_EngineRemap.CURVE_STEP, last)
    end
    return curve
end

---Fits the remap or the stock software at the end of the service
-- @param table vehicle vehicle
-- @param string option RMS_EngineRemap.REMAP or RESTORE
function RMS_EngineRemap.complete(vehicle, option)
    local spec = vehicle.spec_RealisticMechanicalSystems
    if option == RMS_EngineRemap.REMAP then
        local _, index = getMotorItems(vehicle)
        spec.remapMotor = index
        spec.remapAge = vehicle.age
        spec.remapByDealer = RMS_EngineRemap.getIsDealer(spec.workshopType)
        spec.remapGain = RMS_EngineRemap.getGain(vehicle)
        spec.warrantyVoided = true
        spec.partWarranty = {}
    else
        RMS_EngineRemap.reset(vehicle)
    end
end

---Puts the stock software back
-- @param table vehicle vehicle
function RMS_EngineRemap.reset(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    spec.remapMotor = 0
    spec.remapAge = 0
    spec.remapByDealer = false
    spec.remapGain = nil
end

---Keeps a remap only on the engine it was made for
-- @param table vehicle vehicle
function RMS_EngineRemap.validateLoadedEngine(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    local _, index = getMotorItems(vehicle)
    if spec.remapMotor > 0 and spec.remapMotor ~= index then
        RMS_EngineRemap.reset(vehicle)
    end
end
