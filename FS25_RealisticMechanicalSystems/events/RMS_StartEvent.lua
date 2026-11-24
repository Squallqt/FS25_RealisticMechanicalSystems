-- Copyright © 2026 Squallqt. All rights reserved.

---Event carrying start states to the clients, and a driver's start request to the server
RMS_StartEvent = {}
local RMS_StartEvent_mt = Class(RMS_StartEvent, Event)

InitEventClass(RMS_StartEvent, "RMS_StartEvent")


---Create instance of Event class
-- @return table self instance of class event
function RMS_StartEvent.emptyNew()
    return Event.new(RMS_StartEvent_mt)
end


---Create new instance of event
-- @param table vehicle vehicle
-- @param integer? state RMS_Start.STATE, nil in a request
-- @param boolean? preheatWasRequired true when the start needed preheating
-- @return table self instance of event
function RMS_StartEvent.new(vehicle, state, preheatWasRequired)
    local self = RMS_StartEvent.emptyNew()
    self.vehicle = vehicle
    self.state = state
    self.preheatWasRequired = preheatWasRequired
    return self
end


---Writes event data to a stream
-- @param integer streamId stream id
-- @param Connection connection connection the event goes to
function RMS_StartEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObject(streamId, self.vehicle)
    if not connection:getIsServer() then
        streamWriteUIntN(streamId, self.state, 3)
        streamWriteBool(streamId, self.preheatWasRequired)
    end
end


---Reads event data from a stream
-- @param integer streamId stream id
-- @param Connection connection connection the event comes from
function RMS_StartEvent:readStream(streamId, connection)
    self.vehicle = NetworkUtil.readNodeObject(streamId)
    if connection:getIsServer() then
        self.state = streamReadUIntN(streamId, 3)
        self.preheatWasRequired = streamReadBool(streamId)
    end
    self:run(connection)
end


---Applies the state on a client, starts the motor on the server
-- @param Connection connection connection the event comes from
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
-- @param table vehicle vehicle
-- @param integer state RMS_Start.STATE
-- @param boolean preheatWasRequired true when the start needed preheating
function RMS_StartEvent.sendEvent(vehicle, state, preheatWasRequired)
    g_server:broadcastEvent(RMS_StartEvent.new(vehicle, state, preheatWasRequired), nil, nil, vehicle)
end


---Asks the server alone for a start, never the other players
-- @param table vehicle vehicle
function RMS_StartEvent.sendRequest(vehicle)
    g_client:getServerConnection():sendEvent(RMS_StartEvent.new(vehicle))
end
