-- Copyright © 2026 Squallqt. All rights reserved.

---Tutorial tips, each shown once
RMS_Tutorial = {}
RMS_Tutorial.modDirectory = g_currentModDirectory
RMS_Tutorial.vehicle = nil
RMS_Tutorial.timer = 0
RMS_Tutorial.messageDowntime = 3000

---Pause after a tip before the next one, in ms
RMS_Tutorial.TIP_DOWNTIME = 60000

---Welcomes the player in the question dialog of the game
function RMS_Tutorial:showWelcome()
    YesNoDialog.show(self.onWelcomeAnswer, self, g_i18n:getText("rms_tutorial_welcome_message"),
        g_i18n:getText("rms_tutorial_welcome_dialog_title"), g_i18n:getText("rms_tutorial_welcome_enable_button"),
        g_i18n:getText("rms_tutorial_welcome_disable_button"), DialogElement.TYPE_INFO)
    self.messageDowntime = 5000
end

---Turns the tips off when the player declined them
function RMS_Tutorial:onWelcomeAnswer(keepsTips)
    if not keepsTips then
        RMS_Config.TUTORIAL_MODE = false
        RMS_Config.syncTutorialState()
    end
end

---Keeps the vehicle the player drives when RMS tracks it
function RMS_Tutorial:getRMSVehicle()
    local player = g_localPlayer
    local vehicle = player ~= nil and player.getCurrentVehicle ~= nil and player:getCurrentVehicle() or nil
    local spec = vehicle ~= nil and vehicle.spec_RealisticMechanicalSystems or nil
    self.vehicle = (spec ~= nil and not spec.isExcludedVehicle) and vehicle or nil
end

---Tells whether one of the named systems is enabled on the machine
local function isEnabled(machine, ...)
    for _, systemKey in ipairs({ ... }) do
        if machine.enabled[systemKey] then
            return true
        end
    end
    return false
end

---Name of the machine, the argument most tips print
local function getName(machine)
    return machine.vehicle:getFullName()
end

---Key that opens the field inspection, as the keyboard shows it
local function getInspectionKey()
    return RMS_Utils.getPrimaryKeyboardInputText("RMS_FIELD_INSPECTION", "R")
end

---Tells whether the trailer is heavy for the power that pulls it
local function hasHeavyTrailer(machine)
    local spec = machine.spec
    local brakes = spec.chassisBrakeState
    local isTruck = spec.isTruck == true
    local ratio = isTruck and brakes.hpGrossMassRatio or brakes.hpTrailerMassRatio
    local limit = RMS_Utils.getHeavyTrailerRatioLevels(machine.vehicle) * RMS_Config.CORE.TRANSMISSION_FACTOR_DATA.HEAVY_TRAILER_TUTORIAL_MARGIN
    return math.max(brakes.trailerMass, 0) > 0.1 and ratio <= limit
end

---Share of the service interval used, 1 at the expiry threshold
local function getServiceIntervalUsed(machine)
    local base = machine.spec.baseServiceLevel
    return (base - machine.vehicle:getServiceLevel()) / (base - RMS_Config.CORE.SERVICE_EXPIRED_THRESHOLD)
end

---Tells whether a part the major service checks is worn
local function hasMajorServiceWear(machine)
    local wear = machine.spec.partWear
    for _, partId in ipairs(RealisticMechanicalSystems.MAJOR_SERVICE_CHECKS) do
        if wear[partId] ~= nil and RMS_Utils.getIsPartWorn(partId, wear[partId]) then
            return true
        end
    end
    return false
end

---Tells whether a poor quality part has a breakdown waiting to show
local function hasPoorPartsBreakdown(machine)
    for id, breakdown in pairs(machine.spec.activeBreakdowns or {}) do
        local definition = RMS_Breakdowns.BreakdownRegistry[id]
        if definition ~= nil and definition.isSelectable == true and breakdown.isActive == false
            and breakdown.source == RealisticMechanicalSystems.BREAKDOWN_SOURCES.POOR_PARTS then
            return true
        end
    end
    return false
end

