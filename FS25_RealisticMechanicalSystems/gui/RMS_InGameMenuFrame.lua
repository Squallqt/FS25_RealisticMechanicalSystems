-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---Fleet and settings menu frame.
RMS_InGameMenuFrame = {}
RMS_InGameMenuFrame.MOD_DIR = g_currentModDirectory
RMS_InGameMenuFrame.PAGE_NAME = "pageRMSFleet"
RMS_InGameMenuFrame.REFRESH_INTERVAL_MS = 5000
-- fitToBoundary uses 1 as its overview reference.
RMS_InGameMenuFrame.MAP_ZOOM_DEFAULT = 7
RMS_InGameMenuFrame.MAP_ZOOM_MIN = 1
RMS_InGameMenuFrame.MAP_ZOOM_MAX = RMS_InGameMenuFrame.MAP_ZOOM_DEFAULT * 4
RMS_InGameMenuFrame.MAP_ZOOM_STEP = 1.25
RMS_InGameMenuFrame.SCREEN_EDGE_SLIDER_MARGIN_X = 0
RMS_InGameMenuFrame.MENU_BUTTON_COUNT = 7
RMS_InGameMenuFrame.SUB_CATEGORY = {
    ACTIVE = 1,
    SERVICE = 2,
    SETTINGS = 3
}
RMS_InGameMenuFrame.SORT = {
    DEADLINE = 1,
    NAME = 2,
    HOURS = 3
}
RMS_InGameMenuFrame.URGENCY = {
    NONE = 0,
    SOON = 1,
    OVERDUE = 2
}
RMS_InGameMenuFrame.DUE_SOON_RATIO = 0.8

local SUB_CATEGORY = RMS_InGameMenuFrame.SUB_CATEGORY
local SORT = RMS_InGameMenuFrame.SORT
local URGENCY = RMS_InGameMenuFrame.URGENCY
local SORT_TEXT_KEYS = {"rms_fleet_sort_deadline", "rms_fleet_sort_name", "rms_fleet_sort_hours"}
local TRACKED_SORTS = {SORT.DEADLINE, SORT.NAME, SORT.HOURS}
local UNTRACKED_SORTS = {SORT.NAME, SORT.HOURS}
local COLOR_SOON = {1.0, 0.55, 0.0, 1.0}

local RMS_InGameMenuFrame_mt = Class(RMS_InGameMenuFrame, TabbedMenuFrameElement)

---Returns the colour of an urgency level, the game green while nothing is due
local function getUrgencyColor(urgency)
    if urgency == URGENCY.OVERDUE then
        return RMS_Utils.COLOR.ALERT
    elseif urgency == URGENCY.SOON then
        return COLOR_SOON
    end
    return RMS_Utils.COLOR.HIGHLIGHT
end

---Formats a number of hours with its unit, in the number format of the language
local function formatHours(hours)
    return RMS_Utils.formatHours(hours)
end

---Formats the hours left before the next maintenance, or overdue
local function formatDeadline(remaining)
    local key = remaining < 0 and "rms_fleet_overdue" or "rms_fleet_remaining"
    return string.format(g_i18n:getText(key), g_i18n:formatNumber(math.abs(remaining), 1))
end

---Sums the price of every maintenance log entry of a vehicle
local function getTotalCost(vehicle)
    local totalCost = 0
    for _, entry in ipairs(vehicle.spec_RealisticMechanicalSystems.maintenanceLog) do
        totalCost = totalCost + (entry.price or 0)
    end
    return totalCost
end

