-- Copyright © 2026 Squallqt. All rights reserved.

---Vehicle part wear.

local hasCVTAddon = RMS_Utils.hasCVTAddon
local ensureFactorStatsEntry = RealisticMechanicalSystems.ensureFactorStatsEntry
local getColdEngineStress = RealisticMechanicalSystems.getColdEngineStress
local isMissionVehicle = RealisticMechanicalSystems.isMissionVehicle
local sanitizeNumber = RealisticMechanicalSystems.sanitizeNumber


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

local SERVICE_LEVEL_KEY_BY_SYSTEM = {}
for _, clock in ipairs(RealisticMechanicalSystems.SERVICE_CLOCKS) do
    for _, systemKey in ipairs(clock.systems) do
        SERVICE_LEVEL_KEY_BY_SYSTEM[systemKey] = clock.levelKey
    end
end

local function getExpiredServiceFactor(vehicle, systemKey, C)
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

    local threshold = RMS_Config.CORE.SERVICE_EXPIRED_THRESHOLD
    if serviceLevel >= threshold then
        return 0
    end
    local intervals = 1 + (threshold - serviceLevel) / threshold
    local knee = RMS_Config.CORE.SERVICE_EXPIRED_KNEE[systemKey]
    if knee == nil then
        return math.min((intervals - 1) * C.SERVICE_EXPIRED_MULTIPLIER, C.SERVICE_EXPIRED_MAX)
    end
    local severity = math.clamp((intervals - knee[1]) / (knee[2] - knee[1]), 0, 1)
    local doublings = math.max(intervals - knee[2], 0) / RMS_Config.CORE.SERVICE_EXPIRED_DOUBLING
    return math.min(severity * C.SERVICE_EXPIRED_MULTIPLIER * 2 ^ doublings, C.SERVICE_EXPIRED_MAX)
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
            local volume = math.max(RMS_Fluids.getLevel(self, clock.circuits[1]), 0.01)
            spec[clock.levelKey] = math.max((spec[clock.levelKey] or spec.baseServiceLevel)
                - hourlyWear / clock.intervalFactor / volume / 3600000 * dt, 0)
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
    local isLent = isMissionVehicle(self)
    -- a lent machine does not wear; helpers ease off on its causes
    local scale = isLent and 0
        or (1 + spec.extraConditionWear) / reliability * RMS_Fluids.getSystemWearMultiplier(self, systemKey) * dtMultiplier

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
    systemStats.total = systemStats.total + (isLent and causeTotal / reliability * dtMultiplier or wearRate * scale)
    for alias, value in pairs(causeRates) do
        systemStats[alias] = (tonumber(systemStats[alias]) or 0) + value / reliability * dtMultiplier
    end

    spec.systemWearNow[systemKey] = factors
    spec.systemWearRateNow[systemKey] = wearRate * (1 + spec.extraConditionWear) / reliability
end

---Wears the parts of a system at once, the cause on the parts it reaches
function RealisticMechanicalSystems:applyInstantDamageToSystem(system, damageAmount, factorName)
    if isMissionVehicle(self) then
        return
    end

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

-- in game hours
local function getOutdoorWearRate(vehicle)
    local C = RMS_Config.CORE
    local class = C.RESALE.PROFILE_CLASSES[RMS_Fluids.getProfileName(vehicle)]
    local hoursPerYear = 12 * g_currentMission.environment.daysPerPeriod * 24
    return C.OUTDOOR_LIFE_SHARE_PER_YEAR[class == "COMBINE" and "COMBINE" or "TRACTOR"] / hoursPerYear / C.BASE_SYSTEMS_WEAR
        * g_currentMission:getEffectiveTimeScale()
end

