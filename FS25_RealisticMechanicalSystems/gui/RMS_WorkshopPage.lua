-- Copyright © 2026 Squallqt. All rights reserved.

---Page of the workshop, a frame shown under its tabs
RMS_WorkshopPage = {}

local RMS_WorkshopPage_mt = Class(RMS_WorkshopPage, FrameElement)

---Creates a page
function RMS_WorkshopPage.new(target, customMt)
    return FrameElement.new(target, customMt or RMS_WorkshopPage_mt)
end

---Keeps the dialog the page belongs to
function RMS_WorkshopPage:initialize(dialog)
    self.dialog = dialog
end

---Keeps the vehicle on screen and the workshop it stands in
function RMS_WorkshopPage:setVehicle(vehicle, workshopType)
    self.vehicle = vehicle
    self.workshopType = workshopType
end

---Columns of rows the focus moves over
function RMS_WorkshopPage:getFocusColumns()
    return {}
end

---Element the focus enters the page on
function RMS_WorkshopPage:getFocusEntry()
    return nil
end

---Button the page puts in the bar in place of the shortcuts
function RMS_WorkshopPage:getAction()
    return nil, true
end

---Leaves a view opened inside the page
function RMS_WorkshopPage:goBack()
    return false
end
