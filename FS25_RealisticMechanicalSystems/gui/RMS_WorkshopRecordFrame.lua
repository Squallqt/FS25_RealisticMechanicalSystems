-- Copyright © 2026 Squallqt. All rights reserved.

---Record page: the maintenance log, and the report of an entry
RMS_WorkshopRecordFrame = {}

local RMS_WorkshopRecordFrame_mt = Class(RMS_WorkshopRecordFrame, RMS_WorkshopPage)

local MIN_HOURS_FOR_COST_PER_HOUR = 1

local HERO_METRICS = {
    { icon = "gui.icon_ingameMenu_statistics", label = "rms_log_recorded_interventions_title", figure = "entries" },
    { icon = "gui.icon_calendar", label = "rms_log_last_intervention_title", figure = "lastIntervention" },
    { icon = "gui.storeAttribute_operatingHours", label = "rms_ws_label_operating_hours", figure = "hours" }
}

-- pictogram, label and figure of each card, a cost in game money
local KPI_CARDS = {
    { profile = "rms_logKpiIcon", label = "rms_log_total_cost_title", figure = "totalCost", isCost = true },
    { profile = "rms_logKpiIcon", label = "rms_log_cost_per_month_title", figure = "costPerMonth", isCost = true },
    { profile = "rms_logKpiIcon", label = "rms_log_cost_per_hour_title", figure = "costPerHour", isCost = true },
    { profile = "rms_logKpiIcon", slice = "gui.icon_calendar", label = "rms_log_ownership_months_title", figure = "months" },
    { profile = "rms_logKpiIconWide", slice = "gui.contextAction_icon_repairAlert", label = "rms_log_total_breakdowns_count_title",
        figure = "breakdowns" },
    { profile = "rms_logKpiIcon", slice = "gui.icon_clock", label = "rms_log_average_breakdowns_interval_title", figure = "breakdownInterval" },
    { profile = "rms_logKpiMaintenanceIcon", label = "rms_log_average_maintenance_interval_title", figure = "maintenanceInterval" }
}

local function getPartNames(vehicle, entry)
    local names, seen = {}, {}
    for _, id in ipairs(entry.conditionData ~= nil and entry.conditionData.selectedBreakdowns or {}) do
        if RMS_Breakdowns.BreakdownRegistry[id] ~= nil then
            local name = RMS_Utils.getBreakdownPartName(id, vehicle)
            if not seen[name] then
                seen[name] = true
                table.insert(names, name)
            end
        end
    end
    return names
end

local function getLocation(entry)
    return RMS_Utils.getKeyByValue(RealisticMechanicalSystems.WORKSHOP, entry.location) ~= nil and g_i18n:getText(entry.location) or ""
end

local function getSystemSuffix(vehicle, entry)
    if entry.type ~= RealisticMechanicalSystems.STATUS.BODYWORK and entry.optionTwo ~= nil and entry.optionTwo ~= "NONE" then
        return " (" .. g_i18n:getText(RMS_Utils.getSystemLabel(vehicle, entry.optionTwo)) .. ")"
    end
    return ""
end

