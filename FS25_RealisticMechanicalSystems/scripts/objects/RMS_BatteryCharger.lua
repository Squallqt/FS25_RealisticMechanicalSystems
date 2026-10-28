-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---Mobile battery charger.
RMS_BatteryCharger = {}
RMS_BatteryCharger.SPEC_NAME = "FS25_RealisticMechanicalSystems.rmsBatteryCharger"
RMS_BatteryCharger.SPEC_TABLE_NAME = "spec_" .. RMS_BatteryCharger.SPEC_NAME
RMS_BatteryCharger.MAX_DISTANCE = 4
RMS_BatteryCharger.STOPPED_SPEED = 0.1
RMS_BatteryCharger.MOVEMENT_TOLERANCE = 0.05
RMS_BatteryCharger.STATE = { IDLE = 0, CHARGING = 1, FULL = 2, INTERRUPTED = 3 }
RMS_BatteryCharger.MODE = { CHARGE = 0, START = 1 }
RMS_BatteryCharger.START_CURRENT_A = 200
RMS_BatteryCharger.MAX_CURRENT_24V_A = 80
RMS_BatteryCharger.START_COOLDOWN_MS = 30000

---
local function getSpec(charger)
    return charger ~= nil and charger[RMS_BatteryCharger.SPEC_TABLE_NAME] or nil
end

---
local function canDisconnect(spec)
    return spec.state == RMS_BatteryCharger.STATE.CHARGING or spec.state == RMS_BatteryCharger.STATE.FULL
end

---Returns the distance between two objects, math.huge without a node
function RMS_BatteryCharger.getDistance(a, b)
    if a == nil or b == nil or a.rootNode == nil or b.rootNode == nil then
        return math.huge
    end
    local ax, ay, az = getWorldTranslation(a.rootNode)
    local bx, by, bz = getWorldTranslation(b.rootNode)
    return MathUtil.vector3Length(ax - bx, ay - by, az - bz)
end
local getDistance = RMS_BatteryCharger.getDistance

---Tells whether an object still stands in the world
function RMS_BatteryCharger.getIsAlive(object)
    return object ~= nil and object.isDeleted ~= true and object.isDeleting ~= true
        and object.markedForDeletion ~= true and object.rootNode ~= nil and entityExists(object.rootNode)
end
local getIsAlive = RMS_BatteryCharger.getIsAlive

---
local function getIsCranking(target)
    return RMS_Electrical.getIsStarting(target)
end

---Returns where an object stands
function RMS_BatteryCharger.getPosition(object)
    return {getWorldTranslation(object.rootNode)}
end
local getPosition = RMS_BatteryCharger.getPosition

---Tells whether an object left the place it was plugged at
function RMS_BatteryCharger.hasMoved(object, position)
    local x, y, z = getWorldTranslation(object.rootNode)
    return MathUtil.vector3Length(x - position[1], y - position[2], z - position[3])
        > RMS_BatteryCharger.MOVEMENT_TOLERANCE
end
local hasMoved = RMS_BatteryCharger.hasMoved

---
local function configurePushDrive(charger)
    local motorized = charger.spec_motorized
    if motorized ~= nil and motorized.motor ~= nil then
        motorized.directionChangeMode = VehicleMotor.DIRECTION_CHANGE_MODE_AUTOMATIC
        motorized.gearShiftMode = VehicleMotor.SHIFT_MODE_AUTOMATIC
        motorized.motor:setDirectionChangeMode(motorized.directionChangeMode)
        motorized.motor:setGearShiftMode(motorized.gearShiftMode)
    end
end

---
local function publishState(charger, spec)
    spec.publishedCurrent = spec.current
    spec.publishedSoc = spec.soc
    spec.publishedVoltage = spec.voltage
    spec.publishedInsufficient = spec.insufficient
    charger:raiseDirtyFlags(spec.dirtyFlag)
end

---
local function getTargetObject(spec)
    if spec.targetObjectId ~= nil then
        return NetworkUtil.getObject(spec.targetObjectId)
    end
    return spec.target
end

