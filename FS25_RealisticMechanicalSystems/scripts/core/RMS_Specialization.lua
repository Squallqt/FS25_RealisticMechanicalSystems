-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

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

    -- the eight tracked vehicle systems
    SYSTEMS = {
        ENGINE = "rms_spec_system_engine",
        TRANSMISSION = "rms_spec_system_transmission",
        HYDRAULICS = "rms_spec_system_hydraulics",
        COOLING = "rms_spec_system_cooling",
        ELECTRICAL = "rms_spec_system_electrical",
        CHASSIS = "rms_spec_system_chassis",
        FUEL = "rms_spec_system_fuel",
        PTO = "rms_spec_system_pto"
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
    RealisticMechanicalSystems.SYSTEMS.PTO
}

RealisticMechanicalSystems.SERVICE_CLOCKS = {
    { key = "engine", levelKey = "serviceLevel", intervalFactor = 1, maintenanceType = "STANDARD", circuits = { "engineOil" }, systems = { "engine", "fuel" } },
    { key = "transmission", levelKey = "transmissionServiceLevel", intervalFactor = 2, maintenanceType = "EXTENDED", circuits = { "transmissionOil" }, systems = { "transmission", "pto" } },
    { key = "hydraulic", levelKey = "hydraulicServiceLevel", intervalFactor = 2, maintenanceType = "EXTENDED", circuits = { "hydraulicFluid" }, systems = { "hydraulics" } },
    { key = "coolant", levelKey = "coolantServiceLevel", intervalFactor = 4, maintenanceType = "PREVENTIVE", circuits = { "coolant" }, systems = { "cooling" } }
}

RealisticMechanicalSystems.MAJOR_SERVICE_CHECKS = { "INLET_VALVES", "EXHAUST_VALVES", "FUEL_INJECTOR_MALFUNCTION", "THERMOSTAT_MALFUNCTION" }

RealisticMechanicalSystems.PART_TYPES_ORDER = {
    RealisticMechanicalSystems.PART_TYPES.USED,
    RealisticMechanicalSystems.PART_TYPES.AFTERMARKET,
    RealisticMechanicalSystems.PART_TYPES.OEM
}

RealisticMechanicalSystems.modDirectory = g_currentModDirectory

