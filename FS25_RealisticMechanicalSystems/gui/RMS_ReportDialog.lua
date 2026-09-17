-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---Dialog presenting a stored inspection report of a vehicle
RMS_ReportDialog = {}
RMS_ReportDialog.INSTANCE = nil

local RMS_ReportDialog_mt = Class(RMS_ReportDialog, MessageDialog)
local modDirectory = g_currentModDirectory
-- thresholds a measured figure falls back on when the report carries no rule for it
local ASSESSMENT_DEFAULT_CONFIG = {inverted = false, ideal = 100, high = 95, mid = 90, low = 70, isPercent = true}
local getSystemDisplayName
local formatRecommendationText
local joinRecommendationParts

---Recommendation rules evaluated in order against the report entry and its metrics
local RECOMMENDATION_RULES = {
    -- service between 0.45 and 0.65
    {
        l10nKey = "rms_report_recommendation_service_due",
        check = function(vehicle, reportEntry, metrics)
            if reportEntry == nil or reportEntry.conditionData == nil then
                return false
            end
            local service = reportEntry.conditionData.service
            return type(service) == "number" and service > 0.45 and service < 0.65
        end
    },
    -- service below 0.45
    {
        l10nKey = "rms_report_recommendation_service_urgent",
        check = function(vehicle, reportEntry, metrics)
            if reportEntry == nil or reportEntry.conditionData == nil then
                return false
            end
            local service = reportEntry.conditionData.service
            return type(service) == "number" and service < 0.45
        end
    },
    -- at least one visible selectable active breakdown
    {
        l10nKey = "rms_report_recommendation_repair_active_breakdowns",
        check = function(vehicle, reportEntry, metrics)
            if metrics == nil then
                return false
            end
            return (metrics.visibleSelectableActiveBreakdownsCount or 0) > 0
        end
    },
    -- poor condition parts that have not failed yet, listed by name
    {
        l10nKey = "rms_report_recommendation_defective_parts",
        check = function(vehicle, reportEntry, metrics)
            if metrics == nil then
                return false
            end

            local partsText = joinRecommendationParts(metrics.inactivePoorPartsNames)
            if partsText ~= nil then
                return {
                    params = {partsText}
                }
            end

            return false
        end
    },
    -- quick fix parts that have not failed yet, listed by name
    {
        l10nKey = "rms_report_recommendation_quick_fix",
        check = function(vehicle, reportEntry, metrics)
            if metrics == nil then
                return false
            end

            local partsText = joinRecommendationParts(metrics.inactiveQuickFixPartsNames)
            if partsText ~= nil then
                return {
                    params = {partsText}
                }
            end

            return false
        end
    },
    -- overall condition below 0.4
    {
        l10nKey = "rms_report_recommendation_overhaul",
        check = function(vehicle, reportEntry, metrics)
            if reportEntry == nil or reportEntry.conditionData == nil then
                return false
            end
            local condition = reportEntry.conditionData.condition
            return type(condition) == "number" and condition < 0.4
        end
    },
    -- wear rate above 1.3 times nominal, complete inspection only
    {
        l10nKey = "rms_report_recommendation_operating_conditions",
        check = function(vehicle, reportEntry, metrics)
            if metrics == nil or not metrics.isCompleteInspection then
                return false
            end
            local wearRate = metrics.wearRate
            local nominalWearRate = metrics.nominalWearRate
            if type(wearRate) ~= "number" or type(nominalWearRate) ~= "number" or nominalWearRate <= 0 then
                return false
            end
            return (wearRate / nominalWearRate) > 1.3
        end
    },
    -- poor quality consumables breakdown present, complete inspection only
    {
        l10nKey = "rms_report_recommendation_repeat_maintenance",
        check = function(vehicle, reportEntry, metrics)
            if metrics == nil or not metrics.isCompleteInspection then
                return false
            end
            return metrics.hasPoorQualityConsumablesBreakdown == true
        end
    },
    -- worst enabled system below 0.4 while overall condition stays above 0.4
    {
        l10nKey = "rms_report_recommendation_system_overhaul",
        check = function(vehicle, reportEntry, metrics)
            if reportEntry == nil or reportEntry.conditionData == nil then
                return false
            end

            local overallCondition = tonumber(reportEntry.conditionData.condition)
            if overallCondition ~= nil and overallCondition <= 0.4 then
                return false
            end

            local minCond = 1.0
            local targetSystemKey = nil
            local systems = reportEntry.conditionData.systems or {}

            for systemName, systemData in pairs(systems) do
                if type(systemData) == "table" and systemData.enabled ~= false then
                    local systemCondition = tonumber(systemData.condition)
                    if systemCondition ~= nil and systemCondition < 0.4 and systemCondition < minCond then
                        minCond = systemCondition
                        targetSystemKey = systemName
                    end
                end
            end

            if targetSystemKey ~= nil then
                return {
                    params = {getSystemDisplayName(targetSystemKey)}
                }
            end

            return false
        end
    },
    -- enabled system at or above 0.4 whose stress over condition exceeds 0.8, complete inspection only
    {
        l10nKey = "rms_report_recommendation_system_preventive_maintenance",
        check = function(vehicle, reportEntry, metrics)
            if reportEntry == nil or reportEntry.conditionData == nil or metrics == nil or not metrics.isCompleteInspection then
                return false
            end

            local overallCondition = tonumber(reportEntry.conditionData.condition)
            if overallCondition ~= nil and overallCondition <= 0.4 then
                return false
            end

            local highestRelativeStress = 0
            local targetSystemKey = nil
            local systems = reportEntry.conditionData.systems or {}

            for systemName, systemData in pairs(systems) do
                if type(systemData) == "table" and systemData.enabled ~= false then
                    local systemCondition = math.max(tonumber(systemData.condition) or 0, 0.001)
                    local systemStress = math.max(tonumber(systemData.stress) or 0, 0)
                    local relativeStress = systemStress / systemCondition

                    if systemCondition >= 0.4 and relativeStress > 0.8 and relativeStress > highestRelativeStress then
                        highestRelativeStress = relativeStress
                        targetSystemKey = systemName
                    end
                end
            end

            if targetSystemKey ~= nil then
                return {
                    params = {getSystemDisplayName(targetSystemKey)}
                }
            end

            return false
        end
    }
}

