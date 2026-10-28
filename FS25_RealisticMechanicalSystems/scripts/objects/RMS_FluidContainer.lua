-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---Physical fluid container.
RMS_FluidContainer = {}
RMS_FluidContainer.SPEC_NAME = "FS25_RealisticMechanicalSystems.rmsFluidContainer"
RMS_FluidContainer.SPEC_TABLE_NAME = "spec_" .. RMS_FluidContainer.SPEC_NAME
RMS_FluidContainer.DRUM_I3D_FILENAME = "data/maps/textures/shared/props/motorex/motorexOilBarrel.i3d"
RMS_FluidContainer.CARRIED_CAPACITY = 25
RMS_FluidContainer.PUMP_I3D_FILENAME = "objects/drumPump/drumPumpMounted.i3d"
RMS_FluidContainer.PUMP_TRANSLATION = { 0, 0.898252845, 0.1980392635 }

---Checks if all prerequisite specializations are loaded
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
    schema:register(XMLValueType.STRING, baseKey .. "#largeBodyDiffuse", "25 liter body diffuse map")
    schema:register(XMLValueType.STRING, baseKey .. "#largeLabelDiffuse", "25 liter label diffuse map")
    schema:register(XMLValueType.STRING, baseKey .. "#drumBodyDiffuse", "200 liter drum diffuse map")
    schema:register(XMLValueType.STRING, baseKey .. "#drumLabelDiffuse", "200 liter drum label diffuse map")
    schema:setXMLSpecializationType()

    Vehicle.xmlSchemaSavegame:register(XMLValueType.BOOL,
        "vehicles.vehicle(?)." .. RMS_FluidContainer.SPEC_NAME .. "#hasPump", "Whether a pump sits on the drum")
end

---Registers public container functions
function RMS_FluidContainer.registerFunctions(vehicleType)
    SpecializationUtil.registerFunction(vehicleType, "getRMSFluidProductKey", RMS_FluidContainer.getRMSFluidProductKey)
    SpecializationUtil.registerFunction(vehicleType, "getRMSFluidLiters", RMS_FluidContainer.getRMSFluidLiters)
    SpecializationUtil.registerFunction(vehicleType, "getRMSFluidCapacity", RMS_FluidContainer.getRMSFluidCapacity)
    SpecializationUtil.registerFunction(vehicleType, "getRMSFluidPercentage", RMS_FluidContainer.getRMSFluidPercentage)
    SpecializationUtil.registerFunction(vehicleType, "beginRMSFluidTransaction", RMS_FluidContainer.beginRMSFluidTransaction)
    SpecializationUtil.registerFunction(vehicleType, "endRMSFluidTransaction", RMS_FluidContainer.endRMSFluidTransaction)
    SpecializationUtil.registerFunction(vehicleType, "removeRMSFluidLiters", RMS_FluidContainer.removeRMSFluidLiters)
    SpecializationUtil.registerFunction(vehicleType, "restoreRMSFluidLiters", RMS_FluidContainer.restoreRMSFluidLiters)
    SpecializationUtil.registerFunction(vehicleType, "deleteRMSContainerIfEmpty", RMS_FluidContainer.deleteRMSContainerIfEmpty)
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
end

---Registers native container behavior overrides
function RMS_FluidContainer.registerOverwrittenFunctions(vehicleType)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "delete", RMS_FluidContainer.delete)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "getCanBePickedUp", RMS_FluidContainer.getCanBePickedUp)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "getMeshNodes", RMS_FluidContainer.getMeshNodes)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "showInfo", RMS_FluidContainer.showInfo)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "updateMass", RMS_FluidContainer.updateMass)
end

---Registers load, save and network callbacks
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

