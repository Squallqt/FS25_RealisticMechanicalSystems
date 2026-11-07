-- Copyright © 2026 Squallqt. All rights reserved.

---Engine remapping by a tuner at the machine
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
-- months of free restore after a remap
RMS_EngineRemap.FREE_RESTORE_MONTHS = 12
RMS_EngineRemap.DURATION_HOURS = {
    [RMS_EngineRemap.REMAP] = 3,
    [RMS_EngineRemap.RESTORE] = 1
}
-- rpm between two points of the bench curve
RMS_EngineRemap.CURVE_STEP = 10

local function getMotorItems(vehicle)
    local storeItem = g_storeManager:getItemByXMLFilename(vehicle.configFileName)
    local items = storeItem ~= nil and storeItem.configurations ~= nil and storeItem.configurations.motor or nil
    return items, vehicle.configurations ~= nil and vehicle.configurations.motor or 1
end

local function getFamilyPower(vehicle)
    local items = getMotorItems(vehicle)
    local low, high, lowItem, highItem = nil, nil, nil, nil
    for _, item in ipairs(items or {}) do
        if item.isSelectable ~= false and item.power ~= nil then
            if low == nil or item.power < low then low, lowItem = item.power, item end
            if high == nil or item.power > high then high, highItem = item.power, item end
        end
    end
    return low, high, lowItem, highItem
end

