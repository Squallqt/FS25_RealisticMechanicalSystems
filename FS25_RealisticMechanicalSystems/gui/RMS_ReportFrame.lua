-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---Inspection report of a log entry, shown in the record page
RMS_ReportFrame = {}
local RMS_ReportFrame_mt = Class(RMS_ReportFrame, FrameElement)

local WEAR_NORMAL_PERCENT = 10
local WEAR_HIGH_PERCENT = 30
local WEAR_CAUSE_MIN_PERCENT = 1
local WORN_PARTS_SHOWN = 3
local WEAR_CAUSES_SHOWN = 3
local ASSESSMENT_ROWS = 3
local SPEC_ROWS = 9
local SUMMARY_FIGURES = {
    { label = "rms_report_overall_assessment_condition", figure = "condition" },
    { label = "rms_ws_label_service", figure = "service" },
    { label = "rms_report_detected_breakdowns_title", figure = "breakdowns" }
}
local WEAR_CAUSE_TEXTS = {
    sf = "rms_tutorial_service_interval_expired_title",
    mlf = "rms_tutorial_engine_overload_title",
    aicf = "rms_report_wear_air_filter",
    cmf = "rms_tutorial_cold_engine_title",
    csf = "rms_tutorial_cold_engine_title",
    flf = "rms_tutorial_fluid_level_title",
    hmf = "rms_tutorial_engine_overheat_title",
    ohf = "rms_tutorial_engine_overheat_title",
    hcf = "rms_tutorial_engine_overheat_title",
    lf = "rms_tutorial_lugging_title",
    pof = "rms_report_wear_pull_overload",
    htf = "rms_tutorial_heavy_trailer_title",
    wsf = "rms_tutorial_wheel_slip_title",
    dwf = "rms_tutorial_drivetrain_windup_title",
    ctf = "rms_tutorial_cold_oil_title",
    hotf = "rms_tutorial_transmission_overheat_title",
    hlf = "rms_report_wear_heavy_lift",
    of = "rms_report_wear_hydraulic_use",
    cof = "rms_report_wear_cold_hydraulic_oil",
    hof = "rms_report_wear_hot_hydraulic_oil",
    vf = "rms_report_wear_vibration",
    hfbf = "rms_report_wear_hydraulic_filter_bypass",
    tfbf = "rms_report_wear_transmission_filter_bypass",
    wef = "rms_tutorial_wet_weather_title",
    ltf = "rms_report_wear_lights",
    crf = "rms_tutorial_cranking_title",
    slf = "rms_tutorial_steering_title",
    bmf = "rms_report_wear_braking",
    pbf = "rms_tutorial_park_brake_title",
    tif = "rms_report_wear_terrain_impact",
    lff = "rms_tutorial_low_fuel_title",
    cff = "rms_report_wear_cold_fuel",
    idf = "rms_tutorial_idle_deposit_title",
    hpf = "rms_report_wear_full_injection",
    ddf = "rms_report_wear_deep_discharge",
    hdf = "rms_report_wear_high_draw",
    bhf = "rms_report_wear_battery_heat",
    lubf = "rms_report_wear_lubrication",
    plf = "rms_report_wear_pto_overload",
    pef = "rms_tutorial_pto_engagement_title",
    prf = "rms_tutorial_pto_raised_title",
    hef = "rms_report_wear_harvest_overload",
    hgf = "rms_report_wear_harvest_flow",
    hsf = "rms_report_wear_harvest_straw",
    hstf = "rms_report_wear_harvest_stones",
    hrf = "rms_report_wear_harvest_rice",
    hwf = "rms_report_wear_harvest_wet"
}
RMS_ReportFrame.WEAR_CAUSE_TEXTS = WEAR_CAUSE_TEXTS
RMS_ReportFrame.SERVICE_NOTICE_HOURS = 100
RMS_ReportFrame.POWER_MIN_PERCENT = 90
RMS_ReportFrame.HYDRAULIC_FLOW_MIN_PERCENT = 85
RMS_ReportFrame.BATTERY_CAPACITY_MIN_PERCENT = 80
RMS_ReportFrame.ALTERNATOR_MIN_PERCENT = 90
RMS_ReportFrame.TRACTION_BATTERY_MIN_PERCENT = 70
RMS_ReportFrame.CONSUMPTION_MAX_PERCENT = 110
RMS_ReportFrame.BATTERY_CHARGE_SCALE = { IDEAL = 100, HIGH = 75, MID = 50, LOW = 25 }
RMS_ReportFrame.OVERHAUL_HOURS = 8000
RMS_ReportFrame.SHEET_SCALE = { IDEAL = 99, HIGH = 90, MID = 70, LOW = 30 }
local POOR_CONSUMABLES = "MAINTENANCE_WITH_POOR_QUALITY_CONSUMABLES"

