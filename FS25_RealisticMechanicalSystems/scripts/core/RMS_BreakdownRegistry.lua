-- Copyright (C) 2026 Squallqt.
-- Licensed under the GNU General Public License v3.0 or later. See LICENSE.

---Breakdown definitions.

-- dashboard indicator ids
RMS_Breakdowns.DASHBOARD = {
    ENGINE = "engine",
    WARNING = "warning",
    TRANSMISSION = "transmission",
    BRAKES = "brakes",
    BATTERY = "battery",
    COOLANT = "coolant",
    SERVICE = "service",
    OIL = "oil",
    PREHEAT = "preheat",
    TRACTION_BATTERY = "tractionBattery",
    LIMITED_POWER = "limitedPower",
    DPF = "dpf"
}

-- indicator colours
RMS_Breakdowns.COLORS = {
    DEFAULT = Dashboard.COLORS.GREY,
    COOL = { 0.0097, 0.4287, 0.6445, 1 },
    WARNING  = { 1, 0.4287, 0.0006, 1 },
    CRITICAL = {0.8069, 0.0097, 0.0097, 1}
}

local color = RMS_Breakdowns.COLORS
local db = RMS_Breakdowns.DASHBOARD

local glowPlugFailureIndicator = {
    id = db.PREHEAT,
    color = color.WARNING,
    switchOn = function(vehicle)
        return vehicle ~= nil and vehicle.getIsMotorStarted ~= nil and vehicle:getIsMotorStarted()
    end,
    switchOff = function(vehicle)
        return vehicle == nil or vehicle.getIsMotorStarted == nil or not vehicle:getIsMotorStarted()
    end,
    blinkWhileActive = true
}

-- which colour wins when several indicators share a slot
RMS_Breakdowns.COLOR_PRIORITY = {
    [color.CRITICAL] = 3,
    [color.WARNING]  = 2,
    [color.COOL]     = 1,
    [color.DEFAULT]  = 0
}


local getIsElectricVehicle = RMS_Utils.getIsElectricVehicle
local hasCVTAddon = RMS_Utils.hasCVTAddon

---Tells whether a powershift gearbox runs without CVT conversion
local function isPowershiftBreakdownApplicable(vehicle)
    if hasCVTAddon(vehicle) or getIsElectricVehicle(vehicle) then return false end
    local motor = vehicle:getMotor()
    return motor ~= nil and (motor.gearType == VehicleMotor.TRANSMISSION_TYPE.POWERSHIFT
        or motor.groupType == VehicleMotor.TRANSMISSION_TYPE.POWERSHIFT)
end

local function isSteeringWheelBreakdownApplicable(vehicle)
    if vehicle.spec_wheels == nil or vehicle.spec_wheels.wheels == nil or #vehicle.spec_wheels.wheels == 0 then
        return false
    end
    return vehicle.spec_crawlers == nil or #vehicle.spec_crawlers.crawlers == 0
end

local function isCrawlerBreakdownApplicable(vehicle)
    return vehicle.spec_crawlers ~= nil and vehicle.spec_crawlers.crawlers ~= nil and #vehicle.spec_crawlers.crawlers > 0
end

local function isFrontLoaderPivotBreakdownApplicable(vehicle)
    local spec = vehicle.spec_cylindered
    for _, tool in ipairs(spec ~= nil and spec.movingTools or {}) do
        if RMS_Utils.getIsLoaderMovingTool(tool) then
            return true
        end
    end
    return false
end

local function isTrailerBrakeValveApplicable(vehicle)
    local spec = vehicle.spec_attacherJoints
    if spec == nil or spec.attacherJoints == nil then
        return false
    end
    for _, joint in pairs(spec.attacherJoints) do
        local jointType = joint.jointType
        if jointType == AttacherJoints.JOINTTYPE_TRAILER
            or jointType == AttacherJoints.JOINTTYPE_TRAILERLOW then
            return true
        end
    end
    return false
end

local function isCabSuspensionApplicable(vehicle)
    local spec = vehicle.spec_suspensions
    for _, suspension in ipairs(spec ~= nil and spec.suspensionNodes or {}) do
        if suspension.isRotational and not suspension.useCharacterTorso then
            return true
        end
    end
    return false
end

local function isTransmissionFilterApplicable(vehicle)
    if getIsElectricVehicle(vehicle) or RMS_Fluids.getSumpCircuit(vehicle, "hydraulicFluid") == "transmissionOil" then
        return false
    end
    local motor = vehicle:getMotor()
    return motor ~= nil and (motor.gearType == VehicleMotor.TRANSMISSION_TYPE.POWERSHIFT
        or motor.groupType == VehicleMotor.TRANSMISSION_TYPE.POWERSHIFT or RMS_Utils.hasCVTTransmission(vehicle))
end

---Tells whether the machine burns AdBlue
local function isAdBlueApplicable(vehicle)
    return vehicle.spec_motorized and vehicle.spec_motorized.consumersByFillTypeName and vehicle.spec_motorized.consumersByFillTypeName.DEF ~= nil
end

local systems = RealisticMechanicalSystems.SYSTEMS

RMS_Breakdowns.PARTS = {
    VEHICLE = "rms_breakdowns_part_vehicle",
    CONSUMABLES = "rms_breakdowns_part_consumables",
    ENGINE = "rms_breakdowns_part_engine",
    BATTERY = "rms_breakdowns_part_battery",
    TRACTION_BATTERY = "rms_breakdowns_part_traction_battery",
    HV_CONTACTOR = "rms_breakdowns_part_hv_contactor",
    HV_WIRING = "rms_breakdowns_part_hv_wiring",
    INVERTER = "rms_breakdowns_part_inverter",
    DCDC_CONVERTER = "rms_breakdowns_part_dcdc_converter",
    ONBOARD_CHARGER = "rms_breakdowns_part_onboard_charger",
    ELECTRIC_MOTOR_BEARINGS = "rms_breakdowns_part_electric_motor_bearings",
    ELECTRIC_MOTOR_WINDINGS = "rms_breakdowns_part_electric_motor_windings",
    MOTOR_POSITION_SENSOR = "rms_breakdowns_part_motor_position_sensor",
    COOLANT_PUMP = "rms_breakdowns_part_coolant_pump",
    COOLANT_HOSES = "rms_breakdowns_part_coolant_hoses",
    EXPANSION_TANK = "rms_breakdowns_part_expansion_tank",
    ACCESSORY_BELT_KIT = "rms_breakdowns_part_accessory_belt_kit",
    FAN_BLADE = "rms_breakdowns_part_fan_blade",
    ELECTRIC_COOLING_FAN = "rms_breakdowns_part_electric_cooling_fan",
    THERMAL_WATER_PUMP = "rms_breakdowns_part_thermal_water_pump",
    RADIATOR_CORE = "rms_breakdowns_part_radiator_core",
    REDUCER = "rms_breakdowns_part_reducer",
    GLOW_PLUGS = "rms_breakdowns_part_glow_plugs",
    ECU = "rms_breakdowns_part_ecu",
    POWER_CABLES_AND_GROUNDS = "rms_breakdowns_part_power_cables_and_grounds",
    STARTER_RELAY = "rms_breakdowns_part_starter_relay",
    PREHEAT_RELAY = "rms_breakdowns_part_preheat_relay",
    LOW_BEAM_BULBS = "rms_breakdowns_part_low_beam_bulbs",
    HIGH_BEAM_BULBS = "rms_breakdowns_part_high_beam_bulbs",
    FRONT_WORK_LIGHT_BULBS = "rms_breakdowns_part_front_work_light_bulbs",
    REAR_WORK_LIGHT_BULBS = "rms_breakdowns_part_rear_work_light_bulbs",
    BEACON_BULB = "rms_breakdowns_part_beacon_bulb",
    TURN_SIGNAL_BULBS = "rms_breakdowns_part_turn_signal_bulbs",
    ALTERNATOR = "rms_breakdowns_part_alternator",
    STARTER = "rms_breakdowns_part_starter",
    TURBOCHARGER = "rms_breakdowns_part_turbocharger",
    OIL_PUMP = "rms_breakdowns_part_oil_pump",
    PISTONS = "rms_breakdowns_part_pistons",
    PISTON_RINGS = "rms_breakdowns_part_piston_rings",
    CYLINDER_LINERS = "rms_breakdowns_part_cylinder_liners",
    INLET_VALVES = "rms_breakdowns_part_inlet_valves",
    EXHAUST_VALVES = "rms_breakdowns_part_exhaust_valves",
    VALVE_GUIDES_SEALS = "rms_breakdowns_part_valve_guides_seals",
    CYLINDER_HEAD = "rms_breakdowns_part_cylinder_head",
    CYLINDER_HEAD_GASKET = "rms_breakdowns_part_cylinder_head_gasket",
    MAIN_BEARINGS = "rms_breakdowns_part_main_bearings",
    CONROD_BEARINGS = "rms_breakdowns_part_conrod_bearings",
    CLUTCH = "rms_breakdowns_part_clutch",
    SYNCHRONIZER = "rms_breakdowns_part_synchronizer",
    CVT_HYDRAULIC_CONTROL_VALVE = "rms_breakdowns_part_cvt_hydraulic_control_valve",
    CVT = "rms_breakdowns_part_cvt",
    TRANSMISSION_SEAL = "rms_breakdowns_part_transmission_seal",
    GEARBOX_BEARINGS = "rms_breakdowns_part_gearbox_bearings",
    POWERSHIFT_CLUTCHES = "rms_breakdowns_part_powershift_clutches",
    POWERSHIFT_REVERSER = "rms_breakdowns_part_powershift_reverser",
    TRANSMISSION_CONTROL = "rms_breakdowns_part_transmission_control",
    TRANSMISSION_PUMP = "rms_breakdowns_part_transmission_pump",
    HYDROSTATIC_UNIT = "rms_breakdowns_part_hydrostatic_unit",
    TRANSMISSION_OIL_COOLER = "rms_breakdowns_part_transmission_oil_cooler",
    REAR_BEVEL_GEAR = "rms_breakdowns_part_rear_bevel_gear",
    FINAL_DRIVES = "rms_breakdowns_part_final_drives",
    DIFFERENTIAL = "rms_breakdowns_part_differential",
    DIFF_LOCK_CONTROL = "rms_breakdowns_part_diff_lock_control",
    FOUR_WD_CONTROL = "rms_breakdowns_part_four_wd_control",
    FRONT_AXLE_SHAFT = "rms_breakdowns_part_front_axle_shaft",
    AXLE_BEARINGS = "rms_breakdowns_part_axle_bearings",
    TRANSMISSION_SENSORS = "rms_breakdowns_part_transmission_sensors",
    TRANSMISSION_FILTER = "rms_breakdowns_part_transmission_filter",
    LIFT_VALVE = "rms_breakdowns_part_lift_valve",
    LIFT_POSITION_SENSOR = "rms_breakdowns_part_lift_position_sensor",
    LOADER_CONTROL = "rms_breakdowns_part_loader_control",
    HYDRAULIC_QUICK_COUPLERS = "rms_breakdowns_part_hydraulic_quick_couplers",
    HYDRAULIC_PUMP = "rms_breakdowns_part_hydraulic_pump",
    HYDRAULIC_CYLINDER = "rms_breakdowns_part_hydraulic_cylinder",
    HYDRAULIC_HOSE = "rms_breakdowns_part_hydraulic_hose",
    HYDRAULIC_FILTER = "rms_breakdowns_part_hydraulic_filter",
    HYDRAULIC_OIL_COOLER = "rms_breakdowns_part_hydraulic_oil_cooler",
    HYDRAULIC_SPOOL_VALVE = "rms_breakdowns_part_hydraulic_spool_valve",
    BRAKE_CONTROL = "rms_breakdowns_part_brake_control",
    TRAILER_BRAKE_VALVE = "rms_breakdowns_part_trailer_brake_valve",
    BRAKE_DISCS = "rms_breakdowns_part_brake_discs",
    PARK_BRAKE = "rms_breakdowns_part_park_brake",
    WHEEL_BEARING = "rms_breakdowns_part_wheel_hub_bearing",
    STEERING_LINKAGE = "rms_breakdowns_part_steering_linkage",
    STEERING_KNUCKLE_PIVOT = "rms_breakdowns_part_steering_knuckle_pivot",
    STEERING_ORBITROL = "rms_breakdowns_part_steering_orbitrol",
    STEERING_CYLINDER = "rms_breakdowns_part_steering_cylinder",
    CAB_SUSPENSION = "rms_breakdowns_part_cab_suspension",
    LOADER_PINS_AND_BUSHINGS = "rms_breakdowns_part_loader_pins_and_bushings",
    TRACK_TENSIONER = "rms_breakdowns_part_track_tensioner",
    TRACK_ROLLERS = "rms_breakdowns_part_track_rollers",
    THERMOSTAT = "rms_breakdowns_part_thermostat",
    FAN_CLUTCH = "rms_breakdowns_part_fan_clutch",
    FUEL_PUMP = "rms_breakdowns_part_fuel_pump",
    FUEL_INJECTORS = "rms_breakdowns_part_fuel_injectors",
    HIGH_PRESSURE_PUMP = "rms_breakdowns_part_high_pressure_pump",
    FUEL_FILTER = "rms_breakdowns_part_fuel_filter",
    FUEL_LINE = "rms_breakdowns_part_fuel_line",
    MECHANICAL_INJECTION_PUMP = "rms_breakdowns_part_mechanical_injection_pump",
    FUEL_METERING_VALVE = "rms_breakdowns_part_fuel_metering_valve",
    RAIL_PRESSURE_SENSOR = "rms_breakdowns_part_rail_pressure_sensor",
    RAIL_PRESSURE_LIMITER = "rms_breakdowns_part_rail_pressure_limiter",
    GAS_PRESSURE_REGULATOR = "rms_breakdowns_part_gas_pressure_regulator",
    GAS_SHUTOFF_SOLENOID = "rms_breakdowns_part_gas_shutoff_solenoid",
    GAS_FILTER = "rms_breakdowns_part_gas_filter",
    GAS_LINES = "rms_breakdowns_part_gas_lines",
    GAS_INJECTORS = "rms_breakdowns_part_gas_injectors",
    ADBLUE_PUMP = "rms_breakdowns_part_adblue_pump",
    ADBLUE_DOSER = "rms_breakdowns_part_adblue_doser",
    ADBLUE_FILTER = "rms_breakdowns_part_adblue_filter",
    NOX_SENSOR = "rms_breakdowns_part_nox_sensor",
    PARTICULATE_FILTER = "rms_breakdowns_part_particulate_filter",
    PTO_CLUTCH = "rms_breakdowns_part_pto_clutch",
    PTO_ENGAGEMENT_SOLENOID = "rms_breakdowns_part_pto_engagement_solenoid",
    PTO_OUTPUT_BEARING = "rms_breakdowns_part_pto_output_bearing",
    PTO_OUTPUT_SEAL = "rms_breakdowns_part_pto_output_seal",
    PTO_OUTPUT_SHAFT = "rms_breakdowns_part_pto_output_shaft",
    PTO_ENGAGEMENT_SWITCH = "rms_breakdowns_part_pto_engagement_switch",
    PTO_SPEED_SENSOR = "rms_breakdowns_part_pto_speed_sensor",
    PTO_BRAKE = "rms_breakdowns_part_pto_brake",
    FRONT_PTO_CLUTCH = "rms_breakdowns_part_front_pto_clutch"
}

local parts = RMS_Breakdowns.PARTS

local stagePartPrices = {
    ENGINE_JAM = { 4.578 },
    ECU_MALFUNCTION = { 0.6191, 0.6191, 0.6191, 0.6191 },
    POWER_CABLE_CONNECTION_FAILURE = { 0.0, 0.0, 0.06206, 0.1225 },
    STARTER_RELAY_FAILURE = { 0.0238 },
    PREHEAT_RELAY_FAILURE = { 0.01727 },
    LOW_BEAM_FAILURE = { 0.00818 },
    HIGH_BEAM_FAILURE = { 0.00818 },
    FRONT_WORK_LIGHTS_FAILURE = { 0.00818 },
    REAR_WORK_LIGHTS_FAILURE = { 0.00818 },
    BEACON_LIGHTS_FAILURE = { 0.002836 },
    TURN_LIGHTS_FAILURE = { 0.003938 },
    BATTERY_SULFATION = { 0.1175, 0.1175, 0.1175, 0.1175 },
    GLOW_PLUG_FAILURE = { 0.04384, 0.04384, 0.04384, 0.04384 },
    ALTERNATOR = { 0.3748, 0.3748, 0.3748, 0.3748 },
    STARTER_FAILURE = { 0.2537, 0.2537, 0.2537, 0.2537 },
    INVERTER_MALFUNCTION = { 13.82, 13.82, 13.82, 13.82 },
    DCDC_CONVERTER_FAILURE = { 2.686, 2.686, 2.686, 2.686 },
    ONBOARD_CHARGER_FAILURE = { 6.188, 6.188, 6.188, 6.188 },
    HV_INSULATION_LOSS = { 2.138, 2.138, 2.138, 2.138 },
    TURBOCHARGER_MALFUNCTION = { 0.5706, 0.5706, 0.5706, 0.5706 },
    OIL_PUMP_MALFUNCTION = { 0.1823, 0.1823, 0.3587, 0.3587 },
    PISTONS = { 0.5621, 0.93, 0.93, 1.106 },
    PISTON_RINGS = { 0.2382, 0.6061, 0.93, 0.93 },
    CYLINDER_LINERS = { 0.5621, 0.93, 0.93, 0.93 },
    INLET_VALVES = { 0.1386, 0.1386, 0.1386, 1.371 },
    EXHAUST_VALVES = { 0.1361, 0.1361, 0.1361, 1.371 },
    VALVE_GUIDES_SEALS = { 0.128, 0.128, 0.128, 0.8534 },
    CYLINDER_HEAD = { 1.705, 1.705, 1.705, 1.705 },
    CYLINDER_HEAD_GASKET = { 0.4442, 0.4442, 0.4442, 1.17 },
    MAIN_BEARINGS = { 0.07768, 0.07768, 0.07768, 0.6997 },
    CONROD_BEARINGS = { 0.09872, 0.09872, 0.09872, 0.6695 },
    ELECTRIC_MOTOR_BEARING_WEAR = { 20.23, 20.23, 20.23, 20.23 },
    ELECTRIC_MOTOR_WINDING_FAULT = { 20.23, 20.23, 20.23, 20.23 },
    MOTOR_POSITION_SENSOR_FAULT = { 0.4285, 0.4285, 0.4285, 0.4285 },
    MANUAL_TRANSMISSION_CLUTCH_WEAR = { 0.1129, 0.1129, 0.1571, 0.1571 },
    MANUAL_TRANSMISSION_SYNCHRONIZER_MALFUNCTION = { 0.191, 0.191, 0.191, 0.191 },
    GEARBOX_BEARING_FAILURE = { 0.1101, 0.1101, 0.1101, 0.4272 },
    POWERSHIFT_CLUTCH_FAILURE = { 0.3538, 0.3538, 0.6181, 0.8147 },
    POWERSHIFT_REVERSER_FAILURE = { 0.3538, 0.3538, 0.4588, 0.4841 },
    TRANSMISSION_CONTROL_FAILURE = { 0.1427, 0.1427, 0.54, 0.54 },
    TRANSMISSION_SENSOR_FAILURE = { 0.02213, 0.02213 },
    CVT_SENSOR_FAILURE = { 0.02213, 0.02213 },
    TRANSMISSION_PUMP_MALFUNCTION = { 1.073, 1.073, 1.073, 1.585 },
    HYDROSTATIC_UNIT_MALFUNCTION = { 5.929, 5.929, 5.929, 5.929 },
    CVT_HYDRAULIC_CONTROL_VALVE_MALFUNCTION = { 0.1427, 0.1427, 1.129, 2.458 },
    TRANSMISSION_OIL_LEAK = { 0.02483, 0.02483, 0.02483, 1.098 },
    TRANSMISSION_OIL_COOLER_MALFUNCTION = { 0.4872, 0.4872, 0.6305, 0.6305 },
    TRANSMISSION_FILTER_CLOGGING = { 0.02529, 0.02529, 0.02529, 0.02529 },
    REAR_BEVEL_GEAR_FAILURE = { 1.11, 1.11, 1.11, 1.22 },
    FINAL_DRIVE_FAILURE = { 0.5334, 0.5334, 1.063, 2.367 },
    DIFFERENTIAL_FAILURE = { 0.2859, 0.2859, 0.396, 1.819 },
    FRONT_AXLE_SHAFT_WEAR = { 0.2213, 0.2213, 0.2213, 0.2213 },
    AXLE_BEARING_WEAR = { 0.1101, 0.1101, 0.1101, 1.22 },
    DIFF_LOCK_CONTROL_FAILURE = { 0.2459 },
    FOUR_WD_CONTROL_FAILURE = { 0.1427 },
    REDUCER_GEAR_WEAR = { 4.079, 4.079, 4.079, 4.079 },
    CVT_ADDON_MALFUNCTION = { 0.1427, 1.265, 2.451, 14.95 },
    HYDRAULIC_PUMP_MALFUNCTION = { 1.073, 1.073, 1.073, 1.122 },
    HYDRAULIC_SPOOL_VALVE_MALFUNCTION = { 0.01559, 0.01559, 0.5716, 0.5953 },
    LIFT_VALVE_FAILURE = { 0.7745 },
    LIFT_POSITION_SENSOR_FAILURE = { 0.07243 },
    LOADER_CONTROL_FAILURE = { 0.1001, 0.1001, 0.6351, 0.6351 },
    HYDRAULIC_CYLINDER_INTERNAL_LEAK = { 0.08889, 0.08889, 0.08889, 0.5593 },
    HYDRAULIC_QUICK_COUPLER_FAILURE = { 0.01869, 0.01869, 0.01869, 0.01869 },
    HYDRAULIC_HOSE_EXTERNAL_LEAK = { 0.04035, 0.04035, 0.04035, 0.04035 },
    HYDRAULIC_FILTER_CLOGGING = { 0.02375, 0.02375, 0.02375, 0.02375 },
    HYDRAULIC_OIL_COOLER_MALFUNCTION = { 0.4872, 0.4872, 0.4872, 0.6543 },
    PTO_CLUTCH_WEAR = { 0.1657, 0.1657, 0.4345, 1.53 },
    PTO_OUTPUT_BEARING_WEAR = { 0.06241, 0.06241, 0.2368, 0.4839 },
    PTO_OUTPUT_SEAL_LEAK = { 0.08538, 0.08538, 0.08538, 1.158 },
    PTO_ENGAGEMENT_SOLENOID_FAILURE = { 0.1427, 0.1427, 0.1427, 0.1427 },
    PTO_ENGAGEMENT_SWITCH_FAILURE = { 0.004688, 0.004688, 0.004688, 0.004688 },
    PTO_OUTPUT_SHAFT_FAILURE = { 0.4283 },
    PTO_SPEED_SENSOR_FAILURE = { 0.02213 },
    PTO_BRAKE_FAILURE = { 0.03205 },
    FRONT_PTO_CLUTCH_FAILURE = { 0.2787, 0.2787, 0.8322, 0.8322 },
    BRAKE_DISC_WEAR = { 0.02298, 0.02298, 0.0854, 0.1687 },
    BRAKE_CONTROL_FAILURE = { { 0.08516, 0.001883 }, { 0.08516, 0.001883 }, { 0.08516, 1.124 }, { 0.08516, 1.124 } },
    TRAILER_BRAKE_VALVE_FAILURE = { 0.2023, 0.2023, 0.2023, 0.2023 },
    PARK_BRAKE_MALFUNCTION = { 0.05056, 0.05056, 0.05056, 0.05056 },
    WHEEL_HUB_BEARING_WEAR = { 0.06082, 0.06082, 0.06082, 0.3099 },
    STEERING_LINKAGE_WEAR = { 0.126, 0.126, 0.2436, 0.2436 },
    STEERING_KNUCKLE_PIVOT_WEAR = { 0.02471, 0.02471, 0.1459, 0.8786 },
    STEERING_ORBITROL_MALFUNCTION = { 0.5496, 0.5496, 0.5496, 0.5496 },
    STEERING_CYLINDER_LEAK = { { 0.2965, 0.01118 }, { 0.2965, 0.01118 }, { 0.2965, 0.01118 }, { 0.2965, 0.2965 } },
    LOADER_PIVOT_PIN_WEAR = { 0.04924, 0.04924, 0.04924, 0.04924 },
    CAB_SUSPENSION_DAMPER_LEAK = { 0.09783, 0.09783, 0.09783, 0.09783 },
    TRACK_ROLLER_BEARING_WEAR = { 0.2884, 0.2884, 0.2884, 0.5769 },
    TRACK_TENSIONER_MALFUNCTION = { 0.08889, 0.08889, 0.4239, 0.4239 },
    THERMOSTAT_MALFUNCTION = { 0.0367, 0.0367, 0.0367, 0.0367 },
    COOLANT_HOSE_FAILURE = { 0.03974, 0.03974, 0.05674, 0.05674 },
    EXPANSION_TANK_FAILURE = { 0.1243, 0.1243, 0.1243, 0.1243 },
    ACCESSORY_BELT_FAILURE = { 0.07894, 0.07894, 0.07894, 0.07894 },
    FAN_BLADE_FAILURE = { 0.2838, 0.2838, 0.2838, 0.7579 },
    ELECTRIC_COOLING_FAN_FAILURE = { 0.2382, 0.2382, 0.2382, 0.2382 },
    FAN_CLUTCH_FAILURE = { 0.3866, 0.3866, 0.3866, 0.3866 },
    COOLANT_PUMP_FAILURE = { 0.2228, 0.2228, 0.2228, 0.2228 },
    THERMAL_WATER_PUMP = { 0.2228, 0.2228, 0.2228, 0.2228 },
    RADIATOR_CORE = { 0.4892, 0.4892, 0.4892, 0.4892 },
    FUEL_PUMP_MALFUNCTION = { 0.02944, 0.02944, 0.02944, 0.02944 },
    FUEL_INJECTOR_MALFUNCTION = { 0.1834, 0.1834, 0.2602, 0.2602 },
    HIGH_PRESSURE_PUMP_MALFUNCTION = { 1.057, 1.057, 1.072, 1.802 },
    FUEL_FILTER_CLOGGING = { 0.01432, 0.01432, 0.01432, 0.01432 },
    FUEL_LINE_AIR_LEAK = { 0.02487, 0.02487, 0.02487, 0.02487 },
    MECHANICAL_INJECTION_PUMP_MALFUNCTION = { 1.219, 1.219, 1.219, 1.219 },
    FUEL_METERING_VALVE_FAILURE = { 0.1858, 0.1858, 0.1858, 0.1858 },
    RAIL_PRESSURE_SENSOR_FAILURE = { 0.1665, 0.1665, 0.1665, 0.1665 },
    RAIL_PRESSURE_LIMITER_FAILURE = { 0.1474, 0.1474, 0.1474, 0.1474 },
    GAS_PRESSURE_REGULATOR_FAILURE = { 1.468, 1.468, 1.468, 1.468 },
    GAS_SHUTOFF_SOLENOID_FAILURE = { 0.1427, 0.1427, 0.1427, 0.1427 },
    GAS_FILTER_CLOGGING = { 0.1086, 0.1086, 0.1086, 0.1086 },
    GAS_LINE_LEAK = { 0.04035, 0.04035, 0.04035, 0.04035 },
    GAS_INJECTOR_MALFUNCTION = { 1.303, 1.303, 1.303, 1.303 },
    ADBLUE_PUMP_FAILURE = { 0.2912 },
    ADBLUE_DOSER_FAILURE = { 0.2182 },
    ADBLUE_FILTER_CLOGGING = { 0.02477, 0.02477, 0.02477, 0.02477 },
    NOX_SENSOR_FAILURE = { 0.1907 },
    PARTICULATE_FILTER_FAILURE = { 1.957, 1.957, 1.957, 1.957 },
    PARTICULATE_FILTER_SOOT_OVERLOAD = { 0.0, 0.1548 },
    TRACTION_BATTERY_CELL_FAULT = { 45.88, 45.88, 45.88, 45.88 },
    HV_CONTACTOR_FAILURE = { 0.3363, 0.3363, 0.3363, 0.3363 },
}

local breakdownProgressMultipliers = {
    ECU_MALFUNCTION = 1.00, 
    POWER_CABLE_CONNECTION_FAILURE = 0.9,
    BATTERY_SULFATION = 1.4,
    GLOW_PLUG_FAILURE = 1.0,
    ALTERNATOR = 1.1,
    STARTER_FAILURE = 1.1,
    TURBOCHARGER_MALFUNCTION = 1.1,
    OIL_PUMP_MALFUNCTION = 1.3,
    PISTONS = 1.4,
    PISTON_RINGS = 1.4,
    CYLINDER_LINERS = 1.4,
    INLET_VALVES = 1.4,
    EXHAUST_VALVES = 1.4,
    VALVE_GUIDES_SEALS = 1.4,
    CYLINDER_HEAD = 1.4,
    CYLINDER_HEAD_GASKET = 1.4,
    MAIN_BEARINGS = 1.4,
    CONROD_BEARINGS = 1.4,
    MANUAL_TRANSMISSION_CLUTCH_WEAR = 1.00,
    MANUAL_TRANSMISSION_SYNCHRONIZER_MALFUNCTION = 1.3,
    TRANSMISSION_PUMP_MALFUNCTION = 1.1,
    HYDROSTATIC_UNIT_MALFUNCTION = 1.2,
    CVT_HYDRAULIC_CONTROL_VALVE_MALFUNCTION = 1.1,
    CVT_ADDON_MALFUNCTION = 1.4,
    TRANSMISSION_OIL_COOLER_MALFUNCTION = 1.3,
    TRANSMISSION_OIL_LEAK = 0.8,
    HYDRAULIC_PUMP_MALFUNCTION = 1.1,
    HYDRAULIC_CYLINDER_INTERNAL_LEAK = 0.6,
    HYDRAULIC_HOSE_EXTERNAL_LEAK = 0.8,
    HYDRAULIC_OIL_COOLER_MALFUNCTION = 0.9,
    HYDRAULIC_SPOOL_VALVE_MALFUNCTION = 1.1,
    BRAKE_DISC_WEAR = 0.9,
    BRAKE_CONTROL_FAILURE = 0.9,
    TRAILER_BRAKE_VALVE_FAILURE = 0.9,
    PARK_BRAKE_MALFUNCTION = 0.9,
    WHEEL_HUB_BEARING_WEAR = 1.2,
    STEERING_LINKAGE_WEAR = 1.2,
    STEERING_KNUCKLE_PIVOT_WEAR = 1.2,
    STEERING_ORBITROL_MALFUNCTION = 1.2,
    STEERING_CYLINDER_LEAK = 1.2,
    LOADER_PIVOT_PIN_WEAR = 1.2,
    TRACK_ROLLER_BEARING_WEAR = 1.2,
    TRACK_TENSIONER_MALFUNCTION = 1.3,
    THERMOSTAT_MALFUNCTION = 1.4,
    COOLANT_HOSE_FAILURE = 0.6,
    EXPANSION_TANK_FAILURE = 0.6,
    ACCESSORY_BELT_FAILURE = 1.1,
    FAN_BLADE_FAILURE = 0.9,
    ELECTRIC_COOLING_FAN_FAILURE = 1.2,
    FAN_CLUTCH_FAILURE = 0.9,
    FUEL_PUMP_MALFUNCTION = 1.1,
    FUEL_INJECTOR_MALFUNCTION = 1.1,
    HIGH_PRESSURE_PUMP_MALFUNCTION = 1.1,
    FUEL_LINE_AIR_LEAK = 0.8,
    MECHANICAL_INJECTION_PUMP_MALFUNCTION = 1.1,
    FUEL_METERING_VALVE_FAILURE = 1.1,
    RAIL_PRESSURE_SENSOR_FAILURE = 1.1,
    GAS_PRESSURE_REGULATOR_FAILURE = 1.1,
    GAS_SHUTOFF_SOLENOID_FAILURE = 1.1,
    GAS_FILTER_CLOGGING = 0.35,
    GAS_LINE_LEAK = 0.8,
    GAS_INJECTOR_MALFUNCTION = 1.1,
    ADBLUE_PUMP_FAILURE = 1.0,
    ADBLUE_DOSER_FAILURE = 1.0,
    NOX_SENSOR_FAILURE = 1.0,
    PARTICULATE_FILTER_FAILURE = 1.0,
    PTO_CLUTCH_WEAR = 1.00,
    PTO_OUTPUT_BEARING_WEAR = 1.20,
    PTO_ENGAGEMENT_SOLENOID_FAILURE = 1.10,
    PTO_OUTPUT_SHAFT_FAILURE = 1.20,
    PTO_ENGAGEMENT_SWITCH_FAILURE = 1.10,
    PTO_SPEED_SENSOR_FAILURE = 1.00,
    PTO_BRAKE_FAILURE = 0.90,
    ELECTRIC_MOTOR_BEARING_WEAR = 1.20,
    ELECTRIC_MOTOR_WINDING_FAULT = 1.30,
    MOTOR_POSITION_SENSOR_FAULT = 1.00,
    INVERTER_MALFUNCTION = 1.00,
    DCDC_CONVERTER_FAILURE = 1.10,
    ONBOARD_CHARGER_FAILURE = 1.10,
    HV_INSULATION_LOSS = 0.90,
    TRACTION_BATTERY_CELL_FAULT = 1.40,
    HV_CONTACTOR_FAILURE = 1.10,
    COOLANT_PUMP_FAILURE = 1.20,
    THERMAL_WATER_PUMP = 1.2,
    RADIATOR_CORE = 0.6,
    REDUCER_GEAR_WEAR = 1.20,
    GEARBOX_BEARING_FAILURE = 1.3,
    POWERSHIFT_CLUTCH_FAILURE = 1.1,
    POWERSHIFT_REVERSER_FAILURE = 1.1,
    TRANSMISSION_CONTROL_FAILURE = 1.1,
    REAR_BEVEL_GEAR_FAILURE = 1.20,
    FINAL_DRIVE_FAILURE = 1.20,
    DIFFERENTIAL_FAILURE = 1.20,
    DIFF_LOCK_CONTROL_FAILURE = 1.1,
    FOUR_WD_CONTROL_FAILURE = 1.1,
    LIFT_VALVE_FAILURE = 1.1,
    LIFT_POSITION_SENSOR_FAILURE = 0.6,
    HYDRAULIC_QUICK_COUPLER_FAILURE = 0.8,
    FRONT_AXLE_SHAFT_WEAR = 1.2,
    AXLE_BEARING_WEAR = 1.2,
    TRANSMISSION_SENSOR_FAILURE = 1.0,
    CVT_SENSOR_FAILURE = 1.0,
    LOADER_CONTROL_FAILURE = 1.1,
    CAB_SUSPENSION_DAMPER_LEAK = 1.2,
    RAIL_PRESSURE_LIMITER_FAILURE = 1.1,
    PTO_OUTPUT_SEAL_LEAK = 0.8,
    FRONT_PTO_CLUTCH_FAILURE = 1.0,
}

---Tells whether the vehicle has hydraulics at all
local function isHydraulicBreakdownApplicable(vehicle)
    return RMS_Utils.hasHydraulicCapability(vehicle)
end

---Tells whether the vehicle can lift with its hydraulics
local function isHydraulicLiftBreakdownApplicable(vehicle)
    return isHydraulicBreakdownApplicable(vehicle) and RMS_Utils.hasHydraulicLiftCapability(vehicle)
end

---Tells whether the vehicle carries hydraulic hoses
local function isHydraulicHoseBreakdownApplicable(vehicle)
    return isHydraulicBreakdownApplicable(vehicle) and RMS_Utils.hasHydraulicHoseCapability(vehicle)
end

---Tells whether the vehicle has a hydraulic function the player can drive
local function isHydraulicActuatorBreakdownApplicable(vehicle)
    return isHydraulicBreakdownApplicable(vehicle) and RMS_Utils.hasHydraulicControllableTargetCapability(vehicle)
end

---Tells whether the vehicle has a PTO output
local function isPtoBreakdownApplicable(vehicle)
    return RMS_Utils.hasPtoOutputCapability(vehicle)
end

---Tells whether the vehicle drives its wheels through a reducer
local function isReducerBreakdownApplicable(vehicle)
    return getIsElectricVehicle(vehicle) and vehicle:getMotor().minForwardGearRatio ~= nil
end

---Tells whether the vehicle runs a variator
local function isVariatorBreakdownApplicable(vehicle)
    return not hasCVTAddon(vehicle) and RMS_Utils.hasCVTTransmission(vehicle)
end

RMS_Breakdowns.BreakdownRegistry = {


    COLD_ENGINE = {
        system = systems.ENGINE,
        part = parts.ENGINE,
        isSelectable = false,
        isApplicable = function(vehicle)
            return not getIsElectricVehicle(vehicle)
        end,
        isCanProgress = function(vehicle)
            return false
        end,
        stages = {
            {
                severity = "rms_breakdowns_severity_permanent",
                description = "",
                detectionChance = 0.0,
                progressMultiplier = 0.0,
                repairPrice = 0.0,
                effects = {
                    {
                        id = "ENGINE_HARD_START_MODIFIER",
                        value = 0,
                        aggregation = "max",
                        extraData = {timer = 0, status = 'IDLE'}
                    }
                },
                indicators = {}
            }
        }
    },

    DEAD_BATTERY = {
        system = systems.ELECTRICAL,
        part = parts.BATTERY,
        isSelectable = false,
        isApplicable = function(vehicle)
            return true
        end,
        isCanProgress = function(vehicle)
            return false
        end,
        stages = {
            {
                severity = "rms_breakdowns_severity_permanent",
                description = "",
                detectionChance = 0.0,
                progressMultiplier = 0.0,
                repairPrice = 0.0,
                effects = {
                        {
                            id = "ENGINE_FAILURE",
                            value = 1.0,
                            extraData = {
                                status = 'IDLE',
                                starter = false,
                                message = "rms_breakdowns_dead_battery_message",
                                reason = "BREAKDOWN",
                                disableAi = true
                            },
                            aggregation = "boolean_or"
                        },
                    { id = "LIGHTS_FAILURE", value = 1.0, aggregation = "boolean_or" }
                },
                indicators = {
                    { id = db.BATTERY, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            }
        }
    },

    VOLTAGE_SAG = {
        system = systems.ELECTRICAL,
        part = parts.VEHICLE,
        isSelectable = false,
        isApplicable = function(vehicle)
            return true
        end,
        isCanProgress = function(vehicle)
            return false
        end,
        stages = {
            {
                severity = "rms_breakdowns_severity_permanent",
                description = "",
                detectionChance = 0.0,
                progressMultiplier = 0.0,
                repairPrice = 0.0,
                effects = {
                    { id = "LIGHTS_FLICKER_CHANCE", value = 0.1, extraData = {timer = 0, status = 'IDLE', duration = 200, maskBackup = 0}, aggregation = "min"},
                    { id = "PTO_AUTO_DISENGAGE_CHANCE", value = 1, aggregation = "min", extraData = {status = 'IDLE'} },
                    { id = "ENGINE_STALLS_CHANCE", value = 10.0, aggregation = "min" },
                    { id = "ENGINE_HARD_START_MODIFIER", value = 3, aggregation = "max", extraData = { timer = 0, status = 'IDLE', message = "rms_breakdowns_voltage_sag_message"}},
                },
                indicators = {
                    { id = db.BATTERY, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            }
        }
    },

    COLD_TRACTION_BATTERY = {
        system = systems.FUEL,
        part = parts.TRACTION_BATTERY,
        isSelectable = false,
        isApplicable = function(vehicle)
            return getIsElectricVehicle(vehicle)
        end,
        isCanProgress = function(vehicle)
            return false
        end,
        stages = {
            {
                severity = "rms_breakdowns_severity_reduce_power",
                description = "",
                detectionChance = 0.0,
                progressMultiplier = 0.0,
                repairPrice = 0.0,
                effects = {
                    { id = "FUEL_CONSUMPTION_MODIFIER", value = 0.10, aggregation = "sum" },
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.05, aggregation = "sum" }
                },
                indicators = {}
            },
            {
                severity = "rms_breakdowns_severity_reduce_power",
                description = "",
                detectionChance = 0.0,
                progressMultiplier = 0.0,
                repairPrice = 0.0,
                effects = {
                    { id = "FUEL_CONSUMPTION_MODIFIER", value = 0.25, aggregation = "sum", extraData = { message = "rms_breakdowns_cold_traction_battery_message" } },
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.10, aggregation = "sum" }
                },
                indicators = {
                    { id = db.TRACTION_BATTERY, color = color.COOL, switchOn = true, switchOff = false },
                    { id = db.LIMITED_POWER, color = color.WARNING, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_reduce_power",
                description = "",
                detectionChance = 0.0,
                progressMultiplier = 0.0,
                repairPrice = 0.0,
                effects = {
                    { id = "FUEL_CONSUMPTION_MODIFIER", value = 0.50, aggregation = "sum", extraData = { message = "rms_breakdowns_cold_traction_battery_message" } },
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.25, aggregation = "sum" }
                },
                indicators = {
                    { id = db.TRACTION_BATTERY, color = color.COOL, switchOn = true, switchOff = false },
                    { id = db.LIMITED_POWER, color = color.WARNING, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_reduce_power",
                description = "",
                detectionChance = 0.0,
                progressMultiplier = 0.0,
                repairPrice = 0.0,
                effects = {
                    { id = "FUEL_CONSUMPTION_MODIFIER", value = 1.00, aggregation = "sum", extraData = { message = "rms_breakdowns_cold_traction_battery_message" } },
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.40, aggregation = "sum" }
                },
                indicators = {
                    { id = db.TRACTION_BATTERY, color = color.COOL, switchOn = true, switchOff = false },
                    { id = db.LIMITED_POWER, color = color.WARNING, switchOn = true, switchOff = false }
                }
            }
        }
    },

    AIRFILTER_CLOGGING = {
        system = systems.ENGINE,
        part = parts.VEHICLE,
        isSelectable = false,
        isApplicable = function(vehicle)
            local spec = vehicle.spec_RealisticMechanicalSystems
            if spec == nil then return end
            if spec.isVehicleNeedBlowOut then
                return true
            end
            return false
        end,
        isCanProgress = function(vehicle)
            return false
        end,
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "",
                detectionChance = 0.0,
                progressMultiplier = 0.0,
                repairPrice = 0.0,
                effects = {
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.03, aggregation = "sum"},
                    { id = "FUEL_CONSUMPTION_MODIFIER", value = 0.06, aggregation = "sum" },

                },
                indicators = {
                }
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "",
                detectionChance = 0.0,
                progressMultiplier = 0.0,
                repairPrice = 0.0,
                effects = {
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.06, aggregation = "sum"},
                    { id = "FUEL_CONSUMPTION_MODIFIER", value = 0.12, aggregation = "sum" },

                },
                indicators = {
                }
            },
                        {
                severity = "rms_breakdowns_severity_major",
                description = "",
                detectionChance = 0.0,
                progressMultiplier = 0.0,
                repairPrice = 0.0,
                effects = {
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.10, aggregation = "sum"},
                    { id = "FUEL_CONSUMPTION_MODIFIER", value = 0.18, aggregation = "sum" },
                    { id = "ENGINE_HEAT_MODIFIER", value = 0.05, aggregation = "sum" }
                },
                indicators = {
                }
            }
        }
    },

    STRESS_OVERLOAD = {
        part = parts.VEHICLE,
        isSelectable = false,
        isApplicable = function(vehicle)
            return true
        end,
        isCanProgress = function(vehicle)
            return false
        end,
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "",
                detectionChance = 0.0,
                progressMultiplier = 0.0,
                repairPrice = 0.0,
                effects = {},
                indicators = {
                    { id = db.WARNING, color = color.WARNING, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_critical",
                description = "",
                detectionChance = 0.0,
                progressMultiplier = 0.0,
                repairPrice = 0.0,
                effects = {
                        {
                            id = "EMPTY_EFFECT",
                            value = 1.0,
                            aggregation = "boolean_or",
                            extraData = {
                                reason = "BREAKDOWN"
                            }
                        }
                },
                indicators = {
                    { id = db.WARNING, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            },
        }
    },

    MAINTENANCE_WITH_POOR_QUALITY_CONSUMABLES = {
        isSelectable = false,
        part = parts.CONSUMABLES,
        isApplicable = function(vehicle)
            return true
        end,
        isCanProgress = function(vehicle)
            return true
        end,
        stages = {
            {
                severity = "",
                description = "",
                detectionChance = 0.0,
                progressMultiplier = 5.0,
                repairPrice = 0.0,
                effects = {
                    { id = "CONDITION_WEAR_MODIFIER", value = 0.33, aggregation = 'sum' },
                    { id = "SERVICE_WEAR_MODIFIER", value = 0.33, aggregation = 'sum' }
                }
            },
            {
                severity = "",
                description = "",
                detectionChance = 0.0,
                progressMultiplier = 0.0,
                repairPrice = 0.0,
                effects = {
                    { id = "SELF_DISAPPEARING_BREAKDOWN_EFFECT", value = 1.0, aggregation = 'boolean_or', extraData = {breakdownId = "MAINTENANCE_WITH_POOR_QUALITY_CONSUMABLES"} }
                }
            },   
        },
    },

    ENGINE_THERMAL_PROTECTION = {
        isSelectable = false,
        system = systems.ENGINE,
        part = parts.VEHICLE,
        isApplicable = function(vehicle)
            return RMS_Thermal.getUsesEngineProtection(vehicle)
        end,
        isCanProgress = function(vehicle) return false end,
        stages = {
            {
                severity = "rms_breakdowns_severity_reduce_power",
                description = "rms_breakdowns_overheat_protection_stage1_description",
                detectionChance = 0.0, progressMultiplier = 0.0, repairPrice = 0.0,
                effects = {
                    { id = "ENGINE_THERMAL_TORQUE_LIMIT", value = 0.8, aggregation = "min",
                        extraData = { reason = "THERMAL_PROTECTION", message = "rms_breakdowns_overheat_protection_stage1_message" } }
                },
                indicators = {
                    { id = db.WARNING, color = color.WARNING, switchOn = true, switchOff = false },
                    { id = db.LIMITED_POWER, color = color.WARNING, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_reduce_power",
                description = "rms_breakdowns_overheat_protection_stage2_description",
                detectionChance = 0.0, progressMultiplier = 0.0, repairPrice = 0.0,
                effects = {
                    { id = "ENGINE_THERMAL_TORQUE_LIMIT", value = 0.5, aggregation = "min",
                        extraData = { reason = "THERMAL_PROTECTION", message = "rms_breakdowns_overheat_protection_stage2_message" } }
                },
                indicators = {
                    { id = db.WARNING, color = color.CRITICAL, switchOn = true, switchOff = false },
                    { id = db.LIMITED_POWER, color = color.WARNING, switchOn = true, switchOff = false }
                }
            }
        }
    },

    OVERHEAT_PROTECTION = {
        isSelectable = false,
        system = systems.ENGINE,
        part = parts.VEHICLE,
        isApplicable = function(vehicle)
            return true
        end,
        isCanProgress = function(vehicle)
            return false
        end,
        stages = {
            {
                severity = "rms_breakdowns_severity_reduce_power",
                description = "rms_breakdowns_overheat_protection_stage1_description",
                detectionChance = 0.0,
                progressMultiplier = 0.0,
                repairPrice = 0.0,
                effects = {
                        {
                            id = "ENGINE_LIMP_EFFECT",
                            value = -0.2,
                            aggregation = "min",
                            extraData = {
                                reason = "OVERHEAT",
                                message = "rms_breakdowns_overheat_protection_stage1_message",
                                disableAi = true
                            }
                        },
                },
                indicators = {
                    {  
                        id = db.WARNING,
                        color = color.CRITICAL,
                        switchOn = true,
                        switchOff = false
                    },
                    { id = db.LIMITED_POWER, color = color.WARNING, switchOn = true, switchOff = false }
                }
            },            
            {
                severity = "rms_breakdowns_severity_reduce_power",
                description = "rms_breakdowns_overheat_protection_stage2_description",
                detectionChance = 0.0,
                progressMultiplier = 0.0,
                repairPrice = 0.0,
                effects = {
                        {
                            id = "ENGINE_LIMP_EFFECT",
                            value = -0.5,
                            aggregation = "min",
                            extraData = {
                                reason = "OVERHEAT",
                                message = "rms_breakdowns_overheat_protection_stage2_message",
                                disableAi = true
                            }
                        },
                },
                indicators = {
                    {  
                        id = db.WARNING,
                        color = color.CRITICAL,
                        switchOn = true,
                        switchOff = false
                    },
                    { id = db.LIMITED_POWER, color = color.WARNING, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_reduce_power",
                description = "rms_breakdowns_overheat_protection_stage3_description",
                detectionChance = 0.0,
                progressMultiplier = 0.0,
                repairPrice = 0.0,
                effects = {
                        {
                            id = "ENGINE_LIMP_EFFECT",
                            value = -0.8,
                            aggregation = "min",
                            extraData = {
                                reason = "OVERHEAT",
                                message = "rms_breakdowns_overheat_protection_stage3_message",
                                disableAi = true
                            }
                        },
                },
                indicators = {
                    {  
                        id = db.WARNING,
                        color = color.CRITICAL,
                        switchOn = true,
                        switchOff = false
                    },
                    { id = db.LIMITED_POWER, color = color.WARNING, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_shutdown",
                description = "rms_breakdowns_overheat_protection_stage4_description",
                detectionChance = 0.0,
                progressMultiplier = 0.0,
                repairPrice = 0.0,
                effects = {
                        {
                            id = "ENGINE_FAILURE",
                            value = 1.0,
                            aggregation = "boolean_or",
                            extraData = {
                                status = 'IDLE',
                                starter = false,
                                message = "rms_breakdowns_overheat_protection_stage4_message",
                                reason = "OVERHEAT",
                                disableAi = true
                            }
                        },
                },
                indicators = {
                    {  
                        id = db.WARNING,
                        color = color.CRITICAL,
                        switchOn = true,
                        switchOff = false
                    },
                    { id = db.LIMITED_POWER, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            }
        }
    },

    ENGINE_JAM = {
        isSelectable = false,
        system = systems.ENGINE,
        part = parts.ENGINE,
        isApplicable = function(vehicle)
            return not getIsElectricVehicle(vehicle)
        end,
        stages = {
            {
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_engine_jam_stage1_description",
                detectionChance = 1.0,
                progressMultiplier = 0.0,
                repairPrice = stagePartPrices.ENGINE_JAM[1],
                effects = {
                        {
                            id = "ENGINE_FAILURE",
                            value = 1.0,
                            aggregation = "boolean_or",
                            extraData = {
                                status = 'IDLE',
                                starter = false,
                                reason = "OVERHEAT",
                                disableAi = true
                            }
                        },
                },
                indicators = {
                    {  
                        id = db.ENGINE,
                        color = color.CRITICAL,
                        switchOn = true,
                        switchOff = false
                    }
                }
            }
        }
    },
    


    -- electrical
    ECU_MALFUNCTION = {
        isSelectable = true,
        system = systems.ELECTRICAL,
        part = parts.ECU,
        isApplicable = function(vehicle)
            return RMS_Utils.getUsesEngineECUProfile(vehicle)
        end,
        causes = { primary = {"ohf"}, secondary = {"vf"} },
        component = "SOLID_STATE_CONTROLLER",
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_ecu_malfunction_stage1_description",
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.ECU_MALFUNCTION,
                repairPrice = stagePartPrices.ECU_MALFUNCTION[1],
                effects = {
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.10, aggregation = "sum"},
                    { id = "EXHAUST_SOOT", value = 0.25, aggregation = "max" },
                },
                indicators = {
                    {  
                        id = db.ENGINE,
                        color = color.WARNING,
                        switchOn = function(vehicle)
                            if vehicle.spec_motorized and vehicle:getIsMotorStarted() and vehicle:getMotorLoadPercentage() > 0.95 then
                                return true
                            end
                            return false
                        end,
                        switchOff = function(vehicle)
                            if vehicle.spec_motorized and vehicle:getIsMotorStarted() and vehicle:getMotorLoadPercentage() <= 0.50 then
                                return true
                            end
                            return false
                        end,
                    }
                }
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_ecu_malfunction_stage2_description",
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.ECU_MALFUNCTION,
                repairPrice = stagePartPrices.ECU_MALFUNCTION[2],
                effects = {
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.20, aggregation = "sum" },
                    { id = "FUEL_CONSUMPTION_MODIFIER", value = 0.2, aggregation = "sum" },
                    { id = "EXHAUST_SOOT", value = 0.45, aggregation = "max" }
                },
                indicators = {
                    { id = db.ENGINE, color = color.WARNING, switchOn = true, switchOff = false }
                }
            },
            { 
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_ecu_malfunction_stage3_description",
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.ECU_MALFUNCTION,
                repairPrice = stagePartPrices.ECU_MALFUNCTION[3],
                effects = { 
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.35, aggregation = "sum" },
                    { id = "FUEL_CONSUMPTION_MODIFIER", value = 0.5, aggregation = "sum" },
                    { id = "ENGINE_STALLS_CHANCE", value = 10.0, aggregation = "min" },
                    { id = "ENGINE_HARD_START_MODIFIER", value = 2, aggregation = "max", extraData = { timer = 0, status = 'IDLE'}},
                    { id = "EXHAUST_SOOT", value = 0.80, aggregation = "max" }
                },
                indicators = {
                    { id = db.ENGINE, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            },
            { 
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_ecu_malfunction_stage4_description",
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = stagePartPrices.ECU_MALFUNCTION[4],
                effects = { 
                        {
                            id = "ENGINE_FAILURE",
                            value = 1.0,
                            aggregation = "boolean_or",
                            extraData = {
                                status = 'IDLE',
                                starter = true,
                                reason = "BREAKDOWN",
                                disableAi = true
                            }
                        }
                },
                indicators = {
                    { id = db.ENGINE, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            }
        }
    },

    POWER_CABLE_CONNECTION_FAILURE = {
        isSelectable = true,
        system = systems.ELECTRICAL,
        part = parts.POWER_CABLES_AND_GROUNDS,
        isApplicable = function(vehicle)
            local spec = vehicle.spec_RealisticMechanicalSystems
            return spec.year >= 2000 and vehicle.spec_lights ~= nil
        end,
        causes = { primary = {"wef", "vf"}, secondary = {} },
        component = "ELECTRO_MECHANICAL",
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_power_cable_connection_failure_stage1_description",
                electricDescription = "rms_breakdowns_power_cable_connection_failure_electric_stage1_description",
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.POWER_CABLE_CONNECTION_FAILURE,
                repairPrice = stagePartPrices.POWER_CABLE_CONNECTION_FAILURE[1],
                effects = {
                    { id = "LIGHTS_FLICKER_CHANCE", value = 1.0, extraData = {timer = 0, status = 'IDLE', duration = 200, maskBackup = 0}, aggregation = "min"},
                    { id = "ENGINE_HARD_START_MODIFIER", value = 3, extraData = { timer = 0, status = 'IDLE'}, aggregation = "max"},
                    { id = "ELECTRICAL_CONTACT_RESISTANCE_EFFECT", value = 1, aggregation = "max" },
                    { id = "ELECTRICAL_LEAKAGE_EFFECT", value = 1, aggregation = "sum" }
                }
            },
            {
                severity = "rms_breakdowns_severity_moderate", 
                description = "rms_breakdowns_power_cable_connection_failure_stage2_description",
                electricDescription = "rms_breakdowns_power_cable_connection_failure_electric_stage2_description",
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.POWER_CABLE_CONNECTION_FAILURE,
                repairPrice = stagePartPrices.POWER_CABLE_CONNECTION_FAILURE[2],
                effects = {
                    { id = "LIGHTS_FLICKER_CHANCE", value = 0.33, extraData = {timer = 0, status = 'IDLE', duration = 300, maskBackup = 0}, aggregation = "min" },
                    { id = "ENGINE_STALLS_CHANCE", value = 30.0, aggregation = "min" },
                    { id = "ENGINE_HARD_START_MODIFIER", value = 5, extraData = { timer = 0, status = 'IDLE'}, aggregation = "max"},
                    { id = "ELECTRICAL_CONTACT_RESISTANCE_EFFECT", value = 2, aggregation = "max" },
                    { id = "ELECTRICAL_LEAKAGE_EFFECT", value = 2, aggregation = "sum" }
                },
                inspection = {
                    { additional = "rms_inspection_hint_power_cable_connection_failure_stage2" },
                },
                indicators = {
                    { id = db.BATTERY, color = color.WARNING, switchOn = true, switchOff = false }
                }
            },
            { 
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_power_cable_connection_failure_stage3_description",
                electricDescription = "rms_breakdowns_power_cable_connection_failure_electric_stage3_description",
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.POWER_CABLE_CONNECTION_FAILURE,
                repairPrice = stagePartPrices.POWER_CABLE_CONNECTION_FAILURE[3],
                effects = { 
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.10, aggregation = "sum"},
                    { id = "LIGHTS_FAILURE", value = 1.0, aggregation = "boolean_or" },
                    { id = "ENGINE_STALLS_CHANCE", value = 20.0, aggregation = "min" },
                    { id = "ENGINE_HARD_START_MODIFIER", value = 8, extraData = { timer = 0, status = 'IDLE'}, aggregation = "max"},
                    { id = "ELECTRICAL_CONTACT_RESISTANCE_EFFECT", value = 4, aggregation = "max" },
                    { id = "ELECTRICAL_LEAKAGE_EFFECT", value = 4, aggregation = "sum" }
                },
                inspection = {
                    { additional = "rms_inspection_hint_power_cable_connection_failure_stage3" },
                },
                indicators = {
                    { id = db.BATTERY, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            },
            { 
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_power_cable_connection_failure_stage4_description",
                electricDescription = "rms_breakdowns_power_cable_connection_failure_electric_stage4_description",
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = stagePartPrices.POWER_CABLE_CONNECTION_FAILURE[4],
                effects = {
                    { id = "LIGHTS_FAILURE", value = 1.0, aggregation = "boolean_or" },
                    { id = "ELECTRICAL_LEAKAGE_EFFECT", value = 8, aggregation = "sum" },
                        {
                            id = "ENGINE_FAILURE",
                            value = 1.0,
                            extraData = {
                                status = 'IDLE',
                                starter = false,
                                reason = "BREAKDOWN",
                                disableAi = true
                            },
                            aggregation = "boolean_or"
                        }
                },
                inspection = {
                    { additional = "rms_inspection_hint_power_cable_connection_failure_stage4" },
                },
                indicators = {
                    { id = db.BATTERY, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            }
        }
    },

    STARTER_RELAY_FAILURE = {
        isSelectable = true,
        system = systems.ELECTRICAL,
        part = parts.STARTER_RELAY,
        isApplicable = function(vehicle)
            return not getIsElectricVehicle(vehicle)
        end,
        causes = { primary = {"crf"}, secondary = {} },
        component = "ELECTRO_MECHANICAL",
        stages = {
            {
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_starter_relay_failure_stage1_description",
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = stagePartPrices.STARTER_RELAY_FAILURE[1],
                effects = {
                    { id = "STARTER_HEALTH_MODIFIER", value = -1.0, aggregation = "min", extraData = { disableAi = true } },
                    { id = "ENGINE_HARD_START_MODIFIER", value = 1, aggregation = "max", extraData = { timer = 0, status = "IDLE" } }
                },
                indicators = {
                    { id = db.ENGINE, color = color.WARNING, switchOn = true, switchOff = false }
                }
            }
        }
    },

    PREHEAT_RELAY_FAILURE = {
        isSelectable = true,
        system = systems.ELECTRICAL,
        part = parts.PREHEAT_RELAY,
        isApplicable = function(vehicle)
            return RMS_Preheat.isDieselVehicle(vehicle)
        end,
        causes = { primary = {"crf"}, secondary = {} },
        component = "ELECTRO_MECHANICAL",
        stages = {
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_preheat_relay_failure_stage1_description",
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = stagePartPrices.PREHEAT_RELAY_FAILURE[1],
                effects = {
                    { id = "GLOW_PLUG_FAILURE", value = 4, aggregation = "max" },
                    { id = "GLOW_PLUG_HARD_START_MODIFIER", value = 8, aggregation = "max", extraData = { timer = 0, status = "IDLE", blockStart = true } },
                    { id = "GLOW_PLUG_COLD_IDLE_EFFECT", value = 0.10, aggregation = "max", extraData = { timer = 0, period = 1500 } }
                },
                indicators = { glowPlugFailureIndicator }
            }
        }
    },

    LOW_BEAM_FAILURE = {
        isSelectable = true,
        system = systems.ELECTRICAL,
        part = parts.LOW_BEAM_BULBS,
        isApplicable = function(vehicle)
            return vehicle.spec_RealisticMechanicalSystems.year < RMS_Config.ELECTRICAL.LED_YEARS.LOW_BEAM_FAILURE
                and RMS_Breakdowns.getCarriesLightCircuit(vehicle, "LOW_BEAM_FAILURE")
        end,
        causes = { primary = {}, secondary = {} },
        component = "HALOGEN_H7",
        wearsWhile = function(vehicle)
            return RMS_Breakdowns.getIsLightCircuitLit(vehicle, "LOW_BEAM_FAILURE")
        end,
        stages = {
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_low_beam_failure_stage1_description",
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = stagePartPrices.LOW_BEAM_FAILURE[1],
                effects = {
                    { id = "LOW_BEAM_FAILURE", value = 1, aggregation = "boolean_or" }
                }
            }
        }
    },

    HIGH_BEAM_FAILURE = {
        isSelectable = true,
        system = systems.ELECTRICAL,
        part = parts.HIGH_BEAM_BULBS,
        isApplicable = function(vehicle)
            return vehicle.spec_RealisticMechanicalSystems.year < RMS_Config.ELECTRICAL.LED_YEARS.HIGH_BEAM_FAILURE
                and RMS_Breakdowns.getCarriesLightCircuit(vehicle, "HIGH_BEAM_FAILURE")
        end,
        causes = { primary = {}, secondary = {} },
        component = "HALOGEN_H7",
        wearsWhile = function(vehicle)
            return RMS_Breakdowns.getIsLightCircuitLit(vehicle, "HIGH_BEAM_FAILURE")
        end,
        stages = {
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_high_beam_failure_stage1_description",
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = stagePartPrices.HIGH_BEAM_FAILURE[1],
                effects = {
                    { id = "HIGH_BEAM_FAILURE", value = 1, aggregation = "boolean_or" }
                }
            }
        }
    },

    FRONT_WORK_LIGHTS_FAILURE = {
        isSelectable = true,
        system = systems.ELECTRICAL,
        part = parts.FRONT_WORK_LIGHT_BULBS,
        isApplicable = function(vehicle)
            return vehicle.spec_RealisticMechanicalSystems.year < RMS_Config.ELECTRICAL.LED_YEARS.FRONT_WORK_LIGHTS_FAILURE
                and RMS_Breakdowns.getCarriesLightCircuit(vehicle, "FRONT_WORK_LIGHTS_FAILURE")
        end,
        causes = { primary = {}, secondary = {} },
        component = "HALOGEN_H3",
        wearsWhile = function(vehicle)
            return RMS_Breakdowns.getIsLightCircuitLit(vehicle, "FRONT_WORK_LIGHTS_FAILURE")
        end,
        stages = {
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_front_work_lights_failure_stage1_description",
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = stagePartPrices.FRONT_WORK_LIGHTS_FAILURE[1],
                effects = {
                    { id = "FRONT_WORK_LIGHTS_FAILURE", value = 1, aggregation = "boolean_or" }
                }
            }
        }
    },

    REAR_WORK_LIGHTS_FAILURE = {
        isSelectable = true,
        system = systems.ELECTRICAL,
        part = parts.REAR_WORK_LIGHT_BULBS,
        isApplicable = function(vehicle)
            return vehicle.spec_RealisticMechanicalSystems.year < RMS_Config.ELECTRICAL.LED_YEARS.REAR_WORK_LIGHTS_FAILURE
                and RMS_Breakdowns.getCarriesLightCircuit(vehicle, "REAR_WORK_LIGHTS_FAILURE")
        end,
        causes = { primary = {}, secondary = {} },
        component = "HALOGEN_H3",
        wearsWhile = function(vehicle)
            return RMS_Breakdowns.getIsLightCircuitLit(vehicle, "REAR_WORK_LIGHTS_FAILURE")
        end,
        stages = {
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_rear_work_lights_failure_stage1_description",
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = stagePartPrices.REAR_WORK_LIGHTS_FAILURE[1],
                effects = {
                    { id = "REAR_WORK_LIGHTS_FAILURE", value = 1, aggregation = "boolean_or" }
                }
            }
        }
    },

    BEACON_LIGHTS_FAILURE = {
        isSelectable = true,
        system = systems.ELECTRICAL,
        part = parts.BEACON_BULB,
        isApplicable = function(vehicle)
            return vehicle.spec_RealisticMechanicalSystems.year < RMS_Config.ELECTRICAL.LED_YEARS.BEACON_LIGHTS_FAILURE
                and RMS_Breakdowns.getCarriesLightCircuit(vehicle, "BEACON_LIGHTS_FAILURE")
        end,
        causes = { primary = {}, secondary = {} },
        component = "HALOGEN_H1",
        wearsWhile = function(vehicle)
            return RMS_Breakdowns.getIsLightCircuitLit(vehicle, "BEACON_LIGHTS_FAILURE")
        end,
        stages = {
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_beacon_lights_failure_stage1_description",
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = stagePartPrices.BEACON_LIGHTS_FAILURE[1],
                effects = {
                    { id = "BEACON_LIGHTS_FAILURE", value = 1, aggregation = "boolean_or" }
                }
            }
        }
    },

    TURN_LIGHTS_FAILURE = {
        isSelectable = true,
        system = systems.ELECTRICAL,
        part = parts.TURN_SIGNAL_BULBS,
        isApplicable = function(vehicle)
            return vehicle.spec_RealisticMechanicalSystems.year < RMS_Config.ELECTRICAL.LED_YEARS.TURN_LIGHTS_FAILURE
                and RMS_Breakdowns.getCarriesLightCircuit(vehicle, "TURN_LIGHTS_FAILURE")
        end,
        causes = { primary = {}, secondary = {} },
        component = "P21W",
        wearsWhile = function(vehicle)
            return RMS_Breakdowns.getIsLightCircuitLit(vehicle, "TURN_LIGHTS_FAILURE")
        end,
        stages = {
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_turn_lights_failure_stage1_description",
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = stagePartPrices.TURN_LIGHTS_FAILURE[1],
                effects = {
                    { id = "TURN_LIGHTS_FAILURE", value = 1, aggregation = "boolean_or" }
                }
            }
        }
    },

    BATTERY_SULFATION = {
        isSelectable = true,
        system = systems.ELECTRICAL,
        part = parts.BATTERY,
        isApplicable = function(vehicle)
            return true
        end,
        causes = { primary = {"crf"}, secondary = {} },
        component = "STARTER_BATTERY",
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_battery_sulfation_stage1_description",
                electricDescription = "rms_breakdowns_battery_sulfation_electric_stage1_description",
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.BATTERY_SULFATION,
                repairPrice = stagePartPrices.BATTERY_SULFATION[1],
                effects = {
                    { id = "BATTERY_HEALTH_MODIFIER", value = -0.3, aggregation = "min"},

                },
            },
            {
                severity = "rms_breakdowns_severity_moderate", 
                description = "rms_breakdowns_battery_sulfation_stage2_description",
                electricDescription = "rms_breakdowns_battery_sulfation_electric_stage2_description",
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.BATTERY_SULFATION,
                repairPrice = stagePartPrices.BATTERY_SULFATION[2],
                effects = {
                    { id = "BATTERY_HEALTH_MODIFIER", value = -0.6, aggregation = "min"},
                    { id = "ENGINE_HARD_START_MODIFIER", value = 3, extraData = { timer = 0, status = 'IDLE'}, aggregation = "max"},
                },
                indicators = {
                    { id = db.BATTERY, color = color.WARNING, switchOn = true, switchOff = false }
                }
            },
            { 
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_battery_sulfation_stage3_description",
                electricDescription = "rms_breakdowns_battery_sulfation_electric_stage3_description",
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.BATTERY_SULFATION,
                repairPrice = stagePartPrices.BATTERY_SULFATION[3],
                effects = { 
                    { id = "BATTERY_HEALTH_MODIFIER", value = -0.75, aggregation = "min"},
                    { id = "ENGINE_HARD_START_MODIFIER", value = 6, extraData = { timer = 0, status = 'IDLE'}, aggregation = "max"},
                },
                indicators = {
                    { id = db.BATTERY, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            },
            { 
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_battery_sulfation_stage4_description",
                electricDescription = "rms_breakdowns_battery_sulfation_electric_stage4_description",
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = stagePartPrices.BATTERY_SULFATION[4],
                effects = { 
                    { id = "BATTERY_HEALTH_MODIFIER", value = -1.0, aggregation = "min"},
                    { id = "ENGINE_HARD_START_MODIFIER", value = 9, extraData = { timer = 0, status = 'IDLE'}, aggregation = "max"},
                },
                indicators = {
                    { id = db.BATTERY, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            }
        }
    },

    GLOW_PLUG_FAILURE = {
        isSelectable = true,
        system = systems.ELECTRICAL,
        part = parts.GLOW_PLUGS,
        isApplicable = function(vehicle)
            return RMS_Preheat.isDieselVehicle(vehicle)
        end,
        causes = { primary = {"crf"}, secondary = {} },
        component = "ELECTRO_MECHANICAL",
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_glow_plug_failure_stage1_description",
                detectionChance = 0.5,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.GLOW_PLUG_FAILURE,
                repairPrice = stagePartPrices.GLOW_PLUG_FAILURE[1],
                effects = {
                    { id = "GLOW_PLUG_FAILURE", value = 1, aggregation = "max" },
                    { id = "GLOW_PLUG_HARD_START_MODIFIER", value = 2, aggregation = "max", extraData = { timer = 0, status = "IDLE" } }
                },
                indicators = {
                    glowPlugFailureIndicator
                }
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_glow_plug_failure_stage2_description",
                detectionChance = 0.75,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.GLOW_PLUG_FAILURE,
                repairPrice = stagePartPrices.GLOW_PLUG_FAILURE[2],
                effects = {
                    { id = "GLOW_PLUG_FAILURE", value = 2, aggregation = "max" },
                    { id = "GLOW_PLUG_HARD_START_MODIFIER", value = 4, aggregation = "max", extraData = { timer = 0, status = "IDLE" } },
                    { id = "GLOW_PLUG_COLD_IDLE_EFFECT", value = 0.05, aggregation = "max", extraData = { timer = 0, period = 1800 } }
                },
                indicators = {
                    glowPlugFailureIndicator
                }
            },
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_glow_plug_failure_stage3_description",
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.GLOW_PLUG_FAILURE,
                repairPrice = stagePartPrices.GLOW_PLUG_FAILURE[3],
                effects = {
                    { id = "GLOW_PLUG_FAILURE", value = 3, aggregation = "max" },
                    { id = "GLOW_PLUG_HARD_START_MODIFIER", value = 8, aggregation = "max", extraData = { timer = 0, status = "IDLE" } },
                    { id = "GLOW_PLUG_COLD_IDLE_EFFECT", value = 0.10, aggregation = "max", extraData = { timer = 0, period = 1500 } }
                },
                indicators = {
                    glowPlugFailureIndicator
                }
            },
            {
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_glow_plug_failure_stage4_description",
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = stagePartPrices.GLOW_PLUG_FAILURE[4],
                effects = {
                    { id = "GLOW_PLUG_FAILURE", value = 4, aggregation = "max" },
                    { id = "GLOW_PLUG_HARD_START_MODIFIER", value = 8, aggregation = "max", extraData = { timer = 0, status = "IDLE", blockStart = true } },
                    { id = "GLOW_PLUG_COLD_IDLE_EFFECT", value = 0.10, aggregation = "max", extraData = { timer = 0, period = 1500 } }
                },
                indicators = {
                    glowPlugFailureIndicator
                }
            }
        }
    },

    ALTERNATOR = {
        isSelectable = true,
        system = systems.ELECTRICAL,
        part = parts.ALTERNATOR,
        isApplicable = function(vehicle)
            return not getIsElectricVehicle(vehicle)
        end,
        causes = { primary = { "ohf", "crf" }, secondary = { "ltf", "vf" } },
        component = "SOLID_STATE_CONTROLLER",
        branches = 2,
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_alternator_branch1_stage1_description",
                branchDescriptions = {
                    "rms_breakdowns_alternator_branch1_stage1_description",
                    "rms_breakdowns_alternator_branch2_stage1_description"
                },
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.ALTERNATOR,
                repairPrice = stagePartPrices.ALTERNATOR[1],
                effects = {
                    { id = "ALTERNATOR_HEALTH_MODIFIER", value = -0.2, aggregation = "min" },
                    { id = "ELECTRICAL_LEAKAGE_EFFECT", value = 1, aggregation = "sum", branch = 2 }
                }
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_alternator_branch1_stage2_description",
                branchDescriptions = {
                    "rms_breakdowns_alternator_branch1_stage2_description",
                    "rms_breakdowns_alternator_branch2_stage2_description"
                },
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.ALTERNATOR,
                repairPrice = stagePartPrices.ALTERNATOR[2],
                effects = {
                    { id = "ALTERNATOR_HEALTH_MODIFIER", value = -0.5, aggregation = "min" },
                    { id = "ELECTRICAL_LEAKAGE_EFFECT", value = 2, aggregation = "sum", branch = 2 }
                },
                indicators = {
                    { id = db.BATTERY, color = color.WARNING, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_alternator_branch1_stage3_description",
                branchDescriptions = {
                    "rms_breakdowns_alternator_branch1_stage3_description",
                    "rms_breakdowns_alternator_branch2_stage3_description"
                },
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.ALTERNATOR,
                repairPrice = stagePartPrices.ALTERNATOR[3],
                effects = {
                    { id = "ALTERNATOR_HEALTH_MODIFIER", value = -0.7, aggregation = "min" },
                    { id = "ELECTRICAL_LEAKAGE_EFFECT", value = 4, aggregation = "sum", branch = 2 }
                },
                indicators = {
                    { id = db.BATTERY, color = color.CRITICAL, switchOn = true, switchOff = false }
                },
                inspection = {
                    { additional = "rms_inspection_hint_alternator_stage3", branch = 1 }
                }
            },
            {
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_alternator_branch1_stage4_description",
                branchDescriptions = {
                    "rms_breakdowns_alternator_branch1_stage4_description",
                    "rms_breakdowns_alternator_branch2_stage4_description"
                },
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = stagePartPrices.ALTERNATOR[4],
                effects = {
                    { id = "ALTERNATOR_HEALTH_MODIFIER", value = -1.0, aggregation = "min" },
                    { id = "ELECTRICAL_LEAKAGE_EFFECT", value = 8, aggregation = "sum", branch = 2 }
                },
                indicators = {
                    { id = db.BATTERY, color = color.CRITICAL, switchOn = true, switchOff = false }
                },
                inspection = {
                    { additional = "rms_inspection_hint_alternator_stage4", branch = 1 }
                }
            }
        }
    },

    STARTER_FAILURE = {
        isSelectable = true,
        system = systems.ELECTRICAL,
        part = parts.STARTER,
        isApplicable = function(vehicle)
            return not getIsElectricVehicle(vehicle)
        end,
        causes = { primary = {"crf"}, secondary = {} },
        component = "DC_MOTOR",
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_starter_failure_stage1_description",
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.STARTER_FAILURE,
                repairPrice = stagePartPrices.STARTER_FAILURE[1],
                effects = {
                    { id = "STARTER_HEALTH_MODIFIER", value = -0.2, aggregation = "min" },
                    { id = "ENGINE_HARD_START_MODIFIER", value = 1, aggregation = "max", extraData = { timer = 0, status = 'IDLE'}}
                }
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_starter_failure_stage2_description",
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.STARTER_FAILURE,
                repairPrice = stagePartPrices.STARTER_FAILURE[2],
                effects = {
                    { id = "STARTER_HEALTH_MODIFIER", value = -0.4, aggregation = "min" },
                    { id = "ENGINE_HARD_START_MODIFIER", value = 1, aggregation = "max", extraData = { timer = 0, status = 'IDLE'}}
                }
            },
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_starter_failure_stage3_description",
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.STARTER_FAILURE,
                repairPrice = stagePartPrices.STARTER_FAILURE[3],
                effects = {
                    { id = "STARTER_HEALTH_MODIFIER", value = -0.55, aggregation = "min" },
                    { id = "ENGINE_HARD_START_MODIFIER", value = 1, aggregation = "max", extraData = { timer = 0, status = 'IDLE'}}
                }
            },
            {
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_starter_failure_stage4_description",
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = stagePartPrices.STARTER_FAILURE[4],
                effects = {
                    { id = "STARTER_HEALTH_MODIFIER", value = -1.0, aggregation = "min", extraData = {disableAi = true} },
                    { id = "ENGINE_HARD_START_MODIFIER", value = 1, aggregation = "max", extraData = { timer = 0, status = 'IDLE'}}
                }
            }
        }
    },

    INVERTER_MALFUNCTION = {
        isSelectable = true,
        system = systems.ELECTRICAL,
        part = parts.INVERTER,
        isApplicable = function(vehicle)
            return getIsElectricVehicle(vehicle)
        end,
        causes = { primary = {"ohf"}, secondary = {"wef", "vf"} },
        component = "SOLID_STATE_CONTROLLER",
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_inverter_malfunction_stage1_description",
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.INVERTER_MALFUNCTION,
                repairPrice = stagePartPrices.INVERTER_MALFUNCTION[1],
                effects = {
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.10, aggregation = "sum" }
                }
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_inverter_malfunction_stage2_description",
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.INVERTER_MALFUNCTION,
                repairPrice = stagePartPrices.INVERTER_MALFUNCTION[2],
                effects = {
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.20, aggregation = "sum" },
                    { id = "FUEL_CONSUMPTION_MODIFIER", value = 0.10, aggregation = "sum" }
                },
                indicators = {
                    { id = db.ENGINE, color = color.WARNING, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_inverter_malfunction_stage3_description",
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.INVERTER_MALFUNCTION,
                repairPrice = stagePartPrices.INVERTER_MALFUNCTION[3],
                effects = {
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.35, aggregation = "sum" },
                    { id = "FUEL_CONSUMPTION_MODIFIER", value = 0.20, aggregation = "sum" },
                    { id = "ENGINE_STALLS_CHANCE", value = 10.0, aggregation = "min" }
                },
                indicators = {
                    { id = db.ENGINE, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_inverter_malfunction_stage4_description",
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = stagePartPrices.INVERTER_MALFUNCTION[4],
                effects = {
                        {
                            id = "ENGINE_FAILURE",
                            value = 1.0,
                            aggregation = "boolean_or",
                            extraData = {
                                status = 'IDLE',
                                starter = false,
                                reason = "BREAKDOWN",
                                disableAi = true
                            }
                        }
                },
                indicators = {
                    { id = db.ENGINE, color = color.CRITICAL, switchOn = true, switchOff = false },
                    { id = db.WARNING, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            }
        }
    },
    DCDC_CONVERTER_FAILURE = {
        isSelectable = true,
        system = systems.ELECTRICAL,
        part = parts.DCDC_CONVERTER,
        isApplicable = function(vehicle)
            return getIsElectricVehicle(vehicle)
        end,
        causes = { primary = {"ohf", "ltf"}, secondary = {"vf"} },
        component = "SOLID_STATE_CONTROLLER",
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_dcdc_converter_failure_stage1_description",
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.DCDC_CONVERTER_FAILURE,
                repairPrice = stagePartPrices.DCDC_CONVERTER_FAILURE[1],
                effects = {
                    { id = "ALTERNATOR_HEALTH_MODIFIER", value = -0.2, aggregation = "min" }
                }
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_dcdc_converter_failure_stage2_description",
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.DCDC_CONVERTER_FAILURE,
                repairPrice = stagePartPrices.DCDC_CONVERTER_FAILURE[2],
                effects = {
                    { id = "ALTERNATOR_HEALTH_MODIFIER", value = -0.5, aggregation = "min" }
                },
                indicators = {
                    { id = db.BATTERY, color = color.WARNING, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_dcdc_converter_failure_stage3_description",
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.DCDC_CONVERTER_FAILURE,
                repairPrice = stagePartPrices.DCDC_CONVERTER_FAILURE[3],
                effects = {
                    { id = "ALTERNATOR_HEALTH_MODIFIER", value = -0.7, aggregation = "min" }
                },
                indicators = {
                    { id = db.BATTERY, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_dcdc_converter_failure_stage4_description",
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = stagePartPrices.DCDC_CONVERTER_FAILURE[4],
                effects = {
                    { id = "ALTERNATOR_HEALTH_MODIFIER", value = -1.0, aggregation = "min" }
                },
                indicators = {
                    { id = db.BATTERY, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            }
        }
    },
    ONBOARD_CHARGER_FAILURE = {
        isSelectable = true,
        system = systems.ELECTRICAL,
        part = parts.ONBOARD_CHARGER,
        isApplicable = function(vehicle)
            return getIsElectricVehicle(vehicle)
        end,
        causes = { primary = {"wef"}, secondary = {} },
        component = "SOLID_STATE_CONTROLLER",
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_onboard_charger_failure_stage1_description",
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.ONBOARD_CHARGER_FAILURE,
                repairPrice = stagePartPrices.ONBOARD_CHARGER_FAILURE[1],
                effects = {
                    { id = "CHARGE_ACCEPTANCE_MODIFIER", value = -0.35, aggregation = "min" }
                }
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_onboard_charger_failure_stage2_description",
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.ONBOARD_CHARGER_FAILURE,
                repairPrice = stagePartPrices.ONBOARD_CHARGER_FAILURE[2],
                effects = {
                    { id = "CHARGE_ACCEPTANCE_MODIFIER", value = -0.65, aggregation = "min" }
                },
                indicators = {
                    { id = db.TRACTION_BATTERY, color = color.WARNING, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_onboard_charger_failure_stage3_description",
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.ONBOARD_CHARGER_FAILURE,
                repairPrice = stagePartPrices.ONBOARD_CHARGER_FAILURE[3],
                effects = {
                    { id = "CHARGE_ACCEPTANCE_MODIFIER", value = -0.90, aggregation = "min" }
                },
                indicators = {
                    { id = db.TRACTION_BATTERY, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_onboard_charger_failure_stage4_description",
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = stagePartPrices.ONBOARD_CHARGER_FAILURE[4],
                effects = {
                    { id = "CHARGE_ACCEPTANCE_MODIFIER", value = -1.0, aggregation = "min" }
                },
                indicators = {
                    { id = db.TRACTION_BATTERY, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            }
        }
    },
    HV_INSULATION_LOSS = {
        isSelectable = true,
        system = systems.ELECTRICAL,
        part = parts.HV_WIRING,
        isApplicable = function(vehicle)
            return getIsElectricVehicle(vehicle)
        end,
        causes = { primary = {"wef"}, secondary = {"vf"} },
        component = "TRANSFORMER",
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_hv_insulation_loss_stage1_description",
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.HV_INSULATION_LOSS,
                repairPrice = stagePartPrices.HV_INSULATION_LOSS[1],
                effects = {},
                indicators = {
                    { id = db.WARNING, color = color.WARNING, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_hv_insulation_loss_stage2_description",
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.HV_INSULATION_LOSS,
                repairPrice = stagePartPrices.HV_INSULATION_LOSS[2],
                effects = {
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.15, aggregation = "sum" }
                },
                indicators = {
                    { id = db.WARNING, color = color.WARNING, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_hv_insulation_loss_stage3_description",
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.HV_INSULATION_LOSS,
                repairPrice = stagePartPrices.HV_INSULATION_LOSS[3],
                effects = {
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.30, aggregation = "sum" },
                    { id = "ENGINE_STALLS_CHANCE", value = 20.0, aggregation = "min" }
                },
                indicators = {
                    { id = db.WARNING, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_hv_insulation_loss_stage4_description",
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = stagePartPrices.HV_INSULATION_LOSS[4],
                effects = {
                        {
                            id = "ENGINE_FAILURE",
                            value = 1.0,
                            aggregation = "boolean_or",
                            extraData = {
                                status = 'IDLE',
                                starter = false,
                                reason = "BREAKDOWN",
                                disableAi = true
                            }
                        }
                },
                indicators = {
                    { id = db.WARNING, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            }
        }
    },
    -- engine
    TURBOCHARGER_MALFUNCTION = {
        isSelectable = true,
        system = systems.ENGINE,
        part = parts.TURBOCHARGER,
        isApplicable = function(vehicle)
            local motor = vehicle:getMotor()
            return not getIsElectricVehicle(vehicle)
                and (motor.peakMotorPower or 0) >= RMS_Config.CORE.TURBO_MIN_POWER_KW
        end,
        causes = { primary = {"hmf", "mlf"}, secondary = {"aicf", "sf", "flf", "cmf"} },
        component = "CENTRIFUGAL_COMPRESSOR",
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_turbocharger_wear_stage1_description",
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.TURBOCHARGER_MALFUNCTION,
                repairPrice = stagePartPrices.TURBOCHARGER_MALFUNCTION[1],
                effects = {
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.10, aggregation = "sum" },
                    { id = "TURBO_WHISTLE_NOISE_EFFECT", value = 0.25, aggregation = "max" },
                    { id = "EXHAUST_SOOT", value = 0.20, aggregation = "max" },
                }
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_turbocharger_wear_stage2_description",
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.TURBOCHARGER_MALFUNCTION,
                repairPrice = stagePartPrices.TURBOCHARGER_MALFUNCTION[2],
                effects = {
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.25, aggregation = "sum" },
                    { id = "FUEL_CONSUMPTION_MODIFIER", value = 0.20, aggregation = "sum" },
                    { id = "TURBO_WHISTLE_NOISE_EFFECT", value = 0.35, aggregation = "max" },
                    { id = "EXHAUST_SOOT", value = 0.40, aggregation = "max" },
                    { id = "EXHAUST_OIL", value = 0.25, aggregation = "max" },
                },
                indicators = {
                    { id = db.ENGINE, color = color.WARNING, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_turbocharger_wear_stage3_description",
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.TURBOCHARGER_MALFUNCTION,
                repairPrice = stagePartPrices.TURBOCHARGER_MALFUNCTION[3],
                effects = {
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.35, aggregation = "sum" },
                    { id = "FUEL_CONSUMPTION_MODIFIER", value = 0.40, aggregation = "sum" },
                    { id = "ENGINE_STALLS_CHANCE", value = 10.0, aggregation = "min" },
                    { id = "TURBO_WHISTLE_NOISE_EFFECT", value = 0.6, aggregation = "max" },
                    { id = "EXHAUST_SOOT", value = 0.65, aggregation = "max" },
                    { id = "EXHAUST_OIL", value = 0.50, aggregation = "max" },
                },
                inspection = {
                    { additional = "rms_inspection_hint_turbocharger_malfunction_stage3" },
                },
                indicators = {
                    { id = db.ENGINE, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_turbocharger_wear_stage4_description",
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = stagePartPrices.TURBOCHARGER_MALFUNCTION[4],
                effects = {
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.50, aggregation = "sum" },
                    { id = "FUEL_CONSUMPTION_MODIFIER", value = 0.60, aggregation = "sum" },
                    { id = "ENGINE_STALLS_CHANCE", value = 10.0, aggregation = "min" },
                    { id = "EXHAUST_SOOT", value = 0.90, aggregation = "max" },
                    { id = "EXHAUST_OIL", value = 0.70, aggregation = "max" },
                },
                inspection = {
                    { additional = "rms_inspection_hint_turbocharger_malfunction_stage4" },
                },
                indicators = {
                    { id = db.ENGINE, color = color.CRITICAL, switchOn = true, switchOff = false },
                    { id = db.WARNING, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            }
        }
    },

    OIL_PUMP_MALFUNCTION = {
        isSelectable = true,
        system = systems.ENGINE,
        part = parts.OIL_PUMP,
        isApplicable = function(vehicle)
            return not getIsElectricVehicle(vehicle)
        end,
        causes = { primary = {"sf"}, secondary = {"flf"} },
        component = "LUBRICATOR_PUMP",
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_oil_pump_malfunction_stage1_description",
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.OIL_PUMP_MALFUNCTION,
                repairPrice = stagePartPrices.OIL_PUMP_MALFUNCTION[1],
                effects = {
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.05, aggregation = "sum" },
                    { id = "ENGINE_KNOCKING_NOISE_EFFECT", value = 0.30, aggregation = "max" },
                    { id = "ENGINE_HEAT_MODIFIER", value = 0.05, aggregation = "sum" },
                    
                },
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_oil_pump_malfunction_stage2_description",
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.OIL_PUMP_MALFUNCTION,
                repairPrice = stagePartPrices.OIL_PUMP_MALFUNCTION[2],
                effects = {
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.25, aggregation = "sum" },
                    { id = "ENGINE_KNOCKING_NOISE_EFFECT", value = 0.5, aggregation = "max" },
                    { id = "ENGINE_HEAT_MODIFIER", value = 0.15, aggregation = "sum" },
                },
                indicators = {
                    { id = db.ENGINE, color = color.WARNING, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_oil_pump_malfunction_stage3_description",
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.OIL_PUMP_MALFUNCTION,
                repairPrice = stagePartPrices.OIL_PUMP_MALFUNCTION[3],
                effects = {
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.45, aggregation = "sum" },
                    { id = "ENGINE_STALLS_CHANCE", value = 10.0, aggregation = "min" },
                    { id = "ENGINE_KNOCKING_NOISE_EFFECT", value = 0.8, aggregation = "max" },
                    { id = "ENGINE_HEAT_MODIFIER", value = 0.35, aggregation = "sum" },
                },
                indicators = {
                    { id = db.ENGINE, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_oil_pump_malfunction_stage4_description",
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = stagePartPrices.OIL_PUMP_MALFUNCTION[4],
                effects = {
                        {
                            id = "ENGINE_FAILURE",
                            value = 1.0,
                            aggregation = "boolean_or",
                            extraData = {
                                status = 'IDLE',
                                starter = true,
                                reason = "BREAKDOWN",
                                disableAi = true
                            }
                        },
                },
                indicators = {
                    { id = db.ENGINE, color = color.CRITICAL, switchOn = true, switchOff = false }
                
                }
            }
        }
    },

    PISTONS = {
        isSelectable = true,
        system = systems.ENGINE,
        part = parts.PISTONS,
        isApplicable = function(vehicle)
            return not getIsElectricVehicle(vehicle)
        end,
        causes = { primary = { "sf", "cmf", "hmf", "flf" }, secondary = { "mlf", "lf" } },
        component = "ENGINE_PISTON",
        branches = 2,
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_pistons_branch1_stage1_description",
                branchDescriptions = {
                    "rms_breakdowns_pistons_branch1_stage1_description",
                    "rms_breakdowns_pistons_branch2_stage1_description"
                },
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.PISTONS,
                repairPrice = stagePartPrices.PISTONS[1],
                effects = {}
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_pistons_branch1_stage2_description",
                branchDescriptions = {
                    "rms_breakdowns_pistons_branch1_stage2_description",
                    "rms_breakdowns_pistons_branch2_stage2_description"
                },
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.PISTONS,
                repairPrice = stagePartPrices.PISTONS[2],
                effects = {
                    { id = "EXHAUST_OIL", value = 0.2, aggregation = "max" },
                    { id = "PISTON_SLAP_NOISE_EFFECT", value = 0.5, aggregation = "max" }
                }
            },
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_pistons_branch1_stage3_description",
                branchDescriptions = {
                    "rms_breakdowns_pistons_branch1_stage3_description",
                    "rms_breakdowns_pistons_branch2_stage3_description"
                },
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.PISTONS,
                repairPrice = stagePartPrices.PISTONS[3],
                effects = {
                    { id = "EXHAUST_OIL", value = 0.4, aggregation = "max" },
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.12, aggregation = "sum" },
                    { id = "ENGINE_HARD_START_MODIFIER", value = 3, aggregation = "max", extraData = { timer = 0, status = "IDLE" } },
                    { id = "PISTON_SLAP_NOISE_EFFECT", value = 0.8, aggregation = "max" }
                },
                indicators = {
                    { id = db.ENGINE, color = color.WARNING, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_pistons_branch1_stage4_description",
                branchDescriptions = {
                    "rms_breakdowns_pistons_branch1_stage4_description",
                    "rms_breakdowns_pistons_branch2_stage4_description"
                },
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = stagePartPrices.PISTONS[4],
                effects = {
                    {
                        id = "ENGINE_FAILURE",
                        value = 1.0,
                        aggregation = "boolean_or",
                        extraData = {
                            status = "IDLE",
                            starter = true,
                            reason = "BREAKDOWN",
                            disableAi = true
                        }
                    },
                },
                indicators = {
                    { id = db.ENGINE, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            }
        }
    },

    PISTON_RINGS = {
        isSelectable = true,
        system = systems.ENGINE,
        part = parts.PISTON_RINGS,
        isApplicable = function(vehicle)
            return not getIsElectricVehicle(vehicle)
        end,
        causes = { primary = { "sf", "cmf", "hmf", "flf" }, secondary = { "mlf", "lf" } },
        component = "ENGINE_PISTON",
        branches = 3,
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_piston_rings_branch1_stage1_description",
                branchDescriptions = {
                    "rms_breakdowns_piston_rings_branch1_stage1_description",
                    "rms_breakdowns_piston_rings_branch2_stage1_description",
                    "rms_breakdowns_piston_rings_branch3_stage1_description"
                },
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.PISTON_RINGS,
                repairPrice = stagePartPrices.PISTON_RINGS[1],
                effects = {}
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_piston_rings_branch1_stage2_description",
                branchDescriptions = {
                    "rms_breakdowns_piston_rings_branch1_stage2_description",
                    "rms_breakdowns_piston_rings_branch2_stage2_description",
                    "rms_breakdowns_piston_rings_branch3_stage2_description"
                },
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.PISTON_RINGS,
                repairPrice = stagePartPrices.PISTON_RINGS[2],
                effects = {
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.04, aggregation = "sum", branch = 1 },
                    { id = "ENGINE_HARD_START_MODIFIER", value = 3, aggregation = "max", extraData = { timer = 0, status = "IDLE" }, branch = 1 },
                    { id = "FUEL_CONSUMPTION_MODIFIER", value = 0.05, aggregation = "sum", branch = 1 },
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.04, aggregation = "sum", branch = 3 },
                    { id = "ENGINE_HARD_START_MODIFIER", value = 3, aggregation = "max", extraData = { timer = 0, status = "IDLE" }, branch = 3 },
                    { id = "FUEL_CONSUMPTION_MODIFIER", value = 0.05, aggregation = "sum", branch = 3 },
                    { id = "EXHAUST_OIL", value = 0.2, aggregation = "max", branch = 2 }
                }
            },
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_piston_rings_branch1_stage3_description",
                branchDescriptions = {
                    "rms_breakdowns_piston_rings_branch1_stage3_description",
                    "rms_breakdowns_piston_rings_branch2_stage3_description",
                    "rms_breakdowns_piston_rings_branch3_stage3_description"
                },
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.PISTON_RINGS,
                repairPrice = stagePartPrices.PISTON_RINGS[3],
                effects = {
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.12, aggregation = "sum", branch = 1 },
                    { id = "ENGINE_HARD_START_MODIFIER", value = 6, aggregation = "max", extraData = { timer = 0, status = "IDLE" }, branch = 1 },
                    { id = "FUEL_CONSUMPTION_MODIFIER", value = 0.1, aggregation = "sum", branch = 1 },
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.12, aggregation = "sum", branch = 3 },
                    { id = "ENGINE_HARD_START_MODIFIER", value = 6, aggregation = "max", extraData = { timer = 0, status = "IDLE" }, branch = 3 },
                    { id = "FUEL_CONSUMPTION_MODIFIER", value = 0.1, aggregation = "sum", branch = 3 },
                    { id = "EXHAUST_OIL", value = 0.4, aggregation = "max", branch = 2 }
                },
                indicators = {
                    { id = db.ENGINE, color = color.WARNING, switchOn = true, switchOff = false, branch = 1 },
                    { id = db.ENGINE, color = color.WARNING, switchOn = true, switchOff = false, branch = 3 }
                }
            },
            {
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_piston_rings_branch1_stage4_description",
                branchDescriptions = {
                    "rms_breakdowns_piston_rings_branch1_stage4_description",
                    "rms_breakdowns_piston_rings_branch2_stage4_description",
                    "rms_breakdowns_piston_rings_branch3_stage4_description"
                },
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = stagePartPrices.PISTON_RINGS[4],
                effects = {
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.25, aggregation = "sum", branch = 1 },
                    { id = "ENGINE_HARD_START_MODIFIER", value = 9, aggregation = "max", extraData = { timer = 0, status = "IDLE" }, branch = 1 },
                    { id = "FUEL_CONSUMPTION_MODIFIER", value = 0.2, aggregation = "sum", branch = 1 },
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.25, aggregation = "sum", branch = 3 },
                    { id = "ENGINE_HARD_START_MODIFIER", value = 9, aggregation = "max", extraData = { timer = 0, status = "IDLE" }, branch = 3 },
                    { id = "FUEL_CONSUMPTION_MODIFIER", value = 0.2, aggregation = "sum", branch = 3 },
                    { id = "EXHAUST_OIL", value = 0.65, aggregation = "max", branch = 2 },
                    { id = "EXHAUST_OIL", value = 0.65, aggregation = "max", branch = 3 }
                },
                indicators = {
                    { id = db.ENGINE, color = color.CRITICAL, switchOn = true, switchOff = false, branch = 1 },
                    { id = db.ENGINE, color = color.CRITICAL, switchOn = true, switchOff = false, branch = 3 }
                }
            }
        }
    },

    CYLINDER_LINERS = {
        isSelectable = true,
        system = systems.ENGINE,
        part = parts.CYLINDER_LINERS,
        isApplicable = function(vehicle)
            return not getIsElectricVehicle(vehicle)
        end,
        causes = { primary = { "sf", "cmf", "hmf", "flf" }, secondary = { "mlf", "lf" } },
        component = "CYLINDER_LINER",
        branches = 2,
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_cylinder_liners_branch1_stage1_description",
                branchDescriptions = {
                    "rms_breakdowns_cylinder_liners_branch1_stage1_description",
                    "rms_breakdowns_cylinder_liners_branch2_stage1_description"
                },
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.CYLINDER_LINERS,
                repairPrice = stagePartPrices.CYLINDER_LINERS[1],
                effects = {}
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_cylinder_liners_branch1_stage2_description",
                branchDescriptions = {
                    "rms_breakdowns_cylinder_liners_branch1_stage2_description",
                    "rms_breakdowns_cylinder_liners_branch2_stage2_description"
                },
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.CYLINDER_LINERS,
                repairPrice = stagePartPrices.CYLINDER_LINERS[2],
                effects = {
                    { id = "EXHAUST_OIL", value = 0.25, aggregation = "max", branch = 1 },
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.04, aggregation = "sum", branch = 1 },
                    { id = "COOLANT_LEAK_RATE", value = 0.08, aggregation = "max", branch = 2 },
                    { id = "PISTON_SLAP_NOISE_EFFECT", value = 0.5, aggregation = "max", branch = 1 }
                },
                inspection = {
                    { additional = "rms_inspection_hint_cylinder_liners_stage2", branch = 2 }
                }
            },
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_cylinder_liners_branch1_stage3_description",
                branchDescriptions = {
                    "rms_breakdowns_cylinder_liners_branch1_stage3_description",
                    "rms_breakdowns_cylinder_liners_branch2_stage3_description"
                },
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.CYLINDER_LINERS,
                repairPrice = stagePartPrices.CYLINDER_LINERS[3],
                effects = {
                    { id = "EXHAUST_OIL", value = 0.5, aggregation = "max", branch = 1 },
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.12, aggregation = "sum", branch = 1 },
                    { id = "COOLANT_LEAK_RATE", value = 0.25, aggregation = "max", branch = 2 },
                    { id = "EXHAUST_UNBURNT", value = 0.3, aggregation = "max", branch = 2 },
                    { id = "PISTON_SLAP_NOISE_EFFECT", value = 0.8, aggregation = "max", branch = 1 }
                },
                indicators = {
                    { id = db.ENGINE, color = color.WARNING, switchOn = true, switchOff = false, branch = 1 },
                    { id = db.COOLANT, color = color.WARNING, switchOn = true, switchOff = false, branch = 2 }
                },
                inspection = {
                    { additional = "rms_inspection_hint_cylinder_liners_stage3", branch = 2 }
                }
            },
            {
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_cylinder_liners_branch1_stage4_description",
                branchDescriptions = {
                    "rms_breakdowns_cylinder_liners_branch1_stage4_description",
                    "rms_breakdowns_cylinder_liners_branch2_stage4_description"
                },
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = stagePartPrices.CYLINDER_LINERS[4],
                effects = {
                    {
                        id = "ENGINE_FAILURE",
                        value = 1.0,
                        aggregation = "boolean_or",
                        extraData = {
                            status = "IDLE",
                            starter = true,
                            reason = "BREAKDOWN",
                            disableAi = true
                        },
                        branch = 1
                    },
                    { id = "COOLANT_LEAK_RATE", value = 0.8, aggregation = "max", branch = 2 },
                    { id = "EXHAUST_UNBURNT", value = 0.5, aggregation = "max", branch = 2 },
                },
                indicators = {
                    { id = db.ENGINE, color = color.CRITICAL, switchOn = true, switchOff = false, branch = 1 },
                    { id = db.COOLANT, color = color.CRITICAL, switchOn = true, switchOff = false, branch = 2 }
                },
                inspection = {
                    { additional = "rms_inspection_hint_cylinder_liners_stage4", branch = 2 }
                }
            }
        }
    },

    INLET_VALVES = {
        isSelectable = true,
        system = systems.ENGINE,
        part = parts.INLET_VALVES,
        isApplicable = function(vehicle)
            return not getIsElectricVehicle(vehicle)
        end,
        causes = { primary = { "sf", "cmf" }, secondary = { "flf", "hmf", "mlf" } },
        component = "ENGINE_VALVE",
        branches = 2,
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_inlet_valves_branch1_stage1_description",
                branchDescriptions = {
                    "rms_breakdowns_inlet_valves_branch1_stage1_description",
                    "rms_breakdowns_inlet_valves_branch2_stage1_description"
                },
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.INLET_VALVES,
                repairPrice = stagePartPrices.INLET_VALVES[1],
                effects = {
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.04, aggregation = "sum" },
                    { id = "FUEL_CONSUMPTION_MODIFIER", value = 0.05, aggregation = "sum" }
                }
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_inlet_valves_branch1_stage2_description",
                branchDescriptions = {
                    "rms_breakdowns_inlet_valves_branch1_stage2_description",
                    "rms_breakdowns_inlet_valves_branch2_stage2_description"
                },
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.INLET_VALVES,
                repairPrice = stagePartPrices.INLET_VALVES[2],
                effects = {
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.12, aggregation = "sum" },
                    { id = "FUEL_CONSUMPTION_MODIFIER", value = 0.1, aggregation = "sum" },
                    { id = "ENGINE_HESITATION_CHANCE", value = 0.3, aggregation = "min",
                        extraData = { timer = 0, duration = 300, status = "IDLE", amplitude = 0.6, motorLoad = 0.8, cruiseState = 0 } }
                },
                indicators = {
                    { id = db.ENGINE, color = color.WARNING, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_inlet_valves_branch1_stage3_description",
                branchDescriptions = {
                    "rms_breakdowns_inlet_valves_branch1_stage3_description",
                    "rms_breakdowns_inlet_valves_branch2_stage3_description"
                },
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.INLET_VALVES,
                repairPrice = stagePartPrices.INLET_VALVES[3],
                effects = {
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.25, aggregation = "sum" },
                    { id = "FUEL_CONSUMPTION_MODIFIER", value = 0.2, aggregation = "sum" },
                    { id = "ENGINE_HESITATION_CHANCE", value = 0.15, aggregation = "min",
                        extraData = { timer = 0, duration = 500, status = "IDLE", amplitude = 1.0, motorLoad = 0.5, cruiseState = 0 } },
                    { id = "ENGINE_STALLS_CHANCE", value = 10.0, aggregation = "min" }
                },
                indicators = {
                    { id = db.ENGINE, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_inlet_valves_branch1_stage4_description",
                branchDescriptions = {
                    "rms_breakdowns_inlet_valves_branch1_stage4_description",
                    "rms_breakdowns_inlet_valves_branch2_stage4_description"
                },
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = stagePartPrices.INLET_VALVES[4],
                effects = {
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.25, aggregation = "sum", branch = 1 },
                    { id = "ENGINE_HESITATION_CHANCE", value = 0.15, aggregation = "min",
                        extraData = { timer = 0, duration = 500, status = "IDLE", amplitude = 1.0, motorLoad = 0.5, cruiseState = 0 },
                        branch = 1 },
                    { id = "ENGINE_STALLS_CHANCE", value = 10.0, aggregation = "min", branch = 1 },
                    { id = "FUEL_CONSUMPTION_MODIFIER", value = 0.2, aggregation = "sum", branch = 1 },
                    {
                        id = "ENGINE_FAILURE",
                        value = 1.0,
                        aggregation = "boolean_or",
                        extraData = {
                            status = "IDLE",
                            starter = true,
                            reason = "BREAKDOWN",
                            disableAi = true
                        },
                        branch = 2
                    }
                },
                indicators = {
                    { id = db.ENGINE, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            }
        }
    },

    EXHAUST_VALVES = {
        isSelectable = true,
        system = systems.ENGINE,
        part = parts.EXHAUST_VALVES,
        isApplicable = function(vehicle)
            return not getIsElectricVehicle(vehicle)
        end,
        causes = { primary = { "sf", "cmf" }, secondary = { "flf", "hmf", "mlf" } },
        component = "ENGINE_VALVE",
        branches = 2,
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_exhaust_valves_branch1_stage1_description",
                branchDescriptions = {
                    "rms_breakdowns_exhaust_valves_branch1_stage1_description",
                    "rms_breakdowns_exhaust_valves_branch2_stage1_description"
                },
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.EXHAUST_VALVES,
                repairPrice = stagePartPrices.EXHAUST_VALVES[1],
                effects = {
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.04, aggregation = "sum" },
                    { id = "FUEL_CONSUMPTION_MODIFIER", value = 0.05, aggregation = "sum" }
                }
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_exhaust_valves_branch1_stage2_description",
                branchDescriptions = {
                    "rms_breakdowns_exhaust_valves_branch1_stage2_description",
                    "rms_breakdowns_exhaust_valves_branch2_stage2_description"
                },
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.EXHAUST_VALVES,
                repairPrice = stagePartPrices.EXHAUST_VALVES[2],
                effects = {
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.12, aggregation = "sum" },
                    { id = "FUEL_CONSUMPTION_MODIFIER", value = 0.1, aggregation = "sum" },
                    { id = "ENGINE_HESITATION_CHANCE", value = 0.3, aggregation = "min",
                        extraData = { timer = 0, duration = 300, status = "IDLE", amplitude = 0.6, motorLoad = 0.8, cruiseState = 0 } }
                },
                indicators = {
                    { id = db.ENGINE, color = color.WARNING, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_exhaust_valves_branch1_stage3_description",
                branchDescriptions = {
                    "rms_breakdowns_exhaust_valves_branch1_stage3_description",
                    "rms_breakdowns_exhaust_valves_branch2_stage3_description"
                },
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.EXHAUST_VALVES,
                repairPrice = stagePartPrices.EXHAUST_VALVES[3],
                effects = {
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.25, aggregation = "sum" },
                    { id = "FUEL_CONSUMPTION_MODIFIER", value = 0.2, aggregation = "sum" },
                    { id = "ENGINE_HESITATION_CHANCE", value = 0.15, aggregation = "min",
                        extraData = { timer = 0, duration = 500, status = "IDLE", amplitude = 1.0, motorLoad = 0.5, cruiseState = 0 } },
                    { id = "ENGINE_STALLS_CHANCE", value = 10.0, aggregation = "min" }
                },
                indicators = {
                    { id = db.ENGINE, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_exhaust_valves_branch1_stage4_description",
                branchDescriptions = {
                    "rms_breakdowns_exhaust_valves_branch1_stage4_description",
                    "rms_breakdowns_exhaust_valves_branch2_stage4_description"
                },
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = stagePartPrices.EXHAUST_VALVES[4],
                effects = {
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.25, aggregation = "sum", branch = 1 },
                    { id = "ENGINE_HESITATION_CHANCE", value = 0.15, aggregation = "min",
                        extraData = { timer = 0, duration = 500, status = "IDLE", amplitude = 1.0, motorLoad = 0.5, cruiseState = 0 },
                        branch = 1 },
                    { id = "ENGINE_STALLS_CHANCE", value = 10.0, aggregation = "min", branch = 1 },
                    { id = "FUEL_CONSUMPTION_MODIFIER", value = 0.2, aggregation = "sum", branch = 1 },
                    {
                        id = "ENGINE_FAILURE",
                        value = 1.0,
                        aggregation = "boolean_or",
                        extraData = {
                            status = "IDLE",
                            starter = true,
                            reason = "BREAKDOWN",
                            disableAi = true
                        },
                        branch = 2
                    }
                },
                indicators = {
                    { id = db.ENGINE, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            }
        }
    },

    VALVE_GUIDES_SEALS = {
        isSelectable = true,
        system = systems.ENGINE,
        part = parts.VALVE_GUIDES_SEALS,
        isApplicable = function(vehicle)
            return not getIsElectricVehicle(vehicle)
        end,
        causes = { primary = { "sf", "cmf" }, secondary = { "flf", "hmf", "mlf" } },
        component = "ENGINE_VALVE",
        branches = 2,
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_valve_guides_seals_branch1_stage1_description",
                branchDescriptions = {
                    "rms_breakdowns_valve_guides_seals_branch1_stage1_description",
                    "rms_breakdowns_valve_guides_seals_branch2_stage1_description"
                },
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.VALVE_GUIDES_SEALS,
                repairPrice = stagePartPrices.VALVE_GUIDES_SEALS[1],
                effects = {
                    { id = "VALVE_TRAIN_NOISE_EFFECT", value = 0.5, aggregation = "max", branch = 1 },
                    { id = "EXHAUST_OIL", value = 0.2, aggregation = "max" }
                }
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_valve_guides_seals_branch1_stage2_description",
                branchDescriptions = {
                    "rms_breakdowns_valve_guides_seals_branch1_stage2_description",
                    "rms_breakdowns_valve_guides_seals_branch2_stage2_description"
                },
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.VALVE_GUIDES_SEALS,
                repairPrice = stagePartPrices.VALVE_GUIDES_SEALS[2],
                effects = {
                    { id = "VALVE_TRAIN_NOISE_EFFECT", value = 0.7, aggregation = "max", branch = 1 },
                    { id = "EXHAUST_OIL", value = 0.4, aggregation = "max" }
                }
            },
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_valve_guides_seals_branch1_stage3_description",
                branchDescriptions = {
                    "rms_breakdowns_valve_guides_seals_branch1_stage3_description",
                    "rms_breakdowns_valve_guides_seals_branch2_stage3_description"
                },
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.VALVE_GUIDES_SEALS,
                repairPrice = stagePartPrices.VALVE_GUIDES_SEALS[3],
                effects = {
                    { id = "VALVE_TRAIN_NOISE_EFFECT", value = 1.0, aggregation = "max", branch = 1 },
                    { id = "EXHAUST_OIL", value = 0.65, aggregation = "max" },
                    { id = "ENGINE_HESITATION_CHANCE", value = 0.3, aggregation = "min", extraData = { timer = 0, duration = 300, status = "IDLE", amplitude = 0.6, motorLoad = 0.8, cruiseState = 0 },
                        branch = 1 },
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.12, aggregation = "sum", branch = 1 }
                },
                indicators = {
                    { id = db.ENGINE, color = color.CRITICAL, switchOn = true, switchOff = false, branch = 1 }
                }
            },
            {
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_valve_guides_seals_branch1_stage4_description",
                branchDescriptions = {
                    "rms_breakdowns_valve_guides_seals_branch1_stage4_description",
                    "rms_breakdowns_valve_guides_seals_branch2_stage4_description"
                },
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = stagePartPrices.VALVE_GUIDES_SEALS[4],
                effects = {
                    { id = "VALVE_TRAIN_NOISE_EFFECT", value = 1.0, aggregation = "max", branch = 1 },
                    { id = "EXHAUST_OIL", value = 0.65, aggregation = "max" },
                    { id = "ENGINE_HESITATION_CHANCE", value = 0.3, aggregation = "min", extraData = { timer = 0, duration = 300, status = "IDLE", amplitude = 0.6, motorLoad = 0.8, cruiseState = 0 },
                        branch = 1 },
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.12, aggregation = "sum", branch = 1 }
                },
                indicators = {
                    { id = db.ENGINE, color = color.CRITICAL, switchOn = true, switchOff = false, branch = 1 }
                }
            }
        }
    },

    CYLINDER_HEAD = {
        isSelectable = true,
        system = systems.ENGINE,
        part = parts.CYLINDER_HEAD,
        isApplicable = function(vehicle)
            return not getIsElectricVehicle(vehicle)
        end,
        causes = { primary = { "hmf" }, secondary = {} },
        component = "HEAT_EXCHANGER",
        wearsByCausesOnly = true,
        branches = 3,
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_cylinder_head_branch1_stage1_description",
                branchDescriptions = {
                    "rms_breakdowns_cylinder_head_branch1_stage1_description",
                    "rms_breakdowns_cylinder_head_branch2_stage1_description",
                    "rms_breakdowns_cylinder_head_branch3_stage1_description"
                },
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.CYLINDER_HEAD,
                repairPrice = stagePartPrices.CYLINDER_HEAD[1],
                effects = {}
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_cylinder_head_branch1_stage2_description",
                branchDescriptions = {
                    "rms_breakdowns_cylinder_head_branch1_stage2_description",
                    "rms_breakdowns_cylinder_head_branch2_stage2_description",
                    "rms_breakdowns_cylinder_head_branch3_stage2_description"
                },
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.CYLINDER_HEAD,
                repairPrice = stagePartPrices.CYLINDER_HEAD[2],
                effects = {
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.04, aggregation = "sum", branch = 1 },
                    { id = "ENGINE_HARD_START_MODIFIER", value = 3, aggregation = "max", extraData = { timer = 0, status = "IDLE" }, branch = 1 },
                    { id = "COOLANT_LEAK_RATE", value = 0.08, aggregation = "max", branch = 1 },
                    { id = "COOLANT_LEAK_RATE", value = 0.08, aggregation = "max", branch = 2 },
                    { id = "COOLANT_LEAK_RATE", value = 0.08, aggregation = "max", branch = 3 }
                },
                inspection = {
                    { additional = "rms_inspection_hint_cylinder_head_stage2", branch = 2 }
                }
            },
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_cylinder_head_branch1_stage3_description",
                branchDescriptions = {
                    "rms_breakdowns_cylinder_head_branch1_stage3_description",
                    "rms_breakdowns_cylinder_head_branch2_stage3_description",
                    "rms_breakdowns_cylinder_head_branch3_stage3_description"
                },
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.CYLINDER_HEAD,
                repairPrice = stagePartPrices.CYLINDER_HEAD[3],
                effects = {
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.12, aggregation = "sum", branch = 1 },
                    { id = "ENGINE_HARD_START_MODIFIER", value = 6, aggregation = "max", extraData = { timer = 0, status = "IDLE" }, branch = 1 },
                    { id = "COOLANT_LEAK_RATE", value = 0.25, aggregation = "max", branch = 1 },
                    { id = "COOLANT_LEAK_RATE", value = 0.25, aggregation = "max", branch = 2 },
                    { id = "COOLANT_LEAK_RATE", value = 0.25, aggregation = "max", branch = 3 },
                    { id = "EXHAUST_UNBURNT", value = 0.3, aggregation = "max", branch = 1 }
                },
                indicators = {
                    { id = db.COOLANT, color = color.CRITICAL, switchOn = true, switchOff = false, branch = 1 },
                    { id = db.COOLANT, color = color.WARNING, switchOn = true, switchOff = false, branch = 2 },
                    { id = db.COOLANT, color = color.WARNING, switchOn = true, switchOff = false, branch = 3 }
                },
                inspection = {
                    { additional = "rms_inspection_hint_cylinder_head_stage3", branch = 2 }
                }
            },
            {
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_cylinder_head_branch1_stage4_description",
                branchDescriptions = {
                    "rms_breakdowns_cylinder_head_branch1_stage4_description",
                    "rms_breakdowns_cylinder_head_branch2_stage4_description",
                    "rms_breakdowns_cylinder_head_branch3_stage4_description"
                },
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = stagePartPrices.CYLINDER_HEAD[4],
                effects = {
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.25, aggregation = "sum", branch = 1 },
                    { id = "ENGINE_HARD_START_MODIFIER", value = 9, aggregation = "max", extraData = { timer = 0, status = "IDLE" }, branch = 1 },
                    { id = "COOLANT_LEAK_RATE", value = 0.8, aggregation = "max", branch = 1 },
                    { id = "COOLANT_LEAK_RATE", value = 0.8, aggregation = "max", branch = 2 },
                    { id = "COOLANT_LEAK_RATE", value = 0.8, aggregation = "max", branch = 3 },
                    { id = "EXHAUST_UNBURNT", value = 0.5, aggregation = "max", branch = 1 }
                },
                indicators = {
                    { id = db.COOLANT, color = color.CRITICAL, switchOn = true, switchOff = false, branch = 1 },
                    { id = db.COOLANT, color = color.CRITICAL, switchOn = true, switchOff = false, branch = 2 },
                    { id = db.COOLANT, color = color.CRITICAL, switchOn = true, switchOff = false, branch = 3 }
                },
                inspection = {
                    { additional = "rms_inspection_hint_cylinder_head_stage4", branch = 2 }
                }
            }
        }
    },

    CYLINDER_HEAD_GASKET = {
        isSelectable = true,
        system = systems.ENGINE,
        part = parts.CYLINDER_HEAD_GASKET,
        isApplicable = function(vehicle)
            return not getIsElectricVehicle(vehicle)
        end,
        causes = { primary = { "hmf" }, secondary = { "sf" } },
        component = "ENGINE_HEAD_GASKET",
        branches = 3,
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_cylinder_head_gasket_branch1_stage1_description",
                branchDescriptions = {
                    "rms_breakdowns_cylinder_head_gasket_branch1_stage1_description",
                    "rms_breakdowns_cylinder_head_gasket_branch2_stage1_description",
                    "rms_breakdowns_cylinder_head_gasket_branch3_stage1_description"
                },
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.CYLINDER_HEAD_GASKET,
                repairPrice = stagePartPrices.CYLINDER_HEAD_GASKET[1],
                effects = {}
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_cylinder_head_gasket_branch1_stage2_description",
                branchDescriptions = {
                    "rms_breakdowns_cylinder_head_gasket_branch1_stage2_description",
                    "rms_breakdowns_cylinder_head_gasket_branch2_stage2_description",
                    "rms_breakdowns_cylinder_head_gasket_branch3_stage2_description"
                },
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.CYLINDER_HEAD_GASKET,
                repairPrice = stagePartPrices.CYLINDER_HEAD_GASKET[2],
                effects = {
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.04, aggregation = "sum", branch = 1 },
                    { id = "ENGINE_HARD_START_MODIFIER", value = 3, aggregation = "max", extraData = { timer = 0, status = "IDLE" }, branch = 1 },
                    { id = "COOLANT_LEAK_RATE", value = 0.08, aggregation = "max", branch = 1 },
                    { id = "COOLANT_LEAK_RATE", value = 0.08, aggregation = "max", branch = 2 },
                    { id = "COOLANT_LEAK_RATE", value = 0.08, aggregation = "max", branch = 3 }
                },
                inspection = {
                    { additional = "rms_inspection_hint_cylinder_head_gasket_stage2", branch = 2 }
                }
            },
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_cylinder_head_gasket_branch1_stage3_description",
                branchDescriptions = {
                    "rms_breakdowns_cylinder_head_gasket_branch1_stage3_description",
                    "rms_breakdowns_cylinder_head_gasket_branch2_stage3_description",
                    "rms_breakdowns_cylinder_head_gasket_branch3_stage3_description"
                },
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.CYLINDER_HEAD_GASKET,
                repairPrice = stagePartPrices.CYLINDER_HEAD_GASKET[3],
                effects = {
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.12, aggregation = "sum", branch = 1 },
                    { id = "ENGINE_HARD_START_MODIFIER", value = 6, aggregation = "max", extraData = { timer = 0, status = "IDLE" }, branch = 1 },
                    { id = "COOLANT_LEAK_RATE", value = 0.25, aggregation = "max", branch = 1 },
                    { id = "COOLANT_LEAK_RATE", value = 0.25, aggregation = "max", branch = 2 },
                    { id = "COOLANT_LEAK_RATE", value = 0.25, aggregation = "max", branch = 3 },
                    { id = "EXHAUST_UNBURNT", value = 0.3, aggregation = "max", branch = 1 }
                },
                indicators = {
                    { id = db.COOLANT, color = color.CRITICAL, switchOn = true, switchOff = false, branch = 1 },
                    { id = db.COOLANT, color = color.WARNING, switchOn = true, switchOff = false, branch = 2 },
                    { id = db.COOLANT, color = color.WARNING, switchOn = true, switchOff = false, branch = 3 }
                },
                inspection = {
                    { additional = "rms_inspection_hint_cylinder_head_gasket_stage3", branch = 2 }
                }
            },
            {
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_cylinder_head_gasket_branch1_stage4_description",
                branchDescriptions = {
                    "rms_breakdowns_cylinder_head_gasket_branch1_stage4_description",
                    "rms_breakdowns_cylinder_head_gasket_branch2_stage4_description",
                    "rms_breakdowns_cylinder_head_gasket_branch3_stage4_description"
                },
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = stagePartPrices.CYLINDER_HEAD_GASKET[4],
                effects = {
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.25, aggregation = "sum", branch = 1 },
                    { id = "ENGINE_HARD_START_MODIFIER", value = 9, aggregation = "max", extraData = { timer = 0, status = "IDLE" }, branch = 1 },
                    { id = "COOLANT_LEAK_RATE", value = 0.8, aggregation = "max", branch = 1 },
                    { id = "COOLANT_LEAK_RATE", value = 0.8, aggregation = "max", branch = 2 },
                    { id = "COOLANT_LEAK_RATE", value = 0.8, aggregation = "max", branch = 3 },
                    { id = "EXHAUST_UNBURNT", value = 0.5, aggregation = "max", branch = 1 }
                },
                indicators = {
                    { id = db.COOLANT, color = color.CRITICAL, switchOn = true, switchOff = false, branch = 1 },
                    { id = db.COOLANT, color = color.CRITICAL, switchOn = true, switchOff = false, branch = 2 },
                    { id = db.COOLANT, color = color.CRITICAL, switchOn = true, switchOff = false, branch = 3 }
                },
                inspection = {
                    { additional = "rms_inspection_hint_cylinder_head_gasket_stage4", branch = 2 }
                }
            }
        }
    },

    MAIN_BEARINGS = {
        isSelectable = true,
        system = systems.ENGINE,
        part = parts.MAIN_BEARINGS,
        isApplicable = function(vehicle)
            return not getIsElectricVehicle(vehicle)
        end,
        causes = { primary = { "flf", "hmf" }, secondary = { "sf", "mlf" } },
        component = "SLEEVE_BEARING",
        branches = 2,
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_main_bearings_branch1_stage1_description",
                branchDescriptions = {
                    "rms_breakdowns_main_bearings_branch1_stage1_description",
                    "rms_breakdowns_main_bearings_branch2_stage1_description"
                },
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.MAIN_BEARINGS,
                repairPrice = stagePartPrices.MAIN_BEARINGS[1],
                effects = {}
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_main_bearings_branch1_stage2_description",
                branchDescriptions = {
                    "rms_breakdowns_main_bearings_branch1_stage2_description",
                    "rms_breakdowns_main_bearings_branch2_stage2_description"
                },
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.MAIN_BEARINGS,
                repairPrice = stagePartPrices.MAIN_BEARINGS[2],
                effects = {}
            },
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_main_bearings_branch1_stage3_description",
                branchDescriptions = {
                    "rms_breakdowns_main_bearings_branch1_stage3_description",
                    "rms_breakdowns_main_bearings_branch2_stage3_description"
                },
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.MAIN_BEARINGS,
                repairPrice = stagePartPrices.MAIN_BEARINGS[3],
                effects = {
                    { id = "ENGINE_KNOCKING_NOISE_EFFECT", value = 0.8, aggregation = "max" },
                    { id = "ENGINE_HEAT_MODIFIER", value = 0.35, aggregation = "sum" }
                },
                indicators = {
                    { id = db.OIL, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_main_bearings_branch1_stage4_description",
                branchDescriptions = {
                    "rms_breakdowns_main_bearings_branch1_stage4_description",
                    "rms_breakdowns_main_bearings_branch2_stage4_description"
                },
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = stagePartPrices.MAIN_BEARINGS[4],
                effects = {
                    {
                        id = "ENGINE_FAILURE",
                        value = 1.0,
                        aggregation = "boolean_or",
                        extraData = {
                            status = "IDLE",
                            starter = true,
                            reason = "BREAKDOWN",
                            disableAi = true
                        }
                    }
                },
                indicators = {
                    { id = db.OIL, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            }
        }
    },

    CONROD_BEARINGS = {
        isSelectable = true,
        system = systems.ENGINE,
        part = parts.CONROD_BEARINGS,
        isApplicable = function(vehicle)
            return not getIsElectricVehicle(vehicle)
        end,
        causes = { primary = { "flf", "hmf" }, secondary = { "sf", "mlf" } },
        component = "SLEEVE_BEARING",
        branches = 2,
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_conrod_bearings_branch1_stage1_description",
                branchDescriptions = {
                    "rms_breakdowns_conrod_bearings_branch1_stage1_description",
                    "rms_breakdowns_conrod_bearings_branch2_stage1_description"
                },
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.CONROD_BEARINGS,
                repairPrice = stagePartPrices.CONROD_BEARINGS[1],
                effects = {}
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_conrod_bearings_branch1_stage2_description",
                branchDescriptions = {
                    "rms_breakdowns_conrod_bearings_branch1_stage2_description",
                    "rms_breakdowns_conrod_bearings_branch2_stage2_description"
                },
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.CONROD_BEARINGS,
                repairPrice = stagePartPrices.CONROD_BEARINGS[2],
                effects = {}
            },
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_conrod_bearings_branch1_stage3_description",
                branchDescriptions = {
                    "rms_breakdowns_conrod_bearings_branch1_stage3_description",
                    "rms_breakdowns_conrod_bearings_branch2_stage3_description"
                },
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.CONROD_BEARINGS,
                repairPrice = stagePartPrices.CONROD_BEARINGS[3],
                effects = {
                    { id = "ENGINE_KNOCKING_NOISE_EFFECT", value = 0.8, aggregation = "max" },
                    { id = "ENGINE_HEAT_MODIFIER", value = 0.35, aggregation = "sum" }
                },
                indicators = {
                    { id = db.OIL, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_conrod_bearings_branch1_stage4_description",
                branchDescriptions = {
                    "rms_breakdowns_conrod_bearings_branch1_stage4_description",
                    "rms_breakdowns_conrod_bearings_branch2_stage4_description"
                },
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = stagePartPrices.CONROD_BEARINGS[4],
                effects = {
                    {
                        id = "ENGINE_FAILURE",
                        value = 1.0,
                        aggregation = "boolean_or",
                        extraData = {
                            status = "IDLE",
                            starter = true,
                            reason = "BREAKDOWN",
                            disableAi = true
                        }
                    }
                },
                indicators = {
                    { id = db.OIL, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            }
        }
    },

    ELECTRIC_MOTOR_BEARING_WEAR = {
        isSelectable = true,
        system = systems.ENGINE,
        part = parts.ELECTRIC_MOTOR_BEARINGS,
        isApplicable = function(vehicle)
            return getIsElectricVehicle(vehicle)
        end,
        causes = { primary = {}, secondary = {"hmf"} },
        component = "BALL_BEARING",
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_electric_motor_bearing_wear_stage1_description",
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.ELECTRIC_MOTOR_BEARING_WEAR,
                repairPrice = stagePartPrices.ELECTRIC_MOTOR_BEARING_WEAR[1],
                effects = {
                    { id = "ELECTRIC_MOTOR_BEARING_NOISE_EFFECT", value = 1.0, aggregation = "max" },
                    { id = "FUEL_CONSUMPTION_MODIFIER", value = 0.03, aggregation = "sum" }
                }
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_electric_motor_bearing_wear_stage2_description",
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.ELECTRIC_MOTOR_BEARING_WEAR,
                repairPrice = stagePartPrices.ELECTRIC_MOTOR_BEARING_WEAR[2],
                effects = {
                    { id = "ELECTRIC_MOTOR_BEARING_NOISE_EFFECT", value = 1.5, aggregation = "max" },
                    { id = "FUEL_CONSUMPTION_MODIFIER", value = 0.06, aggregation = "sum" },
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.05, aggregation = "sum" }
                },
                indicators = {
                    { id = db.ENGINE, color = color.WARNING, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_electric_motor_bearing_wear_stage3_description",
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.ELECTRIC_MOTOR_BEARING_WEAR,
                repairPrice = stagePartPrices.ELECTRIC_MOTOR_BEARING_WEAR[3],
                effects = {
                    { id = "ELECTRIC_MOTOR_BEARING_NOISE_EFFECT", value = 2.0, aggregation = "max" },
                    { id = "FUEL_CONSUMPTION_MODIFIER", value = 0.10, aggregation = "sum" },
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.12, aggregation = "sum" },
                    { id = "ENGINE_HEAT_MODIFIER", value = 0.10, aggregation = "sum" }
                },
                indicators = {
                    { id = db.ENGINE, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_electric_motor_bearing_wear_stage4_description",
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = stagePartPrices.ELECTRIC_MOTOR_BEARING_WEAR[4],
                effects = {
                        {
                            id = "ENGINE_FAILURE",
                            value = 1.0,
                            aggregation = "boolean_or",
                            extraData = {
                                status = 'IDLE',
                                starter = false,
                                reason = "BREAKDOWN",
                                disableAi = true
                            }
                        }
                },
                indicators = {
                    { id = db.ENGINE, color = color.CRITICAL, switchOn = true, switchOff = false },
                    { id = db.WARNING, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            }
        }
    },
    ELECTRIC_MOTOR_WINDING_FAULT = {
        isSelectable = true,
        system = systems.ENGINE,
        part = parts.ELECTRIC_MOTOR_WINDINGS,
        isApplicable = function(vehicle)
            return getIsElectricVehicle(vehicle)
        end,
        causes = { primary = {"hmf"}, secondary = {"mlf"} },
        component = "AC_MOTOR",
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_electric_motor_winding_fault_stage1_description",
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.ELECTRIC_MOTOR_WINDING_FAULT,
                repairPrice = stagePartPrices.ELECTRIC_MOTOR_WINDING_FAULT[1],
                effects = {
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.08, aggregation = "sum" },
                    { id = "ENGINE_HEAT_MODIFIER", value = 0.05, aggregation = "sum" }
                }
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_electric_motor_winding_fault_stage2_description",
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.ELECTRIC_MOTOR_WINDING_FAULT,
                repairPrice = stagePartPrices.ELECTRIC_MOTOR_WINDING_FAULT[2],
                effects = {
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.18, aggregation = "sum" },
                    { id = "FUEL_CONSUMPTION_MODIFIER", value = 0.08, aggregation = "sum" },
                    { id = "ENGINE_HEAT_MODIFIER", value = 0.10, aggregation = "sum" }
                },
                indicators = {
                    { id = db.ENGINE, color = color.WARNING, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_electric_motor_winding_fault_stage3_description",
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.ELECTRIC_MOTOR_WINDING_FAULT,
                repairPrice = stagePartPrices.ELECTRIC_MOTOR_WINDING_FAULT[3],
                effects = {
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.30, aggregation = "sum" },
                    { id = "FUEL_CONSUMPTION_MODIFIER", value = 0.15, aggregation = "sum" },
                    { id = "ENGINE_STALLS_CHANCE", value = 15.0, aggregation = "min" },
                    { id = "ENGINE_HEAT_MODIFIER", value = 0.20, aggregation = "sum" }
                },
                indicators = {
                    { id = db.ENGINE, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_electric_motor_winding_fault_stage4_description",
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = stagePartPrices.ELECTRIC_MOTOR_WINDING_FAULT[4],
                effects = {
                        {
                            id = "ENGINE_FAILURE",
                            value = 1.0,
                            aggregation = "boolean_or",
                            extraData = {
                                status = 'IDLE',
                                starter = false,
                                reason = "BREAKDOWN",
                                disableAi = true
                            }
                        }
                },
                indicators = {
                    { id = db.ENGINE, color = color.CRITICAL, switchOn = true, switchOff = false },
                    { id = db.WARNING, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            }
        }
    },
    MOTOR_POSITION_SENSOR_FAULT = {
        isSelectable = true,
        system = systems.ENGINE,
        part = parts.MOTOR_POSITION_SENSOR,
        isApplicable = function(vehicle)
            return getIsElectricVehicle(vehicle)
        end,
        causes = { primary = {"hmf"}, secondary = {} },
        component = "TRANSDUCER",
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_motor_position_sensor_fault_stage1_description",
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.MOTOR_POSITION_SENSOR_FAULT,
                repairPrice = stagePartPrices.MOTOR_POSITION_SENSOR_FAULT[1],
                effects = {
                    { id = "ENGINE_HESITATION_CHANCE", value = 0.3, aggregation = "min", extraData = {timer = 0, duration = 300, status = 'IDLE', amplitude = 0.4, motorLoad = 0.2, cruiseState = 0} }
                }
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_motor_position_sensor_fault_stage2_description",
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.MOTOR_POSITION_SENSOR_FAULT,
                repairPrice = stagePartPrices.MOTOR_POSITION_SENSOR_FAULT[2],
                effects = {
                    { id = "ENGINE_HESITATION_CHANCE", value = 0.2, aggregation = "min", extraData = {timer = 0, duration = 400, status = 'IDLE', amplitude = 0.6, motorLoad = 0.2, cruiseState = 0} },
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.10, aggregation = "sum" }
                },
                indicators = {
                    { id = db.ENGINE, color = color.WARNING, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_motor_position_sensor_fault_stage3_description",
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.MOTOR_POSITION_SENSOR_FAULT,
                repairPrice = stagePartPrices.MOTOR_POSITION_SENSOR_FAULT[3],
                effects = {
                    { id = "ENGINE_HESITATION_CHANCE", value = 0.1, aggregation = "min", extraData = {timer = 0, duration = 500, status = 'IDLE', amplitude = 0.8, motorLoad = 0.2, cruiseState = 0} },
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.20, aggregation = "sum" },
                    { id = "ENGINE_STALLS_CHANCE", value = 10.0, aggregation = "min" }
                },
                indicators = {
                    { id = db.ENGINE, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_motor_position_sensor_fault_stage4_description",
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = stagePartPrices.MOTOR_POSITION_SENSOR_FAULT[4],
                effects = {
                        {
                            id = "ENGINE_FAILURE",
                            value = 1.0,
                            aggregation = "boolean_or",
                            extraData = {
                                status = 'IDLE',
                                starter = false,
                                reason = "BREAKDOWN",
                                disableAi = true
                            }
                        }
                },
                indicators = {
                    { id = db.ENGINE, color = color.CRITICAL, switchOn = true, switchOff = false },
                    { id = db.WARNING, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            }
        }
    },
    MANUAL_TRANSMISSION_CLUTCH_WEAR = {
        isSelectable = true,
        system = systems.TRANSMISSION,
        part = parts.CLUTCH,
        isApplicable = function(vehicle)
            if hasCVTAddon(vehicle) then return false end
            local motor = vehicle:getMotor()
            if not motor then return false end
            return motor.minForwardGearRatio == nil
        end,
        causes = { primary = { "lf" }, secondary = { "pof", "sf" } },
        component = "FRICTION_CLUTCH",
        branches = 2,
        isCanProgress = function(vehicle)
            return vehicle:getLastSpeed() > 0.01
        end,
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_transmission_slip_stage1_description",
                branchDescriptions = {
                    "rms_breakdowns_transmission_slip_stage1_description",
                    "rms_breakdowns_manual_transmission_clutch_wear_branch2_stage1_description"
                },
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.MANUAL_TRANSMISSION_CLUTCH_WEAR,
                repairPrice = stagePartPrices.MANUAL_TRANSMISSION_CLUTCH_WEAR[1],
                effects = {
                    { id = "TRANSMISSION_SLIP_EFFECT", value = 0.2, aggregation = "max", branch = 1 },
                    { id = "GEAR_SHIFT_FAILURE_CHANCE", value = 0.1, aggregation = "max", extraData = { duration = 1500, timer = 0, status = "IDLE" }, branch = 2 }
                }
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_transmission_slip_stage2_description",
                branchDescriptions = {
                    "rms_breakdowns_transmission_slip_stage2_description",
                    "rms_breakdowns_manual_transmission_clutch_wear_branch2_stage2_description"
                },
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.MANUAL_TRANSMISSION_CLUTCH_WEAR,
                repairPrice = stagePartPrices.MANUAL_TRANSMISSION_CLUTCH_WEAR[2],
                effects = {
                    { id = "TRANSMISSION_SLIP_EFFECT", value = 0.4, aggregation = "max", branch = 1 },
                    { id = "FUEL_CONSUMPTION_MODIFIER", value = 0.2, aggregation = "sum", branch = 1 },
                    { id = "GEAR_SHIFT_FAILURE_CHANCE", value = 0.2, aggregation = "max", extraData = { duration = 1800, timer = 0, status = "IDLE" }, branch = 2 }
                },
                indicators = {
                    { id = db.TRANSMISSION, color = color.WARNING, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_transmission_slip_stage3_description",
                branchDescriptions = {
                    "rms_breakdowns_transmission_slip_stage3_description",
                    "rms_breakdowns_manual_transmission_clutch_wear_branch2_stage3_description"
                },
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.MANUAL_TRANSMISSION_CLUTCH_WEAR,
                repairPrice = stagePartPrices.MANUAL_TRANSMISSION_CLUTCH_WEAR[3],
                effects = {
                    { id = "TRANSMISSION_SLIP_EFFECT", value = 0.6, aggregation = "max", branch = 1 },
                    { id = "FUEL_CONSUMPTION_MODIFIER", value = 0.5, aggregation = "sum", branch = 1 },
                    { id = "GEAR_SHIFT_FAILURE_CHANCE", value = 0.5, aggregation = "max", extraData = { duration = 2200, timer = 0, status = "IDLE" }, branch = 2 }
                },
                indicators = {
                    { id = db.TRANSMISSION, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_transmission_slip_stage4_description",
                branchDescriptions = {
                    "rms_breakdowns_transmission_slip_stage4_description",
                    "rms_breakdowns_manual_transmission_clutch_wear_branch2_stage4_description"
                },
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = stagePartPrices.MANUAL_TRANSMISSION_CLUTCH_WEAR[4],
                effects = {
                    { id = "TRANSMISSION_SLIP_EFFECT", value = 1.0, aggregation = "max", extraData = { disableAi = true }, branch = 1 },
                    { id = "GEAR_SHIFT_FAILURE_CHANCE", value = 1.0, aggregation = "max",
                        extraData = { timer = 0, disableAi = true, duration = 2200, status = "IDLE" }, branch = 2 }
                },
                indicators = {
                    { id = db.TRANSMISSION, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            }
        }
    },

    MANUAL_TRANSMISSION_SYNCHRONIZER_MALFUNCTION = {
        isSelectable = true,
        system = systems.TRANSMISSION,
        part = parts.SYNCHRONIZER,
        isApplicable = function(vehicle)
            if hasCVTAddon(vehicle) then return false end
            local motor = vehicle:getMotor()
            if not motor then return false end
            return motor.minForwardGearRatio == nil and motor.gearType ~= VehicleMotor.TRANSMISSION_TYPE.POWERSHIFT
        end,
        causes = { primary = { "lf", "pof" }, secondary = { "sf" } },
        component = "FRICTION_CLUTCH",
        isCanProgress = function(vehicle)
            return vehicle:getLastSpeed() > 0.01
        end,
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_transmission_synchronizer_malfunction_stage1_description",
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.MANUAL_TRANSMISSION_SYNCHRONIZER_MALFUNCTION,
                repairPrice = stagePartPrices.MANUAL_TRANSMISSION_SYNCHRONIZER_MALFUNCTION[1],
                effects = {
                    { id = "GEAR_SHIFT_FAILURE_CHANCE", value = 0.1, aggregation = "max", extraData = { duration = 1500, timer = 0, status = "IDLE" } },
                    { id = "GEAR_REJECTION_CHANCE", value = 20.0, aggregation = "min", extraData = { duration = 2000, timer = 0, status = "IDLE" } }
                }
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_transmission_synchronizer_malfunction_stage2_description",
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.MANUAL_TRANSMISSION_SYNCHRONIZER_MALFUNCTION,
                repairPrice = stagePartPrices.MANUAL_TRANSMISSION_SYNCHRONIZER_MALFUNCTION[2],
                effects = {
                    { id = "GEAR_SHIFT_FAILURE_CHANCE", value = 0.2, aggregation = "max", extraData = { duration = 1800, timer = 0, status = "IDLE" } },
                    { id = "GEAR_REJECTION_CHANCE", value = 10.0, aggregation = "min", extraData = { duration = 2000, timer = 0, status = "IDLE" } }
                },
                indicators = {
                    { id = db.TRANSMISSION, color = color.WARNING, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_transmission_synchronizer_malfunction_stage3_description",
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.MANUAL_TRANSMISSION_SYNCHRONIZER_MALFUNCTION,
                repairPrice = stagePartPrices.MANUAL_TRANSMISSION_SYNCHRONIZER_MALFUNCTION[3],
                effects = {
                    { id = "GEAR_SHIFT_FAILURE_CHANCE", value = 0.5, aggregation = "max", extraData = { duration = 2200, timer = 0, status = "IDLE" } },
                    { id = "GEAR_REJECTION_CHANCE", value = 3.0, aggregation = "min", extraData = { duration = 2000, timer = 0, status = "IDLE" } }
                },
                indicators = {
                    { id = db.TRANSMISSION, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_transmission_synchronizer_malfunction_stage4_description",
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = stagePartPrices.MANUAL_TRANSMISSION_SYNCHRONIZER_MALFUNCTION[4],
                effects = {
                    { id = "GEAR_SHIFT_FAILURE_CHANCE", value = 1.0, aggregation = "max",
                        extraData = { timer = 0, disableAi = true, duration = 2200, status = "IDLE" } }
                },
                indicators = {
                    { id = db.TRANSMISSION, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            }
        }
    },

    GEARBOX_BEARING_FAILURE = {
        isSelectable = true,
        system = systems.TRANSMISSION,
        part = parts.GEARBOX_BEARINGS,
        isApplicable = function(vehicle)
            return not hasCVTAddon(vehicle) and not getIsElectricVehicle(vehicle) and vehicle:getMotor() ~= nil
        end,
        causes = { primary = { "flf", "pof" }, secondary = { "sf", "hfbf" } },
        component = "ROLLER_BEARING",
        isCanProgress = function(vehicle)
            return vehicle:getLastSpeed() > 0.01
        end,
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_gearbox_bearing_failure_stage1_description",
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.GEARBOX_BEARING_FAILURE,
                repairPrice = stagePartPrices.GEARBOX_BEARING_FAILURE[1],
                effects = {
                    { id = "GEARBOX_BEARING_NOISE_EFFECT", value = 0.3, aggregation = "max" }
                }
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_gearbox_bearing_failure_stage2_description",
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.GEARBOX_BEARING_FAILURE,
                repairPrice = stagePartPrices.GEARBOX_BEARING_FAILURE[2],
                effects = {
                    { id = "GEARBOX_BEARING_NOISE_EFFECT", value = 0.8, aggregation = "max" }
                }
            },
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_gearbox_bearing_failure_stage3_description",
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.GEARBOX_BEARING_FAILURE,
                repairPrice = stagePartPrices.GEARBOX_BEARING_FAILURE[3],
                effects = {
                    { id = "GEARBOX_BEARING_NOISE_EFFECT", value = 1.0, aggregation = "max" }
                }
            },
            {
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_gearbox_bearing_failure_stage4_description",
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = stagePartPrices.GEARBOX_BEARING_FAILURE[4],
                effects = {
                    { id = "DRIVE_LOSS_EFFECT", value = 1, aggregation = "max", extraData = { disableAi = true } }
                }
            }
        }
    },

    POWERSHIFT_CLUTCH_FAILURE = {
        isSelectable = true,
        system = systems.TRANSMISSION,
        part = parts.POWERSHIFT_CLUTCHES,
        isApplicable = isPowershiftBreakdownApplicable,
        causes = { primary = {}, secondary = { "pof", "sf", "ctf", "flf", "hfbf" } },
        component = "POWERSHIFT_REPLACEMENT_BUDGET",
        branches = 2,
        isCanProgress = function(vehicle)
            return vehicle:getLastSpeed() > 0.01
        end,
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_powershift_clutch_failure_branch1_stage1_description",
                branchDescriptions = {
                    "rms_breakdowns_powershift_clutch_failure_branch1_stage1_description",
                    "rms_breakdowns_powershift_clutch_failure_branch2_stage1_description"
                },
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.POWERSHIFT_CLUTCH_FAILURE,
                repairPrice = stagePartPrices.POWERSHIFT_CLUTCH_FAILURE[1],
                effects = {
                    { id = "TRANSMISSION_SLIP_EFFECT", value = 0.2, aggregation = "max", branch = 1 },
                    { id = "POWERSHIFT_ENGAGEMENT_LAG_AND_HARSH_EFFECT", value = 0.2, aggregation = "max", extraData = { duration = 700, timer = 0, backup = 0, status = "IDLE" }, branch = 2 }
                }
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_powershift_clutch_failure_branch1_stage2_description",
                branchDescriptions = {
                    "rms_breakdowns_powershift_clutch_failure_branch1_stage2_description",
                    "rms_breakdowns_powershift_clutch_failure_branch2_stage2_description"
                },
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.POWERSHIFT_CLUTCH_FAILURE,
                repairPrice = stagePartPrices.POWERSHIFT_CLUTCH_FAILURE[2],
                effects = {
                    { id = "TRANSMISSION_SLIP_EFFECT", value = 0.4, aggregation = "max", branch = 1 },
                    { id = "POWERSHIFT_ENGAGEMENT_LAG_AND_HARSH_EFFECT", value = 0.5, aggregation = "max", extraData = { duration = 1000, timer = 0, backup = 0, status = "IDLE" }, branch = 2 }
                },
                indicators = {
                    { id = db.TRANSMISSION, color = color.WARNING, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_powershift_clutch_failure_branch1_stage3_description",
                branchDescriptions = {
                    "rms_breakdowns_powershift_clutch_failure_branch1_stage3_description",
                    "rms_breakdowns_powershift_clutch_failure_branch2_stage3_description"
                },
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.POWERSHIFT_CLUTCH_FAILURE,
                repairPrice = stagePartPrices.POWERSHIFT_CLUTCH_FAILURE[3],
                effects = {
                    { id = "TRANSMISSION_SLIP_EFFECT", value = 0.6, aggregation = "max", branch = 1 },
                    { id = "POWERSHIFT_ENGAGEMENT_LAG_AND_HARSH_EFFECT", value = 0.99, aggregation = "max", extraData = { duration = 1500, timer = 0, backup = 0, status = "IDLE" }, branch = 2 }
                },
                indicators = {
                    { id = db.TRANSMISSION, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_powershift_clutch_failure_branch1_stage4_description",
                branchDescriptions = {
                    "rms_breakdowns_powershift_clutch_failure_branch1_stage4_description",
                    "rms_breakdowns_powershift_clutch_failure_branch2_stage4_description"
                },
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = stagePartPrices.POWERSHIFT_CLUTCH_FAILURE[4],
                effects = {
                    { id = "TRANSMISSION_SLIP_EFFECT", value = 1.0, aggregation = "max", extraData = { disableAi = true }, branch = 1 },
                    { id = "POWERSHIFT_ENGAGEMENT_LAG_AND_HARSH_EFFECT", value = 1.0, aggregation = "max",
                        extraData = { duration = 0, timer = 0, disableAi = true, status = "IDLE" }, branch = 2 },
                    { id = "DRIVE_LOSS_EFFECT", value = 1, aggregation = "max", extraData = { disableAi = true } }
                },
                indicators = {
                    { id = db.TRANSMISSION, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            }
        }
    },

    POWERSHIFT_REVERSER_FAILURE = {
        isSelectable = true,
        system = systems.TRANSMISSION,
        part = parts.POWERSHIFT_REVERSER,
        isApplicable = isPowershiftBreakdownApplicable,
        causes = { primary = {}, secondary = { "pof", "sf", "ctf", "flf", "hfbf" } },
        component = "POWERSHIFT_REPLACEMENT_BUDGET",
        branches = 2,
        isCanProgress = function(vehicle)
            return vehicle:getLastSpeed() > 0.01
        end,
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_powershift_reverser_failure_branch1_stage1_description",
                branchDescriptions = {
                    "rms_breakdowns_powershift_reverser_failure_branch1_stage1_description",
                    "rms_breakdowns_powershift_reverser_failure_branch2_stage1_description"
                },
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.POWERSHIFT_REVERSER_FAILURE,
                repairPrice = stagePartPrices.POWERSHIFT_REVERSER_FAILURE[1],
                effects = {
                    { id = "TRANSMISSION_SLIP_EFFECT", value = 0.2, aggregation = "max", branch = 1 },
                    { id = "POWERSHIFT_ENGAGEMENT_LAG_AND_HARSH_EFFECT", value = 0.2, aggregation = "max", extraData = { duration = 700, timer = 0, backup = 0, status = "IDLE" }, branch = 2 }
                }
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_powershift_reverser_failure_branch1_stage2_description",
                branchDescriptions = {
                    "rms_breakdowns_powershift_reverser_failure_branch1_stage2_description",
                    "rms_breakdowns_powershift_reverser_failure_branch2_stage2_description"
                },
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.POWERSHIFT_REVERSER_FAILURE,
                repairPrice = stagePartPrices.POWERSHIFT_REVERSER_FAILURE[2],
                effects = {
                    { id = "TRANSMISSION_SLIP_EFFECT", value = 0.4, aggregation = "max", branch = 1 },
                    { id = "POWERSHIFT_ENGAGEMENT_LAG_AND_HARSH_EFFECT", value = 0.5, aggregation = "max", extraData = { duration = 1000, timer = 0, backup = 0, status = "IDLE" }, branch = 2 }
                },
                indicators = {
                    { id = db.TRANSMISSION, color = color.WARNING, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_powershift_reverser_failure_branch1_stage3_description",
                branchDescriptions = {
                    "rms_breakdowns_powershift_reverser_failure_branch1_stage3_description",
                    "rms_breakdowns_powershift_reverser_failure_branch2_stage3_description"
                },
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.POWERSHIFT_REVERSER_FAILURE,
                repairPrice = stagePartPrices.POWERSHIFT_REVERSER_FAILURE[3],
                effects = {
                    { id = "TRANSMISSION_SLIP_EFFECT", value = 0.6, aggregation = "max", branch = 1 },
                    { id = "POWERSHIFT_ENGAGEMENT_LAG_AND_HARSH_EFFECT", value = 0.99, aggregation = "max", extraData = { duration = 1500, timer = 0, backup = 0, status = "IDLE" }, branch = 2 }
                },
                indicators = {
                    { id = db.TRANSMISSION, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_powershift_reverser_failure_branch1_stage4_description",
                branchDescriptions = {
                    "rms_breakdowns_powershift_reverser_failure_branch1_stage4_description",
                    "rms_breakdowns_powershift_reverser_failure_branch2_stage4_description"
                },
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = stagePartPrices.POWERSHIFT_REVERSER_FAILURE[4],
                effects = {
                    { id = "TRANSMISSION_SLIP_EFFECT", value = 1.0, aggregation = "max", extraData = { disableAi = true },
                        branch = 1 },
                    { id = "POWERSHIFT_ENGAGEMENT_LAG_AND_HARSH_EFFECT", value = 1.0, aggregation = "max",
                        extraData = { duration = 0, timer = 0, disableAi = true, status = "IDLE" }, branch = 2 },
                    { id = "DRIVE_LOSS_EFFECT", value = 1, aggregation = "max", extraData = { disableAi = true } }
                },
                indicators = {
                    { id = db.TRANSMISSION, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            }
        }
    },

    TRANSMISSION_CONTROL_FAILURE = {
        isSelectable = true,
        system = systems.TRANSMISSION,
        part = parts.TRANSMISSION_CONTROL,
        isApplicable = isPowershiftBreakdownApplicable,
        causes = { primary = {}, secondary = { "pof", "sf", "ctf", "flf", "hfbf" } },
        component = "POWERSHIFT_REPLACEMENT_BUDGET",
        branches = 2,
        isCanProgress = function(vehicle)
            return vehicle:getLastSpeed() > 0.01
        end,
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_transmission_control_failure_branch1_stage1_description",
                branchDescriptions = {
                    "rms_breakdowns_transmission_control_failure_branch1_stage1_description",
                    "rms_breakdowns_transmission_control_failure_branch2_stage1_description"
                },
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.TRANSMISSION_CONTROL_FAILURE,
                repairPrice = stagePartPrices.TRANSMISSION_CONTROL_FAILURE[1],
                effects = {
                    { id = "POWERSHIFT_ENGAGEMENT_LAG_AND_HARSH_EFFECT", value = 0.2, aggregation = "max", extraData = { duration = 700, timer = 0, backup = 0, status = "IDLE" }, branch = 1 },
                    { id = "GEAR_SHIFT_FAILURE_CHANCE", value = 0.1, aggregation = "max", extraData = { duration = 1500, timer = 0, status = "IDLE" }, branch = 2 }
                }
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_transmission_control_failure_branch1_stage2_description",
                branchDescriptions = {
                    "rms_breakdowns_transmission_control_failure_branch1_stage2_description",
                    "rms_breakdowns_transmission_control_failure_branch2_stage2_description"
                },
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.TRANSMISSION_CONTROL_FAILURE,
                repairPrice = stagePartPrices.TRANSMISSION_CONTROL_FAILURE[2],
                effects = {
                    { id = "POWERSHIFT_ENGAGEMENT_LAG_AND_HARSH_EFFECT", value = 0.5, aggregation = "max", extraData = { duration = 1000, timer = 0, backup = 0, status = "IDLE" }, branch = 1 },
                    { id = "GEAR_SHIFT_FAILURE_CHANCE", value = 0.2, aggregation = "max", extraData = { duration = 1800, timer = 0, status = "IDLE" }, branch = 2 }
                },
                indicators = {
                    { id = db.TRANSMISSION, color = color.WARNING, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_transmission_control_failure_branch1_stage3_description",
                branchDescriptions = {
                    "rms_breakdowns_transmission_control_failure_branch1_stage3_description",
                    "rms_breakdowns_transmission_control_failure_branch2_stage3_description"
                },
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.TRANSMISSION_CONTROL_FAILURE,
                repairPrice = stagePartPrices.TRANSMISSION_CONTROL_FAILURE[3],
                effects = {
                    { id = "POWERSHIFT_ENGAGEMENT_LAG_AND_HARSH_EFFECT", value = 0.99, aggregation = "max", extraData = { duration = 1500, timer = 0, backup = 0, status = "IDLE" }, branch = 1 },
                    { id = "GEAR_SHIFT_FAILURE_CHANCE", value = 0.5, aggregation = "max", extraData = { duration = 2200, timer = 0, status = "IDLE" }, branch = 2 }
                },
                indicators = {
                    { id = db.TRANSMISSION, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_transmission_control_failure_branch1_stage4_description",
                branchDescriptions = {
                    "rms_breakdowns_transmission_control_failure_branch1_stage4_description",
                    "rms_breakdowns_transmission_control_failure_branch2_stage4_description"
                },
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = stagePartPrices.TRANSMISSION_CONTROL_FAILURE[4],
                effects = {
                    { id = "POWERSHIFT_ENGAGEMENT_LAG_AND_HARSH_EFFECT", value = 1.0, aggregation = "max", extraData = { duration = 0, timer = 0, disableAi = true, status = "IDLE" }, branch = 1 },
                    { id = "GEAR_SHIFT_FAILURE_CHANCE", value = 1.0, aggregation = "max",
                        extraData = { timer = 0, disableAi = true, duration = 2200, status = "IDLE" }, branch = 2 }
                },
                indicators = {
                    { id = db.TRANSMISSION, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            }
        }
    },

    TRANSMISSION_SENSOR_FAILURE = {
        isSelectable = true,
        system = systems.TRANSMISSION,
        part = parts.TRANSMISSION_SENSORS,
        isApplicable = function(vehicle)
            if hasCVTAddon(vehicle) or getIsElectricVehicle(vehicle) or not RMS_Utils.getUsesEngineECUProfile(vehicle) then return false end
            local motor = vehicle:getMotor()
            return motor ~= nil and (motor.gearType == VehicleMotor.TRANSMISSION_TYPE.POWERSHIFT
                or motor.groupType == VehicleMotor.TRANSMISSION_TYPE.POWERSHIFT)
        end,
        causes = { primary = { "hotf" }, secondary = { "ctf" } },
        component = "TRANSDUCER",
        branches = 2,
        isCanProgress = function(vehicle)
            return vehicle:getLastSpeed() > 0.01
        end,
        stages = {
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_transmission_sensor_failure_branch1_stage1_description",
                branchDescriptions = {
                    "rms_breakdowns_transmission_sensor_failure_branch1_stage1_description",
                    "rms_breakdowns_transmission_sensor_failure_branch2_stage1_description"
                },
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.TRANSMISSION_SENSOR_FAILURE,
                repairPrice = stagePartPrices.TRANSMISSION_SENSOR_FAILURE[1],
                effects = {
                    { id = "GEAR_SHIFT_FAILURE_CHANCE", value = 0.2, aggregation = "max", extraData = { duration = 1800, timer = 0, status = "IDLE" }, branch = 1 },
                    { id = "POWERSHIFT_ENGAGEMENT_LAG_AND_HARSH_EFFECT", value = 0.5, aggregation = "max", extraData = { duration = 1000, timer = 0, backup = 0, status = "IDLE" }, branch = 2 }
                },
                indicators = {
                    { id = db.TRANSMISSION, color = color.WARNING, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_transmission_sensor_failure_branch1_stage2_description",
                branchDescriptions = {
                    "rms_breakdowns_transmission_sensor_failure_branch1_stage2_description",
                    "rms_breakdowns_transmission_sensor_failure_branch2_stage2_description"
                },
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = stagePartPrices.TRANSMISSION_SENSOR_FAILURE[2],
                effects = {
                    { id = "GEAR_SHIFT_FAILURE_CHANCE", value = 0.5, aggregation = "max", extraData = { duration = 2200, timer = 0, status = "IDLE" }, branch = 1 },
                    { id = "POWERSHIFT_ENGAGEMENT_LAG_AND_HARSH_EFFECT", value = 0.99, aggregation = "max", extraData = { duration = 1500, timer = 0, backup = 0, status = "IDLE" }, branch = 2 }
                },
                indicators = {
                    { id = db.TRANSMISSION, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            }
        }
    },

    CVT_SENSOR_FAILURE = {
        isSelectable = true,
        system = systems.TRANSMISSION,
        part = parts.TRANSMISSION_SENSORS,
        isApplicable = function(vehicle)
            return isVariatorBreakdownApplicable(vehicle) and not getIsElectricVehicle(vehicle)
                and RMS_Utils.getUsesEngineECUProfile(vehicle)
        end,
        causes = { primary = { "hotf" }, secondary = { "ctf" } },
        component = "TRANSDUCER",
        branches = 2,
        isCanProgress = function(vehicle)
            return vehicle:getLastSpeed() > 0.01
        end,
        stages = {
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_cvt_sensor_failure_branch1_stage1_description",
                branchDescriptions = {
                    "rms_breakdowns_cvt_sensor_failure_branch1_stage1_description",
                    "rms_breakdowns_cvt_sensor_failure_branch2_stage1_description"
                },
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.CVT_SENSOR_FAILURE,
                repairPrice = stagePartPrices.CVT_SENSOR_FAILURE[1],
                effects = {
                    { id = "CVT_MAX_RATIO_MODIFIER", value = 0.4, aggregation = "max" }
                },
                indicators = {
                    { id = db.TRANSMISSION, color = color.WARNING, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_cvt_sensor_failure_branch1_stage2_description",
                branchDescriptions = {
                    "rms_breakdowns_cvt_sensor_failure_branch1_stage2_description",
                    "rms_breakdowns_cvt_sensor_failure_branch2_stage2_description"
                },
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = stagePartPrices.CVT_SENSOR_FAILURE[2],
                effects = {
                    { id = "CVT_MAX_RATIO_MODIFIER", value = 0.8, aggregation = "max" }
                },
                indicators = {
                    { id = db.TRANSMISSION, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            }
        }
    },

    TRANSMISSION_PUMP_MALFUNCTION = {
        isSelectable = true,
        system = systems.TRANSMISSION,
        part = parts.TRANSMISSION_PUMP,
        isApplicable = function(vehicle)
            if hasCVTAddon(vehicle) or getIsElectricVehicle(vehicle) then return false end
            local motor = vehicle:getMotor()
            return motor ~= nil and (motor.minForwardGearRatio ~= nil
                or motor.gearType == VehicleMotor.TRANSMISSION_TYPE.POWERSHIFT
                or motor.groupType == VehicleMotor.TRANSMISSION_TYPE.POWERSHIFT)
        end,
        causes = { primary = {}, secondary = { "pof", "sf", "ctf", "flf", "hfbf" } },
        component = "POWERSHIFT_REPLACEMENT_BUDGET",
        isCanProgress = function(vehicle)
            return vehicle:getLastSpeed() > 0.01
        end,
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_transmission_pump_malfunction_stage1_description",
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.TRANSMISSION_PUMP_MALFUNCTION,
                repairPrice = stagePartPrices.TRANSMISSION_PUMP_MALFUNCTION[1],
                effects = {
                    { id = "POWERSHIFT_ENGAGEMENT_LAG_AND_HARSH_EFFECT", value = 0.2, aggregation = "max", extraData = { duration = 700, timer = 0, backup = 0, status = "IDLE" } },
                    { id = "CVT_PRESSURE_DROP_CHANCE", value = 2.0, aggregation = "min", extraData = { duration = 200, timer = 0, status = "IDLE" } },
                    { id = "TRANSMISSION_PUMP_NOISE_EFFECT", value = 0.3, aggregation = "max" }
                }
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_transmission_pump_malfunction_stage2_description",
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.TRANSMISSION_PUMP_MALFUNCTION,
                repairPrice = stagePartPrices.TRANSMISSION_PUMP_MALFUNCTION[2],
                effects = {
                    { id = "POWERSHIFT_ENGAGEMENT_LAG_AND_HARSH_EFFECT", value = 0.5, aggregation = "max", extraData = { duration = 1000, timer = 0, backup = 0, status = "IDLE" } },
                    { id = "CVT_PRESSURE_DROP_CHANCE", value = 1.0, aggregation = "min", extraData = { duration = 250, timer = 0, status = "IDLE" } },
                    { id = "TRANSMISSION_PUMP_NOISE_EFFECT", value = 0.5, aggregation = "max" }
                },
                indicators = {
                    { id = db.TRANSMISSION, color = color.WARNING, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_transmission_pump_malfunction_stage3_description",
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.TRANSMISSION_PUMP_MALFUNCTION,
                repairPrice = stagePartPrices.TRANSMISSION_PUMP_MALFUNCTION[3],
                effects = {
                    { id = "POWERSHIFT_ENGAGEMENT_LAG_AND_HARSH_EFFECT", value = 0.99, aggregation = "max", extraData = { duration = 1500, timer = 0, backup = 0, status = "IDLE" } },
                    { id = "CVT_PRESSURE_DROP_CHANCE", value = 0.5, aggregation = "min", extraData = { duration = 300, timer = 0, status = "IDLE" } },
                    { id = "TRANSMISSION_PUMP_NOISE_EFFECT", value = 0.8, aggregation = "max" }
                },
                indicators = {
                    { id = db.TRANSMISSION, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_transmission_pump_malfunction_stage4_description",
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = stagePartPrices.TRANSMISSION_PUMP_MALFUNCTION[4],
                effects = {
                    { id = "POWERSHIFT_ENGAGEMENT_LAG_AND_HARSH_EFFECT", value = 1.0, aggregation = "max", extraData = { duration = 0, timer = 0, disableAi = true, status = "IDLE" } },
                    { id = "CVT_PRESSURE_DROP_CHANCE", value = 0.1, aggregation = "min", extraData = { duration = 300, timer = 0, status = "IDLE" } },
                    { id = "DRIVE_LOSS_EFFECT", value = 1, aggregation = "max", extraData = { disableAi = true } },
                    { id = "TRANSMISSION_PUMP_NOISE_EFFECT", value = 1.0, aggregation = "max" }
                },
                indicators = {
                    { id = db.TRANSMISSION, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            }
        }
    },

    HYDROSTATIC_UNIT_MALFUNCTION = {
        isSelectable = true,
        system = systems.TRANSMISSION,
        part = parts.HYDROSTATIC_UNIT,
        isApplicable = isVariatorBreakdownApplicable,
        causes = { primary = { "lf" }, secondary = { "hotf", "pof" } },
        component = "CVT_REPLACEMENT_BUDGET",
        isCanProgress = function(vehicle)
            return vehicle:getLastSpeed() > 0.01
        end,
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_hydrostatic_unit_malfunction_stage1_description",
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.HYDROSTATIC_UNIT_MALFUNCTION,
                repairPrice = stagePartPrices.HYDROSTATIC_UNIT_MALFUNCTION[1],
                effects = {
                    { id = "CVT_SLIP_EFFECT", value = 0.1, aggregation = "max" },
                    { id = "TRANSMISSION_HEAT_MODIFIER", value = 0.05, aggregation = "sum" },
                    { id = "CVT_MAX_RATIO_MODIFIER", value = 0.3, aggregation = "max" },
                    { id = "HYDROSTATIC_WHINE_NOISE_EFFECT", value = 0.3, aggregation = "max" }
                }
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_hydrostatic_unit_malfunction_stage2_description",
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.HYDROSTATIC_UNIT_MALFUNCTION,
                repairPrice = stagePartPrices.HYDROSTATIC_UNIT_MALFUNCTION[2],
                effects = {
                    { id = "CVT_SLIP_EFFECT", value = 0.2, aggregation = "max" },
                    { id = "FUEL_CONSUMPTION_MODIFIER", value = 0.2, aggregation = "sum" },
                    { id = "TRANSMISSION_HEAT_MODIFIER", value = 0.1, aggregation = "sum" },
                    { id = "CVT_MAX_RATIO_MODIFIER", value = 0.4, aggregation = "max" },
                    { id = "HYDROSTATIC_WHINE_NOISE_EFFECT", value = 0.5, aggregation = "max" }
                },
                indicators = {
                    { id = db.TRANSMISSION, color = color.WARNING, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_hydrostatic_unit_malfunction_stage3_description",
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.HYDROSTATIC_UNIT_MALFUNCTION,
                repairPrice = stagePartPrices.HYDROSTATIC_UNIT_MALFUNCTION[3],
                effects = {
                    { id = "CVT_SLIP_EFFECT", value = 0.5, aggregation = "max" },
                    { id = "FUEL_CONSUMPTION_MODIFIER", value = 0.25, aggregation = "sum" },
                    { id = "TRANSMISSION_HEAT_MODIFIER", value = 0.15, aggregation = "sum" },
                    { id = "CVT_MAX_RATIO_MODIFIER", value = 0.5, aggregation = "max" },
                    { id = "HYDROSTATIC_WHINE_NOISE_EFFECT", value = 0.8, aggregation = "max" }
                },
                indicators = {
                    { id = db.TRANSMISSION, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_hydrostatic_unit_malfunction_stage4_description",
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = stagePartPrices.HYDROSTATIC_UNIT_MALFUNCTION[4],
                effects = {
                    { id = "CVT_SLIP_EFFECT", value = 1.0, aggregation = "max", extraData = { disableAi = true } },
                    { id = "CVT_MAX_RATIO_MODIFIER", value = 0.8, aggregation = "max" },
                    { id = "DRIVE_LOSS_EFFECT", value = 1, aggregation = "max", extraData = { disableAi = true } },
                    { id = "HYDROSTATIC_WHINE_NOISE_EFFECT", value = 1.0, aggregation = "max" }
                },
                indicators = {
                    { id = db.TRANSMISSION, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            }
        }
    },

    CVT_HYDRAULIC_CONTROL_VALVE_MALFUNCTION = {
        isSelectable = true,
        system = systems.TRANSMISSION,
        part = parts.CVT_HYDRAULIC_CONTROL_VALVE,
        isApplicable = isVariatorBreakdownApplicable,
        causes = { primary = { "hotf" }, secondary = { "ctf", "sf", "hfbf" } },
        component = "CVT_REPLACEMENT_BUDGET",
        isCanProgress = function(vehicle)
            return vehicle:getLastSpeed() > 0.01
        end,
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_hydraulic_control_valve_malfunction_stage1_description",
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.CVT_HYDRAULIC_CONTROL_VALVE_MALFUNCTION,
                repairPrice = stagePartPrices.CVT_HYDRAULIC_CONTROL_VALVE_MALFUNCTION[1],
                effects = {
                    { id = "CVT_PRESSURE_DROP_CHANCE", value = 2.0, aggregation = "min", extraData = { duration = 200, timer = 0, status = "IDLE" } },
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.05, aggregation = "sum" },
                    { id = "CVT_MAX_RATIO_MODIFIER", value = 0.3, aggregation = "max" }
                }
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_hydraulic_control_valve_malfunction_stage2_description",
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.CVT_HYDRAULIC_CONTROL_VALVE_MALFUNCTION,
                repairPrice = stagePartPrices.CVT_HYDRAULIC_CONTROL_VALVE_MALFUNCTION[2],
                effects = {
                    { id = "CVT_PRESSURE_DROP_CHANCE", value = 1.0, aggregation = "min", extraData = { duration = 250, timer = 0, status = "IDLE" } },
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.1, aggregation = "sum" },
                    { id = "TRANSMISSION_HEAT_MODIFIER", value = 0.05, aggregation = "sum" },
                    { id = "CVT_MAX_RATIO_MODIFIER", value = 0.4, aggregation = "max" }
                },
                indicators = {
                    { id = db.TRANSMISSION, color = color.WARNING, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_hydraulic_control_valve_malfunction_stage3_description",
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.CVT_HYDRAULIC_CONTROL_VALVE_MALFUNCTION,
                repairPrice = stagePartPrices.CVT_HYDRAULIC_CONTROL_VALVE_MALFUNCTION[3],
                effects = {
                    { id = "CVT_PRESSURE_DROP_CHANCE", value = 0.5, aggregation = "min", extraData = { duration = 300, timer = 0, status = "IDLE" } },
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.2, aggregation = "sum" },
                    { id = "TRANSMISSION_HEAT_MODIFIER", value = 0.1, aggregation = "sum" },
                    { id = "CVT_MAX_RATIO_MODIFIER", value = 0.5, aggregation = "max" }
                },
                indicators = {
                    { id = db.TRANSMISSION, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_hydraulic_control_valve_malfunction_stage4_description",
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = stagePartPrices.CVT_HYDRAULIC_CONTROL_VALVE_MALFUNCTION[4],
                effects = {
                    { id = "CVT_MAX_RATIO_MODIFIER", value = 0.8, aggregation = "max" },
                    { id = "TRANSMISSION_HEAT_MODIFIER", value = 0.15, aggregation = "sum" },
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.3, aggregation = "sum" },
                    { id = "CVT_PRESSURE_DROP_CHANCE", value = 0.1, aggregation = "min", extraData = { duration = 300, timer = 0, status = "IDLE" } },
                    { id = "ENGINE_LIMP_EFFECT", value = -0.2, aggregation = "min",
                        extraData = { disableAi = true, reason = "BREAKDOWN" } }
                },
                indicators = {
                    { id = db.TRANSMISSION, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            }
        }
    },

    TRANSMISSION_OIL_LEAK = {
        isSelectable = true,
        system = systems.TRANSMISSION,
        part = parts.TRANSMISSION_SEAL,
        isApplicable = function(vehicle)
            return true
        end,
        causes = { primary = { "hotf", "ctf" }, secondary = {} },
        component = "O_RING",
        isCanProgress = function(vehicle)
            return vehicle:getIsMotorStarted()
        end,
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_transmission_oil_leak_stage1_description",
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.TRANSMISSION_OIL_LEAK,
                repairPrice = stagePartPrices.TRANSMISSION_OIL_LEAK[1],
                effects = {
                    { id = "TRANSMISSION_OIL_LEAK_RATE", value = 0.02, aggregation = "max" }
                },
                inspection = {
                    { additional = "rms_inspection_hint_transmission_oil_leak_stage1" }
                }
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_transmission_oil_leak_stage2_description",
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.TRANSMISSION_OIL_LEAK,
                repairPrice = stagePartPrices.TRANSMISSION_OIL_LEAK[2],
                effects = {
                    { id = "TRANSMISSION_OIL_LEAK_RATE", value = 0.08, aggregation = "max" }
                },
                inspection = {
                    { additional = "rms_inspection_hint_transmission_oil_leak_stage2" }
                },
                indicators = {
                    { id = db.WARNING, color = color.WARNING, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_transmission_oil_leak_stage3_description",
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.TRANSMISSION_OIL_LEAK,
                repairPrice = stagePartPrices.TRANSMISSION_OIL_LEAK[3],
                effects = {
                    { id = "TRANSMISSION_OIL_LEAK_RATE", value = 0.25, aggregation = "max" }
                },
                inspection = {
                    { additional = "rms_inspection_hint_transmission_oil_leak_stage3" }
                },
                indicators = {
                    { id = db.TRANSMISSION, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_transmission_oil_leak_stage4_description",
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = stagePartPrices.TRANSMISSION_OIL_LEAK[4],
                effects = {
                    { id = "TRANSMISSION_OIL_LEAK_RATE", value = 0.8, aggregation = "max" }
                },
                inspection = {
                    { additional = "rms_inspection_hint_transmission_oil_leak_stage4" }
                },
                indicators = {
                    { id = db.TRANSMISSION, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            }
        }
    },

    TRANSMISSION_OIL_COOLER_MALFUNCTION = {
        isSelectable = true,
        system = systems.TRANSMISSION,
        part = parts.TRANSMISSION_OIL_COOLER,
        isApplicable = isVariatorBreakdownApplicable,
        causes = { primary = {}, secondary = {} },
        component = "CONTROL_VALVE",
        isCanProgress = function(vehicle)
            return vehicle:getIsMotorStarted()
        end,
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_transmission_oil_cooler_malfunction_stage1_description",
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.TRANSMISSION_OIL_COOLER_MALFUNCTION,
                repairPrice = stagePartPrices.TRANSMISSION_OIL_COOLER_MALFUNCTION[1],
                effects = {
                    { id = "TRANSMISSION_HEAT_MODIFIER", value = 0.05, aggregation = "sum" }
                }
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_transmission_oil_cooler_malfunction_stage2_description",
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.TRANSMISSION_OIL_COOLER_MALFUNCTION,
                repairPrice = stagePartPrices.TRANSMISSION_OIL_COOLER_MALFUNCTION[2],
                effects = {
                    { id = "TRANSMISSION_HEAT_MODIFIER", value = 0.1, aggregation = "sum" }
                },
                indicators = {
                    { id = db.WARNING, color = color.WARNING, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_transmission_oil_cooler_malfunction_stage3_description",
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.TRANSMISSION_OIL_COOLER_MALFUNCTION,
                repairPrice = stagePartPrices.TRANSMISSION_OIL_COOLER_MALFUNCTION[3],
                effects = {
                    { id = "TRANSMISSION_HEAT_MODIFIER", value = 0.15, aggregation = "sum" }
                },
                indicators = {
                    { id = db.TRANSMISSION, color = color.WARNING, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_transmission_oil_cooler_malfunction_stage4_description",
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = stagePartPrices.TRANSMISSION_OIL_COOLER_MALFUNCTION[4],
                effects = {
                    { id = "TRANSMISSION_HEAT_MODIFIER", value = 0.2, aggregation = "sum" }
                },
                indicators = {
                    { id = db.TRANSMISSION, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            }
        }
    },

    TRANSMISSION_FILTER_CLOGGING = {
        isSelectable = true,
        system = systems.TRANSMISSION,
        part = parts.TRANSMISSION_FILTER,
        isApplicable = isTransmissionFilterApplicable,
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_transmission_filter_clogging_stage1_description",
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = stagePartPrices.TRANSMISSION_FILTER_CLOGGING[1],
                effects = {},
                indicators = {
                    { id = db.TRANSMISSION, color = color.WARNING, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_transmission_filter_clogging_stage2_description",
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = stagePartPrices.TRANSMISSION_FILTER_CLOGGING[2],
                effects = {},
                indicators = {
                    { id = db.TRANSMISSION, color = color.WARNING, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_transmission_filter_clogging_stage3_description",
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = stagePartPrices.TRANSMISSION_FILTER_CLOGGING[3],
                effects = {},
                indicators = {
                    { id = db.TRANSMISSION, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_transmission_filter_clogging_stage4_description",
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = stagePartPrices.TRANSMISSION_FILTER_CLOGGING[4],
                effects = {},
                indicators = {
                    { id = db.TRANSMISSION, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            }
        }
    },

    REAR_BEVEL_GEAR_FAILURE = {
        isSelectable = true,
        system = systems.TRANSMISSION,
        part = parts.REAR_BEVEL_GEAR,
        isApplicable = function(vehicle)
            local motorized = vehicle.spec_motorized
            if motorized == nil or motorized.differentials == nil then return false end
            for _, differential in ipairs(motorized.differentials) do
                if differential.diffIndex1IsWheel and differential.diffIndex2IsWheel then return true end
            end
            return false
        end,
        causes = { primary = { "pof", "htf" }, secondary = { "sf", "flf", "hfbf" } },
        component = "GEAR",
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_rear_bevel_gear_failure_stage1_description",
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.REAR_BEVEL_GEAR_FAILURE,
                repairPrice = stagePartPrices.REAR_BEVEL_GEAR_FAILURE[1],
                effects = {
                    { id = "GEAR_WHINE_NOISE_EFFECT", value = 0.3, aggregation = "max" }
                }
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_rear_bevel_gear_failure_stage2_description",
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.REAR_BEVEL_GEAR_FAILURE,
                repairPrice = stagePartPrices.REAR_BEVEL_GEAR_FAILURE[2],
                effects = {
                    { id = "GEAR_WHINE_NOISE_EFFECT", value = 0.8, aggregation = "max" }
                }
            },
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_rear_bevel_gear_failure_stage3_description",
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.REAR_BEVEL_GEAR_FAILURE,
                repairPrice = stagePartPrices.REAR_BEVEL_GEAR_FAILURE[3],
                effects = {
                    { id = "GEAR_WHINE_NOISE_EFFECT", value = 1.0, aggregation = "max" }
                }
            },
            {
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_rear_bevel_gear_failure_stage4_description",
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = stagePartPrices.REAR_BEVEL_GEAR_FAILURE[4],
                effects = {
                    { id = "DRIVE_LOSS_EFFECT", value = 1, aggregation = "max", extraData = { disableAi = true } }
                }
            }
        }
    },

    FINAL_DRIVE_FAILURE = {
        isSelectable = true,
        system = systems.TRANSMISSION,
        part = parts.FINAL_DRIVES,
        isApplicable = function(vehicle)
            local motorized = vehicle.spec_motorized
            if motorized == nil or motorized.differentials == nil then return false end
            for _, differential in ipairs(motorized.differentials) do
                if differential.diffIndex1IsWheel and differential.diffIndex2IsWheel then return true end
            end
            return false
        end,
        causes = { primary = { "pof", "htf" }, secondary = { "sf", "flf", "hfbf" } },
        component = "GEAR",
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_final_drive_failure_stage1_description",
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.FINAL_DRIVE_FAILURE,
                repairPrice = stagePartPrices.FINAL_DRIVE_FAILURE[1],
                effects = {
                    { id = "GEAR_WHINE_NOISE_EFFECT", value = 0.3, aggregation = "max" }
                }
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_final_drive_failure_stage2_description",
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.FINAL_DRIVE_FAILURE,
                repairPrice = stagePartPrices.FINAL_DRIVE_FAILURE[2],
                effects = {
                    { id = "GEAR_WHINE_NOISE_EFFECT", value = 0.8, aggregation = "max" }
                }
            },
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_final_drive_failure_stage3_description",
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.FINAL_DRIVE_FAILURE,
                repairPrice = stagePartPrices.FINAL_DRIVE_FAILURE[3],
                effects = {
                    { id = "GEAR_WHINE_NOISE_EFFECT", value = 1.0, aggregation = "max" }
                }
            },
            {
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_final_drive_failure_stage4_description",
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = stagePartPrices.FINAL_DRIVE_FAILURE[4],
                effects = {
                    { id = "DRIVE_LOSS_EFFECT", value = 1, aggregation = "max", extraData = { disableAi = true } }
                }
            }
        }
    },

    DIFFERENTIAL_FAILURE = {
        isSelectable = true,
        system = systems.TRANSMISSION,
        part = parts.DIFFERENTIAL,
        isApplicable = function(vehicle)
            local motorized = vehicle.spec_motorized
            if motorized == nil or motorized.differentials == nil then return false end
            for _, differential in ipairs(motorized.differentials) do
                if differential.diffIndex1IsWheel and differential.diffIndex2IsWheel then return true end
            end
            return false
        end,
        causes = { primary = { "pof", "htf" }, secondary = { "sf", "flf", "hfbf" } },
        component = "GEAR",
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_differential_failure_stage1_description",
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.DIFFERENTIAL_FAILURE,
                repairPrice = stagePartPrices.DIFFERENTIAL_FAILURE[1],
                effects = {
                    { id = "GEAR_WHINE_NOISE_EFFECT", value = 0.3, aggregation = "max" }
                }
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_differential_failure_stage2_description",
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.DIFFERENTIAL_FAILURE,
                repairPrice = stagePartPrices.DIFFERENTIAL_FAILURE[2],
                effects = {
                    { id = "GEAR_WHINE_NOISE_EFFECT", value = 0.8, aggregation = "max" }
                }
            },
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_differential_failure_stage3_description",
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.DIFFERENTIAL_FAILURE,
                repairPrice = stagePartPrices.DIFFERENTIAL_FAILURE[3],
                effects = {
                    { id = "GEAR_WHINE_NOISE_EFFECT", value = 1.0, aggregation = "max" }
                }
            },
            {
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_differential_failure_stage4_description",
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = stagePartPrices.DIFFERENTIAL_FAILURE[4],
                effects = {
                    { id = "DRIVE_LOSS_EFFECT", value = 1, aggregation = "max", extraData = { disableAi = true } }
                }
            }
        }
    },

    FRONT_AXLE_SHAFT_WEAR = {
        isSelectable = true,
        system = systems.TRANSMISSION,
        part = parts.FRONT_AXLE_SHAFT,
        isApplicable = function(vehicle)
            return RMS_Drivetrain.getIsAvailable(vehicle) and RMS_Drivetrain.getHasCenterDifferential(vehicle)
        end,
        causes = { primary = { "pof", "dwf" }, secondary = { "wsf", "sf" } },
        component = "COUPLING",
        isCanProgress = function(vehicle)
            return vehicle:getLastSpeed() > 0.01
        end,
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_front_axle_shaft_wear_stage1_description",
                inspection = { { additional = "rms_inspection_hint_front_axle_shaft_wear_stage1" } },
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.FRONT_AXLE_SHAFT_WEAR,
                repairPrice = stagePartPrices.FRONT_AXLE_SHAFT_WEAR[1],
                effects = {
                    { id = "FRONT_AXLE_SHAFT_NOISE_EFFECT", value = 0.3, aggregation = "max" }
                }
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_front_axle_shaft_wear_stage2_description",
                inspection = { { additional = "rms_inspection_hint_front_axle_shaft_wear_stage2" } },
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.FRONT_AXLE_SHAFT_WEAR,
                repairPrice = stagePartPrices.FRONT_AXLE_SHAFT_WEAR[2],
                effects = {
                    { id = "FRONT_AXLE_SHAFT_NOISE_EFFECT", value = 0.5, aggregation = "max" }
                }
            },
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_front_axle_shaft_wear_stage3_description",
                inspection = { { additional = "rms_inspection_hint_front_axle_shaft_wear_stage3" } },
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.FRONT_AXLE_SHAFT_WEAR,
                repairPrice = stagePartPrices.FRONT_AXLE_SHAFT_WEAR[3],
                effects = {
                    { id = "FRONT_AXLE_SHAFT_NOISE_EFFECT", value = 0.8, aggregation = "max" }
                }
            },
            {
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_front_axle_shaft_wear_stage4_description",
                inspection = { { additional = "rms_inspection_hint_front_axle_shaft_wear_stage4" } },
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = stagePartPrices.FRONT_AXLE_SHAFT_WEAR[4],
                effects = {
                    { id = "FOUR_WD_ENGAGE_FAILURE", value = 1, aggregation = "boolean_or" }
                }
            }
        }
    },

    AXLE_BEARING_WEAR = {
        isSelectable = true,
        system = systems.TRANSMISSION,
        part = parts.AXLE_BEARINGS,
        isApplicable = function(vehicle)
            local motorized = vehicle.spec_motorized
            if motorized == nil or motorized.differentials == nil then return false end
            for _, differential in ipairs(motorized.differentials) do
                if differential.diffIndex1IsWheel and differential.diffIndex2IsWheel then return true end
            end
            return false
        end,
        causes = { primary = { "pof", "htf" }, secondary = { "sf", "flf", "hfbf" } },
        component = "ROLLER_BEARING",
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_axle_bearing_wear_stage1_description",
                inspection = { { additional = "rms_inspection_hint_axle_bearing_wear_stage1" } },
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.AXLE_BEARING_WEAR,
                repairPrice = stagePartPrices.AXLE_BEARING_WEAR[1],
                effects = {
                    { id = "GEAR_WHINE_NOISE_EFFECT", value = 0.3, aggregation = "max" }
                }
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_axle_bearing_wear_stage2_description",
                inspection = { { additional = "rms_inspection_hint_axle_bearing_wear_stage2" } },
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.AXLE_BEARING_WEAR,
                repairPrice = stagePartPrices.AXLE_BEARING_WEAR[2],
                effects = {
                    { id = "GEAR_WHINE_NOISE_EFFECT", value = 0.5, aggregation = "max" }
                }
            },
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_axle_bearing_wear_stage3_description",
                inspection = { { additional = "rms_inspection_hint_axle_bearing_wear_stage3" } },
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.AXLE_BEARING_WEAR,
                repairPrice = stagePartPrices.AXLE_BEARING_WEAR[3],
                effects = {
                    { id = "GEAR_WHINE_NOISE_EFFECT", value = 0.8, aggregation = "max" }
                }
            },
            {
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_axle_bearing_wear_stage4_description",
                inspection = { { additional = "rms_inspection_hint_axle_bearing_wear_stage4" } },
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = stagePartPrices.AXLE_BEARING_WEAR[4],
                effects = {
                    { id = "DRIVE_LOSS_EFFECT", value = 1, aggregation = "max", extraData = { disableAi = true } }
                }
            }
        }
    },

    DIFF_LOCK_CONTROL_FAILURE = {
        isSelectable = true,
        system = systems.TRANSMISSION,
        part = parts.DIFF_LOCK_CONTROL,
        isApplicable = function(vehicle)
            return RMS_Drivetrain.getIsAvailable(vehicle)
        end,
        causes = { primary = { "hotf" }, secondary = { "ctf", "sf", "hfbf" } },
        component = "SOLENOID_VALVE",
        branches = 2,
        stages = {
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_diff_lock_control_failure_branch1_stage1_description",
                branchDescriptions = {
                    "rms_breakdowns_diff_lock_control_failure_branch1_stage1_description",
                    "rms_breakdowns_diff_lock_control_failure_branch2_stage1_description"
                },
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = stagePartPrices.DIFF_LOCK_CONTROL_FAILURE[1],
                effects = {
                    { id = "DIFF_LOCK_ENGAGE_FAILURE", value = 1, aggregation = "boolean_or", branch = 1 },
                    { id = "DIFF_LOCK_STUCK_ENGAGED", value = 1, aggregation = "boolean_or", branch = 2 }
                },
                indicators = {
                    { id = db.TRANSMISSION, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            }
        }
    },

    FOUR_WD_CONTROL_FAILURE = {
        isSelectable = true,
        system = systems.TRANSMISSION,
        part = parts.FOUR_WD_CONTROL,
        isApplicable = function(vehicle)
            return RMS_Drivetrain.getIsAvailable(vehicle)
                and RMS_Drivetrain.getHasCenterDifferential(vehicle)
        end,
        causes = { primary = { "hotf" }, secondary = { "ctf", "sf", "hfbf" } },
        component = "SOLENOID_VALVE",
        branches = 2,
        stages = {
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_four_wd_control_failure_branch1_stage1_description",
                branchDescriptions = {
                    "rms_breakdowns_four_wd_control_failure_branch1_stage1_description",
                    "rms_breakdowns_four_wd_control_failure_branch2_stage1_description"
                },
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = stagePartPrices.FOUR_WD_CONTROL_FAILURE[1],
                effects = {
                    { id = "FOUR_WD_ENGAGE_FAILURE", value = 1, aggregation = "boolean_or", branch = 1 },
                    { id = "FOUR_WD_STUCK_ENGAGED", value = 1, aggregation = "boolean_or", branch = 2 }
                },
                indicators = {
                    { id = db.TRANSMISSION, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            }
        }
    },

    REDUCER_GEAR_WEAR = {
        isSelectable = true,
        system = systems.TRANSMISSION,
        part = parts.REDUCER,
        isApplicable = isReducerBreakdownApplicable,
        causes = { primary = { "pof", "htf" }, secondary = { "sf", "flf", "hfbf" } },
        component = "GEAR",
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_reducer_gear_wear_stage1_description",
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.REDUCER_GEAR_WEAR,
                repairPrice = stagePartPrices.REDUCER_GEAR_WEAR[1],
                effects = {
                    { id = "GEAR_WHINE_NOISE_EFFECT", value = 1.0, aggregation = "max" }
                }
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_reducer_gear_wear_stage2_description",
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.REDUCER_GEAR_WEAR,
                repairPrice = stagePartPrices.REDUCER_GEAR_WEAR[2],
                effects = {
                    { id = "GEAR_WHINE_NOISE_EFFECT", value = 1.5, aggregation = "max" },
                    { id = "FUEL_CONSUMPTION_MODIFIER", value = 0.05, aggregation = "sum" },
                    { id = "TRANSMISSION_HEAT_MODIFIER", value = 0.05, aggregation = "sum" }
                },
                indicators = {
                    { id = db.TRANSMISSION, color = color.WARNING, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_reducer_gear_wear_stage3_description",
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.REDUCER_GEAR_WEAR,
                repairPrice = stagePartPrices.REDUCER_GEAR_WEAR[3],
                effects = {
                    { id = "GEAR_WHINE_NOISE_EFFECT", value = 2.0, aggregation = "max" },
                    { id = "FUEL_CONSUMPTION_MODIFIER", value = 0.1, aggregation = "sum" },
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.1, aggregation = "sum" },
                    { id = "TRANSMISSION_HEAT_MODIFIER", value = 0.15, aggregation = "sum" }
                },
                indicators = {
                    { id = db.TRANSMISSION, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_reducer_gear_wear_stage4_description",
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = stagePartPrices.REDUCER_GEAR_WEAR[4],
                effects = {
                    { id = "DRIVE_LOSS_EFFECT", value = 1, aggregation = "max", extraData = { disableAi = true } }
                },
                indicators = {
                    { id = db.TRANSMISSION, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            }
        }
    },

    CVT_ADDON_MALFUNCTION = {
        isSelectable = true,
        system = systems.TRANSMISSION,
        part = parts.CVT,
        isApplicable = function(vehicle)
            if hasCVTAddon(vehicle) then return true end
            return false
        end,
        isCanProgress = function(vehicle)
            return false
        end,
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_cvt_addon_malfunction_stage1_description",
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.CVT_ADDON_MALFUNCTION,
                repairPrice = stagePartPrices.CVT_ADDON_MALFUNCTION[1],
                effects = {}
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_cvt_addon_malfunction_stage2_description",
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.CVT_ADDON_MALFUNCTION,
                repairPrice = stagePartPrices.CVT_ADDON_MALFUNCTION[2],
                effects = {},
                indicators = {
                    { id = db.TRANSMISSION, color = color.WARNING, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_cvt_addon_malfunction_stage3_description",
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.CVT_ADDON_MALFUNCTION,
                repairPrice = stagePartPrices.CVT_ADDON_MALFUNCTION[3],
                effects = {},
                indicators = {
                    { id = db.TRANSMISSION, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_cvt_addon_malfunction_stage4_description",
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = stagePartPrices.CVT_ADDON_MALFUNCTION[4],
                effects = {
                    { id = "CVT_SLIP_EFFECT", value = 1.0, aggregation = "max", extraData = { disableAi = true } }
                },
                indicators = {
                    { id = db.TRANSMISSION, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            }
        }
    },

    -- hydraulic system
    HYDRAULIC_PUMP_MALFUNCTION = {
        isSelectable = true,
        system = systems.HYDRAULICS,
        part = parts.HYDRAULIC_PUMP,
        isApplicable = isHydraulicBreakdownApplicable,
        causes = { primary = { "cof", "hof", "sf" }, secondary = { "flf", "hfbf" } },
        component = "CENTRIFUGAL_PUMP",
        branches = 2,
        isCanProgress = function(vehicle)
            local spec = vehicle.spec_RealisticMechanicalSystems
            local breakdown = spec ~= nil and spec.activeBreakdowns ~= nil and spec.activeBreakdowns.HYDRAULIC_PUMP_MALFUNCTION or nil
            return (breakdown == nil or breakdown.branch ~= 2)
                and vehicle:getIsMotorStarted() and vehicle.spec_RealisticMechanicalSystems.isHydraulicActive
        end,
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_hydraulic_pump_malfunction_stage1_description",
                branchDescriptions = {
                    "rms_breakdowns_hydraulic_pump_malfunction_stage1_description",
                    "rms_breakdowns_hydraulic_pump_malfunction_branch2_stage1_description"
                },
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.HYDRAULIC_PUMP_MALFUNCTION,
                repairPrice = stagePartPrices.HYDRAULIC_PUMP_MALFUNCTION[1],
                effects = {
                    { id = "HYDRAULIC_SPEED_MODIFIER", value = -0.2, aggregation = "min", branch = 1 },
                    { id = "HYDRAULIC_SPEED_MODIFIER", value = -1.0, aggregation = "min", extraData = { disableAi = true },
                        branch = 2 },
                    { id = "HYDRAULIC_PUMP_NOISE_EFFECT", value = 0.3, aggregation = "max", branch = 1 }
                },
                indicators = {
                    { id = db.WARNING, color = color.CRITICAL, switchOn = true, switchOff = false, branch = 2 }
                }
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_hydraulic_pump_malfunction_stage2_description",
                branchDescriptions = {
                    "rms_breakdowns_hydraulic_pump_malfunction_stage2_description",
                    "rms_breakdowns_hydraulic_pump_malfunction_branch2_stage1_description"
                },
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.HYDRAULIC_PUMP_MALFUNCTION,
                repairPrice = stagePartPrices.HYDRAULIC_PUMP_MALFUNCTION[2],
                effects = {
                    { id = "HYDRAULIC_SPEED_MODIFIER", value = -0.4, aggregation = "min", branch = 1 },
                    { id = "HYDRAULIC_SPEED_MODIFIER", value = -1.0, aggregation = "min", extraData = { disableAi = true },
                        branch = 2 },
                    { id = "HYDRAULIC_PUMP_NOISE_EFFECT", value = 0.5, aggregation = "max", branch = 1 }
                },
                indicators = {
                    { id = db.WARNING, color = color.WARNING, switchOn = true, switchOff = false, branch = 1 },
                    { id = db.WARNING, color = color.CRITICAL, switchOn = true, switchOff = false, branch = 2 }
                }
            },
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_hydraulic_pump_malfunction_stage3_description",
                branchDescriptions = {
                    "rms_breakdowns_hydraulic_pump_malfunction_stage3_description",
                    "rms_breakdowns_hydraulic_pump_malfunction_branch2_stage1_description"
                },
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.HYDRAULIC_PUMP_MALFUNCTION,
                repairPrice = stagePartPrices.HYDRAULIC_PUMP_MALFUNCTION[3],
                effects = {
                    { id = "HYDRAULIC_SPEED_MODIFIER", value = -0.75, aggregation = "min", branch = 1 },
                    { id = "HYDRAULIC_SPEED_MODIFIER", value = -1.0, aggregation = "min", extraData = { disableAi = true },
                        branch = 2 },
                    { id = "HYDRAULIC_PUMP_NOISE_EFFECT", value = 0.8, aggregation = "max", branch = 1 }
                },
                indicators = {
                    { id = db.WARNING, color = color.CRITICAL, switchOn = true, switchOff = false, branch = 1 },
                    { id = db.WARNING, color = color.CRITICAL, switchOn = true, switchOff = false, branch = 2 }
                }
            },
            {
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_hydraulic_pump_malfunction_stage4_description",
                branchDescriptions = {
                    "rms_breakdowns_hydraulic_pump_malfunction_stage4_description",
                    "rms_breakdowns_hydraulic_pump_malfunction_branch2_stage1_description"
                },
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = stagePartPrices.HYDRAULIC_PUMP_MALFUNCTION[4],
                effects = {
                    { id = "HYDRAULIC_SPEED_MODIFIER", value = -1.0, aggregation = "min", extraData = { disableAi = true },
                        branch = 1 },
                    { id = "HYDRAULIC_SPEED_MODIFIER", value = -1.0, aggregation = "min", extraData = { disableAi = true },
                        branch = 2 },
                    { id = "HYDRAULIC_PUMP_NOISE_EFFECT", value = 1.0, aggregation = "max", branch = 1 }
                },
                indicators = {
                    { id = db.WARNING, color = color.CRITICAL, switchOn = true, switchOff = false, branch = 1 },
                    { id = db.WARNING, color = color.CRITICAL, switchOn = true, switchOff = false, branch = 2 }
                }
            }
        }
    },

    HYDRAULIC_SPOOL_VALVE_MALFUNCTION = {
        isSelectable = true,
        system = systems.HYDRAULICS,
        part = parts.HYDRAULIC_SPOOL_VALVE,
        isApplicable = isHydraulicActuatorBreakdownApplicable,
        causes = { primary = { "of", "sf" }, secondary = { "hfbf" } },
        component = "CONTROL_VALVE",
        branches = 2,
        isCanProgress = function(vehicle)
            local spec = vehicle.spec_RealisticMechanicalSystems
            local breakdown = spec ~= nil and spec.activeBreakdowns ~= nil and spec.activeBreakdowns.HYDRAULIC_SPOOL_VALVE_MALFUNCTION or nil
            return (breakdown == nil or breakdown.branch ~= 2)
                and vehicle:getIsMotorStarted() and vehicle.spec_RealisticMechanicalSystems.isHydraulicActive
        end,
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_hydraulic_spool_valve_stage1_description",
                branchDescriptions = {
                    "rms_breakdowns_hydraulic_spool_valve_stage1_description",
                    "rms_breakdowns_hydraulic_spool_valve_malfunction_branch2_stage1_description"
                },
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.HYDRAULIC_SPOOL_VALVE_MALFUNCTION,
                repairPrice = stagePartPrices.HYDRAULIC_SPOOL_VALVE_MALFUNCTION[1],
                effects = {
                    { id = "HYDRAULIC_FUNCTION_ERRATIC_EFFECT", value = -0.1, aggregation = "min", extraData = { childVehicleHash = "" }, branch = 1 },
                    { id = "HYDRAULIC_FUNCTION_BLOCKED_EFFECT", value = 1, aggregation = "boolean_or", branch = 2 }
                }
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_hydraulic_spool_valve_stage2_description",
                branchDescriptions = {
                    "rms_breakdowns_hydraulic_spool_valve_stage2_description",
                    "rms_breakdowns_hydraulic_spool_valve_malfunction_branch2_stage1_description"
                },
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.HYDRAULIC_SPOOL_VALVE_MALFUNCTION,
                repairPrice = stagePartPrices.HYDRAULIC_SPOOL_VALVE_MALFUNCTION[2],
                effects = {
                    { id = "HYDRAULIC_FUNCTION_ERRATIC_EFFECT", value = -0.2, aggregation = "min", extraData = { childVehicleHash = "" }, branch = 1 },
                    { id = "HYDRAULIC_FUNCTION_BLOCKED_EFFECT", value = 1, aggregation = "boolean_or", branch = 2 }
                },
                indicators = {
                    { id = db.WARNING, color = color.WARNING, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_hydraulic_spool_valve_stage3_description",
                branchDescriptions = {
                    "rms_breakdowns_hydraulic_spool_valve_stage3_description",
                    "rms_breakdowns_hydraulic_spool_valve_malfunction_branch2_stage1_description"
                },
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.HYDRAULIC_SPOOL_VALVE_MALFUNCTION,
                repairPrice = stagePartPrices.HYDRAULIC_SPOOL_VALVE_MALFUNCTION[3],
                effects = {
                    { id = "HYDRAULIC_FUNCTION_ERRATIC_EFFECT", value = -0.35, aggregation = "min", extraData = { childVehicleHash = "" }, branch = 1 },
                    { id = "HYDRAULIC_FUNCTION_BLOCKED_EFFECT", value = 1, aggregation = "boolean_or", branch = 2 }
                },
                indicators = {
                    { id = db.WARNING, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_hydraulic_spool_valve_stage4_description",
                branchDescriptions = {
                    "rms_breakdowns_hydraulic_spool_valve_stage4_description",
                    "rms_breakdowns_hydraulic_spool_valve_malfunction_branch2_stage1_description"
                },
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = stagePartPrices.HYDRAULIC_SPOOL_VALVE_MALFUNCTION[4],
                effects = {
                    { id = "HYDRAULIC_FUNCTION_ERRATIC_EFFECT", value = -0.5, aggregation = "min", extraData = { childVehicleHash = "" }, branch = 1 },
                    { id = "HYDRAULIC_FUNCTION_BLOCKED_EFFECT", value = 1, aggregation = "boolean_or", branch = 2 }
                },
                indicators = {
                    { id = db.WARNING, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            }
        }
    },

    LIFT_VALVE_FAILURE = {
        isSelectable = true,
        system = systems.HYDRAULICS,
        part = parts.LIFT_VALVE,
        isApplicable = isHydraulicLiftBreakdownApplicable,
        causes = { primary = { "of", "sf" }, secondary = { "hfbf" } },
        component = "SOLENOID_VALVE",
        branches = 2,
        stages = {
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_lift_valve_failure_branch1_stage1_description",
                branchDescriptions = {
                    "rms_breakdowns_lift_valve_failure_branch1_stage1_description",
                    "rms_breakdowns_lift_valve_failure_branch2_stage1_description"
                },
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = stagePartPrices.LIFT_VALVE_FAILURE[1],
                effects = {
                    { id = "HYDRAULIC_HOLD_DRIFT_EFFECT", value = 0.05, aggregation = "max", extraData = { timer = 0, status = "IDLE" }, branch = 1 },
                    { id = "LIFT_CONTROL_FAILURE", value = 1, aggregation = "boolean_or", branch = 2 }
                },
                indicators = {
                    { id = db.WARNING, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            }
        }
    },

    LIFT_POSITION_SENSOR_FAILURE = {
        isSelectable = true,
        system = systems.HYDRAULICS,
        part = parts.LIFT_POSITION_SENSOR,
        isApplicable = function(vehicle)
            local spec = vehicle.spec_RealisticMechanicalSystems
            return isHydraulicLiftBreakdownApplicable(vehicle) and spec ~= nil
                and spec.yearIsKnown == true and (tonumber(spec.year) or 0) >= 2000
        end,
        causes = { primary = {}, secondary = {} },
        component = "TRANSDUCER",
        stages = {
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_lift_position_sensor_failure_stage1_description",
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = stagePartPrices.LIFT_POSITION_SENSOR_FAILURE[1],
                effects = {
                    { id = "HYDRAULIC_HOLD_DRIFT_EFFECT", value = 0.05, aggregation = "max", extraData = { timer = 0, status = "IDLE" } }
                },
                indicators = {
                    { id = db.WARNING, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            }
        }
    },

    LOADER_CONTROL_FAILURE = {
        isSelectable = true,
        system = systems.HYDRAULICS,
        part = parts.LOADER_CONTROL,
        isApplicable = isFrontLoaderPivotBreakdownApplicable,
        causes = { primary = { "of" }, secondary = { "vf" } },
        component = "ELECTRO_MECHANICAL",
        isCanProgress = function(vehicle)
            return vehicle:getIsMotorStarted()
        end,
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_loader_control_failure_stage1_description",
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.LOADER_CONTROL_FAILURE,
                repairPrice = stagePartPrices.LOADER_CONTROL_FAILURE[1],
                effects = {
                    { id = "LOADER_CONTROL_EFFECT", value = -0.25, aggregation = "min" }
                }
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_loader_control_failure_stage2_description",
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.LOADER_CONTROL_FAILURE,
                repairPrice = stagePartPrices.LOADER_CONTROL_FAILURE[2],
                effects = {
                    { id = "LOADER_CONTROL_EFFECT", value = -0.5, aggregation = "min" }
                },
                indicators = {
                    { id = db.WARNING, color = color.WARNING, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_loader_control_failure_stage3_description",
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.LOADER_CONTROL_FAILURE,
                repairPrice = stagePartPrices.LOADER_CONTROL_FAILURE[3],
                effects = {
                    { id = "LOADER_CONTROL_EFFECT", value = -0.75, aggregation = "min" }
                },
                indicators = {
                    { id = db.WARNING, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_loader_control_failure_stage4_description",
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = stagePartPrices.LOADER_CONTROL_FAILURE[4],
                effects = {
                    { id = "LOADER_CONTROL_EFFECT", value = -1, aggregation = "min" }
                },
                indicators = {
                    { id = db.WARNING, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            }
        }
    },

    HYDRAULIC_CYLINDER_INTERNAL_LEAK = {
        isSelectable = true,
        system = systems.HYDRAULICS,
        part = parts.HYDRAULIC_CYLINDER,
        isApplicable = isHydraulicLiftBreakdownApplicable,
        causes = { primary = { "hlf", "of", "vf" }, secondary = { "hfbf" } },
        component = "O_RING",
        branches = 2,
        isCanProgress = function(vehicle)
            local spec = vehicle.spec_RealisticMechanicalSystems
            return spec.isImplementLifted or spec.isHydraulicLiftMoving
        end,
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_hydraulic_cylinder_internal_leak_stage1_description",
                branchDescriptions = {
                    "rms_breakdowns_hydraulic_cylinder_internal_leak_stage1_description",
                    "rms_breakdowns_hydraulic_cylinder_internal_leak_branch2_stage1_description"
                },
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.HYDRAULIC_CYLINDER_INTERNAL_LEAK,
                repairPrice = stagePartPrices.HYDRAULIC_CYLINDER_INTERNAL_LEAK[1],
                effects = {
                    { id = "HYDRAULIC_HOLD_DRIFT_EFFECT", value = 0.01, aggregation = "max", extraData = { timer = 0, status = "IDLE" }, branch = 1 },
                    { id = "HYDRAULIC_FLUID_LEAK_RATE", value = 0.02, aggregation = "max", branch = 2 }
                }
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_hydraulic_cylinder_internal_leak_stage2_description",
                branchDescriptions = {
                    "rms_breakdowns_hydraulic_cylinder_internal_leak_stage2_description",
                    "rms_breakdowns_hydraulic_cylinder_internal_leak_branch2_stage2_description"
                },
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.HYDRAULIC_CYLINDER_INTERNAL_LEAK,
                repairPrice = stagePartPrices.HYDRAULIC_CYLINDER_INTERNAL_LEAK[2],
                effects = {
                    { id = "HYDRAULIC_HOLD_DRIFT_EFFECT", value = 0.03, aggregation = "max", extraData = { timer = 0, status = "IDLE" }, branch = 1 },
                    { id = "HYDRAULIC_FLUID_LEAK_RATE", value = 0.08, aggregation = "max", branch = 2 }
                },
                indicators = {
                    { id = db.WARNING, color = color.WARNING, switchOn = true, switchOff = false, branch = 1 },
                    { id = db.WARNING, color = color.WARNING, switchOn = true, switchOff = false, branch = 2 }
                }
            },
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_hydraulic_cylinder_internal_leak_stage3_description",
                branchDescriptions = {
                    "rms_breakdowns_hydraulic_cylinder_internal_leak_stage3_description",
                    "rms_breakdowns_hydraulic_cylinder_internal_leak_branch2_stage3_description"
                },
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.HYDRAULIC_CYLINDER_INTERNAL_LEAK,
                repairPrice = stagePartPrices.HYDRAULIC_CYLINDER_INTERNAL_LEAK[3],
                effects = {
                    { id = "HYDRAULIC_HOLD_DRIFT_EFFECT", value = 0.05, aggregation = "max", extraData = { timer = 0, status = "IDLE" }, branch = 1 },
                    { id = "HYDRAULIC_FLUID_LEAK_RATE", value = 0.25, aggregation = "max", branch = 2 }
                },
                indicators = {
                    { id = db.WARNING, color = color.CRITICAL, switchOn = true, switchOff = false, branch = 1 },
                    { id = db.WARNING, color = color.CRITICAL, switchOn = true, switchOff = false, branch = 2 }
                }
            },
            {
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_hydraulic_cylinder_internal_leak_stage4_description",
                branchDescriptions = {
                    "rms_breakdowns_hydraulic_cylinder_internal_leak_stage4_description",
                    "rms_breakdowns_hydraulic_cylinder_internal_leak_branch2_stage4_description"
                },
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = stagePartPrices.HYDRAULIC_CYLINDER_INTERNAL_LEAK[4],
                effects = {
                    { id = "HYDRAULIC_HOLD_DRIFT_EFFECT", value = 1.0, aggregation = "max", extraData = { timer = 0, status = "IDLE" }, branch = 1 },
                    { id = "HYDRAULIC_FLUID_LEAK_RATE", value = 0.8, aggregation = "max", branch = 2 }
                },
                indicators = {
                    { id = db.WARNING, color = color.CRITICAL, switchOn = true, switchOff = false, branch = 1 },
                    { id = db.WARNING, color = color.CRITICAL, switchOn = true, switchOff = false, branch = 2 }
                }
            }
        }
    },

    HYDRAULIC_QUICK_COUPLER_FAILURE = {
        isSelectable = true,
        system = systems.HYDRAULICS,
        part = parts.HYDRAULIC_QUICK_COUPLERS,
        isApplicable = isHydraulicActuatorBreakdownApplicable,
        causes = { primary = { "hlf", "vf" }, secondary = {} },
        component = "O_RING",
        branches = 2,
        isCanProgress = function(vehicle)
            local spec = vehicle.spec_RealisticMechanicalSystems
            local breakdown = spec ~= nil and spec.activeBreakdowns ~= nil and spec.activeBreakdowns.HYDRAULIC_QUICK_COUPLER_FAILURE or nil
            return (breakdown == nil or breakdown.branch ~= 2)
                and vehicle:getIsMotorStarted() and vehicle.spec_RealisticMechanicalSystems.isHydraulicActive
        end,
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_hydraulic_quick_coupler_failure_branch1_stage1_description",
                branchDescriptions = {
                    "rms_breakdowns_hydraulic_quick_coupler_failure_branch1_stage1_description",
                    "rms_breakdowns_hydraulic_quick_coupler_failure_branch2_stage1_description"
                },
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.HYDRAULIC_QUICK_COUPLER_FAILURE,
                repairPrice = stagePartPrices.HYDRAULIC_QUICK_COUPLER_FAILURE[1],
                effects = {
                    { id = "HYDRAULIC_FLUID_LEAK_RATE", value = 0.02, aggregation = "max", branch = 1 },
                    { id = "HYDRAULIC_FUNCTION_BLOCKED_EFFECT", value = 1, aggregation = "boolean_or", branch = 2 }
                }
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_hydraulic_quick_coupler_failure_branch1_stage2_description",
                branchDescriptions = {
                    "rms_breakdowns_hydraulic_quick_coupler_failure_branch1_stage2_description",
                    "rms_breakdowns_hydraulic_quick_coupler_failure_branch2_stage1_description"
                },
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.HYDRAULIC_QUICK_COUPLER_FAILURE,
                repairPrice = stagePartPrices.HYDRAULIC_QUICK_COUPLER_FAILURE[2],
                effects = {
                    { id = "HYDRAULIC_FLUID_LEAK_RATE", value = 0.08, aggregation = "max", branch = 1 },
                    { id = "HYDRAULIC_FUNCTION_BLOCKED_EFFECT", value = 1, aggregation = "boolean_or", branch = 2 }
                },
                indicators = {
                    { id = db.WARNING, color = color.WARNING, switchOn = true, switchOff = false, branch = 1 }
                }
            },
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_hydraulic_quick_coupler_failure_branch1_stage3_description",
                branchDescriptions = {
                    "rms_breakdowns_hydraulic_quick_coupler_failure_branch1_stage3_description",
                    "rms_breakdowns_hydraulic_quick_coupler_failure_branch2_stage1_description"
                },
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.HYDRAULIC_QUICK_COUPLER_FAILURE,
                repairPrice = stagePartPrices.HYDRAULIC_QUICK_COUPLER_FAILURE[3],
                effects = {
                    { id = "HYDRAULIC_FLUID_LEAK_RATE", value = 0.25, aggregation = "max", branch = 1 },
                    { id = "HYDRAULIC_FUNCTION_BLOCKED_EFFECT", value = 1, aggregation = "boolean_or", branch = 2 }
                },
                indicators = {
                    { id = db.WARNING, color = color.CRITICAL, switchOn = true, switchOff = false, branch = 1 }
                }
            },
            {
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_hydraulic_quick_coupler_failure_branch1_stage4_description",
                branchDescriptions = {
                    "rms_breakdowns_hydraulic_quick_coupler_failure_branch1_stage4_description",
                    "rms_breakdowns_hydraulic_quick_coupler_failure_branch2_stage1_description"
                },
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = stagePartPrices.HYDRAULIC_QUICK_COUPLER_FAILURE[4],
                effects = {
                    { id = "HYDRAULIC_FLUID_LEAK_RATE", value = 0.8, aggregation = "max", branch = 1 },
                    { id = "HYDRAULIC_FUNCTION_BLOCKED_EFFECT", value = 1, aggregation = "boolean_or", branch = 2 }
                },
                indicators = {
                    { id = db.WARNING, color = color.CRITICAL, switchOn = true, switchOff = false, branch = 1 }
                }
            }
        }
    },

    HYDRAULIC_HOSE_EXTERNAL_LEAK = {
        isSelectable = true,
        system = systems.HYDRAULICS,
        part = parts.HYDRAULIC_HOSE,
        isApplicable = isHydraulicHoseBreakdownApplicable,
        causes = { primary = { "hlf", "vf" }, secondary = {} },
        component = "RUBBER_DIAPHRAGM",
        isCanProgress = function(vehicle)
            local spec = vehicle.spec_RealisticMechanicalSystems
            return vehicle:getIsMotorStarted() and spec.isHydraulicActive
        end,
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_hydraulic_hose_external_leak_stage1_description",
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.HYDRAULIC_HOSE_EXTERNAL_LEAK,
                repairPrice = stagePartPrices.HYDRAULIC_HOSE_EXTERNAL_LEAK[1],
                effects = {
                    { id = "HYDRAULIC_SPEED_MODIFIER", value = -0.05, aggregation = "min" },
                    { id = "HYDRAULIC_FLUID_LEAK_RATE", value = 0.02, aggregation = "max" }
                },
                inspection = {
                    { additional = "rms_inspection_hint_hydraulic_hose_external_leak_stage1" }
                }
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_hydraulic_hose_external_leak_stage2_description",
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.HYDRAULIC_HOSE_EXTERNAL_LEAK,
                repairPrice = stagePartPrices.HYDRAULIC_HOSE_EXTERNAL_LEAK[2],
                effects = {
                    { id = "HYDRAULIC_SPEED_MODIFIER", value = -0.1, aggregation = "min" },
                    { id = "HYDRAULIC_FLUID_LEAK_RATE", value = 0.08, aggregation = "max" }
                },
                inspection = {
                    { additional = "rms_inspection_hint_hydraulic_hose_external_leak_stage2" }
                },
                indicators = {
                    { id = db.WARNING, color = color.WARNING, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_hydraulic_hose_external_leak_stage3_description",
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.HYDRAULIC_HOSE_EXTERNAL_LEAK,
                repairPrice = stagePartPrices.HYDRAULIC_HOSE_EXTERNAL_LEAK[3],
                effects = {
                    { id = "HYDRAULIC_SPEED_MODIFIER", value = -0.2, aggregation = "min" },
                    { id = "HYDRAULIC_FLUID_LEAK_RATE", value = 0.25, aggregation = "max" }
                },
                inspection = {
                    { additional = "rms_inspection_hint_hydraulic_hose_external_leak_stage3" }
                },
                indicators = {
                    { id = db.WARNING, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_hydraulic_hose_external_leak_stage4_description",
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = stagePartPrices.HYDRAULIC_HOSE_EXTERNAL_LEAK[4],
                effects = {
                    { id = "HYDRAULIC_SPEED_MODIFIER", value = -0.35, aggregation = "min" },
                    { id = "HYDRAULIC_FLUID_LEAK_RATE", value = 0.8, aggregation = "max" },
                    { id = "HOSE_BURST_NOISE_EFFECT", value = 1.0, aggregation = "max" }
                },
                inspection = {
                    { additional = "rms_inspection_hint_hydraulic_hose_external_leak_stage4" }
                },
                indicators = {
                    { id = db.WARNING, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            }
        }
    },

    HYDRAULIC_FILTER_CLOGGING = {
        isSelectable = true,
        system = systems.HYDRAULICS,
        part = parts.HYDRAULIC_FILTER,
        isApplicable = isHydraulicBreakdownApplicable,
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_hydraulic_filter_clogging_stage1_description",
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = stagePartPrices.HYDRAULIC_FILTER_CLOGGING[1],
                effects = {
                    { id = "HYDRAULIC_SPEED_MODIFIER", value = -0.1, aggregation = "min" }
                }
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_hydraulic_filter_clogging_stage2_description",
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = stagePartPrices.HYDRAULIC_FILTER_CLOGGING[2],
                effects = {
                    { id = "HYDRAULIC_SPEED_MODIFIER", value = -0.25, aggregation = "min" }
                },
                indicators = {
                    { id = db.WARNING, color = color.WARNING, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_hydraulic_filter_clogging_stage3_description",
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = stagePartPrices.HYDRAULIC_FILTER_CLOGGING[3],
                effects = {
                    { id = "HYDRAULIC_SPEED_MODIFIER", value = -0.45, aggregation = "min" }
                },
                indicators = {
                    { id = db.WARNING, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_hydraulic_filter_clogging_stage4_description",
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = stagePartPrices.HYDRAULIC_FILTER_CLOGGING[4],
                effects = {
                    { id = "HYDRAULIC_SPEED_MODIFIER", value = -0.7, aggregation = "min" }
                },
                indicators = {
                    { id = db.WARNING, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            }
        }
    },

    HYDRAULIC_OIL_COOLER_MALFUNCTION = {
        isSelectable = true,
        system = systems.HYDRAULICS,
        part = parts.HYDRAULIC_OIL_COOLER,
        isApplicable = isHydraulicBreakdownApplicable,
        causes = { primary = { "hof", "sf", "of" }, secondary = { "vf" } },
        component = "HEAT_EXCHANGER",
        branches = 2,
        isCanProgress = function(vehicle)
            return vehicle:getIsMotorStarted() and vehicle.spec_RealisticMechanicalSystems.isHydraulicActive
        end,
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_hydraulic_oil_cooler_malfunction_stage1_description",
                branchDescriptions = {
                    "rms_breakdowns_hydraulic_oil_cooler_malfunction_stage1_description",
                    "rms_breakdowns_hydraulic_oil_cooler_malfunction_branch2_stage1_description"
                },
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.HYDRAULIC_OIL_COOLER_MALFUNCTION,
                repairPrice = stagePartPrices.HYDRAULIC_OIL_COOLER_MALFUNCTION[1],
                effects = {
                    { id = "HYDRAULIC_HEAT_MODIFIER", value = 0.05, aggregation = "sum", branch = 1 },
                    { id = "HYDRAULIC_FLUID_LEAK_RATE", value = 0.02, aggregation = "max", branch = 2 }
                }
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_hydraulic_oil_cooler_malfunction_stage2_description",
                branchDescriptions = {
                    "rms_breakdowns_hydraulic_oil_cooler_malfunction_stage2_description",
                    "rms_breakdowns_hydraulic_oil_cooler_malfunction_branch2_stage2_description"
                },
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.HYDRAULIC_OIL_COOLER_MALFUNCTION,
                repairPrice = stagePartPrices.HYDRAULIC_OIL_COOLER_MALFUNCTION[2],
                effects = {
                    { id = "HYDRAULIC_HEAT_MODIFIER", value = 0.1, aggregation = "sum", branch = 1 },
                    { id = "HYDRAULIC_FLUID_LEAK_RATE", value = 0.08, aggregation = "max", branch = 2 }
                },
                indicators = {
                    { id = db.WARNING, color = color.WARNING, switchOn = true, switchOff = false, branch = 1 },
                    { id = db.WARNING, color = color.WARNING, switchOn = true, switchOff = false, branch = 2 }
                }
            },
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_hydraulic_oil_cooler_malfunction_stage3_description",
                branchDescriptions = {
                    "rms_breakdowns_hydraulic_oil_cooler_malfunction_stage3_description",
                    "rms_breakdowns_hydraulic_oil_cooler_malfunction_branch2_stage3_description"
                },
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.HYDRAULIC_OIL_COOLER_MALFUNCTION,
                repairPrice = stagePartPrices.HYDRAULIC_OIL_COOLER_MALFUNCTION[3],
                effects = {
                    { id = "HYDRAULIC_HEAT_MODIFIER", value = 0.15, aggregation = "sum", branch = 1 },
                    { id = "HYDRAULIC_FLUID_LEAK_RATE", value = 0.25, aggregation = "max", branch = 2 }
                },
                indicators = {
                    { id = db.WARNING, color = color.WARNING, switchOn = true, switchOff = false, branch = 1 },
                    { id = db.WARNING, color = color.CRITICAL, switchOn = true, switchOff = false, branch = 2 }
                }
            },
            {
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_hydraulic_oil_cooler_malfunction_stage4_description",
                branchDescriptions = {
                    "rms_breakdowns_hydraulic_oil_cooler_malfunction_stage4_description",
                    "rms_breakdowns_hydraulic_oil_cooler_malfunction_branch2_stage4_description"
                },
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = stagePartPrices.HYDRAULIC_OIL_COOLER_MALFUNCTION[4],
                effects = {
                    { id = "HYDRAULIC_HEAT_MODIFIER", value = 0.2, aggregation = "sum", branch = 1 },
                    { id = "HYDRAULIC_FLUID_LEAK_RATE", value = 0.8, aggregation = "max", branch = 2 }
                },
                indicators = {
                    { id = db.WARNING, color = color.CRITICAL, switchOn = true, switchOff = false, branch = 1 },
                    { id = db.WARNING, color = color.CRITICAL, switchOn = true, switchOff = false, branch = 2 }
                }
            }
        }
    },

    PTO_CLUTCH_WEAR = {
        isSelectable = true,
        system = systems.PTO,
        part = parts.PTO_CLUTCH,
        isApplicable = isPtoBreakdownApplicable,
        causes = { primary = {"plf", "pef"}, secondary = {"sf"} },
        component = "FRICTION_CLUTCH",
        branches = 2,
        isCanProgress = function(vehicle)
            return vehicle.spec_RealisticMechanicalSystems.isPtoActive
        end,
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_pto_clutch_wear_stage1_description",
                branchDescriptions = {
                    "rms_breakdowns_pto_clutch_wear_stage1_description",
                    "rms_breakdowns_pto_clutch_wear_branch2_stage1_description"
                },
                inspection = { { additional = "rms_inspection_hint_pto_clutch_wear_branch2_stage1", branch = 2 } },
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.PTO_CLUTCH_WEAR,
                repairPrice = stagePartPrices.PTO_CLUTCH_WEAR[1],
                effects = {
                    { id = "PTO_AUTO_DISENGAGE_CHANCE", value = 40, aggregation = "min", extraData = {status = "IDLE"}, branch = 1 }
                }
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_pto_clutch_wear_stage2_description",
                branchDescriptions = {
                    "rms_breakdowns_pto_clutch_wear_stage2_description",
                    "rms_breakdowns_pto_clutch_wear_branch2_stage2_description"
                },
                inspection = { { additional = "rms_inspection_hint_pto_clutch_wear_branch2_stage2", branch = 2 } },
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.PTO_CLUTCH_WEAR,
                repairPrice = stagePartPrices.PTO_CLUTCH_WEAR[2],
                effects = {
                    { id = "PTO_AUTO_DISENGAGE_CHANCE", value = 20, aggregation = "min", extraData = {status = "IDLE"}, branch = 1 }
                },
                indicators = {
                    { id = db.WARNING, color = color.WARNING, switchOn = true, switchOff = false, branch = 1 }
                }
            },
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_pto_clutch_wear_stage3_description",
                branchDescriptions = {
                    "rms_breakdowns_pto_clutch_wear_stage3_description",
                    "rms_breakdowns_pto_clutch_wear_branch2_stage3_description"
                },
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.PTO_CLUTCH_WEAR,
                repairPrice = stagePartPrices.PTO_CLUTCH_WEAR[3],
                effects = {
                    { id = "PTO_AUTO_DISENGAGE_CHANCE", value = 10, aggregation = "min", extraData = {status = "IDLE"}, branch = 1 },
                    { id = "PTO_STUCK_ENGAGED_CHANCE", value = 0.5, aggregation = "max", branch = 2 }
                },
                indicators = {
                    { id = db.WARNING, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_pto_clutch_wear_stage4_description",
                branchDescriptions = {
                    "rms_breakdowns_pto_clutch_wear_stage4_description",
                    "rms_breakdowns_pto_clutch_wear_branch2_stage4_description"
                },
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = stagePartPrices.PTO_CLUTCH_WEAR[4],
                effects = {
                    { id = "PTO_FAILURE", value = 1.0, aggregation = "boolean_or", extraData = {disableAi = true}, branch = 1 },
                    { id = "PTO_STUCK_ENGAGED_CHANCE", value = 1.0, aggregation = "max", extraData = {disableAi = true}, branch = 2 }
                },
                indicators = {
                    { id = db.WARNING, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            }
        }
    },

    PTO_OUTPUT_BEARING_WEAR = {
        isSelectable = true,
        system = systems.PTO,
        part = parts.PTO_OUTPUT_BEARING,
        isApplicable = isPtoBreakdownApplicable,
        causes = { primary = {"plf", "sf"}, secondary = {"pef"} },
        component = "PTO_OUTPUT_SHARED_BUDGET",
        isCanProgress = function(vehicle)
            return vehicle.spec_RealisticMechanicalSystems.isPtoActive
        end,
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_pto_output_bearing_wear_stage1_description",
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.PTO_OUTPUT_BEARING_WEAR,
                repairPrice = stagePartPrices.PTO_OUTPUT_BEARING_WEAR[1],
                effects = {
                    { id = "PTO_BEARING_NOISE_EFFECT", value = 0.70, aggregation = "max" }
                },
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_pto_output_bearing_wear_stage2_description",
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.PTO_OUTPUT_BEARING_WEAR,
                repairPrice = stagePartPrices.PTO_OUTPUT_BEARING_WEAR[2],
                effects = {
                    { id = "PTO_BEARING_NOISE_EFFECT", value = 1.20, aggregation = "max" }
                },
                indicators = {
                    { id = db.WARNING, color = color.WARNING, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_pto_output_bearing_wear_stage3_description",
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.PTO_OUTPUT_BEARING_WEAR,
                repairPrice = stagePartPrices.PTO_OUTPUT_BEARING_WEAR[3],
                effects = {
                    { id = "PTO_BEARING_NOISE_EFFECT", value = 1.70, aggregation = "max" },
                },
                indicators = {
                    { id = db.WARNING, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_pto_output_bearing_wear_stage4_description",
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = stagePartPrices.PTO_OUTPUT_BEARING_WEAR[4],
                effects = {
                    { id = "PTO_BEARING_NOISE_EFFECT", value = 1.70, aggregation = "max" }
                },
                indicators = {
                    { id = db.WARNING, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            }
        }
    },

    PTO_OUTPUT_SEAL_LEAK = {
        isSelectable = true,
        system = systems.PTO,
        part = parts.PTO_OUTPUT_SEAL,
        isApplicable = isPtoBreakdownApplicable,
        causes = { primary = { "plf" }, secondary = { "sf" } },
        component = "MECHANICAL_SEAL",
        isCanProgress = function(vehicle)
            return vehicle:getIsMotorStarted()
        end,
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_pto_output_seal_leak_stage1_description",
                inspection = { { additional = "rms_inspection_hint_pto_output_seal_leak_stage1" } },
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.PTO_OUTPUT_SEAL_LEAK,
                repairPrice = stagePartPrices.PTO_OUTPUT_SEAL_LEAK[1],
                effects = {
                    { id = "TRANSMISSION_OIL_LEAK_RATE", value = 0.01, aggregation = "max" }
                }
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_pto_output_seal_leak_stage2_description",
                inspection = { { additional = "rms_inspection_hint_pto_output_seal_leak_stage2" } },
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.PTO_OUTPUT_SEAL_LEAK,
                repairPrice = stagePartPrices.PTO_OUTPUT_SEAL_LEAK[2],
                effects = {
                    { id = "TRANSMISSION_OIL_LEAK_RATE", value = 0.04, aggregation = "max" }
                },
                indicators = {
                    { id = db.WARNING, color = color.WARNING, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_pto_output_seal_leak_stage3_description",
                inspection = { { additional = "rms_inspection_hint_pto_output_seal_leak_stage3" } },
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.PTO_OUTPUT_SEAL_LEAK,
                repairPrice = stagePartPrices.PTO_OUTPUT_SEAL_LEAK[3],
                effects = {
                    { id = "TRANSMISSION_OIL_LEAK_RATE", value = 0.12, aggregation = "max" }
                },
                indicators = {
                    { id = db.TRANSMISSION, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_pto_output_seal_leak_stage4_description",
                inspection = { { additional = "rms_inspection_hint_pto_output_seal_leak_stage4" } },
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = stagePartPrices.PTO_OUTPUT_SEAL_LEAK[4],
                effects = {
                    { id = "TRANSMISSION_OIL_LEAK_RATE", value = 0.4, aggregation = "max" }
                },
                indicators = {
                    { id = db.TRANSMISSION, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            }
        }
    },

    PTO_ENGAGEMENT_SOLENOID_FAILURE = {
        isSelectable = true,
        system = systems.PTO,
        part = parts.PTO_ENGAGEMENT_SOLENOID,
        isApplicable = function(vehicle)
            local spec = vehicle.spec_RealisticMechanicalSystems
            return isPtoBreakdownApplicable(vehicle) and spec ~= nil and (tonumber(spec.year) or 0) >= 1990
        end,
        causes = { primary = {"sf"}, secondary = {} },
        component = "PTO_CONTROL_SHARED_BUDGET",
        isCanProgress = function(vehicle)
            return vehicle:getIsMotorStarted()
        end,
        branches = 2,
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_pto_engagement_solenoid_failure_branch1_stage1_description",
                branchDescriptions = { "rms_breakdowns_pto_engagement_solenoid_failure_branch1_stage1_description", "rms_breakdowns_pto_engagement_solenoid_failure_branch2_stage1_description" },
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.PTO_ENGAGEMENT_SOLENOID_FAILURE,
                repairPrice = stagePartPrices.PTO_ENGAGEMENT_SOLENOID_FAILURE[1],
                effects = {
                    { id = "PTO_AUTO_DISENGAGE_CHANCE", value = 40, aggregation = "min", extraData = {status = "IDLE"}, branch = 1 },
                        { id = "PTO_ENGAGEMENT_BLOCKED_CHANCE", value = 0.10, aggregation = "max", branch = 2 }
                },
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_pto_engagement_solenoid_failure_branch1_stage2_description",
                branchDescriptions = { "rms_breakdowns_pto_engagement_solenoid_failure_branch1_stage2_description", "rms_breakdowns_pto_engagement_solenoid_failure_branch2_stage2_description" },
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.PTO_ENGAGEMENT_SOLENOID_FAILURE,
                repairPrice = stagePartPrices.PTO_ENGAGEMENT_SOLENOID_FAILURE[2],
                effects = {
                    { id = "PTO_AUTO_DISENGAGE_CHANCE", value = 20, aggregation = "min", extraData = {status = "IDLE"}, branch = 1 },
                        { id = "PTO_ENGAGEMENT_BLOCKED_CHANCE", value = 0.30, aggregation = "max", branch = 2 }
                },
                indicators = {
                    { id = db.WARNING, color = color.WARNING, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_pto_engagement_solenoid_failure_branch1_stage3_description",
                branchDescriptions = { "rms_breakdowns_pto_engagement_solenoid_failure_branch1_stage3_description", "rms_breakdowns_pto_engagement_solenoid_failure_branch2_stage3_description" },
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.PTO_ENGAGEMENT_SOLENOID_FAILURE,
                repairPrice = stagePartPrices.PTO_ENGAGEMENT_SOLENOID_FAILURE[3],
                effects = {
                    { id = "PTO_AUTO_DISENGAGE_CHANCE", value = 10, aggregation = "min", extraData = {status = "IDLE"}, branch = 1 },
                        { id = "PTO_ENGAGEMENT_BLOCKED_CHANCE", value = 0.60, aggregation = "max", branch = 2 }
                },
                indicators = {
                    { id = db.WARNING, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_pto_engagement_solenoid_failure_branch1_stage4_description",
                branchDescriptions = { "rms_breakdowns_pto_engagement_solenoid_failure_branch1_stage4_description", "rms_breakdowns_pto_engagement_solenoid_failure_branch2_stage4_description" },
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = stagePartPrices.PTO_ENGAGEMENT_SOLENOID_FAILURE[4],
                effects = {
                        {
                            id = "PTO_FAILURE",
                            value = 1.0,
                            aggregation = "boolean_or",
                            branch = 1,
                            extraData = { disableAi = true }
                        },
                    { id = "PTO_FAILURE", value = 1.0, aggregation = "boolean_or", branch = 2,
                        extraData = { disableAi = true } },
                },
                indicators = {
                    { id = db.WARNING, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            }
        }
    },
    PTO_ENGAGEMENT_SWITCH_FAILURE = {
        isSelectable = true,
        system = systems.PTO,
        part = parts.PTO_ENGAGEMENT_SWITCH,
        isApplicable = function(vehicle)
            local spec = vehicle.spec_RealisticMechanicalSystems
            return isPtoBreakdownApplicable(vehicle) and spec ~= nil and (tonumber(spec.year) or 0) >= 1990
        end,
        causes = { primary = {"sf"}, secondary = {} },
        component = "PTO_CONTROL_SHARED_BUDGET",
        isCanProgress = function(vehicle)
            return vehicle:getIsMotorStarted()
        end,
        branches = 2,
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_pto_engagement_switch_failure_branch1_stage1_description",
                branchDescriptions = { "rms_breakdowns_pto_engagement_switch_failure_branch1_stage1_description", "rms_breakdowns_pto_engagement_switch_failure_branch2_stage1_description" },
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.PTO_ENGAGEMENT_SWITCH_FAILURE,
                repairPrice = stagePartPrices.PTO_ENGAGEMENT_SWITCH_FAILURE[1],
                effects = {
                    { id = "PTO_AUTO_DISENGAGE_CHANCE", value = 40, aggregation = "min", extraData = {status = "IDLE"}, branch = 1 },
                        { id = "PTO_ENGAGEMENT_BLOCKED_CHANCE", value = 0.10, aggregation = "max", branch = 2 }
                },
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_pto_engagement_switch_failure_branch1_stage2_description",
                branchDescriptions = { "rms_breakdowns_pto_engagement_switch_failure_branch1_stage2_description", "rms_breakdowns_pto_engagement_switch_failure_branch2_stage2_description" },
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.PTO_ENGAGEMENT_SWITCH_FAILURE,
                repairPrice = stagePartPrices.PTO_ENGAGEMENT_SWITCH_FAILURE[2],
                effects = {
                    { id = "PTO_AUTO_DISENGAGE_CHANCE", value = 20, aggregation = "min", extraData = {status = "IDLE"}, branch = 1 },
                        { id = "PTO_ENGAGEMENT_BLOCKED_CHANCE", value = 0.30, aggregation = "max", branch = 2 }
                },
                indicators = {
                    { id = db.WARNING, color = color.WARNING, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_pto_engagement_switch_failure_branch1_stage3_description",
                branchDescriptions = { "rms_breakdowns_pto_engagement_switch_failure_branch1_stage3_description", "rms_breakdowns_pto_engagement_switch_failure_branch2_stage3_description" },
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.PTO_ENGAGEMENT_SWITCH_FAILURE,
                repairPrice = stagePartPrices.PTO_ENGAGEMENT_SWITCH_FAILURE[3],
                effects = {
                    { id = "PTO_AUTO_DISENGAGE_CHANCE", value = 10, aggregation = "min", extraData = {status = "IDLE"}, branch = 1 },
                        { id = "PTO_ENGAGEMENT_BLOCKED_CHANCE", value = 0.60, aggregation = "max", branch = 2 }
                },
                indicators = {
                    { id = db.WARNING, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_pto_engagement_switch_failure_branch1_stage4_description",
                branchDescriptions = { "rms_breakdowns_pto_engagement_switch_failure_branch1_stage4_description", "rms_breakdowns_pto_engagement_switch_failure_branch2_stage4_description" },
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = stagePartPrices.PTO_ENGAGEMENT_SWITCH_FAILURE[4],
                effects = {
                        {
                            id = "PTO_FAILURE",
                            value = 1.0,
                            aggregation = "boolean_or",
                            branch = 1,
                            extraData = { disableAi = true }
                        },
                    { id = "PTO_FAILURE", value = 1.0, aggregation = "boolean_or", branch = 2,
                        extraData = { disableAi = true } },
                },
                indicators = {
                    { id = db.WARNING, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            }
        }
    },

    PTO_OUTPUT_SHAFT_FAILURE = {
        isSelectable = true,
        system = systems.PTO,
        part = parts.PTO_OUTPUT_SHAFT,
        isApplicable = isPtoBreakdownApplicable,
        causes = { primary = {"plf", "sf"}, secondary = {"pef"} },
        component = "PTO_OUTPUT_SHARED_BUDGET",
        branches = 2,
        stages = {
            {
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_pto_output_shaft_failure_branch1_stage1_description",
                branchDescriptions = { "rms_breakdowns_pto_output_shaft_failure_branch1_stage1_description", "rms_breakdowns_pto_output_shaft_failure_branch2_stage1_description" },
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = stagePartPrices.PTO_OUTPUT_SHAFT_FAILURE[1],
                effects = { { id = "PTO_FAILURE", value = 1.0, aggregation = "boolean_or",
                    extraData = { disableAi = true },
                    branch = 1 },
                    { id = "PTO_FAILURE", value = 1.0, aggregation = "boolean_or", extraData = { disableAi = true },
                    branch = 2 },
                    { id = "PTO_SPLINES_NOISE_EFFECT", value = 1.0, aggregation = "max", branch = 1 },
                    { id = "PTO_SHAFT_BREAK_NOISE_EFFECT", value = 1.0, aggregation = "max", branch = 2 }
                },
                indicators = { { id = db.WARNING, color = color.CRITICAL, switchOn = true, switchOff = false } }
            }
        }
    },

    PTO_SPEED_SENSOR_FAILURE = {
        isSelectable = true,
        system = systems.PTO,
        part = parts.PTO_SPEED_SENSOR,
        isApplicable = function(vehicle)
            return isPtoBreakdownApplicable(vehicle) and RMS_Utils.getUsesEngineECUProfile(vehicle)
        end,
        causes = { primary = {}, secondary = {} },
        component = "TRANSDUCER",
        stages = {
            {
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_pto_speed_sensor_failure_stage1_description",
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = stagePartPrices.PTO_SPEED_SENSOR_FAILURE[1],
                effects = { { id = "PTO_FAILURE", value = 1.0, aggregation = "boolean_or", extraData = { disableAi = true } } },
                indicators = { { id = db.WARNING, color = color.CRITICAL, switchOn = true, switchOff = false } }
            }
        }
    },

    PTO_BRAKE_FAILURE = {
        isSelectable = true,
        system = systems.PTO,
        part = parts.PTO_BRAKE,
        isApplicable = isPtoBreakdownApplicable,
        causes = { primary = {}, secondary = {} },
        component = "PTO_BRAKE_SERVICE_PROXY",
        stages = {
            {
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_pto_brake_failure_stage1_description",
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = stagePartPrices.PTO_BRAKE_FAILURE[1],
                effects = { { id = "PTO_FAILURE", value = 1.0, aggregation = "boolean_or", extraData = { disableAi = true } } },
                indicators = { { id = db.WARNING, color = color.CRITICAL, switchOn = true, switchOff = false } }
            }
        }
    },

    -- chassis system
    FRONT_PTO_CLUTCH_FAILURE = {
        isSelectable = true,
        system = systems.PTO,
        part = parts.FRONT_PTO_CLUTCH,
        isApplicable = function(vehicle)
            return isPtoBreakdownApplicable(vehicle) and RMS_Utils.getFrontPtoOutput(vehicle) ~= nil
        end,
        causes = { primary = { "pef" }, secondary = { "plf", "sf" } },
        component = "FRICTION_CLUTCH",
        isCanProgress = function(vehicle)
            return RMS_Utils.getConnectedPtoData(vehicle, "front").isActive
        end,
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_front_pto_clutch_failure_stage1_description",
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.FRONT_PTO_CLUTCH_FAILURE,
                repairPrice = stagePartPrices.FRONT_PTO_CLUTCH_FAILURE[1],
                effects = {
                    { id = "FRONT_PTO_AUTO_DISENGAGE_CHANCE", value = 40, aggregation = "min", extraData = {status = "IDLE"} }
                }
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_front_pto_clutch_failure_stage2_description",
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.FRONT_PTO_CLUTCH_FAILURE,
                repairPrice = stagePartPrices.FRONT_PTO_CLUTCH_FAILURE[2],
                effects = {
                    { id = "FRONT_PTO_AUTO_DISENGAGE_CHANCE", value = 20, aggregation = "min", extraData = {status = "IDLE"} }
                },
                indicators = {
                    { id = db.WARNING, color = color.WARNING, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_front_pto_clutch_failure_stage3_description",
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.FRONT_PTO_CLUTCH_FAILURE,
                repairPrice = stagePartPrices.FRONT_PTO_CLUTCH_FAILURE[3],
                effects = {
                    { id = "FRONT_PTO_AUTO_DISENGAGE_CHANCE", value = 10, aggregation = "min", extraData = {status = "IDLE"} }
                },
                indicators = {
                    { id = db.WARNING, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_front_pto_clutch_failure_stage4_description",
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = stagePartPrices.FRONT_PTO_CLUTCH_FAILURE[4],
                effects = {
                    { id = "FRONT_PTO_FAILURE", value = 1.0, aggregation = "boolean_or", extraData = {disableAi = true} }
                },
                indicators = {
                    { id = db.WARNING, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            }
        }
    },

    BRAKE_DISC_WEAR = {
        isSelectable = true,
        system = systems.CHASSIS,
        part = parts.BRAKE_DISCS,
        isApplicable = isSteeringWheelBreakdownApplicable,
        causes = { primary = {"bmf"}, secondary = {} },
        component = "BRAKE_SERVICE_BUDGET",
        isCanProgress = function(vehicle)
            return true
        end,
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_brake_disc_wear_stage1_description",
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.BRAKE_DISC_WEAR,
                repairPrice = stagePartPrices.BRAKE_DISC_WEAR[1],
                effects = {
                    { id = "BRAKE_FORCE_MODIFIER", value = -0.30, aggregation = "min" }
                }
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_brake_disc_wear_stage2_description",
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.BRAKE_DISC_WEAR,
                repairPrice = stagePartPrices.BRAKE_DISC_WEAR[2],
                effects = {
                    { id = "BRAKE_FORCE_MODIFIER", value = -0.45, aggregation = "min" }
                },
            },
            { 
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_brake_disc_wear_stage3_description",
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.BRAKE_DISC_WEAR,
                repairPrice = stagePartPrices.BRAKE_DISC_WEAR[3],
                effects = { 
                    { id = "BRAKE_FORCE_MODIFIER", value = -0.70, aggregation = "min" }
                },
            },
            { 
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_brake_disc_wear_stage4_description",
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = stagePartPrices.BRAKE_DISC_WEAR[4],
                effects = { 
                    { id = "BRAKE_FORCE_MODIFIER", value = -1.0, aggregation = "min", extraData = {disableAi = true} }
                },
            }
        }
    },

    BRAKE_CONTROL_FAILURE = {
        isSelectable = true,
        system = systems.CHASSIS,
        part = parts.BRAKE_CONTROL,
        isApplicable = isSteeringWheelBreakdownApplicable,
        causes = { primary = {"bmf"}, secondary = {} },
        component = "BRAKE_SERVICE_BUDGET",
        branches = 2,
        isCanProgress = function(vehicle)
            return vehicle:getLastSpeed() > 0.01
        end,
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_brake_control_failure_branch1_stage1_description",
                branchDescriptions = { "rms_breakdowns_brake_control_failure_branch1_stage1_description", "rms_breakdowns_brake_control_failure_branch2_stage1_description" },
                inspection = { { additional = "rms_inspection_hint_brake_control_failure_stage1", branch = 1 },
                    { additional = "rms_inspection_hint_brake_control_failure_soft_pedal_stage1", branch = 2 } },
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.BRAKE_CONTROL_FAILURE,
                repairPrice = stagePartPrices.BRAKE_CONTROL_FAILURE[1],
                effects = { { id = "BRAKE_PULL_EFFECT", value = 0.2, aggregation = "max", branch = 1 }, { id = "BRAKE_FORCE_MODIFIER", value = -0.30, aggregation = "min", branch = 2 } },
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_brake_control_failure_branch1_stage2_description",
                branchDescriptions = { "rms_breakdowns_brake_control_failure_branch1_stage2_description", "rms_breakdowns_brake_control_failure_branch2_stage2_description" },
                inspection = { { additional = "rms_inspection_hint_brake_control_failure_stage2", branch = 1 },
                    { additional = "rms_inspection_hint_brake_control_failure_soft_pedal_stage2", branch = 2 } },
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.BRAKE_CONTROL_FAILURE,
                repairPrice = stagePartPrices.BRAKE_CONTROL_FAILURE[2],
                effects = { { id = "BRAKE_PULL_EFFECT", value = 0.5, aggregation = "max", branch = 1 }, { id = "BRAKE_FORCE_MODIFIER", value = -0.45, aggregation = "min", branch = 2 } },
                indicators = { { id = db.BRAKES, color = color.WARNING, switchOn = true, switchOff = false, branch = 2 } },
            },
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_brake_control_failure_branch1_stage3_description",
                branchDescriptions = { "rms_breakdowns_brake_control_failure_branch1_stage3_description", "rms_breakdowns_brake_control_failure_branch2_stage3_description" },
                inspection = { { additional = "rms_inspection_hint_brake_control_failure_stage3", branch = 1 },
                    { additional = "rms_inspection_hint_brake_control_failure_soft_pedal_stage3", branch = 2 } },
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.BRAKE_CONTROL_FAILURE,
                repairPrice = stagePartPrices.BRAKE_CONTROL_FAILURE[3],
                effects = { { id = "BRAKE_PULL_EFFECT", value = 1.2, aggregation = "max", branch = 1 }, { id = "BRAKE_FORCE_MODIFIER", value = -0.70, aggregation = "min", branch = 2 } },
                indicators = { { id = db.BRAKES, color = color.CRITICAL, switchOn = true, switchOff = false, branch = 2 } },
            },
            {
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_brake_control_failure_branch1_stage4_description",
                branchDescriptions = { "rms_breakdowns_brake_control_failure_branch1_stage4_description", "rms_breakdowns_brake_control_failure_branch2_stage4_description" },
                inspection = { { additional = "rms_inspection_hint_brake_control_failure_stage4", branch = 1 },
                    { additional = "rms_inspection_hint_brake_control_failure_soft_pedal_stage4", branch = 2 } },
                detectionChance = 1.0,
                progressMultiplier = 0 * breakdownProgressMultipliers.BRAKE_CONTROL_FAILURE,
                repairPrice = stagePartPrices.BRAKE_CONTROL_FAILURE[4],
                effects = {
                    { id = "BRAKE_PULL_EFFECT", value = 1.2, aggregation = "max", branch = 1 },
                    { id = "BRAKE_FORCE_MODIFIER", value = -1.0, aggregation = "min", branch = 2, extraData = { disableAi = true } },
                },
                indicators = { { id = db.BRAKES, color = color.CRITICAL, switchOn = true, switchOff = false, branch = 2 } },
            },
        }
    },

    TRAILER_BRAKE_VALVE_FAILURE = {
        isSelectable = true,
        system = systems.CHASSIS,
        part = parts.TRAILER_BRAKE_VALVE,
        isApplicable = isTrailerBrakeValveApplicable,
        causes = { primary = {}, secondary = {} },
        component = "TRAILER_BRAKE_VALVE",
        isCanProgress = function(vehicle)
            return vehicle:getLastSpeed() > 0.01
        end,
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_trailer_brake_valve_failure_stage1_description",
                inspection = { { additional = "rms_inspection_hint_trailer_brake_valve_failure_stage1" } },
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.TRAILER_BRAKE_VALVE_FAILURE,
                repairPrice = stagePartPrices.TRAILER_BRAKE_VALVE_FAILURE[1],
                effects = { { id = "TRAILER_BRAKE_FAILURE", value = -0.3, aggregation = "min" } },
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_trailer_brake_valve_failure_stage2_description",
                inspection = { { additional = "rms_inspection_hint_trailer_brake_valve_failure_stage2" } },
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.TRAILER_BRAKE_VALVE_FAILURE,
                repairPrice = stagePartPrices.TRAILER_BRAKE_VALVE_FAILURE[2],
                effects = { { id = "TRAILER_BRAKE_FAILURE", value = -0.45, aggregation = "min" } },
            },
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_trailer_brake_valve_failure_stage3_description",
                inspection = { { additional = "rms_inspection_hint_trailer_brake_valve_failure_stage3" } },
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.TRAILER_BRAKE_VALVE_FAILURE,
                repairPrice = stagePartPrices.TRAILER_BRAKE_VALVE_FAILURE[3],
                effects = { { id = "TRAILER_BRAKE_FAILURE", value = -0.7, aggregation = "min" } },
            },
            {
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_trailer_brake_valve_failure_stage4_description",
                inspection = { { additional = "rms_inspection_hint_trailer_brake_valve_failure_stage4" } },
                detectionChance = 1.0,
                progressMultiplier = 0 * breakdownProgressMultipliers.TRAILER_BRAKE_VALVE_FAILURE,
                repairPrice = stagePartPrices.TRAILER_BRAKE_VALVE_FAILURE[4],
                effects = { { id = "TRAILER_BRAKE_FAILURE", value = -1.0, aggregation = "min" } },
            },
        }
    },

    PARK_BRAKE_MALFUNCTION = {
        isSelectable = true,
        system = systems.CHASSIS,
        part = parts.PARK_BRAKE,
        isApplicable = function(vehicle)
            if vehicle.spec_crawlers ~= nil then
                return #vehicle.spec_crawlers.crawlers == 0
            else
                return true
            end
        end,
        causes = { primary = {"pbf"}, secondary = {} },
        component = "FRICTION_CLUTCH",
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_park_brake_malfunction_stage1_description",
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.PARK_BRAKE_MALFUNCTION,
                repairPrice = stagePartPrices.PARK_BRAKE_MALFUNCTION[1],
                effects = {
                    { id = "PARK_BRAKE_DRAG_EFFECT", value = 0.1, aggregation = "max" },
                    { id = "PARK_BRAKE_DRAG_NOISE_EFFECT", value = 0.3, aggregation = "max" }
                }
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_park_brake_malfunction_stage2_description",
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.PARK_BRAKE_MALFUNCTION,
                repairPrice = stagePartPrices.PARK_BRAKE_MALFUNCTION[2],
                effects = {
                    { id = "PARK_BRAKE_DRAG_EFFECT", value = 0.25, aggregation = "max" },
                    { id = "PARK_BRAKE_DRAG_NOISE_EFFECT", value = 0.5, aggregation = "max" }
                }
            },
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_park_brake_malfunction_stage3_description",
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.PARK_BRAKE_MALFUNCTION,
                repairPrice = stagePartPrices.PARK_BRAKE_MALFUNCTION[3],
                effects = {
                    { id = "PARK_BRAKE_DRAG_EFFECT", value = 0.5, aggregation = "max" },
                    { id = "PARK_BRAKE_DRAG_NOISE_EFFECT", value = 0.8, aggregation = "max" }
                },
                indicators = {
                    { id = db.BRAKES, color = color.WARNING, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_park_brake_malfunction_stage4_description",
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = stagePartPrices.PARK_BRAKE_MALFUNCTION[4],
                effects = {
                    { id = "PARK_BRAKE_DRAG_EFFECT", value = 1.0, aggregation = "max", extraData = {disableAi = true} },
                    { id = "PARK_BRAKE_DRAG_NOISE_EFFECT", value = 1.0, aggregation = "max" }
                },
                indicators = {
                    { id = db.BRAKES, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            }
        }
    },

    WHEEL_HUB_BEARING_WEAR = {
        isSelectable = true,
        system = systems.CHASSIS,
        part = parts.WHEEL_BEARING,
        isApplicable = isSteeringWheelBreakdownApplicable,
        causes = { primary = {"vf", "tif"}, secondary = {"lubf"} },
        component = "ROLLER_BEARING",
        isCanProgress = function(vehicle)
            return vehicle:getLastSpeed() > 0.01
        end,
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_wheel_hub_bearing_wear_stage1_description",
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.WHEEL_HUB_BEARING_WEAR,
                repairPrice = stagePartPrices.WHEEL_HUB_BEARING_WEAR[1],
                effects = {
                    { id = "WHEEL_HUB_BEARING_NOISE_EFFECT", value = 1.0, aggregation = "max" },
                    { id = "MAX_SPEED_MODIFIER", value = 0.05, aggregation = "max" },
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.03, aggregation = "sum" },
                }
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_wheel_hub_bearing_wear_stage2_description",
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.WHEEL_HUB_BEARING_WEAR,
                repairPrice = stagePartPrices.WHEEL_HUB_BEARING_WEAR[2],
                effects = {
                    { id = "WHEEL_HUB_BEARING_NOISE_EFFECT", value = 1.5, aggregation = "max" },
                    { id = "MAX_SPEED_MODIFIER", value = 0.10, aggregation = "max" },
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.05, aggregation = "sum" },
                },
                indicators = {

                }
            },
            { 
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_wheel_hub_bearing_wear_stage3_description",
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.WHEEL_HUB_BEARING_WEAR,
                repairPrice = stagePartPrices.WHEEL_HUB_BEARING_WEAR[3],
                effects = { 
                    { id = "WHEEL_HUB_BEARING_NOISE_EFFECT", value = 2.0, aggregation = "max" },
                    { id = "MAX_SPEED_MODIFIER", value = 0.20, aggregation = "max" },
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.07, aggregation = "sum" },
                    { id = "WHEEL_SEIZURE_GRIND_NOISE_EFFECT", value = 0.3, aggregation = "max" }
                },
                indicators = {

                }
            },
            { 
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_wheel_hub_bearing_wear_stage4_description",
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = stagePartPrices.WHEEL_HUB_BEARING_WEAR[4],
                effects = { 
                    { id = "WHEEL_SEIZURE_GRIND_NOISE_EFFECT", value = 2.5, aggregation = "max" },
                    { id = "WHEEL_SEIZURE_EFFECT", value = 1.0, aggregation = "max", extraData = {disableAi = true}},
                },
                indicators = {
                    { id = db.BRAKES, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            }
        }
    },

    STEERING_LINKAGE_WEAR = {
        isSelectable = true,
        system = systems.CHASSIS,
        part = parts.STEERING_LINKAGE,
        isApplicable = function(vehicle)
            if vehicle.spec_wheels == nil or vehicle.spec_wheels.wheels == nil or #vehicle.spec_wheels.wheels == 0 then
                return false
            end
            if vehicle.spec_crawlers ~= nil and #vehicle.spec_crawlers.crawlers > 0 then
                return false
            end
            return true
        end,
        causes = { primary = {"slf", "tif"}, secondary = {"vf", "lubf"} },
        component = "STEERING_COMPONENT_BUDGET",
        isCanProgress = function(vehicle)
            return vehicle:getLastSpeed() > 0.01
        end,
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_steering_linkage_wear_stage1_description",
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.STEERING_LINKAGE_WEAR,
                repairPrice = stagePartPrices.STEERING_LINKAGE_WEAR[1],
                effects = {
                    { id = "STEERING_STATIC_BIAS_EFFECT", value = 0.2, aggregation = "max" },
                    { id = "STEERING_PLAY_EFFECT", value = 0.5, aggregation = "max" },
                    { id = "STEERING_LINKAGE_NOISE_EFFECT", value = 0.3, aggregation = "max" }
                }
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_steering_linkage_wear_stage2_description",
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.STEERING_LINKAGE_WEAR,
                repairPrice = stagePartPrices.STEERING_LINKAGE_WEAR[2],
                effects = {
                    { id = "STEERING_STATIC_BIAS_EFFECT", value = 0.5, aggregation = "max" },
                    { id = "STEERING_PLAY_EFFECT", value = 1.2, aggregation = "max" },
                    { id = "STEERING_LINKAGE_NOISE_EFFECT", value = 0.5, aggregation = "max" }
                },
                indicators = {
                }
            },
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_steering_linkage_wear_stage3_description",
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.STEERING_LINKAGE_WEAR,
                repairPrice = stagePartPrices.STEERING_LINKAGE_WEAR[3],
                effects = {
                    { id = "STEERING_STATIC_BIAS_EFFECT", value = 1.2, aggregation = "max" },
                    { id = "STEERING_PLAY_EFFECT", value = 2.5, aggregation = "max" },
                    { id = "STEERING_LINKAGE_NOISE_EFFECT", value = 0.8, aggregation = "max" }
                }
            },
            {
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_steering_linkage_wear_stage4_description",
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = stagePartPrices.STEERING_LINKAGE_WEAR[4],
                effects = {
                    { id = "STEERING_WHEEL_FREE_EFFECT", value = 1.0, aggregation = "max", extraData = {disableAi=true} },
                    { id = "STEERING_LINKAGE_NOISE_EFFECT", value = 1.0, aggregation = "max" }
                }
            }
        }
    },

    STEERING_KNUCKLE_PIVOT_WEAR = {
        isSelectable = true,
        system = systems.CHASSIS,
        part = parts.STEERING_KNUCKLE_PIVOT,
        isApplicable = isSteeringWheelBreakdownApplicable,
        causes = { primary = {"slf", "tif"}, secondary = {"vf", "lubf"} },
        component = "STEERING_COMPONENT_BUDGET",
        isCanProgress = function(vehicle)
            return vehicle:getLastSpeed() > 0.01
        end,
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_steering_knuckle_pivot_wear_stage1_description",
                inspection = { { additional = "rms_inspection_hint_steering_knuckle_pivot_wear_stage1" } },
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.STEERING_KNUCKLE_PIVOT_WEAR,
                repairPrice = stagePartPrices.STEERING_KNUCKLE_PIVOT_WEAR[1],
                effects = { { id = "STEERING_PLAY_EFFECT", value = 0.5, aggregation = "max" }, { id = "STEERING_KNUCKLE_NOISE_EFFECT", value = 0.3, aggregation = "max" } },
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_steering_knuckle_pivot_wear_stage2_description",
                inspection = { { additional = "rms_inspection_hint_steering_knuckle_pivot_wear_stage2" } },
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.STEERING_KNUCKLE_PIVOT_WEAR,
                repairPrice = stagePartPrices.STEERING_KNUCKLE_PIVOT_WEAR[2],
                effects = { { id = "STEERING_PLAY_EFFECT", value = 1.2, aggregation = "max" }, { id = "STEERING_KNUCKLE_NOISE_EFFECT", value = 0.5, aggregation = "max" } },
            },
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_steering_knuckle_pivot_wear_stage3_description",
                inspection = { { additional = "rms_inspection_hint_steering_knuckle_pivot_wear_stage3" } },
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.STEERING_KNUCKLE_PIVOT_WEAR,
                repairPrice = stagePartPrices.STEERING_KNUCKLE_PIVOT_WEAR[3],
                effects = { { id = "STEERING_PLAY_EFFECT", value = 2.5, aggregation = "max" }, { id = "STEERING_KNUCKLE_NOISE_EFFECT", value = 0.8, aggregation = "max" } },
            },
            {
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_steering_knuckle_pivot_wear_stage4_description",
                inspection = { { additional = "rms_inspection_hint_steering_knuckle_pivot_wear_stage4" } },
                detectionChance = 1.0,
                progressMultiplier = 0 * breakdownProgressMultipliers.STEERING_KNUCKLE_PIVOT_WEAR,
                repairPrice = stagePartPrices.STEERING_KNUCKLE_PIVOT_WEAR[4],
                effects = { { id = "STEERING_PLAY_EFFECT", value = 2.5, aggregation = "max" }, { id = "STEERING_KNUCKLE_NOISE_EFFECT", value = 1.0, aggregation = "max" } },
            },
        }
    },

    STEERING_ORBITROL_MALFUNCTION = {
        isSelectable = true,
        system = systems.CHASSIS,
        part = parts.STEERING_ORBITROL,
        isApplicable = isSteeringWheelBreakdownApplicable,
        causes = { primary = {"slf", "tif"}, secondary = {"vf", "lubf"} },
        component = "STEERING_COMPONENT_BUDGET",
        isCanProgress = function(vehicle)
            return vehicle:getLastSpeed() > 0.01
        end,
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_steering_orbitrol_malfunction_stage1_description",
                inspection = { { additional = "rms_inspection_hint_steering_orbitrol_malfunction_stage1" } },
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.STEERING_ORBITROL_MALFUNCTION,
                repairPrice = stagePartPrices.STEERING_ORBITROL_MALFUNCTION[1],
                effects = { { id = "STEERING_PLAY_EFFECT", value = 0.5, aggregation = "max" }, { id = "STEERING_ORBITROL_NOISE_EFFECT", value = 0.3, aggregation = "max" } },
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_steering_orbitrol_malfunction_stage2_description",
                inspection = { { additional = "rms_inspection_hint_steering_orbitrol_malfunction_stage2" } },
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.STEERING_ORBITROL_MALFUNCTION,
                repairPrice = stagePartPrices.STEERING_ORBITROL_MALFUNCTION[2],
                effects = { { id = "STEERING_PLAY_EFFECT", value = 1.2, aggregation = "max" }, { id = "STEERING_ORBITROL_NOISE_EFFECT", value = 0.5, aggregation = "max" } },
            },
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_steering_orbitrol_malfunction_stage3_description",
                inspection = { { additional = "rms_inspection_hint_steering_orbitrol_malfunction_stage3" } },
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.STEERING_ORBITROL_MALFUNCTION,
                repairPrice = stagePartPrices.STEERING_ORBITROL_MALFUNCTION[3],
                effects = { { id = "STEERING_PLAY_EFFECT", value = 2.5, aggregation = "max" }, { id = "STEERING_ORBITROL_NOISE_EFFECT", value = 0.8, aggregation = "max" } },
            },
            {
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_steering_orbitrol_malfunction_stage4_description",
                inspection = { { additional = "rms_inspection_hint_steering_orbitrol_malfunction_stage4" } },
                detectionChance = 1.0,
                progressMultiplier = 0 * breakdownProgressMultipliers.STEERING_ORBITROL_MALFUNCTION,
                repairPrice = stagePartPrices.STEERING_ORBITROL_MALFUNCTION[4],
                effects = { { id = "STEERING_PLAY_EFFECT", value = 2.5, aggregation = "max" }, { id = "STEERING_ORBITROL_NOISE_EFFECT", value = 1.0, aggregation = "max" } },
            },
        }
    },

    STEERING_CYLINDER_LEAK = {
        isSelectable = true,
        system = systems.CHASSIS,
        part = parts.STEERING_CYLINDER,
        isApplicable = isSteeringWheelBreakdownApplicable,
        causes = { primary = {}, secondary = {} },
        component = "STEERING_COMPONENT_BUDGET",
        isCanProgress = function(vehicle)
            return vehicle:getLastSpeed() > 0.01
        end,
        branches = 2,
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_steering_cylinder_leak_branch1_stage1_description",
                inspection = { { additional = "rms_inspection_hint_steering_cylinder_leak_stage1", branch = 1 },
                    { additional = "rms_inspection_hint_steering_cylinder_leak_rod_seal_stage1", branch = 2 } },
                branchDescriptions = {
                    "rms_breakdowns_steering_cylinder_leak_branch1_stage1_description",
                    "rms_breakdowns_steering_cylinder_leak_branch2_stage1_description"
                },
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.STEERING_CYLINDER_LEAK,
                repairPrice = stagePartPrices.STEERING_CYLINDER_LEAK[1],
                effects = { { id = "STEERING_STATIC_BIAS_EFFECT", value = 0.2, aggregation = "max", branch = 1 },
                    { id = "HYDRAULIC_FLUID_LEAK_RATE", value = 0.02, aggregation = "max", branch = 2 } },
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_steering_cylinder_leak_branch1_stage2_description",
                inspection = { { additional = "rms_inspection_hint_steering_cylinder_leak_stage2", branch = 1 },
                    { additional = "rms_inspection_hint_steering_cylinder_leak_rod_seal_stage2", branch = 2 } },
                branchDescriptions = {
                    "rms_breakdowns_steering_cylinder_leak_branch1_stage2_description",
                    "rms_breakdowns_steering_cylinder_leak_branch2_stage2_description"
                },
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.STEERING_CYLINDER_LEAK,
                repairPrice = stagePartPrices.STEERING_CYLINDER_LEAK[2],
                effects = { { id = "STEERING_STATIC_BIAS_EFFECT", value = 0.5, aggregation = "max", branch = 1 },
                    { id = "HYDRAULIC_FLUID_LEAK_RATE", value = 0.08, aggregation = "max", branch = 2 } },
            },
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_steering_cylinder_leak_branch1_stage3_description",
                inspection = { { additional = "rms_inspection_hint_steering_cylinder_leak_stage3", branch = 1 },
                    { additional = "rms_inspection_hint_steering_cylinder_leak_rod_seal_stage3", branch = 2 } },
                branchDescriptions = {
                    "rms_breakdowns_steering_cylinder_leak_branch1_stage3_description",
                    "rms_breakdowns_steering_cylinder_leak_branch2_stage3_description"
                },
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.STEERING_CYLINDER_LEAK,
                repairPrice = stagePartPrices.STEERING_CYLINDER_LEAK[3],
                effects = { { id = "STEERING_STATIC_BIAS_EFFECT", value = 1.2, aggregation = "max", branch = 1 },
                    { id = "HYDRAULIC_FLUID_LEAK_RATE", value = 0.25, aggregation = "max", branch = 2 } },
            },
            {
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_steering_cylinder_leak_branch1_stage4_description",
                inspection = { { additional = "rms_inspection_hint_steering_cylinder_leak_stage4", branch = 1 },
                    { additional = "rms_inspection_hint_steering_cylinder_leak_rod_seal_stage4", branch = 2 } },
                branchDescriptions = {
                    "rms_breakdowns_steering_cylinder_leak_branch1_stage4_description",
                    "rms_breakdowns_steering_cylinder_leak_branch2_stage4_description"
                },
                detectionChance = 1.0,
                progressMultiplier = 0 * breakdownProgressMultipliers.STEERING_CYLINDER_LEAK,
                repairPrice = stagePartPrices.STEERING_CYLINDER_LEAK[4],
                effects = { { id = "STEERING_STATIC_BIAS_EFFECT", value = 1.2, aggregation = "max", branch = 1 }, { id = "HYDRAULIC_FLUID_LEAK_RATE", value = 0.8, aggregation = "max", branch = 2 } },
            },
        }
    },

    LOADER_PIVOT_PIN_WEAR = {
        isSelectable = true,
        system = systems.CHASSIS,
        part = parts.LOADER_PINS_AND_BUSHINGS,
        isApplicable = isFrontLoaderPivotBreakdownApplicable,
        causes = { primary = {}, secondary = {} },
        component = "PIN",
        isCanProgress = function(vehicle)
            return vehicle:getLastSpeed() > 0.01
        end,
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_loader_pivot_pin_wear_stage1_description",
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.LOADER_PIVOT_PIN_WEAR,
                repairPrice = stagePartPrices.LOADER_PIVOT_PIN_WEAR[1],
                effects = { { id = "LOADER_PINS_NOISE_EFFECT", value = 0.3, aggregation = "max" } },
                inspection = { { additional = "rms_inspection_hint_loader_pivot_pin_wear_stage1" } },
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_loader_pivot_pin_wear_stage2_description",
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.LOADER_PIVOT_PIN_WEAR,
                repairPrice = stagePartPrices.LOADER_PIVOT_PIN_WEAR[2],
                effects = { { id = "LOADER_PINS_NOISE_EFFECT", value = 0.5, aggregation = "max" } },
                inspection = { { additional = "rms_inspection_hint_loader_pivot_pin_wear_stage2" } },
            },
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_loader_pivot_pin_wear_stage3_description",
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.LOADER_PIVOT_PIN_WEAR,
                repairPrice = stagePartPrices.LOADER_PIVOT_PIN_WEAR[3],
                effects = { { id = "LOADER_PINS_NOISE_EFFECT", value = 0.8, aggregation = "max" } },
                inspection = { { additional = "rms_inspection_hint_loader_pivot_pin_wear_stage3" } },
            },
            {
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_loader_pivot_pin_wear_stage4_description",
                detectionChance = 1.0,
                progressMultiplier = 0 * breakdownProgressMultipliers.LOADER_PIVOT_PIN_WEAR,
                repairPrice = stagePartPrices.LOADER_PIVOT_PIN_WEAR[4],
                effects = { { id = "LOADER_PINS_NOISE_EFFECT", value = 1.0, aggregation = "max" } },
                inspection = { { additional = "rms_inspection_hint_loader_pivot_pin_wear_stage4" } },
            },
        }
    },

    CAB_SUSPENSION_DAMPER_LEAK = {
        isSelectable = true,
        system = systems.CHASSIS,
        part = parts.CAB_SUSPENSION,
        isApplicable = isCabSuspensionApplicable,
        causes = { primary = { "vf" }, secondary = { "tif" } },
        component = "MECHANICAL_SEAL",
        isCanProgress = function(vehicle)
            return vehicle:getLastSpeed() > 0.01
        end,
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_cab_suspension_damper_leak_stage1_description",
                inspection = { { additional = "rms_inspection_hint_cab_suspension_damper_leak_stage1" } },
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.CAB_SUSPENSION_DAMPER_LEAK,
                repairPrice = stagePartPrices.CAB_SUSPENSION_DAMPER_LEAK[1],
                effects = {
                    { id = "CAB_DAMPING_MODIFIER", value = -0.3, aggregation = "min" }
                }
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_cab_suspension_damper_leak_stage2_description",
                inspection = { { additional = "rms_inspection_hint_cab_suspension_damper_leak_stage2" } },
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.CAB_SUSPENSION_DAMPER_LEAK,
                repairPrice = stagePartPrices.CAB_SUSPENSION_DAMPER_LEAK[2],
                effects = {
                    { id = "CAB_DAMPING_MODIFIER", value = -0.55, aggregation = "min" }
                }
            },
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_cab_suspension_damper_leak_stage3_description",
                inspection = { { additional = "rms_inspection_hint_cab_suspension_damper_leak_stage3" } },
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.CAB_SUSPENSION_DAMPER_LEAK,
                repairPrice = stagePartPrices.CAB_SUSPENSION_DAMPER_LEAK[3],
                effects = {
                    { id = "CAB_DAMPING_MODIFIER", value = -0.8, aggregation = "min" },
                    { id = "CAB_DAMPER_NOISE_EFFECT", value = 0.8, aggregation = "max" }
                }
            },
            {
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_cab_suspension_damper_leak_stage4_description",
                inspection = { { additional = "rms_inspection_hint_cab_suspension_damper_leak_stage4" } },
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = stagePartPrices.CAB_SUSPENSION_DAMPER_LEAK[4],
                effects = {
                    { id = "CAB_DAMPING_MODIFIER", value = -0.95, aggregation = "min" },
                    { id = "CAB_DAMPER_NOISE_EFFECT", value = 1.0, aggregation = "max" }
                }
            }
        }
    },

    TRACK_ROLLER_BEARING_WEAR = {
        isSelectable = true,
        system = systems.CHASSIS,
        part = parts.TRACK_ROLLERS,
        isApplicable = isCrawlerBreakdownApplicable,
        causes = { primary = {}, secondary = {} },
        component = "ROLLER_BEARING",
        isCanProgress = function(vehicle)
            return vehicle:getLastSpeed() > 0.01
        end,
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_track_roller_bearing_wear_stage1_description",
                inspection = { { additional = "rms_inspection_hint_track_roller_bearing_wear_stage1" } },
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.TRACK_ROLLER_BEARING_WEAR,
                repairPrice = stagePartPrices.TRACK_ROLLER_BEARING_WEAR[1],
                effects = { { id = "TRACK_ROLLER_NOISE_EFFECT", value = 1.0, aggregation = "max" }, 
                    { id = "MAX_SPEED_MODIFIER", value = 0.05, aggregation = "max" }, { id = "ENGINE_TORQUE_MODIFIER", value = -0.03, aggregation = "sum" } },
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_track_roller_bearing_wear_stage2_description",
                inspection = { { additional = "rms_inspection_hint_track_roller_bearing_wear_stage2" } },
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.TRACK_ROLLER_BEARING_WEAR,
                repairPrice = stagePartPrices.TRACK_ROLLER_BEARING_WEAR[2],
                effects = { { id = "TRACK_ROLLER_NOISE_EFFECT", value = 1.5, aggregation = "max" }, 
                    { id = "MAX_SPEED_MODIFIER", value = 0.10, aggregation = "max" }, { id = "ENGINE_TORQUE_MODIFIER", value = -0.05, aggregation = "sum" } },
            },
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_track_roller_bearing_wear_stage3_description",
                inspection = { { additional = "rms_inspection_hint_track_roller_bearing_wear_stage3" } },
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.TRACK_ROLLER_BEARING_WEAR,
                repairPrice = stagePartPrices.TRACK_ROLLER_BEARING_WEAR[3],
                effects = { { id = "TRACK_ROLLER_NOISE_EFFECT", value = 2.0, aggregation = "max" }, 
                    { id = "MAX_SPEED_MODIFIER", value = 0.20, aggregation = "max" }, { id = "ENGINE_TORQUE_MODIFIER", value = -0.07, aggregation = "sum" },
                    { id = "WHEEL_SEIZURE_GRIND_NOISE_EFFECT", value = 0.3, aggregation = "max" } },
            },
            {
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_track_roller_bearing_wear_stage4_description",
                inspection = { { additional = "rms_inspection_hint_track_roller_bearing_wear_stage4" } },
                detectionChance = 1.0,
                progressMultiplier = 0 * breakdownProgressMultipliers.TRACK_ROLLER_BEARING_WEAR,
                repairPrice = stagePartPrices.TRACK_ROLLER_BEARING_WEAR[4],
                effects = { { id = "WHEEL_SEIZURE_GRIND_NOISE_EFFECT", value = 2.5, aggregation = "max" },
                    { id = "WHEEL_SEIZURE_EFFECT", value = 1.0, aggregation = "max", extraData = { disableAi = true } } },
                indicators = { { id = db.BRAKES, color = color.CRITICAL, switchOn = true, switchOff = false } },
            },
        }
    },

    TRACK_TENSIONER_MALFUNCTION = {
        isSelectable = true,
        system = systems.CHASSIS,
        part = parts.TRACK_TENSIONER,
        isApplicable = function(vehicle)
            if vehicle.spec_crawlers ~= nil and #vehicle.spec_crawlers.crawlers > 0 then
                return true
            end
            return false
        end,
        causes = { primary = {}, secondary = {} },
        component = "O_RING",
        isCanProgress = function(vehicle)
            return vehicle:getLastSpeed() > 0.01
        end,
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_track_tensioner_malfunction_stage1_description",
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.TRACK_TENSIONER_MALFUNCTION,
                repairPrice = stagePartPrices.TRACK_TENSIONER_MALFUNCTION[1],
                effects = {
                    { id = "STEERING_STATIC_BIAS_EFFECT", value = 0.2, aggregation = "max" },
                    { id = "TRACK_CLATTER_NOISE_EFFECT", value = 1.0, aggregation = "max" },
                    { id = "WHEEL_SEIZURE_GRIND_NOISE_EFFECT", value = 0.5, aggregation = "max" },
                    { id = "MAX_SPEED_MODIFIER", value = 0.03, aggregation = "max" },

                }
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_track_tensioner_malfunction_stage2_description",
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.TRACK_TENSIONER_MALFUNCTION,
                repairPrice = stagePartPrices.TRACK_TENSIONER_MALFUNCTION[2],
                effects = {
                    { id = "STEERING_STATIC_BIAS_EFFECT", value = 0.5, aggregation = "max" },
                    { id = "ENGINE_HESITATION_CHANCE", value = 0.3, aggregation = "min", extraData = {timer = 0, duration = 400, status = 'IDLE', amplitude = 0.6, motorLoad = 0.2, cruiseState = 0}},
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.05, aggregation = "sum" },
                    { id = "TRACK_CLATTER_NOISE_EFFECT", value = 1.5, aggregation = "max" },
                    { id = "WHEEL_SEIZURE_GRIND_NOISE_EFFECT", value = 1.0, aggregation = "max" },
                    { id = "MAX_SPEED_MODIFIER", value = 0.06, aggregation = "max" },

                },
                inspection = {
                    { additional = "rms_inspection_hint_track_tensioner_malfunction_stage2" },
                },
                indicators = {
                }
            },
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_track_tensioner_malfunction_stage3_description",
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.TRACK_TENSIONER_MALFUNCTION,
                repairPrice = stagePartPrices.TRACK_TENSIONER_MALFUNCTION[3],
                effects = {
                    { id = "STEERING_STATIC_BIAS_EFFECT", value = 1.5, aggregation = "max" },
                    { id = "ENGINE_HESITATION_CHANCE", value = 0.1, aggregation = "min", extraData = {timer = 0, duration = 500, status = 'IDLE', amplitude = 0.6, motorLoad = 0.2, cruiseState = 0}},
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.1, aggregation = "sum" },
                    { id = "TRACK_CLATTER_NOISE_EFFECT", value = 2.0, aggregation = "max" },
                    { id = "WHEEL_SEIZURE_GRIND_NOISE_EFFECT", value = 2.0, aggregation = "max" },
                    { id = "MAX_SPEED_MODIFIER", value = 0.15, aggregation = "max" },

                },
                inspection = {
                    { additional = "rms_inspection_hint_track_tensioner_malfunction_stage3" },
                },
                indicators = {
                    { id = db.BRAKES, color = color.WARNING, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_track_tensioner_malfunction_stage4_description",
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = stagePartPrices.TRACK_TENSIONER_MALFUNCTION[4],
                effects = {
                    { id = "WHEEL_SEIZURE_GRIND_NOISE_EFFECT", value = 2.5, aggregation = "max" },
                    { id = "WHEEL_SEIZURE_EFFECT", value = 1.0, aggregation = "max", extraData = {disableAi = true}},
                },
                inspection = {
                    { additional = "rms_inspection_hint_track_tensioner_malfunction_stage4" },
                },
                indicators = {
                    { id = db.BRAKES, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            }
        }
    },

    -- cooling system
    THERMOSTAT_MALFUNCTION = {
        isSelectable = true,
        system = systems.COOLING,
        part = parts.THERMOSTAT,
        isApplicable = function(vehicle)
            return not getIsElectricVehicle(vehicle)
        end,
        causes = { primary = {}, secondary = {"sf"} },
        component = "CONTROL_VALVE",
        branches = 2,
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_thermostat_malfunction_branch1_stage1_description",
                branchDescriptions = {
                    "rms_breakdowns_thermostat_malfunction_branch1_stage1_description",
                    "rms_breakdowns_thermostat_malfunction_branch2_stage1_description"
                },
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.THERMOSTAT_MALFUNCTION,
                repairPrice = stagePartPrices.THERMOSTAT_MALFUNCTION[1],
                effects = {
                    { id = "THERMOSTAT_STUCK_EFFECT", value = -1.0, aggregation = "min", branch = 1, extraData = { stuckPosition = 1.0 } },
                    { id = "THERMOSTAT_HEALTH_MODIFIER", value = -0.3, aggregation = "min", branch = 2 },
                },
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_thermostat_malfunction_branch1_stage2_description",
                branchDescriptions = {
                    "rms_breakdowns_thermostat_malfunction_branch1_stage2_description",
                    "rms_breakdowns_thermostat_malfunction_branch2_stage2_description"
                },
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.THERMOSTAT_MALFUNCTION,
                repairPrice = stagePartPrices.THERMOSTAT_MALFUNCTION[2],
                effects = {
                    { id = "THERMOSTAT_STUCK_EFFECT", value = -1.0, aggregation = "min", branch = 1, extraData = { stuckPosition = 1.0 } },
                    { id = "THERMOSTAT_HEALTH_MODIFIER", value = -0.6, aggregation = "min", branch = 2 },
                },
                indicators = {
                    { id = db.WARNING, color = color.WARNING, switchOn = true, switchOff = false, branch = 2 },
                },
            },
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_thermostat_malfunction_branch1_stage3_description",
                branchDescriptions = {
                    "rms_breakdowns_thermostat_malfunction_branch1_stage3_description",
                    "rms_breakdowns_thermostat_malfunction_branch2_stage3_description"
                },
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.THERMOSTAT_MALFUNCTION,
                repairPrice = stagePartPrices.THERMOSTAT_MALFUNCTION[3],
                effects = {
                    { id = "THERMOSTAT_STUCK_EFFECT", value = -1.0, aggregation = "min", branch = 1, extraData = { stuckPosition = 1.0 } },
                    { id = "THERMOSTAT_HEALTH_MODIFIER", value = -0.8, aggregation = "min", branch = 2 },
                },
                indicators = {
                    { id = db.COOLANT, color = color.WARNING, switchOn = true, switchOff = false, branch = 2 },
                },
            },
            {
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_thermostat_malfunction_branch1_stage4_description",
                branchDescriptions = {
                    "rms_breakdowns_thermostat_malfunction_branch1_stage4_description",
                    "rms_breakdowns_thermostat_malfunction_branch2_stage4_description"
                },
                detectionChance = 1.0,
                progressMultiplier = 0 * breakdownProgressMultipliers.THERMOSTAT_MALFUNCTION,
                repairPrice = stagePartPrices.THERMOSTAT_MALFUNCTION[4],
                effects = {
                    { id = "THERMOSTAT_STUCK_EFFECT", value = -1.0, aggregation = "min", branch = 1, extraData = { stuckPosition = 1.0 } },
                    { id = "THERMOSTAT_STUCK_EFFECT", value = -1.0, aggregation = "min", branch = 2, extraData = { stuckPosition = 0.0 } },
                },
                indicators = {
                    { id = db.COOLANT, color = color.CRITICAL, switchOn = true, switchOff = false, branch = 2 },
                },
            },
        }
    },

    COOLANT_HOSE_FAILURE = {
        isSelectable = true,
        system = systems.COOLING,
        part = parts.COOLANT_HOSES,
        isApplicable = function(vehicle)
            return true
        end,
        causes = { primary = {"ohf"}, secondary = {} },
        component = "HYDRAULIC_GASKET",
        branches = 2,
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_coolant_hose_failure_branch1_stage1_description",
                branchDescriptions = {
                    "rms_breakdowns_coolant_hose_failure_branch1_stage1_description",
                    "rms_breakdowns_coolant_hose_failure_branch2_stage1_description"
                },
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.COOLANT_HOSE_FAILURE,
                repairPrice = stagePartPrices.COOLANT_HOSE_FAILURE[1],
                effects = {
                    { id = "COOLANT_LEAK_RATE", value = 0.02, aggregation = "max", branch = 1 },
                    { id = "RADIATOR_HEALTH_MODIFIER", value = -0.2, aggregation = "min", branch = 2 },
                    { id = "COOLANT_STEAM_NOISE_EFFECT", value = 0.3, aggregation = "max", branch = 1 }
                },
                inspection = {
                    { additional = "rms_inspection_hint_coolant_leak_stage1", branch = 1 },
                    { additional = "rms_inspection_hint_thermal_water_pump_stage1", branch = 2 },
                },
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_coolant_hose_failure_branch1_stage2_description",
                branchDescriptions = {
                    "rms_breakdowns_coolant_hose_failure_branch1_stage2_description",
                    "rms_breakdowns_coolant_hose_failure_branch2_stage2_description"
                },
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.COOLANT_HOSE_FAILURE,
                repairPrice = stagePartPrices.COOLANT_HOSE_FAILURE[2],
                effects = {
                    { id = "COOLANT_LEAK_RATE", value = 0.08, aggregation = "max", branch = 1 },
                    { id = "RADIATOR_HEALTH_MODIFIER", value = -0.4, aggregation = "min", branch = 2 },
                    { id = "COOLANT_STEAM_NOISE_EFFECT", value = 0.5, aggregation = "max", branch = 1 }
                },
                indicators = {
                    { id = db.COOLANT, color = color.WARNING, switchOn = true, switchOff = false, branch = 2 },
                },
                inspection = {
                    { additional = "rms_inspection_hint_coolant_leak_stage2", branch = 1 },
                    { additional = "rms_inspection_hint_thermal_water_pump_stage2", branch = 2 },
                },
            },
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_coolant_hose_failure_branch1_stage3_description",
                branchDescriptions = {
                    "rms_breakdowns_coolant_hose_failure_branch1_stage3_description",
                    "rms_breakdowns_coolant_hose_failure_branch2_stage3_description"
                },
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.COOLANT_HOSE_FAILURE,
                repairPrice = stagePartPrices.COOLANT_HOSE_FAILURE[3],
                effects = {
                    { id = "COOLANT_LEAK_RATE", value = 0.25, aggregation = "max", branch = 1 },
                    { id = "RADIATOR_HEALTH_MODIFIER", value = -0.6, aggregation = "min", branch = 2 },
                    { id = "COOLANT_STEAM_NOISE_EFFECT", value = 0.8, aggregation = "max", branch = 1 }
                },
                indicators = {
                    { id = db.COOLANT, color = color.WARNING, switchOn = true, switchOff = false, branch = 1 },
                    { id = db.COOLANT, color = color.CRITICAL, switchOn = true, switchOff = false, branch = 2 },
                },
                inspection = {
                    { additional = "rms_inspection_hint_coolant_leak_stage3", branch = 1 },
                    { additional = "rms_inspection_hint_thermal_water_pump_stage3", branch = 2 },
                },
            },
            {
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_coolant_hose_failure_branch1_stage4_description",
                branchDescriptions = {
                    "rms_breakdowns_coolant_hose_failure_branch1_stage4_description",
                    "rms_breakdowns_coolant_hose_failure_branch2_stage4_description"
                },
                detectionChance = 1.0,
                progressMultiplier = 0 * breakdownProgressMultipliers.COOLANT_HOSE_FAILURE,
                repairPrice = stagePartPrices.COOLANT_HOSE_FAILURE[4],
                effects = {
                    { id = "COOLANT_LEAK_RATE", value = 0.8, aggregation = "max", branch = 1 },
                    { id = "RADIATOR_HEALTH_MODIFIER", value = -0.85, aggregation = "min", branch = 2 },
                    { id = "COOLANT_STEAM_NOISE_EFFECT", value = 1.0, aggregation = "max", branch = 1 }
                },
                indicators = {
                    { id = db.COOLANT, color = color.CRITICAL, switchOn = true, switchOff = false, branch = 1 },
                    { id = db.COOLANT, color = color.CRITICAL, switchOn = true, switchOff = false, branch = 2 },
                },
                inspection = {
                    { additional = "rms_inspection_hint_coolant_leak_stage4", branch = 1 },
                    { additional = "rms_inspection_hint_thermal_water_pump_stage4", branch = 2 },
                },
            },
        }
    },

    EXPANSION_TANK_FAILURE = {
        isSelectable = true,
        system = systems.COOLING,
        part = parts.EXPANSION_TANK,
        isApplicable = function(vehicle)
            return true
        end,
        causes = { primary = {"ohf"}, secondary = {} },
        component = "HYDRAULIC_GASKET",
        branches = 2,
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_expansion_tank_failure_branch1_stage1_description",
                branchDescriptions = {
                    "rms_breakdowns_expansion_tank_failure_branch1_stage1_description",
                    "rms_breakdowns_expansion_tank_failure_branch2_stage1_description"
                },
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.EXPANSION_TANK_FAILURE,
                repairPrice = stagePartPrices.EXPANSION_TANK_FAILURE[1],
                effects = {
                    { id = "COOLANT_LEAK_RATE", value = 0.02, aggregation = "max", branch = 1 },
                    { id = "COOLANT_LEAK_RATE", value = 0.02, aggregation = "max", branch = 2 },
                },
                inspection = {
                    { additional = "rms_inspection_hint_coolant_leak_stage1", branch = 1 },
                    { additional = "rms_inspection_hint_coolant_leak_stage1", branch = 2 },
                },
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_expansion_tank_failure_branch1_stage2_description",
                branchDescriptions = {
                    "rms_breakdowns_expansion_tank_failure_branch1_stage2_description",
                    "rms_breakdowns_expansion_tank_failure_branch2_stage2_description"
                },
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.EXPANSION_TANK_FAILURE,
                repairPrice = stagePartPrices.EXPANSION_TANK_FAILURE[2],
                effects = {
                    { id = "COOLANT_LEAK_RATE", value = 0.08, aggregation = "max", branch = 1 },
                    { id = "COOLANT_LEAK_RATE", value = 0.08, aggregation = "max", branch = 2 },
                },
                inspection = {
                    { additional = "rms_inspection_hint_coolant_leak_stage2", branch = 1 },
                    { additional = "rms_inspection_hint_coolant_leak_stage2", branch = 2 },
                },
            },
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_expansion_tank_failure_branch1_stage3_description",
                branchDescriptions = {
                    "rms_breakdowns_expansion_tank_failure_branch1_stage3_description",
                    "rms_breakdowns_expansion_tank_failure_branch2_stage3_description"
                },
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.EXPANSION_TANK_FAILURE,
                repairPrice = stagePartPrices.EXPANSION_TANK_FAILURE[3],
                effects = {
                    { id = "COOLANT_LEAK_RATE", value = 0.25, aggregation = "max", branch = 1 },
                    { id = "COOLANT_LEAK_RATE", value = 0.25, aggregation = "max", branch = 2 },
                },
                indicators = {
                    { id = db.COOLANT, color = color.WARNING, switchOn = true, switchOff = false, branch = 1 },
                    { id = db.COOLANT, color = color.WARNING, switchOn = true, switchOff = false, branch = 2 },
                },
                inspection = {
                    { additional = "rms_inspection_hint_coolant_leak_stage3", branch = 1 },
                    { additional = "rms_inspection_hint_coolant_leak_stage3", branch = 2 },
                },
            },
            {
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_expansion_tank_failure_branch1_stage4_description",
                branchDescriptions = {
                    "rms_breakdowns_expansion_tank_failure_branch1_stage4_description",
                    "rms_breakdowns_expansion_tank_failure_branch2_stage4_description"
                },
                detectionChance = 1.0,
                progressMultiplier = 0 * breakdownProgressMultipliers.EXPANSION_TANK_FAILURE,
                repairPrice = stagePartPrices.EXPANSION_TANK_FAILURE[4],
                effects = {
                    { id = "COOLANT_LEAK_RATE", value = 0.8, aggregation = "max", branch = 1 },
                    { id = "COOLANT_LEAK_RATE", value = 0.8, aggregation = "max", branch = 2 },
                },
                indicators = {
                    { id = db.COOLANT, color = color.CRITICAL, switchOn = true, switchOff = false, branch = 1 },
                    { id = db.COOLANT, color = color.CRITICAL, switchOn = true, switchOff = false, branch = 2 },
                },
                inspection = {
                    { additional = "rms_inspection_hint_coolant_leak_stage4", branch = 1 },
                    { additional = "rms_inspection_hint_coolant_leak_stage4", branch = 2 },
                },
            },
        }
    },

    ACCESSORY_BELT_FAILURE = {
        isSelectable = true,
        system = systems.COOLING,
        part = parts.ACCESSORY_BELT_KIT,
        isApplicable = function(vehicle)
            return not getIsElectricVehicle(vehicle)
        end,
        causes = { primary = {"ohf", "crf"}, secondary = {"ltf", "vf"} },
        component = "DRIVE_BELT",
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_accessory_belt_failure_stage1_description",
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.ACCESSORY_BELT_FAILURE,
                repairPrice = stagePartPrices.ACCESSORY_BELT_FAILURE[1],
                effects = {
                    { id = "ALTERNATOR_HEALTH_MODIFIER", value = -0.2, aggregation = "min" },
                    { id = "RADIATOR_HEALTH_MODIFIER", value = -0.2, aggregation = "min" },
                    { id = "BELT_SQUEAL_NOISE_EFFECT", value = 0.3, aggregation = "max" }
                },
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_accessory_belt_failure_stage2_description",
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.ACCESSORY_BELT_FAILURE,
                repairPrice = stagePartPrices.ACCESSORY_BELT_FAILURE[2],
                effects = {
                    { id = "ALTERNATOR_HEALTH_MODIFIER", value = -0.5, aggregation = "min" },
                    { id = "RADIATOR_HEALTH_MODIFIER", value = -0.4, aggregation = "min" },
                    { id = "BELT_SQUEAL_NOISE_EFFECT", value = 0.5, aggregation = "max" }
                },
                indicators = {
                    { id = db.BATTERY, color = color.WARNING, switchOn = true, switchOff = false },
                    { id = db.COOLANT, color = color.WARNING, switchOn = true, switchOff = false },
                },
            },
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_accessory_belt_failure_stage3_description",
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.ACCESSORY_BELT_FAILURE,
                repairPrice = stagePartPrices.ACCESSORY_BELT_FAILURE[3],
                effects = {
                    { id = "ALTERNATOR_HEALTH_MODIFIER", value = -0.7, aggregation = "min" },
                    { id = "RADIATOR_HEALTH_MODIFIER", value = -0.6, aggregation = "min" },
                    { id = "BELT_SQUEAL_NOISE_EFFECT", value = 0.8, aggregation = "max" }
                },
                indicators = {
                    { id = db.BATTERY, color = color.CRITICAL, switchOn = true, switchOff = false },
                    { id = db.COOLANT, color = color.CRITICAL, switchOn = true, switchOff = false },
                },
            },
            {
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_accessory_belt_failure_stage4_description",
                detectionChance = 1.0,
                progressMultiplier = 0 * breakdownProgressMultipliers.ACCESSORY_BELT_FAILURE,
                repairPrice = stagePartPrices.ACCESSORY_BELT_FAILURE[4],
                effects = {
                    { id = "ALTERNATOR_HEALTH_MODIFIER", value = -1.0, aggregation = "min" },
                    { id = "RADIATOR_HEALTH_MODIFIER", value = -0.85, aggregation = "min" },
                },
                indicators = {
                    { id = db.BATTERY, color = color.CRITICAL, switchOn = true, switchOff = false },
                    { id = db.COOLANT, color = color.CRITICAL, switchOn = true, switchOff = false },
                },
            },
        }
    },

    FAN_BLADE_FAILURE = {
        isSelectable = true,
        system = systems.COOLING,
        part = parts.FAN_BLADE,
        isApplicable = function(vehicle)
            return not getIsElectricVehicle(vehicle)
        end,
        causes = { primary = {}, secondary = {"ohf", "sf"} },
        component = "IMPELLER",
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_fan_blade_failure_stage1_description",
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.FAN_BLADE_FAILURE,
                repairPrice = stagePartPrices.FAN_BLADE_FAILURE[1],
                effects = {
                    { id = "FAN_CLUTCH_MODIFIER", value = -0.1, aggregation = "min" },
                    { id = "FAN_BLADE_NOISE_EFFECT", value = 0.3, aggregation = "max" },
                },
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_fan_blade_failure_stage2_description",
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.FAN_BLADE_FAILURE,
                repairPrice = stagePartPrices.FAN_BLADE_FAILURE[2],
                effects = {
                    { id = "FAN_CLUTCH_MODIFIER", value = -0.2, aggregation = "min" },
                    { id = "FAN_BLADE_NOISE_EFFECT", value = 0.5, aggregation = "max" },
                },
                indicators = {
                    { id = db.COOLANT, color = color.WARNING, switchOn = true, switchOff = false },
                },
            },
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_fan_blade_failure_stage3_description",
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.FAN_BLADE_FAILURE,
                repairPrice = stagePartPrices.FAN_BLADE_FAILURE[3],
                effects = {
                    { id = "FAN_CLUTCH_MODIFIER", value = -0.3, aggregation = "min" },
                    { id = "FAN_BLADE_NOISE_EFFECT", value = 0.8, aggregation = "max" },
                },
                indicators = {
                    { id = db.COOLANT, color = color.WARNING, switchOn = true, switchOff = false },
                },
            },
            {
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_fan_blade_failure_stage4_description",
                detectionChance = 1.0,
                progressMultiplier = 0 * breakdownProgressMultipliers.FAN_BLADE_FAILURE,
                repairPrice = stagePartPrices.FAN_BLADE_FAILURE[4],
                renews = { "RADIATOR_CORE" },
                effects = {
                    { id = "FAN_CLUTCH_MODIFIER", value = -0.5, aggregation = "min" },
                    { id = "FAN_BLADE_NOISE_EFFECT", value = 1.0, aggregation = "max" },
                },
                indicators = {
                    { id = db.COOLANT, color = color.CRITICAL, switchOn = true, switchOff = false },
                },
            },
        }
    },

    ELECTRIC_COOLING_FAN_FAILURE = {
        isSelectable = true,
        system = systems.COOLING,
        part = parts.ELECTRIC_COOLING_FAN,
        isApplicable = function(vehicle)
            return getIsElectricVehicle(vehicle)
        end,
        causes = { primary = {}, secondary = {"ohf", "sf"} },
        component = "DC_MOTOR",
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_electric_cooling_fan_failure_stage1_description",
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.ELECTRIC_COOLING_FAN_FAILURE,
                repairPrice = stagePartPrices.ELECTRIC_COOLING_FAN_FAILURE[1],
                effects = {
                    { id = "FAN_CLUTCH_MODIFIER", value = -0.1, aggregation = "min" },
                },
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_electric_cooling_fan_failure_stage2_description",
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.ELECTRIC_COOLING_FAN_FAILURE,
                repairPrice = stagePartPrices.ELECTRIC_COOLING_FAN_FAILURE[2],
                effects = {
                    { id = "FAN_CLUTCH_MODIFIER", value = -0.2, aggregation = "min" },
                },
                indicators = {
                    { id = db.COOLANT, color = color.WARNING, switchOn = true, switchOff = false },
                },
            },
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_electric_cooling_fan_failure_stage3_description",
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.ELECTRIC_COOLING_FAN_FAILURE,
                repairPrice = stagePartPrices.ELECTRIC_COOLING_FAN_FAILURE[3],
                effects = {
                    { id = "FAN_CLUTCH_MODIFIER", value = -0.3, aggregation = "min" },
                },
                indicators = {
                    { id = db.COOLANT, color = color.WARNING, switchOn = true, switchOff = false },
                },
            },
            {
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_electric_cooling_fan_failure_stage4_description",
                detectionChance = 1.0,
                progressMultiplier = 0 * breakdownProgressMultipliers.ELECTRIC_COOLING_FAN_FAILURE,
                repairPrice = stagePartPrices.ELECTRIC_COOLING_FAN_FAILURE[4],
                effects = {
                    { id = "FAN_CLUTCH_MODIFIER", value = -0.5, aggregation = "min" },
                },
                indicators = {
                    { id = db.COOLANT, color = color.CRITICAL, switchOn = true, switchOff = false },
                },
            },
        }
    },
    FAN_CLUTCH_FAILURE = {
        isSelectable = true,
        system = systems.COOLING,
        part = parts.FAN_CLUTCH,
        isApplicable = function(vehicle)
            local drive = RMS_Utils.getFanDrive(vehicle)
            return drive == "VISCOUS" or drive == "ELECTRONIC"
        end,
        causes = { primary = {}, secondary = {"ohf", "sf"} },
        component = "MAGNETIC_CLUTCH",
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_fan_clutch_failure_stage1_description",
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.FAN_CLUTCH_FAILURE,
                repairPrice = stagePartPrices.FAN_CLUTCH_FAILURE[1],
                effects = {
                    { id = "FAN_CLUTCH_MODIFIER", value = -0.1, aggregation = "min"},
                    { id = "FAN_CLUTCH_NOISE_EFFECT", value = 0.6, aggregation = "max" }
                }
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_fan_clutch_failure_stage2_description",
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.FAN_CLUTCH_FAILURE,
                repairPrice = stagePartPrices.FAN_CLUTCH_FAILURE[2],
                effects = {
                    { id = "FAN_CLUTCH_MODIFIER", value = -0.2, aggregation = "min"},
                    { id = "FAN_CLUTCH_NOISE_EFFECT", value = 0.8, aggregation = "max" }
                },
                indicators = {
                    { id = db.COOLANT, color = color.WARNING, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_fan_clutch_failure_stage3_description",
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.FAN_CLUTCH_FAILURE,
                repairPrice = stagePartPrices.FAN_CLUTCH_FAILURE[3],
                effects = {
                    { id = "FAN_CLUTCH_MODIFIER", value = -0.3, aggregation = "min"},
                    { id = "FAN_CLUTCH_NOISE_EFFECT", value = 1.0, aggregation = "max" }
                },
                indicators = {
                    { id = db.COOLANT, color = color.WARNING, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_fan_clutch_failure_stage4_description",
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = stagePartPrices.FAN_CLUTCH_FAILURE[4],
                effects = {
                    { id = "FAN_CLUTCH_MODIFIER", value = -0.5, aggregation = "min"},
                },
                indicators = {
                    { id = db.COOLANT, color = color.CRITICAL, switchOn = true, switchOff = false },
                }
            }
        }
    },

    -- fuel system
    COOLANT_PUMP_FAILURE = {
        isSelectable = true,
        system = systems.COOLING,
        part = parts.COOLANT_PUMP,
        isApplicable = function(vehicle)
            return getIsElectricVehicle(vehicle)
        end,
        causes = { primary = {}, secondary = {"ohf", "sf"} },
        component = "CENTRIFUGAL_PUMP",
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_coolant_pump_failure_stage1_description",
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.COOLANT_PUMP_FAILURE,
                repairPrice = stagePartPrices.COOLANT_PUMP_FAILURE[1],
                effects = {
                    { id = "RADIATOR_HEALTH_MODIFIER", value = -0.20, aggregation = "min" }
                }
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_coolant_pump_failure_stage2_description",
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.COOLANT_PUMP_FAILURE,
                repairPrice = stagePartPrices.COOLANT_PUMP_FAILURE[2],
                effects = {
                    { id = "RADIATOR_HEALTH_MODIFIER", value = -0.40, aggregation = "min" }
                },
                indicators = {
                    { id = db.COOLANT, color = color.WARNING, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_coolant_pump_failure_stage3_description",
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.COOLANT_PUMP_FAILURE,
                repairPrice = stagePartPrices.COOLANT_PUMP_FAILURE[3],
                effects = {
                    { id = "RADIATOR_HEALTH_MODIFIER", value = -0.60, aggregation = "min" }
                },
                indicators = {
                    { id = db.COOLANT, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_coolant_pump_failure_stage4_description",
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = stagePartPrices.COOLANT_PUMP_FAILURE[4],
                effects = {
                    { id = "RADIATOR_HEALTH_MODIFIER", value = -0.85, aggregation = "min" }
                },
                indicators = {
                    { id = db.COOLANT, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            }
        }
    },

    THERMAL_WATER_PUMP = {
        isSelectable = true,
        system = systems.COOLING,
        part = parts.THERMAL_WATER_PUMP,
        isApplicable = function(vehicle)
            return not getIsElectricVehicle(vehicle)
        end,
        causes = { primary = { "sf" }, secondary = {} },
        component = "ENGINE_WATER_PUMP",
        branches = 3,
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_thermal_water_pump_branch1_stage1_description",
                branchDescriptions = {
                    "rms_breakdowns_thermal_water_pump_branch1_stage1_description",
                    "rms_breakdowns_thermal_water_pump_branch2_stage1_description",
                    "rms_breakdowns_thermal_water_pump_branch3_stage1_description"
                },
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.THERMAL_WATER_PUMP,
                repairPrice = stagePartPrices.THERMAL_WATER_PUMP[1],
                effects = {
                    { id = "RADIATOR_HEALTH_MODIFIER", value = -0.2, aggregation = "min" },
                    { id = "COOLANT_LEAK_RATE", value = 0.02, aggregation = "max", branch = 2 }
                },
                inspection = {
                    { additional = "rms_inspection_hint_thermal_water_pump_stage1", branch = 2 }
                }
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_thermal_water_pump_branch1_stage2_description",
                branchDescriptions = {
                    "rms_breakdowns_thermal_water_pump_branch1_stage2_description",
                    "rms_breakdowns_thermal_water_pump_branch2_stage2_description",
                    "rms_breakdowns_thermal_water_pump_branch3_stage2_description"
                },
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.THERMAL_WATER_PUMP,
                repairPrice = stagePartPrices.THERMAL_WATER_PUMP[2],
                effects = {
                    { id = "RADIATOR_HEALTH_MODIFIER", value = -0.4, aggregation = "min" },
                    { id = "COOLANT_LEAK_RATE", value = 0.08, aggregation = "max", branch = 2 },
                    { id = "WATER_PUMP_BEARING_NOISE_EFFECT", value = 0.5, aggregation = "max", branch = 3 }
                },
                indicators = {
                    { id = db.COOLANT, color = color.WARNING, switchOn = true, switchOff = false }
                },
                inspection = {
                    { additional = "rms_inspection_hint_thermal_water_pump_stage2", branch = 2 }
                }
            },
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_thermal_water_pump_branch1_stage3_description",
                branchDescriptions = {
                    "rms_breakdowns_thermal_water_pump_branch1_stage3_description",
                    "rms_breakdowns_thermal_water_pump_branch2_stage3_description",
                    "rms_breakdowns_thermal_water_pump_branch3_stage3_description"
                },
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.THERMAL_WATER_PUMP,
                repairPrice = stagePartPrices.THERMAL_WATER_PUMP[3],
                effects = {
                    { id = "RADIATOR_HEALTH_MODIFIER", value = -0.6, aggregation = "min" },
                    { id = "COOLANT_LEAK_RATE", value = 0.25, aggregation = "max", branch = 2 },
                    { id = "WATER_PUMP_BEARING_NOISE_EFFECT", value = 0.8, aggregation = "max", branch = 3 }
                },
                indicators = {
                    { id = db.COOLANT, color = color.CRITICAL, switchOn = true, switchOff = false }
                },
                inspection = {
                    { additional = "rms_inspection_hint_thermal_water_pump_stage3", branch = 2 }
                }
            },
            {
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_thermal_water_pump_branch1_stage4_description",
                branchDescriptions = {
                    "rms_breakdowns_thermal_water_pump_branch1_stage4_description",
                    "rms_breakdowns_thermal_water_pump_branch2_stage4_description",
                    "rms_breakdowns_thermal_water_pump_branch3_stage4_description"
                },
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = stagePartPrices.THERMAL_WATER_PUMP[4],
                effects = {
                    { id = "RADIATOR_HEALTH_MODIFIER", value = -0.85, aggregation = "min" },
                    { id = "COOLANT_LEAK_RATE", value = 0.8, aggregation = "max", branch = 2 },
                    { id = "WATER_PUMP_BEARING_NOISE_EFFECT", value = 1.0, aggregation = "max", branch = 3 }
                },
                indicators = {
                    { id = db.COOLANT, color = color.CRITICAL, switchOn = true, switchOff = false }
                },
                inspection = {
                    { additional = "rms_inspection_hint_thermal_water_pump_stage4", branch = 2 }
                }
            }
        }
    },

    RADIATOR_CORE = {
        isSelectable = true,
        system = systems.COOLING,
        part = parts.RADIATOR_CORE,
        isApplicable = function(vehicle)
            return true
        end,
        causes = { primary = { "sf" }, secondary = {} },
        component = "HEAT_EXCHANGER",
        branches = 2,
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_radiator_core_branch1_stage1_description",
                branchDescriptions = {
                    "rms_breakdowns_radiator_core_branch1_stage1_description",
                    "rms_breakdowns_radiator_core_branch2_stage1_description"
                },
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.RADIATOR_CORE,
                repairPrice = stagePartPrices.RADIATOR_CORE[1],
                effects = {
                    { id = "RADIATOR_HEALTH_MODIFIER", value = -0.2, aggregation = "min", branch = 1 },
                    { id = "COOLANT_LEAK_RATE", value = 0.02, aggregation = "max", branch = 2 }
                },
                inspection = {
                    { additional = "rms_inspection_hint_radiator_core_stage1", branch = 2 }
                }
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_radiator_core_branch1_stage2_description",
                branchDescriptions = {
                    "rms_breakdowns_radiator_core_branch1_stage2_description",
                    "rms_breakdowns_radiator_core_branch2_stage2_description"
                },
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.RADIATOR_CORE,
                repairPrice = stagePartPrices.RADIATOR_CORE[2],
                effects = {
                    { id = "RADIATOR_HEALTH_MODIFIER", value = -0.4, aggregation = "min", branch = 1 },
                    { id = "COOLANT_LEAK_RATE", value = 0.08, aggregation = "max", branch = 2 }
                },
                inspection = {
                    { additional = "rms_inspection_hint_radiator_core_stage2", branch = 2 }
                }
            },
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_radiator_core_branch1_stage3_description",
                branchDescriptions = {
                    "rms_breakdowns_radiator_core_branch1_stage3_description",
                    "rms_breakdowns_radiator_core_branch2_stage3_description"
                },
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.RADIATOR_CORE,
                repairPrice = stagePartPrices.RADIATOR_CORE[3],
                effects = {
                    { id = "RADIATOR_HEALTH_MODIFIER", value = -0.6, aggregation = "min", branch = 1 },
                    { id = "COOLANT_LEAK_RATE", value = 0.25, aggregation = "max", branch = 2 }
                },
                indicators = {
                    { id = db.COOLANT, color = color.CRITICAL, switchOn = true, switchOff = false, branch = 1 },
                    { id = db.COOLANT, color = color.WARNING, switchOn = true, switchOff = false, branch = 2 }
                },
                inspection = {
                    { additional = "rms_inspection_hint_radiator_core_stage3", branch = 2 }
                }
            },
            {
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_radiator_core_branch1_stage4_description",
                branchDescriptions = {
                    "rms_breakdowns_radiator_core_branch1_stage4_description",
                    "rms_breakdowns_radiator_core_branch2_stage4_description"
                },
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = stagePartPrices.RADIATOR_CORE[4],
                effects = {
                    { id = "RADIATOR_HEALTH_MODIFIER", value = -0.85, aggregation = "min", branch = 1 },
                    { id = "COOLANT_LEAK_RATE", value = 0.8, aggregation = "max", branch = 2 }
                },
                indicators = {
                    { id = db.COOLANT, color = color.CRITICAL, switchOn = true, switchOff = false, branch = 1 },
                    { id = db.COOLANT, color = color.CRITICAL, switchOn = true, switchOff = false, branch = 2 }
                },
                inspection = {
                    { additional = "rms_inspection_hint_radiator_core_stage4", branch = 2 }
                }
            }
        }
    },
    FUEL_PUMP_MALFUNCTION = {
        isSelectable = true,
        system = systems.FUEL,
        part = parts.FUEL_PUMP,
        isApplicable = function(vehicle)
            return RMS_Preheat.isDieselVehicle(vehicle) and not (vehicle.spec_motorized and vehicle.spec_motorized.consumersByFillTypeName and vehicle.spec_motorized.consumersByFillTypeName.METHANE)
        end,
        causes = { primary = {}, secondary = {"sf"} },
        component = "CENTRIFUGAL_PUMP",
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_fuel_pump_malfunction_stage1_description",
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.FUEL_PUMP_MALFUNCTION,
                repairPrice = stagePartPrices.FUEL_PUMP_MALFUNCTION[1],
                effects = {
                    { id = "IDLE_HUNTING_EFFECT", value = 0.05, aggregation = "max", extraData = { timer = 0, period = 1800} },
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.05, aggregation = "sum" },
                    { id = "FUEL_CONSUMPTION_MODIFIER", value = 0.15, aggregation = "sum" },
                    { id = "ENGINE_HARD_START_MODIFIER", value = 2, aggregation = "max", extraData = { timer = 0, status = 'IDLE'}},
                    { id = "ENGINE_HESITATION_CHANCE", value = 0.3, aggregation = "min", extraData = {timer = 0, duration = 300, status = 'IDLE', amplitude = 0.6, motorLoad = 0.8, cruiseState = 0} }
                }
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_fuel_pump_malfunction_stage2_description",
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.FUEL_PUMP_MALFUNCTION,
                repairPrice = stagePartPrices.FUEL_PUMP_MALFUNCTION[2],
                effects = {
                    { id = "IDLE_HUNTING_EFFECT", value = 0.08, aggregation = "max", extraData = { timer = 0, period = 1600} },
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.12, aggregation = "sum" },
                    { id = "FUEL_CONSUMPTION_MODIFIER", value = 0.4, aggregation = "sum" },
                    { id = "ENGINE_STALLS_CHANCE", value = 20.0, aggregation = "min" },
                    { id = "ENGINE_HARD_START_MODIFIER", value = 4, aggregation = "max", extraData = { timer = 0, status = 'IDLE'}},
                    { id = "EXHAUST_UNBURNT", value = 0.20, aggregation = "max" },
                    { id = "ENGINE_HESITATION_CHANCE", value = 0.2, aggregation = "min", extraData = {timer = 0, duration = 400, status = 'IDLE', amplitude = 1.0, motorLoad = 0.7, cruiseState = 0} }
                },
                indicators = {
                    {  
                        id = db.ENGINE,
                        color = color.WARNING,
                        switchOn = function(vehicle)
                            if vehicle.spec_motorized and vehicle:getIsMotorStarted() and vehicle:getMotorLoadPercentage() > 0.95 then
                                return true
                            end
                            return false
                        end,
                        switchOff = false
                    }
                }
            },
            { 
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_fuel_pump_malfunction_stage3_description",
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.FUEL_PUMP_MALFUNCTION,
                repairPrice = stagePartPrices.FUEL_PUMP_MALFUNCTION[3],
                effects = {
                    { id = "IDLE_HUNTING_EFFECT", value = 0.10, aggregation = "max", extraData = { timer = 0, period = 1500} },
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.25, aggregation = "sum" },
                    { id = "FUEL_CONSUMPTION_MODIFIER", value = 1.0, aggregation = "sum" },
                    { id = "ENGINE_STALLS_CHANCE", value = 10.0, aggregation = "min" },
                    { id = "ENGINE_HARD_START_MODIFIER", value = 6, aggregation = "max", extraData = { timer = 0, status = 'IDLE'}},
                    { id = "EXHAUST_UNBURNT", value = 0.30, aggregation = "max" },
                    { id = "EXHAUST_SOOT", value = 0.15, aggregation = "max" },
                    { id = "ENGINE_HESITATION_CHANCE", value = 0.15, aggregation = "min", extraData = {timer = 0, duration = 500, status = 'IDLE', amplitude = 1.0, motorLoad = 0.5, cruiseState = 0} }
                },
                indicators = {
                    { id = db.ENGINE, color = color.WARNING, switchOn = true, switchOff = false }
                }
            },
            { 
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_fuel_pump_malfunction_stage4_description",
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = stagePartPrices.FUEL_PUMP_MALFUNCTION[4],
                effects = { 
                        {
                            id = "ENGINE_FAILURE",
                            value = 1.0,
                            aggregation = "boolean_or",
                            extraData = {
                                status = 'IDLE',
                                starter = true,
                                reason = "BREAKDOWN",
                                disableAi = true
                            }
                        }
                },
                indicators = {
                    { id = db.ENGINE, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            }
        }
    },

    FUEL_INJECTOR_MALFUNCTION = {
        isSelectable = true,
        system = systems.FUEL,
        part = parts.FUEL_INJECTORS,
        isApplicable = function(vehicle)
            return RMS_Preheat.isDieselVehicle(vehicle) and not (vehicle.spec_motorized and vehicle.spec_motorized.consumersByFillTypeName and vehicle.spec_motorized.consumersByFillTypeName.METHANE)
        end,
        causes = { primary = {}, secondary = {} },
        component = "SOLENOID_VALVE",
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_fuel_injector_malfunction_stage1_description",
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.FUEL_INJECTOR_MALFUNCTION,
                repairPrice = stagePartPrices.FUEL_INJECTOR_MALFUNCTION[1],
                effects = {
                    { id = "IDLE_HUNTING_EFFECT", value = 0.05, aggregation = "max", extraData = { timer = 0, period = 1800} },
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.08, aggregation = "sum" },
                    { id = "FUEL_CONSUMPTION_MODIFIER", value = 0.10, aggregation = "sum" },
                    { id = "EXHAUST_SOOT", value = 0.20, aggregation = "max" },
                    { id = "EXHAUST_UNBURNT", value = 0.15, aggregation = "max" },
                    { id = "ENGINE_HESITATION_CHANCE", value = 0.4, aggregation = "min", extraData = {timer = 0, duration = 300, status = 'IDLE', amplitude = 0.6, motorLoad = 0.9, cruiseState = 0} },
                    { id = "INJECTOR_KNOCK_NOISE_EFFECT", value = 0.3, aggregation = "max" }
                }
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_fuel_injector_malfunction_stage2_description",
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.FUEL_INJECTOR_MALFUNCTION,
                repairPrice = stagePartPrices.FUEL_INJECTOR_MALFUNCTION[2],
                effects = {
                    { id = "IDLE_HUNTING_EFFECT", value = 0.08, aggregation = "max", extraData = { timer = 0, period = 1500} },
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.20, aggregation = "sum" },
                    { id = "FUEL_CONSUMPTION_MODIFIER", value = 0.25, aggregation = "sum" },
                    { id = "ENGINE_STALLS_CHANCE", value = 30.0, aggregation = "min" },
                    { id = "EXHAUST_SOOT", value = 0.40, aggregation = "max" },
                    { id = "EXHAUST_UNBURNT", value = 0.30, aggregation = "max" },
                    { id = "ENGINE_HESITATION_CHANCE", value = 0.3, aggregation = "min", extraData = {timer = 0, duration = 400, status = 'IDLE', amplitude = 0.8, motorLoad = 0.8, cruiseState = 0} },
                    { id = "INJECTOR_KNOCK_NOISE_EFFECT", value = 0.5, aggregation = "max" }
                },
                indicators = {
                    { id = db.ENGINE, color = color.WARNING, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_fuel_injector_malfunction_stage3_description",
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.FUEL_INJECTOR_MALFUNCTION,
                repairPrice = stagePartPrices.FUEL_INJECTOR_MALFUNCTION[3],
                effects = {
                    { id = "IDLE_HUNTING_EFFECT", value = 0.10, aggregation = "max", extraData = { timer = 0, period = 1800} },
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.35, aggregation = "sum" },
                    { id = "FUEL_CONSUMPTION_MODIFIER", value = 0.50, aggregation = "sum" },
                    { id = "ENGINE_HARD_START_MODIFIER", value = 6, aggregation = "max", extraData = { timer = 0, status = 'IDLE'}},
                    { id = "EXHAUST_SOOT", value = 0.70, aggregation = "max" },
                    { id = "EXHAUST_UNBURNT", value = 0.50, aggregation = "max" },
                    { id = "ENGINE_HESITATION_CHANCE", value = 0.2, aggregation = "min", extraData = {timer = 0, duration = 500, status = 'IDLE', amplitude = 1.0, motorLoad = 0.7, cruiseState = 0} },
                    { id = "INJECTOR_KNOCK_NOISE_EFFECT", value = 0.8, aggregation = "max" }
                },
                indicators = {
                    { id = db.ENGINE, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_fuel_injector_malfunction_stage4_description",
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = stagePartPrices.FUEL_INJECTOR_MALFUNCTION[4],
                effects = {
                        {
                            id = "ENGINE_FAILURE",
                            value = 1.0,
                            aggregation = "boolean_or",
                            extraData = {
                                status = 'IDLE',
                                starter = true,
                                reason = "BREAKDOWN",
                                disableAi = true
                            }
                        },
                    { id = "INJECTOR_KNOCK_NOISE_EFFECT", value = 1.0, aggregation = "max" }
                },
                indicators = {
                    { id = db.ENGINE, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            }
        }
    },

    HIGH_PRESSURE_PUMP_MALFUNCTION = {
        isSelectable = true,
        system = systems.FUEL,
        part = parts.HIGH_PRESSURE_PUMP,
        isApplicable = function(vehicle)
            return RMS_Preheat.isDieselVehicle(vehicle) and RMS_Utils.getUsesEngineECUProfile(vehicle) ~= false
                and not (vehicle.spec_motorized and vehicle.spec_motorized.consumersByFillTypeName and vehicle.spec_motorized.consumersByFillTypeName.METHANE)
        end,
        causes = { primary = {"sf"}, secondary = {} },
        component = "HIGH_PRESSURE_INJECTION_BUDGET",
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_high_pressure_pump_malfunction_stage1_description",
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.HIGH_PRESSURE_PUMP_MALFUNCTION,
                repairPrice = stagePartPrices.HIGH_PRESSURE_PUMP_MALFUNCTION[1],
                effects = {
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.05, aggregation = "sum" },
                    { id = "ENGINE_HARD_START_MODIFIER", value = 2, aggregation = "max", extraData = { timer = 0, status = 'IDLE'}},
                    { id = "HIGH_PRESSURE_PUMP_NOISE_EFFECT", value = 0.3, aggregation = "max" }
                }
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_high_pressure_pump_malfunction_stage2_description",
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.HIGH_PRESSURE_PUMP_MALFUNCTION,
                repairPrice = stagePartPrices.HIGH_PRESSURE_PUMP_MALFUNCTION[2],
                effects = {
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.15, aggregation = "sum" },
                    { id = "ENGINE_HARD_START_MODIFIER", value = 4, aggregation = "max", extraData = { timer = 0, status = 'IDLE'}},
                    { id = "ENGINE_HESITATION_CHANCE", value = 0.3, aggregation = "min", extraData = {timer = 0, duration = 300, status = 'IDLE', amplitude = 0.6, motorLoad = 0.8, cruiseState = 0} },
                    { id = "HIGH_PRESSURE_PUMP_NOISE_EFFECT", value = 0.5, aggregation = "max" }
                },
                indicators = {
                    { id = db.ENGINE, color = color.WARNING, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_high_pressure_pump_malfunction_stage3_description",
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.HIGH_PRESSURE_PUMP_MALFUNCTION,
                repairPrice = stagePartPrices.HIGH_PRESSURE_PUMP_MALFUNCTION[3],
                effects = {
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.30, aggregation = "sum" },
                    { id = "ENGINE_HARD_START_MODIFIER", value = 6, aggregation = "max", extraData = { timer = 0, status = 'IDLE'}},
                    { id = "ENGINE_STALLS_CHANCE", value = 10.0, aggregation = "min" },
                    { id = "ENGINE_HESITATION_CHANCE", value = 0.2, aggregation = "min", extraData = {timer = 0, duration = 400, status = 'IDLE', amplitude = 1.0, motorLoad = 0.7, cruiseState = 0} },
                    { id = "HIGH_PRESSURE_PUMP_NOISE_EFFECT", value = 0.8, aggregation = "max" }
                },
                indicators = {
                    { id = db.ENGINE, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_high_pressure_pump_malfunction_stage4_description",
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = stagePartPrices.HIGH_PRESSURE_PUMP_MALFUNCTION[4],
                effects = {
                    {
                        id = "ENGINE_FAILURE",
                        value = 1.0,
                        aggregation = "boolean_or",
                        extraData = {
                            status = 'IDLE',
                            starter = true,
                            reason = "BREAKDOWN",
                            disableAi = true
                        }
                    },
                    { id = "HIGH_PRESSURE_PUMP_NOISE_EFFECT", value = 1.0, aggregation = "max" }
                },
                indicators = {
                    { id = db.ENGINE, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            }
        }
    },

    FUEL_FILTER_CLOGGING = {
        isSelectable = true,
        system = systems.FUEL,
        part = parts.FUEL_FILTER,
        isApplicable = function(vehicle)
            return RMS_Preheat.isDieselVehicle(vehicle) and not (vehicle.spec_motorized and vehicle.spec_motorized.consumersByFillTypeName and vehicle.spec_motorized.consumersByFillTypeName.METHANE)
        end,
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_fuel_filter_clogging_stage1_description",
                detectionChance = 1.0,
                progressMultiplier = 0.0,
                repairPrice = stagePartPrices.FUEL_FILTER_CLOGGING[1],
                effects = {
                        {
                            id = "ENGINE_HESITATION_CHANCE",
                            value = 0.4,
                            aggregation = "min",
                            extraData = {
                                timer = 0,
                                duration = 300,
                                status = 'IDLE',
                                amplitude = 0.6,
                                motorLoad = 0.9,
                                cruiseState = 0
                            }
                        },
                     { id = "ENGINE_TORQUE_MODIFIER", value = -0.03, aggregation = "sum" },
                }
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_fuel_filter_clogging_stage2_description",
                detectionChance = 1.0,
                progressMultiplier = 0.0,
                repairPrice = stagePartPrices.FUEL_FILTER_CLOGGING[2],
                effects = {
                        {
                            id = "ENGINE_HESITATION_CHANCE",
                            value = 0.3,
                            aggregation = "min",
                            extraData = {
                                timer = 0,
                                duration = 400,
                                status = 'IDLE',
                                amplitude = 0.7,
                                motorLoad = 0.9,
                                cruiseState = 0
                            }
                        },
                     { id = "ENGINE_TORQUE_MODIFIER", value = -0.06, aggregation = "sum" },
                     { id = "ENGINE_STALLS_CHANCE", value = 30.0, aggregation = "min" },
                     { id = "EXHAUST_UNBURNT", value = 0.15, aggregation = "max" },
                }
            },
            { 
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_fuel_filter_clogging_stage3_description",
                detectionChance = 1.0,
                progressMultiplier = 0.0,
                repairPrice = stagePartPrices.FUEL_FILTER_CLOGGING[3],
                effects = { 
                    { id = "ENGINE_HESITATION_CHANCE", value = 0.2, aggregation = "min", extraData = {timer = 0, duration = 500, status = 'IDLE', amplitude = 0.7, motorLoad = 0.9, cruiseState = 0} },
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.1, aggregation = "sum" },
                    { id = "ENGINE_STALLS_CHANCE", value = 20.0, aggregation = "min" },
                    { id = "EXHAUST_UNBURNT", value = 0.25, aggregation = "max" },
                    { id = "EXHAUST_SOOT", value = 0.15, aggregation = "max" },
                }
            },
            { 
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_fuel_filter_clogging_stage4_description",
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = stagePartPrices.FUEL_FILTER_CLOGGING[4],
                effects = {
                        {
                            id = "ENGINE_FAILURE",
                            value = 1.0,
                            aggregation = "boolean_or",
                            extraData = {
                                status = 'IDLE',
                                starter = true,
                                reason = "BREAKDOWN",
                                disableAi = true
                            }
                        }
                }
            }
        }
    },

    FUEL_LINE_AIR_LEAK = {
        isSelectable = true,
        system = systems.FUEL,
        part = parts.FUEL_LINE,
        isApplicable = function(vehicle)
            return RMS_Preheat.isDieselVehicle(vehicle) and not (vehicle.spec_motorized and vehicle.spec_motorized.consumersByFillTypeName and vehicle.spec_motorized.consumersByFillTypeName.METHANE)
        end,
        causes = { primary = {}, secondary = {"sf"} },
        component = "O_RING",
        branches = 2,
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_fuel_line_air_leak_branch1_stage1_description",
                branchDescriptions = { "rms_breakdowns_fuel_line_air_leak_branch1_stage1_description", "rms_breakdowns_fuel_line_air_leak_branch2_stage1_description" },
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.FUEL_LINE_AIR_LEAK,
                repairPrice = stagePartPrices.FUEL_LINE_AIR_LEAK[1],
                effects = {
                    { id = "ENGINE_HARD_START_MODIFIER", value = 1, aggregation = "max", branch = 1, extraData = { timer = 0, status = 'IDLE', count = 0}},
                    { id = "ENGINE_STALLS_CHANCE", value = 40.0, aggregation = "min", branch = 2 }}
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_fuel_line_air_leak_branch1_stage2_description",
                branchDescriptions = { "rms_breakdowns_fuel_line_air_leak_branch1_stage2_description", "rms_breakdowns_fuel_line_air_leak_branch2_stage2_description" },
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.FUEL_LINE_AIR_LEAK,
                repairPrice = stagePartPrices.FUEL_LINE_AIR_LEAK[2],
                effects = {
                    { id = "ENGINE_HESITATION_CHANCE", value = 0.3, aggregation = "min", branch = 1,
                        extraData = {timer = 0, duration = 300, status = 'IDLE', amplitude = 0.6, motorLoad = 0.5, cruiseState = 0} },
                    { id = "ENGINE_HARD_START_MODIFIER", value = 2, aggregation = "max", branch = 1, extraData = { timer = 0, status = 'IDLE', count = 0}},
                    { id = "ENGINE_STALLS_CHANCE", value = 20.0, aggregation = "min", branch = 1 },
                    { id = "EXHAUST_UNBURNT", value = 0.20, aggregation = "max", branch = 1 },
                
                    { id = "ENGINE_STALLS_CHANCE", value = 20.0, aggregation = "min", branch = 2 }}
            },
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_fuel_line_air_leak_branch1_stage3_description",
                branchDescriptions = { "rms_breakdowns_fuel_line_air_leak_branch1_stage3_description", "rms_breakdowns_fuel_line_air_leak_branch2_stage3_description" },
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.FUEL_LINE_AIR_LEAK,
                repairPrice = stagePartPrices.FUEL_LINE_AIR_LEAK[3],
                effects = {
                    { id = "ENGINE_HESITATION_CHANCE", value = 0.2, aggregation = "min", branch = 1,
                        extraData = {timer = 0, duration = 500, status = 'IDLE', amplitude = 0.7, motorLoad = 0.5, cruiseState = 0} },
                    { id = "ENGINE_HARD_START_MODIFIER", value = 3, aggregation = "max", branch = 1, extraData = {timer = 0, status = 'IDLE'}},
                    { id = "ENGINE_STALLS_CHANCE", value = 10.0, aggregation = "min", branch = 1 },
                    { id = "EXHAUST_UNBURNT", value = 0.35, aggregation = "max", branch = 1 },
                
                    { id = "ENGINE_STALLS_CHANCE", value = 10.0, aggregation = "min", branch = 2 }}
            },
            {
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_fuel_line_air_leak_branch1_stage4_description",
                branchDescriptions = { "rms_breakdowns_fuel_line_air_leak_branch1_stage4_description", "rms_breakdowns_fuel_line_air_leak_branch2_stage4_description" },
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = stagePartPrices.FUEL_LINE_AIR_LEAK[4],
                effects = {
                        {
                            id = "ENGINE_FAILURE",
                            value = 1.0,
                            aggregation = "boolean_or", branch = 1,
                            extraData = {
                                status = 'IDLE',
                                starter = true,
                                reason = "BREAKDOWN",
                                disableAi = true
                            }
                        },{ id = "ENGINE_FAILURE", value = 1.0, aggregation = "boolean_or", branch = 2,
                            extraData = { status = 'IDLE', starter = true, reason = "BREAKDOWN", disableAi = true } }}
            }
        }
    },

    MECHANICAL_INJECTION_PUMP_MALFUNCTION = {
        isSelectable = true,
        system = systems.FUEL,
        part = parts.MECHANICAL_INJECTION_PUMP,
        isApplicable = function(vehicle)
            return RMS_Preheat.isDieselVehicle(vehicle) and not RMS_Utils.getUsesEngineECUProfile(vehicle)
                and not (vehicle.spec_motorized and vehicle.spec_motorized.consumersByFillTypeName and vehicle.spec_motorized.consumersByFillTypeName.METHANE)
        end,
        causes = { primary = {"sf"}, secondary = {} },
        component = "LUBRICATOR_PUMP",
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_mechanical_injection_pump_malfunction_stage1_description",
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.MECHANICAL_INJECTION_PUMP_MALFUNCTION,
                repairPrice = stagePartPrices.MECHANICAL_INJECTION_PUMP_MALFUNCTION[1],
                effects = {
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.05, aggregation = "sum" },
                    { id = "ENGINE_HARD_START_MODIFIER", value = 2, aggregation = "max", extraData = { timer = 0, status = 'IDLE'}},
                    { id = "INJECTOR_KNOCK_NOISE_EFFECT", value = 0.3, aggregation = "max" }
                }
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_mechanical_injection_pump_malfunction_stage2_description",
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.MECHANICAL_INJECTION_PUMP_MALFUNCTION,
                repairPrice = stagePartPrices.MECHANICAL_INJECTION_PUMP_MALFUNCTION[2],
                effects = {
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.15, aggregation = "sum" },
                    { id = "ENGINE_HARD_START_MODIFIER", value = 4, aggregation = "max", extraData = { timer = 0, status = 'IDLE'}},
                    { id = "ENGINE_HESITATION_CHANCE", value = 0.3, aggregation = "min", extraData = {timer = 0, duration = 300, status = 'IDLE', amplitude = 0.6, motorLoad = 0.8, cruiseState = 0} },
                    { id = "INJECTOR_KNOCK_NOISE_EFFECT", value = 0.5, aggregation = "max" }
                }
            },
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_mechanical_injection_pump_malfunction_stage3_description",
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.MECHANICAL_INJECTION_PUMP_MALFUNCTION,
                repairPrice = stagePartPrices.MECHANICAL_INJECTION_PUMP_MALFUNCTION[3],
                effects = {
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.30, aggregation = "sum" },
                    { id = "ENGINE_HARD_START_MODIFIER", value = 6, aggregation = "max", extraData = { timer = 0, status = 'IDLE'}},
                    { id = "ENGINE_STALLS_CHANCE", value = 10.0, aggregation = "min" },
                    { id = "ENGINE_HESITATION_CHANCE", value = 0.2, aggregation = "min", extraData = {timer = 0, duration = 400, status = 'IDLE', amplitude = 1.0, motorLoad = 0.7, cruiseState = 0} },
                    { id = "INJECTOR_KNOCK_NOISE_EFFECT", value = 0.8, aggregation = "max" }
                }
            },
            {
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_mechanical_injection_pump_malfunction_stage4_description",
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = stagePartPrices.MECHANICAL_INJECTION_PUMP_MALFUNCTION[4],
                effects = {
                    {
                        id = "ENGINE_FAILURE",
                        value = 1.0,
                        aggregation = "boolean_or",
                        extraData = {
                            status = 'IDLE',
                            starter = true,
                            reason = "BREAKDOWN",
                            disableAi = true
                        }
                    },
                    { id = "INJECTOR_KNOCK_NOISE_EFFECT", value = 1.0, aggregation = "max" }
                }
            }
        }
    },
    FUEL_METERING_VALVE_FAILURE = {
        isSelectable = true,
        system = systems.FUEL,
        part = parts.FUEL_METERING_VALVE,
        isApplicable = function(vehicle)
            return RMS_Preheat.isDieselVehicle(vehicle) and RMS_Utils.getUsesEngineECUProfile(vehicle)
        end,
        causes = { primary = {"sf"}, secondary = {} },
        component = "HIGH_PRESSURE_INJECTION_BUDGET",
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_fuel_metering_valve_failure_stage1_description",
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.FUEL_METERING_VALVE_FAILURE,
                repairPrice = stagePartPrices.FUEL_METERING_VALVE_FAILURE[1],
                effects = {
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.05, aggregation = "sum" },
                    { id = "ENGINE_HARD_START_MODIFIER", value = 2, aggregation = "max", extraData = { timer = 0, status = 'IDLE'}}
                }
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_fuel_metering_valve_failure_stage2_description",
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.FUEL_METERING_VALVE_FAILURE,
                repairPrice = stagePartPrices.FUEL_METERING_VALVE_FAILURE[2],
                effects = {
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.15, aggregation = "sum" },
                    { id = "ENGINE_HARD_START_MODIFIER", value = 4, aggregation = "max", extraData = { timer = 0, status = 'IDLE'}},
                    { id = "ENGINE_HESITATION_CHANCE", value = 0.3, aggregation = "min", extraData = {timer = 0, duration = 300, status = 'IDLE', amplitude = 0.6, motorLoad = 0.8, cruiseState = 0} }
                },
                indicators = {
                    { id = db.ENGINE, color = color.WARNING, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_fuel_metering_valve_failure_stage3_description",
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.FUEL_METERING_VALVE_FAILURE,
                repairPrice = stagePartPrices.FUEL_METERING_VALVE_FAILURE[3],
                effects = {
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.30, aggregation = "sum" },
                    { id = "ENGINE_HARD_START_MODIFIER", value = 6, aggregation = "max", extraData = { timer = 0, status = 'IDLE'}},
                    { id = "ENGINE_STALLS_CHANCE", value = 10.0, aggregation = "min" },
                    { id = "ENGINE_HESITATION_CHANCE", value = 0.2, aggregation = "min", extraData = {timer = 0, duration = 400, status = 'IDLE', amplitude = 1.0, motorLoad = 0.7, cruiseState = 0} }
                },
                indicators = {
                    { id = db.ENGINE, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_fuel_metering_valve_failure_stage4_description",
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = stagePartPrices.FUEL_METERING_VALVE_FAILURE[4],
                effects = {
                    {
                        id = "ENGINE_FAILURE",
                        value = 1.0,
                        aggregation = "boolean_or",
                        extraData = {
                            status = 'IDLE',
                            starter = true,
                            reason = "BREAKDOWN",
                            disableAi = true
                        }
                    }
                },
                indicators = {
                    { id = db.ENGINE, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            }
        }
    },
    RAIL_PRESSURE_SENSOR_FAILURE = {
        isSelectable = true,
        system = systems.FUEL,
        part = parts.RAIL_PRESSURE_SENSOR,
        isApplicable = function(vehicle)
            return RMS_Preheat.isDieselVehicle(vehicle) and RMS_Utils.getUsesEngineECUProfile(vehicle)
        end,
        causes = { primary = {"sf"}, secondary = {} },
        component = "HIGH_PRESSURE_INJECTION_BUDGET",
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_rail_pressure_sensor_failure_stage1_description",
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.RAIL_PRESSURE_SENSOR_FAILURE,
                repairPrice = stagePartPrices.RAIL_PRESSURE_SENSOR_FAILURE[1],
                effects = {
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.05, aggregation = "sum" },
                    { id = "ENGINE_HARD_START_MODIFIER", value = 2, aggregation = "max", extraData = { timer = 0, status = 'IDLE'}}
                }
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_rail_pressure_sensor_failure_stage2_description",
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.RAIL_PRESSURE_SENSOR_FAILURE,
                repairPrice = stagePartPrices.RAIL_PRESSURE_SENSOR_FAILURE[2],
                effects = {
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.15, aggregation = "sum" },
                    { id = "ENGINE_HARD_START_MODIFIER", value = 4, aggregation = "max", extraData = { timer = 0, status = 'IDLE'}},
                    { id = "ENGINE_HESITATION_CHANCE", value = 0.3, aggregation = "min", extraData = {timer = 0, duration = 300, status = 'IDLE', amplitude = 0.6, motorLoad = 0.8, cruiseState = 0} }
                },
                indicators = {
                    { id = db.ENGINE, color = color.WARNING, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_rail_pressure_sensor_failure_stage3_description",
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.RAIL_PRESSURE_SENSOR_FAILURE,
                repairPrice = stagePartPrices.RAIL_PRESSURE_SENSOR_FAILURE[3],
                effects = {
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.30, aggregation = "sum" },
                    { id = "ENGINE_HARD_START_MODIFIER", value = 6, aggregation = "max", extraData = { timer = 0, status = 'IDLE'}},
                    { id = "ENGINE_STALLS_CHANCE", value = 10.0, aggregation = "min" },
                    { id = "ENGINE_HESITATION_CHANCE", value = 0.2, aggregation = "min", extraData = {timer = 0, duration = 400, status = 'IDLE', amplitude = 1.0, motorLoad = 0.7, cruiseState = 0} }
                },
                indicators = {
                    { id = db.ENGINE, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_rail_pressure_sensor_failure_stage4_description",
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = stagePartPrices.RAIL_PRESSURE_SENSOR_FAILURE[4],
                effects = {
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.30, aggregation = "sum" },
                    { id = "ENGINE_HARD_START_MODIFIER", value = 6, aggregation = "max", extraData = { timer = 0, status = 'IDLE'}},
                    { id = "ENGINE_STALLS_CHANCE", value = 10.0, aggregation = "min" },
                    { id = "ENGINE_HESITATION_CHANCE", value = 0.2, aggregation = "min", extraData = {timer = 0, duration = 400, status = 'IDLE', amplitude = 1.0, motorLoad = 0.7, cruiseState = 0} }
                },
                indicators = {
                    { id = db.ENGINE, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            }
        }
    },
    RAIL_PRESSURE_LIMITER_FAILURE = {
        isSelectable = true,
        system = systems.FUEL,
        part = parts.RAIL_PRESSURE_LIMITER,
        isApplicable = function(vehicle)
            return RMS_Preheat.isDieselVehicle(vehicle) and RMS_Utils.getUsesEngineECUProfile(vehicle)
        end,
        causes = { primary = {"sf"}, secondary = {} },
        component = "RELIEF_VALVE",
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_rail_pressure_limiter_failure_stage1_description",
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.RAIL_PRESSURE_LIMITER_FAILURE,
                repairPrice = stagePartPrices.RAIL_PRESSURE_LIMITER_FAILURE[1],
                effects = {
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.05, aggregation = "sum" },
                    { id = "ENGINE_HARD_START_MODIFIER", value = 2, aggregation = "max", extraData = { timer = 0, status = 'IDLE'}}
                }
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_rail_pressure_limiter_failure_stage2_description",
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.RAIL_PRESSURE_LIMITER_FAILURE,
                repairPrice = stagePartPrices.RAIL_PRESSURE_LIMITER_FAILURE[2],
                effects = {
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.15, aggregation = "sum" },
                    { id = "ENGINE_HARD_START_MODIFIER", value = 4, aggregation = "max", extraData = { timer = 0, status = 'IDLE'}},
                    { id = "ENGINE_HESITATION_CHANCE", value = 0.3, aggregation = "min", extraData = {timer = 0, duration = 300, status = 'IDLE', amplitude = 0.6, motorLoad = 0.8, cruiseState = 0} }
                },
                indicators = {
                    { id = db.ENGINE, color = color.WARNING, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_rail_pressure_limiter_failure_stage3_description",
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.RAIL_PRESSURE_LIMITER_FAILURE,
                repairPrice = stagePartPrices.RAIL_PRESSURE_LIMITER_FAILURE[3],
                effects = {
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.30, aggregation = "sum" },
                    { id = "ENGINE_HARD_START_MODIFIER", value = 6, aggregation = "max", extraData = { timer = 0, status = 'IDLE'}},
                    { id = "ENGINE_STALLS_CHANCE", value = 10.0, aggregation = "min" },
                    { id = "ENGINE_HESITATION_CHANCE", value = 0.2, aggregation = "min", extraData = {timer = 0, duration = 400, status = 'IDLE', amplitude = 1.0, motorLoad = 0.7, cruiseState = 0} }
                },
                indicators = {
                    { id = db.ENGINE, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_rail_pressure_limiter_failure_stage4_description",
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = stagePartPrices.RAIL_PRESSURE_LIMITER_FAILURE[4],
                effects = {
                    {
                        id = "ENGINE_FAILURE",
                        value = 1.0,
                        aggregation = "boolean_or",
                        extraData = {
                            status = 'IDLE',
                            starter = true,
                            reason = "BREAKDOWN",
                            disableAi = true
                        }
                    }
                },
                indicators = {
                    { id = db.ENGINE, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            }
        }
    },
    GAS_PRESSURE_REGULATOR_FAILURE = {
        isSelectable = true,
        system = systems.FUEL,
        part = parts.GAS_PRESSURE_REGULATOR,
        isApplicable = function(vehicle)
            return vehicle.spec_motorized and vehicle.spec_motorized.consumersByFillTypeName and vehicle.spec_motorized.consumersByFillTypeName.METHANE ~= nil
        end,
        causes = { primary = {"sf"}, secondary = {} },
        component = "RUBBER_DIAPHRAGM",
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_gas_pressure_regulator_failure_stage1_description",
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.GAS_PRESSURE_REGULATOR_FAILURE,
                repairPrice = stagePartPrices.GAS_PRESSURE_REGULATOR_FAILURE[1],
                effects = {
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.05, aggregation = "sum" },
                    { id = "ENGINE_HARD_START_MODIFIER", value = 2, aggregation = "max", extraData = { timer = 0, status = 'IDLE'}}
                }
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_gas_pressure_regulator_failure_stage2_description",
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.GAS_PRESSURE_REGULATOR_FAILURE,
                repairPrice = stagePartPrices.GAS_PRESSURE_REGULATOR_FAILURE[2],
                effects = {
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.15, aggregation = "sum" },
                    { id = "ENGINE_HARD_START_MODIFIER", value = 4, aggregation = "max", extraData = { timer = 0, status = 'IDLE'}},
                    { id = "ENGINE_HESITATION_CHANCE", value = 0.3, aggregation = "min", extraData = {timer = 0, duration = 300, status = 'IDLE', amplitude = 0.6, motorLoad = 0.8, cruiseState = 0} }
                },
                indicators = {
                    { id = db.ENGINE, color = color.WARNING, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_gas_pressure_regulator_failure_stage3_description",
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.GAS_PRESSURE_REGULATOR_FAILURE,
                repairPrice = stagePartPrices.GAS_PRESSURE_REGULATOR_FAILURE[3],
                effects = {
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.30, aggregation = "sum" },
                    { id = "ENGINE_HARD_START_MODIFIER", value = 6, aggregation = "max", extraData = { timer = 0, status = 'IDLE'}},
                    { id = "ENGINE_STALLS_CHANCE", value = 10.0, aggregation = "min" },
                    { id = "ENGINE_HESITATION_CHANCE", value = 0.2, aggregation = "min", extraData = {timer = 0, duration = 400, status = 'IDLE', amplitude = 1.0, motorLoad = 0.7, cruiseState = 0} }
                },
                indicators = {
                    { id = db.ENGINE, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_gas_pressure_regulator_failure_stage4_description",
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = stagePartPrices.GAS_PRESSURE_REGULATOR_FAILURE[4],
                effects = {
                    {
                        id = "ENGINE_FAILURE",
                        value = 1.0,
                        aggregation = "boolean_or",
                        extraData = {
                            status = 'IDLE',
                            starter = true,
                            reason = "BREAKDOWN",
                            disableAi = true
                        }
                    }
                },
                indicators = {
                    { id = db.ENGINE, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            }
        }
    },
    GAS_SHUTOFF_SOLENOID_FAILURE = {
        isSelectable = true,
        system = systems.FUEL,
        part = parts.GAS_SHUTOFF_SOLENOID,
        isApplicable = function(vehicle)
            return vehicle.spec_motorized and vehicle.spec_motorized.consumersByFillTypeName and vehicle.spec_motorized.consumersByFillTypeName.METHANE ~= nil
        end,
        causes = { primary = {}, secondary = {"sf"} },
        component = "SOLENOID_VALVE",
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_gas_shutoff_solenoid_failure_stage1_description",
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.GAS_SHUTOFF_SOLENOID_FAILURE,
                repairPrice = stagePartPrices.GAS_SHUTOFF_SOLENOID_FAILURE[1],
                effects = {
                    { id = "ENGINE_HARD_START_MODIFIER", value = 2, aggregation = "max", extraData = { timer = 0, status = 'IDLE'}},
                    { id = "ENGINE_HESITATION_CHANCE", value = 0.3, aggregation = "min", extraData = {timer = 0, duration = 300, status = 'IDLE', amplitude = 0.6, motorLoad = 0.8, cruiseState = 0} }
                }
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_gas_shutoff_solenoid_failure_stage2_description",
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.GAS_SHUTOFF_SOLENOID_FAILURE,
                repairPrice = stagePartPrices.GAS_SHUTOFF_SOLENOID_FAILURE[2],
                effects = {
                    { id = "ENGINE_STALLS_CHANCE", value = 20.0, aggregation = "min" },
                    { id = "ENGINE_HARD_START_MODIFIER", value = 4, aggregation = "max", extraData = { timer = 0, status = 'IDLE'}},
                    { id = "ENGINE_HESITATION_CHANCE", value = 0.2, aggregation = "min", extraData = {timer = 0, duration = 400, status = 'IDLE', amplitude = 1.0, motorLoad = 0.7, cruiseState = 0} }
                },
                indicators = {
                    {  
                        id = db.ENGINE,
                        color = color.WARNING,
                        switchOn = function(vehicle)
                            if vehicle.spec_motorized and vehicle:getIsMotorStarted() and vehicle:getMotorLoadPercentage() > 0.95 then
                                return true
                            end
                            return false
                        end,
                        switchOff = false
                    }
                }
            },
            { 
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_gas_shutoff_solenoid_failure_stage3_description",
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.GAS_SHUTOFF_SOLENOID_FAILURE,
                repairPrice = stagePartPrices.GAS_SHUTOFF_SOLENOID_FAILURE[3],
                effects = {
                    { id = "ENGINE_STALLS_CHANCE", value = 10.0, aggregation = "min" },
                    { id = "ENGINE_HARD_START_MODIFIER", value = 6, aggregation = "max", extraData = { timer = 0, status = 'IDLE'}},
                    { id = "ENGINE_HESITATION_CHANCE", value = 0.15, aggregation = "min", extraData = {timer = 0, duration = 500, status = 'IDLE', amplitude = 1.0, motorLoad = 0.5, cruiseState = 0} }
                },
                indicators = {
                    { id = db.ENGINE, color = color.WARNING, switchOn = true, switchOff = false }
                }
            },
            { 
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_gas_shutoff_solenoid_failure_stage4_description",
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = stagePartPrices.GAS_SHUTOFF_SOLENOID_FAILURE[4],
                effects = { 
                        {
                            id = "ENGINE_FAILURE",
                            value = 1.0,
                            aggregation = "boolean_or",
                            extraData = {
                                status = 'IDLE',
                                starter = true,
                                reason = "BREAKDOWN",
                                disableAi = true
                            }
                        }
                },
                indicators = {
                    { id = db.ENGINE, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            }
        }
    },
    GAS_FILTER_CLOGGING = {
        isSelectable = true,
        system = systems.FUEL,
        part = parts.GAS_FILTER,
        causes = { primary = {}, secondary = {"sf"} },
        component = "FILTER_STRAINER",
        isApplicable = function(vehicle)
            return vehicle.spec_motorized and vehicle.spec_motorized.consumersByFillTypeName and vehicle.spec_motorized.consumersByFillTypeName.METHANE ~= nil
        end,
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_gas_filter_clogging_stage1_description",
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.GAS_FILTER_CLOGGING,
                repairPrice = stagePartPrices.GAS_FILTER_CLOGGING[1],
                effects = {
                        {
                            id = "ENGINE_HESITATION_CHANCE",
                            value = 0.4,
                            aggregation = "min",
                            extraData = {
                                timer = 0,
                                duration = 300,
                                status = 'IDLE',
                                amplitude = 0.6,
                                motorLoad = 0.9,
                                cruiseState = 0
                            }
                        },
                     { id = "ENGINE_TORQUE_MODIFIER", value = -0.03, aggregation = "sum" },
                }
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_gas_filter_clogging_stage2_description",
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.GAS_FILTER_CLOGGING,
                repairPrice = stagePartPrices.GAS_FILTER_CLOGGING[2],
                effects = {
                        {
                            id = "ENGINE_HESITATION_CHANCE",
                            value = 0.3,
                            aggregation = "min",
                            extraData = {
                                timer = 0,
                                duration = 400,
                                status = 'IDLE',
                                amplitude = 0.7,
                                motorLoad = 0.9,
                                cruiseState = 0
                            }
                        },
                     { id = "ENGINE_TORQUE_MODIFIER", value = -0.06, aggregation = "sum" },
                     { id = "ENGINE_STALLS_CHANCE", value = 30.0, aggregation = "min" },
                     { id = "EXHAUST_UNBURNT", value = 0.15, aggregation = "max" },
                }
            },
            { 
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_gas_filter_clogging_stage3_description",
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.GAS_FILTER_CLOGGING,
                repairPrice = stagePartPrices.GAS_FILTER_CLOGGING[3],
                effects = { 
                    { id = "ENGINE_HESITATION_CHANCE", value = 0.2, aggregation = "min", extraData = {timer = 0, duration = 500, status = 'IDLE', amplitude = 0.7, motorLoad = 0.9, cruiseState = 0} },
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.1, aggregation = "sum" },
                    { id = "ENGINE_STALLS_CHANCE", value = 20.0, aggregation = "min" },
                    { id = "EXHAUST_UNBURNT", value = 0.25, aggregation = "max" },
                    { id = "EXHAUST_SOOT", value = 0.15, aggregation = "max" },
                }
            },
            { 
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_gas_filter_clogging_stage4_description",
                detectionChance = 1.0,
                progressMultiplier = 0 * breakdownProgressMultipliers.GAS_FILTER_CLOGGING,
                repairPrice = stagePartPrices.GAS_FILTER_CLOGGING[4],
                effects = {
                        {
                            id = "ENGINE_FAILURE",
                            value = 1.0,
                            aggregation = "boolean_or",
                            extraData = {
                                status = 'IDLE',
                                starter = true,
                                reason = "BREAKDOWN",
                                disableAi = true
                            }
                        }
                }
            }
        }
    },
    GAS_LINE_LEAK = {
        isSelectable = true,
        system = systems.FUEL,
        part = parts.GAS_LINES,
        isApplicable = function(vehicle)
            return vehicle.spec_motorized and vehicle.spec_motorized.consumersByFillTypeName and vehicle.spec_motorized.consumersByFillTypeName.METHANE ~= nil
        end,
        causes = { primary = {}, secondary = {"sf"} },
        component = "O_RING",
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_gas_line_leak_stage1_description",
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.GAS_LINE_LEAK,
                repairPrice = stagePartPrices.GAS_LINE_LEAK[1],
                effects = {
                    { id = "ENGINE_HARD_START_MODIFIER", value = 1, aggregation = "max", extraData = { timer = 0, status = 'IDLE', count = 0}},
                    { id = "GAS_LEAK_NOISE_EFFECT", value = 0.3, aggregation = "max" }
                }
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_gas_line_leak_stage2_description",
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.GAS_LINE_LEAK,
                repairPrice = stagePartPrices.GAS_LINE_LEAK[2],
                effects = {
                    { id = "ENGINE_HESITATION_CHANCE", value = 0.3, aggregation = "min", extraData = {timer = 0, duration = 300, status = 'IDLE', amplitude = 0.6, motorLoad = 0.5, cruiseState = 0} },
                    { id = "ENGINE_HARD_START_MODIFIER", value = 2, aggregation = "max", extraData = { timer = 0, status = 'IDLE', count = 0}},
                    { id = "ENGINE_STALLS_CHANCE", value = 20.0, aggregation = "min" },
                    { id = "EXHAUST_UNBURNT", value = 0.20, aggregation = "max" },
                    { id = "GAS_LEAK_NOISE_EFFECT", value = 0.5, aggregation = "max" }
                }
            },
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_gas_line_leak_stage3_description",
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.GAS_LINE_LEAK,
                repairPrice = stagePartPrices.GAS_LINE_LEAK[3],
                effects = {
                    { id = "ENGINE_HESITATION_CHANCE", value = 0.2, aggregation = "min", extraData = {timer = 0, duration = 500, status = 'IDLE', amplitude = 0.7, motorLoad = 0.5, cruiseState = 0} },
                    { id = "ENGINE_HARD_START_MODIFIER", value = 3, aggregation = "max", extraData = {timer = 0, status = 'IDLE'}},
                    { id = "ENGINE_STALLS_CHANCE", value = 10.0, aggregation = "min" },
                    { id = "EXHAUST_UNBURNT", value = 0.35, aggregation = "max" },
                    { id = "GAS_LEAK_NOISE_EFFECT", value = 0.8, aggregation = "max" }
                }
            },
            {
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_gas_line_leak_stage4_description",
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = stagePartPrices.GAS_LINE_LEAK[4],
                effects = {
                        {
                            id = "ENGINE_FAILURE",
                            value = 1.0,
                            aggregation = "boolean_or",
                            extraData = {
                                status = 'IDLE',
                                starter = true,
                                reason = "BREAKDOWN",
                                disableAi = true
                            }
                        },
                    { id = "GAS_LEAK_NOISE_EFFECT", value = 1.0, aggregation = "max" }
                }
            }
        }
    },
    GAS_INJECTOR_MALFUNCTION = {
        isSelectable = true,
        system = systems.FUEL,
        part = parts.GAS_INJECTORS,
        isApplicable = function(vehicle)
            return vehicle.spec_motorized and vehicle.spec_motorized.consumersByFillTypeName and vehicle.spec_motorized.consumersByFillTypeName.METHANE ~= nil
        end,
        causes = { primary = {}, secondary = {} },
        component = "SOLENOID_VALVE",
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_gas_injector_malfunction_stage1_description",
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.GAS_INJECTOR_MALFUNCTION,
                repairPrice = stagePartPrices.GAS_INJECTOR_MALFUNCTION[1],
                effects = {
                    { id = "IDLE_HUNTING_EFFECT", value = 0.05, aggregation = "max", extraData = { timer = 0, period = 1800} },
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.08, aggregation = "sum" },
                    { id = "FUEL_CONSUMPTION_MODIFIER", value = 0.10, aggregation = "sum" },
                    { id = "EXHAUST_SOOT", value = 0.20, aggregation = "max" },
                    { id = "EXHAUST_UNBURNT", value = 0.15, aggregation = "max" },
                    { id = "ENGINE_HESITATION_CHANCE", value = 0.4, aggregation = "min", extraData = {timer = 0, duration = 300, status = 'IDLE', amplitude = 0.6, motorLoad = 0.9, cruiseState = 0} }
                }
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_gas_injector_malfunction_stage2_description",
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.GAS_INJECTOR_MALFUNCTION,
                repairPrice = stagePartPrices.GAS_INJECTOR_MALFUNCTION[2],
                effects = {
                    { id = "IDLE_HUNTING_EFFECT", value = 0.08, aggregation = "max", extraData = { timer = 0, period = 1500} },
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.20, aggregation = "sum" },
                    { id = "FUEL_CONSUMPTION_MODIFIER", value = 0.25, aggregation = "sum" },
                    { id = "ENGINE_STALLS_CHANCE", value = 30.0, aggregation = "min" },
                    { id = "EXHAUST_SOOT", value = 0.40, aggregation = "max" },
                    { id = "EXHAUST_UNBURNT", value = 0.30, aggregation = "max" },
                    { id = "ENGINE_HESITATION_CHANCE", value = 0.3, aggregation = "min", extraData = {timer = 0, duration = 400, status = 'IDLE', amplitude = 0.8, motorLoad = 0.8, cruiseState = 0} }
                },
                indicators = {
                    { id = db.ENGINE, color = color.WARNING, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_gas_injector_malfunction_stage3_description",
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.GAS_INJECTOR_MALFUNCTION,
                repairPrice = stagePartPrices.GAS_INJECTOR_MALFUNCTION[3],
                effects = {
                    { id = "IDLE_HUNTING_EFFECT", value = 0.10, aggregation = "max", extraData = { timer = 0, period = 1800} },
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.35, aggregation = "sum" },
                    { id = "FUEL_CONSUMPTION_MODIFIER", value = 0.50, aggregation = "sum" },
                    { id = "ENGINE_HARD_START_MODIFIER", value = 6, aggregation = "max", extraData = { timer = 0, status = 'IDLE'}},
                    { id = "EXHAUST_SOOT", value = 0.70, aggregation = "max" },
                    { id = "EXHAUST_UNBURNT", value = 0.50, aggregation = "max" },
                    { id = "ENGINE_HESITATION_CHANCE", value = 0.2, aggregation = "min", extraData = {timer = 0, duration = 500, status = 'IDLE', amplitude = 1.0, motorLoad = 0.7, cruiseState = 0} }
                },
                indicators = {
                    { id = db.ENGINE, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_gas_injector_malfunction_stage4_description",
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = stagePartPrices.GAS_INJECTOR_MALFUNCTION[4],
                effects = {
                        {
                            id = "ENGINE_FAILURE",
                            value = 1.0,
                            aggregation = "boolean_or",
                            extraData = {
                                status = 'IDLE',
                                starter = true,
                                reason = "BREAKDOWN",
                                disableAi = true
                            }
                        }
                },
                indicators = {
                    { id = db.ENGINE, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            }
        }
    },
    ADBLUE_PUMP_FAILURE = {
        isSelectable = true,
        system = systems.FUEL,
        part = parts.ADBLUE_PUMP,
        isApplicable = function(vehicle)
            return vehicle.spec_motorized and vehicle.spec_motorized.consumersByFillTypeName and vehicle.spec_motorized.consumersByFillTypeName.DEF ~= nil
        end,
        causes = { primary = {}, secondary = {"sf"} },
        component = "ADBLUE_MODULE_SERVICE_PROXY",
        stages = {
{
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_adblue_pump_failure_stage1_description",
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.ADBLUE_PUMP_FAILURE,
                repairPrice = stagePartPrices.ADBLUE_PUMP_FAILURE[1],
                effects = { { id = "SCR_DOSING_FAILURE", value = 1, aggregation = "boolean_or" } },
                indicators = {
                    { id = db.ENGINE, color = color.WARNING, switchOn = true, switchOff = false }
                }
            }
        }
    },
    ADBLUE_DOSER_FAILURE = {
        isSelectable = true,
        system = systems.FUEL,
        part = parts.ADBLUE_DOSER,
        isApplicable = function(vehicle)
            return vehicle.spec_motorized and vehicle.spec_motorized.consumersByFillTypeName and vehicle.spec_motorized.consumersByFillTypeName.DEF ~= nil
        end,
        causes = { primary = {}, secondary = {} },
        component = "ADBLUE_DOSER_SERVICE_PROXY",
        stages = {
{
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_adblue_doser_failure_stage1_description",
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.ADBLUE_DOSER_FAILURE,
                repairPrice = stagePartPrices.ADBLUE_DOSER_FAILURE[1],
                effects = { { id = "SCR_DOSING_FAILURE", value = 1, aggregation = "boolean_or" } },
                indicators = {
                    { id = db.ENGINE, color = color.WARNING, switchOn = true, switchOff = false }
                }
            }
        }
    },
    ADBLUE_FILTER_CLOGGING = {
        isSelectable = true,
        system = systems.FUEL,
        part = parts.ADBLUE_FILTER,
        isApplicable = isAdBlueApplicable,
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_adblue_filter_clogging_stage1_description",
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = stagePartPrices.ADBLUE_FILTER_CLOGGING[1],
                effects = {}
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_adblue_filter_clogging_stage2_description",
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = stagePartPrices.ADBLUE_FILTER_CLOGGING[2],
                effects = {},
                indicators = {
                    { id = db.ENGINE, color = color.WARNING, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_adblue_filter_clogging_stage3_description",
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = stagePartPrices.ADBLUE_FILTER_CLOGGING[3],
                effects = {
                    { id = "SCR_DOSING_FAILURE", value = 1, aggregation = "boolean_or" }
                },
                indicators = {
                    { id = db.ENGINE, color = color.WARNING, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_adblue_filter_clogging_stage4_description",
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = stagePartPrices.ADBLUE_FILTER_CLOGGING[4],
                effects = {
                    { id = "SCR_DOSING_FAILURE", value = 1, aggregation = "boolean_or" }
                },
                indicators = {
                    { id = db.ENGINE, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            }
        }
    },

    NOX_SENSOR_FAILURE = {
        isSelectable = true,
        system = systems.FUEL,
        part = parts.NOX_SENSOR,
        isApplicable = function(vehicle)
            return vehicle.spec_motorized and vehicle.spec_motorized.consumersByFillTypeName and vehicle.spec_motorized.consumersByFillTypeName.DEF ~= nil
        end,
        causes = { primary = {"sf"}, secondary = {} },
        component = "NOX_TRANSDUCER_PROXY",
        stages = {
{
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_nox_sensor_failure_stage1_description",
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.NOX_SENSOR_FAILURE,
                repairPrice = stagePartPrices.NOX_SENSOR_FAILURE[1],
                effects = { { id = "NOX_MONITORING_FAILURE", value = 1, aggregation = "boolean_or" } },
                indicators = {
                    { id = db.ENGINE, color = color.WARNING, switchOn = true, switchOff = false }
                }
            }
        }
    },
    PARTICULATE_FILTER_FAILURE = {
        isSelectable = true,
        system = systems.FUEL,
        part = parts.PARTICULATE_FILTER,
        causes = { primary = {}, secondary = {} },
        component = "DPF_FILTER_STRAINER_PROXY",
        branches = 2,
        isApplicable = function(vehicle)
            return vehicle.spec_RealisticMechanicalSystems.hasParticulateFilter == true
        end,
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_particulate_filter_failure_branch1_stage1_description",
                branchDescriptions = { "rms_breakdowns_particulate_filter_failure_branch1_stage1_description", "rms_breakdowns_particulate_filter_failure_branch2_stage1_description" },
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.PARTICULATE_FILTER_FAILURE,
                repairPrice = stagePartPrices.PARTICULATE_FILTER_FAILURE[1],
                effects = {
                    { id = "EXHAUST_SOOT", value = 0.20, aggregation = "max", branch = 1 }
                }
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_particulate_filter_failure_branch1_stage2_description",
                branchDescriptions = { "rms_breakdowns_particulate_filter_failure_branch1_stage2_description", "rms_breakdowns_particulate_filter_failure_branch2_stage2_description" },
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.PARTICULATE_FILTER_FAILURE,
                repairPrice = stagePartPrices.PARTICULATE_FILTER_FAILURE[2],
                effects = {
                    { id = "EXHAUST_SOOT", value = 0.40, aggregation = "max", branch = 1 }
                },
                indicators = { { id = db.DPF, color = color.WARNING, switchOn = true, switchOff = false } }
            },
            { 
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_particulate_filter_failure_branch1_stage3_description",
                branchDescriptions = { "rms_breakdowns_particulate_filter_failure_branch1_stage3_description", "rms_breakdowns_particulate_filter_failure_branch2_stage3_description" },
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.PARTICULATE_FILTER_FAILURE,
                repairPrice = stagePartPrices.PARTICULATE_FILTER_FAILURE[3],
                effects = {
                    { id = "EXHAUST_SOOT", value = 0.70, aggregation = "max", branch = 1 },
                    { id = "PARTICULATE_FILTER_BLOCKED", value = 1, aggregation = "boolean_or", branch = 2 }
                },
                indicators = { { id = db.DPF, color = color.WARNING, switchOn = true, switchOff = false } }
            },
            { 
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_particulate_filter_failure_branch1_stage4_description",
                branchDescriptions = { "rms_breakdowns_particulate_filter_failure_branch1_stage4_description", "rms_breakdowns_particulate_filter_failure_branch2_stage4_description" },
                detectionChance = 1.0,
                progressMultiplier = 0 * breakdownProgressMultipliers.PARTICULATE_FILTER_FAILURE,
                repairPrice = stagePartPrices.PARTICULATE_FILTER_FAILURE[4],
                effects = {
                    { id = "EXHAUST_SOOT", value = 0.70, aggregation = "max", branch = 1 },
                    { id = "PARTICULATE_FILTER_BLOCKED", value = 1, aggregation = "boolean_or", branch = 2 }
                },
                indicators = { { id = db.DPF, color = color.CRITICAL, switchOn = true, switchOff = false } }
            }
        }
    },

    PARTICULATE_FILTER_SOOT_OVERLOAD = {
        isSelectable = false,
        system = systems.FUEL,
        part = parts.PARTICULATE_FILTER,
        isApplicable = function(vehicle)
            return vehicle.spec_RealisticMechanicalSystems.hasParticulateFilter == true
        end,
        stages = {
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_particulate_filter_soot_overload_stage1_description",
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = stagePartPrices.PARTICULATE_FILTER_SOOT_OVERLOAD[1],
                effects = {},
                indicators = {
                    { id = db.DPF, color = color.WARNING, switchOn = true, switchOff = false },
                    { id = db.ENGINE, color = color.WARNING, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_particulate_filter_soot_overload_stage2_description",
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = stagePartPrices.PARTICULATE_FILTER_SOOT_OVERLOAD[2],
                effects = {},
                indicators = {
                    { id = db.DPF, color = color.CRITICAL, switchOn = true, switchOff = false },
                    { id = db.ENGINE, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            }
        }
    },

    -- traction battery
    TRACTION_BATTERY_CELL_FAULT = {
        isSelectable = true,
        system = systems.FUEL,
        part = parts.TRACTION_BATTERY,
        isApplicable = function(vehicle)
            return getIsElectricVehicle(vehicle)
        end,
        causes = { primary = {"ddf", "bhf"}, secondary = {"hdf"} },
        component = "TRACTION_BATTERY",
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_traction_battery_cell_fault_stage1_description",
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.TRACTION_BATTERY_CELL_FAULT,
                repairPrice = stagePartPrices.TRACTION_BATTERY_CELL_FAULT[1],
                effects = {
                    { id = "TRACTION_BATTERY_CAPACITY_MODIFIER", value = -0.05, aggregation = "sum" }
                }
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_traction_battery_cell_fault_stage2_description",
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.TRACTION_BATTERY_CELL_FAULT,
                repairPrice = stagePartPrices.TRACTION_BATTERY_CELL_FAULT[2],
                effects = {
                    { id = "TRACTION_BATTERY_CAPACITY_MODIFIER", value = -0.12, aggregation = "sum" },
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.10, aggregation = "sum" }
                },
                indicators = {
                    { id = db.TRACTION_BATTERY, color = color.WARNING, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_traction_battery_cell_fault_stage3_description",
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.TRACTION_BATTERY_CELL_FAULT,
                repairPrice = stagePartPrices.TRACTION_BATTERY_CELL_FAULT[3],
                effects = {
                    { id = "TRACTION_BATTERY_CAPACITY_MODIFIER", value = -0.25, aggregation = "sum" },
                    { id = "ENGINE_TORQUE_MODIFIER", value = -0.25, aggregation = "sum" },
                    { id = "ENGINE_STALLS_CHANCE", value = 15.0, aggregation = "min" }
                },
                indicators = {
                    { id = db.TRACTION_BATTERY, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_traction_battery_cell_fault_stage4_description",
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = stagePartPrices.TRACTION_BATTERY_CELL_FAULT[4],
                effects = {
                    { id = "TRACTION_BATTERY_CAPACITY_MODIFIER", value = -0.25, aggregation = "sum" },
                        {
                            id = "ENGINE_FAILURE",
                            value = 1.0,
                            aggregation = "boolean_or",
                            extraData = {
                                status = 'IDLE',
                                starter = false,
                                reason = "BREAKDOWN",
                                disableAi = true
                            }
                        }
                },
                indicators = {
                    { id = db.TRACTION_BATTERY, color = color.CRITICAL, switchOn = true, switchOff = false },
                    { id = db.WARNING, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            }
        }
    },
    HV_CONTACTOR_FAILURE = {
        isSelectable = true,
        system = systems.FUEL,
        part = parts.HV_CONTACTOR,
        isApplicable = function(vehicle)
            return getIsElectricVehicle(vehicle)
        end,
        causes = { primary = {"hdf"}, secondary = {} },
        component = "CIRCUIT_BREAKER",
        stages = {
            {
                severity = "rms_breakdowns_severity_minor",
                description = "rms_breakdowns_hv_contactor_failure_stage1_description",
                detectionChance = 1.0,
                progressMultiplier = 2.0 * breakdownProgressMultipliers.HV_CONTACTOR_FAILURE,
                repairPrice = stagePartPrices.HV_CONTACTOR_FAILURE[1],
                effects = {
                    { id = "ENGINE_STALLS_CHANCE", value = 60.0, aggregation = "min" }
                }
            },
            {
                severity = "rms_breakdowns_severity_moderate",
                description = "rms_breakdowns_hv_contactor_failure_stage2_description",
                detectionChance = 1.0,
                progressMultiplier = 1.0 * breakdownProgressMultipliers.HV_CONTACTOR_FAILURE,
                repairPrice = stagePartPrices.HV_CONTACTOR_FAILURE[2],
                effects = {
                    { id = "ENGINE_STALLS_CHANCE", value = 30.0, aggregation = "min" }
                },
                indicators = {
                    { id = db.TRACTION_BATTERY, color = color.WARNING, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_major",
                description = "rms_breakdowns_hv_contactor_failure_stage3_description",
                detectionChance = 1.0,
                progressMultiplier = 0.5 * breakdownProgressMultipliers.HV_CONTACTOR_FAILURE,
                repairPrice = stagePartPrices.HV_CONTACTOR_FAILURE[3],
                effects = {
                    { id = "ENGINE_STALLS_CHANCE", value = 10.0, aggregation = "min" }
                },
                indicators = {
                    { id = db.TRACTION_BATTERY, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            },
            {
                severity = "rms_breakdowns_severity_critical",
                description = "rms_breakdowns_hv_contactor_failure_stage4_description",
                detectionChance = 1.0,
                progressMultiplier = 0,
                repairPrice = stagePartPrices.HV_CONTACTOR_FAILURE[4],
                effects = {
                        {
                            id = "ENGINE_FAILURE",
                            value = 1.0,
                            aggregation = "boolean_or",
                            extraData = {
                                status = 'IDLE',
                                starter = false,
                                reason = "BREAKDOWN",
                                disableAi = true
                            }
                        }
                },
                indicators = {
                    { id = db.TRACTION_BATTERY, color = color.CRITICAL, switchOn = true, switchOff = false }
                }
            }
        }
    },
}

---Wraps every applicability test so a disabled system never breaks down
local function wrapBreakdownApplicabilityByEnabledSystem()
    for _, entry in pairs(RMS_Breakdowns.BreakdownRegistry or {}) do
        if type(entry) == "table" and entry.system ~= nil and type(entry.isApplicable) == "function" then
            local originalIsApplicable = entry.isApplicable

            entry.isApplicable = function(vehicle)
                if vehicle == nil or vehicle.spec_RealisticMechanicalSystems == nil then
                    return false
                end

                local spec = vehicle.spec_RealisticMechanicalSystems
                local systemKey = RMS_Utils.getSystemKey(RealisticMechanicalSystems.SYSTEMS, entry.system)

                if systemKey == "" and type(entry.system) == "string" then
                    systemKey = string.lower(entry.system)
                end

                if systemKey ~= nil and systemKey ~= "" then
                    local systemData = spec.systems ~= nil and spec.systems[systemKey] or nil
                    if type(systemData) == "table" and systemData.enabled == false then
                        return false
                    end
                end

                return originalIsApplicable(vehicle) == true
            end
        end
    end
end

wrapBreakdownApplicabilityByEnabledSystem()






