-- Copyright © 2026 Squallqt. All rights reserved.

---What each intervention of the workshop offers, and how it starts
RMS_WorkshopOrders = {}

local LEVEL_FLUIDS = {
    { circuit = "engineOil", nameKey = "rms_fluid_hud_engineOil" },
    { circuit = "transmissionOil", nameKey = "rms_fluid_circuit_transmissionOil" },
    { circuit = "hydraulicFluid", nameKey = "rms_fluid_circuit_hydraulicFluid" },
    { circuit = "coolant", nameKey = "rms_fluid_hud_coolant" }
}

---Returns a cell maker giving the same text to every choice
-- @param string key l10n key of the text
-- @return function getCell cell maker
local function every(key)
    return function()
        return g_i18n:getText(key), 2
    end
end

---Returns the cell of a share: its percentage and its level
-- @param float value share, 0 to 1
-- @return string text text of the cell
-- @return integer level level of the cell, 0 to 2
local function shareCell(value)
    if value <= 0 then
        return "-", 0
    end
    return string.format("%d%%", math.floor(value * 100 + 0.5)), value >= 1 and 2 or 1
end

---Returns the text naming an oil circuit, the common sump by its own name
-- @param table vehicle vehicle
-- @param string circuit fluid circuit
-- @return string? text name of the circuit, nil for a circuit without a level row
local function getOilName(vehicle, circuit)
    if circuit == "transmissionOil" and RMS_Fluids.getSumpCircuit(vehicle, "hydraulicFluid") == "transmissionOil" then
        return g_i18n:getText("rms_fluid_hud_transmissionHydraulic")
    end
    for _, fluid in ipairs(LEVEL_FLUIDS) do
        if fluid.circuit == circuit then
            return g_i18n:getText(fluid.nameKey)
        end
    end
end

---Returns the service interval of the clock changing a circuit
-- @param table vehicle vehicle
-- @param string circuit fluid circuit
-- @return string text interval, empty without a clock
local function getIntervalText(vehicle, circuit)
    for _, clock in ipairs(vehicle:getServiceClocks()) do
        if RMS_Utils.getKeyByValue(clock.circuits, circuit) ~= nil then
            local _, interval = vehicle:getServiceClockHours(clock)
            return string.format(g_i18n:getText("rms_ws_levels_interval"),
                RMS_Utils.formatServiceDeadline({ interval = interval, months = clock.months }, true))
        end
    end
    return ""
end

---Returns how often a maintenance level comes against the lightest one
-- @param table vehicle vehicle
-- @param string level maintenance level
-- @param string lightest lightest maintenance level
-- @return string text frequency
local function getFrequencyText(vehicle, level, lightest)
    local interval = vehicle:getMaintenanceLevelInterval(level)
    local ratio = interval / vehicle:getMaintenanceLevelInterval(lightest)
    local count = math.floor(ratio + 0.5)
    if math.abs(ratio - count) > 0.01 then
        return string.format(g_i18n:getText("rms_ws_levels_interval"), RMS_Utils.formatHours(interval))
    elseif count <= 1 then
        return g_i18n:getText("rms_ws_levels_every_service")
    end
    return string.format(g_i18n:getText("rms_ws_levels_one_service_in"), count)
end

---Returns the text keys of the filters a maintenance changes, nil without any
-- @param table vehicle vehicle
-- @return string? detailKey l10n key of the filters changed
-- @return string? newKey l10n key of the cell
local function getFiltersKeys(vehicle)
    local hasEngine = not vehicle.spec_RealisticMechanicalSystems.isElectricVehicle
    local hasHydraulic = RMS_Consumables.getHasFilter(vehicle, RMS_Consumables.getFilterOfBreakdown("HYDRAULIC_FILTER_CLOGGING"))
    local hasTransmission = RMS_Consumables.getHasFilter(vehicle, RMS_Consumables.getFilterOfBreakdown("TRANSMISSION_FILTER_CLOGGING"))
    if not hasEngine and not hasHydraulic then
        return nil, nil
    end
    local detailKey
    if not hasEngine then
        detailKey = "rms_ws_levels_filters_hydraulic"
    elseif hasHydraulic then
        detailKey = hasTransmission and "rms_ws_levels_filters_all_transmission" or "rms_ws_levels_filters_all"
    else
        detailKey = hasTransmission and "rms_ws_levels_filters_engine_transmission" or "rms_ws_levels_filters_engine"
    end
    return detailKey, hasEngine and "rms_ws_levels_new_plural" or "rms_ws_levels_new"
