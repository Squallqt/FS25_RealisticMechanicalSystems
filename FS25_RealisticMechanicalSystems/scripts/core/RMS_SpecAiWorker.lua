-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---AI worker easing off while the machine is overloaded

---Returns the pace an AI worker is eased to
local function getAiWorkerSpeedLimit(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    if spec ~= nil and vehicle:getIsAIActive() then
        return spec.aiWorkerSpeedLimit
    end
    return nil
end

---Eases the helper off under overload and gives its pace back after
-- @param float dt time since last call in ms
function RealisticMechanicalSystems:updateAiWorkerSpeed(dt)
    if not self.isServer then return end
    local spec = self.spec_RealisticMechanicalSystems

    if not self:getIsAIActive() then
        spec.aiWorkerSpeedLimit = nil
        spec.aiWorkerOverload = 0
        return
    end

    if spec.batteryIsolated then
        RMS_Electrical.setBatteryIsolated(self, false)
    end

    local C = RMS_Config.CORE.AI_WORKER
    local seconds = dt / 1000
    spec.aiWorkerOverload = spec.aiWorkerOverload
        + (spec.overloadLevel - spec.aiWorkerOverload) * math.min(seconds / C.OVERLOAD_SMOOTHING, 1)

    if spec.overloadLevel > C.SLOW_DOWN_LEVEL then
        local speed = spec.aiWorkerSpeedLimit or self:getLastSpeed()
        spec.aiWorkerSpeedLimit = math.max(speed - C.SLOW_DOWN_RATE * seconds, C.MIN_SPEED)
    elseif spec.aiWorkerSpeedLimit ~= nil and spec.aiWorkerOverload < C.RESUME_LEVEL then
        spec.aiWorkerSpeedLimit = spec.aiWorkerSpeedLimit + C.RESUME_RATE * seconds
        if spec.aiWorkerSpeedLimit > self:getLastSpeed() + C.RELEASE_MARGIN then
            spec.aiWorkerSpeedLimit = nil
        end
    end
end

---Holds the helper under its eased pace, the player's cruise speed untouched
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

-- Native navigation and AutoDrive also limit the motor directly.
VehicleMotor.setSpeedLimit = Utils.overwrittenFunction(VehicleMotor.setSpeedLimit, function(self, superFunc, limit)
    local speedLimit = getAiWorkerSpeedLimit(self.vehicle)
    if speedLimit ~= nil then
        limit = math.min(limit, speedLimit)
    end
    superFunc(self, limit)
end)
