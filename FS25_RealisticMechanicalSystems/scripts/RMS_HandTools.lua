-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---Hand tool specialization: air blower, grease gun and jumper cables
rmsHandTools = {}

local specName = "spec_" .. g_currentModName .. ".rmsHandTools"

---Returns the reach of the hand tool raycast
local function getRaycastDistance()
    return RMS_Config.FIELD_CARE.RAYCAST_DISTANCE
end


local log_dbg = RMS_Utils.createLogger("[RMS_HAND_TOOLS]")

---Returns the hand tool spec of an object, creating it on first use
local function ensureSpec(object)
    local spec = object[specName]
    if spec == nil then
        spec = {}
        object[specName] = spec
    end

    return spec
end

---Returns the hand tool spec of an object without creating it
-- @param table? tool hand tool
-- @return table? spec hand tool spec, nil when the object carries none
function rmsHandTools.getSpec(tool)
    if tool == nil then
        return nil
    end

    if g_currentModName ~= nil then
        local spec = tool["spec_" .. g_currentModName .. ".rmsHandTools"]
        if spec ~= nil then
            return spec
        end
    end

    for key, value in pairs(tool) do
        if type(key) == "string"
            and string.sub(key, 1, 5) == "spec_"
            and string.sub(key, -13) == ".rmsHandTools" then
            return value
        end
    end

    return nil
end

---Returns which of the three tools this is, read from its xml
local function getToolKind(handTool)
    local configFileName = string.lower(handTool ~= nil and handTool.configFileName or "")

    if string.find(configFileName, "airblower", 1, true) then
        return "airBlower"
    end

    if string.find(configFileName, "greasegun", 1, true) then
        return "greaseGun"
    end

    if string.find(configFileName, "jumpercables", 1, true) then
        return "jumperCables"
    end

    return "unknown"
end

---Resolves an i3d node declared under a mapping key
local function resolveMappedNode(object, mappingKey)
    if object == nil or object.components == nil or object.i3dMappings == nil then
        return nil
    end

    return I3DUtil.indexToObject(object.components, mappingKey, object.i3dMappings)
end

---Restores the cable pair to its own graphics
local function restoreLeftCablePair(handTool)
    local spec = ensureSpec(handTool)
    if spec.leftPairParent == nil or spec.leftPairNode == nil then
        return
    end

    link(spec.leftPairParent, spec.leftPairNode)
    setTranslation(spec.leftPairNode, unpack(spec.leftPairTranslation))
    setRotation(spec.leftPairNode, unpack(spec.leftPairRotation))
end

---Attaches the tool to each hand without moving the character's skeleton
function rmsHandTools:attachToolToHand(superFunc)
    restoreLeftCablePair(self)
    local attached = superFunc(self)
    local spec = ensureSpec(self)
    if attached and spec.leftHandNode ~= nil then
        local player = self:getCarryingPlayer()
        local model = player.graphicsComponent.model
        if model.thirdPersonLeftHandNode ~= nil then
            HandToolUtil.linkAndTransformRelativeToParent(spec.leftPairNode, spec.leftHandNode, model.thirdPersonLeftHandNode)
        end
    end
    return attached
end

---Keeps both cable pairs in the native first-person graphics container.
function rmsHandTools:attachToolToCamera(superFunc)
    restoreLeftCablePair(self)
    return superFunc(self)
end

function rmsHandTools:detachTool(superFunc)
    restoreLeftCablePair(self)
    return superFunc(self)
end

---Raycasts forward from the tool and returns the vehicle it hits
local function getRaycastVehicle(handTool, maxDistance)
    local spec = ensureSpec(handTool)
    spec.raycastVehicle = nil
    spec.raycastVehicleDistance = math.huge

    if spec.raycastNode == nil or spec.raycastNode == 0 then
        log_dbg("Raycast aborted: raycastNode is missing")
        return nil
    end

    local x, y, z = getWorldTranslation(spec.raycastNode)
    local dx, dy, dz = localDirectionToWorld(spec.raycastNode, 0, 0, -1)

    raycastAll(x, y, z, dx, dy, dz, maxDistance or getRaycastDistance(), "handToolRaycastCallback", handTool, nil, false, true)

    return spec.raycastVehicle
end

---Sets the text shown on the tool action
local function setActionText(handTool, text)
    local spec = ensureSpec(handTool)
    if spec.activateActionEventId ~= nil then
        g_inputBinding:setActionEventText(spec.activateActionEventId, text)
    end
end

---Returns the action text of the tool when it points at nothing
local function getDefaultActionText(handTool)
    local toolKind = getToolKind(handTool)

    if toolKind == "airBlower" then
        return g_i18n:getText("rms_air_blower_action_short")
    elseif toolKind == "greaseGun" then
        return g_i18n:getText("rms_grease_gun_action")
    elseif toolKind == "jumperCables" then
        return g_i18n:getText("rms_jumper_cables_action")
    end

    return ""
end

---Starts or stops one sound of the air blower
local function setBlowerSoundState(handTool, sampleName, shouldPlay)
    local spec = ensureSpec(handTool)
    if spec == nil or spec.samples == nil or spec.toolKind ~= "airBlower" then
        return
    end

    RMS_SoundManager.setSamplePlaying(spec.samples[sampleName], shouldPlay)
end

---Puts the dust emitter of the blower back at its rest position
local function resetDustEmitterPosition(handTool)
    local spec = ensureSpec(handTool)
    if spec.dustEmitterRootNode ~= nil and spec.dustEmitterRootNode ~= 0 then
        setTranslation(
            spec.dustEmitterRootNode,
            spec.dustEmitterBaseX or 0,
            spec.dustEmitterBaseY or 0,
            spec.dustEmitterBaseZ or 0
        )
    end
