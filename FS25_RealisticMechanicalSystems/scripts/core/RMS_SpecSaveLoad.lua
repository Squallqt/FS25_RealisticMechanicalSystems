-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---Vehicle savegame persistence.

local log_dbg = RMS_Utils.createLogger("[RMS_SPEC]")
local getIsElectricVehicle = RMS_Utils.getIsElectricVehicle
local ensureFactorStats = RealisticMechanicalSystems.ensureFactorStats
local refreshExclusionState = RealisticMechanicalSystems.refreshExclusionState
local getSyncOperatingTime = RealisticMechanicalSystems.getSyncOperatingTime
local captureSystemsSync = RealisticMechanicalSystems.captureSystemsSync

---Builds a zeroed wear statistics entry for every system
local function createEmptyFactorStats(systems)
    local result = {}
    if type(systems) ~= "table" then
        return result
    end

    for systemKey, _ in pairs(systems) do
        result[systemKey] = {
            total = 0,
            _prevStress = 0,
            _avgStress = 0,
            operatingHours = -1
        }
    end

    return result
end

---Flattens the factor statistics into system.stat keys for the savegame
local function flattenFactorStats(factorStats)
    local flat = {}
    if type(factorStats) ~= "table" then
        return flat
    end

    for systemKey, stats in pairs(factorStats) do
        if type(stats) == "table" then
            for statKey, statValue in pairs(stats) do
                local numericValue = tonumber(statValue)
                if numericValue ~= nil then
                    flat[string.format("%s.%s", tostring(systemKey), tostring(statKey))] = numericValue
                end
            end
        end
    end

    return flat
end

---Rebuilds the factor statistics from the flattened savegame map
local function applyFlattenedFactorStats(spec, flattenedMap)
    if spec == nil then
        return
    end

    if type(spec.factorStats) ~= "table" then
        spec.factorStats = {}
    end

    if type(flattenedMap) ~= "table" then
        return
    end

    for flatKey, value in pairs(flattenedMap) do
        local systemKey, statKey = string.match(tostring(flatKey), "([^%.]+)%.(.+)")
        local numericValue = tonumber(value)
        if systemKey ~= nil and statKey ~= nil and numericValue ~= nil then
            if type(spec.factorStats[systemKey]) ~= "table" then
                spec.factorStats[systemKey] = {}
            end
            spec.factorStats[systemKey][statKey] = numericValue
        end
    end
end

---Tells whether the vehicle is an auxiliary machine
local function getIsAuxiliaryMachine(xmlFile)
    return not xmlFile:getValue("vehicle.enterable#isTabbable", true)
end

---Tells whether the vehicle is a machine towed with its own engine
local function getIsTowedMachine(vehicle)
    return vehicle.getInputAttacherJoints ~= nil and #vehicle:getInputAttacherJoints() > 0
end

---Tells whether RMS tracks a store item once bought
-- @param XMLFile xmlFile vehicle file of the store item
-- @param string? customEnvironment mod of the store item
-- @return boolean isTracked true when RMS tracks the machine by default
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
-- @param boolean isExcluded true to exclude the vehicle
-- @param Connection? connection player connection, nil for the local player
-- @return boolean canSet true when the player may change the flag
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