---Tells whether a value is a number that is neither nan nor infinite
-- @param any value value to test
-- @return boolean isFinite true for a finite number
function RealisticMechanicalSystems.isFiniteNumber(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

-- @param table savegame savegame
-- @return string key savegame key
function RealisticMechanicalSystems.getSavegameKey(savegame)
    return savegame.key .. ".RealisticMechanicalSystems"
end

---Tells whether a vehicle is lent by a contract
-- @param table? vehicle vehicle
-- @return boolean isMissionVehicle true for a contract vehicle
function RealisticMechanicalSystems.isMissionVehicle(vehicle)
    return vehicle ~= nil and vehicle.propertyState == VehiclePropertyState.MISSION
end

-- @param any value value to convert
-- @param float fallback value used when the conversion fails
-- @param float? minValue lower bound
-- @param float? maxValue upper bound
-- @return float number sanitized number
function RealisticMechanicalSystems.sanitizeNumber(value, fallback, minValue, maxValue)
    local sanitized = tonumber(value)
    local safeFallback = tonumber(fallback)

    if not RealisticMechanicalSystems.isFiniteNumber(safeFallback) then
        safeFallback = 0
    end

    if not RealisticMechanicalSystems.isFiniteNumber(sanitized) then
        sanitized = safeFallback
    end

    if minValue ~= nil then
        local minNumber = tonumber(minValue)
        if RealisticMechanicalSystems.isFiniteNumber(minNumber) and sanitized < minNumber then
            sanitized = minNumber
        end
    end

    if maxValue ~= nil then
        local maxNumber = tonumber(maxValue)
        if RealisticMechanicalSystems.isFiniteNumber(maxNumber) and sanitized > maxNumber then
            sanitized = maxNumber
        end
    end

    return sanitized
end

source(g_currentModDirectory .. "scripts/core/RMS_Thermal.lua")
source(g_currentModDirectory .. "scripts/core/RMS_Electrical.lua")
source(g_currentModDirectory .. "scripts/core/RMS_Preheat.lua")
source(g_currentModDirectory .. "scripts/core/RMS_Exhaust.lua")
source(g_currentModDirectory .. "scripts/core/RMS_Breakdowns.lua")
source(g_currentModDirectory .. "scripts/core/RMS_Consumables.lua")
source(g_currentModDirectory .. "scripts/core/RMS_Drivetrain.lua")
source(g_currentModDirectory .. "scripts/core/RMS_Steering.lua")
source(g_currentModDirectory .. "scripts/core/RMS_ElectricDrive.lua")

RealisticMechanicalSystems.FACTOR_STATS_ALIASES = {
    expiredServiceFactor = "sf",
    -- engine
    motorLoadFactor = "mlf",
    airFilterCloggingFactor = "aicf",
    coldMotorFactor = "cmf",
    lowFluidFactor = "flf",
    hotMotorFactor = "hmf",
    -- transmission
    pullOverloadFactor = "pof",
    heavyTrailerFactor = "htf",
    luggingFactor = "lf",
    wheelSlipFactor = "wsf",
    drivetrainWindupFactor = "dwf",
    coldTransFactor = "ctf",
    hotTransFactor = "hotf",
    -- hydraulic
    heavyLiftFactor = "hlf",
    operatingFactor = "of",
    coldOilFactor = "cof",
    hotOilFactor = "hof",
    vibFactor = "vf",
    filterBypassFactor = "hfbf",
    transmissionFilterBypassFactor = "tfbf",
    -- cooling
    highCoolingFactor = "hcf",
    overheatFactor = "ohf",
    coldShockFactor = "csf",

    -- electrical
    weatherExposureFactor = "wef",
    lightsFactor = "ltf",
    crankingStressFactor = "crf",

    -- chassis
    steerLoadFactor = "slf",
    brakeMassFactor = "bmf",
    parkBrakeDragFactor = "pbf",
    terrainImpactFactor = "tif",

    --fuel
    lowFuelStarvationFactor = "lff",
    coldFuelFactor = "cff",
    idleDepositFactor = "idf",
    highPressureFactor = "hpf",
    -- traction battery
    deepDischargeFactor = "ddf",
    highDrawFactor = "hdf",
    batteryHeatFactor = "bhf",
    lubricationFactor = "lubf",
    instantDamageFactor = "idfg",
    ptoLoadFactor = "plf",
    ptoEngagementFactor = "pef",
    ptoRaisedFactor = "prf"
}

RealisticMechanicalSystems.FACTOR_STATS_KEYS = {}
for _, alias in pairs(RealisticMechanicalSystems.FACTOR_STATS_ALIASES) do
    RealisticMechanicalSystems.FACTOR_STATS_KEYS[alias] = true
end

local log_dbg = RMS_Utils.createLogger("[RMS_SPEC]")

---Returns the operating hours of a vehicle
local function getVehicleOperatingHours(vehicle)
    if vehicle == nil then
        return 0
    end

    if vehicle.getOperatingTime ~= nil then
        local operatingTime = tonumber(vehicle:getOperatingTime())
        if operatingTime ~= nil then
            return operatingTime / (60 * 60 * 1000)
        end
    end

    if vehicle.getFormattedOperatingTime ~= nil then
        return tonumber(vehicle:getFormattedOperatingTime()) or 0
    end

    return 0
end
RealisticMechanicalSystems.getVehicleOperatingHours = getVehicleOperatingHours

---Returns one normalized wear factor statistics entry
local function ensureFactorStatsEntry(spec, systemKey)
    if spec == nil or systemKey == nil then
        return nil
    end
    if type(spec.factorStats) ~= "table" then
        spec.factorStats = {}
    end

    if type(spec.factorStats[systemKey]) ~= "table" then
        spec.factorStats[systemKey] = {}
    end

    local stats = spec.factorStats[systemKey]
    stats.total = tonumber(stats.total) or 0
    stats._prevStress = tonumber(stats._prevStress) or 0
    stats._avgStress = tonumber(stats._avgStress) or 0
    stats.operatingHours = tonumber(stats.operatingHours)
    if stats.operatingHours == nil then
        stats.operatingHours = -1
    end

    return stats
end
RealisticMechanicalSystems.ensureFactorStatsEntry = ensureFactorStatsEntry

---Returns the wear factor statistics of the spec, missing entries created
local function ensureFactorStats(spec, vehicle)
    if spec == nil then
        return {}
    end

    if type(spec.factorStats) ~= "table" then
        spec.factorStats = {}
    end

    for systemKey, _ in pairs(spec.systems or {}) do
        ensureFactorStatsEntry(spec, systemKey)
    end

    return spec.factorStats
end
RealisticMechanicalSystems.ensureFactorStats = ensureFactorStats

---Returns the transmission name declared in the vehicle xml
local function getTransmissionNameFromXML(vehicle)
    if vehicle == nil then
        return nil
    end

    local motorConfigIndex = 1
    if vehicle.configurations ~= nil and vehicle.configurations.motor ~= nil then
        motorConfigIndex = math.max(tonumber(vehicle.configurations.motor) or 1, 1)
    end

    if vehicle.xmlFile ~= nil and vehicle.xmlFile.getValue ~= nil then
        local key = string.format("vehicle.motorized.motorConfigurations.motorConfiguration(%d).transmission", motorConfigIndex - 1)
        -- Motorized inherits transmission only if the selected block is absent.
        if not vehicle.xmlFile:hasProperty(key) then
            key = "vehicle.motorized.motorConfigurations.motorConfiguration(0).transmission"
        end
        local name = vehicle.xmlFile:getValue(key .. "#name", nil, vehicle.customEnvironment, false)
        if name ~= nil then
            return tostring(name)
        end
    end

    local storeItem = g_storeManager:getItemByXMLFilename(vehicle.configFileName)
    if storeItem ~= nil and storeItem.specs ~= nil and type(storeItem.specs.transmission) == "table" then
        return storeItem.specs.transmission[motorConfigIndex] or storeItem.specs.transmission[1]
    end

    return nil
end

---Classifies the transmission from its xml name and its gear configuration
local function getTransmissionType(vehicle)
    local transmissionTypes = RealisticMechanicalSystems.TRANSMISSION_TYPES
    if vehicle == nil or vehicle.getMotor == nil then
        return transmissionTypes.UNKNOWN
    end

    local motor = vehicle:getMotor()
    if motor == nil then
        return transmissionTypes.UNKNOWN
    end

    local transmissionName = getTransmissionNameFromXML(vehicle)
    if transmissionName ~= nil then
        local normalizedName = string.lower(tostring(transmissionName))
        if string.find(normalizedName, "manual", 1, true) ~= nil
            and (string.find(normalizedName, "powershift", 1, true) ~= nil
            or string.find(normalizedName, "power shift", 1, true) ~= nil) then
            return transmissionTypes.MANUAL_POWERSHIFT
        elseif string.find(normalizedName, "powershift", 1, true) ~= nil
            or string.find(normalizedName, "power shift", 1, true) ~= nil then
            return transmissionTypes.POWERSHIFT
        elseif string.find(normalizedName, "variable", 1, true) ~= nil
            or string.find(normalizedName, "cvt", 1, true) ~= nil then
            return transmissionTypes.VARIABLE
        elseif string.find(normalizedName, "automatic", 1, true) ~= nil
            or string.find(normalizedName, "auto", 1, true) ~= nil then
            return transmissionTypes.AUTOMATIC
        elseif string.find(normalizedName, "manual", 1, true) ~= nil then
            return transmissionTypes.MANUAL
        end
    end

    if motor.gearType == VehicleMotor.TRANSMISSION_TYPE.POWERSHIFT
        or motor.groupType == VehicleMotor.TRANSMISSION_TYPE.POWERSHIFT then
        if motor.forwardGears ~= nil or motor.backwardGears ~= nil then
            return transmissionTypes.MANUAL_POWERSHIFT
        end

        return transmissionTypes.POWERSHIFT
    end

    if motor.minForwardGearRatio ~= nil then
        return transmissionTypes.VARIABLE
    end

    if motor.forwardGears ~= nil or motor.backwardGears ~= nil then
        return transmissionTypes.MANUAL
    end

    return transmissionTypes.UNKNOWN
end

RealisticMechanicalSystems.getTransmissionType = getTransmissionType
RealisticMechanicalSystems.getTransmissionNameFromXML = getTransmissionNameFromXML

local hasCVTAddon = RMS_Utils.hasCVTAddon
local hasCVTTransmission = RMS_Utils.hasCVTTransmission

---Recomputes whether the vehicle is excluded
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
-- @param table vehicle vehicle
-- @param integer groupBits sync group bit mask
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
-- @param table vehicle vehicle
-- @param integer groupBits sync group bit mask
-- @param Connection connection connection
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
-- @param boolean isExcluded true to exclude the vehicle
-- @param boolean? noEventSend no event send
function RealisticMechanicalSystems:setRMSUserExcluded(isExcluded, noEventSend)
    local spec = self.spec_RealisticMechanicalSystems
    if spec == nil then
        return false, "unsupported"
    end

    local requestedValue = isExcluded == true
    if spec.isExcludedByUser == requestedValue then
        return false, "unchanged"
    end

    spec.isExcludedByUser = requestedValue
    refreshExclusionState(spec)

    if spec.isExcludedVehicle then
        if self.isClient then
            RMS_Exhaust.reset(self)
        end
        RMS_Drivetrain.releaseControl(self)
        spec.pendingSideNotifications = {}
    else
        spec.lubricationUsedThisPeriod = true
        RealisticMechanicalSystems.registerVehicle(self)
    end

    self:recalculateAndApplyEffects()
    RealisticMechanicalSystems.raiseRMSDirty(self, RealisticMechanicalSystems.SYNC_GROUP_ALL)

    if self.isServer and not noEventSend then
        RMS_VehicleExclusionEvent.sendToClients(self, spec.isExcludedByUser)
    end

    return true
end

---Returns the mission time scale, guarded against a missing or invalid value
local function getSafeMissionTimeScale()
    local timeScale = g_currentMission.missionInfo.timeScale or 1
    if timeScale <= 0 then
        timeScale = 1
    end
    return timeScale
end
RealisticMechanicalSystems.getSafeMissionTimeScale = getSafeMissionTimeScale

local SYSTEM_SYNC_EPSILON = 0.001
local OVERLOAD_AVERAGE_PERIOD_MS = 60000
local OVERLOAD_WINDOW_COMPACT_THRESHOLD = 256
local OVERLOAD_FACTOR_ALIASES_BY_SYSTEM = {
    engine = { "mlf", "hmf", "lf" },
    transmission = { "pof", "htf", "lf", "wsf", "hotf" }
}

---Clears the runtime-only rolling overload window
local function resetOverloadAverage(systemData)
    systemData._avgStress = 0
    systemData._avgStressWindow = nil
end

---Adds one sample to the rolling overload average
local function updateOverloadAverage(systemData, sampleDurationMs, sampleRatePerHour)
    local window = systemData._avgStressWindow
    if type(window) ~= "table" and sampleRatePerHour <= 0 then
        resetOverloadAverage(systemData)
        return 0
    end

    if type(window) ~= "table" then
        window = {
            samples = {},
            head = 1,
            tail = 0,
            totalDurationMs = 0,
            weightedSum = 0,
            positiveSampleCount = 0
        }
        systemData._avgStressWindow = window
    end

    local samples = window.samples
    local head = window.head
    local tail = window.tail
    local totalDurationMs = window.totalDurationMs
    local weightedSum = window.weightedSum
    local positiveSampleCount = window.positiveSampleCount

    if sampleRatePerHour > 0 or head <= tail then
        tail = tail + 1
        samples[tail] = {
            durationMs = sampleDurationMs,
            ratePerHour = sampleRatePerHour
        }
        totalDurationMs = totalDurationMs + sampleDurationMs
        weightedSum = weightedSum + sampleRatePerHour * sampleDurationMs
        if sampleRatePerHour > 0 then
            positiveSampleCount = positiveSampleCount + 1
        end
    end

    while head <= tail and totalDurationMs > OVERLOAD_AVERAGE_PERIOD_MS do
        local oldest = samples[head]
        local oldestDurationMs = math.max(tonumber(oldest.durationMs) or 0, 0)
        local oldestRatePerHour = tonumber(oldest.ratePerHour) or 0
        local overflowMs = totalDurationMs - OVERLOAD_AVERAGE_PERIOD_MS

        if oldestDurationMs <= overflowMs then
            totalDurationMs = totalDurationMs - oldestDurationMs
            weightedSum = weightedSum - oldestRatePerHour * oldestDurationMs
            samples[head] = nil
            head = head + 1
            if oldestRatePerHour > 0 then
                positiveSampleCount = positiveSampleCount - 1
            end
        else
            oldest.durationMs = oldestDurationMs - overflowMs
            totalDurationMs = totalDurationMs - overflowMs
            weightedSum = weightedSum - oldestRatePerHour * overflowMs
        end
    end

    if positiveSampleCount <= 0 or weightedSum <= 0 or totalDurationMs <= 0 then
        resetOverloadAverage(systemData)
        return 0
    end

    if head > OVERLOAD_WINDOW_COMPACT_THRESHOLD and head > tail / 2 then
        local compactedSamples = {}
        for index = head, tail do
            compactedSamples[#compactedSamples + 1] = samples[index]
        end
        samples = compactedSamples
        head = 1
        tail = #samples
    end

    window.samples = samples
    window.head = head
    window.tail = tail
    window.totalDurationMs = totalDurationMs
    window.weightedSum = weightedSum
    window.positiveSampleCount = positiveSampleCount

    local average = math.max(weightedSum / OVERLOAD_AVERAGE_PERIOD_MS, 0)
    systemData._avgStress = average
    return average
end

---Tells whether the vehicle may flag a sync group dirty right now
local function canRaiseDirtyFlag(vehicle, spec)
    return vehicle ~= nil and vehicle.isServer and spec ~= nil and spec.rmsDirtyFlag ~= nil
end

---Returns the operating time replicated to the clients
local function getSyncOperatingTime(vehicle)
    if vehicle == nil then
        return 0
    end

    if vehicle.getOperatingTime ~= nil then
        return tonumber(vehicle:getOperatingTime()) or 0
    end

    return tonumber(vehicle.operatingTime) or 0
end
RealisticMechanicalSystems.getSyncOperatingTime = getSyncOperatingTime

---Serializes the active breakdowns into the string the dirty check compares
local function serializeBreakdownsForDirtyCheck(breakdownsTable)
    if type(breakdownsTable) ~= "table" or next(breakdownsTable) == nil then
        return ""
    end

    local parts = {}

    for id, breakdown in pairs(breakdownsTable) do
        local stage = math.max(math.floor(tonumber(breakdown.stage) or 1), 1)
        local visible = breakdown.isVisible and 1 or 0
        local selected = breakdown.isSelectedForRepair and 1 or 0
        local active = breakdown.isActive ~= false and 1 or 0
        local source = math.max(math.floor(tonumber(breakdown.source) or 0), 0)

        table.insert(parts, string.format("%s,%d,%d,%d,%d,%d,%d", id, stage, visible, selected, active, source, breakdown.usedPartHours or 0))
    end

    table.sort(parts)

    return table.concat(parts, ";")
end

---Tells whether two floats differ by more than an epsilon
local function syncFloatChanged(a, b, epsilon)
    local valueA = RealisticMechanicalSystems.sanitizeNumber(a, 0)
    local valueB = RealisticMechanicalSystems.sanitizeNumber(b, 0)
    return math.abs(valueA - valueB) > (epsilon or 0)
end

---Flags the state group dirty when the status or the maintenance timer changed
local function markStateDirty(vehicle, spec)
    if not canRaiseDirtyFlag(vehicle, spec) then
        return false
    end

    if spec._lastSyncState_currentState ~= spec.currentState or
       spec._lastSyncState_plannedState ~= spec.plannedState or
       syncFloatChanged(spec._lastSyncState_maintenanceTimer, spec.maintenanceTimer, 1.0) then
            RealisticMechanicalSystems.raiseRMSDirty(vehicle, RealisticMechanicalSystems.SYNC_GROUP.STATE)
            spec._lastSyncState_currentState = spec.currentState
            spec._lastSyncState_plannedState = spec.plannedState
            spec._lastSyncState_maintenanceTimer = spec.maintenanceTimer
            return true
    end

    return false
end

---Flags the service context group dirty on a change
local function markServiceContextDirty(vehicle, spec)
    if not canRaiseDirtyFlag(vehicle, spec) then
        return false
    end

    if spec._lastSyncServiceContext_optionOne ~= spec.serviceOptionOne or
       spec._lastSyncServiceContext_optionTwo ~= spec.serviceOptionTwo or
       spec._lastSyncServiceContext_optionThree ~= spec.serviceOptionThree or
       spec._lastSyncServiceContext_workshopType ~= spec.workshopType then
            RealisticMechanicalSystems.raiseRMSDirty(vehicle, RealisticMechanicalSystems.SYNC_GROUP.SERVICE_CONTEXT)
            spec._lastSyncServiceContext_optionOne = spec.serviceOptionOne
            spec._lastSyncServiceContext_optionTwo = spec.serviceOptionTwo
            spec._lastSyncServiceContext_optionThree = spec.serviceOptionThree
            spec._lastSyncServiceContext_workshopType = spec.workshopType
            return true
    end

    return false
end

---Flags the telemetry group dirty on a change
local function markTelemetryDirty(vehicle, spec)
    if not canRaiseDirtyFlag(vehicle, spec) then
        return false
    end

    local operatingTime = getSyncOperatingTime(vehicle)
    local realOperatingTime = spec.realOperatingTime or 0
    local dynamicMotorLoad = tonumber(spec.dynamicMotorLoad) or 0
    local wheelSlip = tonumber(spec.wheelSlipIntensity) or 0

    if syncFloatChanged(spec._lastSyncTelemetry_operatingTime, operatingTime, 60000.0) or
       syncFloatChanged(spec._lastSyncTelemetry_realOperatingTime, realOperatingTime, 60000.0) or
       syncFloatChanged(spec._lastSyncTelemetry_fuelUsageRaw, spec._fuelUsageRaw, 0.3) or
       syncFloatChanged(spec._lastSyncTelemetry_dynamicMotorLoad, dynamicMotorLoad, 0.01) or
       syncFloatChanged(spec._lastSyncTelemetry_wheelSlip, wheelSlip, 0.01) or
       syncFloatChanged(spec._lastSyncTelemetry_liftedMass, spec.liftedMass, 10.0) then
            RealisticMechanicalSystems.raiseRMSDirty(vehicle, RealisticMechanicalSystems.SYNC_GROUP.TELEMETRY)
            spec._lastSyncTelemetry_operatingTime = operatingTime
            spec._lastSyncTelemetry_realOperatingTime = realOperatingTime
            spec._lastSyncTelemetry_fuelUsageRaw = spec._fuelUsageRaw
            spec._lastSyncTelemetry_dynamicMotorLoad = dynamicMotorLoad
            spec._lastSyncTelemetry_wheelSlip = wheelSlip
            spec._lastSyncTelemetry_liftedMass = spec.liftedMass
            return true
    end

    return false
end

local function markThermalDirty(vehicle, spec)
    if not canRaiseDirtyFlag(vehicle, spec) then
        return false
    end

    RMS_Thermal.getEngineTemperature(vehicle)
    local hasHydraulicTemperature = RMS_Thermal.getHasSeparateHydraulicCircuit(spec) and spec.rawHydraulicTemperature ~= nil
    local hasTractionBatteryTemperature = spec.isElectricVehicle == true and spec.tractionBatteryTempC ~= nil
    if spec._lastSyncThermal_hasHydraulicTemperature ~= hasHydraulicTemperature or
       spec._lastSyncThermal_hasTractionBatteryTemperature ~= hasTractionBatteryTemperature or
       syncFloatChanged(spec._lastSyncThermal_rawHydraulicTemperature, spec.rawHydraulicTemperature, 0.05) or
       syncFloatChanged(spec._lastSyncThermal_tractionBatteryTempC, spec.tractionBatteryTempC, 0.05) or
       syncFloatChanged(spec._lastSyncThermal_rawEngineTemperature, spec.rawEngineTemperature, 0.05) or
       syncFloatChanged(spec._lastSyncThermal_rawTransmissionTemperature, spec.rawTransmissionTemperature, 0.05) or
       syncFloatChanged(spec._lastSyncThermal_thermostatState, spec.thermostatState, 0.05) or
       syncFloatChanged(spec._lastSyncThermal_transmissionThermostatState, spec.transmissionThermostatState, 0.05) then
            RealisticMechanicalSystems.raiseRMSDirty(vehicle, RealisticMechanicalSystems.SYNC_GROUP.THERMAL)
            spec._lastSyncThermal_rawEngineTemperature = spec.rawEngineTemperature
            spec._lastSyncThermal_rawTransmissionTemperature = spec.rawTransmissionTemperature
            spec._lastSyncThermal_hasHydraulicTemperature = hasHydraulicTemperature
            spec._lastSyncThermal_hasTractionBatteryTemperature = hasTractionBatteryTemperature
            spec._lastSyncThermal_rawHydraulicTemperature = spec.rawHydraulicTemperature
            spec._lastSyncThermal_tractionBatteryTempC = spec.tractionBatteryTempC
            spec._lastSyncThermal_thermostatState = spec.thermostatState
            spec._lastSyncThermal_transmissionThermostatState = spec.transmissionThermostatState
            return true
    end

    return false
end

---Flags the electrical group dirty on a change
local function markElectricalDirty(vehicle, spec)
    if not canRaiseDirtyFlag(vehicle, spec) then
        return false
    end

    if syncFloatChanged(spec._lastSyncElectrical_batterySoc, spec.batterySoc, 0.01) or
       spec._lastSyncElectrical_batteryIsolated ~= spec.batteryIsolated or
       syncFloatChanged(spec._lastSyncElectrical_systemVoltage, spec.systemVoltageV, 0.01) or
       spec._lastSyncElectrical_preheatState ~= spec.preheatState or
       spec._lastSyncElectrical_preheatLampTestActive ~= spec.preheatLampTestActive or
       spec._lastSyncElectrical_preheatWasRequired ~= spec.preheatWasRequired or
       spec._lastSyncElectrical_preheatColdStartFaultSeverity ~= spec.preheatColdStartFaultSeverity then
            RealisticMechanicalSystems.raiseRMSDirty(vehicle, RealisticMechanicalSystems.SYNC_GROUP.ELECTRICAL)
            spec._lastSyncElectrical_batterySoc = spec.batterySoc
            spec._lastSyncElectrical_batteryIsolated = spec.batteryIsolated
            spec._lastSyncElectrical_systemVoltage = spec.systemVoltageV
            spec._lastSyncElectrical_preheatState = spec.preheatState
            spec._lastSyncElectrical_preheatLampTestActive = spec.preheatLampTestActive
            spec._lastSyncElectrical_preheatWasRequired = spec.preheatWasRequired
            spec._lastSyncElectrical_preheatColdStartFaultSeverity = spec.preheatColdStartFaultSeverity
            return true
    end

    return false
end

---Stores the field care values last compared by the network sync
function RealisticMechanicalSystems.storeFieldcareSyncState(vehicle, spec, serializedLeakDebt)
    spec._lastSyncFieldcare_radiatorClogging = spec.radiatorClogging
    spec._lastSyncFieldcare_airFilterClogging = spec.airFilterClogging
    spec._lastSyncFieldcare_airFilterResidue = spec.airFilterResidue
    for _, filter in ipairs(RMS_Consumables.FILTERS) do
        spec["_lastSyncFieldcare_" .. filter.stateKey] = spec[filter.stateKey]
    end
    spec._lastSyncFieldcare_lubricationLevel = spec.lubricationLevel
    spec._lastSyncFieldcare_engineOilLevel = spec.engineOilLevel
    spec._lastSyncFieldcare_coolantLevel = spec.coolantLevel
    spec._lastSyncFieldcare_transmissionOilLevel = spec.transmissionOilLevel
    spec._lastSyncFieldcare_hydraulicFluidLevel = spec.hydraulicFluidLevel
    for _, circuit in ipairs(RMS_Fluids.CIRCUIT_ORDER) do
        spec["_lastSyncFieldcare_capacity_" .. circuit] = RMS_Fluids.getCapacity(vehicle, circuit)
        spec["_lastSyncFieldcare_compatibility_" .. circuit] = RMS_Fluids.getCompatibility(vehicle, circuit)
    end
    spec._lastSyncFieldcare_leakDebt = serializedLeakDebt
    spec._lastSyncFieldcare_inspectionSoundActive = spec.fieldInspectionSoundActive
end

---Flags the field care group dirty when the clogging or the lubrication changed
local function markFieldcareDirty(vehicle, spec)
    if not canRaiseDirtyFlag(vehicle, spec) then
        return false
    end

    local fluidDataChanged = false
    for _, circuit in ipairs(RMS_Fluids.CIRCUIT_ORDER) do
        if syncFloatChanged(spec["_lastSyncFieldcare_capacity_" .. circuit], RMS_Fluids.getCapacity(vehicle, circuit), 0.001)
            or syncFloatChanged(spec["_lastSyncFieldcare_compatibility_" .. circuit], RMS_Fluids.getCompatibility(vehicle, circuit), 0.0001) then
            fluidDataChanged = true
            break
        end
    end
    local serializedLeakDebt = RMS_Fluids.serializeLeakDebt(spec.fluidLeakLossDebt)
    local filterChanged = false
    for _, filter in ipairs(RMS_Consumables.FILTERS) do
        filterChanged = filterChanged or syncFloatChanged(spec["_lastSyncFieldcare_" .. filter.stateKey], spec[filter.stateKey], 0.005)
    end

    if syncFloatChanged(spec._lastSyncFieldcare_radiatorClogging, spec.radiatorClogging, 0.005) or
       syncFloatChanged(spec._lastSyncFieldcare_airFilterClogging, spec.airFilterClogging, 0.005) or
       syncFloatChanged(spec._lastSyncFieldcare_airFilterResidue, spec.airFilterResidue, 0.005) or
       filterChanged or
       syncFloatChanged(spec._lastSyncFieldcare_lubricationLevel, spec.lubricationLevel, 0.005) or
       syncFloatChanged(spec._lastSyncFieldcare_engineOilLevel, spec.engineOilLevel, 0.005) or
       syncFloatChanged(spec._lastSyncFieldcare_coolantLevel, spec.coolantLevel, 0.005) or
       syncFloatChanged(spec._lastSyncFieldcare_transmissionOilLevel, spec.transmissionOilLevel, 0.005) or
       syncFloatChanged(spec._lastSyncFieldcare_hydraulicFluidLevel, spec.hydraulicFluidLevel, 0.005) or
       fluidDataChanged or
       spec._lastSyncFieldcare_leakDebt ~= serializedLeakDebt or
       spec._lastSyncFieldcare_inspectionSoundActive ~= spec.fieldInspectionSoundActive then
            RealisticMechanicalSystems.raiseRMSDirty(vehicle, RealisticMechanicalSystems.SYNC_GROUP.FIELDCARE)
            RealisticMechanicalSystems.storeFieldcareSyncState(vehicle, spec, serializedLeakDebt)
            return true
    end

    return false
end

---Tells whether a system condition moved past its sync threshold
local function getSystemsSyncChanged(spec)
    local lastSystems = spec._lastSyncWear_systems
    if lastSystems == nil then
        return true
    end

    local count = 0
    for sysKey, sysData in pairs(spec.systems) do
        count = count + 1

        local last = lastSystems[sysKey]
        if last == nil then
            return true
        end

        if syncFloatChanged(last.condition, sysData.condition, SYSTEM_SYNC_EPSILON) or
           last.enabled ~= (sysData.enabled ~= false) then
            return true
        end
    end

    return count ~= spec._lastSyncWear_systemsCount
end

---Snapshots the system conditions for the next dirty check
local function captureSystemsSync(spec)
    local snapshot = {}
    local count = 0

    for sysKey, sysData in pairs(spec.systems) do
        snapshot[sysKey] = {
            condition = sysData.condition,
            enabled = sysData.enabled ~= false
        }
        count = count + 1
    end

    spec._lastSyncWear_systems = snapshot
    spec._lastSyncWear_systemsCount = count
end
RealisticMechanicalSystems.captureSystemsSync = captureSystemsSync

---Flags the wear group dirty when the service, condition or a system changed
local function markWearDirty(vehicle, spec)
    if not canRaiseDirtyFlag(vehicle, spec) then
        return false
    end

    if syncFloatChanged(spec._lastSyncWear_serviceLevel, spec.serviceLevel, 0.001) or
       syncFloatChanged(spec._lastSyncWear_transmissionServiceLevel, spec.transmissionServiceLevel, 0.001) or
       syncFloatChanged(spec._lastSyncWear_coolantServiceLevel, spec.coolantServiceLevel, 0.001) or
       syncFloatChanged(spec._lastSyncWear_hydraulicServiceLevel, spec.hydraulicServiceLevel, 0.001) or
       spec._lastSyncWear_serviceCalendar ~= RMS_Utils.serializeNumericMap(spec.serviceCalendar) or
       spec._lastSyncWear_partWarranty ~= RMS_Utils.serializeNumericMap(spec.partWarranty) or
       spec._lastSyncWear_usedPartWarranty ~= RMS_Utils.serializeNumericMap(spec.usedPartWarranty) or
       spec._lastSyncWear_warrantyPlan ~= spec.warrantyPlan or
       syncFloatChanged(spec._lastSyncWear_conditionLevel, spec.conditionLevel, 0.001) or
       spec._lastSyncWear_ptoEngagementSequence ~= spec.ptoEngagementSequence or
       spec._lastSyncWear_ptoShockSequence ~= spec.ptoShockSequence or
       spec._lastSyncWear_ptoRaisedTooLong ~= spec.ptoRaisedTooLong or
       getSystemsSyncChanged(spec) then
            RealisticMechanicalSystems.raiseRMSDirty(vehicle, RealisticMechanicalSystems.SYNC_GROUP.WEAR)
            spec._lastSyncWear_serviceLevel = spec.serviceLevel
            spec._lastSyncWear_transmissionServiceLevel = spec.transmissionServiceLevel
            spec._lastSyncWear_coolantServiceLevel = spec.coolantServiceLevel
            spec._lastSyncWear_hydraulicServiceLevel = spec.hydraulicServiceLevel
            spec._lastSyncWear_serviceCalendar = RMS_Utils.serializeNumericMap(spec.serviceCalendar)
            spec._lastSyncWear_partWarranty = RMS_Utils.serializeNumericMap(spec.partWarranty)
            spec._lastSyncWear_usedPartWarranty = RMS_Utils.serializeNumericMap(spec.usedPartWarranty)
            spec._lastSyncWear_warrantyPlan = spec.warrantyPlan
            spec._lastSyncWear_conditionLevel = spec.conditionLevel
            spec._lastSyncWear_ptoEngagementSequence = spec.ptoEngagementSequence
            spec._lastSyncWear_ptoShockSequence = spec.ptoShockSequence
            spec._lastSyncWear_ptoRaisedTooLong = spec.ptoRaisedTooLong
            captureSystemsSync(spec)
            return true
    end

    return false
end

---Flags the breakdown group dirty when the serialized breakdowns changed
local function markBreakdownsDirty(vehicle, spec)
    if not canRaiseDirtyFlag(vehicle, spec) then
        return false
    end

    local serializedBreakdowns = serializeBreakdownsForDirtyCheck(spec.activeBreakdowns)
    if spec._lastSyncBreakdowns_serialized ~= serializedBreakdowns then
            RealisticMechanicalSystems.raiseRMSDirty(vehicle, RealisticMechanicalSystems.SYNC_GROUP.BREAKDOWNS)
            spec._lastSyncBreakdowns_serialized = serializedBreakdowns
            return true
    end

    return false
end

local function markServiceProgressDirty(vehicle, spec)
    if not canRaiseDirtyFlag(vehicle, spec) then
        return false
    end

    if syncFloatChanged(spec._lastSyncServiceProgress_elapsed, spec.pendingProgressElapsedTime,500.0) or
       spec._lastSyncServiceProgress_step ~= spec.pendingProgressStepIndex or
       syncFloatChanged(spec._lastSyncServiceProgress_total, spec.pendingProgressTotalTime, 500.0) then
            RealisticMechanicalSystems.raiseRMSDirty(vehicle, RealisticMechanicalSystems.SYNC_GROUP.SERVICE_PROGRESS)
            spec._lastSyncServiceProgress_elapsed = spec.pendingProgressElapsedTime
            spec._lastSyncServiceProgress_step = spec.pendingProgressStepIndex
            spec._lastSyncServiceProgress_total = spec.pendingProgressTotalTime
            return true
    end

    return false
end

---Returns the connection of the player driving the vehicle
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

---Flags the tutorial group dirty for the driving player on a change
local function markTutorialDataDirty(vehicle, spec)
    if not canRaiseDirtyFlag(vehicle, spec) then
        return false
    end

    local tutorialConnection = getTutorialSyncConnection(vehicle)
    if tutorialConnection == nil then
        spec._lastSyncTutorial_connection = nil
        return false
    end

    local fuelState = spec.fuelState
    local idleTimer  = tonumber(fuelState.idleTimer)  or 0
    local fuelLevel  = tonumber(fuelState.level)      or 0
    local luggingTimer    = tonumber(spec.luggingTutorialTimer)    or 0
    local wheelSlipTimer  = tonumber(spec.wheelSlipTutorialTimer)  or 0
    local brakeState  = spec.chassisBrakeState
    local hpTrailerMassRatio = tonumber(brakeState.hpTrailerMassRatio) or 1000
    local trailerMass = tonumber(brakeState.trailerMass) or 0
    local hpGrossMassRatio = tonumber(brakeState.hpGrossMassRatio) or 1000
    local isCranking  = spec.isCranking == true
    local steerState    = spec.chassisSteerState
    local groundContact = steerState.groundContact > 0
    local isMoving      = steerState.isMoving == true
    local vibrationTimer = spec.vibrationTutorialTimer
    local impactTimer    = spec.terrainImpactTutorialTimer
    local elecSys      = spec.systems ~= nil and spec.systems.electrical or nil
    local crankingTimer = elecSys ~= nil and (tonumber(elecSys.crankingTimer) or 0) or 0

    if spec._lastSyncTutorial_connection ~= tutorialConnection                          or
       syncFloatChanged(spec._lastSyncTutorial_idleTimer,       idleTimer,       1.0)   or
       syncFloatChanged(spec._lastSyncTutorial_fuelLevel,       fuelLevel,       0.01)  or
       syncFloatChanged(spec._lastSyncTutorial_luggingTimer,    luggingTimer,    100.0) or
       syncFloatChanged(spec._lastSyncTutorial_wheelSlipTimer,  wheelSlipTimer,  100.0) or
       syncFloatChanged(spec._lastSyncTutorial_hpTrailerMassRatio, hpTrailerMassRatio, 0.1) or
       syncFloatChanged(spec._lastSyncTutorial_trailerMass,     trailerMass,     0.01)  or
       syncFloatChanged(spec._lastSyncTutorial_hpGrossMassRatio, hpGrossMassRatio, 0.1) or
       spec._lastSyncTutorial_isCranking    ~= isCranking                              or
       spec._lastSyncTutorial_groundContact ~= groundContact                           or
       spec._lastSyncTutorial_isMoving      ~= isMoving                                or
       syncFloatChanged(spec._lastSyncTutorial_vibrationTimer,  vibrationTimer,  100.0) or
       syncFloatChanged(spec._lastSyncTutorial_impactTimer,     impactTimer,     100.0) or
       syncFloatChanged(spec._lastSyncTutorial_crankingTimer,   crankingTimer,   100.0) then
            RealisticMechanicalSystems.raiseRMSDirtyForConnection(vehicle, RealisticMechanicalSystems.SYNC_GROUP.TUTORIAL_DATA, tutorialConnection)
            spec._lastSyncTutorial_connection      = tutorialConnection
            spec._lastSyncTutorial_idleTimer       = idleTimer
            spec._lastSyncTutorial_fuelLevel       = fuelLevel
            spec._lastSyncTutorial_luggingTimer    = luggingTimer
            spec._lastSyncTutorial_wheelSlipTimer  = wheelSlipTimer
            spec._lastSyncTutorial_hpTrailerMassRatio = hpTrailerMassRatio
            spec._lastSyncTutorial_trailerMass     = trailerMass
            spec._lastSyncTutorial_hpGrossMassRatio = hpGrossMassRatio
            spec._lastSyncTutorial_isCranking      = isCranking
            spec._lastSyncTutorial_groundContact   = groundContact
            spec._lastSyncTutorial_isMoving        = isMoving
            spec._lastSyncTutorial_vibrationTimer  = vibrationTimer
            spec._lastSyncTutorial_impactTimer     = impactTimer
            spec._lastSyncTutorial_crankingTimer   = crankingTimer
            return true
    end

    return false
end

---Flags every group a finished or cancelled service touches
-- @param table vehicle vehicle
function RealisticMechanicalSystems.raiseServiceLifecycleDirtyFlags(vehicle)
    if vehicle == nil or vehicle.spec_RealisticMechanicalSystems == nil then
        return false
    end

    local spec = vehicle.spec_RealisticMechanicalSystems
    local raised = false

    if markStateDirty(vehicle, spec) then
        raised = true
    end
    if markServiceContextDirty(vehicle, spec) then
        raised = true
    end
    if markWearDirty(vehicle, spec) then
        raised = true
    end
    if markBreakdownsDirty(vehicle, spec) then
        raised = true
    end
    if markServiceProgressDirty(vehicle, spec) then
        raised = true
    end

    return raised
end

---Finishes the running service at once
-- @param table vehicle vehicle
-- @return boolean finished true when a service was running
function RealisticMechanicalSystems.forceFinishService(vehicle)
    if vehicle == nil or vehicle.spec_RealisticMechanicalSystems == nil or not vehicle.isServer then
        return false
    end

    local spec = vehicle.spec_RealisticMechanicalSystems
    if spec.currentState == RealisticMechanicalSystems.STATUS.READY then
        return false
    end

    local remainingMs = math.max(spec.maintenanceTimer or 0, 0)
    local missionInfo = g_currentMission and g_currentMission.missionInfo or nil
    local timeScale = (missionInfo and missionInfo.timeScale) or 1
    if timeScale <= 0 then
        timeScale = 1
    end

    local forceDt = math.max(math.ceil(remainingMs / timeScale) + 1, 1)

    vehicle:processService(forceDt, true)

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
    local schemaSavegame = Vehicle.xmlSchemaSavegame

    schema:setXMLSpecializationType("RealisticMechanicalSystems")

    local baseKey = "vehicles.vehicle(?).RealisticMechanicalSystems"
    schemaSavegame:register(XMLValueType.BOOL,   baseKey .. "#userExclusion", "User decision overriding the automatic exclusion, absent when the user has no opinion")
    schemaSavegame:register(XMLValueType.FLOAT,  baseKey .. "#service", "Service Level")
    schemaSavegame:register(XMLValueType.FLOAT,  baseKey .. "#transmissionService", "Transmission and hydraulic oil service level")
    schemaSavegame:register(XMLValueType.FLOAT,  baseKey .. "#coolantService", "Coolant service level")
    schemaSavegame:register(XMLValueType.FLOAT,  baseKey .. "#hydraulicService", "Separate hydraulic oil service level")
    schemaSavegame:register(XMLValueType.STRING, baseKey .. "#serviceCalendar", "Calendar start ages by service circuit")
    schemaSavegame:register(XMLValueType.INT, baseKey .. "#warrantyPlan", "Factory warranty plan")
    schemaSavegame:register(XMLValueType.STRING, baseKey .. "#partWarranty", "Dealer part warranty expiry ages")
    schemaSavegame:register(XMLValueType.STRING, baseKey .. "#usedPartWarranty", "Used part warranty expiry ages")
    schemaSavegame:register(XMLValueType.FLOAT,  baseKey .. "#condition", "Condition Level")
    schemaSavegame:register(XMLValueType.STRING, baseKey .. "#breakdowns", "Active Breakdowns")
    schemaSavegame:register(XMLValueType.STRING, baseKey .. "#state", "Current State")
    schemaSavegame:register(XMLValueType.STRING, baseKey .. "#plannedState", "Planned State")
    schemaSavegame:register(XMLValueType.FLOAT,  baseKey .. "#maintenanceTimer", "Maintenance Timer")
    schemaSavegame:register(XMLValueType.FLOAT,  baseKey .. "#realOperatingTime", "Real Operating Time")
    schemaSavegame:register(XMLValueType.FLOAT,  baseKey .. "#engineTemperature", "Engine Temperature")
    schemaSavegame:register(XMLValueType.FLOAT,  baseKey .. "#transmissionTemperature", "Transmission Temperature")
    schemaSavegame:register(XMLValueType.FLOAT,  baseKey .. "#hydraulicTemperature", "Optional Separate Hydraulic Temperature")
    schemaSavegame:register(XMLValueType.FLOAT,  baseKey .. "#thermalWorldTime", "Optional Thermal World Time Metadata")
    schemaSavegame:register(XMLValueType.FLOAT,  baseKey .. "#thermalAmbient", "Optional Thermal Ambient Metadata")
    schemaSavegame:register(XMLValueType.FLOAT,  baseKey .. "#batterySoc", "Battery State Of Charge")
    schemaSavegame:register(XMLValueType.BOOL,   baseKey .. "#batteryIsolated", "Battery isolator open", false)
    schemaSavegame:register(XMLValueType.FLOAT,  baseKey .. "#tractionBatteryTempC", "Traction battery temperature of an electric vehicle")
    schemaSavegame:register(XMLValueType.FLOAT,  baseKey .. "#radiatorClogging", "Radiator clogging level")
    schemaSavegame:register(XMLValueType.FLOAT,  baseKey .. "#airFilterClogging", "Air filter clogging level")
    schemaSavegame:register(XMLValueType.FLOAT,  baseKey .. "#airFilterResidue", "Air filter clogging a blow out cannot remove")
    for _, filter in ipairs(RMS_Consumables.FILTERS) do
        schemaSavegame:register(XMLValueType.FLOAT,  baseKey .. "#" .. filter.stateKey, "Filter clogging, 1 when its change falls due")
    end
    schemaSavegame:register(XMLValueType.FLOAT,  baseKey .. "#engineOilLevel", "Engine oil level")
    schemaSavegame:register(XMLValueType.FLOAT,  baseKey .. "#coolantLevel", "Coolant level")
    schemaSavegame:register(XMLValueType.FLOAT,  baseKey .. "#transmissionOilLevel", "Transmission oil level")
    schemaSavegame:register(XMLValueType.FLOAT,  baseKey .. "#hydraulicFluidLevel", "Hydraulic fluid level")
    schemaSavegame:register(XMLValueType.INT,    baseKey .. "#fluidCapacityVersion", "Fluid capacity model version")
    schemaSavegame:register(XMLValueType.STRING, baseKey .. "#fluidCapacitySource", "Resolved fluid capacity source")
    schemaSavegame:register(XMLValueType.FLOAT,  baseKey .. "#engineOilCapacity", "Engine oil capacity in liters")
    schemaSavegame:register(XMLValueType.FLOAT,  baseKey .. "#coolantCapacity", "Coolant capacity in liters")
    schemaSavegame:register(XMLValueType.FLOAT,  baseKey .. "#transmissionOilCapacity", "Transmission oil capacity in liters")
    schemaSavegame:register(XMLValueType.FLOAT,  baseKey .. "#hydraulicFluidCapacity", "Hydraulic fluid capacity in liters")
    schemaSavegame:register(XMLValueType.FLOAT,  baseKey .. "#engineOilCompatibility", "Engine oil mixture compatibility")
    schemaSavegame:register(XMLValueType.FLOAT,  baseKey .. "#coolantCompatibility", "Coolant mixture compatibility")
    schemaSavegame:register(XMLValueType.FLOAT,  baseKey .. "#transmissionOilCompatibility", "Transmission oil mixture compatibility")
    schemaSavegame:register(XMLValueType.FLOAT,  baseKey .. "#hydraulicFluidCompatibility", "Hydraulic fluid mixture compatibility")
    schemaSavegame:register(XMLValueType.STRING, baseKey .. "#fluidLeakLossDebt", "Unreplenished fluid loss by leak")
    schemaSavegame:register(XMLValueType.STRING, baseKey .. "#pendingFluidRequirements", "Physical fluid reserved for the running service")
    schemaSavegame:register(XMLValueType.FLOAT,  baseKey .. "#wetStackingLevel", "Wet stacking deposit level")
    schemaSavegame:register(XMLValueType.FLOAT,  baseKey .. "#particulateFilterLevel", "Particulate filter soot level, 1 calling a regeneration")
    schemaSavegame:register(XMLValueType.FLOAT,  baseKey .. "#scrInducementHours", "Engine hours since an AdBlue fault was confirmed")
    schemaSavegame:register(XMLValueType.BOOL,   baseKey .. "#particulateFilterOverloaded", "Whether the particulate filter overload is shown as a breakdown")
    schemaSavegame:register(XMLValueType.FLOAT,  baseKey .. "#lubricationLevel", "Lubrication level")
    schemaSavegame:register(XMLValueType.BOOL,   baseKey .. "#lubricationUsedThisPeriod", "Whether the vehicle was used during the current period")
    schemaSavegame:register(XMLValueType.FLOAT,  baseKey .. "#thermostatState", "Engine Thermostat Position")
    schemaSavegame:register(XMLValueType.FLOAT,  baseKey .. "#transmissionThermostatState", "Transmission Thermostat Position")
    schemaSavegame:register(XMLValueType.STRING, baseKey .. "#serviceOptionOne", "Current Service Option One")
    schemaSavegame:register(XMLValueType.STRING, baseKey .. "#serviceOptionTwo", "Current Service Option Two")
    schemaSavegame:register(XMLValueType.BOOL,   baseKey .. "#serviceOptionThree", "Current Service Option Three")
    schemaSavegame:register(XMLValueType.STRING, baseKey .. "#workshopType", "Workshop Type")
    schemaSavegame:register(XMLValueType.STRING, baseKey .. "#pendingSelectedBreakdowns", "Pending Selected Breakdowns")
    schemaSavegame:register(XMLValueType.FLOAT,  baseKey .. "#pendingServicePrice", "Pending Service Price")
    schemaSavegame:register(XMLValueType.STRING, baseKey .. "#pendingServiceInvoice", "Pending Service Invoice")
    schemaSavegame:register(XMLValueType.STRING, baseKey .. "#pendingInspectionQueue", "Pending Inspection Queue")
    schemaSavegame:register(XMLValueType.STRING, baseKey .. "#pendingRepairQueue", "Pending Repair Queue")
    schemaSavegame:register(XMLValueType.INT,    baseKey .. "#pendingProgressStepIndex", "Pending Progress Step Index")
    schemaSavegame:register(XMLValueType.FLOAT,  baseKey .. "#pendingProgressTotalTime", "Pending Progress Total Time")
    schemaSavegame:register(XMLValueType.FLOAT,  baseKey .. "#pendingProgressElapsedTime", "Pending Progress Elapsed Time")
    schemaSavegame:register(XMLValueType.STRING, baseKey .. "#pendingServiceClockStart", "Service clock levels at the start of the running service")
    schemaSavegame:register(XMLValueType.STRING, baseKey .. "#pendingServiceClockTarget", "Service clock levels the running service restores")
    schemaSavegame:register(XMLValueType.STRING, baseKey .. "#systemsState", "Systems state snapshot")
    schemaSavegame:register(XMLValueType.STRING, baseKey .. "#partWear", "Wear of each part")
    schemaSavegame:register(XMLValueType.STRING, baseKey .. "#factorStats", "Per-system accumulated factor stats")
    schemaSavegame:register(XMLValueType.STRING, baseKey .. "#pendingOverhaulPartStart", "Wear of each part at the start of the running overhaul")
    schemaSavegame:register(XMLValueType.STRING, baseKey .. "#pendingOverhaulPartTarget", "Wear the running overhaul brings each part to")
    schemaSavegame:register(XMLValueType.INT,    baseKey .. "#driveMode", "Drivetrain mode (0=4x2, 1=4WD, 2=AUTO)")
    schemaSavegame:register(XMLValueType.BOOL,   baseKey .. "#diffLockRequested", "Differential lock requested")
    schemaSavegame:register(XMLValueType.FLOAT,  baseKey .. "#tripStartKilometers", "Odometer reading at the last trip meter reset (km)")
    schemaSavegame:register(XMLValueType.INT,    baseKey .. "#ptoEngagementCount", "PTO engagement count")
    schemaSavegame:register(XMLValueType.INT,    baseKey .. "#ptoEngagementSequence", "PTO engagement cycle sequence")

    local logKey = baseKey .. ".maintenanceLog.entry(?)"
    schemaSavegame:register(XMLValueType.INT,    logKey .. "#id", "Entry ID")
    schemaSavegame:register(XMLValueType.STRING, logKey .. "#type", "Maintenance Type")
    schemaSavegame:register(XMLValueType.FLOAT,  logKey .. "#price", "Price")
    schemaSavegame:register(XMLValueType.STRING, logKey .. "#date", "Date")

    schemaSavegame:register(XMLValueType.STRING, logKey .. "#location", "Workshop Location")
    schemaSavegame:register(XMLValueType.STRING, logKey .. "#optionOne", "Option One")
    schemaSavegame:register(XMLValueType.STRING, logKey .. "#optionTwo", "Option Two")
    schemaSavegame:register(XMLValueType.BOOL,   logKey .. "#optionThree", "Option Three")
    schemaSavegame:register(XMLValueType.STRING, logKey .. "#isVisible", "is Visible in Log")
    schemaSavegame:register(XMLValueType.BOOL,   logKey .. "#isCompleted", "Is Completed")
    schemaSavegame:register(XMLValueType.STRING, logKey .. "#invoice", "Invoice Lines")
    local condKey = logKey .. ".conditionData"
    schemaSavegame:register(XMLValueType.INT,    condKey .. "#year", "Vehicle Year")
    schemaSavegame:register(XMLValueType.FLOAT,  condKey .. "#operatingHours", "Operating Hours")
    schemaSavegame:register(XMLValueType.FLOAT,  condKey .. "#odometerKilometers", "Odometer Reading (km)")
    schemaSavegame:register(XMLValueType.FLOAT,  condKey .. "#age", "Vehicle Age")
    schemaSavegame:register(XMLValueType.FLOAT,  condKey .. "#condition", "Condition Level")
    schemaSavegame:register(XMLValueType.FLOAT,  condKey .. "#service", "Service Level")
    schemaSavegame:register(XMLValueType.STRING, condKey .. "#activeBreakdowns", "Active Breakdowns")
    schemaSavegame:register(XMLValueType.STRING, condKey .. "#selectedBreakdowns", "Selected Breakdowns")
    schemaSavegame:register(XMLValueType.STRING, condKey .. "#activeEffects", "Active Effects")
    schemaSavegame:register(XMLValueType.STRING, condKey .. "#activeIndicators", "Active Indicators")
    schemaSavegame:register(XMLValueType.FLOAT,  condKey .. "#reliability", "Reliability")
    schemaSavegame:register(XMLValueType.STRING, condKey .. "#systems", "Per-system snapshot")
    schemaSavegame:register(XMLValueType.STRING, condKey .. "#partWear", "Wear of each part")
    schemaSavegame:register(XMLValueType.FLOAT,  condKey .. "#batterySoc", "Battery State Of Charge")
    schemaSavegame:register(XMLValueType.FLOAT,  condKey .. "#wearExcess", "Wear over the normal wear")
    schemaSavegame:register(XMLValueType.STRING, condKey .. "#wearCauses", "Share of each cause of wear")

    schema:setXMLSpecializationType()

    RMS_Thermal.registerReversibleFan()
    RealisticMechanicalSystems.registerWarrantyConfiguration()
end

---
-- @param table vehicleType vehicle type
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

---
-- @param table vehicleType vehicle type
function RealisticMechanicalSystems.registerOverwrittenFunctions(vehicleType)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "getIsTabbable", RealisticMechanicalSystems.getIsTabbable)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "repaintVehicle", RMS_Bodywork.repaintVehicle)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "getCanMotorRun", RMS_Breakdowns.getCanMotorRun)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "getMotorNotAllowedWarning", RMS_Breakdowns.getMotorNotAllowedWarning)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "getCanStartAIVehicle", RMS_Breakdowns.getCanStartAIVehicle)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "startMotor", RMS_Breakdowns.startMotor)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "updateDamageAmount", RealisticMechanicalSystems.updateDamageAmount)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "setLightsTypesMask", RMS_Breakdowns.setLightsTypesMask)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "setBeaconLightsVisibility", RMS_Breakdowns.setBeaconLightsVisibility)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "setTurnLightState", RMS_Breakdowns.setTurnLightState)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "getSpeedLimit", RMS_Breakdowns.getSpeedLimitOverwrite)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "getCruiseControlSpeed", RealisticMechanicalSystems.getCruiseControlSpeed)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "updateVehiclePhysics", RMS_Breakdowns.updateVehiclePhysics)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "updateVehiclePhysics", RMS_Drivetrain.updateVehiclePhysics)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "updateConsumers", RMS_Breakdowns.updateConsumersOverwrite)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "getSellPrice", RealisticMechanicalSystems.getSellPrice)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "updateMotorTemperature", RealisticMechanicalSystems.updateMotorTemperature)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "addToPhysics", RMS_Drivetrain.addToPhysics)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "brake", RMS_Drivetrain.brake)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "updateSteeringAngle", RMS_Steering.updateSteeringAngle)
    SpecializationUtil.registerOverwrittenFunction(vehicleType, "updateArticulatedAxisRotation", RMS_Steering.updateArticulatedAxisRotation)
