-- Copyright © 2026 Squallqt. All rights reserved.

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

---Runs the hourly service clocks down while the engine runs
function RealisticMechanicalSystems:updateServiceLevel(dt)
    local spec = self.spec_RealisticMechanicalSystems
    if isMissionVehicle(self) then
        return
    end

    local hourlyWear = self:getIsMotorStarted() and RMS_Config.CORE.BASE_SERVICE_WEAR * (1 + spec.extraServiceWear) or 0
    for _, clock in ipairs(self:getServiceClocks()) do
        if clock.intervalFactor ~= nil then
            spec[clock.levelKey] = math.max((spec[clock.levelKey] or spec.baseServiceLevel)
                - hourlyWear / clock.intervalFactor / 3600000 * dt, 0)
        end
    end
end

---Sets the condition of the machine, each system weighed by its share
function RealisticMechanicalSystems:updateConditionLevel()
    local spec = self.spec_RealisticMechanicalSystems
    local weights = RMS_Config.CORE.SYSTEM_WEIGHTS
    local weighted, totalWeight = 0, 0
    for systemKey, system in pairs(spec.systems) do
        local weight = weights[systemKey] or 0
        if system.enabled ~= false and weight > 0 then
            weighted = weighted + system.condition * weight
            totalWeight = totalWeight + weight
        end
    end
    spec.conditionLevel = totalWeight > 0 and math.clamp(weighted / totalWeight, 0.001, 1.0) or 1.0
end

function RealisticMechanicalSystems:updateSystemWear(dt, systemKey, wearRate, factors)
    local spec = self.spec_RealisticMechanicalSystems
    local reliability = math.max(spec.reliability, 0.001)
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

-- the wear of a system this update: its rate, each cause listed at 0
local function startWear(rate, causes)
    local wear = { rate = rate, factors = {} }
    for _, name in ipairs(causes) do
        wear.factors[name] = 0
    end
    return wear
end

local function addCause(wear, name, value)
    wear.factors[name] = value
    wear.rate = wear.rate + value
end

local function finishWear(vehicle, dt, systemKey, wear, readings)
    for name, value in pairs(readings) do
        wear.factors[name] = value
    end
    vehicle:updateSystemWear(dt, systemKey, wear.rate, wear.factors)
end

local function getEngineTemperature(spec)
    return sanitizeNumber(spec.rawEngineTemperature or spec.engineTemperature, -99, -99, 160)
end

-- an engine idling on a machine standing still wears little
local function getIsIdling(vehicle, motorLoad)
    return motorLoad < RMS_Config.CORE.ENGINE_FACTOR_DATA.MOTOR_IDLING_THRESHOLD and vehicle:getLastSpeed() < 0.003
end

-- a stopped machine still ages outdoors
local function wearStopped(wear, spec)
    wear.rate = getPassiveWearRate(wear.rate, spec.isUnderRoof)
end

local function updateElectricMotorSystem(vehicle, dt, systemKey)
    local spec = vehicle.spec_RealisticMechanicalSystems
    local C = RMS_Config.ELECTRIC_DRIVE
    local wear = startWear(1.0, { "motorLoadFactor", "hotMotorFactor" })
    local temperature = getEngineTemperature(spec)

    if vehicle:getIsMotorStarted() then
        local motorLoad = vehicle:getMotorLoadPercentage()
        if spec.dynamicMotorLoad > C.MOTOR_OVERLOADED_THRESHOLD then
            addCause(wear, "motorLoadFactor", RMS_Utils.calculateQuadraticMultiplier(spec.dynamicMotorLoad, C.MOTOR_OVERLOADED_THRESHOLD, false,
                C.MOTOR_OVERLOADED_MAX_EFFECT) * C.MOTOR_OVERLOADED_MULTIPLIER)
        end

        local overheatThreshold, overheatFullEffect = getOverheatWearRange(spec)
        if temperature > overheatThreshold and motorLoad > 0.3 then
            local heat = RMS_Utils.calculateQuadraticMultiplier(temperature, overheatThreshold, false, overheatFullEffect)
                * RMS_Utils.calculateQuadraticMultiplier(motorLoad, 0.3, false) * C.MOTOR_OVERHEAT_MULTIPLIER
            addCause(wear, "hotMotorFactor", math.min(heat, C.MOTOR_OVERHEAT_MULTIPLIER))
        end

        if getIsIdling(vehicle, motorLoad) then
            wear.rate = wear.rate * C.MOTOR_STANDSTILL_MULTIPLIER
        end
    else
        wearStopped(wear, spec)
    end

    finishWear(vehicle, dt, systemKey, wear, { dynamicMotorLoad = spec.dynamicMotorLoad, engineTemperature = temperature })
end

local ENGINE_CAUSES = { "motorLoadFactor", "lowFluidFactor", "luggingFactor", "airFilterCloggingFactor", "expiredServiceFactor",
    "coldMotorFactor", "hotMotorFactor" }