end

---Returns the maintenance level changing the AdBlue filter, nil without one
-- @param table vehicle vehicle
-- @return string? level maintenance level
local function getAdBlueFilterLevel(vehicle)
    local filter = RMS_Consumables.getFilterOfBreakdown("ADBLUE_FILTER_CLOGGING")
    if RMS_Consumables.getHasFilter(vehicle, filter) then
        return RealisticMechanicalSystems.MAINTENANCE_TYPES[filter.maintenanceType]
    end
    return nil
end

---Names each filter a maintenance level fits the machine
-- @param table vehicle vehicle
-- @param string level maintenance level
-- @return table names names of the filters
function RMS_WorkshopOrders.getFittedFilters(vehicle, level)
    local spec = vehicle.spec_RealisticMechanicalSystems
    local names = {}
    if not spec.isElectricVehicle then
        table.insert(names, g_i18n:getText("rms_ws_quote_oil_filter"))
        table.insert(names, g_i18n:getText("rms_breakdowns_part_fuel_filter"))
    end
    for _, entry in ipairs({ { "HYDRAULIC_FILTER_CLOGGING", "rms_breakdowns_part_hydraulic_filter" },
        { "TRANSMISSION_FILTER_CLOGGING", "rms_breakdowns_part_transmission_filter" } }) do
        if RMS_Consumables.getHasFilter(vehicle, RMS_Consumables.getFilterOfBreakdown(entry[1])) then
            table.insert(names, g_i18n:getText(entry[2]))
        end
    end
    if getAdBlueFilterLevel(vehicle) == level then
        table.insert(names, g_i18n:getText("rms_breakdowns_part_adblue_filter"))
    end
    if not spec.isElectricVehicle and spec.isVehicleNeedBlowOut and RealisticMechanicalSystems.getMaintenanceRenewsAirFilter(level) then
        table.insert(names, g_i18n:getText("rms_inspection_air_filter"))
    end
    return names
end

---Returns the table rows of the inspection order
-- @param table vehicle vehicle
-- @return table rows rows of the order table
local function getInspectionRows(vehicle)
    local R = RealisticMechanicalSystems
    ---Tells whether an inspection gives a report, and a complete one
    -- @param string inspectionType inspection level
    -- @return boolean hasReport true when it gives a report
    -- @return boolean isComplete true when the report is complete
    local function report(inspectionType)
        local entry = { type = R.STATUS.INSPECTION, optionOne = inspectionType, isCompleted = true }
        local hasReport = R.getIsLogEntryHasReport(entry)
        return hasReport, hasReport and R.getIsCompleteReport(entry)
    end
    local hasControllers = RMS_DiagnosticTool.getHasControllers(vehicle)
    return {
        { name = "rms_ws_inspection_mechanical", detail = "rms_ws_inspection_mechanical_detail",
            getCell = function(choice) return shareCell(R.getInspectionDetectionShare(choice, false)) end },
        { name = hasControllers and "rms_ws_inspection_electronic" or "rms_ws_inspection_electrical",
            detail = hasControllers and "rms_ws_inspection_electronic_detail" or "rms_ws_inspection_electrical_detail",
            getCell = function(choice) return shareCell(R.getInspectionDetectionShare(choice, true)) end },
        { name = "rms_ws_inspection_dormant", detail = "rms_ws_inspection_dormant_detail",
            getCell = function(choice)
                return shareCell(R.getInspectionFindsDormant(choice) and R.getInspectionDetectionShare(choice, false) or 0)
            end },
        { name = "rms_ws_inspection_report", detail = "rms_ws_inspection_report_detail",
            getCell = function(choice)
                local hasReport, isMeasured = report(choice)
                if isMeasured then
                    return g_i18n:getText("rms_ws_inspection_measures"), 2
                elseif hasReport then
                    return g_i18n:getText("rms_ws_inspection_ratings"), 1
                end
                return "-", 0
            end },
        { name = "rms_report_breakdown_risk_title", detail = "rms_ws_inspection_risk_detail",
            getCell = function(choice)
                local _, isMeasured = report(choice)
                if isMeasured then
                    return g_i18n:getText("rms_ws_inspection_assessed"), 2
                end
                return "-", 0
            end }
    }