end

local function setDustEmitterDistance(handTool, distance)
    local spec = ensureSpec(handTool)
    if spec.dustEmitterRootNode == nil or spec.dustEmitterRootNode == 0 then
        return
    end

    local clampedDistance = math.max(tonumber(distance) or 0, 0.1)

    setTranslation(
        spec.dustEmitterRootNode,
        spec.dustEmitterBaseX + spec.dustEmitterDirX * clampedDistance,
        spec.dustEmitterBaseY + spec.dustEmitterDirY * clampedDistance,
        spec.dustEmitterBaseZ + spec.dustEmitterDirZ * clampedDistance
    )
end

---Replicates the tool state, skipping an unchanged one unless forced
local function sendHandToolState(handTool, state, force, targetVehicle, targetDistance)
    if g_server == nil and g_client == nil then
        return
    end

    local spec = ensureSpec(handTool)
    if state == "use" then
        local distance = tonumber(targetDistance) or 0
        if not force
            and spec.lastSentUseTargetVehicle == targetVehicle
            and math.abs((spec.lastSentUseTargetDistance or 0) - distance) < 0.05 then
            return
        end

        RMS_HandToolSyncEvent.send(handTool, state, targetVehicle, distance)
        spec.lastSentUseTargetVehicle = targetVehicle
        spec.lastSentUseTargetDistance = distance
        return
    end

    if not force and spec.lastSentNetworkState == state then
        return
    end

    RMS_HandToolSyncEvent.send(handTool, state, targetVehicle, targetDistance)

    if state == "stop" then
        spec.lastSentUseTargetVehicle = nil
        spec.lastSentUseTargetDistance = nil
    end

    spec.lastSentNetworkState = state
end

---Broadcasts the jumper cable state from the server
local function broadcastJumperCablesState(handTool, state, targetVehicle)
    local spec = ensureSpec(handTool)

    if g_server ~= nil then
        RMS_JumperCablesEvent.broadcastState(handTool, state, targetVehicle, spec.connectedVehicleA, spec.connectedVehicleB)
    end

    if handTool.isClient then
        handTool:applyJumperCablesState(state, targetVehicle, spec.connectedVehicleA, spec.connectedVehicleB)
    end
end

---Shows the cable clamps matching the current connection
local function updateJumperCablesVisibility(handTool)
    local spec = ensureSpec(handTool)
    if spec.toolKind ~= "jumperCables" then
        return
    end

    if spec.leftPairNode ~= nil and spec.leftPairNode ~= 0 then
        setVisibility(spec.leftPairNode, spec.connectedVehicleA == nil)
    end

    if spec.rightPairNode ~= nil and spec.rightPairNode ~= 0 then
        setVisibility(spec.rightPairNode, spec.connectedVehicleB == nil)
    end
end

---Resolves a connected object to the vehicle carrying the battery
local function normalizeConnectedVehicle(vehicle)
    if vehicle == nil then
        return nil
    end

    if vehicle.getRootVehicle ~= nil then
        return vehicle:getRootVehicle()
    end

    return vehicle
end

---Tells whether two vehicles are already linked by jumper cables
local function areVehiclesExternallyConnected(vehicleA, vehicleB)
    vehicleA = normalizeConnectedVehicle(vehicleA)
    vehicleB = normalizeConnectedVehicle(vehicleB)

    if vehicleA == nil or vehicleB == nil or vehicleA == vehicleB then
        return false
    end

    local specA = vehicleA.spec_RealisticMechanicalSystems
    local specB = vehicleB.spec_RealisticMechanicalSystems
    if specA == nil or specB == nil then
        return false
    end

    local connectionA = specA.externalPowerConnection
    if type(connectionA) == "table" and connectionA.object ~= nil then
        connectionA = connectionA.object
    end

    local connectionB = specB.externalPowerConnection
    if type(connectionB) == "table" and connectionB.object ~= nil then
        connectionB = connectionB.object
    end

    return connectionA == vehicleB and connectionB == vehicleA
end


---
-- @param table specializations specializations of the hand tool type
-- @return boolean hasPrerequisite true when the specialization applies
function rmsHandTools.prerequisitesPresent(specializations)
    return true
end

---
-- @param table handTool hand tool type
function rmsHandTools.registerFunctions(handTool)
    SpecializationUtil.registerFunction(handTool, "handToolRaycastCallback", rmsHandTools.handToolRaycastCallback)
    SpecializationUtil.registerFunction(handTool, "applyAirBlowerNetworkState", rmsHandTools.applyAirBlowerNetworkState)
    SpecializationUtil.registerFunction(handTool, "tryUseGreaseGunServer", rmsHandTools.tryUseGreaseGunServer)
    SpecializationUtil.registerFunction(handTool, "handleJumperCablesActionServer", rmsHandTools.handleJumperCablesActionServer)
    SpecializationUtil.registerFunction(handTool, "applyJumperCablesState", rmsHandTools.applyJumperCablesState)
    for _, name in ipairs({"attachToolToHand", "attachToolToCamera", "detachTool"}) do
        if handTool.functions[name] ~= nil then
            SpecializationUtil.registerOverwrittenFunction(handTool, name, rmsHandTools[name])
        else
            SpecializationUtil.registerFunction(handTool, name, Utils.overwrittenFunction(HandTool[name], rmsHandTools[name]))
        end
    end
end

