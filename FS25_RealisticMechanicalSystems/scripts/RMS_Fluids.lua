-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---Physical fluid catalogue, vehicle capacities, mixture compatibility and leak-loss accounting
RMS_Fluids = RMS_Fluids or {}

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
        leakEffectId = nil
    },
    coolant = {
        levelKey = "coolantLevel",
        systemKey = "cooling",
        leakEffectId = "COOLANT_LEAK_RATE"
    },
    transmissionOil = {
        levelKey = "transmissionOilLevel",
        systemKey = "transmission",
        leakEffectId = "TRANSMISSION_OIL_LEAK_RATE"
    },
    hydraulicFluid = {
        levelKey = "hydraulicFluidLevel",
        systemKey = "hydraulics",
        leakEffectId = "HYDRAULIC_FLUID_LEAK_RATE"
    }
}

RMS_Fluids.SYSTEM_TO_CIRCUIT = {
    engine = "engineOil",
    cooling = "coolant",
    transmission = "transmissionOil",
    hydraulics = "hydraulicFluid"
}

-- liters of a 100 hp machine of each family, from the real machines of docs/RMS_FLUID_CAPACITY_REFERENCES.md;
-- maxPower is twice the most powerful of them, the volumes no longer growing past it
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

-- how the volumes follow the engine power, measured on the same real machines
RMS_Fluids.PROFILE_REFERENCE_POWER = 100
RMS_Fluids.POWER_EXPONENT = 0.75
-- a fifth wheel or this empty mass in tonnes makes a road vehicle a heavy truck
RMS_Fluids.HEAVY_ROAD_VEHICLE_MASS = 5
RMS_Fluids.KW_TO_HP = 1.35962

-- store category to profile family, the road ones split on the vehicle itself
RMS_Fluids.CATEGORY_PROFILES = {
    TRACTORSS = "TRACTOR",
    TRACTORSM = "TRACTOR",
    TRACTORSL = "TRACTOR",
    HARVESTERS = "HARVESTER",
    MOWERS = "MOWER",
    MOWERVEHICLES = "MOWER",
    COMBINEWINDROWER = "MOWER",
    BALERSROUND = "MOWER",
    BALERSSQUARE = "MOWER",
    SPRAYERS = "SPRAYER",
    SPRAYERVEHICLES = "SPRAYER",
    SLURRYTANKS = "TRACTOR",
    SLURRYVEHICLES = "TRACTOR",
    MISC = "TRACTOR",
    MISCVEHICLES = "TRACTOR",
    MISCDRIVABLES = "TRACTOR",
    FORAGEMIXERS = "TRACTOR",
    FORAGEHARVESTERS = "FORAGE_HARVESTER",
    BEETVEHICLES = "ROOT_HARVESTER",
    BEETHARVESTERS = "ROOT_HARVESTER",
    POTATOVEHICLES = "ROOT_HARVESTER",
    POTATOHARVESTING = "ROOT_HARVESTER",
    BEETLOADING = "ROOT_HARVESTER",
    VEGETABLEHARVESTERS = "SPECIALTY_HARVESTER",
    SPINACHHARVESTERS = "SPECIALTY_HARVESTER",
    COTTONVEHICLES = "SPECIALTY_HARVESTER",
    COTTONHARVESTERS = "SPECIALTY_HARVESTER",
    SUGARCANEVEHICLES = "SUGARCANE_HARVESTER",
    SUGARCANEHARVESTERS = "SUGARCANE_HARVESTER",
    RICEHARVESTERS = "SPECIALTY_HARVESTER",
    RICEPLANTERS = "SPECIALTY_HARVESTER",
    PEAHARVESTERS = "SPECIALTY_HARVESTER",
    GREENBEANHARVESTERS = "SPECIALTY_HARVESTER",
    GRAPEHARVESTERS = "SPECIALTY_HARVESTER",
    GRAPEVEHICLES = "SPECIALTY_HARVESTER",
    OLIVEVEHICLES = "SPECIALTY_HARVESTER",
    OLIVEHARVESTERS = "SPECIALTY_HARVESTER",
    SKIDSTEERVEHICLES = "LOADER_COMPACT",
    FORKLIFTS = "LOADER_COMPACT",
    FRONTLOADERVEHICLES = "WHEEL_LOADER",
    TELELOADERVEHICLES = "TELEHANDLER",
    WHEELLOADERVEHICLES = "WHEEL_LOADER",
    WOODHARVESTING = "FORESTRY",
    WOODCHIPPERS = "FORESTRY",
    FORESTRYMISC = "FORESTRY",
    FORESTRYEXCAVATORS = "FORESTRY",
    FORESTRYFORWARDERS = "FORESTRY",
    FORESTRYHARVESTERS = "FORESTRY",
    CARS = "ROAD",
    TRANSPORTCARS = "ROAD",
    TRUCKS = "ROAD"
}

-- tractors are the machines whose transmission and hydraulics may share one sump; these brands keep
-- two separate oils, every other tractor shares one, checked in docs/RMS_FLUID_CAPACITY_REFERENCES.md
RMS_Fluids.TRACTOR_CATEGORIES = { TRACTORSS = true, TRACTORSM = true, TRACTORSL = true }
RMS_Fluids.SEPARATE_SUMP_TRACTOR_BRANDS = { FENDT = true, VALTRA = true, LINDNER = true }
RMS_Fluids.COMMON_SUMP_TEXT_KEY = "rms_fluid_circuit_transmissionHydraulic"

