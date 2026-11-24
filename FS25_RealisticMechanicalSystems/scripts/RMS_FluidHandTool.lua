-- Copyright © 2026 Squallqt. All rights reserved.

---Hand tool of a fluid container: a carried can or the nozzle of a drum
RMS_FluidHandTool = {}

local specName = "spec_" .. g_currentModName .. ".rmsFluidHandTool"
local modDirectory = g_currentModDirectory

RMS_FluidHandTool.FILENAMES = {
    medium = "objects/fluids/shared/canisterHand5L.xml",
    large = "objects/fluids/shared/canisterHand20L.xml",
    adBlueCan = "objects/fluids/products/totalEnergiesAdBlue/canisterHand10L.xml",
    drum = "objects/drumPump/drumPumpNozzle.xml",
    tank = "objects/drumPump/drumPumpNozzle.xml"
}
RMS_FluidHandTool.TARGET_REFRESH_INTERVAL = 200
RMS_FluidHandTool.FOLLOW_INTERVAL = 500
RMS_FluidHandTool.CARRY_DISTANCE = 1.2
RMS_FluidHandTool.CARRY_MIN_DISTANCE = 0.3
RMS_FluidHandTool.CARRY_CLEARANCE = 0.35
RMS_FluidHandTool.CARRY_DROP = 0.15
RMS_FluidHandTool.CARRY_MASK = CollisionFlag.TERRAIN + CollisionFlag.STATIC_OBJECT + CollisionFlag.BUILDING + CollisionFlag.ROAD
    + CollisionFlag.VEHICLE + CollisionFlag.DYNAMIC_OBJECT
RMS_FluidHandTool.POUR_TILT = math.rad(80)
RMS_FluidHandTool.TILT_DURATION = 350
RMS_FluidHandTool.LEVEL_TOLERANCE = 0.01
RMS_FluidHandTool.STATUS_DURATION = 2500
RMS_FluidHandTool.LOGO_SLICE_PREFIX = "rms_Brand"
RMS_FluidHandTool.LOGO_SHEETS = {
    MOTOREX = "brands/hud_brand_motorex.xml",
    MOTUL = "brands/hud_brand_motul.xml",
    FUCHS = "brands/hud_brand_fuchs.xml",
    SKF = "brands/hud_brand_skf.xml",
    TOTALENERGIES = "brands/hud_brand_totalenergies.xml"
}
RMS_FluidHandTool.CONTAINER_TEXT_KEYS = {
    can = { label = "rms_fluid_container_label", empty = "rms_fluid_container_empty" },
    drum = { label = "rms_fluid_drum_label", empty = "rms_fluid_drum_empty" },
    tank = { label = "rms_fluid_tank_label", empty = "rms_fluid_tank_empty" }
}
RMS_FluidHandTool.LOGO_COLOR = { 1, 1, 1, 1 }
RMS_FluidHandTool.GAUGE_ZONE_ALPHA = 0.2
RMS_FluidHandTool.HOSE_WARNING_SHARE = 0.75
RMS_FluidHandTool.HOSE_WARNING_ID = "rmsDrumPumpHose"

RMS_FluidHandTool.setDowns = {}

source(modDirectory .. "events/RMS_FluidCanisterEvent.lua")

---Checks if all prerequisite specializations are loaded
-- @param table specializations specializations
-- @return boolean hasPrerequisite true if all prerequisite specializations are loaded
function RMS_FluidHandTool.prerequisitesPresent(specializations)
    return true
end

---Registers the functions of the hand tool
-- @param table handToolType hand tool type
function RMS_FluidHandTool.registerFunctions(handToolType)
    SpecializationUtil.registerFunction(handToolType, "setRMSFluidContainer", RMS_FluidHandTool.setRMSFluidContainer)
    SpecializationUtil.registerFunction(handToolType, "rmsFluidCarryCallback", RMS_FluidHandTool.rmsFluidCarryCallback)
end

---Registers the event listeners of the hand tool
-- @param table handToolType hand tool type
function RMS_FluidHandTool.registerEventListeners(handToolType)
    for _, name in ipairs({ "onLoad", "onDelete", "onUpdate", "onDraw", "onWriteStream", "onReadStream", "onHeldStart",
        "onHeldEnd", "onHandToolHolderChanged", "onCarryingPlayerEnteredVehicle", "onRegisterActionEvents" }) do
        SpecializationUtil.registerEventListener(handToolType, name, RMS_FluidHandTool)
    end
end

---Tells whether the local player carries the hand tool
-- @param table handTool fluid hand tool
-- @return boolean isCarried true when the local player carries it
local function getIsLocallyCarried(handTool)
    local player = handTool:getCarryingPlayer()
    return player ~= nil and player.isOwner
end

---Registers the brand logos and the gauge hatching, once per mission
function RMS_FluidHandTool.registerOverlays()
    local contextDisplay = g_currentMission.hud.contextActionDisplay
    if RMS_FluidHandTool.contextDisplay == contextDisplay then
        return
    end

    if RMS_FluidHandTool.contextDisplay ~= nil then
        RMS_FluidHandTool.gaugeZone:delete()
        for _, logo in pairs(RMS_FluidHandTool.logos) do
            logo:delete()
        end
    end
    RMS_FluidHandTool.contextDisplay = contextDisplay
    RMS_FluidHandTool.gaugeZone = g_overlayManager:createOverlay("rms_LevelGauge.pourZone", 0, 0, 0, 0)
    RMS_FluidHandTool.gaugeZone:setColor(1, 1, 1, RMS_FluidHandTool.GAUGE_ZONE_ALPHA)
    RMS_FluidHandTool.logos = {}
    for brand, sheet in pairs(RMS_FluidHandTool.LOGO_SHEETS) do
        local prefix = RMS_FluidHandTool.LOGO_SLICE_PREFIX .. brand
        g_overlayManager:addTextureConfigFile(modDirectory .. sheet, prefix)
        RMS_FluidHandTool.logos[brand] = g_overlayManager:createOverlay(prefix .. ".logo", 0, 0, 0, 0)
        contextDisplay.slicesIds[prefix] = prefix .. ".logo"
    end
