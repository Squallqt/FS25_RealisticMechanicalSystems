-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---Vehicle consumables and field inspection.
RMS_Consumables = RMS_Consumables or {}

local OIL_SMOKE_OF_WORN_ENGINE
for _, symptom in ipairs(RMS_Config.CORE.WORN_PART_SYMPTOMS) do
    if symptom.effect == "EXHAUST_OIL" then
        OIL_SMOKE_OF_WORN_ENGINE = symptom.amplitude
    end
end

local function updateFieldInspectionSoundActive(vehicle, spec)
    local isActive = next(spec.fieldInspectionActivePlayers) ~= nil
    if spec.fieldInspectionSoundActive ~= isActive then
        spec.fieldInspectionSoundActive = isActive
        RealisticMechanicalSystems.raiseRMSDirty(vehicle, RealisticMechanicalSystems.SYNC_GROUP.FIELDCARE)
        vehicle:raiseActive()
    end
end

---Registers a player as inspecting this vehicle
function RMS_Consumables:setFieldInspectionPlayerActive(player, isActive)
    if not self.isServer or player == nil then
        return
    end

    local spec = self.spec_RealisticMechanicalSystems
    if isActive then
        spec.fieldInspectionActivePlayers[player] = g_time + RMS_Config.FIELD_CARE.VISUAL_INSPECTION_DURATION
    else
        spec.fieldInspectionActivePlayers[player] = nil
    end

    updateFieldInspectionSoundActive(self, spec)
end

---Drops elapsed inspections on the server and plays the sound on a client
function RMS_Consumables:updateFieldInspectionSound()
    local spec = self.spec_RealisticMechanicalSystems
    if spec.fieldInspectionSoundActive then
        self:raiseActive()
    end

    if self.isServer then
        for player, endTime in pairs(spec.fieldInspectionActivePlayers) do
            if endTime <= g_time then
                spec.fieldInspectionActivePlayers[player] = nil
            end
        end
        updateFieldInspectionSoundActive(self, spec)
    end

    if self.isClient and spec.samples ~= nil then
        RMS_SoundManager.setSamplePlaying(spec.samples.inspection, not spec.isExcludedVehicle and spec.fieldInspectionSoundActive)
    end
end

-- weights of the ground, of raised dust and of debris
local RADIATOR_DUST = { field = 2, road = 0.5, dust = 1, debris = 2, wetnessPower = 3, cloggingPerHour = 0.35 / 9 }
local AIR_FILTER_DUST = { field = 2, road = 1, dust = 2, debris = 1, wetnessPower = 1, cloggingPerHour = 0.35 / 16 }

local function getDustRate(machine, spec, weights)
    local isOnField = machine:getIsOnField()
    local raisesDust = isOnField and spec.isImplementLowered and machine:getLastSpeed() > 0.1
    local dryness = math.max(1 - g_currentMission.environment.weather:getGroundWetness(), 0) ^ weights.wetnessPower
    local exposure = (isOnField and weights.field or weights.road) + (raisesDust and weights.dust or 0) + (spec.hasDebris and weights.debris or 0)
    return dryness * exposure * Washable.getIntervalMultiplier() * 2, raisesDust
end

---Blocks the radiator with the dust of the ground the machine drives on
function RMS_Consumables:updateRadiatorClogging(dt, canAccumulate)
    local spec = self.spec_RealisticMechanicalSystems
    if not spec.isVehicleNeedBlowOut then
        spec.radiatorClogging = 0
        return
    end

    spec.radiatorClogging = math.clamp(spec.radiatorClogging, 0, 1)
    spec.radiatorCloggingRate = 0
    if canAccumulate == false then
        return
    end

    local rate, raisesDust = getDustRate(self, spec, RADIATOR_DUST)
    spec.isRaisingDust = raisesDust
    if self:getLastSpeed() > 0.5 and spec.radiatorClogging < 1 then
        spec.radiatorCloggingRate = rate
        spec.radiatorClogging = math.min(spec.radiatorClogging + (dt / 3600000) * RADIATOR_DUST.cloggingPerHour * rate, 1)
    end
end

---Loads the air filter, part of the dust embedding past any blow out
function RMS_Consumables:updateAirFilterClogging(dt)
    local spec = self.spec_RealisticMechanicalSystems
    if not spec.isVehicleNeedBlowOut or spec.isElectricVehicle then
        spec.airFilterClogging, spec.airFilterResidue = 0, 0
        return
    end

    spec.airFilterCloggingRate = 0
    local rate = getDustRate(self, spec, AIR_FILTER_DUST)
    if self:getLastSpeed() > 0.5 and spec.airFilterClogging < 1 then
        local load = (dt / 3600000) * AIR_FILTER_DUST.cloggingPerHour * rate
        spec.airFilterCloggingRate = rate
        spec.airFilterClogging = math.min(spec.airFilterClogging + load, 1)
        spec.airFilterResidue = math.min(spec.airFilterResidue + load * RMS_Config.FIELD_CARE.AIR_FILTER_BLOWOUT_RESIDUE_SHARE,
            spec.airFilterClogging)
    end
