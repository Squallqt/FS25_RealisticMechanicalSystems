-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---Debug snapshot of a vehicle, built on the server and sent to the requesting client
RMS_DebugSnapshot = {}

RMS_DebugSnapshot.REQUEST_INTERVAL_MS = 500
RMS_DebugSnapshot.MAX_SNAPSHOT_AGE_MS = 1500
RMS_DebugSnapshot.DATA_REQUEST_TTL_MS = RMS_DebugSnapshot.MAX_SNAPSHOT_AGE_MS
RMS_DebugSnapshot.ENTRY_TYPE_NUMBER = 0
RMS_DebugSnapshot.ENTRY_TYPE_BOOLEAN = 1
RMS_DebugSnapshot.ENTRY_TYPE_STRING = 2
RMS_DebugSnapshot.ENTRY_TYPE_TABLE = 3

RMS_DebugSnapshot.lastRequestedVehicle = nil
RMS_DebugSnapshot.lastRequestTime = -math.huge

local DEBUG_SECTIONS = {
    "service",
    "airFilter",
    "drivetrain",
    "engine",
    "transmission",
    "hydraulics",
    "cooling",
    "electrical",
    "chassis",
    "fuel",
    "pto",
    "battery",
    "radiator",
    "engineTemp",
    "transmissionTemp",
    "aiWorker"
}

---Copies a value the snapshot can carry, walking tables and guarding against cycles
-- @param any value value to copy
-- @param table? visited tables already copied
-- @return any copy copied value, nil for a type the snapshot cannot carry
local function copyPlainValue(value, visited)
    local valueType = type(value)
    if valueType == "number" or valueType == "boolean" or valueType == "string" then
        return value
    end
    if valueType ~= "table" then
        return nil
    end

    visited = visited or {}
    if visited[value] then
        return nil
    end
    visited[value] = true

    local result = {}
    for key, childValue in pairs(value) do
        local keyType = type(key)
        if keyType == "string" or keyType == "number" then
            local copiedValue = copyPlainValue(childValue, visited)
            if copiedValue ~= nil then
                result[key] = copiedValue
            end
        end
    end

    visited[value] = nil
    return result
end

---Copies the debug sections listed for the snapshot
-- @param table? debugData debug data of the vehicle
-- @return table copy copied sections
local function copyDebugData(debugData)
    local result = {}

    for _, sectionName in ipairs(DEBUG_SECTIONS) do
        local section = copyPlainValue((debugData or {})[sectionName])
        if section ~= nil then
            result[sectionName] = section
        end
    end

    return result
end

---Copies the accumulated wear factor statistics
-- @param table? factorStats factor statistics
-- @return table copy copied statistics
local function copyFactorStats(factorStats)
    local result = {}

    for systemKey, stats in pairs(factorStats or {}) do
        if type(stats) == "table" then
            local copiedStats = {}
            for statKey, statValue in pairs(stats) do
                if type(statKey) == "string"
                        and string.sub(statKey, 1, 1) ~= "_"
                        and type(statValue) == "number"
                        and statValue == statValue
                        and statValue ~= math.huge
                        and statValue ~= -math.huge then
                    copiedStats[statKey] = statValue
                end
            end
            result[systemKey] = copiedStats
        end
    end

    return result
end