---Loads the native GIANTS drum without importing its static rigid body
function RMS_FluidContainer.loadNativeDrumVisual(parentNode)
    local i3dRoot = g_i3DManager:loadI3DFile(RMS_FluidContainer.DRUM_I3D_FILENAME, false, false)
    if i3dRoot == nil or i3dRoot == 0 or getNumOfChildren(i3dRoot) == 0 then
        if i3dRoot ~= nil and i3dRoot ~= 0 then
            delete(i3dRoot)
        end
        Logging.error("RMS: unable to load native fluid drum '%s'", RMS_FluidContainer.DRUM_I3D_FILENAME)
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

---Loads the pump a drum carries on its bung
local function loadPump(container, drumLink)
    local i3dRoot = g_i3DManager:loadI3DFile(Utils.getFilename(RMS_FluidContainer.PUMP_I3D_FILENAME, container.baseDirectory), false, false)
    local node = getChildAt(i3dRoot, 0)
    link(drumLink, node)
    delete(i3dRoot)
    setTranslation(node, unpack(RMS_FluidContainer.PUMP_TRANSLATION))

    local graphics = getChildAt(node, 0)
    return { node = node, hoseOutlet = getChildAt(graphics, 2), restHose = getChildAt(graphics, 4), storedNozzle = getChildAt(graphics, 5) }
end

---Shows the pump of a drum as it stands
local function applyPump(container)
    local spec = container[RMS_FluidContainer.SPEC_TABLE_NAME]
    setVisibility(spec.pump.node, spec.hasPump)
    setVisibility(spec.pump.storedNozzle, not spec.isNozzleOut)
    setVisibility(spec.pump.restHose, not spec.isNozzleOut)
end

---Loads the catalogue product and the liters left, a new container full
function RMS_FluidContainer:onLoad(savegame)
    local spec = self[RMS_FluidContainer.SPEC_TABLE_NAME]
    if spec == nil then
        spec = self.spec_rmsFluidContainer or {}
        self[RMS_FluidContainer.SPEC_TABLE_NAME] = spec
    end
    spec.productKey = self.xmlFile:getValue("vehicle.rmsFluidContainer#productKey")
    spec.transactionDepth = 0
    spec.pendingDeleteCheck = false
    spec.activeTransfer = nil
    spec.isTransferActive = false

    local product = RMS_Fluids.PRODUCTS[spec.productKey]
    if product == nil then
        Logging.xmlError(self.xmlFile, "Unknown RMS fluid product key '%s'", tostring(spec.productKey))
        return
    end

    spec.capacity = self:getFillUnitCapacity(1)
    spec.fillTypeIndex = g_fillTypeManager:getFillTypeIndexByName("RMS_" .. spec.productKey)
    spec.hasPump = false
    if savegame ~= nil then
        local savegameKey = savegame.key .. "." .. RMS_FluidContainer.SPEC_NAME
        spec.hasPump = savegame.xmlFile:getValue(savegameKey .. "#hasPump", false)
    end
    spec.dirtyFlag = self:getNextDirtyFlag()
    spec.carriedDirtyFlag = self:getNextDirtyFlag()
    spec.pumpDirtyFlag = self:getNextDirtyFlag()
    spec.isCarried = false
    spec.isNozzleOut = false
    self:setMassDirty()

    local baseKey = "vehicle.rmsFluidContainer"
    local mediumRoots = { self.i3dMappings.mediumVisualLink.nodeId }
    local largeRoots = { self.i3dMappings.largeVisualLink.nodeId }
    local drumRoots = { self.i3dMappings.drumVisualLink.nodeId }
    local hasDrumVisual = RMS_FluidContainer.loadNativeDrumVisual(drumRoots[1])
    RMS_FluidContainer.stripChildCollision(mediumRoots[1])
    RMS_FluidContainer.stripChildCollision(largeRoots[1])
    RMS_FluidContainer.stripChildCollision(drumRoots[1])
    RMS_FluidContainer.stripChildCollision(self.i3dMappings.drumPalletVisualLink.nodeId)

    spec.canDiffuseFilenames = {}
    for _, name in ipairs({ "mediumBody", "mediumCap", "mediumLabel", "largeBody", "largeLabel" }) do
        spec.canDiffuseFilenames[name] = Utils.getFilename(self.xmlFile:getValue(baseKey .. "#" .. name .. "Diffuse"), self.baseDirectory)
    end
    self:applyRMSFluidVisuals(mediumRoots[1], 5)
    self:applyRMSFluidVisuals(largeRoots[1], 25)

    if hasDrumVisual then
        RMS_FluidContainer.applyDiffuseByName(
            drumRoots,
            "vis",
            Utils.getFilename(self.xmlFile:getValue(baseKey .. "#drumBodyDiffuse"), self.baseDirectory)
        )
        RMS_FluidContainer.applyDiffuseByName(
            drumRoots,
            "decal",
            Utils.getFilename(self.xmlFile:getValue(baseKey .. "#drumLabelDiffuse"), self.baseDirectory)
        )
    end

    if hasDrumVisual and spec.capacity > RMS_FluidContainer.CARRIED_CAPACITY then
        spec.pump = loadPump(self, drumRoots[1])
        applyPump(self)
    end
