-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---Event carrying the shared settings between the server and the clients
RMS_SettingsSyncEvent = {}
local RMS_SettingsSyncEvent_mt = Class(RMS_SettingsSyncEvent, Event)

InitEventClass(RMS_SettingsSyncEvent, "RMS_SettingsSyncEvent")

---Creates an empty event, filled by readStream
-- @return table event event
function RMS_SettingsSyncEvent.emptyNew()
    return Event.new(RMS_SettingsSyncEvent_mt)
end

---Creates an event holding the current shared settings
-- @return table event event
function RMS_SettingsSyncEvent.new()
    local self = RMS_SettingsSyncEvent.emptyNew()
    self.values = {}
    for index, setting in ipairs(RMS_Config.SHARED_SETTINGS) do
        self.values[index] = RMS_Config.getSettingTable(setting)[setting.field]
    end
    return self
end

---Writes the settings in the order of RMS_Config.SHARED_SETTINGS
-- @param integer streamId stream id
-- @param table connection connection
function RMS_SettingsSyncEvent:writeStream(streamId, connection)
    for index, setting in ipairs(RMS_Config.SHARED_SETTINGS) do
        if setting.isFloat then
            streamWriteFloat32(streamId, self.values[index])
        else
            streamWriteBool(streamId, self.values[index])
        end
    end
end

---Reads the settings in the order of RMS_Config.SHARED_SETTINGS
-- @param integer streamId stream id
-- @param table connection connection
function RMS_SettingsSyncEvent:readStream(streamId, connection)
    self.values = {}
    for index, setting in ipairs(RMS_Config.SHARED_SETTINGS) do
        if setting.isFloat then
            self.values[index] = streamReadFloat32(streamId)
        else
            self.values[index] = streamReadBool(streamId)
        end
    end
    self:run(connection)
end

---Writes the received settings in the configuration and applies them
-- @param table event received event
local function applySettings(event)
    for index, setting in ipairs(RMS_Config.SHARED_SETTINGS) do
        RMS_Config.getSettingTable(setting)[setting.field] = event.values[index]
    end
    RealisticMechanicalSystems.finishInstantServices()
    RMS_Drivetrain.refreshAllParkBrakePedals()
    RMS_Drivetrain.claimFromOtherMod()
    RMS_Main:forceWorkshopUpdate(true)
end

---Applies the settings, from a master user only on the server
-- @param table connection connection
function RMS_SettingsSyncEvent:run(connection)
    if not connection:getIsServer() then
        local userId = g_currentMission.userManager:getUserIdByConnection(connection)
        local user = g_currentMission.userManager:getUserByUserId(userId)
        if user == nil or not user:getIsMasterUser() then
            return
        end

        applySettings(self)
        -- the other clients receive what the server now holds
        g_server:broadcastEvent(RMS_SettingsSyncEvent.new(), nil, connection)
    else
        applySettings(self)
    end
end

---Saves the settings on the server and shares them with the other side
function RMS_SettingsSyncEvent.share()
    if g_currentMission:getIsServer() then
        RMS_Config.saveToXMLFile()
        if g_server ~= nil then
            g_server:broadcastEvent(RMS_SettingsSyncEvent.new())
        end
    elseif g_client ~= nil then
        g_client:getServerConnection():sendEvent(RMS_SettingsSyncEvent.new())
    end
end
