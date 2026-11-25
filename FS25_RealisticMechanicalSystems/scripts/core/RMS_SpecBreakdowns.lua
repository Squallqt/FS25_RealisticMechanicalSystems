-- Copyright © 2026 Squallqt. All rights reserved.

---Breakdown occurrence and progression

local log_dbg = RMS_Utils.createLogger("[RMS_SPEC]")

---Tells whether a player sits in the machine or in what it carries
-- @param table rootVehicle root vehicle
-- @return boolean hasPlayer true when a player sits in it
local function hasEnteredPlayerInVehicleChain(rootVehicle)
    for _, childVehicle in ipairs(rootVehicle:getChildVehicles()) do
        if childVehicle.getIsEntered ~= nil and childVehicle:getIsEntered() then
            return true
        end
    end

    return false
end


---Returns the effect a worn part gives at a wear
-- @param table symptom worn part symptom
-- @param float wear wear of the part
-- @return float value value of the effect
local function getWornPartEffect(symptom, wear)
    local start = symptom.rampStart or RMS_Config.CORE.WORN_PART_RAMP_START
    local exponent = symptom.exponent
    wear = math.min(wear, 0.999)
    return symptom.amplitude * math.max(0, (wear ^ exponent - start ^ exponent) / (1 - start ^ exponent))
end

---Returns the parts carrying a symptom, nil when its system is disabled
-- @param table spec RMS specialization of the vehicle
-- @param table symptom worn part symptom
-- @return table? carriers parts carrying it
local function getSymptomCarriers(spec, symptom)
    local carriers = symptom.combustion
    if spec.isElectricVehicle then
        carriers = symptom.electric
    end
    if carriers == nil then
        return nil
    end
    return spec.systems[string.lower(symptom.system)].enabled and carriers or nil
end

---Returns the symptom a part carries for an effect, nil without one
-- @param table spec RMS specialization of the vehicle
-- @param string partId part
-- @param string effectId effect
-- @return table? symptom worn part symptom
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

---Returns the effects of the worn parts
-- @param table vehicle vehicle
-- @return table effects effect values by id
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
                    share = value / symptom.amplitude })
            end
        end
    end
    return effects
end

---Draws a breakdown on each part by the wear it took since the last draw
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

---Returns the breakdowns under way, suspended ones left out
-- @param table spec RMS specialization of the vehicle
-- @return integer count breakdowns under way
local function countActiveBreakdowns(spec)
    local count = 0
    for _, breakdown in pairs(spec.activeBreakdowns) do
        if breakdown.isActive then
            count = count + 1
        end
    end
    return count
end

