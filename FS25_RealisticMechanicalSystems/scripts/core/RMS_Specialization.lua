-- Copyright © 2026 Squallqt. All rights reserved.

---RMS vehicle specialization.
RealisticMechanicalSystems = {
    -- service status of a vehicle
    STATUS = {
        READY = 'rms_spec_state_ready',
        INSPECTION = 'rms_spec_state_inspection',
        MAINTENANCE = 'rms_spec_state_maintenance',
        REPAIR = 'rms_spec_state_repair',
        REFILL = 'rms_spec_state_refill',
        OVERHAUL = 'rms_spec_state_overhaul',
        BODYWORK = 'button_repaint',
        REMAP = 'rms_spec_state_remap',
        BROKEN = 'rms_spec_state_broken'
    },

    LOG_DIAGNOSTIC_READING = 'rms_diagnostic_log_title',

    STATES = {
        EXCELLENT = 'rms_spec_state_excellent',
        GOOD = 'rms_spec_state_good',
        SERVICE_GOOD = 'rms_spec_state_service_good',
        NORMAL = 'rms_spec_state_normal',
        BAD = 'rms_spec_state_bad',
        TERRIBLE = 'rms_spec_state_terrible',
        UNKNOWN = 'rms_spec_state_unknown',
        OPTIMAL = "rms_spec_state_optimal",
        RECOMMENDED = "rms_spec_state_recommended",
        REQUIRED = "rms_spec_state_required",
        OVERDUE = "rms_spec_state_overdue",
    },

    -- network sync groups, one bit each in the dirty mask
    SYNC_GROUP = {
        STATE = 1,
        SERVICE_CONTEXT = 2,
        TELEMETRY = 4,
        THERMAL = 8,
        ELECTRICAL = 16,
        FIELDCARE = 32,
        WEAR = 64,
        BREAKDOWNS = 128,
        SERVICE_PROGRESS = 256,
        TUTORIAL_DATA = 512,
        DRIVETRAIN = 1024,
        RESALE = 2048
    },

    -- a harvester carries the harvest system in place of the PTO
    SYSTEMS = {
        ENGINE = "rms_spec_system_engine",
        TRANSMISSION = "rms_spec_system_transmission",
        HYDRAULICS = "rms_spec_system_hydraulics",
        COOLING = "rms_spec_system_cooling",
        ELECTRICAL = "rms_spec_system_electrical",
        CHASSIS = "rms_spec_system_chassis",
        FUEL = "rms_spec_system_fuel",
        PTO = "rms_spec_system_pto",
        HARVEST = "rms_spec_system_harvest"
    },

    BREAKDOWN_SOURCES = {
        RANDOM = 1,
        POOR_PARTS = 2,
        QUICK_FIX = 3
    },

    WORKSHOP = {
    DEALER  = "rms_spec_workshop_dealer",
    MOBILE  = "rms_spec_workshop_mobile",
    OWN     = "rms_spec_workshop_own",
    },

    PART_TYPES = {
    OEM         = "rms_spec_part_types_oem",
    USED        = "rms_spec_part_types_used",
    AFTERMARKET = "rms_spec_part_types_aftermarket",
    },

    INSPECTION_TYPES = {
    STANDARD = "rms_spec_inspection_standard",
    VISUAL   = "rms_spec_inspection_visual",
    COMPLETE = "rms_spec_inspection_complete",
    },

    MAINTENANCE_TYPES = {
    STANDARD = "rms_spec_maintenance_standard",
    EXTENDED = "rms_spec_maintenance_extended",
    PREVENTIVE = "rms_spec_maintenance_preventive",
    },

    REPAIR_TYPES = {
    LOW    = "rms_spec_repair_type_fix",
    MEDIUM = "rms_spec_repair_type_replacement",
    HIGH = "rms_spec_repair_type_advanced",
    },

    OVERHAUL_TYPES = {
    STANDARD = "rms_spec_overhaul_standard",
    PARTIAL  = "rms_spec_overhaul_partial",
    FULL     = "rms_spec_overhaul_full",
    },

    TRANSMISSION_TYPES = {
    MANUAL      = "manual",
    MANUAL_POWERSHIFT = "manual_powershift",
    AUTOMATIC   = "automatic",
    POWERSHIFT  = "powershift",
    VARIABLE    = "variable",
    CVT         = "variable",
    UNKNOWN     = "unknown",
    },
}

-- display order of the vehicle systems
RealisticMechanicalSystems.SYSTEMS_ORDER = {
    RealisticMechanicalSystems.SYSTEMS.ENGINE,
    RealisticMechanicalSystems.SYSTEMS.TRANSMISSION,
    RealisticMechanicalSystems.SYSTEMS.HYDRAULICS,
    RealisticMechanicalSystems.SYSTEMS.COOLING,
    RealisticMechanicalSystems.SYSTEMS.ELECTRICAL,
    RealisticMechanicalSystems.SYSTEMS.CHASSIS,
    RealisticMechanicalSystems.SYSTEMS.FUEL,
    RealisticMechanicalSystems.SYSTEMS.PTO,
    RealisticMechanicalSystems.SYSTEMS.HARVEST
}

RealisticMechanicalSystems.SERVICE_CLOCKS = {
    { key = "engine", levelKey = "serviceLevel", intervalFactor = 1, maintenanceType = "STANDARD", circuits = { "engineOil" }, systems = { "engine", "fuel" } },
    { key = "transmission", levelKey = "transmissionServiceLevel", intervalFactor = 2, maintenanceType = "EXTENDED", circuits = { "transmissionOil" }, systems = { "transmission", "pto" } },
    { key = "hydraulic", levelKey = "hydraulicServiceLevel", intervalFactor = 2, maintenanceType = "EXTENDED", circuits = { "hydraulicFluid" }, systems = { "hydraulics" } },
    { key = "coolant", levelKey = "coolantServiceLevel", intervalFactor = 4, maintenanceType = "PREVENTIVE", circuits = { "coolant" }, systems = { "cooling" } }
}

-- the harvest organs among them are renewed and billed when worn
RealisticMechanicalSystems.MAJOR_SERVICE_CHECKS = { "INLET_VALVES", "EXHAUST_VALVES", "FUEL_INJECTOR_MALFUNCTION", "THERMOSTAT_MALFUNCTION",
    "FEEDER_CHAIN_WEAR", "FEED_ACCELERATOR_WEAR", "THRESHING_BAR_WEAR", "CONCAVE_WEAR", "SEPARATION_WEAR", "CLEANING_SIEVE_WEAR",
    "GRAIN_ELEVATOR_WEAR", "STRAW_CHOPPER_WEAR", "FEED_ROLL_WEAR", "CUTTERHEAD_WEAR", "FORAGE_KNIFE_WEAR", "SHEAR_BAR_WEAR",
    "CROP_PROCESSOR_WEAR", "CROP_ACCELERATOR_WEAR", "DISCHARGE_SPOUT_WEAR", "BEET_TOPPER_WEAR", "LIFTING_SHARE_WEAR",
    "BEET_CLEANING_WEAR", "ROOT_ELEVATOR_WEAR", "HOPPER_FLOOR_WEAR", "SIEVE_WEB_WEAR", "HAULM_SEPARATOR_WEAR", "PICKING_UNIT_WEAR",
    "COTTON_FAN_WEAR", "BASE_CUTTER_WEAR", "CANE_FEED_ROLL_WEAR", "CANE_CHOPPER_WEAR", "CANE_EXTRACTOR_WEAR", "CANE_ELEVATOR_WEAR",
    "SHAKER_WEAR", "CATCHING_SCALE_WEAR", "BUCKET_CONVEYOR_WEAR", "CLEANING_FAN_WEAR", "DESTEMMER_WEAR", "VEGETABLE_PICKER_WEAR",
    "VEGETABLE_CLEANING_WEAR", "VEGETABLE_ELEVATOR_WEAR" }

RealisticMechanicalSystems.PART_TYPES_ORDER = {
    RealisticMechanicalSystems.PART_TYPES.USED,
    RealisticMechanicalSystems.PART_TYPES.AFTERMARKET,
    RealisticMechanicalSystems.PART_TYPES.OEM
}

RealisticMechanicalSystems.modDirectory = g_currentModDirectory

---Tells whether a value is a number that is neither nan nor infinite
function RealisticMechanicalSystems.isFiniteNumber(value)
    return type(value) == "number" and value - value == 0
end

function RealisticMechanicalSystems.getSavegameKey(savegame)
    return savegame.key .. ".RealisticMechanicalSystems"
end

---Tells whether a vehicle is lent by a contract
function RealisticMechanicalSystems.isMissionVehicle(vehicle)
    return vehicle ~= nil and vehicle.propertyState == VehiclePropertyState.MISSION
end

---Finite number from a value, else fallback or 0, within finite bounds
function RealisticMechanicalSystems.sanitizeNumber(value, fallback, minValue, maxValue)
    local isFinite = RealisticMechanicalSystems.isFiniteNumber
    local number = tonumber(value)
    if not isFinite(number) then
        number = tonumber(fallback)
        if not isFinite(number) then
            number = 0
        end
    end
    local lower, upper = tonumber(minValue), tonumber(maxValue)
    if isFinite(lower) and number < lower then
        number = lower
    end
    if isFinite(upper) and number > upper then
        number = upper
    end
    return number
end

source(g_currentModDirectory .. "scripts/core/RMS_Thermal.lua")
source(g_currentModDirectory .. "scripts/core/RMS_Electrical.lua")
source(g_currentModDirectory .. "scripts/core/RMS_Preheat.lua")
source(g_currentModDirectory .. "scripts/core/RMS_Exhaust.lua")
source(g_currentModDirectory .. "scripts/core/RMS_Breakdowns.lua")
source(g_currentModDirectory .. "scripts/core/RMS_Start.lua")
source(g_currentModDirectory .. "scripts/core/RMS_Consumables.lua")
source(g_currentModDirectory .. "scripts/core/RMS_Greasing.lua")
source(g_currentModDirectory .. "scripts/core/RMS_Drivetrain.lua")
source(g_currentModDirectory .. "scripts/core/RMS_Steering.lua")
source(g_currentModDirectory .. "scripts/core/RMS_ElectricDrive.lua")

-- the short name each wear cause is saved under, system by system
RealisticMechanicalSystems.FACTOR_STATS_ALIASES = {
    expiredServiceFactor = "sf", instantDamageFactor = "idfg",
    motorLoadFactor = "mlf", airFilterCloggingFactor = "aicf", coldMotorFactor = "cmf", hotMotorFactor = "hmf",
    pullOverloadFactor = "pof", heavyTrailerFactor = "htf", luggingFactor = "lf", wheelSlipFactor = "wsf",
    drivetrainWindupFactor = "dwf", coldTransFactor = "ctf", hotTransFactor = "hotf",
    heavyLiftFactor = "hlf", operatingFactor = "of", coldOilFactor = "cof", hotOilFactor = "hof", vibFactor = "vf",
    filterBypassFactor = "hfbf", transmissionFilterBypassFactor = "tfbf",
    highCoolingFactor = "hcf", overheatFactor = "ohf", coldShockFactor = "csf",
    weatherExposureFactor = "wef", crankingStressFactor = "crf",
    steerLoadFactor = "slf", brakeMassFactor = "bmf", parkBrakeDragFactor = "pbf", terrainImpactFactor = "tif", lubricationFactor = "lubf",
    lowFuelStarvationFactor = "lff", coldFuelFactor = "cff", idleDepositFactor = "idf", highPressureFactor = "hpf",
    deepDischargeFactor = "ddf", batteryHeatFactor = "bhf",
    ptoLoadFactor = "plf", ptoEngagementFactor = "pef", ptoRaisedFactor = "prf",
    harvestEffortFactor = "hef", harvestGrainFactor = "hgf", harvestStrawFactor = "hsf", harvestStoneFactor = "hstf",
    harvestRiceFactor = "hrf", harvestWetFactor = "hwf"
}

-- refused parts: abused, or fitted not new original; index saved
RealisticMechanicalSystems.WARRANTY_ABUSES = { "impact", "heat", "low_level", "fuel_dry", "park_brake", "pto_engagement",
    "stones", "starter", "pto_angle", "windup", "filter", "trailer", "aftermarket_part", "used_part", "oil" }
RealisticMechanicalSystems.WARRANTY_ABUSE = {}
for code, reason in ipairs(RealisticMechanicalSystems.WARRANTY_ABUSES) do
    RealisticMechanicalSystems.WARRANTY_ABUSE[reason] = code
end

---Tells whether a warranty reason refuses the fault it is given for
function RealisticMechanicalSystems.getIsWarrantyRefusal(reason)
    return reason == "overdue" or RealisticMechanicalSystems.WARRANTY_ABUSE[reason] ~= nil
end

RealisticMechanicalSystems.FACTOR_STATS_KEYS = {}
for _, alias in pairs(RealisticMechanicalSystems.FACTOR_STATS_ALIASES) do
    RealisticMechanicalSystems.FACTOR_STATS_KEYS[alias] = true
end
-- no longer measured: a saved game still holds what they wore
for _, alias in ipairs({ "flf", "ltf", "hdf" }) do
    RealisticMechanicalSystems.FACTOR_STATS_KEYS[alias] = true
end

---Table held under a key, created when missing or not a table
local function ensureTable(holder, key)
    if type(holder[key]) ~= "table" then
        holder[key] = {}
    end
    return holder[key]
end

---Tells whether a name contains one of the words
local function nameContains(name, ...)
    for _, word in ipairs({ ... }) do
        if string.find(name, word, 1, true) ~= nil then
            return true
        end
    end
    return false
end

---Operating hours of a vehicle, 0 when it keeps none
local function getVehicleOperatingHours(vehicle)
    if vehicle ~= nil and vehicle.getOperatingTime ~= nil then
        local milliseconds = tonumber(vehicle:getOperatingTime())
        if milliseconds ~= nil then
            return milliseconds / 3600000
        end
    end
    if vehicle ~= nil and vehicle.getFormattedOperatingTime ~= nil then
        return tonumber(vehicle:getFormattedOperatingTime()) or 0
    end
    return 0
