-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---Replicates every adjustable RMS_Config value between the admin client, the server and the other clients
RMS_SettingsSyncEvent = {}
local RMS_SettingsSyncEvent_mt = Class(RMS_SettingsSyncEvent, Event)

InitEventClass(RMS_SettingsSyncEvent, "RMS_SettingsSyncEvent")


---Create instance of Event class
-- @return table self instance of class event
function RMS_SettingsSyncEvent.emptyNew()
    return Event.new(RMS_SettingsSyncEvent_mt)
end


---Create new instance of event holding a snapshot of the local configuration
-- @return table self instance of class event
function RMS_SettingsSyncEvent.new()
    local self = RMS_SettingsSyncEvent.emptyNew()

    self.baseServiceWear           = RMS_Config.CORE.BASE_SERVICE_WEAR
    self.baseSystemsWear           = RMS_Config.CORE.BASE_SYSTEMS_WEAR
    self.generalWearEnabled        = RMS_Config.CORE.GENERAL_WEAR_ENABLED
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
    self.temperatureChangeSpeed    = RMS_Config.THERMAL.TEMPERATURE_CHANGE_SPEED
    self.transTemperatureChangeMultiplier = RMS_Config.THERMAL.TRANS_TEMPERATURE_CHANGE_MULTIPLIER
    self.maxDirtInfluence          = RMS_Config.THERMAL.MAX_DIRT_INFLUENCE
    self.batteryUsableCapacityFactor = RMS_Config.ELECTRICAL.BATTERY_USABLE_CAPACITY_FACTOR
    self.alternatorMaxOutput       = RMS_Config.ELECTRICAL.ALT_MAX_OUTPUT
    self.idleCurrentA              = RMS_Config.ELECTRICAL.IDLE_CURRENT_A
    self.debugMode                 = RMS_Config.DEBUG
    self.drivetrainEnabled         = RMS_Config.DRIVETRAIN.ENABLED
    self.drivetrainAllowAutoMode   = RMS_Config.DRIVETRAIN.ALLOW_AUTO_MODE
    self.drivetrainWindupDamage    = RMS_Config.DRIVETRAIN.WINDUP_DAMAGE_ENABLED
    self.drivetrainParkBrakeEnabled = RMS_Config.DRIVETRAIN.PARKBRAKE_ENABLED
    self.drivetrainParkBrakeAuto   = RMS_Config.DRIVETRAIN.PARKBRAKE_AUTO_MODE
    self.exhaustSmokeEnabled       = RMS_Config.EXHAUST.ENABLED

    return self
end


---Called on server side on join, values are written in the order readStream expects them
-- @param integer streamId streamId
-- @param any connection connection
function RMS_SettingsSyncEvent:writeStream(streamId, connection)
    streamWriteFloat32(streamId, self.baseServiceWear       or 0)
    streamWriteFloat32(streamId, self.baseSystemsWear       or 0)
    streamWriteBool(streamId,    self.generalWearEnabled    or false)
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
    streamWriteFloat32(streamId, self.temperatureChangeSpeed or 1.4)
    streamWriteFloat32(streamId, self.transTemperatureChangeMultiplier or 1.0)
    streamWriteFloat32(streamId, self.maxDirtInfluence       or 1.0)
    streamWriteFloat32(streamId, self.batteryUsableCapacityFactor or 0.1)
    streamWriteFloat32(streamId, self.alternatorMaxOutput    or 100)
    streamWriteFloat32(streamId, self.idleCurrentA           or 0.5)
    streamWriteBool(streamId,    self.debugMode              or false)
    streamWriteBool(streamId,    self.drivetrainEnabled ~= false)
    streamWriteBool(streamId,    self.drivetrainAllowAutoMode ~= false)
    streamWriteBool(streamId,    self.drivetrainWindupDamage ~= false)
    streamWriteBool(streamId,    self.drivetrainParkBrakeEnabled ~= false)
    streamWriteBool(streamId,    self.drivetrainParkBrakeAuto ~= false)
    streamWriteBool(streamId,    self.exhaustSmokeEnabled ~= false)
end