---Wears the engine on load, lugging, clogging, temperature and service
function RealisticMechanicalSystems:updateEngineSystem(dt)
    local spec = self.spec_RealisticMechanicalSystems
    local system = spec.systems.engine
    if not system.enabled then
        return
    end
    local systemKey = RMS_Utils.getSystemKey(RealisticMechanicalSystems.SYSTEMS, system.name)
    if spec.isElectricVehicle then
        updateElectricMotorSystem(self, dt, systemKey)
        return
    end

    local C = RMS_Config.CORE.ENGINE_FACTOR_DATA
    local wear = startWear(1.0, ENGINE_CAUSES)
    local temperature = getEngineTemperature(spec)
    if self:getIsMotorStarted() then
        local motorLoad, dynamicLoad = self:getMotorLoadPercentage(), spec.dynamicMotorLoad

        -- past the strongest engine of the same block
        local overloadRatio = RMS_EngineRemap.getOverloadRatio(self)
        local overloadThreshold = C.MOTOR_OVERLOADED_THRESHOLD * overloadRatio
        if dynamicLoad > overloadThreshold then
            local overload = RMS_Utils.calculateQuadraticMultiplier(dynamicLoad, overloadThreshold, false, C.MOTOR_OVERLOADED_MAX_EFFECT * overloadRatio)
            addCause(wear, "motorLoadFactor", math.clamp(overload * C.MOTOR_OVERLOADED_MULTIPLIER, 0, C.MOTOR_OVERLOADED_MULTIPLIER))
        end

        if dynamicLoad > C.LUGGING_MOTORLOAD_THRESHOLD and self:getLastSpeed() > 0.5 then
            addCause(wear, "luggingFactor", RMS_Utils.getEngineLuggingSeverity(self.spec_motorized.motor, dynamicLoad, C.LUGGING_MOTORLOAD_THRESHOLD)
                * C.LUGGING_MULTIPLIER)
        end

        if spec.airFilterClogging > C.AIR_FILTER_CLOGGING_THRESHOLD then
            addCause(wear, "airFilterCloggingFactor", RMS_Utils.calculateQuadraticMultiplier(spec.airFilterClogging, C.AIR_FILTER_CLOGGING_THRESHOLD, false)
                * C.AIR_FILTER_CLOGGING_MULTIPLIER)
        end

        local coldStress = getColdEngineStress(self)
        if coldStress > 0 then
            addCause(wear, "coldMotorFactor", coldStress * C.COLD_MOTOR_MULTIPLIER)
        elseif temperature > C.OVERHEAT_MOTOR_THRESHOLD and motorLoad > 0.3 then
            local heat = RMS_Utils.calculateQuadraticMultiplier(temperature, C.OVERHEAT_MOTOR_THRESHOLD, false, 120) * C.OVERHEAT_MOTOR_MULTIPLIER
                * RMS_Utils.calculateQuadraticMultiplier(motorLoad, 0.3, false)
            addCause(wear, "hotMotorFactor", math.min(heat, C.OVERHEAT_MOTOR_MULTIPLIER))
        end

        if getIsIdling(self, motorLoad) then
            wear.rate = wear.rate * C.MOTOR_IDLING_MULTIPLIER
        end
        addCause(wear, "expiredServiceFactor", getExpiredServiceFactor(self, "engine", C.SERVICE_EXPIRED_MULTIPLIER))
        addCause(wear, "lowFluidFactor", RMS_Utils.getFluidShortage(spec.engineOilLevel) * RMS_Config.FLUIDS.LOW_LEVEL_WEAR_MULTIPLIER)
    else
        wearStopped(wear, spec)
    end

    finishWear(self, dt, systemKey, wear, { dynamicMotorLoad = spec.dynamicMotorLoad, engineTemperature = temperature })
end

-- seconds of pull before full wear, rising with the overload up to 1.15
local function getPullOverloadTargetTime(C, driveLoad)
    if driveLoad <= C.PULL_OVERLOAD_THRESHOLD then
        return 0
    end
    local timerMax = C.PULL_OVERLOAD_TIMER_MAX_EFFECT
    local timerMin = math.max(2 * C.PULL_OVERLOAD_TIMER_THRESHOLD - timerMax, 0)
    local loadRatio = math.clamp((driveLoad - C.PULL_OVERLOAD_THRESHOLD) / math.max(1.15 - C.PULL_OVERLOAD_THRESHOLD, 0.001), 0.0, 1.0)
    return timerMin + (timerMax - timerMin) * loadRatio
end

local function moveTutorialTimer(spec, key, isOn, dt, ceiling)
    spec[key] = isOn and math.min(spec[key] + dt, ceiling) or math.max(spec[key] - dt, 0)
end

local TRANSMISSION_CAUSES = { "expiredServiceFactor", "pullOverloadFactor", "lowFluidFactor", "filterBypassFactor",
    "transmissionFilterBypassFactor", "heavyTrailerFactor", "luggingFactor", "wheelSlipFactor", "drivetrainWindupFactor",
    "coldTransFactor", "hotTransFactor" }

