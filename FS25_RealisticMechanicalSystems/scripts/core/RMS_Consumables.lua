-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---Consumable upkeep of a vehicle: radiator and filter clogging, lubrication, field inspection
RMS_Consumables = RMS_Consumables or {}

---Flags the field inspection sound dirty when its players change
local function updateFieldInspectionSoundActive(vehicle, spec)
    local isActive = next(spec.fieldInspectionActivePlayers) ~= nil
    if spec.fieldInspectionSoundActive ~= isActive then
        spec.fieldInspectionSoundActive = isActive
        RealisticMechanicalSystems.raiseRMSDirty(vehicle, RealisticMechanicalSystems.SYNC_GROUP.FIELDCARE)
        vehicle:raiseActive()
    end
end

---Registers a player as inspecting this vehicle
-- @param table player player
-- @param boolean isActive true when the inspection starts
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

---Accumulates radiator clogging from ground wetness, field work, dust and debris
-- @param float dt time since last call in ms
-- @param boolean? canAccumulate true while the vehicle is operating
function RMS_Consumables:updateRadiatorClogging(dt, canAccumulate)
    local spec = self.spec_RealisticMechanicalSystems
    if spec == nil then
        return
    end

    if not spec.isVehicleNeedBlowOut then
        spec.radiatorClogging = 0
        return
    end

    spec.radiatorClogging = math.clamp(spec.radiatorClogging or 0, 0, 1)
    if canAccumulate == false then
        return
    end

    if spec.debugData == nil then
        spec.debugData = {}
    end
    if spec.debugData.radiator == nil then
        spec.debugData.radiator = {
            baseWetnessFactor = 1.0,
            isOnField = false,
            hasDust = false,
            hasDebris = false,
            totalMultiplier = 0.0
        }
    end
    local dbg = RMS_Utils.getIsDebugDataWanted(self) and spec.debugData.radiator or nil

    local lastSpeed = self:getLastSpeed()
    local wetness = g_currentMission.environment.weather:getGroundWetness()
    local baseWetnessFactor = math.max(1 - wetness, 0)
    local wetnessFactor = math.max(baseWetnessFactor ^ 3, 0)
    local isOnField = self:getIsOnField()
    local hasDust = isOnField and spec.isImplementLowered and lastSpeed > 0.1
    local fieldFactor = isOnField and 2.0 or 0.5
    local dustFactor = hasDust and 1.0 or 0.0
    local debrisFactor = spec.hasDebris and 2.0 or 0.0

    if dbg then
        dbg.baseWetnessFactor = baseWetnessFactor
        dbg.isOnField = isOnField
        dbg.hasDust = hasDust
        dbg.hasDebris = spec.hasDebris
        dbg.totalMultiplier = 0.0
    end

    if lastSpeed > 0.5 and spec.radiatorClogging < 1.0 then
        local totalMultiplier = wetnessFactor * (fieldFactor + dustFactor + debrisFactor) * Washable.getIntervalMultiplier() * 2
        if dbg then dbg.totalMultiplier = totalMultiplier end

        -- at normal dirt speed dry field work reaches the cleaning threshold in 3 hours
        local change = (dt / 3600000) * (0.35 / 9) * totalMultiplier
        spec.radiatorClogging = math.min(spec.radiatorClogging + change, 1.0)
    end
end

