-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---Server-authoritative physical container transfer state and validation
RMS_FluidTransfer = {}

RMS_FluidTransfer.MAX_DISTANCE = 4
-- km/h under which a machine stands still, as the game counts it
RMS_FluidTransfer.STOPPED_SPEED = 0.5
-- liters a second a container delivers: 5 L can, 25 L can, drum through its pump
RMS_FluidTransfer.LITERS_PER_SECOND = { [5] = 0.2, [25] = 0.3, [200] = 1 }
-- metres of hose between the pump of a drum and its nozzle, twice the 2 m its maker ships
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
-- @param entityId node node standing beside it
-- @return float distance metres to the footprint of the machine, zero inside it
function RMS_FluidTransfer.getDistanceToVehicle(vehicle, node)
    local x, _, z = worldToLocal(vehicle.rootNode, getWorldTranslation(node))
    local size = vehicle.size
    local dx = math.max(math.abs(x - size.widthOffset) - size.width * 0.5, 0)
    local dz = math.max(math.abs(z - size.lengthOffset) - size.length * 0.5, 0)
    return math.sqrt(dx * dx + dz * dz)
end

---Returns the player, user and farm of a network connection
-- @param Connection connection requester connection
-- @return table? requester authenticated requester context
function RMS_FluidTransfer.getRequesterContext(connection)
    if connection == nil then
        return nil
    end

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

---
local function getIsOwnedByRequester(container, target, requester)
    return requester ~= nil and requester.farmId ~= nil
        and container ~= nil and container.getOwnerFarmId ~= nil
        and target ~= nil and target.getOwnerFarmId ~= nil
        and container:getOwnerFarmId() == requester.farmId
        and target:getOwnerFarmId() == requester.farmId
end

---
local function getRuntimeValidation(container, target, circuit, requester)
    if g_server == nil or container == nil or target == nil or requester == nil
        or container.isDeleted == true or target.isDeleted == true
        or container[RMS_FluidContainer.SPEC_TABLE_NAME] == nil
        or target.spec_RealisticMechanicalSystems == nil
        or RMS_Fluids.CIRCUITS[circuit] == nil then
        return RMS_FluidTransfer.RESULT.INVALID
    end

    if not getIsOwnedByRequester(container, target, requester) then
        return RMS_FluidTransfer.RESULT.NO_ACCESS
    end

    -- the container pours from the hand that carries it, the can or the nozzle of a drum
    if container:getRMSFluidCarrier() ~= requester.player then
        return RMS_FluidTransfer.RESULT.INVALID
    end

    -- a drum delivers no further than its hose
    if RMS_FluidTransfer.getDistanceToVehicle(target, requester.player.rootNode) > RMS_FluidTransfer.MAX_DISTANCE
        or (container:getRMSFluidCapacity() > RMS_FluidContainer.CARRIED_CAPACITY
            and RMS_FluidTransfer.getDistanceToVehicle(target, container.rootNode) > RMS_FluidTransfer.HOSE_LENGTH) then
        return RMS_FluidTransfer.RESULT.OUT_OF_RANGE
    end

    if target.isUnderService ~= nil and target:isUnderService() then
        return RMS_FluidTransfer.RESULT.SERVICE_BUSY
    end

    if target.getIsMotorStarted ~= nil and target:getIsMotorStarted() then
        return RMS_FluidTransfer.RESULT.MOTOR_RUNNING
    end

    if target.getLastSpeed ~= nil and math.abs(tonumber(target:getLastSpeed()) or 0) > RMS_FluidTransfer.STOPPED_SPEED then
        return RMS_FluidTransfer.RESULT.VEHICLE_MOVING
    end

    if RMS_Fluids.getCapacity(target, circuit) <= RMS_Fluids.EPSILON
        or RMS_Fluids.getMissingLiters(target, circuit) <= RMS_Fluids.EPSILON then
        return RMS_FluidTransfer.RESULT.CIRCUIT_FULL
    end

    if container:getRMSFluidLiters() <= RMS_Fluids.EPSILON then
        return RMS_FluidTransfer.RESULT.CONTAINER_EMPTY
    end

    return RMS_FluidTransfer.RESULT.OK
end

-- what a player is told of a refused pour
local REFUSAL_TEXT_KEYS = {
    [RMS_FluidTransfer.RESULT.MOTOR_RUNNING] = "rms_fluid_error_motor_running",
    [RMS_FluidTransfer.RESULT.VEHICLE_MOVING] = "rms_fluid_error_vehicle_moving",
    [RMS_FluidTransfer.RESULT.SERVICE_BUSY] = "rms_charger_error_service",
    [RMS_FluidTransfer.RESULT.CIRCUIT_FULL] = "rms_fluid_error_no_circuit",
    [RMS_FluidTransfer.RESULT.BUSY] = "rms_fluid_error_busy"
}

---Returns the text telling a player why the server refused the pour
-- @param table container container the player poured from
-- @param string result result of the server
-- @return string? textKey text of the refusal, nil for a result no legitimate request meets
function RMS_FluidTransfer.getRefusalTextKey(container, result)
    local isDrum = container:getRMSFluidCapacity() > RMS_FluidContainer.CARRIED_CAPACITY
    if result == RMS_FluidTransfer.RESULT.OUT_OF_RANGE then
        return isDrum and "rms_drum_pump_machine_too_far" or nil
    elseif result == RMS_FluidTransfer.RESULT.CONTAINER_EMPTY then
        return isDrum and "rms_fluid_drum_empty" or "rms_fluid_container_empty"
    end
    return REFUSAL_TEXT_KEYS[result]