end

---
-- @param table vehicleType vehicle type
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
    SpecializationUtil.registerFunction(vehicleType, "updateCoolingSystem", RealisticMechanicalSystems.updateCoolingSystem)
    SpecializationUtil.registerFunction(vehicleType, "updateElectricalSystem", RealisticMechanicalSystems.updateElectricalSystem)
    SpecializationUtil.registerFunction(vehicleType, "updateChassisSystem", RealisticMechanicalSystems.updateChassisSystem)
    SpecializationUtil.registerFunction(vehicleType, "updateFuelSystem", RealisticMechanicalSystems.updateFuelSystem)
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
    SpecializationUtil.registerFunction(vehicleType, "updateLubricationLevel", RMS_Consumables.updateLubricationLevel)
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
    SpecializationUtil.registerFunction(vehicleType, "lubricateVehicle", RMS_Consumables.lubricateVehicle)
    SpecializationUtil.registerFunction(vehicleType, "startFieldVisualInspectionProcess", RMS_Consumables.startFieldVisualInspectionProcess)
    SpecializationUtil.registerFunction(vehicleType, "setFieldInspectionPlayerActive", RMS_Consumables.setFieldInspectionPlayerActive)
    SpecializationUtil.registerFunction(vehicleType, "updateFieldInspectionSound", RMS_Consumables.updateFieldInspectionSound)

    SpecializationUtil.registerFunction(vehicleType, "updateAiWorkerSpeed", RealisticMechanicalSystems.updateAiWorkerSpeed)
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
    SpecializationUtil.registerFunction(vehicleType, "getOverhaulPerformedCount", RealisticMechanicalSystems.getOverhaulPerformedCount)
    