local log_dbg = RMS_Utils.createLogger("[RMS_REPORT_DIALOG]")

---Returns the localized text of a key, or the fallback when the key is missing or unresolved
-- @param string key l10n key
-- @param string fallback text used when the key resolves to nothing
-- @return string text localized text
local function getTextOrFallback(key, fallback)
    local text = g_i18n:getText(key)
    if text == nil or text == "" or text == key then
        return fallback
    end
    return text
end

---Returns the localized display name of a system, matching its key case insensitively
-- @param string systemKey system key
-- @return string name localized system name, the key itself when unknown
function getSystemDisplayName(systemKey)
    local normalizedKey = string.lower(tostring(systemKey or ""))

    for enumKey, l10nKey in pairs(RealisticMechanicalSystems.SYSTEMS or {}) do
        if string.lower(enumKey) == normalizedKey then
            return getTextOrFallback(l10nKey, tostring(systemKey))
        end
    end

    return tostring(systemKey or "")
end

---Formats a recommendation template with its parameters
-- @param string l10nKey l10n key of the template
-- @param table? params format arguments
-- @param string? fallback text used when the key resolves to nothing
-- @return string text formatted recommendation
function formatRecommendationText(l10nKey, params, fallback)
    local template = getTextOrFallback(l10nKey, fallback or l10nKey)
    if type(params) == "table" and #params > 0 then
        local formattedText = string.format(template, table.unpack(params))
        if formattedText ~= nil and formattedText ~= "" then
            return formattedText
        end
    end

    return template
end

---Returns the numeric value of an active effect
-- @param table activeEffects active effects indexed by effect id
-- @param string effectId effect id
-- @return float? value effect value, nil when the effect is absent
local function getEffectValue(activeEffects, effectId)
    local effect = activeEffects[effectId]
    if type(effect) == "table" and type(effect.value) == "number" then
        return effect.value
    end
    return nil
end

---Returns the localized stress label for a stress over condition ratio
-- @param float stress system stress
-- @param float condition system condition
-- @return string label absent, low, moderate, elevated or high
local function getStressLabel(stress, condition)
    local safeCondition = math.max(tonumber(condition) or 0, 0.001)
    local normalizedStress = math.max(math.min((tonumber(stress) or 0.0) / safeCondition, 1.0), 0.0)

    if normalizedStress < RMS_Config.CORE.BREAKDOWN_PROBABILITIES.STRESS_THRESHOLD then
        return getTextOrFallback("rms_report_stress_absent", "Absent")
    elseif normalizedStress < 0.4 then
        return getTextOrFallback("rms_report_stress_low", "Low")
    elseif normalizedStress < 0.6 then
        return getTextOrFallback("rms_report_stress_moderate", "Moderate")
    elseif normalizedStress < 0.8 then
        return getTextOrFallback("rms_report_stress_elevated", "Elevated")
    else
        return getTextOrFallback("rms_report_stress_high", "High")
    end
end

---Clamps a value to the 0 to 1 range
-- @param any value value to clamp
-- @return float ratio clamped ratio
local function clampUnitRatio(value)
    return math.max(math.min(tonumber(value) or 0, 1), 0)
end

---Returns the numeric value of an active effect, tolerating a nil effect table
-- @param table? activeEffects active effects indexed by effect id
-- @param string effectId effect id
-- @return float? value effect value, nil when the effect is absent
local function getTransmissionEffectValue(activeEffects, effectId)
    local effect = activeEffects ~= nil and activeEffects[effectId] or nil
    if type(effect) == "table" and type(effect.value) == "number" then
        return effect.value
    end
    return nil
end

---Appends a text to the list unless it is empty or already present
-- @param table list text list, modified in place
-- @param table seen texts already inserted
-- @param string? value text to append
local function appendUniqueText(list, seen, value)
    if value == nil or value == "" or seen[value] then
        return
    end

    seen[value] = true
    table.insert(list, value)
end

---Sorts and joins part names into a comma separated list
-- @param table parts part names
-- @return string? text joined names, nil when the list is empty
function joinRecommendationParts(parts)
    if type(parts) ~= "table" or #parts == 0 then
        return nil
    end

    table.sort(parts)
    return table.concat(parts, ", ")
end

---Evaluates every recommendation rule and returns the resulting bullet list
-- @param table vehicle vehicle
-- @param table reportEntry stored report entry
-- @param table metrics metrics computed for the report
-- @return table recommendations bullet lines, a single all clear line when no rule matched
local function buildRecommendationsData(vehicle, reportEntry, metrics)
    local recommendations = {}

    for _, rule in ipairs(RECOMMENDATION_RULES) do
        if type(rule.check) == "function" then
            local result = rule.check(vehicle, reportEntry, metrics)
            if result then
                local recommendationText = nil

                if result == true then
                    recommendationText = formatRecommendationText(rule.l10nKey)
                elseif type(result) == "table" then
                    recommendationText = formatRecommendationText(
                        result.l10nKey or rule.l10nKey,
                        result.params,
                        result.fallback
                    )
                end

                if recommendationText ~= nil and recommendationText ~= "" then
                    table.insert(recommendations, recommendationText)
                end
            end
        end
    end

    if #recommendations == 0 then
        table.insert(recommendations, formatRecommendationText("rms_report_recommendation_all_ok"))
    end

    return recommendations
end