---Returns what the running intervention costs
local function getCommittedCost(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    local price = spec.pendingServicePrice
    if price ~= nil and price > 0 then
        return price
    end

    if spec.currentState == RealisticMechanicalSystems.STATUS.REFILL then
        return RMS_FluidWorkshop.getTransactionPrice(vehicle, spec.currentState, spec.workshopType,
            spec.serviceOptionOne, spec.serviceOptionTwo, spec.serviceOptionThree or false) or 0
    end
    return vehicle:getServicePrice(spec.currentState, spec.serviceOptionOne, spec.serviceOptionTwo,
        spec.serviceOptionThree or false) or 0
end

---Tells whether a vehicle belongs in the menu
local function canDisplayVehicle(vehicle, farmId)
    return g_currentMission.accessHandler:canPlayerAccess(vehicle)
        and vehicle:getOwnerFarmId() == farmId
        and vehicle:getShowInVehiclesOverview()
        and g_storeManager:getItemByXMLFilename(vehicle.configFileName) ~= nil
end

---Builds the list row of a vehicle, tracked or not
local function buildRow(vehicle, isTracked)
    local storeItem = g_storeManager:getItemByXMLFilename(vehicle.configFileName)
    local category = g_storeManager:getCategoryByName(storeItem.categoryName)
    local row = {
        vehicle = vehicle,
        isTracked = isTracked,
        isServicing = false,
        name = vehicle:getFullName(),
        image = storeItem.imageFilename,
        categoryName = category.name,
        categoryTitle = category.title,
        categoryImage = category.image,
        categoryOrder = category.orderId,
        hours = math.floor(vehicle:getOperatingTime() / 360000) / 10,
        remaining = math.huge,
        urgency = URGENCY.NONE
    }

    if not isTracked then
        row.status = g_i18n:getText(RealisticMechanicalSystems.getExclusionReason(vehicle))
        return row
    end

    local condition, isCompleteInspection = vehicle:getLastInspectedCondition()
    row.reportHours, row.isReportOutdated = vehicle:getInspectionReportAge()
    row.condition = RMS_Utils.formatCondition(condition, isCompleteInspection)
    row.conditionColor = row.isReportOutdated and RMS_Utils.COLOR.TEXT_DIM or {RMS_Utils.getConditionColor(condition, isCompleteInspection)}
    row.isServicing = vehicle:isUnderService()
    row.used, row.interval = vehicle:getServiceCountdown()
    row.schedule = vehicle:getServiceSchedule()

    if row.isServicing then
        row.status = string.format("%s · %s", RMS_Utils.formatServiceState(vehicle:getCurrentStatus()),
            RMS_Utils.formatDuration(vehicle:getServiceDuration()))
    else
        row.remaining = row.interval - row.used
        if row.used >= row.interval or (row.schedule ~= nil and row.schedule.calendarDue) then
            row.urgency = URGENCY.OVERDUE
        elseif row.schedule ~= nil and row.schedule.progress >= RMS_InGameMenuFrame.DUE_SOON_RATIO then
            row.urgency = URGENCY.SOON
        end
        row.status = row.schedule ~= nil and row.schedule.calendarDue
            and g_i18n:getText("rms_service_calendar_due") or formatDeadline(row.remaining)
    end

    return row
end

---Orders two rows on a sort mode, ties broken by name then by vehicle
local function isRowBefore(sortMode, a, b)
    if sortMode == SORT.DEADLINE and a.remaining ~= b.remaining then
        return a.remaining < b.remaining
    elseif sortMode == SORT.HOURS and a.hours ~= b.hours then
        return a.hours > b.hours
    end

    local nameA, nameB = string.lower(a.name), string.lower(b.name)
    if nameA ~= nameB then
        return nameA < nameB
    end
    return tostring(a.vehicle.uniqueId) < tostring(b.vehicle.uniqueId)
end

---Loads the frame layout and returns the frame
-- @return table frame instance of class RMS_InGameMenuFrame
function RMS_InGameMenuFrame.register()
    local frame = RMS_InGameMenuFrame.new()
    local filename = RMS_InGameMenuFrame.MOD_DIR .. "gui/RMS_InGameMenuFrame.xml"
    g_gui:loadGui(filename, "rmsInGameMenuFleetFrame", frame, false)
    return frame
end

---Create instance of RMS_InGameMenuFrame
-- @param table? target target
-- @param table? customMt custom metatable
-- @return table self instance of class RMS_InGameMenuFrame
function RMS_InGameMenuFrame.new(target, customMt)
    local self = TabbedMenuFrameElement.new(target, customMt or RMS_InGameMenuFrame_mt)

    self.hasCustomMenuButtons = true
    self.trackedRows = {}
    self.serviceRows = {}
    self.untrackedRows = {}
    self.categories = {}
    self.machineRows = {}
    self.stateRows = {}
    self.refreshTimerMs = 0
    self.subCategoryState = SUB_CATEGORY.ACTIVE
    self.isUntrackedView = false
    self.isCategoryView = true
    self.sortMode = SORT.DEADLINE
    self.sortModes = TRACKED_SORTS
    self.showMap = false
    self.vehicleMapZoom = RMS_InGameMenuFrame.MAP_ZOOM_DEFAULT
    self.isRefreshing = false
    self.isFrameOpen = false
    self.conditionRingRatio = 0
    self.serviceRingRatio = 0

    return self
end

---Refreshes the balance box
function RMS_InGameMenuFrame:updateBalanceDisplay()
    local money = g_currentMission:getMoney()
    if money <= -1 then
        self.balanceElement:applyProfile(ShopMenu.GUI_PROFILE.SHOP_MONEY_NEGATIVE, nil, true)
    else
        self.balanceElement:applyProfile(ShopMenu.GUI_PROFILE.SHOP_MONEY, nil, true)
    end

    self.balanceElement:setText(g_i18n:formatMoney(money, 0, true, false))
    self.moneyBox:invalidateLayout()
    self.moneyBoxBg:setSize(self.moneyBox.flowSizes[1] + 60 * g_pixelSizeScaledX)
end

---Builds the footer actions, wires the tabs and lists, then fills the page
function RMS_InGameMenuFrame:initialize()
    RMS_InGameMenuFrame:superClass().initialize(self)

    self.backButtonInfo = {inputAction = InputAction.MENU_BACK}
    self.levelUpButtonInfo = {
        inputAction = InputAction.MENU_BACK,
        callback = function()
            self:onClickBack()
        end
    }
    self.nextPageButtonInfo = {
        inputAction = InputAction.MENU_PAGE_NEXT,
        text = g_i18n:getText("ui_ingameMenuNext"),
        callback = function()
            self:onPageNext()
        end
    }
    self.prevPageButtonInfo = {
        inputAction = InputAction.MENU_PAGE_PREV,
        text = g_i18n:getText("ui_ingameMenuPrev"),
        callback = function()
            self:onPagePrevious()
        end
    }
    -- MENU_ACCEPT already confirms the focused element.
    self.enterVehicleButtonInfo = {
        inputAction = InputAction.MENU_EXTRA_2,
        text = g_i18n:getText("button_enterVehicle"),
        callback = function()
            self:onTryEnterVehicle()
        end
    }
    self.sellVehicleButtonInfo = {
        inputAction = InputAction.MENU_CANCEL,
        text = g_i18n:getText("ui_sellItem"),
        callback = function()
            self:onSellSelectedVehicle()
        end
    }
    self.maintenanceLogButtonInfo = {
        inputAction = InputAction.MENU_ACTIVATE,
        text = g_i18n:getText("rms_ws_label_maintenance_log"),
        callback = function()
            self:onShowMaintenanceLog()
        end
    }
    self.exclusionButtonInfo = {
        inputAction = InputAction.MENU_EXTRA_1,
        callback = function()
            self:onToggleExclusion()
        end
    }

    for index, tab in ipairs(self.subCategoryTabs) do
        tab.getIsSelected = function()
            return index == self.subCategoryState
        end
        RMS_Utils.mirrorSelectionToChildren(tab)
    end
    self.subCategoryPaging:setTexts({"1", "2", "3"})
    self.subCategoryPaging:setState(self.subCategoryState, false)
    self.subCategoryBox:invalidateLayout()

    for _, list in ipairs({self.categoryList, self.machineList, self.stateList}) do
        list:setDataSource(self)
        list:setDelegate(self)
    end

    self.locationButton.getIsSelected = function()
        return self.showMap
    end
    RMS_Utils.mirrorSelectionToChildren(self.locationButton)
    RMS_Utils.centerActionContent(self.locationButton)

    self.pillValueColor = {unpack(self.serviceValues[1].textColor)}
    self.lastCheckValue:setTextColor(unpack(RMS_Utils.COLOR.TEXT_DIM))
    self.serviceFootValue:setTextColor(unpack(RMS_Utils.COLOR.TEXT_DIM))

    RMS_SettingsPage.initializeControls(self)
    self.settingsContainer:setVisible(false)
    self:setMenuButtonInfo({self.backButtonInfo, self.prevPageButtonInfo, self.nextPageButtonInfo})
end

---Returns the active main tab
-- @return integer index sub category index
function RMS_InGameMenuFrame:getCurrentSubCategory()
    return self.subCategoryState
end

---Tells whether the navigator shows a view opened from another one
-- @return boolean isNested true when the back action leads to a parent view
function RMS_InGameMenuFrame:getIsNestedView()
    return self.subCategoryState == SUB_CATEGORY.ACTIVE and (self.isUntrackedView or not self.isCategoryView)
end

---Shows a main tab from its first view, the last one being the settings page
-- @param integer state sub category index
function RMS_InGameMenuFrame:updateSubCategoryPages(state)
    local isSettings = state == SUB_CATEGORY.SETTINGS

    self.subCategoryState = state
    self.subCategoryPaging:setState(state, false)
    self.isUntrackedView = false
    self.isCategoryView = state == SUB_CATEGORY.ACTIVE
    self.focusedCategory = nil
    self.categoryName = nil
    self.selectedVehicle = nil
    self.showMap = false

    self.fleetPage:setVisible(not isSettings)
    self.settingsContainer:setVisible(isSettings)
    if isSettings then
        RMS_SettingsPage.show(self)
    end

    self:reloadRows()
    self:focusNavigator()
    RMS_Utils.resetScrollingTexts(isSettings and self.settingsContainer or self.fleetPage)
end

---Keeps the settings slider at the native screen edge
function RMS_InGameMenuFrame:updateScreenEdgeSliders()
    local sliderBox = self.settingsSliderBox
    local width, height = sliderBox.absSize[1], sliderBox.absSize[2]
    if self.settingsSliderWidth == width and self.settingsSliderHeight == height then
        return
    end

    self.settingsSliderWidth, self.settingsSliderHeight = width, height
    sliderBox:setAbsolutePosition(1 - width - RMS_InGameMenuFrame.SCREEN_EDGE_SLIDER_MARGIN_X, 0.5 - height * 0.5)
    for _, child in ipairs(sliderBox.elements) do
        child:updateAbsolutePosition()
    end
end

---
function RMS_InGameMenuFrame:onFrameOpen()
    self.subCategoryBox:invalidateLayout()
    self.subCategoryPaging:setSize(self.subCategoryBox.maxFlowSize + 140 * g_pixelSizeScaledX)
    self.vehicleMap:setIngameMap(g_currentMission.hud:getIngameMap())

    RMS_InGameMenuFrame:superClass().onFrameOpen(self)

    self.isFrameOpen = true
    RMS_WorkshopDialog.setCurrencyIcon(self.currencyIcon)
    self.refreshTimerMs = RMS_InGameMenuFrame.REFRESH_INTERVAL_MS
    self:updateSubCategoryPages(self.subCategoryState)
    self:updateScreenEdgeSliders()
end

---
function RMS_InGameMenuFrame:onFrameClose()
    self.isFrameOpen = false
    RMS_SettingsPage.applyChanges()
    RMS_InGameMenuFrame:superClass().onFrameClose(self)
end

---
-- @param float dt time since last call in ms
function RMS_InGameMenuFrame:update(dt)
    RMS_InGameMenuFrame:superClass().update(self, dt)
    self:updateScreenEdgeSliders()

    if self.subCategoryState == SUB_CATEGORY.SETTINGS then
        return
    end

    self.refreshTimerMs = self.refreshTimerMs - dt
    if self.refreshTimerMs <= 0 then
        self.refreshTimerMs = RMS_InGameMenuFrame.REFRESH_INTERVAL_MS
        self:reloadRows()
    end
end

---Rebuilds the rows of every section from the live fleet and refreshes the page
function RMS_InGameMenuFrame:reloadRows()
    local farmId = g_currentMission:getFarmId()
    local overdue, soon = 0, 0

    self.trackedRows, self.serviceRows, self.untrackedRows = {}, {}, {}
    for _, vehicle in pairs(g_currentMission.vehicleSystem.vehicles) do
        if canDisplayVehicle(vehicle, farmId) then
            local spec = vehicle.spec_RealisticMechanicalSystems
            local row = buildRow(vehicle, spec ~= nil and not spec.isExcludedVehicle)

            if not row.isTracked then
                table.insert(self.untrackedRows, row)
            else
                table.insert(self.trackedRows, row)
                if row.isServicing then
                    table.insert(self.serviceRows, row)
                elseif row.urgency == URGENCY.OVERDUE then
                    overdue = overdue + 1
                elseif row.urgency == URGENCY.SOON then
                    soon = soon + 1
                end
            end
        end
    end

    self:updateBalanceDisplay()
    self:updatePulse(overdue, soon, #self.serviceRows)

    if self.subCategoryState ~= SUB_CATEGORY.SETTINGS then
        self:refreshNavigator()
        self:refreshDossier()
        self:updateFocusLinks()
    end
    self:updateActionButtons()
end

---Writes the three counters of the fleet
-- @param integer overdue machines past their maintenance
-- @param integer soon machines due soon
-- @param integer servicing machines in a workshop
function RMS_InGameMenuFrame:updatePulse(overdue, soon, servicing)
    local counts = {overdue, soon, servicing}
    local colors = {RMS_Utils.COLOR.ALERT, COLOR_SOON, RMS_Utils.COLOR.HIGHLIGHT}

    for index, element in ipairs(self.pulseValues) do
        element:setText(tostring(counts[index]))
        element:setTextColor(unpack(counts[index] > 0 and colors[index] or RMS_Utils.COLOR.TEXT_DIM))
    end
    self.pulseLayout:invalidateLayout()
end

---Returns the rows of the section on screen
-- @return table rows list rows
function RMS_InGameMenuFrame:getSectionRows()
    if self.subCategoryState == SUB_CATEGORY.SERVICE then
        return self.serviceRows
    end
    return self.isUntrackedView and self.untrackedRows or self.trackedRows
end

---Groups rows by store category, each group keeping its most urgent machine
local function groupCategories(rows)
    local categories, byName = {}, {}

    for _, row in ipairs(rows) do
        local category = byName[row.categoryName]
        if category == nil then
            category = {
                name = row.categoryName,
                title = row.categoryTitle,
                image = row.categoryImage,
                order = row.categoryOrder,
                count = 0,
                overdue = 0,
                soon = 0,
                top = row
            }
            byName[row.categoryName] = category
            table.insert(categories, category)
        end

        category.count = category.count + 1
        if row.urgency == URGENCY.OVERDUE then
            category.overdue = category.overdue + 1
        elseif row.urgency == URGENCY.SOON then
            category.soon = category.soon + 1
        end
        if isRowBefore(SORT.DEADLINE, row, category.top) then
            category.top = row
        end
    end

    table.sort(categories, function(a, b)
        return a.order < b.order
    end)
    return categories
end

---Rebuilds the navigator card, keeping its selection
function RMS_InGameMenuFrame:refreshNavigator()
    local rows = self:getSectionRows()
    local isFleet = self.subCategoryState == SUB_CATEGORY.ACTIVE
    local title = g_i18n:getText(self:getSectionTitleKey())
    local count = #rows

    self.categories = isFleet and groupCategories(rows) or {}
    self.topRow = rows[1]
    for _, row in ipairs(rows) do
        if isRowBefore(SORT.DEADLINE, row, self.topRow) then
            self.topRow = row
        end
    end

    local category = self:getCategory(self.categoryName)
    if self.categoryName ~= nil and category == nil then
        self.categoryName = nil
        self.isCategoryView = true
    end
    local isCategoryView = isFleet and self.isCategoryView

    self.sortModes = self.isUntrackedView and UNTRACKED_SORTS or TRACKED_SORTS
    if self.sortSelector.rmsSortModes ~= self.sortModes then
        local texts = {}
        for _, mode in ipairs(self.sortModes) do
            table.insert(texts, g_i18n:getText(SORT_TEXT_KEYS[mode]))
        end
        self.sortSelector.rmsSortModes = self.sortModes
        self.sortSelector:setTexts(texts)
        self.sortMode = self.sortModes[1]
        self.sortSelector:setState(1, false)
    end

    self.machineRows = {}
    if not isCategoryView then
        for _, row in ipairs(rows) do
            if category == nil or row.categoryName == category.name then
                table.insert(self.machineRows, row)
            end
        end
        table.sort(self.machineRows, function(a, b)
            return isRowBefore(self.sortMode, a, b)
        end)

        if category ~= nil then
            title, count = category.title, #self.machineRows
        elseif isFleet then
            title = g_i18n:getText(self:getAllMachinesTextKey())
        end
    end

    self.navTitle:setText(string.format("%s · %d", title, count))

    self.categoryBlock:setVisible(isCategoryView and count > 0)
    self.sortRow:setVisible(not isCategoryView and count > 0)
    self.machineBlock:setVisible(not isCategoryView and count > 0)
    self.navEmptyText:setVisible(count == 0)
    self.navEmptyText:setText(g_i18n:getText(self:getEmptyTextKey()))
    local isNested = self:getIsNestedView()
    self.viewButton:setVisible(isFleet and not isNested and #self.untrackedRows > 0)
    self.viewButton:setText(string.format("%s · %d", g_i18n:getText("rms_ingame_menu_section_other"), #self.untrackedRows))
    RMS_Utils.centerActionContent(self.viewButton)
    self.backButton:setVisible(isNested)
    self.backButton:setText(g_i18n:getText(self.isUntrackedView and not isCategoryView and "rms_ingame_menu_section_other" or "rms_ingame_menu_section_active"))
    RMS_Utils.centerActionContent(self.backButton)

    if count == 0 then
        self.selectedVehicle = nil
        return
    end

    -- Suppress selection callbacks during reload.
    local list = isCategoryView and self.categoryList or self.machineList
    self.isRefreshing = true
    list:setSoundSuppressed(true)
    list:reloadData()
    list:setSelectedItem(1, isCategoryView and self:getFocusedCategoryIndex() or self:getSelectedMachineIndex(), false, true)
    list:setSoundSuppressed(false)
    self.isRefreshing = false
end

---Returns the l10n key of the title of the section on screen
-- @return string key l10n key
function RMS_InGameMenuFrame:getSectionTitleKey()
    if self.subCategoryState == SUB_CATEGORY.SERVICE then
        return "rms_ingame_menu_section_service"
    end
    return self.isUntrackedView and "rms_ingame_menu_section_other" or "rms_ingame_menu_section_active"
end

---Returns the l10n key of the message an empty section shows
-- @return string key l10n key
function RMS_InGameMenuFrame:getEmptyTextKey()
    if self.subCategoryState == SUB_CATEGORY.SERVICE then
        return "rms_ingame_menu_empty_service"
    end
    return self.isUntrackedView and "rms_ingame_menu_empty_other" or "rms_ingame_menu_empty_active"
end

---Returns the l10n key of the entry listing every machine of the pool on screen
-- @return string key l10n key
function RMS_InGameMenuFrame:getAllMachinesTextKey()
    return self.isUntrackedView and "rms_fleet_all_untracked" or "rms_fleet_all"
end

---Returns a category of the section on screen
-- @param string? name store category name
-- @return table? category category group, nil when the section holds none of that name
function RMS_InGameMenuFrame:getCategory(name)
    for _, category in ipairs(self.categories) do
        if category.name == name then
            return category
        end
    end
    return nil
end

---Returns the list index of the highlighted category
-- @return integer index list index
function RMS_InGameMenuFrame:getFocusedCategoryIndex()
    for index, category in ipairs(self.categories) do
        if category.name == self.focusedCategory then
            return index + 1
        end
    end

    self.focusedCategory = nil
    return 1
end

---Returns the list index of the selected machine
-- @return integer index list index
function RMS_InGameMenuFrame:getSelectedMachineIndex()
    for index, row in ipairs(self.machineRows) do
        if row.vehicle == self.selectedVehicle then
            return index
        end
    end

    self.selectedVehicle = self.machineRows[1].vehicle
    return 1
end

---Chains the focus over what the view shows
function RMS_InGameMenuFrame:updateFocusLinks()
    local column, side = {}, {}
    for _, element in ipairs({self.sortSelector, self.categoryList, self.machineList, self.viewButton, self.backButton}) do
        if element:getIsVisible() then
            table.insert(column, element)
        end
    end
    for _, element in ipairs({self.locationButton, self.stateList, self.logButton}) do
        if element:getIsVisible() then
            table.insert(side, element)
        end
    end

    local list = self.categoryList:getIsVisible() and self.categoryList or self.machineList
    self.navigatorFocus = list:getIsVisible() and list or column[1] or self.subCategoryPaging

    for index, element in ipairs(column) do
        FocusManager:linkElements(element, FocusManager.TOP, column[index - 1])
        FocusManager:linkElements(element, FocusManager.BOTTOM, column[index + 1])
        FocusManager:linkElements(element, FocusManager.LEFT, nil)
        FocusManager:linkElements(element, FocusManager.RIGHT, side[1])
    end
    for index, element in ipairs(side) do
        FocusManager:linkElements(element, FocusManager.TOP, self.navigatorFocus)
        FocusManager:linkElements(element, FocusManager.BOTTOM, self.navigatorFocus)
        FocusManager:linkElements(element, FocusManager.LEFT, side[index - 1] or self.navigatorFocus)
        FocusManager:linkElements(element, FocusManager.RIGHT, side[index + 1])
    end

    if self.stateList:getIsVisible() then
        FocusManager:linkElements(self.stateList, FocusManager.TOP, self.logButton:getIsVisible() and self.logButton or nil)
        FocusManager:linkElements(self.stateList, FocusManager.BOTTOM, nil)
    end

    if self.vehicleMap:getIsVisible() then
        FocusManager:linkElements(self.mapZoomInButton, FocusManager.TOP, self.navigatorFocus)
        FocusManager:linkElements(self.mapZoomInButton, FocusManager.BOTTOM, self.mapZoomOutButton)
        FocusManager:linkElements(self.mapZoomOutButton, FocusManager.TOP, self.mapZoomInButton)
        FocusManager:linkElements(self.mapZoomOutButton, FocusManager.BOTTOM, self.locationButton)
        for _, element in ipairs({self.mapZoomInButton, self.mapZoomOutButton}) do
            FocusManager:linkElements(element, FocusManager.LEFT, self.navigatorFocus)
            FocusManager:linkElements(element, FocusManager.RIGHT, side[2])
        end
        FocusManager:linkElements(self.locationButton, FocusManager.TOP, self.mapZoomOutButton)
    end

    local focused = FocusManager:getFocusedElement()
    if focused == nil or focused == self.subCategoryPaging or not focused:getIsVisible() then
        self:focusNavigator()
    end
end

---Gives the focus back to the navigator
function RMS_InGameMenuFrame:focusNavigator()
    if self.isFrameOpen and self.subCategoryState ~= SUB_CATEGORY.SETTINGS then
        FocusManager:setFocus(self.navigatorFocus)
    end
end

---
-- @param table list list element
-- @param integer _section section index
-- @return integer count number of rows
function RMS_InGameMenuFrame:getNumberOfItemsInSection(list, _section)
    if list == self.categoryList then
        return #self.categories + 1
    elseif list == self.stateList then
        return #self.stateRows
    end
    return #self.machineRows
end

---
-- @param table list list element
-- @param integer _section section index
-- @param integer index row index
-- @return string name cell template name
function RMS_InGameMenuFrame:getCellTypeForItemInSection(list, _section, index)
    if list == self.categoryList then
        return index == 1 and "all" or "category"
    elseif list == self.stateList then
        local row = self.stateRows[index]
        return row ~= nil and row.kind or "system"
    end
    return "machine"
end

---Loads a picture into a cell only when it changes
local function setCellImage(element, filename)
    if element.rmsImageFilename ~= filename then
        element.rmsImageFilename = filename
        element:setImageFilename(filename)
    end
end

---
-- @param table list list element
-- @param integer _section section index
-- @param integer index row index
-- @param table cell cell element
function RMS_InGameMenuFrame:populateCellForItemInSection(list, _section, index, cell)
    if list == self.stateList then
        RMS_Utils.populateConditionCell(cell, self.stateRows[index])
        return
    end

    if list == self.machineList then
        local row = self.machineRows[index]
        local conditionElement = cell:getAttribute("condition")
        local statusElement = cell:getAttribute("status")

        setCellImage(cell:getAttribute("picture"), row.image)
        cell:getAttribute("title"):setText(row.name)
        cell:getAttribute("label"):setText(row.isTracked and g_i18n:getText("rms_fleet_check") or "")
        conditionElement:setText(row.condition or "")
        conditionElement:setTextColor(unpack(row.conditionColor or RMS_Utils.COLOR.TEXT))
        statusElement:setText(row.status)
        statusElement:setTextColor(unpack(row.isTracked and getUrgencyColor(row.urgency) or RMS_Utils.COLOR.TEXT_DIM))
        return
    end

    if index == 1 then
        cell:getAttribute("title"):setText(g_i18n:getText(self:getAllMachinesTextKey()))
        cell:getAttribute("count"):setText(tostring(#self:getSectionRows()))
        return
    end

    local category = self.categories[index - 1]
    local noteElement = cell:getAttribute("note")

    setCellImage(cell:getAttribute("picture"), category.image)
    cell:getAttribute("title"):setText(category.title)
    cell:getAttribute("count"):setText(tostring(category.count))
    noteElement:setVisible(category.overdue > 0 or category.soon > 0)
    if category.overdue > 0 then
        noteElement:setText(string.format(g_i18n:getText("rms_fleet_overdue_count"), category.overdue))
        noteElement:setTextColor(unpack(RMS_Utils.COLOR.ALERT))
    elseif category.soon > 0 then
        noteElement:setText(string.format(g_i18n:getText("rms_fleet_due_soon_count"), category.soon))
        noteElement:setTextColor(unpack(COLOR_SOON))
    end
    cell:getAttribute("texts"):invalidateLayout()
end

---Follows the highlight: a category shows its most urgent machine
-- @param table list list element
-- @param integer _section section index
-- @param integer index row index
function RMS_InGameMenuFrame:onListSelectionChanged(list, _section, index)
    if self.isRefreshing or list == self.stateList then
        return
    end

    if list == self.categoryList then
        local category = self.categories[index - 1]
        self.focusedCategory = category ~= nil and category.name or nil
    else
        local row = self.machineRows[index]
        self.selectedVehicle = row ~= nil and row.vehicle or nil
    end

    self:refreshDossier()
    self:updateActionButtons()
end

---Opens the list of a category, or of the whole section from the first entry
-- @param table _list list element
-- @param integer _section section index
-- @param integer index row index
function RMS_InGameMenuFrame:onClickCategory(_list, _section, index)
    local category = self.categories[index - 1]
    local top = category ~= nil and category.top or self.topRow

    self.focusedCategory = category ~= nil and category.name or nil
    self.categoryName = self.focusedCategory
    self.selectedVehicle = top.vehicle
    self.isCategoryView = false
    self:reloadRows()
    self:focusNavigator()
end

---Goes up one level
function RMS_InGameMenuFrame:onClickBack()
    if self.isCategoryView then
        self.isUntrackedView = false
        self.focusedCategory = nil
    else
        self.focusedCategory = self.categoryName
    end

    self.isCategoryView = true
    self.categoryName = nil
    self.selectedVehicle = nil
    self.showMap = false
    self:reloadRows()
    self:focusNavigator()
end

function RMS_InGameMenuFrame:onClickView()
    self.isUntrackedView = true
    self.focusedCategory = nil
    self.selectedVehicle = nil
    self.showMap = false
    self:reloadRows()
    self:focusNavigator()
end

---
-- @param integer state selector state
function RMS_InGameMenuFrame:onSortChanged(state)
    self.sortMode = self.sortModes[state]
    self:reloadRows()
end

---
function RMS_InGameMenuFrame:onClickFleetSection()
    self:updateSubCategoryPages(SUB_CATEGORY.ACTIVE)
end

---
function RMS_InGameMenuFrame:onClickServiceSection()
    self:updateSubCategoryPages(SUB_CATEGORY.SERVICE)
end

---
function RMS_InGameMenuFrame:onClickSettingsSection()
    self:updateSubCategoryPages(SUB_CATEGORY.SETTINGS)
end

---Cycles forward through the three main tabs
function RMS_InGameMenuFrame:onPageNext()
    self:updateSubCategoryPages(self.subCategoryState % 3 + 1)
end

---Cycles backward through the three main tabs
function RMS_InGameMenuFrame:onPagePrevious()
    self:updateSubCategoryPages((self.subCategoryState + 1) % 3 + 1)
end

---Returns the row the right side shows
-- @return table? row list row, nil when the section is empty
function RMS_InGameMenuFrame:getDisplayedRow()
    if #self:getSectionRows() == 0 then
        return nil
    end

    if self.subCategoryState == SUB_CATEGORY.ACTIVE and self.isCategoryView then
        local category = self:getCategory(self.focusedCategory)
        return category ~= nil and category.top or self.topRow
    end

    for _, row in ipairs(self.machineRows) do
        if row.vehicle == self.selectedVehicle then
            return row
        end
    end
    return nil
end

---Shows the cards matching the displayed machine and fills them
function RMS_InGameMenuFrame:refreshDossier()
    local row = self:getDisplayedRow()

    self.identityCard:setVisible(row ~= nil)
    self.dossierColumn:setVisible(row ~= nil and row.isTracked)
    self.untrackedCard:setVisible(row ~= nil and not row.isTracked)
    self.emptyCard:setVisible(row == nil)
    self.cardRow:invalidateLayout()

    if row == nil then
        self.identityVehicle = nil
        self.emptyTitle:setText(g_i18n:getText(self:getEmptyTextKey()))
        return
    end

    self:updateIdentity(row)
    if row.isTracked then
        self:updateCondition(row)
        self:updateService(row)
    end
end

---Fills the identity card: what the machine is, its reliability and its figures
-- @param table row list row
function RMS_InGameMenuFrame:updateIdentity(row)
    local vehicle = row.vehicle
    local isLeased = vehicle.propertyState == VehiclePropertyState.LEASED

    if self.identityVehicle ~= vehicle then
        local storeItem = g_storeManager:getItemByXMLFilename(vehicle.configFileName)
        local brand = g_brandManager:getBrandByIndex(vehicle:getBrand())

        self.identityVehicle = vehicle
        self.showMap = false
        self.brandText:setText(brand ~= nil and brand.name ~= "NONE" and brand.title or "")
        self.modelText:setText(vehicle:getName())
        self.vehicleImage:setImageFilename(row.image)

        StoreItemUtil.loadSpecsFromXML(storeItem)
        local power = Motorized.getSpecValuePower(storeItem, vehicle)
        self.categoryText:setText(power ~= nil and string.format("%s · %s", row.categoryTitle, power) or row.categoryTitle)

        self.ratingTiles:setVisible(row.isTracked)
        self.reasonTile:setVisible(not row.isTracked)
        if row.isTracked then
            local reliability = RealisticMechanicalSystems.getBrandReliability(vehicle, nil)
            self.reliabilityValue:setText(RMS_Utils.formatReliability(reliability))
            self.serviceAccessValue:setText(RMS_Utils.formatServiceAccess(vehicle, storeItem))
        end
        self.odometerGlyph:setVisible(row.isTracked)
        self.conditionGlyph:setVisible(not row.isTracked)
    end

    self.vehicleImage:setVisible(not self.showMap)
    self.vehicleMap:setVisible(self.showMap)
    if self.showMap then
        local x, _, z = getWorldTranslation(vehicle.rootNode)
        self.vehicleMap:setCenterToWorldPosition(x, z)
        self.vehicleMap:setMapZoom(self.vehicleMapZoom)
        self.vehicleMap:setMapAlpha(1)
    end
    self:updateMapZoomControls()

    local thirdLabel, thirdValue = "rms_odometer_label", RMS_Utils.formatOdometerKilometers(RMS_Utils.getOdometerKilometers(vehicle))
    if not row.isTracked then
        local damage = vehicle.getDamageAmount ~= nil and vehicle:getDamageAmount() or 0
        thirdLabel, thirdValue = "rms_ws_label_condition", string.format("%.0f%%", math.clamp(1 - damage, 0, 1) * 100)
        self.reasonValue:setText(row.status)
    end

    local fourthLabel, fourthValue = "rms_ws_label_value", RMS_Utils.getResaleValue(vehicle)
    if isLeased then
        fourthLabel = "rms_ingame_menu_header_leasing_price"
        fourthValue = (vehicle.price or vehicle:getPrice())
            * (EconomyManager.DEFAULT_RUNNING_LEASING_FACTOR + EconomyManager.PER_DAY_LEASING_FACTOR)
    end

    local facts = {
        {"rms_ws_label_age", string.format("%d %s", vehicle.age, g_i18n:getText("rms_ws_age_unit"))},
        {"rms_ws_label_operating_hours", formatHours(row.hours)},
        {thirdLabel, thirdValue},
        {fourthLabel, fourthValue ~= nil and g_i18n:formatMoney(fourthValue, 0, true, false) or "-"}
    }
    for index, fact in ipairs(facts) do
        RMS_Utils.fitRowValue(self.factLabels[index], self.factPills[index], self.factValues[index],
            g_i18n:getText(fact[1]), fact[2])
    end
end

---Fills the condition card from the last inspection
-- @param table row list row
function RMS_InGameMenuFrame:updateCondition(row)
    local vehicle = row.vehicle
    local condition, isCompleteInspection = vehicle:getLastInspectedCondition()
    local report = RealisticMechanicalSystems.getReferenceReport(vehicle)
    local systems = report ~= nil and report.conditionData ~= nil and report.conditionData.systems or nil
    local isMeasured = systems ~= nil and RealisticMechanicalSystems.getIsCompleteReport(report)

    self.conditionValue:setText(row.condition)
    self.conditionValue:setTextColor(unpack(row.conditionColor))
    self.conditionOutdatedText:setVisible(row.isReportOutdated)
    self.conditionValueStack:invalidateLayout()
    self.conditionRingRatio = RMS_Utils.getConditionRingRatio(condition, isCompleteInspection)
    self.conditionRingColor = row.conditionColor

    self.systemsLayout:setVisible(systems ~= nil)
    self.systemsEmptyText:setVisible(systems == nil)

    if self.stateVehicle ~= vehicle then
        self.stateVehicle, self.openSystem = vehicle, nil
    end
    local footText = ""
    if systems ~= nil then
        self.stateRows, footText = RMS_Utils.getConditionRows(vehicle, report, systems, isMeasured, row.isReportOutdated, self.openSystem)
    else
        self.stateRows = {}
    end
    self.stateFootText:setText(footText)
    self.stateFootRule:setVisible(footText ~= "")
    RMS_Utils.reloadListTemplates(self.stateList)

    RMS_Utils.fitValuePill(self.lastCheckPill, self.lastCheckValue, "center", RMS_Utils.formatReportAge(row.reportHours))
    self.lastCheckValue:setTextColor(unpack(row.isReportOutdated and RMS_Breakdowns.COLORS.WARNING or RMS_Utils.COLOR.TEXT_DIM))
end

---Unfolds a system of the condition card on its parts, or folds it back
-- @param table _list list element
-- @param integer _section section index
-- @param integer index row index
function RMS_InGameMenuFrame:onClickStateRow(_list, _section, index)
    local row = self.stateRows[index]
    if row == nil or row.kind ~= "system" or not row.canOpen then
        return
    end
    self.openSystem = not row.isOpen and row.systemKey or nil
    self:refreshDossier()
    for rowIndex, stateRow in ipairs(self.stateRows) do
        if stateRow.kind == "system" and stateRow.systemKey == row.systemKey then
            self.stateList:setSelectedItem(1, rowIndex, false, true)
        end
    end
end

---Fills the banner and the second card: next maintenance or running work
-- @param table row list row
function RMS_InGameMenuFrame:updateService(row)
    local vehicle = row.vehicle
    local spec = vehicle.spec_RealisticMechanicalSystems
    local overhaulCount = string.format("%d", vehicle:getOverhaulPerformedCount() or 0)
    local totalCost = g_i18n:formatMoney(getTotalCost(vehicle), 0, true, false)
    local color = getUrgencyColor(row.urgency)
    local rows, foot

    local breakdownCount = 0
    for _, breakdown in pairs(vehicle:getActiveBreakdowns()) do
        if breakdown.isVisible then
            breakdownCount = breakdownCount + 1
        end
    end
    local breakdowns = {"rms_ws_section_breakdowns", tostring(breakdownCount), breakdownCount > 0 and RMS_Utils.COLOR.ALERT or nil}

    self.bannerIcons[1]:setVisible(not row.isServicing)
    self.bannerIcons[2]:setVisible(row.isServicing)
    self.serviceTrackColor = nil

    if row.isServicing then
        local duration = RMS_Utils.formatDuration(vehicle:getServiceDuration())
        local procedure = RMS_Utils.formatServiceState(spec.currentState)
        local isKnownWorkshop = RMS_Utils.getKeyByValue(RealisticMechanicalSystems.WORKSHOP, spec.workshopType) ~= nil
        local totalTime = spec.pendingProgressTotalTime or 0
        local progress = totalTime > 0 and math.clamp((spec.pendingProgressElapsedTime or 0) / totalTime, 0, 1) or 0

        self.bannerTitle:setText(procedure)
        self.bannerDetail:setText(isKnownWorkshop and string.format("%s · %s", g_i18n:getText(spec.workshopType), duration) or duration)
        self.bannerDetail:setTextColor(unpack(RMS_Utils.COLOR.TEXT_DIM))
        self.serviceCardTitle:setText(g_i18n:getText("rms_ingame_menu_header_procedure"))
        self.serviceValue:setText(string.format("%d%%", math.floor(progress * 100)))
        self.serviceRingRatio = progress
        rows = {
            {"rms_ws_label_committed_cost", g_i18n:formatMoney(getCommittedCost(vehicle), 0, true, false)},
            breakdowns,
            {"rms_ws_label_overhaul_count", overhaulCount},
            {"rms_ingame_menu_header_cost", totalCost}
        }
        foot = {"rms_ws_label_finish_time", RMS_Utils.formatFinishTime(vehicle:getServiceFinishTime())}
    else
        self.bannerTitle:setText(RMS_Utils.formatMaintenanceLevel(vehicle, vehicle:getDueMaintenanceType()))
        self.bannerDetail:setText(RMS_Utils.formatServiceReason(vehicle, row.schedule) .. " · " .. row.status)
        self.bannerDetail:setTextColor(unpack(color))
        self.serviceCardTitle:setText(g_i18n:getText("rms_fleet_next_service"))
        self.serviceValue:setText(row.schedule ~= nil and row.schedule.calendarLeading
            and RMS_Utils.formatMonths(row.schedule.remainingMonths)
            or formatHours(math.max(row.remaining, 0)))
        self.serviceRingRatio = math.clamp(1 - (row.schedule ~= nil and row.schedule.progress or 0), 0, 1)
        self.serviceTrackColor = row.urgency == URGENCY.OVERDUE and color or nil
        rows = {
            breakdowns,
            {"rms_ws_label_overhaul_count", overhaulCount},
            {"rms_ingame_menu_header_cost", totalCost},
            {"rms_ingame_menu_header_interval", RMS_Utils.formatServiceDeadline(row.schedule, true)}
        }
        foot = {"rms_ws_label_last_maintenance", RMS_Utils.formatTimeAgo(vehicle:getLastMaintenanceDate())}
    end

    self.serviceRingColor = color
    self.serviceValue:setTextColor(unpack(color))
    self.bannerAccent:setImageColor(nil, unpack(color))
    for _, icon in ipairs(self.bannerIcons) do
        icon:setImageColor(nil, unpack(color))
    end

    for index, entry in ipairs(rows) do
        RMS_Utils.fitRowValue(self.serviceLabels[index], self.servicePills[index], self.serviceValues[index],
            g_i18n:getText(entry[1]), entry[2])
        self.serviceValues[index]:setTextColor(unpack(entry[3] or self.pillValueColor))
    end
    self.serviceFootLabel:setText(g_i18n:getText(foot[1]))
    RMS_Utils.fitValuePill(self.serviceFootPill, self.serviceFootValue, "center", foot[2])
end

local function drawRing(area, ratio, arcColor, trackColor)
    local height = area.absSize[2]
    RMS_ProgressRing.render(area.absPosition[1] + area.absSize[1] * 0.5, area.absPosition[2] + height * 0.5,
        height * (g_screenHeight / g_screenWidth), height, ratio, arcColor or RMS_Utils.COLOR.HIGHLIGHT, trackColor or RMS_Utils.COLOR.RING_TRACK)
end

---
function RMS_InGameMenuFrame:onDrawConditionRing()
    drawRing(self.conditionRingArea, self.conditionRingRatio, self.conditionRingColor)
end

---
function RMS_InGameMenuFrame:onDrawServiceRing()
    drawRing(self.serviceRingArea, self.serviceRingRatio, self.serviceRingColor, self.serviceTrackColor)
end


---Swaps the picture of the machine for the map centered on it, and back
function RMS_InGameMenuFrame:onClickLocation()
    self.showMap = not self.showMap
    self.vehicleMapZoom = RMS_InGameMenuFrame.MAP_ZOOM_DEFAULT
    self:refreshDossier()
    self:updateFocusLinks()
end

---Keeps the two preview controls in sync with the available zoom range
function RMS_InGameMenuFrame:updateMapZoomControls()
    self.mapZoomInButton:setDisabled(self.vehicleMapZoom >= RMS_InGameMenuFrame.MAP_ZOOM_MAX)
    self.mapZoomOutButton:setDisabled(self.vehicleMapZoom <= RMS_InGameMenuFrame.MAP_ZOOM_MIN)
end

---Zooms the visible vehicle preview
-- @param integer direction positive to zoom in, negative to zoom out
function RMS_InGameMenuFrame:changeMapZoom(direction)
    self.vehicleMapZoom = math.clamp(self.vehicleMapZoom * RMS_InGameMenuFrame.MAP_ZOOM_STEP ^ direction,
        RMS_InGameMenuFrame.MAP_ZOOM_MIN, RMS_InGameMenuFrame.MAP_ZOOM_MAX)
    self.vehicleMap:setMapZoom(self.vehicleMapZoom)
    self:updateMapZoomControls()
end

---
function RMS_InGameMenuFrame:onClickMapZoomIn()
    self:changeMapZoom(1)
end

---
function RMS_InGameMenuFrame:onClickMapZoomOut()
    self:changeMapZoom(-1)
end

---Uses the wheel only over the visible preview
function RMS_InGameMenuFrame:mouseEvent(posX, posY, isDown, isUp, button, eventUsed)
    local map = self.vehicleMap
    if not eventUsed and isDown and self.isFrameOpen and map:getIsVisible()
        and GuiUtils.checkOverlayOverlap(posX, posY, map.absPosition[1], map.absPosition[2], map.absSize[1], map.absSize[2]) then
        if Input.isMouseButtonPressed(Input.MOUSE_BUTTON_WHEEL_UP) then
            self:changeMapZoom(1)
            return true
        elseif Input.isMouseButtonPressed(Input.MOUSE_BUTTON_WHEEL_DOWN) then
            self:changeMapZoom(-1)
            return true
        end
    end

    return RMS_InGameMenuFrame:superClass().mouseEvent(self, posX, posY, isDown, isUp, button, eventUsed)
end

---Returns the machine the footer actions apply to
-- @return table? vehicle vehicle, nil while the player browses categories
function RMS_InGameMenuFrame:getSelectedVehicle()
    if self.subCategoryState == SUB_CATEGORY.SETTINGS or (self.subCategoryState == SUB_CATEGORY.ACTIVE and self.isCategoryView) then
        return nil
    end

    local row = self:getDisplayedRow()
    return row ~= nil and row.vehicle or nil
end

function RMS_InGameMenuFrame:updateActionButtons()
    local buttons = {self:getIsNestedView() and self.levelUpButtonInfo or self.backButtonInfo,
        self.prevPageButtonInfo, self.nextPageButtonInfo}
    local vehicle = self:getSelectedVehicle()

    if vehicle ~= nil then
        local spec = vehicle.spec_RealisticMechanicalSystems
        local isTracked = spec ~= nil and not spec.isExcludedVehicle
        local isServicing = isTracked and vehicle:isUnderService()

        if not isServicing then
            self.enterVehicleButtonInfo.disabled = not (vehicle.getIsEnterableFromMenu ~= nil and vehicle:getIsEnterableFromMenu())
            self.sellVehicleButtonInfo.text = g_i18n:getText(vehicle.propertyState == VehiclePropertyState.LEASED and "ui_returnThis" or "ui_sellItem")
            table.insert(buttons, self.enterVehicleButtonInfo)
            table.insert(buttons, self.sellVehicleButtonInfo)
        end
        if isTracked then
            table.insert(buttons, self.maintenanceLogButtonInfo)
        end
        if spec ~= nil then
            local isExcluding = not spec.isExcludedVehicle
            self.exclusionButtonInfo.text = g_i18n:getText(isExcluding and "rms_ingame_menu_exclude" or "rms_ingame_menu_include")
            self.exclusionButtonInfo.disabled = not RealisticMechanicalSystems.getCanSetUserExclusion(vehicle, isExcluding)
            table.insert(buttons, self.exclusionButtonInfo)
        end
    end

    self:setMenuButtonInfo(buttons)
    self:setMenuButtonInfoDirty()
end

---Includes the selected machine in RMS or excludes it, through the server
function RMS_InGameMenuFrame:onToggleExclusion()
    local vehicle = self:getSelectedVehicle()
    local spec = vehicle ~= nil and vehicle.spec_RealisticMechanicalSystems or nil
    if spec == nil or not RealisticMechanicalSystems.getCanSetUserExclusion(vehicle, not spec.isExcludedVehicle) then
        return
    end

    RMS_VehicleExclusionEvent.request(vehicle, not spec.isExcludedVehicle)
    self:reloadRows()
end

---Closes the menu and enters the selected vehicle
function RMS_InGameMenuFrame:onTryEnterVehicle()
    local vehicle = self:getSelectedVehicle()
    if vehicle ~= nil and vehicle.getIsEnterableFromMenu ~= nil and vehicle:getIsEnterableFromMenu() then
        g_gui:showGui("")
        g_localPlayer:requestToEnterVehicle(vehicle)
    end
end

---Returns a leased RMS vehicle through the mod dialog, sells anything else
function RMS_InGameMenuFrame:onSellSelectedVehicle()
    local vehicle = self:getSelectedVehicle()
    if vehicle == nil then
        return
    end

    local storeItem = g_storeManager:getItemByXMLFilename(vehicle.configFileName)
    local spec = vehicle.spec_RealisticMechanicalSystems
    local isTracked = spec ~= nil and not spec.isExcludedVehicle
    if isTracked and vehicle:isUnderService() then
        return
    end

    if isTracked and vehicle.propertyState == VehiclePropertyState.LEASED then
        RMS_SellItemDialog.show(vehicle, self.onRMSSellDialogCallback, self, {vehicle})
        return
    end

    g_shopController:sell(storeItem, vehicle)
end

---Sends the vehicle return once the player confirmed it
-- @param boolean yes true when the player confirmed
-- @param table vehicle vehicle the dialog was opened for
function RMS_InGameMenuFrame:onRMSSellDialogCallback(yes, vehicle)
    if not yes or vehicle.isDeleted or vehicle.propertyState ~= VehiclePropertyState.LEASED or vehicle:isUnderService() then
        return
    end

    g_client:getServerConnection():sendEvent(SellVehicleEvent.new(vehicle, 1, true))
end

---Opens the maintenance log of the displayed machine
function RMS_InGameMenuFrame:onShowMaintenanceLog()
    local row = self:getDisplayedRow()
    if row == nil or not row.isTracked then
        return
    end

    if #row.vehicle.spec_RealisticMechanicalSystems.maintenanceLog > 1 then
        RMS_MaintenanceLogDialog.show(row.vehicle)
    else
        InfoDialog.show(g_i18n:getText("rms_ws_no_log_empty_message"))
    end
end
