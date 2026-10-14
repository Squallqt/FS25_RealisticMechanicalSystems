-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---Dialog presenting a stored inspection report of a vehicle
RMS_ReportDialog = {}
RMS_ReportDialog.INSTANCE = nil

local RMS_ReportDialog_mt = Class(RMS_ReportDialog, MessageDialog)
local modDirectory = g_currentModDirectory

-- extra wear percent under which wear is normal, over which much faster, and to name a cause
local WEAR_NORMAL_PERCENT = 10
local WEAR_HIGH_PERCENT = 30
local WEAR_CAUSE_MIN_PERCENT = 1
-- name of each wear cause by its statistics alias, as the mod's tips name it
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
    wef = "rms_tutorial_wet_weather_title",
    ltf = "rms_report_wear_lights",
    crf = "rms_tutorial_cranking_title",
    slf = "rms_tutorial_steering_title",
    bmf = "rms_report_wear_braking",
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
    prf = "rms_tutorial_pto_raised_title"
}
RMS_ReportDialog.WEAR_CAUSE_TEXTS = WEAR_CAUSE_TEXTS
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
    -- wear much faster than normal, as the wear block of the same report measures it, complete inspection only
    {
        l10nKey = "rms_report_recommendation_operating_conditions",
        check = function(vehicle, reportEntry, metrics)
            if metrics == nil or not metrics.isCompleteInspection then
                return false
            end
            return (reportEntry.conditionData.wearExcess or 0) * 100 > WEAR_HIGH_PERCENT
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
                    params = {getSystemDisplayName(vehicle, targetSystemKey)}
                }
            end

            return false
        end
    },
    -- system the major service adjustments reach, failure risk high, complete inspection only
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

            local highestRisk = 0
            local targetSystemKey = nil
            local systems = reportEntry.conditionData.systems or {}

            for _, systemName in ipairs(RealisticMechanicalSystems.getMajorServiceSystems(vehicle)) do
                local systemData = systems[systemName]
                if type(systemData) == "table" and systemData.enabled ~= false then
                    local systemCondition = math.max(tonumber(systemData.condition) or 0, 0.001)
                    local risk, severity = RMS_Utils.getSystemBreakdownRisk(vehicle, systemData, 3600000, systemName)
                    local tier = RMS_Utils.getBreakdownRiskTier(risk, severity)

                    if systemCondition >= 0.4 and tier ~= nil and tier >= 3 and risk > highestRisk then
                        highestRisk = risk
                        targetSystemKey = systemName
                    end
                end
            end

            if targetSystemKey ~= nil then
                return {
                    params = {getSystemDisplayName(vehicle, targetSystemKey), RMS_Utils.formatHours(
                        vehicle:getMaintenanceLevelInterval(RealisticMechanicalSystems.MAINTENANCE_TYPES.PREVENTIVE))}
                }
            end

            return false
        end
    }
}

local log_dbg = RMS_Utils.createLogger("[RMS_REPORT_DIALOG]")

---Returns the localized text of a key, or the fallback
local function getTextOrFallback(key, fallback)
    local text = g_i18n:getText(key)
    if text == nil or text == "" or text == key then
        return fallback
    end
    return text
end

---Returns the localized display name of a system on a vehicle
-- @param table vehicle vehicle
-- @param string systemKey system key
-- @return string name localized system name, the key itself when unknown
function getSystemDisplayName(vehicle, systemKey)
    local normalizedKey = string.lower(tostring(systemKey or ""))

    for enumKey, l10nKey in pairs(RealisticMechanicalSystems.SYSTEMS or {}) do
        if string.lower(enumKey) == normalizedKey then
            return getTextOrFallback(RMS_Utils.getSystemLabel(vehicle, l10nKey), tostring(systemKey))
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
local function getEffectValue(activeEffects, effectId)
    local effect = activeEffects[effectId]
    if type(effect) == "table" and type(effect.value) == "number" then
        return effect.value
    end
    return nil
end

---Clamps a value to the 0 to 1 range
local function clampUnitRatio(value)
    return math.max(math.min(tonumber(value) or 0, 1), 0)
