-- Copyright © 2026 Squallqt. All rights reserved.

---Jumper cables bridging the battery of a machine to another's
RMS_JumperCables = {}

local specName = "spec_" .. g_currentModName .. ".rmsJumperCables"
local modDirectory = g_currentModDirectory

RMS_JumperCables.WARNING_DURATION = 2200
RMS_JumperCables.REFUSALS = { TOO_FAR = "jumperTooFar", ELECTRIC_DONOR = "jumperElectricDonor", VOLTAGE = "jumperVoltage" }

---Tells whether the local player carries the cables
-- @param table cables jumper cables
-- @return boolean isCarried true when the local player carries them
local function getIsLocallyCarried(cables)
    local player = cables:getCarryingPlayer()
    return player ~= nil and player.isOwner
end

---Returns the machine a machine is linked to by cables
-- @param table machine machine
-- @return table? linked machine linked, nil for none
local function getPowerLink(machine)
    local connection = machine.spec_RealisticMechanicalSystems.externalPowerConnection
    return type(connection) == "table" and connection.object or connection
end

---Tells whether two machines are linked to each other
-- @param table? machineA first machine
-- @param table? machineB second machine
-- @return boolean isLinked true when they are linked to each other
local function getAreLinked(machineA, machineB)
    if machineA == nil or machineB == nil then
        return false
    end
    machineA, machineB = machineA:getRootVehicle(), machineB:getRootVehicle()
    return machineA ~= machineB and getPowerLink(machineA) == machineB and getPowerLink(machineB) == machineA
end

---Shows the clamp pairs still free on the cables
-- @param table spec cables specialization
local function showClamps(spec)
    setVisibility(spec.leftPair, spec.machineA == nil)
    setVisibility(spec.rightPair, spec.machineB == nil)
end

---Shows a warning to the local player
-- @param string textKey l10n key of the warning
-- @param any ... values of the format of the warning
local function warn(textKey, ...)
    g_currentMission:showBlinkingWarning(string.format(g_i18n:getText(textKey), ...), RMS_JumperCables.WARNING_DURATION)
end

---Puts the left clamp pair back on the cables
-- @param table spec cables specialization
local function putLeftPairBack(spec)
    link(spec.leftPairParent, spec.leftPair)
    setTranslation(spec.leftPair, unpack(spec.leftPairTranslation))
    setRotation(spec.leftPair, unpack(spec.leftPairRotation))
end

---Sends a state of the cables to every player, the server included
-- @param table cables jumper cables
-- @param string state change of the cables
-- @param table? target machine clamped or unclamped
local function tell(cables, state, target)
    local spec = cables[specName]
    RMS_JumperCablesEvent.broadcastState(cables, state, target, spec.machineA, spec.machineB)
    if cables.isClient then
        cables:setRMSJumperCablesState(state, target, spec.machineA, spec.machineB)
    end
end

---Unlinks the clamped machines
-- @param table cables jumper cables
local function unclamp(cables)
    local spec = cables[specName]
    if getAreLinked(spec.machineA, spec.machineB) then
        spec.machineA:getRootVehicle():clearExternalPowerConnection(spec.machineB)
    end
    spec.machineA, spec.machineB = nil, nil
end

---Checks if all prerequisite specializations are loaded
-- @param table specializations specializations
-- @return boolean hasPrerequisite true if all prerequisite specializations are loaded
function RMS_JumperCables.prerequisitesPresent(specializations)
    return true
end

---Registers the functions of the cables
-- @param table handToolType hand tool type
function RMS_JumperCables.registerFunctions(handToolType)
    SpecializationUtil.registerFunction(handToolType, "clampRMSJumperCables", RMS_JumperCables.clampRMSJumperCables)
    SpecializationUtil.registerFunction(handToolType, "setRMSJumperCablesState", RMS_JumperCables.setRMSJumperCablesState)
end

---Registers the overwritten functions of the cables
-- @param table handToolType hand tool type
function RMS_JumperCables.registerOverwrittenFunctions(handToolType)
    SpecializationUtil.registerOverwrittenFunction(handToolType, "attachToolToHand", RMS_JumperCables.attachToolToHand)
    SpecializationUtil.registerOverwrittenFunction(handToolType, "attachToolToCamera", RMS_JumperCables.putLeftPairBackFirst)
    SpecializationUtil.registerOverwrittenFunction(handToolType, "detachTool", RMS_JumperCables.putLeftPairBackFirst)
end

---Registers the event listeners of the cables
-- @param table handToolType hand tool type
function RMS_JumperCables.registerEventListeners(handToolType)
    for _, name in ipairs({ "onLoad", "onDelete", "onUpdate", "onWriteStream", "onReadStream", "onHeldStart", "onHandToolHolderChanged",
        "onRegisterActionEvents" }) do
        SpecializationUtil.registerEventListener(handToolType, name, RMS_JumperCables)
    end
end

