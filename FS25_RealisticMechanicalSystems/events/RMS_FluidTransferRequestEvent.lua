-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---Client request to start or cancel a physical fluid transfer
RMS_FluidTransferRequestEvent = {}
local RMS_FluidTransferRequestEvent_mt = Class(RMS_FluidTransferRequestEvent, Event)

InitEventClass(RMS_FluidTransferRequestEvent, "RMS_FluidTransferRequestEvent")

function RMS_FluidTransferRequestEvent.emptyNew()
    return Event.new(RMS_FluidTransferRequestEvent_mt)
end

function RMS_FluidTransferRequestEvent.new(container, target, circuit, incompatibleConfirmed, cancel)
    local self = RMS_FluidTransferRequestEvent.emptyNew()
    self.container = container
    self.target = target
    self.circuit = circuit
    self.incompatibleConfirmed = incompatibleConfirmed == true
    self.cancel = cancel == true
    return self
end

function RMS_FluidTransferRequestEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObject(streamId, self.container)
    NetworkUtil.writeNodeObject(streamId, self.target)
    streamWriteString(streamId, self.circuit or "")
    streamWriteBool(streamId, self.incompatibleConfirmed)
    streamWriteBool(streamId, self.cancel)
end

function RMS_FluidTransferRequestEvent:readStream(streamId, connection)
    self.container = NetworkUtil.readNodeObject(streamId)
    self.target = NetworkUtil.readNodeObject(streamId)
    self.circuit = streamReadString(streamId)
    self.incompatibleConfirmed = streamReadBool(streamId)
    self.cancel = streamReadBool(streamId)
    self:run(connection)
end

function RMS_FluidTransferRequestEvent:run(connection)
    if connection:getIsServer() or self.container == nil then
        return
    end

    local requester = RMS_FluidTransfer.getRequesterContext(connection)
    if requester == nil then
        return
    end

    if self.cancel then
        local containerSpec = self.container[RMS_FluidContainer.SPEC_TABLE_NAME]
        local transfer = containerSpec ~= nil and containerSpec.activeTransfer or nil
        if transfer ~= nil and transfer.requesterUserId == requester.userId then
            RMS_FluidTransfer.cancel(self.container)
        end
        return
    end

    if self.target == nil or not self.container:getIsSynchronized() or not self.target:getIsSynchronized() then
        return
    end
    RMS_FluidTransfer.tryStart(
        self.container,
        self.target,
        self.circuit,
        requester,
        self.incompatibleConfirmed
    )
end

function RMS_FluidTransferRequestEvent.send(container, target, circuit, incompatibleConfirmed, cancel)
    if g_client ~= nil then
        g_client:getServerConnection():sendEvent(RMS_FluidTransferRequestEvent.new(
            container,
            target,
            circuit,
            incompatibleConfirmed,
            cancel
        ))
    end
end
