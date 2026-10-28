-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---RMS settings page.
RMS_SettingsPage = {}
RMS_SettingsPage.name = g_currentModName
RMS_SettingsPage.modDirectory = g_currentModDirectory

RMS_SettingsPage.steps = {}

---Compares two setting values, numbers within 0.0001 counting as equal
local function valuesDiffer(a, b)
    if type(a) == "number" or type(b) == "number" then
        return math.abs((tonumber(a) or 0) - (tonumber(b) or 0)) > 0.0001
    end

    return a ~= b
end

---Snapshots the live configuration into the flat table the page edits
local function buildPendingConfigFromRMSConfig()
    return {
        tutorialMode = RMS_Config.TUTORIAL_MODE,

        baseServiceWear = RMS_Config.CORE.BASE_SERVICE_WEAR,
        baseSystemsWear = RMS_Config.CORE.BASE_SYSTEMS_WEAR,
        exhaustSmokeEnabled = RMS_Config.EXHAUST.ENABLED,
        enableWarningMessages = RMS_Config.CORE.ENABLE_WARNING_MESSAGES,

        instantInspection = RMS_Config.MAINTENANCE.INSTANT_INSPECTION,
        instantMaintenanceRepair = RMS_Config.MAINTENANCE.INSTANT_MAINTENANCE_REPAIR,
        instantBodywork = RMS_Config.MAINTENANCE.INSTANT_BODYWORK,
        instantOverhaul = RMS_Config.MAINTENANCE.INSTANT_OVERHAUL,

        dealerAlwaysAvailable = RMS_Config.WORKSHOP.DEALER_ALWAYS_AVAILABLE,
        mobileAlwaysAvailable = RMS_Config.WORKSHOP.MOBILE_ALWAYS_AVAILABLE,
        ownAlwaysAvailable = RMS_Config.WORKSHOP.OWN_ALWAYS_AVAILABLE,
        mobileWorkshopRestrictionsEnabled = RMS_Config.WORKSHOP.MOBILE_WORKSHOP_RESTRICTIONS_ENABLED,
        openHour = RMS_Config.WORKSHOP.OPEN_HOUR,
        closeHour = RMS_Config.WORKSHOP.CLOSE_HOUR,

        drivetrainEnabled = RMS_Config.DRIVETRAIN.ENABLED,
        drivetrainAllowAutoMode = RMS_Config.DRIVETRAIN.ALLOW_AUTO_MODE,
        drivetrainParkBrakeEnabled = RMS_Config.DRIVETRAIN.PARKBRAKE_ENABLED,

        debugMode = RMS_DebugWindow.getIsOpen()
    }
end

---Returns the pending configuration, snapshotting the live one on first use
local function getPendingConfig()
    if RMS_SettingsPage.pendingConfig == nil then
        RMS_SettingsPage.pendingConfig = buildPendingConfigFromRMSConfig()
    end

    return RMS_SettingsPage.pendingConfig
end

---Returns a GUI profile by name
local function getSettingsProfile(defaultProfileName)
    return g_gui:getProfile(defaultProfileName)
end

---Swaps the vanilla button background of a settings row for the mod one
local function applyButtonBackgroundProfile(button)
    if button == nil or button.elements == nil then
        return
    end

    for _, child in pairs(button.elements) do
        if child ~= nil and child.applyProfile ~= nil and child.profile == "fs25_settingsButtonBg" then
            child:applyProfile("rms_settingsButtonBg")
            return
        end
    end
end

---Swaps the vanilla multi text option background for the mod one
local function applyMultiTextOptionBackgroundProfile(option)
    if option == nil or option.elements == nil then
        return
    end

    for _, child in pairs(option.elements) do
        if child ~= nil and child.applyProfile ~= nil and child.profile == "fs25_multiTextOptionBg" then
            child:applyProfile("rms_settingsMultiTextOptionBg")
            return
        end
    end
end

---Adds a padlock to a settings row, shown while the option itself is disabled
local function addDisabledLockToSettingsRow(rowElement, optionElement, tooltip)
    if rowElement == nil or optionElement == nil then
        return nil
    end

    local lockButton = ButtonElement.new()
    lockButton.name = "iconDisabled"
    lockButton:loadProfile(getSettingsProfile("fs25_settingsMultiTextOptionLocked"), true)
    lockButton.target = RMS_SettingsPage
    lockButton:setCallback("onClickCallback", "onClickSettingsLockedIcon")
    lockButton:setCallback("onFocusCallback", "onFocusSettingsLockedIcon")

    local lockTooltip = TextElement.new()
    lockTooltip:loadProfile(getSettingsProfile("fs25_multiTextOptionTooltip"), true)
    lockTooltip:setText(tooltip)
    lockTooltip:setPosition(unpack(GuiUtils.getNormalizedScreenValues("940px 0px", lockTooltip.position)))
    lockButton:addElement(lockTooltip)

    rowElement:addElement(lockButton)
    lockButton:onGuiSetupFinished()
    lockTooltip:onGuiSetupFinished()
    lockButton:setDisabled(true)

    local oldSetDisabled = optionElement.setDisabled
    optionElement.setDisabled = function(element, disabled, ...)
        oldSetDisabled(element, disabled, ...)
        lockButton:setDisabled(not disabled)
    end


    return lockButton
end

---Paints a settings row with the alternating background
local function applySettingsRowColor(page, rowElement)
    if page == nil or not page.rmsUseFleetMenuStyle or rowElement == nil or rowElement.setImageColor == nil then
        return
    end

    local settingsFrame = _G.InGameMenuSettingsFrame
    if settingsFrame ~= nil and settingsFrame.COLOR_ALTERNATING ~= nil then
        rowElement:setImageColor(nil, table.unpack(settingsFrame.COLOR_ALTERNATING[page.rmsSettingsRowIsEven]))
    end

    page.rmsSettingsRowIsEven = not page.rmsSettingsRowIsEven
end

