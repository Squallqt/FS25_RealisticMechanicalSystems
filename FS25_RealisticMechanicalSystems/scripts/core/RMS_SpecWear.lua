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

local function getIsFilterBypassed(spec, stateKey)
    return RMS_Consumables.getFilterStage(spec[stateKey]) >= RMS_Config.CORE.HYDRAULICS_FACTOR_DATA.FILTER_BYPASS_STAGE
end

-- a clogged filter opens its bypass, a defective one lets dirt pass
local function getFilterBypassFactor(vehicle, wearRate, stateKey)
    stateKey = stateKey or "hydraulicFilterClogging"
    local defective = RMS_Consumables.getDefectiveFilter(vehicle)
    if not getIsFilterBypassed(vehicle.spec_RealisticMechanicalSystems, stateKey)
        and (defective == nil or defective.stateKey ~= stateKey) then
        return 0
    end
    return wearRate * RMS_Config.CORE.HYDRAULICS_FACTOR_DATA.FILTER_BYPASS_MULTIPLIER
end

---Runs the hourly service clocks down while the engine runs
function RealisticMechanicalSystems:updateServiceLevel(dt)
    local spec = self.spec_RealisticMechanicalSystems
    if isMissionVehicle(self) then
        return
    end

    local hourlyWear = self:getIsMotorStarted() and RMS_Config.CORE.BASE_SERVICE_WEAR or 0
    for _, clock in ipairs(self:getServiceClocks()) do
        if clock.intervalFactor ~= nil then
            local oilShare = clock.key == "engine" and RMS_Fluids.getEngineOilIntervalShare(self) or 1
            spec[clock.levelKey] = math.max((spec[clock.levelKey] or spec.baseServiceLevel)
                - hourlyWear / clock.intervalFactor / oilShare / 3600000 * dt, 0)
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

-- the red coolant lamp is lit
local function getHeatAbuse(_, spec)
    return spec.engineTemperature >= RMS_Thermal.getDriveValues(spec).TELLTALE.CRITICAL and "heat" or nil
end

-- the abuse a cause's wear is, past the warning the player was given
local CAUSE_ABUSES = {
    hmf = getHeatAbuse,
    ohf = getHeatAbuse,
    hotf = function(_, spec)
        return spec.transmissionTemperature >= RMS_Config.CORE.TRANSMISSION_FACTOR_DATA.OVERHEAT_TRANSMISSION_WARNING
            and "heat" or nil
    end,
    pbf = function() return "park_brake" end,
    hstf = function() return "stones" end,
    dwf = function(vehicle) return RMS_Drivetrain.getIsWindupChosen(vehicle) and "windup" or nil end,
    aicf = function() return "filter" end,
    -- a defective filter wears unwarned: only a clogged one is abuse
    hfbf = function(_, spec) return getIsFilterBypassed(spec, "hydraulicFilterClogging") and "filter" or nil end,
    tfbf = function(_, spec) return getIsFilterBypassed(spec, "transmissionFilterClogging") and "filter" or nil end,
    htf = function() return "trailer" end,
    bmf = function() return "trailer" end,
}

---Marks the parts a cause wears with an abuse, refusing their warranty
-- @param string abuse one of WARRANTY_ABUSES
function RealisticMechanicalSystems.markCauseAbuse(vehicle, systemKey, alias, abuse)
    local spec = vehicle.spec_RealisticMechanicalSystems
    local shares = spec.partCauseShares[systemKey][alias]
    for index, partId in ipairs(spec.systemParts[systemKey]) do
        local baseShare = RMS_Breakdowns.BreakdownRegistry[partId].wearsByCausesOnly and 0 or 1
        if (shares ~= nil and shares[index] or baseShare) > 0 then
            spec.partAbuse[partId] = RealisticMechanicalSystems.WARRANTY_ABUSE[abuse]
        end
    end
end

