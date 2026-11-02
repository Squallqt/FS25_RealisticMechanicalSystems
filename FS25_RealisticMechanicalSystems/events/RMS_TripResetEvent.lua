-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---Event resetting the trip meter of a vehicle
RMS_TripResetEvent = {}
local RMS_TripResetEvent_mt = Class(RMS_TripResetEvent, Event)

InitEventClass(RMS_TripResetEvent, "RMS_TripResetEvent")

---Create instance of Event class
function RMS_TripResetEvent.emptyNew()
    return Event.new(RMS_TripResetEvent_mt)
end

---Create new instance of event
function RMS_TripResetEvent.new(vehicle)
    local self = RMS_TripResetEvent.emptyNew()
    self.vehicle = vehicle
    return self
end

---Writes the vehicle
function RMS_TripResetEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObject(streamId, self.vehicle)
end

---Reads the vehicle
function RMS_TripResetEvent:readStream(streamId, connection)
    self.vehicle = NetworkUtil.readNodeObject(streamId)
    self:run(connection)
end

---Run action on receiving side
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