---Accumulates air intake clogging, weighted on its own
-- @param float dt time since last call in ms
function RMS_Consumables:updateAirFilterClogging(dt)
    local C = RMS_Config.FIELD_CARE
    local spec = self.spec_RealisticMechanicalSystems
    if spec == nil then
        return
    end

    -- an electric motor breathes no air
    if not spec.isVehicleNeedBlowOut or spec.isElectricVehicle then
        spec.airFilterClogging = 0
        spec.airFilterResidue = 0
        return
    end

    if spec.debugData == nil then
        spec.debugData = {}
    end
    if spec.debugData.airFilter == nil then
        spec.debugData.airFilter = {
            baseWetnessFactor = 1.0,
            isOnField = false,
            hasDust = false,
            hasDebris = false,
            totalMultiplier = 0.0
        }
    end
    local dbg = RMS_Utils.getIsDebugDataWanted(self) and spec.debugData.airFilter or nil

    local lastSpeed = self:getLastSpeed()
    local wetness = g_currentMission.environment.weather:getGroundWetness()
    local baseWetnessFactor = math.max(1 - wetness, 0)
    local wetnessFactor = baseWetnessFactor
    local isOnField = self:getIsOnField()
    local hasDust = isOnField and spec.isImplementLowered and lastSpeed > 0.1
    local fieldFactor = isOnField and 2.0 or 1.0
    local dustFactor = hasDust and 2.0 or 0.0
    local debrisFactor = spec.hasDebris and 1.0 or 0.0

    if dbg then
        dbg.baseWetnessFactor = baseWetnessFactor
        dbg.isOnField = isOnField
        dbg.hasDust = hasDust
        dbg.hasDebris = spec.hasDebris
        dbg.totalMultiplier = 0.0
    end

    -- air filter clogging from working hours in dust
    if lastSpeed > 0.5 and spec.airFilterClogging < 1.0 then
        local totalMultiplier = wetnessFactor * (fieldFactor + dustFactor + debrisFactor) * Washable.getIntervalMultiplier() * 2
        if dbg then dbg.totalMultiplier = totalMultiplier end

        -- at normal dirt speed dry field work reaches the cleaning threshold in 4 hours
        local change = (dt / 3600000) * (0.35 / 16) * totalMultiplier
        spec.airFilterClogging = math.min(spec.airFilterClogging + change, 1.0)

        -- dust embedded in the media, cleared by a replacement only
        local residueShare = tonumber(C.AIR_FILTER_BLOWOUT_RESIDUE_SHARE) or 0
        spec.airFilterResidue = math.min((spec.airFilterResidue or 0) + change * residueShare, spec.airFilterClogging)
    end
end

---Clears radiator and air intake clogging at the configured cleaning speed
-- @param float dt time since last call in ms
function RMS_Consumables:cleanRadiatorAndAirFilter(dt)
    local C = RMS_Config.FIELD_CARE
    local spec = self.spec_RealisticMechanicalSystems
    if spec == nil then
        return
    end

    local prevRadiatorClogging = tonumber(spec.radiatorClogging) or 0
    local prevAirFilterClogging = tonumber(spec.airFilterClogging) or 0
    local airFilterResidue = math.clamp(tonumber(spec.airFilterResidue) or 0, 0, 1)
    local cleaningDelta = (C.CLEANING_SPEED / 1000) * dt

    spec.radiatorClogging = math.max(prevRadiatorClogging - cleaningDelta, 0)
    -- blowing out stops at the residue
    spec.airFilterClogging = math.max(prevAirFilterClogging - cleaningDelta, airFilterResidue)

    RMS_Config.TUTORIAL_MESSAGES.RAD_OR_FILTER_CLOGGED = true

    if self.isServer then
        RealisticMechanicalSystems.raiseRMSDirty(self, RealisticMechanicalSystems.SYNC_GROUP.FIELDCARE)
    end
end

---Tells whether a blow out can no longer clear the air filter
-- @param table spec vehicle spec
-- @return boolean isWornOut true when the filter is due for replacement
function RMS_Consumables.getIsAirFilterWornOut(spec)
    return spec.airFilterResidue >= RMS_Config.FIELD_CARE.AIR_FILTER_REPLACEMENT_RESIDUE
end

---Returns the loose dust of the air filter, the share a blow out removes
-- @param table spec vehicle spec
-- @return float looseDust clogging above the residue
function RMS_Consumables.getAirFilterLooseDust(spec)
    return math.max(spec.airFilterClogging - spec.airFilterResidue, 0)
