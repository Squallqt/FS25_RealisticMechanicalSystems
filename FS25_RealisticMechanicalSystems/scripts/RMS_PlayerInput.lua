-- Copyright © 2026 Squallqt. All rights reserved.

---Field inspection held on foot, battery isolator of the machine faced
RMS_PlayerInput = {}

RMS_PlayerInput.HOLD_TIME = 600
RMS_PlayerInput.CANCEL_MESSAGE_TIME = 1500
RMS_PlayerInput.WARNING_DURATION = 2000

local state = { machine = nil, inspected = nil, held = nil, heldTime = 0, isHoldDone = false, isKeyConsumed = false }
local inspectionEventId, isolatorEventId

local function getIsFreeOnFoot(player)
    return player.isControlled and not player:getIsInVehicle() and not player:getAreHandsHoldingObject() and not player:getIsHoldingHandTool()
end

local function getFacedMachine(player)
    local node = player.targeter:getClosestTargetedNodeFromType(PlayerInputComponent)
    local machine = node ~= nil and g_currentMission:getNodeObject(node) or nil
    local spec = machine ~= nil and machine.spec_RealisticMechanicalSystems or nil
    if spec == nil or spec.isExcludedVehicle or not g_currentMission.accessHandler:canPlayerAccess(machine, player) then
        return nil
    end
    return machine
end

local function forgetHold()
    state.held, state.heldTime, state.isHoldDone = nil, 0, false
end

local function endInspection(isComplete, reasonKey)
    local machine = state.inspected
    local inspection = machine.spec_RealisticMechanicalSystems.fieldInspection
    state.inspected = nil
    RMS_FieldInspectionEvent.send(machine, false)
    inspection.isActive = false
    inspection.elapsedTime = isComplete and inspection.duration or 0
    RMS_Hud.showInspectionProgress(nil)
    if isComplete then
        RMS_InspectionDialog.show(machine)
    elseif reasonKey ~= nil then
        RMS_Hud.showInspectionMessage(g_i18n:getText(reasonKey), RMS_PlayerInput.CANCEL_MESSAGE_TIME)
    end
end

local function followInspection(player, dt)
    local machine = state.inspected
    local inspection = machine.spec_RealisticMechanicalSystems.fieldInspection
    if not inspection.isActive or not player.isControlled then
        endInspection(false)
    elseif not getIsFreeOnFoot(player) or getFacedMachine(player) ~= machine then
        endInspection(false, "rms_field_inspection_cancelled")
    else
        inspection.elapsedTime = math.min(inspection.elapsedTime + dt, inspection.duration)
        RMS_Hud.showInspectionProgress(inspection.elapsedTime / math.max(inspection.duration, 1))
        if inspection.elapsedTime >= inspection.duration then
            endInspection(true)
        end
    end
end

-- a short press is the game's activate, a long one the inspection
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

local function onIsolatorInput()
    local machine = state.machine
    if machine == nil or not RMS_Electrical.getHasBatteryIsolator(machine) then
        return
    end

    local refusal = RMS_Electrical.getBatteryIsolatorRefusal(machine)
    if refusal ~= nil then
        g_currentMission:showBlinkingWarning(g_i18n:getText(refusal), RMS_PlayerInput.WARNING_DURATION)
    else
        RMS_BatteryIsolatorEvent.send(machine, not machine.spec_RealisticMechanicalSystems.batteryIsolated)
    end
end

local function showIsolatorAction(machine)
    local hasIsolator = machine ~= nil and RMS_Electrical.getHasBatteryIsolator(machine)
    g_inputBinding:setActionEventActive(isolatorEventId, hasIsolator)
    if hasIsolator then
        g_inputBinding:setActionEventText(isolatorEventId,
            g_i18n:getText(machine.spec_RealisticMechanicalSystems.batteryIsolated and "rms_battery_isolator_restore" or "rms_battery_isolator_cut"))
    end
end

local function update(inputComponent, superFunc, dt)
    superFunc(inputComponent, dt)

    local player = inputComponent.player
    if not player.isOwner or g_inputBinding:getContextName() ~= PlayerInputComponent.INPUT_CONTEXT_NAME or inspectionEventId == nil then
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

local function registerActionEvents(inputComponent)
    if not inputComponent.player.isOwner then
        return
    end

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

local function drawHands(hands, superFunc, ...)
    if state.inspected == nil then
        return superFunc(hands, ...)
    end
end

PlayerInputComponent.update = Utils.overwrittenFunction(PlayerInputComponent.update, update)
PlayerInputComponent.registerActionEvents = Utils.appendedFunction(PlayerInputComponent.registerActionEvents, registerActionEvents)
HandToolHands.onDraw = Utils.overwrittenFunction(HandToolHands.onDraw, drawHands)
