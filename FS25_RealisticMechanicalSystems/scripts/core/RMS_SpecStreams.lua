-- Copyright © 2026 Squallqt. All rights reserved.

---Vehicle network streams

local getSyncOperatingTime = RealisticMechanicalSystems.getSyncOperatingTime

-- [connection][packet number][vehicle] = sync groups the packet carried
local unacknowledgedGroups = setmetatable({}, { __mode = "k" })

---Notes the groups an update packet carried, to send them again when it is lost
-- @param table vehicle vehicle
-- @param Connection connection connection the packet goes to
-- @param integer groups sync groups carried, one bit each
local function rememberSentGroups(vehicle, connection, groups)
    local packets = unacknowledgedGroups[connection] or {}
    unacknowledgedGroups[connection] = packets
    local packet = packets[connection.lastSeqSent] or setmetatable({}, { __mode = "k" })
    packets[connection.lastSeqSent] = packet
    packet[vehicle] = bit32.bor(packet[vehicle] or 0, groups)
end

---Sends again the groups of an update packet the network lost
-- @param table _ mission
-- @param Connection connection connection of the packet
-- @param integer packetId packet lost
function RealisticMechanicalSystems.onConnectionPacketLost(_, connection, packetId)
    local packets = unacknowledgedGroups[connection]
    local packet = packets ~= nil and packets[packetId] or nil
    if packet == nil then
        return
    end
    packets[packetId] = nil
    for vehicle, groups in pairs(packet) do
        local spec = vehicle.spec_RealisticMechanicalSystems
        local pending = spec.rmsPendingByConnection[connection]
        if pending ~= nil then
            spec.rmsPendingByConnection[connection] = bit32.bor(pending, groups)
            vehicle:raiseDirtyFlags(spec.rmsDirtyFlag)
        end
    end
end

---Forgets the groups of an update packet the client received
-- @param table _ mission
-- @param Connection connection connection of the packet
-- @param integer packetId packet received
function RealisticMechanicalSystems.onConnectionPacketSent(_, connection, packetId)
    local packets = unacknowledgedGroups[connection]
    if packets ~= nil then
        packets[packetId] = nil
    end
end

FSBaseMission.onConnectionPacketLost = Utils.appendedFunction(FSBaseMission.onConnectionPacketLost, RealisticMechanicalSystems.onConnectionPacketLost)
FSBaseMission.onConnectionPacketSent = Utils.appendedFunction(FSBaseMission.onConnectionPacketSent, RealisticMechanicalSystems.onConnectionPacketSent)

---Writes the details of the current or pending service
-- @param table spec RMS specialization of the vehicle
-- @param integer streamId stream id
local function writeServiceContext(spec, streamId)
    streamWriteString(streamId, spec.serviceOptionOne or "")
    streamWriteString(streamId, spec.serviceOptionTwo or "")
    streamWriteString(streamId, spec.workshopType)
    streamWriteFloat32(streamId, RealisticMechanicalSystems.sanitizeNumber(spec.pendingServicePrice, 0, 0))
    streamWriteString(streamId, RMS_Utils.serializeInvoice(spec.pendingServiceInvoice))
end

---Reads the same service details on join and on update
-- @param table spec RMS specialization of the vehicle
-- @param integer streamId stream id
local function readServiceContext(spec, streamId)
    spec.serviceOptionOne = streamReadString(streamId)
    spec.serviceOptionTwo = streamReadString(streamId)
    spec.workshopType = streamReadString(streamId)
    spec.pendingServicePrice = streamReadFloat32(streamId)
    spec.pendingServiceInvoice = RMS_Utils.deserializeInvoice(streamReadString(streamId))
    if spec.serviceOptionOne == "" then spec.serviceOptionOne = nil end
    if spec.serviceOptionTwo == "" then spec.serviceOptionTwo = nil end
end

---Writes the resale price
-- @param integer streamId stream id
-- @param float value resale price
local function writeResalePrice(streamId, value)
    streamWriteString(streamId, string.format("%.17g", value))
end

