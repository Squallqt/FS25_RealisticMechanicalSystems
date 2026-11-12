-- Copyright © 2026 Squallqt. All rights reserved.

---Diagnostic page: known breakdowns, the ones picked and their estimate
RMS_WorkshopDiagnosticFrame = {}

local RMS_WorkshopDiagnosticFrame_mt = Class(RMS_WorkshopDiagnosticFrame, RMS_WorkshopPage)

-- quote list in reference pixels, as laid out in the XML
local QUOTE_WIDTH, QUOTE_HEIGHT = 316, 288
-- a fault row: its description, shortened beside its warranty
local ROW_WIDTH, DESCRIPTION_WIDTH, DESCRIPTION_COVERED = 683, 547, 390
-- the warranty that pays a fault, named on its row
local COVER_NAMES = { factory = "rms_ws_quote_cover_factory", part = "rms_ws_quote_cover_part", used = "rms_ws_quote_cover_used" }

local READING_ROWS = {
    { label = "rms_ws_label_condition", icon = "rms_workshopRowConditionIcon", text = "conditionText", color = "conditionColor" },
    { label = "rms_ws_label_service", icon = "rms_workshopRowMaintenanceIcon", text = "serviceText", color = "serviceColor" }
}

---Creates the page
function RMS_WorkshopDiagnosticFrame.new()
    local self = RMS_WorkshopPage.new(nil, RMS_WorkshopDiagnosticFrame_mt)
    self.breakdownIds = {}
    self.wornParts = {}
    self.quoteLines = {}
    return self
end

