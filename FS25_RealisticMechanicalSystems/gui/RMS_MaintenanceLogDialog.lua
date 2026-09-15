-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---Maintenance log dialog listing the service history of a vehicle and its ownership statistics
RMS_MaintenanceLogDialog = {}
RMS_MaintenanceLogDialog.INSTANCE = nil

local RMS_MaintenanceLogDialog_mt = Class(RMS_MaintenanceLogDialog, MessageDialog)
local modDirectory = g_currentModDirectory

---Draws the native maintenance glyph in the maintenance interval KPI
-- @param table area transparent GUI element receiving the XML draw callback
function RMS_MaintenanceLogDialog:onDrawMaintenanceKpiIcon(area)
    RMS_WorkshopDialog.drawMaintenanceIcon(area, "rms_logKpiMaintenanceIcon")
end

---Draws the player's native currency glyph in a cost KPI
-- @param table area transparent GUI element receiving the XML draw callback
function RMS_MaintenanceLogDialog:onDrawCurrencyKpiIcon(area)
    RMS_WorkshopDialog.drawCurrencyIcon(area)
end

---Tells whether a repaired breakdown is worth listing, general wear is not
-- @param string? breakdownId breakdown id
-- @return boolean isLoggable true when the breakdown is listed
local function isLoggableRepairBreakdownId(breakdownId)
    return breakdownId ~= nil and breakdownId ~= "GENERAL_WEAR"
end

---Tells whether a log entry is shown, treating a missing flag as visible and accepting string flags
-- @param table? entry maintenance log entry
-- @return boolean isVisible true when the entry is listed
local function isLogEntryVisible(entry)
    if entry == nil then
        return false
    end

    local value = entry.isVisible
    if value == nil then
        return true
    end

    if type(value) == "string" then
        local v = string.lower(value)
        if v == "false" or v == "0" or v == "off" or v == "no" then
            return false
        end
        return true
    end

    return value ~= false
end

---Counts the breakdowns resolved by the completed repair and overhaul entries
-- @param table logEntries maintenance log entries
-- @return integer count number of resolved breakdowns
local function getResolvedBreakdownsCount(logEntries)
    if type(logEntries) ~= "table" then
        return 0
    end

    local total = 0
    local S = RealisticMechanicalSystems.STATUS

    for _, entry in ipairs(logEntries) do
        if entry ~= nil and entry.isCompleted ~= false then
            local entryType = entry.type

            if entryType == S.REPAIR or entryType == S.OVERHAUL then
                local conditionData = entry.conditionData
                local selectedBreakdowns = conditionData ~= nil and conditionData.selectedBreakdowns or nil

                if type(selectedBreakdowns) == "table" then
                    for _, breakdownId in ipairs(selectedBreakdowns) do
                        if breakdownId ~= nil and breakdownId ~= "GENERAL_WEAR" then
                            total = total + 1
                        end
                    end
                end
            end
        end
    end

    return total
end

local formatLogDate = RMS_Utils.formatMaintenanceLogDate
local getLogTypePresentation = RMS_Utils.getLogTypePresentation
local LOG_ICON_PROFILES = RMS_Utils.LOG_ICON_PROFILES

---Returns the unique localized part names stored by a maintenance log entry
-- @param table entry maintenance log entry
-- @return table partNames localized part names
local function getLogPartNames(entry)
    local repairedParts = {}
    local seenParts = {}

    if entry.conditionData ~= nil and type(entry.conditionData.selectedBreakdowns) == "table" then
        for _, breakdownId in ipairs(entry.conditionData.selectedBreakdowns) do
            if isLoggableRepairBreakdownId(breakdownId) then
                local breakdownDef = RMS_Breakdowns.BreakdownRegistry[breakdownId]
                local partKey = breakdownDef ~= nil and (breakdownDef.part or breakdownDef.system) or nil
                if partKey ~= nil and not seenParts[partKey] then
                    table.insert(repairedParts, partKey)
                    seenParts[partKey] = true
                end
            end
        end
    end

    local partNames = {}
    for _, partKey in ipairs(repairedParts) do
        table.insert(partNames, g_i18n:getText(partKey))
    end

    return partNames