end

---Sizes and colours the context icon, a brand logo kept in its own colours
-- @param table contextDisplay context action display of the HUD
-- @param function superFunc original function
-- @param string contextAction input action
-- @param string contextIconName slice of the icon
-- @param string text text of the context
-- @param integer priority priority of the context
-- @param string? actionText text of the action
local function setContext(contextDisplay, superFunc, contextAction, contextIconName, text, priority, actionText)
    superFunc(contextDisplay, contextAction, contextIconName, text, priority, actionText)

    local isLogo = string.startsWith(contextDisplay.lastSliceId, RMS_FluidHandTool.LOGO_SLICE_PREFIX)
    local color = isLogo and RMS_FluidHandTool.LOGO_COLOR or HUD.COLOR.ACTIVE
    contextDisplay.iconOverlay:setDimension(contextDisplay:scalePixelValuesToScreenVector(isLogo and 48 or 64, 48))
    contextDisplay.iconOverlay:setColor(color[1], color[2], color[3], color[4])
end
ContextActionDisplay.setContext = Utils.overwrittenFunction(ContextActionDisplay.setContext, setContext)

---Returns the can the hands hold or aim at, nil without one
-- @param table hands hands of the player
-- @return table? can fluid container
local function getHandsCan(hands)
    local node = hands:getHeldItem()
    if node == nil then
        local target = hands:getCarryingPlayer().targeter.closestTargetsByKey[HandToolHands]
        if target == nil or not hands:getCanPickUpNode(target.node) then
            return nil
        end
        node = target.node
    end

    local object = g_currentMission:getNodeObject(node)
    if object ~= nil and object[RMS_FluidContainer.SPEC_TABLE_NAME] ~= nil then
        return object
    end
    return nil
end

---Returns the drum with a pump the hands aim at, and its place
-- @param table hands hands of the player
-- @return table? drum fluid container
-- @return integer? index place of the drum
local function getHandsDrum(hands)
    local target = hands:getCarryingPlayer().targeter.closestTargetsByKey[HandToolHands]
    if target == nil or hands:getHeldItem() ~= nil then
        return nil
    end

    local object = g_currentMission:getNodeObject(target.node)
    local spec = object ~= nil and object[RMS_FluidContainer.SPEC_TABLE_NAME] or nil
    if spec == nil then
        return nil
    end
    local index = object:getRMSFluidSlotAt(target.x, target.y, target.z)
    local slot = spec.slots[index]
    if slot.hasPump and not slot.isNozzleOut and g_currentMission.accessHandler:canPlayerAccess(object) then
        return object, index
    end
    return nil
end

---Takes the can or the nozzle of the drum the hands aim at
-- @param table hands hands of the player
local function onTakeAction(hands)
    local container = getHandsCan(hands)
    if container ~= nil then
        RMS_FluidCanisterEvent.send(container)
        return
    end
    local drum, index = getHandsDrum(hands)
    if drum ~= nil then
        RMS_FluidCanisterEvent.send(drum, nil, index)
    end
end

---Takes the pump of the drum the hands aim at, else the game's pick up
-- @param table hands hands of the player
-- @param function superFunc original function
-- @param any ... arguments of the game's function
local function onPickUpAction(hands, superFunc, ...)
    local drum, index = getHandsDrum(hands)
    if drum ~= nil then
        RMS_DrumPumpEvent.send(drum, nil, index)
        return
    end
    superFunc(hands, ...)
end
HandToolHands.onPickUpAction = Utils.overwrittenFunction(HandToolHands.onPickUpAction, onPickUpAction)

---Registers the key taking a can or a nozzle
-- @param table hands hands of the player
local function onHandsRegisterActionEvents(hands)
    if hands:getIsActiveForInput(true) then
        local _, eventId = hands:addActionEvent(InputAction.RMS_TOGGLE_FLUID_CAN, hands, onTakeAction, true, false, false, false, nil)
        g_inputBinding:setActionEventTextPriority(eventId, GS_PRIO_VERY_HIGH)
        g_inputBinding:setActionEventText(eventId, g_i18n:getText("rms_fluid_hand_take"))
        RMS_FluidHandTool.takeEventId = eventId
    end
end
HandToolHands.onRegisterActionEvents = Utils.appendedFunction(HandToolHands.onRegisterActionEvents, onHandsRegisterActionEvents)

---Picks the can back up once carried, and offers the take and pump keys
-- @param table hands hands of the player
local function onHandsUpdate(hands)
    local player = hands:getCarryingPlayer()
    if player == nil or not player.isOwner or not hands:getIsHeld() then
        return
    end

    local carried = RMS_FluidHandTool.carryAsked
    if carried ~= nil and (carried.isDeleted or not carried[RMS_FluidContainer.SPEC_TABLE_NAME].isCarried) then
        RMS_FluidHandTool.carryAsked = nil
        if not carried.isDeleted then
            local x, y, z = player.targeter:getLastLookRay()
            local cx, cy, cz = getWorldTranslation(carried.rootNode)
            local distance = MathUtil.vector3Length(cx - x, cy - y, cz - z)
            if distance <= HandToolHands.PICKUP_DISTANCE then
                hands:pickUpTarget({ node = carried.rootNode, distance = distance })
            end
        end
    end

    local drum = getHandsDrum(hands)
    g_inputBinding:setActionEventActive(RMS_FluidHandTool.takeEventId, drum ~= nil or getHandsCan(hands) ~= nil)
    g_inputBinding:setActionEventText(RMS_FluidHandTool.takeEventId, g_i18n:getText(drum ~= nil and "rms_drum_pump_nozzle_take" or "rms_fluid_hand_take"))
    if drum ~= nil then
        local pickUpEventId = hands.spec_hands.pickUpActionEventId
        g_inputBinding:setActionEventActive(pickUpEventId, true)
        g_inputBinding:setActionEventText(pickUpEventId, g_i18n:getText("rms_drum_pump_take"))
    end