end
RealisticMechanicalSystems.getVehicleOperatingHours = getVehicleOperatingHours

---Wear statistics of a system, created or repaired in place
local function ensureFactorStatsEntry(spec, systemKey)
    if spec == nil or systemKey == nil then
        return nil
    end
    local stats = ensureTable(ensureTable(spec, "factorStats"), systemKey)
    stats.total = tonumber(stats.total) or 0
    stats._prevStress = tonumber(stats._prevStress) or 0
    stats._avgStress = tonumber(stats._avgStress) or 0
    -- -1 until the hours are first recorded
    stats.operatingHours = tonumber(stats.operatingHours) or -1
    return stats
end
RealisticMechanicalSystems.ensureFactorStatsEntry = ensureFactorStatsEntry

---Wear statistics of every system of the vehicle
local function ensureFactorStats(spec)
    if spec == nil then
        return {}
    end
    ensureTable(spec, "factorStats")
    for systemKey in pairs(spec.systems or {}) do
        ensureFactorStatsEntry(spec, systemKey)
    end
    return spec.factorStats
end
RealisticMechanicalSystems.ensureFactorStats = ensureFactorStats

---Transmission name of the motor configuration, XML first, then shop
local function getTransmissionNameFromXML(vehicle)
    if vehicle == nil then
        return nil
    end
    local configurations = vehicle.configurations
    local index = math.max(configurations ~= nil and tonumber(configurations.motor) or 1, 1)

    local xmlFile = vehicle.xmlFile
    if xmlFile ~= nil and xmlFile.getValue ~= nil then
        local path = "vehicle.motorized.motorConfigurations.motorConfiguration(%d).transmission"
        local key = string.format(path, index - 1)
        -- Motorized inherits transmission only if the selected block is absent.
        if not xmlFile:hasProperty(key) then
            key = string.format(path, 0)
        end
        local name = xmlFile:getValue(key .. "#name", nil, vehicle.customEnvironment, false)
        if name ~= nil then
            return tostring(name)
        end
    end

    local storeItem = g_storeManager:getItemByXMLFilename(vehicle.configFileName)
    local names = storeItem ~= nil and storeItem.specs ~= nil and storeItem.specs.transmission or nil
    if type(names) == "table" then
        return names[index] or names[1]
    end
    return nil
end

---Kind of transmission, from its name, else from the game gearbox
local function getTransmissionType(vehicle)
    local TYPES = RealisticMechanicalSystems.TRANSMISSION_TYPES
    local motor = vehicle ~= nil and vehicle.getMotor ~= nil and vehicle:getMotor() or nil
    if motor == nil then
        return TYPES.UNKNOWN
    end

    local name = getTransmissionNameFromXML(vehicle)
    if name ~= nil then
        name = string.lower(tostring(name))
        local isPowershift = nameContains(name, "powershift", "power shift")
        if isPowershift and nameContains(name, "manual") then
            return TYPES.MANUAL_POWERSHIFT
        elseif isPowershift then
            return TYPES.POWERSHIFT
        elseif nameContains(name, "variable", "cvt") then
            return TYPES.VARIABLE
        elseif nameContains(name, "auto") then
            return TYPES.AUTOMATIC
        elseif nameContains(name, "manual") then
            return TYPES.MANUAL
        end
    end

    local hasGears = motor.forwardGears ~= nil or motor.backwardGears ~= nil
    local POWERSHIFT = VehicleMotor.TRANSMISSION_TYPE.POWERSHIFT
    if motor.gearType == POWERSHIFT or motor.groupType == POWERSHIFT then
        return hasGears and TYPES.MANUAL_POWERSHIFT or TYPES.POWERSHIFT
    elseif motor.minForwardGearRatio ~= nil then
        return TYPES.VARIABLE
    elseif hasGears then
        return TYPES.MANUAL
    end
    return TYPES.UNKNOWN
end

RealisticMechanicalSystems.getTransmissionType = getTransmissionType
RealisticMechanicalSystems.getTransmissionNameFromXML = getTransmissionNameFromXML

local hasCVTAddon = RMS_Utils.hasCVTAddon

local function refreshExclusionState(spec)
    if spec.isExcludedByUser ~= nil then
        spec.isExcludedVehicle = spec.isExcludedByUser
    else
        spec.isExcludedVehicle = spec.isExcludedByRule
    end
end
RealisticMechanicalSystems.refreshExclusionState = refreshExclusionState

RealisticMechanicalSystems.SYNC_GROUP_ALL = 4095

---Flags one or more sync groups dirty on the vehicle
function RealisticMechanicalSystems.raiseRMSDirty(vehicle, groupBits)
    local spec = vehicle ~= nil and vehicle.spec_RealisticMechanicalSystems or nil
    if spec == nil or not vehicle.isServer or spec.rmsDirtyFlag == nil then
        return
    end

    for connection, mask in pairs(spec.rmsPendingByConnection) do
        spec.rmsPendingByConnection[connection] = bit32.bor(mask, groupBits)
    end

    vehicle:raiseDirtyFlags(spec.rmsDirtyFlag)
end

---Flags one or more sync groups dirty for a single connection
function RealisticMechanicalSystems.raiseRMSDirtyForConnection(vehicle, groupBits, connection)
    local spec = vehicle.spec_RealisticMechanicalSystems
    local mask = spec.rmsPendingByConnection[connection]
    if mask == nil then
        return
    end

    spec.rmsPendingByConnection[connection] = bit32.bor(mask, groupBits)
    vehicle:raiseDirtyFlags(spec.rmsDirtyFlag)
end

---Sets the user exclusion flag and replicates it
function RealisticMechanicalSystems:setRMSUserExcluded(isExcluded, noEventSend)
    local spec = self.spec_RealisticMechanicalSystems
    if spec == nil then
        return false, "unsupported"
    end
    local isWanted = isExcluded == true
    if spec.isExcludedByUser == isWanted then
        return false, "unchanged"
    end

    spec.isExcludedByUser = isWanted
    refreshExclusionState(spec)
    if not spec.isExcludedVehicle then
        RealisticMechanicalSystems.registerVehicle(self)
    else
        -- Left to the game: smoke, drivetrain and pending messages let go
        if self.isClient then
            RMS_Exhaust.reset(self)
        end
        RMS_Drivetrain.releaseControl(self)
        spec.pendingSideNotifications = {}
    end

    self:recalculateAndApplyEffects()
    RealisticMechanicalSystems.raiseRMSDirty(self, RealisticMechanicalSystems.SYNC_GROUP_ALL)
    if self.isServer and not noEventSend then
        RMS_VehicleExclusionEvent.sendToClients(self, spec.isExcludedByUser)
    end
    return true
end

---Time scale of the mission, 1 when unset or not positive
local function getSafeMissionTimeScale()
    local timeScale = g_currentMission.missionInfo.timeScale or 1
    return timeScale > 0 and timeScale or 1
end
RealisticMechanicalSystems.getSafeMissionTimeScale = getSafeMissionTimeScale

local SYSTEM_SYNC_EPSILON = 0.001
local OVERLOAD_AVERAGE_PERIOD_MS = 60000
local OVERLOAD_WINDOW_COMPACT_THRESHOLD = 256
local OVERLOAD_FACTOR_ALIASES_BY_SYSTEM = {
    engine = { "mlf", "hmf", "lf" },
    transmission = { "pof", "htf", "lf", "wsf", "hotf" },
    harvest = { "hef" }
}

local function resetOverloadAverage(systemData)
    systemData._avgStress = 0
    systemData._avgStressWindow = nil
end

---Drops the samples, or part of the oldest, past the averaging period
local function trimOverloadWindow(window)
    while window.head <= window.tail and window.totalDurationMs > OVERLOAD_AVERAGE_PERIOD_MS do
        local oldest = window.samples[window.head]
        local length = math.max(tonumber(oldest.durationMs) or 0, 0)
        local rate = tonumber(oldest.ratePerHour) or 0
        local excess = window.totalDurationMs - OVERLOAD_AVERAGE_PERIOD_MS
        local cut = math.min(length, excess)
        window.totalDurationMs = window.totalDurationMs - cut
        window.weightedSum = window.weightedSum - rate * cut
        if length <= excess then
            window.samples[window.head] = nil
            window.head = window.head + 1
            if rate > 0 then
                window.positiveSampleCount = window.positiveSampleCount - 1
            end
        else
            oldest.durationMs = length - excess
        end
    end
end