end

---Returns the table rows of the maintenance order
-- @param table vehicle vehicle
-- @param string workshopType workshop
-- @return table rows rows of the order table
local function getLevelRows(vehicle, workshopType)
    local spec = vehicle.spec_RealisticMechanicalSystems
    local R = RealisticMechanicalSystems
    local rows = {}
    for _, fluid in ipairs(LEVEL_FLUIDS) do
        if RMS_Fluids.hasCircuit(vehicle, fluid.circuit) then
            table.insert(rows, { text = getOilName(vehicle, fluid.circuit), detailText = getIntervalText(vehicle, fluid.circuit),
                icon = RMS_Fluids.CIRCUITS[fluid.circuit].icon,
                getCell = function(level)
                    if RMS_Fluids.getMaintenanceMode(level, fluid.circuit) == "replace" then
                        return g_i18n:getText("rms_ws_levels_drain"), 2
                    end
                    return g_i18n:getText("rms_ws_levels_top_up"), 1
                end })
        end
    end
    if not spec.isElectricVehicle and spec.isVehicleNeedBlowOut then
        table.insert(rows, { name = "rms_inspection_air_filter", detailText = "", icon = "rms_workshopFluidIconAirFilter",
            getCell = function(level)
                if R.getMaintenanceRenewsAirFilter(level) then
                    return g_i18n:getText("rms_ws_levels_new"), 2
                end
                return g_i18n:getText("rms_ws_levels_blown"), 1
            end })
    end
    local detailKey, newKey = getFiltersKeys(vehicle)
    if detailKey ~= nil then
        local adBlueLevel = getAdBlueFilterLevel(vehicle)
        table.insert(rows, { name = "rms_ws_levels_filters", detail = detailKey, icon = "rms_workshopFluidIconFilters",
            getCell = function(level)
                return g_i18n:getText(level == adBlueLevel and "rms_ws_levels_new_adblue" or newKey), 2
            end })
    end
    if #R.getMajorServiceSystems(vehicle) > 0 then
        table.insert(rows, { name = "rms_ws_levels_checks", detail = "rms_ws_levels_checks_detail", icon = "rms_workshopFluidIconAdjustments",
            getCell = function(level)
                if level == R.MAINTENANCE_TYPES.PREVENTIVE then
                    return g_i18n:getText("rms_ws_levels_checks_done"), 2
                end
                return "-", 0
            end })
    end
    local readsFaultCodes = R.getMaintenanceReadsFaultCodes(vehicle, workshopType)
    table.insert(rows, { name = "rms_ws_levels_fault_search", icon = "rms_workshopLevelIconFaultSearch",
        detail = readsFaultCodes and "rms_ws_levels_fault_search_detail" or "rms_ws_levels_fault_search_no_tool_detail",
        getCell = function()
            if readsFaultCodes then
                return g_i18n:getText("rms_ws_levels_included"), 2
            end
            return g_i18n:getText("rms_ws_levels_mechanical"), 1
        end })
    return rows
end

---Counts the parts a thorough repair adds to the standard one
-- @param table vehicle vehicle
-- @param string workshopType workshop
-- @return integer count number of parts added
function RMS_WorkshopOrders.getThoroughAddedCount(vehicle, workshopType)
    local R, count = RealisticMechanicalSystems, 0
    for _, line in ipairs(vehicle:getRepairPriceLines(R.REPAIR_TYPES.HIGH, R.PART_TYPES.OEM, workshopType)) do
        count = count + #line.kitParts + #line.wornParts
    end
    return count
end

