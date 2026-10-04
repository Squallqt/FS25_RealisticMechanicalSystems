-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---Workshop dialog showing the vehicle condition, its breakdowns and the available services
RMS_WorkshopDialog = {}
RMS_WorkshopDialog.INSTANCE = nil

local RMS_WorkshopDialog_mt = Class(RMS_WorkshopDialog, MessageDialog)

RMS_WorkshopDialog.TAB = {
    SUMMARY = 1,
    DIAGNOSTIC = 2,
    INTERVENTIONS = 3,
    TECHNICAL = 4
}

-- order of the action buttons of the interventions tab, as the XML lists them
RMS_WorkshopDialog.INTERVENTION_ACTION = {
    INSPECTION = 1,
    MAINTENANCE = 2,
    REPAIR = 3,
    OVERHAUL = 4,
    REFILL = 5,
    BODYWORK = 6
}
local modDirectory = g_currentModDirectory

local log_dbg = RMS_Utils.createLogger("[RMS_WORKSHOP_DIALOG]")

local FLUID_FIELDS = {
    {circuit = "engineOil", row = "engineOilRow", value = "engineOilValue", gauge = "engineOilGauge"},
    {circuit = "coolant", row = "coolantRow", value = "coolantValue", gauge = "coolantGauge"},
    {circuit = "transmissionOil", row = "transmissionOilRow", value = "transmissionOilValue", gauge = "transmissionOilGauge"},
    {circuit = "hydraulicFluid", row = "hydraulicFluidRow", value = "hydraulicFluidValue", gauge = "hydraulicFluidGauge"}
}

---Clamps a value to the range used by progress indicators
-- @param any value source value
-- @return float ratio clamped ratio
local function clampRatio(value)
    local clamped = math.max(0, math.min(tonumber(value) or 0, 1))
    return math.floor(clamped * 100 + 0.5) / 100
end

---Returns a label without its trailing colon for recap cards
-- @param string? value localized label
-- @return string label without a trailing colon
local function stripTrailingColon(value)
    return (tostring(value or ""):gsub("%s*:%s*$", ""))
end

