-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---Service dialog for inspection and overhaul, with a type option and a yes or no option
RMS_MaintenanceTwoOptionsDialog = {}
RMS_MaintenanceTwoOptionsDialog.INSTANCE = nil

local RMS_MaintenanceTwoOptionsDialog_mt = Class(RMS_MaintenanceTwoOptionsDialog, MessageDialog)
local modDirectory = g_currentModDirectory

---Loads the dialog layout and stores the shared instance
function RMS_MaintenanceTwoOptionsDialog.register()
    local dialog = RMS_MaintenanceTwoOptionsDialog.new()
    g_gui:loadGui(modDirectory .. "gui/RMS_MaintenanceTwoOptionsDialog.xml", "RMS_MaintenanceTwoOptionsDialog", dialog)
    RMS_MaintenanceTwoOptionsDialog.INSTANCE = dialog
end

---Create instance of RMS_MaintenanceTwoOptionsDialog
-- @param table? target target
-- @param table? customMt custom metatable
-- @return table dialog instance of class RMS_MaintenanceTwoOptionsDialog
function RMS_MaintenanceTwoOptionsDialog.new(target, customMt)
    local dialog = MessageDialog.new(target, customMt or RMS_MaintenanceTwoOptionsDialog_mt)
    dialog.vehicle = nil
    dialog.optionOneValues = nil
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

---Updates the segmented option row from its values and selected value
-- @param table buttons segment buttons
-- @param table labels localized labels
-- @param table values option values
-- @param string? selectedValue selected option value
local function updateSegmentButtons(buttons, labels, values, selectedValue)
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


---Opens the dialog on a vehicle for an inspection or an overhaul
-- @param table vehicle vehicle
-- @param string maintenanceType service status constant
function RMS_MaintenanceTwoOptionsDialog.show(vehicle, maintenanceType)
    if RMS_MaintenanceTwoOptionsDialog.INSTANCE == nil then RMS_MaintenanceTwoOptionsDialog.register() end
    if vehicle == nil or vehicle.spec_RealisticMechanicalSystems == nil or maintenanceType == nil then return end
    
    local dialog = RMS_MaintenanceTwoOptionsDialog.INSTANCE
    dialog.vehicle = vehicle
    dialog.maintenanceType = maintenanceType
    dialog.resetConfigScroll = true

    dialog.optionThree.useYesNoTexts = true
    if dialog.optionThree.setIsChecked ~= nil then
        dialog.optionThree:setIsChecked(false, false, false)
    else
        dialog.optionThree:setState(BinaryOptionElement.STATE_LEFT)
    end

    if dialog.maintenanceType == RealisticMechanicalSystems.STATUS.INSPECTION then
        dialog.selectedOptionOne = RealisticMechanicalSystems.INSPECTION_TYPES.STANDARD
    elseif dialog.maintenanceType == RealisticMechanicalSystems.STATUS.OVERHAUL then
        dialog.selectedOptionOne = RealisticMechanicalSystems.OVERHAUL_TYPES.STANDARD
    end
    dialog.selectedOptionThree = false
    
    dialog:updateScreen()
    g_gui:showDialog("RMS_MaintenanceTwoOptionsDialog")
end

