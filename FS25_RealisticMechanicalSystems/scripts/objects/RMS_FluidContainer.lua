-- Copyright © 2026 Squallqt. All rights reserved.

---Fluid container: can, jerrican, drums or tank of a catalogue product
RMS_FluidContainer = {}
RMS_FluidContainer.SPEC_NAME = "FS25_RealisticMechanicalSystems.rmsFluidContainer"
RMS_FluidContainer.SPEC_TABLE_NAME = "spec_" .. RMS_FluidContainer.SPEC_NAME
RMS_FluidContainer.DRUM_I3D_FILENAME = "data/maps/textures/shared/props/motorex/motorexOilBarrel.i3d"
RMS_FluidContainer.ADBLUE_CAN_I3D_FILENAME = "data/maps/mapAS/textures/props/canister.i3d"
RMS_FluidContainer.ADBLUE_DRUM_I3D_FILENAME = "data/placeables/brandless/decoration/garbageContainers/barrel02.i3d"
RMS_FluidContainer.CARRIED_CAPACITY = 20
RMS_FluidContainer.PUMP_I3D_FILENAME = "objects/drumPump/drumPumpMounted.i3d"
RMS_FluidContainer.PUMP_TRANSLATION = { 0, 0.898252845, 0.1980392635 }
RMS_FluidContainer.ADBLUE_DRUM_PUMP = { translation = { 0.2171, 0.9421, 0 }, rotationY = 90 }
RMS_FluidContainer.ADBLUE_DRUM_PUMP_LEFT = { translation = { -0.2171, 0.9421, 0 }, rotationY = -90 }
RMS_FluidContainer.TANK_PUMP = { translation = { 0, 1.558, 0 }, rotationY = 0 }
RMS_FluidContainer.TANK_HOSE_I3D_FILENAME = "objects/drumPump/drumPumpTankHose.i3d"
RMS_FluidContainer.DRUM_PLACES = {
    { { link = "drumVisualLink", collision = "drumCollision" } },
    { { link = "drumVisualLinkA", collision = "drumCollisionA", isLeft = true },
        { link = "drumVisualLinkB", collision = "drumCollisionB" } }
}

---Checks if all prerequisite specializations are loaded
-- @param table specializations specializations
-- @return boolean hasPrerequisite true if all prerequisite specializations are loaded
function RMS_FluidContainer.prerequisitesPresent(specializations)
    return SpecializationUtil.hasSpecialization(FillUnit, specializations)
end

---Registers container XML data
function RMS_FluidContainer.initSpecialization()
    local schema = Vehicle.xmlSchema
    schema:setXMLSpecializationType("RMSFluidContainer")
    local baseKey = "vehicle.rmsFluidContainer"
    schema:register(XMLValueType.STRING, baseKey .. "#productKey", "Immutable RMS fluid catalogue key")
    schema:register(XMLValueType.STRING, baseKey .. "#mediumBodyDiffuse", "5 liter body diffuse map")
    schema:register(XMLValueType.STRING, baseKey .. "#mediumCapDiffuse", "5 liter cap diffuse map")
    schema:register(XMLValueType.STRING, baseKey .. "#mediumLabelDiffuse", "5 liter label diffuse map")
    schema:register(XMLValueType.STRING, baseKey .. "#largeBodyDiffuse", "20 liter jerrican body diffuse map")
    schema:register(XMLValueType.STRING, baseKey .. "#largeLabelDiffuse", "20 liter jerrican label diffuse map")
    schema:register(XMLValueType.STRING, baseKey .. "#drumBodyDiffuse", "Drum paint diffuse map, the brand's print")
    schema:register(XMLValueType.STRING, baseKey .. "#drumPrints", "I3D of the product label on the drum")
    schema:register(XMLValueType.STRING, baseKey .. "#drumLabelDiffuse", "Drum product label diffuse map")
    schema:register(XMLValueType.STRING, baseKey .. "#canDiffuse", "Game can model diffuse map, the product's plastic")
    schema:register(XMLValueType.STRING, baseKey .. "#canPrints", "I3D of the product label on the game can model")
    schema:register(XMLValueType.STRING, baseKey .. "#drumDiffuse", "Game drum model diffuse map, the product's plastic")
    schema:register(XMLValueType.STRING, baseKey .. "#drumSpecular", "Game drum model specular map")
    schema:register(XMLValueType.STRING, baseKey .. "#tankDiffuse", "Game tank model diffuse map, the product's colours")
    schema:register(XMLValueType.STRING, baseKey .. "#tankPrints", "I3D of the product plate on the game tank model")
    schema:setXMLSpecializationType()

    Vehicle.xmlSchemaSavegame:register(XMLValueType.BOOL,
        "vehicles.vehicle(?)." .. RMS_FluidContainer.SPEC_NAME .. "#hasPump", "Whether a pump sits on the drum")
    Vehicle.xmlSchemaSavegame:register(XMLValueType.BOOL,
        "vehicles.vehicle(?)." .. RMS_FluidContainer.SPEC_NAME .. "#hasPump2", "Whether a pump sits on the second drum")
end

