-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---Synchronizes a vehicle service status and carries an optional notification and log entry
RMS_VehicleChangeStatusEvent = {}
local RMS_VehicleChangeStatusEvent_mt = Class(RMS_VehicleChangeStatusEvent, Event)
MessageType.RMS_VEHICLE_CHANGE_STATUS = nextMessageTypeId()

InitEventClass(RMS_VehicleChangeStatusEvent, "RMS_VehicleChangeStatusEvent")


---Create instance of Event class
-- @return table self instance of class event
function RMS_VehicleChangeStatusEvent.emptyNew()
    return Event.new(RMS_VehicleChangeStatusEvent_mt)
end


---Create new instance of event
-- @param table vehicle vehicle
-- @param string? notificationText text shown as a side notification
-- @param table? logEntry maintenance log entry completed with this status change
-- @return table self instance of class event
function RMS_VehicleChangeStatusEvent.new(vehicle, notificationText, logEntry)
    local self = RMS_VehicleChangeStatusEvent.emptyNew()
    self.vehicle = vehicle
    self.notificationText = notificationText or ""
    self.serializedLogEntry = logEntry ~= nil and RMS_Utils.serializeMaintenanceLogEntry(logEntry) or ""

    local spec = vehicle ~= nil and vehicle.spec_RealisticMechanicalSystems or nil
    self.currentState = spec ~= nil and spec.currentState or ""
    self.plannedState = spec ~= nil and spec.plannedState or ""
    self.maintenanceTimer = spec ~= nil and spec.maintenanceTimer or 0
    self.progressStepIndex = spec ~= nil and spec.pendingProgressStepIndex or 0
    self.progressTotalTime = spec ~= nil and spec.pendingProgressTotalTime or 0
    self.progressElapsedTime = spec ~= nil and spec.pendingProgressElapsedTime or 0
    return self
end


---Called on server side on join
-- @param integer streamId streamId
-- @param Connection connection connection
function RMS_VehicleChangeStatusEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObject(streamId, self.vehicle)
    streamWriteString(streamId, self.notificationText or "")
    streamWriteString(streamId, self.currentState or "")
    streamWriteString(streamId, self.plannedState or "")
    streamWriteFloat32(streamId, RealisticMechanicalSystems.sanitizeNumber(self.maintenanceTimer, 0, 0))
    streamWriteInt32(streamId, math.floor(RealisticMechanicalSystems.sanitizeNumber(self.progressStepIndex, 0, 0)))
    streamWriteFloat32(streamId, RealisticMechanicalSystems.sanitizeNumber(self.progressTotalTime, 0, 0))
    streamWriteFloat32(streamId, RealisticMechanicalSystems.sanitizeNumber(self.progressElapsedTime, 0, 0))
    streamWriteString(streamId, self.serializedLogEntry or "")
end


---Called on client side on join
-- @param integer streamId streamId
-- @param Connection connection connection
function RMS_VehicleChangeStatusEvent:readStream(streamId, connection)
    self.vehicle = NetworkUtil.readNodeObject(streamId)
    self.notificationText = streamReadString(streamId)
    self.currentState = streamReadString(streamId)
    self.plannedState = streamReadString(streamId)
    self.maintenanceTimer = RealisticMechanicalSystems.sanitizeNumber(streamReadFloat32(streamId), 0, 0)
    self.progressStepIndex = math.floor(RealisticMechanicalSystems.sanitizeNumber(streamReadInt32(streamId), 0, 0))
    self.progressTotalTime = RealisticMechanicalSystems.sanitizeNumber(streamReadFloat32(streamId), 0, 0)
    self.progressElapsedTime = RealisticMechanicalSystems.sanitizeNumber(streamReadFloat32(streamId), 0, 0)
    self.serializedLogEntry = streamReadString(streamId)
    self:run(connection)
end


---Reapplies effects and indicators, notifies the owning farm, and relays the event on the server
-- @param Connection connection connection
function RMS_VehicleChangeStatusEvent:run(connection)
    if self.vehicle ~= nil and self.vehicle:getIsSynchronized() then
        local spec = self.vehicle.spec_RealisticMechanicalSystems
        if connection:getIsServer() and spec ~= nil then
            spec.currentState = self.currentState
            spec.plannedState = self.plannedState
            spec.maintenanceTimer = self.maintenanceTimer
            spec.pendingProgressStepIndex = self.progressStepIndex
            spec.pendingProgressTotalTime = self.progressTotalTime
            spec.pendingProgressElapsedTime = self.progressElapsedTime

            if self.serializedLogEntry ~= nil and self.serializedLogEntry ~= "" then
                local entry = RMS_Utils.deserializeMaintenanceLogEntry(self.serializedLogEntry)
                if entry ~= nil then
                    spec.maintenanceLog = spec.maintenanceLog or {}
                    local replaced = false
                    for i, existingEntry in ipairs(spec.maintenanceLog) do
                        if existingEntry.id == entry.id then
                            spec.maintenanceLog[i] = entry
                            replaced = true
                            break
                        end
                    end
                    if not replaced then
                        table.insert(spec.maintenanceLog, entry)
                    end
                end
            end
        end

        self.vehicle:recalculateAndApplyEffects()
        self.vehicle:recalculateAndApplyIndicators()

        -- notification and sound for the owning farm only
        if connection:getIsServer() and self.notificationText ~= nil and self.notificationText ~= "" then
            if g_currentMission:getFarmId() == self.vehicle.ownerFarmId and g_currentMission ~= nil and g_currentMission.hud ~= nil then
                g_currentMission.hud:addSideNotification({1, 1, 1, 1}, self.notificationText)
            end
            if g_currentMission:getFarmId() == self.vehicle.ownerFarmId then
                RMS_SoundManager.playSample(RMS_Main.samples.maintenanceCompleted2D)
            end
        end

        g_messageCenter:publish(MessageType.RMS_VEHICLE_CHANGE_STATUS, self.vehicle)
    end

    -- relay to the other clients, only for the farm owning the vehicle
    if not connection:getIsServer() then
        if self.vehicle ~= nil and self.vehicle:getIsSynchronized() then
            local userId = g_currentMission.userManager:getUserIdByConnection(connection)
            local farm = g_farmManager:getFarmByUserId(userId)
            if farm ~= nil and farm.farmId == self.vehicle:getOwnerFarmId() then
                g_server:broadcastEvent(RMS_VehicleChangeStatusEvent.new(self.vehicle, self.notificationText), nil, connection, self.vehicle)
            end
        end
    end
end


---Broadcast the status change from the server to the clients of the vehicle
-- @param table vehicle vehicle
-- @param string? notificationText text shown as a side notification
-- @param table? logEntry maintenance log entry completed with this status change
function RMS_VehicleChangeStatusEvent.send(vehicle, notificationText, logEntry)
    if g_server ~= nil then
        g_server:broadcastEvent(RMS_VehicleChangeStatusEvent.new(vehicle, notificationText or "", logEntry), nil, nil, vehicle)
    end
end
