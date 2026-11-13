-- Copyright © 2026 Squallqt. All rights reserved.

---Plays on the clients an event a breakdown effect had on the server
RMS_EffectSyncEvent = {}
local RMS_EffectSyncEvent_mt = Class(RMS_EffectSyncEvent, Event)

InitEventClass(RMS_EffectSyncEvent, "RMS_EffectSyncEvent")


---Create instance of Event class
function RMS_EffectSyncEvent.emptyNew()
    return Event.new(RMS_EffectSyncEvent_mt)
end


---Create new instance of event
-- @param string effectId effect the event comes from
-- @param string status what happened
-- @param float? value the lights mask of a flicker, the length in ms of a grind
function RMS_EffectSyncEvent.new(vehicle, effectId, status, value)
    local self = RMS_EffectSyncEvent.emptyNew()
    self.vehicle = vehicle
    self.effectId = effectId
    self.status = status
    self.value = value or 0
    return self
end


---Writes event data to a stream.
function RMS_EffectSyncEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObject(streamId, self.vehicle)
    streamWriteString(streamId, self.effectId)
    streamWriteString(streamId, self.status)
    streamWriteFloat32(streamId, self.value)
end


---Reads event data from a stream.
function RMS_EffectSyncEvent:readStream(streamId, connection)
    self.vehicle = NetworkUtil.readNodeObject(streamId)
    self.effectId = streamReadString(streamId)
    self.status = streamReadString(streamId)
    self.value = streamReadFloat32(streamId)
    self:run(connection)
end


-- the state of an effect the client runs as well, nil once it is gone
local function getState(vehicle, effectId)
    return vehicle.spec_RealisticMechanicalSystems.activeEffects[effectId] ~= nil
        and RMS_Breakdowns.getEffectState(vehicle, effectId) or nil
end

local function playSample(vehicle, name)
    RMS_SoundManager.playSample(vehicle.spec_RealisticMechanicalSystems.samples[name])
end

-- what a client plays of each effect, by effect id
local CLIENT_EVENTS = {
    ENGINE_STALLS_CHANCE = function(vehicle)
        vehicle:stopMotor()
        RMS_Breakdowns.showWarning(vehicle, "rms_breakdowns_engine_stalled_message", 5000)
    end,
    CHOPPER_FAILURE = function(vehicle, event)
        RMS_Breakdowns.showWarning(vehicle, event.status == "SWATH" and "rms_breakdowns_chopper_failure_message"
            or "rms_breakdowns_chopper_failure_unchopped_message", 4000)
    end,
    BRAKE_FORCE_MODIFIER = function(vehicle) playSample(vehicle, "brakes") end,
    POWERSHIFT_ENGAGEMENT_LAG_AND_HARSH_EFFECT = function(vehicle) playSample(vehicle, "powershiftClunk") end,
    ENGINE_HESITATION_CHANCE = function(vehicle, event)
        local cough = getState(vehicle, event.effectId)
        if cough ~= nil then
            RMS_Breakdowns.startEngineCough(vehicle, cough)
        end
    end,
    LIGHTS_FLICKER_CHANCE = function(vehicle, event)
        local flicker = getState(vehicle, event.effectId)
        if flicker ~= nil then
            RMS_Breakdowns.startLightsFlicker(flicker, event.value)
        end
    end,
    GEAR_SHIFT_FAILURE_CHANCE = function(vehicle, event)
        local grind = getState(vehicle, event.effectId)
        if grind ~= nil then
            grind.status, grind.timer = "FAILED", 0
            if event.value > 0 then
                local motor = vehicle:getMotor()
                motor.gearChangeTimer, motor.autoGearChangeTimer = event.value, event.value
            end
        end
        playSample(vehicle, "transmissionShiftFailed")
    end,
    GEAR_REJECTION_CHANCE = function(vehicle, event)
        local rejection = getState(vehicle, event.effectId)
        if event.status == "IDLE" then
            if rejection ~= nil then
                rejection.status, rejection.timer = "IDLE", 0
            end
            playSample(vehicle, "transmissionShiftFailed")
        elseif rejection ~= nil then
            RMS_Breakdowns.rejectGear(vehicle, rejection)
        end
    end
}



---Plays the event on a client, or warns its driver of the stop
function RMS_EffectSyncEvent:run(connection)
    local vehicle = self.vehicle
    if vehicle == nil or not vehicle:getIsSynchronized() or vehicle.spec_RealisticMechanicalSystems.isExcludedVehicle then
        return
    end
    if RMS_Breakdowns.SHAFT_ALARMS[self.effectId] then
        RMS_Breakdowns.soundShaftAlarm(vehicle)
    end
    local play = CLIENT_EVENTS[self.effectId]
    if play ~= nil then
        play(vehicle, self)
    else
        RMS_Breakdowns.showWarning(vehicle, RMS_Breakdowns.WORK_STOP_MESSAGES[self.effectId], 4000)
    end
end


---Sends the event of an effect from the server to the clients
function RMS_EffectSyncEvent.send(vehicle, effectId, status, value)
    if g_server ~= nil then
        g_server:broadcastEvent(RMS_EffectSyncEvent.new(vehicle, effectId, status, value), nil, nil, vehicle)
    end
end