-- the driven work of the transmission, its gearbox in good order
local function addTransmissionWork(vehicle, wear, system, driveLoad, transTemp, dt)
    local spec = vehicle.spec_RealisticMechanicalSystems
    local C = RMS_Config.CORE.TRANSMISSION_FACTOR_DATA
    local motor = vehicle.spec_motorized.motor
    local motorLoad, speed = vehicle:getMotorLoadPercentage(), vehicle:getLastSpeed()

    local pullTarget = getPullOverloadTargetTime(C, driveLoad)
    system.pullOverloadTimerMin = pullTarget
    if system.pullOverloadTimer < pullTarget then
        system.pullOverloadTimer = math.min(system.pullOverloadTimer + dt / 1000, pullTarget)
    elseif system.pullOverloadTimer > pullTarget then
        system.pullOverloadTimer = math.max(system.pullOverloadTimer - dt / 1000, pullTarget)
    end
    if speed > 0.5 and driveLoad > C.PULL_OVERLOAD_THRESHOLD and system.pullOverloadTimer > 0 then
        local pull = RMS_Utils.calculateQuadraticMultiplier(system.pullOverloadTimer, 0, false, C.PULL_OVERLOAD_TIMER_MAX_EFFECT)
        local severity = math.clamp((driveLoad - C.PULL_OVERLOAD_THRESHOLD) / (1.15 - C.PULL_OVERLOAD_THRESHOLD), 0, 1)
        addCause(wear, "pullOverloadFactor", math.clamp(pull * severity * severity * C.PULL_OVERLOAD_MULTIPLIER, 0, C.PULL_OVERLOAD_MULTIPLIER))
    end

    if not spec.isElectricVehicle and driveLoad > C.LUGGING_MOTORLOAD_THRESHOLD and speed > 0.5 then
        addCause(wear, "luggingFactor", RMS_Utils.getEngineLuggingSeverity(motor, driveLoad, C.LUGGING_MOTORLOAD_THRESHOLD) * C.LUGGING_MULTIPLIER)
    end
    moveTutorialTimer(spec, "luggingTutorialTimer", wear.factors.luggingFactor > 0, dt, 5000)

    local isTruck = spec.isTruck == true
    local brakeState = spec.chassisBrakeState
    local trailerRatio = isTruck and brakeState.hpGrossMassRatio or brakeState.hpTrailerMassRatio
    local ratioThreshold, fullEffectRatio = RMS_Utils.getHeavyTrailerRatioLevels(isTruck)
    if math.max(brakeState.trailerMass, 0) > 0.1 and trailerRatio < ratioThreshold and motorLoad > C.HEAVY_TRAILER_MOTORLOAD_THRESHOLD and speed > 0.5 then
        local trailer = RMS_Utils.calculateQuadraticMultiplier(trailerRatio, ratioThreshold, true, fullEffectRatio)
        local loadRatio = math.clamp((motorLoad - C.HEAVY_TRAILER_MOTORLOAD_THRESHOLD) / math.max(1.0 - C.HEAVY_TRAILER_MOTORLOAD_THRESHOLD, 0.001), 0, 1.0)
        trailer = math.max(trailer * C.HEAVY_TRAILER_MULTIPLIER * loadRatio, 0)
        addCause(wear, "heavyTrailerFactor", math.min(trailer, C.HEAVY_TRAILER_MULTIPLIER))
    end

    local isSlipping = not RMS_Drivetrain.getIsTurning(vehicle) and spec.wheelSlipIntensity > C.WHEEL_SLIP_THRESHOLD and speed < 20
        and motorLoad > 0.5 and (speed > 0.5 or not vehicle:getIsAIActive())
    if isSlipping then
        local slip = RMS_Utils.calculateQuadraticMultiplier(spec.wheelSlipIntensity, C.WHEEL_SLIP_THRESHOLD, false)
        addCause(wear, "wheelSlipFactor", math.max(slip * C.WHEEL_SLIP_MULTIPLIER * (spec.avgTireGroundFrictionCoeff ^ 2) * motorLoad, 0))
    end
    moveTutorialTimer(spec, "wheelSlipTutorialTimer", isSlipping, dt, 3000)

    local windup = RMS_Drivetrain.getWindupWearFactor(vehicle)
    if windup > 0 then
        addCause(wear, "drivetrainWindupFactor", windup)
    end

    if hasCVTTransmission(vehicle) and transTemp > C.OVERHEAT_TRANSMISSION_THRESHOLD and motorLoad > 0.3 then
        local heat = RMS_Utils.calculateQuadraticMultiplier(transTemp, C.OVERHEAT_TRANSMISSION_THRESHOLD, false, 120)
            * C.OVERHEAT_TRANSMISSION_MAX_MULTIPLIER * RMS_Utils.calculateQuadraticMultiplier(motor:getLastRealMotorRpm() / motor.maxRpm, 0.5, false)
        addCause(wear, "hotTransFactor", math.min(heat, C.OVERHEAT_TRANSMISSION_MAX_MULTIPLIER))
    end

    if getIsIdling(vehicle, motorLoad) then
        wear.rate = wear.rate * C.TRANSMISSION_IDLING_MULTIPLIER
    end
    addCause(wear, "expiredServiceFactor", getExpiredServiceFactor(vehicle, "transmission", C.SERVICE_EXPIRED_MULTIPLIER))
end