---Tells whether a repair fits parts: a picked fault of a part, or a worn part picked
-- @param table vehicle vehicle
-- @return boolean fitsParts true when it fits some
function RMS_WorkshopOrders.getRepairFitsParts(vehicle)
    local R = RealisticMechanicalSystems
    for id in pairs(vehicle:getActiveBreakdowns()) do
        if RMS_Breakdowns.BreakdownRegistry[id].isPartFault and R.getIsPickedForRepair(vehicle, id, R.REPAIR_TYPES.MEDIUM) then
            return true
        end
    end
    return #R.getPreventiveParts(vehicle) > 0
end

---Returns the table rows of the repair order
-- @param table vehicle vehicle
-- @param string workshopType workshop
-- @return table rows rows of the order table
local function getRepairRows(vehicle, workshopType)
    local R = RealisticMechanicalSystems
    local REPAIR = R.REPAIR_TYPES
    local isCovered = vehicle:isWarrantyRepairCovered(workshopType)
    local picked, running = 0, 0
    for id in pairs(vehicle:getActiveBreakdowns()) do
        picked = picked + (R.getIsPickedForRepair(vehicle, id, REPAIR.MEDIUM) and 1 or 0)
        running = running + (R.getIsPickedForRepair(vehicle, id, REPAIR.LOW) and 1 or 0)
    end
    local fitsParts = RMS_WorkshopOrders.getRepairFitsParts(vehicle)
    ---Returns a cell maker: the text for every method but the lightest, none for a repair fitting no part
    -- @param string key l10n key of the text
    -- @return function getCell cell maker
    local function replaces(key)
        return function(method)
            if method == REPAIR.LOW or not fitsParts then
                return "-", 0
            end
            return g_i18n:getText(key), 2
        end
    end
    local rows = {}
    if running < picked then
        table.insert(rows, { name = "rms_ws_repair_row_faults", detail = "rms_ws_repair_row_faults_detail",
            getCell = function(method)
                if method ~= REPAIR.LOW then
                    return g_i18n:getText("rms_ws_repair_faults_all"), 2
                end
                return string.format(g_i18n:getText("rms_ws_table_count"), running, picked), 1
            end })
    end
    table.insert(rows, { name = "rms_ws_repair_row_fault", detail = "rms_ws_repair_row_fault_detail",
        getCell = function(method)
            if method == REPAIR.LOW then
                return g_i18n:getText("rms_ws_repair_fault_returns"), 1
            end
            return g_i18n:getText("rms_ws_repair_fault_removed"), 2
        end })
    table.insert(rows, { name = "rms_ws_repair_row_part", detail = "rms_ws_repair_row_part_detail", getCell = replaces("rms_ws_repair_part_replaced") })
    local added = RMS_WorkshopOrders.getThoroughAddedCount(vehicle, workshopType)
    table.insert(rows, { name = "rms_ws_repair_row_around", detail = "rms_ws_repair_row_around_detail",
        getCell = function(method)
            if method ~= REPAIR.HIGH then
                return "-", 0
            elseif added == 0 then
                return g_i18n:getText("rms_ws_repair_around_none"), 1
            end
            return string.format(g_i18n:getText("rms_ws_repair_around_count"), added), 2
        end })
    table.insert(rows, { name = "rms_ws_repair_row_quality", detail = "rms_ws_repair_row_quality_detail",
        getCell = replaces(isCovered and RealisticMechanicalSystems.PART_TYPES.OEM or "rms_ws_repair_quality_choice") })
    return rows
end

