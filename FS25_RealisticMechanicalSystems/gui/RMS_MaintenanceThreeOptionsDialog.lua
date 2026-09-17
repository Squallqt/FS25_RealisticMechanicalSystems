-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---Shared configuration dialog for maintenance, repair, overhaul and refill services
RMS_MaintenanceThreeOptionsDialog = {}
RMS_MaintenanceThreeOptionsDialog.INSTANCE = nil

local RMS_MaintenanceThreeOptionsDialog_mt = Class(RMS_MaintenanceThreeOptionsDialog, MessageDialog)
local modDirectory = g_currentModDirectory

local REFILL_ROW_FIELDS = {
    {circuit = "engineOil", row = "refillEngineOilRow", level = "refillEngineOilLevel", amount = "refillEngineOilAmount", gauge = "refillEngineOilGauge"},
    {circuit = "coolant", row = "refillCoolantRow", level = "refillCoolantLevel", amount = "refillCoolantAmount", gauge = "refillCoolantGauge"},
    {circuit = "transmissionOil", row = "refillTransmissionOilRow", level = "refillTransmissionOilLevel", amount = "refillTransmissionOilAmount", gauge = "refillTransmissionOilGauge"},
    {circuit = "hydraulicFluid", row = "refillHydraulicFluidRow", level = "refillHydraulicFluidLevel", amount = "refillHydraulicFluidAmount", gauge = "refillHydraulicFluidGauge"}
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

---Returns a label without its trailing colon, the rows carrying it on their own line
-- @param string? text localized label
-- @return string text label without a trailing colon
local function stripTrailingColon(text)
    return (tostring(text or ""):gsub("%s*:%s*$", ""))
end

---Removes the legacy list marker from text presented in a dedicated description block
-- @param string? text localized description
-- @return string text description without a leading asterisk
local function stripLeadingMarker(text)
    return (tostring(text or ""):gsub("^%s*%*%s*", ""))
end

---Returns the systems a partial overhaul may target, every system when the spec is unreadable
-- @param table? vehicle vehicle
-- @return table values system l10n keys in declared order
local function getEnabledOverhaulSystemValues(vehicle)
    local values = {}
    local spec = vehicle ~= nil and vehicle.spec_RealisticMechanicalSystems or nil
    local allSystems = RealisticMechanicalSystems.SYSTEMS_ORDER

    if spec == nil or type(spec.systems) ~= "table" then
        return allSystems
    end

    for _, systemL10nKey in ipairs(allSystems) do
        local systemKey = RMS_Utils.getSystemKey(RealisticMechanicalSystems.SYSTEMS, systemL10nKey)
        local systemData = spec.systems[systemKey]
        if type(systemData) == "table" and systemData.enabled ~= false then
            table.insert(values, systemL10nKey)
        end
    end

    return values
end

---Returns the second option actually sent, an overhaul only carries one outside the partial type
-- @param table? dialog dialog instance
-- @return string? optionTwo second option value
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

---Tells whether the selected workshop is currently open
-- @param table dialog dialog instance
-- @return boolean isOpen true when the workshop accepts a service now
local function getSelectedWorkshopAvailability(dialog)
    local vehicle = dialog ~= nil and dialog.vehicle or nil
    local spec = vehicle ~= nil and vehicle.spec_RealisticMechanicalSystems or nil
    local workshopType = RMS_WorkshopDialog.INSTANCE ~= nil and RMS_WorkshopDialog.INSTANCE.workshopType or (spec ~= nil and spec.workshopType or nil)

    if RMS_Main ~= nil and RMS_Main.isWorkshopTypeOpen ~= nil then
        return RMS_Main:isWorkshopTypeOpen(workshopType)
    end

    return true
end

---Returns the localized name of the selected procedure, option then service type
-- @param table? dialog dialog instance
-- @return string name procedure name
local function getSelectedProcedureDisplayName(dialog)
    if dialog == nil then
        return ""
    end

    local optionOneText = dialog.selectedOptionOne ~= nil and g_i18n:getText(dialog.selectedOptionOne) or ""
    local typeText = dialog.maintenanceType ~= nil and g_i18n:getText(dialog.maintenanceType) or ""

    if optionOneText == "" then
        return typeText
    end

    if typeText == "" then
        return optionOneText
    end

    return string.format("%s · %s", typeText, optionOneText)
end

---Updates a segmented option row from its values and selected value
-- @param table buttons segment buttons
-- @param table labels localized option labels
-- @param table values option values
-- @param string? selectedValue selected option value
-- @param boolean? disabled true when the complete row is disabled
local function updateSegmentButtons(buttons, labels, values, selectedValue, disabled)
    local visibleCount = math.min(#(buttons or {}), #(values or {}))
    local layout = buttons ~= nil and buttons[1] ~= nil and buttons[1].parent or nil
    if visibleCount > 0 and layout ~= nil and layout.size ~= nil then
        local spacing = layout.elementSpacing or 0
        local segmentWidth = (layout.size[1] - spacing * (visibleCount - 1)) / visibleCount
        for index = 1, visibleCount do
            buttons[index]:setSize(segmentWidth, nil)
        end
    end

    for index, button in ipairs(buttons or {}) do
        local isVisible = values[index] ~= nil
        button:setVisible(isVisible)
        button:setText(labels[index] or "")
        button:setSelected(isVisible and values[index] == selectedValue)
        button:setDisabled(disabled == true)
    end

    if layout ~= nil and layout.invalidateLayout ~= nil then
        layout:invalidateLayout()
    end
end

---Updates the custom yes or no segments from the stored boolean value
-- @param table dialog dialog instance
local function updateBinaryButtons(dialog)
    local buttons = dialog ~= nil and dialog.optionThreeButtons or nil
    if buttons == nil or buttons[1] == nil or buttons[2] == nil then
        return
    end

    buttons[1]:setText(g_i18n:getText(BinaryOptionElement.STRING_NO))
    buttons[1]:setSelected(dialog.selectedOptionThree ~= true)
    buttons[2]:setText(g_i18n:getText(BinaryOptionElement.STRING_YES))
    buttons[2]:setSelected(dialog.selectedOptionThree == true)
end

---Updates the dedicated refill presentation from the requirements used by the transaction
-- @param table dialog dialog instance
-- @param table requirements ordered fluid requirements
-- @param string requirementsLabel context-specific requirements label
local function updateRefillPresentation(dialog, requirements, requirementsLabel)
    local litersByCircuit = RMS_Fluids.getRequiredLitersByCircuit(requirements)
    local hasRequirements = next(litersByCircuit) ~= nil
    local unit = g_i18n:getText("unit_literShort")

    dialog.refillEmptyGroup:setVisible(not hasRequirements)
    dialog.refillRequirementsGroup:setVisible(hasRequirements)
    dialog.refillRequirementsLabel:setText(requirementsLabel)

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
                g_i18n:formatNumber(currentLiters, 1),
                g_i18n:formatNumber(capacity, 1),
                unit
            ))
            dialog[fields.amount]:setText(string.format(
                "+ %s %s",
                g_i18n:formatNumber(requiredLiters, 1),
                unit
            ))
            gauge:setSize(baseWidth * levelRatio, nil)
        end
    end

    if hasRequirements then
        RMS_Utils.fitValuePills(dialog.refillRequirementsGroup)
    end
    dialog.refillRowsLayout:invalidateLayout()