---Tells whether the transmission is a CVT or carries a CVT addon
local function hasCVT(machine)
    return RMS_Utils.hasCVTTransmission(machine.vehicle) or RMS_Utils.hasCVTAddon(machine.vehicle)
end

---Tells whether a fluid of an enabled system is under its minimum mark
local function hasLowFluid(machine)
    local spec = machine.spec
    local minimum = RMS_Config.FLUIDS.LEVEL_MIN_MARK
    return (machine.enabled.engine and (tonumber(spec.engineOilLevel) or 1) < minimum)
        or (machine.enabled.cooling and (tonumber(spec.coolantLevel) or 1) < minimum)
        or (machine.enabled.transmission and (tonumber(spec.transmissionOilLevel) or 1) < minimum)
        or (machine.enabled.hydraulics and RMS_Fluids.getLevel(machine.vehicle, "hydraulicFluid") < minimum)
end

---Tells whether the oil is still cold enough to wear the transmission
local function hasColdOil(machine)
    local spec = machine.spec
    local data = RMS_Config.CORE.TRANSMISSION_FACTOR_DATA
    local isHydraulicWorking = machine.enabled.hydraulics and spec.isHydraulicActive
    local temperature = RealisticMechanicalSystems.sanitizeNumber(spec.rawTransmissionTemperature or spec.transmissionTemperature, 20, -80, 180)
    return (machine.enabled.transmission or isHydraulicWorking)
        and machine.isStarted
        and temperature < data.COLD_TRANSMISSION_THRESHOLD
end

