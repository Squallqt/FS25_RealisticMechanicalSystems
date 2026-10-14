-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---Work order of an inspection: three types, then the repair it may chain to
RMS_MaintenanceTwoOptionsDialog = {}
RMS_MaintenanceTwoOptionsDialog.INSTANCE = nil

local RMS_MaintenanceTwoOptionsDialog_mt = Class(RMS_MaintenanceTwoOptionsDialog, MessageDialog)
local modDirectory = g_currentModDirectory

-- the inspection types, in the order of their columns
local INSPECTION_TYPE_KEYS = { "VISUAL", "STANDARD", "COMPLETE" }
-- the look of a cell by what a type does: all of it, part of it, nothing
local CELL_KINDS = { [2] = "Done", [1] = "Light", [0] = "None" }

---Loads the dialog layout and stores the shared instance
function RMS_MaintenanceTwoOptionsDialog.register()
    local dialog = RMS_MaintenanceTwoOptionsDialog.new()
    g_gui:loadGui(modDirectory .. "gui/RMS_MaintenanceTwoOptionsDialog.xml", "RMS_MaintenanceTwoOptionsDialog", dialog)
    RMS_MaintenanceTwoOptionsDialog.INSTANCE = dialog
end

---Create instance of RMS_MaintenanceTwoOptionsDialog
-- @param table? target target
-- @param table? customMt custom metatable
-- @return table dialog instance of class RMS_MaintenanceTwoOptionsDialog
function RMS_MaintenanceTwoOptionsDialog.new(target, customMt)
    local dialog = MessageDialog.new(target, customMt or RMS_MaintenanceTwoOptionsDialog_mt)
    dialog.vehicle = nil
    dialog.maintenanceType = RealisticMechanicalSystems.STATUS.INSPECTION
    return dialog
end

---Returns a label without its trailing colon
local function stripTrailingColon(text)
    return (tostring(text or ""):gsub("%s*:%s*$", ""))
end

---Removes the legacy list marker from a description
local function stripLeadingMarker(text)
    return (tostring(text or ""):gsub("^%s*%*%s*", ""))
end

---Returns what an inspection type does on each row of its table
-- @param string inspectionType inspection type
-- @return table cells text and kind of each row, 2 for all of it, 1 for part of it, 0 for nothing
function RMS_MaintenanceTwoOptionsDialog.getInspectionCells(inspectionType)
    local rms = RealisticMechanicalSystems

    ---Writes the share of the faults of a kind an inspection finds
    local function share(value)
        if value <= 0 then
            return { "-", 0 }
        end
        return { string.format("%d%%", math.floor(value * 100 + 0.5)), value >= 1 and 2 or 1 }
    end

    local entry = { type = rms.STATUS.INSPECTION, optionOne = inspectionType }
    local hasReport = rms.getIsLogEntryHasReport(entry)
    local isMeasured = hasReport and rms.getIsCompleteReport(entry)
    local report = { "-", 0 }
    if isMeasured then
        report = { g_i18n:getText("rms_ws_inspection_measures"), 2 }
    elseif hasReport then
        report = { g_i18n:getText("rms_ws_inspection_ratings"), 1 }
    end

    return {
        share(rms.getInspectionDetectionShare(inspectionType, false)),
        share(rms.getInspectionDetectionShare(inspectionType, true)),
        share(rms.getInspectionFindsDormant(inspectionType) and rms.getInspectionDetectionShare(inspectionType, false) or 0),
        report,
        isMeasured and { g_i18n:getText("rms_ws_inspection_assessed"), 2 } or { "-", 0 }
    }
end