---Wears the transmission on pull, trailer, lugging, slip, windup and oil
function RealisticMechanicalSystems:updateTransmissionSystem(dt)
    local spec = self.spec_RealisticMechanicalSystems
    local system = spec.systems.transmission
    system.pullOverloadTimer = system.pullOverloadTimer or 0
    if not system.enabled then
        return
    end

    local C = RMS_Config.CORE.TRANSMISSION_FACTOR_DATA
    local motor = self.spec_motorized.motor
    -- other consumers load the engine, not the drive
    local applied = sanitizeNumber(motor:getMotorAppliedTorque(), 0, 0)
    local external = sanitizeNumber(motor:getMotorExternalTorque(), 0, 0)
    local driveShare = applied > 0 and math.clamp((applied - external) / applied, 0, 1) or 0
    local driveLoad = spec.dynamicMotorLoad * driveShare
    local transTemp = sanitizeNumber(spec.rawTransmissionTemperature or spec.transmissionTemperature, -99, -99, 180)
    local isRunning = self:getIsMotorStarted()
    local wear = startWear(1.0, TRANSMISSION_CAUSES)

    if isRunning and not self:getIsAIActive() then
        local drivelineLoad = RMS_Drivetrain.getDrivelineLoad(self)
        if transTemp < C.COLD_TRANSMISSION_THRESHOLD and drivelineLoad > C.COLD_TRANSMISSION_LOAD_THRESHOLD then
            local cold = RMS_Utils.calculateQuadraticMultiplier(transTemp, C.COLD_TRANSMISSION_THRESHOLD, true)
                * RMS_Utils.calculateQuadraticMultiplier(drivelineLoad, C.COLD_TRANSMISSION_LOAD_THRESHOLD, false)
            addCause(wear, "coldTransFactor", math.min(cold * C.COLD_TRANSMISSION_MULTIPLIER, C.COLD_TRANSMISSION_MULTIPLIER))
        end
    end

    -- the transmission addon owns the wear of its gearbox
    if hasCVTAddon(self) and isRunning then
        if getIsIdling(self, self:getMotorLoadPercentage()) then
            wear.rate = wear.rate * C.TRANSMISSION_IDLING_MULTIPLIER
        end
    elseif isRunning then
        addTransmissionWork(self, wear, system, driveLoad, transTemp, dt)
    else
        wearStopped(wear, spec)
    end

    if isRunning then
        addCause(wear, "lowFluidFactor", RMS_Utils.getFluidShortage(spec.transmissionOilLevel) * RMS_Config.FLUIDS.LOW_LEVEL_WEAR_MULTIPLIER)
        if RMS_Fluids.getSumpCircuit(self, "hydraulicFluid") == "transmissionOil" then
            addCause(wear, "filterBypassFactor", getFilterBypassFactor(spec, wear.rate))
        else
            addCause(wear, "transmissionFilterBypassFactor", getFilterBypassFactor(spec, wear.rate, "transmissionFilterClogging"))
        end
    end

    local brakeState = spec.chassisBrakeState
    finishWear(self, dt, RMS_Utils.getSystemKey(RealisticMechanicalSystems.SYSTEMS, system.name), wear, {
        pullOverloadTimer = system.pullOverloadTimer, pullOverloadTimerMin = system.pullOverloadTimerMin,
        heavyTrailerMassRatio = spec.isTruck == true and brakeState.hpGrossMassRatio or brakeState.hpTrailerMassRatio,
        heavyTrailerMassBasis = spec.isTruck == true and "gcw" or "trailer" })
end

local HYDRAULICS_CAUSES = { "expiredServiceFactor", "heavyLiftFactor", "lowFluidFactor", "filterBypassFactor", "vibFactor",
    "operatingFactor", "coldOilFactor", "hotOilFactor" }

-- the oil the pump works: its own circuit, or the transmission it shares
local function getHydraulicOilTemperature(spec)
    local transmission = spec.rawTransmissionTemperature or spec.transmissionTemperature
    local temperature = RMS_Thermal.getHasSeparateHydraulicCircuit(spec) and (spec.rawHydraulicTemperature or spec.hydraulicTemperature)
        or transmission
    return sanitizeNumber(temperature, transmission or 20, -80, 180)
end

