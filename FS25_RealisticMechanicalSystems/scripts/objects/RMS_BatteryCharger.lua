-- Copyright © 2026 Squallqt. All rights reserved.

---Mobile battery charger: charge and starting aid
RMS_BatteryCharger = {}
RMS_BatteryCharger.SPEC_NAME = "FS25_RealisticMechanicalSystems.rmsBatteryCharger"
RMS_BatteryCharger.SPEC_TABLE_NAME = "spec_" .. RMS_BatteryCharger.SPEC_NAME
RMS_BatteryCharger.MAX_DISTANCE = 4
RMS_BatteryCharger.STOPPED_SPEED = 0.1
RMS_BatteryCharger.STATE = { IDLE = 0, CHARGING = 1, FULL = 2, INTERRUPTED = 3 }
RMS_BatteryCharger.MODE = { CHARGE = 0, START = 1 }
RMS_BatteryCharger.START_CURRENT_A = 200
RMS_BatteryCharger.MAX_CURRENT_24V_A = 80
RMS_BatteryCharger.START_COOLDOWN_MS = 30000

---Returns the charger specialization of a vehicle, nil without one
-- @param table? charger vehicle
-- @return table? spec charger specialization
local function getSpec(charger)
    return charger ~= nil and charger[RMS_BatteryCharger.SPEC_TABLE_NAME] or nil
end

---Tells whether the charger is connected
-- @param table spec charger specialization
-- @return boolean isConnected true while charging or full
local function canDisconnect(spec)
    return spec.state == RMS_BatteryCharger.STATE.CHARGING or spec.state == RMS_BatteryCharger.STATE.FULL
end

---Returns the distance between two objects
-- @param table a first object
-- @param table b second object
-- @return float distance distance (m)
function RMS_BatteryCharger.getDistance(a, b)
    local ax, ay, az = getWorldTranslation(a.rootNode)
    local bx, by, bz = getWorldTranslation(b.rootNode)
    return MathUtil.vector3Length(ax - bx, ay - by, az - bz)
end
local getDistance = RMS_BatteryCharger.getDistance

---Returns how far an object stands from the body of a machine, math.huge without a node
-- @param table? object object
-- @param table? machine machine
-- @return float distance distance (m)
function RMS_BatteryCharger.getDistanceToMachine(object, machine)
    if object == nil or machine == nil or object.rootNode == nil or machine.rootNode == nil then
        return math.huge
    end
    return RMS_FluidTransfer.getDistanceToVehicle(machine, object.rootNode)
end
local getDistanceToMachine = RMS_BatteryCharger.getDistanceToMachine

---Tells whether an object still stands in the world
-- @param table? object object
-- @return boolean isAlive true while it stands in the world
function RMS_BatteryCharger.getIsAlive(object)
    return object ~= nil and object.isDeleted ~= true and object.isDeleting ~= true
        and object.markedForDeletion ~= true and object.rootNode ~= nil and entityExists(object.rootNode)
end
local getIsAlive = RMS_BatteryCharger.getIsAlive

---Tells whether the target is being started
-- @param table target machine
-- @return boolean isCranking true while it cranks
local function getIsCranking(target)
    return RMS_Electrical.getIsStarting(target)
end

---Sets the push drive to automatic direction and gears
-- @param table charger battery charger
local function configurePushDrive(charger)
    local motorized = charger.spec_motorized
    motorized.directionChangeMode = VehicleMotor.DIRECTION_CHANGE_MODE_AUTOMATIC
    motorized.gearShiftMode = VehicleMotor.SHIFT_MODE_AUTOMATIC
    motorized.motor:setDirectionChangeMode(motorized.directionChangeMode)
    motorized.motor:setGearShiftMode(motorized.gearShiftMode)
end

---Publishes the measurements and sends them to the clients
-- @param table charger battery charger
-- @param table spec charger specialization
local function publishState(charger, spec)
    spec.publishedCurrent = spec.current
    spec.publishedSoc = spec.soc
    spec.publishedVoltage = spec.voltage
    spec.publishedInsufficient = spec.insufficient
    charger:raiseDirtyFlags(spec.dirtyFlag)
end

---Plays the clamps put on or taken off, for every player around
-- @param table charger battery charger
-- @param integer previousState RMS_BatteryCharger.STATE before the change
local function playClamps(charger, previousState)
    local spec = charger[RMS_BatteryCharger.SPEC_TABLE_NAME]
    local wasConnected = previousState == RMS_BatteryCharger.STATE.CHARGING or previousState == RMS_BatteryCharger.STATE.FULL
    if charger.isClient and wasConnected ~= canDisconnect(spec) then
        RMS_SoundManager.playSample(wasConnected and spec.disconnectSample or spec.connectSample)
    end
end

---Plays the clamps and notifies the owner of a state change
-- @param table charger battery charger
-- @param integer previousState RMS_BatteryCharger.STATE before the change
-- @param boolean previousInsufficient true when the current was short before the change
-- @param table? previousTarget machine connected before the change
local function notifyChange(charger, previousState, previousInsufficient, previousTarget)
    playClamps(charger, previousState)
    if not charger.isClient or charger:getOwnerFarmId() ~= g_currentMission:getFarmId() then
        return
    end
    local spec = charger[RMS_BatteryCharger.SPEC_TABLE_NAME]
    local message
    if spec.state ~= previousState then
        if spec.state == RMS_BatteryCharger.STATE.CHARGING then
            message = g_i18n:getText(spec.mode == RMS_BatteryCharger.MODE.START
                and "rms_charger_start_connected" or "rms_charger_connected")
        elseif spec.state == RMS_BatteryCharger.STATE.FULL then
            message = g_i18n:getText("rms_charger_full")
        elseif spec.state == RMS_BatteryCharger.STATE.IDLE then
            if previousState == RMS_BatteryCharger.STATE.CHARGING or previousState == RMS_BatteryCharger.STATE.FULL then
                message = g_i18n:getText("rms_charger_disconnected")
            end
        elseif spec.reason == "motor" then
            message = g_i18n:getText("rms_charger_stopped_motor")
        elseif spec.reason ~= "" then
            message = string.format(g_i18n:getText("rms_charger_interrupted_reason"),
                g_i18n:getText("rms_charger_error_" .. spec.reason))
        else
            message = g_i18n:getText("rms_charger_interrupted")
        end
    elseif spec.state == RMS_BatteryCharger.STATE.CHARGING and spec.insufficient and not previousInsufficient then
        message = g_i18n:getText("rms_charger_consumers")
    end
    if message ~= nil then
        local target = RMS_Utils.getConnectedObject(spec) or previousTarget
        local name = target ~= nil and target:getFullName() or charger:getFullName()
        g_currentMission.hud:addSideNotification(HUD.COLOR.DEFAULT,
            string.format(g_i18n:getText("rms_hud_vehicle_notification"), name, message))
    end
