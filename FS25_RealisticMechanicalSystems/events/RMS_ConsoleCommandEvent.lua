-- Copyright © 2026 Squallqt. All rights reserved.

---Event running a console command on the server
RMS_ConsoleCommandEvent = {}
local RMS_ConsoleCommandEvent_mt = Class(RMS_ConsoleCommandEvent, Event)

InitEventClass(RMS_ConsoleCommandEvent, "RMS_ConsoleCommandEvent")

---Create instance of Event class
-- @return table self instance of class event
function RMS_ConsoleCommandEvent.emptyNew()
    return Event.new(RMS_ConsoleCommandEvent_mt)
end


---Create new instance of event
-- @param string commandName command, or "__response" from the server
-- @param string? argsOne first argument
-- @param string? argsTwo second argument
-- @param table? vehicle vehicle the command applies to
-- @return table self instance of event
function RMS_ConsoleCommandEvent.new(commandName, argsOne, argsTwo, vehicle)
    local self = RMS_ConsoleCommandEvent.emptyNew()
    self.commandName = commandName
    self.argsOne = argsOne
    self.argsTwo = argsTwo
    self.vehicle = vehicle
    return self
end


---Writes event data to a stream
-- @param integer streamId stream id
-- @param Connection connection connection the event goes to
function RMS_ConsoleCommandEvent:writeStream(streamId, connection)
    streamWriteString(streamId, self.commandName)
    streamWriteString(streamId, self.argsOne or "")
    streamWriteString(streamId, self.argsTwo or "")
    local hasVehicle = self.vehicle ~= nil
    streamWriteBool(streamId, hasVehicle)
    if hasVehicle then
        NetworkUtil.writeNodeObject(streamId, self.vehicle)
    end
end


---Reads event data from a stream
-- @param integer streamId stream id
-- @param Connection connection connection the event comes from
function RMS_ConsoleCommandEvent:readStream(streamId, connection)
    self.commandName = streamReadString(streamId)
    self.argsOne = streamReadString(streamId)
    self.argsTwo = streamReadString(streamId)
    local hasVehicle = streamReadBool(streamId)
    if hasVehicle then
        self.vehicle = NetworkUtil.readNodeObject(streamId)
    end

    -- Empty strings represent absent arguments
    if self.argsOne == "" then self.argsOne = nil end
    if self.argsTwo == "" then self.argsTwo = nil end

    self:run(connection)
end


---Runs a command for an admin on the server, or prints the server's answer
-- @param Connection connection connection the event comes from
function RMS_ConsoleCommandEvent:run(connection)
    if connection:getIsServer() then
        if self.commandName == "__response" and self.argsOne ~= nil then
            print(self.argsOne)
        end
        return
    end

    local userId = g_currentMission.userManager:getUserIdByConnection(connection)
    local user = g_currentMission.userManager:getUserByUserId(userId)
    if user == nil or not user:getIsMasterUser() or self.vehicle == nil then
        return
    end

    local commands = RealisticMechanicalSystems.ConsoleCommands
    commands._overrideVehicle = self.vehicle
    commands._outputConnection = connection
    commands[self.commandName](commands, self.argsOne, self.argsTwo)
    commands._overrideVehicle = nil
    commands._outputConnection = nil

    RealisticMechanicalSystems.raiseRMSDirty(self.vehicle, RealisticMechanicalSystems.SYNC_GROUP.STATE)
    RealisticMechanicalSystems.raiseRMSDirty(self.vehicle, RealisticMechanicalSystems.SYNC_GROUP.SERVICE_CONTEXT)
    RealisticMechanicalSystems.raiseRMSDirty(self.vehicle, RealisticMechanicalSystems.SYNC_GROUP.TELEMETRY)
    RealisticMechanicalSystems.raiseRMSDirty(self.vehicle, RealisticMechanicalSystems.SYNC_GROUP.THERMAL)
    RealisticMechanicalSystems.raiseRMSDirty(self.vehicle, RealisticMechanicalSystems.SYNC_GROUP.ELECTRICAL)
    RealisticMechanicalSystems.raiseRMSDirty(self.vehicle, RealisticMechanicalSystems.SYNC_GROUP.FIELDCARE)
    RealisticMechanicalSystems.raiseRMSDirty(self.vehicle, RealisticMechanicalSystems.SYNC_GROUP.WEAR)
    RealisticMechanicalSystems.raiseRMSDirty(self.vehicle, RealisticMechanicalSystems.SYNC_GROUP.BREAKDOWNS)
    RealisticMechanicalSystems.raiseRMSDirty(self.vehicle, RealisticMechanicalSystems.SYNC_GROUP.SERVICE_PROGRESS)
end


---Send the console command from a client to the server
-- @param string commandName command
-- @param string? argsOne first argument
-- @param string? argsTwo second argument
-- @param table? vehicle vehicle the command applies to
function RMS_ConsoleCommandEvent.sendToServer(commandName, argsOne, argsTwo, vehicle)
    if not g_currentMission.isMasterUser then
        print("RMS: Admin access required.")
        return
    end
    g_client:getServerConnection():sendEvent(RMS_ConsoleCommandEvent.new(commandName, argsOne, argsTwo, vehicle))
end