---Called on saving
-- @param XMLFile xmlFile XMLFile instance
-- @param string key xml key
-- @param table usedModNames used mod names
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
        local currentOperatingTime = self.getOperatingTime ~= nil and self:getOperatingTime() or self.operatingTime or 0
        local realOperatingTime = spec.realOperatingTime
        if (realOperatingTime == nil or realOperatingTime <= 0) and currentOperatingTime > 0 then
            realOperatingTime = currentOperatingTime
            spec.realOperatingTime = realOperatingTime
        end
        xmlFile:setValue(key .. "#service", spec.serviceLevel or 1.0)
        xmlFile:setValue(key .. "#transmissionService", spec.transmissionServiceLevel)
        xmlFile:setValue(key .. "#coolantService", spec.coolantServiceLevel)
        xmlFile:setValue(key .. "#hydraulicService", spec.hydraulicServiceLevel)
        xmlFile:setValue(key .. "#serviceCalendar", RMS_Utils.serializeNumericMap(spec.serviceCalendar))
        xmlFile:setValue(key .. "#warrantyPlan", spec.warrantyPlan)
        xmlFile:setValue(key .. "#partWarranty", RMS_Utils.serializeNumericMap(spec.partWarranty))
        xmlFile:setValue(key .. "#usedPartWarranty", RMS_Utils.serializeNumericMap(spec.usedPartWarranty))
        xmlFile:setValue(key .. "#condition", spec.conditionLevel or 1.0)
        xmlFile:setValue(key .. "#realOperatingTime", realOperatingTime or currentOperatingTime)
        if xmlFile.handle ~= nil then
            setXMLFloat(xmlFile.handle, key .. "#realOperatingTime", tonumber(realOperatingTime or currentOperatingTime) or 0)
        end
        local breakdownString = RMS_Utils.serializeBreakdowns(spec.activeBreakdowns)
        xmlFile:setValue(key .. "#breakdowns", breakdownString)
        xmlFile:setValue(key .. "#state", spec.currentState or RealisticMechanicalSystems.STATUS.READY)
        xmlFile:setValue(key .. "#plannedState", spec.plannedState or RealisticMechanicalSystems.STATUS.READY)
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
        xmlFile:setValue(key .. "#lubricationLevel", math.clamp(spec.lubricationLevel or 1.0, 0.0, 1.0))
        xmlFile:setValue(key .. "#lubricationUsedThisPeriod", spec.lubricationUsedThisPeriod == true)
        xmlFile:setValue(key .. "#thermostatState", RealisticMechanicalSystems.sanitizeNumber(spec.thermostatState, 0.0, 0.0, 1.0))
        xmlFile:setValue(key .. "#transmissionThermostatState", RealisticMechanicalSystems.sanitizeNumber(spec.transmissionThermostatState, 0.0, 0.0, 1.0))
        xmlFile:setValue(key .. "#serviceOptionOne", spec.serviceOptionOne or "")
        xmlFile:setValue(key .. "#serviceOptionTwo", spec.serviceOptionTwo or "")
        xmlFile:setValue(key .. "#serviceOptionThree", spec.serviceOptionThree or false)
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
        xmlFile:setValue(key .. "#factorStats", RMS_Utils.serializeNumericMap(flattenFactorStats(spec.factorStats)))
        xmlFile:setValue(key .. "#ptoEngagementCount", spec.ptoEngagementCount or 0)
        xmlFile:setValue(key .. "#ptoEngagementSequence", spec.ptoEngagementSequence or 0)
        xmlFile:setValue(key .. "#pendingOverhaulPartStart", RMS_Utils.serializeNumericMap(spec.pendingOverhaulPartStart))
        xmlFile:setValue(key .. "#pendingOverhaulPartTarget", RMS_Utils.serializeNumericMap(spec.pendingOverhaulPartTarget))

        RMS_Drivetrain.saveToXMLFile(self, xmlFile, key)
        xmlFile:setValue(key .. "#tripStartKilometers", spec.tripStartKilometers)

        if spec.maintenanceLog and #spec.maintenanceLog > 0 then
            for i, entry in ipairs(spec.maintenanceLog) do
                local entryKey = string.format("%s.maintenanceLog.entry(%d)", key, i - 1)
                
                xmlFile:setValue(entryKey .. "#id", entry.id or 0)
                xmlFile:setValue(entryKey .. "#type", entry.type or "")
                xmlFile:setValue(entryKey .. "#price", entry.price or 0)
                xmlFile:setValue(entryKey .. "#date", RMS_Utils.serializeDate(entry.date)) 
                xmlFile:setValue(entryKey .. "#location", entry.location or "UNKNOWN")
                xmlFile:setValue(entryKey .. "#optionOne", entry.optionOne or "NONE")
                xmlFile:setValue(entryKey .. "#optionTwo", entry.optionTwo or "NONE")
                xmlFile:setValue(entryKey .. "#optionThree", entry.optionThree or false)
                xmlFile:setValue(entryKey .. "#isVisible", tostring(RMS_Utils.normalizeBoolValue(entry.isVisible, true)))
                xmlFile:setValue(entryKey .. "#isCompleted", RMS_Utils.normalizeBoolValue(entry.isCompleted, true))
                if entry.invoice ~= nil then
                    xmlFile:setValue(entryKey .. "#invoice", RMS_Utils.serializeInvoice(entry.invoice))
                end

                if entry.conditionData then
                    local condKey = entryKey .. ".conditionData"
                    xmlFile:setValue(condKey .. "#year", entry.conditionData.year or 0)
                    xmlFile:setValue(condKey .. "#operatingHours", entry.conditionData.operatingHours or 0)
                    if entry.conditionData.odometerKilometers ~= nil then
                        xmlFile:setValue(condKey .. "#odometerKilometers", entry.conditionData.odometerKilometers)
                    end
                    xmlFile:setValue(condKey .. "#age", entry.conditionData.age or 0)
                    xmlFile:setValue(condKey .. "#condition", entry.conditionData.condition or 1)
                    xmlFile:setValue(condKey .. "#service", entry.conditionData.service or 1)
                    xmlFile:setValue(condKey .. "#reliability", entry.conditionData.reliability or 1)
                    xmlFile:setValue(condKey .. "#systems", RMS_Utils.serializeSystemsState(RMS_Utils.createSystemsSnapshot(entry.conditionData.systems)))
                    xmlFile:setValue(condKey .. "#partWear", RMS_Utils.serializeNumericMap(entry.conditionData.partWear))
                    xmlFile:setValue(condKey .. "#batterySoc", entry.conditionData.batterySoc or 1)
                    if entry.conditionData.wearExcess ~= nil then
                        xmlFile:setValue(condKey .. "#wearExcess", entry.conditionData.wearExcess)
                        xmlFile:setValue(condKey .. "#wearCauses", RMS_Utils.serializeWearCauses(entry.conditionData.wearCauses))
                    end

                    if entry.conditionData.activeBreakdowns then
                        xmlFile:setValue(condKey .. "#activeBreakdowns", RMS_Utils.serializeBreakdowns(entry.conditionData.activeBreakdowns))
                    end
                    
                    if entry.conditionData.selectedBreakdowns and #entry.conditionData.selectedBreakdowns > 0 then
                        xmlFile:setValue(condKey .. "#selectedBreakdowns", table.concat(entry.conditionData.selectedBreakdowns, ","))
                    end
                    
                    if entry.conditionData.activeEffects then
                        xmlFile:setValue(condKey .. "#activeEffects", RMS_Utils.serializeEffectSnapshot(entry.conditionData.activeEffects))
                    end
                    
                    if entry.conditionData.activeIndicators then
                        local indKeys = {}
                        for indId, _ in pairs(entry.conditionData.activeIndicators) do 
                            table.insert(indKeys, tostring(indId)) 
                        end
                        xmlFile:setValue(condKey .. "#activeIndicators", table.concat(indKeys, ","))
                    end
                end
            end
        end
        
    end