---Finds a vanilla settings row holding a button, as a template
local function getVanillaSettingsButtonTemplate()
    local settingsPage = g_inGameMenu.pageSettings
    local scrollPanel = settingsPage ~= nil and settingsPage.gameSettingsLayout or nil

    if scrollPanel == nil or scrollPanel.elements == nil then
        return nil
    end

    for _, element in pairs(scrollPanel.elements) do
        if element.typeName == "Bitmap"
            and element.elements ~= nil
            and element.elements[1] ~= nil
            and element.elements[1].typeName == "Button" then
            return element
        end
    end

    return nil
end

---
function RMS_SettingsPage:onClickSettingsLockedIcon()
end

---Scrolls the settings list so that the focused padlock stays visible
-- @param table icon focused padlock element
function RMS_SettingsPage:onFocusSettingsLockedIcon(icon)
    local page = RMS_SettingsPage.embeddedPage
    if page ~= nil and page.settingsLayout ~= nil and page.settingsLayout.scrollToMakeElementVisible ~= nil then
        page.settingsLayout:scrollToMakeElementVisible(icon)
    end
end

---Returns the embedded page only while the settings tab is the active one
local function getCurrentSettingsPage()
    local embeddedPage = RMS_SettingsPage.embeddedPage
    if embeddedPage ~= nil
        and embeddedPage.getCurrentSubCategory ~= nil
        and embeddedPage:getCurrentSubCategory() == RMS_InGameMenuFrame.SUB_CATEGORY.SETTINGS then
        return embeddedPage
    end

    return nil
end

---Tells whether the mission runs in multiplayer
local function isCurrentMissionMultiplayer()
    return g_currentMission.missionDynamicInfo.isMultiplayer == true
end

---Tells whether the player may edit the settings
local function canChangeRMSSettings()
    return g_currentMission:getIsClient()
        and (not isCurrentMissionMultiplayer() or g_currentMission:getIsServer() or g_currentMission.isMasterUser)
end

---Refreshes the settings controls when the settings tab is open
local function refreshCurrentSettingsPage()
    local currentPage = getCurrentSettingsPage()
    if currentPage ~= nil then
        RMS_SettingsPage:updateRMSSettings(currentPage)
    end
end

---Applies changed instant service settings to running services
-- @param table? oldConfig configuration before the change
-- @param table? newConfig configuration after the change
function RMS_SettingsPage.applyPendingConfigSideEffects(oldConfig, newConfig)
    if not g_currentMission:getIsServer() then
        return
    end

    if oldConfig == nil or newConfig == nil or RMS_Main.vehicles == nil then
        return
    end

    local instantInspectionEnabled = (oldConfig.instantInspection ~= true and newConfig.instantInspection == true)
    local instantMaintenanceRepairEnabled = (oldConfig.instantMaintenanceRepair ~= true and newConfig.instantMaintenanceRepair == true)
    local instantBodyworkEnabled = (oldConfig.instantBodywork ~= true and newConfig.instantBodywork == true)
    local instantOverhaulEnabled = (oldConfig.instantOverhaul ~= true and newConfig.instantOverhaul == true)

    if not instantInspectionEnabled and not instantMaintenanceRepairEnabled
        and not instantBodyworkEnabled and not instantOverhaulEnabled then
        return
    end

    local states = RealisticMechanicalSystems.STATUS

    for _, vehicle in pairs(RMS_Main.vehicles) do
        if vehicle ~= nil and vehicle.spec_RealisticMechanicalSystems ~= nil and not vehicle.spec_RealisticMechanicalSystems.isExcludedVehicle then
            local spec = vehicle.spec_RealisticMechanicalSystems
            local currentState = spec.currentState

            if (instantInspectionEnabled and currentState == states.INSPECTION)
                or (instantMaintenanceRepairEnabled and (currentState == states.MAINTENANCE or currentState == states.REPAIR))
                or (instantBodyworkEnabled and currentState == states.BODYWORK)
                or (instantOverhaulEnabled and currentState == states.OVERHAUL) then
                if RealisticMechanicalSystems.forceFinishService(vehicle) then
                    RealisticMechanicalSystems.raiseServiceLifecycleDirtyFlags(vehicle)
                end
            end
        end
    end
end

---Writes the pending configuration into RMS_Config and syncs it
-- @param table? current configuration currently applied
-- @param table? pending configuration edited on the page
function RMS_SettingsPage.commitPendingConfig(current, pending)
    if pending == nil or current == nil then
        return
    end

    local workshopChanged =
        valuesDiffer(pending.dealerAlwaysAvailable, current.dealerAlwaysAvailable) or
        valuesDiffer(pending.mobileAlwaysAvailable, current.mobileAlwaysAvailable) or
        valuesDiffer(pending.ownAlwaysAvailable, current.ownAlwaysAvailable) or
        valuesDiffer(pending.mobileWorkshopRestrictionsEnabled, current.mobileWorkshopRestrictionsEnabled) or
        valuesDiffer(pending.openHour, current.openHour) or
        valuesDiffer(pending.closeHour, current.closeHour)

    local tutorialModeChanged = valuesDiffer(pending.tutorialMode, current.tutorialMode)
    RMS_Config.TUTORIAL_MODE = pending.tutorialMode
    if tutorialModeChanged then
        RMS_Config.syncTutorialState()
    end

    RMS_Config.CORE.BASE_SERVICE_WEAR = pending.baseServiceWear
    RMS_Config.CORE.BASE_SYSTEMS_WEAR = pending.baseSystemsWear
    RMS_Config.CORE.ENABLE_WARNING_MESSAGES = pending.enableWarningMessages

    RMS_Config.EXHAUST.ENABLED = pending.exhaustSmokeEnabled

    RMS_Config.MAINTENANCE.INSTANT_INSPECTION = pending.instantInspection
    RMS_Config.MAINTENANCE.INSTANT_MAINTENANCE_REPAIR = pending.instantMaintenanceRepair
    RMS_Config.MAINTENANCE.INSTANT_BODYWORK = pending.instantBodywork
    RMS_Config.MAINTENANCE.INSTANT_OVERHAUL = pending.instantOverhaul

    RMS_Config.WORKSHOP.DEALER_ALWAYS_AVAILABLE = pending.dealerAlwaysAvailable
    RMS_Config.WORKSHOP.MOBILE_ALWAYS_AVAILABLE = pending.mobileAlwaysAvailable
    RMS_Config.WORKSHOP.OWN_ALWAYS_AVAILABLE = pending.ownAlwaysAvailable
    RMS_Config.WORKSHOP.MOBILE_WORKSHOP_RESTRICTIONS_ENABLED = pending.mobileWorkshopRestrictionsEnabled
    RMS_Config.WORKSHOP.OPEN_HOUR = pending.openHour
    RMS_Config.WORKSHOP.CLOSE_HOUR = pending.closeHour

    RMS_Config.DRIVETRAIN.ENABLED = pending.drivetrainEnabled
    RMS_Config.DRIVETRAIN.ALLOW_AUTO_MODE = pending.drivetrainAllowAutoMode
    RMS_Config.DRIVETRAIN.PARKBRAKE_ENABLED = pending.drivetrainParkBrakeEnabled

    if valuesDiffer(pending.debugMode, current.debugMode) then
        RMS_DebugWindow.isOpen = pending.debugMode
        RMS_Config.DEBUG = pending.debugMode
    end

    RMS_SettingsPage.applyPendingConfigSideEffects(current, pending)
    RMS_Drivetrain.refreshAllParkBrakePedals()
    RMS_Drivetrain.claimFromOtherMod()

    if workshopChanged then
        RMS_Main:forceWorkshopUpdate(true)
    end

    RMS_SettingsSyncEvent.share()