---Loads the dialog layout and stores the shared instance
function RMS_ReportDialog.register()
    local dialog = RMS_ReportDialog.new()
    g_gui:loadGui(modDirectory .. "gui/RMS_ReportDialog.xml", "RMS_ReportDialog", dialog)
    RMS_ReportDialog.INSTANCE = dialog
end

---Create instance of RMS_ReportDialog
-- @param table? target target
-- @param table? customMt custom metatable
-- @return table dialog instance of class RMS_ReportDialog
function RMS_ReportDialog.new(target, customMt)
    local dialog = MessageDialog.new(target, customMt or RMS_ReportDialog_mt)
    dialog.vehicle = nil
    return dialog
end

---Opens the dialog on a log entry that carries a report
-- @param table vehicle vehicle
-- @param table logEntry maintenance log entry
function RMS_ReportDialog.show(vehicle, logEntry)

    if logEntry == nil or not RealisticMechanicalSystems.getIsLogEntryHasReport(logEntry) then
        log_dbg("Invalid log entry")
        return
    end

    if RMS_ReportDialog.INSTANCE == nil then RMS_ReportDialog.register() end
    if vehicle == nil or vehicle.spec_RealisticMechanicalSystems == nil then return end
    
    local dialog = RMS_ReportDialog.INSTANCE
    local spec = vehicle.spec_RealisticMechanicalSystems

    dialog.maintenanceLog = spec.maintenanceLog or {}
    dialog.vehicle = vehicle
    dialog.lastReport = logEntry
    dialog.isCompleteInspection = RealisticMechanicalSystems.getIsCompleteReport(logEntry)

    dialog.overallAssessmentData = {}
    dialog.systemConditionData = {}
    dialog.vehicleSpecData = {}
    dialog.breakdownsData = {}
    dialog.recommendationsData = {}
    
    dialog:updateScreen()
    g_gui:showDialog("RMS_ReportDialog")
end

