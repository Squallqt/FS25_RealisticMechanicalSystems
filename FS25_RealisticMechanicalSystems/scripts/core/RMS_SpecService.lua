-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---Vehicle workshop services.

local log_dbg = RMS_Utils.createLogger("[RMS_SPEC]")
local getSafeMissionTimeScale = RealisticMechanicalSystems.getSafeMissionTimeScale

---Tells whether a visible breakdown was picked for this repair type
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

---Tells whether a breakdown can be picked by the player
local function getIsSelectableBreakdown(breakdownId)
    local breakdownDef = RMS_Breakdowns.BreakdownRegistry[breakdownId]
    if breakdownDef == nil or breakdownDef.isSelectable ~= true then
        return false
    end
    return true
end

local AGRICULTURAL_PRICE_FACTORS = { labour = 1, filters = 1, parts = 1 }

---Returns how a machine's size scales a real price
local function getSizeScale(vehicle, exponent, factorKey)
    local C = RMS_Config.MAINTENANCE
    local factors = C.PROFILE_PRICE_FACTORS[RMS_Fluids.getProfileName(vehicle)] or AGRICULTURAL_PRICE_FACTORS
    return (RMS_Fluids.getEnginePower(vehicle) / C.REFERENCE_POWER) ^ exponent * factors[factorKey]
end

---Returns the labour hours of an operation, for billing and work timers
local function getLabourHours(vehicle, hours, category)
    return hours * getSizeScale(vehicle, RMS_Config.MAINTENANCE.LABOUR_POWER_EXPONENT, "labour")
        * RMS_Utils.getServiceAccessLabourFactor(vehicle, category)
end

-- @param table vehicle vehicle
-- @param string breakdownId breakdown id
-- @param string repairType repair type
-- @return float hours labour hours
function RealisticMechanicalSystems.getRepairLabourHours(vehicle, breakdownId, repairType)
    local C = RMS_Config.MAINTENANCE
    local operation = C.REPAIR_OPERATIONS[breakdownId]
    if operation == nil then return 0 end
    local key = RMS_Utils.getKeyByValue(RealisticMechanicalSystems.REPAIR_TYPES, repairType)
    return getLabourHours(vehicle, operation.hours * C.REPAIR_TIME_MULTIPLIERS[key], operation.category)
end

---
local function getOverhaulAccessFactor(vehicle, systemName)
    local systems = RealisticMechanicalSystems.SYSTEMS
    ---
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
function RealisticMechanicalSystems.getServiceWorkHours(vehicle, serviceType, optionOne, optionTwo, optionThree)
    local C, states = RMS_Config.MAINTENANCE, RealisticMechanicalSystems.STATUS
    if serviceType == states.INSPECTION then
        local key = RMS_Utils.getKeyByValue(RealisticMechanicalSystems.INSPECTION_TYPES, optionOne)
        return getLabourHours(vehicle, C.INSPECTION_TIME * C.INSPECTION_TIME_MULTIPLIERS[key] / 3600000,
            key == "VISUAL" and "external" or "diagnostic")
    elseif serviceType == states.MAINTENANCE then
        local key = RMS_Utils.getKeyByValue(RealisticMechanicalSystems.MAINTENANCE_TYPES, optionOne)
        return getLabourHours(vehicle, C.MAINTENANCE_LABOUR_HOURS[key], "maintenance")
    elseif serviceType == states.REPAIR then
        local hours = 0
        for id, breakdown in pairs(vehicle:getActiveBreakdowns() or {}) do
            if isBreakdownSelectedForPlayerRepair(id, breakdown, optionOne) then
                hours = hours + RealisticMechanicalSystems.getRepairLabourHours(vehicle, id, optionOne)
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
        return hours + (optionThree and C.REPAINT_TIME / 3600000 or 0)
    elseif serviceType == states.BODYWORK then
        return (RMS_Bodywork.getDurationMs(vehicle, optionOne) or 0) / 3600000
    elseif serviceType == states.REFILL then
        return C.REFILL_TIME / 3600000
    end
    return 0
end

---
local function getServiceWorkDurationMs(vehicle, serviceType, optionOne, optionTwo, optionThree)
    local hours = RealisticMechanicalSystems.getServiceWorkHours(vehicle, serviceType, optionOne, optionTwo, optionThree)
    if hours <= 0 then return 0 end
    local C, states = RMS_Config.MAINTENANCE, RealisticMechanicalSystems.STATUS
    local instant = serviceType == states.INSPECTION and C.INSTANT_INSPECTION
        or (serviceType == states.MAINTENANCE or serviceType == states.REPAIR) and C.INSTANT_MAINTENANCE_REPAIR
        or serviceType == states.OVERHAUL and C.INSTANT_OVERHAUL
        or serviceType == states.BODYWORK and C.INSTANT_BODYWORK
    return instant and 1000 or hours * 3600000
end

---Clears every pending service field of the spec
local function resetPendingServiceProgress(spec)
    spec.pendingSelectedBreakdowns = {}
    spec.pendingServicePrice = nil
    spec.pendingServiceInvoice = nil
    spec.pendingInspectionQueue = {}
    spec.pendingRepairQueue = {}
    spec.pendingProgressStepIndex = 0
    spec.pendingProgressTotalTime = 0
    spec.pendingProgressElapsedTime = 0
    spec.pendingServiceClockStart = {}
    spec.pendingServiceClockTarget = {}
    spec.pendingOverhaulPartStart = {}
    spec.pendingOverhaulPartTarget = {}
    spec.pendingFluidRequirements = {}
end

---Returns the sumps a service clock covers on the vehicle, those holding oil
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

---Brings the service clocks a running service resets toward their new level
local function applyPendingServiceClockInterpolation(spec, ratio)
    for _, clock in ipairs(RealisticMechanicalSystems.SERVICE_CLOCKS) do
        local startLevel = spec.pendingServiceClockStart[clock.key]
        local targetLevel = spec.pendingServiceClockTarget[clock.key]
        if startLevel ~= nil and targetLevel ~= nil then
            spec[clock.levelKey] = startLevel + (targetLevel - startLevel) * ratio
        end
    end
end

---Brings the parts a running overhaul renews toward their new wear
local function applyPendingOverhaulPartInterpolation(spec, ratio)
    for partId, startWear in pairs(spec.pendingOverhaulPartStart) do
        spec.partWear[partId] = startWear + (spec.pendingOverhaulPartTarget[partId] - startWear) * ratio
    end
    for systemKey in pairs(spec.systemParts) do
        RealisticMechanicalSystems.refreshSystemCondition(spec, systemKey)
    end
end

---Lists the systems the adjustments of a major service reach
-- @param table vehicle vehicle
-- @return table systemKeys system keys
function RealisticMechanicalSystems.getMajorServiceSystems(vehicle)
    local systems = vehicle.spec_RealisticMechanicalSystems.systems
    local systemKeys = {}
    for _, breakdownId in ipairs(RealisticMechanicalSystems.MAJOR_SERVICE_CHECKS) do
        local breakdown = RMS_Breakdowns.BreakdownRegistry[breakdownId]
        local systemKey = RMS_Utils.getSystemKey(RealisticMechanicalSystems.SYSTEMS, breakdown.system)
        if systems[systemKey].enabled and breakdown.isApplicable(vehicle) and not table.hasElement(systemKeys, systemKey) then
            table.insert(systemKeys, systemKey)
        end
    end
    return systemKeys
