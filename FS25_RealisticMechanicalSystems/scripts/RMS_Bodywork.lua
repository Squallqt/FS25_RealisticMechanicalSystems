-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---Paint service rules shared by the quote and the server transaction
RMS_Bodywork = {}

RMS_Bodywork.TOUCHUP = "rms_bodywork_touchup"
RMS_Bodywork.FULL = "rms_bodywork_full"
RMS_Bodywork.MIN_TOUCHUP_WEAR = 0.01
RMS_Bodywork.MAX_TOUCHUP_WEAR = 0.30
-- real price of a full repaint by body size tier, a touch-up costing a share of it that grows with the wear
RMS_Bodywork.FULL_PRICES = { 3000, 6000, 14000 }
RMS_Bodywork.TOUCHUP_SHARE = 0.4
RMS_Bodywork.COLOR_ZONES = {"baseColor", "designColor", "rimColor"}
RMS_Bodywork.DURATION_HOURS = {
    [RMS_Bodywork.TOUCHUP] = {1, 2, 3},
    [RMS_Bodywork.FULL] = {8, 16, 24}
}
local previewParameters = {
    "colorScale", "smoothnessScale", "metalnessScale", "clearCoatSmoothness",
    "clearCoatIntensity", "porosity"
}
local previewMaps = {"detailDiffuse", "detailNormal", "detailSpecular"}

---Checks whether a loaded material can be restored after the silver preview.
local function getPaintDetailDiffuse(node, materialIndex)
    local slotName = getMaterialSlotName(node, materialIndex)
    if type(slotName) ~= "string" or slotName == "" then
        return nil
    end

    local materialId = getMaterial(node, materialIndex)
    if materialId == nil or materialId == 0 then
        return nil
    end
    local red, green, blue = getMaterialCustomParameter(materialId, "colorScale")
    if red == nil or green == nil or blue == nil then
        return nil
    end
    local detailDiffuse = nil
    for _, mapName in ipairs(previewMaps) do
        local filename = getMaterialCustomMapFilename(materialId, mapName)
        if type(filename) ~= "string" or filename == "" then
            return nil
        end
        if mapName == "detailDiffuse" then
            detailDiffuse = filename
        end
    end
    return detailDiffuse:lower()
end

---Walks painted component materials; a mixed shape is handled one slot at a time.
local function visitPaintMaterials(node, callback, colorSlots)
    if getHasClassId(node, ClassIds.SHAPE) then
        for materialIndex = 0, getNumOfMaterials(node) - 1 do
            local detailDiffuse = getPaintDetailDiffuse(node, materialIndex)
            if detailDiffuse ~= nil then
                local slotName = getMaterialSlotName(node, materialIndex)
                if colorSlots[slotName]
                    or detailDiffuse:find("calibratedpaint_", 1, true) ~= nil
                    or detailDiffuse:find("metalpainted", 1, true) ~= nil
                    or detailDiffuse:find("plasticpainted", 1, true) ~= nil then
                    callback(node, materialIndex)
                end
            end
        end
    end
    for childIndex = 0, getNumOfChildren(node) - 1 do
        visitPaintMaterials(getChildAt(node, childIndex), callback, colorSlots)
    end
end

---Restores the original native maps and shader values without retaining entity IDs.
function RMS_Bodywork.restorePreview(vehicle, finalized)
    local spec = vehicle ~= nil and vehicle.spec_RealisticMechanicalSystems or nil
    if spec == nil then
        return
    end
    for _, original in ipairs(spec.bodyworkPreviewMaterials or {}) do
        if entityExists(original.node) then
            local materialId = getMaterial(original.node, original.materialIndex)
            for _, mapName in ipairs(previewMaps) do
                local map = original.maps[mapName]
                if map ~= nil and map.filename ~= nil then
                    materialId = setMaterialCustomMapFromFile(
                        materialId, mapName, map.filename, false, map.isSRGB, false)
                end
            end
            if materialId ~= getMaterial(original.node, original.materialIndex) then
                setMaterial(original.node, materialId, original.materialIndex)
            end
            for _, parameterName in ipairs(previewParameters) do
                local values = original.parameters[parameterName]
                if values ~= nil and values[1] ~= nil then
                    setShaderParameter(original.node, parameterName,
                        values[1], values[2], values[3], values[4], false, original.materialIndex)
                end
            end
        end
    end
    spec.bodyworkPreviewMaterials = nil
    spec.bodyworkPreviewActive = false
    spec.bodyworkPreviewFinalized = finalized == true
    spec.bodyworkCrawlerRimApplied = nil