end

---
-- @param table savegame savegame
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
    self.spec_RealisticMechanicalSystems.conditionLevel = self.spec_RealisticMechanicalSystems.baseConditionLevel

    local currentOperatingTime = self.getOperatingTime ~= nil and self:getOperatingTime() or self.operatingTime or 0
    local existingRealOperatingTime = tonumber(self.spec_RealisticMechanicalSystems.realOperatingTime) or 0
    self.spec_RealisticMechanicalSystems.realOperatingTime = math.max(existingRealOperatingTime, currentOperatingTime)

    self.spec_RealisticMechanicalSystems.systems = {
        engine = { name = RealisticMechanicalSystems.SYSTEMS.ENGINE, condition = 1.0, enabled = true },
        transmission = { name = RealisticMechanicalSystems.SYSTEMS.TRANSMISSION, condition = 1.0, enabled = true },
        hydraulics = { name = RealisticMechanicalSystems.SYSTEMS.HYDRAULICS, condition = 1.0, enabled = true },
        cooling = { name = RealisticMechanicalSystems.SYSTEMS.COOLING, condition = 1.0, enabled = true },
        electrical = { name = RealisticMechanicalSystems.SYSTEMS.ELECTRICAL, condition = 1.0, enabled = true },
        chassis = { name = RealisticMechanicalSystems.SYSTEMS.CHASSIS, condition = 1.0, enabled = true },
        fuel = { name = RealisticMechanicalSystems.SYSTEMS.FUEL, condition = 1.0, enabled = true },
        pto = { name = RealisticMechanicalSystems.SYSTEMS.PTO, condition = 1.0, enabled = true }
    }
    self.spec_RealisticMechanicalSystems.factorStats = createEmptyFactorStats(self.spec_RealisticMechanicalSystems.systems)
    ensureFactorStats(self.spec_RealisticMechanicalSystems, self)

    -- engine consumables
    self.spec_RealisticMechanicalSystems.airFilterClogging = 0.0
    self.spec_RealisticMechanicalSystems.airFilterResidue = 0.0
    for _, filter in ipairs(RMS_Consumables.FILTERS) do
        self.spec_RealisticMechanicalSystems[filter.stateKey] = 0.0
    end

    -- fluid levels
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

    self.spec_RealisticMechanicalSystems.maintenanceLog = {}
    
    self.spec_RealisticMechanicalSystems._fuelUsageRaw  = 0
    self.spec_RealisticMechanicalSystems.lastBlinkingWarningMessage = ""
    self.spec_RealisticMechanicalSystems.blinkingWarningTimer = 0
    self.spec_RealisticMechanicalSystems.coldEngineExposureMs = 0
    self.spec_RealisticMechanicalSystems.coldEngineWarningShown = false
    self.spec_RealisticMechanicalSystems.pendingSideNotifications = {}

    self.spec_RealisticMechanicalSystems.startButtonActionEvents = {}
    self.spec_RealisticMechanicalSystems.startButtonDown = false
    self.spec_RealisticMechanicalSystems.startButtonHeld = false
    self.spec_RealisticMechanicalSystems.startButtonUp = false
    RMS_Preheat.initSpec(self)
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
    self.spec_RealisticMechanicalSystems.lubricationUsedThisPeriod = true
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
    self.spec_RealisticMechanicalSystems.ptoLastRpmShare = 0
    self.spec_RealisticMechanicalSystems.isPtoImplementRaised = false
    self.spec_RealisticMechanicalSystems.ptoShockSequence = 0
    self.spec_RealisticMechanicalSystems.ptoTutorialObservedShockSequence = 0
    self.spec_RealisticMechanicalSystems.ptoRaisedTutorialTimer = 0
    self.spec_RealisticMechanicalSystems.ptoRaisedTooLong = false
    self.spec_RealisticMechanicalSystems.ptoPreviousActiveLinks = {}
    self.spec_RealisticMechanicalSystems.ptoTutorialObservedSequence = 0
    self.spec_RealisticMechanicalSystems.ptoEngagementAttempt = false
    self.spec_RealisticMechanicalSystems.ptoEngagementAttemptBlocked = nil
    self.spec_RealisticMechanicalSystems.ptoEngagementAttemptWarningShown = nil
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
    self.spec_RealisticMechanicalSystems.plannedState = RealisticMechanicalSystems.STATUS.READY
    self.spec_RealisticMechanicalSystems.workshopType = RealisticMechanicalSystems.WORKSHOP.DEALER
    self.spec_RealisticMechanicalSystems.serviceOptionOne = nil
    self.spec_RealisticMechanicalSystems.serviceOptionTwo = nil
    self.spec_RealisticMechanicalSystems.serviceOptionThree = false
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

