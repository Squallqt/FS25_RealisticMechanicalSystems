-- Copyright © 2026 Squallqt. All rights reserved.

---Server response for a stock check or a rejected service transaction
RMS_ServiceResultEvent = {}
local RMS_ServiceResultEvent_mt = Class(RMS_ServiceResultEvent, Event)

InitEventClass(RMS_ServiceResultEvent, "RMS_ServiceResultEvent")

---Create instance of Event class
function RMS_ServiceResultEvent.emptyNew()
    return Event.new(RMS_ServiceResultEvent_mt)
end

---Create new instance of event
function RMS_ServiceResultEvent.new(result, stockRequestId, shortages)
    local self = RMS_ServiceResultEvent.emptyNew()
    self.result = result
    self.stockRequestId = stockRequestId
    self.shortages = shortages
    return self
end

---Writes event data to a stream.
function RMS_ServiceResultEvent:writeStream(streamId, connection)
    if streamWriteBool(streamId, self.stockRequestId ~= nil) then
        streamWriteUInt32(streamId, self.stockRequestId)
        for _, circuit in ipairs(RMS_Fluids.CIRCUIT_ORDER) do
            local liters = self.shortages[circuit]
            if streamWriteBool(streamId, liters ~= nil) then
                streamWriteFloat32(streamId, liters)
            end
        end
    else
        streamWriteString(streamId, self.result or RMS_FluidWorkshop.RESULT.INVALID)
    end
end

---Reads event data from a stream.
function RMS_ServiceResultEvent:readStream(streamId, connection)
    if streamReadBool(streamId) then
        self.stockRequestId = streamReadUInt32(streamId)
        self.shortages = {}
        for _, circuit in ipairs(RMS_Fluids.CIRCUIT_ORDER) do
            if streamReadBool(streamId) then
                self.shortages[circuit] = streamReadFloat32(streamId)
            end
        end
    else
        self.result = streamReadString(streamId)
    end
    self:run(connection)
end

---Run action on receiving side
function RMS_ServiceResultEvent:run(connection)
    if connection:getIsServer() then
        if self.stockRequestId ~= nil then
            local dialog = RMS_WorkshopDialog.INSTANCE
            if dialog ~= nil then
                dialog:onStockQuote(self.stockRequestId, self.shortages)
            end
        else
            RMS_FluidWorkshop.showResult(self.result)
        end
    end
end
