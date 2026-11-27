-- Copyright © 2026 Squallqt. All rights reserved.

---Harvest load of the engine
RMS_HarvestLoad = {}

---Checks if all prerequisite specializations are loaded
-- @param table specializations specializations
-- @return boolean hasPrerequisite true if all prerequisite specializations are loaded
function RMS_HarvestLoad.prerequisitesPresent(specializations)
    return SpecializationUtil.hasSpecialization(Combine, specializations)
end

---Registers the event listeners
-- @param table vehicleType vehicle type
function RMS_HarvestLoad.registerEventListeners(vehicleType)
    SpecializationUtil.registerEventListener(vehicleType, "onLoad", RMS_HarvestLoad)
    SpecializationUtil.registerEventListener(vehicleType, "onUpdateTick", RMS_HarvestLoad)
end

---Called on loading
-- @param table? savegame savegame
function RMS_HarvestLoad:onLoad(savegame)
    if not self.isServer or not RMS_Drivetrain.getIsInCategories(self, RMS_Config.CORE.HARVEST_FACTOR_DATA.KINDS) then
        SpecializationUtil.removeEventListener(self, "onUpdateTick", RMS_HarvestLoad)
    end
end

---Returns the harvest power over the engine power
-- @param table harvester harvester
-- @return float? load harvest load, nil to keep the game's load
-- @return boolean? isSmoothed true for the load of the harvesting mod, which smooths it itself
function RMS_HarvestLoad.getHarvestLoad(harvester)
    local rootSpec = harvester.rootVehicle.spec_RealisticMechanicalSystems
    if rootSpec == nil or rootSpec.isExcludedVehicle then
        return nil
    end
    local api = RMS_Utils.getHarvestModApi()
    if api ~= nil and api.isRHMActive(harvester) then
        if RMS_Utils.getIsHarvestModArcade() then
            return nil
        end
        return api.getEngineLoad(harvester) / 100, true
    end
    local spec = harvester.spec_RealisticMechanicalSystems
    local state = spec ~= nil and spec.harvestState or nil
    if state == nil or state.powerKw == nil then
        return nil
    end
    return state.powerKw * RMS_Fluids.KW_TO_HP / state.enginePowerHp, false
end

---Follows the harvest load, then the load shown
-- @param table harvester harvester
-- @param float dt time since the last tick (ms)
local function updateHarvestLoad(harvester, dt)
    local spec = harvester.spec_rmsHarvestLoad
    local load, isSmoothed = RMS_HarvestLoad.getHarvestLoad(harvester)
    if load == nil or not harvester:getIsTurnedOn() then
        spec.measuredLoad, spec.askedLoad, spec.shownLoad = nil, nil, nil
        return
    end
    local C = RMS_Config.CORE.HARVEST_FACTOR_DATA
    if isSmoothed then
        spec.askedLoad = load
    else
        spec.measuredLoad = (spec.measuredLoad or 0) * (1 - C.LOAD_TICK_SHARE) + load * C.LOAD_TICK_SHARE
        local step = dt * 0.001 / C.FILL_TIME
        spec.askedLoad = (spec.askedLoad or 0) + math.clamp(spec.measuredLoad - (spec.askedLoad or 0), -step, step)
    end
    local isStopped = spec.askedLoad == 0 and harvester:getLastSpeed() < C.SHOWN_LOAD_STOP_SPEED
    local tau = isStopped and C.SHOWN_LOAD_STOP_TAU or RMS_Config.CORE.ENGINE_FACTOR_DATA.SHOWN_LOAD_TAU
    spec.shownLoad = (spec.shownLoad or 0) + (spec.askedLoad - (spec.shownLoad or 0)) * (1 - math.exp(-dt * 0.001 / tau))
end

---Called on update tick
-- @param float dt time since the last tick (ms)
function RMS_HarvestLoad:onUpdateTick(dt)
    updateHarvestLoad(self, dt)
end

---Returns the harvest load of an engine, its harvesters' together
-- @param table vehicle motorized vehicle
-- @return float? load harvest load, nil while no harvest loads the engine
function RMS_HarvestLoad.getEngineLoad(vehicle)
    local load = nil
    for _, child in ipairs(vehicle.childVehicles) do
        local spec = child.spec_rmsHarvestLoad
        if spec ~= nil and spec.shownLoad ~= nil then
            load = (load or 0) + spec.shownLoad
        end
    end
    return load
end