RMS_Fluids.PRODUCTS = {
    MOTOREX_FARMER_PRO_10W40 = {
        brand = "MOTOREX", name = "Farmer Pro SAE 10W/40",
        assetDirectory = "objects/fluids/products/motorexFarmerPro",
        densityKgPerLiter = 0.868,
        storePrices = { [5] = 45, [25] = 202, [200] = 1605 },
        isStoreItem = true,
        compatibleCircuits = { engineOil = true }, capacities = { 5, 25, 200 }
    },
    MOTOREX_FARMER_POLY_604 = {
        brand = "MOTOREX", name = "Farmer Poly 604",
        assetDirectory = "objects/fluids/products/motorexFarmerPoly",
        densityKgPerLiter = 0.868,
        storePrices = { [5] = 45, [25] = 208, [200] = 1665 },
        isStoreItem = true,
        compatibleCircuits = { transmissionOil = true, hydraulicFluid = true }, capacities = { 5, 25, 200 }
    },
    MOTOREX_COOLANT_M30_RTU = {
        brand = "MOTOREX", name = "Coolant M3.0 Ready To Use",
        assetDirectory = "objects/fluids/products/motorexCoolantM30",
        densityKgPerLiter = 1.070,
        storePrices = { [5] = 105, [25] = 394, [200] = 2650 },
        isStoreItem = true,
        compatibleCircuits = { coolant = true }, capacities = { 5, 25, 200 }
    },
    MOTUL_AGRI_TEKNO_10W40 = {
        brand = "MOTUL", name = "AGRI TEKNO 10W-40",
        assetDirectory = "objects/fluids/products/motulAgriTekno",
        densityKgPerLiter = 0.871,
        storePrices = { [5] = 25, [25] = 104, [200] = 835 },
        isStoreItem = true,
        compatibleCircuits = { engineOil = true }, capacities = { 5, 25, 200 }
    },
    MOTUL_TRH_97 = {
        brand = "MOTUL", name = "TRH 97",
        assetDirectory = "objects/fluids/products/motulTrh97",
        densityKgPerLiter = 0.886,
        storePrices = { [5] = 50, [25] = 229, [200] = 1725 },
        isStoreItem = true,
        compatibleCircuits = { transmissionOil = true, hydraulicFluid = true }, capacities = { 5, 25, 200 }
    },
    MOTUL_AUTO_COOL_EXPERT_37C = {
        brand = "MOTUL", name = "AUTO COOL EXPERT -37°C",
        assetDirectory = "objects/fluids/products/motulAutoCoolExpert",
        densityKgPerLiter = 1.076,
        storePrices = { [5] = 30, [25] = 123, [200] = 970 },
        isStoreItem = true,
        compatibleCircuits = { coolant = true }, capacities = { 5, 25, 200 }
    },
    FUCHS_AGRIFARM_MOT_XLA_10W40 = {
        brand = "FUCHS", name = "Agrifarm MOT X-LA 10W40",
        assetDirectory = "objects/fluids/products/fuchsMotXla",
        densityKgPerLiter = 0.859,
        storePrices = { [5] = 35, [25] = 171, [200] = 1435 },
        isStoreItem = true,
        compatibleCircuits = { engineOil = true }, capacities = { 5, 25, 200 }
    },
    FUCHS_AGRIFARM_UTTO_MP = {
        brand = "FUCHS", name = "Agrifarm UTTO MP",
        assetDirectory = "objects/fluids/products/fuchsUttoMp",
        densityKgPerLiter = 0.870,
        storePrices = { [5] = 25, [25] = 113, [200] = 910 },
        isStoreItem = true,
        compatibleCircuits = { transmissionOil = true, hydraulicFluid = true }, capacities = { 5, 25, 200 }
    },
    FUCHS_FRICOFIN_LD50 = {
        brand = "FUCHS", name = "Fricofin LD50",
        assetDirectory = "objects/fluids/products/fuchsFricofinLd50",
        densityKgPerLiter = 1.070,
        storePrices = { [5] = 35, [25] = 110, [200] = 870 },
        isStoreItem = true,
        compatibleCircuits = { coolant = true }, capacities = { 5, 25, 200 }
    }
}

RMS_Fluids.LEAK_BREAKDOWN_CIRCUITS = {
    COOLANT_LEAK = "coolant",
    TRANSMISSION_OIL_LEAK = "transmissionOil",
    HYDRAULIC_HOSE_EXTERNAL_LEAK = "hydraulicFluid"
}

RMS_Fluids._warnedUnknownVehicles = {}

local function clamp(value, minimum, maximum)
    value = tonumber(value) or minimum
    return math.max(minimum, math.min(value, maximum))
end

---Returns the circuit holding a circuit's oil, the transmission sump for the hydraulics of a common sump
-- @param table? spec vehicle spec
-- @param string circuit circuit key
-- @return string sumpCircuit circuit whose capacity, level and mixture hold the oil
local function getSpecSumpCircuit(spec, circuit)
    if circuit == "hydraulicFluid" and spec ~= nil and spec.hasCommonSump then
        return "transmissionOil"
    end
    return circuit
