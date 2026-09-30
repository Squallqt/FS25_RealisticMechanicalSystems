-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---Applies the completed paint configuration on connected clients.
RMS_BodyworkColorEvent = {}
local RMS_BodyworkColorEvent_mt = Class(RMS_BodyworkColorEvent, Event)

InitEventClass(RMS_BodyworkColorEvent, "RMS_BodyworkColorEvent")

function RMS_BodyworkColorEvent.emptyNew()
    return Event.new(RMS_BodyworkColorEvent_mt)
end

function RMS_BodyworkColorEvent.new(vehicle, colors)
    local self = RMS_BodyworkColorEvent.emptyNew()
    self.vehicle = vehicle
    self.colors = colors
    return self
end

function RMS_BodyworkColorEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObject(streamId, self.vehicle)
    streamWriteString(streamId, self.colors)
end

function RMS_BodyworkColorEvent:readStream(streamId, connection)
    self.vehicle = NetworkUtil.readNodeObject(streamId)
    self.colors = streamReadString(streamId)
    self:run(connection)
end

function RMS_BodyworkColorEvent:run(connection)
    if connection:getIsServer() and self.vehicle ~= nil
        and self.vehicle.spec_RealisticMechanicalSystems ~= nil then
        RMS_Bodywork.restorePreview(self.vehicle, true)
        if RMS_Bodywork.validateColors(self.vehicle, self.colors) then
            RMS_Bodywork.applyColors(self.vehicle, self.colors)
        end
    end
end

function RMS_BodyworkColorEvent.sendToClients(vehicle, colors)
    if g_server ~= nil then
        g_server:broadcastEvent(RMS_BodyworkColorEvent.new(vehicle, colors), nil, nil, vehicle)
    end
end
