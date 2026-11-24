-- Copyright © 2026 Squallqt. All rights reserved.

---Event telling the server which player inspects a machine on foot
RMS_FieldInspectionEvent = {}
local RMS_FieldInspectionEvent_mt = Class(RMS_FieldInspectionEvent, Event)

InitEventClass(RMS_FieldInspectionEvent, "RMS_FieldInspectionEvent")

---Create instance of Event class
-- @return table self instance of class event
function RMS_FieldInspectionEvent.emptyNew()
    return Event.new(RMS_FieldInspectionEvent_mt)
end

---Create new instance of event
-- @param table vehicle vehicle
-- @param boolean isActive true while the player inspects it
-- @return table self instance of event
function RMS_FieldInspectionEvent.new(vehicle, isActive)
    local self = RMS_FieldInspectionEvent.emptyNew()
    self.vehicle = vehicle
    self.isActive = isActive
    return self
end

---Writes event data to a stream
-- @param integer streamId stream id
-- @param Connection connection connection the event goes to
function RMS_FieldInspectionEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObject(streamId, self.vehicle)
    streamWriteBool(streamId, self.isActive)
end

---Reads event data from a stream
-- @param integer streamId stream id
-- @param Connection connection connection the event comes from
function RMS_FieldInspectionEvent:readStream(streamId, connection)
    self.vehicle = NetworkUtil.readNodeObject(streamId)
    self.isActive = streamReadBool(streamId)
    self:run(connection)
end

---Applies the inspection state for the player behind the sending connection
-- @param Connection connection connection the event comes from
function RMS_FieldInspectionEvent:run(connection)
    local vehicle = self.vehicle
    if vehicle == nil or not vehicle:getIsSynchronized() then
        return
    end

    local player = g_currentMission.connectionsToPlayer[connection]
    if player ~= nil then
        vehicle:setFieldInspectionPlayerActive(player, self.isActive)
    end
end

---Sends the inspection state through the server
-- @param table vehicle vehicle
-- @param boolean isActive true while the player inspects it
function RMS_FieldInspectionEvent.send(vehicle, isActive)
    if g_server ~= nil then
        vehicle:setFieldInspectionPlayerActive(g_localPlayer, isActive)
    else
        g_client:getServerConnection():sendEvent(RMS_FieldInspectionEvent.new(vehicle, isActive))
    end
end
