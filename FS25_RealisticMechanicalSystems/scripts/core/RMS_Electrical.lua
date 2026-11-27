-- Copyright © 2026 Squallqt. All rights reserved.

---Low-voltage electrical system
RMS_Electrical = {}

local DAY_MS = 24 * 60 * 60 * 1000
local HOUR_MS = 60 * 60 * 1000
local MIN_CAPACITY_AH = 0.01
-- Substep linked batteries to limit charge-transfer overshoot
local PAIR_STEP_MS = 30000
local PAIR_MAX_STEPS = 120

---Returns the value of a curve at x, held at its ends
-- @param table curve points {x, value}
-- @param float x x
-- @return float value value
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

---Returns the value of the first step reaching x
-- @param table steps steps {up to x, value}
-- @param float x x
-- @return any? value value, nil past the last step
local function pickStep(steps, x)
    for _, step in ipairs(steps) do
        if x <= step[1] then
            return step[2]
        end
    end
end

---Returns a value rounded to a catalogue step
-- @param float value value
-- @param float step step
-- @return float value value rounded
local function toCatalogueStep(value, step)
    return math.floor(value / step + 0.5) * step
end

---Tells whether no configuration hides a lamp of the machine
-- @param table vehicle vehicle
-- @param entityId node node of the lamp
-- @return boolean isMounted true when no configuration hides it
function RMS_Electrical.getIsLampMounted(vehicle, node)
    local isComponent = false
    while node ~= 0 and not isComponent do
        if not getVisibility(node) then
            return false
        end
        for _, component in ipairs(vehicle.components) do
            isComponent = isComponent or component.node == node
        end
        node = getParent(node)
    end
    return true
end

---Tells whether one of the lights is mounted
-- @param table vehicle vehicle
-- @param table lights lights
-- @return boolean holdsLamp true when one is mounted
local function getHoldsMountedLamp(vehicle, lights)
    for _, light in ipairs(lights) do
        if RMS_Electrical.getIsLampMounted(vehicle, light.node) then
            return true
        end
    end
    return false
end

---Tells whether the machine carries turn lights
-- @param table vehicle vehicle
-- @return boolean carriesTurnLights true with turn lights
function RMS_Electrical.getCarriesTurnLights(vehicle)
    local spec = vehicle.spec_lights
    if spec == nil then
        return false
    end
    if getHoldsMountedLamp(vehicle, spec.staticLights.turnLightsLeft) then
        return true
    end
    for _, profile in pairs(spec.realLights) do
        if getHoldsMountedLamp(vehicle, profile.turnLightsLeft) then
            return true
        end
    end
    return false
end

---Returns the number of beacons on the machine
-- @param table vehicle vehicle
-- @return integer count number of beacons
function RMS_Electrical.getMountedBeaconCount(vehicle)
    if vehicle.spec_lights == nil then
        return 0
    end
    local count = 0
    for _, beaconLight in ipairs(vehicle.spec_lights.beaconLights) do
        if beaconLight.linkNode ~= nil and RMS_Electrical.getIsLampMounted(vehicle, beaconLight.linkNode)
            or beaconLight.linkNode == nil and getHoldsMountedLamp(vehicle, beaconLight.staticLights) then
            count = count + 1
        end
    end
    return count
end

