-- Copyright © 2026 Squallqt. All rights reserved.

---Event sending whether the workshop is open from the server to the clients
RMS_WorkshopChangeStatusEvent = {}
local RMS_WorkshopChangeStatusEvent_mt = Class(RMS_WorkshopChangeStatusEvent, Event)
MessageType.RMS_WORKSHOP_CHANGE_STATUS = nextMessageTypeId()

InitEventClass(RMS_WorkshopChangeStatusEvent, "RMS_WorkshopChangeStatusEvent")


---Create instance of Event class
-- @return table self instance of class event
function RMS_WorkshopChangeStatusEvent.emptyNew()
    return Event.new(RMS_WorkshopChangeStatusEvent_mt)
end


---Create new instance of event
-- @param boolean isOpen true while the workshop is open
-- @return table self instance of event
function RMS_WorkshopChangeStatusEvent.new(isOpen)
    local self = RMS_WorkshopChangeStatusEvent.emptyNew()
    self.isOpen = isOpen
    return self
end


---Writes event data to a stream
-- @param integer streamId stream id
-- @param Connection connection connection the event goes to
function RMS_WorkshopChangeStatusEvent:writeStream(streamId, connection)
    streamWriteBool(streamId, self.isOpen)
end


---Reads event data from a stream
-- @param integer streamId stream id
-- @param Connection connection connection the event comes from
function RMS_WorkshopChangeStatusEvent:readStream(streamId, connection)
    self.isOpen = streamReadBool(streamId)
    self:run(connection)
end


---Keeps the state on a client and tells the windows
-- @param Connection connection connection the event comes from
function RMS_WorkshopChangeStatusEvent:run(connection)
    RMS_Main.isWorkshopOpen = self.isOpen
    g_messageCenter:publish(MessageType.RMS_WORKSHOP_CHANGE_STATUS, self.isOpen)
end


---Broadcast the workshop state from the server to all clients
-- @param boolean isOpen true while the workshop is open
function RMS_WorkshopChangeStatusEvent.send(isOpen)
    g_server:broadcastEvent(RMS_WorkshopChangeStatusEvent.new(isOpen))
end