---Notifies a live change of the charger, never the join or save snapshot
local function notifyChange(charger, previousState, previousInsufficient, previousTarget)
    if not charger.isClient or g_currentMission.hud == nil
        or g_currentMission.hud.addSideNotification == nil
        or charger:getOwnerFarmId() ~= g_currentMission:getFarmId() then
        return
    end
    local spec = assert(getSpec(charger))
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
        local target = getTargetObject(spec) or previousTarget
        local name = target ~= nil and target:getFullName() or charger:getFullName()
        g_currentMission.hud:addSideNotification(HUD.COLOR.DEFAULT,
            string.format(g_i18n:getText("rms_hud_vehicle_notification"), name, message))
    end
end

---Finds the charger connected to a target
function RMS_BatteryCharger.getConnectedCharger(target)
    local battery = target.spec_RealisticMechanicalSystems
    if battery ~= nil and getIsAlive(battery.batteryCharger) then return battery.batteryCharger end
    if not target.isServer then
        for _, charger in pairs(g_currentMission.vehicleSystem.vehicles) do
            local spec = getSpec(charger)
            if spec ~= nil and canDisconnect(spec) and getIsAlive(charger) and getTargetObject(spec) == target then
                return charger
            end
        end
    end
    return nil
end

---Returns why the connected charger blocks a start
function RMS_BatteryCharger.getStartBlockReason(target)
    if target:getIsMotorStarted() then return nil end
    local charger = RMS_BatteryCharger.getConnectedCharger(target)
    local spec = getSpec(charger)
    if spec == nil then return nil end
    if spec.mode ~= RMS_BatteryCharger.MODE.START then return "rms_charger_unplug_before_start" end
    if (spec.cooldownUntilMs or 0) > (g_currentMission.time or 0) then
        return "rms_charger_start_wait"
    end
    return nil
end

---
function RMS_BatteryCharger.prerequisitesPresent(specializations)
    return SpecializationUtil.hasSpecialization(PushHandTool, specializations)
end

---
function RMS_BatteryCharger.initSpecialization()
    local schema = Vehicle.xmlSchema
    schema:setXMLSpecializationType("RMSBatteryCharger")
    schema:register(XMLValueType.FLOAT, "vehicle.rmsBatteryCharger#maxCurrent", "Maximum output current in amps", 150)
    schema:register(XMLValueType.NODE_INDEX, "vehicle.rmsBatteryCharger#display", "Digital charger display")
    SoundManager.registerSampleXMLPaths(schema, "vehicle.rmsBatteryCharger.sounds", "work")
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

---
function RMS_BatteryCharger.registerOverwrittenFunctions(vehicleType)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "showInfo", RMS_BatteryCharger.showInfo)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "addToPhysics", RMS_BatteryCharger.addToPhysics)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "removeFromPhysics", RMS_BatteryCharger.removeFromPhysics)
end

local function setIsParked(vehicle, isParked)
    local spec = getSpec(vehicle)
    if spec.isParked == isParked then
        return
    end
    spec.isParked = isParked
    if not isParked then
        for _, jointIndex in ipairs(spec.parkingJoints or {}) do
            removeJoint(jointIndex)
        end
        spec.parkingJoints = nil
        return
    end
    -- Wheels need dynamic bodies; a world joint locks the parked pose.
    spec.parkingJoints = {}
    for _, component in ipairs(vehicle.components) do
        local joint = JointConstructor.new()
        joint:setActors(component.node, 0)
        local x, y, z = getWorldTranslation(component.node)
        joint:setJointWorldPositions(x, y, z, x, y, z)
        for axis = 0, 2 do
            joint:setTranslationLimit(axis, true, 0, 0)
            joint:setRotationLimit(axis, 0, 0)
        end
        joint:setJointWorldAxes(1, 0, 0, 1, 0, 0)
        joint:setJointWorldNormals(0, 1, 0, 0, 1, 0)
        joint:setEnableCollision(false)
        table.insert(spec.parkingJoints, joint:finalize())
    end
end