end

---
-- @param boolean wasEntered true if the vehicle was entered
function RealisticMechanicalSystems:onLeaveVehicle(wasEntered)
    local spec = self.spec_RealisticMechanicalSystems
    if spec == nil then
        return
    end

    spec.lastBlinkingWarningMessage = ""
    spec.blinkingWarningTimer = 0

    local hadStartInput = spec.startButtonDown or spec.startButtonHeld or spec.startButtonUp
    spec.startButtonDown = false
    spec.startButtonHeld = false
    spec.startButtonUp = false

    if hadStartInput then
        RMS_StartButtonEvent.send(self, false, false, false)
    end

    if self.isServer
        and not self:getIsMotorStarted()
        and spec.preheatState ~= RMS_Preheat.STATE.IDLE then
        RMS_Breakdowns.cancelStarterCranking(self)
        RMS_Preheat.reset(self, false)
        if self:getMotorState() ~= MotorState.OFF then
            self:setMotorState(MotorState.OFF)
        end
        RealisticMechanicalSystems.raiseRMSDirty(self, RealisticMechanicalSystems.SYNC_GROUP.ELECTRICAL)
    end

    RMS_Drivetrain.onDriverLeft(self, wasEntered)
end

---Frees the implements of a machine left without its park brake
function RealisticMechanicalSystems:onDeactivate()
    RMS_Drivetrain.restoreFreeRolling(self)