local function getRecorded(activeEffects, effectId)
    local effect = activeEffects[effectId]
    if type(effect) == "table" then
        return effect.value
    end
    return nil
end

local function getHealth(activeEffects, effectId)
    return math.clamp(1 + (getRecorded(activeEffects, effectId) or 0), 0, 1)
end

local function getSystemName(vehicle, systemKey)
    return g_i18n:getText(RMS_Utils.getSystemLabel(vehicle, RMS_Utils.getSystemNameByKey(RealisticMechanicalSystems.SYSTEMS, systemKey)))
end

-- Level once the shortest hourly clock has its notice hours left
local function getServiceNoticeLevel(vehicle)
    local hours = math.huge
    for _, clock in ipairs(vehicle:getServiceClocks()) do
        if clock.intervalFactor ~= nil then
            hours = math.min(hours, clock.intervalFactor * RMS_Config.SERVICE_REFERENCE_HOURS)
        end
    end
    local expired = RMS_Config.CORE.SERVICE_EXPIRED_THRESHOLD
    local base = vehicle.spec_RealisticMechanicalSystems.baseServiceLevel
    return expired + (base - expired) * math.min(RMS_ReportFrame.SERVICE_NOTICE_HOURS / hours, 1)
end

local function joinNames(names)
    local list = {}
    for name in pairs(names) do
        table.insert(list, name)
    end
    table.sort(list)
    return table.concat(list, ", ")
end

local function readGearbox(activeEffects)
    local failed = "rms_report_transmission_failed"
    local value = getRecorded(activeEffects, "TRANSMISSION_SLIP_EFFECT")
    if value ~= nil then
        return value >= 1 and failed or "rms_report_transmission_slipping", 1 - value
    end
    value = getRecorded(activeEffects, "GEAR_SHIFT_FAILURE_CHANCE")
    if value ~= nil then
        return value >= 1 and failed or "rms_report_transmission_shifting_impaired", 1 - value
    end
    value = getRecorded(activeEffects, "GEAR_REJECTION_CHANCE")
    if value ~= nil then
        return value <= 3 and failed or "rms_report_transmission_gear_rejection", value / 20
    end
    value = getRecorded(activeEffects, "POWERSHIFT_ENGAGEMENT_LAG_AND_HARSH_EFFECT")
    if value ~= nil then
        return value >= 1 and failed or "rms_report_transmission_shift_delay", 1 - value
    end
    value = getRecorded(activeEffects, "CVT_SLIP_EFFECT")
    if value ~= nil then
        return value >= 1 and failed or "rms_report_transmission_cvt_slipping", 1 - value
    end
    value = getRecorded(activeEffects, "CVT_MAX_RATIO_MODIFIER")
    if value ~= nil then
        return value >= 0.8 and failed or "rms_report_transmission_cvt_ratio_limited", 1 - value
    end
    value = getRecorded(activeEffects, "CVT_PRESSURE_DROP_CHANCE")
    if value ~= nil then
        return value <= 0.1 and failed or "rms_report_transmission_cvt_pressure_instability", value / 2
    end
    return "rms_report_state_optimal", 1
end

