-- Copyright © 2026 Squallqt. All rights reserved.

---Client request to start or cancel a physical fluid transfer
RMS_FluidTransferRequestEvent = {}
local RMS_FluidTransferRequestEvent_mt = Class(RMS_FluidTransferRequestEvent, Event)

InitEventClass(RMS_FluidTransferRequestEvent, "RMS_FluidTransferRequestEvent")

---Create instance of Event class
function RMS_FluidTransferRequestEvent.emptyNew()
    return Event.new(RMS_FluidTransferRequestEvent_mt)
end

---Create new instance of event
-- @param integer? index place poured from (the drum of a pallet), the first by default
function RMS_FluidTransferRequestEvent.new(container, target, circuit, incompatibleConfirmed, cancel, result, index)
    local self = RMS_FluidTransferRequestEvent.emptyNew()
    self.container = container
    self.target = target
    self.circuit = circuit
    self.incompatibleConfirmed = incompatibleConfirmed == true
    self.cancel = cancel == true
    self.result = result or ""
    self.index = index or 1
    return self
end

---Writes event data to a stream.
function RMS_FluidTransferRequestEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObject(streamId, self.container)
    NetworkUtil.writeNodeObject(streamId, self.target)
    streamWriteString(streamId, self.circuit or "")
    streamWriteBool(streamId, self.incompatibleConfirmed)
    streamWriteBool(streamId, self.cancel)
    streamWriteString(streamId, self.result)
    streamWriteUInt8(streamId, self.index)
end

---Reads event data from a stream.
function RMS_FluidTransferRequestEvent:readStream(streamId, connection)
    self.container = NetworkUtil.readNodeObject(streamId)
    self.target = NetworkUtil.readNodeObject(streamId)
    self.circuit = streamReadString(streamId)
    self.incompatibleConfirmed = streamReadBool(streamId)
    self.cancel = streamReadBool(streamId)
    self.result = streamReadString(streamId)
    self.index = streamReadUInt8(streamId)
    self:run(connection)
end

---Starts or cancels the transfer on the server, or shows the refusal on the client
function RMS_FluidTransferRequestEvent:run(connection)
    if connection:getIsServer() then
        local textKey = self.container ~= nil and RMS_FluidTransfer.getRefusalTextKey(self.container, self.result) or nil
        if textKey ~= nil then
            g_currentMission:showBlinkingWarning(g_i18n:getText(textKey), 2000)
        end
        return
    end
    local containerSpec = self.container ~= nil and self.container[RMS_FluidContainer.SPEC_TABLE_NAME] or nil
    local slot = containerSpec ~= nil and containerSpec.slots ~= nil and containerSpec.slots[self.index] or nil
    if slot == nil then
        return
    end

    local requester = RMS_FluidTransfer.getRequesterContext(connection)
    if requester == nil then
        return
    end

    if self.cancel then
        local transfer = slot.activeTransfer
        if transfer ~= nil and transfer.requesterUserId == requester.userId then
            RMS_FluidTransfer.cancel(self.container, self.index)
        end
        return
    end

    if self.target == nil or not self.container:getIsSynchronized() or not self.target:getIsSynchronized() then
        return
    end
    local _, result = RMS_FluidTransfer.tryStart(
        self.container,
        self.target,
        self.circuit,
        requester,
        self.incompatibleConfirmed,
        self.index
    )
    if result ~= RMS_FluidTransfer.RESULT.OK then
        connection:sendEvent(RMS_FluidTransferRequestEvent.new(self.container, nil, self.circuit, false, false, result, self.index))
    end
end

---Sends a transfer request from a client to the server
function RMS_FluidTransferRequestEvent.send(container, target, circuit, incompatibleConfirmed, cancel, index)
    if g_client ~= nil then
        g_client:getServerConnection():sendEvent(RMS_FluidTransferRequestEvent.new(
            container,
            target,
            circuit,
            incompatibleConfirmed,
            cancel,
            nil,
            index
        ))
    end
end
