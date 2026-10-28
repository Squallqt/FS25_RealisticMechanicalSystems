-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---Field inspection dialog and its findings
RMS_InspectionDialog = {}
RMS_InspectionDialog.INSTANCE = nil

local RMS_InspectionDialog_mt = Class(RMS_InspectionDialog, MessageDialog)
local modDirectory = g_currentModDirectory
local TEXT_COLOR = RMS_Utils.COLOR.TEXT

local TARGET_TO_SECTION = {
    engineOil = "technicalFluidsData",
    coolant = "technicalFluidsData",
    hydraulicFluid = "technicalFluidsData",
    transmissionOil = "technicalFluidsData",
    radiator = "fieldCareData",
    airFilter = "fieldCareData",
    lubrication = "fieldCareData"
}

local FLUID_ROWS = {
    { titleKey = "rms_inspection_engine_oil", circuit = "engineOil", icon = "rms_workshopFluidIconEngineOil" },
    { titleKey = "rms_inspection_coolant", circuit = "coolant", icon = "rms_workshopFluidIconCoolant" },
    { titleKey = "rms_inspection_hydraulic_fluid", circuit = "hydraulicFluid", icon = "rms_workshopFluidIconHydraulicFluid" },
    { titleKey = "rms_inspection_transmission_oil", circuit = "transmissionOil", icon = "rms_workshopFluidIconTransmissionOil" }
}

local STATUS_PRIORITY = {
    rms_inspection_ok = 0,
    rms_inspection_status_slightly_low = 1,
    rms_inspection_status_slight_moisture = 1,
    rms_inspection_status_slightly_dirty = 1,
    rms_inspection_status_slightly_dry = 1,
    rms_inspection_status_change_overdue = 1,
    rms_inspection_status_low = 2,
    rms_inspection_status_seepage = 2,
    rms_inspection_status_dirty = 2,
    rms_inspection_status_dry = 2,
    rms_inspection_status_change_long_overdue = 2,
    rms_inspection_status_very_low = 3,
    rms_inspection_status_active_leak = 3,
    rms_inspection_status_heavily_clogged = 3,
    rms_inspection_status_very_dry = 3,
    rms_inspection_status_replacement_due = 3,
    rms_inspection_status_critically_low = 4,
    rms_inspection_status_severe_leak = 4,
    rms_inspection_status_critically_clogged = 4,
    rms_inspection_status_critically_dry = 4,
    rms_inspection_status_not_required = 0
}

local AIR_FILTER_STAGE_STATUS = {
    "rms_inspection_status_slightly_dirty",
    "rms_inspection_status_dirty",
    "rms_inspection_status_heavily_clogged"
}

local FIELD_CARE_ICONS = {
    rms_inspection_air_filter = "rms_workshopFluidIconAirFilter",
    rms_inspection_radiator = "rms_workshopFluidIconRadiator",
    rms_inspection_lubrication_level = "rms_workshopFluidIconLubrication"
}

---Localizes a value when it is an rms_ key
local function getLocalizedText(value)
    if value == nil then
        return ""
    end

    if type(value) == "string" and string.sub(value, 1, 4) == "rms_" then
        return g_i18n:getText(value)
    end

    return tostring(value)
end

---Returns the colour of a severity, as the dashboard telltales use it
local function getSeverityColor(priority)
    if priority >= 4 then
        return RMS_Breakdowns.COLORS.CRITICAL
    elseif priority >= 1 then
        return RMS_Breakdowns.COLORS.WARNING
    end

    return RMS_Utils.COLOR.HIGHLIGHT
end

---Returns the row colour from its status severity
local function getRowColor(row)
    if row ~= nil and row.statusKey == "rms_inspection_status_not_required" then
        return RMS_Breakdowns.COLORS.DEFAULT
    end

    return getSeverityColor(row ~= nil and STATUS_PRIORITY[row.statusKey or ""] or 0)
end

local GAUGE_PARTS = { "inspectionGaugeTrack", "inspectionGaugeZone", "inspectionGaugeMinMark", "inspectionGaugeMaxMark",
    "inspectionGaugeMinLabel", "inspectionGaugeMaxLabel" }