---Writes the advice of a report, in the order the player acts on it
function RMS_ReportFrame.getRecommendations(vehicle, conditionData, findings, isComplete)
    local advice = {}
    local function advise(key, ...)
        local text = g_i18n:getText(key)
        if select("#", ...) > 0 then
            text = string.format(text, ...)
        end
        table.insert(advice, text)
    end

    local service, condition = conditionData.service, conditionData.condition
    local overhaul = 1 - RMS_ReportFrame.OVERHAUL_HOURS / RMS_Config.CORE.MACHINE_LIFE_HOURS
    if service <= RMS_Config.CORE.SERVICE_EXPIRED_THRESHOLD then
        advise("rms_report_recommendation_service_urgent")
    elseif service <= getServiceNoticeLevel(vehicle) then
        advise("rms_report_recommendation_service_due")
    end
    if findings.activeCount > 0 then
        advise("rms_report_recommendation_repair_active_breakdowns")
    end
    if next(findings.poorParts) ~= nil then
        advise("rms_report_recommendation_defective_parts", joinNames(findings.poorParts))
    end
    if next(findings.quickFixParts) ~= nil then
        advise("rms_report_recommendation_quick_fix", joinNames(findings.quickFixParts))
    end
    if condition < overhaul then
        advise("rms_report_recommendation_overhaul")
    end
    if isComplete and conditionData.wearExcess ~= nil and conditionData.wearExcess * 100 > WEAR_HIGH_PERCENT then
        advise("rms_report_recommendation_operating_conditions")
    end
    if isComplete and findings.hasPoorConsumables then
        advise("rms_report_recommendation_repeat_maintenance")
    end

    if condition > overhaul then
        -- A sound machine with one system to overhaul: the weakest
        local systems, weakestKey, weakest = conditionData.systems, nil, overhaul
        for _, systemName in ipairs(RealisticMechanicalSystems.SYSTEMS_ORDER) do
            local systemKey = RMS_Utils.getSystemKey(RealisticMechanicalSystems.SYSTEMS, systemName)
            local system = systems[systemKey]
            if system ~= nil and system.enabled ~= false and system.condition < weakest then
                weakestKey, weakest = systemKey, system.condition
            end
        end
        if weakestKey ~= nil then
            advise("rms_report_recommendation_system_overhaul", getSystemName(vehicle, weakestKey))
        end

        -- The riskiest worn part the major service adjusts, system sound
        local riskiestKey, highest = nil, 0
        if isComplete then
            for _, partId in ipairs(RealisticMechanicalSystems.MAJOR_SERVICE_CHECKS) do
                local wear = conditionData.partWear[partId]
                if wear ~= nil and RMS_Utils.getIsPartWorn(partId, wear) then
                    local systemKey = RMS_Utils.getSystemKey(RealisticMechanicalSystems.SYSTEMS, RMS_Breakdowns.BreakdownRegistry[partId].system)
                    local system = systems[systemKey]
                    local ratio = RMS_Utils.getPartRiskRatio(partId, wear)
                    if system ~= nil and system.condition >= overhaul and ratio > highest then
                        riskiestKey, highest = systemKey, ratio
                    end
                end
            end
        end
        if riskiestKey ~= nil then
            advise("rms_report_recommendation_system_preventive_maintenance", getSystemName(vehicle, riskiestKey),
                RMS_Utils.formatHours(vehicle:getMaintenanceLevelInterval(RealisticMechanicalSystems.MAINTENANCE_TYPES.PREVENTIVE)))
        end
    end

    if advice[1] == nil then
        advise("rms_report_recommendation_all_ok")
    end
    return advice
end

---Creates the frame
function RMS_ReportFrame.new()
    return FrameElement.new(nil, RMS_ReportFrame_mt)
end