end

---Rebuilds the native scrolling layout after visibility or text changes
-- @param table? dialog dialog instance
local function refreshConfigScroll(dialog)
    local layout = dialog ~= nil and dialog.configScroll or nil
    if layout == nil then
        return
    end

    if layout.invalidateLayout ~= nil then
        layout:invalidateLayout()
    end
    if dialog.resetConfigScroll == true and layout.scrollTo ~= nil then
        layout:scrollTo(0, false)
        dialog.resetConfigScroll = false
    end
    if layout.raiseSliderUpdateEvent ~= nil then
        layout:raiseSliderUpdateEvent()
    end
    if dialog.configSliderBox ~= nil and dialog.configSlider ~= nil then
        dialog.configSliderBox:setVisible(dialog.configSlider.needsSlider == true)
    end
end

---Fills the fluid rows of the recap, one circuit per row with its own glyph
-- @param table dialog dialog instance
-- @param table? requirements ordered fluid requirements
-- @return integer count number of circuits billed
local function updateRecapFluids(dialog, requirements)
    local profiles = {
        engineOil = "rms_workshopRecapFluidIconEngineOil",
        coolant = "rms_workshopRecapFluidIconCoolant",
        transmissionOil = "rms_workshopRecapFluidIconTransmissionOil",
        hydraulicFluid = "rms_workshopRecapFluidIconHydraulicFluid"
    }
    local names = {
        engineOil = "rms_inspection_engine_oil",
        coolant = "rms_inspection_coolant",
        transmissionOil = "rms_inspection_transmission_oil",
        hydraulicFluid = "rms_inspection_hydraulic_fluid"
    }
    local modes = {
        topUp = "rms_fluid_mode_top_up",
        replace = "rms_fluid_mode_replace",
        repair = "rms_fluid_mode_repair"
    }
    local unit = g_i18n:getText("unit_literShort")
    local count = 0

    for _, requirement in ipairs(requirements or {}) do
        local liters = math.max(tonumber(requirement.liters) or 0, 0)
        if liters > RMS_Fluids.EPSILON and count < #dialog.recapFluidRow then
            count = count + 1
            dialog.recapFluidIcon[count]:applyProfile(profiles[requirement.circuit], true)
            dialog.recapFluidName[count]:setText(g_i18n:getText(names[requirement.circuit] or requirement.circuit))
            dialog.recapFluidValue[count]:setText(string.format("%s %s (%s)",
                g_i18n:formatNumber(liters, 1), unit, g_i18n:getText(modes[requirement.mode] or "rms_fluid_mode_top_up")))
        end
    end

    for index, row in ipairs(dialog.recapFluidRow) do
        row:setVisible(index <= count)
    end

    -- the block shrinks to what it bills, so one circuit no longer floats in a four circuit frame
    local height = dialog.recapFluidsLabel.size[2]
        + count * (dialog.recapFluidRow[1].size[2] + dialog.recapFluidsLayout.elementSpacing)
        + 2 * dialog.recapFluidsPadding
    dialog.recapFluidsBlock:setVisible(count > 0)
    dialog.recapFluidsBlock:setSize(nil, height)
    dialog.recapFluidsSurface:setSize(nil, height)
    dialog.recapFluidsLayout:setSize(nil, height)
    dialog.recapFluidsLayout:invalidateLayout()

    return count