---Reads the resale price and announces it when it changes
-- @param table vehicle vehicle
-- @param integer streamId stream id
local function readResalePrice(vehicle, streamId)
    local spec = vehicle.spec_RealisticMechanicalSystems
    local sellPrice = tonumber(streamReadString(streamId))
    if sellPrice ~= spec.syncedSellPrice then
        spec.syncedSellPrice = sellPrice
        g_messageCenter:publish(MessageType.RMS_VEHICLE_RESALE_CHANGED, vehicle)
    end
end

---Writes the hydraulic and traction battery temperatures, each when the machine has one
-- @param table vehicle vehicle
-- @param integer streamId stream id
local function writeOptionalThermalState(vehicle, streamId)
    local spec = vehicle.spec_RealisticMechanicalSystems
    local hasHydraulicTemperature = RMS_Thermal.getHasSeparateHydraulicCircuit(spec)
    if streamWriteBool(streamId, hasHydraulicTemperature) then
        streamWriteFloat32(streamId, spec.rawHydraulicTemperature)
    end
    if streamWriteBool(streamId, spec.isElectricVehicle) then
        streamWriteFloat32(streamId, spec.tractionBatteryTempC)
    end
end

---Reads the hydraulic and traction battery temperatures
-- @param table spec RMS specialization of the vehicle
-- @param integer streamId stream id
-- @param boolean? initializeDisplay true to set the shown temperatures too
local function readOptionalThermalState(spec, streamId, initializeDisplay)
    if streamReadBool(streamId) then
        local hydraulicTemp = streamReadFloat32(streamId)
        spec.rawHydraulicTemperature = hydraulicTemp
        if initializeDisplay or spec.hydraulicTemperature == nil then spec.hydraulicTemperature = hydraulicTemp end
    else
        spec.rawHydraulicTemperature, spec.hydraulicTemperature = nil, nil
    end
    if streamReadBool(streamId) then
        spec.tractionBatteryTempC = streamReadFloat32(streamId)
    else
        spec.tractionBatteryTempC = nil
    end
end

---Writes the radiator, filters, greasing and fluids
-- @param table self vehicle
-- @param table spec RMS specialization of the vehicle
-- @param integer streamId stream id
local function writeFieldcareState(self, spec, streamId)
    streamWriteFloat32(streamId, spec.radiatorClogging)
    streamWriteFloat32(streamId, spec.fanReversalTime)
    streamWriteFloat32(streamId, spec.airFilterClogging)
    streamWriteFloat32(streamId, spec.airFilterResidue)
    for _, filter in ipairs(RMS_Consumables.FILTERS) do
        streamWriteFloat32(streamId, spec[filter.stateKey])
    end
    streamWriteString(streamId, RMS_Greasing.serialize(self))
    streamWriteFloat32(streamId, spec.engineOilLevel)
    streamWriteFloat32(streamId, spec.coolantLevel)
    streamWriteFloat32(streamId, spec.transmissionOilLevel)
    streamWriteFloat32(streamId, spec.hydraulicFluidLevel)
    for _, circuit in ipairs(RMS_Fluids.CIRCUIT_ORDER) do
        streamWriteFloat32(streamId, spec.fluidCapacities[circuit])
        streamWriteFloat32(streamId, spec.fluidCompatibility[circuit])
    end
    streamWriteFloat32(streamId, spec.engineOilSuitedShare)
    streamWriteString(streamId, RMS_Fluids.serializeLeakDebt(spec.fluidLeakLossDebt))
    -- uncovered pickups are computed on the server only
    for _, circuit in ipairs(RMS_Fluids.PICKUP_CIRCUITS) do
        streamWriteBool(streamId, spec.pickupUncovered[circuit] == true)
    end
end

