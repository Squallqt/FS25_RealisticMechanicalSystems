-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---Event reversing the fan of a vehicle
RMS_FanReversalEvent = {}
local RMS_FanReversalEvent_mt = Class(RMS_FanReversalEvent, Event)

InitEventClass(RMS_FanReversalEvent, "RMS_FanReversalEvent")

---Create instance of Event class
-- @return table self instance of class event
function RMS_FanReversalEvent.emptyNew()
    return Event.new(RMS_FanReversalEvent_mt)
end

---Create new instance of event
-- @param table vehicle vehicle
-- @return table self instance of class event
function RMS_FanReversalEvent.new(vehicle)
    local self = RMS_FanReversalEvent.emptyNew()
    self.vehicle = vehicle
    return self
end

---Writes event data to a stream.
-- @param integer streamId streamId
-- @param Connection connection connection
function RMS_FanReversalEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObject(streamId, self.vehicle)
end

---Reads event data from a stream.
-- @param integer streamId streamId
-- @param Connection connection connection
function RMS_FanReversalEvent:readStream(streamId, connection)
    self.vehicle = NetworkUtil.readNodeObject(streamId)
    self:run(connection)
end

---Run action on receiving side
-- @param Connection connection connection
function RMS_FanReversalEvent:run(connection)
    local vehicle = self.vehicle
    if vehicle ~= nil and vehicle:getIsSynchronized() then
        RMS_Thermal.startFanReversal(vehicle)
    end
end

---Reverses the fan on the server, or asks the server for it
-- @param table vehicle vehicle
function RMS_FanReversalEvent.send(vehicle)
    if g_server ~= nil then
        RMS_Thermal.startFanReversal(vehicle)
    else
        g_client:getServerConnection():sendEvent(RMS_FanReversalEvent.new(vehicle))
    end
end