end

---Blows the radiator clean and the air filter down to its embedded dust
function RMS_Consumables:cleanRadiatorAndAirFilter(dt)
    local spec = self.spec_RealisticMechanicalSystems
    local cleared = RMS_Config.FIELD_CARE.CLEANING_SPEED / 1000 * dt
    spec.radiatorClogging = math.max(spec.radiatorClogging - cleared, 0)
    spec.airFilterClogging = math.max(spec.airFilterClogging - cleared, spec.airFilterResidue)
    RMS_Config.TUTORIAL_MESSAGES.RAD_OR_FILTER_CLOGGED = true

    if self.isServer then
        RealisticMechanicalSystems.raiseRMSDirty(self, RealisticMechanicalSystems.SYNC_GROUP.FIELDCARE)
    end
end

---Tells whether a blow out can no longer clear the air filter
function RMS_Consumables.getIsAirFilterWornOut(spec)
    return spec.airFilterResidue >= RMS_Config.FIELD_CARE.AIR_FILTER_REPLACEMENT_RESIDUE
end

---Returns the loose dust of the air filter, the share a blow out removes
function RMS_Consumables.getAirFilterLooseDust(spec)
    return math.max(spec.airFilterClogging - spec.airFilterResidue, 0)
end

---Rates the blow out the air filter is due for
function RMS_Consumables.getAirFilterBlowOutStage(spec)
    if RMS_Consumables.getAirFilterLooseDust(spec) <= 0.15 then
        return 0
    elseif spec.airFilterClogging >= 0.60 then
        return 3
    elseif spec.airFilterClogging >= 0.35 then
        return 2
    end

    return 1
end

RMS_Consumables.FILTERS = {
    {
        stateKey = "fuelFilterClogging",
        systemKey = "fuel",
        breakdownId = "FUEL_FILTER_CLOGGING",
        getCloggingMultiplier = function(spec)
            return spec.fuelState.level < RMS_Config.CORE.FUEL_FACTOR_DATA.LOW_FUEL_THRESHOLD
                and RMS_Config.FIELD_CARE.FUEL_FILTER_LOW_FUEL_MULTIPLIER or 1
        end
    },
    {
        stateKey = "hydraulicFilterClogging",
        systemKey = "hydraulics",
        breakdownId = "HYDRAULIC_FILTER_CLOGGING",
        getCloggingMultiplier = function(spec)
            return spec.isHydraulicActive and RMS_Config.FIELD_CARE.HYDRAULIC_FILTER_ACTIVE_MULTIPLIER or 1
        end
    },
    {
        stateKey = "transmissionFilterClogging",
        systemKey = "transmission",
        breakdownId = "TRANSMISSION_FILTER_CLOGGING",
        getCloggingMultiplier = function(spec)
            return 1
        end
    },
    {
        stateKey = "adBlueFilterClogging",
        systemKey = "fuel",
        breakdownId = "ADBLUE_FILTER_CLOGGING",
        getCloggingMultiplier = function(spec)
            return 1 / RMS_Config.FIELD_CARE.ADBLUE_FILTER_SERVICE_INTERVALS
        end,
        maintenanceType = "PREVENTIVE"
    },
    {
        stateKey = "sparkPlugWear",
        systemKey = "electrical",
        breakdownId = "SPARK_PLUG_WEAR",
        hours = RMS_Config.FIELD_CARE.SPARK_PLUG_HOURS,
        getCloggingMultiplier = function()
            return RMS_Config.SERVICE_REFERENCE_HOURS / RMS_Config.FIELD_CARE.SPARK_PLUG_HOURS
        end
    }
}

---Tells whether a service changes a filter now rather than at the next
function RMS_Consumables.getIsFilterDue(vehicle, filter)
    if filter.hours == nil then
        return true
    end
    local nextService = RealisticMechanicalSystems.getServiceProgramHours(vehicle, "engine") / filter.hours
    return vehicle.spec_RealisticMechanicalSystems[filter.stateKey] + nextService > 1
end

---Returns the tracked filter a breakdown shows
function RMS_Consumables.getFilterOfBreakdown(breakdownId)
    for _, filter in ipairs(RMS_Consumables.FILTERS) do
        if filter.breakdownId == breakdownId then
            return filter
        end
    end
    return nil