end
HandToolHands.onUpdate = Utils.appendedFunction(HandToolHands.onUpdate, onHandsUpdate)

---Returns the circuit of a machine a container tops up
-- @param table container fluid container
-- @param table vehicle machine
-- @return string? circuit circuit, nil when nothing is missing
-- @return boolean isCompatible true when the product suits it
function RMS_FluidHandTool.getPourCircuit(container, vehicle)
    local productKey = container:getRMSFluidProductKey()
    -- a tank product goes to its own tank only, never to a circuit
    for tank in pairs(RMS_Fluids.TANKS) do
        if RMS_Fluids.getIsProductCompatible(productKey, tank) then
            if RMS_Fluids.getMissingLiters(vehicle, tank) > RMS_Fluids.EPSILON then
                return tank, true
            end
            return nil, false
        end
    end
    local wrongCircuit = nil
    for _, circuit in ipairs(RMS_Fluids.getSumpCircuits(vehicle)) do
        if RMS_Fluids.getMissingLiters(vehicle, circuit) > RMS_Fluids.EPSILON then
            if RMS_Fluids.getIsProductCompatible(productKey, circuit) then
                return circuit, true
            end
            wrongCircuit = wrongCircuit or circuit
        end
    end
    return wrongCircuit, false
end

---Returns why the container cannot pour into the machine aimed at
-- @param table vehicle machine
-- @param string? circuit circuit poured into
-- @param table container fluid container
-- @return string? textKey l10n key, nil when it may pour
function RMS_FluidHandTool.getPourRefusal(vehicle, circuit, container)
    if circuit == nil then
        local product = RMS_Fluids.PRODUCTS[container:getRMSFluidProductKey()]
        if product.compatibleCircuits.adBlue and RMS_Fluids.getTankFillUnitIndex(vehicle, "adBlue") == nil then
            return "rms_fluid_error_no_adblue_tank"
        end
        return "rms_fluid_error_no_circuit"
    elseif container:getRMSFluidCapacity() > RMS_FluidContainer.CARRIED_CAPACITY
        and RMS_FluidTransfer.getDistanceToVehicle(vehicle, container.rootNode) > RMS_FluidTransfer.HOSE_LENGTH then
        return container:getRMSFluidFormat() == "tank" and "rms_drum_pump_tank_too_far" or "rms_drum_pump_machine_too_far"
    elseif vehicle:isUnderService() then
        return "rms_charger_error_service"
    elseif vehicle:getIsMotorStarted() then
        return "rms_fluid_error_motor_running"
    elseif math.abs(vehicle:getLastSpeed()) > RMS_FluidTransfer.STOPPED_SPEED then
        return "rms_fluid_error_vehicle_moving"
    end
    return nil
end

---Takes a can or the nozzle of a drum into the hand of a player, on the server
-- @param table player player
-- @param table container fluid container
-- @param integer index place of the can, or drum of a pallet whose nozzle is taken
function RMS_FluidHandTool.take(player, container, index)
    local slot = container[RMS_FluidContainer.SPEC_TABLE_NAME].slots[index]
    if slot.carrierTool ~= nil or slot.isBeingTaken
        or not g_currentMission.accessHandler:canPlayerAccess(container, player) or player:getIsHoldingHandTool() then
        return
    end
    if container:getRMSFluidCapacity() > RMS_FluidContainer.CARRIED_CAPACITY then
        if not slot.hasPump or container:getRMSFluidHoseSpan(player, index) > RMS_FluidTransfer.HOSE_LENGTH then
            return
        end
    else
        local x, y, z = getWorldTranslation(player.rootNode)
        local cx, cy, cz = getWorldTranslation(container.rootNode)
        if container.dynamicMountObject ~= nil or container.tensionMountObject ~= nil
            or MathUtil.vector3Length(x - cx, y - cy, z - cz) > RMS_FluidTransfer.MAX_DISTANCE then
            return
        end
    end

    -- Guard against repeated requests during asynchronous loading
    slot.isBeingTaken = true
    local loadingData = HandToolLoadingData.new()
    loadingData:setFilename(modDirectory .. RMS_FluidHandTool.FILENAMES[container:getRMSFluidFormat()])
    loadingData:setOwnerFarmId(player.farmId)
    loadingData:setIsSaved(false)
    loadingData:setIsRegistered(false)
    loadingData:load(RMS_FluidHandTool.onTaken, RMS_FluidHandTool, { player = player, container = container, index = index })
end

---Puts the loaded hand tool in the hand of the player
-- @param table _ callback target
-- @param table handTool hand tool loaded
-- @param integer loadingState HandToolLoadingState
-- @param table arguments player, container and index
function RMS_FluidHandTool.onTaken(_, handTool, loadingState, arguments)
    local player, container, index = arguments.player, arguments.container, arguments.index
    container[RMS_FluidContainer.SPEC_TABLE_NAME].slots[index].isBeingTaken = nil
    if loadingState ~= HandToolLoadingState.OK then
        return
    end
    if container.isDeleted or player.isDeleted or not player:getCanPickupHandTool(handTool) then
        handTool:delete()
        return
    end

    for _, carrier in ipairs(g_currentMission.playerSystem.players) do
        if carrier.hands ~= nil and carrier.hands:getHeldItem() == container.rootNode then
            carrier.hands:dropHeldItem()
        end
    end

    local spec = handTool[specName]
    spec.followX, spec.followY, spec.followZ = getWorldTranslation(player.rootNode)
    handTool:setRMSFluidContainer(container, index)
    -- Set the holder before the creation stream is sent
    handTool:setHolder(player, true)
    player:setCurrentHandTool(handTool, true)
    if spec.isNozzle then
        container:setRMSFluidNozzle(handTool, index)
    else
        container:setRMSFluidCarried(handTool)
    end
    handTool:register()