---Wears the hydraulics on pump, lift load, vibration, cylinders and oil
function RealisticMechanicalSystems:updateHydraulicsSystem(dt)
    local spec = self.spec_RealisticMechanicalSystems
    local system = spec.systems.hydraulics
    if not system.enabled then
        return
    end

    local C = RMS_Config.CORE.HYDRAULICS_FACTOR_DATA
    local vibration = RMS_Config.CORE.CHASSIS_FACTOR_DATA
    local mass = self:getTotalMass(true)
    local liftRatio = mass > 0 and math.max(spec.liftedMass, 0) / mass or 0
    local vibSignal = spec.chassisVibState.smoothed
    local isRunning = self:getIsMotorStarted()
    local wear = startWear(0, HYDRAULICS_CAUSES)

    if isRunning then
        wear.rate = C.PUMP_WEAR_RATE
        addCause(wear, "heavyLiftFactor", mass > 0 and math.min(spec.raisingMass / mass, 1) or 0)
    end

    if isRunning and spec.isImplementLifted and self:getLastSpeed() > 0.003 and vibSignal > vibration.VIB_FACTOR_THRESHOLD then
        local vibMultiplier = vibration.VIB_FACTOR_MULTIPLIER * math.min(liftRatio / C.VIB_FULL_LIFT_MASS_RATIO, 1)
        local vib = RMS_Utils.calculateQuadraticMultiplier(vibSignal, vibration.VIB_FACTOR_THRESHOLD, false,
            math.max(vibration.VIB_FACTOR_MAX_SIGNAL, vibration.VIB_FACTOR_THRESHOLD + 0.001))
        addCause(wear, "vibFactor", math.min(vib * vibMultiplier, vibMultiplier))
    end

    if isRunning and spec.isHydraulicActive then
        addCause(wear, "operatingFactor", math.max(1 - C.PUMP_WEAR_RATE, 0))
        local oilTemperature = getHydraulicOilTemperature(spec)
        if oilTemperature < C.COLD_OIL_THRESHOLD and not self:getIsAIActive() then
            addCause(wear, "coldOilFactor", RMS_Utils.calculateQuadraticMultiplier(oilTemperature, C.COLD_OIL_THRESHOLD, true) * C.COLD_OIL_MULTIPLIER)
        elseif oilTemperature > C.HOT_OIL_THRESHOLD then
            local heat = RMS_Utils.calculateQuadraticMultiplier(oilTemperature, C.HOT_OIL_THRESHOLD, false, 120) * C.HOT_OIL_MULTIPLIER
            addCause(wear, "hotOilFactor", math.min(heat, C.HOT_OIL_MULTIPLIER))
        end
        addCause(wear, "expiredServiceFactor", getExpiredServiceFactor(self, "hydraulics", C.SERVICE_EXPIRED_MULTIPLIER))
    end

    if isRunning then
        addCause(wear, "lowFluidFactor", RMS_Utils.getFluidShortage(RMS_Fluids.getLevel(self, "hydraulicFluid"))
            * RMS_Config.FLUIDS.LOW_LEVEL_WEAR_MULTIPLIER)
    end
    addCause(wear, "filterBypassFactor", getFilterBypassFactor(spec, wear.rate))

    finishWear(self, dt, RMS_Utils.getSystemKey(RealisticMechanicalSystems.SYSTEMS, system.name), wear, {
        heavyLiftMassRatio = liftRatio, vibSignal = vibSignal, isHydraulicActive = spec.isHydraulicActive == true })
end

---Wears the PTO on load, a raised implement and each engagement
function RealisticMechanicalSystems:updatePtoSystem(dt)
    local spec = self.spec_RealisticMechanicalSystems
    local system = spec.systems.pto
    if system == nil or system.enabled == false then
        return
    end

    local C = RMS_Config.CORE.PTO_FACTOR_DATA
    local wear = startWear(0, { "expiredServiceFactor", "ptoLoadFactor", "ptoRaisedFactor" })
    local engagementDamage = math.max(tonumber(spec.ptoEngagementDamage) or 0, 0)
    spec.ptoEngagementDamage = 0

    if self:getIsMotorStarted() and spec.isPtoActive then
        wear.rate = 1
        local utilization = math.max(tonumber(spec.ptoUtilization) or 0, 0)
        if utilization > C.LOAD_FACTOR_THRESHOLD then
            addCause(wear, "ptoLoadFactor", RMS_Utils.calculatePtoLoadFactor(utilization, C))
        end
        if spec.isPtoImplementRaised and not self:getIsAIActive() then
            addCause(wear, "ptoRaisedFactor", C.RAISED_IMPLEMENT_MULTIPLIER)
        end
        addCause(wear, "expiredServiceFactor", getExpiredServiceFactor(self, "pto", C.SERVICE_EXPIRED_MULTIPLIER))
    end

    spec.ptoRaisedTutorialTimer = math.clamp((tonumber(spec.ptoRaisedTutorialTimer) or 0) + (wear.factors.ptoRaisedFactor > 0 and dt or -dt),
        0, C.RAISED_TUTORIAL_MS)
    spec.ptoRaisedTooLong = spec.ptoRaisedTutorialTimer >= C.RAISED_TUTORIAL_MS

    if engagementDamage > 0 then
        self:applyInstantDamageToSystem(system.name, engagementDamage, "ptoEngagementFactor")
    end

    finishWear(self, dt, RMS_Utils.getSystemKey(RealisticMechanicalSystems.SYSTEMS, system.name), wear, {
        isPtoActive = spec.isPtoActive == true, ptoEngagementDamage = engagementDamage, ptoRpm = spec.ptoRpm, ptoPower = spec.ptoPower,
        ptoUtilization = spec.ptoUtilization, ptoEngagementCount = spec.ptoEngagementCount })
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
    local system = spec.systems.cooling
    if not system.enabled then
        return
    end

    local C = RMS_Config.CORE.COOLING_FACTOR_DATA
    local wear = startWear(1.0, { "expiredServiceFactor", "highCoolingFactor", "overheatFactor", "coldShockFactor" })
    local temperature = getEngineTemperature(spec)
    if self:getIsMotorStarted() then
        local motor = self.spec_motorized.motor
        local rpmLoad = motor:getLastModulatedMotorRpm() / motor.maxRpm

        if temperature > RMS_Thermal.getDriveValues(spec).PID_TARGET_TEMP + C.HIGH_COOLING_TEMP_MARGIN
            and spec.thermostatState > C.HIGH_COOLING_FACTOR_THRESHOLD then
            local cooling = RMS_Utils.calculateQuadraticMultiplier(spec.thermostatState, C.HIGH_COOLING_FACTOR_THRESHOLD, false)
                * C.HIGH_COOLING_FACTOR_MULTIPLIER
            addCause(wear, "highCoolingFactor", math.min(cooling, C.HIGH_COOLING_FACTOR_MULTIPLIER))
        end

        local overheatThreshold, overheatFullEffect = getOverheatWearRange(spec, C.OVERHEAT_FACTOR_THRESHOLD)
        if temperature > overheatThreshold then
            local heat = RMS_Utils.calculateQuadraticMultiplier(temperature, overheatThreshold, false, overheatFullEffect) * C.OVERHEAT_FACTOR_MULTIPLIER
            addCause(wear, "overheatFactor", math.min(heat, C.OVERHEAT_FACTOR_MULTIPLIER))
        end

        if not spec.isElectricVehicle and temperature < C.COLD_SHOCK_FACTOR_THRESHOLD and rpmLoad > 0.75 and not self:getIsAIActive() then
            local shock = RMS_Utils.calculateQuadraticMultiplier(temperature, C.COLD_SHOCK_FACTOR_THRESHOLD, true) * C.COLD_SHOCK_FACTOR_MULTIPLIER
                * RMS_Utils.calculateQuadraticMultiplier(rpmLoad, 0.75, false)
            addCause(wear, "coldShockFactor", math.min(shock, C.COLD_SHOCK_FACTOR_MULTIPLIER))
        end

        if spec.thermostatState == 0 and wear.factors.overheatFactor == 0 and wear.factors.coldShockFactor == 0 then
            wear.rate = wear.rate * C.COOLING_IDLING_MULTIPLIER
        end
        addCause(wear, "expiredServiceFactor", getExpiredServiceFactor(self, "cooling", C.SERVICE_EXPIRED_MULTIPLIER))
    else
        wearStopped(wear, spec)
    end

    finishWear(self, dt, RMS_Utils.getSystemKey(RealisticMechanicalSystems.SYSTEMS, system.name), wear, {})
