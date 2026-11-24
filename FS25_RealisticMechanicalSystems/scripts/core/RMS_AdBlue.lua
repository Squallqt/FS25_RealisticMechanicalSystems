-- Copyright © 2026 Squallqt. All rights reserved.

---AdBlue of a followed machine: brand use, own refill, a shown level
RMS_AdBlue = {}

RMS_AdBlue.FAULT_ID = "ADBLUE_TANK_LEVEL"
RMS_AdBlue.STAGE = { NORMAL = 0, LOW = 1, VERY_LOW = 2, EMPTY = 3 }

local STAGE = RMS_AdBlue.STAGE

---Returns the AdBlue tank of a machine RMS follows, nil without one
-- @param table vehicle vehicle
-- @return integer? fillUnitIndex fill unit of the tank
function RMS_AdBlue.getTank(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    if spec == nil or spec.isExcludedVehicle then
        return nil
    end
    return vehicle:getConsumerFillUnitIndex(FillType.DEF)
end

---Returns the share of the AdBlue tank left, nil without one
-- @param table vehicle vehicle
-- @return float? level level, 0 to 1
function RMS_AdBlue.getLevel(vehicle)
    local tank = RMS_AdBlue.getTank(vehicle)
    local capacity = tank ~= nil and vehicle:getFillUnitCapacity(tank) or 0
    if capacity <= 0 then
        return nil
    end
    return math.clamp(vehicle:getFillUnitFillLevel(tank) / capacity, 0, 1)
end

---Returns the stage of a tank level, nil without a tank
-- @param float? level level, 0 to 1
-- @return integer? stage RMS_AdBlue.STAGE
function RMS_AdBlue.getStage(level)
    if level == nil then
        return nil
    end
    local config = RMS_Config.EXHAUST.ADBLUE
    if level <= 0 then
        return STAGE.EMPTY
    elseif level < config.INDUCEMENT_LEVEL then
        return STAGE.VERY_LOW
    elseif level < config.WARNING_LEVEL then
        return STAGE.LOW
    end
    return STAGE.NORMAL
end

---Tells whether a low tank derates the engine, from Stage IV on
-- @param table vehicle vehicle
-- @return boolean hasInducement true when it derates
function RMS_AdBlue.getHasInducement(vehicle)
    local year = vehicle.spec_RealisticMechanicalSystems.year
    local power = vehicle:getMotor().peakMotorPower
    return RMS_Exhaust.getIsStageIV(year, power) or RMS_Exhaust.getIsStageV(year, power)
end

---Returns the inducement the tank calls for: nil, "LOW" or "SEVERE"
-- @param table vehicle vehicle
-- @return string? inducement "LOW" or "SEVERE", nil for none
function RMS_AdBlue.getInducement(vehicle)
    local stage = RMS_AdBlue.getStage(RMS_AdBlue.getLevel(vehicle))
    if stage == nil or stage < STAGE.VERY_LOW or not RMS_AdBlue.getHasInducement(vehicle) then
        return nil
    end
    return stage == STAGE.EMPTY and "SEVERE" or "LOW"
end

---Returns the AdBlue a litre of diesel takes, by the brand
-- @param table vehicle vehicle
-- @return float ratio litres of AdBlue per litre of diesel
function RMS_AdBlue.getRatio(vehicle)
    local config = RMS_Config.EXHAUST.ADBLUE
    return config.BRAND_RATIOS[g_brandManager:getBrandByIndex(vehicle:getBrand()).name] or config.DEFAULT_RATIO
end

---Returns the AdBlue and diesel consumers of a machine RMS follows
-- @param table vehicle vehicle
-- @return table? adBlue AdBlue consumer, nil when RMS leaves them to the game
-- @return table? diesel diesel consumer
function RMS_AdBlue.getConsumers(vehicle)
    if RMS_AdBlue.getTank(vehicle) == nil then
        return nil
    end
    local consumers = vehicle.spec_motorized.consumersByFillType
    local adBlue, diesel = consumers[FillType.DEF], consumers[FillType.DIESEL]
    -- the game's update burns its permanent consumers alone
    if diesel == nil or not (adBlue.permanentConsumption and diesel.permanentConsumption) then
        return nil
    end
    return adBlue, diesel
end

---Bills the AdBlue the game burnt for a helper who buys the fuel
-- @param table vehicle vehicle
-- @param table consumer AdBlue consumer
-- @param float pending litres the consumer held before the update
function RMS_AdBlue.chargeWorker(vehicle, consumer, pending)
    if not vehicle.isServer or consumer.fillLevelToChange >= pending or not vehicle:getIsAIActive()
        or not g_currentMission.missionInfo.helperBuyFuel then
        return
    end
    -- the game flushes past a litre; one frame's use is not billed
    local farmId = vehicle:getOwnerFarmId()
    local price = pending * g_currentMission.economyManager:getCostPerLiter(FillType.DEF) * 1.5
    g_farmManager:updateFarmStats(farmId, "expenses", price)
    g_currentMission:addMoney(-price, farmId, MoneyType.PURCHASE_FUEL, true)
end

---Runs a motor check without the AdBlue tank: empty, it derates
-- @param table vehicle vehicle
-- @param function func motor check
-- @return any result what the check returns
function RMS_AdBlue.callWithoutTank(vehicle, func)
    local tank = RMS_AdBlue.getTank(vehicle)
    local propellants = vehicle.spec_motorized.propellantFillUnitIndices
    local position = nil
    for index, fillUnitIndex in ipairs(tank ~= nil and propellants or {}) do
        if fillUnitIndex == tank then
            position = index
            break
        end
    end
    if position == nil then
        return func(vehicle)
    end
    table.remove(propellants, position)
    local result = func(vehicle)
    table.insert(propellants, position, tank)
    return result
end

-- the diesel nozzle no longer fills the AdBlue of a machine RMS follows
Motorized.onFillUnitFillLevelChanged = Utils.overwrittenFunction(Motorized.onFillUnitFillLevelChanged,
    function(self, superFunc, fillUnitIndex, fillLevelDelta, fillType, ...)
        if fillType == FillType.DIESEL and RMS_AdBlue.getTank(self) ~= nil then
            return
        end
        return superFunc(self, fillUnitIndex, fillLevelDelta, fillType, ...)
    end)

local MESSAGES = {
    [STAGE.LOW] = { "rms_adblue_low_message", "rms_adblue_low_message" },
    [STAGE.VERY_LOW] = { "rms_adblue_very_low_message", "rms_adblue_very_low_derate_message" },
    [STAGE.EMPTY] = { "rms_adblue_empty_message", "rms_adblue_empty_derate_message" }
}

---Tells the driver what the tank calls for, then as it worsens
-- @param table vehicle vehicle
function RMS_AdBlue.updateMessages(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    local stage = RMS_AdBlue.getStage(RMS_AdBlue.getLevel(vehicle))
    if stage == nil or not vehicle.isClient or not vehicle:getIsActiveForInput(true) then
        spec.adBlueShownStage = nil
        return
    end
    local shown = spec.adBlueShownStage
    local hasInducement = RMS_AdBlue.getHasInducement(vehicle)
    local key = nil
    if shown == nil or stage > shown then
        key = MESSAGES[stage] ~= nil and MESSAGES[stage][hasInducement and 2 or 1] or nil
    elseif hasInducement and shown >= STAGE.VERY_LOW and stage < STAGE.VERY_LOW then
        key = "rms_adblue_restored_message"
    end
    spec.adBlueShownStage = stage
    if key ~= nil then
        RMS_Hud.showNotification(g_i18n:getText(key), g_i18n:getText("rms_adblue_title"))
    end
end

---Returns the colour of the AdBlue lamp this frame, nil while unlit
-- @param float? level level, 0 to 1
-- @param float time time of the blink (ms)
-- @return table? color rgba color
function RMS_AdBlue.getLampColor(level, time)
    local stage = RMS_AdBlue.getStage(level)
    if stage == nil or stage == STAGE.NORMAL then
        return nil
    end
    local color = RMS_Breakdowns.COLORS.WARNING
    if stage == STAGE.LOW then
        return color
    end
    local config = RMS_Config.EXHAUST.ADBLUE
    local share = level / config.INDUCEMENT_LEVEL
    local phaseMs = RMS_Hud.LAMP_BLINK.PHASE_MS * (config.EMPTY_BLINK_FACTOR + (1 - config.EMPTY_BLINK_FACTOR) * share)
    return math.floor(time / phaseMs) % 2 == 0 and color or nil
end

---Adds the low tank code of the engine controller to a reading
-- @param table target machine
-- @param table codes fault entries of the reading
-- @param table stored fault entries by code
function RMS_AdBlue.addFaultCode(target, codes, stored)
    local stage = RMS_AdBlue.getStage(RMS_AdBlue.getLevel(target))
    if stage == nil or stage == STAGE.NORMAL then
        return
    end
    local entry = RMS_DiagnosticTool.getFaultEntry(target, RMS_AdBlue.FAULT_ID, stage >= STAGE.VERY_LOW)
    if entry.spn == nil then
        return
    end
    local key = string.format("%s %d %d", entry.ecu, entry.spn, entry.fmi)
    if stored[key] == nil then
        stored[key] = entry
        table.insert(codes, entry)
    end
end
