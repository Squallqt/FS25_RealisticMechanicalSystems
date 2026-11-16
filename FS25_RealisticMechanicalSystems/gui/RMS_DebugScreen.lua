-- Copyright © 2026 Squallqt. All rights reserved.

---Screen lending the debug window the mouse.
RMS_DebugScreen = {}
RMS_DebugScreen.INSTANCE = nil

local RMS_DebugScreen_mt = Class(RMS_DebugScreen, MessageDialog)

---Create instance of RMS_DebugScreen
function RMS_DebugScreen.new(target, customMt)
    local self = MessageDialog.new(target, customMt or RMS_DebugScreen_mt)
    self:setDisableOpenSound(true)
    return self
end

function RMS_DebugScreen:draw(...)
    RMS_DebugScreen:superClass().draw(self, ...)
    RMS_DebugWindow.drawMouse()
end

function RMS_DebugScreen:mouseEvent(posX, posY, isDown, isUp, button, eventUsed)
    RMS_DebugWindow.onMouseEvent(posX, posY, isDown, isUp, button)
    return true
end

function RMS_DebugScreen:inputEvent(action, value, eventUsed)
    if action == InputAction.MENU_BACK and not eventUsed then
        RMS_DebugWindow.setOpen(false)
        return true
    end
    return RMS_DebugScreen:superClass().inputEvent(self, action, value, eventUsed)
end

function RMS_DebugScreen:onClose()
    RMS_DebugScreen:superClass().onClose(self)
    RMS_DebugWindow.invalidate()
end