end

---Starts an editing session on a fresh snapshot of the live configuration
function RMS_SettingsPage.beginSettingsSession()
    RMS_SettingsPage.pendingConfig = buildPendingConfigFromRMSConfig()
    RMS_SettingsPage.rmsHasPendingSettingsChange = false
end

---Builds every settings control on the page, once per page
-- @param table? targetPage page hosting the controls
function RMS_SettingsPage:initializeSettingsPageControls(targetPage)
    local page = targetPage
    if page == nil or page.rmsInitSettingsMenuDone then
        return
    end

    ---Deletes a settings element by id
    local function deleteElementById(elementId)
        local root = page.settingsPage or page.settingsLayout or page
        local element = root ~= nil and root:getDescendantById(elementId) or nil
        if element ~= nil then
            element:delete()
        end
    end

    RMS_SettingsPage:generateAllSteps()
    page.rmsSettingsRowIsEven = false

    -- General
    page.rmsTutorialMode = RMS_SettingsPage:addBinaryOption(
        page,
        "onTutorialModeChanged",
        g_i18n:getText("rms_tutorialMode_label"),
        g_i18n:getText("rms_tutorialMode_tooltip")
    )
    page.rmsTutorialResetTips = RMS_SettingsPage:addButtonOption(
        page,
        "onResetTutorialTipsClicked",
        g_i18n:getText("rms_tutorialResetTips_label"),
        g_i18n:getText("rms_tutorialResetTips_text"),
        g_i18n:getText("rms_tutorialResetTips_tooltip")
    )
    page.rmsWarningMessages = RMS_SettingsPage:addBinaryOption(
        page,
        "onWarningMessagesChanged",
        g_i18n:getText("rms_warningMessages_label"),
        g_i18n:getText("rms_warningMessages_tooltip")
    )
    page.rmsDebugMode = RMS_SettingsPage:addBinaryOption(
        page,
        "onDebugModeChanged",
        g_i18n:getText("rms_debugMode_label"),
        string.format(g_i18n:getText("rms_debugMode_tooltip"), RMS_Utils.getPrimaryKeyboardInputText("RMS_TOGGLE_DEBUG_WINDOW", "Alt Gr + F5"))
    )

    RMS_SettingsPage:addSectionHeader(page, g_i18n:getText("rms_settings_section_service_wear"))

    page.rmsServiceWear = RMS_SettingsPage:addMultiTextOption(
        page, "onServiceWearChanged",
        RMS_SettingsPage.steps.serviceWear.texts,
        g_i18n:getText("rms_serviceInterval_label"),
        g_i18n:getText("rms_serviceInterval_tooltip")
    )
    page.rmsConditionWear = RMS_SettingsPage:addMultiTextOption(
        page, "onConditionWearChanged",
        RMS_SettingsPage.steps.conditionWear.texts,
        g_i18n:getText("rms_vehicleLifespan_label"),
        g_i18n:getText("rms_vehicleLifespan_tooltip")
    )
    page.rmsExhaustSmokeEnabled = RMS_SettingsPage:addBinaryOption(
        page,
        "onExhaustSmokeEnabledChanged",
        g_i18n:getText("rms_exhaustSmokeEnabled_label"),
        g_i18n:getText("rms_exhaustSmokeEnabled_tooltip")
    )

    RMS_SettingsPage:addSectionHeader(page, g_i18n:getText("rms_ws_header_title"))

    page.rmsInstantInspection = RMS_SettingsPage:addBinaryOption(
        page,
        "onInstantInspectionChanged",
        g_i18n:getText("rms_instantInspection_label"),
        g_i18n:getText("rms_instantInspection_tooltip")
    )

    page.rmsInstantMaintenanceRepair = RMS_SettingsPage:addBinaryOption(
        page,
        "onInstantMaintenanceRepairChanged",
        g_i18n:getText("rms_instantMaintenanceRepair_label"),
        g_i18n:getText("rms_instantMaintenanceRepair_tooltip")
    )

    page.rmsInstantBodywork = RMS_SettingsPage:addBinaryOption(
        page,
        "onInstantBodyworkChanged",
        g_i18n:getText("rms_instantBodywork_label"),
        g_i18n:getText("rms_instantBodywork_tooltip")
    )

    page.rmsInstantOverhaul = RMS_SettingsPage:addBinaryOption(
        page,
        "onInstantOverhaulChanged",
        g_i18n:getText("rms_instantOverhaul_label"),
        g_i18n:getText("rms_instantOverhaul_tooltip")
    )

    page.rmsMobileWorkshopRestrictions = RMS_SettingsPage:addBinaryOption(
        page,
        "onMobileWorkshopRestrictionsChanged",
        g_i18n:getText("rms_mobileWorkshopRestrictions_label"),
        g_i18n:getText("rms_mobileWorkshopRestrictions_tooltip")
    )

    page.rmsDealerWorkshopAvailable = RMS_SettingsPage:addBinaryOption(
        page,
        "onDealerWorkshopAvailableChanged",
        g_i18n:getText("rms_dealerWorkshopAvailable_label"),
        g_i18n:getText("rms_dealerWorkshopAvailable_tooltip")
    )

    page.rmsMobileWorkshopAvailable = RMS_SettingsPage:addBinaryOption(
        page,
        "onMobileWorkshopAvailableChanged",
        g_i18n:getText("rms_mobileWorkshopAvailable_label"),
        g_i18n:getText("rms_mobileWorkshopAvailable_tooltip")
    )

    page.rmsOwnWorkshopAvailable = RMS_SettingsPage:addBinaryOption(
        page,
        "onOwnWorkshopAvailableChanged",
        g_i18n:getText("rms_ownWorkshopAvailable_label"),
        g_i18n:getText("rms_ownWorkshopAvailable_tooltip")
    )

    -- Workshop Open Hour
    page.rmsWorkshopOpenHour = RMS_SettingsPage:addMultiTextOption(
        page,
        "onWorkshopOpenHourChanged",
        RMS_SettingsPage.steps.hours.texts,
        g_i18n:getText("rms_workshopOpenHour_label"),
        g_i18n:getText("rms_workshopOpenHour_tooltip")
    )

    -- Workshop Close Hour
    page.rmsWorkshopCloseHour = RMS_SettingsPage:addMultiTextOption(
        page,
        "onWorkshopCloseHourChanged",
        RMS_SettingsPage.steps.hours.texts,
        g_i18n:getText("rms_workshopCloseHour_label"),
        g_i18n:getText("rms_workshopCloseHour_tooltip")
    )

    RMS_SettingsPage:addSectionHeader(page, g_i18n:getText("rms_settings_section_drivetrain"))

    page.rmsDrivetrainEnabled = RMS_SettingsPage:addBinaryOption(
        page,
        "onDrivetrainEnabledChanged",
        g_i18n:getText("rms_drivetrainEnabled_label"),
        g_i18n:getText("rms_drivetrainEnabled_tooltip")
    )
    page.rmsDrivetrainAllowAutoMode = RMS_SettingsPage:addBinaryOption(
        page,
        "onDrivetrainAllowAutoModeChanged",
        g_i18n:getText("rms_drivetrainAllowAutoMode_label"),
        g_i18n:getText("rms_drivetrainAllowAutoMode_tooltip")
    )
    page.rmsDrivetrainParkBrakeEnabled = RMS_SettingsPage:addBinaryOption(
        page,
        "onDrivetrainParkBrakeEnabledChanged",
        g_i18n:getText("rms_drivetrainParkBrakeEnabled_label"),
        g_i18n:getText("rms_drivetrainParkBrakeEnabled_tooltip")
    )

    deleteElementById("subTitlePrefab")
    deleteElementById("binaryPrefab")
    deleteElementById("multiPrefab")

    page.settingsLayout:invalidateLayout()
    page.rmsInitSettingsMenuDone = true