-- a stopped machine still ages outdoors
local function wearStopped(wear, vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    wear.rate = spec.isUnderRoof and 0 or getOutdoorWearRate(vehicle)
end

local function addTorqueWear(vehicle, wear, load, C, overloadName)
    local isElectric = vehicle.spec_RealisticMechanicalSystems.isElectricVehicle
    local torque = RMS_Utils.getRatedTorqueRatio(vehicle, load)
    local rated = RMS_Config.CORE.ENGINE_FACTOR_DATA.MOTOR_OVERLOADED_THRESHOLD * RMS_EngineRemap.getOverloadRatio(vehicle)
    local lawWear = RMS_Utils.getLifeLawFactor(torque, C.TORQUE_LIFE_EXPONENT)
    -- the curve falls at very low revs, the strain on the block does not
    local lowRevWear = 0
    if not isElectric and load > C.LUGGING_MOTORLOAD_THRESHOLD and vehicle:getLastSpeed() > 0.5 then
        lowRevWear = RMS_Utils.getEngineLuggingSeverity(vehicle.spec_motorized.motor, load, C.LUGGING_MOTORLOAD_THRESHOLD)
            * C.LUGGING_MULTIPLIER
    end
    if load > rated or isElectric then
        addCause(wear, overloadName, lawWear)
        addCause(wear, "luggingFactor", lowRevWear)
    else
        addCause(wear, "luggingFactor", lawWear + lowRevWear)
    end
end

local function getNormalTop(spec)
    if spec.isElectricVehicle then
        return RMS_Config.THERMAL.PROFILES.evDrive.regulatedMax
    end
    return RMS_Config.CORE.ENGINE_FACTOR_DATA.OVERHEAT_MOTOR_THRESHOLD
end

local function updateElectricMotorSystem(vehicle, dt, systemKey)
    local spec = vehicle.spec_RealisticMechanicalSystems
    local C = RMS_Config.ELECTRIC_DRIVE
    local wear = startWear(1.0, { "motorLoadFactor", "hotMotorFactor" })
    local temperature = getEngineTemperature(spec)

    if vehicle:getIsMotorStarted() then
        local torque = RMS_Utils.getRatedTorqueRatio(vehicle, spec.dynamicMotorLoad)
        addCause(wear, "motorLoadFactor", RMS_Utils.getLifeLawFactor(torque, C.TORQUE_LIFE_EXPONENT))
        local overload = math.max(torque - 1, 0) / C.OVERLOAD_HEATING_SHARE * C.OVERLOAD_HEATING_K
        addCause(wear, "hotMotorFactor", RMS_Utils.getHeatWearFactor(temperature + overload, getNormalTop(spec)))
        if getIsIdling(vehicle, vehicle:getMotorLoadPercentage()) then
            wear.rate = wear.rate * C.MOTOR_STANDSTILL_MULTIPLIER
        end
    else
        wearStopped(wear, vehicle)
    end

    finishWear(vehicle, dt, systemKey, wear, { dynamicMotorLoad = spec.dynamicMotorLoad, engineTemperature = temperature })
end

local ENGINE_CAUSES = { "motorLoadFactor", "luggingFactor", "airFilterCloggingFactor", "expiredServiceFactor",
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
        local motorLoad = self:getMotorLoadPercentage()
        addTorqueWear(self, wear, spec.dynamicMotorLoad, C, "motorLoadFactor")

        if spec.airFilterClogging > C.AIR_FILTER_CLOGGING_THRESHOLD then
            addCause(wear, "airFilterCloggingFactor", RMS_Utils.calculateQuadraticMultiplier(spec.airFilterClogging, C.AIR_FILTER_CLOGGING_THRESHOLD, false)
                * C.AIR_FILTER_CLOGGING_MULTIPLIER)
        end

        addCause(wear, "coldMotorFactor", getColdEngineStress(self))
        addCause(wear, "hotMotorFactor", RMS_Utils.getHeatWearFactor(temperature, C.OVERHEAT_MOTOR_THRESHOLD))

        if getIsIdling(self, motorLoad) then
            wear.rate = wear.rate * C.MOTOR_IDLING_MULTIPLIER
        end
        addCause(wear, "expiredServiceFactor", getExpiredServiceFactor(self, "engine", C))
    else
        wearStopped(wear, self)
    end

    finishWear(self, dt, systemKey, wear, { dynamicMotorLoad = spec.dynamicMotorLoad, engineTemperature = temperature })
end

local function moveTutorialTimer(spec, key, isOn, dt, ceiling)
    spec[key] = isOn and math.min(spec[key] + dt, ceiling) or math.max(spec[key] - dt, 0)
end

local TRANSMISSION_CAUSES = { "expiredServiceFactor", "pullOverloadFactor", "filterBypassFactor",
    "transmissionFilterBypassFactor", "heavyTrailerFactor", "luggingFactor", "wheelSlipFactor", "drivetrainWindupFactor",
    "coldTransFactor", "hotTransFactor" }

-- the driven work of the transmission, its gearbox in good order
local function addTransmissionWork(vehicle, wear, driveLoad, transTemp, dt)
    local spec = vehicle.spec_RealisticMechanicalSystems
    local C = RMS_Config.CORE.TRANSMISSION_FACTOR_DATA
    local motorLoad, speed = vehicle:getMotorLoadPercentage(), vehicle:getLastSpeed()

    addTorqueWear(vehicle, wear, driveLoad, C, "pullOverloadFactor")
    moveTutorialTimer(spec, "luggingTutorialTimer", wear.factors.luggingFactor > 0, dt, 5000)

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

    addCause(wear, "hotTransFactor", RMS_Utils.getHeatWearFactor(transTemp, C.OVERHEAT_TRANSMISSION_THRESHOLD))

    if getIsIdling(vehicle, motorLoad) then
        wear.rate = wear.rate * C.TRANSMISSION_IDLING_MULTIPLIER
    end
    addCause(wear, "expiredServiceFactor", getExpiredServiceFactor(vehicle, "transmission", C))
end

---Wears the transmission on pull, trailer, lugging, slip, windup and oil
function RealisticMechanicalSystems:updateTransmissionSystem(dt)
    local spec = self.spec_RealisticMechanicalSystems
    local system = spec.systems.transmission
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
        addCause(wear, "coldTransFactor", RMS_Utils.getColdWearFactor(transTemp, C.COLD_TRANSMISSION_THRESHOLD))
    end

    -- the transmission addon owns the wear of its gearbox
    if hasCVTAddon(self) and isRunning then
        if getIsIdling(self, self:getMotorLoadPercentage()) then
            wear.rate = wear.rate * C.TRANSMISSION_IDLING_MULTIPLIER
        end
    elseif isRunning then
        addTransmissionWork(self, wear, driveLoad, transTemp, dt)
    else
        wearStopped(wear, self)
    end

    if isRunning then
        if RMS_Fluids.getSumpCircuit(self, "hydraulicFluid") == "transmissionOil" then
            addCause(wear, "filterBypassFactor", getFilterBypassFactor(spec, wear.rate))
        else
            addCause(wear, "transmissionFilterBypassFactor", getFilterBypassFactor(spec, wear.rate, "transmissionFilterClogging"))
        end
    end

    local brakeState = spec.chassisBrakeState
    finishWear(self, dt, RMS_Utils.getSystemKey(RealisticMechanicalSystems.SYSTEMS, system.name), wear, {
        driveTorqueRatio = RMS_Utils.getRatedTorqueRatio(self, driveLoad),
        heavyTrailerMassRatio = spec.isTruck == true and brakeState.hpGrossMassRatio or brakeState.hpTrailerMassRatio,
        heavyTrailerMassBasis = spec.isTruck == true and "gcw" or "trailer" })
end

local HYDRAULICS_CAUSES = { "expiredServiceFactor", "heavyLiftFactor", "filterBypassFactor", "vibFactor",
    "operatingFactor", "coldOilFactor", "hotOilFactor" }

-- the oil the pump works: its own circuit, or the transmission it shares
local function getHydraulicOilTemperature(spec)
    local transmission = spec.rawTransmissionTemperature or spec.transmissionTemperature
    local temperature = RMS_Thermal.getHasSeparateHydraulicCircuit(spec) and (spec.rawHydraulicTemperature or spec.hydraulicTemperature)
        or transmission
    return sanitizeNumber(temperature, transmission or 20, -80, 180)
end

---Wears the hydraulics on pump, lift load, vibration, cylinders and oil
-- fatigue past ordinary shaking, up to the hardest the game gives
local function getVibrationWear(signal, C, multiplier)
    local ratio = math.min(signal, C.VIB_FACTOR_MAX_SIGNAL) / C.VIB_FACTOR_THRESHOLD
    return math.max(ratio ^ RMS_Config.CORE.CHASSIS_FACTOR_DATA.VIB_FATIGUE_EXPONENT - 1, 0) * multiplier
end

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
        addCause(wear, "vibFactor", getVibrationWear(vibSignal, vibration, vibMultiplier))
    end

    if isRunning and spec.isHydraulicActive then
        addCause(wear, "operatingFactor", math.max(1 - C.PUMP_WEAR_RATE, 0))
        local oilTemperature = getHydraulicOilTemperature(spec)
        if not self:getIsAIActive() then
            addCause(wear, "coldOilFactor", RMS_Utils.getColdWearFactor(oilTemperature, C.COLD_OIL_THRESHOLD))
        end
        addCause(wear, "hotOilFactor", RMS_Utils.getHeatWearFactor(oilTemperature, C.HOT_OIL_THRESHOLD))
        addCause(wear, "expiredServiceFactor", getExpiredServiceFactor(self, "hydraulics", C))
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
        local angle = math.min(spec.ptoShaftAngle or 0, C.SHAFT_ANGLE_WEAR_MAX)
        if angle > C.SHAFT_ANGLE_REFERENCE then
            addCause(wear, "ptoRaisedFactor", C.SHAFT_ANGLE_LIFE_FACTOR ^ ((angle - C.SHAFT_ANGLE_REFERENCE) / 10) - 1)
        end
        addCause(wear, "expiredServiceFactor", getExpiredServiceFactor(self, "pto", C))
    end

    local isRaisedByPlayer = self:getIsMotorStarted() and spec.isPtoActive and spec.isPtoImplementRaised and not self:getIsAIActive()
    spec.ptoRaisedTutorialTimer = math.clamp((tonumber(spec.ptoRaisedTutorialTimer) or 0) + (isRaisedByPlayer and dt or -dt),
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

        if spec.isElectricVehicle then
            local T = RMS_Config.ELECTRIC_DRIVE.THERMAL
            local heat = RMS_Utils.calculateQuadraticMultiplier(temperature, T.OVERHEAT_THRESHOLD, false, T.OVERHEAT_FULL_EFFECT)
                * C.ELECTRIC_OVERHEAT_MULTIPLIER
            addCause(wear, "overheatFactor", math.min(heat, C.ELECTRIC_OVERHEAT_MULTIPLIER))
        else
            addCause(wear, "overheatFactor", RMS_Utils.getHeatWearFactor(temperature, C.OVERHEAT_FACTOR_THRESHOLD))
        end

        if not spec.isElectricVehicle and temperature < C.COLD_SHOCK_FACTOR_THRESHOLD and rpmLoad > 0.75 and not self:getIsAIActive() then
            local shock = RMS_Utils.calculateQuadraticMultiplier(temperature, C.COLD_SHOCK_FACTOR_THRESHOLD, true) * C.COLD_SHOCK_FACTOR_MULTIPLIER
                * RMS_Utils.calculateQuadraticMultiplier(rpmLoad, 0.75, false)
            addCause(wear, "coldShockFactor", math.min(shock, C.COLD_SHOCK_FACTOR_MULTIPLIER))
        end

        if spec.thermostatState == 0 and wear.factors.overheatFactor == 0 and wear.factors.coldShockFactor == 0 then
            wear.rate = wear.rate * C.COOLING_IDLING_MULTIPLIER
        end
        addCause(wear, "expiredServiceFactor", getExpiredServiceFactor(self, "cooling", C))
    else
        wearStopped(wear, self)
    end

    finishWear(self, dt, RMS_Utils.getSystemKey(RealisticMechanicalSystems.SYSTEMS, system.name), wear, {})
end

local WET_WEATHERS = { "RAIN", "SNOW", "HAIL" }

---Wears the electrics on cranking, weather, lights, heat and vibration
function RealisticMechanicalSystems:updateElectricalSystem(dt)
    local spec = self.spec_RealisticMechanicalSystems
    local system = spec.systems.electrical
    if not system.enabled then
        return
    end

    local C = RMS_Config.CORE.ELECTRICAL_FACTOR_DATA
    local vibState = spec.chassisVibState
    local wear = startWear(1.0, { "crankingStressFactor", "weatherExposureFactor", "overheatFactor", "vibFactor" })

    if not spec.isUnderRoof then
        for _, name in ipairs(WET_WEATHERS) do
            if RMS_Main.currentWeather == WeatherType[name] then
                addCause(wear, "weatherExposureFactor", getOutdoorWearRate(self))
            end
        end
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
        addCause(wear, "overheatFactor", RMS_Utils.getHeatWearFactor(getEngineTemperature(spec), getNormalTop(spec)))
        if vibState.smoothed > C.VIB_FACTOR_THRESHOLD then
            addCause(wear, "vibFactor", getVibrationWear(vibState.smoothed, C, C.VIB_FACTOR_MULTIPLIER))
        end
    elseif wear.factors.crankingStressFactor == 0 then
        wearStopped(wear, self)
    end

    finishWear(self, dt, RMS_Utils.getSystemKey(RealisticMechanicalSystems.SYSTEMS, system.name), wear, {
        crankingTimer = system.crankingTimer, vibSignal = vibState.signal, vibRaw = vibState.raw })
end

local CHASSIS_CAUSES = { "lubricationFactor", "vibFactor", "steerLoadFactor", "steerLowSpeedFactor", "brakeMassFactor",
    "parkBrakeDragFactor" }

-- a trailer braked by a light machine wears its brakes, by the pedal
local function getBrakeMassWear(vehicle, spec, C)
    local brakeState = spec.chassisBrakeState
    local ratio = spec.isTruck == true and brakeState.hpGrossMassRatio or brakeState.hpTrailerMassRatio
    local threshold, fullEffect = RMS_Utils.getHeavyTrailerRatioLevels(vehicle)
    if ratio >= threshold then
        return 0
    end
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
                addCause(wear, "brakeMassFactor", getBrakeMassWear(self, spec, C))
            end
            addCause(wear, "parkBrakeDragFactor", RMS_Drivetrain.getParkBrakeDragFactor(self))
        else
            wear.rate = wear.rate * C.CHASSIS_IDLING_MULTIPLIER
        end

        if steerState.groundContact > 0 and not self:getIsAIActive() then
            local lowSpeed = RMS_Utils.calculateQuadraticMultiplier(speed, C.STEER_LOAD_SPEED_THRESHOLD, true)
            wear.factors.steerLowSpeedFactor = lowSpeed
            local isHeldOnLock = math.abs(steerState.position or 0) >= 1 and (steerState.inputMagnitude or 0) > 0
            addCause(wear, "steerLoadFactor", C.STEER_LOAD_FACTOR_MULTIPLIER * steerState.travelRate * lowSpeed
                * spec.avgTireGroundFrictionCoeff * steerState.axleLoadRatio + (isHeldOnLock and C.STEER_LOCK_MULTIPLIER or 0))
        end
    else
        wearStopped(wear, self)
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
    local wear = startWear(1.0, { "deepDischargeFactor", "batteryHeatFactor" })

    if vehicle:getIsMotorStarted() then
        local heat = (spec.tractionBatteryTempC - C.BATTERY_HEAT_THRESHOLD) / C.BATTERY_HEAT_STEP_K
        addCause(wear, "batteryHeatFactor", heat > 0 and C.BATTERY_HEAT_FACTOR ^ heat - 1 or 0)
        if fuelState.level < C.DEEP_DISCHARGE_THRESHOLD then
            local loadShare = 1 + RMS_Utils.calculateQuadraticMultiplier(vehicle:getMotorLoadPercentage(), 0.70, false)
            addCause(wear, "deepDischargeFactor", RMS_Utils.calculateQuadraticMultiplier(fuelState.level, C.DEEP_DISCHARGE_THRESHOLD, true)
                * loadShare * C.DEEP_DISCHARGE_MULTIPLIER)
        end
    else
        wearStopped(wear, vehicle)
    end

    finishWear(vehicle, dt, systemKey, wear, { currentFuelUsageRatio = fuelState.currentUsageRatio, fuelLevel = fuelState.level })
end

local FUEL_CAUSES = { "lowFuelStarvationFactor", "coldFuelFactor", "idleDepositFactor", "highPressureFactor" }

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

        if not self:getIsAIActive() then
            addCause(wear, "coldFuelFactor", RMS_Utils.getColdWearFactor(temperature, C.COLD_FUEL_THRESHOLD))
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
    else
        wearStopped(wear, self)
    end

    finishWear(self, dt, systemKey, wear, readings)
end

local function getHeatLevels(key)
    local levels = RMS_Config.CORE.DIRECT_FAILURES[key]
    return levels.limit, levels.release
end

local function getLowLevels()
    return -RMS_Config.FLUIDS.LEVEL_CRITICALLY_LOW, -RMS_Config.FLUIDS.LEVEL_CRITICALLY_LOW
end

-- i={partId, firstStage, levels or getLevels, read}
local DIRECT_FAILURES = {
    { partId = "CYLINDER_HEAD_GASKET", firstStage = 2, levels = "ENGINE_HEAT", read = function(spec) return getEngineTemperature(spec) end },
    { partId = "TRANSMISSION_PUMP_MALFUNCTION", levels = "TRANSMISSION_HEAT",
        read = function(spec) return sanitizeNumber(spec.rawTransmissionTemperature or spec.transmissionTemperature, -99, -99, 180) end },
    { partId = "HYDRAULIC_PUMP_MALFUNCTION", levels = "HYDRAULIC_HEAT", read = getHydraulicOilTemperature },
    { partId = "STARTER_FAILURE", levels = "STARTER_CRANKING", whileCranking = true, read = function(spec) return spec.crankingSeconds end },
    { partId = "PTO_OUTPUT_SHAFT_FAILURE", read = function(spec) return spec.ptoShaftAngle or 0 end,
        getLevels = function(_, spec) return getHeatLevels(spec.isPtoImplementRaised and "PTO_SHAFT_ANGLE_TURNING" or "PTO_SHAFT_ANGLE") end },
    -- the oil lamp lights once the pump draws air
    { partId = "MAIN_BEARINGS", firstStage = 3, read = function(spec) return -(tonumber(spec.engineOilLevel) or 1) end, getLevels = getLowLevels },
    { partId = "ENGINE_JAM", read = function(spec) return -(tonumber(spec.engineOilLevel) or 1) end, getLevels = function() return 0, 0 end },
    { partId = "TRANSMISSION_PUMP_MALFUNCTION", read = function(spec) return -(tonumber(spec.transmissionOilLevel) or 1) end, getLevels = getLowLevels },
    { partId = "HYDRAULIC_PUMP_MALFUNCTION", read = function(spec) return -(tonumber(spec.hydraulicFluidLevel) or 1) end, getLevels = getLowLevels },
}

local function failPart(vehicle, partId, firstStage)
    local spec = vehicle.spec_RealisticMechanicalSystems
    local breakdown = spec.activeBreakdowns[partId]
    if breakdown ~= nil then
        vehicle:changeBreakdownStage(partId, breakdown.stage + 1)
    elseif RMS_Breakdowns.BreakdownRegistry[partId].isApplicable(vehicle) then
        vehicle:addBreakdown(partId, firstStage or 1)
    end
end

---Fails the part an abuse strains past the maker's limit
function RealisticMechanicalSystems:updateDirectFailures(dt)
    local spec = self.spec_RealisticMechanicalSystems
    if isMissionVehicle(self) then
        return
    end

    local starter = RMS_Config.CORE.DIRECT_FAILURES.STARTER_CRANKING
    local cranked = spec.crankingSeconds or 0
    spec.crankingSeconds = spec.isCranking and cranked + dt / 1000 or math.max(cranked - dt / 1000 * starter.limit / starter.rest, 0)
    spec.directFailureLatches = spec.directFailureLatches or {}
    local isRunning = self:getIsMotorStarted()
    for index, failure in ipairs(DIRECT_FAILURES) do
        local value = failure.read(spec)
        local limit, release = (failure.getLevels or getHeatLevels)(failure.levels, spec)
        local isWatched = failure.whileCranking and spec.isCranking or not failure.whileCranking and isRunning
        if isWatched and value >= limit and not spec.directFailureLatches[index] then
            spec.directFailureLatches[index] = true
            failPart(self, failure.partId, failure.firstStage)
        elseif not isWatched or value < release then
            spec.directFailureLatches[index] = nil
        end
    end
end
