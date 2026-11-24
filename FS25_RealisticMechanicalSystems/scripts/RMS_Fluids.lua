-- Copyright © 2026 Squallqt. All rights reserved.

---Fluid catalogue, capacities and mixtures
RMS_Fluids = {}

RMS_Fluids.CAPACITY_VERSION = 3
RMS_Fluids.EPSILON = 0.0001

RMS_Fluids.CIRCUIT_ORDER = {
    "engineOil",
    "coolant",
    "transmissionOil",
    "hydraulicFluid"
}

RMS_Fluids.CIRCUITS = {
    engineOil = {
        levelKey = "engineOilLevel",
        systemKey = "engine",
        icon = "rms_workshopFluidIconEngineOil"
    },
    coolant = {
        levelKey = "coolantLevel",
        systemKey = "cooling",
        leakEffectId = "COOLANT_LEAK_RATE",
        icon = "rms_workshopFluidIconCoolant"
    },
    transmissionOil = {
        levelKey = "transmissionOilLevel",
        systemKey = "transmission",
        leakEffectId = "TRANSMISSION_OIL_LEAK_RATE",
        icon = "rms_workshopFluidIconTransmissionOil"
    },
    hydraulicFluid = {
        levelKey = "hydraulicFluidLevel",
        systemKey = "hydraulics",
        leakEffectId = "HYDRAULIC_FLUID_LEAK_RATE",
        icon = "rms_workshopFluidIconHydraulicFluid"
    }
}

RMS_Fluids.SYSTEM_TO_CIRCUIT = {
    engine = "engineOil",
    cooling = "coolant",
    transmission = "transmissionOil",
    hydraulics = "hydraulicFluid"
}

-- litres at PROFILE_REFERENCE_POWER hp, maxPower in hp
RMS_Fluids.PROFILES = {
    ROAD_LIGHT =          { engineOil = 5.9,  coolant = 11.0, transmissionOil = 7.1,  hydraulicFluid = 0.0,   maxPower = 950,
                            exponents = { engineOil = 0.4, coolant = 0.55, transmissionOil = 0.3 } },
    ROAD_HEAVY =          { engineOil = 11.0, coolant = 15.2, transmissionOil = 4.6,  hydraulicFluid = 9.5,   maxPower = 1220 },
    TRACTOR =             { engineOil = 9.7,  coolant = 15.0, transmissionOil = 23.0, hydraulicFluid = 34.5,  maxPower = 1384 },
    HARVESTER =           { engineOil = 10.2, coolant = 16.8, transmissionOil = 6.2,  hydraulicFluid = 17.4,  maxPower = 1580 },
    FORAGE_HARVESTER =    { engineOil = 11.8, coolant = 23.1, transmissionOil = 3.4,  hydraulicFluid = 13.5,  maxPower = 2312 },
    ROOT_HARVESTER =      { engineOil = 12.0, coolant = 15.8, transmissionOil = 2.5,  hydraulicFluid = 75.7,  maxPower = 1252 },
    SPECIALTY_HARVESTER = { engineOil = 11.4, coolant = 18.5, transmissionOil = 5.0,  hydraulicFluid = 49.9,  maxPower = 1180 },
    SUGARCANE_HARVESTER = { engineOil = 13.6, coolant = 28.4, transmissionOil = 2.9,  hydraulicFluid = 165.4, maxPower = 660 },
    SPRAYER =             { engineOil = 11.0, coolant = 13.4, transmissionOil = 3.5,  hydraulicFluid = 34.8,  maxPower = 800 },
    MOWER =               { engineOil = 13.6, coolant = 17.5, transmissionOil = 5.3,  hydraulicFluid = 35.7,  maxPower = 898 },
    LOADER_COMPACT =      { engineOil = 12.3, coolant = 14.9, transmissionOil = 41.3, hydraulicFluid = 51.8,  maxPower = 192 },
    TELEHANDLER =         { engineOil = 10.3, coolant = 16.7, transmissionOil = 7.5,  hydraulicFluid = 94.0,  maxPower = 312 },
    WHEEL_LOADER =        { engineOil = 12.4, coolant = 17.2, transmissionOil = 10.6, hydraulicFluid = 81.7,  maxPower = 666 },
    FORESTRY =            { engineOil = 15.6, coolant = 19.4, transmissionOil = 6.6,  hydraulicFluid = 123.2, maxPower = 584 }
}

RMS_Fluids.PROFILE_REFERENCE_POWER = 100
RMS_Fluids.POWER_EXPONENT = 0.75
RMS_Fluids.HEAVY_ROAD_VEHICLE_MASS = 5
RMS_Fluids.KW_TO_HP = 1.35962

RMS_Fluids.CATEGORY_PROFILES = {
    TRACTORSS = "TRACTOR",
    TRACTORSM = "TRACTOR",
    TRACTORSL = "TRACTOR",
    HARVESTERS = "HARVESTER",
    MOWERS = "MOWER",
    COMBINEWINDROWER = "MOWER",
    BALERSROUND = "MOWER",
    BALERSSQUARE = "MOWER",
    SPRAYERS = "SPRAYER",
    SLURRYTANKS = "TRACTOR",
    MISC = "TRACTOR",
    MISCDRIVABLES = "TRACTOR",
    FORAGEMIXERS = "TRACTOR",
    FORAGEHARVESTERS = "FORAGE_HARVESTER",
    BEETHARVESTERS = "ROOT_HARVESTER",
    POTATOHARVESTING = "ROOT_HARVESTER",
    BEETLOADING = "ROOT_HARVESTER",
    VEGETABLEHARVESTERS = "SPECIALTY_HARVESTER",
    SPINACHHARVESTERS = "SPECIALTY_HARVESTER",
    COTTONHARVESTERS = "SPECIALTY_HARVESTER",
    SUGARCANEHARVESTERS = "SUGARCANE_HARVESTER",
    RICEHARVESTERS = "SPECIALTY_HARVESTER",
    RICEPLANTERS = "SPECIALTY_HARVESTER",
    PEAHARVESTERS = "SPECIALTY_HARVESTER",
    GREENBEANHARVESTERS = "SPECIALTY_HARVESTER",
    GRAPEHARVESTERS = "SPECIALTY_HARVESTER",
    OLIVEHARVESTERS = "SPECIALTY_HARVESTER",
    SKIDSTEERVEHICLES = "LOADER_COMPACT",
    FORKLIFTS = "LOADER_COMPACT",
    FRONTLOADERVEHICLES = "WHEEL_LOADER",
    TELELOADERVEHICLES = "TELEHANDLER",
    WHEELLOADERVEHICLES = "WHEEL_LOADER",
    WOODCHIPPERS = "FORESTRY",
    FORESTRYMISC = "FORESTRY",
    FORESTRYEXCAVATORS = "FORESTRY",
    FORESTRYFORWARDERS = "FORESTRY",
    FORESTRYHARVESTERS = "FORESTRY",
    CARS = "ROAD",
    TRUCKS = "ROAD"
}