end

---Takes over the settings tab of the fleet menu
-- @param table? page page hosting the settings tab
function RMS_SettingsPage:activateEmbeddedSettingsPage(page)
    if page == nil then
        return
    end

    self.embeddedPage = page
    page.rmsUseFleetMenuStyle = true

    if self.pendingConfig == nil then
        RMS_SettingsPage.beginSettingsSession()
    end

    self:updateRMSPageVisibility(page)

    self:initializeSettingsPageControls(page)
    if page.settingsSlider ~= nil and page.settingsSlider.setDataElement ~= nil then
        page.settingsSlider:setDataElement(page.settingsLayout)
    end
    RMS_SettingsPage.registerEmbeddedFocus(page)
    self:updateRMSPageVisibility(page)
    self:updateRMSSettings(page)
end

---Registers the settings layout with the focus manager
-- @param table? page page hosting the settings tab
function RMS_SettingsPage.registerEmbeddedFocus(page)
    if page == nil
        or page.rmsSettingsFocusLoaded
        or page.settingsLayout == nil then
        return
    end

    local currentGui = FocusManager.currentGui
    if page.name ~= nil then
        FocusManager:setGui(page.name)
    end

    FocusManager:removeElement(page.settingsLayout)
    FocusManager:loadElementFromCustomValues(page.settingsLayout)

    if currentGui ~= nil then
        FocusManager:setGui(currentGui)
    end

    page.rmsSettingsFocusLoaded = true
end

---Shows the settings layout only once its controls have been built
-- @param table? targetPage page hosting the settings tab
function RMS_SettingsPage:updateRMSPageVisibility(targetPage)
    local page = targetPage
    if page == nil then
        return
    end

    if page.noPermissionText ~= nil then
        page.noPermissionText:setVisible(false)
    end
    if page.settingsLayout ~= nil then
        page.settingsLayout:setVisible(page.rmsInitSettingsMenuDone == true)
    end
    if page.settingsSliderBox ~= nil then
        page.settingsSliderBox:setVisible(page.rmsInitSettingsMenuDone == true)
    end
    if page.settingsTooltipSeparator ~= nil then
        page.settingsTooltipSeparator:setVisible(page.rmsInitSettingsMenuDone == true)
    end
end

function RMS_SettingsPage:onFrameClose()
    if not RMS_SettingsPage.rmsHasPendingSettingsChange then
        RMS_SettingsPage.pendingConfig = nil
        return
    end

    local pending = RMS_SettingsPage.pendingConfig
    local current = buildPendingConfigFromRMSConfig()

    RMS_SettingsPage.pendingConfig = nil
    RMS_SettingsPage.rmsHasPendingSettingsChange = false

    if pending == nil then
        return
    end

    local anyChanged = false
    for key, oldValue in pairs(current) do
        if valuesDiffer(pending[key], oldValue) then
            anyChanged = true
            break
        end
    end

    if not anyChanged then
        return
    end

    RMS_SettingsPage.commitPendingConfig(current, pending)
