-- Copyright © 2026 Squallqt. All rights reserved.

---Field inspection held on foot, battery isolator of the machine faced
RMS_PlayerInput = {}

RMS_PlayerInput.HOLD_TIME = 600
RMS_PlayerInput.CANCEL_MESSAGE_TIME = 1500
RMS_PlayerInput.WARNING_DURATION = 2000

local state = { machine = nil, inspected = nil, held = nil, heldTime = 0, isHoldDone = false, isKeyConsumed = false }
local inspectionEventId, isolatorEventId

---Tells whether the player stands on foot with empty hands
-- @param table player player
-- @return boolean isFree true on foot with empty hands
local function getIsFreeOnFoot(player)
    return player.isControlled and not player:getIsInVehicle() and not player:getAreHandsHoldingObject() and not player:getIsHoldingHandTool()
end

---Returns the tracked machine the player faces and may use, nil without one
-- @param table player player
-- @return table? machine machine faced
local function getFacedMachine(player)
    local node = player.targeter:getClosestTargetedNodeFromType(PlayerInputComponent)
    local machine = node ~= nil and g_currentMission:getNodeObject(node) or nil
    local spec = machine ~= nil and machine.spec_RealisticMechanicalSystems or nil
    if spec == nil or spec.isExcludedVehicle or not g_currentMission.accessHandler:canPlayerAccess(machine, player) then
        return nil
    end
    return machine
end

---Forgets the key held on a machine
local function forgetHold()
    state.held, state.heldTime, state.isHoldDone = nil, 0, false
end

---Ends the inspection on foot, opening its result when it is complete
-- @param boolean isComplete true when the inspection is complete
-- @param string? reasonKey l10n key of the cancel message
local function endInspection(isComplete, reasonKey)
    local machine = state.inspected
    state.inspected = nil
    RMS_FieldInspectionEvent.send(machine, false)
    RMS_Hud.showInspectionProgress(nil)
    if isComplete then
        RMS_InspectionDialog.show(machine)
    elseif reasonKey ~= nil then
        RMS_Hud.showInspectionMessage(g_i18n:getText(reasonKey), RMS_PlayerInput.CANCEL_MESSAGE_TIME)
    end
end

---Runs the inspection on foot while the player stays at the machine
-- @param table player player
-- @param float dt time since the last frame (ms)
local function followInspection(player, dt)
    local machine = state.inspected
    local inspection = machine.spec_RealisticMechanicalSystems.fieldInspection
    if not player.isControlled then
        endInspection(false)
    elseif not getIsFreeOnFoot(player) or getFacedMachine(player) ~= machine then
        endInspection(false, "rms_field_inspection_cancelled")
    else
        inspection.elapsedTime = math.min(inspection.elapsedTime + dt, inspection.duration)
        RMS_Hud.showInspectionProgress(inspection.elapsedTime / inspection.duration)
        if inspection.elapsedTime >= inspection.duration then
            endInspection(true)
        end
    end
end

---A short press is the game's activate, a long one the inspection
-- @param table inputComponent input component of the player
-- @param string actionName input action
-- @param float inputValue input value
local function onInspectionInput(inputComponent, actionName, inputValue)
    if inputValue == 0 then
        local isShortPress = not state.isKeyConsumed and state.held ~= nil and not state.isHoldDone
        state.isKeyConsumed = false
        forgetHold()
        if isShortPress then
            g_currentMission.activatableObjectsSystem:onActivateObjectInput(InputAction.ACTIVATE_OBJECT, 1, nil, false)
        end
        return
    end

    if state.inspected ~= nil then
        return
    elseif state.machine == nil then
        forgetHold()
        return
    elseif state.held ~= state.machine then
        state.held, state.heldTime, state.isHoldDone = state.machine, 0, false
    end
    if state.isHoldDone then
        return
    end

    state.heldTime = state.heldTime + g_currentDt
    if state.heldTime >= RMS_PlayerInput.HOLD_TIME then
        state.isHoldDone, state.isKeyConsumed = true, true
        if state.held:startFieldVisualInspectionProcess() then
            state.inspected = state.held
        end
    end