---Called on loading
-- @param table xmlFile file of the hand tool
-- @param string baseDirectory directory of the hand tool
function RMS_JumperCables:onLoad(xmlFile, baseDirectory)
    local spec = self[specName]
    ---Returns a node of the cables by its mapping
    -- @param string name i3d mapping
    -- @return entityId? node node
    local function node(name)
        return I3DUtil.indexToObject(self.components, name, self.i3dMappings)
    end
    spec.raycastNode = node("raycastNode")
    spec.heldGraphics, spec.storedGraphics = node("heldGraphics"), node("storedGraphics")
    spec.leftPair, spec.rightPair, spec.leftHandNode = node("leftPair"), node("rightPair"), node("leftHandNode")
    spec.leftPairParent = getParent(spec.leftPair)
    spec.leftPairTranslation = { getTranslation(spec.leftPair) }
    spec.leftPairRotation = { getRotation(spec.leftPair) }
    spec.machineA, spec.machineB = nil, nil
    spec.pendingIds = {}
    showClamps(spec)

    if self.isClient then
        local soundsFile = loadXMLFile("rmsJumperCablesSounds", modDirectory .. "sounds/rms_sounds.xml")
        spec.connectSample = g_soundManager:loadSampleFromXML(soundsFile, "sounds", "jumperCablesConnectTool", modDirectory, self.components,
            1, AudioGroup.VEHICLE, self.i3dMappings, self)
        spec.disconnectSample = g_soundManager:loadSampleFromXML(soundsFile, "sounds", "jumperCablesDisconnectTool", modDirectory,
            self.components, 1, AudioGroup.VEHICLE, self.i3dMappings, self)
        delete(soundsFile)
    end
end

---Called on deleting, unlinking the machines
function RMS_JumperCables:onDelete()
    local spec = self[specName]
    putLeftPairBack(spec)
    if self.isServer then
        unclamp(self)
    end
    if self.isClient then
        g_soundManager:deleteSample(spec.connectSample)
        g_soundManager:deleteSample(spec.disconnectSample)
    end
end

---Called on server side on join
-- @param integer streamId stream id
-- @param Connection connection connection
function RMS_JumperCables:onWriteStream(streamId, connection)
    local spec = self[specName]
    for _, machine in ipairs({ spec.machineA or false, spec.machineB or false }) do
        if streamWriteBool(streamId, machine ~= false) then
            NetworkUtil.writeNodeObject(streamId, machine)
        end
    end
end

---Called on client side on join
-- @param integer streamId stream id
-- @param Connection connection connection
function RMS_JumperCables:onReadStream(streamId, connection)
    local spec = self[specName]
    -- the machines may join after the cables: kept as ids until they exist
    spec.pendingIds.A = streamReadBool(streamId) and NetworkUtil.readNodeObjectId(streamId) or nil
    spec.pendingIds.B = streamReadBool(streamId) and NetworkUtil.readNodeObjectId(streamId) or nil
    if next(spec.pendingIds) ~= nil then
        self:raiseActive()
    end
end

---Holds the left clamp pair in the left hand of the character
-- @param function superFunc original function
-- @return boolean isAttached true once attached
function RMS_JumperCables:attachToolToHand(superFunc)
    local spec = self[specName]
    putLeftPairBack(spec)
    local isAttached = superFunc(self)
    local leftHand = self:getCarryingPlayer().graphicsComponent.model.thirdPersonLeftHandNode
    if isAttached and leftHand ~= nil then
        HandToolUtil.linkAndTransformRelativeToParent(spec.leftPair, spec.leftHandNode, leftHand)
    end
    return isAttached
end

---Gives the left clamp pair back before the game moves the cables
-- @param function superFunc original function
-- @return any result what the game's function returns
function RMS_JumperCables:putLeftPairBackFirst(superFunc)
    putLeftPairBack(self[specName])
    return superFunc(self)
end

---Shows the stored or held cables, unclamping them once stored
-- @param table? holder new holder
-- @param table? lastHolder previous holder
function RMS_JumperCables:onHandToolHolderChanged(holder, lastHolder)
    local spec = self[specName]
    local isStored = holder ~= nil and holder:isa(HandToolHolder)
    setVisibility(spec.heldGraphics, not isStored)
    setVisibility(spec.storedGraphics, isStored)

    if isStored and self.isServer and (spec.machineA ~= nil or spec.machineB ~= nil) then
        unclamp(self)
        tell(self, "jumperDisconnected", nil)
    end
end

---Warns the carrier when both machines are already clamped
function RMS_JumperCables:onHeldStart()
    local spec = self[specName]
    if getIsLocallyCarried(self) and spec.machineA ~= nil and spec.machineB ~= nil then
        warn("rms_jumper_cables_both_already_connected", spec.machineA:getFullName(), spec.machineB:getFullName())
    end
end

---Registers the key clamping a machine
function RMS_JumperCables:onRegisterActionEvents()
    if not self:getIsActiveForInput(true) then
        return
    end

    local spec = self[specName]
    local _, eventId = self:addActionEvent(InputAction.ACTIVATE_HANDTOOL, self, RMS_JumperCables.onAction, false, true, false, true, nil)
    g_inputBinding:setActionEventTextPriority(eventId, GS_PRIO_VERY_HIGH)
    g_inputBinding:setActionEventText(eventId, g_i18n:getText("rms_jumper_cables_action"))
    spec.actionEventId = eventId