---Reads the radiator, filters, greasing and fluids
-- @param table self vehicle
-- @param table spec RMS specialization of the vehicle
-- @param integer streamId stream id
local function readFieldcareState(self, spec, streamId)
    spec.radiatorClogging = streamReadFloat32(streamId)
    spec.fanReversalTime = streamReadFloat32(streamId)
    spec.airFilterClogging = streamReadFloat32(streamId)
    spec.airFilterResidue = streamReadFloat32(streamId)
    for _, filter in ipairs(RMS_Consumables.FILTERS) do
        spec[filter.stateKey] = streamReadFloat32(streamId)
    end
    RMS_Greasing.deserialize(self, streamReadString(streamId))
    spec.engineOilLevel = streamReadFloat32(streamId)
    spec.coolantLevel = streamReadFloat32(streamId)
    spec.transmissionOilLevel = streamReadFloat32(streamId)
    spec.hydraulicFluidLevel = streamReadFloat32(streamId)
    for _, circuit in ipairs(RMS_Fluids.CIRCUIT_ORDER) do
        spec.fluidCapacities[circuit] = streamReadFloat32(streamId)
        spec.fluidCompatibility[circuit] = streamReadFloat32(streamId)
    end
    spec.engineOilSuitedShare = streamReadFloat32(streamId)
    spec.fluidLeakLossDebt = RMS_Fluids.deserializeLeakDebt(streamReadString(streamId))
    for _, circuit in ipairs(RMS_Fluids.PICKUP_CIRCUITS) do
        spec.pickupUncovered[circuit] = streamReadBool(streamId)
    end
    spec.fluidCapacityVersion = RMS_Fluids.CAPACITY_VERSION
    RMS_Fluids.updateEffects(self)
end

---Writes the service levels, warranty, remap, condition and part wear
-- @param table spec RMS specialization of the vehicle
-- @param integer streamId stream id
local function writeWearState(spec, streamId)
    streamWriteFloat32(streamId, spec.serviceLevel)
    streamWriteFloat32(streamId, spec.transmissionServiceLevel)
    streamWriteFloat32(streamId, spec.coolantServiceLevel)
    streamWriteFloat32(streamId, spec.hydraulicServiceLevel)
    streamWriteString(streamId, RMS_Utils.serializeNumericMap(spec.serviceCalendar))
    streamWriteUInt8(streamId, spec.warrantyPlan)
    streamWriteString(streamId, RMS_Utils.serializeNumericMap(spec.partWarranty))
    streamWriteString(streamId, RMS_Utils.serializeNumericMap(spec.usedPartWarranty))
    streamWriteBool(streamId, spec.warrantyVoided)
    streamWriteUInt8(streamId, spec.remapMotor)
    streamWriteInt32(streamId, spec.remapAge)
    streamWriteBool(streamId, spec.remapByDealer)
    streamWriteFloat32(streamId, spec.conditionLevel)
    streamWriteString(streamId, RMS_Utils.serializeSystemsState(spec.systems))
    streamWriteString(streamId, RMS_Utils.serializeNumericMap(spec.partWear))
end

---Reads the service levels, warranty, remap, condition and part wear
-- @param table spec RMS specialization of the vehicle
-- @param integer streamId stream id
local function readWearState(spec, streamId)
    spec.serviceLevel = streamReadFloat32(streamId)
    spec.transmissionServiceLevel = streamReadFloat32(streamId)
    spec.coolantServiceLevel = streamReadFloat32(streamId)
    spec.hydraulicServiceLevel = streamReadFloat32(streamId)
    spec.serviceCalendar = RMS_Utils.deserializeNumericMap(streamReadString(streamId))
    spec.warrantyPlan = streamReadUInt8(streamId)
    spec.partWarranty = RMS_Utils.deserializeNumericMap(streamReadString(streamId))
    spec.usedPartWarranty = RMS_Utils.deserializeNumericMap(streamReadString(streamId))
    spec.warrantyVoided = streamReadBool(streamId)
    spec.remapMotor = streamReadUInt8(streamId)
    spec.remapAge = streamReadInt32(streamId)
    spec.remapByDealer = streamReadBool(streamId)
    spec.remapGain = nil
    spec.conditionLevel = streamReadFloat32(streamId)
    local loadedSystems = RMS_Utils.deserializeSystemsState(streamReadString(streamId))
    for sysKey, sysData in pairs(loadedSystems) do
        spec.systems[sysKey].condition = sysData.condition
        spec.systems[sysKey].enabled = sysData.enabled
    end
    spec.partWear = RMS_Utils.deserializeNumericMap(streamReadString(streamId))
