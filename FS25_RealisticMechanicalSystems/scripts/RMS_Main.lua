-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---Mod entry point: specialization registration, workshop hours, shop pages and the main update
RMS_Main = {}

RMS_SoundManager = {}

---Plays a sample once
-- @param table? sample audio sample
function RMS_SoundManager.playSample(sample)
    if sample ~= nil then
        g_soundManager:playSample(sample)
    end
end

---Stops a sample, fading it out over the given duration
-- @param table? sample audio sample
-- @param float? fadeDuration fade out duration in ms
-- @param boolean? force true to stop it at once
function RMS_SoundManager.stopSample(sample, fadeDuration, force)
    if sample == nil then
        return
    end

    if fadeDuration == nil then
        g_soundManager:stopSample(sample)
    else
        g_soundManager:stopSample(sample, fadeDuration, force or 0)
    end
end

---Tells whether a sample is playing
-- @param table? sample audio sample
-- @return boolean isPlaying true while it plays
function RMS_SoundManager.getIsSamplePlaying(sample)
    return sample ~= nil and g_soundManager:getIsSamplePlaying(sample)
end

---Starts or stops a looping sample
-- @param table? sample audio sample
-- @param boolean shouldPlay true to play it
-- @param float? fadeDuration fade duration in ms
-- @param boolean? force true to apply it at once
function RMS_SoundManager.setSamplePlaying(sample, shouldPlay, fadeDuration, force)
    if sample == nil then
        return
    end

    local isPlaying = RMS_SoundManager.getIsSamplePlaying(sample)
    if shouldPlay and not isPlaying then
        RMS_SoundManager.playSample(sample)
    elseif not shouldPlay and isPlaying then
        RMS_SoundManager.stopSample(sample, fadeDuration, force)
    end
end

---Sets the pitch offset of a sample
-- @param table? sample audio sample
-- @param float pitchOffset pitch offset
function RMS_SoundManager.setSamplePitchOffset(sample, pitchOffset)
    if sample ~= nil then
        g_soundManager:setSamplePitchOffset(sample, pitchOffset)
    end
end

---Sets the volume offset of a sample
-- @param table? sample audio sample
-- @param float volumeOffset volume offset
function RMS_SoundManager.setSampleVolumeOffset(sample, volumeOffset)
    if sample ~= nil then
        g_soundManager:setSampleVolumeOffset(sample, volumeOffset)
    end
end

local modDirectory = g_currentModDirectory
local modName = g_currentModName

source(g_currentModDirectory .. "scripts/RMS_Config.lua")
source(g_currentModDirectory .. "scripts/RMS_Utils.lua")
source(g_currentModDirectory .. "scripts/RMS_Fluids.lua")
source(g_currentModDirectory .. "scripts/RMS_FluidTransfer.lua")
source(g_currentModDirectory .. "scripts/RMS_FluidStorage.lua")
source(g_currentModDirectory .. "scripts/RMS_Bodywork.lua")
source(g_currentModDirectory .. "scripts/RMS_FluidWorkshop.lua")
source(g_currentModDirectory .. "scripts/RMS_ProgressRing.lua")
source(g_currentModDirectory .. "scripts/RMS_VehicleYearsData.lua")
source(g_currentModDirectory .. "scripts/RMS_VehicleYears.lua")
source(g_currentModDirectory .. "scripts/RMS_DebugSnapshot.lua")
source(g_currentModDirectory .. "scripts/RMS_Leasing.lua")
source(g_currentModDirectory .. "scripts/RMS_Tutorial.lua")
source(g_currentModDirectory .. "gui/RMS_WorkshopDialog.lua")
source(g_currentModDirectory .. "gui/RMS_MaintenanceLogDialog.lua")
source(g_currentModDirectory .. "gui/RMS_ReportDialog.lua")
source(g_currentModDirectory .. "gui/RMS_InspectionDialog.lua")
source(g_currentModDirectory .. "gui/RMS_SellItemDialog.lua")
source(g_currentModDirectory .. "gui/RMS_InGameMenuFrame.lua")
source(g_currentModDirectory .. "gui/RMS_MaintenanceTwoOptionsDialog.lua")
source(g_currentModDirectory .. "gui/RMS_MaintenanceThreeOptionsDialog.lua")
source(g_currentModDirectory .. "gui/RMS_WelcomeDialog.lua")
source(g_currentModDirectory .. "gui/RMS_SettingsPage.lua")
source(g_currentModDirectory .. "scripts/RMS_Hud.lua")
source(g_currentModDirectory .. "scripts/RMS_PlayerInput.lua")
source(g_currentModDirectory .. "events/RMS_VehicleChangeStatusEvent.lua")
source(g_currentModDirectory .. "events/RMS_WorkshopChangeStatusEvent.lua")
source(g_currentModDirectory .. "events/RMS_ServiceRequestEvent.lua")
source(g_currentModDirectory .. "events/RMS_BodyworkColorEvent.lua")
source(g_currentModDirectory .. "events/RMS_ServiceResultEvent.lua")
source(g_currentModDirectory .. "events/RMS_FluidTransferRequestEvent.lua")
source(g_currentModDirectory .. "events/RMS_BatteryChargerRequestEvent.lua")
source(g_currentModDirectory .. "events/RMS_CancelServiceEvent.lua")
source(g_currentModDirectory .. "events/RMS_SettingsSyncEvent.lua")
source(g_currentModDirectory .. "events/RMS_TutorialStateEvent.lua")
source(g_currentModDirectory .. "events/RMS_EffectSyncEvent.lua")
source(g_currentModDirectory .. "events/RMS_LogEntrySyncEvent.lua")
source(g_currentModDirectory .. "events/RMS_ConsoleCommandEvent.lua")
source(g_currentModDirectory .. "events/RMS_VehicleExclusionEvent.lua")
source(g_currentModDirectory .. "events/RMS_StartButtonEvent.lua")
source(g_currentModDirectory .. "events/RMS_FieldInspectionEvent.lua")
source(g_currentModDirectory .. "events/RMS_BatteryIsolatorEvent.lua")
source(g_currentModDirectory .. "events/RMS_HandToolSyncEvent.lua")
source(g_currentModDirectory .. "events/RMS_JumperCablesEvent.lua")
source(g_currentModDirectory .. "events/RMS_DrivetrainEvent.lua")
source(g_currentModDirectory .. "events/RMS_TripResetEvent.lua")
source(g_currentModDirectory .. "events/RMS_DebugSnapshotResponseEvent.lua")
source(g_currentModDirectory .. "events/RMS_DebugSnapshotRequestEvent.lua")

