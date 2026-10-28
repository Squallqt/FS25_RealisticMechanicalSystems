-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---On foot field inspection and battery isolator actions

local rmsInspectionVehicle = nil
local rmsInspectionActionId = nil
local rmsBatteryIsolatorActionId = nil
local rmsInspectionHoldVehicle = nil
local rmsInspectionHoldTime = 0
local rmsInspectionHoldThreshold = 600
local rmsInspectionHoldTriggered = false
local rmsInspectionConsumeUntilRelease = false

local rmsActiveInspectionVehicle = nil
local rmsInspectionMaxDistance = 6.0


---Clears the hold timer of the inspection action
local function rmsResetInspectionHoldState()
    rmsInspectionHoldVehicle = nil
    rmsInspectionHoldTime = 0
    rmsInspectionHoldTriggered = false
end

---Runs the native interaction after a short press of the inspection key
local function rmsActivateCurrentObject()
    local system = g_currentMission.activatableObjectsSystem
    if system == nil then
        return
    end

    if system.onActivateObjectInput ~= nil then
        system:onActivateObjectInput(InputAction.ACTIVATE_OBJECT, 1, nil, false)
        return
    end

    local activatable = nil
    if system.getActivatable ~= nil then
        activatable = system:getActivatable()
    else
        activatable = system.currentActivatableObject
    end

    if activatable ~= nil
        and activatable.run ~= nil
        and (activatable.getIsActivatable == nil or activatable:getIsActivatable()) then
        activatable:run()
    end
end

---Returns the tracked vehicle the player looks at and may access
local function rmsGetInspectionVehicleFromTargeter(player)
    local object = nil

    if player.targeter ~= nil then
        local node = player.targeter:getClosestTargetedNodeFromType(PlayerInputComponent)

        if node ~= nil then
            object = g_currentMission:getNodeObject(node)
        end
    end

    if object == nil then
        return nil
    end

    local spec = object.spec_RealisticMechanicalSystems
    if spec == nil or spec.isExcludedVehicle then
        return nil
    end

    if not g_currentMission.accessHandler:canPlayerAccess(object, player) then
        return nil
    end

    return object
end

---Stops the running inspection and tells the player why
local function rmsCancelActiveInspection(reasonText)
    local vehicle = rmsActiveInspectionVehicle
    if vehicle ~= nil and vehicle.spec_RealisticMechanicalSystems ~= nil then
        local spec = vehicle.spec_RealisticMechanicalSystems
        local inspection = spec.fieldInspection
        RMS_FieldInspectionEvent.send(vehicle, false)

        if inspection ~= nil then
            inspection.isActive = false
            inspection.elapsedTime = 0
        end
    end

    rmsActiveInspectionVehicle = nil
    RMS_Hud.showInspectionProgress(nil)

    if reasonText ~= nil and reasonText ~= "" then
        RMS_Hud.showInspectionMessage(reasonText, 1500)
    end
end

---Ends the inspection and opens the inspection dialog
local function rmsCompleteActiveInspection()
    local vehicle = rmsActiveInspectionVehicle
    if vehicle == nil or vehicle.spec_RealisticMechanicalSystems == nil then
        rmsCancelActiveInspection()
        return
    end

    local spec = vehicle.spec_RealisticMechanicalSystems
    local inspection = spec.fieldInspection
    RMS_FieldInspectionEvent.send(vehicle, false)

    if inspection ~= nil then
        inspection.isActive = false
        inspection.elapsedTime = inspection.duration
    end

    rmsActiveInspectionVehicle = nil
    RMS_Hud.showInspectionProgress(nil)

    RMS_InspectionDialog.show(vehicle)
end