---Writes the inspection table, the chosen type selected
-- @param table dialog dialog instance
-- @param string workshopType workshop type
function RMS_MaintenanceTwoOptionsDialog.updateInspectionTable(dialog, workshopType)
    local vehicle = dialog.vehicle
    local inspection = RealisticMechanicalSystems.STATUS.INSPECTION
    local hours, isOutdated = vehicle:getInspectionReportAge()
    dialog.inspectionLastReport:setText(RMS_Utils.formatReportAge(hours))
    dialog.inspectionLastReport:setTextColor(unpack(isOutdated and RMS_Breakdowns.COLORS.WARNING or RMS_Utils.COLOR.TEXT))
    dialog.inspectionOutdated:setVisible(isOutdated)
    dialog.inspectionOutdated:setTextColor(unpack(RMS_Breakdowns.COLORS.WARNING))

    for column, button in ipairs(dialog.inspectionColumns) do
        local inspectionType = RealisticMechanicalSystems.INSPECTION_TYPES[INSPECTION_TYPE_KEYS[column]]
        local price = RMS_FluidWorkshop.getTransactionPrice(vehicle, inspection, workshopType, inspectionType, nil, false)
        local duration = vehicle:getServiceDuration(inspection, inspectionType, nil, false, workshopType)
        button:setSelected(inspectionType == dialog.selectedOptionOne)
        dialog.inspectionName[column]:setText(g_i18n:getText(inspectionType))
        dialog.inspectionPrice[column]:setText(price ~= nil and g_i18n:formatMoney(price, 0, true, false) or "-")
        dialog.inspectionDuration[column]:setText(RMS_Config.MAINTENANCE.INSTANT_INSPECTION
            and g_i18n:getText("rms_option_menu_duration_instant") or RMS_Utils.formatShortDuration(duration))

        for row, cell in ipairs(RMS_MaintenanceTwoOptionsDialog.getInspectionCells(inspectionType)) do
            for kind, suffix in pairs(CELL_KINDS) do
                local element = dialog["inspectionCell" .. suffix .. column][row]
                element:setVisible(kind == cell[2])
                element:setText(cell[1])
            end
        end
    end
end

---Opens the dialog on a vehicle, the standard inspection chosen
-- @param table vehicle vehicle
function RMS_MaintenanceTwoOptionsDialog.show(vehicle)
    if RMS_MaintenanceTwoOptionsDialog.INSTANCE == nil then RMS_MaintenanceTwoOptionsDialog.register() end
    if vehicle == nil or vehicle.spec_RealisticMechanicalSystems == nil then return end

    local dialog = RMS_MaintenanceTwoOptionsDialog.INSTANCE
    dialog.vehicle = vehicle
    dialog.resetConfigScroll = true
    dialog.selectedOptionOne = RealisticMechanicalSystems.INSPECTION_TYPES.STANDARD
    dialog.selectedOptionThree = false

    dialog:updateScreen()
    g_gui:showDialog("RMS_MaintenanceTwoOptionsDialog")
end