---Rebuilds every section of the report from the stored log entry
function RMS_ReportDialog:updateScreen()
    if self.vehicle == nil then return end
    local spec = self.vehicle.spec_RealisticMechanicalSystems

    self.overallAssessmentData = {}
    self.systemConditionData = {}
    self.vehicleSpecData = {}
    self.breakdownsData = {}
    self.recommendationsData = {}

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

    -- identity band: the report number, then everything that dates the reading on one line
    self.reportTitle:setText(g_i18n:getText("rms_report_header_title") .. " #" .. self.lastReport.id - 1, nil, nil, true)
    self.reportVehicleImage:setImageFilename(self.vehicle:getImageFilename())

    local reportDate = self.lastReport.date or {}
    local dateStr = string.format("%s %s. '%02d",
        reportDate.day or 1,
        g_i18n:formatPeriod(reportDate.month or 1, true),
        reportDate.year or 0)

    self.reportSubtitle:setText(table.concat({
        self.vehicle:getFullName(),
        dateStr,
        string.format("%s (%s)", g_i18n:getText(self.lastReport.type), g_i18n:getText(self.lastReport.optionOne)),
        g_i18n:getText(self.lastReport.location),
        string.format("%d %s", self.lastReport.conditionData.age or 0, g_i18n:getText("rms_ws_age_unit")),
        string.format("%.1f %s", self.lastReport.conditionData.operatingHours or 0, g_i18n:getText("rms_ws_hours_unit"))
    }, " · "), nil, nil, true)

    -- overall assessment
    -- condition and service
    local condition = self.lastReport.conditionData.condition or 1.0
    local service = self.lastReport.conditionData.service or 1.0
    self.reportSummaryCondition:setText(RMS_Utils.formatCondition(condition, self.isCompleteInspection))
    self.reportSummaryCondition:setTextColor(RMS_Utils.getConditionColor(condition, self.isCompleteInspection))
    self.reportSummaryService:setText(RMS_Utils.formatService(service, self.isCompleteInspection))
    self.reportSummaryService:setTextColor(RMS_Utils.getServiceColor(service, self.isCompleteInspection))

    -- shortest mtbf, lowest and mean condition across enabled systems
    local systems = self.lastReport.conditionData.systems or {}
    local lowestCondition = 1.0
    local minMTBF = RMS_Config.CORE.BREAKDOWN_PROBABILITIES.MAX_MTBF
    local totalCurrentSystemCondition = 0.0
    local enabledSystemsCount = 0
    for _, systemData in pairs(systems) do
        if systemData.enabled ~= false then
            local systemCondition = math.max(math.min(systemData.condition or 1.0, 1.0), 0.0)
            local mtbf = RMS_Utils.getEstimatedMTBF(systemCondition, systemData.stress)
            minMTBF = (mtbf < minMTBF and mtbf) or minMTBF
            lowestCondition = (systemCondition < lowestCondition and systemCondition) or lowestCondition
            totalCurrentSystemCondition = totalCurrentSystemCondition + systemCondition
            enabledSystemsCount = enabledSystemsCount + 1
        end
    end

    local currentCondition = enabledSystemsCount > 0 and (totalCurrentSystemCondition / enabledSystemsCount) or condition

    minMTBF = minMTBF / 60
    table.insert(self.overallAssessmentData, {'rms_report_overall_assessment_mtbf', minMTBF})

    -- current crit failure risk
    local critFailureRisk = RMS_Utils.getCriticalFailureChance(lowestCondition)
    table.insert(self.overallAssessmentData, {'rms_report_overall_assessment_crit_fail_risk', critFailureRisk})
    
    -- wear rate measured since the first entry or the last overhaul
    local reportReliability = math.max(tonumber(self.lastReport.conditionData.reliability or spec.reliability) or 1.0, 0.001)
    local nominalWearRate = RMS_Config.CORE.BASE_SYSTEMS_WEAR / reportReliability
    local wearRate = nominalWearRate
    local startOperatingTime = 0.0
    local startCondition = 1.0
    local startSystems = nil
    local currentOperatingTime = self.lastReport.conditionData.operatingHours or 0.0

    for i = #self.maintenanceLog, 1, -1 do
        local entry = self.maintenanceLog[i]
        if entry.id == 1 then
            startOperatingTime = entry.conditionData.operatingHours or 0
            startCondition = entry.conditionData.condition or 1.0
            startSystems = entry.conditionData.systems or {}
            break
        elseif entry.type == RealisticMechanicalSystems.STATUS.OVERHAUL then
            startOperatingTime = entry.conditionData.operatingHours or 0
            startCondition = entry.conditionData.condition or 1.0
            startSystems = entry.conditionData.systems or {}
            break
        end
    end

    local operatingTimeDiff = math.max(currentOperatingTime - startOperatingTime, 0.001)
    local hasEnoughWearSample = currentOperatingTime >= 1.0 and operatingTimeDiff >= 1.0

    if not hasEnoughWearSample then
        wearRate = nominalWearRate
    else
        local totalWearRate = 0.0
        local wearRateSystemsCount = 0

        for systemKey, systemData in pairs(systems) do
            if systemData.enabled ~= false then
                local currentSystemCondition = math.max(math.min(systemData.condition or 1.0, 1.0), 0.0)
                local startSystemData = startSystems ~= nil and startSystems[systemKey] or nil
                local startSystemCondition = startCondition

                if type(startSystemData) == "table" then
                    startSystemCondition = math.max(math.min(startSystemData.condition or startCondition, 1.0), 0.0)
                elseif type(startSystemData) == "number" then
                    startSystemCondition = math.max(math.min(startSystemData, 1.0), 0.0)
                end

                local conditionDiff = math.max(startSystemCondition - currentSystemCondition, 0.0)
                local systemWearRate = conditionDiff / operatingTimeDiff
                totalWearRate = totalWearRate + systemWearRate
                wearRateSystemsCount = wearRateSystemsCount + 1
            end
        end

        if wearRateSystemsCount > 0 then
            wearRate = totalWearRate / wearRateSystemsCount
        else
            wearRate = nominalWearRate
        end
    end

    table.insert(self.overallAssessmentData, {'rms_report_overall_assessment_wear_rate',  wearRate})

    -- nominal wear rate
    table.insert(self.overallAssessmentData, {'rms_report_overall_assessment_nominal_wear_rate', nominalWearRate})

    -- expected residual life
    local effectiveWearRate = wearRate > 0 and wearRate or nominalWearRate
    local rul = effectiveWearRate > 0 and (math.max(currentCondition, 0.0) / effectiveWearRate) or 0

    table.insert(self.overallAssessmentData, {'rms_report_overall_assessment_rul', rul})

    -- system condition, in declared system order
    for _, systemL10nKey in ipairs(RealisticMechanicalSystems.SYSTEMS_ORDER) do
        local systemKey = RMS_Utils.getSystemKey(RealisticMechanicalSystems.SYSTEMS, systemL10nKey)
        local systemData = systems[systemKey]
        if type(systemData) == "table" and systemData.enabled ~= false then
            local systemCondition = math.max(math.min(systemData.condition or 1.0, 1.0), 0.0)
            local systemStress = math.max(math.min(systemData.stress or 0.0, 1.0), 0.0)
            table.insert(self.systemConditionData, {systemL10nKey, systemCondition, systemStress})
        end
    end

    -- vehicle specs
    local activeEffects = self.lastReport.conditionData.activeEffects or {}
    local nominalBatteryCapacityAh = RMS_Config.ELECTRICAL.BATTERY_NOMINAL_CAPACITY or 0
    local batterySoc = clampUnitRatio(self.lastReport.conditionData.batterySoc or 1)
    local batteryHealth = clampUnitRatio(1.0 + (getEffectValue(activeEffects, "BATTERY_HEALTH_MODIFIER") or 0))
    local alternatorHealth = clampUnitRatio(1.0 + (getEffectValue(activeEffects, "ALTERNATOR_HEALTH_MODIFIER") or 0))
    local thermostatHealth = clampUnitRatio(1.0 + (getEffectValue(activeEffects, "THERMOSTAT_HEALTH_MODIFIER") or 0))
    local radiatorHealth = clampUnitRatio(1.0 + (getEffectValue(activeEffects, "RADIATOR_HEALTH_MODIFIER") or 0))
    local fanClutchHealth = clampUnitRatio(1.0 + (getEffectValue(activeEffects, "FAN_CLUTCH_MODIFIER") or 0))

    ---Appends one spec row to the vehicle spec section
    -- @param table data spec row
    local function addVehicleSpec(data)
        table.insert(self.vehicleSpecData, data)
    end

    -- power
    local motor = self.vehicle:getMotor()
    local peakPowerHp = ((motor ~= nil and motor.peakMotorPower) or 0) * 1.36
    local currentPowerModifier = 1.0 + (getEffectValue(activeEffects, "ENGINE_TORQUE_MODIFIER") or 0)
    local currentPowerHp = math.max(peakPowerHp * currentPowerModifier, 0)
    addVehicleSpec({
        key = "rms_report_system_condition_power",
        kind = "pair",
        currentValue = currentPowerHp,
        nominalValue = peakPowerHp,
        ratio = peakPowerHp > 0 and (currentPowerHp / peakPowerHp) or 1.0,
        unit = "hp",
        stdVisible = true
    })

    -- brakes
    local brakesPowerModifier = 1.0 + (getEffectValue(activeEffects, "BRAKE_FORCE_MODIFIER") or 0)
    addVehicleSpec({
        key = "rms_report_system_condition_brakes",
        kind = "ratio",
        value = brakesPowerModifier,
        stdVisible = true
    })

    ---Appends a textual transmission spec row
    -- @param string titleKey l10n key of the row title
    -- @param string textKey l10n key of the row text
    -- @param float ratio ratio driving the row colour
    local function addTransmissionTextSpec(titleKey, textKey, ratio)
        addVehicleSpec({
            key = titleKey,
            kind = "text",
            textKey = textKey,
            ratio = clampUnitRatio(ratio),
            stdVisible = false
        })
    end

    addVehicleSpec({
        key = "rms_report_vehicle_spec_battery_charge",
        kind = "ratio",
        value = batterySoc,
        stdVisible = true
    })

    -- transmission, first matching effect wins and the rest are skipped
    local hasTransmissionIssues = false

    local transmissionSlipValue = getTransmissionEffectValue(activeEffects, "TRANSMISSION_SLIP_EFFECT")
    if transmissionSlipValue ~= nil and not hasTransmissionIssues then
        hasTransmissionIssues = true
        addTransmissionTextSpec(
            "rms_report_system_condition_transmission",
            transmissionSlipValue >= 1.0 and "rms_report_transmission_failed" or "rms_report_transmission_slipping",
            1.0 - transmissionSlipValue
        )
    end

    local gearShiftFailureValue = getTransmissionEffectValue(activeEffects, "GEAR_SHIFT_FAILURE_CHANCE")
    if gearShiftFailureValue ~= nil and not hasTransmissionIssues then
        hasTransmissionIssues = true
        addTransmissionTextSpec(
            "rms_report_system_condition_transmission",
            gearShiftFailureValue >= 1.0 and "rms_report_transmission_failed" or "rms_report_transmission_shifting_impaired",
            1.0 - gearShiftFailureValue
        )
    end

    local gearRejectionValue = getTransmissionEffectValue(activeEffects, "GEAR_REJECTION_CHANCE")
    if gearRejectionValue ~= nil and not hasTransmissionIssues then
        hasTransmissionIssues = true
        addTransmissionTextSpec(
            "rms_report_system_condition_transmission",
            gearRejectionValue <= 3.0 and "rms_report_transmission_failed" or "rms_report_transmission_gear_rejection",
            gearRejectionValue / 20.0
        )
    end

    local powershiftLagValue = getTransmissionEffectValue(activeEffects, "POWERSHIFT_ENGAGEMENT_LAG_AND_HARSH_EFFECT")
    if powershiftLagValue ~= nil and not hasTransmissionIssues then
        hasTransmissionIssues = true
        addTransmissionTextSpec(
            "rms_report_system_condition_transmission",
            powershiftLagValue >= 1.0 and "rms_report_transmission_failed" or "rms_report_transmission_shift_delay",
            1.0 - powershiftLagValue
        )
    end

    local cvtSlipValue = getTransmissionEffectValue(activeEffects, "CVT_SLIP_EFFECT")
    if cvtSlipValue ~= nil and not hasTransmissionIssues then
        hasTransmissionIssues = true
        addTransmissionTextSpec(
            "rms_report_system_condition_transmission",
            cvtSlipValue >= 1.0 and "rms_report_transmission_failed" or "rms_report_transmission_cvt_slipping",
            1.0 - cvtSlipValue
        )
    end

    local cvtRatioLimitValue = getTransmissionEffectValue(activeEffects, "CVT_MAX_RATIO_MODIFIER")
    if cvtRatioLimitValue ~= nil and not hasTransmissionIssues then
        hasTransmissionIssues = true
        addTransmissionTextSpec(
            "rms_report_system_condition_transmission",
            cvtRatioLimitValue >= 0.8 and "rms_report_transmission_failed" or "rms_report_transmission_cvt_ratio_limited",
            1.0 - cvtRatioLimitValue
        )
    end

    local cvtPressureDropValue = getTransmissionEffectValue(activeEffects, "CVT_PRESSURE_DROP_CHANCE")
    if cvtPressureDropValue ~= nil and not hasTransmissionIssues then
        hasTransmissionIssues = true
        addTransmissionTextSpec(
            "rms_report_system_condition_transmission",
            cvtPressureDropValue <= 0.1 and "rms_report_transmission_failed" or "rms_report_transmission_cvt_pressure_instability",
            cvtPressureDropValue / 2.0
        )
    end

    local transThermostatStuckValue = getTransmissionEffectValue(activeEffects, "TRANSMISSION_THERMOSTAT_STUCK_EFFECT")
    local transThermostatHealthValue = getTransmissionEffectValue(activeEffects, "TRANSMISSION_THERMOSTAT_HEALTH_MODIFIER")
    if (transThermostatStuckValue ~= nil or transThermostatHealthValue ~= nil) and not hasTransmissionIssues then
        hasTransmissionIssues = true
        addTransmissionTextSpec(
            "rms_report_system_condition_transmission",
            transThermostatStuckValue ~= nil and "rms_report_transmission_failed" or "rms_report_transmission_thermostat_degraded",
            transThermostatStuckValue ~= nil and 0.0 or (1.0 + transThermostatHealthValue)
        )
    end

    if not hasTransmissionIssues then
        addTransmissionTextSpec(
            "rms_report_system_condition_transmission",
            "rms_report_state_optimal",
            1.0
        )
    end

    local coolingEfficiencyModifier = math.min(thermostatHealth, radiatorHealth, fanClutchHealth)
    addVehicleSpec({
        key = "rms_report_system_condition_cooling",
        kind = "ratio",
        value = coolingEfficiencyModifier,
        stdVisible = false
    })

    local fuelConsumptionModifier = 1.0 + (getEffectValue(activeEffects, "FUEL_CONSUMPTION_MODIFIER") or 0)
    addVehicleSpec({
        key = "rms_report_system_condition_consumption",
        kind = "ratio",
        value = fuelConsumptionModifier,
        stdVisible = false,
        inverted = true,
        ideal = 100,
        low = 105,
        mid = 110,
        high = 130
    })

    if RMS_Breakdowns.BreakdownRegistry.HYDRAULIC_PUMP_MALFUNCTION.isApplicable(self.vehicle) then
        local hydraulicEfficiencyModifier = 1.0 + (getEffectValue(activeEffects, "HYDRAULIC_SPEED_MODIFIER") or 0)
        addVehicleSpec({
            key = "rms_report_system_condition_hydraulic",
            kind = "ratio",
            value = hydraulicEfficiencyModifier,
            stdVisible = false
        })
    end

    local nominalAlternatorCurrent = RMS_Config.ELECTRICAL.ALT_MAX_OUTPUT or 0
    local currentAlternatorCurrent = nominalAlternatorCurrent * alternatorHealth
    addVehicleSpec({
        key = "rms_report_vehicle_spec_max_alternator_current",
        kind = "pair",
        currentValue = currentAlternatorCurrent,
        nominalValue = nominalAlternatorCurrent,
        ratio = nominalAlternatorCurrent > 0 and (currentAlternatorCurrent / nominalAlternatorCurrent) or 1.0,
        unit = "A",
        stdVisible = false
    })

    local effectiveBatteryCapacityAh = nominalBatteryCapacityAh * batteryHealth
    addVehicleSpec({
        key = "rms_report_vehicle_spec_battery_capacity",
        kind = "pair",
        currentValue = effectiveBatteryCapacityAh,
        nominalValue = nominalBatteryCapacityAh,
        ratio = nominalBatteryCapacityAh > 0 and (effectiveBatteryCapacityAh / nominalBatteryCapacityAh) or batteryHealth,
        unit = "Ah",
        stdVisible = false
    })

    -- breakdowns and recommendations
    local reportMetrics = {
        visibleSelectableBreakdownsCount = 0,
        visibleSelectableActiveBreakdownsCount = 0,
        wearRate = wearRate,
        nominalWearRate = nominalWearRate,
        hasPoorQualityConsumablesBreakdown = false,
        isCompleteInspection = self.isCompleteInspection == true,
        inactivePoorPartsNames = {},
        inactiveQuickFixPartsNames = {}
    }
    local inactivePoorPartsSeen = {}
    local inactiveQuickFixSeen = {}

    -- breakdown ids listed from highest to lowest stage, ties kept deterministic
    local reportActiveBreakdowns = (self.lastReport.conditionData and self.lastReport.conditionData.activeBreakdowns) or {}
    local breakdownIds = {}
    for breakdownId, _ in pairs(reportActiveBreakdowns) do
        table.insert(breakdownIds, breakdownId)
    end
    table.sort(breakdownIds, function(a, b)
        local aStage = reportActiveBreakdowns[a] ~= nil and (reportActiveBreakdowns[a].stage or 0) or 0
        local bStage = reportActiveBreakdowns[b] ~= nil and (reportActiveBreakdowns[b].stage or 0) or 0
        if aStage ~= bStage then
            return aStage > bStage
        end
        return tostring(a) < tostring(b)
    end)

    for _, breakdownId in ipairs(breakdownIds) do
        local breakdownData = reportActiveBreakdowns[breakdownId]
        local registryEntry = RMS_Breakdowns.BreakdownRegistry[breakdownId]

        if breakdownId == "MAINTENANCE_WITH_POOR_QUALITY_CONSUMABLES" then
            reportMetrics.hasPoorQualityConsumablesBreakdown = true
        end

        if breakdownData ~= nil and breakdownData.isVisible and registryEntry ~= nil and registryEntry.isSelectable then
            reportMetrics.visibleSelectableBreakdownsCount = reportMetrics.visibleSelectableBreakdownsCount + 1
            local stage = breakdownData.stage or 1
            local stageData = registryEntry.stages and registryEntry.stages[stage]
            if stageData ~= nil then
                local partKey = registryEntry.part or registryEntry.system
                local partText = partKey ~= nil and g_i18n:getText(partKey) or tostring(breakdownId)

                if breakdownData.isActive ~= false then
                    reportMetrics.visibleSelectableActiveBreakdownsCount = reportMetrics.visibleSelectableActiveBreakdownsCount + 1
                elseif breakdownData.source == RealisticMechanicalSystems.BREAKDOWN_SOURCES.POOR_PARTS then
                    appendUniqueText(reportMetrics.inactivePoorPartsNames, inactivePoorPartsSeen, partText)
                elseif breakdownData.source == RealisticMechanicalSystems.BREAKDOWN_SOURCES.QUICK_FIX then
                    appendUniqueText(reportMetrics.inactiveQuickFixPartsNames, inactiveQuickFixSeen, partText)
                end

                local severityText = g_i18n:getText(stageData.severity)
                local descriptionText = g_i18n:getText(stageData.description)

                if breakdownData.isActive == false and breakdownData.source == RealisticMechanicalSystems.BREAKDOWN_SOURCES.QUICK_FIX then
                    severityText = g_i18n:getText("rms_breakdowns_quick_fix_stage")
                    descriptionText = g_i18n:getText("rms_breakdowns_temporarily_repaired_description")
                elseif breakdownData.isActive == false and breakdownData.source == RealisticMechanicalSystems.BREAKDOWN_SOURCES.POOR_PARTS then
                    severityText = g_i18n:getText("rms_breakdowns_defected_parts_stage")
                    descriptionText = g_i18n:getText("rms_breakdowns_defected_parts_detected_description")
                end

                table.insert(self.breakdownsData, {
                    title = partText,
                    severity = severityText,
                    text = descriptionText,
                    stage = stage,
                    isActive = breakdownData.isActive ~= false
                })
            end
        end
    end
    self.reportSummaryBreakdowns:setText(tostring(reportMetrics.visibleSelectableBreakdownsCount))

    if #self.breakdownsData == 0 then
        table.insert(self.breakdownsData, {title = g_i18n:getText("rms_log_inspection_desc_no_breakdowns"), text = "", severity = ""})
    end

    self.recommendationsData = buildRecommendationsData(self.vehicle, self.lastReport, reportMetrics)

    self:renderAssessmentRows()
    self:renderSystemRows()
    self:renderSpecRows()

    self.breakdownsTable:setDataSource(self)
    self.recommendationsTable:setDataSource(self)
    self.breakdownsTable:reloadData()
    self.recommendationsTable:reloadData()

    -- every value is written by now, so each pill can close on the one it wraps
    RMS_Utils.fitValuePills(self)
