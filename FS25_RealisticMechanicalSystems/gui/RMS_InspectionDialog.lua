-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---Check on foot: fluids, cleaning, greasing and a verdict
RMS_InspectionDialog = {}

local RMS_InspectionDialog_mt = Class(RMS_InspectionDialog, MessageDialog)

local OK, NOT_REQUIRED = "rms_inspection_ok", "rms_inspection_status_not_required"

-- statuses by severity: watch, worse, serious, stop
local SEVERITY = {}
for severity, statuses in ipairs({
    { "rms_inspection_status_slightly_low", "rms_inspection_status_slight_moisture", "rms_inspection_status_slightly_dirty",
        "rms_inspection_status_grease_due", "rms_inspection_status_change_overdue" },
    { "rms_inspection_status_low", "rms_inspection_status_seepage", "rms_inspection_status_dirty", "rms_inspection_status_grease_late",
        "rms_inspection_status_change_long_overdue" },
    { "rms_inspection_status_very_low", "rms_inspection_status_active_leak", "rms_inspection_status_heavily_clogged",
        "rms_inspection_status_replacement_due" },
    { "rms_inspection_status_critically_low", "rms_inspection_status_severe_leak", "rms_inspection_status_critically_clogged" }
}) do
    for _, status in ipairs(statuses) do
        SEVERITY[status] = severity
    end
end

-- cleaning and greasing points; an air filter on fuel only
local CARE_POINTS = {
    { target = "airFilter", titleKey = "rms_inspection_air_filter", icon = "rms_workshopFluidIconAirFilter", isFuelled = true },
    { target = "radiator", titleKey = "rms_inspection_radiator", icon = "rms_workshopFluidIconRadiator" },
    { target = "lubrication", titleKey = "rms_grease_hud_title", icon = "rms_workshopFluidIconLubrication" }
}

local AIR_FILTER_STATUS = { "rms_inspection_status_slightly_dirty", "rms_inspection_status_dirty", "rms_inspection_status_heavily_clogged" }

local GAUGE_PARTS = { "inspectionGaugeTrack", "inspectionGaugeZone", "inspectionGaugeMinMark", "inspectionGaugeMaxMark",
    "inspectionGaugeMinLabel", "inspectionGaugeMaxLabel" }

local function getSeverity(status)
    return SEVERITY[status] or 0
end

local function getSeverityColor(severity)
    if severity >= 4 then
        return RMS_Breakdowns.COLORS.CRITICAL
    elseif severity >= 1 then
        return RMS_Breakdowns.COLORS.WARNING
    end
    return RMS_Utils.COLOR.HIGHLIGHT
end

local function newRow(titleKey, title, icon)
    return { titleKey = titleKey, title = title, icon = icon, statusKey = OK, value = g_i18n:getText(OK) }
end

---Builds a row for each fluid circuit of a machine, at its level
function RMS_InspectionDialog.buildFluidRows(vehicle)
    local rows = {}
    for _, circuit in ipairs(RMS_Fluids.CIRCUIT_ORDER) do
        if RMS_Fluids.hasCircuit(vehicle, circuit) then
            local row = newRow(RMS_Fluids.getCircuitTextKey(nil, circuit), g_i18n:getText(RMS_Fluids.getCircuitTextKey(vehicle, circuit)),
                RMS_Fluids.CIRCUITS[circuit].icon)
            row.circuit, row.target, row.level = circuit, circuit, RMS_Fluids.getLevel(vehicle, circuit)
            table.insert(rows, row)
        end
    end
    return rows
end

---Builds a row for each cleaning and greasing point of a machine
function RMS_InspectionDialog.buildFieldCareRows(vehicle)
    local isElectric = vehicle.spec_RealisticMechanicalSystems.isElectricVehicle
    local rows = {}
    for _, point in ipairs(CARE_POINTS) do
        if not (point.isFuelled and isElectric) then
            local row = newRow(point.titleKey, g_i18n:getText(point.titleKey), point.icon)
            row.target = point.target
            table.insert(rows, row)
        end
    end
    return rows
end

---What the check finds: a status per point, lines under them
local Report = {}
local Report_mt = { __index = Report }

---Starts a report on the rows of the dialog
function Report.new(vehicle, fluidRows, careRows)
    local self = setmetatable({ vehicle = vehicle, spec = vehicle.spec_RealisticMechanicalSystems, rows = {}, lines = {} }, Report_mt)
    for _, rows in ipairs({ fluidRows, careRows }) do
        for _, row in ipairs(rows) do
            self.rows[row.target] = row
        end
    end
    return self
end