function RealisticMechanicalSystems:updateSystemWear(dt, systemKey, wearRate, factors)
    local spec = self.spec_RealisticMechanicalSystems
    local reliability = math.max(spec.reliability, 0.001)
    local dtMultiplier = RMS_Config.CORE.BASE_SYSTEMS_WEAR / (60 * 60 * 1000) * dt
    local isLent = isMissionVehicle(self)
    -- a lent machine does not wear; helpers ease off on its causes
    local scale = isLent and 0 or RMS_Fluids.getSystemWearMultiplier(self, systemKey) / reliability * dtMultiplier

    local causeRates, causeTotal = {}, 0
    for key, value in pairs(factors) do
        local alias = RealisticMechanicalSystems.FACTOR_STATS_ALIASES[key]
        if alias ~= nil and value > 0 then
            causeRates[alias] = value
            causeTotal = causeTotal + value
            local abuse = not isLent and CAUSE_ABUSES[alias] ~= nil and CAUSE_ABUSES[alias](self, spec) or nil
            if abuse ~= nil then
                RealisticMechanicalSystems.markCauseAbuse(self, systemKey, alias, abuse)
            end
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
    spec.systemWearRateNow[systemKey] = wearRate / reliability
end

---Wears the parts of a system at once, the cause on the parts it reaches
-- @param string? abuse one of WARRANTY_ABUSES, marking the parts it wears
function RealisticMechanicalSystems:applyInstantDamageToSystem(system, damageAmount, factorName, abuse)
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
        if abuse ~= nil and partDamage > 0 then
            spec.partAbuse[partId] = RealisticMechanicalSystems.WARRANTY_ABUSE[abuse]
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
            addCause(wear, "filterBypassFactor", getFilterBypassFactor(self, wear.rate))
        else
            addCause(wear, "transmissionFilterBypassFactor", getFilterBypassFactor(self, wear.rate, "transmissionFilterClogging"))
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

    addCause(wear, "filterBypassFactor", getFilterBypassFactor(self, wear.rate))

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
    local isShock = spec.isPtoEngagementShock
    spec.ptoEngagementDamage, spec.isPtoEngagementShock = 0, false

    if self:getIsMotorStarted() and spec.isPtoActive then
        wear.rate = 1
        local utilization = math.max(tonumber(spec.ptoUtilization) or 0, 0)
        if utilization > C.LOAD_FACTOR_THRESHOLD then
            addCause(wear, "ptoLoadFactor", RMS_Utils.calculatePtoLoadFactor(utilization, C))
        end
        if spec.ptoShaftWear > 0 then
            addCause(wear, "ptoRaisedFactor", spec.ptoShaftWear)
        end
        addCause(wear, "expiredServiceFactor", getExpiredServiceFactor(self, "pto", C))
    end

    local isRaisedByPlayer = self:getIsMotorStarted() and spec.isPtoActive and spec.isPtoImplementRaised and not self:getIsAIActive()
    spec.ptoRaisedTutorialTimer = math.clamp((tonumber(spec.ptoRaisedTutorialTimer) or 0) + (isRaisedByPlayer and dt or -dt),
        0, C.RAISED_TUTORIAL_MS)
    spec.ptoRaisedTooLong = spec.ptoRaisedTutorialTimer >= C.RAISED_TUTORIAL_MS

    if engagementDamage > 0 then
        self:applyInstantDamageToSystem(system.name, engagementDamage, "ptoEngagementFactor", isShock and "pto_engagement" or nil)
    end

    finishWear(self, dt, RMS_Utils.getSystemKey(RealisticMechanicalSystems.SYSTEMS, system.name), wear, {
        isPtoActive = spec.isPtoActive == true, ptoEngagementDamage = engagementDamage, ptoRpm = spec.ptoRpm, ptoPower = spec.ptoPower,
        ptoUtilization = spec.ptoUtilization, ptoEngagementCount = spec.ptoEngagementCount })
end