end

---Writes the engine and oil temperatures and the thermostats
-- @param table self vehicle
-- @param table spec RMS specialization of the vehicle
-- @param integer streamId stream id
local function writeThermalState(self, spec, streamId)
    streamWriteFloat32(streamId, RMS_Thermal.getEngineTemperature(self))
    streamWriteFloat32(streamId, spec.rawTransmissionTemperature)
    streamWriteFloat32(streamId, spec.thermostatState)
    streamWriteFloat32(streamId, spec.transmissionThermostatState)
    writeOptionalThermalState(self, streamId)
end

local TRIP_FUEL = { "tripFuelLitres", "tripEngineTime", "tripWorkFuelLitres", "tripWorkedHectares" }

---Writes the trip fuel and work counters
-- @param table spec RMS specialization of the vehicle
-- @param integer streamId stream id
local function writeTripFuel(spec, streamId)
    for _, name in ipairs(TRIP_FUEL) do
        streamWriteFloat32(streamId, RealisticMechanicalSystems.sanitizeNumber(spec[name], 0, 0))
    end
end

---Reads the trip fuel and work counters
-- @param table spec RMS specialization of the vehicle
-- @param integer streamId stream id
local function readTripFuel(spec, streamId)
    for _, name in ipairs(TRIP_FUEL) do
        spec[name] = streamReadFloat32(streamId)
    end
end

---Writes the battery, the system voltage and the start state
-- @param table spec RMS specialization of the vehicle
-- @param integer streamId stream id
local function writeElectricalState(spec, streamId)
    streamWriteFloat32(streamId, spec.batterySoc)
    streamWriteBool(streamId, spec.batteryIsolated)
    streamWriteFloat32(streamId, RealisticMechanicalSystems.sanitizeNumber(spec.systemVoltageV, 12.6, 0, 30))
    streamWriteUInt8(streamId, spec.startState)
    streamWriteBool(streamId, spec.preheatLampTestActive)
    streamWriteBool(streamId, spec.preheatWasRequired)
    streamWriteUInt8(streamId, spec.preheatColdStartFaultSeverity)
end


