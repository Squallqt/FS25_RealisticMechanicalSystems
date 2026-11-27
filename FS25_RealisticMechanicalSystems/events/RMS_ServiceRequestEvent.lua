-- Copyright © 2026 Squallqt. All rights reserved.

---Event asking the server to check the workshop stock or to start a service
RMS_ServiceRequestEvent = {}
local RMS_ServiceRequestEvent_mt = Class(RMS_ServiceRequestEvent, Event)
local networkUtil = NetworkUtil

InitEventClass(RMS_ServiceRequestEvent, "RMS_ServiceRequestEvent")


---Create instance of Event class
-- @return table self instance of class event
function RMS_ServiceRequestEvent.emptyNew()
    return Event.new(RMS_ServiceRequestEvent_mt)
end


---Create new instance of event
-- @param table vehicle vehicle
-- @param string serviceType RealisticMechanicalSystems.STATUS of the service
-- @param string workshopType workshop the service is ordered from
-- @param string? optionOne first option of the service
-- @param string? optionTwo second option of the service
-- @param table? sellingPoint selling point of the workshop
-- @param integer? stockRequestId id of a stock check, nil to start the service
-- @return table self instance of event
function RMS_ServiceRequestEvent.new(vehicle, serviceType, workshopType, optionOne, optionTwo, sellingPoint, stockRequestId)
    local self = RMS_ServiceRequestEvent.emptyNew()
    self.vehicle = vehicle
    self.serviceType = serviceType
    self.workshopType = workshopType
    self.optionOne = optionOne
    self.optionTwo = optionTwo
    self.placeable = sellingPoint ~= nil and sellingPoint.owningPlaceable or nil
    self.stockRequestId = stockRequestId
    return self
end


---Writes event data to a stream
-- @param integer streamId stream id
-- @param Connection connection connection the event goes to
function RMS_ServiceRequestEvent:writeStream(streamId, connection)
    networkUtil.writeNodeObject(streamId, self.vehicle)
    streamWriteString(streamId, self.serviceType)
    streamWriteString(streamId, self.workshopType)
    streamWriteString(streamId, self.optionOne or "")
    streamWriteString(streamId, self.optionTwo or "")
    if streamWriteBool(streamId, self.placeable ~= nil) then
        networkUtil.writeNodeObject(streamId, self.placeable)
    end
    if streamWriteBool(streamId, self.stockRequestId ~= nil) then
        streamWriteUInt32(streamId, self.stockRequestId)
    end
end


---Reads event data from a stream
-- @param integer streamId stream id
-- @param Connection connection connection the event comes from
function RMS_ServiceRequestEvent:readStream(streamId, connection)
    self.vehicle = networkUtil.readNodeObject(streamId)
    self.serviceType = streamReadString(streamId)
    self.workshopType = streamReadString(streamId)
    self.optionOne = streamReadString(streamId)
    self.optionTwo = streamReadString(streamId)
    if streamReadBool(streamId) then
        self.placeable = networkUtil.readNodeObject(streamId)
    end
    if streamReadBool(streamId) then
        self.stockRequestId = streamReadUInt32(streamId)
    end

    -- Empty strings represent absent options
    if self.optionOne == "" then self.optionOne = nil end
    if self.optionTwo == "" then self.optionTwo = nil end

    self:run(connection)
end


---Answers the stock check, or starts the service, for a player of the owning farm
-- @param Connection connection connection the event comes from
function RMS_ServiceRequestEvent:run(connection)
    if self.vehicle ~= nil and self.vehicle:getIsSynchronized() then
        local userId = g_currentMission.userManager:getUserIdByConnection(connection)
        local farm = g_farmManager:getFarmByUserId(userId)
        if farm == nil or farm.farmId ~= self.vehicle:getOwnerFarmId() then
            return
        end

        local workshop = self.placeable ~= nil and self.placeable.spec_workshop or nil
        local sellingPoint = workshop ~= nil and workshop.sellingPoint or nil
        if self.stockRequestId ~= nil then
            local requirements = RMS_FluidWorkshop.getTransactionRequirements(self.vehicle,
                self.serviceType, self.workshopType, self.optionOne, self.optionTwo)
            local shortages = RMS_FluidWorkshop.getStockShortages(self.vehicle, sellingPoint, self.workshopType,
                { { serviceType = self.serviceType, requirements = requirements } })
            connection:sendEvent(RMS_ServiceResultEvent.new(nil, self.stockRequestId, shortages))
            return
        end

        if self.vehicle.spec_RealisticMechanicalSystems.currentState ~= RealisticMechanicalSystems.STATUS.READY
            or not RMS_Main:isWorkshopTypeOpen(self.workshopType) then
            return
        end

        local started, result = RMS_FluidWorkshop.tryStartService(
            self.vehicle,
            sellingPoint,
            self.serviceType,
            self.workshopType,
            self.optionOne,
            self.optionTwo,
            farm.farmId
        )
        if started then
            RMS_VehicleChangeStatusEvent.send(self.vehicle)
        else
            connection:sendEvent(RMS_ServiceResultEvent.new(result))
        end
    end
end


---Sends a stock check or a service request to the server
-- @param table vehicle vehicle
-- @param string serviceType RealisticMechanicalSystems.STATUS of the service
-- @param string workshopType workshop the service is ordered from
-- @param string? optionOne first option of the service
-- @param string? optionTwo second option of the service
-- @param table? sellingPoint selling point of the workshop
-- @param integer? stockRequestId id of a stock check, nil to start the service
function RMS_ServiceRequestEvent.send(vehicle, serviceType, workshopType, optionOne, optionTwo, sellingPoint, stockRequestId)
    g_client:getServerConnection():sendEvent(RMS_ServiceRequestEvent.new(vehicle, serviceType, workshopType,
        optionOne, optionTwo, sellingPoint, stockRequestId))
end
