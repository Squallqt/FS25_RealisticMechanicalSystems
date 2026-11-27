-- Copyright © 2026 Squallqt. All rights reserved.

---Fuel a machine burnt since its trip reset, and the ground it worked
RMS_TripFuel = {}

-- km/h under which no ground is counted
RMS_TripFuel.MIN_WORK_SPEED = 0.9
RMS_TripFuel.WIDTH_REFRESH_MS = 1000

---Clears the counters, with the trip meter
-- @param table spec RMS specialization of the vehicle
function RMS_TripFuel.reset(spec)
    spec.tripFuelLitres, spec.tripEngineTime = 0, 0
    spec.tripWorkFuelLitres, spec.tripWorkedHectares = 0, 0
    spec.tripWidthTimer = 0
    spec.tripBurnRate = spec.tripBurnRate or 0
end

---Tells whether a work area works the field, not a straw spreader
-- @param table area work area
-- @return boolean isField true for a field area
local function isFieldArea(area)
    -- the Straw Harvest pellet press picks up its swaths as a baler
    return g_workAreaTypeManager:getWorkAreaTypeIsSteeringAssistArea(area.type) or area.type == WorkAreaType.PELLETIZER
end

---Tells whether an implement of the combination works its ground
-- @param table vehicle vehicle
-- @return boolean isWorking true while one works
local function getIsWorking(vehicle)
    for _, child in ipairs(vehicle.rootVehicle.childVehicles) do
        local workArea = child.spec_workArea
        if workArea ~= nil then
            for _, area in ipairs(workArea.workAreas) do
                if isFieldArea(area) and child:getIsWorkAreaActive(area) then
                    return true
                end
            end
        end
    end
    return false
end

---Returns the working width of the combination, in metres
-- @param table vehicle vehicle
-- @return float width width (m)
local function getWorkingWidth(vehicle)
    local root = vehicle.rootVehicle
    local width = root.getAttacherToolWorkingWidth ~= nil and root:getAttacherToolWorkingWidth() or 0
    if width > 0 then
        return width
    end
    for _, child in ipairs(root.childVehicles) do
        for _, area in ipairs(child.spec_workArea ~= nil and child.spec_workArea.workAreas or {}) do
            if isFieldArea(area) then
                width = math.max(width, area.workWidth)
            end
        end
    end
    return width
end

---Returns the consumer the game reports as its fuel usage
-- @param table motorized motorized specialization
-- @return table? consumer fuel consumer
local function getFuelConsumer(motorized)
    local consumers = motorized.consumersByFillType
    return consumers[FillType.DIESEL] or consumers[FillType.ELECTRICCHARGE] or consumers[FillType.METHANE]
end

---Counts the fuel the engine burns, and the ground it works
-- @param table vehicle vehicle
-- @param function superFunc original function
-- @param float dt time since the last frame (ms)
-- @param float accInput accelerator input
-- @return any result what the game's function returns, on a vehicle RMS leaves alone
function RMS_TripFuel.updateConsumers(vehicle, superFunc, dt, accInput)
    local spec, motorized = vehicle.spec_RealisticMechanicalSystems, vehicle.spec_motorized
    local fuel = getFuelConsumer(motorized)
    if spec.isExcludedVehicle or fuel == nil then
        return superFunc(vehicle, dt, accInput)
    end
    local pending = fuel.fillLevelToChange
    superFunc(vehicle, dt, accInput)
    local litres = fuel.fillLevelToChange - pending
    if litres < 0 then
        -- the game empties its litre: this frame burnt as the one before
        litres = spec.tripBurnRate * dt
        motorized.lastFuelUsage = spec.tripBurnRate * 3600000
    else
        spec.tripBurnRate = litres / dt
    end
    spec.tripFuelLitres = spec.tripFuelLitres + litres
    spec.tripEngineTime = spec.tripEngineTime + dt

    local speed = vehicle:getLastSpeed()
    if speed <= RMS_TripFuel.MIN_WORK_SPEED or not getIsWorking(vehicle) then
        spec.tripWidthTimer = 0
        return
    end
    spec.tripWidthTimer = spec.tripWidthTimer - dt
    if spec.tripWidthTimer <= 0 then
        spec.tripWidthTimer = RMS_TripFuel.WIDTH_REFRESH_MS
        spec.tripWorkingWidth = getWorkingWidth(vehicle)
    end
    if spec.tripWorkingWidth <= 0 then
        return
    end
    -- km travelled times metres of width, in hectares
    spec.tripWorkedHectares = spec.tripWorkedHectares + speed * dt / 3600000 * spec.tripWorkingWidth / 10
    spec.tripWorkFuelLitres = spec.tripWorkFuelLitres + litres
end

---Returns the litres an hour of engine burnt since the reset, nil before
-- @param table spec RMS specialization of the vehicle
-- @return float? litres litres per hour
function RMS_TripFuel.getAveragePerHour(spec)
    return spec.tripEngineTime > 0 and spec.tripFuelLitres / spec.tripEngineTime * 3600000 or nil
end

---Returns the litres a worked hectare took since the reset, nil before
-- @param table spec RMS specialization of the vehicle
-- @return float? litres litres per hectare
function RMS_TripFuel.getAveragePerArea(spec)
    return spec.tripWorkedHectares > 0 and spec.tripWorkFuelLitres / spec.tripWorkedHectares or nil
end
