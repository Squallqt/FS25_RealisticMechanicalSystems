-- Copyright © 2026 Squallqt. All rights reserved.

---RMS mission integration.
RMS_Main = {}

RMS_SoundManager = {}

---Plays a sample once
-- @param table? sample audio sample
-- @param table? afterSample sample whose end starts this one
function RMS_SoundManager.playSample(sample, afterSample)
    if sample ~= nil then
        g_soundManager:playSample(sample, 0, afterSample)
    end
end

---Stops a sample, its delay and fade out in ms
function RMS_SoundManager.stopSample(sample, delay, fadeOut)
    if sample ~= nil then
        g_soundManager:stopSample(sample, delay, fadeOut)
    end
end

---Tells whether a sample is playing
function RMS_SoundManager.getIsSamplePlaying(sample)
    return sample ~= nil and g_soundManager:getIsSamplePlaying(sample)
end

---Starts or stops a looping sample, its stop delay and fade out in ms
function RMS_SoundManager.setSamplePlaying(sample, shouldPlay, delay, fadeOut)
    if sample == nil then
        return
    end

    local isPlaying = RMS_SoundManager.getIsSamplePlaying(sample)
    if shouldPlay and not isPlaying then
        RMS_SoundManager.playSample(sample)
    elseif not shouldPlay and isPlaying then
        RMS_SoundManager.stopSample(sample, delay, fadeOut)
    end
end

---Sets the pitch offset of a sample
function RMS_SoundManager.setSamplePitchOffset(sample, pitchOffset)
    if sample ~= nil then
        g_soundManager:setSamplePitchOffset(sample, pitchOffset)
    end
end

---Plays a sample from a point of its recording
-- @param table sample audio sample
-- @param float offset point of the recording in ms
function RMS_SoundManager.playSampleFrom(sample, offset)
    if sample.isEmptySample or sample.soundSample == nil then
        return
    end
    local volume = g_soundManager:getModifierFactor(sample, "volume") * g_soundManager:getCurrentSampleVolume(sample)
    playSample(sample.soundSample, sample.loops, volume, offset, 0, 0)
end

---Returns the length of the start recording of an engine sound
-- @param table sample audio sample
-- @return float duration duration in ms, 0 for a sound without one
function RMS_SoundManager.getSampleStartDuration(sample)
    return g_soundManager:getSampleLoopSynthesisStartDuration(sample)
end

---Returns the volume of a sample before its offset
function RMS_SoundManager.getSampleVolume(sample)
    return sample.current.volume * g_soundManager:getCurrentFadeFactor(sample) * sample.volumeScale
end

---Sets the volume offset of a sample
function RMS_SoundManager.setSampleVolumeOffset(sample, volumeOffset)
    if sample ~= nil then
        g_soundManager:setSampleVolumeOffset(sample, volumeOffset)
    end
end

local modDirectory = g_currentModDirectory
local modName = g_currentModName

RMS_Main.BREAKDOWN_TEXTS = {
    br = "translations/breakdowns/l10n_br.xml",
    cs = "translations/breakdowns/l10n_cs.xml",
    ct = "translations/breakdowns/l10n_ct.xml",
    cz = "translations/breakdowns/l10n_cz.xml",
    da = "translations/breakdowns/l10n_da.xml",
    de = "translations/breakdowns/l10n_de.xml",
    ea = "translations/breakdowns/l10n_ea.xml",
    en = "translations/breakdowns/l10n_en.xml",
    es = "translations/breakdowns/l10n_es.xml",
    fc = "translations/breakdowns/l10n_fc.xml",
    fi = "translations/breakdowns/l10n_fi.xml",
    fr = "translations/breakdowns/l10n_fr.xml",
    hu = "translations/breakdowns/l10n_hu.xml",
    id = "translations/breakdowns/l10n_id.xml",
    it = "translations/breakdowns/l10n_it.xml",
    jp = "translations/breakdowns/l10n_jp.xml",
    kr = "translations/breakdowns/l10n_kr.xml",
    nl = "translations/breakdowns/l10n_nl.xml",
    no = "translations/breakdowns/l10n_no.xml",
    pl = "translations/breakdowns/l10n_pl.xml",
    pt = "translations/breakdowns/l10n_pt.xml",
    ro = "translations/breakdowns/l10n_ro.xml",
    ru = "translations/breakdowns/l10n_ru.xml",
    sv = "translations/breakdowns/l10n_sv.xml",
    tr = "translations/breakdowns/l10n_tr.xml",
    uk = "translations/breakdowns/l10n_uk.xml",
    vi = "translations/breakdowns/l10n_vi.xml"
}

---Adds the breakdown texts of the game language
function RMS_Main.loadBreakdownTexts()
    local filename = RMS_Main.BREAKDOWN_TEXTS[g_languageShort] or RMS_Main.BREAKDOWN_TEXTS.en
    local xmlFile = XMLFile.load("rmsBreakdownTexts", modDirectory .. filename)
    xmlFile:iterate("l10n.texts.text", function(_, key)
        g_i18n:setText(xmlFile:getString(key .. "#name"), xmlFile:getString(key .. "#text"))
    end)
    xmlFile:delete()
