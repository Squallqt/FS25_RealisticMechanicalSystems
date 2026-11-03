-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---A clamp asked of the server, or the state of the cables it gives back
RMS_JumperCablesEvent = {}
local RMS_JumperCablesEvent_mt = Class(RMS_JumperCablesEvent, Event)

InitEventClass(RMS_JumperCablesEvent, "RMS_JumperCablesEvent")

function RMS_JumperCablesEvent.emptyNew()
    return Event.new(RMS_JumperCablesEvent_mt)
end

function RMS_JumperCablesEvent.new(cables, state, target, machineA, machineB)
    local self = RMS_JumperCablesEvent.emptyNew()
    self.cables = cables
    self.state = state
    self.target = target
    self.machineA = machineA
    self.machineB = machineB
    return self
end

function RMS_JumperCablesEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObject(streamId, self.cables)
    streamWriteString(streamId, self.state)
    NetworkUtil.writeNodeObject(streamId, self.target)
    NetworkUtil.writeNodeObject(streamId, self.machineA)
    NetworkUtil.writeNodeObject(streamId, self.machineB)
end

function RMS_JumperCablesEvent:readStream(streamId, connection)
    self.cables = NetworkUtil.readNodeObject(streamId)
    self.state = streamReadString(streamId)
    self.target = NetworkUtil.readNodeObject(streamId)
    self.machineA = NetworkUtil.readNodeObject(streamId)
    self.machineB = NetworkUtil.readNodeObject(streamId)
    self:run(connection)
end

function RMS_JumperCablesEvent:run(connection)
    local cables = self.cables
    if cables == nil or not cables:getIsSynchronized() or cables.setRMSJumperCablesState == nil then
        return
    end

    if not connection:getIsServer() then
        local player = g_currentMission.connectionsToPlayer[connection]
        if player ~= nil and cables:getCarryingPlayer() == player then
            cables:clampRMSJumperCables(self.target)
        end
        return
    end
    cables:setRMSJumperCablesState(self.state, self.target, self.machineA, self.machineB)
end

---Asks the server to clamp or unclamp a machine
function RMS_JumperCablesEvent.sendRequest(cables, target)
    g_client:getServerConnection():sendEvent(RMS_JumperCablesEvent.new(cables, "", target))
end

---Gives every player the state of the cables
function RMS_JumperCablesEvent.broadcastState(cables, state, target, machineA, machineB)
    g_server:broadcastEvent(RMS_JumperCablesEvent.new(cables, state, target, machineA, machineB), nil, nil, cables)
end
