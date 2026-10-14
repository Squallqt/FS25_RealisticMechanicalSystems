-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---Battery drum pump carried in hand, set on the bung of a drum
RMS_DrumPump = {}

local specName = "spec_" .. g_currentModName .. ".rmsDrumPump"
local modDirectory = g_currentModDirectory

RMS_DrumPump.FILENAME = "objects/drumPump/drumPump.xml"
RMS_DrumPump.TARGET_REFRESH_INTERVAL = 200

-- pumps set on a drum, taken out of the hand once the game has left the callback
RMS_DrumPump.mounted = {}

source(modDirectory .. "events/RMS_DrumPumpEvent.lua")

---
function RMS_DrumPump.prerequisitesPresent(specializations)
    return true
end

---
function RMS_DrumPump.registerEventListeners(handToolType)
    for _, name in ipairs({ "onLoad", "onUpdate", "onDraw", "onHeldStart", "onHeldEnd", "onRegisterActionEvents" }) do
        SpecializationUtil.registerEventListener(handToolType, name, RMS_DrumPump)
    end
end

---Tells whether a player stands within reach of a container
local function getIsInReach(player, container)
    local x, y, z = getWorldTranslation(player.rootNode)
    local cx, cy, cz = getWorldTranslation(container.rootNode)
    return MathUtil.vector3Length(x - cx, y - cy, z - cz) <= RMS_FluidTransfer.MAX_DISTANCE
end

---Sets the pump a player carries on the bung of a drum, on the server
-- @param table player player carrying the pump
-- @param table handTool pump in hand
-- @param table container drum aimed at
function RMS_DrumPump.mount(player, handTool, container)
    local containerSpec = container[RMS_FluidContainer.SPEC_TABLE_NAME]
    if containerSpec == nil or containerSpec.pump == nil or containerSpec.hasPump or handTool[specName] == nil
        or handTool:getCarryingPlayer() ~= player or container:getOwnerFarmId() ~= player.farmId
        or not getIsInReach(player, container) then
        return
    end

    container:setRMSFluidPump(true)
    if next(RMS_DrumPump.mounted) == nil then
        g_currentMission:addUpdateable(RMS_DrumPump)
    end
    RMS_DrumPump.mounted[handTool] = true
end

---Takes the pumps set on a drum out of the hand that carried them
function RMS_DrumPump.update()
    local mounted = RMS_DrumPump.mounted
    RMS_DrumPump.mounted = {}
    g_currentMission:removeUpdateable(RMS_DrumPump)

    for handTool in pairs(mounted) do
        if not handTool.isDeleted then
            handTool:delete()
        end
    end
end

---Takes the pump off a drum into the hand of a player, on the server
-- @param table player player taking it
-- @param table container drum aimed at
function RMS_DrumPump.unmount(player, container)
    local containerSpec = container[RMS_FluidContainer.SPEC_TABLE_NAME]
    if containerSpec == nil or not containerSpec.hasPump or containerSpec.carrierTool ~= nil or containerSpec.isBeingTaken
        or container:getOwnerFarmId() ~= player.farmId or player:getIsHoldingHandTool()
        or not getIsInReach(player, container) then
        return
    end

    -- the hand tool loads over several frames, a second click must not take the pump twice
    containerSpec.isBeingTaken = true
    local loadingData = HandToolLoadingData.new()
    loadingData:setFilename(modDirectory .. RMS_DrumPump.FILENAME)
    loadingData:setOwnerFarmId(player.farmId)
    loadingData:setIsRegistered(false)
    loadingData:load(RMS_DrumPump.onUnmounted, RMS_DrumPump, { player = player, container = container })
end