---Updates the bodywork service buttons from the available modes
-- @param table dialog workshop dialog instance
-- @param string selectedMode selected bodywork mode
-- @param boolean isDealer whether the dealer service is selected
local function updateBodyworkServiceButtons(dialog, selectedMode, isDealer)
    local buttons = dialog.bodyworkServiceButtons or {}
    local values = {RMS_Bodywork.TOUCHUP}
    if isDealer then
        table.insert(values, RMS_Bodywork.FULL)
    end

    local labels = {}
    for _, value in ipairs(values) do
        table.insert(labels, g_i18n:getText(value))
    end

    local visibleCount = math.min(#buttons, #values)
    local layout = buttons[1] ~= nil and buttons[1].parent or nil
    if visibleCount > 0 and layout ~= nil and layout.size ~= nil then
        local spacing = layout.elementSpacing or 0
        local segmentWidth = (layout.size[1] - spacing * (visibleCount - 1)) / visibleCount
        for index = 1, visibleCount do
            buttons[index]:setSize(segmentWidth, nil)
        end
    end

    for index, button in ipairs(buttons) do
        local value = values[index]
        local isVisible = value ~= nil and index <= visibleCount
        button:setVisible(isVisible)
        button:setText(isVisible and labels[index] or "")
        button:setSelected(isVisible and value == selectedMode)
    end

    if layout ~= nil and layout.invalidateLayout ~= nil then
        layout:invalidateLayout()
    end
end

---Tells whether a log entry belongs in the technical record
-- @param table? entry maintenance log entry
-- @return boolean isVisible true when the entry is visible
local function isLogEntryVisible(entry)
    if entry == nil then
        return false
    end

    return RMS_Utils.normalizeBoolValue(entry.isVisible, true)
end

---Formats a stored service date with the period formatter
-- @param table? entry maintenance log entry
-- @return string text formatted date
local function formatLogDate(entry)
    local date = entry ~= nil and entry.date or nil
    if date == nil then
        return "-"
    end

    local day = tonumber(date.day) or 1
    local month = tonumber(date.month) or 1
    local year = tonumber(date.year) or 0
    return string.format("%d %s %d", day, g_i18n:formatPeriod(month, true), year)
end

---Returns the newest maintenance log entry that carries an inspection report
-- @param table vehicle vehicle
-- @return table? entry log entry holding the report
local function getLastReportEntry(vehicle)
    local log = vehicle.spec_RealisticMechanicalSystems.maintenanceLog or {}
    for index = #log, 1, -1 do
        if RealisticMechanicalSystems.getIsLogEntryHasReport(log[index]) then
            return log[index]
        end
    end

    return nil
end

---Returns the localized name of a service state
-- @param string? serviceType service state
-- @return string text localized state name
local function getServiceTypeText(serviceType)
    if serviceType == nil then
        return "-"
    end

    return g_i18n:getText(serviceType)
end

---Counts the repaired breakdowns stored in completed repair and overhaul entries
-- @param table logEntries maintenance log entries
-- @return integer count repaired breakdown count
local function getResolvedBreakdownsCount(logEntries)
    local count = 0
    local STATUS = RealisticMechanicalSystems.STATUS

    for _, entry in ipairs(logEntries or {}) do
        if entry ~= nil and entry.isCompleted ~= false and (entry.type == STATUS.REPAIR or entry.type == STATUS.OVERHAUL) then
            local selectedBreakdowns = entry.conditionData ~= nil and entry.conditionData.selectedBreakdowns or nil
            for _, breakdownId in ipairs(selectedBreakdowns or {}) do
                if breakdownId ~= "GENERAL_WEAR" then
                    count = count + 1
                end
            end
        end
    end

    return count
end

-- currency glyphs of the menu atlas, one per money unit the game offers
local CURRENCY_SLICES = {
    [GS_MONEY_EURO] = "ui_elements.currency_euro",
    [GS_MONEY_DOLLAR] = "ui_elements.currency_dollar",
    [GS_MONEY_POUND] = "ui_elements.currency_pound"
}
-- rows the quote can print before it has to summarise the rest
local MAX_LISTED_PARTS = 16

local currencyOverlays = {}
local MAINTENANCE_ICON_SLICE_ID = "rms_DashboardHud.maintainability"
local OIL_ICON_SLICE_ID = "rms_WorkshopFluids.engineOil"
local workshopIconOverlays = {}
local IMAGE_COLOR_ATTRIBUTES = {
    [GuiOverlay.STATE_DISABLED] = "imageDisabledColor",
    [GuiOverlay.STATE_FOCUSED] = "imageFocusedColor",
    [GuiOverlay.STATE_SELECTED] = "imageSelectedColor",
    [GuiOverlay.STATE_HIGHLIGHTED] = "imageHighlightedColor",
    [GuiOverlay.STATE_PRESSED] = "imagePressedColor"
}

---Draws the currency glyph of the money unit the player set, over an element
-- @param table area element the glyph fills
function RMS_WorkshopDialog.drawCurrencyIcon(area)
    local unit = g_gameSettings:getValue("moneyUnit")
    if CURRENCY_SLICES[unit] == nil then
        unit = GS_MONEY_DOLLAR
    end

    local overlay = currencyOverlays[unit]
    if overlay == nil then
        overlay = g_overlayManager:createOverlay(CURRENCY_SLICES[unit], 0, 0, 0, 0)
        currencyOverlays[unit] = overlay
    end

    local green = HUD.COLOR.ACTIVE
    local height = area.absSize[2]
    local width = height * (g_screenHeight / g_screenWidth)

    overlay:setDimension(width, height)
    overlay:setPosition(area.absPosition[1], area.absPosition[2])
    overlay:setColor(green[1], green[2], green[3], green[4])
    overlay:render()
end

---Draws a verified atlas glyph without passing through a Bitmap overlay
-- @param table? area transparent GUI element defining the render bounds and state
-- @param string sliceId registered overlay slice id
-- @param string profileName profile providing the native RMS state colors
local function drawWorkshopIcon(area, sliceId, profileName)
    if area == nil or g_overlayManager == nil then
        return
    end

    local overlay = workshopIconOverlays[sliceId]
    if overlay == nil then
        overlay = g_overlayManager:createOverlay(sliceId, 0, 0, 0, 0)
        workshopIconOverlays[sliceId] = overlay
    end

    if overlay == nil then
        return
    end

    local profile = g_gui:getProfile(profileName)
    local colorAttribute = IMAGE_COLOR_ATTRIBUTES[area:getOverlayState()]
    local colorValue = colorAttribute ~= nil and profile:getValue(colorAttribute) or nil
    local color = GuiUtils.getColorGradientArray(colorValue)
        or GuiUtils.getColorGradientArray(profile:getValue("imageColor"), HUD.COLOR.ACTIVE)

    overlay:setPosition(area.absPosition[1], area.absPosition[2])
    overlay:setDimension(area.absSize[1], area.absSize[2])
    overlay:setColor(color[1], color[2], color[3], color[4])
    overlay:render()
end

---Draws the verified RMS maintenance glyph
-- @param table? area transparent GUI element defining the render bounds and state
-- @param string profileName profile providing the native RMS state colors
function RMS_WorkshopDialog.drawMaintenanceIcon(area, profileName)
    drawWorkshopIcon(area, MAINTENANCE_ICON_SLICE_ID, profileName)
end

---Draws the RMS engine-oil glyph from the registered workshop fluid atlas
-- @param table? area transparent GUI element defining the render bounds and state
-- @param string profileName profile providing the native RMS state colors
function RMS_WorkshopDialog.drawOilIcon(area, profileName)
    drawWorkshopIcon(area, OIL_ICON_SLICE_ID, profileName)
end

---Draws an RMS progress ring centered inside a GUI area
-- @param table? area GUI draw area
-- @param float ratio progress ratio
local function drawProgressRing(area, ratio)
    if area == nil then
        return
    end

    local ringHeight = area.absSize[2]
    local ringWidth = ringHeight * (g_screenHeight / g_screenWidth)
    local centerX = area.absPosition[1] + area.absSize[1] * 0.5
    local centerY = area.absPosition[2] + area.absSize[2] * 0.5
    RMS_ProgressRing.render(centerX, centerY, ringWidth, ringHeight, clampRatio(ratio), false, RMS_ProgressRing.THIN_DOT)
end


---Loads the dialog layout and stores the shared instance
function RMS_WorkshopDialog.register()
    local dialog = RMS_WorkshopDialog.new()
    g_gui:loadGui(modDirectory .. "gui/RMS_WorkshopDialog.xml", "RMS_WorkshopDialog", dialog)
    RMS_WorkshopDialog.INSTANCE = dialog
end

---Create instance of RMS_WorkshopDialog
-- @param table? target target
-- @param table? customMt custom metatable
-- @return table dialog instance of class RMS_WorkshopDialog
function RMS_WorkshopDialog.new(target, customMt)
    local dialog = MessageDialog.new(target, customMt or RMS_WorkshopDialog_mt)
    dialog.vehicle = nil
    dialog.isDialogOpen = false
    dialog.lastObservedStatus = nil
    dialog.currentTab = RMS_WorkshopDialog.TAB.SUMMARY
    dialog.conditionRingRatio = 0
    dialog.serviceRingRatio = 0
    dialog.diagnosticEstimateParts = {}
    dialog.technicalReportBreakdownItems = {}
    dialog.technicalReportRecommendationItems = {}
    dialog.technicalLogData = {}
    dialog.selectedTechnicalLogIndex = nil
    dialog.fluidGaugeWidths = {}
    dialog.systemGaugeWidths = {}
    return dialog
end


---Opens the dialog on a vehicle, taking the workshop type from the vanilla workshop screen
-- @param table vehicle vehicle
function RMS_WorkshopDialog.show(vehicle, selectBodywork)
    if RMS_WorkshopDialog.INSTANCE == nil then RMS_WorkshopDialog.register() end
    if vehicle == nil or vehicle.spec_RealisticMechanicalSystems == nil then
        log_dbg("Tried to show RMS_WorkshopDialog without a valid vehicle.")
        return
    end
    local dialog = RMS_WorkshopDialog.INSTANCE
    if dialog == nil then
        log_dbg("Tried to show RMS_WorkshopDialog, but the dialog is unavailable.")
        return
    end
    dialog.vehicle = vehicle
    dialog.activeBreakdowns = vehicle:getActiveBreakdowns()
    dialog.visibleBreakdowns = {}
    dialog.breakdownRegistry = RMS_Breakdowns.BreakdownRegistry
    dialog.workshopType = RealisticMechanicalSystems.WORKSHOP.DEALER
    dialog.lastObservedStatus = vehicle:getCurrentStatus()
    dialog.currentTab = selectBodywork and RMS_WorkshopDialog.TAB.INTERVENTIONS or RMS_WorkshopDialog.TAB.SUMMARY
    dialog.bodyworkSelected = selectBodywork == true
    dialog.bodyworkSelectedColors = {}
    dialog.selectedTechnicalLogIndex = nil

    if g_workshopScreen.isOwnWorkshop then  dialog.workshopType = RealisticMechanicalSystems.WORKSHOP.OWN end
    if g_workshopScreen.isMobileWorkshop then  dialog.workshopType = RealisticMechanicalSystems.WORKSHOP.MOBILE end
    local wear = RMS_Bodywork.getWear(vehicle)
    dialog.bodyworkSelectedMode = (dialog.workshopType == RealisticMechanicalSystems.WORKSHOP.OWN
        or (wear ~= nil and wear >= RMS_Bodywork.MIN_TOUCHUP_WEAR
            and wear <= RMS_Bodywork.MAX_TOUCHUP_WEAR))
        and RMS_Bodywork.TOUCHUP or RMS_Bodywork.FULL

    if dialog ~= nil and dialog.setCurrentTab ~= nil then
        dialog:setCurrentTab(dialog.currentTab)
    end
    if dialog ~= nil and dialog.updateScreen ~= nil then
        dialog:updateScreen()
    end
    g_gui:showDialog("RMS_WorkshopDialog")
end

---Rebuilds the info panel, the breakdown table, the status line and the action buttons
function RMS_WorkshopDialog:updateScreen()
    if self.vehicle == nil then return end
    local spec = self.vehicle.spec_RealisticMechanicalSystems
    local vehicle = self.vehicle
    local STATUS = RealisticMechanicalSystems.STATUS
    self.activeBreakdowns = vehicle:getActiveBreakdowns()
    self.lastObservedStatus = self.vehicle:getCurrentStatus()

    -- vehicle info panel
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
    self.vehicleImage:setImageFilename(vehicle:getImageFilename())
    local brand = g_brandManager:getBrandByIndex(vehicle:getBrand())
    local brandText = brand.name ~= "NONE" and brand.title or ""
    local modelText = vehicle:getName()
    self.vehicleBrandValue:setText(brandText)
    self.vehicleNameValue:setText(modelText)
    self.diagnosticVehicleImage:setImageFilename(vehicle:getImageFilename())
    self.diagnosticVehicleBrand:setText(brandText)
    self.diagnosticVehicleName:setText(modelText)
    self.technicalVehicleImage:setImageFilename(vehicle:getImageFilename())
    self.technicalVehicleName:setText(vehicle:getFullName())
    local storeItem = g_storeManager:getItemByXMLFilename(vehicle.configFileName)
    local isDirectSell = self.workshopType == RealisticMechanicalSystems.WORKSHOP.DEALER
    local resaleValue = RMS_Utils.getResaleValue(vehicle, isDirectSell)
    self.lastResaleValue = resaleValue
    local valueLabel = g_i18n:getText("rms_ws_label_value")
    if isDirectSell and resaleValue ~= nil then
        local bonusPercent = math.floor((EconomyManager.DIRECT_SELL_MULTIPLIER - 1) * 100 + 0.5)
        valueLabel = string.format("%s (+%d%%)", valueLabel, bonusPercent)
    end
    self.valueLabel:setText(valueLabel)
    local currentValue = resaleValue ~= nil and g_i18n:formatMoney(resaleValue, 0, true, false) or nil
    local newPrice = nil
    if storeItem ~= nil then
        newPrice = StoreItemUtil.getDefaultPrice(storeItem, vehicle.configurations)
        if newPrice == nil or newPrice <= 0 then
            newPrice = storeItem.price
        end
    end
    local newPriceText = newPrice ~= nil and newPrice > 0 and g_i18n:formatMoney(newPrice, 0, true, false) or nil
    if currentValue ~= nil and newPriceText ~= nil then
        self.valueValue:setText(string.format("%s / %s", currentValue, newPriceText))
    else
        self.valueValue:setText(currentValue or newPriceText or "-")
    end
    
    self.ageValue:setText(string.format("%d %s", vehicle.age, g_i18n:getText("rms_ws_age_unit")))
    self.operatingHoursValue:setText(string.format("%s %s", vehicle:getFormattedOperatingTime(), g_i18n:getText("rms_ws_hours_unit")))
    
    local monthsSinceInspectionText = RMS_Utils.formatTimeAgo(self.vehicle:getLastInspectionDate())
    local inspectedService, isCompleteServiceInspection = self.vehicle:getLastInspectedService()
    local inspectedCondition, isCompleteInspection = self.vehicle:getLastInspectedCondition()

    self.serviceValue:setText(RMS_Utils.formatService(inspectedService, isCompleteServiceInspection))
    self.serviceValue:setTextColor(RMS_Utils.getServiceColor(inspectedService, isCompleteServiceInspection))
    self.conditionValue:setText(RMS_Utils.formatCondition(inspectedCondition, isCompleteInspection))
    self.conditionValue:setTextColor(RMS_Utils.getConditionColor(inspectedCondition, isCompleteInspection))
    self.conditionLastInspectionDeltaValue:setTextColor(unpack(RMS_Utils.COLOR.TEXT_DIM))
    self.conditionLastInspectionDeltaValue:setText(monthsSinceInspectionText)
    self.diagnosticLastInspection:setText(monthsSinceInspectionText)
    self.diagnosticService:setText(RMS_Utils.formatService(inspectedService, isCompleteServiceInspection))
    self.diagnosticService:setTextColor(RMS_Utils.getServiceColor(inspectedService, isCompleteServiceInspection))
    self.diagnosticCondition:setText(RMS_Utils.formatCondition(inspectedCondition, isCompleteInspection))
    self.diagnosticCondition:setTextColor(RMS_Utils.getConditionColor(inspectedCondition, isCompleteInspection))
    self.conditionRingRatio = RMS_Utils.getConditionRingRatio(inspectedCondition, isCompleteInspection)
    self.serviceRingRatio = RMS_Utils.getServiceRingRatio(inspectedService, isCompleteServiceInspection)

    local serviceHours, serviceInterval = self.vehicle:getServiceCountdown()
    self.relAndMainLabel:setText(g_i18n:getText(
        RealisticMechanicalSystems.MAINTENANCE_LABEL_TEXT_KEYS[self.vehicle:getDueMaintenanceType()]))
    self.relAndMainValue:setText(RMS_Utils.formatOperatingHours(serviceHours, serviceInterval))

    -- breakdown table, restricted to the breakdowns already discovered
    self.visibleBreakdowns = {}
    for id, breakdown in pairs(self.activeBreakdowns) do
        if breakdown.isVisible then
            table.insert(self.visibleBreakdowns, id)
        end
    end
    table.sort(self.visibleBreakdowns, function(a, b)
        local aStage = self.activeBreakdowns[a] ~= nil and (self.activeBreakdowns[a].stage or 0) or 0
        local bStage = self.activeBreakdowns[b] ~= nil and (self.activeBreakdowns[b].stage or 0) or 0
        if aStage ~= bStage then
            return aStage > bStage
        end
        return tostring(a) < tostring(b)
    end)

    self.breakdownTable:setDataSource(self)
    self.breakdownTable:setDelegate(self)
    self.breakdownTable:reloadData()

    -- status line, closed workshop and running service both disable the buttons
    local buttonsDisabled = false
    local statusText = ""
    
    local isWorkshopTypeOpen = RMS_Main == nil
        or RMS_Main.isWorkshopTypeOpen == nil
        or RMS_Main:isWorkshopTypeOpen(self.workshopType)

    if not isWorkshopTypeOpen then
        buttonsDisabled = true
        statusText = g_i18n:getText("rms_ws_status_closed")
    else
        statusText = g_i18n:getText("rms_ws_status_open")
    end

    if spec.currentState ~= STATUS.READY then
        buttonsDisabled = true
        local finishTimeText = RMS_Utils.formatFinishTime(self.vehicle:getServiceFinishTime(nil, nil, nil, nil))
        local localizedStatus = g_i18n:getText(spec.currentState)
        statusText = string.format(g_i18n:getText("rms_ws_status_in_progress_format"), localizedStatus, finishTimeText)
        if spec.currentState ~= STATUS.REPAIR and spec.currentState ~= STATUS.REFILL then
            local operationInProgressText = string.format(g_i18n:getText("rms_ws_status_in_progress_short_format"), localizedStatus)
            self.serviceValue:setText(operationInProgressText)
            self.serviceValue:setTextColor(unpack(RMS_Utils.COLOR.TEXT_DIM))
            self.conditionValue:setText(operationInProgressText)
            self.conditionValue:setTextColor(unpack(RMS_Utils.COLOR.TEXT_DIM))
        end
    end

    local workshopTypeKey = RMS_Utils.getKeyByValue(RealisticMechanicalSystems.WORKSHOP, self.workshopType)
    local workshopTypeText = workshopTypeKey ~= nil and g_i18n:getText(self.workshopType) or ""
    if workshopTypeText ~= "" then
        statusText = statusText .. " · " .. workshopTypeText
    end

    -- the three status bars carry the same sentence, so they carry the same colour
    local statusColor = isWorkshopTypeOpen and RMS_Utils.COLOR.TEXT or RMS_Utils.COLOR.TEXT_DIM
    self.statusText:setText(statusText)
    self.statusText:setTextColor(unpack(statusColor))
    self.diagnosticStatusText:setText(statusText)
    self.diagnosticStatusText:setTextColor(unpack(statusColor))

    -- An overhaul requires at least one eligible system.
    local hasSystemEligibleForOverhaul = #RMS_Utils.getEligibleOverhaulSystems(self.vehicle) > 0

    if g_workshopScreen.isDealer or g_workshopScreen.isOwnWorkshop then
        self.inspectionButton.disabled = buttonsDisabled 
        self.maintenanceButton.disabled = buttonsDisabled
        self.repairButton.disabled = buttonsDisabled
        self.overhaulButton:setDisabled(buttonsDisabled or not hasSystemEligibleForOverhaul)
    else
        self.inspectionButton.disabled = buttonsDisabled or spec.currentState ~= STATUS.READY
        self.maintenanceButton.disabled = buttonsDisabled or spec.currentState ~= STATUS.READY
        self.repairButton.disabled = buttonsDisabled or spec.currentState ~= STATUS.READY
        self.overhaulButton:setDisabled(true)
    end

    local isUnderService = spec.currentState ~= STATUS.READY
    self.cancelServiceButton:setVisible(isUnderService)
    self.cancelServiceButton.disabled = not isUnderService
    self.inspectionButton:setVisible(not isUnderService)
    self.maintenanceButton:setVisible(not isUnderService)
    self.repairButton:setVisible(not isUnderService)
    self.overhaulButton:setVisible(not isUnderService)
    self.refillButton:setVisible(not isUnderService)
    self.refillButton:setDisabled(self.vehicle.getMissingFluidShare ~= nil and self.vehicle:getMissingFluidShare() <= 0.001)
    self.bodyworkButton:setVisible(not isUnderService)
    self.cancelServiceButtonSeparator:setVisible(isUnderService)
    self.inspectionButtonSeparator:setVisible(not isUnderService)
    self.maintenanceButtonSeparator:setVisible(not isUnderService)
    self.repairButtonSeparator:setVisible(not isUnderService)
    self.overhaulButtonSeparator:setVisible(not isUnderService)
    self.refillButtonSeparator:setVisible(not isUnderService)
    self.bodyworkButtonSeparator:setVisible(not isUnderService)
    self:updateInterventionPanels(statusText, isWorkshopTypeOpen, isUnderService)

    local repairPrice = RMS_FluidWorkshop.getTransactionPrice(
        self.vehicle,
        RealisticMechanicalSystems.STATUS.REPAIR,
        self.workshopType,
        RealisticMechanicalSystems.REPAIR_TYPES.MEDIUM,
        RealisticMechanicalSystems.PART_TYPES.OEM,
        false
    ) or 0

    local selectedRepairCount = 0
    for _, breakdown in pairs(self.activeBreakdowns) do
        if breakdown ~= nil and breakdown.isVisible and breakdown.isSelectedForRepair then
            selectedRepairCount = selectedRepairCount + 1
        end
    end

    -- with no breakdown ticked there is no repair to configure, and the three ways into the repair
    -- dialog close together: the bottom bar, the card of the interventions tab and the estimate
    if selectedRepairCount == 0 then
        self.repairButton.disabled = true
    end
    self.diagnosticConfigureButton:setDisabled(selectedRepairCount == 0 or isUnderService)
    -- a closed workshop or a running service leaves nothing to configure: the whole list waits
    for _, button in ipairs(self.interventionActionButtons) do
        button:setDisabled(buttonsDisabled)
    end
    self.interventionActionButtons[RMS_WorkshopDialog.INTERVENTION_ACTION.REPAIR]:setDisabled(buttonsDisabled or selectedRepairCount == 0)
    -- the mobile workshop cannot repaint, so the card and the bottom bar close together
    local isBodyworkDisabled = buttonsDisabled or self.workshopType == RealisticMechanicalSystems.WORKSHOP.MOBILE
    self.interventionActionButtons[RMS_WorkshopDialog.INTERVENTION_ACTION.BODYWORK]:setDisabled(isBodyworkDisabled)
    self.bodyworkButton:setDisabled(isBodyworkDisabled)
    self.interventionActionButtons[RMS_WorkshopDialog.INTERVENTION_ACTION.OVERHAUL]:setDisabled(
        buttonsDisabled or not hasSystemEligibleForOverhaul)
    self.interventionActionButtons[RMS_WorkshopDialog.INTERVENTION_ACTION.BODYWORK]:setSelected(
        self.bodyworkSelected == true and not isUnderService)
    self:updateBodyworkQuote(isWorkshopTypeOpen, isUnderService)
    self:updateDiagnosticEstimate(selectedRepairCount, repairPrice)
    -- the bar carries the shortcuts, not a price list: each figure is quoted by the dialog that starts the work
    self.inspectionButton:setText(g_i18n:getText("rms_ws_action_inspection"))
    self.maintenanceButton:setText(g_i18n:getText("rms_ws_action_maintenance"))
    self.repairButton:setText(g_i18n:getText("rms_ws_action_repair"))
    self.overhaulButton:setText(g_i18n:getText("rms_ws_action_overhaul"))
    self.refillButton:setText(g_i18n:getText("rms_ws_action_refill"))
    if self.refillButton.parent ~= nil and self.refillButton.parent.invalidateLayout ~= nil then
        self.refillButton.parent:invalidateLayout()
    end

    -- The status bar reports a running service; the diagnostic list remains deterministic.
    local isListEmpty = #self.visibleBreakdowns == 0
    self.breakdownTable:setVisible(not isListEmpty)
    self.emptyTableText:setVisible(isListEmpty)
    self.emptyTableText:setText(g_i18n:getText("rms_ws_info_no_breakdowns"))
    self.emptyTableText:setTextColor(unpack(RMS_Utils.COLOR.TEXT_DIM))

    self:updateSummaryPanels()
    self:updateTechnicalRecord()
    self:setCurrentTab(self.currentTab)

    -- every value is written by now, so each pill can close on the one it wraps
    RMS_Utils.fitValuePills(self)
end

---Fills the system bars of the condition card from the report snapshot, never the live systems
function RMS_WorkshopDialog:updateSummarySystems()
    local entry = getLastReportEntry(self.vehicle)
    local systems = entry ~= nil and entry.conditionData ~= nil and entry.conditionData.systems or nil
    -- per system figures are a measurement: without a complete diagnosis the card says so instead
    local isMeasured = systems ~= nil and RealisticMechanicalSystems.getIsCompleteReport(entry)

    self.summarySystemsLayout:setVisible(isMeasured)
    self.summarySystemsEmptyText:setVisible(not isMeasured)
    self.summarySystemsEmptyText:setText(g_i18n:getText(systems == nil
        and "rms_ws_no_last_report_message"
        or "rms_ws_systems_need_complete_inspection"))

    if not isMeasured then
        return
    end

    for index, systemL10nKey in ipairs(RealisticMechanicalSystems.SYSTEMS_ORDER) do
        local systemKey = RMS_Utils.getSystemKey(RealisticMechanicalSystems.SYSTEMS, systemL10nKey)
        local systemData
        if type(systems) == "table" and systemKey ~= nil then
            systemData = systems[systemKey]
        end
        local isEnabled = type(systemData) == "table" and systemData.enabled ~= false
        local condition = isEnabled and clampRatio(systemData.condition or 1) or 0
        local percent = condition * 100
        local gaugeElement = self.summarySystemGauge[index]
        local rowElement = self.summarySystemRow[index]

        rowElement:setVisible(isEnabled)
        self.summarySystemName[index]:setText(isEnabled and g_i18n:getText(systemL10nKey) or "")
        self.summarySystemValue[index]:setText(isEnabled and string.format("%d", math.floor(percent + 0.5)) or "")
        gaugeElement:setVisible(isEnabled)
        gaugeElement:setSize(self.systemGaugeWidths[index] * condition, nil)
        gaugeElement:setImageColor(nil, RMS_Utils.getGaugeColor(percent, 95, 80, 60, 40, true))
    end

    self.summarySystemsLayout:invalidateLayout()
end

---Fills the four figures of the service card that the ring does not carry
function RMS_WorkshopDialog:updateSummaryService()
    local spec = self.vehicle.spec_RealisticMechanicalSystems
    local lastMaintenanceDate = self.vehicle:getLastMaintenanceDate()

    self.summaryReliability:setText(string.format("%d %%", math.floor(clampRatio(spec.reliability or 1) * 100 + 0.5)))
    self.summaryMaintainability:setText(string.format("%.2f", spec.maintainability or 1))
    self.summaryLastMaintenance:setText(type(lastMaintenanceDate) == "table"
        and formatLogDate({date = lastMaintenanceDate})
        or g_i18n:getText("rms_spec_never"))
    self.summaryOverhaulCount:setText(string.format("%d", self.vehicle:getOverhaulPerformedCount() or 0))
end

---Updates the summary alert and fluid level cards
function RMS_WorkshopDialog:updateSummaryPanels()
    self:updateSummarySystems()
    self:updateSummaryService()

    local spec = self.vehicle.spec_RealisticMechanicalSystems
    local alertId = self.visibleBreakdowns[1]
    local alertData = alertId ~= nil and self.activeBreakdowns[alertId] or nil
    local alertDefinition = alertId ~= nil and self.breakdownRegistry[alertId] or nil
    local hasAlert = alertData ~= nil and alertDefinition ~= nil

    self.summaryAlertRow:setVisible(hasAlert)
    self.summaryNoAlertText:setVisible(not hasAlert)

    -- only the worst breakdown gets a row, so the count tells how many more wait in the diagnostic tab
    local alertCount = #self.visibleBreakdowns
    local alertsTitle = g_i18n:getText("rms_ws_section_alerts")
    if alertCount > 1 then
        alertsTitle = string.format("%s · (x%d)", alertsTitle, alertCount)
    end
    self.summaryAlertsTitle:setText(alertsTitle)

    if alertData ~= nil and alertDefinition ~= nil then
        local stageDefinition = alertData.stage ~= nil and alertDefinition.stages ~= nil
            and alertDefinition.stages[alertData.stage] or nil
        local partKey = alertDefinition.part or alertDefinition.system
        local descriptionKey = stageDefinition ~= nil and stageDefinition.description or nil
        local descriptionText = descriptionKey ~= nil and g_i18n:getText(descriptionKey) or "-"

        if alertData.isActive == false and alertData.source == RealisticMechanicalSystems.BREAKDOWN_SOURCES.QUICK_FIX then
            descriptionText = g_i18n:getText("rms_breakdowns_temporarily_repaired_description")
        elseif alertData.isActive == false and alertData.source == RealisticMechanicalSystems.BREAKDOWN_SOURCES.POOR_PARTS then
            descriptionText = g_i18n:getText("rms_breakdowns_defected_parts_detected_description")
        end

        self.summaryAlertPart:setText(partKey ~= nil and g_i18n:getText(partKey) or tostring(alertId))
        self.summaryAlertDescription:setText(descriptionText)
        self.summaryAlertPrice:setText(g_i18n:formatMoney(
            self.vehicle:getBreakdownRepairPrice(alertId, alertData.stage, RealisticMechanicalSystems.PART_TYPES.OEM, self.workshopType),
            0,
            true,
            false
        ))
    end

    local fluidUnit = g_i18n:getText("unit_literShort")
    local quantityFormat = g_i18n:getText("rms_inspection_fluid_quantity_format")
    for _, fields in ipairs(FLUID_FIELDS) do
        -- a row only for the oils the machine holds, one for a common sump
        local hasCircuit = spec.systems[RMS_Fluids.CIRCUITS[fields.circuit].systemKey].enabled ~= false
            and RMS_Fluids.getSumpCircuit(self.vehicle, fields.circuit) == fields.circuit
        self[fields.row]:setVisible(hasCircuit)

        if hasCircuit then
            local level = RMS_Fluids.getLevel(self.vehicle, fields.circuit)
            local valueElement = self[fields.value]
            local gaugeElement = self[fields.gauge]
            local baseWidth = self.fluidGaugeWidths[fields.gauge] or gaugeElement.size[1]

            self.fluidGaugeWidths[fields.gauge] = baseWidth
            valueElement:setText(string.format(
                quantityFormat,
                RMS_FluidWorkshop.formatLiters(RMS_Fluids.getLiters(self.vehicle, fields.circuit)),
                RMS_FluidWorkshop.formatLiters(RMS_Fluids.getCapacity(self.vehicle, fields.circuit)),
                fluidUnit
            ))
            gaugeElement:setSize(GuiUtils.alignValueToScreenPixels(baseWidth * level, true), nil)
        end
    end

    self.transmissionOilTitle:setText(g_i18n:getText(
        RMS_Fluids.getCircuitTextKey(self.vehicle, "transmissionOil", "rms_inspection_transmission_oil")))
    self.fluidRowsLayout:invalidateLayout()
end

---Updates the selected repair estimate shown beside the breakdown list
-- @param integer selectedRepairCount number of selected breakdowns
-- @param float repairPrice transaction price for the default repair options
function RMS_WorkshopDialog:updateDiagnosticEstimate(selectedRepairCount, repairPrice)
    local selectedParts = {}

    for _, breakdownId in ipairs(self.visibleBreakdowns) do
        local breakdown = self.activeBreakdowns[breakdownId]
        local definition = self.breakdownRegistry[breakdownId]
        if breakdown ~= nil and breakdown.isSelectedForRepair and definition ~= nil then
            local partKey = definition.part or definition.system
            table.insert(selectedParts, partKey ~= nil and g_i18n:getText(partKey) or tostring(breakdownId))
        end
    end

    -- the quote is an estimate taken before the repair is configured: it lists the parts and the total, nothing else
    if #selectedParts > MAX_LISTED_PARTS then
        local hidden = #selectedParts - (MAX_LISTED_PARTS - 1)
        for _ = MAX_LISTED_PARTS, #selectedParts do
            table.remove(selectedParts)
        end
        table.insert(selectedParts, string.format(g_i18n:getText("rms_ws_label_more_parts"), hidden))
    end

    self.diagnosticEstimateParts = selectedParts
    self.diagnosticSelectedPartsTable:setDataSource(self)
    self.diagnosticSelectedPartsTable:reloadData()
    self.diagnosticSelectedPartsTable:setVisible(selectedRepairCount > 0)
    self.diagnosticTotal:setText(g_i18n:formatMoney(repairPrice or 0, 0, true, false))
end

---Updates the ready and running intervention panels from the persisted service context
-- @param string statusText workshop status text
-- @param boolean isWorkshopTypeOpen true when the current workshop accepts work
-- @param boolean isUnderService true while an intervention is running
function RMS_WorkshopDialog:updateInterventionPanels(statusText, isWorkshopTypeOpen, isUnderService)
    local spec = self.vehicle.spec_RealisticMechanicalSystems
    local currentStateText = isUnderService and getServiceTypeText(spec.currentState) or "-"
    local workshopStateText = g_i18n:getText(isWorkshopTypeOpen and "rms_ws_status_open" or "rms_ws_status_closed")
    local optionTexts = {}

    if spec.serviceOptionOne ~= nil and spec.serviceOptionOne ~= "NONE" then
        table.insert(optionTexts, g_i18n:getText(spec.serviceOptionOne))
    end
    if spec.currentState ~= RealisticMechanicalSystems.STATUS.BODYWORK
        and spec.serviceOptionTwo ~= nil and spec.serviceOptionTwo ~= "NONE" then
        table.insert(optionTexts, g_i18n:getText(spec.serviceOptionTwo))
    end

    local showBodywork = self.bodyworkSelected == true and not isUnderService
    self.interventionReadyPanel:setVisible(not isUnderService and not showBodywork)
    self.bodyworkOrderPanel:setVisible(showBodywork)
    self.interventionProgressPanel:setVisible(isUnderService)
    self.interventionSummaryDefault:setVisible(not showBodywork)
    self.bodyworkRecapPanel:setVisible(showBodywork)
    self.interventionCurrentName:setText(currentStateText)
    self.interventionCurrentDetail:setText(#optionTexts > 0 and table.concat(optionTexts, " · ") or "-")
    self.interventionWorkshopState:setText(workshopStateText)
    self.interventionSummaryVehicle:setText(self.vehicle:getFullName())
    self.interventionSummaryPrice:setText(isUnderService and g_i18n:formatMoney(spec.pendingServicePrice or 0, 0, true, false) or "-")
    self.interventionSummaryPriceLabel:setText(g_i18n:getText("rms_ws_label_committed_cost"))
    self.interventionStatusText:setText(statusText)
    self.interventionStatusText:setTextColor(unpack(isWorkshopTypeOpen and RMS_Utils.COLOR.TEXT or RMS_Utils.COLOR.TEXT_DIM))

    if isUnderService then
        local finishTime, daysToAdd = self.vehicle:getServiceFinishTime()
        self.interventionSummaryFinishTime:setText(RMS_Utils.formatFinishTime(finishTime, daysToAdd))
    else
        self.interventionSummaryFinishTime:setText("-")
    end
end

---Returns the selected technical log entry, displayed newest first
-- @return table? entry selected log entry
function RMS_WorkshopDialog:getSelectedTechnicalLogEntry()
    if self.selectedTechnicalLogIndex == nil then
        return nil
    end

    return self.technicalLogData[self.selectedTechnicalLogIndex]
end

---Refreshes the two-column breakdown preview and its empty state
-- @param table items localized breakdown names
-- @param string emptyText text displayed when the list is empty
function RMS_WorkshopDialog:updateTechnicalReportBreakdownList(items, emptyText)
    self.technicalReportBreakdownItems = items or {}
    self.technicalReportBreakdownTable:setDataSource(self)
    self.technicalReportBreakdownTable:reloadData()

    local hasItems = #self.technicalReportBreakdownItems > 0
    self.technicalReportBreakdownTable:setVisible(hasItems)
    self.technicalReportBreakdownEmpty:setText(emptyText or "-")
    self.technicalReportBreakdownEmpty:setVisible(not hasItems)
end

---Refreshes the recommendation preview and its empty state
-- @param table items localized recommendation texts
function RMS_WorkshopDialog:updateTechnicalReportRecommendationList(items)
    self.technicalReportRecommendationItems = items or {}
    self.technicalReportRecommendationTable:setDataSource(self)
    self.technicalReportRecommendationTable:reloadData()

    local hasItems = #self.technicalReportRecommendationItems > 0
    self.technicalReportRecommendationTable:setVisible(hasItems)
    self.technicalReportRecommendationEmpty:setVisible(not hasItems)
end

---Updates the report preview in the technical record
-- @param table? entry report log entry
function RMS_WorkshopDialog:updateTechnicalReportPreview(entry)
    local hasReport = entry ~= nil and RealisticMechanicalSystems.getIsLogEntryHasReport(entry)
    self.technicalOpenReportButton:setDisabled(not hasReport)

    if not hasReport then
        self.technicalReportTitle:setText(g_i18n:getText("rms_ws_label_last_report"))
        self.technicalReportMeta:setText(g_i18n:getText("rms_ws_no_last_report_message"))
        self.technicalReportCondition:setText("-")
        self.technicalReportCondition:setTextColor(unpack(RMS_Utils.COLOR.TEXT_DIM))
        self.technicalReportService:setText("-")
        self.technicalReportService:setTextColor(unpack(RMS_Utils.COLOR.TEXT_DIM))
        self.technicalReportBreakdowns:setText("-")
        self.technicalReportBreakdowns:setTextColor(unpack(RMS_Utils.COLOR.TEXT_DIM))
        self:updateTechnicalReportBreakdownList({}, "-")
        self:updateTechnicalReportRecommendationList({})
        RMS_Utils.fitValuePills(self)
        return
    end

    local conditionData = entry ~= nil and entry.conditionData or {}
    local isCompleteReport = RealisticMechanicalSystems.getIsCompleteReport(entry)
    local breakdownNames = {}
    local visibleBreakdownCount = 0

    for breakdownId, breakdown in pairs(conditionData.activeBreakdowns or {}) do
        if breakdown ~= nil and breakdown.isVisible then
            visibleBreakdownCount = visibleBreakdownCount + 1
            local definition = self.breakdownRegistry[breakdownId]
            local partKey = definition ~= nil and (definition.part or definition.system) or nil
            table.insert(breakdownNames, partKey ~= nil and g_i18n:getText(partKey) or tostring(breakdownId))
        end
    end
    table.sort(breakdownNames)

    local recommendationItems = {}
    local service = tonumber(conditionData.service)
    local condition = tonumber(conditionData.condition)
    if service ~= nil and service < 0.45 then
        table.insert(recommendationItems, g_i18n:getText("rms_report_recommendation_service_urgent"))
    elseif service ~= nil and service < 0.65 then
        table.insert(recommendationItems, g_i18n:getText("rms_report_recommendation_service_due"))
    end
    if visibleBreakdownCount > 0 then
        table.insert(recommendationItems, g_i18n:getText("rms_report_recommendation_repair_active_breakdowns"))
    end
    if condition ~= nil and condition < 0.4 then
        table.insert(recommendationItems, g_i18n:getText("rms_report_recommendation_overhaul"))
    end
    if #recommendationItems == 0 then
        table.insert(recommendationItems, g_i18n:getText("rms_report_recommendation_all_ok"))
    end

    self.technicalReportTitle:setText(g_i18n:getText("rms_report_header_title"))
    local reportDate = entry ~= nil and RMS_Utils.formatMaintenanceLogDate(entry) or "-"
    local serviceType = entry ~= nil and entry.type or nil
    self.technicalReportMeta:setText(string.format("%s · %s", reportDate, getServiceTypeText(serviceType)))
    self.technicalReportCondition:setText(RMS_Utils.formatCondition(conditionData.condition, isCompleteReport))
    self.technicalReportCondition:setTextColor(RMS_Utils.getConditionColor(conditionData.condition, isCompleteReport))
    self.technicalReportService:setText(RMS_Utils.formatService(conditionData.service, isCompleteReport))
    self.technicalReportService:setTextColor(RMS_Utils.getServiceColor(conditionData.service, isCompleteReport))
    self.technicalReportBreakdowns:setText(tostring(visibleBreakdownCount))
    self.technicalReportBreakdowns:setTextColor(unpack(HUD.COLOR.ACTIVE))
    self:updateTechnicalReportBreakdownList(breakdownNames, g_i18n:getText("rms_log_inspection_desc_no_breakdowns"))
    self:updateTechnicalReportRecommendationList(recommendationItems)
    RMS_Utils.fitValuePills(self)
end

---Rebuilds the technical record statistics, history and latest report preview
function RMS_WorkshopDialog:updateTechnicalRecord()
    local spec = self.vehicle.spec_RealisticMechanicalSystems
    local logEntries = spec.maintenanceLog or {}
    local totalCost = 0
    local maintenanceCount = 0
    local purchaseDate = nil

    self.technicalLogData = {}
    for index = #logEntries, 1, -1 do
        local entry = logEntries[index]
        if isLogEntryVisible(entry) then
            table.insert(self.technicalLogData, entry)
        end
    end

    for _, entry in ipairs(logEntries) do
        totalCost = totalCost + (tonumber(entry.price) or 0)
        if entry.id == 1 then
            purchaseDate = entry.date
        end
        if entry.type == RealisticMechanicalSystems.STATUS.MAINTENANCE then
            maintenanceCount = maintenanceCount + 1
        end
    end

    local environment = g_currentMission.environment
    local currentMonth = environment.currentPeriod
    local currentYear = environment.currentYear
    local purchaseMonth = purchaseDate ~= nil and (purchaseDate.month or currentMonth) or currentMonth
    local purchaseYear = purchaseDate ~= nil and (purchaseDate.year or currentYear) or currentYear
    local ownershipMonths = math.max(1, (currentMonth + (currentYear - 1) * 12) - (purchaseMonth + (purchaseYear - 1) * 12))

    self.technicalTotalCost:setText(g_i18n:formatMoney(totalCost, 0, true, false))
    self.technicalCostPerMonth:setText(g_i18n:formatMoney(totalCost / ownershipMonths, 0, true, false))
    self.technicalBreakdownsCount:setText(tostring(getResolvedBreakdownsCount(logEntries)))
    self.technicalMaintenanceCount:setText(tostring(maintenanceCount))

    self.technicalLogTable:setDataSource(self)
    self.technicalLogTable:setDelegate(self)
    self.technicalLogTable:reloadData()
    local isEmpty = #self.technicalLogData == 0
    self.technicalLogTable:setVisible(not isEmpty)
    self.technicalEmptyText:setVisible(isEmpty)

    if not isEmpty then
        if self.selectedTechnicalLogIndex == nil or self.selectedTechnicalLogIndex > #self.technicalLogData then
            self.selectedTechnicalLogIndex = 1
        end
        self.technicalLogTable:setSelectedItem(1, self.selectedTechnicalLogIndex, false, false)
    else
        self.selectedTechnicalLogIndex = nil
    end

    local reportEntry = self:getSelectedTechnicalLogEntry()
    if reportEntry == nil or not RealisticMechanicalSystems.getIsLogEntryHasReport(reportEntry) then
        reportEntry = nil
        for index = #logEntries, 1, -1 do
            if RealisticMechanicalSystems.getIsLogEntryHasReport(logEntries[index]) then
                reportEntry = logEntries[index]
                break
            end
        end
    end
    self:updateTechnicalReportPreview(reportEntry)
end

---Returns the progress of the running service as a whole percentage
-- @return integer? percent progress percentage, nil when no duration is known
function RMS_WorkshopDialog:getServiceProgressPercent()
    if self.vehicle == nil or self.vehicle.spec_RealisticMechanicalSystems == nil then
        return nil
    end

    local spec = self.vehicle.spec_RealisticMechanicalSystems
    local totalTime = spec.pendingProgressTotalTime or 0
    local elapsedTime = spec.pendingProgressElapsedTime or 0

    if totalTime <= 0 then
        return nil
    end

    local ratio = math.max(0, math.min(elapsedTime / totalTime, 1))
    return math.floor(ratio * 100)
end



---Draws the currency glyph on the vehicle value row
function RMS_WorkshopDialog:onDrawValueIcon()
    RMS_WorkshopDialog.drawCurrencyIcon(self.valueIconArea)
end

---Draws a maintenance glyph in a standard workshop information row
-- @param table area transparent GUI element receiving the XML draw callback
function RMS_WorkshopDialog:onDrawMaintenanceIcon(area)
    RMS_WorkshopDialog.drawMaintenanceIcon(area, "rms_workshopMaintenanceIcon")
end

---Draws a maintenance glyph in an intervention action button
-- @param table area transparent GUI element receiving the XML draw callback
function RMS_WorkshopDialog:onDrawMaintenanceActionIcon(area)
    RMS_WorkshopDialog.drawMaintenanceIcon(area, "rms_workshopMaintenanceActionIcon")
end

---Draws the engine-oil glyph in an intervention action button
-- @param table area transparent GUI element receiving the XML draw callback
function RMS_WorkshopDialog:onDrawOilActionIcon(area)
    RMS_WorkshopDialog.drawOilIcon(area, "rms_workshopOilActionIcon")
end

---Draws the last inspected condition ring
function RMS_WorkshopDialog:onDrawConditionRing()
    drawProgressRing(self.conditionRingArea, self.conditionRingRatio)
end

---Draws the last inspected service ring
function RMS_WorkshopDialog:onDrawServiceRing()
    drawProgressRing(self.serviceRingArea, self.serviceRingRatio)
end

---Reads the live progress of the running intervention and keeps the printed percentage in step
-- @return float ratio progress between 0 and 1
function RMS_WorkshopDialog:refreshInterventionProgress()
    local progressPercent = self:getServiceProgressPercent() or 0

    if progressPercent ~= self.lastDrawnInterventionPercent then
        self.lastDrawnInterventionPercent = progressPercent

        self.interventionProgressValue:setText(string.format("%d %%", progressPercent))
    end

    return progressPercent / 100
end

---Draws the running intervention progress ring
function RMS_WorkshopDialog:onDrawInterventionRing()
    drawProgressRing(self.interventionRingArea, self:refreshInterventionProgress())
end


---Returns the number of visible breakdowns
-- @param table list list element
-- @param integer section section index
-- @return integer count number of rows
function RMS_WorkshopDialog:getNumberOfItemsInSection(list, section)
    if list == self.diagnosticSelectedPartsTable then
        return #self.diagnosticEstimateParts
    end

    if list == self.technicalReportBreakdownTable then
        return math.ceil(#self.technicalReportBreakdownItems / 3)
    end

    if list == self.technicalReportRecommendationTable then
        return #self.technicalReportRecommendationItems
    end

    if list == self.technicalLogTable then
        return #self.technicalLogData
    end

    return #self.visibleBreakdowns
end


---Fills one breakdown row, the stage colour rising from white to red, dimmed when not selected
-- @param table list list element
-- @param integer section section index
-- @param integer index row index
-- @param table cell cell element
function RMS_WorkshopDialog:populateCellForItemInSection(list, section, index, cell)
    if list == self.diagnosticSelectedPartsTable then
        cell:getAttribute("diagnosticEstimatePart"):setText(self.diagnosticEstimateParts[index] or "")
        return
    end

    if list == self.technicalReportBreakdownTable then
        RMS_Utils.populateThreeColumnTextRow(
            self.technicalReportBreakdownItems,
            index,
            cell,
            "technicalReportBreakdownLeft",
            "technicalReportBreakdownCenter",
            "technicalReportBreakdownCenterBullet",
            "technicalReportBreakdownRight",
            "technicalReportBreakdownRightBullet"
        )
        return
    end

    if list == self.technicalReportRecommendationTable then
        cell:getAttribute("technicalReportRecommendationText"):setText(self.technicalReportRecommendationItems[index] or "")
        return
    end

    if list == self.technicalLogTable then
        self:populateTechnicalLogCell(index, cell)
        return
    end

    local breakdownId = self.visibleBreakdowns[index]
    local data = self.activeBreakdowns[breakdownId]
    if data == nil then return end

    local part_key = self.breakdownRegistry[breakdownId].part or self.breakdownRegistry[breakdownId].system
    local stage_key = self.breakdownRegistry[breakdownId].stages[data.stage].severity
    local description_key = self.breakdownRegistry[breakdownId].stages[data.stage].description
    local price = self.vehicle:getBreakdownRepairPrice(breakdownId, data.stage, RealisticMechanicalSystems.PART_TYPES.OEM, self.workshopType)
    local selected = data.isSelectedForRepair
    local descriptionElement = cell:getAttribute("rms_tableBreakdownDisc")

    RMS_Utils.applyScrollSpeed(cell)

    local stageText = ""
    local descriptionText = ""

    if data.isActive == false and data.source == RealisticMechanicalSystems.BREAKDOWN_SOURCES.QUICK_FIX then
        stageText = g_i18n:getText("rms_breakdowns_quick_fix_stage")
        descriptionText = g_i18n:getText("rms_breakdowns_temporarily_repaired_description")
    elseif data.isActive == false and data.source == RealisticMechanicalSystems.BREAKDOWN_SOURCES.POOR_PARTS then
        stageText = g_i18n:getText("rms_breakdowns_defected_parts_stage")
        descriptionText = g_i18n:getText("rms_breakdowns_defected_parts_detected_description")
    else
        stageText = g_i18n:getText(stage_key)
        descriptionText = g_i18n:getText(description_key)
    end

    cell:getAttribute("rms_tableBreakdownStage"):setTextColor(unpack(RMS_Utils.COLOR.STAGE[data.stage] or RMS_Utils.COLOR.STAGE[4]))

    cell:getAttribute("rms_tableBreakdownName"):setText(g_i18n:getText(part_key))
    descriptionElement:setText(descriptionText)
    cell:getAttribute("rms_tableBreakdownStage"):setText(stageText)
    cell:getAttribute("rms_tableBreakdownPrice"):setText(g_i18n:formatMoney(price, 0, true, false))
    
    
    local selectionToggle = cell:getAttribute("rms_tableBreakdownSelect")
    RMS_Utils.mirrorSelectionToChildren(selectionToggle)
    selectionToggle:setSelected(selected)

    if selected then
        cell:getAttribute("rms_tableBreakdownName"):setDisabled(false)
        cell:getAttribute("rms_tableBreakdownSeparator"):setDisabled(false)
        descriptionElement:setDisabled(false)
        cell:getAttribute("rms_tableBreakdownStage"):setDisabled(false)
        cell:getAttribute("rms_tableBreakdownPrice"):setDisabled(false)
    else
        cell:getAttribute("rms_tableBreakdownName"):setDisabled(true)
        cell:getAttribute("rms_tableBreakdownSeparator"):setDisabled(true)
        descriptionElement:setDisabled(true)
        descriptionElement:setText(descriptionText, nil, nil, true)
        cell:getAttribute("rms_tableBreakdownStage"):setDisabled(true)
        cell:getAttribute("rms_tableBreakdownPrice"):setDisabled(true)
    end
end

---Fills one technical history row
-- @param integer index row index
-- @param table cell cell element
function RMS_WorkshopDialog:populateTechnicalLogCell(index, cell)
    local entry = self.technicalLogData[index]
    if entry == nil then
        return
    end

    local typeText, color, iconSliceId, iconStyle = RMS_Utils.getLogTypePresentation(entry)
    local iconProfiles = RMS_Utils.LOG_ICON_PROFILES[iconStyle] or RMS_Utils.LOG_ICON_PROFILES.square
    local metaText = RMS_Utils.formatMaintenanceLogDate(entry)

    if entry.isCompleted == false then
        metaText = string.format("%s · %s", metaText, g_i18n:getText("rms_log_cancelled_desc"))
    elseif entry.optionOne ~= nil and entry.optionOne ~= "NONE" then
        metaText = string.format("%s · %s", metaText, g_i18n:getText(entry.optionOne))
    end

    local typeIcon = cell:getAttribute("technicalLogIcon")
    typeIcon:applyProfile(iconProfiles.row)
    typeIcon:setImageSlice(nil, iconSliceId)
    typeIcon:setImageColor(nil, unpack(color))
    cell:getAttribute("technicalLogType"):setText(typeText)
    cell:getAttribute("technicalLogType"):setTextColor(unpack(color))
    cell:getAttribute("technicalLogMeta"):setText(metaText)
    cell:getAttribute("technicalLogPrice"):setText(g_i18n:formatMoney(entry.price or 0, 0, true, false))
end


---Toggles the repair selection of the clicked breakdown
-- @param table button clicked button
function RMS_WorkshopDialog:onRowClick(button)
    if self.vehicle:getCurrentStatus() ~= RealisticMechanicalSystems.STATUS.READY then return end
    if button == nil or self.visibleBreakdowns[button.parent.indexInSection] == nil then return end
    
    local id = self.visibleBreakdowns[button.parent.indexInSection]
    local breakdown = self.activeBreakdowns[id]
    if breakdown then
        breakdown.isSelectedForRepair = not breakdown.isSelectedForRepair
        self:updateScreen()
    end
end

---Selects a technical history row and updates its report preview
-- @param table row clicked list row
function RMS_WorkshopDialog:onTechnicalRowClick(row)
    if row == nil or row.indexInSection == nil then
        return
    end

    self.selectedTechnicalLogIndex = row.indexInSection
    self.technicalLogTable:setSelectedItem(1, row.indexInSection, false, false)
    self:updateTechnicalReportPreview(self:getSelectedTechnicalLogEntry())
end

---Shows one workshop page and selects its tab
-- @param integer tabIndex workshop tab index
function RMS_WorkshopDialog:setCurrentTab(tabIndex)
    local selectedIndex = math.max(RMS_WorkshopDialog.TAB.SUMMARY, math.min(tonumber(tabIndex) or RMS_WorkshopDialog.TAB.SUMMARY, RMS_WorkshopDialog.TAB.TECHNICAL))
    self.currentTab = selectedIndex

    for index, page in ipairs(self.workshopPages or {}) do
        page:setVisible(index == selectedIndex)
        if index == selectedIndex then
            RMS_Utils.resetScrollingTexts(page)
        end
    end
    for index, tab in ipairs(self.workshopTabs or {}) do
        tab:setSelected(index == selectedIndex)
    end

    self.workshopTabPaging:setState(selectedIndex, false)
end

---Applies the tab the pager landed on, moved by a click, by its arrows or by left and right
function RMS_WorkshopDialog:onWorkshopTabPagingChanged()
    self:setCurrentTab(self.workshopTabPaging:getState())
    if self.currentTab == RMS_WorkshopDialog.TAB.INTERVENTIONS and self.vehicle ~= nil then
        self:updateScreen()
    end
end

---Shows the summary page
function RMS_WorkshopDialog:onClickSummaryTab()
    self:setCurrentTab(RMS_WorkshopDialog.TAB.SUMMARY)
end

---Shows the diagnostic and estimate page
function RMS_WorkshopDialog:onClickDiagnosticTab()
    self:setCurrentTab(RMS_WorkshopDialog.TAB.DIAGNOSTIC)
end

---Shows the interventions page
function RMS_WorkshopDialog:onClickInterventionsTab()
    self:setCurrentTab(RMS_WorkshopDialog.TAB.INTERVENTIONS)
    if self.vehicle ~= nil then
        self:updateScreen()
    end
end

---Shows the technical record page
function RMS_WorkshopDialog:onClickTechnicalTab()
    self:setCurrentTab(RMS_WorkshopDialog.TAB.TECHNICAL)
end

---Opens the maintenance log, or tells the player it holds nothing but the purchase entry
function RMS_WorkshopDialog:onClickShowLog()
    local spec = self.vehicle.spec_RealisticMechanicalSystems
    if #spec.maintenanceLog > 1 then
        RMS_MaintenanceLogDialog.show(self.vehicle, true)
    else
        InfoDialog.show(g_i18n:getText("rms_ws_no_log_empty_message"))
    end
end

---Opens the newest log entry carrying a report, or tells the player there is none
function RMS_WorkshopDialog:onClickShowReport()
    local spec = self.vehicle.spec_RealisticMechanicalSystems
    local selectedEntry = self.currentTab == RMS_WorkshopDialog.TAB.TECHNICAL and self:getSelectedTechnicalLogEntry() or nil
    if selectedEntry ~= nil and RealisticMechanicalSystems.getIsLogEntryHasReport(selectedEntry) then
        RMS_ReportDialog.show(self.vehicle, selectedEntry, self)
        return
    end

    for i = #spec.maintenanceLog, 1, -1 do
        local entry = spec.maintenanceLog[i]
        if RealisticMechanicalSystems.getIsLogEntryHasReport(entry) then
            RMS_ReportDialog.show(self.vehicle, entry, self)
            return
        end
    end
    InfoDialog.show(g_i18n:getText("rms_ws_no_last_report_message"))
end

---Moves between work orders through the single workshop navigation path
-- @param string serviceType requested intervention
-- @param table? sourceDialog open configuration dialog, when switching from one
function RMS_WorkshopDialog:selectIntervention(serviceType, sourceDialog)
    if self.vehicle == nil or (sourceDialog ~= nil and sourceDialog.vehicle ~= self.vehicle) then
        return
    end
    if sourceDialog ~= nil and sourceDialog.maintenanceType == serviceType then
        return
    end
    if serviceType == RealisticMechanicalSystems.STATUS.REPAIR
        and not RMS_Utils.hasSelectedVisibleBreakdown(self.vehicle) then
        return
    end
    if serviceType == RealisticMechanicalSystems.STATUS.OVERHAUL
        and #RMS_Utils.getEligibleOverhaulSystems(self.vehicle) == 0 then
        return
    end
    if serviceType == RealisticMechanicalSystems.STATUS.BODYWORK
        and self.workshopType == RealisticMechanicalSystems.WORKSHOP.MOBILE then
        return
    end

    if sourceDialog ~= nil then
        sourceDialog:close()
    end
    if serviceType == RealisticMechanicalSystems.STATUS.BODYWORK then
        self:onClickBodywork()
        return
    end

    self.bodyworkSelected = false
    self:setCurrentTab(RMS_WorkshopDialog.TAB.INTERVENTIONS)
    self:updateScreen()
    if serviceType == RealisticMechanicalSystems.STATUS.INSPECTION then
        RMS_MaintenanceTwoOptionsDialog.show(self.vehicle, serviceType)
    else
        RMS_MaintenanceThreeOptionsDialog.show(self.vehicle, serviceType)
    end
end

---Tells whether a child dialog can return to its workshop
-- @param table sourceDialog open child dialog
-- @return boolean isAvailable true when the matching workshop is still open
function RMS_WorkshopDialog.canNavigateFromChildDialog(sourceDialog)
    local workshop = RMS_WorkshopDialog.INSTANCE
    return workshop ~= nil and workshop.isDialogOpen == true
        and sourceDialog ~= nil and sourceDialog.vehicle == workshop.vehicle
        and sourceDialog.workshopContext ~= false
end

---Initializes the native workshop tab pager in a child dialog
-- @param table sourceDialog open child dialog
-- @param integer selectedTab initial workshop page
function RMS_WorkshopDialog.initializeChildTabPaging(sourceDialog, selectedTab)
    local tabTexts = {}
    for index in ipairs(sourceDialog.workshopNavTabs or {}) do
        table.insert(tabTexts, tostring(index))
    end

    sourceDialog.workshopTabBox:invalidateLayout()
    sourceDialog.workshopTabPaging:setTexts(tabTexts)
    sourceDialog.workshopTabPaging:setSize(sourceDialog.workshopTabBox.maxFlowSize + 140 * g_pixelSizeScaledX)
    sourceDialog.workshopTabPaging:setState(selectedTab, false)
    RMS_WorkshopDialog.updateChildTabAvailability(sourceDialog)
end

---Enables navigation to workshop pages only when this dialog was opened over that workshop
-- @param table sourceDialog child dialog with workshopNavTabs
function RMS_WorkshopDialog.updateChildTabAvailability(sourceDialog)
    local isAvailable = RMS_WorkshopDialog.canNavigateFromChildDialog(sourceDialog)
    for index, tab in ipairs(sourceDialog.workshopNavTabs or {}) do
        tab:setDisabled(index < RMS_WorkshopDialog.TAB.TECHNICAL and not isAvailable)
    end
    sourceDialog.workshopTabPaging:setDisabled(not isAvailable)
end

---Routes a native tab pager selection through the shared workshop navigation
-- @param table sourceDialog open child dialog
function RMS_WorkshopDialog.onChildTabPagingChanged(sourceDialog)
    if not RMS_WorkshopDialog.canNavigateFromChildDialog(sourceDialog) then
        return
    end

    RMS_WorkshopDialog.selectTabFromChildDialog(sourceDialog, sourceDialog.workshopTabPaging:getState())
end

---Returns from a child dialog to one of the workshop pages
-- @param table sourceDialog open child dialog
-- @param integer tabIndex workshop page
function RMS_WorkshopDialog.selectTabFromChildDialog(sourceDialog, tabIndex)
    local workshop = RMS_WorkshopDialog.INSTANCE
    if not RMS_WorkshopDialog.canNavigateFromChildDialog(sourceDialog) then
        return
    end

    local parentDialog = sourceDialog.parentDialog
    sourceDialog:close()
    if parentDialog ~= nil and parentDialog ~= workshop and parentDialog.vehicle == workshop.vehicle then
        parentDialog:close()
    end
    workshop:setCurrentTab(tabIndex)
    workshop:updateScreen()
end

---Routes the configuration side menu through the same intervention selector
-- @param table sourceDialog open configuration dialog
-- @param string serviceType requested intervention
function RMS_WorkshopDialog.selectInterventionFromConfiguration(sourceDialog, serviceType)
    local workshop = RMS_WorkshopDialog.INSTANCE
    if workshop ~= nil then
        workshop:selectIntervention(serviceType, sourceDialog)
    end
end

function RMS_WorkshopDialog:onClickInspection()
    self:selectIntervention(RealisticMechanicalSystems.STATUS.INSPECTION)
end

function RMS_WorkshopDialog:onClickService()
    self:selectIntervention(RealisticMechanicalSystems.STATUS.MAINTENANCE)
end

function RMS_WorkshopDialog:onClickRepair()
    self:selectIntervention(RealisticMechanicalSystems.STATUS.REPAIR)
end

function RMS_WorkshopDialog:onClickOverhaul()
    self:selectIntervention(RealisticMechanicalSystems.STATUS.OVERHAUL)
end

function RMS_WorkshopDialog:onClickRefill()
    self:selectIntervention(RealisticMechanicalSystems.STATUS.REFILL)
end

---Updates one native color selector from the vehicle's actual configurations.
function RMS_WorkshopDialog:getBodyworkColorTitle(zone)
    local storeItem = g_storeManager:getItemByXMLFilename(self.vehicle.configFileName)
    local items = storeItem ~= nil and storeItem.configurations ~= nil
        and storeItem.configurations[zone] or nil
    local desc = g_vehicleConfigurationManager:getConfigurationDescByName(zone)
    return items ~= nil and items[1] ~= nil and items[1].overwrittenTitle
        or desc.title
end

function RMS_WorkshopDialog:ensureBodyworkColorRows(zones)
    self.bodyworkExtraColorRows = self.bodyworkExtraColorRows or {}
    local fixed = {
        baseColor = {self.bodyworkBaseColorRow, self.bodyworkBaseColorOption},
        designColor = {self.bodyworkDesignColorRow, self.bodyworkDesignColorOption},
        rimColor = {self.bodyworkRimColorRow, self.bodyworkRimColorOption}
    }
    local active = {}
    local rows = {}
    local function addRow(key, title, callback)
        local zone = key
        active[zone] = true
        local row, control
        if fixed[zone] ~= nil then
            row, control = fixed[zone][1], fixed[zone][2]
        else
            row = self.bodyworkExtraColorRows[zone]
            if row == nil then
                row = self.bodyworkBaseColorRow:clone(self.bodyworkColorList)
                self.bodyworkExtraColorRows[zone] = row
                local button = row:getDescendantByName("colorImage").parent
                button.target = nil
                button.onClickCallback = callback
            end
            control = row:getDescendantByName("colorImage").parent
        end
        row:getDescendantByName("colorTitle"):setText(title)
        self.bodyworkColorList:addElement(row)
        rows[zone] = {row, control}
    end
    for _, zone in ipairs(zones) do
        addRow(zone, self:getBodyworkColorTitle(zone), function()
            self:openBodyworkColorPicker(zone)
        end)
    end
    for zone, row in pairs(self.bodyworkExtraColorRows) do
        if not active[zone] then
            row:delete()
            self.bodyworkExtraColorRows[zone] = nil
        end
    end
    for zone, elements in pairs(fixed) do
        if not active[zone] then
            elements[1]:setVisible(false)
        end
    end
    return rows
end

function RMS_WorkshopDialog:updateBodyworkColorOption(zone, row, control)
    local choices = RMS_Bodywork.getColorChoices(self.vehicle, zone, self.bodyworkSelectedColors)
    local customChoice = RMS_Bodywork.getCustomColorChoice(self.vehicle, zone, self.bodyworkSelectedColors)
    local selection = self.bodyworkSelectedColors[zone]
    local selectedChoice = nil
    for _, choice in ipairs(choices) do
        if choice.index == selection then
            selectedChoice = choice
            break
        end
    end
    local displayChoice = selectedChoice
    if displayChoice == nil then
        for _, choice in ipairs(choices) do
            if choice.index == (self.vehicle.configurations or {})[zone] then
                displayChoice = choice
                break
            end
        end
    end
    local isCustomSelected = type(selection) == "table" and customChoice ~= nil
        and customChoice.index == selection.index
    local currentCustomColor = nil
    if customChoice ~= nil and (self.vehicle.configurations or {})[zone] == customChoice.index then
        local data = (self.vehicle.configurationData or {})[zone]
        local currentData = data ~= nil and data[customChoice.index] or nil
        if currentData ~= nil and RMS_Bodywork.isValidColor(currentData.color) then
            currentCustomColor = currentData.color
        end
    end
    local hasChoices = #choices > 0 or customChoice ~= nil
    row:setVisible(hasChoices)
    control:setDisabled(not hasChoices)
    local colorChoice = selectedChoice or displayChoice
    local showCurrentCustom = currentCustomColor ~= nil
        and (selection == nil or selection == 0
            or (customChoice ~= nil and selection == customChoice.index))
    local uiColor = isCustomSelected and selection.color
        or showCurrentCustom and currentCustomColor
        or colorChoice ~= nil and colorChoice.item.uiColor
    local materialItem = nil
    if customChoice ~= nil and (isCustomSelected or showCurrentCustom) then
        materialItem = customChoice.item
    elseif colorChoice ~= nil then
        materialItem = colorChoice.item
    end
    local material = materialItem ~= nil and materialItem.isMetallic and "metallic"
        or materialItem ~= nil and materialItem.isMat and "matte" or "glossy"
    local colorImage = control:getDescendantByName("colorImage")
    colorImage:setVisible(uiColor ~= nil)
    if uiColor ~= nil then
        colorImage:setImageColor(nil, uiColor[1], uiColor[2], uiColor[3], 1)
    end
    control:getDescendantByName("colorImageMetallic"):setVisible(uiColor ~= nil and material == "metallic")
    control:getDescendantByName("colorImageGlossy"):setVisible(uiColor ~= nil and material == "glossy")
    control:getDescendantByName("colorImageMatte"):setVisible(uiColor ~= nil and material == "matte")
    return hasChoices
end

---Keeps the bodywork work order and estimate inside the workshop page.
function RMS_WorkshopDialog:updateBodyworkQuote(isWorkshopTypeOpen, isUnderService)
    local showBodywork = self.bodyworkSelected == true and not isUnderService
    self.bodyworkStartButton:setVisible(showBodywork)
    if not showBodywork then
        return
    end

    if self.workshopType == RealisticMechanicalSystems.WORKSHOP.OWN then
        self.bodyworkSelectedMode = RMS_Bodywork.TOUCHUP
    end
    local mode = self.bodyworkSelectedMode or RMS_Bodywork.FULL
    local colors = mode == RMS_Bodywork.FULL and RMS_Bodywork.encodeColors(self.vehicle, self.bodyworkSelectedColors) or nil
    local wear = RMS_Bodywork.getWear(self.vehicle)
    local price = RMS_FluidWorkshop.getTransactionPrice(
        self.vehicle, RealisticMechanicalSystems.STATUS.BODYWORK, self.workshopType, mode, colors, false)
    local duration = self.vehicle:getServiceDuration(
        RealisticMechanicalSystems.STATUS.BODYWORK, mode, colors, false, self.workshopType)
    local finishTime, daysToAdd = self.vehicle:getServiceFinishTime(
        RealisticMechanicalSystems.STATUS.BODYWORK, mode, colors, false, self.workshopType)
    local allowed = isWorkshopTypeOpen and RMS_Bodywork.isAllowed(self.vehicle, self.workshopType, mode, colors)
    local isDealer = self.workshopType == RealisticMechanicalSystems.WORKSHOP.DEALER
    updateBodyworkServiceButtons(self, mode, isDealer)

    local wearText = wear ~= nil and string.format("%.1f %%", wear * 100)
        or g_i18n:getText("rms_bodywork_unavailable")
    self.bodyworkWearValue:setText(wearText)
    self.bodyworkDescription:setText(g_i18n:getText(mode == RMS_Bodywork.TOUCHUP
        and "rms_bodywork_touchup_description" or "rms_bodywork_full_description"))
    self.bodyworkRecapType:setText(g_i18n:getText("button_repaint"))
    self.bodyworkRecapOptions:setText(g_i18n:getText(mode))
    self.bodyworkRecapPriceLabel:setText(stripTrailingColon(g_i18n:getText("rms_option_menu_price_text")))
    self.bodyworkRecapPrice:setText(allowed and price ~= nil and g_i18n:formatMoney(price, 0, true, false) or "-")
    self.bodyworkRecapDurationLabel:setText(g_i18n:getText("rms_option_menu_duration_text"))
    self.bodyworkRecapDuration:setText(price ~= nil and RMS_Utils.formatDuration(duration) or "-")
    self.bodyworkRecapFinishLabel:setText(stripTrailingColon(g_i18n:getText("rms_option_menu_finish_time_text")))
    self.bodyworkRecapFinish:setText(price ~= nil and RMS_Utils.formatFinishTime(finishTime, daysToAdd) or "-")
    self.bodyworkRecapVehicle:setText(self.vehicle.getFullName ~= nil and self.vehicle:getFullName() or g_i18n:getText("ui_vehicle"))
    local eligibilityKey = "rms_bodywork_ineligible"
    if not isWorkshopTypeOpen then
        eligibilityKey = "rms_ws_status_closed"
    elseif mode == RMS_Bodywork.TOUCHUP and wear ~= nil then
        if wear < RMS_Bodywork.MIN_TOUCHUP_WEAR then
            eligibilityKey = "rms_bodywork_no_wear"
        elseif wear > RMS_Bodywork.MAX_TOUCHUP_WEAR then
            eligibilityKey = "rms_bodywork_wear_limit"
        end
    end
    local canStart = allowed and price ~= nil
    self.bodyworkRecapAvailabilityPanel:setVisible(not canStart)
    if not canStart then
        self.bodyworkRecapEligibility:setText(g_i18n:getText(eligibilityKey))
    end
    self.bodyworkStartButton:setDisabled(not canStart)

    local hasColors = false
    local colorRowCount = 0
    if mode == RMS_Bodywork.FULL then
        local zones = RMS_Bodywork.getColorZones(self.vehicle)
        colorRowCount = #zones
        local rows = self:ensureBodyworkColorRows(zones)
        for _, zone in ipairs(zones) do
            hasColors = self:updateBodyworkColorOption(zone, rows[zone][1], rows[zone][2]) or hasColors
        end
    end
    self.bodyworkColorsHeader:setVisible(mode == RMS_Bodywork.FULL)
    self.bodyworkColorList:setVisible(hasColors)
    self.bodyworkColorSliderBox:setVisible(hasColors and colorRowCount > 3)
    self.bodyworkColorList:invalidateLayout()
    self.bodyworkNoColorPanel:setVisible(mode == RMS_Bodywork.FULL and not hasColors)
    self.bodyworkNoColorChoices:setText(g_i18n:getText("rms_bodywork_no_colors"))
end

function RMS_WorkshopDialog:onClickBodywork()
    if self.vehicle == nil then
        return
    end
    if self.bodyworkSelected then
        self:setCurrentTab(RMS_WorkshopDialog.TAB.INTERVENTIONS)
        self:updateScreen()
        return
    end
    self.bodyworkSelected = true
    self.bodyworkSelectedColors = {}
    local wear = RMS_Bodywork.getWear(self.vehicle)
    self.bodyworkSelectedMode = (self.workshopType == RealisticMechanicalSystems.WORKSHOP.OWN
        or (wear ~= nil and wear >= RMS_Bodywork.MIN_TOUCHUP_WEAR
            and wear <= RMS_Bodywork.MAX_TOUCHUP_WEAR))
        and RMS_Bodywork.TOUCHUP or RMS_Bodywork.FULL
    self:setCurrentTab(RMS_WorkshopDialog.TAB.INTERVENTIONS)
    self:updateScreen()
end

function RMS_WorkshopDialog:setBodyworkColor(zone, selectedIndex)
    self.bodyworkSelectedColors[zone] = selectedIndex
    for _, otherZone in ipairs(RMS_Bodywork.getColorZones(self.vehicle)) do
        if otherZone ~= zone and self.bodyworkSelectedColors[otherZone] ~= nil
            and self.bodyworkSelectedColors[otherZone] ~= 0 then
            local stillAvailable = false
            local otherSelection = self.bodyworkSelectedColors[otherZone]
            if type(otherSelection) == "table" then
                local customChoice = RMS_Bodywork.getCustomColorChoice(
                    self.vehicle, otherZone, self.bodyworkSelectedColors)
                stillAvailable = customChoice ~= nil and customChoice.index == otherSelection.index
            else
                for _, otherChoice in ipairs(RMS_Bodywork.getColorChoices(
                    self.vehicle, otherZone, self.bodyworkSelectedColors)) do
                    if otherChoice.index == otherSelection then
                        stillAvailable = true
                        break
                    end
                end
            end
            if not stillAvailable then
                self.bodyworkSelectedColors[otherZone] = 0
            end
        end
    end
    self:updateScreen()
end

function RMS_WorkshopDialog:selectBodyworkMode(mode)
    if mode ~= RMS_Bodywork.TOUCHUP and mode ~= RMS_Bodywork.FULL then
        return
    end
    if mode == RMS_Bodywork.FULL and self.workshopType ~= RealisticMechanicalSystems.WORKSHOP.DEALER then
        return
    end

    self.bodyworkSelectedMode = mode
    self:updateScreen()
end

function RMS_WorkshopDialog:onClickBodyworkTouchup()
    self:selectBodyworkMode(RMS_Bodywork.TOUCHUP)
end

function RMS_WorkshopDialog:onClickBodyworkFull()
    self:selectBodyworkMode(RMS_Bodywork.FULL)
end

---Applies the configuration index and optional custom color.
function RMS_WorkshopDialog:onBodyworkColorPicked(zone, choices, selectedIndex, customColorData)
    if customColorData ~= nil then
        local customChoice = RMS_Bodywork.getCustomColorChoice(
            self.vehicle, zone, self.bodyworkSelectedColors)
        local selectedColor = type(customColorData) == "table" and customColorData.customColor or nil
        if customChoice ~= nil and selectedColor ~= nil and RMS_Bodywork.isValidColor(selectedColor) then
            self:setBodyworkColor(zone, {
                index = customChoice.index,
                color = {selectedColor[1], selectedColor[2], selectedColor[3]}
            })
        end
        return
    end

    -- the picker answers with the place of the color in the list it was given
    local choice = type(selectedIndex) == "number" and choices[selectedIndex] or nil
    if choice ~= nil then
        self:setBodyworkColor(zone, choice.index)
    end
end

function RMS_WorkshopDialog:openBodyworkColorPicker(zone)
    if self.vehicle == nil or self.bodyworkSelectedMode ~= RMS_Bodywork.FULL
        or self.workshopType ~= RealisticMechanicalSystems.WORKSHOP.DEALER then
        return
    end
    local choices = RMS_Bodywork.getColorChoices(self.vehicle, zone, self.bodyworkSelectedColors)
    local customChoice = RMS_Bodywork.getCustomColorChoice(self.vehicle, zone, self.bodyworkSelectedColors)
    if #choices == 0 and customChoice == nil then
        return
    end
    if ColorPickerDialog == nil or ColorPickerDialog.INSTANCE == nil then
        InfoDialog.show(g_i18n:getText("rms_bodywork_unavailable"))
        return
    end
    local vehicle = self.vehicle
    local colors = {}
    local selection = self.bodyworkSelectedColors[zone]
    local currentIndex = type(selection) == "table" and selection.index or selection
    if currentIndex == nil or currentIndex == 0 then
        currentIndex = (self.vehicle.configurations or {})[zone]
    end
    local defaultColorIndex = nil
    local defaultMaterial = nil
    for position, choice in ipairs(choices) do
        local item = choice.item
        local material = item.isMetallic and "metallic" or item.isMat and "matte" or "glossy"
        colors[#colors + 1] = {
            name = item.name,
            color = item.color,
            material = material,
            materialTemplateName = item.materialTemplateName
        }
        if choice.index == currentIndex then
            defaultMaterial = material
            defaultColorIndex = position
        end
    end
    local customColor = nil
    if type(selection) == "table" then
        customColor = {selection.color[1], selection.color[2], selection.color[3],
            ColorPickerDialog.MATERIAL_GLOSSY}
    elseif customChoice ~= nil and currentIndex == customChoice.index then
        local data = (self.vehicle.configurationData or {})[zone]
        local currentData = data ~= nil and data[currentIndex] or nil
        if currentData ~= nil and RMS_Bodywork.isValidColor(currentData.color) then
            customColor = {currentData.color[1], currentData.color[2], currentData.color[3],
                ColorPickerDialog.MATERIAL_GLOSSY}
        end
    end
    ColorPickerDialog.show(function(_, selectedIndex, _, customColorData)
        if self.vehicle == vehicle and self.bodyworkSelectedMode == RMS_Bodywork.FULL then
            self:onBodyworkColorPicked(zone, choices, selectedIndex, customColorData)
        end
    end, self, nil, colors, defaultColorIndex, defaultMaterial, customColor,
        customChoice ~= nil, false, true)
end

function RMS_WorkshopDialog:onClickBodyworkBaseColor()
    self:openBodyworkColorPicker("baseColor")
end

function RMS_WorkshopDialog:onClickBodyworkDesignColor()
    self:openBodyworkColorPicker("designColor")
end

function RMS_WorkshopDialog:onClickBodyworkRimColor()
    self:openBodyworkColorPicker("rimColor")
end

function RMS_WorkshopDialog:onClickStartBodywork()
    local vehicle = self.vehicle
    if vehicle == nil then
        return
    end
    local mode = self.bodyworkSelectedMode
    local colors = mode == RMS_Bodywork.FULL and RMS_Bodywork.encodeColors(self.vehicle, self.bodyworkSelectedColors) or nil
    if not RMS_Bodywork.isAllowed(vehicle, self.workshopType, mode, colors) then
        return
    end
    local price = RMS_FluidWorkshop.getTransactionPrice(
        vehicle, RealisticMechanicalSystems.STATUS.BODYWORK, self.workshopType, mode, colors, false)
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
            vehicle, g_workshopScreen.sellingPoint, RealisticMechanicalSystems.STATUS.BODYWORK,
            self.workshopType, mode, colors, false, g_currentMission:getFarmId())
        if not started then
            RMS_FluidWorkshop.showResult(result)
            return
        end
        RMS_VehicleChangeStatusEvent.send(vehicle)
    else
        RMS_ServiceRequestEvent.send(
            vehicle, RealisticMechanicalSystems.STATUS.BODYWORK,
            self.workshopType, mode, colors, false)
    end
    self.bodyworkSelected = false
    self.bodyworkSelectedMode = nil
    self:updateScreen()
end

---Asks the player to confirm cancelling the running service
function RMS_WorkshopDialog:onClickCancelService()
    if self.vehicle == nil then return end
    local spec = self.vehicle.spec_RealisticMechanicalSystems
    if spec == nil or spec.currentState == RealisticMechanicalSystems.STATUS.READY then return end

    local title = string.format(g_i18n:getText("rms_ws_cancel_confirm_title"), g_i18n:getText(spec.currentState))
    local text = g_i18n:getText("rms_ws_cancel_confirm_text")

    if YesNoDialog ~= nil and YesNoDialog.show ~= nil then
        YesNoDialog.show(self.onCancelServiceConfirm, self, text, title, nil, nil)
    end
end

---Cancels the service on confirmation, locally on the server, by request from a client
-- @param boolean yes true when the player confirmed
function RMS_WorkshopDialog:onCancelServiceConfirm(yes)
    if yes and self.vehicle ~= nil then
        if g_server ~= nil then
            self.vehicle:cancelService()
        else
            RMS_CancelServiceEvent.send(self.vehicle)
        end
        self:updateScreen()
    end
end


---Caches the gauge widths and binds the tab selection
function RMS_WorkshopDialog:onCreate()
    self.fluidGaugeWidths = self.fluidGaugeWidths or {}
    for _, fields in ipairs(FLUID_FIELDS) do
        local gaugeElement = self[fields.gauge]
        if gaugeElement ~= nil then
            self.fluidGaugeWidths[fields.gauge] = gaugeElement.size[1]
        end
    end

    self.systemGaugeWidths = self.systemGaugeWidths or {}
    for index, gaugeElement in ipairs(self.summarySystemGauge or {}) do
        self.systemGaugeWidths[index] = gaugeElement.size[1]
    end
    for _, tab in ipairs(self.workshopTabs or {}) do
        RMS_Utils.mirrorSelectionToChildren(tab)
    end
    for _, button in ipairs(self.bodyworkServiceButtons or {}) do
        RMS_Utils.mirrorSelectionToChildren(button)
    end

    self:setCurrentTab(self.currentTab or RMS_WorkshopDialog.TAB.SUMMARY)
    RMS_Utils.applyScrollSpeed(self.dialogElement)
end

---Subscribes to the money, vehicle status and workshop status messages
function RMS_WorkshopDialog:onOpen()
    RMS_WorkshopDialog:superClass().onOpen(self)

    self.isDialogOpen = true
    RMS_Utils.resetScrollingTexts(self.workshopPages[self.currentTab])

    local tabTexts = {}
    for index in ipairs(self.workshopTabs) do
        table.insert(tabTexts, tostring(index))
    end

    self.workshopTabBox:invalidateLayout()
    self.workshopTabPaging:setTexts(tabTexts)
    self.workshopTabPaging:setSize(self.workshopTabBox.maxFlowSize + 140 * g_pixelSizeScaledX)
    self.workshopTabPaging:setState(self.currentTab, false)

    for _, button in ipairs(self.interventionActionButtons or {}) do
        RMS_Utils.centerActionContent(button)
    end

    ---Refreshes the screen when the displayed vehicle changed status
    -- @param table vehicle vehicle carried by the message
    local function onVehicleChangeStatusEvent(vehicle)
        if self.vehicle.node == vehicle.node then
            self:updateScreen()
        end
    end

    ---Refreshes the screen when the workshop opened or closed
    local function onWorkshopChangeStatusEvent()
        self:updateScreen()
    end

    g_messageCenter:subscribe(MessageType.MONEY_CHANGED, self.updateScreen, self)
    g_messageCenter:subscribe(MessageType.RMS_VEHICLE_CHANGE_STATUS, onVehicleChangeStatusEvent, self)
    g_messageCenter:subscribe(MessageType.RMS_WORKSHOP_CHANGE_STATUS, onWorkshopChangeStatusEvent, self)
end

---Clears the dialog state and flushes the pending money changes
function RMS_WorkshopDialog:onClose()
    self.isDialogOpen = false
    self.lastObservedStatus = nil
    for _, row in pairs(self.bodyworkExtraColorRows or {}) do
        row:delete()
    end
    self.bodyworkExtraColorRows = nil
    self.vehicle = nil
    self.currentTab = RMS_WorkshopDialog.TAB.SUMMARY
    self.technicalReportBreakdownItems = {}
    self.technicalReportRecommendationItems = {}
    self.technicalLogData = {}
    self.selectedTechnicalLogIndex = nil
    self.bodyworkSelected = false
    self.bodyworkSelectedMode = nil
    self.bodyworkSelectedColors = nil
    self.lastDrawnInterventionPercent = nil
    g_messageCenter:unsubscribeAll(self)
    g_currentMission:showMoneyChange(MoneyType.VEHICLE_RUNNING_COSTS)
    g_currentMission:showMoneyChange(MoneyType.SHOP_VEHICLE_BUY)
    g_currentMission:showMoneyChange(MoneyType.SHOP_VEHICLE_SELL)

    RMS_WorkshopDialog:superClass().onClose(self)
end

---Closes the dialog
function RMS_WorkshopDialog:onClickBack()
    self:close()
end
