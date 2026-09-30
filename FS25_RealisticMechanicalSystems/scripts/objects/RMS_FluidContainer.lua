-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---Physical RMS fluid container holding its own liters, so the game's 255 fill type limit never empties it
RMS_FluidContainer = {}
RMS_FluidContainer.SPEC_NAME = "FS25_RealisticMechanicalSystems.rmsFluidContainer"
RMS_FluidContainer.SPEC_TABLE_NAME = "spec_" .. RMS_FluidContainer.SPEC_NAME
RMS_FluidContainer.DRUM_I3D_FILENAME = "data/maps/textures/shared/props/motorex/motorexOilBarrel.i3d"

---Requires the native FillUnit specialization, whose configuration picks the 5, 25 or 200 liter format
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

    Vehicle.xmlSchemaSavegame:register(XMLValueType.FLOAT,
        "vehicles.vehicle(?)." .. RMS_FluidContainer.SPEC_NAME .. "#liters", "Liters left in the container")
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
end

---Registers native container behavior overrides
function RMS_FluidContainer.registerOverwrittenFunctions(vehicleType)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "delete", RMS_FluidContainer.delete)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "getCanBePickedUp", RMS_FluidContainer.getCanBePickedUp)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "getMeshNodes", RMS_FluidContainer.getMeshNodes)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "getFillLevelInformation", RMS_FluidContainer.getFillLevelInformation)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "showInfo", RMS_FluidContainer.showInfo)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "getAdditionalComponentMass", RMS_FluidContainer.getAdditionalComponentMass)
end

---Registers load, save and network callbacks
function RMS_FluidContainer.registerEventListeners(vehicleType)
    SpecializationUtil.registerEventListener(vehicleType, "onLoad", RMS_FluidContainer)
    SpecializationUtil.registerEventListener(vehicleType, "onLoadEnd", RMS_FluidContainer)
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

---Loads the immutable catalogue product and the liters left, a new container starting full
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
    spec.clientTransferTarget = nil
    spec.clientTransferCircuit = nil

    local product = RMS_Fluids.PRODUCTS[spec.productKey]
    if product == nil then
        Logging.xmlError(self.xmlFile, "Unknown RMS fluid product key '%s'", tostring(spec.productKey))
        return
    end

    spec.capacity = product.capacities[Utils.getNoNil(self.configurations["fillUnit"], 1)]
    spec.liters = spec.capacity
    if savegame ~= nil and not savegame.resetVehicles then
        spec.liters = math.clamp(savegame.xmlFile:getValue(savegame.key .. "." .. RMS_FluidContainer.SPEC_NAME .. "#liters", 0), 0, spec.capacity)
    end
    spec.dirtyFlag = self:getNextDirtyFlag()
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

    RMS_FluidContainer.applyDiffuseByName(
        mediumRoots,
        "body",
        Utils.getFilename(self.xmlFile:getValue(baseKey .. "#mediumBodyDiffuse"), self.baseDirectory)
    )
    RMS_FluidContainer.applyDiffuseByName(
        mediumRoots,
        "cap",
        Utils.getFilename(self.xmlFile:getValue(baseKey .. "#mediumCapDiffuse"), self.baseDirectory)
    )
    RMS_FluidContainer.applyDiffuseByName(
        mediumRoots,
        "label",
        Utils.getFilename(self.xmlFile:getValue(baseKey .. "#mediumLabelDiffuse"), self.baseDirectory)
    )
    RMS_FluidContainer.applyDiffuseByName(
        largeRoots,
        "body60",
        Utils.getFilename(self.xmlFile:getValue(baseKey .. "#largeBodyDiffuse"), self.baseDirectory)
    )
    RMS_FluidContainer.applyDiffuseByName(
        largeRoots,
        "label60",
        Utils.getFilename(self.xmlFile:getValue(baseKey .. "#largeLabelDiffuse"), self.baseDirectory)
    )
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

    if self.isClient and g_currentMission ~= nil and g_currentMission.activatableObjectsSystem ~= nil then
        spec.activatable = RMS_FluidContainerActivatable.new(self)
        g_currentMission.activatableObjectsSystem:addActivatable(spec.activatable)
    end
end

