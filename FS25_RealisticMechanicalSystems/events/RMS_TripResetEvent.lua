-- Copyright © 2026 Squallqt. All rights reserved.

---Event resetting the trip meter of a vehicle
RMS_TripResetEvent = {}
local RMS_TripResetEvent_mt = Class(RMS_TripResetEvent, Event)

InitEventClass(RMS_TripResetEvent, "RMS_TripResetEvent")

---Create instance of Event class
-- @return table self instance of class event
function RMS_TripResetEvent.emptyNew()
    return Event.new(RMS_TripResetEvent_mt)
end

---Create new instance of event
-- @param table vehicle vehicle
-- @return table self instance of event
function RMS_TripResetEvent.new(vehicle)
    local self = RMS_TripResetEvent.emptyNew()
    self.vehicle = vehicle
    return self
end

---Writes event data to a stream
-- @param integer streamId stream id
-- @param Connection connection connection the event goes to
function RMS_TripResetEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObject(streamId, self.vehicle)
end

---Reads event data from a stream
-- @param integer streamId stream id
-- @param Connection connection connection the event comes from
function RMS_TripResetEvent:readStream(streamId, connection)
    self.vehicle = NetworkUtil.readNodeObject(streamId)
    self:run(connection)
end

---Resets the meter, the server passing the reset on to the other players
-- @param Connection connection connection the event comes from
function RMS_TripResetEvent:run(connection)
    if self.vehicle == nil or not self.vehicle:getIsSynchronized() then
        return
    end

    if not connection:getIsServer() then
        g_server:broadcastEvent(RMS_TripResetEvent.new(self.vehicle), nil, connection, self.vehicle)
    end
    RealisticMechanicalSystems.resetTripMeter(self.vehicle, true)
end

---Sends the reset to the server, or to the clients
-- @param table vehicle vehicle
-- @param boolean? noEventSend true to send nothing
function RMS_TripResetEvent.sendEvent(vehicle, noEventSend)
    if noEventSend then
        return
    end

    if g_server ~= nil then
        g_server:broadcastEvent(RMS_TripResetEvent.new(vehicle), nil, nil, vehicle)
    else
        g_client:getServerConnection():sendEvent(RMS_TripResetEvent.new(vehicle))
    end
end