end

-- the machine shakes its electrics past a threshold, up to a ceiling
local function getVibrationWear(signal, C, multiplier)
    local vib = RMS_Utils.calculateQuadraticMultiplier(signal, C.VIB_FACTOR_THRESHOLD, false,
        math.max(C.VIB_FACTOR_MAX_SIGNAL, C.VIB_FACTOR_THRESHOLD + 0.001))
    return math.min(vib * multiplier, multiplier)
end

local WEATHER_MULTIPLIERS = { { "RAIN", "RAIN_FACTOR_MULTIPLIER" }, { "SNOW", "SNOW_FACTOR_MULTIPLIER" }, { "HAIL", "HAIL_FACTOR_MULTIPLIER" } }

---Wears the electrics on cranking, weather, lights, heat and vibration
function RealisticMechanicalSystems:updateElectricalSystem(dt)
    local spec = self.spec_RealisticMechanicalSystems
    local system = spec.systems.electrical
    if not system.enabled then
        return
    end

    local C = RMS_Config.CORE.ELECTRICAL_FACTOR_DATA
    local vibState = spec.chassisVibState
    local wear = startWear(1.0, { "crankingStressFactor", "weatherExposureFactor", "lightsFactor", "overheatFactor", "vibFactor" })

    local lights = self.spec_lights
    if lights ~= nil and bit32.band(self:getLightsTypesMask(), lights.maxLightStateMask) > 0 then
        addCause(wear, "lightsFactor", C.LIGHTS_FACTOR_MULTIPLIER)
    end

    if not spec.isUnderRoof then
        local multiplier = 0
        for _, weather in ipairs(WEATHER_MULTIPLIERS) do
            if RMS_Main.currentWeather == WeatherType[weather[1]] then
                multiplier = C[weather[2]]
                break
            end
        end
        addCause(wear, "weatherExposureFactor", multiplier)
    end

    system.crankingTimer = system.crankingTimer or 0
    if spec.isCranking then
        system.crankingTimer = math.min(system.crankingTimer + dt, 10000)
        if system.crankingTimer > 3500 then
            addCause(wear, "crankingStressFactor", C.CRANKING_STRESS_MULTIPLIER)
        end
    else
        system.crankingTimer = math.max(system.crankingTimer - dt / 100, 0)
    end

    if self:getIsMotorStarted() then
        local temperature = getEngineTemperature(spec)
        local overheatThreshold, overheatFullEffect = getOverheatWearRange(spec, C.OVERHEAT_FACTOR_THRESHOLD)
        if temperature > overheatThreshold then
            local heat = RMS_Utils.calculateQuadraticMultiplier(temperature, overheatThreshold, false, overheatFullEffect) * C.OVERHEAT_FACTOR_MULTIPLIER
            addCause(wear, "overheatFactor", math.min(heat, C.OVERHEAT_FACTOR_MULTIPLIER))
        end
        if vibState.smoothed > C.VIB_FACTOR_THRESHOLD then
            addCause(wear, "vibFactor", getVibrationWear(vibState.smoothed, C, C.VIB_FACTOR_MULTIPLIER))
        end
    elseif wear.factors.lightsFactor == 0 and wear.factors.crankingStressFactor == 0 then
        wearStopped(wear, spec)
    end

    finishWear(self, dt, RMS_Utils.getSystemKey(RealisticMechanicalSystems.SYSTEMS, system.name), wear, {
        crankingTimer = system.crankingTimer, vibSignal = vibState.signal, vibRaw = vibState.raw })
