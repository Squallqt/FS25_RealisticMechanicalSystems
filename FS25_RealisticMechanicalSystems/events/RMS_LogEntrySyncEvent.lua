-- Copyright © 2026 Squallqt. All rights reserved.

---Event sending one maintenance log entry from the server to the clients
RMS_LogEntrySyncEvent = {}
local RMS_LogEntrySyncEvent_mt = Class(RMS_LogEntrySyncEvent, Event)

InitEventClass(RMS_LogEntrySyncEvent, "RMS_LogEntrySyncEvent")


---Create instance of Event class
-- @return table self instance of class event
function RMS_LogEntrySyncEvent.emptyNew()
    return Event.new(RMS_LogEntrySyncEvent_mt)
end


---Create new instance of event
-- @param table vehicle vehicle
-- @param string serializedEntry serialized log entry
-- @return table self instance of event
function RMS_LogEntrySyncEvent.new(vehicle, serializedEntry)
    local self = RMS_LogEntrySyncEvent.emptyNew()
    self.vehicle = vehicle
    self.serializedEntry = serializedEntry
    return self
end


---Writes event data to a stream
-- @param integer streamId stream id
-- @param Connection connection connection the event goes to
function RMS_LogEntrySyncEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObject(streamId, self.vehicle)
    streamWriteString(streamId, self.serializedEntry)
end


---Reads event data from a stream
-- @param integer streamId stream id
-- @param Connection connection connection the event comes from
function RMS_LogEntrySyncEvent:readStream(streamId, connection)
    self.vehicle = NetworkUtil.readNodeObject(streamId)
    self.serializedEntry = streamReadString(streamId)
    self:run(connection)
end


---Adds the entry to the log, or replaces the entry of the same id
-- @param Connection connection connection the event comes from
function RMS_LogEntrySyncEvent:run(connection)
    local vehicle = self.vehicle
    if vehicle == nil or not vehicle:getIsSynchronized() then
        return
    end

    local spec = vehicle.spec_RealisticMechanicalSystems

    local entry = RMS_Utils.deserializeMaintenanceLogEntry(self.serializedEntry)
    for i, existingEntry in ipairs(spec.maintenanceLog) do
        if existingEntry.id == entry.id then
            spec.maintenanceLog[i] = entry
            return
        end
    end

    table.insert(spec.maintenanceLog, entry)
end


---Sends the entry from the server to the clients of the vehicle
-- @param table vehicle vehicle
-- @param table entry log entry
function RMS_LogEntrySyncEvent.sendToClients(vehicle, entry)
    local serialized = RMS_Utils.serializeMaintenanceLogEntry(entry)
    g_server:broadcastEvent(RMS_LogEntrySyncEvent.new(vehicle, serialized), nil, nil, vehicle)
end