---Parks the trolley on entering physics unless pushed
function RMS_BatteryCharger:addToPhysics(superFunc)
    if not superFunc(self) then
        return false
    end
    if self.isServer then
        getSpec(self).isParked = nil
        setIsParked(self, not self:getIsControlled())
    end
    return true
end

function RMS_BatteryCharger:removeFromPhysics(superFunc)
    if self.isServer then
        setIsParked(self, false)
    end
    return superFunc(self)
end

---
function RMS_BatteryCharger.registerEventListeners(vehicleType)
    for _, name in ipairs({"onLoad", "onDelete", "onUpdate", "onRegisterActionEvents", "onVehicleSettingChanged", "saveToXMLFile", "onReadStream", "onWriteStream",
        "onReadUpdateStream", "onWriteUpdateStream"}) do
        SpecializationUtil.registerEventListener(vehicleType, name, RMS_BatteryCharger)
    end
end

local DISPLAY_INDICATIONS = { "lcdUnitV", "lcdUnitA", "lcdVoltage12V", "lcdVoltage24V", "lcdPulseTronic", "lcdBatteryAUTO",
    "lcdCurrentBOOST", "lcdCurrentRangeOutline", "lcdSocOutline", "lcdPhase4", "lcdPhase5", "lcdPhase7",
    "lcdProcessSTART" }

local function getShownIndications(spec)
    local shown = { "lcdUnitV", "lcdUnitA" }
    local target = getTargetObject(spec)
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

---
function RMS_BatteryCharger:onLoad(savegame)
    configurePushDrive(self)
    local spec = self[RMS_BatteryCharger.SPEC_TABLE_NAME]
    spec.maxCurrent = math.max(self.xmlFile:getValue("vehicle.rmsBatteryCharger#maxCurrent", 150), 0)
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
        spec.cooldownUntilMs = (g_currentMission.time or 0)
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
        if display ~= nil then
            spec.display = {voltage = {}, current = {}, bars = {}}
            for _, measurement in ipairs({"voltage", "current"}) do
                for digit = 0, 2 do
                    local node = getChild(display, measurement .. "Digit" .. digit)
                    if node ~= 0 then
                        local segments = {}
                        for segment = 0, 6 do
                            segments[segment + 1] = getChild(node, measurement .. "Digit" .. digit .. "Segment" .. segment)
                        end
                        spec.display[measurement][digit + 1] = segments
                    end
                end
            end
            for bar = 0, 4 do spec.display.bars[bar + 1] = getChild(display, "socBar" .. bar) end
            spec.display.indications = {}
            for _, name in ipairs(DISPLAY_INDICATIONS) do
                local node = getChild(display, name)
                if node ~= 0 then
                    spec.display.indications[name] = node
                end
            end
        end
        spec.sample = g_soundManager:loadSampleFromXML(self.xmlFile, "vehicle.rmsBatteryCharger.sounds", "work",
            self.baseDirectory, self.components, 0, AudioGroup.VEHICLE, self.i3dMappings, self)
        spec.activatable = RMS_BatteryChargerActivatable.new(self)
        g_currentMission.activatableObjectsSystem:addActivatable(spec.activatable)
    end
    if spec.pendingResume or spec.pendingTarget then
        self:raiseActive()
    end
end

---Checks the physical link without requiring the player to remain nearby.
function RMS_BatteryCharger.validate(charger, target, mode)
    if not getIsAlive(charger) or not getIsAlive(target) or getSpec(charger) == nil then
        return "unavailable"
    end
    local targetSpec = target.spec_RealisticMechanicalSystems
    if targetSpec == nil or targetSpec.isExcludedVehicle
        or targetSpec.systems == nil or targetSpec.systems.electrical == nil
        or targetSpec.systems.electrical.enabled == false then
        return "unavailable"
    end
    if charger:getOwnerFarmId() ~= target:getOwnerFarmId() then
        return "access"
    end
    if getDistance(charger, target) > RMS_BatteryCharger.MAX_DISTANCE then
        return "distance"
    end
    local spec = assert(getSpec(charger))
    local connected = canDisconnect(spec) and getTargetObject(spec) == target and spec.targetPosition ~= nil
    local process = mode or spec.mode or RMS_BatteryCharger.MODE.CHARGE
    if process == RMS_BatteryCharger.MODE.START and targetSpec.electricalRating.seriesBatteries > 1 then return "voltage" end
    if (not connected or process ~= RMS_BatteryCharger.MODE.START)
        and (target:getIsMotorStarted() or getIsCranking(target)) then return "motor" end
    if connected and hasMoved(target, spec.targetPosition)
        or not connected and math.abs(target:getLastSpeed()) > RMS_BatteryCharger.STOPPED_SPEED then
        return "moving"
    end
    if target:isUnderService() then
        return "service"
    end
    if targetSpec.externalPowerConnection ~= nil then
        return "cables"
    end
    local other = RMS_BatteryCharger.getConnectedCharger(target)
    if other ~= nil and other ~= charger then return "busy" end
    return "ok"
