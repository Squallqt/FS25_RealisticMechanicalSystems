-- Copyright © 2026 Squallqt. All rights reserved.

---Fluid transfer from a container to a machine, run and checked on the server
RMS_FluidTransfer = {}

RMS_FluidTransfer.MAX_DISTANCE = 4
RMS_FluidTransfer.STOPPED_SPEED = 0.5
RMS_FluidTransfer.LITERS_PER_SECOND = { medium = 0.2, large = 0.3, adBlueCan = 0.3, drum = 1, tank = 1 }
RMS_FluidTransfer.HOSE_LENGTH = 4

RMS_FluidTransfer.RESULT = {
    OK = "OK",
    INVALID = "INVALID",
    NO_ACCESS = "NO_ACCESS",
    OUT_OF_RANGE = "OUT_OF_RANGE",
    MOTOR_RUNNING = "MOTOR_RUNNING",
    VEHICLE_MOVING = "VEHICLE_MOVING",
    SERVICE_BUSY = "SERVICE_BUSY",
    CIRCUIT_FULL = "CIRCUIT_FULL",
    WRONG_FLUID_CONFIRMATION_REQUIRED = "WRONG_FLUID_CONFIRMATION_REQUIRED",
    BUSY = "BUSY",
    CONTAINER_EMPTY = "CONTAINER_EMPTY"
}

---Returns how far a node stands from the body of a machine, on the ground
-- @param table vehicle machine
-- @param entityId node node
-- @return float distance distance (m)
function RMS_FluidTransfer.getDistanceToVehicle(vehicle, node)
    local x, _, z = worldToLocal(vehicle.rootNode, getWorldTranslation(node))
    local size = vehicle.size
    local dx = math.max(math.abs(x - size.widthOffset) - size.width * 0.5, 0)
    local dz = math.max(math.abs(z - size.lengthOffset) - size.length * 0.5, 0)
    return math.sqrt(dx * dx + dz * dz)
end

---Returns the player, user and farm of a network connection
-- @param Connection connection connection
-- @return table? requester userId, farmId and player, nil when one is missing
function RMS_FluidTransfer.getRequesterContext(connection)
    local userId = g_currentMission.userManager:getUserIdByConnection(connection)
    local farm = g_farmManager:getFarmByUserId(userId)
    local player = g_currentMission.playerSystem:getPlayerByUserId(userId)
    if userId == nil or farm == nil or player == nil then
        return nil
    end

    return {
        userId = userId,
        farmId = farm.farmId,
        player = player
    }
end

---Tells whether the requesting farm may use both the container and the machine
-- @param table container fluid container
-- @param table target machine
-- @param table requester requester context
-- @return boolean isOwned true when the farm may use both
local function getIsOwnedByRequester(container, target, requester)
    return g_currentMission.accessHandler:canFarmAccess(requester.farmId, container)
        and g_currentMission.accessHandler:canFarmAccess(requester.farmId, target)
end

---Returns why a pour may not run now, OK when it may
-- @param table container fluid container
-- @param table target machine
-- @param string circuit circuit filled
-- @param table? requester requester context, nil once the player left
-- @param integer index place poured from
-- @return string result RMS_FluidTransfer.RESULT
local function getRuntimeValidation(container, target, circuit, requester, index)
    if requester == nil or target.isDeleted then
        return RMS_FluidTransfer.RESULT.INVALID
    end

    if not getIsOwnedByRequester(container, target, requester) then
        return RMS_FluidTransfer.RESULT.NO_ACCESS
    end

    if container:getRMSFluidCarrier(index) ~= requester.player then
        return RMS_FluidTransfer.RESULT.INVALID
    end

    if RMS_FluidTransfer.getDistanceToVehicle(target, requester.player.rootNode) > RMS_FluidTransfer.MAX_DISTANCE
        or (container:getRMSFluidCapacity() > RMS_FluidContainer.CARRIED_CAPACITY
            and RMS_FluidTransfer.getDistanceToVehicle(target, container.rootNode) > RMS_FluidTransfer.HOSE_LENGTH) then
        return RMS_FluidTransfer.RESULT.OUT_OF_RANGE
    end

    if target:isUnderService() then
        return RMS_FluidTransfer.RESULT.SERVICE_BUSY
    end

    if target:getIsMotorStarted() then
        return RMS_FluidTransfer.RESULT.MOTOR_RUNNING
    end

    if math.abs(target:getLastSpeed()) > RMS_FluidTransfer.STOPPED_SPEED then
        return RMS_FluidTransfer.RESULT.VEHICLE_MOVING
    end

    if RMS_Fluids.getCapacity(target, circuit) <= RMS_Fluids.EPSILON
        or RMS_Fluids.getMissingLiters(target, circuit) <= RMS_Fluids.EPSILON then
        return RMS_FluidTransfer.RESULT.CIRCUIT_FULL
    end

    if container:getRMSFluidLiters(index) <= RMS_Fluids.EPSILON then
        return RMS_FluidTransfer.RESULT.CONTAINER_EMPTY
    end

    return RMS_FluidTransfer.RESULT.OK
