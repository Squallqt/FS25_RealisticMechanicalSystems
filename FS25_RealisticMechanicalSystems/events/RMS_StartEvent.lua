-- Copyright © 2026 Squallqt. All rights reserved.

---Start states to the clients, a driver's start request to the server
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
    if not connection:getIsServer() then
        streamWriteUIntN(streamId, self.state, 3)
        streamWriteBool(streamId, self.preheatWasRequired)
    end
end


---Reads event data from a stream.
function RMS_StartEvent:readStream(streamId, connection)
    self.vehicle = NetworkUtil.readNodeObject(streamId)
    if connection:getIsServer() then
        self.state = streamReadUIntN(streamId, 3)
        self.preheatWasRequired = streamReadBool(streamId)
    end
    self:run(connection)
end


---Run action on receiving side
function RMS_StartEvent:run(connection)
    if self.vehicle == nil or not self.vehicle:getIsSynchronized() then
        return
    end
    if connection:getIsServer() then
        RMS_Start.onStateReceived(self.vehicle, self.state, self.preheatWasRequired)
    else
        self.vehicle:startMotor()
    end
end


---Broadcasts a start state from the server
function RMS_StartEvent.sendEvent(vehicle, state, preheatWasRequired)
    if g_server ~= nil then
        g_server:broadcastEvent(RMS_StartEvent.new(vehicle, state, preheatWasRequired), nil, nil, vehicle)
    end
end


---Asks the server alone for a start, never the other players
function RMS_StartEvent.sendRequest(vehicle)
    g_client:getServerConnection():sendEvent(RMS_StartEvent.new(vehicle))
end