---Returns the worst status severity of the whole report
local function getWorstPriority(dialog)
    local worst = 0
    for _, rows in ipairs({dialog.technicalFluidsData, dialog.fieldCareData}) do
        for _, row in ipairs(rows or {}) do
            if row.statusKey ~= "rms_inspection_status_not_required" then
                worst = math.max(worst, STATUS_PRIORITY[row.statusKey or ""] or 0)
            end
        end
    end

    return worst
end

---Returns whether a warning exists outside the air filter row
local function hasWarningOutsideAirFilter(dialog)
    for _, rows in ipairs({dialog.technicalFluidsData, dialog.fieldCareData}) do
        for _, row in ipairs(rows or {}) do
            local priority = STATUS_PRIORITY[row.statusKey or ""] or 0
            if row.titleKey ~= "rms_inspection_air_filter" and priority >= 1 then
                return true
            end
        end
    end

    return false
end

---Sets the status of a row, the more severe one winning
local function setRowValue(rows, titleKey, statusKey)
    if rows == nil or titleKey == nil or statusKey == nil then
        return
    end

    for _, row in ipairs(rows) do
        if row.titleKey == titleKey then
            local newPriority = STATUS_PRIORITY[statusKey] or 0
            local currentPriority = STATUS_PRIORITY[row.statusKey or "rms_inspection_ok"] or 0

            if newPriority >= currentPriority then
                row.statusKey = statusKey
                row.value = getLocalizedText(statusKey)
            end

            return
        end
    end
end

---Appends a localized line to the findings, skipping duplicates
local function appendAdditionalLine(lines, textKey, ...)
    if lines == nil or textKey == nil or textKey == "" then
        return
    end

    local text = getLocalizedText(textKey)
    if select("#", ...) > 0 then
        text = string.format(text, ...)
    end
    if text == "" then
        return
    end

    for _, existing in ipairs(lines) do
        if existing == text then
            return
        end
    end

    table.insert(lines, text)
end

---Joins the findings into a bullet list
local function buildAdditionalText(lines)
    local formattedLines = {}
    for _, line in ipairs(lines or {}) do
        table.insert(formattedLines, "\194\183  " .. line)
    end

    return table.concat(formattedLines, "\n")
end

---Applies the findings of the active breakdown stages
local function applyBreakdownInspectionFindings(dialog, additionalLines)
    local vehicle = dialog.vehicle
    if vehicle == nil or vehicle.getActiveBreakdowns == nil then
        return
    end

    local activeBreakdowns = vehicle:getActiveBreakdowns() or {}
    local registry = RMS_Breakdowns.BreakdownRegistry or {}
    local targetMap = {
        engineOil = "rms_inspection_engine_oil",
        coolant = "rms_inspection_coolant",
        hydraulicFluid = "rms_inspection_hydraulic_fluid",
        transmissionOil = "rms_inspection_transmission_oil",
        radiator = "rms_inspection_radiator",
        airFilter = "rms_inspection_air_filter",
        lubrication = "rms_inspection_lubrication_level"
    }

    local hasUnidentified = false
    for breakdownId, breakdown in pairs(activeBreakdowns) do
        local registryEntry = registry[breakdownId]
        if registryEntry ~= nil and registryEntry.stages ~= nil then
            local stageData = registryEntry.stages[breakdown.stage]
            local findings = stageData ~= nil and stageData.inspection ~= nil and RMS_Utils.getBranchItems(stageData.inspection, breakdown) or nil

            if findings ~= nil and #findings > 0 and not breakdown.isVisible and registryEntry.isSelectable
                and RMS_Consumables.getFilterOfBreakdown(breakdownId) == nil then
                hasUnidentified = true
            end
            if findings ~= nil then
                for _, finding in ipairs(findings) do
                    if finding.target ~= nil and finding.status ~= nil then
                        local titleKey = targetMap[RMS_Fluids.getSumpCircuit(vehicle, finding.target)]
                        local sectionKey = TARGET_TO_SECTION[finding.target]
                        if titleKey ~= nil and sectionKey ~= nil then
                            setRowValue(dialog[sectionKey], titleKey, finding.status)
                        end
                    end

                    appendAdditionalLine(additionalLines, finding.additional)
                end
            end
        end
    end
    if hasUnidentified then
        appendAdditionalLine(additionalLines, "rms_inspection_hint_unidentified")
    end
