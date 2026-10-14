-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---Shared configuration dialog for maintenance, repair, overhaul and refill services
RMS_MaintenanceThreeOptionsDialog = {}
RMS_MaintenanceThreeOptionsDialog.INSTANCE = nil

local RMS_MaintenanceThreeOptionsDialog_mt = Class(RMS_MaintenanceThreeOptionsDialog, MessageDialog)
local modDirectory = g_currentModDirectory

local REFILL_ROW_FIELDS = {
    {circuit = "engineOil", row = "refillEngineOilRow", level = "refillEngineOilLevel", amount = "refillEngineOilAmount",
        gauge = "refillEngineOilGauge", under = "refillEngineOilGaugeUnder"},
    {circuit = "coolant", row = "refillCoolantRow", level = "refillCoolantLevel", amount = "refillCoolantAmount",
        gauge = "refillCoolantGauge", under = "refillCoolantGaugeUnder"},
    {circuit = "transmissionOil", row = "refillTransmissionOilRow", level = "refillTransmissionOilLevel",
        amount = "refillTransmissionOilAmount", gauge = "refillTransmissionOilGauge", under = "refillTransmissionOilGaugeUnder"},
    {circuit = "hydraulicFluid", row = "refillHydraulicFluidRow", level = "refillHydraulicFluidLevel",
        amount = "refillHydraulicFluidAmount", gauge = "refillHydraulicFluidGauge", under = "refillHydraulicFluidGaugeUnder"}
}

---Loads the dialog layout and stores the shared instance
function RMS_MaintenanceThreeOptionsDialog.register()
    local dialog = RMS_MaintenanceThreeOptionsDialog.new()
    g_gui:loadGui(modDirectory .. "gui/RMS_MaintenanceThreeOptionsDialog.xml", "RMS_MaintenanceThreeOptionsDialog", dialog)
    RMS_MaintenanceThreeOptionsDialog.INSTANCE = dialog
end

---Create instance of RMS_MaintenanceThreeOptionsDialog
-- @param table? target target
-- @param table? customMt custom metatable
-- @return table dialog instance of class RMS_MaintenanceThreeOptionsDialog
function RMS_MaintenanceThreeOptionsDialog.new(target, customMt)
    local dialog = MessageDialog.new(target, customMt or RMS_MaintenanceThreeOptionsDialog_mt)
    dialog.vehicle = nil
    dialog.overhaulSystemValues = nil
    dialog.optionOneValues = nil
    dialog.optionTwoValues = nil
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

---Returns the second option actually sent
local function getEffectiveOptionTwo(dialog)
    if dialog == nil then
        return "NONE"
    end

    if dialog.maintenanceType == RealisticMechanicalSystems.STATUS.REFILL then
        return nil
    end

    if dialog.maintenanceType == RealisticMechanicalSystems.STATUS.OVERHAUL
        and dialog.selectedOptionOne ~= RealisticMechanicalSystems.OVERHAUL_TYPES.PARTIAL then
        return "NONE"
    end

    return dialog.selectedOptionTwo
end

---Updates the refill rows from the requirements of the transaction
local function updateRefillPresentation(dialog, requirements, requirementsLabel)
    local litersByCircuit = RMS_Fluids.getRequiredLitersByCircuit(requirements)
    local hasRequirements = next(litersByCircuit) ~= nil
    local unit = g_i18n:getText("unit_literShort")

    dialog.refillEmptyGroup:setVisible(not hasRequirements)
    dialog.refillRequirementsGroup:setVisible(hasRequirements)
    dialog.refillRequirementsLabel:setText(requirementsLabel)

    dialog.refillTransmissionOilTitle:setText(g_i18n:getText(
        RMS_Fluids.getCircuitTextKey(dialog.vehicle, "transmissionOil", "rms_inspection_transmission_oil")))
    for _, fields in ipairs(REFILL_ROW_FIELDS) do
        local requiredLiters = math.max(tonumber(litersByCircuit[fields.circuit]) or 0, 0)
        local isVisible = requiredLiters > RMS_Fluids.EPSILON
        local row = dialog[fields.row]
        row:setVisible(isVisible)

        if isVisible then
            local capacity = RMS_Fluids.getCapacity(dialog.vehicle, fields.circuit)
            local currentLiters = RMS_Fluids.getLiters(dialog.vehicle, fields.circuit)
            local levelRatio = capacity > RMS_Fluids.EPSILON and math.clamp(currentLiters / capacity, 0, 1) or 0
            local gauge = dialog[fields.gauge]
            local baseWidth = dialog.refillGaugeWidths[fields.gauge] or gauge.size[1]

            dialog[fields.level]:setText(string.format(
                g_i18n:getText("rms_inspection_fluid_quantity_format"),
                RMS_FluidWorkshop.formatLiters(currentLiters),
                RMS_FluidWorkshop.formatLiters(capacity),
                unit
            ))
            dialog[fields.amount]:setText(string.format(
                "+ %s %s",
                RMS_FluidWorkshop.formatLiters(requiredLiters),
                unit
            ))
            RMS_Utils.setLevelGauge(gauge, dialog[fields.under], baseWidth, levelRatio)
        end
    end

    if hasRequirements then
        RMS_Utils.fitValuePills(dialog.refillRequirementsGroup)
    end
    dialog.refillRowsLayout:invalidateLayout()
end

-- quote of the recap in reference pixels, as the dialog XML lays it out
local QUOTE_WIDTH, QUOTE_HEIGHT, QUOTE_TOP, QUOTE_BOTTOM, QUOTE_LIST = 372, 168, 28, 8, 132
local QUOTE_HEAD, QUOTE_HEAD_GAP, QUOTE_LINE, QUOTE_NOTE = 20, 7, 17, 16
local QUOTE_ROW_WIDTH, QUOTE_SLIDER_ROOM, QUOTE_AMOUNT, QUOTE_GAP = 348, 12, 62, 6
local QUOTE_INDENT, QUOTE_BULLET_X, QUOTE_BULLET_TEXT = 12, 2, 13
-- groups that gather the lines of their kind under one name and their sum
local QUOTE_GROUP_KEYS = { repair = "rms_ws_action_repair", fluid = "rms_ws_section_fluids" }
-- what the quote says of a job paid for the farm, by the warranty or the lease
local COVER_TEXTS = {
    warranty = { price = "rms_option_menu_warranty_repair_text", fluids = "rms_fluid_warranty_covered" },
    lease = { price = "rms_option_menu_lease_service_text", fluids = "rms_fluid_lease_covered" }
}

---Opens the dialog on a vehicle for a maintenance, repair, overhaul or refill
-- @param table vehicle vehicle
-- @param string maintenanceType service status constant
function RMS_MaintenanceThreeOptionsDialog.show(vehicle, maintenanceType)
    if RMS_MaintenanceThreeOptionsDialog.INSTANCE == nil then RMS_MaintenanceThreeOptionsDialog.register() end
    if vehicle == nil or vehicle.spec_RealisticMechanicalSystems == nil or maintenanceType == nil then return end
    if maintenanceType == RealisticMechanicalSystems.STATUS.OVERHAUL
        and #RMS_Utils.getEligibleOverhaulSystems(vehicle) == 0 then return end
    
    local dialog = RMS_MaintenanceThreeOptionsDialog.INSTANCE
    if dialog == nil then return end
    dialog.vehicle = vehicle
    dialog.maintenanceType = maintenanceType
    dialog.resetConfigScroll = true

    if dialog.maintenanceType == RealisticMechanicalSystems.STATUS.MAINTENANCE then
        -- the level the schedule calls for comes selected
        dialog.selectedOptionOne = vehicle:getDueMaintenanceType()
    elseif dialog.maintenanceType == RealisticMechanicalSystems.STATUS.REPAIR then
        dialog.selectedOptionOne = RealisticMechanicalSystems.REPAIR_TYPES.MEDIUM
    elseif dialog.maintenanceType == RealisticMechanicalSystems.STATUS.OVERHAUL then
        dialog.selectedOptionOne = RealisticMechanicalSystems.OVERHAUL_TYPES.STANDARD
    else
        dialog.selectedOptionOne = nil
    end
    dialog.overhaulSystemValues = RMS_Utils.getEligibleOverhaulSystems(vehicle)
    if dialog.maintenanceType == RealisticMechanicalSystems.STATUS.REFILL then
        dialog.selectedOptionTwo = nil
    elseif dialog.maintenanceType == RealisticMechanicalSystems.STATUS.OVERHAUL then
        dialog.selectedOptionTwo = dialog.overhaulSystemValues[1]
    else
        dialog.selectedOptionTwo = RealisticMechanicalSystems.PART_TYPES.OEM
    end
    dialog.selectedOptionThree = false
    
    dialog:updateScreen()
    g_gui:showDialog("RMS_MaintenanceThreeOptionsDialog")