---Rebuilds the inspection table, the price rows and the follow-up
function RMS_MaintenanceTwoOptionsDialog:updateScreen()
    if self.vehicle == nil then return end

    local spec = self.vehicle.spec_RealisticMechanicalSystems
    local workshopType = RMS_WorkshopDialog.INSTANCE ~= nil and RMS_WorkshopDialog.INSTANCE.workshopType or spec.workshopType

    local balanceText = g_i18n:formatMoney(math.floor(g_currentMission:getMoney()), 2, true, false)
    self.balanceElement:setText(balanceText)
    RMS_Utils.updateMoneyBoxLayout(
        self.balanceTitleElement,
        self.balanceElement,
        self.moneyBox,
        self.moneyBoxBg,
        g_i18n:getText("ui_balance"),
        balanceText
    )
    -- the inspection is the first of the procedures
    for index, button in ipairs(self.configChoiceButtons) do
        button:setSelected(index == 1)
    end
    local isTopUpOffered = RMS_FluidWorkshop.getIsTopUpOffered(workshopType)
    self.configChoiceButtons[5]:setVisible(isTopUpOffered)
    self.configChoiceButtons[5].parent:invalidateLayout()
    self.shortcutButtons[5]:setVisible(isTopUpOffered)
    self.refillShortcutSeparator:setVisible(isTopUpOffered)
    self.shortcutButtons[5].parent:invalidateLayout()
    -- the bottom bar carries the workshop shortcuts
    for index, button in ipairs(self.shortcutButtons) do
        button:setDisabled(self.configChoiceButtons[index]:getIsDisabled())
    end

    RMS_MaintenanceTwoOptionsDialog.updateInspectionTable(self, workshopType)

    local inspection = RealisticMechanicalSystems.STATUS.INSPECTION
    local isAllowedInMobileWorkshop = RMS_FluidWorkshop.getMobileWorkshopAvailability(self.vehicle, inspection, workshopType,
        self.selectedOptionOne)
    local isWorkshopOpen = RMS_WorkshopDialog.getIsWorkshopOpen()

    -- price, duration, finish time
    local servicePrice = RMS_FluidWorkshop.getTransactionPrice(self.vehicle, inspection, workshopType, self.selectedOptionOne, nil, self.selectedOptionThree)
    local priceValue = servicePrice ~= nil
        and g_i18n:formatMoney(servicePrice, 0, true, false)
        or g_i18n:getText("rms_fluid_service_price_unavailable")
    local durationValue = RMS_Config.MAINTENANCE.INSTANT_INSPECTION and g_i18n:getText("rms_option_menu_duration_instant")
        or RMS_Utils.formatDuration(self.vehicle:getServiceDuration(inspection, self.selectedOptionOne, nil, self.selectedOptionThree, workshopType))
    local finishTime, daysToAdd = self.vehicle:getServiceFinishTime(inspection, self.selectedOptionOne, nil, self.selectedOptionThree, workshopType)

    self.recapType:setText(g_i18n:getText(inspection))
    self.recapOptions:setText(g_i18n:getText(self.selectedOptionOne))
    self.recapVehicle:setText(self.vehicle:getFullName())
    self.recapPriceLabel:setText(stripTrailingColon(g_i18n:getText("rms_option_menu_price_text")))
    self.recapPrice:setText(priceValue)
    self.recapDurationLabel:setText(stripTrailingColon(g_i18n:getText("rms_option_menu_duration_text")))
    self.recapDuration:setText(durationValue)
    self.recapFinishLabel:setText(stripTrailingColon(g_i18n:getText("rms_option_menu_finish_time_text")))
    self.recapFinish:setText(RMS_Utils.formatFinishTime(finishTime, daysToAdd))

    -- the refusal of the mobile workshop is written under the table
    self.optionOneDisclaimer:setVisible(not isAllowedInMobileWorkshop)
    if not isAllowedInMobileWorkshop then
        self.optionOneDisclaimer:setText(RMS_FluidWorkshop.getMobileWorkshopRestrictionText(
            self.vehicle, inspection, workshopType, self.selectedOptionOne))
        self.optionOneDisclaimer:setTextColor(unpack(RMS_Utils.COLOR.ALERT))
    end

    -- the repair the inspection may chain to
    local optionThreeText = g_i18n:getText("rms_option_menu_perform_repair")
    local optionThreeDisclaimerText = g_i18n:getText("rms_option_menu_option_three_disclaimer_repair_after_detection")
    if self.selectedOptionThree then
        optionThreeDisclaimerText = optionThreeDisclaimerText .. " " .. g_i18n:getText("rms_option_menu_follow_up_separate_transaction")
    end
    self.optionThreeText:setText(optionThreeText)
    self.optionThreeDisclaimer:setText(stripLeadingMarker(optionThreeDisclaimerText))
    self.recapAddonLabel:setText(optionThreeText)
    self.recapAddon:setText(g_i18n:getText(self.selectedOptionThree and BinaryOptionElement.STRING_YES or BinaryOptionElement.STRING_NO))
    RMS_WorkshopDialog.updateFollowUpCards(self)

    self.startServiceButton:setDisabled(not isAllowedInMobileWorkshop or not isWorkshopOpen)

    local workshopTypeKey = RMS_Utils.getKeyByValue(RealisticMechanicalSystems.WORKSHOP, workshopType)
    local workshopTypeText = workshopTypeKey ~= nil and g_i18n:getText(workshopType) or ""
    local availabilityText = g_i18n:getText(isWorkshopOpen and "rms_ws_status_open" or "rms_ws_status_closed")
    if workshopTypeText ~= "" then
        availabilityText = availabilityText .. " · " .. workshopTypeText
    end

    self.configStatusText:setText(availabilityText)
    RMS_WorkshopDialog.refreshOrderScroll(self)
    self:updateFocusLinks()
end