end

---Enables the start button action only while it can actually be used
-- @param table self vehicle
function RealisticMechanicalSystems.updateStartButtonActionEvents(self)
    if not self.isClient or not self:getIsActiveForInput(true) then
        return
    end

    local spec = self.spec_RealisticMechanicalSystems
    local motorizedSpec = self.spec_motorized
    if spec == nil or motorizedSpec == nil or spec.startButtonActionEvents == nil then
        return
    end

    local automaticMotorStartEnabled = g_currentMission.missionInfo.automaticMotorStartEnabled == true

    for inputAction, actionEvent in pairs(spec.startButtonActionEvents) do
        local actionEventId = actionEvent.actionEventId
        local registeredEvent = actionEventId ~= nil
            and g_inputBinding.events ~= nil
            and g_inputBinding.events[actionEventId]
            or nil

        if registeredEvent ~= nil then
            g_inputBinding:setActionEventActive(actionEventId, true)

            if inputAction == InputAction.TOGGLE_MOTOR_STATE then
                g_inputBinding:setActionEventTextVisibility(actionEventId, not automaticMotorStartEnabled)

                local motorState = self:getMotorState()
                if motorState == MotorState.STARTING or motorState == MotorState.ON or RMS_Preheat.isFailed(self) then
                    g_inputBinding:setActionEventTextPriority(actionEventId, GS_PRIO_VERY_LOW)
                    g_inputBinding:setActionEventText(actionEventId, motorizedSpec.turnOffText)
                else
                    g_inputBinding:setActionEventTextPriority(actionEventId, GS_PRIO_VERY_HIGH)
                    g_inputBinding:setActionEventText(actionEventId, motorizedSpec.turnOnText)
                end
            else
                g_inputBinding:setActionEventTextVisibility(actionEventId, false)
            end
        end
    end