---Gives a point a status, unless it already has a more severe one
function Report:mark(target, status)
    local row = self.rows[target]
    if row ~= nil and getSeverity(status) >= getSeverity(row.statusKey) then
        row.statusKey, row.value = status, g_i18n:getText(status)
    end
end

---Writes a line under the points, once
function Report:note(textKey, ...)
    local text = select("#", ...) > 0 and string.format(g_i18n:getText(textKey), ...) or g_i18n:getText(textKey)
    for _, line in ipairs(self.lines) do
        if line == text then
            return
        end
    end
    table.insert(self.lines, text)
end

---Reads the level of every fluid against the marks of its gauge
function Report:readFluidLevels(fluidRows)
    local C = RMS_Config.FLUIDS
    local lowCount = 0
    for _, row in ipairs(fluidRows) do
        local level = row.level
        local status
        if level <= C.LEVEL_CRITICALLY_LOW then
            status = "rms_inspection_status_critically_low"
        elseif level <= C.LEVEL_VERY_LOW then
            status = "rms_inspection_status_very_low"
        elseif level <= C.LEVEL_LOW then
            status = "rms_inspection_status_low"
        elseif level < C.LEVEL_MIN_MARK then
            status = "rms_inspection_status_slightly_low"
        end
        if status ~= nil then
            self:mark(row.target, status)
            lowCount = lowCount + 1
        end
    end
    if lowCount > 1 then
        self:note("rms_inspection_hint_fluid_levels_low")
    elseif lowCount == 1 then
        self:note("rms_inspection_hint_fluid_level_low")
    end
end

---Marks the fluids whose service clock ran past its interval
function Report:readServiceClocks()
    local threshold = RMS_Config.CORE.SERVICE_EXPIRED_THRESHOLD
    for _, clock in ipairs(self.vehicle:getServiceClocks()) do
        local level = self.spec[clock.levelKey]
        if level < threshold then
            for _, circuit in ipairs(clock.circuits) do
                self:mark(circuit, level < threshold / 2 and "rms_inspection_status_change_long_overdue" or "rms_inspection_status_change_overdue")
            end
            self:note("rms_inspection_hint_service_" .. clock.key)
        end
    end
end

---Reads what the stage of each fault shows on foot
function Report:readBreakdowns()
    local hasUnidentified = false
    for id, breakdown in pairs(self.vehicle:getActiveBreakdowns()) do
        local definition = RMS_Breakdowns.BreakdownRegistry[id]
        local stage = definition ~= nil and definition.stages ~= nil and definition.stages[breakdown.stage] or nil
        local findings = stage ~= nil and stage.inspection ~= nil and RMS_Utils.getBranchItems(stage.inspection, breakdown) or {}
        -- a fault the workshop has not named; a filter has its own row
        if #findings > 0 and not breakdown.isVisible and definition.isSelectable and RMS_Consumables.getFilterOfBreakdown(id) == nil then
            hasUnidentified = true
        end
        for _, finding in ipairs(findings) do
            if finding.target ~= nil and finding.status ~= nil then
                self:mark(RMS_Fluids.getSumpCircuit(self.vehicle, finding.target), finding.status)
            end
            if finding.additional ~= nil and finding.additional ~= "" then
                local variant = RMS_Utils.getBreakdownNameVariant(self.vehicle, definition)
                self:note(variant ~= nil and finding.variantAdditional ~= nil and finding.variantAdditional[variant] or finding.additional)
            end
        end
    end
    if hasUnidentified then
        self:note("rms_inspection_hint_unidentified")
    end
end

---Rates the radiator and the air filter a blow-out cleans
function Report:readClogging()
    if self.spec.isVehicleNeedBlowOut == false then
        return
    end

    local clogging = math.clamp(tonumber(self.spec.radiatorClogging) or 0, 0, 1)
    if clogging >= 0.85 then
        self:mark("radiator", "rms_inspection_status_critically_clogged")
        self:note("rms_inspection_hint_radiator_clogging_stage4")
    elseif clogging >= 0.60 then
        self:mark("radiator", "rms_inspection_status_heavily_clogged")
        self:note("rms_inspection_hint_radiator_clogging_stage3")
    elseif clogging >= 0.35 then
        self:mark("radiator", "rms_inspection_status_dirty")
        self:note("rms_inspection_hint_radiator_clogging_stage2")
    elseif clogging > 0.15 then
        self:mark("radiator", "rms_inspection_status_slightly_dirty")
        self:note("rms_inspection_hint_radiator_clogging_stage1")
    end

    local filterStage = RMS_Consumables.getAirFilterBlowOutStage(self.spec)
    if filterStage > 0 then
        self:note("rms_inspection_hint_air_filter_clogging_stage" .. filterStage)
        self:mark("airFilter", AIR_FILTER_STATUS[filterStage])
    end
    if clogging >= 0.35 or filterStage >= 2 then
        self:note("rms_air_blower_action")
    end
    if RMS_Consumables.getIsAirFilterWornOut(self.spec) then
        self.isAirFilterReplacementDue = true
        self:note("rms_inspection_hint_air_filter_blowout_limit", RMS_Utils.formatAirFilterServiceHours(self.vehicle))
        self:mark("airFilter", "rms_inspection_status_replacement_due")
    end
