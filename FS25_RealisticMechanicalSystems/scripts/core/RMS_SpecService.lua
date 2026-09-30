-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---Workshop services on a vehicle: inspection, maintenance, repair and overhaul, with their prices and durations

local log_dbg = RMS_Utils ~= nil and RMS_Utils.createLogger ~= nil
    and RMS_Utils.createLogger("[RMS_SPEC]")
    or function(...) end
local getSafeMissionTimeScale = RealisticMechanicalSystems.getSafeMissionTimeScale

---Tells whether a visible breakdown was picked for this repair type, quick fix needing it active
-- @param string breakdownId breakdown id
-- @param table breakdown active breakdown entry
-- @param string? optionOne repair type
-- @return boolean isSelected true when the repair covers it
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
-- @param string breakdownId breakdown id
-- @return boolean isSelectable true when the player can pick it
local function getIsSelectableBreakdown(breakdownId)
    local breakdownDef = RMS_Breakdowns.BreakdownRegistry[breakdownId]
    if breakdownDef == nil or breakdownDef.isSelectable ~= true then
        return false
    end
    return true
end

---Clears every pending service field of the spec
-- @param table spec vehicle spec
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
    spec.pendingPreventiveSystemStressStart = {}
    spec.pendingPreventiveSystemStressTarget = {}
    spec.pendingOverhaulSystemStart = {}
    spec.pendingOverhaulSystemTarget = {}
    spec.pendingOverhaulSystemStressStart = {}
    spec.pendingOverhaulSystemStressTarget = {}
    spec.pendingRepairSystemStressStart = {}
    spec.pendingRepairSystemStressTarget = {}
    spec.pendingRepairSystemStressStartRatio = {}
    spec.pendingFluidRequirements = {}
end

---Interpolates the stress of the listed systems between their start and target values
-- @param table? spec vehicle spec
-- @param table? startMap stress at the start of the service
-- @param table? targetMap stress at the end of the service
-- @param float ratio service progress ratio
local function applyPendingSystemStressInterpolation(spec, startMap, targetMap, ratio)
    if spec == nil or spec.systems == nil then
        return false
    end

    if startMap == nil or targetMap == nil then
        return false
    end

    for systemKey, startStress in pairs(startMap) do
        local systemData = spec.systems[systemKey]
        local targetStress = targetMap[systemKey]
        if systemData ~= nil and targetStress ~= nil then
            local interpolatedStress = startStress + (targetStress - startStress) * ratio
            systemData.stress = math.max(interpolatedStress, 0)
        end
    end
end

---Returns the sumps a service clock covers on the vehicle, those holding oil
-- @param table vehicle vehicle
-- @param table clock service clock definition
-- @return table sumps set of sump circuits, empty when the vehicle holds none of its oils
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

---Collects the service clocks a service resets, those whose every oil it changes
-- @param table vehicle vehicle
-- @param table requirements fluid work of the service
-- @return table startLevels clock levels at the start of the service, by clock key
-- @return table targetLevels clock levels the service restores, by clock key
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

---Brings the service clocks the running service resets from their start level toward the restored one
-- @param table spec vehicle spec
-- @param float ratio service progress ratio
local function applyPendingServiceClockInterpolation(spec, ratio)
    for _, clock in ipairs(RealisticMechanicalSystems.SERVICE_CLOCKS) do
        local startLevel = spec.pendingServiceClockStart[clock.key]
        local targetLevel = spec.pendingServiceClockTarget[clock.key]
        if startLevel ~= nil and targetLevel ~= nil then
            spec[clock.levelKey] = startLevel + (targetLevel - startLevel) * ratio
        end
    end
end

---Interpolates the stress of the systems covered by a preventive maintenance
-- @param table? spec vehicle spec
-- @param float ratio service progress ratio
local function applyPendingPreventiveStressInterpolation(spec, ratio)
    if spec == nil then
        return false
    end

    applyPendingSystemStressInterpolation(spec, spec.pendingPreventiveSystemStressStart, spec.pendingPreventiveSystemStressTarget, ratio)
end

---Interpolates the stress of the systems covered by an overhaul
-- @param table? spec vehicle spec
-- @param float ratio service progress ratio
local function applyPendingOverhaulStressInterpolation(spec, ratio)
    if spec == nil then
        return false
    end

    applyPendingSystemStressInterpolation(spec, spec.pendingOverhaulSystemStressStart, spec.pendingOverhaulSystemStressTarget, ratio)
end

---Records the stress a repair will remove from a system, drawn once with a random spread
-- @param table? spec vehicle spec
-- @param string? systemKey system key
-- @param string optionOne repair type
local function markRepairStressReduction(spec, systemKey, optionOne)
    if spec == nil or spec.systems == nil or systemKey == nil or systemKey == "" then
        return false
    end

    local systemData = spec.systems[systemKey]
    if systemData == nil then
        return
    end

    local optionOneKey = RMS_Utils.getKeyByValue(RealisticMechanicalSystems.REPAIR_TYPES, optionOne)

    spec.pendingRepairSystemStressStart = spec.pendingRepairSystemStressStart or {}
    spec.pendingRepairSystemStressTarget = spec.pendingRepairSystemStressTarget or {}
    spec.pendingRepairSystemStressStartRatio = spec.pendingRepairSystemStressStartRatio or {}

    if spec.pendingRepairSystemStressTarget[systemKey] == nil then
        spec.pendingRepairSystemStressStart[systemKey] = math.max(tonumber(systemData.stress) or 0, 0)
        spec.pendingRepairSystemStressTarget[systemKey] = math.max(RMS_Config.MAINTENANCE.REPAIR_REMAINING_STRESS_RATIO[optionOneKey] * systemData.stress * (0.9 + math.random() * 0.2), 0)
        local totalTime = math.max(tonumber(spec.pendingProgressTotalTime) or 0, 0.0001)
        spec.pendingRepairSystemStressStartRatio[systemKey] = math.min(math.max((tonumber(spec.pendingProgressElapsedTime) or 0) / totalTime, 0), 1)
    end