end

---Tells whether any place of the container is pouring, on the server
-- @param table container fluid container
-- @return boolean isActive true while a place pours
function RMS_FluidTransfer.getHasActive(container)
    for _, slot in ipairs(container[RMS_FluidContainer.SPEC_TABLE_NAME].slots) do
        if slot.activeTransfer ~= nil then
            return true
        end
    end
    return false
end

local REFUSAL_TEXT_KEYS = {
    [RMS_FluidTransfer.RESULT.MOTOR_RUNNING] = "rms_fluid_error_motor_running",
    [RMS_FluidTransfer.RESULT.VEHICLE_MOVING] = "rms_fluid_error_vehicle_moving",
    [RMS_FluidTransfer.RESULT.SERVICE_BUSY] = "rms_charger_error_service",
    [RMS_FluidTransfer.RESULT.CIRCUIT_FULL] = "rms_fluid_error_no_circuit",
    [RMS_FluidTransfer.RESULT.BUSY] = "rms_fluid_error_busy"
}

---Returns the text telling a player why the server refused the pour
-- @param table container fluid container
-- @param string result RMS_FluidTransfer.RESULT
-- @return string? textKey l10n key, nil when nothing is shown
function RMS_FluidTransfer.getRefusalTextKey(container, result)
    local isDrum = container:getRMSFluidCapacity() > RMS_FluidContainer.CARRIED_CAPACITY
    local isTank = container:getRMSFluidFormat() == "tank"
    if result == RMS_FluidTransfer.RESULT.OUT_OF_RANGE then
        return isTank and "rms_drum_pump_tank_too_far" or isDrum and "rms_drum_pump_machine_too_far" or nil
    elseif result == RMS_FluidTransfer.RESULT.CONTAINER_EMPTY then
        return isTank and "rms_fluid_tank_empty" or isDrum and "rms_fluid_drum_empty" or "rms_fluid_container_empty"
    end
    return REFUSAL_TEXT_KEYS[result]
end

---Starts one locked manual transfer after all authoritative checks
-- @param table container fluid container
-- @param table target machine
-- @param string circuit circuit filled
-- @param table requester requester context
-- @param boolean incompatibleConfirmed true once the player accepted an incompatible fluid
-- @param integer index place poured from
-- @return boolean isStarted true once started
-- @return string result RMS_FluidTransfer.RESULT
function RMS_FluidTransfer.tryStart(container, target, circuit, requester, incompatibleConfirmed, index)
    local result = getRuntimeValidation(container, target, circuit, requester, index)
    if result ~= RMS_FluidTransfer.RESULT.OK then
        return false, result
    end

    local containerSpec = container[RMS_FluidContainer.SPEC_TABLE_NAME]
    local slot = containerSpec.slots[index]
    if slot.activeTransfer ~= nil then
        return false, RMS_FluidTransfer.RESULT.BUSY
    end

    local targetSpec = target.spec_RealisticMechanicalSystems
    targetSpec.fluidTransferLocks = targetSpec.fluidTransferLocks or {}
    local currentLock = targetSpec.fluidTransferLocks[circuit]
    if currentLock ~= nil and currentLock ~= container and currentLock.isDeleted ~= true then
        return false, RMS_FluidTransfer.RESULT.BUSY
    end

    local productKey = container:getRMSFluidProductKey()
    if not RMS_Fluids.getIsProductCompatible(productKey, circuit) and not incompatibleConfirmed then
        return false, RMS_FluidTransfer.RESULT.WRONG_FLUID_CONFIRMATION_REQUIRED
    end

    targetSpec.fluidTransferLocks[circuit] = container
    slot.activeTransfer = {
        target = target,
        circuit = circuit,
        productKey = productKey,
        requesterUserId = requester.userId,
        index = index
    }
    container:raiseDirtyFlags(containerSpec.dirtyFlag)
    -- Idle containers need an update to transfer fluid
    container:raiseActive()
    return true, RMS_FluidTransfer.RESULT.OK