---
-- @param table handTool hand tool type
function rmsHandTools.registerEventListeners(handTool)
    SpecializationUtil.registerEventListener(handTool, "onLoad", rmsHandTools)
    SpecializationUtil.registerEventListener(handTool, "onPostLoad", rmsHandTools)
    SpecializationUtil.registerEventListener(handTool, "onDelete", rmsHandTools)
    SpecializationUtil.registerEventListener(handTool, "onUpdate", rmsHandTools)
    SpecializationUtil.registerEventListener(handTool, "onWriteStream", rmsHandTools)
    SpecializationUtil.registerEventListener(handTool, "onReadStream", rmsHandTools)
    SpecializationUtil.registerEventListener(handTool, "onHeldStart", rmsHandTools)
    SpecializationUtil.registerEventListener(handTool, "onHeldEnd", rmsHandTools)
    SpecializationUtil.registerEventListener(handTool, "onHandToolHolderChanged", rmsHandTools)
    SpecializationUtil.registerEventListener(handTool, "onRegisterActionEvents", rmsHandTools)
end

---
-- @param table savegame savegame
function rmsHandTools:onLoad(savegame)
    ensureSpec(self)
end

---
-- @param table savegame savegame
function rmsHandTools:onPostLoad(savegame)
    local spec = ensureSpec(self)
    spec.toolKind = getToolKind(self)
    spec.activateText = getDefaultActionText(self)
    spec.isActive = false
    spec.activatePressed = false
    spec.raycastVehicle = nil
    spec.raycastVehicleDistance = math.huge
    spec.raycastNode = resolveMappedNode(self, "raycastNode")
    spec.leftPairNode = nil
    spec.rightPairNode = nil
    spec.dustEmitterNode = nil
    spec.dustEmitterRootNode = nil
    spec.dustEmitterBaseX = nil
    spec.dustEmitterBaseY = nil
    spec.dustEmitterBaseZ = nil
    spec.dustParticleSystem = nil
    spec.lastAirBlowerHintKey = nil
    spec.networkUseActive = false
    spec.networkTargetVehicle = nil
    spec.networkTargetDistance = 0
    spec.lastSentNetworkState = nil
    spec.lastSentUseTargetVehicle = nil
    spec.lastSentUseTargetDistance = nil
    spec.samples = spec.samples or {}

    if self.isClient then
        local xmlSoundFile = loadXMLFile("rmsHandToolSounds", self.baseDirectory .. "sounds/rms_sounds.xml")
        if xmlSoundFile ~= nil then
            if spec.toolKind == "airBlower" then
                spec.samples.airBlower = g_soundManager:loadSampleFromXML(xmlSoundFile, "sounds", "airBlowerTool", self.baseDirectory, self.components, 0, AudioGroup.VEHICLE, self.i3dMappings, self)
                spec.samples.airBlowerAirResistance = g_soundManager:loadSampleFromXML(
                    xmlSoundFile, "sounds", "airBlowerAirResistanceTool", self.baseDirectory,
                    self.components, 0, AudioGroup.VEHICLE, self.i3dMappings, self
                )
            elseif spec.toolKind == "greaseGun" then
                spec.samples.greaseGun = g_soundManager:loadSampleFromXML(xmlSoundFile, "sounds", "greaseGunTool", self.baseDirectory, self.components, 1, AudioGroup.VEHICLE, self.i3dMappings, self)
            elseif spec.toolKind == "jumperCables" then
                spec.samples.jumperCablesConnect = g_soundManager:loadSampleFromXML(
                    xmlSoundFile, "sounds", "jumperCablesConnectTool", self.baseDirectory,
                    self.components, 1, AudioGroup.VEHICLE, self.i3dMappings, self
                )
                spec.samples.jumperCablesDisconnect = g_soundManager:loadSampleFromXML(
                    xmlSoundFile, "sounds", "jumperCablesDisconnectTool", self.baseDirectory,
                    self.components, 1, AudioGroup.VEHICLE, self.i3dMappings, self
                )
            end

            delete(xmlSoundFile)
        end
    end

    if spec.toolKind == "airBlower" then
        spec.dustEmitterNode = resolveMappedNode(self, "dustEmitterNode")
    end

    if spec.toolKind == "airBlower" and spec.dustEmitterNode ~= nil and spec.dustEmitterNode ~= 0 then
        local emitterParent = getParent(spec.dustEmitterNode)
        if emitterParent ~= nil and emitterParent ~= 0 then
            spec.dustEmitterRootNode = emitterParent
        else
            spec.dustEmitterRootNode = spec.dustEmitterNode
        end

        if spec.dustEmitterRootNode ~= nil and spec.dustEmitterRootNode ~= 0 then
            spec.dustEmitterBaseX, spec.dustEmitterBaseY, spec.dustEmitterBaseZ = getTranslation(spec.dustEmitterRootNode)
            spec.dustEmitterDirX, spec.dustEmitterDirY, spec.dustEmitterDirZ = localDirectionToLocal(spec.dustEmitterRootNode,
                getParent(spec.dustEmitterRootNode), 0, 0, -1)
        end

        local sourceParticleSystem = g_particleSystemManager:getParticleSystem("wheel_dust")

        if sourceParticleSystem ~= nil then
            spec.dustParticleSystem = ParticleUtil.copyParticleSystem(nil, nil, sourceParticleSystem, spec.dustEmitterNode)

            if spec.dustParticleSystem ~= nil then
                ParticleUtil.setEmittingState(spec.dustParticleSystem, false)
            end
        end
    end

    if spec.toolKind == "jumperCables" then
        spec.heldGraphicsNode = resolveMappedNode(self, "heldGraphics")
        spec.storedGraphicsNode = resolveMappedNode(self, "storedGraphics")
        spec.leftPairNode = resolveMappedNode(self, "leftPair")
        spec.rightPairNode = resolveMappedNode(self, "rightPair")
        spec.leftHandNode = resolveMappedNode(self, "leftHandNode")
        if spec.leftPairNode ~= nil and spec.leftHandNode ~= nil then
            spec.leftPairParent = getParent(spec.leftPairNode)
            spec.leftPairTranslation = {getTranslation(spec.leftPairNode)}
            spec.leftPairRotation = {getRotation(spec.leftPairNode)}
        end
        spec.connectedVehicleA = nil
        spec.connectedVehicleB = nil
        updateJumperCablesVisibility(self)
    end