---Returns the table rows of the overhaul order
-- @param table vehicle vehicle
-- @param string? system system of a partial overhaul
-- @return table rows rows of the order table
local function getOverhaulRows(vehicle, system)
    local OVERHAUL = RealisticMechanicalSystems.OVERHAUL_TYPES
    local targets = RMS_Config.MAINTENANCE.OVERHAUL_CONDITION_TARGETS
    local circuit = system ~= nil and RMS_Fluids.SYSTEM_TO_CIRCUIT[RMS_Utils.getSystemKey(RealisticMechanicalSystems.SYSTEMS, system)] or nil
    local hasPartialOil = circuit ~= nil and RMS_Fluids.getCapacity(vehicle, circuit) > 0
    local rows = {
        { name = "rms_ws_overhaul_row_systems", detail = "rms_ws_overhaul_row_systems_detail",
            getCell = function(extent)
                if extent == OVERHAUL.PARTIAL then
                    return g_i18n:getText("rms_ws_overhaul_systems_one"), 1
                end
                return g_i18n:getText("rms_ws_overhaul_systems_all"), 2
            end },
        { name = "rms_ws_overhaul_row_condition", detail = "rms_ws_overhaul_row_condition_detail",
            getCell = function(extent)
                local target = targets[RMS_Utils.getKeyByValue(OVERHAUL, extent)]
                return string.format("%d%%", math.floor(target * 100 + 0.5)), target >= 1 and 2 or 1
            end },
        { name = "rms_ws_overhaul_row_faults", detail = "rms_ws_overhaul_row_faults_detail", getCell = every("rms_ws_overhaul_faults_repaired") },
        { name = "rms_ws_overhaul_row_fluids", detail = "rms_ws_overhaul_row_fluids_detail",
            getCell = function(extent)
                if extent ~= OVERHAUL.PARTIAL then
                    return g_i18n:getText("rms_ws_overhaul_fluids_all"), 2
                elseif not hasPartialOil then
                    return "-", 0
                end
                return g_i18n:getText("rms_ws_overhaul_fluids_own"), 1
            end }
    }
    local hasFuel = RMS_Consumables.getHasFilter(vehicle, RMS_Consumables.getFilterOfBreakdown("FUEL_FILTER_CLOGGING"))
    local hasHydraulic = RMS_Consumables.getHasFilter(vehicle, RMS_Consumables.getFilterOfBreakdown("HYDRAULIC_FILTER_CLOGGING"))
    local hasTransmission = RMS_Consumables.getHasFilter(vehicle, RMS_Consumables.getFilterOfBreakdown("TRANSMISSION_FILTER_CLOGGING"))
    if hasFuel or hasHydraulic then
        local detailKey
        if not hasFuel then
            detailKey = "rms_ws_levels_filters_hydraulic"
        elseif hasHydraulic then
            detailKey = hasTransmission and "rms_ws_overhaul_filters_both_transmission" or "rms_ws_overhaul_filters_both"
        else
            detailKey = hasTransmission and "rms_ws_overhaul_filters_fuel_transmission" or "rms_ws_overhaul_filters_fuel"
        end
        local cellKey = "rms_ws_levels_new"
        if getAdBlueFilterLevel(vehicle) ~= nil then
            cellKey = "rms_ws_levels_new_adblue"
        elseif hasFuel and (hasHydraulic or hasTransmission) then
            cellKey = "rms_ws_levels_new_plural"
        end
        table.insert(rows, { name = "rms_ws_levels_filters", detail = detailKey, getCell = every(cellKey) })
    end
    table.insert(rows, { name = "rms_ws_inspection_report", detail = "rms_ws_inspection_report_detail", getCell = every("rms_ws_inspection_measures") })
    return rows
end

---Tells whether a full repaint offers other colors
-- @param table vehicle vehicle
-- @return boolean hasColors true when other colors are offered
function RMS_WorkshopOrders.getHasBodyworkColors(vehicle)
    for _, zone in ipairs(RMS_Bodywork.getColorZones(vehicle)) do
        if #RMS_Bodywork.getColorChoices(vehicle, zone, {}) > 0 or RMS_Bodywork.getCustomColorChoice(vehicle, zone, {}) ~= nil then
            return true
        end
    end
    return false
end

---Returns the table rows of the paint order
-- @param table vehicle vehicle
-- @return table rows rows of the order table
local function getBodyworkRows(vehicle)
    local dealer = g_i18n:getText(RealisticMechanicalSystems.WORKSHOP.DEALER)
    local hasColors = RMS_WorkshopOrders.getHasBodyworkColors(vehicle)
    return {
        { name = "rms_ws_paint_row_extent", detail = "rms_ws_paint_row_extent_detail",
            getCell = function(mode)
                if mode == RMS_Bodywork.TOUCHUP then
                    return string.format(g_i18n:getText("rms_ws_paint_extent_up_to"),
                        string.format("%d%%", math.floor(RMS_Bodywork.MAX_TOUCHUP_WEAR * 100 + 0.5))), 1
                end
                return g_i18n:getText("rms_ws_paint_extent_all"), 2
            end },
        { name = "rms_ws_paint_row_colors", detail = "rms_ws_paint_row_colors_detail",
            getCell = function(mode)
                if mode == RMS_Bodywork.TOUCHUP or not hasColors then
                    return g_i18n:getText("rms_ws_paint_colors_kept"), 1
                end
                return g_i18n:getText("rms_ws_paint_colors_choice"), 2
            end },
        { name = "rms_ws_paint_row_workshop", detail = "rms_ws_paint_row_workshop_detail",
            getCell = function(mode)
                if mode == RMS_Bodywork.TOUCHUP then
                    return g_i18n:getText(RealisticMechanicalSystems.WORKSHOP.OWN) .. " · " .. dealer, 2
                end
                return dealer, 1
            end }
    }