---Loads the GUI profiles of the mod
function RMS_Main.loadGuiProfiles()
    if RMS_Main.guiProfilesLoaded then
        return
    end

    g_gui:loadProfiles(modDirectory .. "gui/guiProfiles.xml")

    if g_overlayManager.textureConfigs.rms_MenuIcon == nil then
        g_overlayManager:addTextureConfigFile(modDirectory .. "images/menuIcon.xml", "rms_MenuIcon")
    end

    if g_overlayManager.textureConfigs.rms_WorkshopFluids == nil then
        g_overlayManager:addTextureConfigFile(modDirectory .. "gui/rms_workshopFluids.xml", "rms_WorkshopFluids")
    end

    if g_overlayManager.textureConfigs.rms_LevelGauge == nil then
        g_overlayManager:addTextureConfigFile(modDirectory .. "gui/rms_levelGauge.xml", "rms_LevelGauge")
    end

    -- the fleet page is built before the HUD and names glyphs of its atlas
    if g_overlayManager.textureConfigs.rms_DashboardHud == nil then
        g_overlayManager:addTextureConfigFile(modDirectory .. "hud/rms_dashboardHud.xml", "rms_DashboardHud")
    end

    RMS_Main.guiProfilesLoaded = true
end


---Declares the RMS specialization to the vehicle type manager
function RMS_Main.initSpec()
    g_specializationManager:addSpecialization("RealisticMechanicalSystems", "RealisticMechanicalSystems", g_currentModDirectory.."scripts/core/RMS_Specialization.lua", "")
    TypeManager.finalizeTypes = Utils.appendedFunction(TypeManager.finalizeTypes, RMS_Main.registerSpecializationToVehicles)
end

local RMS_REQUIRED_SPECIALIZATIONS = {"motorized", "wheels", "enterable"}

local RMS_REJECTED_SPECIALIZATIONS = {"pushHandTool", "locomotive", "motorbike"}

---Tells whether a vehicle type gets the RMS specialization
local function getIsTypeManagedByRMS(vehicleType)
	local specializations = vehicleType.specializationsByName
	if specializations.RealisticMechanicalSystems ~= nil then
		return false
	end

	for _, name in ipairs(RMS_REQUIRED_SPECIALIZATIONS) do
		if specializations[name] == nil then
			return false
		end
	end

	for _, name in ipairs(RMS_REJECTED_SPECIALIZATIONS) do
		if specializations[name] ~= nil then
			return false
		end
	end

	return true
end

---Attaches the RMS specialization to every managed vehicle type
function RMS_Main.registerSpecializationToVehicles()
	if g_modIsLoaded["FS25_AdvancedDamageSystem"] then
		if not RMS_Main.conflictLogged then
			Logging.warning("RMS: Advanced Damage System is loaded, RMS stays out. Keep only one of the two.")
			RMS_Main.conflictLogged = true
		end
		return
	end

	local specName = "RealisticMechanicalSystems"
	local specObject = g_specializationManager:getSpecializationObjectByName(specName)

	for _, vehicleType in pairs(g_vehicleTypeManager.types) do
		if getIsTypeManagedByRMS(vehicleType) then
			vehicleType.specializationsByName[specName] = specObject
			table.insert(vehicleType.specializationNames, specName)
			table.insert(vehicleType.specializations, specObject)
		end
	end
end


local htPath = modDirectory .. "xml/handTools.xml"
local xmlFile = XMLFile.loadIfExists("rmsHandTools", htPath)

if xmlFile ~= nil then
    xmlFile:iterate("handTools.specializations.specialization", function(_, key)
        local name = xmlFile:getString(key .. "#name")
        local className = xmlFile:getString(key .. "#className")
        local filename = xmlFile:getString(key .. "#filename")

        g_handToolSpecializationManager:addSpecialization(name, className, modDirectory .. filename)
    end)

    xmlFile:iterate("handTools.types.type", function(_, key)
        g_handToolTypeManager:loadTypeFromXML(xmlFile.handle, key, false, nil, modName)
    end)

    xmlFile:delete()
end


--             HUD, GUI and Workshop Screen Reg