end

---Returns the row count of the requested report note list
-- @param table list list element
-- @param integer section section index
-- @return integer count row count
function RMS_ReportDialog:getNumberOfItemsInSection(list, section)
    if list == self.breakdownsTable then
        return #self.breakdownsData
    elseif list == self.recommendationsTable then
        return #self.recommendationsData
    end

    return 0
end

---Fills one note cell, dispatching on the list it belongs to
-- @param table list list element
-- @param integer section section index
-- @param integer index row index
-- @param table cell cell element
function RMS_ReportDialog:populateCellForItemInSection(list, section, index, cell)
    if list == self.breakdownsTable then
        self:populateBreakdownsCell(index, cell)
    elseif list == self.recommendationsTable then
        self:populateRecommendationsCell(index, cell)
    end
end

---Returns the thresholds of every measured figure, scaled by the reliability the report recorded
-- @return table config thresholds keyed by l10n key
function RMS_ReportDialog:getAssessmentConfig()
    local spec = self.vehicle.spec_RealisticMechanicalSystems
    local maxMtbf = RMS_Config.CORE.BREAKDOWN_PROBABILITIES.MAX_MTBF / 60
    local minMtbf = RMS_Config.CORE.BREAKDOWN_PROBABILITIES.MIN_MTBF / 60
    local diffMtbf = maxMtbf - minMtbf
    local minCrit = RMS_Config.CORE.BREAKDOWN_PROBABILITIES.CRITICAL_MIN
    local maxCrit = RMS_Config.CORE.BREAKDOWN_PROBABILITIES.CRITICAL_MAX
    local critDiff = maxCrit - minCrit
    local reportReliability = math.max(tonumber(self.lastReport.conditionData.reliability or spec.reliability) or 1.0, 0.001)
    local nominalWearRate = RMS_Config.CORE.BASE_SYSTEMS_WEAR / reportReliability
    local rul = 1 / nominalWearRate

    return {
        rms_report_overall_assessment_mtbf = {ideal = maxMtbf, high = diffMtbf * 0.66, mid = diffMtbf * 0.33, low = minMtbf, isPercent = false},
        rms_report_overall_assessment_rul = {ideal = rul, high = rul * 0.66, mid = rul * 0.33, low = rul * 0.1, isPercent = false},
        rms_report_overall_assessment_wear_rate = {inverted = true, ideal = nominalWearRate, high = nominalWearRate * 1.1, mid = nominalWearRate * 1.2, low = nominalWearRate * 1.3, isPercent = true},
        rms_report_overall_assessment_nominal_wear_rate = {
            inverted = true,
            ideal = nominalWearRate,
            high = nominalWearRate * 1.1,
            mid = nominalWearRate * 1.2,
            low = nominalWearRate * 1.3,
            isPercent = true
        },
        rms_report_overall_assessment_crit_fail_risk = {inverted = true, ideal = minCrit, high = critDiff * 0.33, mid = critDiff * 0.66, low = maxCrit * 1.3, isPercent = true}
    }