end

---Opens or closes the battery isolator of the machine faced
local function onIsolatorInput()
    local machine = state.machine
    if not RMS_Electrical.getHasBatteryIsolator(machine) then
        return
    end

    local refusal = RMS_Electrical.getBatteryIsolatorRefusal(machine)
    if refusal ~= nil then
        g_currentMission:showBlinkingWarning(g_i18n:getText(refusal), RMS_PlayerInput.WARNING_DURATION)
    else
        RMS_BatteryIsolatorEvent.send(machine, not machine.spec_RealisticMechanicalSystems.batteryIsolated)
    end
end

---Offers the battery isolator of the machine faced
-- @param table? machine machine faced
local function showIsolatorAction(machine)
    local hasIsolator = machine ~= nil
    g_inputBinding:setActionEventActive(isolatorEventId, hasIsolator)
    if hasIsolator then
        g_inputBinding:setActionEventText(isolatorEventId,
            g_i18n:getText(machine.spec_RealisticMechanicalSystems.batteryIsolated and "rms_battery_isolator_restore" or "rms_battery_isolator_cut"))
    end
end

---Follows the machine faced, the held key and the running inspection
-- @param table inputComponent input component of the player
-- @param function superFunc original function
-- @param float dt time since the last frame (ms)
local function update(inputComponent, superFunc, dt)
    superFunc(inputComponent, dt)

    local player = inputComponent.player
    if g_inputBinding:getContextName() ~= PlayerInputComponent.INPUT_CONTEXT_NAME then
        return
    end

    if state.inspected ~= nil then
        g_inputBinding:setActionEventActive(inspectionEventId, true)
        showIsolatorAction(nil)
        followInspection(player, dt)
        return
    end

    local machine = getIsFreeOnFoot(player) and getFacedMachine(player) or nil
    if machine ~= state.machine then
        forgetHold()
    end
    state.machine = machine
    showIsolatorAction(machine)

    local isActive = machine ~= nil or state.isKeyConsumed
    g_inputBinding:setActionEventActive(inspectionEventId, isActive)
    if isActive then
        g_inputBinding:setActionEventText(inspectionEventId, g_i18n:getText("rms_field_inspection_hold_to_start"))
    else
        forgetHold()
    end
end

---Registers the inspection and the isolator keys of the player on foot
-- @param table inputComponent input component of the player
local function registerActionEvents(inputComponent)
    local _
    g_inputBinding:beginActionEventsModification(PlayerInputComponent.INPUT_CONTEXT_NAME)
    _, inspectionEventId = g_inputBinding:registerActionEvent(InputAction.RMS_FIELD_INSPECTION, inputComponent, onInspectionInput,
        true, true, true, true, nil, true)
    g_inputBinding:setActionEventActive(inspectionEventId, false)
    g_inputBinding:setActionEventTextPriority(inspectionEventId, GS_PRIO_NORMAL)
    _, isolatorEventId = g_inputBinding:registerActionEvent(InputAction.RMS_TOGGLE_BATTERY_ISOLATOR, inputComponent, onIsolatorInput,
        false, true, false, true, nil, true)
    g_inputBinding:setActionEventActive(isolatorEventId, false)
    g_inputBinding:setActionEventTextPriority(isolatorEventId, GS_PRIO_NORMAL)
    g_inputBinding:endActionEventsModification()
end

---Hides the hands of the player during an inspection
-- @param table hands hands of the player
-- @param function superFunc original function
-- @param any ... arguments of the game's draw
-- @return any ... what the game's draw returns
local function drawHands(hands, superFunc, ...)
    if state.inspected == nil then
        return superFunc(hands, ...)
    end
end

PlayerInputComponent.update = Utils.overwrittenFunction(PlayerInputComponent.update, update)
PlayerInputComponent.registerActionEvents = Utils.appendedFunction(PlayerInputComponent.registerActionEvents, registerActionEvents)
HandToolHands.onDraw = Utils.overwrittenFunction(HandToolHands.onDraw, drawHands)