---Overload rate averaged over the last period, from one more sample
local function updateOverloadAverage(systemData, sampleDurationMs, sampleRatePerHour)
    local window = systemData._avgStressWindow
    if type(window) ~= "table" then
        if sampleRatePerHour <= 0 then
            resetOverloadAverage(systemData)
            return 0
        end
        window = { samples = {}, head = 1, tail = 0, totalDurationMs = 0, weightedSum = 0, positiveSampleCount = 0 }
        systemData._avgStressWindow = window
    end

    -- A zero rate counts only while older samples are still weighed
    if sampleRatePerHour > 0 or window.head <= window.tail then
        window.tail = window.tail + 1
        window.samples[window.tail] = { durationMs = sampleDurationMs, ratePerHour = sampleRatePerHour }
        window.totalDurationMs = window.totalDurationMs + sampleDurationMs
        window.weightedSum = window.weightedSum + sampleRatePerHour * sampleDurationMs
        if sampleRatePerHour > 0 then
            window.positiveSampleCount = window.positiveSampleCount + 1
        end
    end
    trimOverloadWindow(window)

    if window.positiveSampleCount <= 0 or window.weightedSum <= 0 or window.totalDurationMs <= 0 then
        resetOverloadAverage(systemData)
        return 0
    end
    -- The dropped slots are packed once they pile up
    if window.head > OVERLOAD_WINDOW_COMPACT_THRESHOLD and window.head > window.tail / 2 then
        local kept = {}
        for index = window.head, window.tail do
            kept[#kept + 1] = window.samples[index]
        end
        window.samples, window.head, window.tail = kept, 1, #kept
    end

    local average = math.max(window.weightedSum / OVERLOAD_AVERAGE_PERIOD_MS, 0)
    systemData._avgStress = average
    return average
end

local function canRaiseDirtyFlag(vehicle, spec)
    return vehicle ~= nil and vehicle.isServer and spec ~= nil and spec.rmsDirtyFlag ~= nil
end

---Operating time the network sends, in ms
local function getSyncOperatingTime(vehicle)
    local time = nil
    if vehicle ~= nil then
        if vehicle.getOperatingTime ~= nil then
            time = vehicle:getOperatingTime()
        else
            time = vehicle.operatingTime
        end
    end
    return tonumber(time) or 0
end
RealisticMechanicalSystems.getSyncOperatingTime = getSyncOperatingTime

---Breakdown fields the clients show, as one comparable string
local function serializeBreakdownsForDirtyCheck(breakdowns)
    local entries = {}
    for id, breakdown in pairs(type(breakdowns) == "table" and breakdowns or {}) do
        table.insert(entries, string.format("%s,%d,%d,%d,%d,%d,%d", id, math.max(math.floor(tonumber(breakdown.stage) or 1), 1),
            breakdown.isVisible and 1 or 0, breakdown.isSelectedForRepair and 1 or 0, breakdown.isActive ~= false and 1 or 0,
            math.max(math.floor(tonumber(breakdown.source) or 0), 0), breakdown.usedPartHours or 0))
    end
    table.sort(entries)
    return table.concat(entries, ";")
end

---Tells whether two numbers differ past a tolerance, nil reading 0
local function hasNumberMoved(last, current, tolerance)
    local sanitize = RealisticMechanicalSystems.sanitizeNumber
    return math.abs(sanitize(last, 0) - sanitize(current, 0)) > tolerance
end

---A value a sync group watches, a spec field or read by a function
-- @param float? tolerance a number moves past it, no tolerance compares as is
local function watch(source, tolerance)
    local read = source
    if type(source) ~= "function" then
        read = function(_, spec) return spec[source] end
    end
    return { read = read, tolerance = tolerance }
end

---A spec field read as a number, a default standing for none
local function watchNumber(field, default, tolerance)
    return watch(function(_, spec) return tonumber(spec[field]) or default end, tolerance)
end

---Conditions and switches of the systems, with their count
local function readSystemsSync(_, spec)
    local systems, count = {}, 0
    for systemKey, systemData in pairs(spec.systems) do
        systems[systemKey] = { condition = systemData.condition, enabled = systemData.enabled ~= false }
        count = count + 1
    end
    return { systems = systems, count = count }
end

---Tells whether a system changed, or one came or went
local function haveSystemsMoved(last, current)
    if last == nil then
        return true
    end
    for systemKey, now in pairs(current.systems) do
        local before = last.systems[systemKey]
        if before == nil or before.enabled ~= now.enabled
            or hasNumberMoved(before.condition, now.condition, SYSTEM_SYNC_EPSILON) then
            return true
        end
    end
    return last.count ~= current.count
end

local function getTutorialSyncConnection(vehicle)
    local connection = vehicle:getOwnerConnection()
    if connection == nil then
        return nil
    end

    local uniqueUserId = g_currentMission.userManager:getUniqueUserIdByConnection(connection)
    if uniqueUserId == nil then
        return nil
    end

    local state = RMS_Config.TUTORIAL_PLAYER_STATES[tostring(uniqueUserId)]
    if state ~= nil and not state.tutorialMode then
        return nil
    end

    return connection
end

---Sync groups in update order, each with the values it watches
local syncGroups = nil

---The same groups by their bit
local syncGroupsByBit = {}

---Builds the sync groups once the fluids and filters are known
local function getSyncGroups()
    if syncGroups ~= nil then
        return syncGroups
    end
    local GROUP = RealisticMechanicalSystems.SYNC_GROUP
    local function mapText(field)
        return watch(function(_, spec) return RMS_Utils.serializeNumericMap(spec[field]) end)
    end

    local fieldcare = {
        watch("radiatorClogging", 0.005), watch("airFilterClogging", 0.005), watch("airFilterResidue", 0.005),
        watch("lubricationLevel", 0.005), watch("greasingDuePoints"), watch("engineOilLevel", 0.005),
        watch("coolantLevel", 0.005), watch("transmissionOilLevel", 0.005), watch("hydraulicFluidLevel", 0.005),
        watch(function(_, spec) return RMS_Fluids.serializeLeakDebt(spec.fluidLeakLossDebt) end),
        watch("fieldInspectionSoundActive")
    }
    for _, circuit in ipairs(RMS_Fluids.PICKUP_CIRCUITS) do
        table.insert(fieldcare, watch(function(_, spec) return spec.pickupUncovered[circuit] == true end))
    end
    for _, filter in ipairs(RMS_Consumables.FILTERS) do
        table.insert(fieldcare, watch(filter.stateKey, 0.005))
    end
    for _, circuit in ipairs(RMS_Fluids.CIRCUIT_ORDER) do
        table.insert(fieldcare, watch(function(vehicle) return RMS_Fluids.getCapacity(vehicle, circuit) end, 0.001))
        table.insert(fieldcare, watch(function(vehicle) return RMS_Fluids.getCompatibility(vehicle, circuit) end, 0.0001))
    end

    syncGroups = {
        { group = GROUP.STATE, watches = { watch("currentState"), watch("maintenanceTimer", 1.0) } },
        { group = GROUP.SERVICE_CONTEXT, watches = {
            watch("serviceOptionOne"), watch("serviceOptionTwo"), watch("workshopType") } },
        { group = GROUP.TELEMETRY, watches = {
            watch(getSyncOperatingTime, 60000.0), watchNumber("realOperatingTime", 0, 60000.0), watch("_fuelUsageRaw", 0.3),
            watchNumber("dynamicMotorLoad", 0, 0.01), watchNumber("wheelSlipIntensity", 0, 0.01), watch("liftedMass", 10.0) } },
        -- The engine temperature is brought up to date before it is compared
        { group = GROUP.THERMAL, prepare = function(vehicle) RMS_Thermal.getEngineTemperature(vehicle) end, watches = {
            watch(function(_, spec) return RMS_Thermal.getHasSeparateHydraulicCircuit(spec) and spec.rawHydraulicTemperature ~= nil end),
            watch(function(_, spec) return spec.isElectricVehicle == true and spec.tractionBatteryTempC ~= nil end),
            watch("rawHydraulicTemperature", 0.05), watch("tractionBatteryTempC", 0.05), watch("rawEngineTemperature", 0.05),
            watch("rawTransmissionTemperature", 0.05), watch("thermostatState", 0.05), watch("transmissionThermostatState", 0.05) } },
        { group = GROUP.ELECTRICAL, watches = {
            watch("batterySoc", 0.01), watch("batteryIsolated"), watch("systemVoltageV", 0.01), watch("startState"),
            watch("preheatLampTestActive"), watch("preheatWasRequired"), watch("preheatColdStartFaultSeverity") } },
        { group = GROUP.FIELDCARE, watches = fieldcare },
        { group = GROUP.WEAR, watches = {
            watch("serviceLevel", 0.001), watch("transmissionServiceLevel", 0.001), watch("coolantServiceLevel", 0.001),
            watch("hydraulicServiceLevel", 0.001), mapText("serviceCalendar"), mapText("partWarranty"), mapText("usedPartWarranty"),
            watch("warrantyPlan"), watch("warrantyVoided"), watch("remapMotor"), watch("remapAge"), watch("remapByDealer"), watch("conditionLevel", 0.001),
            watch("ptoEngagementSequence"), watch("ptoShockSequence"), watch("ptoRaisedTooLong"),
            { read = readSystemsSync, hasMoved = haveSystemsMoved } } },
        { group = GROUP.BREAKDOWNS, watches = {
            watch(function(_, spec) return serializeBreakdownsForDirtyCheck(spec.activeBreakdowns) end) } },
        { group = GROUP.SERVICE_PROGRESS, watches = {
            watch("pendingProgressElapsedTime", 500.0), watch("pendingProgressStepIndex"), watch("pendingProgressTotalTime", 500.0) } },
        -- Sent to the driver alone, their connection first
        { group = GROUP.TUTORIAL_DATA, watches = {
            watch(function(vehicle) return getTutorialSyncConnection(vehicle) end),
            watch(function(_, spec) return tonumber(spec.fuelState.idleTimer) or 0 end, 1.0),
            watch(function(_, spec) return tonumber(spec.fuelState.level) or 0 end, 0.01),
            watchNumber("luggingTutorialTimer", 0, 100.0), watchNumber("wheelSlipTutorialTimer", 0, 100.0),
            watch(function(_, spec) return tonumber(spec.chassisBrakeState.hpTrailerMassRatio) or 1000 end, 0.1),
            watch(function(_, spec) return tonumber(spec.chassisBrakeState.trailerMass) or 0 end, 0.01),
            watch(function(_, spec) return tonumber(spec.chassisBrakeState.hpGrossMassRatio) or 1000 end, 0.1),
            watch(function(_, spec) return spec.isCranking == true end),
            watch(function(_, spec) return spec.chassisSteerState.groundContact > 0 end),
            watch(function(_, spec) return spec.chassisSteerState.isMoving == true end),
            watch("vibrationTutorialTimer", 100.0), watch("terrainImpactTutorialTimer", 100.0),
            watch(function(_, spec)
                local electrical = spec.systems ~= nil and spec.systems.electrical or nil
                return electrical ~= nil and (tonumber(electrical.crankingTimer) or 0) or 0
            end, 100.0) } }
    }
    for _, entry in ipairs(syncGroups) do
        syncGroupsByBit[entry.group] = entry
    end
    return syncGroups
end

---Reads the values a sync group watches, from a first one on
-- @param integer? first first value read, 1 when nil
local function readSyncGroup(vehicle, spec, entry, first)
    local values = {}
    for index = first or 1, #entry.watches do
        values[index] = entry.watches[index].read(vehicle, spec)
    end
    return values
end

---Tells whether a watched value moved since it was last sent
local function hasWatchMoved(watched, last, current)
    if watched.hasMoved ~= nil then
        return watched.hasMoved(last, current)
    elseif watched.tolerance ~= nil then
        return hasNumberMoved(last, current, watched.tolerance)
    end
    return last ~= current
end

---Raises a sync group when one of its values moved since it was sent
-- @param table? connection the one connection to send to, every one when nil
local function markGroupDirty(vehicle, spec, group, connection)
    if not canRaiseDirtyFlag(vehicle, spec) then
        return false
    end
    getSyncGroups()
    local entry = syncGroupsByBit[group]
    if entry.prepare ~= nil then
        entry.prepare(vehicle)
    end
    local sent = ensureTable(spec, "rmsLastSync")
    local last = sent[group] or {}
    local values = readSyncGroup(vehicle, spec, entry)
    for index, watched in ipairs(entry.watches) do
        if hasWatchMoved(watched, last[index], values[index]) then
            if connection ~= nil then
                RealisticMechanicalSystems.raiseRMSDirtyForConnection(vehicle, group, connection)
            else
                RealisticMechanicalSystems.raiseRMSDirty(vehicle, group)
            end
            sent[group] = values
            return true
        end
    end
    return false
end

---Raises the tutorial data for the driver, while they keep the tips on
local function markTutorialDataDirty(vehicle, spec)
    if not canRaiseDirtyFlag(vehicle, spec) then
        return false
    end
    local GROUP = RealisticMechanicalSystems.SYNC_GROUP
    local connection = getTutorialSyncConnection(vehicle)
    if connection == nil then
        -- The next driver gets everything
        local last = ensureTable(spec, "rmsLastSync")[GROUP.TUTORIAL_DATA]
        if last ~= nil then
            last[1] = nil
        end
        return false
    end
    return markGroupDirty(vehicle, spec, GROUP.TUTORIAL_DATA, connection)
end

---Raises every sync group whose values moved
function RealisticMechanicalSystems.markSyncGroupsDirty(vehicle, spec)
    if not canRaiseDirtyFlag(vehicle, spec) then
        return
    end
    local TUTORIAL = RealisticMechanicalSystems.SYNC_GROUP.TUTORIAL_DATA
    for _, entry in ipairs(getSyncGroups()) do
        if entry.group == TUTORIAL then
            markTutorialDataDirty(vehicle, spec)
        else
            markGroupDirty(vehicle, spec, entry.group)
        end
    end
end

---Takes the current values as sent, so a loaded vehicle raises nothing
function RealisticMechanicalSystems.storeSyncBaseline(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    local sent = ensureTable(spec, "rmsLastSync")
    local TUTORIAL = RealisticMechanicalSystems.SYNC_GROUP.TUTORIAL_DATA
    for _, entry in ipairs(getSyncGroups()) do
        -- The tutorial data waits for its driver, then goes out whole
        sent[entry.group] = readSyncGroup(vehicle, spec, entry, entry.group == TUTORIAL and 2 or 1)
    end
end

---Flags every group a finished or cancelled service touches
function RealisticMechanicalSystems.raiseServiceLifecycleDirtyFlags(vehicle)
    local spec = vehicle ~= nil and vehicle.spec_RealisticMechanicalSystems or nil
    if spec == nil then
        return false
    end
    local GROUP = RealisticMechanicalSystems.SYNC_GROUP
    local raised = false
    for _, group in ipairs({ GROUP.STATE, GROUP.SERVICE_CONTEXT, GROUP.WEAR, GROUP.BREAKDOWNS, GROUP.SERVICE_PROGRESS }) do
        raised = markGroupDirty(vehicle, spec, group) or raised
    end
    return raised
end

---Savegame attributes of a vehicle: name, type, content, default
local SAVEGAME_ATTRIBUTES = {
    { "userExclusion", "BOOL", "User decision overriding the automatic exclusion, absent when the user has no opinion" },
    { "service", "FLOAT", "Engine oil service clock, 1 just serviced" },
    { "transmissionService", "FLOAT", "Transmission and hydraulic oil service level" },
    { "coolantService", "FLOAT", "Coolant service level" },
    { "hydraulicService", "FLOAT", "Separate hydraulic oil service level" },
    { "serviceCalendar", "STRING", "Calendar start ages by service circuit" },
    { "warrantyPlan", "INT", "Factory warranty plan" },
    { "partWarranty", "STRING", "Dealer part warranty expiry ages" },
    { "usedPartWarranty", "STRING", "Used part warranty expiry ages" },
    { "warrantyVoided", "BOOL", "Warranty lost to an engine remap" },
    { "remapMotor", "INT", "Engine configuration remapped, 0 on stock software" },
    { "remapAge", "INT", "Machine age in months at the remap" },
    { "remapByDealer", "BOOL", "Remap by the dealer, factory software" },
    { "condition", "FLOAT", "Overall condition of the machine" },
    { "breakdowns", "STRING", "Breakdowns on the machine, encoded" },
    { "state", "STRING", "Service under way, ready when none" },
    { "maintenanceTimer", "FLOAT", "Time left of the running service, in ms" },
    { "realOperatingTime", "FLOAT", "Working time counted by RMS, in ms" },
    { "engineTemperature", "FLOAT", "Engine coolant temperature, in degrees" },
    { "transmissionTemperature", "FLOAT", "Transmission oil temperature, in degrees" },
    { "hydraulicTemperature", "FLOAT", "Separate hydraulic oil temperature, in degrees" },
    { "thermalWorldTime", "FLOAT", "Mission time of the saved temperatures" },
    { "thermalAmbient", "FLOAT", "Air temperature of the saved temperatures" },
    { "batterySoc", "FLOAT", "Battery charge, 1 full" },
    { "batteryIsolated", "BOOL", "Battery isolator open", false },
    { "tractionBatteryTempC", "FLOAT", "Traction battery temperature of an electric vehicle" },
    { "radiatorClogging", "FLOAT", "Radiator clogging, 1 fully clogged" },
    { "airFilterClogging", "FLOAT", "Air filter clogging level" },
    { "airFilterResidue", "FLOAT", "Air filter clogging a blow out cannot remove" },
    { "engineOilLevel", "FLOAT", "Engine oil level" },
    { "coolantLevel", "FLOAT", "Coolant level" },
    { "transmissionOilLevel", "FLOAT", "Transmission oil level" },
    { "hydraulicFluidLevel", "FLOAT", "Hydraulic fluid level" },
    { "fluidCapacityVersion", "INT", "Fluid capacity model version" },
    { "fluidCapacitySource", "STRING", "Resolved fluid capacity source" },
    { "engineOilCapacity", "FLOAT", "Engine oil capacity in liters" },
    { "coolantCapacity", "FLOAT", "Coolant capacity in liters" },
    { "transmissionOilCapacity", "FLOAT", "Transmission oil capacity in liters" },
    { "hydraulicFluidCapacity", "FLOAT", "Hydraulic fluid capacity in liters" },
    { "engineOilCompatibility", "FLOAT", "Engine oil mixture compatibility" },
    { "coolantCompatibility", "FLOAT", "Coolant mixture compatibility" },
    { "transmissionOilCompatibility", "FLOAT", "Transmission oil mixture compatibility" },
    { "hydraulicFluidCompatibility", "FLOAT", "Hydraulic fluid mixture compatibility" },
    { "engineOilSuitedShare", "FLOAT", "Share of the engine oil its manual asks for" },
    { "fluidLeakLossDebt", "STRING", "Unreplenished fluid loss by leak" },
    { "pendingFluidRequirements", "STRING", "Physical fluid reserved for the running service" },
    { "wetStackingLevel", "FLOAT", "Wet stacking deposit level" },
    { "particulateFilterLevel", "FLOAT", "Particulate filter soot level, 1 calling a regeneration" },
    { "particulateFilterAsh", "FLOAT", "Particulate filter ash, 1 calling a cleaning" },
    { "particulateFilterOilAsh", "FLOAT", "Part of the filter ash left by an unsuited engine oil" },
    { "scrInducementHours", "FLOAT", "Engine hours since an AdBlue fault was confirmed" },
    { "particulateFilterOverloaded", "BOOL", "Whether the particulate filter overload is shown as a breakdown" },
    { "greasing", "STRING", "Grease points due, hours elapsed and hours late per interval, then the worked day" },
    { "thermostatState", "FLOAT", "Opening of the engine thermostat, 0 to 1" },
    { "transmissionThermostatState", "FLOAT", "Opening of the transmission oil thermostat, 0 to 1" },
    { "serviceOptionOne", "STRING", "First choice of the running service" },
    { "serviceOptionTwo", "STRING", "Second choice of the running service" },
    { "workshopType", "STRING", "Workshop doing the running service" },
    { "pendingSelectedBreakdowns", "STRING", "Breakdowns the running service repairs" },
    { "pendingServicePrice", "FLOAT", "Price of the running service" },
    { "pendingServiceInvoice", "STRING", "Invoice lines of the running service" },
    { "pendingInspectionQueue", "STRING", "Breakdowns the running inspection has yet to find" },
    { "pendingRepairQueue", "STRING", "Breakdowns the running repair has yet to clear" },
    { "pendingProgressStepIndex", "INT", "Step the running service is at" },
    { "pendingProgressTotalTime", "FLOAT", "Length of the running service, in ms" },
    { "pendingProgressElapsedTime", "FLOAT", "Time the running service has run, in ms" },
    { "pendingServiceClockStart", "STRING", "Service clock levels at the start of the running service" },
    { "pendingServiceClockTarget", "STRING", "Service clock levels the running service restores" },
    { "systemsState", "STRING", "Condition and switch of each system" },
    { "partWear", "STRING", "Wear of each part" },
    { "partAbuse", "STRING", "Abuse that last wore each part, refusing its warranty" },
    { "pickupAirTime", "STRING", "Seconds each pump has drawn air since its part was fitted" },
    { "factorStats", "STRING", "Wear gathered by each cause, system by system" },
    { "pendingOverhaulPartStart", "STRING", "Wear of each part at the start of the running overhaul" },
    { "pendingOverhaulPartTarget", "STRING", "Wear the running overhaul brings each part to" },
    { "driveMode", "INT", "Drivetrain mode (0=4x2, 1=4WD, 2=AUTO)" },
    { "diffLockRequested", "BOOL", "Differential lock requested" },
    { "tripStartKilometers", "FLOAT", "Odometer reading at the last trip meter reset (km)" },
    { "ptoEngagementCount", "INT", "PTO engagement count" },
    { "ptoEngagementSequence", "INT", "PTO engagement cycle sequence" }
}

---Savegame attributes of a maintenance log entry
local LOG_ENTRY_ATTRIBUTES = {
    { "id", "INT", "Number of the entry" },
    { "type", "STRING", "Kind of service" },
    { "price", "FLOAT", "Price paid" },
    { "date", "STRING", "Day, month and year of the service" },
    { "location", "STRING", "Workshop of the service" },
    { "optionOne", "STRING", "First choice of the service" },
    { "optionTwo", "STRING", "Second choice of the service" },
    { "isVisible", "STRING", "Whether the record shows the entry" },
    { "isCompleted", "BOOL", "Whether the service ran to its end" },
    { "invoice", "STRING", "Invoice Lines" }
}

---Savegame attributes of the machine as a log entry found it
local LOG_CONDITION_ATTRIBUTES = {
    { "year", "INT", "Model year of the machine" },
    { "operatingHours", "FLOAT", "Hours on the meter" },
    { "odometerKilometers", "FLOAT", "Odometer Reading (km)" },
    { "age", "FLOAT", "Age of the machine in months" },
    { "condition", "FLOAT", "Overall condition" },
    { "service", "FLOAT", "Engine oil service clock" },
    { "activeBreakdowns", "STRING", "Breakdowns on the machine, encoded" },
    { "selectedBreakdowns", "STRING", "Breakdowns chosen for repair" },
    { "activeEffects", "STRING", "Effects the breakdowns had" },
    { "activeIndicators", "STRING", "Warning lights lit" },
    { "reliability", "FLOAT", "Reliability of the make" },
    { "systems", "STRING", "Condition and switch of each system" },
    { "partWear", "STRING", "Wear of each part" },
    { "batterySoc", "FLOAT", "Battery charge, 1 full" },
    { "wearExcess", "FLOAT", "Wear over the normal wear" },
    { "wearCauses", "STRING", "Share of each cause of wear" }
}

---Finishes the running service at once
function RealisticMechanicalSystems.forceFinishService(vehicle)
    local spec = vehicle ~= nil and vehicle.spec_RealisticMechanicalSystems or nil
    if spec == nil or not vehicle.isServer or spec.currentState == RealisticMechanicalSystems.STATUS.READY then
        return false
    end

    -- One step as long as what is left, at the time scale of the mission
    local missionInfo = g_currentMission ~= nil and g_currentMission.missionInfo or nil
    local timeScale = missionInfo ~= nil and missionInfo.timeScale or 1
    timeScale = timeScale > 0 and timeScale or 1
    local remaining = math.max(spec.maintenanceTimer or 0, 0)
    vehicle:processService(math.max(math.ceil(remaining / timeScale) + 1, 1), true)

    if spec.currentState ~= RealisticMechanicalSystems.STATUS.READY then
        spec.pendingProgressElapsedTime = spec.pendingProgressTotalTime or 0
        spec.maintenanceTimer = 0
        vehicle:completeService()
    end
    return true
end

---Registers the savegame schema of the specialization
function RealisticMechanicalSystems.initSpecialization()
    local schema = Vehicle.xmlSchema
    local savegame = Vehicle.xmlSchemaSavegame
    local function register(path, attributes)
        for _, attribute in ipairs(attributes) do
            savegame:register(XMLValueType[attribute[2]], path .. "#" .. attribute[1], attribute[3], attribute[4])
        end
    end

    schema:setXMLSpecializationType("RealisticMechanicalSystems")
    local base = "vehicles.vehicle(?).RealisticMechanicalSystems"
    register(base, SAVEGAME_ATTRIBUTES)
    for _, filter in ipairs(RMS_Consumables.FILTERS) do
        savegame:register(XMLValueType.FLOAT, base .. "#" .. filter.stateKey, "Filter clogging, 1 when its change falls due")
    end
    local entry = base .. ".maintenanceLog.entry(?)"
    register(entry, LOG_ENTRY_ATTRIBUTES)
    register(entry .. ".conditionData", LOG_CONDITION_ATTRIBUTES)
    schema:setXMLSpecializationType()

    RMS_Thermal.registerReversibleFan()
    RealisticMechanicalSystems.registerWarrantyConfiguration()
end

function RealisticMechanicalSystems.registerEventListeners(vehicleType)
    SpecializationUtil.registerEventListener(vehicleType, "onLoad", RealisticMechanicalSystems)
    SpecializationUtil.registerEventListener(vehicleType, "onPostLoad", RealisticMechanicalSystems)
    SpecializationUtil.registerEventListener(vehicleType, "onSaleItemSet", RealisticMechanicalSystems)
    SpecializationUtil.registerEventListener(vehicleType, "onDelete", RealisticMechanicalSystems)
    SpecializationUtil.registerEventListener(vehicleType, "onLeaveVehicle", RealisticMechanicalSystems)
    SpecializationUtil.registerEventListener(vehicleType, "onDeactivate", RealisticMechanicalSystems)
    SpecializationUtil.registerEventListener(vehicleType, "onUpdate", RealisticMechanicalSystems)
    SpecializationUtil.registerEventListener(vehicleType, "onPostUpdate", RealisticMechanicalSystems)
    SpecializationUtil.registerEventListener(vehicleType, "onStartMotor", RealisticMechanicalSystems)
    SpecializationUtil.registerEventListener(vehicleType, "onStopMotor", RealisticMechanicalSystems)
    SpecializationUtil.registerEventListener(vehicleType, "onWriteStream", RealisticMechanicalSystems)
    SpecializationUtil.registerEventListener(vehicleType, "onReadStream", RealisticMechanicalSystems)
    SpecializationUtil.registerEventListener(vehicleType, "onWriteUpdateStream", RealisticMechanicalSystems)
    SpecializationUtil.registerEventListener(vehicleType, "onReadUpdateStream", RealisticMechanicalSystems)
    SpecializationUtil.registerEventListener(vehicleType, "saveToXMLFile", RealisticMechanicalSystems)
    SpecializationUtil.registerEventListener(vehicleType, "onRegisterActionEvents", RealisticMechanicalSystems)
end

function RealisticMechanicalSystems.registerOverwrittenFunctions(vehicleType)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "getIsTabbable", RealisticMechanicalSystems.getIsTabbable)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "repaintVehicle", RMS_Bodywork.repaintVehicle)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "getCanMotorRun", RMS_Breakdowns.getCanMotorRun)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "getMotorNotAllowedWarning", RMS_Breakdowns.getMotorNotAllowedWarning)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "getCanStartAIVehicle", RMS_Breakdowns.getCanStartAIVehicle)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "startMotor", RMS_Start.startMotor)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "stopMotor", RMS_Start.stopMotor)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "updateDamageAmount", RealisticMechanicalSystems.updateDamageAmount)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "setLightsTypesMask", RMS_Breakdowns.setLightsTypesMask)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "setBeaconLightsVisibility", RMS_Breakdowns.setBeaconLightsVisibility)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "setTurnLightState", RMS_Breakdowns.setTurnLightState)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "getIsActiveForLights", RMS_Breakdowns.getIsActiveForLights)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "getSpeedLimit", RMS_Breakdowns.getSpeedLimitOverwrite)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "getCruiseControlSpeed", RealisticMechanicalSystems.getCruiseControlSpeed)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "updateVehiclePhysics", RMS_Breakdowns.updateVehiclePhysics)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "updateVehiclePhysics", RMS_Drivetrain.updateVehiclePhysics)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "updateConsumers", RMS_Breakdowns.updateConsumersOverwrite)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "getSellPrice", RealisticMechanicalSystems.getSellPrice)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "updateMotorTemperature", RealisticMechanicalSystems.updateMotorTemperature)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "addToPhysics", RMS_Drivetrain.addToPhysics)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "brake", RMS_Drivetrain.brake)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "addCutterArea", RealisticMechanicalSystems.addCutterArea)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "processCombineChopperArea", RMS_Breakdowns.processCombineChopperArea)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "setIsSwathActive", RMS_Breakdowns.setIsSwathActive)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "updateSteeringAngle", RMS_Steering.updateSteeringAngle)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "updateArticulatedAxisRotation", RMS_Steering.updateArticulatedAxisRotation)
end

