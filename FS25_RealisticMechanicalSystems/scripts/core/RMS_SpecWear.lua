-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---Vehicle part wear.

local hasCVTTransmission = RMS_Utils.hasCVTTransmission
local hasCVTAddon = RMS_Utils.hasCVTAddon
local ensureFactorStatsEntry = RealisticMechanicalSystems.ensureFactorStatsEntry
local getColdEngineStress = RealisticMechanicalSystems.getColdEngineStress
local isMissionVehicle = RealisticMechanicalSystems.isMissionVehicle
local sanitizeNumber = RealisticMechanicalSystems.sanitizeNumber

local function getPassiveWearRate(wearRate, isUnderRoof)
    return wearRate * (isUnderRoof and 0.0 or 0.05)
end

local function refreshSystemCondition(spec, systemKey)
    local parts = spec.systemParts[systemKey]
    if #parts == 0 then
        return
    end

    local totalWear = 0
    for _, partId in ipairs(parts) do
        totalWear = totalWear + math.min(spec.partWear[partId], 1)
    end
    spec.systems[systemKey].condition = math.clamp(1 - totalWear / #parts, 0.001, 1.0)
end
RealisticMechanicalSystems.refreshSystemCondition = refreshSystemCondition

function RealisticMechanicalSystems.buildSystemParts(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    local recordedWear = spec.partWear or {}
    spec.partWear = {}
    spec.partStrain = {}
    spec.partDrawnWear = {}
    spec.systemParts, spec.partCauseShares = {}, {}

    for systemKey, systemData in pairs(spec.systems) do
        local parts = {}
        for partId, definition in pairs(RMS_Breakdowns.BreakdownRegistry) do
            if definition.causes ~= nil and RMS_Utils.getSystemKey(RealisticMechanicalSystems.SYSTEMS, definition.system) == systemKey
                and definition.isApplicable(vehicle) then
                table.insert(parts, partId)
            end
        end
        table.sort(parts)

        local weights = {}
        for index, partId in ipairs(parts) do
            local causes = RMS_Breakdowns.BreakdownRegistry[partId].causes
            for _, alias in ipairs(causes.primary) do
                weights[alias] = weights[alias] or {}
                weights[alias][index] = 1
            end
            for _, alias in ipairs(causes.secondary) do
                weights[alias] = weights[alias] or {}
                weights[alias][index] = RMS_Config.CORE.SECONDARY_CAUSE_SHARE
            end
            spec.partWear[partId] = recordedWear[partId]
            if spec.partWear[partId] == nil then
                if RMS_Breakdowns.BreakdownRegistry[partId].wearsWhile ~= nil then
                    spec.partWear[partId] = RealisticMechanicalSystems.getUnrecordedLitPartWear(vehicle, partId)
                else
                    spec.partWear[partId] = 1 - systemData.condition
                end
            end
        end

        local shares = {}
        for alias, partWeights in pairs(weights) do
            local total = 0
            for index = 1, #parts do
                total = total + (partWeights[index] or 0)
            end
            shares[alias] = {}
            for index = 1, #parts do
                shares[alias][index] = (partWeights[index] or 0) * #parts / total
            end
        end

        spec.systemParts[systemKey] = parts
        spec.partCauseShares[systemKey] = shares
        refreshSystemCondition(spec, systemKey)
    end
end

local function getOverheatWearRange(spec, combustionThreshold)
    if spec.isElectricVehicle then
        local T = RMS_Config.ELECTRIC_DRIVE.THERMAL
        return T.OVERHEAT_THRESHOLD, T.OVERHEAT_FULL_EFFECT
    end
    return combustionThreshold, 120
end

local SERVICE_LEVEL_KEY_BY_SYSTEM = {}
for _, clock in ipairs(RealisticMechanicalSystems.SERVICE_CLOCKS) do
    for _, systemKey in ipairs(clock.systems) do
        SERVICE_LEVEL_KEY_BY_SYSTEM[systemKey] = clock.levelKey
    end
end

local function getExpiredServiceFactor(vehicle, systemKey, serviceMultiplier)
    local spec = vehicle.spec_RealisticMechanicalSystems
    local levelKey = SERVICE_LEVEL_KEY_BY_SYSTEM[systemKey]
    local serviceLevel = spec[levelKey] or spec.baseServiceLevel
    -- Service clocks are resolved at load.
    for _, clock in ipairs(spec.serviceClocks or RealisticMechanicalSystems.SERVICE_CLOCKS) do
        for _, coveredSystem in ipairs(clock.systems) do
            if coveredSystem == systemKey then
                serviceLevel = spec[clock.levelKey] or spec.baseServiceLevel or 1
                local startAge = spec.serviceCalendar ~= nil and spec.serviceCalendar[clock.key] or nil
                if clock.months ~= nil and startAge ~= nil then
                    local elapsed = math.max((tonumber(vehicle.age) or 0) - startAge, 0)
                    serviceLevel = math.min(serviceLevel, (spec.baseServiceLevel or 1) - elapsed / clock.months
                        * ((spec.baseServiceLevel or 1) - RMS_Config.CORE.SERVICE_EXPIRED_THRESHOLD))
                end
            end
        end
    end

    if serviceLevel < RMS_Config.CORE.SERVICE_EXPIRED_THRESHOLD then
        local severity = math.clamp(
            (RMS_Config.CORE.SERVICE_EXPIRED_THRESHOLD - serviceLevel) / RMS_Config.CORE.SERVICE_EXPIRED_THRESHOLD,
            0.0,
            1.0
        )
        local serviceExpireWear = severity * (serviceMultiplier or 0)
        return serviceExpireWear
    end

    return 0.0
end

local function getFilterBypassFactor(spec, wearRate, stateKey)
    local C = RMS_Config.CORE.HYDRAULICS_FACTOR_DATA
    if RMS_Consumables.getFilterStage(spec[stateKey or "hydraulicFilterClogging"]) < C.FILTER_BYPASS_STAGE then
        return 0
    end
    return wearRate * C.FILTER_BYPASS_MULTIPLIER
end

---Advances the hourly service clocks while the engine runs
function RealisticMechanicalSystems:updateServiceLevel(dt)
    local spec = self.spec_RealisticMechanicalSystems
    if isMissionVehicle(self) then
        return
    end

    local wearRate = 0
    if self.getIsMotorStarted ~= nil and self:getIsMotorStarted() then
        wearRate = RMS_Config.CORE.BASE_SERVICE_WEAR * (1 + (spec.extraServiceWear or 0))
    end
    for _, clock in ipairs(self:getServiceClocks()) do
        if clock.intervalFactor ~= nil then
            spec[clock.levelKey] = math.max((spec[clock.levelKey] or spec.baseServiceLevel)
                - wearRate / clock.intervalFactor / 3600000 * dt, 0)
        end
    end

end

---Recomputes the overall condition as the weighted mean of the enabled systems
function RealisticMechanicalSystems:updateConditionLevel()
    local spec = self.spec_RealisticMechanicalSystems
    local weightedCondition = 0
    local totalEnabledWeight = 0
    local systemWeights = RMS_Config.CORE.SYSTEM_WEIGHTS or {}

    for systemName, systemData in pairs(spec.systems) do
        if systemData.enabled ~= false then
            local weight = tonumber(systemWeights[systemName]) or 0
            if weight > 0 then
                local systemCondition = tonumber(systemData.condition) or 1.0
                weightedCondition = weightedCondition + systemCondition * weight
                totalEnabledWeight = totalEnabledWeight + weight
            end
        end
    end

    local condition = 1.0
    if totalEnabledWeight > 0 then
        condition = weightedCondition / totalEnabledWeight
    end

    spec.conditionLevel = math.clamp(condition, 0.001, 1.0)
end

function RealisticMechanicalSystems:updateSystemWear(dt, systemKey, wearRate, factors)
    local spec = self.spec_RealisticMechanicalSystems
    local reliability = math.max(spec.reliability or 1.0, 0.001)
    local dtMultiplier = RMS_Config.CORE.BASE_SYSTEMS_WEAR / (60 * 60 * 1000) * dt
    local scale = (1 + spec.extraConditionWear) / reliability * RMS_Fluids.getSystemWearMultiplier(self, systemKey) * dtMultiplier

    local causeRates, causeTotal = {}, 0
    for key, value in pairs(factors) do
        local alias = RealisticMechanicalSystems.FACTOR_STATS_ALIASES[key]
        if alias ~= nil and value > 0 then
            causeRates[alias] = value
            causeTotal = causeTotal + value
        end
    end
    local causeScale = causeTotal > wearRate and wearRate / causeTotal or 1
    local baseRate = math.max(wearRate - causeTotal, 0)

    local shares = spec.partCauseShares[systemKey]
    for index, partId in ipairs(spec.systemParts[systemKey]) do
        local entry = RMS_Breakdowns.BreakdownRegistry[partId]
        local partBaseRate, baseShare = baseRate, 1
        if entry.wearsByCausesOnly then
            partBaseRate, baseShare = 0, 0
        elseif entry.wearsWhile ~= nil then
            baseShare = entry.wearsWhile(self) and 1 or 0
            partBaseRate = baseShare
        end
        local causeRate = 0
        for alias, value in pairs(causeRates) do
            causeRate = causeRate + value * causeScale * (shares[alias] ~= nil and shares[alias][index] or baseShare)
        end
        spec.partStrain[partId] = causeRate
        spec.partWear[partId] = spec.partWear[partId] + (partBaseRate + causeRate) * scale
    end
    refreshSystemCondition(spec, systemKey)

    local systemStats = ensureFactorStatsEntry(spec, systemKey)
    systemStats.total = systemStats.total + wearRate * scale
    for alias, value in pairs(causeRates) do
        systemStats[alias] = (tonumber(systemStats[alias]) or 0) + value / reliability * dtMultiplier
    end

    spec.systemWearNow[systemKey] = factors
    spec.systemWearRateNow[systemKey] = wearRate * (1 + spec.extraConditionWear) / reliability
end

---Wears the parts of a system at once, the cause on the parts it reaches
function RealisticMechanicalSystems:applyInstantDamageToSystem(system, damageAmount, factorName)
    local spec = self.spec_RealisticMechanicalSystems
    local systemKey = RMS_Utils.getSystemKey(RealisticMechanicalSystems.SYSTEMS, system)
    local alias = RealisticMechanicalSystems.FACTOR_STATS_ALIASES[factorName]
    local shares = spec.partCauseShares[systemKey][alias]

    for index, partId in ipairs(spec.systemParts[systemKey]) do
        local baseShare = RMS_Breakdowns.BreakdownRegistry[partId].wearsByCausesOnly and 0 or 1
        local partDamage = damageAmount * (shares ~= nil and shares[index] or baseShare)
        spec.partWear[partId] = spec.partWear[partId] + partDamage
        if factorName == "terrainImpactFactor" and partDamage > 0 then
            spec.partImpactWear[partId] = (spec.partImpactWear[partId] or 0) + partDamage
        end
    end
    refreshSystemCondition(spec, systemKey)

    local systemStats = ensureFactorStatsEntry(spec, systemKey)
    systemStats.total = systemStats.total + damageAmount
    if alias ~= nil then
        systemStats[alias] = (tonumber(systemStats[alias]) or 0) + damageAmount
    end
end

-- systems
local function updateElectricMotorSystem(vehicle, dt, systemKey)
    local spec = vehicle.spec_RealisticMechanicalSystems
    local C = RMS_Config.ELECTRIC_DRIVE
    local motorLoadFactor, hotMotorFactor = 0, 0
    local wearRate = 1.0
    local engineTemperature = sanitizeNumber(spec.rawEngineTemperature or spec.engineTemperature, -99, -99, 160)

    if vehicle:getIsMotorStarted() then
        local motorLoad = vehicle:getMotorLoadPercentage()

        if spec.dynamicMotorLoad > C.MOTOR_OVERLOADED_THRESHOLD then
            motorLoadFactor = RMS_Utils.calculateQuadraticMultiplier(spec.dynamicMotorLoad, C.MOTOR_OVERLOADED_THRESHOLD, false, C.MOTOR_OVERLOADED_MAX_EFFECT)
                * C.MOTOR_OVERLOADED_MULTIPLIER
            wearRate = wearRate + motorLoadFactor
        end

        local overheatThreshold, overheatFullEffect = getOverheatWearRange(spec)
        if engineTemperature > overheatThreshold and motorLoad > 0.3 then
            hotMotorFactor = RMS_Utils.calculateQuadraticMultiplier(engineTemperature, overheatThreshold, false, overheatFullEffect)
                * RMS_Utils.calculateQuadraticMultiplier(motorLoad, 0.3, false) * C.MOTOR_OVERHEAT_MULTIPLIER
            hotMotorFactor = math.min(hotMotorFactor, C.MOTOR_OVERHEAT_MULTIPLIER)
            wearRate = wearRate + hotMotorFactor
        end

        if motorLoad < RMS_Config.CORE.ENGINE_FACTOR_DATA.MOTOR_IDLING_THRESHOLD and vehicle:getLastSpeed() < 0.003 then
            wearRate = wearRate * C.MOTOR_STANDSTILL_MULTIPLIER
        end
    else
        wearRate = getPassiveWearRate(wearRate, spec.isUnderRoof)
    end

    vehicle:updateSystemWear(dt, systemKey, wearRate, {
        motorLoadFactor = motorLoadFactor,
        hotMotorFactor = hotMotorFactor,
        dynamicMotorLoad = spec.dynamicMotorLoad,
        engineTemperature = engineTemperature
    })
end

---Wears the engine on load, lugging, clogging, temperature and service
function RealisticMechanicalSystems:updateEngineSystem(dt)
    local spec = self.spec_RealisticMechanicalSystems
    local spec_motorized = self.spec_motorized
    local C = RMS_Config.CORE.ENGINE_FACTOR_DATA
    local motorLoadFactor, luggingFactor, expiredServiceFactor, coldMotorFactor, hotMotorFactor, airFilterCloggingFactor = 0, 0, 0, 0, 0, 0
    local baseWearRate = 1.0
    local wearRate = baseWearRate
    local systemKey = RMS_Utils.getSystemKey(RealisticMechanicalSystems.SYSTEMS, spec.systems.engine.name)
    local systemData = spec.systems.engine

    if not systemData.enabled then
        return
    end

    if spec.isElectricVehicle then
        updateElectricMotorSystem(self, dt, systemKey)
        return
    end

    local engineTemperature = sanitizeNumber(spec.rawEngineTemperature or spec.engineTemperature, -99, -99, 160)

    if self.getIsMotorStarted ~= nil and self:getIsMotorStarted() then
        local motorLoad = self:getMotorLoadPercentage()
        local dynamicMotorLoad = spec.dynamicMotorLoad

        -- overload factor, past the strongest engine of the same block
        local overloadRatio = RMS_EngineRemap.getOverloadRatio(self)
        local overloadThreshold = C.MOTOR_OVERLOADED_THRESHOLD * overloadRatio
        if dynamicMotorLoad > overloadThreshold then
            motorLoadFactor = RMS_Utils.calculateQuadraticMultiplier(dynamicMotorLoad, overloadThreshold, false,
                C.MOTOR_OVERLOADED_MAX_EFFECT * overloadRatio)
            motorLoadFactor = math.clamp(motorLoadFactor * (C.MOTOR_OVERLOADED_MULTIPLIER or 0), 0, C.MOTOR_OVERLOADED_MULTIPLIER or 0)
            wearRate = wearRate + motorLoadFactor
        end

        if dynamicMotorLoad > C.LUGGING_MOTORLOAD_THRESHOLD and self:getLastSpeed() > 0.5 then
            luggingFactor = RMS_Utils.getEngineLuggingSeverity(spec_motorized.motor, dynamicMotorLoad, C.LUGGING_MOTORLOAD_THRESHOLD)
            luggingFactor = luggingFactor * (C.LUGGING_MULTIPLIER or 0)
            wearRate = wearRate + luggingFactor
        end

        if spec.airFilterClogging > C.AIR_FILTER_CLOGGING_THRESHOLD then
            airFilterCloggingFactor = RMS_Utils.calculateQuadraticMultiplier(spec.airFilterClogging, C.AIR_FILTER_CLOGGING_THRESHOLD, false)
            airFilterCloggingFactor = airFilterCloggingFactor * (C.AIR_FILTER_CLOGGING_MULTIPLIER or 0)
            wearRate = wearRate + airFilterCloggingFactor
        end

        local coldEngineStress = getColdEngineStress(self)
        if coldEngineStress > 0 then
            coldMotorFactor = coldEngineStress * C.COLD_MOTOR_MULTIPLIER
            wearRate = wearRate + coldMotorFactor

        elseif engineTemperature > C.OVERHEAT_MOTOR_THRESHOLD and motorLoad > 0.3 then
            hotMotorFactor = RMS_Utils.calculateQuadraticMultiplier(engineTemperature, C.OVERHEAT_MOTOR_THRESHOLD, false, 120)
            local motorLoadInf = RMS_Utils.calculateQuadraticMultiplier(motorLoad, 0.3, false)
            hotMotorFactor = hotMotorFactor * (C.OVERHEAT_MOTOR_MULTIPLIER or 0) * motorLoadInf
            hotMotorFactor = math.min(hotMotorFactor, C.OVERHEAT_MOTOR_MULTIPLIER or hotMotorFactor)
            wearRate = wearRate + hotMotorFactor
        end

        if motorLoad < C.MOTOR_IDLING_THRESHOLD and self:getLastSpeed() < 0.003 then
            wearRate = wearRate * C.MOTOR_IDLING_MULTIPLIER
        end

        expiredServiceFactor = getExpiredServiceFactor(self, "engine", C.SERVICE_EXPIRED_MULTIPLIER)
        wearRate = wearRate + expiredServiceFactor
    else
        wearRate = getPassiveWearRate(wearRate, spec.isUnderRoof)
    end

    local lowFluidFactor = 0
    if self.getIsMotorStarted ~= nil and self:getIsMotorStarted() then
        lowFluidFactor = RMS_Utils.getFluidShortage(spec.engineOilLevel) * RMS_Config.FLUIDS.LOW_LEVEL_WEAR_MULTIPLIER
        wearRate = wearRate + lowFluidFactor
    end

    self:updateSystemWear(dt, systemKey, wearRate, {
        motorLoadFactor = motorLoadFactor,
        lowFluidFactor = lowFluidFactor,
        luggingFactor = luggingFactor,
        dynamicMotorLoad = spec.dynamicMotorLoad,
        airFilterCloggingFactor = airFilterCloggingFactor,
        expiredServiceFactor = expiredServiceFactor,
        coldMotorFactor = coldMotorFactor,
        hotMotorFactor = hotMotorFactor,
        engineTemperature = engineTemperature,
    })
end

---Wears the transmission on pull, trailer, lugging, slip, windup and oil
function RealisticMechanicalSystems:updateTransmissionSystem(dt)
    local spec = self.spec_RealisticMechanicalSystems
    local spec_motorized = self.spec_motorized
    local C = RMS_Config.CORE.TRANSMISSION_FACTOR_DATA
    local systemData = spec.systems.transmission
    systemData.pullOverloadTimer = tonumber(systemData.pullOverloadTimer) or 0
    local vehicleHaveCVT = hasCVTTransmission(self)
    local isMotorStarted = self.getIsMotorStarted ~= nil and self:getIsMotorStarted()
    local dynamicMotorLoad = tonumber(spec.dynamicMotorLoad) or 0
    -- External consumers load the engine, not the propulsion.
    local applied = sanitizeNumber(spec_motorized.motor:getMotorAppliedTorque(), 0, 0)
    local external = sanitizeNumber(spec_motorized.motor:getMotorExternalTorque(), 0, 0)
    local driveShare = applied > 0 and math.clamp((applied - external) / applied, 0, 1) or 0
    dynamicMotorLoad = dynamicMotorLoad * driveShare
    local expiredServiceFactor, pullOverloadFactor, luggingFactor, heavyTrailerFactor, wheelSlipFactor, coldTransFactor, hotTransFactor = 0, 0, 0, 0, 0, 0, 0
    local drivetrainWindupFactor = 0
    local wearRate = 1.0
    local brakeState = spec.chassisBrakeState
    local isTruck = spec.isTruck == true
    local trailerMass = math.max(brakeState.trailerMass, 0)
    local hpHeavyTrailerRatio = isTruck
        and brakeState.hpGrossMassRatio
        or brakeState.hpTrailerMassRatio
    local heavyTrailerRatioThreshold, heavyTrailerFullEffectRatio = RMS_Utils.getHeavyTrailerRatioLevels(isTruck)
    local systemKey = RMS_Utils.getSystemKey(RealisticMechanicalSystems.SYSTEMS, spec.systems.transmission.name)
    
    if not systemData.enabled then
        return
    end

    local transTemp = sanitizeNumber(spec.rawTransmissionTemperature or spec.transmissionTemperature, -99, -99, 180)

    if isMotorStarted and not self:getIsAIActive() then
        local drivelineLoad = RMS_Drivetrain.getDrivelineLoad(self)
        if transTemp < C.COLD_TRANSMISSION_THRESHOLD and drivelineLoad > C.COLD_TRANSMISSION_LOAD_THRESHOLD then
            local temperatureFactor = RMS_Utils.calculateQuadraticMultiplier(transTemp, C.COLD_TRANSMISSION_THRESHOLD, true)
            local loadFactor = RMS_Utils.calculateQuadraticMultiplier(drivelineLoad, C.COLD_TRANSMISSION_LOAD_THRESHOLD, false)
            coldTransFactor = math.min(temperatureFactor * loadFactor * C.COLD_TRANSMISSION_MULTIPLIER, C.COLD_TRANSMISSION_MULTIPLIER)
            wearRate = wearRate + coldTransFactor
        end
    end

    -- The transmission addon owns its wear.
    if hasCVTAddon(self) and isMotorStarted then
        local motorLoad = self:getMotorLoadPercentage()
        local speed = self:getLastSpeed()
        if motorLoad < RMS_Config.CORE.ENGINE_FACTOR_DATA.MOTOR_IDLING_THRESHOLD and speed < 0.003 then
            wearRate = wearRate * C.TRANSMISSION_IDLING_MULTIPLIER
        end

    elseif isMotorStarted then
        local motorLoad = self:getMotorLoadPercentage()
        local lastRpm = spec_motorized.motor:getLastRealMotorRpm()
        local maxRpm = spec_motorized.motor.maxRpm
        local rpmLoad = lastRpm / maxRpm
        local speed = self:getLastSpeed()
        
        local pullOverloadTargetTimer = 0
        if dynamicMotorLoad > C.PULL_OVERLOAD_THRESHOLD then
            local timerMax = tonumber(C.PULL_OVERLOAD_TIMER_MAX_EFFECT) or 90
            local timerMid = tonumber(C.PULL_OVERLOAD_TIMER_THRESHOLD) or 60
            local timerMin = math.max(timerMid - (timerMax - timerMid), 0)
            local loadMaxForTimer = 1.15
            local loadRange = math.max(loadMaxForTimer - C.PULL_OVERLOAD_THRESHOLD, 0.001)
            local loadRatio = math.clamp((dynamicMotorLoad - C.PULL_OVERLOAD_THRESHOLD) / loadRange, 0.0, 1.0)
            pullOverloadTargetTimer = timerMin + (timerMax - timerMin) * loadRatio
        end

        systemData.pullOverloadTimerMin = dynamicMotorLoad <= C.PULL_OVERLOAD_THRESHOLD and 0 or pullOverloadTargetTimer

        if systemData.pullOverloadTimer < pullOverloadTargetTimer then
            systemData.pullOverloadTimer = math.min(systemData.pullOverloadTimer + dt / 1000, pullOverloadTargetTimer)
        elseif systemData.pullOverloadTimer > pullOverloadTargetTimer then
            systemData.pullOverloadTimer = math.max(systemData.pullOverloadTimer - dt / 1000, pullOverloadTargetTimer)
        end

        if speed > 0.5 and dynamicMotorLoad > C.PULL_OVERLOAD_THRESHOLD and systemData.pullOverloadTimer > 0 then
            pullOverloadFactor = RMS_Utils.calculateQuadraticMultiplier(systemData.pullOverloadTimer, 0, false, C.PULL_OVERLOAD_TIMER_MAX_EFFECT)
            local overloadSeverity = math.clamp((dynamicMotorLoad - C.PULL_OVERLOAD_THRESHOLD) / (1.15 - C.PULL_OVERLOAD_THRESHOLD), 0, 1)
            pullOverloadFactor = math.clamp(pullOverloadFactor * overloadSeverity * overloadSeverity * C.PULL_OVERLOAD_MULTIPLIER, 0, C.PULL_OVERLOAD_MULTIPLIER)
            wearRate = wearRate + pullOverloadFactor
        end
 
        if not spec.isElectricVehicle and dynamicMotorLoad > C.LUGGING_MOTORLOAD_THRESHOLD and speed > 0.5 then
            luggingFactor = RMS_Utils.getEngineLuggingSeverity(spec_motorized.motor, dynamicMotorLoad, C.LUGGING_MOTORLOAD_THRESHOLD)
            luggingFactor = luggingFactor * C.LUGGING_MULTIPLIER
            wearRate = wearRate + luggingFactor
        end
        if luggingFactor > 0 then
            spec.luggingTutorialTimer = math.min((spec.luggingTutorialTimer or 0) + dt, 5000)
        else
             spec.luggingTutorialTimer = math.max((spec.luggingTutorialTimer or 0) - dt, 0)
        end

        if trailerMass > 0.1 and hpHeavyTrailerRatio < heavyTrailerRatioThreshold and motorLoad > C.HEAVY_TRAILER_MOTORLOAD_THRESHOLD and speed > 0.5 then
            heavyTrailerFactor = RMS_Utils.calculateQuadraticMultiplier(hpHeavyTrailerRatio, heavyTrailerRatioThreshold, true, heavyTrailerFullEffectRatio)
            local loadRange = math.max(1.0 - C.HEAVY_TRAILER_MOTORLOAD_THRESHOLD, 0.001)
            local loadRatio = math.clamp((motorLoad - C.HEAVY_TRAILER_MOTORLOAD_THRESHOLD) / loadRange, 0, 1.0)
            heavyTrailerFactor = math.max(heavyTrailerFactor * C.HEAVY_TRAILER_MULTIPLIER * loadRatio, 0)
            heavyTrailerFactor = math.min(heavyTrailerFactor, C.HEAVY_TRAILER_MULTIPLIER or heavyTrailerFactor)
            wearRate = wearRate + heavyTrailerFactor
        end

        local isTurning = RMS_Drivetrain.getIsTurning(self)
        if not isTurning and spec.wheelSlipIntensity > C.WHEEL_SLIP_THRESHOLD and speed < 20 and motorLoad > 0.5
                and (speed > 0.5 or not self:getIsAIActive()) then
            local groundFrictionCoef = spec.avgTireGroundFrictionCoeff
            wheelSlipFactor = RMS_Utils.calculateQuadraticMultiplier(spec.wheelSlipIntensity, C.WHEEL_SLIP_THRESHOLD, false)
            wheelSlipFactor = math.max(wheelSlipFactor * (C.WHEEL_SLIP_MULTIPLIER or 0) * (groundFrictionCoef ^ 2) * motorLoad, 0)
            wearRate = wearRate + wheelSlipFactor
            spec.wheelSlipTutorialTimer = math.min((spec.wheelSlipTutorialTimer or 0) + dt, 3000)
        else
             spec.wheelSlipTutorialTimer = math.max((spec.wheelSlipTutorialTimer or 0) - dt, 0)
        end

        drivetrainWindupFactor = RMS_Drivetrain.getWindupWearFactor(self)
        if drivetrainWindupFactor > 0 then
            wearRate = wearRate + drivetrainWindupFactor
        end

        if vehicleHaveCVT then
            if transTemp > C.OVERHEAT_TRANSMISSION_THRESHOLD and motorLoad > 0.3 then
                hotTransFactor = RMS_Utils.calculateQuadraticMultiplier(transTemp, C.OVERHEAT_TRANSMISSION_THRESHOLD, false, 120)
                local motorLoadInf = RMS_Utils.calculateQuadraticMultiplier(rpmLoad, 0.5, false)
                hotTransFactor = hotTransFactor * C.OVERHEAT_TRANSMISSION_MAX_MULTIPLIER * motorLoadInf
                hotTransFactor = math.min(hotTransFactor, C.OVERHEAT_TRANSMISSION_MAX_MULTIPLIER or hotTransFactor)
                wearRate = wearRate + hotTransFactor
            end
        end

        if motorLoad < RMS_Config.CORE.ENGINE_FACTOR_DATA.MOTOR_IDLING_THRESHOLD and speed < 0.003 then
            wearRate = wearRate * C.TRANSMISSION_IDLING_MULTIPLIER
        end

        expiredServiceFactor = getExpiredServiceFactor(self, "transmission", C.SERVICE_EXPIRED_MULTIPLIER)
        wearRate = wearRate + expiredServiceFactor
    else
        wearRate = getPassiveWearRate(wearRate, spec.isUnderRoof)
    end

    local lowFluidFactor = 0
    if self.getIsMotorStarted ~= nil and self:getIsMotorStarted() then
        lowFluidFactor = RMS_Utils.getFluidShortage(spec.transmissionOilLevel) * RMS_Config.FLUIDS.LOW_LEVEL_WEAR_MULTIPLIER
        wearRate = wearRate + lowFluidFactor
    end

    local filterBypassFactor, transmissionFilterBypassFactor = 0, 0
    if isMotorStarted and RMS_Fluids.getSumpCircuit(self, "hydraulicFluid") == "transmissionOil" then
        filterBypassFactor = getFilterBypassFactor(spec, wearRate)
        wearRate = wearRate + filterBypassFactor
    elseif isMotorStarted then
        transmissionFilterBypassFactor = getFilterBypassFactor(spec, wearRate, "transmissionFilterClogging")
        wearRate = wearRate + transmissionFilterBypassFactor
    end

    self:updateSystemWear(dt, systemKey, wearRate, {
        expiredServiceFactor = expiredServiceFactor,
        pullOverloadFactor = pullOverloadFactor,
        lowFluidFactor = lowFluidFactor,
        filterBypassFactor = filterBypassFactor,
        transmissionFilterBypassFactor = transmissionFilterBypassFactor,
        pullOverloadTimer = systemData.pullOverloadTimer,
        pullOverloadTimerMin = systemData.pullOverloadTimerMin,
        heavyTrailerFactor = heavyTrailerFactor,
        heavyTrailerMassRatio = hpHeavyTrailerRatio,
        heavyTrailerMassBasis = isTruck and "gcw" or "trailer",
        luggingFactor = luggingFactor,
        wheelSlipFactor = wheelSlipFactor,
        drivetrainWindupFactor = drivetrainWindupFactor,
        coldTransFactor = coldTransFactor,
        hotTransFactor = hotTransFactor
    })
end

---Wears the hydraulics on pump, lift load, vibration, cylinders and oil
function RealisticMechanicalSystems:updateHydraulicsSystem(dt)
    local spec = self.spec_RealisticMechanicalSystems
    local systemKey = RMS_Utils.getSystemKey(RealisticMechanicalSystems.SYSTEMS, spec.systems.hydraulics.name)
    local systemData = spec.systems.hydraulics
    local expiredServiceFactor = 0
    local C = RMS_Config.CORE.HYDRAULICS_FACTOR_DATA
    local heavyLiftFactor, operatingFactor, coldOilFactor, hotOilFactor, vibFactor = 0, 0, 0, 0, 0
    local wearRate = 0
    local vehicleMass = self.getTotalMass ~= nil and (self:getTotalMass(true) or 0) or 0
    local heavyLiftMassRatio = vehicleMass > 0 and math.max(spec.liftedMass or 0, 0) / vehicleMass or 0
    local vibState = spec.chassisVibState or {}
    local vibSignal = tonumber(vibState.smoothed) or 0
    local vibConfig = RMS_Config.CORE.CHASSIS_FACTOR_DATA

    if not systemData.enabled then
        return
    end

    local motorStarted = self.getIsMotorStarted ~= nil and self:getIsMotorStarted()
    if motorStarted then
        heavyLiftFactor = vehicleMass > 0 and math.min(spec.raisingMass / vehicleMass, 1) or 0
        wearRate = C.PUMP_WEAR_RATE + heavyLiftFactor
    end

    if motorStarted and spec.isImplementLifted and self:getLastSpeed() > 0.003 then
        local vibThreshold = tonumber(vibConfig.VIB_FACTOR_THRESHOLD) or 0.08
        if vibSignal > vibThreshold then
            local vibMaxSignal = tonumber(vibConfig.VIB_FACTOR_MAX_SIGNAL) or 0.36
            local vibMaxForCurve = math.max(vibMaxSignal, vibThreshold + 0.001)
            local vibMultiplier = (tonumber(vibConfig.VIB_FACTOR_MULTIPLIER) or 36.0)
                * math.min(heavyLiftMassRatio / C.VIB_FULL_LIFT_MASS_RATIO, 1)
            vibFactor = RMS_Utils.calculateQuadraticMultiplier(vibSignal, vibThreshold, false, vibMaxForCurve)
            vibFactor = math.min(vibFactor * vibMultiplier, vibMultiplier)
            wearRate = wearRate + vibFactor
        end
    end

    if motorStarted and spec.isHydraulicActive then
        operatingFactor = math.max(1 - C.PUMP_WEAR_RATE, 0)
        wearRate = wearRate + operatingFactor
        local hydraulicTemperature = RMS_Thermal.getHasSeparateHydraulicCircuit(spec)
            and (spec.rawHydraulicTemperature or spec.hydraulicTemperature)
            or (spec.rawTransmissionTemperature or spec.transmissionTemperature)
        local oilTemperature = sanitizeNumber(hydraulicTemperature, spec.rawTransmissionTemperature or spec.transmissionTemperature or 20, -80, 180)
        if oilTemperature < C.COLD_OIL_THRESHOLD and not self:getIsAIActive() then
            coldOilFactor = RMS_Utils.calculateQuadraticMultiplier(oilTemperature, C.COLD_OIL_THRESHOLD, true)
                * C.COLD_OIL_MULTIPLIER
            wearRate = wearRate + coldOilFactor
        elseif oilTemperature > C.HOT_OIL_THRESHOLD then
            hotOilFactor = RMS_Utils.calculateQuadraticMultiplier(oilTemperature, C.HOT_OIL_THRESHOLD, false, 120)
                * C.HOT_OIL_MULTIPLIER
            hotOilFactor = math.min(hotOilFactor, C.HOT_OIL_MULTIPLIER)
            wearRate = wearRate + hotOilFactor
        end

        expiredServiceFactor = getExpiredServiceFactor(self, "hydraulics", C.SERVICE_EXPIRED_MULTIPLIER)
        wearRate = wearRate + expiredServiceFactor
    end

    local lowFluidFactor = 0
    if self.getIsMotorStarted ~= nil and self:getIsMotorStarted() then
        lowFluidFactor = RMS_Utils.getFluidShortage(RMS_Fluids.getLevel(self, "hydraulicFluid")) * RMS_Config.FLUIDS.LOW_LEVEL_WEAR_MULTIPLIER
        wearRate = wearRate + lowFluidFactor
    end

    local filterBypassFactor = getFilterBypassFactor(spec, wearRate)
    wearRate = wearRate + filterBypassFactor

    self:updateSystemWear(dt, systemKey, wearRate, {
        expiredServiceFactor = expiredServiceFactor,
        heavyLiftFactor = heavyLiftFactor,
        lowFluidFactor = lowFluidFactor,
        filterBypassFactor = filterBypassFactor,
        heavyLiftMassRatio = heavyLiftMassRatio,
        vibFactor = vibFactor,
        vibSignal = vibSignal,
        operatingFactor = operatingFactor,
        coldOilFactor = coldOilFactor,
        hotOilFactor = hotOilFactor,
        isHydraulicActive = spec.isHydraulicActive == true
    })
end

---Wears the PTO on load, a raised implement and each engagement
function RealisticMechanicalSystems:updatePtoSystem(dt)
    local spec = self.spec_RealisticMechanicalSystems
    local systemData = spec.systems.pto
    if systemData == nil or systemData.enabled == false then
        return
    end

    local C = RMS_Config.CORE.PTO_FACTOR_DATA
    local systemKey = RMS_Utils.getSystemKey(RealisticMechanicalSystems.SYSTEMS, systemData.name)
    local wearRate = 0
    local expiredServiceFactor = 0
    local ptoLoadFactor = 0
    local ptoRaisedFactor = 0
    local engagementDamage = math.max(tonumber(spec.ptoEngagementDamage) or 0, 0)
    spec.ptoEngagementDamage = 0

    if self.getIsMotorStarted ~= nil and self:getIsMotorStarted() and spec.isPtoActive then
        wearRate = 1
        local utilization = math.max(tonumber(spec.ptoUtilization) or 0, 0)
        if utilization > C.LOAD_FACTOR_THRESHOLD then
            ptoLoadFactor = RMS_Utils.calculatePtoLoadFactor(utilization, C)
            wearRate = wearRate + ptoLoadFactor
        end

        if spec.isPtoImplementRaised and not self:getIsAIActive() then
            ptoRaisedFactor = C.RAISED_IMPLEMENT_MULTIPLIER
            wearRate = wearRate + ptoRaisedFactor
        end

        expiredServiceFactor = getExpiredServiceFactor(self, "pto", C.SERVICE_EXPIRED_MULTIPLIER)
        wearRate = wearRate + expiredServiceFactor
    end

    spec.ptoRaisedTutorialTimer = math.clamp((tonumber(spec.ptoRaisedTutorialTimer) or 0) + (ptoRaisedFactor > 0 and dt or -dt),
        0, C.RAISED_TUTORIAL_MS)
    spec.ptoRaisedTooLong = spec.ptoRaisedTutorialTimer >= C.RAISED_TUTORIAL_MS

    if engagementDamage > 0 then
        self:applyInstantDamageToSystem(systemData.name, engagementDamage, "ptoEngagementFactor")
    end

    self:updateSystemWear(dt, systemKey, wearRate, {
        isPtoActive = spec.isPtoActive == true,
        expiredServiceFactor = expiredServiceFactor,
        ptoLoadFactor = ptoLoadFactor,
        ptoRaisedFactor = ptoRaisedFactor,
        ptoEngagementDamage = engagementDamage,
        ptoRpm = spec.ptoRpm,
        ptoPower = spec.ptoPower,
        ptoUtilization = spec.ptoUtilization,
        ptoEngagementCount = spec.ptoEngagementCount
    })
end

local function getAttachedCutterData(spec_combine, fruitTypeIndex)
    local stone, isPickup, conversion = 1, false, nil
    for cutter in pairs(spec_combine.attachedCutters) do
        if cutter.getCutterStoneMultiplier ~= nil then
            stone = math.max(stone, cutter:getCutterStoneMultiplier())
        end
        local spec_cutter = cutter.spec_cutter
        if spec_cutter ~= nil then
            isPickup = isPickup or spec_cutter.useWindrow == true
            conversion = conversion or spec_cutter.fruitTypeConverters[fruitTypeIndex]
        end
    end
    return stone, isPickup, conversion
end

local function measureHarvestWork(vehicle, state, dt)
    local C = RMS_Config.CORE.HARVEST_FACTOR_DATA
    local spec_combine = vehicle.spec_combine
    local engineKw = math.max(tonumber(vehicle:getMotor().peakMotorPower) or 0, 1)
    local hectares = spec_combine.workedHectars
    local haPerHour = state.hectares ~= nil and math.max(hectares - state.hectares, 0) / (dt / 3600000) or 0
    state.hectares = hectares

    local fruitTypeIndex = spec_combine.lastValidInputFruitType
    local fruitDesc = g_fruitTypeManager:getFruitTypeByIndex(fruitTypeIndex)
    local stone, isPickup, conversion = getAttachedCutterData(spec_combine, fruitTypeIndex)
    state.stone = stone - 1
    state.crop = fruitDesc ~= nil and fruitDesc.name or nil
    state.isRice = state.crop ~= nil and string.find(state.crop, "RICE", 1, true) ~= nil

    local grainTph, strawTph = 0, 0
    if fruitDesc ~= nil and fruitDesc.fillType ~= nil then
        local fillType = conversion ~= nil and g_fillTypeManager:getFillTypeByIndex(conversion.fillTypeIndex) or fruitDesc.fillType
        -- from l/m2 to l/ha
        grainTph = haPerHour * fruitDesc.literPerSqm * 10000 * (conversion ~= nil and conversion.conversionFactor or 1) * fillType.massPerLiter
        if fruitDesc.hasWindrow and fruitDesc.windrowLiterPerSqm ~= nil then
            strawTph = haPerHour * fruitDesc.windrowLiterPerSqm * 10000 * fruitDesc.windrowFillType.massPerLiter
        end
    end

    local isChopping = spec_combine.chopper.isAvailable and not spec_combine.isSwathActive
    local rotaryKw, chopperKw
    if state.kind == "grain" then
        local model = fruitDesc ~= nil and fruitDesc.hasWindrow and C.SMALL_GRAIN or C.MAIZE
        rotaryKw = model.a + model.c * (model == C.SMALL_GRAIN and strawTph or grainTph)
        chopperKw = isChopping and fruitDesc ~= nil and fruitDesc.hasWindrow and C.CHOPPER_ENERGY * grainTph or 0
    elseif state.kind == "forage" and not isPickup then
        rotaryKw = C.FORAGE.a + C.FORAGE.c * grainTph * C.FORAGE_DRY_MATTER
    end

    local effort = rotaryKw ~= nil and rotaryKw / (C.ROTARY_SHARE * engineKw) or spec_combine.numAttachedCutters > 0 and vehicle:getCombineLoadPercentage() or 0
    local chopper = chopperKw ~= nil and chopperKw / (C.CHOPPER_SHARE * engineKw) or 0
    state.source, state.isWet = "rms", vehicle:getIsThreshingDuringRain()

    if RHM_Api ~= nil and RHM_Api.isActivelyHarvesting(vehicle) then
        local power = RHM_Api.getPowerBreakdown(vehicle)
        local processHp = power.pProcess + power.pChopper + power.pSoil
        -- a provider that stops computing keeps its last powers unchanged
        if power.effectiveHp > 0 and processHp > 0 and (RHM_Api.getEngineLoad(vehicle) > 0 or processHp ~= state.rhProcessHp) then
            effort = processHp / (C.ROTARY_SHARE * power.effectiveHp)
            chopper = power.pChopper / (C.CHOPPER_SHARE * power.effectiveHp)
            grainTph = RHM_Api.getTonPerHour(vehicle)
            -- from hp to kW
            rotaryKw, chopperKw = processHp / 1.35962, power.pChopper / 1.35962
            state.source, state.isWet = "rh", RHM_Api.isMoistureExceeded(vehicle)
        end
        state.rhProcessHp = processHp
    end

    local motor, peak = vehicle:getMotor(), 0
    for rpm = motor.minRpm, motor.maxRpm, 50 do
        peak = math.max(peak, motor:getTorqueCurveValue(rpm) * rpm)
    end
    -- from kNm and rpm to hp
    state.enginePowerHp = peak * math.pi / 30 * 1.35962

    state.effort, state.chopper = effort, chopper
    state.grain = grainTph * C.SMALL_GRAIN.c / (C.ROTARY_SHARE * engineKw)
    state.tonPerHour, state.rotaryKw, state.chopperKw = grainTph, rotaryKw or 0, chopperKw or 0
    state.tons = (state.tons or 0) + grainTph * dt / 3600000
end

---Wears the harvest organs on the work they do, only while harvesting
function RealisticMechanicalSystems:updateHarvestSystem(dt)
    local spec = self.spec_RealisticMechanicalSystems
    local systemData = spec.systems.harvest
    if systemData == nil or not systemData.enabled then
        return
    end

    local C = RMS_Config.CORE.HARVEST_FACTOR_DATA
    local systemKey = RMS_Utils.getSystemKey(RealisticMechanicalSystems.SYSTEMS, systemData.name)
    local state = spec.harvestState
    if state == nil then
        state = { kind = RMS_Drivetrain.getHarvestKind(self) }
        spec.harvestState = state
    end

    spec.isHarvestRunning = self:getIsMotorStarted() and self:getIsTurnedOn()
    local wearRate = 0
    local factors = { harvestEffortFactor = 0, harvestGrainFactor = 0, harvestStrawFactor = 0, harvestStoneFactor = 0,
        harvestRiceFactor = 0, harvestWetFactor = 0, lubricationFactor = 0 }
    if spec.isHarvestRunning then
        measureHarvestWork(self, state, dt)
        local work = C.BASE_RATE * state.effort
        local stone = state.stone * (spec.activeEffects.METAL_DETECTOR_OFF ~= nil and C.DETECTOR_OFF_STONE_MULTIPLIER or 1)
        local rates = {
            harvestEffortFactor = C.BASE_RATE * math.max(state.effort - 1, 0),
            harvestGrainFactor = C.BASE_RATE * math.max(state.grain - 1, 0),
            harvestStrawFactor = C.BASE_RATE * math.max(state.chopper - 1, 0),
            harvestStoneFactor = work * stone,
            harvestRiceFactor = state.isRice and work * C.RICE_MULTIPLIER or 0,
            harvestWetFactor = state.isWet and work * C.WET_MULTIPLIER or 0,
            lubricationFactor = work * (RMS_Greasing.getWearFactor(self) - 1)
        }
        wearRate = C.BASE_RATE * math.min(state.effort, 1)
        for key, rate in pairs(rates) do
            -- a cause spreads over its parts: scaled to reach each part whole
            local shares = spec.partCauseShares[systemKey][RealisticMechanicalSystems.FACTOR_STATS_ALIASES[key]]
            local maxShare = 0
            for _, share in pairs(shares or {}) do
                maxShare = math.max(maxShare, share)
            end
            factors[key] = maxShare > 0 and rate / maxShare or 0
            wearRate = wearRate + factors[key]
        end
        factors.harvestEffort, factors.harvestGrain, factors.harvestChopper = state.effort, state.grain, state.chopper
        factors.harvestTonPerHour, factors.harvestChopperKw, factors.harvestStone = state.tonPerHour, state.chopperKw, stone
        factors.harvestSource = state.source
    end

    self:updateSystemWear(dt, systemKey, wearRate, factors)
end

local function getHarvestSpec(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    if spec == nil or spec.systems.harvest == nil or not spec.systems.harvest.enabled then
        return nil
    end
    return spec
end

-- grain loss in percent, engine power in hp, power demand as a factor
RealisticMechanicalSystems.HARVEST_WEAR_PROVIDER = {
    getWearLoss = function(vehicle)
        local spec = getHarvestSpec(vehicle)
        if spec == nil then
            return nil
        end
        local effect = spec.activeEffects.HARVEST_GRAIN_LOSS
        return math.clamp(effect ~= nil and effect.value or 0, 0, RMS_Config.CORE.HARVEST_FACTOR_DATA.MAX_GRAIN_LOSS) * 100
    end,
    getEnginePowerHp = function(vehicle)
        local spec = getHarvestSpec(vehicle)
        return spec ~= nil and spec.harvestState ~= nil and spec.harvestState.enginePowerHp or nil
    end,
    getPowerDemandFactor = function(vehicle)
        local spec = getHarvestSpec(vehicle)
        if spec == nil then
            return nil
        end
        local effect = spec.activeEffects.HARVEST_POWER_DEMAND
        return 1 + (effect ~= nil and math.max(effect.value, 0) or 0)
    end
}

---Wears the cooling on high cooling, overheating, cold shock and service
function RealisticMechanicalSystems:updateCoolingSystem(dt)
    local spec = self.spec_RealisticMechanicalSystems
    local spec_motorized = self.spec_motorized
    local systemKey = RMS_Utils.getSystemKey(RealisticMechanicalSystems.SYSTEMS, spec.systems.cooling.name)
    local systemData = spec.systems.cooling
    local expiredServiceFactor = 0
    local C = RMS_Config.CORE.COOLING_FACTOR_DATA
    local highCoolingFactor, overheatFactor, coldShockFactor = 0, 0, 0
    local wearRate = 1.0
    local rpmLoad = 0

    if not systemData.enabled then
        return
    end

    local engineTemperature = sanitizeNumber(spec.rawEngineTemperature or spec.engineTemperature, -99, -99, 160)

    if self.getIsMotorStarted ~= nil and self:getIsMotorStarted() then
        local lastRpm = spec_motorized.motor:getLastModulatedMotorRpm()
        local maxRpm = spec_motorized.motor.maxRpm
        rpmLoad = lastRpm / maxRpm

        if engineTemperature > RMS_Thermal.getDriveValues(spec).PID_TARGET_TEMP + C.HIGH_COOLING_TEMP_MARGIN then
            if spec.thermostatState > C.HIGH_COOLING_FACTOR_THRESHOLD then
                highCoolingFactor = RMS_Utils.calculateQuadraticMultiplier(spec.thermostatState, C.HIGH_COOLING_FACTOR_THRESHOLD, false)
                highCoolingFactor = highCoolingFactor * (C.HIGH_COOLING_FACTOR_MULTIPLIER or 0)
                highCoolingFactor = math.min(highCoolingFactor, C.HIGH_COOLING_FACTOR_MULTIPLIER or highCoolingFactor)
                wearRate = wearRate + highCoolingFactor
            end
        end

        local overheatThreshold, overheatFullEffect = getOverheatWearRange(spec, C.OVERHEAT_FACTOR_THRESHOLD)
        if engineTemperature > overheatThreshold then
            overheatFactor = RMS_Utils.calculateQuadraticMultiplier(engineTemperature, overheatThreshold, false, overheatFullEffect)
            overheatFactor = overheatFactor * (C.OVERHEAT_FACTOR_MULTIPLIER or 0)
            overheatFactor = math.min(overheatFactor, C.OVERHEAT_FACTOR_MULTIPLIER or overheatFactor)
            wearRate = wearRate + overheatFactor
        end

        if not spec.isElectricVehicle and engineTemperature < C.COLD_SHOCK_FACTOR_THRESHOLD and rpmLoad > 0.75 and not self:getIsAIActive() then
            coldShockFactor = RMS_Utils.calculateQuadraticMultiplier(engineTemperature, C.COLD_SHOCK_FACTOR_THRESHOLD, true)
            local motorLoadInf = RMS_Utils.calculateQuadraticMultiplier(rpmLoad, 0.75, false)
            coldShockFactor = coldShockFactor * (C.COLD_SHOCK_FACTOR_MULTIPLIER or 0) * motorLoadInf
            coldShockFactor = math.min(coldShockFactor, C.COLD_SHOCK_FACTOR_MULTIPLIER or coldShockFactor)
            wearRate = wearRate + coldShockFactor
        end

        if spec.thermostatState == 0 and overheatFactor == 0 and coldShockFactor == 0 then
            wearRate = wearRate * C.COOLING_IDLING_MULTIPLIER
        end

        expiredServiceFactor = getExpiredServiceFactor(self, "cooling", C.SERVICE_EXPIRED_MULTIPLIER)
        wearRate = wearRate + expiredServiceFactor
    else
        wearRate = getPassiveWearRate(wearRate, spec.isUnderRoof)
    end

    self:updateSystemWear(dt, systemKey, wearRate, {
        expiredServiceFactor = expiredServiceFactor,
        highCoolingFactor = highCoolingFactor,
        overheatFactor = overheatFactor,
        coldShockFactor = coldShockFactor
    })
end

---Wears the electrics on cranking, weather, lights, heat and vibration
function RealisticMechanicalSystems:updateElectricalSystem(dt)
    local spec = self.spec_RealisticMechanicalSystems
    local systemKey = RMS_Utils.getSystemKey(RealisticMechanicalSystems.SYSTEMS, spec.systems.electrical.name)
    local systemData = spec.systems.electrical
    if systemData == nil then return end
    local vibState = spec.chassisVibState
    local vibSignal = vibState.signal
    local vibRaw = vibState.raw
    local weatherExposureFactor, lightsFactor, overheatFactor, crankingStressFactor, vibFactor = 0, 0, 0, 0, 0
    local C = RMS_Config.CORE.ELECTRICAL_FACTOR_DATA
    local wearRate = 1.0

    if not systemData.enabled then
        return
    end

    local engineTemperature = sanitizeNumber(spec.rawEngineTemperature or spec.engineTemperature, -99, -99, 160)

    local isOutdoor = not spec.isUnderRoof

    if self.spec_lights ~= nil and self.getLightsTypesMask ~= nil then
        local lightsSpec = self.spec_lights
        local lightsMask = tonumber(self:getLightsTypesMask()) or 0
        local maxLightStateMask = tonumber(lightsSpec.maxLightStateMask) or 0
        local activeMainLightsMask = lightsMask

        if maxLightStateMask > 0 and bitAND ~= nil then
            activeMainLightsMask = bitAND(lightsMask, maxLightStateMask)
        end

        if activeMainLightsMask > 0 then
            lightsFactor = C.LIGHTS_FACTOR_MULTIPLIER or 0
            wearRate = wearRate + lightsFactor
        end
    end

    if isOutdoor then
        local weatherType = RMS_Main.currentWeather
        if weatherType == WeatherType.RAIN then
            weatherExposureFactor = C.RAIN_FACTOR_MULTIPLIER or 0
        elseif weatherType == WeatherType.SNOW then
            weatherExposureFactor = C.SNOW_FACTOR_MULTIPLIER or 0
        elseif weatherType == WeatherType.HAIL then
            weatherExposureFactor = C.HAIL_FACTOR_MULTIPLIER or 0
        end
        wearRate = wearRate + weatherExposureFactor
    end

    systemData.crankingTimer = systemData.crankingTimer or 0
    if spec.isCranking then
        systemData.crankingTimer = math.min(systemData.crankingTimer + dt, 10000)
        if systemData.crankingTimer > 3500 then
            crankingStressFactor = C.CRANKING_STRESS_MULTIPLIER
            wearRate = wearRate + crankingStressFactor
        end
    else
        systemData.crankingTimer = math.max(systemData.crankingTimer - dt / 100, 0)
    end

    if self:getIsMotorStarted() then
        local overheatThreshold, overheatFullEffect = getOverheatWearRange(spec, C.OVERHEAT_FACTOR_THRESHOLD)
        if engineTemperature > overheatThreshold then
            overheatFactor = RMS_Utils.calculateQuadraticMultiplier(engineTemperature, overheatThreshold, false, overheatFullEffect)
            overheatFactor = overheatFactor * (C.OVERHEAT_FACTOR_MULTIPLIER or 0)
            overheatFactor = math.min(overheatFactor, C.OVERHEAT_FACTOR_MULTIPLIER or overheatFactor)
            wearRate = wearRate + overheatFactor
        end

        local vibThreshold = tonumber(C.VIB_FACTOR_THRESHOLD) or 0.12
        if vibState.smoothed > vibThreshold then
            local vibMaxSignal = tonumber(C.VIB_FACTOR_MAX_SIGNAL) or 0.22
            local vibMaxForCurve = math.max(vibMaxSignal, vibThreshold + 0.001)
            local vibMultiplier = tonumber(C.VIB_FACTOR_MULTIPLIER) or 4.0
            vibFactor = RMS_Utils.calculateQuadraticMultiplier(vibState.smoothed, vibThreshold, false, vibMaxForCurve)
            vibFactor = vibFactor * vibMultiplier
            vibFactor = math.min(vibFactor, vibMultiplier)
            wearRate = wearRate + vibFactor
        end

    elseif lightsFactor == 0 and crankingStressFactor == 0 then 
        wearRate = getPassiveWearRate(wearRate, spec.isUnderRoof)
    end

    self:updateSystemWear(dt, systemKey, wearRate, {
        crankingStressFactor = crankingStressFactor,
        crankingTimer = systemData.crankingTimer or 0,
        weatherExposureFactor = weatherExposureFactor,
        lightsFactor = lightsFactor,
        overheatFactor = overheatFactor,
        vibFactor = vibFactor,
        vibSignal = vibSignal,
        vibRaw = vibRaw
    })
end

---Wears the chassis on vibration, steering, braking and lubrication
function RealisticMechanicalSystems:updateChassisSystem(dt)
    local spec = self.spec_RealisticMechanicalSystems
    local systemKey = RMS_Utils.getSystemKey(RealisticMechanicalSystems.SYSTEMS, spec.systems.chassis.name)
    local systemData = spec.systems.chassis
    local lubricationFactor, vibFactor, steerLoadFactor = 0, 0, 0
    local vibState = spec.chassisVibState
    local steerState = spec.chassisSteerState
    local brakeState = spec.chassisBrakeState
    local vibSignal = vibState.signal
    local vibRaw = vibState.raw
    local steerLowSpeedFactor = 0
    local brakeMassFactor = 0
    local parkBrakeDragFactor = 0
    local isTruck = spec.isTruck == true
    local trailerMass = math.max(brakeState.trailerMass, 0)
    local hpBrakeMassRatio = isTruck
        and brakeState.hpGrossMassRatio
        or brakeState.hpTrailerMassRatio
    local brakePedal = brakeState.pedal
    local C = RMS_Config.CORE.CHASSIS_FACTOR_DATA
    local brakeMassRatioThreshold = isTruck
        and (tonumber(C.BRAKE_MASS_TRUCK_RATIO_THRESHOLD) or 6.0)
        or (tonumber(C.BRAKE_MASS_RATIO_THRESHOLD) or 10.0)
    local brakeMassFullEffectRatio = isTruck
        and (tonumber(C.BRAKE_MASS_TRUCK_RATIO_FULL_EFFECT) or 3.0)
        or (tonumber(C.BRAKE_MASS_RATIO_FULL_EFFECT) or 5.0)
    local wearRate = 1.0

    if not systemData.enabled then
        return
    end

    local speed = self:getLastSpeed()


    if self.getIsMotorStarted ~= nil and self:getIsMotorStarted() then
        if spec.isVehicleNeedLubricate then
            lubricationFactor = RMS_Greasing.getWearFactor(self) - 1
            wearRate = wearRate + lubricationFactor
        end

        if speed > 0.003 then
            local vibThreshold = tonumber(C.VIB_FACTOR_THRESHOLD) or 0.12
            if vibState.smoothed > vibThreshold then
                local vibMaxSignal = tonumber(C.VIB_FACTOR_MAX_SIGNAL) or 0.22
                local vibMaxForCurve = math.max(vibMaxSignal, vibThreshold + 0.001)
                local vibMultiplier = tonumber(C.VIB_FACTOR_MULTIPLIER) or 4.0
                vibFactor = RMS_Utils.calculateQuadraticMultiplier(vibState.smoothed, vibThreshold, false, vibMaxForCurve)
                vibFactor = vibFactor * vibMultiplier
                vibFactor = math.min(vibFactor, vibMultiplier)
                wearRate = wearRate + vibFactor
            end

            if trailerMass > 0.1 and brakeState.isBraking and speed > (tonumber(C.BRAKE_MASS_SPEED_THRESHOLD) or 2.0) then
                if hpBrakeMassRatio < brakeMassRatioThreshold then
                    local ratioFactor = RMS_Utils.calculateQuadraticMultiplier(hpBrakeMassRatio, brakeMassRatioThreshold, true, brakeMassFullEffectRatio)
                    local brakeInputFactor = brakePedal
                    brakeMassFactor = ratioFactor * brakeInputFactor * (tonumber(C.BRAKE_MASS_FACTOR_MULTIPLIER) or 6.0)
                    brakeMassFactor = math.min(brakeMassFactor, tonumber(C.BRAKE_MASS_FACTOR_MULTIPLIER) or brakeMassFactor)
                    wearRate = wearRate + brakeMassFactor
                end
            end

            parkBrakeDragFactor = RMS_Drivetrain.getParkBrakeDragFactor(self)
            wearRate = wearRate + parkBrakeDragFactor

        else
            wearRate = wearRate * C.CHASSIS_IDLING_MULTIPLIER    
        end

        if steerState.groundContact > 0 and not self:getIsAIActive() then
            steerLowSpeedFactor = RMS_Utils.calculateQuadraticMultiplier(speed, C.STEER_LOAD_SPEED_THRESHOLD, true)
            steerLoadFactor = C.STEER_LOAD_FACTOR_MULTIPLIER * steerState.travelRate * steerLowSpeedFactor
                * spec.avgTireGroundFrictionCoeff * steerState.axleLoadRatio
            wearRate = wearRate + steerLoadFactor
        end
    else
        wearRate = getPassiveWearRate(wearRate, spec.isUnderRoof)
    end

    self:updateSystemWear(dt, systemKey, wearRate, {
        lubricationFactor = lubricationFactor,
        vibFactor = vibFactor,
        vibSignal = vibSignal,
        vibRaw = vibRaw,
        impactCount = spec.terrainImpacts.count,
        impactSpeedLoss = spec.terrainImpacts.lastSpeedLoss,
        steerPlay = spec.activeEffects.STEERING_PLAY_EFFECT ~= nil and spec.activeEffects.STEERING_PLAY_EFFECT.value or 0,
        steerPull = spec.activeEffects.STEERING_STATIC_BIAS_EFFECT ~= nil and spec.activeEffects.STEERING_STATIC_BIAS_EFFECT.value or 0,
        steerLoadFactor = steerLoadFactor,
        steerLowSpeedFactor = steerLowSpeedFactor,
        steerGroundFrictionCoeff = spec.avgTireGroundFrictionCoeff,
        steerTravelRate = steerState.travelRate,
        steerAxleLoadRatio = steerState.axleLoadRatio,
        brakeMassFactor = brakeMassFactor,
        parkBrakeDragFactor = parkBrakeDragFactor,
        brakeMassRatio = hpBrakeMassRatio,
        brakeMassBasis = isTruck and "gcw" or "trailer"
    })
end

local function updateTractionBatterySystem(vehicle, dt, systemKey)
    local spec = vehicle.spec_RealisticMechanicalSystems
    local C = RMS_Config.ELECTRIC_DRIVE
    local fuelState = spec.fuelState
    local deepDischargeFactor, highDrawFactor, batteryHeatFactor = 0, 0, 0
    local wearRate = 1.0

    if vehicle:getIsMotorStarted() then
        if spec.tractionBatteryTempC > C.BATTERY_HEAT_THRESHOLD then
            batteryHeatFactor = RMS_Utils.calculateQuadraticMultiplier(spec.tractionBatteryTempC, C.BATTERY_HEAT_THRESHOLD, false, C.BATTERY_HEAT_FULL_EFFECT)
            batteryHeatFactor = math.min(batteryHeatFactor * C.BATTERY_HEAT_MULTIPLIER, C.BATTERY_HEAT_MULTIPLIER)
            wearRate = wearRate + batteryHeatFactor
        end

        if fuelState.level < C.DEEP_DISCHARGE_THRESHOLD then
            local motorLoadInf = 1 + RMS_Utils.calculateQuadraticMultiplier(vehicle:getMotorLoadPercentage(), 0.70, false)
            deepDischargeFactor = RMS_Utils.calculateQuadraticMultiplier(fuelState.level, C.DEEP_DISCHARGE_THRESHOLD, true)
                * motorLoadInf * C.DEEP_DISCHARGE_MULTIPLIER
            wearRate = wearRate + deepDischargeFactor
        end

        if fuelState.currentUsageRatio > C.HIGH_DRAW_THRESHOLD then
            highDrawFactor = RMS_Utils.calculateQuadraticMultiplier(fuelState.currentUsageRatio, C.HIGH_DRAW_THRESHOLD, false)
            highDrawFactor = math.min(highDrawFactor * C.HIGH_DRAW_MULTIPLIER, C.HIGH_DRAW_MULTIPLIER)
            wearRate = wearRate + highDrawFactor
        end
    else
        wearRate = getPassiveWearRate(wearRate, spec.isUnderRoof)
    end

    vehicle:updateSystemWear(dt, systemKey, wearRate, {
        deepDischargeFactor = deepDischargeFactor,
        highDrawFactor = highDrawFactor,
        batteryHeatFactor = batteryHeatFactor,
        currentFuelUsageRatio = fuelState.currentUsageRatio,
        fuelLevel = fuelState.level
    })
end

---Wears the fuel system on starvation, cold fuel, deposits and pressure
function RealisticMechanicalSystems:updateFuelSystem(dt)
    local spec = self.spec_RealisticMechanicalSystems
    local systemKey = RMS_Utils.getSystemKey(RealisticMechanicalSystems.SYSTEMS, spec.systems.fuel.name)
    local systemData = spec.systems.fuel
    if systemData == nil then return end
    local lowFuelStarvationFactor, coldFuelFactor = 0, 0
    local expiredServiceFactor, fuelLevel, fuelTemperature, idleDepositFactor, highPressureFactor = 0, 0, 0, 0, 0
    local currentFuelUsageRatio = 0
    local C = RMS_Config.CORE.FUEL_FACTOR_DATA
    local wearRate = 1.0
    local fuelState = spec.fuelState

    if not systemData.enabled then
        return
    end

    if spec.isElectricVehicle then
        updateTractionBatterySystem(self, dt, systemKey)
        return
    end

    if self.getIsMotorStarted ~= nil and self:getIsMotorStarted() then
        local motorLoad = self:getMotorLoadPercentage()
        fuelLevel = fuelState.level
        currentFuelUsageRatio = fuelState.currentUsageRatio

        if fuelLevel < C.LOW_FUEL_THRESHOLD then
            lowFuelStarvationFactor = RMS_Utils.calculateQuadraticMultiplier(fuelLevel, C.LOW_FUEL_THRESHOLD, true)
            local motorLoadInf = 1 + RMS_Utils.calculateQuadraticMultiplier(motorLoad, 0.70, false)
            lowFuelStarvationFactor = lowFuelStarvationFactor * motorLoadInf * C.LOW_FUEL_FACTOR_MULTIPLIER
            wearRate = wearRate + lowFuelStarvationFactor
        end

        fuelTemperature = fuelState.temperature
        if fuelTemperature < C.COLD_FUEL_THRESHOLD and motorLoad > 0.5 and not self:getIsAIActive() then
            coldFuelFactor = RMS_Utils.calculateQuadraticMultiplier(fuelTemperature, C.COLD_FUEL_THRESHOLD, true)
            local motorLoadInf = RMS_Utils.calculateQuadraticMultiplier(motorLoad, 0.50, false)
            coldFuelFactor = coldFuelFactor * motorLoadInf * C.COLD_FUEL_FACTOR_MULTIPLIER
            coldFuelFactor = math.min(coldFuelFactor, C.COLD_FUEL_FACTOR_MULTIPLIER or coldFuelFactor)
            wearRate = wearRate + coldFuelFactor
        end

        local idleTimer = math.max(tonumber(fuelState.idleTimer) or 0, 0)
        if idleTimer >= C.IDLE_DEPOSIT_FACTOR_TIMER_THRESHOLD then
            idleDepositFactor = RMS_Utils.calculateQuadraticMultiplier(
                idleTimer,
                C.IDLE_DEPOSIT_FACTOR_TIMER_THRESHOLD,
                false,
                C.IDLE_DEPOSIT_FACTOR_MAX_TIMER
            )
            idleDepositFactor = idleDepositFactor * C.IDLE_DEPOSIT_FACTOR_MULTIPLIER
            wearRate = wearRate + idleDepositFactor
        end

        local highPressureThreshold = tonumber(C.HIGH_PRESSURE_FACTOR_THRESHOLD) or 0.8
        if currentFuelUsageRatio > highPressureThreshold then
            highPressureFactor = RMS_Utils.calculateQuadraticMultiplier(currentFuelUsageRatio, highPressureThreshold, false)
            highPressureFactor = math.min(highPressureFactor * C.HIGH_PRESSURE_FACTOR_MULTIPLIER, C.HIGH_PRESSURE_FACTOR_MULTIPLIER)
            wearRate = wearRate + highPressureFactor
        end

        expiredServiceFactor = getExpiredServiceFactor(self, "fuel", C.SERVICE_EXPIRED_MULTIPLIER)
        wearRate = wearRate + expiredServiceFactor
    else
        wearRate = getPassiveWearRate(wearRate, spec.isUnderRoof)
    end

    self:updateSystemWear(dt, systemKey, wearRate, {
        expiredServiceFactor = expiredServiceFactor,
        lowFuelStarvationFactor = lowFuelStarvationFactor,
        coldFuelFactor = coldFuelFactor,
        idleDepositFactor = idleDepositFactor,
        highPressureFactor = highPressureFactor,
        currentFuelUsageRatio = currentFuelUsageRatio,
        idleTimer = fuelState.idleTimer,
        fuelLevel = fuelLevel,
        fuelTemperature = fuelTemperature
    })
end
