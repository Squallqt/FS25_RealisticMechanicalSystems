-- Copyright © 2026 Squallqt. All rights reserved.

---Welcome window, shown once to each player
RMS_Welcome = {}

---Forgets every player
function RMS_Welcome.reset()
    RMS_Welcome.seenUserIds = {}
    RMS_Welcome.isLocalSeen = nil
end

---Tells whether a player saw the welcome
-- @param string uniqueUserId unique user id of the player
-- @return boolean isSeen true once the player saw it
function RMS_Welcome.getIsSeen(uniqueUserId)
    return RMS_Welcome.seenUserIds[uniqueUserId] == true
end

---Remembers that a player saw the welcome
-- @param string uniqueUserId unique user id of the player
function RMS_Welcome.setSeen(uniqueUserId)
    RMS_Welcome.seenUserIds[uniqueUserId] = true
end

---Writes the players who saw the welcome
-- @param integer xmlFile savegame file
-- @param string key key of the welcome
function RMS_Welcome.saveToXMLFile(xmlFile, key)
    local userIds = {}
    for uniqueUserId, _ in pairs(RMS_Welcome.seenUserIds) do
        table.insert(userIds, uniqueUserId)
    end
    table.sort(userIds)

    for index, uniqueUserId in ipairs(userIds) do
        setXMLString(xmlFile, string.format("%s.player(%d)#uniqueUserId", key, index - 1), uniqueUserId)
    end
end

---Reads the players who saw the welcome
-- @param integer xmlFile savegame file
-- @param string key key of the welcome
function RMS_Welcome.loadFromXMLFile(xmlFile, key)
    local index = 0
    while true do
        local uniqueUserId = getXMLString(xmlFile, string.format("%s.player(%d)#uniqueUserId", key, index))
        if uniqueUserId == nil then
            break
        end
        RMS_Welcome.setSeen(uniqueUserId)
        index = index + 1
    end
end

---Shows the welcome to the local player who has not seen it
-- @param float dt time since last call in ms
function RMS_Welcome:update(dt)
    if g_localPlayer == nil or g_gui:getIsGuiVisible() or g_currentMission.hud:getIsFading() then
        return
    end
    local uniqueUserId = g_localPlayer:getUniqueUserId()
    if string.isNilOrWhitespace(uniqueUserId) then
        return
    end

    local isServer = g_server ~= nil
    if RMS_Welcome.isLocalSeen == nil and isServer then
        RMS_Welcome.isLocalSeen = RMS_Welcome.getIsSeen(uniqueUserId)
    end
    if RMS_Welcome.isLocalSeen ~= false then
        return
    end

    RMS_Welcome.isLocalSeen = true
    local key = g_inputDisplayManager:getKeyboardInputActionKey(InputAction.RMS_FIELD_INSPECTION)
        or g_i18n:getText("input_RMS_FIELD_INSPECTION")
    InfoDialog.show(string.format(g_i18n:getText("rms_welcome_message"), key))
    if isServer then
        RMS_Welcome.setSeen(uniqueUserId)
    else
        RMS_WelcomeEvent.sendToServer()
    end
end

RMS_Welcome.reset()
addModEventListener(RMS_Welcome)