end

---Finds the charger connected to a target
-- @param table target machine
-- @return table? charger charger, nil for none
function RMS_BatteryCharger.getConnectedCharger(target)
    local battery = target.spec_RealisticMechanicalSystems
    if getIsAlive(battery.batteryCharger) then return battery.batteryCharger end
    if not target.isServer then
        for _, charger in pairs(g_currentMission.vehicleSystem.vehicles) do
            local spec = getSpec(charger)
            if spec ~= nil and canDisconnect(spec) and getIsAlive(charger) and RMS_Utils.getConnectedObject(spec) == target then
                return charger
            end
        end
    end
    return nil
end

---Returns why the connected charger blocks a start
-- @param table target machine
-- @return string? textKey l10n key of the reason, nil when nothing blocks
function RMS_BatteryCharger.getStartBlockReason(target)
    if target:getIsMotorStarted() then return nil end
    local charger = RMS_BatteryCharger.getConnectedCharger(target)
    local spec = getSpec(charger)
    if spec == nil then return nil end
    if spec.mode ~= RMS_BatteryCharger.MODE.START then return "rms_charger_unplug_before_start" end
    if spec.cooldownUntilMs > g_currentMission.time then
        return "rms_charger_start_wait"
    end
    return nil
end

---Checks if all prerequisite specializations are loaded
-- @param table specializations specializations
-- @return boolean hasPrerequisite true if all prerequisite specializations are loaded
function RMS_BatteryCharger.prerequisitesPresent(specializations)
    return SpecializationUtil.hasSpecialization(PushHandTool, specializations)
end

---Registers the charger, its display, sounds and saved state
function RMS_BatteryCharger.initSpecialization()
    local schema = Vehicle.xmlSchema
    schema:setXMLSpecializationType("RMSBatteryCharger")
    schema:register(XMLValueType.FLOAT, "vehicle.rmsBatteryCharger#maxCurrent", "Maximum output current in amps", 150)
    schema:register(XMLValueType.NODE_INDEX, "vehicle.rmsBatteryCharger#display", "Digital charger display")
    for _, name in ipairs({ "work", "connect", "disconnect" }) do
        SoundManager.registerSampleXMLPaths(schema, "vehicle.rmsBatteryCharger.sounds", name)
    end
    schema:setXMLSpecializationType()
    local saveKey = "vehicles.vehicle(?)." .. RMS_BatteryCharger.SPEC_NAME
    Vehicle.xmlSchemaSavegame:register(XMLValueType.INT, saveKey .. "#state", "Charger state", 0)
    Vehicle.xmlSchemaSavegame:register(XMLValueType.INT, saveKey .. "#mode", "Charge or starting aid process", 0)
    Vehicle.xmlSchemaSavegame:register(XMLValueType.FLOAT, saveKey .. "#cooldownMs", "Remaining start recovery time", 0)
    Vehicle.xmlSchemaSavegame:register(XMLValueType.STRING, saveKey .. "#targetUniqueId", "Persistent target vehicle id")
    Vehicle.xmlSchemaSavegame:register(XMLValueType.STRING, saveKey .. "#reason", "Last interruption reason")
    Vehicle.xmlSchemaSavegame:register(XMLValueType.FLOAT, saveKey .. "#soc", "Last measured state of charge", 0)
    Vehicle.xmlSchemaSavegame:register(XMLValueType.FLOAT, saveKey .. "#voltage", "Last measured circuit voltage", 0)
end

---Registers the overwritten functions of the charger
-- @param table vehicleType vehicle type
function RMS_BatteryCharger.registerOverwrittenFunctions(vehicleType)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "showInfo", RMS_BatteryCharger.showInfo)
end

---Registers the event listeners of the charger
-- @param table vehicleType vehicle type
function RMS_BatteryCharger.registerEventListeners(vehicleType)
    for _, name in ipairs({"onLoad", "onDelete", "onUpdate", "onRegisterActionEvents", "onVehicleSettingChanged", "saveToXMLFile", "onReadStream", "onWriteStream",
        "onReadUpdateStream", "onWriteUpdateStream"}) do
        SpecializationUtil.registerEventListener(vehicleType, name, RMS_BatteryCharger)
    end
end

local DISPLAY_INDICATIONS = { "lcdUnitV", "lcdUnitA", "lcdVoltage12V", "lcdVoltage24V", "lcdPulseTronic", "lcdBatteryAUTO",
    "lcdCurrentBOOST", "lcdCurrentRangeOutline", "lcdSocOutline", "lcdPhase4", "lcdPhase5", "lcdPhase7",
    "lcdProcessSTART" }