end

---Applies native fill mass changes to small containers immediately
function RMS_FluidContainer:onFillUnitFillLevelChanged(fillUnitIndex)
    if fillUnitIndex == 1 then
        self:updateMass()
    end
end

---Finds every descendant with the requested I3D node name
function RMS_FluidContainer.collectNodesByName(node, requestedName, result)
    if string.lower(getName(node) or "") == string.lower(requestedName) then
        table.insert(result, node)
    end
    for index = 0, getNumOfChildren(node) - 1 do
        RMS_FluidContainer.collectNodesByName(getChildAt(node, index), requestedName, result)
    end
end

---Applies one product diffuse map to all materials below the supplied nodes
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
-- @param entityId root node holding the can
-- @param float capacity format of the can in liters
function RMS_FluidContainer:applyRMSFluidVisuals(root, capacity)
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
function RMS_FluidContainer.stripCollision(node)
    setRigidBodyType(node, RigidBodyType.NONE)
    for index = 0, getNumOfChildren(node) - 1 do
        RMS_FluidContainer.stripCollision(getChildAt(node, index))
    end
end

---Drops the collisions of referenced visuals, keeping the RMS collision root
function RMS_FluidContainer.stripChildCollision(node)
    for index = 0, getNumOfChildren(node) - 1 do
        RMS_FluidContainer.stripCollision(getChildAt(node, index))
    end
end

---Cancels a running transfer and empties the hand before deletion
function RMS_FluidContainer:onDelete()
    local spec = self[RMS_FluidContainer.SPEC_TABLE_NAME]
    RMS_FluidTransfer.cancel(self)
    if spec.carrierTool ~= nil then
        RMS_FluidHandTool.queueSetDown(spec.carrierTool)
    end
end

---Takes the container out of the world while carried, or sets it back down
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
-- @return table? player carrying player
function RMS_FluidContainer:getRMSFluidCarrier()
    local handTool = self[RMS_FluidContainer.SPEC_TABLE_NAME].carrierTool
    return handTool ~= nil and handTool:getCarryingPlayer() or nil
end

---Hands the container to the hand tool standing for it, or sets it down
-- @param table? handTool hand tool carrying it, nil to set it down
-- @param float? x world position it is set down at
-- @param float? y
-- @param float? z
-- @param float? rotY heading it is set down with
function RMS_FluidContainer:setRMSFluidCarried(handTool, x, y, z, rotY)
    local spec = self[RMS_FluidContainer.SPEC_TABLE_NAME]
    spec.carrierTool = handTool
    spec.isCarried = handTool ~= nil
    spec.setDownPose = { x, y, z, rotY }
    RMS_FluidTransfer.cancel(self)
    applyCarried(self, spec.isCarried, x, y, z, rotY)
    self:raiseDirtyFlags(spec.carriedDirtyFlag)
end

---Tells whether a pump sits on the drum
-- @return boolean hasPump
function RMS_FluidContainer:getHasRMSFluidPump()
    return self[RMS_FluidContainer.SPEC_TABLE_NAME].hasPump
