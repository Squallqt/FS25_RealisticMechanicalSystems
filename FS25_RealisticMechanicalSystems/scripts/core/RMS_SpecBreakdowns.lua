-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---Breakdown occurrence and progression.

local log_dbg = RMS_Utils.createLogger("[RMS_SPEC]")

---Tells whether a player sits in the vehicle or its implements
local function hasEnteredPlayerInVehicleChain(rootVehicle)
    if rootVehicle == nil then
        return false
    end

    if rootVehicle.getIsEntered ~= nil and rootVehicle:getIsEntered() then
        return true
    end

    if rootVehicle.getChildVehicles ~= nil then
        for _, childVehicle in ipairs(rootVehicle:getChildVehicles()) do
            if childVehicle ~= nil and childVehicle.getIsEntered ~= nil and childVehicle:getIsEntered() then
                return true
            end
        end
    end

    return false
end


local function getWornPartEffect(symptom, wear)
    local start = symptom.rampStart or RMS_Config.CORE.WORN_PART_RAMP_START
    local exponent = symptom.exponent
    wear = math.min(wear, 0.999)
    return symptom.amplitude * math.max(0, (wear ^ exponent - start ^ exponent) / (1 - start ^ exponent))
end

local function getSymptomCarriers(spec, symptom)
    local carriers = symptom.combustion
    if spec.isElectricVehicle then
        carriers = symptom.electric
    end
    if carriers == nil then
        return nil
    end
    local systemName = RealisticMechanicalSystems.SYSTEMS[symptom.system]
    for _, systemData in pairs(spec.systems) do
        if systemData.name == systemName then
            return systemData.enabled and carriers or nil
        end
    end
    return nil
end

---Returns a part's symptom for an effect, nil without one
local function getCarriedSymptom(spec, partId, effectId)
    for _, symptom in ipairs(RMS_Config.CORE.WORN_PART_SYMPTOMS) do
        if symptom.effect == effectId then
            local carriers = getSymptomCarriers(spec, symptom)
            if carriers ~= nil then
                for _, carrierId in ipairs(carriers) do
                    if carrierId == partId then
                        return symptom
                    end
                end
            end
            return nil
        end
    end
    return nil
end