---Temporary cleanup for empty containers persisted before 1.0; remove this onLoadEnd hook for the 1.0 release
function RMS_FluidContainer:onLoadEnd()
    if self.isServer and self.propertyState ~= VehiclePropertyState.SHOP_CONFIG then
        self:deleteRMSContainerIfEmpty()
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
    if filename == nil or not fileExists(filename) then
        Logging.error("RMS: missing fluid product texture '%s'", tostring(filename))
        return
    end
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

---Drops collisions carried by referenced visuals while preserving the RMS collision root
function RMS_FluidContainer.stripChildCollision(node)
    for index = 0, getNumOfChildren(node) - 1 do
        RMS_FluidContainer.stripCollision(getChildAt(node, index))
    end
end

---Cancels any in-progress transfer before the container is deleted
function RMS_FluidContainer:onDelete()
    local spec = self[RMS_FluidContainer.SPEC_TABLE_NAME]
    if spec.activatable ~= nil and g_currentMission ~= nil and g_currentMission.activatableObjectsSystem ~= nil then
        g_currentMission.activatableObjectsSystem:removeActivatable(spec.activatable)
        spec.activatable = nil
    end
    if RMS_FluidTransfer ~= nil then
        RMS_FluidTransfer.cancel(self)
    end
end

---Advances the active transfer only on the authoritative server
function RMS_FluidContainer:onUpdate(dt, isActiveForInput, isActiveForInputIgnoreSelection, isSelected)
    local spec = self[RMS_FluidContainer.SPEC_TABLE_NAME]

    if self.isServer and RMS_FluidTransfer ~= nil and spec.activeTransfer ~= nil then
        RMS_FluidTransfer.update(self, dt)
    end

    local target = self.isClient and spec.clientTransferTarget or nil
    if target ~= nil then
        local circuit = spec.clientTransferCircuit
        if target.isDeleted == true
            or self:getRMSFluidLiters() <= RMS_Fluids.EPSILON
            or RMS_Fluids.getMissingLiters(target, circuit) <= RMS_Fluids.EPSILON
            or (target.getIsMotorStarted ~= nil and target:getIsMotorStarted()) then
            spec.clientTransferTarget = nil
            spec.clientTransferCircuit = nil
        end
    end
end

---Saves the liters left and cancels transient transfer state
function RMS_FluidContainer:saveToXMLFile(xmlFile, key, usedModNames)
    if self.isServer and RMS_FluidTransfer ~= nil then
        RMS_FluidTransfer.cancel(self)
    end
    xmlFile:setValue(key .. "#liters", self[RMS_FluidContainer.SPEC_TABLE_NAME].liters)
end

---Sends the liters to a joining client
function RMS_FluidContainer:onWriteStream(streamId, connection)
    streamWriteFloat32(streamId, self[RMS_FluidContainer.SPEC_TABLE_NAME].liters)
end

---Receives the liters on joining
function RMS_FluidContainer:onReadStream(streamId, connection)
    self[RMS_FluidContainer.SPEC_TABLE_NAME].liters = streamReadFloat32(streamId)
    self:setMassDirty()
end

---Sends the changed liters to the clients
function RMS_FluidContainer:onWriteUpdateStream(streamId, connection, dirtyMask)
    if not connection:getIsServer() then
        local spec = self[RMS_FluidContainer.SPEC_TABLE_NAME]
        if streamWriteBool(streamId, bit32.band(dirtyMask, spec.dirtyFlag) ~= 0) then
            streamWriteFloat32(streamId, spec.liters)
        end
    end
end

---Receives the changed liters from the server
function RMS_FluidContainer:onReadUpdateStream(streamId, timestamp, connection)
    if connection:getIsServer() and streamReadBool(streamId) then
        self[RMS_FluidContainer.SPEC_TABLE_NAME].liters = streamReadFloat32(streamId)
        self:setMassDirty()
    end
end

---Returns the immutable catalogue product key
function RMS_FluidContainer:getRMSFluidProductKey()
    return self[RMS_FluidContainer.SPEC_TABLE_NAME].productKey
end

---Returns the liters left
function RMS_FluidContainer:getRMSFluidLiters()
    return self[RMS_FluidContainer.SPEC_TABLE_NAME].liters
end

---Returns the capacity of the container format
function RMS_FluidContainer:getRMSFluidCapacity()
    return self[RMS_FluidContainer.SPEC_TABLE_NAME].capacity
end