---Builds the mod state once the mission is running
function RMS_Main:onStartMission()
    RMS_Main.loadGuiProfiles()
    self.shopMenuPageInstalled = false

    RMS_WorkshopDialog.register()
    RMS_MaintenanceLogDialog.register()
    RMS_ReportDialog.register()
    RMS_InspectionDialog.register()
    RMS_SellItemDialog.register()
    RMS_MaintenanceTwoOptionsDialog.register()
    RMS_MaintenanceThreeOptionsDialog.register()
    RMS_WelcomeDialog.register()

    RMS_ProgressRing.register()

    local mission = g_currentMission
    RMS_Main.hud = RMS_Hud:new()
    RMS_Main.hud:setScale(g_gameSettings:getValue(GameSettings.SETTING.UI_SCALE))
	RMS_Main.hud:setVehicle(nil)

	table.insert(mission.hud.displayComponents, RMS_Main.hud)

	mission.hud.setControlledVehicle = Utils.appendedFunction(mission.hud.setControlledVehicle, function(self, vehicle)
		RMS_Main.hud:setVehicle(vehicle)
		RMS_Main.hud:setVisible(vehicle ~= nil and vehicle.spec_RealisticMechanicalSystems ~= nil and not vehicle.spec_RealisticMechanicalSystems.isExcludedVehicle)
	end)

	mission.hud.drawControlledEntityHUD = Utils.appendedFunction(mission.hud.drawControlledEntityHUD, function(self)
		RMS_Main.hud:draw()
	end)

    -- spec list damage fix (store and garage overwiev)
    for _, spec in ipairs(g_storeManager.specTypes) do
        if spec.name == 'wearable' then
            local origFunc = spec.getValueFunc
            spec.getValueFunc = function(s, v)
                if v ~= nil and v.spec_RealisticMechanicalSystems ~= nil and not v.spec_RealisticMechanicalSystems.isExcludedVehicle then
                    return RMS_Utils.formatTimeAgo(v:getLastMaintenanceDate())
                else
                    return origFunc(s, v)
                end
            end
        end
    end
end


---Refreshes the native trigger cards when an RMS dealer payment changes
-- @param table screen workshop screen
-- @param float dt frame duration in milliseconds
function RMS_Main.refreshWorkshopResalePrices(screen, dt)
    screen.rmsResaleRefreshTimer = (screen.rmsResaleRefreshTimer or 0) + dt
    if screen.rmsResaleRefreshTimer < 250 then
        return
    end
    screen.rmsResaleRefreshTimer = 0
    screen.rmsResaleValues = screen.rmsResaleValues or setmetatable({}, {__mode = "k"})
    for _, vehicle in ipairs(screen.vehicles or {}) do
        local spec = vehicle.spec_RealisticMechanicalSystems
        if spec ~= nil and not spec.isExcludedVehicle then
            local value = RMS_Utils.getResaleValue(vehicle, true)
            if screen.rmsResaleValues[vehicle] ~= value then
                screen.rmsResaleValues[vehicle] = value
                screen.needsListReload = true
            end
        end
    end
end

---Opens the workshop dialog in place of the vanilla repair button
-- @param table screenInstance workshop screen
function RMS_Main.onCustomRepairClick(screenInstance)
    RMS_WorkshopDialog.show(screenInstance.vehicle)
end

---Redirects the vanilla repair button to the mod workshop dialog
-- @param table screenInstance workshop screen
-- @param table? vehicle vehicle
function RMS_Main.hookRepairButton(screenInstance, vehicle)
    if screenInstance.rmsOriginalRepairCallback == nil and screenInstance.repairButton.onClickCallback ~= nil then
        screenInstance.rmsOriginalRepairCallback = screenInstance.repairButton.onClickCallback
    end
    if vehicle ~= nil and vehicle.spec_RealisticMechanicalSystems ~= nil and not vehicle.spec_RealisticMechanicalSystems.isExcludedVehicle then
        screenInstance.repairButton.onClickCallback = function()           
            RMS_Main.onCustomRepairClick(screenInstance)
        end
        screenInstance.repairButton:setDisabled(false)
    else
        screenInstance.repairButton.onClickCallback = screenInstance.rmsOriginalRepairCallback
    end
end


---Finds the native repaint control by its actual GUI callback.
-- @param table screenInstance workshop screen
-- @return table? button repaint button, when the native callback is exposed
function RMS_Main.findNativeRepaintButton(screenInstance)
    if screenInstance.rmsNativeRepaintButton ~= nil then
        return screenInstance.rmsNativeRepaintButton
    end

    local callbacks = {}
    for name, callback in pairs(WorkshopScreen) do
        if type(name) == "string" and string.find(string.lower(name), "repaint", 1, true)
            and type(callback) == "function" then
            callbacks[callback] = true
        end
    end

    local button = nil
    for _, element in ipairs(screenInstance:getDescendants()) do
        if element.target == screenInstance and callbacks[element.onClickCallback] then
            if button ~= nil then
                return nil
            end
            button = element
        end
    end

    if button ~= nil then
        screenInstance.rmsNativeRepaintButton = button
        screenInstance.rmsOriginalRepaintCallback = button.onClickCallback
    end
    return button
end