end

---Sets a pump on the bung of the drum or takes it off, on the server
-- @param boolean hasPump
function RMS_FluidContainer:setRMSFluidPump(hasPump)
    local spec = self[RMS_FluidContainer.SPEC_TABLE_NAME]
    spec.hasPump = hasPump
    applyPump(self)
    self:raiseDirtyFlags(spec.pumpDirtyFlag)
    if not hasPump then
        self:deleteRMSContainerIfEmpty()
    end
end

---Hands the nozzle of the drum to its hand tool, or hangs it up
-- @param table? handTool hand tool carrying it, nil to hang it up
function RMS_FluidContainer:setRMSFluidNozzle(handTool)
    local spec = self[RMS_FluidContainer.SPEC_TABLE_NAME]
    spec.carrierTool = handTool
    spec.isNozzleOut = handTool ~= nil
    RMS_FluidTransfer.cancel(self)
    applyPump(self)
    self:raiseDirtyFlags(spec.pumpDirtyFlag)
end

---Returns how much of the hose a player has pulled out
-- @param table player player holding or taking the nozzle
-- @return float span metres between the player and the pump
function RMS_FluidContainer:getRMSFluidHoseSpan(player)
    local x, _, z = player:getPosition()
    local outletX, _, outletZ = getWorldTranslation(self[RMS_FluidContainer.SPEC_TABLE_NAME].pump.hoseOutlet)
    return MathUtil.vector2Length(x - outletX, z - outletZ)
end

---Advances the active transfer only on the authoritative server
function RMS_FluidContainer:onUpdate(dt, isActiveForInput, isActiveForInputIgnoreSelection, isSelected)
    local spec = self[RMS_FluidContainer.SPEC_TABLE_NAME]

    if self.isServer and spec.activeTransfer ~= nil then
        RMS_FluidTransfer.update(self, dt)
        if spec.activeTransfer ~= nil then
            self:raiseActive()
        end
    end
end

---Saves the pump and cancels transient transfer state
function RMS_FluidContainer:saveToXMLFile(xmlFile, key, usedModNames)
    if self.isServer then
        RMS_FluidTransfer.cancel(self)
    end
    local spec = self[RMS_FluidContainer.SPEC_TABLE_NAME]
    xmlFile:setValue(key .. "#hasPump", spec.hasPump)
end

---Sends the transfer, carried and pump states to a joining client
function RMS_FluidContainer:onWriteStream(streamId, connection)
    local spec = self[RMS_FluidContainer.SPEC_TABLE_NAME]
    streamWriteBool(streamId, spec.activeTransfer ~= nil)
    streamWriteBool(streamId, spec.isCarried)
    streamWriteBool(streamId, spec.hasPump)
    streamWriteBool(streamId, spec.isNozzleOut)
end

---Receives the transfer, carried and pump states on joining
function RMS_FluidContainer:onReadStream(streamId, connection)
    local spec = self[RMS_FluidContainer.SPEC_TABLE_NAME]
    spec.isTransferActive = streamReadBool(streamId)
    spec.isCarried = streamReadBool(streamId)
    spec.hasPump = streamReadBool(streamId)
    spec.isNozzleOut = streamReadBool(streamId)
    -- Native mass updates do not run on idle containers.
    self:updateMass()
    if spec.isCarried then
        applyCarried(self, true)
    end
    if spec.pump ~= nil then
        applyPump(self)
    end
end