---Returns the remaining percentage
function RMS_FluidContainer:getRMSFluidPercentage()
    local capacity = self:getRMSFluidCapacity()
    return capacity > 0 and math.clamp(self:getRMSFluidLiters() / capacity, 0, 1) or 0
end

-- short name of each kind of fluid, the one the player needs to tell containers apart
local FLUID_KIND_TEXT_KEYS = {
    engineOil = "rms_fluid_hud_engineOil",
    transmissionHydraulic = "rms_fluid_hud_transmissionHydraulic",
    coolant = "rms_fluid_hud_coolant"
}

-- fluid kinds each fill level display took per line in its current pass, weak so a deleted display goes
local displayPasses = setmetatable({}, { __mode = "k" })

---Returns the kind of fluid a product is
local function getFluidKind(product)
    if product.compatibleCircuits.engineOil then
        return "engineOil"
    elseif product.compatibleCircuits.coolant then
        return "coolant"
    end
    return "transmissionHydraulic"
end

---Shows the container in the fill level display under its brand logo and its kind of fluid; when the game's
-- 255 fill type limit refused the brand types, the line keeps the kind without logo nor unit
function RMS_FluidContainer:getFillLevelInformation(superFunc, display)
    superFunc(self, display)
    local spec = self[RMS_FluidContainer.SPEC_TABLE_NAME]
    local product = RMS_Fluids.PRODUCTS[spec.productKey]
    local kind = getFluidKind(product)
    local lineFillType = g_fillTypeManager:getFillTypeIndexByName("RMS_HUD_" .. product.brand) or FillType.UNKNOWN

    -- the game merges lines sharing a fill type, so a second kind of fluid on one line gets its product named
    local pass = displayPasses[display]
    if pass == nil or pass.time ~= g_time then
        pass = { time = g_time, lineKinds = {} }
        displayPasses[display] = pass
    end
    local lineKind = pass.lineKinds[lineFillType]
    if lineKind == nil then
        pass.lineKinds[lineFillType] = kind
    end
    local infoText = (lineKind ~= nil and lineKind ~= kind) and product.name or nil

    display:addFillLevel(lineFillType, spec.liters, spec.capacity, 0, false, nil,
        g_i18n:getText(FLUID_KIND_TEXT_KEYS[kind]), infoText)
end

---Shows the kind of fluid, its liters, then the brand and product when the player looks at the container
function RMS_FluidContainer:showInfo(superFunc, box)
    superFunc(self, box)
    local spec = self[RMS_FluidContainer.SPEC_TABLE_NAME]
    local product = RMS_Fluids.PRODUCTS[spec.productKey]
    box:addLine(g_i18n:getText(FLUID_KIND_TEXT_KEYS[getFluidKind(product)]), string.format("%s / %s %s", RMS_FluidWorkshop.formatLiters(spec.liters),
        RMS_FluidWorkshop.formatLiters(spec.capacity), g_i18n:getText("unit_literShort")))
    box:addLine(g_brandManager:getBrandByName(product.brand).title, product.name)
end

---Adds the weight of the fluid to the container body
function RMS_FluidContainer:getAdditionalComponentMass(superFunc, component)
    local additionalMass = superFunc(self, component)
    if component.node == self.components[1].node then
        local spec = self[RMS_FluidContainer.SPEC_TABLE_NAME]
        additionalMass = additionalMass + spec.liters * RMS_Fluids.PRODUCTS[spec.productKey].densityKgPerLiter * 0.001
    end
    return additionalMass
end

---Allows native hand pickup for the 5 and 25 liter formats
function RMS_FluidContainer:getCanBePickedUp(superFunc, byPlayer)
    return self:getRMSFluidCapacity() <= 25 and superFunc(self, byPlayer)
end

---Makes delayed vehicle deletion idempotent while preserving the final immediate delete
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

---Prevents an empty container from disappearing in the middle of an atomic allocation
function RMS_FluidContainer:beginRMSFluidTransaction()
    local spec = self[RMS_FluidContainer.SPEC_TABLE_NAME]
    spec.transactionDepth = (spec.transactionDepth or 0) + 1
end

---Finishes an allocation and performs the deferred deletion check when committed
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