end

---Queues a carried can to be set down on the next frame of the server
-- @param table handTool fluid hand tool
-- @param table? pose world position and heading asked, nil for none
function RMS_FluidHandTool.queueSetDown(handTool, pose)
    if next(RMS_FluidHandTool.setDowns) == nil then
        g_currentMission:addUpdateable(RMS_FluidHandTool)
    end
    RMS_FluidHandTool.setDowns[handTool] = pose or false
end

---Sets the queued cans down, the container back in the world
function RMS_FluidHandTool.update()
    local setDowns = RMS_FluidHandTool.setDowns
    RMS_FluidHandTool.setDowns = {}
    g_currentMission:removeUpdateable(RMS_FluidHandTool)

    for handTool, pose in pairs(setDowns) do
        if not handTool.isDeleted then
            local spec = handTool[specName]
            local player = handTool:getCarryingPlayer()
            if pose and player ~= nil then
                local x, y, z = getWorldTranslation(player.rootNode)
                if MathUtil.vector3Length(pose[1] - x, pose[2] - y, pose[3] - z) <= RMS_FluidTransfer.MAX_DISTANCE then
                    spec.setDownPose = pose
                end
            end
            spec.isSetDown = true
            handTool:delete()
        end
    end
end

---Called on loading
-- @param table xmlFile file of the hand tool
-- @param string baseDirectory directory of the hand tool
function RMS_FluidHandTool:onLoad(xmlFile, baseDirectory)
    local spec = self[specName]
    if self.i3dMappings.visualLink ~= nil then
        spec.visualLink = I3DUtil.indexToObject(self.components, "visualLink", self.i3dMappings)
    end
    spec.followTimer = 0
    spec.targetTimer = 0
    spec.tilt = 0
    spec.isPouring = false
    spec.isPourKeyDown = false

    if self.isClient then
        RMS_FluidHandTool.registerOverlays()
        spec.samples = {}
    end
end

---Links the tool to its container, and to the drum of its nozzle
-- @param table container fluid container
-- @param integer index place of the can, or drum of the nozzle
function RMS_FluidHandTool:setRMSFluidContainer(container, index)
    local spec = self[specName]
    spec.container = container
    spec.index = index
    spec.isNozzle = container:getRMSFluidCapacity() > RMS_FluidContainer.CARRIED_CAPACITY
    spec.pourText = string.format(g_i18n:getText("rms_fluid_pour_action"), container:getRMSFluidKindText())
    spec.carryText = g_i18n:getText(spec.isNozzle and "rms_drum_pump_nozzle_return" or "rms_fluid_hand_carry")
    if not spec.isNozzle then
        container:applyRMSFluidVisuals(spec.visualLink, container:getRMSFluidCapacity())
    end

    if self.isClient then
        local product = RMS_Fluids.PRODUCTS[container:getRMSFluidProductKey()]
        spec.contextIcon = RMS_FluidHandTool.LOGO_SLICE_PREFIX .. product.brand
        g_inputBinding:setActionEventText(spec.pourEventId, spec.pourText)
        g_inputBinding:setActionEventText(spec.carryEventId, spec.carryText)

        local isWatery = product.compatibleCircuits.coolant or product.compatibleCircuits.adBlue
        local sampleName = spec.isNozzle and "drumPump" or (isWatery and "fluidPourCoolant" or "fluidPourOil")
        local soundsFile = loadXMLFile("rmsFluidHandToolSounds", modDirectory .. "sounds/rms_sounds.xml")
        spec.samples.pour = g_soundManager:loadSampleFromXML(soundsFile, "sounds", sampleName, modDirectory, self.components, 0,
            AudioGroup.VEHICLE, self.i3dMappings, self)
        delete(soundsFile)
    end
end

---Called on server side on join
-- @param integer streamId stream id
-- @param Connection connection connection
function RMS_FluidHandTool:onWriteStream(streamId, connection)
    NetworkUtil.writeNodeObject(streamId, self[specName].container)
    streamWriteUInt8(streamId, self[specName].index)
end

---Called on client side on join
-- @param integer streamId stream id
-- @param Connection connection connection
function RMS_FluidHandTool:onReadStream(streamId, connection)
    -- The container may arrive after its hand tool on join
    self[specName].containerId = NetworkUtil.readNodeObjectId(streamId)
    self[specName].containerIndex = streamReadUInt8(streamId)
    self:raiseActive()
end

---Stops the pour under way
-- @param table handTool fluid hand tool
local function stopPour(handTool)
    local spec = handTool[specName]
    if spec.pourVehicle ~= nil then
        spec.pourVehicle = nil
        RMS_FluidTransferRequestEvent.send(spec.container, nil, nil, false, true, spec.index)
    end
end

---Tells whether a node looked at is a tracked machine the farm may use
-- @param entityId node node
-- @return boolean isMachine true for such a machine
function RMS_FluidHandTool.getIsMachineNode(node)
    local vehicle = g_currentMission:getNodeObject(node)
    local vehicleSpec = vehicle ~= nil and vehicle.spec_RealisticMechanicalSystems or nil
    return vehicleSpec ~= nil and not vehicleSpec.isExcludedVehicle and g_currentMission.accessHandler:canPlayerAccess(vehicle)
end