end

local function copyCapacities(source)
    local result = {}
    for _, circuit in ipairs(RMS_Fluids.CIRCUIT_ORDER) do
        local capacity = 0
        if source ~= nil then
            capacity = tonumber(source[circuit]) or 0
        end
        result[circuit] = math.max(capacity, 0)
    end
    return result
end

---Returns the stable catalogue key for one vehicle XML
-- @param table? vehicle vehicle
-- @return string key normalized XML key
function RMS_Fluids.getVehicleXMLKey(vehicle)
    if vehicle == nil then
        return ""
    end

    local storeItem = nil
    if g_storeManager ~= nil and vehicle.configFileName ~= nil then
        storeItem = g_storeManager:getItemByXMLFilename(vehicle.configFileName)
    end

    if storeItem ~= nil then
        local prefix = ""
        if storeItem.customEnvironment ~= nil
            and (storeItem.baseDir == nil or string.find(string.lower(storeItem.baseDir), "pdlc", 1, true) == nil) then
            prefix = tostring(storeItem.customEnvironment) .. "/"
        end
        local rawFilename = storeItem.rawXMLFilename or storeItem.xmlFilename or vehicle.configFileName or ""
        return string.lower(prefix .. string.gsub(tostring(rawFilename), "\\", "/"))
    end

    return string.lower(string.gsub(tostring(vehicle.configFileName or ""), "\\", "/"))
end

---Returns the first known store category of a vehicle
-- @param table? vehicle vehicle
-- @return string category upper-case category
function RMS_Fluids.getVehicleCategory(vehicle)
    if vehicle == nil or g_storeManager == nil or vehicle.configFileName == nil then
        return ""
    end

    local storeItem = g_storeManager:getItemByXMLFilename(vehicle.configFileName)
    if storeItem == nil then
        return ""
    end

    local categoryNames = storeItem.categoryNames
    if type(categoryNames) == "table" then
        for _, categoryName in ipairs(categoryNames) do
            local normalized = string.upper(tostring(categoryName or ""))
            if RMS_Fluids.CATEGORY_PROFILES[normalized] ~= nil then
                return normalized
            end
        end
    end

    return string.upper(tostring(storeItem.categoryName or ""))
end

---Returns the advertised power of the engine fitted, the torque curve telling it when the shop leaves it out
-- @param table vehicle vehicle
-- @return float power engine power in hp
function RMS_Fluids.getEnginePower(vehicle)
    local storeItem = g_storeManager:getItemByXMLFilename(vehicle.configFileName)
    local motorItems = storeItem ~= nil and storeItem.configurations ~= nil and storeItem.configurations.motor or nil
    local motorItem = motorItems ~= nil and vehicle.configurations ~= nil and motorItems[vehicle.configurations.motor] or nil
    if motorItem ~= nil and motorItem.power ~= nil then
        return motorItem.power
    end

    return vehicle.spec_motorized.motor.peakMotorPower * RMS_Fluids.KW_TO_HP
end

---Tells whether a road vehicle is a heavy truck, from its fifth wheel or its empty mass
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

---Tells whether a tractor's transmission and hydraulics share one sump, which its brand decides
-- @param table vehicle vehicle
-- @return boolean hasCommonSump true for one oil serving both
function RMS_Fluids.getHasCommonSump(vehicle)
    if not RMS_Fluids.TRACTOR_CATEGORIES[RMS_Fluids.getVehicleCategory(vehicle)] then
        return false
    end
    return not RMS_Fluids.SEPARATE_SUMP_TRACTOR_BRANDS[g_brandManager:getBrandByIndex(vehicle:getBrand()).name]
end

---Returns the circuit holding a circuit's oil, the transmission sump for the hydraulics of a common sump
-- @param table? vehicle vehicle
-- @param string circuit circuit key
-- @return string sumpCircuit circuit whose capacity, level and mixture hold the oil
function RMS_Fluids.getSumpCircuit(vehicle, circuit)
    return getSpecSumpCircuit(vehicle ~= nil and vehicle.spec_RealisticMechanicalSystems or nil, circuit)
end

---Returns the circuits that hold their own oil, the hydraulics of a common sump drawing on the transmission's
-- @param table vehicle vehicle
-- @return table circuits circuit keys in display order
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
-- @param string circuit circuit key
-- @param string textKey text naming the circuit on its own
-- @return string textKey text naming the circuit on this vehicle
function RMS_Fluids.getCircuitTextKey(vehicle, circuit, textKey)
    local spec = vehicle ~= nil and vehicle.spec_RealisticMechanicalSystems or nil
    if spec ~= nil and spec.hasCommonSump and getSpecSumpCircuit(spec, circuit) == "transmissionOil" then
        return RMS_Fluids.COMMON_SUMP_TEXT_KEY
    end
    return textKey
end