end

---Rates the greasing, late once its delay has begun
function Report:readLubrication()
    if not self.spec.isVehicleNeedLubricate then
        return
    end

    local total, duePoints = RMS_Greasing.getTotalPoints(self.vehicle), RMS_Greasing.getDuePoints(self.vehicle)
    self.rows.lubrication.greasing = { total = total, greased = total - duePoints }
    if duePoints == 0 then
        return
    end
    self:mark("lubrication", RMS_Greasing.getStatus(self.vehicle) == "late" and "rms_inspection_status_grease_late"
        or "rms_inspection_status_grease_due")
    self:note("rms_inspection_hint_grease_due", duePoints)
end

---Returns the worst severity, and a warning off the air filter
function Report:getWorst()
    local worst, isOtherWarned = 0, false
    for target, row in pairs(self.rows) do
        local severity = getSeverity(row.statusKey)
        worst = math.max(worst, severity)
        isOtherWarned = isOtherWarned or target ~= "airFilter" and severity >= 1
    end
    return worst, isOtherWarned
end

---Creates the dialog
function RMS_InspectionDialog.new(target, customMt)
    local self = MessageDialog.new(target, customMt or RMS_InspectionDialog_mt)
    self.technicalFluidsData, self.fieldCareData = {}, {}
    return self
end

---Wires both lists and keeps the margin each card has around its rows
function RMS_InspectionDialog:onCreate()
    RMS_InspectionDialog:superClass().onCreate(self)
    for _, list in ipairs({ self.technicalFluidsList, self.fieldCareList }) do
        list:setDataSource(self)
        list:setDelegate(self)
    end
    self.technicalFluidsCardPadding = self.technicalFluidsCard.size[2] - self.technicalFluidsList.size[2]
    self.fieldCareCardPadding = self.fieldCareCard.size[2] - self.fieldCareList.size[2]
end

---Opens the check on a machine
function RMS_InspectionDialog.show(vehicle)
    local self = RMS_InspectionDialog.INSTANCE
    self.vehicle = vehicle
    self:updateScreen()
    g_gui:showDialog("RMS_InspectionDialog")
end

---Checks the machine, then writes its points, lines and verdict
function RMS_InspectionDialog:updateScreen()
    local vehicle = self.vehicle
    local spec = vehicle.spec_RealisticMechanicalSystems
    self.technicalFluidsData = RMS_InspectionDialog.buildFluidRows(vehicle)
    self.fieldCareData = RMS_InspectionDialog.buildFieldCareRows(vehicle)

    local report = Report.new(vehicle, self.technicalFluidsData, self.fieldCareData)
    if spec.isVehicleNeedBlowOut == false then
        report:mark("radiator", NOT_REQUIRED)
        report:mark("airFilter", NOT_REQUIRED)
    end
    if spec.isVehicleNeedLubricate == false then
        report:mark("lubrication", NOT_REQUIRED)
    end
    report:readFluidLevels(self.technicalFluidsData)
    report:readServiceClocks()
    report:readBreakdowns()
    report:readClogging()
    report:readLubrication()

    local bullets = {}
    for _, line in ipairs(report.lines) do
        table.insert(bullets, "\194\183  " .. line)
    end
    local hasLines = #bullets > 0
    self.additionalText:setText(table.concat(bullets, "\n"))
    self.additionalScroll:setVisible(hasLines)
    self.additionalSliderBox:setVisible(hasLines)
    self.noFindingsText:setVisible(not hasLines)

    self.technicalFluidsList:reloadData()
    self.technicalFluidsCard:setSize(nil, self.technicalFluidsList.contentSize + self.technicalFluidsCardPadding)
    RMS_Utils.reloadListTemplates(self.fieldCareList)
    self.fieldCareCard:setSize(nil, self.fieldCareList.contentSize + self.fieldCareCardPadding)

    self:updateIdentity()
    self:updateVerdict(report)
end