end

---Reapplies the saved running state after load or multiplayer synchronization.
function RMS_Bodywork.syncPreview(vehicle)
    local spec = vehicle ~= nil and vehicle.spec_RealisticMechanicalSystems or nil
    if spec == nil or not vehicle.isClient then
        return
    end
    local running = spec.currentState == RealisticMechanicalSystems.STATUS.BODYWORK
        and spec.serviceOptionOne == RMS_Bodywork.FULL
    if not running then
        if spec.bodyworkPreviewActive then
            RMS_Bodywork.restorePreview(vehicle, false)
        else
            spec.bodyworkPreviewFinalized = false
        end
        if spec.currentState == RealisticMechanicalSystems.STATUS.READY then
            RMS_Bodywork.syncCrawlerRimColor(vehicle)
        end
        return
    end
    if spec.bodyworkPreviewActive or spec.bodyworkPreviewFinalized then
        return
    end

    local colorSlots = {}
    for _, zone in ipairs(RMS_Bodywork.getColorZones(vehicle)) do
        for name in pairs(RMS_Bodywork.getColorTargetSlots(vehicle, zone)) do
            colorSlots[name] = true
        end
    end
    local strippedMaterial = VehicleMaterial.new(vehicle.baseDirectory)
    if not strippedMaterial:setTemplateName("SHARED_SILVER") then
        return
    end
    local originals = {}
    for _, component in ipairs(vehicle.components or {}) do
        visitPaintMaterials(component.node, function(node, materialIndex)
            local materialId = getMaterial(node, materialIndex)
            local maps = {}
            for _, mapName in ipairs(previewMaps) do
                local filename = getMaterialCustomMapFilename(materialId, mapName)
                if filename ~= nil then
                    maps[mapName] = {
                        filename = filename,
                        isSRGB = getMaterialCustomMapIsSRGB(materialId, mapName)
                    }
                end
            end
            local parameters = {}
            for _, parameterName in ipairs(previewParameters) do
                parameters[parameterName] = {getShaderParameter(node, parameterName, materialIndex)}
            end
            originals[#originals + 1] = {
                node = node,
                materialIndex = materialIndex,
                maps = maps,
                parameters = parameters
            }
            strippedMaterial:applyToMaterial(node, materialIndex, false)
        end, colorSlots)
    end
    spec.bodyworkPreviewMaterials = originals
    spec.bodyworkPreviewActive = true
end

---Keeps the native repaint action from bypassing an RMS bodywork transaction.
function RMS_Bodywork.repaintVehicle(vehicle, superFunc, ...)
    local spec = vehicle.spec_RealisticMechanicalSystems
    if spec ~= nil and not spec.isExcludedVehicle then
        return
    end
    return superFunc(vehicle, ...)
end

---Returns the volume tier from the vehicle dimensions loaded by GIANTS.
function RMS_Bodywork.getSizeTier(vehicle)
    local size = vehicle ~= nil and vehicle.size or nil
    local width = size ~= nil and tonumber(size.width) or nil
    local length = size ~= nil and tonumber(size.length) or nil
    local height = size ~= nil and tonumber(size.height) or nil
    if width == nil or length == nil or height == nil or width <= 0 or length <= 0 or height <= 0 then
        return nil
    end

    local volume = width * length * height
    if volume < 20 then
        return 1
    end
    return volume <= 100 and 2 or 3
end

function RMS_Bodywork.getWear(vehicle)
    if vehicle == nil or vehicle.spec_wearable == nil or vehicle.getWearTotalAmount == nil then
        return nil
    end
    local wear = tonumber(vehicle:getWearTotalAmount())
    return wear ~= nil and math.max(0, math.min(wear, 1)) or nil
end