end

-- table of the order in reference pixels, as the dialog XML lays it out
local LEVEL_TABLE_WIDTH, LEVEL_TABLE_HEIGHT = 619, 472
local LEVEL_LABEL_WIDTH, LEVEL_GAP, LEVEL_HEADER, LEVEL_ROW, LEVEL_BOTTOM = 220, 8, 112, 44, 8
-- oils the table lists, in its order, with their short name and their icon
local LEVEL_FLUIDS = {
    { circuit = "engineOil", nameKey = "rms_fluid_hud_engineOil", icon = "rms_workshopFluidIconEngineOil" },
    { circuit = "transmissionOil", nameKey = "rms_inspection_transmission_oil", icon = "rms_workshopFluidIconTransmissionOil" },
    { circuit = "hydraulicFluid", nameKey = "rms_inspection_hydraulic_fluid", icon = "rms_workshopFluidIconHydraulicFluid" },
    { circuit = "coolant", nameKey = "rms_fluid_hud_coolant", icon = "rms_workshopFluidIconCoolant" }
}
-- the look of a cell by what a column does: all of it, part of it, nothing
local LEVEL_CELL_KINDS = { [2] = "Done", [1] = "Light", [0] = "None" }
-- the cards of the systems a partial overhaul can take: their height, the gap between two rows, how many to a row
local SYSTEM_CARD_HEIGHT, SYSTEM_CARD_GAP, SYSTEM_CARDS_PER_ROW = 48, 9, 4

---Names the oil a circuit holds, a common sump as one
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

---Returns the change interval of an oil, from the service programme
local function getLevelIntervalText(vehicle, circuit)
    for _, clock in ipairs(vehicle:getServiceClocks()) do
        if RMS_Utils.getKeyByValue(clock.circuits, circuit) ~= nil then
            local _, interval = vehicle:getServiceClockHours(clock)
            return string.format(g_i18n:getText("rms_ws_levels_interval"),
                RMS_Utils.formatServiceDeadline({ interval = interval, months = clock.months }, true))
        end
    end
    return ""
end

---Names the filters every level fits the machine
local function getFiltersKeys(vehicle)
    local hasEngine = not vehicle.spec_RealisticMechanicalSystems.isElectricVehicle
    local hasHydraulic = RMS_Consumables.getHasFilter(vehicle, RMS_Consumables.getFilterOfBreakdown("HYDRAULIC_FILTER_CLOGGING"))
    if not hasEngine and not hasHydraulic then
        return nil, nil
    end
    local detailKey = not hasEngine and "rms_ws_levels_filters_hydraulic"
        or (hasHydraulic and "rms_ws_levels_filters_all" or "rms_ws_levels_filters_engine")
    return detailKey, hasEngine and "rms_ws_levels_new_plural" or "rms_ws_levels_new"
end

---Names each filter a maintenance level fits the machine
local function getFittedFilters(vehicle, level)
    local spec = vehicle.spec_RealisticMechanicalSystems
    local names = {}
    if not spec.isElectricVehicle then
        table.insert(names, g_i18n:getText("rms_ws_quote_oil_filter"))
        table.insert(names, g_i18n:getText("rms_breakdowns_part_fuel_filter"))
    end
    if RMS_Consumables.getHasFilter(vehicle, RMS_Consumables.getFilterOfBreakdown("HYDRAULIC_FILTER_CLOGGING")) then
        table.insert(names, g_i18n:getText("rms_breakdowns_part_hydraulic_filter"))
    end
    if not spec.isElectricVehicle and spec.isVehicleNeedBlowOut and RealisticMechanicalSystems.getMaintenanceRenewsAirFilter(level) then
        table.insert(names, g_i18n:getText("rms_inspection_air_filter"))
    end
    return names
end

---Lists the rows of the level table, with what each level does
-- @param table vehicle vehicle
-- @param string workshopType workshop the order is opened in
-- @return table rows name, detail, icon and getCell(level) giving the text of a cell and its kind, 2 to 0
function RMS_MaintenanceThreeOptionsDialog.getLevelRows(vehicle, workshopType)
    local spec = vehicle.spec_RealisticMechanicalSystems
    local rows = {}

    for _, fluid in ipairs(LEVEL_FLUIDS) do
        if RMS_Fluids.hasCircuit(vehicle, fluid.circuit) then
            table.insert(rows, {
                name = getOilName(vehicle, fluid.circuit),
                detail = getLevelIntervalText(vehicle, fluid.circuit),
                icon = fluid.icon,
                getCell = function(level)
                    if RMS_Fluids.getMaintenanceMode(level, fluid.circuit) == "replace" then
                        return g_i18n:getText("rms_ws_levels_drain"), 2
                    end
                    return g_i18n:getText("rms_ws_levels_top_up"), 1
                end
            })
        end
    end

    -- an electric motor breathes no air
    if not spec.isElectricVehicle and spec.isVehicleNeedBlowOut then
        table.insert(rows, { name = g_i18n:getText("rms_inspection_air_filter"), detail = "", icon = "rms_workshopFluidIconAirFilter",
            getCell = function(level)
                if RealisticMechanicalSystems.getMaintenanceRenewsAirFilter(level) then
                    return g_i18n:getText("rms_ws_levels_new"), 2
                end
                return g_i18n:getText("rms_ws_levels_blown"), 1
            end })
    end

    -- every level changes the oil filter with the engine oil, and the fuel and hydraulic filters
    local detailKey, newKey = getFiltersKeys(vehicle)
    if detailKey ~= nil then
        table.insert(rows, { name = g_i18n:getText("rms_ws_levels_filters"), detail = g_i18n:getText(detailKey),
            icon = "rms_workshopFluidIconFilters",
            getCell = function()
                return g_i18n:getText(newKey), 2
            end })
    end

    -- valve clearance, injectors and thermostat, on the machines carrying them
    if #RealisticMechanicalSystems.getMajorServiceSystems(vehicle) > 0 then
        table.insert(rows, { name = g_i18n:getText("rms_ws_levels_checks"), detail = g_i18n:getText("rms_ws_levels_checks_detail"),
            icon = "rms_workshopFluidIconAdjustments",
            getCell = function(level)
                if level == RealisticMechanicalSystems.MAINTENANCE_TYPES.PREVENTIVE then
                    return g_i18n:getText("rms_ws_levels_checks_done"), 2
                end
                return "-", 0
            end })
    end

    -- every level looks for faults as the standard inspection its workshop can run
    local readsFaultCodes = RealisticMechanicalSystems.getMaintenanceReadsFaultCodes(vehicle, workshopType)
    table.insert(rows, { name = g_i18n:getText("rms_ws_levels_fault_search"), icon = "rms_workshopLevelIconFaultSearch",
        detail = g_i18n:getText(readsFaultCodes and "rms_ws_levels_fault_search_detail" or "rms_ws_levels_fault_search_mobile_detail"),
        getCell = function()
            if readsFaultCodes then
                return g_i18n:getText("rms_ws_levels_included"), 2
            end
            return g_i18n:getText("rms_ws_levels_mechanical"), 1
        end })

    return rows
end

---Lists the rows of the repair table, with what each method does
-- @param table vehicle vehicle
-- @return table rows name, detail and getCell(method) giving the text of a cell and its kind, 2 to 0
function RMS_MaintenanceThreeOptionsDialog.getRepairRows(vehicle)
    local REPAIR = RealisticMechanicalSystems.REPAIR_TYPES
    local ticked, running = 0, 0
    for _, breakdown in pairs(vehicle:getActiveBreakdowns()) do
        if breakdown.isSelectedForRepair and breakdown.isVisible then
            ticked = ticked + 1
            if breakdown.isActive then
                running = running + 1
            end
        end
    end
    ---Builds the cells of a row a quick fix leaves untouched
    local function replaces(key)
        return function(method)
            if method == REPAIR.LOW then
                return "-", 0
            end
            return g_i18n:getText(key), 2
        end
    end

    local rows = {}
    -- a quick fix leaves the breakdowns that are not running, a dormant defect or one already quick fixed
    if running < ticked then
        table.insert(rows, { name = g_i18n:getText("rms_ws_repair_row_faults"), detail = g_i18n:getText("rms_ws_repair_row_faults_detail"),
            getCell = function(method)
                if method ~= REPAIR.LOW then
                    return g_i18n:getText("rms_ws_repair_faults_all"), 2
                end
                return string.format(g_i18n:getText("rms_ws_table_count"), running, ticked), 1
            end })
    end
    table.insert(rows, { name = g_i18n:getText("rms_ws_repair_row_fault"), detail = g_i18n:getText("rms_ws_repair_row_fault_detail"),
        getCell = function(method)
            if method == REPAIR.LOW then
                return g_i18n:getText("rms_ws_repair_fault_returns"), 1
            end
            return g_i18n:getText("rms_ws_repair_fault_removed"), 2
        end })
    table.insert(rows, { name = g_i18n:getText("rms_ws_repair_row_part"), detail = g_i18n:getText("rms_ws_repair_row_part_detail"),
        getCell = replaces("rms_ws_repair_part_replaced") })
    local remaining = RMS_Config.MAINTENANCE.REPAIR_REMAINING_STRESS_RATIO
    table.insert(rows, { name = g_i18n:getText("rms_ws_repair_row_stress"), detail = g_i18n:getText("rms_ws_repair_row_stress_detail"),
        getCell = function(method)
            local ratio = remaining[RMS_Utils.getKeyByValue(REPAIR, method)]
            if ratio == nil then
                return "-", 0
            elseif ratio <= 0 then
                return g_i18n:getText("rms_ws_repair_stress_cleared"), 2
            end
            return string.format("-%d%%", math.floor((1 - ratio) * 100 + 0.5)), 1
        end })
    table.insert(rows, { name = g_i18n:getText("rms_ws_repair_row_quality"), detail = g_i18n:getText("rms_ws_repair_row_quality_detail"),
        getCell = replaces("rms_ws_repair_quality_choice") })
    return rows
