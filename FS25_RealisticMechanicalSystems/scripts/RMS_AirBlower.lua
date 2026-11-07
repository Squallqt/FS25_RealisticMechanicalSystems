-- Copyright © 2026 Squallqt. All rights reserved.

---Air blower clearing the dust of a radiator and an air filter
RMS_AirBlower = {}

local specName = "spec_" .. g_currentModName .. ".rmsAirBlower"
local modDirectory = g_currentModDirectory

RMS_AirBlower.WARNING_DURATION = 2200
RMS_AirBlower.DISTANCE_STEP = 0.05
RMS_AirBlower.MIN_DUST_DISTANCE = 0.1

local function getIsLocallyCarried(blower)
    local player = blower:getCarryingPlayer()
    return player ~= nil and player.isOwner
end

local function getAnswerKey(machineSpec)
    if not machineSpec.isVehicleNeedBlowOut then
        return "rms_air_blower_cleaning_not_require"
    elseif machineSpec.radiatorClogging > 0 or RMS_Consumables.getAirFilterLooseDust(machineSpec) > 0 then
        return nil
    elseif RMS_Consumables.getIsAirFilterWornOut(machineSpec) then
        return "rms_air_blower_filter_requires_maintenance"
    end
    return "rms_air_blower_already_clean"
end

local function showAnswer(machine, textKey)
    local hours = textKey == "rms_air_blower_filter_requires_maintenance" and RMS_Utils.formatAirFilterServiceHours(machine) or nil
    g_currentMission:showBlinkingWarning(string.format(g_i18n:getText(textKey), machine:getFullName(), hours), RMS_AirBlower.WARNING_DURATION)
end

local function placeDust(spec, distance)
    local reach = math.max(distance, RMS_AirBlower.MIN_DUST_DISTANCE)
    setTranslation(spec.dustRoot, spec.dustBase[1] + spec.dustDirection[1] * reach, spec.dustBase[2] + spec.dustDirection[2] * reach,
        spec.dustBase[3] + spec.dustDirection[3] * reach)
end

local function stopDust(spec)
    if spec.dust ~= nil then
        ParticleUtil.setEmittingState(spec.dust, false)
        setTranslation(spec.dustRoot, unpack(spec.dustBase))
    end
end

local function stopSounds(spec)
    RMS_SoundManager.setSamplePlaying(spec.blowSample, false)
    RMS_SoundManager.setSamplePlaying(spec.resistanceSample, false)
end

local function share(blower, isBlowing, target, distance)
    local spec = blower[specName]
    if isBlowing == spec.sentBlowing and target == spec.sentTarget
        and math.abs(distance - spec.sentDistance) < RMS_AirBlower.DISTANCE_STEP then
        return
    end
    spec.sentBlowing, spec.sentTarget, spec.sentDistance = isBlowing, target, distance
    RMS_AirBlowerEvent.send(blower, isBlowing, target, distance)
end

function RMS_AirBlower.prerequisitesPresent(specializations)
    return true
end

function RMS_AirBlower.registerFunctions(handToolType)
    SpecializationUtil.registerFunction(handToolType, "setRMSAirBlowerState", RMS_AirBlower.setRMSAirBlowerState)
end

function RMS_AirBlower.registerEventListeners(handToolType)
    for _, name in ipairs({ "onLoad", "onDelete", "onUpdate", "onWriteStream", "onReadStream", "onHeldStart", "onHeldEnd",
        "onRegisterActionEvents" }) do
        SpecializationUtil.registerEventListener(handToolType, name, RMS_AirBlower)
    end
end

function RMS_AirBlower:onLoad(xmlFile, baseDirectory)
    local spec = self[specName]
    spec.raycastNode = I3DUtil.indexToObject(self.components, "raycastNode", self.i3dMappings)
    spec.isActionDown = false
    spec.isBlowing, spec.target, spec.distance = false, nil, 0
    spec.sentBlowing, spec.sentTarget, spec.sentDistance = false, nil, 0

    if self.isClient then
        local soundsFile = loadXMLFile("rmsAirBlowerSounds", modDirectory .. "sounds/rms_sounds.xml")
        spec.blowSample = g_soundManager:loadSampleFromXML(soundsFile, "sounds", "airBlowerTool", modDirectory, self.components, 0,
            AudioGroup.VEHICLE, self.i3dMappings, self)
        spec.resistanceSample = g_soundManager:loadSampleFromXML(soundsFile, "sounds", "airBlowerAirResistanceTool", modDirectory,
            self.components, 0, AudioGroup.VEHICLE, self.i3dMappings, self)
        delete(soundsFile)

        local emitter = I3DUtil.indexToObject(self.components, "dustEmitterNode", self.i3dMappings)
        spec.dustRoot = getParent(emitter)
        spec.dustBase = { getTranslation(spec.dustRoot) }
        spec.dustDirection = { localDirectionToLocal(spec.dustRoot, getParent(spec.dustRoot), 0, 0, -1) }
        -- the game's wheel dust, thrown at the machine in reach
        spec.dust = ParticleUtil.copyParticleSystem(nil, nil, g_particleSystemManager:getParticleSystem("wheel_dust"), emitter)
        stopDust(spec)
    end