---Rebuilds the options, the price, duration and finish time rows, and the disclaimers
function RMS_MaintenanceTwoOptionsDialog:updateScreen()
    if self.vehicle == nil then return end

    local spec = self.vehicle.spec_RealisticMechanicalSystems
    local workshopType = RMS_WorkshopDialog.INSTANCE ~= nil and RMS_WorkshopDialog.INSTANCE.workshopType or spec.workshopType

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
    local selectedChoiceIndex = self.maintenanceType == RealisticMechanicalSystems.STATUS.INSPECTION and 1 or 4
    for index, button in ipairs(self.configChoiceButtons or {}) do
        button:setSelected(index == selectedChoiceIndex)
    end
    local repairChoiceButton = self.configChoiceButtons ~= nil and self.configChoiceButtons[3] or nil
    if repairChoiceButton ~= nil then
        repairChoiceButton:setDisabled(not RMS_Utils.hasSelectedVisibleBreakdown(self.vehicle))
    end

    -- title
    self.recapType:setText(g_i18n:getText(self.maintenanceType))

    -- option one
    local optionOneText = ""
    local optionOneOptions = {}

    if self.maintenanceType == RealisticMechanicalSystems.STATUS.INSPECTION then
        optionOneText = g_i18n:getText("rms_option_menu_option_one_title_inspection")
        local instantInspection = RMS_Config.MAINTENANCE.INSTANT_INSPECTION
        if instantInspection then
            self.optionOneValues = {
                RealisticMechanicalSystems.INSPECTION_TYPES.STANDARD,
                RealisticMechanicalSystems.INSPECTION_TYPES.COMPLETE
            }
            if self.selectedOptionOne == RealisticMechanicalSystems.INSPECTION_TYPES.VISUAL then
                self.selectedOptionOne = RealisticMechanicalSystems.INSPECTION_TYPES.STANDARD
            end
        else
            self.optionOneValues = {
                RealisticMechanicalSystems.INSPECTION_TYPES.VISUAL,
                RealisticMechanicalSystems.INSPECTION_TYPES.STANDARD,
                RealisticMechanicalSystems.INSPECTION_TYPES.COMPLETE
            }
        end
    else
        optionOneText = g_i18n:getText("rms_option_menu_option_one_title_overhaul")
        self.optionOneValues = {
            RealisticMechanicalSystems.OVERHAUL_TYPES.PARTIAL,
            RealisticMechanicalSystems.OVERHAUL_TYPES.STANDARD,
            RealisticMechanicalSystems.OVERHAUL_TYPES.FULL
        }
    end

    for _, optionValue in ipairs(self.optionOneValues) do
        table.insert(optionOneOptions, g_i18n:getText(optionValue))
    end

    self.optionOneText:setText(optionOneText)
    self.optionOne:setTexts(optionOneOptions)

    local selectedOptionIndex = RMS_Utils.getKeyByValue(self.optionOneValues, self.selectedOptionOne)
    if selectedOptionIndex ~= nil and self.optionOne.setState ~= nil then
        self.optionOne:setState(selectedOptionIndex)
    end
    updateSegmentButtons(self.optionOneButtons, optionOneOptions, self.optionOneValues, self.selectedOptionOne)

    local isAllowedInMobileWorkshop = RMS_FluidWorkshop.getMobileWorkshopAvailability(
        self.vehicle,
        self.maintenanceType,
        workshopType,
        self.selectedOptionOne
    )
    local isWorkshopOpen = getSelectedWorkshopAvailability(self)

    -- price, duration, finishtime
    local servicePrice = RMS_FluidWorkshop.getTransactionPrice(self.vehicle, self.maintenanceType, workshopType, self.selectedOptionOne, self.selectedOptionTwo, self.selectedOptionThree)
    local priceValue = servicePrice ~= nil
        and g_i18n:formatMoney(servicePrice, 0, true, false)
        or g_i18n:getText("rms_fluid_service_price_unavailable")
    local durationValue = ""
    if RMS_Config.MAINTENANCE.INSTANT_INSPECTION and  self.maintenanceType == RealisticMechanicalSystems.STATUS.INSPECTION then
        durationValue = g_i18n:getText("rms_option_menu_duration_instant")
    else
        durationValue = RMS_Utils.formatDuration(self.vehicle:getServiceDuration(self.maintenanceType, self.selectedOptionOne, self.selectedOptionTwo, self.selectedOptionThree, workshopType))
    end
    local finishTime, daysToAdd = self.vehicle:getServiceFinishTime(self.maintenanceType, self.selectedOptionOne, self.selectedOptionTwo, self.selectedOptionThree, workshopType)
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
        self.selectedOptionTwo
    )
    local requirementsText = RMS_FluidWorkshop.formatTransactionRequirements(requirements)
    local hasFluids = requirementsText ~= ""

    -- an inspection consumes nothing: the block sizes itself to the billed circuits, or goes away
    self.recapFluidsLabel:setText(hasFluids
        and stripTrailingColon(g_i18n:getText(RMS_FluidWorkshop.getRequirementsTextKey(workshopType)))
        or "")
    updateRecapFluids(self, hasFluids and requirements or nil)

    -- disclaimers
    if self.maintenanceType == RealisticMechanicalSystems.STATUS.INSPECTION then
        local disclaimerByType = {
            [RealisticMechanicalSystems.INSPECTION_TYPES.STANDARD] = g_i18n:getText("rms_option_menu_inspection_standard_description"),
            [RealisticMechanicalSystems.INSPECTION_TYPES.VISUAL] = g_i18n:getText("rms_option_menu_inspection_visual_description"),
            [RealisticMechanicalSystems.INSPECTION_TYPES.COMPLETE] = g_i18n:getText("rms_option_menu_inspection_complete_description")
        }
        self.optionOneDisclaimer:setText(stripLeadingMarker(disclaimerByType[self.selectedOptionOne]))
    else
        local disclaimerByType = {
            [RealisticMechanicalSystems.OVERHAUL_TYPES.STANDARD] = g_i18n:getText("rms_option_menu_overhaul_standard_description"),
            [RealisticMechanicalSystems.OVERHAUL_TYPES.PARTIAL]  = g_i18n:getText("rms_option_menu_overhaul_partial_description"),
            [RealisticMechanicalSystems.OVERHAUL_TYPES.FULL]     = g_i18n:getText("rms_option_menu_overhaul_full_description")
        }
        self.optionOneDisclaimer:setText(stripLeadingMarker(disclaimerByType[self.selectedOptionOne]))
    end

    if not isAllowedInMobileWorkshop then
        local procedureName = getSelectedProcedureDisplayName(self)
        local vehicleName = self.vehicle.getFullName ~= nil and self.vehicle:getFullName() or g_i18n:getText("ui_vehicle")
        self.optionOneDisclaimer:setText(string.format(g_i18n:getText("rms_mobile_workshop_low_maintainability"), procedureName, vehicleName))
        self.optionOneDisclaimer:setTextColor(unpack(RMS_Utils.COLOR.ALERT))
    else
        self.optionOneDisclaimer:applyProfile("rms_workshopConfigDescription", true)
    end

    -- option three
    local optionThreeText
    local optionThreeDisclaimerText
    if self.maintenanceType == RealisticMechanicalSystems.STATUS.INSPECTION then
        optionThreeText = g_i18n:getText("rms_option_menu_perform_repair")
        optionThreeDisclaimerText = g_i18n:getText("rms_option_menu_option_three_disclaimer_repair_after_detection")
    else
        optionThreeText = g_i18n:getText("rms_option_menu_perform_renew_paint")
        optionThreeDisclaimerText = g_i18n:getText("rms_option_menu_option_three_disclaimer_overhaul_repaint")
    end

    if self.selectedOptionThree and self.maintenanceType == RealisticMechanicalSystems.STATUS.INSPECTION then
        optionThreeDisclaimerText = optionThreeDisclaimerText .. " " .. g_i18n:getText("rms_option_menu_follow_up_separate_transaction")
    end
    self.optionThreeText:setText(optionThreeText)
    self.optionThreeDisclaimer:setText(stripLeadingMarker(optionThreeDisclaimerText))
    self.recapAddonLabel:setText(optionThreeText)
    self.recapAddon:setText(g_i18n:getText(self.selectedOptionThree and BinaryOptionElement.STRING_YES or BinaryOptionElement.STRING_NO))
    updateBinaryButtons(self)

    if self.startServiceButton ~= nil then
        self.startServiceButton:setDisabled(not isAllowedInMobileWorkshop or not isWorkshopOpen)
    end

    local workshopTypeKey = RMS_Utils.getKeyByValue(RealisticMechanicalSystems.WORKSHOP, workshopType)
    local workshopTypeText = workshopTypeKey ~= nil and g_i18n:getText(workshopType) or ""
    local availabilityText = g_i18n:getText(isWorkshopOpen and "rms_ws_status_open" or "rms_ws_status_closed")
    if workshopTypeText ~= "" then
        availabilityText = availabilityText .. " · " .. workshopTypeText
    end

    self.recapOptions:setText(self.selectedOptionOne ~= nil and g_i18n:getText(self.selectedOptionOne) or "-")
    self.configStatusText:setText(availabilityText)
    refreshConfigScroll(self)