---Wires both lists
function RMS_WorkshopDiagnosticFrame:initialize(dialog)
    RMS_WorkshopDiagnosticFrame:superClass().initialize(self, dialog)
    for _, list in ipairs({ self.breakdownTable, self.diagnosticQuoteList }) do
        list:setDataSource(self)
        list:setDelegate(self)
    end
    self.lastCheckColor = { unpack(self.diagnosticLastInspection.textColor) }
    self.emptyHintColor = { unpack(self.breakdownEmptyHint.textColor) }
    RMS_Utils.fitIcon(self.breakdownEmptyIcon)
    self.readingRows = RMS_Utils.cloneTemplate(self.readingRowTemplate, #READING_ROWS)
    for index, entry in ipairs(READING_ROWS) do
        local icon = self.readingRows[index]:getDescendantByName("icon")
        icon:applyProfile(entry.icon)
        RMS_Utils.fitIcon(icon)
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
    self.wornParts = RMS_Utils.getInspectedWornParts(vehicle)
    RMS_Utils.reloadListTemplates(self.breakdownTable)
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

---Writes the quote of the picked faults, Standard with original parts
function RMS_WorkshopDiagnosticFrame:updateEstimate()
    local R, vehicle, workshopType = RealisticMechanicalSystems, self.vehicle, self.workshopType
    local REPAIR, OEM = R.REPAIR_TYPES.MEDIUM, R.PART_TYPES.OEM
    local invoice = RMS_FluidWorkshop.getTransactionInvoice(vehicle, R.STATUS.REPAIR, workshopType, REPAIR, OEM)
    local groups = RMS_FluidWorkshop.getQuoteGroups(vehicle, R.STATUS.REPAIR, REPAIR, OEM, invoice, workshopType)
    local height
    self.quoteLines, height = RMS_FluidWorkshop.getQuoteRows(groups)
    RMS_Utils.reloadListTemplates(self.diagnosticQuoteList)
    self.diagnosticQuoteList:setVisible(#self.quoteLines > 0)
    self.diagnosticQuoteSliderBox:setVisible(height > QUOTE_HEIGHT)
    self.diagnosticQuoteOptions:setText(RMS_Utils.formatServiceOption(vehicle, R.STATUS.REPAIR, REPAIR, workshopType) .. " · "
        .. g_i18n:getText(RMS_Utils.getSystemLabel(vehicle, OEM)))

    local price = RMS_FluidWorkshop.getTransactionPrice(vehicle, R.STATUS.REPAIR, workshopType, REPAIR, OEM)
    self.diagnosticTotal:setText(g_i18n:formatMoney(price, 0, true, false))
    self.diagnosticConfigureButton:setDisabled(#self.quoteLines == 0 or self.isUnderService)
end

---Rows of a list
function RMS_WorkshopDiagnosticFrame:getNumberOfItemsInSection(list)
    if list == self.diagnosticQuoteList then
        return #self.quoteLines
    end
    -- the worn parts follow the faults under their title
    return #self.breakdownIds + (#self.wornParts > 0 and #self.wornParts + 1 or 0)
end

---Template of a row: a fault, the worn parts or a quote row
function RMS_WorkshopDiagnosticFrame:getCellTypeForItemInSection(list, _section, index)
    if list == self.diagnosticQuoteList then
        return RMS_FluidWorkshop.getQuoteCellType(self.quoteLines[index])
    elseif index <= #self.breakdownIds then
        return "orderRowTemplate"
    end
    return index == #self.breakdownIds + 1 and "wornTitleTemplate" or "wornRowTemplate"
end

---Fills a row of a list
function RMS_WorkshopDiagnosticFrame:populateCellForItemInSection(list, _section, index, cell)
    if list == self.diagnosticQuoteList then
        RMS_FluidWorkshop.populateQuoteCell(cell, self.quoteLines[index], self.diagnosticQuoteList.size[1] / QUOTE_WIDTH, QUOTE_WIDTH)
        return
    elseif index > #self.breakdownIds then
        local worn = self.wornParts[index - #self.breakdownIds - 1]
        if worn ~= nil then
            -- a worn part is picked for its replacement as a fault is
            local isPicked = self.vehicle.spec_RealisticMechanicalSystems.preventiveParts[worn.partId] ~= nil
            local toggle = cell:getAttribute("wornSelect")
            RMS_Utils.mirrorSelectionToChildren(toggle, cell)
            toggle:setSelected(isPicked)
            cell:getAttribute("wornSurface").getIsSelected = function()
                return cell:getIsSelected()
            end
            cell:getAttribute("wornName"):setDisabled(not isPicked)
            cell:getAttribute("wornDetail"):setDisabled(not isPicked)
            local color = { RMS_Utils.getValueColorInverted(3, 1, 1, 2, 3, false) }
            cell:getAttribute("wornIcon"):setImageColor(nil, unpack(color))
            cell:getAttribute("wornName"):setText(worn.title)
            local risk = cell:getAttribute("wornRisk")
            risk:setText(worn.severity)
            risk:setTextColor(unpack(color))
            cell:getAttribute("wornDetail"):setText(worn.text)
        end
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
    local isCovered, reason = vehicle:isWarrantyRepairCovered(self.workshopType, id)
    local cover = cell:getAttribute("rms_tableBreakdownCover")
    cover:setVisible(isCovered and COVER_NAMES[reason] ~= nil)
    cover:setText(isCovered and COVER_NAMES[reason] ~= nil and g_i18n:getText(COVER_NAMES[reason]) or "")
    description:setSize(((isCovered and COVER_NAMES[reason] ~= nil) and DESCRIPTION_COVERED or DESCRIPTION_WIDTH)
        * self.breakdownTable.size[1] / ROW_WIDTH, nil)
    -- an unpicked row starts its description over
    description:setText(descriptionText, nil, nil, not isPicked)

    local toggle = cell:getAttribute("rms_tableBreakdownSelect")
    -- a light box on a dark row, a dark one on a highlighted row
    RMS_Utils.mirrorSelectionToChildren(toggle, cell)
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
    local worn = self.wornParts[index - #self.breakdownIds - 1]
    if index > #self.breakdownIds then
        if worn ~= nil then
            RealisticMechanicalSystems.togglePreventivePart(self.vehicle, worn.partId)
            self.dialog:refresh()
        end
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