function RealisticMechanicalSystems.registerFunctions(vehicleType)
    SpecializationUtil.registerFunction(vehicleType, "rmsUpdate", RealisticMechanicalSystems.rmsUpdate)
    SpecializationUtil.registerFunction(vehicleType, "updateVehicleStateSnapshot", RealisticMechanicalSystems.updateVehicleStateSnapshot)
    SpecializationUtil.registerFunction(vehicleType, "setRMSUserExcluded", RealisticMechanicalSystems.setRMSUserExcluded)

    -- Crab steering alone does not register the articulation hook.
    if vehicleType.functions.updateArticulatedAxisRotation == nil
            and SpecializationUtil.hasSpecialization(ArticulatedAxis, vehicleType.specializations) then
        SpecializationUtil.registerFunction(vehicleType, "updateArticulatedAxisRotation", RMS_Steering.passArticulatedAxisRotation)
    end

    SpecializationUtil.registerFunction(vehicleType, "recalculateAndApplyEffects", RealisticMechanicalSystems.recalculateAndApplyEffects)
    SpecializationUtil.registerFunction(vehicleType, "recalculateAndApplyIndicators", RealisticMechanicalSystems.recalculateAndApplyIndicators)
    
    SpecializationUtil.registerFunction(vehicleType, "tryTriggerBreakdown", RealisticMechanicalSystems.tryTriggerBreakdown)
    SpecializationUtil.registerFunction(vehicleType, "getRandomBreakdown", RealisticMechanicalSystems.getRandomBreakdown)
    SpecializationUtil.registerFunction(vehicleType, "addBreakdown", RealisticMechanicalSystems.addBreakdown)
    SpecializationUtil.registerFunction(vehicleType, "suspendBreakdown", RealisticMechanicalSystems.suspendBreakdown)
    SpecializationUtil.registerFunction(vehicleType, "removeBreakdown", RealisticMechanicalSystems.removeBreakdown)
    SpecializationUtil.registerFunction(vehicleType, "hasBreakdown", RealisticMechanicalSystems.hasBreakdown)
    SpecializationUtil.registerFunction(vehicleType, "hasSystemBreakdowns", RealisticMechanicalSystems.hasSystemBreakdowns)
    SpecializationUtil.registerFunction(vehicleType, "processBreakdowns", RealisticMechanicalSystems.processBreakdowns)
    SpecializationUtil.registerFunction(vehicleType, "changeBreakdownStage", RealisticMechanicalSystems.changeBreakdownStage)
    SpecializationUtil.registerFunction(vehicleType, "getActiveBreakdowns", RealisticMechanicalSystems.getActiveBreakdowns)
    SpecializationUtil.registerFunction(vehicleType, "hasEffect", RealisticMechanicalSystems.hasEffect)
    SpecializationUtil.registerFunction(vehicleType, "processWornParts", RealisticMechanicalSystems.processWornParts)
    
    SpecializationUtil.registerFunction(vehicleType, "initService", RealisticMechanicalSystems.initService)
    SpecializationUtil.registerFunction(vehicleType, "processService", RealisticMechanicalSystems.processService)
    SpecializationUtil.registerFunction(vehicleType, "completeService", RealisticMechanicalSystems.completeService)
    SpecializationUtil.registerFunction(vehicleType, "cancelService", RealisticMechanicalSystems.cancelService)

    SpecializationUtil.registerFunction(vehicleType, "getServiceLevel", RealisticMechanicalSystems.getServiceLevel)
    SpecializationUtil.registerFunction(vehicleType, "getConditionLevel", RealisticMechanicalSystems.getConditionLevel)
    SpecializationUtil.registerFunction(vehicleType, "getSystemConditionLevel", RealisticMechanicalSystems.getSystemConditionLevel)
    SpecializationUtil.registerFunction(vehicleType, "updateServiceLevel", RealisticMechanicalSystems.updateServiceLevel)
    SpecializationUtil.registerFunction(vehicleType, "updateConditionLevel", RealisticMechanicalSystems.updateConditionLevel)

    SpecializationUtil.registerFunction(vehicleType, "updateSystemWear", RealisticMechanicalSystems.updateSystemWear)
    SpecializationUtil.registerFunction(vehicleType, "updateEngineSystem", RealisticMechanicalSystems.updateEngineSystem)
    SpecializationUtil.registerFunction(vehicleType, "updateTransmissionSystem", RealisticMechanicalSystems.updateTransmissionSystem)
    SpecializationUtil.registerFunction(vehicleType, "getTransmissionType", RealisticMechanicalSystems.getTransmissionType)
    SpecializationUtil.registerFunction(vehicleType, "updateHydraulicsSystem", RealisticMechanicalSystems.updateHydraulicsSystem)
    SpecializationUtil.registerFunction(vehicleType, "updatePtoSystem", RealisticMechanicalSystems.updatePtoSystem)
    SpecializationUtil.registerFunction(vehicleType, "updateHarvestSystem", RealisticMechanicalSystems.updateHarvestSystem)
    SpecializationUtil.registerFunction(vehicleType, "updateCoolingSystem", RealisticMechanicalSystems.updateCoolingSystem)
    SpecializationUtil.registerFunction(vehicleType, "updateElectricalSystem", RealisticMechanicalSystems.updateElectricalSystem)
    SpecializationUtil.registerFunction(vehicleType, "updateChassisSystem", RealisticMechanicalSystems.updateChassisSystem)
    SpecializationUtil.registerFunction(vehicleType, "updateFuelSystem", RealisticMechanicalSystems.updateFuelSystem)
    SpecializationUtil.registerFunction(vehicleType, "updateDirectFailures", RealisticMechanicalSystems.updateDirectFailures)
    SpecializationUtil.registerFunction(vehicleType, "applyInstantDamageToSystem", RealisticMechanicalSystems.applyInstantDamageToSystem)
    
    SpecializationUtil.registerFunction(vehicleType, "isUnderService", RealisticMechanicalSystems.isUnderService)
    SpecializationUtil.registerFunction(vehicleType, "isUnderRoof", RealisticMechanicalSystems.isUnderRoof)
    SpecializationUtil.registerFunction(vehicleType, "isUnderRoofRaycastCallback", RealisticMechanicalSystems.isUnderRoofRaycastCallback)
    SpecializationUtil.registerFunction(vehicleType, "getCurrentStatus", RealisticMechanicalSystems.getCurrentStatus)
    
    SpecializationUtil.registerFunction(vehicleType, "updateThermalSystems", RMS_Thermal.updateThermalSystems)
    SpecializationUtil.registerFunction(vehicleType, "updateEngineThermalModel", RMS_Thermal.updateEngineThermalModel)
    SpecializationUtil.registerFunction(vehicleType, "updateTransmissionThermalModel", RMS_Thermal.updateTransmissionThermalModel)
    SpecializationUtil.registerFunction(vehicleType, "getSmoothedTemperature", RMS_Thermal.getSmoothedTemperature)
     
    SpecializationUtil.registerFunction(vehicleType, "updateBatteryChargingModel", RMS_Electrical.updateBatteryChargingModel)
    SpecializationUtil.registerFunction(vehicleType, "syncDeadBatteryEffect", RMS_Electrical.syncDeadBatteryEffect)
    SpecializationUtil.registerFunction(vehicleType, "syncVoltageSagEffect", RMS_Electrical.syncVoltageSagEffect)
    SpecializationUtil.registerFunction(vehicleType, "establishExternalPowerConnection", RMS_Electrical.establishExternalPowerConnection)
    SpecializationUtil.registerFunction(vehicleType, "clearExternalPowerConnection", RMS_Electrical.clearExternalPowerConnection)
    
    SpecializationUtil.registerFunction(vehicleType, "updateDrivetrain", RMS_Drivetrain.updateDrivetrain)

    SpecializationUtil.registerFunction(vehicleType, "updateRadiatorClogging", RMS_Consumables.updateRadiatorClogging)
    SpecializationUtil.registerFunction(vehicleType, "updateAirFilterClogging", RMS_Consumables.updateAirFilterClogging)
    SpecializationUtil.registerFunction(vehicleType, "updateFilterClogging", RMS_Consumables.updateFilterClogging)
    SpecializationUtil.registerFunction(vehicleType, "cleanRadiatorAndAirFilter", RMS_Consumables.cleanRadiatorAndAirFilter)
    SpecializationUtil.registerFunction(vehicleType, "updateFluidLevels", RMS_Consumables.updateFluidLevels)
    SpecializationUtil.registerFunction(vehicleType, "refillVehicleFluids", RMS_Consumables.refillVehicleFluids)
    SpecializationUtil.registerFunction(vehicleType, "topUpRepairedLeaks", RMS_Consumables.topUpRepairedLeaks)
    SpecializationUtil.registerFunction(vehicleType, "getMissingFluidShare", RMS_Consumables.getMissingFluidShare)
    SpecializationUtil.registerFunction(vehicleType, "getFluidCapacity", RMS_Consumables.getFluidCapacity)
    SpecializationUtil.registerFunction(vehicleType, "getFluidLiters", RMS_Consumables.getFluidLiters)
    SpecializationUtil.registerFunction(vehicleType, "getMissingFluidLiters", RMS_Consumables.getMissingFluidLiters)
    SpecializationUtil.registerFunction(vehicleType, "getFluidCompatibility", RMS_Consumables.getFluidCompatibility)
    SpecializationUtil.registerFunction(vehicleType, "addFluidLiters", RMS_Consumables.addFluidLiters)
    SpecializationUtil.registerFunction(vehicleType, "replaceFluidCircuit", RMS_Consumables.replaceFluidCircuit)
    SpecializationUtil.registerFunction(vehicleType, "startFieldVisualInspectionProcess", RMS_Consumables.startFieldVisualInspectionProcess)
    SpecializationUtil.registerFunction(vehicleType, "setFieldInspectionPlayerActive", RMS_Consumables.setFieldInspectionPlayerActive)
    SpecializationUtil.registerFunction(vehicleType, "updateFieldInspectionSound", RMS_Consumables.updateFieldInspectionSound)

    SpecializationUtil.registerFunction(vehicleType, "updateAiWorkerSpeed", RealisticMechanicalSystems.updateAiWorkerSpeed)
    SpecializationUtil.registerFunction(vehicleType, "updateAiWorkerBlocked", RealisticMechanicalSystems.updateAiWorkerBlocked)
    SpecializationUtil.registerFunction(vehicleType, "isWarrantyRepairCovered", RealisticMechanicalSystems.isWarrantyRepairCovered)
    SpecializationUtil.registerFunction(vehicleType, "getWarrantyLimits", RealisticMechanicalSystems.getWarrantyLimits)
    SpecializationUtil.registerFunction(vehicleType, "getIsUsedPartWarrantyCovered", RealisticMechanicalSystems.getIsUsedPartWarrantyCovered)
    SpecializationUtil.registerFunction(vehicleType, "getUsedPartOfferSummary", RealisticMechanicalSystems.getUsedPartOfferSummary)
    SpecializationUtil.registerFunction(vehicleType, "getIsWarrantyServiceOverdue", RealisticMechanicalSystems.getIsWarrantyServiceOverdue)
    SpecializationUtil.registerFunction(vehicleType, "isLeaseMaintenanceCovered", RealisticMechanicalSystems.isLeaseMaintenanceCovered)

    SpecializationUtil.registerFunction(vehicleType, "getServicePrice", RealisticMechanicalSystems.getServicePrice)
    SpecializationUtil.registerFunction(vehicleType, "getServiceDuration", RealisticMechanicalSystems.getServiceDuration)
    SpecializationUtil.registerFunction(vehicleType, "getServiceFinishTime", RealisticMechanicalSystems.getServiceFinishTime)
    SpecializationUtil.registerFunction(vehicleType, "getBreakdownRepairPrice", RealisticMechanicalSystems.getBreakdownRepairPrice)
    SpecializationUtil.registerFunction(vehicleType, "getRepairPriceLines", RealisticMechanicalSystems.getRepairPriceLines)
    SpecializationUtil.registerFunction(vehicleType, "getMaintenancePriceLines", RealisticMechanicalSystems.getMaintenancePriceLines)
    
    SpecializationUtil.registerFunction(vehicleType, "addEntryToMaintenanceLog", RealisticMechanicalSystems.addEntryToMaintenanceLog)
    SpecializationUtil.registerFunction(vehicleType, "getLastInspectedCondition", RealisticMechanicalSystems.getLastInspectedCondition)
    SpecializationUtil.registerFunction(vehicleType, "getLastInspectedService", RealisticMechanicalSystems.getLastInspectedService)
    SpecializationUtil.registerFunction(vehicleType, "getInspectionReportAge", RealisticMechanicalSystems.getInspectionReportAge)
    SpecializationUtil.registerFunction(vehicleType, "getLastMaintenanceDate", RealisticMechanicalSystems.getLastMaintenanceDate)
    SpecializationUtil.registerFunction(vehicleType, "getServiceReferenceInterval", RealisticMechanicalSystems.getServiceReferenceInterval)
    SpecializationUtil.registerFunction(vehicleType, "getServiceClocks", RealisticMechanicalSystems.getServiceClocks)
    SpecializationUtil.registerFunction(vehicleType, "getServiceClockHours", RealisticMechanicalSystems.getServiceClockHours)
    SpecializationUtil.registerFunction(vehicleType, "getServiceClockLevel", RealisticMechanicalSystems.getServiceClockLevel)
    SpecializationUtil.registerFunction(vehicleType, "getServiceSchedule", RealisticMechanicalSystems.getServiceSchedule)
    SpecializationUtil.registerFunction(vehicleType, "getNextServiceClock", RealisticMechanicalSystems.getNextServiceClock)
    SpecializationUtil.registerFunction(vehicleType, "getServiceCountdown", RealisticMechanicalSystems.getServiceCountdown)
    SpecializationUtil.registerFunction(vehicleType, "getDueMaintenanceType", RealisticMechanicalSystems.getDueMaintenanceType)
    SpecializationUtil.registerFunction(vehicleType, "getMaintenanceTypes", RealisticMechanicalSystems.getMaintenanceTypes)
    SpecializationUtil.registerFunction(vehicleType, "getMaintenanceLevelInterval", RealisticMechanicalSystems.getMaintenanceLevelInterval)
    SpecializationUtil.registerFunction(vehicleType, "getLastServiceOptions", RealisticMechanicalSystems.getLastServiceOptions)
    SpecializationUtil.registerFunction(vehicleType, "getPerformedServiceCount", RealisticMechanicalSystems.getPerformedServiceCount)
    
