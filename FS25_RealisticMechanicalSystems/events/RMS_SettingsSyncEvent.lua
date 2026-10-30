-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---Event syncing the RMS settings
RMS_SettingsSyncEvent = {}
local RMS_SettingsSyncEvent_mt = Class(RMS_SettingsSyncEvent, Event)

InitEventClass(RMS_SettingsSyncEvent, "RMS_SettingsSyncEvent")


---Create instance of Event class
-- @return table self instance of class event
function RMS_SettingsSyncEvent.emptyNew()
    return Event.new(RMS_SettingsSyncEvent_mt)
end


---Create new instance of event
-- @return table self instance of class event
function RMS_SettingsSyncEvent.new()
    local self = RMS_SettingsSyncEvent.emptyNew()

    self.baseServiceWear           = RMS_Config.CORE.BASE_SERVICE_WEAR
    self.baseSystemsWear           = RMS_Config.CORE.BASE_SYSTEMS_WEAR
    self.enableWarningMessages     = RMS_Config.CORE.ENABLE_WARNING_MESSAGES
    self.instantInspection         = RMS_Config.MAINTENANCE.INSTANT_INSPECTION
    self.instantMaintenanceRepair  = RMS_Config.MAINTENANCE.INSTANT_MAINTENANCE_REPAIR
    self.instantBodywork           = RMS_Config.MAINTENANCE.INSTANT_BODYWORK
    self.instantOverhaul           = RMS_Config.MAINTENANCE.INSTANT_OVERHAUL
    self.dealerAlwaysAvailable     = RMS_Config.WORKSHOP.DEALER_ALWAYS_AVAILABLE
    self.mobileAlwaysAvailable     = RMS_Config.WORKSHOP.MOBILE_ALWAYS_AVAILABLE
    self.ownAlwaysAvailable        = RMS_Config.WORKSHOP.OWN_ALWAYS_AVAILABLE
    self.mobileWorkshopRestrictionsEnabled = RMS_Config.WORKSHOP.MOBILE_WORKSHOP_RESTRICTIONS_ENABLED
    self.openHour                  = RMS_Config.WORKSHOP.OPEN_HOUR
    self.closeHour                 = RMS_Config.WORKSHOP.CLOSE_HOUR
    self.debugMode                 = RMS_Config.DEBUG
    self.drivetrainEnabled         = RMS_Config.DRIVETRAIN.ENABLED
    self.drivetrainAllowAutoMode   = RMS_Config.DRIVETRAIN.ALLOW_AUTO_MODE
    self.drivetrainParkBrakeEnabled = RMS_Config.DRIVETRAIN.PARKBRAKE_ENABLED
    self.exhaustSmokeEnabled       = RMS_Config.EXHAUST.ENABLED

    return self
end


---Writes event data to a stream.
-- @param integer streamId streamId
-- @param any connection connection
function RMS_SettingsSyncEvent:writeStream(streamId, connection)
    streamWriteFloat32(streamId, self.baseServiceWear       or 0)
    streamWriteFloat32(streamId, self.baseSystemsWear       or 0)
    streamWriteBool(streamId,    self.enableWarningMessages or false)
    streamWriteBool(streamId,    self.instantInspection      or false)
    streamWriteBool(streamId,    self.instantMaintenanceRepair or false)
    streamWriteBool(streamId,    self.instantBodywork        or false)
    streamWriteBool(streamId,    self.instantOverhaul        or false)
    streamWriteBool(streamId,    self.dealerAlwaysAvailable  or false)
    streamWriteBool(streamId,    self.mobileAlwaysAvailable  or false)
    streamWriteBool(streamId,    self.ownAlwaysAvailable     or false)
    streamWriteBool(streamId,    self.mobileWorkshopRestrictionsEnabled or false)
    streamWriteFloat32(streamId, self.openHour               or 8)
    streamWriteFloat32(streamId, self.closeHour              or 19)
    streamWriteBool(streamId,    self.debugMode              or false)
    streamWriteBool(streamId,    self.drivetrainEnabled ~= false)
    streamWriteBool(streamId,    self.drivetrainAllowAutoMode ~= false)
    streamWriteBool(streamId,    self.drivetrainParkBrakeEnabled ~= false)
    streamWriteBool(streamId,    self.exhaustSmokeEnabled ~= false)
end