---Writes the machine, its hours, its odometer and its next service
function RMS_InspectionDialog:updateIdentity()
    local vehicle = self.vehicle
    self.identityElement:setText(table.concat({ vehicle:getFullName(), RMS_Utils.formatHours(RMS_Utils.getHourMeter(vehicle)),
        "ODO " .. RMS_Utils.formatOdometerKilometers(RMS_Utils.getOdometerKilometers(vehicle)),
        RMS_Utils.formatServiceDue(vehicle, vehicle:getServiceSchedule()) }, "  \194\183  "))
    self.headerTextLayout:setSize(math.max(self.dialogTitleElement.size[1], self.identityElement.size[1]), nil)
    self.headerTextLayout:invalidateLayout()
    self.headerLayout:invalidateLayout()
end

---Writes the go or no go the check comes down to
function RMS_InspectionDialog:updateVerdict(report)
    local worst, isOtherWarned = report:getWorst()
    local name = worst >= 4 and "stop" or worst >= 1 and "watch" or "ok"
    local message = g_i18n:getText("rms_inspection_verdict_" .. name .. "_message")
    if name == "watch" and report.isAirFilterReplacementDue and #report.lines == 1 and not isOtherWarned then
        message = string.format(g_i18n:getText("rms_inspection_verdict_air_filter_service_message"),
            RMS_Utils.formatAirFilterServiceHours(self.vehicle))
    end
    local color = getSeverityColor(worst)
    self.verdictTitle:setText(g_i18n:getText("rms_inspection_verdict_" .. name .. "_title"))
    self.verdictTitle:setTextColor(unpack(color))
    self.verdictMessage:setText(message)
    self.verdictBadgeText:setText(worst == 0 and "OK" or "!")
    self.verdictBadge.color = { unpack(color) }
end

---Number of rows of a list
function RMS_InspectionDialog:getNumberOfItemsInSection(list)
    return list == self.technicalFluidsList and #self.technicalFluidsData or #self.fieldCareData
end

---Writes a row: a fluid by its gauge, a care point by its status
function RMS_InspectionDialog:populateCellForItemInSection(list, _section, index, cell)
    local isFluid = list == self.technicalFluidsList
    local row = isFluid and self.technicalFluidsData[index] or self.fieldCareData[index]
    cell:getAttribute("inspectionIcon"):applyProfile(row.icon, true)
    local title = cell:getAttribute("inspectionTitle")
    title:setTextColor(unpack(RMS_Utils.COLOR.TEXT))
    if isFluid then
        title:setText(row.title)
        for _, name in ipairs(GAUGE_PARTS) do
            cell:getAttribute(name):setVisible(true)
        end
        RMS_Utils.setLevelGauge(cell:getAttribute("inspectionGaugeFill"), cell:getAttribute("inspectionGaugeUnder"),
            cell:getAttribute("inspectionGaugeTrack").size[1], row.level)
    else
        local value = cell:getAttribute("inspectionValue")
        RMS_Utils.fitRowValue(title, cell:getAttribute("inspectionValuePill"), value, row.title, row.value)
        local color = row.statusKey == NOT_REQUIRED and RMS_Breakdowns.COLORS.DEFAULT or getSeverityColor(getSeverity(row.statusKey))
        value:setTextColor(unpack(color))
        local greasing = row.greasing
        if greasing ~= nil then
            local count, segments = cell:getAttribute("inspectionCount"), cell:getAttribute("inspectionSegments")
            count:setText(string.format("%d / %d", greasing.greased, greasing.total))
            count:setPosition(title.position[1] + title:getTextWidth() + 8 * g_pixelSizeScaledX, count.position[2])
            segments.rmsGreasing = greasing
            segments.rmsRestColor = { color[1], color[2], color[3], 0.35 }
        end
    end
end

---Gives the greasing its own row, its gauge under the title
function RMS_InspectionDialog:getCellTypeForItemInSection(list, _section, index)
    if list == self.technicalFluidsList then
        return "technicalFluidsRowTemplate"
    end
    -- the list also asks for row 0, where a section header would go
    local row = self.fieldCareData[index]
    return row ~= nil and row.greasing ~= nil and "fieldCareGreasingRowTemplate" or "fieldCareRowTemplate"
end

---Draws one segment per grease point of the machine, the greased lit
function RMS_InspectionDialog:onDrawGreasingSegments(element)
    local greasing = element.rmsGreasing
    RMS_Utils.drawSegments(element.absPosition[1], element.absPosition[2], element.absSize[1], element.absSize[2], greasing.total,
        greasing.greased, RMS_Utils.COLOR.HIGHLIGHT, element.rmsRestColor, RMS_Utils.getSegmentGap(greasing.total, 2) * g_pixelSizeScaledX)
end

---Forgets the machine
function RMS_InspectionDialog:onClose()
    self.vehicle = nil
    RMS_InspectionDialog:superClass().onClose(self)
end

---Closes the check
function RMS_InspectionDialog:onClickBack()
    self:close()
end