end

function RealisticMechanicalSystems:onLeaveVehicle(wasEntered)
    local spec = self.spec_RealisticMechanicalSystems
    if spec == nil then
        return
    end

    -- The next driver gets every warning afresh
    spec.lastBlinkingWarningMessage, spec.blinkingWarningTimer = "", 0

    RMS_Start.onLeaveVehicle(self)
    RMS_Drivetrain.onDriverLeft(self, wasEntered)
end

---Frees the implements of a machine left without its park brake
function RealisticMechanicalSystems:onDeactivate()
    RMS_Drivetrain.restoreFreeRolling(self)
end

---Registers the specialization action events
function RealisticMechanicalSystems:onRegisterActionEvents(isActiveForInput, isActiveForInputIgnoreSelection)
    if not self.isClient then
        return
    end

    local spec = self.spec_RealisticMechanicalSystems
    if spec == nil then
        return
    end

    self:clearActionEventsTable(spec.odometerActionEvents)
    self:clearActionEventsTable(spec.fanActionEvents)

    RMS_Drivetrain.registerActionEvents(self, isActiveForInputIgnoreSelection)

    if not isActiveForInputIgnoreSelection then
        return
    end

    if not spec.isExcludedVehicle and self.spec_drivable ~= nil then
        local _, odometerEventId = self:addActionEvent(spec.odometerActionEvents, InputAction.RMS_TOGGLE_ODOMETER, self,
            RealisticMechanicalSystems.onOdometerAction, true, true, true, true, nil)
        if odometerEventId ~= nil then
            g_inputBinding:setActionEventText(odometerEventId, g_i18n:getText("input_RMS_TOGGLE_ODOMETER"))
            g_inputBinding:setActionEventTextPriority(odometerEventId, GS_PRIO_HIGH)
            g_inputBinding:setActionEventTextVisibility(odometerEventId, true)
        end
    end

    if not spec.isExcludedVehicle and spec.hasReversibleFan then
        local _, fanEventId = self:addActionEvent(spec.fanActionEvents, InputAction.RMS_REVERSE_FAN, self,
            RealisticMechanicalSystems.onReverseFanAction, false, true, false, true, nil)
        if fanEventId ~= nil then
            g_inputBinding:setActionEventText(fanEventId, g_i18n:getText("input_RMS_REVERSE_FAN"))
            g_inputBinding:setActionEventTextPriority(fanEventId, GS_PRIO_HIGH)
            g_inputBinding:setActionEventTextVisibility(fanEventId, true)
        end
    end
end

function RealisticMechanicalSystems:onReverseFanAction()
    RMS_SoundManager.playSample(self.spec_RealisticMechanicalSystems.samples.fanReversalSwitch)
    RMS_FanReversalEvent.send(self)
end

---Odometer key: a press switches odometer and trip, a hold resets the trip
function RealisticMechanicalSystems:onOdometerAction(actionName, inputValue)
    local spec = self.spec_RealisticMechanicalSystems
    if inputValue == 0 then
        if not spec.odometerHoldHandled then
            spec.odometerShowsTrip = not spec.odometerShowsTrip
        end
        spec.odometerHoldTime = 0
        spec.odometerHoldHandled = false
        return
    end

    spec.odometerHoldTime = spec.odometerHoldTime + g_currentDt
    if spec.odometerShowsTrip and not spec.odometerHoldHandled and spec.odometerHoldTime >= 1000 then
        spec.odometerHoldHandled = true
        RealisticMechanicalSystems.resetTripMeter(self)
    end