---Redirects the native repaint action for RMS vehicles only.
-- @param table screenInstance workshop screen
-- @param table? vehicle selected vehicle
function RMS_Main.hookRepaintButton(screenInstance, vehicle)
    local button = RMS_Main.findNativeRepaintButton(screenInstance)
    if button == nil then
        if vehicle ~= nil and vehicle.spec_RealisticMechanicalSystems ~= nil
            and not vehicle.spec_RealisticMechanicalSystems.isExcludedVehicle
            and not screenInstance.rmsRepaintHookWarningShown then
            Logging.warning("RMS: Native workshop repaint callback could not be identified; RMS repaint is blocked on this screen")
            screenInstance.rmsRepaintHookWarningShown = true
        end
        return
    end

    local isRmsVehicle = vehicle ~= nil and vehicle.spec_RealisticMechanicalSystems ~= nil
        and not vehicle.spec_RealisticMechanicalSystems.isExcludedVehicle
    if isRmsVehicle then
        button.onClickCallback = function()
            local workshopType = RealisticMechanicalSystems.WORKSHOP.DEALER
            if screenInstance.isOwnWorkshop then
                workshopType = RealisticMechanicalSystems.WORKSHOP.OWN
            end
            if screenInstance.isMobileWorkshop then
                workshopType = RealisticMechanicalSystems.WORKSHOP.MOBILE
            end
            if workshopType ~= RealisticMechanicalSystems.WORKSHOP.MOBILE then
                RMS_WorkshopDialog.show(screenInstance.vehicle, true)
            end
        end
        button:setText(g_i18n:getText("button_repaint"))
        button:setDisabled(screenInstance.isMobileWorkshop == true)
    else
        button.onClickCallback = screenInstance.rmsOriginalRepaintCallback
    end
end


---Stops the native repaint event on RMS vehicles
-- @param table event repaint event
-- @param function superFunc native event handler
-- @param table connection event connection
function RMS_Main.runNativeRepaintEvent(event, superFunc, connection)
    local vehicle = event.vehicle
    if vehicle ~= nil and vehicle.spec_RealisticMechanicalSystems ~= nil
        and not vehicle.spec_RealisticMechanicalSystems.isExcludedVehicle then
        return
    end
    return superFunc(event, connection)
end


---Writes the vehicle price missing from the native BuyVehicleData stream
function RMS_Main.writeBuyVehicleDataPrice(data, superFunc, streamId, connection)
    superFunc(data, streamId, connection)
    streamWriteInt32(streamId, math.floor(tonumber(data.price) or 0))
end


---Reads the vehicle price missing from the native BuyVehicleData stream
function RMS_Main.readBuyVehicleDataPrice(data, superFunc, streamId, connection)
    superFunc(data, streamId, connection)
    data.price = streamReadInt32(streamId)
end


---Detects changes to the vehicle's color configurations, custom ones included
function RMS_Main.hasConfigurationColorChange(vehicle, configurations, configurationData)
    if vehicle == nil or configurations == nil then
        return false
    end
    local storeItem = g_storeManager:getItemByXMLFilename(vehicle.configFileName)
    for _, name in ipairs(RMS_Bodywork.getColorZones(vehicle)) do
        local selectedIndex = configurations[name] or vehicle.configurations[name]
        if selectedIndex ~= vehicle.configurations[name] then
            return true, name
        end
        local item = storeItem.configurations[name][selectedIndex]
        if item ~= nil and item.isCustomColor then
            local selectedData = configurationData ~= nil and configurationData[name] ~= nil
                and configurationData[name][selectedIndex] or nil
            local currentData = vehicle.configurationData ~= nil and vehicle.configurationData[name] ~= nil
                and vehicle.configurationData[name][selectedIndex] or nil
            if (selectedData == nil) ~= (currentData == nil)
                or (selectedData ~= nil and item:hasDataChanged(selectedData, currentData)) then
                return true, name
            end
        end
    end
    return false
end

---Keeps the native color row prices aligned with the single RMS paint charge.
function RMS_Main.updateShopConfigData(screen, superFunc, storeItem, vehicle, saleItem)
    superFunc(screen, storeItem, vehicle, saleItem)
    local spec = vehicle ~= nil and vehicle.spec_RealisticMechanicalSystems or nil
    if spec == nil or spec.isExcludedVehicle then
        return
    end
    local _, firstZone = RMS_Main.hasConfigurationColorChange(
        vehicle, screen.configurations, screen.configurationData)
    local paintPrice = firstZone ~= nil and RMS_Bodywork.getPrice(
        vehicle, RMS_Bodywork.FULL, RealisticMechanicalSystems.WORKSHOP.DEALER) or nil
    for index, option in ipairs(screen.colorPickers or {}) do
        local colorElement = screen.colorElements ~= nil and screen.colorElements[index] or nil
        local configIndex = screen.configurations[option.configName]
        if colorElement ~= nil and configIndex ~= nil then
            local priceElement = colorElement.parent:getDescendantByName("price")
            screen:setConfigPrice(option.configName, configIndex, priceElement, vehicle)
            if paintPrice ~= nil and option.configName == firstZone then
                local optionPrice = storeItem.configurations[option.configName][configIndex].price
                if ConfigurationUtil.hasBoughtConfiguration(vehicle, option.configName, configIndex) then
                    optionPrice = 0
                end
                priceElement:setText("+" .. g_i18n:formatMoney(optionPrice + paintPrice))
            end
        end
    end
end