---Reads the saved RMS state of a vehicle
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
    local savedAge = xmlFile:getValue(vehicleKey .. "#age", 0)
    for _, clock in ipairs(RealisticMechanicalSystems.SERVICE_CLOCKS) do
        if spec.serviceCalendar[clock.key] == nil then
            spec.serviceCalendar[clock.key] = savedAge
        end
    end
    spec.conditionLevel = RealisticMechanicalSystems.sanitizeNumber(xmlFile:getValue(key .. "#condition", spec.conditionLevel), spec.conditionLevel or 1.0, 0.001, 1.0)
    spec.currentState = xmlFile:getValue(key .. "#state", spec.currentState)
    spec.plannedState = xmlFile:getValue(key .. "#plannedState", spec.plannedState)
    spec.maintenanceTimer = RealisticMechanicalSystems.sanitizeNumber(xmlFile:getValue(key .. "#maintenanceTimer", spec.maintenanceTimer), spec.maintenanceTimer or 0, 0)
    
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

    -- Load Breakdowns
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

    -- Load Simple Variables
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
    spec.lubricationLevel = math.clamp(xmlFile:getValue(key .. "#lubricationLevel", spec.lubricationLevel), 0.0, 1.0)
    spec.lubricationUsedThisPeriod = xmlFile:getValue(key .. "#lubricationUsedThisPeriod", true)
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
    if spec.serviceOptionOne == "" then spec.serviceOptionOne = nil end
    if spec.serviceOptionTwo == "" then spec.serviceOptionTwo = nil end
    spec.serviceOptionThree = xmlFile:getValue(key .. "#serviceOptionThree", spec.serviceOptionThree)
    RMS_Drivetrain.loadFromSavegame(self, xmlFile, key)
    spec.tripStartKilometers = xmlFile:getValue(key .. "#tripStartKilometers", spec.tripStartKilometers)
    local loadedWorkshopType = xmlFile:getValue(key .. "#workshopType", "")
    if loadedWorkshopType ~= nil and loadedWorkshopType ~= "" then
        spec.workshopType = loadedWorkshopType
    end
    spec.pendingServicePrice = RMS_Utils.decodeOptionalFloat(xmlFile:getValue(key .. "#pendingServicePrice", spec.pendingServicePrice))
    spec.pendingServiceInvoice = RMS_Utils.deserializeInvoice(xmlFile:getValue(key .. "#pendingServiceInvoice"))
    spec.pendingSelectedBreakdowns = {}
    local pendingSelBdStr = xmlFile:getValue(key .. "#pendingSelectedBreakdowns", "")
    if pendingSelBdStr ~= nil and pendingSelBdStr ~= "" then
        for item in string.gmatch(pendingSelBdStr, "([^,]+)") do
            table.insert(spec.pendingSelectedBreakdowns, item)
        end
    end
    spec.pendingInspectionQueue = {}
    local pendingInspectionQueueStr = xmlFile:getValue(key .. "#pendingInspectionQueue", "")
    if pendingInspectionQueueStr ~= nil and pendingInspectionQueueStr ~= "" then
        for item in string.gmatch(pendingInspectionQueueStr, "([^,]+)") do
            table.insert(spec.pendingInspectionQueue, item)
        end
    end

    spec.pendingRepairQueue = {}
    local pendingRepairQueueStr = xmlFile:getValue(key .. "#pendingRepairQueue", "")
    if pendingRepairQueueStr ~= nil and pendingRepairQueueStr ~= "" then
        for item in string.gmatch(pendingRepairQueueStr, "([^,]+)") do
            table.insert(spec.pendingRepairQueue, item)
        end
    end

    spec.pendingProgressStepIndex = xmlFile:getValue(key .. "#pendingProgressStepIndex", spec.pendingProgressStepIndex)
    spec.pendingProgressTotalTime = xmlFile:getValue(key .. "#pendingProgressTotalTime", spec.pendingProgressTotalTime)
    spec.pendingProgressElapsedTime = xmlFile:getValue(key .. "#pendingProgressElapsedTime", spec.pendingProgressElapsedTime)
    spec.pendingServiceClockStart = RMS_Utils.deserializeNumericMap(xmlFile:getValue(key .. "#pendingServiceClockStart", ""))
    spec.pendingServiceClockTarget = RMS_Utils.deserializeNumericMap(xmlFile:getValue(key .. "#pendingServiceClockTarget", ""))
    spec.pendingOverhaulPartStart = RMS_Utils.deserializeNumericMap(xmlFile:getValue(key .. "#pendingOverhaulPartStart", ""))
    spec.pendingOverhaulPartTarget = RMS_Utils.deserializeNumericMap(xmlFile:getValue(key .. "#pendingOverhaulPartTarget", ""))
    spec.partWear = RMS_Utils.deserializeNumericMap(xmlFile:getValue(key .. "#partWear", ""))
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
    ensureFactorStats(spec, self)
    applyFlattenedFactorStats(spec, loadedFactorStatsFlat)
    ensureFactorStats(spec, self)

    -- Load Maintenance Log
    spec.maintenanceLog = {}
    local i = 0
    while true do
        local entryKey = string.format("%s.maintenanceLog.entry(%d)", key, i)
        if not xmlFile:hasProperty(entryKey) then
            break
        end

        local entry = {
            id = xmlFile:getValue(entryKey .. "#id"),
            type = xmlFile:getValue(entryKey .. "#type"),
            price = xmlFile:getValue(entryKey .. "#price"),
            date = RMS_Utils.deserializeDate(xmlFile:getValue(entryKey .. "#date")),
            conditionData = {}
        }
        local condKey = entryKey .. ".conditionData"

        if xmlFile:hasProperty(condKey) then
            entry.location = xmlFile:getValue(entryKey .. "#location", "UNKNOWN")
            entry.optionOne = xmlFile:getValue(entryKey .. "#optionOne", "NONE")
            entry.optionTwo = xmlFile:getValue(entryKey .. "#optionTwo", "NONE")
            entry.optionThree = xmlFile:getValue(entryKey .. "#optionThree", false)
            entry.isVisible = RMS_Utils.normalizeBoolValue(xmlFile:getValue(entryKey .. "#isVisible", true), true)
            entry.isCompleted = RMS_Utils.normalizeBoolValue(xmlFile:getValue(entryKey .. "#isCompleted", true), true)
            entry.invoice = RMS_Utils.deserializeInvoice(xmlFile:getValue(entryKey .. "#invoice"))

            entry.conditionData.year = xmlFile:getValue(condKey .. "#year", 0)
            entry.conditionData.operatingHours = xmlFile:getValue(condKey .. "#operatingHours", 0)
            entry.conditionData.odometerKilometers = xmlFile:getValue(condKey .. "#odometerKilometers")
            entry.conditionData.age = xmlFile:getValue(condKey .. "#age", 0)
            entry.conditionData.condition = xmlFile:getValue(condKey .. "#condition", 1)
            entry.conditionData.service = xmlFile:getValue(condKey .. "#service", 1)
            entry.conditionData.reliability = xmlFile:getValue(condKey .. "#reliability", 1)
            entry.conditionData.systems = RMS_Utils.createSystemsSnapshot(RMS_Utils.deserializeSystemsState(xmlFile:getValue(condKey .. "#systems", "")))
            entry.conditionData.partWear = RMS_Utils.deserializeNumericMap(xmlFile:getValue(condKey .. "#partWear", ""))
            entry.conditionData.batterySoc = xmlFile:getValue(condKey .. "#batterySoc", 1)
            entry.conditionData.wearExcess = xmlFile:getValue(condKey .. "#wearExcess")
            entry.conditionData.wearCauses = RMS_Utils.deserializeWearCauses(xmlFile:getValue(condKey .. "#wearCauses", ""))

            local bdStr = xmlFile:getValue(condKey .. "#activeBreakdowns", "")
            entry.conditionData.activeBreakdowns = RMS_Utils.deserializeBreakdowns(bdStr) or {}

            local selBdStr = xmlFile:getValue(condKey .. "#selectedBreakdowns", "")
            entry.conditionData.selectedBreakdowns = RMS_Utils.parseCsvList(selBdStr)

            entry.conditionData.activeEffects = RMS_Utils.deserializeEffectSnapshot(xmlFile:getValue(condKey .. "#activeEffects", ""))

            entry.conditionData.activeIndicators = {}
            local indicatorIds = RMS_Utils.parseCsvList(xmlFile:getValue(condKey .. "#activeIndicators", ""))
            for _, indId in ipairs(indicatorIds) do
                entry.conditionData.activeIndicators[indId] = true
            end

            table.insert(spec.maintenanceLog, entry)
        end

        i = i + 1
    end

    -- Fill defaults
    if spec.serviceLevel == nil then spec.serviceLevel = spec.baseServiceLevel end
    if spec.conditionLevel == nil then spec.conditionLevel = spec.baseConditionLevel end
    if spec.maintenanceTimer == nil then spec.maintenanceTimer = 0 end
    if spec.currentState == nil then spec.currentState = RealisticMechanicalSystems.STATUS.READY end
    if spec.plannedState == nil then spec.plannedState = RealisticMechanicalSystems.STATUS.READY end
    if spec.serviceOptionThree == nil then spec.serviceOptionThree = false end
    if spec.pendingSelectedBreakdowns == nil then spec.pendingSelectedBreakdowns = {} end
    if spec.pendingInspectionQueue == nil then spec.pendingInspectionQueue = {} end
    if spec.pendingRepairQueue == nil then spec.pendingRepairQueue = {} end
    if spec.pendingProgressStepIndex == nil then spec.pendingProgressStepIndex = 0 end
    if spec.pendingProgressTotalTime == nil then spec.pendingProgressTotalTime = 0 end
    if spec.pendingProgressElapsedTime == nil then spec.pendingProgressElapsedTime = 0 end
    if spec.pendingOverhaulPartStart == nil then spec.pendingOverhaulPartStart = {} end
    if spec.pendingOverhaulPartTarget == nil then spec.pendingOverhaulPartTarget = {} end
    self:updateConditionLevel()