function RMS_Bodywork.getPrice(vehicle, mode, workshopType)
    if vehicle == nil or vehicle.getPrice == nil or RMS_Bodywork.DURATION_HOURS[mode] == nil
        or RMS_Bodywork.getSizeTier(vehicle) == nil then
        return nil
    end
    local currentWear = RMS_Bodywork.getWear(vehicle)
    if currentWear == nil or (mode == RMS_Bodywork.TOUCHUP
        and (currentWear < RMS_Bodywork.MIN_TOUCHUP_WEAR
            or currentWear > RMS_Bodywork.MAX_TOUCHUP_WEAR)) then
        return nil
    end
    local price = RMS_Bodywork.FULL_PRICES[RMS_Bodywork.getSizeTier(vehicle)]
    if mode == RMS_Bodywork.TOUCHUP then
        price = price * RMS_Bodywork.TOUCHUP_SHARE * math.sqrt(currentWear)
        if workshopType == RealisticMechanicalSystems.WORKSHOP.OWN then
            price = price * RMS_Config.WORKSHOP.PRICE_MULTIPLIERS.OWN
        end
    end
    return math.ceil(RMS_Utils.getGamePrice(price) / 10) * 10
end

---Returns the service duration for the selected vehicle size.
function RMS_Bodywork.getDurationMs(vehicle, mode)
    local tier = RMS_Bodywork.getSizeTier(vehicle)
    local hours = RMS_Bodywork.DURATION_HOURS[mode]
    if tier == nil or hours == nil then
        return nil
    end
    return hours[tier] * 3600000
end

---Lists only color configurations the native shop allows players to select.
local function getSelectionIndex(selection)
    return type(selection) == "table" and selection.index or selection
end

local function hasMaterialSlot(node, slotName)
    if getHasClassId(node, ClassIds.SHAPE) then
        for materialIndex = 0, getNumOfMaterials(node) - 1 do
            if getMaterialSlotName(node, materialIndex) == slotName then
                return true
            end
        end
    end
    for childIndex = 0, getNumOfChildren(node) - 1 do
        if hasMaterialSlot(getChildAt(node, childIndex), slotName) then
            return true
        end
    end
    return false
end

local function vehicleHasMaterialSlot(vehicle, slotName)
    for _, component in ipairs(vehicle.components or {}) do
        if hasMaterialSlot(component.node, slotName) then
            return true
        end
    end
    return false
end

local function collectCrawlerRimSlots(node, slots)
    if node == nil or not entityExists(node) then
        return
    end
    if getHasClassId(node, ClassIds.SHAPE) then
        for materialIndex = 0, getNumOfMaterials(node) - 1 do
            local name = getMaterialSlotName(node, materialIndex)
            if type(name) == "string" and (name == "rim_inner_mat" or name == "rim_outer_mat"
                or name:match("_rim_inner_mat$") ~= nil or name:match("_rim_outer_mat$") ~= nil) then
                slots[name] = true
            end
        end
    end
    for childIndex = 0, getNumOfChildren(node) - 1 do
        collectCrawlerRimSlots(getChildAt(node, childIndex), slots)
    end
end

