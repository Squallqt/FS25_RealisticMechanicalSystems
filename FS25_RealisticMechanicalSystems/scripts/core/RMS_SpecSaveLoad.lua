-- Copyright © 2026 Squallqt. All rights reserved.

---Vehicle savegame persistence.

local log_dbg = RMS_Utils.createLogger("[RMS_SPEC]")
local getIsElectricVehicle = RMS_Utils.getIsElectricVehicle
local ensureFactorStats = RealisticMechanicalSystems.ensureFactorStats
local refreshExclusionState = RealisticMechanicalSystems.refreshExclusionState

---Wear statistics of systems not worked yet, their hours unrecorded
local function createEmptyFactorStats(systems)
    local stats = {}
    for systemKey in pairs(type(systems) == "table" and systems or {}) do
        stats[systemKey] = { total = 0, _prevStress = 0, _avgStress = 0, operatingHours = -1 }
    end
    return stats
end

---Wear statistics as one map keyed system.cause, numbers only
local function flattenFactorStats(factorStats)
    local flat = {}
    for systemKey, stats in pairs(type(factorStats) == "table" and factorStats or {}) do
        if type(stats) == "table" then
            for statKey, value in pairs(stats) do
                local number = tonumber(value)
                if number ~= nil then
                    flat[tostring(systemKey) .. "." .. tostring(statKey)] = number
                end
            end
        end
    end
    return flat
end

---Puts flattened wear statistics back under their systems
local function applyFlattenedFactorStats(spec, flattenedMap)
    if spec == nil then
        return
    end
    if type(spec.factorStats) ~= "table" then
        spec.factorStats = {}
    end
    for flatKey, value in pairs(type(flattenedMap) == "table" and flattenedMap or {}) do
        local systemKey, statKey = string.match(tostring(flatKey), "([^%.]+)%.(.+)")
        local number = tonumber(value)
        if systemKey ~= nil and number ~= nil then
            local stats = spec.factorStats[systemKey]
            if type(stats) ~= "table" then
                stats = {}
                spec.factorStats[systemKey] = stats
            end
            stats[statKey] = number
        end
    end
end

local function getIsAuxiliaryMachine(xmlFile)
    return not xmlFile:getValue("vehicle.enterable#isTabbable", true)
end

local function getIsTowedMachine(vehicle)
    return vehicle.getInputAttacherJoints ~= nil and #vehicle:getInputAttacherJoints() > 0
end

---Tells whether RMS tracks a store item once bought
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
-- @param Connection? connection player connection, nil for the local player
function RealisticMechanicalSystems.getCanSetUserExclusion(vehicle, isExcluded, connection)
    local spec = vehicle.spec_RealisticMechanicalSystems
    if spec == nil or (isExcluded and vehicle:isUnderService()) then
        return false
    end

    if connection == nil then
        return g_currentMission:getIsServer() or g_currentMission.isMasterUser == true
    end
    return g_currentMission.userManager:getUserByConnection(connection):getIsMasterUser()
end

---Tells whether the vehicle sits in the trucks store category
RealisticMechanicalSystems.SAMPLE_NAMES = {
    "starterRelayClick", "batteryClicking", "preheatRelay",
    "hvContactor", "alarm", "warning", "transmissionShiftFailed", "gearDisengage", "powershiftClunk", "brakes",
    "parkBrakeLeverApply", "parkBrakeLeverRelease", "parkBrakeAutoApply", "parkBrakeAutoRelease", "parkBrakeSwitchOn",
    "parkBrakeSwitchOff", "fanReversalSwitch", "parkBrakeTruckApply", "parkBrakeTruckRelease",
    "engineKnocking", "pistonSlap", "valveTrainNoise", "injectorKnock", "highPressurePump", "turboWhistle", "fanNoice", "fanBladeImbalance",
    "accessoryBelt", "waterPumpBearing", "gearWhineNoise", "gearboxBearingNoise", "transmissionPump", "hydrostaticWhine",
    "hydraulicPump", "coolantSteam", "gasLeak", "parkBrakeDrag", "steeringLinkage", "steeringKnuckle", "steeringOrbitrol",
    "wheelHubBearingNoise", "wheelSeizureGrind", "trackRoller", "trackClatter", "loaderPins", "frontAxleShaft", "cabDamper", "ptoBearingNoise", "ptoSplines",
    "electricMotorBearing", "hoseBurst", "ptoShaftBreak", "inspection", "batteryIsolator"
}

local function getIsTruck(vehicle)
    if vehicle == nil or vehicle.configFileName == nil then
        return false
    end

    local storeItem = g_storeManager:getItemByXMLFilename(vehicle.configFileName)
    local categoryName = storeItem ~= nil and tostring(storeItem.categoryName or "") or ""
    return string.upper(categoryName) == "TRUCKS"
end


---Log entry attributes in saved order; isDetail: with condition data
local LOG_ENTRY_XML = {
    { name = "id", write = function(entry) return entry.id or 0 end },
    { name = "type", write = function(entry) return entry.type or "" end },
    { name = "price", write = function(entry) return entry.price or 0 end },
    { name = "date", write = function(entry) return RMS_Utils.serializeDate(entry.date) end,
        read = function(value) return RMS_Utils.deserializeDate(value) end },
    { name = "location", isDetail = true, default = "UNKNOWN" },
    { name = "optionOne", isDetail = true, default = "NONE" },
    { name = "optionTwo", isDetail = true, default = "NONE" },
    { name = "isVisible", isDetail = true, default = true,
        write = function(entry) return tostring(RMS_Utils.normalizeBoolValue(entry.isVisible, true)) end,
        read = function(value) return RMS_Utils.normalizeBoolValue(value, true) end },
    { name = "isCompleted", isDetail = true, default = true,
        write = function(entry) return RMS_Utils.normalizeBoolValue(entry.isCompleted, true) end,
        read = function(value) return RMS_Utils.normalizeBoolValue(value, true) end },
    { name = "invoice", isDetail = true,
        write = function(entry) return entry.invoice ~= nil and RMS_Utils.serializeInvoice(entry.invoice) or nil end,
        read = function(value) return RMS_Utils.deserializeInvoice(value) end }
}