---Chains the focus over the order being configured
function RMS_MaintenanceTwoOptionsDialog:updateFocusLinks()
    local procedures = {}
    for _, button in ipairs(self.configChoiceButtons) do
        table.insert(procedures, {button})
    end

    local preferred = self.inspectionColumns[RMS_Utils.getKeyByValue(INSPECTION_TYPE_KEYS,
        RMS_Utils.getKeyByValue(RealisticMechanicalSystems.INSPECTION_TYPES, self.selectedOptionOne))]
    local columns = {procedures, {self.inspectionColumns, self.optionThreeButtons}, {{self.startServiceButton}}}
    self.focusEntry = RMS_Utils.linkFocusColumns(self.workshopTabPaging, columns, preferred)
    RMS_Utils.keepFocusShown(self.focusEntry)
end

---Chooses the inspection type of a column
-- @param integer index column index
function RMS_MaintenanceTwoOptionsDialog:selectInspection(index)
    self.selectedOptionOne = RealisticMechanicalSystems.INSPECTION_TYPES[INSPECTION_TYPE_KEYS[index]]
    self:updateScreen()
end

---
function RMS_MaintenanceTwoOptionsDialog:onClickInspection1()
    self:selectInspection(1)
end

---
function RMS_MaintenanceTwoOptionsDialog:onClickInspection2()
    self:selectInspection(2)
end

---
function RMS_MaintenanceTwoOptionsDialog:onClickInspection3()
    self:selectInspection(3)
end

---
function RMS_MaintenanceTwoOptionsDialog:onClickConfigureInspection()
    RMS_WorkshopDialog.selectInterventionFromConfiguration(self, RealisticMechanicalSystems.STATUS.INSPECTION)
end

---
function RMS_MaintenanceTwoOptionsDialog:onClickConfigureMaintenance()
    RMS_WorkshopDialog.selectInterventionFromConfiguration(self, RealisticMechanicalSystems.STATUS.MAINTENANCE)
end

---
function RMS_MaintenanceTwoOptionsDialog:onClickConfigureRepair()
    RMS_WorkshopDialog.selectInterventionFromConfiguration(self, RealisticMechanicalSystems.STATUS.REPAIR)
end

---
function RMS_MaintenanceTwoOptionsDialog:onClickConfigureOverhaul()
    RMS_WorkshopDialog.selectInterventionFromConfiguration(self, RealisticMechanicalSystems.STATUS.OVERHAUL)
end

---
function RMS_MaintenanceTwoOptionsDialog:onClickConfigureRefill()
    RMS_WorkshopDialog.selectInterventionFromConfiguration(self, RealisticMechanicalSystems.STATUS.REFILL)
end

---
function RMS_MaintenanceTwoOptionsDialog:onClickConfigureBodywork()
    RMS_WorkshopDialog.selectInterventionFromConfiguration(self, RealisticMechanicalSystems.STATUS.BODYWORK)
end

---
function RMS_MaintenanceTwoOptionsDialog:onClickSummaryTab()
    RMS_WorkshopDialog.selectTabFromChildDialog(self, RMS_WorkshopDialog.TAB.SUMMARY)
end

---
function RMS_MaintenanceTwoOptionsDialog:onClickDiagnosticTab()
    RMS_WorkshopDialog.selectTabFromChildDialog(self, RMS_WorkshopDialog.TAB.DIAGNOSTIC)
end

---
function RMS_MaintenanceTwoOptionsDialog:onClickInterventionsTab()
    RMS_WorkshopDialog.selectTabFromChildDialog(self, RMS_WorkshopDialog.TAB.INTERVENTIONS)
end

---
function RMS_MaintenanceTwoOptionsDialog:onClickTechnicalTab()
    RMS_WorkshopDialog.selectTabFromChildDialog(self, RMS_WorkshopDialog.TAB.TECHNICAL)
end

---
function RMS_MaintenanceTwoOptionsDialog:onWorkshopTabPagingChanged()
    RMS_WorkshopDialog.onChildTabPagingChanged(self)
end

---Draws the native maintenance glyph in the intervention action list
-- @param table area transparent GUI element receiving the XML draw callback
function RMS_MaintenanceTwoOptionsDialog:onDrawMaintenanceActionIcon(area)
    RMS_WorkshopDialog.drawMaintenanceIcon(area, "rms_workshopMaintenanceActionIcon")
