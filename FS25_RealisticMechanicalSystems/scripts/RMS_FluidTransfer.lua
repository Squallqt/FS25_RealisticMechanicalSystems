-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---Server-authoritative physical container transfer state and validation
RMS_FluidTransfer = {}

RMS_FluidTransfer.MAX_DISTANCE = 4
RMS_FluidTransfer.STOPPED_SPEED = 0.01
RMS_FluidTransfer.LITERS_PER_SECOND = 1

RMS_FluidTransfer.RESULT = {
    OK = "OK",
    INVALID = "INVALID",
    NO_ACCESS = "NO_ACCESS",
    OUT_OF_RANGE = "OUT_OF_RANGE",
    MOTOR_RUNNING = "MOTOR_RUNNING",
    VEHICLE_MOVING = "VEHICLE_MOVING",
    CIRCUIT_FULL = "CIRCUIT_FULL",
    WRONG_FLUID_CONFIRMATION_REQUIRED = "WRONG_FLUID_CONFIRMATION_REQUIRED",
    BUSY = "BUSY",
    CONTAINER_EMPTY = "CONTAINER_EMPTY"
}

local function getDistance(objectA, objectB)
    local nodeA = objectA ~= nil and (objectA.rootNode or objectA.nodeId) or nil
    local nodeB = objectB ~= nil and (objectB.rootNode or objectB.nodeId) or nil
    if nodeA == nil or nodeB == nil then
        return math.huge
    end

    local ax, ay, az = getWorldTranslation(nodeA)
    local bx, by, bz = getWorldTranslation(nodeB)
    return MathUtil.vector3Length(ax - bx, ay - by, az - bz)
end

---Resolves the authenticated player, user and farm attached to a network connection
-- @param Connection connection requester connection
-- @return table? requester authenticated requester context
function RMS_FluidTransfer.getRequesterContext(connection)
    if connection == nil or g_currentMission == nil or g_currentMission.userManager == nil
        or g_currentMission.playerSystem == nil or g_farmManager == nil then
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

local function getIsOwnedByRequester(container, target, requester)
    return requester ~= nil and requester.farmId ~= nil
        and container ~= nil and container.getOwnerFarmId ~= nil
        and target ~= nil and target.getOwnerFarmId ~= nil
        and container:getOwnerFarmId() == requester.farmId
        and target:getOwnerFarmId() == requester.farmId
end

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

    if requester.player == nil
        or getDistance(requester.player, container) > RMS_FluidTransfer.MAX_DISTANCE
        or getDistance(requester.player, target) > RMS_FluidTransfer.MAX_DISTANCE
        or getDistance(container, target) > RMS_FluidTransfer.MAX_DISTANCE then
        return RMS_FluidTransfer.RESULT.OUT_OF_RANGE
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
end

local function getActiveRequester(transfer)
    local player = g_currentMission ~= nil and g_currentMission.playerSystem ~= nil
        and transfer.requesterUserId ~= nil
        and g_currentMission.playerSystem:getPlayerByUserId(transfer.requesterUserId) or nil
    if player == nil then
        return nil
    end
    return {
        userId = transfer.requesterUserId,
        farmId = transfer.requesterFarmId,
        player = player
    }
end

local function getTransferAmount(dt)
    return RMS_FluidTransfer.LITERS_PER_SECOND * math.max(tonumber(dt) or 0, 0) / 1000
end

---Advances the active server transfer and rolls back any unaccepted FillUnit removal
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

    local amount = getTransferAmount(dt)
    if amount <= RMS_Fluids.EPSILON then
        return
    end
    amount = math.min(amount, container:getRMSFluidLiters(), RMS_Fluids.getMissingLiters(transfer.target, transfer.circuit))
    if amount <= RMS_Fluids.EPSILON then
        RMS_FluidTransfer.cancel(container)
        return
    end

    container:beginRMSFluidTransaction()
    local removed, fillType = container:removeRMSFluidLiters(amount, transfer.requesterFarmId)
    local accepted = RMS_Fluids.addLiters(transfer.target, transfer.circuit, removed, transfer.productKey)
    if removed - accepted > RMS_Fluids.EPSILON then
        container:restoreRMSFluidLiters(removed - accepted, transfer.requesterFarmId, fillType)
    end

    local finished = accepted <= RMS_Fluids.EPSILON
        or container:getRMSFluidLiters() <= RMS_Fluids.EPSILON
        or RMS_Fluids.getMissingLiters(transfer.target, transfer.circuit) <= RMS_Fluids.EPSILON
    if finished then
        RMS_FluidTransfer.cancel(container)
    end
    container:endRMSFluidTransaction(accepted > RMS_Fluids.EPSILON)
end