local function getAttachedCutterData(spec_combine, fruitTypeIndex)
    local stone, isPickup, conversion = 1, false, nil
    for cutter in pairs(spec_combine.attachedCutters) do
        local spec_cutter = cutter.spec_cutter
        -- stones only reach a header at the ground, cutting or picking up
        local isAtGround = spec_cutter == nil or spec_cutter.useWindrow == true
            or (spec_cutter.currentCutHeight or 0) <= RMS_Config.CORE.HARVEST_FACTOR_DATA.STONE_CUT_HEIGHT
        if cutter.getCutterStoneMultiplier ~= nil and isAtGround then
            stone = math.max(stone, cutter:getCutterStoneMultiplier())
        end
        if spec_cutter ~= nil then
            isPickup = isPickup or spec_cutter.useWindrow == true
            conversion = conversion or spec_cutter.fruitTypeConverters[fruitTypeIndex]
        end
    end
    return stone, isPickup, conversion
end

-- the crop counted since the time of the last measure
local function getHarvestInput(spec)
    spec.harvestInput = spec.harvestInput or { liters = 0, time = g_currentMission.time }
    return spec.harvestInput
end

---Counts the crop the cutters hand over, field bonuses included
function RealisticMechanicalSystems.addCutterArea(self, superFunc, area, liters, inputFruitType, outputFillType, strawRatio, ...)
    local applied = superFunc(self, area, liters, inputFruitType, outputFillType, strawRatio, ...)
    local spec = self.spec_RealisticMechanicalSystems
    if spec ~= nil and applied > 0 and liters > 0 then
        local input = getHarvestInput(spec)
        input.liters = input.liters + liters
        -- a pickup hands over a windrow, its crop read from the grain
        input.fruitTypeIndex = inputFruitType or g_fruitTypeManager:getFruitTypeIndexByFillTypeIndex(outputFillType)
        input.fillTypeIndex, input.strawRatio = outputFillType, math.clamp(tonumber(strawRatio) or 1, 0, 1)
    end
    return applied
end

-- the straw of the crop as the combine buffers it, in t per l of grain
local function getStrawPerGrainLiter(fruitDesc, conversion)
    if fruitDesc.windrowLiterPerSqm == nil or fruitDesc.literPerSqm <= 0 then
        return 0
    end
    -- a crop without windrow drops straw all the same
    local windrowFillType = g_fruitTypeManager:getWindrowFillTypeIndexByFruitTypeIndex(fruitDesc.index) or FillType.STRAW
    local cropPerLiter = 1 / (conversion ~= nil and conversion.conversionFactor or 1)
    return cropPerLiter / fruitDesc.literPerSqm * fruitDesc.windrowLiterPerSqm
        * g_fillTypeManager:getFillTypeByIndex(windrowFillType).massPerLiter
end

-- a flow against the flow of full work, a model being a + c * t/h
local function getFullWorkShare(flow, model, engineKw)
    local C = RMS_Config.CORE.HARVEST_FACTOR_DATA
    return flow * model.c / math.max(C.ROTARY_SHARE * engineKw - model.a, 1)
end