RMS_Fluids.TRACTOR_CATEGORIES = { TRACTORSS = true, TRACTORSM = true, TRACTORSL = true }
RMS_Fluids.SEPARATE_SUMP_TRACTOR_BRANDS = { FENDT = true, VALTRA = true, LINDNER = true }
RMS_Fluids.COMMON_SUMP_TEXT_KEY = "rms_fluid_circuit_transmissionHydraulic"

RMS_Fluids.PRODUCTS = {
    MOTOREX_FARMER_PRO_10W40 = {
        brand = "MOTOREX", name = "Farmer Pro SAE 10W/40",
        storePrices = { [5] = 47, [20] = 123, [200] = 1076 },
        isLowAsh = true,
        compatibleCircuits = { engineOil = true }, capacities = { 5, 20, 200 }
    },
    MOTOREX_FARMER_UNI_15W40 = {
        brand = "MOTOREX", name = "Farmer UNI SAE 15W/40",
        storePrices = { [5] = 37, [20] = 96, [200] = 836 },
        compatibleCircuits = { engineOil = true }, capacities = { 5, 20, 200 }
    },
    MOTOREX_FARMER_POLY_604 = {
        brand = "MOTOREX", name = "Farmer Poly 604",
        storePrices = { [5] = 50, [20] = 133, [200] = 902 },
        compatibleCircuits = { transmissionOil = true, hydraulicFluid = true }, capacities = { 5, 20, 200 }
    },
    MOTOREX_COOLANT_M30_RTU = {
        brand = "MOTOREX", name = "Coolant M3.0 Ready To Use",
        storePrices = { [5] = 29, [20] = 91, [200] = 794 },
        compatibleCircuits = { coolant = true }, capacities = { 5, 20, 200 }
    },
    MOTUL_AGRI_TEKNO_15W40 = {
        brand = "MOTUL", name = "AGRI TEKNO 15W-40",
        storePrices = { [5] = 29, [20] = 91, [208] = 827 },
        compatibleCircuits = { engineOil = true }, capacities = { 5, 20, 208 }
    },
    MOTUL_AGRI_TEKNO_LA_10W40 = {
        brand = "MOTUL", name = "AGRI TEKNO LA 10W-40",
        storePrices = { [5] = 43, [20] = 134, [208] = 1217 },
        isLowAsh = true,
        compatibleCircuits = { engineOil = true }, capacities = { 5, 20, 208 }
    },
    MOTUL_TRH_97 = {
        brand = "MOTUL", name = "TRH 97",
        storePrices = { [5] = 31, [20] = 114, [208] = 888 },
        compatibleCircuits = { transmissionOil = true, hydraulicFluid = true }, capacities = { 5, 20, 208 }
    },
    MOTUL_AUTO_COOL_EXPERT_37C = {
        brand = "MOTUL", name = "AUTO COOL EXPERT -37°C",
        storePrices = { [5] = 16, [20] = 74, [208] = 788 },
        compatibleCircuits = { coolant = true }, capacities = { 5, 20, 208 }
    },
    FUCHS_AGRIFARM_MOT_XLA_10W40 = {
        brand = "FUCHS", name = "Agrifarm MOT X-LA 10W40",
        storePrices = { [5] = 35, [20] = 109, [205] = 973 },
        isLowAsh = true,
        compatibleCircuits = { engineOil = true }, capacities = { 5, 20, 205 }
    },
    FUCHS_AGRIFARM_MOT_15W40 = {
        brand = "FUCHS", name = "Agrifarm MOT 15W-40",
        storePrices = { [5] = 25, [20] = 95, [205] = 834 },
        compatibleCircuits = { engineOil = true }, capacities = { 5, 20, 205 }
    },
    FUCHS_AGRIFARM_UTTO_MP = {
        brand = "FUCHS", name = "Agrifarm UTTO MP",
        storePrices = { [5] = 30, [20] = 95, [205] = 883 },
        compatibleCircuits = { transmissionOil = true, hydraulicFluid = true }, capacities = { 5, 20, 205 }
    },
    FUCHS_FRICOFIN_LD50 = {
        brand = "FUCHS", name = "Fricofin LD50",
        storePrices = { [5] = 22, [20] = 69, [205] = 601 },
        compatibleCircuits = { coolant = true }, capacities = { 5, 20, 205 }
    },
    TOTALENERGIES_ADBLUE = {
        brand = "TOTALENERGIES", name = "AdBlue",
        storePrices = { [10] = 13, [208] = 144, [1000] = 563 },
        compatibleCircuits = { adBlue = true }, capacities = { 10, 208, 1000 },
        formats = { [10] = "adBlueCan", [208] = "drum", [1000] = "tank" }
    }
}

-- machine tanks of the game's own fill units, poured into like a circuit
RMS_Fluids.TANKS = {
    adBlue = { fillTypeName = "DEF" }
}

RMS_Fluids._warnedUnknownVehicles = {}

-- circuit each leaking breakdown drains, read from the registry at the first need
local leakCircuits = nil

---Returns the circuit a breakdown drains, from the leak effect of its stages
-- @param string? breakdownId breakdown
-- @return string? circuit fluid circuit, nil for a breakdown without a leak
local function getLeakCircuit(breakdownId)
    if leakCircuits == nil then
        leakCircuits = {}
        for id, definition in pairs(RMS_Breakdowns.BreakdownRegistry) do
            for _, stage in ipairs(definition.stages) do
                for _, effect in ipairs(stage.effects) do
                    for circuit, circuitDefinition in pairs(RMS_Fluids.CIRCUITS) do
                        if circuitDefinition.leakEffectId == effect.id then
                            leakCircuits[id] = circuit
                        end
                    end
                end
            end
        end
    end
    return leakCircuits[breakdownId]
end

---Returns the circuit holding a circuit's oil, the common sump taking the hydraulics
-- @param table spec RMS specialization of the vehicle
-- @param string circuit fluid circuit
-- @return string circuit circuit holding the oil
local function getSpecSumpCircuit(spec, circuit)
    if circuit == "hydraulicFluid" and spec.hasCommonSump then
        return "transmissionOil"
    end
    return circuit
end

