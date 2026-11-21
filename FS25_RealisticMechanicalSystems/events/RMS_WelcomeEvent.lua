-- Copyright © 2026 Squallqt. All rights reserved.

---Welcome state of a player
RMS_WelcomeEvent = {}
local RMS_WelcomeEvent_mt = Class(RMS_WelcomeEvent, Event)

InitEventClass(RMS_WelcomeEvent, "RMS_WelcomeEvent")

---Create instance of Event class
function RMS_WelcomeEvent.emptyNew()
    return Event.new(RMS_WelcomeEvent_mt)
end

---Create new instance of event
function RMS_WelcomeEvent.new(isSeen)
    local self = RMS_WelcomeEvent.emptyNew()
    self.isSeen = isSeen
    return self
end

---Writes event data to a stream.
function RMS_WelcomeEvent:writeStream(streamId, connection)
    streamWriteBool(streamId, self.isSeen)
end

---Reads event data from a stream.
function RMS_WelcomeEvent:readStream(streamId, connection)
    self.isSeen = streamReadBool(streamId)
    self:run(connection)
end

---Run action on receiving side
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
function RMS_WelcomeEvent.sendToClient(connection, user)
    connection:sendEvent(RMS_WelcomeEvent.new(RMS_Welcome.getIsSeen(user:getUniqueUserId())))
end

---Send the server that the player saw the welcome
function RMS_WelcomeEvent.sendToServer()
    g_client:getServerConnection():sendEvent(RMS_WelcomeEvent.new(true))
end