end

RMS_Main.loadBreakdownTexts()

source(g_currentModDirectory .. "scripts/RMS_Config.lua")
source(g_currentModDirectory .. "scripts/RMS_Utils.lua")
source(g_currentModDirectory .. "scripts/RMS_Fluids.lua")
source(g_currentModDirectory .. "scripts/RMS_FluidTransfer.lua")
source(g_currentModDirectory .. "scripts/RMS_FluidStorage.lua")
source(g_currentModDirectory .. "scripts/RMS_Bodywork.lua")
source(g_currentModDirectory .. "scripts/RMS_EngineRemap.lua")
source(g_currentModDirectory .. "scripts/RMS_FluidWorkshop.lua")
source(g_currentModDirectory .. "scripts/RMS_ProgressRing.lua")
source(g_currentModDirectory .. "scripts/RMS_ProductionYearData.lua")
source(g_currentModDirectory .. "scripts/RMS_ProductionYear.lua")
source(g_currentModDirectory .. "scripts/objects/RMS_BatteryChargerAimData.lua")
source(g_currentModDirectory .. "scripts/RMS_DebugReading.lua")
source(g_currentModDirectory .. "scripts/RMS_DebugWindow.lua")
source(g_currentModDirectory .. "scripts/RMS_Leasing.lua")
source(g_currentModDirectory .. "scripts/RMS_Tutorial.lua")
source(g_currentModDirectory .. "scripts/RMS_Hud.lua")
source(g_currentModDirectory .. "scripts/RMS_PlayerInput.lua")
source(g_currentModDirectory .. "events/RMS_VehicleChangeStatusEvent.lua")
source(g_currentModDirectory .. "events/RMS_WorkshopChangeStatusEvent.lua")
source(g_currentModDirectory .. "events/RMS_ServiceRequestEvent.lua")
source(g_currentModDirectory .. "events/RMS_BodyworkColorEvent.lua")
source(g_currentModDirectory .. "events/RMS_ServiceResultEvent.lua")
source(g_currentModDirectory .. "events/RMS_FluidTransferRequestEvent.lua")
source(g_currentModDirectory .. "events/RMS_BatteryChargerRequestEvent.lua")
source(g_currentModDirectory .. "events/RMS_DiagnosticRequestEvent.lua")
source(g_currentModDirectory .. "events/RMS_CancelServiceEvent.lua")
source(g_currentModDirectory .. "events/RMS_SettingsSyncEvent.lua")
source(g_currentModDirectory .. "events/RMS_TutorialStateEvent.lua")
source(g_currentModDirectory .. "events/RMS_EffectSyncEvent.lua")
source(g_currentModDirectory .. "events/RMS_LogEntrySyncEvent.lua")
source(g_currentModDirectory .. "events/RMS_ConsoleCommandEvent.lua")
source(g_currentModDirectory .. "events/RMS_VehicleExclusionEvent.lua")
source(g_currentModDirectory .. "events/RMS_StartEvent.lua")
source(g_currentModDirectory .. "events/RMS_FieldInspectionEvent.lua")
source(g_currentModDirectory .. "events/RMS_BatteryIsolatorEvent.lua")
source(g_currentModDirectory .. "events/RMS_AirBlowerEvent.lua")
source(g_currentModDirectory .. "events/RMS_JumperCablesEvent.lua")
source(g_currentModDirectory .. "events/RMS_DrivetrainEvent.lua")
source(g_currentModDirectory .. "events/RMS_TripResetEvent.lua")
source(g_currentModDirectory .. "events/RMS_FanReversalEvent.lua")
source(g_currentModDirectory .. "events/RMS_DebugReadingEvent.lua")



---Declares the RMS specialization to the vehicle type manager
function RMS_Main.initSpec()
    g_specializationManager:addSpecialization("RealisticMechanicalSystems", "RealisticMechanicalSystems", g_currentModDirectory.."scripts/core/RMS_Specialization.lua", "")
    g_specializationManager:addSpecialization("rmsImplementGreasing", "RMS_ImplementGreasing", g_currentModDirectory .. "scripts/RMS_ImplementGreasing.lua", "")
    TypeManager.finalizeTypes = Utils.appendedFunction(TypeManager.finalizeTypes, RMS_Main.registerSpecializationToVehicles)
end

local RMS_REQUIRED_SPECIALIZATIONS = {"motorized", "wheels", "enterable"}

local RMS_REJECTED_SPECIALIZATIONS = {"pushHandTool", "locomotive", "motorbike"}

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

local function getIsImplementType(vehicleType)
	local specializations = vehicleType.specializationsByName
	return specializations.attachable ~= nil and specializations.wearable ~= nil
		and specializations.RealisticMechanicalSystems == nil and specializations.rmsImplementGreasing == nil