---Adds one RMS full-paint price to the native configuration quote.
function RMS_Main.getConfigurationCostsAndChanges(screen, superFunc, storeItem, vehicle, saleItem)
    local basePrice, upgradePrice, hasChanges = superFunc(screen, storeItem, vehicle, saleItem)
    local spec = vehicle ~= nil and vehicle.spec_RealisticMechanicalSystems or nil
    if spec ~= nil and not spec.isExcludedVehicle
        and RMS_Main.hasConfigurationColorChange(vehicle, screen.configurations, screen.configurationData) then
        local price = RMS_Bodywork.getPrice(vehicle, RMS_Bodywork.FULL,
            RealisticMechanicalSystems.WORKSHOP.DEALER)
        if price == nil then
            return basePrice, upgradePrice, false
        end
        upgradePrice = upgradePrice + price
    end
    return basePrice, upgradePrice, hasChanges
end

---Charges the RMS paint before the native transaction reloads the vehicle
function RMS_Main.runChangeVehicleConfigEvent(event, superFunc, connection)
    if not connection:getIsServer() and event.vehicle ~= nil and event.vehicleBuyData ~= nil then
        local spec = event.vehicle.spec_RealisticMechanicalSystems
        if spec ~= nil and not spec.isExcludedVehicle
            and RMS_Main.hasConfigurationColorChange(event.vehicle,
                event.vehicleBuyData.configurations, event.vehicleBuyData.configurationData) then
            local price = RMS_Bodywork.getPrice(event.vehicle, RMS_Bodywork.FULL,
                RealisticMechanicalSystems.WORKSHOP.DEALER)
            if price == nil or (tonumber(event.vehicleBuyData.price) or 0) < price then
                connection:sendEvent(ChangeVehicleConfigEvent.newServerToClient(false))
                return
            end
        end
    end
    return superFunc(event, connection)
end

---Loads whether RMS tracks the store item, stored under the reliability spec
local function loadIsTracked(xmlFile, customEnvironment)
    return RealisticMechanicalSystems.getIsStoreItemTracked(xmlFile, customEnvironment)
end

---Tells whether a store item gets the RMS rating, a vehicle answering for itself
local function getIsRated(storeItem, vehicle)
    if vehicle ~= nil then
        local spec = vehicle.spec_RealisticMechanicalSystems
        if spec == nil or spec.isExcludedVehicle then
            return false
        end
    elseif storeItem.specs.reliability ~= true then
        return false
    end

    return storeItem.specs.power ~= nil
end

---Returns the reliability of a store item, the vehicle value taking precedence
local function getReliability(storeItem, vehicle)
    if getIsRated(storeItem, vehicle) then
        local reliability = RealisticMechanicalSystems.getBrandReliability(vehicle, storeItem)
        return RMS_Utils.formatReliability(reliability)
    end
end

---
local function getServiceAccess(storeItem, vehicle, configurations)
    if getIsRated(storeItem, vehicle) then
        return RMS_Utils.formatServiceAccess(vehicle, storeItem, configurations)
    end
end

-- adds spec while browsing
if not g_modIsLoaded["FS25_AdvancedDamageSystem"] then
    g_storeManager:addSpecType("reliability", "shopListAttributeIconReliability", loadIsTracked, getReliability, StoreSpecies.VEHICLE)
    g_storeManager:addSpecType("serviceAccess", "shopListAttributeIconServiceAccess", RMS_Utils.loadServiceAccess, getServiceAccess, StoreSpecies.VEHICLE)
end

---Inserts a page into the shop menu
-- @param table frame shop frame
-- @param string pageName page name
-- @param table uvs icon uv coordinates
-- @param function predicateFunc tells whether the page applies to an item
-- @param string? insertAfter page the new one is placed after
function RMS_Main.addShopMenuPage(frame, pageName, uvs, predicateFunc, insertAfter)
    local targetPosition = 0

    g_shopMenu.controlIDs[pageName] = nil

    for i = 1, #g_shopMenu.pagingElement.elements do
        local child = g_shopMenu.pagingElement.elements[i]
        if child == g_shopMenu[insertAfter] then
            targetPosition = i + 1
            break
        end
    end

    if targetPosition == 0 then
        targetPosition = #g_shopMenu.pagingElement.elements + 1
    end

    g_shopMenu[pageName] = frame
    g_shopMenu.pagingElement:addElement(g_shopMenu[pageName])
    g_shopMenu:exposeControlsAsFields(pageName)

    for i = 1, #g_shopMenu.pagingElement.elements do
        local child = g_shopMenu.pagingElement.elements[i]
        if child == g_shopMenu[pageName] then
            table.remove(g_shopMenu.pagingElement.elements, i)
            table.insert(g_shopMenu.pagingElement.elements, targetPosition, child)
            break
        end
    end

    for i = 1, #g_shopMenu.pagingElement.pages do
        local child = g_shopMenu.pagingElement.pages[i]
        if child.element == g_shopMenu[pageName] then
            table.remove(g_shopMenu.pagingElement.pages, i)
            table.insert(g_shopMenu.pagingElement.pages, targetPosition, child)
            break
        end
    end

    g_shopMenu.pagingElement:updateAbsolutePosition()
    g_shopMenu.pagingElement:updatePageMapping()
    g_shopMenu:registerPage(g_shopMenu[pageName], nil, predicateFunc)
    g_shopMenu:addPageTab(g_shopMenu[pageName], Utils.getFilename("images/menuIcon.dds", modDirectory), GuiUtils.getUVs(uvs))

    for i = 1, #g_shopMenu.pageFrames do
        local child = g_shopMenu.pageFrames[i]
        if child == g_shopMenu[pageName] then
            table.remove(g_shopMenu.pageFrames, i)
            table.insert(g_shopMenu.pageFrames, targetPosition, child)
            break
        end
    end

    g_shopMenu:rebuildTabList()