end


---Writes the pending configuration back into every control of the page
-- @param table? currentPage page hosting the settings tab
function RMS_SettingsPage:updateRMSSettings(currentPage)
    if currentPage == nil or not currentPage.rmsInitSettingsMenuDone then return end

    local steps = RMS_SettingsPage.steps
    local pending = RMS_SettingsPage.pendingConfig or buildPendingConfigFromRMSConfig()
    local tutorialOption = currentPage.rmsTutorialMode

    ---Selects the step whose value is closest to the target
    local function setIndex(element, valueList, targetValue)
        local bestIndex = 1
        local bestDiff = math.huge

        for i, v in ipairs(valueList) do
            local diff = math.abs((tonumber(v) or 0) - (tonumber(targetValue) or 0))
            if diff < bestDiff then
                bestDiff = diff
                bestIndex = i
            end
        end

        element:setState(bestIndex)
    end

    setIndex(currentPage.rmsServiceWear, steps.serviceWear.values, pending.baseServiceWear)
    setIndex(currentPage.rmsConditionWear, steps.conditionWear.values, pending.baseSystemsWear)

    if tutorialOption ~= nil then
        tutorialOption:setIsChecked(pending.tutorialMode, false, false)
    end
    currentPage.rmsInstantInspection:setIsChecked(pending.instantInspection, false, false)
    currentPage.rmsInstantMaintenanceRepair:setIsChecked(pending.instantMaintenanceRepair, false, false)
    currentPage.rmsInstantBodywork:setIsChecked(pending.instantBodywork, false, false)
    currentPage.rmsInstantOverhaul:setIsChecked(pending.instantOverhaul, false, false)
    currentPage.rmsExhaustSmokeEnabled:setIsChecked(pending.exhaustSmokeEnabled, false, false)
    currentPage.rmsWarningMessages:setIsChecked(pending.enableWarningMessages, false, false)
    currentPage.rmsDealerWorkshopAvailable:setIsChecked(pending.dealerAlwaysAvailable, false, false)
    currentPage.rmsMobileWorkshopAvailable:setIsChecked(pending.mobileAlwaysAvailable, false, false)
    currentPage.rmsOwnWorkshopAvailable:setIsChecked(pending.ownAlwaysAvailable, false, false)
    currentPage.rmsMobileWorkshopRestrictions:setIsChecked(pending.mobileWorkshopRestrictionsEnabled, false, false)
    currentPage.rmsDrivetrainEnabled:setIsChecked(pending.drivetrainEnabled, false, false)
    currentPage.rmsDrivetrainAllowAutoMode:setIsChecked(pending.drivetrainAllowAutoMode, false, false)
    currentPage.rmsDrivetrainParkBrakeEnabled:setIsChecked(pending.drivetrainParkBrakeEnabled, false, false)
    currentPage.rmsDebugMode:setIsChecked(pending.debugMode, false, false)
    
    setIndex(currentPage.rmsWorkshopOpenHour, steps.hours.values, pending.openHour)
    setIndex(currentPage.rmsWorkshopCloseHour, steps.hours.values, pending.closeHour)

    local areAllWorkshopsAlwaysAvailable = pending.dealerAlwaysAvailable
        and pending.mobileAlwaysAvailable
        and pending.ownAlwaysAvailable
    currentPage.rmsWorkshopOpenHour:setDisabled(areAllWorkshopsAlwaysAvailable)
    currentPage.rmsWorkshopCloseHour:setDisabled(areAllWorkshopsAlwaysAvailable)

    local canChangeSettings = canChangeRMSSettings()
    local disableAll = not canChangeSettings

    currentPage.rmsServiceWear:setDisabled(disableAll)
    currentPage.rmsConditionWear:setDisabled(disableAll)
    currentPage.rmsExhaustSmokeEnabled:setDisabled(disableAll)

    currentPage.rmsInstantInspection:setDisabled(disableAll)
    currentPage.rmsInstantMaintenanceRepair:setDisabled(disableAll)
    currentPage.rmsInstantBodywork:setDisabled(disableAll)
    currentPage.rmsInstantOverhaul:setDisabled(disableAll)
    currentPage.rmsDealerWorkshopAvailable:setDisabled(disableAll)
    currentPage.rmsMobileWorkshopAvailable:setDisabled(disableAll)
    currentPage.rmsOwnWorkshopAvailable:setDisabled(disableAll)
    currentPage.rmsMobileWorkshopRestrictions:setDisabled(disableAll)
    currentPage.rmsDrivetrainEnabled:setDisabled(disableAll)
    currentPage.rmsDrivetrainAllowAutoMode:setDisabled(disableAll or not pending.drivetrainEnabled)
    currentPage.rmsDrivetrainParkBrakeEnabled:setDisabled(disableAll)
    currentPage.rmsWarningMessages:setDisabled(disableAll)
    currentPage.rmsDebugMode:setDisabled(disableAll)

    if disableAll or areAllWorkshopsAlwaysAvailable then
        currentPage.rmsWorkshopOpenHour:setDisabled(true)
        currentPage.rmsWorkshopCloseHour:setDisabled(true)
    end

end

---Stores whether exhaust smoke is simulated
-- @param integer state binary option state
function RMS_SettingsPage:onExhaustSmokeEnabledChanged(state)
    getPendingConfig().exhaustSmokeEnabled = (state == BinaryOptionElement.STATE_RIGHT)
    RMS_SettingsPage.rmsHasPendingSettingsChange = true
    refreshCurrentSettingsPage()
end

---Stores the base service wear step
-- @param integer state selected step index
function RMS_SettingsPage:onServiceWearChanged(state)
    getPendingConfig().baseServiceWear = RMS_SettingsPage.steps.serviceWear.values[state]
    RMS_SettingsPage.rmsHasPendingSettingsChange = true
    refreshCurrentSettingsPage()
end

