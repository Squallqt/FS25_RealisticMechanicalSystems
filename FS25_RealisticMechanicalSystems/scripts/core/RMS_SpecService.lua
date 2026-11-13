-- Copyright © 2026 Squallqt. All rights reserved.

---Vehicle workshop services.

local log_dbg = RMS_Utils.createLogger("[RMS_SPEC]")
local getSafeMissionTimeScale = RealisticMechanicalSystems.getSafeMissionTimeScale

local function isBreakdownSelectedForPlayerRepair(breakdownId, breakdown, optionOne)
    local breakdownDef = RMS_Breakdowns.BreakdownRegistry[breakdownId]
    if breakdownDef == nil or breakdownDef.isSelectable ~= true then
        return false
    end

    local isSelectedForQuickFix = breakdown.isSelectedForRepair and breakdown.isVisible and (optionOne == RealisticMechanicalSystems.REPAIR_TYPES.LOW and breakdown.isActive)
    local isSelectedForStandartRepair = breakdown.isSelectedForRepair
        and breakdown.isVisible
        and (optionOne == RealisticMechanicalSystems.REPAIR_TYPES.MEDIUM
            or optionOne == RealisticMechanicalSystems.REPAIR_TYPES.HIGH)
    return isSelectedForStandartRepair or isSelectedForQuickFix
end

---Tells whether a picked fault is in a repair, warranty ones always
local function getIsFaultInRepair(vehicle, breakdownId, breakdown, optionOne, workshopType)
    return isBreakdownSelectedForPlayerRepair(breakdownId, breakdown, optionOne)
        or isBreakdownSelectedForPlayerRepair(breakdownId, breakdown, RealisticMechanicalSystems.REPAIR_TYPES.MEDIUM)
            and vehicle:isWarrantyRepairCovered(workshopType, breakdownId)
end

---Returns the method and parts of a fault, the warranty's if covered
function RealisticMechanicalSystems.getFaultRepairOptions(vehicle, breakdownId, optionOne, optionTwo, workshopType)
    if vehicle:isWarrantyRepairCovered(workshopType, breakdownId) then
        return RealisticMechanicalSystems.REPAIR_TYPES.MEDIUM, RealisticMechanicalSystems.PART_TYPES.OEM
    end
    return optionOne, optionTwo
end

---Returns the faults a repair puts right, in the order it works on them
function RealisticMechanicalSystems.getRepairQueue(vehicle, optionOne, workshopType)
    local ids = {}
    for id, breakdown in pairs(vehicle:getActiveBreakdowns()) do
        if getIsFaultInRepair(vehicle, id, breakdown, optionOne, workshopType) then
            table.insert(ids, id)
        end
    end
    table.sort(ids)
    return ids
end

---Returns the rebuild kit a part belongs to, the first that lists it
-- @return table? group key, price share and parts of the kit
function RealisticMechanicalSystems.getRenewalGroup(partId)
    for _, group in ipairs(RMS_Config.CORE.RENEWAL_GROUPS) do
        if table.hasElement(group.parts, partId) then
            return group
        end
    end
    return nil
end

---Lists the worn parts picked for a preventive replacement, by id
-- @return table parts ids still listed by the last complete report
function RealisticMechanicalSystems.getPreventiveParts(vehicle)
    local picked, parts = vehicle.spec_RealisticMechanicalSystems.preventiveParts, {}
    for _, entry in ipairs(RMS_Utils.getInspectedWornParts(vehicle)) do
        if picked[entry.partId] ~= nil then
            table.insert(parts, entry.partId)
        end
    end
    table.sort(parts)
    return parts
end

---Picks a worn part for a preventive replacement, or puts it back
function RealisticMechanicalSystems.togglePreventivePart(vehicle, partId)
    local picked = vehicle.spec_RealisticMechanicalSystems.preventiveParts
    -- a used part offered for it comes from a donor drawn once
    picked[partId] = picked[partId] == nil and (RealisticMechanicalSystems.drawUsedPartDonorHours(partId) or 0) or nil
end

---Lists the parts a repair of a fault fits, the fault's own first
-- @param table partWear wear of each tracked part before this fault's repair
-- @param function isBroken tells whether a part still waits for the repair of its own fault
function RealisticMechanicalSystems.getRepairFittedParts(vehicle, breakdownId, stage, repairType, partWear, isBroken)
    local parts = { breakdownId }
    local function fit(partId)
        if partWear[partId] ~= nil and not isBroken(partId) and not table.hasElement(parts, partId) then
            table.insert(parts, partId)
        end
    end
    local definition = RMS_Breakdowns.BreakdownRegistry[breakdownId]
    for _, partId in ipairs(definition.stages[stage].renews or {}) do
        fit(partId)
    end
    if repairType == RealisticMechanicalSystems.REPAIR_TYPES.HIGH then
        local group = RealisticMechanicalSystems.getRenewalGroup(breakdownId)
        for _, partId in ipairs(group ~= nil and group.parts or {}) do
            fit(partId)
        end
        local systemKey = RMS_Utils.getSystemKey(RealisticMechanicalSystems.SYSTEMS, definition.system)
        for _, partId in ipairs(vehicle.spec_RealisticMechanicalSystems.systemParts[systemKey]) do
            if RMS_Utils.getIsPartWorn(partId, partWear[partId]) then
                fit(partId)
            end
        end
    end
    return parts
end

---Lists the parts a repair replaces beside each fault's own part
-- @return table parts breakdown ids by the fault whose repair replaces them, each part listed once
function RealisticMechanicalSystems.getRepairReplacedParts(vehicle, optionOne, optionTwo, workshopType)
    local R = RealisticMechanicalSystems
    local spec = vehicle.spec_RealisticMechanicalSystems
    local partWear, listed, replaced = RMS_Utils.shallowCopy(spec.partWear), {}, {}
    local queue = R.getRepairQueue(vehicle, optionOne, workshopType)
    -- the faults still waiting keep their parts, as during the work
    local waiting = {}
    for id in pairs(spec.activeBreakdowns) do
        waiting[id] = true
    end
    local function isBroken(partId)
        return waiting[partId] == true
    end
    for _, id in ipairs(queue) do
        listed[id] = true
    end

    for _, id in ipairs(queue) do
        local fault = spec.activeBreakdowns[id]
        local repairType, partType = R.getFaultRepairOptions(vehicle, id, optionOne, optionTwo, workshopType)
        replaced[id] = {}
        if repairType ~= R.REPAIR_TYPES.LOW then
            waiting[id] = nil
            local wear = partType == R.PART_TYPES.USED and fault.usedPartHours ~= nil
                and fault.usedPartHours / RMS_Config.CORE.MACHINE_LIFE_HOURS or 0
            for _, partId in ipairs(R.getRepairFittedParts(vehicle, id, fault.stage, repairType, partWear, isBroken)) do
                if partWear[partId] ~= nil then
                    partWear[partId] = wear
                end
                if not listed[partId] then
                    listed[partId] = true
                    table.insert(replaced[id], partId)
                end
            end
        end
    end
    return replaced
end

local function getIsSelectableBreakdown(breakdownId)
    local breakdownDef = RMS_Breakdowns.BreakdownRegistry[breakdownId]
    if breakdownDef == nil or breakdownDef.isSelectable ~= true then
        return false
    end
    return true
end

local function getRenewedParts(vehicle, maintenanceType)
    local spec = vehicle.spec_RealisticMechanicalSystems
    local ids = {}
    for _, filter in ipairs(RMS_Consumables.FILTERS) do
        if filter.hours ~= nil and RMS_Consumables.getHasFilter(vehicle, filter) and RMS_Consumables.getIsFilterDue(vehicle, filter) then
            table.insert(ids, filter.breakdownId)
        end
    end
    if maintenanceType ~= RealisticMechanicalSystems.MAINTENANCE_TYPES.PREVENTIVE then
        return ids
    end
    for _, partId in ipairs(RealisticMechanicalSystems.MAJOR_SERVICE_CHECKS) do
        local wear = spec.partWear[partId]
        if wear ~= nil and RMS_Breakdowns.BreakdownRegistry[partId].system == RealisticMechanicalSystems.SYSTEMS.HARVEST
            and RMS_Utils.getIsPartWorn(partId, wear) then
            table.insert(ids, partId)
        end
    end
    return ids
end

local AGRICULTURAL_PRICE_FACTORS = { labour = 1, filters = 1, parts = 1 }

local function getSizeScale(vehicle, exponent, factorKey)
    local C = RMS_Config.MAINTENANCE
    local factors = C.PROFILE_PRICE_FACTORS[RMS_Fluids.getProfileName(vehicle)] or AGRICULTURAL_PRICE_FACTORS
    return (RMS_Fluids.getEnginePower(vehicle) / C.REFERENCE_POWER) ^ exponent * factors[factorKey]
end

local function getLabourHours(vehicle, hours, category)
    return hours * getSizeScale(vehicle, RMS_Config.MAINTENANCE.LABOUR_POWER_EXPONENT, "labour")
        * RMS_Utils.getServiceAccessLabourFactor(vehicle, category)
end

function RealisticMechanicalSystems.getRepairLabourHours(vehicle, breakdownId, repairType)
    local C = RMS_Config.MAINTENANCE
    local operation = C.REPAIR_OPERATIONS[breakdownId]
    if operation == nil then return 0 end
    local key = RMS_Utils.getKeyByValue(RealisticMechanicalSystems.REPAIR_TYPES, repairType)
    return getLabourHours(vehicle, operation.hours * C.REPAIR_TIME_MULTIPLIERS[key], operation.category)
end

local function getOverhaulAccessFactor(vehicle, systemName)
    local systems = RealisticMechanicalSystems.SYSTEMS
    local function getFactor(name)
        local key = RMS_Utils.getKeyByValue(systems, name) or string.upper(name)
        local category = (key == "TRANSMISSION" or key == "PTO") and "transmission" or "mechanical"
        return RMS_Utils.getServiceAccessLabourFactor(vehicle, category)
    end
    if systemName ~= nil then return getFactor(systemName) end
    local factor = 1
    for key in pairs(vehicle.spec_RealisticMechanicalSystems.systems) do
        factor = factor + (getFactor(key) - 1) * RMS_Utils.getEffectiveSystemWeight(vehicle, key, systems)
    end
    return factor
end

---Returns the real work hours of a service
-- @param string? workshopType workshop of a repair, whose warranty sets the method of its faults
function RealisticMechanicalSystems.getServiceWorkHours(vehicle, serviceType, optionOne, optionTwo, workshopType)
    local C, states = RMS_Config.MAINTENANCE, RealisticMechanicalSystems.STATUS
    if serviceType == states.INSPECTION then
        local key = RMS_Utils.getKeyByValue(RealisticMechanicalSystems.INSPECTION_TYPES, optionOne)
        return getLabourHours(vehicle, C.INSPECTION_TIME * C.INSPECTION_TIME_MULTIPLIERS[key] / 3600000,
            key == "VISUAL" and "external" or "diagnostic")
    elseif serviceType == states.MAINTENANCE then
        local key = RMS_Utils.getKeyByValue(RealisticMechanicalSystems.MAINTENANCE_TYPES, optionOne)
        local hours = getLabourHours(vehicle, C.MAINTENANCE_LABOUR_HOURS[key], "maintenance")
        for _, partId in ipairs(getRenewedParts(vehicle, optionOne)) do
            hours = hours + RealisticMechanicalSystems.getRepairLabourHours(vehicle, partId, RealisticMechanicalSystems.REPAIR_TYPES.MEDIUM)
        end
        return hours
    elseif serviceType == states.REPAIR then
        local R, hours = RealisticMechanicalSystems, 0
        for id, breakdown in pairs(vehicle:getActiveBreakdowns() or {}) do
            if getIsFaultInRepair(vehicle, id, breakdown, optionOne, workshopType) then
                local repairType = R.getFaultRepairOptions(vehicle, id, optionOne, optionTwo, workshopType)
                hours = hours + R.getRepairLabourHours(vehicle, id, repairType)
            end
        end
        -- a part picked in prevention adds its work, unless already fitted
        if optionOne ~= R.REPAIR_TYPES.LOW then
            local fitted = {}
            for _, parts in pairs(R.getRepairReplacedParts(vehicle, optionOne, optionTwo, workshopType)) do
                for _, partId in ipairs(parts) do
                    fitted[partId] = true
                end
            end
            for _, id in ipairs(R.getPreventiveParts(vehicle)) do
                hours = hours + (fitted[id] and 0 or R.getRepairLabourHours(vehicle, id, R.REPAIR_TYPES.MEDIUM))
            end
        end
        return hours
    elseif serviceType == states.OVERHAUL then
        local key = RMS_Utils.getKeyByValue(RealisticMechanicalSystems.OVERHAUL_TYPES, optionOne)
        local hours = C.OVERHAUL_TIME * C.OVERHAUL_TIME_MULTIPLIERS[key] / 3600000
        if optionOne == RealisticMechanicalSystems.OVERHAUL_TYPES.PARTIAL then
            hours = hours * RMS_Utils.getEffectiveSystemWeight(vehicle, optionTwo, RealisticMechanicalSystems.SYSTEMS)
        end
        local selectedSystem = optionOne == RealisticMechanicalSystems.OVERHAUL_TYPES.PARTIAL and optionTwo or nil
        hours = getLabourHours(vehicle, hours, "mechanical") * getOverhaulAccessFactor(vehicle, selectedSystem)
        return hours
    elseif serviceType == states.BODYWORK then
        return (RMS_Bodywork.getDurationMs(vehicle, optionOne) or 0) / 3600000
    elseif serviceType == states.REMAP then
        return RMS_EngineRemap.getDurationHours(optionOne)
    elseif serviceType == states.REFILL then
        return C.REFILL_TIME / 3600000
    end
    return 0
