-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---Event opening or closing the battery isolator of a vehicle
RMS_BatteryIsolatorEvent = {}
local RMS_BatteryIsolatorEvent_mt = Class(RMS_BatteryIsolatorEvent, Event)

InitEventClass(RMS_BatteryIsolatorEvent, "RMS_BatteryIsolatorEvent")

---Create instance of Event class
-- @return table self instance of class event
function RMS_BatteryIsolatorEvent.emptyNew()
    return Event.new(RMS_BatteryIsolatorEvent_mt)
end

---Create new instance of event
-- @param table vehicle vehicle
-- @param boolean isIsolated true to cut the battery off
-- @return table self instance of class event
function RMS_BatteryIsolatorEvent.new(vehicle, isIsolated)
    local self = RMS_BatteryIsolatorEvent.emptyNew()
    self.vehicle = vehicle
    self.isIsolated = isIsolated == true
    return self
end

---Writes event data to a stream.
-- @param integer streamId streamId
-- @param Connection connection connection
function RMS_BatteryIsolatorEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObject(streamId, self.vehicle)
    streamWriteBool(streamId, self.isIsolated)
end

---Reads event data from a stream.
-- @param integer streamId streamId
-- @param Connection connection connection
function RMS_BatteryIsolatorEvent:readStream(streamId, connection)
    self.vehicle = NetworkUtil.readNodeObject(streamId)
    self.isIsolated = streamReadBool(streamId)
    self:run(connection)
end

---Run action on receiving side
-- @param Connection connection connection
function RMS_BatteryIsolatorEvent:run(connection)
    local vehicle = self.vehicle
    if vehicle ~= nil and vehicle:getIsSynchronized() then
        RMS_Electrical.requestBatteryIsolated(vehicle, self.isIsolated)
    end
end

---Moves the isolator on the server, or asks the server for it
-- @param table vehicle vehicle
-- @param boolean isIsolated true to cut the battery off
function RMS_BatteryIsolatorEvent.send(vehicle, isIsolated)
    if g_server ~= nil then
        RMS_Electrical.requestBatteryIsolated(vehicle, isIsolated)
    else
        g_client:getServerConnection():sendEvent(RMS_BatteryIsolatorEvent.new(vehicle, isIsolated))
    end
end