end

---Tells whether a machine carries a filter
function RMS_Consumables.getHasFilter(vehicle, filter)
    return vehicle.spec_RealisticMechanicalSystems.systems[filter.systemKey].enabled
        and RMS_Breakdowns.BreakdownRegistry[filter.breakdownId].isApplicable(vehicle)
end

---Returns the stage of its breakdown a filter's clogging has reached
function RMS_Consumables.getFilterStage(clogging)
    local stage = 0
    for index, threshold in ipairs(RMS_Config.FIELD_CARE.FILTER_STAGE_THRESHOLDS) do
        if clogging >= threshold then
            stage = index
        end
    end
    return stage
end

---Clogs the fuel and hydraulic filters over the engine hours
function RMS_Consumables:updateFilterClogging(operatingDt)
    local spec = self.spec_RealisticMechanicalSystems
    local intervals = operatingDt / (60 * 60 * 1000) / self:getServiceReferenceInterval()
    local thresholds = RMS_Config.FIELD_CARE.FILTER_STAGE_THRESHOLDS

    for _, filter in ipairs(RMS_Consumables.FILTERS) do
        if RMS_Consumables.getHasFilter(self, filter) then
            spec[filter.stateKey] = math.min(spec[filter.stateKey] + intervals * filter.getCloggingMultiplier(spec),
                thresholds[#thresholds])
        end
    end
end

---Shows each filter's clogging as its breakdown at the stage reached
function RMS_Consumables.syncFilterBreakdowns(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    for _, filter in ipairs(RMS_Consumables.FILTERS) do
        local stage = RMS_Consumables.getFilterStage(spec[filter.stateKey])
        local breakdown = spec.activeBreakdowns[filter.breakdownId]

        if stage == 0 then
            if breakdown ~= nil then
                vehicle:removeBreakdown(filter.breakdownId)
            end
        else
            if breakdown == nil then
                vehicle:addBreakdown(filter.breakdownId, stage)
            elseif breakdown.stage ~= stage then
                vehicle:changeBreakdownStage(filter.breakdownId, stage)
            end

            breakdown = spec.activeBreakdowns[filter.breakdownId]
            if breakdown ~= nil and not breakdown.isVisible
                and stage == #RMS_Breakdowns.BreakdownRegistry[filter.breakdownId].stages then
                breakdown.isVisible = true
                RealisticMechanicalSystems.raiseRMSDirty(vehicle, RealisticMechanicalSystems.SYNC_GROUP.BREAKDOWNS)
            end
        end
    end
end

-- @param string? breakdownId breakdown of the one filter replaced, every filter when nil
function RMS_Consumables.renewFilters(vehicle, breakdownId, maintenanceType)
    local spec = vehicle.spec_RealisticMechanicalSystems
    for _, filter in ipairs(RMS_Consumables.FILTERS) do
        if (breakdownId == nil or breakdownId == filter.breakdownId)
            and (maintenanceType == nil or (filter.maintenanceType == nil
                or RealisticMechanicalSystems.MAINTENANCE_TYPES[filter.maintenanceType] == maintenanceType)
                and RMS_Consumables.getIsFilterDue(vehicle, filter)) then
            spec[filter.stateKey] = 0
            vehicle:removeBreakdown(filter.breakdownId)
        end
    end
end

-- @return float rate share of the sump per hour
function RMS_Consumables.getEngineOilBurnRate(vehicle)
    local C = RMS_Config.FLUIDS
    local spec = vehicle.spec_RealisticMechanicalSystems
    local interval = math.max(tonumber(vehicle:getServiceReferenceInterval()) or 0, 0.001)
    local oilSmoke = spec.activeEffects.EXHAUST_OIL ~= nil and spec.activeEffects.EXHAUST_OIL.value or 0
    local worn = math.min(oilSmoke / OIL_SMOKE_OF_WORN_ENGINE, 1)
    local load = math.clamp(tonumber(spec.dynamicMotorLoad) or 0.5, 0, 1)
    local loadFactor = (1 - C.ENGINE_OIL_LOAD_SHARE * 0.5) + C.ENGINE_OIL_LOAD_SHARE * load
    return (C.ENGINE_OIL_CONSUMPTION_PER_INTERVAL / interval) * (1 + C.ENGINE_OIL_WEAR_CONSUMPTION * worn ^ 2) * loadFactor
end

---Consumes engine oil and drains any leaking fluid over the operating time
function RMS_Consumables:updateFluidLevels(operatingDt)
    local spec = self.spec_RealisticMechanicalSystems
    local hours = (tonumber(operatingDt) or 0) / (60 * 60 * 1000)
    if hours <= 0 or spec.systems == nil then
        return
    end

    if spec.systems.engine.enabled and not spec.isElectricVehicle then
        local rate = RMS_Consumables.getEngineOilBurnRate(self)
        RMS_Fluids.removeLiters(self, "engineOil", rate * hours * RMS_Fluids.getCapacity(self, "engineOil"))
    end

    if spec.systems.cooling.enabled then
        local lost = RMS_Fluids.removeLiters(self, "coolant", (tonumber(spec.coolantLeakRate) or 0) * hours * RMS_Fluids.getCapacity(self, "coolant"))
        RMS_Fluids.recordLeakLoss(self, "coolant", lost)
    end

    if spec.systems.transmission.enabled then
        local lost = RMS_Fluids.removeLiters(self, "transmissionOil", (tonumber(spec.transmissionOilLeakRate) or 0) * hours * RMS_Fluids.getCapacity(self, "transmissionOil"))
        RMS_Fluids.recordLeakLoss(self, "transmissionOil", lost)
    end

    if spec.systems.hydraulics.enabled then
        local lost = RMS_Fluids.removeLiters(self, "hydraulicFluid", (tonumber(spec.hydraulicFluidLeakRate) or 0) * hours * RMS_Fluids.getCapacity(self, "hydraulicFluid"))
        RMS_Fluids.recordLeakLoss(self, "hydraulicFluid", lost)
    end
end

---Returns how much fluid the machine is missing, in whole charges
function RMS_Consumables:getMissingFluidShare()
    local spec = self.spec_RealisticMechanicalSystems
    local missing = 0

    for _, circuit in ipairs(RMS_Fluids.getSumpCircuits(self)) do
        local systemData = spec.systems ~= nil and spec.systems[RMS_Fluids.CIRCUITS[circuit].systemKey] or nil
        if systemData ~= nil and systemData.enabled ~= false then
            missing = missing + (1 - RMS_Fluids.getLevel(self, circuit))
        end
    end

    return missing
end

---Fills back the fluids nothing leaks any more
function RMS_Consumables:topUpRepairedLeaks(breakdownIds)
    RMS_Fluids.restoreRepairedLeakLosses(self, breakdownIds or self.spec_RealisticMechanicalSystems.pendingSelectedBreakdowns or {})
end

---Fills every fluid the machine carries back up
function RMS_Consumables:refillVehicleFluids()
    for _, circuit in ipairs(RMS_Fluids.CIRCUIT_ORDER) do
        if RMS_Fluids.getCapacity(self, circuit) > 0 then
            RMS_Fluids.replaceCircuit(self, circuit)
        end
    end
end

---Returns a physical circuit capacity in liters
function RMS_Consumables:getFluidCapacity(circuit)
    return RMS_Fluids.getCapacity(self, circuit)
end

---Returns the physical quantity currently in a circuit
function RMS_Consumables:getFluidLiters(circuit)
    return RMS_Fluids.getLiters(self, circuit)
end

---Returns the physical quantity missing from a circuit
function RMS_Consumables:getMissingFluidLiters(circuit)
    return RMS_Fluids.getMissingLiters(self, circuit)
end

---Returns mixture compatibility for a circuit
function RMS_Consumables:getFluidCompatibility(circuit)
    return RMS_Fluids.getCompatibility(self, circuit)
end

---Adds a catalogue product to a circuit
function RMS_Consumables:addFluidLiters(circuit, liters, productKey)
    return RMS_Fluids.addLiters(self, circuit, liters, productKey)
end

---Replaces a circuit with compatible fluid
function RMS_Consumables:replaceFluidCircuit(circuit)
    RMS_Fluids.replaceCircuit(self, circuit)
end

---Starts a field inspection, engine stopped and out of any service
function RMS_Consumables:startFieldVisualInspectionProcess()
    local spec = self.spec_RealisticMechanicalSystems
    if spec.isExcludedVehicle then
        return false
    elseif self:getIsMotorStarted() then
        g_currentMission:showBlinkingWarning(g_i18n:getText("rms_field_inspection_engine_must_be_stopped"), 2200)
        return false
    elseif spec.fieldInspection.isActive or self:getCurrentStatus() ~= RealisticMechanicalSystems.STATUS.READY then
        return false
    end

    spec.fieldInspection.isActive = true
    spec.fieldInspection.elapsedTime = 0
    spec.fieldInspection.duration = RMS_Config.FIELD_CARE.VISUAL_INSPECTION_DURATION
    RMS_FieldInspectionEvent.send(self, true)
    return true
end