---Advances the inspection, cancelling it when the player looks away or moves
local function rmsUpdateActiveInspection(inputComponent, dt)
    local vehicle = rmsActiveInspectionVehicle
    if vehicle == nil or vehicle.spec_RealisticMechanicalSystems == nil then
        return
    end

    local spec = vehicle.spec_RealisticMechanicalSystems
    local inspection = spec.fieldInspection
    local player = inputComponent.player

    if inspection == nil or not inspection.isActive then
        rmsCancelActiveInspection()
        return
    end

    if player == nil or not player.isControlled then
        rmsCancelActiveInspection()
        return
    end

    if player:getIsInVehicle() or player:getAreHandsHoldingObject() or player:getIsHoldingHandTool() then
        rmsCancelActiveInspection(g_i18n:getText("rms_field_inspection_cancelled"))
        return
    end

    local currentTargetVehicle = rmsGetInspectionVehicleFromTargeter(player)
    if currentTargetVehicle ~= vehicle then
        rmsCancelActiveInspection(g_i18n:getText("rms_field_inspection_cancelled"))
        return
    end

    if player.rootNode == nil then
        rmsCancelActiveInspection(g_i18n:getText("rms_field_inspection_cancelled"))
        return
    end

    local distance = vehicle:getDistanceToNode(player.rootNode)
    if distance == nil or distance > rmsInspectionMaxDistance then
        rmsCancelActiveInspection(g_i18n:getText("rms_field_inspection_cancelled"))
        return
    end

    inspection.elapsedTime = math.min(inspection.elapsedTime + dt, inspection.duration)

    RMS_Hud.showInspectionProgress(inspection.elapsedTime / math.max(inspection.duration, 1))

    if inspection.elapsedTime >= inspection.duration then
        rmsCompleteActiveInspection()
    end
end

---Starts the inspection on hold, a short press going to the native action
local function rmsOnInputFieldInspection(inputComponent, actionName, inputValue, callbackState, isAnalog)
    if inputValue == 0 then
        local activateObject = not rmsInspectionConsumeUntilRelease
            and rmsInspectionHoldVehicle ~= nil
            and not rmsInspectionHoldTriggered

        rmsInspectionConsumeUntilRelease = false
        rmsResetInspectionHoldState()

        if activateObject then
            rmsActivateCurrentObject()
        end

        return
    end

    if rmsActiveInspectionVehicle ~= nil then
        return
    end

    if rmsInspectionVehicle == nil then
        rmsResetInspectionHoldState()
        return
    end

    if rmsInspectionHoldVehicle ~= rmsInspectionVehicle then
        rmsInspectionHoldVehicle = rmsInspectionVehicle
        rmsInspectionHoldTime = 0
        rmsInspectionHoldTriggered = false
    end

    if rmsInspectionHoldTriggered then
        return
    end

    rmsInspectionHoldTime = rmsInspectionHoldTime + g_currentDt

    if rmsInspectionHoldTime >= rmsInspectionHoldThreshold then
        rmsInspectionHoldTriggered = true
        rmsInspectionConsumeUntilRelease = true

        if rmsInspectionHoldVehicle ~= nil and rmsInspectionHoldVehicle.startFieldVisualInspectionProcess ~= nil then
            local started = rmsInspectionHoldVehicle:startFieldVisualInspectionProcess()

            if started then
                rmsActiveInspectionVehicle = rmsInspectionHoldVehicle
            end
        end
    end
end

---Opens or closes the battery isolator of the machine in front of the player
local function rmsOnInputBatteryIsolator()
    local vehicle = rmsInspectionVehicle
    if vehicle == nil or not RMS_Electrical.getHasBatteryIsolator(vehicle) then
        return
    end

    local refusal = RMS_Electrical.getBatteryIsolatorRefusal(vehicle)
    if refusal ~= nil then
        g_currentMission:showBlinkingWarning(g_i18n:getText(refusal), 2000)
        return
    end

    RMS_BatteryIsolatorEvent.send(vehicle, not vehicle.spec_RealisticMechanicalSystems.batteryIsolated)
end

---Offers the battery isolator action, named after what it will do
local function rmsUpdateBatteryIsolatorAction(vehicle)
    if rmsBatteryIsolatorActionId == nil then
        return
    end

    local hasIsolator = vehicle ~= nil and RMS_Electrical.getHasBatteryIsolator(vehicle)
    g_inputBinding:setActionEventActive(rmsBatteryIsolatorActionId, hasIsolator)

    if hasIsolator then
        local isIsolated = vehicle.spec_RealisticMechanicalSystems.batteryIsolated
        g_inputBinding:setActionEventText(rmsBatteryIsolatorActionId,
            g_i18n:getText(isIsolated and "rms_battery_isolator_restore" or "rms_battery_isolator_cut"))
    end
