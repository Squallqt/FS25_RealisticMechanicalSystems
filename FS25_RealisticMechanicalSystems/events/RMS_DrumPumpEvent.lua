-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---Event setting a pump on a drum or taking it back in hand
RMS_DrumPumpEvent = {}
local RMS_DrumPumpEvent_mt = Class(RMS_DrumPumpEvent, Event)

InitEventClass(RMS_DrumPumpEvent, "RMS_DrumPumpEvent")

---
function RMS_DrumPumpEvent.emptyNew()
    return Event.new(RMS_DrumPumpEvent_mt)
end

---
-- @param table container drum aimed at
-- @param table? handTool pump in hand to set on it, nil to take its pump back
function RMS_DrumPumpEvent.new(container, handTool)
    local self = RMS_DrumPumpEvent.emptyNew()
    self.container = container
    self.handTool = handTool
    self.isMount = handTool ~= nil
    return self
end

---
function RMS_DrumPumpEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObject(streamId, self.container)
    if streamWriteBool(streamId, self.handTool ~= nil) then
        NetworkUtil.writeNodeObject(streamId, self.handTool)
    end
end

---
function RMS_DrumPumpEvent:readStream(streamId, connection)
    self.container = NetworkUtil.readNodeObject(streamId)
    self.isMount = streamReadBool(streamId)
    if self.isMount then
        self.handTool = NetworkUtil.readNodeObject(streamId)
    end
    self:run(connection)
end

---
function RMS_DrumPumpEvent:run(connection)
    if connection:getIsServer() or self.container == nil then
        return
    end

    local requester = RMS_FluidTransfer.getRequesterContext(connection)
    if requester == nil then
        return
    end

    if not self.isMount then
        RMS_DrumPump.unmount(requester.player, self.container)
    elseif self.handTool ~= nil then
        RMS_DrumPump.mount(requester.player, self.handTool, self.container)
    end
end

---Asks the server to set a pump on a drum or take it back
-- @param table container drum aimed at
-- @param table? handTool pump in hand to set on it, nil to take its pump back
function RMS_DrumPumpEvent.send(container, handTool)
    g_client:getServerConnection():sendEvent(RMS_DrumPumpEvent.new(container, handTool))
end