---Scales the volumes of a profile to an engine power, rounded to the deciliter
-- @param table profile capacity profile
-- @param float power engine power in hp
-- @return table capacities capacity by circuit
function RMS_Fluids.getProfileCapacities(profile, power)
    local scale = math.min(power, profile.maxPower) / RMS_Fluids.PROFILE_REFERENCE_POWER
    local capacities = {}
    for _, circuit in ipairs(RMS_Fluids.CIRCUIT_ORDER) do
        local exponent = profile.exponents ~= nil and profile.exponents[circuit] or RMS_Fluids.POWER_EXPONENT
        capacities[circuit] = math.floor(profile[circuit] * scale ^ exponent * 10 + 0.5) / 10
    end
    return capacities
end

---Returns the family of machines a vehicle belongs to, the road ones split on the vehicle itself
-- @param table vehicle vehicle
-- @return string profileName capacity profile name
function RMS_Fluids.getProfileName(vehicle)
    local category = RMS_Fluids.getVehicleCategory(vehicle)
    local profileName = RMS_Fluids.CATEGORY_PROFILES[category]
    if profileName == nil then
        profileName = "TRACTOR"
        local xmlKey = RMS_Fluids.getVehicleXMLKey(vehicle)
        local warningKey = xmlKey ~= "" and xmlKey or tostring(vehicle)
        -- only a machine RMS manages is worth a missing profile warning
        if not vehicle.spec_RealisticMechanicalSystems.isExcludedVehicle
            and not RMS_Fluids._warnedUnknownVehicles[warningKey] then
            RMS_Fluids._warnedUnknownVehicles[warningKey] = true
            if Logging ~= nil and Logging.warning ~= nil then
                Logging.warning("RMS: no fluid capacity profile for category '%s' (%s); using TRACTOR", category, warningKey)
            end
        end
    elseif profileName == "ROAD" then
        profileName = RMS_Fluids.getIsHeavyRoadVehicle(vehicle) and "ROAD_HEAVY" or "ROAD_LIGHT"
    end
    return profileName
end

---Resolves configured capacities before disabled systems are zeroed
-- @param table vehicle vehicle
-- @return table capacities capacity by circuit
-- @return string source override key or profile name
function RMS_Fluids.resolveCapacities(vehicle)
    local xmlKey = RMS_Fluids.getVehicleXMLKey(vehicle)
    local overrides = RMS_Config ~= nil and RMS_Config.FLUIDS ~= nil and RMS_Config.FLUIDS.CAPACITY_OVERRIDES or nil
    local override = type(overrides) == "table" and overrides[xmlKey] or nil
    if type(override) == "table" then
        return copyCapacities(override), "override:" .. xmlKey
    end

    local profileName = RMS_Fluids.getProfileName(vehicle)
    return RMS_Fluids.getProfileCapacities(RMS_Fluids.PROFILES[profileName], RMS_Fluids.getEnginePower(vehicle)), "profile:" .. profileName
end

---Initializes or restores a vehicle's physical fluid data
-- @param table vehicle vehicle
-- @param boolean? forceResolve true to replace saved capacities while preserving liters
function RMS_Fluids.initializeVehicle(vehicle, forceResolve)
    local spec = vehicle ~= nil and vehicle.spec_RealisticMechanicalSystems or nil
    if spec == nil then
        return
    end

    spec.fluidCapacities = spec.fluidCapacities or {}
    spec.fluidCompatibility = spec.fluidCompatibility or {}
    spec.fluidLeakLossDebt = spec.fluidLeakLossDebt or {}

    local resolved, source = RMS_Fluids.resolveCapacities(vehicle)
    local hasCurrentSavedCapacities = tonumber(spec.fluidCapacityVersion) == RMS_Fluids.CAPACITY_VERSION
    spec.hasCommonSump = RMS_Fluids.getHasCommonSump(vehicle)
    if spec.hasCommonSump then
        -- the sump holds both oils, and a save from before pours both circuits into it
        if spec.systems.hydraulics.enabled then
            resolved.transmissionOil = resolved.transmissionOil + resolved.hydraulicFluid
        end
        resolved.hydraulicFluid = 0

        local transmissionCapacity = math.max(tonumber(spec.fluidCapacities.transmissionOil) or 0, 0)
        local hydraulicCapacity = math.max(tonumber(spec.fluidCapacities.hydraulicFluid) or 0, 0)
        if not hasCurrentSavedCapacities and hydraulicCapacity > 0 then
            local transmissionLiters = clamp(spec.transmissionOilLevel or 1, 0, 1) * transmissionCapacity
            local hydraulicLiters = clamp(spec.hydraulicFluidLevel or 1, 0, 1) * hydraulicCapacity
            local liters = transmissionLiters + hydraulicLiters
            spec.transmissionOilLevel = liters / (transmissionCapacity + hydraulicCapacity)
            if liters > 0 then
                spec.fluidCompatibility.transmissionOil = (transmissionLiters * clamp(spec.fluidCompatibility.transmissionOil or 1, 0, 1)
                    + hydraulicLiters * clamp(spec.fluidCompatibility.hydraulicFluid or 1, 0, 1)) / liters
            end
        end
    end
    for _, circuit in ipairs(RMS_Fluids.CIRCUIT_ORDER) do
        local definition = RMS_Fluids.CIRCUITS[circuit]
        local systemData = spec.systems ~= nil and spec.systems[definition.systemKey] or nil
        local enabled = systemData ~= nil and systemData.enabled ~= false
        local oldCapacity = math.max(tonumber(spec.fluidCapacities[circuit]) or 0, 0)
        local oldLevel = clamp(spec[definition.levelKey] or 1, 0, 1)
        local newCapacity = enabled and math.max(tonumber(resolved[circuit]) or 0, 0) or 0

        -- a capacity of zero is what says the circuit is absent, its level then survives untouched
        if forceResolve == true then
            local oldLiters = oldLevel * oldCapacity
            spec.fluidCapacities[circuit] = newCapacity
            if newCapacity > 0 then
                spec[definition.levelKey] = clamp(oldLiters / newCapacity, 0, 1)
            end
        elseif not hasCurrentSavedCapacities or oldCapacity <= 0 then
            spec.fluidCapacities[circuit] = newCapacity
        elseif not enabled then
            spec.fluidCapacities[circuit] = 0
        end

        spec.fluidCompatibility[circuit] = clamp(spec.fluidCompatibility[circuit] or 1, 0, 1)
    end

    spec.fluidCapacityVersion = RMS_Fluids.CAPACITY_VERSION
    spec.fluidCapacitySource = source
    RMS_Fluids.updateEffects(vehicle)