end

---Resets the trip meter to the current odometer reading, on every machine
function RealisticMechanicalSystems.resetTripMeter(vehicle, noEventSend)
    vehicle.spec_RealisticMechanicalSystems.tripStartKilometers = RMS_Utils.getOdometerKilometers(vehicle)
    RMS_TripResetEvent.sendEvent(vehicle, noEventSend)
end

local function getOwnerServicePeriod(clock, care)
    local drop = RMS_Config.CORE.BASE_SERVICE_WEAR / clock.intervalFactor
    local threshold = care == "neglected" and 0 or RMS_Config.CORE.SERVICE_EXPIRED_THRESHOLD
    return (1 - threshold) / drop, drop
end

local function getHistoryWearRate(spec, systemKey, index, partId, care)
    local history = RMS_Config.CORE.USED_VEHICLE_HISTORY
    local entry = RMS_Breakdowns.BreakdownRegistry[partId]
    local baseShare = 1
    if entry.wearsByCausesOnly then
        baseShare = 0
    elseif entry.wearsWhile ~= nil then
        baseShare = history.LIT_SHARE
    end
    local rate = (history.BASE_RATES[systemKey] or 1) * baseShare
    local shares = spec.partCauseShares[systemKey]
    for _, causes in ipairs({ history.WORK_CAUSES[systemKey] or {}, history.CARE_CAUSES[care][systemKey] or {} }) do
        for alias, value in pairs(causes) do
            rate = rate + value * (shares[alias] ~= nil and shares[alias][index] or baseShare)
        end
    end
    return rate * RMS_Config.CORE.BASE_SYSTEMS_WEAR / math.max(spec.reliability or 1, 0.001)
end

local function drawPartLife(partId)
    local C = RMS_Config.CORE
    local life = C.COMPONENT_LIVES[RMS_Breakdowns.BreakdownRegistry[partId].component]
    return life.scale / C.MACHINE_LIFE_HOURS * (-math.log(1 - math.random())) ^ (1 / life.shape)
end

---Returns the wear of a lit part without record
function RealisticMechanicalSystems.getUnrecordedLitPartWear(vehicle, partId)
    local C = RMS_Config.CORE
    local wear = vehicle:getOperatingTime() / 3600000 * C.USED_VEHICLE_HISTORY.LIT_SHARE * C.BASE_SYSTEMS_WEAR
        / math.max(vehicle.spec_RealisticMechanicalSystems.reliability or 1, 0.001)
    local life = drawPartLife(partId)
    while wear > life do
        wear = wear - life
        life = drawPartLife(partId)
    end
    return wear
end

