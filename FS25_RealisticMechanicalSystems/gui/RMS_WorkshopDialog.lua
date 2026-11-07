-- Copyright © 2026 Squallqt. All rights reserved.

---Workshop of a vehicle: header, tabs, and one frame per page
RMS_WorkshopDialog = {}

local RMS_WorkshopDialog_mt = Class(RMS_WorkshopDialog, MessageDialog)

RMS_WorkshopDialog.TAB = {
    SUMMARY = 1,
    DIAGNOSTIC = 2,
    INTERVENTIONS = 3,
    RECORD = 4
}

local SHORTCUT_SERVICES = { "INSPECTION", "MAINTENANCE", "REPAIR", "OVERHAUL", "REFILL", "BODYWORK", "REMAP" }

---Resale value quoted here, the dealer paying its direct sale bonus
local function getResaleValue(self)
    return RMS_Utils.getResaleValue(self.vehicle, self.workshopType == RealisticMechanicalSystems.WORKSHOP.DEALER)
end

---Creates the dialog
function RMS_WorkshopDialog.new()
    local self = MessageDialog.new(nil, RMS_WorkshopDialog_mt)
    self.currentTab = RMS_WorkshopDialog.TAB.SUMMARY
    return self
end

---Opens the workshop on a vehicle
-- @param string? workshopType workshop the vehicle stands in, nil for its record only
function RMS_WorkshopDialog.show(vehicle, workshopType, serviceType)
    local self = RMS_WorkshopDialog.INSTANCE
    self.vehicle = vehicle
    self.workshopType = workshopType
    self.observedStatus = nil
    for _, page in ipairs(self.pages) do
        page:setVehicle(vehicle, workshopType)
    end
    if workshopType == nil then
        self.currentTab = RMS_WorkshopDialog.TAB.RECORD
    elseif serviceType ~= nil then
        self.currentTab = RMS_WorkshopDialog.TAB.INTERVENTIONS
        self.pages[RMS_WorkshopDialog.TAB.INTERVENTIONS]:selectService(serviceType)
    else
        self.currentTab = RMS_WorkshopDialog.TAB.SUMMARY
    end
    g_gui:showDialog("RMS_WorkshopDialog")
end

---Hands the pages their dialog and puts their elements in its focus
function RMS_WorkshopDialog:onCreate()
    for _, page in ipairs(self.pages) do
        page:initialize(self)
    end
    RMS_Utils.registerScreenFocus(self)
    for _, tab in ipairs(self.tabs) do
        RMS_Utils.mirrorSelectionToChildren(tab)
    end
    local tabTexts = {}
    for index in ipairs(self.tabs) do
        table.insert(tabTexts, tostring(index))
    end
    self.tabPaging:setTexts(tabTexts)
    RMS_Utils.applyScrollSpeed(self.dialogElement)
end

---Watches the vehicle and the money while the dialog is open
function RMS_WorkshopDialog:onOpen()
    RMS_WorkshopDialog:superClass().onOpen(self)
    self.tabBox:invalidateLayout()
    self.tabPaging:setSize(self.tabBox.maxFlowSize + 140 * g_pixelSizeScaledX)
    g_messageCenter:subscribe(MessageType.MONEY_CHANGED, self.refresh, self)
    g_messageCenter:subscribe(MessageType.RMS_WORKSHOP_CHANGE_STATUS, self.refresh, self)
    self:refresh()
    FocusManager:setFocus(self.focusEntry)
end

---Lets the vehicle go and shows the money spent
function RMS_WorkshopDialog:onClose()
    g_messageCenter:unsubscribeAll(self)
    for _, page in ipairs(self.pages) do
        page:setVehicle(nil, nil)
    end
    self.vehicle = nil
    g_currentMission:showMoneyChange(MoneyType.VEHICLE_RUNNING_COSTS)
    g_currentMission:showMoneyChange(MoneyType.SHOP_VEHICLE_BUY)
    g_currentMission:showMoneyChange(MoneyType.SHOP_VEHICLE_SELL)
    RMS_WorkshopDialog:superClass().onClose(self)
end

---Refreshes the pages when the vehicle changes status or value
function RMS_WorkshopDialog:update(dt)
    RMS_WorkshopDialog:superClass().update(self, dt)
    if self.vehicle:getCurrentStatus() ~= self.observedStatus or getResaleValue(self) ~= self.observedResaleValue then
        self:refresh()
    end
end