end

---
-- @param integer streamId streamId
-- @param Connection connection connection
function rmsHandTools:onWriteStream(streamId, connection)
    local spec = ensureSpec(self)
    if spec.toolKind == "airBlower" and not connection:getIsServer() then
        streamWriteBool(streamId, spec.networkUseActive)
        NetworkUtil.writeNodeObject(streamId, spec.networkTargetVehicle)
        streamWriteFloat32(streamId, spec.networkTargetDistance)
    elseif spec.toolKind == "jumperCables" and not connection:getIsServer() then
        for _, suffix in ipairs({"A", "B"}) do
            local vehicle = spec["connectedVehicle" .. suffix]
            if streamWriteBool(streamId, vehicle ~= nil) then
                NetworkUtil.writeNodeObject(streamId, vehicle)
            end
        end
    end
end

---
-- @param integer streamId streamId
-- @param Connection connection connection
function rmsHandTools:onReadStream(streamId, connection)
    local spec = ensureSpec(self)
    if spec.toolKind == "airBlower" and connection:getIsServer() then
        local isActive = streamReadBool(streamId)
        local targetVehicle = NetworkUtil.readNodeObject(streamId)
        local targetDistance = streamReadFloat32(streamId)
        self:applyAirBlowerNetworkState(isActive and "use" or "stop", targetVehicle, targetDistance)
    elseif spec.toolKind == "jumperCables" and connection:getIsServer() then
        for _, suffix in ipairs({"A", "B"}) do
            spec["connectedVehicle" .. suffix] = nil
            spec["pendingConnectedVehicle" .. suffix .. "Id"] = nil
            if streamReadBool(streamId) then
                spec["pendingConnectedVehicle" .. suffix .. "Id"] = NetworkUtil.readNodeObjectId(streamId)
                self:raiseActive()
            end
        end
        updateJumperCablesVisibility(self)
    end
end

---
function rmsHandTools:onDelete()
    restoreLeftCablePair(self)
    local spec = ensureSpec(self)

    if self.isServer and spec.toolKind == "jumperCables"
        and areVehiclesExternallyConnected(spec.connectedVehicleA, spec.connectedVehicleB) then
        normalizeConnectedVehicle(spec.connectedVehicleA):clearExternalPowerConnection(spec.connectedVehicleB)
    end

    setBlowerSoundState(self, "airBlower", false)
    setBlowerSoundState(self, "airBlowerAirResistance", false)

    if spec.samples ~= nil then
        if spec.samples.airBlower ~= nil then
            g_soundManager:deleteSample(spec.samples.airBlower)
        end

        if spec.samples.airBlowerAirResistance ~= nil then
            g_soundManager:deleteSample(spec.samples.airBlowerAirResistance)
        end

        if spec.samples.greaseGun ~= nil then
            g_soundManager:deleteSample(spec.samples.greaseGun)
        end

        if spec.samples.jumperCablesConnect ~= nil then
            g_soundManager:deleteSample(spec.samples.jumperCablesConnect)
        end

        if spec.samples.jumperCablesDisconnect ~= nil then
            g_soundManager:deleteSample(spec.samples.jumperCablesDisconnect)
        end
    end

    if spec.dustParticleSystem ~= nil then
        ParticleUtil.deleteParticleSystem(spec.dustParticleSystem)
        spec.dustParticleSystem = nil
    end
end


---Registers the tool actions and starts its idle sounds
function rmsHandTools:onHeldStart()
    if g_localPlayer == nil or self:getCarryingPlayer() ~= g_localPlayer then
        return
    end

    local spec = ensureSpec(self)
    spec.isActive = true
    spec.activatePressed = false
    spec.networkUseActive = false
    spec.networkTargetVehicle = nil
    spec.networkTargetDistance = 0
    spec.lastAirBlowerHintKey = nil
    spec.lastSentNetworkState = nil
    spec.lastSentUseTargetVehicle = nil
    spec.lastSentUseTargetDistance = nil

    if spec.toolKind == 'jumperCables' and self.isClient and spec.connectedVehicleA ~= nil and spec.connectedVehicleB ~= nil then
        g_currentMission:showBlinkingWarning(
            string.format(
                g_i18n:getText("rms_jumper_cables_both_already_connected"),
                spec.connectedVehicleA:getFullName(),
                spec.connectedVehicleB:getFullName()
            ),
            2200
        )
    end

end

---Stops the sounds and the effects when the player puts the tool away
function rmsHandTools:onHeldEnd()
    local spec = ensureSpec(self)

    if spec.toolKind == "airBlower" and spec.lastSentNetworkState == "start" then
        sendHandToolState(self, "stop", true)
    end

    spec.isActive = false
    spec.activatePressed = false
    spec.networkUseActive = false
    spec.networkTargetVehicle = nil
    spec.networkTargetDistance = 0
    spec.lastAirBlowerHintKey = nil
    spec.lastSentUseTargetVehicle = nil
    spec.lastSentUseTargetDistance = nil
    setActionText(self, spec.activateText)
    setBlowerSoundState(self, "airBlower", false)
    setBlowerSoundState(self, "airBlowerAirResistance", false)
    resetDustEmitterPosition(self)