---Finds the machine aimed at, its circuit and why it may not be poured into
-- @param table handTool fluid hand tool
-- @param table player player
local function updateTarget(handTool, player)
    local spec = handTool[specName]
    local node = player.targeter:getClosestTargetedNodeFromType(RMS_FluidHandTool)
    local vehicle = node ~= nil and g_currentMission:getNodeObject(node) or nil

    spec.target = vehicle
    spec.targetCircuit, spec.targetIsCompatible, spec.targetRefusal = nil, false, nil
    if vehicle ~= nil then
        spec.targetCircuit, spec.targetIsCompatible = RMS_FluidHandTool.getPourCircuit(spec.container, vehicle)
        spec.targetRefusal = RMS_FluidHandTool.getPourRefusal(vehicle, spec.targetCircuit, spec.container)
        if spec.targetRefusal == nil then
            spec.targetText = string.format(g_i18n:getText("rms_fluid_pour_action"),
                g_i18n:getText(RMS_Fluids.getCircuitTextKey(vehicle, spec.targetCircuit)))
        end
    end
    if spec.pourVehicle ~= nil and spec.pourVehicle ~= vehicle and not spec.isNozzle then
        stopPour(handTool)
    end
end

---Keeps the can short of what the player faces
-- @param entityId hitObjectId object hit, 0 for none
-- @param float x hit x (world)
-- @param float y hit y (world)
-- @param float z hit z (world)
-- @param float distance distance to the hit (m)
function RMS_FluidHandTool:rmsFluidCarryCallback(hitObjectId, x, y, z, distance)
    if hitObjectId ~= 0 then
        self[specName].carryDistance = math.max(distance - RMS_FluidHandTool.CARRY_CLEARANCE, RMS_FluidHandTool.CARRY_MIN_DISTANCE)
    end
end

---Called on update: follows the carrier, plays the pour, watches the hose, aims
-- @param float dt time since the last frame (ms)
function RMS_FluidHandTool:onUpdate(dt)
    local spec = self[specName]
    if spec.containerId ~= nil then
        local container = NetworkUtil.getObject(spec.containerId)
        if container == nil or not container:getIsSynchronized() then
            self:raiseActive()
            return
        end
        spec.containerId = nil
        self:setRMSFluidContainer(container, spec.containerIndex)
    end

    local container = spec.container
    if container == nil or container.isDeleted then
        return
    end

    local player = self:getCarryingPlayer()
    if self.isServer and player ~= nil and not spec.isNozzle then
        spec.followTimer = spec.followTimer - dt
        if spec.followTimer <= 0 then
            -- Keep the hidden container at its carrier for save and disconnect
            spec.followTimer = RMS_FluidHandTool.FOLLOW_INTERVAL
            spec.followX, spec.followY, spec.followZ = getWorldTranslation(player.rootNode)
            setWorldTranslation(container.rootNode, spec.followX, spec.followY, spec.followZ)
        end
    end

    if not self.isClient then
        return
    end

    local isPouring = container:getIsRMSFluidTransferActive(spec.index)
    if isPouring ~= spec.isPouring then
        spec.isPouring = isPouring
        RMS_SoundManager.setSamplePlaying(spec.samples.pour, isPouring)
        if getIsLocallyCarried(self) then
            if isPouring then
                RMS_FluidHandTool.showPour(container, spec.pourVehicle, spec.pourCircuit, spec.pourIsCompatible, spec.index)
            else
                RMS_FluidHandTool.endPour()
            end
        end
    end

    if spec.isNozzle and player ~= nil and player.isOwner and not spec.isSetDown then
        local length, span = RMS_FluidTransfer.HOSE_LENGTH, container:getRMSFluidHoseSpan(player, spec.index)
        if span > length then
            RMS_FluidHandTool.onCarryAction(self)
        elseif span > length * RMS_FluidHandTool.HOSE_WARNING_SHARE and not g_gui:getIsGuiVisible() then
            g_currentMission:showBlinkingWarning(string.format(g_i18n:getText("rms_drum_pump_hose_range"), length - span), 100,
                RMS_FluidHandTool.HOSE_WARNING_ID)
        end
    end

    local tilt = isPouring and not spec.isNozzle and 1 or 0
    if spec.tilt ~= tilt then
        local step = dt / RMS_FluidHandTool.TILT_DURATION
        spec.tilt = math.clamp(tilt, spec.tilt - step, spec.tilt + step)
        setRotation(self.graphicalNode, spec.tilt * RMS_FluidHandTool.POUR_TILT, 0, 0)
    end

    if player ~= nil and player.isOwner and self:getIsHeld() then
        spec.targetTimer = spec.targetTimer - dt
        if spec.targetTimer <= 0 then
            spec.targetTimer = RMS_FluidHandTool.TARGET_REFRESH_INTERVAL
            updateTarget(self, player)
        end
    end
end

---Offers the pour in the action line while the can may pour
function RMS_FluidHandTool:onDraw()
    local spec = self[specName]
    if spec.target ~= nil and spec.targetRefusal == nil and RMS_FluidHandTool.display == nil then
        g_currentMission.hud.contextActionDisplay:setContext(InputAction.ACTIVATE_HANDTOOL, spec.contextIcon,
            spec.target:getFullName(), HUD.CONTEXT_PRIORITY.HIGH, spec.targetText)
    end
end

---Registers the pour and carry keys
function RMS_FluidHandTool:onRegisterActionEvents()
    if not self:getIsActiveForInput(true) then
        return
    end

    local spec = self[specName]
    local _, pourEventId = self:addActionEvent(InputAction.ACTIVATE_HANDTOOL, self, RMS_FluidHandTool.onPourAction, true, true, true, true, nil)
    g_inputBinding:setActionEventTextPriority(pourEventId, GS_PRIO_VERY_HIGH)
    g_inputBinding:setActionEventText(pourEventId, spec.pourText)
    spec.pourEventId = pourEventId

    local _, carryEventId = self:addActionEvent(InputAction.RMS_TOGGLE_FLUID_CAN, self, RMS_FluidHandTool.onCarryAction, true, false, false, false, nil)
    g_inputBinding:setActionEventActive(carryEventId, true)
    g_inputBinding:setActionEventTextPriority(carryEventId, GS_PRIO_VERY_HIGH)
    g_inputBinding:setActionEventText(carryEventId, spec.carryText)
    spec.carryEventId = carryEventId