---Writes the workshop state into the header and every page
function RMS_WorkshopDialog:refresh()
    local vehicle, STATUS = self.vehicle, RealisticMechanicalSystems.STATUS
    local spec = vehicle.spec_RealisticMechanicalSystems
    self.observedStatus = vehicle:getCurrentStatus()
    self.observedResaleValue = getResaleValue(self)

    RMS_Utils.setBalance(self.moneyBox, self.moneyBoxBg, self.balanceElement)

    local isRecord = self.workshopType == nil
    local isOpen = not isRecord and RMS_Main:isWorkshopTypeOpen(self.workshopType)
    local isUnderService = spec.currentState ~= STATUS.READY
    local statusText = g_i18n:getText(isOpen and "rms_ws_status_open" or "rms_ws_status_closed")
    if isUnderService then
        statusText = string.format(g_i18n:getText("rms_ws_status_in_progress_format"), RMS_Utils.formatServiceState(spec.currentState),
            RMS_Utils.formatFinishTime(vehicle:getServiceFinishTime(nil, nil, nil, nil)))
    end
    if not isRecord then
        statusText = statusText .. " · " .. g_i18n:getText(self.workshopType)
    end
    local state = {
        statusText = statusText,
        statusColor = isOpen and RMS_Utils.COLOR.TEXT or RMS_Utils.COLOR.TEXT_DIM,
        isOpen = isOpen,
        isUnderService = isUnderService
    }
    self.state = state
    -- the record alone answers when the vehicle is outside a workshop
    for index, page in ipairs(self.pages) do
        if not isRecord or index == RMS_WorkshopDialog.TAB.RECORD then
            page:refresh(state)
        end
    end

    for index, tab in ipairs(self.tabs) do
        tab:setDisabled(isRecord and index ~= RMS_WorkshopDialog.TAB.RECORD)
    end
    self.tabPaging:setDisabled(isRecord)
    self:setTab(self.currentTab)
end

---Shows a page and links the focus over it
function RMS_WorkshopDialog:setTab(tabIndex)
    self.currentTab = tabIndex
    for index, page in ipairs(self.pages) do
        page:setVisible(index == tabIndex)
        self.tabs[index]:setSelected(index == tabIndex)
    end
    RMS_Utils.resetScrollingTexts(self.pages[tabIndex])
    self.tabPaging:setState(tabIndex, false)
    self:updateButtons()
    self:updateFocusLinks()
end

---Shows the intervention shortcuts, or the action of the page
function RMS_WorkshopDialog:updateButtons()
    local actionText, isActionDisabled = self.pages[self.currentTab]:getAction()
    local isRecord = self.workshopType == nil
    -- one activate key: the dealer tops up, the tuner never comes there
    local offers = { REFILL = not isRecord and RMS_FluidWorkshop.getIsTopUpOffered(self.workshopType),
        REMAP = not isRecord and RMS_EngineRemap.getIsTunerAt(self.workshopType) }
    self.cancelServiceButton:setVisible(self.state.isUnderService)
    for index, button in ipairs(self.shortcuts) do
        button:setVisible(actionText == nil and not isRecord and not self.state.isUnderService
            and offers[SHORTCUT_SERVICES[index]] ~= false)
        button:setDisabled(not self.state.isOpen)
    end
    self.pageActionButton:setVisible(actionText ~= nil)
    if actionText ~= nil then
        self.pageActionButton:setText(actionText)
        self.pageActionButton:setDisabled(isActionDisabled)
    end
    RMS_Utils.showButtonSeparators(self.buttonBox)
end

---Runs the action of the page on screen
function RMS_WorkshopDialog:onClickPageAction()
    self.pages[self.currentTab]:onAction()
end

---Links the focus over the page on screen, under the tab selector
function RMS_WorkshopDialog:updateFocusLinks()
    local page = self.pages[self.currentTab]
    self.focusEntry = RMS_Utils.linkFocusColumns(self.tabPaging, page:getFocusColumns(), page:getFocusEntry())
    RMS_Utils.keepFocusShown(self.focusEntry)
end

---Shows the page of a clicked tab
function RMS_WorkshopDialog:onClickTab(button)
    for index, tab in ipairs(self.tabs) do
        if tab == button then
            self:setTab(index)
        end
    end
end

---Shows the page the pager landed on
function RMS_WorkshopDialog:onTabPagingChanged()
    self:setTab(self.tabPaging:getState())
end

---Opens the intervention of a shortcut
function RMS_WorkshopDialog:onClickShortcut(button)
    for index, shortcut in ipairs(self.shortcuts) do
        if shortcut == button then
            self:selectService(RealisticMechanicalSystems.STATUS[SHORTCUT_SERVICES[index]])
        end
    end
end

---Opens an intervention on the interventions page
function RMS_WorkshopDialog:selectService(serviceType)
    self.pages[RMS_WorkshopDialog.TAB.INTERVENTIONS]:selectService(serviceType)
    self.currentTab = RMS_WorkshopDialog.TAB.INTERVENTIONS
    self:refresh()
end

---Asks the player to confirm cancelling the running service
function RMS_WorkshopDialog:onClickCancelService()
    local state = self.vehicle.spec_RealisticMechanicalSystems.currentState
    local title = string.format(g_i18n:getText("rms_ws_cancel_confirm_title"), RMS_Utils.formatServiceState(state))
    YesNoDialog.show(self.onCancelServiceConfirm, self, g_i18n:getText("rms_ws_cancel_confirm_text"), title)
end

---Cancels the running service once the player confirmed it
function RMS_WorkshopDialog:onCancelServiceConfirm(yes)
    if not yes then
        return
    end
    if g_server ~= nil then
        self.vehicle:cancelService()
    else
        RMS_CancelServiceEvent.send(self.vehicle)
    end
    self:refresh()
end

---Leaves the view the page shows, or the workshop from its first view
function RMS_WorkshopDialog:onClickBack()
    if not self.pages[self.currentTab]:goBack() then
        self:close()
    end
end