---Adds a breakdown at a stage, rolling its detection and reapplying the effects
-- @param string breakdownId breakdown
-- @param integer|table|nil stageOrOptions stage, or options of the breakdown
function RealisticMechanicalSystems:addBreakdown(breakdownId, stageOrOptions)
    local spec = self.spec_RealisticMechanicalSystems
    if RealisticMechanicalSystems.isMissionVehicle(self) then return end

    local options
    if type(stageOrOptions) == "table" then
        options = stageOrOptions
    else
        options = {
            stage = stageOrOptions,
            isActive = true,
        }
    end

    local registryEntry = RMS_Breakdowns.BreakdownRegistry[breakdownId]
    local isFull = registryEntry.isPartFault and countActiveBreakdowns(spec) >= RMS_Config.CORE.CONCURRENT_BREAKDOWN_LIMIT_PER_VEHICLE
    if isFull or self:hasBreakdown(breakdownId) then
        return
    end

    local isActive = options.isActive ~= false
    local resumeTimer = 0
    if not isActive then
        local serviceScale = RMS_Config.CORE.REFERENCE_SERVICE_WEAR / RMS_Config.CORE.BASE_SERVICE_WEAR
        resumeTimer = RMS_Config.CORE.REPEAT_BREAKDOWN_TIME * serviceScale * (math.random() + 0.5)
    end

    spec.activeBreakdowns[breakdownId] = {
        stage = math.clamp(math.floor(options.stage or 1), 1, #registryEntry.stages),
        progressTimer = math.max(options.progressTimer or 0, 0),
        isVisible = RMS_Utils.normalizeBoolValue(options.isVisible, false),
        isSelectedForRepair = RMS_Utils.normalizeBoolValue(options.isSelectedForRepair, true),
        isActive = isActive, resumeTimer = resumeTimer,
        source = options.source or RealisticMechanicalSystems.BREAKDOWN_SOURCES.RANDOM,
        effectTargetIndex = 0,
        branch = 0
    }
    if self.isServer then
        spec.activeBreakdowns[breakdownId].usedPartHours = RealisticMechanicalSystems.drawUsedPartDonorHours(breakdownId)
    end
    if isActive then
        spec.activeBreakdowns[breakdownId].warrantyServiceOverdue = self:getIsWarrantyServiceOverdue(breakdownId)
        spec.activeBreakdowns[breakdownId].warrantyAbuse = spec.partAbuse[breakdownId]
    end
    if registryEntry.branches ~= nil then
        local branch = options.branch or 0
        spec.activeBreakdowns[breakdownId].branch = (branch >= 1 and branch <= registryEntry.branches) and branch
            or math.random(registryEntry.branches)
    end
    
    self:recalculateAndApplyEffects()

    RealisticMechanicalSystems.raiseRMSDirty(self, RealisticMechanicalSystems.SYNC_GROUP.BREAKDOWNS)
end

---Suspends a breakdown for a delay and marks it as quick fixed
-- @param string breakdownId breakdown
-- @param float resumeTimer delay before it resumes in ms
function RealisticMechanicalSystems:suspendBreakdown(breakdownId, resumeTimer)
    local spec = self.spec_RealisticMechanicalSystems
    local breakdown = spec.activeBreakdowns[breakdownId]
    if breakdown == nil then
        return
    end

    breakdown.isActive = false
    breakdown.resumeTimer = resumeTimer
    breakdown.source = RealisticMechanicalSystems.BREAKDOWN_SOURCES.QUICK_FIX

    self:recalculateAndApplyEffects()

    RealisticMechanicalSystems.raiseRMSDirty(self, RealisticMechanicalSystems.SYNC_GROUP.BREAKDOWNS)
end

---Removes the listed breakdowns, all of them when called without an argument
-- @param string ... breakdowns to remove
function RealisticMechanicalSystems:removeBreakdown(...)
    local spec = self.spec_RealisticMechanicalSystems
    if next(spec.activeBreakdowns) == nil then
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

---Tells whether a breakdown is active, any fault of a part without an id
-- @param string? breakdownId breakdown
-- @return boolean hasBreakdown true when active
function RealisticMechanicalSystems:hasBreakdown(breakdownId)
    local spec = self.spec_RealisticMechanicalSystems
    if breakdownId == nil then
        for activeBreakdownId, _ in pairs(spec.activeBreakdowns) do
            if RMS_Breakdowns.BreakdownRegistry[activeBreakdownId].isPartFault then
                return true
            end
        end

        return false
    end

    return spec.activeBreakdowns[breakdownId] ~= nil
end

---Moves a breakdown to a stage, or one stage back
-- @param string breakdownId breakdown
-- @param integer|boolean targetStageOrReverse stage, or true to go one stage back
function RealisticMechanicalSystems:changeBreakdownStage(breakdownId, targetStageOrReverse)
    local spec = self.spec_RealisticMechanicalSystems
    if spec.activeBreakdowns[breakdownId] == nil then
        return
    end
    
    local registryBreakdown = RMS_Breakdowns.BreakdownRegistry[breakdownId]
    local breakdown = spec.activeBreakdowns[breakdownId]
    local currentStage = breakdown.stage
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

---Returns the duration of a stage in ms, nil when it does not progress
-- @param table stageData stage of the breakdown
-- @return float? duration duration (ms)
local function getStageDuration(stageData)
    if stageData.progressMultiplier <= 0 then
        return nil
    end
    local C = RMS_Config.CORE
    return C.BASE_BREAKDOWN_PROGRESS_TIME * stageData.progressMultiplier * C.REFERENCE_SERVICE_WEAR / C.BASE_SERVICE_WEAR
end
RealisticMechanicalSystems.getStageDuration = getStageDuration

---Returns the share of its stage a breakdown has run, none at the last stage
-- @param table registryEntry definition of the breakdown
-- @param table breakdown state of the breakdown
-- @return float progress share, 0 to 1
local function getStageProgress(registryEntry, breakdown)
    local stages = registryEntry.stages
    local duration = stages[breakdown.stage + 1] ~= nil and getStageDuration(stages[breakdown.stage]) or nil
    if duration == nil then
        return 0
    end
    return math.clamp(breakdown.progressTimer / duration, 0, 1)
end
RealisticMechanicalSystems.getStageProgress = getStageProgress

---Counts down suspended breakdowns and advances progressing ones
-- @param float dt time of the step (ms)
function RealisticMechanicalSystems:processBreakdowns(dt)
    local spec = self.spec_RealisticMechanicalSystems
    if next(spec.activeBreakdowns) == nil then
        return
    end

    local effectsNeedRecalculation = false

    for id, breakdown in pairs(self:getActiveBreakdowns()) do
        local registryEntry = RMS_Breakdowns.BreakdownRegistry[id]

        if not breakdown.isActive then
            breakdown.resumeTimer = math.max(breakdown.resumeTimer - dt, 0)

            if breakdown.resumeTimer <= 0 then
                breakdown.isActive = true
                if breakdown.warrantyServiceOverdue == nil then
                    breakdown.warrantyServiceOverdue = self:getIsWarrantyServiceOverdue(id)
                    breakdown.warrantyAbuse = spec.partAbuse[id]
                end
                effectsNeedRecalculation = true
            end
        else
            local stageData = registryEntry.stages[breakdown.stage]
            
            if stageData.progressMultiplier > 0 then
                
                local canProgress = true
                if registryEntry.isCanProgress ~= nil then
                    canProgress = registryEntry.isCanProgress(self)
                end

                if canProgress then
                    breakdown.progressTimer = breakdown.progressTimer + dt * (1 + (spec.partStrain[id] or 0))

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

    if effectsNeedRecalculation then
        self:recalculateAndApplyEffects()

        RealisticMechanicalSystems.raiseRMSDirty(self, RealisticMechanicalSystems.SYNC_GROUP.BREAKDOWNS)
    end
end

---Reapplies the effects once a worn part symptom changes step
function RealisticMechanicalSystems:processWornParts()
    local spec = self.spec_RealisticMechanicalSystems
    if not self.isServer then
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

---Merges the data of an engine failure, one keeping the starter still winning
-- @param table existing effect gathered so far
-- @param table extraData data of the engine failure folded in
local function mergeEngineFailure(existing, extraData)
    local current = existing.extraData
    if current.starter and not extraData.starter then
        existing.extraData = extraData
    else
        current.starter = current.starter or extraData.starter
        current.message = current.message or extraData.message
        current.disableAi = extraData.disableAi or current.disableAi
    end
end

---Tells whether a value is set
-- @param any value value
-- @return boolean isSet true when neither nil, false nor 0
local function getIsSet(value)
    return value ~= nil and value ~= false and value ~= 0
end

-- each rule folds one more breakdown in, keeping the heaviest extraData
local AGGREGATIONS = {
    sum = function(effect, value, effectData)
        if math.abs(value) > math.abs(effect.value) then
            effect.extraData = RMS_Utils.deepCopy(effectData.extraData)
        end
        effect.value = effect.value + value
    end,
    min = function(effect, value, effectData)
        if value < effect.value then
            effect.value, effect.extraData = value, RMS_Utils.deepCopy(effectData.extraData)
        end
    end,
    max = function(effect, value, effectData)
        if value > effect.value then
            effect.value, effect.extraData = value, RMS_Utils.deepCopy(effectData.extraData)
        end
    end,
    boolean_or = function(effect, value, effectData)
        local wasSet = getIsSet(effect.value)
        effect.value = effect.value or value
        if not getIsSet(value) then
            return
        elseif effectData.id == "ENGINE_FAILURE" then
            mergeEngineFailure(effect, RMS_Utils.deepCopy(effectData.extraData))
        elseif not wasSet then
            effect.extraData = RMS_Utils.deepCopy(effectData.extraData)
        end
    end
}

---Folds an effect value into the effects
-- @param table effects effects by id
-- @param table effectData effect of the stage
-- @param any value value of the effect
local function aggregateEffect(effects, effectData, value)
    local effect = effects[effectData.id]
    if effect == nil then
        effect = RMS_Utils.deepCopy(effectData)
        effect.value = value
        effects[effectData.id] = effect
    else
        AGGREGATIONS[effectData.aggregation](effect, value, effectData)
    end
end

---Notes the codes on display and queues the messages of new ones
-- @param table vehicle vehicle
-- @param boolean? noSideNotifications true to queue no message
local function queueFaultCodeMessages(vehicle, noSideNotifications)
    local spec = vehicle.spec_RealisticMechanicalSystems
    local shown = spec.displayedFaultCodes or {}
    local codes, entries = {}, {}
    if RMS_DiagnosticTool.getHasControllers(vehicle) then
        for _, entry in ipairs(RMS_DiagnosticTool.readFaultCodes(vehicle) or {}) do
            -- the AdBlue gauge tells a low tank in words
            if entry.spn ~= nil and entry.breakdownId ~= RMS_AdBlue.FAULT_ID then
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
    local toDriver = hasEnteredPlayerInVehicleChain(vehicle.rootVehicle)
    for _, item in ipairs(entries) do
        if not shown[item.key] then
            spec.pendingFaultCodeMessages = spec.pendingFaultCodeMessages or {}
            table.insert(spec.pendingFaultCodeMessages, { key = item.key, text = RMS_DiagnosticTool.getDisplayText(item.entry),
                isCritical = item.entry.isCritical, toDriver = toDriver })
        end
    end
end

---Returns the value of an effect, eased toward the next stage, a worn part carrying more
-- @param table vehicle vehicle
-- @param string breakdownId breakdown
-- @param table breakdown state of the breakdown
-- @param table effectData effect of the stage
-- @param table? nextStageData next stage of the breakdown
-- @param float progress share of the stage run, 0 to 1
-- @return float value value of the effect
local function getStageEffectValue(vehicle, breakdownId, breakdown, effectData, nextStageData, progress)
    local value = effectData.value
    if progress > 0 and nextStageData ~= nil and effectData.aggregation ~= "boolean_or" then
        for _, nextEffectData in ipairs(RMS_Utils.getBranchItems(nextStageData.effects, breakdown)) do
            if nextEffectData.id == effectData.id then
                value = value + (nextEffectData.value - value) * progress
                break
            end
        end
    end
    local spec = vehicle.spec_RealisticMechanicalSystems
    local symptom = getCarriedSymptom(spec, breakdownId, effectData.id)
    if symptom ~= nil then
        local wornValue = getWornPartEffect(symptom, spec.partWear[breakdownId] or 0)
        if math.abs(wornValue) > math.abs(value) then
            return wornValue
        end
    end
    return value
end

---Rebuilds the active effects from the breakdowns and applies the difference
-- @param boolean? noSideNotifications true when restoring an initial network snapshot
function RealisticMechanicalSystems:recalculateAndApplyEffects(noSideNotifications)
    local spec = self.spec_RealisticMechanicalSystems
    if noSideNotifications then
        spec.pendingSideNotifications = {}
    end

    if spec.isExcludedVehicle then
        local previouslyActiveEffects = spec.activeEffects
        spec.activeEffects = {}

        for effectId, applicator in pairs(RMS_Breakdowns.EffectApplicators) do
            if previouslyActiveEffects[effectId] ~= nil and applicator.remove then
                applicator.remove(self, applicator)
            end
        end

        self:recalculateAndApplyIndicators()
        return
    end

    local previouslyActiveEffects = spec.activeEffects
    local aggregatedEffects = {}

    for breakdownId, breakdown in pairs(self:getActiveBreakdowns()) do
        local registryEntry = RMS_Breakdowns.BreakdownRegistry[breakdownId]
        if breakdown.isActive then
            local stageData = registryEntry.stages[breakdown.stage]
            local nextStageData = registryEntry.stages[breakdown.stage + 1]
            local progress = getStageProgress(registryEntry, breakdown)
            for _, effectData in ipairs(RMS_Utils.getBranchItems(stageData.effects, breakdown)) do
                local value = getStageEffectValue(self, breakdownId, breakdown, effectData, nextStageData, progress)
                aggregateEffect(aggregatedEffects, effectData, value)
            end
        end
    end

    for _, effectData in ipairs(getWornPartEffects(self)) do
        aggregateEffect(aggregatedEffects, effectData, effectData.value)
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
                and previouslyActiveEffects[effectId].extraData.message ~= spec.activeEffects[effectId].extraData.message
            if self.isClient and not noSideNotifications and (not wasPreviouslyActive or thermalMessageChanged)
                    and (RMS_Config.CORE.ENABLE_WARNING_MESSAGES or effectId == "ENGINE_THERMAL_TORQUE_LIMIT")
                    and self:getOwnerFarmId() == g_currentMission:getFarmId() then
                local currentEffect = spec.activeEffects[effectId]
                local hasEnteredPlayer = hasEnteredPlayerInVehicleChain(self.rootVehicle)

                if currentEffect.extraData ~= nil
                        and currentEffect.extraData.message ~= nil
                        and not hasEnteredPlayer then
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
        spec.pendingSideNotifications.ENGINE_THERMAL_TORQUE_LIMIT = "rms_thermal_power_restored_message"
    end
    self:recalculateAndApplyIndicators()
    queueFaultCodeMessages(self, noSideNotifications)
end

---Rebuilds the dashboard indicators from the active breakdowns
function RealisticMechanicalSystems:recalculateAndApplyIndicators()
    local spec = self.spec_RealisticMechanicalSystems

    spec.activeIndicators = {} 
    if spec.isExcludedVehicle then return end

    local aggregatedIndicatorData = {} 

    for id, breakdown in pairs(self:getActiveBreakdowns()) do
        local stageData = RMS_Breakdowns.BreakdownRegistry[id].stages[breakdown.stage]

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

                local newPriority = RMS_Breakdowns.COLOR_PRIORITY[indicatorDef.color]
                local existingPriority = RMS_Breakdowns.COLOR_PRIORITY[currentData.color]
                
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