end

---
function RMS_BatteryCharger.stop(charger, state, reason, suppressNotification)
    local spec = getSpec(charger)
    if spec == nil then return end
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
        spec.targetPosition = nil
        spec.wasCranking = false
    end
    if not canDisconnect(spec) then
        spec.target = nil
        spec.targetUniqueId = ""
        spec.soc = 0
        spec.voltage = 0
    end
    publishState(charger, spec)
    if not suppressNotification then notifyChange(charger, previousState, previousInsufficient, previousTarget) end
    charger:raiseActive()
end

---
function RMS_BatteryCharger.tryStart(charger, target, requester, restoring, mode)
    local spec = getSpec(charger)
    if charger == nil or not charger.isServer or spec == nil then return "unavailable" end
    if not restoring and (requester == nil or requester.player == nil
        or requester.farmId == FarmManager.SPECTATOR_FARM_ID
        or requester.farmId ~= charger:getOwnerFarmId()) then
        return "access"
    end
    if not restoring and (requester.player:getIsInVehicle()
        or getDistance(requester.player, charger) > RMS_BatteryCharger.MAX_DISTANCE) then
        return "player_distance"
    end
    mode = mode or spec.mode or RMS_BatteryCharger.MODE.CHARGE
    if mode ~= RMS_BatteryCharger.MODE.CHARGE and mode ~= RMS_BatteryCharger.MODE.START then return "unavailable" end
    local reason = RMS_BatteryCharger.validate(charger, target, mode)
    if reason ~= "ok" then return reason end
    if not restoring and canDisconnect(spec) then return "busy" end
    if mode ~= RMS_BatteryCharger.MODE.START and target.spec_RealisticMechanicalSystems.batterySoc >= 1 then return "full" end
    local previousState, previousInsufficient = spec.state, spec.insufficient
    spec.mode = mode
    spec.target = target
    spec.targetPosition = getPosition(target)
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

---Tells the electrical solver what the charger can give its target
-- @return float chargeA current offered to the consumers and the battery
-- @return float startAidA current offered to the starter alone
function RMS_BatteryCharger.getAvailableCurrent(target, isCranking)
    local charger = target.spec_RealisticMechanicalSystems.batteryCharger
    local spec = getSpec(charger)
    if spec == nil or spec.state ~= RMS_BatteryCharger.STATE.CHARGING then return 0, 0 end
    -- A pending disconnect must supply no current.
    if RMS_BatteryCharger.validate(charger, target) ~= "ok" then return 0, 0 end
    if spec.mode == RMS_BatteryCharger.MODE.START then
        if target:getIsMotorStarted() or not isCranking
            or (spec.cooldownUntilMs or 0) > (g_currentMission.time or 0) then return 0, 0 end
        return 0, RMS_BatteryCharger.START_CURRENT_A
    end
    local rating = target.spec_RealisticMechanicalSystems.electricalRating
    return rating.seriesBatteries > 1 and math.min(spec.maxCurrent, RMS_BatteryCharger.MAX_CURRENT_24V_A) or spec.maxCurrent, 0
end