end

-- @param table? holder new holder of the tool
-- @param table? lastHolder holder it leaves
function rmsHandTools:onHandToolHolderChanged(holder, lastHolder)
    local spec = ensureSpec(self)
    if spec.toolKind ~= "jumperCables" then
        return
    end

    local isStored = holder ~= nil and holder:isa(HandToolHolder)
    setVisibility(spec.heldGraphicsNode, not isStored)
    setVisibility(spec.storedGraphicsNode, isStored)

    if isStored and self.isServer and (spec.connectedVehicleA ~= nil or spec.connectedVehicleB ~= nil) then
        if areVehiclesExternallyConnected(spec.connectedVehicleA, spec.connectedVehicleB) then
            normalizeConnectedVehicle(spec.connectedVehicleA):clearExternalPowerConnection(spec.connectedVehicleB)
        end
        spec.connectedVehicleA = nil
        spec.connectedVehicleB = nil
        broadcastJumperCablesState(self, "jumperDisconnected", nil)
    end
end

---Applies the blower state, aiming its dust emitter and cleaning the target
-- @param string state tool state
-- @param table? targetVehicle vehicle being blown out
-- @param float? targetDistance distance to it
-- @return boolean changed true when the state changed
function rmsHandTools:applyAirBlowerNetworkState(state, targetVehicle, targetDistance)
    local spec = ensureSpec(self)
    if spec.toolKind ~= "airBlower" then
        return false
    end

    if state == "start" then
        spec.networkUseActive = true
        spec.networkTargetVehicle = nil
        spec.networkTargetDistance = 0
    elseif state == "stop" then
        spec.networkUseActive = false
        spec.networkTargetVehicle = nil
        spec.networkTargetDistance = 0
    elseif state == "use" then
        spec.networkUseActive = true
        spec.networkTargetVehicle = normalizeConnectedVehicle(targetVehicle)
        spec.networkTargetDistance = tonumber(targetDistance) or 0
    else
        return false
    end

    return true
end

---Greases the target vehicle on the server when it needs it
-- @param table? targetVehicle vehicle being greased
-- @param Connection? connection connection of the requesting player
-- @return boolean used true when grease was applied
function rmsHandTools:tryUseGreaseGunServer(targetVehicle, connection)
    if not self.isServer then
        return false
    end

    local spec = ensureSpec(self)
    if spec.toolKind ~= "greaseGun" then
        return false
    end

    if connection ~= nil then
        local player = g_currentMission.connectionsToPlayer[connection]
        if player == nil or self.getCarryingPlayer == nil or self:getCarryingPlayer() ~= player then
            return false
        end
    end

    local vehicle = normalizeConnectedVehicle(targetVehicle)
    if vehicle == nil then
        vehicle = getRaycastVehicle(self, getRaycastDistance())
    end

    if vehicle == nil then
        return false
    end

    local vehicleSpec = vehicle.spec_RealisticMechanicalSystems
    if vehicleSpec == nil or not vehicleSpec.isVehicleNeedLubricate then
        return false
    end

    if (tonumber(vehicleSpec.lubricationLevel) or 0) >= 1.0 then
        return false
    end

    vehicle:lubricateVehicle()
    return true
end

---Runs one jumper cable action on the server
-- @param string state requested cable state
-- @param table? targetVehicle vehicle aimed at
-- @param Connection? connection connection of the requesting player
function rmsHandTools:handleJumperCablesActionServer(state, targetVehicle, connection)
    if not self.isServer then
        return false
    end

    local spec = ensureSpec(self)
    if spec.toolKind ~= "jumperCables" then
        return false
    end

    if connection ~= nil then
        local player = g_currentMission.connectionsToPlayer[connection]
        if player == nil or self.getCarryingPlayer == nil or self:getCarryingPlayer() ~= player then
            return false
        end
    end

    local resultState = "jumperInvalid"
    local vehicle = targetVehicle

    if state ~= "jumperInteract" then
        return false
    end

    -- no rms
    if vehicle == nil or vehicle.spec_RealisticMechanicalSystems == nil then
        resultState = "jumperInvalid"

    -- disconnect
    elseif vehicle == spec.connectedVehicleA or vehicle == spec.connectedVehicleB then
        if spec.connectedVehicleA ~= nil and spec.connectedVehicleA.clearExternalPowerConnection ~= nil then
            spec.connectedVehicleA:clearExternalPowerConnection(spec.connectedVehicleB)
        elseif spec.connectedVehicleB ~= nil and spec.connectedVehicleB.clearExternalPowerConnection ~= nil then
            spec.connectedVehicleB:clearExternalPowerConnection(spec.connectedVehicleA)
        end

        if vehicle == spec.connectedVehicleA then
            spec.connectedVehicleA = nil
        else
            spec.connectedVehicleB = nil
        end

        resultState = "jumperDisconnected"

    -- connect first
    elseif spec.connectedVehicleA == nil and spec.connectedVehicleB == nil then
        spec.connectedVehicleA = vehicle
        resultState = "jumperSelected"

    -- connect second
    elseif spec.connectedVehicleA == nil or spec.connectedVehicleB == nil then
        local firstVehicle = spec.connectedVehicleA or spec.connectedVehicleB
        local isValid, reason = RMS_Electrical.isValidPowerPair(firstVehicle, vehicle)

        if not isValid then
            if reason == "TOO_FAR" then
                resultState = "jumperTooFar"
            elseif reason == "ELECTRIC_DONOR" then
                resultState = "jumperElectricDonor"
            elseif reason == "VOLTAGE" then
                resultState = "jumperVoltage"
            else
                resultState = "jumperInvalid"
            end
        else
            if spec.connectedVehicleB == nil then
                spec.connectedVehicleB = vehicle
            else
                spec.connectedVehicleA = vehicle
            end

            if firstVehicle:establishExternalPowerConnection(vehicle) then
                resultState = "jumperConnected"
            else
                if spec.connectedVehicleA == vehicle then
                    spec.connectedVehicleA = nil
                elseif spec.connectedVehicleB == vehicle then
                    spec.connectedVehicleB = nil
                end

                resultState = "jumperInvalid"
            end
        end
    else
        resultState = "jumperFull"
    end

    broadcastJumperCablesState(self, resultState, vehicle)
    return resultState == "jumperSelected" or resultState == "jumperConnected" or resultState == "jumperDisconnected"