end

local CHASSIS_CAUSES = { "lubricationFactor", "vibFactor", "steerLoadFactor", "steerLowSpeedFactor", "brakeMassFactor",
    "parkBrakeDragFactor" }

-- a trailer braked by a light machine wears its brakes, by the pedal
local function getBrakeMassWear(spec, C)
    local brakeState = spec.chassisBrakeState
    local isTruck = spec.isTruck == true
    local ratio = isTruck and brakeState.hpGrossMassRatio or brakeState.hpTrailerMassRatio
    local threshold = isTruck and C.BRAKE_MASS_TRUCK_RATIO_THRESHOLD or C.BRAKE_MASS_RATIO_THRESHOLD
    if ratio >= threshold then
        return 0
    end
    local fullEffect = isTruck and C.BRAKE_MASS_TRUCK_RATIO_FULL_EFFECT or C.BRAKE_MASS_RATIO_FULL_EFFECT
    local wear = RMS_Utils.calculateQuadraticMultiplier(ratio, threshold, true, fullEffect) * brakeState.pedal * C.BRAKE_MASS_FACTOR_MULTIPLIER
    return math.min(wear, C.BRAKE_MASS_FACTOR_MULTIPLIER)
end

---Wears the chassis on vibration, steering, braking and lubrication
function RealisticMechanicalSystems:updateChassisSystem(dt)
    local spec = self.spec_RealisticMechanicalSystems
    local system = spec.systems.chassis
    if not system.enabled then
        return
    end

    local C = RMS_Config.CORE.CHASSIS_FACTOR_DATA
    local vibState, steerState, brakeState = spec.chassisVibState, spec.chassisSteerState, spec.chassisBrakeState
    local speed = self:getLastSpeed()
    local wear = startWear(1.0, CHASSIS_CAUSES)

    if self:getIsMotorStarted() then
        if spec.isVehicleNeedLubricate then
            addCause(wear, "lubricationFactor", RMS_Greasing.getWearFactor(self) - 1)
        end

        if speed > 0.003 then
            if vibState.smoothed > C.VIB_FACTOR_THRESHOLD then
                addCause(wear, "vibFactor", getVibrationWear(vibState.smoothed, C, C.VIB_FACTOR_MULTIPLIER))
            end
            if math.max(brakeState.trailerMass, 0) > 0.1 and brakeState.isBraking and speed > C.BRAKE_MASS_SPEED_THRESHOLD then
                addCause(wear, "brakeMassFactor", getBrakeMassWear(spec, C))
            end
            addCause(wear, "parkBrakeDragFactor", RMS_Drivetrain.getParkBrakeDragFactor(self))
        else
            wear.rate = wear.rate * C.CHASSIS_IDLING_MULTIPLIER
        end

        if steerState.groundContact > 0 and not self:getIsAIActive() then
            local lowSpeed = RMS_Utils.calculateQuadraticMultiplier(speed, C.STEER_LOAD_SPEED_THRESHOLD, true)
            wear.factors.steerLowSpeedFactor = lowSpeed
            addCause(wear, "steerLoadFactor", C.STEER_LOAD_FACTOR_MULTIPLIER * steerState.travelRate * lowSpeed
                * spec.avgTireGroundFrictionCoeff * steerState.axleLoadRatio)
        end
    else
        wearStopped(wear, spec)
    end

    local effects = spec.activeEffects
    finishWear(self, dt, RMS_Utils.getSystemKey(RealisticMechanicalSystems.SYSTEMS, system.name), wear, {
        vibSignal = vibState.signal, vibRaw = vibState.raw, impactCount = spec.terrainImpacts.count,
        impactSpeedLoss = spec.terrainImpacts.lastSpeedLoss,
        steerPlay = effects.STEERING_PLAY_EFFECT ~= nil and effects.STEERING_PLAY_EFFECT.value or 0,
        steerPull = effects.STEERING_STATIC_BIAS_EFFECT ~= nil and effects.STEERING_STATIC_BIAS_EFFECT.value or 0,
        steerGroundFrictionCoeff = spec.avgTireGroundFrictionCoeff, steerTravelRate = steerState.travelRate,
        steerAxleLoadRatio = steerState.axleLoadRatio,
        brakeMassRatio = spec.isTruck == true and brakeState.hpGrossMassRatio or brakeState.hpTrailerMassRatio,
        brakeMassBasis = spec.isTruck == true and "gcw" or "trailer" })
end

