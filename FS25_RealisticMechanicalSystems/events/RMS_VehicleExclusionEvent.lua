-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---User controlled exclusion flag of a vehicle, asked by a player to the server and broadcast by the server to the clients
RMS_VehicleExclusionEvent = {}
local RMS_VehicleExclusionEvent_mt = Class(RMS_VehicleExclusionEvent, Event)

InitEventClass(RMS_VehicleExclusionEvent, "RMS_VehicleExclusionEvent")


---Create instance of Event class
-- @return table self instance of class event
function RMS_VehicleExclusionEvent.emptyNew()
    return Event.new(RMS_VehicleExclusionEvent_mt)
end


---Create new instance of event
-- @param table vehicle vehicle
-- @param boolean isExcludedByUser true if the user excluded the vehicle
-- @return table self instance of class event
function RMS_VehicleExclusionEvent.new(vehicle, isExcludedByUser)
    local self = RMS_VehicleExclusionEvent.emptyNew()
    self.vehicle = vehicle
    self.isExcludedByUser = isExcludedByUser == true
    return self
end


---Writes the vehicle and the flag
-- @param integer streamId streamId
-- @param Connection connection connection
function RMS_VehicleExclusionEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObject(streamId, self.vehicle)
    streamWriteBool(streamId, self.isExcludedByUser)
end


---Reads the vehicle and the flag
-- @param integer streamId streamId
-- @param Connection connection connection
function RMS_VehicleExclusionEvent:readStream(streamId, connection)
    self.vehicle = NetworkUtil.readNodeObject(streamId)
    self.isExcludedByUser = streamReadBool(streamId)
    self:run(connection)
end


---Applies the flag the server sent, or the one a player asked for when the player may change it
-- @param Connection connection connection
function RMS_VehicleExclusionEvent:run(connection)
    local vehicle = self.vehicle
    if vehicle == nil or not vehicle:getIsSynchronized() or vehicle.setRMSUserExcluded == nil then
        return
    end

    if connection:getIsServer() then
        vehicle:setRMSUserExcluded(self.isExcludedByUser, true)
    elseif RealisticMechanicalSystems.getCanSetUserExclusion(vehicle, self.isExcludedByUser, connection) then
        vehicle:setRMSUserExcluded(self.isExcludedByUser)
    end
end


---Broadcast the exclusion flag from the server to the clients of the vehicle
-- @param table vehicle vehicle
-- @param boolean isExcludedByUser true if the user excluded the vehicle
function RMS_VehicleExclusionEvent.sendToClients(vehicle, isExcludedByUser)
    if g_server ~= nil then
        g_server:broadcastEvent(RMS_VehicleExclusionEvent.new(vehicle, isExcludedByUser), nil, nil, vehicle)
    end
end


---Asks for a new exclusion flag, applied at once on the server and sent to it from a client
-- @param table vehicle vehicle
-- @param boolean isExcludedByUser true to exclude the vehicle
function RMS_VehicleExclusionEvent.request(vehicle, isExcludedByUser)
    if g_server ~= nil then
        vehicle:setRMSUserExcluded(isExcludedByUser)
    else
        g_client:getServerConnection():sendEvent(RMS_VehicleExclusionEvent.new(vehicle, isExcludedByUser))
    end
end