end

-- the setting of RMS_Config.MAINTENANCE that makes each service instant
local INSTANT_SETTINGS = {
    [RealisticMechanicalSystems.STATUS.INSPECTION] = "INSTANT_INSPECTION",
    [RealisticMechanicalSystems.STATUS.MAINTENANCE] = "INSTANT_MAINTENANCE_REPAIR",
    [RealisticMechanicalSystems.STATUS.REPAIR] = "INSTANT_MAINTENANCE_REPAIR",
    [RealisticMechanicalSystems.STATUS.OVERHAUL] = "INSTANT_OVERHAUL",
    [RealisticMechanicalSystems.STATUS.BODYWORK] = "INSTANT_BODYWORK",
    [RealisticMechanicalSystems.STATUS.REMAP] = "INSTANT_REMAP"
}

---Tells whether the settings finish a service at once
function RealisticMechanicalSystems.getIsServiceInstant(serviceType)
    local setting = INSTANT_SETTINGS[serviceType]
    return setting ~= nil and RMS_Config.MAINTENANCE[setting]
end

---Finishes every running service the settings make instant
function RealisticMechanicalSystems.finishInstantServices()
    if not g_currentMission:getIsServer() then
        return
    end
    for _, vehicle in pairs(RMS_Main.vehicles) do
        local spec = vehicle.spec_RealisticMechanicalSystems
        if RealisticMechanicalSystems.getIsServiceInstant(spec.currentState) and not spec.isExcludedVehicle
            and RealisticMechanicalSystems.forceFinishService(vehicle) then
            RealisticMechanicalSystems.raiseServiceLifecycleDirtyFlags(vehicle)
        end
    end
end

local function getServiceWorkDurationMs(vehicle, serviceType, optionOne, optionTwo, workshopType)
    local hours = RealisticMechanicalSystems.getServiceWorkHours(vehicle, serviceType, optionOne, optionTwo, workshopType)
    if hours <= 0 then
        return 0
    end
    return RealisticMechanicalSystems.getIsServiceInstant(serviceType) and 1000 or hours * 3600000
end

---Lists a running service fills, emptied when it starts or ends
local PENDING_SERVICE_LISTS = { "pendingSelectedBreakdowns", "pendingInspectionQueue", "pendingRepairQueue", "pendingPreventiveParts",
    "pendingServiceClockStart",
    "pendingServiceClockTarget", "pendingOverhaulPartStart", "pendingOverhaulPartTarget", "pendingFluidRequirements" }

---Clears the state a running service keeps
local function resetPendingServiceProgress(spec)
    for _, field in ipairs(PENDING_SERVICE_LISTS) do
        spec[field] = {}
    end
    spec.pendingServicePrice, spec.pendingServiceInvoice = nil, nil
    spec.pendingProgressStepIndex, spec.pendingProgressTotalTime, spec.pendingProgressElapsedTime = 0, 0, 0
end

local function getServiceClockSumps(vehicle, clock)
    local sumps = {}
    for _, circuit in ipairs(clock.circuits) do
        local sump = RMS_Fluids.getSumpCircuit(vehicle, circuit)
        if RMS_Fluids.getCapacity(vehicle, sump) > 0 then
            sumps[sump] = true
        end
    end

    return sumps
end

local function collectServiceClockTargets(vehicle, requirements)
    local spec = vehicle.spec_RealisticMechanicalSystems
    local changedSumps = {}
    for _, requirement in ipairs(requirements) do
        if requirement.mode == "replace" then
            changedSumps[requirement.circuit] = true
        end
    end

    local startLevels, targetLevels = {}, {}
    for _, clock in ipairs(vehicle:getServiceClocks()) do
        local isChanged = true
        for sump in pairs(getServiceClockSumps(vehicle, clock)) do
            isChanged = isChanged and changedSumps[sump] == true
        end

        if isChanged then
            startLevels[clock.key] = spec[clock.levelKey]
            targetLevels[clock.key] = spec.baseServiceLevel
        end
    end

    return startLevels, targetLevels
end

local function applyPendingServiceClockInterpolation(spec, ratio)
    for _, clock in ipairs(RealisticMechanicalSystems.SERVICE_CLOCKS) do
        local startLevel = spec.pendingServiceClockStart[clock.key]
        local targetLevel = spec.pendingServiceClockTarget[clock.key]
        if startLevel ~= nil and targetLevel ~= nil then
            spec[clock.levelKey] = startLevel + (targetLevel - startLevel) * ratio
        end
    end
end

local function applyPendingOverhaulPartInterpolation(spec, ratio)
    for partId, startWear in pairs(spec.pendingOverhaulPartStart) do
        spec.partWear[partId] = startWear + (spec.pendingOverhaulPartTarget[partId] - startWear) * ratio
    end
    for systemKey in pairs(spec.systemParts) do
        RealisticMechanicalSystems.refreshSystemCondition(spec, systemKey)
    end
end

---Lists the systems the adjustments of a major service reach
function RealisticMechanicalSystems.getMajorServiceSystems(vehicle)
    local systems = vehicle.spec_RealisticMechanicalSystems.systems
    local systemKeys = {}
    for _, breakdownId in ipairs(RealisticMechanicalSystems.MAJOR_SERVICE_CHECKS) do
        local breakdown = RMS_Breakdowns.BreakdownRegistry[breakdownId]
        local systemKey = RMS_Utils.getSystemKey(RealisticMechanicalSystems.SYSTEMS, breakdown.system)
        if breakdown.isApplicable(vehicle) and systems[systemKey].enabled and not table.hasElement(systemKeys, systemKey) then
            table.insert(systemKeys, systemKey)
        end
    end
    return systemKeys
end

---Skips a vehicle in the tab selection while its service runs
function RealisticMechanicalSystems:getIsTabbable(superFunc)
    local spec = self.spec_RealisticMechanicalSystems
    if spec ~= nil and not spec.isExcludedVehicle and self:isUnderService() then
        return false
    end
    return superFunc(self)
end

---Starts a service, building its step queues, its duration and its price
function RealisticMechanicalSystems:initService(type, workshopType, optionOne, optionTwo)
    local spec = self.spec_RealisticMechanicalSystems
    local states = RealisticMechanicalSystems.STATUS
    local vehicleState = self:getCurrentStatus()
    local C = RMS_Config.MAINTENANCE
    local repairPrice = nil

    if vehicleState ~= states.READY or (spec.maintenanceTimer or 0) ~= 0 then
        return false
    end

    if not RMS_Main:isWorkshopTypeOpen(workshopType) then
        return false
    end

    if type == states.OVERHAUL then
        local eligibleSystems = RMS_Utils.getEligibleOverhaulSystems(self)
        if #eligibleSystems == 0 or (optionOne == RealisticMechanicalSystems.OVERHAUL_TYPES.PARTIAL
            and RMS_Utils.getKeyByValue(eligibleSystems, optionTwo) == nil) then
            return false
        end
    end
    if type == states.BODYWORK and not RMS_Bodywork.isAllowed(self, workshopType, optionOne, optionTwo) then
        return false
    end
    if type == states.REMAP and not RMS_EngineRemap.getAvailability(self, workshopType, optionOne) then
        return false
    end

    if type == states.OVERHAUL
        and optionOne == RealisticMechanicalSystems.OVERHAUL_TYPES.PARTIAL
        and optionTwo ~= nil
        and RMS_Utils.getEffectiveSystemWeight(self, optionTwo, RealisticMechanicalSystems.SYSTEMS) <= 0 then
        log_dbg(string.format("Partial overhaul of %s refused: system '%s' off or absent", self:getFullName(), tostring(optionTwo)))
        return false
    end

    if not RMS_FluidWorkshop.getWorkshopAvailability(self, type, workshopType, optionOne) then
        return false
    end

    local totalTimeMs = getServiceWorkDurationMs(self, type, optionOne, optionTwo, workshopType)
    if self:getIsOperating() then
        self:stopMotor()
    end

    spec.currentState = type
    spec.workshopType = workshopType
    spec.serviceOptionOne = optionOne
    spec.serviceOptionTwo = optionTwo
    if type == states.BODYWORK then
        spec.bodyworkPreviewFinalized = false
    end
    resetPendingServiceProgress(spec)

    if type == states.INSPECTION then
        repairPrice = self:getServicePrice(type, optionOne, optionTwo)
    end
    -- An inspection or a service looks for the breakdowns not found yet
    if type == states.INSPECTION or type == states.MAINTENANCE then
        for id, breakdown in pairs(self:getActiveBreakdowns()) do
            if breakdown ~= nil and not breakdown.isVisible then
                table.insert(spec.pendingInspectionQueue, id)
            end
        end
    end

    if type == states.MAINTENANCE then
        repairPrice = self:getServicePrice(type, optionOne, optionTwo)

    elseif type == states.REPAIR then
        spec.pendingRepairQueue = RealisticMechanicalSystems.getRepairQueue(self, optionOne, workshopType)
        spec.pendingPreventiveParts = {}
        for _, line in ipairs(self:getRepairPriceLines(optionOne, optionTwo, workshopType)) do
            if line.isPreventive then
                spec.pendingPreventiveParts[line.breakdownId] = spec.preventiveParts[line.breakdownId]
            end
        end
        repairPrice = self:getServicePrice(type, optionOne, optionTwo)

    elseif type == states.REFILL then
        repairPrice = self:getServicePrice(type, optionOne, optionTwo)

    elseif type == states.BODYWORK then
        repairPrice = RMS_Bodywork.getPrice(self, optionOne, workshopType)

    elseif type == states.REMAP then
        repairPrice = RMS_EngineRemap.getPrice(self, optionOne)

    elseif type == states.OVERHAUL then
        local key = RMS_Utils.getKeyByValue(RealisticMechanicalSystems.OVERHAUL_TYPES, optionOne)
        local targetOverhaulSystemKey = nil
        if optionOne == RealisticMechanicalSystems.OVERHAUL_TYPES.PARTIAL then 
            targetOverhaulSystemKey = RMS_Utils.getSystemKey(RealisticMechanicalSystems.SYSTEMS, optionTwo)
            if (targetOverhaulSystemKey == nil or targetOverhaulSystemKey == "") and type(optionTwo) == "string" then
                targetOverhaulSystemKey = string.lower(optionTwo)
            end
        end


        local targetWear = 1 - C.OVERHAUL_CONDITION_TARGETS[key]
        for systemKey, systemData in pairs(spec.systems) do
            if optionOne ~= RealisticMechanicalSystems.OVERHAUL_TYPES.PARTIAL or systemKey == targetOverhaulSystemKey or optionTwo == systemData.name then
                for _, partId in ipairs(spec.systemParts[systemKey]) do
                    spec.pendingOverhaulPartStart[partId] = spec.partWear[partId]
                    spec.pendingOverhaulPartTarget[partId] = math.min(spec.partWear[partId], targetWear)
                end
            end
        end

        if optionOne == RealisticMechanicalSystems.OVERHAUL_TYPES.PARTIAL and next(spec.pendingOverhaulPartTarget) == nil then
            -- No system matches: the booking is undone
            log_dbg(string.format("Partial overhaul of %s refused: no system matches '%s'", self:getFullName(), tostring(optionTwo)))
            spec.currentState, spec.workshopType = states.READY, workshopType
            spec.serviceOptionOne, spec.serviceOptionTwo = nil, nil
            resetPendingServiceProgress(spec)
            return false
        end
    end

    spec.pendingSelectedBreakdowns = {}
    spec.pendingFluidRequirements = RMS_Fluids.getServiceRequirements(
        self,
        type,
        optionOne,
        optionTwo,
        spec.pendingRepairQueue
    )
    spec.pendingServiceClockStart, spec.pendingServiceClockTarget = collectServiceClockTargets(self, spec.pendingFluidRequirements)

    spec.pendingServicePrice = repairPrice

    if totalTimeMs > 0 then
        spec.maintenanceTimer = totalTimeMs
        spec.maintenanceTimerTime = RMS_Thermal.getWorldTimeMS()
        spec.pendingProgressTotalTime, spec.pendingProgressElapsedTime, spec.pendingProgressStepIndex = totalTimeMs, 0, 0
        log_dbg(string.format(
            '%s initiated for %s, will take %.2f seconds (%.2f seconds booked)',
            spec.currentState,
            self:getFullName(),
            totalTimeMs / 1000,
            spec.maintenanceTimer / 1000
        ))
    else
        spec.currentState = states.READY
        resetPendingServiceProgress(spec)
    end

    RealisticMechanicalSystems.raiseRMSDirty(self, RealisticMechanicalSystems.SYNC_GROUP.STATE
        + RealisticMechanicalSystems.SYNC_GROUP.SERVICE_PROGRESS
        + RealisticMechanicalSystems.SYNC_GROUP.SERVICE_CONTEXT)
    if type == states.BODYWORK then
        RMS_Bodywork.syncPreview(self)
    end
    return spec.currentState == type and (spec.maintenanceTimer or 0) > 0
