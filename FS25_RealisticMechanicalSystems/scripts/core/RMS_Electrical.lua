-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---Low-voltage electrical system.
RMS_Electrical = RMS_Electrical or {}

local sanitizeNumber = RealisticMechanicalSystems.sanitizeNumber

local DAY_MS = 24 * 60 * 60 * 1000
local HOUR_MS = 60 * 60 * 1000
local MIN_CAPACITY_AH = 0.01
-- Substep linked batteries to limit charge-transfer overshoot.
local PAIR_STEP_MS = 30000
local PAIR_MAX_STEPS = 120

---Reads a value on a curve of points, held flat past its ends
local function interpolate(curve, x)
    if x <= curve[1][1] then
        return curve[1][2]
    end

    for i = 2, #curve do
        local low, high = curve[i - 1], curve[i]
        if x <= high[1] then
            return low[2] + (high[2] - low[2]) * (x - low[1]) / (high[1] - low[1])
        end
    end

    return curve[#curve][2]
end

---Reads the value of the first step a quantity fits under
local function pickStep(steps, x)
    for _, step in ipairs(steps) do
        if x <= step[1] then
            return step[2]
        end
    end
end

---Takes a size to the nearest step of a catalogue
local function toCatalogueStep(value, step)
    return math.floor(value / step + 0.5) * step
end

---Sizes the circuit of a machine from its family, its power and its year
-- @param table vehicle vehicle
-- @return table rating alternator, battery, starter and consumers of the machine
function RMS_Electrical.resolveRating(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    local C = RMS_Config.ELECTRICAL
    local law = C.RATING
    local family = RMS_Fluids.getProfileName(vehicle)
    local power = math.clamp(RMS_Fluids.getEnginePower(vehicle), law.POWER_RANGE_HP[1], law.POWER_RANGE_HP[2])
    local year = math.clamp(spec.year, law.YEAR_RANGE[1], law.YEAR_RANGE[2])

    ---
    local function size(entry)
        return entry.base * (power / 100) ^ entry.powerExponent * entry.decadeFactor ^ ((year - 2000) / 10)
    end

    local rating = {
        alternatorA = size(law.ALTERNATOR_A),
        batteryCapacityAh = size(law.BATTERY_AH),
        starterKw = size(law.STARTER_KW)
    }
    if family == "TELEHANDLER" then
        rating.alternatorA = law.TELEHANDLER_ALTERNATOR_A
    elseif family == "ROAD_LIGHT" then
        rating.alternatorA = law.ROAD_LIGHT.alternatorA
        rating.batteryCapacityAh = law.ROAD_LIGHT.batteryCapacityAh
        rating.starterKw = law.ROAD_LIGHT.starterKw
    end

    local is24V = law.SYSTEM_24V_FAMILIES[family] == true or family == "WHEEL_LOADER" and power > law.WHEEL_LOADER_24V_ABOVE_HP
    local series = is24V and 2 or 1
    rating.seriesBatteries = series
    rating.alternatorA = toCatalogueStep(rating.alternatorA / series, law.ALTERNATOR_STEP_A)
    rating.batteryCapacityAh = is24V and law.BATTERY_24V_AH or toCatalogueStep(rating.batteryCapacityAh, law.BATTERY_STEP_AH)

    rating.hasCalculators = spec.isElectricVehicle == true or RMS_Utils.getUsesEngineECUProfile(vehicle)
    rating.baseLoadA = (rating.hasCalculators and C.BASE_LOAD_ECU_A or C.BASE_LOAD_A) / series

    local workLamps
    if year < 1990 then
        workLamps = C.WORK_LAMPS_BEFORE_1990
    elseif year < 2012 then
        workLamps = C.WORK_LAMPS_BEFORE_2012
    else
        workLamps = pickStep(C.WORK_LAMPS_BY_POWER, power)
    end
    if family == "HARVESTER" or family == "FORAGE_HARVESTER" then
        workLamps = workLamps * C.WORK_LAMPS_HARVESTER_FACTOR
    end
    local lampW = year < C.LED_YEARS.FRONT_WORK_LIGHTS_FAILURE and C.WORK_LAMP_HALOGEN_W or C.WORK_LAMP_LED_W
    rating.workLamps = workLamps
    rating.workLightsSideA = workLamps / 2 * lampW / (C.LAMP_VOLTAGE_V * series)
    rating.glowPlugsA = pickStep(C.GLOW_PLUGS_BY_POWER, power) * C.GLOW_PLUG_A / series

    local curve, resistance, current = C.OCV_CURVE, C.INTERNAL_RESISTANCE_CURVE, C.STARTER_CURRENT_CURVE
    rating.starterRatedA = rating.starterKw * current[#current][2] / series
    rating.referenceCrankingV = (curve[#curve][2]
        - rating.starterRatedA * resistance[#resistance][2] / rating.batteryCapacityAh) * series

    return rating
end

local function getRestingVoltage(rating, soc)
    return interpolate(RMS_Config.ELECTRICAL.OCV_CURVE, soc) * rating.seriesBatteries
end
RMS_Electrical.getRestingVoltage = getRestingVoltage

---Sizes the circuit and settles the voltmeter on the resting voltage
-- @param table vehicle vehicle
function RMS_Electrical.initializeVehicle(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    spec.electricalRating = RMS_Electrical.resolveRating(vehicle)

    local restingV = getRestingVoltage(spec.electricalRating, spec.batterySoc)
    spec.rawSystemVoltageV = restingV
    spec.systemVoltageV = restingV
end

---Returns the capacity the battery still holds, sulfation taken off
-- @param table vehicle vehicle
-- @return float capacityAh capacity in amp hours
function RMS_Electrical.getBatteryCapacityAh(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    return math.max(spec.electricalRating.batteryCapacityAh * spec.batteryHealth, MIN_CAPACITY_AH)
end

---Returns what the alternator, or an electric's converter, gives now
local function getGeneratorOutput(vehicle, spec, isRunning)
    local ratedA = spec.electricalRating.alternatorA * spec.alternatorHealth

    if spec.isElectricVehicle then
        return (isRunning or RMS_ElectricDrive.getIsCharging(vehicle)) and ratedA or 0
    end
    if not isRunning then
        return 0
    end

    local motor = vehicle:getMotor()
    local speed = math.clamp((motor:getLastModulatedMotorRpm() - motor.minRpm) / (motor.maxRpm - motor.minRpm), 0, 1)
    local idleFactor = RMS_Config.ELECTRICAL.ALTERNATOR_IDLE_FACTOR
    return ratedA * (idleFactor + (1 - idleFactor) * speed)
end

---Lists what the consumers of a machine draw at this moment
local function getLoads(vehicle, spec, isRunning, isCranking, ambientC)
    local C = RMS_Config.ELECTRICAL
    local rating = spec.electricalRating
    local series = rating.seriesBatteries
    local loads = { base = 0, cab = 0, lights = 0, starter = 0, preheat = 0 }

    if isRunning then
        loads.base = rating.baseLoadA
        loads.cab = (C.CAB_FAN_A + (ambientC > C.AIR_CONDITIONING_MIN_TEMP_C and C.AIR_CONDITIONING_A or 0)) / series
    end

    if vehicle.spec_lights ~= nil then
        -- Light types: 0 road, 1 rear work, 2 front work.
        local mask = vehicle:getLightsTypesMask()
        if mask % 2 == 1 then
            loads.lights = C.ROAD_LIGHTS_A / series
        end
        if math.floor(mask / 2) % 2 == 1 then
            loads.lights = loads.lights + rating.workLightsSideA
        end
        if math.floor(mask / 4) % 2 == 1 then
            loads.lights = loads.lights + rating.workLightsSideA
        end
    end

    if isCranking then
        loads.starter = rating.starterKw * interpolate(C.STARTER_CURRENT_CURVE, ambientC) / series
    end
    if RMS_Preheat.isHeating(vehicle) then
        loads.preheat = rating.glowPlugsA
    end

    loads.total = loads.base + loads.cab + loads.lights + loads.starter + loads.preheat
    return loads
end

---Tells whether a machine is being started at this instant
-- @param table vehicle vehicle
-- @return boolean isStarting native or RMS cranking active
function RMS_Electrical.getIsStarting(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    if spec.isCranking == true or vehicle:getMotorState() == MotorState.STARTING then
        return true
    end

    for _, effectId in ipairs({ "ENGINE_HARD_START_MODIFIER", "GLOW_PLUG_HARD_START_MODIFIER", "ENGINE_FAILURE" }) do
        local effect = spec.activeEffects[effectId]
        local status = effect ~= nil and effect.extraData ~= nil and effect.extraData.status or nil
        if status == "CRANKING" or status == "PASSED" then
            return true
        end
    end

    return false
end

---Reads the circuit of a machine into one node
local function buildNode(vehicle, isStarting)
    local spec = vehicle.spec_RealisticMechanicalSystems
    local C = RMS_Config.ELECTRICAL
    local rating = spec.electricalRating
    local ambientC = RMS_Utils.getAmbientTemperature()
    local isRunning = vehicle:getIsMotorStarted()
    local isCranking = not spec.isElectricVehicle and (isStarting == true or RMS_Electrical.getIsStarting(vehicle))
    local capacityAh = RMS_Electrical.getBatteryCapacityAh(vehicle)

    local node = {
        vehicle = vehicle,
        spec = spec,
        rating = rating,
        ambientC = ambientC,
        isRunning = isRunning,
        isCranking = isCranking,
        capacityAh = capacityAh,
        soc = sanitizeNumber(spec.batterySoc, 1, 0, 1),
        floorSoc = interpolate(C.INACCESSIBLE_CHARGE_CURVE, ambientC),
        resistanceOhm = interpolate(C.INTERNAL_RESISTANCE_CURVE, ambientC) / capacityAh * rating.seriesBatteries
            * (1 + (C.EMPTY_RESISTANCE_FACTOR - 1) * (1 - sanitizeNumber(spec.batterySoc, 1, 0, 1))),
        circuitOhm = spec.circuitResistanceFactor * C.CIRCUIT_ADMISSIBLE_DROP_V * rating.seriesBatteries / rating.starterRatedA,
        generatorA = 0,
        chargerA = 0,
        startAidA = 0,
        chargerOutA = 0,
        loads = { base = 0, cab = 0, lights = 0, starter = 0, preheat = 0, total = 0 }
    }

    if not spec.batteryIsolated then
        node.loads = getLoads(vehicle, spec, isRunning, isCranking, ambientC)
        node.generatorA = getGeneratorOutput(vehicle, spec, isRunning)
        if isStarting and spec.isElectricVehicle and not isRunning then
            node.loads.total = node.loads.total + rating.baseLoadA
        end
    end

    if vehicle.isServer and spec.batteryCharger ~= nil then
        node.chargerA, node.startAidA = RMS_BatteryCharger.getAvailableCurrent(vehicle, isCranking)
    end

    return node
end

---Returns the current a battery takes at its state of charge
local function getAcceptance(node)
    local C = RMS_Config.ELECTRICAL
    if node.soc >= 1 then
        return 0
    end

    local rate = node.soc < C.CHARGE_TOPPING_SOC and C.CHARGE_ACCEPTANCE_BULK or C.CHARGE_ACCEPTANCE_TOPPING
    return rate * node.capacityAh
end

---Balances one circuit, the battery carrying any shortfall
local function solveNode(node)
    local restingV = getRestingVoltage(node.rating, node.soc)
    local startAidA = math.min(node.startAidA, node.loads.total)
    local shortfallA = node.loads.total - startAidA - node.generatorA - node.chargerA

    if shortfallA <= 0 then
        node.batteryA = math.min(-shortfallA, getAcceptance(node))
        local isFed = node.generatorA + node.chargerA + startAidA > 0
        node.voltageV = isFed and RMS_Config.ELECTRICAL.REGULATED_VOLTAGE_V * node.rating.seriesBatteries or restingV
        local drawnA = node.loads.total - startAidA + node.batteryA
        node.chargerOutA = startAidA + math.max(drawnA - node.generatorA, 0)
    elseif node.soc > node.floorSoc then
        node.batteryA = -shortfallA
        node.voltageV = math.max(restingV - shortfallA * (node.resistanceOhm + node.circuitOhm), 0)
        node.chargerOutA = startAidA + node.chargerA
    else
        node.batteryA = 0
        node.voltageV = 0
        node.chargerOutA = startAidA + node.chargerA
    end
end

---Moves the charge of one circuit over a duration, leg by leg
local function advanceNode(node, hours)
    local C = RMS_Config.ELECTRICAL

    for _ = 1, 3 do
        solveNode(node)
        if hours <= 0 or node.batteryA == 0 then
            return
        end

        local targetSoc = node.floorSoc
        if node.batteryA > 0 then
            targetSoc = node.soc < C.CHARGE_TOPPING_SOC and C.CHARGE_TOPPING_SOC or 1
        end

        local legHours = (targetSoc - node.soc) * node.capacityAh / node.batteryA
        if legHours > hours then
            node.soc = node.soc + node.batteryA * hours / node.capacityAh
            hours = 0
        else
            node.soc = targetSoc
            hours = hours - legHours
        end
    end

    solveNode(node)
end

---Balances two circuits joined by jumper cables
local function solvePair(a, b)
    local C = RMS_Config.ELECTRICAL
    local nodes = { a, b }
    local demandA = {}
    local generatorA = a.generatorA + b.generatorA

    for index, node in ipairs(nodes) do
        node.restingV = getRestingVoltage(node.rating, node.soc)
        node.acceptA = getAcceptance(node)
        demandA[index] = node.loads.total - node.generatorA
    end

    local totalA = demandA[1] + demandA[2]
    if totalA <= 0 and generatorA > 0 then
        local acceptA = a.acceptA + b.acceptA
        local share = acceptA > 0 and math.min(-totalA / acceptA, 1) or 0
        for _, node in ipairs(nodes) do
            node.batteryA = node.acceptA * share
            node.voltageV = C.REGULATED_VOLTAGE_V * node.rating.seriesBatteries
        end
        return
    end

    local conductance = { 1 / a.resistanceOhm, 1 / b.resistanceOhm }
    local cable = 1 / C.JUMPER_CABLE_RESISTANCE_OHM
    -- A clamped battery becomes a fixed-current node.
    local fixedA = { 0, 0 }
    local voltageV = { 0, 0 }

    for _ = 1, 3 do
        local m11, m22 = conductance[1] + cable, conductance[2] + cable
        local r1 = conductance[1] * a.restingV - demandA[1] - fixedA[1]
        local r2 = conductance[2] * b.restingV - demandA[2] - fixedA[2]
        local determinant = m11 * m22 - cable * cable
        if determinant <= 0 then
            voltageV[1], voltageV[2] = 0, 0
            break
        end
        voltageV[1] = (r1 * m22 + cable * r2) / determinant
        voltageV[2] = (m11 * r2 + cable * r1) / determinant

        local isSettled = true
        for index, node in ipairs(nodes) do
            if conductance[index] > 0 then
                local batteryA = conductance[index] * (voltageV[index] - node.restingV)
                if batteryA < 0 and node.soc <= node.floorSoc then
                    conductance[index], fixedA[index], isSettled = 0, 0, false
                elseif batteryA > node.acceptA then
                    conductance[index], fixedA[index], isSettled = 0, node.acceptA, false
                end
            end
        end
        if isSettled then
            break
        end
    end

    for index, node in ipairs(nodes) do
        node.batteryA = conductance[index] > 0 and conductance[index] * (voltageV[index] - node.restingV) or fixedA[index]
        node.voltageV = math.max(voltageV[index] - math.max(demandA[index], 0) * node.circuitOhm, 0)
    end
end

---Moves the charge of two linked circuits over a duration
local function advancePair(a, b, elapsedMs)
    local steps = math.clamp(math.ceil(elapsedMs / PAIR_STEP_MS), 1, PAIR_MAX_STEPS)
    local stepHours = elapsedMs / HOUR_MS / steps

    for _ = 1, steps do
        solvePair(a, b)
        for _, node in ipairs({ a, b }) do
            local soc = node.soc + node.batteryA * stepHours / node.capacityAh
            if node.batteryA < 0 then
                soc = math.max(soc, node.floorSoc)
            end
            node.soc = math.clamp(soc, 0, 1)
        end
    end

    solvePair(a, b)
end

---Returns the time a circuit lived since its last pass
local function getElapsed(spec, dt, isWorking)
    local worldTime = RMS_Thermal.getWorldTimeMS()
    local previousTime = spec._electricalWorldTime
    spec._electricalWorldTime = worldTime

    local worldElapsedMs = dt
    if worldTime ~= nil then
        worldElapsedMs = previousTime ~= nil and math.max(worldTime - previousTime, 0) or 0
    end

    return isWorking and dt or worldElapsedMs, worldElapsedMs
end

---Returns the draw of a parked machine's circuit on its battery
local function getRestingDraw(spec)
    local C = RMS_Config.ELECTRICAL
    local rating = spec.electricalRating
    return ((rating.hasCalculators and C.STANDBY_A or 0) + spec.circuitLeakageFactor * C.LEAKAGE_FAULT_A) / rating.seriesBatteries
end
RMS_Electrical.getRestingDraw = getRestingDraw

---Takes self-discharge and resting draw off the charge, on the game calendar
local function applyCalendarLosses(node, worldElapsedMs)
    local C = RMS_Config.ELECTRICAL
    local months = worldElapsedMs / DAY_MS / g_currentMission.environment.daysPerPeriod

    local warmth = (node.ambientC - C.SELF_DISCHARGE_REFERENCE_TEMP_C) / C.SELF_DISCHARGE_DOUBLING_C
    node.soc = math.max(node.soc - C.SELF_DISCHARGE_PER_MONTH * 2 ^ warmth * months / node.spec.batteryHealth, 0)

    if not node.isRunning and not node.spec.batteryIsolated and node.soc > node.floorSoc then
        local drawn = getRestingDraw(node.spec) * C.MONTH_HOURS * months / node.capacityAh
        node.soc = math.max(node.soc - drawn, node.floorSoc)
    end
end

local function commitNode(node, dt)
    local spec = node.spec
    spec.batterySoc = node.soc
    spec.rawSystemVoltageV = node.voltageV

    local alpha = dt / (RMS_Config.ELECTRICAL.SYSTEM_VOLTAGE_TAU_MS + dt)
    spec.systemVoltageV = spec.systemVoltageV + alpha * (node.voltageV - spec.systemVoltageV)
    spec.electricalBalance = node
end

---Returns the machine at the other end of the jumper cables
local function getCablePartner(vehicle)
    local partner = vehicle.spec_RealisticMechanicalSystems.externalPowerConnection
    if partner == nil then
        return nil
    end

    if math.abs(vehicle:getLastSpeed()) > 1 or math.abs(partner:getLastSpeed()) > 1 then
        vehicle:clearExternalPowerConnection(partner)
        return nil
    end

    return partner
end

---Runs one step of a circuit, and of the one linked to it by cables
-- @param float dt time since last call in ms
function RMS_Electrical:updateBatteryChargingModel(dt)
    local spec = self.spec_RealisticMechanicalSystems
    dt = sanitizeNumber(dt, 0, 0)
    if not self.isServer or dt <= 0 then
        return
    end

    -- Solve a linked battery pair only once per frame.
    local solveStamp = g_currentMission.time
    if spec._electricalSolveStamp == solveStamp then
        return
    end

    local node = buildNode(self)
    local partner = getCablePartner(self)
    if partner ~= nil then
        local partnerSpec = partner.spec_RealisticMechanicalSystems
        local partnerNode = buildNode(partner)
        local isWorking = node.isRunning or node.isCranking or node.loads.preheat > 0
            or partnerNode.isRunning or partnerNode.isCranking or partnerNode.loads.preheat > 0
        local elapsedMs, worldElapsedMs = getElapsed(spec, dt, isWorking)
        getElapsed(partnerSpec, dt, isWorking)

        applyCalendarLosses(node, worldElapsedMs)
        applyCalendarLosses(partnerNode, worldElapsedMs)
        advancePair(node, partnerNode, elapsedMs)
        commitNode(node, dt)
        commitNode(partnerNode, dt)

        spec._electricalSolveStamp = solveStamp
        partnerSpec._electricalSolveStamp = solveStamp
        return
    end

    local isWorking = node.isRunning or node.isCranking or node.loads.preheat > 0
    local elapsedMs, worldElapsedMs = getElapsed(spec, dt, isWorking)
    applyCalendarLosses(node, worldElapsedMs)
    advanceNode(node, elapsedMs / HOUR_MS)
    commitNode(node, dt)

    if spec.batteryCharger ~= nil then
        RMS_BatteryCharger.onBatteryUpdated(self, node.chargerOutA, node.batteryA)
    end
end

---Returns the voltage the circuit would hold if started now
-- @param table vehicle vehicle
-- @return float voltage circuit voltage under starting load
function RMS_Electrical.getStartingVoltage(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    if spec.batteryIsolated then
        return 0
    end

    local node = buildNode(vehicle, true)
    local partner = spec.externalPowerConnection
    if partner ~= nil then
        solvePair(node, buildNode(partner))
    else
        solveNode(node)
    end

    return node.voltageV
end

---Returns the lowest voltage that still turns the starter of a machine
-- @param table vehicle vehicle
-- @return float voltage minimum cranking voltage of its batteries in series
function RMS_Electrical.getMinCrankingVoltage(vehicle)
    return RMS_Config.ELECTRICAL.MIN_CRANKING_VOLTAGE_V * vehicle.spec_RealisticMechanicalSystems.electricalRating.seriesBatteries
end

---Tells whether the circuit can start the machine
-- @param table vehicle vehicle
-- @return boolean canStart true when the circuit holds
function RMS_Electrical.getCanStart(vehicle)
    local voltageV = RMS_Electrical.getStartingVoltage(vehicle)
    if vehicle.spec_RealisticMechanicalSystems.isElectricVehicle then
        return voltageV > 0
    end
    return voltageV >= RMS_Electrical.getMinCrankingVoltage(vehicle)
end

---Returns how fast the starter turns, against a full battery on a mild engine
-- @param table vehicle vehicle
-- @return float speed 0 when the starter cannot turn, 1 at its reference speed
function RMS_Electrical.getCrankingSpeed(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    local voltageV = RMS_Electrical.getStartingVoltage(vehicle)
    if voltageV < RMS_Electrical.getMinCrankingVoltage(vehicle) then
        return 0
    end

    local engineC = tonumber(spec.rawEngineTemperature)
    if engineC == nil or engineC <= -99 then
        engineC = RMS_Utils.getAmbientTemperature()
    end
    return math.min(voltageV / spec.electricalRating.referenceCrankingV, 1)
        * interpolate(RMS_Config.ELECTRICAL.CRANKING_DRAG_CURVE, engineC)
        * spec.starterHealth
end

---Tells whether the lights of a machine stay off whatever asks for them
-- @param table vehicle root vehicle
-- @return boolean keepsOff isolator open or waiting AI worker
function RMS_Electrical.getKeepsLightsOff(vehicle)
    if vehicle.spec_RealisticMechanicalSystems.batteryIsolated then
        return true
    end

    -- Native and driving-mod updates reapply AI light requests.
    return vehicle:getIsAIActive() and not vehicle:getIsMotorStarted() and not vehicle:getIsControlled()
end

---Tells whether a machine carries a battery isolator, every RMS machine
-- @param table vehicle vehicle
-- @return boolean hasIsolator true on a machine the mod runs
function RMS_Electrical.getHasBatteryIsolator(vehicle)
    return not vehicle.spec_RealisticMechanicalSystems.isExcludedVehicle
end

---Opens or closes the battery isolator of a machine, on the server
-- @param table vehicle vehicle
-- @param boolean isIsolated true to cut the battery off
function RMS_Electrical.setBatteryIsolated(vehicle, isIsolated)
    local spec = vehicle.spec_RealisticMechanicalSystems
    if spec.batteryIsolated == isIsolated then
        return
    end

    spec.batteryIsolated = isIsolated
    if isIsolated and vehicle.spec_lights ~= nil and vehicle:getLightsTypesMask() ~= 0 then
        vehicle:setLightsTypesMask(0, true)
    end
    RMS_Electrical.playBatteryIsolatorSound(vehicle)
end

---Returns the text refusing to move the battery isolator
-- @param table vehicle vehicle
-- @return string? reason text key, nil when the isolator may be moved
function RMS_Electrical.getBatteryIsolatorRefusal(vehicle)
    if vehicle:getMotorState() ~= MotorState.OFF then
        return "rms_battery_isolator_engine_running"
    end
    return nil
end

---Opens or closes the battery isolator a player asks for, on the server
-- @param table vehicle vehicle
-- @param boolean isIsolated true to cut the battery off
function RMS_Electrical.requestBatteryIsolated(vehicle, isIsolated)
    if RMS_Electrical.getHasBatteryIsolator(vehicle) and RMS_Electrical.getBatteryIsolatorRefusal(vehicle) == nil then
        RMS_Electrical.setBatteryIsolated(vehicle, isIsolated)
    end
end

---Plays the click of the battery isolator on the machine
-- @param table vehicle vehicle
function RMS_Electrical.playBatteryIsolatorSound(vehicle)
    if vehicle.isClient then
        RMS_SoundManager.playSample(vehicle.spec_RealisticMechanicalSystems.samples.batteryIsolator)
    end
end

---Adds or removes the dead battery breakdown
function RMS_Electrical:syncDeadBatteryEffect()
    local spec = self.spec_RealisticMechanicalSystems
    if not self.isServer then
        return
    end

    local breakdownId = "DEAD_BATTERY"
    local isDead = false
    if spec.batteryIsolated then
        isDead = false
    elseif self:getIsMotorStarted() then
        isDead = spec.rawSystemVoltageV <= 0
    else
        isDead = not RMS_Electrical.getCanStart(self)
    end

    if isDead and not self:hasBreakdown(breakdownId) then
        self:addBreakdown(breakdownId)
        if spec.isCranking then
            for _, effectId in ipairs({ "ENGINE_HARD_START_MODIFIER", "GLOW_PLUG_HARD_START_MODIFIER", "ENGINE_FAILURE" }) do
                local effect = spec.activeEffects[effectId]
                if effect ~= nil and effect.extraData ~= nil and effect.extraData.status ~= nil then
                    effect.extraData.status = "IDLE"
                    effect.extraData.automaticCrank = false
                end
            end
        end
    elseif not isDead and self:hasBreakdown(breakdownId) then
        self:removeBreakdown(breakdownId)
    end
end

---Adds or removes the voltage sag breakdown
-- @param float dt time since last call in ms
function RMS_Electrical:syncVoltageSagEffect(dt)
    local spec = self.spec_RealisticMechanicalSystems
    if not self.isServer then
        return
    end

    local C = RMS_Config.ELECTRICAL
    local breakdownId = "VOLTAGE_SAG"
    spec.syncVoltageSagEffectTimer = spec.syncVoltageSagEffectTimer or C.VOLTAGE_SAG_DELAY_MS

    if self:hasBreakdown("DEAD_BATTERY") or spec.batteryIsolated then
        spec.syncVoltageSagEffectTimer = C.VOLTAGE_SAG_DELAY_MS
        if self:hasBreakdown(breakdownId) then
            self:removeBreakdown(breakdownId)
        end
        return
    end

    if spec.isCranking then
        return
    end

    if spec.rawSystemVoltageV >= C.VOLTAGE_SAG_V * spec.electricalRating.seriesBatteries then
        spec.syncVoltageSagEffectTimer = C.VOLTAGE_SAG_DELAY_MS
        if self:hasBreakdown(breakdownId) then
            self:removeBreakdown(breakdownId)
        end
    elseif not self:hasBreakdown(breakdownId) then
        spec.syncVoltageSagEffectTimer = spec.syncVoltageSagEffectTimer - dt
        if spec.syncVoltageSagEffectTimer <= 0 then
            self:addBreakdown(breakdownId)
            spec.syncVoltageSagEffectTimer = C.VOLTAGE_SAG_DELAY_MS
        end
    end
end

---Tells whether two vehicles may be linked by jumper cables
-- @param table? vehicleA first vehicle
-- @param table? vehicleB second vehicle
-- @return boolean isValid true when the pair is allowed
function RMS_Electrical.isValidPowerPair(vehicleA, vehicleB)
    if vehicleA == nil or vehicleB == nil or vehicleA == vehicleB then
        return false, ''
    end

    if vehicleA.getRootVehicle ~= nil then
        vehicleA = vehicleA:getRootVehicle()
    end

    if vehicleB.getRootVehicle ~= nil then
        vehicleB = vehicleB:getRootVehicle()
    end

    if vehicleA == nil or vehicleB == nil or vehicleA == vehicleB then
        return false, 'SAME'
    end

    if vehicleA.spec_RealisticMechanicalSystems == nil or vehicleB.spec_RealisticMechanicalSystems == nil then
        return false, 'NO_RMS'
    end

    if vehicleA.spec_RealisticMechanicalSystems.batteryCharger ~= nil
        or vehicleB.spec_RealisticMechanicalSystems.batteryCharger ~= nil
        or RMS_BatteryCharger.getConnectedCharger(vehicleA) ~= nil
        or RMS_BatteryCharger.getConnectedCharger(vehicleB) ~= nil then
        return false
    end

    local connectionA = vehicleA.spec_RealisticMechanicalSystems.externalPowerConnection
    local connectionB = vehicleB.spec_RealisticMechanicalSystems.externalPowerConnection
    if connectionA ~= nil and connectionA ~= vehicleB or connectionB ~= nil and connectionB ~= vehicleA then
        return false, 'BUSY'
    end

    local nodeA = vehicleA.rootNode
    if nodeA == nil and vehicleA.components ~= nil and vehicleA.components[1] ~= nil then
        nodeA = vehicleA.components[1].node
    end

    local nodeB = vehicleB.rootNode
    if nodeB == nil and vehicleB.components ~= nil and vehicleB.components[1] ~= nil then
        nodeB = vehicleB.components[1].node
    end

    if nodeA == nil or nodeB == nil then
        return false, ''
    end

    local ax, ay, az = getWorldTranslation(nodeA)
    local bx, by, bz = getWorldTranslation(nodeB)
    local dx = bx - ax
    local dy = by - ay
    local dz = bz - az

    if MathUtil.vector3Length(dx, dy, dz) > RMS_Config.FIELD_CARE.JUMPER_CABLES_MAX_CONNECTION_DISTANCE then
        return false, 'TOO_FAR'
    end

    local specA = vehicleA.spec_RealisticMechanicalSystems
    local specB = vehicleB.spec_RealisticMechanicalSystems
    if specA.electricalRating.seriesBatteries ~= specB.electricalRating.seriesBatteries then
        return false, 'VOLTAGE'
    end

    local electricSpec, engineSpec = nil, nil
    if specA.isElectricVehicle and not specB.isElectricVehicle then
        electricSpec, engineSpec = specA, specB
    elseif specB.isElectricVehicle and not specA.isElectricVehicle then
        electricSpec, engineSpec = specB, specA
    end
    if electricSpec ~= nil and electricSpec.batterySoc > engineSpec.batterySoc then
        return false, 'ELECTRIC_DONOR'
    end

    return true
end

---Records the jumper cable link toward another vehicle
-- @param table externalConnection vehicle at the other end
function RMS_Electrical:establishExternalPowerConnection(externalConnection)
    local spec = self.spec_RealisticMechanicalSystems
    if spec == nil or not self.isServer then
        return
    end

    local otherVehicle = externalConnection
    if otherVehicle ~= nil and otherVehicle.getRootVehicle ~= nil then
        otherVehicle = otherVehicle:getRootVehicle()
    end

    local otherSpec = otherVehicle ~= nil and otherVehicle.spec_RealisticMechanicalSystems or nil
    local isValid, reason = RMS_Electrical.isValidPowerPair(self, otherVehicle)

    if reason == 'BUSY' then
        return false
    end
    if isValid then
        spec.externalPowerConnection = otherVehicle
        if otherSpec ~= nil then
            otherSpec.externalPowerConnection = self
        end
        return true
    else
        spec.externalPowerConnection = nil
        if otherSpec ~= nil and otherSpec.externalPowerConnection == self then
            otherSpec.externalPowerConnection = nil
        end
        return false
    end
end

---Drops the jumper cable link toward another vehicle
-- @param table? otherVehicle vehicle at the other end
function RMS_Electrical:clearExternalPowerConnection(otherVehicle)
    local spec = self.spec_RealisticMechanicalSystems
    if spec == nil or not self.isServer then
        return false
    end

    local normalizedOther = otherVehicle
    if normalizedOther ~= nil and normalizedOther.getRootVehicle ~= nil then
        normalizedOther = normalizedOther:getRootVehicle()
    end
    if normalizedOther == nil then
        normalizedOther = spec.externalPowerConnection
    end

    spec.externalPowerConnection = nil

    local otherSpec = normalizedOther ~= nil and normalizedOther.spec_RealisticMechanicalSystems or nil
    if otherSpec ~= nil and otherSpec.externalPowerConnection == self then
        otherSpec.externalPowerConnection = nil
    end

    return true
end