---Returns the display indications lit for the state and the target
-- @param table spec charger specialization
-- @return table names names of the indications lit
local function getShownIndications(spec)
    local shown = { "lcdUnitV", "lcdUnitA" }
    local target = RMS_Utils.getConnectedObject(spec)
    if not canDisconnect(spec) or not getIsAlive(target) or not target.finishedLoading then
        return shown
    end
    local isTwentyFourVolt = target.spec_RealisticMechanicalSystems.electricalRating.seriesBatteries > 1
    table.insert(shown, isTwentyFourVolt and "lcdVoltage24V" or "lcdVoltage12V")
    if spec.mode == RMS_BatteryCharger.MODE.START then
        table.insert(shown, "lcdProcessSTART")
        return shown
    end
    table.insert(shown, "lcdPulseTronic")
    table.insert(shown, "lcdBatteryAUTO")
    table.insert(shown, "lcdCurrentBOOST")
    table.insert(shown, "lcdCurrentRangeOutline")
    table.insert(shown, "lcdSocOutline")
    table.insert(shown, spec.state == RMS_BatteryCharger.STATE.FULL and "lcdPhase7" or spec.soc < 0.8 and "lcdPhase4" or "lcdPhase5")
    return shown
end

---Called on loading
-- @param table? savegame savegame
function RMS_BatteryCharger:onLoad(savegame)
    configurePushDrive(self)
    local spec = self[RMS_BatteryCharger.SPEC_TABLE_NAME]
    spec.maxCurrent = self.xmlFile:getValue("vehicle.rmsBatteryCharger#maxCurrent", 150)
    spec.state = RMS_BatteryCharger.STATE.IDLE
    spec.mode = RMS_BatteryCharger.MODE.CHARGE
    spec.cooldownUntilMs = 0
    spec.wasCranking = false
    spec.targetUniqueId = ""
    spec.reason = ""
    spec.current = 0
    spec.soc = 0
    spec.voltage = 0
    spec.insufficient = false
    spec.dirtyFlag = self:getNextDirtyFlag()
    if savegame ~= nil and not savegame.resetVehicles then
        local key = savegame.key .. "." .. RMS_BatteryCharger.SPEC_NAME
        spec.state = math.clamp(savegame.xmlFile:getValue(key .. "#state", 0), 0, 3)
        spec.mode = savegame.xmlFile:getValue(key .. "#mode", 0) == RMS_BatteryCharger.MODE.START
            and RMS_BatteryCharger.MODE.START or RMS_BatteryCharger.MODE.CHARGE
        spec.cooldownUntilMs = g_currentMission.time
            + math.clamp(savegame.xmlFile:getValue(key .. "#cooldownMs", 0), 0, RMS_BatteryCharger.START_COOLDOWN_MS)
        spec.targetUniqueId = savegame.xmlFile:getValue(key .. "#targetUniqueId", "")
        spec.reason = savegame.xmlFile:getValue(key .. "#reason", "")
        spec.soc = math.clamp(savegame.xmlFile:getValue(key .. "#soc", 0), 0, 1)
        spec.voltage = savegame.xmlFile:getValue(key .. "#voltage", 0)
        spec.pendingResume = spec.state == RMS_BatteryCharger.STATE.CHARGING
        spec.pendingTarget = spec.state == RMS_BatteryCharger.STATE.FULL and spec.targetUniqueId ~= ""
        if spec.state == RMS_BatteryCharger.STATE.INTERRUPTED then
            spec.targetUniqueId, spec.soc, spec.voltage = "", 0, 0
        end
    end
    if self.isClient then
        local display = self.xmlFile:getValue("vehicle.rmsBatteryCharger#display", nil, self.components, self.i3dMappings)
        spec.display = {voltage = {}, current = {}, bars = {}, indications = {}}
        for _, measurement in ipairs({"voltage", "current"}) do
            for digit = 0, 2 do
                local node = getChild(display, measurement .. "Digit" .. digit)
                local segments = {}
                for segment = 0, 6 do
                    segments[segment + 1] = getChild(node, measurement .. "Digit" .. digit .. "Segment" .. segment)
                end
                spec.display[measurement][digit + 1] = segments
            end
        end
        for bar = 0, 4 do spec.display.bars[bar + 1] = getChild(display, "socBar" .. bar) end
        for _, name in ipairs(DISPLAY_INDICATIONS) do
            spec.display.indications[name] = getChild(display, name)
        end
        spec.sample = g_soundManager:loadSampleFromXML(self.xmlFile, "vehicle.rmsBatteryCharger.sounds", "work",
            self.baseDirectory, self.components, 0, AudioGroup.VEHICLE, self.i3dMappings, self)
        spec.connectSample = g_soundManager:loadSampleFromXML(self.xmlFile, "vehicle.rmsBatteryCharger.sounds", "connect",
            self.baseDirectory, self.components, 1, AudioGroup.VEHICLE, self.i3dMappings, self)
        spec.disconnectSample = g_soundManager:loadSampleFromXML(self.xmlFile, "vehicle.rmsBatteryCharger.sounds", "disconnect",
            self.baseDirectory, self.components, 1, AudioGroup.VEHICLE, self.i3dMappings, self)
        spec.activatable = RMS_BatteryChargerActivatable.new(self)
        g_currentMission.activatableObjectsSystem:addActivatable(spec.activatable)
    end
    if spec.pendingResume or spec.pendingTarget then
        self:raiseActive()
    end
end

