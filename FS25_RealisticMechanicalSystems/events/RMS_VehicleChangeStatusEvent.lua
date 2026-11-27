-- Copyright © 2026 Squallqt. All rights reserved.

---Event sending the service state of a vehicle from the server to the clients
RMS_VehicleChangeStatusEvent = {}
local RMS_VehicleChangeStatusEvent_mt = Class(RMS_VehicleChangeStatusEvent, Event)
MessageType.RMS_VEHICLE_CHANGE_STATUS = nextMessageTypeId()

InitEventClass(RMS_VehicleChangeStatusEvent, "RMS_VehicleChangeStatusEvent")


---Create instance of Event class
-- @return table self instance of class event
function RMS_VehicleChangeStatusEvent.emptyNew()
    return Event.new(RMS_VehicleChangeStatusEvent_mt)
end


---Create new instance of event from the current service state of the vehicle
-- @param table vehicle vehicle
-- @param string notificationText text of the notification, none if empty
-- @param table? logEntry log entry added with the state
-- @return table self instance of event
function RMS_VehicleChangeStatusEvent.new(vehicle, notificationText, logEntry)
    local self = RMS_VehicleChangeStatusEvent.emptyNew()
    self.vehicle = vehicle
    self.notificationText = notificationText
    self.serializedLogEntry = logEntry ~= nil and RMS_Utils.serializeMaintenanceLogEntry(logEntry) or ""

    local spec = vehicle.spec_RealisticMechanicalSystems
    self.currentState = spec.currentState
    self.maintenanceTimer = spec.maintenanceTimer
    self.progressStepIndex = spec.pendingProgressStepIndex
    self.progressTotalTime = spec.pendingProgressTotalTime
    self.progressElapsedTime = spec.pendingProgressElapsedTime
    return self
end


---Writes event data to a stream
-- @param integer streamId stream id
-- @param Connection connection connection the event goes to
function RMS_VehicleChangeStatusEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObject(streamId, self.vehicle)
    streamWriteString(streamId, self.notificationText)
    streamWriteString(streamId, self.currentState)
    streamWriteFloat32(streamId, self.maintenanceTimer)
    streamWriteInt32(streamId, math.floor(RealisticMechanicalSystems.sanitizeNumber(self.progressStepIndex, 0, 0)))
    streamWriteFloat32(streamId, RealisticMechanicalSystems.sanitizeNumber(self.progressTotalTime, 0, 0))
    streamWriteFloat32(streamId, RealisticMechanicalSystems.sanitizeNumber(self.progressElapsedTime, 0, 0))
    streamWriteString(streamId, self.serializedLogEntry)
end


---Reads event data from a stream
-- @param integer streamId stream id
-- @param Connection connection connection the event comes from
function RMS_VehicleChangeStatusEvent:readStream(streamId, connection)
    self.vehicle = NetworkUtil.readNodeObject(streamId)
    self.notificationText = streamReadString(streamId)
    self.currentState = streamReadString(streamId)
    self.maintenanceTimer = streamReadFloat32(streamId)
    self.progressStepIndex = streamReadInt32(streamId)
    self.progressTotalTime = streamReadFloat32(streamId)
    self.progressElapsedTime = streamReadFloat32(streamId)
    self.serializedLogEntry = streamReadString(streamId)
    self:run(connection)
end


---Run action on receiving side
-- @param Connection connection connection the event comes from
function RMS_VehicleChangeStatusEvent:run(connection)
    if self.vehicle ~= nil and self.vehicle:getIsSynchronized() then
        local spec = self.vehicle.spec_RealisticMechanicalSystems
        spec.currentState = self.currentState
        spec.maintenanceTimer = self.maintenanceTimer
        spec.maintenanceTimerTime = RMS_Thermal.getWorldTimeMS()
        spec.pendingProgressStepIndex = self.progressStepIndex
        spec.pendingProgressTotalTime = self.progressTotalTime
        spec.pendingProgressElapsedTime = self.progressElapsedTime
        if spec.currentState == RealisticMechanicalSystems.STATUS.READY then
            RMS_Bodywork.syncPreview(self.vehicle)
        end

        if self.serializedLogEntry ~= "" then
            local entry = RMS_Utils.deserializeMaintenanceLogEntry(self.serializedLogEntry)
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

        self.vehicle:recalculateAndApplyEffects()
        self.vehicle:recalculateAndApplyIndicators()

        if self.notificationText ~= "" and g_currentMission:getFarmId() == self.vehicle.ownerFarmId then
            g_currentMission.hud:addSideNotification({1, 1, 1, 1}, self.notificationText)
            RMS_SoundManager.playSample(RMS_Main.samples.maintenanceCompleted2D)
        end

        g_messageCenter:publish(MessageType.RMS_VEHICLE_CHANGE_STATUS, self.vehicle)
    end
end


---Broadcast the status change from the server to the clients of the vehicle
-- @param table vehicle vehicle
-- @param string? notificationText text of the notification
-- @param table? logEntry log entry added with the state
function RMS_VehicleChangeStatusEvent.send(vehicle, notificationText, logEntry)
    g_server:broadcastEvent(RMS_VehicleChangeStatusEvent.new(vehicle, notificationText or "", logEntry), nil, nil, vehicle)
end