end


---Opens the dialog on a vehicle for a maintenance, repair, overhaul or refill
-- @param table vehicle vehicle
-- @param string maintenanceType service status constant
function RMS_MaintenanceThreeOptionsDialog.show(vehicle, maintenanceType)
    if RMS_MaintenanceThreeOptionsDialog.INSTANCE == nil then RMS_MaintenanceThreeOptionsDialog.register() end
    if vehicle == nil or vehicle.spec_RealisticMechanicalSystems == nil or maintenanceType == nil then return end
    
    local dialog = RMS_MaintenanceThreeOptionsDialog.INSTANCE
    dialog.vehicle = vehicle
    dialog.maintenanceType = maintenanceType
    dialog.resetConfigScroll = true
    dialog.optionThree.useYesNoTexts = true
    if dialog.optionThree.setIsChecked ~= nil then
        dialog.optionThree:setIsChecked(false, false, false)
    else
        dialog.optionThree:setState(BinaryOptionElement.STATE_LEFT)
    end

    if dialog.maintenanceType == RealisticMechanicalSystems.STATUS.MAINTENANCE then
        dialog.selectedOptionOne = RealisticMechanicalSystems.MAINTENANCE_TYPES.STANDARD
    elseif dialog.maintenanceType == RealisticMechanicalSystems.STATUS.REPAIR then
        dialog.selectedOptionOne = RealisticMechanicalSystems.REPAIR_TYPES.MEDIUM
    elseif dialog.maintenanceType == RealisticMechanicalSystems.STATUS.OVERHAUL then
        dialog.selectedOptionOne = RealisticMechanicalSystems.OVERHAUL_TYPES.STANDARD
    else
        dialog.selectedOptionOne = nil
    end
    dialog.overhaulSystemValues = getEnabledOverhaulSystemValues(vehicle)
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