end

---Rates the blow out the air filter is due for
-- @param table spec vehicle spec
-- @return integer stage 0 nothing worth blowing out, 1 slightly dirty, 2 dirty, 3 heavily clogged
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

-- fuel and hydraulic filters, with their system and the breakdown they show as
RMS_Consumables.FILTERS = {
    {
        stateKey = "fuelFilterClogging",
        systemKey = "fuel",
        breakdownId = "FUEL_FILTER_CLOGGING",
        -- the pick-up draws the bottom water and sediment of a tank on its reserve
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
    }
}

---Returns the tracked filter a breakdown shows
-- @param string breakdownId breakdown id
-- @return table? filter filter entry, nil for any other breakdown
function RMS_Consumables.getFilterOfBreakdown(breakdownId)
    for _, filter in ipairs(RMS_Consumables.FILTERS) do
        if filter.breakdownId == breakdownId then
            return filter
        end
    end
    return nil
end

---Tells whether a machine carries a filter
-- @param table vehicle vehicle
-- @param table filter filter entry
-- @return boolean hasFilter true when the machine has it
function RMS_Consumables.getHasFilter(vehicle, filter)
    return vehicle.spec_RealisticMechanicalSystems.systems[filter.systemKey].enabled
        and RMS_Breakdowns.BreakdownRegistry[filter.breakdownId].isApplicable(vehicle)
end

---Returns the stage of its breakdown a filter's clogging has reached
-- @param float clogging filter clogging, 1 when its change falls due
-- @return integer stage 0 before its change is due, up to the last stage
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
-- @param float operatingDt operating time since last call in ms
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
-- @param table vehicle vehicle
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

            -- refused when the machine already carries as many breakdowns as it can
            breakdown = spec.activeBreakdowns[filter.breakdownId]
            if breakdown ~= nil and not breakdown.isVisible
                and stage == #RMS_Breakdowns.BreakdownRegistry[filter.breakdownId].stages then
                breakdown.isVisible = true
                RealisticMechanicalSystems.raiseRMSDirty(vehicle, RealisticMechanicalSystems.SYNC_GROUP.BREAKDOWNS)
            end
        end
    end
end

---Fits new filters, all or the one a breakdown names
-- @param table vehicle vehicle
-- @param string? breakdownId breakdown of the one filter replaced, every filter when nil
function RMS_Consumables.renewFilters(vehicle, breakdownId)
    local spec = vehicle.spec_RealisticMechanicalSystems
    for _, filter in ipairs(RMS_Consumables.FILTERS) do
        if breakdownId == nil or breakdownId == filter.breakdownId then
            spec[filter.stateKey] = 0
            vehicle:removeBreakdown(filter.breakdownId)
        end
    end
end

---Drops the lubrication level once per period unless greased
function RMS_Consumables:onLubricationPeriodChanged()
    local C = RMS_Config.FIELD_CARE
    local spec = self.spec_RealisticMechanicalSystems
    if not self.isServer or spec == nil or spec.isExcludedVehicle or not spec.isVehicleNeedLubricate then
        return
    end

    if not spec.lubricationUsedThisPeriod then
        spec.lubricationLevel = math.max(
            (tonumber(spec.lubricationLevel) or 1.0) - C.LUBRICATION_REDUCE_PER_PERIOD,
            0
        )
        RealisticMechanicalSystems.raiseRMSDirty(self, RealisticMechanicalSystems.SYNC_GROUP.FIELDCARE)
    end

    spec.lubricationUsedThisPeriod = false
end

