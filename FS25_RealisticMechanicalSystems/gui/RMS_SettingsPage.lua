-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---Settings tab of the fleet menu
RMS_SettingsPage = {}

---Lists the hours of ranges given as first hour, last hour and step
local function listHours(ranges)
    local hours = {}
    for _, range in ipairs(ranges) do
        for value = range[1], range[2], range[3] do
            table.insert(hours, value)
        end
    end
    return hours
end

local CLOCK_HOURS = listHours({ { 0, 23, 1 } })

---Tells whether a workshop keeps opening hours
local function hasWorkshopHours(values)
    return not (values.dealerAlwaysAvailable and values.mobileAlwaysAvailable and values.ownAlwaysAvailable)
end

-- each row of the settings tab and the RMS_Config field it edits
local SETTINGS = {
    { row = "rmsTutorialMode", key = "tutorialMode", field = "TUTORIAL_MODE", isPersonal = true },
    { row = "rmsWarningMessages", key = "enableWarningMessages", group = "CORE", field = "ENABLE_WARNING_MESSAGES" },
    { row = "rmsDebugMode", key = "debugMode" },
    { row = "rmsServiceWear", key = "baseServiceWear", group = "CORE", field = "BASE_SERVICE_WEAR", intervalWear = 0.5,
        hours = listHours({ { 1, 20, 1 }, { 22, 50, 2 }, { 55, 100, 5 }, { 200, 1000, 100 } }) },
    { row = "rmsConditionWear", key = "baseSystemsWear", group = "CORE", field = "BASE_SYSTEMS_WEAR", intervalWear = 1,
        hours = listHours({ { 40, 200, 10 }, { 220, 500, 20 }, { 550, 1000, 50 }, { 2000, 10000, 1000 }, { 20000, 50000, 10000 } }) },
    { row = "rmsExhaustSmokeEnabled", key = "exhaustSmokeEnabled", group = "EXHAUST", field = "ENABLED" },
    { row = "rmsInstantInspection", key = "instantInspection", group = "MAINTENANCE", field = "INSTANT_INSPECTION" },
    { row = "rmsInstantMaintenanceRepair", key = "instantMaintenanceRepair", group = "MAINTENANCE", field = "INSTANT_MAINTENANCE_REPAIR" },
    { row = "rmsInstantBodywork", key = "instantBodywork", group = "MAINTENANCE", field = "INSTANT_BODYWORK" },
    { row = "rmsInstantOverhaul", key = "instantOverhaul", group = "MAINTENANCE", field = "INSTANT_OVERHAUL" },
    { row = "rmsMobileWorkshopRestrictions", key = "mobileWorkshopRestrictionsEnabled", group = "WORKSHOP",
        field = "MOBILE_WORKSHOP_RESTRICTIONS_ENABLED" },
    { row = "rmsDealerWorkshopAvailable", key = "dealerAlwaysAvailable", group = "WORKSHOP", field = "DEALER_ALWAYS_AVAILABLE" },
    { row = "rmsMobileWorkshopAvailable", key = "mobileAlwaysAvailable", group = "WORKSHOP", field = "MOBILE_ALWAYS_AVAILABLE" },
    { row = "rmsOwnWorkshopAvailable", key = "ownAlwaysAvailable", group = "WORKSHOP", field = "OWN_ALWAYS_AVAILABLE" },
    { row = "rmsWorkshopOpenHour", key = "openHour", group = "WORKSHOP", field = "OPEN_HOUR", hours = CLOCK_HOURS,
        isNeeded = hasWorkshopHours, lockReason = "rms_workshopHours_locked" },
    { row = "rmsWorkshopCloseHour", key = "closeHour", group = "WORKSHOP", field = "CLOSE_HOUR", hours = CLOCK_HOURS,
        isNeeded = hasWorkshopHours, lockReason = "rms_workshopHours_locked" },
    { row = "rmsDrivetrainEnabled", key = "drivetrainEnabled", group = "DRIVETRAIN", field = "ENABLED" },
    { row = "rmsDrivetrainAllowAutoMode", key = "drivetrainAllowAutoMode", group = "DRIVETRAIN", field = "ALLOW_AUTO_MODE",
        isNeeded = function(values) return values.drivetrainEnabled end, lockReason = "rms_drivetrainAllowAutoMode_locked" },
    { row = "rmsDrivetrainParkBrakeEnabled", key = "drivetrainParkBrakeEnabled", group = "DRIVETRAIN", field = "PARKBRAKE_ENABLED" }
}

-- instant setting and the service states it finishes
local INSTANT_SERVICES = {
    instantInspection = { "INSPECTION" },
    instantMaintenanceRepair = { "MAINTENANCE", "REPAIR" },
    instantBodywork = { "BODYWORK" },
    instantOverhaul = { "OVERHAUL" }
}