end

---Returns the months left on the soonest fitted-part cover of a repair
-- @param table vehicle vehicle
-- @param string workshopType workshop
-- @return float months months left, math.huge without a fitted-part cover
function RMS_WorkshopOrders.getPartWarrantyMonthsLeft(vehicle, workshopType)
    local R, left = RealisticMechanicalSystems, math.huge
    for _, line in ipairs(vehicle:getRepairPriceLines(R.REPAIR_TYPES.MEDIUM, R.PART_TYPES.OEM, workshopType)) do
        if line.warrantyReason == "part" then
            left = math.min(left, vehicle.spec_RealisticMechanicalSystems.partWarranty[line.breakdownId] - vehicle.age)
        end
    end
    return left
end

---Returns the warranty corner of the repair order
-- @param table vehicle vehicle
-- @param string workshopType workshop
-- @return table corner label, name and reason of the corner
local function getWarrantyCorner(vehicle, workshopType)
    local R = RealisticMechanicalSystems
    local isCovered, status = vehicle:isWarrantyRepairCovered(workshopType)
    local months, hours = vehicle:getWarrantyLimits()
    local reason = string.format(g_i18n:getText("rms_ws_warranty_terms"), months, g_i18n:formatNumber(hours, 0))
    if status == "part" then
        reason = string.format(g_i18n:getText("rms_warranty_part"), RMS_WorkshopOrders.getPartWarrantyMonthsLeft(vehicle, workshopType))
    elseif status == "partial" then
        reason = g_i18n:getText("rms_warranty_partial_imposed")
    elseif status == "lease" or status == "remapped" or status == "own" then
        reason = g_i18n:getText("rms_warranty_" .. status)
    elseif R.getIsWarrantyRefusal(status) then
        reason = string.format(g_i18n:getText("rms_ws_warranty_refused"), g_i18n:getText("rms_warranty_" .. status))
    end
    if isCovered then
        reason = reason .. "\n" .. g_i18n:getText("rms_warranty_imposed")
    end
    return {
        label = "rms_ws_warranty_title",
        name = g_i18n:getText(isCovered and "rms_ws_warranty_covered" or status == "partial" and "rms_warranty_partial" or "rms_ws_warranty_not_covered"),
        isHighlight = isCovered,
        reason = reason,
        isReasonWarning = R.getIsWarrantyRefusal(status)
    }
end

local STATUS = RealisticMechanicalSystems.STATUS