---Consumes lubrication over the operating time
-- @param float operatingDt operating time since last call in ms
-- @param integer motorState motor state
function RMS_Consumables:updateLubricationLevel(operatingDt, motorState)
    local C = RMS_Config.FIELD_CARE
    local spec = self.spec_RealisticMechanicalSystems
    if not spec.isVehicleNeedLubricate then
        return
    end

    if motorState == MotorState.ON then
        spec.lubricationUsedThisPeriod = true
    end

    spec.lubricationLevel = math.max(
        spec.lubricationLevel - C.LUBRICATION_REDUCE_PER_OPERATING_HOUR * operatingDt / (60 * 60 * 1000),
        0
    )
end

---Consumes engine oil and drains any leaking fluid over the operating time
-- @param float operatingDt operating time since last call in ms
function RMS_Consumables:updateFluidLevels(operatingDt)
    local C = RMS_Config.FLUIDS
    local spec = self.spec_RealisticMechanicalSystems
    local hours = (tonumber(operatingDt) or 0) / (60 * 60 * 1000)
    if hours <= 0 or spec.systems == nil then
        return
    end

    -- an engine burns oil over its service interval, a worn one burns much more
    if spec.systems.engine.enabled and not spec.isElectricVehicle then
        local interval = math.max(tonumber(self:getServiceReferenceInterval()) or 0, 0.001)
        local condition = math.clamp(tonumber(spec.systems.engine.condition) or 1, 0, 1)
        local load = math.clamp(tonumber(spec.dynamicMotorLoad) or 0.5, 0, 1)
        local loadFactor = (1 - C.ENGINE_OIL_LOAD_SHARE * 0.5) + C.ENGINE_OIL_LOAD_SHARE * load
        local rate = (C.ENGINE_OIL_CONSUMPTION_PER_INTERVAL / interval) * (1 + C.ENGINE_OIL_WEAR_CONSUMPTION * (1 - condition)) * loadFactor
        RMS_Fluids.removeLiters(self, "engineOil", rate * hours * RMS_Fluids.getCapacity(self, "engineOil"))
    end

    -- the other three fluids only go down through a leak
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
-- @return float share sum of what every fluid it carries is missing
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

---Restores one grease gun charge of lubrication, capped at full
function RMS_Consumables:lubricateVehicle()
    local C = RMS_Config.FIELD_CARE
    local spec = self.spec_RealisticMechanicalSystems

    spec.lubricationLevel = math.min(spec.lubricationLevel + C.LUBRICATION_RESTORE_PER_USE, 1.0)
    spec.lubricationUsedThisPeriod = true

    RMS_Config.TUTORIAL_MESSAGES.NEEDS_LUBRICATION = true

    if self.isServer then
        RealisticMechanicalSystems.raiseRMSDirty(self, RealisticMechanicalSystems.SYNC_GROUP.FIELDCARE)
    end
end

---Starts a field inspection, refused while running or in service
-- @return boolean started true when the inspection began
function RMS_Consumables:startFieldVisualInspectionProcess()
    local spec = self.spec_RealisticMechanicalSystems
    if spec == nil or spec.isExcludedVehicle then
        return false
    end

    if self.getIsMotorStarted ~= nil and self:getIsMotorStarted() then
        if self.isClient then
            g_currentMission:showBlinkingWarning(g_i18n:getText("rms_field_inspection_engine_must_be_stopped"), 2200)
        end
        return false
    end

    if self:getCurrentStatus() ~= RealisticMechanicalSystems.STATUS.READY then
        return false
    end

    local inspection = spec.fieldInspection
    if inspection == nil then
        return false
    end

    if inspection.isActive then
        return false
    end

    inspection.isActive = true
    inspection.elapsedTime = 0
    inspection.duration = RMS_Config.FIELD_CARE.VISUAL_INSPECTION_DURATION
    inspection.startTime = g_time
    inspection.targetVehicle = self

    local node = self.rootNode
    if (node == nil or node == 0) and self.components ~= nil and self.components[1] ~= nil then
        node = self.components[1].node
    end
    inspection.targetNode = node

    RMS_FieldInspectionEvent.send(self, true)

    return true
end