end

---Registers the specialization action events
-- @param boolean isActiveForInput true if vehicle is active for input
-- @param boolean isActiveForInputIgnoreSelection active regardless of selection
function RealisticMechanicalSystems:onRegisterActionEvents(isActiveForInput, isActiveForInputIgnoreSelection)
    if not self.isClient then
        return
    end

    local spec = self.spec_RealisticMechanicalSystems
    local motorizedSpec = self.spec_motorized
    if spec == nil or motorizedSpec == nil then
        return
    end

    self:clearActionEventsTable(spec.startButtonActionEvents)
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

    local startInputActions = {
        InputAction.TOGGLE_MOTOR_STATE,
        InputAction.MOTOR_STATE_ON or "MOTOR_STATE_ON"
    }

    for _, inputAction in ipairs(startInputActions) do
        local motorizedActionEvent = motorizedSpec.actionEvents[inputAction]
        if motorizedActionEvent ~= nil and motorizedActionEvent.actionEventId ~= nil then
            g_inputBinding:removeActionEvent(motorizedActionEvent.actionEventId)
        end
        motorizedSpec.actionEvents[inputAction] = nil

        -- Share one action event with native held-state tracking.
        local _, actionEventId = self:addActionEvent(
            spec.startButtonActionEvents,
            inputAction,
            self,
            RMS_Breakdowns.onStartButtonAction,
            true,
            true,
            false,
            true,
            nil,
            nil,
            true
        )

        if actionEventId ~= nil then
            g_inputBinding:setActionEventTextVisibility(actionEventId, false)
            g_inputBinding:setActionEventTextPriority(actionEventId, GS_PRIO_VERY_LOW)
        end
    end

    RealisticMechanicalSystems.updateStartButtonActionEvents(self)
end

function RealisticMechanicalSystems:onReverseFanAction()
    RMS_SoundManager.playSample(self.spec_RealisticMechanicalSystems.samples.fanReversalSwitch)
    RMS_FanReversalEvent.send(self)
end

---Odometer key: a press switches odometer and trip, a hold resets the trip
-- @param string actionName input action name
-- @param float inputValue input value, zero on release
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
-- @param table vehicle vehicle
-- @param boolean? noEventSend no event send
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

---Draws the wear a part lasts, by the Weibull law of its kind
local function drawPartLife(partId)
    local C = RMS_Config.CORE
    local life = C.COMPONENT_LIVES[RMS_Breakdowns.BreakdownRegistry[partId].component]
    return life.scale / C.MACHINE_LIFE_HOURS * (-math.log(1 - math.random())) ^ (1 / life.shape)
end

---Returns the wear of a lit part without record
-- @param table vehicle vehicle
-- @param string partId breakdown id of the part
-- @return float wear wear of the part
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

-- @param table vehicle vehicle
-- @param string care careful, regular or neglected
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

-- @param table vehicle vehicle
-- @param float hours operating hours
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

-- @param table vehicle vehicle
-- @param float hours operating hours
-- @return float price catch-up price
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