---Attributes of the machine as a log entry found it, in saved order
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
        read = function(value) return RMS_Utils.createSystemsSnapshot(RMS_Utils.deserializeSystemsState(value)) end },
    { name = "partWear", default = "",
        write = function(data) return RMS_Utils.serializeNumericMap(data.partWear) end,
        read = function(value) return RMS_Utils.deserializeNumericMap(value) end },
    { name = "batterySoc", default = 1 },
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
        read = function(value) return RMS_Utils.parseCsvList(value) end },
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
function RealisticMechanicalSystems:saveToXMLFile(xmlFile, key, usedModNames)
    local spec = self.spec_RealisticMechanicalSystems
    if spec ~= nil and not spec.isNewToRMS then
        -- Catch up only within the current mission clock.
        if self.isServer and not spec.isExcludedVehicle and self.getMotor ~= nil and self:getMotor() ~= nil
           and self.getIsMotorStarted ~= nil and not self:getIsMotorStarted()
           and self.updateThermalSystems ~= nil and RMS_Thermal.getWorldTimeMS() ~= nil then
            self:updateThermalSystems(1, true, true)
        end
        if spec.isExcludedByUser ~= nil then
            xmlFile:setValue(key .. "#userExclusion", spec.isExcludedByUser)
        end
        -- RMS working time, from the game's while RMS has counted none
        local gameTime = self.getOperatingTime ~= nil and self:getOperatingTime() or self.operatingTime or 0
        if (spec.realOperatingTime or 0) <= 0 and gameTime > 0 then
            spec.realOperatingTime = gameTime
        end
        local workingTime = spec.realOperatingTime or gameTime
        xmlFile:setValue(key .. "#service", spec.serviceLevel or 1.0)
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
        xmlFile:setValue(key .. "#condition", spec.conditionLevel or 1.0)
        xmlFile:setValue(key .. "#realOperatingTime", workingTime)
        if xmlFile.handle ~= nil then
            setXMLFloat(xmlFile.handle, key .. "#realOperatingTime", tonumber(workingTime) or 0)
        end
        xmlFile:setValue(key .. "#breakdowns", RMS_Utils.serializeBreakdowns(spec.activeBreakdowns))
        xmlFile:setValue(key .. "#state", spec.currentState or RealisticMechanicalSystems.STATUS.READY)
        xmlFile:setValue(key .. "#maintenanceTimer", RealisticMechanicalSystems.sanitizeNumber(spec.maintenanceTimer, 0, 0))
        xmlFile:setValue(key .. "#engineTemperature", RMS_Thermal.getEngineTemperature(self))
        xmlFile:setValue(key .. "#transmissionTemperature", RealisticMechanicalSystems.sanitizeNumber(spec.rawTransmissionTemperature or spec.transmissionTemperature, 20))
        if RMS_Thermal.getHasSeparateHydraulicCircuit(spec) then
            xmlFile:setValue(key .. "#hydraulicTemperature", RealisticMechanicalSystems.sanitizeNumber(
                spec.rawHydraulicTemperature or spec.hydraulicTemperature, spec.rawTransmissionTemperature or 20))
        end
        if type(spec._thermalEngineWorldTime) == "number" and spec._thermalEngineWorldTime == spec._thermalEngineWorldTime and math.abs(spec._thermalEngineWorldTime) < math.huge then
            xmlFile:setValue(key .. "#thermalWorldTime", spec._thermalEngineWorldTime)
            xmlFile:setValue(key .. "#thermalAmbient", RealisticMechanicalSystems.sanitizeNumber(spec._thermalEngineAmbient, 20, -80, 80))
        end
        xmlFile:setValue(key .. "#batterySoc", RealisticMechanicalSystems.sanitizeNumber(spec.batterySoc, 1.0, 0, 1))
        xmlFile:setValue(key .. "#batteryIsolated", spec.batteryIsolated)
        if spec.isElectricVehicle then
            xmlFile:setValue(key .. "#tractionBatteryTempC", RealisticMechanicalSystems.sanitizeNumber(spec.tractionBatteryTempC, 20))
        end
        xmlFile:setValue(key .. "#radiatorClogging", math.max(spec.radiatorClogging or 0, 0))
        xmlFile:setValue(key .. "#airFilterClogging", math.max(spec.airFilterClogging or 0, 0))
        xmlFile:setValue(key .. "#airFilterResidue", math.max(spec.airFilterResidue or 0, 0))
        for _, filter in ipairs(RMS_Consumables.FILTERS) do
            xmlFile:setValue(key .. "#" .. filter.stateKey, spec[filter.stateKey])
        end
        xmlFile:setValue(key .. "#engineOilLevel", math.clamp(spec.engineOilLevel or 1.0, 0.0, 1.0))
        xmlFile:setValue(key .. "#coolantLevel", math.clamp(spec.coolantLevel or 1.0, 0.0, 1.0))
        xmlFile:setValue(key .. "#transmissionOilLevel", math.clamp(spec.transmissionOilLevel or 1.0, 0.0, 1.0))
        xmlFile:setValue(key .. "#hydraulicFluidLevel", math.clamp(spec.hydraulicFluidLevel or 1.0, 0.0, 1.0))
        xmlFile:setValue(key .. "#fluidCapacityVersion", spec.fluidCapacityVersion or RMS_Fluids.CAPACITY_VERSION)
        xmlFile:setValue(key .. "#fluidCapacitySource", spec.fluidCapacitySource or "")
        xmlFile:setValue(key .. "#engineOilCapacity", spec.fluidCapacities.engineOil)
        xmlFile:setValue(key .. "#coolantCapacity", spec.fluidCapacities.coolant)
        xmlFile:setValue(key .. "#transmissionOilCapacity", spec.fluidCapacities.transmissionOil)
        xmlFile:setValue(key .. "#hydraulicFluidCapacity", spec.fluidCapacities.hydraulicFluid)
        xmlFile:setValue(key .. "#engineOilCompatibility", spec.fluidCompatibility.engineOil)
        xmlFile:setValue(key .. "#coolantCompatibility", spec.fluidCompatibility.coolant)
        xmlFile:setValue(key .. "#transmissionOilCompatibility", spec.fluidCompatibility.transmissionOil)
        xmlFile:setValue(key .. "#hydraulicFluidCompatibility", spec.fluidCompatibility.hydraulicFluid)
        xmlFile:setValue(key .. "#fluidLeakLossDebt", RMS_Fluids.serializeLeakDebt(spec.fluidLeakLossDebt))
        xmlFile:setValue(key .. "#wetStackingLevel", RealisticMechanicalSystems.sanitizeNumber(spec.fuelState.wetStackingLevel, 0, 0, 1))
        xmlFile:setValue(key .. "#particulateFilterLevel", RealisticMechanicalSystems.sanitizeNumber(spec.fuelState.particulateFilterLevel, 0, 0, RMS_Config.EXHAUST.PARTICULATE_FILTER.SERVICE_LEVEL))
        xmlFile:setValue(key .. "#scrInducementHours", RealisticMechanicalSystems.sanitizeNumber(spec.scrInducementHours, 0, 0))
        xmlFile:setValue(key .. "#particulateFilterOverloaded", spec.fuelState.isParticulateFilterOverloaded == true)
        xmlFile:setValue(key .. "#greasing", RMS_Greasing.serialize(self))
        xmlFile:setValue(key .. "#thermostatState", RealisticMechanicalSystems.sanitizeNumber(spec.thermostatState, 0.0, 0.0, 1.0))
        xmlFile:setValue(key .. "#transmissionThermostatState", RealisticMechanicalSystems.sanitizeNumber(spec.transmissionThermostatState, 0.0, 0.0, 1.0))
        xmlFile:setValue(key .. "#serviceOptionOne", spec.serviceOptionOne or "")
        xmlFile:setValue(key .. "#serviceOptionTwo", spec.serviceOptionTwo or "")
        xmlFile:setValue(key .. "#workshopType", spec.workshopType or "")
        xmlFile:setValue(key .. "#pendingSelectedBreakdowns", table.concat(spec.pendingSelectedBreakdowns or {}, ","))
        xmlFile:setValue(key .. "#pendingServicePrice", RMS_Utils.encodeOptionalFloat(spec.pendingServicePrice))
        xmlFile:setValue(key .. "#pendingServiceInvoice", RMS_Utils.serializeInvoice(spec.pendingServiceInvoice))
        xmlFile:setValue(key .. "#pendingInspectionQueue", table.concat(spec.pendingInspectionQueue or {}, ","))
        xmlFile:setValue(key .. "#pendingRepairQueue", table.concat(spec.pendingRepairQueue or {}, ","))
        xmlFile:setValue(key .. "#pendingFluidRequirements", RMS_Fluids.serializeServiceRequirements(spec.pendingFluidRequirements))
        xmlFile:setValue(key .. "#pendingProgressStepIndex", spec.pendingProgressStepIndex or 0)
        xmlFile:setValue(key .. "#pendingProgressTotalTime", spec.pendingProgressTotalTime or 0)
        xmlFile:setValue(key .. "#pendingProgressElapsedTime", spec.pendingProgressElapsedTime or 0)
        xmlFile:setValue(key .. "#pendingServiceClockStart", RMS_Utils.serializeNumericMap(spec.pendingServiceClockStart))
        xmlFile:setValue(key .. "#pendingServiceClockTarget", RMS_Utils.serializeNumericMap(spec.pendingServiceClockTarget))
        xmlFile:setValue(key .. "#systemsState", RMS_Utils.serializeSystemsState(spec.systems))
        xmlFile:setValue(key .. "#partWear", RMS_Utils.serializeNumericMap(spec.partWear))
        xmlFile:setValue(key .. "#partAbuse", RMS_Utils.serializeNumericMap(spec.partAbuse))
        xmlFile:setValue(key .. "#pickupAirTime", RMS_Utils.serializeNumericMap(spec.pickupAirTime))
        xmlFile:setValue(key .. "#factorStats", RMS_Utils.serializeNumericMap(flattenFactorStats(spec.factorStats)))
        xmlFile:setValue(key .. "#ptoEngagementCount", spec.ptoEngagementCount or 0)
        xmlFile:setValue(key .. "#ptoEngagementSequence", spec.ptoEngagementSequence or 0)
        xmlFile:setValue(key .. "#pendingOverhaulPartStart", RMS_Utils.serializeNumericMap(spec.pendingOverhaulPartStart))
        xmlFile:setValue(key .. "#pendingOverhaulPartTarget", RMS_Utils.serializeNumericMap(spec.pendingOverhaulPartTarget))

        RMS_Drivetrain.saveToXMLFile(self, xmlFile, key)
        xmlFile:setValue(key .. "#tripStartKilometers", spec.tripStartKilometers)

        for index, entry in ipairs(spec.maintenanceLog or {}) do
            local entryKey = string.format("%s.maintenanceLog.entry(%d)", key, index - 1)
            writeLogFields(xmlFile, entryKey, entry, LOG_ENTRY_XML)
            if entry.conditionData then
                writeLogFields(xmlFile, entryKey .. ".conditionData", entry.conditionData, LOG_CONDITION_XML)
            end
        end
    end