end

---Interpolates the repair stress reduction, each system starting from the ratio it was booked at
-- @param table? spec vehicle spec
-- @param float ratio service progress ratio
local function applyPendingRepairStressInterpolation(spec, ratio)
    if spec == nil or spec.systems == nil then
        return
    end

    if spec.pendingRepairSystemStressStart == nil
        or spec.pendingRepairSystemStressTarget == nil
        or spec.pendingRepairSystemStressStartRatio == nil then
        return
    end

    for systemKey, startStress in pairs(spec.pendingRepairSystemStressStart) do
        local systemData = spec.systems[systemKey]
        local targetStress = spec.pendingRepairSystemStressTarget[systemKey]
        local startRatio = tonumber(spec.pendingRepairSystemStressStartRatio[systemKey]) or 0
        if systemData ~= nil and targetStress ~= nil then
            local localRatio = 1
            if startRatio < 1 then
                localRatio = math.min(math.max((ratio - startRatio) / (1 - startRatio), 0), 1)
            end
            local interpolatedStress = startStress + (targetStress - startStress) * localRatio
            systemData.stress = math.max(interpolatedStress, 0)
        end
    end
end

---Picks the configured number of systems with the shortest mtbf and returns their stress targets
-- @param table? vehicle vehicle
-- @return table startMap stress at the start of the service
-- @return table targetMap stress at the end of the service
local function collectPreventiveMaintenanceStressTargets(vehicle)
    local spec = vehicle ~= nil and vehicle.spec_RealisticMechanicalSystems or nil
    if spec == nil or type(spec.systems) ~= "table" then
        return {}, {}
    end

    local config = RMS_Config.MAINTENANCE or {}
    local systemsCount = math.max(math.floor(tonumber(config.MAINTENANCE_PREVENTIVE_SYSTEMS_COUNT) or 0), 0)
    if systemsCount <= 0 then
        return {}, {}
    end

    local targetMultiplier = math.clamp(tonumber(config.MAINTENANCE_PREVENTIVE_STRESS_REMOVE_MULTIPLIER) or 0, 0, 1)
    local candidates = {}

    for systemKey, systemData in pairs(spec.systems) do
        if type(systemData) == "table" and systemData.enabled ~= false then
            local condition = math.clamp(tonumber(systemData.condition) or spec.conditionLevel or 1.0, 0.001, 1.0)
            local currentStress = math.max(tonumber(systemData.stress) or 0, 0)
            local targetStress = math.min(currentStress, condition * targetMultiplier)
            local removableStress = currentStress - targetStress
            if removableStress > 0.0001 then
                table.insert(candidates, {
                    systemKey = systemKey,
                    startStress = currentStress,
                    targetStress = targetStress,
                    mtbf = RMS_Utils.getEstimatedMTBF(condition, currentStress),
                    removableStress = removableStress
                })
            end
        end
    end

    table.sort(candidates, function(a, b)
        if a.mtbf ~= b.mtbf then
            return a.mtbf < b.mtbf
        end
        if a.removableStress ~= b.removableStress then
            return a.removableStress > b.removableStress
        end
        return tostring(a.systemKey) < tostring(b.systemKey)
    end)

    local startMap = {}
    local targetMap = {}
    local selectedCount = math.min(systemsCount, #candidates)
    for i = 1, selectedCount do
        local candidate = candidates[i]
        startMap[candidate.systemKey] = candidate.startStress
        targetMap[candidate.systemKey] = candidate.targetStress
    end

    return startMap, targetMap
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
    local totalTimeMs = 0
    local repairPrice = nil

    if vehicleState ~= states.READY or (spec.maintenanceTimer or 0) ~= 0 then
        return false
    end

    if RMS_Main ~= nil
        and RMS_Main.isWorkshopTypeOpen ~= nil
        and not RMS_Main:isWorkshopTypeOpen(workshopType) then
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

    if self.spec_enterable ~= nil and self.spec_enterable.setIsTabbable ~= nil then
        self.spec_enterable:setIsTabbable(false)
    end

    if type == states.OVERHAUL
        and optionOne == RealisticMechanicalSystems.OVERHAUL_TYPES.PARTIAL
        and optionTwo ~= nil
        and RMS_Utils.getEffectiveSystemWeight(self, optionTwo, RealisticMechanicalSystems.SYSTEMS) <= 0 then
        log_dbg(string.format("Skipping partial overhaul for %s: invalid or disabled target system '%s'", self:getFullName(), tostring(optionTwo)))
        return false
    end

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
            if C.INSTANT_INSPECTION and optionOne == RealisticMechanicalSystems.INSPECTION_TYPES.VISUAL then
                optionOne = RealisticMechanicalSystems.INSPECTION_TYPES.STANDARD
                spec.serviceOptionOne = optionOne
            end

            local key = RMS_Utils.getKeyByValue(RealisticMechanicalSystems.INSPECTION_TYPES, optionOne)
            if C.INSTANT_INSPECTION then
                totalTimeMs = 1000
            else
                totalTimeMs = C.INSPECTION_TIME * C.INSPECTION_TIME_MULTIPLIERS[key]
            end
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
        local key = RMS_Utils.getKeyByValue(RealisticMechanicalSystems.MAINTENANCE_TYPES, optionOne)
        totalTimeMs = C.INSTANT_MAINTENANCE_REPAIR and 1000
            or C.MAINTENANCE_TIME * C.MAINTENANCE_TIME_MULTIPLIERS[key]
        spec.pendingPreventiveSystemStressStart = {}
        spec.pendingPreventiveSystemStressTarget = {}

        if key == "PREVENTIVE" then
            spec.pendingPreventiveSystemStressStart, spec.pendingPreventiveSystemStressTarget = collectPreventiveMaintenanceStressTargets(self)
        end

        if self:hasBreakdown("MAINTENANCE_WITH_POOR_QUALITY_CONSUMABLES") then
            self:removeBreakdown("MAINTENANCE_WITH_POOR_QUALITY_CONSUMABLES")
        end
        repairPrice = self:getServicePrice(type, optionOne, optionTwo, optionThree)

    -- repair
    elseif type == states.REPAIR then
        local key = RMS_Utils.getKeyByValue(RealisticMechanicalSystems.REPAIR_TYPES, optionOne)
        local idsToRepair = {}
        for id, breakdown in pairs(self:getActiveBreakdowns()) do
            if isBreakdownSelectedForPlayerRepair(id, breakdown, optionOne) then
                table.insert(idsToRepair, id)
            end
        end

        spec.pendingRepairQueue = RMS_Utils.shallowCopy(idsToRepair)
        totalTimeMs = C.INSTANT_MAINTENANCE_REPAIR and #idsToRepair > 0 and 1000
            or C.REPAIR_TIME * C.REPAIR_TIME_MULTIPLIERS[key] * #idsToRepair
        repairPrice = self:getServicePrice(type, optionOne, optionTwo, optionThree)

    -- fluid top up
    elseif type == states.REFILL then
        totalTimeMs = C.REFILL_TIME
        repairPrice = self:getServicePrice(type, optionOne, optionTwo, optionThree)

    -- bodywork
    elseif type == states.BODYWORK then
        totalTimeMs = C.INSTANT_BODYWORK and 1000 or RMS_Bodywork.getDurationMs(self, optionOne) or 0
        repairPrice = RMS_Bodywork.getPrice(self, optionOne, workshopType)

    -- overhaul
    elseif type == states.OVERHAUL then
        local key = RMS_Utils.getKeyByValue(RealisticMechanicalSystems.OVERHAUL_TYPES, optionOne)
        totalTimeMs = C.OVERHAUL_TIME * C.OVERHAUL_TIME_MULTIPLIERS[key]
        local targetOverhaulSystemKey = nil
        if optionOne == RealisticMechanicalSystems.OVERHAUL_TYPES.PARTIAL then 
            local systemWeight = RMS_Utils.getEffectiveSystemWeight(self, optionTwo or "", RealisticMechanicalSystems.SYSTEMS)
            totalTimeMs = totalTimeMs * systemWeight
            targetOverhaulSystemKey = RMS_Utils.getSystemKey(RealisticMechanicalSystems.SYSTEMS, optionTwo)
            if (targetOverhaulSystemKey == nil or targetOverhaulSystemKey == "") and type(optionTwo) == "string" then
                targetOverhaulSystemKey = string.lower(optionTwo)
            end
        end

        if C.INSTANT_OVERHAUL then
            totalTimeMs = 1000
        end

        local desiredSystemTarget = C.OVERHAUL_CONDITION_TARGETS[key]
        spec.pendingOverhaulSystemStart = {}
        spec.pendingOverhaulSystemTarget = {}
        spec.pendingOverhaulSystemStressStart = {}
        spec.pendingOverhaulSystemStressTarget = {}

        for systemKey, systemData in pairs(spec.systems) do
            if optionOne ~= RealisticMechanicalSystems.OVERHAUL_TYPES.PARTIAL or systemKey == targetOverhaulSystemKey or optionTwo == systemData.name then
                local startCondition = math.clamp(tonumber(systemData.condition) or spec.conditionLevel or 1.0, 0.001, 1.0)
                local startStress = math.max(tonumber(systemData.stress) or 0, 0)
                local targetCondition = math.max(startCondition, desiredSystemTarget)
                spec.pendingOverhaulSystemStart[systemKey] = startCondition
                spec.pendingOverhaulSystemTarget[systemKey] = targetCondition
                spec.pendingOverhaulSystemStressStart[systemKey] = startStress
                spec.pendingOverhaulSystemStressTarget[systemKey] = 0
            end
        end

        if optionOne == RealisticMechanicalSystems.OVERHAUL_TYPES.PARTIAL and next(spec.pendingOverhaulSystemTarget) == nil then
            log_dbg(string.format("Skipping partial overhaul for %s: no valid system targets resolved for '%s'", self:getFullName(), tostring(optionTwo)))
            spec.currentState = states.READY
            spec.plannedState = states.READY
            spec.workshopType = workshopType
            spec.serviceOptionOne = nil
            spec.serviceOptionTwo = nil
            spec.serviceOptionThree = false
            resetPendingServiceProgress(spec)
            if self.spec_enterable ~= nil and self.spec_enterable.setIsTabbable ~= nil then
                self.spec_enterable:setIsTabbable(true)
            end
            return false
        end

        self:updateConditionLevel()
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
        local isInstantService = (type == states.INSPECTION and C.INSTANT_INSPECTION)
            or ((type == states.MAINTENANCE or type == states.REPAIR) and C.INSTANT_MAINTENANCE_REPAIR)
            or (type == states.BODYWORK and C.INSTANT_BODYWORK)
            or (type == states.OVERHAUL and C.INSTANT_OVERHAUL)
        local adjustedTotalTimeMs = (type == states.BODYWORK or isInstantService)
            and totalTimeMs or totalTimeMs / spec.maintainability
        spec.maintenanceTimer = adjustedTotalTimeMs
        spec.pendingProgressTotalTime = adjustedTotalTimeMs
        spec.pendingProgressElapsedTime = 0
        spec.pendingProgressStepIndex = 0
        log_dbg(string.format(
            '%s initiated for %s, will take %.2f seconds (%.2f seconds after reliability adjustment). Next planned state: %s',
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

---Repairs one breakdown, suspending it on a quick fix and possibly fitting a defective part
-- @param table vehicle vehicle
-- @param table spec vehicle spec
-- @param string? breakdownId breakdown id
-- @param string optionOne repair type
-- @param string optionTwo part type
-- @param string optionTwoKey part type key
local function processPendingRepairStep(vehicle, spec, breakdownId, optionOne, optionTwo, optionTwoKey)
    if breakdownId == nil or vehicle:getActiveBreakdowns()[breakdownId] == nil then
        return
    end

    table.insert(spec.pendingSelectedBreakdowns, breakdownId)

    local C = RMS_Config.MAINTENANCE
    local breakdownDef = RMS_Breakdowns.BreakdownRegistry[breakdownId]
    local systemName = breakdownDef ~= nil and breakdownDef.system or nil
    local systemKey = RMS_Utils.getSystemKey(RealisticMechanicalSystems.SYSTEMS, systemName)
    local systemData = (systemKey ~= nil and systemKey ~= "" and spec.systems ~= nil) and spec.systems[systemKey] or nil

    if optionOne == RealisticMechanicalSystems.REPAIR_TYPES.LOW then
        local random = math.random()
        local serviceScale = RMS_Config.CORE.REFERENCE_SERVICE_WEAR / RMS_Config.CORE.BASE_SERVICE_WEAR
        vehicle:suspendBreakdown(breakdownId, RMS_Config.CORE.REPEAT_BREAKDOWN_TIME * serviceScale * (random + 0.5))
    else
        local stage = vehicle:getActiveBreakdowns()[breakdownId].stage
        vehicle:removeBreakdown(breakdownId)
        if systemData ~= nil then
            markRepairStressReduction(spec, systemKey, optionOne)
        else
            log_dbg(string.format("Repair effect skipped: missing system mapping for breakdown '%s' (system='%s')", tostring(breakdownId), tostring(systemName)))
        end

        if optionTwo ~= RealisticMechanicalSystems.PART_TYPES.PREMIUM then
            local defectChance = C.PARTS_BREAKDOWN_CHANCES[optionTwoKey]
            if math.random() < defectChance then
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
end

---Advances the running service, consuming its step queue and interpolating the stress changes
-- @param float dt time since last call in ms
-- @param boolean? ignoreWorkshopHours true to advance independently of opening hours
function RealisticMechanicalSystems:processService(dt, ignoreWorkshopHours)
    local spec = self.spec_RealisticMechanicalSystems
    local states = RealisticMechanicalSystems.STATUS
    local vehicleState = self:getCurrentStatus()
    local C = RMS_Config.MAINTENANCE

    if vehicleState == states.READY
        or (not ignoreWorkshopHours
            and RMS_Main ~= nil
            and RMS_Main.isWorkshopTypeOpen ~= nil
            and not RMS_Main:isWorkshopTypeOpen(spec.workshopType)) then
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
                        local inspectionDetectionMul = 1.0
                        if serviceType == states.INSPECTION then
                            local optionOneKey = RMS_Utils.getKeyByValue(RealisticMechanicalSystems.INSPECTION_TYPES, optionOne)
                            inspectionDetectionMul = C.INSPECTION_DETECTION_CHANCE_MULTIPLIERS[optionOneKey] or 1.0
                        end
                        local chance = (breakdownDef.stages[breakdown.stage].detectionChance * inspectionDetectionMul) or 0
                        if math.random() < chance then
                            if breakdown.isActive or optionOne == RealisticMechanicalSystems.INSPECTION_TYPES.COMPLETE then
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

        if spec.pendingProgressTotalTime > 0 then
            local ratio = math.min(math.max(spec.pendingProgressElapsedTime / spec.pendingProgressTotalTime, 0), 1)
            applyPendingRepairStressInterpolation(spec, ratio)
        end
        self:updateConditionLevel()
    end

    if serviceType == states.MAINTENANCE and spec.pendingProgressTotalTime > 0 then
        local ratio = math.min(math.max(spec.pendingProgressElapsedTime / spec.pendingProgressTotalTime, 0), 1)
        applyPendingServiceClockInterpolation(spec, ratio)
        applyPendingPreventiveStressInterpolation(spec, ratio)

    elseif serviceType == states.OVERHAUL and spec.pendingProgressTotalTime > 0 then
        local ratio = math.min(math.max(spec.pendingProgressElapsedTime / spec.pendingProgressTotalTime, 0), 1)
        applyPendingServiceClockInterpolation(spec, ratio)
        local hasPerSystemTargets = spec.pendingOverhaulSystemStart ~= nil
            and next(spec.pendingOverhaulSystemStart) ~= nil
            and spec.pendingOverhaulSystemTarget ~= nil
            and next(spec.pendingOverhaulSystemTarget) ~= nil
        if hasPerSystemTargets then
            for systemKey, startCondition in pairs(spec.pendingOverhaulSystemStart) do
                local systemData = spec.systems[systemKey]
                local targetCondition = spec.pendingOverhaulSystemTarget[systemKey]
                if systemData ~= nil and targetCondition ~= nil then
                    local interpolatedCondition = startCondition + (targetCondition - startCondition) * ratio
                    systemData.condition = math.max(startCondition, interpolatedCondition)
                end
            end
            applyPendingOverhaulStressInterpolation(spec, ratio)
            self:updateConditionLevel()
        end
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

---Applies the final service result, writes the log entry and returns the vehicle to ready
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

    if serviceType ~= states.INSPECTION and serviceType ~= states.BODYWORK then
        local nominalCapacityAh = math.max(spec.batteryCapacityAh or 0, 1)
        local usableCapacityAh = math.max(
            nominalCapacityAh * RMS_Config.ELECTRICAL.BATTERY_USABLE_CAPACITY_FACTOR,
            0.01
        )
        local effectiveCapacityAh = math.max(usableCapacityAh * math.max(spec.batteryHealth or 0, 0.0001), 0.01)
        spec.batterySoc = 1.0
        spec.batteryChargeAh = effectiveCapacityAh
    end

    applyPendingServiceClockInterpolation(spec, 1)

    if serviceType == states.MAINTENANCE then
        for systemKey, targetStress in pairs(spec.pendingPreventiveSystemStressTarget or {}) do
            local systemData = spec.systems[systemKey]
            if systemData ~= nil then
                systemData.stress = math.max(tonumber(targetStress) or 0, 0)
            end
        end

        -- the hydraulic filter goes with the transmission oil
        if spec.pendingServiceClockTarget.transmission ~= nil and self:hasBreakdown("HYDRAULIC_FILTER_CLOGGING") then
            self:removeBreakdown("HYDRAULIC_FILTER_CLOGGING")
        end
    end

    if serviceType == states.OVERHAUL then
        local hasPerSystemTargets = spec.pendingOverhaulSystemTarget ~= nil and next(spec.pendingOverhaulSystemTarget) ~= nil
        if hasPerSystemTargets then
            for systemKey, targetCondition in pairs(spec.pendingOverhaulSystemTarget) do
                local systemData = spec.systems[systemKey]
                if systemData ~= nil then
                    systemData.condition = math.clamp(tonumber(targetCondition) or systemData.condition or 1.0, 0.001, 1.0)
                    systemData.stress = 0
                end
            end
            self:updateConditionLevel()
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

        for systemKey, targetStress in pairs(spec.pendingRepairSystemStressTarget or {}) do
            local systemData = spec.systems[systemKey]
            if systemData ~= nil then
                systemData.stress = math.max(tonumber(targetStress) or 0, 0)
            end
        end
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

    if self.spec_enterable ~= nil and self.spec_enterable.setIsTabbable ~= nil then 
        self.spec_enterable:setIsTabbable(true)
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
        if optionOne == RealisticMechanicalSystems.MAINTENANCE_TYPES.STANDARD then
            spec.airFilterClogging = spec.airFilterResidue
        else
            spec.airFilterClogging = 0
            spec.airFilterResidue = 0
        end
        spec.lubricationLevel = 1.0
        spec.lubricationUsedThisPeriod = true
    end

    ---Clears the paint wear of every wearable node of the vehicle
    -- @param table? vehicle vehicle
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

    if serviceType == states.REPAIR or serviceType == states.OVERHAUL and spec.pendingSelectedBreakdowns.CVT_ADDON_MALFUNCTION ~= nil then
        local systemData = spec.systems.transmission
        if systemData.stress > 0.25 then
            spec.systems.transmission.stress = 0.25
        end
    end

    local maintenanceCompletedText = string.format("%s: %s", self:getFullName(), string.format(g_i18n:getText("rms_spec_maintenance_complete_notification"), g_i18n:getText(serviceType)))

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
            nextOptionOne = RealisticMechanicalSystems.MAINTENANCE_TYPES.STANDARD
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
            local nextServiceText = string.format("%s: %s", self:getFullName(), nextServiceMessage)
            if g_currentMission.hud ~= nil and g_currentMission.hud.addSideNotification ~= nil
                    and self:getOwnerFarmId() == g_currentMission:getFarmId() then
                g_currentMission.hud:addSideNotification({1, 1, 1, 1}, nextServiceText)
            end
            RMS_VehicleChangeStatusEvent.send(self, maintenanceCompletedText .. ". " .. nextServiceMessage, lastEntry)
        else
            if result == RMS_FluidWorkshop.RESULT.NOT_ENOUGH_MONEY then
                local notEnoughMoneyText = string.format(
                    "%s: %s",
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

    spec.pendingSelectedBreakdowns = selectedBreakdowns
    self:recalculateAndApplyEffects()
    self:addEntryToMaintenanceLog(serviceType, optionOne, optionTwo, optionThree, spec.pendingServicePrice, false, spec.pendingServiceInvoice)

    local lastEntry = spec.maintenanceLog and spec.maintenanceLog[#spec.maintenanceLog]
    if lastEntry ~= nil then
        lastEntry.isVisible = true
    end

    if self.spec_enterable ~= nil and self.spec_enterable.setIsTabbable ~= nil then
        self.spec_enterable:setIsTabbable(true)
    end

    local cancelText = string.format("%s: %s", self:getFullName(), string.format(g_i18n:getText("rms_spec_maintenance_cancelled_notification"), g_i18n:getText(serviceType)))
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

    RealisticMechanicalSystems.raiseRMSDirty(self, RealisticMechanicalSystems.SYNC_GROUP.STATE
        + RealisticMechanicalSystems.SYNC_GROUP.SERVICE_PROGRESS
        + RealisticMechanicalSystems.SYNC_GROUP.SERVICE_CONTEXT)

    RMS_VehicleChangeStatusEvent.send(self, cancelText)
end

---Appends a log entry holding the service options, its price and a snapshot of the condition
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
    local realHours = ((spec.realOperatingTime or 0) / (60 * 60 * 1000))
    if realHours <= 0 then
        realHours = self:getFormattedOperatingTime() or 0
    end

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
            age = self.age or 0,
            condition = self:getConditionLevel(),
            service = self:getServiceLevel(),
            systems = systemsSnapshot,
            batterySoc = tonumber(spec.batterySoc) or 1,
            activeBreakdowns = RMS_Utils.deepCopy(self:getActiveBreakdowns()),
            selectedBreakdowns = selectedBreakdowns,
            activeEffects = RMS_Utils.shallowCopy(spec.activeEffects),
            activeIndicators = RMS_Utils.shallowCopy(spec.activeIndicators),
            reliability = spec.reliability,
            maintainability = spec.maintainability,
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

    return (entry.type ~= RealisticMechanicalSystems.STATUS.REPAIR 
    and entry.optionOne ~= RealisticMechanicalSystems.INSPECTION_TYPES.VISUAL 
    and entry.optionOne ~= "NONE" 
    and isCompleted)
end

---Tells whether a log entry holds a complete inspection report
-- @param table? entry maintenance log entry
-- @return boolean isComplete true for a complete inspection
function RealisticMechanicalSystems.getIsCompleteReport(entry)
    return entry.optionOne == RealisticMechanicalSystems.INSPECTION_TYPES.COMPLETE or entry.type == RealisticMechanicalSystems.STATUS.OVERHAUL
end

---Returns the condition recorded by the newest inspection
-- @return float? condition recorded condition
-- @return boolean isComplete true when the inspection was complete
function RealisticMechanicalSystems:getLastInspectedCondition()
    local spec = self.spec_RealisticMechanicalSystems
    if not spec or not spec.maintenanceLog or #spec.maintenanceLog == 0 then
        return 0
    end

    for i = #spec.maintenanceLog, 1, -1 do
        local entry = spec.maintenanceLog[i]
        if RealisticMechanicalSystems.getIsLogEntryHasReport(entry) then
            return entry.conditionData.condition, RealisticMechanicalSystems.getIsCompleteReport(entry)
        end
    end
    return 1.0
end

---Returns the service level recorded by the newest inspection
-- @return float? service recorded service level
-- @return boolean isComplete true when the inspection was complete
function RealisticMechanicalSystems:getLastInspectedService()
    local spec = self.spec_RealisticMechanicalSystems
    if not spec or not spec.maintenanceLog or #spec.maintenanceLog == 0 then
        return 0
    end

    for i = #spec.maintenanceLog, 1, -1 do
        local entry = spec.maintenanceLog[i]
        if RealisticMechanicalSystems.getIsLogEntryHasReport(entry) then
            return entry.conditionData.service, RealisticMechanicalSystems.getIsCompleteReport(entry)
        end
    end
    return 1.0
end

---Returns the date of the newest inspection
-- @return table? date inspection date
function RealisticMechanicalSystems:getLastInspectionDate()
    local spec = self.spec_RealisticMechanicalSystems
    if not spec or not spec.maintenanceLog or #spec.maintenanceLog == 0 then
        return 0
    end

    for i = #spec.maintenanceLog, 1, -1 do
        local entry = spec.maintenanceLog[i]
        if RealisticMechanicalSystems.getIsLogEntryHasReport(entry) then
            return entry.date
        end
    end
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

---Returns the hours of engine running the engine oil lasts, the interval set by the player stretched by the vehicle reliability
-- @return float interval interval in hours of engine running, the time the wear model counts
function RealisticMechanicalSystems:getEngineMaintenanceInterval()
    local spec = self.spec_RealisticMechanicalSystems
    return (spec.baseServiceLevel - RMS_Config.CORE.SERVICE_EXPIRED_THRESHOLD) / RMS_Config.CORE.BASE_SERVICE_WEAR * spec.reliability
end

---Returns the service clocks of the vehicle, those covering at least one oil it holds
-- @return table clocks clock definitions, in the order of SERVICE_CLOCKS
function RealisticMechanicalSystems:getServiceClocks()
    local clocks = {}
    for _, clock in ipairs(RealisticMechanicalSystems.SERVICE_CLOCKS) do
        if next(getServiceClockSumps(self, clock)) ~= nil then
            table.insert(clocks, clock)
        end
    end

    return clocks
end

---Returns the hours a service clock has run since its reset and the hours it lasts, as the hour meter counts them;
-- the hours follow the clock, so poor consumables and a machine parked outside bring its oil change closer
-- @param table clock service clock definition
-- @return float hours hours run since the clock was reset
-- @return float interval hours the clock lasts
function RealisticMechanicalSystems:getServiceClockHours(clock)
    local spec = self.spec_RealisticMechanicalSystems
    local gameTimeCoeff = 1.0
    if g_modIsLoaded ~= nil and g_modIsLoaded["FS25_ingameTimeOperatingHours"] then
        gameTimeCoeff = getSafeMissionTimeScale()
    end

    local interval = self:getEngineMaintenanceInterval() * clock.intervalFactor * gameTimeCoeff
    local usedShare = (spec.baseServiceLevel - spec[clock.levelKey]) / (spec.baseServiceLevel - RMS_Config.CORE.SERVICE_EXPIRED_THRESHOLD)
    return usedShare * interval, interval
end

---Returns the service clock with the fewest hours left, the most overdue one past its interval
-- @return table clock service clock definition
-- @return float hours hours run since the clock was reset
-- @return float interval hours the clock lasts
function RealisticMechanicalSystems:getNextServiceClock()
    local nextClock, nextHours, nextInterval = nil, 0, 0
    for _, clock in ipairs(self:getServiceClocks()) do
        local hours, interval = self:getServiceClockHours(clock)
        if nextClock == nil or interval - hours < nextInterval - nextHours then
            nextClock, nextHours, nextInterval = clock, hours, interval
        end
    end

    return nextClock, nextHours, nextInterval
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


local WARRANTY_MAX_OPERATING_HOURS = 20
local WARRANTY_MAX_AGE_MONTHS = 12

---Tells whether the dealer warranty pays for a repair, on ownership, vehicle age and hours, and the chosen options
-- @param string repairType repair type
-- @param string partType part type
-- @param string workshopType workshop type
-- @return boolean isCovered true when the warranty pays
function RealisticMechanicalSystems:isWarrantyRepairCovered(repairType, partType, workshopType)
    if workshopType ~= RealisticMechanicalSystems.WORKSHOP.DEALER then
        return false
    end

    if self.propertyState ~= 2 then
        return false
    end

    local resolvedPartType = partType or RealisticMechanicalSystems.PART_TYPES.OEM
    local resolverRepairType = repairType or RealisticMechanicalSystems.REPAIR_TYPES.MEDIUM
    if resolvedPartType ~= RealisticMechanicalSystems.PART_TYPES.OEM or resolverRepairType ~= RealisticMechanicalSystems.REPAIR_TYPES.MEDIUM then
        return false
    end

    local operatingHours = self.getFormattedOperatingTime ~= nil and tonumber(self:getFormattedOperatingTime()) or 0
    local ageMonths = tonumber(self.age) or 0

    if operatingHours >= WARRANTY_MAX_OPERATING_HOURS or ageMonths >= WARRANTY_MAX_AGE_MONTHS then
        return false
    end

    return true
end

-- an agricultural machine, priced as the reference machine's family
local AGRICULTURAL_PRICE_FACTORS = { labour = 1, filters = 1, parts = 1 }

---Returns how a machine's size scales a real price: its engine against the reference power, then its family
-- @param table vehicle vehicle
-- @param float exponent how the price follows the engine power
-- @param string factorKey labour, filters or parts
-- @return float scale price scale
local function getSizeScale(vehicle, exponent, factorKey)
    local C = RMS_Config.MAINTENANCE
    local factors = C.PROFILE_PRICE_FACTORS[RMS_Fluids.getProfileName(vehicle)] or AGRICULTURAL_PRICE_FACTORS
    return (RMS_Fluids.getEnginePower(vehicle) / C.REFERENCE_POWER) ^ exponent * factors[factorKey]
end

---Returns a real price in game euros, rounded up to ten
-- @param float realPrice real price in euros
-- @return float price game price
local function getBilledPrice(realPrice)
    return math.ceil(RMS_Utils.getGamePrice(realPrice) / 10) * 10
end

---Returns the labour of a job: its real hours on the reference machine sized on the engine, at the workshop's rate,
-- the machine's ease of maintenance shortening or lengthening them
-- @param table vehicle vehicle
-- @param float hours real hours on the reference machine
-- @param string workshopType workshop type
-- @return float price labour price
local function getLabourPrice(vehicle, hours, workshopType)
    local C = RMS_Config.MAINTENANCE
    local workshopKey = RMS_Utils.getKeyByValue(RealisticMechanicalSystems.WORKSHOP, workshopType)
    return getBilledPrice(hours * getSizeScale(vehicle, C.LABOUR_POWER_EXPONENT, "labour") * C.LABOUR_RATE
        * RMS_Config.WORKSHOP.PRICE_MULTIPLIERS[workshopKey] / vehicle.spec_RealisticMechanicalSystems.maintainability)
end

---Returns the price of repairing a breakdown at a stage: its registry share of the reference repair value, sized on
-- the engine, for the part and repair type chosen
-- @param table vehicle vehicle
-- @param string breakdownId breakdown id
-- @param integer stage breakdown stage
-- @param string repairType repair type
-- @param string partType part type
-- @param string workshopType workshop type
-- @return float price repair price
local function getBreakdownLinePrice(vehicle, breakdownId, stage, repairType, partType, workshopType)
    local C = RMS_Config.MAINTENANCE
    local workshopKey = RMS_Utils.getKeyByValue(RealisticMechanicalSystems.WORKSHOP, workshopType)
    return getBilledPrice(RMS_Breakdowns.BreakdownRegistry[breakdownId].stages[stage].repairPrice / 100 * C.REPAIR_REFERENCE_VALUE
        * getSizeScale(vehicle, C.PARTS_POWER_EXPONENT, "parts")
        * C.PARTS_PRICE_MULTIPLIERS[RMS_Utils.getKeyByValue(RealisticMechanicalSystems.PART_TYPES, partType)]
        * C.REPAIR_PRICE_MULTIPLIERS[RMS_Utils.getKeyByValue(RealisticMechanicalSystems.REPAIR_TYPES, repairType)]
        * RMS_Config.WORKSHOP.PRICE_MULTIPLIERS[workshopKey] / vehicle.spec_RealisticMechanicalSystems.maintainability)
end

---Returns the price of a service, the warranty bringing it to zero when it applies; a top up charges its fluids only
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
        -- an inspection is billed for the time it takes
        local key = RMS_Utils.getKeyByValue(RealisticMechanicalSystems.INSPECTION_TYPES, optionOne)
        return getLabourPrice(self, C.INSPECTION_TIME * C.INSPECTION_TIME_MULTIPLIERS[key] / 3600000, workshopType)

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
            * ownWorkshopDiscount / spec.maintainability)
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

---Returns the labour and the filters of a maintenance, a real dealer's service sized on the engine power and
-- turned into game prices; the workshop changes the labour, the parts the filters, the ease of maintenance its hours
-- @param string optionOne maintenance type
-- @param string optionTwo part type
-- @param string? workshopTypeOverride workshop type replacing the stored one
-- @return table lines kind and price of the labour line then the filters line
function RealisticMechanicalSystems:getMaintenancePriceLines(optionOne, optionTwo, workshopTypeOverride)
    local C = RMS_Config.MAINTENANCE
    local key = RMS_Utils.getKeyByValue(RealisticMechanicalSystems.MAINTENANCE_TYPES, optionOne)
    local partKey = RMS_Utils.getKeyByValue(RealisticMechanicalSystems.PART_TYPES, optionTwo)
    return {
        { kind = "labour", price = getLabourPrice(self, C.MAINTENANCE_LABOUR_HOURS[key],
            workshopTypeOverride or self.spec_RealisticMechanicalSystems.workshopType) },
        { kind = "filters", price = getBilledPrice(C.MAINTENANCE_FILTER_PRICES[key]
            * getSizeScale(self, C.PARTS_POWER_EXPONENT, "filters") * C.PARTS_PRICE_MULTIPLIERS[partKey]) }
    }
end

---Returns the price of each breakdown a repair puts right, the warranty bringing every line to zero
-- @param string? optionOne repair type
-- @param string? optionTwo part type
-- @param string? workshopTypeOverride workshop type replacing the stored one
-- @param boolean? allBreakdowns true to price every breakdown, not only the selected ones
-- @return table lines breakdownId and price of each repaired breakdown, sorted by id
function RealisticMechanicalSystems:getRepairPriceLines(optionOne, optionTwo, workshopTypeOverride, allBreakdowns)
    local workshopType = workshopTypeOverride or self.spec_RealisticMechanicalSystems.workshopType
    local isCovered = self:isWarrantyRepairCovered(optionOne, optionTwo, workshopType)
    local lines = {}

    for id, breakdown in pairs(self:getActiveBreakdowns()) do
        if isBreakdownSelectedForPlayerRepair(id, breakdown, optionOne) or (allBreakdowns and getIsSelectableBreakdown(id)) then
            if RMS_Breakdowns.BreakdownRegistry[id] ~= nil then
                local linePrice = 0
                if not isCovered then
                    linePrice = getBreakdownLinePrice(self, id, breakdown.stage, optionOne, optionTwo, workshopType)
                end
                table.insert(lines, { breakdownId = id, price = linePrice })
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
function RealisticMechanicalSystems:getBreakdownRepairPrice(breakdownId, breakdownStage, partType, workshopTypeOverride)
    local registryEntry = RMS_Breakdowns.BreakdownRegistry[breakdownId]
    if registryEntry == nil or registryEntry.stages[breakdownStage] == nil then
        return 0
    end

    local workshopType = workshopTypeOverride or self.spec_RealisticMechanicalSystems.workshopType
    if self:isWarrantyRepairCovered(RealisticMechanicalSystems.REPAIR_TYPES.MEDIUM, partType, workshopType) then
        return 0
    end
    return getBreakdownLinePrice(self, breakdownId, breakdownStage, RealisticMechanicalSystems.REPAIR_TYPES.MEDIUM, partType,
        workshopType)
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
    local C = RMS_Config.MAINTENANCE
    local workshopType = workshopTypeOverride or spec.workshopType

    if not maintenanceType then maintenanceType = spec.currentState end

    if maintenanceType == RealisticMechanicalSystems.STATUS.READY then
        return 0
    end

    local workDurationHours = 0

    if spec.currentState ~= RealisticMechanicalSystems.STATUS.READY and spec.currentState ~= RealisticMechanicalSystems.STATUS.BROKEN then
        workDurationHours = spec.maintenanceTimer / 3600000
    else
        local totalDurationMs = 0
        if maintenanceType == RealisticMechanicalSystems.STATUS.INSPECTION then
            if C.INSTANT_INSPECTION and optionOne == RealisticMechanicalSystems.INSPECTION_TYPES.VISUAL then
                optionOne = RealisticMechanicalSystems.INSPECTION_TYPES.STANDARD
            end
            local key = RMS_Utils.getKeyByValue(RealisticMechanicalSystems.INSPECTION_TYPES, optionOne)
            if C.INSTANT_INSPECTION then
                totalDurationMs = 1000
            else
                totalDurationMs = C.INSPECTION_TIME * C.INSPECTION_TIME_MULTIPLIERS[key] / spec.maintainability
            end
        elseif maintenanceType == RealisticMechanicalSystems.STATUS.REFILL then
            totalDurationMs = C.REFILL_TIME

        elseif maintenanceType == RealisticMechanicalSystems.STATUS.BODYWORK then
            totalDurationMs = C.INSTANT_BODYWORK and 1000 or RMS_Bodywork.getDurationMs(self, optionOne) or 0

        elseif maintenanceType == RealisticMechanicalSystems.STATUS.MAINTENANCE then
            local key = RMS_Utils.getKeyByValue(RealisticMechanicalSystems.MAINTENANCE_TYPES, optionOne)
            if C.INSTANT_MAINTENANCE_REPAIR then
                totalDurationMs = 1000
            else
                totalDurationMs = C.MAINTENANCE_TIME * C.MAINTENANCE_TIME_MULTIPLIERS[key] / spec.maintainability
            end
        elseif maintenanceType == RealisticMechanicalSystems.STATUS.OVERHAUL then
            local key = RMS_Utils.getKeyByValue(RealisticMechanicalSystems.OVERHAUL_TYPES, optionOne)
            totalDurationMs = C.OVERHAUL_TIME * C.OVERHAUL_TIME_MULTIPLIERS[key] / spec.maintainability
            if optionOne == RealisticMechanicalSystems.OVERHAUL_TYPES.PARTIAL then
                 local systemWeight = RMS_Utils.getEffectiveSystemWeight(self, optionTwo, RealisticMechanicalSystems.SYSTEMS)
                 if systemWeight <= 0 then
                    return 0
                 end
                 totalDurationMs = totalDurationMs * systemWeight
            end
            if optionThree then
                totalDurationMs = totalDurationMs + C.REPAINT_TIME
            end
            if C.INSTANT_OVERHAUL then
                totalDurationMs = 1000
            end
        elseif maintenanceType == RealisticMechanicalSystems.STATUS.REPAIR then
            local repairCount = 0
            local breakdowns = self:getActiveBreakdowns()

            if breakdowns ~= nil and next(breakdowns) ~= nil then
                for id, breakdown in pairs(breakdowns) do
                    if isBreakdownSelectedForPlayerRepair(id, breakdown, optionOne) then
                        repairCount = repairCount + 1
                    end
                end
            end

            -- no breakdown ticked leaves the repair type unset, and there is nothing to time
            if repairCount == 0 then
                return 0
            end

            local key = RMS_Utils.getKeyByValue(RealisticMechanicalSystems.REPAIR_TYPES, optionOne)
            if C.INSTANT_MAINTENANCE_REPAIR then
                totalDurationMs = 1000
            else
                totalDurationMs = C.REPAIR_TIME * C.REPAIR_TIME_MULTIPLIERS[key] * repairCount / spec.maintainability
            end
        end
        workDurationHours = totalDurationMs / 3600000
    end

    if workDurationHours <= 0 then
        return 0
    end

    local totalElapsedHours

    if RMS_Main ~= nil
        and RMS_Main.isWorkshopTypeAlwaysAvailable ~= nil
        and RMS_Main:isWorkshopTypeAlwaysAvailable(workshopType) then
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