end

---Sets the can down short of what the player faces, to be carried in the hands
-- @param table handTool fluid hand tool
local function carry(handTool)
    local spec = handTool[specName]
    local x, y, z, dx, dy, dz = handTool:getCarryingPlayer().targeter:getLastLookRay()
    spec.carryDistance = RMS_FluidHandTool.CARRY_DISTANCE
    raycastClosest(x, y, z, dx, dy, dz, RMS_FluidHandTool.CARRY_DISTANCE + RMS_FluidHandTool.CARRY_CLEARANCE, "rmsFluidCarryCallback",
        handTool, RMS_FluidHandTool.CARRY_MASK)

    RMS_FluidHandTool.carryAsked = spec.container
    spec.isSetDown = true
    RMS_FluidCanisterEvent.send(handTool, { x + dx * spec.carryDistance, y + dy * spec.carryDistance - RMS_FluidHandTool.CARRY_DROP,
        z + dz * spec.carryDistance, MathUtil.getYRotationFromDirection(dx, dz) })
end

---Starts the pour into the machine aimed at, confirmed first when the fluid does not suit
-- @param table handTool fluid hand tool
local function startPour(handTool)
    local spec = handTool[specName]
    local target, circuit = spec.target, spec.targetCircuit
    if target == nil then
        return
    end
    if spec.targetRefusal ~= nil then
        local display = RMS_FluidHandTool.display
        if circuit ~= nil or display == nil or display.vehicle ~= target then
            g_currentMission:showBlinkingWarning(g_i18n:getText(spec.targetRefusal), 2000)
        end
        return
    end

    local isUnsuited = spec.targetIsCompatible
        and not RMS_Fluids.getIsProductSuited(target, spec.container:getRMSFluidProductKey(), circuit)
    if (not spec.targetIsCompatible or isUnsuited) and (spec.confirmedVehicle ~= target or spec.confirmedCircuit ~= circuit) then
        YesNoDialog.show(
            function(confirmed)
                if confirmed then
                    spec.confirmedVehicle, spec.confirmedCircuit = target, circuit
                end
            end,
            nil,
            g_i18n:getText(isUnsuited and "rms_fluid_unsuited_oil_message" or RMS_Fluids.getIncompatibleMessageKey(target, circuit)),
            g_i18n:getText(isUnsuited and "rms_fluid_unsuited_oil_title" or "rms_fluid_incompatible_title")
        )
        return
    end

    spec.pourVehicle = target
    spec.pourCircuit = circuit
    spec.pourIsCompatible = spec.targetIsCompatible
    RMS_FluidTransferRequestEvent.send(spec.container, target, circuit, not spec.targetIsCompatible, false, spec.index)
end

---Pours into the machine aimed at for as long as the key is held
-- @param string actionName input action
-- @param float inputValue input value
function RMS_FluidHandTool:onPourAction(actionName, inputValue)
    local spec = self[specName]
    local isDown = inputValue ~= 0
    -- Process only press and release edges of the held action
    if isDown == spec.isPourKeyDown or spec.container == nil then
        return
    end
    spec.isPourKeyDown = isDown

    if isDown then
        updateTarget(self, self:getCarryingPlayer())
        startPour(self)
    else
        stopPour(self)
    end
end

---Hands the can back at the release of the key, or hangs the nozzle up
function RMS_FluidHandTool:onCarryAction()
    local spec = self[specName]
    if spec.isNozzle then
        local x, y, z = getWorldTranslation(self:getCarryingPlayer().rootNode)
        spec.isSetDown = true
        RMS_FluidCanisterEvent.send(self, { x, y, z, 0 })
    elseif spec.container ~= nil then
        carry(self)
    end
end

---Lets the player aim at machines with the can
function RMS_FluidHandTool:onHeldStart()
    if getIsLocallyCarried(self) then
        local targeter = self:getCarryingPlayer().targeter
        targeter:addTargetType(RMS_FluidHandTool, CollisionFlag.VEHICLE, 0, RMS_FluidTransfer.MAX_DISTANCE)
        targeter:addFilterToTargetType(RMS_FluidHandTool, RMS_FluidHandTool.getIsMachineNode)
    end
end

---Sets the can down once it leaves the hand, never put away like a tool
function RMS_FluidHandTool:onHeldEnd()
    if getIsLocallyCarried(self) then
        local spec = self[specName]
        local player = self:getCarryingPlayer()
        local x, y, z = getWorldTranslation(player.rootNode)
        player.targeter:removeTargetType(RMS_FluidHandTool)
        spec.target = nil
        stopPour(self)
        if not spec.isSetDown then
            RMS_FluidCanisterEvent.send(self, { x, y + 0.3, z, 0 })
        end
    end
end

---Sets down the can of a player who left the game
-- @param table? holder new holder
-- @param table? lastHolder previous holder
function RMS_FluidHandTool:onHandToolHolderChanged(holder, lastHolder)
    if self.isServer and holder == nil and not self[specName].isSetDown then
        RMS_FluidHandTool.queueSetDown(self)
    end
end

---Sets down the can of a player who climbs into a machine
function RMS_FluidHandTool:onCarryingPlayerEnteredVehicle()
    if self.isServer then
        RMS_FluidHandTool.queueSetDown(self)
    end
end