---Called on server side on join
-- @param integer streamId stream id
-- @param Connection connection connection
function RealisticMechanicalSystems:onWriteStream(streamId, connection)
    local spec = self.spec_RealisticMechanicalSystems
    if next(spec.rmsPendingByConnection) == nil then
        -- a first receiver resets the last state sent
        spec.rmsLastSync = nil
    end
    spec.rmsPendingByConnection[connection] = 0

    if streamWriteBool(streamId, spec.isExcludedByUser ~= nil) then
        streamWriteBool(streamId, spec.isExcludedByUser)
    end
    streamWriteBool(streamId, spec.isExcludedVehicle)
    if spec.isExcludedVehicle then return end

    -- [Group 1] State
    streamWriteString(streamId, spec.currentState)
    streamWriteFloat32(streamId, spec.maintenanceTimer)

    -- [Group 2] Service context
    writeServiceContext(spec, streamId)

    -- [Group 3] Telemetry
    streamWriteFloat32(streamId, getSyncOperatingTime(self))
    streamWriteFloat32(streamId, spec.realOperatingTime)
    streamWriteFloat32(streamId, spec._fuelUsageRaw)
    streamWriteFloat32(streamId, spec.dynamicMotorLoad)
    streamWriteBool(streamId, spec.isHarvestLoad)
    streamWriteFloat32(streamId, spec.motorDemand)

    -- [Group 4] Thermal
    writeThermalState(self, spec, streamId)

    -- [Group 5] Electrical
    writeElectricalState(spec, streamId)

    -- [Group 6] Field care
    writeFieldcareState(self, spec, streamId)
    streamWriteBool(streamId, spec.fieldInspectionSoundActive)

    -- [Group 7] Wear
    writeWearState(spec, streamId)
    streamWriteBool(streamId, spec.isHeaderSlipping)

    -- [Group 8] Breakdowns
    streamWriteString(streamId, RMS_Utils.serializeBreakdowns(spec.activeBreakdowns))
    streamWriteString(streamId, RMS_Utils.serializeNumericMap(spec.preventiveParts))

    -- [Group 9] Service progress
    streamWriteInt32(streamId, spec.pendingProgressStepIndex)
    streamWriteFloat32(streamId, RealisticMechanicalSystems.sanitizeNumber(spec.pendingProgressTotalTime, 0, 0))
    streamWriteFloat32(streamId, RealisticMechanicalSystems.sanitizeNumber(spec.pendingProgressElapsedTime, 0, 0))

    -- [Group 10] Maintenance log
    local logCount = #spec.maintenanceLog
    streamWriteUInt16(streamId, logCount)
    for i = 1, logCount do
        local entry = spec.maintenanceLog[i]
        streamWriteString(streamId, RMS_Utils.serializeMaintenanceLogEntry(entry))
    end

    -- [Group 11] Drivetrain
    RMS_Drivetrain.writeStreamState(self, streamId)

    -- [Group 12] Exhaust deposits
    streamWriteFloat32(streamId, spec.fuelState.wetStackingLevel)
    streamWriteFloat32(streamId, spec.fuelState.particulateFilterLevel)
    streamWriteFloat32(streamId, spec.fuelState.particulateFilterAsh)
    streamWriteBool(streamId, spec.fuelState.isParticulateFilterRegenerating)
    streamWriteBool(streamId, spec.isEngineDerated)

    -- [Group 13] Resale price
    writeResalePrice(streamId, RMS_Utils.getMarketValue(self))

    -- [Group 14] Trip meter: the game sends its odometer only with a cruise control
    streamWriteFloat32(streamId, (RMS_Utils.getOdometerKilometers(self) or 0) - spec.tripStartKilometers)
    writeTripFuel(spec, streamId)
end