---Publishes measurements after the one authoritative battery integration.
function RMS_BatteryCharger.onBatteryUpdated(target, current, netCurrent)
    local charger = target.spec_RealisticMechanicalSystems.batteryCharger
    local spec = getSpec(charger)
    if spec == nil then return end
    local battery = target.spec_RealisticMechanicalSystems
    local previousInsufficient = spec.insufficient
    local insufficient = spec.mode ~= RMS_BatteryCharger.MODE.START
        and spec.state == RMS_BatteryCharger.STATE.CHARGING and netCurrent <= 0 and battery.batterySoc < 1
    local changed = spec.publishedCurrent == nil or math.abs(spec.publishedCurrent - current) >= 0.1
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

---
function RMS_BatteryCharger:onUpdate()
    local spec = assert(getSpec(self))
    -- Motorized supplies push physics only.
    if self.isServer and self.spec_motorized ~= nil then
        local motorState = self:getMotorState()
        if self:getIsControlled() and (motorState == MotorState.OFF or motorState == MotorState.IGNITION) then
            self:startMotor(false)
        elseif not self:getIsControlled() and (motorState == MotorState.STARTING or motorState == MotorState.ON) then
            self:stopMotor(false)
        end
    end
    if self.isServer and self.isAddedToPhysics then
        setIsParked(self, not self:getIsControlled())
    end
    if self.isServer and spec.pendingTarget then
        local system = g_currentMission.vehicleSystem
        if system.loadedVehicles == nil then
            local target = system:getVehicleByUniqueId(spec.targetUniqueId)
            spec.pendingTarget = false
            local reason = RMS_BatteryCharger.validate(self, target)
            if reason == "ok" then
                spec.target = target
                spec.targetPosition = getPosition(target)
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
                spec.targetPosition = getPosition(target)
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
        local target = getTargetObject(spec)
        if getIsAlive(target) then
            local cranking = getIsCranking(target) and not target:getIsMotorStarted()
            if spec.wasCranking and not cranking then
                spec.cooldownUntilMs = (g_currentMission.time or 0) + RMS_BatteryCharger.START_COOLDOWN_MS
                publishState(self, spec)
            end
            spec.wasCranking = cranking
            if not cranking and spec.current ~= 0 then
                spec.current = 0
                publishState(self, spec)
            end
        end
    end
    if self.isServer and canDisconnect(spec) and not spec.pendingTarget then
        local target = getTargetObject(spec)
        if getIsAlive(target) and target.spec_RealisticMechanicalSystems ~= nil then
            local voltage = target.spec_RealisticMechanicalSystems.systemVoltageV
            local changed = spec.publishedVoltage == nil or math.abs(spec.publishedVoltage - voltage) >= 0.02
                or math.floor(spec.publishedVoltage * 10 + 0.5) ~= math.floor(voltage * 10 + 0.5)
            spec.voltage = voltage
            if changed then publishState(self, spec) end
        end
    end
    if spec.state == RMS_BatteryCharger.STATE.CHARGING or spec.pendingResume or spec.pendingTarget
        or spec.state == RMS_BatteryCharger.STATE.FULL and getIsAlive(getTargetObject(spec)) then self:raiseActive() end
    if self.isClient then
        if spec.display ~= nil then
            local voltage = math.floor(math.clamp(spec.voltage, 0, 99.9) * 10 + 0.5)
            local current = math.floor(math.clamp(spec.current, 0, 999) + 0.5)
            local bars = spec.soc <= 0 and 0 or math.min(math.ceil(spec.soc * 5), 5)
            if voltage ~= spec.display.voltageValue or current ~= spec.display.currentValue or bars ~= spec.display.barCount then
                local masks = {63, 6, 91, 79, 102, 109, 125, 7, 127, 111}
                for measurement, value in pairs({voltage = voltage, current = current}) do
                    for digit, segments in ipairs(spec.display[measurement]) do
                        local number = math.floor(value / 10 ^ (3 - digit)) % 10
                        local mask = masks[number + 1]
                        local leadingBlank = digit == 1 and value < 100 or measurement == "current" and digit == 2 and value < 10
                        for segment, node in ipairs(segments) do
                            if node ~= nil then
                                setVisibility(node, not leadingBlank and math.floor(mask / 2 ^ (segment - 1)) % 2 == 1)
                            end
                        end
                    end
                end
                for bar, node in ipairs(spec.display.bars) do
                    if node ~= nil then setVisibility(node, bar <= bars) end
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
        end
        if spec.sample ~= nil then
            RMS_SoundManager.setSamplePlaying(spec.sample, spec.current > 0)
        end
    end
