-- Copyright © 2026 Squallqt. All rights reserved.

---Server response for a rejected service transaction
RMS_ServiceResultEvent = {}
local RMS_ServiceResultEvent_mt = Class(RMS_ServiceResultEvent, Event)

InitEventClass(RMS_ServiceResultEvent, "RMS_ServiceResultEvent")

---Create instance of Event class
function RMS_ServiceResultEvent.emptyNew()
    return Event.new(RMS_ServiceResultEvent_mt)
end

---Create new instance of event
function RMS_ServiceResultEvent.new(result)
    local self = RMS_ServiceResultEvent.emptyNew()
    self.result = result
    return self
end

---Writes event data to a stream.
function RMS_ServiceResultEvent:writeStream(streamId, connection)
    streamWriteString(streamId, self.result or RMS_FluidWorkshop.RESULT.INVALID)
end

---Reads event data from a stream.
function RMS_ServiceResultEvent:readStream(streamId, connection)
    self.result = streamReadString(streamId)
    self:run(connection)
end

---Run action on receiving side
function RMS_ServiceResultEvent:run(connection)
    if connection:getIsServer() then
        RMS_FluidWorkshop.showResult(self.result)
    end
end