local function getWornPartEffects(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    local effects = {}
    for _, symptom in ipairs(RMS_Config.CORE.WORN_PART_SYMPTOMS) do
        local carriers = getSymptomCarriers(spec, symptom)
        if carriers ~= nil then
            local wear = 0
            for _, partId in ipairs(carriers) do
                if spec.partWear[partId] ~= nil and not vehicle:hasBreakdown(partId) then
                    wear = math.max(wear, spec.partWear[partId])
                end
            end
            local value = getWornPartEffect(symptom, wear)
            if value ~= 0 then
                table.insert(effects, { id = symptom.effect, value = value, aggregation = symptom.aggregation,
                    extraData = RMS_Utils.deepCopy(symptom.extraData), share = value / symptom.amplitude })
            end
        end
    end
    return effects
end

function RealisticMechanicalSystems:tryTriggerBreakdown()
    local spec = self.spec_RealisticMechanicalSystems

    for systemKey, parts in pairs(spec.systemParts) do
        for _, partId in ipairs(parts) do
            local wear = spec.partWear[partId]
            local drawnWear = math.min(spec.partDrawnWear[partId] or wear, wear)
            if wear > drawnWear and not self:hasBreakdown(partId)
                and math.random() < RMS_Utils.getPartFailureChance(partId, drawnWear, wear) then
                self:addBreakdown(partId, 1)
                log_dbg(string.format("Part [%s] failed at wear %.3f", partId, wear))
            end
            spec.partDrawnWear[partId] = wear
        end
    end
end

---Draws a part of the machine that has no breakdown yet
-- @return string? breakdownId drawn breakdown id, nil when every part has one
function RealisticMechanicalSystems:getRandomBreakdown()
    local candidates = {}
    for _, parts in pairs(self.spec_RealisticMechanicalSystems.systemParts) do
        for _, partId in ipairs(parts) do
            if not self:hasBreakdown(partId) then
                table.insert(candidates, partId)
            end
        end
    end

    if #candidates == 0 then
        return nil
    end
    return candidates[math.random(#candidates)]
end

---Adds a breakdown at a stage, rolling its detection and reapplying the effects
-- @param string breakdownId breakdown id
-- @param any stageOrOptions stage index or an option table
function RealisticMechanicalSystems:addBreakdown(breakdownId, stageOrOptions)
    local spec = self.spec_RealisticMechanicalSystems
    if not spec then return end

    local options
    if type(stageOrOptions) == "table" then
        options = stageOrOptions
    else
        options = {
            stage = stageOrOptions,
            isActive = true,
        }
    end

    local activeBreakdowns = self:getActiveBreakdowns()
    local breakdownRegistry = RMS_Breakdowns.BreakdownRegistry
    
    local activeBreakdownsCount = 0
    for _, breakdownData in pairs(activeBreakdowns) do
        if type(breakdownData) == "table" and breakdownData.isActive ~= false then
            activeBreakdownsCount = activeBreakdownsCount + 1
        end
    end

    local registryEntry = breakdownRegistry[breakdownId]
    if registryEntry == nil then
        log_dbg("addBreakdown skipped: unknown breakdown id:", tostring(breakdownId))
        return
    end

    if activeBreakdownsCount >= RMS_Config.CORE.CONCURRENT_BREAKDOWN_LIMIT_PER_VEHICLE and registryEntry.isSelectable then
        return nil 
    end

    if self:hasBreakdown(breakdownId) then
        return
    end

    local currentIsActive = false
    if options.isActive == nil then
        currentIsActive = true
    else
        currentIsActive = options.isActive
    end

    local resumeTimer = math.max(tonumber(options.resumeTimer) or 0, 0)
    if not currentIsActive and resumeTimer <= 0 then
        local serviceScale = RMS_Config.CORE.REFERENCE_SERVICE_WEAR / RMS_Config.CORE.BASE_SERVICE_WEAR
        resumeTimer = RMS_Config.CORE.REPEAT_BREAKDOWN_TIME * serviceScale * (math.random() + 0.5)
    end

    spec.activeBreakdowns[breakdownId] = {
        stage = math.max(math.floor(tonumber(options.stage) or 1), 1),
        progressTimer = math.max(tonumber(options.progressTimer) or 0, 0),
        isVisible = RMS_Utils.normalizeBoolValue(options.isVisible, false),
        isSelectedForRepair = RMS_Utils.normalizeBoolValue(options.isSelectedForRepair, true),
        isActive = currentIsActive,
        resumeTimer = resumeTimer,
        source = options.source or RealisticMechanicalSystems.BREAKDOWN_SOURCES.RANDOM,
        effectTargetIndex = math.max(math.floor(tonumber(options.effectTargetIndex) or 0), 0),
        branch = 0
    }
    if self.isServer then
        spec.activeBreakdowns[breakdownId].usedPartHours = RealisticMechanicalSystems.drawUsedPartDonorHours(breakdownId)
    end
    if currentIsActive then
        spec.activeBreakdowns[breakdownId].warrantyServiceOverdue = self:getIsWarrantyServiceOverdue(breakdownId)
    end
    if registryEntry.branches ~= nil then
        local branch = math.floor(tonumber(options.branch) or 0)
        spec.activeBreakdowns[breakdownId].branch = (branch >= 1 and branch <= registryEntry.branches) and branch
            or math.random(registryEntry.branches)
    end
    
    self:recalculateAndApplyEffects()

    RealisticMechanicalSystems.raiseRMSDirty(self, RealisticMechanicalSystems.SYNC_GROUP.BREAKDOWNS)
end

---Suspends a breakdown for a delay and marks it as quick fixed
-- @param string breakdownId breakdown id
-- @param float? resumeTimer delay before it resumes in ms
function RealisticMechanicalSystems:suspendBreakdown(breakdownId, resumeTimer)
    local spec = self.spec_RealisticMechanicalSystems
    if not spec or not spec.activeBreakdowns then
        return
    end

    local breakdown = spec.activeBreakdowns[breakdownId]
    if breakdown == nil then
        return
    end

    breakdown.isActive = false
    breakdown.resumeTimer = math.max(tonumber(resumeTimer) or 0, 0)
    breakdown.source = RealisticMechanicalSystems.BREAKDOWN_SOURCES.QUICK_FIX

    self:recalculateAndApplyEffects()

    RealisticMechanicalSystems.raiseRMSDirty(self, RealisticMechanicalSystems.SYNC_GROUP.BREAKDOWNS)
end

---Removes the listed breakdowns, all of them when called without an argument
-- @param any ... breakdown ids
function RealisticMechanicalSystems:removeBreakdown(...)
    local spec = self.spec_RealisticMechanicalSystems
    if not spec or not spec.activeBreakdowns or next(spec.activeBreakdowns) == nil then
        return
    end
    
    local idsToRemove = {...}

    if #idsToRemove == 0 then
        spec.activeBreakdowns = {}
        self:recalculateAndApplyEffects()
        RealisticMechanicalSystems.raiseRMSDirty(self, RealisticMechanicalSystems.SYNC_GROUP.BREAKDOWNS)
        return
    end

    local removedCount = 0
    for _, id in ipairs(idsToRemove) do
        if spec.activeBreakdowns[id] then
            spec.activeBreakdowns[id] = nil
            removedCount = removedCount + 1
        end
    end
    
    if removedCount > 0 then
        self:recalculateAndApplyEffects()
        RealisticMechanicalSystems.raiseRMSDirty(self, RealisticMechanicalSystems.SYNC_GROUP.BREAKDOWNS)
    end
end

---Tells whether a breakdown is active, any selectable one without an id
-- @param string? breakdownId breakdown id
-- @return boolean hasBreakdown true when the breakdown is active
function RealisticMechanicalSystems:hasBreakdown(breakdownId)
    local spec = self.spec_RealisticMechanicalSystems
    if not spec or not spec.activeBreakdowns or next(spec.activeBreakdowns) == nil then
        return false
    end

    if breakdownId == nil then
        for activeBreakdownId, _ in pairs(spec.activeBreakdowns) do
            local breakdownDef = RMS_Breakdowns.BreakdownRegistry[activeBreakdownId]
            if breakdownDef ~= nil and breakdownDef.isSelectable == true then
                return true
            end
        end

        return false
    end

    return spec.activeBreakdowns[breakdownId] ~= nil
end

---Tells whether an effect is active, or any one when called without an id
-- @param string? effectId effect id
-- @return boolean hasEffect true when the effect is active
function RealisticMechanicalSystems:hasEffect(effectId)
    local spec = self.spec_RealisticMechanicalSystems
    if not spec or not spec.activeEffects or next(spec.activeEffects) == nil then
        return false
    end

    if effectId == nil then
        return next(spec.activeEffects) ~= nil
    end

    return spec.activeEffects[effectId] ~= nil
end

---Tells whether a system carries an active breakdown
-- @param string system system name
-- @return boolean hasBreakdown true when the system has one
function RealisticMechanicalSystems:hasSystemBreakdowns(system)
    local spec = self.spec_RealisticMechanicalSystems
    if not spec or not spec.activeBreakdowns or next(spec.activeBreakdowns) == nil then
        return false
    end

    local systemKey = RMS_Utils.getSystemKey(RealisticMechanicalSystems.SYSTEMS, system)
    if systemKey == nil or systemKey == "" then
        systemKey = type(system) == "string" and string.lower(system) or ""
    end

    if systemKey == "" then
        return false
    end

    for breakdownId, _ in pairs(spec.activeBreakdowns) do
        local registryBreakdown = RMS_Breakdowns.BreakdownRegistry[breakdownId]
        if registryBreakdown ~= nil then
            local breakdownSystemKey = RMS_Utils.getSystemKey(RealisticMechanicalSystems.SYSTEMS, registryBreakdown.system)
            if breakdownSystemKey == systemKey then
                return true
            end
        end
    end

    return false
end

---Moves a breakdown to a stage, or one stage back
-- @param string breakdownId breakdown id
-- @param any targetStageOrReverse target stage index, or true to step back
function RealisticMechanicalSystems:changeBreakdownStage(breakdownId, targetStageOrReverse)
    local spec = self.spec_RealisticMechanicalSystems
    if not spec or not spec.activeBreakdowns or next(spec.activeBreakdowns) == nil or spec.activeBreakdowns[breakdownId] == nil then
        return
    end
    
    local registryBreakdown = RMS_Breakdowns.BreakdownRegistry[breakdownId]
    local breakdown = spec.activeBreakdowns[breakdownId]
    if registryBreakdown == nil or registryBreakdown.stages == nil or #registryBreakdown.stages == 0 then
        return
    end

    local currentStage = math.max(math.floor(tonumber(breakdown.stage) or 1), 1)
    local targetStage = currentStage + 1

    if type(targetStageOrReverse) == "boolean" then
        if targetStageOrReverse then
            targetStage = currentStage - 1
        end
    elseif type(targetStageOrReverse) == "number" then
        targetStage = math.floor(targetStageOrReverse)
    end

    targetStage = math.min(math.max(targetStage, 1), #registryBreakdown.stages)

    if targetStage ~= currentStage then
        breakdown.stage = targetStage
        self:recalculateAndApplyEffects()

        RealisticMechanicalSystems.raiseRMSDirty(self, RealisticMechanicalSystems.SYNC_GROUP.BREAKDOWNS)
    end
end

local RAMP_STEPS = 20

local function getStageDuration(stageData)
    if stageData.progressMultiplier == nil or stageData.progressMultiplier <= 0 then
        return nil
    end
    local C = RMS_Config.CORE
    return C.BASE_BREAKDOWN_PROGRESS_TIME * stageData.progressMultiplier * C.REFERENCE_SERVICE_WEAR / C.BASE_SERVICE_WEAR
end
RealisticMechanicalSystems.getStageDuration = getStageDuration

local function getStageProgress(registryEntry, breakdown)
    local stageData = registryEntry.stages[breakdown.stage]
    local duration = stageData ~= nil and registryEntry.stages[breakdown.stage + 1] ~= nil and getStageDuration(stageData) or nil
    if duration == nil then
        return 0
    end
    return math.clamp((breakdown.progressTimer or 0) / duration, 0, 1)
end
RealisticMechanicalSystems.getStageProgress = getStageProgress

---Counts down suspended breakdowns and advances progressing ones
-- @param float dt time since last call in ms
function RealisticMechanicalSystems:processBreakdowns(dt)
    local spec = self.spec_RealisticMechanicalSystems
    if not spec or not spec.activeBreakdowns or next(spec.activeBreakdowns) == nil then
        return
    end

    local effectsNeedRecalculation = false

    for id, breakdown in pairs(self:getActiveBreakdowns()) do
        local registryEntry = RMS_Breakdowns.BreakdownRegistry[id]

        if registryEntry then
            breakdown.isActive = breakdown.isActive ~= false
            breakdown.resumeTimer = math.max(tonumber(breakdown.resumeTimer) or 0, 0)

            if not breakdown.isActive then
                if breakdown.resumeTimer > 0 then
                    breakdown.resumeTimer = math.max(breakdown.resumeTimer - dt, 0)
                end

                if breakdown.resumeTimer <= 0 then
                    breakdown.resumeTimer = 0
                    breakdown.isActive = true
                    if breakdown.warrantyServiceOverdue == nil then
                        breakdown.warrantyServiceOverdue = self:getIsWarrantyServiceOverdue(id)
                    end
                    effectsNeedRecalculation = true
                end
            elseif registryEntry.stages[breakdown.stage] then
                local stageData = registryEntry.stages[breakdown.stage]
                
                if stageData.progressMultiplier and stageData.progressMultiplier > 0 then
                    
                    local canProgress = true
                    if registryEntry.isCanProgress ~= nil then
                        canProgress = registryEntry.isCanProgress(self)
                    end

                    if canProgress then
                        breakdown.progressTimer = (breakdown.progressTimer or 0) + dt * (1 + (spec.partStrain[id] or 0))

                        local stageDuration = getStageDuration(stageData)
                        local rampStep = math.floor(getStageProgress(registryEntry, breakdown) * RAMP_STEPS)
                        if rampStep ~= breakdown.rampStep then
                            breakdown.rampStep = rampStep
                            effectsNeedRecalculation = true
                        end

                        if breakdown.progressTimer >= stageDuration then
                            local maxStages = #registryEntry.stages
                            
                            if breakdown.stage < maxStages then
                                breakdown.stage = breakdown.stage + 1
                                breakdown.progressTimer = 0
                                effectsNeedRecalculation = true

                                if breakdown.stage == maxStages and registryEntry.stages[breakdown.stage].detectionChance > 0 then
                                    breakdown.isVisible = true
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    if effectsNeedRecalculation then
        self:recalculateAndApplyEffects()

        RealisticMechanicalSystems.raiseRMSDirty(self, RealisticMechanicalSystems.SYNC_GROUP.BREAKDOWNS)
    end
end

function RealisticMechanicalSystems:processWornParts()
    local spec = self.spec_RealisticMechanicalSystems
    if not spec or not self.isServer then
        return
    end

    local steps = {}
    for _, effect in ipairs(getWornPartEffects(self)) do
        table.insert(steps, effect.id .. math.floor(effect.share * RAMP_STEPS))
    end
    local signature = table.concat(steps, " ")
    if signature ~= spec.wornPartSignature then
        spec.wornPartSignature = signature
        self:recalculateAndApplyEffects()
        RealisticMechanicalSystems.raiseRMSDirty(self, RealisticMechanicalSystems.SYNC_GROUP.BREAKDOWNS)
    end
end

local function aggregateEffect(aggregatedEffects, effectData, newValue)
    local effectId = effectData.id
    local strategy = effectData.aggregation or "sum"

    local existingEffect = aggregatedEffects[effectId]

    if existingEffect == nil then
        local newEffect = RMS_Utils.deepCopy(effectData)
        newEffect.value = newValue
        aggregatedEffects[effectId] = newEffect
    else
        if strategy == "sum" then
            if math.abs(newValue) > math.abs(existingEffect.value) then
                existingEffect.extraData = RMS_Utils.deepCopy(effectData.extraData)
            end
            existingEffect.value = existingEffect.value + newValue

        elseif strategy == "multiply" then
            if math.abs(newValue - 1) > math.abs(existingEffect.value - 1) then
                existingEffect.extraData = RMS_Utils.deepCopy(effectData.extraData)
            end
            existingEffect.value = existingEffect.value * newValue

        elseif strategy == "min" then
            if newValue < existingEffect.value then
                existingEffect.value = newValue
                existingEffect.extraData = RMS_Utils.deepCopy(effectData.extraData)
            end

        elseif strategy == "max" then
            if newValue > existingEffect.value then
                existingEffect.value = newValue
                existingEffect.extraData = RMS_Utils.deepCopy(effectData.extraData)
            end

        elseif strategy == "boolean_or" then
            local wasActive = existingEffect.value ~= nil and existingEffect.value ~= false and existingEffect.value ~= 0
            local isActive = newValue ~= nil and newValue ~= false and newValue ~= 0
            existingEffect.value = existingEffect.value or newValue

            if isActive then
                if effectId == "ENGINE_FAILURE" then
                    local newExtraData = RMS_Utils.deepCopy(effectData.extraData)

                    if existingEffect.extraData == nil then
                        existingEffect.extraData = newExtraData
                    elseif newExtraData ~= nil then
                        local existingStarter = existingEffect.extraData.starter == true
                        local newStarter = newExtraData.starter == true

                        if existingStarter and not newStarter then
                            existingEffect.extraData = newExtraData
                        else
                            existingEffect.extraData.starter = existingStarter or newStarter

                            if existingEffect.extraData.message == nil and newExtraData.message ~= nil then
                                existingEffect.extraData.message = newExtraData.message
                            end
                            if existingEffect.extraData.reason == nil and newExtraData.reason ~= nil then
                                existingEffect.extraData.reason = newExtraData.reason
                            end
                            if newExtraData.disableAi == true then
                                existingEffect.extraData.disableAi = true
                            end
                        end
                    end
                elseif isActive and not wasActive then
                    existingEffect.extraData = RMS_Utils.deepCopy(effectData.extraData)
                end
            end
        end
    end
end

local function queueFaultCodeMessages(vehicle, noSideNotifications)
    local spec = vehicle.spec_RealisticMechanicalSystems
    local shown = spec.displayedFaultCodes or {}
    local codes, entries = {}, {}
    if RMS_DiagnosticTool.getHasControllers(vehicle) then
        for _, entry in ipairs(RMS_DiagnosticTool.readFaultCodes(vehicle) or {}) do
            if entry.spn ~= nil then
                local key = string.format("%d %d", entry.spn, entry.fmi)
                codes[key] = true
                table.insert(entries, { key = key, entry = entry })
            end
        end
    end
    spec.displayedFaultCodes = codes
    if noSideNotifications or not vehicle.isClient or vehicle:getOwnerFarmId() ~= g_currentMission:getFarmId() then
        return
    end
    local toDriver = hasEnteredPlayerInVehicleChain(vehicle.rootVehicle or vehicle)
    for _, item in ipairs(entries) do
        if not shown[item.key] then
            spec.pendingFaultCodeMessages = spec.pendingFaultCodeMessages or {}
            table.insert(spec.pendingFaultCodeMessages, { key = item.key, text = RMS_DiagnosticTool.getDisplayText(item.entry),
                isCritical = item.entry.isCritical, toDriver = toDriver })
        end
    end
end

---Rebuilds the active effects from the breakdowns and applies the difference
-- @param boolean? noSideNotifications true when restoring an initial network snapshot
function RealisticMechanicalSystems:recalculateAndApplyEffects(noSideNotifications)
    local spec = self.spec_RealisticMechanicalSystems
    if not spec then return end
    if noSideNotifications then
        spec.pendingSideNotifications = {}
    end

    if spec.isExcludedVehicle then
        local previouslyActiveEffects = spec.activeEffects or {}
        spec.activeEffects = {}

        for effectId, applicator in pairs(RMS_Breakdowns.EffectApplicators) do
            if previouslyActiveEffects[effectId] ~= nil and applicator.remove then
                applicator.remove(self, applicator)
            end
        end

        self:recalculateAndApplyIndicators()
        return
    end

    local previouslyActiveEffects = spec.activeEffects or {}
    local aggregatedEffects = {}
    local unknownBreakdownIds = {}

    for id, breakdown in pairs(self:getActiveBreakdowns()) do
        local registryEntry = RMS_Breakdowns.BreakdownRegistry[id]

        if registryEntry == nil then
            table.insert(unknownBreakdownIds, id)
        elseif breakdown.isActive ~= false and registryEntry.stages[breakdown.stage] then
            local stageData = registryEntry.stages[breakdown.stage]
            local nextStageData = registryEntry.stages[breakdown.stage + 1]
            local progress = getStageProgress(registryEntry, breakdown)

            if stageData.effects then
                for _, effectData in ipairs(RMS_Utils.getBranchItems(stageData.effects, breakdown)) do
                    local effectId = effectData.id
                    local strategy = effectData.aggregation or "sum"

                    local newValue
                    if type(effectData.value) == 'function' then
                        newValue = effectData.value(self)
                    else
                        newValue = effectData.value
                    end

                    if progress > 0 and nextStageData ~= nil and nextStageData.effects ~= nil and type(newValue) == "number"
                        and strategy ~= "boolean_or" then
                        for _, nextEffectData in ipairs(RMS_Utils.getBranchItems(nextStageData.effects, breakdown)) do
                            if nextEffectData.id == effectId then
                                local nextValue = nextEffectData.value
                                if type(nextValue) == "function" then
                                    nextValue = nextValue(self)
                                end
                                if type(nextValue) == "number" then
                                    newValue = newValue + (nextValue - newValue) * progress
                                end
                                break
                            end
                        end
                    end

                    local carriedSymptom = type(newValue) == "number" and getCarriedSymptom(spec, id, effectId) or nil
                    if carriedSymptom ~= nil then
                        local wornValue = getWornPartEffect(carriedSymptom, spec.partWear[id] or 0)
                        if math.abs(wornValue) > math.abs(newValue) then
                            newValue = wornValue
                        end
                    end

                    aggregateEffect(aggregatedEffects, effectData, newValue)
                end
            end
        end
    end

    for _, effectData in ipairs(getWornPartEffects(self)) do
        aggregateEffect(aggregatedEffects, effectData, effectData.value)
    end

    if #unknownBreakdownIds > 0 then
        for _, unknownId in ipairs(unknownBreakdownIds) do
            spec.activeBreakdowns[unknownId] = nil
        end
        RealisticMechanicalSystems.raiseRMSDirty(self, RealisticMechanicalSystems.SYNC_GROUP.BREAKDOWNS)
    end

    if spec.isElectricVehicle then
        for _, effect in pairs(aggregatedEffects) do
            if effect.extraData ~= nil and effect.extraData.electricMessage ~= nil then
                effect.extraData.message = effect.extraData.electricMessage
            end
        end
    end

    spec.activeEffects = aggregatedEffects

    for effectId, applicator in pairs(RMS_Breakdowns.EffectApplicators) do
        local isCurrentlyActive = spec.activeEffects[effectId] ~= nil
        local wasPreviouslyActive = previouslyActiveEffects[effectId] ~= nil

        if isCurrentlyActive then
            if applicator.apply then
                applicator.apply(self, spec.activeEffects[effectId], applicator, noSideNotifications)
            end

            local thermalMessageChanged = effectId == "ENGINE_THERMAL_TORQUE_LIMIT" and wasPreviouslyActive
                and previouslyActiveEffects[effectId].extraData ~= nil and spec.activeEffects[effectId].extraData ~= nil
                and previouslyActiveEffects[effectId].extraData.message ~= spec.activeEffects[effectId].extraData.message
            if self.isClient and not noSideNotifications and (not wasPreviouslyActive or thermalMessageChanged)
                    and (RMS_Config.CORE.ENABLE_WARNING_MESSAGES ~= false or effectId == "ENGINE_THERMAL_TORQUE_LIMIT")
                    and self:getOwnerFarmId() == g_currentMission:getFarmId() then
                local currentEffect = spec.activeEffects[effectId]
                local rootVehicle = self.rootVehicle or self
                local hasEnteredPlayer = hasEnteredPlayerInVehicleChain(rootVehicle)

                if currentEffect ~= nil
                        and currentEffect.extraData ~= nil
                        and currentEffect.extraData.message ~= nil
                        and not hasEnteredPlayer then
                    spec.pendingSideNotifications = spec.pendingSideNotifications or {}
                    spec.pendingSideNotifications[effectId] = currentEffect.extraData.message
                end
            end
        elseif wasPreviouslyActive then
            if applicator.remove then
                applicator.remove(self, applicator)
            end
        end
    end
    
    if self.isClient and not noSideNotifications
            and previouslyActiveEffects.ENGINE_THERMAL_TORQUE_LIMIT ~= nil
            and spec.activeEffects.ENGINE_THERMAL_TORQUE_LIMIT == nil
            and self:getOwnerFarmId() == g_currentMission:getFarmId() then
        spec.pendingSideNotifications = spec.pendingSideNotifications or {}
        spec.pendingSideNotifications.ENGINE_THERMAL_TORQUE_LIMIT = "rms_thermal_power_restored_message"
    end
    self:recalculateAndApplyIndicators()
    queueFaultCodeMessages(self, noSideNotifications)
end

---Rebuilds the dashboard indicators from the active breakdowns
function RealisticMechanicalSystems:recalculateAndApplyIndicators()
    local spec = self.spec_RealisticMechanicalSystems
    if not spec then return end

    spec.activeIndicators = {} 
    if spec.isExcludedVehicle then return end

    local aggregatedIndicatorData = {} 

    for id, breakdown in pairs(self:getActiveBreakdowns()) do
        local registryEntry = RMS_Breakdowns.BreakdownRegistry[id]
        if registryEntry and registryEntry.stages[breakdown.stage] then
            local stageData = registryEntry.stages[breakdown.stage]

            if stageData.indicators then
                for _, indicatorDef in ipairs(RMS_Utils.getBranchItems(stageData.indicators, breakdown)) do
                    local id = indicatorDef.id
                    
                    if aggregatedIndicatorData[id] == nil then
                        aggregatedIndicatorData[id] = {
                            color = indicatorDef.color,
                            switchOnConditions = {},
                            switchOffConditions = {},
                            blinkWhileActive = false
                        }
                    end

                    local currentData = aggregatedIndicatorData[id]

                    local newPriority = RMS_Breakdowns.COLOR_PRIORITY[indicatorDef.color] or 0
                    local existingPriority = RMS_Breakdowns.COLOR_PRIORITY[currentData.color] or 0
                    
                    if newPriority > existingPriority then
                        currentData.color = indicatorDef.color
                    end

                    if indicatorDef.switchOn then
                        table.insert(currentData.switchOnConditions, indicatorDef.switchOn)
                    end
                    if indicatorDef.switchOff then
                        table.insert(currentData.switchOffConditions, indicatorDef.switchOff)
                    end
                    currentData.blinkWhileActive = currentData.blinkWhileActive or indicatorDef.blinkWhileActive == true
                end
            end
        end
    end

    for id, data in pairs(aggregatedIndicatorData) do
        local finalIndicator = {
            color = data.color,
            isActive = false,
            blinkWhileActive = data.blinkWhileActive,
        }

        finalIndicator.switchOn = function(vehicle)
            for _, condition in ipairs(data.switchOnConditions) do
                local result = false
                if type(condition) == 'function' then
                    result = condition(vehicle)
                elseif type(condition) == 'boolean' then
                    result = condition
                end
                
                if result then
                    return true
                end
            end
            return false
        end

        finalIndicator.switchOff = function(vehicle)
            for _, condition in ipairs(data.switchOffConditions) do
                local result = false
                if type(condition) == 'function' then
                    result = condition(vehicle)
                elseif type(condition) == 'boolean' then
                    result = condition
                end
                
                if result then
                    return true
                end
            end
            return false
        end

        spec.activeIndicators[id] = finalIndicator
    end
end