---Sends changed transfer, carried and pump states to the clients
function RMS_FluidContainer:onWriteUpdateStream(streamId, connection, dirtyMask)
    if not connection:getIsServer() then
        local spec = self[RMS_FluidContainer.SPEC_TABLE_NAME]
        if streamWriteBool(streamId, bit32.band(dirtyMask, spec.dirtyFlag) ~= 0) then
            streamWriteBool(streamId, spec.activeTransfer ~= nil)
        end
        if streamWriteBool(streamId, bit32.band(dirtyMask, spec.carriedDirtyFlag) ~= 0)
            and not streamWriteBool(streamId, spec.isCarried) then
            for index = 1, 4 do
                streamWriteFloat32(streamId, spec.setDownPose[index])
            end
        end
        if streamWriteBool(streamId, bit32.band(dirtyMask, spec.pumpDirtyFlag) ~= 0) then
            streamWriteBool(streamId, spec.hasPump)
            streamWriteBool(streamId, spec.isNozzleOut)
        end
    end
end

---Receives changed transfer, carried and pump states from the server
function RMS_FluidContainer:onReadUpdateStream(streamId, timestamp, connection)
    if connection:getIsServer() then
        local spec = self[RMS_FluidContainer.SPEC_TABLE_NAME]
        if streamReadBool(streamId) then
            spec.isTransferActive = streamReadBool(streamId)
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
            spec.hasPump = streamReadBool(streamId)
            spec.isNozzleOut = streamReadBool(streamId)
            applyPump(self)
        end
    end
end

-- @return boolean isActive true while fluid is being poured
function RMS_FluidContainer:getIsRMSFluidTransferActive()
    local spec = self[RMS_FluidContainer.SPEC_TABLE_NAME]
    if self.isServer then
        return spec.activeTransfer ~= nil
    end

    return spec.isTransferActive
end

---Returns the immutable catalogue product key
function RMS_FluidContainer:getRMSFluidProductKey()
    return self[RMS_FluidContainer.SPEC_TABLE_NAME].productKey
end

---Returns the liters left
function RMS_FluidContainer:getRMSFluidLiters()
    return self:getFillUnitFillLevel(1)
end

---Returns the capacity of the container format
function RMS_FluidContainer:getRMSFluidCapacity()
    return self:getFillUnitCapacity(1)
end

---Returns the remaining percentage
function RMS_FluidContainer:getRMSFluidPercentage()
    local capacity = self:getRMSFluidCapacity()
    return capacity > 0 and math.clamp(self:getRMSFluidLiters() / capacity, 0, 1) or 0
end

local FLUID_KIND_TEXT_KEYS = {
    engineOil = "rms_fluid_hud_engineOil",
    transmissionHydraulic = "rms_fluid_hud_transmissionHydraulic",
    coolant = "rms_fluid_hud_coolant"
}

---Returns the kind of fluid a product is
local function getFluidKind(product)
    if product.compatibleCircuits.engineOil then
        return "engineOil"
    elseif product.compatibleCircuits.coolant then
        return "coolant"
    end
    return "transmissionHydraulic"
end

---Returns the short name of the kind of fluid a container holds
-- @return string text kind of fluid, as the container shows it
function RMS_FluidContainer:getRMSFluidKindText()
    local product = RMS_Fluids.PRODUCTS[self[RMS_FluidContainer.SPEC_TABLE_NAME].productKey]
    return g_i18n:getText(FLUID_KIND_TEXT_KEYS[getFluidKind(product)])
end

---Shows the fluid, its liters, the brand and the product in the info box
function RMS_FluidContainer:showInfo(superFunc, box)
    superFunc(self, box)
    local spec = self[RMS_FluidContainer.SPEC_TABLE_NAME]
    local product = RMS_Fluids.PRODUCTS[spec.productKey]
    box:addLine(g_i18n:getText(FLUID_KIND_TEXT_KEYS[getFluidKind(product)]), string.format("%s / %s %s", RMS_FluidWorkshop.formatLiters(self:getRMSFluidLiters()),
        RMS_FluidWorkshop.formatLiters(self:getRMSFluidCapacity()), g_i18n:getText("unit_literShort")))
    box:addLine(g_brandManager:getBrandByName(product.brand).title, product.name)
    if spec.pump ~= nil and not spec.hasPump then
        box:addLine(g_i18n:getText("rms_drum_pump_required"), "", true)
    end
end