---Returns the first known store category of a vehicle
-- @param table vehicle vehicle
-- @return string category store category, upper case
function RMS_Fluids.getVehicleCategory(vehicle)
    local storeItem = g_storeManager:getItemByXMLFilename(vehicle.configFileName)
    if storeItem == nil then
        return ""
    end

    for _, categoryName in ipairs(storeItem.categoryNames) do
        if RMS_Fluids.CATEGORY_PROFILES[categoryName] ~= nil then
            return categoryName
        end
    end

    return storeItem.categoryName
end

---Returns the advertised power of the engine fitted
-- @param table vehicle vehicle
-- @return float power power (hp)
function RMS_Fluids.getEnginePower(vehicle)
    local storeItem = g_storeManager:getItemByXMLFilename(vehicle.configFileName)
    local motorItems = storeItem ~= nil and storeItem.configurations ~= nil and storeItem.configurations.motor or nil
    local motorItem = motorItems ~= nil and motorItems[vehicle.configurations.motor] or nil
    if motorItem ~= nil and motorItem.power ~= nil then
        return motorItem.power
    end

    return vehicle.spec_motorized.motor.peakMotorPower * RMS_Fluids.KW_TO_HP
end

---Tells whether a road vehicle is a heavy truck
-- @param table vehicle vehicle
-- @return boolean isHeavy true for a heavy truck
function RMS_Fluids.getIsHeavyRoadVehicle(vehicle)
    if vehicle:getDefaultMass() >= RMS_Fluids.HEAVY_ROAD_VEHICLE_MASS then
        return true
    end

    local attacherJointsSpec = vehicle.spec_attacherJoints
    if attacherJointsSpec ~= nil then
        for _, attacherJoint in ipairs(attacherJointsSpec.attacherJoints) do
            if attacherJoint.jointType == AttacherJoints.JOINTTYPE_SEMITRAILER then
                return true
            end
        end
    end

    return false
end

---Tells whether a tractor's transmission and hydraulics share one sump
-- @param table vehicle vehicle
-- @return boolean hasCommonSump true when they share one
function RMS_Fluids.getHasCommonSump(vehicle)
    if not RMS_Fluids.TRACTOR_CATEGORIES[RMS_Fluids.getVehicleCategory(vehicle)] then
        return false
    end
    return not RMS_Fluids.SEPARATE_SUMP_TRACTOR_BRANDS[g_brandManager:getBrandByIndex(vehicle:getBrand()).name]
end

---Returns the circuit holding a circuit's oil
-- @param table vehicle vehicle
-- @param string circuit fluid circuit
-- @return string circuit circuit holding the oil
function RMS_Fluids.getSumpCircuit(vehicle, circuit)
    return getSpecSumpCircuit(vehicle.spec_RealisticMechanicalSystems, circuit)
end

---Tells whether a vehicle holds a circuit of its own
-- @param table vehicle vehicle
-- @param string circuit fluid circuit
-- @return boolean hasCircuit true for a circuit of its own
function RMS_Fluids.hasCircuit(vehicle, circuit)
    return RMS_Fluids.getSumpCircuit(vehicle, circuit) == circuit and RMS_Fluids.getCapacity(vehicle, circuit) > 0
end

---Returns the circuits that hold their own oil
-- @param table vehicle vehicle
-- @return table circuits circuits in order
function RMS_Fluids.getSumpCircuits(vehicle)
    local circuits = {}
    for _, circuit in ipairs(RMS_Fluids.CIRCUIT_ORDER) do
        if RMS_Fluids.getSumpCircuit(vehicle, circuit) == circuit then
            table.insert(circuits, circuit)
        end
    end
    return circuits
end

---Returns the text naming a circuit, the common sump having its own
-- @param table? vehicle vehicle
-- @param string circuit fluid circuit
-- @param boolean? isShort true for the short name
-- @return string textKey l10n key
function RMS_Fluids.getCircuitTextKey(vehicle, circuit, isShort)
    local spec = vehicle ~= nil and vehicle.spec_RealisticMechanicalSystems or nil
    if spec ~= nil and spec.hasCommonSump and getSpecSumpCircuit(spec, circuit) == "transmissionOil" then
        return isShort and "rms_fluid_hud_transmissionHydraulic" or RMS_Fluids.COMMON_SUMP_TEXT_KEY
    end
    return "rms_fluid_circuit_" .. circuit
end

---Returns the text warning what an unsuited fluid does to a circuit
-- @param table vehicle vehicle
-- @param string circuit fluid circuit
-- @return string textKey l10n key
function RMS_Fluids.getIncompatibleMessageKey(vehicle, circuit)
    local spec = vehicle.spec_RealisticMechanicalSystems
    if spec.hasCommonSump and getSpecSumpCircuit(spec, circuit) == "transmissionOil" then
        return "rms_fluid_incompatible_message_transmissionHydraulic"
    end
    return "rms_fluid_incompatible_message_" .. circuit
end

---Scales the volumes of a profile to an engine power, rounded to the deciliter
-- @param table profile capacity profile
-- @param float power engine power (hp)
-- @return table capacities liters by circuit
function RMS_Fluids.getProfileCapacities(profile, power)
    local scale = math.min(power, profile.maxPower) / RMS_Fluids.PROFILE_REFERENCE_POWER
    local capacities = {}
    for _, circuit in ipairs(RMS_Fluids.CIRCUIT_ORDER) do
        local exponent = profile.exponents ~= nil and profile.exponents[circuit] or RMS_Fluids.POWER_EXPONENT
        capacities[circuit] = math.floor(profile[circuit] * scale ^ exponent * 10 + 0.5) / 10
    end
    return capacities
end

---Returns the family of machines a vehicle belongs to
-- @param table vehicle vehicle
-- @return string profileName capacity profile
function RMS_Fluids.getProfileName(vehicle)
    local category = RMS_Fluids.getVehicleCategory(vehicle)
    local profileName = RMS_Fluids.CATEGORY_PROFILES[category]
    if profileName == nil then
        profileName = "TRACTOR"
        local filename = vehicle.configFileName
        if not vehicle.spec_RealisticMechanicalSystems.isExcludedVehicle and not RMS_Fluids._warnedUnknownVehicles[filename] then
            RMS_Fluids._warnedUnknownVehicles[filename] = true
            Logging.warning("RMS: no fluid capacity profile for category '%s' (%s); using TRACTOR", category, filename)
        end
    elseif profileName == "ROAD" then
        profileName = RMS_Fluids.getIsHeavyRoadVehicle(vehicle) and "ROAD_HEAVY" or "ROAD_LIGHT"
    end
    return profileName
end

