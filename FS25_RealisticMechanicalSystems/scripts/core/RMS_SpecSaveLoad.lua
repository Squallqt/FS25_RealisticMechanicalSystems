-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---Savegame persistence of the vehicle spec, and the classification decided at load time

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
            stress = 0,
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
    -- a machine under a procedure stays in until it is done
    if spec == nil or (isExcluded and vehicle:isUnderService()) then
        return false
    end

    if connection == nil then
        return g_currentMission:getIsServer() or g_currentMission.isMasterUser == true
    end
    return g_currentMission.userManager:getUserByConnection(connection):getIsMasterUser()
end

---Tells whether the vehicle sits in the trucks store category
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
    -- a machine RMS never took in saves nothing
    if spec ~= nil and not spec.isNewToRMS then
        -- only the current mission clock is caught up, a stopped vehicle may miss updates
        if self.isServer and not spec.isExcludedVehicle and self.getMotor ~= nil and self:getMotor() ~= nil
           and self.getIsMotorStarted ~= nil and not self:getIsMotorStarted()
           and self.updateThermalSystems ~= nil and RMS_Thermal.getWorldTimeMS() ~= nil then
            self:updateThermalSystems(1, true, true)
        end
        xmlFile:setValue(key .. "#saveVersion", RealisticMechanicalSystems.SAVE_VERSION)
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
        -- the world clock of the save never advances it through time the game was closed
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
        xmlFile:setValue(key .. "#fuelFilterClogging", spec.fuelFilterClogging)
        xmlFile:setValue(key .. "#hydraulicFilterClogging", spec.hydraulicFilterClogging)
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
        xmlFile:setValue(key .. "#pendingPreventiveSystemStressStart", RMS_Utils.serializeNumericMap(spec.pendingPreventiveSystemStressStart))
        xmlFile:setValue(key .. "#pendingPreventiveSystemStressTarget", RMS_Utils.serializeNumericMap(spec.pendingPreventiveSystemStressTarget))
        xmlFile:setValue(key .. "#systemsState", RMS_Utils.serializeSystemsState(spec.systems))
        xmlFile:setValue(key .. "#factorStats", RMS_Utils.serializeNumericMap(flattenFactorStats(spec.factorStats)))
        xmlFile:setValue(key .. "#ptoEngagementCount", spec.ptoEngagementCount or 0)
        xmlFile:setValue(key .. "#ptoEngagementSequence", spec.ptoEngagementSequence or 0)
        xmlFile:setValue(key .. "#pendingOverhaulSystemStart", RMS_Utils.serializeNumericMap(spec.pendingOverhaulSystemStart))
        xmlFile:setValue(key .. "#pendingOverhaulSystemTarget", RMS_Utils.serializeNumericMap(spec.pendingOverhaulSystemTarget))
        xmlFile:setValue(key .. "#pendingOverhaulSystemStressStart", RMS_Utils.serializeNumericMap(spec.pendingOverhaulSystemStressStart))
        xmlFile:setValue(key .. "#pendingOverhaulSystemStressTarget", RMS_Utils.serializeNumericMap(spec.pendingOverhaulSystemStressTarget))
        xmlFile:setValue(key .. "#pendingRepairSystemStressStart", RMS_Utils.serializeNumericMap(spec.pendingRepairSystemStressStart))
        xmlFile:setValue(key .. "#pendingRepairSystemStressTarget", RMS_Utils.serializeNumericMap(spec.pendingRepairSystemStressTarget))
        xmlFile:setValue(key .. "#pendingRepairSystemStressStartRatio", RMS_Utils.serializeNumericMap(spec.pendingRepairSystemStressStartRatio))

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
    self.spec_RealisticMechanicalSystems.loadedSaveVersion = RealisticMechanicalSystems.SAVE_VERSION
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
    self.spec_RealisticMechanicalSystems.conditionLevel = self.spec_RealisticMechanicalSystems.baseConditionLevel

    local currentOperatingTime = self.getOperatingTime ~= nil and self:getOperatingTime() or self.operatingTime or 0
    local existingRealOperatingTime = tonumber(self.spec_RealisticMechanicalSystems.realOperatingTime) or 0
    self.spec_RealisticMechanicalSystems.realOperatingTime = math.max(existingRealOperatingTime, currentOperatingTime)
    self.spec_RealisticMechanicalSystems._prevConditionLevel = 0

    self.spec_RealisticMechanicalSystems.systems = {
        engine = { name = RealisticMechanicalSystems.SYSTEMS.ENGINE, condition = 1.0, stress = 0.0, enabled = true },
        transmission = { name = RealisticMechanicalSystems.SYSTEMS.TRANSMISSION, condition = 1.0, stress = 0.0, enabled = true },
        hydraulics = { name = RealisticMechanicalSystems.SYSTEMS.HYDRAULICS, condition = 1.0, stress = 0.0, enabled = true },
        cooling = { name = RealisticMechanicalSystems.SYSTEMS.COOLING, condition = 1.0, stress = 0.0, enabled = true },
        electrical = { name = RealisticMechanicalSystems.SYSTEMS.ELECTRICAL, condition = 1.0, stress = 0.0, enabled = true },
        chassis = { name = RealisticMechanicalSystems.SYSTEMS.CHASSIS, condition = 1.0, stress = 0.0, enabled = true },
        fuel = { name = RealisticMechanicalSystems.SYSTEMS.FUEL, condition = 1.0, stress = 0.0, enabled = true },
        pto = { name = RealisticMechanicalSystems.SYSTEMS.PTO, condition = 1.0, stress = 0.0, enabled = true }
    }
    self.spec_RealisticMechanicalSystems.factorStats = createEmptyFactorStats(self.spec_RealisticMechanicalSystems.systems)
    ensureFactorStats(self.spec_RealisticMechanicalSystems, self)

    -- engine consumables
    self.spec_RealisticMechanicalSystems.airFilterClogging = 0.0
    self.spec_RealisticMechanicalSystems.airFilterResidue = 0.0
    self.spec_RealisticMechanicalSystems.fuelFilterClogging = 0.0
    self.spec_RealisticMechanicalSystems.hydraulicFilterClogging = 0.0

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
    self.spec_RealisticMechanicalSystems.year = RMS_VehicleYears.DEFAULT_YEAR
    self.spec_RealisticMechanicalSystems.yearIsKnown = false

    self.spec_RealisticMechanicalSystems.activeBreakdowns = {}
    self.spec_RealisticMechanicalSystems.activeEffects = {}
    self.spec_RealisticMechanicalSystems.activeIndicators = {}
    self.spec_RealisticMechanicalSystems.activeFunctions = {}
    self.spec_RealisticMechanicalSystems.originalFunctions = {}
    self.spec_RealisticMechanicalSystems.dynamicBreakdowns = {}

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
    self.spec_RealisticMechanicalSystems.externalPowerConnection = nil

    self.spec_RealisticMechanicalSystems.engineTemperature = -99
    self.spec_RealisticMechanicalSystems.rawEngineTemperature = -99
    self.spec_RealisticMechanicalSystems._netTargetEngineTemp = nil
    self.spec_RealisticMechanicalSystems._smoothedMotorLoad = 0
    self.spec_RealisticMechanicalSystems._netDynamicMotorLoad = 0
    self.spec_RealisticMechanicalSystems.radiatorHealth = 1.0
    self.spec_RealisticMechanicalSystems.fanClutchHealth = 1.0
    self.spec_RealisticMechanicalSystems.thermostatState = 0.0
    self.spec_RealisticMechanicalSystems.thermostatHealth = 1.0
    self.spec_RealisticMechanicalSystems.thermostatStuckedPosition = nil
    self.spec_RealisticMechanicalSystems.engTermPID = {
        integral = 0,
        lastError = 0
    }

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
    self.spec_RealisticMechanicalSystems._netTargetTransmissionTemp = nil
    self.spec_RealisticMechanicalSystems.transmissionThermostatState = 0.0
    self.spec_RealisticMechanicalSystems.transmissionThermostatHealth = 1.0
    self.spec_RealisticMechanicalSystems.transmissionThermostatStuckedPosition = nil
    self.spec_RealisticMechanicalSystems.overloadLevel = 0
    self.spec_RealisticMechanicalSystems.aiWorkerOverload = 0
    self.spec_RealisticMechanicalSystems.aiWorkerSpeedLimit = nil

    self.spec_RealisticMechanicalSystems.debugData = {
        service = {
            totalWearRate = 0
        },
        airFilter = {
            baseWetnessFactor = 1.0,
            isOnField = false,
            hasDust = false,
            hasDebris = false,
            totalMultiplier = 0.0
        },
        drivetrain = {
        },
        exhaust = {
            opacity = 0,
            vapour = 0
        },

        engine = {
            totalWearRate = 0, 
            expiredServiceFactor = 0,
            motorLoadFactor = 0, 
            coldMotorFactor = 0, 
            hotMotorFactor = 0,
            breakdownProbability = 0,
            critBreakdownProbability = 0
        },

        transmission = {
            totalWearRate = 0, 
            expiredServiceFactor = 0,
            pullOverloadFactor = 0,
            heavyTrailerFactor = 0,
            heavyTrailerMassRatio = 0,
            wheelSlipFactor = 0,
            luggingFactor = 0,
            breakdownProbability = 0,
            critBreakdownProbability = 0,
            pullOverloadTimer = 0
        },

        hydraulics = {
            totalWearRate = 0,
            expiredServiceFactor = 0,
            heavyLiftFactor = 0,
            heavyLiftMassRatio = 0,
            vibFactor = 0,
            vibSignal = 0,
            operatingFactor = 0,
            coldOilFactor = 0,
            hotOilFactor = 0,
            breakdownProbability = 0,
            critBreakdownProbability = 0
        },

        pto = {
            totalWearRate = 0,
            isPtoActive = false,
            expiredServiceFactor = 0,
            ptoLoadFactor = 0,
            ptoRaisedFactor = 0,
            ptoEngagementDamage = 0,
            ptoRpm = 0,
            ptoPower = 0,
            ptoUtilization = 0,
            ptoEngagementCount = 0,
            breakdownProbability = 0,
            critBreakdownProbability = 0
        },

        cooling = {
            totalWearRate = 0,
            expiredServiceFactor = 0,
            highCoolingFactor = 0,
            overheatFactor = 0,
            coldShockFactor = 0,
            breakdownProbability = 0,
            critBreakdownProbability = 0
        },

        electrical = {
            totalWearRate = 0,
            vibFactor = 0,
            vibSignal = 0,
            vibRaw = 0,
            lightsFactor = 0,
            crankingStressFactor = 0,
            overheatFactor = 0,
            breakdownProbability = 0,
            critBreakdownProbability = 0
        },

        chassis = {
            totalWearRate = 0,
            vibFactor = 0,
            vibSignal = 0,
            vibRaw = 0,
            impactCount = 0,
            impactSpeedLoss = 0,
            steerPlay = 0,
            steerPull = 0,
            steerLoadFactor = 0,
            steerLowSpeedFactor = 0,
            steerGroundFrictionCoeff = 0,
            steerTravelRate = 0,
            steerAxleLoadRatio = 0,
            brakeMassFactor = 0,
            brakeMassRatio = 0,
            breakdownProbability = 0,
            critBreakdownProbability = 0
        },

        fuel = {
            totalWearRate = 0,
            expiredServiceFactor = 0,
            lowFuelStarvationFactor = 0,
            coldFuelFactor = 0,
            idleDepositFactor = 0,
            highPressureFactor = 0,
            deepDischargeFactor = 0,
            highDrawFactor = 0,
            idleTimer = 0,
            fuelLevel = 0,
            fuelTemperature = 0,
            breakdownProbability = 0,
            critBreakdownProbability = 0
        },

        battery = {
        },

        radiator = {
            baseWetnessFactor = 1.0,
            isOnField = false,
            hasDust = false,
            hasDebris = false,
            totalMultiplier = 0.0
        },

        engineTemp = {
            totalHeat = 0, 
            totalCooling = 0, 
            radiatorCooling = 0, 
            speedCooling = 0, 
            convectionCooling = 0,
        },

        transmissionTemp = {
            totalHeat = 0,
            totalCooling = 0,
            coolerCooling = 0,
            speedCooling = 0,
            convectionCooling = 0,
            loadFactor = 0,
            extraTransmissionHeat = 0,
            idleHeat = 0,
            ptoHeat = 0,
            hydraulicHeat = 0
        },

        aiWorker = {
            overload = 0,
            speedLimit = 0
        }
    }

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
    self.spec_RealisticMechanicalSystems.isImplementOperating = false
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
        massRatio = 0,
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
        wetStackingLevel = 0
    }
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
    self.spec_RealisticMechanicalSystems.pendingPreventiveSystemStressStart = {}
    self.spec_RealisticMechanicalSystems.pendingPreventiveSystemStressTarget = {}
    self.spec_RealisticMechanicalSystems.pendingOverhaulSystemStart = {}
    self.spec_RealisticMechanicalSystems.pendingOverhaulSystemTarget = {}
    self.spec_RealisticMechanicalSystems.pendingOverhaulSystemStressStart = {}
    self.spec_RealisticMechanicalSystems.pendingOverhaulSystemStressTarget = {}
    self.spec_RealisticMechanicalSystems.pendingRepairSystemStressStart = {}
    self.spec_RealisticMechanicalSystems.pendingRepairSystemStressTarget = {}
    self.spec_RealisticMechanicalSystems.pendingRepairSystemStressStartRatio = {}


    if self.isServer then
        local spec = self.spec_RealisticMechanicalSystems
        spec.rmsDirtyFlag = self:getNextDirtyFlag()
        spec.rmsPendingByConnection = {}
    end