---Registers public container functions
-- @param table vehicleType vehicle type
function RMS_FluidContainer.registerFunctions(vehicleType)
    SpecializationUtil.registerFunction(vehicleType, "getRMSFluidProductKey", RMS_FluidContainer.getRMSFluidProductKey)
    SpecializationUtil.registerFunction(vehicleType, "getRMSFluidLiters", RMS_FluidContainer.getRMSFluidLiters)
    SpecializationUtil.registerFunction(vehicleType, "getRMSFluidCapacity", RMS_FluidContainer.getRMSFluidCapacity)
    SpecializationUtil.registerFunction(vehicleType, "getRMSFluidFormat", RMS_FluidContainer.getRMSFluidFormat)
    SpecializationUtil.registerFunction(vehicleType, "dressRMSFluidGameCan", RMS_FluidContainer.dressRMSFluidGameCan)
    SpecializationUtil.registerFunction(vehicleType, "getRMSFluidPercentage", RMS_FluidContainer.getRMSFluidPercentage)
    SpecializationUtil.registerFunction(vehicleType, "beginRMSFluidTransaction", RMS_FluidContainer.beginRMSFluidTransaction)
    SpecializationUtil.registerFunction(vehicleType, "endRMSFluidTransaction", RMS_FluidContainer.endRMSFluidTransaction)
    SpecializationUtil.registerFunction(vehicleType, "removeRMSFluidLiters", RMS_FluidContainer.removeRMSFluidLiters)
    SpecializationUtil.registerFunction(vehicleType, "restoreRMSFluidLiters", RMS_FluidContainer.restoreRMSFluidLiters)
    SpecializationUtil.registerFunction(vehicleType, "getIsRMSFluidTransferActive", RMS_FluidContainer.getIsRMSFluidTransferActive)
    SpecializationUtil.registerFunction(vehicleType, "getRMSFluidCarrier", RMS_FluidContainer.getRMSFluidCarrier)
    SpecializationUtil.registerFunction(vehicleType, "setRMSFluidCarried", RMS_FluidContainer.setRMSFluidCarried)
    SpecializationUtil.registerFunction(vehicleType, "applyRMSFluidVisuals", RMS_FluidContainer.applyRMSFluidVisuals)
    SpecializationUtil.registerFunction(vehicleType, "getRMSFluidKindText", RMS_FluidContainer.getRMSFluidKindText)
    SpecializationUtil.registerFunction(vehicleType, "getHasRMSFluidPump", RMS_FluidContainer.getHasRMSFluidPump)
    SpecializationUtil.registerFunction(vehicleType, "setRMSFluidPump", RMS_FluidContainer.setRMSFluidPump)
    SpecializationUtil.registerFunction(vehicleType, "setRMSFluidStored", RMS_FluidContainer.setRMSFluidStored)
    SpecializationUtil.registerFunction(vehicleType, "setRMSFluidNozzle", RMS_FluidContainer.setRMSFluidNozzle)
    SpecializationUtil.registerFunction(vehicleType, "getRMSFluidHoseSpan", RMS_FluidContainer.getRMSFluidHoseSpan)
    SpecializationUtil.registerFunction(vehicleType, "getRMSFluidSlotCount", RMS_FluidContainer.getRMSFluidSlotCount)
    SpecializationUtil.registerFunction(vehicleType, "getRMSFluidSlotAt", RMS_FluidContainer.getRMSFluidSlotAt)
    SpecializationUtil.registerFunction(vehicleType, "getHandsJointBreakForceFactor", RMS_FluidContainer.getHandsJointBreakForceFactor)
end

---Registers native container behavior overrides
-- @param table vehicleType vehicle type
function RMS_FluidContainer.registerOverwrittenFunctions(vehicleType)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "delete", RMS_FluidContainer.delete)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "getCanBePickedUp", RMS_FluidContainer.getCanBePickedUp)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "getMeshNodes", RMS_FluidContainer.getMeshNodes)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "getInfoBoxTitle", RMS_FluidContainer.getInfoBoxTitle)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "showInfo", RMS_FluidContainer.showInfo)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "updateMass", RMS_FluidContainer.updateMass)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "addFillUnitFillLevel", RMS_FluidContainer.addFillUnitFillLevel)
end

---Registers load, save and network callbacks
-- @param table vehicleType vehicle type
function RMS_FluidContainer.registerEventListeners(vehicleType)
    SpecializationUtil.registerEventListener(vehicleType, "onLoad", RMS_FluidContainer)
    SpecializationUtil.registerEventListener(vehicleType, "onFillUnitFillLevelChanged", RMS_FluidContainer)
    SpecializationUtil.registerEventListener(vehicleType, "onDelete", RMS_FluidContainer)
    SpecializationUtil.registerEventListener(vehicleType, "onUpdate", RMS_FluidContainer)
    SpecializationUtil.registerEventListener(vehicleType, "saveToXMLFile", RMS_FluidContainer)
    SpecializationUtil.registerEventListener(vehicleType, "onReadStream", RMS_FluidContainer)
    SpecializationUtil.registerEventListener(vehicleType, "onWriteStream", RMS_FluidContainer)
    SpecializationUtil.registerEventListener(vehicleType, "onReadUpdateStream", RMS_FluidContainer)
    SpecializationUtil.registerEventListener(vehicleType, "onWriteUpdateStream", RMS_FluidContainer)
end

---Returns the format of a capacity
-- @param float capacity capacity (l)
-- @return string format "medium" (5 L can), "large" (20 L jerrican) or "drum"
function RMS_FluidContainer.getFormat(capacity)
    if capacity <= 5 then
        return "medium"
    end
    return capacity <= RMS_FluidContainer.CARRIED_CAPACITY and "large" or "drum"
end

---Links the product label on the drum's lid or flank
-- @param table container fluid container
-- @param entityId parentNode node the label goes under
-- @param string baseKey XML key of the container
function RMS_FluidContainer.loadDrumPrints(container, parentNode, baseKey)
    local filename = container.xmlFile:getValue(baseKey .. "#drumPrints")
    local i3dRoot = g_i3DManager:loadI3DFile(Utils.getFilename(filename, container.baseDirectory), false, false)
    if i3dRoot == 0 then
        Logging.xmlError(container.xmlFile, "Unable to load drum prints '%s'", filename)
        return
    end
    local prints = getChildAt(i3dRoot, 0)
    link(parentNode, prints)
    delete(i3dRoot)
    RMS_FluidContainer.applyDiffuseByName({ prints }, "productLabel",
        Utils.getFilename(container.xmlFile:getValue(baseKey .. "#drumLabelDiffuse"), container.baseDirectory))
end

---Loads the game's oil drum as a visual, without its rigid body
-- @param entityId parentNode node the drum goes under
-- @return boolean isLoaded true once loaded
function RMS_FluidContainer.loadNativeDrumVisual(parentNode)
    return RMS_FluidContainer.loadNativeVisual(RMS_FluidContainer.DRUM_I3D_FILENAME, parentNode)
end

---Loads a game prop as a visual, without its rigid body
-- @param string filename I3D of the prop
-- @param entityId parentNode node the prop goes under
-- @return boolean isLoaded true once loaded
function RMS_FluidContainer.loadNativeVisual(filename, parentNode)
    local i3dRoot = g_i3DManager:loadI3DFile(filename, false, false)
    if i3dRoot == 0 or getNumOfChildren(i3dRoot) == 0 then
        if i3dRoot ~= 0 then
            delete(i3dRoot)
        end
        Logging.error("RMS: unable to load native fluid container '%s'", filename)
        return false
    end

    local drumNode = getChildAt(i3dRoot, 0)
    unlink(drumNode)
    delete(i3dRoot)
    RMS_FluidContainer.stripCollision(drumNode)
    link(parentNode, drumNode)
    setTranslation(drumNode, 0, 0, 0)
    setRotation(drumNode, 0, 0, 0)
    return true
