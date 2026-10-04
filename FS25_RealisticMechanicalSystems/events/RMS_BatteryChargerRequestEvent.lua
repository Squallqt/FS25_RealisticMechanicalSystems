-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---Charger commands and their server reply; live state is replicated by the vehicle streams.
RMS_BatteryChargerRequestEvent = {}
local RMS_BatteryChargerRequestEvent_mt = Class(RMS_BatteryChargerRequestEvent, Event)
InitEventClass(RMS_BatteryChargerRequestEvent, "RMS_BatteryChargerRequestEvent")

function RMS_BatteryChargerRequestEvent.emptyNew()
    return Event.new(RMS_BatteryChargerRequestEvent_mt)
end

function RMS_BatteryChargerRequestEvent.new(charger, target, disconnect, result, mode)
    local self = RMS_BatteryChargerRequestEvent.emptyNew()
    self.charger = charger
    self.target = target
    self.disconnect = disconnect == true
    self.result = result or ""
    self.mode = mode or RMS_BatteryCharger.MODE.CHARGE
    return self
end

function RMS_BatteryChargerRequestEvent:writeStream(streamId)
    NetworkUtil.writeNodeObject(streamId, self.charger)
    NetworkUtil.writeNodeObject(streamId, self.target)
    streamWriteBool(streamId, self.disconnect)
    streamWriteString(streamId, self.result)
    streamWriteUIntN(streamId, self.mode, 1)
end

function RMS_BatteryChargerRequestEvent:readStream(streamId, connection)
    self.charger = NetworkUtil.readNodeObject(streamId)
    self.target = NetworkUtil.readNodeObject(streamId)
    self.disconnect = streamReadBool(streamId)
    self.result = streamReadString(streamId)
    self.mode = streamReadUIntN(streamId, 1)
    self:run(connection)
end

function RMS_BatteryChargerRequestEvent:run(connection)
    if connection:getIsServer() then
        if self.result ~= "" and self.result ~= "ok" then
            InfoDialog.show(g_i18n:getText("rms_charger_error_" .. self.result))
        end
        return
    end
    local requester = RMS_FluidTransfer.getRequesterContext(connection)
    local result = "unavailable"
    if self.charger ~= nil and self.charger.isServer
        and self.charger[RMS_BatteryCharger.SPEC_TABLE_NAME] ~= nil
        and self.charger.rootNode ~= nil and entityExists(self.charger.rootNode)
        and requester ~= nil and requester.player ~= nil
        and requester.player.rootNode ~= nil and entityExists(requester.player.rootNode) then
        local player = requester.player
        local cx, cy, cz = getWorldTranslation(self.charger.rootNode)
        local px, py, pz = getWorldTranslation(player.rootNode)
        if requester.farmId == FarmManager.SPECTATOR_FARM_ID or self.charger:getOwnerFarmId() ~= requester.farmId then
            result = "access"
        elseif player:getIsInVehicle()
            or MathUtil.vector3Length(cx - px, cy - py, cz - pz) > RMS_BatteryCharger.MAX_DISTANCE then
            result = "player_distance"
        elseif self.disconnect then
            RMS_BatteryCharger.stop(self.charger)
            result = "ok"
        elseif self.target ~= nil and self.charger:getIsSynchronized() and self.target:getIsSynchronized() then
            result = RMS_BatteryCharger.tryStart(self.charger, self.target, requester, false, self.mode)
        end
    end
    connection:sendEvent(RMS_BatteryChargerRequestEvent.new(self.charger, nil, self.disconnect, result))
end

function RMS_BatteryChargerRequestEvent.send(charger, target, disconnect, mode)
    if g_client ~= nil then
        g_client:getServerConnection():sendEvent(RMS_BatteryChargerRequestEvent.new(charger, target, disconnect, nil, mode))
    end
end