---Returns why a charger may not be connected to a machine, "ok" when it may
-- @param table charger battery charger
-- @param table? target machine
-- @param integer? mode RMS_BatteryCharger.MODE, the charger's own by default
-- @return string result "ok" or an error code
function RMS_BatteryCharger.validate(charger, target, mode)
    if not getIsAlive(charger) or not getIsAlive(target) then
        return "unavailable"
    end
    local targetSpec = target.spec_RealisticMechanicalSystems
    if targetSpec == nil or targetSpec.isExcludedVehicle or not targetSpec.systems.electrical.enabled then
        return "unavailable"
    end
    local accessHandler = g_currentMission.accessHandler
    if not accessHandler:canFarmAccess(charger:getOwnerFarmId(), target) and not accessHandler:canFarmAccess(target:getOwnerFarmId(), charger) then
        return "access"
    end
    if getDistanceToMachine(charger, target) > RMS_BatteryCharger.MAX_DISTANCE then
        return "distance"
    end
    local spec = charger[RMS_BatteryCharger.SPEC_TABLE_NAME]
    local connected = canDisconnect(spec) and RMS_Utils.getConnectedObject(spec) == target
    local process = mode or spec.mode
    if process == RMS_BatteryCharger.MODE.START and targetSpec.electricalRating.seriesBatteries > 1 then return "voltage" end
    if (not connected or process ~= RMS_BatteryCharger.MODE.START)
        and (target:getIsMotorStarted() or getIsCranking(target)) then return "motor" end
    if not connected and math.abs(target:getLastSpeed()) > RMS_BatteryCharger.STOPPED_SPEED then
        return "moving"
    end
    if targetSpec.externalPowerConnection ~= nil then
        return "cables"
    end
    local other = RMS_BatteryCharger.getConnectedCharger(target)
    if other ~= nil and other ~= charger then return "busy" end
    return "ok"
end

---Stops the charger in a state, disconnected unless full
-- @param table charger battery charger
-- @param integer? state RMS_BatteryCharger.STATE, idle by default
-- @param string? reason error code of an interruption
-- @param boolean? suppressNotification true to notify nobody
function RMS_BatteryCharger.stop(charger, state, reason, suppressNotification)
    local spec = charger[RMS_BatteryCharger.SPEC_TABLE_NAME]
    local previousState, previousInsufficient, previousTarget = spec.state, spec.insufficient, spec.target
    local targetSpec = spec.target ~= nil and spec.target.spec_RealisticMechanicalSystems or nil
    spec.state = state or RMS_BatteryCharger.STATE.IDLE
    if targetSpec ~= nil and targetSpec.batteryCharger == charger and not canDisconnect(spec) then
        targetSpec.batteryCharger = nil
    end
    spec.reason = reason or ""
    spec.pendingResume = false
    spec.pendingTarget = false
    spec.current = 0
    spec.insufficient = false
    if not canDisconnect(spec) then
        spec.wasCranking = false
        spec.target = nil
        spec.targetUniqueId = ""
        spec.soc = 0
        spec.voltage = 0
    end
    publishState(charger, spec)
    if not suppressNotification then notifyChange(charger, previousState, previousInsufficient, previousTarget) end
    charger:raiseActive()
end

---Connects the charger to a target, or returns why not
-- @param table charger battery charger
-- @param table target machine
-- @param table? requester requester context, nil when restoring
-- @param boolean? restoring true when a saved link is restored
-- @param integer? mode RMS_BatteryCharger.MODE, the charger's own by default
-- @return string result "ok" or an error code
function RMS_BatteryCharger.tryStart(charger, target, requester, restoring, mode)
    local spec = charger[RMS_BatteryCharger.SPEC_TABLE_NAME]
    if not restoring and not g_currentMission.accessHandler:canFarmAccess(requester.farmId, target) then
        return "access"
    end
    mode = mode or spec.mode
    local reason = RMS_BatteryCharger.validate(charger, target, mode)
    if reason ~= "ok" then return reason end
    if not restoring and canDisconnect(spec) then return "busy" end
    if mode ~= RMS_BatteryCharger.MODE.START and target.spec_RealisticMechanicalSystems.batterySoc >= 1 then return "full" end
    local previousState, previousInsufficient = spec.state, spec.insufficient
    spec.mode = mode
    spec.target = target
    spec.wasCranking = false
    spec.targetUniqueId = target:getUniqueId()
    spec.state = RMS_BatteryCharger.STATE.CHARGING
    spec.reason = ""
    spec.pendingResume = false
    spec.soc = target.spec_RealisticMechanicalSystems.batterySoc
    spec.voltage = target.spec_RealisticMechanicalSystems.systemVoltageV
    spec.current = 0
    spec.insufficient = false
    target.spec_RealisticMechanicalSystems.batteryCharger = charger
    publishState(charger, spec)
    if not restoring then notifyChange(charger, previousState, previousInsufficient) end
    charger:raiseActive()
    return "ok"
end

---Returns the current the charger gives its target
-- @param table target machine
-- @param boolean isCranking true while the machine cranks
-- @return float current current (A)
function RMS_BatteryCharger.getAvailableCurrent(target, isCranking)
    local charger = target.spec_RealisticMechanicalSystems.batteryCharger
    local spec = charger[RMS_BatteryCharger.SPEC_TABLE_NAME]
    if spec.state ~= RMS_BatteryCharger.STATE.CHARGING then return 0 end
    -- A pending disconnect must supply no current
    if RMS_BatteryCharger.validate(charger, target) ~= "ok" then return 0 end
    if spec.mode == RMS_BatteryCharger.MODE.START then
        if target:getIsMotorStarted() then return 0 end
        return isCranking and RMS_BatteryCharger.START_CURRENT_A or spec.maxCurrent
    end
    local rating = target.spec_RealisticMechanicalSystems.electricalRating
    return rating.seriesBatteries > 1 and math.min(spec.maxCurrent, RMS_BatteryCharger.MAX_CURRENT_24V_A) or spec.maxCurrent
end