end

local function addSpecialization(vehicleType, specName)
	local specObject = g_specializationManager:getSpecializationObjectByName(specName)
	vehicleType.specializationsByName[specName] = specObject
	table.insert(vehicleType.specializationNames, specName)
	table.insert(vehicleType.specializations, specObject)
end

---Attaches RMS to the machines and the greasing to the implements
function RMS_Main.registerSpecializationToVehicles()
	for _, vehicleType in pairs(g_vehicleTypeManager.types) do
		if getIsTypeManagedByRMS(vehicleType) then
			addSpecialization(vehicleType, "RealisticMechanicalSystems")
		elseif getIsImplementType(vehicleType) then
			addSpecialization(vehicleType, "rmsImplementGreasing")
		end
	end
end


---Declares the hand tools of the mod, specializations before types
function RMS_Main.loadHandToolTypes()
    local declarations = XMLFile.load("rmsHandTools", modDirectory .. "xml/handTools.xml")
    declarations:iterate("handTools.specializations.specialization", function(_, path)
        g_handToolSpecializationManager:addSpecialization(declarations:getString(path .. "#name"),
            declarations:getString(path .. "#className"), modDirectory .. declarations:getString(path .. "#filename"))
    end)
    declarations:iterate("handTools.types.type", function(_, path)
        g_handToolTypeManager:loadTypeFromXML(declarations.handle, path, false, nil, modName)
    end)
    declarations:delete()
end

RMS_Main.loadHandToolTypes()


---Builds the mod state once the mission is running
function RMS_Main:onStartMission()
    RMS_Gui.loadResources()
    RMS_Gui.loadScreens()

    local hud = RMS_Hud:new()
    hud:setScale(g_gameSettings:getValue(GameSettings.SETTING.UI_SCALE))
    hud:setVehicle(nil)
    RMS_Main.hud = hud

    -- Drawn after the vehicle HUD, fed the vehicle the game controls
    local gameHud = g_currentMission.hud
    table.insert(gameHud.displayComponents, hud)
    gameHud.setControlledVehicle = Utils.appendedFunction(gameHud.setControlledVehicle, function(_, vehicle)
        hud:setVehicle(vehicle)
    end)
    gameHud.drawControlledEntityHUD = Utils.appendedFunction(gameHud.drawControlledEntityHUD, function()
        hud:draw()
    end)

    -- Condition line of the shop, RMS first, the game for the rest
    local condition = g_storeManager:getSpecTypeByName("wearable")
    local getGameCondition = condition.getValueFunc
    condition.getValueFunc = function(storeItem, realItem, configurations, saleItem)
        return RMS_Main.getShopCondition(storeItem, realItem, saleItem)
            or getGameCondition(storeItem, realItem, configurations, saleItem)
    end
end


---Refreshes the native trigger cards when an RMS dealer payment changes
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

---Workshop a vanilla workshop screen stands for
function RMS_Main.getWorkshopType(screenInstance)
    local WORKSHOP = RealisticMechanicalSystems.WORKSHOP
    if screenInstance.isMobileWorkshop then
        return WORKSHOP.MOBILE
    elseif screenInstance.isOwnWorkshop then
        return WORKSHOP.OWN
    end
    return WORKSHOP.DEALER
end

---Opens the workshop dialog in place of the vanilla repair button
function RMS_Main.onCustomRepairClick(screenInstance)
    RMS_WorkshopDialog.show(screenInstance.vehicle, RMS_Main.getWorkshopType(screenInstance))
end

---Redirects the vanilla repair button to the mod workshop dialog
function RMS_Main.hookRepairButton(screenInstance, vehicle)
    local button = screenInstance.repairButton
    if screenInstance.rmsOriginalRepairCallback == nil and button.onClickCallback ~= nil then
        screenInstance.rmsOriginalRepairCallback = button.onClickCallback
    end
    local spec = vehicle ~= nil and vehicle.spec_RealisticMechanicalSystems or nil
    if spec == nil or spec.isExcludedVehicle then
        button.onClickCallback = screenInstance.rmsOriginalRepairCallback
        return
    end
    button.onClickCallback = function()
        RMS_Main.onCustomRepairClick(screenInstance)
    end
    button:setDisabled(false)
end


---Finds the native repaint control by its actual GUI callback.
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
            RMS_WorkshopDialog.show(screenInstance.vehicle, RMS_Main.getWorkshopType(screenInstance), RealisticMechanicalSystems.STATUS.BODYWORK)
        end
        button:setText(g_i18n:getText("button_repaint"))
        button:setDisabled(screenInstance.isMobileWorkshop == true)
    else
        button.onClickCallback = screenInstance.rmsOriginalRepaintCallback
    end
end


---Stops the native repaint event on RMS vehicles
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