end

---Returns the localized workshop name stored by a maintenance log entry
-- @param table entry maintenance log entry
-- @return string locationText localized workshop name
local function getLogLocation(entry)
    local locationKey = RMS_Utils.getKeyByValue(RealisticMechanicalSystems.WORKSHOP, entry.location)
    return locationKey ~= nil and g_i18n:getText(entry.location) or ""
end

---Builds the compact localized description displayed by a history row
-- @param table entry maintenance log entry
-- @return string description localized intervention description
local function getLogDescription(entry)
    local status = RealisticMechanicalSystems.STATUS
    local partNames = getLogPartNames(entry)
    local description = ""

    if entry.isCompleted == false then
        description = g_i18n:getText("rms_log_cancelled_desc")
    else
        local partTypeSuffix = ""
        if entry.optionTwo ~= nil and entry.optionTwo ~= "NONE" then
            partTypeSuffix = " (" .. g_i18n:getText(entry.optionTwo) .. ")"
        end

        if entry.type == status.REPAIR then
            description = table.concat(partNames, ", ")
            if description == "" then
                description = g_i18n:getText("rms_log_repair_desc_generic")
            end
            description = description .. partTypeSuffix
        elseif entry.type == status.MAINTENANCE then
            description = string.format(g_i18n:getText("rms_log_performed"), g_i18n:getText("rms_ws_task_maintenance"), g_i18n:getText(entry.optionOne))
            description = description .. partTypeSuffix
            if #partNames > 0 then
                description = description .. ". " .. string.format(g_i18n:getText("rms_log_inspection_desc_with_breakdowns"), table.concat(partNames, ", "))
            end
        elseif entry.type == status.INSPECTION then
            description = string.format(g_i18n:getText("rms_log_performed"), g_i18n:getText("rms_ws_task_inspection"), g_i18n:getText(entry.optionOne))
            if #partNames > 0 then
                description = description .. ". " .. string.format(g_i18n:getText("rms_log_inspection_desc_with_breakdowns"), table.concat(partNames, ", "))
            else
                description = description .. ". " .. g_i18n:getText("rms_log_inspection_desc_no_breakdowns")
            end
        elseif entry.type == status.OVERHAUL then
            description = string.format(g_i18n:getText("rms_log_performed"), g_i18n:getText("rms_ws_task_overhaul"), g_i18n:getText(entry.optionOne))
            if entry.optionThree then
                description = description .. ". " .. g_i18n:getText("rms_log_overhaul_desc_with_painting")
            end
        end
    end

    local locationText = getLogLocation(entry)
    if locationText ~= "" then
        description = description .. (description ~= "" and " · " or "") .. locationText
    end

    return description
end

---Builds the structured content displayed by the selected-entry card
-- @param table entry maintenance log entry
-- @return table presentation summary, detail label, detail items and workshop name
local function getLogDetailPresentation(entry)
    local status = RealisticMechanicalSystems.STATUS
    local partNames = getLogPartNames(entry)
    local presentation = {
        summary = "",
        detailLabel = "",
        detailItems = {},
        location = getLogLocation(entry)
    }

    if entry.isCompleted == false then
        presentation.summary = g_i18n:getText("rms_log_cancelled_desc")
        return presentation
    end

    local partTypeSuffix = ""
    if entry.optionTwo ~= nil and entry.optionTwo ~= "NONE" then
        partTypeSuffix = " (" .. g_i18n:getText(entry.optionTwo) .. ")"
    end

    if entry.type == status.REPAIR then
        presentation.summary = g_i18n:getText("rms_log_repair_desc_generic") .. partTypeSuffix
        if #partNames > 0 then
            presentation.detailLabel = g_i18n:getText("rms_log_total_breakdowns_count_title")
            presentation.detailItems = partNames
        end
    elseif entry.type == status.MAINTENANCE then
        presentation.summary = string.format(g_i18n:getText("rms_log_performed"), g_i18n:getText("rms_ws_task_maintenance"), g_i18n:getText(entry.optionOne)) .. partTypeSuffix
        if #partNames > 0 then
            presentation.detailLabel = g_i18n:getText("rms_report_detected_breakdowns_title")
            presentation.detailItems = partNames
        end
    elseif entry.type == status.INSPECTION then
        presentation.summary = string.format(g_i18n:getText("rms_log_performed"), g_i18n:getText("rms_ws_task_inspection"), g_i18n:getText(entry.optionOne))
        presentation.detailLabel = g_i18n:getText("rms_report_detected_breakdowns_title")
        presentation.detailItems = #partNames > 0 and partNames or {g_i18n:getText("rms_log_inspection_desc_no_breakdowns")}
    elseif entry.type == status.OVERHAUL then
        presentation.summary = string.format(g_i18n:getText("rms_log_performed"), g_i18n:getText("rms_ws_task_overhaul"), g_i18n:getText(entry.optionOne))
        if entry.optionThree then
            presentation.detailLabel = g_i18n:getText("rms_log_description")
            presentation.detailItems = {g_i18n:getText("rms_log_overhaul_desc_with_painting")}
        end
    else
        presentation.summary = getLogTypePresentation(entry)
    end

    return presentation