end

---Applies the cable state locally, moving the clamps and the sounds
-- @param string state cable state
-- @param table? targetVehicle vehicle aimed at
-- @param table? connectedVehicleA vehicle on the first clamp
-- @param table? connectedVehicleB vehicle on the second clamp
function rmsHandTools:applyJumperCablesState(state, targetVehicle, connectedVehicleA, connectedVehicleB)
    local spec = ensureSpec(self)
    spec.connectedVehicleA = connectedVehicleA
    spec.connectedVehicleB = connectedVehicleB
    updateJumperCablesVisibility(self)

    if self.isClient then
        if state == "jumperSelected" or state == "jumperConnected" then
            RMS_SoundManager.playSample(spec.samples.jumperCablesConnect)
        elseif state == "jumperDisconnected" or state == "jumperAutoDisconnected" then
            RMS_SoundManager.playSample(spec.samples.jumperCablesDisconnect)
        end
    end

    if not self.isClient or g_localPlayer == nil or self.getCarryingPlayer == nil or self:getCarryingPlayer() ~= g_localPlayer then
        return
    end

    local targetName = targetVehicle ~= nil and targetVehicle.getFullName ~= nil and targetVehicle:getFullName() or nil
    local firstVehicle = spec.connectedVehicleA or spec.connectedVehicleB
    local firstVehicleName = firstVehicle ~= nil and firstVehicle.getFullName ~= nil and firstVehicle:getFullName() or nil

    if state == "jumperSelected" and targetName ~= nil then
        g_currentMission:showBlinkingWarning(string.format(g_i18n:getText("rms_jumper_cables_connected"), targetName), 2200)
    elseif state == "jumperConnected" and targetName ~= nil then
        g_currentMission:showBlinkingWarning(string.format(g_i18n:getText("rms_jumper_cables_connected"), targetName), 2200)
    elseif state == "jumperDisconnected" and targetName ~= nil then
        g_currentMission:showBlinkingWarning(string.format(g_i18n:getText("rms_jumper_cables_disconnected"), targetName), 2200)
    elseif state == "jumperAutoDisconnected" then
        g_currentMission:showBlinkingWarning(g_i18n:getText("rms_jumper_cables_auto_disconnected"), 2200)
    elseif state == "jumperTooFar" and targetName ~= nil and firstVehicleName ~= nil then
        g_currentMission:showBlinkingWarning(string.format(g_i18n:getText("rms_jumper_cables_is_too_far"), targetName, firstVehicleName), 2200)
    elseif state == "jumperFull" and spec.connectedVehicleA ~= nil and spec.connectedVehicleB ~= nil then
        g_currentMission:showBlinkingWarning(
            string.format(
                g_i18n:getText("rms_jumper_cables_both_already_connected"),
                spec.connectedVehicleA:getFullName(),
                spec.connectedVehicleB:getFullName()
            ),
            2200
        )
    elseif state == "jumperElectricDonor" then
        g_currentMission:showBlinkingWarning(g_i18n:getText("rms_jumper_cables_electric_donor"), 2200)
    elseif state == "jumperVoltage" then
        g_currentMission:showBlinkingWarning(g_i18n:getText("rms_jumper_cables_voltage_mismatch"), 2200)
    elseif state == "jumperInvalid" then
        g_currentMission:showBlinkingWarning(g_i18n:getText("rms_jumper_cables_impossible_to_connect"), 2200)
    end
end


---
function rmsHandTools:onRegisterActionEvents()
    local spec = ensureSpec(self)
    if not self:getIsActiveForInput(true) then
        return
    end

    if spec.activateText == nil or spec.activateText == "" then
        return
    end

    local _, eventId = self:addActionEvent(
        InputAction.ACTIVATE_HANDTOOL,
        self,
        rmsHandTools.onActionCallback,
        true,
        true,
        false,
        true,
        nil
    )

    spec.activateActionEventId = eventId

    if eventId ~= nil then
        g_inputBinding:setActionEventTextPriority(eventId, GS_PRIO_VERY_HIGH)
        g_inputBinding:setActionEventText(eventId, spec.activateText)
        g_inputBinding:setActionEventActive(eventId, true)
    end
end

---Returns the text an air blower answers a vehicle with nothing to blow out
local function getAirBlowerAnswerKey(vehicleSpec)
    if vehicleSpec == nil or vehicleSpec.isVehicleNeedBlowOut ~= true then
        return "rms_air_blower_cleaning_not_require"
    elseif (tonumber(vehicleSpec.radiatorClogging) or 0) > 0 or RMS_Consumables.getAirFilterLooseDust(vehicleSpec) > 0 then
        return nil
    elseif RMS_Consumables.getIsAirFilterWornOut(vehicleSpec) then
        return "rms_air_blower_filter_requires_maintenance"
    end

    return "rms_air_blower_already_clean"