end

---Loads the pump on a drum, returning its nodes
-- @param table container fluid container
-- @param entityId drumLink node of the drum
-- @param table? place { translation, rotationY }, the oil drum's bung by default
-- @return table pump nodes of the pump
local function loadPump(container, drumLink, place)
    local i3dRoot = g_i3DManager:loadI3DFile(Utils.getFilename(RMS_FluidContainer.PUMP_I3D_FILENAME, container.baseDirectory), false, false)
    local node = getChildAt(i3dRoot, 0)
    link(drumLink, node)
    delete(i3dRoot)
    setTranslation(node, unpack(place ~= nil and place.translation or RMS_FluidContainer.PUMP_TRANSLATION))
    setRotation(node, 0, math.rad(place ~= nil and place.rotationY or 0), 0)

    local graphics = getChildAt(node, 0)
    return { node = node, hoseOutlet = getChildAt(graphics, 2), restHose = getChildAt(graphics, 4), storedNozzle = getChildAt(graphics, 5) }
end

---Swaps the parked hose of a pump for the one lying on the tank roof
-- @param table container fluid container
-- @param table pump nodes of the pump
local function loadTankHose(container, pump)
    local filename = Utils.getFilename(RMS_FluidContainer.TANK_HOSE_I3D_FILENAME, container.baseDirectory)
    local i3dRoot = g_i3DManager:loadI3DFile(filename, false, false)
    if i3dRoot == 0 then
        Logging.error("RMS: unable to load the tank hose '%s'", filename)
        return
    end
    local hose = getChildAt(i3dRoot, 0)
    link(getParent(pump.restHose), hose)
    delete(i3dRoot)
    setVisibility(pump.restHose, false)
    pump.restHose = hose
end

---Shows the pump of a place, its nozzle and hose while hung up
-- @param table slot place of the container
local function applyPump(slot)
    setVisibility(slot.pump.node, slot.hasPump)
    setVisibility(slot.pump.storedNozzle, not slot.isNozzleOut)
    setVisibility(slot.pump.restHose, not slot.isNozzleOut)
end

---Returns a place: the can or jerrican, or one drum of the format
-- @param table container fluid container
-- @param integer index place
-- @return table slot place
local function getSlot(container, index)
    return container[RMS_FluidContainer.SPEC_TABLE_NAME].slots[index]
end

---Tells whether nothing keeps the container once empty: no allocation, no pump, no other place holding fluid
-- @param table container fluid container
-- @param integer? fillUnitIndex fill unit being emptied, nil to look at every place
-- @return boolean isRemovable true when nothing keeps it
local function getIsRemovable(container, fillUnitIndex)
    local spec = container[RMS_FluidContainer.SPEC_TABLE_NAME]
    if spec.transactionDepth > 0 then
        return false
    end
    for index, slot in ipairs(spec.slots) do
        if slot.hasPump or slot.fillUnitIndex ~= fillUnitIndex and container:getRMSFluidLiters(index) > RMS_Fluids.EPSILON then
            return false
        end
    end
    return true
end

---Deletes the container left empty, when its fill units allow it and nothing keeps it
-- @param table container fluid container
local function deleteIfEmpty(container)
    if container.spec_fillUnit.removeVehicleIfEmpty and getIsRemovable(container) then
        container:delete()
    end
end

---Dresses a drum place in the game's drum, painted and labelled
-- @param table container fluid container
-- @param entityId link node of the place
-- @param string baseKey XML key of the container
-- @return boolean isDressed true once dressed
local function dressDrum(container, link, baseKey)
    if not RMS_FluidContainer.loadNativeDrumVisual(link) then
        return false
    end
    RMS_FluidContainer.stripChildCollision(link)
    RMS_FluidContainer.applyDiffuseByName({ link }, "vis",
        Utils.getFilename(container.xmlFile:getValue(baseKey .. "#drumBodyDiffuse"), container.baseDirectory))
    -- the paint map holds the brand's print; the logo decal would hide it
    local decals = {}
    RMS_FluidContainer.collectNodesByName(link, "decal", decals)
    for _, node in ipairs(decals) do
        setVisibility(node, false)
    end
    RMS_FluidContainer.loadDrumPrints(container, link, baseKey)
    return true
end

---Links an I3D of product prints, its own maps, under a node
-- @param table container fluid container
-- @param entityId parentNode node the prints go under
-- @param string filename I3D of the prints
function RMS_FluidContainer.loadPrints(container, parentNode, filename)
    local i3dRoot = g_i3DManager:loadI3DFile(Utils.getFilename(filename, container.baseDirectory), false, false)
    if i3dRoot == 0 then
        Logging.xmlError(container.xmlFile, "Unable to load prints '%s'", filename)
        return
    end
    local prints = getChildAt(i3dRoot, 0)
    link(parentNode, prints)
    delete(i3dRoot)
end

---Applies one specular map to all materials below the nodes
-- @param table nodes nodes
-- @param string filename specular map
function RMS_FluidContainer.applySpecularToNodes(nodes, filename)
    for _, node in ipairs(nodes) do
        local materials = {}
        RMS_FluidContainer.collectMaterials(node, materials)
        for _, materialId in ipairs(materials) do
            local replacement = setMaterialGlossMapFromFile(materialId, filename, true, true, false)
            MaterialUtil.replaceMaterialRec(node, materialId, replacement)
        end
    end
end

---Returns a product map of the container
-- @param table container fluid container
-- @param string attribute XML attribute of the map
-- @return string filename map
local function getProductFilename(container, attribute)
    local filename = container.xmlFile:getValue("vehicle.rmsFluidContainer#" .. attribute)
    return Utils.getFilename(filename, container.baseDirectory)
end

---Dresses the game can in the product's plastic and label
-- @param entityId parentNode node the can goes under
function RMS_FluidContainer:dressRMSFluidGameCan(parentNode)
    if not RMS_FluidContainer.loadNativeVisual(RMS_FluidContainer.ADBLUE_CAN_I3D_FILENAME, parentNode) then
        return
    end
    RMS_FluidContainer.applyDiffuseByName({ parentNode }, "visual_lod", getProductFilename(self, "canDiffuse"))
    RMS_FluidContainer.loadPrints(self, parentNode, self.xmlFile:getValue("vehicle.rmsFluidContainer#canPrints"))