---Tips in check order; text is the key before _title and _message
RMS_Tutorial.TIPS = {
    { key = "HEAVY_TRAILER", text = "rms_tutorial_heavy_trailer", isDue = function(m)
        return m.enabled.transmission and m.isStarted and m.speed > 5 and hasHeavyTrailer(m) end },
    { key = "AGE_DEGRADATION", text = "rms_tutorial_age_degradation", getArguments = getName, isDue = function(m)
        return m.vehicle:getConditionLevel() < 0.66 end },
    { key = "IDLE_AND_DOWNTIME", text = "rms_tutorial_idle_and_downtime", isDue = function(m)
        return m.isStarted and m.spec.fuelState.idleTimer > 30 end },
    { key = "HOT_WEATHER", text = "rms_tutorial_hot_weather", getArguments = getInspectionKey, isDue = function(m)
        return isEnabled(m, "engine", "cooling") and RMS_Utils.getAmbientTemperature() > 30 end },
    { key = "WET_WEATHER", text = "rms_tutorial_wet_weather", isDue = function(m)
        local weather = g_currentMission.environment.weather:getCurrentWeatherType()
        return m.enabled.electrical and (weather == WeatherType.RAIN or weather == WeatherType.SNOW or weather == WeatherType.HAIL) end },
    { key = "RAD_OR_FILTER_CLOGGED", text = "rms_tutorial_cooling_air_check", isDue = function(m)
        local spec = m.spec
        return isEnabled(m, "engine", "cooling") and spec.isVehicleNeedBlowOut
            and (spec.radiatorClogging >= 0.35 or RMS_Consumables.getAirFilterBlowOutStage(spec) >= 2
                or RMS_Consumables.getIsAirFilterWornOut(spec)) end,
        getArguments = function(m) return getInspectionKey(), RMS_Utils.formatAirFilterServiceHours(m.vehicle) end },
    { key = "NEEDS_LUBRICATION", text = "rms_tutorial_needs_lubrication", isDue = function(m)
        return RMS_Greasing.getDuePoints(m.vehicle) > 0 end,
        getArguments = function(m) return getName(m), getInspectionKey() end },
    { key = "ENGINE_OVERHEAT", text = "rms_tutorial_engine_overheat", alsoSeen = { "CVT_OVERHEAT" }, isDue = function(m)
        return m.enabled.engine and m.isStarted and m.spec.engineTemperature > 100 and not m.isElectric end },
    { key = "COLD_ENGINE", text = "rms_tutorial_cold_engine", isDue = function(m)
        return m.enabled.engine and m.spec.engineTemperature < 40 and m.isStarted and m.speed < 1 and not m.isElectric end },
    { key = "OVERLOAD_INDICATOR", text = "rms_tutorial_overload_indicator", getArguments = getName, isDue = function(m)
        return m.isStarted and m.vehicle:hasBreakdown("STRESS_OVERLOAD") end },
    { key = "ENGINE_OVERLOAD", text = "rms_tutorial_engine_overload", isDue = function(m)
        return m.enabled.engine and m.isStarted and m.spec.dynamicMotorLoad >= 1.15 and not m.isElectric end },
    { key = "LUGGING", text = "rms_tutorial_lugging", isDue = function(m)
        local timer = m.spec.luggingTutorialTimer
        return m.enabled.transmission and timer ~= nil and timer >= 5000 and not m.isElectric end },
    { key = "CVT_OVERHEAT", text = "rms_tutorial_cvt_overheat", alsoSeen = { "ENGINE_OVERHEAT" }, isDue = function(m)
        return m.enabled.transmission and m.isStarted and m.spec.transmissionTemperature > 100 and not m.isElectric and hasCVT(m) end },
    { key = "TRANSMISSION_OVERHEAT", text = "rms_tutorial_transmission_overheat", isDue = function(m)
        return m.enabled.transmission and m.isStarted and m.spec.transmissionTemperature > 100 and not m.isElectric and not hasCVT(m) end },
    { key = "FLUID_LEVEL", text = "rms_tutorial_fluid_level", isDue = function(m)
        return m.isStarted and hasLowFluid(m) end },
    { key = "EXHAUST_SMOKE", text = "rms_tutorial_exhaust_smoke", isDue = function(m)
        local smoke = m.spec.exhaustSmoke
        return m.enabled.engine and m.isStarted and smoke ~= nil and smoke.isActive == true
            and math.max(tonumber(smoke.soot) or 0, tonumber(smoke.oil) or 0, tonumber(smoke.unburnt) or 0) > 0.25 end },
    { key = "DRIVETRAIN_MODES", text = "rms_tutorial_drivetrain_modes", isDue = function(m)
        return m.isStarted and m.spec.drivetrain ~= nil and m.spec.drivetrain.hasControl == true end },
    -- One park brake tip per kind of brake, the same title
    { key = "PARK_BRAKE", text = "rms_tutorial_park_brake", isDue = function(m)
        return m.spec.drivetrain.parkKind == RMS_Drivetrain.PARK_KIND.AUTOMATIC and RMS_Drivetrain.getIsParkBrakeEngaged(m.vehicle) end },
    { key = "PARK_BRAKE_MANUAL", text = "rms_tutorial_park_brake", message = "rms_tutorial_park_brake_manual_message", isDue = function(m)
        return m.spec.drivetrain.parkKind ~= RMS_Drivetrain.PARK_KIND.AUTOMATIC and RMS_Drivetrain.getIsParkBrakeEngaged(m.vehicle) end },
    { key = "WHEEL_SLIP", text = "rms_tutorial_wheel_slip", isDue = function(m)
        local spec = m.spec
        return m.enabled.transmission and m.isStarted and spec.wheelSlipIntensity ~= nil and spec.wheelSlipIntensity > 0.9
            and spec.wheelSlipTutorialTimer ~= nil and spec.wheelSlipTutorialTimer >= 3000 end },
    { key = "DRIVETRAIN_WINDUP", text = "rms_tutorial_drivetrain_windup", isDue = function(m)
        local drivetrain = m.spec.drivetrain
        return m.enabled.transmission and m.isStarted and drivetrain ~= nil and drivetrain.diffLockEngaged == true
            and (tonumber(drivetrain.windupStress) or 0) > RMS_Config.DRIVETRAIN.WINDUP_TUTORIAL_THRESHOLD end },
    { key = "TERRAIN_IMPACT", text = "rms_tutorial_terrain_impact", isDue = function(m)
        return m.enabled.chassis and m.spec.terrainImpactTutorialTimer > 0 end },
    { key = "CHASSIS_VIBRATION", text = "rms_tutorial_chassis_vibration", getArguments = getName, isDue = function(m)
        return m.enabled.chassis and m.isStarted
            and m.spec.vibrationTutorialTimer >= RMS_Config.CORE.CHASSIS_FACTOR_DATA.VIB_TUTORIAL_MS end },
    { key = "STEERING", text = "rms_tutorial_steering", isDue = function(m)
        local steer = m.spec.chassisSteerState
        return m.enabled.chassis and m.isStarted and m.speed <= 0.1 and steer.groundContact > 0 and steer.isMoving == true end },
    { key = "PREHEAT", text = "rms_tutorial_preheat", isDue = function(m)
        return m.enabled.electrical and RMS_Preheat.isHeating(m.vehicle) end },
    { key = "CRANKING", text = "rms_tutorial_cranking", isDue = function(m)
        local timer = m.spec.systems.electrical.crankingTimer
        return m.enabled.electrical and not m.isElectric and timer ~= nil and timer >= 9000
            and not m.vehicle:hasEffect("ENGINE_HARD_START_MODIFIER") and not m.vehicle:hasEffect("GLOW_PLUG_HARD_START_MODIFIER") end },
    { key = "BATTERY_LOW", text = "rms_tutorial_battery_low", alsoSeen = { "HARD_START" }, isDue = function(m)
        return m.enabled.electrical and not m.isStarted and not m.spec.isCranking and m.vehicle:hasBreakdown("VOLTAGE_SAG") end },
    { key = "HARD_START", text = "rms_tutorial_hard_start", getArguments = getName, isDue = function(m)
        local vehicle = m.vehicle
        local isHard = vehicle:hasEffect("ENGINE_HARD_START_MODIFIER")
            or (vehicle:hasEffect("GLOW_PLUG_HARD_START_MODIFIER") and RMS_Preheat.shouldApplyGlowPlugHardStart(vehicle))
        return isEnabled(m, "engine", "electrical", "fuel") and isHard and not m.isStarted end },
    { key = "CRITICAL_FAILURE", text = "rms_tutorial_critical_failure", getArguments = getName, isDue = function(m)
        return isEnabled(m, "engine", "cooling", "electrical", "fuel") and m.vehicle:hasEffect("ENGINE_FAILURE") end },
    { key = "LOW_FUEL", text = "rms_tutorial_low_fuel", isDue = function(m)
        return m.enabled.fuel and m.isStarted and not m.isElectric
            and m.spec.fuelState.level < (RMS_Config.CORE.FUEL_FACTOR_DATA.LOW_FUEL_THRESHOLD or 0.20) end },
    { key = "IDLE_DEPOSIT", text = "rms_tutorial_idle_deposit", isDue = function(m)
        return m.enabled.fuel and m.isStarted and not m.isElectric and m.spec.fuelState.idleTimer >= 120 end },
    { key = "PTO_ENGAGEMENT", text = "rms_tutorial_pto_engagement", isDue = function(m)
        return m.enabled.pto and m.hasNewPtoShock end },
    { key = "PTO_RAISED", text = "rms_tutorial_pto_raised", isDue = function(m)
        return m.enabled.pto and m.spec.ptoRaisedTooLong == true end },
    { key = "COLD_OIL", text = "rms_tutorial_cold_oil", isDue = hasColdOil },
    { key = "SERVICE_DUE_SOON", text = "rms_tutorial_service_due_soon", getArguments = getName, isDue = function(m)
        local used = getServiceIntervalUsed(m)
        return used >= 0.9 and used < 1.0 end },
    { key = "SERVICE_INTERVAL_EXPIRED", text = "rms_tutorial_service_interval_expired", getArguments = getName, isDue = function(m)
        return getServiceIntervalUsed(m) >= 1.01 end },
    { key = "NEEDS_REPAIR", text = "rms_tutorial_needs_repair", getArguments = getName, isDue = function(m)
        return m.isStarted and m.vehicle:hasBreakdown() end },
    { key = "NEEDS_OVERHAUL", text = "rms_tutorial_needs_overhaul", getArguments = getName, isDue = function(m)
        return m.vehicle:getConditionLevel() < 0.19 end },
    { key = "NEEDS_PREVENTIVE", text = "rms_tutorial_needs_preventive", isDue = function(m)
        return m.isStarted and hasMajorServiceWear(m) end,
        getArguments = function(m)
            local interval = m.vehicle:getMaintenanceLevelInterval(RealisticMechanicalSystems.MAINTENANCE_TYPES.PREVENTIVE)
            return getName(m), RMS_Utils.formatHours(interval)
        end },
    { key = "POOR_CONSUMABLES", text = "rms_tutorial_poor_consumables", getArguments = getName, isDue = function(m)
        return m.vehicle:hasBreakdown("MAINTENANCE_WITH_POOR_QUALITY_CONSUMABLES") end },
    { key = "POOR_PARTS", text = "rms_tutorial_poor_parts", getArguments = getName, isDue = hasPoorPartsBreakdown }
}