---Wires the note lists and clones the rows of each card
function RMS_ReportFrame:initialize()
    for _, list in ipairs({ self.breakdownsTable, self.recommendationsTable }) do
        list:setDataSource(self)
    end
    self.assessmentRows = RMS_Utils.cloneTemplate(self.assessmentRowTemplate, ASSESSMENT_ROWS)
    self.wearCauseRows = RMS_Utils.cloneTemplate(self.wearCauseRowTemplate, WEAR_CAUSES_SHOWN)
    self.systemRows = RMS_Utils.cloneTemplate(self.systemRowTemplate, #RealisticMechanicalSystems.SYSTEMS_ORDER)
    self.specRows = RMS_Utils.cloneTemplate(self.specRowTemplate, SPEC_ROWS)
    self.summaryFigures = {}
    for index, figure in ipairs(RMS_Utils.cloneTemplate(self.summaryFigureTemplate, #SUMMARY_FIGURES)) do
        figure:getDescendantByName("label"):setText(g_i18n:getText(SUMMARY_FIGURES[index].label))
        self.summaryFigures[SUMMARY_FIGURES[index].figure] = figure:getDescendantByName("value")
    end
end

---Writes the report of a log entry
function RMS_ReportFrame:setReport(vehicle, entry)
    self.vehicle = vehicle
    self.lastReport = entry
    self.isCompleteInspection = RealisticMechanicalSystems.getIsCompleteReport(entry)
    self:updateScreen()
    RMS_Utils.resetScrollingTexts(self)
end

---Builds the technical sheet against the factory figures
function RMS_ReportFrame.buildVehicleSpecs(vehicle, conditionData)
    local spec = vehicle.spec_RealisticMechanicalSystems
    local effects, rating = conditionData.activeEffects, spec.electricalRating
    local isElectric = spec.isElectricVehicle
    local rows = {}

    local function addFigure(key, nominal, share, unit, isPublic, minPercent)
        table.insert(rows, { key = key, kind = "pair", current = nominal * share, nominal = nominal, ratio = share, unit = unit,
            isPublic = isPublic, minPercent = minPercent })
    end
    local function addShare(key, share, isPublic, minPercent)
        table.insert(rows, { key = key, kind = "ratio", ratio = share, isPublic = isPublic, minPercent = minPercent })
    end

    addFigure("rms_report_system_condition_power", vehicle:getMotor().peakMotorPower * 1.36,
        math.max(1 + (getRecorded(effects, "ENGINE_TORQUE_MODIFIER") or 0), 0), "hp", true, RMS_ReportFrame.POWER_MIN_PERCENT)
    addShare("rms_report_system_condition_brakes", 1 + (getRecorded(effects, "BRAKE_FORCE_MODIFIER") or 0), true)

    local batteryChargeKey, batteryCapacityKey = "rms_report_vehicle_spec_battery_charge", "rms_report_vehicle_spec_battery_capacity"
    if isElectric then
        batteryChargeKey = "rms_report_vehicle_spec_auxiliary_battery_charge"
        batteryCapacityKey = "rms_report_vehicle_spec_auxiliary_battery_capacity"
    elseif spec.electricalRating.seriesBatteries > 1 then
        batteryChargeKey = "rms_report_vehicle_spec_battery_24v_charge"
        batteryCapacityKey = "rms_report_vehicle_spec_battery_24v_capacity"
    end
    table.insert(rows, { key = batteryChargeKey, kind = "ratio", ratio = math.clamp(conditionData.batterySoc, 0, 1), isPublic = true,
        isMeasured = true, scale = RMS_ReportFrame.BATTERY_CHARGE_SCALE })

    local gearboxText, gearboxShare = readGearbox(effects)
    table.insert(rows, { key = "rms_report_system_condition_transmission", kind = "text", textKey = gearboxText,
        ratio = math.clamp(gearboxShare, 0, 1) })
    addShare("rms_report_system_condition_cooling", math.min(getHealth(effects, "THERMOSTAT_HEALTH_MODIFIER"),
        getHealth(effects, "RADIATOR_HEALTH_MODIFIER"), getHealth(effects, "FAN_CLUTCH_MODIFIER")))
    table.insert(rows, { key = isElectric and "rms_report_system_condition_energy_consumption" or "rms_report_system_condition_consumption",
        kind = "ratio", ratio = 1 + (getRecorded(effects, "FUEL_CONSUMPTION_MODIFIER") or 0), isConsumption = true })
    if RMS_Breakdowns.BreakdownRegistry.HYDRAULIC_PUMP_MALFUNCTION.isApplicable(vehicle) then
        addShare("rms_report_system_condition_hydraulic", 1 + (getRecorded(effects, "HYDRAULIC_SPEED_MODIFIER") or 0), false,
            RMS_ReportFrame.HYDRAULIC_FLOW_MIN_PERCENT)
    end

    if isElectric then
        local capacityShare = RMS_ElectricDrive.getCapacityShare(math.clamp(conditionData.systems.fuel.condition, 0, 1),
            getRecorded(effects, "TRACTION_BATTERY_CAPACITY_MODIFIER") or 0)
        addFigure("rms_report_vehicle_spec_traction_battery_capacity", spec.tractionBatteryNominalCapacity, capacityShare, "kWh", true,
            RMS_ReportFrame.TRACTION_BATTERY_MIN_PERCENT)
    else
        addFigure("rms_report_vehicle_spec_max_alternator_current", rating.alternatorA, getHealth(effects, "ALTERNATOR_HEALTH_MODIFIER"),
            "A", false, RMS_ReportFrame.ALTERNATOR_MIN_PERCENT)
    end
    addFigure(batteryCapacityKey, rating.batteryCapacityAh, getHealth(effects, "BATTERY_HEALTH_MODIFIER"), "Ah", false,
        RMS_ReportFrame.BATTERY_CAPACITY_MIN_PERCENT)

    return rows
end

---Lists the breakdowns found, worst first, with what the advice reads
function RMS_ReportFrame:collectBreakdowns()
    local breakdowns = self.lastReport.conditionData.activeBreakdowns
    local findings = { activeCount = 0, poorParts = {}, quickFixParts = {}, hasPoorConsumables = false }
    local shownCount = 0

    local ids = {}
    for id in pairs(breakdowns) do
        table.insert(ids, id)
    end
    table.sort(ids, function(a, b)
        local stageA, stageB = breakdowns[a].stage or 0, breakdowns[b].stage or 0
        if stageA == stageB then
            return a < b
        end
        return stageA > stageB
    end)

    local sources = RealisticMechanicalSystems.BREAKDOWN_SOURCES
    for _, id in ipairs(ids) do
        local breakdown, definition = breakdowns[id], RMS_Breakdowns.BreakdownRegistry[id]
        findings.hasPoorConsumables = findings.hasPoorConsumables or id == POOR_CONSUMABLES
        if breakdown.isVisible and definition ~= nil and definition.isSelectable then
            shownCount = shownCount + 1
            local stage = breakdown.stage or 1
            if definition.stages[stage] ~= nil then
                local partName = RMS_Utils.getBreakdownPartName(id, self.vehicle)
                local isActive = breakdown.isActive ~= false
                if isActive then
                    findings.activeCount = findings.activeCount + 1
                elseif breakdown.source == sources.POOR_PARTS then
                    findings.poorParts[partName] = true
                elseif breakdown.source == sources.QUICK_FIX then
                    findings.quickFixParts[partName] = true
                end
                local severityText, descriptionText = RMS_Utils.getBreakdownTexts(self.vehicle, id, breakdown)
                table.insert(self.breakdownsData, { title = partName, severity = severityText, text = descriptionText, stage = stage,
                    isActive = isActive })
            end
        end
    end
    return findings, shownCount
end

---Rebuilds every section of the report from the stored log entry
function RMS_ReportFrame:updateScreen()
    local vehicle, entry = self.vehicle, self.lastReport
    local conditionData = entry.conditionData
    local spec = vehicle.spec_RealisticMechanicalSystems

    self.reportTitle:setText(g_i18n:getText("rms_report_header_title") .. " #" .. entry.id - 1, nil, nil, true)
    self.reportVehicleImage:setImageFilename(vehicle:getImageFilename())

    self.reportSubtitle:setText(table.concat({
        vehicle:getFullName(),
        RMS_Utils.formatMaintenanceLogDate(entry),
        string.format("%s (%s)", g_i18n:getText(entry.type),
            RMS_Utils.formatServiceOption(vehicle, entry.type, entry.optionOne)),
        g_i18n:getText(entry.location),
        string.format("%d %s", conditionData.age or 0, g_i18n:getText("rms_ws_age_unit")),
        RMS_Utils.formatHours(math.floor(conditionData.operatingHours * 10) / 10),
        "ODO " .. RMS_Utils.formatOdometerKilometers(conditionData.odometerKilometers)
    }, " · "), nil, nil, true)

    local figures = self.summaryFigures
    figures.condition:setText(RMS_Utils.formatCondition(conditionData.condition, self.isCompleteInspection))
    figures.condition:setTextColor(RMS_Utils.getConditionColor(conditionData.condition, self.isCompleteInspection))
    figures.service:setText(RMS_Utils.formatService(conditionData.service, self.isCompleteInspection))
    figures.service:setTextColor(RMS_Utils.getServiceColor(conditionData.service, self.isCompleteInspection))

    local riskTier
    for systemKey in pairs(conditionData.systems) do
        local tier = RMS_Utils.getBreakdownRiskTier(RMS_Utils.getSystemRiskRatio(vehicle, systemKey, conditionData.partWear))
        if tier ~= nil and (riskTier == nil or tier > riskTier) then
            riskTier = tier
        end
    end
    self.overallAssessmentData = {
        {'rms_ws_label_reliability', RMS_Utils.formatReliability(spec.reliability), {RMS_Utils.getReliabilityColor(spec.reliability)}},
        {'rms_ws_label_service_access', RMS_Utils.formatServiceAccess(vehicle), {RMS_Utils.getServiceAccessColor(vehicle)}},
        {'rms_report_breakdown_risk_title', RMS_Utils.formatBreakdownRisk(riskTier),
            riskTier ~= nil and {RMS_Utils.getValueColorInverted(riskTier, 1, 1, 2, 2, false)} or RMS_Utils.COLOR.TEXT_DIM}
    }

    self.systemConditionData = {}
    for _, systemL10nKey in ipairs(RealisticMechanicalSystems.SYSTEMS_ORDER) do
        local systemKey = RMS_Utils.getSystemKey(RealisticMechanicalSystems.SYSTEMS, systemL10nKey)
        local system = conditionData.systems[systemKey]
        if system ~= nil and system.enabled ~= false then
            local ratio = RMS_Utils.getSystemRiskRatio(vehicle, systemKey, conditionData.partWear)
            table.insert(self.systemConditionData, {systemL10nKey, math.clamp(system.condition, 0, 1), RMS_Utils.getBreakdownRiskTier(ratio)})
        end
    end

    self.vehicleSpecData = RMS_ReportFrame.buildVehicleSpecs(vehicle, conditionData)

    self.breakdownsData = {}
    local findings, shownCount = self:collectBreakdowns()
    figures.breakdowns:setText(tostring(shownCount))
    if self.isCompleteInspection then
        self:addWornPartRows()
    end
    self.breakdownsCardTitle:setText(g_i18n:getText(self.isCompleteInspection and "rms_report_breakdowns_worn_title"
        or "rms_report_detected_breakdowns_title"))
    if self.breakdownsData[1] == nil then
        table.insert(self.breakdownsData, {title = g_i18n:getText(self.isCompleteInspection and "rms_report_no_breakdowns_worn"
            or "rms_log_inspection_desc_no_breakdowns"), text = "", severity = ""})
    end

    self.recommendationsData = RMS_ReportFrame.getRecommendations(vehicle, conditionData, findings, self.isCompleteInspection)

    self:renderAssessmentRows()
    self:renderWear()
    self:renderSystemRows()
    self:renderSpecRows()
    for _, list in ipairs({ self.breakdownsTable, self.recommendationsTable }) do
        list:reloadData()
    end

    RMS_Utils.fitValuePills(self)
end

---The lists of detected breakdowns and of recommendations
function RMS_ReportFrame:getFocusColumns()
    return { { { self.breakdownsTable } }, { { self.recommendationsTable } } }
end

---Returns the row count of a note list
function RMS_ReportFrame:getNumberOfItemsInSection(list, section)
    if list == self.recommendationsTable then
        return #self.recommendationsData
    end
    return #self.breakdownsData
end

---Fills one note cell of a list
function RMS_ReportFrame:populateCellForItemInSection(list, section, index, cell)
    if list == self.recommendationsTable then
        self:populateRecommendationsCell(index, cell)
    else
        self:populateBreakdownsCell(index, cell)
    end
end

---Paints the inspection assessment
function RMS_ReportFrame:renderAssessmentRows()
    for index, row in ipairs(self.assessmentRows) do
        local data = self.overallAssessmentData[index]
        local isAvailable = data[1] ~= "rms_report_breakdown_risk_title" or self.isCompleteInspection
        local valueText = isAvailable and data[2] or g_i18n:getText("rms_report_state_not_available")
        row:getDescendantByName("label"):setTextColor(unpack(isAvailable and RMS_Utils.COLOR.TEXT or RMS_Utils.COLOR.TEXT_DIM))
        row:getDescendantByName("value"):setTextColor(unpack(isAvailable and (data[3] or RMS_Utils.COLOR.TEXT) or RMS_Utils.COLOR.TEXT_DIM))
        RMS_Utils.writeRow(row, g_i18n:getText(data[1]), valueText)
    end
end

local function getWearColor(percent)
    return RMS_Utils.getValueColorInverted(percent, WEAR_NORMAL_PERCENT, WEAR_NORMAL_PERCENT, WEAR_HIGH_PERCENT, 100, false)
end

---Writes the extra wear of the machine and its three main causes
function RMS_ReportFrame:renderWear()
    local data = self.lastReport.conditionData
    self.wearBlock:setVisible(data.wearExcess ~= nil)
    if data.wearExcess == nil then
        return
    end

    local shares = {}
    for alias, share in pairs(data.wearCauses) do
        local key = WEAR_CAUSE_TEXTS[alias]
        if key ~= nil then
            shares[key] = (shares[key] or 0) + share * 100
        end
    end
    local causes = {}
    for key, percent in pairs(shares) do
        if percent >= WEAR_CAUSE_MIN_PERCENT then
            table.insert(causes, { key = key, percent = percent })
        end
    end
    table.sort(causes, function(a, b)
        if a.percent ~= b.percent then
            return a.percent > b.percent
        end
        return a.key < b.key
    end)

    local percent = data.wearExcess * 100
    if percent < WEAR_NORMAL_PERCENT then
        self.wearValue:setText(g_i18n:getText("rms_report_wear_normal"))
    else
        -- Round before the native integer formatter truncates.
        self.wearValue:setText(string.format(g_i18n:getText("rms_report_wear_percent"), g_i18n:formatNumber(MathUtil.round(percent), 0)))
    end
    self.wearValue:setTextColor(getWearColor(percent))

    for index, row in ipairs(self.wearCauseRows) do
        local cause = causes[index]
        local labelElement, valueElement = row:getDescendantByName("label"), row:getDescendantByName("value")
        labelElement:setVisible(cause ~= nil or index == 1)
        valueElement:setVisible(cause ~= nil)
        if cause ~= nil then
            labelElement:setText(g_i18n:getText(cause.key))
            valueElement:setText(string.format(g_i18n:getText("rms_report_wear_percent"), g_i18n:formatNumber(cause.percent, 1)))
            if cause.percent >= WEAR_NORMAL_PERCENT then
                valueElement:setTextColor(getWearColor(cause.percent))
            else
                valueElement:setTextColor(unpack(RMS_Utils.COLOR.TEXT))
            end
        end
    end
    if #causes == 0 then
        self.wearCauseRows[1]:getDescendantByName("label"):setText(g_i18n:getText("rms_report_wear_no_cause"))
    end
end

---Paints one gauge per enabled system
function RMS_ReportFrame:renderSystemRows()
    for index, row in ipairs(self.systemRows) do
        local data = self.systemConditionData[index]
        row:setVisible(data ~= nil)

        if data ~= nil then
            local nameElement, valueElement, riskElement = row:getDescendantByName("name"), row:getDescendantByName("value"),
                row:getDescendantByName("risk")
            local condition = data[2]
            local percent = condition * 100
            local riskTier = data[3]
            nameElement:setText(g_i18n:getText(RMS_Utils.getSystemLabel(self.vehicle, data[1])))

            if self.isCompleteInspection then
                valueElement:setText(string.format("%.1f %%", percent))
                riskElement:setText(RMS_Utils.formatBreakdownRisk(riskTier))
                if riskTier ~= nil then
                    riskElement:setTextColor(RMS_Utils.getValueColorInverted(riskTier, 1, 1, 2, 2, false))
                else
                    riskElement:setTextColor(unpack(RMS_Utils.COLOR.TEXT_DIM))
                end
                valueElement:setTextColor(RMS_Utils.getValueColor(percent, 95, 80, 60, 40, true))
            else
                valueElement:setText(RMS_Utils.formatCondition(condition, false))
                valueElement:setTextColor(RMS_Utils.getConditionColor(condition, false))
                riskElement:setText(g_i18n:getText("rms_report_state_not_available"))
                riskElement:setTextColor(unpack(RMS_Utils.COLOR.TEXT_DIM))
            end
        end
    end

    self.systemRows[1].parent:invalidateLayout()
end

---Paints what the machine still delivers against its factory figures
function RMS_ReportFrame:renderSpecRows()
    local isComplete = self.isCompleteInspection
    local stateTexts = {}
    for index, key in ipairs({ "rms_report_state_optimal", "rms_report_state_normal", "rms_report_state_degraded",
            "rms_report_state_impaired", "rms_report_state_critical" }) do
        stateTexts[index] = g_i18n:getText(key)
    end

    for index, row in ipairs(self.specRows) do
        local figure = self.vehicleSpecData[index]
        row:setVisible(figure ~= nil)
        if figure ~= nil then
            local labelElement, valueElement = row:getDescendantByName("label"), row:getDescendantByName("value")
            local isRead = isComplete or figure.isPublic
            local valueText = g_i18n:getText("rms_report_state_not_available")
            labelElement:setTextColor(unpack(isRead and RMS_Utils.COLOR.TEXT or RMS_Utils.COLOR.TEXT_DIM))
            if not isRead then
                valueElement:setTextColor(unpack(RMS_Utils.COLOR.TEXT_DIM))
            elseif figure.isConsumption then
                local percent = math.max(figure.ratio, 0) * 100
                local limit = RMS_ReportFrame.CONSUMPTION_MAX_PERCENT
                valueText = string.format("%.1f %%", percent)
                valueElement:setTextColor(RMS_Utils.getValueColorInverted(percent, limit, limit, limit, limit, isComplete))
            else
                local percent = math.clamp(figure.ratio, 0, 1) * 100
                local steps = figure.scale or RMS_ReportFrame.SHEET_SCALE
                if figure.minPercent ~= nil then
                    -- A tested part passes or fails at its limit
                    local limit = figure.minPercent
                    steps = { IDEAL = limit, HIGH = limit, MID = limit, LOW = limit }
                end
                if figure.kind == "pair" then
                    valueText = string.format("%.1f | %.1f %s", figure.current, figure.nominal, figure.unit)
                elseif figure.kind == "text" then
                    valueText = g_i18n:getText(figure.textKey)
                elseif isComplete or figure.isMeasured then
                    valueText = string.format("%.1f %%", percent)
                else
                    valueText = RMS_Utils.getValueLabel(percent, steps.IDEAL, steps.HIGH, steps.MID, steps.LOW, unpack(stateTexts))
                end
                valueElement:setTextColor(RMS_Utils.getValueColor(percent, steps.IDEAL, steps.HIGH, steps.MID, steps.LOW,
                    isComplete and figure.minPercent == nil))
            end
            RMS_Utils.fitRowText(labelElement, valueElement, g_i18n:getText(figure.key), valueText)
        end
    end

    self.specRows[1].parent:invalidateLayout()
end

function RMS_ReportFrame:addWornPartRows()
    local conditionData = self.lastReport.conditionData
    local systems = conditionData.systems or {}
    local activeBreakdowns = conditionData.activeBreakdowns or {}
    local adjusted = {}
    for _, partId in ipairs(RealisticMechanicalSystems.MAJOR_SERVICE_CHECKS) do
        adjusted[partId] = true
    end

    local worn = {}
    local systemParts = self.vehicle.spec_RealisticMechanicalSystems.systemParts
    for systemKey, system in pairs(systems) do
        if system.enabled ~= false then
            for _, partId in ipairs(systemParts[systemKey]) do
                local wear = conditionData.partWear[partId]
                if wear ~= nil and activeBreakdowns[partId] == nil and RMS_Utils.getIsPartWorn(partId, wear) then
                    table.insert(worn, { partId = partId, systemKey = systemKey, ratio = RMS_Utils.getPartRiskRatio(partId, wear) })
                end
            end
        end
    end
    table.sort(worn, function(a, b)
        if a.ratio ~= b.ratio then
            return a.ratio > b.ratio
        end
        return a.partId < b.partId
    end)

    local count = math.min(#worn, WORN_PARTS_SHOWN)
    local color = { RMS_Utils.getValueColorInverted(3, 1, 1, 2, 3, false) }
    for index = 1, count do
        local entry = worn[index]
        local systemName = getSystemName(self.vehicle, entry.systemKey)
        local text = adjusted[entry.partId]
            and string.format(g_i18n:getText("rms_report_worn_part_adjust"), systemName,
                RMS_Utils.formatMaintenanceLevel(self.vehicle, RealisticMechanicalSystems.MAINTENANCE_TYPES.PREVENTIVE))
            or string.format(g_i18n:getText("rms_report_worn_part_replace"), systemName)
        table.insert(self.breakdownsData, {
            title = RMS_Utils.getBreakdownPartName(entry.partId, self.vehicle),
            severity = string.format(g_i18n:getText("rms_report_worn_part_risk"), g_i18n:formatNumber(entry.ratio, 1)),
            text = text,
            color = color
        })
    end
    return count
end

---Fills one detected breakdown or worn part
function RMS_ReportFrame:populateBreakdownsCell(index, cell)
    RMS_Utils.applyScrollSpeed(cell)
    local data = self.breakdownsData[index] or {}
    local stageColor = data.color or (data.isActive == false and RMS_Utils.COLOR.TEXT_DIM or RMS_Utils.COLOR.STAGE[data.stage or 1])
    local severityElement = cell:getAttribute("reportBreakdownsSeverity")
    local hasSeverity = (data.severity or "") ~= ""
    local description = data.text or ""
    local isEmptyState = not hasSeverity and description == ""

    local titleElement = cell:getAttribute("reportBreakdownsTitle")
    local emptyTitleElement = cell:getAttribute("reportBreakdownsEmptyTitle")
    local textElement = cell:getAttribute("reportBreakdownsText")

    cell:getAttribute("reportBreakdownsIcon"):setImageColor(nil, unpack(stageColor or RMS_Utils.COLOR.TEXT))
    titleElement:setVisible(not isEmptyState)
    titleElement:setText(data.title or "")
    emptyTitleElement:setVisible(isEmptyState)
    emptyTitleElement:setText(data.title or "")
    severityElement:setVisible(hasSeverity)
    severityElement:setText(data.severity or "")
    severityElement:setTextColor(unpack(stageColor or RMS_Utils.COLOR.TEXT))
    textElement:setText(description)
end

---Fills one recommendation with its prebuilt line
function RMS_ReportFrame:populateRecommendationsCell(index, cell)
    RMS_Utils.applyScrollSpeed(cell)
    cell:getAttribute("reportRecRow"):setText(self.recommendationsData[index])
end