---Sizes the circuit of a machine from its family, its power and its year
-- @param table vehicle vehicle
-- @return table rating ratings of the circuit
function RMS_Electrical.resolveRating(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    local C = RMS_Config.ELECTRICAL
    local law = C.RATING
    local family = RMS_Fluids.getProfileName(vehicle)
    local power = math.clamp(RMS_Fluids.getEnginePower(vehicle), law.POWER_RANGE_HP[1], law.POWER_RANGE_HP[2])
    local year = math.clamp(spec.year, law.YEAR_RANGE[1], law.YEAR_RANGE[2])

    ---Returns a rating at the power and the year of the machine
    -- @param table entry base, power exponent and decade factor of the rating
    -- @return float value rating
    local function size(entry)
        return entry.base * (power / 100) ^ entry.powerExponent * entry.decadeFactor ^ ((year - 2000) / 10)
    end

    local is24V = law.SYSTEM_24V_FAMILIES[family] or family == "WHEEL_LOADER" and power > law.WHEEL_LOADER_24V_ABOVE_HP
    local series = is24V and 2 or 1
    local rating = { seriesBatteries = series }
    if family == "ROAD_LIGHT" then
        rating.alternatorA = law.ROAD_LIGHT.alternatorA
        rating.batteryCapacityAh = law.ROAD_LIGHT.batteryCapacityAh
        rating.starterKw = law.ROAD_LIGHT.starterKw
    else
        local alternatorA = family == "TELEHANDLER" and law.TELEHANDLER_ALTERNATOR_A or size(law.ALTERNATOR_A)
        rating.alternatorA = toCatalogueStep(alternatorA / series, law.ALTERNATOR_STEP_A)
        rating.batteryCapacityAh = is24V and law.BATTERY_24V_AH or toCatalogueStep(size(law.BATTERY_AH), law.BATTERY_STEP_AH)
        rating.starterKw = size(law.STARTER_KW)
    end

    rating.hasCalculators = spec.isElectricVehicle or RMS_Utils.getUsesEngineECUProfile(vehicle)
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
    rating.workLightsSideA = workLamps / 2 * lampW / (C.LAMP_VOLTAGE_V * series)
    local beaconA = year < C.LED_YEARS.BEACON_LIGHTS_FAILURE and C.BEACON_HALOGEN_A or C.BEACON_LED_W / C.LAMP_VOLTAGE_V
    rating.beaconsA = RMS_Electrical.getMountedBeaconCount(vehicle) * beaconA / series
    local turnLampW = year < C.LED_YEARS.TURN_LIGHTS_FAILURE and C.TURN_LAMP_BULB_W or C.TURN_LAMP_LED_W
    rating.turnLightsSideA = RMS_Electrical.getCarriesTurnLights(vehicle)
        and C.TURN_LAMPS_PER_SIDE * turnLampW * C.TURN_LIGHT_DUTY / (C.LAMP_VOLTAGE_V * series) or 0
    local glowPlugs = family == "ROAD_LIGHT" and law.ROAD_LIGHT.glowPlugs or pickStep(C.GLOW_PLUGS_BY_POWER, power)
    rating.glowPlugsA = glowPlugs * C.GLOW_PLUG_A / series

    local curve, resistance, current = C.OCV_CURVE, C.INTERNAL_RESISTANCE_CURVE, C.STARTER_CURRENT_CURVE
    rating.starterRatedA = rating.starterKw * current[#current][2] / series
    rating.referenceCrankingV = (curve[#curve][2]
        - rating.starterRatedA * resistance[#resistance][2] / rating.batteryCapacityAh) * series

    return rating
end

---Returns the resting voltage of the batteries at a charge
-- @param table rating ratings of the circuit
-- @param float soc state of charge, 0 to 1
-- @return float voltage voltage (V)
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
-- @return float capacity capacity (Ah)
function RMS_Electrical.getBatteryCapacityAh(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    return math.max(spec.electricalRating.batteryCapacityAh * spec.batteryHealth, MIN_CAPACITY_AH)
end

---Returns the current of the alternator, or of the converter of an electric machine
-- @param table vehicle vehicle
-- @param table spec RMS specialization of the vehicle
-- @param boolean isRunning true while the engine runs
-- @return float current current (A)
local function getGeneratorOutput(vehicle, spec, isRunning)
    local ratedA = spec.electricalRating.alternatorA * spec.alternatorHealth

    if spec.isElectricVehicle then
        return (isRunning or RMS_ElectricDrive.getIsCharging(vehicle)) and ratedA or 0
    end
    if not isRunning then
        return 0
    end

    local idleFactor = RMS_Config.ELECTRICAL.ALTERNATOR_IDLE_FACTOR
    return ratedA * (idleFactor + (1 - idleFactor) * RMS_Utils.getMotorRpmShareAboveIdle(vehicle))
end

---Returns the currents the consumers draw
-- @param table vehicle vehicle
-- @param table spec RMS specialization of the vehicle
-- @param boolean isRunning true while the engine runs
-- @param boolean isCranking true while the starter turns
-- @param float ambientC ambient temperature (deg C)
-- @return table loads current of each consumer (A)
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
        -- Light types: 0 road, 1 rear work, 2 front work
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
        if vehicle:getBeaconLightsVisibility() then
            loads.lights = loads.lights + rating.beaconsA
        end
        local turnLightState = vehicle:getTurnLightState()
        if turnLightState == Lights.TURNLIGHT_HAZARD then
            loads.lights = loads.lights + 2 * rating.turnLightsSideA
        elseif turnLightState ~= Lights.TURNLIGHT_OFF then
            loads.lights = loads.lights + rating.turnLightsSideA
        end
    end

    if isCranking then
        loads.starter = rating.starterKw * interpolate(C.STARTER_CURRENT_CURVE, ambientC) / series
    end
    if RMS_Preheat.isHeating(vehicle) and not isCranking and RMS_Preheat.getGlowPlugFailureSeverity(vehicle) < 4 then
        loads.preheat = rating.glowPlugsA
    end

    loads.total = loads.base + loads.cab + loads.lights + loads.starter + loads.preheat
    return loads
end

---Tells whether a machine is being started at this instant
-- @param table vehicle vehicle
-- @return boolean isStarting true while the starter turns
function RMS_Electrical.getIsStarting(vehicle)
    return RMS_Start.getIsCranking(vehicle)
end

---Returns the circuit of a machine at this instant
-- @param table vehicle vehicle
-- @param boolean? isStarting true while the starter turns
-- @return table node circuit
local function buildNode(vehicle, isStarting)
    local spec = vehicle.spec_RealisticMechanicalSystems
    local C = RMS_Config.ELECTRICAL
    local rating = spec.electricalRating
    local ambientC = RMS_Utils.getAmbientTemperature()
    local isRunning = vehicle:getIsMotorStarted()
    local isCranking = not spec.isElectricVehicle and (isStarting or RMS_Electrical.getIsStarting(vehicle))
    local capacityAh = RMS_Electrical.getBatteryCapacityAh(vehicle)

    local node = {
        rating = rating,
        ambientC = ambientC,
        isRunning = isRunning,
        isCranking = isCranking,
        capacityAh = capacityAh,
        soc = spec.batterySoc,
        floorSoc = interpolate(C.INACCESSIBLE_CHARGE_CURVE, ambientC),
        resistanceOhm = interpolate(C.INTERNAL_RESISTANCE_CURVE, ambientC) / capacityAh * rating.seriesBatteries
            * (1 + (C.EMPTY_RESISTANCE_FACTOR - 1) * (1 - spec.batterySoc)),
        circuitOhm = spec.circuitResistanceFactor * C.CIRCUIT_ADMISSIBLE_DROP_V * rating.seriesBatteries / rating.starterRatedA,
        generatorA = 0,
        chargerA = 0,
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
        node.chargerA = RMS_BatteryCharger.getAvailableCurrent(vehicle, isCranking)
    end
    -- held up by a charger, the cold keeps no charge of the battery back
    node.reachSoc = node.chargerA > 0 and 0 or node.floorSoc

    return node
end

---Returns the charge current the battery accepts
-- @param table node circuit
-- @return float current current (A)
local function getAcceptance(node)
    local C = RMS_Config.ELECTRICAL
    if node.soc >= 1 then
        return 0
    end

    local rate = node.soc < C.CHARGE_TOPPING_SOC and C.CHARGE_ACCEPTANCE_BULK or C.CHARGE_ACCEPTANCE_TOPPING
    return rate * node.capacityAh
end

---Solves the battery current and the voltage of a circuit
-- @param table node circuit
local function solveNode(node)
    local restingV = getRestingVoltage(node.rating, node.soc)
    local shortfallA = node.loads.total - node.generatorA - node.chargerA

    if shortfallA <= 0 then
        node.batteryA = math.min(-shortfallA, getAcceptance(node))
        local isFed = node.generatorA + node.chargerA > 0
        node.voltageV = isFed and RMS_Config.ELECTRICAL.REGULATED_VOLTAGE_V * node.rating.seriesBatteries or restingV
        node.chargerOutA = math.max(node.loads.total + node.batteryA - node.generatorA, 0)
    elseif node.soc > node.reachSoc then
        node.batteryA = -shortfallA
        node.voltageV = math.max(restingV - shortfallA * (node.resistanceOhm + node.circuitOhm), 0)
        node.chargerOutA = node.chargerA
    else
        node.batteryA = 0
        node.voltageV = 0
        node.chargerOutA = node.chargerA
    end
end

---Advances the charge of a circuit over hours, through its charge stages
-- @param table node circuit
-- @param float hours hours
local function advanceNode(node, hours)
    local C = RMS_Config.ELECTRICAL

    for _ = 1, 3 do
        solveNode(node)
        if hours <= 0 or node.batteryA == 0 then
            return
        end

        local targetSoc = node.reachSoc
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

---Solves the currents and voltages of two circuits linked by cables
-- @param table a first circuit
-- @param table b second circuit
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
    -- held up by the other machine, the cold keeps no charge back
    local isLive = { a.soc > a.floorSoc or a.generatorA > 0, b.soc > b.floorSoc or b.generatorA > 0 }
    a.reachSoc = isLive[2] and 0 or a.floorSoc
    b.reachSoc = isLive[1] and 0 or b.floorSoc

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
                if batteryA < 0 and node.soc <= node.reachSoc then
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

---Advances the charge of two linked circuits in substeps
-- @param table a first circuit
-- @param table b second circuit
-- @param float elapsedMs time elapsed (ms)
local function advancePair(a, b, elapsedMs)
    local steps = math.clamp(math.ceil(elapsedMs / PAIR_STEP_MS), 1, PAIR_MAX_STEPS)
    local stepHours = elapsedMs / HOUR_MS / steps

    for _ = 1, steps do
        solvePair(a, b)
        for _, node in ipairs({ a, b }) do
            local soc = node.soc + node.batteryA * stepHours / node.capacityAh
            if node.batteryA < 0 then
                soc = math.max(soc, node.reachSoc)
            end
            node.soc = math.clamp(soc, 0, 1)
        end
    end

    solvePair(a, b)
end

---Returns the time elapsed for the circuit and the world time elapsed
-- @param table spec RMS specialization of the vehicle
-- @param float dt time of the step (ms)
-- @param boolean isWorking true while the circuit works
-- @return float elapsedMs time elapsed for the circuit (ms)
-- @return float worldElapsedMs world time elapsed (ms)
local function getElapsed(spec, dt, isWorking)
    local worldTime = RMS_Thermal.getWorldTimeMS()
    local previousTime = spec._electricalWorldTime
    spec._electricalWorldTime = worldTime

    local worldElapsedMs = previousTime ~= nil and math.max(worldTime - previousTime, 0) or 0

    return isWorking and dt or worldElapsedMs, worldElapsedMs
end

---Returns the current drawn with the engine off
-- @param table spec RMS specialization of the vehicle
-- @return float current current of one battery (A)
local function getRestingDraw(spec)
    local C = RMS_Config.ELECTRICAL
    local rating = spec.electricalRating
    return ((rating.hasCalculators and C.STANDBY_A or 0) + spec.circuitLeakageFactor * C.LEAKAGE_FAULT_A) / rating.seriesBatteries
end
RMS_Electrical.getRestingDraw = getRestingDraw

---Takes the self discharge and the resting draw off the charge
-- @param table node circuit
-- @param table spec RMS specialization of the vehicle
-- @param float worldElapsedMs world time elapsed (ms)
local function applyCalendarLosses(node, spec, worldElapsedMs)
    local C = RMS_Config.ELECTRICAL
    local months = worldElapsedMs / DAY_MS / g_currentMission.environment.daysPerPeriod

    local warmth = (node.ambientC - C.SELF_DISCHARGE_REFERENCE_TEMP_C) / C.SELF_DISCHARGE_DOUBLING_C
    node.soc = math.max(node.soc - C.SELF_DISCHARGE_PER_MONTH * 2 ^ warmth * months / spec.batteryHealth, 0)

    if not node.isRunning and not spec.batteryIsolated and node.soc > node.floorSoc then
        local drawn = getRestingDraw(spec) * C.MONTH_HOURS * months / node.capacityAh
        node.soc = math.max(node.soc - drawn, node.floorSoc)
    end
end

---Stores the charge and eases the voltmeter
-- @param table node circuit
-- @param table spec RMS specialization of the vehicle
-- @param float dt time of the step (ms)
local function commitNode(node, spec, dt)
    spec.batterySoc = node.soc
    spec.rawSystemVoltageV = node.voltageV

    local alpha = dt / (RMS_Config.ELECTRICAL.SYSTEM_VOLTAGE_TAU_MS + dt)
    spec.systemVoltageV = spec.systemVoltageV + alpha * (node.voltageV - spec.systemVoltageV)
    spec.electricalBalance = node
end

---Returns the machine linked by cables, unlinked once one of them moves
-- @param table vehicle vehicle
-- @return table? partner machine linked
local function getCablePartner(vehicle)
    local partner = vehicle.spec_RealisticMechanicalSystems.externalPowerConnection
    if partner == nil then
        return nil
    end

    if math.abs(vehicle:getLastSpeed()) > 1 or math.abs(partner:getLastSpeed()) > 1 then
        vehicle:clearExternalPowerConnection()
        return nil
    end

    return partner
end

---Runs one step of a circuit, and of the one linked to it by cables
-- @param float dt time of the step (ms)
function RMS_Electrical:updateBatteryChargingModel(dt)
    local spec = self.spec_RealisticMechanicalSystems
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
        -- each machine steps the pair in its own frame
        local lastSolve = math.max(spec._electricalSolveStamp or -math.huge, partnerSpec._electricalSolveStamp or -math.huge)
        local elapsedMs, worldElapsedMs = getElapsed(spec, math.min(solveStamp - lastSolve, dt), isWorking)
        getElapsed(partnerSpec, dt, isWorking)

        applyCalendarLosses(node, spec, worldElapsedMs)
        applyCalendarLosses(partnerNode, partnerSpec, worldElapsedMs)
        advancePair(node, partnerNode, elapsedMs)
        commitNode(node, spec, dt)
        commitNode(partnerNode, partnerSpec, dt)

        spec._electricalSolveStamp = solveStamp
        partnerSpec._electricalSolveStamp = solveStamp
        return
    end

    local isWorking = node.isRunning or node.isCranking or node.loads.preheat > 0
    local elapsedMs, worldElapsedMs = getElapsed(spec, dt, isWorking)
    applyCalendarLosses(node, spec, worldElapsedMs)
    advanceNode(node, elapsedMs / HOUR_MS)
    commitNode(node, spec, dt)

    if spec.batteryCharger ~= nil then
        RMS_BatteryCharger.onBatteryUpdated(self, node.chargerOutA, node.batteryA)
    end
end

---Returns the voltage of the circuit solved at this instant
-- @param table vehicle vehicle
-- @param boolean? isStarting true while the starter turns
-- @return float voltage voltage (V)
local function getVoltageNow(vehicle, isStarting)
    local node = buildNode(vehicle, isStarting)
    local partner = vehicle.spec_RealisticMechanicalSystems.externalPowerConnection
    if partner ~= nil then
        solvePair(node, buildNode(partner))
    else
        solveNode(node)
    end

    return node.voltageV
end

---Returns the voltage the circuit would hold if started now
-- @param table vehicle vehicle
-- @return float voltage voltage (V), 0 with the isolator open
function RMS_Electrical.getStartingVoltage(vehicle)
    if vehicle.spec_RealisticMechanicalSystems.batteryIsolated then
        return 0
    end
    return getVoltageNow(vehicle, true)
end

---Returns the lowest voltage that still turns the starter of a machine
-- @param table vehicle vehicle
-- @return float voltage voltage (V)
function RMS_Electrical.getMinCrankingVoltage(vehicle)
    return RMS_Config.ELECTRICAL.MIN_CRANKING_VOLTAGE_V * vehicle.spec_RealisticMechanicalSystems.electricalRating.seriesBatteries
end

---Tells whether the circuit can start the machine
-- @param table vehicle vehicle
-- @return boolean canStart true when it can
function RMS_Electrical.getCanStart(vehicle)
    local voltageV = RMS_Electrical.getStartingVoltage(vehicle)
    if vehicle.spec_RealisticMechanicalSystems.isElectricVehicle then
        return voltageV > 0
    end
    return voltageV >= RMS_Electrical.getMinCrankingVoltage(vehicle)
end

---Returns how fast the starter turns, against a full battery on a mild engine
-- @param table vehicle vehicle
-- @return float speed speed, 0 to 1
function RMS_Electrical.getCrankingSpeed(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    local voltageV = RMS_Electrical.getStartingVoltage(vehicle)
    if voltageV < RMS_Electrical.getMinCrankingVoltage(vehicle) then
        return 0
    end

    return math.min(voltageV / spec.electricalRating.referenceCrankingV, 1)
        * interpolate(RMS_Config.ELECTRICAL.CRANKING_DRAG_CURVE, spec.rawEngineTemperature)
        * spec.starterHealth
end

---Returns how long the starter may crank from rest and how fast it cools
-- @param table vehicle vehicle
-- @return float limitS cranking that brings it to its permissible rise (s)
-- @return float coolingS time constant of its cooling (s)
local function getStarterHeatTimes(vehicle)
    local C = RMS_Config.ELECTRICAL
    local limitS = C.STARTER_HEAT_LIMIT_S[RMS_Breakdowns.getStarterFamily(vehicle)]
    return limitS, limitS * C.STARTER_REST_PER_CRANK / math.log(C.STARTER_PERMISSIBLE_RISE_K / RMS_Config.CORE.HEAT_HALVING_K)
end

---Heats the starter while it turns and cools it at rest
-- @param table vehicle vehicle
-- @param float dt time of the step (ms)
-- @param boolean isTurning true while the starter turns
function RMS_Electrical.updateStarterHeat(vehicle, dt, isTurning)
    local spec = vehicle.spec_RealisticMechanicalSystems
    local C = RMS_Config.ELECTRICAL
    local riseK = C.STARTER_PERMISSIBLE_RISE_K
    local limitS, coolingS = getStarterHeatTimes(vehicle)
    local targetK = 0
    if isTurning then
        local curve = C.STARTER_CURRENT_CURVE
        local currentRatio = interpolate(curve, RMS_Utils.getAmbientTemperature()) / curve[#curve][2]
        targetK = riseK / (1 - math.exp(-limitS / coolingS)) * currentRatio ^ 2
    end
    spec.starterHeatK = targetK + (spec.starterHeatK - targetK) * math.exp(-dt / 1000 / coolingS)
end

---Tells whether the starter is hotter than cranks and rests as its manual asks ever make it
-- @param table vehicle vehicle
-- @return boolean isOverheated true past that heat
function RMS_Electrical.getIsStarterOverheated(vehicle)
    local C = RMS_Config.ELECTRICAL
    local limitS, coolingS = getStarterHeatTimes(vehicle)
    local cycleS = limitS * (1 + C.STARTER_REST_PER_CRANK)
    return vehicle.spec_RealisticMechanicalSystems.starterHeatK > C.STARTER_PERMISSIBLE_RISE_K / (1 - math.exp(-cycleS / coolingS))
end

---Tells whether no lamp of a machine gets any current
-- @param table vehicle vehicle
-- @return boolean isUnpowered true when none does
function RMS_Electrical.getIsUnpowered(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    return spec.batteryIsolated or spec.activeEffects.LIGHTS_FAILURE ~= nil
end

---Tells whether the lights of a machine stay off whatever asks for them
-- @param table vehicle vehicle
-- @return boolean keepsOff true when they stay off
function RMS_Electrical.getKeepsLightsOff(vehicle)
    if RMS_Electrical.getIsUnpowered(vehicle) then
        return true
    end

    -- Native and driving-mod updates reapply AI light requests
    return vehicle:getIsAIActive() and not vehicle:getIsMotorStarted() and not vehicle:getIsControlled()
end

---Puts out every lamp of a machine left without current
-- @param table vehicle vehicle
-- @param boolean? noEventSend true to send no event
function RMS_Electrical.switchOffAllLights(vehicle, noEventSend)
    if vehicle.spec_lights == nil then
        return
    end
    if vehicle:getLightsTypesMask() ~= 0 then
        vehicle:setLightsTypesMask(0, true, noEventSend)
    end
    if vehicle:getBeaconLightsVisibility() then
        vehicle:setBeaconLightsVisibility(false, true, noEventSend)
    end
    if vehicle:getTurnLightState() ~= Lights.TURNLIGHT_OFF then
        vehicle:setTurnLightState(Lights.TURNLIGHT_OFF, true, noEventSend)
    end
end

---Tells whether a machine carries a battery isolator, every RMS machine
-- @param table vehicle vehicle
-- @return boolean hasIsolator true with one
function RMS_Electrical.getHasBatteryIsolator(vehicle)
    return not vehicle.spec_RealisticMechanicalSystems.isExcludedVehicle
end

---Opens or closes the battery isolator of a machine, on the server
-- @param table vehicle vehicle
-- @param boolean isIsolated true to open it
function RMS_Electrical.setBatteryIsolated(vehicle, isIsolated)
    local spec = vehicle.spec_RealisticMechanicalSystems
    if spec.batteryIsolated == isIsolated then
        return
    end

    spec.batteryIsolated = isIsolated
    if isIsolated then
        RMS_Electrical.switchOffAllLights(vehicle)
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
-- @param boolean isIsolated true to open it
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

---Adds or removes a breakdown
-- @param table vehicle vehicle
-- @param string breakdownId breakdown
-- @param boolean isActive true to add it
local function setBreakdownActive(vehicle, breakdownId, isActive)
    if vehicle:hasBreakdown(breakdownId) ~= isActive then
        if isActive then
            vehicle:addBreakdown(breakdownId)
        else
            vehicle:removeBreakdown(breakdownId)
        end
    end
end

---Adds or removes the dead battery breakdown
function RMS_Electrical:syncDeadBatteryEffect()
    local spec = self.spec_RealisticMechanicalSystems
    if not self.isServer then
        return
    end

    local isDead = false
    if spec.batteryIsolated then
        isDead = false
    elseif self:getIsMotorStarted() then
        -- solved now: the last step may date from the starter's turn
        isDead = getVoltageNow(self) <= 0
    else
        isDead = not RMS_Electrical.getCanStart(self)
    end
    setBreakdownActive(self, "DEAD_BATTERY", isDead)
end

---Adds or removes the voltage sag breakdown
-- @param float dt time of the step (ms)
function RMS_Electrical:syncVoltageSagEffect(dt)
    local spec = self.spec_RealisticMechanicalSystems
    if not self.isServer then
        return
    end

    local C = RMS_Config.ELECTRICAL
    if self:hasBreakdown("DEAD_BATTERY") or spec.batteryIsolated then
        spec.voltageSagMs = 0
        setBreakdownActive(self, "VOLTAGE_SAG", false)
    elseif not spec.isCranking then
        local isLow = spec.rawSystemVoltageV < C.VOLTAGE_SAG_V * spec.electricalRating.seriesBatteries
        if not isLow or self:hasBreakdown("VOLTAGE_SAG") then
            spec.voltageSagMs = 0
            setBreakdownActive(self, "VOLTAGE_SAG", isLow)
        else
            spec.voltageSagMs = (spec.voltageSagMs or 0) + dt
            if spec.voltageSagMs >= C.VOLTAGE_SAG_DELAY_MS then
                spec.voltageSagMs = 0
                self:addBreakdown("VOLTAGE_SAG")
            end
        end
    end
end

---Tells whether two vehicles may be linked by jumper cables
-- @param table vehicleA first vehicle
-- @param table vehicleB second vehicle
-- @return boolean isValid true when they may
-- @return string? reason reason of a refusal, "ELECTRIC_DONOR" for an electric donor
function RMS_Electrical.isValidPowerPair(vehicleA, vehicleB)
    vehicleA, vehicleB = vehicleA:getRootVehicle(), vehicleB:getRootVehicle()
    local specA, specB = vehicleA.spec_RealisticMechanicalSystems, vehicleB.spec_RealisticMechanicalSystems
    if vehicleA == vehicleB then
        return false, "SAME"
    elseif specA == nil or specB == nil then
        return false, "NO_RMS"
    elseif specA.batteryCharger ~= nil or specB.batteryCharger ~= nil then
        return false, "CHARGER"
    elseif specA.externalPowerConnection ~= nil and specA.externalPowerConnection ~= vehicleB
        or specB.externalPowerConnection ~= nil and specB.externalPowerConnection ~= vehicleA then
        return false, "BUSY"
    elseif calcDistanceFrom(vehicleA.rootNode, vehicleB.rootNode) > RMS_Config.FIELD_CARE.JUMPER_CABLES_MAX_CONNECTION_DISTANCE then
        return false, "TOO_FAR"
    elseif specA.electricalRating.seriesBatteries ~= specB.electricalRating.seriesBatteries then
        return false, "VOLTAGE"
    end

    local electricSpec, engineSpec = specA, specB
    if specB.isElectricVehicle then
        electricSpec, engineSpec = specB, specA
    end
    local isElectricDonor = electricSpec.isElectricVehicle and not engineSpec.isElectricVehicle
        and electricSpec.batterySoc > engineSpec.batterySoc
    return not isElectricDonor, isElectricDonor and "ELECTRIC_DONOR" or nil
end

---Links or unlinks two machines on both ends
-- @param table vehicle vehicle
-- @param table partner other machine
-- @param boolean isLinked true to link them
local function setCableLink(vehicle, partner, isLinked)
    vehicle.spec_RealisticMechanicalSystems.externalPowerConnection = isLinked and partner or nil
    partner.spec_RealisticMechanicalSystems.externalPowerConnection = isLinked and vehicle or nil
end

---Records the jumper cable link toward another vehicle
-- @param table otherVehicle other machine
-- @return boolean canLink true once linked
function RMS_Electrical:establishExternalPowerConnection(otherVehicle)
    local canLink, reason = RMS_Electrical.isValidPowerPair(self, otherVehicle)
    if canLink then
        setCableLink(self, otherVehicle:getRootVehicle(), true)
    elseif reason ~= "BUSY" then
        self:clearExternalPowerConnection()
    end
    return canLink
end

---Drops the jumper cable link of a vehicle, on both ends
function RMS_Electrical:clearExternalPowerConnection()
    local partner = self.spec_RealisticMechanicalSystems.externalPowerConnection
    if partner ~= nil then
        setCableLink(self, partner, false)
    end
end