-- the crop taken in since the last measure, over the time really gone by
local function measureHarvestWork(vehicle, state, input, elapsedMs)
    local C = RMS_Config.CORE.HARVEST_FACTOR_DATA
    local spec_combine = vehicle.spec_combine
    local engineKw = math.max(tonumber(vehicle:getMotor().peakMotorPower) or 0, 1)
    local liters = input.liters
    input.liters = 0

    local fruitTypeIndex = input.fruitTypeIndex or spec_combine.lastValidInputFruitType
    local fruitDesc = g_fruitTypeManager:getFruitTypeByIndex(fruitTypeIndex)
    local stone, isPickup, conversion = getAttachedCutterData(spec_combine, fruitTypeIndex)
    state.stone = stone - 1
    state.crop = fruitDesc ~= nil and fruitDesc.name or nil
    state.isRice = state.crop ~= nil and string.find(state.crop, "RICE", 1, true) ~= nil

    local hours = elapsedMs / 3600000
    local strawRatio = input.strawRatio or 1
    local grainTph, strawTph = 0, 0
    local fillType = g_fillTypeManager:getFillTypeByIndex(input.fillTypeIndex)
    if liters > 0 and fruitDesc ~= nil and fillType ~= nil then
        grainTph = liters * fillType.massPerLiter / hours
        -- the share of straw the header takes in with the grain
        strawTph = liters * getStrawPerGrainLiter(fruitDesc, conversion) * strawRatio / hours
    end

    local isChopping = spec_combine.chopper.isAvailable and not spec_combine.isSwathActive
        and vehicle.spec_RealisticMechanicalSystems.activeEffects.CHOPPER_FAILURE == nil
    local rotaryKw, chopperKw = nil, 0
    state.grain = 0
    if state.kind == "grain" then
        -- the whole plant goes through on its straw, ears alone on their grain
        local isWholePlant = fruitDesc ~= nil and fruitDesc.windrowLiterPerSqm ~= nil and strawRatio > C.WHOLE_PLANT_STRAW_RATIO
        local model = isWholePlant and C.SMALL_GRAIN or C.MAIZE
        local flow = isWholePlant and strawTph or grainTph
        rotaryKw = model.a + model.c * flow
        -- the elevators carry the grain of full work in this crop
        state.grain = getFullWorkShare(flow, model, engineKw)
        chopperKw = isChopping and C.CHOPPER_ENERGY * strawTph or 0
    elseif state.kind == "forage" and not isPickup then
        local flow = grainTph * C.FORAGE_DRY_MATTER
        rotaryKw = C.FORAGE.a + C.FORAGE.c * flow
        state.grain = getFullWorkShare(flow, C.FORAGE, engineKw)
    end

    local effort = rotaryKw ~= nil and rotaryKw / (C.ROTARY_SHARE * engineKw) or spec_combine.numAttachedCutters > 0 and vehicle:getCombineLoadPercentage() or 0
    local chopper = chopperKw / (C.CHOPPER_SHARE * engineKw)
    state.source, state.isWet = "rms", vehicle:getIsThreshingDuringRain()

    local api = RMS_Utils.getHarvestModApi()
    if api ~= nil and api.isActivelyHarvesting(vehicle) then
        local power = api.getPowerBreakdown(vehicle)
        local processHp = power.pProcess + power.pChopper + power.pSoil
        -- a provider that stops computing keeps its last powers unchanged
        if power.effectiveHp > 0 and processHp > 0 and (api.getEngineLoad(vehicle) > 0 or processHp ~= state.rhProcessHp) then
            -- against the rated engine, not the power its difficulty adds
            local ratedHp = engineKw * 1.35962
            effort = processHp / (C.ROTARY_SHARE * ratedHp)
            chopper = power.pChopper / (C.CHOPPER_SHARE * ratedHp)
            -- from hp to kW
            rotaryKw, chopperKw = processHp / 1.35962, power.pChopper / 1.35962
            state.source, state.isWet = "rh", api.isMoistureExceeded(vehicle)
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
    state.tonPerHour, state.rotaryKw, state.chopperKw = grainTph, rotaryKw or 0, chopperKw
    state.tons = (state.tons or 0) + grainTph * hours
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

    -- measured every step, so no crop is left over for later
    local input = getHarvestInput(spec)
    local now = g_currentMission.time
    if now > input.time then
        measureHarvestWork(self, state, input, now - input.time)
        input.time = now
    end

    -- a header driven on its own still feeds the machine
    spec.isHarvestRunning = state.effort ~= nil and self:getIsMotorStarted() and (self:getIsTurnedOn() or state.tonPerHour > 0)
    local wearRate = 0
    local factors = { harvestEffortFactor = 0, harvestGrainFactor = 0, harvestStrawFactor = 0, harvestStoneFactor = 0,
        harvestRiceFactor = 0, harvestWetFactor = 0, lubricationFactor = 0 }
    if spec.isHarvestRunning then
        local work = C.BASE_RATE * state.effort
        -- stones, rice straw and a damp crop only reach organs fed with crop
        local cropWork = state.tonPerHour > 0 and work or 0
        local stone = state.stone * (spec.activeEffects.METAL_DETECTOR_OFF ~= nil and C.DETECTOR_OFF_STONE_MULTIPLIER or 1)
        local rates = {
            harvestEffortFactor = C.BASE_RATE * math.max(state.effort - 1, 0),
            harvestGrainFactor = C.BASE_RATE * math.max(state.grain - 1, 0),
            harvestStrawFactor = C.BASE_RATE * math.max(state.chopper - 1, 0),
            harvestStoneFactor = cropWork * stone,
            harvestRiceFactor = state.isRice and cropWork * C.RICE_MULTIPLIER or 0,
            harvestWetFactor = state.isWet and cropWork * C.WET_MULTIPLIER or 0,
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
        factors.harvestStone = cropWork > 0 and stone or 0
        factors.harvestSource = state.source
    end

    self:updateSystemWear(dt, systemKey, wearRate, factors)
end

-- also asked while loading, before RMS builds the systems
local function getHarvestSpec(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    if spec == nil or spec.systems == nil or spec.isExcludedVehicle or spec.systems.harvest == nil or not spec.systems.harvest.enabled then
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
    -- the notice says to fill up before the tank runs dry
    if (spec.lastFuelLevel or 0) > 0 and fuelState.level <= 0 and not isMissionVehicle(self) then
        RealisticMechanicalSystems.markCauseAbuse(self, systemKey, "lff", "fuel_dry")
    end
    spec.lastFuelLevel = fuelState.level
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

-- i={partId, firstStage, abuse, levels or getLevels, read}
local DIRECT_FAILURES = {
    { partId = "CYLINDER_HEAD_GASKET", firstStage = 2, abuse = "heat", levels = "ENGINE_HEAT",
        read = function(spec) return getEngineTemperature(spec) end },
    { partId = "TRANSMISSION_PUMP_MALFUNCTION", abuse = "heat", levels = "TRANSMISSION_HEAT",
        read = function(spec) return sanitizeNumber(spec.rawTransmissionTemperature or spec.transmissionTemperature, -99, -99, 180) end },
    { partId = "HYDRAULIC_PUMP_MALFUNCTION", abuse = "heat", levels = "HYDRAULIC_HEAT", read = getHydraulicOilTemperature },
    { partId = "STARTER_FAILURE", abuse = "starter", levels = "STARTER_CRANKING", whileCranking = true,
        read = function(spec) return spec.crankingSeconds end },
    { partId = "PTO_OUTPUT_SHAFT_FAILURE", abuse = "pto_angle", read = function(spec) return spec.ptoShaftAngle end,
        getLevels = function(_, spec) return spec.ptoShaftLimit, RMS_Config.CORE.DIRECT_FAILURES.PTO_SHAFT_ANGLE.release end },
}

---Fails a part one stage for each span of air its pump has drawn
local function failAirDrawingParts(vehicle, spec)
    for _, partId in pairs(RMS_Fluids.PICKUP_PARTS) do
        local definition = RMS_Breakdowns.BreakdownRegistry[partId]
        local stage = math.min(math.floor((spec.pickupAirTime[partId] or 0) / RMS_Config.FLUIDS.PICKUP_STAGE_SECONDS), #definition.stages)
        local breakdown = spec.activeBreakdowns[partId]
        if stage > (breakdown ~= nil and breakdown.stage or 0) and definition.isApplicable(vehicle) then
            spec.partAbuse[partId] = RealisticMechanicalSystems.WARRANTY_ABUSE.low_level
            if breakdown ~= nil then
                vehicle:changeBreakdownStage(partId, stage)
            else
                vehicle:addBreakdown(partId, stage)
            end
        end
    end
end

local function failPart(vehicle, failure)
    local spec = vehicle.spec_RealisticMechanicalSystems
    local partId = failure.partId
    local breakdown = spec.activeBreakdowns[partId]
    if breakdown ~= nil then
        spec.partAbuse[partId] = RealisticMechanicalSystems.WARRANTY_ABUSE[failure.abuse]
        vehicle:changeBreakdownStage(partId, breakdown.stage + 1)
    elseif RMS_Breakdowns.BreakdownRegistry[partId].isApplicable(vehicle) then
        spec.partAbuse[partId] = RealisticMechanicalSystems.WARRANTY_ABUSE[failure.abuse]
        vehicle:addBreakdown(partId, failure.firstStage or 1)
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
            failPart(self, failure)
        elseif not isWatched or value < release then
            spec.directFailureLatches[index] = nil
        end
    end
    failAirDrawingParts(self, spec)
end