end

---
function RMS_BatteryCharger:onRegisterActionEvents()
    if self.isClient then
        self:clearActionEventsTable(self.spec_motorized.actionEvents)
    end
end

---
function RMS_BatteryCharger:onVehicleSettingChanged(gameSettingId)
    if gameSettingId == GameSettings.SETTING.DIRECTION_CHANGE_MODE
        or gameSettingId == GameSettings.SETTING.GEAR_SHIFT_MODE then
        configurePushDrive(self)
    end
end

---
function RMS_BatteryCharger:onDelete()
    if self.isServer then
        setIsParked(self, false)
        RMS_BatteryCharger.stop(self, nil, nil, true)
    end
    local spec = assert(getSpec(self))
    if self.isClient then
        g_currentMission.activatableObjectsSystem:removeActivatable(spec.activatable)
        g_soundManager:deleteSample(spec.sample)
    end
end

---
function RMS_BatteryCharger:saveToXMLFile(xmlFile, key)
    local spec = assert(getSpec(self))
    xmlFile:setValue(key .. "#state", spec.state)
    xmlFile:setValue(key .. "#mode", spec.mode or RMS_BatteryCharger.MODE.CHARGE)
    xmlFile:setValue(key .. "#cooldownMs", math.max((spec.cooldownUntilMs or 0) - (g_currentMission.time or 0), 0))
    xmlFile:setValue(key .. "#targetUniqueId", spec.targetUniqueId)
    xmlFile:setValue(key .. "#reason", spec.reason)
    xmlFile:setValue(key .. "#soc", spec.soc)
    xmlFile:setValue(key .. "#voltage", spec.voltage)
end

---
local function writeState(spec, streamId)
    streamWriteUIntN(streamId, spec.state, 2)
    streamWriteUIntN(streamId, spec.mode or RMS_BatteryCharger.MODE.CHARGE, 1)
    streamWriteFloat32(streamId, math.max((spec.cooldownUntilMs or 0) - (g_currentMission.time or 0), 0))
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

---
local function readState(spec, streamId)
    spec.state = streamReadUIntN(streamId, 2)
    spec.mode = streamReadUIntN(streamId, 1)
    spec.cooldownUntilMs = (g_currentMission.time or 0) + streamReadFloat32(streamId)
    spec.targetUniqueId = streamReadString(streamId)
    -- Savegame IDs are local; network IDs can resolve after load.
    spec.targetObjectId = nil
    if streamReadBool(streamId) then spec.targetObjectId = NetworkUtil.readNodeObjectId(streamId) end
    spec.reason = streamReadString(streamId)
    spec.current = streamReadFloat32(streamId)
    spec.soc = streamReadFloat32(streamId)
    spec.voltage = streamReadFloat32(streamId)
    spec.insufficient = streamReadBool(streamId)
end

---
function RMS_BatteryCharger:onWriteStream(streamId)
    writeState(assert(getSpec(self)), streamId)
end

---
function RMS_BatteryCharger:onReadStream(streamId)
    readState(assert(getSpec(self)), streamId)
    self:raiseActive()
end

---
function RMS_BatteryCharger:onWriteUpdateStream(streamId, connection, dirtyMask)
    if not connection:getIsServer() then
        local spec = assert(getSpec(self))
        local changed = bitAND(dirtyMask, spec.dirtyFlag) ~= 0
        streamWriteBool(streamId, changed)
        if changed then writeState(spec, streamId) end
    end
end

---
function RMS_BatteryCharger:onReadUpdateStream(streamId, timestamp, connection)
    if connection:getIsServer() and streamReadBool(streamId) then
        local spec = assert(getSpec(self))
        local previousState, previousInsufficient, previousTarget = spec.state, spec.insufficient, getTargetObject(spec)
        readState(spec, streamId)
        notifyChange(self, previousState, previousInsufficient, previousTarget)
        self:raiseActive()
    end