---Rebuilds the visible work order, recap values and contextual descriptions
function RMS_MaintenanceThreeOptionsDialog:updateScreen()
    if self.vehicle == nil then return end

    local spec = self.vehicle.spec_RealisticMechanicalSystems
    local workshopType = RMS_WorkshopDialog.INSTANCE ~= nil and RMS_WorkshopDialog.INSTANCE.workshopType or spec.workshopType
    local isRefill = self.maintenanceType == RealisticMechanicalSystems.STATUS.REFILL

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
    local repairChoiceButton = self.configChoiceButtons ~= nil and self.configChoiceButtons[3] or nil
    if repairChoiceButton ~= nil then
        repairChoiceButton:setDisabled(not RMS_Utils.hasSelectedVisibleBreakdown(self.vehicle))
    end

    -- title
    self.recapType:setText(g_i18n:getText(isRefill and "rms_fluid_refill_work_order" or self.maintenanceType))

    -- option one
    local optionOneText = ""
    local optionOneOptions = {}
    local optionOneValues = {}
    local choosenPartsForQuickFix = {}
    local choosenPartsForRepair = {}

    if self.maintenanceType == RealisticMechanicalSystems.STATUS.MAINTENANCE then
        optionOneText = g_i18n:getText("rms_option_menu_option_one_title_maintenance")
        optionOneValues = {
            RealisticMechanicalSystems.MAINTENANCE_TYPES.MINIMAL,
            RealisticMechanicalSystems.MAINTENANCE_TYPES.STANDARD,
            RealisticMechanicalSystems.MAINTENANCE_TYPES.EXTENDED,
            RealisticMechanicalSystems.MAINTENANCE_TYPES.PREVENTIVE
        }
    elseif self.maintenanceType == RealisticMechanicalSystems.STATUS.REPAIR then
        optionOneText = g_i18n:getText("rms_option_menu_option_one_title_repair")

        -- an active breakdown can be quick fixed, an inactive one can only be replaced
        local isHaveBreakdownToBeQuickFixed = false
        local isHaveBreakdownToBeReplaced = false
        local activeBreakdowns = self.vehicle:getActiveBreakdowns()
        local breakdownRegistry = RMS_Breakdowns.BreakdownRegistry
        for breakdownId, breakdownData in pairs(activeBreakdowns) do
            if breakdownData.isSelectedForRepair and breakdownData.isVisible then
                if breakdownData.isActive then
                    isHaveBreakdownToBeQuickFixed = true
                    isHaveBreakdownToBeReplaced = true
                    table.insert(choosenPartsForQuickFix, breakdownRegistry[breakdownId].part)
                    table.insert(choosenPartsForRepair, breakdownRegistry[breakdownId].part)
                else 
                    isHaveBreakdownToBeReplaced = true
                    table.insert(choosenPartsForRepair, breakdownRegistry[breakdownId].part)
                end
            end
        end

        if isHaveBreakdownToBeQuickFixed then
            table.insert(optionOneValues, RealisticMechanicalSystems.REPAIR_TYPES.LOW)
        end
        if isHaveBreakdownToBeReplaced then
            table.insert(optionOneValues, RealisticMechanicalSystems.REPAIR_TYPES.MEDIUM)
            table.insert(optionOneValues, RealisticMechanicalSystems.REPAIR_TYPES.HIGH)
        end

    elseif self.maintenanceType == RealisticMechanicalSystems.STATUS.OVERHAUL then
        optionOneText = g_i18n:getText("rms_option_menu_option_one_title_overhaul")
        optionOneValues = {
            RealisticMechanicalSystems.OVERHAUL_TYPES.PARTIAL,
            RealisticMechanicalSystems.OVERHAUL_TYPES.STANDARD,
            RealisticMechanicalSystems.OVERHAUL_TYPES.FULL
        }
    end

    for _, optionValue in ipairs(optionOneValues) do
        table.insert(optionOneOptions, g_i18n:getText(optionValue))
    end

    self.optionOneValues = optionOneValues
    if self.optionOneValues[1] == nil then
        self.selectedOptionOne = nil
    elseif RMS_Utils.getKeyByValue(self.optionOneValues, self.selectedOptionOne) == nil then
        self.selectedOptionOne = self.optionOneValues[1]
    end

    self.optionOneText:setText(optionOneText)
    self.optionOne:setTexts(optionOneOptions)
    local selectedOptionOneIndex = RMS_Utils.getKeyByValue(self.optionOneValues, self.selectedOptionOne)
    if selectedOptionOneIndex ~= nil and self.optionOne.setState ~= nil then
        self.optionOne:setState(selectedOptionOneIndex)
    end

    -- option two
    local optionTwoText = ""
    local optionTwoOptions = {}
    local optionTwoValues = {}

    if self.maintenanceType == RealisticMechanicalSystems.STATUS.MAINTENANCE then
        optionTwoText = g_i18n:getText("rms_option_menu_option_two_title_maintenance")
        optionTwoValues = RealisticMechanicalSystems.PART_TYPES_ORDER
    elseif self.maintenanceType == RealisticMechanicalSystems.STATUS.REPAIR then
        optionTwoText = g_i18n:getText("rms_option_menu_option_two_title_repair")
        optionTwoValues = RealisticMechanicalSystems.PART_TYPES_ORDER
    elseif self.maintenanceType == RealisticMechanicalSystems.STATUS.OVERHAUL then
        optionTwoText = g_i18n:getText("rms_option_menu_option_two_title_overhaul")
        self.overhaulSystemValues = self.overhaulSystemValues or getEnabledOverhaulSystemValues(self.vehicle)
        optionTwoValues = self.overhaulSystemValues
    end

    local maintenanceConsumableTextKeys = {
        [RealisticMechanicalSystems.PART_TYPES.USED] = "rms_spec_consumable_types_used",
        [RealisticMechanicalSystems.PART_TYPES.AFTERMARKET] = "rms_spec_consumable_types_aftermarket",
        [RealisticMechanicalSystems.PART_TYPES.OEM] = "rms_spec_consumable_types_oem",
        [RealisticMechanicalSystems.PART_TYPES.PREMIUM] = "rms_spec_consumable_types_premium"
    }
    for _, optionValue in ipairs(optionTwoValues) do
        local textKey = self.maintenanceType == RealisticMechanicalSystems.STATUS.MAINTENANCE
            and maintenanceConsumableTextKeys[optionValue]
            or optionValue
        table.insert(optionTwoOptions, g_i18n:getText(textKey))
    end

    self.optionTwoValues = optionTwoValues
    self.optionTwoText:setText(optionTwoText)
    self.optionTwo:setTexts(optionTwoOptions)
    if self.optionTwoValues[1] == nil then
        self.selectedOptionTwo = nil
    elseif RMS_Utils.getKeyByValue(self.optionTwoValues, self.selectedOptionTwo) == nil then
        self.selectedOptionTwo = self.optionTwoValues[1]
    end
    local selectedOptionTwoIndex = RMS_Utils.getKeyByValue(self.optionTwoValues, self.selectedOptionTwo)
    if selectedOptionTwoIndex ~= nil and self.optionTwo.setState ~= nil then
        self.optionTwo:setState(selectedOptionTwoIndex)
    end

    local disableOptionTwo = false
    if self.maintenanceType == RealisticMechanicalSystems.STATUS.REPAIR then
        disableOptionTwo = self.selectedOptionOne == RealisticMechanicalSystems.REPAIR_TYPES.LOW
    elseif self.maintenanceType == RealisticMechanicalSystems.STATUS.OVERHAUL then
        disableOptionTwo = self.selectedOptionOne ~= RealisticMechanicalSystems.OVERHAUL_TYPES.PARTIAL
    end
    self.optionTwo:setDisabled(disableOptionTwo)
    updateSegmentButtons(self.optionOneButtons, optionOneOptions, optionOneValues, self.selectedOptionOne, false)

    local requiresOverhaulSystem = self.maintenanceType == RealisticMechanicalSystems.STATUS.OVERHAUL
        and self.selectedOptionOne == RealisticMechanicalSystems.OVERHAUL_TYPES.PARTIAL
    local showOptionTwo = not isRefill
        and (self.maintenanceType ~= RealisticMechanicalSystems.STATUS.OVERHAUL or requiresOverhaulSystem)
    local useNativeOptionTwo = requiresOverhaulSystem
    self.optionTwo:setVisible(useNativeOptionTwo)
    updateSegmentButtons(
        self.optionTwoButtons,
        optionTwoOptions,
        optionTwoValues,
        self.selectedOptionTwo,
        disableOptionTwo or useNativeOptionTwo
    )
    if useNativeOptionTwo then
        for _, button in ipairs(self.optionTwoButtons or {}) do
            button:setVisible(false)
        end
    end

    self.optionOneText:setVisible(not isRefill)
    self.optionOneSegmentRow:setVisible(not isRefill)
    self.optionOneDisclaimer:setVisible(not isRefill)
    self.optionTwoText:setVisible(showOptionTwo)
    self.optionTwoChooser:setVisible(showOptionTwo)
    self.optionTwoDisclaimer:setVisible(showOptionTwo and self.maintenanceType ~= RealisticMechanicalSystems.STATUS.OVERHAUL)
    self.optionThreeGroup:setVisible(not isRefill)
    self.optionThreeDisclaimer:setVisible(not isRefill)
    self.refillGroup:setVisible(isRefill)

    local isAllowedInMobileWorkshop = RMS_FluidWorkshop.getMobileWorkshopAvailability(
        self.vehicle,
        self.maintenanceType,
        workshopType,
        self.selectedOptionOne
    )
    local isWorkshopOpen = getSelectedWorkshopAvailability(self)

    -- price, duration, finishtime
    local isWarrantyRepair = self.maintenanceType == RealisticMechanicalSystems.STATUS.REPAIR
        and self.vehicle:isWarrantyRepairCovered(self.selectedOptionOne, self.selectedOptionTwo)
    local effectiveOptionTwo = getEffectiveOptionTwo(self)
    local servicePrice = RMS_FluidWorkshop.getTransactionPrice(self.vehicle, self.maintenanceType, workshopType, self.selectedOptionOne, effectiveOptionTwo, self.selectedOptionThree)
    local priceValue = ""

    if servicePrice == nil then
        priceValue = g_i18n:getText("rms_fluid_service_price_unavailable")
    elseif isWarrantyRepair and servicePrice <= RMS_Fluids.EPSILON then
        priceValue = g_i18n:getText("rms_option_menu_warranty_repair_text")
    else
        priceValue = g_i18n:formatMoney(servicePrice, 0, true, false)
    end
    local durationValue = RMS_Utils.formatDuration(self.vehicle:getServiceDuration(self.maintenanceType, self.selectedOptionOne, effectiveOptionTwo, self.selectedOptionThree, workshopType))
    local finishTime, daysToAdd = self.vehicle:getServiceFinishTime(self.maintenanceType, self.selectedOptionOne, effectiveOptionTwo, self.selectedOptionThree, workshopType)
    local finishTimeValue = RMS_Utils.formatFinishTime(finishTime, daysToAdd)

    self.recapPriceLabel:setText(stripTrailingColon(g_i18n:getText("rms_option_menu_price_text")))
    self.recapPrice:setText(priceValue)
    self.recapDurationLabel:setText(stripTrailingColon(g_i18n:getText("rms_option_menu_duration_text")))
    self.recapDuration:setText(durationValue)
    self.recapFinishLabel:setText(stripTrailingColon(g_i18n:getText("rms_option_menu_finish_time_text")))
    self.recapFinish:setText(finishTimeValue)
    self.recapVehicle:setText(self.vehicle.getFullName ~= nil and self.vehicle:getFullName() or g_i18n:getText("ui_vehicle"))

    local requirements = RMS_FluidWorkshop.getTransactionRequirements(
        self.vehicle,
        self.maintenanceType,
        self.selectedOptionOne,
        effectiveOptionTwo
    )
    local requirementsText = RMS_FluidWorkshop.formatTransactionRequirements(requirements)
    local hasFluids = #requirements > 0
    local requirementsLabel = stripTrailingColon(g_i18n:getText(RMS_FluidWorkshop.getRequirementsTextKey(workshopType)))
    local refillRequirementsLabel = g_i18n:getText(workshopType == RealisticMechanicalSystems.WORKSHOP.DEALER
        and "rms_fluid_refill_dealer_supply" or "rms_fluid_refill_stock_supply")
    -- the recap stands on its own: the fluids are billed there too, even for a plain top up
    local showFluidsInRecap = hasFluids

    -- the block sizes itself to the billed circuits and disappears when there are none
    self.recapFluidsLabel:setText(showFluidsInRecap and requirementsLabel or "")
    updateRecapFluids(self, showFluidsInRecap and requirements or nil)

    if isRefill then
        updateRefillPresentation(self, requirements, refillRequirementsLabel)
    end

    -- disclaimers
    if self.maintenanceType == RealisticMechanicalSystems.STATUS.MAINTENANCE then
        local optionOneDisclaimers = {
            [RealisticMechanicalSystems.MAINTENANCE_TYPES.STANDARD]   = g_i18n:getText("rms_option_menu_maintenance_standard_description"),
            [RealisticMechanicalSystems.MAINTENANCE_TYPES.MINIMAL]    = g_i18n:getText("rms_option_menu_maintenance_minimal_description"),
            [RealisticMechanicalSystems.MAINTENANCE_TYPES.EXTENDED]   = g_i18n:getText("rms_option_menu_maintenance_extended_description"),
            [RealisticMechanicalSystems.MAINTENANCE_TYPES.PREVENTIVE] = g_i18n:getText("rms_option_menu_maintenance_preventive_description")
        }
        self.optionOneDisclaimer:setText(stripLeadingMarker(optionOneDisclaimers[self.selectedOptionOne]))
        self.choosenPartsHeader:setVisible(false)
        self.choosenPartsText:setVisible(false)
    elseif self.maintenanceType == RealisticMechanicalSystems.STATUS.REPAIR then
        local choosenPartsLabels = {}
        if self.selectedOptionOne == nil then
            self.optionOneDisclaimer:setText("")
        elseif self.selectedOptionOne == RealisticMechanicalSystems.REPAIR_TYPES.LOW then
            for _, part in ipairs(choosenPartsForQuickFix) do
                table.insert(choosenPartsLabels, g_i18n:getText(part))
            end
            self.optionOneDisclaimer:setText(stripLeadingMarker(g_i18n:getText("rms_option_menu_repair_type_fix_description")))
        else
            for _, part in ipairs(choosenPartsForRepair) do
                table.insert(choosenPartsLabels, g_i18n:getText(part))
            end
            if self.selectedOptionOne == RealisticMechanicalSystems.REPAIR_TYPES.MEDIUM then
                self.optionOneDisclaimer:setText(stripLeadingMarker(g_i18n:getText("rms_option_menu_repair_type_replacement_description")))
            else
                self.optionOneDisclaimer:setText(stripLeadingMarker(g_i18n:getText("rms_option_menu_repair_type_advanced_description")))
            end
        end
        self.choosenPartsText:setText(#choosenPartsLabels > 0 and table.concat(choosenPartsLabels, " · ") or "-")
        self.choosenPartsHeader:setVisible(true)
        self.choosenPartsText:setVisible(true)
    elseif self.maintenanceType == RealisticMechanicalSystems.STATUS.OVERHAUL then
        local optionOneDisclaimers = {
            [RealisticMechanicalSystems.OVERHAUL_TYPES.STANDARD] = g_i18n:getText("rms_option_menu_overhaul_standard_description"),
            [RealisticMechanicalSystems.OVERHAUL_TYPES.PARTIAL]  = g_i18n:getText("rms_option_menu_overhaul_partial_description"),
            [RealisticMechanicalSystems.OVERHAUL_TYPES.FULL]     = g_i18n:getText("rms_option_menu_overhaul_full_description")
        }
        self.optionOneDisclaimer:setText(stripLeadingMarker(optionOneDisclaimers[self.selectedOptionOne]))
        self.choosenPartsHeader:setVisible(false)
        self.choosenPartsText:setVisible(false)
    else
        self.optionOneDisclaimer:setText("")
        self.choosenPartsHeader:setVisible(false)
        self.choosenPartsText:setVisible(false)
    end

    if self.maintenanceType == RealisticMechanicalSystems.STATUS.MAINTENANCE then
        local optionTwoDisclaimers = {
            [RealisticMechanicalSystems.PART_TYPES.OEM]         = g_i18n:getText("rms_option_menu_consumable_oem_description"),
            [RealisticMechanicalSystems.PART_TYPES.USED]        = g_i18n:getText("rms_option_menu_consumable_used_description"),
            [RealisticMechanicalSystems.PART_TYPES.AFTERMARKET] = g_i18n:getText("rms_option_menu_consumable_aftermarket_description"),
            [RealisticMechanicalSystems.PART_TYPES.PREMIUM]     = g_i18n:getText("rms_option_menu_consumable_premium_description")
        }
        self.optionTwoDisclaimer:setText(stripLeadingMarker(optionTwoDisclaimers[self.selectedOptionTwo]))
    elseif self.maintenanceType == RealisticMechanicalSystems.STATUS.OVERHAUL then
        self.optionTwoDisclaimer:setText("")
    elseif self.maintenanceType == RealisticMechanicalSystems.STATUS.REPAIR then
        local optionTwoDisclaimers = {
            [RealisticMechanicalSystems.PART_TYPES.OEM]         = g_i18n:getText("rms_option_menu_part_oem_description"),
            [RealisticMechanicalSystems.PART_TYPES.USED]        = g_i18n:getText("rms_option_menu_part_used_description"),
            [RealisticMechanicalSystems.PART_TYPES.AFTERMARKET] = g_i18n:getText("rms_option_menu_part_aftermarket_description"),
            [RealisticMechanicalSystems.PART_TYPES.PREMIUM]     = g_i18n:getText("rms_option_menu_part_premium_description")
        }
        self.optionTwoDisclaimer:setText(stripLeadingMarker(optionTwoDisclaimers[self.selectedOptionTwo]))
    else
        self.optionTwoDisclaimer:setText("")
    end

    if not isAllowedInMobileWorkshop then
        local procedureName = getSelectedProcedureDisplayName(self)
        local vehicleName = self.vehicle.getFullName ~= nil and self.vehicle:getFullName() or g_i18n:getText("ui_vehicle")
        self.optionOneDisclaimer:setText(string.format(g_i18n:getText("rms_mobile_workshop_low_maintainability"), procedureName, vehicleName))
        self.optionOneDisclaimer:setTextColor(unpack(RMS_Utils.COLOR.ALERT))
        self.optionTwoDisclaimer:setVisible(false)
    else
        self.optionOneDisclaimer:applyProfile("rms_workshopConfigDescription", true)
        self.optionTwoDisclaimer:setVisible(showOptionTwo and self.maintenanceType ~= RealisticMechanicalSystems.STATUS.OVERHAUL)
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
    elseif self.maintenanceType == RealisticMechanicalSystems.STATUS.OVERHAUL then
        optionThreeText = g_i18n:getText("rms_option_menu_perform_renew_paint")
        optionThreeDisclaimerText = g_i18n:getText("rms_option_menu_option_three_disclaimer_overhaul_repaint")
    end

    if self.selectedOptionThree and not isRefill and self.maintenanceType ~= RealisticMechanicalSystems.STATUS.OVERHAUL then
        optionThreeDisclaimerText = optionThreeDisclaimerText .. " " .. g_i18n:getText("rms_option_menu_follow_up_separate_transaction")
    end
    self.optionThreeText:setText(optionThreeText)
    self.optionThreeDisclaimer:setText(stripLeadingMarker(optionThreeDisclaimerText))
    -- a top up carries no third option: the card stays and says so, rather than leave a gap
    if isRefill then
        self.recapAddonLabel:setText(g_i18n:getText("rms_ws_label_addon"))
        self.recapAddon:setText(g_i18n:getText("rms_option_none"))
    else
        self.recapAddonLabel:setText(optionThreeText)
        self.recapAddon:setText(g_i18n:getText(self.selectedOptionThree and BinaryOptionElement.STRING_YES or BinaryOptionElement.STRING_NO))
    end
    updateBinaryButtons(self)

    if self.startServiceButton ~= nil then
        local hasValidSelection = isRefill and hasFluids or self.selectedOptionOne ~= nil
        self.startServiceButton:setDisabled(not hasValidSelection or not isAllowedInMobileWorkshop or not isWorkshopOpen)
    end

    -- the recap names the two settings, the parts themselves are listed in the work order
    local optionTexts = {}
    if self.selectedOptionOne ~= nil then
        table.insert(optionTexts, g_i18n:getText(self.selectedOptionOne))
    end
    if self.maintenanceType == RealisticMechanicalSystems.STATUS.MAINTENANCE then
        local consumableTextKey = maintenanceConsumableTextKeys[self.selectedOptionTwo]
        if consumableTextKey ~= nil then
            table.insert(optionTexts, g_i18n:getText(consumableTextKey))
        end
    elseif effectiveOptionTwo ~= nil and effectiveOptionTwo ~= "NONE" then
        table.insert(optionTexts, g_i18n:getText(effectiveOptionTwo))
    end

    local workshopTypeKey = RMS_Utils.getKeyByValue(RealisticMechanicalSystems.WORKSHOP, workshopType)
    local workshopTypeText = workshopTypeKey ~= nil and g_i18n:getText(workshopType) or ""
    local availabilityText = g_i18n:getText(isWorkshopOpen and "rms_ws_status_open" or "rms_ws_status_closed")
    if workshopTypeText ~= "" then
        availabilityText = availabilityText .. " · " .. workshopTypeText
    end

    if isRefill then
        self.recapOptions:setText(refillRequirementsLabel)
    else
        self.recapOptions:setText(#optionTexts > 0 and table.concat(optionTexts, " · ") or "-")
    end
    self.configStatusText:setText(availabilityText)
    refreshConfigScroll(self)

end

---Selects a fixed option-one segment
-- @param integer index option index
function RMS_MaintenanceThreeOptionsDialog:selectOptionOnePreset(index)
    if self.optionOne ~= nil then
        self.optionOne:setState(index)
    end
    self:onClickOptionOne(index)
end

function RMS_MaintenanceThreeOptionsDialog:onClickOptionOnePreset1()
    self:selectOptionOnePreset(1)
end

function RMS_MaintenanceThreeOptionsDialog:onClickOptionOnePreset2()
    self:selectOptionOnePreset(2)
end

function RMS_MaintenanceThreeOptionsDialog:onClickOptionOnePreset3()
    self:selectOptionOnePreset(3)
end

function RMS_MaintenanceThreeOptionsDialog:onClickOptionOnePreset4()
    self:selectOptionOnePreset(4)
end

---Selects a fixed option-two segment
-- @param integer index option index
function RMS_MaintenanceThreeOptionsDialog:selectOptionTwoPreset(index)
    if self.optionTwo ~= nil then
        self.optionTwo:setState(index)
    end
    self:onClickOptionTwo(index)
end

function RMS_MaintenanceThreeOptionsDialog:onClickOptionTwoPreset1()
    self:selectOptionTwoPreset(1)
end

function RMS_MaintenanceThreeOptionsDialog:onClickOptionTwoPreset2()
    self:selectOptionTwoPreset(2)
end

function RMS_MaintenanceThreeOptionsDialog:onClickOptionTwoPreset3()
    self:selectOptionTwoPreset(3)
end

function RMS_MaintenanceThreeOptionsDialog:onClickOptionTwoPreset4()
    self:selectOptionTwoPreset(4)
end

---Reopens the relevant configuration dialog for another intervention type
-- @param string maintenanceType target service type
-- @param boolean usesTwoOptions true for the inspection dialog
function RMS_MaintenanceThreeOptionsDialog:openInterventionConfiguration(maintenanceType, usesTwoOptions)
    local vehicle = self.vehicle
    if vehicle == nil then
        return
    end

    self:close()
    if usesTwoOptions then
        RMS_MaintenanceTwoOptionsDialog.show(vehicle, maintenanceType)
    else
        RMS_MaintenanceThreeOptionsDialog.show(vehicle, maintenanceType)
    end
end

function RMS_MaintenanceThreeOptionsDialog:onClickConfigureInspection()
    self:openInterventionConfiguration(RealisticMechanicalSystems.STATUS.INSPECTION, true)
end

function RMS_MaintenanceThreeOptionsDialog:onClickConfigureMaintenance()
    self:openInterventionConfiguration(RealisticMechanicalSystems.STATUS.MAINTENANCE, false)
end

function RMS_MaintenanceThreeOptionsDialog:onClickConfigureRepair()
    if not RMS_Utils.hasSelectedVisibleBreakdown(self.vehicle) then
        return
    end

    self:openInterventionConfiguration(RealisticMechanicalSystems.STATUS.REPAIR, false)
end

function RMS_MaintenanceThreeOptionsDialog:onClickConfigureOverhaul()
    self:openInterventionConfiguration(RealisticMechanicalSystems.STATUS.OVERHAUL, false)
end

function RMS_MaintenanceThreeOptionsDialog:onClickConfigureRefill()
    self:openInterventionConfiguration(RealisticMechanicalSystems.STATUS.REFILL, false)
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

---Toggles the yes or no option and refreshes the screen
-- @param integer state binary option state
-- @param table binaryOptionElement binary option element
function RMS_MaintenanceThreeOptionsDialog:onClickOptionThree(state, binaryOptionElement)
    self.selectedOptionThree = (state == BinaryOptionElement.STATE_RIGHT)
    self:updateScreen()
end

function RMS_MaintenanceThreeOptionsDialog:onClickOptionThreeNo()
    if self.optionThree ~= nil and self.optionThree.setIsChecked ~= nil then
        self.optionThree:setIsChecked(false, false, false)
    end
    self.selectedOptionThree = false
    self:updateScreen()
end

function RMS_MaintenanceThreeOptionsDialog:onClickOptionThreeYes()
    if self.optionThree ~= nil and self.optionThree.setIsChecked ~= nil then
        self.optionThree:setIsChecked(true, false, false)
    end
    self.selectedOptionThree = true
    self:updateScreen()
end

---Starts the service directly on the server, sends a request from a client, after a money check
function RMS_MaintenanceThreeOptionsDialog:onClickStartService()
    local vehicle = self.vehicle
    local workshopType = RMS_WorkshopDialog.INSTANCE.workshopType
    if not RMS_FluidWorkshop.getMobileWorkshopAvailability(
        vehicle,
        self.maintenanceType,
        workshopType,
        self.selectedOptionOne
    ) or not getSelectedWorkshopAvailability(self) then
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



---Selects the interventions tab in the configuration shell and binds the button backgrounds
function RMS_MaintenanceThreeOptionsDialog:onCreate()
    -- the fluid block follows the circuits actually billed; its XML height gives the design margin
    self.recapFluidsPadding = (self.recapFluidsBlock.size[2]
        - self.recapFluidsLabel.size[2]
        - #self.recapFluidRow * (self.recapFluidRow[1].size[2] + self.recapFluidsLayout.elementSpacing)) * 0.5

    self.refillGaugeWidths = self.refillGaugeWidths or {}
    for _, fields in ipairs(REFILL_ROW_FIELDS) do
        local gauge = self[fields.gauge]
        if gauge ~= nil then
            self.refillGaugeWidths[fields.gauge] = gauge.size[1]
        end
    end

    RMS_Utils.mirrorSelectionToChildren(self.configurationTab)
    self.configurationTab:setSelected(true)

    for _, button in ipairs(self.configChoiceButtons or {}) do
        RMS_Utils.mirrorSelectionToChildren(button)
    end

    for _, button in ipairs(self.optionOneButtons or {}) do
        RMS_Utils.mirrorSelectionToChildren(button)
    end

    for _, button in ipairs(self.optionTwoButtons or {}) do
        RMS_Utils.mirrorSelectionToChildren(button)
    end

    for _, button in ipairs(self.optionThreeButtons or {}) do
        RMS_Utils.mirrorSelectionToChildren(button)
    end
end

---
function RMS_MaintenanceThreeOptionsDialog:onOpen()
    RMS_MaintenanceThreeOptionsDialog:superClass().onOpen(self)

    if self.optionThree ~= nil then
        self.optionThree.useYesNoTexts = true
        if self.optionThree.setIsChecked ~= nil then
            self.optionThree:setIsChecked(self.selectedOptionThree == true, false, false)
        elseif self.optionThree.getState ~= nil then
            self.optionThree:setState(self.optionThree:getState())
        end
    end

    refreshConfigScroll(self)

    for _, button in ipairs(self.configChoiceButtons or {}) do
        RMS_Utils.centerActionContent(button)
    end

    g_messageCenter:subscribe(MessageType.MONEY_CHANGED, self.updateScreen, self)
end

---
function RMS_MaintenanceThreeOptionsDialog:onClose()
    self.vehicle = nil
    g_messageCenter:unsubscribeAll(self)

    RMS_MaintenanceThreeOptionsDialog:superClass().onClose(self)
end