end

---Dresses a drum place in the game's plastic drum
-- @param table container fluid container
-- @param entityId link node of the place
-- @return boolean isDressed true once dressed
local function dressGameDrum(container, link)
    if not RMS_FluidContainer.loadNativeVisual(RMS_FluidContainer.ADBLUE_DRUM_I3D_FILENAME, link) then
        return false
    end
    RMS_FluidContainer.stripChildCollision(link)
    local visuals = {}
    RMS_FluidContainer.collectNodesByName(link, "visual_lod", visuals)
    RMS_FluidContainer.applyDiffuseToNodes(visuals, getProductFilename(container, "drumDiffuse"))
    RMS_FluidContainer.applySpecularToNodes(visuals, getProductFilename(container, "drumSpecular"))
    RMS_FluidContainer.loadPrints(container, link, container.xmlFile:getValue("vehicle.rmsFluidContainer#drumPrints"))
    return true
end

---Dresses the game tank in the product's colours and plate
-- @param table container fluid container
-- @return boolean isDressed true once dressed
local function dressGameTank(container)
    local visuals = {}
    RMS_FluidContainer.collectNodesByName(container.rootNode, "fertilizerTank_vis", visuals)
    if #visuals == 0 then
        Logging.error("RMS: the game tank visual is missing")
        return false
    end
    RMS_FluidContainer.applyDiffuseToNodes(visuals, getProductFilename(container, "tankDiffuse"))
    RMS_FluidContainer.loadPrints(container, container.rootNode, container.xmlFile:getValue("vehicle.rmsFluidContainer#tankPrints"))
    return true
end