end

---Selects a fixed option-one segment
-- @param integer index option index
function RMS_MaintenanceTwoOptionsDialog:selectOptionOnePreset(index)
    if self.optionOne ~= nil then
        self.optionOne:setState(index)
    end
    self:onClickOptionOne(index)
end

function RMS_MaintenanceTwoOptionsDialog:onClickOptionOnePreset1()
    self:selectOptionOnePreset(1)
end

function RMS_MaintenanceTwoOptionsDialog:onClickOptionOnePreset2()
    self:selectOptionOnePreset(2)
end

function RMS_MaintenanceTwoOptionsDialog:onClickOptionOnePreset3()
    self:selectOptionOnePreset(3)
end

---Reopens the relevant configuration dialog for another intervention type
-- @param string maintenanceType target service type
-- @param boolean usesTwoOptions true for the inspection dialog
function RMS_MaintenanceTwoOptionsDialog:openInterventionConfiguration(maintenanceType, usesTwoOptions)
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

function RMS_MaintenanceTwoOptionsDialog:onClickConfigureInspection()
    self:openInterventionConfiguration(RealisticMechanicalSystems.STATUS.INSPECTION, true)
end

function RMS_MaintenanceTwoOptionsDialog:onClickConfigureMaintenance()
    self:openInterventionConfiguration(RealisticMechanicalSystems.STATUS.MAINTENANCE, false)
end

function RMS_MaintenanceTwoOptionsDialog:onClickConfigureRepair()
    if not RMS_Utils.hasSelectedVisibleBreakdown(self.vehicle) then
        return
    end

    self:openInterventionConfiguration(RealisticMechanicalSystems.STATUS.REPAIR, false)