---Called on client side on join
-- @param integer streamId stream id
-- @param Connection connection connection
function RealisticMechanicalSystems:onReadStream(streamId, connection)
    local spec = self.spec_RealisticMechanicalSystems

    spec.isExcludedByUser = nil
    if streamReadBool(streamId) then
        spec.isExcludedByUser = streamReadBool(streamId)
    end
    spec.isExcludedVehicle = streamReadBool(streamId)
    if spec.isExcludedVehicle then return end

    -- [Group 1] State
    spec.currentState = streamReadString(streamId)
    spec.maintenanceTimer = streamReadFloat32(streamId)
    spec.maintenanceTimerTime = RMS_Thermal.getWorldTimeMS()

    -- [Group 2] Service context
    readServiceContext(spec, streamId)

    -- [Group 3] Telemetry
    self:setOperatingTime(streamReadFloat32(streamId), true)
    spec.realOperatingTime = streamReadFloat32(streamId)
    local syncFuelRaw = streamReadFloat32(streamId)
    spec._fuelUsageRaw = syncFuelRaw
    spec.dynamicMotorLoad = streamReadFloat32(streamId)
    spec.isHarvestLoad = streamReadBool(streamId)
    spec.motorDemand = streamReadFloat32(streamId)
    self.spec_motorized.lastFuelUsage = syncFuelRaw

    -- [Group 4] Thermal
    local syncRawEngTemp = streamReadFloat32(streamId)
    local syncRawTransTemp = streamReadFloat32(streamId)
    RMS_Thermal.setEngineTemperature(self, syncRawEngTemp)
    spec.rawTransmissionTemperature = syncRawTransTemp
    spec.transmissionTemperature = syncRawTransTemp
    spec.thermostatState = streamReadFloat32(streamId)
    spec.transmissionThermostatState = streamReadFloat32(streamId)
    readOptionalThermalState(spec, streamId, true)

    -- [Group 5] Electrical
    spec.batterySoc = streamReadFloat32(streamId)
    spec.batteryIsolated = streamReadBool(streamId)
    spec.systemVoltageV = streamReadFloat32(streamId)
    spec.rawSystemVoltageV = spec.systemVoltageV
    spec.startState = streamReadUInt8(streamId)
    spec.preheatLampTestActive = streamReadBool(streamId)
    spec.preheatWasRequired = streamReadBool(streamId)
    spec.preheatColdStartFaultSeverity = streamReadUInt8(streamId)

    -- [Group 6] Field care
    readFieldcareState(self, spec, streamId)
    spec.fieldInspectionSoundActive = streamReadBool(streamId)
    if spec.fieldInspectionSoundActive then
        self:raiseActive()
    end

    -- [Group 7] Wear
    readWearState(spec, streamId)
    spec.isHeaderSlipping = streamReadBool(streamId)

    -- [Group 8] Breakdowns
    spec.activeBreakdowns = RMS_Utils.deserializeBreakdowns(streamReadString(streamId))
    spec.preventiveParts = RMS_Utils.deserializeNumericMap(streamReadString(streamId))

    -- [Group 9] Service progress
    spec.pendingProgressStepIndex = streamReadInt32(streamId)
    spec.pendingProgressTotalTime = streamReadFloat32(streamId)
    spec.pendingProgressElapsedTime = streamReadFloat32(streamId)

    -- [Group 10] Maintenance log
    local logCount = streamReadUInt16(streamId)
    spec.maintenanceLog = {}
    for i = 1, logCount do
        table.insert(spec.maintenanceLog, RMS_Utils.deserializeMaintenanceLogEntry(streamReadString(streamId)))
    end

    -- [Group 11] Drivetrain
    RMS_Drivetrain.readStreamState(self, streamId, true)

    -- [Group 12] Exhaust deposits
    spec.fuelState.wetStackingLevel = streamReadFloat32(streamId)
    spec.fuelState.particulateFilterLevel = streamReadFloat32(streamId)
    spec.fuelState.particulateFilterAsh = streamReadFloat32(streamId)
    spec.fuelState.isParticulateFilterRegenerating = streamReadBool(streamId)
    spec.isEngineDerated = streamReadBool(streamId)

    -- [Group 13] Resale price
    readResalePrice(self, streamId)

    -- [Group 14] Trip meter
    spec.tripStartKilometers = (RMS_Utils.getOdometerKilometers(self) or 0) - streamReadFloat32(streamId)
    readTripFuel(spec, streamId)

    self:recalculateAndApplyEffects(true)
    self:recalculateAndApplyIndicators()
    if spec.isElectricVehicle then
        RMS_ElectricDrive.applyBatteryCapacity(self)
    end

    -- Register here: parked vehicles do not update on join
    RealisticMechanicalSystems.registerVehicle(self)
end

