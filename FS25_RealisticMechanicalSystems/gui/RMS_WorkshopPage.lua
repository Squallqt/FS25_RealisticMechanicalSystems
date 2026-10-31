-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---Page of the workshop, a frame shown under its tabs
RMS_WorkshopPage = {}

local RMS_WorkshopPage_mt = Class(RMS_WorkshopPage, FrameElement)

---Creates a page
-- @param table? target target
-- @param table? customMt metatable of the page class
-- @return table page
function RMS_WorkshopPage.new(target, customMt)
    return FrameElement.new(target, customMt or RMS_WorkshopPage_mt)
end

---Keeps the dialog the page belongs to
-- @param table dialog workshop dialog
function RMS_WorkshopPage:initialize(dialog)
    self.dialog = dialog
end

---Keeps the vehicle on screen and the workshop it stands in
-- @param table? vehicle vehicle, nil once the dialog closed
-- @param string? workshopType workshop, nil for the record only
function RMS_WorkshopPage:setVehicle(vehicle, workshopType)
    self.vehicle = vehicle
    self.workshopType = workshopType
end

---Columns of rows the focus moves over
-- @return table columns
function RMS_WorkshopPage:getFocusColumns()
    return {}
end

---Element the focus enters the page on
-- @return table? element
function RMS_WorkshopPage:getFocusEntry()
    return nil
end

---Button the page puts in the bar in place of the shortcuts
-- @return string? text button text, nil without one
-- @return boolean isDisabled true when the action cannot run
function RMS_WorkshopPage:getAction()
    return nil, true
end

---Leaves a view opened inside the page
-- @return boolean isLeft true when a view was left
function RMS_WorkshopPage:goBack()
    return false
end