end

---Returns the numeric value of an active effect, the table possibly nil
local function getTransmissionEffectValue(activeEffects, effectId)
    local effect = activeEffects ~= nil and activeEffects[effectId] or nil
    if type(effect) == "table" and type(effect.value) == "number" then
        return effect.value
    end
    return nil
end

---Appends a text to the list unless empty or already there
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

---Evaluates every recommendation rule into a bullet list
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
function RMS_ReportDialog.show(vehicle, logEntry, parentDialog)

    if logEntry == nil or not RealisticMechanicalSystems.getIsLogEntryHasReport(logEntry) then
        log_dbg("Invalid log entry")
        return
    end

    if RMS_ReportDialog.INSTANCE == nil then RMS_ReportDialog.register() end
    if vehicle == nil or vehicle.spec_RealisticMechanicalSystems == nil then return end
    
    local dialog = RMS_ReportDialog.INSTANCE
    dialog.vehicle = vehicle
    dialog.parentDialog = parentDialog
    dialog.workshopContext = parentDialog ~= nil and (parentDialog == RMS_WorkshopDialog.INSTANCE
        or parentDialog.workshopContext == true)
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

---Builds the technical sheet of a vehicle from what a report recorded
-- @param table vehicle vehicle
-- @param table conditionData condition the report recorded
-- @return table rows sheet rows in display order
function RMS_ReportDialog.buildVehicleSpecs(vehicle, conditionData)
    local spec = vehicle.spec_RealisticMechanicalSystems
    local systems = conditionData.systems or {}
    local rows = {}

    local activeEffects = conditionData.activeEffects or {}
    local nominalBatteryCapacityAh = spec.electricalRating.batteryCapacityAh
    local batterySoc = clampUnitRatio(conditionData.batterySoc or 1)
    local batteryHealth = clampUnitRatio(1.0 + (getEffectValue(activeEffects, "BATTERY_HEALTH_MODIFIER") or 0))
    local alternatorHealth = clampUnitRatio(1.0 + (getEffectValue(activeEffects, "ALTERNATOR_HEALTH_MODIFIER") or 0))
    local thermostatHealth = clampUnitRatio(1.0 + (getEffectValue(activeEffects, "THERMOSTAT_HEALTH_MODIFIER") or 0))
    local radiatorHealth = clampUnitRatio(1.0 + (getEffectValue(activeEffects, "RADIATOR_HEALTH_MODIFIER") or 0))
    local fanClutchHealth = clampUnitRatio(1.0 + (getEffectValue(activeEffects, "FAN_CLUTCH_MODIFIER") or 0))

    ---Appends one spec row to the vehicle spec section
    local function addVehicleSpec(data)
        table.insert(rows, data)
    end

    -- power
    local motor = vehicle:getMotor()
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
    local function addTransmissionTextSpec(titleKey, textKey, ratio)
        addVehicleSpec({
            key = titleKey,
            kind = "text",
            textKey = textKey,
            ratio = clampUnitRatio(ratio),
            stdVisible = false
        })
    end

    -- an electric has two batteries and a 24 V machine two in series
    local isElectric = spec.isElectricVehicle
    local batteryChargeKey, batteryCapacityKey = "rms_report_vehicle_spec_battery_charge", "rms_report_vehicle_spec_battery_capacity"
    if isElectric then
        batteryChargeKey = "rms_report_vehicle_spec_auxiliary_battery_charge"
        batteryCapacityKey = "rms_report_vehicle_spec_auxiliary_battery_capacity"
    elseif spec.electricalRating.seriesBatteries > 1 then
        batteryChargeKey = "rms_report_vehicle_spec_battery_24v_charge"
        batteryCapacityKey = "rms_report_vehicle_spec_battery_24v_capacity"
    end
    addVehicleSpec({
        key = batteryChargeKey,
        kind = "ratio",
        value = batterySoc,
        isAlwaysMeasured = true,
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
        key = isElectric and "rms_report_system_condition_energy_consumption" or "rms_report_system_condition_consumption",
        kind = "ratio",
        value = fuelConsumptionModifier,
        stdVisible = false,
        inverted = true,
        ideal = 100,
        low = 105,
        mid = 110,
        high = 130
    })

    if RMS_Breakdowns.BreakdownRegistry.HYDRAULIC_PUMP_MALFUNCTION.isApplicable(vehicle) then
        local hydraulicEfficiencyModifier = 1.0 + (getEffectValue(activeEffects, "HYDRAULIC_SPEED_MODIFIER") or 0)
        addVehicleSpec({
            key = "rms_report_system_condition_hydraulic",
            kind = "ratio",
            value = hydraulicEfficiencyModifier,
            stdVisible = false
        })
    end

    if isElectric then
        -- what the traction battery still holds, from the wear and the failed cells the report recorded
        local capacityShare = RMS_ElectricDrive.getCapacityShare(clampUnitRatio(systems.fuel.condition),
            getEffectValue(activeEffects, "TRACTION_BATTERY_CAPACITY_MODIFIER") or 0)
        addVehicleSpec({
            key = "rms_report_vehicle_spec_traction_battery_capacity",
            kind = "pair",
            currentValue = spec.tractionBatteryNominalCapacity * capacityShare,
            nominalValue = spec.tractionBatteryNominalCapacity,
            ratio = capacityShare,
            unit = "kWh",
            stdVisible = true
        })
    else
        local nominalAlternatorCurrent = spec.electricalRating.alternatorA
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
    end

    local effectiveBatteryCapacityAh = nominalBatteryCapacityAh * batteryHealth
    addVehicleSpec({
        key = batteryCapacityKey,
        kind = "pair",
        currentValue = effectiveBatteryCapacityAh,
        nominalValue = nominalBatteryCapacityAh,
        ratio = nominalBatteryCapacityAh > 0 and (effectiveBatteryCapacityAh / nominalBatteryCapacityAh) or batteryHealth,
        unit = "Ah",
        stdVisible = false
    })

    return rows
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

    -- identity band: report number, then what dates the reading
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
        string.format("%s (%s)", g_i18n:getText(self.lastReport.type),
            RMS_Utils.formatServiceOption(self.vehicle, self.lastReport.type, self.lastReport.optionOne)),
        g_i18n:getText(self.lastReport.location),
        string.format("%d %s", self.lastReport.conditionData.age or 0, g_i18n:getText("rms_ws_age_unit")),
        RMS_Utils.formatHours(self.lastReport.conditionData.operatingHours),
        "ODO " .. RMS_Utils.formatOdometerKilometers(self.lastReport.conditionData.odometerKilometers)
    }, " · "), nil, nil, true)

    -- overall assessment: condition and service
    local condition = self.lastReport.conditionData.condition or 1.0
    local service = self.lastReport.conditionData.service or 1.0
    self.reportSummaryCondition:setText(RMS_Utils.formatCondition(condition, self.isCompleteInspection))
    self.reportSummaryCondition:setTextColor(RMS_Utils.getConditionColor(condition, self.isCompleteInspection))
    self.reportSummaryService:setText(RMS_Utils.formatService(service, self.isCompleteInspection))
    self.reportSummaryService:setTextColor(RMS_Utils.getServiceColor(service, self.isCompleteInspection))

    -- the assessment comes from the measurements of this inspection
    local systems = self.lastReport.conditionData.systems or {}
    local overallRiskTier = nil
    for systemKey, systemData in pairs(systems) do
        local probability, severity = RMS_Utils.getSystemBreakdownRisk(self.vehicle, systemData, 3600000, systemKey)
        local tier = RMS_Utils.getBreakdownRiskTier(probability, severity)
        if tier ~= nil then overallRiskTier = math.max(overallRiskTier or 0, tier) end
    end

    table.insert(self.overallAssessmentData, {'rms_ws_label_reliability', RMS_Utils.formatReliability(spec.reliability),
        {RMS_Utils.getReliabilityColor(spec.reliability)}})
    table.insert(self.overallAssessmentData, {'rms_ws_label_service_access', RMS_Utils.formatServiceAccess(self.vehicle),
        {RMS_Utils.getServiceAccessColor(self.vehicle)}})
    table.insert(self.overallAssessmentData, {'rms_report_breakdown_risk_title', RMS_Utils.formatBreakdownRisk(overallRiskTier),
        overallRiskTier ~= nil and {RMS_Utils.getValueColorInverted(overallRiskTier, 1, 1, 2, 2, false)} or RMS_Utils.COLOR.TEXT_DIM})

    -- system condition, in declared system order
    for _, systemL10nKey in ipairs(RealisticMechanicalSystems.SYSTEMS_ORDER) do
        local systemKey = RMS_Utils.getSystemKey(RealisticMechanicalSystems.SYSTEMS, systemL10nKey)
        local systemData = systems[systemKey]
        if type(systemData) == "table" and systemData.enabled ~= false then
            local systemCondition = math.max(math.min(systemData.condition or 1.0, 1.0), 0.0)
            local probability, severity = RMS_Utils.getSystemBreakdownRisk(self.vehicle, systemData, 3600000, systemKey)
            table.insert(self.systemConditionData, {systemL10nKey, systemCondition, RMS_Utils.getBreakdownRiskTier(probability, severity)})
        end
    end

    self.vehicleSpecData = RMS_ReportDialog.buildVehicleSpecs(self.vehicle, self.lastReport.conditionData)

    -- breakdowns and recommendations
    local reportMetrics = {
        visibleSelectableBreakdownsCount = 0,
        visibleSelectableActiveBreakdownsCount = 0,
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
                local descriptionText = g_i18n:getText(RMS_Breakdowns.getStageDescription(self.vehicle, stageData))

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
    self:renderWear()
    self:renderSystemRows()
    self:renderSpecRows()

    self.breakdownsTable:setDataSource(self)
    self.recommendationsTable:setDataSource(self)
    self.breakdownsTable:reloadData()
    self.recommendationsTable:reloadData()

    -- every value is written by now, so each pill can close on the one it wraps
    RMS_Utils.fitValuePills(self)
    self:updateFocusLinks()
end

---Chains the focus under the tab selector
function RMS_ReportDialog:updateFocusLinks()
    self.focusEntry = RMS_Utils.linkFocusColumns(self.workshopTabPaging, {{{self.breakdownsTable}}, {{self.recommendationsTable}}})
    RMS_Utils.keepFocusShown(self.focusEntry)
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

---Paints the inspection assessment
function RMS_ReportDialog:renderAssessmentRows()
    for index, labelElement in ipairs(self.assessmentLabel) do
        local data = self.overallAssessmentData[index]
        local valueElement = self.assessmentValue[index]
        labelElement.parent:setVisible(data ~= nil)
        if data ~= nil then
            local isAvailable = data[1] ~= "rms_report_breakdown_risk_title" or self.isCompleteInspection
            local valueText = isAvailable and data[2] or g_i18n:getText("rms_report_state_not_available")
            labelElement:setTextColor(unpack(isAvailable and RMS_Utils.COLOR.TEXT or RMS_Utils.COLOR.TEXT_DIM))
            valueElement:setTextColor(unpack(isAvailable and (data[3] or RMS_Utils.COLOR.TEXT) or RMS_Utils.COLOR.TEXT_DIM))
            RMS_Utils.fitRowValue(labelElement, self.assessmentPill[index], valueElement, g_i18n:getText(data[1]), valueText)
        end
    end
    self.assessmentLabel[1].parent.parent:invalidateLayout()
end

---Returns the colour of an extra wear
local function getWearColor(percent)
    return RMS_Utils.getValueColorInverted(percent, WEAR_NORMAL_PERCENT, WEAR_NORMAL_PERCENT, WEAR_HIGH_PERCENT, 100, false)
end

---Writes the extra wear of the machine and its three main causes
function RMS_ReportDialog:renderWear()
    local data = self.lastReport.conditionData
    self.wearBlock:setVisible(data.wearExcess ~= nil)
    if data.wearExcess == nil then
        return
    end

    -- the causes the player knows under one name are summed
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
        -- the native formatter cuts whole numbers down: the pace is rounded first
        self.wearValue:setText(string.format(g_i18n:getText("rms_report_wear_percent"), g_i18n:formatNumber(MathUtil.round(percent), 0)))
    end
    self.wearValue:setTextColor(getWearColor(percent))

    for index, labelElement in ipairs(self.wearCauseLabel) do
        local cause, valueElement = causes[index], self.wearCauseValue[index]
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
        self.wearCauseLabel[1]:setText(g_i18n:getText("rms_report_wear_no_cause"))
    end
end

---Paints one gauge per enabled system
function RMS_ReportDialog:renderSystemRows()
    for index, nameElement in ipairs(self.systemName) do
        local data = self.systemConditionData[index]
        local valueElement = self.systemValue[index]
        local riskElement = self.systemRisk[index]
        nameElement.parent:setVisible(data ~= nil)

        if data ~= nil then
            local condition = clampUnitRatio(data[2])
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

    self.systemName[1].parent.parent:invalidateLayout()
end

---Paints what the machine still delivers against its factory figures
function RMS_ReportDialog:renderSpecRows()
    for index, labelElement in ipairs(self.specLabel) do
        local data = self.vehicleSpecData[index]
        local valueElement = self.specValue[index]
        labelElement.parent:setVisible(data ~= nil)

        if data ~= nil then
            local kind = data.kind or "ratio"
            local ratio = tonumber(data.ratio or data.value) or 0
            -- a consumption reads worse as it rises and is not capped
            local percent = (data.inverted == true and math.max(ratio, 0) or clampUnitRatio(ratio)) * 100
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
                elseif self.isCompleteInspection or data.isAlwaysMeasured then
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

---Fills one detected breakdown
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

---
function RMS_ReportDialog:onClickSummaryTab()
    RMS_WorkshopDialog.selectTabFromChildDialog(self, RMS_WorkshopDialog.TAB.SUMMARY)
end

---
function RMS_ReportDialog:onClickDiagnosticTab()
    RMS_WorkshopDialog.selectTabFromChildDialog(self, RMS_WorkshopDialog.TAB.DIAGNOSTIC)
end

---
function RMS_ReportDialog:onClickInterventionsTab()
    RMS_WorkshopDialog.selectTabFromChildDialog(self, RMS_WorkshopDialog.TAB.INTERVENTIONS)
end

---
function RMS_ReportDialog:onClickTechnicalTab()
    RMS_WorkshopDialog.selectTabFromChildDialog(self, RMS_WorkshopDialog.TAB.TECHNICAL)
end

---
function RMS_ReportDialog:onWorkshopTabPagingChanged()
    RMS_WorkshopDialog.onChildTabPagingChanged(self)
end

---Selects the technical record tab
function RMS_ReportDialog:onCreate()
    -- the report details the technical record, whose tab stays lit
    RMS_Utils.mirrorSelectionToChildren(self.workshopNavTabs[4])
    self.workshopNavTabs[4]:setSelected(true)
    RMS_Utils.applyScrollSpeed(self.dialogElement)
end


---Opens the dialog and subscribes to balance changes
function RMS_ReportDialog:onOpen()
    RMS_ReportDialog:superClass().onOpen(self)

    RMS_WorkshopDialog.initializeChildTabPaging(self, RMS_WorkshopDialog.TAB.TECHNICAL)

    RMS_Utils.resetScrollingTexts(self.dialogElement)
    g_messageCenter:subscribe(MessageType.MONEY_CHANGED, self.updateScreen, self)

    self:updateFocusLinks()
    FocusManager:setFocus(self.focusEntry)
end


---Closes the dialog and releases its subscriptions
function RMS_ReportDialog:onClose()
    self.vehicle = nil
    self.parentDialog = nil
    self.workshopContext = nil
    g_messageCenter:unsubscribeAll(self)

    RMS_ReportDialog:superClass().onClose(self)
end