end

---Skips a vehicle in the tab selection while its service runs
-- @param function superFunc native or previously overwritten function
-- @return boolean isTabbable true when the vehicle may be selected with the tab key
function RealisticMechanicalSystems:getIsTabbable(superFunc)
    local spec = self.spec_RealisticMechanicalSystems
    if spec ~= nil and not spec.isExcludedVehicle and self:isUnderService() then
        return false
    end
    return superFunc(self)
end

---Starts a service, building its step queues, its duration and its price
-- @param string type service status constant
-- @param string? workshopType workshop the service runs at
-- @param string? optionOne first service option
-- @param string? optionTwo second service option
-- @param boolean? optionThree third service option
function RealisticMechanicalSystems:initService(type, workshopType, optionOne, optionTwo, optionThree)
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

    if type == states.OVERHAUL and optionThree == true then
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

    if type == states.OVERHAUL
        and optionOne == RealisticMechanicalSystems.OVERHAUL_TYPES.PARTIAL
        and optionTwo ~= nil
        and RMS_Utils.getEffectiveSystemWeight(self, optionTwo, RealisticMechanicalSystems.SYSTEMS) <= 0 then
        log_dbg(string.format("Skipping partial overhaul for %s: invalid or disabled target system '%s'", self:getFullName(), tostring(optionTwo)))
        return false
    end

    if not RMS_FluidWorkshop.getWorkshopAvailability(self, type, workshopType, optionOne) then
        return false
    end

    local totalTimeMs = getServiceWorkDurationMs(self, type, optionOne, optionTwo, optionThree)
    if self:getIsOperating() then
        self:stopMotor()
    end

    spec.currentState = type
    spec.plannedState = states.READY
    spec.workshopType = workshopType
    spec.serviceOptionOne = optionOne
    spec.serviceOptionTwo = optionTwo
    spec.serviceOptionThree = optionThree
    if type == states.BODYWORK then
        spec.bodyworkPreviewFinalized = false
    end
    resetPendingServiceProgress(spec)

    -- inspection
    if type == states.INSPECTION or type == states.MAINTENANCE then
        if type == states.INSPECTION then

            repairPrice = self:getServicePrice(type, optionOne, optionTwo, optionThree)
        end

        for id, breakdown in pairs(self:getActiveBreakdowns()) do
            if breakdown ~= nil and not breakdown.isVisible then
                table.insert(spec.pendingInspectionQueue, id)
            end
        end
    end

    -- maintenance
    if type == states.MAINTENANCE then
        if self:hasBreakdown("MAINTENANCE_WITH_POOR_QUALITY_CONSUMABLES") then
            self:removeBreakdown("MAINTENANCE_WITH_POOR_QUALITY_CONSUMABLES")
        end
        repairPrice = self:getServicePrice(type, optionOne, optionTwo, optionThree)

    -- repair
    elseif type == states.REPAIR then
        local idsToRepair = {}
        for id, breakdown in pairs(self:getActiveBreakdowns()) do
            if isBreakdownSelectedForPlayerRepair(id, breakdown, optionOne) then
                table.insert(idsToRepair, id)
            end
        end

        spec.pendingRepairQueue = RMS_Utils.shallowCopy(idsToRepair)
        repairPrice = self:getServicePrice(type, optionOne, optionTwo, optionThree)

    -- fluid top up
    elseif type == states.REFILL then
        repairPrice = self:getServicePrice(type, optionOne, optionTwo, optionThree)

    -- bodywork
    elseif type == states.BODYWORK then
        repairPrice = RMS_Bodywork.getPrice(self, optionOne, workshopType)

    -- overhaul
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
            log_dbg(string.format("Skipping partial overhaul for %s: no valid system targets resolved for '%s'", self:getFullName(), tostring(optionTwo)))
            spec.currentState = states.READY
            spec.plannedState = states.READY
            spec.workshopType = workshopType
            spec.serviceOptionOne = nil
            spec.serviceOptionTwo = nil
            spec.serviceOptionThree = false
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
        local adjustedTotalTimeMs = totalTimeMs
        spec.maintenanceTimer = adjustedTotalTimeMs
        spec.pendingProgressTotalTime = adjustedTotalTimeMs
        spec.pendingProgressElapsedTime = 0
        spec.pendingProgressStepIndex = 0
        log_dbg(string.format(
            '%s initiated for %s, will take %.2f seconds (%.2f seconds booked). Next planned state: %s',
            spec.currentState,
            self:getFullName(),
            totalTimeMs / 1000,
            spec.maintenanceTimer / 1000,
            spec.plannedState
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

---Repairs one breakdown of the running service
local function processPendingRepairStep(vehicle, spec, breakdownId, optionOne, optionTwo, optionTwoKey)
    if breakdownId == nil or vehicle:getActiveBreakdowns()[breakdownId] == nil then
        return
    end

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
        local isPaid = not (vehicle:isWarrantyRepairCovered(optionOne, optionTwo, spec.workshopType, breakdownId)
            or RealisticMechanicalSystems.getIsUsedPartWarrantyCovered(vehicle, breakdownId, optionOne, optionTwo))
        vehicle:removeBreakdown(breakdownId)

        local wear = 0
        if optionTwo == RealisticMechanicalSystems.PART_TYPES.USED and donorHours ~= nil then
            wear = donorHours / RMS_Config.CORE.MACHINE_LIFE_HOURS
        end
        local renewedParts = { breakdownId }
        for _, partId in ipairs(RMS_Breakdowns.BreakdownRegistry[breakdownId].stages[stage].renews or {}) do
            if not vehicle:hasBreakdown(partId) then
                table.insert(renewedParts, partId)
            end
        end
        for _, group in ipairs(RMS_Config.CORE.RENEWAL_GROUPS) do
            if table.hasElement(group, breakdownId) then
                for _, partId in ipairs(group) do
                    if partId ~= breakdownId and not vehicle:hasBreakdown(partId) then
                        table.insert(renewedParts, partId)
                    end
                end
                break
            end
        end
        if optionOne == RealisticMechanicalSystems.REPAIR_TYPES.HIGH then
            for _, partId in ipairs(spec.systemParts[systemKey]) do
                if not vehicle:hasBreakdown(partId) and RMS_Utils.getIsPartWorn(partId, spec.partWear[partId]) then
                    table.insert(renewedParts, partId)
                end
            end
        end
        for _, partId in ipairs(renewedParts) do
            RealisticMechanicalSystems.recordPartWarranty(vehicle, partId, optionTwo, isPaid, donorHours)
            if spec.partWear[partId] ~= nil then
                spec.partWear[partId] = wear
            end
        end
        RealisticMechanicalSystems.refreshSystemCondition(spec, systemKey)
        if breakdownId == "CVT_ADDON_MALFUNCTION" then
            vehicle.spec_CVTaddon.CVTdamage = wear * 100
        end

        if RMS_Consumables.getFilterOfBreakdown(breakdownId) ~= nil then
            RMS_Consumables.renewFilters(vehicle, breakdownId)
        elseif math.random() < C.PARTS_BREAKDOWN_CHANCES[optionTwoKey] then
            local serviceScale = RMS_Config.CORE.REFERENCE_SERVICE_WEAR / RMS_Config.CORE.BASE_SERVICE_WEAR
            vehicle:addBreakdown(breakdownId, {
                stage = stage,
                isVisible = false,
                isSelectedForRepair = true,
                isActive = false,
                resumeTimer = RMS_Config.CORE.REPEAT_BREAKDOWN_TIME * serviceScale * (math.random() + 0.5),
                progressTimer = 0,
                source = RealisticMechanicalSystems.BREAKDOWN_SOURCES.POOR_PARTS
            })
        end
    end
end

---Advances the running service through its step queue
-- @param float dt time since last call in ms
-- @param boolean? ignoreWorkshopHours true to advance independently of opening hours
function RealisticMechanicalSystems:processService(dt, ignoreWorkshopHours)
    local spec = self.spec_RealisticMechanicalSystems
    local states = RealisticMechanicalSystems.STATUS
    local vehicleState = self:getCurrentStatus()
    local C = RMS_Config.MAINTENANCE

    if vehicleState == states.READY
        or (not ignoreWorkshopHours and not RMS_Main:isWorkshopTypeOpen(spec.workshopType)) then
        return
    end

    local timeScale = getSafeMissionTimeScale()
    local prevTimer = spec.maintenanceTimer or 0
    spec.maintenanceTimer = (spec.maintenanceTimer or 0) - dt * timeScale
    local progressed = math.max(prevTimer - math.max(spec.maintenanceTimer, 0), 0)

    if spec.pendingProgressTotalTime > 0 then
        spec.pendingProgressElapsedTime = math.min((spec.pendingProgressElapsedTime or 0) + progressed, spec.pendingProgressTotalTime)
    end

    local serviceType = spec.currentState
    local optionOne = spec.serviceOptionOne
    local optionTwo = spec.serviceOptionTwo
    local optionTwoKey = RMS_Utils.getKeyByValue(RealisticMechanicalSystems.PART_TYPES, optionTwo)

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
                processPendingRepairStep(self, spec, breakdownId, optionOne, optionTwo, optionTwoKey)
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
        if serviceType == states.MAINTENANCE and math.random() < C.PARTS_BREAKDOWN_CHANCES[optionTwoKey] then
            self:addBreakdown('MAINTENANCE_WITH_POOR_QUALITY_CONSUMABLES', 1)
            log_dbg("Added breakdown 'MAINTENANCE_WITH_POOR_QUALITY_CONSUMABLES' due to poor quality consumables chance.")
        end
        self:completeService()
    end
end

---Tells whether only a diagnostic tool reads a breakdown
-- @param string breakdownId breakdown id
-- @return boolean needsTool true when a look at the machine cannot find it
function RealisticMechanicalSystems.getBreakdownNeedsDiagnosticTool(breakdownId)
    local operation = RMS_Config.MAINTENANCE.REPAIR_OPERATIONS[breakdownId]
    return operation ~= nil and RMS_Config.MAINTENANCE.INSPECTION_TOOL_CATEGORIES[operation.category] == true
end

---Returns the share of its detection chance a fault keeps under an inspection
-- @param string inspectionType inspection type
-- @param boolean needsTool true for a fault only a diagnostic tool reads
-- @return float share share of the detection chance of the fault
function RealisticMechanicalSystems.getInspectionDetectionShare(inspectionType, needsTool)
    if needsTool and inspectionType == RealisticMechanicalSystems.INSPECTION_TYPES.VISUAL then
        return 0
    end
    return RMS_Config.MAINTENANCE.INSPECTION_DETECTION_CHANCE_MULTIPLIERS[
        RMS_Utils.getKeyByValue(RealisticMechanicalSystems.INSPECTION_TYPES, inspectionType)]
end

---Tells whether an inspection also looks for the dormant faults
-- @param string inspectionType inspection type
-- @return boolean findsDormant true for the complete inspection
function RealisticMechanicalSystems.getInspectionFindsDormant(inspectionType)
    return inspectionType == RealisticMechanicalSystems.INSPECTION_TYPES.COMPLETE
end

---Tells whether a maintenance reads the fault codes of a machine
-- @param table vehicle vehicle
-- @param string workshopType workshop type
-- @return boolean readsFaultCodes includes diagnostic-only faults
function RealisticMechanicalSystems.getMaintenanceReadsFaultCodes(vehicle, workshopType)
    return RMS_FluidWorkshop.getWorkshopAvailability(vehicle, RealisticMechanicalSystems.STATUS.INSPECTION, workshopType,
        RealisticMechanicalSystems.INSPECTION_TYPES.STANDARD) == true
end

---Tells whether a machine lights a telltale for an unidentified fault
-- @param table vehicle vehicle
-- @return boolean hasWarning unidentified fault lights a telltale
function RealisticMechanicalSystems.getHasUnidentifiedWarning(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    local hasEngineOil = RMS_Fluids.hasCircuit(vehicle, "engineOil")
    for breakdownId, breakdown in pairs(vehicle:getActiveBreakdowns()) do
        local definition = RMS_Breakdowns.BreakdownRegistry[breakdownId]
        if definition.isSelectable and breakdown.isActive and not breakdown.isVisible then
            for _, indicator in ipairs(RMS_Utils.getBranchItems(definition.stages[breakdown.stage].indicators, breakdown)) do
                if RMS_Hud.getIsTelltaleFitted(indicator.id, RMS_Hud.TELLTALE_YEARS[indicator.id] or 0, spec, hasEngineOil) then
                    return true
                end
            end
        end
    end
    return false
end

---Tells whether a maintenance level fits a new air filter
-- @param string maintenanceType maintenance type
-- @return boolean renews true when the filter is replaced
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
    local optionThree = spec.serviceOptionThree
    local isMobileWorkshop = spec.workshopType == RealisticMechanicalSystems.WORKSHOP.MOBILE
    local selectedBreakdowns = RMS_Utils.shallowCopy(spec.pendingSelectedBreakdowns or {})
    local plannedRepairCandidateIds = {}

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
                    RealisticMechanicalSystems.recordPartWarranty(self, partId, optionTwo,
                        not self:isLeaseMaintenanceCovered(spec.workshopType))
                    RealisticMechanicalSystems.refreshSystemCondition(spec, RMS_Utils.getSystemKey(RealisticMechanicalSystems.SYSTEMS, definition.system))
                end
            end
            self:updateConditionLevel()
        end

        RMS_Consumables.renewFilters(self, nil, optionOne)
        for index = #selectedBreakdowns, 1, -1 do
            if not self:hasBreakdown(selectedBreakdowns[index]) then
                table.remove(selectedBreakdowns, index)
            end
        end
    end

    if serviceType == states.OVERHAUL then
        applyPendingOverhaulPartInterpolation(spec, 1)
        for partId in pairs(spec.pendingOverhaulPartTarget) do
            RealisticMechanicalSystems.recordPartWarranty(self, partId, RealisticMechanicalSystems.PART_TYPES.OEM, true)
        end
        self:updateConditionLevel()
        if RMS_Utils.hasCVTAddon(self) and (optionOne ~= RealisticMechanicalSystems.OVERHAUL_TYPES.PARTIAL
            or optionTwo == RealisticMechanicalSystems.SYSTEMS.TRANSMISSION) then
            local target = RMS_Config.MAINTENANCE.OVERHAUL_CONDITION_TARGETS[RMS_Utils.getKeyByValue(RealisticMechanicalSystems.OVERHAUL_TYPES, optionOne)]
            self.spec_CVTaddon.CVTdamage = math.min(self.spec_CVTaddon.CVTdamage, (1 - target) * 100)
        end

        local idsToRepair = {}
        for id, _ in pairs(spec.activeBreakdowns) do
            if RMS_Breakdowns.BreakdownRegistry[id] and RMS_Breakdowns.BreakdownRegistry[id].isSelectable then
                if optionOne ~= RealisticMechanicalSystems.OVERHAUL_TYPES.PARTIAL or optionTwo == RMS_Breakdowns.BreakdownRegistry[id].system then
                    table.insert(idsToRepair, id)
                end
            end
        end

        selectedBreakdowns = idsToRepair
        if #idsToRepair > 0 then
            self:removeBreakdown(table.unpack(idsToRepair))
        end
        RMS_Consumables.renewFilters(self)
    elseif serviceType == states.REPAIR then
        local optionTwoKey = RMS_Utils.getKeyByValue(RealisticMechanicalSystems.PART_TYPES, optionTwo)
        local repairQueue = spec.pendingRepairQueue or {}
        spec.pendingProgressStepIndex = math.max(math.floor(tonumber(spec.pendingProgressStepIndex) or 0), 0)

        while spec.pendingProgressStepIndex < #repairQueue do
            spec.pendingProgressStepIndex = spec.pendingProgressStepIndex + 1
            local breakdownId = repairQueue[spec.pendingProgressStepIndex]
            processPendingRepairStep(self, spec, breakdownId, optionOne, optionTwo, optionTwoKey)
        end

        selectedBreakdowns = RMS_Utils.shallowCopy(spec.pendingSelectedBreakdowns or {})
        self:updateConditionLevel()

        if optionThree == true then
            spec.plannedState = states.MAINTENANCE
        end
    end

    if serviceType == states.INSPECTION or serviceType == states.MAINTENANCE then
        local needRepair = #selectedBreakdowns > 0
        for _, breakdownId in ipairs(selectedBreakdowns) do
            table.insert(plannedRepairCandidateIds, breakdownId)
        end

        for breakdownId, breakdown in pairs(self:getActiveBreakdowns()) do
            if breakdown.isVisible and breakdown.isSelectedForRepair then
                needRepair = true
                table.insert(plannedRepairCandidateIds, breakdownId)
            end
        end

        if optionThree and needRepair then
            for _, breakdownId in ipairs(plannedRepairCandidateIds) do
                local breakdown = self:getActiveBreakdowns()[breakdownId]
                if breakdown ~= nil and breakdown.isVisible then
                    breakdown.isSelectedForRepair = true
                end
            end
            spec.plannedState = states.REPAIR
        end
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

    spec.pendingSelectedBreakdowns = selectedBreakdowns
    self:recalculateAndApplyEffects()
    self:addEntryToMaintenanceLog(serviceType, optionOne, optionTwo, optionThree, spec.pendingServicePrice, true, spec.pendingServiceInvoice)

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
        spec.lubricationLevel = 1.0
        spec.lubricationUsedThisPeriod = true
    end

    ---Clears the paint wear of every wearable node of the vehicle
    local function resetVehicleRepaintWear(vehicle)
        if vehicle == nil or vehicle.spec_wearable == nil then
            return
        end

        local specWearable = vehicle.spec_wearable
        if specWearable.wearableNodes == nil then
            return
        end

        for _, nodeData in ipairs(specWearable.wearableNodes) do
            vehicle:setNodeWearAmount(nodeData, 0, true)
        end
    end

    if serviceType == states.OVERHAUL and optionThree == true then
        resetVehicleRepaintWear(self)
    end

    local maintenanceCompletedText = string.format(g_i18n:getText("rms_hud_vehicle_notification"), self:getFullName(),
        string.format(g_i18n:getText("rms_spec_maintenance_complete_notification"), RMS_Utils.formatServiceState(serviceType)))

    if serviceType == states.INSPECTION or serviceType == states.MAINTENANCE then
        local activeBreakdowns = self:getActiveBreakdowns()
        local activeBreakdownsCount = 0
        for _, value in pairs(activeBreakdowns) do
            if value.isVisible then
                activeBreakdownsCount = activeBreakdownsCount + 1
            end
        end
        if activeBreakdownsCount == 0 then
            maintenanceCompletedText = maintenanceCompletedText .. ". " .. g_i18n:getText("rms_spec_inspection_no_issues_detected_notification")
        else
            maintenanceCompletedText = maintenanceCompletedText .. ". " .. string.format(g_i18n:getText("rms_spec_inspection_issues_detected_notification"), activeBreakdownsCount)
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
    spec.serviceOptionThree = false

    RealisticMechanicalSystems.raiseRMSDirty(self, RealisticMechanicalSystems.SYNC_GROUP.STATE
        + RealisticMechanicalSystems.SYNC_GROUP.SERVICE_PROGRESS
        + RealisticMechanicalSystems.SYNC_GROUP.SERVICE_CONTEXT)

    if spec.plannedState ~= states.READY then
        local nextWork = spec.plannedState
        spec.plannedState = states.READY
        spec.currentState = states.READY

        local nextOptionOne, nextOptionTwo, nextOptionThree

        if nextWork == states.REPAIR then
            nextOptionOne = RealisticMechanicalSystems.REPAIR_TYPES.MEDIUM
            nextOptionTwo = RealisticMechanicalSystems.PART_TYPES.OEM
            nextOptionThree = false
        elseif nextWork == states.MAINTENANCE then
            nextOptionOne = self:getDueMaintenanceType()
            nextOptionTwo = RealisticMechanicalSystems.PART_TYPES.OEM
            nextOptionThree = false
        end

        if nextWork == states.REPAIR then
            local repairQueueCount = 0
            for breakdownId, breakdown in pairs(self:getActiveBreakdowns()) do
                if isBreakdownSelectedForPlayerRepair(breakdownId, breakdown, RealisticMechanicalSystems.REPAIR_TYPES.MEDIUM) then
                    repairQueueCount = repairQueueCount + 1
                end
            end

            if repairQueueCount == 0 then
                log_dbg("Planned REPAIR skipped: no visible selected breakdowns to repair.")
                RMS_VehicleChangeStatusEvent.send(self, maintenanceCompletedText, lastEntry)
                return
            end
        end

        local started, result = RMS_FluidWorkshop.tryStartService(
            self,
            nil,
            nextWork,
            spec.workshopType,
            nextOptionOne,
            nextOptionTwo,
            nextOptionThree
        )

        if started then
            local nextServiceMessage = string.format(g_i18n:getText('rms_spec_next_planned_service_notification'), g_i18n:getText(nextWork))
            local nextServiceText = string.format(g_i18n:getText("rms_hud_vehicle_notification"), self:getFullName(), nextServiceMessage)
            if g_currentMission.hud ~= nil and g_currentMission.hud.addSideNotification ~= nil
                    and self:getOwnerFarmId() == g_currentMission:getFarmId() then
                g_currentMission.hud:addSideNotification({1, 1, 1, 1}, nextServiceText)
            end
            RMS_VehicleChangeStatusEvent.send(self, maintenanceCompletedText .. ". " .. nextServiceMessage, lastEntry)
        else
            if result == RMS_FluidWorkshop.RESULT.NOT_ENOUGH_MONEY then
                local notEnoughMoneyText = string.format(
                    g_i18n:getText("rms_hud_vehicle_notification"),
                    self:getFullName(),
                    string.format(
                        g_i18n:getText('rms_spec_next_planned_service_not_enough_money_notification'),
                        g_i18n:getText(nextWork)
                    )
                )
                if g_currentMission.hud ~= nil and g_currentMission.hud.addSideNotification ~= nil
                        and self:getOwnerFarmId() == g_currentMission:getFarmId() then
                    g_currentMission.hud:addSideNotification({1, 1, 1, 1}, notEnoughMoneyText)
                end
            end
            local resultTextKey = result ~= nil and RMS_FluidWorkshop.RESULT_TEXT_KEYS[result] or nil
            resultTextKey = resultTextKey or RMS_FluidWorkshop.RESULT_TEXT_KEYS.INVALID
            local failedServiceMessage = string.format(
                g_i18n:getText("rms_spec_next_planned_service_failed_notification"),
                g_i18n:getText(nextWork),
                g_i18n:getText(resultTextKey)
            )
            log_dbg("Planned service transaction refused:", tostring(result))
            RMS_VehicleChangeStatusEvent.send(self, maintenanceCompletedText .. ". " .. failedServiceMessage, lastEntry)
        end
    else
        spec.currentState = states.READY
        RMS_VehicleChangeStatusEvent.send(self, maintenanceCompletedText, lastEntry)
    end
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
    local optionThree = spec.serviceOptionThree
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
    self:addEntryToMaintenanceLog(serviceType, optionOne, optionTwo, optionThree, spec.pendingServicePrice, false, spec.pendingServiceInvoice)

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
    spec.plannedState = states.READY
    spec.currentState = states.READY
    resetPendingServiceProgress(spec)
    spec.serviceOptionOne = nil
    spec.serviceOptionTwo = nil
    spec.serviceOptionThree = false

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

---Returns how many hours the hour meter shows for one hour of the engine
local function getHourMeterCoefficient()
    return g_modIsLoaded["FS25_ingameTimeOperatingHours"] and getSafeMissionTimeScale() or 1
end

---Tells how much faster than normal the machine has worn, and from what
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
-- @param string maintenanceType service status constant
-- @param string? optionOne first service option
-- @param string? optionTwo second service option
-- @param boolean? optionThree third service option
-- @param float price service price
-- @param boolean isCompleted false when the service was cancelled
-- @param table? invoice invoice lines charged for the service
function RealisticMechanicalSystems:addEntryToMaintenanceLog(maintenanceType, optionOne, optionTwo, optionThree, price, isCompleted, invoice)
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
        price = price ~= nil and price or self:getServicePrice(maintenanceType, optionOne, optionTwo, optionThree),
        location = spec.workshopType,
        date = { 
            day = env.currentDayInPeriod or 1, 
            month = env.currentPeriod, 
            year = env.currentYear 
        },

        optionOne = optionOne,
        optionTwo = optionTwo or "NONE",
        optionThree = optionThree,
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
-- @param table? entry maintenance log entry
-- @return boolean hasReport true when a report is attached
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
-- @param table? entry maintenance log entry
-- @return boolean isComplete true for a complete inspection
function RealisticMechanicalSystems.getIsCompleteReport(entry)
    return entry.optionOne == RealisticMechanicalSystems.INSPECTION_TYPES.COMPLETE or entry.type == RealisticMechanicalSystems.STATUS.OVERHAUL
end

local REPORT_VALIDITY_SHARE = 0.5

---Tells how old a report is in work hours, and whether it still holds
local function getReportAge(vehicle, report)
    local hours = math.max(getRealOperatingHours(vehicle) - report.conditionData.operatingHours, 0)
    local isOutdated = hours >= vehicle:getServiceReferenceInterval() * REPORT_VALIDITY_SHARE
    local reported = report.conditionData.activeBreakdowns
    for id, breakdown in pairs(vehicle:getActiveBreakdowns()) do
        isOutdated = isOutdated or (breakdown.isVisible and not (reported[id] ~= nil and reported[id].isVisible))
    end
    return hours * getHourMeterCoefficient(), isOutdated
end

---Returns the report the screens read their figures from
-- @param boolean? forService true to read the service level
-- @return table? report log entry, nil when the vehicle was never inspected
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

-- @return table? report log entry, nil when no complete inspection measured them
-- @return float? hours work hours since it
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
-- @return float? condition recorded condition
-- @return boolean isComplete true when the report holds measures
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
-- @return float? service recorded service level
-- @return boolean isComplete true when the report holds measures
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
-- @return boolean isOutdated true when the report no longer describes the machine
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
-- @return table? date maintenance date
function RealisticMechanicalSystems:getLastMaintenanceDate()
    local spec = self.spec_RealisticMechanicalSystems
    if not spec or not spec.maintenanceLog or #spec.maintenanceLog == 0 then
        return 0
    end

    for i = #spec.maintenanceLog, 1, -1 do
        local entry = spec.maintenanceLog[i]
        if entry.type == RealisticMechanicalSystems.STATUS.MAINTENANCE or entry.type == RealisticMechanicalSystems.STATUS.OVERHAUL then
            return entry.date
        end
    end
end

---Returns the service reference interval the player selected
function RealisticMechanicalSystems:getServiceReferenceInterval()
    local spec = self.spec_RealisticMechanicalSystems
    return (spec.baseServiceLevel - RMS_Config.CORE.SERVICE_EXPIRED_THRESHOLD) / RMS_Config.CORE.BASE_SERVICE_WEAR
end

---Returns the service clocks of the circuits present, a common sump once
function RealisticMechanicalSystems:getServiceClocks()
    local spec = self.spec_RealisticMechanicalSystems
    if spec.fluidCapacityVersion ~= nil and spec.serviceClocks ~= nil and spec.serviceClocksCapacityVersion == spec.fluidCapacityVersion
        and spec.serviceClocksCapacities == spec.fluidCapacities
        and spec.serviceClocksFilename == self.configFileName then return spec.serviceClocks end
    local referenceHours = RMS_Config.SERVICE_REFERENCE_HOURS
    local clocks, bySump = {}, {}
    for _, definition in ipairs(RealisticMechanicalSystems.SERVICE_CLOCKS) do
        local limits = RMS_Config.SERVICE_PROGRAM[definition.key]
        for sump in pairs(getServiceClockSumps(self, definition)) do
            local clock = bySump[sump]
            if clock == nil then
                clock = RMS_Utils.shallowCopy(definition)
                clock.intervalFactor = limits.hours ~= nil and limits.hours / referenceHours or nil
                clock.months = limits.months
                clock.circuits = {sump}
                clock.systems = RMS_Utils.shallowCopy(definition.systems)
                bySump[sump] = clock
                table.insert(clocks, clock)
            else
                if limits.hours ~= nil then
                    clock.intervalFactor = math.min(clock.intervalFactor or math.huge, limits.hours / referenceHours)
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
    return clocks
end

---Returns elapsed hourly progress and its limit in the hour meter's units.
function RealisticMechanicalSystems:getServiceClockHours(clock)
    if clock == nil then return 0, 0 end
    local spec = self.spec_RealisticMechanicalSystems
    local coefficient = getHourMeterCoefficient()
    if clock.intervalFactor == nil then return 0, math.huge end
    local interval = self:getServiceReferenceInterval() * clock.intervalFactor * coefficient
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

---
function RealisticMechanicalSystems:getNextServiceClock()
    local schedule = self:getServiceSchedule()
    if schedule == nil then return nil, 0, 0 end
    return schedule.clock, schedule.used, schedule.interval
end

---
function RealisticMechanicalSystems:getServiceCountdown()
    local _, used, interval = self:getNextServiceClock()
    return used, interval
end

---
function RealisticMechanicalSystems:getDueMaintenanceType()
    local schedule = self:getServiceSchedule()
    return schedule ~= nil and schedule.maintenanceType or RealisticMechanicalSystems.MAINTENANCE_TYPES.STANDARD
end

---
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
-- @param string maintenanceType maintenance type
-- @return float hours interval in the hour meter's units
function RealisticMechanicalSystems:getMaintenanceLevelInterval(maintenanceType)
    local held, programmed = math.huge, math.huge
    for _, definition in ipairs(RealisticMechanicalSystems.SERVICE_CLOCKS) do
        if RealisticMechanicalSystems.MAINTENANCE_TYPES[definition.maintenanceType] == maintenanceType then
            local hours = RMS_Config.SERVICE_PROGRAM[definition.key].hours
            programmed = math.min(programmed, hours)
            if next(getServiceClockSumps(self, definition)) ~= nil then
                held = math.min(held, hours)
            end
        end
    end
    return self:getServiceReferenceInterval() * (held < math.huge and held or programmed)
        / RMS_Config.SERVICE_REFERENCE_HOURS * getHourMeterCoefficient()
end

---Returns the options of the newest service
-- @return string? optionOne first service option
-- @return string? optionTwo second service option
-- @return boolean? optionThree third service option
function RealisticMechanicalSystems:getLastServiceOptions()
    local spec = self.spec_RealisticMechanicalSystems
    if not spec or not spec.maintenanceLog or #spec.maintenanceLog == 0 then
        return RealisticMechanicalSystems.INSPECTION_TYPES.STANDARD, "NONE", false
    else
        local lastEntry = spec.maintenanceLog[#spec.maintenanceLog]
        return lastEntry.optionOne, lastEntry.optionTwo, lastEntry.optionThree
    end
end

---Counts the completed overhauls in the maintenance log
-- @return integer count number of overhauls
function RealisticMechanicalSystems:getOverhaulPerformedCount()
    local spec = self.spec_RealisticMechanicalSystems
    if not spec or not spec.maintenanceLog or #spec.maintenanceLog == 0 then
        return 0
    end
    local count = 0
    for i = #spec.maintenanceLog, 1, -1 do
        local entry = spec.maintenanceLog[i]
        if entry.type == RealisticMechanicalSystems.STATUS.OVERHAUL  then
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
-- @param integer index plan index
-- @return integer months age limit in months
-- @return integer hours hour meter limit, whole hours of play
function RealisticMechanicalSystems.getWarrantyPlan(index)
    local plan = RealisticMechanicalSystems.WARRANTY_PLANS[index]
    return plan.months, math.floor(plan.hours / (RMS_Config.CORE.BASE_SYSTEMS_WEAR * RMS_Config.CORE.MACHINE_LIFE_HOURS) + 0.5)
end

function RealisticMechanicalSystems:getWarrantyLimits()
    return RealisticMechanicalSystems.getWarrantyPlan(self.spec_RealisticMechanicalSystems.warrantyPlan)
end

---Tells whether the service of a fault's system is overdue
-- @param string breakdownId breakdown id
-- @return boolean isOverdue true past the hours or the months of a service of that system
function RealisticMechanicalSystems:getIsWarrantyServiceOverdue(breakdownId)
    local system = RMS_Utils.getSystemKey(RealisticMechanicalSystems.SYSTEMS, RMS_Breakdowns.BreakdownRegistry[breakdownId].system)
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

---Tells whether the warranty pays for one fault or the selected faults
-- @param string? repairType repair type, replacement when nil
-- @param string? partType part type, original when nil
-- @param string workshopType workshop type
-- @param string? breakdownId one fault, nil for the faults selected
-- @return boolean covered true when the warranty pays
-- @return string reason own, options, lease, overdue, part, factory, expired or partial
function RealisticMechanicalSystems:isWarrantyRepairCovered(repairType, partType, workshopType, breakdownId)
    local R, spec = RealisticMechanicalSystems, self.spec_RealisticMechanicalSystems
    if workshopType == R.WORKSHOP.OWN then return false, "own" end
    if (partType or R.PART_TYPES.OEM) ~= R.PART_TYPES.OEM
        or (repairType or R.REPAIR_TYPES.MEDIUM) ~= R.REPAIR_TYPES.MEDIUM then return false, "options" end
    if self.propertyState == VehiclePropertyState.LEASED then return false, "lease" end
    if breakdownId ~= nil then
        local fault = self:getActiveBreakdowns()[breakdownId]
        if fault ~= nil and fault.warrantyServiceOverdue then return false, "overdue" end
        local expiry = spec.partWarranty[breakdownId]
        if expiry ~= nil and self.age < expiry then return true, "part" end
    end
    local months, hours = self:getWarrantyLimits()
    local factory = self.age < months and R.getRealOperatingHours(self) < hours
    if breakdownId ~= nil then return factory, factory and "factory" or "expired" end
    local selected, covered = 0, 0
    for id, fault in pairs(self:getActiveBreakdowns()) do
        if isBreakdownSelectedForPlayerRepair(id, fault, repairType or R.REPAIR_TYPES.MEDIUM) then
            selected = selected + 1
            if self:isWarrantyRepairCovered(repairType, partType, workshopType, id) then covered = covered + 1 end
        end
    end
    if selected > 0 then
        if covered == selected then return true, factory and "factory" or "part" end
        return false, covered > 0 and "partial" or "expired"
    end
    return factory, factory and "factory" or "expired"
end

---Records fitted-part cover; none for a filter, same expiry on exchange
-- @param table vehicle vehicle
-- @param string partId breakdown id of the part
-- @param string partType part type fitted
-- @param boolean isPaid false when the warranty or the lease paid the part
-- @param integer? donorHours work hours of the offered donor machine
function RealisticMechanicalSystems.recordPartWarranty(vehicle, partId, partType, isPaid, donorHours)
    local R, spec = RealisticMechanicalSystems, vehicle.spec_RealisticMechanicalSystems
    if RMS_Consumables.getFilterOfBreakdown(partId) ~= nil then return end
    if partType == R.PART_TYPES.USED and donorHours ~= nil and R.getIsUsedPartGuaranteed(partId, donorHours) then
        if isPaid then spec.usedPartWarranty[partId] = vehicle.age + 3 end
    else
        spec.usedPartWarranty[partId] = nil
    end
    if spec.workshopType ~= R.WORKSHOP.DEALER or partType ~= R.PART_TYPES.OEM then
        spec.partWarranty[partId] = nil
    elseif isPaid then
        spec.partWarranty[partId] = vehicle.age + 12
    end
end

---Draws the donor machine of a fault's used part; a filter has none
-- @param string breakdownId breakdown id
-- @return integer? hours work hours of the donor machine
function RealisticMechanicalSystems.drawUsedPartDonorHours(breakdownId)
    if RMS_Consumables.getFilterOfBreakdown(breakdownId) == nil then
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
    local expiry = self.spec_RealisticMechanicalSystems.usedPartWarranty[breakdownId]
    return expiry ~= nil and self.age < expiry
end

---Sums up the used parts offered for the faults of a repair
-- @param integer repairType repair type
-- @return integer? minimum lowest donor, game meter hours
-- @return integer? maximum highest donor, game meter hours
-- @return integer count faults with a used part offer
-- @return integer guaranteed offers with salvage cover
function RealisticMechanicalSystems:getUsedPartOfferSummary(repairType)
    local minimum, maximum, count, guaranteed = nil, nil, 0, 0
    for id, fault in pairs(self:getActiveBreakdowns()) do
        if fault.usedPartHours ~= nil and isBreakdownSelectedForPlayerRepair(id, fault, repairType) then
            local hours = RealisticMechanicalSystems.getUsedPartMeterHours(fault.usedPartHours)
            minimum, maximum = math.min(minimum or hours, hours), math.max(maximum or hours, hours)
            count = count + 1
            if RealisticMechanicalSystems.getIsUsedPartGuaranteed(id, fault.usedPartHours) then guaranteed = guaranteed + 1 end
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
-- @param string workshopType workshop type
-- @return boolean isCovered true when the lease pays
function RealisticMechanicalSystems:isLeaseMaintenanceCovered(workshopType)
    return self.propertyState == VehiclePropertyState.LEASED
        and (workshopType == RealisticMechanicalSystems.WORKSHOP.DEALER or workshopType == RealisticMechanicalSystems.WORKSHOP.MOBILE)
end

---Returns a real price in game euros, rounded up to ten
local function getBilledPrice(realPrice)
    local cents = math.floor(RMS_Utils.getGamePrice(realPrice) * 100 + 0.5)
    return math.ceil(cents / 1000) * 10
end

---Returns the labour price of a job at the workshop's rate
local function getLabourPrice(vehicle, hours, workshopType)
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

---Returns the price of repairing a breakdown at a stage
local function getBreakdownLinePrice(vehicle, breakdownId, stage, repairType, partType, workshopType)
    local C = RMS_Config.MAINTENANCE
    local workshopKey = RMS_Utils.getKeyByValue(RealisticMechanicalSystems.WORKSHOP, workshopType)
    local partsPrice = getBilledPrice(getStagePartsShare(vehicle, breakdownId, stage) / 100 * C.REPAIR_REFERENCE_VALUE
        * getSizeScale(vehicle, C.PARTS_POWER_EXPONENT, "parts")
        * C.PARTS_PRICE_MULTIPLIERS[RMS_Utils.getKeyByValue(RealisticMechanicalSystems.PART_TYPES, partType)]
        * C.REPAIR_PRICE_MULTIPLIERS[RMS_Utils.getKeyByValue(RealisticMechanicalSystems.REPAIR_TYPES, repairType)]
        * RMS_Config.WORKSHOP.PRICE_MULTIPLIERS[workshopKey])
    return partsPrice + getLabourPrice(vehicle, RealisticMechanicalSystems.getRepairLabourHours(vehicle, breakdownId, repairType), workshopType)
end

---Returns the price of a service
-- @param string? maintenanceType service status constant
-- @param string? optionOne first service option
-- @param string? optionTwo second service option
-- @param boolean? optionThree third service option
-- @param string? workshopTypeOverride workshop type replacing the stored one
-- @param boolean? allBreakdowns true to price every breakdown, not only the selected ones
-- @return float price service price
function RealisticMechanicalSystems:getServicePrice(maintenanceType, optionOne, optionTwo, optionThree, workshopTypeOverride, allBreakdowns)
    if not maintenanceType then
        maintenanceType = self.spec_RealisticMechanicalSystems.currentState
    end
    if maintenanceType == RealisticMechanicalSystems.STATUS.BODYWORK then
        return RMS_Bodywork.getPrice(self, optionOne or self.spec_RealisticMechanicalSystems.serviceOptionOne,
            workshopTypeOverride or self.spec_RealisticMechanicalSystems.workshopType) or 0
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
        return getLabourPrice(self, RealisticMechanicalSystems.getServiceWorkHours(self, maintenanceType, optionOne), workshopType)

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
        overhaulPrice = overhaulPrice + getLabourPrice(self,
            RealisticMechanicalSystems.getServiceWorkHours(self, maintenanceType, optionOne, optionTwo, optionThree), workshopType)
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
-- @param string optionOne maintenance type
-- @param string optionTwo part type
-- @param string? workshopTypeOverride workshop type replacing the stored one
-- @param boolean? isFullPrice true for what the dealer bills, the lease left aside
-- @return table lines labour and filters; no labour in farm workshop
function RealisticMechanicalSystems:getMaintenancePriceLines(optionOne, optionTwo, workshopTypeOverride, isFullPrice)
    local C = RMS_Config.MAINTENANCE
    local key = RMS_Utils.getKeyByValue(RealisticMechanicalSystems.MAINTENANCE_TYPES, optionOne)
    local partKey = RMS_Utils.getKeyByValue(RealisticMechanicalSystems.PART_TYPES, optionTwo)
    local workshopType = workshopTypeOverride or self.spec_RealisticMechanicalSystems.workshopType
    local billedShare = (not isFullPrice and self:isLeaseMaintenanceCovered(workshopType)) and 0 or 1
    local lines = {}
    if workshopType ~= RealisticMechanicalSystems.WORKSHOP.OWN then
        table.insert(lines, { kind = "labour", price = billedShare * getLabourPrice(self,
            RealisticMechanicalSystems.getServiceWorkHours(self, RealisticMechanicalSystems.STATUS.MAINTENANCE, optionOne), workshopType) })
    end
    table.insert(lines, { kind = "filters", price = billedShare * getBilledPrice(C.MAINTENANCE_FILTER_PRICES[key]
        * getSizeScale(self, C.PARTS_POWER_EXPONENT, "filters") * C.PARTS_PRICE_MULTIPLIERS[partKey]) })
    return lines
end

---Returns the price of each breakdown a repair puts right
-- @param string? optionOne repair type
-- @param string? optionTwo part type
-- @param string? workshopTypeOverride workshop type replacing the stored one
-- @param boolean? allBreakdowns true to price every breakdown, not only the selected ones
-- @return table lines breakdownId and price of each repaired breakdown, sorted by id
function RealisticMechanicalSystems:getRepairPriceLines(optionOne, optionTwo, workshopTypeOverride, allBreakdowns)
    local workshopType = workshopTypeOverride or self.spec_RealisticMechanicalSystems.workshopType
    local lines = {}

    for id, breakdown in pairs(self:getActiveBreakdowns()) do
        if isBreakdownSelectedForPlayerRepair(id, breakdown, optionOne) or (allBreakdowns and getIsSelectableBreakdown(id)) then
            if RMS_Breakdowns.BreakdownRegistry[id] ~= nil then
                local isCovered, reason = self:isWarrantyRepairCovered(optionOne, optionTwo, workshopType, id)
                if RealisticMechanicalSystems.getIsUsedPartWarrantyCovered(self, id, optionOne, optionTwo) then
                    isCovered, reason = true, "used"
                end
                local linePrice = self:getBreakdownRepairPrice(id, breakdown.stage, optionTwo, workshopType, optionOne)
                table.insert(lines, { breakdownId = id, price = linePrice, warranty = isCovered, warrantyReason = reason })
            end
        end
    end

    table.sort(lines, function(a, b)
        return a.breakdownId < b.breakdownId
    end)
    return lines
end

---Returns the price of repairing one breakdown at a stage with a part type
-- @param string breakdownId breakdown id
-- @param integer breakdownStage breakdown stage
-- @param string partType part type
-- @param string? workshopTypeOverride workshop type replacing the stored one
-- @return float price repair price
function RealisticMechanicalSystems:getBreakdownRepairPrice(breakdownId, breakdownStage, partType, workshopTypeOverride, repairType)
    local registryEntry = RMS_Breakdowns.BreakdownRegistry[breakdownId]
    if registryEntry == nil or registryEntry.stages[breakdownStage] == nil then
        return 0
    end

    local workshopType = workshopTypeOverride or self.spec_RealisticMechanicalSystems.workshopType
    repairType = repairType or RealisticMechanicalSystems.REPAIR_TYPES.MEDIUM
    if RealisticMechanicalSystems.getIsUsedPartWarrantyCovered(self, breakdownId, repairType, partType) then
        return getLabourPrice(self, RealisticMechanicalSystems.getRepairLabourHours(self, breakdownId, repairType), workshopType)
    end
    if self:isWarrantyRepairCovered(repairType, partType, workshopType, breakdownId) then
        if workshopType == RealisticMechanicalSystems.WORKSHOP.MOBILE then
            local hours = RealisticMechanicalSystems.getRepairLabourHours(self, breakdownId, repairType)
            return math.max(getLabourPrice(self, hours, workshopType)
                - getLabourPrice(self, hours, RealisticMechanicalSystems.WORKSHOP.DEALER), 0)
        end
        return 0
    end
    return getBreakdownLinePrice(self, breakdownId, breakdownStage, repairType, partType, workshopType)
end

-- @param string partId part id
-- @return float price replacement price
function RealisticMechanicalSystems:getPartReplacementPrice(partId)
    return getBreakdownLinePrice(self, partId, 1, RealisticMechanicalSystems.REPAIR_TYPES.MEDIUM, RealisticMechanicalSystems.PART_TYPES.OEM,
        RealisticMechanicalSystems.WORKSHOP.DEALER)
end

---Returns the duration of a service in real time
-- @param string? maintenanceType service status constant
-- @param string? optionOne first service option
-- @param string? optionTwo second service option
-- @param boolean? optionThree third service option
-- @param string? workshopTypeOverride workshop type replacing the stored one
-- @return float duration service duration in ms
function RealisticMechanicalSystems:getServiceDuration(maintenanceType, optionOne, optionTwo, optionThree, workshopTypeOverride)
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
        local totalDurationMs = getServiceWorkDurationMs(self, maintenanceType, optionOne, optionTwo, optionThree)
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
        local currentHour = (g_currentMission.environment.dayTime / 3600000) % 24

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
-- @param string? maintenanceType service status constant
-- @param string? optionOne first service option
-- @param string? optionTwo second service option
-- @param boolean? optionThree third service option
-- @param string? workshopTypeOverride workshop type replacing the stored one
-- @return float finishTime hour of the day the service ends
-- @return integer daysToAdd whole days crossed before it ends
function RealisticMechanicalSystems:getServiceFinishTime(maintenanceType, optionOne, optionTwo, optionThree, workshopTypeOverride)
    local spec = self.spec_RealisticMechanicalSystems

    if not maintenanceType then maintenanceType = spec.currentState end
    local savedOptionOne, savedOptionTwo, savedOptionThree = self:getLastServiceOptions()
    if optionOne == nil then optionOne = savedOptionOne end
    if optionTwo == nil then optionTwo = savedOptionTwo end
    if optionThree == nil then optionThree = savedOptionThree end

    if maintenanceType == RealisticMechanicalSystems.STATUS.READY then
        return 0
    end

    local totalCalendarDuration = RealisticMechanicalSystems.getServiceDuration(self, maintenanceType, optionOne, optionTwo, optionThree, workshopTypeOverride)

    if totalCalendarDuration <= 0 then
        local currentTime = (g_currentMission.environment.dayTime / 3600000) % 24
        return currentTime, 0
    end

    local currentDayTime = g_currentMission.environment.dayTime / 3600000
    local finishDayTimeAbsolute = currentDayTime + totalCalendarDuration

    local currentDay = math.floor(currentDayTime / 24)
    local finishDay = math.floor(finishDayTimeAbsolute / 24)
    
    local finishTimeOfDay = finishDayTimeAbsolute % 24
    local daysToAdd = finishDay - currentDay
    
    return finishTimeOfDay, daysToAdd
end
