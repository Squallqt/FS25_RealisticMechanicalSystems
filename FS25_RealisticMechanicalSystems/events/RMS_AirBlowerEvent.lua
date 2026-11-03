-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---Whether a player blows with an air blower, and at which machine
RMS_AirBlowerEvent = {}
local RMS_AirBlowerEvent_mt = Class(RMS_AirBlowerEvent, Event)

InitEventClass(RMS_AirBlowerEvent, "RMS_AirBlowerEvent")

function RMS_AirBlowerEvent.emptyNew()
    return Event.new(RMS_AirBlowerEvent_mt)
end

function RMS_AirBlowerEvent.new(blower, isBlowing, target, distance)
    local self = RMS_AirBlowerEvent.emptyNew()
    self.blower = blower
    self.isBlowing = isBlowing
    self.target = target
    self.distance = distance
    return self
end

function RMS_AirBlowerEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObject(streamId, self.blower)
    streamWriteBool(streamId, self.isBlowing)
    NetworkUtil.writeNodeObject(streamId, self.target)
    streamWriteFloat32(streamId, self.distance)
end

function RMS_AirBlowerEvent:readStream(streamId, connection)
    self.blower = NetworkUtil.readNodeObject(streamId)
    self.isBlowing = streamReadBool(streamId)
    self.target = NetworkUtil.readNodeObject(streamId)
    self.distance = streamReadFloat32(streamId)
    self:run(connection)
end

function RMS_AirBlowerEvent:run(connection)
    local blower = self.blower
    if blower == nil or not blower:getIsSynchronized() or blower.setRMSAirBlowerState == nil then
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
function RMS_AirBlowerEvent.send(blower, isBlowing, target, distance)
    if g_server ~= nil then
        blower:setRMSAirBlowerState(isBlowing, target, distance)
        g_server:broadcastEvent(RMS_AirBlowerEvent.new(blower, isBlowing, target, distance), nil, nil, blower)
    else
        g_client:getServerConnection():sendEvent(RMS_AirBlowerEvent.new(blower, isBlowing, target, distance))
    end
end