---Called after the battery step: publishes the measurements, stopped once the battery is full
-- @param table target machine
-- @param float current current the charger gives (A)
-- @param float netCurrent current into the battery (A)
function RMS_BatteryCharger.onBatteryUpdated(target, current, netCurrent)
    local charger = target.spec_RealisticMechanicalSystems.batteryCharger
    local spec = charger[RMS_BatteryCharger.SPEC_TABLE_NAME]
    local battery = target.spec_RealisticMechanicalSystems
    local previousInsufficient = spec.insufficient
    local insufficient = spec.mode ~= RMS_BatteryCharger.MODE.START
        and spec.state == RMS_BatteryCharger.STATE.CHARGING and netCurrent <= 0 and battery.batterySoc < 1
    local changed = math.abs(spec.publishedCurrent - current) >= 0.1
        or math.abs(spec.publishedSoc - battery.batterySoc) >= 0.001
        or math.abs(spec.publishedVoltage - battery.systemVoltageV) >= 0.02
        or spec.publishedInsufficient ~= insufficient
    spec.current = current
    spec.soc = battery.batterySoc
    spec.voltage = battery.systemVoltageV
    spec.insufficient = insufficient
    if changed then
        publishState(charger, spec)
        notifyChange(charger, spec.state, previousInsufficient)
    end
    if spec.mode ~= RMS_BatteryCharger.MODE.START and spec.state == RMS_BatteryCharger.STATE.CHARGING
        and battery.batterySoc >= 1 then RMS_BatteryCharger.stop(charger, RMS_BatteryCharger.STATE.FULL) end
end

---Called on update: restores the saved link, watches it, drives the display and sound
function RMS_BatteryCharger:onUpdate()
    local spec = self[RMS_BatteryCharger.SPEC_TABLE_NAME]
    -- Motorized supplies push physics only
    if self.isServer then
        local motorState = self:getMotorState()
        if self:getIsControlled() and (motorState == MotorState.OFF or motorState == MotorState.IGNITION) then
            self:startMotor(false)
        elseif not self:getIsControlled() and (motorState == MotorState.STARTING or motorState == MotorState.ON) then
            self:stopMotor(false)
        end
    end
    if self.isServer and spec.pendingTarget then
        local system = g_currentMission.vehicleSystem
        if system.loadedVehicles == nil then
            local target = system:getVehicleByUniqueId(spec.targetUniqueId)
            spec.pendingTarget = false
            local reason = RMS_BatteryCharger.validate(self, target)
            if reason == "ok" then
                spec.target = target
                target.spec_RealisticMechanicalSystems.batteryCharger = self
                publishState(self, spec)
            else
                RMS_BatteryCharger.stop(self, RMS_BatteryCharger.STATE.INTERRUPTED, reason, true)
            end
        end
    end
    if self.isServer and spec.pendingResume then
        local system = g_currentMission.vehicleSystem
        if system.loadedVehicles == nil then
            local target = system:getVehicleByUniqueId(spec.targetUniqueId)
            local reason = RMS_BatteryCharger.tryStart(self, target, nil, true)
            if reason == "full" then
                spec.target = target
                target.spec_RealisticMechanicalSystems.batteryCharger = self
                spec.soc = target.spec_RealisticMechanicalSystems.batterySoc
                spec.voltage = target.spec_RealisticMechanicalSystems.systemVoltageV
                RMS_BatteryCharger.stop(self, RMS_BatteryCharger.STATE.FULL, nil, true)
            elseif reason ~= "ok" then
                RMS_BatteryCharger.stop(self, RMS_BatteryCharger.STATE.INTERRUPTED, reason, true)
            end
        end
    end
    if self.isServer and canDisconnect(spec) and not spec.pendingResume and not spec.pendingTarget then
        local reason = RMS_BatteryCharger.validate(self, spec.target)
        if reason ~= "ok" then RMS_BatteryCharger.stop(self, RMS_BatteryCharger.STATE.INTERRUPTED, reason) end
    end
    if self.isServer and spec.mode == RMS_BatteryCharger.MODE.START and canDisconnect(spec) then
        local target = RMS_Utils.getConnectedObject(spec)
        if getIsAlive(target) then
            local cranking = getIsCranking(target) and not target:getIsMotorStarted()
            if spec.wasCranking and not cranking then
                spec.cooldownUntilMs = g_currentMission.time + RMS_BatteryCharger.START_COOLDOWN_MS
                publishState(self, spec)
            end
            spec.wasCranking = cranking
        end
    end
    if self.isServer and canDisconnect(spec) and not spec.pendingTarget then
        local target = RMS_Utils.getConnectedObject(spec)
        if getIsAlive(target) then
            local voltage = target.spec_RealisticMechanicalSystems.systemVoltageV
            local changed = math.abs(spec.publishedVoltage - voltage) >= 0.02
                or math.floor(spec.publishedVoltage * 10 + 0.5) ~= math.floor(voltage * 10 + 0.5)
            spec.voltage = voltage
            if changed then publishState(self, spec) end
        end
    end
    if spec.state == RMS_BatteryCharger.STATE.CHARGING or spec.pendingResume or spec.pendingTarget
        or spec.state == RMS_BatteryCharger.STATE.FULL and getIsAlive(RMS_Utils.getConnectedObject(spec)) then self:raiseActive() end
    if self.isClient then
        local voltage = math.floor(math.clamp(spec.voltage, 0, 99.9) * 10 + 0.5)
        local current = math.floor(math.clamp(spec.current, 0, 999) + 0.5)
        local bars = spec.soc <= 0 and 0 or math.min(math.ceil(spec.soc * 5), 5)
        if voltage ~= spec.display.voltageValue or current ~= spec.display.currentValue or bars ~= spec.display.barCount then
            -- seven segment masks of the digits 0 to 9
            local masks = {63, 6, 91, 79, 102, 109, 125, 7, 127, 111}
            for measurement, value in pairs({voltage = voltage, current = current}) do
                for digit, segments in ipairs(spec.display[measurement]) do
                    local number = math.floor(value / 10 ^ (3 - digit)) % 10
                    local mask = masks[number + 1]
                    local leadingBlank = digit == 1 and value < 100 or measurement == "current" and digit == 2 and value < 10
                    for segment, node in ipairs(segments) do
                        setVisibility(node, not leadingBlank and math.floor(mask / 2 ^ (segment - 1)) % 2 == 1)
                    end
                end
            end
            for bar, node in ipairs(spec.display.bars) do
                setVisibility(node, bar <= bars)
            end
            spec.display.voltageValue, spec.display.currentValue, spec.display.barCount = voltage, current, bars
        end
        local shown = getShownIndications(spec)
        local signature = table.concat(shown, " ")
        if signature ~= spec.display.indicationSignature then
            spec.display.indicationSignature = signature
            local isShown = {}
            for _, name in ipairs(shown) do
                isShown[name] = true
            end
            for name, node in pairs(spec.display.indications) do
                setVisibility(node, isShown[name] == true)
            end
        end
        RMS_SoundManager.setSamplePlaying(spec.sample, spec.current > 0)
    end