end

---Rates the radiator and air filter clogging
local function applyCloggingInspectionFindings(dialog, additionalLines)
    local vehicle = dialog.vehicle
    local spec = vehicle ~= nil and vehicle.spec_RealisticMechanicalSystems or nil
    if spec == nil then
        return
    end

    if spec.isVehicleNeedBlowOut == false then
        return
    end

    local radiatorClogging = math.clamp(tonumber(spec.radiatorClogging) or 0, 0, 1)
    if radiatorClogging > 0.15 then
        local statusKey
        if radiatorClogging >= 0.85 then
            statusKey = "rms_inspection_status_critically_clogged"
            appendAdditionalLine(additionalLines, "rms_inspection_hint_radiator_clogging_stage4")
        elseif radiatorClogging >= 0.60 then
            statusKey = "rms_inspection_status_heavily_clogged"
            appendAdditionalLine(additionalLines, "rms_inspection_hint_radiator_clogging_stage3")
        elseif radiatorClogging >= 0.35 then
            statusKey = "rms_inspection_status_dirty"
            appendAdditionalLine(additionalLines, "rms_inspection_hint_radiator_clogging_stage2")
        else
            statusKey = "rms_inspection_status_slightly_dirty"
            appendAdditionalLine(additionalLines, "rms_inspection_hint_radiator_clogging_stage1")
        end

        setRowValue(dialog.fieldCareData, "rms_inspection_radiator", statusKey)
    end

    local airFilterStage = RMS_Consumables.getAirFilterBlowOutStage(spec)
    if airFilterStage > 0 then
        appendAdditionalLine(additionalLines, "rms_inspection_hint_air_filter_clogging_stage" .. airFilterStage)
        setRowValue(dialog.fieldCareData, "rms_inspection_air_filter", AIR_FILTER_STAGE_STATUS[airFilterStage])
    end
    if radiatorClogging >= 0.35 or airFilterStage >= 2 then
        appendAdditionalLine(additionalLines, "rms_air_blower_action")
    end

    if RMS_Consumables.getIsAirFilterWornOut(spec) then
        dialog.isAirFilterReplacementDue = true
        appendAdditionalLine(additionalLines, "rms_inspection_hint_air_filter_blowout_limit",
            RMS_Utils.formatAirFilterServiceHours(dialog.vehicle))
        setRowValue(dialog.fieldCareData, "rms_inspection_air_filter", "rms_inspection_status_replacement_due")
    end
end

---Rates the lubrication level
local function applyLubricationInspectionFindings(dialog, additionalLines)
    local vehicle = dialog.vehicle
    local spec = vehicle ~= nil and vehicle.spec_RealisticMechanicalSystems or nil
    if spec == nil or spec.isVehicleNeedLubricate == false then
        return
    end

    local lubricationLevel = math.clamp(tonumber(spec.lubricationLevel) or 0, 0, 1)
    local statusKey = nil

    local C = RMS_Config.FIELD_CARE

    if lubricationLevel <= C.LUBRICATION_CRITICALLY_DRY_THRESHOLD then
        statusKey = "rms_inspection_status_critically_dry"
        appendAdditionalLine(additionalLines, "rms_inspection_hint_lubrication_stage4")
    elseif lubricationLevel <= C.LUBRICATION_VERY_DRY_THRESHOLD then
        statusKey = "rms_inspection_status_very_dry"
        appendAdditionalLine(additionalLines, "rms_inspection_hint_lubrication_stage3")
    elseif lubricationLevel <= C.LUBRICATION_DRY_THRESHOLD then
        statusKey = "rms_inspection_status_dry"
        appendAdditionalLine(additionalLines, "rms_inspection_hint_lubrication_stage2")
    elseif lubricationLevel <= C.LUBRICATION_WARNING_THRESHOLD then
        statusKey = "rms_inspection_status_slightly_dry"
        appendAdditionalLine(additionalLines, "rms_inspection_hint_lubrication_stage1")
    end

    if statusKey ~= nil then
        setRowValue(dialog.fieldCareData, "rms_inspection_lubrication_level", statusKey)
    end
end