end

---Paints the measured figures of the assessment card, one row per figure
function RMS_ReportDialog:renderAssessmentRows()
    local config = self:getAssessmentConfig()

    for index, labelElement in ipairs(self.assessmentLabel) do
        local data = self.overallAssessmentData[index]
        local valueElement = self.assessmentValue[index]
        labelElement.parent:setVisible(data ~= nil)

        if data ~= nil then
            local key = data[1]
            local cfg = config[key] or ASSESSMENT_DEFAULT_CONFIG
            local value = data[2]

            local valueText
            if self.isCompleteInspection then
                valueText = cfg.isPercent and string.format("%.2f %%", value * 100) or string.format("%.1f", value)
                if cfg.inverted then
                    valueElement:setTextColor(RMS_Utils.getValueColorInverted(value, cfg.ideal, cfg.low, cfg.mid, cfg.high, true))
                else
                    valueElement:setTextColor(RMS_Utils.getValueColor(value, cfg.ideal, cfg.high, cfg.mid, cfg.low, true))
                end
            else
                valueText = g_i18n:getText("rms_report_state_not_available")
                valueElement:setTextColor(unpack(RMS_Utils.COLOR.TEXT_DIM))
            end

            labelElement:setTextColor(unpack(self.isCompleteInspection and RMS_Utils.COLOR.TEXT or RMS_Utils.COLOR.TEXT_DIM))
            RMS_Utils.fitRowValue(labelElement, self.assessmentPill[index], valueElement, g_i18n:getText(key), valueText)
        end
    end

    self.assessmentLabel[1].parent.parent:invalidateLayout()