end

local function processPendingRepairStep(vehicle, spec, breakdownId, optionOne, optionTwo)
    if breakdownId == nil or vehicle:getActiveBreakdowns()[breakdownId] == nil then
        return
    end
    optionOne, optionTwo = RealisticMechanicalSystems.getFaultRepairOptions(vehicle, breakdownId, optionOne, optionTwo, spec.workshopType)
    local optionTwoKey = RMS_Utils.getKeyByValue(RealisticMechanicalSystems.PART_TYPES, optionTwo)

    table.insert(spec.pendingSelectedBreakdowns, breakdownId)

    local C = RMS_Config.MAINTENANCE
    local systemKey = RMS_Utils.getSystemKey(RealisticMechanicalSystems.SYSTEMS, RMS_Breakdowns.BreakdownRegistry[breakdownId].system)

    if optionOne == RealisticMechanicalSystems.REPAIR_TYPES.LOW then
        local random = math.random()
        local serviceScale = RMS_Config.CORE.REFERENCE_SERVICE_WEAR / RMS_Config.CORE.BASE_SERVICE_WEAR
        vehicle:suspendBreakdown(breakdownId, RMS_Config.CORE.REPEAT_BREAKDOWN_TIME * serviceScale * (random + 0.5))
    else
        local fault = vehicle:getActiveBreakdowns()[breakdownId]
        local stage, donorHours = fault.stage, fault.usedPartHours
        local isPaid = not (vehicle:isWarrantyRepairCovered(spec.workshopType, breakdownId)
            or RealisticMechanicalSystems.getIsUsedPartWarrantyCovered(vehicle, breakdownId, optionOne, optionTwo))
        vehicle:removeBreakdown(breakdownId)

        local wear = 0
        if optionTwo == RealisticMechanicalSystems.PART_TYPES.USED and donorHours ~= nil then
            wear = donorHours / RMS_Config.CORE.MACHINE_LIFE_HOURS
        end
        local renewedParts = RealisticMechanicalSystems.getRepairFittedParts(vehicle, breakdownId, stage, optionOne, spec.partWear,
            function(partId) return vehicle:hasBreakdown(partId) end)
        for _, partId in ipairs(renewedParts) do
            RealisticMechanicalSystems.recordPartWarranty(vehicle, partId, optionTwo, isPaid, donorHours)
            RealisticMechanicalSystems.markFittedPart(vehicle, partId, optionTwo)
            if spec.partWear[partId] ~= nil then
                -- its failures draw from its own wear, not across the old part's
                spec.partWear[partId], spec.partDrawnWear[partId] = wear, wear
            end
        end
        RealisticMechanicalSystems.refreshSystemCondition(spec, systemKey)
        if breakdownId == "CVT_ADDON_MALFUNCTION" then
            vehicle.spec_CVTaddon.CVTdamage = wear * 100
        end

        if RMS_Consumables.getFilterOfBreakdown(breakdownId) ~= nil then
            RMS_Consumables.renewFilters(vehicle, breakdownId)
        elseif math.random() < C.PARTS_BREAKDOWN_CHANCES[optionTwoKey] then
            -- a poor part fails again, hidden until its drawn delay runs out
            vehicle:addBreakdown(breakdownId, { stage = stage, isVisible = false, isActive = false,
                source = RealisticMechanicalSystems.BREAKDOWN_SOURCES.POOR_PARTS })
        end
    end
end

---Fits a worn part replaced in prevention, as a repair fits a part
-- @param integer donorHours work hours of the donor machine of a used part, 0 for none
local function fitPreventivePart(vehicle, spec, partId, partType, donorHours)
    local R, C = RealisticMechanicalSystems, RMS_Config.MAINTENANCE
    local donor = donorHours > 0 and donorHours or nil
    local wear = partType == R.PART_TYPES.USED and donor ~= nil and donor / RMS_Config.CORE.MACHINE_LIFE_HOURS or 0
    R.recordPartWarranty(vehicle, partId, partType, true, donor)
    R.markFittedPart(vehicle, partId, partType)
    if spec.partWear[partId] ~= nil then
        spec.partWear[partId], spec.partDrawnWear[partId] = wear, wear
    end
    R.refreshSystemCondition(spec, RMS_Utils.getSystemKey(R.SYSTEMS, RMS_Breakdowns.BreakdownRegistry[partId].system))
    if RMS_Consumables.getFilterOfBreakdown(partId) ~= nil then
        RMS_Consumables.renewFilters(vehicle, partId)
    elseif math.random() < C.PARTS_BREAKDOWN_CHANCES[RMS_Utils.getKeyByValue(R.PART_TYPES, partType)] then
        vehicle:addBreakdown(partId, { stage = 1, isVisible = false, isActive = false, source = R.BREAKDOWN_SOURCES.POOR_PARTS })
    end
end

---Advances the running service through its step queue
function RealisticMechanicalSystems:processService(dt, ignoreWorkshopHours)
    local spec = self.spec_RealisticMechanicalSystems
    local states = RealisticMechanicalSystems.STATUS
    local vehicleState = self:getCurrentStatus()

    if vehicleState == states.READY
        or (not ignoreWorkshopHours and not RMS_Main:isWorkshopTypeOpen(spec.workshopType)) then
        return
    end

    local timeScale = getSafeMissionTimeScale()
    local prevTimer = spec.maintenanceTimer or 0
    spec.maintenanceTimer = (spec.maintenanceTimer or 0) - dt * timeScale
    spec.maintenanceTimerTime = RMS_Thermal.getWorldTimeMS()
    local progressed = math.max(prevTimer - math.max(spec.maintenanceTimer, 0), 0)

    if spec.pendingProgressTotalTime > 0 then
        spec.pendingProgressElapsedTime = math.min((spec.pendingProgressElapsedTime or 0) + progressed, spec.pendingProgressTotalTime)
    end

    local serviceType = spec.currentState
    local optionOne = spec.serviceOptionOne
    local optionTwo = spec.serviceOptionTwo

    if serviceType == states.INSPECTION or serviceType == states.MAINTENANCE then
        local steps = #spec.pendingInspectionQueue
        local breakdownsRevealed = false
        if steps > 0 and spec.pendingProgressTotalTime > 0 then
            local targetStep = math.min(steps, math.floor((spec.pendingProgressElapsedTime / spec.pendingProgressTotalTime) * steps))
            while spec.pendingProgressStepIndex < targetStep do
                spec.pendingProgressStepIndex = spec.pendingProgressStepIndex + 1
                local breakdownId = spec.pendingInspectionQueue[spec.pendingProgressStepIndex]
                local breakdown = self:getActiveBreakdowns()[breakdownId]
                if breakdown ~= nil and not breakdown.isVisible then
                    local breakdownDef = RMS_Breakdowns.BreakdownRegistry[breakdownId]
                    if breakdownDef ~= nil and breakdownDef.stages ~= nil and breakdownDef.stages[breakdown.stage] ~= nil then
                        local needsTool = RealisticMechanicalSystems.getBreakdownNeedsDiagnosticTool(breakdownId)
                        local inspectionDetectionMul = 1.0
                        if serviceType == states.INSPECTION then
                            inspectionDetectionMul = RealisticMechanicalSystems.getInspectionDetectionShare(optionOne, needsTool)
                        elseif needsTool and not RealisticMechanicalSystems.getMaintenanceReadsFaultCodes(self, spec.workshopType) then
                            inspectionDetectionMul = 0
                        end
                        local chance = (breakdownDef.stages[breakdown.stage].detectionChance * inspectionDetectionMul) or 0
                        if math.random() < chance then
                            if breakdown.isActive or RealisticMechanicalSystems.getInspectionFindsDormant(optionOne) then
                                breakdown.isVisible = true
                                breakdownsRevealed = true
                                table.insert(spec.pendingSelectedBreakdowns, breakdownId)
                            end
                        end
                    end
                end
            end
        end
        if breakdownsRevealed then
            RealisticMechanicalSystems.raiseRMSDirty(self, RealisticMechanicalSystems.SYNC_GROUP.BREAKDOWNS)
        end

    elseif serviceType == states.REPAIR then
        local steps = #spec.pendingRepairQueue
        if steps > 0 and spec.pendingProgressTotalTime > 0 then
            local targetStep = math.min(steps, math.floor((spec.pendingProgressElapsedTime / spec.pendingProgressTotalTime) * steps))
            while spec.pendingProgressStepIndex < targetStep do
                spec.pendingProgressStepIndex = spec.pendingProgressStepIndex + 1
                local breakdownId = spec.pendingRepairQueue[spec.pendingProgressStepIndex]
                processPendingRepairStep(self, spec, breakdownId, optionOne, optionTwo)
            end
        end

        self:updateConditionLevel()
    end

    if serviceType == states.MAINTENANCE and spec.pendingProgressTotalTime > 0 then
        local ratio = math.min(math.max(spec.pendingProgressElapsedTime / spec.pendingProgressTotalTime, 0), 1)
        applyPendingServiceClockInterpolation(spec, ratio)

    elseif serviceType == states.OVERHAUL and spec.pendingProgressTotalTime > 0 then
        local ratio = math.min(math.max(spec.pendingProgressElapsedTime / spec.pendingProgressTotalTime, 0), 1)
        applyPendingServiceClockInterpolation(spec, ratio)
        applyPendingOverhaulPartInterpolation(spec, ratio)
        self:updateConditionLevel()
    end

    if (spec.maintenanceTimer or 0) <= 0 then
        spec.maintenanceTimer = 0
        self:completeService()
    end
end

---Tells whether only a diagnostic tool reads a breakdown
function RealisticMechanicalSystems.getBreakdownNeedsDiagnosticTool(breakdownId)
    local operation = RMS_Config.MAINTENANCE.REPAIR_OPERATIONS[breakdownId]
    return operation ~= nil and RMS_Config.MAINTENANCE.INSPECTION_TOOL_CATEGORIES[operation.category] == true
end

---Returns the share of its detection chance a fault keeps under an inspection
function RealisticMechanicalSystems.getInspectionDetectionShare(inspectionType, needsTool)
    if needsTool and inspectionType == RealisticMechanicalSystems.INSPECTION_TYPES.VISUAL then
        return 0
    end
    return RMS_Config.MAINTENANCE.INSPECTION_DETECTION_CHANCE_MULTIPLIERS[
        RMS_Utils.getKeyByValue(RealisticMechanicalSystems.INSPECTION_TYPES, inspectionType)]
end

---Tells whether an inspection also looks for the dormant faults
function RealisticMechanicalSystems.getInspectionFindsDormant(inspectionType)
    return inspectionType == RealisticMechanicalSystems.INSPECTION_TYPES.COMPLETE
end

---Tells whether a maintenance reads the fault codes of a machine
function RealisticMechanicalSystems.getMaintenanceReadsFaultCodes(vehicle, workshopType)
    return RMS_FluidWorkshop.getWorkshopAvailability(vehicle, RealisticMechanicalSystems.STATUS.INSPECTION, workshopType,
        RealisticMechanicalSystems.INSPECTION_TYPES.STANDARD) == true
end

-- the year dashboards got each telltale
local TELLTALE_YEARS = { engine = 1990, transmission = 1990, brakes = 1980, battery = 1950, coolant = 1950, warning = 1990,
    service = 1970, oil = 0 }

---Tells whether the dashboard of a machine carries a telltale
function RealisticMechanicalSystems.getIsTelltaleFitted(vehicle, indicatorId)
    local spec = vehicle.spec_RealisticMechanicalSystems
    if indicatorId == "preheat" then
        return spec.isDieselVehicle == true
    elseif indicatorId == "dpf" then
        return spec.hasParticulateFilter == true
    elseif indicatorId == "tractionBattery" or indicatorId == "limitedPower" then
        return spec.isElectricVehicle == true
    elseif indicatorId == "fanReversal" then
        return spec.hasReversibleFan == true
    elseif indicatorId == "oil" and RMS_Fluids.getCapacity(vehicle, "engineOil") <= 0 then
        return false
    elseif indicatorId == "transmission" and RMS_Drivetrain.getIsRoadVehicleCategory(vehicle) and not spec.isTruck then
        return false
    end
    return TELLTALE_YEARS[indicatorId] <= spec.year