---Puts the loaded pump in the hand of the player and takes it off the drum
function RMS_DrumPump.onUnmounted(_, handTool, loadingState, arguments)
    local player, container = arguments.player, arguments.container
    container[RMS_FluidContainer.SPEC_TABLE_NAME].isBeingTaken = nil
    if loadingState ~= HandToolLoadingState.OK then
        return
    end
    if container.isDeleted or player.isDeleted or not player:getCanPickupHandTool(handTool) then
        handTool:delete()
        return
    end

    -- held before it is registered: the creation stream then carries its holder to every client
    handTool:setHolder(player, true)
    player:setCurrentHandTool(handTool, true)
    handTool:register()
    container:setRMSFluidPump(false)
end

---
function RMS_DrumPump:onLoad(xmlFile, baseDirectory)
    local spec = self[specName]
    if spec == nil then
        spec = {}
        self[specName] = spec
    end
    spec.targetTimer = 0

    if self.isClient then
        RMS_FluidHandTool.registerOverlays()
    end
end

---Finds the drum without a pump the player aims at
local function updateTarget(handTool, player)
    local spec = handTool[specName]
    local node = player.targeter:getClosestTargetedNodeFromType(RMS_DrumPump)
    local container = node ~= nil and g_currentMission:getNodeObject(node) or nil
    local containerSpec = container ~= nil and container[RMS_FluidContainer.SPEC_TABLE_NAME] or nil
    if containerSpec == nil or containerSpec.pump == nil or containerSpec.hasPump
        or container:getOwnerFarmId() ~= g_currentMission:getFarmId() then
        container = nil
    end

    spec.target = container
    g_inputBinding:setActionEventActive(spec.mountEventId, container ~= nil)
end

---
function RMS_DrumPump:onUpdate(dt)
    local spec = self[specName]
    local player = self:getCarryingPlayer()
    if player ~= nil and player.isOwner and self:getIsHeld() then
        spec.targetTimer = spec.targetTimer - dt
        if spec.targetTimer <= 0 then
            spec.targetTimer = RMS_DrumPump.TARGET_REFRESH_INTERVAL
            updateTarget(self, player)
        end
    end
end

---Offers to set the pump on the drum aimed at
function RMS_DrumPump:onDraw()
    local container = self[specName].target
    if container ~= nil and not container.isDeleted then
        local product = RMS_Fluids.PRODUCTS[container:getRMSFluidProductKey()]
        g_currentMission.hud.contextActionDisplay:setContext(InputAction.ACTIVATE_HANDTOOL, RMS_FluidHandTool.LOGO_SLICE_PREFIX .. product.brand,
            container:getRMSFluidKindText(), HUD.CONTEXT_PRIORITY.HIGH, g_i18n:getText("rms_drum_pump_mount"))
    end
end

---
function RMS_DrumPump:onRegisterActionEvents()
    if not self:getIsActiveForInput(true) then
        return
    end

    -- the hand tool click, offered only on a drum and acting at its release
    local _, mountEventId = self:addActionEvent(InputAction.ACTIVATE_HANDTOOL, self, RMS_DrumPump.onMountAction, true, false, false, false, nil)
    g_inputBinding:setActionEventTextPriority(mountEventId, GS_PRIO_VERY_HIGH)
    g_inputBinding:setActionEventText(mountEventId, g_i18n:getText("rms_drum_pump_mount"))
    self[specName].mountEventId = mountEventId
end

---Sets the pump on the drum aimed at
function RMS_DrumPump:onMountAction()
    local container = self[specName].target
    if container ~= nil and not container.isDeleted then
        RMS_DrumPumpEvent.send(container, self)
    end
end

---Lets the player aim at drums with the pump
function RMS_DrumPump:onHeldStart()
    local player = self:getCarryingPlayer()
    if player ~= nil and player.isOwner then
        player.targeter:addTargetType(RMS_DrumPump, CollisionFlag.VEHICLE, 0, HandToolHands.PICKUP_DISTANCE)
    end
end

---
function RMS_DrumPump:onHeldEnd()
    local player = self:getCarryingPlayer()
    if player ~= nil and player.isOwner then
        player.targeter:removeTargetType(RMS_DrumPump)
        self[specName].target = nil
    end
end