end

---Paints one gauge per enabled system, with its condition and its failure risk
function RMS_ReportDialog:renderSystemRows()
    for index, nameElement in ipairs(self.systemName) do
        local data = self.systemConditionData[index]
        local valueElement = self.systemValue[index]
        local riskElement = self.systemRisk[index]
        nameElement.parent:setVisible(data ~= nil)

        if data ~= nil then
            local condition = clampUnitRatio(data[2])
            local percent = condition * 100
            local stress = data[3] or 0
            local risk = clampUnitRatio(stress / math.max(condition, 0.001)) * 100
            nameElement:setText(g_i18n:getText(data[1]))

            if self.isCompleteInspection then
                valueElement:setText(string.format("%.1f %%", percent))
                riskElement:setText(getStressLabel(stress, condition))
                riskElement:setTextColor(RMS_Utils.getValueColorInverted(risk, 20, 40, 60, 80, true))
            else
                valueElement:setText(RMS_Utils.getValueLabel(percent, 80, 60, 40, 20, unpack(self:getStateTexts())))
                riskElement:setText(g_i18n:getText("rms_report_state_not_available"))
                riskElement:setTextColor(unpack(RMS_Utils.COLOR.TEXT_DIM))
            end
            valueElement:setTextColor(RMS_Utils.getValueColor(percent, 95, 80, 60, 40, self.isCompleteInspection))
        end
    end

    self.systemName[1].parent.parent:invalidateLayout()
