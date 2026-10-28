-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---Diagnostic PC commands and server replies
RMS_DiagnosticRequestEvent = {}
local RMS_DiagnosticRequestEvent_mt = Class(RMS_DiagnosticRequestEvent, Event)
InitEventClass(RMS_DiagnosticRequestEvent, "RMS_DiagnosticRequestEvent")

local SHARED_ERRORS = {
    access = "rms_charger_error_access",
    moving = "rms_charger_error_moving",
    power = "rms_battery_isolator_open",
    money = "shop_messageNotEnoughMoneyToBuy",
    unavailable = "rms_charger_error_unavailable"
}

---
function RMS_DiagnosticRequestEvent.emptyNew()
    return Event.new(RMS_DiagnosticRequestEvent_mt)
end

---
function RMS_DiagnosticRequestEvent.new(tool, target, action, result)
    local self = RMS_DiagnosticRequestEvent.emptyNew()
    self.tool = tool
    self.target = target
    self.action = action
    self.result = result or ""
    return self
end

---
function RMS_DiagnosticRequestEvent:writeStream(streamId)
    NetworkUtil.writeNodeObject(streamId, self.tool)
    NetworkUtil.writeNodeObject(streamId, self.target)
    streamWriteUIntN(streamId, self.action, 3)
    streamWriteString(streamId, self.result)
end

---
function RMS_DiagnosticRequestEvent:readStream(streamId, connection)
    self.tool = NetworkUtil.readNodeObject(streamId)
    self.target = NetworkUtil.readNodeObject(streamId)
    self.action = streamReadUIntN(streamId, 3)
    self.result = streamReadString(streamId)
    self:run(connection)
end

---
function RMS_DiagnosticRequestEvent:run(connection)
    if connection:getIsServer() then
        if self.result ~= "" and self.result ~= "ok" then
            InfoDialog.show(g_i18n:getText(SHARED_ERRORS[self.result] or "rms_diagnostic_error_" .. self.result))
        end
        return
    end
    local action = RMS_DiagnosticTool.ACTION
    local requester = RMS_FluidTransfer.getRequesterContext(connection)
    local result = "unavailable"
    if self.tool ~= nil and self.tool.isServer
        and self.tool[RMS_DiagnosticTool.SPEC_TABLE_NAME] ~= nil
        and self.tool.rootNode ~= nil and entityExists(self.tool.rootNode)
        and requester ~= nil and requester.player ~= nil
        and requester.player.rootNode ~= nil and entityExists(requester.player.rootNode) then
        local player = requester.player
        local cx, cy, cz = getWorldTranslation(self.tool.rootNode)
        local px, py, pz = getWorldTranslation(player.rootNode)
        if requester.farmId == FarmManager.SPECTATOR_FARM_ID or self.tool:getOwnerFarmId() ~= requester.farmId then
            result = "access"
        elseif player:getIsInVehicle()
            or MathUtil.vector3Length(cx - px, cy - py, cz - pz) > RMS_BatteryCharger.MAX_DISTANCE then
            result = "player_distance"
        elseif self.action == action.UNPLUG then
            RMS_DiagnosticTool.unplug(self.tool)
            result = "ok"
        elseif self.action == action.SCAN then
            result = RMS_DiagnosticTool.startScan(self.tool)
        elseif self.action == action.RENEW then
            result = RMS_DiagnosticTool.renewLicence(self.tool)
        elseif self.target ~= nil and self.tool:getIsSynchronized() and self.target:getIsSynchronized() then
            result = RMS_DiagnosticTool.plug(self.tool, self.target)
            if result == "ok" and RMS_DiagnosticTool.getIsPowered(self.target) then
                RMS_DiagnosticTool.startScan(self.tool)
            end
        end
    end
    connection:sendEvent(RMS_DiagnosticRequestEvent.new(self.tool, nil, self.action, result))
end

---Sends a command of the PC to the server
-- @param table tool trolley
-- @param table? target machine to plug into
-- @param integer action RMS_DiagnosticTool.ACTION
function RMS_DiagnosticRequestEvent.send(tool, target, action)
    if g_client ~= nil then
        g_client:getServerConnection():sendEvent(RMS_DiagnosticRequestEvent.new(tool, target, action))
    end
end