end

---Re-resolves capacities and preserves absolute liters where possible
-- @param table vehicle vehicle
function RMS_Fluids.reinitializeVehicleCapacities(vehicle)
    RMS_Fluids.initializeVehicle(vehicle, true)
    if vehicle ~= nil and vehicle.isServer and RealisticMechanicalSystems ~= nil then
        RealisticMechanicalSystems.raiseRMSDirty(vehicle, RealisticMechanicalSystems.SYNC_GROUP.FIELDCARE)
    end
end

---Returns a circuit capacity in liters
-- @param table vehicle vehicle
-- @param string circuit circuit key
-- @return float capacity liters
function RMS_Fluids.getCapacity(vehicle, circuit)
    local spec = vehicle ~= nil and vehicle.spec_RealisticMechanicalSystems or nil
    if spec == nil or spec.fluidCapacities == nil then
        return 0
    end
    return math.max(tonumber(spec.fluidCapacities[getSpecSumpCircuit(spec, circuit)]) or 0, 0)
end

---Returns the fill level of a circuit from zero to one
-- @param table vehicle vehicle
-- @param string circuit circuit key
-- @return float level fill ratio
function RMS_Fluids.getLevel(vehicle, circuit)
    local spec = vehicle.spec_RealisticMechanicalSystems
    return clamp(spec[RMS_Fluids.CIRCUITS[getSpecSumpCircuit(spec, circuit)].levelKey] or 1, 0, 1)
end

---Returns the current circuit quantity in liters
-- @param table vehicle vehicle
-- @param string circuit circuit key
-- @return float liters current liters
function RMS_Fluids.getLiters(vehicle, circuit)
    local spec = vehicle ~= nil and vehicle.spec_RealisticMechanicalSystems or nil
    circuit = getSpecSumpCircuit(spec, circuit)
    local definition = RMS_Fluids.CIRCUITS[circuit]
    if spec == nil or definition == nil then
        return 0
    end
    return RMS_Fluids.getCapacity(vehicle, circuit) * clamp(spec[definition.levelKey] or 0, 0, 1)
end

---Returns missing liters in a circuit
-- @param table vehicle vehicle
-- @param string circuit circuit key
-- @return float liters missing liters
function RMS_Fluids.getMissingLiters(vehicle, circuit)
    return math.max(RMS_Fluids.getCapacity(vehicle, circuit) - RMS_Fluids.getLiters(vehicle, circuit), 0)
end

---Returns mixture compatibility from zero to one
-- @param table vehicle vehicle
-- @param string circuit circuit key
-- @return float compatibility compatibility ratio
function RMS_Fluids.getCompatibility(vehicle, circuit)
    local spec = vehicle ~= nil and vehicle.spec_RealisticMechanicalSystems or nil
    circuit = getSpecSumpCircuit(spec, circuit)
    return clamp(spec ~= nil and spec.fluidCompatibility ~= nil and spec.fluidCompatibility[circuit] or 1, 0, 1)
end

---Tells whether one catalogue product belongs in a circuit
-- @param string productKey product catalogue key
-- @param string circuit circuit key
-- @return boolean compatible true when specified for the circuit
function RMS_Fluids.getIsProductCompatible(productKey, circuit)
    local product = RMS_Fluids.PRODUCTS[productKey]
    return product ~= nil and product.compatibleCircuits[circuit] == true
end

