-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---Sends each state of an engine start from the server to the clients
RMS_StartEvent = {}
local RMS_StartEvent_mt = Class(RMS_StartEvent, Event)

InitEventClass(RMS_StartEvent, "RMS_StartEvent")


---Create instance of Event class
function RMS_StartEvent.emptyNew()
    return Event.new(RMS_StartEvent_mt)
end


---Create new instance of event
function RMS_StartEvent.new(vehicle, state, preheatWasRequired)
    local self = RMS_StartEvent.emptyNew()
    self.vehicle = vehicle
    self.state = state
    self.preheatWasRequired = preheatWasRequired == true
    return self
end


---Writes event data to a stream.
function RMS_StartEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObject(streamId, self.vehicle)
    streamWriteUIntN(streamId, self.state, 3)
    streamWriteBool(streamId, self.preheatWasRequired)
end


---Reads event data from a stream.
function RMS_StartEvent:readStream(streamId, connection)
    self.vehicle = NetworkUtil.readNodeObject(streamId)
    self.state = streamReadUIntN(streamId, 3)
    self.preheatWasRequired = streamReadBool(streamId)
    self:run(connection)
end


---Run action on receiving side
function RMS_StartEvent:run(connection)
    if self.vehicle ~= nil and self.vehicle:getIsSynchronized() then
        RMS_Start.onStateReceived(self.vehicle, self.state, self.preheatWasRequired)
    end
end


---Broadcasts a start state from the server
function RMS_StartEvent.sendEvent(vehicle, state, preheatWasRequired)
    if g_server ~= nil then
        g_server:broadcastEvent(RMS_StartEvent.new(vehicle, state, preheatWasRequired), nil, nil, vehicle)
    end
end