end

---Starts one locked manual transfer after all authoritative checks
-- @param table container physical source container
-- @param table target RMS target vehicle
-- @param string circuit target circuit
-- @param table requester authenticated requester context
-- @param boolean incompatibleConfirmed explicit incompatible-fluid confirmation
-- @return boolean started whether the transfer started
-- @return string result validation result
function RMS_FluidTransfer.tryStart(container, target, circuit, requester, incompatibleConfirmed)
    local result = getRuntimeValidation(container, target, circuit, requester)
    if result ~= RMS_FluidTransfer.RESULT.OK then
        return false, result
    end

    local containerSpec = container[RMS_FluidContainer.SPEC_TABLE_NAME]
    if containerSpec.activeTransfer ~= nil then
        return false, RMS_FluidTransfer.RESULT.BUSY
    end

    local targetSpec = target.spec_RealisticMechanicalSystems
    targetSpec.fluidTransferLocks = targetSpec.fluidTransferLocks or {}
    local currentLock = targetSpec.fluidTransferLocks[circuit]
    if currentLock ~= nil and currentLock ~= container and currentLock.isDeleted ~= true then
        return false, RMS_FluidTransfer.RESULT.BUSY
    end

    local productKey = container:getRMSFluidProductKey()
    if RMS_Fluids.PRODUCTS[productKey] == nil then
        return false, RMS_FluidTransfer.RESULT.INVALID
    end
    if not RMS_Fluids.getIsProductCompatible(productKey, circuit) and incompatibleConfirmed ~= true then
        return false, RMS_FluidTransfer.RESULT.WRONG_FLUID_CONFIRMATION_REQUIRED
    end

    targetSpec.fluidTransferLocks[circuit] = container
    containerSpec.activeTransfer = {
        target = target,
        circuit = circuit,
        productKey = productKey,
        requesterUserId = requester.userId,
        requesterFarmId = requester.farmId
    }
    container:raiseDirtyFlags(containerSpec.dirtyFlag)
    -- a container at rest is not updated by the game, and its update pours the fluid
    container:raiseActive()
    return true, RMS_FluidTransfer.RESULT.OK
end

---Releases the container and target-circuit locks without changing fluid levels
-- @param table container physical source container
function RMS_FluidTransfer.cancel(container)
    local containerSpec = container ~= nil and container[RMS_FluidContainer.SPEC_TABLE_NAME] or nil
    local transfer = containerSpec ~= nil and containerSpec.activeTransfer or nil
    if transfer == nil then
        return
    end

    local targetSpec = transfer.target ~= nil and transfer.target.spec_RealisticMechanicalSystems or nil
    if targetSpec ~= nil and targetSpec.fluidTransferLocks ~= nil
        and targetSpec.fluidTransferLocks[transfer.circuit] == container then
        targetSpec.fluidTransferLocks[transfer.circuit] = nil
    end
    containerSpec.activeTransfer = nil
    container:raiseDirtyFlags(containerSpec.dirtyFlag)
end

---
local function getActiveRequester(transfer)
    local player = transfer.requesterUserId ~= nil
        and g_currentMission.playerSystem:getPlayerByUserId(transfer.requesterUserId) or nil
    if player == nil then
        return nil
    end
    return {
        userId = transfer.requesterUserId,
        farmId = player.farmId,
        player = player
    }
end

---Advances the active server transfer and puts back any liters the target refused
-- @param table container physical source container
-- @param float dt elapsed milliseconds
function RMS_FluidTransfer.update(container, dt)
    local containerSpec = container ~= nil and container[RMS_FluidContainer.SPEC_TABLE_NAME] or nil
    local transfer = containerSpec ~= nil and containerSpec.activeTransfer or nil
    if transfer == nil then
        return
    end

    local requester = getActiveRequester(transfer)
    local result = getRuntimeValidation(container, transfer.target, transfer.circuit, requester)
    if result ~= RMS_FluidTransfer.RESULT.OK then
        RMS_FluidTransfer.cancel(container)
        return
    end

    local amount = RMS_FluidTransfer.LITERS_PER_SECOND[container:getRMSFluidCapacity()] * math.max(tonumber(dt) or 0, 0) / 1000
    if amount <= RMS_Fluids.EPSILON then
        return
    end
    amount = math.min(amount, container:getRMSFluidLiters(), RMS_Fluids.getMissingLiters(transfer.target, transfer.circuit))
    if amount <= RMS_Fluids.EPSILON then
        RMS_FluidTransfer.cancel(container)
        return
    end

    container:beginRMSFluidTransaction()
    local removed = container:removeRMSFluidLiters(amount)
    local accepted = RMS_Fluids.addLiters(transfer.target, transfer.circuit, removed, transfer.productKey)
    if removed - accepted > RMS_Fluids.EPSILON then
        container:restoreRMSFluidLiters(removed - accepted)
    end

    local finished = accepted <= RMS_Fluids.EPSILON
        or container:getRMSFluidLiters() <= RMS_Fluids.EPSILON
        or RMS_Fluids.getMissingLiters(transfer.target, transfer.circuit) <= RMS_Fluids.EPSILON
    if finished then
        RMS_FluidTransfer.cancel(container)
    end
    container:endRMSFluidTransaction(accepted > RMS_Fluids.EPSILON)
end