end

---Tells whether a machine lights a telltale for an unidentified fault
function RealisticMechanicalSystems.getHasUnidentifiedWarning(vehicle)
    for breakdownId, breakdown in pairs(vehicle:getActiveBreakdowns()) do
        local definition = RMS_Breakdowns.BreakdownRegistry[breakdownId]
        if definition.isSelectable and breakdown.isActive and not breakdown.isVisible then
            for _, indicator in ipairs(RMS_Utils.getBranchItems(definition.stages[breakdown.stage].indicators, breakdown)) do
                -- A gearbox fault lights the warning, not the oil temperature lamp
                local lampId = indicator.id == "transmission" and "warning" or indicator.id
                if RealisticMechanicalSystems.getIsTelltaleFitted(vehicle, lampId) then
                    return true
                end
            end
        end
    end
    return false
end

---Tells whether a maintenance level fits a new air filter
function RealisticMechanicalSystems.getMaintenanceRenewsAirFilter(maintenanceType)
    return maintenanceType ~= RealisticMechanicalSystems.MAINTENANCE_TYPES.STANDARD
end

---Applies the service result, writes the log entry and frees the vehicle
function RealisticMechanicalSystems:completeService()
    local spec = self.spec_RealisticMechanicalSystems
    local states = RealisticMechanicalSystems.STATUS
    local serviceType = spec.currentState
    local optionOne = spec.serviceOptionOne
    local optionTwo = spec.serviceOptionTwo
    local isMobileWorkshop = spec.workshopType == RealisticMechanicalSystems.WORKSHOP.MOBILE
    local selectedBreakdowns = RMS_Utils.shallowCopy(spec.pendingSelectedBreakdowns or {})

    applyPendingServiceClockInterpolation(spec, 1)
    -- Reset calendars only after a completed renewal.
    spec.serviceCalendar = spec.serviceCalendar or {}
    for key in pairs(spec.pendingServiceClockTarget or {}) do
        spec.serviceCalendar[key] = tonumber(self.age) or 0
    end

    if serviceType == states.MAINTENANCE then
        if optionOne == RealisticMechanicalSystems.MAINTENANCE_TYPES.PREVENTIVE then
            for _, partId in ipairs(RealisticMechanicalSystems.MAJOR_SERVICE_CHECKS) do
                local definition = RMS_Breakdowns.BreakdownRegistry[partId]
                if definition.isApplicable(self) and RMS_Utils.getIsPartWorn(partId, spec.partWear[partId]) then
                    spec.partWear[partId] = 0
                    -- consumables other than original fit parts the warranty does not know
                    RealisticMechanicalSystems.markFittedPart(self, partId, optionTwo == RealisticMechanicalSystems.PART_TYPES.OEM
                        and optionTwo or RealisticMechanicalSystems.PART_TYPES.AFTERMARKET)
                    RealisticMechanicalSystems.recordPartWarranty(self, partId, optionTwo,
                        not self:isLeaseMaintenanceCovered(spec.workshopType))
                    RealisticMechanicalSystems.refreshSystemCondition(spec, RMS_Utils.getSystemKey(RealisticMechanicalSystems.SYSTEMS, definition.system))
                end
            end
            self:updateConditionLevel()
        end

        RMS_Consumables.renewFilters(self, nil, optionOne)
        local defectChance = RMS_Config.MAINTENANCE.PARTS_BREAKDOWN_CHANCES[RMS_Utils.getKeyByValue(RealisticMechanicalSystems.PART_TYPES, optionTwo)]
        if math.random() < defectChance then
            RMS_Consumables.addDefectiveFilter(self, optionOne)
        end
        for index = #selectedBreakdowns, 1, -1 do
            if not self:hasBreakdown(selectedBreakdowns[index]) then
                table.remove(selectedBreakdowns, index)
            end
        end
    end

    if serviceType == states.OVERHAUL then
        applyPendingOverhaulPartInterpolation(spec, 1)
        for partId in pairs(spec.pendingOverhaulPartTarget) do
            spec.partAbuse[partId] = nil
            RealisticMechanicalSystems.recordPartWarranty(self, partId, RealisticMechanicalSystems.PART_TYPES.OEM, true)
        end
        self:updateConditionLevel()
        if RMS_Utils.hasCVTAddon(self) and (optionOne ~= RealisticMechanicalSystems.OVERHAUL_TYPES.PARTIAL
            or optionTwo == RealisticMechanicalSystems.SYSTEMS.TRANSMISSION) then
            local target = RMS_Config.MAINTENANCE.OVERHAUL_CONDITION_TARGETS[RMS_Utils.getKeyByValue(RealisticMechanicalSystems.OVERHAUL_TYPES, optionOne)]
            self.spec_CVTaddon.CVTdamage = math.min(self.spec_CVTaddon.CVTdamage, (1 - target) * 100)
        end

        -- a partial overhaul repairs the breakdowns of its one system
        local idsToRepair = {}
        local isPartial = optionOne == RealisticMechanicalSystems.OVERHAUL_TYPES.PARTIAL
        for breakdownId in pairs(spec.activeBreakdowns) do
            local definition = RMS_Breakdowns.BreakdownRegistry[breakdownId]
            if definition ~= nil and definition.isSelectable and (not isPartial or optionTwo == definition.system) then
                table.insert(idsToRepair, breakdownId)
            end
        end

        selectedBreakdowns = idsToRepair
        if #idsToRepair > 0 then
            self:removeBreakdown(table.unpack(idsToRepair))
        end
        RMS_Consumables.renewFilters(self)
    elseif serviceType == states.REPAIR then
        local repairQueue = spec.pendingRepairQueue or {}
        spec.pendingProgressStepIndex = math.max(math.floor(tonumber(spec.pendingProgressStepIndex) or 0), 0)

        while spec.pendingProgressStepIndex < #repairQueue do
            spec.pendingProgressStepIndex = spec.pendingProgressStepIndex + 1
            local breakdownId = repairQueue[spec.pendingProgressStepIndex]
            processPendingRepairStep(self, spec, breakdownId, optionOne, optionTwo)
        end
        local preventive = {}
        for partId in pairs(spec.pendingPreventiveParts or {}) do
            table.insert(preventive, partId)
        end
        table.sort(preventive)
        for _, partId in ipairs(preventive) do
            fitPreventivePart(self, spec, partId, optionTwo, spec.pendingPreventiveParts[partId])
            spec.preventiveParts[partId] = nil
        end

        selectedBreakdowns = RMS_Utils.shallowCopy(spec.pendingSelectedBreakdowns or {})
        self:updateConditionLevel()
    end

    if serviceType == states.BODYWORK then
        RMS_Bodywork.restorePreview(self, true)
        if optionOne == RMS_Bodywork.FULL and not RMS_Bodywork.applyColors(self, optionTwo) then
            Logging.warning("RMS: Bodywork color application failed for %s; service cancelled", tostring(self.configFileName))
            self:cancelService()
            return
        end
        RMS_Bodywork.clearWear(self)
        if optionOne == RMS_Bodywork.FULL then
            RMS_BodyworkColorEvent.sendToClients(self, optionTwo)
        end
    end
    if serviceType == states.REMAP then
        RMS_EngineRemap.complete(self, optionOne)
    end

    spec.pendingSelectedBreakdowns = selectedBreakdowns
    self:recalculateAndApplyEffects()
    self:addEntryToMaintenanceLog(serviceType, optionOne, optionTwo, spec.pendingServicePrice, true, spec.pendingServiceInvoice)

    local lastEntry = spec.maintenanceLog and spec.maintenanceLog[#spec.maintenanceLog]
    if lastEntry ~= nil then
        lastEntry.isVisible = true
    end

    if not isMobileWorkshop and (serviceType == states.MAINTENANCE
        or serviceType == states.REPAIR
        or serviceType == states.OVERHAUL
        or serviceType == states.BODYWORK) then
        self:setDirtAmount(0)
    end

    RMS_Fluids.applyServiceRequirements(self, spec.pendingFluidRequirements)

    if serviceType == states.MAINTENANCE then
        spec.radiatorClogging = 0
        if RealisticMechanicalSystems.getMaintenanceRenewsAirFilter(optionOne) then
            spec.airFilterClogging = 0
            spec.airFilterResidue = 0
        else
            spec.airFilterClogging = spec.airFilterResidue
        end
        RMS_Greasing.greaseAll(self)
    end

    local maintenanceCompletedText = string.format(g_i18n:getText("rms_hud_vehicle_notification"), self:getFullName(),
        string.format(g_i18n:getText("rms_spec_maintenance_complete_notification"), RMS_Utils.formatServiceState(serviceType)))

    if serviceType == states.INSPECTION or serviceType == states.MAINTENANCE then
        local foundCount = 0
        for _, breakdown in pairs(self:getActiveBreakdowns()) do
            foundCount = foundCount + (breakdown.isVisible and 1 or 0)
        end
        if foundCount == 0 then
            maintenanceCompletedText = maintenanceCompletedText .. ". " .. g_i18n:getText("rms_spec_inspection_no_issues_detected_notification")
        else
            maintenanceCompletedText = maintenanceCompletedText .. ". " .. string.format(g_i18n:getText("rms_spec_inspection_issues_detected_notification"), foundCount)
        end
    end

    if g_currentMission.hud ~= nil and g_currentMission.hud.addSideNotification ~= nil
            and self:getOwnerFarmId() == g_currentMission:getFarmId() then
        g_currentMission.hud:addSideNotification({1, 1, 1, 1}, maintenanceCompletedText)
    end

    if g_currentMission:getFarmId() == self.ownerFarmId then
        RMS_SoundManager.playSample(RMS_Main.samples.maintenanceCompleted2D)
    end


    spec.maintenanceTimer = 0
    resetPendingServiceProgress(spec)
    spec.serviceOptionOne = nil
    spec.serviceOptionTwo = nil

    RealisticMechanicalSystems.raiseRMSDirty(self, RealisticMechanicalSystems.SYNC_GROUP.STATE
        + RealisticMechanicalSystems.SYNC_GROUP.SERVICE_PROGRESS
        + RealisticMechanicalSystems.SYNC_GROUP.SERVICE_CONTEXT)

    spec.currentState = states.READY
    RMS_VehicleChangeStatusEvent.send(self, maintenanceCompletedText, lastEntry)
end

---Aborts the running service, logging it as not completed
function RealisticMechanicalSystems:cancelService()
    local spec = self.spec_RealisticMechanicalSystems
    local states = RealisticMechanicalSystems.STATUS
    local serviceType = spec.currentState

    if serviceType == states.READY then
        return
    end

    local optionOne = spec.serviceOptionOne
    local optionTwo = spec.serviceOptionTwo
    local selectedBreakdowns = RMS_Utils.shallowCopy(spec.pendingSelectedBreakdowns or {})

    if serviceType == states.BODYWORK then
        RMS_Bodywork.restorePreview(self, true)
    end

    -- Cancelled work must not reset fluid service clocks.
    for _, clock in ipairs(RealisticMechanicalSystems.SERVICE_CLOCKS) do
        local start = spec.pendingServiceClockStart ~= nil and spec.pendingServiceClockStart[clock.key] or nil
        if start ~= nil then spec[clock.levelKey] = start end
    end
    spec.pendingSelectedBreakdowns = selectedBreakdowns
    self:recalculateAndApplyEffects()
    self:addEntryToMaintenanceLog(serviceType, optionOne, optionTwo, spec.pendingServicePrice, false, spec.pendingServiceInvoice)

    local lastEntry = spec.maintenanceLog and spec.maintenanceLog[#spec.maintenanceLog]
    if lastEntry ~= nil then
        lastEntry.isVisible = true
    end

    local cancelText = string.format(g_i18n:getText("rms_hud_vehicle_notification"), self:getFullName(),
        string.format(g_i18n:getText("rms_spec_maintenance_cancelled_notification"), RMS_Utils.formatServiceState(serviceType)))
    if g_currentMission.hud ~= nil and g_currentMission.hud.addSideNotification ~= nil
            and self:getOwnerFarmId() == g_currentMission:getFarmId() then
        g_currentMission.hud:addSideNotification({1, 1, 1, 1}, cancelText)
    end

    if self.isServer then
        local lastEntry = spec.maintenanceLog and spec.maintenanceLog[#spec.maintenanceLog]
        if lastEntry ~= nil then
            RMS_LogEntrySyncEvent.sendToClients(self, lastEntry)
        end
    end

    spec.maintenanceTimer = 0
    spec.currentState = states.READY
    resetPendingServiceProgress(spec)
    spec.serviceOptionOne = nil
    spec.serviceOptionTwo = nil

    RealisticMechanicalSystems.raiseRMSDirty(self, RealisticMechanicalSystems.SYNC_GROUP.STATE + RealisticMechanicalSystems.SYNC_GROUP.WEAR
        + RealisticMechanicalSystems.SYNC_GROUP.SERVICE_PROGRESS
        + RealisticMechanicalSystems.SYNC_GROUP.SERVICE_CONTEXT)

    RMS_VehicleChangeStatusEvent.send(self, cancelText)
end

local function getRealOperatingHours(vehicle)
    local realHours = (vehicle.spec_RealisticMechanicalSystems.realOperatingTime or 0) / (60 * 60 * 1000)
    if realHours <= 0 then
        realHours = vehicle:getFormattedOperatingTime() or 0
    end
    return realHours
end
RealisticMechanicalSystems.getRealOperatingHours = getRealOperatingHours

local function getWearExcess(spec)
    local normal, causes = 0, {}
    for systemKey, weight in pairs(RMS_Config.CORE.SYSTEM_WEIGHTS) do
        local stats = spec.factorStats ~= nil and spec.factorStats[systemKey] or nil
        if stats ~= nil then
            normal = normal + weight * (tonumber(stats.total) or 0)
            for alias in pairs(RealisticMechanicalSystems.FACTOR_STATS_KEYS) do
                local wear = weight * (tonumber(stats[alias]) or 0)
                normal = normal - wear
                causes[alias] = (causes[alias] or 0) + wear
            end
        end
    end
    if normal <= 0 then
        return nil, {}
    end

    local excess = 0
    for alias, wear in pairs(causes) do
        causes[alias] = wear / normal
        excess = excess + causes[alias]
    end
    return excess, causes
end

---Appends a log entry: options, price and condition snapshot
function RealisticMechanicalSystems:addEntryToMaintenanceLog(maintenanceType, optionOne, optionTwo, price, isCompleted, invoice)
    local spec = self.spec_RealisticMechanicalSystems
    if not spec then return end

    local entryId = #spec.maintenanceLog + 1
    local env = g_currentMission.environment
    local selectedBreakdowns = RMS_Utils.shallowCopy(spec.pendingSelectedBreakdowns or {})
    local systemsSnapshot = RMS_Utils.createSystemsSnapshot(spec.systems)
    local realHours = getRealOperatingHours(self)
    local wearExcess, wearCauses = getWearExcess(spec)

    local entry = {
        id = entryId,                     
        type = maintenanceType,
        price = price ~= nil and price or self:getServicePrice(maintenanceType, optionOne, optionTwo),
        location = spec.workshopType,
        date = { 
            day = env.currentDayInPeriod or 1, 
            month = env.currentPeriod, 
            year = env.currentYear 
        },

        optionOne = optionOne,
        optionTwo = optionTwo or "NONE",
        isVisible = false,
        isCompleted = isCompleted ~= false,
        invoice = RMS_Utils.deepCopy(invoice),

        conditionData = {
            year = spec.year,
            operatingHours = realHours,
            odometerKilometers = RMS_Utils.getOdometerKilometers(self),
            age = self.age or 0,
            condition = self:getConditionLevel(),
            service = self:getServiceLevel(),
            systems = systemsSnapshot,
            partWear = RMS_Utils.shallowCopy(spec.partWear),
            batterySoc = tonumber(spec.batterySoc) or 1,
            activeBreakdowns = RMS_Utils.deepCopy(self:getActiveBreakdowns()),
            selectedBreakdowns = selectedBreakdowns,
            activeEffects = RMS_Utils.shallowCopy(spec.activeEffects),
            activeIndicators = RMS_Utils.shallowCopy(spec.activeIndicators),
            reliability = spec.reliability,
            wearExcess = wearExcess,
            wearCauses = wearCauses
        }
    }

    table.insert(spec.maintenanceLog, entry)
end


---Tells whether a log entry carries an inspection report
function RealisticMechanicalSystems.getIsLogEntryHasReport(entry)
    if entry == nil then
        return false
    end

    local isCompleted = RMS_Utils.normalizeBoolValue(entry.isCompleted, true)

    return (entry.type == RealisticMechanicalSystems.STATUS.INSPECTION
        or entry.type == RealisticMechanicalSystems.STATUS.MAINTENANCE
        or entry.type == RealisticMechanicalSystems.STATUS.OVERHAUL)
        and entry.optionOne ~= RealisticMechanicalSystems.INSPECTION_TYPES.VISUAL
        and entry.optionOne ~= "NONE"
        and isCompleted
end

---Tells whether a log entry holds a complete inspection report
function RealisticMechanicalSystems.getIsCompleteReport(entry)
    return entry.optionOne == RealisticMechanicalSystems.INSPECTION_TYPES.COMPLETE or entry.type == RealisticMechanicalSystems.STATUS.OVERHAUL
end

local REPORT_VALIDITY_SHARE = 0.5

local function getReportAge(vehicle, report)
    local hours = math.max(getRealOperatingHours(vehicle) - report.conditionData.operatingHours, 0)
    local isOutdated = hours >= vehicle:getServiceReferenceInterval() * REPORT_VALIDITY_SHARE
    local reported = report.conditionData.activeBreakdowns
    for id, breakdown in pairs(vehicle:getActiveBreakdowns()) do
        isOutdated = isOutdated or (breakdown.isVisible and not (reported[id] ~= nil and reported[id].isVisible))
    end
    return hours, isOutdated
end

---Returns the report the screens read their figures from
function RealisticMechanicalSystems:getReferenceReport(forService)
    local log = self.spec_RealisticMechanicalSystems.maintenanceLog or {}
    local newest = nil
    for index = #log, 1, -1 do
        local entry = log[index]
        if RealisticMechanicalSystems.getIsLogEntryHasReport(entry) then
            newest = newest or entry
            if RealisticMechanicalSystems.getIsCompleteReport(entry) then
                local _, isOutdated = getReportAge(self, entry)
                return isOutdated and newest or entry
            elseif forService and entry.type == RealisticMechanicalSystems.STATUS.MAINTENANCE then
                return newest
            end
        end
    end
    return newest
end

function RealisticMechanicalSystems:getPartsReport()
    local log = self.spec_RealisticMechanicalSystems.maintenanceLog or {}
    for index = #log, 1, -1 do
        local entry = log[index]
        if RealisticMechanicalSystems.getIsLogEntryHasReport(entry) and RealisticMechanicalSystems.getIsCompleteReport(entry)
            and next(entry.conditionData.partWear) ~= nil then
            return entry, (getReportAge(self, entry))
        end
    end
    return nil
end

---Returns the condition the reference report recorded
function RealisticMechanicalSystems:getLastInspectedCondition()
    local spec = self.spec_RealisticMechanicalSystems
    if not spec or not spec.maintenanceLog or #spec.maintenanceLog == 0 then
        return 0
    end

    local report = RealisticMechanicalSystems.getReferenceReport(self)
    if report ~= nil then
        return report.conditionData.condition, RealisticMechanicalSystems.getIsCompleteReport(report)
    end
    return 1.0
end

---Returns the service level the reference report recorded
function RealisticMechanicalSystems:getLastInspectedService()
    local spec = self.spec_RealisticMechanicalSystems
    if not spec or not spec.maintenanceLog or #spec.maintenanceLog == 0 then
        return 0
    end

    local report = RealisticMechanicalSystems.getReferenceReport(self, true)
    if report ~= nil then
        return report.conditionData.service, RealisticMechanicalSystems.getIsCompleteReport(report)
    end
    return 1.0
end

---Tells how old the newest inspection report is, and whether it still holds
-- @return float? hours report age in hour-meter units, nil without report
function RealisticMechanicalSystems:getInspectionReportAge()
    local log = self.spec_RealisticMechanicalSystems.maintenanceLog
    for index = #log, 1, -1 do
        if RealisticMechanicalSystems.getIsLogEntryHasReport(log[index]) then
            return getReportAge(self, log[index])
        end
    end
    return nil, false
end

---Returns the date of the newest maintenance
function RealisticMechanicalSystems:getLastMaintenanceDate()
    local STATUS, log = RealisticMechanicalSystems.STATUS, self.spec_RealisticMechanicalSystems.maintenanceLog
    for index = #log, 1, -1 do
        if log[index].type == STATUS.MAINTENANCE or log[index].type == STATUS.OVERHAUL then
            return log[index].date
        end
    end
    return nil
end

---Returns the service reference interval the player selected
function RealisticMechanicalSystems:getServiceReferenceInterval()
    local spec = self.spec_RealisticMechanicalSystems
    return (spec.baseServiceLevel - RMS_Config.CORE.SERVICE_EXPIRED_THRESHOLD) / RMS_Config.CORE.BASE_SERVICE_WEAR
end

---Returns the programmed hours of a clock, engine oil by its year
-- @return float? hours programmed hours, nil for a clock without an hourly limit
function RealisticMechanicalSystems.getServiceProgramHours(vehicle, key)
    local spec = vehicle.spec_RealisticMechanicalSystems
    if key == "engine" and spec.yearIsKnown == true then
        for _, step in ipairs(RMS_Config.ENGINE_OIL_HOURS_BY_YEAR) do
            if spec.year < step.before then return step.hours end
        end
    end
    return RMS_Config.SERVICE_PROGRAM[key].hours
end

---Returns the service clocks of the circuits present, a common sump once
function RealisticMechanicalSystems:getServiceClocks()
    local spec = self.spec_RealisticMechanicalSystems
    local engineHours = RealisticMechanicalSystems.getServiceProgramHours(self, "engine")
    if spec.fluidCapacityVersion ~= nil and spec.serviceClocks ~= nil and spec.serviceClocksCapacityVersion == spec.fluidCapacityVersion
        and spec.serviceClocksCapacities == spec.fluidCapacities and spec.serviceClocksEngineHours == engineHours
        and spec.serviceClocksFilename == self.configFileName then return spec.serviceClocks end
    local referenceHours = RMS_Config.SERVICE_REFERENCE_HOURS
    local clocks, bySump = {}, {}
    for _, definition in ipairs(RealisticMechanicalSystems.SERVICE_CLOCKS) do
        local limits = RMS_Config.SERVICE_PROGRAM[definition.key]
        local hours = RealisticMechanicalSystems.getServiceProgramHours(self, definition.key)
        for sump in pairs(getServiceClockSumps(self, definition)) do
            local clock = bySump[sump]
            if clock == nil then
                clock = RMS_Utils.shallowCopy(definition)
                clock.intervalFactor = hours ~= nil and hours / referenceHours or nil
                clock.months = limits.months
                clock.circuits = {sump}
                clock.systems = RMS_Utils.shallowCopy(definition.systems)
                bySump[sump] = clock
                table.insert(clocks, clock)
            else
                if hours ~= nil then
                    clock.intervalFactor = math.min(clock.intervalFactor or math.huge, hours / referenceHours)
                end
                if limits.months ~= nil then clock.months = math.min(clock.months or math.huge, limits.months) end
                for _, systemKey in ipairs(definition.systems) do table.insert(clock.systems, systemKey) end
            end
        end
    end
    spec.serviceCalendar = spec.serviceCalendar or {}
    for _, clock in ipairs(clocks) do
        -- A missing calendar date must not reset hourly progress.
        if spec.serviceCalendar[clock.key] == nil then spec.serviceCalendar[clock.key] = tonumber(self.age) or 0 end
    end
    spec.serviceClocks, spec.serviceClocksCapacityVersion = clocks, spec.fluidCapacityVersion
    spec.serviceClocksFilename = self.configFileName
    spec.serviceClocksCapacities = spec.fluidCapacities
    spec.serviceClocksEngineHours = engineHours
    return clocks
end

---Returns elapsed hourly progress and its limit in the hour meter's units.
function RealisticMechanicalSystems:getServiceClockHours(clock)
    if clock == nil then return 0, 0 end
    local spec = self.spec_RealisticMechanicalSystems
    if clock.intervalFactor == nil then return 0, math.huge end
    local interval = self:getServiceReferenceInterval() * clock.intervalFactor
    local share = (spec.baseServiceLevel - (spec[clock.levelKey] or spec.baseServiceLevel))
        / (spec.baseServiceLevel - RMS_Config.CORE.SERVICE_EXPIRED_THRESHOLD)
    return share * interval, interval
end

---Returns the worse of the hourly and calendar progress of a clock
function RealisticMechanicalSystems:getServiceClockLevel(clock)
    local spec = self.spec_RealisticMechanicalSystems
    local level = spec[clock.levelKey] or spec.baseServiceLevel
    local startAge = spec.serviceCalendar ~= nil and spec.serviceCalendar[clock.key] or tonumber(self.age) or 0
    if clock.months ~= nil then
        local elapsed = math.max((tonumber(self.age) or 0) - startAge, 0)
        level = math.min(level, spec.baseServiceLevel - elapsed / clock.months
            * (spec.baseServiceLevel - RMS_Config.CORE.SERVICE_EXPIRED_THRESHOLD))
    end
    return math.max(level, 0)
end

---Returns the next service to recommend, overdue work first
function RealisticMechanicalSystems:getServiceSchedule()
    local spec = self.spec_RealisticMechanicalSystems
    local clocks = self:getServiceClocks()
    local candidates, result, requiredRank = {}, nil, 0
    local ranks = {STANDARD = 1, EXTENDED = 2, PREVENTIVE = 3}
    for _, clock in ipairs(clocks) do
        local used, interval = self:getServiceClockHours(clock)
        local elapsed = math.max((tonumber(self.age) or 0) - (spec.serviceCalendar[clock.key] or tonumber(self.age) or 0), 0)
        local calendarShare = clock.months ~= nil and elapsed / clock.months or 0
        local hourlyShare = interval < math.huge and used / interval or 0
        local progress = math.max(hourlyShare, calendarShare)
        local rank = ranks[clock.maintenanceType]
        local candidate = {clock = clock, used = used, interval = interval, months = clock.months,
            remainingMonths = clock.months ~= nil and clock.months - elapsed or nil,
            calendarDue = calendarShare >= 1, calendarLeading = calendarShare > hourlyShare,
            progress = progress, rank = rank, overdue = progress >= 1}
        table.insert(candidates, candidate)
        if candidate.overdue then requiredRank = math.max(requiredRank, rank) end
        local choose = result == nil
        if result ~= nil then
            if candidate.overdue ~= result.overdue then
                choose = candidate.overdue
            elseif candidate.overdue then
                choose = progress > result.progress + 0.000001
                    or (math.abs(progress - result.progress) <= 0.000001 and rank > result.rank)
            else
                local remaining, previous = interval - used, result.interval - result.used
                choose = remaining < previous - 0.000001
                    or (math.abs(remaining - previous) <= 0.000001 and rank > result.rank)
            end
        end
        if choose then result = candidate end
    end
    if result == nil then return nil end
    if not result.overdue then
        for _, candidate in ipairs(candidates) do
            if candidate.interval - candidate.used <= result.interval - result.used + 0.000001 then
                requiredRank = math.max(requiredRank, candidate.rank)
            end
        end
    end
    result.maintenanceType = RealisticMechanicalSystems.MAINTENANCE_TYPES[
        ({"STANDARD", "EXTENDED", "PREVENTIVE"})[math.max(requiredRank, result.rank)]]
    result.level = self:getServiceClockLevel(result.clock)
    return result
end

function RealisticMechanicalSystems:getNextServiceClock()
    local schedule = self:getServiceSchedule()
    if schedule == nil then return nil, 0, 0 end
    return schedule.clock, schedule.used, schedule.interval
end

function RealisticMechanicalSystems:getServiceCountdown()
    local _, used, interval = self:getNextServiceClock()
    return used, interval
end

function RealisticMechanicalSystems:getDueMaintenanceType()
    local schedule = self:getServiceSchedule()
    return schedule ~= nil and schedule.maintenanceType or RealisticMechanicalSystems.MAINTENANCE_TYPES.STANDARD
end

function RealisticMechanicalSystems:getMaintenanceTypes()
    local clocks = self:getServiceClocks()
    local minimum = clocks[1] ~= nil and clocks[1].maintenanceType or "STANDARD"
    local result, include = {}, false
    for _, key in ipairs({"STANDARD", "EXTENDED", "PREVENTIVE"}) do
        include = include or key == minimum
        if include then table.insert(result, RealisticMechanicalSystems.MAINTENANCE_TYPES[key]) end
    end
    return result
end

---Returns the hours between two maintenances of a level
-- @return float hours interval in the hour meter's units
function RealisticMechanicalSystems:getMaintenanceLevelInterval(maintenanceType)
    local held, programmed = math.huge, math.huge
    for _, definition in ipairs(RealisticMechanicalSystems.SERVICE_CLOCKS) do
        if RealisticMechanicalSystems.MAINTENANCE_TYPES[definition.maintenanceType] == maintenanceType then
            local hours = RealisticMechanicalSystems.getServiceProgramHours(self, definition.key)
            programmed = math.min(programmed, hours)
            if next(getServiceClockSumps(self, definition)) ~= nil then
                held = math.min(held, hours)
            end
        end
    end
    return self:getServiceReferenceInterval() * (held < math.huge and held or programmed)
        / RMS_Config.SERVICE_REFERENCE_HOURS
end

---Returns the options of the newest service
function RealisticMechanicalSystems:getLastServiceOptions()
    local spec = self.spec_RealisticMechanicalSystems
    if not spec or not spec.maintenanceLog or #spec.maintenanceLog == 0 then
        return RealisticMechanicalSystems.INSPECTION_TYPES.STANDARD, "NONE"
    else
        local lastEntry = spec.maintenanceLog[#spec.maintenanceLog]
        return lastEntry.optionOne, lastEntry.optionTwo
    end
end

---Counts the services of one type the log holds as run to their end
function RealisticMechanicalSystems:getPerformedServiceCount(serviceType)
    local count = 0
    for _, entry in ipairs(self.spec_RealisticMechanicalSystems.maintenanceLog) do
        if entry.type == serviceType and entry.isCompleted ~= false then
            count = count + 1
        end
    end
    return count
end


RealisticMechanicalSystems.WARRANTY_CONFIGURATION = "rmsWarranty"
RealisticMechanicalSystems.WARRANTY_PLANS = {
    { months = 24, hours = 2000, rate = 0 },
    { months = 36, hours = 2500, rate = 0.016 },
    { months = 48, hours = 3500, rate = 0.026 }
}

---Returns the limits of a warranty plan
-- @return integer hours hour meter limit, whole hours of play
function RealisticMechanicalSystems.getWarrantyPlan(index)
    local plan = RealisticMechanicalSystems.WARRANTY_PLANS[index]
    return plan.months, math.floor(plan.hours / (RMS_Config.CORE.BASE_SYSTEMS_WEAR * RMS_Config.CORE.MACHINE_LIFE_HOURS) + 0.5)
end

function RealisticMechanicalSystems:getWarrantyLimits()
    return RealisticMechanicalSystems.getWarrantyPlan(self.spec_RealisticMechanicalSystems.warrantyPlan)
end

---Tells whether the machine is still under its plan's months and hours
function RealisticMechanicalSystems.getIsWithinWarrantyLimits(vehicle)
    local months, hours = vehicle:getWarrantyLimits()
    return vehicle.age < months and RealisticMechanicalSystems.getRealOperatingHours(vehicle) < hours
end

---Tells whether the service or the greasing of a fault's part is overdue
function RealisticMechanicalSystems:getIsWarrantyServiceOverdue(breakdownId)
    local entry = RMS_Breakdowns.BreakdownRegistry[breakdownId]
    local causes = entry.causes
    if causes ~= nil and (table.hasElement(causes.primary, "lubf") or table.hasElement(causes.secondary, "lubf"))
        and RMS_Greasing.getStatus(self) == "late" then
        return true
    end
    local system = RMS_Utils.getSystemKey(RealisticMechanicalSystems.SYSTEMS, entry.system)
    for _, clock in ipairs(self:getServiceClocks()) do
        if table.hasElement(clock.systems, system) then
            local used, interval = self:getServiceClockHours(clock)
            local startAge = self.spec_RealisticMechanicalSystems.serviceCalendar[clock.key]
            if used >= interval or clock.months ~= nil and self.age - startAge >= clock.months then
                return true
            end
        end
    end
    return false
end

---Tells whether the warranty repairs one fault or the picked ones
-- @param string? breakdownId one fault, nil for the faults picked
-- @return string reason none covered: the faults' shared reason, or "expired"
function RealisticMechanicalSystems:isWarrantyRepairCovered(workshopType, breakdownId)
    local R, spec = RealisticMechanicalSystems, self.spec_RealisticMechanicalSystems
    if self.propertyState == VehiclePropertyState.LEASED then return false, "lease" end
    if spec.warrantyVoided then return false, "remapped" end
    local factory = R.getIsWithinWarrantyLimits(self)
    if breakdownId == nil then
        local picked, covered, reason = 0, 0, nil
        for id, fault in pairs(self:getActiveBreakdowns()) do
            if isBreakdownSelectedForPlayerRepair(id, fault, R.REPAIR_TYPES.MEDIUM) then
                picked = picked + 1
                local isCovered, faultReason = self:isWarrantyRepairCovered(workshopType, id)
                if isCovered then
                    covered = covered + 1
                else
                    reason = (reason == nil or reason == faultReason) and faultReason or "expired"
                end
            end
        end
        if picked > 0 then
            if covered == picked then return true, factory and "factory" or "part" end
            return false, covered > 0 and "partial" or reason
        end
        if not factory then return false, "expired" end
        if workshopType == R.WORKSHOP.OWN then return false, "own" end
        return true, "factory"
    end
    local fault = self:getActiveBreakdowns()[breakdownId]
    local expiry = spec.partWarranty[breakdownId]
    local part = expiry ~= nil and self.age < expiry
    -- no cover left, a refusal, then the workshop
    if not factory and not part then return false, "expired" end
    if fault ~= nil and fault.warrantyServiceOverdue then return false, "overdue" end
    if fault ~= nil and fault.warrantyAbuse ~= nil then return false, R.WARRANTY_ABUSES[fault.warrantyAbuse] end
    if workshopType == R.WORKSHOP.OWN then return false, "own" end
    return true, part and "part" or "factory"
end

---Records fitted-part cover; none for a filter, same expiry on exchange
-- @param integer? donorHours work hours of the offered donor machine
function RealisticMechanicalSystems.recordPartWarranty(vehicle, partId, partType, isPaid, donorHours)
    local R, spec = RealisticMechanicalSystems, vehicle.spec_RealisticMechanicalSystems
    spec.pickupAirTime[partId] = nil
    if RMS_Consumables.getFilterOfBreakdown(partId) ~= nil then return end
    if partType == R.PART_TYPES.USED and donorHours ~= nil and R.getIsUsedPartGuaranteed(partId, donorHours) then
        if isPaid then spec.usedPartWarranty[partId] = vehicle.age + 3 end
    else
        spec.usedPartWarranty[partId] = nil
    end
    if isPaid then
        local isDealerOriginal = spec.workshopType == R.WORKSHOP.DEALER and partType == R.PART_TYPES.OEM
        spec.partWarranty[partId] = isDealerOriginal and vehicle.age + 12 or nil
    end
end

---Marks a fitted part not new original, out of the warranty
function RealisticMechanicalSystems.markFittedPart(vehicle, partId, partType)
    local R = RealisticMechanicalSystems
    local abuse = partType == R.PART_TYPES.AFTERMARKET and "aftermarket_part" or partType == R.PART_TYPES.USED and "used_part" or nil
    local isFilter = RMS_Consumables.getFilterOfBreakdown(partId) ~= nil
    vehicle.spec_RealisticMechanicalSystems.partAbuse[partId] = not isFilter and R.WARRANTY_ABUSE[abuse] or nil
end

---Draws the donor machine of a fault's used part; a filter has none
-- @return integer? hours work hours of the donor machine, nil for a fault no repair fixes
function RealisticMechanicalSystems.drawUsedPartDonorHours(breakdownId)
    if RMS_Breakdowns.BreakdownRegistry[breakdownId].isSelectable and RMS_Consumables.getFilterOfBreakdown(breakdownId) == nil then
        local donors = RMS_Config.MAINTENANCE.USED_PART_DONOR_HOURS
        return donors[math.random(#donors)]
    end
end

-- @param integer donorHours work hours of the donor machine
-- @return integer hours on the game's hour meter
function RealisticMechanicalSystems.getUsedPartMeterHours(donorHours)
    return math.floor(donorHours / (RMS_Config.CORE.BASE_SYSTEMS_WEAR * RMS_Config.CORE.MACHINE_LIFE_HOURS) + 0.5)
end

function RealisticMechanicalSystems.getIsUsedPartGuaranteed(partId, donorHours)
    return RMS_Breakdowns.BreakdownRegistry[partId].system ~= RealisticMechanicalSystems.SYSTEMS.ENGINE
        or donorHours <= RMS_Config.CORE.MACHINE_LIFE_HOURS / 2
end

function RealisticMechanicalSystems:getIsUsedPartWarrantyCovered(breakdownId, repairType, partType)
    local R = RealisticMechanicalSystems
    if partType ~= R.PART_TYPES.USED or repairType ~= R.REPAIR_TYPES.MEDIUM then return false end
    local fault = self:getActiveBreakdowns()[breakdownId]
    -- the breaker covers its own used part, not one an abuse wore
    if fault ~= nil and fault.warrantyAbuse ~= nil and fault.warrantyAbuse ~= R.WARRANTY_ABUSE.used_part then return false end
    local expiry = self.spec_RealisticMechanicalSystems.usedPartWarranty[breakdownId]
    return expiry ~= nil and self.age < expiry
end

---Sums up the used parts offered for the faults the player repairs
-- @return integer? minimum lowest donor, game meter hours
-- @return integer? maximum highest donor, game meter hours
function RealisticMechanicalSystems:getUsedPartOfferSummary(repairType, workshopType)
    local minimum, maximum, count, guaranteed = nil, nil, 0, 0
    for id, fault in pairs(self:getActiveBreakdowns()) do
        if fault.usedPartHours ~= nil and isBreakdownSelectedForPlayerRepair(id, fault, repairType)
            and not self:isWarrantyRepairCovered(workshopType, id) then
            local hours = RealisticMechanicalSystems.getUsedPartMeterHours(fault.usedPartHours)
            minimum, maximum = math.min(minimum or hours, hours), math.max(maximum or hours, hours)
            count = count + 1
            if RealisticMechanicalSystems.getIsUsedPartGuaranteed(id, fault.usedPartHours) then guaranteed = guaranteed + 1 end
        end
    end
    if repairType ~= RealisticMechanicalSystems.REPAIR_TYPES.LOW then
        for _, id in ipairs(RealisticMechanicalSystems.getPreventiveParts(self)) do
            local donorHours = self.spec_RealisticMechanicalSystems.preventiveParts[id]
            if donorHours > 0 then
                local hours = RealisticMechanicalSystems.getUsedPartMeterHours(donorHours)
                minimum, maximum = math.min(minimum or hours, hours), math.max(maximum or hours, hours)
                count = count + 1
                if RealisticMechanicalSystems.getIsUsedPartGuaranteed(id, donorHours) then guaranteed = guaranteed + 1 end
            end
        end
    end
    return minimum, maximum, count, guaranteed
end

function RealisticMechanicalSystems.getWarrantyConfigurationName(index)
    local months, hours = RealisticMechanicalSystems.getWarrantyPlan(index)
    local key = index == 1 and "rms_warranty_base" or "rms_warranty_extension"
    return string.format(g_i18n:getText(key), months, g_i18n:formatNumber(hours, 0))
end

function RealisticMechanicalSystems.registerWarrantyConfiguration()
    local R = RealisticMechanicalSystems
    local name = R.WARRANTY_CONFIGURATION
    g_vehicleConfigurationManager:addConfigurationType(name, g_i18n:getText("rms_ws_warranty_title"), nil, VehicleConfigurationItem)
    ConfigurationUtil.getConfigurationsFromXML = Utils.overwrittenFunction(ConfigurationUtil.getConfigurationsFromXML,
        function(manager, superFunc, xmlFile, key, baseDir, customEnvironment, isMod, storeItem)
            local configurations, defaults = superFunc(manager, xmlFile, key, baseDir, customEnvironment, isMod, storeItem)
            if manager ~= g_vehicleConfigurationManager or not R.getIsStoreItemTracked(xmlFile, customEnvironment) then
                return configurations, defaults
            end
            local items = {}
            for index in ipairs(R.WARRANTY_PLANS) do
                local item = VehicleConfigurationItem.new(name)
                item.name, item.index, item.saveId = R.getWarrantyConfigurationName(index), index, tostring(index)
                item.isDefault = index == 1
                items[index] = item
            end
            configurations, defaults = configurations or {}, defaults or {}
            configurations[name], defaults[name] = items, 1
            return configurations, defaults
        end)
    EconomyManager.getBuyPrice = Utils.overwrittenFunction(EconomyManager.getBuyPrice,
        function(manager, superFunc, storeItem, configurations, saleItem)
            local price, upgrades = superFunc(manager, storeItem, configurations, saleItem)
            if saleItem == nil and configurations ~= nil and storeItem.configurations ~= nil and storeItem.configurations[name] ~= nil then
                local plan = R.WARRANTY_PLANS[configurations[name] or 1]
                local premium = price * plan.rate
                return price + premium, upgrades + premium
            end
            return price, upgrades
        end)
    ShopConfigScreen.processStoreItemConfigurationOption = Utils.overwrittenFunction(ShopConfigScreen.processStoreItemConfigurationOption,
        function(screen, superFunc, storeItem, configName, items, vehicle, isSubConfigOption, saleItem)
            if configName == name then
                if vehicle ~= nil or saleItem ~= nil or screen.saleItem ~= nil then return nil end
                for index, item in ipairs(items) do item.name = R.getWarrantyConfigurationName(index) end
            end
            return superFunc(screen, storeItem, configName, items, vehicle, isSubConfigOption, saleItem)
        end)
    ShopConfigScreen.setConfigPrice = Utils.overwrittenFunction(ShopConfigScreen.setConfigPrice,
        function(screen, superFunc, configName, index, element, vehicle)
            if configName ~= name then return superFunc(screen, configName, index, element, vehicle) end
            local configurations = RMS_Utils.shallowCopy(screen.configurations)
            configurations[name] = 1
            local base = g_currentMission.economyManager:getBuyPrice(screen.storeItem, configurations)
            element:setText("+" .. g_i18n:formatMoney(base * R.WARRANTY_PLANS[index].rate))
            element:setVisible(true)
        end)
    ShopConfigScreen.updateData = Utils.appendedFunction(ShopConfigScreen.updateData,
        function(screen, storeItem, vehicle, saleItem)
            local element = screen.configurationToListElement[name]
            if vehicle == nil and saleItem == nil and element ~= nil then
                screen:setConfigPrice(name, screen.configurations[name], element:getDescendantByName("price"), vehicle)
            end
        end)
    ShopConfigScreen.onClickLease = Utils.overwrittenFunction(ShopConfigScreen.onClickLease,
        function(screen, superFunc)
            if (screen.configurations[name] or 1) ~= 1 then
                screen.configurations[name] = 1
                screen:updateDisplay(screen.storeItem, screen.vehicle, screen.saleItem, true)
            end
            return superFunc(screen)
        end)
    BuyVehicleData.buy = Utils.overwrittenFunction(BuyVehicleData.buy,
        function(data, superFunc, ...)
            if data.configurations[name] ~= nil and (data.leaseVehicle or data.saleItem ~= nil) then
                data.configurations[name] = 1
                data.boughtConfigurations[name] = {true}
            end
            return superFunc(data, ...)
        end)
    BuyVehicleData.setLeaseVehicle = Utils.appendedFunction(BuyVehicleData.setLeaseVehicle,
        function(data, leased)
            if leased and data.configurations[name] ~= nil then
                data.configurations[name] = 1
                data.boughtConfigurations[name] = {true}
            end
        end)
end

---Tells whether the lease pays a maintenance
function RealisticMechanicalSystems:isLeaseMaintenanceCovered(workshopType)
    return self.propertyState == VehiclePropertyState.LEASED
        and (workshopType == RealisticMechanicalSystems.WORKSHOP.DEALER or workshopType == RealisticMechanicalSystems.WORKSHOP.MOBILE)
end

local function getBilledPrice(realPrice)
    local cents = math.floor(RMS_Utils.getGamePrice(realPrice) * 100 + 0.5)
    return math.ceil(cents / 1000) * 10
end

local function getLabourPrice(hours, workshopType)
    local C = RMS_Config.MAINTENANCE
    local workshopKey = RMS_Utils.getKeyByValue(RealisticMechanicalSystems.WORKSHOP, workshopType)
    return getBilledPrice(hours * C.LABOUR_RATE
        * RMS_Config.WORKSHOP.PRICE_MULTIPLIERS[workshopKey])
end

local function getStagePartsShare(vehicle, breakdownId, stage)
    local share = RMS_Breakdowns.BreakdownRegistry[breakdownId].stages[stage].repairPrice
    if type(share) ~= "table" then
        return share
    end
    local breakdown = vehicle:getActiveBreakdowns()[breakdownId]
    if breakdown ~= nil then
        return share[breakdown.branch]
    end
    local total = 0
    for _, value in ipairs(share) do
        total = total + value
    end
    return total / #share
end

---Bills a share of the reference value in parts of a quality
local function getPartsPrice(vehicle, share, repairType, partType, workshopType)
    local C = RMS_Config.MAINTENANCE
    local workshopKey = RMS_Utils.getKeyByValue(RealisticMechanicalSystems.WORKSHOP, workshopType)
    -- a quick fix fits no part
    local qualityScale = repairType == RealisticMechanicalSystems.REPAIR_TYPES.LOW and 1
        or C.PARTS_PRICE_MULTIPLIERS[RMS_Utils.getKeyByValue(RealisticMechanicalSystems.PART_TYPES, partType)]
    return getBilledPrice(share / 100 * C.REPAIR_REFERENCE_VALUE
        * getSizeScale(vehicle, C.PARTS_POWER_EXPONENT, "parts") * qualityScale
        * C.REPAIR_PRICE_MULTIPLIERS[RMS_Utils.getKeyByValue(RealisticMechanicalSystems.REPAIR_TYPES, repairType)]
        * RMS_Config.WORKSHOP.PRICE_MULTIPLIERS[workshopKey])
end

local function getBreakdownPartsPrice(vehicle, breakdownId, stage, repairType, partType, workshopType)
    return getPartsPrice(vehicle, getStagePartsShare(vehicle, breakdownId, stage), repairType, partType, workshopType)
end

local function getBreakdownLinePrice(vehicle, breakdownId, stage, repairType, partType, workshopType)
    return getBreakdownPartsPrice(vehicle, breakdownId, stage, repairType, partType, workshopType)
        + getLabourPrice(RealisticMechanicalSystems.getRepairLabourHours(vehicle, breakdownId, repairType), workshopType)
end

---Splits the parts a repair fits: the fault's, its kit, worn ones
-- @param table added parts its repair replaces beyond the fault's own part, as the quote lists them
-- @return table own the fault's part and those its stage broke, table kit, table worn
local function getAddedParts(breakdownId, stage, added)
    local renews = RMS_Breakdowns.BreakdownRegistry[breakdownId].stages[stage].renews or {}
    local group = RealisticMechanicalSystems.getRenewalGroup(breakdownId)
    local own, kit, worn = { breakdownId }, {}, {}
    for _, partId in ipairs(added) do
        if table.hasElement(renews, partId) then
            table.insert(own, partId)
        else
            table.insert((group ~= nil and table.hasElement(group.parts, partId)) and kit or worn, partId)
        end
    end
    return own, kit, worn
end

---Prices one fault of an order: labour, its parts, kit and worn parts
-- @param table added parts its repair replaces beyond its own, as the quote lists them
-- @param table rebuilt kits an earlier fault of the order already paid
-- @return table costs labourHours, labour, parts, kit, worn, ownParts, kitParts, wornParts, partType
local function getBreakdownCosts(vehicle, breakdownId, stage, repairType, partType, workshopType, added, rebuilt)
    local R = RealisticMechanicalSystems
    local hours = R.getRepairLabourHours(vehicle, breakdownId, repairType)
    local share = getStagePartsShare(vehicle, breakdownId, stage)
    local costs = { labourHours = hours, labour = getLabourPrice(hours, workshopType), kit = 0, worn = 0, partType = partType,
        repairType = repairType }
    costs.ownParts, costs.kitParts, costs.wornParts = getAddedParts(breakdownId, stage, added)
    if repairType ~= R.REPAIR_TYPES.HIGH then
        costs.parts = getPartsPrice(vehicle, share, repairType, partType, workshopType)
        return costs
    end
    local group = R.getRenewalGroup(breakdownId)
    -- a kit an earlier fault paid only adds what this stage broke beyond it
    local kitShare = group ~= nil and group.price or 0
    local partsShare = rebuilt[group] and math.max(share - kitShare, 0) or share
    costs.parts = getPartsPrice(vehicle, partsShare, repairType, partType, workshopType)
    if group ~= nil and not rebuilt[group] then
        rebuilt[group] = true
        costs.kit = getPartsPrice(vehicle, math.max(kitShare - share, 0), repairType, partType, workshopType)
    end
    local wornShare = 0
    for _, partId in ipairs(costs.wornParts) do
        wornShare = wornShare + getStagePartsShare(vehicle, partId, 1)
    end
    costs.worn = getPartsPrice(vehicle, wornShare, repairType, partType, workshopType)
    return costs
end

---Returns what the farm pays of a fault's costs, after any warranty
local function getPaidPrice(vehicle, breakdownId, costs, repairType, partType, workshopType)
    local R = RealisticMechanicalSystems
    if R.getIsUsedPartWarrantyCovered(vehicle, breakdownId, repairType, partType) then
        return costs.labour
    end
    if vehicle:isWarrantyRepairCovered(workshopType, breakdownId) then
        if workshopType == R.WORKSHOP.MOBILE then
            return math.max(costs.labour - getLabourPrice(costs.labourHours, R.WORKSHOP.DEALER), 0)
        end
        return 0
    end
    return costs.labour + costs.parts + costs.kit + costs.worn
end

---Returns the price of a service
function RealisticMechanicalSystems:getServicePrice(maintenanceType, optionOne, optionTwo, workshopTypeOverride, allBreakdowns)
    if not maintenanceType then
        maintenanceType = self.spec_RealisticMechanicalSystems.currentState
    end
    if maintenanceType == RealisticMechanicalSystems.STATUS.BODYWORK then
        return RMS_Bodywork.getPrice(self, optionOne or self.spec_RealisticMechanicalSystems.serviceOptionOne,
            workshopTypeOverride or self.spec_RealisticMechanicalSystems.workshopType) or 0
    end
    if maintenanceType == RealisticMechanicalSystems.STATUS.REMAP then
        return RMS_EngineRemap.getPrice(self, optionOne or self.spec_RealisticMechanicalSystems.serviceOptionOne)
    end
    local price = self:getPrice()
    local spec = self.spec_RealisticMechanicalSystems
    local C = RMS_Config.MAINTENANCE

    if maintenanceType == RealisticMechanicalSystems.STATUS.READY then
        return 0
    end

    local workshopType = workshopTypeOverride or spec.workshopType
    local workshopKey = RMS_Utils.getKeyByValue(RealisticMechanicalSystems.WORKSHOP, workshopType)
    local ownWorkshopDiscount = RMS_Config.WORKSHOP.PRICE_MULTIPLIERS[workshopKey] or 1.0

    if maintenanceType == RealisticMechanicalSystems.STATUS.INSPECTION then
        return getLabourPrice(RealisticMechanicalSystems.getServiceWorkHours(self, maintenanceType, optionOne), workshopType)

    elseif maintenanceType == RealisticMechanicalSystems.STATUS.MAINTENANCE then
        local maintenancePrice = 0
        for _, line in ipairs(self:getMaintenancePriceLines(optionOne, optionTwo, workshopType)) do
            maintenancePrice = maintenancePrice + line.price
        end
        return maintenancePrice

    elseif maintenanceType == RealisticMechanicalSystems.STATUS.OVERHAUL then
        local key = RMS_Utils.getKeyByValue(RealisticMechanicalSystems.OVERHAUL_TYPES, optionOne)
        local share = C.OVERHAUL_PRICE_MULTIPLIERS[key]
        if optionOne == RealisticMechanicalSystems.OVERHAUL_TYPES.PARTIAL then
            local systemWeight = RMS_Utils.getEffectiveSystemWeight(self, optionTwo, RealisticMechanicalSystems.SYSTEMS)
            if systemWeight <= 0 then
                return 0
            end
            share = share * systemWeight
        end
        local overhaulPrice = getBilledPrice(share * C.OVERHAUL_REFERENCE_VALUE * getSizeScale(self, C.PARTS_POWER_EXPONENT, "parts")
            * ownWorkshopDiscount)
        overhaulPrice = overhaulPrice + getLabourPrice(
            RealisticMechanicalSystems.getServiceWorkHours(self, maintenanceType, optionOne, optionTwo), workshopType)
        return math.min(math.max(overhaulPrice, 100), price * C.OVERHAUL_MAX_PRICE_RATIO)
    
    elseif maintenanceType == RealisticMechanicalSystems.STATUS.REPAIR then
        local repairPrice = 0
        for _, line in ipairs(self:getRepairPriceLines(optionOne, optionTwo, workshopType, allBreakdowns)) do
            repairPrice = repairPrice + line.price
        end
        return repairPrice
    end
    return 0
end

---Returns the labour and the filters of a maintenance
function RealisticMechanicalSystems:getMaintenancePriceLines(optionOne, optionTwo, workshopTypeOverride, isFullPrice)
    local C = RMS_Config.MAINTENANCE
    local key = RMS_Utils.getKeyByValue(RealisticMechanicalSystems.MAINTENANCE_TYPES, optionOne)
    local partKey = RMS_Utils.getKeyByValue(RealisticMechanicalSystems.PART_TYPES, optionTwo)
    local workshopType = workshopTypeOverride or self.spec_RealisticMechanicalSystems.workshopType
    local billedShare = (not isFullPrice and self:isLeaseMaintenanceCovered(workshopType)) and 0 or 1
    local lines = {}
    if workshopType ~= RealisticMechanicalSystems.WORKSHOP.OWN then
        table.insert(lines, { kind = "labour", price = billedShare * getLabourPrice(
            RealisticMechanicalSystems.getServiceWorkHours(self, RealisticMechanicalSystems.STATUS.MAINTENANCE, optionOne), workshopType) })
    end
    table.insert(lines, { kind = "filters", price = billedShare * getBilledPrice(C.MAINTENANCE_FILTER_PRICES[key]
        * getSizeScale(self, C.PARTS_POWER_EXPONENT, "filters") * C.PARTS_PRICE_MULTIPLIERS[partKey]) })
    for _, partId in ipairs(getRenewedParts(self, optionOne)) do
        table.insert(lines, { kind = "repair", key = partId, price = billedShare * getBreakdownPartsPrice(self, partId, 1,
            RealisticMechanicalSystems.REPAIR_TYPES.MEDIUM, optionTwo, workshopType) })
    end
    return lines
end

---Returns the price of each breakdown a repair puts right
-- @return table lines breakdownId and price of each repaired breakdown, sorted by id
function RealisticMechanicalSystems:getRepairPriceLines(optionOne, optionTwo, workshopTypeOverride, allBreakdowns)
    local R = RealisticMechanicalSystems
    local workshopType = workshopTypeOverride or self.spec_RealisticMechanicalSystems.workshopType
    local ids = {}
    for id, breakdown in pairs(self:getActiveBreakdowns()) do
        if (getIsFaultInRepair(self, id, breakdown, optionOne, workshopType) or (allBreakdowns and getIsSelectableBreakdown(id)))
            and RMS_Breakdowns.BreakdownRegistry[id] ~= nil then
            table.insert(ids, id)
        end
    end
    table.sort(ids)

    local replaced, rebuilt, lines = R.getRepairReplacedParts(self, optionOne, optionTwo, workshopType), {}, {}
    for _, id in ipairs(ids) do
        local repairType, partType = R.getFaultRepairOptions(self, id, optionOne, optionTwo, workshopType)
        local isCovered, reason = self:isWarrantyRepairCovered(workshopType, id)
        if R.getIsUsedPartWarrantyCovered(self, id, repairType, partType) then
            isCovered, reason = true, "used"
        end
        local costs = getBreakdownCosts(self, id, self:getActiveBreakdowns()[id].stage, repairType, partType, workshopType,
            replaced[id] or {}, rebuilt)
        costs.breakdownId, costs.warranty, costs.warrantyReason = id, isCovered, reason
        costs.gross = costs.labour + costs.parts + costs.kit + costs.worn
        costs.price = getPaidPrice(self, id, costs, repairType, partType, workshopType)
        table.insert(lines, costs)
    end
    -- a quick fix fits no part; a thorough one may fit it already
    if optionOne ~= R.REPAIR_TYPES.LOW then
        local fitted = {}
        for _, parts in pairs(replaced) do
            for _, partId in ipairs(parts) do
                fitted[partId] = true
            end
        end
        for _, id in ipairs(R.getPreventiveParts(self)) do
            if not fitted[id] then
                local costs = getBreakdownCosts(self, id, 1, R.REPAIR_TYPES.MEDIUM, optionTwo, workshopType, {}, {})
                costs.breakdownId, costs.isPreventive, costs.warranty = id, true, false
                costs.gross = costs.labour + costs.parts
                costs.price = costs.gross
                table.insert(lines, costs)
            end
        end
    end
    return lines
end

---Returns the price of repairing one breakdown at a stage with a part type
function RealisticMechanicalSystems:getBreakdownRepairPrice(breakdownId, breakdownStage, partType, workshopTypeOverride, repairType)
    local registryEntry = RMS_Breakdowns.BreakdownRegistry[breakdownId]
    if registryEntry == nil or registryEntry.stages[breakdownStage] == nil then
        return 0
    end

    local workshopType = workshopTypeOverride or self.spec_RealisticMechanicalSystems.workshopType
    repairType = repairType or RealisticMechanicalSystems.REPAIR_TYPES.MEDIUM
    local added = RealisticMechanicalSystems.getRepairFittedParts(self, breakdownId, breakdownStage, repairType,
        self.spec_RealisticMechanicalSystems.partWear, function(partId) return self:getActiveBreakdowns()[partId] ~= nil end)
    table.remove(added, 1)
    local costs = getBreakdownCosts(self, breakdownId, breakdownStage, repairType, partType, workshopType, added, {})
    return getPaidPrice(self, breakdownId, costs, repairType, partType, workshopType)
end

function RealisticMechanicalSystems:getPartReplacementPrice(partId)
    return getBreakdownLinePrice(self, partId, 1, RealisticMechanicalSystems.REPAIR_TYPES.MEDIUM, RealisticMechanicalSystems.PART_TYPES.OEM,
        RealisticMechanicalSystems.WORKSHOP.DEALER)
end

-- a running timer moves by steps: count from its step, not from now
local function getServiceCountStart(spec)
    if spec.currentState ~= RealisticMechanicalSystems.STATUS.READY and spec.currentState ~= RealisticMechanicalSystems.STATUS.BROKEN then
        return spec.maintenanceTimerTime
    end
    return RMS_Thermal.getWorldTimeMS()
end

---Returns the duration of a service in real time
-- @return float duration service duration in ms
function RealisticMechanicalSystems:getServiceDuration(maintenanceType, optionOne, optionTwo, workshopTypeOverride)
    local spec = self.spec_RealisticMechanicalSystems
    local workshopType = workshopTypeOverride or spec.workshopType

    if not maintenanceType then maintenanceType = spec.currentState end

    if maintenanceType == RealisticMechanicalSystems.STATUS.READY then
        return 0
    end

    local workDurationHours = 0

    if spec.currentState ~= RealisticMechanicalSystems.STATUS.READY and spec.currentState ~= RealisticMechanicalSystems.STATUS.BROKEN then
        workDurationHours = spec.maintenanceTimer / 3600000
    else
        local totalDurationMs = getServiceWorkDurationMs(self, maintenanceType, optionOne, optionTwo, workshopType)
        workDurationHours = totalDurationMs / 3600000
    end

    if workDurationHours <= 0 then
        return 0
    end

    local totalElapsedHours

    if RMS_Main:isWorkshopTypeAlwaysAvailable(workshopType) then
        totalElapsedHours = workDurationHours
    else
        local WORKSHOP_HOURS = RMS_Config.WORKSHOP
        local currentHour = (getServiceCountStart(spec) / 3600000) % 24

        totalElapsedHours = 0
        local timeRemaining = workDurationHours

        local workStartTimeToday = math.max(currentHour, WORKSHOP_HOURS.OPEN_HOUR)

        if workStartTimeToday >= WORKSHOP_HOURS.CLOSE_HOUR then
            local hoursUntilNextOpen = (24 - currentHour) + WORKSHOP_HOURS.OPEN_HOUR
            totalElapsedHours = totalElapsedHours + hoursUntilNextOpen
            currentHour = WORKSHOP_HOURS.OPEN_HOUR
        elseif currentHour < WORKSHOP_HOURS.OPEN_HOUR then
            local hoursUntilOpen = WORKSHOP_HOURS.OPEN_HOUR - currentHour
            totalElapsedHours = totalElapsedHours + hoursUntilOpen
            currentHour = WORKSHOP_HOURS.OPEN_HOUR
        end

        while timeRemaining > 0 do
            local remainingWorkHoursToday = WORKSHOP_HOURS.CLOSE_HOUR - currentHour

            if timeRemaining <= remainingWorkHoursToday then
                totalElapsedHours = totalElapsedHours + timeRemaining
                timeRemaining = 0
            else
                totalElapsedHours = totalElapsedHours + remainingWorkHoursToday
                timeRemaining = timeRemaining - remainingWorkHoursToday

                local overnightBreak = (24 - WORKSHOP_HOURS.CLOSE_HOUR) + WORKSHOP_HOURS.OPEN_HOUR
                totalElapsedHours = totalElapsedHours + overnightBreak

                currentHour = WORKSHOP_HOURS.OPEN_HOUR
            end
        end
    end

    return totalElapsedHours
end

---Returns the in game time a service would finish at
-- @return float finishTime hour of the day the service ends
function RealisticMechanicalSystems:getServiceFinishTime(maintenanceType, optionOne, optionTwo, workshopTypeOverride)
    local spec = self.spec_RealisticMechanicalSystems

    if not maintenanceType then maintenanceType = spec.currentState end
    local savedOptionOne, savedOptionTwo = self:getLastServiceOptions()
    if optionOne == nil then optionOne = savedOptionOne end
    if optionTwo == nil then optionTwo = savedOptionTwo end

    if maintenanceType == RealisticMechanicalSystems.STATUS.READY then
        return 0
    end

    local totalCalendarDuration = RealisticMechanicalSystems.getServiceDuration(self, maintenanceType, optionOne, optionTwo, workshopTypeOverride)

    if totalCalendarDuration <= 0 then
        local currentTime = (g_currentMission.environment.dayTime / 3600000) % 24
        return currentTime, 0
    end

    local finish = getServiceCountStart(spec) / 3600000 + totalCalendarDuration
    return finish % 24, math.floor(finish / 24) - g_currentMission.environment.currentMonotonicDay
end