---Stores whether the tutorial tips are shown
-- @param any state binary option state or boolean
-- @param table? optionElement option element that fired the callback
function RMS_SettingsPage:onTutorialModeChanged(state, optionElement)
    local pending = getPendingConfig()
    local newValue = false

    if optionElement ~= nil and optionElement.getIsChecked ~= nil then
        newValue = optionElement:getIsChecked()
    elseif RMS_SettingsPage.embeddedPage ~= nil
        and RMS_SettingsPage.embeddedPage.rmsTutorialMode ~= nil
        and RMS_SettingsPage.embeddedPage.rmsTutorialMode.getIsChecked ~= nil then
        newValue = RMS_SettingsPage.embeddedPage.rmsTutorialMode:getIsChecked()
    elseif state == BinaryOptionElement.STATE_RIGHT then
        newValue = true
    elseif type(state) == "boolean" then
        newValue = not state
    end

    pending.tutorialMode = newValue
    RMS_SettingsPage.rmsHasPendingSettingsChange = true
    refreshCurrentSettingsPage()
end

---Asks the player to confirm, then clears the seen tutorial messages
function RMS_SettingsPage:onResetTutorialTipsClicked()
    YesNoDialog.show(function(shouldReset)
        if shouldReset then
            RMS_Config.resetTutorialMessages()
            RMS_Config.syncTutorialState()
        end
    end, nil, g_i18n:getText("rms_tutorialResetConfirm_message"), g_i18n:getText("rms_tutorialResetConfirm_title"))
end

---Stores the base systems wear step
-- @param integer state selected step index
function RMS_SettingsPage:onConditionWearChanged(state)
    getPendingConfig().baseSystemsWear = RMS_SettingsPage.steps.conditionWear.values[state]
    RMS_SettingsPage.rmsHasPendingSettingsChange = true
    refreshCurrentSettingsPage()
end

---Stores whether inspections complete instantly
-- @param integer state binary option state
function RMS_SettingsPage:onInstantInspectionChanged(state)
    getPendingConfig().instantInspection = (state == BinaryOptionElement.STATE_RIGHT)
    RMS_SettingsPage.rmsHasPendingSettingsChange = true
    refreshCurrentSettingsPage()
end

---Stores whether maintenance and repairs complete instantly
-- @param integer state binary option state
function RMS_SettingsPage:onInstantMaintenanceRepairChanged(state)
    getPendingConfig().instantMaintenanceRepair = (state == BinaryOptionElement.STATE_RIGHT)
    RMS_SettingsPage.rmsHasPendingSettingsChange = true
    refreshCurrentSettingsPage()
end

---Stores whether bodywork completes instantly
-- @param integer state binary option state
function RMS_SettingsPage:onInstantBodyworkChanged(state)
    getPendingConfig().instantBodywork = (state == BinaryOptionElement.STATE_RIGHT)
    RMS_SettingsPage.rmsHasPendingSettingsChange = true
    refreshCurrentSettingsPage()
end

---Stores whether overhauls complete instantly
-- @param integer state binary option state
function RMS_SettingsPage:onInstantOverhaulChanged(state)
    getPendingConfig().instantOverhaul = (state == BinaryOptionElement.STATE_RIGHT)
    RMS_SettingsPage.rmsHasPendingSettingsChange = true
    refreshCurrentSettingsPage()
end

---Stores whether the dealer workshop is always open
-- @param integer state binary option state
function RMS_SettingsPage:onDealerWorkshopAvailableChanged(state)
    getPendingConfig().dealerAlwaysAvailable = (state == BinaryOptionElement.STATE_RIGHT)
    RMS_SettingsPage.rmsHasPendingSettingsChange = true
    refreshCurrentSettingsPage()
end

---Stores whether the mobile workshop is always open
-- @param integer state binary option state
function RMS_SettingsPage:onMobileWorkshopAvailableChanged(state)
    getPendingConfig().mobileAlwaysAvailable = (state == BinaryOptionElement.STATE_RIGHT)
    RMS_SettingsPage.rmsHasPendingSettingsChange = true
    refreshCurrentSettingsPage()
end

---Stores whether the own workshop is always open
-- @param integer state binary option state
function RMS_SettingsPage:onOwnWorkshopAvailableChanged(state)
    getPendingConfig().ownAlwaysAvailable = (state == BinaryOptionElement.STATE_RIGHT)
    RMS_SettingsPage.rmsHasPendingSettingsChange = true
    refreshCurrentSettingsPage()
end

---Stores whether the mobile workshop restricts services by its equipment
-- @param integer state binary option state
function RMS_SettingsPage:onMobileWorkshopRestrictionsChanged(state)
    getPendingConfig().mobileWorkshopRestrictionsEnabled = (state == BinaryOptionElement.STATE_RIGHT)
    RMS_SettingsPage.rmsHasPendingSettingsChange = true
    refreshCurrentSettingsPage()
end

-- @param integer state selected step index
function RMS_SettingsPage:onWorkshopOpenHourChanged(state)
    local pending = getPendingConfig()
    local newOpen = RMS_SettingsPage.steps.hours.values[state]
    local currentClose = pending.closeHour

    if newOpen >= currentClose then
        currentClose = newOpen + 1
        if currentClose > 23 then
            currentClose = 23
            newOpen = 22
        end
        pending.closeHour = currentClose
    end

    pending.openHour = newOpen
    RMS_SettingsPage.rmsHasPendingSettingsChange = true
    refreshCurrentSettingsPage()
end

-- @param integer state selected step index
function RMS_SettingsPage:onWorkshopCloseHourChanged(state)
    local pending = getPendingConfig()
    local newClose = RMS_SettingsPage.steps.hours.values[state]
    local currentOpen = pending.openHour

    if currentOpen >= newClose then
        currentOpen = newClose - 1
        if currentOpen < 0 then
            currentOpen = 0
            newClose = 1
        end
        pending.openHour = currentOpen
    end

    pending.closeHour = newClose
    RMS_SettingsPage.rmsHasPendingSettingsChange = true
    refreshCurrentSettingsPage()
end



