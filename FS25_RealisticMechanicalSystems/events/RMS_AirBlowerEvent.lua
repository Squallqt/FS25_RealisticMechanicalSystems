-- Copyright © 2026 Squallqt. All rights reserved.

---Event carrying whether an air blower blows, and at which machine
RMS_AirBlowerEvent = {}
local RMS_AirBlowerEvent_mt = Class(RMS_AirBlowerEvent, Event)

InitEventClass(RMS_AirBlowerEvent, "RMS_AirBlowerEvent")

---Create instance of Event class
-- @return table self instance of class event
function RMS_AirBlowerEvent.emptyNew()
    return Event.new(RMS_AirBlowerEvent_mt)
end

---Create new instance of event
-- @param table blower air blower
-- @param boolean isBlowing true while the blower blows
-- @param table? target machine blown at, nil if none
-- @param float distance distance to the machine (m)
-- @return table self instance of event
function RMS_AirBlowerEvent.new(blower, isBlowing, target, distance)
    local self = RMS_AirBlowerEvent.emptyNew()
    self.blower = blower
    self.isBlowing = isBlowing
    self.target = target
    self.distance = distance
    return self
end

---Writes event data to a stream
-- @param integer streamId stream id
-- @param Connection connection connection the event goes to
function RMS_AirBlowerEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObject(streamId, self.blower)
    streamWriteBool(streamId, self.isBlowing)
    NetworkUtil.writeNodeObject(streamId, self.target)
    streamWriteFloat32(streamId, self.distance)
end

---Reads event data from a stream
-- @param integer streamId stream id
-- @param Connection connection connection the event comes from
function RMS_AirBlowerEvent:readStream(streamId, connection)
    self.blower = NetworkUtil.readNodeObject(streamId)
    self.isBlowing = streamReadBool(streamId)
    self.target = NetworkUtil.readNodeObject(streamId)
    self.distance = streamReadFloat32(streamId)
    self:run(connection)
end

---Applies the state, the server passing it on to the other players
-- @param Connection connection connection the event comes from
function RMS_AirBlowerEvent:run(connection)
    local blower = self.blower
    if blower == nil or not blower:getIsSynchronized() then
        return
    end

    if not connection:getIsServer() then
        local player = g_currentMission.connectionsToPlayer[connection]
        if player == nil or blower:getCarryingPlayer() ~= player then
            return
        end
        g_server:broadcastEvent(RMS_AirBlowerEvent.new(blower, self.isBlowing, self.target, self.distance), nil, connection, blower)
    end
    blower:setRMSAirBlowerState(self.isBlowing, self.target, self.distance)
end

---Sends the state of a blower through the server to every player
-- @param table blower air blower
-- @param boolean isBlowing true while the blower blows
-- @param table? target machine blown at, nil if none
-- @param float distance distance to the machine (m)
function RMS_AirBlowerEvent.send(blower, isBlowing, target, distance)
    if g_server ~= nil then
        blower:setRMSAirBlowerState(isBlowing, target, distance)
        g_server:broadcastEvent(RMS_AirBlowerEvent.new(blower, isBlowing, target, distance), nil, nil, blower)
    else
        g_client:getServerConnection():sendEvent(RMS_AirBlowerEvent.new(blower, isBlowing, target, distance))
    end
end