---Sets the liters on the server, the weight following them and the clients told
local function setLiters(container, liters)
    local spec = container[RMS_FluidContainer.SPEC_TABLE_NAME]
    spec.liters = math.clamp(liters, 0, spec.capacity)
    container:raiseDirtyFlags(spec.dirtyFlag)
    container:setMassDirty()
end

---Removes liters, an emptied container going away once its transaction ends
-- @param float liters liters asked for
-- @return float removed liters actually taken
function RMS_FluidContainer:removeRMSFluidLiters(liters)
    local spec = self[RMS_FluidContainer.SPEC_TABLE_NAME]
    local removed = math.min(math.max(liters, 0), spec.liters)
    setLiters(self, spec.liters - removed)

    if spec.liters <= RMS_Fluids.EPSILON then
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
    local spec = self[RMS_FluidContainer.SPEC_TABLE_NAME]
    local before = spec.liters
    setLiters(self, spec.liters + math.max(liters, 0))
    return spec.liters - before
end

---Deletes an empty container
function RMS_FluidContainer:deleteRMSContainerIfEmpty()
    if not self.isServer or self.isDeleted or self.isDeleting or self.markedForDeletion
        or self:getRMSFluidLiters() > RMS_Fluids.EPSILON then
        return
    end

    self:delete()
end

RMS_FluidContainerActivatable = {}
local RMS_FluidContainerActivatable_mt = Class(RMS_FluidContainerActivatable)

function RMS_FluidContainerActivatable.new(container)
    local self = setmetatable({}, RMS_FluidContainerActivatable_mt)
    self.container = container
    self.activateText = g_i18n:getText("rms_fluid_container_action_start")
    return self
end

local function getObjectDistance(objectA, objectB)
    if objectA == nil or objectB == nil or objectA.rootNode == nil or objectB.rootNode == nil then
        return math.huge
    end
    local ax, ay, az = getWorldTranslation(objectA.rootNode)
    local bx, by, bz = getWorldTranslation(objectB.rootNode)
    return MathUtil.vector3Length(ax - bx, ay - by, az - bz)
end

function RMS_FluidContainerActivatable:getNearbyVehicles()
    local vehicles = {}
    local farmId = g_currentMission:getFarmId()
    for _, vehicle in pairs(g_currentMission.vehicleSystem.vehicles) do
        if vehicle ~= self.container and vehicle.spec_RealisticMechanicalSystems ~= nil
            and vehicle.getOwnerFarmId ~= nil and vehicle:getOwnerFarmId() == farmId
            and getObjectDistance(self.container, vehicle) <= RMS_FluidTransfer.MAX_DISTANCE then
            for _, circuit in ipairs(RMS_Fluids.CIRCUIT_ORDER) do
                if RMS_Fluids.getCapacity(vehicle, circuit) > RMS_Fluids.EPSILON
                    and RMS_Fluids.getMissingLiters(vehicle, circuit) > RMS_Fluids.EPSILON then
                    table.insert(vehicles, vehicle)
                    break
                end
            end
        end
    end
    table.sort(vehicles, function(a, b)
        return tostring(a.configFileName or "") < tostring(b.configFileName or "")
    end)
    return vehicles
end

function RMS_FluidContainerActivatable:getIsActivatable()
    local container = self.container
    if container == nil or container.isDeleted == true or container.isDeleting == true
        or container.markedForDeletion == true or container:getRMSFluidLiters() <= RMS_Fluids.EPSILON
        or g_currentMission == nil or g_localPlayer == nil or g_localPlayer:getIsInVehicle() then
        return false
    end

    local containerNode = container.rootNode
    local playerNode = g_localPlayer.rootNode
    if container.isAddedToPhysics ~= true
        or containerNode == nil or containerNode == 0 or not entityExists(containerNode)
        or playerNode == nil or playerNode == 0 or not entityExists(playerNode)
        or g_currentMission:getNodeObject(containerNode) ~= container then
        return false
    end

    local playerX, playerY, playerZ = getWorldTranslation(playerNode)
    if self:getDistance(playerX, playerY, playerZ) > RMS_FluidTransfer.MAX_DISTANCE then
        return false
    end

    local farmId = g_currentMission:getFarmId()
    if farmId == FarmManager.SPECTATOR_FARM_ID or container.getOwnerFarmId == nil
        or container:getOwnerFarmId() ~= farmId then
        return false
    end
    return true
end