---Stores whether the drivetrain system is simulated
-- @param integer state binary option state
function RMS_SettingsPage:onDrivetrainEnabledChanged(state)
    getPendingConfig().drivetrainEnabled = (state == BinaryOptionElement.STATE_RIGHT)
    RMS_SettingsPage.rmsHasPendingSettingsChange = true
    refreshCurrentSettingsPage()
end

---Stores whether the drivetrain automatic mode is offered
-- @param integer state binary option state
function RMS_SettingsPage:onDrivetrainAllowAutoModeChanged(state)
    getPendingConfig().drivetrainAllowAutoMode = (state == BinaryOptionElement.STATE_RIGHT)
    RMS_SettingsPage.rmsHasPendingSettingsChange = true
    refreshCurrentSettingsPage()
end

---Stores whether the park brake is simulated
-- @param integer state binary option state
function RMS_SettingsPage:onDrivetrainParkBrakeEnabledChanged(state)
    getPendingConfig().drivetrainParkBrakeEnabled = (state == BinaryOptionElement.STATE_RIGHT)
    RMS_SettingsPage.rmsHasPendingSettingsChange = true
    refreshCurrentSettingsPage()
end

---Stores whether warning messages are shown
-- @param integer state binary option state
function RMS_SettingsPage:onWarningMessagesChanged(state)
    getPendingConfig().enableWarningMessages = (state == BinaryOptionElement.STATE_RIGHT)
    RMS_SettingsPage.rmsHasPendingSettingsChange = true
    refreshCurrentSettingsPage()
end

---Stores whether the debug mode, its window and its logs, is on
-- @param integer state binary option state
function RMS_SettingsPage:onDebugModeChanged(state)
    getPendingConfig().debugMode = (state == BinaryOptionElement.STATE_RIGHT)
    RMS_SettingsPage.rmsHasPendingSettingsChange = true
    refreshCurrentSettingsPage()
end


---Appends a section title to the settings layout
-- @param table inGameMenuSettingsFrame frame hosting the settings layout
-- @param string titleText section title
function RMS_SettingsPage:addSectionHeader(inGameMenuSettingsFrame, titleText)
    local textElement = TextElement.new()
    local textElementProfile = getSettingsProfile("fs25_settingsSectionHeader")
    textElement.name = "sectionHeader"
    textElement:loadProfile(textElementProfile, true)
    textElement:setText(titleText)
    inGameMenuSettingsFrame.settingsLayout:addElement(textElement)
    textElement:onGuiSetupFinished()
end

---Appends a stepped option row to the settings layout
-- @param table inGameMenuSettingsFrame frame hosting the settings layout
-- @param string onClickCallback name of the callback fired on change
-- @param table texts step labels
-- @param string title row title
-- @param string tooltip row tooltip
-- @return table option multi text option element
function RMS_SettingsPage:addMultiTextOption(inGameMenuSettingsFrame, onClickCallback, texts, title, tooltip)
    local bitMap = BitmapElement.new()
    local bitMapProfile = getSettingsProfile("fs25_multiTextOptionContainer")
    bitMap:loadProfile(bitMapProfile, true)
    applySettingsRowColor(inGameMenuSettingsFrame, bitMap)

    local multiTextOption = MultiTextOptionElement.new()
    local multiTextOptionProfile = getSettingsProfile("fs25_settingsMultiTextOption")
    multiTextOption:loadProfile(multiTextOptionProfile, true)
    multiTextOption.updateChildrenState = true
    multiTextOption.target = RMS_SettingsPage
    multiTextOption:setCallback("onClickCallback", onClickCallback)
    multiTextOption:setTexts(texts)

    local multiTextOptionTitle = TextElement.new()
    local multiTextOptionTitleProfile = getSettingsProfile("fs25_settingsMultiTextOptionTitle")
    multiTextOptionTitle:loadProfile(multiTextOptionTitleProfile, true)
    multiTextOptionTitle:setText(title)

    local multiTextOptionTooltip = TextElement.new()
    local multiTextOptionTooltipProfile = getSettingsProfile("fs25_multiTextOptionTooltip")
    multiTextOptionTooltip.name = "ignore"
    multiTextOptionTooltip:loadProfile(multiTextOptionTooltipProfile, true)
    multiTextOptionTooltip:setText(tooltip)

    multiTextOption:addElement(multiTextOptionTooltip)
    bitMap:addElement(multiTextOption)
    addDisabledLockToSettingsRow(bitMap, multiTextOption, tooltip)
    bitMap:addElement(multiTextOptionTitle)

    multiTextOption:onGuiSetupFinished()
    applyMultiTextOptionBackgroundProfile(multiTextOption)
    multiTextOptionTitle:onGuiSetupFinished()
    multiTextOptionTooltip:onGuiSetupFinished()

    inGameMenuSettingsFrame.settingsLayout:addElement(bitMap)
    bitMap:onGuiSetupFinished()
    
    return multiTextOption
end

---Appends a yes or no option row to the settings layout
-- @param table inGameMenuSettingsFrame frame hosting the settings layout
-- @param string onClickCallback name of the callback fired on change
-- @param string title row title
-- @param string tooltip row tooltip
-- @return table option binary option element
function RMS_SettingsPage:addBinaryOption(inGameMenuSettingsFrame, onClickCallback, title, tooltip)
    local bitMap = BitmapElement.new()
    local bitMapProfile = getSettingsProfile("fs25_multiTextOptionContainer")
    bitMap:loadProfile(bitMapProfile, true)
    applySettingsRowColor(inGameMenuSettingsFrame, bitMap)

    local binaryOption = BinaryOptionElement.new()
    binaryOption.useYesNoTexts = true
    local binaryOptionProfile = getSettingsProfile("fs25_settingsBinaryOption")
    binaryOption:loadProfile(binaryOptionProfile, true)
    binaryOption.target = RMS_SettingsPage
    binaryOption:setCallback("onClickCallback", onClickCallback)

    local binaryOptionTitle = TextElement.new()
    local binaryOptionTitleProfile = getSettingsProfile("fs25_settingsMultiTextOptionTitle")
    binaryOptionTitle:loadProfile(binaryOptionTitleProfile, true)
    binaryOptionTitle:setText(title)

    local binaryOptionTooltip = TextElement.new()
    local binaryOptionTooltipProfile = getSettingsProfile("fs25_multiTextOptionTooltip")
    binaryOptionTooltip.name = "ignore"
    binaryOptionTooltip:loadProfile(binaryOptionTooltipProfile, true)
    binaryOptionTooltip:setText(tooltip)

    binaryOption:addElement(binaryOptionTooltip)
    bitMap:addElement(binaryOption)
    addDisabledLockToSettingsRow(bitMap, binaryOption, tooltip)
    bitMap:addElement(binaryOptionTitle)

    binaryOption:onGuiSetupFinished()
    binaryOptionTitle:onGuiSetupFinished()
    binaryOptionTooltip:onGuiSetupFinished()

    inGameMenuSettingsFrame.settingsLayout:addElement(bitMap)
    bitMap:onGuiSetupFinished()
    
    return binaryOption