end

local SYSTEM_KEYS = { "engine", "transmission", "hydraulics", "cooling", "electrical", "chassis", "fuel", "pto", "harvest" }

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
    self.spec_RealisticMechanicalSystems.partAbuse = {}
    self.spec_RealisticMechanicalSystems.pickupAirTime = {}
    self.spec_RealisticMechanicalSystems.pickupUncovered = {}
    self.spec_RealisticMechanicalSystems.aerationWhining = {}
    self.spec_RealisticMechanicalSystems.warrantyVoided = false
    self.spec_RealisticMechanicalSystems.remapMotor = 0
    self.spec_RealisticMechanicalSystems.remapAge = 0
    self.spec_RealisticMechanicalSystems.remapByDealer = false
    self.spec_RealisticMechanicalSystems.conditionLevel = self.spec_RealisticMechanicalSystems.baseConditionLevel

    local currentOperatingTime = self.getOperatingTime ~= nil and self:getOperatingTime() or self.operatingTime or 0
    local existingRealOperatingTime = tonumber(self.spec_RealisticMechanicalSystems.realOperatingTime) or 0
    self.spec_RealisticMechanicalSystems.realOperatingTime = math.max(existingRealOperatingTime, currentOperatingTime)

    -- every system new, the harvest one off until a harvester enables it
    local systems = {}
    for _, systemKey in ipairs(SYSTEM_KEYS) do
        systems[systemKey] = { name = RealisticMechanicalSystems.SYSTEMS[string.upper(systemKey)], condition = 1.0,
            enabled = systemKey ~= "harvest" }
    end
    self.spec_RealisticMechanicalSystems.systems = systems
    self.spec_RealisticMechanicalSystems.factorStats = createEmptyFactorStats(self.spec_RealisticMechanicalSystems.systems)
    ensureFactorStats(self.spec_RealisticMechanicalSystems)

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
    self.spec_RealisticMechanicalSystems.fluidLeakLossDebt = {}
    self.spec_RealisticMechanicalSystems.fluidCapacityVersion = nil
    self.spec_RealisticMechanicalSystems.fluidCapacitySource = nil
    self.spec_RealisticMechanicalSystems.pendingFluidRequirements = {}
    self.spec_RealisticMechanicalSystems.coolantLeakRate = 0
    self.spec_RealisticMechanicalSystems.transmissionOilLeakRate = 0
    self.spec_RealisticMechanicalSystems.hydraulicFluidLeakRate = 0

    self.spec_RealisticMechanicalSystems.extraConditionWear = 0
    self.spec_RealisticMechanicalSystems.extraServiceWear = 0
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
    self.spec_RealisticMechanicalSystems.parkBrakeDrag = 0
    self.spec_RealisticMechanicalSystems.externalPowerConnection = nil

    self.spec_RealisticMechanicalSystems.engineTemperature = -99
    self.spec_RealisticMechanicalSystems.rawEngineTemperature = -99
    self.spec_RealisticMechanicalSystems._smoothedMotorLoad = 0
    self.spec_RealisticMechanicalSystems._netDynamicMotorLoad = 0
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
    self.spec_RealisticMechanicalSystems.transmissionThermostatHealth = 1.0
    self.spec_RealisticMechanicalSystems.transmissionThermostatStuckedPosition = nil
    self.spec_RealisticMechanicalSystems.overloadLevel = 0
    self.spec_RealisticMechanicalSystems.aiWorkerOverload = 0
    self.spec_RealisticMechanicalSystems.aiWorkerSpeedLimit = nil

    self.spec_RealisticMechanicalSystems.systemWearNow = {}
    self.spec_RealisticMechanicalSystems.systemWearRateNow = {}
    self.spec_RealisticMechanicalSystems.radiatorCloggingRate = 0
    self.spec_RealisticMechanicalSystems.airFilterCloggingRate = 0
    self.spec_RealisticMechanicalSystems.isRaisingDust = false
    -- heat flows of the last thermal step
    self.spec_RealisticMechanicalSystems.engineHeatBalance = {}
    self.spec_RealisticMechanicalSystems.transmissionHeatBalance = {}

    self.spec_RealisticMechanicalSystems.isUnderRoof = true
    self.spec_RealisticMechanicalSystems.roofRaycastHit = false
    self.spec_RealisticMechanicalSystems.roofRaycastResult = nil
    self.spec_RealisticMechanicalSystems.roofLastRaycastTime = nil
    self.spec_RealisticMechanicalSystems.roofWasStationary = false
    self.spec_RealisticMechanicalSystems.dynamicMotorLoad = 0
    self.spec_RealisticMechanicalSystems.activeDraftMaxForce = 0
    self.spec_RealisticMechanicalSystems.activeDraftEffectiveForceCap = 0
    self.spec_RealisticMechanicalSystems.isCranking = false
    self.spec_RealisticMechanicalSystems.wheelSlipIntensity = 0
    self.spec_RealisticMechanicalSystems._wheelSlipPreviousSample = 0
    self.spec_RealisticMechanicalSystems._wheelSlipOlderSample = 0
    self.spec_RealisticMechanicalSystems.wheelSlipTutorialTimer = 0
    self.spec_RealisticMechanicalSystems.luggingTutorialTimer = 0
    self.spec_RealisticMechanicalSystems.vibrationTutorialTimer = 0
    self.spec_RealisticMechanicalSystems.terrainImpactTutorialTimer = 0
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
    self.spec_RealisticMechanicalSystems.ptoEngagementSequence = 0
    self.spec_RealisticMechanicalSystems.ptoEngagementDamage = 0
    self.spec_RealisticMechanicalSystems.isPtoEngagementShock = false
    self.spec_RealisticMechanicalSystems.ptoLastRpmShare = 0
    self.spec_RealisticMechanicalSystems.isPtoImplementRaised = false
    self.spec_RealisticMechanicalSystems.ptoShockSequence = 0
    self.spec_RealisticMechanicalSystems.ptoTutorialObservedShockSequence = 0
    self.spec_RealisticMechanicalSystems.ptoRaisedTutorialTimer = 0
    self.spec_RealisticMechanicalSystems.ptoRaisedTooLong = false
    self.spec_RealisticMechanicalSystems.ptoPreviousActiveLinks = {}
    self.spec_RealisticMechanicalSystems.ptoTutorialObservedSequence = 0
    self.spec_RealisticMechanicalSystems.chassisVibState = {
        prevSuspension = {},
        smoothed = 0,
        raw = 0,
        signal = 0,
        isWearing = false
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
        totalMass = 0,
        hpTrailerMassRatio = 1000,
        hpGrossMassRatio = 1000,
        isBraking = false,
        isBrakingByAxis = false
    }
    self.spec_RealisticMechanicalSystems.fuelState = {
        level = 0,
        currentUsageRatio = 0,
        temperature = 0,
        idleTimer = 0,
        wetStackingLevel = 0,
        particulateFilterLevel = 0,
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

---Breakdown ids saved comma separated
local function splitSavedIds(text)
    local ids = {}
    for id in string.gmatch(text or "", "[^,]+") do
        table.insert(ids, id)
    end
    return ids
end

local function loadSavedState(self, xmlFile, key, vehicleKey, currentOperatingTime)
    local spec = self.spec_RealisticMechanicalSystems
    spec.serviceLevel = RealisticMechanicalSystems.sanitizeNumber(xmlFile:getValue(key .. "#service", spec.serviceLevel), spec.serviceLevel or 1.0, 0.001)
    spec.transmissionServiceLevel = RealisticMechanicalSystems.sanitizeNumber(
        xmlFile:getValue(key .. "#transmissionService", spec.transmissionServiceLevel), spec.transmissionServiceLevel, 0.001)
    spec.coolantServiceLevel = RealisticMechanicalSystems.sanitizeNumber(xmlFile:getValue(key .. "#coolantService", spec.coolantServiceLevel), spec.coolantServiceLevel, 0.001)
    spec.hydraulicServiceLevel = RealisticMechanicalSystems.sanitizeNumber(
        xmlFile:getValue(key .. "#hydraulicService", spec.hydraulicServiceLevel), spec.hydraulicServiceLevel, 0.001)
    spec.serviceCalendar = RMS_Utils.deserializeNumericMap(xmlFile:getValue(key .. "#serviceCalendar", ""))
    spec.warrantyPlan = xmlFile:getValue(key .. "#warrantyPlan", 1)
    spec.partWarranty = RMS_Utils.deserializeNumericMap(xmlFile:getValue(key .. "#partWarranty", ""))
    spec.usedPartWarranty = RMS_Utils.deserializeNumericMap(xmlFile:getValue(key .. "#usedPartWarranty", ""))
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
    spec.conditionLevel = RealisticMechanicalSystems.sanitizeNumber(xmlFile:getValue(key .. "#condition", spec.conditionLevel), spec.conditionLevel or 1.0, 0.001, 1.0)
    spec.currentState = xmlFile:getValue(key .. "#state", spec.currentState)
    spec.maintenanceTimer = RealisticMechanicalSystems.sanitizeNumber(xmlFile:getValue(key .. "#maintenanceTimer", spec.maintenanceTimer), spec.maintenanceTimer or 0, 0)
    spec.maintenanceTimerTime = RMS_Thermal.getWorldTimeMS()
    
    local loadedRealOperatingTime = nil
    if xmlFile:hasProperty(key .. "#realOperatingTime") then
        loadedRealOperatingTime = xmlFile:getValue(key .. "#realOperatingTime")
    end
    if loadedRealOperatingTime == nil and xmlFile.handle ~= nil then
        loadedRealOperatingTime = getXMLFloat(xmlFile.handle, key .. "#realOperatingTime")
    end
    if loadedRealOperatingTime ~= nil then
        spec.realOperatingTime = RealisticMechanicalSystems.sanitizeNumber(loadedRealOperatingTime, currentOperatingTime, 0)
    else
        spec.realOperatingTime = currentOperatingTime
    end

    local breakdownString = xmlFile:getValue(key .. "#breakdowns", "")
    if breakdownString and breakdownString ~= "" then
        spec.activeBreakdowns = {}
        for breakdownId, breakdown in pairs(RMS_Utils.deserializeBreakdowns(breakdownString)) do
            if self.isServer and breakdown.usedPartHours == nil then
                breakdown.usedPartHours = RealisticMechanicalSystems.drawUsedPartDonorHours(breakdownId)
            end
            spec.activeBreakdowns[breakdownId] = breakdown
        end
    else
        spec.activeBreakdowns = {}
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
    spec.radiatorClogging = math.max(xmlFile:getValue(key .. "#radiatorClogging", spec.radiatorClogging), 0)
    spec.airFilterClogging = math.max(xmlFile:getValue(key .. "#airFilterClogging", spec.airFilterClogging), 0)
    spec.airFilterResidue = math.clamp(xmlFile:getValue(key .. "#airFilterResidue", spec.airFilterResidue) or 0, 0, spec.airFilterClogging)
    for _, filter in ipairs(RMS_Consumables.FILTERS) do
        spec[filter.stateKey] = xmlFile:getValue(key .. "#" .. filter.stateKey, spec[filter.stateKey])
    end
    spec.engineOilLevel = math.clamp(xmlFile:getValue(key .. "#engineOilLevel", spec.engineOilLevel), 0.0, 1.0)
    spec.coolantLevel = math.clamp(xmlFile:getValue(key .. "#coolantLevel", spec.coolantLevel), 0.0, 1.0)
    spec.transmissionOilLevel = math.clamp(xmlFile:getValue(key .. "#transmissionOilLevel", spec.transmissionOilLevel), 0.0, 1.0)
    spec.hydraulicFluidLevel = math.clamp(xmlFile:getValue(key .. "#hydraulicFluidLevel", spec.hydraulicFluidLevel), 0.0, 1.0)
    spec.fluidCapacityVersion = xmlFile:getValue(key .. "#fluidCapacityVersion")
    spec.fluidCapacitySource = xmlFile:getValue(key .. "#fluidCapacitySource", "")
    spec.fluidCapacities = {
        engineOil = math.max(xmlFile:getValue(key .. "#engineOilCapacity", 0) or 0, 0),
        coolant = math.max(xmlFile:getValue(key .. "#coolantCapacity", 0) or 0, 0),
        transmissionOil = math.max(xmlFile:getValue(key .. "#transmissionOilCapacity", 0) or 0, 0),
        hydraulicFluid = math.max(xmlFile:getValue(key .. "#hydraulicFluidCapacity", 0) or 0, 0)
    }
    spec.fluidCompatibility = {
        engineOil = math.clamp(xmlFile:getValue(key .. "#engineOilCompatibility", 1) or 1, 0, 1),
        coolant = math.clamp(xmlFile:getValue(key .. "#coolantCompatibility", 1) or 1, 0, 1),
        transmissionOil = math.clamp(xmlFile:getValue(key .. "#transmissionOilCompatibility", 1) or 1, 0, 1),
        hydraulicFluid = math.clamp(xmlFile:getValue(key .. "#hydraulicFluidCompatibility", 1) or 1, 0, 1)
    }
    spec.fluidLeakLossDebt = RMS_Fluids.deserializeLeakDebt(xmlFile:getValue(key .. "#fluidLeakLossDebt", ""))
    spec.pendingFluidRequirements = RMS_Fluids.deserializeServiceRequirements(xmlFile:getValue(key .. "#pendingFluidRequirements", ""))
    spec.fuelState.wetStackingLevel = RealisticMechanicalSystems.sanitizeNumber(xmlFile:getValue(key .. "#wetStackingLevel", spec.fuelState.wetStackingLevel), 0, 0, 1)
    spec.fuelState.particulateFilterLevel = RealisticMechanicalSystems.sanitizeNumber(xmlFile:getValue(key .. "#particulateFilterLevel", 0), 0, 0,
        RMS_Config.EXHAUST.PARTICULATE_FILTER.SERVICE_LEVEL)
    spec.scrInducementHours = RealisticMechanicalSystems.sanitizeNumber(xmlFile:getValue(key .. "#scrInducementHours", 0), 0, 0)
    spec.fuelState.isParticulateFilterOverloaded = xmlFile:getValue(key .. "#particulateFilterOverloaded", false)
    RMS_Greasing.deserialize(self, xmlFile:getValue(key .. "#greasing"))
    spec.thermostatState = RealisticMechanicalSystems.sanitizeNumber(xmlFile:getValue(key .. "#thermostatState", spec.thermostatState), spec.thermostatState or 0, 0.0, 1.0)
    spec.transmissionThermostatState = RealisticMechanicalSystems.sanitizeNumber(
        xmlFile:getValue(key .. "#transmissionThermostatState", spec.transmissionThermostatState),
        spec.transmissionThermostatState or 0,
        0.0,
        1.0
    )
    spec.ptoEngagementCount = math.floor(math.max(xmlFile:getValue(key .. "#ptoEngagementCount", spec.ptoEngagementCount) or 0, 0))
    spec.ptoEngagementSequence = math.floor(math.max(xmlFile:getValue(key .. "#ptoEngagementSequence", spec.ptoEngagementSequence) or 0, 0))
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
    local loadedWorkshopType = xmlFile:getValue(key .. "#workshopType", "")
    if loadedWorkshopType ~= nil and loadedWorkshopType ~= "" then
        spec.workshopType = loadedWorkshopType
    end
    spec.pendingServicePrice = RMS_Utils.decodeOptionalFloat(xmlFile:getValue(key .. "#pendingServicePrice", spec.pendingServicePrice))
    spec.pendingServiceInvoice = RMS_Utils.deserializeInvoice(xmlFile:getValue(key .. "#pendingServiceInvoice"))
    spec.pendingSelectedBreakdowns = splitSavedIds(xmlFile:getValue(key .. "#pendingSelectedBreakdowns", ""))
    spec.pendingInspectionQueue = splitSavedIds(xmlFile:getValue(key .. "#pendingInspectionQueue", ""))
    spec.pendingRepairQueue = splitSavedIds(xmlFile:getValue(key .. "#pendingRepairQueue", ""))

    spec.pendingProgressStepIndex = xmlFile:getValue(key .. "#pendingProgressStepIndex", spec.pendingProgressStepIndex)
    spec.pendingProgressTotalTime = xmlFile:getValue(key .. "#pendingProgressTotalTime", spec.pendingProgressTotalTime)
    spec.pendingProgressElapsedTime = xmlFile:getValue(key .. "#pendingProgressElapsedTime", spec.pendingProgressElapsedTime)
    spec.pendingServiceClockStart = RMS_Utils.deserializeNumericMap(xmlFile:getValue(key .. "#pendingServiceClockStart", ""))
    spec.pendingServiceClockTarget = RMS_Utils.deserializeNumericMap(xmlFile:getValue(key .. "#pendingServiceClockTarget", ""))
    spec.pendingOverhaulPartStart = RMS_Utils.deserializeNumericMap(xmlFile:getValue(key .. "#pendingOverhaulPartStart", ""))
    spec.pendingOverhaulPartTarget = RMS_Utils.deserializeNumericMap(xmlFile:getValue(key .. "#pendingOverhaulPartTarget", ""))
    spec.partWear = RMS_Utils.deserializeNumericMap(xmlFile:getValue(key .. "#partWear", ""))
    spec.partAbuse = RMS_Utils.deserializeNumericMap(xmlFile:getValue(key .. "#partAbuse", ""))
    spec.pickupAirTime = RMS_Utils.deserializeNumericMap(xmlFile:getValue(key .. "#pickupAirTime", ""))
    local loadedFactorStatsFlat = RMS_Utils.deserializeNumericMap(xmlFile:getValue(key .. "#factorStats", ""))

    local loadedSystemsStateRaw = RMS_Utils.deserializeSystemsState(xmlFile:getValue(key .. "#systemsState", ""))
    local loadedSystemsState = {}
    for loadedKey, loadedData in pairs(loadedSystemsStateRaw) do
        loadedSystemsState[string.lower(tostring(loadedKey))] = loadedData
    end
    local hasSerializedSystemsState = next(loadedSystemsState) ~= nil

    if spec.systems == nil then
        spec.systems = {}
    end
    for systemKey, systemData in pairs(spec.systems) do
        if type(systemData) ~= "table" then
            systemData = {
                condition = tonumber(systemData) or 1.0,
                enabled = true
            }
            spec.systems[systemKey] = systemData
        end

        local loadedData = loadedSystemsState[string.lower(tostring(systemKey))]
        if loadedData ~= nil then
            systemData.condition = math.clamp(tonumber(loadedData.condition) or systemData.condition or 1.0, 0.001, 1.0)
            systemData.enabled = RMS_Utils.normalizeBoolValue(loadedData.enabled, systemData.enabled ~= false)
        else
            if not hasSerializedSystemsState and spec.conditionLevel ~= nil then
                systemData.condition = math.clamp(tonumber(spec.conditionLevel) or systemData.condition or 1.0, 0.001, 1.0)
            else
                systemData.condition = math.clamp(tonumber(systemData.condition) or 1.0, 0.001, 1.0)
            end
            systemData.enabled = RMS_Utils.normalizeBoolValue(systemData.enabled, true)
        end

        systemData.name = RMS_Utils.getSystemNameByKey(RealisticMechanicalSystems.SYSTEMS, systemKey)
    end
    ensureFactorStats(spec)
    applyFlattenedFactorStats(spec, loadedFactorStatsFlat)
    ensureFactorStats(spec)

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

    -- A save without these values starts the vehicle at rest
    local defaults = {
        serviceLevel = spec.baseServiceLevel, conditionLevel = spec.baseConditionLevel, maintenanceTimer = 0,
        currentState = RealisticMechanicalSystems.STATUS.READY,
        pendingSelectedBreakdowns = {}, pendingInspectionQueue = {}, pendingRepairQueue = {},
        pendingProgressStepIndex = 0, pendingProgressTotalTime = 0, pendingProgressElapsedTime = 0,
        pendingOverhaulPartStart = {}, pendingOverhaulPartTarget = {}
    }
    for field, value in pairs(defaults) do
        if spec[field] == nil then
            spec[field] = value
        end
    end
    self:updateConditionLevel()
end

function RealisticMechanicalSystems:onPostLoad(savegame)
    local spec = self.spec_RealisticMechanicalSystems
    local currentOperatingTime = self.getOperatingTime ~= nil and self:getOperatingTime() or self.operatingTime or 0
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

    if (spec.realOperatingTime == nil or spec.realOperatingTime <= 0) and currentOperatingTime > 0 then
        spec.realOperatingTime = currentOperatingTime
    end

    spec.isUnderRoof = self:isUnderRoof()

    spec.fieldInspection = spec.fieldInspection or {
        isActive = false,
        elapsedTime = 0,
        duration = RMS_Config.FIELD_CARE.VISUAL_INSPECTION_DURATION
    }

    local xmlSoundFile = loadXMLFile("rmsSounds", RealisticMechanicalSystems.modDirectory .. "sounds/rms_sounds.xml")
    if spec.samples == nil then
        spec.samples = {}
    end
    
    if xmlSoundFile ~= nil then
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
            spec.samples.starterIntro =soundManager:loadSampleFromXML(xmlSoundFile, "sounds", name .. "Intro", modDir, root, 1, AudioGroup.VEHICLE, i3d)
            spec.samples.starter = soundManager:loadSampleFromXML(xmlSoundFile, "sounds", name, modDir, root, 0, AudioGroup.VEHICLE, i3d)
            spec.samples.starterCatch = soundManager:loadSampleFromXML(xmlSoundFile, "sounds", name .. "Catch", modDir, root, 1, AudioGroup.VEHICLE, i3d)
        end
        delete(xmlSoundFile)
    else
        log_dbg("ERROR: RealisticMechanicalSystems - Could not load rms_sounds.xml")
    end

    RMS_Thermal.initializeEngineTemperature(self)
    spec.rawTransmissionTemperature = spec.transmissionTemperature

    spec.isElectricVehicle = getIsElectricVehicle(self)
    spec.isDieselVehicle = RMS_Preheat.isDieselVehicle(self)
    spec.hydraulicsMoveAlphaCache = {}
    spec.hydraulicsLiftRatioCache = {}

    local function resetIsMovingRecursive(vehicleObj, visited)
        if vehicleObj == nil or visited[vehicleObj] then
            return
        end
        visited[vehicleObj] = true

        if vehicleObj.spec_attacherJoints ~= nil then
            if vehicleObj.spec_attacherJoints.attacherJoints ~= nil then
                for _, jointDesc in pairs(vehicleObj.spec_attacherJoints.attacherJoints) do
                    if jointDesc ~= nil then
                        jointDesc.isMoving = false
                    end
                end
            end

            if vehicleObj.spec_attacherJoints.attachedImplements ~= nil then
                for _, implementData in pairs(vehicleObj.spec_attacherJoints.attachedImplements) do
                    if implementData ~= nil and implementData.object ~= nil then
                        resetIsMovingRecursive(implementData.object, visited)
                    end
                end
            end
        end
    end

    -- the systems the machine carries: a harvester drives its organs, no PTO
    local capacities = RMS_Fluids.resolveCapacities(self)
    local isHarvester = RMS_Drivetrain.getHarvestKind(self) ~= nil
    spec.systems.hydraulics.enabled = RMS_Utils.hasHydraulicCapability(self) and capacities.hydraulicFluid > 0
    spec.systems.pto.enabled = not isHarvester and RMS_Utils.hasPtoOutputCapability(self)
    spec.systems.harvest.enabled = isHarvester
    RealisticMechanicalSystems.buildSystemParts(self)
    RMS_Fluids.initializeVehicle(self, false)
    RealisticMechanicalSystems.getServiceClocks(self)
    if RMS_Thermal.getHasSeparateHydraulicCircuit(spec) then
        spec.rawHydraulicTemperature = RealisticMechanicalSystems.sanitizeNumber(spec.rawHydraulicTemperature, spec.rawTransmissionTemperature)
        spec.hydraulicTemperature = spec.rawHydraulicTemperature
    else
        spec.rawHydraulicTemperature = nil
        spec.hydraulicTemperature = nil
    end
    -- Restart runtime clocks at the current mission time.
    spec._thermalEngineWorldTime, spec._thermalOilWorldTime, spec._thermalBatteryWorldTime = nil, nil, nil
    spec._thermalEngineAmbient, spec._thermalOilAmbient, spec._thermalBatteryAmbient = nil, nil, nil
    if spec.isElectricVehicle then
        RMS_ElectricDrive.initBatteryCapacity(self)
    end
    local isRoadVehicle = RMS_Drivetrain.getIsRoadVehicleCategory(self)
    RMS_Greasing.initialize(self)
    spec.isVehicleNeedBlowOut = not isRoadVehicle
    resetIsMovingRecursive(self, {})

    -- What loading set counts as sent
    RealisticMechanicalSystems.storeSyncBaseline(self)
    spec.ptoTutorialObservedSequence = spec.ptoEngagementSequence
    spec.ptoTutorialObservedShockSequence = spec.ptoShockSequence

    RMS_Electrical.initializeVehicle(self)

    self:recalculateAndApplyEffects(true)
end

local SALE_STATE_KEY = "vehicles.vehicle(0)"

---Writes the RMS state of a vehicle to a string
function RealisticMechanicalSystems.saveStateToMemory(vehicle)
    local xmlFile = XMLFile.create("rmsSaleState", "", "vehicles", Vehicle.xmlSchemaSavegame)
    RealisticMechanicalSystems.saveToXMLFile(vehicle, xmlFile, SALE_STATE_KEY .. ".RealisticMechanicalSystems", {})
    local state = saveXMLFileToMemory(xmlFile.handle)
    xmlFile:delete()
    return state
end

---Gives a bought used offer the RMS state of the machine a player sold
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

function RealisticMechanicalSystems:onDelete()
    local spec = self.spec_RealisticMechanicalSystems

    if self.isClient then
        RMS_Exhaust.reset(self)
    end

    if spec and spec.samples then
        g_soundManager:deleteSamples(spec.samples)
    end

    if RMS_Main and RMS_Main.vehicles and self.uniqueId and RMS_Main.vehicles[self.uniqueId] then
        if RMS_Main.previousKey == self.uniqueId then
            RMS_Main.previousKey = nil
        end
        RMS_Main.vehicles[self.uniqueId] = nil
        RMS_Main.numVehicles = RMS_Main.numVehicles - 1
    end
end