end

---Draws the RMS oil-level glyph in the intervention action list
-- @param table area transparent GUI element receiving the XML draw callback
function RMS_MaintenanceTwoOptionsDialog:onDrawOilActionIcon(area)
    RMS_WorkshopDialog.drawOilIcon(area, "rms_workshopOilActionIcon")
end

---
function RMS_MaintenanceTwoOptionsDialog:onClickOptionThreeNo()
    self.selectedOptionThree = false
    self:updateScreen()
end

---
function RMS_MaintenanceTwoOptionsDialog:onClickOptionThreeYes()
    self.selectedOptionThree = true
    self:updateScreen()
end

---Starts the service on the server, or asks it from a client
function RMS_MaintenanceTwoOptionsDialog:onClickStartService()
    local vehicle = self.vehicle
    local workshopType = RMS_WorkshopDialog.INSTANCE.workshopType
    local inspection = RealisticMechanicalSystems.STATUS.INSPECTION
    if not RMS_FluidWorkshop.getMobileWorkshopAvailability(vehicle, inspection, workshopType, self.selectedOptionOne)
        or not RMS_WorkshopDialog.getIsWorkshopOpen() then
        return
    end

    local price = RMS_FluidWorkshop.getTransactionPrice(vehicle, inspection, workshopType, self.selectedOptionOne, nil, self.selectedOptionThree)
    if price == nil then
        RMS_FluidWorkshop.showResult(RMS_FluidWorkshop.RESULT.PRICE_UNAVAILABLE)
        return
    end

    if g_currentMission:getMoney() < price then
        InfoDialog.show(g_i18n:getText("shop_messageNotEnoughMoneyToBuy"))
        return
    end

    if g_server ~= nil then
        local started, result = RMS_FluidWorkshop.tryStartService(
            vehicle,
            g_workshopScreen.sellingPoint,
            inspection,
            workshopType,
            self.selectedOptionOne,
            nil,
            self.selectedOptionThree
        )
        if not started then
            RMS_FluidWorkshop.showResult(result)
            return
        end
        RMS_VehicleChangeStatusEvent.send(vehicle)
    else
        RMS_ServiceRequestEvent.send(vehicle, inspection, workshopType, self.selectedOptionOne, nil, self.selectedOptionThree)
    end

    self:close()
end

---Closes the dialog
function RMS_MaintenanceTwoOptionsDialog:onClickBack()
    self:close()
end



---Selects the interventions tab and binds the button backgrounds
function RMS_MaintenanceTwoOptionsDialog:onCreate()
    RMS_Utils.mirrorSelectionToChildren(self.workshopNavTabs[3])
    self.workshopNavTabs[3]:setSelected(true)

    -- a column of the table draws its frame, fill, name and cells as chosen
    for _, buttons in ipairs({self.configChoiceButtons, self.inspectionColumns, self.optionThreeButtons}) do
        for _, button in ipairs(buttons) do
            RMS_Utils.mirrorSelectionToChildren(button)
        end
    end

    RMS_Utils.applyScrollSpeed(self.dialogElement)
end

---
function RMS_MaintenanceTwoOptionsDialog:onOpen()
    RMS_MaintenanceTwoOptionsDialog:superClass().onOpen(self)
    RMS_WorkshopDialog.initializeChildTabPaging(self, RMS_WorkshopDialog.TAB.INTERVENTIONS)

    RMS_WorkshopDialog.refreshOrderScroll(self)

    for _, button in ipairs(self.configChoiceButtons) do
        RMS_Utils.centerActionContent(button)
    end

    RMS_Utils.resetScrollingTexts(self.dialogElement)
    g_messageCenter:subscribe(MessageType.MONEY_CHANGED, self.updateScreen, self)

    self:updateFocusLinks()
    FocusManager:setFocus(self.focusEntry)
end

---
function RMS_MaintenanceTwoOptionsDialog:onClose()
    self.vehicle = nil
    g_messageCenter:unsubscribeAll(self)

    RMS_MaintenanceTwoOptionsDialog:superClass().onClose(self)
end
