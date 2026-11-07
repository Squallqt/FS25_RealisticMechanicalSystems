-- Copyright © 2026 Squallqt. All rights reserved.

---Engine start in the game's motor states: preheat, starter, catch
RMS_Start = {}

-- the engine waits in the game's IGNITION state until it catches
RMS_Start.STATE = {
    IDLE = 0,
    PREHEATING = 1,
    CRANKING = 2,
    CATCHING = 3,
    FAILED = 4
}

RMS_Start.STATE_NAME = {
    [RMS_Start.STATE.IDLE] = "idle",
    [RMS_Start.STATE.PREHEATING] = "preheating",
    [RMS_Start.STATE.CRANKING] = "cranking",
    [RMS_Start.STATE.CATCHING] = "catching",
    [RMS_Start.STATE.FAILED] = "failed"
}

-- longest starter turn and rest before the next, from manuals, in ms
local STARTER_ATTEMPTS = {
    Car = { crank = 10000, rest = 20000 },
    Tractor4 = { crank = 30000, rest = 120000 },
    Tractor6 = { crank = 30000, rest = 120000 },
    Heavy = { crank = 30000, rest = 120000 }
}

---Resets every start field of the vehicle spec
function RMS_Start.initSpec(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    spec.startState = RMS_Start.STATE.IDLE
    spec.startTimerMs = 0
    spec.startCatchDelayMs = 0
    spec.crankProgressS = 0
    spec.hasStarterTurned = false
    spec.isStartRequested = false
    spec.isStartReleased = false
    spec.lastStartUxState = RMS_Start.STATE.IDLE
    spec.preheatLampTestRemainingMs = 0
    spec.preheatLampTestActive = false
    spec.preheatRemainingMs = 0
    spec.preheatRequiredMs = 0
    spec.preheatWasRequired = false
    spec.preheatColdStartFaultSeverity = 0
end

---Returns the longest turn of the starter and the rest after it
function RMS_Start.getStarterAttempt(vehicle)
    return STARTER_ATTEMPTS[RMS_Breakdowns.getStarterFamily(vehicle)]
end

---Tells whether a start sequence runs, the engine not running yet
function RMS_Start.getIsActive(vehicle)
    return vehicle.spec_RealisticMechanicalSystems.startState ~= RMS_Start.STATE.IDLE
end

---Tells whether the starter turns the engine at this instant
function RMS_Start.getIsCranking(vehicle)
    local state = vehicle.spec_RealisticMechanicalSystems.startState
    return state == RMS_Start.STATE.CRANKING or state == RMS_Start.STATE.CATCHING
        or vehicle:getMotorState() == MotorState.STARTING
end

---Tells whether frozen dead glow plugs keep a diesel from firing
function RMS_Start.getIsColdBlocked(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    local effect = spec.activeEffects.GLOW_PLUG_HARD_START_MODIFIER
    return not spec.isExcludedVehicle and effect ~= nil and effect.extraData ~= nil and effect.extraData.blockStart == true
        and RMS_Preheat.isColdStartAssistanceRequired(vehicle)
end

---Returns how long the starter must turn the engine, in s at full speed
-- @return float? need nil when it fires at once, huge when it never fires
function RMS_Start.getCrankNeed(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    local failure = spec.activeEffects.ENGINE_FAILURE
    if failure ~= nil and failure.extraData.starter then
        return math.huge
    end

    local need = nil
    local engine = spec.activeEffects.ENGINE_HARD_START_MODIFIER
    if engine ~= nil and not spec.isElectricVehicle then
        need = engine.value
    end
    local glowPlugs = spec.activeEffects.GLOW_PLUG_HARD_START_MODIFIER
    if glowPlugs ~= nil and RMS_Preheat.shouldApplyGlowPlugHardStart(vehicle) then
        if glowPlugs.extraData ~= nil and glowPlugs.extraData.blockStart then
            return math.huge
        end
        need = math.max(need or 0, glowPlugs.value)
    end
    if need == nil then
        return nil
    end

    local engineC = RMS_Preheat.getEngineTemperatureC(vehicle)
    if engineC <= -10 then
        return need + (-10 - engineC) / 2
    end
    return need * (1 - 0.3 * math.clamp((engineC - 30) / 60, 0, 1))
end

---Tells whether RMS runs the start instead of the game
function RMS_Start.getNeedsSequence(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    if spec.isExcludedVehicle then
        return false
    elseif spec.isElectricVehicle then
        return spec.activeEffects.ENGINE_FAILURE ~= nil
    end
    return RMS_Preheat.isDieselVehicle(vehicle) or RMS_Start.getCrankNeed(vehicle) ~= nil
end

local function setState(vehicle, state)
    local spec = vehicle.spec_RealisticMechanicalSystems
    spec.startState = state
    spec.startTimerMs = 0
    spec.isStartRequested = false
    if state == RMS_Start.STATE.CRANKING then
        spec.hasStarterTurned = true
    elseif state ~= RMS_Start.STATE.CATCHING then
        spec.hasStarterTurned = false
    end
    if vehicle.isServer then
        RMS_StartEvent.sendEvent(vehicle, state, spec.preheatWasRequired)
    end
end

local function begin(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    if vehicle:getMotorState() == MotorState.OFF then
        vehicle:setMotorState(MotorState.IGNITION)
    end
    spec.preheatColdStartFaultSeverity = 0
    if not RMS_Preheat.isDieselVehicle(vehicle) then
        setState(vehicle, RMS_Start.STATE.CRANKING)
        return
    end

    local duration = RMS_Preheat.getRequiredDurationMs(vehicle)
    spec.preheatRequiredMs = duration
    spec.preheatRemainingMs = duration
    spec.preheatWasRequired = duration > 0
    spec.preheatLampTestRemainingMs = RMS_Config.PREHEAT.LAMP_TEST_DURATION_MS
    spec.preheatLampTestActive = spec.preheatLampTestRemainingMs > 0
    setState(vehicle, RMS_Start.STATE.PREHEATING)
end

local function catch(vehicle, delayMs)
    vehicle.spec_RealisticMechanicalSystems.startCatchDelayMs = delayMs
    setState(vehicle, RMS_Start.STATE.CATCHING)
end

---Ends the start sequence, the engine still off
function RMS_Start.reset(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    spec.preheatLampTestRemainingMs = 0
    spec.preheatLampTestActive = false
    spec.preheatRemainingMs = 0
    spec.preheatRequiredMs = 0
    spec.preheatWasRequired = false
    if spec.startState ~= RMS_Start.STATE.IDLE then
        setState(vehicle, RMS_Start.STATE.IDLE)
    end
end

local function abort(vehicle)
    RMS_Start.reset(vehicle)
    vehicle:setMotorState(MotorState.OFF)
end

local function release(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    spec.isStartReleased = true
    if vehicle:getCanMotorRun() then
        vehicle:startMotor()
    end
    spec.isStartReleased = false
    if spec.startState == RMS_Start.STATE.CATCHING then
        setState(vehicle, RMS_Start.STATE.FAILED)
    end
end

local function updatePreheating(vehicle, dt)
    local spec = vehicle.spec_RealisticMechanicalSystems
    spec.preheatLampTestRemainingMs = math.max(spec.preheatLampTestRemainingMs - dt, 0)
    spec.preheatLampTestActive = spec.preheatLampTestRemainingMs > 0
    spec.preheatRemainingMs = math.max(spec.preheatRemainingMs - dt, 0)
    if spec.preheatLampTestActive or spec.preheatRemainingMs > 0 then
        return
    end

    if spec.preheatWasRequired and RMS_Preheat.isColdStartAssistanceRequired(vehicle) then
        spec.preheatColdStartFaultSeverity = RMS_Preheat.getGlowPlugFailureSeverity(vehicle)
    end
    if RMS_Start.getCrankNeed(vehicle) ~= nil then
        setState(vehicle, RMS_Start.STATE.CRANKING)
    else
        catch(vehicle, 0)
    end
end

local function updateCranking(vehicle, dt)
    local spec = vehicle.spec_RealisticMechanicalSystems
    local crankSpeed = RMS_Electrical.getCrankingSpeed(vehicle)
    local canFire = crankSpeed >= RMS_Config.ELECTRICAL.FIRING_CRANKING_SPEED
    if canFire then
        spec.crankProgressS = spec.crankProgressS + crankSpeed * dt / 1000
    end

    local failure = spec.activeEffects.ENGINE_FAILURE
    local need = RMS_Start.getCrankNeed(vehicle)
    if failure ~= nil and not failure.extraData.starter then
        setState(vehicle, RMS_Start.STATE.FAILED)
    elseif canFire and (need == nil or spec.crankProgressS >= need) then
        catch(vehicle, RMS_Breakdowns.getStarterCatchDelay(vehicle))
    elseif spec.startTimerMs >= RMS_Start.getStarterAttempt(vehicle).crank then
        setState(vehicle, RMS_Start.STATE.FAILED)
    end
end

local function updateClientUx(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    local state = spec.startState
    if state == spec.lastStartUxState then
        return
    end

    spec.lastStartUxState = state
    local isPreheating = state == RMS_Start.STATE.PREHEATING and spec.preheatWasRequired
    if isPreheating then
        RMS_SoundManager.playSample(spec.samples.preheatRelay)
    end
    if not vehicle:getIsActiveForInput(true) or RMS_Config.CORE.ENABLE_WARNING_MESSAGES == false then
        return
    end

    if isPreheating then
        g_currentMission:showBlinkingWarning(g_i18n:getText("rms_preheat_ignition_message"), 2000)
    elseif state == RMS_Start.STATE.FAILED then
        local messageKey = spec.preheatWasRequired
            and RMS_Preheat.isColdStartAssistanceRequired(vehicle)
            and RMS_Preheat.getGlowPlugFailureSeverity(vehicle) >= 4
            and "rms_preheat_system_failure_message"
            or "rms_preheat_start_failed_message"
        g_currentMission:showBlinkingWarning(g_i18n:getText(messageKey), 4000)
    end
end

---Advances the start sequence
function RMS_Start.update(vehicle, dt)
    local spec = vehicle.spec_RealisticMechanicalSystems
    if vehicle.isClient then
        updateClientUx(vehicle)
    end
    if not vehicle.isServer then
        return
    end

    local motorState = vehicle:getMotorState()
    if spec.preheatColdStartFaultSeverity > 0 and (motorState == MotorState.OFF or motorState == MotorState.ON
        and RMS_Preheat.getEngineTemperatureC(vehicle) >= RMS_Config.CORE.ENGINE_FACTOR_DATA.COLD_MOTOR_TEMP_THRESHOLD) then
        spec.preheatColdStartFaultSeverity = 0
    end

    local state = spec.startState
    if state == RMS_Start.STATE.IDLE then
        return
    end
    -- the key, a stop or another start took the engine out of ignition
    if motorState ~= MotorState.IGNITION then
        RMS_Start.reset(vehicle)
        return
    end

    spec.startTimerMs = spec.startTimerMs + dt
    if state == RMS_Start.STATE.PREHEATING then
        updatePreheating(vehicle, dt)
    elseif state == RMS_Start.STATE.CRANKING then
        updateCranking(vehicle, dt)
    elseif state == RMS_Start.STATE.CATCHING and spec.startTimerMs >= spec.startCatchDelayMs then
        release(vehicle)
    end
end

---Applies a state of the start sequence sent by the server
function RMS_Start.onStateReceived(vehicle, state, preheatWasRequired)
    local spec = vehicle.spec_RealisticMechanicalSystems
    if spec == nil or spec.isExcludedVehicle then
        return
    end

    spec.preheatWasRequired = preheatWasRequired
    setState(vehicle, state)
end

---Ends the sequence once the game started the engine
function RMS_Start.onStartMotor(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    if spec.hasStarterTurned and spec.startState == RMS_Start.STATE.CATCHING then
        -- the engine runs up in the catch sound, not in its start recording
        vehicle.spec_motorized.motorStartTime = g_currentMission.time + RMS_Breakdowns.getStarterRunUp(vehicle)
    end
    spec.crankProgressS = 0
    RMS_Start.reset(vehicle)
end

---Switches the ignition off behind a driver leaving during the start
function RMS_Start.onLeaveVehicle(vehicle)
    vehicle.spec_RealisticMechanicalSystems.crankProgressS = 0
    if vehicle.isServer and RMS_Start.getIsActive(vehicle) then
        abort(vehicle)
    end
end

---Runs the start sequence when one is needed, else the game's start
function RMS_Start.startMotor(self, superFunc, noEventSend)
    local spec = self.spec_RealisticMechanicalSystems
    local reason = RMS_Breakdowns.getStartBlockReason(self)
    if reason ~= nil then
        if self.isClient and self:getIsActiveForInput(true) then
            g_currentMission:showBlinkingWarning(g_i18n:getText(reason), 2000)
        end
        return
    end
    if self.isServer and spec.batteryIsolated then
        RMS_Electrical.setBatteryIsolated(self, false)
    end

    local motorState = self:getMotorState()
    if spec.isStartReleased or (motorState ~= MotorState.OFF and motorState ~= MotorState.IGNITION) then
        superFunc(self, noEventSend)
        return
    end
    if self:getIsAIActive() then
        if spec.activeEffects.ENGINE_FAILURE == nil and not RMS_Start.getIsColdBlocked(self) then
            superFunc(self, noEventSend)
        end
        return
    end

    local state = spec.startState
    if not self.isServer then
        if noEventSend then
            -- from the server: the game's own start, or the catch of a sequence
            if state == RMS_Start.STATE.IDLE or state == RMS_Start.STATE.CATCHING then
                superFunc(self, noEventSend)
            end
        elseif state ~= RMS_Start.STATE.IDLE or RMS_Start.getNeedsSequence(self) then
            spec.isStartRequested = true
            MotorSetTurnedOnEvent.sendEvent(self, true)
        else
            superFunc(self, noEventSend)
        end
        return
    end

    if state == RMS_Start.STATE.IDLE then
        if RMS_Start.getNeedsSequence(self) then
            begin(self)
        else
            superFunc(self, noEventSend)
        end
    elseif state == RMS_Start.STATE.FAILED then
        -- the game's automatic start lets the starter rest as a driver would
        if g_currentMission.missionInfo.automaticMotorStartEnabled ~= true
            or spec.startTimerMs >= RMS_Start.getStarterAttempt(self).rest then
            begin(self)
        end
    end
end

---Switches the ignition off during the start sequence
function RMS_Start.stopMotor(self, superFunc, noEventSend)
    if self:getMotorState() ~= MotorState.IGNITION or not RMS_Start.getIsActive(self) then
        superFunc(self, noEventSend)
    elseif self.isServer then
        abort(self)
    elseif not noEventSend then
        MotorSetTurnedOnEvent.sendEvent(self, false)
    end
end

---Hands the start the key asks for to the sequence
-- @return boolean isTaken true when the game must not start the engine
function RMS_Start.takeKeyStart(vehicle)
    if vehicle.spec_RealisticMechanicalSystems.isStartReleased
        or not g_ignitionLockManager:getIsAvailable()
        or g_ignitionLockManager:getState() ~= IgnitionLockState.START
        -- the key turns only the machine the local player drives
        or not vehicle:getIsActiveForInput(true) then
        return false
    end

    local spec = vehicle.spec_RealisticMechanicalSystems
    local state = spec.startState
    if state == RMS_Start.STATE.IDLE and not RMS_Start.getNeedsSequence(vehicle) then
        return false
    end
    if (state == RMS_Start.STATE.IDLE or state == RMS_Start.STATE.FAILED) and not spec.isStartRequested then
        vehicle:startMotor()
    end
    return true
end

local function playDeadStartSound(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    if spec.isElectricVehicle or spec.batteryIsolated then
        return
    end
    if RMS_Electrical.getStartingVoltage(vehicle) < RMS_Electrical.getMinCrankingVoltage(vehicle) then
        RMS_SoundManager.playSample(spec.samples.batteryClicking)
    elseif vehicle:hasBreakdown("STARTER_RELAY_FAILURE") or vehicle:hasBreakdown("ENGINE_JAM") or spec.starterHealth <= 0 then
        RMS_SoundManager.playSample(spec.samples.starterRelayClick)
    end
end

local function getIsStarting(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    return spec ~= nil and spec.startState ~= RMS_Start.STATE.IDLE and spec.startState ~= RMS_Start.STATE.FAILED
end

local function getIsStartIdle(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    local motorState = vehicle:getMotorState()
    return spec ~= nil and not spec.isExcludedVehicle and not getIsStarting(vehicle)
        and (motorState == MotorState.OFF or motorState == MotorState.IGNITION)
end

---Clicks a starter that cannot turn, and stops a start under way
function RMS_Start.actionEventToggleMotorState(self, superFunc, ...)
    if getIsStarting(self) and not self:getIsAIActive() then
        self:stopMotor()
        return
    end
    if getIsStartIdle(self) then
        playDeadStartSound(self)
    end
    superFunc(self, ...)
end

---Clicks a starter that cannot turn
function RMS_Start.actionEventSetMotorStateOn(self, superFunc, ...)
    if getIsStartIdle(self) then
        playDeadStartSound(self)
    end
    superFunc(self, ...)
end

---Offers to stop the engine while it is being started
function RMS_Start.updateActionEvents(self)
    local actionEvent = self.spec_motorized.actionEvents[InputAction.TOGGLE_MOTOR_STATE]
    if actionEvent ~= nil and getIsStarting(self) then
        g_inputBinding:setActionEventTextPriority(actionEvent.actionEventId, GS_PRIO_VERY_LOW)
        g_inputBinding:setActionEventText(actionEvent.actionEventId, self.spec_motorized.turnOffText)
    end
end

Motorized.actionEventToggleMotorState = Utils.overwrittenFunction(Motorized.actionEventToggleMotorState, RMS_Start.actionEventToggleMotorState)
Motorized.actionEventSetMotorStateOn = Utils.overwrittenFunction(Motorized.actionEventSetMotorStateOn, RMS_Start.actionEventSetMotorStateOn)
Motorized.updateActionEvents = Utils.appendedFunction(Motorized.updateActionEvents, RMS_Start.updateActionEvents)