end

---Clears the engine keys of the push drive
function RMS_BatteryCharger:onRegisterActionEvents()
    if self.isClient then
        self:clearActionEventsTable(self.spec_motorized.actionEvents)
    end
end

---Keeps the push drive automatic on a setting change
-- @param integer gameSettingId setting changed
function RMS_BatteryCharger:onVehicleSettingChanged(gameSettingId)
    if gameSettingId == GameSettings.SETTING.DIRECTION_CHANGE_MODE
        or gameSettingId == GameSettings.SETTING.GEAR_SHIFT_MODE then
        configurePushDrive(self)
    end
end

---Called on deleting, also before onLoad when the game is left during loading
function RMS_BatteryCharger:onDelete()
    local spec = self[RMS_BatteryCharger.SPEC_TABLE_NAME]
    if self.isServer and spec.dirtyFlag ~= nil then
        RMS_BatteryCharger.stop(self, nil, nil, true)
    end
    if self.isClient then
        g_currentMission.activatableObjectsSystem:removeActivatable(spec.activatable)
        g_soundManager:deleteSamples({ spec.sample, spec.connectSample, spec.disconnectSample })
    end
end

---Saves the state, mode, recovery time and target
-- @param table xmlFile savegame file
-- @param string key key of the specialization
function RMS_BatteryCharger:saveToXMLFile(xmlFile, key)
    local spec = self[RMS_BatteryCharger.SPEC_TABLE_NAME]
    xmlFile:setValue(key .. "#state", spec.state)
    xmlFile:setValue(key .. "#mode", spec.mode)
    xmlFile:setValue(key .. "#cooldownMs", math.max(spec.cooldownUntilMs - g_currentMission.time, 0))
    xmlFile:setValue(key .. "#targetUniqueId", spec.targetUniqueId)
    xmlFile:setValue(key .. "#reason", spec.reason)
    xmlFile:setValue(key .. "#soc", spec.soc)
    xmlFile:setValue(key .. "#voltage", spec.voltage)
end

---Writes the state of the charger
-- @param table spec charger specialization
-- @param integer streamId stream id
local function writeState(spec, streamId)
    streamWriteUIntN(streamId, spec.state, 2)
    streamWriteUIntN(streamId, spec.mode, 1)
    streamWriteFloat32(streamId, math.max(spec.cooldownUntilMs - g_currentMission.time, 0))
    streamWriteString(streamId, spec.targetUniqueId)
    local hasTarget = getIsAlive(spec.target)
    streamWriteBool(streamId, hasTarget)
    if hasTarget then NetworkUtil.writeNodeObject(streamId, spec.target) end
    streamWriteString(streamId, spec.reason)
    streamWriteFloat32(streamId, spec.current)
    streamWriteFloat32(streamId, spec.soc)
    streamWriteFloat32(streamId, spec.voltage)
    streamWriteBool(streamId, spec.insufficient)
end

---Reads the state of the charger
-- @param table spec charger specialization
-- @param integer streamId stream id
local function readState(spec, streamId)
    spec.state = streamReadUIntN(streamId, 2)
    spec.mode = streamReadUIntN(streamId, 1)
    spec.cooldownUntilMs = g_currentMission.time + streamReadFloat32(streamId)
    spec.targetUniqueId = streamReadString(streamId)
    -- Savegame IDs are local; network IDs can resolve after load
    spec.targetObjectId = nil
    if streamReadBool(streamId) then spec.targetObjectId = NetworkUtil.readNodeObjectId(streamId) end
    spec.reason = streamReadString(streamId)
    spec.current = streamReadFloat32(streamId)
    spec.soc = streamReadFloat32(streamId)
    spec.voltage = streamReadFloat32(streamId)
    spec.insufficient = streamReadBool(streamId)
end

---Called on server side on join
-- @param integer streamId stream id
function RMS_BatteryCharger:onWriteStream(streamId)
    writeState(self[RMS_BatteryCharger.SPEC_TABLE_NAME], streamId)
end

---Called on client side on join
-- @param integer streamId stream id
function RMS_BatteryCharger:onReadStream(streamId)
    readState(self[RMS_BatteryCharger.SPEC_TABLE_NAME], streamId)
    self:raiseActive()
end

---Called on server side on update
-- @param integer streamId stream id
-- @param Connection connection connection
-- @param integer dirtyMask dirty mask
function RMS_BatteryCharger:onWriteUpdateStream(streamId, connection, dirtyMask)
    if not connection:getIsServer() then
        local spec = self[RMS_BatteryCharger.SPEC_TABLE_NAME]
        local changed = bitAND(dirtyMask, spec.dirtyFlag) ~= 0
        streamWriteBool(streamId, changed)
        if changed then writeState(spec, streamId) end
    end
end

---Called on client side on update
-- @param integer streamId stream id
-- @param integer timestamp timestamp
-- @param Connection connection connection
function RMS_BatteryCharger:onReadUpdateStream(streamId, timestamp, connection)
    if connection:getIsServer() and streamReadBool(streamId) then
        local spec = self[RMS_BatteryCharger.SPEC_TABLE_NAME]
        local previousState, previousInsufficient, previousTarget = spec.state, spec.insufficient, RMS_Utils.getConnectedObject(spec)
        readState(spec, streamId)
        notifyChange(self, previousState, previousInsufficient, previousTarget)
        self:raiseActive()
    end
