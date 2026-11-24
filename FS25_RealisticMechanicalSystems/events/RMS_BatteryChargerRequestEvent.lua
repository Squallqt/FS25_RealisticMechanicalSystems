-- Copyright © 2026 Squallqt. All rights reserved.

---Event carrying a charger command and the server's reply
RMS_BatteryChargerRequestEvent = {}
local RMS_BatteryChargerRequestEvent_mt = Class(RMS_BatteryChargerRequestEvent, Event)
InitEventClass(RMS_BatteryChargerRequestEvent, "RMS_BatteryChargerRequestEvent")

---Create instance of Event class
-- @return table self instance of class event
function RMS_BatteryChargerRequestEvent.emptyNew()
    return Event.new(RMS_BatteryChargerRequestEvent_mt)
end

---Create new instance of event
-- @param table charger battery charger
-- @param table? target machine to charge or start, nil in a reply
-- @param boolean disconnect true to unplug the charger
-- @param string? result reply of the server, "ok" or an error code
-- @param integer? mode RMS_BatteryCharger.MODE, charge by default
-- @return table self instance of event
function RMS_BatteryChargerRequestEvent.new(charger, target, disconnect, result, mode)
    local self = RMS_BatteryChargerRequestEvent.emptyNew()
    self.charger = charger
    self.target = target
    self.disconnect = disconnect
    self.result = result or ""
    self.mode = mode or RMS_BatteryCharger.MODE.CHARGE
    return self
end

---Writes event data to a stream
-- @param integer streamId stream id
function RMS_BatteryChargerRequestEvent:writeStream(streamId)
    NetworkUtil.writeNodeObject(streamId, self.charger)
    NetworkUtil.writeNodeObject(streamId, self.target)
    streamWriteBool(streamId, self.disconnect)
    streamWriteString(streamId, self.result)
    streamWriteUIntN(streamId, self.mode, 1)
end

---Reads event data from a stream
-- @param integer streamId stream id
-- @param Connection connection connection the event comes from
function RMS_BatteryChargerRequestEvent:readStream(streamId, connection)
    self.charger = NetworkUtil.readNodeObject(streamId)
    self.target = NetworkUtil.readNodeObject(streamId)
    self.disconnect = streamReadBool(streamId)
    self.result = streamReadString(streamId)
    self.mode = streamReadUIntN(streamId, 1)
    self:run(connection)
end

---Runs the command on the server and answers, or shows the refusal on the client
-- @param Connection connection connection the event comes from
function RMS_BatteryChargerRequestEvent:run(connection)
    if connection:getIsServer() then
        if self.result ~= "" and self.result ~= "ok" then
            InfoDialog.show(g_i18n:getText("rms_charger_error_" .. self.result))
        end
        return
    end
    local requester = RMS_FluidTransfer.getRequesterContext(connection)
    local result = "unavailable"
    if self.charger ~= nil and entityExists(self.charger.rootNode)
        and requester ~= nil and entityExists(requester.player.rootNode) then
        local player = requester.player
        local cx, cy, cz = getWorldTranslation(self.charger.rootNode)
        local px, py, pz = getWorldTranslation(player.rootNode)
        if not g_currentMission.accessHandler:canFarmAccess(requester.farmId, self.charger) then
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

---Sends a charger command from a client to the server
-- @param table charger battery charger
-- @param table? target machine to charge or start
-- @param boolean disconnect true to unplug the charger
-- @param integer? mode RMS_BatteryCharger.MODE
function RMS_BatteryChargerRequestEvent.send(charger, target, disconnect, mode)
    g_client:getServerConnection():sendEvent(RMS_BatteryChargerRequestEvent.new(charger, target, disconnect, nil, mode))
end