end

---Lists the rows of the overhaul table, with what each extent does
-- @param table vehicle vehicle
-- @param string? system system a partial overhaul takes
-- @return table rows name, detail and getCell(extent) giving the text of a cell and its kind, 2 to 0
function RMS_MaintenanceThreeOptionsDialog.getOverhaulRows(vehicle, system)
    local OVERHAUL = RealisticMechanicalSystems.OVERHAUL_TYPES
    local targets = RMS_Config.MAINTENANCE.OVERHAUL_CONDITION_TARGETS
    ---Writes a cell every extent fills alike
    local function every(key)
        return function()
            return g_i18n:getText(key), 2
        end
    end
    -- a partial overhaul changes the oil of its system, when the system holds one
    local circuit = system ~= nil and RMS_Fluids.SYSTEM_TO_CIRCUIT[RMS_Utils.getSystemKey(RealisticMechanicalSystems.SYSTEMS, system)] or nil
    local hasPartialOil = circuit ~= nil and RMS_Fluids.getCapacity(vehicle, circuit) > 0

    local rows = {
        { name = g_i18n:getText("rms_ws_overhaul_row_systems"), detail = g_i18n:getText("rms_ws_overhaul_row_systems_detail"),
            getCell = function(extent)
                if extent == OVERHAUL.PARTIAL then
                    return g_i18n:getText("rms_ws_overhaul_systems_one"), 1
                end
                return g_i18n:getText("rms_ws_overhaul_systems_all"), 2
            end },
        { name = g_i18n:getText("rms_ws_overhaul_row_condition"), detail = g_i18n:getText("rms_ws_overhaul_row_condition_detail"),
            getCell = function(extent)
                local target = targets[RMS_Utils.getKeyByValue(OVERHAUL, extent)]
                return string.format("%d%%", math.floor(target * 100 + 0.5)), target >= 1 and 2 or 1
            end },
        { name = g_i18n:getText("rms_ws_repair_row_stress"), detail = g_i18n:getText("rms_ws_overhaul_row_treated_detail"),
            getCell = every("rms_ws_repair_stress_cleared") },
        { name = g_i18n:getText("rms_ws_overhaul_row_faults"), detail = g_i18n:getText("rms_ws_overhaul_row_faults_detail"),
            getCell = every("rms_ws_overhaul_faults_repaired") },
        { name = g_i18n:getText("rms_ws_overhaul_row_fluids"), detail = g_i18n:getText("rms_ws_overhaul_row_fluids_detail"),
            getCell = function(extent)
                if extent ~= OVERHAUL.PARTIAL then
                    return g_i18n:getText("rms_ws_overhaul_fluids_all"), 2
                elseif not hasPartialOil then
                    return "-", 0
                end
                return g_i18n:getText("rms_ws_overhaul_fluids_own"), 1
            end }
    }

    -- every extent renews the fuel and hydraulic filters the machine carries
    local hasFuel = RMS_Consumables.getHasFilter(vehicle, RMS_Consumables.getFilterOfBreakdown("FUEL_FILTER_CLOGGING"))
    local hasHydraulic = RMS_Consumables.getHasFilter(vehicle, RMS_Consumables.getFilterOfBreakdown("HYDRAULIC_FILTER_CLOGGING"))
    if hasFuel or hasHydraulic then
        local detailKey = not hasFuel and "rms_ws_levels_filters_hydraulic"
            or (hasHydraulic and "rms_ws_overhaul_filters_both" or "rms_ws_overhaul_filters_fuel")
        table.insert(rows, { name = g_i18n:getText("rms_ws_levels_filters"), detail = g_i18n:getText(detailKey),
            getCell = every(hasFuel and hasHydraulic and "rms_ws_levels_new_plural" or "rms_ws_levels_new") })
    end
    table.insert(rows, { name = g_i18n:getText("rms_ws_inspection_report"), detail = g_i18n:getText("rms_ws_inspection_report_detail"),
        getCell = every("rms_ws_inspection_measures") })
    return rows
end