---What the tips read of the machine; PTO events marked as seen
local function readMachine(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    local machine = {
        vehicle = vehicle,
        spec = spec,
        isStarted = vehicle:getIsMotorStarted(),
        speed = vehicle:getLastSpeed(),
        isElectric = spec.isElectricVehicle,
        enabled = {}
    }
    for systemKey, system in pairs(spec.systems or {}) do
        machine.enabled[systemKey] = type(system) == "table" and system.enabled == true
    end

    local ptoEngagementSequence = tonumber(spec.ptoEngagementSequence) or 0
    local hasNewPtoEngagement = ptoEngagementSequence > (tonumber(spec.ptoTutorialObservedSequence) or 0)
    if hasNewPtoEngagement then
        spec.ptoTutorialObservedSequence = ptoEngagementSequence
    end
    local ptoShockSequence = tonumber(spec.ptoShockSequence) or 0
    machine.hasNewPtoShock = ptoShockSequence > (tonumber(spec.ptoTutorialObservedShockSequence) or 0)
    if machine.hasNewPtoShock then
        spec.ptoTutorialObservedShockSequence = ptoShockSequence
    end
    return machine
end

---Shows the first tip not seen yet that the machine triggers
function RMS_Tutorial:showNextTip(vehicle)
    local machine = readMachine(vehicle)
    local seen = RMS_Config.TUTORIAL_MESSAGES
    for _, tip in ipairs(RMS_Tutorial.TIPS) do
        if not seen[tip.key] and tip.isDue(machine) then
            local message = g_i18n:getText(tip.message or tip.text .. "_message")
            if tip.getArguments ~= nil then
                message = string.format(message, tip.getArguments(machine))
            end
            RMS_Hud.showNotification(message, 0, g_i18n:getText(tip.text .. "_title"), true)
            seen[tip.key] = true
            for _, key in ipairs(tip.alsoSeen or {}) do
                seen[key] = true
            end
            self.messageDowntime = RMS_Tutorial.TIP_DOWNTIME
            return
        end
    end
end

---Checks the tips each step, once the pause after a tip is over
function RMS_Tutorial:update(dt)
    if g_localPlayer == nil or not RMS_Config.ensureLocalTutorialState() or not RMS_Config.TUTORIAL_MODE then
        self.vehicle, self.timer = nil, 0
        return
    end

    if g_gui:getIsGuiVisible() then
        self.vehicle = nil
        return
    end

    if RMS_Main.hud ~= nil and RMS_Main.hud:hasClosableNotification() then
        return
    end

    self.messageDowntime = math.max(self.messageDowntime - dt, 0)
    self.timer = self.timer + dt
    if self.timer < RMS_Config.TUTORIAL_UPDATE_DELAY then
        return
    end
    self.timer = self.timer % RMS_Config.TUTORIAL_UPDATE_DELAY

    self:getRMSVehicle()
    if self.messageDowntime > 0 then
        return
    end

    if not RMS_Config.WELCOME_MESSAGE_SEEN then
        self:showWelcome()
        RMS_Config.WELCOME_MESSAGE_SEEN = true
    end
    if self.vehicle ~= nil then
        self:showNextTip(self.vehicle)
    end
    -- A message just shown is saved as seen
    if self.messageDowntime > 0 then
        RMS_Config.syncTutorialState()
    end
end

addModEventListener(RMS_Tutorial)
