-- Copyright © 2026 Squallqt. All rights reserved.

---Event sending the drive mode, lock request and park brake of a driver to the server
RMS_DrivetrainEvent = {}
local RMS_DrivetrainEvent_mt = Class(RMS_DrivetrainEvent, Event)

InitEventClass(RMS_DrivetrainEvent, "RMS_DrivetrainEvent")

---Create instance of Event class
-- @return table self instance of class event
function RMS_DrivetrainEvent.emptyNew()
    return Event.new(RMS_DrivetrainEvent_mt)
end

---Create new instance of event from the current drivetrain state of the vehicle
-- @param table vehicle vehicle
-- @return table self instance of event
function RMS_DrivetrainEvent.new(vehicle)
    local self = RMS_DrivetrainEvent.emptyNew()
    local state = RMS_Drivetrain.getState(vehicle)

    self.vehicle = vehicle
    self.driveMode = state.driveMode
    self.diffLockRequested = state.diffLockRequested
    self.parkBrake = state.parkBrake
    return self
end

---Writes event data to a stream
-- @param integer streamId stream id
-- @param Connection connection connection the event goes to
function RMS_DrivetrainEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObject(streamId, self.vehicle)
    streamWriteUIntN(streamId, self.driveMode, 2)
    streamWriteBool(streamId, self.diffLockRequested)
    streamWriteBool(streamId, self.parkBrake)
end

---Reads event data from a stream
-- @param integer streamId stream id
-- @param Connection connection connection the event comes from
function RMS_DrivetrainEvent:readStream(streamId, connection)
    self.vehicle = NetworkUtil.readNodeObject(streamId)
    self.driveMode = streamReadUIntN(streamId, 2)
    self.diffLockRequested = streamReadBool(streamId)
    self.parkBrake = streamReadBool(streamId)
    self:run(connection)
end

---Applies the state on the server when it comes from the driver of the vehicle
-- @param Connection connection connection the event comes from
function RMS_DrivetrainEvent:run(connection)
    if self.vehicle == nil or not self.vehicle:getIsSynchronized() then
        return
    end

    if self.vehicle:getOwnerConnection() ~= connection then
        return
    end

    RMS_Drivetrain.setDrivetrainState(self.vehicle, self.driveMode, self.diffLockRequested, self.parkBrake)
end

---Send the drivetrain state from a client to the server
-- @param table vehicle vehicle
function RMS_DrivetrainEvent.sendEvent(vehicle)
    g_client:getServerConnection():sendEvent(RMS_DrivetrainEvent.new(vehicle))
end
