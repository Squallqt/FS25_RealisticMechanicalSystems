-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---Trolley diagnostic tool.
RMS_DiagnosticTool = {}
RMS_DiagnosticTool.SPEC_NAME = "FS25_RealisticMechanicalSystems.rmsDiagnosticTool"
RMS_DiagnosticTool.SPEC_TABLE_NAME = "spec_" .. RMS_DiagnosticTool.SPEC_NAME
RMS_DiagnosticTool.CONFIGURATION = "rmsDiagnosticPc"
RMS_DiagnosticTool.PC_OPTION = 2
RMS_DiagnosticTool.LICENCE_MONTHS = 12
RMS_DiagnosticTool.ACTION = { PLUG = 1, UNPLUG = 2, SCAN = 3, RENEW = 4 }
RMS_DiagnosticTool.SCAN = { NONE = 0, RUNNING = 1, DONE = 2, INTERRUPTED = 3 }

local CONFIGURATION_KEY = "vehicle.rmsDiagnosticTool.rmsDiagnosticPcConfigurations.rmsDiagnosticPcConfiguration"
local getIsAlive = RMS_BatteryCharger.getIsAlive
local getDistance = RMS_BatteryCharger.getDistance

---
local function getSpec(tool)
    return tool ~= nil and tool[RMS_DiagnosticTool.SPEC_TABLE_NAME] or nil
end

local function updateScreen(spec)
    local isPlugged = spec.target ~= nil or spec.targetObjectId ~= nil
    if spec.screenOn ~= nil then
        setVisibility(spec.screenOn, isPlugged)
    end
    if spec.screenOff ~= nil then
        setVisibility(spec.screenOff, not isPlugged)
    end
end

---Returns the machine a PC is plugged into, server or client
local function getTargetObject(spec)
    if spec.targetObjectId ~= nil then
        return NetworkUtil.getObject(spec.targetObjectId)
    end
    return spec.target
end

---
function RMS_DiagnosticTool.prerequisitesPresent(specializations)
    return SpecializationUtil.hasSpecialization(RMS_BatteryCharger, specializations)
end

---
function RMS_DiagnosticTool.initSpecialization()
    if g_iconGenerator == nil then
        g_vehicleConfigurationManager:addConfigurationType(RMS_DiagnosticTool.CONFIGURATION,
            g_i18n:getText("rms_diagnostic_configuration"), "rmsDiagnosticTool", VehicleConfigurationItem)
    end
    local schema = Vehicle.xmlSchema
    schema:setXMLSpecializationType("RMSDiagnosticTool")
    ObjectChangeUtil.registerObjectChangeXMLPaths(schema, CONFIGURATION_KEY .. "(?)")
    schema:setXMLSpecializationType()
    Vehicle.xmlSchemaSavegame:register(XMLValueType.STRING, "vehicles.vehicle(?)." .. RMS_DiagnosticTool.SPEC_NAME
        .. "#targetUniqueId", "Machine the PC is plugged into")
    Vehicle.xmlSchemaSavegame:register(XMLValueType.INT, "vehicles.vehicle(?)." .. RMS_DiagnosticTool.SPEC_NAME
        .. "#licenceMonths", "Months left on the paid licence")
end

---
function RMS_DiagnosticTool.registerEventListeners(vehicleType)
    for _, name in ipairs({ "onLoad", "onDelete", "onUpdate", "saveToXMLFile", "onReadStream", "onWriteStream",
        "onReadUpdateStream", "onWriteUpdateStream" }) do
        SpecializationUtil.registerEventListener(vehicleType, name, RMS_DiagnosticTool)
    end
end

