-- Copyright © 2026 Squallqt. All rights reserved.

---Event setting a pump on a drum or taking it back in hand
RMS_DrumPumpEvent = {}
local RMS_DrumPumpEvent_mt = Class(RMS_DrumPumpEvent, Event)

InitEventClass(RMS_DrumPumpEvent, "RMS_DrumPumpEvent")

---Create instance of Event class
-- @return table self instance of class event
function RMS_DrumPumpEvent.emptyNew()
    return Event.new(RMS_DrumPumpEvent_mt)
end

---Create new instance of event
-- @param table container drum or pallet of drums
-- @param table? handTool pump in hand to set on it, nil to take its pump back
-- @param integer index drum of the pallet
-- @return table self instance of event
function RMS_DrumPumpEvent.new(container, handTool, index)
    local self = RMS_DrumPumpEvent.emptyNew()
    self.container = container
    self.handTool = handTool
    self.isMount = handTool ~= nil
    self.index = index
    return self
end

---Writes event data to a stream
-- @param integer streamId stream id
-- @param Connection connection connection the event goes to
function RMS_DrumPumpEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObject(streamId, self.container)
    streamWriteUInt8(streamId, self.index)
    if streamWriteBool(streamId, self.handTool ~= nil) then
        NetworkUtil.writeNodeObject(streamId, self.handTool)
    end
end

---Reads event data from a stream
-- @param integer streamId stream id
-- @param Connection connection connection the event comes from
function RMS_DrumPumpEvent:readStream(streamId, connection)
    self.container = NetworkUtil.readNodeObject(streamId)
    self.index = streamReadUInt8(streamId)
    self.isMount = streamReadBool(streamId)
    if self.isMount then
        self.handTool = NetworkUtil.readNodeObject(streamId)
    end
    self:run(connection)
end

---Sets or takes back the pump on the server for the requesting player
-- @param Connection connection connection the event comes from
function RMS_DrumPumpEvent:run(connection)
    if self.container == nil then
        return
    end

    local requester = RMS_FluidTransfer.getRequesterContext(connection)
    if requester == nil then
        return
    end

    if not self.isMount then
        RMS_DrumPump.unmount(requester.player, self.container, self.index)
    elseif self.handTool ~= nil then
        RMS_DrumPump.mount(requester.player, self.handTool, self.container, self.index)
    end
end

---Asks the server to set a pump on a drum or take it back
-- @param table container drum or pallet of drums
-- @param table? handTool pump in hand to set on it, nil to take its pump back
-- @param integer index drum of the pallet
function RMS_DrumPumpEvent.send(container, handTool, index)
    g_client:getServerConnection():sendEvent(RMS_DrumPumpEvent.new(container, handTool, index))
end