end

function RMS_MaintenanceTwoOptionsDialog:onClickConfigureOverhaul()
    self:openInterventionConfiguration(RealisticMechanicalSystems.STATUS.OVERHAUL, false)
end

function RMS_MaintenanceTwoOptionsDialog:onClickConfigureRefill()
    self:openInterventionConfiguration(RealisticMechanicalSystems.STATUS.REFILL, false)
end

---Draws the native maintenance glyph in the intervention action list
-- @param table area transparent GUI element receiving the XML draw callback
function RMS_MaintenanceTwoOptionsDialog:onDrawMaintenanceActionIcon(area)
    RMS_WorkshopDialog.drawMaintenanceIcon(area, "rms_workshopMaintenanceActionIcon")
end

---Draws the RMS oil-level glyph in the intervention action list
-- @param table area transparent GUI element receiving the XML draw callback
function RMS_MaintenanceTwoOptionsDialog:onDrawOilActionIcon(area)
    RMS_WorkshopDialog.drawOilIcon(area, "rms_workshopOilActionIcon")
end

---Selects the service type option and refreshes the screen
-- @param integer index selected option index
function RMS_MaintenanceTwoOptionsDialog:onClickOptionOne(index)
    self.selectedOptionOne = self.optionOneValues[index] or self.selectedOptionOne
    self:updateScreen()
end

---Toggles the yes or no option and refreshes the screen
-- @param integer state binary option state
-- @param table binaryOptionElement binary option element
function RMS_MaintenanceTwoOptionsDialog:onClickOptionThree(state, binaryOptionElement)
    self.selectedOptionThree = (state == BinaryOptionElement.STATE_RIGHT)
    self:updateScreen()
end

function RMS_MaintenanceTwoOptionsDialog:onClickOptionThreeNo()
    if self.optionThree ~= nil and self.optionThree.setIsChecked ~= nil then
        self.optionThree:setIsChecked(false, false, false)
    end
    self.selectedOptionThree = false
    self:updateScreen()
end

function RMS_MaintenanceTwoOptionsDialog:onClickOptionThreeYes()
    if self.optionThree ~= nil and self.optionThree.setIsChecked ~= nil then
        self.optionThree:setIsChecked(true, false, false)
    end
    self.selectedOptionThree = true
    self:updateScreen()
end

---Starts the service directly on the server, sends a request from a client, after a money check
function RMS_MaintenanceTwoOptionsDialog:onClickStartService()
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

    local spec = vehicle.spec_RealisticMechanicalSystems
    
    local price = RMS_FluidWorkshop.getTransactionPrice(vehicle, self.maintenanceType, workshopType, self.selectedOptionOne, self.selectedOptionTwo, self.selectedOptionThree)
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
            self.selectedOptionTwo,
            self.selectedOptionThree
        )
        if not started then
            RMS_FluidWorkshop.showResult(result)
            return
        end
        RMS_VehicleChangeStatusEvent.send(vehicle)
    else
        RMS_ServiceRequestEvent.send(vehicle, self.maintenanceType, workshopType, self.selectedOptionOne, self.selectedOptionTwo, self.selectedOptionThree)
    end
    
    self:close()
end

---Closes the dialog
function RMS_MaintenanceTwoOptionsDialog:onClickBack()
    self:close()
end



---Selects the interventions tab in the configuration shell and binds the button backgrounds
function RMS_MaintenanceTwoOptionsDialog:onCreate()
    -- the fluid block follows the circuits actually billed; its XML height gives the design margin
    self.recapFluidsPadding = (self.recapFluidsBlock.size[2]
        - self.recapFluidsLabel.size[2]
        - #self.recapFluidRow * (self.recapFluidRow[1].size[2] + self.recapFluidsLayout.elementSpacing)) * 0.5

    RMS_Utils.mirrorSelectionToChildren(self.configurationTab)
    self.configurationTab:setSelected(true)

    for _, button in ipairs(self.configChoiceButtons or {}) do
        RMS_Utils.mirrorSelectionToChildren(button)
    end

    for _, button in ipairs(self.optionOneButtons or {}) do
        RMS_Utils.mirrorSelectionToChildren(button)
    end

    for _, button in ipairs(self.optionThreeButtons or {}) do
        RMS_Utils.mirrorSelectionToChildren(button)
    end
end

---
function RMS_MaintenanceTwoOptionsDialog:onOpen()
    RMS_MaintenanceTwoOptionsDialog:superClass().onOpen(self)

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
function RMS_MaintenanceTwoOptionsDialog:onClose()
    self.vehicle = nil
    g_messageCenter:unsubscribeAll(self)

    RMS_MaintenanceTwoOptionsDialog:superClass().onClose(self)
end
