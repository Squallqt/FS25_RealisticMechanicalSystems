-- Copyright © 2026 Squallqt. All rights reserved.

---Event greasing a point or loading a cartridge, then the gun it leaves
RMS_GreaseGunEvent = {}
local RMS_GreaseGunEvent_mt = Class(RMS_GreaseGunEvent, Event)

InitEventClass(RMS_GreaseGunEvent, "RMS_GreaseGunEvent")

RMS_GreaseGunEvent.STROKE = 0
RMS_GreaseGunEvent.LOAD = 1
RMS_GreaseGunEvent.STATE = 2
RMS_GreaseGunEvent.KIND_BITS = 2

---Create instance of Event class
-- @return table self instance of class event
function RMS_GreaseGunEvent.emptyNew()
    return Event.new(RMS_GreaseGunEvent_mt)
end

---Create new instance of event
-- @param table handTool grease gun
-- @param integer kind RMS_GreaseGunEvent.STROKE, LOAD or STATE
-- @param table? target machine to grease or cartridge to load, nil for a state
-- @param float? greaseMl grease left in the gun (ml), for a state
-- @param boolean? isStroke true when the state follows a stroke
-- @return table self instance of event
function RMS_GreaseGunEvent.new(handTool, kind, target, greaseMl, isStroke)
    local self = RMS_GreaseGunEvent.emptyNew()
    self.handTool = handTool
    self.kind = kind
    self.target = target
    self.greaseMl = greaseMl
    self.isStroke = isStroke
    return self
end

---Writes event data to a stream
-- @param integer streamId stream id
-- @param Connection connection connection the event goes to
function RMS_GreaseGunEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObject(streamId, self.handTool)
    streamWriteUIntN(streamId, self.kind, RMS_GreaseGunEvent.KIND_BITS)
    if self.kind == RMS_GreaseGunEvent.STATE then
        streamWriteFloat32(streamId, self.greaseMl)
        streamWriteBool(streamId, self.isStroke)
    else
        NetworkUtil.writeNodeObject(streamId, self.target)
    end
end

---Reads event data from a stream
-- @param integer streamId stream id
-- @param Connection connection connection the event comes from
function RMS_GreaseGunEvent:readStream(streamId, connection)
    self.handTool = NetworkUtil.readNodeObject(streamId)
    self.kind = streamReadUIntN(streamId, RMS_GreaseGunEvent.KIND_BITS)
    if self.kind == RMS_GreaseGunEvent.STATE then
        self.greaseMl = streamReadFloat32(streamId)
        self.isStroke = streamReadBool(streamId)
    else
        self.target = NetworkUtil.readNodeObject(streamId)
    end
    self:run(connection)
end

---Serves a request on the server, applies a gun state on a client
-- @param Connection connection connection the event comes from
function RMS_GreaseGunEvent:run(connection)
    if self.handTool == nil then
        return
    end

    if self.kind == RMS_GreaseGunEvent.STATE then
        self.handTool:applyRMSGreaseGunState(self.greaseMl, self.isStroke)
    elseif self.target ~= nil then
        local requester = RMS_FluidTransfer.getRequesterContext(connection)
        if requester ~= nil then
            RMS_GreaseGun.serve(self.handTool, requester.player, self.kind, self.target)
        end
    end
end

---Asks the server to grease a point or to load a cartridge
-- @param table handTool grease gun
-- @param integer kind RMS_GreaseGunEvent.STROKE or LOAD
-- @param table target machine to grease or cartridge to load
function RMS_GreaseGunEvent.sendRequest(handTool, kind, target)
    g_client:getServerConnection():sendEvent(RMS_GreaseGunEvent.new(handTool, kind, target))
end

---Gives the players the grease left in a gun, with the stroke it made
-- @param table handTool grease gun
-- @param float greaseMl grease left in the gun (ml)
-- @param boolean isStroke true when the state follows a stroke
function RMS_GreaseGunEvent.broadcastState(handTool, greaseMl, isStroke)
    g_server:broadcastEvent(RMS_GreaseGunEvent.new(handTool, RMS_GreaseGunEvent.STATE, nil, greaseMl, isStroke))
end