end

---Writes the answer of an air blower to a vehicle
local function formatAirBlowerAnswer(vehicle, textKey)
    local hours = textKey == "rms_air_blower_filter_requires_maintenance" and RMS_Utils.formatAirFilterServiceHours(vehicle) or nil
    return string.format(g_i18n:getText(textKey), vehicle:getFullName(), hours)
end

---Runs the tool action on the vehicle the player points at
-- @param string actionName input action name
-- @param float inputValue input value
function rmsHandTools:onActionCallback(actionName, inputValue)
    local spec = ensureSpec(self)
    local isPressed = inputValue > 0

    if not spec.isActive then
        return
    end

    spec.activatePressed = isPressed

    -- airBlower
    if not isPressed then
        if spec.toolKind == "airBlower" then
            sendHandToolState(self, "stop")
        end

        spec.lastAirBlowerHintKey = nil
        setActionText(self, spec.activateText)
        setBlowerSoundState(self, "airBlower", false)
        setBlowerSoundState(self, "airBlowerAirResistance", false)
        resetDustEmitterPosition(self)
        return
    end

    if spec.toolKind == "airBlower" then
        sendHandToolState(self, "start")
    end

    local vehicle = getRaycastVehicle(self, getRaycastDistance())

    -- greaseGun
    if vehicle ~= nil and spec.toolKind == "greaseGun" then
        local vehicleSpec = vehicle.spec_RealisticMechanicalSystems
        if vehicleSpec ~= nil and vehicleSpec.isVehicleNeedLubricate and (tonumber(vehicleSpec.lubricationLevel) or 0) < 1.0 then
            sendHandToolState(self, "use", true, vehicle)
        elseif vehicleSpec ~= nil and not vehicleSpec.isVehicleNeedLubricate then
            if self.isClient then
                g_currentMission:showBlinkingWarning(string.format(g_i18n:getText("rms_grease_gun_lubrication_not_require"), vehicle:getFullName()), 2200)
            end
        else
            if self.isClient then
                g_currentMission:showBlinkingWarning(string.format(g_i18n:getText("rms_grease_gun_already_lubricated"), vehicle:getFullName()), 2200)
            end
        end
    end

    -- jumperCables
    if vehicle ~= nil and spec.toolKind == "jumperCables" then
        local vehicleSpec = vehicle.spec_RealisticMechanicalSystems
        if vehicleSpec ~= nil then
            if self.isServer then
                self:handleJumperCablesActionServer("jumperInteract", vehicle)
            else
                RMS_JumperCablesEvent.sendRequest(self, "jumperInteract", vehicle)
            end
        else
            g_currentMission:showBlinkingWarning(g_i18n:getText("rms_jumper_cables_impossible_to_connect"), 2200)
        end
    end

    -- airBlower
    if vehicle ~= nil and spec.toolKind == "airBlower" and self.isClient then
        local textKey = getAirBlowerAnswerKey(vehicle.spec_RealisticMechanicalSystems)
        if textKey ~= nil then
            g_currentMission:showBlinkingWarning(formatAirBlowerAnswer(vehicle, textKey), 2200)
        end
    end

    if vehicle == nil then
        if spec.toolKind == "airBlower" and self.isClient then
            g_currentMission:showBlinkingWarning(g_i18n:getText("rms_air_blower_no_vehicle"), 2200)
        elseif spec.toolKind == "greaseGun" and self.isClient then
            g_currentMission:showBlinkingWarning(g_i18n:getText("rms_grease_gun_no_vehicle"), 2200)
        end
    end
end

---Raycast callback keeping the first RMS vehicle hit
-- @param entityId hitActorId actor hit
-- @param float x hit x position
-- @param float y hit y position
-- @param float z hit z position
-- @param float distance hit distance
-- @param float nx hit normal x
-- @param float ny hit normal y
-- @param float nz hit normal z
-- @param integer subShapeIndex sub shape index
-- @param entityId hitShapeId shape hit
-- @return boolean continueRaycast false to stop the raycast
function rmsHandTools:handToolRaycastCallback(hitActorId, x, y, z, distance, nx, ny, nz, subShapeIndex, hitShapeId)
    local spec = ensureSpec(self)
    local vehicle = g_currentMission.vehicleSystem:getVehicleByNodeId(hitActorId, hitShapeId)

    if vehicle ~= nil and vehicle.spec_RealisticMechanicalSystems ~= nil then
        spec.raycastVehicle = vehicle
        spec.raycastVehicleDistance = distance
        return false
    end

    return true
end