end

---Adds the state and measurements of the charger to the info box
-- @param function superFunc original function
-- @param table box info box
function RMS_BatteryCharger:showInfo(superFunc, box)
    superFunc(self, box)
    local spec = self[RMS_BatteryCharger.SPEC_TABLE_NAME]
    local stateKeys = {"rms_charger_idle", "rms_charger_charging", "rms_charger_full", "rms_charger_interrupted"}
    local state = g_i18n:getText(stateKeys[spec.state + 1])
    if spec.mode == RMS_BatteryCharger.MODE.START and canDisconnect(spec) then
        local target = RMS_Utils.getConnectedObject(spec)
        if getIsAlive(target) and target:getIsMotorStarted() then
            state = g_i18n:getText("rms_charger_start_running")
        elseif getIsAlive(target) and getIsCranking(target) then
            state = g_i18n:getText("rms_charger_start_active")
        elseif spec.cooldownUntilMs > g_currentMission.time then
            state = string.format(g_i18n:getText("rms_charger_start_countdown"),
                math.ceil((spec.cooldownUntilMs - g_currentMission.time) / 1000))
        else
            state = g_i18n:getText("rms_charger_start_ready")
        end
    elseif spec.insufficient then state = g_i18n:getText("rms_charger_consumers") end
    box:addLine(g_i18n:getText("rms_charger_status"), state)
    if spec.targetUniqueId ~= "" then
        box:addLine(g_i18n:getText("rms_charger_battery"), string.format("%d%%", math.floor(spec.soc * 100)))
        box:addLine(g_i18n:getText("rms_charger_voltage"), g_i18n:formatNumber(spec.voltage, 1) .. " V")
        box:addLine(g_i18n:getText("rms_charger_current"), g_i18n:formatNumber(spec.current, 1) .. " A")
    end
end

---Activatable of a charger: the PC, a tool space or the charger itself
RMS_BatteryChargerActivatable = {}
local RMS_BatteryChargerActivatable_mt = Class(RMS_BatteryChargerActivatable)

---Creates the activatable of a charger
-- @param table charger battery charger
-- @return table self instance of the activatable
function RMS_BatteryChargerActivatable.new(charger)
    local self = setmetatable({}, RMS_BatteryChargerActivatable_mt)
    self.charger = charger
    self.activateText = g_i18n:getText("rms_charger_start")
    return self
end

---Tells whether the player stands in reach of a tool space
-- @param table charger battery charger
-- @return boolean isInReach true in reach of a tool space
local function getIsInToolReach(charger)
    for _, holder in ipairs(charger.spec_handToolHolders.handToolHolders) do
        if holder.isPlayerInRange then
            return true
        end
    end
    return false
end

---Returns the distance where a ray enters the first box, the limit when it misses them
-- @param entityId node node the boxes are given in
-- @param table boxes min x y z, max x y z of each box
-- @param float x origin x (world)
-- @param float y origin y (world)
-- @param float z origin z (world)
-- @param float dx direction x (world)
-- @param float dy direction y (world)
-- @param float dz direction z (world)
-- @param float limit farthest distance looked at
-- @return float distance distance along the ray
local function getRayBoxesEntry(node, boxes, x, y, z, dx, dy, dz, limit)
    local origin = { worldToLocal(node, x, y, z) }
    local direction = { worldDirectionToLocal(node, dx, dy, dz) }
    for _, box in ipairs(boxes) do
        local near, far = 0, limit
        for axis = 1, 3 do
            local low, high = box[axis], box[axis + 3]
            if math.abs(direction[axis]) < 1e-9 then
                if origin[axis] < low or origin[axis] > high then
                    far = -1
                end
            else
                local t1, t2 = (low - origin[axis]) / direction[axis], (high - origin[axis]) / direction[axis]
                near, far = math.max(near, math.min(t1, t2)), math.min(far, math.max(t1, t2))
            end
            if near > far then
                break
            end
        end
        if near <= far and near < limit then
            limit = near
        end
    end
    return limit
end

---Returns whether the player looks at the PC, and the tool space looked at
-- @param table charger battery charger
-- @param table player player
-- @return boolean isPc true when the player looks at the PC
-- @return table? space tool space looked at
local function getLookedAt(charger, player)
    local x, y, z, dx, dy, dz = player.targeter:getLastLookRay()
    if x == nil then
        return false, nil
    end
    local first, isPc, space = math.huge, false, nil
    local pcRoot = RMS_DiagnosticTool.getPcRoot(charger)
    if pcRoot ~= nil then
        first = getRayBoxesEntry(pcRoot, RMS_BatteryChargerAimData.PC, x, y, z, dx, dy, dz, first)
        isPc = first < math.huge
    end
    for _, holder in ipairs(charger.spec_handToolHolders.handToolHolders) do
        local boxes = RMS_BatteryChargerAimData.TOOLS[holder.holderType]
        if holder:getHandTool() ~= nil then
            local entry = getRayBoxesEntry(holder.holderNode, boxes, x, y, z, dx, dy, dz, first)
            if entry < first then
                first, isPc, space = entry, false, holder
            end
        end
    end
    if first < math.huge and getRayBoxesEntry(charger.rootNode, RMS_BatteryChargerAimData.TROLLEY, x, y, z, dx, dy, dz, first) < first then
        return false, nil
    end
    return isPc, space
end

---Returns the tool space, the action and the tool the player may take or store
-- @param table charger battery charger
-- @param table player player
-- @param table? lookedSpace tool space looked at
-- @return table? space tool space
-- @return string? action "take" or "store"
-- @return table? tool hand tool
local function getToolSpaceAction(charger, player, lookedSpace)
    local heldTool = player:getHeldHandTool()
    if heldTool == nil then
        if lookedSpace ~= nil and lookedSpace.isPlayerInRange and player:getCanPickupHandTool(lookedSpace:getHandTool()) then
            return lookedSpace, "take", lookedSpace:getHandTool()
        end
        return nil
    end
    for _, holder in ipairs(charger.spec_handToolHolders.handToolHolders) do
        if holder.isPlayerInRange and holder:getHandTool() == nil and holder:getCanPickupHandTool(heldTool) then
            return holder, "store", heldTool
        end
    end
    return nil
