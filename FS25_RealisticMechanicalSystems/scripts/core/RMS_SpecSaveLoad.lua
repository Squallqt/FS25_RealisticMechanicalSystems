-- Copyright © 2026 Squallqt. All rights reserved.

---Vehicle savegame persistence

local getIsElectricVehicle = RMS_Utils.getIsElectricVehicle
local refreshExclusionState = RealisticMechanicalSystems.refreshExclusionState

---Keeps the ids of a list that name a breakdown the mod still has
-- @param table ids breakdown or part ids
-- @return table known ids the registry has
local function keepKnownIds(ids)
    local known = {}
    for _, id in ipairs(ids) do
        if RMS_Breakdowns.BreakdownRegistry[id] ~= nil then
            table.insert(known, id)
        end
    end
    return known
end

---Keeps the entries of a map keyed by a breakdown the mod still has
-- @param table map values by breakdown or part id
-- @return table known entries the registry has
local function keepKnownKeys(map)
    local known = {}
    for id, value in pairs(map) do
        if RMS_Breakdowns.BreakdownRegistry[id] ~= nil then
            known[id] = value
        end
    end
    return known
end

---Keeps the lines of a logged bill whose fault or part the mod still has, with the parts it still has
-- @param table? invoice lines of the bill, nil for a log entry without one
-- @return table? known lines
local function keepKnownInvoiceLines(invoice)
    if invoice == nil then
        return nil
    end
    local known = {}
    for _, line in ipairs(invoice) do
        if (line.kind ~= "repair" and line.kind ~= "preventive") or RMS_Breakdowns.BreakdownRegistry[line.key] ~= nil then
            if line.ownParts ~= nil then
                line.ownParts, line.kitParts, line.wornParts = keepKnownIds(line.ownParts), keepKnownIds(line.kitParts), keepKnownIds(line.wornParts)
            end
            table.insert(known, line)
        end
    end
    return known
end

---Keeps the systems the mod knows, leaving out one an older version had
-- @param table systems state by system key
-- @return table known state by known system key
local function keepKnownSystems(systems)
    local known = {}
    for systemKey, state in pairs(systems) do
        if RealisticMechanicalSystems.SYSTEMS[string.upper(systemKey)] ~= nil then
            known[systemKey] = state
        end
    end
    return known
end

---Returns empty wear statistics of the systems, their hours unrecorded
-- @param table systems system names by enum key
-- @return table stats wear statistics by system
local function createEmptyFactorStats(systems)
    local stats = {}
    for systemKey in pairs(systems) do
        stats[systemKey] = { total = 0, _prevStress = 0, _avgStress = 0, operatingHours = -1 }
    end
    return stats
end

---Returns the wear statistics as one map keyed system.cause, numbers only
-- @param table? factorStats wear statistics by system
-- @return table flat numbers by system.cause
local function flattenFactorStats(factorStats)
    local flat = {}
    for systemKey, stats in pairs(type(factorStats) == "table" and factorStats or {}) do
        -- the overload window is a table among the numbers
        for statKey, value in pairs(stats) do
            if type(value) == "number" then
                flat[systemKey .. "." .. statKey] = value
            end
        end
    end
    return flat
end

---Puts flattened wear statistics back under their systems, keeping the systems onLoad made and the causes the mod counts
-- @param table spec RMS specialization of the vehicle
-- @param table flattenedMap numbers by system.cause
local function applyFlattenedFactorStats(spec, flattenedMap)
    for flatKey, number in pairs(flattenedMap) do
        local systemKey, statKey = string.match(flatKey, "([^%.]+)%.(.+)")
        local stats = spec.factorStats[systemKey]
        if stats ~= nil and (stats[statKey] ~= nil or RealisticMechanicalSystems.FACTOR_STATS_KEYS[statKey]) then
            stats[statKey] = number
        end
    end
end

---Puts the saved cause wear back under each part, keeping the causes the mod counts
-- @param table flattenedMap numbers by part.cause
-- @return table map wear by cause alias, base for no cause, by part
local function unflattenPartCauseWear(flattenedMap)
    local map = {}
    for flatKey, value in pairs(flattenedMap) do
        local partId, cause = string.match(flatKey, "([^%.]+)%.(.+)")
        if cause == "base" or RealisticMechanicalSystems.FACTOR_STATS_KEYS[cause] then
            map[partId] = map[partId] or {}
            map[partId][cause] = value
        end
    end
    return map
end

---Tells whether a machine is left out of the switch between vehicles
-- @param table xmlFile file of the vehicle
-- @return boolean isAuxiliary true when left out
local function getIsAuxiliaryMachine(xmlFile)
    return not xmlFile:getValue("vehicle.enterable#isTabbable", true)
end

---Tells whether a machine is towed
-- @param table vehicle vehicle
-- @return boolean isTowed true with an input attacher joint
local function getIsTowedMachine(vehicle)
    return vehicle.getInputAttacherJoints ~= nil and #vehicle:getInputAttacherJoints() > 0
end

---Tells whether RMS tracks a store item once bought
-- @param table xmlFile file of the store item
-- @param string? customEnvironment mod of the store item
-- @return boolean isTracked true when RMS tracks it
function RealisticMechanicalSystems.getIsStoreItemTracked(xmlFile, customEnvironment)
    local vehicleType = g_vehicleTypeManager:getTypeByName(xmlFile:getValue("vehicle#type"), customEnvironment)
    if vehicleType == nil or vehicleType.specializationsByName.RealisticMechanicalSystems == nil then
        return false
    end

    return not getIsAuxiliaryMachine(xmlFile)
        and not xmlFile:hasProperty("vehicle.attachable.inputAttacherJoints.inputAttacherJoint(0)")
        and not xmlFile:hasProperty("vehicle.attachable.inputAttacherJointConfigurations.inputAttacherJointConfiguration(0).inputAttacherJoint(0)")
end