end

---Loads the dialog layout and stores the shared instance
function RMS_MaintenanceLogDialog.register()
    local dialog = RMS_MaintenanceLogDialog.new()
    g_gui:loadGui(modDirectory .. "gui/RMS_MaintenanceLogDialog.xml", "RMS_MaintenanceLogDialog", dialog)
    RMS_MaintenanceLogDialog.INSTANCE = dialog
end

---Create instance of RMS_MaintenanceLogDialog
-- @param table? target target
-- @param table? customMt custom metatable
-- @return table dialog instance of class RMS_MaintenanceLogDialog
function RMS_MaintenanceLogDialog.new(target, customMt)
    local dialog = MessageDialog.new(target, customMt or RMS_MaintenanceLogDialog_mt)
    dialog.vehicle = nil
    dialog.logDataAll = nil
    dialog.detailLogItems = {}
    dialog.selectedLogIndex = nil
    return dialog
end

---Returns the selected log entry, the list being displayed newest first
-- @return table? entry selected maintenance log entry
function RMS_MaintenanceLogDialog:getSelectedLogEntry()
    if self.logData == nil or self.selectedLogIndex == nil then
        return nil
    end

    local entryIndex = #self.logData - self.selectedLogIndex + 1
    return self.logData[entryIndex]
end

---Enables the report button only when the selected entry carries a report
function RMS_MaintenanceLogDialog:updateShowReportButtonState()
    local entry = self:getSelectedLogEntry()
    local disabled = not (entry ~= nil and RealisticMechanicalSystems.getIsLogEntryHasReport(entry))

    if self.showReportButton ~= nil then
        self.showReportButton:setDisabled(disabled)
    end
end