end

---
-- @param table savegame savegame
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

    -- Sounds Loading
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
        delete(xmlSoundFile)
    else
        log_dbg("ERROR: RealisticMechanicalSystems - Could not load rms_sounds.xml")
    end

    RMS_Thermal.registerDashboardLiveCompatibility(self)
    RMS_Thermal.initializeEngineTemperature(self)
    spec.rawTransmissionTemperature = spec.transmissionTemperature

    spec.isElectricVehicle = getIsElectricVehicle(self)
    spec.isDieselVehicle = RMS_Preheat.isDieselVehicle(self)
    spec.hydraulicsMoveAlphaCache = {}
    spec.hydraulicsLiftRatioCache = {}

    ---
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

    ---
    local function enableOrDisableSystems(vehicle)
        local spec = vehicle.spec_RealisticMechanicalSystems
        local resolvedCapacities = RMS_Fluids.resolveCapacities(vehicle)
        for _, systemData in pairs(spec.systems) do
            if systemData.name == RealisticMechanicalSystems.SYSTEMS.HYDRAULICS then
                systemData.enabled = RMS_Utils.hasHydraulicCapability(vehicle)
                    and resolvedCapacities.hydraulicFluid > 0
            elseif systemData.name == RealisticMechanicalSystems.SYSTEMS.PTO then
                systemData.enabled = RMS_Utils.hasPtoOutputCapability(vehicle)
            end
        end
    end

    enableOrDisableSystems(self)
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
    spec.isVehicleNeedLubricate = not isRoadVehicle
    spec.isVehicleNeedBlowOut = not isRoadVehicle
    resetIsMovingRecursive(self, {})

    -- dirty-flag comparison: [1] state
    spec._lastSyncState_currentState = spec.currentState
    spec._lastSyncState_plannedState = spec.plannedState
    spec._lastSyncState_maintenanceTimer = spec.maintenanceTimer
    -- [2] service context
    spec._lastSyncServiceContext_optionOne = spec.serviceOptionOne
    spec._lastSyncServiceContext_optionTwo = spec.serviceOptionTwo
    spec._lastSyncServiceContext_optionThree = spec.serviceOptionThree
    spec._lastSyncServiceContext_workshopType = spec.workshopType
    -- [3] telemetry
    spec._lastSyncTelemetry_operatingTime = getSyncOperatingTime(self)
    spec._lastSyncTelemetry_realOperatingTime = spec.realOperatingTime
    spec._lastSyncTelemetry_fuelUsageRaw = spec._fuelUsageRaw
    spec._lastSyncTelemetry_dynamicMotorLoad = tonumber(spec.dynamicMotorLoad) or 0
    spec._lastSyncTelemetry_liftedMass = spec.liftedMass
    -- [4] thermal
    spec._lastSyncThermal_rawEngineTemperature = spec.rawEngineTemperature
    spec._lastSyncThermal_rawTransmissionTemperature = spec.rawTransmissionTemperature
    spec._lastSyncThermal_rawHydraulicTemperature = spec.rawHydraulicTemperature
    spec._lastSyncThermal_tractionBatteryTempC = spec.tractionBatteryTempC
    spec._lastSyncThermal_hasHydraulicTemperature = RMS_Thermal.getHasSeparateHydraulicCircuit(spec) and spec.rawHydraulicTemperature ~= nil
    spec._lastSyncThermal_hasTractionBatteryTemperature = spec.isElectricVehicle == true and spec.tractionBatteryTempC ~= nil
    spec._lastSyncThermal_thermostatState = spec.thermostatState
    spec._lastSyncThermal_transmissionThermostatState = spec.transmissionThermostatState
    -- [5] electrical
    spec._lastSyncElectrical_batterySoc = spec.batterySoc
    spec._lastSyncElectrical_batteryIsolated = spec.batteryIsolated
    spec._lastSyncElectrical_systemVoltage = spec.systemVoltageV
    spec._lastSyncElectrical_preheatState = spec.preheatState
    spec._lastSyncElectrical_preheatLampTestActive = spec.preheatLampTestActive
    spec._lastSyncElectrical_preheatWasRequired = spec.preheatWasRequired
    spec._lastSyncElectrical_preheatColdStartFaultSeverity = spec.preheatColdStartFaultSeverity
    -- [6] field care
    RealisticMechanicalSystems.storeFieldcareSyncState(self, spec, RMS_Fluids.serializeLeakDebt(spec.fluidLeakLossDebt))
    -- [7] wear
    spec._lastSyncWear_serviceLevel = spec.serviceLevel
    spec._lastSyncWear_transmissionServiceLevel = spec.transmissionServiceLevel
    spec._lastSyncWear_coolantServiceLevel = spec.coolantServiceLevel
    spec._lastSyncWear_hydraulicServiceLevel = spec.hydraulicServiceLevel
    spec._lastSyncWear_serviceCalendar = RMS_Utils.serializeNumericMap(spec.serviceCalendar)
    spec._lastSyncWear_partWarranty = RMS_Utils.serializeNumericMap(spec.partWarranty)
    spec._lastSyncWear_usedPartWarranty = RMS_Utils.serializeNumericMap(spec.usedPartWarranty)
    spec._lastSyncWear_warrantyPlan = spec.warrantyPlan
    spec._lastSyncWear_conditionLevel = spec.conditionLevel
    spec._lastSyncWear_ptoEngagementSequence = spec.ptoEngagementSequence
    spec._lastSyncWear_ptoShockSequence = spec.ptoShockSequence
    spec._lastSyncWear_ptoRaisedTooLong = spec.ptoRaisedTooLong
    spec.ptoTutorialObservedSequence = spec.ptoEngagementSequence
    spec.ptoTutorialObservedShockSequence = spec.ptoShockSequence
    captureSystemsSync(spec)
    -- [8] breakdowns
    spec._lastSyncBreakdowns_serialized = RMS_Utils.serializeBreakdowns(spec.activeBreakdowns or {})
    -- [9] service
    spec._lastSyncServiceProgress_elapsed = spec.pendingProgressElapsedTime
    spec._lastSyncServiceProgress_step = spec.pendingProgressStepIndex
    spec._lastSyncServiceProgress_total = spec.pendingProgressTotalTime
    -- [10] tutorial data
    spec._lastSyncTutorial_idleTimer = spec.fuelState.idleTimer
    spec._lastSyncTutorial_fuelLevel = spec.fuelState.level

    RMS_Electrical.initializeVehicle(self)

    self:recalculateAndApplyEffects(true)
end

local SALE_STATE_KEY = "vehicles.vehicle(0)"

---Writes the RMS state of a vehicle to a string
-- @param table vehicle vehicle
-- @return string state
function RealisticMechanicalSystems.saveStateToMemory(vehicle)
    local xmlFile = XMLFile.create("rmsSaleState", "", "vehicles", Vehicle.xmlSchemaSavegame)
    RealisticMechanicalSystems.saveToXMLFile(vehicle, xmlFile, SALE_STATE_KEY .. ".RealisticMechanicalSystems", {})
    local state = saveXMLFileToMemory(xmlFile.handle)
    xmlFile:delete()
    return state
end

---Gives a bought used offer the RMS state of the machine a player sold
-- @param table saleItem used offer
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

---
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