---Returns why RMS leaves a vehicle out, as the text key the fleet menu shows
-- @param table vehicle vehicle
-- @return string? reasonKey l10n key, nil when RMS tracks the vehicle
function RealisticMechanicalSystems.getExclusionReason(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    if spec == nil then
        if vehicle.spec_motorized == nil then
            return "rms_ingame_menu_reason_implement"
        end
        return "rms_ingame_menu_reason_unsupported"
    end

    if not spec.isExcludedVehicle then
        return nil
    elseif spec.isExcludedByUser then
        return "rms_ingame_menu_reason_user"
    elseif getIsTowedMachine(vehicle) then
        return "rms_ingame_menu_reason_towed"
    end
    return "rms_ingame_menu_reason_auxiliary"
end

---Tells whether a player may include or exclude a vehicle
-- @param table vehicle vehicle
-- @param boolean isExcluded true to exclude it
-- @param Connection? connection player connection, nil for the local player
-- @return boolean canSet true when the player may
function RealisticMechanicalSystems.getCanSetUserExclusion(vehicle, isExcluded, connection)
    if isExcluded and vehicle:isUnderService() then
        return false
    end

    if connection == nil then
        return g_currentMission:getIsServer() or g_currentMission.isMasterUser == true
    end
    return g_currentMission.userManager:getUserByConnection(connection):getIsMasterUser()
end

RealisticMechanicalSystems.SAMPLE_NAMES = {
    "starterRelayClick", "batteryClicking", "preheatRelay",
    "hvContactor", "alarm", "warning", "transmissionShiftFailed", "gearDisengage", "powershiftClunk", "brakes",
    "parkBrakeLeverApply", "parkBrakeLeverRelease", "parkBrakeAutoApply", "parkBrakeAutoRelease", "parkBrakeSwitchOn",
    "parkBrakeSwitchOff", "fanReversalSwitch", "parkBrakeTruckApply", "parkBrakeTruckRelease",
    "engineKnocking", "pistonSlap", "valveTrainNoise", "injectorKnock", "highPressurePump", "turboWhistle", "fanNoice", "fanBladeImbalance",
    "accessoryBelt", "headerBelt", "headerSlipClutch", "headerShaftBreak", "waterPumpBearing", "gearWhineNoise", "gearboxBearingNoise", "transmissionPump", "hydrostaticWhine",
    "hydraulicPump", "coolantSteam", "gasLeak", "parkBrakeDrag", "steeringLinkage", "steeringKnuckle", "steeringOrbitrol",
    "wheelHubBearingNoise", "wheelSeizureGrind", "trackRoller", "trackClatter", "loaderPins", "frontAxleShaft", "cabDamper", "ptoBearingNoise", "ptoSplines",
    "electricMotorBearing", "hoseBurst", "ptoShaftBreak", "inspection", "batteryIsolator"
}

---Tells whether the vehicle sits in the trucks store category
-- @param table vehicle vehicle
-- @return boolean isTruck true for a truck
local function getIsTruck(vehicle)
    local storeItem = g_storeManager:getItemByXMLFilename(vehicle.configFileName)
    return storeItem ~= nil and storeItem.categoryName == "TRUCKS"
end


-- log entry attributes in saved order
local LOG_ENTRY_XML = {
    { name = "id" },
    { name = "type" },
    { name = "price", default = 0 },
    { name = "date", write = function(entry) return RMS_Utils.serializeDate(entry.date) end,
        read = function(value) return RMS_Utils.deserializeDate(value) end },
    { name = "location", default = "UNKNOWN" },
    { name = "optionOne", default = "NONE" },
    { name = "optionTwo", default = "NONE" },
    { name = "isVisible", default = true,
        write = function(entry) return tostring(RMS_Utils.normalizeBoolValue(entry.isVisible, true)) end,
        read = function(value) return RMS_Utils.normalizeBoolValue(value, true) end },
    { name = "isCompleted", default = true,
        write = function(entry) return RMS_Utils.normalizeBoolValue(entry.isCompleted, true) end,
        read = function(value) return RMS_Utils.normalizeBoolValue(value, true) end },
    { name = "invoice",
        write = function(entry) return entry.invoice ~= nil and RMS_Utils.serializeInvoice(entry.invoice) or nil end,
        read = function(value) return keepKnownInvoiceLines(RMS_Utils.deserializeInvoice(value)) end }
}

-- attributes of the machine as a log entry found it, in saved order
local LOG_CONDITION_XML = {
    { name = "year", default = 0 },
    { name = "operatingHours", default = 0 },
    { name = "odometerKilometers" },
    { name = "age", default = 0 },
    { name = "condition", default = 1 },
    { name = "service", default = 1 },
    { name = "reliability", default = 1 },
    { name = "systems", default = "",
        write = function(data) return RMS_Utils.serializeSystemsState(RMS_Utils.createSystemsSnapshot(data.systems)) end,
        read = function(value) return keepKnownSystems(RMS_Utils.createSystemsSnapshot(RMS_Utils.deserializeSystemsState(value))) end },
    { name = "partWear", default = "",
        write = function(data) return RMS_Utils.serializeNumericMap(data.partWear) end,
        read = function(value) return keepKnownKeys(RMS_Utils.deserializeNumericMap(value)) end },
    { name = "batterySoc", default = 1, read = function(value) return math.clamp(value, 0, 1) end },
    { name = "wearExcess" },
    { name = "wearCauses", default = "",
        write = function(data) return data.wearExcess ~= nil and RMS_Utils.serializeWearCauses(data.wearCauses) or nil end,
        read = function(value) return RMS_Utils.deserializeWearCauses(value) end },
    { name = "activeBreakdowns", default = "",
        write = function(data) return data.activeBreakdowns and RMS_Utils.serializeBreakdowns(data.activeBreakdowns) or nil end,
        read = function(value) return RMS_Utils.deserializeBreakdowns(value) or {} end },
    { name = "selectedBreakdowns", default = "",
        write = function(data)
            local selected = data.selectedBreakdowns
            return selected and #selected > 0 and table.concat(selected, ",") or nil
        end,
        read = function(value) return keepKnownIds(RMS_Utils.parseCsvList(value)) end },
    { name = "activeEffects", default = "",
        write = function(data) return data.activeEffects and RMS_Utils.serializeEffectSnapshot(data.activeEffects) or nil end,
        read = function(value) return RMS_Utils.deserializeEffectSnapshot(value) end },
    { name = "activeIndicators", default = "",
        write = function(data)
            if data.activeIndicators == nil then
                return nil
            end
            local ids = {}
            for id in pairs(data.activeIndicators) do
                table.insert(ids, tostring(id))
            end
            return table.concat(ids, ",")
        end,
        read = function(value)
            local indicators = {}
            for _, id in ipairs(RMS_Utils.parseCsvList(value)) do
                indicators[id] = true
            end
            return indicators
        end }
}

---Writes the attributes of a log entry or of its condition data
-- @param table xmlFile savegame file
-- @param string path key of the entry
-- @param table holder log entry or its condition data
-- @param table fields attributes to write
local function writeLogFields(xmlFile, path, holder, fields)
    for _, field in ipairs(fields) do
        local value
        if field.write ~= nil then
            value = field.write(holder)
        else
            value = holder[field.name]
            if value == nil then
                value = field.default
            end
        end
        if value ~= nil then
            xmlFile:setValue(path .. "#" .. field.name, value)
        end
    end
end

---Reads the attributes of a log entry or of its condition data
-- @param table xmlFile savegame file
-- @param string path key of the entry
-- @param table holder log entry or its condition data
-- @param table fields attributes to read
local function readLogFields(xmlFile, path, holder, fields)
    for _, field in ipairs(fields) do
        local value = xmlFile:getValue(path .. "#" .. field.name, field.default)
        if field.read ~= nil then
            value = field.read(value)
        end
        holder[field.name] = value
    end
end

---Called on saving
-- @param table xmlFile savegame file
-- @param string key key of the specialization
-- @param table usedModNames mods used
function RealisticMechanicalSystems:saveToXMLFile(xmlFile, key, usedModNames)
    local spec = self.spec_RealisticMechanicalSystems
    if not spec.isNewToRMS then
        -- Catch up only within the current mission clock
        if self.isServer and not spec.isExcludedVehicle and not self:getIsMotorStarted() then
            self:updateThermalSystems(1, true, true)
        end
        if spec.isExcludedByUser ~= nil then
            xmlFile:setValue(key .. "#userExclusion", spec.isExcludedByUser)
        end
        local gameTime = self:getOperatingTime()
        if spec.realOperatingTime <= 0 and gameTime > 0 then
            spec.realOperatingTime = gameTime
        end
        xmlFile:setValue(key .. "#service", spec.serviceLevel)
        xmlFile:setValue(key .. "#transmissionService", spec.transmissionServiceLevel)
        xmlFile:setValue(key .. "#coolantService", spec.coolantServiceLevel)
        xmlFile:setValue(key .. "#hydraulicService", spec.hydraulicServiceLevel)
        xmlFile:setValue(key .. "#serviceCalendar", RMS_Utils.serializeNumericMap(spec.serviceCalendar))
        xmlFile:setValue(key .. "#warrantyPlan", spec.warrantyPlan)
        xmlFile:setValue(key .. "#partWarranty", RMS_Utils.serializeNumericMap(spec.partWarranty))
        xmlFile:setValue(key .. "#usedPartWarranty", RMS_Utils.serializeNumericMap(spec.usedPartWarranty))
        xmlFile:setValue(key .. "#warrantyVoided", spec.warrantyVoided)
        xmlFile:setValue(key .. "#remapMotor", spec.remapMotor)
        xmlFile:setValue(key .. "#remapAge", spec.remapAge)
        xmlFile:setValue(key .. "#remapByDealer", spec.remapByDealer)
        xmlFile:setValue(key .. "#condition", spec.conditionLevel)
        xmlFile:setValue(key .. "#realOperatingTime", spec.realOperatingTime)
        xmlFile:setValue(key .. "#breakdowns", RMS_Utils.serializeBreakdowns(spec.activeBreakdowns))
        xmlFile:setValue(key .. "#state", spec.currentState)
        xmlFile:setValue(key .. "#maintenanceTimer", spec.maintenanceTimer)
        xmlFile:setValue(key .. "#engineTemperature", RMS_Thermal.getEngineTemperature(self))
        xmlFile:setValue(key .. "#transmissionTemperature", spec.rawTransmissionTemperature)
        if RMS_Thermal.getHasSeparateHydraulicCircuit(spec) then
            xmlFile:setValue(key .. "#hydraulicTemperature", spec.rawHydraulicTemperature)
        end
        xmlFile:setValue(key .. "#batterySoc", spec.batterySoc)
        xmlFile:setValue(key .. "#batteryIsolated", spec.batteryIsolated)
        if spec.isElectricVehicle then
            xmlFile:setValue(key .. "#tractionBatteryTempC", spec.tractionBatteryTempC)
        end
        xmlFile:setValue(key .. "#radiatorClogging", spec.radiatorClogging)
        xmlFile:setValue(key .. "#airFilterClogging", spec.airFilterClogging)
        xmlFile:setValue(key .. "#airFilterResidue", spec.airFilterResidue)
        for _, filter in ipairs(RMS_Consumables.FILTERS) do
            xmlFile:setValue(key .. "#" .. filter.stateKey, spec[filter.stateKey])
        end
        xmlFile:setValue(key .. "#engineOilLevel", spec.engineOilLevel)
        xmlFile:setValue(key .. "#coolantLevel", spec.coolantLevel)
        xmlFile:setValue(key .. "#transmissionOilLevel", spec.transmissionOilLevel)
        xmlFile:setValue(key .. "#hydraulicFluidLevel", spec.hydraulicFluidLevel)
        xmlFile:setValue(key .. "#fluidCapacityVersion", spec.fluidCapacityVersion)
        xmlFile:setValue(key .. "#engineOilCapacity", spec.fluidCapacities.engineOil)
        xmlFile:setValue(key .. "#coolantCapacity", spec.fluidCapacities.coolant)
        xmlFile:setValue(key .. "#transmissionOilCapacity", spec.fluidCapacities.transmissionOil)
        xmlFile:setValue(key .. "#hydraulicFluidCapacity", spec.fluidCapacities.hydraulicFluid)
        xmlFile:setValue(key .. "#engineOilCompatibility", spec.fluidCompatibility.engineOil)
        xmlFile:setValue(key .. "#coolantCompatibility", spec.fluidCompatibility.coolant)
        xmlFile:setValue(key .. "#transmissionOilCompatibility", spec.fluidCompatibility.transmissionOil)
        xmlFile:setValue(key .. "#hydraulicFluidCompatibility", spec.fluidCompatibility.hydraulicFluid)
        xmlFile:setValue(key .. "#engineOilSuitedShare", spec.engineOilSuitedShare)
        xmlFile:setValue(key .. "#fluidLeakLossDebt", RMS_Fluids.serializeLeakDebt(spec.fluidLeakLossDebt))
        xmlFile:setValue(key .. "#wetStackingLevel", spec.fuelState.wetStackingLevel)
        xmlFile:setValue(key .. "#particulateFilterLevel", spec.fuelState.particulateFilterLevel)
        xmlFile:setValue(key .. "#particulateFilterAsh", spec.fuelState.particulateFilterAsh)
        xmlFile:setValue(key .. "#particulateFilterOilAsh", spec.fuelState.particulateFilterOilAsh)
        xmlFile:setValue(key .. "#scrInducementHours", spec.scrInducementHours)
        xmlFile:setValue(key .. "#particulateFilterOverloaded", spec.fuelState.isParticulateFilterOverloaded)
        xmlFile:setValue(key .. "#greasing", RMS_Greasing.serialize(self))
        xmlFile:setValue(key .. "#thermostatState", spec.thermostatState)
        xmlFile:setValue(key .. "#transmissionThermostatState", spec.transmissionThermostatState)
        xmlFile:setValue(key .. "#serviceOptionOne", spec.serviceOptionOne or "")
        xmlFile:setValue(key .. "#serviceOptionTwo", spec.serviceOptionTwo or "")
        xmlFile:setValue(key .. "#workshopType", spec.workshopType)
        xmlFile:setValue(key .. "#pendingSelectedBreakdowns", table.concat(spec.pendingSelectedBreakdowns, ","))
        xmlFile:setValue(key .. "#pendingServicePrice", RMS_Utils.encodeOptionalFloat(spec.pendingServicePrice))
        xmlFile:setValue(key .. "#pendingServiceInvoice", RMS_Utils.serializeInvoice(spec.pendingServiceInvoice))
        xmlFile:setValue(key .. "#pendingInspectionQueue", table.concat(spec.pendingInspectionQueue, ","))
        xmlFile:setValue(key .. "#pendingRepairQueue", table.concat(spec.pendingRepairQueue, ","))
        xmlFile:setValue(key .. "#pendingPreventiveParts", RMS_Utils.serializeNumericMap(spec.pendingPreventiveParts))
        xmlFile:setValue(key .. "#pendingFluidRequirements", RMS_Fluids.serializeServiceRequirements(spec.pendingFluidRequirements))
        xmlFile:setValue(key .. "#pendingProgressStepIndex", spec.pendingProgressStepIndex)
        xmlFile:setValue(key .. "#pendingProgressTotalTime", spec.pendingProgressTotalTime)
        xmlFile:setValue(key .. "#pendingProgressElapsedTime", spec.pendingProgressElapsedTime)
        xmlFile:setValue(key .. "#pendingServiceClockStart", RMS_Utils.serializeNumericMap(spec.pendingServiceClockStart))
        xmlFile:setValue(key .. "#pendingServiceClockTarget", RMS_Utils.serializeNumericMap(spec.pendingServiceClockTarget))
        xmlFile:setValue(key .. "#systemsState", RMS_Utils.serializeSystemsState(spec.systems))
        xmlFile:setValue(key .. "#partWear", RMS_Utils.serializeNumericMap(spec.partWear))
        xmlFile:setValue(key .. "#partCauseWear", RMS_Utils.serializeNumericMap(flattenFactorStats(spec.partCauseWear)))
        xmlFile:setValue(key .. "#partAbuse", RMS_Utils.serializeNumericMap(spec.partAbuse))
        xmlFile:setValue(key .. "#pickupAirTime", RMS_Utils.serializeNumericMap(spec.pickupAirTime))
        xmlFile:setValue(key .. "#factorStats", RMS_Utils.serializeNumericMap(flattenFactorStats(spec.factorStats)))
        xmlFile:setValue(key .. "#ptoEngagementCount", spec.ptoEngagementCount)
        if spec.headerDrive ~= nil then
            xmlFile:setValue(key .. "#headerStartCount", spec.headerDrive.starts)
        end
        xmlFile:setValue(key .. "#pendingOverhaulPartStart", RMS_Utils.serializeNumericMap(spec.pendingOverhaulPartStart))
        xmlFile:setValue(key .. "#pendingOverhaulPartTarget", RMS_Utils.serializeNumericMap(spec.pendingOverhaulPartTarget))

        RMS_Drivetrain.saveToXMLFile(self, xmlFile, key)
        xmlFile:setValue(key .. "#tripStartKilometers", spec.tripStartKilometers)
        for _, name in ipairs({ "tripFuelLitres", "tripEngineTime", "tripWorkFuelLitres", "tripWorkedHectares" }) do
            xmlFile:setValue(key .. "#" .. name, spec[name])
        end

        for index, entry in ipairs(spec.maintenanceLog) do
            local entryKey = string.format("%s.maintenanceLog.entry(%d)", key, index - 1)
            writeLogFields(xmlFile, entryKey, entry, LOG_ENTRY_XML)
            writeLogFields(xmlFile, entryKey .. ".conditionData", entry.conditionData, LOG_CONDITION_XML)
        end
    end
end

local SYSTEM_KEYS = { "engine", "transmission", "hydraulics", "cooling", "electrical", "chassis", "fuel", "pto", "harvest" }

---Called on loading
-- @param table? savegame savegame
function RealisticMechanicalSystems:onLoad(savegame)
    self.spec_RealisticMechanicalSystems.isExcludedVehicle = false
    self.spec_RealisticMechanicalSystems.isExcludedByRule = false
    self.spec_RealisticMechanicalSystems.isExcludedByUser = nil
    self.spec_RealisticMechanicalSystems.isElectricVehicle = false
    self.spec_RealisticMechanicalSystems.isTruck = getIsTruck(self)
    self.spec_RealisticMechanicalSystems.isVehicleNeedLubricate = false
    self.spec_RealisticMechanicalSystems.isVehicleNeedBlowOut = false

    self.spec_RealisticMechanicalSystems.baseServiceLevel = 1.0
    self.spec_RealisticMechanicalSystems.baseConditionLevel = 1.0
    self.spec_RealisticMechanicalSystems.serviceLevel = self.spec_RealisticMechanicalSystems.baseServiceLevel
    self.spec_RealisticMechanicalSystems.transmissionServiceLevel = self.spec_RealisticMechanicalSystems.baseServiceLevel
    self.spec_RealisticMechanicalSystems.coolantServiceLevel = self.spec_RealisticMechanicalSystems.baseServiceLevel
    self.spec_RealisticMechanicalSystems.hydraulicServiceLevel = self.spec_RealisticMechanicalSystems.baseServiceLevel
    self.spec_RealisticMechanicalSystems.serviceCalendar = {}
    self.spec_RealisticMechanicalSystems.warrantyPlan = 1
    self.spec_RealisticMechanicalSystems.partWarranty = {}
    self.spec_RealisticMechanicalSystems.usedPartWarranty = {}
    self.spec_RealisticMechanicalSystems.preventiveParts = {}
    self.spec_RealisticMechanicalSystems.partAbuse = {}
    self.spec_RealisticMechanicalSystems.pickupAirTime = {}
    self.spec_RealisticMechanicalSystems.pickupUncovered = {}
    self.spec_RealisticMechanicalSystems.aerationWhining = {}
    self.spec_RealisticMechanicalSystems.warrantyVoided = false
    self.spec_RealisticMechanicalSystems.remapMotor = 0
    self.spec_RealisticMechanicalSystems.remapAge = 0
    self.spec_RealisticMechanicalSystems.remapByDealer = false
    self.spec_RealisticMechanicalSystems.conditionLevel = self.spec_RealisticMechanicalSystems.baseConditionLevel

    self.spec_RealisticMechanicalSystems.realOperatingTime = self:getOperatingTime()

    -- every system new, the harvest one off until a harvester enables it
    local systems = {}
    for _, systemKey in ipairs(SYSTEM_KEYS) do
        systems[systemKey] = { name = RealisticMechanicalSystems.SYSTEMS[string.upper(systemKey)], condition = 1.0,
            enabled = systemKey ~= "harvest" }
    end
    self.spec_RealisticMechanicalSystems.systems = systems
    self.spec_RealisticMechanicalSystems.factorStats = createEmptyFactorStats(self.spec_RealisticMechanicalSystems.systems)

    self.spec_RealisticMechanicalSystems.airFilterClogging = 0.0
    self.spec_RealisticMechanicalSystems.airFilterResidue = 0.0
    for _, filter in ipairs(RMS_Consumables.FILTERS) do
        self.spec_RealisticMechanicalSystems[filter.stateKey] = 0.0
    end

    self.spec_RealisticMechanicalSystems.engineOilLevel = 1.0
    self.spec_RealisticMechanicalSystems.coolantLevel = 1.0
    self.spec_RealisticMechanicalSystems.transmissionOilLevel = 1.0
    self.spec_RealisticMechanicalSystems.hydraulicFluidLevel = 1.0
    self.spec_RealisticMechanicalSystems.fluidCapacities = {}
    self.spec_RealisticMechanicalSystems.fluidCompatibility = {
        engineOil = 1.0,
        coolant = 1.0,
        transmissionOil = 1.0,
        hydraulicFluid = 1.0
    }
    self.spec_RealisticMechanicalSystems.engineOilSuitedShare = 1
    self.spec_RealisticMechanicalSystems.fluidLeakLossDebt = {}
    self.spec_RealisticMechanicalSystems.fluidCapacityVersion = nil
    self.spec_RealisticMechanicalSystems.pendingFluidRequirements = {}
    self.spec_RealisticMechanicalSystems.coolantLeakRate = 0
    self.spec_RealisticMechanicalSystems.transmissionOilLeakRate = 0
    self.spec_RealisticMechanicalSystems.hydraulicFluidLeakRate = 0

    self.spec_RealisticMechanicalSystems.extraEngineHeat = 0
    self.spec_RealisticMechanicalSystems.extraTransmissionHeat = 0
    self.spec_RealisticMechanicalSystems.extraHydraulicHeat = 0
    self.spec_RealisticMechanicalSystems.fluidEngineHeat = 0
    self.spec_RealisticMechanicalSystems.fluidTransmissionHeat = 0
    self.spec_RealisticMechanicalSystems.fluidHydraulicHeat = 0
    self.spec_RealisticMechanicalSystems.fluidHydraulicSpeedModifier = 0
    
    self.spec_RealisticMechanicalSystems.reliability = 1.0
    self.spec_RealisticMechanicalSystems.year = RMS_ProductionYear.DEFAULT_YEAR
    self.spec_RealisticMechanicalSystems.yearIsKnown = false
    self.spec_RealisticMechanicalSystems.yearSource = RMS_ProductionYear.SOURCE.UNKNOWN

    self.spec_RealisticMechanicalSystems.activeBreakdowns = {}
    self.spec_RealisticMechanicalSystems.activeEffects = {}
    self.spec_RealisticMechanicalSystems.activeIndicators = {}
    self.spec_RealisticMechanicalSystems.activeFunctions = {}
    self.spec_RealisticMechanicalSystems.effectStates = {}

    self.spec_RealisticMechanicalSystems.maintenanceLog = {}
    
    self.spec_RealisticMechanicalSystems._fuelUsageRaw  = 0
    self.spec_RealisticMechanicalSystems.lastBlinkingWarningMessage = ""
    self.spec_RealisticMechanicalSystems.blinkingWarningTimer = 0
    self.spec_RealisticMechanicalSystems.coldEngineExposureMs = 0
    self.spec_RealisticMechanicalSystems.coldEngineWarningShown = false
    self.spec_RealisticMechanicalSystems.pendingSideNotifications = {}

    RMS_Start.initSpec(self)
    RMS_Exhaust.initSpec(self)

    self.spec_RealisticMechanicalSystems.drivetrainActionEvents = {}
    RMS_Drivetrain.initSpec(self)

    self.spec_RealisticMechanicalSystems.odometerActionEvents = {}
    self.spec_RealisticMechanicalSystems.fanActionEvents = {}
    self.spec_RealisticMechanicalSystems.tripStartKilometers = 0
    RMS_TripFuel.reset(self.spec_RealisticMechanicalSystems)
    self.spec_RealisticMechanicalSystems.odometerShowsTrip = false
    self.spec_RealisticMechanicalSystems.odometerHoldTime = 0
    self.spec_RealisticMechanicalSystems.odometerHoldHandled = false

    self.spec_RealisticMechanicalSystems.radiatorClogging = 0.0
    self.spec_RealisticMechanicalSystems.lubricationLevel = 1.0
    self.spec_RealisticMechanicalSystems.fieldInspectionSoundActive = false
    self.spec_RealisticMechanicalSystems.fieldInspectionActivePlayers = {}

    self.spec_RealisticMechanicalSystems.batterySoc = 1.0
    self.spec_RealisticMechanicalSystems.batteryHealth = 1.0
    self.spec_RealisticMechanicalSystems.batteryIsolated = false
    self.spec_RealisticMechanicalSystems.circuitResistanceFactor = 0
    self.spec_RealisticMechanicalSystems.circuitLeakageFactor = 0
    self.spec_RealisticMechanicalSystems.tractionBatteryTempC = 20
    self.spec_RealisticMechanicalSystems.rawSystemVoltageV = 12.6
    self.spec_RealisticMechanicalSystems.systemVoltageV = 12.6
    self.spec_RealisticMechanicalSystems.alternatorHealth = 1.0
    self.spec_RealisticMechanicalSystems.starterHealth = 1.0
    self.spec_RealisticMechanicalSystems.starterHeatK = 0
    self.spec_RealisticMechanicalSystems.parkBrakeDrag = 0
    self.spec_RealisticMechanicalSystems.externalPowerConnection = nil

    self.spec_RealisticMechanicalSystems.engineTemperature = -99
    self.spec_RealisticMechanicalSystems.rawEngineTemperature = -99
    self.spec_RealisticMechanicalSystems._smoothedMotorLoad = 0
    self.spec_RealisticMechanicalSystems.radiatorHealth = 1.0
    self.spec_RealisticMechanicalSystems.fanClutchHealth = 1.0
    self.spec_RealisticMechanicalSystems.hasReversibleFan = self.configurations[RMS_Thermal.REVERSIBLE_FAN] == 2
    if savegame == nil and self.age == 0 and self.propertyState == VehiclePropertyState.OWNED then
        local plan = self.configurations[RealisticMechanicalSystems.WARRANTY_CONFIGURATION] or 1
        self.spec_RealisticMechanicalSystems.warrantyPlan = plan
        -- Machine value without the extension
        self.price = self.price / (1 + RealisticMechanicalSystems.WARRANTY_PLANS[plan].rate)
    end
    self.spec_RealisticMechanicalSystems.fanReversalTime = 0
    self.spec_RealisticMechanicalSystems.fanRunningSinceReversal = 0
    self.spec_RealisticMechanicalSystems.thermostatState = 0.0
    self.spec_RealisticMechanicalSystems.thermostatHealth = 1.0
    self.spec_RealisticMechanicalSystems.thermostatStuckedPosition = nil

    self.spec_RealisticMechanicalSystems.transmissionTemperature = -99
    self.spec_RealisticMechanicalSystems.rawTransmissionTemperature = -99
    self.spec_RealisticMechanicalSystems.hydraulicTemperature = nil
    self.spec_RealisticMechanicalSystems.rawHydraulicTemperature = nil
    self.spec_RealisticMechanicalSystems._thermalEngineWorldTime = nil
    self.spec_RealisticMechanicalSystems._thermalOilWorldTime = nil
    self.spec_RealisticMechanicalSystems._thermalBatteryWorldTime = nil
    self.spec_RealisticMechanicalSystems._thermalEngineAmbient = nil
    self.spec_RealisticMechanicalSystems._thermalOilAmbient = nil
    self.spec_RealisticMechanicalSystems._thermalBatteryAmbient = nil
    self.spec_RealisticMechanicalSystems.transmissionThermostatState = 0.0
    self.spec_RealisticMechanicalSystems.overloadLevel = 0
    self.spec_RealisticMechanicalSystems.aiWorkerOverload = 0
    self.spec_RealisticMechanicalSystems.aiWorkerSpeedLimit = nil
    self.spec_RealisticMechanicalSystems.aiWorkerBlockedMs = 0
    self.spec_RealisticMechanicalSystems.aiWorkerBlockedAt = nil

    self.spec_RealisticMechanicalSystems.systemWearNow = {}
    self.spec_RealisticMechanicalSystems.systemWearRateNow = {}
    self.spec_RealisticMechanicalSystems.radiatorCloggingRate = 0
    self.spec_RealisticMechanicalSystems.airFilterCloggingRate = 0
    self.spec_RealisticMechanicalSystems.isRaisingDust = false
    self.spec_RealisticMechanicalSystems.engineHeatBalance = {}
    self.spec_RealisticMechanicalSystems.transmissionHeatBalance = {}

    self.spec_RealisticMechanicalSystems.isUnderRoof = true
    self.spec_RealisticMechanicalSystems.roofRaycastHit = false
    self.spec_RealisticMechanicalSystems.roofRaycastResult = nil
    self.spec_RealisticMechanicalSystems.roofLastRaycastTime = nil
    self.spec_RealisticMechanicalSystems.roofWasStationary = false
    self.spec_RealisticMechanicalSystems.dynamicMotorLoad = 0
    self.spec_RealisticMechanicalSystems.shownMotorLoad = 0
    self.spec_RealisticMechanicalSystems.isHarvestLoad = false
    self.spec_RealisticMechanicalSystems.motorDemand = 0
    self.spec_RealisticMechanicalSystems.rpmDrop = 0
    self.spec_RealisticMechanicalSystems.activeDraftMaxForce = 0
    self.spec_RealisticMechanicalSystems.activeDraftEffectiveForceCap = 0
    self.spec_RealisticMechanicalSystems.isCranking = false
    self.spec_RealisticMechanicalSystems.wheelSlipIntensity = 0
    self.spec_RealisticMechanicalSystems._wheelSlipPreviousSample = 0
    self.spec_RealisticMechanicalSystems._wheelSlipOlderSample = 0
    self.spec_RealisticMechanicalSystems.avgTireGroundFrictionCoeff = 0
    self.spec_RealisticMechanicalSystems.avgGroundSurfaceFactor = 0
    self.spec_RealisticMechanicalSystems.isImplementLifted = false
    self.spec_RealisticMechanicalSystems.isImplementLowered = false
    self.spec_RealisticMechanicalSystems.liftedMass = 0
    self.spec_RealisticMechanicalSystems.raisingMass = 0
    self.spec_RealisticMechanicalSystems.loadHeightCache = {}
    self.spec_RealisticMechanicalSystems.hydraulicsMoveAlphaCache = {}
    self.spec_RealisticMechanicalSystems.hydraulicsLiftRatioCache = {}
    self.spec_RealisticMechanicalSystems.hydraulicLiftMassByJoint = {}
    self.spec_RealisticMechanicalSystems.hydraulicActiveTargetCount = 0
    self.spec_RealisticMechanicalSystems.isHydraulicActive = false
    self.spec_RealisticMechanicalSystems.isHydraulicLiftMoving = false
    self.spec_RealisticMechanicalSystems.isPtoActive = false
    self.spec_RealisticMechanicalSystems.ptoTorque = 0
    self.spec_RealisticMechanicalSystems.ptoRpm = 0
    self.spec_RealisticMechanicalSystems.ptoPower = 0
    self.spec_RealisticMechanicalSystems.ptoUtilization = 0
    self.spec_RealisticMechanicalSystems.ptoEngagementCount = 0
    self.spec_RealisticMechanicalSystems.ptoEngagementDamage = 0
    self.spec_RealisticMechanicalSystems.isPtoEngagementShock = false
    self.spec_RealisticMechanicalSystems.ptoLastRpmShare = 0
    self.spec_RealisticMechanicalSystems.ptoShaftAngle = 0
    self.spec_RealisticMechanicalSystems.ptoShaftLimit = RMS_Config.CORE.DIRECT_FAILURES.PTO_SHAFT_ANGLE.limit
    self.spec_RealisticMechanicalSystems.frontPtoShaftAngle = 0
    self.spec_RealisticMechanicalSystems.frontPtoShaftLimit = RMS_Config.CORE.DIRECT_FAILURES.PTO_SHAFT_ANGLE.limit
    self.spec_RealisticMechanicalSystems.ptoShaftWear = 0
    self.spec_RealisticMechanicalSystems.isHeaderSlipping = false
    self.spec_RealisticMechanicalSystems.ptoPreviousActiveLinks = {}
    self.spec_RealisticMechanicalSystems.chassisVibState = {
        prevSuspension = {},
        smoothed = 0,
        signal = 0
    }
    self.spec_RealisticMechanicalSystems.terrainImpacts = {
        heldSpeed = 0,
        speedLoss = 0,
        count = 0,
        lastSpeedLoss = 0
    }
    self.spec_RealisticMechanicalSystems.chassisSteerState = {
        position = 0,
        travelRate = 0,
        angleMagnitude = 0,
        inputMagnitude = 0,
        groundContact = 0,
        axleLoadRatio = 1,
        isMoving = false
    }
    self.spec_RealisticMechanicalSystems.chassisBrakeState = {
        pedal = 0,
        trailerMass = 0,
        hpTrailerMassRatio = 1000,
        hpGrossMassRatio = 1000,
        isBraking = false
    }
    self.spec_RealisticMechanicalSystems.fuelState = {
        level = 0,
        currentUsageRatio = 0,
        temperature = 0,
        idleTimer = 0,
        wetStackingLevel = 0,
        particulateFilterLevel = 0,
        particulateFilterAsh = 0,
        particulateFilterOilAsh = 0,
        particulateFilterRegenerationMs = 0,
        isParticulateFilterRegenerating = false,
        isParticulateFilterOverloaded = false,
        isParticulateFilterBlocked = false
    }
    self.spec_RealisticMechanicalSystems.scrInducementHours = 0
    self.spec_RealisticMechanicalSystems.engineTorqueCap = 1
    self.spec_RealisticMechanicalSystems.isEngineDerated = false
    self.spec_RealisticMechanicalSystems.hasDebris = false

    self.spec_RealisticMechanicalSystems.onUpdateTimer = RMS_Config.ON_UPDATE_DELAY
    self.spec_RealisticMechanicalSystems.updateVehicleStateTimerOne = RMS_Config.UPDATE_VEHICLE_STATE_DELAY_ONE
    self.spec_RealisticMechanicalSystems.updateVehicleStateTimerTwo = RMS_Config.UPDATE_VEHICLE_STATE_DELAY_TWO
    self.spec_RealisticMechanicalSystems.updateVehicleStateTimerThree = RMS_Config.UPDATE_VEHICLE_STATE_DELAY_THREE
    self.spec_RealisticMechanicalSystems.metaUpdateTimer = math.random() * RMS_Config.META_UPDATE_DELAY
    self.spec_RealisticMechanicalSystems.maintenanceTimer = 0
    self.spec_RealisticMechanicalSystems.currentState = RealisticMechanicalSystems.STATUS.READY
    self.spec_RealisticMechanicalSystems.workshopType = RealisticMechanicalSystems.WORKSHOP.DEALER
    self.spec_RealisticMechanicalSystems.serviceOptionOne = nil
    self.spec_RealisticMechanicalSystems.serviceOptionTwo = nil
    self.spec_RealisticMechanicalSystems.pendingSelectedBreakdowns = {}
    self.spec_RealisticMechanicalSystems.pendingServicePrice = nil
    self.spec_RealisticMechanicalSystems.pendingServiceInvoice = nil
    self.spec_RealisticMechanicalSystems.pendingInspectionQueue = {}
    self.spec_RealisticMechanicalSystems.pendingRepairQueue = {}
    self.spec_RealisticMechanicalSystems.pendingPreventiveParts = {}
    self.spec_RealisticMechanicalSystems.pendingProgressStepIndex = 0
    self.spec_RealisticMechanicalSystems.pendingProgressTotalTime = 0
    self.spec_RealisticMechanicalSystems.pendingProgressElapsedTime = 0
    self.spec_RealisticMechanicalSystems.pendingServiceClockStart = {}
    self.spec_RealisticMechanicalSystems.pendingServiceClockTarget = {}
    self.spec_RealisticMechanicalSystems.pendingOverhaulPartStart = {}
    self.spec_RealisticMechanicalSystems.pendingOverhaulPartTarget = {}


    if self.isServer then
        local spec = self.spec_RealisticMechanicalSystems
        spec.rmsDirtyFlag = self:getNextDirtyFlag()
        spec.rmsPendingByConnection = {}
    end
end

---Returns the ids of a comma separated list that name a breakdown the mod still has
-- @param string text ids
-- @return table ids ids
local function splitSavedIds(text)
    return keepKnownIds(RMS_Utils.parseCsvList(text))
end

---Reads the saved RMS state of a vehicle
-- @param table self vehicle
-- @param table xmlFile savegame file
-- @param string key key of the specialization
-- @param string vehicleKey key of the vehicle
-- @param float currentOperatingTime operating time of the vehicle (ms)
local function loadSavedState(self, xmlFile, key, vehicleKey, currentOperatingTime)
    local spec = self.spec_RealisticMechanicalSystems
    spec.serviceLevel = RealisticMechanicalSystems.sanitizeNumber(xmlFile:getValue(key .. "#service", spec.serviceLevel), spec.serviceLevel, 0.001)
    spec.transmissionServiceLevel = RealisticMechanicalSystems.sanitizeNumber(
        xmlFile:getValue(key .. "#transmissionService", spec.transmissionServiceLevel), spec.transmissionServiceLevel, 0.001)
    spec.coolantServiceLevel = RealisticMechanicalSystems.sanitizeNumber(xmlFile:getValue(key .. "#coolantService", spec.coolantServiceLevel), spec.coolantServiceLevel, 0.001)
    spec.hydraulicServiceLevel = RealisticMechanicalSystems.sanitizeNumber(
        xmlFile:getValue(key .. "#hydraulicService", spec.hydraulicServiceLevel), spec.hydraulicServiceLevel, 0.001)
    spec.serviceCalendar = RMS_Utils.deserializeNumericMap(xmlFile:getValue(key .. "#serviceCalendar", ""))
    spec.warrantyPlan = xmlFile:getValue(key .. "#warrantyPlan", 1)
    spec.partWarranty = keepKnownKeys(RMS_Utils.deserializeNumericMap(xmlFile:getValue(key .. "#partWarranty", "")))
    spec.usedPartWarranty = keepKnownKeys(RMS_Utils.deserializeNumericMap(xmlFile:getValue(key .. "#usedPartWarranty", "")))
    spec.warrantyVoided = xmlFile:getValue(key .. "#warrantyVoided", false)
    spec.remapMotor = xmlFile:getValue(key .. "#remapMotor", 0)
    spec.remapAge = xmlFile:getValue(key .. "#remapAge", 0)
    spec.remapByDealer = xmlFile:getValue(key .. "#remapByDealer", false)
    RMS_EngineRemap.validateLoadedEngine(self)
    local savedAge = xmlFile:getValue(vehicleKey .. "#age", 0)
    for _, clock in ipairs(RealisticMechanicalSystems.SERVICE_CLOCKS) do
        if spec.serviceCalendar[clock.key] == nil then
            spec.serviceCalendar[clock.key] = savedAge
        end
    end
    spec.conditionLevel = RealisticMechanicalSystems.sanitizeNumber(xmlFile:getValue(key .. "#condition", spec.conditionLevel), spec.conditionLevel, 0.001, 1.0)
    spec.currentState = xmlFile:getValue(key .. "#state", spec.currentState)
    if RMS_Utils.getKeyByValue(RealisticMechanicalSystems.STATUS, spec.currentState) == nil then
        spec.currentState = RealisticMechanicalSystems.STATUS.READY
    end
    spec.maintenanceTimer = RealisticMechanicalSystems.sanitizeNumber(xmlFile:getValue(key .. "#maintenanceTimer", spec.maintenanceTimer), spec.maintenanceTimer, 0)
    spec.maintenanceTimerTime = RMS_Thermal.getWorldTimeMS()
    
    local loadedRealOperatingTime = xmlFile:getValue(key .. "#realOperatingTime")
    if loadedRealOperatingTime ~= nil then
        spec.realOperatingTime = RealisticMechanicalSystems.sanitizeNumber(loadedRealOperatingTime, currentOperatingTime, 0)
    else
        spec.realOperatingTime = currentOperatingTime
    end

    spec.activeBreakdowns = RMS_Utils.deserializeBreakdowns(xmlFile:getValue(key .. "#breakdowns", ""))
    for breakdownId, breakdown in pairs(spec.activeBreakdowns) do
        if self.isServer and breakdown.usedPartHours == nil then
            breakdown.usedPartHours = RealisticMechanicalSystems.drawUsedPartDonorHours(breakdownId)
        end
    end

    spec.engineTemperature = RealisticMechanicalSystems.sanitizeNumber(xmlFile:getValue(key .. "#engineTemperature", spec.engineTemperature), 20)
    spec.transmissionTemperature = RealisticMechanicalSystems.sanitizeNumber(
        xmlFile:getValue(key .. "#transmissionTemperature", spec.transmissionTemperature),
        spec.engineTemperature
    )
    spec.rawHydraulicTemperature = xmlFile:getValue(key .. "#hydraulicTemperature")
    spec.batterySoc = RealisticMechanicalSystems.sanitizeNumber(xmlFile:getValue(key .. "#batterySoc", spec.batterySoc), 1.0, 0, 1)
    spec.batteryIsolated = xmlFile:getValue(key .. "#batteryIsolated", spec.batteryIsolated)
    spec.tractionBatteryTempC = RealisticMechanicalSystems.sanitizeNumber(xmlFile:getValue(key .. "#tractionBatteryTempC", spec.tractionBatteryTempC), 20)
    spec.radiatorClogging = math.clamp(xmlFile:getValue(key .. "#radiatorClogging", spec.radiatorClogging), 0, 1)
    spec.airFilterClogging = math.clamp(xmlFile:getValue(key .. "#airFilterClogging", spec.airFilterClogging), 0, 1)
    spec.airFilterResidue = math.clamp(xmlFile:getValue(key .. "#airFilterResidue", spec.airFilterResidue), 0, spec.airFilterClogging)
    for _, filter in ipairs(RMS_Consumables.FILTERS) do
        spec[filter.stateKey] = xmlFile:getValue(key .. "#" .. filter.stateKey, spec[filter.stateKey])
    end
    spec.engineOilLevel = math.clamp(xmlFile:getValue(key .. "#engineOilLevel", spec.engineOilLevel), 0.0, 1.0)
    spec.coolantLevel = math.clamp(xmlFile:getValue(key .. "#coolantLevel", spec.coolantLevel), 0.0, 1.0)
    spec.transmissionOilLevel = math.clamp(xmlFile:getValue(key .. "#transmissionOilLevel", spec.transmissionOilLevel), 0.0, 1.0)
    spec.hydraulicFluidLevel = math.clamp(xmlFile:getValue(key .. "#hydraulicFluidLevel", spec.hydraulicFluidLevel), 0.0, 1.0)
    spec.fluidCapacityVersion = xmlFile:getValue(key .. "#fluidCapacityVersion")
    spec.fluidCapacities = {
        engineOil = math.max(xmlFile:getValue(key .. "#engineOilCapacity", 0), 0),
        coolant = math.max(xmlFile:getValue(key .. "#coolantCapacity", 0), 0),
        transmissionOil = math.max(xmlFile:getValue(key .. "#transmissionOilCapacity", 0), 0),
        hydraulicFluid = math.max(xmlFile:getValue(key .. "#hydraulicFluidCapacity", 0), 0)
    }
    spec.fluidCompatibility = {
        engineOil = math.clamp(xmlFile:getValue(key .. "#engineOilCompatibility", 1), 0, 1),
        coolant = math.clamp(xmlFile:getValue(key .. "#coolantCompatibility", 1), 0, 1),
        transmissionOil = math.clamp(xmlFile:getValue(key .. "#transmissionOilCompatibility", 1), 0, 1),
        hydraulicFluid = math.clamp(xmlFile:getValue(key .. "#hydraulicFluidCompatibility", 1), 0, 1)
    }
    spec.engineOilSuitedShare = math.clamp(xmlFile:getValue(key .. "#engineOilSuitedShare", 1), 0, 1)
    spec.fluidLeakLossDebt = keepKnownKeys(RMS_Fluids.deserializeLeakDebt(xmlFile:getValue(key .. "#fluidLeakLossDebt", "")))
    spec.pendingFluidRequirements = RMS_Fluids.deserializeServiceRequirements(xmlFile:getValue(key .. "#pendingFluidRequirements", ""))
    spec.fuelState.wetStackingLevel = RealisticMechanicalSystems.sanitizeNumber(xmlFile:getValue(key .. "#wetStackingLevel", spec.fuelState.wetStackingLevel), 0, 0, 1)
    spec.fuelState.particulateFilterLevel = RealisticMechanicalSystems.sanitizeNumber(xmlFile:getValue(key .. "#particulateFilterLevel", 0), 0, 0,
        RMS_Config.EXHAUST.PARTICULATE_FILTER.SERVICE_LEVEL)
    spec.fuelState.particulateFilterAsh = RealisticMechanicalSystems.sanitizeNumber(xmlFile:getValue(key .. "#particulateFilterAsh", 0), 0, 0, 1)
    spec.fuelState.particulateFilterOilAsh = RealisticMechanicalSystems.sanitizeNumber(xmlFile:getValue(key .. "#particulateFilterOilAsh", 0), 0, 0, 1)
    spec.scrInducementHours = RealisticMechanicalSystems.sanitizeNumber(xmlFile:getValue(key .. "#scrInducementHours", 0), 0, 0)
    spec.fuelState.isParticulateFilterOverloaded = xmlFile:getValue(key .. "#particulateFilterOverloaded", false)
    RMS_Greasing.deserialize(self, xmlFile:getValue(key .. "#greasing"))
    spec.thermostatState = RealisticMechanicalSystems.sanitizeNumber(xmlFile:getValue(key .. "#thermostatState", spec.thermostatState), spec.thermostatState, 0.0, 1.0)
    spec.transmissionThermostatState = RealisticMechanicalSystems.sanitizeNumber(
        xmlFile:getValue(key .. "#transmissionThermostatState", spec.transmissionThermostatState),
        spec.transmissionThermostatState,
        0.0,
        1.0
    )
    spec.ptoEngagementCount = math.floor(math.max(xmlFile:getValue(key .. "#ptoEngagementCount", spec.ptoEngagementCount), 0))
    spec.loadedHeaderStarts = math.floor(math.max(xmlFile:getValue(key .. "#headerStartCount", 0), 0))
    spec.serviceOptionOne = xmlFile:getValue(key .. "#serviceOptionOne", spec.serviceOptionOne)
    spec.serviceOptionTwo = xmlFile:getValue(key .. "#serviceOptionTwo", spec.serviceOptionTwo)
    -- An empty choice is saved as an empty text
    for _, field in ipairs({ "serviceOptionOne", "serviceOptionTwo" }) do
        if spec[field] == "" then
            spec[field] = nil
        end
    end
    RMS_Drivetrain.loadFromSavegame(self, xmlFile, key)
    spec.tripStartKilometers = xmlFile:getValue(key .. "#tripStartKilometers", spec.tripStartKilometers)
    for _, name in ipairs({ "tripFuelLitres", "tripEngineTime", "tripWorkFuelLitres", "tripWorkedHectares" }) do
        spec[name] = xmlFile:getValue(key .. "#" .. name, spec[name])
    end
    local loadedWorkshopType = xmlFile:getValue(key .. "#workshopType", "")
    if loadedWorkshopType ~= "" then
        spec.workshopType = loadedWorkshopType
    end
    spec.pendingServicePrice = RMS_Utils.decodeOptionalFloat(xmlFile:getValue(key .. "#pendingServicePrice", spec.pendingServicePrice))
    spec.pendingServiceInvoice = RMS_Utils.deserializeInvoice(xmlFile:getValue(key .. "#pendingServiceInvoice"))
    spec.pendingSelectedBreakdowns = splitSavedIds(xmlFile:getValue(key .. "#pendingSelectedBreakdowns", ""))
    spec.pendingInspectionQueue = splitSavedIds(xmlFile:getValue(key .. "#pendingInspectionQueue", ""))
    spec.pendingRepairQueue = splitSavedIds(xmlFile:getValue(key .. "#pendingRepairQueue", ""))
    spec.pendingPreventiveParts = keepKnownKeys(RMS_Utils.deserializeNumericMap(xmlFile:getValue(key .. "#pendingPreventiveParts", "")))

    spec.pendingProgressStepIndex = xmlFile:getValue(key .. "#pendingProgressStepIndex", spec.pendingProgressStepIndex)
    spec.pendingProgressTotalTime = xmlFile:getValue(key .. "#pendingProgressTotalTime", spec.pendingProgressTotalTime)
    spec.pendingProgressElapsedTime = xmlFile:getValue(key .. "#pendingProgressElapsedTime", spec.pendingProgressElapsedTime)
    spec.pendingServiceClockStart = RMS_Utils.deserializeNumericMap(xmlFile:getValue(key .. "#pendingServiceClockStart", ""))
    spec.pendingServiceClockTarget = RMS_Utils.deserializeNumericMap(xmlFile:getValue(key .. "#pendingServiceClockTarget", ""))
    spec.pendingOverhaulPartStart = keepKnownKeys(RMS_Utils.deserializeNumericMap(xmlFile:getValue(key .. "#pendingOverhaulPartStart", "")))
    spec.pendingOverhaulPartTarget = keepKnownKeys(RMS_Utils.deserializeNumericMap(xmlFile:getValue(key .. "#pendingOverhaulPartTarget", "")))
    spec.partWear = keepKnownKeys(RMS_Utils.deserializeNumericMap(xmlFile:getValue(key .. "#partWear", "")))
    spec.partCauseWear = keepKnownKeys(unflattenPartCauseWear(RMS_Utils.deserializeNumericMap(xmlFile:getValue(key .. "#partCauseWear", ""))))
    spec.partAbuse = keepKnownKeys(RMS_Utils.deserializeNumericMap(xmlFile:getValue(key .. "#partAbuse", "")))
    spec.pickupAirTime = keepKnownKeys(RMS_Utils.deserializeNumericMap(xmlFile:getValue(key .. "#pickupAirTime", "")))
    local loadedFactorStatsFlat = RMS_Utils.deserializeNumericMap(xmlFile:getValue(key .. "#factorStats", ""))

    local loadedSystemsStateRaw = RMS_Utils.deserializeSystemsState(xmlFile:getValue(key .. "#systemsState", ""))
    local loadedSystemsState = {}
    for loadedKey, loadedData in pairs(loadedSystemsStateRaw) do
        loadedSystemsState[string.lower(loadedKey)] = loadedData
    end
    local hasSerializedSystemsState = next(loadedSystemsState) ~= nil

    for systemKey, systemData in pairs(spec.systems) do
        local loadedData = loadedSystemsState[systemKey]
        if loadedData ~= nil then
            systemData.condition = math.clamp(loadedData.condition, 0.001, 1.0)
            systemData.enabled = loadedData.enabled
        elseif not hasSerializedSystemsState then
            systemData.condition = spec.conditionLevel
        end
    end
    applyFlattenedFactorStats(spec, loadedFactorStatsFlat)

    spec.maintenanceLog = {}
    local index = 0
    while xmlFile:hasProperty(string.format("%s.maintenanceLog.entry(%d)", key, index)) do
        local entryKey = string.format("%s.maintenanceLog.entry(%d)", key, index)
        index = index + 1
        -- Entries without condition data come from a format no longer read
        local conditionKey = entryKey .. ".conditionData"
        if xmlFile:hasProperty(conditionKey) then
            local entry = { conditionData = {} }
            readLogFields(xmlFile, entryKey, entry, LOG_ENTRY_XML)
            readLogFields(xmlFile, conditionKey, entry.conditionData, LOG_CONDITION_XML)
            table.insert(spec.maintenanceLog, entry)
        end
    end

    self:updateConditionLevel()
end

---Called after loading
-- @param table? savegame savegame
function RealisticMechanicalSystems:onPostLoad(savegame)
    local spec = self.spec_RealisticMechanicalSystems
    local currentOperatingTime = self:getOperatingTime()
    local savedKey = savegame ~= nil and RealisticMechanicalSystems.getSavegameKey(savegame) or nil

    spec.isNewToRMS = savegame == nil or not savegame.xmlFile:hasProperty(savedKey)
    spec.isExcludedByRule = getIsAuxiliaryMachine(self.xmlFile) or getIsTowedMachine(self)
    spec.isExcludedByUser = nil
    if savegame ~= nil then
        spec.isExcludedByUser = savegame.xmlFile:getValue(savedKey .. "#userExclusion")
    end
    refreshExclusionState(spec)

    if savegame ~= nil then
        loadSavedState(self, savegame.xmlFile, savedKey, savegame.key, currentOperatingTime)
    else
        spec.realOperatingTime = currentOperatingTime
    end

    if spec.realOperatingTime <= 0 and currentOperatingTime > 0 then
        spec.realOperatingTime = currentOperatingTime
    end

    spec.isUnderRoof = self:isUnderRoof()

    spec.fieldInspection = {}

    local xmlSoundFile = loadXMLFile("rmsSounds", RealisticMechanicalSystems.modDirectory .. "sounds/rms_sounds.xml")
    spec.samples = {}
    local soundManager = g_soundManager
    local modDir = RealisticMechanicalSystems.modDirectory
    local root = self.components
    local i3d = self.i3dMappings

    for _, name in ipairs(RealisticMechanicalSystems.SAMPLE_NAMES) do
        spec.samples[name] = soundManager:loadSampleFromXML(xmlSoundFile, "sounds", name, modDir, root, 1, AudioGroup.VEHICLE, i3d, self)
    end
    if not getIsElectricVehicle(self) then
        local name = "starter" .. RMS_Breakdowns.getStarterFamily(self)
        -- no target: a machine's volume factor balances its own sounds only
        spec.samples.starterIntro = soundManager:loadSampleFromXML(xmlSoundFile, "sounds", name .. "Intro", modDir, root, 1, AudioGroup.VEHICLE, i3d)
        spec.samples.starter = soundManager:loadSampleFromXML(xmlSoundFile, "sounds", name, modDir, root, 0, AudioGroup.VEHICLE, i3d)
        spec.samples.starterCatch = soundManager:loadSampleFromXML(xmlSoundFile, "sounds", name .. "Catch", modDir, root, 1, AudioGroup.VEHICLE, i3d)
    end
    delete(xmlSoundFile)

    RMS_Thermal.initializeEngineTemperature(self)
    spec.rawTransmissionTemperature = spec.transmissionTemperature

    spec.isElectricVehicle = getIsElectricVehicle(self)
    spec.isDieselVehicle = RMS_Preheat.isDieselVehicle(self)
    spec.hydraulicsMoveAlphaCache = {}
    spec.hydraulicsLiftRatioCache = {}

    ---Clears the moving state of a vehicle and of what it carries, each once
    -- @param table vehicleObj vehicle
    -- @param table visited vehicles already reset
    local function resetIsMovingRecursive(vehicleObj, visited)
        if visited[vehicleObj] then
            return
        end
        visited[vehicleObj] = true

        if vehicleObj.spec_attacherJoints ~= nil then
            for _, jointDesc in pairs(vehicleObj.spec_attacherJoints.attacherJoints) do
                jointDesc.isMoving = false
            end

            for _, implementData in pairs(vehicleObj.spec_attacherJoints.attachedImplements) do
                if implementData.object ~= nil then
                    resetIsMovingRecursive(implementData.object, visited)
                end
            end
        end
    end

    local capacities = RMS_Fluids.resolveCapacities(self)
    local isHarvester = RMS_Drivetrain.getHarvestKind(self) ~= nil
    spec.systems.hydraulics.enabled = RMS_Utils.hasHydraulicCapability(self) and capacities.hydraulicFluid > 0
    spec.systems.pto.enabled = RMS_Utils.getHasWearablePto(self)
    spec.systems.harvest.enabled = isHarvester or RMS_Utils.getIsSelfPropelledMower(self)
    RealisticMechanicalSystems.buildSystemParts(self)
    if spec.partWear.HEADER_DRIVE_BELT_WEAR ~= nil then
        spec.headerDrive = RealisticMechanicalSystems.newHeaderDrive(spec.loadedHeaderStarts)
    end
    RMS_Fluids.initializeVehicle(self)
    RealisticMechanicalSystems.getServiceClocks(self)
    if RMS_Thermal.getHasSeparateHydraulicCircuit(spec) then
        spec.rawHydraulicTemperature = RealisticMechanicalSystems.sanitizeNumber(spec.rawHydraulicTemperature, spec.rawTransmissionTemperature)
        spec.hydraulicTemperature = spec.rawHydraulicTemperature
    else
        spec.rawHydraulicTemperature = nil
        spec.hydraulicTemperature = nil
    end
    spec._thermalEngineWorldTime, spec._thermalOilWorldTime, spec._thermalBatteryWorldTime = nil, nil, nil
    spec._thermalEngineAmbient, spec._thermalOilAmbient, spec._thermalBatteryAmbient = nil, nil, nil
    if spec.isElectricVehicle then
        RMS_ElectricDrive.initBatteryCapacity(self)
    end
    local isRoadVehicle = RMS_Drivetrain.getIsRoadVehicleCategory(self)
    RMS_Greasing.initialize(self)
    spec.isVehicleNeedBlowOut = not isRoadVehicle
    resetIsMovingRecursive(self, {})

    RealisticMechanicalSystems.storeSyncBaseline(self)

    RMS_Electrical.initializeVehicle(self)

    self:recalculateAndApplyEffects(true)
end

local SALE_STATE_KEY = "vehicles.vehicle(0)"

---Writes the RMS state of a vehicle to a string
-- @param table vehicle vehicle
-- @return string state RMS state saved
function RealisticMechanicalSystems.saveStateToMemory(vehicle)
    local xmlFile = XMLFile.create("rmsSaleState", "", "vehicles", Vehicle.xmlSchemaSavegame)
    RealisticMechanicalSystems.saveToXMLFile(vehicle, xmlFile, SALE_STATE_KEY .. ".RealisticMechanicalSystems", {})
    local state = saveXMLFileToMemory(xmlFile.handle)
    xmlFile:delete()
    return state
end

---Gives a bought used offer the RMS state of the machine a player sold
-- @param table saleItem used offer bought
function RealisticMechanicalSystems:onSaleItemSet(saleItem)
    if not self.isServer or saleItem.rmsState == nil then
        return
    end
    local spec = self.spec_RealisticMechanicalSystems
    local xmlFile = XMLFile.wrap(loadXMLFileFromMemory("rmsSaleState", saleItem.rmsState), Vehicle.xmlSchemaSavegame)
    local key = SALE_STATE_KEY .. ".RealisticMechanicalSystems"
    spec.isExcludedByUser = xmlFile:getValue(key .. "#userExclusion")
    refreshExclusionState(spec)
    loadSavedState(self, xmlFile, key, SALE_STATE_KEY, saleItem.operatingTime)
    xmlFile:delete()
    spec.isNewToRMS = false
    self:recalculateAndApplyEffects()
    RealisticMechanicalSystems.raiseRMSDirty(self, RealisticMechanicalSystems.SYNC_GROUP_ALL)
end

---Called on deleting
function RealisticMechanicalSystems:onDelete()
    local spec = self.spec_RealisticMechanicalSystems

    if self.isClient then
        RMS_Exhaust.reset(self)
    end

    if spec.samples then
        g_soundManager:deleteSamples(spec.samples)
    end

    if RMS_Main.vehicles[self.uniqueId] then
        if RMS_Main.previousKey == self.uniqueId then
            RMS_Main.previousKey = nil
        end
        RMS_Main.vehicles[self.uniqueId] = nil
        RMS_Main.numVehicles = RMS_Main.numVehicles - 1
    end
end
