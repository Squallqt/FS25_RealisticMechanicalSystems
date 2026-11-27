-- Copyright © 2026 Squallqt. All rights reserved.

---Screen lending the debug window the mouse
RMS_DebugScreen = {}

local RMS_DebugScreen_mt = Class(RMS_DebugScreen, MessageDialog)

---Create instance of RMS_DebugScreen
-- @return table self instance of the screen
function RMS_DebugScreen.new()
    local self = MessageDialog.new(nil, RMS_DebugScreen_mt)
    self:setDisableOpenSound(true)
    return self
end

---Draws the screen, then the mouse of the debug window
-- @param any ... arguments of the game's draw
function RMS_DebugScreen:draw(...)
    RMS_DebugScreen:superClass().draw(self, ...)
    RMS_DebugWindow.drawMouse()
end

---Hands every mouse event to the debug window
-- @param float posX mouse x (screen)
-- @param float posY mouse y (screen)
-- @param boolean isDown true when a button went down
-- @param boolean isUp true when a button went up
-- @param integer button mouse button
-- @param boolean eventUsed true when the event was used already
-- @return boolean eventUsed always true
function RMS_DebugScreen:mouseEvent(posX, posY, isDown, isUp, button, eventUsed)
    RMS_DebugWindow.onMouseEvent(posX, posY, isDown, isUp, button)
    return true
end

---Closes the debug window on back
-- @param string action input action
-- @param float value input value
-- @param boolean eventUsed true when the event was used already
-- @return boolean eventUsed true when the event is used
function RMS_DebugScreen:inputEvent(action, value, eventUsed)
    if action == InputAction.MENU_BACK then
        RMS_DebugWindow.setOpen(false)
        return true
    end
    return RMS_DebugScreen:superClass().inputEvent(self, action, value, eventUsed)
end

---Lays the debug window out again once the mouse is given back
function RMS_DebugScreen:onClose()
    RMS_DebugScreen:superClass().onClose(self)
    RMS_DebugWindow.invalidate()
end