local function updateTractionBatterySystem(vehicle, dt, systemKey)
    local spec = vehicle.spec_RealisticMechanicalSystems
    local C = RMS_Config.ELECTRIC_DRIVE
    local fuelState = spec.fuelState
    local wear = startWear(1.0, { "deepDischargeFactor", "highDrawFactor", "batteryHeatFactor" })

    if vehicle:getIsMotorStarted() then
        if spec.tractionBatteryTempC > C.BATTERY_HEAT_THRESHOLD then
            local heat = RMS_Utils.calculateQuadraticMultiplier(spec.tractionBatteryTempC, C.BATTERY_HEAT_THRESHOLD, false, C.BATTERY_HEAT_FULL_EFFECT)
            addCause(wear, "batteryHeatFactor", math.min(heat * C.BATTERY_HEAT_MULTIPLIER, C.BATTERY_HEAT_MULTIPLIER))
        end
        if fuelState.level < C.DEEP_DISCHARGE_THRESHOLD then
            local loadShare = 1 + RMS_Utils.calculateQuadraticMultiplier(vehicle:getMotorLoadPercentage(), 0.70, false)
            addCause(wear, "deepDischargeFactor", RMS_Utils.calculateQuadraticMultiplier(fuelState.level, C.DEEP_DISCHARGE_THRESHOLD, true)
                * loadShare * C.DEEP_DISCHARGE_MULTIPLIER)
        end
        if fuelState.currentUsageRatio > C.HIGH_DRAW_THRESHOLD then
            local draw = RMS_Utils.calculateQuadraticMultiplier(fuelState.currentUsageRatio, C.HIGH_DRAW_THRESHOLD, false)
            addCause(wear, "highDrawFactor", math.min(draw * C.HIGH_DRAW_MULTIPLIER, C.HIGH_DRAW_MULTIPLIER))
        end
    else
        wearStopped(wear, spec)
    end

    finishWear(vehicle, dt, systemKey, wear, { currentFuelUsageRatio = fuelState.currentUsageRatio, fuelLevel = fuelState.level })
end

local FUEL_CAUSES = { "expiredServiceFactor", "lowFuelStarvationFactor", "coldFuelFactor", "idleDepositFactor", "highPressureFactor" }

---Wears the fuel system on starvation, cold fuel, deposits and pressure
function RealisticMechanicalSystems:updateFuelSystem(dt)
    local spec = self.spec_RealisticMechanicalSystems
    local system = spec.systems.fuel
    if not system.enabled then
        return
    end
    local systemKey = RMS_Utils.getSystemKey(RealisticMechanicalSystems.SYSTEMS, system.name)
    if spec.isElectricVehicle then
        updateTractionBatterySystem(self, dt, systemKey)
        return
    end

    local C = RMS_Config.CORE.FUEL_FACTOR_DATA
    local fuelState = spec.fuelState
    local wear = startWear(1.0, FUEL_CAUSES)
    local readings = { currentFuelUsageRatio = 0, idleTimer = fuelState.idleTimer, fuelLevel = 0, fuelTemperature = 0 }

    if self:getIsMotorStarted() then
        local motorLoad = self:getMotorLoadPercentage()
        local level, temperature, usage = fuelState.level, fuelState.temperature, fuelState.currentUsageRatio
        readings.fuelLevel, readings.fuelTemperature, readings.currentFuelUsageRatio = level, temperature, usage

        if level < C.LOW_FUEL_THRESHOLD then
            local loadShare = 1 + RMS_Utils.calculateQuadraticMultiplier(motorLoad, 0.70, false)
            addCause(wear, "lowFuelStarvationFactor", RMS_Utils.calculateQuadraticMultiplier(level, C.LOW_FUEL_THRESHOLD, true) * loadShare
                * C.LOW_FUEL_FACTOR_MULTIPLIER)
        end

        if temperature < C.COLD_FUEL_THRESHOLD and motorLoad > 0.5 and not self:getIsAIActive() then
            local cold = RMS_Utils.calculateQuadraticMultiplier(temperature, C.COLD_FUEL_THRESHOLD, true)
                * RMS_Utils.calculateQuadraticMultiplier(motorLoad, 0.50, false) * C.COLD_FUEL_FACTOR_MULTIPLIER
            addCause(wear, "coldFuelFactor", math.min(cold, C.COLD_FUEL_FACTOR_MULTIPLIER))
        end

        local idleTime = math.max(fuelState.idleTimer, 0)
        if idleTime >= C.IDLE_DEPOSIT_FACTOR_TIMER_THRESHOLD then
            addCause(wear, "idleDepositFactor", RMS_Utils.calculateQuadraticMultiplier(idleTime, C.IDLE_DEPOSIT_FACTOR_TIMER_THRESHOLD, false,
                C.IDLE_DEPOSIT_FACTOR_MAX_TIMER) * C.IDLE_DEPOSIT_FACTOR_MULTIPLIER)
        end

        if usage > C.HIGH_PRESSURE_FACTOR_THRESHOLD then
            local pressure = RMS_Utils.calculateQuadraticMultiplier(usage, C.HIGH_PRESSURE_FACTOR_THRESHOLD, false)
            addCause(wear, "highPressureFactor", math.min(pressure * C.HIGH_PRESSURE_FACTOR_MULTIPLIER, C.HIGH_PRESSURE_FACTOR_MULTIPLIER))
        end

        addCause(wear, "expiredServiceFactor", getExpiredServiceFactor(self, "fuel", C.SERVICE_EXPIRED_MULTIPLIER))
    else
        wearStopped(wear, spec)
    end

    finishWear(self, dt, systemKey, wear, readings)
end
