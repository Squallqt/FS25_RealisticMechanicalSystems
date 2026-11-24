-- Copyright © 2026 Squallqt. All rights reserved.

---Page of the workshop, a frame shown under its tabs
RMS_WorkshopPage = {}

Class(RMS_WorkshopPage, FrameElement)

---Creates a page
-- @param table customMt metatable of the page class
-- @return table self instance of the page
function RMS_WorkshopPage.new(customMt)
    return FrameElement.new(nil, customMt)
end

---Keeps the dialog the page belongs to
-- @param table dialog workshop dialog
function RMS_WorkshopPage:initialize(dialog)
    self.dialog = dialog
end

---Keeps the vehicle on screen and the workshop it stands in
-- @param table vehicle vehicle
-- @param string? workshopType workshop, nil for the record alone
function RMS_WorkshopPage:setVehicle(vehicle, workshopType)
    self.vehicle = vehicle
    self.workshopType = workshopType
end

---Element the focus enters the page on
-- @return table? element element, nil for none
function RMS_WorkshopPage:getFocusEntry()
    return nil
end

---Button the page puts in the bar in place of the shortcuts
-- @return string? text text of the button, nil for none
-- @return boolean isDisabled true when the button is disabled
function RMS_WorkshopPage:getAction()
    return nil, true
end

---Leaves a view opened inside the page
-- @return boolean isHandled true when the page left a view
function RMS_WorkshopPage:goBack()
    return false
end