---Puts the container back in the world, or hangs the nozzle up
function RMS_FluidHandTool:onDelete()
    local spec = self[specName]
    if self.isClient then
        g_soundManager:deleteSamples(spec.samples)
        local display = RMS_FluidHandTool.display
        if display ~= nil and display.container == spec.container then
            RMS_FluidHandTool.endPour()
        end
    end

    local container = spec.container
    if self.isServer and container ~= nil and not container.isDeleted
        and container[RMS_FluidContainer.SPEC_TABLE_NAME].slots[spec.index].carrierTool == self then
        if spec.isNozzle then
            container:setRMSFluidNozzle(nil, spec.index)
        else
            local pose = spec.setDownPose or { spec.followX, spec.followY + 0.3, spec.followZ, 0 }
            container:setRMSFluidCarried(nil, pose[1], pose[2], pose[3], pose[4])
        end
    end
end

---Shows the local player the pour that started
-- @param table container fluid container
-- @param table vehicle machine poured into
-- @param string circuit circuit poured into
-- @param boolean isCompatible true when the product suits it
-- @param integer index place poured from
function RMS_FluidHandTool.showPour(container, vehicle, circuit, isCompatible, index)
    if RMS_FluidHandTool.display == nil then
        g_currentMission:addDrawable(RMS_FluidHandTool)
    end

    local product = RMS_Fluids.PRODUCTS[container:getRMSFluidProductKey()]
    RMS_FluidHandTool.display = {
        container = container,
        index = index,
        vehicle = vehicle,
        circuit = circuit,
        isCompatible = isCompatible,
        isPouring = true,
        logo = RMS_FluidHandTool.logos[product.brand],
        circuitText = g_i18n:getText(RMS_Fluids.getCircuitTextKey(vehicle, circuit)),
        machineText = vehicle:getFullName(),
        productText = g_brandManager:getBrandByName(product.brand).title .. " " .. product.name,
        containerLiters = container:getRMSFluidLiters(index),
        containerCapacity = container:getRMSFluidCapacity(index),
        containerFormat = container:getRMSFluidFormat()
    }
    g_currentMission.hud.contextActionDisplay:resetContext()
end

---Leaves the pour that stopped on screen for a moment, with what ended it
function RMS_FluidHandTool.endPour()
    local display = RMS_FluidHandTool.display
    if display ~= nil and display.isPouring then
        display.isPouring = false
        display.endTime = g_time + RMS_FluidHandTool.STATUS_DURATION
    end
end

---Returns the text naming the container, or saying it is empty
-- @param table display pour shown
-- @param string kind "label" or "empty"
-- @return string textKey l10n key
function RMS_FluidHandTool.getContainerTextKey(display, kind)
    local keys = RMS_FluidHandTool.CONTAINER_TEXT_KEYS
    if display.containerFormat == "tank" then
        return keys.tank[kind]
    end
    return keys[display.containerCapacity > RMS_FluidContainer.CARRIED_CAPACITY and "drum" or "can"][kind]
end

---Shrinks a text size until the text holds in a width
-- @param string text text
-- @param float textSize text size
-- @param float width width to fit in (screen)
-- @return float textSize text size that fits
function RMS_FluidHandTool.fitTextSize(text, textSize, width)
    while getTextWidth(textSize, text) > width do
        textSize = textSize * 0.95
    end
    return textSize
end

---Returns a height of the pour panel in screen units
-- @param table hud HUD
-- @param float pixels height in pixels
-- @return float height height (screen)
local function scaledY(hud, pixels)
    return hud:scalePixelToScreenHeight(pixels)
end

---Returns the screen y of a row, some pixels above the foot of the pour panel
-- @param table hud HUD
-- @param float y foot of the panel
-- @param float pixels height of the row above the foot, in pixels
-- @return float y y of the row (screen)
local function rowY(hud, y, pixels)
    return y + hud:scalePixelToScreenHeight(pixels)
end

---Returns a height on whole screen pixels
-- @param float value height (screen)
-- @return float height height snapped to screen pixels
local function onPixels(value)
    return math.floor(value / g_pixelSizeY + 0.5) * g_pixelSizeY
end

