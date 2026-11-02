-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---Server response for a rejected service transaction
RMS_ServiceResultEvent = {}
local RMS_ServiceResultEvent_mt = Class(RMS_ServiceResultEvent, Event)

InitEventClass(RMS_ServiceResultEvent, "RMS_ServiceResultEvent")

function RMS_ServiceResultEvent.emptyNew()
    return Event.new(RMS_ServiceResultEvent_mt)
end

function RMS_ServiceResultEvent.new(result)
    local self = RMS_ServiceResultEvent.emptyNew()
    self.result = result
    return self
end

function RMS_ServiceResultEvent:writeStream(streamId, connection)
    streamWriteString(streamId, self.result or RMS_FluidWorkshop.RESULT.INVALID)
end

function RMS_ServiceResultEvent:readStream(streamId, connection)
    self.result = streamReadString(streamId)
    self:run(connection)
end

function RMS_ServiceResultEvent:run(connection)
    if connection:getIsServer() then
        RMS_FluidWorkshop.showResult(self.result)
    end
end