end

---Appends a button row cloned from the vanilla settings template
-- @param table inGameMenuSettingsFrame frame hosting the settings layout
-- @param string onClickCallback name of the callback fired on click
-- @param string title row title
-- @param string text button text
-- @param string tooltip row tooltip
-- @return table? button button element
function RMS_SettingsPage:addButtonOption(inGameMenuSettingsFrame, onClickCallback, title, text, tooltip)
    local template = getVanillaSettingsButtonTemplate()
    local bitMap
    if template ~= nil and template.clone ~= nil then
        bitMap = template:clone(inGameMenuSettingsFrame.settingsLayout)
        bitMap.id = nil
    else
        bitMap = BitmapElement.new()
        local bitMapProfile = getSettingsProfile("fs25_multiTextOptionContainer")
        bitMap:loadProfile(bitMapProfile, true)
        inGameMenuSettingsFrame.settingsLayout:addElement(bitMap)
    end

    applySettingsRowColor(inGameMenuSettingsFrame, bitMap)

    local button
    local buttonTitle

    for _, element in pairs(bitMap.elements) do
        if element.typeName == "Button" then
            button = element
        elseif element.typeName == "Text" and element.name ~= "ignore" then
            buttonTitle = element
        end
    end

    if button == nil then
        button = ButtonElement.new()
        bitMap:addElement(button)
    end

    button:applyProfile("rms_settingsButton")
    applyButtonBackgroundProfile(button)
    button.target = RMS_SettingsPage
    button:setCallback("onClickCallback", onClickCallback)
    button:setText(text)
    button.id = nil
    button.isAlwaysFocusedOnOpen = false
    button.focused = false

    if buttonTitle == nil then
        buttonTitle = TextElement.new()
        local buttonTitleProfile = getSettingsProfile("fs25_settingsMultiTextOptionTitle")
        buttonTitle:loadProfile(buttonTitleProfile, true)
        bitMap:addElement(buttonTitle)
    elseif buttonTitle.applyProfile ~= nil then
        buttonTitle:applyProfile("fs25_settingsMultiTextOptionTitle")
    end

    buttonTitle:setText(title)
    buttonTitle.id = nil
    if buttonTitle.setDisabled ~= nil then
        buttonTitle:setDisabled(false)
    end

    local buttonTooltip = button:getDescendantByName("ignore")
    if buttonTooltip == nil then
        buttonTooltip = TextElement.new()
        local buttonTooltipProfile = getSettingsProfile("fs25_multiTextOptionTooltip")
        buttonTooltip.name = "ignore"
        buttonTooltip:loadProfile(buttonTooltipProfile, true)
        button:addElement(buttonTooltip)
    end

    buttonTooltip:setText(tooltip)
    buttonTooltip.id = nil

    button:onGuiSetupFinished()
    buttonTitle:onGuiSetupFinished()
    buttonTooltip:onGuiSetupFinished()

    bitMap:onGuiSetupFinished()

    return button
end


---Builds the value and label lists of every stepped setting, once per session
function RMS_SettingsPage:generateAllSteps()
    if self.steps.generated then return end

    ---Builds a step list of evenly spaced values
    local function createSteps(startVal, count, stepSize, formatter)
        local data = { values = {}, texts = {} }
        for i = 0, count - 1 do
            local val = startVal + (i * stepSize)
            table.insert(data.values, val)
            table.insert(data.texts, formatter and formatter(val) or tostring(val))
        end
        return data
    end

    do
        local data = { values = {}, texts = {} }

        ---Appends one hour range to the step list
        local function addHourRange(startHour, endHour, stepHour)
            local hours = startHour
            while hours <= endHour + 0.0001 do
                table.insert(data.values, 0.5 / hours)
                table.insert(data.texts, RMS_Utils.formatHours(hours))
                hours = hours + stepHour
            end
        end

        addHourRange(1.0, 20.0, 1.0)
        addHourRange(22.0, 50.0, 2.0)
        addHourRange(55.0, 100.0, 5.0)
        addHourRange(200.0, 1000.0, 100.0)

        self.steps.serviceWear = data
    end

    do
        local data = { values = {}, texts = {} }

        ---Appends one hour range to the step list
        local function addHourRange(startHour, endHour, stepHour)
            local hours = startHour
            while hours <= endHour + 0.0001 do
                table.insert(data.values, 1.0 / hours)
                table.insert(data.texts, RMS_Utils.formatHours(hours))
                hours = hours + stepHour
            end
        end

        addHourRange(40, 200, 10)
        addHourRange(220, 500, 20)
        addHourRange(550, 1000, 50)
        addHourRange(2000, 10000, 1000)
        addHourRange(20000, 50000, 10000)

        self.steps.conditionWear = data
    end

    self.steps.hours = createSteps(0, 24, 1, function(v)
        return string.format("%02d:00", v)
    end)

    self.steps.generated = true
end


---Clears the editing session state
function RMS_SettingsPage.reset()
    RMS_SettingsPage.steps = {}
    RMS_SettingsPage.pendingConfig = nil
    RMS_SettingsPage.rmsHasPendingSettingsChange = false
    RMS_SettingsPage.embeddedPage = nil
end
