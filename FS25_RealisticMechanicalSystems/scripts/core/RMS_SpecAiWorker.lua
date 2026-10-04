-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---AI worker driving: the helper eases off while the machine is overloaded, like a careful driver

---Returns the pace an AI worker is eased to
-- @param table vehicle vehicle
-- @return float? speedLimit speed limit in km/h, nil while the helper drives freely
local function getAiWorkerSpeedLimit(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    if spec ~= nil and vehicle:getIsAIActive() then
        return spec.aiWorkerSpeedLimit
    end
    return nil
end

---Eases the helper off while the machine runs into overload, and gives its pace back once the load eases
-- @param float dt time since last call in ms
function RealisticMechanicalSystems:updateAiWorkerSpeed(dt)
    if not self.isServer then return end
    local spec = self.spec_RealisticMechanicalSystems

    if not self:getIsAIActive() then
        spec.aiWorkerSpeedLimit = nil
        spec.aiWorkerOverload = 0
        return
    end

    local C = RMS_Config.CORE.AI_WORKER
    local seconds = dt / 1000
    spec.aiWorkerOverload = spec.aiWorkerOverload
        + (spec.overloadLevel - spec.aiWorkerOverload) * math.min(seconds / C.OVERLOAD_SMOOTHING, 1)

    -- easing off answers the load of the moment, picking up again waits for it to stay calm
    if spec.overloadLevel > C.SLOW_DOWN_LEVEL then
        local speed = spec.aiWorkerSpeedLimit or self:getLastSpeed()
        spec.aiWorkerSpeedLimit = math.max(speed - C.SLOW_DOWN_RATE * seconds, C.MIN_SPEED)
    elseif spec.aiWorkerSpeedLimit ~= nil and spec.aiWorkerOverload < C.RESUME_LEVEL then
        spec.aiWorkerSpeedLimit = spec.aiWorkerSpeedLimit + C.RESUME_RATE * seconds
        if spec.aiWorkerSpeedLimit > self:getLastSpeed() + C.RELEASE_MARGIN then
            spec.aiWorkerSpeedLimit = nil
        end
    end

    if RMS_Utils.getIsDebugDataWanted(self) then
        spec.debugData.aiWorker.overload = spec.aiWorkerOverload
        spec.debugData.aiWorker.speedLimit = spec.aiWorkerSpeedLimit or 0
    end
end

---Holds the helper under its eased pace, which the game's helpers and its gearbox read, the player's
-- cruise speed staying as set
-- @param function superFunc original function
-- @return float speed cruise control speed in km/h
function RealisticMechanicalSystems:getCruiseControlSpeed(superFunc)
    local speed = superFunc(self)
    local speedLimit = getAiWorkerSpeedLimit(self)
    if speedLimit ~= nil then
        return math.min(speed, speedLimit)
    end
    return speed
end

-- the game's navigation drive and AutoDrive limit the motor without reading the cruise speed
VehicleMotor.setSpeedLimit = Utils.overwrittenFunction(VehicleMotor.setSpeedLimit, function(self, superFunc, limit)
    local speedLimit = getAiWorkerSpeedLimit(self.vehicle)
    if speedLimit ~= nil then
        limit = math.min(limit, speedLimit)
    end
    superFunc(self, limit)
end)