local function getPresentation(vehicle, entry)
    local STATUS = RealisticMechanicalSystems.STATUS
    local partNames = getPartNames(vehicle, entry)
    local suffix = getSystemSuffix(vehicle, entry)
    local performed = g_i18n:getText("rms_log_performed")
    if entry.isCompleted == false then
        return { summary = g_i18n:getText("rms_log_cancelled_desc"), detailLabel = "", detailItems = {} }
    elseif entry.type == RealisticMechanicalSystems.LOG_DIAGNOSTIC_READING then
        local codes = RMS_DiagnosticTool.getReadingCodes(vehicle, entry)
        return { summary = g_i18n:getText("rms_diagnostic_log_title"), detailLabel = g_i18n:getText("rms_diagnostic_log_codes"),
            detailItems = #codes > 0 and codes or { g_i18n:getText("rms_diagnostic_no_fault") } }
    elseif entry.type == STATUS.REPAIR then
        return { summary = g_i18n:getText("rms_log_repair_desc_generic") .. suffix,
            detailLabel = #partNames > 0 and g_i18n:getText("rms_log_total_breakdowns_count_title") or "", detailItems = partNames }
    elseif entry.type == STATUS.MAINTENANCE then
        return { summary = RMS_Utils.formatMaintenanceLevel(vehicle, entry.optionOne) .. suffix, detailLabel = #partNames > 0 and g_i18n:getText("rms_report_detected_breakdowns_title") or "",
            detailItems = partNames }
    elseif entry.type == STATUS.INSPECTION then
        return { summary = string.format(performed, g_i18n:getText("rms_ws_task_inspection"), g_i18n:getText(entry.optionOne)),
            detailLabel = g_i18n:getText("rms_report_detected_breakdowns_title"),
            detailItems = #partNames > 0 and partNames or { g_i18n:getText("rms_log_inspection_desc_no_breakdowns") } }
    elseif entry.type == STATUS.OVERHAUL then
        return { summary = string.format(performed, g_i18n:getText("rms_ws_task_overhaul"), g_i18n:getText(entry.optionOne)),
            detailLabel = entry.optionThree and g_i18n:getText("rms_log_description") or "",
            detailItems = entry.optionThree and { g_i18n:getText("rms_log_overhaul_desc_with_painting") } or {} }
    elseif entry.type == STATUS.BODYWORK then
        return { summary = g_i18n:getText(entry.optionOne), detailLabel = "", detailItems = {} }
    end
    return { summary = (RMS_Utils.getLogTypePresentation(entry)), detailLabel = "", detailItems = {} }
end

local function getDescription(vehicle, entry)
    local STATUS = RealisticMechanicalSystems.STATUS
    local partNames = getPartNames(vehicle, entry)
    local partsText = string.format(g_i18n:getText("rms_log_inspection_desc_with_breakdowns"), table.concat(partNames, ", "))
    local description = getPresentation(vehicle, entry).summary
    if entry.isCompleted == false then
        description = g_i18n:getText("rms_log_cancelled_desc")
    elseif entry.type == RealisticMechanicalSystems.LOG_DIAGNOSTIC_READING then
        description = RMS_DiagnosticTool.formatReadingCodes(vehicle, entry)
    elseif entry.type == STATUS.REPAIR then
        description = (#partNames > 0 and table.concat(partNames, ", ") or g_i18n:getText("rms_log_repair_desc_generic"))
            .. getSystemSuffix(vehicle, entry)
    elseif entry.type == STATUS.MAINTENANCE and #partNames > 0 then
        description = description .. ". " .. partsText
    elseif entry.type == STATUS.INSPECTION then
        description = description .. ". " .. (#partNames > 0 and partsText or g_i18n:getText("rms_log_inspection_desc_no_breakdowns"))
    elseif entry.type == STATUS.OVERHAUL and entry.optionThree then
        description = description .. ". " .. g_i18n:getText("rms_log_overhaul_desc_with_painting")
    end
    local location = getLocation(entry)
    if location ~= "" then
        description = description .. " · " .. location
    end
    return description
end

---Creates the page
function RMS_WorkshopRecordFrame.new()
    local self = RMS_WorkshopPage.new(nil, RMS_WorkshopRecordFrame_mt)
    self.entries = {}
    self.detailItems = {}
    self.invoiceRows = {}
    return self
end

---Wires the lists and the report view
function RMS_WorkshopRecordFrame:initialize(dialog)
    RMS_WorkshopRecordFrame:superClass().initialize(self, dialog)
    for _, list in ipairs({ self.logTable, self.detailPartsTable, self.invoiceTable }) do
        list:setDataSource(self)
        list:setDelegate(self)
    end
    self.report:initialize(dialog)
    self.heroMetrics = RMS_Utils.cloneTemplate(self.heroMetricTemplate, #HERO_METRICS)
    for index, entry in ipairs(HERO_METRICS) do
        self.heroMetrics[index]:getDescendantByName("icon"):setImageSlice(nil, entry.icon)
        self.heroMetrics[index]:getDescendantByName("label"):setText(g_i18n:getText(entry.label))
    end
    self.kpiCards = RMS_Utils.cloneTemplate(self.kpiCardTemplate, #KPI_CARDS)
    for index, entry in ipairs(KPI_CARDS) do
        local icon = self.kpiCards[index]:getDescendantByName("icon")
        icon:applyProfile(entry.profile)
        if entry.slice ~= nil then
            icon:setImageSlice(nil, entry.slice)
        end
        self.kpiCards[index]:getDescendantByName("label"):setText(g_i18n:getText(entry.label))
    end
end

---Opens the log on the newest entry
function RMS_WorkshopRecordFrame:setVehicle(vehicle, workshopType)
    RMS_WorkshopRecordFrame:superClass().setVehicle(self, vehicle, workshopType)
    self.selectedIndex = 1
    self:showReport(nil)
end

---Writes the header, the figures, the history and the selected entry
function RMS_WorkshopRecordFrame:refresh()
    local vehicle = self.vehicle
    local spec = vehicle.spec_RealisticMechanicalSystems
    local log = spec.maintenanceLog
    self.entries = RMS_Utils.getVisibleLogEntries(vehicle)

    self.logVehicleImage:setImageFilename(vehicle:getImageFilename())
    self.vehicleNameValue:setText(vehicle:getFullName())
    self.vehicleLogIdentityValue:setText(g_i18n:getText("rms_log_header_title") .. " · ODO "
        .. RMS_Utils.formatOdometerKilometers(RMS_Utils.getOdometerKilometers(vehicle)))
    local figures = {
        entries = tostring(#self.entries),
        lastIntervention = self.entries[1] ~= nil and RMS_Utils.formatMaintenanceLogDate(self.entries[1]) or "-",
        hours = RMS_Utils.formatHours(RMS_Utils.getHourMeter(vehicle))
    }

    local totalCost, purchaseDate, purchaseHours = 0, nil, 0
    for _, entry in ipairs(log) do
        totalCost = totalCost + (entry.price or 0)
        if entry.id == 1 then
            purchaseDate = entry.date
            purchaseHours = entry.conditionData ~= nil and entry.conditionData.operatingHours or 0
        end
    end
    local environment = g_currentMission.environment
    local month, year = environment.currentPeriod, environment.currentYear
    local purchaseMonth = purchaseDate ~= nil and purchaseDate.month or month
    local purchaseYear = purchaseDate ~= nil and purchaseDate.year or year
    local months = math.max(1, (month + (year - 1) * 12) - (purchaseMonth + (purchaseYear - 1) * 12))
    local ownedHours = spec.realOperatingTime / (60 * 60 * 1000) - purchaseHours
    local breakdownCount = RMS_Utils.getResolvedBreakdownsCount(log)
    figures.totalCost = g_i18n:formatMoney(totalCost, 0, true, false)
    figures.costPerMonth = g_i18n:formatMoney(totalCost / months, 0, true, false) .. " / " .. g_i18n:getText("rms_ws_age_unit")
    figures.costPerHour = ownedHours >= MIN_HOURS_FOR_COST_PER_HOUR
        and g_i18n:formatMoney(totalCost / ownedHours, 0, true, false) .. " / " .. g_i18n:getText("rms_spec_op_hours_short") or "-"
    figures.months = string.format("%d %s", months, g_i18n:getText("rms_ws_age_unit"))
    figures.breakdowns = string.format("%d", breakdownCount)
    figures.breakdownInterval = breakdownCount > 0 and RMS_Utils.formatHours(math.max(ownedHours / breakdownCount, 0)) or "-"

    local maintenanceCount, intervalSum, lastHours = 0, 0, purchaseHours
    for _, entry in ipairs(log) do
        local hours = entry.conditionData ~= nil and tonumber(entry.conditionData.operatingHours) or nil
        if entry.type == RealisticMechanicalSystems.STATUS.MAINTENANCE and entry.isCompleted ~= false and hours ~= nil then
            intervalSum = intervalSum + math.max(hours - lastHours, 0)
            lastHours = hours
            maintenanceCount = maintenanceCount + 1
        end
    end
    figures.maintenanceInterval = maintenanceCount > 0 and RMS_Utils.formatHours(intervalSum / maintenanceCount) or "-"
    for index, entry in ipairs(HERO_METRICS) do
        self.heroMetrics[index]:getDescendantByName("value"):setText(figures[entry.figure])
    end
    for index, entry in ipairs(KPI_CARDS) do
        if entry.isCost then
            RMS_Utils.setCurrencyIcon(self.kpiCards[index]:getDescendantByName("icon"))
        end
        self.kpiCards[index]:getDescendantByName("value"):setText(figures[entry.figure])
    end

    self.logTable:reloadData()
    local isEmpty = #self.entries == 0
    self.logTable:setVisible(not isEmpty)
    self.emptylogText:setVisible(isEmpty)
    if not isEmpty then
        self.selectedIndex = math.min(self.selectedIndex, #self.entries)
        self.logTable:setSelectedItem(1, self.selectedIndex, false, false)
    end
    self:updateSelectedEntry()
end

---Writes the card of the selected entry
function RMS_WorkshopRecordFrame:updateSelectedEntry()
    local entry = self.entries[self.selectedIndex]
    self.selectedLogIcon:setVisible(entry ~= nil)
    self.selectedLogLocation:setVisible(entry ~= nil)
    if entry == nil then
        self.selectedLogType:setText("-")
        self.selectedLogType:setTextColor(unpack(RMS_Utils.COLOR.TEXT))
        self.selectedLogDate:setText("-")
        self.selectedLogHours:setText("-")
        self.selectedLogPrice:setText("-")
        self.selectedLogSummary:setText(g_i18n:getText("rms_log_empty"))
        self.selectedLogDetailsHeader:setVisible(false)
        self.detailItems, self.invoiceRows = {}, {}
    else
        local typeText, color, iconSliceId, iconStyle = RMS_Utils.getLogTypePresentation(entry)
        local presentation = getPresentation(self.vehicle, entry)
        self.selectedLogIcon:applyProfile(RMS_Utils.LOG_ICON_PROFILES[iconStyle].detail)
        self.selectedLogIcon:setImageSlice(nil, iconSliceId)
        self.selectedLogIcon:setImageColor(nil, unpack(color))
        self.selectedLogType:setText(typeText)
        self.selectedLogType:setTextColor(unpack(color))
        self.selectedLogDate:setText(RMS_Utils.formatMaintenanceLogDate(entry))
        self.selectedLogHours:setText(RMS_Utils.formatHours(math.floor((entry.conditionData ~= nil and tonumber(entry.conditionData.operatingHours) or 0) * 10) / 10))
        self.selectedLogPrice:setText(g_i18n:formatMoney(entry.price or 0, 0, true, false))
        self.selectedLogSummary:setText(presentation.summary)
        local location = getLocation(entry)
        self.selectedLogLocation:setText((location ~= "" and location .. " · " or "") .. "ODO "
            .. RMS_Utils.formatOdometerKilometers(entry.conditionData ~= nil and entry.conditionData.odometerKilometers or nil))
        self.invoiceRows = entry.isCompleted ~= false and entry.invoice ~= nil
            and RMS_FluidWorkshop.getInvoiceRows(self.vehicle, entry.type, entry.optionOne, entry.invoice, true) or {}
        local hasInvoice = #self.invoiceRows > 0
        local detailLabel = hasInvoice and g_i18n:getText("rms_log_invoice_title") or presentation.detailLabel
        self.selectedLogDetailsLabel:setText(detailLabel)
        self.selectedLogDetailsHeader:setVisible(detailLabel ~= "")
        self.detailItems = hasInvoice and {} or presentation.detailItems
    end
    self.invoiceTable:reloadData()
    self.invoiceTable:setVisible(#self.invoiceRows > 0)
    self.detailPartsTable:reloadData()
    self.detailPartsTable:setVisible(#self.detailItems > 0)
    self.detailIdentityRow:invalidateLayout()
    RMS_Utils.fitValuePills(self)
    self.dialog:updateButtons()
end

---Rows of a list
function RMS_WorkshopRecordFrame:getNumberOfItemsInSection(list)
    if list == self.detailPartsTable then
        return math.ceil(#self.detailItems / 2)
    elseif list == self.invoiceTable then
        return #self.invoiceRows
    end
    return #self.entries
end

---Fills a row of a list
function RMS_WorkshopRecordFrame:populateCellForItemInSection(list, _section, index, cell)
    if list == self.detailPartsTable then
        RMS_Utils.populateTwoColumnTextRow(self.detailItems, index, cell, "detailPartLeft", "detailPartRight", "detailPartRightBullet")
        return
    elseif list == self.invoiceTable then
        local row = self.invoiceRows[index]
        cell:getAttribute("invoiceLabel"):setText(row.label)
        cell:getAttribute("invoiceAmount"):setText(row.price ~= nil and g_i18n:formatMoney(row.price, 0, true, false) or "")
        return
    end

    local entry = self.entries[index]
    local typeText, color, iconSliceId, iconStyle = RMS_Utils.getLogTypePresentation(entry)
    local icon = cell:getAttribute("logTypeIcon")
    icon:applyProfile(RMS_Utils.LOG_ICON_PROFILES[iconStyle].row)
    icon:setImageSlice(nil, iconSliceId)
    icon:setImageColor(nil, unpack(color))
    cell:getAttribute("logType"):setText(typeText)
    cell:getAttribute("logType"):setTextColor(unpack(color))
    cell:getAttribute("logDate"):setText(RMS_Utils.formatMaintenanceLogDate(entry))
    cell:getAttribute("logHours"):setText(RMS_Utils.formatHours(math.floor((entry.conditionData ~= nil and tonumber(entry.conditionData.operatingHours) or 0) * 10) / 10))
    cell:getAttribute("logDescription"):setText(getDescription(self.vehicle, entry))
    cell:getAttribute("logPrice"):setText(g_i18n:formatMoney(entry.price or 0, 0, true, false))
end

---Follows the entry the list selects
function RMS_WorkshopRecordFrame:onListSelectionChanged(list, _section, index)
    if list == self.logTable and index ~= self.selectedIndex then
        self.selectedIndex = index
        self:updateSelectedEntry()
    end
end

---Selects the clicked entry
function RMS_WorkshopRecordFrame:onRowClick(row)
    self.logTable:setSelectedItem(1, row.indexInSection, false, false)
end

---Shows the report of an entry, or the log again
function RMS_WorkshopRecordFrame:showReport(entry)
    self.logView:setVisible(entry == nil)
    self.reportView:setVisible(entry ~= nil)
    if entry ~= nil then
        self.report:setReport(self.vehicle, entry)
    end
end

---Opens the report of the selected entry
function RMS_WorkshopRecordFrame:onAction()
    self:showReport(self.entries[self.selectedIndex])
    self.dialog:setTab(RMS_WorkshopDialog.TAB.RECORD)
end

---The report button of the log
function RMS_WorkshopRecordFrame:getAction()
    if self.reportView:getIsVisible() then
        return nil, true
    end
    local entry = self.entries[self.selectedIndex]
    return g_i18n:getText("rms_log_button_show_report"), entry == nil or not RealisticMechanicalSystems.getIsLogEntryHasReport(entry)
end

---Leaves the report for the log
function RMS_WorkshopRecordFrame:goBack()
    if not self.reportView:getIsVisible() then
        return false
    end
    self:showReport(nil)
    self.dialog:setTab(RMS_WorkshopDialog.TAB.RECORD)
    return true
end

---The history list, or the lists of the report
function RMS_WorkshopRecordFrame:getFocusColumns()
    if self.reportView:getIsVisible() then
        return self.report:getFocusColumns()
    end
    return { { { self.logTable } } }
end