---Reads the level of every fluid circuit the report shows
local function applyFluidLevelInspectionFindings(dialog, additionalLines)
    local vehicle = dialog.vehicle
    local spec = vehicle ~= nil and vehicle.spec_RealisticMechanicalSystems or nil
    if spec == nil then
        return
    end

    local C = RMS_Config.FLUIDS
    local lowCount = 0

    for _, row in ipairs(dialog.technicalFluidsData) do
        local level = RMS_Fluids.getLevel(vehicle, row.circuit)
        local statusKey = nil

        if level <= C.LEVEL_CRITICALLY_LOW then
            statusKey = "rms_inspection_status_critically_low"
        elseif level <= C.LEVEL_VERY_LOW then
            statusKey = "rms_inspection_status_very_low"
        elseif level <= C.LEVEL_LOW then
            statusKey = "rms_inspection_status_low"
        elseif level < C.LEVEL_MIN_MARK then
            statusKey = "rms_inspection_status_slightly_low"
        end

        row.level = level

        if statusKey ~= nil then
            setRowValue(dialog.technicalFluidsData, row.titleKey, statusKey)
            lowCount = lowCount + 1
        end
    end

    if lowCount > 0 then
        appendAdditionalLine(additionalLines, lowCount > 1 and "rms_inspection_hint_fluid_levels_low" or "rms_inspection_hint_fluid_level_low")
    end
end

---Marks the fluids whose service clock ran past its interval
local function applyServiceClockInspectionFindings(dialog, additionalLines)
    local vehicle = dialog.vehicle
    local spec = vehicle.spec_RealisticMechanicalSystems
    local threshold = RMS_Config.CORE.SERVICE_EXPIRED_THRESHOLD

    for _, clock in ipairs(vehicle:getServiceClocks()) do
        local level = spec[clock.levelKey]
        if level < threshold then
            local statusKey = level < threshold / 2 and "rms_inspection_status_change_long_overdue"
                or "rms_inspection_status_change_overdue"
            for _, row in ipairs(dialog.technicalFluidsData) do
                for _, circuit in ipairs(clock.circuits) do
                    if row.circuit == circuit then
                        setRowValue(dialog.technicalFluidsData, row.titleKey, statusKey)
                    end
                end
            end
            appendAdditionalLine(additionalLines, "rms_inspection_hint_service_" .. clock.key)
        end
    end
end

---Writes the machine name, hours, odometer and next service
local function updateIdentity(dialog)
    local vehicle = dialog.vehicle
    local hoursText = RMS_Utils.formatHours(vehicle:getFormattedOperatingTime())
    local serviceText = RMS_Utils.formatServiceDue(vehicle, vehicle:getServiceSchedule())

    local odometerText = "ODO " .. RMS_Utils.formatOdometerKilometers(RMS_Utils.getOdometerKilometers(vehicle))
    dialog.identityElement:setText(string.format("%s  \194\183  %s  \194\183  %s  \194\183  %s", vehicle:getFullName(), hoursText, odometerText, serviceText))

    local textWidth = math.max(dialog.dialogTitleElement.size[1], dialog.identityElement.size[1])
    dialog.headerTextLayout:setSize(textWidth, nil)
    dialog.headerTextLayout:invalidateLayout()
    dialog.headerLayout:invalidateLayout()
end

---Writes the go or no go the whole report comes down to
local function updateVerdict(dialog, additionalLines)
    local worst = getWorstPriority(dialog)
    local name, color

    if worst >= 4 then
        name = "stop"
    elseif worst >= 1 then
        name = "watch"
    else
        name = "ok"
    end

    color = getSeverityColor(worst)
    local message = g_i18n:getText("rms_inspection_verdict_" .. name .. "_message")
    if name == "watch"
        and dialog.isAirFilterReplacementDue == true
        and #additionalLines == 1
        and not hasWarningOutsideAirFilter(dialog) then
        message = string.format(g_i18n:getText("rms_inspection_verdict_air_filter_service_message"),
            RMS_Utils.formatAirFilterServiceHours(dialog.vehicle))
    end

    dialog.verdictTitle:setText(g_i18n:getText("rms_inspection_verdict_" .. name .. "_title"))
    dialog.verdictMessage:setText(message)
    dialog.verdictBadgeText:setText(worst == 0 and "OK" or "!")
    dialog.verdictTitle:setTextColor(unpack(color))
    dialog.verdictBadge.color = {color[1], color[2], color[3], color[4]}
