-- Copyright © 2026 Squallqt. All rights reserved.

---Client request to take a fluid can in hand, or to set down the one carried
RMS_FluidCanisterEvent = {}
local RMS_FluidCanisterEvent_mt = Class(RMS_FluidCanisterEvent, Event)

InitEventClass(RMS_FluidCanisterEvent, "RMS_FluidCanisterEvent")

---Create instance of Event class
function RMS_FluidCanisterEvent.emptyNew()
    return Event.new(RMS_FluidCanisterEvent_mt)
end

---Create new instance of event
-- @param table? pose world position and heading the can is set down at, nil to take
-- @param integer? index drum of a pallet whose nozzle is taken, the first by default
function RMS_FluidCanisterEvent.new(object, pose, index)
    local self = RMS_FluidCanisterEvent.emptyNew()
    self.object = object
    self.pose = pose
    self.index = index or 1
    return self
end

---Writes event data to a stream.
function RMS_FluidCanisterEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObject(streamId, self.object)
    streamWriteUInt8(streamId, self.index)
    if streamWriteBool(streamId, self.pose ~= nil) then
        for index = 1, 4 do
            streamWriteFloat32(streamId, self.pose[index])
        end
    end
end

---Reads event data from a stream.
function RMS_FluidCanisterEvent:readStream(streamId, connection)
    self.object = NetworkUtil.readNodeObject(streamId)
    self.index = streamReadUInt8(streamId)
    if streamReadBool(streamId) then
        self.pose = {}
        for index = 1, 4 do
            self.pose[index] = streamReadFloat32(streamId)
        end
    end
    self:run(connection)
end

---Takes or sets down the can on the server for the requesting player
function RMS_FluidCanisterEvent:run(connection)
    if connection:getIsServer() or self.object == nil then
        return
    end

    local requester = RMS_FluidTransfer.getRequesterContext(connection)
    if requester == nil then
        return
    end

    if self.pose == nil then
        RMS_FluidHandTool.take(requester.player, self.object, self.index)
    elseif self.object:getCarryingPlayer() == requester.player then
        RMS_FluidHandTool.queueSetDown(self.object, self.pose)
    end
end

---Asks the server to take a can in hand or set it down
function RMS_FluidCanisterEvent.send(object, pose, index)
    g_client:getServerConnection():sendEvent(RMS_FluidCanisterEvent.new(object, pose, index))
end