end

---Returns the five condition labels a partial inspection falls back on
-- @return table texts localized labels, best first
function RMS_ReportDialog:getStateTexts()
    return {
        g_i18n:getText("rms_spec_state_excellent"),
        g_i18n:getText("rms_spec_state_good"),
        g_i18n:getText("rms_spec_state_normal"),
        g_i18n:getText("rms_spec_state_bad"),
        g_i18n:getText("rms_spec_state_terrible")
    }
end

---Paints what the machine still delivers, against the figures it left the factory with
function RMS_ReportDialog:renderSpecRows()
    for index, labelElement in ipairs(self.specLabel) do
        local data = self.vehicleSpecData[index]
        local valueElement = self.specValue[index]
        labelElement.parent:setVisible(data ~= nil)

        if data ~= nil then
            local kind = data.kind or "ratio"
            local percent = clampUnitRatio(data.ratio or data.value or 0) * 100
            local cfg = {
                inverted = data.inverted == true,
                ideal = data.ideal or 99,
                high = data.high or 90,
                mid = data.mid or 70,
                low = data.low or 30
            }
            local isReadable = self.isCompleteInspection or data.stdVisible ~= false

            local valueText
            labelElement:setTextColor(unpack(isReadable and RMS_Utils.COLOR.TEXT or RMS_Utils.COLOR.TEXT_DIM))

            if not isReadable then
                valueText = g_i18n:getText("rms_report_state_not_available")
                valueElement:setTextColor(unpack(RMS_Utils.COLOR.TEXT_DIM))
            else
                local stateTexts = {
                    g_i18n:getText("rms_report_state_optimal"),
                    g_i18n:getText("rms_report_state_normal"),
                    g_i18n:getText("rms_report_state_degraded"),
                    g_i18n:getText("rms_report_state_impaired"),
                    g_i18n:getText("rms_report_state_critical")
                }
                if kind == "text" then
                    valueText = g_i18n:getText(data.textKey or "")
                elseif kind == "pair" then
                    valueText = string.format("%.1f | %.1f %s", data.currentValue or 0, data.nominalValue or 0, data.unit or "")
                elseif self.isCompleteInspection or data.key == "rms_report_vehicle_spec_battery_charge" then
                    valueText = string.format("%.1f %%", percent)
                elseif cfg.inverted then
                    valueText = RMS_Utils.getValueLabelInverted(percent, cfg.ideal, cfg.low, cfg.mid, cfg.high, unpack(stateTexts))
                else
                    valueText = RMS_Utils.getValueLabel(percent, cfg.ideal, cfg.high, cfg.mid, cfg.low, unpack(stateTexts))
                end

                if cfg.inverted then
                    valueElement:setTextColor(RMS_Utils.getValueColorInverted(percent, cfg.ideal, cfg.low, cfg.mid, cfg.high, self.isCompleteInspection))
                else
                    valueElement:setTextColor(RMS_Utils.getValueColor(percent, cfg.ideal, cfg.high, cfg.mid, cfg.low, self.isCompleteInspection))
                end
            end

            RMS_Utils.fitRowText(labelElement, valueElement, g_i18n:getText(data.key), valueText)
        end
    end

    self.specLabel[1].parent.parent:invalidateLayout()
end

---Fills one detected breakdown, its part and severity over its description
-- @param integer index row index
-- @param table cell cell element
function RMS_ReportDialog:populateBreakdownsCell(index, cell)
    RMS_Utils.applyScrollSpeed(cell)
    local data = self.breakdownsData[index] or {}
    local stageColor = data.isActive == false and RMS_Utils.COLOR.TEXT_DIM or RMS_Utils.COLOR.STAGE[data.stage or 1]
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
-- @param integer index row index
-- @param table cell cell element
function RMS_ReportDialog:populateRecommendationsCell(index, cell)
    RMS_Utils.applyScrollSpeed(cell)
    local rowElement = cell:getAttribute("reportRecRow")

    rowElement:setText(self.recommendationsData[index] or "")
end


---Closes the dialog
function RMS_ReportDialog:onClickBack()
    self:close()
end

---Selects the technical record tab in the report shell
function RMS_ReportDialog:onCreate()
    -- The report is a detail view of the technical record, so its tab stays lit.
    RMS_Utils.mirrorSelectionToChildren(self.reportTechnicalTab)
    self.reportTechnicalTab:setSelected(true)
    RMS_Utils.applyScrollSpeed(self.dialogElement)
end


---Opens the dialog and subscribes to balance changes
function RMS_ReportDialog:onOpen()
    RMS_ReportDialog:superClass().onOpen(self)

    g_messageCenter:subscribe(MessageType.MONEY_CHANGED, self.updateScreen, self)
end


---Closes the dialog and releases its subscriptions
function RMS_ReportDialog:onClose()
    self.vehicle = nil
    g_messageCenter:unsubscribeAll(self)

    RMS_ReportDialog:superClass().onClose(self)
end