---Resolves the capacities of the profile before disabled systems are zeroed
-- @param table vehicle vehicle
-- @return table capacities liters by circuit
function RMS_Fluids.resolveCapacities(vehicle)
    local profileName = RMS_Fluids.getProfileName(vehicle)
    local capacities = RMS_Fluids.getProfileCapacities(RMS_Fluids.PROFILES[profileName], RMS_Fluids.getEnginePower(vehicle))
    if vehicle.spec_RealisticMechanicalSystems.isElectricVehicle then
        capacities.engineOil = 0
    end
    return capacities
end

---Initializes or restores a vehicle's physical fluid data
-- @param table vehicle vehicle
function RMS_Fluids.initializeVehicle(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    local resolved = RMS_Fluids.resolveCapacities(vehicle)
    local hasCurrentSavedCapacities = spec.fluidCapacityVersion == RMS_Fluids.CAPACITY_VERSION
    spec.hasCommonSump = RMS_Fluids.getHasCommonSump(vehicle)
    if spec.hasCommonSump then
        if spec.systems.hydraulics.enabled then
            resolved.transmissionOil = resolved.transmissionOil + resolved.hydraulicFluid
        end
        resolved.hydraulicFluid = 0
    end
    for _, circuit in ipairs(RMS_Fluids.CIRCUIT_ORDER) do
        local definition = RMS_Fluids.CIRCUITS[circuit]
        local enabled = spec.systems[definition.systemKey].enabled
        local oldCapacity = spec.fluidCapacities[circuit] or 0
        local newCapacity = enabled and resolved[circuit] or 0

        -- Capacity zero marks an absent circuit; preserve its saved level
        if not hasCurrentSavedCapacities or oldCapacity <= 0 then
            spec.fluidCapacities[circuit] = newCapacity
        elseif not enabled then
            spec.fluidCapacities[circuit] = 0
        end
    end

    spec.fluidCapacityVersion = RMS_Fluids.CAPACITY_VERSION
    RMS_Fluids.updateEffects(vehicle)
end

---Returns the fill unit of a machine tank, nil without one
-- @param table vehicle vehicle
-- @param string tank machine tank
-- @return integer? fillUnitIndex fill unit
function RMS_Fluids.getTankFillUnitIndex(vehicle, tank)
    local consumer = vehicle.spec_motorized.consumersByFillTypeName[RMS_Fluids.TANKS[tank].fillTypeName]
    return consumer ~= nil and consumer.fillUnitIndex or nil
end

---Returns a circuit capacity in liters
-- @param table vehicle vehicle
-- @param string circuit circuit or tank
-- @return float capacity capacity (l)
function RMS_Fluids.getCapacity(vehicle, circuit)
    if RMS_Fluids.TANKS[circuit] ~= nil then
        local index = RMS_Fluids.getTankFillUnitIndex(vehicle, circuit)
        return index ~= nil and math.max(vehicle:getFillUnitCapacity(index), 0) or 0
    end
    local spec = vehicle.spec_RealisticMechanicalSystems
    return spec.fluidCapacities[getSpecSumpCircuit(spec, circuit)] or 0
end

---Returns the fill level of a circuit from zero to one
-- @param table vehicle vehicle
-- @param string circuit circuit or tank
-- @return float level level, 0 to 1
function RMS_Fluids.getLevel(vehicle, circuit)
    if RMS_Fluids.TANKS[circuit] ~= nil then
        local capacity = RMS_Fluids.getCapacity(vehicle, circuit)
        return capacity > 0 and math.clamp(RMS_Fluids.getLiters(vehicle, circuit) / capacity, 0, 1) or 0
    end
    local spec = vehicle.spec_RealisticMechanicalSystems
    return spec[RMS_Fluids.CIRCUITS[getSpecSumpCircuit(spec, circuit)].levelKey]
end

RMS_Fluids.GAUGE_MIN_POSITION = 0.4
RMS_Fluids.GAUGE_MAX_POSITION = 0.8

---Reads a level on the level gauge
-- @param float level level, 0 to 1
-- @param table green rgba color of a level above the minimum mark
-- @return float fill share of the gauge filled
-- @return table color rgba color of the fill
function RMS_Fluids.getGaugeFill(level, green)
    local C = RMS_Config.FLUIDS
    local stretch = (1 - C.LEVEL_MIN_MARK) / (RMS_Fluids.GAUGE_MAX_POSITION - RMS_Fluids.GAUGE_MIN_POSITION)
    local fill = RMS_Fluids.GAUGE_MAX_POSITION - (1 - level) / stretch
    local color = level <= C.LEVEL_VERY_LOW and RMS_Breakdowns.COLORS.CRITICAL
        or level < C.LEVEL_MIN_MARK and RMS_Breakdowns.COLORS.WARNING or green
    return math.max(fill, 0), color
end

-- circuit = part an air-drawing pump of that sump fails
RMS_Fluids.PICKUP_PARTS = { engineOil = "MAIN_BEARINGS", transmissionOil = "TRANSMISSION_PUMP_MALFUNCTION",
    hydraulicFluid = "HYDRAULIC_PUMP_MALFUNCTION" }
-- order of the pumps sent to the clients
RMS_Fluids.PICKUP_CIRCUITS = { "engineOil", "transmissionOil", "hydraulicFluid" }

---Returns the tangent of the lean a sump keeps its pump covered to
-- @param float level level, 0 to 1
-- @return float margin tangent of the lean
function RMS_Fluids.getPickupMargin(level)
    local C = RMS_Config.FLUIDS
    return math.tan(math.rad(C.PICKUP_MIN_MARK_ANGLE)) * (level - C.LEVEL_CRITICALLY_LOW)
        / (C.LEVEL_MIN_MARK - C.LEVEL_CRITICALLY_LOW)
end

RMS_Fluids.PICKUP_MAX_LEAN = 10

---Returns the tangent of the lean of the oil in a sump
-- @param table vehicle vehicle
-- @return float lean tangent of the lean
function RMS_Fluids.getSumpLean(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    return math.sqrt((spec.sumpLeanX or 0) ^ 2 + (spec.sumpLeanZ or 0) ^ 2)
end

---Tells whether the pump of a sump draws air
-- @param table vehicle vehicle
-- @param string circuit fluid circuit
-- @param float lean tangent of the lean of the oil
-- @param boolean wasUncovered drawing air until now, then until the oil is back under the hysteresis
-- @return boolean isUncovered true while the pump draws air
function RMS_Fluids.getIsPickupUncovered(vehicle, circuit, lean, wasUncovered)
    local partId = RMS_Fluids.PICKUP_PARTS[circuit]
    if not RMS_Fluids.hasCircuit(vehicle, circuit) or not RMS_Breakdowns.BreakdownRegistry[partId].isApplicable(vehicle) then
        return false
    end
    local level = RMS_Fluids.getLevel(vehicle, circuit)
    if level >= RMS_Config.FLUIDS.LEVEL_MIN_MARK then
        return false
    end
    local margin = RMS_Fluids.getPickupMargin(level)
    if wasUncovered then
        return math.atan(lean) > math.atan(margin) - math.rad(RMS_Config.FLUIDS.PICKUP_HYSTERESIS_ANGLE)
    end
    return lean >= margin
end

---Follows the oil of the sumps on the server and sums the air drawn
-- @param table vehicle vehicle
-- @param float dt ms of the RMS tick, counted as air while a pump draws it
function RMS_Fluids.updatePickups(vehicle, dt)
    local spec = vehicle.spec_RealisticMechanicalSystems
    -- the slope alone, from the attitude the game holds exactly
    local _, sideY = localDirectionToWorld(vehicle.rootNode, 1, 0, 0)
    local _, upY = localDirectionToWorld(vehicle.rootNode, 0, 1, 0)
    local _, frontY = localDirectionToWorld(vehicle.rootNode, 0, 0, 1)
    local maxLean = RMS_Fluids.PICKUP_MAX_LEAN
    local leanX, leanZ = maxLean, maxLean
    if upY * maxLean > math.max(math.abs(sideY), math.abs(frontY)) then
        leanX, leanZ = -sideY / upY, -frontY / upY
    end
    local blend = spec.sumpLeanX == nil and 1 or math.min(dt / 1000 / RMS_Config.FLUIDS.PICKUP_SMOOTHING_SECONDS, 1)
    spec.sumpLeanX = (spec.sumpLeanX or 0) + (leanX - (spec.sumpLeanX or 0)) * blend
    spec.sumpLeanZ = (spec.sumpLeanZ or 0) + (leanZ - (spec.sumpLeanZ or 0)) * blend

    local lean = RMS_Fluids.getSumpLean(vehicle)
    local isTurning = vehicle:getIsMotorStarted()
    local isCounted = not RealisticMechanicalSystems.isMissionVehicle(vehicle)
    for circuit, partId in pairs(RMS_Fluids.PICKUP_PARTS) do
        local isUncovered = isTurning and RMS_Fluids.getIsPickupUncovered(vehicle, circuit, lean, spec.pickupUncovered[circuit])
        spec.pickupUncovered[circuit] = isUncovered
        if isUncovered and isCounted then
            spec.pickupAirTime[partId] = (spec.pickupAirTime[partId] or 0) + dt / 1000
        end
    end
end

---Returns the current circuit quantity in liters
-- @param table vehicle vehicle
-- @param string circuit circuit or tank
-- @return float liters liters
function RMS_Fluids.getLiters(vehicle, circuit)
    if RMS_Fluids.TANKS[circuit] ~= nil then
        local index = RMS_Fluids.getTankFillUnitIndex(vehicle, circuit)
        return index ~= nil and math.max(vehicle:getFillUnitFillLevel(index), 0) or 0
    end
    local spec = vehicle.spec_RealisticMechanicalSystems
    circuit = getSpecSumpCircuit(spec, circuit)
    return RMS_Fluids.getCapacity(vehicle, circuit) * spec[RMS_Fluids.CIRCUITS[circuit].levelKey]
end

---Returns missing liters in a circuit
-- @param table vehicle vehicle
-- @param string circuit circuit or tank
-- @return float liters liters missing
function RMS_Fluids.getMissingLiters(vehicle, circuit)
    return math.max(RMS_Fluids.getCapacity(vehicle, circuit) - RMS_Fluids.getLiters(vehicle, circuit), 0)
end

---Returns mixture compatibility from zero to one
-- @param table vehicle vehicle
-- @param string circuit fluid circuit
-- @return float compatibility compatibility, 0 to 1
function RMS_Fluids.getCompatibility(vehicle, circuit)
    local spec = vehicle.spec_RealisticMechanicalSystems
    return spec.fluidCompatibility[getSpecSumpCircuit(spec, circuit)]
end

---Tells whether one catalogue product belongs in a circuit
-- @param string productKey catalogue product
-- @param string circuit circuit or tank
-- @return boolean isCompatible true when it belongs there
function RMS_Fluids.getIsProductCompatible(productKey, circuit)
    return RMS_Fluids.PRODUCTS[productKey].compatibleCircuits[circuit] == true
end

---Tells whether AdBlue or a particulate filter asks for low ash oil
-- @param table vehicle vehicle
-- @return boolean needsLowAsh true when low ash oil is needed
function RMS_Fluids.getNeedsLowAshOil(vehicle)
    return vehicle.spec_RealisticMechanicalSystems.hasParticulateFilter == true
        or vehicle.spec_motorized.consumersByFillTypeName.DEF ~= nil
end

---Tells whether a product is the oil the machine asks for
-- @param table vehicle vehicle
-- @param string productKey catalogue product
-- @param string circuit fluid circuit
-- @return boolean isSuited true when it suits
function RMS_Fluids.getIsProductSuited(vehicle, productKey, circuit)
    return circuit ~= "engineOil" or RMS_Fluids.PRODUCTS[productKey].isLowAsh == true or not RMS_Fluids.getNeedsLowAshOil(vehicle)
end

---Returns the share of its oil interval the oil in an engine keeps
-- @param table vehicle vehicle
-- @return float share share of the interval
function RMS_Fluids.getEngineOilIntervalShare(vehicle)
    local suited = vehicle.spec_RealisticMechanicalSystems.engineOilSuitedShare
    return suited + (1 - suited) * RMS_Config.FLUIDS.UNSUITED_ENGINE_OIL_INTERVAL
end

---Reduces outstanding leak debts after an external top-up
-- @param table spec RMS specialization of the vehicle
-- @param string circuit fluid circuit
-- @param float liters liters added
function RMS_Fluids.reduceLeakDebt(spec, circuit, liters)
    local matching = {}
    local total = 0
    for breakdownId, debt in pairs(spec.fluidLeakLossDebt) do
        local leakCircuit = getLeakCircuit(breakdownId)
        -- a share split between tied leaks can stay under the epsilon
        if leakCircuit ~= nil and getSpecSumpCircuit(spec, leakCircuit) == circuit and debt > RMS_Fluids.EPSILON then
            matching[breakdownId] = debt
            total = total + debt
        end
    end

    if total <= RMS_Fluids.EPSILON then
        return
    end

    local reduction = math.min(liters, total)
    for breakdownId, amount in pairs(matching) do
        local remaining = math.max(amount - reduction * amount / total, 0)
        spec.fluidLeakLossDebt[breakdownId] = remaining > RMS_Fluids.EPSILON and remaining or nil
    end
end

---Adds fluid to a circuit and updates its weighted compatibility
-- @param table vehicle vehicle
-- @param string circuit circuit or tank
-- @param float liters liters to add
-- @param string? productKey nil for compatible workshop fluid
-- @param boolean? skipDebtReduction true to leave the leak debts as they are
-- @return float accepted liters added
function RMS_Fluids.addLiters(vehicle, circuit, liters, productKey, skipDebtReduction)
    if RMS_Fluids.TANKS[circuit] ~= nil then
        return RMS_Fluids.addTankLiters(vehicle, circuit, liters)
    end
    local spec = vehicle.spec_RealisticMechanicalSystems
    circuit = getSpecSumpCircuit(spec, circuit)
    local capacity = RMS_Fluids.getCapacity(vehicle, circuit)
    local oldLiters = RMS_Fluids.getLiters(vehicle, circuit)
    local accepted = math.min(liters, capacity - oldLiters)
    if accepted <= RMS_Fluids.EPSILON then
        return 0
    end

    local incomingCompatibility = (productKey == nil or RMS_Fluids.getIsProductCompatible(productKey, circuit)) and 1 or 0
    local oldCompatibility = RMS_Fluids.getCompatibility(vehicle, circuit)
    local newLiters = oldLiters + accepted
    spec[RMS_Fluids.CIRCUITS[circuit].levelKey] = math.clamp(newLiters / capacity, 0, 1)
    spec.fluidCompatibility[circuit] = math.clamp((oldLiters * oldCompatibility + accepted * incomingCompatibility) / newLiters, 0, 1)
    if circuit == "engineOil" then
        local isSuited = productKey == nil or RMS_Fluids.getIsProductSuited(vehicle, productKey, circuit)
        spec.engineOilSuitedShare = math.clamp((oldLiters * spec.engineOilSuitedShare + accepted * (isSuited and 1 or 0))
            / newLiters, 0, 1)
    end

    if not skipDebtReduction then
        RMS_Fluids.reduceLeakDebt(spec, circuit, accepted)
    end

    RMS_Fluids.updateEffects(vehicle)
    RealisticMechanicalSystems.raiseRMSDirty(vehicle, RealisticMechanicalSystems.SYNC_GROUP.FIELDCARE)
    return accepted
end

---Fills a machine tank through the game's fill unit, on the server
-- @param table vehicle vehicle
-- @param string tank machine tank
-- @param float liters liters to add
-- @return float added liters added
function RMS_Fluids.addTankLiters(vehicle, tank, liters)
    if liters <= RMS_Fluids.EPSILON then
        return 0
    end
    -- the game's fill unit stops at its capacity
    local fillType = g_fillTypeManager:getFillTypeIndexByName(RMS_Fluids.TANKS[tank].fillTypeName)
    return vehicle:addFillUnitFillLevel(vehicle:getOwnerFarmId(), RMS_Fluids.getTankFillUnitIndex(vehicle, tank), liters, fillType,
        ToolType.UNDEFINED, nil)
end

---Removes fluid without changing mixture compatibility
-- @param table vehicle vehicle
-- @param string circuit fluid circuit
-- @param float liters liters to remove
-- @return float removed liters removed
function RMS_Fluids.removeLiters(vehicle, circuit, liters)
    local spec = vehicle.spec_RealisticMechanicalSystems
    circuit = getSpecSumpCircuit(spec, circuit)
    local capacity = RMS_Fluids.getCapacity(vehicle, circuit)
    local oldLiters = RMS_Fluids.getLiters(vehicle, circuit)
    local removed = math.min(liters, oldLiters)
    spec[RMS_Fluids.CIRCUITS[circuit].levelKey] = capacity > 0 and math.clamp((oldLiters - removed) / capacity, 0, 1) or 0
    return removed
end

---Replaces the complete circuit with compatible fluid and clears its leak debts, on the server
-- @param table vehicle vehicle
-- @param string circuit fluid circuit
function RMS_Fluids.replaceCircuit(vehicle, circuit)
    local spec = vehicle.spec_RealisticMechanicalSystems
    circuit = getSpecSumpCircuit(spec, circuit)
    spec[RMS_Fluids.CIRCUITS[circuit].levelKey] = RMS_Fluids.getCapacity(vehicle, circuit) > 0 and 1 or 0
    spec.fluidCompatibility[circuit] = 1
    if circuit == "engineOil" then
        spec.engineOilSuitedShare = 1
    end
    for breakdownId in pairs(spec.fluidLeakLossDebt) do
        local leakCircuit = getLeakCircuit(breakdownId)
        if leakCircuit ~= nil and getSpecSumpCircuit(spec, leakCircuit) == circuit then
            spec.fluidLeakLossDebt[breakdownId] = nil
        end
    end
    RMS_Fluids.updateEffects(vehicle)
    RealisticMechanicalSystems.raiseRMSDirty(vehicle, RealisticMechanicalSystems.SYNC_GROUP.FIELDCARE)
end

---Returns the leak rate of an active breakdown on its way
-- @param string breakdownId breakdown
-- @param table breakdown state of the breakdown
-- @param string circuit fluid circuit it drains
-- @return float rate normalized circuit share per hour
function RMS_Fluids.getBreakdownLeakRate(breakdownId, breakdown, circuit)
    local leakEffectId = RMS_Fluids.CIRCUITS[circuit].leakEffectId
    local stage = RMS_Breakdowns.BreakdownRegistry[breakdownId].stages[breakdown.stage]
    for _, effect in ipairs(RMS_Utils.getBranchItems(stage.effects, breakdown)) do
        if effect.id == leakEffectId then
            return effect.value
        end
    end
    return 0
end

---Assigns actual lost liters to the active leak or tied dominant leaks
-- @param table vehicle vehicle
-- @param string circuit fluid circuit
-- @param float liters liters lost
function RMS_Fluids.recordLeakLoss(vehicle, circuit, liters)
    local spec = vehicle.spec_RealisticMechanicalSystems
    if liters <= RMS_Fluids.EPSILON then
        return
    end

    local dominantRate = 0
    local dominantIds = {}
    for breakdownId, breakdown in pairs(spec.activeBreakdowns) do
        if getLeakCircuit(breakdownId) == circuit and breakdown.isActive then
            local rate = RMS_Fluids.getBreakdownLeakRate(breakdownId, breakdown, circuit)
            if rate > dominantRate + RMS_Fluids.EPSILON then
                dominantRate = rate
                dominantIds = { breakdownId }
            elseif rate > RMS_Fluids.EPSILON and math.abs(rate - dominantRate) <= RMS_Fluids.EPSILON then
                table.insert(dominantIds, breakdownId)
            end
        end
    end

    if #dominantIds == 0 then
        return
    end

    table.sort(dominantIds)
    local share = liters / #dominantIds
    for _, breakdownId in ipairs(dominantIds) do
        spec.fluidLeakLossDebt[breakdownId] = (spec.fluidLeakLossDebt[breakdownId] or 0) + share
    end
end

---Restores the unreplenished loss belonging to repaired leak breakdowns
-- @param table vehicle vehicle
-- @param table breakdownIds breakdowns repaired
function RMS_Fluids.restoreRepairedLeakLosses(vehicle, breakdownIds)
    local spec = vehicle.spec_RealisticMechanicalSystems
    local requestedByCircuit = {}
    for _, breakdownId in ipairs(breakdownIds) do
        local circuit = getLeakCircuit(breakdownId)
        if circuit ~= nil then
            requestedByCircuit[circuit] = (requestedByCircuit[circuit] or 0) + (spec.fluidLeakLossDebt[breakdownId] or 0)
            spec.fluidLeakLossDebt[breakdownId] = nil
        end
    end

    for circuit, requested in pairs(requestedByCircuit) do
        RMS_Fluids.addLiters(vehicle, circuit, math.min(requested, RMS_Fluids.getMissingLiters(vehicle, circuit)), nil, true)
    end
end

---Returns wear, heat and hydraulic speed consequences for compatibility
-- @param float compatibility compatibility, 0 to 1
-- @return float wearMultiplier wear multiplier
-- @return float heat heat added
-- @return float hydraulicSpeed hydraulic speed modifier
function RMS_Fluids.getCompatibilityConsequences(compatibility)
    local contamination = 1 - compatibility
    local wearMultiplier = 1
    if contamination > 0.50 then
        wearMultiplier = 2.0 + (contamination - 0.50) / 0.50
    elseif contamination > 0.10 then
        wearMultiplier = 1.33 + 0.67 * (contamination - 0.10) / 0.40
    elseif contamination > 0.01 then
        wearMultiplier = 1.0 + 0.33 * (contamination - 0.01) / 0.09
    end

    local heat = 0
    local hydraulicSpeed = 0
    if contamination > 0.50 then
        local ratio = (contamination - 0.50) / 0.50
        heat = 0.10 + 0.10 * ratio
        hydraulicSpeed = -0.10 - 0.15 * ratio
    elseif contamination > 0.10 then
        local ratio = (contamination - 0.10) / 0.40
        heat = 0.10 * ratio
        hydraulicSpeed = -0.10 * ratio
    end

    return wearMultiplier, heat, hydraulicSpeed
end

---Updates effects derived from the four mixture compatibilities
-- @param table vehicle vehicle
function RMS_Fluids.updateEffects(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    local _, engineHeat = RMS_Fluids.getCompatibilityConsequences(RMS_Fluids.getCompatibility(vehicle, "engineOil"))
    local _, coolantHeat = RMS_Fluids.getCompatibilityConsequences(RMS_Fluids.getCompatibility(vehicle, "coolant"))
    local _, transmissionHeat = RMS_Fluids.getCompatibilityConsequences(RMS_Fluids.getCompatibility(vehicle, "transmissionOil"))
    local _, hydraulicHeat, hydraulicSpeed = RMS_Fluids.getCompatibilityConsequences(RMS_Fluids.getCompatibility(vehicle, "hydraulicFluid"))
    spec.fluidEngineHeat = engineHeat + coolantHeat
    spec.fluidTransmissionHeat = transmissionHeat
    spec.fluidHydraulicHeat = hydraulicHeat
    spec.fluidHydraulicSpeedModifier = hydraulicSpeed
end

---Returns the targeted wear multiplier for a system
-- @param table vehicle vehicle
-- @param string systemKey key of the system
-- @return float multiplier wear multiplier
function RMS_Fluids.getSystemWearMultiplier(vehicle, systemKey)
    local circuit = RMS_Fluids.SYSTEM_TO_CIRCUIT[systemKey]
    if circuit == nil then
        return 1
    end
    local wearMultiplier = RMS_Fluids.getCompatibilityConsequences(RMS_Fluids.getCompatibility(vehicle, circuit))
    return wearMultiplier
end

---Adds a contaminated or air-drawing fluid to the breakdown modifier
-- @param table vehicle vehicle
-- @param float breakdownModifier modifier of the breakdowns
-- @return float modifier hydraulic speed modifier, -1 at least
function RMS_Fluids.getHydraulicSpeedModifier(vehicle, breakdownModifier)
    local spec = vehicle.spec_RealisticMechanicalSystems
    local fluidModifier = spec.fluidHydraulicSpeedModifier
    if spec.pickupUncovered.hydraulicFluid then
        fluidModifier = fluidModifier - (1 - RMS_Config.FLUIDS.PICKUP_HYDRAULIC_SPEED)
    end
    return math.max(breakdownModifier + fluidModifier, -1)
end

---Serializes leak debts deterministically
-- @param table debts leak debts
-- @return string serialized serialized debts
function RMS_Fluids.serializeLeakDebt(debts)
    local ids = {}
    for breakdownId, debt in pairs(debts) do
        if debt > RMS_Fluids.EPSILON then
            table.insert(ids, breakdownId)
        end
    end
    table.sort(ids)

    local values = {}
    for _, breakdownId in ipairs(ids) do
        table.insert(values, string.format("%s:%.6f", breakdownId, debts[breakdownId]))
    end
    return table.concat(values, ";")
end

---Deserializes leak debts
-- @param string serialized serialized debts
-- @return table debts leak debts
function RMS_Fluids.deserializeLeakDebt(serialized)
    local debts = {}
    for item in string.gmatch(serialized, "[^;]+") do
        local breakdownId, valueStr = string.match(item, "^([^:]+):([%+%-%.%d]+)$")
        local value = valueStr ~= nil and tonumber(valueStr) or nil
        if breakdownId ~= nil and value ~= nil and value > RMS_Fluids.EPSILON then
            debts[breakdownId] = value
        end
    end
    return debts
end

local MAINTENANCE_CHANGES = {
    STANDARD = { engineOil = true },
    EXTENDED = { engineOil = true, transmissionOil = true, hydraulicFluid = true },
    PREVENTIVE = { engineOil = true, transmissionOil = true, hydraulicFluid = true, coolant = true }
}

---Returns what a maintenance level does to a circuit
-- @param string maintenanceType RealisticMechanicalSystems.MAINTENANCE_TYPES
-- @param string circuit fluid circuit
-- @return string mode "replace" or "topUp"
function RMS_Fluids.getMaintenanceMode(maintenanceType, circuit)
    local level = RMS_Utils.getKeyByValue(RealisticMechanicalSystems.MAINTENANCE_TYPES, maintenanceType)
    return MAINTENANCE_CHANGES[level][circuit] and "replace" or "topUp"
end

---Builds the exact physical fluid requirements for a service
-- @param table vehicle vehicle
-- @param string serviceType RealisticMechanicalSystems.STATUS of the service
-- @param string? optionOne first option of the service
-- @param string? optionTwo second option of the service
-- @param table? selectedBreakdowns breakdowns a repair fixes
-- @return table requirements fluid requirements
function RMS_Fluids.getServiceRequirements(vehicle, serviceType, optionOne, optionTwo, selectedBreakdowns)
    local requirements = {}
    local states = RealisticMechanicalSystems.STATUS

    ---Adds a requirement on the circuit holding the oil, when it has liters
    -- @param string circuit fluid circuit
    -- @param string mode "topUp", "replace" or "repair"
    -- @param float liters liters
    -- @param table? breakdownIds breakdowns of a repair
    local function append(circuit, mode, liters, breakdownIds)
        circuit = RMS_Fluids.getSumpCircuit(vehicle, circuit)
        if RMS_Fluids.getCapacity(vehicle, circuit) > 0 and liters > RMS_Fluids.EPSILON then
            table.insert(requirements, {
                circuit = circuit,
                mode = mode,
                liters = liters,
                breakdownIds = breakdownIds or {}
            })
        end
    end

    ---Adds a top up or a change of every circuit, as the mode of each says
    -- @param function modeForCircuit returns the mode of a circuit
    local function appendAll(modeForCircuit)
        for _, circuit in ipairs(RMS_Fluids.getSumpCircuits(vehicle)) do
            local mode = modeForCircuit(circuit)
            if mode == "replace" then
                append(circuit, mode, RMS_Fluids.getCapacity(vehicle, circuit))
            elseif mode == "topUp" then
                append(circuit, mode, RMS_Fluids.getMissingLiters(vehicle, circuit))
            end
        end
    end

    if serviceType == states.REFILL then
        appendAll(function()
            return "topUp"
        end)
    elseif serviceType == states.MAINTENANCE then
        appendAll(function(circuit)
            return RMS_Fluids.getMaintenanceMode(optionOne, circuit)
        end)
    elseif serviceType == states.REPAIR then
        local spec = vehicle.spec_RealisticMechanicalSystems
        local idsByCircuit = {}
        for _, breakdownId in ipairs(selectedBreakdowns or {}) do
            local circuit = getLeakCircuit(breakdownId)
            if circuit ~= nil then
                circuit = RMS_Fluids.getSumpCircuit(vehicle, circuit)
                idsByCircuit[circuit] = idsByCircuit[circuit] or {}
                table.insert(idsByCircuit[circuit], breakdownId)
            end
        end

        for _, circuit in ipairs(RMS_Fluids.CIRCUIT_ORDER) do
            local ids = idsByCircuit[circuit]
            if ids ~= nil then
                table.sort(ids)
                local debt = 0
                for _, breakdownId in ipairs(ids) do
                    debt = debt + (spec.fluidLeakLossDebt[breakdownId] or 0)
                end
                append(circuit, "repair", math.min(debt, RMS_Fluids.getMissingLiters(vehicle, circuit)), ids)
            end
        end
    elseif serviceType == states.OVERHAUL then
        if optionOne == RealisticMechanicalSystems.OVERHAUL_TYPES.PARTIAL then
            local circuit = RMS_Fluids.SYSTEM_TO_CIRCUIT[RMS_Utils.getSystemKey(RealisticMechanicalSystems.SYSTEMS, optionTwo)]
            if circuit ~= nil then
                append(circuit, "replace", RMS_Fluids.getCapacity(vehicle, circuit))
            end
        else
            appendAll(function()
                return "replace"
            end)
        end
    end

    return requirements
end

---Applies fluid work already reserved at service start
-- @param table vehicle vehicle
-- @param table requirements fluid requirements
function RMS_Fluids.applyServiceRequirements(vehicle, requirements)
    for _, requirement in ipairs(requirements) do
        if requirement.mode == "replace" then
            RMS_Fluids.replaceCircuit(vehicle, requirement.circuit)
        elseif requirement.mode == "topUp" then
            RMS_Fluids.addLiters(vehicle, requirement.circuit, requirement.liters, nil)
        else
            RMS_Fluids.restoreRepairedLeakLosses(vehicle, requirement.breakdownIds)
        end
    end
end

---Returns required liters grouped by circuit
-- @param table requirements fluid requirements
-- @return table liters liters by circuit
function RMS_Fluids.getRequiredLitersByCircuit(requirements)
    local result = {}
    for _, requirement in ipairs(requirements) do
        result[requirement.circuit] = (result[requirement.circuit] or 0) + requirement.liters
    end
    return result
end

---Serializes service requirements deterministically
-- @param table requirements fluid requirements
-- @return string serialized serialized requirements
function RMS_Fluids.serializeServiceRequirements(requirements)
    local values = {}
    for _, requirement in ipairs(requirements) do
        table.insert(values, string.format("%s|%s|%.6f|%s", requirement.circuit, requirement.mode, requirement.liters,
            table.concat(requirement.breakdownIds, ",")))
    end
    return table.concat(values, ";")
end

---Deserializes saved service requirements
-- @param string serialized serialized requirements
-- @return table requirements fluid requirements
function RMS_Fluids.deserializeServiceRequirements(serialized)
    local requirements = {}
    for item in string.gmatch(serialized, "[^;]+") do
        local circuit, mode, litersString, idsString = string.match(item, "^([^|]+)|([^|]+)|([%+%-%.%d]+)|(.*)$")
        local liters = litersString ~= nil and tonumber(litersString) or nil
        if RMS_Fluids.CIRCUITS[circuit] ~= nil
            and (mode == "replace" or mode == "topUp" or mode == "repair")
            and liters ~= nil and liters > RMS_Fluids.EPSILON then
            local ids = {}
            for breakdownId in string.gmatch(idsString, "[^,]+") do
                table.insert(ids, breakdownId)
            end
            table.insert(requirements, {
                circuit = circuit,
                mode = mode,
                liters = liters,
                breakdownIds = ids
            })
        end
    end
    return requirements
end
