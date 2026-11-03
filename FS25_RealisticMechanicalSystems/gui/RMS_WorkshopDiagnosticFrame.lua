-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---Diagnostic page: known breakdowns, the ones picked and their estimate
RMS_WorkshopDiagnosticFrame = {}

local RMS_WorkshopDiagnosticFrame_mt = Class(RMS_WorkshopDiagnosticFrame, RMS_WorkshopPage)

local MAX_LISTED_PARTS = 16

local READING_ROWS = {
    { label = "rms_ws_label_condition", icon = "rms_workshopRowConditionIcon", text = "conditionText", color = "conditionColor" },
    { label = "rms_ws_label_service", icon = "rms_workshopRowMaintenanceIcon", text = "serviceText", color = "serviceColor" }
}

---Creates the page
function RMS_WorkshopDiagnosticFrame.new()
    local self = RMS_WorkshopPage.new(nil, RMS_WorkshopDiagnosticFrame_mt)
    self.breakdownIds = {}
    self.estimateParts = {}
    return self
end

---Wires both lists
function RMS_WorkshopDiagnosticFrame:initialize(dialog)
    RMS_WorkshopDiagnosticFrame:superClass().initialize(self, dialog)
    for _, list in ipairs({ self.breakdownTable, self.diagnosticSelectedPartsTable }) do
        list:setDataSource(self)
        list:setDelegate(self)
    end
    self.lastCheckColor = { unpack(self.diagnosticLastInspection.textColor) }
    self.emptyHintColor = { unpack(self.breakdownEmptyHint.textColor) }
    self.readingRows = RMS_Utils.cloneTemplate(self.readingRowTemplate, #READING_ROWS)
    for index, entry in ipairs(READING_ROWS) do
        self.readingRows[index]:getDescendantByName("icon"):applyProfile(entry.icon)
    end
end

---Writes the reading, the breakdowns and the estimate
function RMS_WorkshopDiagnosticFrame:refresh(state)
    local vehicle = self.vehicle
    self.isUnderService = state.isUnderService
    self.statusBar:setStatus(state)
    RMS_Utils.setVehicleIdentity(vehicle, self.diagnosticVehicleImage, self.diagnosticVehicleBrand, self.diagnosticVehicleName)

    local reading = RMS_Utils.getInspectionReading(vehicle)
    self.diagnosticLastInspection:setText(reading.ageText)
    self.diagnosticLastInspection:setTextColor(unpack(reading.isOutdated and RMS_Breakdowns.COLORS.WARNING or self.lastCheckColor))
    for index, entry in ipairs(READING_ROWS) do
        local row = self.readingRows[index]
        RMS_Utils.writeRow(row, g_i18n:getText(entry.label), reading[entry.text])
        row:getDescendantByName("value"):setTextColor(unpack(reading[entry.color]))
    end

    self.breakdownIds = RMS_Utils.getVisibleBreakdownIds(vehicle)
    self.breakdownTable:reloadData()
    local isEmpty = #self.breakdownIds == 0
    local isWarning = RealisticMechanicalSystems.getHasUnidentifiedWarning(vehicle)
    self.breakdownTable:setVisible(not isEmpty)
    self.breakdownInfoRow:setVisible(not isEmpty)
    self.breakdownEmptyPanel:setVisible(isEmpty)
    self.breakdownEmptyTitle:setText(g_i18n:getText(isWarning and "rms_ws_faults_warning_title" or "rms_ws_faults_none_title"))
    self.breakdownEmptyHint:setText(g_i18n:getText(isWarning and "rms_ws_faults_warning_hint" or "rms_ws_faults_none_hint"))
    self.breakdownEmptyHint:setTextColor(unpack(isWarning and RMS_Breakdowns.COLORS.WARNING or self.emptyHintColor))

    self:updateEstimate()
    RMS_Utils.fitValuePills(self)
end

---Lists the parts picked for repair and their price
function RMS_WorkshopDiagnosticFrame:updateEstimate()
    local breakdowns = self.vehicle:getActiveBreakdowns()
    local parts = {}
    for _, id in ipairs(self.breakdownIds) do
        if breakdowns[id].isSelectedForRepair then
            table.insert(parts, RMS_Utils.getBreakdownPartName(id, self.vehicle))
        end
    end
    local pickedCount = #parts
    if pickedCount > MAX_LISTED_PARTS then
        for _ = MAX_LISTED_PARTS, pickedCount do
            table.remove(parts)
        end
        table.insert(parts, string.format(g_i18n:getText("rms_ws_label_more_parts"), pickedCount - (MAX_LISTED_PARTS - 1)))
    end
    self.estimateParts = parts
    self.diagnosticSelectedPartsTable:reloadData()
    self.diagnosticSelectedPartsTable:setVisible(pickedCount > 0)

    local STATUS = RealisticMechanicalSystems.STATUS
    local price = RMS_FluidWorkshop.getTransactionPrice(self.vehicle, STATUS.REPAIR, self.workshopType, RealisticMechanicalSystems.REPAIR_TYPES.MEDIUM,
        RealisticMechanicalSystems.PART_TYPES.OEM, false)
    self.diagnosticTotal:setText(g_i18n:formatMoney(price, 0, true, false))
    self.diagnosticConfigureButton:setDisabled(pickedCount == 0 or self.isUnderService)
end

---Rows of a list
function RMS_WorkshopDiagnosticFrame:getNumberOfItemsInSection(list)
    return list == self.breakdownTable and #self.breakdownIds or #self.estimateParts
end

---Fills a row of a list
function RMS_WorkshopDiagnosticFrame:populateCellForItemInSection(list, _section, index, cell)
    if list == self.diagnosticSelectedPartsTable then
        cell:getAttribute("diagnosticEstimatePart"):setText(self.estimateParts[index])
        return
    end

    local vehicle, id = self.vehicle, self.breakdownIds[index]
    local breakdown = vehicle:getActiveBreakdowns()[id]
    local stageText, descriptionText = RMS_Utils.getBreakdownTexts(vehicle, id, breakdown)
    local price = vehicle:getBreakdownRepairPrice(id, breakdown.stage, RealisticMechanicalSystems.PART_TYPES.OEM, self.workshopType)
    local isPicked = breakdown.isSelectedForRepair

    RMS_Utils.applyScrollSpeed(cell)
    local stage = cell:getAttribute("rms_tableBreakdownStage")
    stage:setText(stageText)
    stage:setTextColor(unpack(RMS_Utils.COLOR.STAGE[breakdown.stage] or RMS_Utils.COLOR.STAGE[4]))
    cell:getAttribute("rms_tableBreakdownName"):setText(RMS_Utils.getBreakdownPartName(id, vehicle))
    cell:getAttribute("rms_tableBreakdownPrice"):setText(g_i18n:formatMoney(price, 0, true, false))
    local description = cell:getAttribute("rms_tableBreakdownDisc")
    -- an unpicked row starts its description over
    description:setText(descriptionText, nil, nil, not isPicked)

    local toggle = cell:getAttribute("rms_tableBreakdownSelect")
    RMS_Utils.mirrorSelectionToChildren(toggle)
    toggle:setSelected(isPicked)
    cell:getAttribute("surface").getIsSelected = function()
        return cell:getIsSelected()
    end
    for _, name in ipairs({ "rms_tableBreakdownName", "rms_tableBreakdownSeparator", "rms_tableBreakdownStage", "rms_tableBreakdownPrice" }) do
        cell:getAttribute(name):setDisabled(not isPicked)
    end
    description:setDisabled(not isPicked)
end

---Picks a breakdown for repair, or puts it back
function RMS_WorkshopDiagnosticFrame:onBreakdownClick(_list, _section, index)
    if self.isUnderService then
        return
    end
    local breakdown = self.vehicle:getActiveBreakdowns()[self.breakdownIds[index]]
    breakdown.isSelectedForRepair = not breakdown.isSelectedForRepair
    self.dialog:refresh()
end

---Opens the repair of the picked breakdowns
function RMS_WorkshopDiagnosticFrame:onClickRepair()
    self.dialog:selectService(RealisticMechanicalSystems.STATUS.REPAIR)
end

---The breakdown list, then the estimate button
function RMS_WorkshopDiagnosticFrame:getFocusColumns()
    return { { { self.breakdownTable } }, { { self.diagnosticConfigureButton } } }
end