end

---Loads the dialog layout and stores the shared instance
function RMS_InspectionDialog.register()
    local dialog = RMS_InspectionDialog.new()
    g_gui:loadGui(modDirectory .. "gui/RMS_InspectionDialog.xml", "RMS_InspectionDialog", dialog)
    RMS_InspectionDialog.INSTANCE = dialog
end

---Create instance of RMS_InspectionDialog
-- @param table? target target
-- @param table? customMt custom metatable
-- @return table dialog instance of class RMS_InspectionDialog
function RMS_InspectionDialog.new(target, customMt)
    local dialog = MessageDialog.new(target, customMt or RMS_InspectionDialog_mt)
    dialog.vehicle = nil
    dialog.technicalFluidsData = {}
    dialog.fieldCareData = {}
    dialog.isAirFilterReplacementDue = false
    return dialog
end

---Opens the dialog on a vehicle
-- @param table vehicle vehicle
function RMS_InspectionDialog.show(vehicle)
    if RMS_InspectionDialog.INSTANCE == nil then RMS_InspectionDialog.register() end
    if vehicle == nil or vehicle.spec_RealisticMechanicalSystems == nil then return end
    
    local dialog = RMS_InspectionDialog.INSTANCE
    dialog.vehicle = vehicle
    dialog:updateScreen()
    g_gui:showDialog("RMS_InspectionDialog")
end

---Builds a card for each oil circuit of a machine
-- @param table vehicle vehicle
-- @return table rows fluid rows, all fine
function RMS_InspectionDialog.buildFluidRows(vehicle)
    local rows = {}
    for _, fluidRow in ipairs(FLUID_ROWS) do
        if RMS_Fluids.hasCircuit(vehicle, fluidRow.circuit) then
            local title = g_i18n:getText(RMS_Fluids.getCircuitTextKey(vehicle, fluidRow.circuit, fluidRow.titleKey))
            table.insert(rows, {titleKey = fluidRow.titleKey, title = title, icon = fluidRow.icon,
                circuit = fluidRow.circuit, statusKey = "rms_inspection_ok", value = g_i18n:getText("rms_inspection_ok")})
        end
    end
    return rows
end

---Builds the cleaning and lubrication rows.
-- @param table vehicle vehicle
-- @return table rows card rows, all fine
function RMS_InspectionDialog.buildFieldCareRows(vehicle)
    local titleKeys = {}
    if not vehicle.spec_RealisticMechanicalSystems.isElectricVehicle then
        table.insert(titleKeys, "rms_inspection_air_filter")
    end
    table.insert(titleKeys, "rms_inspection_radiator")
    table.insert(titleKeys, "rms_inspection_lubrication_level")

    local rows = {}
    for _, titleKey in ipairs(titleKeys) do
        table.insert(rows, {titleKey = titleKey, title = g_i18n:getText(titleKey), icon = FIELD_CARE_ICONS[titleKey],
            statusKey = "rms_inspection_ok", value = g_i18n:getText("rms_inspection_ok")})
    end
    return rows
end