---Returns the RMS_Config table holding a setting
local function getConfigTable(setting)
    return setting.group ~= nil and RMS_Config[setting.group] or RMS_Config
end

---Reads the current value of every setting
local function readSettings()
    local values = { debugMode = RMS_DebugWindow.getIsOpen() }
    for _, setting in ipairs(SETTINGS) do
        if setting.field ~= nil then
            values[setting.key] = getConfigTable(setting)[setting.field]
        end
    end
    return values
end

---Returns the setting value of a selector step
local function getStepValue(setting, state)
    local hours = setting.hours[state]
    return setting.intervalWear ~= nil and setting.intervalWear / hours or hours
end

---Returns the selector step closest to a setting value
local function getClosestState(setting, value)
    local closest, distance = 1, math.huge
    for state in ipairs(setting.hours) do
        local stepDistance = math.abs(getStepValue(setting, state) - value)
        if stepDistance < distance then
            closest, distance = state, stepDistance
        end
    end
    return closest
end

---Tells whether the player may change the shared settings
local function getIsAdmin()
    local mission = g_currentMission
    return not mission.missionDynamicInfo.isMultiplayer or mission:getIsServer() or mission.isMasterUser
end

---Locks or unlocks the row of an option, its padlock giving the reason
-- @param table option option element of the row
-- @param string? reason l10n key of the reason, nil to unlock
local function setRowLock(option, reason)
    local row = option.parent
    local padlock = row:getDescendantByName("iconDisabled")
    -- disabling a row disables its children, padlock included
    row:setDisabled(reason ~= nil)
    padlock:setDisabled(reason == nil)
    if reason ~= nil then
        padlock:getDescendantByName("reason"):setText(g_i18n:getText(reason))
    end
end

---Locks the rows the player may not change or does not need
local function updateRowLocks(page)
    local isAdmin = getIsAdmin()
    local pending = RMS_SettingsPage.pending
    for option, setting in pairs(page.rmsSettings) do
        if not setting.isPersonal then
            local reason
            if not isAdmin then
                reason = "rms_settings_admin_required"
            elseif setting.isNeeded ~= nil and not setting.isNeeded(pending) then
                reason = setting.lockReason
            end
            setRowLock(option, reason)
        end
    end
end

---Writes the engine oil hours of each era at the selected hours
local function updateServiceTooltip(page)
    local option = page.rmsServiceWear
    local hours = page.rmsSettings[option].intervalWear / RMS_SettingsPage.pending.baseServiceWear
    local eraHours = {}
    -- eras run oldest first, the text lists them newest first
    local eras = RMS_Config.ENGINE_OIL_HOURS_BY_YEAR
    for i = #eras, 1, -1 do
        table.insert(eraHours, RMS_Utils.formatHours(hours * eras[i].hours / RMS_Config.SERVICE_REFERENCE_HOURS))
    end
    option:getDescendantByName("ignore"):setText(string.format(g_i18n:getText("rms_serviceInterval_tooltip"), unpack(eraHours)))
end

---Keeps the opening hour first, moving the hour not picked
local function keepWorkshopHoursOrdered(page, pickedKey)
    local pending = RMS_SettingsPage.pending
    if pending.openHour < pending.closeHour then
        return
    end

    if pickedKey == "openHour" then
        pending.openHour = math.min(pending.openHour, 22)
        pending.closeHour = pending.openHour + 1
    else
        pending.closeHour = math.max(pending.closeHour, 1)
        pending.openHour = pending.closeHour - 1
    end
    -- the clock rows start at 0:00
    page.rmsWorkshopOpenHour:setState(pending.openHour + 1)
    page.rmsWorkshopCloseHour:setState(pending.closeHour + 1)
end

---Finishes the services an instant setting just turned on
-- @param table before instant settings before the change
-- @param table after instant settings after the change
function RMS_SettingsPage.finishInstantServices(before, after)
    if not g_currentMission:getIsServer() then
        return
    end

    local finishedStates = {}
    for key, states in pairs(INSTANT_SERVICES) do
        if after[key] and not before[key] then
            for _, state in ipairs(states) do
                finishedStates[RealisticMechanicalSystems.STATUS[state]] = true
            end
        end
    end

    for _, vehicle in pairs(RMS_Main.vehicles) do
        local spec = vehicle.spec_RealisticMechanicalSystems
        if finishedStates[spec.currentState] and not spec.isExcludedVehicle and RealisticMechanicalSystems.forceFinishService(vehicle) then
            RealisticMechanicalSystems.raiseServiceLifecycleDirtyFlags(vehicle)
        end
    end
end