---Writes the corner of the table
local function updateTableCorner(dialog, workshopType)
    local vehicle = dialog.vehicle
    local STATUS = RealisticMechanicalSystems.STATUS
    local label, name, reason, color = "rms_ws_levels_recommended_for", "", "", dialog.levelCornerNameColor
    if dialog.maintenanceType == STATUS.MAINTENANCE then
        name = RMS_Utils.formatMaintenanceLevel(vehicle, vehicle:getDueMaintenanceType())
        reason = RMS_Utils.formatServiceDue(vehicle, vehicle:getServiceSchedule(), true)
    elseif dialog.maintenanceType == STATUS.REPAIR then
        local DEALER = RealisticMechanicalSystems.WORKSHOP.DEALER
        local isCovered = vehicle:isWarrantyRepairCovered(RealisticMechanicalSystems.REPAIR_TYPES.MEDIUM,
            RealisticMechanicalSystems.PART_TYPES.OEM, DEALER)
        label = "rms_ws_warranty_title"
        name = g_i18n:getText(isCovered and "rms_ws_warranty_covered" or "rms_ws_warranty_not_covered")
        reason = g_i18n:getText(not isCovered and "rms_ws_warranty_terms"
            or (workshopType == DEALER and "rms_ws_warranty_free_here" or "rms_ws_warranty_free_dealer"))
        color = isCovered and color or RMS_Utils.COLOR.TEXT
    else
        label = "rms_ws_overhaul_worn"
        name = string.format(g_i18n:getText("rms_ws_table_count"), #RMS_Utils.getEligibleOverhaulSystems(vehicle),
            #RMS_Utils.getOverhaulSystems(vehicle))
        color = RMS_Breakdowns.COLORS.WARNING
    end
    dialog.levelRecommendedLabel:setText(g_i18n:getText(label))
    dialog.levelRecommendedName:setText(name)
    dialog.levelRecommendedName:setTextColor(unpack(color))
    dialog.levelRecommendedReason:setText(reason)
end

---Lays the table of the order out and writes each column
-- @param table dialog dialog instance
-- @param string workshopType workshop type
-- @param string? optionTwo consumables or part quality sent with a maintenance or a repair
function RMS_MaintenanceThreeOptionsDialog.updateChoiceTable(dialog, workshopType, optionTwo)
    local vehicle = dialog.vehicle
    local STATUS = RealisticMechanicalSystems.STATUS
    local serviceType = dialog.maintenanceType
    local choices = dialog.optionOneValues
    local rows, due
    if serviceType == STATUS.MAINTENANCE then
        rows = RMS_MaintenanceThreeOptionsDialog.getLevelRows(vehicle, workshopType)
        due = vehicle:getDueMaintenanceType()
    elseif serviceType == STATUS.REPAIR then
        rows = RMS_MaintenanceThreeOptionsDialog.getRepairRows(vehicle)
    else
        rows = RMS_MaintenanceThreeOptionsDialog.getOverhaulRows(vehicle, dialog.selectedOptionTwo)
    end
    local isInstant = serviceType == STATUS.OVERHAUL and RMS_Config.MAINTENANCE.INSTANT_OVERHAUL
        or serviceType ~= STATUS.OVERHAUL and RMS_Config.MAINTENANCE.INSTANT_MAINTENANCE_REPAIR
    local unitX, unitY = dialog.levelTablePixel[1], dialog.levelTablePixel[2]
    local columnWidth = (LEVEL_TABLE_WIDTH - LEVEL_LABEL_WIDTH - LEVEL_GAP * #choices) / #choices
    local height = LEVEL_HEADER + #rows * LEVEL_ROW + LEVEL_BOTTOM
    dialog.levelTable:setSize(nil, height * unitY)
    updateTableCorner(dialog, workshopType)

    for index, name in ipairs(dialog.levelRowName) do
        local row = rows[index]
        local y = LEVEL_HEADER + (index - 1) * LEVEL_ROW
        local hasIcon = row ~= nil and row.icon ~= nil
        local hasDetail = row ~= nil and row.detail ~= ""
        local x = hasIcon and 34 or 0
        dialog.levelRowRule[index]:setVisible(row ~= nil)
        dialog.levelRowIcon[index]:setVisible(hasIcon)
        name:setVisible(row ~= nil)
        dialog.levelRowDetail[index]:setVisible(hasDetail)
        if hasIcon then
            dialog.levelRowIcon[index]:applyProfile(row.icon, true)
        end
        if row ~= nil then
            name:setPosition(x * unitX, -(y + (hasDetail and 5 or 12)) * unitY)
            name:setSize((LEVEL_LABEL_WIDTH - x - 4) * unitX, nil)
            name:setText(row.name)
            dialog.levelRowDetail[index]:setPosition(x * unitX, -(y + 24) * unitY)
            dialog.levelRowDetail[index]:setSize((LEVEL_LABEL_WIDTH - x - 4) * unitX, nil)
            dialog.levelRowDetail[index]:setText(row.detail)
        end
    end

    for column, button in ipairs(dialog.levelColumns) do
        local choice = choices[column]
        button:setVisible(choice ~= nil)
        if choice ~= nil then
            button:setPosition((LEVEL_LABEL_WIDTH + LEVEL_GAP + (column - 1) * (columnWidth + LEVEL_GAP)) * unitX, nil)
            button:setSize(columnWidth * unitX, height * unitY)
            button:setSelected(choice == dialog.selectedOptionOne)
            dialog.levelColumnFrame[column]:setSize(columnWidth * unitX, height * unitY)
            dialog.levelColumnBg[column]:setSize((columnWidth - 4) * unitX, (height - 4) * unitY)

            -- a partial overhaul is priced on the system chosen, the others on every system
            local choiceOptionTwo = optionTwo
            if serviceType == STATUS.OVERHAUL then
                choiceOptionTwo = choice == RealisticMechanicalSystems.OVERHAUL_TYPES.PARTIAL and dialog.selectedOptionTwo or "NONE"
            end
            local price = RMS_FluidWorkshop.getTransactionPrice(vehicle, serviceType, workshopType, choice, choiceOptionTwo, dialog.selectedOptionThree)
            local duration = vehicle:getServiceDuration(serviceType, choice, choiceOptionTwo, dialog.selectedOptionThree, workshopType)

            -- the schedule marks the level due, the warranty the repair it covers
            local badgeKey = nil
            if choice == due then
                badgeKey = "rms_spec_state_recommended"
            elseif serviceType == STATUS.REPAIR and vehicle:isWarrantyRepairCovered(choice, optionTwo, workshopType) then
                badgeKey = "rms_ws_badge_warranty"
            end
            dialog.levelBadge[column]:setPosition((columnWidth / 2 - 52) * unitX, nil)
            dialog.levelBadgeText[column]:setPosition((columnWidth / 2 - 52) * unitX, nil)
            dialog.levelBadge[column]:setVisible(badgeKey ~= nil)
            dialog.levelBadgeText[column]:setVisible(badgeKey ~= nil)
            dialog.levelBadgeText[column]:setText(badgeKey ~= nil and g_i18n:getText(badgeKey) or "")

            local texts = {
                [dialog.levelName[column]] = serviceType == STATUS.MAINTENANCE and RMS_Utils.formatMaintenanceLevel(vehicle, choice)
                    or g_i18n:getText(choice),
                [dialog.levelPrice[column]] = price ~= nil and g_i18n:formatMoney(price, 0, true, false) or "-",
                [dialog.levelDuration[column]] = (isInstant and duration > 0) and g_i18n:getText("rms_option_menu_duration_instant")
                    or RMS_Utils.formatShortDuration(duration)
            }
            for element, text in pairs(texts) do
                element:setSize((columnWidth - 8) * unitX, nil)
                element:setText(text)
            end

            for index, rule in ipairs(dialog["levelCellRule" .. column]) do
                local row = rows[index]
                rule:setVisible(row ~= nil)
                rule:setSize((columnWidth - 20) * unitX, nil)
                local text, kind = "", nil
                if row ~= nil then
                    text, kind = row.getCell(choice)
                end
                for cellKind, suffix in pairs(LEVEL_CELL_KINDS) do
                    local cell = dialog["levelCell" .. suffix .. column][index]
                    cell:setVisible(cellKind == kind)
                    cell:setSize((columnWidth - 8) * unitX, nil)
                    cell:setText(text)
                end
            end
        end
    end

    -- under the levels, what every one of them does besides
    if serviceType == STATUS.MAINTENANCE then
        local footer = g_i18n:getText("rms_ws_levels_every_level")
        for _, clock in ipairs(vehicle:getServiceClocks()) do
            if clock.estimated then
                footer = footer .. " " .. g_i18n:getText("rms_service_program_estimated")
                break
            end
        end
        dialog.levelFooter:setText(footer)
    end
end

---Writes the cards of the systems a partial overhaul can take
-- @param table dialog dialog instance
-- @param table labels name of each system
function RMS_MaintenanceThreeOptionsDialog.updateSystemCards(dialog, labels)
    local rowCount = math.ceil(#dialog.optionTwoValues / SYSTEM_CARDS_PER_ROW)
    for index, card in ipairs(dialog.overhaulSystemCard) do
        local system = dialog.optionTwoValues[index]
        card:setVisible(system ~= nil)
        card:setSelected(system ~= nil and system == dialog.selectedOptionTwo)
        dialog.overhaulSystemName[index]:setText(labels[index] or "")
    end
    dialog.overhaulSystemRow:setSize(nil, (rowCount * SYSTEM_CARD_HEIGHT + (rowCount - 1) * SYSTEM_CARD_GAP) * dialog.levelTablePixel[2])
end

-- chance of a later defect a quality card colours yellow up to, then orange up to, then red
local QUALITY_RISK_LOW, QUALITY_RISK_HIGH = 0.2, 0.4
-- shortest fill of the gauge of a quality, as a share of its track
local QUALITY_GAUGE_MIN = 0.04

---Writes the quality cards of a maintenance or a repair
-- @param table dialog dialog instance
-- @param string workshopType workshop type
-- @param table labels name of each quality
-- @param boolean disabled true when the order fits no part
function RMS_MaintenanceThreeOptionsDialog.updateQualityCards(dialog, workshopType, labels, disabled)
    local vehicle = dialog.vehicle
    local original = RealisticMechanicalSystems.PART_TYPES.OEM
    local prices = {}
    for _, quality in ipairs(dialog.optionTwoValues) do
        prices[quality] = RMS_FluidWorkshop.getTransactionPrice(vehicle, dialog.maintenanceType, workshopType,
            dialog.selectedOptionOne, quality, dialog.selectedOptionThree)
    end

    for index, card in ipairs(dialog.qualityCard) do
        local quality = dialog.optionTwoValues[index]
        local price = prices[quality]
        local priceText, delta = "-", ""
        if price ~= nil then
            priceText = g_i18n:formatMoney(price, 0, true, false)
            local gap = prices[original] ~= nil and price - prices[original] or 0
            if math.abs(gap) >= 0.5 then
                delta = string.format(g_i18n:getText("rms_ws_quality_delta"),
                    (gap < 0 and "-" or "+") .. g_i18n:formatMoney(math.abs(gap), 0, true, false))
            end
        end
        if quality == original then
            delta = g_i18n:getText("rms_ws_quality_reference")
        end

        local chance = RMS_Config.MAINTENANCE.PARTS_BREAKDOWN_CHANCES[
            RMS_Utils.getKeyByValue(RealisticMechanicalSystems.PART_TYPES, quality)]
        local r, g, b, a = RMS_Utils.getValueColorInverted(chance, 0, 0, QUALITY_RISK_LOW, QUALITY_RISK_HIGH)
        card:setSelected(quality == dialog.selectedOptionTwo)
        card:setDisabled(disabled)
        dialog.qualityName[index]:setText(labels[index])
        dialog.qualityPrice[index]:setText(priceText)
        dialog.qualityDelta[index]:setText(delta)
        dialog.qualityRisk[index]:setText(string.format("%d%%", math.floor(chance * 100 + 0.5)))
        dialog.qualityRisk[index]:setTextColor(r, g, b, a)
        dialog.qualityGauge[index].color = { r, g, b, a }
        dialog.qualityGauge[index]:setVisible(chance > 0)
        dialog.qualityGauge[index]:setSize(math.max(chance, QUALITY_GAUGE_MIN) * dialog.qualityGaugeWidth, nil)
    end
end

---Tells who pays a job for the farm, the warranty or the lease
-- @param table vehicle vehicle
-- @param string serviceType service status
-- @param string? optionOne first option chosen
-- @param string? optionTwo second option chosen
-- @param string workshopType workshop type
-- @return string? coverKey "warranty" or "lease", nil when the farm pays
function RMS_MaintenanceThreeOptionsDialog.getCoverKey(vehicle, serviceType, optionOne, optionTwo, workshopType)
    local STATUS = RealisticMechanicalSystems.STATUS
    if serviceType == STATUS.REPAIR and vehicle:isWarrantyRepairCovered(optionOne, optionTwo, workshopType) then
        return "warranty"
    elseif serviceType == STATUS.MAINTENANCE and vehicle:isLeaseMaintenanceCovered(workshopType) then
        return "lease"
    end
    return nil
end

---Quotes the bill of the order in the recap, laid out in groups
-- @param table dialog dialog instance
-- @param string workshopType workshop type
-- @param string? optionTwo second option sent
-- @param string? coverKey "warranty" for a repair the warranty pays, "lease" for a maintenance the lease pays
function RMS_MaintenanceThreeOptionsDialog.updateQuote(dialog, workshopType, optionTwo, coverKey)
    local vehicle = dialog.vehicle
    local invoice = RMS_FluidWorkshop.getTransactionInvoice(vehicle, dialog.maintenanceType, workshopType,
        dialog.selectedOptionOne, optionTwo, dialog.selectedOptionThree)
    local groups, gathered = {}, {}
    local shortages = RMS_FluidWorkshop.getStockShortages(vehicle, g_workshopScreen.sellingPoint, dialog.maintenanceType, workshopType,
        RMS_FluidWorkshop.getTransactionRequirements(vehicle, dialog.maintenanceType, dialog.selectedOptionOne, optionTwo))
    dialog.hasStockShortage = next(shortages) ~= nil
    for _, row in ipairs(invoice ~= nil and RMS_FluidWorkshop.getInvoiceRows(vehicle, dialog.maintenanceType, dialog.selectedOptionOne, invoice) or {}) do
        if QUOTE_GROUP_KEYS[row.kind] ~= nil then
            local group = gathered[row.kind]
            if group == nil then
                group = { label = g_i18n:getText(QUOTE_GROUP_KEYS[row.kind]), lines = {} }
                gathered[row.kind] = group
                table.insert(groups, group)
            end
            table.insert(group.lines, { label = row.label, price = row.price })
            if row.price ~= nil then
                group.price = (group.price or 0) + row.price
            end
            if shortages[row.circuit] ~= nil then
                table.insert(group.lines, { isAlert = true, note = string.format(g_i18n:getText("rms_fluid_stock_missing"),
                    RMS_FluidWorkshop.formatLiters(shortages[row.circuit]) .. " " .. g_i18n:getText("unit_literShort")) })
            end
        else
            local group = { label = row.label, price = row.price, lines = {} }
            table.insert(groups, group)
            if row.kind == "filters" then
                local fitted = getFittedFilters(vehicle, dialog.selectedOptionOne)
                for index = 1, #fitted, 2 do
                    table.insert(group.lines, { note = fitted[index], second = fitted[index + 1], isBullet = true })
                end
            end
        end
    end
    -- an unpriced fluid comes from the farm's drums or is covered
    if gathered.fluid ~= nil and not dialog.hasStockShortage
        and (coverKey ~= nil or workshopType ~= RealisticMechanicalSystems.WORKSHOP.DEALER) then
        table.insert(gathered.fluid.lines, { note = g_i18n:getText(coverKey ~= nil and COVER_TEXTS[coverKey].fluids or "rms_fluid_stock_required") })
    end

    local rows, height = {}, 0
    for index, group in ipairs(groups) do
        table.insert(rows, { isHead = true, isFirst = index == 1, label = group.label, price = group.price })
        height = height + QUOTE_HEAD + (index == 1 and 0 or QUOTE_HEAD_GAP)
        for _, line in ipairs(group.lines) do
            table.insert(rows, line)
            height = height + (line.note ~= nil and QUOTE_NOTE or QUOTE_LINE)
        end
    end

    local isScrolling = height > QUOTE_LIST
    local blockHeight = (QUOTE_TOP + math.min(height, QUOTE_LIST) + QUOTE_BOTTOM) * dialog.quotePixel[2]
    dialog.quoteLines = rows
    dialog.quoteRowWidth = isScrolling and QUOTE_ROW_WIDTH - QUOTE_SLIDER_ROOM or QUOTE_ROW_WIDTH
    dialog.recapQuoteBlock:setVisible(#rows > 0)
    dialog.recapQuoteBlock:setSize(nil, blockHeight)
    dialog.recapQuoteSurface:setSize(nil, blockHeight)
    dialog.recapQuoteSliderBox:setVisible(isScrolling)
    dialog.recapQuoteList:reloadData(true)
end

---Returns the number of rows of the quote
-- @return integer count row count
function RMS_MaintenanceThreeOptionsDialog:getNumberOfItemsInSection(list, section)
    return #self.quoteLines
end

---Returns the template of a row of the quote
-- @return string name template name
function RMS_MaintenanceThreeOptionsDialog:getCellTypeForItemInSection(list, section, index)
    local row = self.quoteLines[index]
    if row == nil then
        return "quoteLine"
    elseif row.isHead then
        return row.isFirst and "quoteHead" or "quoteHeadGap"
    end
    if row.isAlert then
        return "quoteAlert"
    end
    return row.note ~= nil and "quoteNote" or "quoteLine"
end

---Writes a row of the quote
function RMS_MaintenanceThreeOptionsDialog:populateCellForItemInSection(list, section, index, cell)
    local row = self.quoteLines[index]
    local unitX = self.quotePixel[1]
    local width = self.quoteRowWidth
    if row.isAlert then
        local alert = cell:getAttribute("quoteAlertText")
        alert:setSize((width - QUOTE_INDENT) * unitX, nil)
        alert:setText(row.note)
        return
    end
    if row.note ~= nil then
        local note, second = cell:getAttribute("quoteNoteText"), cell:getAttribute("quoteNoteText2")
        local bullet, secondBullet = cell:getAttribute("quoteNoteBullet"), cell:getAttribute("quoteNoteBullet2")
        local half = (width - QUOTE_INDENT) / 2
        local textX = QUOTE_INDENT + (row.isBullet and QUOTE_BULLET_TEXT or 0)
        bullet:setVisible(row.isBullet == true)
        note:setPosition(textX * unitX, nil)
        note:setSize((row.isBullet and half - QUOTE_BULLET_TEXT or width - QUOTE_INDENT) * unitX, nil)
        note:setText(row.note)
        secondBullet:setVisible(row.second ~= nil)
        secondBullet:setPosition((QUOTE_INDENT + half + QUOTE_BULLET_X) * unitX, nil)
        second:setVisible(row.second ~= nil)
        second:setPosition((textX + half) * unitX, nil)
        second:setSize((half - QUOTE_BULLET_TEXT) * unitX, nil)
        second:setText(row.second or "")
        return
    end
    local name, amount = cell:getAttribute("quoteName"), cell:getAttribute("quoteAmount")
    local nameX = row.isHead and 0 or QUOTE_INDENT
    if row.isHead and not row.isFirst then
        cell:getAttribute("quoteRule"):setSize(width * unitX, nil)
    end
    name:setSize((width - nameX - QUOTE_AMOUNT - QUOTE_GAP) * unitX, nil)
    name:setText(row.label)
    amount:setPosition((width - QUOTE_AMOUNT) * unitX, nil)
    amount:setText(row.price ~= nil and g_i18n:formatMoney(row.price, 0, true, false) or "")
end

---Rebuilds the visible work order, recap values and contextual descriptions
function RMS_MaintenanceThreeOptionsDialog:updateScreen()
    if self.vehicle == nil then return end

    local spec = self.vehicle.spec_RealisticMechanicalSystems
    local workshopType = RMS_WorkshopDialog.INSTANCE ~= nil and RMS_WorkshopDialog.INSTANCE.workshopType or spec.workshopType
    local isRefill = self.maintenanceType == RealisticMechanicalSystems.STATUS.REFILL
    local hasFollowUp = self.maintenanceType == RealisticMechanicalSystems.STATUS.MAINTENANCE
        or self.maintenanceType == RealisticMechanicalSystems.STATUS.REPAIR

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
    local choiceIndexByType = {
        [RealisticMechanicalSystems.STATUS.INSPECTION] = 1,
        [RealisticMechanicalSystems.STATUS.MAINTENANCE] = 2,
        [RealisticMechanicalSystems.STATUS.REPAIR] = 3,
        [RealisticMechanicalSystems.STATUS.OVERHAUL] = 4,
        [RealisticMechanicalSystems.STATUS.REFILL] = 5
    }
    local selectedChoiceIndex = choiceIndexByType[self.maintenanceType]
    for index, button in ipairs(self.configChoiceButtons or {}) do
        button:setSelected(index == selectedChoiceIndex)
    end
    local isTopUpOffered = RMS_FluidWorkshop.getIsTopUpOffered(workshopType)
    self.configChoiceButtons[5]:setVisible(isTopUpOffered)
    self.configChoiceButtons[5].parent:invalidateLayout()
    self.shortcutButtons[5]:setVisible(isTopUpOffered)
    self.refillShortcutSeparator:setVisible(isTopUpOffered)
    self.shortcutButtons[5].parent:invalidateLayout()
    -- the bottom bar carries the workshop shortcuts and closes with the list beside it
    for index, button in ipairs(self.shortcutButtons) do
        button:setDisabled(self.configChoiceButtons[index]:getIsDisabled())
    end

    -- title
    self.recapType:setText(g_i18n:getText(isRefill and "rms_fluid_refill_work_order" or self.maintenanceType))

    -- the levels, methods or extents of the order, side by side in its table
    local STATUS = RealisticMechanicalSystems.STATUS
    local optionOneText = ""
    local optionOneValues = {}
    if self.maintenanceType == STATUS.MAINTENANCE then
        optionOneText = g_i18n:getText("rms_option_menu_option_one_title_maintenance")
        optionOneValues = self.vehicle:getMaintenanceTypes()
    elseif self.maintenanceType == STATUS.REPAIR then
        optionOneText = g_i18n:getText("rms_option_menu_option_one_title_repair")
        -- a running breakdown can be quick fixed, a dormant or quick fixed one only replaced
        local hasTicked, hasRunning = false, false
        for _, breakdown in pairs(self.vehicle:getActiveBreakdowns()) do
            if breakdown.isSelectedForRepair and breakdown.isVisible then
                hasTicked = true
                hasRunning = hasRunning or breakdown.isActive
            end
        end
        if hasRunning then
            table.insert(optionOneValues, RealisticMechanicalSystems.REPAIR_TYPES.LOW)
        end
        if hasTicked then
            table.insert(optionOneValues, RealisticMechanicalSystems.REPAIR_TYPES.MEDIUM)
            table.insert(optionOneValues, RealisticMechanicalSystems.REPAIR_TYPES.HIGH)
        end
    elseif self.maintenanceType == STATUS.OVERHAUL then
        optionOneText = g_i18n:getText("rms_option_menu_option_one_title_overhaul")
        optionOneValues = {
            RealisticMechanicalSystems.OVERHAUL_TYPES.PARTIAL,
            RealisticMechanicalSystems.OVERHAUL_TYPES.STANDARD,
            RealisticMechanicalSystems.OVERHAUL_TYPES.FULL
        }
    end
    self.optionOneValues = optionOneValues
    if self.optionOneValues[1] == nil then
        self.selectedOptionOne = nil
    elseif RMS_Utils.getKeyByValue(self.optionOneValues, self.selectedOptionOne) == nil then
        self.selectedOptionOne = self.optionOneValues[1]
    end
    self.optionOneText:setText(optionOneText)

    -- the consumables or the part quality on their cards, the system of a partial overhaul on its own
    local optionTwoText = ""
    local optionTwoValues = {}
    if self.maintenanceType == STATUS.MAINTENANCE then
        optionTwoText = g_i18n:getText("rms_option_menu_option_two_title_maintenance")
        optionTwoValues = RealisticMechanicalSystems.PART_TYPES_ORDER
    elseif self.maintenanceType == STATUS.REPAIR then
        optionTwoText = g_i18n:getText("rms_option_menu_option_two_title_repair")
        optionTwoValues = RealisticMechanicalSystems.PART_TYPES_ORDER
    elseif self.maintenanceType == STATUS.OVERHAUL then
        optionTwoText = g_i18n:getText("rms_option_menu_option_two_title_overhaul")
        self.overhaulSystemValues = RMS_Utils.getEligibleOverhaulSystems(self.vehicle)
        optionTwoValues = self.overhaulSystemValues
    end

    local maintenanceConsumableTextKeys = {
        [RealisticMechanicalSystems.PART_TYPES.USED] = "rms_spec_consumable_types_used",
        [RealisticMechanicalSystems.PART_TYPES.AFTERMARKET] = "rms_spec_consumable_types_aftermarket",
        [RealisticMechanicalSystems.PART_TYPES.OEM] = "rms_spec_consumable_types_oem",
        [RealisticMechanicalSystems.PART_TYPES.PREMIUM] = "rms_spec_consumable_types_premium"
    }
    local optionTwoLabels = {}
    for _, optionValue in ipairs(optionTwoValues) do
        local textKey = self.maintenanceType == STATUS.MAINTENANCE
            and maintenanceConsumableTextKeys[optionValue]
            or RMS_Utils.getSystemLabel(self.vehicle, optionValue)
        table.insert(optionTwoLabels, g_i18n:getText(textKey))
    end

    self.optionTwoValues = optionTwoValues
    self.optionTwoText:setText(optionTwoText)
    if self.optionTwoValues[1] == nil then
        self.selectedOptionTwo = nil
    elseif RMS_Utils.getKeyByValue(self.optionTwoValues, self.selectedOptionTwo) == nil then
        self.selectedOptionTwo = self.optionTwoValues[1]
    end

    local isMaintenance = self.maintenanceType == STATUS.MAINTENANCE
    local requiresOverhaulSystem = self.maintenanceType == STATUS.OVERHAUL
        and self.selectedOptionOne == RealisticMechanicalSystems.OVERHAUL_TYPES.PARTIAL
    local showQualities = isMaintenance or self.maintenanceType == STATUS.REPAIR
    self.optionOneText:setVisible(not isRefill)
    self.levelTable:setVisible(not isRefill)
    self.levelFooter:setVisible(isMaintenance)
    self.optionTwoText:setVisible(showQualities or requiresOverhaulSystem)
    self.qualityRow:setVisible(showQualities)
    self.overhaulSystemRow:setVisible(requiresOverhaulSystem)
    self.optionThreeGroup:setVisible(hasFollowUp)
    self.refillGroup:setVisible(isRefill)
    if showQualities then
        -- a quick fix fits no part
        RMS_MaintenanceThreeOptionsDialog.updateQualityCards(self, workshopType, optionTwoLabels,
            self.selectedOptionOne == RealisticMechanicalSystems.REPAIR_TYPES.LOW)
    end
    if requiresOverhaulSystem then
        RMS_MaintenanceThreeOptionsDialog.updateSystemCards(self, optionTwoLabels)
    end

    local isAllowedInMobileWorkshop = RMS_FluidWorkshop.getMobileWorkshopAvailability(
        self.vehicle,
        self.maintenanceType,
        workshopType,
        self.selectedOptionOne
    )
    local isWorkshopOpen = RMS_WorkshopDialog.getIsWorkshopOpen()

    -- price, duration, finishtime
    local coverKey = RMS_MaintenanceThreeOptionsDialog.getCoverKey(self.vehicle, self.maintenanceType, self.selectedOptionOne,
        self.selectedOptionTwo, workshopType)
    local effectiveOptionTwo = getEffectiveOptionTwo(self)
    local servicePrice = RMS_FluidWorkshop.getTransactionPrice(self.vehicle, self.maintenanceType, workshopType, self.selectedOptionOne, effectiveOptionTwo, self.selectedOptionThree)
    local priceValue = ""

    if servicePrice == nil then
        priceValue = g_i18n:getText("rms_fluid_service_price_unavailable")
    elseif coverKey ~= nil and servicePrice <= RMS_Fluids.EPSILON then
        priceValue = g_i18n:getText(COVER_TEXTS[coverKey].price)
    else
        priceValue = g_i18n:formatMoney(servicePrice, 0, true, false)
    end
    local duration = self.vehicle:getServiceDuration(self.maintenanceType, self.selectedOptionOne, effectiveOptionTwo, self.selectedOptionThree, workshopType)
    local isInstantService = RMS_Config.MAINTENANCE.INSTANT_MAINTENANCE_REPAIR
        and (self.maintenanceType == RealisticMechanicalSystems.STATUS.MAINTENANCE
            or self.maintenanceType == RealisticMechanicalSystems.STATUS.REPAIR)
        and duration > 0
    local durationValue = isInstantService and g_i18n:getText("rms_option_menu_duration_instant")
        or RMS_Utils.formatDuration(duration)
    local finishTime, daysToAdd = self.vehicle:getServiceFinishTime(self.maintenanceType, self.selectedOptionOne, effectiveOptionTwo, self.selectedOptionThree, workshopType)
    local finishTimeValue = RMS_Utils.formatFinishTime(finishTime, daysToAdd)

    self.recapPriceLabel:setText(stripTrailingColon(g_i18n:getText("rms_option_menu_price_text")))
    self.recapPrice:setText(priceValue)
    self.recapDurationLabel:setText(stripTrailingColon(g_i18n:getText("rms_option_menu_duration_text")))
    self.recapDuration:setText(durationValue)
    self.recapFinishLabel:setText(stripTrailingColon(g_i18n:getText("rms_option_menu_finish_time_text")))
    self.recapFinish:setText(finishTimeValue)
    local requirements = RMS_FluidWorkshop.getTransactionRequirements(
        self.vehicle,
        self.maintenanceType,
        self.selectedOptionOne,
        effectiveOptionTwo
    )
    local hasFluids = #requirements > 0
    RMS_MaintenanceThreeOptionsDialog.updateQuote(self, workshopType, effectiveOptionTwo, coverKey)

    if isRefill then
        updateRefillPresentation(self, requirements, g_i18n:getText("rms_fluid_refill_dealer_supply"))
    end

    if not isRefill then
        RMS_MaintenanceThreeOptionsDialog.updateChoiceTable(self, workshopType, effectiveOptionTwo)
    end

    -- the refusal of the mobile workshop is written under the table
    self.optionOneDisclaimer:setVisible(not isAllowedInMobileWorkshop)
    if not isAllowedInMobileWorkshop then
        self.optionOneDisclaimer:setText(RMS_FluidWorkshop.getMobileWorkshopRestrictionText(
            self.vehicle, self.maintenanceType, workshopType, self.selectedOptionOne))
        self.optionOneDisclaimer:setTextColor(unpack(RMS_Utils.COLOR.ALERT))
    end

    -- option three
    local optionThreeText = ""
    local optionThreeDisclaimerText = ""
    if self.maintenanceType == RealisticMechanicalSystems.STATUS.MAINTENANCE then
        optionThreeText = g_i18n:getText("rms_option_menu_perform_repair")
        optionThreeDisclaimerText = g_i18n:getText("rms_option_menu_option_three_disclaimer_repair_after_detection")
    elseif self.maintenanceType == RealisticMechanicalSystems.STATUS.REPAIR then
        optionThreeText = g_i18n:getText("rms_option_menu_perform_maintenance")
        optionThreeDisclaimerText = g_i18n:getText("rms_option_menu_option_three_disclaimer_maintenance_after_repair")
    end

    if self.maintenanceType == RealisticMechanicalSystems.STATUS.OVERHAUL then
        self.selectedOptionThree = false
    end

    if self.selectedOptionThree and hasFollowUp then
        optionThreeDisclaimerText = optionThreeDisclaimerText .. " " .. g_i18n:getText("rms_option_menu_follow_up_separate_transaction")
    end
    self.optionThreeText:setText(optionThreeText)
    self.optionThreeDisclaimer:setText(stripLeadingMarker(optionThreeDisclaimerText))
    self.recapAddonBlock:setVisible(hasFollowUp)
    RMS_Utils.updateRecapVehicleCard(self, hasFollowUp)
    self.recapVehicle:setText(self.vehicle.getFullName ~= nil and self.vehicle:getFullName() or g_i18n:getText("ui_vehicle"))
    if hasFollowUp then
        self.recapAddonLabel:setText(optionThreeText)
        self.recapAddon:setText(g_i18n:getText(self.selectedOptionThree and BinaryOptionElement.STRING_YES or BinaryOptionElement.STRING_NO))
    end
    RMS_WorkshopDialog.updateFollowUpCards(self)

    if self.startServiceButton ~= nil then
        local hasValidSelection = isRefill and hasFluids or self.selectedOptionOne ~= nil
        if self.maintenanceType == RealisticMechanicalSystems.STATUS.OVERHAUL then
            hasValidSelection = #self.overhaulSystemValues > 0
                and (self.selectedOptionOne ~= RealisticMechanicalSystems.OVERHAUL_TYPES.PARTIAL
                    or self.selectedOptionTwo ~= nil)
        end
        self.startServiceButton:setDisabled(not hasValidSelection or not isAllowedInMobileWorkshop or not isWorkshopOpen
            or self.hasStockShortage)
    end

    -- the recap names the two settings, the parts themselves are listed in the work order
    local optionTexts = {}
    if self.selectedOptionOne ~= nil then
        table.insert(optionTexts, RMS_Utils.formatServiceOption(self.vehicle, self.maintenanceType, self.selectedOptionOne))
    end
    if self.maintenanceType == RealisticMechanicalSystems.STATUS.MAINTENANCE then
        local consumableTextKey = maintenanceConsumableTextKeys[self.selectedOptionTwo]
        if consumableTextKey ~= nil then
            table.insert(optionTexts, g_i18n:getText(consumableTextKey))
        end
    elseif effectiveOptionTwo ~= nil and effectiveOptionTwo ~= "NONE" then
        table.insert(optionTexts, g_i18n:getText(RMS_Utils.getSystemLabel(self.vehicle, effectiveOptionTwo)))
    end

    local workshopTypeKey = RMS_Utils.getKeyByValue(RealisticMechanicalSystems.WORKSHOP, workshopType)
    local workshopTypeText = workshopTypeKey ~= nil and g_i18n:getText(workshopType) or ""
    local availabilityText = g_i18n:getText(isWorkshopOpen and "rms_ws_status_open" or "rms_ws_status_closed")
    if workshopTypeText ~= "" then
        availabilityText = availabilityText .. " · " .. workshopTypeText
    end

    if isRefill then
        self.recapOptions:setText(g_i18n:getText("rms_fluid_refill_dealer_supply"))
    else
        self.recapOptions:setText(#optionTexts > 0 and table.concat(optionTexts, " · ") or "-")
    end
    self.configStatusText:setText(availabilityText)
    RMS_WorkshopDialog.refreshOrderScroll(self)
    self:updateFocusLinks()
end

---Chains the focus over the order being configured
function RMS_MaintenanceThreeOptionsDialog:updateFocusLinks()
    local procedures = {}
    for _, button in ipairs(self.configChoiceButtons) do
        table.insert(procedures, {button})
    end

    -- the columns, the system or quality cards, then the follow-up
    local systemRows = { {}, {} }
    for index, card in ipairs(self.overhaulSystemCard) do
        table.insert(systemRows[math.ceil(index / SYSTEM_CARDS_PER_ROW)], card)
    end
    local columns = {procedures, {self.levelColumns, systemRows[1], systemRows[2], self.qualityCard, self.optionThreeButtons},
        {{self.startServiceButton}}}
    local preferred = nil
    for index, column in ipairs(self.levelColumns) do
        if column:getIsVisible() and self.optionOneValues[index] == self.selectedOptionOne then
            preferred = column
        end
    end
    self.focusEntry = RMS_Utils.linkFocusColumns(self.workshopTabPaging, columns, preferred)
    RMS_Utils.keepFocusShown(self.focusEntry)
end

---Chooses the level, method or extent of a column of the table
function RMS_MaintenanceThreeOptionsDialog:onClickLevel1()
    self:onClickOptionOne(1)
end

---
function RMS_MaintenanceThreeOptionsDialog:onClickLevel2()
    self:onClickOptionOne(2)
end

---
function RMS_MaintenanceThreeOptionsDialog:onClickLevel3()
    self:onClickOptionOne(3)
end

---Chooses the quality of a card
function RMS_MaintenanceThreeOptionsDialog:onClickOptionTwoPreset1()
    self:onClickOptionTwo(1)
end

---
function RMS_MaintenanceThreeOptionsDialog:onClickOptionTwoPreset2()
    self:onClickOptionTwo(2)
end

---
function RMS_MaintenanceThreeOptionsDialog:onClickOptionTwoPreset3()
    self:onClickOptionTwo(3)
end

---
function RMS_MaintenanceThreeOptionsDialog:onClickOptionTwoPreset4()
    self:onClickOptionTwo(4)
end

---Chooses the system of a card for a partial overhaul
function RMS_MaintenanceThreeOptionsDialog:onClickOverhaulSystem1()
    self:onClickOptionTwo(1)
end

---
function RMS_MaintenanceThreeOptionsDialog:onClickOverhaulSystem2()
    self:onClickOptionTwo(2)
end

---
function RMS_MaintenanceThreeOptionsDialog:onClickOverhaulSystem3()
    self:onClickOptionTwo(3)
end

---
function RMS_MaintenanceThreeOptionsDialog:onClickOverhaulSystem4()
    self:onClickOptionTwo(4)
end

---
function RMS_MaintenanceThreeOptionsDialog:onClickOverhaulSystem5()
    self:onClickOptionTwo(5)
end

---
function RMS_MaintenanceThreeOptionsDialog:onClickOverhaulSystem6()
    self:onClickOptionTwo(6)
end

---
function RMS_MaintenanceThreeOptionsDialog:onClickOverhaulSystem7()
    self:onClickOptionTwo(7)
end

---
function RMS_MaintenanceThreeOptionsDialog:onClickOverhaulSystem8()
    self:onClickOptionTwo(8)
end

---
function RMS_MaintenanceThreeOptionsDialog:onClickConfigureInspection()
    RMS_WorkshopDialog.selectInterventionFromConfiguration(self, RealisticMechanicalSystems.STATUS.INSPECTION)
end

---
function RMS_MaintenanceThreeOptionsDialog:onClickConfigureMaintenance()
    RMS_WorkshopDialog.selectInterventionFromConfiguration(self, RealisticMechanicalSystems.STATUS.MAINTENANCE)
end

---
function RMS_MaintenanceThreeOptionsDialog:onClickConfigureRepair()
    RMS_WorkshopDialog.selectInterventionFromConfiguration(self, RealisticMechanicalSystems.STATUS.REPAIR)
end

---
function RMS_MaintenanceThreeOptionsDialog:onClickConfigureOverhaul()
    RMS_WorkshopDialog.selectInterventionFromConfiguration(self, RealisticMechanicalSystems.STATUS.OVERHAUL)
end

---
function RMS_MaintenanceThreeOptionsDialog:onClickConfigureRefill()
    RMS_WorkshopDialog.selectInterventionFromConfiguration(self, RealisticMechanicalSystems.STATUS.REFILL)
end

---
function RMS_MaintenanceThreeOptionsDialog:onClickConfigureBodywork()
    RMS_WorkshopDialog.selectInterventionFromConfiguration(self, RealisticMechanicalSystems.STATUS.BODYWORK)
end

---
function RMS_MaintenanceThreeOptionsDialog:onClickSummaryTab()
    RMS_WorkshopDialog.selectTabFromChildDialog(self, RMS_WorkshopDialog.TAB.SUMMARY)
end

---
function RMS_MaintenanceThreeOptionsDialog:onClickDiagnosticTab()
    RMS_WorkshopDialog.selectTabFromChildDialog(self, RMS_WorkshopDialog.TAB.DIAGNOSTIC)
end

---
function RMS_MaintenanceThreeOptionsDialog:onClickInterventionsTab()
    RMS_WorkshopDialog.selectTabFromChildDialog(self, RMS_WorkshopDialog.TAB.INTERVENTIONS)
end

---
function RMS_MaintenanceThreeOptionsDialog:onClickTechnicalTab()
    RMS_WorkshopDialog.selectTabFromChildDialog(self, RMS_WorkshopDialog.TAB.TECHNICAL)
end

---
function RMS_MaintenanceThreeOptionsDialog:onWorkshopTabPagingChanged()
    RMS_WorkshopDialog.onChildTabPagingChanged(self)
end

---Draws the native maintenance glyph in the intervention action list
-- @param table area transparent GUI element receiving the XML draw callback
function RMS_MaintenanceThreeOptionsDialog:onDrawMaintenanceActionIcon(area)
    RMS_WorkshopDialog.drawMaintenanceIcon(area, "rms_workshopMaintenanceActionIcon")
end

---Draws the RMS oil-level glyph in the intervention action list
-- @param table area transparent GUI element receiving the XML draw callback
function RMS_MaintenanceThreeOptionsDialog:onDrawOilActionIcon(area)
    RMS_WorkshopDialog.drawOilIcon(area, "rms_workshopOilActionIcon")
end

---Selects the service type option and refreshes the screen
-- @param integer index selected option index
function RMS_MaintenanceThreeOptionsDialog:onClickOptionOne(index)
    if self.optionOneValues ~= nil and self.optionOneValues[index] ~= nil then
        self.selectedOptionOne = self.optionOneValues[index]
    end
    self:updateScreen()
end

---Selects the part type or the overhaul system and refreshes the screen
-- @param integer index selected option index
function RMS_MaintenanceThreeOptionsDialog:onClickOptionTwo(index)
    self.selectedOptionTwo = self.optionTwoValues[index] or self.selectedOptionTwo
    self:updateScreen()
end

---
function RMS_MaintenanceThreeOptionsDialog:onClickOptionThreeNo()
    self.selectedOptionThree = false
    self:updateScreen()
end

---
function RMS_MaintenanceThreeOptionsDialog:onClickOptionThreeYes()
    self.selectedOptionThree = true
    self:updateScreen()
end

---Starts the service on the server, or asks it from a client
function RMS_MaintenanceThreeOptionsDialog:onClickStartService()
    local vehicle = self.vehicle
    local workshopType = RMS_WorkshopDialog.INSTANCE.workshopType
    if not RMS_FluidWorkshop.getMobileWorkshopAvailability(
        vehicle,
        self.maintenanceType,
        workshopType,
        self.selectedOptionOne
    ) or not RMS_WorkshopDialog.getIsWorkshopOpen() then
        return
    end

    local effectiveOptionTwo = getEffectiveOptionTwo(self)
    
    local price = RMS_FluidWorkshop.getTransactionPrice(vehicle, self.maintenanceType, workshopType, self.selectedOptionOne, effectiveOptionTwo, self.selectedOptionThree)
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
            self.maintenanceType,
            workshopType,
            self.selectedOptionOne,
            effectiveOptionTwo,
            self.selectedOptionThree
        )
        if not started then
            RMS_FluidWorkshop.showResult(result)
            return
        end
        RMS_VehicleChangeStatusEvent.send(vehicle)
    else
        RMS_ServiceRequestEvent.send(vehicle, self.maintenanceType, workshopType, self.selectedOptionOne, effectiveOptionTwo, self.selectedOptionThree)
    end

    self:close()
end

---Closes the dialog
function RMS_MaintenanceThreeOptionsDialog:onClickBack()
    self:close()
end



---Selects the interventions tab and binds the button backgrounds
function RMS_MaintenanceThreeOptionsDialog:onCreate()
    -- the quote lists its lines through the dialog; its sizes in reference pixels come from its layout
    self.quotePixel = { self.recapQuoteBlock.size[1] / QUOTE_WIDTH, self.recapQuoteBlock.size[2] / QUOTE_HEIGHT }
    self.quoteLines = {}
    self.recapQuoteList:setDataSource(self)
    self.recapQuoteList:setDelegate(self)

    self.refillGaugeWidths = self.refillGaugeWidths or {}
    for _, fields in ipairs(REFILL_ROW_FIELDS) do
        local gauge = self[fields.gauge]
        if gauge ~= nil then
            self.refillGaugeWidths[fields.gauge] = gauge.size[1]
        end
    end

    RMS_Utils.mirrorSelectionToChildren(self.workshopNavTabs[3])
    self.workshopNavTabs[3]:setSelected(true)

    for _, button in ipairs(self.configChoiceButtons or {}) do
        RMS_Utils.mirrorSelectionToChildren(button)
    end

    -- a quality or system card draws its frame, fill and name as chosen; a quality gauge fills the track laid out for it
    for _, cards in ipairs({ self.qualityCard, self.overhaulSystemCard }) do
        for _, card in ipairs(cards) do
            RMS_Utils.mirrorSelectionToChildren(card)
        end
    end
    self.qualityGaugeWidth = self.qualityGauge[1].size[1]

    for _, button in ipairs(self.optionThreeButtons or {}) do
        RMS_Utils.mirrorSelectionToChildren(button)
    end

    -- a level column draws its frame, fill, name and cells as chosen; its sizes in reference pixels come from its layout
    for _, column in ipairs(self.levelColumns) do
        RMS_Utils.mirrorSelectionToChildren(column)
    end
    self.levelTablePixel = { self.levelTable.size[1] / LEVEL_TABLE_WIDTH, self.levelTable.size[2] / LEVEL_TABLE_HEIGHT }
    self.levelCornerNameColor = { unpack(self.levelRecommendedName.textColor) }

    RMS_Utils.applyScrollSpeed(self.dialogElement)
end

---
function RMS_MaintenanceThreeOptionsDialog:onOpen()
    RMS_MaintenanceThreeOptionsDialog:superClass().onOpen(self)
    RMS_WorkshopDialog.initializeChildTabPaging(self, RMS_WorkshopDialog.TAB.INTERVENTIONS)
    RMS_WorkshopDialog.refreshOrderScroll(self)

    for _, button in ipairs(self.configChoiceButtons or {}) do
        RMS_Utils.centerActionContent(button)
    end

    RMS_Utils.resetScrollingTexts(self.dialogElement)
    g_messageCenter:subscribe(MessageType.MONEY_CHANGED, self.updateScreen, self)

    self:updateFocusLinks()
    FocusManager:setFocus(self.focusEntry)
end

---
function RMS_MaintenanceThreeOptionsDialog:onClose()
    self.vehicle = nil
    g_messageCenter:unsubscribeAll(self)

    RMS_MaintenanceThreeOptionsDialog:superClass().onClose(self)
end