end

---
-- @param table savegame savegame
function RealisticMechanicalSystems:onPostLoad(savegame)
    local spec = self.spec_RealisticMechanicalSystems
    local currentOperatingTime = self.getOperatingTime ~= nil and self:getOperatingTime() or self.operatingTime or 0
    local savedKey = savegame ~= nil and RealisticMechanicalSystems.getSavegameKey(savegame) or nil

    -- RMS knows the vehicle once its own data sits in the save
    spec.isNewToRMS = savegame == nil or not savegame.xmlFile:hasProperty(savedKey)
    spec.isExcludedByRule = getIsAuxiliaryMachine(self.xmlFile) or getIsTowedMachine(self)
    spec.isExcludedByUser = nil
    if savegame ~= nil then
        spec.isExcludedByUser = savegame.xmlFile:getValue(savedKey .. "#userExclusion")
    end
    refreshExclusionState(spec)

    if spec ~= nil and savegame ~= nil then
        local key = savedKey
        spec.loadedSaveVersion = tonumber(savegame.xmlFile:getValue(key .. "#saveVersion")) or 0

        spec.serviceLevel = RealisticMechanicalSystems.sanitizeNumber(savegame.xmlFile:getValue(key .. "#service", spec.serviceLevel), spec.serviceLevel or 1.0, 0.001)
        spec.transmissionServiceLevel = RealisticMechanicalSystems.sanitizeNumber(
            savegame.xmlFile:getValue(key .. "#transmissionService", spec.transmissionServiceLevel), spec.transmissionServiceLevel, 0.001)
        spec.coolantServiceLevel = RealisticMechanicalSystems.sanitizeNumber(savegame.xmlFile:getValue(key .. "#coolantService", spec.coolantServiceLevel), spec.coolantServiceLevel, 0.001)
        spec.hydraulicServiceLevel = RealisticMechanicalSystems.sanitizeNumber(
            savegame.xmlFile:getValue(key .. "#hydraulicService", spec.transmissionServiceLevel), spec.transmissionServiceLevel, 0.001)
        spec.serviceCalendar = RMS_Utils.deserializeNumericMap(savegame.xmlFile:getValue(key .. "#serviceCalendar", ""))
        -- a clock with no saved date starts its months at the age of the vehicle
        local savedAge = savegame.xmlFile:getValue(savegame.key .. "#age", 0)
        for _, clock in ipairs(RealisticMechanicalSystems.SERVICE_CLOCKS) do
            if spec.serviceCalendar[clock.key] == nil then
                spec.serviceCalendar[clock.key] = savedAge
            end
        end
        spec.conditionLevel = RealisticMechanicalSystems.sanitizeNumber(savegame.xmlFile:getValue(key .. "#condition", spec.conditionLevel), spec.conditionLevel or 1.0, 0.001, 1.0)
        spec.currentState = RealisticMechanicalSystems.fromLegacyConstant(savegame.xmlFile:getValue(key .. "#state", spec.currentState))
        spec.plannedState = RealisticMechanicalSystems.fromLegacyConstant(savegame.xmlFile:getValue(key .. "#plannedState", spec.plannedState))
        spec.maintenanceTimer = RealisticMechanicalSystems.sanitizeNumber(savegame.xmlFile:getValue(key .. "#maintenanceTimer", spec.maintenanceTimer), spec.maintenanceTimer or 0, 0)
        
        local loadedRealOperatingTime = nil
        if savegame.xmlFile:hasProperty(key .. "#realOperatingTime") then
            loadedRealOperatingTime = savegame.xmlFile:getValue(key .. "#realOperatingTime")
        end
        if loadedRealOperatingTime == nil and savegame.xmlFile.handle ~= nil then
            loadedRealOperatingTime = getXMLFloat(savegame.xmlFile.handle, key .. "#realOperatingTime")
        end
        if loadedRealOperatingTime ~= nil then
            spec.realOperatingTime = RealisticMechanicalSystems.sanitizeNumber(loadedRealOperatingTime, currentOperatingTime, 0)
        else
            spec.realOperatingTime = currentOperatingTime
        end

        -- Load Breakdowns
        local breakdownString = savegame.xmlFile:getValue(key .. "#breakdowns", "")
        if breakdownString and breakdownString ~= "" then
            spec.activeBreakdowns = {}
            for breakdownId, breakdown in pairs(RMS_Utils.deserializeBreakdowns(breakdownString)) do
                spec.activeBreakdowns[RealisticMechanicalSystems.fromLegacyBreakdownId(breakdownId)] = breakdown
            end
        else
            spec.activeBreakdowns = {}
        end

        -- Load Simple Variables
        spec.engineTemperature = RealisticMechanicalSystems.sanitizeNumber(savegame.xmlFile:getValue(key .. "#engineTemperature", spec.engineTemperature), 20)
        spec.transmissionTemperature = RealisticMechanicalSystems.sanitizeNumber(
            savegame.xmlFile:getValue(key .. "#transmissionTemperature", spec.transmissionTemperature),
            spec.engineTemperature
        )
        spec.rawHydraulicTemperature = savegame.xmlFile:getValue(key .. "#hydraulicTemperature")
        -- the saved metadata is kept for diagnostics, never to catch up elapsed time
        spec.loadedThermalWorldTime = savegame.xmlFile:getValue(key .. "#thermalWorldTime")
        spec.loadedThermalAmbient = savegame.xmlFile:getValue(key .. "#thermalAmbient")
        spec.batterySoc = RealisticMechanicalSystems.sanitizeNumber(savegame.xmlFile:getValue(key .. "#batterySoc", spec.batterySoc), 1.0, 0, 1)
        spec.batteryIsolated = savegame.xmlFile:getValue(key .. "#batteryIsolated", spec.batteryIsolated)
        spec.tractionBatteryTempC = RealisticMechanicalSystems.sanitizeNumber(savegame.xmlFile:getValue(key .. "#tractionBatteryTempC", spec.tractionBatteryTempC), 20)
        spec.radiatorClogging = math.max(savegame.xmlFile:getValue(key .. "#radiatorClogging", spec.radiatorClogging), 0)
        local loadedAirFilterClogging = savegame.xmlFile:getValue(key .. "#airFilterClogging")
        if loadedAirFilterClogging == nil then
            loadedAirFilterClogging = savegame.xmlFile:getValue(key .. "#airIntakeClogging", spec.airFilterClogging)
        end
        spec.airFilterClogging = math.max(loadedAirFilterClogging, 0)
        spec.airFilterResidue = math.clamp(savegame.xmlFile:getValue(key .. "#airFilterResidue", spec.airFilterResidue) or 0, 0, spec.airFilterClogging)
        spec.fuelFilterClogging = savegame.xmlFile:getValue(key .. "#fuelFilterClogging", spec.fuelFilterClogging)
        spec.hydraulicFilterClogging = savegame.xmlFile:getValue(key .. "#hydraulicFilterClogging", spec.hydraulicFilterClogging)
        spec.engineOilLevel = math.clamp(savegame.xmlFile:getValue(key .. "#engineOilLevel", spec.engineOilLevel), 0.0, 1.0)
        spec.coolantLevel = math.clamp(savegame.xmlFile:getValue(key .. "#coolantLevel", spec.coolantLevel), 0.0, 1.0)
        spec.transmissionOilLevel = math.clamp(savegame.xmlFile:getValue(key .. "#transmissionOilLevel", spec.transmissionOilLevel), 0.0, 1.0)
        spec.hydraulicFluidLevel = math.clamp(savegame.xmlFile:getValue(key .. "#hydraulicFluidLevel", spec.hydraulicFluidLevel), 0.0, 1.0)
        spec.fluidCapacityVersion = savegame.xmlFile:getValue(key .. "#fluidCapacityVersion")
        spec.fluidCapacitySource = savegame.xmlFile:getValue(key .. "#fluidCapacitySource", "")
        spec.fluidCapacities = {
            engineOil = math.max(savegame.xmlFile:getValue(key .. "#engineOilCapacity", 0) or 0, 0),
            coolant = math.max(savegame.xmlFile:getValue(key .. "#coolantCapacity", 0) or 0, 0),
            transmissionOil = math.max(savegame.xmlFile:getValue(key .. "#transmissionOilCapacity", 0) or 0, 0),
            hydraulicFluid = math.max(savegame.xmlFile:getValue(key .. "#hydraulicFluidCapacity", 0) or 0, 0)
        }
        spec.fluidCompatibility = {
            engineOil = math.clamp(savegame.xmlFile:getValue(key .. "#engineOilCompatibility", 1) or 1, 0, 1),
            coolant = math.clamp(savegame.xmlFile:getValue(key .. "#coolantCompatibility", 1) or 1, 0, 1),
            transmissionOil = math.clamp(savegame.xmlFile:getValue(key .. "#transmissionOilCompatibility", 1) or 1, 0, 1),
            hydraulicFluid = math.clamp(savegame.xmlFile:getValue(key .. "#hydraulicFluidCompatibility", 1) or 1, 0, 1)
        }
        spec.fluidLeakLossDebt = RMS_Fluids.deserializeLeakDebt(savegame.xmlFile:getValue(key .. "#fluidLeakLossDebt", ""))
        spec.pendingFluidRequirements = RMS_Fluids.deserializeServiceRequirements(savegame.xmlFile:getValue(key .. "#pendingFluidRequirements", ""))
        spec.fuelState.wetStackingLevel = RealisticMechanicalSystems.sanitizeNumber(savegame.xmlFile:getValue(key .. "#wetStackingLevel", spec.fuelState.wetStackingLevel), 0, 0, 1)
        spec.lubricationLevel = math.clamp(savegame.xmlFile:getValue(key .. "#lubricationLevel", spec.lubricationLevel), 0.0, 1.0)
        spec.lubricationUsedThisPeriod = savegame.xmlFile:getValue(key .. "#lubricationUsedThisPeriod", true)
        spec.thermostatState = RealisticMechanicalSystems.sanitizeNumber(savegame.xmlFile:getValue(key .. "#thermostatState", spec.thermostatState), spec.thermostatState or 0, 0.0, 1.0)
        spec.transmissionThermostatState = RealisticMechanicalSystems.sanitizeNumber(
            savegame.xmlFile:getValue(key .. "#transmissionThermostatState", spec.transmissionThermostatState),
            spec.transmissionThermostatState or 0,
            0.0,
            1.0
        )
        spec.ptoEngagementCount = math.floor(math.max(savegame.xmlFile:getValue(key .. "#ptoEngagementCount", spec.ptoEngagementCount) or 0, 0))
        spec.ptoEngagementSequence = math.floor(math.max(savegame.xmlFile:getValue(key .. "#ptoEngagementSequence", spec.ptoEngagementSequence) or 0, 0))
        if spec.engTermPID ~= nil then
            spec.engTermPID.mechPos = spec.thermostatState
        end
        spec.serviceOptionOne = RealisticMechanicalSystems.fromLegacyConstant(savegame.xmlFile:getValue(key .. "#serviceOptionOne", spec.serviceOptionOne))
        spec.serviceOptionTwo = RealisticMechanicalSystems.fromLegacyConstant(savegame.xmlFile:getValue(key .. "#serviceOptionTwo", spec.serviceOptionTwo))
        if spec.serviceOptionOne == "" then spec.serviceOptionOne = nil end
        if spec.serviceOptionTwo == "" then spec.serviceOptionTwo = nil end
        spec.serviceOptionThree = savegame.xmlFile:getValue(key .. "#serviceOptionThree", spec.serviceOptionThree)
        RMS_Drivetrain.loadFromSavegame(self, savegame.xmlFile, key)
        spec.tripStartKilometers = savegame.xmlFile:getValue(key .. "#tripStartKilometers", spec.tripStartKilometers)
        local loadedWorkshopType = RealisticMechanicalSystems.fromLegacyConstant(savegame.xmlFile:getValue(key .. "#workshopType", ""))
        if loadedWorkshopType ~= nil and loadedWorkshopType ~= "" then
            spec.workshopType = loadedWorkshopType
        end
        spec.pendingServicePrice = RMS_Utils.decodeOptionalFloat(savegame.xmlFile:getValue(key .. "#pendingServicePrice", spec.pendingServicePrice))
        spec.pendingServiceInvoice = RMS_Utils.deserializeInvoice(savegame.xmlFile:getValue(key .. "#pendingServiceInvoice"))
        spec.pendingSelectedBreakdowns = {}
        local pendingSelBdStr = savegame.xmlFile:getValue(key .. "#pendingSelectedBreakdowns", "")
        if pendingSelBdStr ~= nil and pendingSelBdStr ~= "" then
            for item in string.gmatch(pendingSelBdStr, "([^,]+)") do
                table.insert(spec.pendingSelectedBreakdowns, item)
            end
        end
        spec.pendingInspectionQueue = {}
        local pendingInspectionQueueStr = savegame.xmlFile:getValue(key .. "#pendingInspectionQueue", "")
        if pendingInspectionQueueStr ~= nil and pendingInspectionQueueStr ~= "" then
            for item in string.gmatch(pendingInspectionQueueStr, "([^,]+)") do
                table.insert(spec.pendingInspectionQueue, item)
            end
        end

        spec.pendingRepairQueue = {}
        local pendingRepairQueueStr = savegame.xmlFile:getValue(key .. "#pendingRepairQueue", "")
        if pendingRepairQueueStr ~= nil and pendingRepairQueueStr ~= "" then
            for item in string.gmatch(pendingRepairQueueStr, "([^,]+)") do
                table.insert(spec.pendingRepairQueue, item)
            end
        end

        spec.pendingProgressStepIndex = savegame.xmlFile:getValue(key .. "#pendingProgressStepIndex", spec.pendingProgressStepIndex)
        spec.pendingProgressTotalTime = savegame.xmlFile:getValue(key .. "#pendingProgressTotalTime", spec.pendingProgressTotalTime)
        spec.pendingProgressElapsedTime = savegame.xmlFile:getValue(key .. "#pendingProgressElapsedTime", spec.pendingProgressElapsedTime)
        spec.pendingServiceClockStart = RMS_Utils.deserializeNumericMap(savegame.xmlFile:getValue(key .. "#pendingServiceClockStart", ""))
        spec.pendingServiceClockTarget = RMS_Utils.deserializeNumericMap(savegame.xmlFile:getValue(key .. "#pendingServiceClockTarget", ""))
        -- the former oil clock covered both sumps: keep the paid renewal of a running job
        if not savegame.xmlFile:hasProperty(key .. "#hydraulicService") then
            spec.pendingServiceClockStart.hydraulic = spec.pendingServiceClockStart.transmission
            spec.pendingServiceClockTarget.hydraulic = spec.pendingServiceClockTarget.transmission
        end
        if not savegame.xmlFile:hasProperty(key .. "#pendingServiceClockStart")
            and not savegame.xmlFile:hasProperty(key .. "#pendingServiceClockTarget") then
            if spec.currentState == RealisticMechanicalSystems.STATUS.MAINTENANCE then
                local legacyStart = RMS_Utils.decodeOptionalFloat(savegame.xmlFile:getValue(key .. "#pendingMaintenanceServiceStart"))
                local legacyTarget = RMS_Utils.decodeOptionalFloat(savegame.xmlFile:getValue(key .. "#pendingMaintenanceServiceTarget"))
                if legacyStart ~= nil and legacyTarget ~= nil then
                    spec.pendingServiceClockStart.engine = legacyStart
                    spec.pendingServiceClockTarget.engine = legacyTarget
                end
            elseif spec.currentState == RealisticMechanicalSystems.STATUS.OVERHAUL
                and spec.serviceOptionOne ~= RealisticMechanicalSystems.OVERHAUL_TYPES.PARTIAL then
                spec.pendingServiceClockStart.engine = spec.serviceLevel
                spec.pendingServiceClockTarget.engine = 1.0
            end
        end
        spec.pendingPreventiveSystemStressStart = RMS_Utils.deserializeNumericMap(savegame.xmlFile:getValue(key .. "#pendingPreventiveSystemStressStart", ""))
        spec.pendingPreventiveSystemStressTarget = RMS_Utils.deserializeNumericMap(savegame.xmlFile:getValue(key .. "#pendingPreventiveSystemStressTarget", ""))
        spec.pendingOverhaulSystemStart = RMS_Utils.deserializeNumericMap(savegame.xmlFile:getValue(key .. "#pendingOverhaulSystemStart", ""))
        spec.pendingOverhaulSystemTarget = RMS_Utils.deserializeNumericMap(savegame.xmlFile:getValue(key .. "#pendingOverhaulSystemTarget", ""))
        spec.pendingOverhaulSystemStressStart = RMS_Utils.deserializeNumericMap(savegame.xmlFile:getValue(key .. "#pendingOverhaulSystemStressStart", ""))
        spec.pendingOverhaulSystemStressTarget = RMS_Utils.deserializeNumericMap(savegame.xmlFile:getValue(key .. "#pendingOverhaulSystemStressTarget", ""))
        spec.pendingRepairSystemStressStart = RMS_Utils.deserializeNumericMap(savegame.xmlFile:getValue(key .. "#pendingRepairSystemStressStart", ""))
        spec.pendingRepairSystemStressTarget = RMS_Utils.deserializeNumericMap(savegame.xmlFile:getValue(key .. "#pendingRepairSystemStressTarget", ""))
        spec.pendingRepairSystemStressStartRatio = RMS_Utils.deserializeNumericMap(savegame.xmlFile:getValue(key .. "#pendingRepairSystemStressStartRatio", ""))
        local loadedFactorStatsFlat = RMS_Utils.deserializeNumericMap(savegame.xmlFile:getValue(key .. "#factorStats", ""))

        local loadedSystemsStateRaw = RMS_Utils.deserializeSystemsState(savegame.xmlFile:getValue(key .. "#systemsState", ""))
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
                    stress = 0.0,
                    enabled = true
                }
                spec.systems[systemKey] = systemData
            end

            local loadedData = loadedSystemsState[string.lower(tostring(systemKey))]
            if loadedData ~= nil then
                systemData.condition = math.clamp(tonumber(loadedData.condition) or systemData.condition or 1.0, 0.001, 1.0)
                systemData.stress = math.max(tonumber(loadedData.stress) or systemData.stress or 0.0, 0.0)
                systemData.enabled = RMS_Utils.normalizeBoolValue(loadedData.enabled, systemData.enabled ~= false)
            else
                if not hasSerializedSystemsState and spec.conditionLevel ~= nil then
                    systemData.condition = math.clamp(tonumber(spec.conditionLevel) or systemData.condition or 1.0, 0.001, 1.0)
                else
                    systemData.condition = math.clamp(tonumber(systemData.condition) or 1.0, 0.001, 1.0)
                end
                systemData.stress = math.max(tonumber(systemData.stress) or 0.0, 0.0)
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
            if not savegame.xmlFile:hasProperty(entryKey) then
                break
            end

            local entry = {
                id = savegame.xmlFile:getValue(entryKey .. "#id"),
                type = RealisticMechanicalSystems.fromLegacyConstant(savegame.xmlFile:getValue(entryKey .. "#type")),
                price = savegame.xmlFile:getValue(entryKey .. "#price"),
                date = RMS_Utils.deserializeDate(savegame.xmlFile:getValue(entryKey .. "#date")),
                conditionData = {}
            }
            local condKey = entryKey .. ".conditionData"

            if savegame.xmlFile:hasProperty(condKey) then
                entry.location = RealisticMechanicalSystems.fromLegacyConstant(savegame.xmlFile:getValue(entryKey .. "#location", "UNKNOWN"))
                entry.optionOne = RealisticMechanicalSystems.fromLegacyConstant(savegame.xmlFile:getValue(entryKey .. "#optionOne", "NONE"))
                entry.optionTwo = RealisticMechanicalSystems.fromLegacyConstant(savegame.xmlFile:getValue(entryKey .. "#optionTwo", "NONE"))
                entry.optionThree = savegame.xmlFile:getValue(entryKey .. "#optionThree", false)
                entry.isVisible = RMS_Utils.normalizeBoolValue(savegame.xmlFile:getValue(entryKey .. "#isVisible", true), true)
                entry.isCompleted = RMS_Utils.normalizeBoolValue(savegame.xmlFile:getValue(entryKey .. "#isCompleted", true), true)
                entry.invoice = RMS_Utils.deserializeInvoice(savegame.xmlFile:getValue(entryKey .. "#invoice"))

                entry.conditionData.year = savegame.xmlFile:getValue(condKey .. "#year", 0)
                entry.conditionData.operatingHours = savegame.xmlFile:getValue(condKey .. "#operatingHours", 0)
                entry.conditionData.odometerKilometers = savegame.xmlFile:getValue(condKey .. "#odometerKilometers")
                entry.conditionData.age = savegame.xmlFile:getValue(condKey .. "#age", 0)
                entry.conditionData.condition = savegame.xmlFile:getValue(condKey .. "#condition", 1)
                entry.conditionData.service = savegame.xmlFile:getValue(condKey .. "#service", 1)
                entry.conditionData.reliability = savegame.xmlFile:getValue(condKey .. "#reliability", 1)
                entry.conditionData.systems = RMS_Utils.createSystemsSnapshot(RMS_Utils.deserializeSystemsState(savegame.xmlFile:getValue(condKey .. "#systems", "")))
                entry.conditionData.batterySoc = savegame.xmlFile:getValue(condKey .. "#batterySoc", 1)
                entry.conditionData.wearExcess = savegame.xmlFile:getValue(condKey .. "#wearExcess")
                entry.conditionData.wearCauses = RMS_Utils.deserializeWearCauses(savegame.xmlFile:getValue(condKey .. "#wearCauses", ""))

                local bdStr = savegame.xmlFile:getValue(condKey .. "#activeBreakdowns", "")
                entry.conditionData.activeBreakdowns = RMS_Utils.deserializeBreakdowns(bdStr) or {}

                local selBdStr = savegame.xmlFile:getValue(condKey .. "#selectedBreakdowns", "")
                entry.conditionData.selectedBreakdowns = RMS_Utils.parseCsvList(selBdStr)

                entry.conditionData.activeEffects = RMS_Utils.deserializeEffectSnapshot(savegame.xmlFile:getValue(condKey .. "#activeEffects", ""))

                entry.conditionData.activeIndicators = {}
                local indicatorIds = RMS_Utils.parseCsvList(savegame.xmlFile:getValue(condKey .. "#activeIndicators", ""))
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
        if spec.pendingPreventiveSystemStressStart == nil then spec.pendingPreventiveSystemStressStart = {} end
        if spec.pendingPreventiveSystemStressTarget == nil then spec.pendingPreventiveSystemStressTarget = {} end
        if spec.pendingOverhaulSystemStart == nil then spec.pendingOverhaulSystemStart = {} end
        if spec.pendingOverhaulSystemTarget == nil then spec.pendingOverhaulSystemTarget = {} end
        if spec.pendingOverhaulSystemStressStart == nil then spec.pendingOverhaulSystemStressStart = {} end
        if spec.pendingOverhaulSystemStressTarget == nil then spec.pendingOverhaulSystemStressTarget = {} end
        if spec.pendingRepairSystemStressStart == nil then spec.pendingRepairSystemStressStart = {} end
        if spec.pendingRepairSystemStressTarget == nil then spec.pendingRepairSystemStressTarget = {} end
        if spec.pendingRepairSystemStressStartRatio == nil then spec.pendingRepairSystemStressStartRatio = {} end
        self:updateConditionLevel()
        RealisticMechanicalSystems.applySaveVersion(spec, spec.loadedSaveVersion)
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
        duration = RMS_Config.FIELD_CARE.VISUAL_INSPECTION_DURATION,
        startTime = 0,
        targetNode = nil,
        targetVehicle = nil
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
        
        spec.samples.starterCranking = soundManager:loadSampleFromXML(xmlSoundFile, "sounds", "starterCranking", modDir, root, 1, AudioGroup.VEHICLE, i3d, self)
        spec.samples.starterCrankingEnd = soundManager:loadSampleFromXML(xmlSoundFile, "sounds", "starterCrankingEnd", modDir, root, 1, AudioGroup.VEHICLE, i3d, self)
        spec.samples.alarm = soundManager:loadSampleFromXML(xmlSoundFile, "sounds", "alarm", modDir, root, 1, AudioGroup.VEHICLE, i3d, self)
        spec.samples.warning = soundManager:loadSampleFromXML(xmlSoundFile, "sounds", "warning", modDir, root, 1, AudioGroup.VEHICLE, i3d, self)
        spec.samples.transmissionShiftFailed1 = soundManager:loadSampleFromXML(xmlSoundFile, "sounds", "transmissionShiftFailed1", modDir, root, 1, AudioGroup.VEHICLE, i3d, self)
        spec.samples.transmissionShiftFailed2 = soundManager:loadSampleFromXML(xmlSoundFile, "sounds", "transmissionShiftFailed2", modDir, root, 1, AudioGroup.VEHICLE, i3d, self)
        spec.samples.transmissionShiftFailed3 = soundManager:loadSampleFromXML(xmlSoundFile, "sounds", "transmissionShiftFailed3", modDir, root, 1, AudioGroup.VEHICLE, i3d, self)
        spec.samples.brakes1 = soundManager:loadSampleFromXML(xmlSoundFile, "sounds", "brakes1", modDir, root, 1, AudioGroup.VEHICLE, i3d, self)
        spec.samples.brakes2 = soundManager:loadSampleFromXML(xmlSoundFile, "sounds", "brakes2", modDir, root, 1, AudioGroup.VEHICLE, i3d, self)
        spec.samples.brakes3 = soundManager:loadSampleFromXML(xmlSoundFile, "sounds", "brakes3", modDir, root, 1, AudioGroup.VEHICLE, i3d, self)
        spec.samples.turboWhistle = soundManager:loadSampleFromXML(xmlSoundFile, "sounds", "turboWhistle", modDir, root, 1, AudioGroup.VEHICLE, i3d, self)
        spec.samples.fanNoice = soundManager:loadSampleFromXML(xmlSoundFile, "sounds", "fanNoice", modDir, root, 1, AudioGroup.VEHICLE, i3d, self)
        spec.samples.wheelHubBearingNoise = soundManager:loadSampleFromXML(xmlSoundFile, "sounds", "wheelHubBearingNoise", modDir, root, 1, AudioGroup.VEHICLE, i3d, self)
        spec.samples.ptoBearingNoise = soundManager:loadSampleFromXML(xmlSoundFile, "sounds", "ptoBearingNoise", modDir, root, 1, AudioGroup.VEHICLE, i3d, self)
        spec.samples.vibrationNoice = soundManager:loadSampleFromXML(xmlSoundFile, "sounds", "vibrationNoice", modDir, root, 1, AudioGroup.VEHICLE, i3d, self)
        spec.samples.wheelSeizureGrind = soundManager:loadSampleFromXML(xmlSoundFile, "sounds", "wheelSeizureGrind", modDir, root, 1, AudioGroup.VEHICLE, i3d, self)
        spec.samples.gearDisengage1 = soundManager:loadSampleFromXML(xmlSoundFile, "sounds", "gearDisengage1", modDir, root, 1, AudioGroup.VEHICLE, i3d, self)
        spec.samples.engineKnocking = soundManager:loadSampleFromXML(xmlSoundFile, "sounds", "engineKnocking", modDir, root, 1, AudioGroup.VEHICLE, i3d, self)
        spec.samples.valveTrainNoise = soundManager:loadSampleFromXML(xmlSoundFile, "sounds", "valveTrainNoise", modDir, root, 1, AudioGroup.VEHICLE, i3d, self)
        spec.samples.inspection = soundManager:loadSampleFromXML(xmlSoundFile, "sounds", "inspection", modDir, root, 1, AudioGroup.VEHICLE, i3d, self)
        spec.samples.parkBrakeLeverApply = soundManager:loadSampleFromXML(xmlSoundFile, "sounds", "parkBrakeLeverApply", modDir, root, 1, AudioGroup.VEHICLE, i3d, self)
        spec.samples.parkBrakeLeverRelease = soundManager:loadSampleFromXML(xmlSoundFile, "sounds", "parkBrakeLeverRelease", modDir, root, 1, AudioGroup.VEHICLE, i3d, self)
        spec.samples.parkBrakeAutoApply = soundManager:loadSampleFromXML(xmlSoundFile, "sounds", "parkBrakeAutoApply", modDir, root, 1, AudioGroup.VEHICLE, i3d, self)
        spec.samples.parkBrakeAutoRelease = soundManager:loadSampleFromXML(xmlSoundFile, "sounds", "parkBrakeAutoRelease", modDir, root, 1, AudioGroup.VEHICLE, i3d, self)
        spec.samples.parkBrakeSwitchOn = soundManager:loadSampleFromXML(xmlSoundFile, "sounds", "parkBrakeSwitchOn", modDir, root, 1, AudioGroup.VEHICLE, i3d, self)
        spec.samples.parkBrakeSwitchOff = soundManager:loadSampleFromXML(xmlSoundFile, "sounds", "parkBrakeSwitchOff", modDir, root, 1, AudioGroup.VEHICLE, i3d, self)
        spec.samples.parkBrakeTruckApply = soundManager:loadSampleFromXML(xmlSoundFile, "sounds", "parkBrakeTruckApply", modDir, root, 1, AudioGroup.VEHICLE, i3d, self)
        spec.samples.parkBrakeTruckRelease = soundManager:loadSampleFromXML(xmlSoundFile, "sounds", "parkBrakeTruckRelease", modDir, root, 1, AudioGroup.VEHICLE, i3d, self)
        spec.samples.batteryIsolator = soundManager:loadSampleFromXML(xmlSoundFile, "sounds", "batteryIsolator", modDir, root, 1, AudioGroup.VEHICLE, i3d, self)
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
        -- the other systems exist on every machine, electric ones included
        for _, systemData in pairs(spec.systems) do
            -- a hydraulic circuit its fluid profile gives no oil does not exist
            if systemData.name == RealisticMechanicalSystems.SYSTEMS.HYDRAULICS then
                systemData.enabled = RMS_Utils.hasHydraulicCapability(vehicle)
                    and resolvedCapacities.hydraulicFluid > 0
            elseif systemData.name == RealisticMechanicalSystems.SYSTEMS.PTO then
                systemData.enabled = RMS_Utils.hasPtoOutputCapability(vehicle)
            end
        end
    end

    enableOrDisableSystems(self)
    RMS_Fluids.initializeVehicle(self, false)
    RealisticMechanicalSystems.getServiceClocks(self)
    if RMS_Thermal.getHasSeparateHydraulicCircuit(spec) then
        spec.rawHydraulicTemperature = RealisticMechanicalSystems.sanitizeNumber(spec.rawHydraulicTemperature, spec.rawTransmissionTemperature)
        spec.hydraulicTemperature = spec.rawHydraulicTemperature
    else
        spec.rawHydraulicTemperature = nil
        spec.hydraulicTemperature = nil
    end
    -- each runtime clock starts at the current mission, saved timestamps being metadata
    spec._thermalEngineWorldTime, spec._thermalOilWorldTime, spec._thermalBatteryWorldTime = nil, nil, nil
    spec._thermalEngineAmbient, spec._thermalOilAmbient, spec._thermalBatteryAmbient = nil, nil, nil
    RealisticMechanicalSystems.migrateLegacyThermalProtection(spec)
    if spec.isElectricVehicle then
        RMS_ElectricDrive.initBatteryCapacity(self)
    end
    -- road vehicles take no grease and do not clog up, whatever type their mod declares
    local isRoadVehicle = RMS_Drivetrain.getIsRoadVehicleCategory(self)
    spec.isVehicleNeedLubricate = not isRoadVehicle
    spec.isVehicleNeedBlowOut = not isRoadVehicle
    resetIsMovingRecursive(self, {})

    -- for general wear and tear calculations
    spec._prevConditionLevel = self:getConditionLevel()

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
    spec._lastSyncFieldcare_radiatorClogging = spec.radiatorClogging
    spec._lastSyncFieldcare_airFilterClogging = spec.airFilterClogging
    spec._lastSyncFieldcare_airFilterResidue = spec.airFilterResidue
    spec._lastSyncFieldcare_fuelFilterClogging = spec.fuelFilterClogging
    spec._lastSyncFieldcare_hydraulicFilterClogging = spec.hydraulicFilterClogging
    spec._lastSyncFieldcare_lubricationLevel = spec.lubricationLevel
    spec._lastSyncFieldcare_engineOilLevel = spec.engineOilLevel
    spec._lastSyncFieldcare_coolantLevel = spec.coolantLevel
    spec._lastSyncFieldcare_transmissionOilLevel = spec.transmissionOilLevel
    spec._lastSyncFieldcare_hydraulicFluidLevel = spec.hydraulicFluidLevel
    for _, circuit in ipairs(RMS_Fluids.CIRCUIT_ORDER) do
        spec["_lastSyncFieldcare_capacity_" .. circuit] = RMS_Fluids.getCapacity(self, circuit)
        spec["_lastSyncFieldcare_compatibility_" .. circuit] = RMS_Fluids.getCompatibility(self, circuit)
    end
    spec._lastSyncFieldcare_leakDebt = RMS_Fluids.serializeLeakDebt(spec.fluidLeakLossDebt)
    spec._lastSyncFieldcare_inspectionSoundActive = spec.fieldInspectionSoundActive
    -- [7] wear
    spec._lastSyncWear_serviceLevel = spec.serviceLevel
    spec._lastSyncWear_transmissionServiceLevel = spec.transmissionServiceLevel
    spec._lastSyncWear_coolantServiceLevel = spec.coolantServiceLevel
    spec._lastSyncWear_hydraulicServiceLevel = spec.hydraulicServiceLevel
    spec._lastSyncWear_serviceCalendar = RMS_Utils.serializeNumericMap(spec.serviceCalendar)
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