---Registers a vehicle with the mod, classifying it and creating its spec fields
local function registerVehicle(vehicle)
    if RMS_Main and RMS_Main.vehicles and RMS_Main.vehicles[vehicle.uniqueId] == nil then
        local ownerFarmId = vehicle.getOwnerFarmId ~= nil and vehicle:getOwnerFarmId() or vehicle.ownerFarmId
        local hasSupportedPropertyState = vehicle.propertyState == VehiclePropertyState.OWNED
            or vehicle.propertyState == VehiclePropertyState.LEASED
            or vehicle.propertyState == VehiclePropertyState.MISSION
        local hasValidOwnerFarm = ownerFarmId ~= nil
            and ownerFarmId ~= FarmManager.SPECTATOR_FARM_ID
            and g_farmManager:getFarmById(ownerFarmId) ~= nil

        if hasSupportedPropertyState and hasValidOwnerFarm then

            local spec = vehicle.spec_RealisticMechanicalSystems
            if spec == nil then return end

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
                local inapplicableIds = {}
                for breakdownId in pairs(spec.activeBreakdowns) do
                    local definition = RMS_Breakdowns.BreakdownRegistry[breakdownId]
                    if definition == nil or not definition.isApplicable(vehicle) then
                        table.insert(inapplicableIds, breakdownId)
                    end
                end
                if #inapplicableIds > 0 then
                    vehicle:removeBreakdown(unpack(inapplicableIds))
                end
            end

            if vehicle.isServer and spec.isNewToRMS then
                    spec.isNewToRMS = false
                    local isUsedVehicle = vehicle:getFormattedOperatingTime() > 0.01
                    if isUsedVehicle and not spec.isExcludedVehicle then
                        local isMission = RealisticMechanicalSystems.isMissionVehicle(vehicle)
                        local care = isMission and "careful" or RMS_Utils.getOwnerCare(vehicle:getDamageAmount())
                        RealisticMechanicalSystems.initializeUsedVehicle(vehicle, care, not isMission)
                    end

                    local needsInitialReport = not isUsedVehicle or RealisticMechanicalSystems.isMissionVehicle(vehicle)
                    if needsInitialReport and (spec.maintenanceLog == nil or #spec.maintenanceLog == 0) then
                        local inspectionType = RealisticMechanicalSystems.isMissionVehicle(vehicle) and RealisticMechanicalSystems.INSPECTION_TYPES.STANDARD
                            or RealisticMechanicalSystems.INSPECTION_TYPES.COMPLETE
                        vehicle:addEntryToMaintenanceLog(RealisticMechanicalSystems.STATUS.INSPECTION, inspectionType, "NONE", false, 0)
                    end
            end

            if vehicle.isServer then
                RMS_Drivetrain.resolveParkBrakeKind(vehicle)
            end

            local factorStats = ensureFactorStats(spec, vehicle)
            local currentOperatingHours = getVehicleOperatingHours(vehicle)
            for _, systemStats in pairs(factorStats) do
                if type(systemStats) == "table" then
                    local operatingHours = tonumber(systemStats.operatingHours)
                    if operatingHours == nil or operatingHours < 0 then
                        systemStats.operatingHours = currentOperatingHours
                    end
                end
            end
        end
    end
end
RealisticMechanicalSystems.registerVehicle = registerVehicle

---Adds or removes the cold engine effect from the current engine temperature
local function syncColdEngineEffect(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    if spec == nil then return end

    if vehicle.isServer then
        local engTemp = RealisticMechanicalSystems.sanitizeNumber(spec.rawEngineTemperature or spec.engineTemperature, -99, -99, 160)
        local breakdownId = 'COLD_ENGINE'

        if engTemp <= -10 and not vehicle:hasBreakdown(breakdownId) then
            vehicle:addBreakdown(breakdownId)
        elseif engTemp > -10 and vehicle:hasBreakdown(breakdownId) then
            vehicle:removeBreakdown(breakdownId)
        end
    end
end

local function syncAirFilterCloggingEffect(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    if spec == nil or not vehicle.isServer then return end

    local breakdownId = 'AIRFILTER_CLOGGING'
    local shouldBeStage = 0
    local threshold = RMS_Config.FIELD_CARE.AIR_FILTER_BREAKDOWN_THRESHOLD 

    if spec.airFilterClogging > threshold then
        if spec.airFilterClogging > (threshold + (threshold / 3 * 2)) then
            shouldBeStage = 3
        elseif spec.airFilterClogging > (threshold + (threshold / 3)) then
            shouldBeStage = 2
        else
            shouldBeStage = 1
        end
        if not vehicle:hasBreakdown(breakdownId) then
            vehicle:addBreakdown(breakdownId, shouldBeStage)
        else
            local currentStage = vehicle:getActiveBreakdowns()[breakdownId].stage
            if currentStage ~= shouldBeStage then
                vehicle:changeBreakdownStage(breakdownId, shouldBeStage)
            end
        end
    else
        if vehicle:hasBreakdown(breakdownId) then
            vehicle:removeBreakdown(breakdownId)
        end
    end
end

---Stops the AI helper and AutoDrive when a breakdown stops the machine working
local function syncDisableAiWorkers(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    if spec == nil or not vehicle.isServer then
        return
    end

    if spec.activeEffects ~= nil and next(spec.activeEffects) ~= nil then
        for _, effectData in pairs(spec.activeEffects) do
            if effectData ~= nil and effectData.extraData ~= nil and effectData.extraData.disableAi then
                local autoDriveActive = vehicle.ad ~= nil
                    and vehicle.ad.stateModule ~= nil
                    and vehicle.ad.stateModule.isActive ~= nil
                    and vehicle.ad.stateModule:isActive()

                if autoDriveActive and vehicle.stopAutoDrive ~= nil then
                    vehicle.ad.isStoppingWithError = true

                    if vehicle.ad.stateModule.setLoopsDone ~= nil then
                        vehicle.ad.stateModule:setLoopsDone(0)
                    end

                    vehicle:stopAutoDrive()
                end

                if vehicle:getIsAIActive() and vehicle.stopCurrentAIJob ~= nil then
                    vehicle:stopCurrentAIJob(AIMessageErrorVehicleBroken.new())
                end

                return
            end
        end
    end
end

local COLD_ENGINE_WARNING_MESSAGE = 'rms_spec_cold_engine_message'

---Returns the extra stress a cold engine puts on the systems
local function getColdEngineStress(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    local C = RMS_Config.CORE.ENGINE_FACTOR_DATA
    local engineTemperature = RealisticMechanicalSystems.sanitizeNumber(spec.rawEngineTemperature or spec.engineTemperature, -99, -99, 160)

    if not vehicle:getIsMotorStarted()
            or vehicle:getIsAIActive()
            or engineTemperature >= C.COLD_MOTOR_TEMP_THRESHOLD then
        return 0
    end

    local motorLoad = math.clamp(spec._smoothedMotorLoad, 0, 1)
    if motorLoad <= C.COLD_MOTOR_LOAD_THRESHOLD then
        return 0
    end

    local motor = vehicle.spec_motorized.motor
    local rpmLoad = math.clamp(motor:getLastRealMotorRpm() / motor.maxRpm, 0, 1)
    local temperatureFactor = RMS_Utils.calculateQuadraticMultiplier(
        engineTemperature,
        C.COLD_MOTOR_TEMP_THRESHOLD,
        true
    )
    local loadFactor = math.clamp(RMS_Utils.calculateQuadraticMultiplier(
        motorLoad,
        C.COLD_MOTOR_LOAD_THRESHOLD,
        false
    ), 0, 1)
    local rpmFactor = 1 - C.COLD_MOTOR_RPM_INFLUENCE
        + C.COLD_MOTOR_RPM_INFLUENCE * rpmLoad * rpmLoad

    return temperatureFactor * loadFactor * rpmFactor
end
RealisticMechanicalSystems.getColdEngineStress = getColdEngineStress

---Shows the blinking warnings of the active faults to the driving player
local function syncBlinkingWarning(vehicle, dt)
    local spec = vehicle.spec_RealisticMechanicalSystems
    if spec == nil or not vehicle.isClient then return end

    local C = RMS_Config.CORE.ENGINE_FACTOR_DATA
    if spec.engineTemperature >= C.COLD_MOTOR_TEMP_THRESHOLD then
        spec.coldEngineExposureMs = 0
        spec.coldEngineWarningShown = false
    end

    if RMS_Config.CORE.ENABLE_WARNING_MESSAGES == false
            and (spec.activeEffects == nil or spec.activeEffects.ENGINE_THERMAL_TORQUE_LIMIT == nil) then
        return
    end

    local repeatDelayMs = 180000

    if spec.blinkingWarningTimer == nil then
        spec.blinkingWarningTimer = 0
    end

    if spec.lastBlinkingWarningMessage == nil then
        spec.lastBlinkingWarningMessage = ""
    end

    if spec.blinkingWarningTimer > 0 then
        spec.blinkingWarningTimer = math.max(spec.blinkingWarningTimer - dt, 0)
    end

    local candidateMessage = nil
    local isActiveForInput = vehicle:getIsActiveForInput(true)
    local isAiActive = vehicle:getIsAIActive()
    local isUnderService = vehicle:isUnderService()
    local isMotorStarted = vehicle:getIsMotorStarted()
    local coldEngineStress = 0

    if isMotorStarted and isActiveForInput and not isAiActive and not spec.isElectricVehicle then
        local spec_motorized = vehicle.spec_motorized
        local motor = spec_motorized ~= nil and spec_motorized.motor or nil
        if motor ~= nil then
            local lastRpm = tonumber(motor:getLastModulatedMotorRpm()) or 0
            local maxRpm = math.max(tonumber(motor.maxRpm) or 0, 0.0001)
            local rpmLoad = lastRpm / maxRpm
            local motorLoad = 0

            if vehicle.getMotorLoad ~= nil then
                motorLoad = tonumber(vehicle:getMotorLoad()) or 0
            elseif vehicle.getMotorLoadPercentage ~= nil then
                motorLoad = tonumber(vehicle:getMotorLoadPercentage()) or 0
            end

            if spec.engineTemperature > -90 then
                coldEngineStress = getColdEngineStress(vehicle)
                if coldEngineStress > 0 then
                    spec.coldEngineExposureMs = spec.coldEngineExposureMs + dt
                end

                if coldEngineStress > 0
                        and spec.coldEngineExposureMs >= C.COLD_MOTOR_WARNING_EXPOSURE_MS
                        and not spec.coldEngineWarningShown then
                    candidateMessage = COLD_ENGINE_WARNING_MESSAGE
                elseif spec.engineTemperature >= RMS_Config.CORE.ENGINE_FACTOR_DATA.OVERHEAT_MOTOR_THRESHOLD + 5 and motorLoad > 0.3 then
                    candidateMessage = 'rms_spec_overheat_engine_message'
                end
            end

            if candidateMessage == nil and hasCVTTransmission(vehicle) and spec.transmissionTemperature > -90 then
                if spec.transmissionTemperature >= RMS_Config.CORE.TRANSMISSION_FACTOR_DATA.OVERHEAT_TRANSMISSION_THRESHOLD + 5 and rpmLoad > 0.75 then
                    candidateMessage = 'rms_spec_overheat_transmission_message'
                end
            end
        end
    end

    if coldEngineStress == 0 then
        spec.coldEngineExposureMs = math.max(spec.coldEngineExposureMs - dt, 0)
    end

    local thermalLimit = spec.activeEffects ~= nil and spec.activeEffects.ENGINE_THERMAL_TORQUE_LIMIT or nil
    if thermalLimit ~= nil and thermalLimit.extraData ~= nil and not isUnderService then
        candidateMessage = thermalLimit.extraData.message
    end

    if spec.activeEffects ~= nil and next(spec.activeEffects) ~= nil then
        for _, effectData in pairs(spec.activeEffects) do
            if effectData ~= nil and effectData.extraData ~= nil and effectData.extraData.message ~= nil then
                if candidateMessage == nil and isActiveForInput and not isUnderService then
                    candidateMessage = effectData.extraData.message
                end
            end
        end
    end

    if candidateMessage ~= nil
            and isActiveForInput
            and not isAiActive
            and not isUnderService
            and (spec.blinkingWarningTimer == 0 or spec.lastBlinkingWarningMessage ~= candidateMessage) then
        g_currentMission:showBlinkingWarning(g_i18n:getText(candidateMessage), 3600)
        spec.lastBlinkingWarningMessage = candidateMessage
        spec.blinkingWarningTimer = repeatDelayMs
        if candidateMessage == COLD_ENGINE_WARNING_MESSAGE then
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

---Pushes the pending side notifications of the vehicle
local function syncSideNotifications(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    if spec == nil or not vehicle.isClient then
        return
    end

    -- Pending warnings are runtime state, not join history.
    local pendingNotifications = spec.pendingSideNotifications
    spec.pendingSideNotifications = {}
    if pendingNotifications == nil or next(pendingNotifications) == nil then
        return
    end

    local warningsEnabled = RMS_Config.CORE == nil or RMS_Config.CORE.ENABLE_WARNING_MESSAGES ~= false

    if vehicle:getOwnerFarmId() ~= g_currentMission:getFarmId()
            or g_currentMission.hud == nil
            or g_currentMission.hud.addSideNotification == nil then
        return
    end

    local shownMessages = {}
    for effectId, messageKey in pairs(pendingNotifications) do
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

---Applies the fuel consumption modifier of the active effects
local function syncFuelConsumption(vehicle)
    local spec = vehicle.spec_RealisticMechanicalSystems
    if spec == nil then return end

    if vehicle.isServer and vehicle.spec_motorized ~= nil then
        if vehicle.getIsMotorStarted ~= nil and vehicle:getIsMotorStarted() then
            spec._fuelUsageRaw = RealisticMechanicalSystems.sanitizeNumber(vehicle.spec_motorized.lastFuelUsage, 0, 0, 10000)
        else
            spec._fuelUsageRaw = 0
        end
    end
    if vehicle.isClient and not vehicle.isServer and vehicle.spec_motorized ~= nil then
        vehicle.spec_motorized.lastFuelUsage = RealisticMechanicalSystems.sanitizeNumber(spec._fuelUsageRaw, 0, 0, 10000)
    end
end

---Keeps the CVT addon breakdown in step with the addon state
local function syncCVTaddonBreakdown(vehicle)
    if not hasCVTAddon(vehicle) then return end
    local spec = vehicle.spec_RealisticMechanicalSystems
    if spec == nil or not vehicle.isServer then return end

    local breakdownId = 'CVT_ADDON_MALFUNCTION'
    local spec_CVTaddon = vehicle.spec_CVTaddon
    if spec_CVTaddon ~= nil then
        local shouldHaveBreakdown = spec_CVTaddon.CVTdamage > 60.0
        local shouldBeStage = 1
        if spec_CVTaddon.CVTdamage > 90.0 then
            shouldBeStage = 4
        elseif spec_CVTaddon.CVTdamage > 80.0 then
            shouldBeStage = 3
        elseif spec_CVTaddon.CVTdamage > 70.0 then
            shouldBeStage = 2
        end

        if shouldHaveBreakdown and not vehicle:hasBreakdown(breakdownId) then
            vehicle:addBreakdown(breakdownId, shouldBeStage)
        elseif not shouldHaveBreakdown and vehicle:hasBreakdown(breakdownId) then
            vehicle:removeBreakdown(breakdownId)
        elseif shouldHaveBreakdown and vehicle:hasBreakdown(breakdownId) then
            local currentStage = vehicle:getActiveBreakdowns()[breakdownId].stage
            if currentStage ~= shouldBeStage then
                vehicle:changeBreakdownStage(breakdownId, shouldBeStage)
            end
        end
    else
        if vehicle:hasBreakdown(breakdownId) then
            vehicle:removeBreakdown(breakdownId)
        end
    end
end

---Measures the overload, shows its warning and counts its time
local function syncOverloadWarning(vehicle, dt)
    local spec = vehicle.spec_RealisticMechanicalSystems
    if spec == nil or not vehicle.isServer then return end
    local wearScale = RMS_Config.CORE.BASE_SYSTEMS_WEAR / RMS_Config.CORE.REFERENCE_SYSTEMS_WEAR
    local avgStressWarningThreshold = RMS_Config.CORE.AVG_STRESS_WARNING_THRESHOLD * wearScale
    local avgStressCriticalThreshold = RMS_Config.CORE.AVG_STRESS_CRITICAL_THRESHOLD * wearScale
    local sampleDurationMs = math.max(tonumber(dt) or 0, 1)
    local isMotorStarted = vehicle.getIsMotorStarted ~= nil and vehicle:getIsMotorStarted()

    local factorStats = ensureFactorStats(spec, vehicle)

    local shouldStage = 0
    local maxAvgStress = 0
    local maxSampleRate = 0
    for systemName, systemData in pairs(factorStats) do
        if type(systemData) == "table" then
            local systemStressMultiplier = RMS_Config.CORE.SYSTEM_WEIGHTS[systemName] ~= nil and 10.0 or 1.0
            local selectedAliases = OVERLOAD_FACTOR_ALIASES_BY_SYSTEM[tostring(systemName)]
            local currentStress = 0

            if type(selectedAliases) == "table" then
                for _, alias in ipairs(selectedAliases) do
                    currentStress = currentStress + math.max(tonumber(systemData[alias]) or 0, 0)
                end
                currentStress = currentStress * systemStressMultiplier
            end

            if not isMotorStarted then
                systemData._prevStress = currentStress
                resetOverloadAverage(systemData)
            else
            local previousStress = tonumber(systemData._prevStress)
            if previousStress == nil then
                previousStress = currentStress
            end

            local deltaStress = math.max(currentStress - previousStress, 0)
            local sampleRatePerHour = deltaStress * (60 * 60 * 1000) / sampleDurationMs
            systemData._prevStress = currentStress

            systemData._avgStress = updateOverloadAverage(systemData, sampleDurationMs, sampleRatePerHour)
            if systemData._avgStress > maxAvgStress then maxAvgStress = systemData._avgStress end

            local affectsOverloadBreakdown = type(selectedAliases) == "table" and #selectedAliases > 0
            if affectsOverloadBreakdown then
                maxSampleRate = math.max(maxSampleRate, sampleRatePerHour)
                if systemData._avgStress > avgStressCriticalThreshold then
                    shouldStage = 2
                elseif systemData._avgStress > avgStressWarningThreshold and shouldStage == 0 then
                    shouldStage = 1
                end
            end
            end
        end
    end
    spec.overloadLevel = maxSampleRate / avgStressWarningThreshold

    if RealisticMechanicalSystems.isMissionVehicle(vehicle) then
        return
    end

    local breakdownId = "STRESS_OVERLOAD"
    local activeBreakdowns = spec.activeBreakdowns or {}
    local currentBreakdown = activeBreakdowns[breakdownId]

    if shouldStage > 0 then
        if currentBreakdown == nil then
            vehicle:addBreakdown(breakdownId, shouldStage)
        elseif currentBreakdown.stage < shouldStage then
            vehicle:changeBreakdownStage(breakdownId, shouldStage)
        end
    elseif currentBreakdown ~= nil and maxAvgStress < avgStressWarningThreshold * 0.5 then
        vehicle:removeBreakdown(breakdownId)
    end
end

---Returns the motor load eased over time
local function getSmoothedMotorLoad(vehicle, dt)
    local spec = vehicle.spec_RealisticMechanicalSystems
    if spec == nil then return end

    if vehicle:getIsMotorStarted() then
        local rawLoad = math.max(vehicle:getMotorLoadPercentage() or 0, 0)
        local loadTau = 300
        local loadAlpha = math.min(dt / (loadTau + dt), 1)
        spec._smoothedMotorLoad = (spec._smoothedMotorLoad or 0) + loadAlpha * (rawLoad - (spec._smoothedMotorLoad or 0))
    else
        spec._smoothedMotorLoad = 0
    end
end

---Updates the specialization every rendered frame
-- @param float dt time since last call in ms
-- @param any ... additional update arguments
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
    RealisticMechanicalSystems.updateStartButtonActionEvents(self)
    RMS_Preheat.update(self, dt)
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

    if self.isClient then
        RMS_Exhaust.update(self)
    end

    if spec ~= nil and spec.activeFunctions ~= nil and next(spec.activeFunctions) ~= nil then
        for _ , func in pairs(spec.activeFunctions) do
            func(self, updateDt)
        end
    end
end

---Applies client-side effects after the rendered-frame update
-- @param float dt time since last call in ms
-- @param any ... additional update arguments
function RealisticMechanicalSystems:onPostUpdate(dt, ...)
    local spec = self.spec_RealisticMechanicalSystems
    if not self.isClient or spec.isExcludedVehicle then return end

    RMS_Exhaust.applyShader(self, dt)
end

function RealisticMechanicalSystems:onStartMotor()
    local spec = self.spec_RealisticMechanicalSystems
    RMS_Breakdowns.onStarterCaught(self)
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
    if self.spec_lights ~= nil and self:getLightsTypesMask() ~= 0 and RMS_Electrical.getKeepsLightsOff(self) then
        self:setLightsTypesMask(0, true, not self.isServer)
    end
end

---Runs the vehicle simulation step: state, wear, thermal, electrical, services
-- @param float dt time since last call in ms
-- @param boolean isWorkshopOpen true while the workshop accepts services
function RealisticMechanicalSystems:rmsUpdate(dt, isWorkshopOpen)
    local spec = self.spec_RealisticMechanicalSystems
    if spec.isExcludedVehicle then return end

    local motorState = self.getMotorState ~= nil and self:getMotorState() or nil
    local currentOperatingTime = self.getOperatingTime ~= nil and self:getOperatingTime() or self.operatingTime or 0
    local operatingDt = 0

    if (spec.realOperatingTime == nil or spec.realOperatingTime <= 0) and currentOperatingTime > 0 then
        spec.realOperatingTime = currentOperatingTime
    end

    if motorState == MotorState.ON then
        operatingDt = dt or 0
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
        self:updateEngineSystem(dt)
        self:updateTransmissionSystem(dt)
        self:updateHydraulicsSystem(dt)
        self:updatePtoSystem(dt)
        self:updateCoolingSystem(dt)
        self:updateElectricalSystem(dt)
        self:updateChassisSystem(dt)
        self:updateFuelSystem(dt)
        self:updateConditionLevel()
        self:processWornParts()
        if not isMissionVehicle then
            self:updateLubricationLevel(operatingDt, motorState)
            self:updateFluidLevels(operatingDt)
            self:updateFilterClogging(operatingDt)
        end
        syncOverloadWarning(self, dt)
    end

    if self.isServer and spec.isElectricVehicle then
        RMS_ElectricDrive.applyBatteryCapacity(self)
    end

    if self.isServer then
        markStateDirty(self, spec)
        markServiceContextDirty(self, spec)
        markTelemetryDirty(self, spec)
        markThermalDirty(self, spec)
        markElectricalDirty(self, spec)
        markFieldcareDirty(self, spec)
        markWearDirty(self, spec)
        markBreakdownsDirty(self, spec)
        markServiceProgressDirty(self, spec)
        markTutorialDataDirty(self, spec)
        RealisticMechanicalSystems.updateResalePrice(self)
    end
end

---Replaces the vanilla damage with the RMS condition
-- @param table wearable wearable spec
-- @param function superFunc super function
-- @param float dt time since last call in ms
function RealisticMechanicalSystems.updateDamageAmount(wearable, superFunc, dt)
	if wearable.spec_RealisticMechanicalSystems ~= nil and not wearable.spec_RealisticMechanicalSystems.isExcludedVehicle then
		return 0
	else
		return superFunc(wearable, dt)
	end
end

---Flags the resale quote dirty when either payment changes
-- @param table self vehicle
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
-- @param table self vehicle
-- @param function superFunc super function
-- @return float price sell price
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
-- @param table self vehicle
-- @param function superFunc super function
-- @param float dt time since last call in ms
function RealisticMechanicalSystems.updateMotorTemperature(self, superFunc, dt)
    local spec = self.spec_RealisticMechanicalSystems
    if spec == nil or spec.isExcludedVehicle or hasCVTAddon(self) then
        return superFunc(self, dt)
    end
    RMS_Thermal.getEngineTemperature(self)
    RMS_Thermal.syncEngineProtection(self)
end

---Returns the level of the lowest service clock
-- @return float serviceLevel service level
function RealisticMechanicalSystems:getServiceLevel()
    local spec = self.spec_RealisticMechanicalSystems
    local serviceLevel = spec.baseServiceLevel
    for _, clock in ipairs(self:getServiceClocks()) do
        serviceLevel = math.min(serviceLevel, self:getServiceClockLevel(clock))
    end

    return serviceLevel
end

---Returns the overall condition level
-- @return float conditionLevel condition level
function RealisticMechanicalSystems:getConditionLevel()
    return self.spec_RealisticMechanicalSystems.conditionLevel
end

---Returns the condition of one system
-- @param string systemName system name
-- @return float? condition system condition
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

---Tells whether the vehicle stands under a roof, by raycasting upward
-- @return boolean isUnderRoof true when sheltered
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
    local isIndoorMask = false

    if mission ~= nil and mission.indoorMask ~= nil then
        if mission.indoorMask.getIsIndoorAtWorldPosition ~= nil then
            isIndoorMask = mission.indoorMask:getIsIndoorAtWorldPosition(x, z) == true
        else
            local handle, firstChannel, numChannels = mission.indoorMask:getDensityMapData()
            if handle ~= nil and handle ~= 0 and mission.terrainSize ~= nil and mission.terrainSize > 0 then
                local maskSize = getBitVectorMapSize(handle)
                if maskSize ~= nil and maskSize > 0 then
                    local terrainHalfSize = mission.terrainSize * 0.5
                    local worldToDensityMap = maskSize / mission.terrainSize
                    local xI = math.floor((x + terrainHalfSize) * worldToDensityMap)
                    local zI = math.floor((z + terrainHalfSize) * worldToDensityMap)

                    if xI >= 0 and xI < maskSize and zI >= 0 and zI < maskSize then
                        local maskValue = getBitVectorMapPoint(handle, xI, zI, firstChannel, numChannels)
                        isIndoorMask = maskValue == IndoorMask.INDOOR
                    end
                end
            end
        end
    end

    local movementVehicle = self.rootVehicle or self
    local speed = movementVehicle.getLastSpeed ~= nil and math.abs(tonumber(movementVehicle:getLastSpeed(true)) or 0) or 0
    local stationarySpeedLimit = tonumber(RMS_Config.ROOF_STATIONARY_SPEED_LIMIT) or 0.5
    local isStationary = speed <= stationarySpeedLimit

    if not isStationary then
        if spec ~= nil then
            spec.roofWasStationary = false
            spec.roofLastRaycastTime = nil
            spec.roofRaycastResult = nil
        end
        return isIndoorMask
    end

    if spec == nil then
        return isIndoorMask
    end

    local now = (mission ~= nil and mission.time) or g_time or 0
    local raycastInterval = tonumber(RMS_Config.ROOF_RAYCAST_INTERVAL) or 5000
    local lastRaycastTime = tonumber(spec.roofLastRaycastTime)
    local needsRaycast = spec.roofWasStationary ~= true
        or lastRaycastTime == nil
        or now < lastRaycastTime
        or now - lastRaycastTime >= raycastInterval

    spec.roofWasStationary = true

    if needsRaycast then
        spec.roofLastRaycastTime = now
        spec.roofRaycastHit = false

        local roofMask = CollisionFlag.STATIC_OBJECT + CollisionFlag.BUILDING
        raycastClosest(
            x,
            y + (tonumber(RMS_Config.ROOF_RAYCAST_START_OFFSET) or 1),
            z,
            0,
            1,
            0,
            tonumber(RMS_Config.ROOF_RAYCAST_DISTANCE) or 40,
            "isUnderRoofRaycastCallback",
            self,
            roofMask
        )

        spec.roofRaycastResult = spec.roofRaycastHit == true
    end

    if spec.roofRaycastResult ~= nil then
        return spec.roofRaycastResult == true
    end

    return isIndoorMask
end

---Tells whether a service is running on the vehicle
-- @return boolean isUnderService true while a service runs
function RealisticMechanicalSystems:isUnderService()
    return self.spec_RealisticMechanicalSystems.currentState ~= RealisticMechanicalSystems.STATUS.READY
end

---Returns the current status of the vehicle
-- @return string status status constant
function RealisticMechanicalSystems:getCurrentStatus()
    return self.spec_RealisticMechanicalSystems.currentState
end

---Returns the active breakdowns of the vehicle
-- @return table breakdowns active breakdowns
function RealisticMechanicalSystems:getActiveBreakdowns()
    return self.spec_RealisticMechanicalSystems.activeBreakdowns
end

---Returns the reliability multiplier of the brand of a vehicle
-- @param table vehicle vehicle
-- @param table? storeItem store item
-- @return float reliability brand reliability
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