---Hides the colors a full repaint changes from an owned machine
-- @param table? vehicle owned machine, nil in the shop
function RMS_Main.removeShopConfigPaintColors(screen, storeItem, vehicle)
    local spec = vehicle ~= nil and vehicle.spec_RealisticMechanicalSystems or nil
    if spec == nil or spec.isExcludedVehicle then
        return
    end
    local paintZones = {}
    for _, zone in ipairs(RMS_Bodywork.getColorZones(vehicle)) do
        paintZones[zone] = true
    end
    local colorPickers = {}
    for _, option in ipairs(screen.colorPickers) do
        if not paintZones[option.configName] then
            table.insert(colorPickers, option)
        end
    end
    screen.colorPickers = colorPickers
    screen.displayableColorCount = #colorPickers
end

---Keeps an owned machine's paint whatever the configurator picks
-- @param table? vehicle owned machine, nil in the shop
function RMS_Main.keepShopConfigPaintColors(screen, storeItem, vehicle)
    local spec = vehicle ~= nil and vehicle.spec_RealisticMechanicalSystems or nil
    if spec == nil or spec.isExcludedVehicle then
        return
    end
    for _, zone in ipairs(RMS_Bodywork.getColorZones(vehicle)) do
        screen.configurations[zone] = vehicle.configurations[zone]
        local data = vehicle.configurationData ~= nil and vehicle.configurationData[zone] or nil
        screen.configurationData[zone] = data ~= nil and table.clone(data, math.huge) or nil
    end
end

---Prices a purchase's colors at the RMS paint instead of their options
function RMS_Main.getBuyPaintPrice(manager, superFunc, storeItem, configurations, saleItem)
    local price, upgradePrice = superFunc(manager, storeItem, configurations, saleItem)
    if configurations ~= nil then
        local paintPrice, optionPrice = RMS_Bodywork.getPurchaseColorPrices(storeItem, configurations, saleItem)
        if paintPrice ~= nil then
            price = price - optionPrice + paintPrice
            upgradePrice = upgradePrice - optionPrice + paintPrice
        end
    end
    return price, upgradePrice
end

---Writes the paint on the first color row changed, 0 on the others
function RMS_Main.setShopConfigPaintPrice(screen, superFunc, configName, configIndex, priceElement, vehicle)
    superFunc(screen, configName, configIndex, priceElement, vehicle)
    if vehicle == nil and screen.storeItem.configurations[configName][configIndex]:isa(VehicleConfigurationItemColor) then
        local paintPrice, _, paintedZone = RMS_Bodywork.getPurchaseColorPrices(
            screen.storeItem, screen.configurations, screen.saleItem)
        if paintPrice ~= nil then
            priceElement:setText("+" .. g_i18n:formatMoney(paintedZone == configName and paintPrice or 0))
        end
    end
end

---Rewrites the price of every color row once a choice changes
function RMS_Main.updateShopConfigPaintPrices(screen, storeItem, vehicle)
    if vehicle ~= nil then
        return
    end
    for index, option in ipairs(screen.colorPickers) do
        local colorElement = screen.colorElements[index]
        if colorElement ~= nil then
            screen:setConfigPrice(option.configName, screen.configurations[option.configName],
                colorElement.parent:getDescendantByName("price"), vehicle)
        end
    end
end

local function loadIsTracked(xmlFile, customEnvironment)
    return RealisticMechanicalSystems.getIsStoreItemTracked(xmlFile, customEnvironment)
end

---Tells whether the shop rates a tracked machine or store item
local function getIsRated(storeItem, vehicle)
    local isTracked = storeItem.specs.reliability == true
    if vehicle ~= nil then
        local spec = vehicle.spec_RealisticMechanicalSystems
        isTracked = spec ~= nil and not spec.isExcludedVehicle
    end
    return isTracked and storeItem.specs.power ~= nil
end

local function getLaunchYear(storeItem, vehicle)
    if getIsRated(storeItem, vehicle) then
        local year, source = RMS_ProductionYear.getYear(storeItem)
        if source == RMS_ProductionYear.SOURCE.UNKNOWN then
            return g_i18n:getText("rms_shop_launch_year_unknown")
        end
        return string.format(g_i18n:getText("rms_shop_launch_year"), year)
    end
end

local function getReliability(storeItem, vehicle)
    if getIsRated(storeItem, vehicle) then
        local reliability = RealisticMechanicalSystems.getBrandReliability(vehicle, storeItem)
        return RMS_Utils.formatReliability(reliability, true)
    end
end

local function getServiceAccess(storeItem, vehicle, configurations)
    if getIsRated(storeItem, vehicle) then
        return RMS_Utils.formatServiceAccess(vehicle, storeItem, configurations, true)
    end
end