---Reads event data from a stream.
-- @param integer streamId streamId
-- @param any connection connection
function RMS_SettingsSyncEvent:readStream(streamId, connection)
    self.baseServiceWear           = streamReadFloat32(streamId)
    self.baseSystemsWear           = streamReadFloat32(streamId)
    self.enableWarningMessages     = streamReadBool(streamId)
    self.instantInspection         = streamReadBool(streamId)
    self.instantMaintenanceRepair  = streamReadBool(streamId)
    self.instantBodywork           = streamReadBool(streamId)
    self.instantOverhaul           = streamReadBool(streamId)
    self.dealerAlwaysAvailable     = streamReadBool(streamId)
    self.mobileAlwaysAvailable     = streamReadBool(streamId)
    self.ownAlwaysAvailable        = streamReadBool(streamId)
    self.mobileWorkshopRestrictionsEnabled = streamReadBool(streamId)
    self.openHour                  = streamReadFloat32(streamId)
    self.closeHour                 = streamReadFloat32(streamId)
    self.debugMode                 = streamReadBool(streamId)
    self.drivetrainEnabled         = streamReadBool(streamId)
    self.drivetrainAllowAutoMode   = streamReadBool(streamId)
    self.drivetrainParkBrakeEnabled = streamReadBool(streamId)
    self.exhaustSmokeEnabled       = streamReadBool(streamId)

    self:run(connection)
end


---Writes the received values into RMS_Config
local function applyConfig(event)
    local oldConfig = {
        instantInspection = RMS_Config.MAINTENANCE.INSTANT_INSPECTION,
        instantMaintenanceRepair = RMS_Config.MAINTENANCE.INSTANT_MAINTENANCE_REPAIR,
        instantBodywork = RMS_Config.MAINTENANCE.INSTANT_BODYWORK,
        instantOverhaul = RMS_Config.MAINTENANCE.INSTANT_OVERHAUL
    }

    RMS_Config.CORE.BASE_SERVICE_WEAR                      = event.baseServiceWear
    RMS_Config.CORE.BASE_SYSTEMS_WEAR                      = event.baseSystemsWear
    RMS_Config.CORE.ENABLE_WARNING_MESSAGES                = event.enableWarningMessages
    RMS_Config.MAINTENANCE.INSTANT_INSPECTION               = event.instantInspection
    RMS_Config.MAINTENANCE.INSTANT_MAINTENANCE_REPAIR       = event.instantMaintenanceRepair
    RMS_Config.MAINTENANCE.INSTANT_BODYWORK                 = event.instantBodywork
    RMS_Config.MAINTENANCE.INSTANT_OVERHAUL                 = event.instantOverhaul
    RMS_Config.WORKSHOP.DEALER_ALWAYS_AVAILABLE             = event.dealerAlwaysAvailable
    RMS_Config.WORKSHOP.MOBILE_ALWAYS_AVAILABLE             = event.mobileAlwaysAvailable
    RMS_Config.WORKSHOP.OWN_ALWAYS_AVAILABLE                = event.ownAlwaysAvailable
    RMS_Config.WORKSHOP.MOBILE_WORKSHOP_RESTRICTIONS_ENABLED = event.mobileWorkshopRestrictionsEnabled
    RMS_Config.WORKSHOP.OPEN_HOUR                           = event.openHour
    RMS_Config.WORKSHOP.CLOSE_HOUR                          = event.closeHour
    RMS_Config.DEBUG                                        = event.debugMode
    RMS_Config.DRIVETRAIN.ENABLED                           = event.drivetrainEnabled ~= false
    RMS_Config.DRIVETRAIN.ALLOW_AUTO_MODE                   = event.drivetrainAllowAutoMode ~= false
    RMS_Config.DRIVETRAIN.PARKBRAKE_ENABLED                 = event.drivetrainParkBrakeEnabled ~= false
    RMS_Config.EXHAUST.ENABLED                              = event.exhaustSmokeEnabled ~= false

    local newConfig = {
        instantInspection = event.instantInspection,
        instantMaintenanceRepair = event.instantMaintenanceRepair,
        instantBodywork = event.instantBodywork,
        instantOverhaul = event.instantOverhaul
    }

    RMS_SettingsPage.finishInstantServices(oldConfig, newConfig)
    RMS_Drivetrain.refreshAllParkBrakePedals()
    RMS_Drivetrain.claimFromOtherMod()

    RMS_Main:forceWorkshopUpdate(true)
end


---Run action on receiving side
-- @param any connection connection
function RMS_SettingsSyncEvent:run(connection)
    if not connection:getIsServer() then
        local userId = g_currentMission.userManager:getUserIdByConnection(connection)
        local user = g_currentMission.userManager:getUserByUserId(userId)
        if user == nil or not user:getIsMasterUser() then
            return
        end

        applyConfig(self)
        g_server:broadcastEvent(RMS_SettingsSyncEvent.new(), nil, connection)
    else
        applyConfig(self)
    end
end


---Send the local configuration from a client to the server
function RMS_SettingsSyncEvent.send()
    if g_client ~= nil then
        g_client:getServerConnection():sendEvent(RMS_SettingsSyncEvent.new())
    end
end

---Synchronizes the current configuration.
function RMS_SettingsSyncEvent.share()
    if g_currentMission:getIsServer() then
        RMS_Config.saveToXMLFile()
    end

    if g_currentMission:getIsServer() and g_server ~= nil then
        g_server:broadcastEvent(RMS_SettingsSyncEvent.new())
    elseif g_client ~= nil then
        RMS_SettingsSyncEvent.send()
    end
end