---Called on server side on update
-- @param integer streamId stream id
-- @param Connection connection connection
-- @param integer dirtyMask dirty mask
function RealisticMechanicalSystems:onWriteUpdateStream(streamId, connection, dirtyMask)
    local spec = self.spec_RealisticMechanicalSystems

    if not connection:getIsServer() then
        local pending = spec.rmsPendingByConnection[connection] or 0
        spec.rmsPendingByConnection[connection] = 0
        if pending ~= 0 then
            rememberSentGroups(self, connection, pending)
        end

        if streamWriteBool(streamId, bit32.band(pending, RealisticMechanicalSystems.SYNC_GROUP.STATE) ~= 0) then
            streamWriteString(streamId, spec.currentState)
            streamWriteFloat32(streamId, spec.maintenanceTimer)
            VehiclePropertyState.writeStream(streamId, self.propertyState)
        end

        if streamWriteBool(streamId, bit32.band(pending, RealisticMechanicalSystems.SYNC_GROUP.SERVICE_CONTEXT) ~= 0) then
            writeServiceContext(spec, streamId)
        end

        if streamWriteBool(streamId, bit32.band(pending, RealisticMechanicalSystems.SYNC_GROUP.TELEMETRY) ~= 0) then
            streamWriteFloat32(streamId, getSyncOperatingTime(self))
            streamWriteFloat32(streamId, spec.realOperatingTime)
            streamWriteFloat32(streamId, spec._fuelUsageRaw)
            streamWriteFloat32(streamId, spec.dynamicMotorLoad)
            streamWriteBool(streamId, spec.isHarvestLoad)
            streamWriteFloat32(streamId, spec.motorDemand)
            streamWriteFloat32(streamId, RealisticMechanicalSystems.sanitizeNumber(spec.wheelSlipIntensity, 0, 0, 1))
            streamWriteFloat32(streamId, spec.fuelState.wetStackingLevel)
            streamWriteFloat32(streamId, spec.fuelState.particulateFilterLevel)
            streamWriteFloat32(streamId, spec.fuelState.particulateFilterAsh)
            streamWriteBool(streamId, spec.fuelState.isParticulateFilterRegenerating)
            streamWriteBool(streamId, spec.isEngineDerated)
            streamWriteFloat32(streamId, spec.liftedMass)
            writeTripFuel(spec, streamId)
        end

        if streamWriteBool(streamId, bit32.band(pending, RealisticMechanicalSystems.SYNC_GROUP.THERMAL) ~= 0) then
            writeThermalState(self, spec, streamId)
        end

        if streamWriteBool(streamId, bit32.band(pending, RealisticMechanicalSystems.SYNC_GROUP.ELECTRICAL) ~= 0) then
            writeElectricalState(spec, streamId)
        end

        if streamWriteBool(streamId, bit32.band(pending, RealisticMechanicalSystems.SYNC_GROUP.FIELDCARE) ~= 0) then
            writeFieldcareState(self, spec, streamId)
            streamWriteBool(streamId, spec.fieldInspectionSoundActive)
        end

        if streamWriteBool(streamId, bit32.band(pending, RealisticMechanicalSystems.SYNC_GROUP.WEAR) ~= 0) then
            writeWearState(spec, streamId)
            streamWriteBool(streamId, spec.isHeaderSlipping)
        end

        if streamWriteBool(streamId, bit32.band(pending, RealisticMechanicalSystems.SYNC_GROUP.BREAKDOWNS) ~= 0) then
            streamWriteString(streamId, RMS_Utils.serializeBreakdowns(spec.activeBreakdowns))
            streamWriteString(streamId, RMS_Utils.serializeNumericMap(spec.preventiveParts))
        end

        if streamWriteBool(streamId, bit32.band(pending, RealisticMechanicalSystems.SYNC_GROUP.SERVICE_PROGRESS) ~= 0) then
            streamWriteInt32(streamId, spec.pendingProgressStepIndex)
            streamWriteFloat32(streamId, RealisticMechanicalSystems.sanitizeNumber(spec.pendingProgressTotalTime, 0, 0))
            streamWriteFloat32(streamId, RealisticMechanicalSystems.sanitizeNumber(spec.pendingProgressElapsedTime, 0, 0))
        end

        if streamWriteBool(streamId, bit32.band(pending, RealisticMechanicalSystems.SYNC_GROUP.DRIVETRAIN) ~= 0) then
            RMS_Drivetrain.writeStreamState(self, streamId)
        end

        if streamWriteBool(streamId, bit32.band(pending, RealisticMechanicalSystems.SYNC_GROUP.RESALE) ~= 0) then
            writeResalePrice(streamId, spec.networkResaleValue or RMS_Utils.getMarketValue(self))
        end
    end
end