---
-- @param float dt time since last call in ms
function rmsHandTools:onUpdate(dt)
    local spec = ensureSpec(self)
    if spec.toolKind == "jumperCables" and self.isClient then
        for _, suffix in ipairs({"A", "B"}) do
            local pendingKey = "pendingConnectedVehicle" .. suffix .. "Id"
            local objectId = spec[pendingKey]
            if objectId ~= nil then
                local vehicle = NetworkUtil.getObject(objectId)
                if vehicle ~= nil then
                    spec["connectedVehicle" .. suffix] = vehicle
                    spec[pendingKey] = nil
                    updateJumperCablesVisibility(self)
                else
                    self:raiseActive()
                end
            end
        end
    end
    local carryingPlayer = self:getCarryingPlayer()
    local isLocalOwner = carryingPlayer ~= nil and carryingPlayer.isOwner
    local isUsing = (isLocalOwner and spec.activatePressed) or spec.networkUseActive
    local isOperational = (isLocalOwner and spec.isActive) or spec.networkUseActive

    if spec.toolKind == "jumperCables" and isLocalOwner and spec.isActive then
        local aimed = getRaycastVehicle(self, getRaycastDistance())
        local textKey = "rms_jumper_cables_action"
        if aimed ~= nil then
            textKey = (aimed == spec.connectedVehicleA or aimed == spec.connectedVehicleB) and "rms_jumper_cables_disconnect"
                or "rms_jumper_cables_connect"
        end
        setActionText(self, g_i18n:getText(textKey))
    end

    if spec.toolKind == "jumperCables"
        and self.isServer
        and spec.connectedVehicleA ~= nil
        and spec.connectedVehicleB ~= nil
        and not areVehiclesExternallyConnected(spec.connectedVehicleA, spec.connectedVehicleB) then

        spec.connectedVehicleA = nil
        spec.connectedVehicleB = nil
        updateJumperCablesVisibility(self)
        broadcastJumperCablesState(self, "jumperAutoDisconnected", nil)
    end

    if not isOperational then
        spec.lastAirBlowerHintKey = nil
        setBlowerSoundState(self, "airBlower", false)
        setBlowerSoundState(self, "airBlowerAirResistance", false)
        if spec.dustParticleSystem ~= nil then
            ParticleUtil.setEmittingState(spec.dustParticleSystem, false)
        end
        resetDustEmitterPosition(self)
        return
    end

    if not isUsing then
        spec.lastAirBlowerHintKey = nil
        setBlowerSoundState(self, "airBlower", false)
        setBlowerSoundState(self, "airBlowerAirResistance", false)
        if spec.dustParticleSystem ~= nil then
            ParticleUtil.setEmittingState(spec.dustParticleSystem, false)
        end
        resetDustEmitterPosition(self)
        return
    end

    setBlowerSoundState(self, "airBlower", spec.toolKind == "airBlower")

    local vehicle = nil
    local targetDistance = 0
    if spec.toolKind == "airBlower" and not isLocalOwner then
        vehicle = normalizeConnectedVehicle(spec.networkTargetVehicle)
        targetDistance = spec.networkTargetDistance
    else
        vehicle = getRaycastVehicle(self, getRaycastDistance())
        targetDistance = spec.raycastVehicleDistance
    end

    if vehicle == nil then
        if spec.toolKind == "airBlower" and isLocalOwner then
            sendHandToolState(self, "use", false, nil, 0)
        end

        spec.lastAirBlowerHintKey = nil
        setActionText(self, spec.activateText)
        setBlowerSoundState(self, "airBlowerAirResistance", false)
        if spec.dustParticleSystem ~= nil then
            ParticleUtil.setEmittingState(spec.dustParticleSystem, false)
        end
        resetDustEmitterPosition(self)
        return
    end

    if spec.toolKind == "airBlower" then
        local vehicleSpec = vehicle.spec_RealisticMechanicalSystems
        local needsBlowOut = vehicleSpec ~= nil and vehicleSpec.isVehicleNeedBlowOut == true
        local vehicleId = tostring(vehicle.uniqueId or vehicle.id or vehicle.rootNode or vehicle:getFullName())
        local textKey = getAirBlowerAnswerKey(vehicleSpec)
        local hintKey = textKey ~= nil and (vehicleId .. ":" .. textKey) or nil

        if hintKey ~= nil and spec.lastAirBlowerHintKey ~= hintKey and isLocalOwner then
            g_currentMission:showBlinkingWarning(formatAirBlowerAnswer(vehicle, textKey), 2200)
        end

        spec.lastAirBlowerHintKey = hintKey
        setBlowerSoundState(self, "airBlowerAirResistance", true)

        if isLocalOwner then
            sendHandToolState(self, "use", false, vehicle, targetDistance)
        end

        if self.isServer and needsBlowOut then
            vehicle:cleanRadiatorAndAirFilter(dt)
        end

        if self.isClient then
            local currentAirFilterClogging = vehicleSpec ~= nil and vehicleSpec.airFilterClogging or 0
            local currentRadiatorClogging = vehicleSpec ~= nil and vehicleSpec.radiatorClogging or 0
            local currentAirFilterResidue = vehicleSpec ~= nil and vehicleSpec.airFilterResidue or 0
            local hasCleaningDust = currentAirFilterClogging > currentAirFilterResidue or currentRadiatorClogging > 0
            local dustScale = math.max((currentAirFilterClogging + currentRadiatorClogging) / 20, 0.01)
            local dustLifespan = math.clamp((currentAirFilterClogging + currentRadiatorClogging) * 1200, 600, 1200)

            if spec.dustParticleSystem ~= nil and hasCleaningDust then
                setDustEmitterDistance(self, targetDistance)
                ParticleUtil.setEmitCountScale(spec.dustParticleSystem, dustScale)
                ParticleUtil.setParticleLifespan(spec.dustParticleSystem, dustLifespan)
                ParticleUtil.setEmittingState(spec.dustParticleSystem, true)
            elseif spec.dustParticleSystem ~= nil then
                ParticleUtil.setEmittingState(spec.dustParticleSystem, false)
                resetDustEmitterPosition(self)
            end
        end
    else
        setBlowerSoundState(self, "airBlowerAirResistance", false)
        if spec.dustParticleSystem ~= nil then
            ParticleUtil.setEmittingState(spec.dustParticleSystem, false)
        end
        resetDustEmitterPosition(self)
        return
    end
end