function RMS_Bodywork.getColorZones(vehicle)
    local storeItem = vehicle ~= nil and g_storeManager ~= nil
        and g_storeManager:getItemByXMLFilename(vehicle.configFileName) or nil
    local configurations = storeItem ~= nil and storeItem.configurations or nil
    local zones = {}
    if configurations == nil or g_vehicleConfigurationManager == nil then
        return zones
    end
    for _, zone in ipairs(g_vehicleConfigurationManager:getSortedConfigurationTypes()) do
        local items = configurations[zone]
        if items ~= nil and items[1] ~= nil and items[1]:isa(VehicleConfigurationItemColor) then
            zones[#zones + 1] = zone
        end
    end
    return zones
end

function RMS_Bodywork.getColorTargetSlots(vehicle, zone)
    local slots = {}
    local desc = g_vehicleConfigurationManager:getConfigurationDescByName(zone)
    if desc ~= nil and desc.configurationsKey ~= nil then
        vehicle.xmlFile:iterate(desc.configurationsKey .. ".material", function(_, materialKey)
            local name = vehicle.xmlFile:getValue(materialKey .. "#materialSlotName")
            if name ~= nil and vehicleHasMaterialSlot(vehicle, name) then
                slots[name] = true
            end
        end)
    end
    if desc ~= nil and desc.configurationsKey ~= nil
        and zone:match("^agriBumperColor%d*$") ~= nil
        and DefaultVehiclesConfigurations ~= nil then
        local source = DefaultVehiclesConfigurations
        local xmlFile = XMLFile.loadIfExists(
            "agriBumperDefaultVehicles", source.DEFAULT_VEHICLE_XML, source.DEFAULT_VEHICLE_SCHEMA)
        if xmlFile ~= nil then
            local key = source.getMatchingDefaultVehicleKey(
                xmlFile, vehicle.xmlFile.filename, vehicle.xmlFile.filename)
            if key ~= nil then
                local configurationsKey = desc.configurationsKey:gsub("^vehicle%.", key .. ".")
                xmlFile:iterate(configurationsKey .. ".material", function(_, materialKey)
                    local name = xmlFile:getValue(materialKey .. "#materialSlotName")
                    if name ~= nil and vehicleHasMaterialSlot(vehicle, name) then
                        slots[name] = true
                    end
                end)
            end
            xmlFile:delete()
        end
    end
    if zone == "rimColor" and vehicle.spec_wheels ~= nil then
        for _, name in ipairs({"rim_inner_mat", "rim_outer_mat"}) do
            if vehicleHasMaterialSlot(vehicle, name) then
                slots[name] = true
            end
        end
    end
    if zone == "rimColor" and vehicle.spec_crawlers ~= nil then
        for _, crawler in ipairs(vehicle.spec_crawlers.crawlers or {}) do
            if crawler.rimMaterial == nil then
                collectCrawlerRimSlots(crawler.loadedCrawler, slots)
            end
        end
    end
    return slots
end

---Applies the selected native rim color to crawler rims without a crawler rim material.
function RMS_Bodywork.syncCrawlerRimColor(vehicle)
    local spec = vehicle ~= nil and vehicle.spec_RealisticMechanicalSystems or nil
    local crawlers = vehicle ~= nil and vehicle.spec_crawlers or nil
    local index = vehicle ~= nil and vehicle.configurations ~= nil and vehicle.configurations.rimColor or nil
    if spec == nil or not vehicle.isClient or crawlers == nil or index == nil then
        return
    end
    local configurationData = vehicle.configurationData
    local colorData = configurationData ~= nil and configurationData.rimColor ~= nil
        and configurationData.rimColor[index] or nil
    local color = colorData ~= nil and colorData.color or nil
    local signature = tostring(index)
    if color ~= nil then
        signature = string.format("%s:%.6f:%.6f:%.6f", index, color[1], color[2], color[3])
    end
    spec.bodyworkCrawlerRimApplied = spec.bodyworkCrawlerRimApplied or {}
    for _, crawler in ipairs(crawlers.crawlers or {}) do
        local node = crawler.loadedCrawler
        if crawler.rimMaterial == nil and node ~= nil and entityExists(node) then
            local applied = spec.bodyworkCrawlerRimApplied[crawler]
            if applied == nil or applied.node ~= node or applied.signature ~= signature then
                local slots = {}
                collectCrawlerRimSlots(node, slots)
                if next(slots) == nil then
                    spec.bodyworkCrawlerRimApplied[crawler] = {node = node, signature = signature}
                else
                    local material = VehicleConfigurationItemColor.getMaterialByColorConfiguration(vehicle, "rimColor")
                    if material ~= nil then
                        local success = false
                        for name in pairs(slots) do
                            success = material:apply(node, name) or success
                        end
                        if success then
                            spec.bodyworkCrawlerRimApplied[crawler] = {node = node, signature = signature}
                        end
                    end
                end
            end
        end
    end
end

local function matchesColorConfigurationSets(vehicle, zone, index, indices, configurationSets)
    if configurationSets == nil or next(configurationSets) == nil then
        return true
    end
    local candidate = {}
    for name, currentIndex in pairs(vehicle.configurations or {}) do
        candidate[name] = currentIndex
    end
    for name, selection in pairs(indices or {}) do
        local selectedIndex = getSelectionIndex(selection)
        if type(selectedIndex) == "number" and selectedIndex ~= 0 then
            candidate[name] = selectedIndex
        end
    end
    candidate[zone] = index
    return ConfigurationUtil.getConfigurationsMatchConfigSets(candidate, configurationSets)
end

function RMS_Bodywork.getColorChoices(vehicle, zone, indices)
    if vehicle == nil then
        return {}
    end
    local storeItem = vehicle ~= nil and g_storeManager ~= nil
        and g_storeManager:getItemByXMLFilename(vehicle.configFileName) or nil
    local configurations = storeItem ~= nil and storeItem.configurations or nil
    local configurationSets = storeItem ~= nil and storeItem.configurationSets or nil
    local sourceItems = configurations ~= nil and configurations[zone] or nil
    local choices = {}
    for index, item in ipairs(sourceItems or {}) do
        if item.isSelectable ~= false and item.color ~= nil
            and matchesColorConfigurationSets(vehicle, zone, index, indices, configurationSets) then
            table.insert(choices, {index = index, item = item})
        end
    end
    return choices
end

---Returns the native custom-color configuration, when this zone supports it.
function RMS_Bodywork.getCustomColorChoice(vehicle, zone, indices)
    if vehicle == nil then
        return nil
    end
    local storeItem = vehicle ~= nil and g_storeManager ~= nil
        and g_storeManager:getItemByXMLFilename(vehicle.configFileName) or nil
    local configurations = storeItem ~= nil and storeItem.configurations or nil
    for index, item in ipairs(configurations ~= nil and configurations[zone] or {}) do
        if item.isCustomColor and item.onPostLoad ~= nil
            and matchesColorConfigurationSets(vehicle, zone, index, indices, storeItem.configurationSets) then
            return {index = index, item = item}
        end
    end
    return nil
end

function RMS_Bodywork.isValidColor(color)
    if type(color) ~= "table" then
        return false
    end
    for i = 1, 3 do
        local value = color[i]
        if type(value) ~= "number" or value ~= value or value < 0 or value > 1 then
            return false
        end
    end
    return true
end

---The service context already synchronizes and saves optionTwo as a string.
function RMS_Bodywork.encodeColors(vehicle, indices)
    local tokens = {}
    for _, zone in ipairs(RMS_Bodywork.getColorZones(vehicle)) do
        local selection = indices[zone] or 0
        if type(selection) == "table" then
            if type(selection.index) ~= "number" or not RMS_Bodywork.isValidColor(selection.color) then
                return nil
            end
            local color = selection.color
            tokens[#tokens + 1] = string.format("%s=%d,%.6f,%.6f,%.6f",
                zone, selection.index, color[1], color[2], color[3])
        elseif type(selection) == "number" and selection >= 0 and selection == math.floor(selection) then
            tokens[#tokens + 1] = string.format("%s=%d", zone, selection)
        else
            return nil
        end
    end
    return "z;" .. table.concat(tokens, ";")
end

function RMS_Bodywork.decodeColors(value)
    if type(value) ~= "string" then
        return nil
    end
    if value:sub(1, 2) == "z;" then
        local selections = {}
        for token in value:sub(3):gmatch("[^;]+") do
            local zone, numeric = token:match("^([%w_]+)=(%d+)$")
            if zone ~= nil then
                if selections[zone] ~= nil then
                    return nil
                end
                selections[zone] = tonumber(numeric)
            else
                local index, red, green, blue
                zone, index, red, green, blue = token:match(
                    "^([%w_]+)=(%d+),([%d%.]+),([%d%.]+),([%d%.]+)$")
                if zone == nil or selections[zone] ~= nil then
                    return nil
                end
                local color = {tonumber(red), tonumber(green), tonumber(blue)}
                if not RMS_Bodywork.isValidColor(color) then
                    return nil
                end
                selections[zone] = {index = tonumber(index), color = color}
            end
        end
        return selections
    end
    local base, design, rim = value:match("^(%d+):(%d+):(%d+)$")
    if base ~= nil then
        return {baseColor = tonumber(base), designColor = tonumber(design), rimColor = tonumber(rim)}
    end
    local baseToken, designToken, rimToken = value:match("^c;([^;]+);([^;]+);([^;]+)$")
    if baseToken == nil then
        return nil
    end
    local selections = {}
    for index, token in ipairs({baseToken, designToken, rimToken}) do
        local numeric = token:match("^(%d+)$")
        local selection = numeric ~= nil and tonumber(numeric) or nil
        if selection == nil then
            local colorIndex, red, green, blue = token:match("^(%d+),([%d%.]+),([%d%.]+),([%d%.]+)$")
            selection = colorIndex ~= nil and {
                index = tonumber(colorIndex), color = {tonumber(red), tonumber(green), tonumber(blue)}
            } or nil
            if selection == nil or not RMS_Bodywork.isValidColor(selection.color) then
                return nil
            end
        end
        selections[RMS_Bodywork.COLOR_ZONES[index]] = selection
    end
    return selections
end

function RMS_Bodywork.validateColors(vehicle, encoded)
    local indices = RMS_Bodywork.decodeColors(encoded)
    if indices == nil then
        return false
    end
    local zones = RMS_Bodywork.getColorZones(vehicle)
    local available = {}
    for _, zone in ipairs(zones) do
        available[zone] = true
    end
    for zone, selected in pairs(indices) do
        if not available[zone] and getSelectionIndex(selected) ~= 0 then
            return false
        end
    end
    for _, zone in ipairs(zones) do
        local selected = indices[zone] or 0
        if type(selected) == "table" then
            local choice = RMS_Bodywork.getCustomColorChoice(vehicle, zone, indices)
            if choice == nil or choice.index ~= selected.index or not RMS_Bodywork.isValidColor(selected.color) then
                return false
            end
        elseif selected ~= 0 then
            local valid = false
            for _, choice in ipairs(RMS_Bodywork.getColorChoices(vehicle, zone, indices)) do
                if choice.index == selected then
                    valid = true
                    break
                end
            end
            if not valid then
                return false
            end
        end
    end
    return true
end

function RMS_Bodywork.isAllowed(vehicle, workshopType, mode, encoded)
    local rmsSpec = vehicle ~= nil and vehicle.spec_RealisticMechanicalSystems or nil
    if rmsSpec == nil or rmsSpec.isExcludedVehicle
        or rmsSpec.currentState ~= RealisticMechanicalSystems.STATUS.READY
        or (rmsSpec.maintenanceTimer or 0) ~= 0 then
        return false
    end
    local wear = RMS_Bodywork.getWear(vehicle)
    if wear == nil or RMS_Bodywork.getSizeTier(vehicle) == nil then
        return false
    end
    if mode == RMS_Bodywork.TOUCHUP then
        return (workshopType == RealisticMechanicalSystems.WORKSHOP.OWN
            or workshopType == RealisticMechanicalSystems.WORKSHOP.DEALER)
            and wear >= RMS_Bodywork.MIN_TOUCHUP_WEAR
            and wear <= RMS_Bodywork.MAX_TOUCHUP_WEAR
            and (encoded == nil or encoded == "")
    end
    return mode == RMS_Bodywork.FULL
        and workshopType == RealisticMechanicalSystems.WORKSHOP.DEALER
        and RMS_Bodywork.validateColors(vehicle, encoded)
end

function RMS_Bodywork.clearWear(vehicle)
    local spec = vehicle ~= nil and vehicle.spec_wearable or nil
    for _, nodeData in ipairs(spec ~= nil and spec.wearableNodes or {}) do
        vehicle:setNodeWearAmount(nodeData, 0, true)
    end
end

local function refreshWheelColor(vehicle, zone, previousMaterial, material)
    local wheels = vehicle.spec_wheels
    if wheels == nil then
        return
    end
    local wheelMaterials = {
        {"rimMaterial", "rim_inner_mat"},
        {"rimMaterial", "rim_outer_mat"},
        {"innerRimMaterial", "rim_inner_mat"},
        {"outerRimMaterial", "rim_outer_mat"},
        {"additionalMaterial", "rim_additional_mat"},
        {"hubMaterial", "hub_main_mat"},
        {"hubBoltMaterial", "hub_bolt_mat"}
    }
    for _, entry in ipairs(wheelMaterials) do
        local name, slotName = entry[1], entry[2]
        local rimField = name == "rimMaterial" or name == "innerRimMaterial"
            or name == "outerRimMaterial" or name == "additionalMaterial"
        local materialKey = "vehicle.wheels." .. name
        local usesRimColor = zone == "rimColor" and rimField and material ~= nil
            and not vehicle.xmlFile:getBool(materialKey .. "#useBaseColor", false)
            and vehicle.xmlFile:getValue(materialKey .. "#useDesignColorIndex") == nil
            and (name == "rimMaterial"
                or not vehicle.xmlFile:hasProperty(materialKey)
                or vehicle.xmlFile:getBool(materialKey .. "#useRimColor", false))
        if usesRimColor or (previousMaterial ~= nil and wheels[name] == previousMaterial) then
            wheels[name] = material
        end
        if wheels[name] ~= nil then
            wheels[name]:applyToVehicle(vehicle, slotName)
        end
    end
    local hubMaterials = {
        {"material", "hub_main_mat"},
        {"boltMaterial", "hub_bolt_mat"},
        {"additionalMaterial", "hub_main_additional_mat"},
        {"boltAdditionalMaterial", "hub_bolt_additional_mat"}
    }
    for _, hub in ipairs(wheels.hubs or {}) do
        for _, entry in ipairs(hubMaterials) do
            local name, slotName = entry[1], entry[2]
            if previousMaterial ~= nil and hub[name] == previousMaterial then
                hub[name] = material
            end
            if hub[name] ~= nil then
                hub[name]:apply(hub.node, slotName)
            end
        end
    end
    for _, wheel in pairs(wheels.wheels or {}) do
        for _, visualWheel in ipairs(wheel.visualWheels or {}) do
            if previousMaterial ~= nil and visualWheel.rimMaterial == previousMaterial then
                visualWheel.rimMaterial = material
            end
            visualWheel:postLoad()
        end
    end
end

---Applies a selected native configuration and lets the vehicle save its new index.
function RMS_Bodywork.applyColors(vehicle, encoded)
    local indices = RMS_Bodywork.decodeColors(encoded)
    if indices == nil or not RMS_Bodywork.validateColors(vehicle, encoded) then
        return false
    end
    local storeItem = g_storeManager:getItemByXMLFilename(vehicle.configFileName)
    local selectedItems = {}
    local previousMaterials = {}
    local zones = RMS_Bodywork.getColorZones(vehicle)
    for _, zone in ipairs(zones) do
        local selectedIndex = getSelectionIndex(indices[zone] or 0)
        local index = selectedIndex ~= 0 and selectedIndex or vehicle.configurations[zone]
        local item = storeItem ~= nil and storeItem.configurations ~= nil
            and storeItem.configurations[zone] ~= nil and storeItem.configurations[zone][index] or nil
        if selectedIndex ~= 0 and (item == nil or item.onPostLoad == nil) then
            return false
        end
        if item ~= nil and item.onPostLoad ~= nil then
            selectedItems[zone] = item
            if zone == "baseColor" or zone == "rimColor" or zone:match("^designColor%d*$") ~= nil then
                previousMaterials[zone] = VehicleConfigurationItemColor.getMaterialByColorConfiguration(
                    vehicle, zone)
            end
        end
    end
    for _, zone in ipairs(zones) do
        local selection = indices[zone] or 0
        local index = getSelectionIndex(selection)
        if index ~= 0 then
            if type(selection) == "table" then
                vehicle.configurationData = vehicle.configurationData or {}
                vehicle.configurationData[zone] = vehicle.configurationData[zone] or {}
                vehicle.configurationData[zone][index] = {
                    color = {selection.color[1], selection.color[2], selection.color[3]},
                    materialTemplateName = selectedItems[zone].materialTemplateName
                }
            end
            ConfigurationUtil.addBoughtConfiguration(g_vehicleConfigurationManager, vehicle, zone, index)
            ConfigurationUtil.setConfiguration(vehicle, zone, index)
        end
        if selectedItems[zone] ~= nil then
            selectedItems[zone]:onPostLoad(vehicle, index ~= 0 and index or vehicle.configurations[zone])
            if previousMaterials[zone] ~= nil then
                refreshWheelColor(vehicle, zone, previousMaterials[zone], selectedItems[zone]:getMaterial(vehicle))
            end
        end
    end
    return true
end
