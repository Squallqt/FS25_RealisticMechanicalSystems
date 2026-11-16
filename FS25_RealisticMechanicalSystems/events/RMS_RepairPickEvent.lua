-- Copyright © 2026 Squallqt. All rights reserved.

---Event picking a fault or a worn part of a vehicle for its repair
RMS_RepairPickEvent = {}
local RMS_RepairPickEvent_mt = Class(RMS_RepairPickEvent, Event)

InitEventClass(RMS_RepairPickEvent, "RMS_RepairPickEvent")

---Create instance of Event class
function RMS_RepairPickEvent.emptyNew()
    return Event.new(RMS_RepairPickEvent_mt)
end

---Create new instance of event
function RMS_RepairPickEvent.new(vehicle, partId, isPreventive, isPicked, donorHours)
    local self = RMS_RepairPickEvent.emptyNew()
    self.vehicle = vehicle
    self.partId = partId
    self.isPreventive = isPreventive == true
    self.isPicked = isPicked == true
    self.donorHours = donorHours
    return self
end

---Writes event data to a stream.
function RMS_RepairPickEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObject(streamId, self.vehicle)
    streamWriteString(streamId, self.partId)
    streamWriteBool(streamId, self.isPreventive)
    if streamWriteBool(streamId, self.isPicked) and self.isPreventive then
        streamWriteFloat32(streamId, self.donorHours)
    end
end

---Reads event data from a stream.
function RMS_RepairPickEvent:readStream(streamId, connection)
    self.vehicle = NetworkUtil.readNodeObject(streamId)
    self.partId = streamReadString(streamId)
    self.isPreventive = streamReadBool(streamId)
    self.isPicked = streamReadBool(streamId)
    if self.isPicked and self.isPreventive then
        self.donorHours = streamReadFloat32(streamId)
    end
    self:run(connection)
end

---Run action on receiving side
function RMS_RepairPickEvent:run(connection)
    local vehicle = self.vehicle
    if vehicle ~= nil and vehicle:getIsSynchronized() then
        RealisticMechanicalSystems.setRepairPick(vehicle, self.partId, self.isPreventive, self.isPicked, self.donorHours)
    end
end

---Picks on this game at once, a client asking the server too
-- @param float? donorHours donor hours of the used part of a picked worn part
function RMS_RepairPickEvent.send(vehicle, partId, isPreventive, isPicked, donorHours)
    RealisticMechanicalSystems.setRepairPick(vehicle, partId, isPreventive, isPicked, donorHours)
    if g_server == nil then
        g_client:getServerConnection():sendEvent(RMS_RepairPickEvent.new(vehicle, partId, isPreventive, isPicked, donorHours))
    end
end