end

---Offers the inspection action while the player looks at a tracked vehicle
local function rmsOnPlayerInputComponentUpdate(inputComponent, superFunc, dt)
    superFunc(inputComponent, dt)

    if not inputComponent.player.isOwner
        or g_inputBinding:getContextName() ~= PlayerInputComponent.INPUT_CONTEXT_NAME
        or rmsInspectionActionId == nil then
        return
    end

    if rmsActiveInspectionVehicle ~= nil then
        g_inputBinding:setActionEventActive(rmsInspectionActionId, true)
        rmsUpdateBatteryIsolatorAction(nil)
        rmsUpdateActiveInspection(inputComponent, dt)
        return
    end

    local previousVehicle = rmsInspectionVehicle
    rmsInspectionVehicle = nil

    local player = inputComponent.player
    if player.isControlled
        and not player:getIsInVehicle()
        and not player:getAreHandsHoldingObject()
        and not player:getIsHoldingHandTool() then
        rmsInspectionVehicle = rmsGetInspectionVehicleFromTargeter(player)
    end

    if rmsInspectionVehicle ~= previousVehicle then
        rmsResetInspectionHoldState()
    end

    rmsUpdateBatteryIsolatorAction(rmsInspectionVehicle)

    local isActive = rmsInspectionVehicle ~= nil or rmsInspectionConsumeUntilRelease
    g_inputBinding:setActionEventActive(rmsInspectionActionId, isActive)

    if isActive then
        g_inputBinding:setActionEventText(rmsInspectionActionId, g_i18n:getText("rms_field_inspection_hold_to_start"))
    else
        rmsResetInspectionHoldState()
    end
end

---Registers the field inspection and battery isolator actions
local function rmsOnPlayerInputComponentRegisterActionEvents(inputComponent)
    if not inputComponent.player.isOwner then
        return
    end

    g_inputBinding:beginActionEventsModification(PlayerInputComponent.INPUT_CONTEXT_NAME)

    local _, eventId = g_inputBinding:registerActionEvent(
        InputAction.RMS_FIELD_INSPECTION,
        inputComponent,
        rmsOnInputFieldInspection,
        true,
        true,
        true,
        true,
        nil,
        true
    )

    rmsInspectionActionId = eventId

    if rmsInspectionActionId ~= nil then
        g_inputBinding:setActionEventActive(rmsInspectionActionId, false)
        g_inputBinding:setActionEventTextPriority(rmsInspectionActionId, GS_PRIO_NORMAL)
    end

    _, rmsBatteryIsolatorActionId = g_inputBinding:registerActionEvent(
        InputAction.RMS_TOGGLE_BATTERY_ISOLATOR,
        inputComponent,
        rmsOnInputBatteryIsolator,
        false,
        true,
        false,
        true,
        nil,
        true
    )
    if rmsBatteryIsolatorActionId ~= nil then
        g_inputBinding:setActionEventActive(rmsBatteryIsolatorActionId, false)
        g_inputBinding:setActionEventTextPriority(rmsBatteryIsolatorActionId, GS_PRIO_NORMAL)
    end

    g_inputBinding:endActionEventsModification()
end

---Hides the hand crosshair while an inspection runs
local function rmsOnHandToolHandsDraw(self, superFunc, ...)
    if rmsActiveInspectionVehicle ~= nil then
        return
    end

    return superFunc(self, ...)
end

PlayerInputComponent.update = Utils.overwrittenFunction(PlayerInputComponent.update, rmsOnPlayerInputComponentUpdate)
HandToolHands.onDraw = Utils.overwrittenFunction(HandToolHands.onDraw, rmsOnHandToolHandsDraw)
PlayerInputComponent.registerActionEvents = Utils.appendedFunction(PlayerInputComponent.registerActionEvents, rmsOnPlayerInputComponentRegisterActionEvents)