end

---Clones the last menu button until the menu holds enough of them
-- @param table menu tabbed menu
-- @param integer count buttons needed
function RMS_Main.ensureMenuButtonCount(menu, count)
    if menu.menuButton == nil or menu.buttonsPanel == nil then
        return
    end

    local template = menu.menuButton[#menu.menuButton]
    if template == nil then
        return
    end

    while #menu.menuButton < count do
        local button = template:clone(menu.buttonsPanel, false, true)
        button:setVisible(false)
        table.insert(menu.menuButton, button)
    end

    menu.buttonsPanel:invalidateLayout()
end

---Registers the RMS shop page once the shop menu exists
function RMS_Main:tryRegisterShopMenuPage()
    if self.shopMenuPageInstalled then
        return true
    end

    if g_shopMenu == nil then
        return false
    end

    if g_shopMenu[RMS_InGameMenuFrame.PAGE_NAME] ~= nil then
        self.shopMenuPageInstalled = true
        return true
    end

    local frame = RMS_InGameMenuFrame.register()
    RMS_Main.addShopMenuPage(frame, RMS_InGameMenuFrame.PAGE_NAME, {0, 0, 1024, 1024}, function()
        return true
    end, "pageUsedSale")
    RMS_Main.ensureMenuButtonCount(g_shopMenu, RMS_InGameMenuFrame.MENU_BUTTON_COUNT)
    frame:initialize()

    self.shopMenuPageInstalled = true
    return true
end


---Adds the reliability attribute to a shop item
-- @param table self shop frame
-- @param table storeItem store item
-- @param table? vehicle vehicle
-- @param table? saleItem sale item
function RMS_Main.processAttributeData(self, storeItem, vehicle, saleItem)
    if vehicle ~= nil and vehicle.spec_RealisticMechanicalSystems ~= nil and not vehicle.spec_RealisticMechanicalSystems.isExcludedVehicle then
        local reliabilityItemElement = self.attributeItem:clone(self.attributesLayout)
        local reliabilityIconElement = reliabilityItemElement:getDescendantByName("icon")
        local reliabilityTextElement = reliabilityItemElement:getDescendantByName("text")

        local rel = RealisticMechanicalSystems.getBrandReliability(vehicle, nil)
        reliabilityIconElement:applyProfile("shopConfigAttributeIconReliability")
        reliabilityTextElement:setText(RMS_Utils.formatReliability(rel))
        local accessItemElement = self.attributeItem:clone(self.attributesLayout)
        accessItemElement:getDescendantByName("icon"):applyProfile("shopConfigAttributeIconServiceAccess")
        accessItemElement:getDescendantByName("text"):setText(RMS_Utils.formatServiceAccess(vehicle, storeItem, self.configurations))
        self.attributesLayout:invalidateLayout()

    end
end

---Fills a shop list cell, adding the RMS attributes to it
-- @param table self shop frame
-- @param function superFunc super function
-- @param table list list element
-- @param integer section section index
-- @param integer index row index
-- @param table cell cell element
function RMS_Main.populateCellForItemInSection(self, superFunc, list, section, index, cell)
    if list.id == 'vehiclesList' then
        local vehicle = self.vehicles[index].vehicle
        if vehicle ~= nil and vehicle.spec_RealisticMechanicalSystems ~= nil and not vehicle.spec_RealisticMechanicalSystems.isExcludedVehicle then
            superFunc(self, list, section, index, cell)
            local condition, isCompleteInspection = vehicle:getLastInspectedCondition()
            local _, isReportOutdated = vehicle:getInspectionReportAge()
            cell:getAttribute("damage"):setText(RMS_Utils.formatCondition(condition, isCompleteInspection))
            -- a report that no longer describes the machine keeps its figure, greyed out
            if isReportOutdated then
                cell:getAttribute("damage"):setTextColor(unpack(RMS_Utils.COLOR.TEXT_DIM))
            else
                cell:getAttribute("damage"):setTextColor(RMS_Utils.getConditionColor(condition, isCompleteInspection))
            end
        else
            superFunc(self, list, section, index, cell)
        end
    else
        superFunc(self, list, section, index, cell)
    end
end


-- 511 fill types instead of 255, set before the map registers its first one
FillTypeManager.SEND_NUM_BITS = math.max(FillTypeManager.SEND_NUM_BITS, 9)

FSBaseMission.onStartMission = Utils.prependedFunction(FSBaseMission.onStartMission, RMS_Main.onStartMission)
FSBaseMission.saveSavegame = Utils.appendedFunction(FSBaseMission.saveSavegame, RMS_Config.saveToXMLFile)
Mission00.loadMission00Finished = Utils.appendedFunction(Mission00.loadMission00Finished, function()
    RMS_Config.loadFromXMLFile()
    if g_currentMission:getIsServer() then
        RMS_Drivetrain.claimFromOtherMod()
    end
end)
FSBaseMission.sendInitialClientState = Utils.appendedFunction(FSBaseMission.sendInitialClientState, function(_, connection)
    if g_server ~= nil then
        connection:sendEvent(RMS_SettingsSyncEvent.new())
        RMS_TutorialStateEvent.sendToClient(connection)
    end
end)
WorkshopScreen.update = Utils.appendedFunction(WorkshopScreen.update, RMS_Main.refreshWorkshopResalePrices)
LoadTrigger.update = Utils.overwrittenFunction(LoadTrigger.update, function(trigger, superFunc, dt)
    RMS_ElectricDrive.updateLoadTrigger(trigger, superFunc, dt)
end)
WorkshopScreen.setVehicle = Utils.appendedFunction(WorkshopScreen.setVehicle, RMS_Main.hookRepairButton)
WorkshopScreen.setVehicle = Utils.appendedFunction(WorkshopScreen.setVehicle, RMS_Main.hookRepaintButton)
WearableRepaintEvent.run = Utils.overwrittenFunction(WearableRepaintEvent.run, RMS_Main.runNativeRepaintEvent)
InGameMenuStatisticsFrame.populateCellForItemInSection = Utils.overwrittenFunction(InGameMenuStatisticsFrame.populateCellForItemInSection, RMS_Main.populateCellForItemInSection)
ShopConfigScreen.processAttributeData = Utils.appendedFunction(ShopConfigScreen.processAttributeData, RMS_Main.processAttributeData)
ShopConfigScreen.getConfigurationCostsAndChanges = Utils.overwrittenFunction(
    ShopConfigScreen.getConfigurationCostsAndChanges, RMS_Main.getConfigurationCostsAndChanges)
ShopConfigScreen.updateData = Utils.overwrittenFunction(
    ShopConfigScreen.updateData, RMS_Main.updateShopConfigData)
ChangeVehicleConfigEvent.run = Utils.overwrittenFunction(
    ChangeVehicleConfigEvent.run, RMS_Main.runChangeVehicleConfigEvent)
BuyVehicleData.writeStream = Utils.overwrittenFunction(BuyVehicleData.writeStream, RMS_Main.writeBuyVehicleDataPrice)
BuyVehicleData.readStream = Utils.overwrittenFunction(BuyVehicleData.readStream, RMS_Main.readBuyVehicleDataPrice)


RMS_Main.initSpec()


RMS_Main.vehicles = {}
RMS_Main.numVehicles = 0
RMS_Main.previousKey = nil
RMS_Main.updateAlphaTimer = 0
RMS_Main.workshopCheckTimer = 0
RMS_Main.isWorkshopOpen = true
RMS_Main.currentWeather = WeatherType.SUN
RMS_Main.currentWeatherFactor = 1.0

---Recomputes whether the workshop is open from the time of day
function RMS_Main:evaluateWorkshopState()
    local currentDayHour = g_currentMission.environment.dayTime / (60 * 60 * 1000)
    return (currentDayHour >= RMS_Config.WORKSHOP.OPEN_HOUR
        and currentDayHour < RMS_Config.WORKSHOP.CLOSE_HOUR)
end

---Tells whether a workshop type ignores the opening hours
-- @param string? workshopType workshop type
-- @return boolean isAlwaysAvailable true when it never closes
function RMS_Main:isWorkshopTypeAlwaysAvailable(workshopType)
    local workshopConfig = RMS_Config.WORKSHOP

    if workshopType == RealisticMechanicalSystems.WORKSHOP.DEALER then
        return workshopConfig.DEALER_ALWAYS_AVAILABLE == true
    elseif workshopType == RealisticMechanicalSystems.WORKSHOP.MOBILE then
        return workshopConfig.MOBILE_ALWAYS_AVAILABLE == true
    elseif workshopType == RealisticMechanicalSystems.WORKSHOP.OWN then
        return workshopConfig.OWN_ALWAYS_AVAILABLE == true
    end

    return false
end

---Tells whether a workshop type accepts a service now
-- @param string? workshopType workshop type
-- @return boolean isOpen true when it is open
function RMS_Main:isWorkshopTypeOpen(workshopType)
    return self:isWorkshopTypeAlwaysAvailable(workshopType) or self.isWorkshopOpen == true
end


---Recomputes the workshop state at once and replicates it
-- @param boolean? forceNotify true to notify even without a change
function RMS_Main:forceWorkshopUpdate(forceNotify)
    local isWorkshopOpen = self:evaluateWorkshopState()
    if forceNotify or isWorkshopOpen ~= self.isWorkshopOpen then
        self.isWorkshopOpen = isWorkshopOpen
        if g_currentMission:getIsServer() then
            RMS_WorkshopChangeStatusEvent.send(self.isWorkshopOpen)
        end
        g_messageCenter:publish(MessageType.RMS_WORKSHOP_CHANGE_STATUS, self.isWorkshopOpen)
    end
end

---Runs the per period upkeep of every tracked vehicle
function RMS_Main:onPeriodChanged()
    if not g_currentMission:getIsServer() then
        return
    end

    for _, vehicle in pairs(self.vehicles) do
        RMS_Consumables.onLubricationPeriodChanged(vehicle)
    end
end

---Refreshes the open workshop when its vehicle status or resale payment changes
local function updateOpenWorkshopDialog()
    local dialog = RMS_WorkshopDialog.INSTANCE
    if dialog == nil or not dialog.isDialogOpen or dialog.vehicle == nil or dialog.vehicle.spec_RealisticMechanicalSystems == nil then
        return
    end

    local currentStatus = dialog.vehicle:getCurrentStatus()
    if dialog.lastObservedStatus ~= currentStatus
        or dialog.lastResaleValue ~= RMS_Utils.getResaleValue(dialog.vehicle,
            dialog.workshopType == RealisticMechanicalSystems.WORKSHOP.DEALER) then
        dialog:updateScreen()
    end
end


---Runs the mod update: workshop hours and the simulation step of every vehicle
-- @param float dt time since last call in ms
function RMS_Main:update(dt)
    if g_currentMission:getIsClient() then
        if not self.shopMenuPageInstalled then
            self:tryRegisterShopMenuPage()
        end
    end

    -- workshop
    self.workshopCheckTimer = self.workshopCheckTimer + dt
    if self.workshopFirstEval == nil or self.workshopCheckTimer >= RMS_Config.CORE_UPDATE_DELAY then
        self.workshopFirstEval = true
        self:forceWorkshopUpdate()
        if self.workshopCheckTimer >= RMS_Config.CORE_UPDATE_DELAY then
            self.workshopCheckTimer = self.workshopCheckTimer % RMS_Config.CORE_UPDATE_DELAY
        end
    end

    -- a running engine keeps its machine updating on every game, for its breakdown noises, smoke and gauges
    for _, vehicle in pairs(g_currentMission.vehicleSystem.vehicles) do
        local spec = vehicle.spec_RealisticMechanicalSystems
        if spec ~= nil and not spec.isExcludedVehicle and vehicle.isActive ~= true and vehicle:getMotorState() == MotorState.ON then
            vehicle:raiseActive()
        end
    end

    if not g_currentMission:getIsServer() or self.numVehicles == 0 then
        self.previousKey = nil
        updateOpenWorkshopDialog()
        return
    end

    self.updateAlphaTimer = self.updateAlphaTimer + dt

    -- vehicles
    local timePerVehicle = RMS_Config.CORE_UPDATE_DELAY / self.numVehicles
    local vehiclesToUpdate = math.floor(self.updateAlphaTimer / timePerVehicle)

    if vehiclesToUpdate < 1 then
        updateOpenWorkshopDialog()
        return
    end

    for i = 1, vehiclesToUpdate do
        local vehicle = nil
        self.previousKey, vehicle = next(self.vehicles, self.previousKey)

        if self.previousKey == nil and self.numVehicles > 0 then
             self.previousKey, vehicle = next(self.vehicles)
        end
        
        if vehicle ~= nil and vehicle.spec_RealisticMechanicalSystems ~= nil and not vehicle.spec_RealisticMechanicalSystems.isExcludedVehicle then
            vehicle:rmsUpdate(RMS_Config.CORE_UPDATE_DELAY, self.isWorkshopOpen)

            -- meta
            local spec = vehicle.spec_RealisticMechanicalSystems
            spec.metaUpdateTimer = spec.metaUpdateTimer + RMS_Config.CORE_UPDATE_DELAY
            if spec.metaUpdateTimer > RMS_Config.META_UPDATE_DELAY then

                RMS_Main.currentWeather = g_currentMission.environment.weather:getCurrentWeatherType()
                if RMS_Main.currentWeather == WeatherType.RAIN then
                    RMS_Main.currentWeatherFactor = RMS_Config.CORE.RAIN_FACTOR or 1.0
                elseif RMS_Main.currentWeather == WeatherType.SNOW then
                    RMS_Main.currentWeatherFactor = RMS_Config.CORE.SNOW_FACTOR or 1.0
                elseif RMS_Main.currentWeather == WeatherType.HAIL then
                    RMS_Main.currentWeatherFactor = RMS_Config.CORE.HAIL_FACTOR or 1.0
                else
                    RMS_Main.currentWeatherFactor = 1.0
                end

                if not vehicle:getIsOperating() then
                    spec.isUnderRoof = vehicle:isUnderRoof()
                end

                spec.metaUpdateTimer = spec.metaUpdateTimer - RMS_Config.META_UPDATE_DELAY
  
            end
        end
    end
    self.updateAlphaTimer = self.updateAlphaTimer - vehiclesToUpdate * timePerVehicle
    updateOpenWorkshopDialog()
end

---Loads the RMS map state and GUI registrations
function RMS_Main:loadMap()
    RMS_Main.loadGuiProfiles()
    RMS_SettingsPage.reset()
    self.shopMenuPageInstalled = false
    RMS_Config.resetTutorialStateSession()
    RMS_Config.loadFromXMLFile()
    self:tryRegisterShopMenuPage()

    if g_currentMission:getIsServer() then
        g_messageCenter:subscribe(MessageType.PERIOD_CHANGED, self.onPeriodChanged, self)
    end

    local soundsXmlFile = loadXMLFile("rmsSounds2D", Utils.getFilename("sounds/rms_sounds.xml", modDirectory))
    self.samples = {
        notification2D = g_soundManager:loadSample2DFromXML(soundsXmlFile, "sounds", "notification2D", modDirectory, 1, AudioGroup.GUI),
        maintenanceCompleted2D = g_soundManager:loadSample2DFromXML(soundsXmlFile, "sounds", "maintenanceCompleted2D", modDirectory, 1, AudioGroup.GUI)
    }
    delete(soundsXmlFile)
end

---
function RMS_Main:deleteMap()
    g_messageCenter:unsubscribe(MessageType.PERIOD_CHANGED, self)
    self.shopMenuPageInstalled = false
    RMS_Main.guiProfilesLoaded = nil
    RMS_Config._loaded = nil
    RMS_Config.resetTutorialStateSession()
    RMS_SettingsPage.reset()
    RMS_Exhaust.plumeSources = nil

    g_soundManager:deleteSamples(self.samples)
    self.samples = nil
end

addModEventListener(RMS_Main)