---
function RMS_DiagnosticTool:onLoad(savegame)
    local spec = assert(getSpec(self))
    local option = self.configurations[RMS_DiagnosticTool.CONFIGURATION] or 1
    ObjectChangeUtil.updateObjectChanges(self.xmlFile, CONFIGURATION_KEY, option, self.components, self)
    spec.hasPc = option == RMS_DiagnosticTool.PC_OPTION
    spec.targetUniqueId = ""
    spec.licenceMonths = RMS_DiagnosticTool.LICENCE_MONTHS
    spec.scanState = RMS_DiagnosticTool.SCAN.NONE
    spec.scanFaults = {}
    spec.screenOn = I3DUtil.indexToObject(self.components, "diagnosticScreenOn", self.i3dMappings)
    spec.screenOff = I3DUtil.indexToObject(self.components, "diagnosticScreenOff", self.i3dMappings)
    spec.pcRoot = I3DUtil.indexToObject(self.components, "diagnosticPcRoot", self.i3dMappings)
    updateScreen(spec)
    spec.dirtyFlag = self:getNextDirtyFlag()
    if savegame ~= nil and not savegame.resetVehicles then
        local key = savegame.key .. "." .. RMS_DiagnosticTool.SPEC_NAME
        spec.targetUniqueId = savegame.xmlFile:getValue(key .. "#targetUniqueId", "")
        spec.licenceMonths = savegame.xmlFile:getValue(key .. "#licenceMonths", spec.licenceMonths)
    end
    if spec.targetUniqueId ~= "" then
        self:raiseActive()
    end
end

---
function RMS_DiagnosticTool:onDelete()
    if self.isServer then
        RMS_DiagnosticTool.unplug(self)
    end
end

-- @param table tool trolley
-- @param table? target machine
-- @return string reason "ok", or the reason of the refusal
function RMS_DiagnosticTool.validate(tool, target)
    local spec = getSpec(tool)
    if spec == nil or not spec.hasPc or not getIsAlive(tool) or not getIsAlive(target) then
        return "unavailable"
    end
    local targetSpec = target.spec_RealisticMechanicalSystems
    if targetSpec == nil or targetSpec.isExcludedVehicle then
        return "unavailable"
    end
    if tool:getOwnerFarmId() ~= target:getOwnerFarmId() then
        return "access"
    end
    if getDistance(tool, target) > RMS_BatteryCharger.MAX_DISTANCE then
        return "distance"
    end
    if not RMS_DiagnosticTool.getHasControllers(target) then
        return "electronics"
    end
    local isPlugged = spec.target == target
    if isPlugged and RMS_BatteryCharger.hasMoved(target, spec.targetPosition)
        or not isPlugged and math.abs(target:getLastSpeed()) > RMS_BatteryCharger.STOPPED_SPEED then
        return "moving"
    end
    local other = RMS_DiagnosticTool.getConnectedTool(target)
    if other ~= nil and other ~= tool then
        return "busy"
    end
    return "ok"
end

---Plugs the PC of a trolley into a machine, on the server
-- @param table tool trolley
-- @param table target machine
-- @return string reason "ok", or the reason of the refusal
function RMS_DiagnosticTool.plug(tool, target)
    local reason = RMS_DiagnosticTool.validate(tool, target)
    if reason ~= "ok" then
        return reason
    end
    RMS_DiagnosticTool.unplug(tool)
    local spec = getSpec(tool)
    spec.target = target
    spec.targetPosition = RMS_BatteryCharger.getPosition(target)
    spec.targetUniqueId = target:getUniqueId()
    target.spec_RealisticMechanicalSystems.diagnosticTool = tool
    updateScreen(spec)
    tool:raiseDirtyFlags(spec.dirtyFlag)
    tool:raiseActive()
    return "ok"
end

---Unplugs the PC of a trolley, on the server
-- @param table tool trolley
function RMS_DiagnosticTool.unplug(tool)
    local spec = getSpec(tool)
    local target = spec.target
    if target ~= nil and target.spec_RealisticMechanicalSystems ~= nil
        and target.spec_RealisticMechanicalSystems.diagnosticTool == tool then
        target.spec_RealisticMechanicalSystems.diagnosticTool = nil
    end
    if target ~= nil or spec.targetUniqueId ~= "" then
        spec.target, spec.targetPosition, spec.targetUniqueId = nil, nil, ""
        spec.scanState, spec.scanFaults = RMS_DiagnosticTool.SCAN.NONE, {}
        updateScreen(spec)
        tool:raiseDirtyFlags(spec.dirtyFlag)
    end
end