-- @return string? text attribute, nil for an item RMS leaves to the game
function RMS_Main.getShopCondition(storeItem, realItem, saleItem)
    if realItem ~= nil then
        local spec = realItem.spec_RealisticMechanicalSystems
        if spec ~= nil and not spec.isExcludedVehicle then
            return RMS_Utils.formatShopLastMaintenance(realItem:getLastMaintenanceDate())
        end
    elseif saleItem ~= nil and getIsRated(storeItem, nil) then
        return RMS_Utils.formatOwnerCare(saleItem.damage)
    end
end

---Keeps a sold machine's RMS state on the used offer it becomes
function RMS_Main.onVehicleWillSell(saleSystem, superFunc, vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    if spec == nil or spec.isExcludedVehicle or spec.isNewToRMS then
        return superFunc(saleSystem, vehicle)
    end
    local items = saleSystem:getItems()
    local count = #items
    if vehicle.setDamageAmount ~= nil then
        vehicle:setDamageAmount(RMS_Utils.getOwnerCareDamage(RMS_Utils.getSellerCare(vehicle)), true)
    end
    superFunc(saleSystem, vehicle)
    if #items > count then
        items[#items].rmsState = RealisticMechanicalSystems.saveStateToMemory(vehicle)
    end
end

local function getSaleItem(saleSystem, xmlFile, key)
    local xmlFilename = xmlFile:getString(key .. "#xmlFilename")
    local age = xmlFile:getInt(key .. "#age")
    local operatingTime = xmlFile:getFloat(key .. "#operatingTime") * 1000
    for _, item in ipairs(saleSystem:getItems()) do
        if item.xmlFilename == xmlFilename and item.age == age and math.abs(item.operatingTime - operatingTime) < 1 then
            return item
        end
    end
end

---Writes in the sales file the RMS state each used offer carries
function RMS_Main.saveVehicleSales(saleSystem, superFunc, xmlFilename)
    local isSaved = superFunc(saleSystem, xmlFilename)
    local xmlFile = XMLFile.loadIfExists("rmsVehicleSales", xmlFilename)
    if xmlFile ~= nil then
        xmlFile:iterate("sales.item", function(_, key)
            local item = getSaleItem(saleSystem, xmlFile, key)
            if item ~= nil and item.rmsState ~= nil then
                xmlFile:setString(key .. "#rmsState", item.rmsState)
            end
        end)
        xmlFile:save()
        xmlFile:delete()
    end
    return isSaved
end

---Reads from the sales file the RMS state each used offer carries
function RMS_Main.loadVehicleSales(saleSystem, superFunc, xmlFilename)
    local isLoaded = superFunc(saleSystem, xmlFilename)
    local xmlFile = XMLFile.loadIfExists("rmsVehicleSales", xmlFilename)
    if xmlFile ~= nil then
        xmlFile:iterate("sales.item", function(_, key)
            local state = xmlFile:getString(key .. "#rmsState")
            local item = state ~= nil and getSaleItem(saleSystem, xmlFile, key) or nil
            if item ~= nil then
                item.rmsState = state
            end
        end)
        xmlFile:delete()
    end
    return isLoaded
end

g_storeManager:addSpecType("reliability", "shopListAttributeIconReliability", loadIsTracked, getReliability, StoreSpecies.VEHICLE)
g_storeManager:addSpecType("serviceAccess", "shopListAttributeIconServiceAccess", RMS_Utils.loadServiceAccess, getServiceAccess, StoreSpecies.VEHICLE)
g_storeManager:addSpecType("rmsLaunchYear", "shopListAttributeIconRmsLaunchYear", nil, getLaunchYear, StoreSpecies.VEHICLE)

---Moves the entry a test picks to a position of a list
local function moveEntry(list, isEntry, position)
    for index, entry in ipairs(list) do
        if isEntry(entry) then
            table.remove(list, index)
            table.insert(list, position, entry)
            return
        end
    end
end

---Inserts the RMS page in the shop menu, after the used sales
function RMS_Main.addShopMenuPage(menu, frame)
    local pageName = RMS_InGameMenuFrame.PAGE_NAME
    local paging = menu.pagingElement
    local position = #paging.elements + 1
    for index, element in ipairs(paging.elements) do
        if element == menu.pageUsedSale then
            position = index + 1
            break
        end
    end

    menu[pageName] = frame
    paging:addElement(frame)
    menu:exposeControlsAsFields(pageName)
    -- PagingElement:addElement appends: element and page go to the position
    moveEntry(paging.elements, function(element) return element == frame end, position)
    moveEntry(paging.pages, function(page) return page.element == frame end, position)
    paging:updateAbsolutePosition()
    paging:updatePageMapping()

    menu:registerPage(frame, position, function() return true end)
    menu:addPageTab(frame, Utils.getFilename("images/menuIcon.png", modDirectory), GuiUtils.getUVs({0, 0, 1024, 1024}))
    menu:rebuildTabList()
end

---Clones the last menu button until the menu holds enough of them
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

---Adds the RMS page to the shop menu once the menu exists
function RMS_Main:tryRegisterShopMenuPage()
    local menu = g_shopMenu
    if menu == nil or menu[RMS_InGameMenuFrame.PAGE_NAME] ~= nil then
        return
    end
    local frame = RMS_InGameMenuFrame.register()
    RMS_Main.addShopMenuPage(menu, frame)
    RMS_Main.ensureMenuButtonCount(menu, RMS_InGameMenuFrame.MENU_BUTTON_COUNT)
    frame:initialize()
end


---Adds an icon and its text to the attributes of the shop configurator
local function addShopAttribute(screen, iconProfile, text)
    local attribute = screen.attributeItem:clone(screen.attributesLayout)
    attribute:getDescendantByName("icon"):applyProfile(iconProfile)
    attribute:getDescendantByName("text"):setText(text)
end

---Adds reliability, service access and launch year of an owned machine
function RMS_Main.processAttributeData(screen, storeItem, vehicle)
    local spec = vehicle ~= nil and vehicle.spec_RealisticMechanicalSystems or nil
    if spec == nil or spec.isExcludedVehicle then
        return
    end
    local reliability = RealisticMechanicalSystems.getBrandReliability(vehicle, nil)
    addShopAttribute(screen, "shopConfigAttributeIconReliability", RMS_Utils.formatReliability(reliability, true))
    addShopAttribute(screen, "shopConfigAttributeIconServiceAccess",
        RMS_Utils.formatServiceAccess(vehicle, storeItem, screen.configurations, true))
    local launchYear = getLaunchYear(storeItem, vehicle)
    if launchYear ~= nil then
        addShopAttribute(screen, "shopConfigAttributeIconRmsLaunchYear", launchYear)
    end
    screen.attributesLayout:invalidateLayout()
end

---Shows the last inspected condition in the statistics vehicle list
function RMS_Main.populateCellForItemInSection(frame, superFunc, list, section, index, cell)
    superFunc(frame, list, section, index, cell)
    local vehicle = list.id == "vehiclesList" and frame.vehicles[index].vehicle or nil
    local spec = vehicle ~= nil and vehicle.spec_RealisticMechanicalSystems or nil
    if spec == nil or spec.isExcludedVehicle then
        return
    end
    local condition, isComplete = vehicle:getLastInspectedCondition()
    local _, isOutdated = vehicle:getInspectionReportAge()
    local conditionText = cell:getAttribute("damage")
    conditionText:setText(RMS_Utils.formatCondition(condition, isComplete))
    -- An outdated report is dimmed, a current one coloured by its condition
    if isOutdated then
        conditionText:setTextColor(unpack(RMS_Utils.COLOR.TEXT_DIM))
    else
        conditionText:setTextColor(RMS_Utils.getConditionColor(condition, isComplete))
    end
end

---Keeps the tools on the trolley out of the hand tools menu
function RMS_Main.getCanPickupHandToolFromMenu(holder, superFunc, handTool)
    return holder.parent[RMS_BatteryCharger.SPEC_TABLE_NAME] == nil and superFunc(holder, handTool)
end

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
HandToolHolder.getCanPickupHandToolFromMenu = Utils.overwrittenFunction(HandToolHolder.getCanPickupHandToolFromMenu, RMS_Main.getCanPickupHandToolFromMenu)
ShopConfigScreen.processAttributeData = Utils.appendedFunction(ShopConfigScreen.processAttributeData, RMS_Main.processAttributeData)
ShopConfigScreen.processStoreItemConfigurations = Utils.appendedFunction(
    ShopConfigScreen.processStoreItemConfigurations, RMS_Main.removeShopConfigPaintColors)
ShopConfigScreen.updateData = Utils.prependedFunction(ShopConfigScreen.updateData, RMS_Main.keepShopConfigPaintColors)
ShopConfigScreen.updateData = Utils.appendedFunction(ShopConfigScreen.updateData, RMS_Main.updateShopConfigPaintPrices)
ShopConfigScreen.setConfigPrice = Utils.overwrittenFunction(ShopConfigScreen.setConfigPrice, RMS_Main.setShopConfigPaintPrice)
EconomyManager.getBuyPrice = Utils.overwrittenFunction(EconomyManager.getBuyPrice, RMS_Main.getBuyPaintPrice)
BuyVehicleData.writeStream = Utils.overwrittenFunction(BuyVehicleData.writeStream, RMS_Main.writeBuyVehicleDataPrice)
BuyVehicleData.readStream = Utils.overwrittenFunction(BuyVehicleData.readStream, RMS_Main.readBuyVehicleDataPrice)
VehicleSaleSystem.onVehicleWillSell = Utils.overwrittenFunction(VehicleSaleSystem.onVehicleWillSell, RMS_Main.onVehicleWillSell)
VehicleSaleSystem.saveToXMLFile = Utils.overwrittenFunction(VehicleSaleSystem.saveToXMLFile, RMS_Main.saveVehicleSales)
VehicleSaleSystem.loadFromXMLFile = Utils.overwrittenFunction(VehicleSaleSystem.loadFromXMLFile, RMS_Main.loadVehicleSales)


RMS_Main.initSpec()

-- the screens read the names the specialization gives
source(g_currentModDirectory .. "gui/RMS_Chart.lua")
source(g_currentModDirectory .. "gui/RMS_WorkshopOrders.lua")
source(g_currentModDirectory .. "gui/RMS_WorkshopPage.lua")
source(g_currentModDirectory .. "gui/RMS_ConditionCardFrame.lua")
source(g_currentModDirectory .. "gui/RMS_WorkshopStatusFrame.lua")
source(g_currentModDirectory .. "gui/RMS_ReportFrame.lua")
source(g_currentModDirectory .. "gui/RMS_WorkshopSummaryFrame.lua")
source(g_currentModDirectory .. "gui/RMS_WorkshopDiagnosticFrame.lua")
source(g_currentModDirectory .. "gui/RMS_WorkshopInterventionsFrame.lua")
source(g_currentModDirectory .. "gui/RMS_WorkshopRecordFrame.lua")
source(g_currentModDirectory .. "gui/RMS_WorkshopDialog.lua")
source(g_currentModDirectory .. "gui/RMS_InspectionDialog.lua")
source(g_currentModDirectory .. "gui/RMS_SellItemDialog.lua")
source(g_currentModDirectory .. "gui/RMS_InGameMenuFrame.lua")
source(g_currentModDirectory .. "gui/RMS_DiagnosticScreen.lua")
source(g_currentModDirectory .. "gui/RMS_SettingsPage.lua")
source(g_currentModDirectory .. "gui/RMS_Gui.lua")


RMS_Main.vehicles = {}
RMS_Main.numVehicles = 0
RMS_Main.previousKey = nil
RMS_Main.updateAlphaTimer = 0
RMS_Main.workshopCheckTimer = 0
RMS_Main.isWorkshopOpen = true
RMS_Main.currentWeather = WeatherType.SUN

---Tells whether the time of day falls within the opening hours
function RMS_Main:evaluateWorkshopState()
    local hour = g_currentMission.environment.dayTime / 3600000
    local hours = RMS_Config.WORKSHOP
    return hour >= hours.OPEN_HOUR and hour < hours.CLOSE_HOUR
end

---Setting that keeps each workshop type open around the clock
RMS_Main.ALWAYS_AVAILABLE_SETTINGS = {
    DEALER = "DEALER_ALWAYS_AVAILABLE",
    MOBILE = "MOBILE_ALWAYS_AVAILABLE",
    OWN = "OWN_ALWAYS_AVAILABLE"
}

---Tells whether a workshop type ignores the opening hours
function RMS_Main:isWorkshopTypeAlwaysAvailable(workshopType)
    for name, setting in pairs(RMS_Main.ALWAYS_AVAILABLE_SETTINGS) do
        if RealisticMechanicalSystems.WORKSHOP[name] == workshopType then
            return RMS_Config.WORKSHOP[setting] == true
        end
    end
    return false
end

---Tells whether a workshop type accepts a service now
function RMS_Main:isWorkshopTypeOpen(workshopType)
    return self.isWorkshopOpen == true or self:isWorkshopTypeAlwaysAvailable(workshopType)
end


---Recomputes the workshop state at once and replicates it
function RMS_Main:forceWorkshopUpdate(forceNotify)
    local isOpen = self:evaluateWorkshopState()
    if isOpen == self.isWorkshopOpen and not forceNotify then
        return
    end
    self.isWorkshopOpen = isOpen
    if g_currentMission:getIsServer() then
        RMS_WorkshopChangeStatusEvent.send(isOpen)
    end
    g_messageCenter:publish(MessageType.RMS_WORKSHOP_CHANGE_STATUS, isOpen)
end

---Advances the diagnostic tool licences and the monthly greasing
function RMS_Main:onPeriodChanged()
    if not g_currentMission:getIsServer() then
        return
    end

    RMS_DiagnosticTool.advanceLicences()
    for _, vehicle in pairs(g_currentMission.vehicleSystem.vehicles) do
        if vehicle.spec_rmsImplementGreasing ~= nil then
            RMS_Greasing.onPeriodChanged(vehicle)
        end
    end
end

---Makes the daily grease points of what worked that day due
function RMS_Main:onDayChanged()
    for _, vehicle in pairs(self.vehicles) do
        if not vehicle.spec_RealisticMechanicalSystems.isExcludedVehicle then
            RMS_Greasing.onDayChanged(vehicle)
        end
    end
    for _, vehicle in pairs(g_currentMission.vehicleSystem.vehicles) do
        if vehicle.spec_rmsImplementGreasing ~= nil then
            RMS_Greasing.onDayChanged(vehicle)
        end
    end
end

---Reads the current weather
function RMS_Main.updateWeather()
    RMS_Main.currentWeather = g_currentMission.environment.weather:getCurrentWeatherType()
end

---Steps a tracked machine; weather and shelter every meta step
function RMS_Main:stepVehicle(vehicle)
    local step = RMS_Config.CORE_UPDATE_DELAY
    vehicle:rmsUpdate(step, self.isWorkshopOpen)

    local spec = vehicle.spec_RealisticMechanicalSystems
    spec.metaUpdateTimer = spec.metaUpdateTimer + step
    if spec.metaUpdateTimer <= RMS_Config.META_UPDATE_DELAY then
        return
    end
    spec.metaUpdateTimer = spec.metaUpdateTimer - RMS_Config.META_UPDATE_DELAY
    RMS_Main.updateWeather()
    -- A working machine keeps the shelter it was parked under
    if vehicle:getIsOperating() then
        return
    end
    spec.isUnderRoof = vehicle:isUnderRoof()
end

---Next tracked machine of the round, back to the first after the last
function RMS_Main:getNextRoundVehicle()
    local key, vehicle = next(self.vehicles, self.previousKey)
    if key == nil then
        key, vehicle = next(self.vehicles)
    end
    self.previousKey = key
    return vehicle
end

---Runs the mod update: workshop hours and the simulation step of every vehicle
function RMS_Main:update(dt)
    if g_currentMission:getIsClient() then
        self:tryRegisterShopMenuPage()
    end

    self.workshopCheckTimer = self.workshopCheckTimer + dt
    if self.workshopFirstEval == nil or self.workshopCheckTimer >= RMS_Config.CORE_UPDATE_DELAY then
        self.workshopFirstEval = true
        self:forceWorkshopUpdate()
        if self.workshopCheckTimer >= RMS_Config.CORE_UPDATE_DELAY then
            self.workshopCheckTimer = self.workshopCheckTimer % RMS_Config.CORE_UPDATE_DELAY
        end
    end

    for _, vehicle in pairs(g_currentMission.vehicleSystem.vehicles) do
        local spec = vehicle.spec_RealisticMechanicalSystems
        if spec ~= nil and not spec.isExcludedVehicle and vehicle.isActive ~= true and vehicle:getMotorState() == MotorState.ON then
            vehicle:raiseActive()
        end
    end

    -- Server only: each machine steps once per CORE_UPDATE_DELAY
    local isStepping = g_currentMission:getIsServer() and self.numVehicles > 0
    if not isStepping then
        self.previousKey = nil
        return
    end
    local interval = RMS_Config.CORE_UPDATE_DELAY / self.numVehicles
    local elapsed = self.updateAlphaTimer + dt
    local count = math.floor(elapsed / interval)
    self.updateAlphaTimer = elapsed - count * interval
    for _ = 1, count do
        local vehicle = self:getNextRoundVehicle()
        if not vehicle.spec_RealisticMechanicalSystems.isExcludedVehicle then
            self:stepVehicle(vehicle)
        end
    end
end

---Loads the RMS map state and GUI registrations
function RMS_Main:loadMap()
    RMS_Gui.loadResources()
    RMS_Gui.loadFrames()
    RMS_SettingsPage.reset()
    RMS_Config.resetTutorialStateSession()
    RMS_Config.loadFromXMLFile()
    self:tryRegisterShopMenuPage()

    if g_currentMission:getIsServer() then
        g_messageCenter:subscribe(MessageType.PERIOD_CHANGED, self.onPeriodChanged, self)
        g_messageCenter:subscribe(MessageType.DAY_CHANGED, self.onDayChanged, self)
    end
    if RHM_Api ~= nil and RHM_Api.registerWearProvider ~= nil then
        RHM_Api.registerWearProvider(RealisticMechanicalSystems.HARVEST_WEAR_PROVIDER)
    end

    local soundsXmlFile = loadXMLFile("rmsSounds2D", Utils.getFilename("sounds/rms_sounds.xml", modDirectory))
    self.samples = {
        notification2D = g_soundManager:loadSample2DFromXML(soundsXmlFile, "sounds", "notification2D", modDirectory, 1, AudioGroup.GUI),
        maintenanceCompleted2D = g_soundManager:loadSample2DFromXML(soundsXmlFile, "sounds", "maintenanceCompleted2D", modDirectory, 1, AudioGroup.GUI)
    }
    delete(soundsXmlFile)
end

function RMS_Main:deleteMap()
    g_messageCenter:unsubscribe(MessageType.PERIOD_CHANGED, self)
    g_messageCenter:unsubscribe(MessageType.DAY_CHANGED, self)
    RMS_Gui.unloadResources()
    RMS_Config._loaded = nil
    RMS_Config.resetTutorialStateSession()
    RMS_SettingsPage.reset()
    RMS_Exhaust.plumeSources = nil

    g_soundManager:deleteSamples(self.samples)
    self.samples = nil
end

addModEventListener(RMS_Main)
