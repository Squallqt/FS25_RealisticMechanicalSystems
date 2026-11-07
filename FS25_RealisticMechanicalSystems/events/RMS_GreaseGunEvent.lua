-- Copyright © 2026 Squallqt. All rights reserved.

---Event greasing a point or loading a cartridge, then the gun it leaves
RMS_GreaseGunEvent = {}
local RMS_GreaseGunEvent_mt = Class(RMS_GreaseGunEvent, Event)

InitEventClass(RMS_GreaseGunEvent, "RMS_GreaseGunEvent")

RMS_GreaseGunEvent.STROKE = 0
RMS_GreaseGunEvent.LOAD = 1
RMS_GreaseGunEvent.STATE = 2
RMS_GreaseGunEvent.KIND_BITS = 2

function RMS_GreaseGunEvent.emptyNew()
    return Event.new(RMS_GreaseGunEvent_mt)
end

-- @param table? target machine to grease or cartridge to load, nil for a state
function RMS_GreaseGunEvent.new(handTool, kind, target, greaseMl, isStroke)
    local self = RMS_GreaseGunEvent.emptyNew()
    self.handTool = handTool
    self.kind = kind
    self.target = target
    self.greaseMl = greaseMl
    self.isStroke = isStroke
    return self
end

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

function RMS_GreaseGunEvent:run(connection)
    if self.handTool == nil then
        return
    end

    if self.kind == RMS_GreaseGunEvent.STATE then
        if connection:getIsServer() then
            self.handTool:applyRMSGreaseGunState(self.greaseMl, self.isStroke)
        end
    elseif not connection:getIsServer() and self.target ~= nil then
        local requester = RMS_FluidTransfer.getRequesterContext(connection)
        if requester ~= nil then
            RMS_GreaseGun.serve(self.handTool, requester.player, self.kind, self.target)
        end
    end
end

---Asks the server to grease a point or to load a cartridge
function RMS_GreaseGunEvent.sendRequest(handTool, kind, target)
    g_client:getServerConnection():sendEvent(RMS_GreaseGunEvent.new(handTool, kind, target))
end

---Gives the players the grease left in a gun, with the stroke it made
function RMS_GreaseGunEvent.broadcastState(handTool, greaseMl, isStroke)
    g_server:broadcastEvent(RMS_GreaseGunEvent.new(handTool, RMS_GreaseGunEvent.STATE, nil, greaseMl, isStroke))
end