---Writes one snapshot value, its type first so the reader knows what follows
-- @param integer streamId streamId
-- @param any value value to write
local function writeSnapshotValue(streamId, value)
    local valueType = type(value)

    if valueType == "table" then
        streamWriteUIntN(streamId, RMS_DebugSnapshot.ENTRY_TYPE_TABLE, 2)

        local keys = {}
        for key, _ in pairs(value) do
            if type(key) == "string" or type(key) == "number" then
                table.insert(keys, key)
            end
        end
        table.sort(keys, function(a, b)
            if type(a) == type(b) then
                return a < b
            end
            return tostring(a) < tostring(b)
        end)

        streamWriteUInt16(streamId, #keys)
        for _, key in ipairs(keys) do
            local isNumericKey = type(key) == "number"
            streamWriteBool(streamId, isNumericKey)
            if isNumericKey then
                streamWriteInt32(streamId, key)
            else
                streamWriteString(streamId, key)
            end
            writeSnapshotValue(streamId, value[key])
        end
    elseif valueType == "number" and value == value and value ~= math.huge and value ~= -math.huge then
        streamWriteUIntN(streamId, RMS_DebugSnapshot.ENTRY_TYPE_NUMBER, 2)
        streamWriteFloat32(streamId, value)
    elseif valueType == "boolean" then
        streamWriteUIntN(streamId, RMS_DebugSnapshot.ENTRY_TYPE_BOOLEAN, 2)
        streamWriteBool(streamId, value)
    elseif valueType == "string" then
        streamWriteUIntN(streamId, RMS_DebugSnapshot.ENTRY_TYPE_STRING, 2)
        streamWriteString(streamId, value)
    else
        streamWriteUIntN(streamId, RMS_DebugSnapshot.ENTRY_TYPE_TABLE, 2)
        streamWriteUInt16(streamId, 0)
    end
end

---Reads one snapshot value, dispatching on the type written before it
-- @param integer streamId streamId
-- @return any value value read
local function readSnapshotValue(streamId)
    local valueType = streamReadUIntN(streamId, 2)

    if valueType == RMS_DebugSnapshot.ENTRY_TYPE_NUMBER then
        return streamReadFloat32(streamId)
    elseif valueType == RMS_DebugSnapshot.ENTRY_TYPE_BOOLEAN then
        return streamReadBool(streamId)
    elseif valueType == RMS_DebugSnapshot.ENTRY_TYPE_STRING then
        return streamReadString(streamId)
    end

    local value = {}
    local keyCount = streamReadUInt16(streamId)
    for _ = 1, keyCount do
        local isNumericKey = streamReadBool(streamId)
        local key = isNumericKey and streamReadInt32(streamId) or streamReadString(streamId)
        value[key] = readSnapshotValue(streamId)
    end
    return value
end

---Builds the snapshot of a vehicle on the server
-- @param table? vehicle vehicle
-- @return table snapshot debug snapshot
function RMS_DebugSnapshot.build(vehicle)
    local spec = vehicle ~= nil and vehicle.spec_RealisticMechanicalSystems or nil
    if spec == nil then
        return nil
    end

    local motor = vehicle.getMotor ~= nil and vehicle:getMotor() or nil
    local motorizedSpec = vehicle.spec_motorized or {}
    local lastControlParameters = motorizedSpec.lastControlParameters or {}
    local chassisBrakeState = spec.chassisBrakeState or {}
    local aiWorkerPid = spec.aiWorkerPid or {}
    local preheatState = tonumber(spec.preheatState) or RMS_Preheat.STATE.IDLE
    local preheatIsDiesel = RMS_Preheat.isDieselVehicle(vehicle)
    local preheatEngineTemperatureC = RMS_Preheat.getEngineTemperatureC(vehicle)
    local glowHardStartEffect = spec.activeEffects ~= nil and spec.activeEffects.GLOW_PLUG_HARD_START_MODIFIER or nil
    local glowHardStartStatus = glowHardStartEffect ~= nil
        and glowHardStartEffect.extraData ~= nil
        and glowHardStartEffect.extraData.status
        or "NONE"
    local glowHardStartBlocked = glowHardStartEffect ~= nil
        and glowHardStartEffect.extraData ~= nil
        and glowHardStartEffect.extraData.blockStart == true
        and preheatIsDiesel
        and preheatEngineTemperatureC < RMS_Config.PREHEAT.START_ASSIST_TEMPERATURE_C

    return {
        debugData = copyDebugData(spec.debugData),
        factorStats = copyFactorStats(spec.factorStats),
        state = {
            year = tonumber(spec.year) or 0,
            reliability = tonumber(spec.reliability) or 0,
            maintainability = tonumber(spec.maintainability) or 0,
            realOperatingTime = tonumber(spec.realOperatingTime) or 0,
            conditionLevel = tonumber(spec.conditionLevel) or 0,
            serviceLevel = tonumber(spec.serviceLevel) or 0,
            currentState = tostring(spec.currentState or ""),
            plannedState = tostring(spec.plannedState or ""),
            workshopType = tostring(spec.workshopType or ""),
            serviceOptionOne = tostring(spec.serviceOptionOne or ""),
            serviceOptionTwo = tostring(spec.serviceOptionTwo or ""),
            serviceOptionThree = spec.serviceOptionThree == true,
            maintenanceTimer = tonumber(spec.maintenanceTimer) or 0,
            pendingProgressElapsedTime = tonumber(spec.pendingProgressElapsedTime) or 0,
            pendingProgressStepIndex = tonumber(spec.pendingProgressStepIndex) or 0,
            pendingProgressTotalTime = tonumber(spec.pendingProgressTotalTime) or 0,
            systems = copyPlainValue(spec.systems or {}),
            activeBreakdowns = copyPlainValue(spec.activeBreakdowns or {}),
            activeEffects = copyPlainValue(spec.activeEffects or {}),
            isUnderRoof = spec.isUnderRoof == true,
            weatherFactor = tonumber(RMS_Main ~= nil and RMS_Main.currentWeatherFactor) or 1,
            operatingTimeMs = vehicle.getOperatingTime ~= nil and (tonumber(vehicle:getOperatingTime()) or 0) or 0,
            dirtAmount = vehicle.getDirtAmount ~= nil and (tonumber(vehicle:getDirtAmount()) or 0) or 0,
            wearTotalAmount = vehicle.getWearTotalAmount ~= nil and (tonumber(vehicle:getWearTotalAmount()) or 0) or 0,
            currentSpeedKmh = vehicle.getLastSpeed ~= nil and (tonumber(vehicle:getLastSpeed()) or 0) or 0,
            actualAccelerationMps2 = (tonumber(vehicle.lastSpeedAcceleration) or 0) * 1000000,
            isAiActive = vehicle.getIsAIActive ~= nil and vehicle:getIsAIActive() == true,
            cruiseControlState = vehicle.getCruiseControlState ~= nil and (tonumber(vehicle:getCruiseControlState()) or 0) or 0,
            cruiseControlAccelerator = vehicle.getCruiseControlAxis ~= nil and (tonumber(vehicle:getCruiseControlAxis()) or 0) or 0,
            inputAcceleratorPedal = vehicle.getAccelerationAxis ~= nil and (tonumber(vehicle:getAccelerationAxis()) or 0) or 0,
            requestedAcceleratorPedal = motor ~= nil and (tonumber(motor.lastAcceleratorPedal) or 0) or 0,
            appliedAcceleratorPedal = tonumber(lastControlParameters.acceleratorPedal) or 0,
            motorAvailableTorque = motor ~= nil and motor.getMotorAvailableTorque ~= nil and (tonumber(motor:getMotorAvailableTorque()) or 0) or 0,
            motorExternalTorque = motor ~= nil and motor.getMotorExternalTorque ~= nil and (tonumber(motor:getMotorExternalTorque()) or 0) or 0,
            motorRotSpeed = motor ~= nil and motor.getMotorRotSpeed ~= nil and (tonumber(motor:getMotorRotSpeed()) or 0) or 0,
            peakMotorPower = motor ~= nil and (tonumber(motor.peakMotorPower) or 0) or 0,
            lastModulatedMotorRpm = motor ~= nil and motor.getLastModulatedMotorRpm ~= nil and (tonumber(motor:getLastModulatedMotorRpm()) or 0) or 0,
            maxMotorRpm = motor ~= nil and (tonumber(motor.maxRpm) or 0) or 0,
            motorLoad = vehicle.getMotorLoadPercentage ~= nil and (tonumber(vehicle:getMotorLoadPercentage()) or 0) or 0,
            currentGear = motor ~= nil and (tonumber(motor.gear) or 0) or 0,
            targetGear = motor ~= nil and (tonumber(motor.targetGear) or 0) or 0,
            currentDirection = motor ~= nil and (tonumber(motor.currentDirection) or 1) or 1,
            activeGearGroupIndex = motor ~= nil and (tonumber(motor.activeGearGroupIndex) or 0) or 0,
            gearRatio = motor ~= nil and motor.getGearRatio ~= nil and (tonumber(motor:getGearRatio()) or 0) or 0,
            avgDynamicMotorLoad = tonumber(spec.avgDynamicMotorLoad) or 0,
            avgSpeed = tonumber(spec.avgSpeed) or 0,
            avgAbsDiffAcc = tonumber(spec.avgAbsDiffAcc) or 0,
            avgTireGroundFrictionCoeff = tonumber(spec.avgTireGroundFrictionCoeff) or 0,
            wheelSlipIntensity = tonumber(spec.wheelSlipIntensity) or 0,
            activeDraftMaxForce = tonumber(spec.activeDraftMaxForce) or 0,
            activeDraftEffectiveForceCap = tonumber(spec.activeDraftEffectiveForceCap) or 0,
            chassisBrakePedal = tonumber(chassisBrakeState.pedal) or 0,
            dynamicMotorLoad = tonumber(spec.dynamicMotorLoad) or 0,
            isCranking = spec.isCranking == true,
            engineTemperature = tonumber(spec.engineTemperature) or -99,
            rawEngineTemperature = tonumber(spec.rawEngineTemperature) or -99,
            thermostatState = tonumber(spec.thermostatState) or 0,
            transmissionTemperature = tonumber(spec.transmissionTemperature) or -99,
            rawTransmissionTemperature = tonumber(spec.rawTransmissionTemperature) or -99,
            transmissionThermostatState = tonumber(spec.transmissionThermostatState) or 0,
            batterySoc = tonumber(spec.batterySoc) or 0,
            batteryChargeAh = tonumber(spec.batteryChargeAh) or 0,
            batteryTerminalVoltageV = tonumber(spec.batteryTerminalVoltageV) or 0,
            systemVoltageV = tonumber(spec.systemVoltageV) or 0,
            batteryTempC = tonumber(spec.batteryTempC) or 0,
            radiatorClogging = tonumber(spec.radiatorClogging) or 0,
            airFilterClogging = tonumber(spec.airFilterClogging) or 0,
            airFilterResidue = tonumber(spec.airFilterResidue) or 0,
            lubricationLevel = tonumber(spec.lubricationLevel) or 0,
            engineOilLevel = tonumber(spec.engineOilLevel) or 0,
            coolantLevel = tonumber(spec.coolantLevel) or 0,
            coolantLeakRate = tonumber(spec.coolantLeakRate) or 0,
            transmissionOilLevel = tonumber(spec.transmissionOilLevel) or 0,
            transmissionOilLeakRate = tonumber(spec.transmissionOilLeakRate) or 0,
            hydraulicFluidLevel = tonumber(spec.hydraulicFluidLevel) or 0,
            hydraulicFluidLeakRate = tonumber(spec.hydraulicFluidLeakRate) or 0,
            preheatState = preheatState,
            preheatStateName = RMS_Preheat.getStateName(preheatState),
            preheatIsDiesel = preheatIsDiesel,
            preheatEngineTemperatureC = preheatEngineTemperatureC,
            preheatLampTestActive = spec.preheatLampTestActive == true,
            preheatLampTestRemainingMs = tonumber(spec.preheatLampTestRemainingMs) or 0,
            preheatRemainingMs = tonumber(spec.preheatRemainingMs) or 0,
            preheatRequiredMs = tonumber(spec.preheatRequiredMs) or 0,
            preheatWasRequired = spec.preheatWasRequired == true,
            preheatAutomaticCrank = spec.preheatAutomaticCrank == true,
            preheatAutomaticCrankElapsedMs = tonumber(spec.preheatAutomaticCrankElapsedMs) or 0,
            preheatGlowPlugFailureSeverity = RMS_Preheat.getGlowPlugFailureSeverity(vehicle),
            preheatColdStartFaultSeverity = tonumber(spec.preheatColdStartFaultSeverity) or 0,
            preheatGlowHardStartStatus = tostring(glowHardStartStatus),
            preheatGlowHardStartBlocked = glowHardStartBlocked,
            pendingServicePrice = tonumber(spec.pendingServicePrice),
            pendingSelectedBreakdowns = copyPlainValue(spec.pendingSelectedBreakdowns or {}),
            pendingInspectionQueue = copyPlainValue(spec.pendingInspectionQueue or {}),
            pendingRepairQueue = copyPlainValue(spec.pendingRepairQueue or {}),
            pendingMaintenanceServiceStart = tonumber(spec.pendingMaintenanceServiceStart),
            pendingMaintenanceServiceTarget = tonumber(spec.pendingMaintenanceServiceTarget),
            pendingPreventiveSystemStressStart = copyPlainValue(spec.pendingPreventiveSystemStressStart or {}),
            pendingPreventiveSystemStressTarget = copyPlainValue(spec.pendingPreventiveSystemStressTarget or {}),
            pendingOverhaulSystemStart = copyPlainValue(spec.pendingOverhaulSystemStart or {}),
            pendingOverhaulSystemTarget = copyPlainValue(spec.pendingOverhaulSystemTarget or {}),
            pendingOverhaulSystemStressStart = copyPlainValue(spec.pendingOverhaulSystemStressStart or {}),
            pendingOverhaulSystemStressTarget = copyPlainValue(spec.pendingOverhaulSystemStressTarget or {}),
            pendingRepairSystemStressStart = copyPlainValue(spec.pendingRepairSystemStressStart or {}),
            pendingRepairSystemStressTarget = copyPlainValue(spec.pendingRepairSystemStressTarget or {}),
            aiWorkerApplyTimer = tonumber(aiWorkerPid.applyTimer) or 0,
            implements = copyPlainValue(spec.implements or {}),
            isImplementLowered = spec.isImplementLowered == true,
            isImplementOperating = spec.isImplementOperating == true,
            isImplementLifted = spec.isImplementLifted == true,
            hydraulicActiveTargetCount = tonumber(spec.hydraulicActiveTargetCount) or 0,
            liftedMass = tonumber(spec.liftedMass) or 0,
            hasDebris = spec.hasDebris == true,
            cvtAddon = vehicle.spec_CVTaddon ~= nil and {
                damage = tonumber(vehicle.spec_CVTaddon.CVTdamage) or 0,
                warnDamage = vehicle.spec_CVTaddon.forDBL_warndamage == 1,
                critDamage = vehicle.spec_CVTaddon.forDBL_critdamage == 1,
                warnHeat = vehicle.spec_CVTaddon.forDBL_warnheat == 1,
                critHeat = vehicle.spec_CVTaddon.forDBL_critheat == 1,
                highPressure = vehicle.spec_CVTaddon.forDBL_highpressure == 1
            } or {}
        }
    }
end

---Writes a snapshot to the stream
-- @param integer streamId streamId
-- @param table? snapshot debug snapshot
function RMS_DebugSnapshot.write(streamId, snapshot)
    writeSnapshotValue(streamId, snapshot or {})
end

---Reads a snapshot from the stream
-- @param integer streamId streamId
-- @return table snapshot debug snapshot
function RMS_DebugSnapshot.read(streamId)
    return readSnapshotValue(streamId)
end

---Stores a received snapshot on the client vehicle with its arrival time
-- @param table? vehicle vehicle
-- @param table? snapshot debug snapshot
function RMS_DebugSnapshot.apply(vehicle, snapshot)
    local spec = vehicle ~= nil and vehicle.spec_RealisticMechanicalSystems or nil
    if spec == nil or type(snapshot) ~= "table" then
        return
    end

    spec.rmsDebugSnapshot = snapshot
    spec.rmsDebugSnapshotReceivedAt = (g_currentMission ~= nil and g_currentMission.time) or g_time or 0
end

---Returns the stored snapshot while it is younger than its maximum age
-- @param table? vehicle vehicle
-- @return table? snapshot debug snapshot
function RMS_DebugSnapshot.get(vehicle)
    local spec = vehicle ~= nil and vehicle.spec_RealisticMechanicalSystems or nil
    if spec == nil then
        return nil
    end

    local receivedAt = tonumber(spec.rmsDebugSnapshotReceivedAt)
    local now = (g_currentMission ~= nil and g_currentMission.time) or g_time or 0
    if receivedAt == nil or now - receivedAt > RMS_DebugSnapshot.MAX_SNAPSHOT_AGE_MS then
        return nil
    end

    return spec.rmsDebugSnapshot
end

---Keeps debug calculations active briefly for the vehicle an administrator is inspecting
-- @param table? vehicle vehicle
function RMS_DebugSnapshot.markVehicleRequested(vehicle)
    local spec = vehicle ~= nil and vehicle.spec_RealisticMechanicalSystems or nil
    if spec == nil then
        return
    end

    local now = (g_currentMission ~= nil and g_currentMission.time) or g_time or 0
    spec.rmsDebugDataRequestedUntil = now + RMS_DebugSnapshot.DATA_REQUEST_TTL_MS
end

---Asks the server for a fresh snapshot, at most once per request interval
-- @param table? vehicle vehicle
function RMS_DebugSnapshot.request(vehicle)
    if vehicle == nil or not RMS_Config.DEBUG then
        return
    end
    if g_currentMission == nil or not g_currentMission.isMasterUser then
        return
    end

    if vehicle.isServer then
        RMS_DebugSnapshot.markVehicleRequested(vehicle)
        return
    end
    if g_client == nil then
        return
    end
    if RMS_DebugSnapshotRequestEvent == nil then
        return
    end

    local now = g_currentMission.time or g_time or 0
    if RMS_DebugSnapshot.lastRequestedVehicle ~= vehicle then
        RMS_DebugSnapshot.lastRequestedVehicle = vehicle
        RMS_DebugSnapshot.lastRequestTime = -math.huge
    end
    if now - RMS_DebugSnapshot.lastRequestTime < RMS_DebugSnapshot.REQUEST_INTERVAL_MS then
        return
    end

    RMS_DebugSnapshot.lastRequestTime = now
    RMS_DebugSnapshotRequestEvent.send(vehicle)
end