---Loads the catalogue product and the liters left, a new container full
-- @param table? savegame savegame
function RMS_FluidContainer:onLoad(savegame)
    local spec = self[RMS_FluidContainer.SPEC_TABLE_NAME]
    spec.productKey = self.xmlFile:getValue("vehicle.rmsFluidContainer#productKey")
    spec.transactionDepth = 0
    spec.slots = { { fillUnitIndex = 1 } }

    local product = RMS_Fluids.PRODUCTS[spec.productKey]
    spec.capacity = self:getFillUnitCapacity(1)
    spec.format = product.formats ~= nil and product.formats[spec.capacity] or RMS_FluidContainer.getFormat(spec.capacity)
    spec.fillTypeIndex = g_fillTypeManager:getFillTypeIndexByName("RMS_" .. spec.productKey)
    local savedPumps = { false, false }
    if savegame ~= nil then
        local savegameKey = savegame.key .. "." .. RMS_FluidContainer.SPEC_NAME
        savedPumps = { savegame.xmlFile:getValue(savegameKey .. "#hasPump", false),
            savegame.xmlFile:getValue(savegameKey .. "#hasPump2", false) }
    end
    spec.dirtyFlag = self:getNextDirtyFlag()
    spec.carriedDirtyFlag = self:getNextDirtyFlag()
    spec.pumpDirtyFlag = self:getNextDirtyFlag()
    spec.isCarried = false
    self:setMassDirty()

    local baseKey = "vehicle.rmsFluidContainer"
    -- oils share fluidContainer.i3d, products with formats the game's models
    local isGameModel = product.formats ~= nil
    if isGameModel then
        if spec.format ~= "tank" then
            RMS_FluidContainer.stripChildCollision(self.i3dMappings.drumPalletVisualLink.nodeId)
        end
        if spec.format == "adBlueCan" then
            self:dressRMSFluidGameCan(self.i3dMappings.canVisualLink.nodeId)
        end
    else
        local mediumRoots = { self.i3dMappings.mediumVisualLink.nodeId }
        local largeRoots = { self.i3dMappings.largeVisualLink.nodeId }
        RMS_FluidContainer.stripChildCollision(mediumRoots[1])
        RMS_FluidContainer.stripChildCollision(largeRoots[1])
        RMS_FluidContainer.stripChildCollision(self.i3dMappings.drumPalletVisualLink.nodeId)

        spec.canDiffuseFilenames = {}
        for _, name in ipairs({ "mediumBody", "mediumCap", "mediumLabel", "largeBody", "largeLabel" }) do
            spec.canDiffuseFilenames[name] = Utils.getFilename(self.xmlFile:getValue(baseKey .. "#" .. name .. "Diffuse"), self.baseDirectory)
        end
        self:applyRMSFluidVisuals(mediumRoots[1], 5)
        self:applyRMSFluidVisuals(largeRoots[1], RMS_FluidContainer.CARRIED_CAPACITY)
    end

    if spec.capacity <= RMS_FluidContainer.CARRIED_CAPACITY then
        if self.isServer and savegame == nil and self:getNeedsSaving() then
            g_messageCenter:subscribe(MessageType.VEHICLE_LOADED, RMS_FluidContainer.onNewCanLoaded, self)
        end
        return
    end
    spec.slots = {}
    if spec.format == "tank" then
        local slot = { fillUnitIndex = 1, link = self.rootNode, hasPump = savedPumps[1], isNozzleOut = false }
        if dressGameTank(self) then
            slot.pump = loadPump(self, self.rootNode, RMS_FluidContainer.TANK_PUMP)
            loadTankHose(self, slot.pump)
            applyPump(slot)
        end
        spec.slots[1] = slot
        return
    end
    for index, place in ipairs(RMS_FluidContainer.DRUM_PLACES[#self.spec_fillUnit.fillUnits]) do
        local link = self.i3dMappings[place.link].nodeId
        local slot = { fillUnitIndex = index, link = link, collision = self.i3dMappings[place.collision].nodeId,
            hasPump = savedPumps[index], isNozzleOut = false }
        local isDressed
        if isGameModel then
            isDressed = dressGameDrum(self, link)
        else
            isDressed = dressDrum(self, link, baseKey)
        end
        if isDressed then
            local pumpPlace = nil
            if isGameModel then
                pumpPlace = place.isLeft and RMS_FluidContainer.ADBLUE_DRUM_PUMP_LEFT or RMS_FluidContainer.ADBLUE_DRUM_PUMP
            end
            slot.pump = loadPump(self, link, pumpPlace)
            applyPump(slot)
        end
        spec.slots[index] = slot
    end
end

---Applies native fill mass changes to small containers immediately
-- @param integer fillUnitIndex fill unit changed
function RMS_FluidContainer:onFillUnitFillLevelChanged(fillUnitIndex)
    if fillUnitIndex == 1 then
        self:updateMass()
    end
end

---Finds every descendant with the requested I3D node name
-- @param entityId node node searched
-- @param string requestedName name, any case
-- @param table result nodes found
function RMS_FluidContainer.collectNodesByName(node, requestedName, result)
    if string.lower(getName(node) or "") == string.lower(requestedName) then
        table.insert(result, node)
    end
    for index = 0, getNumOfChildren(node) - 1 do
        RMS_FluidContainer.collectNodesByName(getChildAt(node, index), requestedName, result)
    end
end

---Applies one product diffuse map to all materials below the supplied nodes
-- @param table nodes nodes
-- @param string filename diffuse map
function RMS_FluidContainer.applyDiffuseToNodes(nodes, filename)
    for _, node in ipairs(nodes) do
        local materials = {}
        RMS_FluidContainer.collectMaterials(node, materials)
        for _, materialId in ipairs(materials) do
            local replacement = setMaterialDiffuseMapFromFile(materialId, filename, true, true, false)
            MaterialUtil.replaceMaterialRec(node, materialId, replacement)
        end
    end
end

---Applies one diffuse map only to named visual nodes
-- @param table roots nodes searched
-- @param string nodeName name of the visual nodes
-- @param string filename diffuse map
function RMS_FluidContainer.applyDiffuseByName(roots, nodeName, filename)
    local nodes = {}
    for _, root in ipairs(roots) do
        RMS_FluidContainer.collectNodesByName(root, nodeName, nodes)
    end
    if #nodes == 0 then
        Logging.error("RMS: visual node '%s' is missing", nodeName)
        return
    end
    RMS_FluidContainer.applyDiffuseToNodes(nodes, filename)
end

---Dresses a can in the colours and label of its product
-- @param entityId root node of the can
-- @param float capacity capacity of the can (l)
function RMS_FluidContainer:applyRMSFluidVisuals(root, capacity)
    if self:getRMSFluidFormat() == "adBlueCan" then
        self:dressRMSFluidGameCan(root)
        return
    end
    local filenames = self[RMS_FluidContainer.SPEC_TABLE_NAME].canDiffuseFilenames
    if capacity > 5 then
        RMS_FluidContainer.applyDiffuseByName({ root }, "body60", filenames.largeBody)
        RMS_FluidContainer.applyDiffuseByName({ root }, "label60", filenames.largeLabel)
    else
        RMS_FluidContainer.applyDiffuseByName({ root }, "body", filenames.mediumBody)
        RMS_FluidContainer.applyDiffuseByName({ root }, "cap", filenames.mediumCap)
        RMS_FluidContainer.applyDiffuseByName({ root }, "label", filenames.mediumLabel)
    end
end

---Collects every distinct material used below the node
-- @param entityId node node searched
-- @param table materials materials found
function RMS_FluidContainer.collectMaterials(node, materials)
    if getHasClassId(node, ClassIds.SHAPE) then
        for slot = 0, getNumOfMaterials(node) - 1 do
            local materialId = getMaterial(node, slot)
            if materialId ~= 0 and not table.hasElement(materials, materialId) then
                table.insert(materials, materialId)
            end
        end
    end

    for index = 0, getNumOfChildren(node) - 1 do
        RMS_FluidContainer.collectMaterials(getChildAt(node, index), materials)
    end
end


---Drops the collision the game prop carries, the container has its own
-- @param entityId node node of the prop
function RMS_FluidContainer.stripCollision(node)
    setRigidBodyType(node, RigidBodyType.NONE)
    for index = 0, getNumOfChildren(node) - 1 do
        RMS_FluidContainer.stripCollision(getChildAt(node, index))
    end
end

---Drops the collisions of referenced visuals, keeping the RMS collision root
-- @param entityId node collision root
function RMS_FluidContainer.stripChildCollision(node)
    for index = 0, getNumOfChildren(node) - 1 do
        RMS_FluidContainer.stripCollision(getChildAt(node, index))
    end
end

---Cancels a running transfer and empties the hand before deletion
function RMS_FluidContainer:onDelete()
    local spec = self[RMS_FluidContainer.SPEC_TABLE_NAME]
    g_messageCenter:unsubscribe(MessageType.VEHICLE_LOADED, self)
    RMS_FluidTransfer.cancel(self)
    for _, slot in ipairs(spec.slots or {}) do
        if slot.carrierTool ~= nil then
            RMS_FluidHandTool.queueSetDown(slot.carrierTool)
        end
    end
end

---Hides a carried container, or sets it down in the world
-- @param table container fluid container
-- @param boolean isCarried true while carried
-- @param float? x set-down x (world)
-- @param float? y set-down y (world)
-- @param float? z set-down z (world)
-- @param float? rotY set-down heading (rad)
local function applyCarried(container, isCarried, x, y, z, rotY)
    if isCarried then
        container:removeFromPhysics()
        container:setVisibility(false)
    else
        container:setAbsolutePosition(x, y, z, 0, rotY, 0)
        container:setVisibility(true)
        container:addToPhysics()
    end
end

---Tells which player carries the container in hand, as the server knows it
-- @param integer index place
-- @return table? player player, nil for none
function RMS_FluidContainer:getRMSFluidCarrier(index)
    local handTool = getSlot(self, index).carrierTool
    return handTool ~= nil and handTool:getCarryingPlayer() or nil
end

---Hands the container to the hand tool standing for it, or sets it down
-- @param table? handTool hand tool carrying it, nil to set it down
-- @param float? x set-down x (world)
-- @param float? y set-down y (world)
-- @param float? z set-down z (world)
-- @param float? rotY set-down heading (rad)
function RMS_FluidContainer:setRMSFluidCarried(handTool, x, y, z, rotY)
    local spec = self[RMS_FluidContainer.SPEC_TABLE_NAME]
    spec.slots[1].carrierTool = handTool
    spec.isCarried = handTool ~= nil
    spec.setDownPose = { x, y, z, rotY }
    RMS_FluidTransfer.cancel(self)
    applyCarried(self, spec.isCarried, x, y, z, rotY)
    self:raiseDirtyFlags(spec.carriedDirtyFlag)
end

---Tells how many places the container has, one per drum
-- @return integer count number of places
function RMS_FluidContainer:getRMSFluidSlotCount()
    return #self[RMS_FluidContainer.SPEC_TABLE_NAME].slots
end

---Tells which drum stands nearest a point a player aims at
-- @param float x x (world)
-- @param float y y (world)
-- @param float z z (world)
-- @return integer index place, 1 for a container with one place
function RMS_FluidContainer:getRMSFluidSlotAt(x, y, z)
    local slots = self[RMS_FluidContainer.SPEC_TABLE_NAME].slots
    if #slots < 2 then
        return 1
    end
    local nearest, nearestDistance = 1, math.huge
    for index, slot in ipairs(slots) do
        local slotX, _, slotZ = getWorldTranslation(slot.link)
        local distance = MathUtil.vector2Length(x - slotX, z - slotZ)
        if distance < nearestDistance then
            nearest, nearestDistance = index, distance
        end
    end
    return nearest
end

---Tells whether a pump sits on a drum
-- @param integer index place
-- @return boolean hasPump true when a pump sits on it
function RMS_FluidContainer:getHasRMSFluidPump(index)
    return getSlot(self, index).hasPump == true
end

---Sets a pump on the bung of a drum or takes it off, on the server
-- @param boolean hasPump true to set the pump on
-- @param integer index place
function RMS_FluidContainer:setRMSFluidPump(hasPump, index)
    local slot = getSlot(self, index)
    slot.hasPump = hasPump
    applyPump(slot)
    self:raiseDirtyFlags(self[RMS_FluidContainer.SPEC_TABLE_NAME].pumpDirtyFlag)
    if not hasPump then
        deleteIfEmpty(self)
    end
end

---Hands the nozzle of a drum to its hand tool, or hangs it up
-- @param table? handTool hand tool carrying it, nil to hang it up
-- @param integer index place
function RMS_FluidContainer:setRMSFluidNozzle(handTool, index)
    local slot = getSlot(self, index)
    slot.carrierTool = handTool
    slot.isNozzleOut = handTool ~= nil
    RMS_FluidTransfer.cancel(self, index)
    applyPump(slot)
    self:raiseDirtyFlags(self[RMS_FluidContainer.SPEC_TABLE_NAME].pumpDirtyFlag)
end

---Returns how much of the hose of a drum's pump a player has pulled out
-- @param table player player
-- @param integer index place
-- @return float span length pulled out (m)
function RMS_FluidContainer:getRMSFluidHoseSpan(player, index)
    local x, _, z = player:getPosition()
    local outletX, _, outletZ = getWorldTranslation(getSlot(self, index).pump.hoseOutlet)
    return MathUtil.vector2Length(x - outletX, z - outletZ)
end

---Called on update: runs the transfer on the server
-- @param float dt time since the last frame (ms)
-- @param boolean isActiveForInput true if vehicle is active for input
-- @param boolean isActiveForInputIgnoreSelection true if vehicle is active for input ignoring the selection
-- @param boolean isSelected true if vehicle is selected
function RMS_FluidContainer:onUpdate(dt, isActiveForInput, isActiveForInputIgnoreSelection, isSelected)
    if self.isServer and RMS_FluidTransfer.getHasActive(self) then
        RMS_FluidTransfer.update(self, dt)
        if RMS_FluidTransfer.getHasActive(self) then
            self:raiseActive()
        end
    end
end

---Saves the pump and cancels transient transfer state
-- @param table xmlFile savegame file
-- @param string key key of the specialization
-- @param table usedModNames mods used
function RMS_FluidContainer:saveToXMLFile(xmlFile, key, usedModNames)
    if self.isServer then
        RMS_FluidTransfer.cancel(self)
    end
    local slots = self[RMS_FluidContainer.SPEC_TABLE_NAME].slots
    xmlFile:setValue(key .. "#hasPump", slots[1].hasPump == true)
    if slots[2] ~= nil then
        xmlFile:setValue(key .. "#hasPump2", slots[2].hasPump == true)
    end
end

---Sends the transfer, carried and pump states to a joining client
-- @param integer streamId stream id
-- @param Connection connection connection
function RMS_FluidContainer:onWriteStream(streamId, connection)
    local spec = self[RMS_FluidContainer.SPEC_TABLE_NAME]
    streamWriteBool(streamId, spec.isCarried)
    for _, slot in ipairs(spec.slots) do
        streamWriteBool(streamId, slot.activeTransfer ~= nil)
        streamWriteBool(streamId, slot.hasPump == true)
        streamWriteBool(streamId, slot.isNozzleOut == true)
    end
end

---Receives the transfer, carried and pump states on joining
-- @param integer streamId stream id
-- @param Connection connection connection
function RMS_FluidContainer:onReadStream(streamId, connection)
    local spec = self[RMS_FluidContainer.SPEC_TABLE_NAME]
    spec.isCarried = streamReadBool(streamId)
    for _, slot in ipairs(spec.slots) do
        slot.isTransferActive = streamReadBool(streamId)
        slot.hasPump = streamReadBool(streamId)
        slot.isNozzleOut = streamReadBool(streamId)
        if slot.pump ~= nil then
            applyPump(slot)
        end
    end
    -- Native mass updates do not run on idle containers
    self:updateMass()
    if spec.isCarried then
        applyCarried(self, true)
    end
end

---Sends changed transfer, carried and pump states to the clients
-- @param integer streamId stream id
-- @param Connection connection connection
-- @param integer dirtyMask dirty mask
function RMS_FluidContainer:onWriteUpdateStream(streamId, connection, dirtyMask)
    if not connection:getIsServer() then
        local spec = self[RMS_FluidContainer.SPEC_TABLE_NAME]
        if streamWriteBool(streamId, bit32.band(dirtyMask, spec.dirtyFlag) ~= 0) then
            for _, slot in ipairs(spec.slots) do
                streamWriteBool(streamId, slot.activeTransfer ~= nil)
            end
        end
        if streamWriteBool(streamId, bit32.band(dirtyMask, spec.carriedDirtyFlag) ~= 0)
            and not streamWriteBool(streamId, spec.isCarried) then
            for index = 1, 4 do
                streamWriteFloat32(streamId, spec.setDownPose[index])
            end
        end
        if streamWriteBool(streamId, bit32.band(dirtyMask, spec.pumpDirtyFlag) ~= 0) then
            for _, slot in ipairs(spec.slots) do
                streamWriteBool(streamId, slot.hasPump == true)
                streamWriteBool(streamId, slot.isNozzleOut == true)
            end
        end
    end
end

---Receives changed transfer, carried and pump states from the server
-- @param integer streamId stream id
-- @param integer timestamp timestamp
-- @param Connection connection connection
function RMS_FluidContainer:onReadUpdateStream(streamId, timestamp, connection)
    if connection:getIsServer() then
        local spec = self[RMS_FluidContainer.SPEC_TABLE_NAME]
        if streamReadBool(streamId) then
            for _, slot in ipairs(spec.slots) do
                slot.isTransferActive = streamReadBool(streamId)
            end
            self:updateMass()
        end
        if streamReadBool(streamId) then
            spec.isCarried = streamReadBool(streamId)
            if spec.isCarried then
                applyCarried(self, true)
            else
                local x = streamReadFloat32(streamId)
                local y = streamReadFloat32(streamId)
                local z = streamReadFloat32(streamId)
                applyCarried(self, false, x, y, z, streamReadFloat32(streamId))
            end
        end
        if streamReadBool(streamId) then
            for _, slot in ipairs(spec.slots) do
                slot.hasPump = streamReadBool(streamId)
                slot.isNozzleOut = streamReadBool(streamId)
                if slot.pump ~= nil then
                    applyPump(slot)
                end
            end
        end
    end
end

---Tells whether a transfer runs from a place
-- @param integer index place
-- @return boolean isActive true while a transfer runs
function RMS_FluidContainer:getIsRMSFluidTransferActive(index)
    local slot = getSlot(self, index)
    if self.isServer then
        return slot.activeTransfer ~= nil
    end

    return slot.isTransferActive == true
end

---Returns the immutable catalogue product key
-- @return string productKey key of the product
function RMS_FluidContainer:getRMSFluidProductKey()
    return self[RMS_FluidContainer.SPEC_TABLE_NAME].productKey
end

---Returns the fill unit of a place, the first while loading
-- @param table container fluid container
-- @param integer? index place, the first by default
-- @return integer fillUnitIndex fill unit
local function getFillUnitIndex(container, index)
    local slots = container[RMS_FluidContainer.SPEC_TABLE_NAME].slots
    return slots ~= nil and slots[index or 1] ~= nil and slots[index or 1].fillUnitIndex or 1
end

---Returns the liters left in a place, the first by default
-- @param integer? index place
-- @return float liters liters left
function RMS_FluidContainer:getRMSFluidLiters(index)
    return self:getFillUnitFillLevel(getFillUnitIndex(self, index))
end

---Returns the capacity of a place: a can, a jerrican or one drum
-- @param integer? index place, the first by default
-- @return float capacity capacity (l)
function RMS_FluidContainer:getRMSFluidCapacity(index)
    return self:getFillUnitCapacity(getFillUnitIndex(self, index))
end

---Returns the remaining share of a place
-- @param integer? index place, the first by default
-- @return float share share left, 0 to 1
function RMS_FluidContainer:getRMSFluidPercentage(index)
    return self:getRMSFluidLiters(index) / self:getRMSFluidCapacity(index)
end

local FLUID_KIND_TEXT_KEYS = {
    engineOil = "rms_fluid_hud_engineOil",
    transmissionHydraulic = "rms_fluid_hud_transmissionHydraulic",
    coolant = "rms_fluid_hud_coolant",
    adBlue = "rms_fluid_hud_adBlue"
}

---Returns the kind of fluid a product is
-- @param table product catalogue product
-- @return string kind "engineOil", "adBlue", "coolant" or "transmissionHydraulic"
local function getFluidKind(product)
    if product.compatibleCircuits.engineOil then
        return "engineOil"
    elseif product.compatibleCircuits.adBlue then
        return "adBlue"
    elseif product.compatibleCircuits.coolant then
        return "coolant"
    end
    return "transmissionHydraulic"
end

---Returns the kind of container: medium, large, adBlueCan, drum or tank
-- @return string format format
function RMS_FluidContainer:getRMSFluidFormat()
    return self[RMS_FluidContainer.SPEC_TABLE_NAME].format
end

---Returns the short name of the kind of fluid a container holds
-- @return string text name of the kind
function RMS_FluidContainer:getRMSFluidKindText()
    local product = RMS_Fluids.PRODUCTS[self[RMS_FluidContainer.SPEC_TABLE_NAME].productKey]
    return g_i18n:getText(FLUID_KIND_TEXT_KEYS[getFluidKind(product)])
end

---Titles the info box with the brand and the product
-- @param function superFunc original function
-- @return string title title
function RMS_FluidContainer:getInfoBoxTitle(superFunc)
    local product = RMS_Fluids.PRODUCTS[self[RMS_FluidContainer.SPEC_TABLE_NAME].productKey]
    return g_brandManager:getBrandByName(product.brand).title .. " " .. product.name
end

---Shows the fluid left in each container of the info box
-- @param function superFunc original function
-- @param table box info box
function RMS_FluidContainer:showInfo(superFunc, box)
    superFunc(self, box)
    local spec = self[RMS_FluidContainer.SPEC_TABLE_NAME]
    local hasPump, hasDrum = false, false
    for index, slot in ipairs(spec.slots) do
        local label = #spec.slots > 1 and string.format("%s %d", g_i18n:getText("rms_fluid_drum_label"), index)
            or self:getRMSFluidKindText()
        local liters = self:getRMSFluidLiters(index)
        -- whole liters without grouping, a can to the tenth
        local value = string.format("%d", math.floor(liters + 0.5))
        if self:getRMSFluidCapacity(index) <= RMS_FluidContainer.CARRIED_CAPACITY then
            value = RMS_FluidWorkshop.formatLiters(liters)
        end
        box:addLine(label, value .. " " .. g_i18n:getText("unit_literShort"))
        hasPump = hasPump or slot.hasPump == true
        hasDrum = hasDrum or slot.pump ~= nil
    end
    if hasDrum and not hasPump then
        box:addLine(g_i18n:getText("rms_drum_pump_required"), "", true)
    end
end

---Applies the mass of the fluid at once to a can or jerrican
-- @param function superFunc original function
function RMS_FluidContainer:updateMass(superFunc)
    superFunc(self)
    if self.isServer and self:getRMSFluidCapacity() <= RMS_FluidContainer.CARRIED_CAPACITY then
        local component = self.components[1]
        if component.isDynamic and component.lastMass ~= component.mass then
            setMass(component.node, component.mass)
            component.lastMass = component.mass
        end
    end
end

---Lets the game delete the container a place leaves empty, unless something keeps it
-- @param function superFunc original function
-- @param integer farmId farm
-- @param integer fillUnitIndex fill unit
-- @param float fillLevelDelta liters to add, negative to remove
-- @param integer fillTypeIndex fill type
-- @param integer toolType tool type
-- @param table? fillPositionData fill position
-- @return float appliedDelta liters added, negative when removed
function RMS_FluidContainer:addFillUnitFillLevel(superFunc, farmId, fillUnitIndex, fillLevelDelta, fillTypeIndex, toolType, fillPositionData)
    local spec = self.spec_fillUnit
    local removeVehicleIfEmpty = spec.removeVehicleIfEmpty
    spec.removeVehicleIfEmpty = removeVehicleIfEmpty and getIsRemovable(self, fillUnitIndex)
    local appliedDelta = superFunc(self, farmId, fillUnitIndex, fillLevelDelta, fillTypeIndex, toolType, fillPositionData)
    spec.removeVehicleIfEmpty = removeVehicleIfEmpty
    return appliedDelta
end

---Lets a player pick up a can or a jerrican
-- @param function superFunc original function
-- @param table byPlayer player
-- @return boolean canBePickedUp true when the player may pick it up
function RMS_FluidContainer:getCanBePickedUp(superFunc, byPlayer)
    return self:getRMSFluidCapacity() <= RMS_FluidContainer.CARRIED_CAPACITY and superFunc(self, byPlayer)
end

---Returns the factor on the break force of the hands' joint
-- @return float factor factor, at least 1
function RMS_FluidContainer:getHandsJointBreakForceFactor()
    return math.max(HandToolHands.MAXIMUM_PICKUP_MASS / self:getTotalMass(), 1)
end

---Sets a new can on the ground under it once loaded
-- @param table vehicle vehicle just loaded
function RMS_FluidContainer:onNewCanLoaded(vehicle)
    if vehicle ~= self then
        return
    end
    g_messageCenter:unsubscribe(MessageType.VEHICLE_LOADED, self)
    local x, y, z = getWorldTranslation(self.rootNode)
    local _, rotY, _ = getWorldRotation(self.rootNode)
    local groundY = getTerrainHeightAtWorldPos(g_terrainNode, x, y, z)
    local _, _, hitY, _ = RaycastUtil.raycastClosest(x, y, z, 0, -1, 0, math.max(y - groundY, 0) + 0.1, RMS_FluidHandTool.CARRY_MASK)
    self:removeFromPhysics()
    self:setAbsolutePosition(x, math.max(groundY, hitY or groundY), z, 0, rotY, 0)
    self:addToPhysics()
end

---Deletes the container once, a delayed deletion not repeated
-- @param function superFunc original function
-- @param boolean? immediate true to delete at once
function RMS_FluidContainer:delete(superFunc, immediate)
    if self.isDeleted or self.isDeleting or (self.markedForDeletion and not immediate) then
        return
    end

    superFunc(self, immediate)
end

---Returns the active format collision meshes for native tension belts
-- @param function superFunc original function
-- @return table nodes mesh nodes
function RMS_FluidContainer:getMeshNodes(superFunc)
    local capacity = self:getRMSFluidCapacity()
    local format = self:getRMSFluidFormat()
    if format == "tank" then
        return superFunc(self)
    elseif format == "adBlueCan" then
        return { self.i3dMappings.canCollision.nodeId }
    elseif capacity <= 5 then
        return { self.i3dMappings.mediumCanCollision.nodeId }
    elseif capacity <= 25 then
        return { self.i3dMappings.largeCanCollision.nodeId }
    end
    local nodes = { self.i3dMappings.drumPalletCollision.nodeId }
    for _, slot in ipairs(self[RMS_FluidContainer.SPEC_TABLE_NAME].slots) do
        table.insert(nodes, slot.collision)
    end
    return nodes
end

---Keeps the container, even empty, through an allocation
function RMS_FluidContainer:beginRMSFluidTransaction()
    local spec = self[RMS_FluidContainer.SPEC_TABLE_NAME]
    spec.transactionDepth = spec.transactionDepth + 1
end

---Ends an allocation, deleting the container a committed one left empty
-- @param boolean committed true when the allocation was committed
function RMS_FluidContainer:endRMSFluidTransaction(committed)
    local spec = self[RMS_FluidContainer.SPEC_TABLE_NAME]
    spec.transactionDepth = spec.transactionDepth - 1
    if committed then
        deleteIfEmpty(self)
    end
end

---Adds liters to a place, removing them when negative
-- @param table container fluid container
-- @param float delta liters to add, negative to remove
-- @param integer? index place, the first by default
-- @return float appliedDelta liters added, negative when removed
local function addLiters(container, delta, index)
    return container:addFillUnitFillLevel(container:getOwnerFarmId(), getFillUnitIndex(container, index), delta,
        container[RMS_FluidContainer.SPEC_TABLE_NAME].fillTypeIndex, ToolType.UNDEFINED)
end

---Removes liters from a place
-- @param float liters liters to remove
-- @param integer? index place, the first by default
-- @return float removed liters removed
function RMS_FluidContainer:removeRMSFluidLiters(liters, index)
    return -addLiters(self, -liters, index)
end

---Puts back liters a rolled-back allocation took
-- @param float liters liters to put back
-- @param integer? index place, the first by default
-- @return float added liters put back
function RMS_FluidContainer:restoreRMSFluidLiters(liters, index)
    return addLiters(self, liters, index)
end

---Gives a container back the liters and pumps it was stored with, keeping it even empty
-- @param table stored { { liters = float, hasPump = boolean }, ... } one entry per place
function RMS_FluidContainer:setRMSFluidStored(stored)
    self:beginRMSFluidTransaction()
    for index, place in ipairs(stored) do
        if getSlot(self, index) ~= nil then
            addLiters(self, place.liters - self:getRMSFluidLiters(index), index)
            if place.hasPump then
                self:setRMSFluidPump(true, index)
            end
        end
    end
    self:endRMSFluidTransaction(false)
end