---Tells whether a remap applies to the machine
function RMS_EngineRemap.getIsEligible(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    return spec ~= nil and not spec.isExcludedVehicle and vehicle.spec_motorized ~= nil
        and vehicle.propertyState == VehiclePropertyState.OWNED and RMS_Utils.getUsesEngineECUProfile(vehicle)
end

---Returns the gain from the engine's place in its store item
function RMS_EngineRemap.getGain(vehicle)
    local low, high = getFamilyPower(vehicle)
    local power = RMS_Fluids.getEnginePower(vehicle)
    if low == nil or high <= low then
        return RMS_EngineRemap.HIGH_GAIN
    end
    local share = math.clamp((power - low) / (high - low), 0, 1)
    return RMS_EngineRemap.LOW_GAIN + (RMS_EngineRemap.HIGH_GAIN - RMS_EngineRemap.LOW_GAIN) * share
end

---Tells whether the machine runs remapped software
function RMS_EngineRemap.getIsRemapped(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    return spec ~= nil and (spec.remapMotor or 0) > 0
end

---Returns the torque factor the remap gives the engine
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
function RMS_EngineRemap.getStockLoad(vehicle, load)
    return load * RMS_EngineRemap.getTorqueFactor(vehicle)
end

local function getBlockRatio(vehicle)
    local _, high = getFamilyPower(vehicle)
    local power = RMS_Fluids.getEnginePower(vehicle)
    -- engines of one store item share the torque curve shape
    return high ~= nil and power > 0 and math.max(high / power, 1) or 1
end

---Returns how far the overload threshold moves on a remapped engine
function RMS_EngineRemap.getOverloadRatio(vehicle)
    if not RMS_EngineRemap.getIsRemapped(vehicle) then
        return 1
    end
    return getBlockRatio(vehicle)
end

---Tells whether the remap takes full load past what the block holds
function RMS_EngineRemap.getIsBeyondBlock(vehicle)
    local threshold = RMS_Config.CORE.ENGINE_FACTOR_DATA.MOTOR_OVERLOADED_THRESHOLD
    return 1 + RMS_EngineRemap.getGain(vehicle) > threshold * getBlockRatio(vehicle)
end

---Returns the stock peaks of the engine
function RMS_EngineRemap.getStockPeaks(vehicle)
    local motor = vehicle.spec_motorized.motor
    return motor.peakMotorPower * RMS_Fluids.KW_TO_HP, motor.peakMotorTorque * 1000
end

---Returns the tuner price at the game's economic difficulty
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
function RMS_EngineRemap.getDurationHours(option)
    return RMS_EngineRemap.DURATION_HOURS[option] or 0
end

---Returns the machine age in months up to which a restore is free
function RMS_EngineRemap.getFreeRestoreUntil(vehicle)
    if not RMS_EngineRemap.getIsRemapped(vehicle) then
        return nil
    end
    return (vehicle.spec_RealisticMechanicalSystems.remapAge or 0) + RMS_EngineRemap.FREE_RESTORE_MONTHS
end

---Tells whether a restore costs nothing now
function RMS_EngineRemap.getIsRestoreFree(vehicle)
    local untilAge = RMS_EngineRemap.getFreeRestoreUntil(vehicle)
    return untilAge ~= nil and (vehicle.age or 0) < untilAge
end

---Returns the option a tuner offers the machine now
function RMS_EngineRemap.getOption(vehicle)
    return RMS_EngineRemap.getIsRemapped(vehicle) and RMS_EngineRemap.RESTORE or RMS_EngineRemap.REMAP
end

---Tells whether the tuner comes to a workshop: never to the dealer
function RMS_EngineRemap.getIsTunerAt(workshopType)
    return workshopType ~= RealisticMechanicalSystems.WORKSHOP.DEALER
end

---Tells whether a workshop does the service, and why not
function RMS_EngineRemap.getAvailability(vehicle, workshopType, option)
    if not RMS_EngineRemap.getIsEligible(vehicle) then
        return false, vehicle.propertyState ~= VehiclePropertyState.OWNED and "leased" or "notEligible"
    end
    if not RMS_EngineRemap.getIsTunerAt(workshopType) then
        return false, "dealer"
    end
    return option == nil or option == RMS_EngineRemap.getOption(vehicle), nil
end

local function getIsFactoryTermRunning(vehicle)
    local months, hours = vehicle:getWarrantyLimits()
    return (vehicle.age or 0) < months and RealisticMechanicalSystems.getRealOperatingHours(vehicle) < hours
end

---Returns the fitted parts whose warranty runs, the first to end first
function RMS_EngineRemap.getCoveredParts(vehicle)
    local parts = {}
    for id, expiry in pairs(vehicle.spec_RealisticMechanicalSystems.partWarranty or {}) do
        if (vehicle.age or 0) < expiry then
            table.insert(parts, { id = id, expiry = expiry })
        end
    end
    table.sort(parts, function(a, b)
        return a.expiry < b.expiry or a.expiry == b.expiry and a.id < b.id
    end)
    return parts
end

---Tells whether a factory or fitted part warranty still runs
function RMS_EngineRemap.getIsWarrantyActive(vehicle)
    if vehicle.spec_RealisticMechanicalSystems.warrantyVoided then
        return false
    end
    return getIsFactoryTermRunning(vehicle) or #RMS_EngineRemap.getCoveredParts(vehicle) > 0
end

local function getRangeEnds(vehicle)
    local _, _, lowItem, highItem = getFamilyPower(vehicle)
    if lowItem == nil or lowItem == highItem then
        return nil, nil
    end
    return { name = lowItem.name, gain = RMS_EngineRemap.LOW_GAIN }, { name = highItem.name, gain = RMS_EngineRemap.HIGH_GAIN }
end

---Describes what the tuner offers the machine at this workshop
-- @return table offer refusal, option, peaks in hp and Nm, gain, range ends, price, hours, restore terms
function RMS_EngineRemap.getOffer(vehicle, workshopType)
    local isAllowed, refusal = RMS_EngineRemap.getAvailability(vehicle, workshopType)
    local offer = { eligible = refusal ~= "notEligible" and refusal ~= "leased", refusal = not isAllowed and refusal or nil,
        option = RMS_EngineRemap.getOption(vehicle) }
    if not offer.eligible then
        return offer
    end
    local items, index = getMotorItems(vehicle)
    local item = items ~= nil and items[index] or nil
    local stockHp, stockTorque = RMS_EngineRemap.getStockPeaks(vehicle)
    offer.engineName = item ~= nil and item.name or vehicle:getName()
    offer.gain = RMS_EngineRemap.getGain(vehicle)
    offer.isBeyondBlock = RMS_EngineRemap.getIsBeyondBlock(vehicle)
    offer.stockHp, offer.stockTorque = stockHp, stockTorque
    offer.remapHp, offer.remapTorque = stockHp * (1 + offer.gain), stockTorque * (1 + offer.gain)
    offer.lowEngine, offer.highEngine = getRangeEnds(vehicle)
    offer.price = RMS_EngineRemap.getPrice(vehicle, offer.option)
    offer.durationHours = RMS_EngineRemap.getDurationHours(offer.option)
    offer.freeRestoreUntil = RMS_EngineRemap.getFreeRestoreUntil(vehicle)
    offer.restorePrice = math.floor(RMS_Utils.getGamePrice(RMS_EngineRemap.RESTORE_PRICE) / 10 + 0.5) * 10
    offer.warrantyActive = RMS_EngineRemap.getIsWarrantyActive(vehicle)
    offer.warrantyVoided = vehicle.spec_RealisticMechanicalSystems.warrantyVoided == true
    offer.factoryTerm = getIsFactoryTermRunning(vehicle)
    offer.coveredParts = RMS_EngineRemap.getCoveredParts(vehicle)
    return offer
end

---Samples the stock and remapped curves for the bench chart
-- @return table curve rpm, stockTorque, remapTorque (Nm), stockHp, remapHp lists and peakRpm
function RMS_EngineRemap.getCurve(vehicle)
    local motor = vehicle.spec_motorized.motor
    local torqueCurve = motor:getTorqueCurve()
    local keyframes = torqueCurve.keyframes
    local factor = 1 + RMS_EngineRemap.getGain(vehicle)
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
function RMS_EngineRemap.complete(vehicle, option)
    local spec = vehicle.spec_RealisticMechanicalSystems
    if option == RMS_EngineRemap.REMAP then
        local _, index = getMotorItems(vehicle)
        spec.remapMotor = index
        spec.remapAge = vehicle.age or 0
        spec.remapGain = RMS_EngineRemap.getGain(vehicle)
        spec.warrantyVoided = true
        spec.partWarranty = {}
    else
        RMS_EngineRemap.reset(vehicle)
    end
end

---Puts the stock software back
function RMS_EngineRemap.reset(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    spec.remapMotor = 0
    spec.remapAge = 0
    spec.remapGain = nil
end

---Keeps a remap only on the engine it was made for
function RMS_EngineRemap.validateLoadedEngine(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    local _, index = getMotorItems(vehicle)
    if (spec.remapMotor or 0) > 0 and spec.remapMotor ~= index then
        RMS_EngineRemap.reset(vehicle)
    end
end
