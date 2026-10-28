-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---Debug reading request and response event.
RMS_DebugReadingEvent = {}
local RMS_DebugReadingEvent_mt = Class(RMS_DebugReadingEvent, Event)

InitEventClass(RMS_DebugReadingEvent, "RMS_DebugReadingEvent")

---Create instance of Event class
-- @return table self instance of class event
function RMS_DebugReadingEvent.emptyNew()
    return Event.new(RMS_DebugReadingEvent_mt)
end

---Create new instance of event
-- @param table vehicle vehicle
-- @param table? reading reading of the server, nil for the request of a client
-- @return table self instance of class event
function RMS_DebugReadingEvent.new(vehicle, reading)
    local self = RMS_DebugReadingEvent.emptyNew()
    self.vehicle = vehicle
    self.reading = reading
    return self
end

---Writes the event to a stream
-- @param integer streamId streamId
-- @param Connection connection connection
function RMS_DebugReadingEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObject(streamId, self.vehicle)
    if streamWriteBool(streamId, self.reading ~= nil) then
        RMS_DebugReading.writeStream(streamId, self.reading)
    end
end

---Reads the event from a stream
-- @param integer streamId streamId
-- @param Connection connection connection
function RMS_DebugReadingEvent:readStream(streamId, connection)
    self.vehicle = NetworkUtil.readNodeObject(streamId)
    if streamReadBool(streamId) then
        self.reading = RMS_DebugReading.readStream(streamId)
    end
    self:run(connection)
end

---Server answers an admin request; the client keeps the answer
-- @param Connection connection connection
function RMS_DebugReadingEvent:run(connection)
    local vehicle = self.vehicle
    if vehicle == nil or vehicle.spec_RealisticMechanicalSystems == nil
        or vehicle.spec_RealisticMechanicalSystems.isExcludedVehicle then
        return
    end

    if not connection:getIsServer() then
        local userId = g_currentMission.userManager:getUserIdByConnection(connection)
        local user = g_currentMission.userManager:getUserByUserId(userId)
        if user ~= nil and user:getIsMasterUser() then
            connection:sendEvent(RMS_DebugReadingEvent.new(vehicle, RMS_DebugReading.read(vehicle)))
        end
        return
    end

    RMS_DebugReading.useLocalExhaust(vehicle, self.reading)
    RMS_DebugReading.serverReading = { vehicle = vehicle, reading = self.reading, time = g_time }
end

---Asks the server for the reading of a machine
-- @param table vehicle vehicle
function RMS_DebugReadingEvent.request(vehicle)
    g_client:getServerConnection():sendEvent(RMS_DebugReadingEvent.new(vehicle))
end