---Reduces outstanding leak debts after an external top-up
-- @param table spec vehicle spec
-- @param string circuit circuit key
-- @param float liters liters added
function RMS_Fluids.reduceLeakDebt(spec, circuit, liters)
    liters = math.max(tonumber(liters) or 0, 0)
    if spec == nil or liters <= 0 or type(spec.fluidLeakLossDebt) ~= "table" then
        return
    end

    local matching = {}
    local total = 0
    for breakdownId, debt in pairs(spec.fluidLeakLossDebt) do
        if getSpecSumpCircuit(spec, RMS_Fluids.LEAK_BREAKDOWN_CIRCUITS[breakdownId]) == circuit then
            local amount = math.max(tonumber(debt) or 0, 0)
            if amount > RMS_Fluids.EPSILON then
                matching[breakdownId] = amount
                total = total + amount
            end
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
-- @param string circuit circuit key
-- @param float liters requested liters
-- @param string? productKey catalogue product, nil for guaranteed-compatible workshop fluid
-- @param boolean? skipDebtReduction true for repair compensation
-- @return float accepted accepted liters
function RMS_Fluids.addLiters(vehicle, circuit, liters, productKey, skipDebtReduction)
    local spec = vehicle ~= nil and vehicle.spec_RealisticMechanicalSystems or nil
    circuit = getSpecSumpCircuit(spec, circuit)
    local definition = RMS_Fluids.CIRCUITS[circuit]
    if spec == nil or definition == nil then
        return 0
    end

    local capacity = RMS_Fluids.getCapacity(vehicle, circuit)
    local oldLiters = RMS_Fluids.getLiters(vehicle, circuit)
    local accepted = math.min(math.max(tonumber(liters) or 0, 0), math.max(capacity - oldLiters, 0))
    if accepted <= RMS_Fluids.EPSILON or capacity <= 0 then
        return 0
    end

    local incomingCompatibility = (productKey == nil or RMS_Fluids.getIsProductCompatible(productKey, circuit)) and 1 or 0
    local oldCompatibility = RMS_Fluids.getCompatibility(vehicle, circuit)
    local newLiters = oldLiters + accepted
    spec[definition.levelKey] = clamp(newLiters / capacity, 0, 1)
    spec.fluidCompatibility[circuit] = newLiters > 0
        and clamp((oldLiters * oldCompatibility + accepted * incomingCompatibility) / newLiters, 0, 1)
        or 1

    if skipDebtReduction ~= true then
        RMS_Fluids.reduceLeakDebt(spec, circuit, accepted)
    end

    RMS_Fluids.updateEffects(vehicle)
    if vehicle.isServer and RealisticMechanicalSystems ~= nil then
        RealisticMechanicalSystems.raiseRMSDirty(vehicle, RealisticMechanicalSystems.SYNC_GROUP.FIELDCARE)
    end
    return accepted
end

---Removes fluid without changing mixture compatibility
-- @param table vehicle vehicle
-- @param string circuit circuit key
-- @param float liters requested liters
-- @return float removed removed liters
function RMS_Fluids.removeLiters(vehicle, circuit, liters)
    local spec = vehicle ~= nil and vehicle.spec_RealisticMechanicalSystems or nil
    circuit = getSpecSumpCircuit(spec, circuit)
    local definition = RMS_Fluids.CIRCUITS[circuit]
    if spec == nil or definition == nil then
        return 0
    end

    local capacity = RMS_Fluids.getCapacity(vehicle, circuit)
    local oldLiters = RMS_Fluids.getLiters(vehicle, circuit)
    local removed = math.min(math.max(tonumber(liters) or 0, 0), oldLiters)
    spec[definition.levelKey] = capacity > 0 and clamp((oldLiters - removed) / capacity, 0, 1) or 0
    return removed
end

---Replaces the complete circuit with compatible fluid and clears its leak debts
-- @param table vehicle vehicle
-- @param string circuit circuit key
function RMS_Fluids.replaceCircuit(vehicle, circuit)
    local spec = vehicle ~= nil and vehicle.spec_RealisticMechanicalSystems or nil
    circuit = getSpecSumpCircuit(spec, circuit)
    local definition = RMS_Fluids.CIRCUITS[circuit]
    if spec == nil or definition == nil then
        return
    end

    spec[definition.levelKey] = RMS_Fluids.getCapacity(vehicle, circuit) > 0 and 1 or 0
    spec.fluidCompatibility[circuit] = 1
    for breakdownId in pairs(spec.fluidLeakLossDebt or {}) do
        if getSpecSumpCircuit(spec, RMS_Fluids.LEAK_BREAKDOWN_CIRCUITS[breakdownId]) == circuit then
            spec.fluidLeakLossDebt[breakdownId] = nil
        end
    end
    RMS_Fluids.updateEffects(vehicle)
    if vehicle.isServer and RealisticMechanicalSystems ~= nil then
        RealisticMechanicalSystems.raiseRMSDirty(vehicle, RealisticMechanicalSystems.SYNC_GROUP.FIELDCARE)
    end
end

---Returns the configured leak rate of an active breakdown
-- @param string breakdownId breakdown id
-- @param table breakdown active breakdown entry
-- @param string circuit circuit key
-- @return float rate normalized circuit share per hour
function RMS_Fluids.getBreakdownLeakRate(breakdownId, breakdown, circuit)
    local definition = RMS_Fluids.CIRCUITS[circuit]
    local registry = RMS_Breakdowns ~= nil and RMS_Breakdowns.BreakdownRegistry or nil
    local breakdownDef = registry ~= nil and registry[breakdownId] or nil
    local stage = math.max(math.floor(tonumber(breakdown ~= nil and breakdown.stage or 1) or 1), 1)
    local stageDef = breakdownDef ~= nil and breakdownDef.stages ~= nil and breakdownDef.stages[stage] or nil
    if definition == nil or definition.leakEffectId == nil or stageDef == nil then
        return 0
    end

    for _, effect in ipairs(stageDef.effects or {}) do
        if effect.id == definition.leakEffectId then
            local value = type(effect.value) == "function" and effect.value() or effect.value
            return math.max(tonumber(value) or 0, 0)
        end
    end
    return 0