function RMS_FluidContainerActivatable:updateActivateText()
    local spec = self.container[RMS_FluidContainer.SPEC_TABLE_NAME]
    self.activateText = g_i18n:getText(
        spec.clientTransferTarget ~= nil
            and "rms_fluid_container_action_cancel"
            or "rms_fluid_container_action_start"
    )
end

function RMS_FluidContainerActivatable:getDistance(x, y, z)
    local tx, ty, tz = getWorldTranslation(self.container.rootNode)
    return MathUtil.vector3Length(tx - x, ty - y, tz - z)
end

function RMS_FluidContainerActivatable:startTransfer(target, circuit, incompatibleConfirmed)
    RMS_FluidTransferRequestEvent.send(self.container, target, circuit, incompatibleConfirmed, false)
    local spec = self.container[RMS_FluidContainer.SPEC_TABLE_NAME]
    spec.clientTransferTarget = target
    spec.clientTransferCircuit = circuit
end

function RMS_FluidContainerActivatable:selectCircuit(target)
    if target.getIsMotorStarted ~= nil and target:getIsMotorStarted() then
        InfoDialog.show(g_i18n:getText("rms_fluid_error_motor_running"))
        return
    end
    if target.getLastSpeed ~= nil and math.abs(tonumber(target:getLastSpeed()) or 0) > RMS_FluidTransfer.STOPPED_SPEED then
        InfoDialog.show(g_i18n:getText("rms_fluid_error_vehicle_moving"))
        return
    end

    local circuits = {}
    local options = {}
    for _, circuit in ipairs(RMS_Fluids.getSumpCircuits(target)) do
        if RMS_Fluids.getCapacity(target, circuit) > RMS_Fluids.EPSILON
            and RMS_Fluids.getMissingLiters(target, circuit) > RMS_Fluids.EPSILON then
            table.insert(circuits, circuit)
            table.insert(options, g_i18n:getText(RMS_Fluids.getCircuitTextKey(target, circuit, "rms_fluid_circuit_" .. circuit)))
        end
    end
    if #circuits == 0 then
        InfoDialog.show(g_i18n:getText("rms_fluid_error_no_circuit"))
        return
    end

    local function choose(index)
        local circuit = index ~= nil and circuits[index] or nil
        if circuit == nil then
            return
        end
        local productKey = self.container:getRMSFluidProductKey()
        if RMS_Fluids.getIsProductCompatible(productKey, circuit) then
            self:startTransfer(target, circuit, false)
        else
            local callback = function(confirmed)
                if confirmed then
                    self:startTransfer(target, circuit, true)
                end
            end
            YesNoDialog.show(
                callback,
                nil,
                g_i18n:getText("rms_fluid_incompatible_message"),
                g_i18n:getText("rms_fluid_incompatible_title")
            )
        end
    end

    if #circuits == 1 then
        choose(1)
    else
        OptionDialog.show(
            choose,
            g_i18n:getText("rms_fluid_select_circuit_title"),
            g_i18n:getText("rms_fluid_select_circuit_prompt"),
            options
        )
    end
end

function RMS_FluidContainerActivatable:run()
    local spec = self.container[RMS_FluidContainer.SPEC_TABLE_NAME]
    if spec.clientTransferTarget ~= nil then
        RMS_FluidTransferRequestEvent.send(
            self.container,
            spec.clientTransferTarget,
            spec.clientTransferCircuit,
            false,
            true
        )
        spec.clientTransferTarget = nil
        spec.clientTransferCircuit = nil
        return
    end

    local vehicles = self:getNearbyVehicles()
    if #vehicles == 0 then
        InfoDialog.show(g_i18n:getText("rms_fluid_error_no_vehicle"))
        return
    end

    local function choose(index)
        local target = index ~= nil and vehicles[index] or nil
        if target ~= nil then
            self:selectCircuit(target)
        end
    end

    if #vehicles == 1 then
        choose(1)
    else
        local options = {}
        for _, vehicle in ipairs(vehicles) do
            table.insert(options, vehicle.getFullName ~= nil and vehicle:getFullName() or tostring(vehicle.configFileName))
        end
        OptionDialog.show(
            choose,
            g_i18n:getText("rms_fluid_select_vehicle_title"),
            g_i18n:getText("rms_fluid_select_vehicle_prompt"),
            options
        )
    end
end