---Finds the trolley whose PC is plugged into a machine
-- @param table target machine
-- @return table? tool trolley
function RMS_DiagnosticTool.getConnectedTool(target)
    local targetSpec = target ~= nil and target.spec_RealisticMechanicalSystems or nil
    if targetSpec == nil then
        return nil
    end
    if getIsAlive(targetSpec.diagnosticTool) then
        return targetSpec.diagnosticTool
    end
    if not target.isServer then
        for _, tool in pairs(g_currentMission.vehicleSystem.vehicles) do
            local spec = getSpec(tool)
            if spec ~= nil and getIsAlive(tool) and getTargetObject(spec) == target then
                return tool
            end
        end
    end
    return nil
end

---Returns the root node of the PC a trolley carries, nil without the PC
-- @param table tool trolley
-- @return entityId? pcRoot
function RMS_DiagnosticTool.getPcRoot(tool)
    local spec = getSpec(tool)
    return spec ~= nil and spec.hasPc and spec.pcRoot or nil
end

-- @param table tool trolley
-- @return table? target machine
function RMS_DiagnosticTool.getTarget(tool)
    local target = getTargetObject(assert(getSpec(tool)))
    return getIsAlive(target) and target or nil
end

local function addReadingToLog(target, faults)
    local readings = {}
    for _, fault in ipairs(faults) do
        table.insert(readings, fault.breakdownId .. ":" .. (fault.isCritical and "1" or "0"))
    end
    target:addEntryToMaintenanceLog(RealisticMechanicalSystems.LOG_DIAGNOSTIC_READING, table.concat(readings, ","), "NONE",
        false, 0, true, nil)
    local log = target.spec_RealisticMechanicalSystems.maintenanceLog
    local entry = log[#log]
    entry.isVisible = true
    entry.location = "UNKNOWN"
    entry.conditionData.selectedBreakdowns = {}
    RMS_LogEntrySyncEvent.sendToClients(target, entry)
end

function RMS_DiagnosticTool:onUpdate()
    local spec = assert(getSpec(self))
    if not self.isServer then
        return
    end
    if spec.target == nil and spec.targetUniqueId ~= "" then
        local system = g_currentMission.vehicleSystem
        if system.loadedVehicles == nil then
            local target = system:getVehicleByUniqueId(spec.targetUniqueId)
            spec.targetUniqueId = ""
            if target ~= nil then
                RMS_DiagnosticTool.plug(self, target)
            else
                self:raiseDirtyFlags(spec.dirtyFlag)
            end
        else
            self:raiseActive()
        end
    elseif spec.target ~= nil then
        if RMS_DiagnosticTool.validate(self, spec.target) ~= "ok" then
            RMS_DiagnosticTool.unplug(self)
        else
            if spec.scanState == RMS_DiagnosticTool.SCAN.RUNNING then
                if not RMS_DiagnosticTool.getIsPowered(spec.target) then
                    spec.scanState = RMS_DiagnosticTool.SCAN.INTERRUPTED
                    self:raiseDirtyFlags(spec.dirtyFlag)
                elseif g_currentMission.time - spec.scanStartTime >= RMS_Config.DIAGNOSTIC.SCAN_DURATION_MS then
                    spec.scanState = RMS_DiagnosticTool.SCAN.DONE
                    addReadingToLog(spec.target, spec.scanFaults)
                    self:raiseDirtyFlags(spec.dirtyFlag)
                end
            end
            self:raiseActive()
        end
    end
end

-- @param table target machine
-- @return boolean hasControllers
function RMS_DiagnosticTool.getHasControllers(target)
    return target.spec_RealisticMechanicalSystems.isElectricVehicle == true or RMS_Utils.getUsesEngineECUProfile(target)
end

local FIRST_CYLINDER_SPN, LAST_CYLINDER_SPN = 1323, 1325

---Returns the name of a suspect parameter as the J1939 standard gives it
-- @param integer spn suspect parameter
-- @return string name
function RMS_DiagnosticTool.getSpnName(spn)
    if spn >= FIRST_CYLINDER_SPN and spn <= LAST_CYLINDER_SPN then
        return string.format(g_i18n:getText("rms_diagnostic_spn_cylinder"), spn - FIRST_CYLINDER_SPN + 1)
    end
    return g_i18n:getText("rms_diagnostic_spn_" .. spn)
end

-- @param table entry code from getFaultEntry
-- @return string text
function RMS_DiagnosticTool.getDisplayText(entry)
    return string.format(g_i18n:getText("rms_dashboard_code_message"), RMS_DiagnosticTool.getSpnName(entry.spn),
        g_i18n:getText("rms_dashboard_fmi_" .. entry.fmi))
end

-- @param table target machine
-- @return boolean isPowered
function RMS_DiagnosticTool.getIsPowered(target)
    return not target.spec_RealisticMechanicalSystems.batteryIsolated
end

local function getCodeController(target, code)
    local isElectric = target.spec_RealisticMechanicalSystems.isElectricVehicle
    local ecu, spn = code.ecu, code.spn
    if code.electric ~= nil and isElectric then
        ecu, spn = code.electric.ecu, code.electric.spn
    end
    if ecu == "ENGINE" and isElectric then
        return nil
    end
    if code.fanDrive ~= nil and RMS_Utils.getFanDrive(target) ~= code.fanDrive then
        return nil
    end
    if ecu == "TRANSMISSION" then
        local motor = target:getMotor()
        if isElectric or not RMS_Utils.hasCVTAddon(target) and (motor == nil or motor.minForwardGearRatio == nil
            and motor.gearType ~= VehicleMotor.TRANSMISSION_TYPE.POWERSHIFT) then
            return nil
        end
    end
    return ecu, spn
end

-- @param table target machine
-- @param string breakdownId fault
-- @param boolean isCritical true when the fault lights its telltale red
-- @return table entry breakdownId, isCritical, and ecu, spn, fmi or the system
function RMS_DiagnosticTool.getFaultEntry(target, breakdownId, isCritical)
    local code = RMS_Config.DIAGNOSTIC.FAULT_CODES[breakdownId]
    local breakdown = target:getActiveBreakdowns()[breakdownId]
    if code ~= nil and code.branches ~= nil and breakdown ~= nil and code.branches[breakdown.branch] ~= nil then
        code = code.branches[breakdown.branch]
    end
    local ecu, spn
    if code ~= nil then
        ecu, spn = getCodeController(target, code)
    end
    if ecu == nil then
        local definition = RMS_Breakdowns.BreakdownRegistry[breakdownId]
        return { breakdownId = breakdownId, isCritical = isCritical, system = definition ~= nil and definition.system or nil }
    end
    if code.cylinders ~= nil then
        local sum = 0
        for index = 1, #target:getUniqueId() do
            sum = sum + string.byte(target:getUniqueId(), index)
        end
        spn = spn + sum % code.cylinders
    end
    return { breakdownId = breakdownId, isCritical = isCritical, ecu = ecu, spn = spn,
        fmi = isCritical and code.critical or code.warning }
end

-- @param table target machine
-- @return table controllers ecu names
function RMS_DiagnosticTool.getControllers(target)
    local present = { DASHBOARD = true }
    for breakdownId, code in pairs(RMS_Config.DIAGNOSTIC.FAULT_CODES) do
        local definition = RMS_Breakdowns.BreakdownRegistry[breakdownId]
        if definition ~= nil and (definition.isApplicable == nil or definition.isApplicable(target)) then
            for _, wayCode in pairs(code.branches or {}) do
                local wayEcu = getCodeController(target, wayCode)
                if wayEcu ~= nil then
                    present[wayEcu] = true
                end
            end
            local ecu = code.ecu ~= nil and getCodeController(target, code) or nil
            if ecu ~= nil then
                present[ecu] = true
            end
        end
    end
    local controllers = {}
    for _, ecu in ipairs(RMS_Config.DIAGNOSTIC.ECUS) do
        if present[ecu] then
            table.insert(controllers, ecu)
        end
    end
    return controllers
end

-- @param table target machine
-- @return table? codes codes and uncoded systems, nil when the machine is not powered
-- @return string? reason "power" when the battery of the machine is cut
function RMS_DiagnosticTool.readFaultCodes(target)
    if not RMS_DiagnosticTool.getIsPowered(target) then
        return nil, "power"
    end
    local registry = RMS_Breakdowns.BreakdownRegistry
    local critical = RMS_Breakdowns.COLORS.CRITICAL
    local codes, stored = {}, {}
    for breakdownId, breakdown in pairs(target:getActiveBreakdowns()) do
        local definition = registry[breakdownId]
        local stage = definition ~= nil and breakdown.isActive ~= false and definition.stages[breakdown.stage] or nil
        local indicators = stage ~= nil and RMS_Utils.getBranchItems(stage.indicators, breakdown) or {}
        if #indicators > 0 and definition.system ~= nil then
            local isCritical = false
            for _, indicator in ipairs(indicators) do
                isCritical = isCritical or indicator.color == critical
            end
            local entry = RMS_DiagnosticTool.getFaultEntry(target, breakdownId, isCritical)
            local key = entry.spn ~= nil and string.format("%s %d %d", entry.ecu, entry.spn, entry.fmi) or entry.system
            if stored[key] == nil then
                stored[key] = entry
                table.insert(codes, entry)
            else
                stored[key].isCritical = stored[key].isCritical or entry.isCritical
            end
        end
    end
    table.sort(codes, function(a, b)
        if (a.spn ~= nil) ~= (b.spn ~= nil) then
            return a.spn ~= nil
        end
        return (a.spn or 0) < (b.spn or 0) or a.spn == b.spn and a.breakdownId < b.breakdownId
    end)
    return codes
end

---Returns a logged reading's codes in the PC's format
-- @param table vehicle machine
-- @param table entry journal entry of a reading
-- @return table codes "SPN 157 FMI 18", or the light lit without a code
function RMS_DiagnosticTool.getReadingCodes(vehicle, entry)
    local codes, written = {}, {}
    for reading in string.gmatch(entry.optionOne or "", "[^,]+") do
        local breakdownId, critical = reading:match("^([%w_]+):([01])$")
        if breakdownId ~= nil then
            local fault = RMS_DiagnosticTool.getFaultEntry(vehicle, breakdownId, critical == "1")
            local code = fault.spn ~= nil and string.format("SPN %d FMI %d", fault.spn, fault.fmi)
                or g_i18n:getText("rms_diagnostic_uncoded_title")
            if not written[code] then
                written[code] = true
                table.insert(codes, code)
            end
        end
    end
    return codes
end

---Returns the codes of a reading in one line, or that it found none
-- @param table vehicle machine
-- @param table entry journal entry of a reading
-- @return string text
function RMS_DiagnosticTool.formatReadingCodes(vehicle, entry)
    local codes = RMS_DiagnosticTool.getReadingCodes(vehicle, entry)
    return #codes > 0 and table.concat(codes, ", ") or g_i18n:getText("rms_diagnostic_no_fault")
end

-- @param table tool trolley
-- @return string reason "ok", "unplugged" or "power"
function RMS_DiagnosticTool.startScan(tool)
    local spec = assert(getSpec(tool))
    if spec.target == nil then
        return "unplugged"
    end
    local codes = RMS_DiagnosticTool.readFaultCodes(spec.target)
    if codes == nil then
        return "power"
    end
    spec.scanState = RMS_DiagnosticTool.SCAN.RUNNING
    spec.scanStartTime = g_currentMission.time
    spec.scanFaults = codes
    tool:raiseDirtyFlags(spec.dirtyFlag)
    tool:raiseActive()
    return "ok"
end

---Returns how far a scan has gone, on the server and on a client
-- @param table tool trolley
-- @return float progress 0 to 1
function RMS_DiagnosticTool.getScanProgress(tool)
    local spec = assert(getSpec(tool))
    if spec.scanState ~= RMS_DiagnosticTool.SCAN.RUNNING then
        return spec.scanState == RMS_DiagnosticTool.SCAN.DONE and 1 or 0
    end
    return math.min((g_currentMission.time - spec.scanStartTime) / RMS_Config.DIAGNOSTIC.SCAN_DURATION_MS, 1)
end

function RMS_DiagnosticTool.advanceLicences()
    for _, tool in pairs(g_currentMission.vehicleSystem.vehicles) do
        local spec = getSpec(tool)
        if spec ~= nil and spec.hasPc and spec.licenceMonths > 0 then
            spec.licenceMonths = spec.licenceMonths - 1
            tool:raiseDirtyFlags(spec.dirtyFlag)
        end
    end
end

-- @param table tool trolley
-- @return boolean isValid
function RMS_DiagnosticTool.getIsLicenceValid(tool)
    return assert(getSpec(tool)).licenceMonths > 0
end

-- @return float price
function RMS_DiagnosticTool.getLicencePrice()
    return RMS_Utils.getGamePrice(RMS_Config.DIAGNOSTIC.LICENCE_PRICE)
end

---Returns the month and the year the licence of a PC runs out in
-- @param table tool trolley
-- @return integer period month of the game, 1 being March
-- @return integer year
function RMS_DiagnosticTool.getLicenceEnd(tool)
    local environment = g_currentMission.environment
    local months = environment.currentPeriod - 1 + assert(getSpec(tool)).licenceMonths
    return months % 12 + 1, environment.currentYear + math.floor(months / 12)
end

-- @param table tool trolley
-- @return string reason "ok", or "money"
function RMS_DiagnosticTool.renewLicence(tool)
    local spec = assert(getSpec(tool))
    if spec.licenceMonths > 0 then
        return "ok"
    end
    local price = RMS_DiagnosticTool.getLicencePrice()
    local farmId = tool:getOwnerFarmId()
    if (g_currentMission:getMoney(farmId) or 0) < price then
        return "money"
    end
    g_currentMission:addMoney(-price, farmId, MoneyType.VEHICLE_RUNNING_COSTS, true)
    spec.licenceMonths = RMS_DiagnosticTool.LICENCE_MONTHS
    tool:raiseDirtyFlags(spec.dirtyFlag)
    return "ok"
end

---
function RMS_DiagnosticTool:saveToXMLFile(xmlFile, key)
    local spec = assert(getSpec(self))
    xmlFile:setValue(key .. "#targetUniqueId", spec.target ~= nil and spec.targetUniqueId or "")
    xmlFile:setValue(key .. "#licenceMonths", spec.licenceMonths)
end

---
local function writeState(spec, streamId)
    local target = getIsAlive(spec.target) and spec.target or nil
    streamWriteBool(streamId, target ~= nil)
    if target ~= nil then
        NetworkUtil.writeNodeObject(streamId, target)
    end
    streamWriteUIntN(streamId, spec.licenceMonths, 4)
    streamWriteUIntN(streamId, spec.scanState, 2)
    if spec.scanState ~= RMS_DiagnosticTool.SCAN.NONE then
        streamWriteFloat32(streamId, g_currentMission.time - spec.scanStartTime)
        streamWriteUInt8(streamId, #spec.scanFaults)
        for _, fault in ipairs(spec.scanFaults) do
            streamWriteString(streamId, fault.breakdownId)
            streamWriteBool(streamId, fault.isCritical)
        end
    end
end

---
local function readState(spec, streamId)
    spec.targetObjectId = nil
    if streamReadBool(streamId) then
        spec.targetObjectId = NetworkUtil.readNodeObjectId(streamId)
    end
    spec.licenceMonths = streamReadUIntN(streamId, 4)
    spec.scanState = streamReadUIntN(streamId, 2)
    spec.scanFaults = {}
    if spec.scanState ~= RMS_DiagnosticTool.SCAN.NONE then
        spec.scanStartTime = g_currentMission.time - streamReadFloat32(streamId)
        for _ = 1, streamReadUInt8(streamId) do
            table.insert(spec.scanFaults, { breakdownId = streamReadString(streamId), isCritical = streamReadBool(streamId) })
        end
    end
    updateScreen(spec)
end

---
function RMS_DiagnosticTool:onWriteStream(streamId)
    writeState(assert(getSpec(self)), streamId)
end

---
function RMS_DiagnosticTool:onReadStream(streamId)
    readState(assert(getSpec(self)), streamId)
end

---
function RMS_DiagnosticTool:onWriteUpdateStream(streamId, connection, dirtyMask)
    if not connection:getIsServer() then
        local spec = assert(getSpec(self))
        local changed = bitAND(dirtyMask, spec.dirtyFlag) ~= 0
        streamWriteBool(streamId, changed)
        if changed then
            writeState(spec, streamId)
        end
    end
end

---
function RMS_DiagnosticTool:onReadUpdateStream(streamId, timestamp, connection)
    if connection:getIsServer() and streamReadBool(streamId) then
        readState(assert(getSpec(self)), streamId)
    end
end