end

---
function RMS_BatteryCharger:showInfo(superFunc, box)
    superFunc(self, box)
    local spec = assert(getSpec(self))
    local stateKeys = {"rms_charger_idle", "rms_charger_charging", "rms_charger_full", "rms_charger_interrupted"}
    local state = g_i18n:getText(stateKeys[spec.state + 1])
    if spec.mode == RMS_BatteryCharger.MODE.START and canDisconnect(spec) then
        local target = getTargetObject(spec)
        if getIsAlive(target) and target:getIsMotorStarted() then
            state = g_i18n:getText("rms_charger_start_running")
        elseif getIsAlive(target) and getIsCranking(target) then
            state = g_i18n:getText("rms_charger_start_active")
        elseif (spec.cooldownUntilMs or 0) > (g_currentMission.time or 0) then
            state = string.format(g_i18n:getText("rms_charger_start_countdown"),
                math.ceil(((spec.cooldownUntilMs or 0) - (g_currentMission.time or 0)) / 1000))
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

RMS_BatteryChargerActivatable = {}
local RMS_BatteryChargerActivatable_mt = Class(RMS_BatteryChargerActivatable)

---
function RMS_BatteryChargerActivatable.new(charger)
    local self = setmetatable({}, RMS_BatteryChargerActivatable_mt)
    self.charger = charger
    self.activateText = g_i18n:getText("rms_charger_start")
    return self
end

local function getIsInToolReach(charger)
    for _, holder in ipairs(charger.spec_handToolHolders.handToolHolders) do
        if holder.isPlayerInRange then
            return true
        end
    end
    return false
end

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

-- @return boolean isPcLookedAt
-- @return table? holder space whose stored tool is looked at
local function getLookedAt(charger, player)
    if player.targeter == nil then
        return false, nil
    end
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
        if boxes ~= nil and holder:getHandTool() ~= nil then
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

function RMS_BatteryChargerActivatable:getDistance(x, y, z)
    if g_localPlayer ~= nil and (getIsInToolReach(self.charger) or getLookedAt(self.charger, g_localPlayer)) then
        return 0
    end
    local tx, ty, tz = getWorldTranslation(self.charger.rootNode)
    return MathUtil.vector3Length(tx - x, ty - y, tz - z)
end

---
function RMS_BatteryChargerActivatable:getIsActivatable()
    return getIsAlive(self.charger) and g_localPlayer ~= nil and not g_localPlayer:getIsInVehicle()
        and self.charger.isAddedToPhysics == true
        and self.charger:getOwnerFarmId() == g_currentMission:getFarmId()
        and g_currentMission:getFarmId() ~= FarmManager.SPECTATOR_FARM_ID
        and getDistance(self.charger, g_localPlayer) <= RMS_BatteryCharger.MAX_DISTANCE
end

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
        end, g_i18n:getText("rms_charger_mode_select"), g_i18n:getText("rms_charger_name"),
            {g_i18n:getText("rms_charger_mode_charge"), g_i18n:getText("rms_charger_mode_start")})
    end
end

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
                local distance = getDistance(self.charger, vehicle)
                if distance <= RMS_BatteryCharger.MAX_DISTANCE and distance < nearestDistance then
                    nearest, nearestReason, nearestDistance = vehicle, reason == "ok" and "full" or reason, distance
                end
            end
        end
    end
    table.sort(candidates, function(a, b) return getDistance(self.charger, a) < getDistance(self.charger, b) end)
    ---
    local function choose(index)
        if index ~= nil and candidates[index] ~= nil then
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
                g_i18n:formatNumber(getDistance(self.charger, vehicle), 1),
                math.floor(vehicle.spec_RealisticMechanicalSystems.batterySoc * 100)))
        end
        OptionDialog.show(choose, g_i18n:getText("rms_charger_select"), g_i18n:getText("rms_charger_name"), options)
    end
end