---Called on client side on join, values are read in the order writeStream sends them
-- @param integer streamId streamId
-- @param any connection connection
function RMS_SettingsSyncEvent:readStream(streamId, connection)
    self.baseServiceWear           = streamReadFloat32(streamId)
    self.baseSystemsWear           = streamReadFloat32(streamId)
    self.generalWearEnabled        = streamReadBool(streamId)
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
    self.temperatureChangeSpeed    = streamReadFloat32(streamId)
    self.transTemperatureChangeMultiplier = streamReadFloat32(streamId)
    self.maxDirtInfluence          = streamReadFloat32(streamId)
    self.batteryUsableCapacityFactor = streamReadFloat32(streamId)
    self.alternatorMaxOutput       = streamReadFloat32(streamId)
    self.idleCurrentA              = streamReadFloat32(streamId)
    self.debugMode                 = streamReadBool(streamId)
    self.drivetrainEnabled         = streamReadBool(streamId)
    self.drivetrainAllowAutoMode   = streamReadBool(streamId)
    self.drivetrainWindupDamage    = streamReadBool(streamId)
    self.drivetrainParkBrakeEnabled = streamReadBool(streamId)
    self.drivetrainParkBrakeAuto   = streamReadBool(streamId)
    self.exhaustSmokeEnabled       = streamReadBool(streamId)

    self:run(connection)
end


---Writes the received values into RMS_Config, clamping those with a bounded range
-- @param table event event carrying the configuration snapshot
local function applyConfig(event)
    local oldBatteryCapacityFactor = RMS_Config.ELECTRICAL.BATTERY_USABLE_CAPACITY_FACTOR
    local oldConfig = {
        instantInspection = RMS_Config.MAINTENANCE.INSTANT_INSPECTION,
        instantMaintenanceRepair = RMS_Config.MAINTENANCE.INSTANT_MAINTENANCE_REPAIR,
        instantBodywork = RMS_Config.MAINTENANCE.INSTANT_BODYWORK,
        instantOverhaul = RMS_Config.MAINTENANCE.INSTANT_OVERHAUL
    }

    RMS_Config.CORE.BASE_SERVICE_WEAR                      = event.baseServiceWear
    RMS_Config.CORE.BASE_SYSTEMS_WEAR                      = event.baseSystemsWear
    RMS_Config.CORE.GENERAL_WEAR_ENABLED                   = event.generalWearEnabled
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
    RMS_Config.THERMAL.TEMPERATURE_CHANGE_SPEED             = math.clamp(event.temperatureChangeSpeed, 0.5, 2.0)
    RMS_Config.THERMAL.TRANS_TEMPERATURE_CHANGE_MULTIPLIER  = math.clamp(event.transTemperatureChangeMultiplier, 0.5, 2.0)
    RMS_Config.THERMAL.MAX_DIRT_INFLUENCE                   = math.clamp(event.maxDirtInfluence, 0.0, 1.0)
    RMS_Config.ELECTRICAL.BATTERY_USABLE_CAPACITY_FACTOR    = event.batteryUsableCapacityFactor
    RMS_Config.ELECTRICAL.ALT_MAX_OUTPUT                    = event.alternatorMaxOutput
    RMS_Config.ELECTRICAL.IDLE_CURRENT_A                    = event.idleCurrentA
    RMS_Config.DEBUG                                        = event.debugMode
    RMS_Config.DRIVETRAIN.ENABLED                           = event.drivetrainEnabled ~= false
    RMS_Config.DRIVETRAIN.ALLOW_AUTO_MODE                   = event.drivetrainAllowAutoMode ~= false
    RMS_Config.DRIVETRAIN.WINDUP_DAMAGE_ENABLED             = event.drivetrainWindupDamage ~= false
    RMS_Config.DRIVETRAIN.PARKBRAKE_ENABLED                 = event.drivetrainParkBrakeEnabled ~= false
    RMS_Config.DRIVETRAIN.PARKBRAKE_AUTO_MODE               = event.drivetrainParkBrakeAuto ~= false
    RMS_Config.EXHAUST.ENABLED                              = event.exhaustSmokeEnabled ~= false

    local newConfig = {
        instantInspection = event.instantInspection,
        instantMaintenanceRepair = event.instantMaintenanceRepair,
        instantBodywork = event.instantBodywork,
        instantOverhaul = event.instantOverhaul
    }

    RMS_SettingsPage.applyPendingConfigSideEffects(oldConfig, newConfig)

    -- a changed battery capacity factor rescales the charge of every tracked vehicle
    if math.abs((oldBatteryCapacityFactor or 0) - (event.batteryUsableCapacityFactor or 0)) > 0.0001
        and RMS_Main ~= nil and RMS_Main.vehicles ~= nil then
        for _, vehicle in pairs(RMS_Main.vehicles) do
            if vehicle ~= nil and vehicle.spec_RealisticMechanicalSystems ~= nil and not vehicle.spec_RealisticMechanicalSystems.isExcludedVehicle then
                RMS_Electrical.rescaleBatteryChargeFromSoc(vehicle)

                RealisticMechanicalSystems.raiseRMSDirty(vehicle, RealisticMechanicalSystems.SYNC_GROUP.ELECTRICAL)
            end
        end
    end

    RMS_Main:forceWorkshopUpdate(true)
end


---Applies the configuration, and on the server relays it to the other clients for a master user only
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
