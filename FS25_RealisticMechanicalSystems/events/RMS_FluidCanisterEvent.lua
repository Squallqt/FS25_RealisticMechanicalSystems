-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---Client request to take a fluid can in hand, or to set down the one carried
RMS_FluidCanisterEvent = {}
local RMS_FluidCanisterEvent_mt = Class(RMS_FluidCanisterEvent, Event)

InitEventClass(RMS_FluidCanisterEvent, "RMS_FluidCanisterEvent")

---
function RMS_FluidCanisterEvent.emptyNew()
    return Event.new(RMS_FluidCanisterEvent_mt)
end

---
-- @param table object container to take, or carried hand tool to set down
-- @param table? pose world position and heading the can is set down at, nil to take
function RMS_FluidCanisterEvent.new(object, pose)
    local self = RMS_FluidCanisterEvent.emptyNew()
    self.object = object
    self.pose = pose
    return self
end

---
function RMS_FluidCanisterEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObject(streamId, self.object)
    if streamWriteBool(streamId, self.pose ~= nil) then
        for index = 1, 4 do
            streamWriteFloat32(streamId, self.pose[index])
        end
    end
end

---
function RMS_FluidCanisterEvent:readStream(streamId, connection)
    self.object = NetworkUtil.readNodeObject(streamId)
    if streamReadBool(streamId) then
        self.pose = {}
        for index = 1, 4 do
            self.pose[index] = streamReadFloat32(streamId)
        end
    end
    self:run(connection)
end

---
function RMS_FluidCanisterEvent:run(connection)
    if connection:getIsServer() or self.object == nil then
        return
    end

    local requester = RMS_FluidTransfer.getRequesterContext(connection)
    if requester == nil then
        return
    end

    if self.pose == nil then
        RMS_FluidHandTool.take(requester.player, self.object)
    elseif self.object:getCarryingPlayer() == requester.player then
        RMS_FluidHandTool.queueSetDown(self.object, self.pose)
    end
end

---Asks the server to take a can in hand or set it down
-- @param table object container to take, or carried hand tool to set down
-- @param table? pose world position and heading the can is set down at, nil to take
function RMS_FluidCanisterEvent.send(object, pose)
    g_client:getServerConnection():sendEvent(RMS_FluidCanisterEvent.new(object, pose))
end