---Binds the rows of the layout to their settings, once with the frame
-- @param table page fleet frame holding the settings tab
function RMS_SettingsPage.initializeControls(page)
    page.rmsSettings = {}
    for _, setting in ipairs(SETTINGS) do
        local option = page[setting.row]
        page.rmsSettings[option] = setting
        if setting.hours ~= nil then
            local texts = {}
            for state, hours in ipairs(setting.hours) do
                texts[state] = setting.intervalWear ~= nil and RMS_Utils.formatHours(hours) or string.format("%02d:00", hours)
            end
            option:setTexts(texts)
        end
    end
end

---Shows the settings tab, opening an editing session
-- @param table page fleet frame holding the settings tab
function RMS_SettingsPage.show(page)
    if RMS_SettingsPage.pending == nil then
        RMS_SettingsPage.saved = readSettings()
        RMS_SettingsPage.pending = readSettings()
    end

    local pending = RMS_SettingsPage.pending
    for option, setting in pairs(page.rmsSettings) do
        if setting.hours ~= nil then
            option:setState(getClosestState(setting, pending[setting.key]))
        else
            option:setIsChecked(pending[setting.key], true)
        end
    end

    updateServiceTooltip(page)
    page.rmsDebugMode:getDescendantByName("ignore"):setText(string.format(g_i18n:getText("rms_debugMode_tooltip"),
        RMS_Utils.getPrimaryKeyboardInputText("RMS_TOGGLE_DEBUG_WINDOW", "Alt Gr + F5")))
    updateRowLocks(page)
    InGameMenuSettingsFrame.updateAlternatingElements(nil, page.settingsLayout)
end

---Ends the editing session without applying it
function RMS_SettingsPage.reset()
    RMS_SettingsPage.saved = nil
    RMS_SettingsPage.pending = nil
end

---Ends the editing session, applying the changed settings
function RMS_SettingsPage.applyChanges()
    local saved, pending = RMS_SettingsPage.saved, RMS_SettingsPage.pending
    RMS_SettingsPage.reset()
    if pending == nil then
        return
    end

    local before = readSettings()
    -- changed group, or key of a setting outside any group
    local changed = {}
    local isShared = false
    for _, setting in ipairs(SETTINGS) do
        local value = pending[setting.key]
        if value ~= saved[setting.key] then
            if setting.field ~= nil then
                getConfigTable(setting)[setting.field] = value
            end
            changed[setting.group or setting.key] = true
            isShared = isShared or not setting.isPersonal
        end
    end

    if changed.tutorialMode then
        RMS_Config.syncTutorialState()
    end
    if changed.debugMode then
        RMS_DebugWindow.isOpen = pending.debugMode
        RMS_Config.DEBUG = pending.debugMode
    end
    if changed.MAINTENANCE then
        RMS_SettingsPage.finishInstantServices(before, readSettings())
    end
    if changed.WORKSHOP then
        RMS_Main:forceWorkshopUpdate(true)
    end
    if changed.DRIVETRAIN then
        RMS_Drivetrain.refreshAllParkBrakePedals()
        RMS_Drivetrain.claimFromOtherMod()
    end
    if isShared then
        RMS_SettingsSyncEvent.share()
    end
end

-- callbacks of the rows the settings layout declares

---Stores the value given to a row
-- @param integer state selected step, or state of a switch
-- @param table option option element of the row
function RMS_InGameMenuFrame:onClickRmsOption(state, option)
    local setting = self.rmsSettings[option]
    local pending = RMS_SettingsPage.pending
    if setting.hours ~= nil then
        pending[setting.key] = getStepValue(setting, state)
    else
        pending[setting.key] = option:getIsChecked()
    end

    if setting.key == "openHour" or setting.key == "closeHour" then
        keepWorkshopHoursOrdered(self, setting.key)
    elseif setting.key == "baseServiceWear" then
        updateServiceTooltip(self)
    end
    updateRowLocks(self)
end

---Asks to confirm clearing the seen tutorial messages
function RMS_InGameMenuFrame:onClickRmsResetTutorialTips()
    YesNoDialog.show(self.onYesNoResetTutorialTips, self, g_i18n:getText("rms_tutorialResetConfirm_message"),
        g_i18n:getText("rms_tutorialResetConfirm_title"))
end

---Clears the seen tutorial messages once confirmed
-- @param boolean yes true when confirmed
function RMS_InGameMenuFrame:onYesNoResetTutorialTips(yes)
    if yes then
        RMS_Config.resetTutorialMessages()
        RMS_Config.syncTutorialState()
    end
end

---
function RMS_InGameMenuFrame:onClickLockedIcon()
end

---Keeps the focused padlock in view
-- @param table icon focused padlock element
function RMS_InGameMenuFrame:onFocusLockedIcon(icon)
    self.settingsLayout:scrollToMakeElementVisible(icon)
end