local function addAgedBreakdown(vehicle, partId, elapsed)
    local stages = RMS_Breakdowns.BreakdownRegistry[partId].stages
    local stage = 1
    local duration = RealisticMechanicalSystems.getStageDuration(stages[stage])
    while duration ~= nil and stages[stage + 1] ~= nil and elapsed >= duration do
        elapsed = elapsed - duration
        stage = stage + 1
        duration = RealisticMechanicalSystems.getStageDuration(stages[stage])
    end
    vehicle:addBreakdown(partId, { stage = stage, progressTimer = duration ~= nil and elapsed or 0,
        isVisible = stage == #stages and stages[stage].detectionChance > 0 })
end

-- @param boolean withBreakdowns false for a contract machine, lent in working order
function RealisticMechanicalSystems.initializeUsedVehicle(vehicle, care, withBreakdowns)
    local spec = vehicle.spec_RealisticMechanicalSystems
    local C = RMS_Config.CORE
    local hours = vehicle:getOperatingTime() / 3600000

    local sinceService, preventivePeriod = hours, math.huge
    for _, clock in ipairs(RealisticMechanicalSystems.SERVICE_CLOCKS) do
        local period, drop = getOwnerServicePeriod(clock, care)
        local since = hours % period
        spec[clock.levelKey] = 1 - drop * since
        if clock.key == "engine" then
            sinceService = since
        end
        if clock.maintenanceType == "PREVENTIVE" then
            preventivePeriod = period
        end
    end

    local parts = {}
    for systemKey, systemParts in pairs(spec.systemParts) do
        for index, partId in ipairs(systemParts) do
            parts[partId] = { rate = getHistoryWearRate(spec, systemKey, index, partId, care), age = 0, life = drawPartLife(partId),
                renewal = { partId } }
            for _, group in ipairs(C.RENEWAL_GROUPS) do
                if table.hasElement(group, partId) then
                    parts[partId].renewal = group
                    break
                end
            end
        end
    end

    local time, nextPreventive = 0, preventivePeriod
    while time < hours do
        local failedId, step = nil, math.min(hours, nextPreventive) - time
        for partId, part in pairs(parts) do
            if part.rate > 0 and (part.life - part.age) / part.rate < step then
                failedId, step = partId, (part.life - part.age) / part.rate
            end
        end
        for _, part in pairs(parts) do
            part.age = part.age + part.rate * step
        end
        time = time + step
        if failedId ~= nil then
            parts[failedId].failedAt = time
            for _, partId in ipairs(parts[failedId].renewal) do
                if parts[partId] ~= nil then
                    parts[partId].age, parts[partId].life = 0, drawPartLife(partId)
                end
            end
        elseif time >= nextPreventive then
            for _, partId in ipairs(RealisticMechanicalSystems.MAJOR_SERVICE_CHECKS) do
                local part = parts[partId]
                if part ~= nil and RMS_Utils.getIsPartWorn(partId, part.age) then
                    part.age, part.life = 0, drawPartLife(partId)
                end
            end
            nextPreventive = nextPreventive + preventivePeriod
        end
    end

    for systemKey, systemParts in pairs(spec.systemParts) do
        for _, partId in ipairs(systemParts) do
            spec.partWear[partId] = parts[partId].age
            spec.partAbuse[partId] = nil
            spec.partDrawnWear[partId] = nil
        end
        RealisticMechanicalSystems.refreshSystemCondition(spec, systemKey)
    end
    vehicle:updateConditionLevel()
    vehicle:setDamageAmount(0.0, true)

    if withBreakdowns then
        vehicle:removeBreakdown()
        if care == "neglected" then
            for partId, part in pairs(parts) do
                if part.failedAt ~= nil and hours - part.failedAt <= sinceService then
                    addAgedBreakdown(vehicle, partId, (hours - part.failedAt) * 3600000)
                end
            end
        end
    end
end

-- @return table wear wear by part id
function RealisticMechanicalSystems.getAverageMachineWear(vehicle, hours)
    local spec = vehicle.spec_RealisticMechanicalSystems
    local preventivePeriod = math.huge
    for _, clock in ipairs(RealisticMechanicalSystems.SERVICE_CLOCKS) do
        if clock.maintenanceType == "PREVENTIVE" then
            preventivePeriod = getOwnerServicePeriod(clock, "regular")
        end
    end

    local wear = {}
    for systemKey, systemParts in pairs(spec.systemParts) do
        for index, partId in ipairs(systemParts) do
            local rate = getHistoryWearRate(spec, systemKey, index, partId, "regular")
            local renewedAt = 0
            if table.hasElement(RealisticMechanicalSystems.MAJOR_SERVICE_CHECKS, partId) then
                for due = preventivePeriod, hours, preventivePeriod do
                    if RMS_Utils.getIsPartWorn(partId, rate * (due - renewedAt)) then
                        renewedAt = due
                    end
                end
            end
            wear[partId] = rate * (hours - renewedAt)
        end
    end
    return wear
end

function RealisticMechanicalSystems.getCatchUpPrice(vehicle, hours)
    local spec = vehicle.spec_RealisticMechanicalSystems
    local average = RealisticMechanicalSystems.getAverageMachineWear(vehicle, hours)
    local price = 0
    for partId, averageWear in pairs(average) do
        local ahead = spec.partWear[partId] - averageWear
        if ahead > 0 and spec.activeBreakdowns[partId] == nil then
            price = price + RealisticMechanicalSystems.getPartReplacementPrice(vehicle, partId) * math.min(ahead, 1)
        end
    end
    return price
end

---Adds or removes a breakdown as the vehicle state asks
local function setBreakdownPresent(vehicle, breakdownId, isPresent)
    local hasBreakdown = vehicle:hasBreakdown(breakdownId)
    if isPresent and not hasBreakdown then
        vehicle:addBreakdown(breakdownId)
    elseif not isPresent and hasBreakdown then
        vehicle:removeBreakdown(breakdownId)
    end
end

---Puts a breakdown at the stage the vehicle asks, 0 removing it
local function setBreakdownStage(vehicle, breakdownId, stage)
    local hasBreakdown = vehicle:hasBreakdown(breakdownId)
    if stage <= 0 then
        if hasBreakdown then
            vehicle:removeBreakdown(breakdownId)
        end
    elseif not hasBreakdown then
        vehicle:addBreakdown(breakdownId, stage)
    elseif vehicle:getActiveBreakdowns()[breakdownId].stage ~= stage then
        vehicle:changeBreakdownStage(breakdownId, stage)
    end
end

---Tells whether an active effect carries a flag in its extra data
local function hasEffectFlag(spec, flag)
    for _, effect in pairs(spec.activeEffects or {}) do
        if effect.extraData ~= nil and effect.extraData[flag] then
            return true
        end
    end
    return false
end

---Tells whether a vehicle is owned, leased or lent by an existing farm
local function getIsFarmVehicle(vehicle)
    local PROPERTY = VehiclePropertyState
    local state = vehicle.propertyState
    if state ~= PROPERTY.OWNED and state ~= PROPERTY.LEASED and state ~= PROPERTY.MISSION then
        return false
    end
    local farmId = vehicle.getOwnerFarmId ~= nil and vehicle:getOwnerFarmId() or vehicle.ownerFarmId
    return farmId ~= nil and farmId ~= FarmManager.SPECTATOR_FARM_ID and g_farmManager:getFarmById(farmId) ~= nil
end

---Removes the breakdowns the parts of this vehicle cannot have
local function removeInapplicableBreakdowns(vehicle, spec)
    local breakdownIds = {}
    for breakdownId in pairs(spec.activeBreakdowns) do
        local definition = RMS_Breakdowns.BreakdownRegistry[breakdownId]
        if definition == nil or not definition.isApplicable(vehicle) then
            table.insert(breakdownIds, breakdownId)
        end
    end
    if #breakdownIds > 0 then
        vehicle:removeBreakdown(unpack(breakdownIds))
    end
end

---Seeds a vehicle new to RMS from its hours and damage
local function initializeNewToRMS(vehicle, spec)
    spec.isNewToRMS = false
    local isMission = RealisticMechanicalSystems.isMissionVehicle(vehicle)
    local isUsed = vehicle:getFormattedOperatingTime() > 0.01
    if isUsed and not spec.isExcludedVehicle then
        local care = isMission and "careful" or RMS_Utils.getOwnerCare(vehicle:getDamageAmount())
        RealisticMechanicalSystems.initializeUsedVehicle(vehicle, care, not isMission)
    end
    -- A new or lent machine comes with the report of its delivery inspection
    if (not isUsed or isMission) and (spec.maintenanceLog == nil or #spec.maintenanceLog == 0) then
        local TYPES = RealisticMechanicalSystems.INSPECTION_TYPES
        vehicle:addEntryToMaintenanceLog(RealisticMechanicalSystems.STATUS.INSPECTION, isMission and TYPES.STANDARD or TYPES.COMPLETE,
            "NONE", 0)
    end
end

---Puts a farm vehicle under RMS once, its data read and checked
local function registerVehicle(vehicle)
    if RMS_Main == nil or RMS_Main.vehicles == nil or RMS_Main.vehicles[vehicle.uniqueId] ~= nil or not getIsFarmVehicle(vehicle) then
        return
    end
    local spec = vehicle.spec_RealisticMechanicalSystems
    if spec == nil then
        return
    end
    RMS_Main.vehicles[vehicle.uniqueId] = vehicle
    RMS_Main.numVehicles = RMS_Main.numVehicles + 1
    spec.reliability = RealisticMechanicalSystems.getBrandReliability(vehicle)

    local storeItem = g_storeManager:getItemByXMLFilename(vehicle.configFileName)
    if storeItem ~= nil then
        spec.year, spec.yearSource = RMS_ProductionYear.getVehicleYear(vehicle, storeItem)
        spec.yearIsKnown = spec.yearSource ~= RMS_ProductionYear.SOURCE.UNKNOWN
        spec.electricalRating = RMS_Electrical.resolveRating(vehicle)
    end
    spec.hasParticulateFilter = RMS_Exhaust.getHasParticulateFilter(vehicle)
    RealisticMechanicalSystems.buildSystemParts(vehicle)

    if vehicle.isServer then
        removeInapplicableBreakdowns(vehicle, spec)
        if spec.isNewToRMS then
            initializeNewToRMS(vehicle, spec)
        end
        RMS_Drivetrain.resolveParkBrakeKind(vehicle)
    end

    -- The wear statistics count from the hours the vehicle has now
    local hours = getVehicleOperatingHours(vehicle)
    for _, stats in pairs(ensureFactorStats(spec)) do
        if type(stats) == "table" and (tonumber(stats.operatingHours) or -1) < 0 then
            stats.operatingHours = hours
        end
    end
end
RealisticMechanicalSystems.registerVehicle = registerVehicle

---Keeps the cold engine breakdown at -10 degrees or less
local function syncColdEngineEffect(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    if spec == nil or not vehicle.isServer then
        return
    end
    local temperature = RealisticMechanicalSystems.sanitizeNumber(spec.rawEngineTemperature or spec.engineTemperature, -99, -99, 160)
    setBreakdownPresent(vehicle, "COLD_ENGINE", temperature <= -10)
end

---Stages the air filter breakdown, a third of the threshold apart
local function syncAirFilterCloggingEffect(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    if spec == nil or not vehicle.isServer then
        return
    end
    local threshold = RMS_Config.FIELD_CARE.AIR_FILTER_BREAKDOWN_THRESHOLD
    local stage = 0
    for step = 0, 2 do
        if spec.airFilterClogging > threshold + threshold / 3 * step then
            stage = step + 1
        end
    end
    setBreakdownStage(vehicle, "AIRFILTER_CLOGGING", stage)
end

---Stops the AI worker and a route driver a breakdown forbids
local function syncDisableAiWorkers(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    if spec == nil or not vehicle.isServer or not hasEffectFlag(spec, "disableAi") then
        return
    end

    local routeDriver = vehicle.ad
    local driverState = routeDriver ~= nil and routeDriver.stateModule or nil
    if driverState ~= nil and driverState.isActive ~= nil and driverState:isActive() and vehicle.stopAutoDrive ~= nil then
        -- Stopped as on its own error, its loops reset
        routeDriver.isStoppingWithError = true
        if driverState.setLoopsDone ~= nil then
            driverState:setLoopsDone(0)
        end
        vehicle:stopAutoDrive()
    end
    if vehicle:getIsAIActive() and vehicle.stopCurrentAIJob ~= nil then
        vehicle:stopCurrentAIJob(AIMessageErrorVehicleBroken.new())
    end
end

local COLD_ENGINE_WARNING_MESSAGE = 'rms_spec_cold_engine_message'

local function getColdEngineStress(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    local C = RMS_Config.CORE.ENGINE_FACTOR_DATA
    local engineTemperature = RealisticMechanicalSystems.sanitizeNumber(spec.rawEngineTemperature or spec.engineTemperature, -99, -99, 160)

    if not vehicle:getIsMotorStarted()
            or vehicle:getIsAIActive()
            or engineTemperature >= C.COLD_MOTOR_TEMP_THRESHOLD then
        return 0
    end
    local below = C.COLD_MOTOR_TEMP_THRESHOLD - math.max(engineTemperature, C.COLD_MOTOR_MEASURED_MIN)
    return math.exp(C.COLD_MOTOR_WEAR_SLOPE * below) - 1
end
RealisticMechanicalSystems.getColdEngineStress = getColdEngineStress

---Delay before the same blinking warning shows again, in ms
local BLINKING_WARNING_REPEAT_MS = 180000

---Cold engine, or past an alert temperature
local function getThermalWarning(vehicle, spec, dt)
    local ENGINE = RMS_Config.CORE.ENGINE_FACTOR_DATA
    local message, isCold = nil, false
    -- -90 and below: no temperature read yet
    if spec.engineTemperature > -90 then
        isCold = spec.engineTemperature < ENGINE.COLD_MOTOR_TEMP_THRESHOLD
        if isCold then
            spec.coldEngineExposureMs = spec.coldEngineExposureMs + dt
            if spec.coldEngineExposureMs >= ENGINE.COLD_MOTOR_WARNING_EXPOSURE_MS and not spec.coldEngineWarningShown then
                message = COLD_ENGINE_WARNING_MESSAGE
            end
        end
        if message == nil and spec.engineTemperature >= ENGINE.OVERHEAT_MOTOR_WARNING
            and vehicle:getMotorLoadPercentage() > ENGINE.OVERHEAT_MOTOR_WARNING_LOAD then
            message = "rms_spec_overheat_engine_message"
        end
    end

    local transmissionLimit = RMS_Config.CORE.TRANSMISSION_FACTOR_DATA.OVERHEAT_TRANSMISSION_WARNING
    if message == nil and spec.transmissionTemperature > -90 and spec.transmissionTemperature >= transmissionLimit then
        message = "rms_spec_overheat_transmission_message"
    end
    return message, isCold
end

---Blinks a thermal or breakdown warning, again after a delay
local function syncBlinkingWarning(vehicle, dt)
    local spec = vehicle.spec_RealisticMechanicalSystems
    if spec == nil or not vehicle.isClient then
        return
    end
    if spec.engineTemperature >= RMS_Config.CORE.ENGINE_FACTOR_DATA.COLD_MOTOR_TEMP_THRESHOLD then
        spec.coldEngineExposureMs, spec.coldEngineWarningShown = 0, false
    end
    local effects = spec.activeEffects or {}
    -- Warnings off, the thermal power limit still warns
    if RMS_Config.CORE.ENABLE_WARNING_MESSAGES == false and effects.ENGINE_THERMAL_TORQUE_LIMIT == nil then
        return
    end
    spec.blinkingWarningTimer = math.max((spec.blinkingWarningTimer or 0) - dt, 0)
    spec.lastBlinkingWarningMessage = spec.lastBlinkingWarningMessage or ""

    local isDriven = vehicle:getIsActiveForInput(true)
    local isAiActive = vehicle:getIsAIActive()
    local isUnderService = vehicle:isUnderService()
    local motor = vehicle.spec_motorized ~= nil and vehicle.spec_motorized.motor or nil
    local message, isCold = nil, false
    if vehicle:getIsMotorStarted() and isDriven and not isAiActive and not spec.isElectricVehicle and motor ~= nil then
        message, isCold = getThermalWarning(vehicle, spec, dt)
    end
    if not isCold then
        spec.coldEngineExposureMs = math.max(spec.coldEngineExposureMs - dt, 0)
    end

    -- The thermal power limit comes first, then any breakdown message
    local limit = effects.ENGINE_THERMAL_TORQUE_LIMIT
    if limit ~= nil and limit.extraData ~= nil and not isUnderService then
        message = limit.extraData.message
    end
    if message == nil and isDriven and not isUnderService then
        for _, effect in pairs(effects) do
            if effect.extraData ~= nil and effect.extraData.message ~= nil then
                message = effect.extraData.message
                break
            end
        end
    end

    local isNew = spec.blinkingWarningTimer == 0 or spec.lastBlinkingWarningMessage ~= message
    if message ~= nil and isDriven and not isAiActive and not isUnderService and isNew then
        g_currentMission:showBlinkingWarning(g_i18n:getText(message), 3600)
        spec.lastBlinkingWarningMessage = message
        spec.blinkingWarningTimer = BLINKING_WARNING_REPEAT_MS
        if message == COLD_ENGINE_WARNING_MESSAGE then
            spec.coldEngineWarningShown = true
        end
    end
end

local function syncFaultCodeMessages(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    local pending = spec.pendingFaultCodeMessages
    if pending == nil or pending[1] == nil then
        return
    end
    local warningsEnabled = RMS_Config.CORE.ENABLE_WARNING_MESSAGES ~= false
    local driverReads = vehicle:getIsActiveForInput(true) and not vehicle:getIsAIActive() and not vehicle:isUnderService()
    local waiting = {}
    for _, message in ipairs(pending) do
        if warningsEnabled and spec.displayedFaultCodes[message.key] then
            if not message.toDriver then
                g_currentMission.hud:addSideNotification(message.isCritical and RMS_Breakdowns.COLORS.CRITICAL
                    or RMS_Breakdowns.COLORS.WARNING, string.format(g_i18n:getText("rms_hud_vehicle_notification"),
                    vehicle:getFullName(), message.text))
            elseif driverReads then
                g_currentMission:showBlinkingWarning(message.text, 3600)
            else
                table.insert(waiting, message)
            end
        end
    end
    spec.pendingFaultCodeMessages = waiting
end

---Shows the side notifications the effects left, once each
local function syncSideNotifications(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    if spec == nil or not vehicle.isClient then
        return
    end

    -- Pending warnings are runtime state, not join history.
    local pending = spec.pendingSideNotifications
    spec.pendingSideNotifications = {}
    local hud = g_currentMission.hud
    if pending == nil or next(pending) == nil or vehicle:getOwnerFarmId() ~= g_currentMission:getFarmId()
        or hud == nil or hud.addSideNotification == nil then
        return
    end

    local warningsEnabled = RMS_Config.CORE == nil or RMS_Config.CORE.ENABLE_WARNING_MESSAGES ~= false
    local shownMessages = {}
    for effectId, messageKey in pairs(pending) do
        local effect = spec.activeEffects ~= nil and spec.activeEffects[effectId] or nil
        local thermalRecovery = effectId == "ENGINE_THERMAL_TORQUE_LIMIT"
            and messageKey == "rms_thermal_power_restored_message" and effect == nil
        if (warningsEnabled or effectId == "ENGINE_THERMAL_TORQUE_LIMIT")
                and (thermalRecovery or (effect ~= nil and effect.extraData ~= nil and effect.extraData.message == messageKey))
                and not shownMessages[messageKey] then
            g_currentMission.hud:addSideNotification(RMS_Breakdowns.COLORS.WARNING, string.format(
                g_i18n:getText("rms_hud_vehicle_notification"), vehicle:getFullName(), g_i18n:getText(messageKey)))
            shownMessages[messageKey] = true
        end
    end
end

---Fuel use the server measures, shown as is on the clients
local function syncFuelConsumption(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    local motorized = vehicle.spec_motorized
    if spec == nil or motorized == nil then
        return
    end
    local sanitize = RealisticMechanicalSystems.sanitizeNumber
    if vehicle.isServer then
        local isRunning = vehicle.getIsMotorStarted ~= nil and vehicle:getIsMotorStarted()
        spec._fuelUsageRaw = isRunning and sanitize(motorized.lastFuelUsage, 0, 0, 10000) or 0
    elseif vehicle.isClient then
        motorized.lastFuelUsage = sanitize(spec._fuelUsageRaw, 0, 0, 10000)
    end
end

---Stages the CVT addon breakdown from its damage: 60 % then each 10 %
local function syncCVTaddonBreakdown(vehicle)
    if not hasCVTAddon(vehicle) then
        return
    end
    local spec = vehicle.spec_RealisticMechanicalSystems
    if spec == nil or not vehicle.isServer then
        return
    end
    local damage = vehicle.spec_CVTaddon.CVTdamage
    local stage = 0
    for index, limit in ipairs({ 60.0, 70.0, 80.0, 90.0 }) do
        if damage > limit then
            stage = index
        end
    end
    setBreakdownStage(vehicle, "CVT_ADDON_MALFUNCTION", stage)
end

---Stages the overload breakdown from the averaged wear rate of the drive
local function syncOverloadWarning(vehicle, dt)
    local spec = vehicle.spec_RealisticMechanicalSystems
    if spec == nil or not vehicle.isServer then
        return
    end
    local CORE = RMS_Config.CORE
    local wearScale = CORE.BASE_SYSTEMS_WEAR / CORE.REFERENCE_SYSTEMS_WEAR
    local warning, critical = CORE.AVG_STRESS_WARNING_THRESHOLD * wearScale, CORE.AVG_STRESS_CRITICAL_THRESHOLD * wearScale
    local sampleMs = math.max(tonumber(dt) or 0, 1)
    local isRunning = vehicle.getIsMotorStarted ~= nil and vehicle:getIsMotorStarted()

    local stage, highestAverage, highestRate = 0, 0, 0
    for systemName, stats in pairs(ensureFactorStats(spec)) do
        if type(stats) == "table" then
            local aliases = OVERLOAD_FACTOR_ALIASES_BY_SYSTEM[tostring(systemName)]
            local stress = 0
            if type(aliases) == "table" then
                for _, alias in ipairs(aliases) do
                    stress = stress + math.max(tonumber(stats[alias]) or 0, 0)
                end
                -- A weighted system counts ten times
                stress = stress * (CORE.SYSTEM_WEIGHTS[systemName] ~= nil and 10.0 or 1.0)
            end
            local previous = tonumber(stats._prevStress) or stress
            stats._prevStress = stress

            if not isRunning then
                resetOverloadAverage(stats)
            else
                local rate = math.max(stress - previous, 0) * 3600000 / sampleMs
                stats._avgStress = updateOverloadAverage(stats, sampleMs, rate)
                highestAverage = math.max(highestAverage, stats._avgStress)
                if type(aliases) == "table" and #aliases > 0 then
                    highestRate = math.max(highestRate, rate)
                    if stats._avgStress > critical then
                        stage = 2
                    elseif stats._avgStress > warning and stage == 0 then
                        stage = 1
                    end
                end
            end
        end
    end
    spec.overloadLevel = highestRate / warning

    if RealisticMechanicalSystems.isMissionVehicle(vehicle) then
        return
    end
    local current = (spec.activeBreakdowns or {}).STRESS_OVERLOAD
    if stage > 0 then
        if current == nil then
            vehicle:addBreakdown("STRESS_OVERLOAD", stage)
        elseif current.stage < stage then
            vehicle:changeBreakdownStage("STRESS_OVERLOAD", stage)
        end
    -- Cleared once the worst average falls under half the warning
    elseif current ~= nil and highestAverage < warning * 0.5 then
        vehicle:removeBreakdown("STRESS_OVERLOAD")
    end
end

---Smooths the engine load over about 300 ms
local function getSmoothedMotorLoad(vehicle, dt)
    local spec = vehicle.spec_RealisticMechanicalSystems
    if spec == nil then
        return
    end
    if not vehicle:getIsMotorStarted() then
        spec._smoothedMotorLoad = 0
        return
    end
    local load = math.max(vehicle:getMotorLoadPercentage() or 0, 0)
    local previous = spec._smoothedMotorLoad or 0
    spec._smoothedMotorLoad = previous + math.min(dt / (300 + dt), 1) * (load - previous)
end

---Updates the specialization every rendered frame
function RealisticMechanicalSystems:onUpdate(dt, ...)
    local spec = self.spec_RealisticMechanicalSystems
    self:updateFieldInspectionSound()
    if spec.isExcludedVehicle then return end

    RMS_Thermal.getEngineTemperature(self)
    RMS_Bodywork.syncPreview(self)

    self:updateVehicleStateSnapshot(dt)
    if self.isServer then
        RMS_Steering.updateTerrainImpacts(self, dt)
        self:updateThermalSystems(dt, false, true)
        RMS_Thermal.updateFanReversal(self, dt)
    end
    RMS_Start.update(self, dt)
    RMS_Breakdowns.updateStarter(self, dt)

    local updateDelay = RMS_Config.ON_UPDATE_DELAY
    spec.onUpdateTimer = spec.onUpdateTimer + dt

    if spec.onUpdateTimer < updateDelay then
        return
    end

    -- Discard missed sample intervals.
    spec.onUpdateTimer = spec.onUpdateTimer % updateDelay
    local updateDt = updateDelay

    registerVehicle(self)

    if self.isServer and RMS_Main and RMS_Main.vehicles and RMS_Main.vehicles[self.uniqueId] == nil and self:getIsControlled() then
        self:updateThermalSystems(updateDt, true, not self:getIsMotorStarted())
        self:updateBatteryChargingModel(updateDt)
    end

    self:getSmoothedTemperature(updateDt)

    if self.isServer then
        RMS_Fluids.updatePickups(self, updateDt)
    end
    if self.isClient then
        RMS_Breakdowns.updateAerationWhines(self)
    end

    syncFuelConsumption(self)

    getSmoothedMotorLoad(self, updateDt)

    if spec.isElectricVehicle then
        RMS_ElectricDrive.syncColdBattery(self)
    else
        syncColdEngineEffect(self)
    end

    self:syncDeadBatteryEffect()

    self:syncVoltageSagEffect(updateDt)

    syncAirFilterCloggingEffect(self)

    if self.isServer then
        RMS_Consumables.syncFilterBreakdowns(self)
    end

    syncCVTaddonBreakdown(self)
    
    syncBlinkingWarning(self, updateDt)

    syncSideNotifications(self)

    syncFaultCodeMessages(self)

    syncDisableAiWorkers(self)

    self:updateDrivetrain(updateDt)

    if self.isServer and self.getDamageAmount ~= nil and self:getDamageAmount() ~= 0 then self:setDamageAmount(0.0, true) end
    
    self:updateAiWorkerSpeed(updateDt)
    self:updateAiWorkerBlocked(updateDt)

    if self.isClient then
        RMS_Exhaust.update(self)
    end

    -- Effects that act on each step
    for _, applyEffect in pairs(spec.activeFunctions or {}) do
        applyEffect(self, updateDt)
    end
end

---Applies client-side effects after the rendered-frame update
function RealisticMechanicalSystems:onPostUpdate(dt, ...)
    local spec = self.spec_RealisticMechanicalSystems
    if not self.isClient or spec.isExcludedVehicle then return end

    RMS_Exhaust.applyShader(self, dt)
end

function RealisticMechanicalSystems:onStartMotor()
    local spec = self.spec_RealisticMechanicalSystems
    RMS_Breakdowns.onStarterCaught(self)
    RMS_Start.onStartMotor(self)
    if self.isClient and not spec.isExcludedVehicle then
        RMS_Exhaust.update(self)
        if spec.isElectricVehicle then
            RMS_SoundManager.playSample(spec.samples.hvContactor)
        end
    end
end

function RealisticMechanicalSystems:onStopMotor()
    local spec = self.spec_RealisticMechanicalSystems
    if self.isClient and not spec.isExcludedVehicle and spec.isElectricVehicle then
        RMS_SoundManager.playSample(spec.samples.hvContactor)
    end
    RMS_Drivetrain.refreshParkBrakePedal(self)
    if self.spec_lights ~= nil and RMS_Breakdowns.getLoadedSpec(self) ~= nil and RMS_Electrical.getKeepsLightsOff(self) then
        if self:getLightsTypesMask() ~= 0 then
            self:setLightsTypesMask(0, true, not self.isServer)
        end
        if self:getBeaconLightsVisibility() then
            self:setBeaconLightsVisibility(false, true, not self.isServer)
        end
        local turnLightState = self:getTurnLightState()
        if turnLightState ~= Lights.TURNLIGHT_OFF and turnLightState ~= Lights.TURNLIGHT_HAZARD then
            self:setTurnLightState(Lights.TURNLIGHT_OFF, true, not self.isServer)
        end
    end
end

---Runs the vehicle simulation step: state, wear, thermal, electrical, services
-- each system wears in turn, a disabled one skipping its update
local SYSTEM_WEAR_UPDATES = { "updateEngineSystem", "updateTransmissionSystem", "updateHydraulicsSystem", "updatePtoSystem",
    "updateHarvestSystem", "updateCoolingSystem", "updateElectricalSystem", "updateChassisSystem", "updateFuelSystem" }

---Tells the clients a lent machine now belongs to its farm
local function syncPropertyState(vehicle, spec)
    if vehicle.isServer and spec.syncedPropertyState ~= vehicle.propertyState then
        if spec.syncedPropertyState ~= nil then
            RealisticMechanicalSystems.raiseRMSDirty(vehicle, RealisticMechanicalSystems.SYNC_GROUP.STATE)
        end
        spec.syncedPropertyState = vehicle.propertyState
    end
end
RealisticMechanicalSystems.syncPropertyState = syncPropertyState

function RealisticMechanicalSystems:rmsUpdate(dt, isWorkshopOpen)
    local spec = self.spec_RealisticMechanicalSystems
    if spec.isExcludedVehicle then return end
    syncPropertyState(self, spec)

    -- RMS counts its own working time, from the game's when first seen
    local gameTime = self.getOperatingTime ~= nil and self:getOperatingTime() or self.operatingTime or 0
    if (spec.realOperatingTime or 0) <= 0 and gameTime > 0 then
        spec.realOperatingTime = gameTime
    end
    local isRunning = self.getMotorState ~= nil and self:getMotorState() == MotorState.ON
    local operatingDt = isRunning and (dt or 0) or 0
    if isRunning then
        spec.realOperatingTime = (spec.realOperatingTime or 0) + dt
    end

    self:updateThermalSystems(dt, true, not self:getIsMotorStarted())
    self:updateBatteryChargingModel(dt)

    if self:isUnderService() then
        self:processService(dt)
    else
        local isOperating = self:getIsOperating()
        local isMissionVehicle = RealisticMechanicalSystems.isMissionVehicle(self)
        if not isMissionVehicle then
            self:updateRadiatorClogging(dt, isOperating)
        end

        if isOperating and not isMissionVehicle then
            self:updateAirFilterClogging(dt)
            self:processBreakdowns(dt)
            self:tryTriggerBreakdown()
        end

        self:updateServiceLevel(dt)
        for _, updateSystem in ipairs(SYSTEM_WEAR_UPDATES) do
            self[updateSystem](self, dt)
        end
        self:updateDirectFailures(dt)
        self:updateConditionLevel()
        self:processWornParts()
        if not isMissionVehicle then
            RMS_Greasing.updateMachine(self, operatingDt)
            self:updateFluidLevels(operatingDt)
            self:updateFilterClogging(operatingDt)
        end
        syncOverloadWarning(self, dt)
    end

    if self.isServer and spec.isElectricVehicle then
        RMS_ElectricDrive.applyBatteryCapacity(self)
    end

    if self.isServer then
        RealisticMechanicalSystems.markSyncGroupsDirty(self, spec)
        RealisticMechanicalSystems.updateResalePrice(self)
    end
end

---Replaces the vanilla damage with the RMS condition
function RealisticMechanicalSystems.updateDamageAmount(wearable, superFunc, dt)
    local spec = wearable.spec_RealisticMechanicalSystems
    -- RMS wears the machine itself, the game damage stays at 0
    if spec ~= nil and not spec.isExcludedVehicle then
        return 0
    end
    return superFunc(wearable, dt)
end

---Flags the resale quote dirty when either payment changes
function RealisticMechanicalSystems.updateResalePrice(self)
    local spec = self.spec_RealisticMechanicalSystems
    if not canRaiseDirtyFlag(self, spec) or spec.isExcludedVehicle then
        return
    end

    local value = RMS_Utils.getMarketValue(self)
    local price = self:getPrice()
    local menuValue = math.min(math.floor(value), price)
    local dealerValue = math.min(math.floor(value * EconomyManager.DIRECT_SELL_MULTIPLIER), price)
    if spec._lastSyncResale_menu ~= menuValue or spec._lastSyncResale_dealer ~= dealerValue then
        spec._lastSyncResale_menu = menuValue
        spec._lastSyncResale_dealer = dealerValue
        RealisticMechanicalSystems.raiseRMSDirty(self, RealisticMechanicalSystems.SYNC_GROUP.RESALE)
    end
end

---Replaces the vanilla sell price by the RMS market value
function RealisticMechanicalSystems.getSellPrice(self, superFunc)
    if self.spec_RealisticMechanicalSystems ~= nil and not self.spec_RealisticMechanicalSystems.isExcludedVehicle then
        if not self.isServer and self.spec_RealisticMechanicalSystems.syncedSellPrice ~= nil then
            return self.spec_RealisticMechanicalSystems.syncedSellPrice
        end
        return RMS_Utils.getMarketValue(self)
    end
    return superFunc(self)
end

---Keeps the native engine state while RMS alone advances its temperature
function RealisticMechanicalSystems.updateMotorTemperature(self, superFunc, dt)
    local spec = self.spec_RealisticMechanicalSystems
    local isHeatedByRMS = spec ~= nil and not spec.isExcludedVehicle and not hasCVTAddon(self)
    if not isHeatedByRMS then
        return superFunc(self, dt)
    end
    RMS_Thermal.getEngineTemperature(self)
    RMS_Thermal.syncEngineProtection(self)
end

---Returns the level of the lowest service clock
function RealisticMechanicalSystems:getServiceLevel()
    local spec = self.spec_RealisticMechanicalSystems
    local serviceLevel = spec.baseServiceLevel
    for _, clock in ipairs(self:getServiceClocks()) do
        serviceLevel = math.min(serviceLevel, self:getServiceClockLevel(clock))
    end

    return serviceLevel
end

---Returns the overall condition level
function RealisticMechanicalSystems:getConditionLevel()
    return self.spec_RealisticMechanicalSystems.conditionLevel
end

---Returns the condition of one system
function RealisticMechanicalSystems:getSystemConditionLevel(systemName)
    local spec = self.spec_RealisticMechanicalSystems
    local systemKey = RMS_Utils.getSystemKey(RealisticMechanicalSystems.SYSTEMS, systemName)
    return spec.systems[systemKey].condition
end

---Raycast callback recording whether something was hit above the vehicle
function RealisticMechanicalSystems:isUnderRoofRaycastCallback()
    local spec = self.spec_RealisticMechanicalSystems
    if spec ~= nil then
        spec.roofRaycastHit = true
    end
end

---Tells whether the vehicle is indoors, or under a roof once parked
function RealisticMechanicalSystems:isUnderRoof()
    local spec = self.spec_RealisticMechanicalSystems
    local node = self.rootNode
    if (node == nil or node == 0) and self.components ~= nil and self.components[1] ~= nil then
        node = self.components[1].node
    end
    if node == nil or node == 0 then
        return false
    end

    local x, y, z = getWorldTranslation(node)
    local mission = g_currentMission
    local isIndoor = mission ~= nil and mission.indoorMask ~= nil and mission.indoorMask:getIsIndoorAtWorldPosition(x, z) == true

    -- On the move, the roof is looked for again once parked
    local mover = self.rootVehicle or self
    local speed = mover.getLastSpeed ~= nil and math.abs(tonumber(mover:getLastSpeed(true)) or 0) or 0
    if speed > (tonumber(RMS_Config.ROOF_STATIONARY_SPEED_LIMIT) or 0.5) then
        if spec ~= nil then
            spec.roofWasStationary, spec.roofLastRaycastTime, spec.roofRaycastResult = false, nil, nil
        end
        return isIndoor
    end
    if spec == nil then
        return isIndoor
    end

    local now = (mission ~= nil and mission.time) or g_time or 0
    local last = tonumber(spec.roofLastRaycastTime)
    local isDue = spec.roofWasStationary ~= true or last == nil or now < last
        or now - last >= (tonumber(RMS_Config.ROOF_RAYCAST_INTERVAL) or 5000)
    spec.roofWasStationary = true
    if isDue then
        spec.roofLastRaycastTime = now
        spec.roofRaycastHit = false
        local startY = y + (tonumber(RMS_Config.ROOF_RAYCAST_START_OFFSET) or 1)
        local distance = tonumber(RMS_Config.ROOF_RAYCAST_DISTANCE) or 40
        raycastClosest(x, startY, z, 0, 1, 0, distance, "isUnderRoofRaycastCallback", self, CollisionFlag.STATIC_OBJECT + CollisionFlag.BUILDING)
        spec.roofRaycastResult = spec.roofRaycastHit == true
    end
    if spec.roofRaycastResult ~= nil then
        return spec.roofRaycastResult == true
    end
    return isIndoor
end

---Tells whether a service is running on the vehicle
function RealisticMechanicalSystems:isUnderService()
    return self.spec_RealisticMechanicalSystems.currentState ~= RealisticMechanicalSystems.STATUS.READY
end

---Returns the current status of the vehicle
function RealisticMechanicalSystems:getCurrentStatus()
    return self.spec_RealisticMechanicalSystems.currentState
end

---Returns the active breakdowns of the vehicle
function RealisticMechanicalSystems:getActiveBreakdowns()
    return self.spec_RealisticMechanicalSystems.activeBreakdowns
end

---Returns the reliability multiplier of the brand of a vehicle
function RealisticMechanicalSystems.getBrandReliability(vehicle, storeItem)
    if vehicle ~= nil then
        local brand = g_brandManager:getBrandByIndex(vehicle:getBrand())
        local model = RMS_Config.BRANDS[vehicle:getName()]
        return model or (brand ~= nil and RMS_Config.BRANDS[brand.name]) or 1.0
    end
    if storeItem ~= nil then
        return RMS_Config.BRANDS[storeItem.name] or RMS_Config.BRANDS[storeItem.brandNameRaw] or 1.0
    end
    return 1.0
end

source(g_currentModDirectory .. "scripts/core/RMS_SpecSaveLoad.lua")
source(g_currentModDirectory .. "scripts/core/RMS_SpecStreams.lua")
source(g_currentModDirectory .. "scripts/core/RMS_SpecVehicleState.lua")
source(g_currentModDirectory .. "scripts/core/RMS_SpecWear.lua")
source(g_currentModDirectory .. "scripts/core/RMS_SpecBreakdowns.lua")
source(g_currentModDirectory .. "scripts/core/RMS_SpecService.lua")
source(g_currentModDirectory .. "scripts/core/RMS_SpecAiWorker.lua")
source(g_currentModDirectory .. "scripts/core/RMS_SpecConsole.lua")