---Applies the fluid changes under 20 kg to the mass of a can
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

---Lets a player aim at the 5 and 25 liter formats to take them in hand
function RMS_FluidContainer:getCanBePickedUp(superFunc, byPlayer)
    return self:getRMSFluidCapacity() <= RMS_FluidContainer.CARRIED_CAPACITY and superFunc(self, byPlayer)
end

---Makes the delayed vehicle deletion idempotent
function RMS_FluidContainer:delete(superFunc, immediate)
    if self.isDeleted or self.isDeleting or (self.markedForDeletion and not immediate) then
        return
    end

    superFunc(self, immediate)
end

---Returns the active format collision meshes for native tension belts
function RMS_FluidContainer:getMeshNodes(superFunc)
    local capacity = self:getRMSFluidCapacity()
    if capacity <= 5 then
        return { self.i3dMappings.mediumCanCollision.nodeId }
    elseif capacity <= 25 then
        return { self.i3dMappings.largeCanCollision.nodeId }
    end
    return {
        self.i3dMappings.drumPalletCollision.nodeId,
        self.i3dMappings.drumCollision.nodeId
    }
end

---Keeps an empty container alive during an allocation
function RMS_FluidContainer:beginRMSFluidTransaction()
    local spec = self[RMS_FluidContainer.SPEC_TABLE_NAME]
    spec.transactionDepth = (spec.transactionDepth or 0) + 1
end

function RMS_FluidContainer:endRMSFluidTransaction(committed)
    local spec = self[RMS_FluidContainer.SPEC_TABLE_NAME]
    spec.transactionDepth = math.max((spec.transactionDepth or 0) - 1, 0)
    if spec.transactionDepth == 0 then
        local shouldCheck = spec.pendingDeleteCheck
        spec.pendingDeleteCheck = false
        if committed == true and shouldCheck then
            self:deleteRMSContainerIfEmpty()
        end
    end
end

---Sets the native fill level without exceeding the container capacity
local function setLiters(container, liters)
    local spec = container[RMS_FluidContainer.SPEC_TABLE_NAME]
    local target = math.clamp(liters, 0, container:getRMSFluidCapacity())
    return container:addFillUnitFillLevel(container:getOwnerFarmId(), 1, target - container:getRMSFluidLiters(), spec.fillTypeIndex, ToolType.UNDEFINED)
end

---Removes liters, an emptied container going away once its transaction ends
-- @param float liters liters asked for
-- @return float removed liters actually taken
function RMS_FluidContainer:removeRMSFluidLiters(liters)
    local spec = self[RMS_FluidContainer.SPEC_TABLE_NAME]
    local removed = -setLiters(self, self:getRMSFluidLiters() - math.max(liters, 0))

    if self:getRMSFluidLiters() <= RMS_Fluids.EPSILON then
        if spec.transactionDepth > 0 then
            spec.pendingDeleteCheck = true
        else
            self:deleteRMSContainerIfEmpty()
        end
    end
    return removed
end

---Puts back liters a rolled-back allocation took
-- @param float liters liters to put back
-- @return float restored liters actually put back
function RMS_FluidContainer:restoreRMSFluidLiters(liters)
    return setLiters(self, self:getRMSFluidLiters() + math.max(liters, 0))
end

---Gives a container back the liters and the pump it was stored with
-- @param float liters liters it held
-- @param boolean hasPump true when a pump sat on the drum
function RMS_FluidContainer:setRMSFluidStored(liters, hasPump)
    setLiters(self, liters)
    if hasPump then
        self:setRMSFluidPump(true)
    end
end

---Deletes an empty container, a drum once its pump is taken off
function RMS_FluidContainer:deleteRMSContainerIfEmpty()
    if not self.isServer or self.isDeleted or self.isDeleting or self.markedForDeletion
        or self:getRMSFluidLiters() > RMS_Fluids.EPSILON or self[RMS_FluidContainer.SPEC_TABLE_NAME].hasPump then
        return
    end

    self:delete()
end
