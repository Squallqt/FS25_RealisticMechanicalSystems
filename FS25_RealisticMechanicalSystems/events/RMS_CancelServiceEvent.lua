-- Copyright © 2026 Squallqt. All rights reserved.

---Event asking the server to cancel the service in progress on a vehicle
RMS_CancelServiceEvent = {}
local RMS_CancelServiceEvent_mt = Class(RMS_CancelServiceEvent, Event)

InitEventClass(RMS_CancelServiceEvent, "RMS_CancelServiceEvent")


---Create instance of Event class
-- @return table self instance of class event
function RMS_CancelServiceEvent.emptyNew()
    return Event.new(RMS_CancelServiceEvent_mt)
end


---Create new instance of event
-- @param table vehicle vehicle
-- @return table self instance of event
function RMS_CancelServiceEvent.new(vehicle)
    local self = RMS_CancelServiceEvent.emptyNew()
    self.vehicle = vehicle
    return self
end


---Writes event data to a stream
-- @param integer streamId stream id
-- @param Connection connection connection the event goes to
function RMS_CancelServiceEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObject(streamId, self.vehicle)
end


---Reads event data from a stream
-- @param integer streamId stream id
-- @param Connection connection connection the event comes from
function RMS_CancelServiceEvent:readStream(streamId, connection)
    self.vehicle = NetworkUtil.readNodeObject(streamId)
    self:run(connection)
end


---Cancels the service on the server for a player of the owning farm
-- @param Connection connection connection the event comes from
function RMS_CancelServiceEvent:run(connection)
    if self.vehicle ~= nil and self.vehicle:getIsSynchronized() then
        local userId = g_currentMission.userManager:getUserIdByConnection(connection)
        local farm = g_farmManager:getFarmByUserId(userId)
        if farm == nil or farm.farmId ~= self.vehicle:getOwnerFarmId() then
            return
        end

        local spec = self.vehicle.spec_RealisticMechanicalSystems
        if spec.currentState == RealisticMechanicalSystems.STATUS.READY then
            return
        end

        self.vehicle:cancelService()
    end
end


---Send the cancel request from a client to the server
-- @param table vehicle vehicle
function RMS_CancelServiceEvent.send(vehicle)
    g_client:getServerConnection():sendEvent(RMS_CancelServiceEvent.new(vehicle))
end