end

---Clamps or unclamps the machine the cables point at
-- @param string actionName input action
-- @param float inputValue input value
function RMS_JumperCables:onAction(actionName, inputValue)
    local machine = RMS_Utils.raycastMachine(self[specName].raycastNode)
    if machine == nil then
        return
    end
    if self.isServer then
        self:clampRMSJumperCables(machine)
    else
        RMS_JumperCablesEvent.sendRequest(self, machine)
    end
end

---Clamps a machine on the server: the first one, then a second fit to it
-- @param table? machine machine aimed at
function RMS_JumperCables:clampRMSJumperCables(machine)
    local spec = self[specName]
    local state
    if machine == nil then
        state = "jumperInvalid"
    elseif machine == spec.machineA or machine == spec.machineB then
        local clamped = spec.machineA or spec.machineB
        clamped:clearExternalPowerConnection(clamped == spec.machineA and spec.machineB or spec.machineA)
        if machine == spec.machineA then
            spec.machineA = nil
        else
            spec.machineB = nil
        end
        state = "jumperDisconnected"
    elseif spec.machineA == nil and spec.machineB == nil then
        spec.machineA = machine
        state = "jumperSelected"
    elseif spec.machineA ~= nil and spec.machineB ~= nil then
        state = "jumperFull"
    else
        local first = spec.machineA or spec.machineB
        local isFit, reason = RMS_Electrical.isValidPowerPair(first, machine)
        if not isFit then
            state = RMS_JumperCables.REFUSALS[reason] or "jumperInvalid"
        elseif first:establishExternalPowerConnection(machine) then
            if spec.machineA == nil then
                spec.machineA = machine
            else
                spec.machineB = machine
            end
            state = "jumperConnected"
        else
            state = "jumperInvalid"
        end
    end
    tell(self, state, machine)
end

---Shows and plays a state of the cables, told to their carrier
-- @param string state change of the cables
-- @param table? target machine clamped or unclamped
-- @param table? machineA machine on the left pair of clamps
-- @param table? machineB machine on the right pair of clamps
function RMS_JumperCables:setRMSJumperCablesState(state, target, machineA, machineB)
    local spec = self[specName]
    spec.machineA, spec.machineB = machineA, machineB
    showClamps(spec)

    if state == "jumperSelected" or state == "jumperConnected" then
        RMS_SoundManager.playSample(spec.connectSample)
    elseif state == "jumperDisconnected" or state == "jumperAutoDisconnected" then
        RMS_SoundManager.playSample(spec.disconnectSample)
    end
    if not getIsLocallyCarried(self) then
        return
    end

    if (state == "jumperSelected" or state == "jumperConnected") and target ~= nil then
        warn("rms_jumper_cables_connected", target:getFullName())
    elseif state == "jumperDisconnected" and target ~= nil then
        warn("rms_jumper_cables_disconnected", target:getFullName())
    elseif state == "jumperAutoDisconnected" then
        warn("rms_jumper_cables_auto_disconnected")
    elseif state == "jumperTooFar" then
        warn("rms_jumper_cables_is_too_far", target:getFullName(), (machineA or machineB):getFullName())
    elseif state == "jumperFull" then
        warn("rms_jumper_cables_both_already_connected", machineA:getFullName(), machineB:getFullName())
    elseif state == "jumperElectricDonor" then
        warn("rms_jumper_cables_electric_donor")
    elseif state == "jumperVoltage" then
        warn("rms_jumper_cables_voltage_mismatch")
    elseif state == "jumperInvalid" then
        warn("rms_jumper_cables_impossible_to_connect")
    end
end

---Names the action after the machine aimed at, drops a broken link
-- @param float dt time since the last frame (ms)
function RMS_JumperCables:onUpdate(dt)
    local spec = self[specName]
    for side, objectId in pairs(spec.pendingIds) do
        local machine = NetworkUtil.getObject(objectId)
        if machine ~= nil then
            spec["machine" .. side] = machine
            spec.pendingIds[side] = nil
            showClamps(spec)
        else
            self:raiseActive()
        end
    end

    if getIsLocallyCarried(self) and spec.actionEventId ~= nil then
        local machine = RMS_Utils.raycastMachine(spec.raycastNode)
        local textKey = machine == nil and "rms_jumper_cables_action"
            or (machine == spec.machineA or machine == spec.machineB) and "rms_jumper_cables_disconnect" or "rms_jumper_cables_connect"
        g_inputBinding:setActionEventText(spec.actionEventId, g_i18n:getText(textKey))
    end

    if self.isServer and spec.machineA ~= nil and spec.machineB ~= nil and not getAreLinked(spec.machineA, spec.machineB) then
        spec.machineA, spec.machineB = nil, nil
        tell(self, "jumperAutoDisconnected", nil)
    end
end