end

---Returns the distance to the charger, 0 while a tool or the PC is in reach
-- @param float x player x (world)
-- @param float y player y (world)
-- @param float z player z (world)
-- @return float distance distance (m)
function RMS_BatteryChargerActivatable:getDistance(x, y, z)
    if g_localPlayer ~= nil and (getIsInToolReach(self.charger) or getLookedAt(self.charger, g_localPlayer)) then
        return 0
    end
    local tx, ty, tz = getWorldTranslation(self.charger.rootNode)
    return MathUtil.vector3Length(tx - x, ty - y, tz - z)
end

---Tells whether the local player may use the charger
-- @return boolean isActivatable true when the player may use it
function RMS_BatteryChargerActivatable:getIsActivatable()
    return getIsAlive(self.charger) and g_localPlayer ~= nil and not g_localPlayer:getIsInVehicle()
        and self.charger.isAddedToPhysics
        and g_currentMission.accessHandler:canPlayerAccess(self.charger)
        and getDistance(self.charger, g_localPlayer) <= RMS_BatteryCharger.MAX_DISTANCE
end

---Picks the action and its text from what the player looks at
-- @param float dt time since the last frame (ms)
function RMS_BatteryChargerActivatable:update(dt)
    local lookedSpace
    self.isPcLookedAt, lookedSpace = getLookedAt(self.charger, g_localPlayer)
    self.toolSpace, self.toolAction, self.tool = nil, nil, nil
    if not self.isPcLookedAt then
        self.toolSpace, self.toolAction, self.tool = getToolSpaceAction(self.charger, g_localPlayer, lookedSpace)
    end
    if self.isPcLookedAt then
        self.activateText = g_i18n:getText("rms_diagnostic_open")
    elseif self.toolAction == "store" then
        self.activateText = string.format(self.toolSpace.activatable.storeText, self.tool.typeDesc)
    elseif self.toolAction == "take" then
        self.activateText = string.format(self.toolSpace.activatable.takeText, self.tool.typeDesc)
    else
        self.activateText = g_i18n:getText(canDisconnect(getSpec(self.charger)) and "rms_charger_disconnect" or "rms_charger_start")
    end
end

---Runs the action: PC, tool, disconnect or the mode choice
function RMS_BatteryChargerActivatable:run()
    if self.isPcLookedAt then
        RMS_DiagnosticScreen.show(self.charger)
    elseif self.toolAction == "store" then
        self.tool:setHolder(self.toolSpace)
    elseif self.toolAction == "take" then
        self.tool:setHolder(g_localPlayer)
        g_localPlayer:setCurrentHandTool(self.tool)
    elseif canDisconnect(getSpec(self.charger)) then
        RMS_BatteryChargerRequestEvent.send(self.charger, nil, true)
    else
        OptionDialog.show(function(index)
            if index == 1 then self:connect(RMS_BatteryCharger.MODE.CHARGE)
            elseif index == 2 then self:connect(RMS_BatteryCharger.MODE.START) end
        end, g_i18n:getText("rms_charger_start"), g_i18n:getText("rms_charger_name"),
            {g_i18n:getText("rms_charger_mode_charge"), g_i18n:getText("rms_charger_mode_start")})
    end
end

---Connects the charger to the nearest machine, or offers the machines in reach
-- @param integer mode RMS_BatteryCharger.MODE
function RMS_BatteryChargerActivatable:connect(mode)
    local candidates = {}
    local nearest, nearestReason, nearestDistance = nil, nil, math.huge
    for _, vehicle in pairs(g_currentMission.vehicleSystem.vehicles) do
        if getSpec(vehicle) == nil then
            local reason = RMS_BatteryCharger.validate(self.charger, vehicle, mode)
            if reason == "ok" and (mode == RMS_BatteryCharger.MODE.START
                or vehicle.spec_RealisticMechanicalSystems.batterySoc < 1) then
                table.insert(candidates, vehicle)
            elseif vehicle.spec_RealisticMechanicalSystems ~= nil then
                local distance = getDistanceToMachine(self.charger, vehicle)
                if distance <= RMS_BatteryCharger.MAX_DISTANCE and distance < nearestDistance then
                    nearest, nearestReason, nearestDistance = vehicle, reason == "ok" and "full" or reason, distance
                end
            end
        end
    end
    table.sort(candidates, function(a, b) return getDistanceToMachine(self.charger, a) < getDistanceToMachine(self.charger, b) end)
    ---Sends the connection to the machine picked
    -- @param integer index machine picked, 0 when the dialog is closed
    local function choose(index)
        if candidates[index] ~= nil then
            RMS_BatteryChargerRequestEvent.send(self.charger, candidates[index], false, mode)
        end
    end
    if #candidates == 0 then
        if nearest ~= nil then
            InfoDialog.show(nearest:getFullName() .. "\n" .. g_i18n:getText("rms_charger_error_" .. nearestReason))
        else
            InfoDialog.show(g_i18n:getText("rms_charger_no_vehicle"))
        end
    elseif #candidates == 1 then
        choose(1)
    else
        local options = {}
        for _, vehicle in ipairs(candidates) do
            table.insert(options, string.format("%s, %s m, %d%%", vehicle:getFullName(),
                g_i18n:formatNumber(getDistanceToMachine(self.charger, vehicle), 1),
                math.floor(vehicle.spec_RealisticMechanicalSystems.batterySoc * 100)))
        end
        OptionDialog.show(choose, g_i18n:getText("rms_charger_select"), g_i18n:getText("rms_charger_name"), options)
    end
end
