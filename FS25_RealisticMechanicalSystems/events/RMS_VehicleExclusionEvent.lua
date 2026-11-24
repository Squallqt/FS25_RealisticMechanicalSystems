-- Copyright © 2026 Squallqt. All rights reserved.

---Event asking for and sharing whether a player left a vehicle out of RMS
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
-- @param boolean isExcludedByUser true to leave the vehicle out
-- @return table self instance of event
function RMS_VehicleExclusionEvent.new(vehicle, isExcludedByUser)
    local self = RMS_VehicleExclusionEvent.emptyNew()
    self.vehicle = vehicle
    self.isExcludedByUser = isExcludedByUser
    return self
end


---Writes event data to a stream
-- @param integer streamId stream id
-- @param Connection connection connection the event goes to
function RMS_VehicleExclusionEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObject(streamId, self.vehicle)
    streamWriteBool(streamId, self.isExcludedByUser)
end


---Reads event data from a stream
-- @param integer streamId stream id
-- @param Connection connection connection the event comes from
function RMS_VehicleExclusionEvent:readStream(streamId, connection)
    self.vehicle = NetworkUtil.readNodeObject(streamId)
    self.isExcludedByUser = streamReadBool(streamId)
    self:run(connection)
end


---Applies the flag on a client, or on the server when the sender may set it
-- @param Connection connection connection the event comes from
function RMS_VehicleExclusionEvent:run(connection)
    local vehicle = self.vehicle
    if vehicle == nil or not vehicle:getIsSynchronized() then
        return
    end

    if connection:getIsServer() then
        vehicle:setRMSUserExcluded(self.isExcludedByUser)
    elseif RealisticMechanicalSystems.getCanSetUserExclusion(vehicle, self.isExcludedByUser, connection) then
        vehicle:setRMSUserExcluded(self.isExcludedByUser)
    end
end


---Broadcast the exclusion flag from the server to the clients of the vehicle
-- @param table vehicle vehicle
-- @param boolean isExcludedByUser true when the vehicle is left out
function RMS_VehicleExclusionEvent.sendToClients(vehicle, isExcludedByUser)
    g_server:broadcastEvent(RMS_VehicleExclusionEvent.new(vehicle, isExcludedByUser), nil, nil, vehicle)
end


---Asks for a new exclusion flag, through the server
-- @param table vehicle vehicle
-- @param boolean isExcludedByUser true to leave the vehicle out
function RMS_VehicleExclusionEvent.request(vehicle, isExcludedByUser)
    if g_server ~= nil then
        vehicle:setRMSUserExcluded(isExcludedByUser)
    else
        g_client:getServerConnection():sendEvent(RMS_VehicleExclusionEvent.new(vehicle, isExcludedByUser))
    end
end
