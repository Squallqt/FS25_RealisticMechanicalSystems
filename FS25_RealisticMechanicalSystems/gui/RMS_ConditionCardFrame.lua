-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---Condition card: the last report, system by system, and its age
RMS_ConditionCardFrame = {}

local RMS_ConditionCardFrame_mt = Class(RMS_ConditionCardFrame, FrameElement)

---Creates the card
function RMS_ConditionCardFrame.new()
    local self = FrameElement.new(nil, RMS_ConditionCardFrame_mt)
    self.stateRows = {}
    return self
end

---Wires the callbacks and the condition list of a placed card
function RMS_ConditionCardFrame:initialize()
    -- a card cloned with its page still calls the card it was copied from
    self:setTarget(self, self:getRootElement().target)
    self.stateList:setDataSource(self)
    self.stateList:setDelegate(self)
end

---Keeps the vehicle the card reads, its systems folded when it changes
function RMS_ConditionCardFrame:setVehicle(vehicle)
    if vehicle ~= self.vehicle then
        self.openSystem = nil
    end
    self.vehicle = vehicle
end

---Writes the ring, the systems and the age of the reference report
function RMS_ConditionCardFrame:refresh()
    local vehicle = self.vehicle
    local reading = RMS_Utils.getInspectionReading(vehicle)
    self.reading = reading
    self.valueText:setText(reading.conditionText)
    self.valueText:setTextColor(unpack(reading.conditionColor))
    self.outdatedText:setVisible(reading.isOutdated)
    self.valueStack:invalidateLayout()

    local report = RealisticMechanicalSystems.getReferenceReport(vehicle)
    self.systemsLayout:setVisible(report ~= nil)
    self.systemsEmptyText:setVisible(report == nil)
    local footText = ""
    self.stateRows = {}
    if report ~= nil then
        self.stateRows, footText = RMS_Utils.getConditionRows(vehicle, report, report.conditionData.systems,
            RealisticMechanicalSystems.getIsCompleteReport(report), reading.isOutdated, self.openSystem)
    end
    self.footText:setText(footText)
    self.footRule:setVisible(footText ~= "")
    RMS_Utils.reloadListTemplates(self.stateList)

    self.lastCheckValue:setText(reading.ageText)
    self.lastCheckValue:setTextColor(unpack(reading.isOutdated and RMS_Breakdowns.COLORS.WARNING or RMS_Utils.COLOR.TEXT_DIM))
    RMS_Utils.fitValuePills(self)
end

---Draws the condition ring, greyed out with a report out of date
function RMS_ConditionCardFrame:onDrawRing()
    RMS_ProgressRing.renderInArea(self.ringArea, self.reading.conditionRatio, self.reading.isOutdated and RMS_Utils.COLOR.TEXT_DIM or nil)
end

---Number of rows of the condition list
function RMS_ConditionCardFrame:getNumberOfItemsInSection()
    return #self.stateRows
end

---Template of a row; an empty list still measures its first one
function RMS_ConditionCardFrame:getCellTypeForItemInSection(_list, _section, index)
    local row = self.stateRows[index]
    return row ~= nil and row.kind or "system"
end

---Fills a row of the condition list
function RMS_ConditionCardFrame:populateCellForItemInSection(_list, _section, index, cell)
    RMS_Utils.populateConditionCell(cell, self.stateRows[index])
end

---Unfolds a system on its parts, or folds it back
function RMS_ConditionCardFrame:onClickStateRow(_list, _section, index)
    local row = self.stateRows[index]
    if row.kind ~= "system" or not row.canOpen then
        return
    end
    self.openSystem = not row.isOpen and row.systemKey or nil
    self:refresh()
    for rowIndex, stateRow in ipairs(self.stateRows) do
        if stateRow.kind == "system" and stateRow.systemKey == row.systemKey then
            self.stateList:setSelectedItem(1, rowIndex, false, true)
        end
    end
end