end

---Assigns actual lost liters to the active leak or tied dominant leaks
-- @param table vehicle vehicle
-- @param string circuit circuit key
-- @param float liters actual lost liters
function RMS_Fluids.recordLeakLoss(vehicle, circuit, liters)
    local spec = vehicle ~= nil and vehicle.spec_RealisticMechanicalSystems or nil
    liters = math.max(tonumber(liters) or 0, 0)
    if spec == nil or liters <= RMS_Fluids.EPSILON then
        return
    end

    local dominantRate = 0
    local dominantIds = {}
    for breakdownId, breakdown in pairs(spec.activeBreakdowns or {}) do
        if RMS_Fluids.LEAK_BREAKDOWN_CIRCUITS[breakdownId] == circuit and breakdown.isActive ~= false then
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
    spec.fluidLeakLossDebt = spec.fluidLeakLossDebt or {}
    for _, breakdownId in ipairs(dominantIds) do
        spec.fluidLeakLossDebt[breakdownId] = math.max(tonumber(spec.fluidLeakLossDebt[breakdownId]) or 0, 0) + share
    end
end

---Restores the unreplenished loss belonging to repaired leak breakdowns
-- @param table vehicle vehicle
-- @param table? breakdownIds repaired breakdown ids
function RMS_Fluids.restoreRepairedLeakLosses(vehicle, breakdownIds)
    local spec = vehicle ~= nil and vehicle.spec_RealisticMechanicalSystems or nil
    if spec == nil or type(breakdownIds) ~= "table" then
        return
    end

    local requestedByCircuit = {}
    for _, breakdownId in ipairs(breakdownIds) do
        local circuit = RMS_Fluids.LEAK_BREAKDOWN_CIRCUITS[breakdownId]
        if circuit ~= nil then
            requestedByCircuit[circuit] = (requestedByCircuit[circuit] or 0)
                + math.max(tonumber(spec.fluidLeakLossDebt[breakdownId]) or 0, 0)
            spec.fluidLeakLossDebt[breakdownId] = nil
        end
    end

    for circuit, requested in pairs(requestedByCircuit) do
        RMS_Fluids.addLiters(vehicle, circuit, math.min(requested, RMS_Fluids.getMissingLiters(vehicle, circuit)), nil, true)
    end
end

---Returns wear, heat and hydraulic speed consequences for compatibility
-- @param float compatibility compatibility ratio
-- @return float wearMultiplier wear multiplier
-- @return float heat heat modifier
-- @return float hydraulicSpeed hydraulic speed modifier
function RMS_Fluids.getCompatibilityConsequences(compatibility)
    local contamination = 1 - clamp(compatibility, 0, 1)
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
    local spec = vehicle ~= nil and vehicle.spec_RealisticMechanicalSystems or nil
    if spec == nil then
        return
    end

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
-- @param string systemKey system key
-- @return float multiplier wear multiplier
function RMS_Fluids.getSystemWearMultiplier(vehicle, systemKey)
    local circuit = RMS_Fluids.SYSTEM_TO_CIRCUIT[systemKey]
    if circuit == nil then
        return 1
    end
    local wearMultiplier = RMS_Fluids.getCompatibilityConsequences(RMS_Fluids.getCompatibility(vehicle, circuit))
    return wearMultiplier
end

---Adds fluid contamination to the existing breakdown hydraulic modifier
-- @param table vehicle root vehicle
-- @param float? breakdownModifier existing modifier
-- @return float modifier effective modifier
function RMS_Fluids.getHydraulicSpeedModifier(vehicle, breakdownModifier)
    local spec = vehicle ~= nil and vehicle.spec_RealisticMechanicalSystems or nil
    local fluidModifier = tonumber(spec ~= nil and spec.fluidHydraulicSpeedModifier or 0) or 0
    local currentModifier = tonumber(breakdownModifier or 0) or 0
    return math.max(currentModifier + fluidModifier, -1)
end

---Serializes leak debts deterministically
-- @param table? debts debt table
-- @return string serialized serialized debts
function RMS_Fluids.serializeLeakDebt(debts)
    if type(debts) ~= "table" or next(debts) == nil then
        return ""
    end

    local ids = {}
    for breakdownId, debt in pairs(debts) do
        if (tonumber(debt) or 0) > RMS_Fluids.EPSILON then
            table.insert(ids, breakdownId)
        end
    end
    table.sort(ids)

    local values = {}
    for _, breakdownId in ipairs(ids) do
        table.insert(values, string.format("%s:%.6f", breakdownId, tonumber(debts[breakdownId]) or 0))
    end
    return table.concat(values, ";")
end

---Deserializes leak debts
-- @param string? serialized serialized debts
-- @return table debts debt table
function RMS_Fluids.deserializeLeakDebt(serialized)
    local debts = {}
    for item in string.gmatch(tostring(serialized or ""), "[^;]+") do
        local breakdownId, valueStr = string.match(item, "^([^:]+):([%+%-%.%d]+)$")
        local value = valueStr ~= nil and tonumber(valueStr) or nil
        if breakdownId ~= nil and value ~= nil and value > RMS_Fluids.EPSILON then
            debts[breakdownId] = value
        end
    end
    return debts
