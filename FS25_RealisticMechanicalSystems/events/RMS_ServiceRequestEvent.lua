-- Copyright © 2026 Squallqt. All rights reserved.

RMS_ServiceRequestEvent = {}
local RMS_ServiceRequestEvent_mt = Class(RMS_ServiceRequestEvent, Event)

InitEventClass(RMS_ServiceRequestEvent, "RMS_ServiceRequestEvent")


---Create instance of Event class
function RMS_ServiceRequestEvent.emptyNew()
    return Event.new(RMS_ServiceRequestEvent_mt)
end


---Create new instance of event
function RMS_ServiceRequestEvent.new(vehicle, serviceType, workshopType, optionOne, optionTwo, optionThree)
    local self = RMS_ServiceRequestEvent.emptyNew()
    self.vehicle = vehicle
    self.serviceType = serviceType
    self.workshopType = workshopType
    self.optionOne = optionOne
    self.optionTwo = optionTwo
    self.optionThree = optionThree
    return self
end


---Writes event data to a stream.
function RMS_ServiceRequestEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObject(streamId, self.vehicle)
    streamWriteString(streamId, self.serviceType or "")
    streamWriteString(streamId, self.workshopType or "")
    streamWriteString(streamId, self.optionOne or "")
    streamWriteString(streamId, self.optionTwo or "")
    streamWriteBool(streamId, self.optionThree or false)
end


---Reads event data from a stream.
function RMS_ServiceRequestEvent:readStream(streamId, connection)
    self.vehicle = NetworkUtil.readNodeObject(streamId)
    self.serviceType = streamReadString(streamId)
    self.workshopType = streamReadString(streamId)
    self.optionOne = streamReadString(streamId)
    self.optionTwo = streamReadString(streamId)
    self.optionThree = streamReadBool(streamId)

    -- Empty strings represent absent options.
    if self.optionOne == "" then self.optionOne = nil end
    if self.optionTwo == "" then self.optionTwo = nil end
    if self.workshopType == "" then self.workshopType = nil end

    self:run(connection)
end


---Run action on receiving side
function RMS_ServiceRequestEvent:run(connection)
    if not connection:getIsServer() then
        if self.vehicle ~= nil and self.vehicle:getIsSynchronized() and self.vehicle.spec_RealisticMechanicalSystems ~= nil then
            local userId = g_currentMission.userManager:getUserIdByConnection(connection)
            local farm = g_farmManager:getFarmByUserId(userId)
            if farm == nil or farm.farmId ~= self.vehicle:getOwnerFarmId() then
                return
            end

            local spec = self.vehicle.spec_RealisticMechanicalSystems
            if spec.currentState ~= RealisticMechanicalSystems.STATUS.READY then
                return
            end

            local validTypes = {
                [RealisticMechanicalSystems.STATUS.INSPECTION] = true,
                [RealisticMechanicalSystems.STATUS.MAINTENANCE] = true,
                [RealisticMechanicalSystems.STATUS.REPAIR] = true,
                [RealisticMechanicalSystems.STATUS.REFILL] = true,
                [RealisticMechanicalSystems.STATUS.OVERHAUL] = true,
                [RealisticMechanicalSystems.STATUS.BODYWORK] = true,
                [RealisticMechanicalSystems.STATUS.REMAP] = true
            }
            if not validTypes[self.serviceType] then
                return
            end

            if not RMS_Main:isWorkshopTypeOpen(self.workshopType) then
                return
            end

            local started, result = RMS_FluidWorkshop.tryStartService(
                self.vehicle,
                nil,
                self.serviceType,
                self.workshopType,
                self.optionOne,
                self.optionTwo,
                self.optionThree,
                farm.farmId
            )
            if started then
                RMS_VehicleChangeStatusEvent.send(self.vehicle)
            else
                connection:sendEvent(RMS_ServiceResultEvent.new(result))
            end
        end
    end
end


---Send the service request from a client to the server
function RMS_ServiceRequestEvent.send(vehicle, serviceType, workshopType, optionOne, optionTwo, optionThree)
    if g_client ~= nil then
        g_client:getServerConnection():sendEvent(RMS_ServiceRequestEvent.new(vehicle, serviceType, workshopType, optionOne, optionTwo, optionThree))
    end
end