---Called on client side on update
-- @param integer streamId stream id
-- @param integer timestamp timestamp
-- @param Connection connection connection
function RealisticMechanicalSystems:onReadUpdateStream(streamId, timestamp, connection)
    local spec = self.spec_RealisticMechanicalSystems

    if connection:getIsServer() then
        -- [1] State
        if streamReadBool(streamId) then
            spec.currentState = streamReadString(streamId)
            spec.maintenanceTimer = streamReadFloat32(streamId)
            spec.maintenanceTimerTime = RMS_Thermal.getWorldTimeMS()
            self.propertyState = VehiclePropertyState.readStream(streamId)
        end

        -- [2] Service context
        if streamReadBool(streamId) then
            readServiceContext(spec, streamId)
            RMS_Bodywork.syncPreview(self)
        end

        -- [3] Telemetry
        if streamReadBool(streamId) then
            self:setOperatingTime(streamReadFloat32(streamId), true)
            spec.realOperatingTime = streamReadFloat32(streamId)
            spec._fuelUsageRaw = streamReadFloat32(streamId)
            spec.dynamicMotorLoad = streamReadFloat32(streamId)
            spec.isHarvestLoad = streamReadBool(streamId)
            spec.motorDemand = streamReadFloat32(streamId)
            spec.wheelSlipIntensity = streamReadFloat32(streamId)
            spec.fuelState.wetStackingLevel = streamReadFloat32(streamId)
            spec.fuelState.particulateFilterLevel = streamReadFloat32(streamId)
            spec.fuelState.particulateFilterAsh = streamReadFloat32(streamId)
            spec.fuelState.isParticulateFilterRegenerating = streamReadBool(streamId)
            spec.isEngineDerated = streamReadBool(streamId)
            spec.liftedMass = streamReadFloat32(streamId)
            readTripFuel(spec, streamId)
        end

        -- [4] Thermal
        if streamReadBool(streamId) then
            RMS_Thermal.setEngineTemperature(self, streamReadFloat32(streamId))
            spec.rawTransmissionTemperature = streamReadFloat32(streamId)
            spec.thermostatState = streamReadFloat32(streamId)
            spec.transmissionThermostatState = streamReadFloat32(streamId)
            readOptionalThermalState(spec, streamId, false)
        end

        -- [5] Electrical
        if streamReadBool(streamId) then
            spec.batterySoc = streamReadFloat32(streamId)
            local wasIsolated = spec.batteryIsolated
            spec.batteryIsolated = streamReadBool(streamId)
            if spec.batteryIsolated ~= wasIsolated then
                RMS_Electrical.playBatteryIsolatorSound(self)
            end
            spec.systemVoltageV = streamReadFloat32(streamId)
            spec.rawSystemVoltageV = spec.systemVoltageV
            spec.startState = streamReadUInt8(streamId)
            spec.preheatLampTestActive = streamReadBool(streamId)
            spec.preheatWasRequired = streamReadBool(streamId)
            spec.preheatColdStartFaultSeverity = streamReadUInt8(streamId)
        end

        -- [6] Field care
        if streamReadBool(streamId) then
            readFieldcareState(self, spec, streamId)
            local wasInspected = spec.fieldInspectionSoundActive
            spec.fieldInspectionSoundActive = streamReadBool(streamId)
            if spec.fieldInspectionSoundActive ~= wasInspected then
                self:raiseActive()
            end
        end

        -- [7] Wear
        if streamReadBool(streamId) then
            readWearState(spec, streamId)
            spec.isHeaderSlipping = streamReadBool(streamId)
        end

        -- [8] Breakdowns
        if streamReadBool(streamId) then
            spec.activeBreakdowns = RMS_Utils.deserializeBreakdowns(streamReadString(streamId))
            spec.preventiveParts = RMS_Utils.deserializeNumericMap(streamReadString(streamId))
            self:recalculateAndApplyEffects()
            self:recalculateAndApplyIndicators()
        end

        -- [9] Service progress
        if streamReadBool(streamId) then
            spec.pendingProgressStepIndex = streamReadInt32(streamId)
            spec.pendingProgressTotalTime = streamReadFloat32(streamId)
            spec.pendingProgressElapsedTime = streamReadFloat32(streamId)
        end

        -- [10] Drivetrain
        if streamReadBool(streamId) then
            RMS_Drivetrain.readStreamState(self, streamId)
        end

        -- [11] Resale price
        if streamReadBool(streamId) then
            readResalePrice(self, streamId)
        end
    end
end