---Draws the pour of the local player: circuit level and what the can holds
function RMS_FluidHandTool.draw()
    local display = RMS_FluidHandTool.display
    if display.vehicle.isDeleted or (not display.isPouring and g_time > display.endTime) then
        RMS_FluidHandTool.display = nil
        g_currentMission:removeDrawable(RMS_FluidHandTool)
        return
    end

    display.containerLiters = display.container.isDeleted and 0 or display.container:getRMSFluidLiters(display.index)
    if not g_currentMission.hud.isVisible then
        return
    end

    local hud = RMS_Main.hud
    local liters = RMS_Fluids.getLiters(display.vehicle, display.circuit)
    local capacity = RMS_Fluids.getCapacity(display.vehicle, display.circuit)
    local isLevelDone = not display.isPouring and capacity - liters <= RMS_FluidHandTool.LEVEL_TOLERANCE
    local isEmptied = not display.isPouring and not isLevelDone and display.containerLiters <= RMS_FluidHandTool.LEVEL_TOLERANCE
    local isTank = RMS_Fluids.TANKS[display.circuit] ~= nil
    local fill, fillColor = RMS_Fluids.getLevel(display.vehicle, display.circuit), HUD.COLOR.ACTIVE
    if not isTank then
        fill, fillColor = RMS_Fluids.getGaugeFill(fill, HUD.COLOR.ACTIVE)
    end
    local active, warning = HUD.COLOR.ACTIVE, RMS_Breakdowns.COLORS.WARNING
    local unit = g_i18n:getText("unit_literShort")

    local width, height = hud:scalePixelToScreenWidth(560), hud:scalePixelToScreenHeight(142)
    local padding = hud:scalePixelToScreenWidth(20)
    local x, y = 0.5 - width * 0.5, g_hudAnchorBottom
    local right = x + width - padding

    local background = HUD.COLOR.BACKGROUND_DARK
    drawFilledRectRound(x, y, width, height, 0.25, background[1], background[2], background[3], background[4])
    display.logo:setDimension(hud:scalePixelToScreenWidth(44), scaledY(hud, 44))
    display.logo:setPosition(x + padding, rowY(hud, y, 82))
    display.logo:render()

    local litersText = RMS_FluidWorkshop.formatLiters(liters)
    local capacityText = string.format(" / %s %s", RMS_FluidWorkshop.formatLiters(capacity), unit)
    local statusKey, statusColor = nil, active
    if not display.isCompatible then
        statusKey, statusColor = "rms_fluid_incompatible_title", warning
    elseif isLevelDone then
        statusKey = "rms_fluid_level_done"
    elseif isEmptied then
        statusKey, statusColor = RMS_FluidHandTool.getContainerTextKey(display, "empty"), warning
    elseif fill <= 0 and not isTank then
        statusKey, statusColor = "rms_fluid_level_under_gauge", fillColor
    end

    setTextVerticalAlignment(RenderText.VERTICAL_ALIGN_MIDDLE)
    setTextAlignment(RenderText.ALIGN_RIGHT)
    setTextBold(false)
    setTextColor(1, 1, 1, 0.6)
    local capacityWidth = getTextWidth(scaledY(hud, 16), capacityText)
    renderText(right, rowY(hud, y, 111), scaledY(hud, 16), capacityText)
    setTextBold(true)
    if isLevelDone and display.isCompatible then
        setTextColor(active[1], active[2], active[3], 1)
    else
        setTextColor(1, 1, 1, 1)
    end
    local litersWidth = getTextWidth(scaledY(hud, 26), litersText)
    renderText(right - capacityWidth, rowY(hud, y, 113), scaledY(hud, 26), litersText)
    local statusWidth = 0
    if statusKey ~= nil then
        local statusText = utf8ToUpper(g_i18n:getText(statusKey))
        statusWidth = getTextWidth(scaledY(hud, 13), statusText)
        setTextColor(statusColor[1], statusColor[2], statusColor[3], 1)
        renderText(right, rowY(hud, y, 90), scaledY(hud, 13), statusText)
    end

    local textX, gap = x + padding + hud:scalePixelToScreenWidth(58), hud:scalePixelToScreenWidth(12)
    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextColor(1, 1, 1, 1)
    renderText(textX, rowY(hud, y, 115), RMS_FluidHandTool.fitTextSize(display.circuitText, scaledY(hud, 20),
        right - capacityWidth - litersWidth - gap - textX), display.circuitText)
    setTextBold(false)
    setTextColor(1, 1, 1, 0.6)
    renderText(textX, rowY(hud, y, 92), RMS_FluidHandTool.fitTextSize(display.machineText, scaledY(hud, 14), right - statusWidth - gap - textX),
        display.machineText)
    renderText(x + padding, rowY(hud, y, 16), scaledY(hud, 13), display.productText)

    local trackX, trackWidth = x + padding, width - padding * 2
    local minX = trackX + trackWidth * RMS_Fluids.GAUGE_MIN_POSITION
    local maxX = trackX + trackWidth * RMS_Fluids.GAUGE_MAX_POSITION
    local markWidth = hud:scalePixelToScreenWidth(2)
    local barY, barHeight = onPixels(rowY(hud, y, 58)), onPixels(scaledY(hud, 10))
    drawFilledRect(trackX, barY, trackWidth, barHeight, 1, 1, 1, 0.12)
    if fill > 0 then
        drawFilledRect(trackX, barY, trackWidth * fill, barHeight, fillColor[1], fillColor[2], fillColor[3], 1)
    else
        drawFilledRect(trackX, barY, hud:scalePixelToScreenWidth(6), barHeight, fillColor[1], fillColor[2], fillColor[3], 1)
    end
    if not isTank then
        local zone = RMS_FluidHandTool.gaugeZone
        zone:setDimension(maxX - minX, barHeight)
        zone:setPosition(minX, barY)
        zone:render()
        drawFilledRect(minX - markWidth * 0.5, rowY(hud, y, 54), markWidth, scaledY(hud, 18), 1, 1, 1, 1)
        drawFilledRect(maxX - markWidth * 0.5, rowY(hud, y, 54), markWidth, scaledY(hud, 18), 1, 1, 1, 1)
    end
    drawFilledRect(trackX, rowY(hud, y, 30), trackWidth, scaledY(hud, 1), 1, 1, 1, 0.16)

    if not isTank then
        setTextBold(true)
        setTextAlignment(RenderText.ALIGN_CENTER)
        setTextColor(1, 1, 1, 0.6)
        renderText(minX, rowY(hud, y, 46), scaledY(hud, 11), "MIN")
        renderText(maxX, rowY(hud, y, 46), scaledY(hud, 11), "MAX")
    end

    local canText = string.format(" / %s %s", RMS_FluidWorkshop.formatLiters(display.containerCapacity), unit)
    local canLitersText = RMS_FluidWorkshop.formatLiters(display.containerLiters)
    setTextAlignment(RenderText.ALIGN_RIGHT)
    setTextColor(1, 1, 1, 1)
    local canLitersWidth = getTextWidth(scaledY(hud, 13), canLitersText)
    setTextBold(false)
    local canWidth = getTextWidth(scaledY(hud, 13), canText)
    setTextColor(1, 1, 1, 0.6)
    renderText(right, rowY(hud, y, 16), scaledY(hud, 13), canText)
    renderText(right - canWidth - canLitersWidth - hud:scalePixelToScreenWidth(8), rowY(hud, y, 16), scaledY(hud, 13),
        g_i18n:getText(RMS_FluidHandTool.getContainerTextKey(display, "label")))
    setTextBold(true)
    setTextColor(1, 1, 1, 1)
    renderText(right - canWidth, rowY(hud, y, 16), scaledY(hud, 13), canLitersText)

    setTextBold(false)
    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextVerticalAlignment(RenderText.VERTICAL_ALIGN_BASELINE)
end
