-- Copyright © 2026 Squallqt. All rights reserved.

---AI worker easing off under overload, stopped when it cannot move

local function getAiWorkerSpeedLimit(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    if spec ~= nil and vehicle:getIsAIActive() then
        return spec.aiWorkerSpeedLimit
    end
    return nil
end

---Eases the helper off under overload and gives its pace back after
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

---Stops a helper pushing on the spot once the native recoveries had time
function RealisticMechanicalSystems:updateAiWorkerBlocked(dt)
    if not self.isServer then return end
    local spec = self.spec_RealisticMechanicalSystems

    -- AutoDrive stops and restarts on its own when stuck
    local routeDriver = self.ad
    local driverState = routeDriver ~= nil and routeDriver.stateModule or nil
    local isAutoDriving = driverState ~= nil and driverState.isActive ~= nil and driverState:isActive()
    if not self:getIsAIActive() or isAutoDriving then
        spec.aiWorkerBlockedMs, spec.aiWorkerBlockedAt = 0, nil
        return
    end

    local C = RMS_Config.CORE.AI_WORKER
    local x, _, z = getWorldTranslation(self.rootNode)
    local anchor = spec.aiWorkerBlockedAt
    if anchor == nil or MathUtil.vector2Length(x - anchor[1], z - anchor[2]) > C.BLOCKED_DISTANCE then
        spec.aiWorkerBlockedMs, spec.aiWorkerBlockedAt = 0, { x, z }
    end

    -- accelerator asked by the helper, before the gearbox
    local motor = self:getMotor()
    if self:getIsMotorStarted() and motor ~= nil and (tonumber(motor.lastAcceleratorPedal) or 0) ~= 0 then
        spec.aiWorkerBlockedMs = spec.aiWorkerBlockedMs + dt
        if spec.aiWorkerBlockedMs >= C.BLOCKED_SECONDS * 1000 and self.stopCurrentAIJob ~= nil then
            spec.aiWorkerBlockedMs, spec.aiWorkerBlockedAt = 0, nil
            self:stopCurrentAIJob(AIMessageErrorBlockedByObject.new())
        end
    end
end

---Holds the helper under its eased pace, the player's cruise speed untouched
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