---Refreshes the dossier card from the currently selected timeline entry
function RMS_MaintenanceLogDialog:updateSelectedEntryDetails()
    local entry = self:getSelectedLogEntry()
    local hasEntry = entry ~= nil

    self.selectedLogIcon:setVisible(hasEntry)
    if not hasEntry then
        self.selectedLogType:setText("-")
        self.selectedLogType:setTextColor(unpack(RMS_Utils.COLOR.TEXT))
        self.selectedLogDate:setText("-")
        self.selectedLogHours:setText("-")
        self.selectedLogSummary:setText(g_i18n:getText("rms_log_empty"))
        self.selectedLogLocation:setText("")
        self.selectedLogLocation:setVisible(false)
        self.selectedLogDetailsLabel:setText("")
        self.selectedLogDetailsHeader:setVisible(false)
        self.detailLogItems = {}
        self.detailPartsTable:setVisible(false)
        self.selectedLogPrice:setText("-")
        self.detailIdentityRow:invalidateLayout()
        RMS_Utils.fitValuePills(self)
        self:updateShowReportButtonState()
        return
    end

    local typeText, color, iconSliceId, iconStyle = getLogTypePresentation(entry)
    local operatingHours = entry.conditionData ~= nil and tonumber(entry.conditionData.operatingHours) or 0
    local iconProfiles = LOG_ICON_PROFILES[iconStyle] or LOG_ICON_PROFILES.square
    local presentation = getLogDetailPresentation(entry)

    self.selectedLogIcon:applyProfile(iconProfiles.detail)
    self.selectedLogIcon:setImageSlice(nil, iconSliceId)
    self.selectedLogIcon:setImageColor(nil, unpack(color))
    self.selectedLogType:setText(typeText)
    self.selectedLogType:setTextColor(unpack(color))
    self.selectedLogDate:setText(formatLogDate(entry))
    self.selectedLogHours:setText(string.format("%.1f %s", operatingHours, g_i18n:getText("rms_spec_hour_s")))
    self.selectedLogSummary:setText(presentation.summary)
    self.selectedLogLocation:setText(presentation.location)
    self.selectedLogLocation:setVisible(presentation.location ~= "")
    self.selectedLogDetailsLabel:setText(presentation.detailLabel)
    self.selectedLogDetailsHeader:setVisible(presentation.detailLabel ~= "")
    self.detailLogItems = presentation.detailItems
    self.detailPartsTable:setDataSource(self)
    self.detailPartsTable:reloadData()
    self.detailPartsTable:setVisible(#self.detailLogItems > 0)
    if #self.detailLogItems > 0 then
        self.detailPartsTable:setSelectedItem(1, 1, false, false)
    end
    self.selectedLogPrice:setText(g_i18n:formatMoney(entry.price or 0, 0, true, false))
    self.detailIdentityRow:invalidateLayout()
    RMS_Utils.fitValuePills(self)
    self:updateShowReportButtonState()
end

---Rebuilds the displayed list from the full log, keeping the visible entries
function RMS_MaintenanceLogDialog:rebuildVisibleLogData()
    self.logData = {}
    if self.logDataAll == nil then
        return
    end

    for _, entry in ipairs(self.logDataAll) do
        if isLogEntryVisible(entry) then
            table.insert(self.logData, entry)
        end
    end
end

---Opens the dialog on a vehicle with its newest entry selected
-- @param table vehicle vehicle
function RMS_MaintenanceLogDialog.show(vehicle)
    if RMS_MaintenanceLogDialog.INSTANCE == nil then RMS_MaintenanceLogDialog.register() end
    if vehicle == nil or vehicle.spec_RealisticMechanicalSystems == nil then return end
    
    local dialog = RMS_MaintenanceLogDialog.INSTANCE
    dialog.vehicle = vehicle
    
    dialog.logDataAll = vehicle.spec_RealisticMechanicalSystems.maintenanceLog or {}
    dialog:rebuildVisibleLogData()
    dialog.selectedLogIndex = #dialog.logData > 0 and 1 or nil
    
    dialog:updateScreen()
    g_gui:showDialog("RMS_MaintenanceLogDialog")
end

---Rebuilds the log list and the ownership statistics header
function RMS_MaintenanceLogDialog:updateScreen()
    if self.vehicle == nil then return end

    local spec = self.vehicle.spec_RealisticMechanicalSystems
    self.logDataAll = spec.maintenanceLog or {}
    self:rebuildVisibleLogData()

    local balanceText = g_i18n:formatMoney(g_currentMission:getMoney(), 0, true, false)
    self.balanceElement:setText(balanceText)
    RMS_Utils.updateMoneyBoxLayout(
        self.balanceTitleElement,
        self.balanceElement,
        self.moneyBox,
        self.moneyBoxBg,
        g_i18n:getText("ui_balance"),
        balanceText
    )
    self.logVehicleImage:setImageFilename(self.vehicle:getImageFilename())
    self.vehicleNameValue:setText(self.vehicle:getFullName())
    self.visibleEntryCountValue:setText(tostring(#self.logData))
    local latestVisibleEntry = self.logData[#self.logData]
    self.lastInterventionValue:setText(latestVisibleEntry ~= nil and formatLogDate(latestVisibleEntry) or "-")
    self.vehicleHoursValue:setText(string.format("%s %s", self.vehicle:getFormattedOperatingTime(), g_i18n:getText("rms_ws_hours_unit")))

    local totalCost = 0
    local totalBreakdowns = getResolvedBreakdownsCount(self.logDataAll)
    local purchaseDate = {}
    local purchaseHours = 0

    for _, entry in pairs(self.logDataAll) do
        totalCost = totalCost + (entry.price or 0)
        if entry.id == 1 then
            purchaseDate = entry.date or {}
            purchaseHours = entry.conditionData and entry.conditionData.operatingHours or 0
        end
    end

    self.totalCostValue:setText(g_i18n:formatMoney(totalCost, 0, true, false))

    -- ownership age in months, counted from the first log entry
    local currentYear = g_currentMission.environment.currentYear
    local currentMonth = g_currentMission.environment.currentPeriod
    
    local pMonth = (purchaseDate and purchaseDate.month) or currentMonth
    local pYear = (purchaseDate and purchaseDate.year) or currentYear
    local age = math.max(1, (currentMonth + (currentYear - 1) * 12) - (pMonth + (pYear - 1) * 12))
    
    local costPerMonth = totalCost / age
    local currentLoggedHours = (tonumber(spec.realOperatingTime) or 0) / (60 * 60 * 1000)
    local avgBreakdownInterval = totalBreakdowns > 0 and math.max(((currentLoggedHours - (purchaseHours or 0)) / totalBreakdowns), 0) or 0
    local averageMaintenanceInterval = 0

    self.costPerMonthValue:setText(g_i18n:formatMoney(costPerMonth, 0, true, false) .. " / " .. g_i18n:getText("rms_ws_age_unit"))
    self.ownershipMonthsValue:setText(tostring(age) .. " " .. g_i18n:getText("rms_ws_age_unit"))
    self.totalBreakdownsCountValue:setText(string.format("%d", totalBreakdowns))
    if totalBreakdowns > 0 then
        self.averageBreakdownsIntervalValue:setText(string.format("%.1f", avgBreakdownInterval) .. " " .. g_i18n:getText("rms_spec_hour_s"))
    else
        self.averageBreakdownsIntervalValue:setText("-")
    end

    local maintenanceCount = 0
    local sumMaintenanceInterval = 0
    local lastServiceHours = purchaseHours or 0
    for _, entry in ipairs(self.logDataAll) do
        if entry.type == RealisticMechanicalSystems.STATUS.MAINTENANCE and entry.isCompleted ~= false then
            local serviceHours = entry.conditionData ~= nil and tonumber(entry.conditionData.operatingHours) or nil
            if serviceHours ~= nil then
                sumMaintenanceInterval = sumMaintenanceInterval + math.max(serviceHours - lastServiceHours, 0)
                lastServiceHours = serviceHours
                maintenanceCount = maintenanceCount + 1
            end
        end
    end

    if maintenanceCount > 0 then
        averageMaintenanceInterval = math.max(sumMaintenanceInterval / maintenanceCount, 0)
        self.averageMaintenanceIntervalValue:setText(string.format("%.1f", averageMaintenanceInterval) .. " " .. g_i18n:getText("rms_spec_hour_s"))
    else
        self.averageMaintenanceIntervalValue:setText("-")
    end

    self.logTable:setDataSource(self)
    self.logTable:setDelegate(self)
    self.logTable:reloadData()

    if #self.logData > 0 then
        if self.selectedLogIndex == nil or self.selectedLogIndex > #self.logData then
            self.selectedLogIndex = 1
        end
        self.logTable:setSelectedItem(1, self.selectedLogIndex, false, false)
    else
        self.selectedLogIndex = nil
    end

    self:updateSelectedEntryDetails()

    local isEmpty = #self.logData == 0
    self.logTable:setVisible(not isEmpty)
    self.emptylogText:setVisible(isEmpty)
end

---Returns the number of visible log entries
-- @param table list list element
-- @param integer section section index
-- @return integer count number of rows
function RMS_MaintenanceLogDialog:getNumberOfItemsInSection(list, section)
    if list == self.detailPartsTable then
        return math.ceil(#self.detailLogItems / 2)
    end

    return #self.logData
end

---Fills one log row with its date, hours, colour coded type, description and price
-- @param table list list element
-- @param integer section section index
-- @param integer index row index
-- @param table cell cell element
function RMS_MaintenanceLogDialog:populateCellForItemInSection(list, section, index, cell)
    if list == self.detailPartsTable then
        RMS_Utils.populateTwoColumnTextRow(
            self.detailLogItems,
            index,
            cell,
            "detailPartLeft",
            "detailPartRight",
            "detailPartRightBullet"
        )
        return
    end

    local entryIndex = #self.logData - index + 1
    local entry = self.logData[entryIndex]
    if entry == nil then return end

    local typeText, color, iconSliceId, iconStyle = getLogTypePresentation(entry)
    local operatingHours = entry.conditionData ~= nil and tonumber(entry.conditionData.operatingHours) or 0
    local iconProfiles = LOG_ICON_PROFILES[iconStyle] or LOG_ICON_PROFILES.square

    local typeIcon = cell:getAttribute("logTypeIcon")
    typeIcon:applyProfile(iconProfiles.row)
    typeIcon:setImageSlice(nil, iconSliceId)
    typeIcon:setImageColor(nil, unpack(color))
    cell:getAttribute("logDate"):setText(formatLogDate(entry))
    cell:getAttribute("logHours"):setText(string.format("%.1f %s", operatingHours, g_i18n:getText("rms_spec_hour_s")))
    cell:getAttribute("logType"):setText(typeText)
    cell:getAttribute("logType"):setTextColor(unpack(color))
    cell:getAttribute("logDescription"):setText(getLogDescription(entry))
    cell:getAttribute("logPrice"):setText(g_i18n:formatMoney(entry.price or 0, 0, true, false))
end

---Closes the dialog
function RMS_MaintenanceLogDialog:onClickBack()
    self:close()
end

---Selects a log row and refreshes the report button
-- @param table row clicked row
function RMS_MaintenanceLogDialog:onRowClick(row)
    if row == nil or row.indexInSection == nil then return end

    self.selectedLogIndex = row.indexInSection
    if self.logTable ~= nil then
        self.logTable:setSelectedItem(1, row.indexInSection, false, false)
    end
    self:updateSelectedEntryDetails()
end

---Keeps the dossier card synchronized with keyboard and controller list navigation
-- @param table list list element
-- @param integer section section index
-- @param integer index row index
function RMS_MaintenanceLogDialog:onListSelectionChanged(list, section, index)
    if list ~= self.logTable or section ~= 1 or index == nil then
        return
    end

    self.selectedLogIndex = index
    self:updateSelectedEntryDetails()
end

---Opens the report of the selected entry, or tells the player there is none
function RMS_MaintenanceLogDialog:onClickShowReport()
    local entry = self:getSelectedLogEntry()
    if entry ~= nil and RealisticMechanicalSystems.getIsLogEntryHasReport(entry) then
        RMS_ReportDialog.show(self.vehicle, entry)
        return
    end

    InfoDialog.show(g_i18n:getText("rms_ws_no_report_message"))
end

---Selects the technical record tab in the maintenance log shell
function RMS_MaintenanceLogDialog:onCreate()
    RMS_Utils.mirrorSelectionToChildren(self.logTechnicalTab)
    self.logTechnicalTab:setSelected(true)
end

---Subscribes to balance changes while the dialog is open
function RMS_MaintenanceLogDialog:onOpen()
    RMS_MaintenanceLogDialog:superClass().onOpen(self)
    g_messageCenter:subscribe(MessageType.MONEY_CHANGED, self.updateScreen, self)
end

---Releases the displayed vehicle and dialog subscriptions
function RMS_MaintenanceLogDialog:onClose()
    self.vehicle = nil
    self.logData = nil
    self.logDataAll = nil
    self.selectedLogIndex = nil
    g_messageCenter:unsubscribeAll(self)

    RMS_MaintenanceLogDialog:superClass().onClose(self)
end