---Resets every section, then applies all the findings
function RMS_InspectionDialog:updateScreen()
    if self.vehicle == nil then return end
    
    self.dialogTitleElement:setText(g_i18n:getText("rms_inspection_dialog_title"))

    local spec = self.vehicle.spec_RealisticMechanicalSystems

    self.technicalFluidsData = RMS_InspectionDialog.buildFluidRows(self.vehicle)
    self.fieldCareData = RMS_InspectionDialog.buildFieldCareRows(self.vehicle)

    if spec.isVehicleNeedBlowOut == false then
        setRowValue(self.fieldCareData, "rms_inspection_radiator", "rms_inspection_status_not_required")
        setRowValue(self.fieldCareData, "rms_inspection_air_filter", "rms_inspection_status_not_required")
    end

    if spec.isVehicleNeedLubricate == false then
        setRowValue(self.fieldCareData, "rms_inspection_lubrication_level", "rms_inspection_status_not_required")
    end

    local additionalLines = {}
    self.isAirFilterReplacementDue = false

    applyFluidLevelInspectionFindings(self, additionalLines)
    applyServiceClockInspectionFindings(self, additionalLines)
    applyBreakdownInspectionFindings(self, additionalLines)
    applyCloggingInspectionFindings(self, additionalLines)
    applyLubricationInspectionFindings(self, additionalLines)

    local hasAdditionalFindings = #additionalLines > 0
    self.additionalText:setText(buildAdditionalText(additionalLines))
    self.additionalScroll:setVisible(hasAdditionalFindings)
    self.additionalSliderBox:setVisible(hasAdditionalFindings)
    self.noFindingsText:setText(g_i18n:getText("rms_inspection_no_suspicious_symptoms"))
    self.noFindingsText:setVisible(not hasAdditionalFindings)

    self.technicalFluidsList:setDataSource(self)
    self.technicalFluidsList:setDelegate(self)
    self.technicalFluidsList:reloadData()
    self.technicalFluidsCard:setSize(nil, self.technicalFluidsList.contentSize + self.technicalFluidsCardPadding)

    self.fieldCareList:setDataSource(self)
    self.fieldCareList:setDelegate(self)
    self.fieldCareList:reloadData()
    self.fieldCareCard:setSize(nil, self.fieldCareList.contentSize + self.fieldCareCardPadding)

    updateIdentity(self)
    updateVerdict(self, additionalLines)
end

---Returns the row table backing a list element
local function getListData(self, list)
    if list == self.technicalFluidsList then
        return self.technicalFluidsData
    elseif list == self.fieldCareList then
        return self.fieldCareData
    end

    return nil
end

---Returns the row count of the requested section
-- @param table list list element
-- @param integer section section index
-- @return integer count number of rows
function RMS_InspectionDialog:getNumberOfItemsInSection(list, section)
    local data = getListData(self, list)
    return data ~= nil and #data or 0
end

---Fills one inspection row
-- @param table list list element
-- @param integer section section index
-- @param integer index row index
-- @param table cell cell element
function RMS_InspectionDialog:populateCellForItemInSection(list, section, index, cell)
    local data = getListData(self, list)
    local row = data ~= nil and data[index] or nil
    if row == nil then
        return
    end

    cell:getAttribute("inspectionIcon"):applyProfile(row.icon, true)
    local titleElement = cell:getAttribute("inspectionTitle")
    if list == self.technicalFluidsList then
        titleElement:setText(row.title or "")
    else
        local valueElement = cell:getAttribute("inspectionValue")
        local valuePill = cell:getAttribute("inspectionValuePill")
        RMS_Utils.fitRowValue(titleElement, valuePill, valueElement, row.title or "", row.value or "")
        valueElement:setTextColor(unpack(getRowColor(row)))
    end
    titleElement:setTextColor(unpack(TEXT_COLOR))

    local gaugeTrack = cell:getAttribute("inspectionGaugeTrack")
    if gaugeTrack == nil then
        return
    end

    local level = tonumber(row.level)
    for _, name in ipairs(GAUGE_PARTS) do
        cell:getAttribute(name):setVisible(level ~= nil)
    end

    local gaugeFill, gaugeUnder = cell:getAttribute("inspectionGaugeFill"), cell:getAttribute("inspectionGaugeUnder")
    if level == nil then
        gaugeFill:setVisible(false)
        gaugeUnder:setVisible(false)
        return
    end
    RMS_Utils.setLevelGauge(gaugeFill, gaugeUnder, gaugeTrack.size[1], level)
end

---Caches the margin each card keeps around its rows
function RMS_InspectionDialog:onCreate()
    self.technicalFluidsCardPadding = self.technicalFluidsCard.size[2] - self.technicalFluidsList.size[2]
    self.fieldCareCardPadding = self.fieldCareCard.size[2] - self.fieldCareList.size[2]
end

---
function RMS_InspectionDialog:onOpen()
    RMS_InspectionDialog:superClass().onOpen(self)
end

---Clears the inspected vehicle
function RMS_InspectionDialog:onClose()
    self.vehicle = nil
    RMS_InspectionDialog:superClass().onClose(self)
end

---Closes the dialog
function RMS_InspectionDialog:onClickBack()
    self:close()
end