end

function RMS_AirBlower:onDelete()
    local spec = self[specName]
    if self.isClient then
        g_soundManager:deleteSample(spec.blowSample)
        g_soundManager:deleteSample(spec.resistanceSample)
        ParticleUtil.deleteParticleSystem(spec.dust)
    end
end

function RMS_AirBlower:onWriteStream(streamId, connection)
    local spec = self[specName]
    streamWriteBool(streamId, spec.isBlowing)
    NetworkUtil.writeNodeObject(streamId, spec.target)
    streamWriteFloat32(streamId, spec.distance)
end

function RMS_AirBlower:onReadStream(streamId, connection)
    local isBlowing = streamReadBool(streamId)
    local target = NetworkUtil.readNodeObject(streamId)
    self:setRMSAirBlowerState(isBlowing, target, streamReadFloat32(streamId))
end

---Keeps whether a player blows with the blower and at which machine
function RMS_AirBlower:setRMSAirBlowerState(isBlowing, target, distance)
    local spec = self[specName]
    spec.isBlowing = isBlowing
    spec.target = target ~= nil and target:getRootVehicle() or nil
    spec.distance = distance
end

function RMS_AirBlower:onRegisterActionEvents()
    if not self:getIsActiveForInput(true) then
        return
    end

    local _, eventId = self:addActionEvent(InputAction.ACTIVATE_HANDTOOL, self, RMS_AirBlower.onAction, true, true, false, true, nil)
    g_inputBinding:setActionEventTextPriority(eventId, GS_PRIO_VERY_HIGH)
    g_inputBinding:setActionEventText(eventId, g_i18n:getText("rms_air_blower_action_short"))
end

---Blows while the key is held, saying so when no machine is in reach
function RMS_AirBlower:onAction(actionName, inputValue)
    local spec = self[specName]
    spec.isActionDown = inputValue > 0
    if not spec.isActionDown then
        share(self, false, nil, 0)
        return
    end

    share(self, true, nil, 0)
    if RMS_Utils.raycastMachine(spec.raycastNode) == nil then
        g_currentMission:showBlinkingWarning(g_i18n:getText("rms_air_blower_no_vehicle"), RMS_AirBlower.WARNING_DURATION)
    end
end

function RMS_AirBlower:onHeldStart()
    local spec = self[specName]
    spec.isActionDown = false
    spec.answer = nil
end

function RMS_AirBlower:onHeldEnd()
    local spec = self[specName]
    if getIsLocallyCarried(self) then
        share(self, false, nil, 0)
    end
    spec.isActionDown = false
    stopSounds(spec)
    stopDust(spec)
end

---Blows the dust out of the machine in reach, for every player
function RMS_AirBlower:onUpdate(dt)
    local spec = self[specName]
    local isLocal = getIsLocallyCarried(self)
    local isBlowing = isLocal and spec.isActionDown or not isLocal and spec.isBlowing
    if not isBlowing then
        spec.answer = nil
        stopSounds(spec)
        stopDust(spec)
        return
    end

    local machine, distance = spec.target, spec.distance
    if isLocal then
        machine, distance = RMS_Utils.raycastMachine(spec.raycastNode)
        share(self, true, machine, distance or 0)
    end
    RMS_SoundManager.setSamplePlaying(spec.blowSample, true)
    RMS_SoundManager.setSamplePlaying(spec.resistanceSample, machine ~= nil)
    if machine == nil then
        spec.answer = nil
        stopDust(spec)
        return
    end

    local machineSpec = machine.spec_RealisticMechanicalSystems
    local textKey = getAnswerKey(machineSpec)
    local answer = textKey ~= nil and { machine, textKey } or nil
    if isLocal and answer ~= nil and (spec.answer == nil or spec.answer[1] ~= machine or spec.answer[2] ~= textKey) then
        showAnswer(machine, textKey)
    end
    spec.answer = answer

    if self.isServer and machineSpec.isVehicleNeedBlowOut then
        machine:cleanRadiatorAndAirFilter(dt)
    end

    if self.isClient then
        local clogging = machineSpec.airFilterClogging + machineSpec.radiatorClogging
        if RMS_Consumables.getAirFilterLooseDust(machineSpec) > 0 or machineSpec.radiatorClogging > 0 then
            placeDust(spec, distance)
            ParticleUtil.setEmitCountScale(spec.dust, math.max(clogging / 20, 0.01))
            ParticleUtil.setParticleLifespan(spec.dust, math.clamp(clogging * 1200, 600, 1200))
            ParticleUtil.setEmittingState(spec.dust, true)
        else
            stopDust(spec)
        end
    end
end