end

---Releases the container and target-circuit locks without changing fluid levels
-- @param table container fluid container
-- @param integer? index place to stop, every place of the container when nil
function RMS_FluidTransfer.cancel(container, index)
    local containerSpec = container[RMS_FluidContainer.SPEC_TABLE_NAME]
    if containerSpec == nil or containerSpec.slots == nil then
        return
    end
    for slotIndex, slot in ipairs(containerSpec.slots) do
        local transfer = slot.activeTransfer
        if transfer ~= nil and (index == nil or index == slotIndex) then
            slot.activeTransfer = nil
            local isStillPouring = false
            for _, other in ipairs(containerSpec.slots) do
                isStillPouring = isStillPouring or other.activeTransfer ~= nil and other.activeTransfer.target == transfer.target
                    and other.activeTransfer.circuit == transfer.circuit
            end
            local targetSpec = transfer.target.spec_RealisticMechanicalSystems
            if not isStillPouring and targetSpec.fluidTransferLocks[transfer.circuit] == container then
                targetSpec.fluidTransferLocks[transfer.circuit] = nil
            end
            container:raiseDirtyFlags(containerSpec.dirtyFlag)
        end
    end
end

---Returns the requester of a running transfer, nil once the player left
-- @param table transfer running transfer
-- @return table? requester userId, farmId and player
local function getActiveRequester(transfer)
    local player = g_currentMission.playerSystem:getPlayerByUserId(transfer.requesterUserId)
    if player == nil then
        return nil
    end
    return {
        userId = transfer.requesterUserId,
        farmId = player.farmId,
        player = player
    }
end

---Pours one step of a running transfer, ending it when it is done
-- @param table container fluid container
-- @param table transfer running transfer
-- @param float dt time since the last frame (ms)
local function updateSlot(container, transfer, dt)
    local index = transfer.index
    local requester = getActiveRequester(transfer)
    local result = getRuntimeValidation(container, transfer.target, transfer.circuit, requester, index)
    if result ~= RMS_FluidTransfer.RESULT.OK then
        RMS_FluidTransfer.cancel(container, index)
        return
    end

    local amount = RMS_FluidTransfer.LITERS_PER_SECOND[container:getRMSFluidFormat()]
        * dt / 1000
    if amount <= RMS_Fluids.EPSILON then
        return
    end
    amount = math.min(amount, container:getRMSFluidLiters(index), RMS_Fluids.getMissingLiters(transfer.target, transfer.circuit))
    if amount <= RMS_Fluids.EPSILON then
        RMS_FluidTransfer.cancel(container, index)
        return
    end

    container:beginRMSFluidTransaction()
    local removed = container:removeRMSFluidLiters(amount, index)
    local accepted = RMS_Fluids.addLiters(transfer.target, transfer.circuit, removed, transfer.productKey)
    if removed - accepted > RMS_Fluids.EPSILON then
        container:restoreRMSFluidLiters(removed - accepted, index)
    end

    local finished = accepted <= RMS_Fluids.EPSILON
        or container:getRMSFluidLiters(index) <= RMS_Fluids.EPSILON
        or RMS_Fluids.getMissingLiters(transfer.target, transfer.circuit) <= RMS_Fluids.EPSILON
    if finished then
        RMS_FluidTransfer.cancel(container, index)
    end
    container:endRMSFluidTransaction(accepted > RMS_Fluids.EPSILON)
end

---Pours the running transfers of a container, each place on its own
-- @param table container fluid container
-- @param float dt time since the last frame (ms)
function RMS_FluidTransfer.update(container, dt)
    for _, slot in ipairs(container[RMS_FluidContainer.SPEC_TABLE_NAME].slots) do
        if slot.activeTransfer ~= nil and not container.isDeleted then
            updateSlot(container, slot.activeTransfer, dt)
        end
    end
end