end

---Builds the exact physical fluid requirements for a service
-- @param table vehicle vehicle
-- @param string serviceType service status
-- @param string? optionOne first service option
-- @param string? optionTwo second service option
-- @param table? selectedBreakdowns breakdown ids covered by a repair
-- @return table requirements ordered requirements
function RMS_Fluids.getServiceRequirements(vehicle, serviceType, optionOne, optionTwo, selectedBreakdowns)
    local requirements = {}
    local states = RealisticMechanicalSystems.STATUS

    local function append(circuit, mode, liters, breakdownIds)
        circuit = RMS_Fluids.getSumpCircuit(vehicle, circuit)
        liters = math.max(tonumber(liters) or 0, 0)
        if RMS_Fluids.getCapacity(vehicle, circuit) > 0 and liters > RMS_Fluids.EPSILON then
            table.insert(requirements, {
                circuit = circuit,
                mode = mode,
                liters = liters,
                breakdownIds = breakdownIds or {}
            })
        end
    end

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
        if optionOne == RealisticMechanicalSystems.MAINTENANCE_TYPES.STANDARD then
            appendAll(function(circuit)
                return circuit == "engineOil" and "replace" or "topUp"
            end)
        elseif optionOne == RealisticMechanicalSystems.MAINTENANCE_TYPES.EXTENDED then
            -- every oil, the coolant lasting several of these services
            appendAll(function(circuit)
                return circuit == "coolant" and "topUp" or "replace"
            end)
        elseif optionOne == RealisticMechanicalSystems.MAINTENANCE_TYPES.PREVENTIVE then
            appendAll(function()
                return "replace"
            end)
        end
    elseif serviceType == states.REPAIR then
        local spec = vehicle.spec_RealisticMechanicalSystems
        local idsByCircuit = {}
        for _, breakdownId in ipairs(selectedBreakdowns or {}) do
            local circuit = RMS_Fluids.LEAK_BREAKDOWN_CIRCUITS[breakdownId]
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
                    debt = debt + math.max(tonumber(spec.fluidLeakLossDebt[breakdownId]) or 0, 0)
                end
                append(circuit, "repair", math.min(debt, RMS_Fluids.getMissingLiters(vehicle, circuit)), ids)
            end
        end
    elseif serviceType == states.OVERHAUL then
        if optionOne == RealisticMechanicalSystems.OVERHAUL_TYPES.PARTIAL then
            local systemKey = RMS_Utils.getSystemKey(RealisticMechanicalSystems.SYSTEMS, optionTwo)
            if (systemKey == nil or systemKey == "") and type(optionTwo) == "string" then
                systemKey = string.lower(optionTwo)
            end
            local circuit = RMS_Fluids.SYSTEM_TO_CIRCUIT[systemKey]
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
-- @param table? requirements ordered requirements
function RMS_Fluids.applyServiceRequirements(vehicle, requirements)
    for _, requirement in ipairs(requirements or {}) do
        if requirement.mode == "replace" then
            RMS_Fluids.replaceCircuit(vehicle, requirement.circuit)
        elseif requirement.mode == "topUp" then
            RMS_Fluids.addLiters(vehicle, requirement.circuit, requirement.liters, nil)
        elseif requirement.mode == "repair" then
            RMS_Fluids.restoreRepairedLeakLosses(vehicle, requirement.breakdownIds)
        end
    end
end

---Returns required liters grouped by circuit
-- @param table? requirements ordered requirements
-- @return table litersByCircuit required liters
function RMS_Fluids.getRequiredLitersByCircuit(requirements)
    local result = {}
    for _, requirement in ipairs(requirements or {}) do
        result[requirement.circuit] = (result[requirement.circuit] or 0) + math.max(tonumber(requirement.liters) or 0, 0)
    end
    return result
end

---Serializes service requirements deterministically
-- @param table? requirements ordered requirements
-- @return string serialized requirements
function RMS_Fluids.serializeServiceRequirements(requirements)
    local values = {}
    for _, requirement in ipairs(requirements or {}) do
        table.insert(values, string.format(
            "%s|%s|%.6f|%s",
            tostring(requirement.circuit or ""),
            tostring(requirement.mode or ""),
            math.max(tonumber(requirement.liters) or 0, 0),
            table.concat(requirement.breakdownIds or {}, ",")
        ))
    end
    return table.concat(values, ";")
end

---Deserializes saved service requirements
-- @param string? serialized serialized requirements
-- @return table requirements ordered requirements
function RMS_Fluids.deserializeServiceRequirements(serialized)
    local requirements = {}
    for item in string.gmatch(tostring(serialized or ""), "[^;]+") do
        local circuit, mode, litersString, idsString = string.match(item, "^([^|]+)|([^|]+)|([%+%-%.%d]+)|(.*)$")
        local liters = litersString ~= nil and tonumber(litersString) or nil
        if RMS_Fluids.CIRCUITS[circuit] ~= nil
            and (mode == "replace" or mode == "topUp" or mode == "repair")
            and liters ~= nil and liters > RMS_Fluids.EPSILON then
            local ids = {}
            for breakdownId in string.gmatch(idsString or "", "[^,]+") do
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
