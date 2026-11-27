-- Copyright © 2026 Squallqt. All rights reserved.

---Event carrying whether a player saw the welcome window
RMS_WelcomeEvent = {}
local RMS_WelcomeEvent_mt = Class(RMS_WelcomeEvent, Event)

InitEventClass(RMS_WelcomeEvent, "RMS_WelcomeEvent")

---Create instance of Event class
-- @return table self instance of class event
function RMS_WelcomeEvent.emptyNew()
    return Event.new(RMS_WelcomeEvent_mt)
end

---Create new instance of event
-- @param boolean isSeen true once the player saw the welcome
-- @return table self instance of event
function RMS_WelcomeEvent.new(isSeen)
    local self = RMS_WelcomeEvent.emptyNew()
    self.isSeen = isSeen
    return self
end

---Writes event data to a stream
-- @param integer streamId stream id
-- @param Connection connection connection the event goes to
function RMS_WelcomeEvent:writeStream(streamId, connection)
    streamWriteBool(streamId, self.isSeen)
end

---Reads event data from a stream
-- @param integer streamId stream id
-- @param Connection connection connection the event comes from
function RMS_WelcomeEvent:readStream(streamId, connection)
    self.isSeen = streamReadBool(streamId)
    self:run(connection)
end

---Keeps the state on the client, saves it for the user on the server
-- @param Connection connection connection the event comes from
function RMS_WelcomeEvent:run(connection)
    if connection:getIsServer() then
        RMS_Welcome.isLocalSeen = self.isSeen
        return
    end

    local user = g_currentMission.userManager:getUserByConnection(connection)
    if user ~= nil then
        RMS_Welcome.setSeen(user:getUniqueUserId())
    end
end

---Send a joining player whether they saw the welcome
-- @param Connection connection connection of the player
-- @param table user user of the player
function RMS_WelcomeEvent.sendToClient(connection, user)
    connection:sendEvent(RMS_WelcomeEvent.new(RMS_Welcome.getIsSeen(user:getUniqueUserId())))
end

---Send the server that the player saw the welcome
function RMS_WelcomeEvent.sendToServer()
    g_client:getServerConnection():sendEvent(RMS_WelcomeEvent.new(true))
end