RMS_WorkshopOrders.ORDERS = {
    [STATUS.INSPECTION] = {
        getChoices = function()
            local TYPES = RealisticMechanicalSystems.INSPECTION_TYPES
            return { TYPES.VISUAL, TYPES.STANDARD, TYPES.COMPLETE }
        end,
        getDefaultChoice = function() return RealisticMechanicalSystems.INSPECTION_TYPES.STANDARD end,
        promptKey = "rms_option_menu_option_one_title_inspection",
        getRows = getInspectionRows,
        getCorner = function(vehicle)
            local hours, isOutdated = vehicle:getInspectionReportAge()
            return { label = "rms_ws_label_last_check", name = RMS_Utils.formatReportAge(hours), isWarning = isOutdated,
                reason = isOutdated and g_i18n:getText("rms_ws_reading_outdated") or "", isReasonWarning = true }
        end,
        noteKey = "rms_ws_inspection_maintenance_note"
    },
    [STATUS.MAINTENANCE] = {
        getChoices = function(vehicle) return vehicle:getMaintenanceTypes() end,
        getDefaultChoice = function(vehicle) return vehicle:getDueMaintenanceType() end,
        promptKey = "rms_option_menu_option_one_title_maintenance",
        getRows = getLevelRows,
        getCorner = function(vehicle)
            return { label = "rms_ws_levels_recommended_for", name = RMS_Utils.formatMaintenanceLevel(vehicle, vehicle:getDueMaintenanceType()),
                isHighlight = true, reason = RMS_Utils.formatServiceDue(vehicle, vehicle:getServiceSchedule(), true) }
        end,
        getColumnName = function(vehicle, choice) return RMS_Utils.formatMaintenanceLevel(vehicle, choice) end,
        getFrequency = function(vehicle, choice, choices) return getFrequencyText(vehicle, choice, choices[1]) end,
        getBadge = function(vehicle, choice) return choice == vehicle:getDueMaintenanceType() and "rms_spec_state_recommended" or nil end,
        footerKeys = { "rms_ws_levels_every_level", "rms_service_program_estimated" },
        qualityPromptKey = "rms_option_menu_option_two_title_maintenance"
    },
    [STATUS.REPAIR] = {
        getChoices = function(vehicle)
            local R = RealisticMechanicalSystems
            local REPAIR, choices = R.REPAIR_TYPES, {}
            local hasPicked, hasRunning = false, false
            for id in pairs(vehicle:getActiveBreakdowns()) do
                hasPicked = hasPicked or R.getIsPickedForRepair(vehicle, id, REPAIR.MEDIUM)
                hasRunning = hasRunning or R.getIsPickedForRepair(vehicle, id, REPAIR.LOW)
            end
            if hasRunning then
                table.insert(choices, REPAIR.LOW)
            end
            if hasPicked or #R.getPreventiveParts(vehicle) > 0 then
                table.insert(choices, REPAIR.MEDIUM)
                table.insert(choices, REPAIR.HIGH)
            end
            return choices
        end,
        getDefaultChoice = function() return RealisticMechanicalSystems.REPAIR_TYPES.MEDIUM end,
        isChoiceLocked = function(vehicle, choice, workshopType)
            return choice == RealisticMechanicalSystems.REPAIR_TYPES.HIGH and RMS_WorkshopOrders.getThoroughAddedCount(vehicle, workshopType) == 0
        end,
        promptKey = "rms_option_menu_option_one_title_repair",
        getRows = getRepairRows,
        getCorner = getWarrantyCorner,
        getBadge = function(vehicle, choice, _, workshopType)
            local isCovered = vehicle:isWarrantyRepairCovered(workshopType)
            return isCovered and choice == RealisticMechanicalSystems.REPAIR_TYPES.MEDIUM and "rms_ws_badge_warranty" or nil
        end,
        getImposed = function(vehicle, workshopType)
            if vehicle:isWarrantyRepairCovered(workshopType) then
                return RealisticMechanicalSystems.REPAIR_TYPES.MEDIUM, RealisticMechanicalSystems.PART_TYPES.OEM
            end
        end,
        qualityPromptKey = "rms_option_menu_option_two_title_repair"
    },
    [STATUS.OVERHAUL] = {
        getChoices = function()
            local OVERHAUL = RealisticMechanicalSystems.OVERHAUL_TYPES
            return { OVERHAUL.PARTIAL, OVERHAUL.STANDARD, OVERHAUL.FULL }
        end,
        getDefaultChoice = function() return RealisticMechanicalSystems.OVERHAUL_TYPES.STANDARD end,
        promptKey = "rms_option_menu_option_one_title_overhaul",
        getRows = function(vehicle, _, system) return getOverhaulRows(vehicle, system) end,
        getCorner = function(vehicle)
            return { label = "rms_ws_overhaul_worn", isWarning = true, reason = "",
                name = string.format(g_i18n:getText("rms_ws_table_count"), #RMS_Utils.getEligibleOverhaulSystems(vehicle),
                    #RMS_Utils.getOverhaulSystems(vehicle)) }
        end,
        systemPromptKey = "rms_option_menu_option_two_title_overhaul"
    },
    [STATUS.BODYWORK] = {
        getChoices = function() return { RMS_Bodywork.TOUCHUP, RMS_Bodywork.FULL } end,
        getDefaultChoice = function(vehicle, workshopType)
            local wear = RMS_Bodywork.getWear(vehicle)
            local isTouchUpWear = wear ~= nil and wear >= RMS_Bodywork.MIN_TOUCHUP_WEAR and wear <= RMS_Bodywork.MAX_TOUCHUP_WEAR
            return (workshopType == RealisticMechanicalSystems.WORKSHOP.OWN or isTouchUpWear) and RMS_Bodywork.TOUCHUP or RMS_Bodywork.FULL
        end,
        getRows = getBodyworkRows,
        getCorner = function(vehicle)
            local wear = RMS_Bodywork.getWear(vehicle)
            local isBeyond = wear ~= nil and wear > RMS_Bodywork.MAX_TOUCHUP_WEAR
            local reasonKey = wear ~= nil and wear < RMS_Bodywork.MIN_TOUCHUP_WEAR and "rms_bodywork_no_wear" or isBeyond and "rms_bodywork_wear_limit" or nil
            return { label = "rms_bodywork_wear", isWarning = isBeyond,
                name = wear ~= nil and string.format("%s%%", g_i18n:formatNumber(wear * 100, 1)) or g_i18n:getText("rms_bodywork_unavailable"),
                reason = reasonKey ~= nil and g_i18n:getText(reasonKey) or "" }
        end,
        getRefusalKey = function(vehicle, workshopType, choice)
            if choice == RMS_Bodywork.FULL and workshopType ~= RealisticMechanicalSystems.WORKSHOP.DEALER then
                return "rms_bodywork_dealer_only"
            elseif RMS_Bodywork.getWear(vehicle) == nil then
                return "rms_bodywork_ineligible"
            end
            return nil
        end
    },
    [STATUS.REFILL] = {},
    [STATUS.REMAP] = {}
}

---Tells who pays a job for the farm, the warranty or the lease
-- @param table vehicle vehicle
-- @param string serviceType RealisticMechanicalSystems.STATUS of the service
-- @param string? optionOne first option of the service
-- @param string? optionTwo second option of the service
-- @param string workshopType workshop
-- @return string? coverKey "warranty" or "lease", nil when the farm pays
function RMS_WorkshopOrders.getCoverKey(vehicle, serviceType, optionOne, optionTwo, workshopType)
    if serviceType == STATUS.REPAIR and vehicle:isWarrantyRepairCovered(workshopType) then
        return "warranty"
    elseif serviceType == STATUS.MAINTENANCE and vehicle:isLeaseMaintenanceCovered(workshopType) then
        return "lease"
    end
    return nil
end

---Starts an order on the server, or asks the server from a client
-- @param table vehicle vehicle
-- @param string workshopType workshop
-- @param string serviceType RealisticMechanicalSystems.STATUS of the service
-- @param string? optionOne first option of the service
-- @param string? optionTwo second option of the service
-- @param table? sellingPoint selling point of the workshop
-- @return boolean isSent true when the order started or was sent
function RMS_WorkshopOrders.start(vehicle, workshopType, serviceType, optionOne, optionTwo, sellingPoint)
    local price = RMS_FluidWorkshop.getTransactionPrice(vehicle, serviceType, workshopType, optionOne, optionTwo)
    if price == nil then
        RMS_FluidWorkshop.showResult(RMS_FluidWorkshop.RESULT.PRICE_UNAVAILABLE)
        return false
    elseif price > 0 and g_currentMission:getMoney() < price then
        InfoDialog.show(g_i18n:getText("shop_messageNotEnoughMoneyToBuy"))
        return false
    end
    if g_server == nil then
        RMS_ServiceRequestEvent.send(vehicle, serviceType, workshopType, optionOne, optionTwo, sellingPoint)
        return true
    end
    local isStarted, result = RMS_FluidWorkshop.tryStartService(vehicle, sellingPoint, serviceType, workshopType, optionOne,
        optionTwo, g_currentMission:getFarmId())
    if not isStarted then
        RMS_FluidWorkshop.showResult(result)
        return false
    end
    RMS_VehicleChangeStatusEvent.send(vehicle)
    return true
end
